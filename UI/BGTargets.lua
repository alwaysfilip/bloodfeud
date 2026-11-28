-- Battleground Targets & Flag Carrier HUD, inspired by Forever Simple
-- Battleground Targets and built in Business Meeting's unit-frame style.
-- Uses SecureActionButtonTemplate rows for click-to-target and strictly queues
-- all secure mutations until PLAYER_REGEN_ENABLED when InCombatLockdown().
local _, ns = ...

local W, Fmt, Names, Util = ns.W, ns.Fmt, ns.Names, ns.Util
local L = ns.L

local BGTargets = { demo = false, dirtySecure = false, hover = false }
ns.BGTargets = BGTargets

local WIDTH, ROW_H, MAX_ROWS = 240, 21, 20
local TOP = 28
local FC_H = 22

local LIVE_UNITS = { "target", "focus", "mouseover", "arena1", "arena2", "arena3", "arena4", "arena5" }
for i = 1, 40 do LIVE_UNITS[#LIVE_UNITS + 1] = "nameplate" .. i end

local function inCombat()
	return _G.InCombatLockdown and _G.InCombatLockdown() and true or false
end

local function plain(value, kind)
	if value == nil or Util.IsSecret(value) then return nil end
	if kind and type(value) ~= kind then return nil end
	return value
end

local function safe(fn, ...)
	if not fn then return nil end
	local ok, v = pcall(fn, ...)
	return ok and v or nil
end

-- Live health fraction (0..1) for `key` if visible on any unit token, else nil.
local function liveHealth(key)
	for i = 1, #LIVE_UNITS do
		local unit = LIVE_UNITS[i]
		if plain(safe(_G.UnitExists, unit)) and plain(safe(_G.UnitIsPlayer, unit)) then
			local canon = Names.OfUnit(unit)
			if canon and Names.Key(canon) == key then
				local hp = plain(safe(_G.UnitHealth, unit), "number")
				local maxHp = plain(safe(_G.UnitHealthMax, unit), "number")
				if hp and maxHp and maxHp > 0 then return math.max(0, math.min(1, hp / maxHp)) end
				return nil
			end
		end
	end
	return nil
end

local function createTargetRow(parent, width, height)
	local row = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
	row:SetSize(width, height)
	row:RegisterForClicks("AnyUp", "AnyDown")

	row.class = row:CreateTexture(nil, "ARTWORK")
	row.class:SetSize(height - 3, height - 3)
	row.class:SetPoint("LEFT", 0, 0)

	local bar = CreateFrame("StatusBar", nil, row, "BackdropTemplate")
	row.bar = bar
	bar:SetPoint("LEFT", height, 0)
	bar:SetPoint("RIGHT", 0, 0)
	bar:SetHeight(height - 2)
	bar:EnableMouse(false)
	W.Skin(bar, { 0.03, 0.035, 0.045 }, W.C.steel)
	bar:SetStatusBarTexture(W.FLAT)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)

	row.tag = W.CapsFont(W.Label(bar, "GameFontHighlightSmall"), 10)
	row.tag:SetPoint("RIGHT", -4, 0)
	row.tag:SetJustifyH("RIGHT")

	row.name = W.Label(bar, "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 5, 0)
	row.name:SetPoint("RIGHT", row.tag, "LEFT", -4, 0)
	row.name:SetWordWrap(false)
	row.name:SetTextColor(1, 1, 1)

	row:SetScript("OnEnter", function(self)
		BGTargets.hover = true
		BGTargets:ApplyAlpha()
		self.bar:SetBackdropBorderColor(W.C.gold[1], W.C.gold[2], W.C.gold[3], 1)
	end)
	row:SetScript("OnLeave", function(self)
		BGTargets.hover = false
		BGTargets:ApplyAlpha()
		local c = self.borderColor or W.C.steel
		self.bar:SetBackdropBorderColor(c[1], c[2], c[3], 1)
	end)
	row:Hide()
	return row
end

function BGTargets:ApplyAlpha()
	local f = self.frame
	if not f then return end
	local fade = ns.settings.hudFade and not self.hover
	f:SetAlpha(fade and 0.68 or 1)
end

function BGTargets:Build()
	local f = W.Panel(UIParent, "BusinessMeetingBGTargetsFrame")
	self.frame = f
	f:SetSize(WIDTH, TOP + MAX_ROWS * ROW_H + 12)
	f:SetPoint("RIGHT", UIParent, "RIGHT", -380, 60)
	f:SetFrameStrata("MEDIUM")
	W.Movable(f)
	f:Hide()

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("TOPLEFT", 10, -7)
	icon:SetTexture(W.ICON)
	f.title = W.Heading(f, L.BG_TARGETS_TITLE, 12, W.C.text)
	f.title:SetPoint("LEFT", icon, "RIGHT", 6, 0)

	local close = W.Button(f, "X", 18, 16)
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function()
		if BGTargets.demo then
			BGTargets:SetDemo(false)
		else
			ns.settings.bgTargets = false
		end
		BGTargets:Update()
	end)

	-- Dedicated Flag Carrier buttons (Enemy FC, Friendly FC)
	f.efc = createTargetRow(f, WIDTH - 16, FC_H)
	f.efc:SetPoint("TOPLEFT", 8, -TOP)
	f.efc.borderColor = { 0.898, 0.282, 0.302 }
	f.afc = createTargetRow(f, WIDTH - 16, FC_H)
	f.afc:SetPoint("TOPLEFT", 8, -(TOP + FC_H + 2))
	f.afc.borderColor = { 0.28, 0.60, 0.96 }

	f.rows = {}
	for i = 1, MAX_ROWS do
		local row = createTargetRow(f, WIDTH - 16, ROW_H)
		row:SetPoint("TOPLEFT", 8, -(TOP + (i - 1) * ROW_H))
		f.rows[i] = row
	end

	f:SetScript("OnEnter", function()
		BGTargets.hover = true
		BGTargets:ApplyAlpha()
	end)
	f:SetScript("OnLeave", function()
		BGTargets.hover = false
		BGTargets:ApplyAlpha()
	end)
	local since = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since >= 0.5 then
			since = 0
			BGTargets:RefreshVisuals()
		end
	end)
end

local function demoData()
	return {
		{ name = "Grimtusk-Bloodaxe", key = "grimtusk-bloodaxe", class = 4, kb = 6 },
		{ name = "Vexara-Nightfall", key = "vexara-nightfall", class = 8, kb = 4 },
		{ name = "Morgash-Gorefist", key = "morgash-gorefist", class = 1, kb = 3 },
		{ name = "Zulrakka-Venomtongue", key = "zulrakka-venomtongue", class = 7, kb = 2 },
	}, {
		enemy = { name = "Morgash-Gorefist", key = "morgash-gorefist", class = 1 },
		ally = { name = "Olaf-Stormborn", key = "olaf-stormborn", class = 1 },
	}
end

local function paintRow(row, info, prefix, isFC)
	if W.SetClassIcon(row.class, info.class) then
		row.class:SetVertexColor(1, 1, 1, 1)
	else
		row.class:SetTexture(W.MEDIA .. "crosshair")
		row.class:SetTexCoord(0, 1, 0, 1)
		row.class:SetVertexColor(W.C.muted[1], W.C.muted[2], W.C.muted[3], 1)
	end
	local r, g, b = Fmt.ClassRGB(info.class)
	if not r then r, g, b = 0.55, 0.57, 0.60 end
	row.bar:SetStatusBarColor(r * 0.78, g * 0.78, b * 0.78, 1)
	local hp = liveHealth(info.key)
	row.bar:SetValue(hp or 1)
	row.name:SetText((prefix and (prefix .. " ") or "") .. Names.Display(info.name))

	local tags = {}
	if isFC then tags[#tags + 1] = Fmt.Color(Fmt.GOLD, "FC") end
	if info.isAlly and not isFC then
		tags[#tags + 1] = Fmt.Color("ff69a8ff", "ALLY")
	else
		local s = ns.session
		if s and ns.Detect then
			local listKey = ns.Detect.Match(s.store, info)
			if listKey then
				tags[#tags + 1] = W.Inline("skull", 11, 255, 138, 128)
			elseif ns.Bounties and ns.Bounties:Worth(info) > 0 then
				tags[#tags + 1] = W.Inline("coin", 11)
			else
				local facts = s.store:Get("f:" .. info.key)
				if facts and facts.guild and s.store:IsGuildListed(facts.guild) then
					tags[#tags + 1] = W.Inline("guild", 11, 255, 179, 71)
				end
			end
		end
	end
	row.tag:SetText(table.concat(tags, " "))
	local bc = row.borderColor or (info.isAlly and { 0.24, 0.45, 0.72 } or W.C.steel)
	row.bar:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)
end

local function bindTarget(row, canonName, unitToken)
	local macro = "/targetexact " .. Names.Display(canonName)
	if unitToken then macro = "/target " .. unitToken .. "\n" .. macro end
	if row:GetAttribute("type1") ~= "macro" then row:SetAttribute("type1", "macro") end
	if row:GetAttribute("macrotext1") ~= macro then row:SetAttribute("macrotext1", macro) end
end

function BGTargets:CurrentData()
	if self.demo then return demoData() end
	local bg = ns.Battleground
	if not (bg and bg.active) then return {}, { enemy = nil, ally = nil } end
	local list = {}
	for i = 1, #bg.enemies do list[#list + 1] = bg.enemies[i] end
	if ns.settings.bgTargetsAllies then
		for i = 1, #bg.allies do
			local a = bg.allies[i]
			list[#list + 1] = { name = a.name, key = a.key, class = a.class, kb = a.kb, isAlly = true }
		end
	end
	return list, bg.fc
end

--- Update non-protected visual fields (safe during combat).
function BGTargets:RefreshVisuals()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local list, fc = self:CurrentData()
	if fc.enemy and f.efc:IsShown() then
		paintRow(f.efc, fc.enemy, Fmt.Color(Fmt.RED, "EFC"), true)
	end
	if fc.ally and f.afc:IsShown() then
		paintRow(f.afc, fc.ally, Fmt.Color("ff69a8ff", "AFC"), true)
	end
	for i = 1, MAX_ROWS do
		local row = f.rows[i]
		local info = list[i]
		if info and row:IsShown() then
			local isEFC = fc.enemy and fc.enemy.key == info.key
			paintRow(row, info, nil, isEFC)
		end
	end
end

--- Apply protected SecureActionButton layout & attributes (out of combat only).
function BGTargets:ApplySecure()
	local f = self.frame
	if not f then return end
	if inCombat() then
		self.dirtySecure = true
		return
	end
	self.dirtySecure = false

	local bg = ns.Battleground
	local want = self.demo or (ns.settings.bgTargets and bg and bg.active)
	if not want then
		f:Hide()
		return
	end

	local list, fc = self:CurrentData()
	local y = TOP
	if fc.enemy then
		f.efc:ClearAllPoints()
		f.efc:SetPoint("TOPLEFT", 8, -y)
		bindTarget(f.efc, fc.enemy.name, fc.enemy.unit)
		f.efc:Show()
		y = y + FC_H + 3
	else
		f.efc:Hide()
	end
	if fc.ally then
		f.afc:ClearAllPoints()
		f.afc:SetPoint("TOPLEFT", 8, -y)
		bindTarget(f.afc, fc.ally.name, fc.ally.unit)
		f.afc:Show()
		y = y + FC_H + 3
	else
		f.afc:Hide()
	end
	if fc.enemy or fc.ally then y = y + 4 end

	local count = math.min(#list, MAX_ROWS)
	for i = 1, MAX_ROWS do
		local row = f.rows[i]
		local info = list[i]
		if info and i <= count then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 8, -(y + (i - 1) * ROW_H))
			bindTarget(row, info.name)
			row:Show()
		else
			row:Hide()
		end
	end

	local title = count > 0 and L.BG_TARGETS_TITLE_N:format(count) or L.BG_TARGETS_TITLE
	f.title:SetText(W.Caps(title))
	f:SetHeight(math.max(TOP + 26, y + count * ROW_H + 8))
	f:Show()
	self:ApplyAlpha()
	self:RefreshVisuals()
end

function BGTargets:Update()
	local want = self.demo or (ns.settings.bgTargets and ns.Battleground and ns.Battleground.active)
	if want and not self.frame then
		if inCombat() then
			self.dirtySecure = true
			return
		end
		self:Build()
	end
	if self.frame then self:ApplySecure() end
end

function BGTargets:SetDemo(on)
	self.demo = on and true or false
	self:Update()
end

function BGTargets:Toggle()
	ns.settings.bgTargets = not ns.settings.bgTargets
	self:Update()
	ns:Print(ns.settings.bgTargets and L.MSG_BGTARGETS_ON or L.MSG_BGTARGETS_OFF)
end

function BGTargets:Init()
	ns:Listen("BG_STATE_CHANGED", function() BGTargets:Update() end)
	ns:Listen("BG_ROSTER_CHANGED", function() BGTargets:Update() end)
	ns:Listen("BG_FLAG_CHANGED", function() BGTargets:Update() end)
	ns:On("PLAYER_REGEN_ENABLED", function()
		if BGTargets.dirtySecure then BGTargets:Update() end
	end)
end
