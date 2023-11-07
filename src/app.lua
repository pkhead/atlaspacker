local ffi = require("ffi")
local util = require("util")
local checkerboard = require("checkerboard")
local Workspace = require("workspace")
local AnimationEditor = require("animation")
local Atlas = require("atlas")

local MENU_BAR

local ZOOM_FACTOR = 1.5
local workspace, animEd
local viewAnimEd = false

local intInput = ffi.new("int[1]")
local boolInput = ffi.new("bool[1]")
local strBuf = ffi.new("char[256]")
local strBufLen = 256

local docPropsWindow = {
    show = false
}

local showHelpWindow = false

local errorWindow = {
    show = false,
    msg = nil
}

local formatSelWindow = {
    show = false,
    colsInput = ffi.new("int[1]")
}
formatSelWindow.colsInput[0] = 4

local setIdWindow = {
    show = false,
    inUse = false,
    input = ffi.new("int[1]")
}

function setIdWindow.calcInUse()
    setIdWindow.inUse = false

    local startId = setIdWindow.input[0]
    local numSelected = #workspace.selectedQuads

    -- for each id to be assigned to the selection
    for id=startId, startId + numSelected - 1 do
        -- if there is a quad with this id,
        -- flag as in use
        if workspace.quads[id] then
            setIdWindow.inUse = true
            return
        end
    end
end

local function resetWorkspace(w, h)
    workspace = Workspace.new(w, h)
    animEd = AnimationEditor.new(workspace)
end

local currentFilePath
local function openFile(filePath)
    if not filePath then
        return
    end

    local s, data = pcall(Atlas.read, filePath, true)
    if not s then
        errorWindow.show = true
        errorWindow.msg = data
        return
    end

    currentFilePath = filePath

    resetWorkspace(data.atlasImage:getWidth(), data.atlasImage:getHeight())
    for i, quad in pairs(data.quads) do
        workspace.quads[i] = {
            x = quad.x,
            y = quad.y,
            w = quad.w,
            h = quad.h,
            resScale = quad.resScale,
            cx = quad.w / 2,
            cy = quad.h / 2,
            name = quad.name,
            image = quad.image,
            texture = love.graphics.newImage(quad.image)
        }
    end
    
    workspace.animations = data.animations
end

local function saveFile(filePath)
    assert(filePath)
    local s, err = pcall(Atlas.write, filePath, workspace)
    if not s then
        errorWindow.show = true
        errorWindow.msg = err
    end
end

function App.load()
    checkerboard.refresh()
    resetWorkspace(100, 100)
end

function App.resize(w, h)
    checkerboard.refresh()
end

function App.mousepressed(x, y, btn)
    workspace:mousepressed(x, y, btn)
end

function App.mousemoved(x, y, dx, dy)
    workspace:mousemoved(x, y, dx, dy)
end

function App.mousereleased(x, y, btn)
    workspace:mousereleased(x, y, btn)
end

function App.keypressed(key)
    imgui.love.RunShortcuts(key)
end

function App.wheelmoved(x, y)
    local mx, my = workspace:screenToWorkspace(love.mouse.getX(), love.mouse.getY())

    if y > 0 then
        workspace:zoom(ZOOM_FACTOR, mx, my)
    else
        workspace:zoom(1 / ZOOM_FACTOR, mx, my)
    end
end

local function selectedQuads()
    local t = {}

    for _, i in ipairs(workspace.selectedQuads) do
        table.insert(t, workspace.quads[i])
    end

    return t
end

function App.draw()
    if imgui.BeginMainMenuBar() then
        App.renderMenu(MENU_BAR)
        imgui.EndMainMenuBar()
    end

    workspace:draw(checkerboard)

    -- error notification
    if errorWindow.show then
        errorWindow.show = false
        imgui.OpenPopup_Str("Error opening file")
    end

    if imgui.BeginPopupModal("Error opening file", nil, imgui.ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.Text("%s", errorWindow.msg)
        if imgui.Button("OK") then
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end

    -- format selection prompt
    if formatSelWindow.show then
        formatSelWindow.show = false
        imgui.OpenPopup_Str("Format")
    end

    if imgui.BeginPopupModal("Format", nil, imgui.ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.AlignTextToFramePadding()
        imgui.Text("Columns")
        imgui.SameLine()
        imgui.SetNextItemWidth(imgui.GetTextLineHeight() * 6)
        imgui.InputInt("###columns", formatSelWindow.colsInput, 1, 1000)

        if imgui.Button("OK") then
            workspace:formatSelection(formatSelWindow.colsInput[0])
            imgui.CloseCurrentPopup()
        end

        imgui.SameLine()

        if imgui.Button("Cancel") then
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end

    -- set id prompt
    if setIdWindow.show then
        setIdWindow.show = false
        setIdWindow.calcInUse()
        imgui.OpenPopup_Str("Set ID")
    end

    if imgui.BeginPopupModal("Set ID", nil, imgui.ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.AlignTextToFramePadding()
        imgui.Text("Starting ID")
        imgui.SameLine()
        imgui.SetNextItemWidth(imgui.GetTextLineHeight() * 6)

        if imgui.InputInt("###id", setIdWindow.input, 0, 9999) then
            print("update")
            setIdWindow.calcInUse()
        end

        if setIdWindow.inUse then
            imgui.Text("An ID is already in use")
        else
            imgui.NewLine()
        end

        if imgui.Button("OK") then
            workspace:setId(setIdWindow.input[0])
            imgui.CloseCurrentPopup()
        end

        imgui.SameLine()

        if imgui.Button("Cancel") then
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end

    -- document properties window
    if docPropsWindow.show then
        boolInput[0] = docPropsWindow.show

        if imgui.Begin("Properties", boolInput) then
            imgui.PushItemWidth(-imgui.FLT_MIN)

            -- DOCUMENT PROPERTIES
            imgui.SeparatorText("Document Properties")

            -- labels column
            imgui.BeginGroup()
            imgui.AlignTextToFramePadding()
            imgui.Text("Width")
            imgui.AlignTextToFramePadding()
            imgui.Text("Height")
            imgui.EndGroup()

            -- values column
            imgui.SameLine()
            imgui.BeginGroup()

            intInput[0] = workspace.width
            if imgui.InputInt("##width", intInput) then
                workspace.width = math.max(intInput[0], 1)
            end

            intInput[0] = workspace.height
            if imgui.InputInt("##height", intInput) then
                workspace.height = math.max(intInput[0], 1)
            end

            imgui.EndGroup()

            -- FRAME(s) PROPERTIES
            imgui.SeparatorText("Selection Properties")

            if #workspace.selectedQuads > 0 then
                local quads = selectedQuads()
                local firstQuad = workspace.quads[workspace.selectedQuads[1]]

                -- labels column
                imgui.BeginGroup()
                imgui.AlignTextToFramePadding()
                imgui.Text("Name")
                imgui.AlignTextToFramePadding()
                imgui.Text("Resolution Scale")
                imgui.AlignTextToFramePadding()
                imgui.Text("Center X")
                imgui.AlignTextToFramePadding()
                imgui.Text("Center Y")
                imgui.EndGroup()

                -- values column
                imgui.SameLine()
                imgui.BeginGroup()

                local quadsName = firstQuad.name
                local quadResScale = firstQuad.resScale
                local quadCx = firstQuad.cx
                local quadCy = firstQuad.cy

                -- get aggregate quad properties
                for _, quad in ipairs(quads) do -- quad name
                    if quad.name ~= quadsName then
                        quadsName = ""
                        break
                    end
                end

                for _, quad in ipairs(quads) do -- res scale
                    if quad.resScale ~= quadResScale then
                        quadResScale = 0
                        break
                    end
                end

                for _, quad in ipairs(quads) do -- cx
                    if quad.cx ~= quadCx then
                        quadCx = 0
                        break
                    end
                end

                for _, quad in ipairs(quads) do -- cy
                    if quad.cy ~= quadCy then
                        quadCy = 0
                        break
                    end
                end
                
                ffi.copy(strBuf, quadsName)
                if imgui.InputText("##frame-name", strBuf, strBufLen) then
                    for _, quad in ipairs(quads) do
                        quad.name = ffi.string(strBuf)
                    end
                end
                
                intInput[0] = quadResScale
                if imgui.InputInt("##scale", intInput) then
                    for _, quad in ipairs(quads) do
                        quad.resScale = math.max(intInput[0], 1)
                    end
                end

                intInput[0] = quadCx
                if imgui.InputInt("##cx", intInput) then
                    for _, quad in ipairs(quads) do
                        quad.cx = intInput[0]
                    end
                end

                intInput[0] = quadCy
                if imgui.InputInt("##cy", intInput) then
                    for _, quad in ipairs(quads) do
                        quad.cy = intInput[0]
                    end
                end

                imgui.EndGroup()
            end

            imgui.PopItemWidth()
        end

        imgui.End()

        docPropsWindow.show = boolInput[0]
    end

    -- help window
    if showHelpWindow then
        boolInput[0] = showHelpWindow
        if imgui.Begin("Help", boolInput, imgui.ImGuiWindowFlags_AlwaysAutoResize) then
            imgui.TextWrapped("This is a tool used to make animated sprites in-game.")
            imgui.SeparatorText("Navigation")
            imgui.BulletText("Left-click to select/drag frames")
            imgui.BulletText("Middle-mouse drag to pan")
            imgui.BulletText("Scroll wheel to zoom")
            imgui.BulletText("Right-click to edit frame properties")
            imgui.SeparatorText("File import")
            imgui.TextWrapped("Importing can be done via File > Import, but you can also drag an image onto the window to import as well.")
            imgui.SeparatorText("Animation Editor")
            imgui.TextWrapped(
                "The animation editor is accessed through View > Animation Editor. The buttons " ..
                "on the top of the window is for the creation and deletion of animations. Most " ..
                "controls should be self-explanatory.")
            imgui.NewLine()
            imgui.TextWrapped("The \"Insert Selection\" button inserts "  ..
                "frames selected in the work space to the animation's frame list. To remove a "  ..
                "frame from the frame list, right-click on the desired frame. You can also " ..
                "drag frames in the frame list to move them around.")
        end
        imgui.End()
        showHelpWindow = boolInput[0]
    end

    -- animation editor
    if viewAnimEd then
        viewAnimEd = animEd:draw()
    end

    love.graphics.pop()
end

local function importImage(filePath, x, y)
    local nameBase = string.match(filePath, "^.+[/\\](.+)$")
    local _, fileExtStart = string.find(nameBase, "^.+%.")

    if fileExtStart then
        nameBase = string.sub(nameBase, 1, fileExtStart-1)
    end

    local file = assert(io.open(filePath, "rb"), "could not open file")
    local imgData = file:read("*a")
    file:close()

    local s, img = pcall(love.image.newImageData, love.data.newByteData(imgData))
    if not s then
        errorWindow.show = true
        errorWindow.msg = img
        return
    end
    
    workspace:addImage(x, y, nameBase, img)
end

function App.filedropped(file)
    local mx, my = workspace:screenToWorkspace(love.mouse.getX(), love.mouse.getY())
    importImage(file:getFilename(), mx, my)
end

local function saveAs(path)
    if path then
        local s, err = pcall(saveFile, path)
        if s then
            currentFilePath = path
        else
            errorWindow.show = true
            errorWindow.msg = err
        end
    end
end

MENU_BAR = {
    {   "File",
        {
            {"New", App.shortcut("ctrl+n", function()
                resetWorkspace(100, 100)
            end)},

            {"Save", App.shortcut("ctrl+s", function()
                if currentFilePath then
                    saveFile(currentFilePath)
                else
                    App.fileBrowser:open("save", util.ATLAS_FILE_FILTERS, "atlas.atlas", saveAs)
                end
            end)},

            {"Save As...", App.shortcut("ctrl+shift+s", function()
                App.fileBrowser:open("save", util.ATLAS_FILE_FILTERS, "atlas.atlas", saveAs)
            end)},

            {"Open", App.shortcut("ctrl+o", function()
                App.fileBrowser:open("open", util.ATLAS_FILE_FILTERS, openFile)
            end)},

            {"Import...", function()
                App.fileBrowser:open("multiopen", util.IMAGE_FILE_FILTERS, function(files)
                    if files then
                        local x = workspace.viewX
                        local y = workspace.viewY

                        for _, file in ipairs(files) do
                            importImage(file, x, y)
                            x = x + 10
                            y = y + 10
                        end
                    end
                end)
            end},

            {"Exit", App.shortcut("ctrl+w", App.close)}
        }
    },
    {   "Edit",
        {
            {"Delete", App.shortcut("backspace", function()
                for _, i in ipairs(workspace.selectedQuads) do
                    workspace.quads[i] = nil
                end
                
                workspace.selectedQuads = {}
            end)},

            {"Resize to Extents", App.shortcut("ctrl+e", function()
                workspace:resizeToExtents()
            end)},

            {"Format Selection", App.shortcut("ctrl+f", function()
                -- show format selection prompt if at least one quad is selected
                if #workspace.selectedQuads > 0 then
                    formatSelWindow.show = true
                end
            end)},

            {"Set ID", App.shortcut("ctrl+i", function()
                -- show set id prompt if at least one quad is selected
                if workspace.selectedQuads[1] then
                    setIdWindow.show = true
                end
            end)}
        }
    },
    {   "View",
        {
            {"Zoom In", App.shortcut("ctrl+=", function()
                local imViewport = imgui.GetMainViewport()
                local cx = imViewport.WorkPos.x + imViewport.WorkSize.x / 2
                local cy = imViewport.WorkPos.y + imViewport.WorkSize.y / 2
                cx, cy = workspace:screenToWorkspace(cx, cy)

                workspace:zoom(ZOOM_FACTOR, cx, cy)
            end)},
            {"Zoom Out", App.shortcut("ctrl+-", function()
                local imViewport = imgui.GetMainViewport()
                local cx = imViewport.WorkPos.x + imViewport.WorkSize.x / 2
                local cy = imViewport.WorkPos.y + imViewport.WorkSize.y / 2
                cx, cy = workspace:screenToWorkspace(cx, cy)

                workspace:zoom(1 / ZOOM_FACTOR, cx, cy)
            end)},
            {"Reset Zoom", App.shortcut("ctrl+0", function()
                local imViewport = imgui.GetMainViewport()
                local cx = imViewport.WorkPos.x + imViewport.WorkSize.x / 2
                local cy = imViewport.WorkPos.y + imViewport.WorkSize.y / 2
                cx, cy = workspace:screenToWorkspace(cx, cy)

                workspace:zoom(1 / workspace.viewZoom, cx, cy)
            end)},
            {"Reset View", function()
                workspace.viewX = 0
                workspace.viewY = 0
                workspace.viewZoom = 1
            end},

            "----",

            {"Properties", function()
                docPropsWindow.show = not docPropsWindow.show
            end, function() return docPropsWindow.show end},

            {"Animation Editor", function()
                viewAnimEd = not viewAnimEd
            end, function() return viewAnimEd end}
        }
    },
    {   "Help",
        {
            {"Help...", function()
                showHelpWindow = true
            end}
        }
    }
}