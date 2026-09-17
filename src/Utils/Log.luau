local Log = {}
Log.__index = Log

local PendingCallDecisions = setmetatable({}, { __mode = "k" })

-- `tostring(table)` is used as the pending-decision key and is needed twice per
-- call (ShouldBlock + Call).  Remembering the key per info table halves that
-- work and keeps both lookups on the same interned string.
local CallDecisionKeys = setmetatable({}, { __mode = "k" })

-- clonefunction() allocates a brand new closure every time it runs, and the
-- same calling scripts are cloned over and over.  Clones are cached against the
-- original closure (weak keys: once the game drops the original, the clone goes
-- with it).
local FunctionClones = setmetatable({}, { __mode = "k" })

local function GetDecisionKey(RawInfo): string
	local Key = CallDecisionKeys[RawInfo]
	if not Key then
		Key = tostring(RawInfo)
		CallDecisionKeys[RawInfo] = Key
	end

	return Key
end

local function CloneFunction(Function)
	local Cached = FunctionClones[Function]
	if Cached then
		return Cached
	end

	if not clonefunction then
		return Function
	end

	local Clone = clonefunction(Function)
	FunctionClones[Function] = Clone
	return Clone
end

--[[
	Call retention limit.

	Every captured call keeps a deep-cloned copy of its arguments alive for the
	rest of the session.  On a chatty game (and especially on a phone, where the
	OS is quick to kill apps that grow) that is unbounded memory growth, so each
	remote keeps at most `MaxCallsPerRemote` calls and drops the oldest ones.
	The limit is configurable in Settings (Capture -> Calls Kept Per Remote).

	`MaxCallsPerRemote` is cached: reading it through SaveManager validates the
	whole schema, which must not happen once per intercepted call.
]]
local DefaultMaxCallsPerRemote = 500
local CallCapSlack = 32
local CachedCallCap = nil

local function GetSettingBoolean(Key: string, Default: boolean): boolean
	local Controls = wax.shared.Settings
	local Control = Controls and Controls[Key]
	if Control and Control.Value ~= nil then
		return Control.Value == true
	end

	local SaveManager = wax.shared.SaveManager
	local Success, Value = pcall(function()
		return SaveManager:GetState(Key, Default)
	end)

	return if Success and Value ~= nil then Value == true else Default
end

local function GetMaxCallsPerRemote(): number
	local Controls = wax.shared.Settings
	local Control = Controls and Controls["MaxCallsPerRemote"]

	if Control and Control.Value ~= nil then
		local Value = tonumber(Control.Value)
		if Value and Value >= 1 then
			CachedCallCap = math.floor(Value)
			return CachedCallCap
		end
	end

	if CachedCallCap then
		return CachedCallCap
	end

	local SaveManager = wax.shared.SaveManager
	local Success, Value = pcall(function()
		return SaveManager:GetState("MaxCallsPerRemote", DefaultMaxCallsPerRemote)
	end)

	CachedCallCap = math.floor(tonumber(Success and Value or DefaultMaxCallsPerRemote) or DefaultMaxCallsPerRemote)
	if CachedCallCap < 1 then
		CachedCallCap = DefaultMaxCallsPerRemote
	end

	return CachedCallCap
end

--[[
	Device-tiered budget lookup.

	`src/init.luau` publishes `wax.shared.DeviceProfile` before this module is
	required, so the tier presets are already final here.  The actor environment
	inlines this same file into a bare state that has no DeviceProfile, so every
	read still needs a literal fallback - the values below are the "high" tier
	presets and match `DeviceProfile.MaxPendingNotifications` /
	`DeviceProfile.MaxNotificationsPerHeartbeat`.
]]
local function ProfileValue(Key: string, Default: number): number
	local Profile = wax.shared.DeviceProfile
	local Value = Profile and Profile[Key]

	if type(Value) == "number" then
		return Value
	end

	return Default
end

-- The producer is on a remote hook, while the consumer is the UI heartbeat.
-- Keep the hand-off bounded and coalesce updates for the same remote.  A noisy
-- remote therefore costs one small notification per frame, not one table per
-- packet.
local MaxPendingNotifications = ProfileValue("MaxPendingNotifications", 256)
local MaxNotificationsPerHeartbeat = ProfileValue("MaxNotificationsPerHeartbeat", 96)
wax.shared.LogNotificationQueue = {
	Items = {},
	Head = 1,
	Tail = 0,
	PendingByLog = setmetatable({}, { __mode = "k" }),
	Dropped = 0,
}

local function QueueNotification(LogObject, CallIndex: number, Call)
	local Queue = wax.shared.LogNotificationQueue
	local Existing = Queue.PendingByLog[LogObject]
	if Existing then
		Existing.CallIndex = CallIndex
		Existing.Call = Call or LogObject.Calls[CallIndex]
		Existing.Suppressed = (Existing.Suppressed or 0) + 1
		return
	end

	local Pending = Queue.Tail - Queue.Head + 1
	while Pending >= MaxPendingNotifications do
		local Oldest = Queue.Items[Queue.Head]
		Queue.Items[Queue.Head] = nil
		Queue.Head += 1
		Pending -= 1
		Queue.Dropped += 1
		if Oldest and Oldest.Log then
			Queue.PendingByLog[Oldest.Log] = nil
		end
	end

	if Queue.Head > Queue.Tail then
		table.clear(Queue.Items)
		Queue.Head = 1
		Queue.Tail = 0
	end

	local Notification = {
		Instance = LogObject.Instance,
		Type = LogObject.Type,
		LogIndex = LogObject.Index,
		CallIndex = CallIndex,
		-- Direct references avoid another DebugId lookup on the UI thread.
		Log = LogObject,
		Call = Call or LogObject.Calls[CallIndex],
		Suppressed = 0,
	}
	Queue.Tail += 1
	Queue.Items[Queue.Tail] = Notification
	Queue.PendingByLog[LogObject] = Notification
end

local SpamCallCountThreshold = 120
local SpamTimeWindowSeconds = 1
local HardCaptureLimitPerRemote = 120
local HardCaptureLimitGlobal = 600
local GlobalCaptureWindowStart = 0
local GlobalCaptureCount = 0
local AutoIgnoreSpammyEvents = true

do
	local Success, Value = pcall(function()
		return wax.shared.SaveManager:GetState("AutoIgnoreSpammyEvents", true)
	end)
	if Success then
		AutoIgnoreSpammyEvents = Value == true
	end
end

local function ShouldAutoIgnore(): boolean
	local Control = wax.shared.Settings and wax.shared.Settings.AutoIgnoreSpammyEvents
	if Control and Control.Value ~= nil then
		return Control.Value == true
	end
	return AutoIgnoreSpammyEvents
end

local function RejectCapture(LogObject, Now: number): boolean
	if Now - LogObject.SpamWindowStart >= SpamTimeWindowSeconds then
		LogObject.SpamWindowStart = Now
		LogObject.SpamCallCount = 0
	end

	if Now - GlobalCaptureWindowStart >= SpamTimeWindowSeconds then
		GlobalCaptureWindowStart = Now
		GlobalCaptureCount = 0
	end

	if LogObject.SpamCallCount >= HardCaptureLimitPerRemote or GlobalCaptureCount >= HardCaptureLimitGlobal then
		LogObject.SuppressedCalls += 1
		if ShouldAutoIgnore() and not LogObject.Ignored then
			LogObject:Ignore()
			local Sonner = wax.shared.Sonner
			if Sonner then
				local InstanceName = LogObject.Instance and LogObject.Instance.Name or "remote"
				pcall(Sonner.info, Sonner, `Ignored {InstanceName} ({LogObject.Type}) after sustained event spam.`)
			end
		end
		return true
	end

	LogObject.SpamCallCount += 1
	GlobalCaptureCount += 1
	return false
end

if not wax.shared.IS_ACTOR then
	wax.shared.Connect(wax.shared.RunService.Heartbeat:Connect(function()
		local Queue = wax.shared.LogNotificationQueue
		if Queue.Head > Queue.Tail then
			return
		end

		local Batch = table.create(math.min(MaxNotificationsPerHeartbeat, Queue.Tail - Queue.Head + 1))
		local BatchSize = 0
		while Queue.Head <= Queue.Tail and BatchSize < MaxNotificationsPerHeartbeat do
			local Notification = Queue.Items[Queue.Head]
			Queue.Items[Queue.Head] = nil
			Queue.Head += 1
			if Notification then
				Queue.PendingByLog[Notification.Log] = nil
				BatchSize += 1
				Batch[BatchSize] = Notification
			end
		end

		if Queue.Head > Queue.Tail then
			table.clear(Queue.Items)
			Queue.Head = 1
			Queue.Tail = 0
		end

		if BatchSize > 0 then
			local Communicator = wax.shared.Communicator
			if Communicator then
				Communicator:Fire(Batch)
			end
			table.clear(Batch)
		end
	end))
end


local FunctionToMetatadata, FixTable
do
	if wax.shared.IS_ACTOR then
		local FunctionMetadataCache = setmetatable({}, { __mode = "k" })

		local function CreateTraversalState(Refs)
			return {
				CyclicRefs = Refs or {},
				TableIds = setmetatable({}, { __mode = "k" }),
				Functions = setmetatable({}, { __mode = "k" }),
				NextId = 0,
			}
		end

		local function GenerateId(State)
			State.NextId += 1
			return State.NextId
		end

		FixTable = function(Table, State)
			if not Table then
				return nil
			end

			if not State or not State.CyclicRefs then
				State = CreateTraversalState(State)
			end

			local CyclicRefs = State.CyclicRefs
			local TableId = State.TableIds[Table]
			if not TableId then
				TableId = GenerateId(State)
				State.TableIds[Table] = TableId
			end

			local OutputTable = {}
			CyclicRefs[TableId] = OutputTable

			local ContainsCyclicRef = false

			for Key, Value in next, Table do
				if type(Value) == "table" then
					local ExistingId = State.TableIds[Value]
					if ExistingId then
						ContainsCyclicRef = true

						OutputTable[Key] = {
							__CyclicRef = true,
							__Id = ExistingId,
						}
						continue
					end

					if getmetatable(Value) then
						OutputTable[Key] =
							"Cobalt: Impossible to bridge table with metatable from actor Environment to main Environment"
						continue
					end

					local Result, _, ContainsCyclic = FixTable(Value, State)
					if not Result then
						continue
					end

					OutputTable[Key] = Result
					ContainsCyclicRef = ContainsCyclicRef or ContainsCyclic
				elseif type(Value) == "function" then
					OutputTable[Key] = FunctionToMetatadata(Value, State)
				else
					OutputTable[Key] = Value
				end
			end

			return OutputTable, CyclicRefs, ContainsCyclicRef
		end

		FunctionToMetatadata = function(Function, State)
			if not Function then
				return nil
			end

			if not State or not State.CyclicRefs then
				State = CreateTraversalState()
			end

			local CachedMetadata = FunctionMetadataCache[Function]
			if CachedMetadata then
				return CachedMetadata
			end

			local Metadata = {
				Address = tostring(Function),
				Name = debug.info(Function, "n"),
				Source = debug.info(Function, "s"),
				IsC = iscclosure(Function),
			}

			if State.Functions[Function] then
				Metadata["Recursive"] = true
				Metadata["Validation"] = Data.Token
				Metadata["__Function"] = true

				return Metadata
			end

			State.Functions[Function] = true

			if not iscclosure(Function) then
				Metadata["Upvalues"] = debug.getupvalues and #debug.getupvalues(Function) or 0
				Metadata["Constants"] = debug.getconstants and #debug.getconstants(Function) or 0
				Metadata["Protos"] = debug.getprotos and #debug.getprotos(Function) or 0

				if getfunctionhash then
					Metadata["FunctionHash"] = getfunctionhash(Function)
				end
			end

			
			Metadata["Validation"] = Data.Token
			Metadata["__Function"] = true

			FunctionMetadataCache[Function] = Metadata

			return Metadata
		end
	end
end


function DeepClone(OriginalValue, ValueCopies)
	if wax.shared.IS_ACTOR then
		return OriginalValue
	end

	local OriginalType = type(OriginalValue)
	if OriginalType ~= "table" then
		if OriginalType == "string" or OriginalType == "number" or OriginalType == "boolean" or OriginalValue == nil then
			return OriginalValue
		end

		local RobloxType = typeof(OriginalValue)
		if RobloxType == "Instance" then
			return cloneref(OriginalValue)
	
		elseif RobloxType == "userdata" then
			if getmetatable(OriginalValue) then
				return newproxy(true)
			else
				return newproxy()
			end

		elseif RobloxType == "function" then
			return CloneFunction(OriginalValue)
		end

		return OriginalValue
	end

	
	if ValueCopies then
		local CachedValue = ValueCopies[OriginalValue]
		if CachedValue then
			return CachedValue
		end
	else
		ValueCopies = {}
	end

	
	local ShallowCopy = {}
	ValueCopies[OriginalValue] = ShallowCopy

	for Key, Value in next, OriginalValue do
		local ValueType = type(Value)

		if ValueType == "table" then
			ShallowCopy[Key] = DeepClone(Value, ValueCopies)

		elseif ValueType == "userdata" then
			local ValueRobloxType = typeof(Value)

			if ValueRobloxType == "Instance" then
				ShallowCopy[Key] = cloneref(Value)

			elseif ValueRobloxType == "userdata" then
				if getmetatable(Value) then
					ShallowCopy[Key] = newproxy(true)
				else
					ShallowCopy[Key] = newproxy()
				end

			else
				ShallowCopy[Key] = Value
			end

		elseif ValueType == "function" then
			ShallowCopy[Key] = CloneFunction(Value)
	
		else
			ShallowCopy[Key] = Value
		end
	end

	return ShallowCopy
end

if wax.shared.IS_ACTOR then
	wax.shared.SerializeActorInfo = function(Info)
		return FixTable(DeepClone(Info))
	end
end

function Log.new(Instance, Type, Index, CallingScript)
	local NewLog = setmetatable({
		Instance = Instance,
		Type = Type,
		Index = Index,
		Calls = {},
		GameCalls = {},
		SpamWindowStart = 0,
		SpamCallCount = 0,
		SuppressedCalls = 0,
		Ignored = false,
		Blocked = false,
		Button = nil,
	}, Log)

	return NewLog
end

function Log:IsOverSpamThreshold()
	-- Kept for plugins that query the old API.  Capture admission is enforced
	-- centrally in `Log:Call`, even when the optional auto-ignore setting is off.
	return self.SpamCallCount >= SpamCallCountThreshold
end

local function RunInterceptors(Interceptors: { (...any) -> ...any }, Info: any, Log): boolean
	for _, Callback in Interceptors do
		local Ok, Result = pcall(Callback, Info, Log.Instance, Log.Type)
		if not Ok then
			warn(`[Cobalt Plugin Interceptor] Error: {Result}`)
		elseif Result == false then
			return true
		end
	end

	return false
end

function Log:ShouldBlock(RawInfo, PendingCallDecisionsKey): boolean
	PendingCallDecisionsKey = PendingCallDecisionsKey or GetDecisionKey(RawInfo)

	local Decision = PendingCallDecisions[PendingCallDecisionsKey]
	if Decision then
		return Decision.ShouldBlock
	end

	local FilterAction
	local CallFilters = wax.shared.CallFilters
	do
		if CallFilters then
			FilterAction = CallFilters:Resolve(self.Instance, self.Type, RawInfo)
		end
	end

	local ShouldBlock = RawInfo.Blocked == true or self.Blocked or FilterAction == "Block"
	if ShouldBlock then
		RawInfo.Blocked = true
	end

	PendingCallDecisions[PendingCallDecisionsKey] = {
		FilterAction = FilterAction,
		ShouldBlock = ShouldBlock,
	}
	return ShouldBlock
end

--[[
	Keeps at most `MaxCalls` entries by dropping the oldest ones.

	Call indices are the log's public currency (call lists, notifications, the
	file logger), so both the call array and the executor-call index list are
	rebuilt together and stay consistent.
]]
function Log:TrimCalls(MaxCalls: number)
	local Calls = self.Calls
	local Total = #Calls
	local RemoveCount = Total - MaxCalls
	if RemoveCount <= 0 then
		return 0
	end

	local Trimmed = table.create(Total - RemoveCount)
	for Index = RemoveCount + 1, Total do
		Trimmed[Index - RemoveCount] = Calls[Index]
	end
	self.Calls = Trimmed

	local GameCalls = self.GameCalls
	local WriteIndex = 1
	for ReadIndex = 1, #GameCalls do
		local Shifted = GameCalls[ReadIndex] - RemoveCount
		if Shifted >= 1 then
			GameCalls[WriteIndex] = Shifted
			WriteIndex += 1
		end
	end

	for Index = WriteIndex, #GameCalls do
		GameCalls[Index] = nil
	end

	return RemoveCount
end

function Log:Call(RawInfo): number?
	local PendingCallDecisionsKey = GetDecisionKey(RawInfo)

	local ShouldBlock = self:ShouldBlock(RawInfo, PendingCallDecisionsKey)
	local Decision = PendingCallDecisions[PendingCallDecisionsKey]
	PendingCallDecisions[PendingCallDecisionsKey] = nil

	local ShouldCapture = not self.Ignored and Decision.FilterAction ~= "Ignore"
	do
		if ShouldBlock then
			ShouldCapture = GetSettingBoolean("LogBlockedRemotes", false)
		end

		if RawInfo.Omit then
			ShouldCapture = false
		end
	end

	if not ShouldCapture then
		return nil
	end

	-- Do this before DeepClone.  Cloning arguments is the expensive part of a
	-- capture, and a hard per-remote/global budget prevents one spammy event
	-- from consuming the frame and memory budgets of the whole game.
	if RejectCapture(self, os.clock()) then
		return nil
	end

	local Info = DeepClone(RawInfo)
	Info.CreationTime = tick()

	
	if wax.shared.IS_ACTOR then
		if self.Instance == wax.shared.Communicator then
			return nil
		end

		Info["Actor"] = CurrentActor

		
		local OldArguments = Info.Arguments
		Info.Arguments = {
			Data = OldArguments,
			n = OldArguments.n,
		}

		if Info.InvokeResult then
			local OldInvokeResult = Info.InvokeResult
			Info.InvokeResult = {
				Data = OldInvokeResult,
				n = OldInvokeResult.n,
			}
		end

		local FixedInfo, CyclicRefs, ContainsCyclicRef = FixTable(Info)

		
		local identity = getthreadidentity()
		setthreadidentity(8)
		wax.shared.Communicator.Fire(
			wax.shared.Communicator,
			"ActorCall",
			self.Instance,
			self.Type,
			FixedInfo,
			CyclicRefs,
			ContainsCyclicRef
		)
		setthreadidentity(identity)
		return nil
	end

	
	local PluginManager = wax.shared.CobaltPluginManager
	if PluginManager and PluginManager.HasInterceptors then
		
		local InstanceIntercept = PluginManager.Registry.Interceptors.Instance[self.Instance]
		if InstanceIntercept then
			if InstanceIntercept[self.Type] and RunInterceptors(InstanceIntercept[self.Type], Info, self) then
				return nil
			end
			if InstanceIntercept["All"] and RunInterceptors(InstanceIntercept["All"], Info, self) then
				return nil
			end
		end

		
		local GlobalByType = PluginManager.Registry.Interceptors.Global[self.Type]
		if GlobalByType and RunInterceptors(GlobalByType, Info, self) then
			return nil
		end

		local GlobalAll = PluginManager.Registry.Interceptors.Global["All"]
		if GlobalAll and RunInterceptors(GlobalAll, Info, self) then
			return nil
		end
	end

	
	local Index = #self.Calls + 1
	self.Calls[Index] = Info
	if not Info.IsExecutor then
		table.insert(self.GameCalls, Index)
	end

	-- Trim with a little slack so the rebuild cost is amortised over many calls
	-- instead of running on every single one at the cap.
	local CallCap = GetMaxCallsPerRemote()
	if Index > CallCap + CallCapSlack then
		self:TrimCalls(CallCap)
		Index = #self.Calls
	end

	QueueNotification(self, Index, Info)
	return Index
end

function Log:ClearCalls()
	table.clear(self.Calls)
	table.clear(self.GameCalls)
	local Pending = wax.shared.LogNotificationQueue.PendingByLog[self]
	if Pending then
		Pending.Call = nil
		Pending.CallIndex = nil
		wax.shared.LogNotificationQueue.PendingByLog[self] = nil
	end
	self.SpamWindowStart = os.clock()
	self.SpamCallCount = 0
	self.SuppressedCalls = 0
end

function Log:Ignore()
	self.Ignored = not self.Ignored

	if not wax.shared.IS_ACTOR then
		if wax.shared.ActorCommunicator then
			pcall(wax.shared.ActorCommunicator.Fire, wax.shared.ActorCommunicator, "MainIgnore", self.Instance, self.Type)
		end

		local IgnoredRemoteList = wax.shared.Settings["IgnoredRemotes"]
		if IgnoredRemoteList then
			if self.Ignored then
				IgnoredRemoteList:AddToList(self)
			else
				IgnoredRemoteList:RemoveFromList(self)
			end
		end
	end
end

local ClassesConnectionsToggle = {
	RemoteEvent = "OnClientEvent",
	UnreliableRemoteEvent = "OnClientEvent",
	BindableEvent = "Event",
}

function Log:SetConnectionsEnabled(enabled: boolean)
	if not self.Instance or not ClassesConnectionsToggle[self.Instance.ClassName] then
		return
	end

	local ConnectionName = ClassesConnectionsToggle[self.Instance.ClassName]
	if self.Type ~= "Incoming" or not ConnectionName then
		return
	end

	local LoggingFunctions = wax.shared.IncomingLogConnectionFunctions
	for _, Connection in pairs(getconnections(self.Instance[ConnectionName])) do
		if LoggingFunctions and LoggingFunctions[Connection.Function] then
			continue
		end

		if enabled then
			Connection:Enable()
		else
			Connection:Disable()
		end
	end
end

function Log:Block()
	if not wax.shared.IS_ACTOR and wax.shared.ActorCommunicator then
		pcall(wax.shared.ActorCommunicator.Fire, wax.shared.ActorCommunicator, "MainBlock", self.Instance, self.Type)
	end

	self.Blocked = not self.Blocked
	self:SetConnectionsEnabled(not self.Blocked)
end

function Log:SetButton(Instance, Name, Calls)
	self.Button = {
		Instance = Instance,
		Name = Name,
		Calls = Calls,
	}
end

return Log
