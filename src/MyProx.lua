-- < Soon to be on somewhere like aftman > --

export type MyProx = {
    new: (data: {[any]: any}, public: {[any]: any}?) -> (any, {[any]: any})
}


local MyProx = {}
local Index, NewIndex


Index = function(proxy, index)
    local metatable = getmetatable(proxy)
    local data = metatable.__get[index]

    if data ~= nil then
        return data(proxy, metatable)
    end

    data = metatable.__public[index]
    return if data ~= nil then data else metatable.__shared[index]
end
NewIndex = function(proxy, index, value)
    local metatable = getmetatable(proxy)
    local set = metatable.__set[index]
    if set == nil then
        metatable.__public[index] = value
    elseif set == false then
        error("Attempt to set a read only value", 2)
    else
        set(proxy, metatable, value)
    end
end



MyProx.new = function(data, public)
    local proxy = newproxy(true)
    local metatable = getmetatable(proxy)

    for index, value in data do
        metatable[index] = value
    end

    metatable.__index = Index
    metatable.__newindex = NewIndex
    metatable.__public = metatable.__public or {}

    if public then
        for index, value in public do
            metatable.__public[index] = value
        end
    end


   return proxy, metatable
end

--[[
    local table = {}
    table.__public = {} -- What the user will be able to interact with.
    table.__shared = {} -- functions that the user can see, but can not modify in any way.
    table.__get = {} -- Custom index functions. Like pythons @property.get decorator
    table.__set = {} -- Custom set functions, or read only set ability
]]

return table.freeze(MyProx) :: MyProx