

local Sonner = {
	Queue = {},
	TweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Exponential),
	Wrapper = nil,
	PendingQueue = {},
	PendingHead = 1,
	PendingTail = 0,
	Processing = false,

	-- Toasts are cheap to queue but expensive to render, so the backlog is
	-- bounded: a game spamming events can never grow this without limit.
	MaxPendingToasts = 32,
	MaxVisibleToasts = 4,
}

local Icons = require("@src/Utils/UI/Assets/Icons")
local Interface = require("@src/Utils/UI/Interface")
local Animations = require("@src/Window/Utils/Animations")

local NOTIFICATION_WIDTH = 250
local NOTIFICATION_MIN_HEIGHT = 50
local NOTIFICATION_VERTICAL_PADDING = 20

--[[
	Spinning icons.

	`Sonner.promise` used to spawn a thread per promise that waited on
	RenderStepped forever, and re-resolved the icon with FindFirstChild on every
	frame.  All spinners now share one connection, which is only alive while at
	least one promise is running.
]]
local SpinningIcons = setmetatable({}, { __mode = "k" })
local SpinnerConnection = nil

local function StopSpinnerDriver()
	if SpinnerConnection then
		SpinnerConnection:Disconnect()
		SpinnerConnection = nil
	end
end

local function DriveSpinners()
	local AnyAlive = false

	for Icon in SpinningIcons do
		if Icon.Parent == nil then
			SpinningIcons[Icon] = nil
			continue
		end

		AnyAlive = true
		Icon.Rotation = (Icon.Rotation + 1) % 360
	end

	if not AnyAlive then
		StopSpinnerDriver()
	end
end

local function StartSpinner(Icon)
	if not Icon then
		return nil
	end

	SpinningIcons[Icon] = true

	if not SpinnerConnection then
		SpinnerConnection = wax.shared.RunService.RenderStepped:Connect(DriveSpinners)
	end

	return Icon
end

local function StopSpinner(Icon)
	if not Icon then
		return
	end

	SpinningIcons[Icon] = nil
	if next(SpinningIcons) == nil then
		StopSpinnerDriver()
	end
end

local function GetHiddenPosition(Notification: GuiObject): UDim2
	return UDim2.new(0.5, 0, 1, math.max(NOTIFICATION_MIN_HEIGHT, Notification.AbsoluteSize.Y + 2))
end

local function InternalCreateNotificationObject(zindex, image, text)
	local NotificationTemplate = Interface.New("CanvasGroup", {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(NOTIFICATION_WIDTH, NOTIFICATION_MIN_HEIGHT),
		Position = UDim2.new(0.5, 0, 1, 500),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		ZIndex = zindex,

		["UICorner"] = {
			CornerRadius = UDim.new(0, 4),
		},

		["UIStroke"] = {
			Color = Color3.fromRGB(39, 42, 42),
		},

		["UIScale"] = {},

		["UIPadding"] = {
			PaddingLeft = UDim.new(0, 0),
			PaddingRight = UDim.new(0, 0),
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
		},
	})

	local ImageLabel = Interface.New("ImageLabel", {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.new(0, 20, 0, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 20, 0.5, 0),
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		ZIndex = zindex + 1,
		Parent = NotificationTemplate,
	})

	Animations.SetFadeExpectation("In", ImageLabel, {
		BackgroundTransparency = 1,
		ImageTransparency = 0,
	})

	if image then
		if image:find("rbxasset") then
			ImageLabel.Image = image
		else
			Icons.SetIcon(ImageLabel, image)
		end
	else
		ImageLabel.Visible = false
	end

	local Frame = Interface.New("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		Size = UDim2.new(1, -50, 1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = zindex + 1,
		Parent = NotificationTemplate,

		["UIListLayout"] = {
			VerticalAlignment = Enum.VerticalAlignment.Center,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
		},
	})

	local TextLabel = Interface.New("TextLabel", {
		BorderSizePixel = 0,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		Text = text,
		ZIndex = zindex + 1,
		Parent = Frame,
		TextWrapped = true,
	})

	local function UpdateHeight()
		NotificationTemplate.Size = UDim2.fromOffset(
			NOTIFICATION_WIDTH,
			math.max(NOTIFICATION_MIN_HEIGHT, math.ceil(TextLabel.TextBounds.Y) + NOTIFICATION_VERTICAL_PADDING)
		)
	end

	TextLabel:GetPropertyChangedSignal("TextBounds"):Connect(UpdateHeight)
	UpdateHeight()

	return NotificationTemplate
end

local function InternalToast(image, text, internalTime, removeCallback)
	assert(Sonner.Wrapper, "Sonner has not been initialized")
	assert(typeof(image) == "string" or image == nil, "Image must be a string or nil")
	assert(typeof(text) == "string", "Text is required!")
	assert(typeof(internalTime) == "number" or internalTime == nil, "Time must be a number or nil")

	local time = internalTime or 4.5

	local Notif = InternalCreateNotificationObject(500, image, text)

	Notif.Parent = Sonner.Wrapper
	wax.shared.RunService.Heartbeat:Wait()
	Notif.Position = GetHiddenPosition(Notif)

	table.insert(Sonner.Queue, Notif)

	local ScaleMultiplier = 0.9
	local RemovalQueue = {}

	for index, object in Sonner.Queue do
		if object == Notif then
			continue
		end

		object.ZIndex = 500 - (#Sonner.Queue - index)

		Animations.Play(object.UIScale, {
			Scale = object.UIScale.Scale * ScaleMultiplier,
		}, Sonner.TweenInfo)

		Animations.Play(object, {
			Position = object.Position - UDim2.fromOffset(0, object.AbsoluteSize.Y * 0.35),
		}, Sonner.TweenInfo)

		if ((#Sonner.Queue - index) + 1) >= Sonner.MaxVisibleToasts then
			Animations.FadeOut(object)
			task.delay(0.5, function()
				object:Destroy()
			end)
			table.insert(RemovalQueue, object)
		end
	end

	for _, obj in RemovalQueue do
		table.remove(Sonner.Queue, table.find(Sonner.Queue, obj))
	end

	Animations.Play(Notif, {
		Position = UDim2.new(0.5, 0, 1, -20),
	}, Sonner.TweenInfo)
	Animations.FadeIn(Notif)

	if removeCallback then
		task.spawn(removeCallback, Notif, time)
	else
		task.delay(time, function()
			if not table.find(Sonner.Queue, Notif) then
				return
			end
			table.remove(Sonner.Queue, table.find(Sonner.Queue, Notif))

			Animations.FadeOut(Notif, 0.35)
			Animations.Play(Notif, {
				Position = GetHiddenPosition(Notif),
			}, Sonner.TweenInfo)
			task.wait(0.5)
			Notif:Destroy()
		end)
	end
end

local function ProcessQueue()
	if Sonner.Processing then
		return
	end
	if not Sonner.Wrapper then
		return
	end
	Sonner.Processing = true

	while Sonner.PendingHead <= Sonner.PendingTail do
		local Request = Sonner.PendingQueue[Sonner.PendingHead]
		Sonner.PendingQueue[Sonner.PendingHead] = nil
		Sonner.PendingHead += 1

		if Request then
			InternalToast(Request.image, Request.text, Request.internalTime, Request.removeCallback)
			task.wait(0.5)
		end
	end

	table.clear(Sonner.PendingQueue)
	Sonner.PendingHead = 1
	Sonner.PendingTail = 0
	Sonner.Processing = false
end

local function toast(image, text, internalTime, removeCallback)
	local Pending = Sonner.PendingQueue
	local Queued = Sonner.PendingTail - Sonner.PendingHead + 1

	if Queued >= Sonner.MaxPendingToasts then
		-- Backlog is full: drop the request rather than growing forever.
		return
	end

	Sonner.PendingTail += 1
	Pending[Sonner.PendingTail] = {
		image = image,
		text = text,
		internalTime = internalTime,
		removeCallback = removeCallback,
	}

	task.spawn(ProcessQueue)
end

function Sonner.info(text, internalTime)
	toast("info", text, internalTime)
end

function Sonner.success(text, internalTime)
	toast("circle-check", text, internalTime)
end

function Sonner.warning(text, internalTime)
	toast("triangle-alert", text, internalTime)
end

function Sonner.error(text, internalTime)
	toast("circle-alert", text, internalTime)
end

function Sonner.toast(text, internalTime)
	toast(nil, text, internalTime)
end

function Sonner.promise(func, options)
	local loadingText = options.loadingText or "Loading..."
	local successText = options.successText or "Success!"
	local errorText = options.errorText or "Error!"
	local internalTime = options.time or 4.5

	toast("loader-circle", loadingText, internalTime, function(notif, time)
		local success, resultOrError = nil, nil
		local icon = notif:FindFirstChild("ImageLabel")

		-- One shared spinner driver for every pending promise (see SpinningIcons).
		StartSpinner(icon)

		success, resultOrError = pcall(func, function(text)
			notif.Frame.TextLabel.Text = text
		end)

		StopSpinner(icon)

		task.spawn(function()
			setthreadidentity(8)

			
			

			Animations.FadeOut(notif.ImageLabel, 0.15)
			Animations.Play(notif.ImageLabel, {
				Size = UDim2.new(0, 0, 0, 0),
			}, TweenInfo.new(0.25, Enum.EasingStyle.Exponential))
			task.wait(0.15)

			StopSpinner(icon)
			notif.ImageLabel.Rotation = 0

			if success then
				Icons.SetIcon(notif.ImageLabel, "check")
				local message = (
					typeof(successText) == "string" and successText
					or typeof(successText) == "function" and successText(resultOrError)
					or "Success!"
				)

				if message:match("%s") then
					notif.Frame.TextLabel.Text = string.format(message, tostring(resultOrError))
				else
					notif.Frame.TextLabel.Text = message
				end
			else
				Icons.SetIcon(notif.ImageLabel, "circle-alert")
				notif.Frame.TextLabel.Text = (
					typeof(errorText) == "string" and errorText
					or typeof(errorText) == "function" and errorText(resultOrError)
					or "Error!"
				)
			end

			Animations.FadeIn(notif.ImageLabel)
			Animations.Play(notif.ImageLabel, {
				Size = UDim2.new(0, 20, 0, 20),
			}, TweenInfo.new(0.25, Enum.EasingStyle.Exponential))

			task.delay(time, function()
				if not table.find(Sonner.Queue, notif) then
					return
				end
				table.remove(Sonner.Queue, table.find(Sonner.Queue, notif))

				Animations.FadeOut(notif, 0.35)
				Animations.Play(notif, {
					Position = GetHiddenPosition(notif),
				}, Sonner.TweenInfo)

				task.wait(0.5)
				notif:Destroy()
			end)
		end)
	end)
end

function Sonner.rawtoast(options)
	local image = options.image
	local text = options.text or "No Text Provided"
	local internalTime = options.time or 4.5

	toast(image, text, internalTime)
end

function Sonner.init(wrapper)
	Sonner.Wrapper = wrapper
	task.spawn(ProcessQueue)
end

return Sonner
