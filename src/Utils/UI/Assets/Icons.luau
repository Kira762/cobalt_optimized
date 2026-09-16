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
	local Cached = IconCache[iconName]
	if Cached ~= nil then
		return Cached or nil
	end

	if not Success then
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
