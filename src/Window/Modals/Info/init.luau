
local Interface = require("@src/Utils/UI/Interface")
local Constants = require("@src/Window/Constants")
local Types = require("@src/Window/Types")

local ModalController = require("@src/Window/Components/Modal")
local ContextMenu = require("@src/Window/Components/ContextMenu")

local CodeGen = require("@src/Utils/CodeGen/Generator")


local ArgumentList = require(script.Components.ArgumentList)
local CodeView = require(script.Components.CodeView)
local CreateDefaultFooterButtons = require(script.Components.FooterButtons)
local FunctionInfoView = require(script.Components.FunctionInfoView)


local SetupModal = require(script.Shell)


return function(props: {
	ModalController: ModalController.Modal,
	ContextMenu: ContextMenu.ContextMenu,
	GetDPIScale: (() -> number)?,
	LogsPage: Types.LogsPage,
})
	
	local ModalController = props.ModalController
	local ContextMenu = props.ContextMenu
	local LogsPage = props.LogsPage

	
	local Modal = SetupModal({
		ModalController = ModalController,
		ContextMenu = ContextMenu,
		GetDPIScale = props.GetDPIScale,
	})

	Modal.Footer.BuiltInButtons = CreateDefaultFooterButtons({
		Modal = Modal,
		ModalController = ModalController,
		LogsPage = LogsPage,
	})

	

	
	local ArgumentsInfoUI, ArgumentsScrollingFrame = Modal.Tabs:CreateTabContent()
	local ArgumentsInfoFrame
	do
		Modal.Tabs:CreateTab("ellipsis", "Arguments", ArgumentsInfoUI)
		ArgumentsScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y

		ArgumentsInfoFrame = Interface.New("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),

			["UIListLayout"] = {
				Padding = UDim.new(0, 6),
			},

			Constants.MainUICorner,

			Parent = ArgumentsScrollingFrame,
		})
	end

	
	local OriginalArgsInfoUI, OriginalArgsScrollingFrame = Modal.Tabs:CreateTabContent()
	local OriginalArgsInfoFrame
	do
		Modal.Tabs:CreateTab("list", "Args", OriginalArgsInfoUI)
		OriginalArgsScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		Modal.Tabs:SetMounted("Args", false)

		OriginalArgsInfoFrame = Interface.New("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),

			["UIListLayout"] = {
				Padding = UDim.new(0, 6),
			},

			Constants.MainUICorner,

			Parent = OriginalArgsScrollingFrame,
		})
	end

	
	local CodeInfoUI, CodeScrollingFrame = Modal.Tabs:CreateTabContent()
	local CodeDisplay
	do
		Modal.Tabs:CreateTab("code", "Code", CodeInfoUI)
		CodeScrollingFrame.ScrollBarThickness = 3
		CodeScrollingFrame.VerticalScrollBarInset = Enum.ScrollBarInset.None

		CodeDisplay = CodeView.new(CodeScrollingFrame)
	end

	
	local FunctionInfoUI, FunctionScrollingFrame = Modal.Tabs:CreateTabContent()
	local FunctionInfoDisplay
	do
		Modal.Tabs:CreateTab("parentheses", "Function Info", FunctionInfoUI)

		FunctionInfoDisplay = FunctionInfoView.new(FunctionScrollingFrame)
	end

	
	function Modal:Open(CallInfo)
		
		if wax.shared.CobaltPluginManager and wax.shared.CobaltPluginManager.Initialized then
			for _, Interceptor in wax.shared.CobaltPluginManager.Registry.UIHooks.RemoteInfo.Intercept do
				local Success, Result = pcall(Interceptor, CallInfo)

				if Success and Result == false then
					return
				end
			end
		end

		local Event = CallInfo.Instance

		
		Modal.Title.Text = if CallInfo.Blocked then `{Event.Name} (Blocked)` else Event.Name
		Modal.Icon.Image = Constants.InstanceClassImages[Event.ClassName]

		
		Modal.CurrentInfo = CallInfo

		
		CodeDisplay:SetText(CodeGen:BuildCallCode(CallInfo))

		
		FunctionInfoDisplay:SetCallInfo(CallInfo)

		
		local InitialDataView = (
			if CallInfo.Type == "Incoming" and CallInfo.InvokeResult then "InvokeResult" else "Arguments"
		)

		local FirstTab = Modal.Tabs[Modal.Tabs[1]]

		if FirstTab and FirstTab.TextLabel then
			FirstTab.TextLabel.Text = if InitialDataView == "InvokeResult" then "Return Data" else "Arguments"
		end

		
		ArgumentList.Clear(ArgumentsInfoFrame)
		ArgumentList.Clear(OriginalArgsInfoFrame)

		
		ArgumentList.Populate(ArgumentsInfoFrame, CallInfo[InitialDataView])

		local ShouldShowOriginalArgs = (
			InitialDataView == "InvokeResult" and wax.shared.GetTableLength(CallInfo.Arguments) > 0
		)

		Modal.Tabs:SetMounted("Args", ShouldShowOriginalArgs)
		if ShouldShowOriginalArgs then
			ArgumentList.Populate(OriginalArgsInfoFrame, CallInfo.Arguments)
		end

		
		if wax.shared.CobaltPluginManager and wax.shared.CobaltPluginManager.Initialized then
			for _, Plugin in wax.shared.CobaltPluginManager.Registry.UIHooks.RemoteInfo.Open do
				task.spawn(Plugin, CallInfo)
			end
		end

		
		Modal.Tabs:Select("Arguments")

		if ContextMenu.CurrentContext then
			ContextMenu.CurrentContext.Close()
		end

		ModalController:Open(Modal.Frame)
	end

	return Modal
end
