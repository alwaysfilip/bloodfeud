-- Keeps every guild member's Store converging on the same state using only
-- the guild addon channel: broadcast-only, 255 bytes per message, throttled,
-- no delivery to offline or locked-out (instanced) members.
--
-- Two frame types do all the work:
--   H  "here are my 64 bucket digests". Anyone whose digest for a bucket
--      differs pushes the records they hold in that bucket.
--   U  records from one bucket, plus the sender's digest for that bucket.
--      Listeners merge, then compare digests: if they still differ they hold
--      something the sender lacks, and push that back.
-- Every frame is built at send time from a set of pending record ids, so a
-- record somebody else just broadcast is simply skipped (no duplicate storms).
--
-- No WoW API here: time, randomness, sending and the roster come in through
-- `env`, which is what lets the multi-client simulation drive this file.
local _, ns = ...

local Util, Codec, Permissions, Store = ns.Util, ns.Codec, ns.Permissions, ns.Store
local Fold, cmp = Util.Fold, Store.Compare
local min, max, huge = math.min, math.max, math.huge

local Sync = {}
Sync.__index = Sync
ns.Sync = Sync

local NB = Codec.BUCKETS

Sync.BURST = 10 -- server allowance per prefix: 10 messages...
Sync.RATE = 1 -- ...refilling one per second
Sync.RESERVE = 2 -- tokens kept back for the player's own edits
Sync.HEARD_TTL = 8 -- must stay below the shortest hello delay
Sync.HEARD_KEEP = 180 -- how long we remember what was said, for push-backs
Sync.HELLO_LOGIN = { 10, 30 }
Sync.HELLO_UNLOCK = { 5, 20 }
Sync.HELLO_PERIOD = { 600, 900 }
Sync.HELLO_MIN_GAP = 120
Sync.UNLOCK_STABLE = 5
Sync.QUIET = 10
Sync.SUSPECT_FIRST = 15
Sync.SUSPECT_MAX = 600
Sync.STANDOFF_FIRST = 15
Sync.STANDOFF_MAX = 3600
Sync.STANDOFF_MEMORY = 1800 -- a repeat within this long counts as the same stand-off
Sync.DIRTY_RETRY = 8
Sync.DIRTY_TRIES = 3
Sync.PEER_TTL = 1200
Sync.DEFER_TTL = 60
Sync.AGE_EVERY = 600

--- env: { now(), time(), random(a, b), send(channel, text) -> bool,
---        canSend() -> bool, me = "Name", roster = { Ready(), IsOfficer(key) } }
function Sync.New(store, env)
	local self = setmetatable({}, Sync)
	self.store, self.env = store, env
	self.meKey = Fold(env.me)
	self.tokens = Sync.BURST
	self.refillAt = env.now()
	self.pending = {} -- id -> time it becomes due
	self.rebut = {} -- id -> buried removal to send instead of our own version
	self.heard = {} -- id -> { ts, mby, hash, at }: newest version on the air
	self.standoff = {} -- bucket -> { ["sender:digest"] = { mine, delay, next, last } }
	self.back = {} -- bucket -> { at, since, digest, sender }: push-back to evaluate
	self.lastDay = nil
	self.peers = {} -- folded name -> last heard
	self.dirtySent = {} -- id -> { at, n }
	self.deferred = {} -- direct edits waiting for the roster
	self.helloAt = nil
	self.lastHello = nil
	self.suspect = false
	self.suspectDelay = Sync.SUSPECT_FIRST
	self.suspectNext = 0
	self.lastHeard = -huge
	self.locked = false
	self.unlockAt = nil
	self.nextDue = huge
	self.nextExpire = 0
	self.nextAge = env.now() + Sync.AGE_EVERY
	self.started = false
	self.stats = { H = 0, U = 0, denied = 0, bad = 0 }
	return self
end

--- Begin syncing: announce our state shortly after login.
function Sync:Start()
	self.started = true
	local r = Sync.HELLO_LOGIN
	self:ScheduleHello(self.env.now() + self.env.random(r[1], r[2]))
end

function Sync:ScheduleHello(at, replace)
	if replace or not self.helloAt or at < self.helloAt then
		self.helloAt = at
	end
end

function Sync:PeerCount()
	local n = 0
	for key in pairs(self.peers) do
		if key ~= self.meKey then n = n + 1 end
	end
	return n
end

--- Something changed on our side: any stand-off bookkeeping is stale.
function Sync:Progress()
	self.suspectDelay = Sync.SUSPECT_FIRST
	self.suspectNext = 0
end

---------------------------------------------------------------------------
-- Suppression: what has already been said on the channel
---------------------------------------------------------------------------

function Sync:MarkHeard(rec, now)
	local h = self.heard[rec.id]
	if not h or cmp(rec, h) >= 0 then
		self.heard[rec.id] = { ts = rec.ts, mby = rec.mby, hash = rec.hash, at = now }
	end
end

-- The version we would send for an id: a rebuttal if one is queued, else ours.
function Sync:Outgoing(id)
	local rebut = self.rebut[id]
	if rebut then return rebut end
	if self.store:InSet(id) then return self.store:Get(id) end
	return nil
end

-- True when sending `id` would tell the channel nothing new: the version we
-- would send was broadcast within the last `window` seconds. The default
-- window is short on purpose, because a member who just came online has not
-- heard anything older than their own login.
function Sync:Covered(id, now, window)
	local out = self:Outgoing(id)
	if not out then return true end
	local h = self.heard[id]
	if not h or now - h.at > (window or Sync.HEARD_TTL) then return false end
	return cmp(h, out) >= 0
end

---------------------------------------------------------------------------
-- Scheduling pushes
---------------------------------------------------------------------------

--- Queue our records of bucket `b` because `senderKey`'s digest for it
--- (`foreign`) differs from ours. The same member repeating the same
--- disagreement backs off, so one permanently divergent client cannot make
--- the guild chatter forever. It is keyed per sender on purpose: many fresh
--- clients share the same (empty) digest and each of them must be served.
function Sync:SchedulePush(b, senderKey, foreign, at, now, window)
	local mine = self.store:Digest(b)
	local perBucket = self.standoff[b]
	if not perBucket then
		perBucket = {}
		self.standoff[b] = perBucket
	end
	local key = senderKey .. ":" .. foreign
	local e = perBucket[key]
	if e and e.mine == mine and now - e.last <= max(2 * e.delay, Sync.STANDOFF_MEMORY) then
		e.last = now
		if now < e.next then return false end
		e.delay = min(e.delay * 2, Sync.STANDOFF_MAX)
		e.next = now + e.delay
	else
		perBucket[key] = { mine = mine, delay = Sync.STANDOFF_FIRST, next = now + Sync.STANDOFF_FIRST, last = now }
	end

	local ids = self.store:BucketIds(b)
	for i = 1, #ids do
		local id = ids[i]
		if not self:Covered(id, now, window) then
			local cur = self.pending[id]
			self.pending[id] = cur and min(cur, at) or at
		end
	end
	if at < self.nextDue then self.nextDue = at end
	return true
end

-- A member pushed a bucket and their digest still differed from ours. Once
-- their push has gone quiet, send back whatever we hold that was not part of
-- the exchange. Deciding only then is what stops a client that is merely
-- catching up from echoing everything it has just been given.
function Sync:EvaluateBack(now)
	for b, back in pairs(self.back) do
		if back.at <= now then
			self.back[b] = nil
			if self.store:Digest(b) ~= back.digest then
				self:SchedulePush(b, back.sender, back.digest, now, now, now - back.since + 1)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- One update frame for bucket b: `firstId` (if any) plus every due pending
-- record of that bucket that still fits. Returns true when a frame went out.
function Sync:SendBucket(b, firstId, now)
	local ids, wires, n = {}, {}, 0
	if firstId then
		local out = self:Outgoing(firstId)
		if out then
			n = 1
			ids[1], wires[1] = firstId, out.wire
		end
	end
	local bucketOf = self.store.bucketOf
	for id, at in pairs(self.pending) do
		if at <= now and id ~= firstId then
			local idBucket = bucketOf[id] or Codec.Bucket(id)
			if idBucket == b then
				if self:Covered(id, now) then
					self.pending[id] = nil
					self.rebut[id] = nil
				else
					n = n + 1
					ids[n], wires[n] = id, self:Outgoing(id).wire
				end
			end
		end
	end
	if n == 0 then return false end

	local text, taken = Codec.EncodeUpdate(b, self.store:Digest(b), self.store:Root(), wires)
	if taken == 0 or not self.env.send("state", text) then return false end
	self.tokens = self.tokens - 1
	self.stats.U = self.stats.U + 1
	for i = 1, taken do
		local id = ids[i]
		local out = self:Outgoing(id)
		if out then self:MarkHeard(out, now) end
		self.pending[id] = nil
		self.rebut[id] = nil
	end
	return true
end

-- The player's own edits go first and are repeated until our echo comes back.
function Sync:SendDirty(now)
	local ids = self.store:DirtyIds()
	for i = 1, #ids do
		local id = ids[i]
		local sent = self.dirtySent[id]
		if not sent or now - sent.at >= Sync.DIRTY_RETRY then
			if sent and sent.n >= Sync.DIRTY_TRIES then
				-- No echo after several tries. Stop repeating; the periodic
				-- digest exchange still carries the record.
				self.store:ClearDirty(id)
				self.dirtySent[id] = nil
			elseif not self.store:InSet(id) then
				self.store:ClearDirty(id)
			else
				if not self:SendBucket(self.store.bucketOf[id], id, now) then return false end
				self.dirtySent[id] = { at = now, n = (sent and sent.n or 0) + 1 }
				return true
			end
		end
	end
	return false
end

function Sync:SendHello(now)
	local text = Codec.EncodeHello(self.store:Count(), self.store:Digests(), 0)
	if not self.env.send("state", text) then return false end
	self.tokens = self.tokens - 1
	self.stats.H = self.stats.H + 1
	self.lastHello = now
	local r = Sync.HELLO_PERIOD
	self.helloAt = now + self.env.random(r[1], r[2])
	return true
end

-- Push the due bucket that has waited longest.
function Sync:SendPending(now)
	if now < self.nextDue then return false end
	local bestAt, bestBucket = huge, nil
	local nextDue = huge
	local bucketOf = self.store.bucketOf
	for id, at in pairs(self.pending) do
		if at <= now then
			if self:Covered(id, now) then
				self.pending[id] = nil
				self.rebut[id] = nil
			elseif at < bestAt then
				bestAt, bestBucket = at, bucketOf[id] or Codec.Bucket(id)
			end
		elseif at < nextDue then
			nextDue = at
		end
	end
	if not bestBucket then
		self.nextDue = nextDue
		return false
	end
	self.nextDue = now -- more may be due; rescan on the next call
	return self:SendBucket(bestBucket, nil, now)
end

---------------------------------------------------------------------------
-- The clock: call a couple of times per second
---------------------------------------------------------------------------

function Sync:Expire(now)
	if now < self.nextExpire then return end
	self.nextExpire = now + 5
	for id, h in pairs(self.heard) do
		if now - h.at > Sync.HEARD_KEEP then self.heard[id] = nil end
	end
	for key, at in pairs(self.peers) do
		if now - at > Sync.PEER_TTL then self.peers[key] = nil end
	end
	for id, sent in pairs(self.dirtySent) do
		if not self.store:IsDirty(id) and now - sent.at > Sync.DIRTY_RETRY then self.dirtySent[id] = nil end
	end
	for b, perBucket in pairs(self.standoff) do
		for foreign, e in pairs(perBucket) do
			if now - e.last > 2 * Sync.STANDOFF_MAX then perBucket[foreign] = nil end
		end
		if next(perBucket) == nil then self.standoff[b] = nil end
	end
end

function Sync:FlushDeferred(now)
	if #self.deferred == 0 then return end
	local ready = self.env.roster.Ready()
	local keep = {}
	for i = 1, #self.deferred do
		local d = self.deferred[i]
		if ready then
			self:Apply(d.rec, d.sender, now)
		elseif now - d.at <= Sync.DEFER_TTL then
			keep[#keep + 1] = d
		end
	end
	self.deferred = keep
end

function Sync:Tick()
	if not self.started then return end
	local env = self.env
	local now = env.now()

	-- Removals leave the synced set on a server-day boundary; do it the moment
	-- the day changes so all clients switch together.
	local today = math.floor(env.time() / 86400)
	if now >= self.nextAge or today ~= self.lastDay then
		self.nextAge = now + Sync.AGE_EVERY
		self.lastDay = today
		self.store:Age(env.time())
	end
	self:Expire(now)
	self:FlushDeferred(now)

	if not env.canSend() then
		self.locked = true
		self.unlockAt = nil
		return
	end
	if self.locked then
		self.locked = false
		self.unlockAt = now
	end
	if self.unlockAt then
		-- Lockdown also flickers between encounter pulls: wait for it to settle.
		if now - self.unlockAt < Sync.UNLOCK_STABLE then return end
		self.unlockAt = nil
		if not self.lastHello or now - self.lastHello > Sync.HELLO_MIN_GAP then
			local r = Sync.HELLO_UNLOCK
			self:ScheduleHello(now + env.random(r[1], r[2]))
		end
	end

	self.tokens = min(Sync.BURST, self.tokens + (now - self.refillAt) * Sync.RATE)
	self.refillAt = now
	self:EvaluateBack(now)

	-- We saw evidence of disagreement that nobody has resolved: ask again.
	if self.suspect and now - self.lastHeard >= Sync.QUIET and now >= self.suspectNext then
		self.suspect = false
		self.suspectNext = now + self.suspectDelay
		self.suspectDelay = min(self.suspectDelay * 2, Sync.SUSPECT_MAX)
		-- Everyone who saw the same evidence reaches this point together;
		-- the jitter lets the first hello cancel the others.
		self:ScheduleHello(now + env.random(0.5, 4 + 0.25 * self:PeerCount()))
	end

	for _ = 1, Sync.BURST do
		if self.tokens < 1 then break end
		-- Our own edits first; everything else leaves a reserve for them.
		if not self:SendDirty(now) then
			if self.tokens < Sync.RESERVE + 1 then break end
			if self.helloAt and self.helloAt <= now then
				if not self:SendHello(now) then break end
			elseif not self:SendPending(now) then
				break
			end
		end
	end
end

--- The transport reported a throttle: stay silent for a few seconds.
function Sync:OnThrottled()
	self.tokens = 0
	self.refillAt = self.env.now() + 5
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

-- Gate a record on its writer's rights when the writer sent it personally,
-- then merge. Returns the merge result, "denied" or "deferred".
function Sync:Apply(rec, sender, now)
	local env = self.env
	local senderKey = Fold(sender)
	local direct = Fold(rec.mby) == senderKey
	if direct and rec.k ~= "f" then
		if Permissions.NeedsRoster(rec, senderKey) and not env.roster.Ready() then
			self.deferred[#self.deferred + 1] = { rec = rec, sender = sender, at = now }
			return "deferred"
		end
		if not Permissions.CanWrite(rec, senderKey, env.roster) then
			self.stats.denied = self.stats.denied + 1
			self.store:_log(env.time(), "denied", rec, nil, sender)
			if self.onDenied then self.onDenied(rec, sender) end
			return "denied"
		end
	end
	local res = self.store:Merge(rec, env.time(), sender)
	if res == "rebut" then
		-- A removal we buried long ago beats this: tell the sender.
		self.rebut[rec.id] = self.store:Grave(rec.id)
		local at = now + env.random(1, 3)
		self.pending[rec.id] = at
		if at < self.nextDue then self.nextDue = at end
	elseif res == "new" or res == "replaced" then
		self:Progress()
		if self.onApplied then self.onApplied(rec, sender, res, direct) end
	end
	return res
end

-- Somebody demonstrably holds exactly our state: no need to announce ours.
function Sync:Agreed(now)
	self.suspect = false
	self.back = {}
	self:Progress()
	self.store.data.agreedAt = self.env.time()
	local r = Sync.HELLO_PERIOD
	self:ScheduleHello(now + self.env.random(r[1], r[2]), true)
end

function Sync:OnHello(h, senderKey, now)
	local store, env = self.store, self.env
	store.data.lastSync = env.time()
	if h.root == store:Root() then
		self:Agreed(now)
		return
	end
	self.suspect = true
	local spread = 3 + 0.1 * self:PeerCount()
	for b = 0, NB - 1 do
		if h.digests[b] ~= store:Digest(b) then
			self:SchedulePush(b, senderKey, h.digests[b], now + env.random(1, spread), now)
		end
	end
end

function Sync:OnUpdate(u, sender, mine, now)
	local store = self.store
	for i = 1, #u.records do
		local rec = u.records[i]
		if mine then
			-- Our own frame came back: the edit is on the air.
			local cur = store:Get(rec.id)
			if cur and cmp(cur, rec) == 0 then
				store:ClearDirty(rec.id)
				self.dirtySent[rec.id] = nil
			end
		else
			self:Apply(rec, sender, now)
		end
		self:MarkHeard(rec, now)
		if self.pending[rec.id] and self:Covered(rec.id, now) then
			self.pending[rec.id] = nil
			self.rebut[rec.id] = nil
		end
	end
	self.stats.bad = self.stats.bad + u.bad
	if not mine then
		store.data.lastSync = self.env.time()
		if u.root == store:Root() then
			self:Agreed(now)
		elseif store:Digest(u.bucket) ~= u.digest then
			-- Different after merging. They may simply not be done sending;
			-- decide what to push back once their push has gone quiet.
			self.suspect = true
			local back = self.back[u.bucket]
			if not back then
				back = { since = now }
				self.back[u.bucket] = back
			end
			back.at = now + self.env.random(2, 4)
			back.digest = u.digest
			back.sender = Fold(sender)
		else
			-- This bucket matches but another one does not; a hello will find it.
			self.back[u.bucket] = nil
			self.suspect = true
		end
	end
end

--- Feed one received frame. `sender` is the server-stamped character name.
function Sync:OnFrame(sender, text)
	if not self.started then return end
	local now = self.env.now()
	local senderKey = Fold(sender)
	local mine = senderKey == self.meKey
	local kind = text:sub(1, 1)
	local frame
	if kind == "H" then
		frame = Codec.DecodeHello(text)
	elseif kind == "U" then
		frame = Codec.DecodeUpdate(text)
	end
	if not frame then
		self.stats.bad = self.stats.bad + 1
		return
	end
	-- Anyone sending these runs the addon, whatever version they are on.
	if not mine and self.onHeard then self.onHeard(sender, frame.proto) end
	if frame.proto ~= Codec.PROTO then
		if frame.proto > Codec.PROTO then self.newerSeen = true end
		return
	end
	if not mine then
		self.peers[senderKey] = now
		self.lastHeard = now
	end
	if kind == "H" then
		if not mine then self:OnHello(frame, senderKey, now) end
	else
		self:OnUpdate(frame, sender, mine, now)
	end
end
