local Registry = require(script.Parent.Registry)

-- Asset resolution is deliberately offline.  The old manager downloaded every
-- image and font on startup, which made boot depend on three different hosts
-- and could stall the game before the window appeared.  Repository assets are
-- tried first; Roblox ids are a small, always-available fallback.
local AssetManager = {
	Overrides = {},
	Resolved = {},
	Sources = {},
	Errors = {},
	Preloaded = false,
}

local function GetFallback(Definition)
	if Definition.Type == "Font" then
		return Font.fromId(Definition.FallbackId)
	end

	return Definition.FallbackId
end

local function FileExists(Path: string): boolean
	if typeof(isfile) ~= "function" then
		return false
	end

	local Success, Result = pcall(isfile, Path)
	return Success and Result == true
end

local function GetLocalAsset(Definition): string?
	if Definition.Type ~= "Image" or not Definition.LocalPath then
		return nil
	end

	if typeof(getcustomasset) ~= "function" then
		return nil
	end

	local Candidates = {
		Definition.LocalPath,
		`Cobalt/Assets/{Definition.FileName}`,
	}

	for _, Path in Candidates do
		if not FileExists(Path) then
			continue
		end

		local Success, ContentId = pcall(getcustomasset, Path)
		if Success and typeof(ContentId) == "string" and ContentId ~= "" then
			return ContentId
		end
	end

	return nil
end

local function Resolve(Name: string, Definition): (any, "Local" | "Fallback", string?)
	if Definition.Type == "Image" then
		local LocalAsset = GetLocalAsset(Definition)
		if LocalAsset then
			return LocalAsset, "Local", nil
		end

		return GetFallback(Definition), "Fallback", "Local asset is unavailable"
	end

	-- Fonts intentionally use Roblox's packaged font ids.  Unlike the previous
	-- TTF-to-font JSON pipeline this does not write temporary files or perform a
	-- network request, and it is valid even when the executor has no filesystem.
	return GetFallback(Definition), "Fallback", nil
end

function AssetManager.SetOverride(Name: string, Value: any)
	assert(Registry[Name], `Unknown asset {Name}`)
	AssetManager.Overrides[Name] = Value
end

function AssetManager.ClearOverride(Name: string)
	AssetManager.Overrides[Name] = nil
end

function AssetManager.UseFallback(Name: string)
	local Definition = assert(Registry[Name], `Unknown asset {Name}`)
	AssetManager.SetOverride(Name, GetFallback(Definition))
end

function AssetManager.PreloadAsync()
	if AssetManager.Preloaded then
		return
	end

	for Name, Definition in Registry do
		local Success, Value, Source, Error = pcall(Resolve, Name, Definition)
		if Success then
			AssetManager.Resolved[Name] = Value
			AssetManager.Sources[Name] = Source
			AssetManager.Errors[Name] = Error
		else
			AssetManager.Resolved[Name] = GetFallback(Definition)
			AssetManager.Sources[Name] = "Fallback"
			AssetManager.Errors[Name] = tostring(Value)
		end
	end

	AssetManager.Preloaded = true
end

-- Kept as a compatibility hook for ExecutorSupport.  Validation is local and
-- cheap now; it never probes or downloads custom files.
function AssetManager.ValidateCustomFonts(): (boolean, string?)
	for Name, Definition in Registry do
		if Definition.Type ~= "Font" then
			continue
		end

		local Success, FontFace = pcall(GetFallback, Definition)
		if not Success or FontFace == nil then
			return false, `{Name}: packaged fallback font is unavailable`
		end
	end

	return true
end

function AssetManager.GetCustomFont(Name: string): Font
	local Definition = assert(Registry[Name], `Unknown asset {Name}`)
	assert(Definition.Type == "Font", `{Name} is not a font asset`)
	return AssetManager.Overrides[Name] or AssetManager.Resolved[Name] or GetFallback(Definition)
end

function AssetManager.GetImage(Name: string): string
	local Definition = assert(Registry[Name], `Unknown asset {Name}`)
	assert(Definition.Type == "Image", `{Name} is not an image asset`)
	return AssetManager.Overrides[Name] or AssetManager.Resolved[Name] or GetFallback(Definition)
end

function AssetManager.GetInstanceClassImages(): { [string]: string }
	local Images = {}
	for Name, Definition in Registry do
		if Definition.Type == "Image" and Definition.Group == "InstanceClass" then
			Images[Name] = AssetManager.GetImage(Name)
		end
	end

	return Images
end

return AssetManager
