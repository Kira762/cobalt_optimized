
local function CreateLookupTable(table)
	local LookupTable = {}
	for _, Method in next, table do
		LookupTable[Method] = true
	end
	return LookupTable
end


local setfenv = setfenv
local getconnections = wax.shared.ExecutorSupport["getconnections"].IsWorking and getconnections or function() return {} end

local ClassesToHook = {
	RemoteEvent = "OnClientEvent",
	RemoteFunction = "OnClientInvoke",
	UnreliableRemoteEvent = "OnClientEvent",
	BindableEvent = "Event",
	BindableFunction = "OnInvoke",
}

local ConnectionKeys = CreateLookupTable({
	"Connect",
	"ConnectParallel",
	"connect",
	"connectParallel",
	"Once",
})


local ConnectionsEnabled = false
local CallbacksEnabled = false
local ConnectionHookEnabled = false


local LogConnectionFunctions = {}
local CallbackOwners = setmetatable({}, { __mode = "k" })
local SignalMapping = setmetatable({}, { __mode = "kv" })
local ObservedConnectionInstances = setmetatable({}, { __mode = "k" })
wax.shared.IncomingLogConnectionFunctions = LogConnectionFunctions

local CobaltObserverEnvironmentKey = "__CobaltIncomingObserver"


type InstancesToHook = RemoteEvent | UnreliableRemoteEvent | RemoteFunction | BindableEvent | BindableFunction
type MethodsToHook = "OnClientEvent" | "OnClientInvoke" | "Event" | "OnInvoke"
export type Options = {
	Connections: boolean?,
	Callbacks: boolean?,
	HookConnections: boolean?,
}


local function GetLog(Instance: InstancesToHook, Function: (...any) -> ...any)
	local DebugId = wax.shared.GetDebugId(Instance)

	if wax.shared.ShouldIgnore(Instance, getcallingscript()) or LogConnectionFunctions[Function] then
		return nil
	end

	local IncomingLogs = wax.shared.Logs.Incoming
	if not IncomingLogs then
		return nil
	end

	local Log = IncomingLogs[DebugId]
	if not Log then
		Log = wax.shared.NewLog(Instance, "Incoming", getcallingscript(), DebugId)
	end

	return Log
end

local function ResolveCallableFunction(Value: any): ((...any) -> ...any)?
	if typeof(Value) == "function" then
		return Value
	end

	local Success, Metatable = pcall(wax.shared.getrawmetatable, Value)
	if not Success or not Metatable then
		return nil
	end

	local HasCall, Call = pcall(rawget, Metatable, "__call")
	return if HasCall and typeof(Call) == "function" then Call else nil
end


local function LogRemote(
	Instance: InstancesToHook,
	Function: (...any) -> ...any,
	Info: {
		Arguments: { [number]: any, n: number },
		Origin: Instance,
		Function: (...any) -> ...any,
		Line: number,
		IsExecutor: boolean,
		Blocked: boolean?,
	}
)
	local Log = GetLog(Instance, Function)
	if not Log then
		return false, nil
	end

	local ShouldBlock = Log:ShouldBlock(Info)
	local CallIndex = Log:Call(Info)
	return ShouldBlock, Log, CallIndex
end


local SupportsFilters = wax.shared.ExecutorSupport["FilterBase"].IsWorking


local function CreateBaseFilter()
	local Filters = {}
	if not SupportsFilters then
		return Filters
	end

	
	for ClassName in ClassesToHook do
		table.insert(Filters, InstanceTypeFilter.new(1, ClassName))
	end

	return Filters
end



local function IsCobaltConnectionFunction(Function): boolean
	if not Function then
		return false
	end

	if LogConnectionFunctions[Function] then
		return true
	end

	local Success, Environment = pcall(getfenv, Function)
	local VerificationToken = wax.shared.CobaltVerificationToken
	return (
		Success
		and VerificationToken ~= nil
		and typeof(Environment) == "table"
		and rawequal(rawget(Environment, CobaltObserverEnvironmentKey), VerificationToken)
	)
end


local function CreateConnectionFunction(Instance: InstancesToHook, Method: MethodsToHook)
	local CachedConnectionInfo = nil
	local CachedConnectionCount = -1

	local DebugId = wax.shared.GetDebugId(Instance)

	local ConnectionFunction = function(...)
		
		local ExistingLog = wax.shared.Logs.Incoming[DebugId]
		if ExistingLog and ExistingLog.Ignored then
			return
		end

		local Signal = (Instance :: any)[Method]
		local Connections = getconnections(Signal)
		local ConnectionCount = #Connections

		
		if ConnectionCount ~= CachedConnectionCount then
			CachedConnectionCount = ConnectionCount

			local Information = {
				HasValidConnections = false,
				HasForeignLuaConnections = false,
				Entries = {},
			}

			for _, Connection in Connections do
				
				if Connection.ForeignState then
					
					if Connection.LuaConnection then
						Information.HasForeignLuaConnections = true
					end

					continue
				end

				
				local Function = typeof(Connection.Function) == "function" and (Connection.Function) or (nil)
				if IsCobaltConnectionFunction(Function) then
					continue
				end

				Information.HasValidConnections = true

				
				local Thread = Connection.Thread
				local Origin = nil

				if Thread and getscriptfromthread then
					Origin = getscriptfromthread(Thread)
				end

				if not Origin and Function then
					
					

					local Script = rawget(getfenv(Function), "script")
					if typeof(Script) == "Instance" then
						Origin = Script
					end
				end

				table.insert(Information.Entries, {
					Function = Function,
					Origin = Origin,
					IsExecutor = Function and isexecutorclosure(Function) or false,
				})
			end

			CachedConnectionInfo = Information
		end

		local Arguments = wax.shared.SafePack.Pack(...)
		local TargetLog, TargetCallIndex

		
		if CachedConnectionInfo.HasValidConnections then
			for _, Entry in CachedConnectionInfo.Entries do
				TargetLog, TargetCallIndex = select(2, LogRemote(Instance, Entry.Function, {
					Arguments = Arguments,
					Origin = Entry.Origin,
					Function = Entry.Function,
					Line = nil,
					IsExecutor = Entry.IsExecutor,
				}))
			end

		elseif not wax.shared.IS_ACTOR then
			TargetLog, TargetCallIndex = select(2, LogRemote(Instance, nil, {
				Arguments = Arguments,
				Origin = nil,
				Function = nil,
				Line = nil,
				IsExecutor = false,
			}))
		end

		local Communicator = wax.shared.ActorCommunicator
		if Communicator then
			if
				not wax.shared.IS_ACTOR
				and CachedConnectionInfo.HasForeignLuaConnections
				and TargetLog
				and TargetCallIndex
			then
				Communicator:Fire(
					"InspectIncomingConnections",
					Instance,
					Method,
					TargetLog.Index,
					TargetCallIndex
				)
			end
		end
	end

	local OriginalEnvironment = getfenv(ConnectionFunction)
	setfenv(ConnectionFunction, setmetatable({
		[CobaltObserverEnvironmentKey] = wax.shared.CobaltVerificationToken,
	}, {
		__index = OriginalEnvironment,
		__newindex = OriginalEnvironment,
	}))

	LogConnectionFunctions[ConnectionFunction] = true
	return ConnectionFunction
end




local function HandleCallbackLogging(Log, Info, InitialEnv, InitialIdentity, ...)
	setfenv(0, InitialEnv)
	setthreadidentity(InitialIdentity)

	if Log then
		Info.InvokeResult = wax.shared.SafePack.Pack(...)
		Log:Call(Info)
	end

	return ...
end


local function CreateCallbackDetour(Instance: InstancesToHook, Callback: any)
	local CallbackFunction = assert(ResolveCallableFunction(Callback), "Callback is not callable")
	local Detour = function(...)
		local Origin = nil

		
		if getscriptfromthread then
			Origin = getscriptfromthread(coroutine.running())
		end

		
		if not Origin then
			local Script = rawget(getfenv(CallbackFunction), "script")
			if typeof(Script) == "Instance" then
				Origin = Script
			end
		end

		local FunctionCaller = debug.info(2, "f")
		local IsExecutor = if typeof(FunctionCaller) == "function"
			then isexecutorclosure(FunctionCaller)
			else isexecutorclosure(CallbackFunction)

		local Arguments = wax.shared.SafePack.Pack(...)
		local Log = GetLog(Instance, CallbackFunction)
		local Info = {
			Arguments = Arguments,
			Origin = Origin,
			Function = CallbackFunction,
			Line = nil,
			IsExecutor = IsExecutor,
			InvokeKind = "Callback",
		}
		if Log and Log:ShouldBlock(Info) then
			Log:Call(Info)
			return
		end

		local InitialEnv, InitialIdentity = getfenv(CreateCallbackDetour), getthreadidentity()
		local IsDirectFunction = rawequal(Callback, CallbackFunction)

		setthreadidentity(2)
		setfenv(0, getfenv(CallbackFunction))
		if IsDirectFunction then
			return HandleCallbackLogging(
				Log,
				Info,
				InitialEnv,
				InitialIdentity,
				CallbackFunction(...)
			)
		end

		return HandleCallbackLogging(
			Log,
			Info,
			InitialEnv,
			InitialIdentity,
			CallbackFunction(Callback, ...)
		)
	end

	if wax.shared.ExecutorSupport["setstackhidden"].IsWorking then
		setstackhidden(Detour, true)
	end

	CallbackOwners[Detour] = {
		Original = Callback,
		Method = ClassesToHook[Instance.ClassName],
		Instance = Instance
	}
	return Detour
end

local function GetOriginalScript(OriginalEnv: { [string]: any}): Instance?
	local OriginalScript = rawget(OriginalEnv, "script")
	if typeof(OriginalScript) ~= "Instance" then
		return nil
	end

	return OriginalScript
end


wax.shared.RestoreCallbackDetours = function()
	for Detour, Owner in CallbackOwners do
		local Success, CurrentCallback = pcall(getcallbackvalue, Owner.Instance, Owner.Method)
		if not (Success and rawequal(CurrentCallback, Detour)) then
			continue
		end

		pcall(function()
			if wax.shared.trampoline_call then
				local OriginalEnv = getfenv(Owner.Original)
				local OriginalScript = GetOriginalScript(OriginalEnv)

				wax.shared.trampoline_call(function()
					Owner.Instance[Owner.Method] = Owner.Original
				end, {}, {
					env = OriginalEnv,
					script = OriginalScript,
					identity = 2
				})
			else
				task.spawn(function()
					local OriginalEnv = getfenv(Owner.Original)

					setthreadidentity(2)
					setfenv(0, OriginalEnv)
					Owner.Instance[Owner.Method] = Owner.Original
				end)
			end
		end)
	end

	table.clear(CallbackOwners)
end




local function HandleInstance(Instance: any)
	if
		not ClassesToHook[Instance.ClassName]
		or Instance == wax.shared.Communicator
		or Instance == wax.shared.ActorCommunicator
	then
		return
	end

	local Method = ClassesToHook[Instance.ClassName]

	if ConnectionsEnabled and not ObservedConnectionInstances[Instance] then
		if Instance.ClassName == "RemoteEvent" or Instance.ClassName == "UnreliableRemoteEvent" then
			wax.shared.Connect(Instance.OnClientEvent:Connect(CreateConnectionFunction(Instance, Method)))

			SignalMapping[Instance.OnClientEvent] = Instance
			ObservedConnectionInstances[Instance] = true
		elseif Instance.ClassName == "BindableEvent" then
			wax.shared.Connect(Instance.Event:Connect(CreateConnectionFunction(Instance, Method)))

			SignalMapping[Instance.Event] = Instance
			ObservedConnectionInstances[Instance] = true
		end
	end

	if CallbacksEnabled then
		if Instance.ClassName == "RemoteFunction" or Instance.ClassName == "BindableFunction" then
			local IsCoreRemote = Instance:IsDescendantOf(wax.shared.RobloxReplicatedStorage)
			if IsCoreRemote then return end

			local Success, Callback = pcall(getcallbackvalue, Instance, Method)
			local IsCallable = ResolveCallableFunction(Callback) ~= nil

			if not Success or not IsCallable or CallbackOwners[Callback] then
				return
			end

			
			if wax.shared.trampoline_call then
				local OriginalEnv = getfenv(Callback)
				local OriginalScript = GetOriginalScript(OriginalEnv)

				wax.shared.trampoline_call(function()
					Instance[Method] = CreateCallbackDetour(Instance, Callback)
				end, {}, {
					env = OriginalEnv,
					script = OriginalScript,
					identity = 2
				})
			else
				Instance[Method] = CreateCallbackDetour(Instance, Callback)
			end
		end
	end
end


local function SetupCallbackAssignmentHook()
	local NewIndexHookFilter = SupportsFilters and AnyFilter.new(CreateBaseFilter())
	
	wax.shared.NewIndexHook = wax.shared.Hooking.HookMetaMethod(game, "__newindex", function(...)
		local self, key, value = ...

		if typeof(self) ~= "Instance" or not ClassesToHook[self.ClassName] then
			return wax.shared.NewIndexHook(...)
		end

		if self.ClassName == "RemoteFunction" or self.ClassName == "BindableFunction" then
			local Method = ClassesToHook[self.ClassName]

			local IsCallable = ResolveCallableFunction(value) ~= nil

			if key == Method and IsCallable then
				if CallbackOwners[value] then
					return wax.shared.NewIndexHook(...)
				end

				return wax.shared.NewIndexHook(self, key, CreateCallbackDetour(self :: InstancesToHook, value))
			end
		end

		return wax.shared.NewIndexHook(...)
	end, NewIndexHookFilter)
end


local function HandleConnectionLogging(Instance, Method, callback, ...)
	local Log = wax.shared.Logs.Incoming[wax.shared.GetDebugId(Instance)]

	if Log and Log.Blocked then
		for _, Connection in getconnections(Instance[Method]) do
			if not Connection.ForeignState and Connection.Function ~= callback then
				continue
			end

			Connection:Disable()
		end
	end

	return ...
end


local function SetupConnectionAssignmentHook()
	local SignalMetatable = wax.shared.getrawmetatable(Instance.new("Part").Touched)
	wax.shared.Hooks[SignalMetatable.__index] = wax.shared.Hooking.HookFunction(SignalMetatable.__index, function(...)
		local self, key = ...

		if not wax.shared.Unloaded and ConnectionKeys[key] then
			local Instance = SignalMapping[self]
			local Connect = wax.shared.Hooks[SignalMetatable.__index](...)

			if not Instance then
				return Connect
			end

			local Method = ClassesToHook[Instance.ClassName]
			return wax.shared.newcclosure(function(...)
				local _self, callback = ...
				return HandleConnectionLogging(Instance, Method, callback, Connect(...))
			end, debug.info(Connect, "n"))
		end

		return wax.shared.Hooks[SignalMetatable.__index](...)
	end)
end

local Started = false
return function(Options: Options?)
	if Started then
		return
	end

	
	Options = Options or {}
	do
		ConnectionsEnabled = Options.Connections ~= false
		CallbacksEnabled = Options.Callbacks ~= false
		ConnectionHookEnabled = Options.HookConnections ~= false
	end

	if not ConnectionsEnabled and not CallbacksEnabled then
		return
	end

	Started = true

	
	if CallbacksEnabled then
		if wax.shared.ExecutorSupport["setstackhidden"].IsWorking then
			setstackhidden(HandleCallbackLogging, true)
		end

		SetupCallbackAssignmentHook()
	end

	if ConnectionsEnabled and ConnectionHookEnabled then
		SetupConnectionAssignmentHook()
	end

	wax.shared.Connect(game.DescendantAdded:Connect(function(instance)
		HandleInstance(cloneref(instance))
	end))

	
	local ClassesToSearch = {}
	do
		if ConnectionsEnabled then
			table.insert(ClassesToSearch, "RemoteEvent")
			table.insert(ClassesToSearch, "UnreliableRemoteEvent")
			table.insert(ClassesToSearch, "BindableEvent")
		end
		if CallbacksEnabled then
			table.insert(ClassesToSearch, "RemoteFunction")
			table.insert(ClassesToSearch, "BindableFunction")
		end
	end

	local Categories = {
		game:QueryDescendants(table.concat(ClassesToSearch, ", ")),
	}
	if wax.shared.ExecutorSupport["getnilinstances"].IsWorking then
		table.insert(Categories, getnilinstances())
	end

	for _, Category in Categories do
		for _, TargetInstance in next, Category do
			HandleInstance(cloneref(TargetInstance))
		end
	end
end
