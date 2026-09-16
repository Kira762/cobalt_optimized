-- Small, repository-local icon atlas.
--
-- Cobalt previously evaluated a remote Luau module which downloaded a sprite
-- sheet during startup.  Icons are decorative, so a missing local atlas must
-- never prevent the window from loading.

local Icons = {}

type Icon = {
	Url: string,
	ImageRectOffset: Vector2,
	ImageRectSize: Vector2,
}

local CellSize = 32
local Columns = 8
local AtlasPath = "assets/ui-icons.png"
local AtlasUrl: string? = nil
local AtlasResolved = false

-- Only names used by the built-in UI are included.  Unknown/plugin names are
-- treated as optional and simply render without an icon.
local IconCells: { [string]: number } = {
	["align-vertical-distribute-center"] = 1,
	["ban"] = 2,
	["blocks"] = 3,
	["bug"] = 4,
	["check"] = 5,
	["chevron-down"] = 6,
	["circle-alert"] = 7,
	["circle-fading-arrow-up"] = 8,
	["code"] = 9,
	["copy"] = 10,
	["ellipsis"] = 11,
	["eye"] = 12,
	["file"] = 13,
	["file-clock"] = 14,
	["file-search"] = 15,
	["file-text"] = 16,
	["forward"] = 17,
	["gamepad-2"] = 18,
	["globe"] = 19,
	["list-filter"] = 20,
	["lock"] = 21,
	["lock-open"] = 22,
	["minus"] = 23,
	["network"] = 24,
	["package-search"] = 25,
	["parentheses"] = 26,
	["pencil"] = 27,
	["play"] = 28,
	["plus"] = 29,
	["scroll-text"] = 30,
	["search"] = 31,
	["settings"] = 32,
	["shield-alert"] = 33,
	["terminal"] = 34,
	["trash"] = 35,
	["triangle-alert"] = 36,
	["x"] = 37,
}

local function ResolveAtlas(): string?
	if AtlasResolved then
		return AtlasUrl
	end

	AtlasResolved = true
	if typeof(isfile) ~= "function" or typeof(getcustomasset) ~= "function" then
		return nil
	end

	for _, Path in { AtlasPath, "Cobalt/Assets/ui-icons.png" } do
		local Success, Exists = pcall(isfile, Path)
		if not (Success and Exists) then
			continue
		end

		local AssetSuccess, Result = pcall(getcustomasset, Path)
		if AssetSuccess and typeof(Result) == "string" and Result ~= "" then
			AtlasUrl = Result
			return Result
		end
	end

	return nil
end

local IconCache: { [string]: Icon | false } = {}

function Icons.GetIcon(IconName: string?): Icon?
	if not IconName then
		return nil
	end

	local Cached = IconCache[IconName]
	if Cached ~= nil then
		return Cached or nil
	end

	local Cell = IconCells[IconName]
	local Url = ResolveAtlas()
	if not Cell or not Url then
		IconCache[IconName] = false
		return nil
	end

	local ZeroBased = Cell - 1
	local Icon: Icon = {
		Url = Url,
		ImageRectOffset = Vector2.new((ZeroBased % Columns) * CellSize, math.floor(ZeroBased / Columns) * CellSize),
		ImageRectSize = Vector2.new(CellSize, CellSize),
	}
	IconCache[IconName] = Icon
	return Icon
end

function Icons.SetIcon(imageInstance: ImageLabel | ImageButton, IconName: string?)
	local Icon = Icons.GetIcon(IconName)
	if not Icon then
		return
	end

	if imageInstance.Image ~= Icon.Url then
		imageInstance.Image = Icon.Url
	end
	if imageInstance.ImageRectOffset ~= Icon.ImageRectOffset then
		imageInstance.ImageRectOffset = Icon.ImageRectOffset
	end
	if imageInstance.ImageRectSize ~= Icon.ImageRectSize then
		imageInstance.ImageRectSize = Icon.ImageRectSize
	end
end

return Icons
