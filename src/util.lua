local util = {}

function util.table_find(t, q, i)
    for k=(i or 1), #t do
        if t[k] == q then
            return k
        end
    end
    return nil
end

function util.tableRemoveItem(t, q, i)
    for k=(i or 1), #t do
        if t[k] == q then
            table.remove(t, k)
        end
    end
end

function util.table_copy(t)
    local new = {}
    for i, v in pairs(t) do
        new[i] = v
    end
    return new
end

function util.table_deep_copy(t)
    local new = {}
    for i, v in pairs(t) do
        if type(v) == "table" then
            new[i] = util.table_deep_copy(v)
        else
            new[i] = v
        end
    end
    return new
end

function util.aabbIntersects(x0, y0, w0, h0, x1, y1, w1, h1)
    return
        x0 < x1 + w1 and
        x0 + w0 > x1 and
        y0 < y1 + h1 and
        y0 + h0 > y1
end

function util.pointInAABB(x, y, w, h, a, b)
    return
        a > x and
        b > y and
        a < x + w and
        b < y + h
end

function util.clamp(v, min, max)
    if v > max then
        return max
    elseif v < min then
        return min
    end
    return v
end

-- util.lua is not the best place to put this
util.ATLAS_FILE_FILTERS = {
    {"Atlas", "*.atlas"},
    {"Any", "*.*"}
}

util.IMAGE_FILE_FILTERS = {
    {"Image", "*.png", "*.jpg", "*.jpeg", "*.bmp", "*.tga", "*.hdr", "*.pic", "*.exr"},
    {"Any", "*.*"}
}

util.SOUND_FILE_FILTERS = {
    {"Audio", "*.mp3", "*.ogg", "*.wav"},
    {"Any", "*.*"}
}

util.MUSIC_FILE_FILTERS = {
    {"Audio", "*.mp3", "*.ogg", "*.wav"},
    {"Tracker Module", "*.mod", "*.s3m", "*.xm", "*.it"},
    {"Any", "*.*"}
}

return util