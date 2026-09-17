-- Cobalt bootstrap loader.
--
-- Preferred usage:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/Kira762/cobalt_optimized/main/loader.luau"))()
--
-- Load order:
--   1. the latest generated bundle from GitHub (and refresh the local cache);
--   2. a local/cached cobalt.luau when the download is unavailable.
--
-- Remote-first matters: the loader caches the bundle to cobalt.luau, and an
-- older local-first order pinned users to whatever build they downloaded
-- first, so already-fixed errors (e.g. "[Cobalt].cobalt:95: attempt to call a
-- nil value") kept reappearing from the stale cache.  Set
-- `getgenv().CobaltPreferLocal = true` before running the loader to keep using
-- a deliberately local build.

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

local COBALT_BUNDLE_URL = "https://raw.githubusercontent.com/Kira762/cobalt_optimized/main/cobalt.luau"

local function SafeTypeof(Value)
	if typeof then
		return typeof(Value)
	end
	return type(Value)
end

local function TryRead(Candidates)
	if SafeTypeof(readfile) ~= "function" then
		return nil
	end

	for _, Path in Candidates do
		-- Prefer isfile() to avoid unnecessary pcall overhead
		if SafeTypeof(isfile) == "function" then
			local Ok, Exists = pcall(isfile, Path)
			if not (Ok and Exists) then
				continue
			end
		end

		local Ok, Content = pcall(readfile, Path)
		if Ok and type(Content) == "string" and #Content > 0 then
			print("[Cobalt] source: local file " .. Path)
			return Content
		end
	end

	return nil
end

local function TryWriteCache(Source)
	if SafeTypeof(writefile) ~= "function" then
		return
	end

	-- Skip the write when the cache already holds this exact bundle.
	if SafeTypeof(readfile) == "function" then
		local Ok, Existing = pcall(readfile, "cobalt.luau")
		if Ok and Existing == Source then
			return
		end
	end

	pcall(function()
		writefile("cobalt.luau", Source)
	end)
end

local function StripTrailingSep(Dir)
	local Last = Dir:sub(-1)
	if (Last == "/" or Last == "\\") and #Dir > 3 then
		return Dir:sub(1, -2)
	end
	return Dir
end

local function LooksLikeCobaltBundle(Source)
	return type(Source) == "string"
		and #Source > 1000
		and Source:find("Cobalt", 1, true) ~= nil
		and Source:find("ClosureBindings", 1, true) ~= nil
end

local function TryHttpGet(Url)
	if game ~= nil then
		if SafeTypeof(game.HttpGet) == "function" then
			local Ok, Content = pcall(function()
				return game:HttpGet(Url)
			end)
			if Ok and LooksLikeCobaltBundle(Content) then
				return Content
			end
		end

		if SafeTypeof(game.HttpGetAsync) == "function" then
			local Ok, Content = pcall(function()
				return game:HttpGetAsync(Url)
			end)
			if Ok and LooksLikeCobaltBundle(Content) then
				return Content
			end
		end
	end

	return nil
end

local function TryRemoteFetch()
	local Source = TryHttpGet(COBALT_BUNDLE_URL)
	if Source then
		print("[Cobalt] source: remote bundle " .. COBALT_BUNDLE_URL)
		TryWriteCache(Source)
		return Source
	end

	return nil
end

------------------------------------------------------------------------
-- build candidate list
------------------------------------------------------------------------

local LocalCandidates = {
	-- Direct placements (most common)
	"cobalt.luau",
	"cobalt_optimized/cobalt.luau",
	-- Common executor subdirectory conventions
	"scripts/cobalt.luau",
	"scripts/cobalt_optimized/cobalt.luau",
	"workspace/cobalt.luau",
	"workspace/cobalt_optimized/cobalt.luau",
}

-- Collect executor-specific base directories
local ExecutorBases = {}

-- getworkingdirectory (Synapse, Script-Ware, Fluxus, etc.)
if SafeTypeof(getworkingdirectory) == "function" then
	local Ok, Dir = pcall(getworkingdirectory)
	if Ok and type(Dir) == "string" and #Dir > 0 then
		table.insert(ExecutorBases, StripTrailingSep(Dir))
	end
end

-- Append executor-base-prefixed candidates
for _, Base in ipairs(ExecutorBases) do
	for _, Suffix in ipairs({
		"/cobalt.luau",
		"/cobalt_optimized/cobalt.luau",
		"\\cobalt.luau",
		"\\cobalt_optimized\\cobalt.luau",
	}) do
		table.insert(LocalCandidates, Base .. Suffix)
	end
end

------------------------------------------------------------------------
-- try listfiles-based discovery (last resort before network)
------------------------------------------------------------------------

local function TryListFilesDiscovery()
	if SafeTypeof(listfiles) ~= "function" or SafeTypeof(readfile) ~= "function" then
		return nil
	end

	local SearchDirs = { "" }
	for _, Base in ipairs(ExecutorBases) do
		table.insert(SearchDirs, Base)
	end

	for _, Dir in ipairs(SearchDirs) do
		local Ok, Files = pcall(listfiles, Dir)
		if Ok and type(Files) == "table" then
			for _, FilePath in ipairs(Files) do
				if type(FilePath) == "string" and FilePath:lower():match("cobalt%.luau$") then
					local ReadOk, Content = pcall(readfile, FilePath)
					if ReadOk and type(Content) == "string" and #Content > 0 then
						print("[Cobalt] source: discovered " .. FilePath)
						return Content
					end
				end
			end
		end
	end

	return nil
end

------------------------------------------------------------------------
-- load
------------------------------------------------------------------------

local PreferLocal = false
if SafeTypeof(getgenv) == "function" then
	local Ok, Env = pcall(getgenv)
	PreferLocal = Ok and type(Env) == "table" and Env.CobaltPreferLocal == true
end

local Source
if PreferLocal then
	Source = TryRead(LocalCandidates) or TryListFilesDiscovery() or TryRemoteFetch()
else
	Source = TryRemoteFetch()
	if not Source then
		Source = TryRead(LocalCandidates) or TryListFilesDiscovery()
		if Source then
			warn("[Cobalt] remote bundle unavailable; using a local copy that may be out of date")
		end
	end
end

if not Source then
	-- Build a helpful diagnostic message
	local Lines = {
		"[Cobalt] cobalt.luau could not be loaded.",
		"",
		"The loader tried to download the bundle, then searched local files:",
		"  " .. COBALT_BUNDLE_URL,
		"",
		"If your executor blocks game:HttpGet, place cobalt.luau in your executor's script folder as a fallback.",
		"",
	}

	if #ExecutorBases > 0 then
		table.insert(Lines, "Detected executor script directory:")
		for _, Base in ipairs(ExecutorBases) do
			table.insert(Lines, "  -> " .. Base)
		end
	else
		table.insert(Lines, "Could not detect executor script directory.")
	end

	table.insert(Lines, "")
	table.insert(Lines, "Searched " .. #LocalCandidates .. " local paths without success.")

	error(table.concat(Lines, "\n"))
end

local Fn, CompileError = loadstring(Source, "@cobalt.luau")
if not Fn then
	error("[Cobalt] source failed to compile: " .. tostring(CompileError))
end

Fn()
