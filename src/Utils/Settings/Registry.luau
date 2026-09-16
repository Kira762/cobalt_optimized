local Constants = require("@src/Window/Constants")
local Validation = require(script.Parent.Parent.Validation)

local Setting = require(script.Parent.Setting)

local Schema = Validation.Schema

local PositiveInteger = Schema.union({ Schema.number(), Schema.string() }):refine(function(Value)
	local Number = tonumber(Value)
	return Number ~= nil and Number >= 1 and Number % 1 == 0
end, "must be a positive integer")

local RemoteClassSelection = Schema.table():refine(function(Value)
	for ClassName, Enabled in Value do
		if type(ClassName) ~= "string" or type(Enabled) ~= "boolean" then
			return false
		end
	end
	return true
end, "must map remote class names to booleans")

return {
	
	LimitedLoggingAcknowledged = Setting.new({
		Key = "LimitedLoggingAcknowledged",
		Default = false,
		Schema = Schema.boolean(),
	}),

	
	WindowDPIScale = Setting.new({
		Key = "WindowDPIScale",
		Default = "100%",
		Schema = Schema.enum({ "50%", "75%", "100%", "125%", "150%" }),
		UI = {
			Type = "Dropdown",
			Text = "Interface Scale",
			Values = { "50%", "75%", "100%", "125%", "150%" },
		},
	}),
	CallsPerPage = Setting.new({
		Key = "CallsPerPage",
		Aliases = { "MaxItemPerPages" },
		Default = 20,
		Schema = PositiveInteger,
		UI = {
			Type = "TextBox",
			Text = "Calls Per Page",
			NumericOnly = true,
		},
	}),

	--[[
		Interface motion.  Turning this off makes every transition instant; the
		end state of the interface is identical either way, so it is purely a
		comfort / low-end-device switch.
	]]
	AnimationsEnabled = Setting.new({
		Key = "AnimationsEnabled",
		Default = false,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Interface Animations",
		},
	}),

	--[[
		Retention limit per remote.  Captured calls hold a deep copy of their
		arguments for the whole session, so without a limit a busy game grows
		memory until the device kills Roblox.  Old calls are dropped once a remote
		exceeds this many.
	]]
	MaxCallsPerRemote = Setting.new({
		Key = "MaxCallsPerRemote",
		Default = 500,
		Schema = PositiveInteger,
		UI = {
			Type = "TextBox",
			Text = "Calls Kept Per Remote",
			NumericOnly = true,
		},
	}),
	ExecuteOnTeleport = Setting.new({
		Key = "ExecuteOnTeleport",
		Default = false,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Relaunch After Teleport",
		},
	}),


	
	RakNetHooks = Setting.new({
		Key = "RakNetHooks",
		Default = false,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Use RakNet Hooks on Relaunch (Experimental)",
			Risky = true,
		},
	}),
	OthHooks = Setting.new({
		Key = "OthHooks",
		Default = true,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Use Oth Hooks on Relaunch",
			Risky = false,
		},
	}),
	LogRobloxInternalEvents = Setting.new({
		Key = "LogRobloxInternalEvents",
		Default = false,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Capture Roblox Internal Events",
		},
	}),
	LogActors = Setting.new({
		Key = "LogActors",
		Default = true,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Capture Actor Calls",
		},
	}),
	LogBlockedRemotes = Setting.new({
		Key = "LogBlockedRemotes",
		Default = false,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Record Blocked Calls",
		},
	}),


	
	IgnoredRemotesDropdown = Setting.new({
		Key = "IgnoredRemotesDropdown",
		Default = {
			BindableEvent = true,
			BindableFunction = true,
		},
		Schema = RemoteClassSelection,
		UI = {
			Type = "Dropdown",
			Text = "Ignored Remote Classes",
			Values = Constants.InstanceClassImages,
			AllowNull = true,
			Multi = true,
		},
	}),
	AutoIgnoreSpammyEvents = Setting.new({
		Key = "AutoIgnoreSpammyEvents",
		-- Protect the game by default; the user can turn this off when a full
		-- high-frequency trace is intentional.
		Default = true,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Auto-ignore High-frequency Calls",
		},
	}),
	IgnorePlayerModule = Setting.new({
		Key = "IgnorePlayerModule",
		Default = true,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Ignore PlayerModule Calls",
		},
	}),
	ShowExecutorLogs = Setting.new({
		Key = "ShowExecutorLogs",
		Default = true,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Show Executor Calls",
		},
	}),


	
	InstancePathLookupChain = Setting.new({
		Key = "InstancePathLookupChain",
		Default = "Index",
		Schema = Schema.enum({ "Index", "WaitForChild", "FindFirstChild" }),
		UI = {
			Type = "Dropdown",
			Text = "Instance Path Style",
			Values = {
				Index = "file",
				WaitForChild = "file-clock",
				FindFirstChild = "file-search",
			},
		},
	}),
	EventReferenceStrategy = Setting.new({
		Key = "EventReferenceStrategy",
		Default = "GetNil",
		Schema = Schema.enum({ "GetNil", "Upvalue Lookup" }),
		UI = {
			Type = "Dropdown",
			Text = "Nil Instance Strategy",
			Values = {
				GetNil = "bug",
				["Upvalue Lookup"] = "circle-fading-arrow-up",
			},
		},
	}),
	PreferBufferFromString = Setting.new({
		Key = "PreferBufferFromString",
		Default = false,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Use buffer.fromstring()",
		},
	}),
	ShowWatermark = Setting.new({
		Key = "ShowWatermark",
		Default = true,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Include Cobalt Header",
		},
	}),


	
	EnableLogging = Setting.new({
		Key = "EnableLogging",
		Default = false,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Save Calls to File",
		},
	}),
	

	
	DisableNonEssentialChecks = Setting.new({
		Key = "DisableNonEssentialChecks",
		Default = false,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Skip Optional Executor Checks",
		},
	}),
	AnticheatBypass = Setting.new({
		Key = "AnticheatBypass",
		Default = false,
		Schema = Schema.boolean(),
		UI = {
			Type = "Checkbox",
			Text = "Enable Anti-Cheat Bypass",
		},
	}),
}
