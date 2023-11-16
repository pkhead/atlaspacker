local util = require("util")

---@class ImageQuad
---@field x integer
---@field y integer
---@field w integer
---@field h integer
---@field name string
---@field resScale number
---@field cx integer
---@field cy integer
---@field image love.ImageData
---@field texture love.Image?

---@class Animation
---@field name string
---@field frameLen integer
---@field doLoop boolean
---@field loopPoint integer?
---@field frames integer[]

---@class Workspace
---@field private dragX number
---@field private dragY number
---@field private dragR number
---@field private dragB number
---@field private dragW number
---@field private dragH number
---@field private quadDragOffsets table
---@field private mouseStartX number
---@field private mouseStartY number
local Workspace = {}
Workspace.__index = Workspace

---@param w integer
---@param h integer
function Workspace.new(w, h)
    ---@class Workspace
    local self = setmetatable({}, Workspace)

    self.width = w
    self.height = h
    self.quads = {} ---@type ImageQuad[]
    self.selectedQuads = {} ---@type integer[]
    self.animations = {} ---@type Animation[]
    self.isPanning = false
    self.isSelecting = false
    self.isDragging = false
    
    self.viewX = -(love.graphics.getWidth() - self.width) / 2
    self.viewY = -(love.graphics.getHeight() - self.height) / 2
    self.viewZoom = 1

    return self
end

function Workspace:addImage(x, y, name, img)
    local newId = 0
    while self.quads[newId] do
        newId=newId+1
    end

    self.quads[newId] = {
        x = x,
        y = y,
        w = img:getWidth(),
        h = img:getHeight(),
        name = name,
        resScale = 1,
        cx = math.floor(img:getWidth() / 2),
        cy = math.floor(img:getHeight() / 2),

        image = img,
        texture = love.graphics.newImage(img)
    }
end

function Workspace:getSelectionBounds()
    local minX = math.huge
    local minY = math.huge
    local maxX = -math.huge
    local maxY = -math.huge

    for _, i in ipairs(self.selectedQuads) do
        local quad = self.quads[i]

        minX = math.min(minX, quad.x)
        maxX = math.max(maxX, quad.x+quad.w)
        minY = math.min(minY, quad.y)
        maxY = math.max(maxY, quad.y+quad.h)
    end

    return minX, minY, maxX, maxY
end

function Workspace:screenToWorkspace(x, y)
    local imViewport = imgui.GetMainViewport()
    return
        (x - imViewport.WorkPos.x) / self.viewZoom + self.viewX,
        (y - imViewport.WorkPos.y) / self.viewZoom + self.viewY
end

-- basically an auto-crop
function Workspace:resizeToExtents()
    -- calculate extents
    local minX = math.huge
    local minY = math.huge
    local maxX = -math.huge
    local maxY = -math.huge

    for _, quad in pairs(self.quads) do
        minX = math.min(minX, quad.x)
        maxX = math.max(maxX, quad.x+quad.w)
        minY = math.min(minY, quad.y)
        maxY = math.max(maxY, quad.y+quad.h)
    end

    -- crop
    for _, quad in pairs(self.quads) do
        quad.x = math.floor(quad.x - minX)
        quad.y = math.floor(quad.y - minY)
    end
    self.width = maxX - minX
    self.height = maxY - minY
end

-- autogrid thing
function Workspace:formatSelection(cols)
    local minX, minY = self:getSelectionBounds()

    -- sort images by their id
    local sorted = {}
    for i, v in pairs(self.selectedQuads) do
        sorted[i] = v
    end
    table.sort(sorted)

    local x = minX
    local y = minY
    local col = 0
    local rowHeight = 0

    for _, i in ipairs(sorted) do
        local quad = self.quads[i]
        quad.x = x
        quad.y = y
        rowHeight = math.max(rowHeight, quad.h)
        col=col+1

        if col >= cols then
            x = minX
            y = y + rowHeight
            rowHeight = 0
            col = 0
        else
            x = x + quad.w
        end
    end
end

function Workspace:setId(startId)
    local id = startId
    local sorted = util.table_copy(self.selectedQuads)
    table.sort(sorted)

    -- reconstruct the selectedQuads list as the IDs will change
    self.selectedQuads = {}
    
    for _, i in ipairs(sorted) do
        self.quads[id], self.quads[i] = self.quads[i], self.quads[id]
        table.insert(self.selectedQuads, id)
        id=id+1
    end
end

function Workspace:mousepressed(x, y, btn)
    if btn == 1 then
        self.mouseStartX, self.mouseStartY = self:screenToWorkspace(x, y)
    elseif btn == 3 then
        self.isPanning = true
    end
end

--- trim excess whitespace on quad,
--- thus recentering the quad
---@param quad ImageQuad
local function trimQuad(quad)
    -- get image bounds
    local minX = math.huge
    local maxX = 0
    local minY = nil
    local maxY = 0

    for y=0, quad.image:getHeight() - 1 do
        for x=0, quad.image:getWidth() - 1 do
            local r, g, b, a = quad.image:getPixel(x, y)
            if a > 0 then
                if minY == nil then
                    minY = y
                end

                maxY = y
                
                minX = math.min(minX, x)
                maxX = math.max(maxX, x)
            end
        end
    end

    -- if image is completely transparent, don't do anything
    if minY == nil then
        return
    end

    -- one pixel border of transparent space
    minX = math.max(0, minX - 1)
    minY = math.max(0, minY - 1)
    maxX = math.min(quad.image:getWidth() - 1, maxX + 1)
    maxY = math.min(quad.image:getHeight() - 1, maxY + 1)

    -- create cropped image
    local srcImage = quad.image

    local croppedW = math.floor(maxX - minX)
    local croppedH = math.floor(maxY - minY)
    local cropped = love.image.newImageData(croppedW, croppedH)
    cropped:paste(srcImage, 0, 0, minX, minY, croppedW, croppedH)

    -- realign center
    local ogX = quad.x
    local ogY = quad.y
    
    quad.image = cropped
    quad.x = ogX + minX
    quad.y = ogY + minY
    quad.cx = math.floor(quad.cx - minX)
    quad.cy = math.floor(quad.cy - minY)
    quad.texture = love.graphics.newImage(cropped)
    quad.w = croppedW
    quad.h = croppedH
end

function Workspace:trimSelection()
    for _, index in ipairs(self.selectedQuads) do
        trimQuad(self.quads[index])
    end
end

function Workspace:mousemoved(x, y, dx, dy)
    local mx, my = self:screenToWorkspace(x, y)
    
    if self.isPanning then
        self.viewX = self.viewX - dx / self.viewZoom
        self.viewY = self.viewY - dy / self.viewZoom
    end

    if self.isDragging then
        -- get selection bounds
        self.dragX = self.dragX + dx / self.viewZoom
        self.dragY = self.dragY + dy / self.viewZoom

        local snapX = self.dragX
        local snapY = self.dragY

        -- snap to edges of canvas
        local snapDist = 5 / self.viewZoom
        if math.abs(snapX) < snapDist then
            snapX = 0
        end

        if math.abs(snapY) < snapDist then
            snapY = 0
        end

        -- snap to other quads
        for i, quad in pairs(self.quads) do
            if not util.table_find(self.selectedQuads, i) then
                -- left edge of other
                if math.abs(quad.x - (self.dragX + self.dragW)) < snapDist then
                    snapX = quad.x - self.dragW
                end

                -- right edge of other
                if math.abs(quad.x + quad.w - self.dragX) < snapDist then
                    snapX = quad.x + quad.w
                end

                -- bottom edge of other
                if math.abs(quad.y + quad.h - self.dragY) < snapDist then
                    snapY = quad.y + quad.h
                end

                -- top edge of other
                if math.abs(quad.y - (self.dragY + self.dragH)) < snapDist then
                    snapY = quad.y - self.dragH
                end
            end
        end

        -- move quads
        for i, idx in ipairs(self.selectedQuads) do
            local quad = self.quads[idx]

            quad.x = math.floor(self.quadDragOffsets[i][1] + snapX + 0.5)
            quad.y = math.floor(self.quadDragOffsets[i][2] + snapY + 0.5)
        end
    end

    if self.isSelecting then
        local minX = math.min(mx, self.mouseStartX)
        local maxX = math.max(mx, self.mouseStartX)
        local minY = math.min(my, self.mouseStartY)
        local maxY = math.max(my, self.mouseStartY)

        self.selectedQuads = {}

        for i, quad in pairs(self.quads) do
            if  maxX > quad.x and
                minX < quad.x + quad.w and
                maxY > quad.y and
                minY < quad.y + quad.h
            then
                table.insert(self.selectedQuads, i)
            end
        end
    end

    if love.mouse.isDown(1) and self.mouseStartX and not self.isMouseMoving then
        local mdx = (mx - self.mouseStartX) * self.viewZoom
        local mdy = (my - self.mouseStartY) * self.viewZoom

        -- if the mouse moved 16 pixels away from where it started
        if mdx * mdx + mdy * mdy > 8*8 then
            self.isMouseMoving = true

            -- if user is dragging over empty area, begin box select
            -- if user is dragging over quads, drag selected quads
            local foundQuad = nil
            for i, quad in pairs(self.quads) do
                if  self.mouseStartX > quad.x and
                    self.mouseStartY > quad.y and
                    self.mouseStartX < quad.x + quad.w and
                    self.mouseStartY < quad.y + quad.h
                then
                    foundQuad = i
                    break
                end
            end

            if foundQuad then
                -- if there is less than two selected quads,
                -- drag the quad the user is hovering over
                if self.selectedQuads[2] == nil then
                    self.selectedQuads = {foundQuad}
                end

                local dragR, dragB
                self.dragX, self.dragY, self.dragR, self.dragB = self:getSelectionBounds()
                self.dragW = self.dragR - self.dragX
                self.dragH = self.dragB - self.dragY
                self.quadDragOffsets = {}

                for i, idx in ipairs(self.selectedQuads) do
                    local quad = self.quads[idx]
                    self.quadDragOffsets[i] = {quad.x - self.dragX, quad.y - self.dragY}
                end

                self.isDragging = true
            else
                self.isSelecting = true
            end
        end
    end
end

function Workspace:mousereleased(x, y, btn)
    local wx, wy = self:screenToWorkspace(x, y)

    if btn == 1 then
        -- mouse click, selection
        if not self.isMouseMoving then
            local foundQuad = false

            if not (love.keyboard.isDown("lshift") or love.keyboard.isDown("lctrl")) then
                self.selectedQuads = {}
            end
            
            for i, quad in pairs(self.quads) do
                if util.table_find(self.selectedQuads, i) == nil and
                    wx > quad.x and
                    wy > quad.y and
                    wx < quad.x + quad.w and
                    wy < quad.y + quad.h
                then
                    table.insert(self.selectedQuads, i)
                    foundQuad = true
                    break
                end
            end
        end

        self.isSelecting = false
        self.isDragging = false
        self.isMouseMoving = false
        self.mouseStartX = nil
        self.mouseStartY = nil
    elseif btn == 3 then
        self.isPanning = false
    end
end

function Workspace:zoom(factor, mx, my)
    self.viewZoom = self.viewZoom * factor
    self.viewX = -(mx - self.viewX) / factor + mx
    self.viewY = -(my - self.viewY) / factor + my
end

local transparencyShader = love.graphics.newShader([[
vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 tex_color = Texel(tex, texture_coords);
    return color * tex_color.a;
}
]])

function Workspace:draw(checkerboard)
    local imViewport = imgui.GetMainViewport()
    local ox, oy = imViewport.WorkPos.x, imViewport.WorkPos.y
    local viewW, viewH = imViewport.WorkSize.x / self.viewZoom, imViewport.WorkSize.y / self.viewZoom
    
    --local screenW, screenH = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.push()
    love.graphics.translate(ox, oy)
    
    love.graphics.setScissor(ox - self.viewX * self.viewZoom, oy - self.viewY * self.viewZoom, self.width * self.viewZoom, self.height * self.viewZoom)
    love.graphics.draw(checkerboard.tex, checkerboard.quad, 0, 0, 0, checkerboard.size, checkerboard.size)

    love.graphics.push()

    love.graphics.scale(self.viewZoom, self.viewZoom)
    love.graphics.translate(-self.viewX, -self.viewY)

    -- create stencil from spaces where quads overlap
    love.graphics.stencil(function()
        for i, quad in pairs(self.quads) do
            if util.aabbIntersects(quad.x, quad.y, quad.w, quad.h, self.viewX, self.viewY, viewW, viewH) then
                love.graphics.rectangle("fill", quad.x, quad.y, quad.w, quad.h)
            end
        end
    end, "increment")

    -- draw quad textures
    

    for i, quad in pairs(self.quads) do
        if util.aabbIntersects(quad.x, quad.y, quad.w, quad.h, self.viewX, self.viewY, viewW, viewH) then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(quad.texture, quad.x, quad.y)

            local cx = quad.x + quad.cx
            local cy = quad.y + quad.cy
            
            -- draw + (black outline and white innards)
            for i=1, 2 do
                local w

                if i == 1 then
                    w = 7 / self.viewZoom
                    love.graphics.setLineWidth(4 / self.viewZoom)
                    love.graphics.setColor(0, 0, 0)
                elseif i == 2 then
                    w = 5 / self.viewZoom
                    love.graphics.setLineWidth(1 / self.viewZoom)
                    love.graphics.setColor(1, 1, 1)
                end

                love.graphics.line(
                    cx, cy - w,
                    cx, cy + w
                )
    
                love.graphics.line(
                    cx - w, cy,
                    cx + w, cy
                )
                
            end
        end
    end

    love.graphics.setLineWidth(1)
    
    -- draw red areas where pixels from frames overlap
    love.graphics.setStencilTest("greater", 1)
    -- the math.sin stuff makes the red highlight oscillate
    love.graphics.setColor(1, 0.1, 0, (math.sin(2 * math.pi * love.timer.getTime()) + 1) / 2)
    love.graphics.setShader(transparencyShader)

    for i, quad in pairs(self.quads) do
        if util.aabbIntersects(quad.x, quad.y, quad.w, quad.h, self.viewX, self.viewY, viewW, viewH) then
            love.graphics.draw(quad.texture, quad.x, quad.y)
        end
    end
    
    love.graphics.setStencilTest()
    love.graphics.setShader()
    love.graphics.setScissor()
    
    love.graphics.pop()

    -- draw quad outlines/info
    for i, quad in pairs(self.quads) do
        -- draw outline
        if util.table_find(self.selectedQuads, i) then
            love.graphics.setColor(0, 0, 1, 0.5)
        else
            love.graphics.setColor(0, 0, 0, 0.5)
        end

        local quadX = math.floor((quad.x - self.viewX) * self.viewZoom)
        local quadY = math.floor((quad.y - self.viewY) * self.viewZoom)

        love.graphics.rectangle("line",
            quadX,
            quadY,
            quad.w * self.viewZoom,
            quad.h * self.viewZoom
        )

        -- draw text
        local label = ("%i: %s"):format(i, quad.name)
        love.graphics.rectangle("fill", quadX, quadY, App.font:getWidth(label), 16)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(label, quadX, quadY)
    end

    local mx, my = self:screenToWorkspace(love.mouse.getX(), love.mouse.getY())

    if self.isSelecting then
        local minX = math.min(mx, self.mouseStartX)
        local maxX = math.max(mx, self.mouseStartX)
        local minY = math.min(my, self.mouseStartY)
        local maxY = math.max(my, self.mouseStartY)

        local x, y = minX, minY
        local w, h = maxX - minX, maxY - minY
        x = (x - self.viewX) * self.viewZoom
        y = (y - self.viewY) * self.viewZoom
        w = w * self.viewZoom
        h = h * self.viewZoom
        
        love.graphics.setColor(0, 0, 1, 0.2)
        love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(0, 0, 1)
        love.graphics.rectangle("line", x, y, w, h)
    end
end

return Workspace