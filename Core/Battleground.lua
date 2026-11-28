-- Battleground engine for WoW: Forever (Warsong Gulch, Arathi Basin, Alterac
-- Valley, Darkspear Islands). Tracks live BG scoreboard deltas for BG kills and
-- deaths, maintains the enemy/ally rosters and flag carriers for BG HUDs, and
-- saves complete match scoreboards into History on completion.
local _, ns = ...

local Util, Names = ns.Util, ns.Names
local floor = math.floor

local Battleground = {
	active = false,
	mapKey = nil,
	mapName = nil,
	enemies = {},
	allies = {},
	roster = {},
	byKey = {},
	meRow = nil,
	fc = { enemy = nil, ally = nil },
	events = {},
}
ns.Battleground = Battleground

Battleground.POLL_SECONDS = 5
Battleground.RESUME_WINDOW = 30 * 60 -- resume baseline after a /reload within 30 min

-- Standard WoW class token -> Classic/Forever classID.
local CLASS_ID = {
	WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
	SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
}

local function plain(value, kind)
	if value == nil or Util.IsSecret(value) then return nil end
	if kind and type(value) ~= kind then return nil end
	return value
end

local function safe(fn, ...)
	if not fn then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c
end

--- True when the player is currently inside a PvP battleground instance.
function Battleground.InBG()
	if not _G.IsInInstance then return false end
	local ok, inInst, kind = pcall(_G.IsInInstance)
	return ok and inInst and kind == "pvp" and true or false
end

--- Identify one of Forever's battlegrounds from instance/zone name.
function Battleground.IdentifyMap(name)
	local clean = type(name) == "string" and Util.Fold(name) or ""
	if clean:find("warsong", 1, true) then return "wsg", name end
	if clean:find("arathi", 1, true) then return "ab", name end
	if clean:find("alterac", 1, true) then return "av", name end
	if clean:find("darkspear", 1, true) then return "ds", name end
	return "other", (type(name) == "string" and name ~= "" and name) or "Battleground"
end

--- Current player's faction as Blizzard's scoreboard integer: 0 Horde, 1 Alliance.
function Battleground.MyFactionNum()
	local f = ns.Detect and ns.Detect.MyFaction()
	if f == "Horde" then return 0 end
	if f == "Alliance" then return 1 end
	return nil
end

local function currentMapName()
	if _G.GetInstanceInfo then
		local ok, name = pcall(_G.GetInstanceInfo)
		name = ok and plain(name, "string")
		if name and name ~= "" then return name end
	end
	if _G.GetRealZoneText then
		local ok, name = pcall(_G.GetRealZoneText)
		name = ok and plain(name, "string")
		if name and name ~= "" then return name end
	end
	if _G.C_Map and _G.C_Map.GetBestMapForUnit and _G.C_Map.GetMapInfo then
		local ok, id = pcall(_G.C_Map.GetBestMapForUnit, "player")
		id = ok and plain(id, "number")
		if id then
			local okI, info = pcall(_G.C_Map.GetMapInfo, id)
			if okI and type(info) == "table" and type(info.name) == "string" then return info.name end
		end
	end
	return "Battleground"
end

local function activeStore(create)
	local me = Names.Me()
	if not me or not ns.db then return nil end
	ns.db.bgActive = type(ns.db.bgActive) == "table" and ns.db.bgActive or {}
	local key = Names.Key(me)
	if not ns.db.bgActive[key] and create then ns.db.bgActive[key] = {} end
	return ns.db.bgActive[key], key
end

local function clearActiveStore()
	local me = Names.Me()
	if not me or not ns.db or type(ns.db.bgActive) ~= "table" then return end
	ns.db.bgActive[Names.Key(me)] = nil
end

local function readScoreRow(i)
	local pvp = _G.C_PvP
	if pvp and pvp.GetScoreInfo then
		local ok, info = pcall(pvp.GetScoreInfo, i)
		if ok and type(info) == "table" then
			local rawName = plain(info.name, "string")
			local canon = rawName and Names.Canon(rawName)
			if not canon then return nil end
			local classToken = plain(info.classToken, "string")
			return {
				name = canon,
				key = Names.Key(canon),
				guid = plain(info.guid, "string"),
				faction = plain(info.faction, "number"),
				class = classToken and CLASS_ID[classToken] or nil,
				classToken = classToken,
				className = plain(info.className, "string"),
				kb = plain(info.killingBlows, "number") or 0,
				d = plain(info.deaths, "number") or 0,
				hk = plain(info.honorableKills, "number") or 0,
				dmg = plain(info.damageDone, "number") or 0,
				heal = plain(info.healingDone, "number") or 0,
				honor = plain(info.honorGained, "number") or 0,
			}
		end
	end
	if _G.GetBattlefieldScore then
		local ok, rawName, kb, hk, deaths, honor, faction, _, _, classToken, dmg, heal = pcall(_G.GetBattlefieldScore, i)
		if ok then
			rawName = plain(rawName, "string")
			local canon = rawName and Names.Canon(rawName)
			if not canon then return nil end
			classToken = plain(classToken, "string")
			return {
				name = canon,
				key = Names.Key(canon),
				faction = plain(faction, "number"),
				class = classToken and CLASS_ID[classToken] or nil,
				classToken = classToken,
				kb = plain(kb, "number") or 0,
				d = plain(deaths, "number") or 0,
				hk = plain(hk, "number") or 0,
				dmg = plain(dmg, "number") or 0,
				heal = plain(heal, "number") or 0,
				honor = plain(honor, "number") or 0,
			}
		end
	end
	return nil
end

local function sortRoster(a, b)
	if (a.class or 99) ~= (b.class or 99) then return (a.class or 99) < (b.class or 99) end
	return a.key < b.key
end

--- Request fresh scoreboard data from the server.
function Battleground:RequestScores()
	if not self.active then return end
	if _G.RequestBattlefieldScoreData then pcall(_G.RequestBattlefieldScoreData) end
end

local function matchDuration(startedAt)
	if _G.GetBattlefieldInstanceRunTime then
		local ok, ms = pcall(_G.GetBattlefieldInstanceRunTime)
		ms = ok and plain(ms, "number")
		if ms and ms > 0 then return floor(ms / 1000 + 0.5) end
	end
	return math.max(0, GetServerTime() - (startedAt or GetServerTime()))
end

--- Read the live scoreboard, apply any new BG kill/death deltas, update rosters
--- and save the match if a winner has been declared.
function Battleground:ScanScores()
	if not self.active then return end
	local getNum = _G.GetNumBattlefieldScores
	if not getNum then return end
	local ok, count = pcall(getNum)
	count = ok and plain(count, "number") or 0
	if count <= 0 then return end

	local myFaction = Battleground.MyFactionNum()
	local myGuid = plain(safe(_G.UnitGUID, "player"), "string")
	local me = Names.Me()
	local myKey = me and Names.Key(me)

	local enemies, allies, all, byKey = {}, {}, {}, {}
	local meRow
	for i = 1, count do
		local row = readScoreRow(i)
		if row then
			all[#all + 1] = row
			byKey[row.key] = row
			if (myGuid and row.guid and row.guid == myGuid) or (myKey and row.key == myKey) then
				meRow = row
				if myFaction == nil then myFaction = row.faction end
			end
		end
	end
	for i = 1, #all do
		local row = all[i]
		if myFaction ~= nil and row.faction ~= nil then
			if row.faction == myFaction then
				allies[#allies + 1] = row
			else
				enemies[#enemies + 1] = row
			end
		elseif row == meRow then
			allies[#allies + 1] = row
		else
			enemies[#enemies + 1] = row
		end
	end
	table.sort(enemies, sortRoster)
	table.sort(allies, sortRoster)
	self.enemies, self.allies, self.roster, self.byKey, self.meRow = enemies, allies, all, byKey, meRow

	-- Refresh flag carrier metadata from the roster if known.
	for _, side in ipairs({ "enemy", "ally" }) do
		local carrier = self.fc[side]
		if carrier and carrier.key and byKey[carrier.key] then
			carrier.class = carrier.class or byKey[carrier.key].class
			carrier.name = byKey[carrier.key].name
		end
	end

	-- Delta-track our own killing blows and deaths (safe across /reload).
	local state = activeStore(true)
	if meRow and state then
		local prevKB = state.kb or 0
		local prevD = state.d or 0
		-- If the scoreboard reset (a brand-new match on the same map), reset the baseline.
		if meRow.kb < prevKB or meRow.d < prevD then
			prevKB, prevD = 0, 0
		end
		local dk = math.max(0, meRow.kb - prevKB)
		local dd = math.max(0, meRow.d - prevD)
		state.kb, state.d, state.seenAt = meRow.kb, meRow.d, GetServerTime()
		if (dk > 0 or dd > 0) and ns.Progress then
			ns.Progress:OnBGDelta(dk, dd)
		end
	end

	-- Check if the match has concluded.
	if _G.GetBattlefieldWinner then
		local okW, winner = pcall(_G.GetBattlefieldWinner)
		winner = okW and plain(winner, "number")
		if winner ~= nil then self:FinishMatch(winner) end
	end

	ns:Fire("BG_ROSTER_CHANGED")
end

--- Record a finished BG match into History and Progress (at most once per match).
function Battleground:FinishMatch(winner)
	local state = activeStore(true)
	if not state or state.saved then return nil end
	state.saved = true

	local myFaction = Battleground.MyFactionNum()
	if myFaction == nil and self.meRow then myFaction = self.meRow.faction end
	local win
	if (winner == 0 or winner == 1) and myFaction ~= nil then
		win = (winner == myFaction)
	end

	local me = self.meRow or { kb = state.kb or 0, d = state.d or 0, hk = 0, dmg = 0, heal = 0, honor = 0 }
	local compact = {}
	for i = 1, #self.roster do
		local r = self.roster[i]
		compact[i] = {
			n = r.name, c = r.class, f = r.faction,
			kb = r.kb, d = r.d, hk = r.hk, dmg = r.dmg, heal = r.heal,
			e = (myFaction ~= nil and r.faction ~= nil) and (r.faction ~= myFaction) or false,
		}
	end

	local scoreText
	local proj = ns.BGTimers and ns.BGTimers.projection
	if proj and proj.aScore and proj.hScore then
		scoreText = tostring(proj.aScore) .. "–" .. tostring(proj.hScore)
	end

	local match = {
		t = GetServerTime(),
		map = self.mapName or state.mapName or "Battleground",
		mapKey = self.mapKey or state.mapKey or "other",
		win = win,
		score = scoreText,
		dur = matchDuration(state.startedAt),
		kb = me.kb or 0,
		d = me.d or 0,
		hk = me.hk or 0,
		dmg = me.dmg or 0,
		heal = me.heal or 0,
		honor = me.honor or 0,
		roster = compact,
	}
	if ns.History then ns.History:RecordBG(match) end
	if ns.Progress then ns.Progress:OnBGComplete(match) end
	ns:Fire("BG_MATCH_SAVED", match)
	return match
end

---------------------------------------------------------------------------
-- Flag carriers (WSG and Darkspear Islands)
---------------------------------------------------------------------------

local function carrierFor(nameText)
	local canon = Names.Canon(nameText)
	if not canon then return nil end
	local key = Names.Key(canon)
	local row = Battleground.byKey[key]
	return { name = row and row.name or canon, key = key, class = row and row.class or nil }
end

local function setFC(side, carrier)
	Battleground.fc[side] = carrier
	ns:Fire("BG_FLAG_CHANGED", side, carrier)
end

--- Inspect `arena1`..`arena5` (used by Blizzard for flag carriers in BGs).
function Battleground:ScanFlagUnits()
	if not self.active then return end
	local myFaction = ns.Detect and ns.Detect.MyFaction()
	for i = 1, 5 do
		local unit = "arena" .. i
		if plain(safe(_G.UnitExists, unit)) and plain(safe(_G.UnitIsPlayer, unit)) then
			local canon = Names.OfUnit(unit)
			if canon then
				local key = Names.Key(canon)
				local faction = plain(safe(_G.UnitFactionGroup, unit), "string")
				local _, _, cid = safe(_G.UnitClass, unit)
				local classID = plain(cid, "number")
				local side = (myFaction and faction and faction == myFaction) and "ally" or "enemy"
				local cur = self.fc[side]
				if not cur or cur.key ~= key or cur.unit ~= unit then
					setFC(side, { name = canon, key = key, class = classID or (cur and cur.class), unit = unit })
				end
			end
		end
	end
end

--- Parse BG system chat announcements to keep enemy/ally flag carriers current.
function Battleground:OnBGChat(event, text)
	if not self.active then return end
	text = plain(text, "string")
	if not text then return end
	local myFaction = ns.Detect and ns.Detect.MyFaction() -- "Alliance" or "Horde"

	-- WSG: "The Alliance Flag was picked up by Grimtusk-Bloodaxe!"
	-- (Alliance flag is carried by a Horde player; Horde flag by an Alliance player.)
	local flagFaction, who = text:match("[Tt]he (%a+) [Ff]lag was picked up by ([^!%.]+)")
	if not (flagFaction and who) then
		who, flagFaction = text:match("^([^!%.]+) picked up the (%a+) [Ff]lag")
	end
	if flagFaction and who then
		local carrier = carrierFor(who)
		if carrier then
			local side = (flagFaction == myFaction) and "enemy" or "ally"
			setFC(side, carrier)
		end
		return
	end

	-- Darkspear Islands / Eye of the Storm style neutral flag: "X has taken the flag!"
	local taker = text:match("^([^!%.]+) has taken the flag")
	if taker then
		local carrier = carrierFor(taker)
		if carrier then
			local side
			if event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" then
				side = (myFaction == "Alliance") and "ally" or "enemy"
			elseif event == "CHAT_MSG_BG_SYSTEM_HORDE" then
				side = (myFaction == "Horde") and "ally" or "enemy"
			else
				local row = self.byKey[carrier.key]
				local myNum = Battleground.MyFactionNum()
				side = (row and myNum ~= nil and row.faction == myNum) and "ally" or "enemy"
			end
			setFC(side, carrier)
		end
		return
	end

	-- Dropped / returned / captured: clear that side's carrier.
	local dropFaction = text:match("[Tt]he (%a+) [Ff]lag was dropped")
		or text:match("[Tt]he (%a+) [Ff]lag was returned")
	if dropFaction then
		local side = (dropFaction == myFaction) and "enemy" or "ally"
		setFC(side, nil)
		return
	end
	local capFaction = text:match("captured the (%a+) [Ff]lag")
	if capFaction then
		local side = (capFaction == myFaction) and "enemy" or "ally"
		setFC(side, nil)
		return
	end
	if text:find("flag has been dropped", 1, true) or text:find("flag has been reset", 1, true)
		or text:find("captured the flag", 1, true) then
		setFC("enemy", nil)
		setFC("ally", nil)
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function Battleground:OnZone()
	local nowBG = Battleground.InBG()
	if nowBG then
		local mapKey, mapName = Battleground.IdentifyMap(currentMapName())
		local changed = not self.active or self.mapName ~= mapName
		self.active = true
		self.mapKey, self.mapName = mapKey, mapName
		if changed then
			self.enemies, self.allies, self.roster, self.byKey, self.meRow = {}, {}, {}, {}, nil
			self.fc = { enemy = nil, ally = nil }
			local state = activeStore(true)
			local now = GetServerTime()
			if state then
				local sameRecent = state.mapName == mapName and not state.saved
					and state.seenAt and (now - state.seenAt) <= Battleground.RESUME_WINDOW
				if not sameRecent then
					state.mapKey, state.mapName = mapKey, mapName
					state.startedAt, state.seenAt = now, now
					state.kb, state.d, state.saved = 0, 0, false
				else
					state.seenAt = now
				end
			end
			self:RequestScores()
			ns:Fire("BG_STATE_CHANGED", true, mapKey, mapName)
		end
	elseif self.active then
		local winner = plain(safe(_G.GetBattlefieldWinner), "number")
		if winner ~= nil then self:FinishMatch(winner) end
		self.active = false
		self.mapKey, self.mapName = nil, nil
		self.enemies, self.allies, self.roster, self.byKey, self.meRow = {}, {}, {}, {}, nil
		self.fc = { enemy = nil, ally = nil }
		clearActiveStore()
		ns:Fire("BG_STATE_CHANGED", false)
		if ns.Progress then ns.Progress:Publish() end
	end
end

function Battleground:Init()
	local events = self.events
	events.PLAYER_ENTERING_WORLD = ns:On("PLAYER_ENTERING_WORLD", function() Battleground:OnZone() end)
	events.ZONE_CHANGED_NEW_AREA = ns:On("ZONE_CHANGED_NEW_AREA", function() Battleground:OnZone() end)
	events.UPDATE_BATTLEFIELD_SCORE = ns:On("UPDATE_BATTLEFIELD_SCORE", function() Battleground:ScanScores() end)
	events.UPDATE_BATTLEFIELD_STATUS = ns:On("UPDATE_BATTLEFIELD_STATUS", function()
		if Battleground.active then Battleground:RequestScores() end
	end)
	events.PVP_MATCH_COMPLETE = ns:On("PVP_MATCH_COMPLETE", function(winner)
		if Battleground.active then
			Battleground:ScanScores()
			Battleground:FinishMatch(plain(winner, "number"))
		end
	end)
	events.ARENA_OPPONENT_UPDATE = ns:On("ARENA_OPPONENT_UPDATE", function() Battleground:ScanFlagUnits() end)
	for _, ev in ipairs({ "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_BG_SYSTEM_NEUTRAL" }) do
		events[ev] = ns:On(ev, function(text) Battleground:OnBGChat(ev, text) end)
	end
	C_Timer.NewTicker(Battleground.POLL_SECONDS, function()
		if Battleground.active then
			ns.Safe(Battleground.RequestScores, Battleground)
			ns.Safe(Battleground.ScanFlagUnits, Battleground)
		end
	end)
	self:OnZone()
end
