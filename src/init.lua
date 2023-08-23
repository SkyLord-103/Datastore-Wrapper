local DataStoreService, HTTPService = game:GetService("DataStoreService"), game:GetService("HttpService")

local MyProx, Signal, Response = require(script.MyProx), require(script.Signal), require(script.Response)


---@diagnostic disable-next-line
type Response = Response.Response
---@diagnostic disable-next-line
type Responses = Response.Responses

Response = Response :: Responses

export type Constructor = {
	Response: Responses,

	DataStore: (name: string, scope: string?, options: DataStoreOptions?) -> CDataStore,
	OrderedStore: (name: string, scope: string?, options: DataStoreOptions?) -> COrderedStore,
	KeyStore: (name: string, scope: string, key: string?) -> KeyStore,
	find: (name: string, scope: string?, ordered: boolean?) -> CDataStore | COrderedStore
}

export type CDataStore = {
	State: boolean?,
	Id: string,
	UniqueId: string,
	DataStore: DataStore,

	Get: (CDataStore, key: string, defaultValue: any) -> (Response, any),
	Save: (CDataStore, key: string, value: any, options: DataStoreSetOptions?) -> Response,
	Update: (CDataStore, key: string, updateCallback: (any)-> any) -> (Response, any),
	Remove: (CDataStore, key: string) -> Response,
	Usage: (data: any, compressed: boolean?) -> (number, number),

	Saving: Signal.Signal,
	Saved: Signal.Signal,
	Closing: Signal.Signal,

	Close: (CDataStore) -> (),
}

export type COrderedStore = {
	State: boolean?,
	Id: string,
	UniqueId: string,
	DataStore: OrderedDataStore,

	Get: (COrderedStore, key: string, defaultValue: any) -> (Response, any),
	Save: (COrderedStore, key: string, value: any, options: DataStoreSetOptions?) -> Response,
	Update: (COrderedStore, key: string, updateCallback: (any)-> any) -> (Response, any),
	Remove: (COrderedStore, key: string) -> Response,
	Usage: (data: any, compressed: boolean?) -> (number, number),

	Saving: Signal.Signal,
	Saved: Signal.Signal,
	Closing: Signal.Signal,

	Close: (COrderedStore) -> (),
}


type DataStoreOrOrdered = DataStore | OrderedDataStore
type Key = string | number
type util = {
	GetAsync: (datastore: DataStoreOrOrdered, key: Key) -> (Response, any),
	SetAsync: (datastore: DataStoreOrOrdered, key: Key, value: any) -> Response,
	UpdateAsync: (datastore: DataStoreOrOrdered, key: Key, callback: (curValue: any, dsKeyInfo: DataStoreKeyInfo) -> any) -> (Response, any),
	RemoveAsync: (datastore: DataStoreOrOrdered, key: Key) -> Response,
	retry: (retries: (number?) | {retries: number?, wait: number?}, callback: (...any) -> ...any, ...any) -> (any, boolean),
}



local Constructor: Constructor = {}
local DataStore, OrderedStore = {}, {}
local datastores, bindToClose = {}, {}
local UTIL = {}


Constructor.Response = Response
Constructor.DataStore = function(name, scope, options)
	assert(name ~= nil, "name cannot be nil")
	options = if options == nil then Instance.new("DataStoreOptions") else options

	assert(typeof(scope) == 'string' or scope == nil, 'scope must be of type string or nil')
	assert(typeof(options) == 'Instance' and options.ClassName == 'DataStoreOptions', 'options must be of type DataStoreOptions')

	local id = name .. '/' .. (scope or '')
	if datastores['DataStore/' .. id] then
		return datastores['DataStore/' .. id]
	end

	local proxy, _ = MyProx.new(DataStore, {
		State = true,
		Id = id,
		UniqueId = HTTPService:GenerateGUID(false),

		DataStore = DataStoreService:GetDataStore(name, scope, options),

		Saving = Signal.new(),
		Saved = Signal.new(),
		StateChanged = Signal.new()
	})

	datastores['DataStore/' .. id] = proxy

	return proxy
end

Constructor.OrderedStore = function(name, scope)
	assert(name ~= nil, "name cannot be nil")
	assert(typeof(scope) == 'string' or scope == nil, 'scope must be of type string or nil')

	local id = name .. '/' .. (scope or '')
	if datastores['OrderedStore/' .. id] then
		return datastores['OrderedStore/' .. id]
	end

	local proxy, _ = MyProx.new(OrderedStore, {
		State = true,
		Id = id,
		UniqueId = HTTPService:GenerateGUID(false),

        DataStore = DataStoreService:GetOrderedDataStore(name, scope),

		Saving = Signal.new(),
		Saved = Signal.new(),
		StateChanged = Signal.new()
	})

	datastores['OrderedStore/' .. id] = proxy

	return proxy
end

---@param name string
---@param scope string
---@param datastoreType string
---| "DataStore"
---| "OrderedStore"
Constructor.find = function(name, scope, datastoreType)
	return datastores[datastoreType .. '/' .. (name .. '/' .. scope)]
end


-- DataStore
DataStore.__tostring = function(proxy)
	return "DataStore/" .. proxy.Id
end

DataStore.__public = {}

DataStore.__shared = {
	Get = function(proxy, key, defaultValue)
		if proxy.State == nil then return Response.Closed end

		return UTIL.GetAsync(proxy.DataStore, key, defaultValue)
	end,
	Save = function(proxy, key, value)
		if proxy.State == nil then return Response.Closed end
		proxy.Saving:Fire(proxy, key, value)

		local res, v = UTIL.SetAsync(proxy.DataStore, key, value)
		proxy.Saved:Fire(proxy, key, value)
		return res, v
	end,
	Update = function(proxy, key, callback)
		if proxy.State == nil then return Response.Closed end
		proxy.Saving:Fire(proxy, key)

		local res, v = UTIL.UpdateAsync(proxy.DataStore, key, callback)
		proxy.Saved:Fire(proxy, key)
		return res, v
	end,
	Remove = function(proxy, key)
		if proxy.State == nil then return Response.Closed end

		return UTIL.RemoveAsync(proxy.DataStore, key)
	end,
	Usage = function(_, data)
		local characters = #HTTPService:JSONEncode(data)
		return characters, characters / 4194303
		-- if compressed then
		-- else
		-- end
	end,
	Close = function(proxy)
		if proxy.State == nil then return Response.Closed end
		proxy.Closing:Fire()

		local metatable = getmetatable(proxy)
		metatable.State = nil
		return Response.Success
	end
}

DataStore.__get = {}

DataStore.__set = {
	State = false,
	Id = false,
	UniqueId = false,
	DataStore = false,
	Saving = false,
	Saved = false,
	StateChanged = false
}


-- OrderedStore
-- Coming soon


-- UTIL

---Runs the given `callback` with the optional arguments and if an error is thrown will call the `callback` `retries` amount of times
---@param retries? number The amount of times to retry the callback if it errors
---@param callback function The callback that will be called
---@return boolean success, any result
UTIL.retry = function(retries, callback, ...)
	local retries_, wait_ = 3, 1
	if typeof(retries) == 'table' then
		retries_ = retries['retries'] or 3
		wait_ = retries['wait'] or 1
	else
		retries_ = retries_ or 3
	end

	local args = {...}
	local success, result
	for i = 0, math.abs(retries_) + 1 do
		success, result = pcall(function()
			return callback(unpack(args))
		end)
		if success then break end
		task.wait(wait_)
	end

	return success, result
end

---Calls :GetAsync on the given datastore, and retries if fails\nif data is nil or failed to call DataStoreService it returns the optional `default`
---@param ds DataStore|OrderedDataStore The datastore to run :GetAsync on
---@param key string The key
---@param default? string default data if value at key is nil
---@return Response, any
UTIL.GetAsync = function(ds, key, default)
	local success, data = UTIL.retry(3, function()
		return ds:GetAsync(key)
	end)

	if success then
		return Response.Success, if data == nil then default else data
	else
		return Response.Failure('Failed GetAsync. Returning default if any'), default
	end
end

---Calls :SetAsync on the given datastore, and retries if fails
---@param ds DataStore|OrderedDataStore The datastore to run :SetAsync on
---@param key string The key
---@param value any Data to be saved
---@return Response
UTIL.SetAsync = function(ds, key, value)
	local success, m = UTIL.retry(3, function()
		return ds:SetAsync(key, value)
	end)

	return if success then Response.Success else Response.Failure(m)
end

---Calls :UpdateAsync on the given datastore, and retries if fails
---@param ds DataStore|OrderedDataStore The datastore to run :UpdateAsync on
---@param key string The key
---@param callback any The callback UpdateAsync will call
---@return Response
---@return any
UTIL.UpdateAsync = function(ds, key, callback)
	local success, m = UTIL.retry(3, function()
		return ds:UpdateAsync(key, callback)
	end)

	if success then
		return Response.Success, m
	else
		return Response.Failure(m), nil
	end
end

---Calls :RemoveAsync on the given datastore, and retries if fails
---@param ds DataStore|OrderedDataStore The datastore to run :RemoveAsync on
---@param key string The key
---@return Response
UTIL.RemoveAsync = function(ds, key)
	local success, m = UTIL.retry(3, function()
		return ds:RemoveAsync(key)
	end)

	return if success then Response.Success else Response.Failure(m)
end


game:BindToClose(function()
	for _, store in bindToClose do
		if store.State == nil then continue end
		store:Close()
	end
end)


return table.freeze(Constructor) :: Constructor
