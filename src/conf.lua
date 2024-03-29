function love.conf(t)
    t.identity = "atlaspacker"
    t.version = "11.4"
    t.modules.physics = false
    t.modules.audio = false
    t.modules.joystick = false
    t.modules.sound = false
    t.modules.touch = false
    t.modules.video = false

    -- these modules are loaded if app is launched in GUI mode
    t.modules.graphics = false
    t.modules.window = false
    t.modules.timer = false

    t.window.title = "Atlaspacker"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.stencil = true
end