local DEFAULT_TIMEOUT_SECONDS = 1500

--[[
	Upper bound on pending invocations tracked per remote.

	Entries keep their captured arguments alive until the timeout expires (25
	minutes by default), so an extremely chatty remote could hold on to a lot of
	memory in the meantime.  This is a safety valve, not a queue: it is only ever
	reached under heavy load.
]]
local MAX_ENTRIES_PER_INSTANCE = 256

local InvocationTracker = {}
InvocationTracker.__index = InvocationTracker

export type Tracker = typeof(setmetatable(
	{} :: {
		Entries: { [string]: { [number]: { Value: any, CreatedAt: number } } },
		TimeoutSeconds: number,
		LastPrune: number,
	},
	InvocationTracker
))

function InvocationTracker.new(timeoutSeconds: number?): Tracker
	return setmetatable({
		Entries = {},
		TimeoutSeconds = timeoutSeconds or DEFAULT_TIMEOUT_SECONDS,
		LastPrune = os.clock(),
	}, InvocationTracker)
end

function InvocationTracker.Prune(self: Tracker, now: number?)
	now = now or os.clock()
	if now - self.LastPrune < 1 then
		return
	end

	self.LastPrune = now
	for instance, entries in self.Entries do
		for invokeId, entry in entries do
			if now - entry.CreatedAt >= self.TimeoutSeconds then
				entries[invokeId] = nil
			end
		end

		if next(entries) == nil then
			self.Entries[instance] = nil
			if self.Counts then
				self.Counts[instance] = nil
			end
		end
	end
end

function InvocationTracker.Add(self: Tracker, instance: Instance, invokeId: number, value: any)
	self:Prune()

	local key = wax.shared.GetDebugId(instance)
	local entries = self.Entries[key]
	if not entries then
		entries = {}
		self.Entries[key] = entries
		self.Counts = self.Counts or {}
		self.Counts[key] = 0
	end

	local counts = self.Counts
	local count = (counts and counts[key] or 0) + 1
	if count > MAX_ENTRIES_PER_INSTANCE then
		-- Bounded: start the window over instead of holding everything forever.
		table.clear(entries)
		count = 1
	end

	if counts then
		counts[key] = count
	end

	entries[invokeId] = {
		Value = value,
		CreatedAt = os.clock(),
	}
end

function InvocationTracker.Has(self: Tracker, instance: Instance, invokeId: number): boolean
	self:Prune()

	local entries = self.Entries[wax.shared.GetDebugId(instance)]
	if not entries then
		return false
	end

	local entry = entries[invokeId]
	return entry ~= nil and os.clock() - entry.CreatedAt < self.TimeoutSeconds
end

function InvocationTracker.Consume(self: Tracker, instance: Instance, invokeId: number): any?
	self:Prune()

	local key = wax.shared.GetDebugId(instance)
	local entries = self.Entries[key]
	if not entries then
		return nil
	end

	local entry = entries[invokeId]
	entries[invokeId] = nil
	if next(entries) == nil then
		self.Entries[key] = nil
		if self.Counts then
			self.Counts[key] = nil
		end
	end

	if not entry or os.clock() - entry.CreatedAt >= self.TimeoutSeconds then
		return nil
	end

	return entry.Value
end

function InvocationTracker.Clear(self: Tracker)
	table.clear(self.Entries)
	if self.Counts then
		table.clear(self.Counts)
	end
end

return InvocationTracker
