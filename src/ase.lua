--[[
Module to handle import/export of Aseprite files
--]]

local Aseprite = {}

---@param format string
---@param ... boolean|string|number
---@return string
local function strpack(format, ...)
    return love.data.pack("string", format, ...) --[[@as string]]
end

---@class Queue
local Queue = {}
Queue.__index = Queue

---@return Queue
function Queue.new()
    return setmetatable({}, Queue)
end

function Queue:push(v)
    table.insert(self, v)
end

function Queue:concat()
    return table.concat(self)
end

---@param workspace Workspace
function Aseprite.export(workspace)
    local frames = {} ---@type love.ImageData[]

    local maxWidth, maxHeight = 0, 0

    -- get the size of a rectangle that can fit all quads
    -- accounting for center position
    local numQuads = 0
    for _, quad in pairs(workspace.quads) do
        local newWidth = 2 * math.abs(quad.cx - quad.w/2) + quad.w
        local newHeight = 2 * math.abs(quad.cy - quad.h/2) + quad.h
        
        maxWidth = math.max(maxWidth, newWidth)
        maxHeight = math.max(maxHeight, newHeight)

        numQuads=numQuads+1
    end

    local aseOut = Queue.new()

    -- file header (without file size)
    aseOut:push(strpack("<I2", 0xA5E0)) -- magic number
    aseOut:push(strpack("<I2", numQuads)) -- frame count
    aseOut:push(strpack("<I2I2", maxWidth, maxHeight)) -- frame size
    aseOut:push(strpack("<I2", 32)) -- RGBA
    aseOut:push(strpack("<I4", 0)) -- no layer opacity
    aseOut:push(strpack("<I2", 0)) -- deprecated
    aseOut:push(strpack("<I4I4I1", 0, 0, 0)) -- unused values
    aseOut:push(strpack("<c3", string.rep("\0", 3))) -- unused
    aseOut:push(strpack("<I2", 0)) -- number of colors
    aseOut:push(string.rep("\0", 94)) -- reserved

    -- frame data
    local quadIndex = 1
    for _, quad in pairs(workspace.quads) do
        local frameOut = Queue.new()

        frameOut:push(strpack("<I2", 0xF1FA)) -- magic number

        -- spec requires that first frame stores a Layer Chunk
        -- which means first chunk has 2 chunks, not 1
        if quadIndex == 1 then
            frameOut:push(strpack("<I2", 2))
        else
            frameOut:push(strpack("<I2", 1))
        end

        frameOut:push(strpack("<I2", 1000)) -- frame duration in ms
        frameOut:push(string.rep("\0", 6)) -- reserved

        -- layer chunk in first frame
        if quadIndex == 1 then
            local chunkQueue = Queue.new()

            chunkQueue:push(strpack("<I2I2I2I2I2I2I1c3s2",
                3,          -- WORD     flags: visible and editable
                0,          -- WORD     layer type
                0,          -- WORD     layer child level,
                0,          -- WORD     unused
                0,          -- WORD  
                0,          -- WORD     blend mode (normal)
                0,          -- BYTE     opacity (marked unused)
                "\0\0\0",   -- BYTE[3]  reserved
                "Layer 1"     -- STRING   layer name
            ))

            -- commit chunk
            local chunkData = chunkQueue:concat()
            frameOut:push(strpack("<I4", string.len(chunkData) + 6))
            frameOut:push(strpack("<I2", 0x2004))
            frameOut:push(chunkData)
        end

        -- cel chunk
        do
            local chunkQueue = Queue.new()
            chunkQueue:push(strpack("<I2I2I2I1I2c7 I2I2",
                0,                  -- WORD: layer index
                0,                  -- WORD: x position
                0,                  -- WORD: y position
                255,                -- BYTE: opacity
                0,                  -- WORD: cel type (raw cell)
                string.rep("\0", 7),-- reserved
    
                maxWidth,           -- WORD: width
                maxHeight           -- WORD: height
            ))

            -- write pixel data into chunk queue
            local ox = math.floor(maxWidth/2 - quad.cx)
            local oy = math.floor(maxHeight/2 - quad.cy)
            local w = quad.image:getWidth()
            local h = quad.image:getHeight()
            
            for y=0, maxHeight-1 do
                for x=0, maxWidth-1 do
                    local mx, my = x - ox, y - oy
                    local r, g, b, a = 0, 0, 0, 0

                    if mx >= 0 and my >= 0 and mx < w and my < h then
                        r, g, b, a = quad.image:getPixel(mx, my)
                    end

                    chunkQueue:push(strpack("<I1I1I1I1", r * 255, g * 255, b * 255, a * 255))
                end
            end

            -- commit chunk
            local chunkData = chunkQueue:concat()
            frameOut:push(strpack("<I4", string.len(chunkData) + 6))
            frameOut:push(strpack("<I2", 0x2005))
            frameOut:push(chunkData)

            print("cel chunk")
        end

        local frameData = frameOut:concat()
        aseOut:push(strpack("<I4", string.len(frameData) + 4))
        aseOut:push(frameData)

        print("write frame")

        quadIndex = quadIndex + 1
    end

    -- commit ase file
    local out = Queue.new()
    local aseData = aseOut:concat()
    out:push(strpack("<I4", string.len(aseData)))
    out:push(aseData)

    return out:concat()


    -- test: export spritesheet
    --[[
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
    --]]
end

return Aseprite