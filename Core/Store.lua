-- The guild's Kill on Sight state for one guild, plus the bookkeeping that
-- makes it syncable: versions, tombstones, a graveyard and bucket digests.
--
-- Three kinds of data:
--   reports  one per (subject, author): "author wants subject dead, because".
--            Subjects are players (kind "r") or whole guilds (kind "g").
--   facts    one per listed player: GUID, class, race, level, guild (kind "f").
--   scores   one per (listed player, author): how often the author killed
--            them and was killed by them (kind "c"). Only the author writes it.
--   members  one per guildmate: their own totals and achievements (kind "m").
--   tiers    the guild's rank ladder as officers changed it (kind "t").
--   bounties one per (target, poster), on a player or a guild (kind "b"),
--            and one claim tally per (bounty, claimer) while it is up ("k").
--            A bounty with gold goes to the first kill only; the poster then
--            owes the winner that gold, and the marks on that debt (sent,
--            received, settled) are kind "d".
--   seen     last sighting per player. Local and best-effort, never versioned.
--
-- Pure Lua: no WoW API, so the whole thing runs in the offline tests.
local _, ns = ...

local Util, Codec = ns.Util, ns.Codec
local Fold = Util.Fold
local byte, floor, min, sort = string.byte, math.floor, math.min, table.sort

local Store = {}
Store.__index = Store
ns.Store = Store

local NB = Codec.BUCKETS
local MOD32 = 4294967296
local DMOD = Codec.DIGEST_MOD

Store.TOMB_DAYS = 180 -- removals stay in the synced set this long
Store.FUTURE = 120 -- seconds a timestamp may be ahead of our clock
Store.LOG_MAX = 300
Store.MEMBER_DAYS = 365 -- a guildmate's totals leave the set after a year of silence
Store.DEBT_SECONDS = 48 * 3600 -- how long the poster of a won gold bounty has to pay

-- Kinds whose changes go in the log, and that are removed with tombstones.
local LOGGED = { r = true, g = true, b = true, t = true, d = true }
local TOMBED = { r = true, g = true, b = true }

local function day(t)
	return floor(t / 86400)
end

-- Bytewise string order. Lua's "<" uses the C locale's collation, which is
-- not guaranteed to be the same on every client.
local function cmpBytes(a, b)
	local n = min(#a, #b)
	for i = 1, n do
		local x, y = byte(a, i), byte(b, i)
		if x ~= y then return x > y and 1 or -1 end
	end
	if #a ~= #b then return #a > #b and 1 or -1 end
	return 0
end

--- Total order on versions of the same record: >0 when `a` wins.
local function cmp(a, b)
	if a.ts ~= b.ts then return a.ts > b.ts and 1 or -1 end
	local c = cmpBytes(a.mby, b.mby)
	if c ~= 0 then return c end
	if a.hash ~= b.hash then return a.hash > b.hash and 1 or -1 end
	return 0
end
Store.Compare = cmp

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

--- Bind a store to its persisted table (created empty on first use).
function Store.New(data, now)
	local self = setmetatable({}, Store)
	data.recs = data.recs or {}
	data.grave = data.grave or {}
	data.seen = data.seen or {}
	data.dirty = data.dirty or {}
	data.log = data.log or {}
	self.data = data
	self.listeners = {}

	self.recs, self.grave = {}, {}
	self.bucketOf, self.inSet, self.bset, self.sum = {}, {}, {}, {}
	self.live, self.any, self.glive, self.gidx = {}, {}, {}, {}
	self.scores = {} -- player key -> { [id] = true } for kind "c"
	self.claims = {} -- bounty id -> { [id] = true } for its claims ("k") and debt marks ("d")
	self.blive = {} -- scope .. target key -> number of live bounties
	self.count = 0
	for b = 0, NB - 1 do
		self.bset[b] = {}
		self.sum[b] = 0
	end

	-- Persisted form is the canonical text; anything that no longer parses
	-- (corrupt file, older format) is dropped.
	local loaded = {}
	for id, wire in pairs(data.recs) do
		local rec = type(wire) == "string" and Codec.DecodeRecord(wire)
		if rec and rec.id == id then
			loaded[#loaded + 1] = rec
		else
			data.recs[id] = nil
			data.dirty[id] = nil
		end
	end
	-- Reports first, so facts and scores see the right "has a live report"
	-- state.
	local function dependent(rec) return rec.k == "f" or rec.k == "c" or rec.k == "k" or rec.k == "d" end
	sort(loaded, function(a, b)
		if dependent(a) ~= dependent(b) then return dependent(b) end
		return a.id < b.id
	end)
	for i = 1, #loaded do
		self:_attach(loaded[i], now)
	end
	for id, wire in pairs(data.grave) do
		local rec = type(wire) == "string" and Codec.DecodeRecord(wire)
		if rec and rec.id == id and rec.del then
			self.grave[id] = rec
		else
			data.grave[id] = nil
		end
	end
	for id in pairs(data.dirty) do
		if not self.recs[id] then data.dirty[id] = nil end
	end
	self:Age(now)
	return self
end

---------------------------------------------------------------------------
-- Internal bookkeeping
---------------------------------------------------------------------------

-- A claim (or a debt mark) belongs to one posting of its bounty: it counts
-- while that bounty is up, and only if it was made after the bounty was (last)
-- posted. Claims from before a take-down do not come back when the bounty is
-- posted again.
function Store:_claimCounts(rec)
	local bounty = self.recs[rec.bid]
	return bounty ~= nil and not bounty.del and rec.ts >= bounty.at
end

function Store:_wantInSet(rec, now)
	if rec.k == "f" or rec.k == "c" then return (self.live[rec.key] or 0) > 0 end
	if rec.k == "k" or rec.k == "d" then return self:_claimCounts(rec) end
	if rec.k == "m" then return day(now) - day(rec.ts) < Store.MEMBER_DAYS end
	if rec.del then return day(now) - day(rec.ts) < Store.TOMB_DAYS end
	return true
end

function Store:_setMember(rec, want)
	local id = rec.id
	local has = self.inSet[id] or false
	if has == want then return end
	local b = self.bucketOf[id]
	self.root = nil -- cached root is stale
	if want then
		self.sum[b] = (self.sum[b] + rec.hash) % MOD32
		self.count = self.count + 1
		self.inSet[id] = true
	else
		self.sum[b] = (self.sum[b] - rec.hash) % MOD32
		self.count = self.count - 1
		self.inSet[id] = nil
	end
end

-- Facts and scores travel only while their player is listed.
function Store:_refreshFacts(key, now)
	local facts = self.recs["f:" .. key]
	if facts then self:_setMember(facts, self:_wantInSet(facts, now)) end
	local scores = self.scores[key]
	if scores then
		for id in pairs(scores) do
			local rec = self.recs[id]
			self:_setMember(rec, self:_wantInSet(rec, now))
		end
	end
end

-- Claims travel only while their bounty is up.
function Store:_refreshClaims(bid, now)
	local set = self.claims[bid]
	if not set then return end
	for id in pairs(set) do
		local rec = self.recs[id]
		self:_setMember(rec, self:_wantInSet(rec, now))
	end
end

local function index(t, key, id, add)
	local set = t[key]
	if add then
		if not set then
			set = {}
			t[key] = set
		end
		set[id] = true
	elseif set then
		set[id] = nil
		if next(set) == nil then t[key] = nil end
	end
end

local function bump(t, key, delta)
	local v = (t[key] or 0) + delta
	t[key] = v > 0 and v or nil
end

function Store:_attach(rec, now)
	local id = rec.id
	self.recs[id] = rec
	self.data.recs[id] = rec.wire
	local b = Codec.Bucket(id)
	self.bucketOf[id] = b
	self.bset[b][id] = true
	if rec.k == "r" then
		bump(self.any, rec.key, 1)
		if not rec.del then bump(self.live, rec.key, 1) end
	elseif rec.k == "g" then
		if not rec.del then bump(self.glive, rec.key, 1) end
	elseif rec.k == "c" then
		index(self.scores, rec.key, id, true)
	elseif rec.k == "k" or rec.k == "d" then
		index(self.claims, rec.bid, id, true)
	elseif rec.k == "b" then
		if not rec.del then bump(self.blive, rec.scope .. rec.key, 1) end
	elseif rec.k == "f" and rec.guid then
		self.gidx[rec.guid] = rec.key
	end
	self:_setMember(rec, self:_wantInSet(rec, now))
	if rec.k == "r" then self:_refreshFacts(rec.key, now) end
	if rec.k == "b" then self:_refreshClaims(id, now) end
end

function Store:_detach(id, now)
	local rec = self.recs[id]
	if not rec then return nil end
	self:_setMember(rec, false)
	if rec.k == "r" then
		bump(self.any, rec.key, -1)
		if not rec.del then bump(self.live, rec.key, -1) end
	elseif rec.k == "g" then
		if not rec.del then bump(self.glive, rec.key, -1) end
	elseif rec.k == "c" then
		index(self.scores, rec.key, id, false)
	elseif rec.k == "k" or rec.k == "d" then
		index(self.claims, rec.bid, id, false)
	elseif rec.k == "b" then
		if not rec.del then bump(self.blive, rec.scope .. rec.key, -1) end
	elseif rec.k == "f" and rec.guid and self.gidx[rec.guid] == rec.key then
		self.gidx[rec.guid] = nil
	end
	self.bset[self.bucketOf[id]][id] = nil
	self.bucketOf[id] = nil
	self.recs[id] = nil
	self.data.recs[id] = nil
	if rec.k == "r" then self:_refreshFacts(rec.key, now) end
	if rec.k == "b" then self:_refreshClaims(id, now) end
	return rec
end

function Store:_bury(rec)
	self.grave[rec.id] = rec
	self.data.grave[rec.id] = rec.wire
end

function Store:_unbury(id)
	self.grave[id] = nil
	self.data.grave[id] = nil
end

function Store:_fire(id, rec, old)
	for i = 1, #self.listeners do
		self.listeners[i](id, rec, old)
	end
end

function Store:_log(now, action, rec, old, via)
	local log = self.data.log
	log[#log + 1] = {
		t = now, a = action, id = rec.id, by = rec.mby, via = via,
		prev = old and old.wire or nil,
	}
	while #log > Store.LOG_MAX do
		table.remove(log, 1)
	end
end

---------------------------------------------------------------------------
-- Change notification
---------------------------------------------------------------------------

--- Call fn(id, rec, old) after every change. rec is nil when a record left.
function Store:OnChange(fn)
	self.listeners[#self.listeners + 1] = fn
end

---------------------------------------------------------------------------
-- Sync surface
---------------------------------------------------------------------------

function Store:Get(id)
	return self.recs[id]
end

--- Transmitted (18-bit) digest of one bucket.
function Store:Digest(b)
	return self.sum[b] % DMOD
end

function Store:Digests()
	local d = {}
	for b = 0, NB - 1 do d[b] = self.sum[b] % DMOD end
	return d
end

function Store:Root()
	local root = self.root
	if not root then
		root = Codec.Root(self:Digests())
		self.root = root
	end
	return root
end

--- Number of records in the synced set.
function Store:Count()
	return self.count
end

--- Ids in bucket b that belong to the synced set.
function Store:BucketIds(b)
	local ids = {}
	for id in pairs(self.bset[b]) do
		if self.inSet[id] then ids[#ids + 1] = id end
	end
	return ids
end

function Store:InSet(id)
	return self.inSet[id] or false
end

--- The buried tombstone for an id, if any (used to rebut zombies).
function Store:Grave(id)
	return self.grave[id]
end

--- Merge a record received from the guild. Never checks permissions; that is
--- a separate gate on direct edits (see Permissions), which keeps the merge
--- commutative. Returns one of:
---   "new" "replaced"  stored
---   "same" "older"    we already hold this or something newer
---   "future"          timestamp ahead of our clock, refused
---   "grave"           a removal we had already buried
---   "buried"          a removal too old for the synced set, kept locally
---   "rebut"           a zombie: we hold a buried removal that beats it
function Store:Merge(rec, now, via)
	if rec.ts > now + Store.FUTURE then return "future" end
	local id = rec.id
	local buried = self.grave[id]
	if buried then
		local c = cmp(rec, buried)
		if rec.del then
			if c > 0 then self:_bury(rec) end
			return "grave"
		end
		if c <= 0 then return "rebut" end
		self:_unbury(id) -- a genuine re-add, newer than the old removal
	end

	local mine = self.recs[id]
	if mine then
		local c = cmp(rec, mine)
		if c == 0 then return "same" end
		if c < 0 then return "older" end
	end

	if rec.del and day(now) - day(rec.ts) >= Store.TOMB_DAYS then
		if mine then self:_detach(id, now) end
		self:_bury(rec)
		self.data.dirty[id] = nil
		if mine then self:_fire(id, nil, mine) end
		return "buried"
	end

	if mine then self:_detach(id, now) end
	self:_attach(rec, now)
	self.data.dirty[id] = nil
	if LOGGED[rec.k] then
		self:_log(now, rec.del and "remove" or (mine and not mine.del and "edit" or "add"), rec, mine, via)
	end
	self:_fire(id, rec, mine)
	return mine and "replaced" or "new"
end

--- Move removals past their sync lifetime to the graveyard and drop facts
--- for players nobody has a report on any more. Cut on server-day
--- boundaries so every client makes the same decision at the same time.
function Store:Age(now)
	local old = {}
	for id, rec in pairs(self.recs) do
		if TOMBED[rec.k] and rec.del and day(now) - day(rec.ts) >= Store.TOMB_DAYS then
			old[#old + 1] = id
		end
	end
	for i = 1, #old do
		local rec = self:_detach(old[i], now)
		self:_bury(rec)
		self.data.dirty[old[i]] = nil
	end
	local orphans = {}
	for id, rec in pairs(self.recs) do
		if (rec.k == "f" or rec.k == "c") and not self.any[rec.key] then
			orphans[#orphans + 1] = id
		elseif (rec.k == "k" or rec.k == "d")
			and (not self.recs[rec.bid] or (not self.recs[rec.bid].del and not self:_claimCounts(rec))) then
			orphans[#orphans + 1] = id -- its bounty is gone for good, or was posted anew since
		elseif rec.k == "m" and day(now) - day(rec.ts) >= Store.MEMBER_DAYS then
			orphans[#orphans + 1] = id
		end
	end
	for i = 1, #orphans do
		self:_detach(orphans[i], now)
		self.data.dirty[orphans[i]] = nil
	end
	for key in pairs(self.data.seen) do
		if not self.any[key] then self.data.seen[key] = nil end
	end
	-- Membership of the remaining removals can only change on a day boundary,
	-- which the loop above already handled.
end

---------------------------------------------------------------------------
-- Dirty flags: local edits not yet confirmed as broadcast
---------------------------------------------------------------------------

function Store:MarkDirty(id)
	self.data.dirty[id] = true
end

function Store:ClearDirty(id)
	self.data.dirty[id] = nil
end

function Store:IsDirty(id)
	return self.data.dirty[id] or false
end

function Store:DirtyIds()
	local ids = {}
	for id in pairs(self.data.dirty) do
		if self.recs[id] then ids[#ids + 1] = id else self.data.dirty[id] = nil end
	end
	sort(ids)
	return ids
end

---------------------------------------------------------------------------
-- Local edits
---------------------------------------------------------------------------

function Store:_nextTs(id, now)
	local ts = now
	local mine, buried = self.recs[id], self.grave[id]
	if mine and mine.ts >= ts then ts = mine.ts + 1 end
	if buried and buried.ts >= ts then ts = buried.ts + 1 end
	return ts
end

function Store:_write(rec, now)
	local id = rec.id
	local old = self.recs[id]
	if self.grave[id] then self:_unbury(id) end
	if old then self:_detach(id, now) end
	self:_attach(rec, now)
	self.data.dirty[id] = true
	if LOGGED[rec.k] then
		self:_log(now, rec.del and "remove" or (old and not old.del and "edit" or "add"), rec, old, nil)
	end
	self:_fire(id, rec, old)
	return rec
end

--- Add or update `author`'s report. kind is "r" (player) or "g" (guild).
--- `editor` is who is writing it now: the author, or an officer editing.
function Store:Report(kind, name, reason, author, editor, now)
	editor = editor or author
	local id = Codec.Id(kind, Fold(name), Fold(author))
	local mine = self.recs[id]
	local live = mine and not mine.del and mine or nil
	return self:_write(Codec.Seal({
		k = kind, name = live and live.name or name, author = live and live.author or author,
		mby = editor, ts = self:_nextTs(id, now), at = live and live.at or now,
		reason = Codec.FitReason(kind, name, author, editor, reason),
	}), now)
end

--- Remove one report. Returns the tombstone, or nil if there was nothing live.
function Store:Remove(id, editor, now)
	local mine = self.recs[id]
	if not mine or mine.del or not TOMBED[mine.k] then return nil end
	return self:_write(Codec.Seal({
		k = mine.k, name = mine.name, author = mine.author, mby = editor, scope = mine.scope,
		ts = self:_nextTs(id, now), del = true,
	}), now)
end

local FACT_FIELDS = { "guid", "cur", "class", "race", "level", "guild" }

--- Record what was just observed about a listed player. Only fields that are
--- present in `seen` change; pass guild = false for "is in no guild".
--- Returns the new record, or nil when nothing changed.
function Store:SetFacts(key, seen, editor, now)
	if not self.live[key] then return nil end
	local id = "f:" .. key
	local mine = self.recs[id]
	local rec = { k = "f", key = key, mby = editor }
	local changed = false
	for i = 1, #FACT_FIELDS do
		local f = FACT_FIELDS[i]
		local old = mine and mine[f] or nil
		local new = seen[f]
		if new == nil then
			new = old
		elseif new == false then
			new = nil
		end
		if new ~= old then changed = true end
		rec[f] = new
	end
	if not changed then return nil end
	rec.ts = self:_nextTs(id, now)
	return self:_write(Codec.Seal(rec), now)
end

--- Write `author`'s score against a listed player. Returns the new record,
--- or nil when the player is not listed or nothing changed.
function Store:SetScore(key, author, kills, deaths, now)
	if not self.live[key] then return nil end
	local id = Codec.Id("c", key, Fold(author))
	local mine = self.recs[id]
	kills = math.min(math.max(floor(kills), 0), Codec.MAX_SCORE)
	deaths = math.min(math.max(floor(deaths), 0), Codec.MAX_SCORE)
	if mine and mine.kills == kills and mine.deaths == deaths then return nil end
	return self:_write(Codec.Seal({
		k = "c", key = key, author = author, ts = self:_nextTs(id, now), kills = kills, deaths = deaths,
	}), now)
end

--- The guild's combined score against a player: kills, deaths, and the
--- individual score records (one per guildmate who has fought them).
function Store:Score(key)
	local kills, deaths, list = 0, 0, {}
	local set = self.scores[key]
	if set then
		for id in pairs(set) do
			local rec = self.recs[id]
			kills, deaths = kills + rec.kills, deaths + rec.deaths
			list[#list + 1] = rec
		end
	end
	sort(list, function(a, b)
		local ta, tb = a.kills + a.deaths, b.kills + b.deaths
		if ta ~= tb then return ta > tb end
		return a.id < b.id
	end)
	return kills, deaths, list
end

---------------------------------------------------------------------------
-- Guildmates' totals and the rank ladder
---------------------------------------------------------------------------

local MEMBER_FIELDS = { "kills", "deaths", "best", "points", "ach" }

--- Write `author`'s own totals. t: { kills, deaths, best, points, ach }.
--- Returns the new record, or nil when nothing changed.
function Store:SetMember(author, t, now)
	local id = Codec.Id("m", Fold(author))
	local mine = self.recs[id]
	local rec = { k = "m", author = author }
	local changed = not mine
	for i = 1, #MEMBER_FIELDS do
		local f = MEMBER_FIELDS[i]
		local v = math.max(floor(t[f] or 0), 0)
		rec[f] = v
		if mine and mine[f] ~= v then changed = true end
	end
	if not changed then return nil end
	rec.ts = self:_nextTs(id, now)
	return self:_write(Codec.Seal(rec), now)
end

function Store:Member(key)
	local rec = self.recs[Codec.Id("m", key)]
	return rec
end

--- Every guildmate's totals record, unsorted.
function Store:Members()
	local list = {}
	for id, rec in pairs(self.recs) do
		if rec.k == "m" and self.inSet[id] then list[#list + 1] = rec end
	end
	return list
end

--- Set rank tier n (1..MAX_TIERS). An empty title switches the tier off.
function Store:SetTier(n, kills, title, editor, now)
	local id = Codec.Id("t", tostring(n))
	local mine = self.recs[id]
	kills = math.min(math.max(floor(kills), 0), Codec.MAX_SCORE)
	title = Util.Clean(title or "", Codec.MAX_TITLE)
	if mine and mine.kills == kills and mine.title == title then return nil end
	return self:_write(Codec.Seal({ k = "t", n = n, kills = kills, title = title, mby = editor,
		ts = self:_nextTs(id, now) }), now)
end

--- Tier records the officers have written, by tier number.
function Store:Tiers()
	local out = {}
	for n = 1, Codec.MAX_TIERS do
		out[n] = self.recs[Codec.Id("t", tostring(n))]
	end
	return out
end

---------------------------------------------------------------------------
-- Bounties
---------------------------------------------------------------------------

--- Post (or change) `author`'s bounty on a player (scope "p") or a guild
--- (scope "g"). `editor` is who writes it now: the author, or an officer.
--- `gold` (whole gold pieces, 0 for none) is what the poster promises the
--- first guildmate to land the killing blow.
function Store:PostBounty(scope, name, points, reward, author, editor, now, gold)
	editor = editor or author
	local id = Codec.BountyId(scope, Fold(name), Fold(author))
	local mine = self.recs[id]
	local live = mine and not mine.del and mine or nil
	points = math.min(math.max(floor(points or 1), 1), Codec.MAX_POINTS)
	gold = math.min(math.max(floor(gold or 0), 0), Codec.MAX_GOLD)
	-- Changing the gold makes it a new posting: kills from before do not win
	-- gold that was not on offer when they happened.
	local same = live and (live.gold or 0) == gold
	return self:_write(Codec.Seal({
		k = "b", scope = scope, name = live and live.name or name, author = live and live.author or author,
		mby = editor, ts = self:_nextTs(id, now), at = same and live.at or now, points = points, gold = gold,
		reward = Util.Clean(reward or "", Codec.MAX_REWARD),
	}), now)
end

--- Who won a gold bounty: the earliest claim on this posting. Returns the
--- claim record, or nil while it is still open (or has no gold).
function Store:Winner(bounty)
	if bounty.del or (bounty.gold or 0) == 0 then return nil end
	local set, best = self.claims[bounty.id], nil
	if set then
		for id in pairs(set) do
			local c = self.recs[id]
			if c.k == "k" and self:_claimCounts(c) then
				if not best or c.ts < best.ts or (c.ts == best.ts and cmpBytes(c.akey, best.akey) < 0) then best = c end
			end
		end
	end
	return best
end

--- Count one more claim by `claimer` on a live bounty. Returns the claim
--- record, or nil when the bounty is not up.
function Store:Claim(bid, claimer, now)
	local bounty = self.recs[bid]
	if not bounty or bounty.del then return nil end
	if self:Winner(bounty) then return nil end -- gold goes to the first kill, and that has been
	local id = Codec.ClaimId(bounty.scope, bounty.key, bounty.akey, Fold(claimer))
	local mine = self.recs[id]
	-- A tally from an earlier posting of this bounty starts again from zero.
	local before = mine and self:_claimCounts(mine) and mine.count or 0
	return self:_write(Codec.Seal({
		k = "k", scope = bounty.scope, key = bounty.key, poster = bounty.author, author = claimer,
		ts = math.max(self:_nextTs(id, now), bounty.at), count = math.min(before + 1, Codec.MAX_SCORE),
	}), now)
end

function Store:HasBounty(scope, key)
	return self.blive[scope .. key] ~= nil
end

--- Put a mark on the debt of a won gold bounty. role "s" (the poster: state
--- "s" sent), "w" (the winner: "r" received, "x" not received) or "o" (an
--- officer: "o" settled); state "n" takes the mark back. Returns the record,
--- or nil when the bounty is not up or nothing changes.
function Store:SetMark(bid, role, state, author, now)
	local bounty = self.recs[bid]
	if not bounty or bounty.del then return nil end
	local id = Codec.MarkId(bounty.scope, bounty.key, bounty.akey, role, Fold(author))
	local mine = self.recs[id]
	local current = mine and self:_claimCounts(mine) and mine.state or "n"
	if current == state then return nil end
	return self:_write(Codec.Seal({
		k = "d", scope = bounty.scope, key = bounty.key, poster = bounty.author, role = role, author = author,
		ts = math.max(self:_nextTs(id, now), bounty.at), state = state,
	}), now)
end

function Store:_mark(id)
	local rec = self.recs[id]
	return rec and self:_claimCounts(rec) and rec.state or nil
end

--- The debt on a won gold bounty, or nil when there is none:
--- { bounty, poster, pkey, winner, wkey, gold, at, due, state, open, late }.
--- state: "owed", "sent" (the poster says so; the clock stops), "disputed"
--- (the winner says it has not arrived), "paid" (the winner has it) or
--- "settled" (an officer closed it). late: unpaid past the deadline.
function Store:Debt(bounty, now)
	local claim = self:Winner(bounty)
	if not claim then return nil end
	local scope, key, pkey = bounty.scope, bounty.key, bounty.akey
	local winner = self:_mark(Codec.MarkId(scope, key, pkey, "w", claim.akey))
	local state = "owed"
	if self:_mark(Codec.MarkId(scope, key, pkey, "o")) == "o" then
		state = "settled"
	elseif winner == "r" then
		state = "paid"
	elseif winner == "x" then
		state = "disputed"
	elseif self:_mark(Codec.MarkId(scope, key, pkey, "s")) == "s" then
		state = "sent"
	end
	local due = claim.ts + Store.DEBT_SECONDS
	local unpaid = state == "owed" or state == "disputed"
	return {
		bounty = bounty, poster = bounty.author, pkey = pkey, winner = claim.author, wkey = claim.akey,
		gold = bounty.gold, at = claim.ts, due = due, state = state,
		open = unpaid or state == "sent", late = unpaid and now > due,
	}
end

--- Every debt on a live gold bounty, oldest first.
function Store:Debts(now)
	local list = {}
	for _, rec in pairs(self.recs) do
		if rec.k == "b" and not rec.del and (rec.gold or 0) > 0 then
			local debt = self:Debt(rec, now)
			if debt then list[#list + 1] = debt end
		end
	end
	sort(list, function(a, b)
		if a.at ~= b.at then return a.at < b.at end
		return a.bounty.id < b.bounty.id
	end)
	return list
end

--- Who is in disgrace right now: poster key -> their oldest overdue debt.
function Store:Dishonor(now)
	local out = {}
	local debts = self:Debts(now)
	for i = 1, #debts do
		local d = debts[i]
		if d.late and not out[d.pkey] then out[d.pkey] = d end
	end
	return out
end

--- A live bounty with its claims: { rec, claims = {claim records}, total,
--- winner (the winning claim of a gold bounty), debt (when `now` is given) }.
function Store:_bountyView(rec, now)
	local claims, total = {}, 0
	local set = self.claims[rec.id]
	if set then
		for id in pairs(set) do
			local c = self.recs[id]
			if c.k == "k" and self:_claimCounts(c) then
				claims[#claims + 1] = c
				total = total + c.count
			end
		end
	end
	sort(claims, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.id < b.id
	end)
	return { rec = rec, key = rec.id, claims = claims, total = total, winner = self:Winner(rec),
		debt = now and self:Debt(rec, now) or nil }
end

--- Live bounties, optionally only those on one target (scope and key). Pass
--- `now` to have each one's debt worked out as well.
function Store:Bounties(scope, key, now)
	local list = {}
	for _, rec in pairs(self.recs) do
		if rec.k == "b" and not rec.del and (not scope or (rec.scope == scope and rec.key == key)) then
			list[#list + 1] = self:_bountyView(rec, now)
		end
	end
	sort(list, function(a, b)
		if a.rec.points ~= b.rec.points then return a.rec.points > b.rec.points end
		return a.key < b.key
	end)
	return list
end

---------------------------------------------------------------------------
-- Sightings
---------------------------------------------------------------------------

--- Remember the most recent sighting of a listed player. Returns true when
--- it was newer than what we had.
function Store:SetSeen(key, s)
	if not self.any[key] then return false end
	local cur = self.data.seen[key]
	if cur and cur.at >= s.at then return false end
	self.data.seen[key] = { at = s.at, map = s.map, x = s.x, y = s.y, by = s.by }
	self:_fire("seen:" .. key, nil, nil)
	return true
end

function Store:GetSeen(key)
	return self.data.seen[key]
end

---------------------------------------------------------------------------
-- Queries for the game-facing code
---------------------------------------------------------------------------

--- True when at least one guildmate has a live report on this player key.
function Store:IsListed(key)
	return self.live[key] ~= nil
end

function Store:IsGuildListed(guildName)
	return self.glive[Fold(guildName)] ~= nil
end

--- Key of the listed player known to have this GUID (follows renames).
function Store:KeyForGuid(guid)
	local key = self.gidx[guid]
	if key and self.live[key] then return key end
	return nil
end

local function byAge(a, b)
	if a.at ~= b.at then return a.at < b.at end
	return a.id < b.id
end

function Store:_finish(subject)
	sort(subject.reports, byAge)
	subject.name = subject.reports[1].name
	if subject.kind == "r" then
		subject.facts = self.recs["f:" .. subject.key]
		subject.seen = self.data.seen[subject.key]
		subject.kills, subject.deaths = self:Score(subject.key)
		if subject.facts and subject.facts.cur then subject.name = subject.facts.cur end
	end
	return subject
end

function Store:_subject(kind, key)
	local live = kind == "r" and self.live or self.glive
	if not live[key] then return nil end
	local reports = {}
	for _, rec in pairs(self.recs) do
		if rec.k == kind and rec.key == key and not rec.del then
			reports[#reports + 1] = rec
		end
	end
	if #reports == 0 then return nil end
	return self:_finish({ key = key, kind = kind, reports = reports })
end

--- One listed player: { key, name, reports = {...}, facts, seen } or nil.
function Store:Player(key)
	return self:_subject("r", key)
end

function Store:Guild(key)
	return self:_subject("g", key)
end

function Store:_subjects(kind)
	local byKey, list = {}, {}
	for _, rec in pairs(self.recs) do
		if rec.k == kind and not rec.del then
			local subject = byKey[rec.key]
			if not subject then
				subject = { key = rec.key, kind = kind, reports = {} }
				byKey[rec.key] = subject
				list[#list + 1] = subject
			end
			subject.reports[#subject.reports + 1] = rec
		end
	end
	for i = 1, #list do
		self:_finish(list[i])
	end
	return list
end

--- All listed players, unsorted.
function Store:Players()
	return self:_subjects("r")
end

function Store:Guilds()
	return self:_subjects("g")
end

function Store:Counts()
	local players, guilds = 0, 0
	for _ in pairs(self.live) do players = players + 1 end
	for _ in pairs(self.glive) do guilds = guilds + 1 end
	return players, guilds
end

--- Canonical dump of the synced set, for tests and debugging.
function Store:Dump()
	local lines = {}
	for id, rec in pairs(self.recs) do
		if self.inSet[id] then lines[#lines + 1] = rec.wire end
	end
	sort(lines)
	return table.concat(lines, "\n")
end
