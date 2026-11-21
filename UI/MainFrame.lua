-- The list window: who is Kill on Sight, why, who says so, and where they
-- were last seen. One row per enemy (or per enemy guild), however many
-- guildmates have reported them.
local _, ns = ...

local W, Fmt, Names, Util, Roster = ns.W, ns.Fmt, ns.Names, ns.Util, ns.Roster
local L = ns.L

local Main = { tab = "r", offset = 0, items = {}, selected = nil, stale = true }
ns.MainFrame = Main

local WIDTH, HEIGHT = 880, 520
local PAD = 14
local ROW_H, ROWS = 24, 14
local LIST_TOP = 118

local COLUMNS = {
	r = {
		{ title = L.COL_NAME, w = 180 }, { title = L.COL_LEVEL, w = 36 }, { title = L.COL_GUILD, w = 140 },
		{ title = L.COL_REASON, w = 180 }, { title = L.COL_BY, w = 100 }, { title = L.COL_SEEN, w = 130 },
		{ title = L.COL_SCORE, w = 60 },
	},
	g = {
		{ title = L.COL_GUILD, w = 230 }, { title = L.COL_REASON, w = 330 }, { title = L.COL_BY, w = 150 },
		{ title = L.COL_ADDED, w = 116 },
	},
}
local MAX_COLS = 7

local function grey(text)
	return Fmt.Color(Fmt.GREY, text)
end

---------------------------------------------------------------------------
-- Row content
---------------------------------------------------------------------------

local function more(subject)
	return #subject.reports > 1 and grey(L.MORE:format(#subject.reports - 1)) or ""
end

local function playerCells(subject)
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
	return {
		Fmt.PlayerName(subject), facts and facts.level and tostring(facts.level) or grey("??"), guild,
		first.reason .. more(subject), Names.Display(first.author) .. more(subject), where,
		Fmt.Score(subject.kills, subject.deaths),
	}
end

local function guildCells(subject)
	local first = subject.reports[1]
	return {
		Fmt.Color(Fmt.AMBER, "<" .. subject.name .. ">"), first.reason .. more(subject),
		Names.Display(first.author) .. more(subject), Fmt.Ago(first.at),
	}
end

local function showRowTooltip(row)
	local subject = row.item
	if not subject then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
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
	local seen = subject.seen
	if seen then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L.TIP_SEEN:format(Fmt.Ago(seen.at), (Fmt.Zone(seen.map) and (" · " .. Fmt.Zone(seen.map)) or "")
			.. Fmt.Coords(seen.x, seen.y)) .. (seen.by and L.TIP_SEEN_BY:format(Names.Display(seen.by)) or ""),
			0.66, 0.65, 0.61, true)
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
	local options = W.Button(f, "Options", 70, 22)
	options:SetPoint("RIGHT", close, "LEFT", -6, 0)
	options:SetScript("OnClick", function() ns:OpenOptions() end)

	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetTexture(W.FLAT)
	rule:SetVertexColor(0.23, 0.20, 0.13, 1)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 1, -40)
	rule:SetPoint("TOPRIGHT", -1, -40)

	-- Toolbar
	f.tabPlayers = W.Button(f, L.TAB_PLAYERS, 130, 26)
	f.tabPlayers:SetPoint("TOPLEFT", PAD, -50)
	f.tabPlayers:SetScript("OnClick", function() Main:SetTab("r") end)
	f.tabGuilds = W.Button(f, L.TAB_GUILDS, 130, 26)
	f.tabGuilds:SetPoint("LEFT", f.tabPlayers, "RIGHT", 4, 0)
	f.tabGuilds:SetScript("OnClick", function() Main:SetTab("g") end)

	f.add = W.Button(f, L.ADD_TARGET, 140, 26, "danger")
	f.add:SetPoint("TOPRIGHT", -PAD, -50)
	f.add:SetScript("OnClick", function() Main:OnAdd() end)

	f.search = W.EditBox(f, 240, 26, 40)
	f.search:SetPoint("RIGHT", f.add, "LEFT", -12, 0)
	f.search:SetScript("OnTextChanged", function()
		Main.offset = 0
		Main:Refresh()
	end)
	local searchLabel = W.Label(f, "GameFontDisableSmall", L.SEARCH)
	searchLabel:SetPoint("RIGHT", f.search, "LEFT", -8, 0)

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
	f.removeMine:SetScript("OnClick", function()
		if Main.selected and ns:RemoveMine(Main.tab, Main.selected) then Main.selected = nil end
	end)
	f.edit = W.Button(f, L.EDIT, 110, 26)
	f.edit:SetPoint("LEFT", f.removeMine, "RIGHT", 6, 0)
	f.edit:SetScript("OnClick", function()
		local mine = Main.selected and ns:MyReport(Main.tab, Main.selected)
		if mine then ns.AddDialog:Open("edit", { kind = mine.k, name = mine.name, reason = mine.reason }) end
	end)
	f.removeAll = W.Button(f, L.REMOVE_ALL, 210, 26, "danger")
	f.removeAll:SetPoint("LEFT", f.edit, "RIGHT", 6, 0)
	f.removeAll:SetScript("OnClick", function()
		if Main.selected and ns:RemoveAll(Main.tab, Main.selected) then Main.selected = nil end
	end)

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
	if self.tab == tab then return end
	self.tab = tab
	self.offset = 0
	self.selected = nil
	self:Refresh()
end

local function matches(subject, query)
	if Util.Fold(subject.name):find(query, 1, true) then return true end
	if subject.facts and subject.facts.guild and Util.Fold(subject.facts.guild):find(query, 1, true) then return true end
	for i = 1, #subject.reports do
		local rec = subject.reports[i]
		if Util.Fold(rec.reason or ""):find(query, 1, true) or Util.Fold(rec.author):find(query, 1, true) then return true end
	end
	return false
end

local function newest(subject)
	local at = 0
	for i = 1, #subject.reports do
		if subject.reports[i].at > at then at = subject.reports[i].at end
	end
	return at
end

local function byActivity(a, b)
	local sa, sb = a.seen and a.seen.at or 0, b.seen and b.seen.at or 0
	if sa ~= sb then return sa > sb end
	local na, nb = newest(a), newest(b)
	if na ~= nb then return na > nb end
	return a.key < b.key
end

local function byName(a, b)
	return a.key < b.key
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
	local items = {}
	local query = Util.Fold(Util.Clean(f.search:GetText() or "", 60))
	if session then
		local all = self.tab == "r" and session.store:Players() or session.store:Guilds()
		for i = 1, #all do
			if query == "" or matches(all[i], query) then items[#items + 1] = all[i] end
		end
		table.sort(items, self.tab == "r" and byActivity or byName)
	end
	self.items = items
	self.query = query

	local last = math.max(0, #items - ROWS)
	if self.offset > last then self.offset = last end
	f.slider:SetMinMaxValues(0, last)
	f.slider:SetValue(self.offset)
	f.slider:SetShown(last > 0)

	f.tabPlayers:SetSelected(self.tab == "r")
	f.tabGuilds:SetSelected(self.tab == "g")
	f.subtitle:SetText(L.SUBTITLE .. (session and (" · <" .. session.guild .. ">") or ""))
	f.notice:SetText(self.tab == "g" and L.OFFICER_ONLY or "")

	local columns = COLUMNS[self.tab]
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
	local columns = COLUMNS[self.tab]
	for i = 1, ROWS do
		local row = f.rows[i]
		local item = self.items[self.offset + i]
		row.item = item
		row.index = self.offset + i
		if item then
			local cells = item.kind == "r" and playerCells(item) or guildCells(item)
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
	local session = ns.session
	if #self.items == 0 then
		local text = L.STATUS_NO_GUILD
		if session then
			text = (self.query ~= "" and L.EMPTY_SEARCH) or (self.tab == "r" and L.EMPTY_PLAYERS or L.EMPTY_GUILDS)
		end
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
	local mine = self.selected and ns:MyReport(self.tab, self.selected)

	f.removeMine:SetEnabled(mine and true or false)
	f.edit:SetEnabled(mine and true or false)
	f.removeAll:SetShown(officer)
	f.removeAll:SetEnabled(self.selected ~= nil)

	if self.tab == "g" then
		f.add:SetLabel(L.ADD_GUILD)
		f.add:SetEnabled(officer)
		f.add.tip = (not officer) and L.MSG_NOT_OFFICER or nil
	else
		local ok, info = pcall(ns.Detect.Inspect, "target")
		f.add:SetLabel((ok and info) and L.ADD_TARGET or L.ADD_PLAYER)
		f.add:SetEnabled(session ~= nil)
		f.add.tip = nil
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
	local peers = session.sync:PeerCount()
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

function Main:OnAdd()
	if self.tab == "g" then
		ns.AddDialog:Open("guild", {})
		return
	end
	local ok, info = pcall(ns.Detect.Inspect, "target")
	ns.AddDialog:Open("player", { info = ok and info or nil })
end

function Main:Toggle()
	if not self.frame then self:Build() end
	self.frame:SetShown(not self.frame:IsShown())
end

function Main:Show()
	if not self.frame then self:Build() end
	self.frame:Show()
end

function Main:Init()
	local function markStale()
		Main.stale = true
	end
	ns:Listen("LIST_CHANGED", markStale)
	ns:Listen("SESSION_CHANGED", markStale)
	ns:Listen("ROSTER_CHANGED", markStale)
end
