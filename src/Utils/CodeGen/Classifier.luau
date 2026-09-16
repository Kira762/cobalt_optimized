
local MethodLookupTable = {
	Incoming = {
		RemoteEvent = "OnClientEvent",
		RemoteFunction = "OnClientInvoke",
		UnreliableRemoteEvent = "OnClientEvent",
		BindableEvent = "Event",
		BindableFunction = "OnInvoke",
	},
	Outgoing = {
		RemoteEvent = "FireServer",
		RemoteFunction = "InvokeServer",
		UnreliableRemoteEvent = "FireServer",
		BindableEvent = "Fire",
		BindableFunction = "Invoke",
	},

	
	Bidirectional = {
		RemoteFunction = {
			Request = "InvokeServer",
			SSE = "OnClientInvoke",
		},
		BindableFunction = {
			Request = "Invoke",
			SSE = "OnInvoke",
		},
	},
}


local Types = require(script.Parent.Types)


local function CanEventContainCallbackValue(Instance: Instance)
	return (Instance.ClassName == "RemoteFunction" or Instance.ClassName == "BindableFunction")
end

local function BuildTemplateScenario(CallInfo: Types.CallInfo, Data)
	local Method = MethodLookupTable[CallInfo.Type][CallInfo.Instance.ClassName]

	
	local BidirectionalLookup = MethodLookupTable.Bidirectional[CallInfo.Instance.ClassName]

	if BidirectionalLookup and Data.Shape then
		Method = BidirectionalLookup[Data.Shape]
	end

	
	local Scenario = {
		Type = CallInfo.Type,
		Direction = CallInfo.Type,
		Class = CallInfo.Instance.ClassName,
		Method = Method,
		InvokeKind = CallInfo.InvokeKind,
		Error = CallInfo.Error,
		IsActor = CallInfo.IsActor,
		Actor = CallInfo.Actor,
	}

	
	for Key, Value in Data do
		Scenario[Key] = Value
	end

	return Scenario
end


local Classifier = {}
Classifier.MethodLookupTable = MethodLookupTable


function Classifier.DetermineScenario(CallInfo: Types.CallInfo): Types.Scenario
	local Type = CallInfo.Type

	
	if Type == "Incoming" then
		
		if CanEventContainCallbackValue(CallInfo.Instance) then
			
			if CallInfo.InvokeKind ~= "Request" then
				return BuildTemplateScenario(CallInfo, {
					Arguments = CallInfo.Arguments,
					Result = CallInfo.InvokeResult,

					Shape = "SSE",
				})
			end

			
			return BuildTemplateScenario(CallInfo, {
				Arguments = CallInfo.Arguments,
				Result = CallInfo.InvokeResult,

				Shape = "Request",
			})
		end

		
		return BuildTemplateScenario(CallInfo, {
			Arguments = CallInfo.Arguments,

			Shape = "Signal",
		})
	end

	
	return BuildTemplateScenario(CallInfo, {
		Arguments = CallInfo.Arguments,

		Shape = "Request",
	})
end

return Classifier
