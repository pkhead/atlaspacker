-- This is the version of the file browser which can browse the user's entire computer.

-- TODO: more obvious overwrite warning
-- make the textbox red when overwriting a file
-- TODO: shift+click on multifile to select range
-- TODO: file type selector
local DLL_EXT = jit.os == "Windows" and "dll" or jit.os == "OSX" and "dylib" or "so"
local ffi = require("ffi")
local util = require("util")
local path = require("path")
local imgui = require("cimgui")
local bit = require("bit")
local loveC = ffi.os == "Windows" and ffi.load("love") or ffi.C

ffi.cdef [[
    int PHYSFS_mount(const char* dir, const char* mountPoint, int appendToPath);
	int PHYSFS_unmount(const char* dir);
    const char* PHYSFS_getMountPoint(const char* dir);
]]

if ffi.os == "Windows" then
    ffi.cdef [[
        unsigned long GetLogicalDrives()
    ]]
end

local function withTempMount(dir, fn, ...)
    local mountPoint = loveC.PHYSFS_getMountPoint(dir)
    
    -- if directory is already mounted
    if mountPoint ~= nil then
        return fn(ffi.string(mountPoint), ...)
    end

    if not loveC.PHYSFS_mount(dir, "__FS_TEMP__", 0) then
        error(("could not open directory %s"):format(dir, 2))
    end

    local res = { fn("__FS_TEMP__", ...) }
    loveC.PHYSFS_unmount(dir)

    return unpack(res)
end

local function listDirectory(root, path)
    assert(path ~= nil and type(path) == "string")

    local fullPath = path
    if root then
        fullPath = root .. path
    end

    return withTempMount(fullPath, function(mountPoint)
        local files = {}
        local dirItems = assert(love.filesystem.getDirectoryItems(mountPoint))
        for i, fileName in ipairs(dirItems) do
            local stat = love.filesystem.getInfo(string.format("%s/%s", mountPoint, fileName))

            -- stat may be nil if file could not be read
            if stat then
                files[i] = {
                    name = fileName,
                    type = stat.type,
                    size = stat.size,
                    modtime = stat.modtime
                }
            end
        end

        return files
    end)
end

local HOME = jit.os == "Windows" and os.getenv("USERPROFILE") or os.getenv("HOME")
local SYSTEM_LOCATIONS = {
    ffi.os == "Windows" and { "User", HOME } or { "Home", HOME },
    { "Desktop", HOME .. path.separator .. "Desktop" },
    { "Documents", HOME .. path.separator .. "Documents" },
    { "Music", HOME .. path.separator .. "Music" },
    { "Pictures", HOME .. path.separator .. "Pictures" },
    { "Videos", HOME .. path.separator .. "Videos" },
    { "Downloads", HOME .. path.separator .. "Downloads" },
}

local DRIVE_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

-- remove locations that do not exist on the user's computer
for i=#SYSTEM_LOCATIONS, 1, -1 do
    if not pcall(listDirectory, nil, SYSTEM_LOCATIONS[i][2]) then
        table.remove(SYSTEM_LOCATIONS, i)
    end
end

-- initial directory is the game directory
local SYSTEM_DEFAULT_PATH = HOME

-- load icons
local fileIcon = love.graphics.newImage("file-browser/file-icon.png")
local dirIcon = love.graphics.newImage("file-browser/directory-icon.png")
local typeUnknown = love.graphics.newImage("file-browser/unknown.png")
local imageIcon = love.graphics.newImage("file-browser/image-icon.png")
local audioIcon = love.graphics.newImage("file-browser/audio-icon.png")
local deleteIcon = love.graphics.newImage("file-browser/delete.png")
local backIcon = love.graphics.newImage("file-browser/back.png")
local forwardIcon = love.graphics.newImage("file-browser/forward.png")
local upIcon = love.graphics.newImage("file-browser/up.png")
local fileTypeIcons = {
    atlas = love.graphics.newImage("file-browser/atlas-icon.png"),
    lua = love.graphics.newImage("file-browser/lua-icon.png"),
    
    -- images
    jpg = imageIcon,
    jpeg = imageIcon,
    png = imageIcon,
    bmp = imageIcon,
    tga = imageIcon,
    hdr = imageIcon,
    pic = imageIcon,
    exr = imageIcon,

    -- audio
    mp3 = audioIcon,
    ogg = audioIcon,
    wav = audioIcon,

    -- love supports tracker files???
    mod = audioIcon,
    s3m = audioIcon,
    xm = audioIcon,
    it = audioIcon
    -- not listing all of them here
}

-- File browser class
local FileBrowser = {}
FileBrowser.__index = FileBrowser

function FileBrowser.new(root)
    local self = setmetatable({}, FileBrowser)

    if root then
        if string.sub(root, -1, -1) ~= "/" then
            self.root = root .. "/"
        else
            self.root = root
        end
    end

    self.bookmarks = {}
    self._isOpen = false
    self.returnFullPath = false

    -- if this file browser is able to search through user's entire filesystem
    -- then add system bookmarks
    if self.root == nil then
        for i, v in pairs(SYSTEM_LOCATIONS) do
            table.insert(self.bookmarks, v)
        end
    end

    return self
end

function FileBrowser:addBookmark(name, path)
    table.insert(self.bookmarks, {
        name, path
    })
end

function FileBrowser:open(mode, fileFilters, defaultName, callback)
    -- validate mode argument
    if mode ~= "save" and mode ~= "open" and mode ~= "multiopen" then
        error(("invalid mode '%s'"):format(mode), 2)
    end

    -- validate file types
    if fileFilters ~= nil and type(fileFilters) ~= "table" then
            error(("bad argument #2 to 'FileBrowser.new' (table expected, got %s)"):format(type(callback)), 2)
    end

    if fileFilters == nil or fileFilters[1] == nil then
        fileFilters = {
            {"Any", "*.*"}
        }
    end

    local filterStrings = {}
    for i, filter in ipairs(fileFilters) do
        filterStrings[i] = string.format("%s (%s)", filter[1], table.concat(filter, ", ", 2))
    end

    -- if in open mode, the defaultName argument isn't present
    if mode == "open" or mode == "multiopen" then    
        callback, defaultName = defaultName, callback
    end

    -- validate callback argument
    if type(callback) ~= "function" then
        error(("bad argument #3 to 'FileBrowser.open' (function expected, got %s)"):format(type(callback)), 2)
    end

    if mode == "multiopen" then
        mode = "open"
        self.multi = true
    else
        self.multi = false
    end

    -- if last directory no longer exists, then reset back to default
    if self.lastDirectory == nil or not pcall(listDirectory, self.root, self.lastDirectory) then
        self.lastDirectory = self.root and "/" or SYSTEM_DEFAULT_PATH
    end

    self._isPopupOpen = false
    self._isOpen = true
    self.fileFilters = fileFilters
    self.filterStrings = filterStrings
    self.selectedFilter = 1
    self.pathBuf = ffi.new("char[256]")
    self:setPath(self.lastDirectory)
    self.callback = callback
    self.backStack = {}
    self.forwardStack = {}
    self.selected = {}
    self.openErrorPopup = false
    self.enterPath = false
    self.showPathInput = false
    self.scrollToSelected = false

    if mode == "save" then
        self.write = true
        self.nameBuf = ffi.new("char[256]")
        ffi.copy(self.nameBuf, defaultName or "")
    else
        self.write = false
    end
    
    -- get available locations
    self:refreshLocations()
end

function FileBrowser:close()
    self._isOpen = false
end

local function sortEntries(a, b)
    if a.type == "directory" and b.type ~= "directory" then
        return true
    elseif a.type == b.type then
        return a.name < b.name
    end

    return false
end

function FileBrowser:pathToString(path)
    if self.root ~= nil then
        return path:toString()
    else
        return path:toSysString()
    end
end

function FileBrowser:setPath(newPath)
    local pathAsList = path.fromString(newPath):normalize()
    newPath = self:pathToString(pathAsList)
    
    local list = listDirectory(self.root, newPath)
    
    self.enterPath = false

    if self.write or self.multi then
        self.selected = {}
    else
        self.selected = {1}
    end

    self.path = newPath
    self.pathList = pathAsList
    self.entries = {}
    local filter = self.fileFilters[self.selectedFilter]
    
    for _, file in ipairs(list) do
        local fileName, fileType = file.name, file.type
        local hidden = false

        if fileName ~= ".." and fileName ~= "." then
            -- filter file name
            -- directories are not filtered
            local accepted = fileType == "directory"

            if not accepted then
                for i=2, #filter do
                    local str = filter[i]
                    
                    -- early exit
                    if str == "*.*" then
                        accepted = true
                        break
                    end

                    local filterL, filterR = string.match(str, "(.*)%.(.*)$")
                    local nameL, nameR = string.match(fileName, "(.*)%.(.*)$")

                    -- if file has no extension
                    if nameL == nil and nameR == nil and filterR == "*" then
                        if filterL == "*" or fileName == filterL then
                            accepted = true
                            break
                        end

                    -- if file starts with a dot
                    elseif nameL == nil and nameR ~= nil and filterL == "*" then
                        if filterR == "*" or nameR == filterR then
                            accepted = true
                            break
                        end

                    -- nameL and nameR are both present
                    else
                        if (filterL == "*" or nameL == filterL) and (filterR == "*" or nameR == filterR) then
                            accepted = true
                            break
                        end
                    end
                end
            end
            
            if accepted then
                table.insert(self.entries, {
                    name = fileName,
                    type = fileType,
                    hidden = hidden
                })
            end
        end
    end

    table.sort(self.entries, sortEntries)

    ffi.copy(self.pathBuf, self.path)
end

function FileBrowser:refreshLocations()
    self.locations = {}
    for i, v in pairs(self.bookmarks) do
        self.locations[i] = v
    end

    -- add drives
    if self.root == nil then
        if ffi.os == "Windows" then
            local drives = ffi.C.GetLogicalDrives()
            local mask = 1

            for i=0, 31 do
                -- if this drive letter exists
                if bit.band(drives, mask) ~= 0 then
                    local letter = string.sub(DRIVE_LETTERS, i+1, i+1)
                    table.insert(self.locations,
                        {letter .. ":", letter .. ":"}
                    )
                end

                mask = bit.lshift(mask, 1)
            end
        else
            table.insert(self.locations,
                {"File System", "/"}
            )
        end
    end
end

function FileBrowser:activateEntry(entry)
    if entry.type == "directory" then
        local oldPath = self.path
        local s, err = pcall(self.setPath, self, self.path .. path.separator .. entry.name)
        if s then
            table.insert(self.backStack, oldPath)
            self.forwardStack = {}
        else
            self.openErrorPopup = true
            self.errorMsg = "Could not open " .. entry.name
        end

        return nil
    else
        return self.path .. path.separator .. entry.name
    end
end

function FileBrowser:draw()
    if not self._isOpen then
        return
    end

    local isDone = false
    local callbackRes = nil

    if not self._isPopupOpen then
        imgui.OpenPopup_Str("File Browser")
        imgui.SetNextWindowSize(imgui.ImVec2_Float(imgui.GetTextLineHeight() * 60, imgui.GetTextLineHeight() * 30), imgui.ImGuiCond_FirstUseEver)
        self._isPopupOpen = true
    end

    if imgui.BeginPopupModal("File Browser", nil) then
        local windowSize = imgui.GetWindowSize()

        -- back button
        if imgui.ImageButton("##back", backIcon, imgui.ImVec2_Float(backIcon:getWidth(), backIcon:getHeight())) then
            if self.backStack[1] then
                local path = table.remove(self.backStack)
                table.insert(self.forwardStack, self.path)
                self:setPath(path)
            end
        end imgui.SameLine()

        -- forward button
        if imgui.ImageButton("##fwd", forwardIcon, imgui.ImVec2_Float(forwardIcon:getWidth(), forwardIcon:getHeight())) then
            if self.forwardStack[1] then
                local path = table.remove(self.forwardStack)
                table.insert(self.backStack, self.path)
                self:setPath(path)
            end
        end imgui.SameLine()

        -- parent button
        if imgui.ImageButton("##up", upIcon, imgui.ImVec2_Float(upIcon:getWidth(), upIcon:getHeight())) then
            -- if this is a system file browser, cannot pop off
            -- drive directory on Windows
            if self.root ~= nil or jit.os ~= "Windows" or self.pathList[2] ~= nil then
                table.insert(self.backStack, self.path)
                self.forwardStack = {}
                self:setPath(self.path .. "/..")
            end
        end imgui.SameLine()

        -- refresh button
        if imgui.Button("Refresh") then
            if not pcall(self.setPath, self, self.path) then
                self:setPath(GAME_DIRECTORY)
            end

            self:refreshLocations()
        end imgui.SameLine()

        -- current path
        if self.enterPath or self.showPathInput then
            if not self.enterPath then
                imgui.SetKeyboardFocusHere()
            end

            self.enterPath = true
            self.showPathInput = false

            imgui.SetNextItemWidth(-imgui.FLT_MIN)
            if imgui.InputText("###Path", self.pathBuf, 256, imgui.ImGuiInputTextFlags_EnterReturnsTrue) then
                local path = ffi.string(self.pathBuf)
                local s, err = pcall(self.setPath, self, path)

                if s then
                    self.enterPath = false
                else
                    self.openErrorPopup = true
                    self.errorMsg = "Could not open directory " .. path 
                end
            end
        else
            if imgui.Button("Type") then
                self.showPathInput = true
            end imgui.SameLine()

            if self.pathList[1] == nil then
                imgui.NewLine()
            else
                for i, ent in ipairs(self.pathList) do
                    if i > 1 then
                        imgui.SameLine()
                    end

                    imgui.PushID_Int(i)

                    if imgui.SmallButton(ent) then
                        table.insert(self.backStack, self.path)
                        self.forwardStack = {}
                        self:setPath(path.toString(self.pathList, 1, i))
                    end
                    
                    imgui.PopID()
                end
            end
        end

        local style = imgui.GetStyle()
        local listingHeight = windowSize.y - imgui.GetFrameHeightWithSpacing() * 3 + style.ItemSpacing.y * 1 - style.WindowPadding.y * 2

        -- list locations
        imgui.BeginChild_Str("Locations", imgui.ImVec2_Float(imgui.GetTextLineHeight() * 10, listingHeight), false)

        for _, location in ipairs(self.locations) do
            if imgui.Selectable_Bool(location[1], self.path == location[2]) then
                if self.path ~= location[2] then
                    table.insert(self.backStack, self.path)
                    self.forwardStack = {}
                    self:setPath(location[2])
                end
            end
        end

        -- end location list
        imgui.EndChild() imgui.SameLine()

        -- list files in current directory
        imgui.BeginChild_Str("Listing", imgui.ImVec2_Float(-imgui.FLT_MIN, listingHeight), true)

        -- ok action
        local ok = false

        local flags = imgui.ImGuiSelectableFlags_AllowDoubleClick
        for i, entry in ipairs(self.entries) do
            if string.sub(entry.name, 1, 1) ~= "." and not entry.hidden then
                local selectionIndex = util.table_find(self.selected, i)

                if entry.type then
                    local fileType = string.match(entry.name, "^.+%.(.*)$")
                    local fileTypeIcon = nil
                    
                    if fileType then
                        fileTypeIcon = fileTypeIcons[fileType]
                    end

                    local n

                    -- append a slash at the end if this is a directory
                    -- if this is a system browser, append the system separator
                    -- otherwise append the standard Forward Slash 
                    if self.root ~= nil then
                        n = entry.type == "directory" and entry.name .. "/" or entry.name
                    else
                        n = entry.type == "directory" and entry.name .. path.separator or entry.name
                    end
                    
                    if selectionIndex ~= nil and self.scrollToSelected then
                        imgui.SetScrollHereY()
                    end

                    imgui.Image(fileTypeIcon or (entry.type == "directory" and dirIcon or fileIcon), imgui.ImVec2_Float(13, 13))
                    imgui.SameLine()

                    if imgui.Selectable_Bool(string.format("%s", n), selectionIndex ~= nil, flags) then
                        if self.multi and (imgui.IsKeyDown(imgui.ImGuiKey_LeftCtrl) or imgui.IsKeyDown(imgui.ImGuiKey_RightCtrl)) then
                            if entry.type ~= "directory" then
                                if selectionIndex ~= nil then
                                    table.remove(self.selected, selectionIndex)
                                else
                                    table.insert(self.selected, i)
                                end
                            end
                        else
                            self.selected = {i}
                        end
                        
                        if self.write and entry.type ~= "directory" then
                            ffi.copy(self.nameBuf, entry.name)
                        end

                        if imgui.IsMouseDoubleClicked(0) then
                            ok = true
                        end
                    end
                else
                    imgui.Image(typeUnknown, imgui.ImVec2_Float(13, 13))
                    imgui.SameLine()
                    imgui.Selectable_Bool(entry.name, selectionIndex ~= nil, flags)
                end
            end
        end

        -- end entry list
        self.scrollToSelected = false
        imgui.EndChild()

        if imgui.Button("OK") then
            ok = true
        end imgui.SameLine()

        -- cancel button
        if imgui.Button("Cancel") then
            isDone = true
            callbackRes = nil
        end imgui.SameLine()

        -- file filter
        imgui.SetNextItemWidth(imgui.GetTextLineHeight() * 8)
        if imgui.BeginCombo("##filter", self.fileFilters[self.selectedFilter][1]) then
            for i, v in ipairs(self.fileFilters) do
                if imgui.Selectable_Bool(self.filterStrings[i], i == self.selectedFilter) then
                    self.selectedFilter = i
                    self:setPath(self.path) -- refresh listing
                end
                
                if i == self.selectedFilter then
                    imgui.SetItemDefaultFocus()
                end
            end

            imgui.EndCombo()
        end

        if self.write then
            imgui.SameLine()
            imgui.SetNextItemWidth(-imgui.FLT_MIN)

            local oldName = ffi.string(self.nameBuf)
            local enterPressed = imgui.InputTextWithHint("###Name", "File Name", self.nameBuf, 256, imgui.love.InputTextFlags("EnterReturnsTrue"))
            local newName = ffi.string(self.nameBuf)

            -- find a file/directory that has the same name
            if newName ~= oldName then
                self.selected = {}

                for i, entry in ipairs(self.entries) do
                    if entry.name == newName then
                        self.selected[1] = i
                        self.scrollToSelected = true
                        break
                    end
                end
            end

            if enterPressed then
                ok = true
            end
        end

        -- ok action
        if ok then
            if self.write then
                assert(self.nameBuf ~= nil)
                local name = ffi.string(self.nameBuf)

                -- save mode obviously does not support multi file selection
                -- so no need to check if the user has selected multiple files
                local entry = self.entries[self.selected[1]]

                if entry == nil or entry.type ~= "directory" then
                    if name ~= "" and name ~= "." and name ~= ".." then
                        -- modify name to match current filter
                        -- in write mode, each filter type should only have one filter string
                        -- so only check the first filter
                        local filter = self.fileFilters[self.selectedFilter]
                        local filterL, filterR = string.match(filter[2], "(.*)%.(.*)$")

                        if filter[2] ~= "*.*" and filterR ~= "*" then
                            local nameL, nameR = string.match(name, "(.*)%.(.*)$")

                            -- if no extension was given
                            if nameL == nil and nameR == nil then
                                name = name .. "." .. filterR
                            end
                        end

                        isDone = true
                        callbackRes = self:translatePath(self:pathToString(self.pathList + path.fromString(name)))
                    end

                -- open folder
                else
                    local p = self:activateEntry(entry)
                    if p then
                        isDone = true
                        callbackRes = self:translatePath(p)
                    end
                end

            -- file open mode
            else
                if self.multi then
                    -- if at least one file was selected
                    if self.selected[1] then
                        local firstEntry = self.entries[self.selected[1]]
                        
                        -- open a folder
                        if firstEntry.type == "directory" then
                            self:activateEntry(firstEntry)
                        else
                            isDone = true
                            callbackRes = {}

                            for k, i in ipairs(self.selected) do
                                local entry = self.entries[i]
                                callbackRes[k] = self:translatePath(self:pathToString(self.pathList + path.fromString(entry.name)))
                            end
                        end
                    end
                else
                    local entry = self.entries[self.selected[1]]
                    local p = self:activateEntry(entry)
                    if p then
                        isDone = true
                        callbackRes = self:translatePath(p)
                    end
                end
            end
        end

        -- close popup if finished
        if isDone then
            imgui.CloseCurrentPopup()
        end

        if self.openErrorPopup then
            self.openErrorPopup = false
            imgui.OpenPopup_Str("Error")
        end

        if imgui.BeginPopupModal("Error", nil, imgui.love.WindowFlags("AlwaysAutoResize", "NoSavedSettings")) then
            imgui.Text(self.errorMsg)
            if imgui.Button("OK") then
                imgui.CloseCurrentPopup()
            end

            imgui.EndPopup()
        end

        imgui.EndPopup()
    end
    
    if isDone and self.callback then
        if callbackRes then
            self.lastDirectory = self.path
        end

        self.callback(callbackRes)
        self:close()
    end
end

function FileBrowser:fullPath(path)
    if self.root == nil then
        return path
    else
        return self.root .. path
    end
end

function FileBrowser:translatePath(path)
    if self.returnFullPath then
        return self:fullPath(path)
    else
        return path
    end
end

local fileInputReturns = {}

function FileBrowser:fileInput(id, filter, data)
    local fullId = imgui.GetID_Str(id)

    imgui.PushStyleVar_Vec2(imgui.ImGuiStyleVar_ItemSpacing, imgui.ImVec2_Float(2, 2))

    if imgui.ImageButton(id, dirIcon, imgui.ImVec2_Float(fileIcon:getWidth(), fileIcon:getHeight())) then
        self:open("open", filter, function(newPath)
            fileInputReturns[fullId] = newPath
        end)
    end

    -- delete button
    imgui.SameLine()
    if imgui.ImageButton("X##delete-" .. id, deleteIcon, imgui.ImVec2_Float(deleteIcon:getWidth(), deleteIcon:getHeight())) then
        if data[1] ~= nil then
            fileInputReturns[fullId] = ""
        end
    end

    imgui.PopStyleVar()
    
    -- get file name
    local name = "No file selected"
    if data[1] then
        name = string.match(data[1], "^.+[/\\](.+)$")
    end

    imgui.SameLine()
    imgui.AlignTextToFramePadding()
    imgui.Text("%s", name)

    if fileInputReturns[fullId] then
        local val = fileInputReturns[fullId]
        fileInputReturns[fullId] = nil

        if val == "" then
            data[1] = nil
        else
            data[1] = val
        end

        return true
    end

    return false
end

return FileBrowser