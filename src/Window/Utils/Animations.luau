--[[
	Animations

	Shared animation layer for the whole interface.

	Everything here is intentionally cheap: tweens are created through a single
	de-duplicating entry point (`Animations.Play`) so hovering the same button
	500 times a second never stacks 500 tweens, and every helper degrades to
	"set the final value instantly" when animations are disabled in Settings
	(Appearance -> Interface Animations) or when there is nothing to animate.

	The original public API (TweenInfo, FadeIn, FadeOut, AddFadeExclusion,
	AddFadeExclusions, SetFadeExpectation, Exclusions, Expectations) is
	unchanged - existing callers keep working exactly as before.
]]

local DeviceProfile = require("@src/Utils/DeviceProfile")

local Animations = {
	TweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Exponential),
	FastTweenInfo = TweenInfo.new(0.14, Enum.EasingStyle.Quad),
	MediumTweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Exponential),
	SlowTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Exponential),

	-- How many objects a single group fade may touch.  Big groups (a full log
	-- page, a large modal) are clamped so a fade can never turn into hundreds
	-- of simultaneous tweens on a phone.  Tier-aware: 64/32/8.
	MaxGroupFadeObjects = DeviceProfile.MaxAnimations or 64,

	Exclusions = {},
	Expectations = { In = {}, Out = {} },
}

-- object -> { [propertyName] = Tween }
local ActiveTweens = setmetatable({}, { __mode = "k" })
-- object -> UIScale used by Animations.Scale / Animations.Pop
local ScaleObjects = setmetatable({}, { __mode = "k" })
-- object -> { In = properties, Out = properties } (avoids rebuilding tables)
local PropertyTableCache = setmetatable({}, { __mode = "k" })
-- settings that need a SaveManager read before the Settings UI exists
local SettingFallbackCache = {}

local function GetBooleanSetting(Key: string, Default: boolean): boolean
	local Controls = wax.shared.Settings
	local Control = Controls and Controls[Key]
	if Control then
		local Value = Control.Value
		if Value ~= nil then
			SettingFallbackCache[Key] = Value
			return Value
		end
	end

	local Cached = SettingFallbackCache[Key]
	if Cached ~= nil then
		return Cached
	end

	local SaveManager = wax.shared.SaveManager
	local Success, Value = pcall(function()
		return SaveManager:GetState(Key, Default)
	end)

	Cached = if Success and Value ~= nil then Value else Default
	SettingFallbackCache[Key] = Cached
	return Cached
end

local function GetTransparencyProperty(object)
	if table.find(Animations.Exclusions, object) then
		return nil
	end

	if object:IsA("TextButton") or object:IsA("TextLabel") or object:IsA("TextBox") then
		return { "TextTransparency" }
	elseif object:IsA("CanvasGroup") then
		return { "GroupTransparency" }
	elseif object:IsA("Frame") then
		return { "BackgroundTransparency" }
	elseif object:IsA("ScrollingFrame") then
		return { "ScrollBarImageTransparency" }
	elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
		return { "ImageTransparency", "BackgroundTransparency" }
	elseif object:IsA("UIStroke") then
		return { "Transparency" }
	end

	return nil
end

local function BuildPropertyTable(properties, type, object)
	if Animations.Expectations[type][object] then
		return Animations.Expectations[type][object]
	end

	local Cached = PropertyTableCache[object]
	local CachedForType = Cached and Cached[type]
	if CachedForType and CachedForType.Properties == properties then
		return CachedForType.Table
	end

	local propTable = {}
	for _, prop in properties do
		propTable[prop] = type == "In" and 0 or 1
	end

	if not Cached then
		Cached = {}
		PropertyTableCache[object] = Cached
	end

	Cached[type] = {
		Properties = properties,
		Table = propTable,
	}

	return propTable
end

-------------------------------------------------------------------------------
-- Core tween helpers
-------------------------------------------------------------------------------

local function GetTrackedTweens(object)
	local Tracked = ActiveTweens[object]
	if not Tracked then
		Tracked = {}
		ActiveTweens[object] = Tracked
	end

	return Tracked
end

--[[
	Cancels the tweens this module tracks for the given properties.
]]
local function CancelTracked(object, Properties)
	local Tracked = ActiveTweens[object]
	if not Tracked then
		return
	end

	for Property in Properties do
		local Existing = Tracked[Property]
		if Existing then
			pcall(Existing.Cancel, Existing)
			Tracked[Property] = nil
		end
	end
end

--[[
	Creates and plays a tween, cancelling any previous tween this module started
	for the same properties on the same object.

	Returns the Tween, or nil when nothing had to move (or animations are
	disabled - the properties are then applied instantly, so the end state is
	identical either way).

	The hot paths matter here: this is called from hover/press handlers, so it
	avoids allocating anything when a value is already where it should be.
]]
function Animations.Play(object, Properties, TweenInfo_): Tween?
	if not object then
		return nil
	end

	local Tracked = ActiveTweens[object]
	local NeedsCancel = false
	local HasWork = false

	for Property, Value in Properties do
		if not HasWork and object[Property] ~= Value then
			HasWork = true
		end

		if Tracked and Tracked[Property] then
			NeedsCancel = true
		end
	end

	if not (HasWork and Animations.IsEnabled()) then
		if NeedsCancel then
			CancelTracked(object, Properties)
		end

		if HasWork then
			for Property, Value in Properties do
				object[Property] = Value
			end
		end

		return nil
	end

	if NeedsCancel then
		CancelTracked(object, Properties)
	end

	local Tween = wax.shared.TweenService:Create(object, TweenInfo_ or Animations.TweenInfo, Properties)
	if not Tracked then
		Tracked = GetTrackedTweens(object)
	end

	for Property in Properties do
		Tracked[Property] = Tween
	end

	Tween:Play()
	return Tween
end

--[[
	Cancels every tween this module started on `object`.

	`ResetScale` also snaps an animation-owned UIScale back to 1 - used when a
	pooled element is recycled while a press/pop animation was still running.
]]
function Animations.Cancel(object, ResetScale: boolean?)
	local Tracked = ActiveTweens[object]
	if Tracked then
		for Property, Tween in Tracked do
			pcall(Tween.Cancel, Tween)
			Tracked[Property] = nil
		end
	end

	if ResetScale then
		local Scale = ScaleObjects[object]
		if Scale and Scale.Parent == object then
			Scale.Scale = 1
		end
	end
end

function Animations.IsEnabled(): boolean
	-- Instant transitions are the safe default for a remote-spy UI: they avoid
	-- creating a tween for every hover and every newly visible row.
	return GetBooleanSetting("AnimationsEnabled", false) == true
end

function Animations.SetEnabled(Enabled: boolean)
	SettingFallbackCache["AnimationsEnabled"] = Enabled == true
end

--[[
	Returns (and caches) the UIScale owned by this module for `object`.

	UIScale is only used on objects that are *not* laid out by a UIListLayout,
	so scaling never triggers a reflow.
]]
local function GetScaleObject(object)
	local Scale = ScaleObjects[object]
	if Scale and Scale.Parent == object then
		return Scale
	end

	Scale = object:FindFirstChild("CobaltAnimationScale")
	if not Scale then
		Scale = Instance.new("UIScale")
		Scale.Name = "CobaltAnimationScale"
		Scale.Parent = object
	end

	ScaleObjects[object] = Scale
	return Scale
end

--[[
	Pops an element into view (scale + optional fade).

	Options: { From = 0.96, To = 1, Duration = 0.2, Delay = 0, Fade = false,
	           TweenInfo = TweenInfo? }
]]
function Animations.Pop(object, Options)
	if not object then
		return
	end

	Options = Options or {}
	local From = Options.From or 0.96
	local To = Options.To or 1
	local Duration = Options.Duration or 0.2
	local TweenInfo_ = Options.TweenInfo or TweenInfo.new(Duration, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	local Delay = Options.Delay or 0

	local Scale = GetScaleObject(object)
	Scale.Scale = From

	local function Start()
		Animations.Play(Scale, { Scale = To }, TweenInfo_)

		if Options.Fade then
			Animations.FadeInPlace(object, { Duration = Duration, SkipSelf = true })
		end
	end

	if Delay > 0 and Animations.IsEnabled() then
		task.delay(Delay, Start)
	else
		Start()
	end
end

--[[
	Convenience wrapper: animate a single property to a target value.
]]
function Animations.Tween(object, TweenInfo_, Properties)
	return Animations.Play(object, Properties, TweenInfo_)
end

--[[
	Binds enter/leave feedback (hover on desktop, highlight on touch layouts)
	with de-duplication, so repeated enters never pile tweens up.
]]
function Animations.BindHover(object, IdleProperties, HoverProperties, TweenInfo_)
	if not object then
		return
	end

	object.MouseEnter:Connect(function()
		Animations.Play(object, HoverProperties, TweenInfo_ or Animations.MediumTweenInfo)
	end)

	object.MouseLeave:Connect(function()
		Animations.Play(object, IdleProperties, TweenInfo_ or Animations.MediumTweenInfo)
	end)
end

--[[
	Binds press feedback.  `PressProperties` are applied while held, then the
	element returns to whatever `ReleaseProperties` describes.

	Options: { Press = table?, Release = table?, TweenInfo = TweenInfo? }
]]
function Animations.BindPress(object, Options)
	if not object then
		return
	end

	Options = Options or {}
	local Press = Options.Press
	if not Press then
		return
	end

	local Release = Options.Release
	local Original = nil

	local function IsPressInput(Input: InputObject): boolean
		return (
			Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch
		)
	end

	object.InputBegan:Connect(function(Input: InputObject)
		if Input.UserInputState ~= Enum.UserInputState.Begin or not IsPressInput(Input) then
			return
		end

		if not Original then
			Original = {}
			for Property in Press do
				Original[Property] = object[Property]
			end
		end

		Animations.Play(object, Press, Options.TweenInfo or Animations.FastTweenInfo)
	end)

	object.InputEnded:Connect(function(Input: InputObject)
		if not IsPressInput(Input) then
			return
		end

		if Input.UserInputState ~= Enum.UserInputState.End and Input.UserInputState ~= Enum.UserInputState.Cancel then
			return
		end

		if Release then
			Animations.Play(object, Release, Options.TweenInfo or Animations.MediumTweenInfo)
		elseif Original then
			Animations.Play(object, Original, Options.TweenInfo or Animations.MediumTweenInfo)
		end
	end)
end

-------------------------------------------------------------------------------
-- Fades
-------------------------------------------------------------------------------

local function PlayFade(object, tweenInfo, type)
	local properties = GetTransparencyProperty(object)
	if not properties then
		return
	end

	Animations.Play(object, BuildPropertyTable(properties, type, object), tweenInfo)
end

function Animations.FadeOut(object, time)
	local tweenInfo = time and TweenInfo.new(time, Enum.EasingStyle.Exponential) or Animations.TweenInfo
	PlayFade(object, tweenInfo, "Out")

	if object:IsA("CanvasGroup") then
		return
	end

	for _, child in object:GetDescendants() do
		PlayFade(child, tweenInfo, "Out")
	end
end

function Animations.FadeIn(object, time)
	local tweenInfo = time and TweenInfo.new(time, Enum.EasingStyle.Exponential) or Animations.TweenInfo
	PlayFade(object, tweenInfo, "In")

	if object:IsA("CanvasGroup") then
		return
	end

	for _, child in object:GetDescendants() do
		PlayFade(child, tweenInfo, "In")
	end
end

--[[
	Fades a group of elements in *from where they already are*.

	Unlike FadeIn (which forces every transparency to 0), this captures each
	element's current transparency as the target, hides the group and tween it
	back.  Elements that are intentionally semi-transparent (dimmed labels,
	invisible strokes) therefore keep their exact final look.

	Options: { Duration = 0.18, Delay = 0, MaxObjects = Animations.MaxGroupFadeObjects,
	           SkipSelf = false, Hidden = 1 }
]]
function Animations.FadeInPlace(object, Options)
	if not object then
		return
	end

	Options = Options or {}
	local Duration = Options.Duration or 0.18
	local Delay = Options.Delay or 0
	local Hidden = Options.Hidden or 1
	local MaxObjects = Options.MaxObjects or Animations.MaxGroupFadeObjects

	if not Animations.IsEnabled() then
		return
	end

	local Targets = {}
	local Count = 0

	local function Collect(Target)
		if Count >= MaxObjects then
			return
		end

		local Properties = GetTransparencyProperty(Target)
		if not Properties then
			return
		end

		Targets[Count + 1] = {
			Target = Target,
			Properties = Properties,
		}
		Count += 1
	end

	if not Options.SkipSelf then
		Collect(object)
	end

	if not object:IsA("CanvasGroup") then
		for _, child in object:GetDescendants() do
			if Count >= MaxObjects then
				break
			end

			Collect(child)
		end
	end

	if Count == 0 then
		return
	end

	-- Capture the real targets, then hide.  Anything already invisible is left
	-- alone so we never spawn a tween that cannot be seen.
	local Active = {}
	local ActiveCount = 0
	for _, Entry in Targets do
		local Target = Entry.Target
		local WasHidden = true
		local To = {}

		for _, Property in Entry.Properties do
			local Current = Target[Property]
			To[Property] = Current

			if Current < Hidden then
				WasHidden = false
			end

			Target[Property] = Hidden
		end

		if not WasHidden then
			ActiveCount += 1
			Active[ActiveCount] = {
				Target = Target,
				To = To,
			}
		end
	end

	if ActiveCount == 0 then
		return
	end

	local TweenInfo_ = TweenInfo.new(Duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function Reveal()
		for _, Entry in Active do
			if Entry.Target.Parent == nil and Entry.Target ~= object then
				continue
			end

			Animations.Play(Entry.Target, Entry.To, TweenInfo_)
		end
	end

	if Delay > 0 then
		task.delay(Delay, Reveal)
	else
		Reveal()
	end
end

-------------------------------------------------------------------------------
-- Fade exclusions / expectations
-------------------------------------------------------------------------------

function Animations.AddFadeExclusion(object)
	local prop = GetTransparencyProperty(object)
	if not prop then
		return
	end

	table.insert(Animations.Exclusions, object)
end

function Animations.AddFadeExclusions(objects)
	for _, object in objects do
		local prop = GetTransparencyProperty(object)
		if not prop then
			continue
		end

		table.insert(Animations.Exclusions, object)
	end
end

function Animations.SetFadeExpectation(type: "In" | "Out", object: GuiBase2d, properties: { [string]: any })
	if not Animations.Expectations[type] then
		return
	end

	Animations.Expectations[type][object] = properties

	local Cached = PropertyTableCache[object]
	if Cached then
		Cached[type] = nil
	end
end

function Animations.RemoveFadeExclusion(object)
	local Index = table.find(Animations.Exclusions, object)
	if Index then
		table.remove(Animations.Exclusions, Index)
	end
end

return Animations
