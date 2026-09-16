
local Interface = require("@src/Utils/UI/Interface")
local Constants = require("@src/Window/Constants")
local Types = require("@src/Window/Types")
local Animations = require("@src/Window/Utils/Animations")


return function(props: {
	Parent: GuiObject,
	OnSelected: (Tab: Types.LogDirectionTab) -> (),
})
	local DirectionTabs = {
		Tabs = {},
		CurrentTab = nil,
	}

	function DirectionTabs:Select(Tab, Force: boolean?)
		if self.CurrentTab == Tab and not Force then
			return
		end

		if self.CurrentTab then
			Animations.Play(self.CurrentTab.Instance, {
				BackgroundTransparency = 1,
			}, Constants.DefaultTweenInfo)
		end

		self.CurrentTab = Tab
		Animations.Play(Tab.Instance, {
			BackgroundTransparency = 0,
		}, Constants.DefaultTweenInfo)

		props.OnSelected(Tab)
	end

	function DirectionTabs:Create(TabName: Types.LogDirection, Active: boolean, Logs)
		local Button = Interface.New("TextButton", {
			BackgroundColor3 = Color3.fromRGB(50, 50, 50),
			BackgroundTransparency = Active and 0 or 1,
			Size = UDim2.fromScale(0, 1),
			TextSize = 15,
			Text = TabName,
			Parent = props.Parent,

			["UICorner"] = {
				CornerRadius = UDim.new(0, 4),
			},
		})

		local Tab = {
			Name = TabName,
			Logs = Logs,
			Instance = Button,
		}
		self.Tabs[TabName] = Tab

		Button.MouseButton1Click:Connect(function()
			self:Select(Tab)
		end)

		-- Text-only feedback: the background colour is owned by the active-tab
		-- state above, so the two never fight over the same property.
		Animations.BindPress(Button, {
			Press = { TextTransparency = 0.45 },
			Release = { TextTransparency = 0 },
			TweenInfo = Constants.DefaultTweenInfo,
		})

		if Active then
			self.CurrentTab = Tab
		end

		return Tab
	end

	return DirectionTabs
end
