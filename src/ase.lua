--[[
Module to handle import/export of Aseprite files
--]]
local ffi = require("ffi")

local Aseprite = {}

---@param format string
---@param ... boolean|string|number
---@return string
local function strpack(format, ...)
    return love.data.pack("string", format, ...) --[[@as string]]
end

---@param workspace Workspace
local function parseWorkspace(workspace)
    local celImages = {} ---@type {[integer]: love.ImageData[]}

    --local frames = {} ---@type {[ImageQuad]: }
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

    -- create cel chunks
    local quadIndex = 1
    for id, quad in pairs(workspace.quads) do
        local imageData = love.image.newImageData(maxWidth, maxHeight)
        imageData:paste(quad.image,
            math.floor(maxWidth/2 - quad.cx),
            math.floor(maxHeight/2 - quad.cy),
            0, 0, quad.w, quad.h
        )
        
        celImages[id] = imageData
    end

    -- tags
    local timeline = {} ---@type {id: string, duration: integer}[]
    local tags = {} ---@type {from: integer, to: integer, name: string}[]
    local usedFrames = {} ---@type {[integer]: boolean}

    local frameIndex = 0
    for _, anim in ipairs(workspace.animations) do
        local from = frameIndex

        for _, frame in ipairs(anim.frames) do
            usedFrames[frame] = true

            table.insert(timeline, {
                id = frame,
                duration = math.floor(anim.frameLen * 16)
            })
            frameIndex=frameIndex+1
        end

        local to = frameIndex-1

        if anim.doLoop then
            table.insert(tags, {
                from = from,
                to = to + anim.loopPoint - 1,
                name = anim.name .. "-loop"
            })
        end
           
        if not anim.doLoop or anim.loopPoint ~= 1 then
            table.insert(tags, {
                from = from,
                to = to,
                name = anim.name
            })
        end
    end

    -- insert unused frames
    for id, _ in pairs(workspace.quads) do
        if not usedFrames[id] then
            table.insert(timeline, {
                id = id,
                duration = 100
            })
        end
    end

    return {
        width = maxWidth,
        height = maxHeight,
        celImages = celImages,
        timeline = timeline,
        tags = tags
    }
end

---@param frameOut Queue
---@param chunkQueue Queue
---@param chunkType integer
local function commitChunk(frameOut, chunkQueue, chunkType)
    local chunkData = chunkQueue:concat()
    frameOut:push(strpack("<I4", string.len(chunkData) + 6))
    frameOut:push(strpack("<I2", chunkType))
    frameOut:push(chunkData)
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
    local aseData = parseWorkspace(workspace)
    local aseOut = Queue.new()

    -- file header (without file size)
    aseOut:push(strpack("<I2", 0xA5E0)) -- magic number
    aseOut:push(strpack("<I2", #aseData.timeline)) -- frame count
    aseOut:push(strpack("<I2I2", aseData.width, aseData.height)) -- frame size
    aseOut:push(strpack("<I2", 32)) -- RGBA
    aseOut:push(strpack("<I4", 0)) -- no layer opacity
    aseOut:push(strpack("<I2", 0)) -- deprecated
    aseOut:push(strpack("<I4I4I1", 0, 0, 0)) -- unused values
    aseOut:push(strpack("<c3", string.rep("\0", 3))) -- unused
    aseOut:push(strpack("<I2", 0)) -- number of colors
    aseOut:push(string.rep("\0", 94)) -- reserved

    -- table to map quad ID to the first appearance of it
    -- in the timeline. this is to link them together.
    local celSources = {} ---@type {[integer]: integer}
    
    -- write timeline
    for i, frame in ipairs(aseData.timeline) do
        local frameOut = Queue.new()

        frameOut:push(strpack("<I2", 0xF1FA)) -- magic number

        -- first frame stores a Layer and Frame Tags Chunk
        -- which means first chunk has 3 chunks instead of 1
        if i == 1 then
            frameOut:push(strpack("<I2", 3))
        else
            frameOut:push(strpack("<I2", 1))
        end

        frameOut:push(strpack("<I2", frame.duration)) -- frame duration in ms
        frameOut:push(string.rep("\0", 6)) -- reserved

        if i == 1 then
            do -- layer chunk
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
                commitChunk(frameOut, chunkQueue, 0x2004)
            end

            do -- tags chunk
                local chunkQueue = Queue.new()

                chunkQueue:push(strpack("<I2", #aseData.tags)) -- tag count
                chunkQueue:push(strpack("<I8", 0)) -- reserved
                
                for _, tag in ipairs(aseData.tags) do
                    chunkQueue:push(strpack("<I2I2I1", tag.from, tag.to, 0)) -- from, to, loop direction (forward)
                    chunkQueue:push(strpack("<I8", 0)) -- reserved
                    chunkQueue:push(strpack("<I1I1I1", 0, 0, 0)) -- tag color
                    chunkQueue:push(strpack("x")) -- zero byte
                    chunkQueue:push(strpack("s2", tag.name)) -- tag name
                end

                commitChunk(frameOut, chunkQueue, 0x2018)
            end
        end

        -- cel chunk
        do
            local chunkQueue = Queue.new()

            local link = celSources[frame.id] ---@type integer?
            local celType = 2 -- compressed raw cell
            if link ~= nil then
                celType = 1 -- linked cell
            end

            chunkQueue:push(strpack("<I2I2I2I1I2c7",
                0,                  -- WORD: layer index
                0,                  -- WORD: x position
                0,                  -- WORD: y position
                255,                -- BYTE: opacity
                celType,            -- WORD: cel type (raw cell)
                string.rep("\0", 7) -- reserved
    
            ))
            
            if link ~= nil then
                chunkQueue:push(strpack("<I2", link))
            else
                celSources[frame.id] = i-1

                -- write raw data
                local image = aseData.celImages[frame.id] ---@type love.ImageData
                chunkQueue:push(strpack("<I2I2", image:getWidth(), image:getHeight()))
                chunkQueue:push(love.data.compress("string", "zlib", image))
            end

            -- commit chunk
            commitChunk(frameOut, chunkQueue, 0x2005)
        end

        local frameData = frameOut:concat()
        aseOut:push(strpack("<I4", string.len(frameData) + 4))
        aseOut:push(frameData)

        print("write frame")
    end

    -- commit ase file
    local out = Queue.new()
    local data = aseOut:concat()
    out:push(strpack("<I4", string.len(data)))
    out:push(data)

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