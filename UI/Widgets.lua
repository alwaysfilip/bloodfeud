-- Small building blocks for the addon's own frames. Everything is drawn from
-- plain frames and one flat texture, so it does not depend on which panel
-- templates a particular client ships or how it skins them.
--
-- The look: near-black panels with a thin steel edge, gold brackets in the
-- corners, and narrow capitals for titles, tabs and buttons.
local ADDON, ns = ...

local W = {}
ns.W = W

W.FLAT = "Interface\\Buttons\\WHITE8x8"
W.SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
W.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon"
W.CAPS_FONT = "Fonts\\ARIALN.TTF"

W.C = {
	panel = { 0.063, 0.071, 0.086 },
	well = { 0.031, 0.035, 0.043 },
	edge = { 0.169, 0.184, 0.212 },
	steel = { 0.227, 0.247, 0.282 },
	gold = { 0.831, 0.663, 0.306 },
	text = { 0.902, 0.890, 0.855 },
	soft = { 0.773, 0.784, 0.808 },
	muted = { 0.604, 0.627, 0.663 },
}
W.GOLD_HEX = "ffd4a94e"

local C = W.C
local PALETTE = {
	normal = { bg = C.panel, border = C.steel, text = C.soft },
	hover = { bg = { 0.10, 0.115, 0.14 }, border = { 0.54, 0.435, 0.20 }, text = { 1, 1, 1 } },
	selected = { bg = { 0.11, 0.095, 0.05 }, border = C.gold, text = C.gold },
	danger = { bg = { 0.478, 0.078, 0.094 }, border = { 0.898, 0.282, 0.302 }, text = { 1, 1, 1 } },
	dangerHover = { bg = { 0.58, 0.10, 0.12 }, border = { 1, 0.54, 0.50 }, text = { 1, 1, 1 } },
	disabled = { bg = C.panel, border = C.edge, text = { 0.49, 0.51, 0.55 } },
	-- Tabs have no box: the text carries the state, and the chosen one is underlined
	tab = { text = C.muted },
	tabHover = { text = C.text },
	tabSelected = { text = C.gold },
}

--- Capitals for a title or a label. Colour codes inside the text are kept.
function W.Caps(text)
	if not text then return text end
	return (text:upper():gsub("|C", "|c"):gsub("|R", "|r"))
end

--- Switch a font string to the narrow font used for capitals.
function W.CapsFont(fs, size)
	fs:SetFont(W.CAPS_FONT, size or 12, "")
	return fs
end

--- Give a frame the flat dark look. Needs the BackdropTemplate mixin.
function W.Skin(frame, bg, border, alpha)
	frame:SetBackdrop({ bgFile = W.FLAT, edgeFile = W.FLAT, edgeSize = 1 })
	frame:SetBackdropColor(bg[1], bg[2], bg[3], alpha or 1)
	frame:SetBackdropBorderColor(border[1], border[2], border[3], 1)
end

--- Brackets in the corners of a frame: two short bars per corner. Returns
--- the bars, so their colour can be changed with W.TintBrackets.
function W.Brackets(frame, color, length, corners)
	local bars = {}
	length = length or 14
	local function bar(point, width, height)
		local t = frame:CreateTexture(nil, "OVERLAY")
		t:SetTexture(W.FLAT)
		t:SetVertexColor(color[1], color[2], color[3], 1)
		t:SetSize(width, height)
		t:SetPoint(point, frame, point, 0, 0)
		bars[#bars + 1] = t
	end
	for _, point in ipairs(corners or { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
		bar(point, length, 2)
		bar(point, 2, length)
	end
	frame.brackets = bars
	return bars
end

function W.TintBrackets(frame, r, g, b)
	for _, bar in ipairs(frame.brackets or {}) do
		bar:SetVertexColor(r, g, b, 1)
	end
end

function W.Panel(parent, name)
	local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
	W.Skin(f, C.panel, C.edge, 0.97)
	W.Brackets(f, C.gold)
	return f
end

function W.Label(parent, font, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	if text then fs:SetText(text) end
	return fs
end

--- A title in capitals: gold unless another colour is given.
function W.Heading(parent, text, size, color)
	local fs = W.CapsFont(W.Label(parent, "GameFontNormalLarge"), size or 16)
	color = color or C.gold
	fs:SetTextColor(color[1], color[2], color[3])
	if text then fs:SetText(W.Caps(text)) end
	return fs
end

--- A small label in capitals, for column headers and field names.
function W.Caption(parent, text)
	local fs = W.CapsFont(W.Label(parent, "GameFontDisableSmall"), 11)
	fs:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
	if text then fs:SetText(W.Caps(text)) end
	return fs
end

--- A flat button with its label in capitals. style is "normal", "danger" or
--- "tab". Has SetSelected and SetLabel besides the usual Enable/Disable.
function W.Button(parent, text, width, height, style)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width or 100, height or 26)
	b.style = style or "normal"
	b.label = W.CapsFont(b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
	b.label:SetPoint("CENTER")
	b.label:SetText(W.Caps(text or ""))
	if b.style == "tab" then
		b.underline = b:CreateTexture(nil, "OVERLAY")
		b.underline:SetTexture(W.FLAT)
		b.underline:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
		b.underline:SetHeight(2)
		b.underline:SetPoint("BOTTOMLEFT", 0, 0)
		b.underline:SetPoint("BOTTOMRIGHT", 0, 0)
	end

	local function paint()
		local look
		if b.style == "tab" then
			look = (b.selected and PALETTE.tabSelected) or (b.hover and PALETTE.tabHover) or PALETTE.tab
			b.underline:SetShown(b.selected and true or false)
			b.label:SetTextColor(look.text[1], look.text[2], look.text[3])
			return
		end
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
		self.label:SetText(W.Caps(value))
	end

	paint()
	return b
end

--- A single-line text field.
function W.EditBox(parent, width, height, maxLetters)
	local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	e:SetSize(width or 160, height or 26)
	W.Skin(e, C.well, C.steel)
	e:SetAutoFocus(false)
	e:SetFontObject("ChatFontNormal")
	e:SetTextInsets(8, 8, 0, 0)
	if maxLetters then e:SetMaxLetters(maxLetters) end
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 1) end)
	e:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(C.steel[1], C.steel[2], C.steel[3], 1) end)
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
