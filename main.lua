-- this is to make a lua debugger extension work 
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
    require("lldebugger").start()

    -- for some reason, assertion errors points to a lldebugger internal file
    -- so i'm redefining assert so that doesn't happen 
    function assert(a, b)
        return a or error(b or "assertion failed!", 2)
    end

    function love.errorhandler(msg)
        error(msg, 2)
    end
end

local runDir = arg[1]

local dlExt = jit.os == "Windows" and "dll" or jit.os == "OSX" and "dylib" or "so"
package.path = runDir .. "/?/init.lua;" .. package.path
package.cpath = package.cpath .. (";"..runDir.."/cimgui/?.%s"):format(dlExt)

_G.imgui = require("cimgui")
local ffi = require("ffi")
local util = require("util")
local path = require("path")
local FileBrowser = require("file-browser")

local doCloseApp = false

local fileBrowser = FileBrowser.new()
fileBrowser:addBookmark("Here", love.filesystem.getWorkingDirectory())

local appBase = {
    fileBrowser = fileBrowser,

    close = function()
        doCloseApp = true
    end,

    renderMenu = function(menuStruct)
        for _, menu in ipairs(menuStruct) do
            if imgui.BeginMenu(menu[1]) then
                for _, item in ipairs(menu[2]) do
                    if type(item) == "string" then
                        imgui.Separator()
                    else
                        local checked = false
                        if item[3] then
                            checked = item[3]()
                        end

                        local shortcut = item[2]
                        
                        if type(shortcut) == "function" then
                            if imgui.MenuItem_Bool(item[1], nil, checked) then
                                shortcut()
                            end
                        else
                            if imgui.MenuItem_Bool(item[1], shortcut.text, checked) then
                                shortcut.action()
                            end
                        end
                    end
                end

                imgui.EndMenu()
            end
        end
    end,

    openFileBrowser = function(...)
        fileBrowser:open(...)
    end,

    font = love.graphics.newFont("ProggyClean.ttf", 16),

    shortcut = function(shortcut, callback)
        local modifiers = {}
        for key in string.gmatch(shortcut, "([^+]+)") do
            table.insert(modifiers, key)
        end

        -- the last value is the key to be pressed
        local key = table.remove(modifiers)

        -- validate modifiers
        for _, mod in ipairs(modifiers) do
            if mod ~= "ctrl" and mod ~= "shift" and mod ~= "alt" then
                error("invalid modifier " .. mod, 2)
            end
        end

        table.insert(App._shortcuts, {
            modifiers = modifiers,
            key = key,
            callback = callback
        })

        return {
            action = callback,
            text = shortcut
        }
    end
}
appBase.__index = appBase

appBase.font:setFilter("nearest", "nearest")

local function initApp(appId)
    _G.App = setmetatable({
        _shortcuts = {}
    }, appBase)

    local f = love.filesystem.load("init.lua")
    f()

    if App then
        love.graphics.setBackgroundColor(0.4, 0.4, 0.4)
        
        if App.load then
            App.load()
        end
    end
end

local function closeApp()
    App = nil
end

function love.load()
    imgui.love.Init()
    love.graphics.setBackgroundColor(0, 0, 0)

    initApp()
end

function love.draw()
    love.graphics.setFont(appBase.font)

    if App.draw then
        love.graphics.push("all")
        App.draw()
        love.graphics.pop()
    end

    App.fileBrowser:draw()
        
    imgui.Render()
    imgui.love.RenderDrawLists()

    if doCloseApp then
        doCloseApp = false
        love.event.quit()
    end
end

function love.update(dt)
    imgui.love.Update(dt)
    imgui.NewFrame()

    if App and App.update then
        App.update(dt)
    end
end

function love.mousemoved(x, y, ...)
    imgui.love.MouseMoved(x, y)
    if not imgui.love.GetWantCaptureMouse() and App and App.mousemoved then
        App.mousemoved(x, y, ...)
    end
end

function love.mousepressed(x, y, button, ...)
    imgui.love.MousePressed(button)
    if not imgui.love.GetWantCaptureMouse() and App and App.mousepressed then
        App.mousepressed(x, y, button, ...)
    end
end

function love.mousereleased(x, y, button, ...)
    imgui.love.MouseReleased(button)
    if not imgui.love.GetWantCaptureMouse() and App and App.mousereleased then
        App.mousereleased(x, y, button, ...)
    end
end

function love.wheelmoved(x, y, ...)
    imgui.love.WheelMoved(x, y)
    if not imgui.love.GetWantCaptureMouse() and App and App.wheelmoved then
        App.wheelmoved(x, y, ...)
    end
end

function love.keypressed(key, ...)
    imgui.love.KeyPressed(key)
    if not imgui.love.GetWantCaptureKeyboard() and App then
        if App.keypressed then
            App.keypressed(key, ...)
        end

        -- run shortcuts
        for _, shortcut in ipairs(App._shortcuts) do
            if shortcut.key == key then
                -- detect required modifier keys
                local modDown =
                    util.table_find(shortcut.modifiers, "ctrl") ~= nil == love.keyboard.isDown("lctrl", "rctrl") and
                    util.table_find(shortcut.modifiers, "shift") ~= nil == love.keyboard.isDown("lshift", "rshift") and
                    util.table_find(shortcut.modifiers, "alt") ~= nil == love.keyboard.isDown("lalt", "ralt")
                
                if modDown then
                    shortcut.callback()
                end
            end
        end
    end
end

function love.keyreleased(key, ...)
    imgui.love.KeyReleased(key)
    if not imgui.love.GetWantCaptureKeyboard() and App and App.keyreleased then
        App.keyreleased(key, ...)
    end
end

function love.textinput(t, ...)
    imgui.love.TextInput(t)
    if not imgui.love.GetWantCaptureKeyboard() and App and App.textinput then
        App.textinput(t, ...)
    end
end

function love.resize(...)
    if App and App.resize then
        App.resize(...)
    end
end

function love.filedropped(...)
    if App and App.filedropped then
        App.filedropped(...)
    end
end

function love.quit()
    if App and App.quit then
        App.quit()
    end

    return imgui.love.Shutdown()
end