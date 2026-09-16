local function CreateLookupTable(table)
	local LookupTable = {}
	for _, Method in next, table do
		LookupTable[Method] = true
	end
	return LookupTable
end

local NamecallMethods = {
	["FireServer"] = CreateLookupTable({"RemoteEvent", "UnreliableRemoteEvent"}),
	["fireServer"] = CreateLookupTable({"RemoteEvent", "UnreliableRemoteEvent"}),
	
	["InvokeServer"] = CreateLookupTable({"RemoteFunction"}),
	["invokeServer"] = CreateLookupTable({"RemoteFunction"}),

	["Fire"] = CreateLookupTable({"BindableEvent"}),
	["fire"] = CreateLookupTable({"BindableEvent"}),
	
	["Invoke"] = CreateLookupTable({"BindableFunction"}),
	["invoke"] = CreateLookupTable({"BindableFunction"}),
}
local AllowedClassNames =
	CreateLookupTable({ "RemoteEvent", "RemoteFunction", "UnreliableRemoteEvent", "BindableEvent", "BindableFunction" })


--[[
	Caller resolution.

	Function, source and line used to be resolved by three separate loops that
	walked the same stack levels (up to eighteen debug.info calls per remote).
	One pass returns all three, which is the single biggest win on this hot path.
]]
local function GetCallerInfo()
	local BaseLevel = if wax.shared.IsUsingOthHooks then 3 else 5

	for i = BaseLevel, 10 do
		local Function, Source, Line = debug.info(i, "fsl")
		if not Function or not Source then
			break
		end

		if Source == "[C]" then
			continue
		end

		return Function, Source, Line
	end

	return debug.info(BaseLevel, "f"), debug.info(BaseLevel, "s"), debug.info(BaseLevel, "l")
end


local function getcallingfunction()
	local Function = GetCallerInfo()
	return Function
end


local function getcallingline()
	local _, _, Line = GetCallerInfo()
	return Line
end


local function getcallingsource()
	local _, Source = GetCallerInfo()
	return Source
end


local function GetLog(Instance: Instance, Direction: "Outgoing" | "Incoming", DebugId: number?)
	DebugId = DebugId or wax.shared.GetDebugId(Instance)

	local LogsInDirection = wax.shared.Logs[Direction]
	if not LogsInDirection then
		return nil
	end

	local Log = LogsInDirection[DebugId]
	if not Log then
		Log = wax.shared.NewLog(Instance, Direction, getcallingscript(), DebugId)
	end

	return Log
end


local function HandleLoggingResult(Log, Info, ResultKey, ...)
	local Result = wax.shared.SafePack.Pack(...)
	Info[ResultKey] = Result
	Log:Call(Info)

	return ...
end


local function HandleLogging(TargetInstance: Instance, Method: string, OldFunction: (...any) -> ...any, ...)
	-- Resolve everything the log entry needs exactly once.
	local DebugId = wax.shared.GetDebugId(TargetInstance)
	local Log = GetLog(TargetInstance, "Outgoing", DebugId)
	if not Log then
		return OldFunction(...)
	end
	local Arguments = wax.shared.SafePack.Pack(select(2, ...))

	local CallingScript = getcallingscript()
	local CallingFunction, CallingSource, CallingLine = GetCallerInfo()
	local IsExecutor = checkcaller()

	local Info = {
		Arguments = Arguments,
		Origin = CallingScript,
		Function = CallingFunction,
		Line = CallingLine,
		Source = CallingSource,
		IsExecutor = IsExecutor,
	}
	local ShouldBlock = Log:ShouldBlock(Info)
	Log:Call(Info)
	if ShouldBlock then
		return
	end

	local IsRemoteFunctionInvoke = (
		TargetInstance.ClassName == "RemoteFunction" and (Method == "InvokeServer" or Method == "invokeServer")
	)

	local IsBindableFunctionInvoke = (
		TargetInstance.ClassName == "BindableFunction" and (Method == "Invoke" or Method == "invoke")
	)

	if IsRemoteFunctionInvoke or IsBindableFunctionInvoke then
		
		Log = GetLog(TargetInstance, "Incoming", DebugId)
		local RFResultInfo = {
			Arguments = Arguments,
			InvokeResult = nil,
			Origin = CallingScript,
			Function = CallingFunction,
			Line = CallingLine,
			Source = CallingSource,
			IsExecutor = IsExecutor,
			InvokeKind = "Request",
		}

		if Log:ShouldBlock(RFResultInfo) then
			Log:Call(RFResultInfo)
			return
		end

		return HandleLoggingResult(Log, RFResultInfo, "InvokeResult", OldFunction(...))
	end

	return OldFunction(...)
end


local SupportsFilters = wax.shared.ExecutorSupport["FilterBase"].IsWorking


local function CreateBaseFilter()
	local Filters = {}
	if not SupportsFilters then
		return Filters
	end

	
	table.insert(Filters, NotFilter.new(ArgumentFilter.new(1, wax.shared.Communicator)))
	table.insert(Filters, NotFilter.new(ArgumentFilter.new(1, wax.shared.ActorCommunicator)))

	return Filters
end

local NamecallHookFilter = SupportsFilters and AllFilter.new((function()
	local Filters = CreateBaseFilter()

	

	
	local AnyClassNameFilters = {}
	for ClassName in AllowedClassNames do
		table.insert(AnyClassNameFilters, InstanceTypeFilter.new(1, ClassName))
	end
	
	
	local AnyNamecallMethoFilters = {}
    for Method in NamecallMethods do
        table.insert(AnyNamecallMethoFilters, NamecallFilter.new(Method))
    end

	table.insert(Filters, AnyFilter.new(AnyClassNameFilters))
	table.insert(Filters, AnyFilter.new(AnyNamecallMethoFilters))
    return Filters
end)())



wax.shared.NamecallHook = wax.shared.Hooking.HookMetaMethod(game, "__namecall", function(...)
	local self = ...
	local Method = getnamecallmethod()

	if
		typeof(self) == "Instance"
		and AllowedClassNames[self.ClassName]
		and not rawequal(self, wax.shared.Communicator)
		and not rawequal(self, wax.shared.ActorCommunicator)
		and (NamecallMethods[Method] and NamecallMethods[Method][self.ClassName])
		and not wax.shared.ShouldIgnore(self, getcallingscript())
	then
		return HandleLogging(cloneref(self), Method, wax.shared.NamecallHook, ...)
	end

	return wax.shared.NamecallHook(...)
end, NamecallHookFilter)


local FunctionsToHook
do
	local BindableFunction = Instance.new("BindableFunction")
	local BindableEvent = Instance.new("BindableEvent")

	local RemoteFunction = Instance.new("RemoteFunction")
	local RemoteEvent = Instance.new("RemoteEvent")
	local UnreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")

	FunctionsToHook = {
		BindableFunction.Invoke,
		BindableEvent.Fire,

		RemoteFunction.InvokeServer,
		RemoteEvent.FireServer,
		UnreliableRemoteEvent.FireServer,
	}

	BindableFunction:Destroy()
	BindableEvent:Destroy()

	RemoteFunction:Destroy()
	RemoteEvent:Destroy()
	UnreliableRemoteEvent:Destroy()
end

local FunctionHookFilter = SupportsFilters and AllFilter.new((function()
	local Filters = CreateBaseFilter()

	

	local ClassFilters = {}
	for ClassName in AllowedClassNames do
		table.insert(ClassFilters, InstanceTypeFilter.new(1, ClassName))
	end

	table.insert(Filters, AnyFilter.new(ClassFilters))
	return Filters
end)())

for _, Function in next, FunctionsToHook do
	local Method = debug.info(Function, "n")

	wax.shared.Hooks[Function] = wax.shared.Hooking.HookFunction(Function, function(...)
		local self = ...

		if
			typeof(self) == "Instance"
			and AllowedClassNames[self.ClassName]
			and not rawequal(self, wax.shared.Communicator)
			and not wax.shared.ShouldIgnore(self, getcallingscript())
		then
			return HandleLogging(cloneref(self), Method, wax.shared.Hooks[Function], ...)
		end

		return wax.shared.Hooks[Function](...)
	end, FunctionHookFilter)
end
