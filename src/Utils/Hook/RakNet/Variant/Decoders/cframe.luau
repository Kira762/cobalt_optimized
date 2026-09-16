
local Codec = require(script.Parent.Parent.Parent.Codec)
local VariantTypes = require(script.Parent.Parent.Parent.Constants).VariantTypes


local CFRAME_V1_TYPE = VariantTypes.CoordinateFrameLegacy
local CFRAME_TYPE = VariantTypes.CoordinateFrame

local DecoderModule = {
	Type = { CFRAME_V1_TYPE, CFRAME_TYPE },
}

function DecoderModule.Parse(data: buffer, offset: number, _t: number, _parser: any, _depth: number)
	local cf, newOffset = Codec.ReadCFrameV1(data, offset)
	return {
		Result = cf,
		Offset = newOffset,
	}
end

return DecoderModule
