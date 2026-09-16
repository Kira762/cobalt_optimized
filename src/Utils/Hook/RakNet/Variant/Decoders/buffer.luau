
local Codec = require(script.Parent.Parent.Parent.Codec)
local VariantTypes = require(script.Parent.Parent.Parent.Constants).VariantTypes

local DecoderModule = {
	Type = VariantTypes.Buffer,
}

function DecoderModule.Parse(data: buffer, offset: number, _t: number, _parser: any, _depth: number)
	
	offset += 1

	local length, newOffset = Codec.LEB128(data, offset)
	local result = buffer.create(length)

	buffer.copy(result, 0, data, newOffset, length)

	return {
		Result = result,
		Offset = newOffset + length,
	}
end

return DecoderModule
