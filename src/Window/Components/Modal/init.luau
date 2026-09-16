local Interface = require("@src/Utils/UI/Interface")
local Animations = require("@src/Window/Utils/Animations")

local Modal = {}
Modal.__index = Modal

export type Modal = {
	OpenedModal: GuiObject?,
	Background: GuiObject,
	TweenInfo: TweenInfo,
} & typeof(setmetatable({}, Modal))

local DefaultTweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Exponential)

-- Open/close motion for modal frames.  Scale only (never a full fade): the
-- modal's children keep their own transparencies, so the interface looks exactly
-- the same once the animation settles.
local OpenScale = 0.97
local CloseScale = 0.98
local CloseDuration = 0.13

function Modal.new(
	Parent: GuiObject,
	Options: {
		TweenInfo: TweenInfo?,
	}?
)
	local self = setmetatable({
		OpenedModal = nil,
		Background = nil,
		TweenInfo = Options and Options.TweenInfo or DefaultTweenInfo,
		BackdropTransparency = 0.5,
		Generation = 0,
	}, Modal)

	self.Background = Interface.New("TextButton", {
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.5,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Visible = false,
		ZIndex = 2,

		["UICorner"] = {
			CornerRadius = UDim.new(0, 6),
		},

		Parent = Parent,
	})

	self.BackdropTransparency = self.Background.BackgroundTransparency

	self.Background.MouseButton1Click:Connect(function()
		self:Close()
	end)

	return self
end

--[[
	Hides a modal frame instantly.  Pooled/parent-changing modals that get
	re-opened while a close animation is still running must not be hidden by the
	stale animation, which is what `Generation` guards against.
]]
local function HideAfter(Parent, Delay, IsCurrent: () -> boolean)
	if not Animations.IsEnabled() then
		if IsCurrent() then
			Parent.Visible = false
		end

		return
	end

	task.delay(Delay, function()
		if not IsCurrent() then
			return
		end

		Parent.Visible = false
	end)
end

function Modal:Open(Parent)
	if self.OpenedModal == Parent and Parent.Visible then
		self.Background.Visible = true
		self.Background.BackgroundTransparency = self.BackdropTransparency
		return
	end

	self.Generation += 1

	self.OpenedModal = Parent

	Parent.Visible = true
	self.Background.Visible = true

	-- Backdrop fades in from transparent instead of popping in.
	self.Background.BackgroundTransparency = 1
	Animations.Play(self.Background, {
		BackgroundTransparency = self.BackdropTransparency,
	}, self.TweenInfo)

	Animations.Pop(Parent, {
		From = OpenScale,
		To = 1,
		Duration = self.TweenInfo.Time,
		TweenInfo = self.TweenInfo,
	})
end

function Modal:Close()
	local Opened = self.OpenedModal
	self.OpenedModal = nil
	self.Generation += 1
	local Generation = self.Generation

	local function IsCurrent(): boolean
		return self.Generation == Generation
	end

	if Opened then
		Animations.Pop(Opened, {
			From = 1,
			To = CloseScale,
			Duration = CloseDuration,
			TweenInfo = TweenInfo.new(CloseDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		})

		HideAfter(Opened, CloseDuration, IsCurrent)
	end

	Animations.Play(self.Background, {
		BackgroundTransparency = 1,
	}, TweenInfo.new(self.TweenInfo.Time, Enum.EasingStyle.Exponential, Enum.EasingDirection.In))

	HideAfter(self.Background, self.TweenInfo.Time, IsCurrent)
end

function Modal:ConnectCloseButton(Button, Image)
	Animations.BindHover(Button, {
		ImageTransparency = 0.5,
	}, {
		ImageTransparency = 0.25,
	}, self.TweenInfo)

	Button.MouseButton1Click:Connect(function()
		self:Close()
	end)
end

function Modal:CreateTop(Title: string, Icon: string, Parent: GuiObject)
	local ModalTop = Interface.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = Parent,

		["UIPadding"] = {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
		},
	})

	local ModalTitle = Interface.New("TextLabel", {
		Text = Title,
		TextSize = 17,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = ModalTop,
	})

	local ModalIcon
	if Icon:match("rbxasset") then
		ModalIcon = Interface.New("ImageLabel", {
			Image = Icon,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(4, 0),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,

			Parent = ModalTop,
		})
	else
		ModalIcon = Interface.NewIcon(Icon, {
			ImageTransparency = 0.5,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(4, 0),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,

			Parent = ModalTop,
		})
	end

	local CloseButton = Interface.New("ImageButton", {
		Size = UDim2.fromScale(1, 1),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Parent = ModalTop,
	})

	local CloseImage = Interface.NewIcon("x", {
		ImageTransparency = 0.5,
		Size = UDim2.fromOffset(22, 22),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,

		Parent = CloseButton,
	})

	self:ConnectCloseButton(CloseButton, CloseImage)

	Interface.New("Frame", {
		Parent = Parent,
		BackgroundColor3 = Color3.fromRGB(25, 25, 25),
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.fromOffset(0, 36),
	})

	return ModalTitle, ModalIcon
end

return Modal
