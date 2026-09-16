-- Cobalt loader (paste this whole file into the executor)
--
-- Load order:
--   1. Local file  - dev/after-clone, preferred when present
--   2. Remote      - raw GitHub fallback, always works
--
-- Why this instead of a bare readfile:
--   * readfile() relative paths resolve against the EXECUTOR'S script
--     directory, not wherever you ran `git clone`. A bare
--     readfile("cobalt.luau") hard-errors ("failed to read file") if the
--     repo isn't inside that folder, and it kills the script before any
--     fallback runs.
--   * For dev with src/ present, clone the repo INTO the script directory
--     (so readfile("src/init.luau") resolves) - then local files win and
--     cobalt.luau auto-prefers src/ over its embedded fallback.

local REMOTE_URL = "https://raw.githubusercontent.com/Kira762/cobalt_optimized/main/cobalt.luau"

local function TryRead(Candidates)
	if typeof(readfile) ~= "function" then
		return nil
	end

	for i = 1, #Candidates do
		local Ok, Res = pcall(function()
			return readfile(Candidates[i])
		end)
		if Ok and type(Res) == "string" and Res ~= "" then
			print("[Cobalt] source: local file " .. Candidates[i])
			return Res
		end
	end

	return nil
end

local LocalCandidates = {
	"cobalt.luau",
	"cobalt_optimized/cobalt.luau",
}

-- Absolute fallbacks: the clone may live outside the script directory.
if typeof(getworkingdirectory) == "function" then
		local Ok, Dir = pcall(getworkingdirectory)
		if Ok and type(Dir) == "string" and Dir ~= "" then
			-- Some executors (e.g. Synapse) return a trailing separator.
			local Last = Dir:sub(-1)
			if (Last == "/" or Last == "\\") and #Dir > 3 then
				Dir = Dir:sub(1, -2)
			end
			table.insert(LocalCandidates, Dir .. "/cobalt.luau")
			table.insert(LocalCandidates, Dir .. "/cobalt_optimized/cobalt.luau")
		end
end

local Source = TryRead(LocalCandidates)

if not Source then
	local Ok, Res = pcall(function()
		return game:HttpGet(REMOTE_URL)
	end)
	if Ok and type(Res) == "string" and Res ~= "" then
		print("[Cobalt] source: remote " .. REMOTE_URL)
		Source = Res
	else
		error("[Cobalt] could not load: no local cobalt.luau found and remote fetch failed (" .. tostring(Res) .. ")")
	end
end

local Fn = loadstring(Source)
if not Fn then
	error("[Cobalt] loaded source failed to compile")
end

Fn()
