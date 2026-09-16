local VariantTypes = require(script.Parent.Parent.Parent.Constants).VariantTypes

local NIL_TYPE = VariantTypes.Nil
local NIL_ALT_TYPE = VariantTypes.NilAlt

local DecoderModule = {
	Type = { NIL_TYPE, NIL_ALT_TYPE },
}

function DecoderModule.Parse(data: buffer, offset: number, _t: number, _parser: any, _depth: number)
	return {
		Result = nil,
		Offset = offset,
	}
end

return DecoderModule
