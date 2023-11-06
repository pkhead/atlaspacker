-- programmatically generated checkerboard texture
local CHECKERBOARD_COLOR_1 = { 0.7, 0.7, 0.7, 1 }
local CHECKERBOARD_COLOR_2 = { 0.5, 0.5, 0.5, 1 }
local CHECKERBOARD_SIZE = 16
local checkerboardTex
local checkerboardQuad

local imgData = love.image.newImageData(2, 2)
imgData:setPixel(0, 0, unpack(CHECKERBOARD_COLOR_1))
imgData:setPixel(1, 1, unpack(CHECKERBOARD_COLOR_1))
imgData:setPixel(1, 0, unpack(CHECKERBOARD_COLOR_2))
imgData:setPixel(0, 1, unpack(CHECKERBOARD_COLOR_2))

checkerboardTex = love.graphics.newImage(imgData)
checkerboardTex:setFilter("nearest", "nearest")
checkerboardTex:setWrap("repeat", "repeat")

local function refresh()
    checkerboardQuad = love.graphics.newQuad(0, 0, love.graphics.getWidth() / CHECKERBOARD_SIZE, love.graphics.getHeight() / CHECKERBOARD_SIZE, checkerboardTex)
end

refresh()

return {
    tex = checkerboardTex,
    quad = checkerboardQuad,
    size = CHECKERBOARD_SIZE,
    refresh = refresh
}