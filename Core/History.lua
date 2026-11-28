-- Personal PvP match and duel history, plus aggregate statistics across Open
-- World, Battlegrounds and Duels. Stored locally per character in
-- BusinessMeetingDB.history.
local _, ns = ...

local Names = ns.Names
local floor = math.floor

local History = {}
ns.History = History

History.MAX_BGS = 200
History.MAX_DUELS = 200

--- Per-character history store: { bgs = {...}, duels = {...} }.
function History:Book()
	local me = Names.Me()
	if not me or not ns.db then return nil end
	ns.db.history = type(ns.db.history) == "table" and ns.db.history or {}
	local key = Names.Key(me)
	local book = ns.db.history[key]
	if type(book) ~= "table" then
		book = { bgs = {}, duels = {} }
		ns.db.history[key] = book
	else
		book.bgs = type(book.bgs) == "table" and book.bgs or {}
		book.duels = type(book.duels) == "table" and book.duels or {}
	end
	return book
end

--- Save a completed battleground match (newest first).
function History:RecordBG(match)
	local book = self:Book()
	if not book or type(match) ~= "table" then return nil end
	match.t = match.t or GetServerTime()
	match.key = match.key or ("bg:" .. tostring(match.t) .. ":" .. tostring(#book.bgs + 1))
	table.insert(book.bgs, 1, match)
	while #book.bgs > History.MAX_BGS do
		table.remove(book.bgs)
	end
	ns:Fire("HISTORY_CHANGED")
	return match
end

--- Save a finished 1v1 duel (newest first).
function History:RecordDuel(duel)
	local book = self:Book()
	if not book or type(duel) ~= "table" then return nil end
	duel.t = duel.t or GetServerTime()
	duel.key = duel.key or ("duel:" .. tostring(duel.t) .. ":" .. tostring(#book.duels + 1))
	table.insert(book.duels, 1, duel)
	while #book.duels > History.MAX_DUELS do
		table.remove(book.duels)
	end
	ns:Fire("HISTORY_CHANGED")
	return duel
end

function History:BGList()
	local book = self:Book()
	return book and book.bgs or {}
end

function History:DuelList()
	local book = self:Book()
	return book and book.duels or {}
end

--- Format seconds as "14:05" or "1:02:15".
function History.FormatDuration(seconds)
	seconds = floor(math.max(seconds or 0, 0))
	local h = floor(seconds / 3600)
	local m = floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
	return ("%d:%02d"):format(m, s)
end

--- Format large numbers compactly: 124500 -> "124.5k".
function History.ShortNumber(n)
	n = floor(n or 0)
	if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
	if n >= 10000 then return ("%.1fk"):format(n / 1000) end
	return tostring(n)
end

--- Aggregate statistics across Open World, Battlegrounds and Duels.
function History:Summary()
	local st = ns.Progress and ns.Progress:Stats() or {}
	local owKills, owDeaths = st.kills or 0, st.deaths or 0
	local bgKills, bgDeaths = st.bgKills or 0, st.bgDeaths or 0
	local bgs = self:BGList()
	local duels = self:DuelList()

	local bgWins, bgLosses, totalHonor, totalDur, bestKB = 0, 0, 0, 0, st.bgBestKB or 0
	local byMap = {}
	for i = 1, #bgs do
		local m = bgs[i]
		if m.win == true then
			bgWins = bgWins + 1
		elseif m.win == false then
			bgLosses = bgLosses + 1
		end
		local honor = m.honor or 0
		local dur = m.dur or 0
		totalHonor = totalHonor + honor
		totalDur = totalDur + dur
		if (m.kb or 0) > bestKB then bestKB = m.kb end
		local mapName = m.map or "Battleground"
		local entry = byMap[mapName]
		if not entry then
			entry = { name = mapName, mapKey = m.mapKey, games = 0, wins = 0, losses = 0, kb = 0, d = 0, honor = 0 }
			byMap[mapName] = entry
		end
		entry.games = entry.games + 1
		if m.win == true then entry.wins = entry.wins + 1 elseif m.win == false then entry.losses = entry.losses + 1 end
		entry.kb = entry.kb + (m.kb or 0)
		entry.d = entry.d + (m.d or 0)
		entry.honor = entry.honor + honor
	end
	local decided = bgWins + bgLosses
	local bgTotal = #bgs
	local avgHonor = bgTotal > 0 and floor(totalHonor / bgTotal + 0.5) or 0
	local honorPerHour = totalDur >= 60 and floor(totalHonor * 3600 / totalDur + 0.5) or 0

	local duelWins = math.max(st.duelWins or 0, 0)
	local duelLosses = math.max(st.duelLosses or 0, 0)
	local duelByClass, duelByOpp = {}, {}
	for i = 1, #duels do
		local d = duels[i]
		if d.class then
			local c = duelByClass[d.class] or { w = 0, l = 0 }
			duelByClass[d.class] = c
			if d.won then c.w = c.w + 1 else c.l = c.l + 1 end
		end
		if d.key then
			local o = duelByOpp[d.key] or { name = d.opponent, class = d.class, w = 0, l = 0 }
			duelByOpp[d.key] = o
			if d.won then o.w = o.w + 1 else o.l = o.l + 1 end
		end
	end
	local duelTotal = duelWins + duelLosses

	return {
		owKills = owKills, owDeaths = owDeaths,
		bgKills = bgKills, bgDeaths = bgDeaths,
		totalKills = owKills + bgKills, totalDeaths = owDeaths + bgDeaths,
		bgTotal = bgTotal, bgWins = bgWins, bgLosses = bgLosses,
		bgWinRate = decided > 0 and floor(bgWins * 100 / decided + 0.5) or nil,
		totalHonor = totalHonor, avgHonor = avgHonor, honorPerHour = honorPerHour, bestKB = bestKB,
		byMap = byMap,
		duelTotal = duelTotal, duelWins = duelWins, duelLosses = duelLosses,
		duelWinRate = duelTotal > 0 and floor(duelWins * 100 / duelTotal + 0.5) or nil,
		duelBest = st.duelBest or 0,
		duelByClass = duelByClass, duelByOpponent = duelByOpp,
	}
end
