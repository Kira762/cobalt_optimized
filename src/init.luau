wax.shared.CobaltStartTime = tick()
wax.shared.IS_ACTOR = false

local FileLogger = require(script.Utils.FileLog)


for _, Service in pairs({
	"ContentProvider",
	"CoreGui",
	"TweenService",
	"Players",
	"RunService",
	"HttpService",
	"UserInputService",
	"TextService",
	"StarterGui",
	"RobloxReplicatedStorage",
}) do
	wax.shared[Service] = cloneref(game:GetService(Service))
end

wax.shared.CobaltVerificationToken = wax.shared.HttpService:GenerateGUID()
wax.shared.Hooks = {}


wax.shared.ExecutorName = identifyexecutor()

-- Device tiering runs first: the frame-time sampler overlaps the
-- ExecutorSupport tests below, and the adaptive consumers (Log, Calls, List,
-- Animations) capture their tier preset when they load, so the tier must be
-- final before the rest of the bundle boots.
local DeviceProfile = require("@src/Utils/DeviceProfile")
wax.shared.DeviceProfile = DeviceProfile
DeviceProfile.Detect()
DeviceProfile.BeginFrameSampling()

wax.shared.ExecutorSupport = require(script.ExecutorSupport)
DeviceProfile.FinishDetection()

local AssetManager = require(script.Utils.UI.Assets.Manager)
AssetManager.PreloadAsync()
wax.shared.ExecutorSupport.ValidateCustomAssets(AssetManager)

wax.shared.Sonner = require(script.Window.Components.Sonner)
wax.shared.SaveManager = require(script.Utils.SaveManager)
wax.shared.Settings = {}

wax.shared.CallFilters = require(script.Utils.CallFilter.Manager)
local CallFiltersSubscription = wax.shared.CallFilters:Subscribe(function(Filters)
	if not wax.shared.ActorCommunicator then
		return
	end

	pcall(wax.shared.ActorCommunicator.Fire, wax.shared.ActorCommunicator, "MainCallFiltersSync", Filters)
end)

local Ratelimiter = require("@src/Utils/Ratelimiter")


local DoesSupportOthHooks = (
	wax.shared.ExecutorSupport["oth"].IsWorking
	and wax.shared.ExecutorSupport["iscclosure"].IsWorking
	and wax.shared.ExecutorSupport["getnamecallmethod"].IsWorking
	and wax.shared.ExecutorSupport["getrawmetatable"].IsWorking
)
local DoesSupportStandardHooks = (
	wax.shared.ExecutorSupport["hookfunction"].IsWorking
	and wax.shared.ExecutorSupport["hookmetamethod"].IsWorking
	and wax.shared.ExecutorSupport["newcclosure"].IsWorking
	and wax.shared.ExecutorSupport["islclosure"].IsWorking
	and wax.shared.ExecutorSupport["getnamecallmethod"].IsWorking
	and wax.shared.ExecutorSupport["getrawmetatable"].IsWorking
)

wax.shared.IsUsingRakNetHooks = (
	wax.shared.SaveManager:GetState("RakNetHooks") and wax.shared.ExecutorSupport["raknet"].IsWorking
)

wax.shared.IsUsingOthHooks = (
	wax.shared.SaveManager:GetState("OthHooks") and DoesSupportOthHooks
)

wax.shared.IsOutgoingLoggable = wax.shared.IsUsingRakNetHooks or wax.shared.IsUsingOthHooks or DoesSupportStandardHooks


require(script.Utils.Connect)
wax.shared.Hooking = require(script.Utils.Hook.Luau)


local LuaEncode = require(script.Utils.CodeGen.Serializer.LuaEncode)
wax.shared.LuaEncode = LuaEncode

local CodeGen = require(script.Utils.CodeGen.Generator)
local InstanceSerializer = require(script.Utils.CodeGen.Serializer.Instance)


if not wax.shared.Players.LocalPlayer then
	wax.shared.Players.PlayerAdded:Wait()
end

wax.shared.LocalPlayer = wax.shared.Players.LocalPlayer
local ContendingPlayerScripts =
	cloneref(wax.shared.LocalPlayer:QueryDescendants("PlayerScripts")[1] or wax.shared.LocalPlayer)
if ContendingPlayerScripts:IsA("PlayerScripts") then
	wax.shared.PlayerScripts = ContendingPlayerScripts
else
	wax.shared.PlayerScripts = nil

	local ChildAddedConnection
	ChildAddedConnection = wax.shared.Connect(wax.shared.LocalPlayer.ChildAdded:Connect(function(Child)
		if Child:IsA("PlayerScripts") then
			wax.shared.PlayerScripts = cloneref(Child)
			wax.shared.Disconnect(ChildAddedConnection)
		end
	end))
end



wax.shared.trampoline_call = trampoline_call or (syn and syn.trampoline_call)
wax.shared.gethui = gethui or function()
	return wax.shared.CoreGui
end
wax.shared.checkcaller = checkcaller or function()
	return nil
end

wax.shared.restorefunction = function(Function: (...any) -> ...any, Silent: boolean?)
	local Original = wax.shared.Hooks[Function]

	if Silent and not Original then
		return
	end

	assert(Original, "Function not hooked")

	if restorefunction and isfunctionhooked(Function) then
		restorefunction(Function)
	else
		wax.shared.Hooking.HookFunction(Function, Original)
	end

	wax.shared.Hooks[Function] = nil
end
wax.shared.getrawmetatable = wax.shared.ExecutorSupport["getrawmetatable"].IsWorking
		and (getrawmetatable or debug.getmetatable)
	or function()
		return setmetatable({}, {
			__index = function()
				return function() end
			end,
		})
	end

local RawGetDebugId = clonefunction and clonefunction(game.GetDebugId) or game.GetDebugId

--[[
	DebugId lookup.

	This runs for every intercepted remote call, so the identity switch is only
	performed when the thread is not already elevated - the result is identical,
	but the common case costs one call instead of four.
]]
wax.shared.GetDebugId = function(Instance)
	if not setthreadidentity or not getthreadidentity then
		return RawGetDebugId(Instance)
	end

	local identity = getthreadidentity()
	if identity == 8 then
		return RawGetDebugId(Instance)
	end

	setthreadidentity(8)
	local id = RawGetDebugId(Instance)
	setthreadidentity(identity)
	return id
end

wax.shared.newcclosure = wax.shared.ExecutorName == "AWP"
		and function(f, name)
			local env = getfenv(f)
			local x = setmetatable({
				__F = f,
			}, {
				__index = env,
				__newindex = env,
			})

			local nf = function(...)
				return __F(...)
			end

			setfenv(nf, x) 
			return newcclosure(nf, name)
		end
	or newcclosure


wax.shared.queue_on_teleport = queue_on_teleport or queueonteleport or function(...) end
wax.shared.SafePack = require(script.Utils.SafePack)


wax.shared.IsPlayerModule = function(Origin: LocalScript | ModuleScript, Instance: Instance): boolean
	if Instance and Instance.ClassName ~= "BindableEvent" then
		return false
	end

	if not Origin or typeof(Origin) ~= "Instance" or not Origin.IsA(Origin, "LuaSourceContainer") then
		return false
	end

	local PlayerModule = Origin and Origin.FindFirstAncestor(Origin, "PlayerModule") or nil
	if not PlayerModule then
		return false
	end

	if PlayerModule.Parent == nil then
		return true
	end

	if wax.shared.PlayerScripts then
		return compareinstances(PlayerModule.Parent, wax.shared.PlayerScripts)
	end

	return false
end
--[[

	ShouldIgnore fast path.

	ShouldIgnore runs on every intercepted remote call, but its verdict only
	changes when the settings it reads change, so both verdicts are cached
	against the instance (weak keys: a destroyed remote drops its entry) and a
	repeat call for the same remote costs one table lookup instead of an
	IsDescendantOf walk plus settings reads.

	Only origin-independent verdicts are cached - the player-module check
	depends on the calling script, so those results are recomputed per call.
	The cache is dropped through `InvalidateShouldIgnoreCache`, which
	SettingSync.Save invokes whenever a setting is written.
]]
local IgnoredInstanceCache = setmetatable({}, { __mode = "k" })
local NotIgnoredInstanceCache = setmetatable({}, { __mode = "k" })

wax.shared.InvalidateShouldIgnoreCache = function()
	table.clear(IgnoredInstanceCache)
	table.clear(NotIgnoredInstanceCache)
end

wax.shared.ShouldIgnore = function(Instance, Origin)
	if IgnoredInstanceCache[Instance] then
		return true
	end

	if NotIgnoredInstanceCache[Instance] then
		return false
	end

	local Ignored = false
	local OriginDependent = false

	if not wax.shared.Settings.LogRobloxInternalEvents.Value then
		if Instance.IsDescendantOf(Instance, wax.shared.RobloxReplicatedStorage) then
			Ignored = true
		end
	end

	if not Ignored then
		Ignored = wax.shared.Settings.IgnoredRemotesDropdown.Value[Instance.ClassName] == true
	end

	if not Ignored and wax.shared.Settings.IgnorePlayerModule.Value then
		OriginDependent = true
		Ignored = wax.shared.IsPlayerModule(Origin, Instance)
	end

	if not OriginDependent then
		if Ignored then
			IgnoredInstanceCache[Instance] = true
		else
			NotIgnoredInstanceCache[Instance] = true
		end
	end

	return Ignored
end


wax.shared.GetTableLength = function(Table)
	if Table["n"] then
		return Table.n
	end

	local Length = 0
	for _, _ in pairs(Table) do
		Length += 1
	end
	return Length
end

wax.shared.GetTextBounds = function(Text: string, Font: Font, Size: number, Width: number?): (number, number)
	local Params = Instance.new("GetTextBoundsParams")
	Params.Text = Text
	Params.RichText = true
	Params.Font = Font
	Params.Size = Size
	Params.Width = Width or workspace.CurrentCamera.ViewportSize.X - 32

	local Bounds = wax.shared.TextService:GetTextBoundsAsync(Params)
	Params:Destroy()

	return Bounds.X, Bounds.Y
end

wax.shared.Unloaded = false
local CleanupSpy: (() -> ())?

wax.shared.Unload = function()
	if wax.shared.Unloaded then
		return
	end

	local identity = getthreadidentity and getthreadidentity()
	if setthreadidentity then setthreadidentity(8) end

	local PluginManager = wax.shared.CobaltPluginManager
	if PluginManager then
		for _, Plugin in PluginManager.Registry.Plugins do
			if not Plugin.UnloadCallbacks then
				continue
			end

			for _, Callback in Plugin.UnloadCallbacks or {} do
				task.spawn(pcall, Callback)
			end
		end
	end

	if CleanupSpy then
		local Cleanup = CleanupSpy
		CleanupSpy = nil
		pcall(Cleanup)
	end

	if CallFiltersSubscription then
		pcall(CallFiltersSubscription.Disconnect, CallFiltersSubscription)
		CallFiltersSubscription = nil
	end

	if wax.shared.LogThread then
		pcall(task.cancel, wax.shared.LogThread)
		wax.shared.LogThread = nil
	end

	if Ratelimiter then
		pcall(Ratelimiter.StopAll)
	end

	for _, Connection in pairs(wax.shared.Connections) do
		Connection:Disconnect()
	end
	table.clear(wax.shared.Connections)

	for _, Category in wax.shared.Logs do
		for _, Log in Category do
			Log:ClearCalls()
		end
		table.clear(Category)
	end
	table.clear(wax.shared.Logs)
	table.clear(wax.shared.IncomingLogConnectionFunctions)

	local NotificationQueue = wax.shared.LogNotificationQueue
	if NotificationQueue then
		table.clear(NotificationQueue.Items)
		table.clear(NotificationQueue.PendingByLog)
		NotificationQueue.Head = 1
		NotificationQueue.Tail = 0
	end

	getgenv().CobaltInitialized = false
	getgenv().Cobalt = nil

	wax.shared.Communicator:Destroy()
	wax.shared.ScreenGui:Destroy()

	wax.shared.Unloaded = true

	if identity then setthreadidentity(identity) end
end

local AnticheatData = require(script.Utils.Anticheats.Main)


wax.shared.Communicator = Instance.new("BindableEvent")

wax.shared.SetupLoggingConnection = function()
	if wax.shared.LogConnection then
		wax.shared.LogConnection:Disconnect()
	end

	if wax.shared.LogThread then
		pcall(task.cancel, wax.shared.LogThread)
		wax.shared.LogThread = nil
	end

	wax.shared.LogFileName = `Cobalt/Logs/{DateTime.now():ToIsoDate():gsub(":", "_")}.log`
	local FileLog = FileLogger.new(wax.shared.LogFileName, FileLogger.LOG_LEVELS.INFO, true)

	local LogQueue = {}
	local LogQueueHead = 1
	local LogQueueTail = 0
	local MaxQueuedLogEntries = 256
	wax.shared.LogThread = task.defer(function()
		while not wax.shared.Unloaded do
			while LogQueueHead <= LogQueueTail do
				local Entry = LogQueue[LogQueueHead]
				LogQueue[LogQueueHead] = nil
				LogQueueHead += 1

				if not Entry then
					continue
				end

				local RemoteInstance = Entry.Instance
				local Type = Entry.Type
				local CallOrderInLog = Entry.CallIndex
				local CallDataFromHook = Entry.CallData

				local success, err = pcall(function()
					local generatedCode = CodeGen:BuildCallCode(setmetatable({
						Instance = RemoteInstance,
						Type = Type,
					}, {
						__index = CallDataFromHook,
					}) :: any)

					local comprehensiveDataToSerialize = {
						RemoteInstanceInfo = {
							Name = RemoteInstance and RemoteInstance.Name,
							ClassName = RemoteInstance and RemoteInstance.ClassName,
							Path = RemoteInstance and InstanceSerializer.Serialize(RemoteInstance, {
								DisableNilParentHandler = true,
							}),
						},
						EventType = Type,
						CallOrderInLog = CallOrderInLog,
						DataFromHook = CallDataFromHook,
					}

					local serializedEventData = LuaEncode(
						comprehensiveDataToSerialize,
						{ Prettify = true, InsertCycles = true, UseInstancePaths = true }
					)

					local instanceName = RemoteInstance and RemoteInstance.Name or "UnknownInstance"
					local instanceClassName = RemoteInstance and RemoteInstance.ClassName or "UnknownClass"
					local instancePath = RemoteInstance
							and InstanceSerializer.Serialize(RemoteInstance, {
								DisableNilParentHandler = true,
							})
						or "UnknownPath"

					local logParts = {
						("Instance: %s (%s)"):format(instanceName, instanceClassName),
						("Path: %s"):format(instancePath),
						("Status: %s"):format(CallDataFromHook and CallDataFromHook.Blocked and "Blocked" or "Allowed"),
						("Call Order In Log: %s"):format(CallOrderInLog or "N/A"),
						"-------------------- Event Data --------------------",
						serializedEventData,
						"-------------------- Generated Code --------------------",
						generatedCode,
					}
					local logMessage = table.concat(logParts, "\n\t")
					local threadId = ("%s:%s"):format(Type or "S", instanceName)

					FileLog:Info(threadId, logMessage)
				end)

				if not success then
					local instanceNameForError = RemoteInstance and RemoteInstance.Name or "Unknown"
					FileLog:Error(
						"Logger",
						("Failed to log remote communication for %s:%s - %s"):format(
							Type or "UnknownType",
							instanceNameForError,
							tostring(err)
						)
					)

					warn(
						("Cobalt: Failed to log remote communication for %s:%s - %s"):format(
							Type or "UnknownType",
							instanceNameForError,
							tostring(err)
						)
					)
				end

				task.wait()
			end

			if LogQueueHead > LogQueueTail then
				table.clear(LogQueue)
				LogQueueHead = 1
				LogQueueTail = 0
			end

			task.wait()
		end

		
		table.clear(LogQueue)
		LogQueueHead = 1
		LogQueueTail = 0

		if wax.shared.LogThread then
			pcall(task.cancel, wax.shared.LogThread)
			wax.shared.LogThread = nil
		end
	end)

	return function(Batch)
		if typeof(Batch) ~= "table" then
			return
		end

		for _, Notification in Batch do
			local RemoteInstance = Notification.Instance
			local Type = Notification.Type
			local CallOrderInLog = Notification.CallIndex

			local LogEntry = Notification.Log or wax.shared.Logs[Type][wax.shared.GetDebugId(RemoteInstance)]
			if not LogEntry then
				continue
			end

			-- The notification carries the call itself (indices shift when a log
			-- trims), with the index lookup kept as a fallback.
			local CallDataFromHook = Notification.Call or LogEntry.Calls[CallOrderInLog]
			if not CallDataFromHook then
				continue
			end

			LogQueueTail += 1
			LogQueue[LogQueueTail] = {
				Instance = RemoteInstance,
				Type = Type,
				CallIndex = CallOrderInLog,
				CallData = CallDataFromHook,
			}

			-- File writes are orders of magnitude slower than the hooks that
			-- feed them, so the backlog is bounded: the newest entries win and
			-- the oldest are dropped instead of growing without limit.
			if LogQueueTail - LogQueueHead >= MaxQueuedLogEntries then
				LogQueue[LogQueueHead] = nil
				LogQueueHead += 1
			end
		end
	end
end

if wax.shared.SaveManager:GetState("EnableLogging") then
	local LogConnection = wax.shared.SetupLoggingConnection()
	wax.shared.LogConnection = wax.shared.Connect(wax.shared.Communicator.Event:Connect(LogConnection))
end

wax.shared.Log = require(script.Utils.Log)
wax.shared.Logs = {
	Outgoing = {},
	Incoming = {},
}

wax.shared.NewLog = function(Instance, Type, CallingScript, DebugId)
	local Log = wax.shared.Log.new(Instance, Type, wax.shared.GetTableLength(wax.shared.Logs[Type]) + 1, CallingScript)
	wax.shared.Logs[Type][DebugId] = Log
	return Log
end

local Window = require(script.Window)
if not wax.shared.IsOutgoingLoggable and not wax.shared.SaveManager:GetState("LimitedLoggingAcknowledged") then
	Window.Dialogs.LoggingDisabled.Open(Window)
end

CleanupSpy = require(script.Spy)()

local PluginManager = require(script.Utils.Plugins.Manager)
PluginManager.SetupPlugins()

wax.shared.CobaltPluginManager = PluginManager

wax.shared.Connect(wax.shared.LocalPlayer.OnTeleport:Connect(function()
	if not wax.shared.SaveManager:GetState("ExecuteOnTeleport") then
		return
	end

	-- Relaunch through the lightweight loader. It will use a cached/local
	-- cobalt.luau when present and otherwise download the generated bundle, so
	-- ExecuteOnTeleport also works for one-line loadstring users.
	wax.shared.queue_on_teleport([[
		if getgenv().CobaltAutoExecuted then
			return
		end

		local loaderUrl = "https://raw.githubusercontent.com/Kira762/cobalt_optimized/main/loader.luau"
		local ok, loader = pcall(function()
			return game:HttpGet(loaderUrl)
		end)
		local fn = ok and type(loader) == "string" and loadstring(loader, "@cobalt-loader.luau")
		if fn then
			getgenv().CobaltAutoExecuted = true
			fn()
		end
	]])
end))

getgenv().Cobalt = wax

task.wait(1)
if AnticheatData.Disabled then
	wax.shared.Sonner.success(`Cobalt has bypassed {AnticheatData.Name} (anticheat detected)`)
end
