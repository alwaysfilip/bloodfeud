-- Battleground countdown timer bars + score-pace projection HUD.
-- Inspired by Forever Simple Battleground Timers & Highground Battlegrounds,
-- styled with Business Meeting's near-black panels and gold corner brackets.
local _, ns = ...

local W, History = ns.W, ns.History
local L = ns.L

local BGTimersUI = {}
ns.BGTimersUI = BGTimersUI

local WIDTH, BAR_H, MAX_BARS = 260, 20, 8
local TOP = 28

local COLORS = {
	alliance = { 0.24, 0.52, 0.92 },
	horde = { 0.85, 0.25, 0.25 },
	neutral = { 0.831, 0.663, 0.306 },
	rez = { 0.35, 0.78, 0.88 },
}

local function createBar(parent, i)
	local bar = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
	bar:SetPoint("TOPLEFT", 8, -(TOP + (i - 1) * (BAR_H + 3)))
	bar:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
	bar:SetHeight(BAR_H)
	W.Skin(bar, { 0.03, 0.035, 0.045 }, W.C.steel)
	bar:SetStatusBarTexture(W.FLAT)
	bar:SetMinMaxValues(0, 1)
	bar.label = W.Label(bar, "GameFontHighlightSmall")
	bar.label:SetPoint("LEFT", 6, 0)
	bar.label:SetPoint("RIGHT", -44, 0)
	bar.label:SetWordWrap(false)
	bar.time = W.CapsFont(W.Label(bar, "GameFontHighlightSmall"), 12)
	bar.time:SetPoint("RIGHT", -6, 0)
	bar.time:SetJustifyH("RIGHT")
	bar:Hide()
	return bar
end

function BGTimersUI:ApplyAlpha()
	local f = self.frame
	if not f then return end
	local fade = ns.settings.hudFade and not self.hover
	f:SetAlpha(fade and 0.68 or 1)
end

function BGTimersUI:Build()
	local f = W.Panel(UIParent, "BusinessMeetingBGTimersFrame")
	self.frame = f
	f:SetSize(WIDTH, TOP + 40)
	f:SetPoint("TOP", UIParent, "TOP", 0, -90)
	f:SetFrameStrata("MEDIUM")
	W.Movable(f)
	f:Hide()

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("TOPLEFT", 10, -7)
	icon:SetTexture(W.ICON)
	f.title = W.Heading(f, L.BG_TIMERS_TITLE, 12, W.C.text)
	f.title:SetPoint("LEFT", icon, "RIGHT", 6, 0)

	local close = W.Button(f, "X", 18, 16)
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function()
		if ns.BGTimers.demo then
			ns.BGTimers:SetDemo(false)
		else
			ns.settings.bgTimers = false
		end
		BGTimersUI:Update()
	end)

	f.bars = {}
	for i = 1, MAX_BARS do f.bars[i] = createBar(f, i) end

	f.proj = W.CapsFont(W.Label(f, "GameFontHighlightSmall"), 11)
	f.proj:SetPoint("BOTTOMLEFT", 10, 7)
	f.proj:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	f.proj:SetJustifyH("CENTER")
	f.proj:Hide()

	f:SetScript("OnEnter", function()
		BGTimersUI.hover = true
		BGTimersUI:ApplyAlpha()
	end)
	f:SetScript("OnLeave", function()
		BGTimersUI.hover = false
		BGTimersUI:ApplyAlpha()
	end)
	local since = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since >= 0.1 then
			since = 0
			BGTimersUI:Render()
		end
	end)
end

function BGTimersUI:Update()
	local timers = ns.BGTimers
	local inBG = ns.Battleground and ns.Battleground.active
	local list = timers and timers:List() or {}
	local proj = timers and timers.projection
	local want = (timers and timers.demo) or (ns.settings.bgTimers and inBG and (#list > 0 or proj ~= nil))
	if not want then
		if self.frame then self.frame:Hide() end
		return
	end
	if not self.frame then self:Build() end
	self.frame:Show()
	self:ApplyAlpha()
	self:Render()
end

function BGTimersUI:Render()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local timers = ns.BGTimers
	local list = timers:List()
	local proj = timers.projection
	if not timers.demo and #list == 0 and not proj then
		f:Hide()
		return
	end
	local now = GetTime()
	local shown = math.min(#list, MAX_BARS)
	for i = 1, MAX_BARS do
		local bar = f.bars[i]
		local item = list[i]
		if item then
			local rem = math.max(0, item.endsAt - now)
			local frac = (item.duration and item.duration > 0) and math.min(1, rem / item.duration) or 0
			local c = COLORS[item.side] or COLORS.neutral
			bar:SetStatusBarColor(c[1] * 0.85, c[2] * 0.85, c[3] * 0.85, 1)
			bar:SetValue(frac)
			bar.label:SetText(item.label)
			bar.time:SetText(rem >= 60 and History.FormatDuration(math.ceil(rem)) or ("%.1fs"):format(rem))
			bar:Show()
		else
			bar:Hide()
		end
	end

	local projH = 0
	if proj and proj.winner and proj.eta then
		local sideColor = proj.winner == "Alliance" and "ff69a8ff" or "ffff7070"
		local text = "|c" .. sideColor .. W.Caps(proj.winner) .. "|r "
			.. L.TIMER_WINS_IN:format(History.FormatDuration(proj.eta))
		if proj.aBases and proj.hBases then
			text = text .. " · " .. proj.aBases .. "–" .. proj.hBases
		end
		if proj.basesNeeded then
			text = text .. " · " .. L.TIMER_NEED_BASES:format(proj.basesNeeded)
		end
		f.proj:SetText(W.Caps(text))
		f.proj:Show()
		projH = 22
	else
		f.proj:Hide()
	end

	f:SetHeight(TOP + shown * (BAR_H + 3) + projH + 8)
end

function BGTimersUI:Toggle()
	ns.settings.bgTimers = not ns.settings.bgTimers
	self:Update()
	ns:Print(ns.settings.bgTimers and L.MSG_BGTIMERS_ON or L.MSG_BGTIMERS_OFF)
end

function BGTimersUI:Init()
	ns:Listen("BGTIMERS_CHANGED", function() BGTimersUI:Update() end)
	ns:Listen("BG_STATE_CHANGED", function() BGTimersUI:Update() end)
end
