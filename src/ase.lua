--[[
Module to handle import/export of Aseprite files
--]]

local Aseprite = {}

---@param workspace Workspace
function Aseprite.export(workspace)
    local frames = {} ---@type love.ImageData[]

    local maxWidth, maxHeight = 0, 0

    -- get the size of a rectangle that can fit all quads
    -- accounting for center position
    for _, quad in ipairs(workspace.quads) do
        local newWidth = 2 * math.abs(quad.cx - quad.w/2) + quad.w
        local newHeight = 2 * math.abs(quad.cy - quad.h/2) + quad.h
        
        maxWidth = math.max(maxWidth, newWidth)
        maxHeight = math.max(maxHeight, newHeight)
    end

    -- test: export spritesheet
    local imageTest = love.image.newImageData(maxWidth * #workspace.quads, maxHeight)

    for i, quad in ipairs(workspace.quads) do
        local x = (i-1) * maxWidth
        local y = 0

        imageTest:paste(quad.image,
            math.floor(x + maxWidth/2 - quad.cx),
            math.floor(y + maxHeight/2 - quad.cy),
            0, 0, quad.w, quad.h
        )
    end

    return imageTest:encode("png"):getString()
end

return Aseprite