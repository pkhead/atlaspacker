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
        print(" --to-ase [atlas] [ase]\t\tconvert an atlas file to an aseprite file")
        print(" --to-pngjson [atlas] [png]\tconvert an atlas file to a png and json file")
        print(" --from-pngjson [png] [atlas]\tconvert a png and json file to an atlas file")
        return
    end
    
    if args[1] == "--to-ase" then
        if args[2] == nil then
            error("argument #2 is missing", 2)
        end

        if args[3] == nil then
            error("argument #3 is missing", 2)
        end

        local workspace = Workspace.load(Atlas.read(args[2], "atlas", true))
        local data = Aseprite.export(workspace)

        local file, err = io.open(args[3], "wb")
        if not file then
            error(file, 2)
        end

        file:write(data)
        file:close()
        return
    end

    if args[1] == "--to-pngjson" then
        if args[2] == nil then
            error("argument #2 is missing", 2)
        end

        if args[3] == nil then
            error("argument #3 is missing", 2)
        end

        local workspace = Workspace.load(Atlas.read(args[2], "atlas", true))
        Atlas.write(args[3], "json", workspace)
        
        return
    end

    if args[1] == "--from-pngjson" then
        if args[2] == nil then
            error("argument #2 is missing", 2)
        end

        if args[3] == nil then
            error("argument #3 is missing", 2)
        end

        local workspace = Workspace.load(Atlas.read(args[2], "json", true))
        Atlas.write(args[3], "atlas", workspace)
        
        return
    end

    error(("unknown argument '%s'"):format(args[1]), 2)
end