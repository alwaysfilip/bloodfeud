-- An enemy player near you just went into stealth.
--
-- The combat log is closed, but the client still reports the spells cast by
-- the units it shows you (nameplates, target, focus). When one of those is
-- an enemy player and the spell is Stealth, Vanish, Prowl or Shadowmeld, you
-- are told, and they are marked on the radar while it still remembers them.
-- Someone who was already stealthed when they came near is never seen.
local _, ns = ...

local Util = ns.Util

local Stealth = { names = {}, cache = {}, last = {}, events = {},
	-- What the client let us see, for /feud probe.
	stats = { casts = 0, secret = 0, hits = 0 } }
ns.Stealth = Stealth

Stealth.COOLDOWN = 10 -- seconds before the same enemy alerts again

-- The spells, by the ids they have in the mainline client, with their
-- English names. The name is what decides: ids are only a way to learn what
-- the spells are called on a client in another language.
Stealth.KNOWN = { [1784] = "Stealth", [1856] = "Vanish", [5215] = "Prowl", [58984] = "Shadowmeld" }

local function spellName(id)
	local api = _G.C_Spell and _G.C_Spell.GetSpellName
	if api then
		local ok, name = pcall(api, id)
		if ok and type(name) == "string" and not Util.IsSecret(name) then return name end
	end
	if _G.GetSpellInfo then
		local ok, name = pcall(_G.GetSpellInfo, id)
		if ok and type(name) == "string" and not Util.IsSecret(name) then return name end
	end
	return nil
end

--- Work out what the stealth spells are called on this client.
function Stealth:Build()
	self.names, self.cache = {}, {}
	local locale = _G.GetLocale and _G.GetLocale() or "enUS"
	local english = locale == "enUS" or locale == "enGB"
	for id, name in pairs(Stealth.KNOWN) do
		self.names[name] = true
		if not english then
			local localName = spellName(id)
			if localName then self.names[localName] = true end
		end
	end
end

--- The name of the stealth spell with this id, or nil when it is none.
function Stealth:Spell(spellID)
	local cached = self.cache[spellID]
	if cached ~= nil then return cached or nil end
	local name = spellName(spellID)
	local found
	if name then
		found = self.names[name] and name or false
	else
		found = Stealth.KNOWN[spellID] or false -- names cannot be looked up: go by the id
	end
	self.cache[spellID] = found
	return found or nil
end

--- A unit the client shows us cast something.
function Stealth:OnCast(unit, _, spellID)
	if unit == "player" or unit == "pet" or ns.Detect.paused or not ns.session then return end
	if type(unit) ~= "string" or Util.IsSecret(unit) then return end
	local stats = self.stats
	stats.casts = stats.casts + 1
	if spellID == nil or Util.IsSecret(spellID) then
		stats.secret = stats.secret + 1
		return
	end
	local spell = self:Spell(spellID)
	if not spell then return end
	local ok, info = pcall(ns.Detect.Inspect, unit)
	if not ok or not info then return end -- not an enemy player
	local now = GetTime()
	local last = self.last[info.key]
	if last and now - last < Stealth.COOLDOWN then return end -- the same cast, seen through another unit
	self.last[info.key] = now
	stats.hits = stats.hits + 1
	if ns.Radar then ns.Radar:Stealthed(info, spell) end
	if ns.settings.stealthAlerts then
		ns.Alerts:Stealth(info, spell, ns.Targeting and ns.Targeting:Dossier(info) or { myKills = 0, myDeaths = 0 })
	end
end

function Stealth:Init()
	self:Build()
	self.events.UNIT_SPELLCAST_SUCCEEDED = ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
		Stealth:OnCast(unit, castGUID, spellID)
	end)
end
