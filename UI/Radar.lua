-- The radar window: a small, movable list of the enemy players around you.
-- Shift-click a row to put them on the list, right-click to post a bounty.
local _, ns = ...

local W, Fmt, Names = ns.W, ns.Fmt, ns.Names
local L = ns.L

local RadarUI = {}
ns.RadarUI = RadarUI

local WIDTH, ROW_H, ROWS = 300, 20, 10
local TOP = 30
local SOUND_NEW = 3175 -- SOUNDKIT.MAP_PING

local ON_YOU = "ffff8c33"
local STEALTH = "ffb88cff"

local TAGS = {
	[3] = { L.RADAR_KOS, "ffff8a80" },
	[2] = { L.RADAR_BOUNTY, "fff0c75e" },
	[1] = { L.RADAR_GUILD, "ffffb347" },
}

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
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetTexture(W.FLAT)
	row.bg:SetVertexColor(1, 1, 1, 0)
	row.name = W.Label(row, "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetWidth(150)
	row.name:SetWordWrap(false)
	row.tag = W.Label(row, "GameFontHighlightSmall")
	row.tag:SetPoint("LEFT", 158, 0)
	row.tag:SetWidth(70)
	row.age = W.Label(row, "GameFontDisableSmall")
	row.age:SetPoint("RIGHT", -4, 0)
	row.age:SetJustifyH("RIGHT")
	row:SetScript("OnEnter", function(self)
		self.bg:SetVertexColor(1, 1, 1, 0.07)
		rowTooltip(self)
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:SetVertexColor(1, 1, 1, 0)
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

function RadarUI:Build()
	local f = W.Panel(UIParent, "BusinessMeetingRadarFrame")
	self.frame = f
	f:SetSize(WIDTH, TOP + ROWS * ROW_H + 10)
	f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 80)
	f:SetFrameStrata("MEDIUM")
	W.Movable(f)
	f:Hide()

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
			local hex = Fmt.ClassHex(info.class)
			local label = Names.Display(info.name)
			if info.level then label = label .. " " .. Fmt.Color(Fmt.GREY, tostring(info.level)) end
			row.name:SetText(hex and Fmt.Color(hex, label) or label)
			local tag = TAGS[entry.tag]
			if entry.targeting then
				-- Kill on Sight stays visible next to it; lesser tags give way.
				row.tag:SetText((entry.tag == 3 and (Fmt.Color(tag[2], tag[1]) .. " ") or "")
					.. Fmt.Color(ON_YOU, entry.targeting == "pet" and L.RADAR_ON_PET or L.RADAR_ON_YOU))
			elseif entry.stealth and not entry.plate then
				row.tag:SetText((entry.tag == 3 and (Fmt.Color(tag[2], tag[1]) .. " ") or "") .. Fmt.Color(STEALTH, L.RADAR_STEALTH))
			else
				row.tag:SetText(tag and Fmt.Color(tag[2], tag[1])
					or (info.guild and Fmt.Color(Fmt.GREY, "<" .. info.guild .. ">") or ""))
			end
			row.age:SetText(entry.plate and Fmt.Color("ff8fd18f", L.RADAR_NEAR)
				or L.RADAR_AGO:format(math.floor(now - entry.at + 0.5)))
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
