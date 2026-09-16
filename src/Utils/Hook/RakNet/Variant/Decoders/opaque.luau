local VariantTypes = require(script.Parent.Parent.Parent.Constants).VariantTypes


local FACS_DATA_TYPE = VariantTypes.FacsReplicationData
local NET_ASSET_HANDLE_TYPE = VariantTypes.NetAssetHandle
local NET_ASSET_REF_TYPE = VariantTypes.NetAssetRef
local SLIM_REPLICATION_DATA_TYPE = VariantTypes.SlimReplicationData

local DecoderModule = {
	Type = {
		FACS_DATA_TYPE,
		NET_ASSET_HANDLE_TYPE,
		NET_ASSET_REF_TYPE,
		SLIM_REPLICATION_DATA_TYPE,
	},
}

function DecoderModule.Parse(data: buffer, offset: number, t: number, _parser: any, _depth: number)
	local remaining = buffer.len(data) - offset
	local sliceLen = math.min(remaining, 8)
	local slice = buffer.create(sliceLen)
	if sliceLen > 0 then
		buffer.copy(slice, 0, data, offset, sliceLen)
	end

	return {
		Result = {
			typeId = t,
			bytes = slice,
		},
		Offset = -1,
	}
end

return DecoderModule
