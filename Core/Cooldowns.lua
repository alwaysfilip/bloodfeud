-- Hybrid enemy cooldown tracker ("Counterclock" module) for WoW: Forever.
-- Auto-filters to the current opponent's class (Classic/Forever 9 classes +
-- PvP Trinket). Starts timers automatically when UNIT_SPELLCAST_SUCCEEDED
-- provides a readable spellID (Open World / Duels), and supports instant
-- 1-click or keybind triggering whenever Forever withholds spellID as secret.
local _, ns = ...

local Util, Names = ns.Util, ns.Names

local Cooldowns = {
	current = nil, -- { key, name, class, mode = "duel"|"world"|"bg"|"demo" }
	timers = {}, -- opponentKey -> { [slot] = { startedAt, endsAt, duration } }
	byName = {}, -- folded localized/English spell name -> { { class, slot }, ... }
	demo = false,
	events = {},
}
ns.Cooldowns = Cooldowns

local TRINKET = { id = 42292, name = "PvP Trinket", cd = 300, icon = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01" }

-- Curated high-impact PvP cooldowns per Classic/Forever class (slot 1 is always
-- PvP Trinket, slots 2..6 are class cooldowns).
Cooldowns.BY_CLASS = {
	[1] = { -- Warrior
		TRINKET,
		{ id = 20252, name = "Intercept", cd = 30 },
		{ id = 676, name = "Disarm", cd = 60 },
		{ id = 18499, name = "Berserker Rage", cd = 30 },
		{ id = 5246, name = "Intimidating Shout", cd = 180 },
		{ id = 12292, name = "Death Wish", cd = 180 },
	},
	[2] = { -- Paladin
		TRINKET,
		{ id = 853, name = "Hammer of Justice", cd = 60 },
		{ id = 1044, name = "Blessing of Freedom", cd = 20 },
		{ id = 1022, name = "Blessing of Protection", cd = 300 },
		{ id = 642, name = "Divine Shield", cd = 300 },
		{ id = 20066, name = "Repentance", cd = 60 },
	},
	[3] = { -- Hunter
		TRINKET,
		{ id = 5384, name = "Feign Death", cd = 30 },
		{ id = 1499, name = "Freezing Trap", cd = 15 },
		{ id = 19503, name = "Scatter Shot", cd = 30 },
		{ id = 19577, name = "Intimidation", cd = 60 },
		{ id = 19263, name = "Deterrence", cd = 300 },
	},
	[4] = { -- Rogue
		TRINKET,
		{ id = 408, name = "Kidney Shot", cd = 20 },
		{ id = 5277, name = "Evasion", cd = 300 },
		{ id = 2983, name = "Sprint", cd = 300 },
		{ id = 2094, name = "Blind", cd = 300 },
		{ id = 1856, name = "Vanish", cd = 300 },
	},
	[5] = { -- Priest
		TRINKET,
		{ id = 8122, name = "Psychic Scream", cd = 30 },
		{ id = 15487, name = "Silence", cd = 45 },
		{ id = 6346, name = "Fear Ward", cd = 30 },
		{ id = 14751, name = "Inner Focus", cd = 180 },
		{ id = 19236, name = "Desperate Prayer", cd = 600 },
	},
	[7] = { -- Shaman
		TRINKET,
		{ id = 8177, name = "Grounding Totem", cd = 15 },
		{ id = 2484, name = "Earthbind Totem", cd = 15 },
		{ id = 16188, name = "Nature's Swiftness", cd = 180 },
		{ id = 16166, name = "Elemental Mastery", cd = 180 },
		{ id = 16190, name = "Mana Tide Totem", cd = 300 },
	},
	[8] = { -- Mage
		TRINKET,
		{ id = 1953, name = "Blink", cd = 15 },
		{ id = 122, name = "Frost Nova", cd = 25 },
		{ id = 2139, name = "Counterspell", cd = 30 },
		{ id = 11958, name = "Ice Block", cd = 300 },
		{ id = 12472, name = "Cold Snap", cd = 600 },
	},
	[9] = { -- Warlock
		TRINKET,
		{ id = 17877, name = "Shadowburn", cd = 15 },
		{ id = 19647, name = "Spell Lock", cd = 24 },
		{ id = 5484, name = "Howl of Terror", cd = 40 },
		{ id = 6789, name = "Death Coil", cd = 120 },
		{ id = 18708, name = "Fel Domination", cd = 900 },
	},
	[11] = { -- Druid
		TRINKET,
		{ id = 16979, name = "Feral Charge", cd = 15 },
		{ id = 5211, name = "Bash", cd = 60 },
		{ id = 22812, name = "Barkskin", cd = 60 },
		{ id = 17116, name = "Nature's Swiftness", cd = 180 },
		{ id = 29166, name = "Innervate", cd = 360 },
	},
}

-- Extra spell ID aliases (e.g. Classic/Forever PvP trinket spell IDs and modern
-- Ice Block/trinket IDs) that map onto the same logical ability by name.
local EXTRA_ALIASES = {
	[45438] = "Ice Block",
	[23273] = "PvP Trinket",
	[23274] = "PvP Trinket",
	[23276] = "PvP Trinket",
	[23277] = "PvP Trinket",
	[59752] = "PvP Trinket",
	[208683] = "PvP Trinket",
	[336126] = "PvP Trinket",
}

local EXTRA_NAMES = {
	["insignia of the alliance"] = "PvP Trinket",
	["insignia of the horde"] = "PvP Trinket",
	["gladiator's medallion"] = "PvP Trinket",
	["will to survive"] = "PvP Trinket",
	["every man for himself"] = "PvP Trinket",
}

local function plain(value, kind)
	if value == nil or Util.IsSecret(value) then return nil end
	if kind and type(value) ~= kind then return nil end
	return value
end

local function spellName(id)
	if _G.C_Spell and _G.C_Spell.GetSpellName then
		local ok, name = pcall(_G.C_Spell.GetSpellName, id)
		if ok and type(name) == "string" and not Util.IsSecret(name) and name ~= "" then return name end
	end
	if _G.GetSpellInfo then
		local ok, name = pcall(_G.GetSpellInfo, id)
		if ok and type(name) == "string" and not Util.IsSecret(name) and name ~= "" then return name end
	end
	return nil
end

function Cooldowns.SpellTexture(spec)
	if _G.C_Spell and _G.C_Spell.GetSpellTexture and spec.id then
		local ok, tex = pcall(_G.C_Spell.GetSpellTexture, spec.id)
		if ok and tex and not Util.IsSecret(tex) then return tex end
	end
	return spec.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function Cooldowns:BuildIndex()
	local map = {}
	local function addName(name, classID, slot)
		if type(name) ~= "string" or name == "" then return end
		local key = Util.Fold(name)
		local list = map[key]
		if not list then
			list = {}
			map[key] = list
		end
		list[#list + 1] = { class = classID, slot = slot }
	end
	for classID, list in pairs(Cooldowns.BY_CLASS) do
		for slot = 1, #list do
			local spec = list[slot]
			addName(spec.name, classID, slot)
			local localized = spellName(spec.id)
			if localized and localized ~= spec.name then addName(localized, classID, slot) end
		end
	end
	self.byName = map
end

--- Curated spell list for a classID (defaults to Rogue in demo/unknown fallback).
function Cooldowns.SlotsFor(classID)
	return Cooldowns.BY_CLASS[classID] or { TRINKET }
end

function Cooldowns:SetOpponent(info, mode)
	if not info or not info.key then
		self.current = nil
		ns:Fire("COOLDOWNS_CHANGED")
		return
	end
	self.current = { key = info.key, name = info.name or info.key, class = info.class, mode = mode or "world" }
	ns:Fire("COOLDOWNS_CHANGED")
end

--- Start (or restart) cooldown slot `slot` on `opponentKey` (default: current).
function Cooldowns:TriggerSlot(slot, opponentKey, classID)
	local cur = self.current
	local key = opponentKey or (cur and cur.key)
	local cls = classID or (cur and cur.class)
	if not key then return false end
	local slots = Cooldowns.SlotsFor(cls)
	local spec = slots[slot]
	if not spec then return false end
	local now = GetTime()
	local per = self.timers[key]
	if not per then
		per = {}
		self.timers[key] = per
	end
	per[slot] = { startedAt = now, endsAt = now + spec.cd, duration = spec.cd }
	ns:Fire("COOLDOWNS_CHANGED")
	return true
end

function Cooldowns:ResetSlot(slot, opponentKey)
	local key = opponentKey or (self.current and self.current.key)
	local per = key and self.timers[key]
	if per and per[slot] then
		per[slot] = nil
		ns:Fire("COOLDOWNS_CHANGED")
	end
end

function Cooldowns:ResetAll(opponentKey)
	local key = opponentKey or (self.current and self.current.key)
	if key and self.timers[key] then
		self.timers[key] = nil
		ns:Fire("COOLDOWNS_CHANGED")
	end
end

--- Remaining seconds and duration for `slot` on the active opponent (or 0).
function Cooldowns:Remaining(slot, opponentKey)
	local key = opponentKey or (self.current and self.current.key)
	local per = key and self.timers[key]
	local t = per and per[slot]
	if not t then return 0, 0 end
	local rem = t.endsAt - GetTime()
	if rem <= 0 then
		per[slot] = nil
		return 0, 0
	end
	return rem, t.duration
end

--- Automatic detection via UNIT_SPELLCAST_SUCCEEDED when spellID is readable.
function Cooldowns:OnCast(unit, _, spellID)
	if not ns.settings.cdTracker then return end
	if unit == "player" or unit == "pet" then return end
	if type(unit) ~= "string" or Util.IsSecret(unit) then return end
	spellID = plain(spellID, "number")
	if not spellID then return end

	local alias = EXTRA_ALIASES[spellID]
	local name = spellName(spellID)
	local matches = name and self.byName[Util.Fold(name)]
	if not matches and name then
		local mapped = EXTRA_NAMES[Util.Fold(name)]
		if mapped then matches = self.byName[Util.Fold(mapped)] end
	end
	if not matches and alias then
		matches = self.byName[Util.Fold(alias)]
	end
	if not matches then return end

	-- Identify the caster: either our active duel opponent or an opposing player.
	local key, cls
	local duel = ns.Duels and ns.Duels.active
	local unitName = Names.OfUnit(unit)
	local unitKey = unitName and Names.Key(unitName)
	if duel and unitKey and unitKey == duel.key then
		if not ns.settings.cdDuels then return end
		key, cls = duel.key, duel.class
		if not cls and _G.UnitClass then
			local okC, _, _, cid = pcall(_G.UnitClass, unit)
			if okC then cls = plain(cid, "number") end
		end
	else
		local inBG = ns.Battleground and ns.Battleground.active
		if inBG and not ns.settings.cdBG then return end
		if not inBG and not ns.settings.cdWorld then return end
		local ok, info = pcall(ns.Detect.Inspect, unit)
		if not (ok and info) then return end
		key, cls = info.key, info.class
	end
	if not key then return end
	if not cls then
		-- Shared slot 1 (PvP Trinket) can still trigger before class is known.
		if matches[1] and matches[1].slot == 1 then self:TriggerSlot(1, key, nil) end
		return
	end

	for i = 1, #matches do
		if matches[i].class == cls then
			self:TriggerSlot(matches[i].slot, key, cls)
			return
		end
	end
end

function Cooldowns:OnTargetChanged()
	if not ns.settings.cdTracker or self.demo then return end
	-- Never steal focus from an active duel.
	if ns.Duels and ns.Duels.active and ns.settings.cdDuels then return end
	local inBG = ns.Battleground and ns.Battleground.active
	if inBG and not ns.settings.cdBG then
		if self.current and self.current.mode ~= "duel" then self:SetOpponent(nil) end
		return
	end
	if not inBG and not ns.settings.cdWorld then
		if self.current and self.current.mode ~= "duel" then self:SetOpponent(nil) end
		return
	end
	local ok, info = pcall(ns.Detect.Inspect, "target")
	if ok and info and info.class then
		self:SetOpponent(info, inBG and "bg" or "world")
	elseif self.current and self.current.mode ~= "duel" then
		self:SetOpponent(nil)
	end
end

function Cooldowns:SetDemo(on)
	self.demo = on and true or false
	if self.demo then
		self:SetOpponent({ key = "demo:grimtusk", name = "Grimtusk-Bloodaxe", class = 4 }, "demo")
		self:TriggerSlot(1)
		self:TriggerSlot(5)
	else
		self.timers["demo:grimtusk"] = nil
		self:SetOpponent(nil)
		self:OnTargetChanged()
	end
end

function Cooldowns:Init()
	self:BuildIndex()
	self.events.UNIT_SPELLCAST_SUCCEEDED = ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
		Cooldowns:OnCast(unit, castGUID, spellID)
	end)
	self.events.PLAYER_TARGET_CHANGED = ns:On("PLAYER_TARGET_CHANGED", function() Cooldowns:OnTargetChanged() end)
	ns:Listen("DUEL_STARTED", function(opp)
		if ns.settings.cdTracker and ns.settings.cdDuels and opp then
			Cooldowns:ResetAll(opp.key)
			Cooldowns:SetOpponent(opp, "duel")
		end
	end)
	ns:Listen("DUEL_ENDED", function(_, prev)
		if prev then Cooldowns:ResetAll(prev.key) end
		if Cooldowns.current and Cooldowns.current.mode == "duel" then
			Cooldowns:SetOpponent(nil)
			Cooldowns:OnTargetChanged()
		end
	end)
	-- Prune expired per-enemy tables occasionally.
	C_Timer.NewTicker(60, function()
		local now = GetTime()
		for key, per in pairs(Cooldowns.timers) do
			local any = false
			for slot, t in pairs(per) do
				if t.endsAt <= now then per[slot] = nil else any = true end
			end
			if not any then Cooldowns.timers[key] = nil end
		end
	end)
end

-- Keybinding entry points (declared in Bindings.xml).
function BusinessMeeting_CooldownSlot(slot)
	ns.Safe(Cooldowns.TriggerSlot, Cooldowns, slot)
end

function BusinessMeeting_CooldownReset()
	ns.Safe(Cooldowns.ResetAll, Cooldowns)
end
