-- A deterministic stand-in for the guild addon channel: many clients, one
-- virtual clock, broadcast with latency and optional loss, the server's
-- per-sender throttle, lockdown windows and persisted SavedVariables.
local Sim = {}
Sim.__index = Sim

local STEP = 0.05 -- seconds of virtual time per step
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

function Sim.New(ns, seed, opts)
	opts = opts or {}
	local self = setmetatable({}, Sim)
	self.ns = ns
	self.seed = seed or 1
	self.step, self.t = 0, 0
	self.epoch = opts.epoch or 1795252375
	self.loss = opts.loss or 0
	self.slots = {}
	self.clients, self.byName, self.officers = {}, {}, {}
	self:ResetCounters()
	return self
end

function Sim:ResetCounters()
	self.frames = { H = 0, U = 0, total = 0 }
	self.throttled = 0
	self.maxFrame = 0
	for _, c in ipairs(self.clients or {}) do c.sent = 0 end
end

--- Uniform float in [a, b), or [0, 1) without arguments. Own generator so a
--- seed gives the same run on every machine.
function Sim:Rand(a, b)
	self.seed = (self.seed * 1103515245 + 12345) % 2147483648
	local u = self.seed / 2147483648
	if a then return a + (b - a) * u end
	return u
end

function Sim:Time()
	return floor(self.epoch + self.t)
end

function Sim:At(time, fn)
	local idx = max(self.step + 1, ceil(time / STEP))
	local slot = self.slots[idx]
	if not slot then
		slot = {}
		self.slots[idx] = slot
	end
	slot[#slot + 1] = fn
end

--- opts: officer, skew (clock offset in seconds), online = false, data
function Sim:AddClient(name, opts)
	opts = opts or {}
	local c = { name = name, data = opts.data or {}, skew = opts.skew or 0, online = false, locked = false,
		srvTokens = 10, srvAt = 0, sent = 0, rosterReady = true }
	self.clients[#self.clients + 1] = c
	self.byName[name] = c
	if opts.officer then self.officers[self.ns.Util.Fold(name)] = true end
	if opts.online ~= false then self:Login(c) end
	return c
end

function Sim:Login(c)
	local sim, ns = self, self.ns
	c.online = true
	c.store = ns.Store.New(c.data, sim:Time() + c.skew)
	c.env = {
		now = function() return sim.t end,
		time = function() return sim:Time() + c.skew end,
		random = function(a, b) return sim:Rand(a, b) end,
		canSend = function() return c.online and not c.locked end,
		send = function(_, text) return sim:Send(c, text) end,
		me = c.name,
		roster = {
			Ready = function() return c.rosterReady end,
			IsOfficer = function(key) return sim.officers[key] or false end,
		},
	}
	c.sync = ns.Sync.New(c.store, c.env)
	c.sync:Start()
end

--- Log out (or crash): everything in memory is gone, c.data survives.
function Sim:Logout(c)
	c.online = false
	c.sync, c.store, c.env = nil, nil, nil
end

function Sim:Send(c, text)
	assert(#text <= 255, "frame over 255 bytes: " .. #text)
	if not c.online or c.locked then return false end
	c.srvTokens = min(10, c.srvTokens + (self.t - c.srvAt))
	c.srvAt = self.t
	if c.srvTokens < 1 then
		-- The real server answers AddonMessageThrottle and drops the message.
		self.throttled = self.throttled + 1
		c.sync:OnThrottled()
		return true
	end
	c.srvTokens = c.srvTokens - 1
	c.sent = c.sent + 1
	local kind = text:sub(1, 1)
	self.frames[kind] = (self.frames[kind] or 0) + 1
	self.frames.total = self.frames.total + 1
	if #text > self.maxFrame then self.maxFrame = #text end
	for _, target in ipairs(self.clients) do
		local lost = target ~= c and self.loss > 0 and self:Rand() < self.loss
		if not lost then
			self:At(self.t + self:Rand(0.05, 0.4), function()
				if target.online and not target.locked and target.sync then
					target.sync:OnFrame(c.name, text)
				end
			end)
		end
	end
	return true
end

--- Put raw text on the channel as if `name` had sent it (hostile clients).
function Sim:Inject(name, text)
	for _, target in ipairs(self.clients) do
		if target.online and not target.locked and target.sync and target.name ~= name then
			target.sync:OnFrame(name, text)
		end
	end
end

function Sim:Run(seconds)
	local stopAt = self.step + floor(seconds / STEP + 0.5)
	while self.step < stopAt do
		self.step = self.step + 1
		self.t = self.step * STEP
		local slot = self.slots[self.step]
		if slot then
			self.slots[self.step] = nil
			for i = 1, #slot do slot[i]() end
		end
		if self.step % 10 == 0 then
			for _, c in ipairs(self.clients) do
				if c.online and c.sync then c.sync:Tick() end
			end
		end
	end
end

--- Run until every listed client holds the same synced set, or time is up.
--- Returns the virtual seconds it took, or nil.
function Sim:RunUntilConverged(maxSeconds, clients)
	local started = self.t
	while self.t - started < maxSeconds do
		self:Run(1)
		if self:Converged(clients) then return self.t - started end
	end
	return nil
end

--- True when all listed (default: all online, unlocked) clients hold a
--- byte-identical synced set.
function Sim:Converged(clients)
	local reference
	for _, c in ipairs(clients or self.clients) do
		if c.online and c.store and (clients or not c.locked) then
			local dump = c.store:Dump()
			if reference == nil then
				reference = dump
			elseif dump ~= reference then
				return false
			end
		end
	end
	return true, reference
end

--- Deep copy of a persisted table, to seed several clients with one state.
function Sim.Clone(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = Sim.Clone(v) end
	return c
end

return Sim
