local VariantTypes = require(script.Parent.Parent.Parent.Constants).VariantTypes

local DecoderModule = {
	Type = VariantTypes.UDim,
}

function DecoderModule.Parse(data: buffer, offset: number, _t: number, _parser: any, _depth: number)
	local scale = buffer.readf32(data, offset)
	local udimOffset = buffer.readi32(data, offset + 4)
	return {
		Result = UDim.new(scale, udimOffset),
		Offset = offset + 8,
	}
end

return DecoderModule
