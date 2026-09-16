
local Interface = require("@src/Utils/UI/Interface")

local LazySerializer = require("@src/Window/Utils/Text/LazySerializer")
local SyntaxHighlighter = require("@src/Window/Utils/Text/Highlighter")
local TextBounds = require("@src/Window/Utils/Text/TextBounds")

local ArgumentList = {}

local DefaultPreviewMaxLength = 500

-- How much work (in seconds of real work, not idle frames) one slice of
-- argument rendering may do before handing the frame back.
local PopulateSliceSeconds = 0.004

--[[
	Argument holders are built out of five instances each, and a single page of
	logs can be hundreds of holders.  Destroying and rebuilding them every time
	a row is recycled was the single biggest source of UI churn while the spy
	runs, so holders are pooled instead: releasing reparents them out of view and
	acquiring re-fills every property that varies.

	The pool is bounded, so a long session can never turn the pool itself into a
	memory problem.
]]
local HolderPool = {}
local MaxPooledHolders = 512
local PooledHolderCount = 0

local function ResetHolder(Holder, IsBlockedCall: boolean?)
	Holder.BackgroundColor3 = if IsBlockedCall then Color3.fromRGB(58, 24, 24) else Color3.fromRGB(25, 25, 25)
	Holder.Size = UDim2.new(1, 0, 0, 27)
end

-- Instances cannot carry custom fields, so each holder's three labels are
-- looked up through a weak side table instead.
local HolderLabels = setmetatable({}, { __mode = "k" })

local function BuildHolder()
	local Holder = Interface.New("Frame", {
		Size = UDim2.new(1, 0, 0, 27),

		["UICorner"] = {
			CornerRadius = UDim.new(0, 4),
		},

		["UIPadding"] = {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
		},
	})

	local IndexLabel = Interface.New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		TextSize = 15,
		TextTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,

		Parent = Holder,
	})

	local TypeLabel = Interface.New("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		TextSize = 15,
		TextTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,

		Parent = Holder,
	})

	local TextLabel = Interface.New("TextLabel", {
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,

		Parent = Holder,
	})

	HolderLabels[Holder] = {
		Index = IndexLabel,
		Type = TypeLabel,
		Text = TextLabel,
	}

	return Holder
end

local function AcquireHolder(): GuiObject
	local Pooled = table.remove(HolderPool)

	if Pooled then
		PooledHolderCount -= 1
		return Pooled
	end

	return BuildHolder()
end

--[[
	Puts a holder back in the pool (or destroys it when the pool is full).
	The holder is parented to nil first, so it can never flash in the interface
	while it waits to be reused.
]]
function ArgumentList.ReleaseHolder(Holder: GuiObject)
	Holder.Parent = nil

	if PooledHolderCount >= MaxPooledHolders then
		Holder:Destroy()
		return
	end

	PooledHolderCount += 1
	HolderPool[PooledHolderCount] = Holder
end

local function TruncatePreviewText(Text: string, MaxLength: number): string
	local NormalizedText = Text:gsub("[\r\n\t]", " ")
	if #Text <= MaxLength then
		return NormalizedText
	end

	return NormalizedText:sub(1, MaxLength) .. "..."
end

function ArgumentList.CreatePreviewText(Value: any, MaxLength: number?): string
	MaxLength = MaxLength or DefaultPreviewMaxLength

	if typeof(Value) == "string" then
		return `"{TruncatePreviewText(Value, MaxLength)}"`
	end

	return TruncatePreviewText(tostring(LazySerializer.QuickSerializeArgument(Value)), MaxLength)
end

--[[
	Empties a frame holding argument holders.

	The holders themselves are recycled rather than destroyed; to the caller the
	frame ends up just as empty as before.
]]
function ArgumentList.Clear(Frame: GuiObject)
	for _, Object in Frame:GetChildren() do
		if not Object:IsA("Frame") then
			continue
		end

		ArgumentList.ReleaseHolder(Object)
	end
end

type HolderOptions = {
	IsBlockedCall: boolean?,
	IsError: boolean?,
	IsPreview: boolean?,
	Label: string?,
	MaxPreviewLength: number?,
	PreviewCache: { [number]: string }?,
}

function ArgumentList.CreateHolder(Index: number, Value: any, Parent: GuiObject, Options: HolderOptions | boolean?)
	if typeof(Options) ~= "table" then
		Options = {
			IsBlockedCall = Options,
		}
	end

	
	local IsBlockedCall = Options.IsBlockedCall
	local IsError = Options.IsError == true
	local PreviewCache = Options.PreviewCache
	local IsPreview = Options.IsPreview == true

	local Holder = AcquireHolder()
	ResetHolder(Holder, IsBlockedCall)

	Holder.LayoutOrder = Index
	Holder.Parent = Parent

	local Labels = HolderLabels[Holder]
	local IndexLabel = Labels.Index
	local TypeLabel = Labels.Type
	local TextLabel = Labels.Text

	local TextColor = if IsBlockedCall or IsError then Color3.fromRGB(255, 190, 190) else Color3.new(1, 1, 1)

	IndexLabel.Text = Options.Label or Index
	IndexLabel.TextColor3 = TextColor

	TypeLabel.Text = typeof(Value)
	TypeLabel.TextColor3 = TextColor

	local IndexX = TextBounds.GetCachedWidth(IndexLabel.Text, IndexLabel.FontFace, IndexLabel.TextSize)
	local TypeX = TextBounds.GetCachedWidth(TypeLabel.Text, TypeLabel.FontFace, TypeLabel.TextSize)

	local Text
	if IsPreview then
		if PreviewCache then
			if not PreviewCache[Index] then
				PreviewCache[Index] = ArgumentList.CreatePreviewText(Value, Options.MaxPreviewLength)
			end

			Text = PreviewCache[Index]
		else
			Text = ArgumentList.CreatePreviewText(Value, Options.MaxPreviewLength)
		end
	else
		Text = tostring(LazySerializer.QuickSerializeArgument(Value)):gsub("<", "&lt;"):gsub(">", "&gt;")
	end

	TextLabel.Position = UDim2.fromOffset(IndexX + 6, 0)
	TextLabel.Size = UDim2.new(1, -(IndexX + TypeX + 10), 1, 0)
	TextLabel.TextColor3 = if IsBlockedCall or IsError
		then Color3.fromRGB(255, 190, 190)
		else Color3.fromHex(SyntaxHighlighter.GetArgumentColor(Value))
	TextLabel.Text = Text
	TextLabel.RichText = not IsPreview
	TextLabel.TextTruncate = if IsPreview then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None
	TextLabel.TextWrapped = not IsPreview

	if IsPreview then
		-- Preview holders keep the fixed row height; a recycled holder may have
		-- been stretched by the full-size view before.
		Holder.Size = UDim2.new(1, 0, 0, 27)
	else
		local _, TextY = TextBounds.Get(TextLabel.Text, TextLabel.FontFace, TextLabel.TextSize, TextLabel.AbsoluteSize.X)
		Holder.Size = UDim2.new(1, 0, 0, TextY + 12)
	end

	return Holder
end

function ArgumentList.Populate(Frame: GuiObject, Values: { [any]: any }?): number
	if not Values then
		return 0
	end

	local Count = wax.shared.GetTableLength(Values)
	local SliceStart = os.clock()

	for Index = 1, Count do
		-- Yield only once a frame's worth of work has been done; short argument
		-- lists (the common case) then render without costing any frames.
		if os.clock() - SliceStart >= PopulateSliceSeconds then
			task.wait()
			SliceStart = os.clock()
		end

		ArgumentList.CreateHolder(Index, Values[Index], Frame)
	end

	return Count
end

return ArgumentList
