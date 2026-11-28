-- Kills and deaths against enemy players, and the revenge prompt.
--
-- The combat log is closed to addons in Forever, but two narrower doors are
-- open in the outside world:
--   PARTY_KILL(attackerGUID, targetGUID)  a killing blow by us (or our pet)
--   C_DeathRecap.GetRecapEvents()         who hit us last before we died
-- Both are restricted in instances and battlegrounds, where this module is
-- off anyway.
--
-- Every fight is counted locally, per character, whoever the enemy is. For a
-- listed player the count is also published to the guild as a score record,
-- so the list can show the guild's combined score.
local _, ns = ...

local Util, Names, Codec = ns.Util, ns.Names, ns.Codec
local L = ns.L

local Feuds = { recent = {}, lastDeath = nil, events = {},
	-- What the client actually delivered, for /bm probe.
	stats = { kills = 0, killsSecret = 0, killsMine = 0, killsKnown = 0, deaths = 0, deathsKnown = 0 } }
ns.Feuds = Feuds

Feuds.RECENT_SECONDS = 15 * 60 -- how long an enemy we saw counts as "around"
Feuds.KEEP_DAYS = 120 -- forget local tallies of enemies not met for this long
Feuds.KEEP_MAX = 400
Feuds.RECAP_DELAY = 1 -- seconds after death before the recap is read

local function plain(value, kind)
	if value == nil or Util.IsSecret(value) then return nil end
	if kind and type(value) ~= kind then return nil end
	return value
end

---------------------------------------------------------------------------
-- Local tallies (per character, in the saved variables)
---------------------------------------------------------------------------

function Feuds:Book()
	local me = Names.Me()
	if not me or not ns.db then return nil end
	ns.db.fights = type(ns.db.fights) == "table" and ns.db.fights or {}
	local meKey = Names.Key(me)
	local book = ns.db.fights[meKey]
	if type(book) ~= "table" then
		book = {}
		ns.db.fights[meKey] = book
	end
	return book
end

--- My own tally against an enemy key: { n, k, d, t, r = {death times} }.
function Feuds:Entry(key, create)
	local book = self:Book()
	if not book then return nil end
	local e = book[key]
	if not e and create then
		e = { k = 0, d = 0, t = 0, r = {} }
		book[key] = e
	end
	return e
end

function Feuds:Prune(now)
	local book = self:Book()
	if not book then return end
	local cutoff = now - Feuds.KEEP_DAYS * 86400
	local keys = {}
	for key, e in pairs(book) do
		if type(e) ~= "table" or (e.t or 0) < cutoff then
			book[key] = nil
		else
			keys[#keys + 1] = key
		end
	end
	if #keys > Feuds.KEEP_MAX then
		table.sort(keys, function(a, b) return book[a].t > book[b].t end)
		for i = Feuds.KEEP_MAX + 1, #keys do book[keys[i]] = nil end
	end
end

---------------------------------------------------------------------------
-- Who is around: enemies Detect has seen lately, so a GUID or a bare name
-- from a kill or a death recap can be turned back into a character.
---------------------------------------------------------------------------

function Feuds:Saw(info)
	if not info or not info.key then return end
	local now = GetTime()
	local copy = Util.Copy(info)
	copy.unit = nil
	copy.t = now
	self.recent[info.key] = copy
	if info.guid then self.recent[info.guid] = copy end
end

function Feuds:Recent(id)
	local info = id and self.recent[id]
	if info and GetTime() - info.t <= Feuds.RECENT_SECONDS then return info end
	return nil
end

--- Recently seen enemies whose first name (or whole display name) is `text`.
function Feuds:RecentByName(text)
	local canon = Names.Canon(text)
	if not canon then return nil end
	local exact = self:Recent(Names.Key(canon))
	if exact then return exact end
	local wanted, found, seen = Util.Fold(text), nil, {}
	for _, info in pairs(self.recent) do
		if not seen[info] and GetTime() - info.t <= Feuds.RECENT_SECONDS then
			seen[info] = true
			if Names.FirstKey(info.name) == wanted or Util.Fold(Names.Display(info.name)) == wanted then
				if found then return nil end -- two candidates: do not guess
				found = info
			end
		end
	end
	return found
end

--- An enemy player by GUID: from a live unit if the client still shows one,
--- otherwise from what we saw lately.
function Feuds:ByGuid(guid)
	if not guid then return nil end
	local token
	if _G.UnitTokenFromGUID then
		local ok, value = pcall(_G.UnitTokenFromGUID, guid)
		token = ok and plain(value, "string") or nil
	end
	if token then
		local ok, info = pcall(ns.Detect.Inspect, token)
		if ok and info then
			self:Saw(info)
			return info
		end
	end
	return self:Recent(guid)
end

function Feuds.Paused()
	return ns.Detect.paused
end

---------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------

--- The key a fight is filed under: the list entry if this player is on it
--- (even when listed under an old name or a first name), else their own.
local function fileKey(info)
	local s = ns.session
	if s then
		local key = ns.Detect.Match(s.store, info)
		if key then return key, true end
	end
	return info.key, false
end

--- Push my tally for a listed player to the guild, if it changed.
function Feuds:Publish(key)
	local s = ns.session
	if not s or not s.store:IsListed(key) then return nil end
	local e = self:Entry(key)
	local rec = s.store:Get(Codec.Id("c", key, s.meKey))
	if not e and not rec then return nil end
	e = e or self:Entry(key, true)
	-- After a reinstall the guild may know more than this computer does.
	if rec then
		e.k = math.max(e.k, rec.kills)
		e.d = math.max(e.d, rec.deaths)
	end
	if e.k == 0 and e.d == 0 then return nil end
	return s.store:SetScore(key, s.me, e.k, e.d, GetServerTime())
end

--- A score in my name that does not match my own tally was relayed by
--- someone else (relayed state cannot be verified). This computer knows my
--- score best, so it answers with a newer record of the real numbers.
function Feuds:Defend(rec)
	local s = ns.session
	if not s or rec.akey ~= s.meKey then return end
	local e = self:Entry(rec.key)
	if not e or (rec.kills == e.k and rec.deaths == e.d) then return end
	ns:Debug("correcting a score relayed in my name")
	s.store:SetScore(rec.key, s.me, e.k, e.d, GetServerTime())
end

local function scoreText(key)
	local s = ns.session
	if not s or not s.store:IsListed(key) then return nil end
	local kills, deaths = s.store:Score(key)
	return L.SCORE_GUILD:format(kills, deaths)
end

function Feuds:Count(info, field, now)
	local key, listed = fileKey(info)
	local e = self:Entry(key, true)
	if not e then return nil end
	e.n = info.name
	e.g = info.guid or e.g
	e.t = now
	e[field] = (e[field] or 0) + 1
	if field == "d" then
		e.r = e.r or {}
		e.r[#e.r + 1] = now
	end
	if listed then self:Publish(key) end
	ns:Fire("FEUD_CHANGED", key)
	return key, e, listed
end

function Feuds:OnKill(attackerGUID, targetGUID)
	local stats = self.stats
	stats.kills = stats.kills + 1
	if Feuds.Paused() then return end
	attackerGUID, targetGUID = plain(attackerGUID, "string"), plain(targetGUID, "string")
	if not attackerGUID or not targetGUID then
		stats.killsSecret = stats.killsSecret + 1
		return
	end
	local mine = attackerGUID == plain(UnitGUID("player"), "string") or attackerGUID == plain(UnitGUID("pet"), "string")
	if not mine then return end
	stats.killsMine = stats.killsMine + 1
	local info = self:ByGuid(targetGUID)
	if not info then return end -- not an enemy player we could identify
	stats.killsKnown = stats.killsKnown + 1
	local key, e, listed = self:Count(info, "k", GetServerTime())
	if not key then return end
	if ns.Hotspots and ns.Fmt then
		local map, x, y = ns.Fmt.PlayerPosition()
		if map then ns.Hotspots:Record("kill", map, x, y, info.name) end
	end
	if ns.Progress then ns.Progress:OnKill(info, key, listed, e) end
	if listed and ns.settings.chat then
		ns:Print(L.MSG_KILL:format(Names.Display(info.name), scoreText(key) or ""))
	end
	ns:Debug("killing blow counted (%d-%d)", e.k, e.d)
end

--- The enemy player who killed us, from the newest death recap. The first
--- recap event is the killing blow; if that came from something we cannot
--- identify (a pet, a fall), the next player in the recap is credited.
function Feuds:Killer()
	local recap = _G.C_DeathRecap
	if not (recap and recap.GetRecapEvents) then return nil, "no-api" end
	local ok, events = pcall(recap.GetRecapEvents)
	if not ok or type(events) ~= "table" then return nil, "no-events" end
	local stamp = events[1] and plain(events[1].timestamp, "number")
	for i = 1, #events do
		local e = events[i]
		if type(e) == "table" then
			local guid = plain(e.sourceGUID, "string")
			local info = guid and self:ByGuid(guid)
			if not info then
				local name = plain(e.sourceName, "string")
				info = name and self:RecentByName(name)
			end
			if info then return info, stamp end
		end
	end
	return nil, #events == 0 and "empty" or "unknown", stamp
end

function Feuds:OnDeath()
	if Feuds.Paused() then return end
	self.stats.deaths = self.stats.deaths + 1
	if ns.Progress then ns.Progress:EndStreak() end -- whoever did it
	local info, stamp = self:Killer()
	if not info then
		ns:Debug("death: killer not identified (%s)", tostring(stamp))
		return
	end
	self.stats.deathsKnown = self.stats.deathsKnown + 1
	-- The same recap read twice (an extra PLAYER_DEAD) must count once.
	if type(stamp) == "number" then
		if self.lastDeath == stamp then return end
		self.lastDeath = stamp
	end
	local now = GetServerTime()
	local key, e, listed = self:Count(info, "d", now)
	if not key then return end
	if ns.Hotspots and ns.Fmt then
		local map, x, y = ns.Fmt.PlayerPosition()
		if map then ns.Hotspots:Record("death", map, x, y, info.name) end
	end
	if ns.Progress then ns.Progress:OnDeath() end
	if listed and ns.settings.chat then
		ns:Print(L.MSG_KILLED_BY:format(Names.Display(info.name), scoreText(key) or ""))
	end
	self:ConsiderRevenge(key, info, e, now)
end

---------------------------------------------------------------------------
-- Revenge: offered when the same enemy kills you again and again
---------------------------------------------------------------------------

--- Deaths to this entry within the revenge window (and drop older ones).
function Feuds:RecentDeaths(e, now)
	local window = (ns.settings.revengeWindow or 30) * 60
	local kept = {}
	for _, t in ipairs(e.r or {}) do
		if now - t <= window then kept[#kept + 1] = t end
	end
	e.r = kept
	return #kept
end

function Feuds:ConsiderRevenge(key, info, e, now)
	local n = self:RecentDeaths(e, now)
	if not ns.settings.revenge then return false end
	if n < (ns.settings.revengeCount or 2) then return false end
	if ns:MyReport("r", key) then return false end
	-- Once offered, stay quiet about this enemy for the rest of the window.
	local window = (ns.settings.revengeWindow or 30) * 60
	if e.p and now - e.p < window then return false end
	e.p = now
	if ns.Revenge then ns.Revenge:Show(key, info, n) end
	return true
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

function Feuds:Init()
	self:Prune(GetServerTime())
	self.events.PARTY_KILL = ns:On("PARTY_KILL", function(attacker, target) Feuds:OnKill(attacker, target) end)
	self.events.PLAYER_DEAD = ns:On("PLAYER_DEAD", function()
		-- The recap is filled in just after the death event.
		C_Timer.After(Feuds.RECAP_DELAY, function() ns.Safe(Feuds.OnDeath, Feuds) end)
	end)
	ns:Listen("LIST_CHANGED", function(_, rec)
		if not rec then return end
		if rec.k == "r" and not rec.del then
			-- Becoming listed: publish what this character already has
			-- against them.
			Feuds:Publish(rec.key)
		elseif rec.k == "c" then
			Feuds:Defend(rec)
		end
	end)
end
