local ffi = require("ffi")
local util = require("util")
local Checkerboard = require("checkerboard")

local AnimationEditor = {}
AnimationEditor.__index = AnimationEditor

local inputStrLen = 256
local inputStr = ffi.new("char[?]", inputStrLen)

local inputInt = ffi.new("int[1]")
local inputBool = ffi.new("bool[1]")

function AnimationEditor.new(workspace)
    local self = setmetatable({}, AnimationEditor)
    self.selected = 1
    self.curFrame = 1
    self.workspace = workspace

    self.play = false

    self.previewW = 256
    self.previewH = 256
    self.previewCanvas = love.graphics.newCanvas(self.previewW, self.previewH)
    self.checkerQuad = love.graphics.newQuad(0, 0, self.previewW / Checkerboard.size, self.previewH / Checkerboard.size, Checkerboard.tex)
    
    return self
end

function AnimationEditor:draw()
    local workspace = self.workspace
    
    local windowOpen = ffi.new("bool[1]")
    windowOpen[0] = true

    imgui.SetNextWindowSize(imgui.ImVec2_Float(imgui.GetTextLineHeight() * 80, imgui.GetTextLineHeight() * 30), imgui.ImGuiCond_FirstUseEver)
    if imgui.Begin("Animation Editor", windowOpen) then
        if imgui.Button("New") then
            table.insert(workspace.animations, {
                name = "anim",
                frameLen = 2,
                doLoop = false,
                loopPoint = 1,
                frames = {}
            })
            
            self.selected = #workspace.animations
            self.curFrame = 1
            self.play = false
        end
        
        imgui.SameLine()
        if imgui.Button("Delete") then
            if workspace.animations[self.selected] then
                table.remove(workspace.animations, self.selected)
                if self.selected > #workspace.animations then
                    self.selected = #workspace.animations
                end
            end
        end

        imgui.SameLine()
        if imgui.Button("Duplicate") then
            local selectedAnim = workspace.animations[self.selected]

            if selectedAnim then
                table.insert(workspace.animations, util.table_deep_copy(selectedAnim))
                self.selected = #workspace.animations
                self.curFrame = 1
            self.play = false
            end
        end
        
        -- animation list
        local listW = imgui.GetTextLineHeight() * 12
        local avail = imgui.GetContentRegionAvail()
        if imgui.BeginChild_Str("list", imgui.ImVec2_Float(listW, avail.y), true) then
            for i, animData in ipairs(workspace.animations) do
                imgui.PushID_Int(i)

                if imgui.Selectable_Bool(animData.name, i == self.selected) then
                    self.curFrame = 1
                    self.selected = i
                    self.play = false
                end

                imgui.PopID()
            end
        end
        imgui.EndChild()

        -- animation properties
        imgui.SameLine()

        local animData = workspace.animations[self.selected]
        if animData then
            imgui.BeginChild_Str("prop", imgui.ImVec2_Float(imgui.GetTextLineHeight() * 16, avail.y))
            imgui.PushItemWidth(-imgui.FLT_MIN)

            if self.play then
                if imgui.Button("Pause##playback") then
                    self.play = false
                end

                if love.timer.getTime() >= self.nextFrameTime then
                    self.nextFrameTime = love.timer.getTime() + animData.frameLen / 60
                    self.curFrame = self.curFrame + 1

                    if self.curFrame > #animData.frames then
                        if animData.doLoop then
                            self.curFrame = animData.loopPoint
                        else
                            self.curFrame = self.curFrame - 1
                            self.play = false
                        end
                    end
                end
            else
                if imgui.Button("Play##playback") then
                    self.play = true
                    self.curFrame = 1
                    self.nextFrameTime = love.timer.getTime() + animData.frameLen / 60
                end
            end

            -- name
            imgui.AlignTextToFramePadding()
            imgui.Text("Name")
            imgui.SameLine()
            ffi.copy(inputStr, animData.name)
            if imgui.InputText("##name", inputStr, inputStrLen) then
                animData.name = ffi.string(inputStr)
            end

            -- frame length
            imgui.AlignTextToFramePadding()
            imgui.Text("Length of Frame")
            imgui.SameLine()
            inputInt[0] = animData.frameLen
            if imgui.InputInt("##frameLen", inputInt) then
                animData.frameLen = math.max(inputInt[0], 1)
            end

            -- do loop
            imgui.AlignTextToFramePadding()
            imgui.Text("Loop")
            imgui.SameLine()
            inputBool[0] = animData.doLoop
            if imgui.Checkbox("##doLoop", inputBool) then
                animData.doLoop = inputBool[0]
            end

            if not animData.doLoop then
                imgui.BeginDisabled()
            end

            -- loop point
            imgui.AlignTextToFramePadding()
            imgui.Text("Loop Start")
            imgui.SameLine()
            inputInt[0] = animData.loopPoint
            imgui.InputInt("##loopPoint", inputInt)

            if animData.frames[1] == nil then
                animData.loopPoint = 0
            else
                animData.loopPoint = util.clamp(inputInt[0], 1, #animData.frames)
            end

            if not animData.doLoop then
                imgui.EndDisabled()
            end

            imgui.AlignTextToFramePadding()
            imgui.Text("Frames")
            
            if imgui.Button("Insert Selection") then
                local sorted = {}
                for i, v in ipairs(workspace.selectedQuads) do
                    sorted[i] = v
                end
                table.sort(sorted)

                local frame = self.curFrame
                if animData.frames[1] == nil then
                    frame = 0
                end

                for i=#sorted, 1, -1 do
                    table.insert(animData.frames, frame+1, sorted[i])
                end
                
                self.curFrame = frame + #sorted
            end

            if imgui.Button("Insert Backwards") then
                local sorted = {}
                for i, v in ipairs(workspace.selectedQuads) do
                    sorted[i] = v
                end
                table.sort(sorted)

                local frame = self.curFrame
                if animData.frames[1] == nil then
                    frame = 0
                end

                for _, index in ipairs(sorted) do
                    table.insert(animData.frames, frame+1, index)
                end

                self.curFrame = frame + #sorted
            end

            avail = imgui.GetContentRegionAvail()
            if imgui.BeginChild_Str("frames", imgui.ImVec2_Float(-imgui.FLT_MIN, avail.y)) then
                local frameToDelete
                local moveData

                for i, quadI in ipairs(animData.frames) do
                    local quad = workspace.quads[quadI] or {name = "[NULL]"}
                    imgui.PushID_Int(i)

                    local display = string.format("%-4s %s##frame", tostring(i), quad.name)

                    if imgui.Selectable_Bool(display, i == self.curFrame) then
                        self.curFrame = i
                    end

                    -- delete frame if right-clicked
                    if imgui.IsItemHovered() and imgui.IsMouseReleased(imgui.ImGuiMouseButton_Right) then
                        frameToDelete = i
                    end
                    
                    if imgui.BeginDragDropSource(imgui.ImGuiDragDropFlags_None) then
                        inputInt[0] = i
                        imgui.SetDragDropPayload("FRAME", inputInt, ffi.sizeof(inputInt))

                        print(i)

                        imgui.Text("%-4s %s", tostring(i), quad.name)
                        imgui.EndDragDropSource()
                    end

                    if imgui.BeginDragDropTarget() then
                        local payload = imgui.AcceptDragDropPayload("FRAME")
                        if payload ~= nil then
                            assert(payload[0].DataSize == ffi.sizeof("int"))
                            local data = ffi.cast("int*", payload[0].Data)
                            moveData = {
                                from = data[0],
                                to = i
                            }
                        end

                        imgui.EndDragDropTarget()
                    end

                    imgui.PopID()
                end

                if frameToDelete then
                    table.remove(animData.frames, frameToDelete)
                    if self.curFrame > #animData.frames then
                        self.curFrame = math.max(#animData.frames, 1)
                    end
                end

                if moveData then
                    local v = table.remove(animData.frames, moveData.from)
                    table.insert(animData.frames, moveData.to, v)
                    self.curFrame = moveData.to
                end
            end

            imgui.EndChild()
            imgui.PopItemWidth()
            imgui.EndChild()

            imgui.SameLine()

            -- update 
            if animData.frames[1] then
                local quad = workspace.quads[ assert(animData.frames[self.curFrame]) ]
        
                self:updatePreview(quad)
                imgui.Image(self.previewCanvas, imgui.ImVec2_Float(self.previewW, self.previewH))
            end
        end
    end
    imgui.End()

    return windowOpen[0]
end

function AnimationEditor:updatePreview(quad)
    love.graphics.push()

    love.graphics.setCanvas(self.previewCanvas)
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1)
    love.graphics.clear(1, 0, 0)
    love.graphics.draw(Checkerboard.tex, self.checkerQuad, 0, 0, 0, Checkerboard.size, Checkerboard.size)

    love.graphics.draw(
        quad.texture,
        self.previewW / 2 - quad.cx / quad.resScale,
        self.previewH / 2 - quad.cy / quad.resScale,
        0,
        1 / quad.resScale, 1 / quad.resScale
    )

    love.graphics.pop()
    love.graphics.setCanvas()
end

return AnimationEditor