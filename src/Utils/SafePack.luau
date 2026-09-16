
local TableProxy = {}

local UNPACK_CHUNK = 7997
local SAFE_LIMIT = 12000

-- Scratch buffers for PackFast, indexed by re-entrancy depth.  Hooks are
-- synchronous per invocation, so a small stack covers every realistic nesting
-- level (a hook running inside another hook's capture window); beyond that,
-- PackFast falls back to a fresh table and correctness never depends on the
-- pool size.
local MAX_SCRATCH_DEPTH = 3
local ScratchPool = {}
local ScratchDepth = 0

local function ClearScratch(Scratch)
	local Count = Scratch.n or 0
	for Index = 1, Count do
		Scratch[Index] = nil
	end
	Scratch.n = 0
end

function TableProxy.Pack(...)
    return { n = select("#", ...), ... }
end

--[[

	Packs `...` into a shared scratch buffer instead of allocating a table.

	The hook path packs arguments on every intercepted call, so the fresh
	table per call adds avoidable GC pressure on busy games.  The returned
	table is only valid until the next PackFast at the same nesting depth:
	callers must be done with it (Log:Call deep-clones synchronously) and
	then hand it back via ReleaseFast.

	Re-entrant hooks nest onto the next scratch slot, and a nesting depth
	beyond the pool degrades to `Pack` (a fresh allocation) rather than
	corrupting an outer frame's arguments.
]]
function TableProxy.PackFast(...)
	local Scratch = ScratchPool[ScratchDepth + 1]
	if not Scratch then
		if ScratchDepth + 1 > MAX_SCRATCH_DEPTH then
			return TableProxy.Pack(...)
		end

		Scratch = { n = 0 }
		ScratchPool[ScratchDepth + 1] = Scratch
	end

	ScratchDepth += 1

	local Count = select("#", ...)
	for Index = 1, Count do
		Scratch[Index] = select(Index, ...)
	end

	-- Entries left over from the previous user of this slot must go: callers
	-- iterate with next() (DeepClone, LuaEncode) and would see stale values.
	local PreviousCount = Scratch.n or 0
	for Index = Count + 1, PreviousCount do
		Scratch[Index] = nil
	end
	Scratch.n = Count

	return Scratch
end

--[[

	Returns a scratch buffer taken by PackFast.  Safe to call with any packed
	table: foreign tables (e.g. from a Pack fallback) are simply cleared.
]]
function TableProxy.ReleaseFast(Scratch)
	if not Scratch then
		return
	end

	if ScratchPool[ScratchDepth] == Scratch then
		ScratchDepth -= 1
	end

	ClearScratch(Scratch)
end

--[[

	Stable copy of a packed table - used when arguments must outlive the hook
	frame that packed them (e.g. RemoteFunction invoke results).
]]
function TableProxy.Copy(Source)
	local Count = Source.n or #Source
	local Copy = {}
	for Index = 1, Count do
		Copy[Index] = Source[Index]
	end
	Copy.n = Count
	return Copy
end

function TableProxy.Unpack(Tbl, I, J)
    I = I or 1
    J = J or Tbl.n or #Tbl

    if J - I + 1 > SAFE_LIMIT then
        J = I + SAFE_LIMIT - 1
    end

    if J < I then
        return
    end

    if J - I + 1 <= UNPACK_CHUNK then
        return table.unpack(Tbl, I, J)
    end

    return Tbl[I], TableProxy.Unpack(Tbl, I + 1, J)
end

return TableProxy
