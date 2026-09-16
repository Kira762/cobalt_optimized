-- Cobalt local loader.
--
-- The loader is aggressively offline. Keep cobalt.luau and the assets/
-- directory beside this file (or inside a cobalt_optimized folder) in the
-- executor's script directory. No remote source is fetched at runtime.
--
-- Supported placements (first match wins):
--   <executor_scripts>/cobalt.luau
--   <executor_scripts>/cobalt_optimized/cobalt.luau
--   (plus common executor-specific subdirectories)

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

local function TryRead(Candidates)
	if typeof(readfile) ~= "function" then
		return nil
	end

	for _, Path in Candidates do
		-- Prefer isfile() to avoid unnecessary pcall overhead
		if typeof(isfile) == "function" then
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

local function StripTrailingSep(Dir)
	local Last = Dir:sub(-1)
	if (Last == "/" or Last == "\\") and #Dir > 3 then
		return Dir:sub(1, -2)
	end
	return Dir
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
if typeof(getworkingdirectory) == "function" then
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
-- try listfiles-based discovery (last resort)
------------------------------------------------------------------------

local function TryListFilesDiscovery()
	if typeof(listfiles) ~= "function" or typeof(readfile) ~= "function" then
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

local Source = TryRead(LocalCandidates)
if not Source then
	Source = TryListFilesDiscovery()
end

if not Source then
	-- Build a helpful diagnostic message
	local Lines = {
		"[Cobalt] cobalt.luau was not found on disk.",
		"",
		"To fix this, place cobalt.luau in your executor's script folder.",
		"",
	}

	if #ExecutorBases > 0 then
		table.insert(Lines, "Detected executor script directory:")
		for _, Base in ipairs(ExecutorBases) do
			table.insert(Lines, "  -> " .. Base)
		end
	else
		table.insert(Lines, "Could not detect executor script directory.")
		table.insert(Lines, "Copy cobalt.luau into the same folder where your executor runs scripts.")
	end

	table.insert(Lines, "")
	table.insert(Lines, "Quick steps:")
	table.insert(Lines, "  1. Copy cobalt.luau from the cobalt_optimized repository")
	table.insert(Lines, "  2. Paste it into your executor's script directory")
	table.insert(Lines, "  3. Run this loader again")
	table.insert(Lines, "")
	table.insert(Lines, "Searched " .. #LocalCandidates .. " paths without success.")

	error(table.concat(Lines, "\n"))
end

local Fn, CompileError = loadstring(Source, "@cobalt.luau")
if not Fn then
	error("[Cobalt] local source failed to compile: " .. tostring(CompileError))
end

Fn()
