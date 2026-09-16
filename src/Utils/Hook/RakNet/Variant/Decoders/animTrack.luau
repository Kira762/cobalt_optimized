
local Codec = require(script.Parent.Parent.Parent.Codec)
local VariantTypes = require(script.Parent.Parent.Parent.Constants).VariantTypes


local ANIM_TRACK_VARIANT_TYPE = VariantTypes.AnimTrackVariant
local ANIM_TRACK_PLAY_STATE_TYPE = VariantTypes.AnimTrackPlayState
local ANIM_TRACK_METADATA_TYPE = VariantTypes.AnimTrackMetadata
local ANIM_TRACK_WEIGHT_TYPE = VariantTypes.AnimTrackWeight

local DecoderModule = {
	Type = {
		ANIM_TRACK_VARIANT_TYPE,
		ANIM_TRACK_PLAY_STATE_TYPE,
		ANIM_TRACK_METADATA_TYPE,
		ANIM_TRACK_WEIGHT_TYPE,
	},
}

local Router = {
	
	[ANIM_TRACK_VARIANT_TYPE] = function(data: buffer, offset: number)
		local n, newOffset = Codec.LEB128(data, offset)
		return {
			Result = { animTrackVariant = Codec.ZzDec(n) },
			Offset = newOffset,
		}
	end,

	
	[ANIM_TRACK_PLAY_STATE_TYPE] = function(data: buffer, offset: number)
		return {
			Result = {
				flags = buffer.readu8(data, offset),
				f32 = buffer.readf32(data, offset + 1),
				f64 = buffer.readf64(data, offset + 5),
			},
			Offset = offset + 13,
		}
	end,

	
	[ANIM_TRACK_METADATA_TYPE] = function(data: buffer, offset: number)
		return {
			Result = {
				byte = buffer.readu8(data, offset),
				i16 = buffer.readi16(data, offset + 1),
			},
			Offset = offset + 3,
		}
	end,

	
	[ANIM_TRACK_WEIGHT_TYPE] = function(data: buffer, offset: number)
		return {
			Result = {
				f0 = buffer.readf32(data, offset),
				f1 = buffer.readf32(data, offset + 4),
				d = buffer.readf64(data, offset + 8),
			},
			Offset = offset + 16,
		}
	end,
}

function DecoderModule.Parse(data: buffer, offset: number, t: number, _parser: any, _depth: number)
	return Router[t](data, offset)
end

return DecoderModule
