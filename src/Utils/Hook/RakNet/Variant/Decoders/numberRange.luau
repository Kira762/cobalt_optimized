local VariantTypes = require(script.Parent.Parent.Parent.Constants).VariantTypes

local DecoderModule = {
	Type = VariantTypes.NumberRange,
}

function DecoderModule.Parse(data: buffer, offset: number, _t: number, _parser: any, _depth: number)
	local min = buffer.readf32(data, offset)
	local max = buffer.readf32(data, offset + 4)
	return {
		Result = NumberRange.new(min, max),
		Offset = offset + 8,
	}
end

return DecoderModule
