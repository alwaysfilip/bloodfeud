-- Battleground countdown timers and score-pace projections for WoW: Forever
-- (Warsong Gulch, Arathi Basin, Alterac Valley, Darkspear Islands).
-- Everything is derived from Forever-safe sources: BG system chat announcements,
-- GetAreaSpiritHealerTime() and C_UIWidgetManager.
local _, ns = ...

local Util = ns.Util
local floor = math.floor

local BGTimers = {
	bars = {}, -- id -> { id, label, kind, startedAt, endsAt, duration, side }
	projection = nil, -- { winner, eta, aScore, hScore, maxScore, aBases, hBases, basesNeeded }
	samples = {}, -- recent { t, a, h, max, aBases, hBases }
	poiStates = {}, -- poiID -> last seen contested/assaulted state
	demo = false,
	events = {},
}
ns.BGTimers = BGTimers

-- Capture durations (seconds) by BG key.
local CAP_DURATION = { ab = 60, av = 240, ds = 60, other = 60 }
local FLAG_RESPAWN = { wsg = 23, ds = 15, other = 20 }
local FLAG_DROP = 10
local REZ_CYCLE = 30

local function plain(value, kind)
	if value == nil or Util.IsSecret(value) then return nil end
	if kind and type(value) ~= kind then return nil end
	return value
end

function BGTimers:Start(id, label, duration, kind, side)
	local now = GetTime()
	self.bars[id] = {
		id = id, label = label, kind = kind or "base", side = side or "neutral",
		startedAt = now, endsAt = now + duration, duration = duration,
	}
	ns:Fire("BGTIMERS_CHANGED")
end

function BGTimers:Stop(id)
	if self.bars[id] then
		self.bars[id] = nil
		ns:Fire("BGTIMERS_CHANGED")
	end
end

function BGTimers:Clear()
	self.bars = {}
	self.projection = nil
	self.samples = {}
	self.poiStates = {}
	ns:Fire("BGTIMERS_CHANGED")
end

--- Toggle sample bars so the player can position the window outside a BG.
function BGTimers:SetDemo(on)
	self.demo = on and true or false
	ns:Fire("BGTIMERS_CHANGED")
end

local function sideFromEvent(event, text)
	if event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" then return "alliance" end
	if event == "CHAT_MSG_BG_SYSTEM_HORDE" then return "horde" end
	local lo = text:lower()
	if lo:find("alliance", 1, true) then return "alliance" end
	if lo:find("horde", 1, true) then return "horde" end
	return "neutral"
end

local function cleanBase(raw)
	if type(raw) ~= "string" then return nil end
	raw = raw:gsub("^the ", ""):gsub("[%p%s]+$", "")
	raw = Util.Clean(raw, 40)
	return raw ~= "" and raw or nil
end

--- Parse BG chat announcements for gates, base captures and flag timers.
function BGTimers:OnBGChat(event, text)
	if not (ns.Battleground and ns.Battleground.active) then return end
	text = plain(text, "string")
	if not text then return end
	local lo = text:lower()
	local mapKey = ns.Battleground.mapKey or "other"

	-- 1. Starting gate countdown
	if lo:find("has begun", 1, true) or lo:find("let the battle", 1, true) then
		self:Stop("gate")
		return
	end
	if lo:find("battle for", 1, true) or lo:find("begins in", 1, true) or lo:find("starts in", 1, true) then
		if lo:find("2 minute", 1, true) then
			self:Start("gate", ns.L.TIMER_GATE, 120, "gate", "neutral")
			return
		elseif lo:find("1 minute", 1, true) then
			self:Start("gate", ns.L.TIMER_GATE, 60, "gate", "neutral")
			return
		elseif lo:find("30 second", 1, true) then
			self:Start("gate", ns.L.TIMER_GATE, 30, "gate", "neutral")
			return
		end
	end

	-- 2. Base captures (AB, AV, Darkspear Islands — with or without "the")
	local base = text:match("claims ([^!%.]+)") or text:match("assaulted ([^!%.]+)")
		or text:match("is capturing ([^!%.]+)")
		or text:match("^([^!%.]+) is under attack")
	if base then
		base = cleanBase(base)
		if base then
			local id = "base:" .. Util.Fold(base)
			local dur = CAP_DURATION[mapKey] or 60
			self:Start(id, base, dur, "base", sideFromEvent(event, text))
		end
		return
	end

	local doneBase = text:match("has defended ([^!%.]+)") or text:match("has taken ([^!%.]+)")
		or text:match("captured ([^!%.]+)") or text:match("^([^!%.]+) was taken")
		or text:match("^([^!%.]+) was defended") or text:match("^([^!%.]+) was destroyed")
	if doneBase and not doneBase:lower():find("flag", 1, true) then
		doneBase = cleanBase(doneBase)
		if doneBase then self:Stop("base:" .. Util.Fold(doneBase)) end
		return
	end

	-- 3. Flag timers (WSG & Darkspear Islands)
	local capFlag = text:match("captured the (%a+) [Ff]lag")
	if capFlag or lo:find("captured the flag", 1, true) then
		self:Stop("flag:drop:alliance")
		self:Stop("flag:drop:horde")
		self:Stop("flag:drop:neutral")
		self:Start("flag:respawn", ns.L.TIMER_FLAG_RESPAWN, FLAG_RESPAWN[mapKey] or 20, "flag", "neutral")
		return
	end
	local dropFlag = text:match("[Tt]he (%a+) [Ff]lag was dropped")
	if dropFlag then
		local side = dropFlag:lower()
		self:Start("flag:drop:" .. side, ns.L.TIMER_FLAG_DROP:format(dropFlag), FLAG_DROP, "flag", side)
		return
	end
	if lo:find("flag has been dropped", 1, true) then
		self:Start("flag:drop:neutral", ns.L.TIMER_FLAG_DROP:format("Flag"), FLAG_DROP, "flag", "neutral")
		return
	end
	local pickFlag = text:match("[Tt]he (%a+) [Ff]lag was picked up")
		or text:match("[Tt]he (%a+) [Ff]lag was returned")
	if pickFlag then
		self:Stop("flag:drop:" .. pickFlag:lower())
		self:Stop("flag:respawn")
		return
	end
	if lo:find("has taken the flag", 1, true) or lo:find("flag has been reset", 1, true) then
		self:Stop("flag:drop:neutral")
		self:Stop("flag:respawn")
	end
end

--- Poll GetAreaSpiritHealerTime() for the exact graveyard resurrection wave.
function BGTimers:PollRez()
	if not (ns.Battleground and ns.Battleground.active) then return end
	if not _G.GetAreaSpiritHealerTime then return end
	local ok, sec = pcall(_G.GetAreaSpiritHealerTime)
	sec = ok and plain(sec, "number") or 0
	if sec > 0 and sec <= 60 then
		local now = GetTime()
		local cur = self.bars.rez
		-- Only update if missing or drifted by more than a second.
		if not cur or math.abs((cur.endsAt - now) - sec) > 1.2 then
			self.bars.rez = {
				id = "rez", label = ns.L.TIMER_REZ, kind = "rez", side = "rez",
				startedAt = now - (REZ_CYCLE - sec), endsAt = now + sec, duration = REZ_CYCLE,
			}
			ns:Fire("BGTIMERS_CHANGED")
		end
	elseif self.bars.rez then
		self:Stop("rez")
	end
end

--- Fallback base-capture detection via C_AreaPoiInfo for mid-match joins or
--- battlegrounds whose POI descriptions report assaulted / contested states.
function BGTimers:PollPOI()
	local bg = ns.Battleground
	if not (bg and bg.active) then return end
	local mapApi, poiApi = _G.C_Map, _G.C_AreaPoiInfo
	if not (mapApi and mapApi.GetBestMapForUnit and poiApi and poiApi.GetAreaPOIForMap and poiApi.GetAreaPOIInfo) then
		return
	end
	local okM, mapID = pcall(mapApi.GetBestMapForUnit, "player")
	mapID = okM and plain(mapID, "number")
	if not mapID then return end
	local okP, ids = pcall(poiApi.GetAreaPOIForMap, mapID)
	if not (okP and type(ids) == "table") then return end

	local mapKey = bg.mapKey or "other"
	for i = 1, #ids do
		local poiID = plain(ids[i], "number")
		if poiID then
			local okI, info = pcall(poiApi.GetAreaPOIInfo, mapID, poiID)
			if okI and type(info) == "table" then
				local name = cleanBase(plain(info.name, "string"))
				local desc = (plain(info.description, "string") or ""):lower()
				local atlas = (plain(info.atlasName, "string") or ""):lower()
				local contested = desc:find("conflict", 1, true) or desc:find("assault", 1, true)
					or desc:find("contest", 1, true) or atlas:find("conflict", 1, true)
					or atlas:find("assault", 1, true)
				local prev = self.poiStates[poiID]
				if name then
					local barId = "base:" .. Util.Fold(name)
					if contested and not prev then
						self.poiStates[poiID] = true
						if not self.bars[barId] then
							local side = desc:find("alliance", 1, true) and "alliance"
								or (desc:find("horde", 1, true) and "horde" or "neutral")
							self:Start(barId, name, CAP_DURATION[mapKey] or 60, "base", side)
						end
					elseif not contested and prev then
						self.poiStates[poiID] = nil
						self:Stop(barId)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Score pace & win projection (Arathi Basin and Darkspear Islands)
---------------------------------------------------------------------------

local function readWidgets()
	local mgr = _G.C_UIWidgetManager
	if not (mgr and mgr.GetAllWidgetsBySetID) then return nil end
	local setID = mgr.GetTopCenterWidgetSetID and select(2, pcall(mgr.GetTopCenterWidgetSetID)) or 1
	local ok, list = pcall(mgr.GetAllWidgetsBySetID, setID)
	if not (ok and type(list) == "table") then return nil end

	local aScore, hScore, maxScore, aBases, hBases
	for i = 1, #list do
		local w = list[i]
		local id = type(w) == "table" and w.widgetID
		if id then
			if mgr.GetDoubleStatusBarWidgetVisualizationInfo then
				local okB, bar = pcall(mgr.GetDoubleStatusBarWidgetVisualizationInfo, id)
				if okB and type(bar) == "table" then
					local lv, rv, lm = plain(bar.leftBarValue, "number"), plain(bar.rightBarValue, "number"),
						plain(bar.leftBarMax, "number")
					if lv and rv and lm and lm >= 500 then
						aScore, hScore, maxScore = lv, rv, lm
					end
				end
			end
			local txt
			if mgr.GetIconAndTextWidgetVisualizationInfo then
				local okT, info = pcall(mgr.GetIconAndTextWidgetVisualizationInfo, id)
				if okT and type(info) == "table" then txt = plain(info.text, "string") end
			end
			if not txt and mgr.GetTextWithStateWidgetVisualizationInfo then
				local okT, info = pcall(mgr.GetTextWithStateWidgetVisualizationInfo, id)
				if okT and type(info) == "table" then txt = plain(info.text, "string") end
			end
			if txt then
				local bases, cur, cap = txt:match("[Bb]ases:%s*(%d+).-(%d+)%s*/%s*(%d+)")
				if not cur then cur, cap = txt:match("(%d+)%s*/%s*(%d+)") end
				if cur and cap and tonumber(cap) >= 500 then
					local sc, mx, bs = tonumber(cur), tonumber(cap), bases and tonumber(bases)
					maxScore = mx
					local loTxt = txt:lower()
					if loTxt:find("alliance", 1, true) then
						aScore, aBases = sc, bs or aBases
					elseif loTxt:find("horde", 1, true) then
						hScore, hBases = sc, bs or hBases
					elseif aScore == nil then
						aScore, aBases = sc, bs or aBases
					else
						hScore, hBases = sc, bs or hBases
					end
				end
			end
		end
	end
	if aScore and hScore and maxScore then
		return { a = aScore, h = hScore, max = maxScore, aBases = aBases, hBases = hBases }
	end
	return nil
end

--- Update score-pace projection from live UI widgets (or an explicit sample).
function BGTimers:PollScore(explicit)
	local bg = ns.Battleground
	if not explicit and not (bg and bg.active and (bg.mapKey == "ab" or bg.mapKey == "ds")) then
		self.projection = nil
		return
	end
	local cur = explicit or readWidgets()
	if not cur then return end
	local now = GetTime()
	local samples = self.samples
	samples[#samples + 1] = { t = now, a = cur.a, h = cur.h, max = cur.max, aBases = cur.aBases, hBases = cur.hBases }
	while #samples > 12 do table.remove(samples, 1) end

	-- Find the oldest sample at least 4s old (or the first sample) to estimate rate.
	local base = samples[1]
	for i = #samples - 1, 1, -1 do
		if now - samples[i].t >= 4 then
			base = samples[i]
			break
		end
	end
	local dt = now - base.t
	local aRate, hRate = 0, 0
	if dt >= 2 then
		aRate = math.max(0, (cur.a - base.a) / dt)
		hRate = math.max(0, (cur.h - base.h) / dt)
	end
	if aRate == 0 and hRate == 0 then
		self.projection = { aScore = cur.a, hScore = cur.h, maxScore = cur.max, aBases = cur.aBases, hBases = cur.hBases }
		ns:Fire("BGTIMERS_CHANGED")
		return
	end

	local aEta = aRate > 0 and ((cur.max - cur.a) / aRate) or math.huge
	local hEta = hRate > 0 and ((cur.max - cur.h) / hRate) or math.huge
	local winner, eta
	if aEta <= hEta then
		winner, eta = "Alliance", aEta
	else
		winner, eta = "Horde", hEta
	end

	local myFaction = ns.Detect and ns.Detect.MyFaction()
	local totalBases = (bg and bg.mapKey == "ds") and 4 or 5
	local basesNeeded
	if myFaction and winner ~= myFaction and eta < math.huge and eta > 0 then
		-- How many bases we need to outpace the opponent before they finish.
		local myScore = (myFaction == "Alliance") and cur.a or cur.h
		local needRate = (cur.max - myScore) / eta
		local oppBases = (myFaction == "Alliance") and cur.hBases or cur.aBases
		local oppRate = (myFaction == "Alliance") and hRate or aRate
		if oppBases and oppBases > 0 and oppRate > 0 then
			local perBase = oppRate / oppBases
			basesNeeded = math.min(totalBases, math.max(1, math.ceil(needRate / perBase)))
		end
	end

	self.projection = {
		winner = winner, eta = floor(eta + 0.5),
		aScore = cur.a, hScore = cur.h, maxScore = cur.max,
		aBases = cur.aBases, hBases = cur.hBases, basesNeeded = basesNeeded,
	}
	ns:Fire("BGTIMERS_CHANGED")
end

--- Active timers sorted by soonest expiry first.
function BGTimers:List()
	local now = GetTime()
	if self.demo then
		return {
			{ id = "demo1", label = "Blacksmith", kind = "base", side = "alliance",
				startedAt = now - 18, endsAt = now + 42, duration = 60 },
			{ id = "demo2", label = "Abandoned Tower", kind = "base", side = "horde",
				startedAt = now - 40, endsAt = now + 20, duration = 60 },
			{ id = "demo3", label = ns.L.TIMER_REZ, kind = "rez", side = "rez",
				startedAt = now - 12, endsAt = now + 18, duration = 30 },
		}
	end
	local out = {}
	for id, bar in pairs(self.bars) do
		if bar.endsAt <= now then
			self.bars[id] = nil
		else
			out[#out + 1] = bar
		end
	end
	table.sort(out, function(a, b)
		if a.endsAt ~= b.endsAt then return a.endsAt < b.endsAt end
		return a.id < b.id
	end)
	return out
end

function BGTimers:Init()
	local events = self.events
	for _, ev in ipairs({ "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_BG_SYSTEM_NEUTRAL",
		"CHAT_MSG_MONSTER_YELL" }) do
		events[ev] = ns:On(ev, function(text) BGTimers:OnBGChat(ev, text) end)
	end
	events.UPDATE_UI_WIDGET = ns:On("UPDATE_UI_WIDGET", function() BGTimers:PollScore() end)
	ns:Listen("BG_STATE_CHANGED", function(active)
		if not active then BGTimers:Clear() end
	end)
	C_Timer.NewTicker(1, function()
		if ns.Battleground and ns.Battleground.active then
			ns.Safe(BGTimers.PollRez, BGTimers)
			ns.Safe(BGTimers.PollPOI, BGTimers)
			ns.Safe(BGTimers.PollScore, BGTimers)
		end
	end)
end
