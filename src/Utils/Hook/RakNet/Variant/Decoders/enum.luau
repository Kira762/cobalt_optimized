
local Codec = require(script.Parent.Parent.Parent.Codec)
local Constants = require(script.Parent.Parent.Parent.Constants)

local DecoderModule = {
	Type = Constants.VariantTypes.Enum,
}

local function findByValue(enum: Enum, value: number): EnumItem?
	for _, item in enum:GetEnumItems() do
		if item.Value == value then
			return item
		end
	end
	return nil
end

local function findUniqueByValue(value: number): EnumItem?
	local match: EnumItem? = nil
	for _, enum in Enum:GetEnums() do
		for _, item in enum:GetEnumItems() do
			if item.Value ~= value then
				continue
			end

			if match then
				return nil 
			end

			match = item
		end
	end

	return match
end

function DecoderModule.Parse(data: buffer, offset: number, _t: number, _parser: any, _depth: number)
	local typeId = buffer.readu16(data, offset)
	local value, newOffset = Codec.LEB128(data, offset + 2)

	local enum = Constants.GetEnum(typeId)
	local item = if enum then findByValue(enum, value) else nil
	if not item then
		item = findUniqueByValue(value)
		if item and not Constants.EnumTypes[typeId] then
			Constants.EnumTypes[typeId] = item.EnumType
		end
	end

	return {
		Result = item or value,
		Offset = newOffset,
	}
end

return DecoderModule
