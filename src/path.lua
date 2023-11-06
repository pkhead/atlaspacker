-- path module
local path = {}
path.__index = path

path.separator = jit.os == "Windows" and "\\" or "/"

local path_mt = {}
path_mt.__index = path

function path.fromString(pathStr)
    local out = setmetatable({}, path_mt)
    for ent in string.gmatch(pathStr, "([^/\\\\]+)") do
        table.insert(out, ent)
    end
    return out
end

function path:toSysString(i, j)
    assert(getmetatable(self) == path_mt, "argument #1 is not a path")

    local join = table.concat(self, path.separator, i, j)

    if jit.os == "Windows" then
        return join
    else
        return path.separator .. join
    end
end

function path:toString(i, j)
    assert(getmetatable(self) == path_mt, "argument #1 is not a path")

    local join = table.concat(self, "/", i, j)
    return path.separator .. join
end

function path:normalize()
    assert(getmetatable(self) == path_mt, "argument #1 is not a path")
    
    local new = {}

    for _, v in ipairs(self) do
        if v == ".." then
            table.remove(new)
        elseif v ~= "." then
            table.insert(new, v)
        end
    end

    return setmetatable(new, path_mt)
end

function path:join(path2)
    assert(getmetatable(self) == path_mt, "argument #1 is not a path")
    assert(getmetatable(path2) == path_mt, "argument #2 is not a path")

    local new = {}
    
    for i, v in ipairs(self) do
        new[i] = v
    end

    for _, v in ipairs(path2) do
        if v == ".." then
            table.remove(new)
        elseif v ~= "." then
            table.insert(new, v)
        end
    end

    return setmetatable(new, path_mt)
end

path_mt.__tostring = path.toString
path_mt.__add = path.join

return path