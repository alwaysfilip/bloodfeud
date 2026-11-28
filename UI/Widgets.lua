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
W.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
W.ICON = W.MEDIA .. "icon"
W.CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
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

--- Switch a font string to the narrow font used for capitals. SetFont raises
--- an error for a font file the client does not have; such a client keeps the
--- font the string was created with.
function W.CapsFont(fs, size)
	pcall(fs.SetFont, fs, W.CAPS_FONT, size or 12, "")
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

---------------------------------------------------------------------------
-- Pieces that show a player the way the game's own frames do: a portrait
-- with a level badge, a name on a class-coloured bar, tiles with numbers
-- and icons. Used by the alert banner and the radar.
---------------------------------------------------------------------------

--- A texture from the addon's Media folder. The glyphs are white, so a
--- colour tints them.
function W.Glyph(parent, name, size, color, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(W.MEDIA .. name)
	t:SetSize(size, size)
	if color then t:SetVertexColor(color[1], color[2], color[3], 1) end
	return t
end

--- The same glyph as an escape code for inside a text. r, g, b (0..255) tint it.
function W.Inline(name, size, r, g, b)
	if r then
		return ("|T%s%s:%d:%d:0:0:32:32:0:32:0:32:%d:%d:%d|t"):format(W.MEDIA, name, size, size, r, g, b)
	end
	return ("|T%s%s:%d:%d:0:0|t"):format(W.MEDIA, name, size, size)
end

--- Where a class sits in the game's sheet of round class icons, or nil.
function W.ClassCoords(classID)
	local file = ns.Fmt.ClassFile(classID)
	local sheet = _G.CLASS_ICON_TCOORDS
	local coords = file and type(sheet) == "table" and sheet[file]
	if type(coords) ~= "table" then return nil end
	return coords[1], coords[2], coords[3], coords[4]
end

--- The game's class icon as an escape code for inside a text; "" when the
--- class is not known.
function W.ClassInline(classID, size)
	local left, right, top, bottom = W.ClassCoords(classID)
	if not left then return "" end
	return ("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t"):format(W.CLASS_ICONS, size, size,
		left * 256, right * 256, top * 256, bottom * 256)
end

--- Point a texture at a class icon. Returns false when the class is not known.
function W.SetClassIcon(tex, classID)
	local left, right, top, bottom = W.ClassCoords(classID)
	if not left then return false end
	tex:SetTexture(W.CLASS_ICONS)
	tex:SetTexCoord(left, right, top, bottom)
	return true
end

--- Fill a texture with one colour, lit from the top. Flat on a client
--- without gradients.
function W.Gradient(tex, r, g, b)
	tex:SetTexture(W.FLAT)
	local make = _G.CreateColor
	if not (make and pcall(tex.SetGradient, tex, "VERTICAL", make(r * 0.7, g * 0.7, b * 0.7, 1), make(r, g, b, 1))) then
		tex:SetVertexColor(r, g, b, 1)
	end
end

--- Ink for text on a coloured bar: dark on a light colour, white on a dark one.
function W.Ink(r, g, b)
	if 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.42 then return 0.043, 0.047, 0.059, false end
	return 1, 1, 1, true
end

--- A name in capitals, unless it has letters string.upper cannot handle.
function W.NameCaps(name)
	if type(name) ~= "string" or name:find("[\128-\255]") then return name end
	return name:upper()
end

--- A round portrait: the class icon in a gold ring, with the level in a
--- badge. portrait:Set(classID, level, glyph, color): the glyph (a Media
--- name) stands in when the class is not known.
function W.Portrait(parent, size)
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(size, size)
	p.back = W.Glyph(p, "disc", size - 4, C.well, "BACKGROUND")
	p.back:SetPoint("CENTER")
	p.art = p:CreateTexture(nil, "ARTWORK")
	p.art:SetPoint("CENTER")
	p.ring = W.Glyph(p, "ring", size, nil, "OVERLAY")
	p.ring:SetPoint("CENTER")

	local badge = CreateFrame("Frame", nil, p)
	local badgeSize = math.floor(size * 0.44 + 0.5)
	badge:SetSize(badgeSize, badgeSize)
	badge:SetPoint("BOTTOMRIGHT", 4, -4)
	badge.back = W.Glyph(badge, "badge", badgeSize)
	badge.back:SetPoint("CENTER")
	badge.text = W.CapsFont(badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 10)
	badge.text:SetPoint("CENTER", 0, 0)
	p.badge = badge

	function p:Set(classID, level, glyph, color)
		if W.SetClassIcon(self.art, classID) then
			self.art:SetSize(size - 8, size - 8)
			self.art:SetVertexColor(1, 1, 1, 1)
			self.shows = "class"
		else
			color = color or C.muted
			self.art:SetTexture(W.MEDIA .. (glyph or "crosshair"))
			self.art:SetTexCoord(0, 1, 0, 1)
			self.art:SetSize(size * 0.5, size * 0.5)
			self.art:SetVertexColor(color[1], color[2], color[3], 1)
			self.shows = glyph or "crosshair"
		end
		if level then
			self.badge.text:SetText(tostring(level))
			self.badge:Show()
		else
			self.badge:Hide()
		end
	end
	return p
end

--- A name on a bar in the class colour, like a raid frame.
--- plate:Set(name, r, g, b): gold when no colour is given.
function W.NamePlate(parent, height)
	local n = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	n:SetHeight(height or 22)
	n:SetBackdrop({ edgeFile = W.FLAT, edgeSize = 1 })
	n:SetBackdropBorderColor(0, 0, 0, 1)
	n.fill = n:CreateTexture(nil, "BACKGROUND")
	n.fill:SetPoint("TOPLEFT", 1, -1)
	n.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	n.text = W.CapsFont(n:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 16)
	n.text:SetPoint("LEFT", 8, 0)
	n.text:SetPoint("RIGHT", -6, 0)
	n.text:SetJustifyH("LEFT")
	n.text:SetWordWrap(false)

	function n:Set(name, r, g, b)
		if not r then r, g, b = C.gold[1], C.gold[2], C.gold[3] end
		W.Gradient(self.fill, r, g, b)
		local ir, ig, ib, light = W.Ink(r, g, b)
		self.text:SetTextColor(ir, ig, ib)
		-- A drop shadow muddies dark ink; white ink needs it
		self.text:SetShadowOffset(light and 1 or 0, light and -1 or 0)
		self.text:SetText(W.NameCaps(name or ""))
	end
	return n
end

local GREEN_HEX, RED_HEX, COIN_HEX = "ff7bd88f", "ffff8a80", "fff3d57a"

--- A small box with a label and a figure. tile:Record(label, kills, deaths)
--- shows kills and deaths with a split bar; tile:Contract(label, points,
--- gold, pointsText, moreText) shows what a contract pays.
function W.Tile(parent, width, height)
	local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	t:SetSize(width, height)
	t.label = W.CapsFont(W.Label(t, "GameFontDisableSmall"), 10)
	t.label:SetPoint("TOP", 0, -5)
	t.value = W.CapsFont(W.Label(t, "GameFontHighlight"), 14)
	t.value:SetPoint("CENTER", 0, -2)
	t.sub = W.CapsFont(W.Label(t, "GameFontDisableSmall"), 10)
	t.sub:SetPoint("BOTTOM", 0, 5)
	t.sub:SetTextColor(C.soft[1], C.soft[2], C.soft[3])
	local track = width - 22
	t.lost = t:CreateTexture(nil, "ARTWORK")
	t.lost:SetTexture(W.FLAT)
	t.lost:SetVertexColor(0.898, 0.282, 0.302, 1)
	t.lost:SetSize(track, 3)
	t.lost:SetPoint("BOTTOM", 0, 6)
	t.won = t:CreateTexture(nil, "OVERLAY")
	t.won:SetTexture(W.FLAT)
	t.won:SetVertexColor(0.482, 0.847, 0.561, 1)
	t.won:SetHeight(3)
	t.won:SetPoint("LEFT", t.lost, "LEFT", 0, 0)

	function t:Record(label, kills, deaths)
		kills, deaths = kills or 0, deaths or 0
		W.Skin(self, C.well, C.edge)
		self.label:SetText(W.Caps(label))
		self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
		self.value:SetText(W.Inline("sword", 11, 123, 216, 143) .. " |c" .. GREEN_HEX .. kills .. "|r  "
			.. W.Inline("skull", 11, 255, 138, 128) .. " |c" .. RED_HEX .. deaths .. "|r")
		self.sub:SetText("")
		local total = kills + deaths
		self.lost:SetShown(total > 0)
		self.won:SetShown(kills > 0)
		if kills > 0 then self.won:SetWidth(math.max(1, track * kills / total)) end
		self.kills, self.deaths, self.gold, self.points = kills, deaths, nil, nil
	end

	function t:Contract(label, points, gold, pointsText, moreText)
		W.Skin(self, { 0.09, 0.075, 0.04 }, { 0.54, 0.435, 0.20 })
		self.label:SetText(W.Caps(label))
		self.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
		if (gold or 0) > 0 then
			self.value:SetText("|c" .. COIN_HEX .. gold .. "|r " .. W.Inline("coin", 13))
			self.sub:SetText(moreText or "")
		else
			self.value:SetText("|c" .. COIN_HEX .. (pointsText or tostring(points)) .. "|r")
			self.sub:SetText("")
		end
		self.lost:Hide()
		self.won:Hide()
		self.kills, self.deaths, self.gold, self.points = nil, nil, gold or 0, points
	end
	return t
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

	function b:SetStyle(value)
		self.style = value or "normal"
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
