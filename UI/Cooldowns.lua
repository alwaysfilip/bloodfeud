-- Compact, readable Enemy Cooldown Tracker HUD ("Counterclock" module).
-- Displays ONLY the active opponent's class cooldowns + PvP Trinket as clean
-- 34x34 icon tiles with slot numbers, countdown digits and draining bars.
local _, ns = ...

local W, Fmt, Names, Cooldowns = ns.W, ns.Fmt, ns.Names, ns.Cooldowns
local L = ns.L

local CooldownsUI = { hover = false }
ns.CooldownsUI = CooldownsUI

local ICON_SIZE, GAP, SLOTS = 34, 5, 6
local PAD, TOP = 10, 28
local WIDTH = PAD * 2 + SLOTS * ICON_SIZE + (SLOTS - 1) * GAP
local HEIGHT = TOP + ICON_SIZE + 14

local function fmtCD(sec)
	if sec >= 60 then return ("%dm"):format(math.ceil(sec / 60)) end
	if sec >= 10 then return tostring(math.ceil(sec)) end
	return ("%.1f"):format(sec)
end

local function createSlot(parent, i)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(ICON_SIZE, ICON_SIZE)
	b:SetPoint("TOPLEFT", PAD + (i - 1) * (ICON_SIZE + GAP), -TOP)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	W.Skin(b, W.C.well, W.C.steel)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	b.shade = b:CreateTexture(nil, "OVERLAY")
	b.shade:SetTexture(W.FLAT)
	b.shade:SetPoint("TOPLEFT", 2, -2)
	b.shade:SetPoint("BOTTOMRIGHT", -2, 2)
	b.shade:SetVertexColor(0, 0, 0, 0.65)
	b.shade:Hide()

	b.bar = CreateFrame("StatusBar", nil, b)
	b.bar:SetPoint("BOTTOMLEFT", 2, 2)
	b.bar:SetPoint("BOTTOMRIGHT", -2, 2)
	b.bar:SetHeight(4)
	b.bar:SetStatusBarTexture(W.FLAT)
	b.bar:SetStatusBarColor(W.C.gold[1], W.C.gold[2], W.C.gold[3], 1)
	b.bar:SetMinMaxValues(0, 1)
	b.bar:Hide()

	b.keyNum = W.CapsFont(W.Label(b, "GameFontDisableSmall", tostring(i)), 10)
	b.keyNum:SetPoint("TOPLEFT", 3, -2)
	b.keyNum:SetTextColor(W.C.soft[1], W.C.soft[2], W.C.soft[3])

	b.cd = W.CapsFont(W.Label(b, "GameFontHighlight"), 14)
	b.cd:SetPoint("CENTER", 0, 1)
	b.cd:SetJustifyH("CENTER")
	b.cd:Hide()

	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			Cooldowns:ResetSlot(i)
		else
			Cooldowns:TriggerSlot(i)
		end
	end)
	b:SetScript("OnEnter", function(self)
		self.hover = true
		CooldownsUI.hover = true
		CooldownsUI:ApplyAlpha()
		self:SetBackdropBorderColor(W.C.gold[1], W.C.gold[2], W.C.gold[3], 1)
		if self.spec then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(self.spec.name, 0.94, 0.78, 0.37)
			GameTooltip:AddLine(L.CD_DURATION:format(self.spec.cd), 1, 1, 1)
			GameTooltip:AddLine(L.CD_CLICK_HINT, 0.66, 0.65, 0.61, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = false
		CooldownsUI.hover = false
		CooldownsUI:ApplyAlpha()
		self:SetBackdropBorderColor(W.C.steel[1], W.C.steel[2], W.C.steel[3], 1)
		GameTooltip:Hide()
	end)
	return b
end

function CooldownsUI:ApplyAlpha()
	local f = self.frame
	if not f then return end
	local fade = ns.settings.hudFade and not self.hover
	f:SetAlpha(fade and 0.72 or 1)
end

function CooldownsUI:Build()
	local f = W.Panel(UIParent, "BusinessMeetingCooldownsFrame")
	self.frame = f
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
	f:SetFrameStrata("MEDIUM")
	W.Movable(f)
	f:Hide()

	f.title = W.Heading(f, L.CD_TITLE, 12, W.C.text)
	f.title:SetPoint("TOPLEFT", PAD, -8)
	f.title:SetPoint("RIGHT", -56, 0)

	local reset = W.Button(f, "R", 18, 16)
	reset:SetPoint("TOPRIGHT", -26, -6)
	reset.tip = L.CD_RESET_TIP
	reset:SetScript("OnClick", function() Cooldowns:ResetAll() end)

	local close = W.Button(f, "X", 18, 16)
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function()
		if Cooldowns.demo then
			Cooldowns:SetDemo(false)
		else
			Cooldowns:SetOpponent(nil)
		end
	end)

	f.slots = {}
	for i = 1, SLOTS do f.slots[i] = createSlot(f, i) end

	f:SetScript("OnEnter", function()
		CooldownsUI.hover = true
		CooldownsUI:ApplyAlpha()
	end)
	f:SetScript("OnLeave", function()
		CooldownsUI.hover = false
		CooldownsUI:ApplyAlpha()
	end)
	local since = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since >= 0.1 then
			since = 0
			CooldownsUI:Render()
		end
	end)
end

function CooldownsUI:Update()
	local cur = Cooldowns.current
	local want = (ns.settings.cdTracker or Cooldowns.demo) and cur ~= nil
	if not want then
		if self.frame then self.frame:Hide() end
		return
	end
	if not self.frame then self:Build() end
	local f = self.frame
	local hex = Fmt.ClassHex(cur.class)
	local disp = Names.Display(cur.name)
	local badge = cur.mode == "duel" and Fmt.Color(Fmt.GOLD, " [DUEL]")
		or (cur.mode == "demo" and Fmt.Color(Fmt.GREY, " [TEST]")
		or (cur.mode == "bg" and Fmt.Color("ff69a8ff", " [BG]")
		or Fmt.Color(Fmt.RED, " [PVP]")))
	f.title:SetText((hex and Fmt.Color(hex, W.Caps(disp)) or W.Caps(disp)) .. badge)

	local list = Cooldowns.SlotsFor(cur.class)
	for i = 1, SLOTS do
		local b, spec = f.slots[i], list[i]
		if b.oppKey ~= cur.key then
			b.oppKey, b.wasOnCD, b.flashUntil = cur.key, false, 0
		end
		b.spec = spec
		if spec then
			b.icon:SetTexture(Cooldowns.SpellTexture(spec))
			b:Show()
		else
			b:Hide()
		end
	end
	f:Show()
	self:ApplyAlpha()
	self:Render()
end

function CooldownsUI:Render()
	local f = self.frame
	if not f or not f:IsShown() or not Cooldowns.current then return end
	local now = GetTime()
	local list = Cooldowns.SlotsFor(Cooldowns.current.class)
	for i = 1, SLOTS do
		local b, spec = f.slots[i], list[i]
		if spec then
			local rem, dur = Cooldowns:Remaining(i)
			if rem > 0 and dur > 0 then
				b.wasOnCD = true
				b.flashUntil = 0
				b.shade:Show()
				b.cd:SetText(fmtCD(rem))
				b.cd:Show()
				b.bar:SetValue(math.min(1, rem / dur))
				b.bar:Show()
				b.icon:SetVertexColor(0.55, 0.55, 0.55, 1)
				b:SetBackdropBorderColor(W.C.steel[1], W.C.steel[2], W.C.steel[3], 1)
			else
				if b.wasOnCD then
					b.wasOnCD = false
					b.flashUntil = now + 1.5
				end
				b.shade:Hide()
				b.cd:Hide()
				b.bar:Hide()
				b.icon:SetVertexColor(1, 1, 1, 1)
				if b.flashUntil and now < b.flashUntil then
					b:SetBackdropBorderColor(W.C.gold[1], W.C.gold[2], W.C.gold[3], 1)
				elseif not b.hover then
					b:SetBackdropBorderColor(W.C.steel[1], W.C.steel[2], W.C.steel[3], 1)
				end
			end
		end
	end
end

function CooldownsUI:Toggle()
	ns.settings.cdTracker = not ns.settings.cdTracker
	self:Update()
	ns:Print(ns.settings.cdTracker and L.MSG_CD_ON or L.MSG_CD_OFF)
end

function CooldownsUI:Init()
	ns:Listen("COOLDOWNS_CHANGED", function() CooldownsUI:Update() end)
end
