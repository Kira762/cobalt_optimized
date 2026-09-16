
local Codec = require(script.Parent.Parent.Parent.Codec)
local VariantTypes = require(script.Parent.Parent.Parent.Constants).VariantTypes


local OPTIONAL_CFRAME_ALT_TYPE = VariantTypes.OptionalCoordinateFrameLegacy
local OPTIONAL_CFRAME_TYPE = VariantTypes.OptionalCoordinateFrame

local DecoderModule = {
	Type = { OPTIONAL_CFRAME_ALT_TYPE, OPTIONAL_CFRAME_TYPE },
}

function DecoderModule.Parse(data: buffer, offset: number, _t: number, _parser: any, _depth: number)
	local cf, newOffset = Codec.ReadOptCFrame(data, offset)
	return {
		Result = cf,
		Offset = newOffset,
	}
end

return DecoderModule
