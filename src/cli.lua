local Atlas = require("atlas")
local Workspace = require("workspace")
local Aseprite = require("ase")

return function(args)
    if args[1] == "--help" then
        print("atlaspacker - atlas packing utility")
        print("run with no arguments to launch GUI")
        print("")
        print("commands:")
        print(" --help\t\t\t\tshow this help text")
        print(" --convert-ase [atlas] [ase]\tconvert an atlas file to an aseprite file")
        return
    end

    local i = 1
    local argCount = #args
    while i <= argCount do
        local arg = args[i]
        
        if arg == "--convert-ase" then
            local workspace = Workspace.load(Atlas.read(args[i+1], "atlas", true))
            local data = Aseprite.export(workspace)

            local file, err = io.open(args[i+2], "wb")
            if not file then
                error(file, 2)
            end

            file:write(data)
            file:close()

            i=i+2
        else
            error(("unknown argument '%s'"):format(arg), 2)
        end

        i=i+1
    end
end