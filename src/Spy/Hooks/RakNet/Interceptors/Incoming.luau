
local raknet = require("@src/Utils/Hook/RakNet/Wrapper")
local Constants = require("@src/Utils/Hook/RakNet/Constants")
local ProcessPacket = require("@src/Spy/Hooks/RakNet/PacketProcessor")


local InvocationTracker = require("@src/Spy/Hooks/RakNet/InvocationTracker")
local InterceptorUtils = require("@src/Spy/Hooks/RakNet/InterceptorUtils")


type Requests = {
	Incoming: InvocationTracker.Tracker,
	Outgoing: InvocationTracker.Tracker,
}


local function CreateHandler(Requests: Requests)
	return function(Instance: Instance, Payload: ProcessPacket.Payload): boolean
		local ShouldCapture = not wax.shared.ShouldIgnore(Instance, nil)

		if Payload.Type == "RemoteFunction" then
			local Response = Payload.Response

			
			local OutgoingRequest = Requests.Outgoing:Consume(Instance, Response.InvokeId)
			if OutgoingRequest then
				if OutgoingRequest.ShouldLog == false then
					return false
				end

				local Log = InterceptorUtils.GetLog(Instance, "Incoming")
				local Info = {
					Arguments = OutgoingRequest.Arguments,
					InvokeResult = InterceptorUtils.PackArguments(Response.Arguments),
					Error = Response.Error,
					Origin = nil,
					Function = nil,
					Line = nil,
					Source = nil,
					IsExecutor = nil,
					IsRakNet = true,
					InvokeKind = "Request",
				}
				local ShouldBlock = Log:ShouldBlock(Info)
				Log:Call(Info)
				if ShouldBlock then
					return true
				end

				return false
			end

			
			local Log = InterceptorUtils.GetLog(Instance, "Incoming")
			local Info = {
				Arguments = InterceptorUtils.PackArguments(Response.Arguments),
				InvokeResult = nil,
				Error = Response.Error,
				Origin = nil,
				Function = nil,
				Line = nil,
				Source = nil,
				IsExecutor = nil,
				IsRakNet = true,
				InvokeKind = "Callback",
			}
			if Log:ShouldBlock(Info) then
				Log:Call(Info)
				return true
			end

			Requests.Incoming:Add(Instance, Response.InvokeId, {
				Info = Info,
				Instance = Instance,
				ShouldLog = ShouldCapture,
			})
			return false
		end

		
		
		if not ShouldCapture then
			return false
		end

		local Log = InterceptorUtils.GetLog(Instance, "Incoming")
		local Info = {
			Arguments = InterceptorUtils.PackArguments(Payload.Arguments),
			Origin = nil,
			Function = nil,
			Line = nil,
			Source = nil,
			IsExecutor = nil,
			IsRakNet = true,
			Omit = true
		}
		local ShouldBlock = Log:ShouldBlock(Info)
		Log:Call(Info)
		if ShouldBlock then
			return true
		end

		return false
	end
end


return function(Requests: Requests)
	local HandlePayload = CreateHandler(Requests)
	return raknet.add_receive_hook(Constants.PacketIds.ID_DATA, function(Message: raknet.RakNetMessage)
		ProcessPacket(Message, HandlePayload, function(Instance, InvokeId)
			return Requests.Outgoing:Has(Instance, InvokeId)
		end)
	end)
end
