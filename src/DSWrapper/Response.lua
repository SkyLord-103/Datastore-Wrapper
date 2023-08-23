local typeof = require(game.ReplicatedStorage.Typeof)


export type Response = {
    name: string,
    msg: string,
    b: boolean,
    cmp: (t: Response | boolean) -> boolean,
    __call: (msg: string) -> Response,
}
export type Responses = {
    Success : Response,
    Saved   : Response,
    Failure : Response,
    Unknown : Response,
    Closed  : Response,
}


local MyProx = require(script.Parent.MyProx)

local Response = {}

Response.__type = "Response"
Response.__tostring = function(proxy)
    return proxy.name .. (if proxy.msg == '' then '' else ' :: ' .. proxy.msg)
end
Response.__eq = function(proxy, other)
    return proxy.id == other.id
end
Response.__call = function(proxy, newMsg)
    return newResponse(proxy.name, proxy.b, newMsg, proxy.id)
end


function newResponse(name, boolValue: boolean?, msg: string?, id: string?): Response
    local response, metatable = MyProx.new(Response, {})

    metatable.__shared = {
        id = id or game:GetService("HttpService"):GenerateGUID(false),
        msg = msg or '',
        name = name,
        b = if boolValue == nil then false else boolValue,
        cmp = function(object)
            local ot = typeof(object)
            assert(ot == 'Response' or ot == 'boolean' or ot == 'string', 'Can only call cmp with obj type Response or boolean')

            if ot == 'Response' then
                return response.id == object.id
            elseif ot == 'boolean' then
                return response.b == object
            elseif ot == 'string' then
                return response.name == object
            end
        end
    }

	return response
end


return {
	Success = newResponse("Success", true),
	Saved   = newResponse("Saved", true),
	Failure = newResponse("Failure", false),
	Closed  = newResponse("Closed", false),
	Unknown = newResponse("Unknown", false),
} :: Responses