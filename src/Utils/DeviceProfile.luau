--[[
	DeviceProfile

	One-shot device capability detection, run once at boot.

	The result drives every adaptive budget in Cobalt (capture budgets, call
	frame queue caps, animation limits, page sizes, ...).  Consumers read the
	preset fields at module load time - they are plain numbers, so reading them
	costs nothing in a hot path.

	Tier signals (weakest first):

	- `UserInputService.TouchEnabled` - phones/tablets cap out at "medium".
	- `workspace.CurrentCamera.ViewportSize` - small screens (< 500px height)
	  and small windows (< 800px) downgrade.
	- `Stats` memory if the executor exposes it - low data memory downgrades.
	- executor name - a known premium desktop executor can promote one tier.
	- frame time sampling - a median frame above 18ms downgrades, above 33ms
	  floors at "low".

	`Detect` is synchronous and cheap.  `Init` additionally samples ~10 frames
	so the GPU/CPU signal is included; it yields, so it must run before the
	modules that capture the preset values (src/init.luau does this before
	requiring ExecutorSupport, whose tests overlap with the sampling window).
]]

local DeviceProfile = {
	Tier = "medium",

	IsMobile = false,
	IsSmallScreen = false,
	ViewportSize = nil,

	-- Tier presets (see TIER_PRESETS below).  Kept as direct fields so hot
	-- paths can capture them into locals once at module load.
	CaptureBudgetPerRemote = 120,
	CaptureBudgetGlobal = 600,
	MaxCallFrameQueue = 40,
	ArgumentBuildSliceMs = 4,
	MaxCallsPerPage = 20,
	MaxNotificationsPerHeartbeat = 96,
	MaxPendingNotifications = 256,
	MaxAnimations = 64,
	RowStaggerStep = 0.018,
	LogButtonUpdateSeconds = 0.1,
}

-- Frame-time sampling.  A median frame above FRAME_SLOW_MS downgrades one
-- tier; above FRAME_VERY_SLOW_MS the device floors at "low".
local FRAME_SAMPLE_COUNT = 12
local FRAME_SAMPLE_WARMUP = 2
local FRAME_SLOW_MS = 18
local FRAME_VERY_SLOW_MS = 33

-- Screen height at or below this is treated as a phone-sized viewport.
local SMALL_SCREEN_HEIGHT = 500
-- Window height below this downgrades one tier (full desktop monitors are far
-- above it; small side-by-side windows are not).
local MEDIUM_SCREEN_HEIGHT = 800
-- Data memory (MB) under which a device is treated as memory constrained.
local LOW_MEMORY_MB = 1500
local VERY_LOW_MEMORY_MB = 800

-- Substring match against identifyexecutor(); desktop executors in this list
-- are assumed to have enough headroom to promote one tier.
local PremiumExecutorHints = {
	"synapse",
	"script-ware",
	"scriptware",
	"sirhurt",
	"protosmasher",
	"sentinel",
	"awp",
	"wave",
	"krnl",
	"oxygen",
}

local TIER_ORDER = { "low", "medium", "high" }
local TIER_INDEX = { low = 1, medium = 2, high = 3 }

local TIER_PRESETS = {
	high = {
		CaptureBudgetPerRemote = 120,
		CaptureBudgetGlobal = 600,
		MaxCallFrameQueue = 40,
		ArgumentBuildSliceMs = 4,
		MaxCallsPerPage = 25,
		MaxNotificationsPerHeartbeat = 96,
		MaxPendingNotifications = 256,
		MaxAnimations = 64,
		RowStaggerStep = 0.018,
		LogButtonUpdateSeconds = 0.1,
	},
	medium = {
		CaptureBudgetPerRemote = 80,
		CaptureBudgetGlobal = 300,
		MaxCallFrameQueue = 24,
		ArgumentBuildSliceMs = 3,
		MaxCallsPerPage = 20,
		MaxNotificationsPerHeartbeat = 48,
		MaxPendingNotifications = 128,
		MaxAnimations = 32,
		RowStaggerStep = 0.012,
		LogButtonUpdateSeconds = 0.15,
	},
	low = {
		CaptureBudgetPerRemote = 40,
		CaptureBudgetGlobal = 150,
		MaxCallFrameQueue = 12,
		ArgumentBuildSliceMs = 2,
		MaxCallsPerPage = 15,
		MaxNotificationsPerHeartbeat = 24,
		MaxPendingNotifications = 64,
		MaxAnimations = 8,
		RowStaggerStep = 0,
		LogButtonUpdateSeconds = 0.2,
	},
}

local function ApplyPreset(Tier: string)
	local Preset = TIER_PRESETS[Tier] or TIER_PRESETS.medium
	for Key, Value in Preset do
		DeviceProfile[Key] = Value
	end
end

local function GetExecutorName(): string
	local Success, Name = pcall(function()
		return identifyexecutor and identifyexecutor() or ""
	end)
	if Success and type(Name) == "string" then
		return string.lower(Name)
	end

	return ""
end

local function IsPremiumExecutor(): boolean
	local Name = GetExecutorName()
	if Name == "" then
		return false
	end

	for _, Hint in PremiumExecutorHints do
		if string.find(Name, Hint, 1, true) then
			return true
		end
	end

	return false
end

local function IsTouchDevice(): boolean
	local Success, Enabled = pcall(function()
		return typeof(UserInputService) == "Instance" and UserInputService.TouchEnabled == true
	end)
	return Success and Enabled == true
end

local function GetViewportSize()
	local Success, Size = pcall(function()
		local Camera = typeof(workspace) == "Instance" and workspace.CurrentCamera or nil
		if Camera then
			return Camera.ViewportSize
		end
		return nil
	end)

	if Success and typeof(Size) == "Vector2" then
		return Size
	end

	return nil
end

local function GetDataMemoryMB(): number?
	local Success, MemoryMB = pcall(function()
		local StatsService = game:GetService("Stats")
		-- Executors differ in what they expose; try the common surfaces.
		if type(StatsService.DataMemory) == "number" then
			return StatsService.DataMemory
		end
		if type(StatsService.GetTotalMemoryUsageMb) == "function" then
			return StatsService:GetTotalMemoryUsageMb()
		end
		return nil
	end)

	if Success and type(MemoryMB) == "number" and MemoryMB > 0 then
		return MemoryMB
	end

	return nil
end

--[[
	Static, non-yielding detection.  Safe to call anywhere; leaves the frame
	time signal out of the tier decision until `Init` runs.
]]
function DeviceProfile.Detect()
	local Viewport = GetViewportSize()
	local ViewportHeight = Viewport and Viewport.Y or math.huge

	local Tier = 3 -- high

	if IsTouchDevice() then
		DeviceProfile.IsMobile = true
		Tier = math.min(Tier, 2) -- touch caps at medium
	end

	if Viewport and ViewportHeight <= SMALL_SCREEN_HEIGHT then
		DeviceProfile.IsSmallScreen = true
		Tier = 1 -- small screen floors at low
	elseif Viewport and ViewportHeight < MEDIUM_SCREEN_HEIGHT then
		Tier = math.min(Tier, 2)
	end

	local MemoryMB = GetDataMemoryMB()
	if MemoryMB then
		if MemoryMB <= VERY_LOW_MEMORY_MB then
			Tier = 1
		elseif MemoryMB <= LOW_MEMORY_MB then
			Tier = math.min(Tier, 2)
		end
	end

	if IsPremiumExecutor() then
		Tier = math.min(Tier + 1, if DeviceProfile.IsMobile then 2 else 3)
	end

	DeviceProfile.ViewportSize = Viewport
	DeviceProfile.Tier = TIER_ORDER[Tier] or "medium"
	ApplyPreset(DeviceProfile.Tier)
	return DeviceProfile.Tier
end

-- Frame-time sampling state (drive with BeginFrameSampling/FinishDetection).
local SamplingDone = true
local SamplingMedianMs = nil

local function SampleFrameTime(): number?
	local Success, MedianMs = pcall(function()
		local RunService = game:GetService("RunService")
		local Signal = RunService.Heartbeat

		local Samples = table.create(FRAME_SAMPLE_COUNT)
		for Index = 1, FRAME_SAMPLE_COUNT do
			local Start = os.clock()
			Signal:Wait()
			Samples[Index] = (os.clock() - Start) * 1000
		end

		table.sort(Samples)
		return Samples[math.floor((FRAME_SAMPLE_COUNT + 1) / 2)]
	end)

	if Success and type(MedianMs) == "number" then
		return MedianMs
	end

	return nil
end

--[[
	Collects the frame-time signal in the background so it overlaps the rest
	of boot (ExecutorSupport tests, asset preloading).  Does not yield the
	caller.  `FinishDetection` blocks until the samples are in.
]]
function DeviceProfile.BeginFrameSampling()
	SamplingDone = false

	task.spawn(function()
		SamplingMedianMs = SampleFrameTime()
		SamplingDone = true
	end)
end

function DeviceProfile.FinishDetection(): string
	if not SamplingDone then
		-- Each sample costs exactly one Heartbeat, so this is bounded.
		pcall(function()
			local RunService = game:GetService("RunService")
			local Deadline = os.clock() + 1
			while not SamplingDone and os.clock() < Deadline do
				RunService.Heartbeat:Wait()
			end
		end)
	end

	if SamplingMedianMs then
		local TierIndex = TIER_INDEX[DeviceProfile.Tier] or 2

		if SamplingMedianMs >= FRAME_VERY_SLOW_MS then
			TierIndex = 1
		elseif SamplingMedianMs >= FRAME_SLOW_MS then
			TierIndex = math.max(1, TierIndex - 1)
		end

		-- A slow frame time is a stronger signal than a premium executor
		-- name, but never invalidates the touch cap.
		if DeviceProfile.IsMobile then
			TierIndex = math.min(TierIndex, 2)
		end

		DeviceProfile.Tier = TIER_ORDER[TierIndex] or "medium"
		ApplyPreset(DeviceProfile.Tier)
	end

	return DeviceProfile.Tier
end

--[[
	Full boot-time detection: static signals plus frame sampling.  Yields for
	about FRAME_SAMPLE_COUNT frames.  Call once, before anything that captures
	the preset fields.
]]
function DeviceProfile.Init(): string
	DeviceProfile.Detect()
	DeviceProfile.BeginFrameSampling()
	return DeviceProfile.FinishDetection()
end

-- Static-only detection at load time so the module is never left on defaults
-- when boot forgets to call Init (actors, plugins, tests).
pcall(function()
	DeviceProfile.Detect()
end)

return DeviceProfile
