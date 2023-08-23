local oldTypeof = typeof

local function typeof<T>(value: T): string
	local oType = oldTypeof(value)
	if oType ~= "table" and oType ~= "userdata" then return oType end

	local metatable = getmetatable(value)
	if oldTypeof(metatable) ~= "table" then return oType end

	local customType = metatable["__type"]
	if customType == nil then return oType end

	return customType

end

return typeof