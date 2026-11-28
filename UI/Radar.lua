-- The radar window: a small, movable list of the enemy players around you.
-- Each row is the class icon and a bar in the class colour that drains as
-- the sighting gets older, with icons for Kill on Sight, a contract, a
-- hostile guild and stealth, and the level at the end.
-- Shift-click a row to put them on the list, right-click to post a bounty.
local _, ns = ...

local W, Fmt, Names = ns.W, ns.Fmt, ns.Names
local L = ns.L

local RadarUI = {}
ns.RadarUI = RadarUI

local WIDTH, ROW_H, ROWS = 300, 22, 10
local TOP = 30
local SOUND_NEW = 3175 -- SOUNDKIT.MAP_PING

local ON_YOU = "ffff8c33"

--- The status of an enemy as icons: one for why they matter (Kill on Sight,
--- a contract, a hostile guild), one for stealth, and words for the thing
--- that cannot wait: that they have you targeted.
local function statusText(entry)
	local parts = {}
	if entry.tag == 3 then
		parts[#parts + 1] = W.Inline("skull", 12, 255, 138, 128)
	elseif entry.tag == 2 then
		parts[#parts + 1] = W.Inline("coin", 12)
	elseif entry.tag == 1 then
		parts[#parts + 1] = W.Inline("guild", 12, 255, 179, 71)
	end
	if entry.stealth and not entry.plate then parts[#parts + 1] = W.Inline("stealth", 13, 199, 181, 255) end
	if entry.targeting then
		parts[#parts + 1] = Fmt.Color(ON_YOU, entry.targeting == "pet" and L.RADAR_ON_PET or L.RADAR_ON_YOU)
	end
	return table.concat(parts, " ")
end

local function rowTooltip(row)
	local entry = row.entry
	if not entry then return end
	local info = entry.info
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	local hex = Fmt.ClassHex(info.class)
	GameTooltip:AddLine(hex and Fmt.Color(hex, Names.Display(info.name)) or Names.Display(info.name))
	local what = Fmt.Describe(info)
	if what ~= "" then GameTooltip:AddLine(what, 1, 1, 1) end
	if info.guild then GameTooltip:AddLine("<" .. info.guild .. ">", 1, 0.7, 0.28) end
	if entry.targeting then
		GameTooltip:AddLine(entry.targeting == "pet" and L.RADAR_TARGETING_PET or L.RADAR_TARGETING, 1, 0.55, 0.2)
	end
	if entry.stealth and not entry.plate then
		GameTooltip:AddLine(L.RADAR_STEALTHED:format(entry.stealthSpell or "?", math.floor(GetTime() - entry.stealth + 0.5)),
			0.72, 0.55, 1)
	end
	local s = ns.session
	if s and ns.Targeting then
		for _, line in ipairs(ns.Alerts.DossierLines(ns.Targeting:Dossier(info))) do
			GameTooltip:AddLine(line, 1, 1, 1, true)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L.RADAR_HINT, 0.66, 0.65, 0.61, true)
	GameTooltip:Show()
end

local function createRow(parent, i)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 8, -(TOP + (i - 1) * ROW_H))
	row:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.class = row:CreateTexture(nil, "ARTWORK")
	row.class:SetSize(18, 18)
	row.class:SetPoint("LEFT", 0, 0)

	-- The bar: full while they are in view, empty when the sighting is about to lapse
	local bar = CreateFrame("StatusBar", nil, row, "BackdropTemplate")
	row.bar = bar
	bar:SetPoint("LEFT", 22, 0)
	bar:SetPoint("RIGHT", -26, 0)
	bar:SetHeight(18)
	bar:EnableMouse(false)
	W.Skin(bar, { 0, 0, 0 }, W.C.steel)
	bar:SetStatusBarTexture(W.FLAT)
	bar:SetMinMaxValues(0, 1)
	row.tag = W.CapsFont(W.Label(bar, "GameFontHighlightSmall"), 11)
	row.tag:SetPoint("RIGHT", -5, 0)
	row.tag:SetJustifyH("RIGHT")
	-- The icons sit on a dark tray, so they read whatever the bar's colour
	row.tray = bar:CreateTexture(nil, "OVERLAY")
	row.tray:SetTexture(W.FLAT)
	row.tray:SetVertexColor(W.C.well[1], W.C.well[2], W.C.well[3], 1)
	row.tray:SetPoint("TOPRIGHT", -1, -1)
	row.tray:SetPoint("BOTTOMRIGHT", -1, 1)
	row.tray:SetPoint("LEFT", row.tag, "LEFT", -5, 0)
	row.name = W.Label(bar, "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 6, 0)
	row.name:SetPoint("RIGHT", row.tag, "LEFT", -8, 0)
	row.name:SetWordWrap(false)
	row.name:SetTextColor(1, 1, 1)
	row.level = W.CapsFont(W.Label(row, "GameFontDisableSmall"), 11)
	row.level:SetPoint("RIGHT", 0, 0)
	row.level:SetJustifyH("RIGHT")
	row:SetScript("OnEnter", function(self)
		self.hover = true
		RadarUI:PaintRow(self)
		rowTooltip(self)
	end)
	row:SetScript("OnLeave", function(self)
		self.hover = false
		RadarUI:PaintRow(self)
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self, button)
		local entry = self.entry
		if not entry then return end
		if button == "RightButton" then
			ns.BountyDialog:Open({ scope = "p", name = entry.info.name })
		elseif IsShiftKeyDown() then
			ns.AddDialog:Open("player", { info = entry.info })
		end
	end)
	return row
end

--- The edge of a row's bar: orange while they have you targeted, gold under
--- the mouse.
function RadarUI:PaintRow(row)
	local entry = row.entry
	if entry and entry.targeting then
		row.bar:SetBackdropBorderColor(1, 0.55, 0.2, 1)
	elseif row.hover then
		row.bar:SetBackdropBorderColor(W.C.gold[1], W.C.gold[2], W.C.gold[3], 1)
	else
		row.bar:SetBackdropBorderColor(W.C.steel[1], W.C.steel[2], W.C.steel[3], 1)
	end
end

function RadarUI:ApplyAlpha()
	local f = self.frame
	if not f then return end
	local fade = ns.settings.hudFade and not self.hover
	f:SetAlpha(fade and 0.68 or 1)
end

function RadarUI:Build()
	local f = W.Panel(UIParent, "BusinessMeetingRadarFrame")
	self.frame = f
	f:SetSize(WIDTH, TOP + ROWS * ROW_H + 10)
	f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 80)
	f:SetFrameStrata("MEDIUM")
	W.Movable(f)
	f:Hide()
	f:SetScript("OnEnter", function()
		RadarUI.hover = true
		RadarUI:ApplyAlpha()
	end)
	f:SetScript("OnLeave", function()
		RadarUI.hover = false
		RadarUI:ApplyAlpha()
	end)

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("TOPLEFT", 10, -8)
	icon:SetTexture(W.ICON)
	f.title = W.Heading(f, L.RADAR_TITLE, 13, W.C.text)
	f.title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	local close = W.Button(f, "X", 20, 18)
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function()
		ns.settings.radar = false
		RadarUI:Update()
	end)

	f.rows = {}
	for i = 1, ROWS do f.rows[i] = createRow(f, i) end
	f.empty = W.Label(f, "GameFontDisableSmall", L.RADAR_EMPTY)
	f.empty:SetPoint("TOP", 0, -(TOP + 8))

	local since = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since > 1 then
			since = 0
			RadarUI:Render()
		end
	end)
end

--- Show or hide the window as the settings and the situation ask.
function RadarUI:Update()
	local want = ns.settings.radar and not ns.Detect.paused
	if want and ns.settings.radarAuto then want = #ns.Radar:Visible() > 0 end
	if not want then
		if self.frame then self.frame:Hide() end
		return
	end
	if not self.frame then self:Build() end
	self.frame:Show()
	self:ApplyAlpha()
	self:Render()
end

function RadarUI:Render()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local list = ns.Radar:Visible()
	if ns.settings.radarAuto and #list == 0 then
		f:Hide()
		return
	end
	local now = GetTime()
	for i = 1, ROWS do
		local row, entry = f.rows[i], list[i]
		row.entry = entry
		if entry then
			local info = entry.info
			if W.SetClassIcon(row.class, info.class) then
				row.class:SetVertexColor(1, 1, 1, 1)
			else
				row.class:SetTexture(W.MEDIA .. "crosshair")
				row.class:SetTexCoord(0, 1, 0, 1)
				row.class:SetVertexColor(W.C.muted[1], W.C.muted[2], W.C.muted[3], 1)
			end
			local r, g, b = Fmt.ClassRGB(info.class)
			if not r then r, g, b = 0.55, 0.57, 0.60 end
			-- A little darker than the class colour, so the white name reads on it
			row.bar:SetStatusBarColor(r * 0.8, g * 0.8, b * 0.8, 1)
			row.fresh = entry.plate and 1 or math.max(0, 1 - (now - entry.at) / ns.Radar.KEEP)
			row.bar:SetValue(row.fresh)
			row.name:SetText(Names.Display(info.name))
			local status = statusText(entry)
			row.tag:SetText(status)
			row.tray:SetShown(status ~= "")
			row.level:SetText(info.high and "??" or (info.level and tostring(info.level) or ""))
			self:PaintRow(row)
			row:Show()
		else
			row:Hide()
		end
	end
	local onMe = ns.Targeting and ns.Targeting:Count() or 0
	if onMe > 0 then
		f.title:SetText(W.Caps(L.RADAR_TITLE_ON:format(#list, onMe)))
	else
		f.title:SetText(W.Caps(#list > 0 and L.RADAR_TITLE_N:format(#list) or L.RADAR_TITLE))
	end
	f.empty:SetShown(#list == 0)
end

function RadarUI:Toggle()
	ns.settings.radar = not ns.settings.radar
	self:Update()
	ns:Print(ns.settings.radar and L.MSG_RADAR_ON or L.MSG_RADAR_OFF)
end

function RadarUI:Init()
	-- The window redraws itself every second while shown; a new enemy is the
	-- only thing that needs it to appear (or redraw) at once.
	ns:Listen("RADAR_NEW", function()
		RadarUI:Update()
		if ns.settings.radar and ns.settings.radarSound and ns.settings.sound and _G.PlaySound then
			pcall(_G.PlaySound, SOUND_NEW, "Master")
		end
	end)
	ns:Listen("TARGETING_CHANGED", function() RadarUI:Update() end)
	ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, function() RadarUI:Update() end) end)
	ns:On("ZONE_CHANGED_NEW_AREA", function() RadarUI:Update() end)
	C_Timer.After(2, function() RadarUI:Update() end)
end
