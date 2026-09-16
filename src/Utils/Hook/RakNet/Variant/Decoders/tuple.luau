
local Codec = require(script.Parent.Parent.Parent.Codec)
local VariantTypes = require(script.Parent.Parent.Parent.Constants).VariantTypes


local TUPLE_TYPE = VariantTypes.Tuple
local ARRAY_TYPE = VariantTypes.Array

local DecoderModule = {
	Type = { TUPLE_TYPE, ARRAY_TYPE },
}

function DecoderModule.Parse(data: buffer, offset: number, _t: number, parser: any, depth: number)
	local length = buffer.len(data)
	local count, nextOffset = Codec.LEB128(data, offset)
	local remainingBytes = length - nextOffset
	if count > remainingBytes then
		return { Result = {}, Offset = -1 }
	end

	local values = table.create(count)
	offset = nextOffset
	for i = 1, count do
		local parsed = parser:Parse(offset, depth + 1)
		if parsed.Offset < 0 then
			return { Result = values, Offset = -1 }
		end
		values[i] = parsed.Result
		offset = parsed.Offset
	end

	return {
		Result = values,
		Offset = offset,
	}
end

return DecoderModule
