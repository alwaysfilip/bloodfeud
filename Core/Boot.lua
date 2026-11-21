-- Loaded last: start everything up and provide the slash commands.
local ADDON, ns = ...

local Names, Util = ns.Names, ns.Util
local L = ns.L

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function showLog()
	local session = ns.session
	if not session then
		ns:Print(L.MSG_NO_GUILD)
		return
	end
	local log = session.store.data.log
	if #log == 0 then
		ns:Print("No changes recorded yet.")
		return
	end
	for i = math.max(1, #log - 14), #log do
		local e = log[i]
		local id = tostring(e.id):gsub("^%a:", ""):gsub("/", " by ")
		ns:Print(("%s  %s  %s  writer %s%s"):format(date("%m-%d %H:%M", e.t), e.a, id, Names.Display(e.by or "?"),
			e.via and (", relayed by " .. Names.Display(e.via)) or ""))
	end
end

local function showProbe(lines)
	ns:Print("Probe saved. Type /reload so it is written to disk.")
	local W = ns.W
	local f = ns.probeFrame
	if not f then
		f = W.Panel(UIParent, "BloodFeudProbeFrame")
		ns.probeFrame = f
		f:SetSize(620, 460)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		W.Movable(f)
		tinsert(UISpecialFrames, "BloodFeudProbeFrame")
		local close = W.Button(f, L.CLOSE, 90, 24)
		close:SetPoint("BOTTOMRIGHT", -12, 10)
		close:SetScript("OnClick", function() f:Hide() end)
		local scroll = CreateFrame("ScrollFrame", nil, f)
		scroll:SetPoint("TOPLEFT", 12, -12)
		scroll:SetPoint("BOTTOMRIGHT", -12, 44)
		scroll:EnableMouseWheel(true)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFontObject("ChatFontNormal")
		edit:SetWidth(590)
		edit:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(edit)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local range = self:GetVerticalScrollRange()
			self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
		end)
		f.edit = edit
	end
	f.edit:SetText(table.concat(lines, "\n"))
	f:Show()
	f.edit:HighlightText()
	f.edit:SetFocus()
end

local SETTINGS = { banner = true, sound = true, chat = true, nameplates = true, guildAlerts = true, sightSend = true,
	sightShow = true, revenge = true, bountyAlerts = true, radar = true, radarAuto = true, radarSound = true, debug = true }
-- Numeric settings: name -> { min, max }
local NUMBERS = { revengeCount = { 2, 10 }, revengeWindow = { 5, 120 } }

--- /feud score [Name]: one enemy in detail, or my top feuds.
local function showScore(rest)
	local book = ns.Feuds:Book() or {}
	local name = Names.Canon(rest or "", true)
	if name then
		local key = Names.Key(name)
		local e = book[key]
		ns:Print(L.SCORE_MINE:format(Names.Display(e and e.n or name), e and e.k or 0, e and e.d or 0))
		local session = ns.session
		if session and session.store:IsListed(key) then
			local kills, deaths, list = session.store:Score(key)
			ns:Print(L.SCORE_GUILD_LINE:format(kills, deaths))
			for i = 1, math.min(#list, 8) do
				local rec = list[i]
				ns:Print("   " .. L.SCORE_BY:format(Names.Display(rec.author), rec.kills, rec.deaths))
			end
		end
		return
	end
	local keys = {}
	for key, e in pairs(book) do
		if (e.k or 0) + (e.d or 0) > 0 then keys[#keys + 1] = key end
	end
	if #keys == 0 then
		ns:Print(L.SCORE_NONE)
		return
	end
	table.sort(keys, function(a, b)
		local ea, eb = book[a], book[b]
		if ea.d + ea.k ~= eb.d + eb.k then return ea.d + ea.k > eb.d + eb.k end
		return a < b
	end)
	ns:Print(L.SCORE_TOP)
	for i = 1, math.min(#keys, 10) do
		local e = book[keys[i]]
		ns:Print("   " .. L.SCORE_BY:format(Names.Display(e.n or keys[i]), e.k, e.d))
	end
end

--- /feud bounty [points] [gold] [note] with an enemy targeted (like /feud add,
--- everything typed is about the target), otherwise /feud bounty Name
--- [points] [gold] [note]. "<Guild Name> ..." is a guild either way. Gold is
--- a number with "g" or "gold" after it: "50g", "50 gold".
local function postBounty(rest)
	local guild, tail = rest:match("^<(.-)>%s*(.*)$")
	local scope, name = "p", nil
	if guild then
		scope, name = "g", guild
	else
		local ok, info = pcall(ns.Detect.Inspect, "target")
		if ok and info then
			name, tail = info.name, rest
		else
			local first, after = rest:match("^(%S+)%s*(.*)$")
			if first and not first:match("^%d+$") then name, tail = first, after end
		end
	end
	if not name then
		ns.BountyDialog:Open({})
		return
	end
	tail = tail or ""
	-- A bare number is the points, a number with "g" the gold, in either
	-- order; whatever follows is the note.
	local points, gold
	for _ = 1, 2 do
		local g, afterGold = tail:match("^(%d+)%s*gold%f[%A]%s*(.*)$")
		if not g then g, afterGold = tail:match("^(%d+)%s*g%f[%A]%s*(.*)$") end
		local p, afterPoints = tail:match("^(%d+)%f[%D]%s*(.*)$")
		if g and not gold then
			gold, tail = g, afterGold
		elseif p and not g and not points then
			points, tail = p, afterPoints
		else
			break
		end
	end
	-- Whatever was left out keeps the value of a bounty I already have up.
	ns:PostBounty(scope, name, tonumber(points), tail ~= "" and tail or nil, tonumber(gold))
end

--- /feud rank: my rank; /feud rank set <n> <kills> <title> for officers.
local function rankCommand(rest)
	if rest:match("^set") then
		local n, kills, title = rest:match("^set%s+(%d+)%s+(%d+)%s*(.*)$")
		n = tonumber(n)
		if not n or n < 1 or n > ns.Codec.MAX_TIERS then
			ns:Print(L.RANK_USAGE:format(ns.Codec.MAX_TIERS))
		elseif ns:SetTier(n, kills, title) then
			ns:Print(L.MSG_RANKS_SAVED:format(1))
		end
		return
	end
	local st = ns.Progress:Stats()
	if not st then return end
	local rank, nextTier = ns.Progress:MyRank()
	ns:Print(L.MY_RANK:format(rank and rank.title or L.UNRANKED, st.kills))
	if nextTier then ns:Print(L.NEXT_RANK:format(nextTier.title, nextTier.kills - st.kills)) end
	ns.MainFrame:Show("m")
end

local function slash(input)
	input = Util.Clean(input or "", 300)
	local command, rest = input:match("^(%S+)%s*(.*)$")
	command = command and command:lower() or ""

	if command == "" then
		ns.MainFrame:Toggle()
	elseif command == "add" then
		local ok, info = pcall(ns.Detect.Inspect, "target")
		if ok and info then
			-- With an enemy targeted, everything typed is the reason.
			ns:AddPlayer(info.name, rest, info)
		else
			local name, reason = rest:match("^(%S+)%s*(.*)$")
			if name then
				ns:AddPlayer(Names.Canon(name, true), reason)
			else
				ns:Print(L.MSG_NO_TARGET)
			end
		end
	elseif command == "remove" or command == "rm" then
		local name = Names.Canon(rest, true)
		if name then ns:RemoveMine("r", Names.Key(name)) end
	elseif command == "guild" then
		local name, reason = rest:match("^(.-)%s*=%s*(.*)$")
		ns:AddGuild(name or rest, reason or "")
	elseif command == "sync" then
		ns:SyncNow()
		ns:Print("Asking the guild for changes.")
	elseif command == "score" then
		showScore(rest)
	elseif command == "radar" then
		ns.RadarUI:Toggle()
	elseif command == "bounty" then
		postBounty(rest)
	elseif command == "bounties" then
		ns.MainFrame:Show("b")
	elseif command == "debts" or command == "debt" then
		if ns.Debts:Remind() == 0 then ns:Print(L.DEBT_NONE) end
	elseif command == "rank" or command == "ranks" then
		rankCommand(rest)
	elseif command == "ach" or command == "achievements" then
		ns.MainFrame:Show("a")
	elseif command == "log" then
		showLog()
	elseif command == "probe" then
		ns:Print("Collecting, a few seconds...")
		ns.Probe:Run(showProbe)
	elseif command == "test" then
		ns.Alerts:Test()
	elseif command == "options" or command == "config" then
		ns:OpenOptions()
	elseif command == "set" then
		local key, value = rest:match("^(%S+)%s*(%S*)$")
		local range = key and NUMBERS[key]
		local number = tonumber(value)
		if key and SETTINGS[key] then
			ns.settings[key] = (value == "on" or value == "1" or value == "true")
			ns:Print(key .. " = " .. tostring(ns.settings[key]))
			if key:find("^radar") then ns.RadarUI:Update() end
		elseif range and number then
			ns.settings[key] = math.min(math.max(math.floor(number), range[1]), range[2])
			ns:Print(key .. " = " .. tostring(ns.settings[key]))
		else
			ns:Print("/feud set <banner|sound|chat|nameplates|guildAlerts|sightSend|sightShow|revenge|bountyAlerts|radar|"
				.. "radarAuto|radarSound|debug> on|off")
			ns:Print("/feud set revengeCount <2-10> · /feud set revengeWindow <5-120 minutes>")
		end
	else
		for i = 1, #L.HELP do ns:Print(L.HELP[i]) end
	end
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------

local MODULES = { "Roster", "Comm", "Detect", "Sightings", "Feuds", "Progress", "Debts", "Radar", "MainFrame", "RadarUI",
	"Tooltip", "UnitMenu", "Nameplates", "Minimap", "Options" }

local function start()
	-- Each part starts on its own, so one failure does not take the rest down.
	for i = 1, #MODULES do
		local module = ns[MODULES[i]]
		ns.Safe(module.Init, module)
	end

	_G.SLASH_BLOODFEUD1 = "/feud"
	_G.SLASH_BLOODFEUD2 = "/bloodfeud"
	SlashCmdList["BLOODFEUD"] = function(input) ns.Safe(slash, input) end

	C_Timer.After(8, function()
		local session = ns.session
		if session and ns.settings.chat then
			local players, guilds = session.store:Counts()
			ns:Print(L.MSG_LOADED:format(players, guilds))
		end
	end)
end

ns:On("ADDON_LOADED", function(name)
	if name == ADDON then ns:InitDB() end
end)

ns:On("PLAYER_LOGIN", function()
	if not ns.db then ns:InitDB() end
	ns.Safe(start)
end)
