
local LookupModule = require("@src/Utils/Hook/RakNet/Lookup")
local raknet = require("@src/Utils/Hook/RakNet/Wrapper")
local InvocationTracker = require(script.InvocationTracker)

return function()
	
	LookupModule.Instance.Build()

	local Requests = {
		Incoming = InvocationTracker.new(),
		Outgoing = InvocationTracker.new(),
	}

	
	for _, Interceptor in script.Interceptors:GetChildren() do
		require(Interceptor)(Requests)
	end

	
	return function()
		Requests.Incoming:Clear()
		Requests.Outgoing:Clear()

		LookupModule.Instance.Destroy()
		raknet.remove_all_hooks()
	end
end
