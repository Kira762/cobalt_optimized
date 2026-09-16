-- Cobalt local loader.
--
-- The loader is intentionally offline. Keep cobalt.luau and the assets/
-- directory beside this file (or inside a cobalt_optimized folder) in the
-- executor's script directory. No remote source is fetched at runtime.

local function TryRead(Candidates)
	if typeof(readfile) ~= "function" then
		return nil
	end

	for _, Path in Candidates do
		local Success, Result = pcall(readfile, Path)
		if Success and type(Result) == "string" and Result ~= "" then
			print("[Cobalt] source: local file " .. Path)
			return Result
		end
	end

	return nil
end

local LocalCandidates = {
	"cobalt.luau",
	"cobalt_optimized/cobalt.luau",
}

if typeof(getworkingdirectory) == "function" then
	local Success, Directory = pcall(getworkingdirectory)
	if Success and type(Directory) == "string" and Directory ~= "" then
		local Last = Directory:sub(-1)
		if (Last == "/" or Last == "\\") and #Directory > 3 then
			Directory = Directory:sub(1, -2)
		end
		table.insert(LocalCandidates, Directory .. "/cobalt.luau")
		table.insert(LocalCandidates, Directory .. "/cobalt_optimized/cobalt.luau")
	end
end

local Source = TryRead(LocalCandidates)
if not Source then
	error("[Cobalt] no local cobalt.luau was found; copy the repository into the executor script directory")
end

local Fn, CompileError = loadstring(Source, "cobalt.luau")
if not Fn then
	error("[Cobalt] local source failed to compile: " .. tostring(CompileError))
end

Fn()
