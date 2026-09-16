local VariantTypes = require(script.Parent.Parent.Parent.Constants).VariantTypes

local DecoderModule = {
	Type = VariantTypes.Rect2D,
}

function DecoderModule.Parse(data: buffer, offset: number, _t: number, _parser: any, _depth: number)
	local x0 = buffer.readf32(data, offset)
	local y0 = buffer.readf32(data, offset + 4)
	local x1 = buffer.readf32(data, offset + 8)
	local y1 = buffer.readf32(data, offset + 12)
	return {
		Result = Rect.new(x0, y0, x1, y1),
		Offset = offset + 16,
	}
end

return DecoderModule
