
local RakNet = script:FindFirstAncestor("RakNet")

local Codec = require(RakNet.Codec)
local Lookup = require(RakNet.Lookup)
local VariantTypes = require(RakNet.Constants).VariantTypes


local INSTANCE_TYPE = VariantTypes.InstanceLegacy
local INSTANCE_REF_TYPE = VariantTypes.Instance
local INSTANCE_ALT_TYPE = VariantTypes.InstanceAlt

local DecoderModule = {
	Type = { INSTANCE_TYPE, INSTANCE_REF_TYPE, INSTANCE_ALT_TYPE },
}

function DecoderModule.Parse(data: buffer, offset: number, _t: number, _parser: any, _depth: number)
	local ref, newOffset = Codec.ReadInstanceRef(data, offset)
	if ref.is_null then
		return {
			Result = nil,
			Offset = newOffset,
		}
	end

	return {
		Result = Lookup.Instance.ByRef(ref),
		Offset = newOffset,
	}
end

return DecoderModule
