type RatelimiterOptions = {
	Burst: {
		Time: number,
		Max: number,
	},

	PeriodicInterval: number?,
	MainCallback: (...any) -> ...any,
	ShouldProcess: ((...any) -> boolean)?,
	OnUnload: (() -> ())?,
	-- A bounded queue is important for UI jobs: once a page is stale, waiting
	-- behind thousands of old rows is worse than dropping a few rows.
	MaxQueue: number?,
	DropOldest: boolean?,
}

local Ratelimits = {}
local Ratelimiter = {}
Ratelimiter.__index = Ratelimiter

function Ratelimiter.new(Options: RatelimiterOptions)
	assert(type(Options) == "table", "Ratelimiter options must be a table")
	assert(type(Options.MainCallback) == "function", "Ratelimiter requires MainCallback")

	local self = setmetatable(Options, Ratelimiter)
	self.Burst = self.Burst or { Time = 0.1, Max = 1 }
	self.Burst.Time = math.max(tonumber(self.Burst.Time) or 0.1, 0.001)
	self.Burst.Max = math.max(math.floor(tonumber(self.Burst.Max) or 1), 1)
	self.MaxQueue = self.MaxQueue and math.max(math.floor(self.MaxQueue), 1) or nil
	self.DropOldest = self.DropOldest ~= false
	self.Bucket = {}
	self.Queue = {}
	self.QueueHead = 1
	self.QueueTail = 0

	self.IsDestroyed = false
	self.ManagerThread = nil
	self.PeriodicThread = nil

	self:SetupManagerThread()

	table.insert(Ratelimits, self)
	return self
end

function Ratelimiter.StopAll()
	for _, Ratelimit in Ratelimits do
		Ratelimit:Destroy()
	end

	table.clear(Ratelimits)
end

function Ratelimiter:QueueOperation(...: any): boolean
	if self.IsDestroyed then
		return false
	end

	local Pending = self.QueueTail - self.QueueHead + 1
	if self.MaxQueue and Pending >= self.MaxQueue then
		if not self.DropOldest then
			return false
		end

		self.Queue[self.QueueHead] = nil
		self.QueueHead += 1
	end

	self.QueueTail += 1
	self.Queue[self.QueueTail] = table.pack(...)
	return true
end

function Ratelimiter:SetupManagerThread()
	if self.IsDestroyed then
		return
	end

	self.Bucket = {}
	self.Queue = {}
	self.QueueHead = 1
	self.QueueTail = 0

	if self.ManagerThread then
		pcall(task.cancel, self.ManagerThread)
		self.ManagerThread = nil
	end

	if self.PeriodicThread then
		pcall(task.cancel, self.PeriodicThread)
		self.PeriodicThread = nil
	end

	self.ManagerThread = task.spawn(function()
		while not wax.shared.Unloaded and not self.IsDestroyed do
			local CurrentTime = os.clock()
			local DidWork = false

			if #self.Bucket > 0 then
				local NewBucket = {}
				for _, Time in self.Bucket do
					if CurrentTime - Time < self.Burst.Time then
						NewBucket[#NewBucket + 1] = Time
					end
				end
				self.Bucket = NewBucket
			end

			while #self.Bucket < self.Burst.Max and self.QueueHead <= self.QueueTail do
				local TaskData = self.Queue[self.QueueHead]
				self.Queue[self.QueueHead] = nil
				self.QueueHead += 1

				if self.QueueHead > self.QueueTail then
					table.clear(self.Queue)
					self.QueueHead = 1
					self.QueueTail = 0
				end

				local ShouldRun = TaskData ~= nil
				if ShouldRun and self.ShouldProcess then
					local Success, Result = pcall(self.ShouldProcess, table.unpack(TaskData, 1, TaskData.n))
					ShouldRun = Success and Result ~= false
				end

				if ShouldRun then
					self.Bucket[#self.Bucket + 1] = os.clock()
					DidWork = true
					task.defer(function()
						if self.IsDestroyed then
							return
						end
						pcall(self.MainCallback, table.unpack(TaskData, 1, TaskData.n))
					end)
				end
			end

			-- Do not wake every frame when idle.  A bounded queue still picks up
			-- new work quickly without turning an unused limiter into a heartbeat.
			if DidWork or self.QueueHead <= self.QueueTail then
				task.wait()
			else
				task.wait(math.min(self.Burst.Time, 0.05))
			end
		end

		if wax.shared.Unloaded and not self.IsDestroyed and self.OnUnload then
			pcall(self.OnUnload)
		end
	end)

	if not self.PeriodicInterval then
		return
	end

	self.PeriodicThread = task.spawn(function()
		while not wax.shared.Unloaded and not self.IsDestroyed do
			self:QueueOperation()
			task.wait(self.PeriodicInterval)
		end
	end)
end

function Ratelimiter:Destroy()
	if self.IsDestroyed then
		return
	end

	self.IsDestroyed = true

	if self.ManagerThread then
		pcall(task.cancel, self.ManagerThread)
		self.ManagerThread = nil
	end

	if self.PeriodicThread then
		pcall(task.cancel, self.PeriodicThread)
		self.PeriodicThread = nil
	end

	table.clear(self.Bucket)
	table.clear(self.Queue)
	self.QueueHead = 1
	self.QueueTail = 0
end

Ratelimiter.Stop = Ratelimiter.Destroy

return Ratelimiter
