-- 1v1 duel tracking: detects duel start and outcome, records duel history and
-- win/loss totals, and signals the Enemy Cooldown Tracker when a duel begins
-- or ends.
local _, ns = ...

local Util, Names = ns.Util, ns.Names
local floor = math.floor

local Duels = { active = nil, events = {} }
ns.Duels = Duels

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

-- Turn a Blizzard format string such as "%1$s has defeated %2$s in a duel" into
-- a Lua pattern and record which capture group is the winner (1 or 2).
local function compileFormat(fmt, defaultPattern, defaultWinnerIdx)
	if type(fmt) ~= "string" or fmt == "" then return defaultPattern, defaultWinnerIdx end
	local order = {}
	local escaped = fmt:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
	-- Restore escaped format placeholders like %%1%%$s or %%s
	local pattern = escaped:gsub("%%%%(%d+)%%%$s", function(idx)
		order[#order + 1] = tonumber(idx)
		return "(.+)"
	end)
	if #order == 0 then
		local n = 0
		pattern = escaped:gsub("%%%%s", function()
			n = n + 1
			order[n] = n
			return "(.+)"
		end)
	end
	if #order < 2 then return defaultPattern, defaultWinnerIdx end
	local winnerIdx = (order[1] == 1) and 1 or 2
	return "^" .. pattern .. "$", winnerIdx
end

local function parseOutcome(text)
	local koPat, koWin = compileFormat(_G.DUEL_WINNER_KNOCKOUT, "^(.+) has defeated (.+) in a duel$", 1)
	local a, b = text:match(koPat)
	if a and b then
		if koWin == 1 then return a, b, false end
		return b, a, false
	end
	local flPat, flWin = compileFormat(_G.DUEL_WINNER_RETREAT, "^(.+) has fled from (.+) in a duel$", 2)
	a, b = text:match(flPat)
	if a and b then
		if flWin == 1 then return a, b, true end
		return b, a, true
	end
	return nil
end

local function inspectUnitForDuel(unit, expectedKey)
	if not plain(safe(_G.UnitExists, unit)) then return nil end
	if not plain(safe(_G.UnitIsPlayer, unit)) then return nil end
	local name = Names.OfUnit(unit)
	if not name then return nil end
	local key = Names.Key(name)
	local me = Names.Me()
	if me and key == Names.Key(me) then return nil end
	if expectedKey and key ~= expectedKey then return nil end
	local _, _, cid = safe(_G.UnitClass, unit)
	local classID = plain(cid, "number")
	local level = plain(safe(_G.UnitLevel, unit), "number")
	return { name = name, key = key, class = classID, level = (level and level > 0) and level or nil }
end

local function findOpponent(nameText)
	local canon = nameText and Names.Canon(nameText)
	local key = canon and Names.Key(canon)
	for _, unit in ipairs({ "target", "focus", "mouseover" }) do
		local found = inspectUnitForDuel(unit, key)
		if found then return found end
	end
	for i = 1, 40 do
		local found = inspectUnitForDuel("nameplate" .. i, key)
		if found then return found end
	end
	if canon then return { name = canon, key = key } end
	return nil
end

--- Begin tracking a duel with `opponentName` (or the current player target).
function Duels:Start(opponentName)
	local opp = findOpponent(opponentName)
	if not opp then return end
	if self.active and self.active.key == opp.key then
		self.active.class = self.active.class or opp.class
		self.active.level = self.active.level or opp.level
		return
	end
	opp.startedAt = GetServerTime()
	self.active = opp
	ns:Fire("DUEL_STARTED", opp)
end

--- End the active duel without a system-chat outcome (cancelled/walked off).
function Duels:End(result)
	local prev = self.active
	self.active = nil
	if prev or result then ns:Fire("DUEL_ENDED", result, prev) end
end

local function samePerson(canonA, canonB)
	if not (canonA and canonB) then return false end
	local ka, kb = Names.Key(canonA), Names.Key(canonB)
	if ka == kb then return true end
	return Names.FirstKey(canonA) == kb or Names.FirstKey(canonB) == ka
end

function Duels:OnSystemMessage(text)
	text = plain(text, "string")
	if not text then return end

	-- Challenger does not receive DUEL_REQUESTED; notice the countdown instead.
	if not self.active then
		local cdPrefix = type(_G.DUEL_COUNTDOWN) == "string" and _G.DUEL_COUNTDOWN:match("^(.-)%%") or nil
		if text:find("Duel starting", 1, true) or (cdPrefix and cdPrefix ~= "" and text:find(cdPrefix, 1, true)) then
			self:Start()
			return
		end
	end

	local winnerRaw, loserRaw, fled = parseOutcome(text)
	if not (winnerRaw and loserRaw) then return end
	local me = Names.Me()
	if not me then return end
	local winner, loser = Names.Canon(winnerRaw), Names.Canon(loserRaw)
	if not (winner and loser) then return end

	local won
	local opponent
	if samePerson(winner, me) then
		won, opponent = true, loser
	elseif samePerson(loser, me) then
		won, opponent = false, winner
	else
		return -- someone else's duel nearby
	end

	local oppInfo = self.active
	if not oppInfo or not samePerson(oppInfo.name, opponent) then
		oppInfo = findOpponent(opponent) or { name = opponent, key = Names.Key(opponent) }
	end
	local now = GetServerTime()
	local mapID = ns.Fmt and ns.Fmt.PlayerPosition()
	local rec = {
		t = now,
		opponent = oppInfo.name or opponent,
		key = oppInfo.key or Names.Key(opponent),
		class = oppInfo.class,
		level = oppInfo.level,
		won = won,
		fled = fled and true or false,
		dur = oppInfo.startedAt and floor(math.max(0, now - oppInfo.startedAt)) or 0,
		zone = mapID and ns.Fmt.Zone(mapID) or nil,
	}
	if ns.History then ns.History:RecordDuel(rec) end
	if ns.Progress then ns.Progress:OnDuel(won) end
	self:End(rec)
end

function Duels:Init()
	local events = self.events
	events.DUEL_REQUESTED = ns:On("DUEL_REQUESTED", function(opponent)
		opponent = plain(opponent, "string")
		Duels:Start(opponent)
	end)
	events.DUEL_INBOUNDS = ns:On("DUEL_INBOUNDS", function()
		if not Duels.active then Duels:Start() end
	end)
	events.DUEL_FINISHED = ns:On("DUEL_FINISHED", function()
		-- Defer slightly so the CHAT_MSG_SYSTEM outcome can still read active.class,
		-- without accidentally ending a brand-new duel started in the meantime.
		local finishing = Duels.active
		if not finishing then return end
		C_Timer.After(0.5, function()
			if Duels.active == finishing then Duels:End(nil) end
		end)
	end)
	events.CHAT_MSG_SYSTEM = ns:On("CHAT_MSG_SYSTEM", function(text) Duels:OnSystemMessage(text) end)
end
