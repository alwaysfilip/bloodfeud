-- Who on the other side has you (or your pet) targeted.
--
-- The client only lets an addon ask this about enemies it shows you: the ones
-- with a nameplate, your own target and your focus. For those it is asked ten
-- times a second. An enemy who starts targeting you gives an alert with what
-- matters in a fight (class, level, guild, whether they are Kill on Sight,
-- how the guild and you have fared against them), and is marked on the radar
-- and on their nameplate for as long as it lasts.
local _, ns = ...

local Util = ns.Util

local Targeting = { on = {}, last = {}, tick = 0,
	-- What the client let us find out, for /feud probe.
	stats = { checks = 0, unknown = 0, hits = 0 } }
ns.Targeting = Targeting

Targeting.POLL = 0.1 -- seconds between looks at the nameplates
Targeting.SLOW_EVERY = 5 -- the player's own target and focus: every so many looks
Targeting.COOLDOWN = 30 -- seconds before the same enemy alerts again
Targeting.LOST = 2 -- seconds out of sight before we stop saying they target us

local function plain(value, kind)
	if value == nil or Util.IsSecret(value) then return nil end
	if kind and type(value) ~= kind then return nil end
	return value
end

-- true, false, or nil when the client withholds the comparison.
local function same(theirs, mine)
	if not _G.UnitIsUnit then return nil end
	local ok, result = pcall(_G.UnitIsUnit, theirs, mine)
	if ok and result ~= nil and not Util.IsSecret(result) then return result and true or false end
	return nil
end

--- Does the enemy behind `unit` have me targeted? Returns true (and, as a
--- second value, true when it is my pet rather than me), false, or nil when
--- the client will not say.
function Targeting.Check(unit)
	local stats = Targeting.stats
	stats.checks = stats.checks + 1
	local theirs = unit .. "target"
	local me = same(theirs, "player")
	if me then return true, false end
	if me == false then
		if ns.settings.targetPet and same(theirs, "pet") then return true, true end
		return false
	end
	-- The comparison is withheld: go by who their target is.
	local mine = plain(UnitGUID("player"), "string")
	local ok, guid = pcall(UnitGUID, theirs)
	if ok and mine then
		if guid == nil then return false end -- they have no target at all
		if type(guid) == "string" and not Util.IsSecret(guid) then
			if guid == mine then return true, false end
			local pet = ns.settings.targetPet and plain(UnitGUID("pet"), "string")
			if pet and guid == pet then return true, true end
			return false
		end
	end
	stats.unknown = stats.unknown + 1
	return nil
end

--- What is known about an enemy that matters in a fight:
--- { subject (their list entry, when Kill on Sight), listKey, kills, deaths
---   (the guild's, for a listed player), myKills, myDeaths, bounty (a line) }.
function Targeting:Dossier(info)
	local s = ns.session
	local out = { myKills = 0, myDeaths = 0 }
	if not s or not info then return out end
	local key = ns.Detect.Match(s.store, info)
	local subject = key and s.store:Player(key) or nil
	out.listKey, out.subject = key, subject
	if subject then out.kills, out.deaths = subject.kills or 0, subject.deaths or 0 end
	local mine = ns.Feuds and ns.Feuds:Entry(key or info.key)
	if mine then out.myKills, out.myDeaths = mine.k or 0, mine.d or 0 end
	out.bounty = ns.Bounties and ns.Bounties:Line(info, key) or nil
	return out
end

--- Has this enemy me or my pet targeted? Returns true, and "pet" or "me".
function Targeting:Is(key)
	local cur = self.on[key]
	if not cur then return false end
	return true, cur.pet and "pet" or "me"
end

--- How many enemies have me (not just my pet) targeted.
function Targeting:Count()
	local n = 0
	for _, cur in pairs(self.on) do
		if not cur.pet then n = n + 1 end
	end
	return n
end

--- Tell the player, unless this enemy did so a moment ago or is the one the
--- player has targeted themselves (no news there).
function Targeting:Alert(info, unit, pet)
	if not ns.settings.targetAlerts then return false end
	local now = GetTime()
	local slot = info.key .. (pet and "/pet" or "")
	local last = self.last[slot]
	if last and now - last < Targeting.COOLDOWN then return false end
	if unit == "target" then return false end
	local ok, mine = pcall(ns.Detect.Inspect, "target")
	if ok and mine and mine.key == info.key then return false end
	self.last[slot] = now
	ns.Alerts:Targeted(info, self:Dossier(info), pet)
	return true
end

--- Look at one enemy player (`info` as Detect.Inspect gave it) through `unit`.
function Targeting:Look(unit, info)
	if ns.Detect.paused or not info or not info.key then return end
	local result, pet = Targeting.Check(unit)
	if result == nil then return end
	local key = info.key
	local cur = self.on[key]
	if result then
		local now = GetTime()
		-- Moving from the pet to its owner (or back) is news again.
		local fresh = not cur or cur.pet ~= pet
		if not cur then
			cur = { since = now }
			self.on[key] = cur
			self.stats.hits = self.stats.hits + 1
			cur.info = Util.Copy(info)
			cur.info.unit = nil
		end
		cur.unit, cur.at, cur.pet = unit, now, pet
		if fresh then
			self:Alert(info, unit, pet)
			ns:Fire("TARGETING_CHANGED")
		end
	elseif cur then
		self.on[key] = nil
		ns:Fire("TARGETING_CHANGED")
	end
end

function Targeting:Clear()
	if next(self.on) == nil then return end
	self.on = {}
	ns:Fire("TARGETING_CHANGED")
end

local SLOW = { "target", "focus" }

--- Look again at every enemy the client shows us.
function Targeting:Poll()
	if ns.Detect.paused or not ns.session then
		self:Clear()
		return
	end
	local radar = ns.Radar
	if radar then
		for unit, key in pairs(radar.plates) do
			local entry = radar.list[key]
			if entry then self:Look(unit, entry.info) end
		end
	end
	self.tick = self.tick + 1
	if self.tick % Targeting.SLOW_EVERY ~= 0 then return end
	for i = 1, #SLOW do
		local ok, info = pcall(ns.Detect.Inspect, SLOW[i])
		if ok and info then self:Look(SLOW[i], info) end
	end
	-- Whoever is out of sight may have moved on to someone else.
	local now, changed = GetTime(), false
	for key, cur in pairs(self.on) do
		if now - cur.at > Targeting.LOST then
			self.on[key] = nil
			changed = true
		end
	end
	if changed then ns:Fire("TARGETING_CHANGED") end
	for slot, at in pairs(self.last) do
		if now - at > 600 then self.last[slot] = nil end
	end
end

function Targeting:Init()
	C_Timer.NewTicker(Targeting.POLL, function() ns.Safe(Targeting.Poll, Targeting) end)
end
