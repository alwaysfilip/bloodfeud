-- Saved battleground scoreboard viewer, opened by clicking a match in the
-- History tab.
local _, ns = ...

local W, Fmt, Names, History = ns.W, ns.Fmt, ns.Names, ns.History
local L = ns.L

local Dialog = { filter = "all", offset = 0, rows = {} }
ns.MatchDialog = Dialog

local WIDTH, HEIGHT = 680, 440
local ROW_H, ROWS = 22, 13
local TOP = 104

local COLS = {
	{ title = L.COL_NAME, w = 210 },
	{ title = L.COL_KB, w = 52 },
	{ title = L.COL_DEATHS, w = 62 },
	{ title = L.COL_HK, w = 56 },
	{ title = L.COL_DAMAGE, w = 110 },
	{ title = L.COL_HEALING, w = 110 },
}

local function createRow(parent, i)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetTexture(W.FLAT)
	row.cells = {}
	local x = 0
	for c = 1, #COLS do
		local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cell:SetPoint("LEFT", row, "LEFT", x + 4, 0)
		cell:SetWidth(COLS[c].w - 8)
		cell:SetJustifyH("LEFT")
		cell:SetWordWrap(false)
		row.cells[c] = cell
		x = x + COLS[c].w
	end
	return row
end

function Dialog:Build()
	local f = W.Panel(UIParent, "BusinessMeetingMatchDialog")
	self.frame = f
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER", 0, 20)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	W.Movable(f)
	f:Hide()
	tinsert(UISpecialFrames, "BusinessMeetingMatchDialog")

	f.title = W.Heading(f, "", 16)
	f.title:SetPoint("TOPLEFT", 16, -12)
	f.sub = W.Label(f, "GameFontHighlightSmall")
	f.sub:SetPoint("TOPLEFT", 16, -34)
	f.sub:SetPoint("RIGHT", -90, 0)

	local close = W.Button(f, "X", 26, 22)
	close:SetPoint("TOPRIGHT", -14, -12)
	close:SetScript("OnClick", function() f:Hide() end)

	f.filters = {}
	local defs = { { "all", L.FILTER_ALL }, { "enemy", L.FILTER_ENEMIES }, { "ally", L.FILTER_ALLIES } }
	local prev
	for i = 1, #defs do
		local key, label = defs[i][1], defs[i][2]
		local b = W.Button(f, label, 84, 22, "tab")
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 16, -56) end
		b:SetScript("OnClick", function()
			Dialog.filter = key
			Dialog.offset = 0
			Dialog:Refresh()
		end)
		f.filters[key] = b
		prev = b
	end

	local x = 16
	for c = 1, #COLS do
		local h = W.Caption(f, COLS[c].title)
		h:SetPoint("TOPLEFT", x + 4, -(TOP - 16))
		x = x + COLS[c].w
	end

	local list = CreateFrame("Frame", nil, f)
	list:SetPoint("TOPLEFT", 16, -TOP)
	list:SetPoint("TOPRIGHT", -34, -TOP)
	list:SetHeight(ROWS * ROW_H)
	list:EnableMouseWheel(true)
	f.rows = {}
	for i = 1, ROWS do f.rows[i] = createRow(list, i) end
	f.empty = W.Label(list, "GameFontDisable", L.MATCH_NO_ROSTER)
	f.empty:SetPoint("CENTER")

	local slider = CreateFrame("Slider", nil, f, "BackdropTemplate")
	f.slider = slider
	slider:SetPoint("TOPRIGHT", -14, -TOP)
	slider:SetSize(12, ROWS * ROW_H)
	slider:SetOrientation("VERTICAL")
	W.Skin(slider, { 0.04, 0.04, 0.05 }, { 0.14, 0.15, 0.18 })
	slider:SetThumbTexture(W.FLAT)
	local thumb = slider:GetThumbTexture()
	thumb:SetSize(10, 32)
	thumb:SetVertexColor(W.C.gold[1], W.C.gold[2], W.C.gold[3], 1)
	slider:SetMinMaxValues(0, 0)
	slider:SetValueStep(1)
	slider:SetValue(0)
	slider:SetScript("OnValueChanged", function(_, value)
		local off = math.floor(value + 0.5)
		if off ~= Dialog.offset then
			Dialog.offset = off
			Dialog:Render()
		end
	end)
	list:SetScript("OnMouseWheel", function(_, delta)
		local lo, hi = slider:GetMinMaxValues()
		slider:SetValue(math.max(lo, math.min(hi, slider:GetValue() - delta * 3)))
	end)
end

function Dialog:Refresh()
	local f, match = self.frame, self.match
	if not (f and match) then return end
	local result = match.win == true and Fmt.Color("ff8fd18f", L.RESULT_WIN)
		or (match.win == false and Fmt.Color(Fmt.RED, L.RESULT_LOSS) or Fmt.Color(Fmt.GREY, L.RESULT_DRAW))
	f.title:SetText(W.Caps(match.map or "Battleground") .. "  ·  " .. result)
	f.sub:SetText(L.MATCH_SUMMARY:format(History.FormatDuration(match.dur), match.kb or 0, match.d or 0,
		match.hk or 0, match.honor or 0, Fmt.Ago(match.t)))
	for k, b in pairs(f.filters) do b:SetSelected(k == self.filter) end

	local list = {}
	for _, r in ipairs(match.roster or {}) do
		if self.filter == "all" or (self.filter == "enemy" and r.e) or (self.filter == "ally" and not r.e) then
			list[#list + 1] = r
		end
	end
	table.sort(list, function(a, b)
		if (a.kb or 0) ~= (b.kb or 0) then return (a.kb or 0) > (b.kb or 0) end
		if (a.dmg or 0) ~= (b.dmg or 0) then return (a.dmg or 0) > (b.dmg or 0) end
		return (a.n or "") < (b.n or "")
	end)
	self.rows = list

	local last = math.max(0, #list - ROWS)
	if self.offset > last then self.offset = last end
	f.slider:SetMinMaxValues(0, last)
	f.slider:SetValue(self.offset)
	f.slider:SetShown(last > 0)
	self:Render()
end

function Dialog:Render()
	local f = self.frame
	if not f then return end
	for i = 1, ROWS do
		local row = f.rows[i]
		local r = self.rows[self.offset + i]
		if r then
			local icon = W.ClassInline(r.c, 13)
			local hex = Fmt.ClassHex(r.c)
			local disp = Names.Display(r.n or "")
			local name = (icon ~= "" and (icon .. " ") or "") .. (hex and Fmt.Color(hex, disp) or disp)
			row.cells[1]:SetText(name)
			row.cells[2]:SetText(tostring(r.kb or 0))
			row.cells[3]:SetText(tostring(r.d or 0))
			row.cells[4]:SetText(tostring(r.hk or 0))
			row.cells[5]:SetText(History.ShortNumber(r.dmg or 0))
			row.cells[6]:SetText(History.ShortNumber(r.heal or 0))
			if r.e then
				row.bg:SetVertexColor(0.55, 0.14, 0.12, (i % 2 == 0) and 0.18 or 0.11)
			else
				row.bg:SetVertexColor(0.14, 0.36, 0.55, (i % 2 == 0) and 0.18 or 0.11)
			end
			row:Show()
		else
			row:Hide()
		end
	end
	f.empty:SetShown(#self.rows == 0)
end

function Dialog:Open(match)
	if not match then return end
	if not self.frame then self:Build() end
	self.match = match
	self.filter = "all"
	self.offset = 0
	self:Refresh()
	self.frame:Show()
end
