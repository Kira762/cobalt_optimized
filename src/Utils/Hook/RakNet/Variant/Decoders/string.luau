
local Codec = require(script.Parent.Parent.Parent.Codec)
local VariantTypes = require(script.Parent.Parent.Parent.Constants).VariantTypes


local STRING_TYPE = VariantTypes.String
local BINARY_STRING_TYPE = VariantTypes.BinaryString

local DecoderModule = {
	Type = { STRING_TYPE, BINARY_STRING_TYPE },
}

function DecoderModule.Parse(data: buffer, offset: number, _t: number, _parser: any, _depth: number)
	local length, newOffset = Codec.LEB128(data, offset)
	return {
		Result = buffer.readstring(data, newOffset, length),
		Offset = newOffset + length,
	}
end

return DecoderModule
