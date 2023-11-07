--[[
Copyright 2023 pkhead

Permission is hereby granted, free of charge, to any person obtaining a copy of this software
and associated documentation files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--]]

local Atlas = {}
Atlas.__index = Atlas

local str_unpack = love.data.unpack

local function readData(fileData)
    -- check signature
    local version = 0
    local offset = 1

    if string.sub(fileData, 1, 5) == "Atlas" then
        version, offset = str_unpack("<I1", fileData, 6)
    else
        -- level is 3 because this function is called by Atlas.load
        error("invalid atlas file", 3)
    end
    
    -- global res scale only exists in version 1 files
    local globalResScale = 1

    if version == 1 then
        globalResScale, offset = str_unpack("<f", fileData, offset)
    end

    local sizePng
    sizePng, offset = str_unpack("<I4", fileData, offset)
    local pngData = love.data.newByteData(string.sub(fileData, offset, offset+sizePng-1))
    offset = offset + sizePng

    -- get each frame of the atlas image
    -- and also create a new texture for each quad
    local quads = {}
    local numQuads
    numQuads, offset = str_unpack("<I4", fileData, offset)

    for _=1, numQuads do
        local id, x, y, w, h, name, next = str_unpack("<i4i4i4i4i4z", fileData, offset)
        offset = next

        local scale = globalResScale
        local cx = w / 2
        local cy = h / 2

        if version >= 2 then
            scale, cx, cy, offset = str_unpack("<i4i4i4", fileData, offset)
        end

        quads[id] = {
            name = name,
            x = x,
            y = y,
            w = w,
            h = h,
            resScale = scale,
            cx = cx,
            cy = cy
        }
    end

    -- read animations
    local anims = {}

    if version >= 1 then
        local numAnims
        numAnims, offset = str_unpack("<I4", fileData, offset)

        for i=1, numAnims do
            local loopData, frameCount
            local animDat = {}

            animDat.name, animDat.frameLen, loopData, frameCount,
            offset = str_unpack("<zI4I4I4", fileData, offset)

            if loopData == 0 then
                animDat.doLoop = false
                animDat.loopPoint = 1
            else
                animDat.doLoop = true
                animDat.loopPoint = loopData
            end

            -- read frames
            animDat.frames = {}
            for j=1, frameCount do
                local quadI
                quadI, offset = str_unpack("<I4", fileData, offset)
                animDat.frames[j] = quadI
            end

            anims[animDat.name] = animDat
        end
    end

    return {
        imageData = pngData,
        quads = quads,
        animations = anims
    }
end

-- Load an atlas file from a path
-- @param path The path to be loaded by `love.filesystem.read`
-- @returns The newly created atlas
function Atlas.load(path)
    local fileData, fileSize = love.filesystem.read(path)
    local atlasData = readData(fileData)

    local self = setmetatable({}, Atlas)

    self.image = love.graphics.newImage(atlasData.imageData)
    self.quadData = atlasData.quads
    self.animations = atlasData.animations
    self.curQuad = 1

    self.curAnim = nil
    self.frame = 0
    self.animTicker = 0

    self.quads = {}

    for id, data in pairs(atlasData.quads) do
        local quad = love.graphics.newQuad(data.x, data.y, data.w, data.h, self.image)
        self.quads[id] = quad
    end

    return self
end

-- Release all resources associated with the atlas
function Atlas:release()
    for _, quad in pairs(self.quads) do
        quad:release()
    end

    self.image:release()
    self.animations = nil
    self.quads = nil
    self.quadData = nil
end

-- Returns true if this atlas has an animation of the given name
-- @param animName The name query
function Atlas:hasAnim(animName)
    return self.animations[animName] ~= nil
end

-- Begin playing an animation
-- @param animName The name of the animation to play
function Atlas:playAnim(animName)
    local animDat = self.animations[animName]
    if animDat == nil then
        error(("animation '%s' does not exist"):format(animName), 2)
        return
    end

    self.curAnim = animName
    self.frame = 1
    self.animTicker = animDat.frameLen / 60
    self.curQuad = animDat.frames[1]
end

-- Get the frames of an animation
-- @param animName The name of the animation
function Atlas:getAnimFrames(animName)
    local animDat = self.animations[animName]
    if animDat == nil then
        error(("animation '%s' does not exist"):format(animName), 2)
    end

    return animDat.frames
end

-- Stop the currently playing animation
function Atlas:stopAnim()
    self.curAnim = nil
end

-- Update the atlas animation
-- @param dt The delta-time, in seconds
function Atlas:update(dt)
    if self.curAnim then
        local animDat = self.animations[self.curAnim]
        
        self.animTicker = self.animTicker - dt
        
        if self.animTicker <= 0 then
            -- if reached end of animation
            if self.frame == #animDat.frames then
                -- go back to loop point
                if animDat.doLoop then
                    self.frame = animDat.loopPoint
                    self.curQuad = animDat.frames[self.frame]
                    self.animTicker = animDat.frameLen / 60

                else -- stop animation
                    self:stopAnim()
                    return
                end
            else
                self.frame = self.frame + 1
                self.curQuad = animDat.frames[self.frame]
                self.animTicker = animDat.frameLen / 60
            end
        end

        assert(self.quadData[self.curQuad])
    end
end

-- Draw the atlas without taking into account
-- the resolution scale and offset
-- @param id The ID of the quad to draw
-- @param ... Transform arguments to pass to `love.graphics.draw` 
function Atlas:drawRaw(id, ...)
    love.graphics.draw(self.image, self.quads[id], ...)
end

-- Draw the atlas
-- @param x The X coordinate of the center of the frame
-- @param y The Y coordinate of the center of the frame
-- @param r The rotation of the frame
-- @param sx X scaling
-- @param sy Y scaling
function Atlas:draw(x, y, r, sx, sy)
    sx = sx or 1
    sy = sy or 1

    local quad = self.quads[self.curQuad]
    local quadData = self.quadData[self.curQuad]

    love.graphics.draw(self.image, quad,
        x - quadData.cx / quadData.resScale * sx,
        y - quadData.cy / quadData.resScale * sy,
        r, sx / quadData.resScale, sy / quadData.resScale
    )
end

return Atlas