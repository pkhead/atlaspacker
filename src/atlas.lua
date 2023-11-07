--[[
    This file handles the loading of atlas files for the editor.
    They are different files because the editor loads each frame
    as a separate image, while your game loads the atlas file
    as an actual sprite atlas.
--]]

local Atlas = {}

local str_unpack = love.data.unpack
local data_pack = love.data.pack

function Atlas.read(filePath, separateImages)
    local file = io.open(filePath, "rb")
    assert(file, "Could not open " .. filePath)
    local fileData = file:read("*a")

    -- check signature
    local version = 0
    local offset = 1

    if string.sub(fileData, 1, 5) == "Atlas" then
        version, offset = str_unpack("<I1", fileData, 6)
    else
        print("WARNING: Atlas file does not begin with signature. Proceeding anyway for compatibility purposes...")
    end
    
    -- global resolution scale only exists in version 1
    local globalResScale = 1

    if version == 1 then
        globalResScale, offset = str_unpack("<f", fileData, offset)
    end

    local sizePng
    sizePng, offset = str_unpack("<I4", fileData, offset)
    local pngData = love.data.newByteData(string.sub(fileData, offset, offset+sizePng-1))
    offset = offset + sizePng

    -- get atlas image
    local image = love.image.newImageData(pngData)

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
            local scale, cx, cy
            scale, cx, cy, offset = str_unpack("<i4i4i4", fileData, offset)
        end

        quads[id] = {
            x = x,
            y = y,
            w = w,
            h = h,
            name = name,
            resScale = scale,
            cx = cx,
            cy = cy
        }

        if separateImages then
            local quadImage = love.image.newImageData(w, h)
            quadImage:paste(image, 0, 0, x, y, w, h)
            quads[id].image = quadImage
        end
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

            anims[i] = animDat
        end
    end

    file:close()

    return {
        atlasImage = image,
        quads = quads,
        animations = anims
    }
end

function Atlas.write(filePath, saveData)
    local file = io.open(filePath, "wb")
    assert(file, "Could not open " .. filePath)

    -- create singular png file
    local atlasImage = love.image.newImageData(saveData.width, saveData.height)

    for i, quad in pairs(saveData.quads) do
        atlasImage:paste(quad.image, quad.x, quad.y, 0, 0, quad.w, quad.h)
    end

    local atlasImageData = atlasImage:encode("png")

    local out = {"Atlas\02"}

    -- write image data
    table.insert(out, data_pack("string", "<s4", atlasImageData:getString()))

    -- write quad data
    local quadCount = 0
    for _, _ in pairs(saveData.quads) do quadCount=quadCount+1 end
    table.insert(out, data_pack("string", "<I4", quadCount))

    for id, quad in pairs(saveData.quads) do
        table.insert(out, data_pack("string", "<i4i4i4i4i4zi4i4i4", id, quad.x, quad.y, quad.w, quad.h, quad.name, quad.resScale, quad.cx, quad.cy))
    end

    -- write animation data
    table.insert(out, data_pack("string", "<I4", #saveData.animations)) -- animation count

    for _, animData in ipairs(saveData.animations) do
        local loopData = 0
        if animData.doLoop then
            loopData = animData.loopPoint
        end

        -- animation name as a zero-terminated string,
        -- frame length as a uint16,
        -- loop point as a uint16, if loop is disabled then it stores 0
        -- number of frames as a uint16
        table.insert(out, data_pack("string", "<zI4I4I4", animData.name, animData.frameLen, loopData, #animData.frames))

        for _, quadId in ipairs(animData.frames) do
            -- quad id as a uint16
            table.insert(out, data_pack("string", "<I4", quadId))
        end
    end
    
    -- write data to file
    for _, data in ipairs(out) do
        file:write(data)
    end

    file:close()
end

return Atlas