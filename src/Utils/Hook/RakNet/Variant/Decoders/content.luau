
local Codec = require(script.Parent.Parent.Parent.Codec)
local Lookup = require(script.Parent.Parent.Parent.Lookup)
local VariantTypes = require(script.Parent.Parent.Parent.Constants).VariantTypes

local DecoderModule = {
	Type = VariantTypes.Content,
}

local KIND_ID_URI: { [number]: (number) -> string } = {
	[3] = function(id)
		return "rbxassetid://" .. tostring(id)
	end,
	[11] = function(id)
		return "http://www.roblox.com/asset/?id=" .. tostring(id)
	end,
	[13] = function(id)
		return "https://www.roblox.com/asset/?id=" .. tostring(id)
	end,
	[21] = function(id)
		return "https://assetdelivery.roblox.com/v1/asset/?id=" .. tostring(id)
	end,
}

local KIND_PREFIX: { [number]: string } = {
	[4] = "rbxgameasset://",
}

local function readNulString(data: buffer, offset: number): (string, number)
	local len, nextOffset = Codec.LEB128U(data, offset)
	local s = buffer.readstring(data, nextOffset, len)
	nextOffset += len
	
	nextOffset += 1
	return s, nextOffset
end

function DecoderModule.Parse(data: buffer, offset: number, _t: number, _parser: any, _depth: number)
	local source = buffer.readu8(data, offset)
	offset += 1

	if source == 0 then
		return { Result = Content.none, Offset = offset }
	end

	if source == 1 then
		local kind = buffer.readu8(data, offset)
		offset += 1

		if kind == 0 then
			local uri
			uri, offset = readNulString(data, offset)
			return { Result = Content.fromUri(uri), Offset = offset }
		end

		local prefix = KIND_PREFIX[kind]
		if prefix then
			local suffix
			suffix, offset = readNulString(data, offset)
			return { Result = Content.fromUri(prefix .. suffix), Offset = offset }
		end

		local toUri = KIND_ID_URI[kind]
		if toUri then
			local zz, nextOffset = Codec.LEB128U(data, offset)
			local id = Codec.ZzDec(zz)
			return { Result = Content.fromUri(toUri(id)), Offset = nextOffset }
		end

		return {
			Result = { contentKind = kind },
			Offset = offset,
		}
	end

	if source == 2 then
		local ref, refOffset = Codec.ReadInstanceRef(data, offset)
		if ref.is_null then
			return { Result = Content.none, Offset = refOffset }
		end
		local inst = Lookup.Instance.ByRef(ref)
		if inst then
			local ok, content = pcall(Content.fromObject, inst)
			if ok then
				return { Result = content, Offset = refOffset }
			end
		end
		return {
			Result = { contentObjectId = ref.instance_id, peerId = ref.peer_id },
			Offset = refOffset,
		}
	end

	
	return {
		Result = if source == 3 then Content.none else { contentSource = source },
		Offset = offset,
	}
end

return DecoderModule
