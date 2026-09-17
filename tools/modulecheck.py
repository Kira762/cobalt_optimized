#!/usr/bin/env python3
"""Generate a Luau harness that loads every ModuleScript in cobalt.luau through
the bundle's real LoadScript(), then prints how many actually executed.

The harness runs cobalt.luau with `readfile` wired to fail and `require`
wired to reject strings. This exercises the self-contained bundle without
assuming that the source tree or local assets are present.

  python3 tools/modulecheck.py <cobalt.luau> <out.luau>
  luau <out.luau>

A healthy bundle reports a mix of `table` and `function` first-return-values
(modules that legitimately `return` a function).  A bundle whose closures only
*return* the wrapper instead of invoking it reports every module as a bare
`function` under "UNINVOKED".
"""
from __future__ import annotations

import pathlib
import sys


def bracket(s: str) -> str:
    level = 0
    while True:
        close = "]" + "=" * level + "]"
        if close not in s:
            return "[" + "=" * level + "[" + "\n" + s + "\n" + close
        level += 1
        if level > 12:
            raise RuntimeError("cannot bracket")


# Exposes the bundle internals just before it starts running scripts, so the
# harness can drive LoadScript() itself instead of only watching script #1.
# SharedEnvironment is the raw table behind wax.shared: the harness seeds the
# few services src/init.luau would publish so that module bodies which read
# them at load time (Utils.Log's Heartbeat consumer) can be exercised too.
EPILOGUE_MARKER = "for _, ScriptRef in next, ScriptsToRun do"
EPILOGUE = (
    "getgenv().__CobaltInternals = { LoadScript = LoadScript, "
    "RefBindings = RefBindings, ScriptClosures = ScriptClosures, "
    "Shared = SharedEnvironment }\n\n"
)

STUBS = r'''
local RealType = type
local RealError = error

local InstanceMT = {}
InstanceMT.__index = function(self, k)
    if k == "ClassName" then return rawget(self, "__class") or "Instance" end
    return nil
end
local function NewInstance(cls)
    return setmetatable({ __class = cls, Name = cls }, InstanceMT)
end

-- A do-nothing RBXScriptSignal.  Modules that wire a Heartbeat consumer at load
-- time must still be loadable here, otherwise the harness cannot tell a missing
-- executor API apart from a module that never runs at all.
local FakeConnection = { Enabled = true }
FakeConnection.__index = FakeConnection
function FakeConnection.Disconnect() end
local FakeSignal = {
    Connect = function() return FakeConnection end,
    ConnectParallel = function() return FakeConnection end,
    Once = function() return FakeConnection end,
    Wait = function() return 0 end,
    Fire = function() end,
}

local Services = {}
game = {
    GetService = function(_, name)
        if not Services[name] then Services[name] = NewInstance(name) end
        return Services[name]
    end,
}
Services.RunService = setmetatable({ __class = "RunService" }, {
    __index = function(_, k)
        if k == "Heartbeat" or k == "RenderStepped" or k == "Stepped" then
            return FakeSignal
        end
        return nil
    end,
})
Services.HttpService = setmetatable({ __class = "HttpService" }, {
    __index = function(_, k)
        if k == "GenerateGUID" then return function() return "GUID-STUB" end end
        if k == "JSONEncode" then return function() return "{}" end end
        if k == "JSONDecode" then return function() return {} end end
        return nil
    end,
})
workspace = NewInstance("Workspace")
Instance = { new = NewInstance }

function typeof(v)
    local t = RealType(v)
    if t == "table" and getmetatable(v) == InstanceMT then return "Instance" end
    return t
end
function tick() return os.clock() end
local GENV = {}
function getgenv() return GENV end
function identifyexecutor() return "Harness", "0.0.0" end
function cloneref(v) return v end
function getconnections() return {} end
function isfile() return false end
function listfiles() return {} end
function isfolder() return false end
function getnamecallmethod() return "" end
function checkcaller() return false end
function getrawmetatable() return nil end
function setreadonly() end
function hookmetamethod() end
function newcclosure(f) return f end
function isexecutorclosure() return false end
function getgc() return {} end
function getscripts() return {} end
function getloadedmodules() return {} end
function getinstances() return {} end
function getnilinstances() return {} end
function queue_on_teleport() end
function islclosure() return true end
function getthreadidentity() return 8 end
function setthreadidentity() end
function gethui() return NewInstance("Hui") end
function getcustomasset(p) return "rbxasset://" .. tostring(p) end
function isourclosure() return false end
function getscriptbytecode() return "" end
function dumpstring() return "" end
function getprotos() return {} end
function getconstants() return {} end
function getupvalues() return {} end
function getupvalue() return nil end
function setupvalue() end
function getstates() return {} end
function getrunningscripts() return {} end
function getactor() return nil end
function getcommchannel() return nil end
function getluastate() return nil end
function get_current_actor() return nil end
function trampoline_call() end
function compareinstances(a, b) return a == b end
function getscriptclosure() return nil end
function firesignal() end
function firetouchinterest() end
function hookfunction() end
function replaceclosure() end
function getaddress() return "0x0" end
function getcallbackvalue() return nil end
function setfflag() end
task = {
    spawn = function(f, ...) pcall(f, ...) end,
    defer = function() end,
    delay = function(_, f, ...) pcall(f, ...) end,
    wait = function() return 0 end,
    cancel = function() end,
    synchronize = function() end,
    desynchronize = function() end,
}

-- Roblox's require only accepts Instances; a string alias is an error.
local RealRequire = require
require = function(module)
    if RealType(module) ~= "table" then
        RealError("Expected ':' not '.' calling member function require")
    end
    return RealRequire(module)
end
-- Nothing is on disk: this is the remote-load case.
readfile = function(path) RealError("failed to read file: " .. tostring(path)) end

print("== module check: " .. #COBALT_SOURCE .. " bytes ==")
local Fn, CompileErr = loadstring(COBALT_SOURCE, "cobalt.luau")
if not Fn then
    print("COMPILE FAILED: " .. tostring(CompileErr))
    error("aborting module check", 0)
end
print("loadstring(cobalt.luau) compiled OK")
local RunOk, RunErr = pcall(Fn)
print("top-level chunk ok=" .. tostring(RunOk) .. (RunOk and "" or ("  err=" .. tostring(RunErr))))

local I = getgenv().__CobaltInternals
if not I then
    print("FATAL: internals epilogue did not run - module body never executed")
    error("aborting module check", 0)
end

local function FindModuleRef(FullName)
    for refId = 1, 10000 do
        local ref = I.RefBindings[refId]
        if ref and ref.ClassName == "ModuleScript" and I.ScriptClosures[ref] then
            local okName, fullName = pcall(function() return ref:GetFullName() end)
            if okName and fullName == FullName then
                return ref
            end
        end
    end
    return nil
end

-- src/init.luau publishes these before any consumer module loads, so seed them
-- the same way.  Utils.Connect is the real module (it publishes Connect and
-- Disconnect); RunService is a test double for the Roblox service.
local ConnectRef = FindModuleRef("[Cobalt].cobalt.Utils.Connect")
assert(ConnectRef, "setup: Utils.Connect module not found")
local okConnect, connectErr = pcall(I.LoadScript, ConnectRef)
assert(okConnect, "setup: Utils.Connect failed to load: " .. tostring(connectErr))
I.Shared.RunService = game:GetService("RunService")

local okCount, failCount = 0, 0
local failures, kinds, uninvoked, nilCalls = {}, {}, {}, {}
for refId = 1, 10000 do
    local ref = I.RefBindings[refId]
    if ref and ref.ClassName == "ModuleScript" and I.ScriptClosures[ref] then
        local ok, res = pcall(I.LoadScript, ref)
        if ok then
            okCount = okCount + 1
            kinds[type(res)] = (kinds[type(res)] or 0) + 1
            if type(res) == "function" then
                table.insert(uninvoked, refId .. " " .. tostring(ref:GetFullName()))
            end
        else
            failCount = failCount + 1
            local entry = refId .. " " .. tostring(ref:GetFullName()) .. " -> " .. tostring(res)
            table.insert(failures, entry)

            -- A missing Roblox/executor API in this stub env surfaces as
            -- "attempt to index nil with 'X'".  "attempt to call a nil value"
            -- is different: something was called that no environment provides,
            -- which means the module references an identifier that does not
            -- exist (e.g. Log's former bare `ProfileValue(...)` call).
            if tostring(res):find("attempt to call a nil value", 1, true) then
                table.insert(nilCalls, entry)
            end
        end
    end
end

print("ModuleScripts executed and returned : " .. okCount)
print("ModuleScripts errored               : " .. failCount)
local kindParts = {}
for k, v in pairs(kinds) do table.insert(kindParts, k .. "=" .. v) end
table.sort(kindParts)
print("first-return-value kinds            : " .. (next(kindParts) and table.concat(kindParts, ", ") or "(none)"))
print("returned a bare function            : " .. #uninvoked .. " (expected: the 5 modules that `return` a function)")
for _, u in ipairs(uninvoked) do print("  fn " .. u) end

-- A bundle whose closures never invoke their body shows up as 100% functions
-- and 0% tables, and the LocalScript body is never reached at all.
if (kinds.table or 0) == 0 then
    print("RESULT: FAIL - no module returned a table; closures are not invoking their bodies")
    error("aborting module check", 0)
end
-- Regression: icon-less options (array-style dropdown values such as the
-- interface-scale list, menu entries without Icon) call GetIcon/SetIcon with
-- nil. Once the icon module loads this must be a safe no-op - a nil cache
-- *write* aborts the whole Window load with "table index is nil".
local IconsRef = FindModuleRef("[Cobalt].cobalt.Utils.UI.Assets.Icons")
assert(IconsRef, "regression setup: icons module not found")
local okIcons, Icons = pcall(I.LoadScript, IconsRef)
assert(okIcons, "regression setup: icons module failed to load: " .. tostring(Icons))
local okGet, gotIcon = pcall(Icons.GetIcon, nil)
assert(okGet, "REGRESSION: GetIcon(nil) errored: " .. tostring(gotIcon))
assert(gotIcon == nil, "REGRESSION: GetIcon(nil) must return nil")
local okSet, setErr = pcall(Icons.SetIcon, {}, nil)
assert(okSet, "REGRESSION: SetIcon(image, nil) errored: " .. tostring(setErr))
-- This stub env serves an empty 200 body, so the icon module loads but is
-- unusable (IconsModule is nil): even ordinary lookups must degrade to nil
-- instead of throwing outside the GetAsset pcall.
local okKnown, knownIcon = pcall(Icons.GetIcon, "chevron-down")
assert(okKnown, "REGRESSION: GetIcon(valid) errored with unusable icon module: " .. tostring(knownIcon))
assert(knownIcon == nil, "REGRESSION: GetIcon(valid) must return nil when the icon module is unusable")
print("icon nil-name regression check     : OK")

-- Regression: src/Utils/Log.luau sized its notification queue with a bare
-- `ProfileValue(...)` call that no environment defines.  It aborted the module
-- body, and the whole boot died with a line number that pointed at init.luau:
--   [Cobalt].cobalt:95: attempt to call a nil value
-- The module must load and hand back its table in a state with no Roblox APIs.
local LogRef = FindModuleRef("[Cobalt].cobalt.Utils.Log")
assert(LogRef, "regression setup: Utils.Log module not found")
local okLog, LogModule = pcall(I.LoadScript, LogRef)
assert(okLog, "REGRESSION: Utils.Log failed to load: " .. tostring(LogModule))
assert(type(LogModule) == "table" and type(LogModule.new) == "function",
    "REGRESSION: Utils.Log did not return its module table")
print("Utils.Log load regression check    : OK")

-- Regression: FormatError() re-translated messages that a nested module had
-- already translated, so a failure two requires down surfaced as a line inside
-- the *caller* - that is how `Utils.Log:106` reached the user as
-- `[Cobalt].cobalt:95`.  The deepest module and line must survive.
local NestedRef = FindModuleRef("[Cobalt].cobalt.Spy.Hooks.RakNet.PacketProcessor")
local okNested, nestedErr = nil, nil
if NestedRef then
    okNested, nestedErr = pcall(I.LoadScript, NestedRef)
end
if NestedRef and not okNested and tostring(nestedErr):find("AccessModifierType", 1, true) then
    assert(tostring(nestedErr):find("[Cobalt].cobalt.Utils.Hook.RakNet.Constants:", 1, true),
        "REGRESSION: nested error lost its deepest attribution: " .. tostring(nestedErr))
    print("nested error attribution check     : OK")
end

-- The actor environment is a generated chunk: bundle.py inlines src/Utils/Log.luau
-- into a serialized string that the bundle itself never compiles, so a syntax
-- error there would only appear once an actor starts.  Compile it here.
local ActorEnvRef = nil
for refId = 1, 10000 do
    local ref = I.RefBindings[refId]
    if ref and ref.ClassName == "StringValue" and ref.Name == "Environment" then
        ActorEnvRef = ref
    end
end
assert(ActorEnvRef, "generated actor Environment source not found")
local ActorEnvFn, ActorEnvErr = loadstring(ActorEnvRef.Value, "actor-environment")
assert(ActorEnvFn, "REGRESSION: generated actor environment does not compile: " .. tostring(ActorEnvErr))
print("actor environment compile check    : OK (" .. #ActorEnvRef.Value .. " bytes)")

-- The actor environment is a standalone chunk in another state: it has no wax
-- `require`, so the only requires that may appear in it are the guarded
-- `wax.shared.X or require(...)` form, where the shared value is always set
-- first and the require never actually runs.  An unguarded require - e.g. a
-- `require("@src/Utils/DeviceProfile")` added to src/Utils/Log.luau, which
-- bundle.py inlines here - kills the actor at start with Roblox's
-- "Expected ':' not '.' calling member function require".
local UnguardedRequires = {}
local ActorLineNo = 0
local InBlockComment = false
for ActorLine in string.gmatch(ActorEnvRef.Value .. "\n", "(.-)\n") do
    ActorLineNo = ActorLineNo + 1

    -- Prose only: skip comments so a sentence mentioning require() is not a hit.
    local Trimmed = ActorLine:gsub("^%s+", "")
    if InBlockComment then
        if Trimmed:find("]]", 1, true) then
            InBlockComment = false
        end
    elseif Trimmed:sub(1, 4) == "--[[" then
        InBlockComment = not Trimmed:find("]]", 5, true)
    elseif Trimmed:sub(1, 2) ~= "--" and ActorLine:find("require(", 1, true)
        and not ActorLine:match("wax%.shared%.%w+ or require%(") then
        table.insert(UnguardedRequires, "actor environment line " .. ActorLineNo .. ": " .. Trimmed)
    end
end
if #UnguardedRequires > 0 then
    print("RESULT: FAIL - the actor environment calls require() outside a wax.shared guard:")
    for _, line in ipairs(UnguardedRequires) do print("  actor " .. line) end
    error("aborting module check", 0)
end
print("actor environment require guard    : OK")

if #nilCalls > 0 then
    print("RESULT: FAIL - " .. #nilCalls .. " module(s) call an identifier that does not exist:")
    for _, f in ipairs(nilCalls) do print("  nil " .. f) end
    error("aborting module check", 0)
end

print("RESULT: OK - module bodies execute under the self-contained bundle configuration")
if #failures > 0 then
    print("(the " .. #failures .. " errors below are missing executor APIs in this stub env, not load failures)")
    for _, f in ipairs(failures) do print("  env " .. f) end
end
'''


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    source = pathlib.Path(sys.argv[1]).read_text()
    marker_index = source.rindex(EPILOGUE_MARKER)
    source = source[:marker_index] + EPILOGUE + source[marker_index:]
    pathlib.Path(sys.argv[2]).write_text("local COBALT_SOURCE = " + bracket(source) + "\n" + STUBS)
    print("wrote", sys.argv[2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
