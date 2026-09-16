local Icons = {}

type Icon = {
	Url: string,
	Id: number,
	IconName: string,
	ImageRectOffset: Vector2,
	ImageRectSize: Vector2,
}

local Success, IconsModule = pcall(function()
	local IconFetchSuccess, IconModuleSource = pcall(request, {
		Url = "https://raw.githubusercontent.com/mstudio45/lucide-roblox-direct/refs/heads/main/source.lua",
		Method = "GET",
	})

	assert(
		IconFetchSuccess and IconModuleSource.Success
			or IconModuleSource.StatusCode >= 200 and IconModuleSource.StatusCode < 300,
		"Failed to fetch lucide icons direct module source"
	)
	return (loadstring(IconModuleSource.Body) :: () -> { Icons: { string }, GetAsset: (Name: string) -> Icon? })()
end)

--[[
	Icon lookups are memoised.

	SetIcon runs for every icon in the interface (every call row, every menu
	option, every toast) and each miss used to pay for a pcall plus a lookup
	inside the loaded icon module.  Negative results are cached too, so an icon
	that does not exist is not searched for again.
]]
local IconCache = {}

function Icons.GetIcon(iconName: string): Icon?
	-- Context-menu options and dropdown entries do not always carry an icon
	-- (e.g. array-style dropdown values such as the interface-scale list), so
	-- SetIcon is routinely called with nil. A nil *read* is harmless in Luau,
	-- but once the remote module has loaded (request available) the miss
	-- branch below would *write* IconCache[nil] and abort the whole load with
	-- "table index is nil". Treat a missing name as a missing icon instead.
	if iconName == nil then
		return nil
	end

	local Cached = IconCache[iconName]
	if Cached ~= nil then
		return Cached or nil
	end

	-- A 200 response with an empty or unexpected body still sets Success (e.g.
	-- loadstring("")() returns nil), leaving IconsModule unusable. Evaluating
	-- IconsModule.GetAsset would then throw *outside* the pcall below, so bail
	-- out here: a missing icon must never abort the interface load.
	if not Success or type(IconsModule) ~= "table" or type(IconsModule.GetAsset) ~= "function" then
		return nil
	end

	local Ok, Icon = pcall(IconsModule.GetAsset, iconName)
	if not Ok or not Icon then
		IconCache[iconName] = false
		return nil
	end

	IconCache[iconName] = Icon
	return Icon
end

function Icons.SetIcon(imageInstance: ImageLabel, iconName: string)
	local Icon: Icon? = Icons.GetIcon(iconName)
	if not Icon then
		return
	end

	-- Skip redundant property writes: they still dirty the instance.
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
