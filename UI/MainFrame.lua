-- The main window, in six tabs:
--   Players       who is Kill on Sight, why, who says so, where last seen
--   Guilds        enemy guilds on the list (officers)
--   Bounties      prices on enemy heads, and who has collected
--   Ranks         every guildmate's kills, rank and bounty points
--   Achievements  what you have earned, and how many guildmates have
--   Addon         which guildmates run Blood Feud, and on which version
-- Each tab describes its columns, rows and buttons in TABS below; the window
-- itself is shared.
local _, ns = ...

local W, Fmt, Names, Util, Roster = ns.W, ns.Fmt, ns.Names, ns.Util, ns.Roster
local L = ns.L

local Main = { tab = "r", offset = 0, items = {}, selected = nil, stale = true }
ns.MainFrame = Main

local WIDTH, HEIGHT = 960, 520
local PAD = 14
local ROW_H, ROWS = 24, 14
local LIST_TOP = 118
local MAX_COLS = 7
local TAB_ORDER = { "r", "g", "b", "m", "a", "u" }

local function grey(text)
	return Fmt.Color(Fmt.GREY, text)
end

local function more(subject)
	return #subject.reports > 1 and grey(L.MORE:format(#subject.reports - 1)) or ""
end

local function contains(query, ...)
	for i = 1, select("#", ...) do
		local text = select(i, ...)
		if text and Util.Fold(text):find(query, 1, true) then return true end
	end
	return false
end

--- A listed player the way the bounty lookups want them: under the name they
--- go by now. Their list key (a first name, or an older name) goes alongside.
local function bountyInfo(subject)
	return { key = Names.Key(subject.name), name = subject.name, guild = subject.facts and subject.facts.guild }
end

local function bountyTarget(rec)
	if rec.scope == "g" then return Fmt.Color(Fmt.AMBER, "<" .. rec.name .. ">") end
	return Names.Display(rec.name)
end

local GREEN = "ff8fd18f"

--- Where the gold of a won bounty stands: "Kari Frost · owed, 36 h left".
local function debtStatus(debt, now)
	local text
	if debt.state == "paid" then
		text = Fmt.Color(GREEN, L.DEBT_PAID)
	elseif debt.state == "settled" then
		text = grey(L.DEBT_SETTLED)
	elseif debt.state == "sent" then
		text = Fmt.Color(Fmt.GOLD, L.DEBT_SENT)
	elseif debt.late then
		text = Fmt.Color(Fmt.RED, L.DEBT_LATE)
	elseif debt.state == "disputed" then
		text = Fmt.Color(Fmt.AMBER, L.DEBT_DISPUTED:format(ns.Debts.Left(debt, now)))
	else
		text = Fmt.Color(Fmt.AMBER, L.DEBT_OWED:format(ns.Debts.Left(debt, now)))
	end
	return L.DEBT_WON_BY:format(Names.Display(debt.winner)) .. " · " .. text
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local TABS = {}

-- Players ------------------------------------------------------------------

TABS.r = {
	label = L.TAB_PLAYERS,
	columns = {
		{ title = L.COL_NAME, w = 180 }, { title = L.COL_LEVEL, w = 36 }, { title = L.COL_GUILD, w = 150 },
		{ title = L.COL_REASON, w = 220 }, { title = L.COL_BY, w = 110 }, { title = L.COL_SEEN, w = 150 },
		{ title = L.COL_SCORE, w = 60 },
	},
	items = function(s) return s.store:Players() end,
	sort = function(a, b)
		local sa, sb = a.seen and a.seen.at or 0, b.seen and b.seen.at or 0
		if sa ~= sb then return sa > sb end
		local na, nb = a.reports[#a.reports].at, b.reports[#b.reports].at
		if na ~= nb then return na > nb end
		return a.key < b.key
	end,
	matches = function(subject, q)
		if contains(q, subject.name, subject.facts and subject.facts.guild) then return true end
		for i = 1, #subject.reports do
			if contains(q, subject.reports[i].reason, subject.reports[i].author) then return true end
		end
		return false
	end,
	cells = function(subject)
		local facts, seen, first = subject.facts, subject.seen, subject.reports[1]
		local session = ns.session
		local guild = ""
		if facts and facts.guild then
			local listed = session and session.store:IsGuildListed(facts.guild)
			guild = listed and Fmt.Color(Fmt.AMBER, "<" .. facts.guild .. ">") or ("<" .. facts.guild .. ">")
		end
		local where = grey(L.NOT_SEEN)
		if seen then
			local zone = Fmt.Zone(seen.map)
			where = Fmt.Ago(seen.at) .. (zone and (" · " .. zone) or "")
		end
		local name = Fmt.PlayerName(subject)
		if session and ns.Bounties:Worth(bountyInfo(subject), subject.key) > 0 then
			name = name .. Fmt.Color(Fmt.GOLD, " $")
		end
		return {
			name, facts and facts.level and tostring(facts.level) or grey("??"), guild,
			first.reason .. more(subject), Names.Display(first.author) .. more(subject), where,
			Fmt.Score(subject.kills, subject.deaths),
		}
	end,
	empty = L.EMPTY_PLAYERS,
}

-- Guilds -------------------------------------------------------------------

TABS.g = {
	label = L.TAB_GUILDS,
	columns = {
		{ title = L.COL_GUILD, w = 250 }, { title = L.COL_REASON, w = 360 }, { title = L.COL_BY, w = 170 },
		{ title = L.COL_ADDED, w = 116 },
	},
	items = function(s) return s.store:Guilds() end,
	sort = function(a, b) return a.key < b.key end,
	matches = function(subject, q)
		if contains(q, subject.name) then return true end
		for i = 1, #subject.reports do
			if contains(q, subject.reports[i].reason, subject.reports[i].author) then return true end
		end
		return false
	end,
	cells = function(subject)
		local first = subject.reports[1]
		return {
			Fmt.Color(Fmt.AMBER, "<" .. subject.name .. ">"), first.reason .. more(subject),
			Names.Display(first.author) .. more(subject), Fmt.Ago(first.at),
		}
	end,
	notice = L.OFFICER_ONLY,
	empty = L.EMPTY_GUILDS,
}

-- Bounties -----------------------------------------------------------------

TABS.b = {
	label = L.TAB_BOUNTIES,
	columns = {
		{ title = L.COL_TARGET, w = 190 }, { title = L.COL_POINTS, w = 54 }, { title = L.COL_GOLD, w = 60 },
		{ title = L.COL_REWARD, w = 140 }, { title = L.COL_POSTED_BY, w = 120 }, { title = L.COL_CLAIMS, w = 250 },
		{ title = L.COL_POSTED, w = 90 },
	},
	items = function(s) return s.store:Bounties(nil, nil, GetServerTime()) end,
	matches = function(view, q)
		local rec = view.rec
		if contains(q, rec.name, rec.reward, rec.author) then return true end
		for i = 1, #view.claims do
			if contains(q, view.claims[i].author) then return true end
		end
		return false
	end,
	cells = function(view)
		local rec = view.rec
		local gold = rec.gold or 0
		local claims = grey(gold > 0 and L.BOUNTY_OPEN or L.NO_CLAIMS)
		if view.debt then
			claims = debtStatus(view.debt, GetServerTime())
		elseif view.total > 0 then
			local parts = {}
			for i = 1, math.min(#view.claims, 3) do
				parts[#parts + 1] = Names.Display(view.claims[i].author) .. " " .. view.claims[i].count
			end
			claims = view.total .. "  " .. grey(table.concat(parts, ", "))
		end
		return {
			bountyTarget(rec), Fmt.Color(Fmt.GOLD, tostring(rec.points)),
			gold > 0 and Fmt.Color(Fmt.GOLD, L.GOLD_SHORT:format(gold)) or grey("–"),
			rec.reward ~= "" and rec.reward or grey("–"), Names.Display(rec.author), claims, Fmt.Ago(rec.at),
		}
	end,
	notice = L.BOUNTY_NOTICE,
	empty = L.EMPTY_BOUNTIES,
}

-- Ranks --------------------------------------------------------------------

TABS.m = {
	label = L.TAB_RANKS,
	columns = {
		{ title = L.COL_NAME, w = 190 }, { title = L.COL_RANK, w = 170 }, { title = L.COL_KILLS, w = 80 },
		{ title = L.COL_DEATHS, w = 80 }, { title = L.COL_STREAK, w = 100 }, { title = L.COL_BOUNTY_POINTS, w = 110 },
		{ title = L.COL_ACHIEVEMENTS, w = 120 },
	},
	items = function() return ns.Progress:Roll() end,
	matches = function(m, q)
		return contains(q, m.name, m.rank and m.rank.title, m.dishonored and L.DISHONORED)
	end,
	cells = function(m)
		local name = Names.Display(m.name)
		if m.me then name = Fmt.Color(Fmt.GOLD, name) end
		local rank, points = m.rank and m.rank.title or grey(L.UNRANKED), tostring(m.points)
		if m.dishonored then
			-- An unpaid bounty: no rank, and the bounty points count for nothing.
			rank, points = Fmt.Color(Fmt.RED, L.DISHONORED), Fmt.Color(Fmt.RED, "0")
		end
		return {
			name, rank, tostring(m.kills), tostring(m.deaths), tostring(m.best), points,
			tostring(ns.Progress.CountBits(m.ach)) .. grey(" / " .. #ns.Achievements),
		}
	end,
	notice = function()
		local st = ns.Progress:Stats()
		if not st then return "" end
		local rank, nextTier = ns.Progress:MyRank()
		local text = L.MY_RANK:format(rank and rank.title or L.UNRANKED, st.kills)
		if nextTier then text = text .. "   ·   " .. L.NEXT_RANK:format(nextTier.title, nextTier.kills - st.kills) end
		return text
	end,
	empty = L.EMPTY_RANKS,
}

-- Achievements -------------------------------------------------------------

TABS.a = {
	label = L.TAB_ACHIEVEMENTS,
	columns = {
		{ title = L.COL_ACHIEVEMENT, w = 200 }, { title = L.COL_DESCRIPTION, w = 420 }, { title = L.COL_EARNED, w = 130 },
		{ title = L.COL_GUILDMATES, w = 140 },
	},
	items = function(s)
		local st = ns.Progress:Stats() or { earned = {} }
		local members = s.store:Members()
		local out = {}
		for i, a in ipairs(ns.Achievements) do
			local others = 0
			for j = 1, #members do
				if members[j].akey ~= s.meKey and ns.Progress.Has(members[j].ach, i) then others = others + 1 end
			end
			out[i] = { key = i, a = a, earned = st.earned[i], others = others }
		end
		return out
	end,
	sort = function(x, y)
		if (x.earned ~= nil) ~= (y.earned ~= nil) then return x.earned ~= nil end
		return x.key < y.key
	end,
	matches = function(item, q) return contains(q, item.a.name, item.a.desc) end,
	cells = function(item)
		local name = item.earned and Fmt.Color(Fmt.GOLD, item.a.name) or grey(item.a.name)
		return {
			name, item.earned and item.a.desc or grey(item.a.desc),
			item.earned and Fmt.Ago(item.earned) or grey("–"),
			item.others > 0 and tostring(item.others) or grey("0"),
		}
	end,
	notice = function()
		local st = ns.Progress:Stats()
		local n = 0
		if st then for _ in pairs(st.earned) do n = n + 1 end end
		return L.ACH_PROGRESS:format(n, #ns.Achievements)
	end,
	empty = "",
}

-- Addon users -------------------------------------------------------------

TABS.u = {
	label = L.TAB_USERS,
	columns = {
		{ title = L.COL_NAME, w = 240 }, { title = L.COL_VERSION, w = 150 }, { title = L.COL_STATUS, w = 320 },
		{ title = L.COL_HEARD, w = 160 },
	},
	items = function() return ns.Users:List() end,
	matches = function(u, q) return contains(q, u.name, u.version) end,
	cells = function(u)
		local name = Names.Display(u.name)
		if u.me then name = Fmt.Color(Fmt.GOLD, name) end
		local status = u.online and Fmt.Color(GREEN, L.USER_ONLINE) or grey(L.USER_OFFLINE)
		if u.standing == "old" then
			status = status .. " · " .. Fmt.Color(Fmt.AMBER, L.USER_OLD)
		elseif u.standing == "new" then
			status = status .. " · " .. Fmt.Color(Fmt.AMBER, L.USER_NEW)
		end
		return { name, u.version or grey("?"), status, u.me and grey(L.USER_YOU) or Fmt.Ago(u.t) }
	end,
	notice = function()
		local sum = ns.Users:Summary()
		local text = sum.total > 0 and L.USERS_SUMMARY:format(sum.have, sum.total) or L.USERS_SUMMARY_PLAIN:format(sum.have)
		text = text .. "   ·   " .. L.USERS_ONLINE:format(sum.online)
		if sum.old > 0 then text = text .. "   ·   " .. Fmt.Color(Fmt.AMBER, L.USERS_OLD:format(sum.old)) end
		if sum.new > 0 then text = text .. "   ·   " .. Fmt.Color(Fmt.AMBER, L.USERS_NEW:format(sum.new)) end
		return text
	end,
	empty = "",
}

---------------------------------------------------------------------------
-- Row tooltips
---------------------------------------------------------------------------

local function tipSubject(subject)
	if subject.kind == "r" then
		GameTooltip:AddLine(Fmt.PlayerName(subject))
		local what = Fmt.Describe(subject.facts)
		if what ~= "" then GameTooltip:AddLine(what, 1, 1, 1) end
		if subject.facts and subject.facts.guild then GameTooltip:AddLine("<" .. subject.facts.guild .. ">", 1, 0.7, 0.28) end
	else
		GameTooltip:AddLine("<" .. subject.name .. ">", 1, 0.7, 0.28)
	end
	for i = 1, #subject.reports do
		local rec = subject.reports[i]
		GameTooltip:AddLine(" ")
		if rec.reason ~= "" then GameTooltip:AddLine("“" .. rec.reason .. "”", 1, 1, 1, true) end
		GameTooltip:AddLine(L.TIP_BY:format(Names.Display(rec.author), Fmt.Ago(rec.at)), 0.66, 0.65, 0.61)
	end
	if (subject.kills or 0) + (subject.deaths or 0) > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L.TIP_SCORE:format(subject.kills, subject.deaths), 1, 1, 1)
	end
	local s = ns.session
	if s and subject.kind == "r" then
		local bounty = ns.Bounties:Line(bountyInfo(subject), subject.key)
		if bounty then GameTooltip:AddLine(bounty, 0.94, 0.78, 0.37) end
	end
	local seen = subject.seen
	if seen then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L.TIP_SEEN:format(Fmt.Ago(seen.at), (Fmt.Zone(seen.map) and (" · " .. Fmt.Zone(seen.map)) or "")
			.. Fmt.Coords(seen.x, seen.y)) .. (seen.by and L.TIP_SEEN_BY:format(Names.Display(seen.by)) or ""),
			0.66, 0.65, 0.61, true)
	end
end

local function tipBounty(view)
	local rec = view.rec
	GameTooltip:AddLine(bountyTarget(rec))
	GameTooltip:AddLine(L.BOUNTY_WORTH:format(rec.points), 0.94, 0.78, 0.37)
	if (rec.gold or 0) > 0 then GameTooltip:AddLine(L.BOUNTY_GOLD_FIRST:format(rec.gold), 0.94, 0.78, 0.37, true) end
	if rec.reward ~= "" then GameTooltip:AddLine(L.BOUNTY_PROMISED:format(rec.reward), 1, 1, 1, true) end
	GameTooltip:AddLine(L.TIP_BY:format(Names.Display(rec.author), Fmt.Ago(rec.at)), 0.66, 0.65, 0.61)
	local debt = view.debt
	if debt then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(debtStatus(debt, GetServerTime()), 1, 1, 1, true)
		GameTooltip:AddLine(L.DEBT_WON_AT:format(Fmt.Ago(debt.at)), 0.66, 0.65, 0.61)
		if debt.open then GameTooltip:AddLine(L.DEBT_HOW, 0.66, 0.65, 0.61, true) end
	elseif #view.claims > 0 then
		GameTooltip:AddLine(" ")
		for i = 1, math.min(#view.claims, 10) do
			local c = view.claims[i]
			GameTooltip:AddDoubleLine(Names.Display(c.author), L.CLAIMS_N:format(c.count), 1, 1, 1, 0.79, 0.78, 0.74)
		end
	end
end

local function tipMember(m)
	GameTooltip:AddLine(Names.Display(m.name))
	if m.dishonored then
		GameTooltip:AddLine(L.TIP_DISHONORED:format(m.dishonored.gold, Names.Display(m.dishonored.winner)), 1, 0.54, 0.5, true)
	end
	GameTooltip:AddLine(m.rank and m.rank.title or L.UNRANKED, 0.94, 0.78, 0.37)
	GameTooltip:AddLine(L.MEMBER_LINE:format(m.kills, m.deaths, m.best, m.points), 1, 1, 1)
	local earned = {}
	for i, a in ipairs(ns.Achievements) do
		if ns.Progress.Has(m.ach, i) then earned[#earned + 1] = a.name end
	end
	if #earned > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(table.concat(earned, ", "), 0.79, 0.78, 0.74, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L.UPDATED:format(Fmt.Ago(m.ts)), 0.66, 0.65, 0.61)
end

local function tipAchievement(item)
	GameTooltip:AddLine(item.a.name, 0.94, 0.78, 0.37)
	GameTooltip:AddLine(item.a.desc, 1, 1, 1, true)
	local s = ns.session
	if not s then return end
	local who = {}
	for _, m in ipairs(s.store:Members()) do
		if m.akey ~= s.meKey and ns.Progress.Has(m.ach, item.key) then who[#who + 1] = Names.Display(m.author) end
	end
	if #who > 0 then
		table.sort(who)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L.ALSO_EARNED:format(table.concat(who, ", ")), 0.79, 0.78, 0.74, true)
	end
end

local function tipUser(u)
	GameTooltip:AddLine(Names.Display(u.name))
	GameTooltip:AddLine(L.USER_VERSION:format(u.version or "?"), 1, 1, 1)
	if u.standing == "old" then
		GameTooltip:AddLine(L.USER_OLD_TIP, 1, 0.7, 0.28, true)
	elseif u.standing == "new" then
		GameTooltip:AddLine(L.USER_NEW_TIP, 1, 0.7, 0.28, true)
	end
	if not u.me then GameTooltip:AddLine(L.USER_HEARD:format(Fmt.Ago(u.t)), 0.66, 0.65, 0.61) end
end

local function showRowTooltip(row)
	local item = row.item
	if not item then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local tab = Main.tab
	if tab == "u" then
		tipUser(item)
	elseif tab == "r" or tab == "g" then
		tipSubject(item)
	elseif tab == "b" then
		tipBounty(item)
	elseif tab == "m" then
		tipMember(item)
	else
		tipAchievement(item)
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function createRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
	row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetTexture(W.FLAT)
	row.bg:SetVertexColor(1, 1, 1, 0)
	row.cells = {}
	for c = 1, MAX_COLS do
		local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cell:SetJustifyH("LEFT")
		cell:SetWordWrap(false)
		row.cells[c] = cell
	end
	row:SetScript("OnEnter", function(self)
		self.hover = true
		Main:PaintRow(self)
		showRowTooltip(self)
	end)
	row:SetScript("OnLeave", function(self)
		self.hover = false
		Main:PaintRow(self)
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		local key = self.item and self.item.key
		Main.selected = (Main.selected ~= key) and key or nil
		Main:Render()
		Main:UpdateActions()
	end)
	return row
end

function Main:Build()
	local f = W.Panel(UIParent, "BloodFeudMainFrame")
	self.frame = f
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	W.Movable(f)
	f:Hide()
	tinsert(UISpecialFrames, "BloodFeudMainFrame")

	-- Header
	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", PAD, -10)
	icon:SetTexture(W.SKULL)
	local title = W.Label(f, "GameFontNormalLarge", ns.TITLE)
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	title:SetTextColor(0.94, 0.78, 0.37)
	f.subtitle = W.Label(f, "GameFontDisableSmall")
	f.subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)
	local close = W.Button(f, "X", 26, 22)
	close:SetPoint("TOPRIGHT", -PAD, -9)
	close:SetScript("OnClick", function() f:Hide() end)
	local options = W.Button(f, L.OPTIONS, 70, 22)
	options:SetPoint("RIGHT", close, "LEFT", -6, 0)
	options:SetScript("OnClick", function() ns:OpenOptions() end)
	local radar = W.Button(f, L.RADAR_TITLE, 70, 22)
	radar:SetPoint("RIGHT", options, "LEFT", -6, 0)
	radar:SetScript("OnClick", function() ns.RadarUI:Toggle() end)

	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetTexture(W.FLAT)
	rule:SetVertexColor(0.23, 0.20, 0.13, 1)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 1, -40)
	rule:SetPoint("TOPRIGHT", -1, -40)

	-- Tabs
	f.tabs = {}
	local prev
	for _, key in ipairs(TAB_ORDER) do
		local b = W.Button(f, TABS[key].label, 88, 26)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", PAD, -50) end
		b:SetScript("OnClick", function() Main:SetTab(key) end)
		f.tabs[key] = b
		prev = b
	end
	f.tabPlayers, f.tabGuilds = f.tabs.r, f.tabs.g

	f.add = W.Button(f, L.ADD_TARGET, 130, 26, "danger")
	f.add:SetPoint("TOPRIGHT", -PAD, -50)
	f.add:SetScript("OnClick", function() Main:OnAdd() end)

	f.search = W.EditBox(f, 170, 26, 40)
	f.search:SetPoint("RIGHT", f.add, "LEFT", -10, 0)
	f.search:SetScript("OnTextChanged", function()
		Main.offset = 0
		Main:Refresh()
	end)
	local searchLabel = W.Label(f, "GameFontDisableSmall", L.SEARCH)
	searchLabel:SetPoint("RIGHT", f.search, "LEFT", -6, 0)

	f.notice = W.Label(f, "GameFontDisableSmall")
	f.notice:SetPoint("TOPLEFT", PAD, -82)
	f.notice:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)

	-- Column headers
	f.heads = {}
	for c = 1, MAX_COLS do
		f.heads[c] = W.Label(f, "GameFontDisableSmall")
	end

	-- List
	local list = CreateFrame("Frame", nil, f)
	f.list = list
	list:SetPoint("TOPLEFT", PAD, -LIST_TOP)
	list:SetPoint("TOPRIGHT", -(PAD + 18), -LIST_TOP)
	list:SetHeight(ROWS * ROW_H)
	list:EnableMouseWheel(true)
	f.rows = {}
	for i = 1, ROWS do
		f.rows[i] = createRow(list, i)
	end
	f.empty = W.Label(list, "GameFontDisable")
	f.empty:SetPoint("CENTER")
	f.empty:SetJustifyH("CENTER")

	local slider = CreateFrame("Slider", nil, f, "BackdropTemplate")
	f.slider = slider
	slider:SetPoint("TOPRIGHT", -PAD, -LIST_TOP)
	slider:SetSize(12, ROWS * ROW_H)
	slider:SetOrientation("VERTICAL")
	W.Skin(slider, { 0.04, 0.04, 0.05 }, { 0.14, 0.15, 0.18 })
	slider:SetThumbTexture(W.FLAT)
	local thumb = slider:GetThumbTexture()
	thumb:SetSize(10, 36)
	thumb:SetVertexColor(0.69, 0.55, 0.24, 1)
	slider:SetMinMaxValues(0, 0)
	slider:SetValueStep(1)
	slider:SetValue(0)
	slider:SetScript("OnValueChanged", function(_, value)
		local offset = math.floor(value + 0.5)
		if offset ~= Main.offset then
			Main.offset = offset
			Main:Render()
		end
	end)
	list:SetScript("OnMouseWheel", function(_, delta)
		local low, high = slider:GetMinMaxValues()
		slider:SetValue(math.max(low, math.min(high, slider:GetValue() - delta * 3)))
	end)

	-- Actions on the selected row
	f.removeMine = W.Button(f, L.REMOVE_MINE, 150, 26)
	f.removeMine:SetPoint("BOTTOMLEFT", PAD, 34)
	f.removeMine:SetScript("OnClick", function() Main:OnRemoveMine() end)
	f.edit = W.Button(f, L.EDIT, 110, 26)
	f.edit:SetPoint("LEFT", f.removeMine, "RIGHT", 6, 0)
	f.edit:SetScript("OnClick", function() Main:OnEdit() end)
	f.bounty = W.Button(f, L.POST_BOUNTY, 130, 26)
	f.bounty:SetPoint("LEFT", f.edit, "RIGHT", 6, 0)
	f.bounty:SetScript("OnClick", function() Main:OnBounty() end)
	f.removeAll = W.Button(f, L.REMOVE_ALL, 210, 26, "danger")
	f.removeAll:SetPoint("LEFT", f.bounty, "RIGHT", 6, 0)
	f.removeAll:SetScript("OnClick", function() Main:OnRemoveAll() end)

	-- Footer
	local foot = f:CreateTexture(nil, "ARTWORK")
	foot:SetTexture(W.FLAT)
	foot:SetVertexColor(0.23, 0.20, 0.13, 1)
	foot:SetHeight(1)
	foot:SetPoint("BOTTOMLEFT", 1, 26)
	foot:SetPoint("BOTTOMRIGHT", -1, 26)
	f.status = W.Label(f, "GameFontDisableSmall")
	f.status:SetPoint("BOTTOMLEFT", PAD, 8)
	f.syncStatus = W.Label(f, "GameFontDisableSmall")
	f.syncStatus:SetPoint("BOTTOMRIGHT", -PAD, 8)
	f.syncStatus:SetJustifyH("RIGHT")

	local sinceRefresh, sinceStatus = 0, 0
	f:SetScript("OnShow", function()
		Main:Refresh()
	end)
	f:SetScript("OnUpdate", function(_, elapsed)
		sinceRefresh = sinceRefresh + elapsed
		sinceStatus = sinceStatus + elapsed
		if Main.stale and sinceRefresh > 0.3 then
			sinceRefresh = 0
			Main:Refresh()
		elseif sinceStatus > 1 then
			sinceStatus = 0
			Main:UpdateStatus()
			Main:UpdateActions()
		end
	end)
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

function Main:SetTab(tab)
	if self.tab == tab or not TABS[tab] then return end
	self.tab = tab
	self.offset = 0
	self.selected = nil
	self:Refresh()
end

--- Rebuild the visible list from the store.
function Main:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then
		self.stale = true
		return
	end
	self.stale = false
	local session = ns.session
	local tab = TABS[self.tab]
	local items = {}
	local query = Util.Fold(Util.Clean(f.search:GetText() or "", 60))
	if session then
		local all = tab.items(session)
		for i = 1, #all do
			if query == "" or tab.matches(all[i], query) then items[#items + 1] = all[i] end
		end
		if tab.sort then table.sort(items, tab.sort) end
	end
	self.items = items
	self.query = query

	local last = math.max(0, #items - ROWS)
	if self.offset > last then self.offset = last end
	f.slider:SetMinMaxValues(0, last)
	f.slider:SetValue(self.offset)
	f.slider:SetShown(last > 0)

	for key, b in pairs(f.tabs) do b:SetSelected(key == self.tab) end
	f.subtitle:SetText(L.SUBTITLE .. (session and (" · <" .. session.guild .. ">") or ""))
	local notice = tab.notice
	if type(notice) == "function" then notice = session and notice() or "" end
	f.notice:SetText(notice or "")

	local columns = tab.columns
	local x = 0
	for c = 1, MAX_COLS do
		local head, col = f.heads[c], columns[c]
		head:ClearAllPoints()
		if col then
			head:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + x + 4, -(LIST_TOP - 16))
			head:SetText(col.title:upper())
			head:Show()
			x = x + col.w
		else
			head:Hide()
		end
	end

	self:Render()
	self:UpdateStatus()
	self:UpdateActions()
end

function Main:PaintRow(row)
	local selected = row.item and row.item.key == self.selected
	if selected then
		row.bg:SetVertexColor(0.55, 0.16, 0.12, 0.45)
	elseif row.hover then
		row.bg:SetVertexColor(1, 1, 1, 0.07)
	else
		row.bg:SetVertexColor(1, 1, 1, (row.index % 2 == 0) and 0.025 or 0)
	end
end

--- Fill the visible rows from the current offset.
function Main:Render()
	local f = self.frame
	if not f then return end
	local tab = TABS[self.tab]
	local columns = tab.columns
	for i = 1, ROWS do
		local row = f.rows[i]
		local item = self.items[self.offset + i]
		row.item = item
		row.index = self.offset + i
		if item then
			local cells = tab.cells(item)
			local x = 0
			for c = 1, MAX_COLS do
				local cell, col = row.cells[c], columns[c]
				cell:ClearAllPoints()
				if col then
					cell:SetPoint("LEFT", row, "LEFT", x + 4, 0)
					cell:SetWidth(col.w - 8)
					cell:SetText(cells[c] or "")
					cell:Show()
					x = x + col.w
				else
					cell:Hide()
				end
			end
			self:PaintRow(row)
			row:Show()
		else
			row:Hide()
		end
	end
	if #self.items == 0 then
		local text = L.STATUS_NO_GUILD
		if ns.session then text = (self.query ~= "" and L.EMPTY_SEARCH) or tab.empty end
		f.empty:SetText(text)
		f.empty:Show()
	else
		f.empty:Hide()
	end
end

function Main:UpdateActions()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local session = ns.session
	local officer = session and Roster.AmOfficer() or false
	local tab = self.tab
	local list = tab == "r" or tab == "g"
	local mine = list and self.selected and ns:MyReport(tab, self.selected)

	f.removeMine:SetShown(list or tab == "b")
	if tab == "b" then
		-- The bounty board: take a bounty down, and for a won gold bounty the
		-- say of the two it concerns and of the officers.
		local rec = self.selected and session and session.store:Get(self.selected)
		local live = rec and not rec.del and rec.k == "b"
		local debt = live and session.store:Debt(rec, GetServerTime()) or nil
		local poster = live and rec.akey == session.meKey
		local winner = debt ~= nil and debt.wkey == session.meKey
		f.removeMine:SetLabel(officer and L.REMOVE_BOUNTY_ANY or L.REMOVE_BOUNTY)
		f.removeMine:SetEnabled(live and (officer or (poster and not (debt and debt.open))) or false)
		f.edit:SetShown(debt ~= nil and (winner or poster))
		f.edit:SetLabel(winner and L.DEBT_MARK_PAID or L.DEBT_MARK_SENT)
		f.edit:SetEnabled(debt ~= nil and ((winner and debt.open) or (poster and not winner and debt.state == "owed")))
		f.bounty:SetShown(winner)
		f.bounty:SetLabel(L.DEBT_NOT_RECEIVED)
		f.bounty:SetEnabled(winner and debt.state == "sent")
		f.removeAll:SetShown(officer and debt ~= nil)
		f.removeAll:SetLabel(L.DEBT_SETTLE)
		f.removeAll:SetEnabled(debt ~= nil and debt.open)
	else
		f.edit:SetShown(list)
		f.edit:SetLabel(L.EDIT)
		f.edit:SetEnabled(mine and true or false)
		f.bounty:SetShown(list)
		f.bounty:SetLabel(L.POST_BOUNTY)
		f.bounty:SetEnabled(self.selected ~= nil)
		f.removeAll:SetShown(list and officer)
		f.removeAll:SetLabel(L.REMOVE_ALL)
		f.removeAll:SetEnabled(self.selected ~= nil)
		f.removeMine:SetLabel(L.REMOVE_MINE)
		f.removeMine:SetEnabled(mine and true or false)
	end

	f.add:Show()
	f.add.tip = nil
	if tab == "g" then
		f.add:SetLabel(L.ADD_GUILD)
		f.add:SetEnabled(officer)
		f.add.tip = (not officer) and L.MSG_NOT_OFFICER or nil
	elseif tab == "r" then
		local ok, info = pcall(ns.Detect.Inspect, "target")
		f.add:SetLabel((ok and info) and L.ADD_TARGET or L.ADD_PLAYER)
		f.add:SetEnabled(session ~= nil)
	elseif tab == "b" then
		f.add:SetLabel(L.POST_BOUNTY)
		f.add:SetEnabled(session ~= nil)
	elseif tab == "m" then
		f.add:SetLabel(L.EDIT_RANKS)
		f.add:SetShown(officer)
		f.add:SetEnabled(officer)
	elseif tab == "u" then
		f.add:SetLabel(L.REFRESH)
		f.add:SetEnabled(session ~= nil)
		f.add.tip = L.REFRESH_TIP
	else
		f.add:Hide()
	end
end

function Main:UpdateStatus()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local session = ns.session
	if not session then
		f.status:SetText(L.STATUS_NO_GUILD)
		f.syncStatus:SetText("")
		return
	end
	local players, guilds = session.store:Counts()
	local peers = ns.Users:Summary().online - 1 -- not counting myself
	f.status:SetText(L.STATUS_COUNTS:format(players, guilds) .. "   ·   "
		.. (peers > 0 and L.STATUS_PEERS:format(peers) or L.STATUS_ALONE))

	local parts = {}
	local waiting = #session.store:DirtyIds()
	if waiting > 0 then parts[#parts + 1] = Fmt.Color(Fmt.AMBER, L.STATUS_PENDING:format(waiting)) end
	if session.sync.locked then
		parts[#parts + 1] = Fmt.Color(Fmt.AMBER, L.STATUS_LOCKED)
	elseif session.store.data.agreedAt then
		parts[#parts + 1] = L.STATUS_SYNCED:format(Fmt.Ago(session.store.data.agreedAt))
	elseif session.store.data.lastSync then
		parts[#parts + 1] = L.STATUS_CONTACT:format(Fmt.Ago(session.store.data.lastSync))
	end
	f.syncStatus:SetText(table.concat(parts, "   ·   "))
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

function Main:OnAdd()
	local tab = self.tab
	if tab == "g" then
		ns.AddDialog:Open("guild", {})
	elseif tab == "b" then
		local ok, info = pcall(ns.Detect.Inspect, "target")
		ns.BountyDialog:Open({ scope = "p", name = ok and info and info.name or nil })
	elseif tab == "m" then
		ns.RanksDialog:Open()
	elseif tab == "u" then
		ns:Print(ns.Users:Ask() and L.MSG_USERS_ASKED or L.MSG_USERS_WAIT)
	else
		local ok, info = pcall(ns.Detect.Inspect, "target")
		ns.AddDialog:Open("player", { info = ok and info or nil })
	end
end

function Main:OnRemoveMine()
	if not self.selected then return end
	if self.tab == "b" then
		if ns:RemoveBounty(self.selected) then self.selected = nil end
	elseif ns:RemoveMine(self.tab, self.selected) then
		self.selected = nil
	end
end

--- The second button: edit my reason, or have my say on a won bounty's gold.
function Main:OnEdit()
	local s = ns.session
	if not s or not self.selected then return end
	if self.tab == "b" then
		local rec = s.store:Get(self.selected)
		local debt = rec and s.store:Debt(rec, GetServerTime())
		if not debt then return end
		if debt.wkey == s.meKey then
			ns:MarkReceived(self.selected, "r")
		elseif debt.pkey == s.meKey then
			ns:MarkSent(self.selected, true)
		end
		return
	end
	local mine = ns:MyReport(self.tab, self.selected)
	if mine then ns.AddDialog:Open("edit", { kind = mine.k, name = mine.name, reason = mine.reason }) end
end

--- The officers' button: remove every report, or settle a bounty debt.
function Main:OnRemoveAll()
	if not self.selected then return end
	if self.tab == "b" then
		ns:SettleDebt(self.selected, true)
	elseif ns:RemoveAll(self.tab, self.selected) then
		self.selected = nil
	end
end

--- Post a bounty on the selected player or guild; on the bounty board, the
--- winner saying the gold never arrived.
function Main:OnBounty()
	local s = ns.session
	if not s or not self.selected then return end
	if self.tab == "b" then
		ns:MarkReceived(self.selected, "x")
		return
	end
	local subject = self.tab == "g" and s.store:Guild(self.selected) or s.store:Player(self.selected)
	if not subject then return end
	ns.BountyDialog:Open({ scope = self.tab == "g" and "g" or "p", name = subject.name })
end

function Main:Toggle()
	if not self.frame then self:Build() end
	self.frame:SetShown(not self.frame:IsShown())
end

function Main:Show(tab)
	if not self.frame then self:Build() end
	if tab then self:SetTab(tab) end
	self.frame:Show()
end

function Main:Init()
	local function markStale()
		Main.stale = true
	end
	ns:Listen("LIST_CHANGED", markStale)
	ns:Listen("SESSION_CHANGED", markStale)
	ns:Listen("ROSTER_CHANGED", markStale)
	ns:Listen("PROGRESS_CHANGED", markStale)
	ns:Listen("USERS_CHANGED", markStale)
end
