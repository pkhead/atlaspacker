--[[
rect packer module
--]]

local util = require("util")

---@alias Rect {x: number, y: number, w: number, h: number}
---@param rects Rect[]
return function(rects)
	if rects[1] == nil then
		return rects
	end
	
	local rectsSorted = util.table_copy(rects)

	---@param a Rect
	---@param b Rect
	table.sort(rectsSorted, function(a, b)
		return b.h < a.h
	end)

	local totalArea = 0
	for _, rect in ipairs(rects) do
		totalArea = totalArea + rect.w * rect.h
	end

	local packW = math.sqrt(totalArea)

	local x = 1
	local y = 1
	local rowH = 0
	for _, rect in ipairs(rectsSorted) do
		rect.x = x
		rect.y = y
		x = x + rect.w + 1

		if rowH == 0 then
			rowH = rect.h
		end

		if x > packW then
			x = 1
			y = y + rowH + 1
			rowH = 0
		end
	end

	return rects
end
