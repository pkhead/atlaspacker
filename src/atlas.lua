--[[
    This file handles the loading of atlas files for the editor.
    They are different files because the editor loads each frame
    as a separate image, while your game loads the atlas file
    as an actual sprite atlas.
--]]

local Atlas = {}
local json = require("json")

local str_unpack = love.data.unpack
local data_pack = love.data.pack

local function readAtlas(filePath)
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

        local quadImage = love.image.newImageData(w, h)
        quadImage:paste(image, 0, 0, x, y, w, h)
        quads[id].image = quadImage
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

local function readJson(filePath)
    local pngFile = io.open(filePath, "rb")
    assert(pngFile, "Could not open " .. filePath)
    local jsonFile = io.open(filePath .. ".json", "r")
    assert(jsonFile, "Could not open " .. filePath .. ".json")

    local jsonData = json.decode(jsonFile:read("*a"))
    local pngData = love.data.newByteData(pngFile:read("*a"))
    local image = love.image.newImageData(pngData)

    -- get each frame of the atlas image
    -- and also create a new texture for each quad
    local quads = {}

    for _, quadDat in ipairs(jsonData.quads) do
        assert(type(quadDat.x) == "number")
        assert(type(quadDat.y) == "number")
        assert(type(quadDat.w) == "number")
        assert(type(quadDat.h) == "number")
        assert(type(quadDat.name) == "string")
        assert(type(quadDat.resScale) == "number")
        assert(type(quadDat.cx) == "number")
        assert(type(quadDat.cy) == "number")
        assert(type(quadDat.id) == "number")

        quads[quadDat.id] = {
            x = quadDat.x,
            y = quadDat.y,
            w = quadDat.w,
            h = quadDat.h,
            name = quadDat.name,
            resScale = quadDat.resScale,
            cx = quadDat.cx,
            cy = quadDat.cy
        }

        local quadImage = love.image.newImageData(quadDat.w, quadDat.h)
        quadImage:paste(image, 0, 0, quadDat.x, quadDat.y, quadDat.w, quadDat.h)
        quads[quadDat.id].image = quadImage
    end

    -- read animations
    local anims = {}

    for i, animJson in ipairs(jsonData.animations) do
        assert(type(animJson.name) == "string")
        assert(type(animJson.frameLen) == "number")
        assert(type(animJson.loop) == "number")
        assert(type(animJson.frames) == "table")

        local animDat = {}

        animDat.name = animJson.name
        animDat.frameLen = animJson.frameLen
        local loopData = animJson.loop
        
        if loopData == 0 then
            animDat.doLoop = false
            animDat.loopPoint = 1
        else
            animDat.doLoop = true
            animDat.loopPoint = loopData
        end

        -- read frames
        animDat.frames = {}
        for j, quadI in ipairs(animJson.frames) do
            assert(type(animJson.frames[j]) == "number")
            animDat.frames[j] = quadI
        end

        anims[i] = animDat
    end

    pngFile:close()
    jsonFile:close()

    return {
        atlasImage = image,
        quads = quads,
        animations = anims
    }
end

---@alias OpenMode
---|    "atlas"
---|    "json"

---@param filePath string
---@param openMode OpenMode
---@param separateImages any
function Atlas.read(filePath, openMode, separateImages)
    if openMode == "atlas" then
        return readAtlas(filePath)
    elseif openMode == "json" then
        return readJson(filePath)
    else
        error(("unknown open mode '%s'"):format(openMode))
    end
end

---@alias SaveMode
---|    "atlas"
---|    "image"
---|    "json"

---@param filePath string
---@param saveMode SaveMode
---@param saveData any
function Atlas.write(filePath, saveMode, saveData)
    if saveMode ~= "atlas" and saveMode ~= "image" and saveMode ~= "json" then
        error(("invalid save mode '%s'"):format(saveMode), 2)
    end
    
    local file = io.open(filePath, "wb")
    assert(file, "Could not open " .. filePath)

    -- create singular png file
    local atlasImage = love.image.newImageData(saveData.width, saveData.height)

    for i, quad in pairs(saveData.quads) do
        atlasImage:paste(quad.image, quad.x, quad.y, 0, 0, quad.w, quad.h)
    end

    local atlasImageData = atlasImage:encode("png")

    -- save mode is png or png+json, save the png
    if saveMode == "image" or saveMode == "json" then
        file:write(atlasImageData:getString())

        -- if save mode is json, also save quad/animation data as a json file
        if saveMode == "json" then
            local jsonFile = io.open(filePath .. ".json", "w")
            assert(jsonFile, ("Could not open %s.json"):format(filePath))

            local outTable = {
                version = 0,
                quads = {},
                animations = {}
            }

            -- write quad data
            for id, quad in pairs(saveData.quads) do
                table.insert(outTable.quads, {
                    id = id,
                    name = quad.name,
                    x = quad.x,
                    y = quad.y,
                    w = quad.w,
                    h = quad.h,
                    resScale = quad.resScale,
                    cx = quad.cx,
                    cy = quad.cy
                })
            end

            -- write animation data
            for _, animData in ipairs(saveData.animations) do
                local loopData = 0
                if animData.doLoop then
                    loopData = animData.loopPoint
                end

                local animSave = {
                    name = animData.name,
                    frameLen = animData.frameLen,
                    loop = loopData,
                    frames = {}
                }

                for _, quadId in ipairs(animData.frames) do
                    table.insert(animSave.frames, quadId)
                end

                table.insert(outTable.animations, animSave)
            end

            jsonFile:write(json.encode(outTable))
            jsonFile:close()
        end

    -- save mode is atlas
    elseif saveMode == "atlas" then
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
    end

    file:close()
end

return Atlas