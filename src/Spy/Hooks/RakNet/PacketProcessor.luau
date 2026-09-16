
local raknet = require("@src/Utils/Hook/RakNet/Wrapper")
local Constants = require("@src/Utils/Hook/RakNet/Constants")


local Lookup = require("@src/Utils/Hook/RakNet/Lookup")
local Codec = require("@src/Utils/Hook/RakNet/Codec")
local Parser = require("@src/Utils/Hook/RakNet/Variant/Parser")


local ItemTypes = Constants.ItemTypes

type ByteRange = {
	Start: number,
	Finish: number,
}

export type RemoteFunctionPayload = {
	Type: "RemoteFunction",
	Response: Parser.RemoteFunctionPayload,
	Offset: number,
}

export type ArgumentsPayload = {
	Type: "Arguments",
	Arguments: Parser.Arguments,
	Offset: number,
}

export type Payload = RemoteFunctionPayload | ArgumentsPayload

type IsRemoteFunctionResponse = (Instance: Instance, InvokeId: number) -> boolean

local SupportedInstanceTypes = {
	RemoteEvent = true,
	RemoteFunction = true,
	UnreliableRemoteEvent = true,
}

local function IsInvocationItem(ItemType: number): boolean
	return ItemType == ItemTypes.ReliableEventInvocationItem
	or ItemType == ItemTypes.UnreliableEventInvocationItem
end

local function ParseItem(
	Data: buffer,
	Length: number,
	ItemStart: number,
	IsResponse: IsRemoteFunctionResponse?
)
	local Offset = ItemStart
	local ItemType = buffer.readu8(Data, Offset)
	Offset += 1

	if not IsInvocationItem(ItemType) then
		return {
			Stop = true,
			Reason = "unsupported item type",
			ItemType = ItemType,
			CurrentOffset = Offset,
		}
	end

	local InstanceRef, NextOffset = Codec.ReadInstanceRef(Data, Offset)
	Offset = NextOffset

	if InstanceRef.is_null or Offset + 2 > Length then
		return {
			Stop = true,
			Reason = if InstanceRef.is_null then "null instance reference" else "scope id exceeds packet",
			ItemType = ItemType,
			InstanceRef = InstanceRef,
			CurrentOffset = Offset,
		}
	end

	local ScopeId = buffer.readu16(Data, Offset)
	Offset += 2

	local Instance = Lookup.Instance.ByRef(InstanceRef)
	if not Instance or not SupportedInstanceTypes[Instance.ClassName] then
		return {
			Stop = true,
			Reason = "instance lookup failed",
			ItemType = ItemType,
			InstanceRef = InstanceRef,
			ScopeId = ScopeId,
			CurrentOffset = Offset,
		}
	end

	local PayloadParser = Parser.new(Data)
	local Payload: Payload
	if Instance:IsA("RemoteFunction") then
		local InvokeId = Codec.LEB128(Data, Offset)
		local Response = PayloadParser:ParseRemoteFunction(
			Offset,
			IsResponse ~= nil and IsResponse(Instance, InvokeId)
		)
		Payload = {
			Type = "RemoteFunction",
			Response = Response,
			Offset = Response.Offset,
		}
	else
		local Arguments = PayloadParser:ParseArgs(Offset)
		Payload = {
			Type = "Arguments",
			Arguments = {
				Values = Arguments.Values,
				Count = Arguments.Count,
			},
			Offset = Arguments.Offset,
		}
	end

	if Payload.Offset <= Offset or Payload.Offset > Length then
		return {
			Stop = true,
			Reason = "payload offset is invalid",
			ItemType = ItemType,
			InstanceRef = InstanceRef,
			ScopeId = ScopeId,
			Instance = Instance,
			Payload = Payload,
			PayloadStart = Offset,
			PacketLength = Length,
			CurrentOffset = Offset,
		}
	end

	return {
		ItemType = ItemType,
		InstanceRef = InstanceRef,
		ScopeId = ScopeId,
		Instance = Instance,
		Payload = Payload,
		PayloadStart = Offset,
	}
end

local function TryParseItem(
	Data: buffer,
	Length: number,
	ItemStart: number,
	IsResponse: IsRemoteFunctionResponse?
)
	local Success, Result = pcall(ParseItem, Data, Length, ItemStart, IsResponse)
	if not Success then
		return nil, {
			Stop = true,
			Reason = "item parser errored",
			Error = Result,
			CurrentOffset = ItemStart,
		}
	elseif Result.Stop then
		return nil, Result
	end

	return Result, nil
end

local function IsPlausibleBoundary(Data: buffer, Length: number, Offset: number): boolean
	if Offset >= Length then
		return true
	end

	local NextItemType = buffer.readu8(Data, Offset)
	return NextItemType == 0 or IsInvocationItem(NextItemType)
end

local function FindNextInvocation(
	Data: buffer,
	Length: number,
	StartOffset: number,
	IsResponse: IsRemoteFunctionResponse?
)
	for Candidate = StartOffset, Length - 1 do
		if not IsInvocationItem(buffer.readu8(Data, Candidate)) then
			continue
		end

		local Parsed = TryParseItem(Data, Length, Candidate, IsResponse)
		if Parsed and IsPlausibleBoundary(Data, Length, Parsed.Payload.Offset) then
			return Candidate, Parsed
		end
	end

	return nil, nil
end

local function RewriteWithoutRanges(Message: raknet.RakNetMessage, Data: buffer, Length: number, Ranges: { ByteRange })
	local RemovedLength = 0
	for _, Range in Ranges do
		RemovedLength += Range.Finish - Range.Start
	end

	local NewLength = Length - RemovedLength
	if NewLength <= 1 then
		Message:Block()
		return
	end

	local Rewritten = buffer.create(NewLength)
	local SourceOffset = 0
	local DestinationOffset = 0

	for _, Range in Ranges do
		local CopyLength = Range.Start - SourceOffset
		if CopyLength > 0 then
			buffer.copy(Rewritten, DestinationOffset, Data, SourceOffset, CopyLength)
			DestinationOffset += CopyLength
		end

		SourceOffset = Range.Finish
	end

	local RemainingLength = Length - SourceOffset
	if RemainingLength > 0 then
		buffer.copy(Rewritten, DestinationOffset, Data, SourceOffset, RemainingLength)
	end

	Message:SetData(Rewritten)
end


return function(
	Message: raknet.RakNetMessage,
	Postprocess: (Instance: Instance, Payload: Payload, Message: raknet.RakNetMessage) -> boolean?,
	IsResponse: IsRemoteFunctionResponse?
)
	local Data = Message.AsBuffer
	local Length = buffer.len(Data)
	if Length < 2 then
		return
	end

	local BlockedRanges: { ByteRange } = {}
	local Offset = 1
	while Offset < Length do
		local ItemStart = Offset
		local Parsed, Failure = TryParseItem(Data, Length, ItemStart, IsResponse)
		if not Parsed then
			local RecoveredStart, Recovered = FindNextInvocation(Data, Length, ItemStart + 1, IsResponse)
			if RecoveredStart and Recovered then
				ItemStart = RecoveredStart
				Parsed = Recovered
			else
				break
			end
		end

		local ItemEnd = Parsed.Payload.Offset

		local ShouldBlock = Postprocess(Parsed.Instance, Parsed.Payload, Message)
		if ShouldBlock then
			table.insert(BlockedRanges, {
				Start = ItemStart,
				Finish = ItemEnd,
			})
		end

		Offset = ItemEnd
	end

	if #BlockedRanges > 0 then
		RewriteWithoutRanges(Message, Data, Length, BlockedRanges)
	end
end
