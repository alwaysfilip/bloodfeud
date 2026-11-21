-- Small building blocks for the addon's own frames. Everything is drawn from
-- plain frames and one flat texture, so it does not depend on which panel
-- templates a particular client ships or how it skins them.
local _, ns = ...

local W = {}
ns.W = W

W.FLAT = "Interface\\Buttons\\WHITE8x8"
W.SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

local PALETTE = {
	normal = { bg = { 0.10, 0.11, 0.14 }, border = { 0.29, 0.27, 0.20 }, text = { 0.91, 0.90, 0.87 } },
	hover = { bg = { 0.16, 0.17, 0.21 }, border = { 0.69, 0.55, 0.24 }, text = { 1, 1, 1 } },
	selected = { bg = { 0.17, 0.14, 0.07 }, border = { 0.69, 0.55, 0.24 }, text = { 0.94, 0.78, 0.37 } },
	danger = { bg = { 0.35, 0.08, 0.06 }, border = { 0.76, 0.29, 0.25 }, text = { 1, 0.89, 0.87 } },
	dangerHover = { bg = { 0.48, 0.11, 0.08 }, border = { 1, 0.54, 0.50 }, text = { 1, 1, 1 } },
	disabled = { bg = { 0.08, 0.09, 0.11 }, border = { 0.18, 0.19, 0.22 }, text = { 0.45, 0.45, 0.45 } },
}

--- Give a frame the flat dark look. Needs the BackdropTemplate mixin.
function W.Skin(frame, bg, border, alpha)
	frame:SetBackdrop({ bgFile = W.FLAT, edgeFile = W.FLAT, edgeSize = 1 })
	frame:SetBackdropColor(bg[1], bg[2], bg[3], alpha or 1)
	frame:SetBackdropBorderColor(border[1], border[2], border[3], 1)
end

function W.Panel(parent, name)
	local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
	W.Skin(f, { 0.06, 0.07, 0.09 }, { 0.42, 0.34, 0.16 }, 0.97)
	return f
end

function W.Label(parent, font, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	if text then fs:SetText(text) end
	return fs
end

--- A flat button. style is "normal" or "danger". Has SetSelected and
--- SetLabel besides the usual Enable/Disable.
function W.Button(parent, text, width, height, style)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width or 100, height or 26)
	b.style = style or "normal"
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("CENTER")
	b.label:SetText(text or "")

	local function paint()
		local look
		if not b:IsEnabled() then
			look = PALETTE.disabled
		elseif b.style == "danger" then
			look = b.hover and PALETTE.dangerHover or PALETTE.danger
		elseif b.selected then
			look = PALETTE.selected
		else
			look = b.hover and PALETTE.hover or PALETTE.normal
		end
		W.Skin(b, look.bg, look.border)
		b.label:SetTextColor(look.text[1], look.text[2], look.text[3])
	end
	b.Paint = paint

	b:SetScript("OnEnter", function(self)
		self.hover = true
		paint()
		if self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = false
		paint()
		GameTooltip:Hide()
	end)
	b:SetScript("OnEnable", paint)
	b:SetScript("OnDisable", paint)

	function b:SetSelected(value)
		self.selected = value and true or false
		paint()
	end

	function b:SetLabel(value)
		self.label:SetText(value)
	end

	paint()
	return b
end

--- A single-line text field.
function W.EditBox(parent, width, height, maxLetters)
	local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	e:SetSize(width or 160, height or 26)
	W.Skin(e, { 0.04, 0.04, 0.05 }, { 0.20, 0.22, 0.26 })
	e:SetAutoFocus(false)
	e:SetFontObject("ChatFontNormal")
	e:SetTextInsets(8, 8, 0, 0)
	if maxLetters then e:SetMaxLetters(maxLetters) end
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(0.69, 0.55, 0.24, 1) end)
	e:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0.20, 0.22, 0.26, 1) end)
	return e
end

--- Make a frame draggable by its own background and remember nothing: the
--- client restores the position of named, user-placed frames by itself.
function W.Movable(frame)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetUserPlaced(true)
end
