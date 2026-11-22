-- What the player sees and hears when someone on the list is nearby.
--
-- The banner is built like one of the game's own unit frames rather than a
-- block of text: a portrait with the class icon and the level, the name on a
-- bar in the class colour, and tiles for the guild's record against them and
-- any contract. Only the intel and who sanctioned it are sentences.
local _, ns = ...

local Names, Fmt = ns.Names, ns.Fmt
local L = ns.L

local Alerts = { last = {} }
ns.Alerts = Alerts

local FLAT = "Interface\\Buttons\\WHITE8x8"
local SOUND_KOS = 8959 -- SOUNDKIT.RAID_WARNING
local SOUND_GUILD = 3081 -- SOUNDKIT.TELL_MESSAGE
local SOUND_ACHIEVEMENT = 888 -- SOUNDKIT.LEVEL_UP
local SOUND_TARGETED = 8960 -- SOUNDKIT.READY_CHECK
local SHOW_SECONDS = 7

local WIDTH, HEIGHT, LINE_H = 500, 112, 13
local PAD, PORTRAIT, ROW_TOP = 12, 48, 30
local TILE_W, TILE_H, TILE_GAP, WIDE_W = 74, 48, 6, 154

local RED, AMBER, GOLD = { 1, 0.42, 0.36 }, { 1, 0.70, 0.28 }, { 0.94, 0.78, 0.37 }
local GREEN, VIOLET, ORANGE = { 0.56, 0.82, 0.56 }, { 0.72, 0.55, 1 }, { 1, 0.55, 0.2 }

---------------------------------------------------------------------------
-- Banner
---------------------------------------------------------------------------

local banner

local function createBanner()
	local W = ns.W
	local C = W.C
	local f = CreateFrame("Frame", "BusinessMeetingAlertBanner", UIParent, "BackdropTemplate")
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("TOP", UIParent, "TOP", 0, -150)
	f:SetFrameStrata("HIGH")
	-- Near-black, with a dim edge and bright corner brackets in the alert's colour
	f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
	f:SetBackdropColor(0.043, 0.047, 0.059, 0.94)
	W.Brackets(f, { 1, 1, 1 }, 14, { "TOPLEFT", "BOTTOMRIGHT" })
	f:EnableMouse(false)
	f:Hide()

	-- Top line: what kind of alert, and on the right whether they are Kill on Sight
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(14, 14)
	f.icon:SetPoint("TOPLEFT", PAD, -9)
	f.title = W.CapsFont(f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), 13)
	f.title:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
	f.title:SetJustifyH("LEFT")
	f.badge = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.badge:SetSize(88, 16)
	f.badge:SetPoint("TOPRIGHT", -PAD, -7)
	W.Skin(f.badge, { 0.478, 0.078, 0.094 }, { 0.898, 0.282, 0.302 })
	f.badge.text = W.CapsFont(f.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11)
	f.badge.text:SetPoint("CENTER")
	f.badge.text:SetText(W.Caps(L.TIP_TITLE))
	f.tag = W.Caption(f)
	f.tag:SetJustifyH("RIGHT")

	-- Who it is about: portrait, name plate, and race, class and guild below it
	f.portrait = W.Portrait(f, PORTRAIT)
	f.portrait:SetPoint("TOPLEFT", PAD, -ROW_TOP)
	f.plate = W.NamePlate(f, 22)
	f.plate:SetPoint("TOPLEFT", PAD + PORTRAIT + 10, -(ROW_TOP + 1))
	f.name = f.plate.text
	f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.sub:SetPoint("TOPLEFT", f.plate, "BOTTOMLEFT", 1, -5)
	f.sub:SetPoint("RIGHT", f.plate, "RIGHT", 0, 0)
	f.sub:SetJustifyH("LEFT")
	f.sub:SetWordWrap(false)
	f.sub:SetTextColor(C.soft[1], C.soft[2], C.soft[3])

	-- Up to two tiles, or one wide one, at the right
	f.tiles = { W.Tile(f, TILE_W, TILE_H), W.Tile(f, TILE_W, TILE_H) }
	local wide = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.wide = wide
	wide:SetSize(WIDE_W, TILE_H)
	wide:SetPoint("TOPRIGHT", -PAD, -ROW_TOP)
	W.Skin(wide, C.well, C.edge)
	wide.left = W.CapsFont(W.Label(wide, "GameFontNormalSmall"), 12)
	wide.left:SetPoint("TOPLEFT", 8, -7)
	wide.left:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
	wide.right = W.CapsFont(W.Label(wide, "GameFontDisableSmall"), 12)
	wide.right:SetPoint("TOPRIGHT", -8, -7)
	wide.right:SetJustifyH("RIGHT")
	wide.right:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
	wide.bar = CreateFrame("StatusBar", nil, wide, "BackdropTemplate")
	wide.bar:SetPoint("BOTTOMLEFT", 8, 8)
	wide.bar:SetPoint("BOTTOMRIGHT", -8, 8)
	wide.bar:SetHeight(13)
	W.Skin(wide.bar, { 0, 0, 0 }, C.steel)
	wide.bar:SetStatusBarTexture(FLAT)
	wide.bar:SetStatusBarColor(C.gold[1], C.gold[2], C.gold[3], 1)
	wide.barText = W.CapsFont(wide.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 10)
	wide.barText:SetPoint("CENTER")
	wide.spell = wide:CreateTexture(nil, "ARTWORK")
	wide.spell:SetSize(34, 34)
	wide.spell:SetPoint("LEFT", 7, 0)
	wide.spellName = W.Label(wide, "GameFontHighlight")
	wide.spellName:SetPoint("TOPLEFT", wide.spell, "TOPRIGHT", 8, -3)
	wide.spellSub = W.Caption(wide, L.TILE_SPELL_NEAR)
	wide.spellSub:SetPoint("TOPLEFT", wide.spellName, "BOTTOMLEFT", 0, -4)

	-- Bottom line: the intel on the left, who sanctioned it on the right
	f.by = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.by:SetPoint("TOPRIGHT", -PAD, -(ROW_TOP + PORTRAIT + 8))
	f.by:SetJustifyH("RIGHT")
	f.detail = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.detail:SetPoint("TOPLEFT", PAD, -(ROW_TOP + PORTRAIT + 8))
	f.detail:SetPoint("RIGHT", f.by, "LEFT", -10, 0)
	f.detail:SetJustifyH("LEFT")
	f.detail:SetJustifyV("TOP")
	return f
end

--- The wide tile: the way to the next rank, or the spell someone just used.
local function setWide(wide, data)
	local W = ns.W
	local rank = data.kind == "rank"
	wide.left:SetShown(rank)
	wide.right:SetShown(rank)
	wide.bar:SetShown(rank)
	wide.spell:SetShown(not rank)
	wide.spellName:SetShown(not rank)
	wide.spellSub:SetShown(not rank)
	if rank then
		wide.left:SetText(W.Caps(data.title))
		wide.right:SetText(data.next and W.Caps(data.next) or "")
		wide.bar:SetMinMaxValues(0, math.max(1, data.need or data.have))
		wide.bar:SetValue(data.have)
		wide.barText:SetText(data.need and (data.have .. " / " .. data.need) or tostring(data.have))
	else
		if data.texture then
			wide.spell:SetTexture(data.texture)
			wide.spell:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			wide.spell:SetVertexColor(1, 1, 1, 1)
		else
			wide.spell:SetTexture(W.MEDIA .. "stealth")
			wide.spell:SetTexCoord(0, 1, 0, 1)
			wide.spell:SetVertexColor(VIOLET[1], VIOLET[2], VIOLET[3], 1)
		end
		wide.spellName:SetText(data.name or "")
	end
end

--- Show the banner. spec:
---   title, color {r, g, b}, icon (a Media name)   the top line
---   kos, tag                                      top right: the Kill on Sight badge, a short text
---   who {name, class, level, kind, guild, glyph, glyphColor}
---   tiles {{kind = "record", label, kills, deaths} | {kind = "contract", points, gold}}, at most two
---   wide {kind = "rank", title, next, have, need} | {kind = "spell", name, texture}, instead of tiles
---   line, by, lines                               the bottom line, its right-hand side, 1 or 2 lines
local function showBanner(spec)
	local W = ns.W
	banner = banner or createBanner()
	local f = banner
	f.spec = spec
	local r, g, b = spec.color[1], spec.color[2], spec.color[3]
	f:SetBackdropBorderColor(r * 0.45, g * 0.45, b * 0.45, 1)
	W.TintBrackets(f, r, g, b)
	f.icon:SetTexture(W.MEDIA .. (spec.icon or "crosshair"))
	f.icon:SetVertexColor(r, g, b, 1)
	f.title:SetText(W.Caps(spec.title))
	f.title:SetTextColor(r, g, b)

	f.badge:SetShown(spec.kos and true or false)
	f.tag:ClearAllPoints()
	if spec.kos then
		f.tag:SetPoint("RIGHT", f.badge, "LEFT", -8, 0)
	else
		f.tag:SetPoint("TOPRIGHT", -PAD, -10)
	end
	f.tag:SetText(spec.tag and W.Caps(spec.tag) or "")

	local who = spec.who
	f.portrait:Set(who.class, who.level, who.glyph, who.glyphColor)
	f.plate:Set(who.name, Fmt.ClassRGB(who.class))
	local sub = who.kind or ""
	if who.guild then sub = (sub ~= "" and (sub .. "  ") or "") .. Fmt.Color(Fmt.AMBER, "<" .. who.guild .. ">") end
	f.sub:SetText(sub)

	-- Tiles from the right edge inwards; the name plate takes what is left
	local tiles, used = spec.tiles or {}, 0
	f.wide:SetShown(spec.wide ~= nil)
	local count = 0
	if spec.wide then
		setWide(f.wide, spec.wide)
		used = WIDE_W
	else
		count = math.min(#tiles, #f.tiles)
		if count > 0 then used = count * TILE_W + (count - 1) * TILE_GAP end
	end
	for i = 1, #f.tiles do
		local tile, data = f.tiles[i], (i <= count) and tiles[i] or nil
		if data then
			tile:ClearAllPoints()
			tile:SetPoint("TOPRIGHT", -(PAD + (count - i) * (TILE_W + TILE_GAP)), -ROW_TOP)
			if data.kind == "contract" then
				tile:Contract(L.TILE_CONTRACT, data.points, data.gold, L.TILE_POINTS:format(data.points),
					L.TILE_POINTS_MORE:format(data.points))
			else
				tile:Record(data.label, data.kills, data.deaths)
			end
			tile:Show()
		else
			tile:Hide()
		end
	end
	f.plate:SetWidth(WIDTH - (PAD + PORTRAIT + 10) - PAD - used - (used > 0 and 10 or 0))

	local lines = spec.lines or 1
	f.detail:SetWordWrap(lines > 1)
	f.detail:SetMaxLines(lines)
	f.detail:SetText(spec.line or "")
	f.by:SetText(spec.by or "")
	f:SetHeight(HEIGHT + (lines - 1) * LINE_H)

	f:SetAlpha(1)
	f:Show()
	local token = (f.token or 0) + 1
	f.token = token
	C_Timer.After(SHOW_SECONDS, function()
		if banner.token == token then banner:Hide() end
	end)
end

local function play(soundID)
	if not ns.settings.sound or not _G.PlaySound then return end
	pcall(_G.PlaySound, soundID, "Master")
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

--- "added by Olaf, 3 d ago" plus the reason of the oldest report, and a
--- note when more guildmates have reported the same player.
function Alerts.ReasonLine(subject)
	local first = subject.reports[1]
	local reason = first.reason ~= "" and ("“" .. first.reason .. "”") or ""
	local by = L.ALERT_BY:format(Names.Display(first.author), Fmt.Ago(first.at))
	local more = #subject.reports > 1 and L.MORE:format(#subject.reports - 1) or ""
	if reason == "" then return by .. more end
	return reason .. " · " .. by .. more
end

local function cooled(key)
	local now = GetTime()
	local last = Alerts.last[key]
	if last and now - last < (ns.settings.alertCooldown or 60) then return false end
	Alerts.last[key] = now
	return true
end

---------------------------------------------------------------------------
-- What goes on the banner
---------------------------------------------------------------------------

--- The player an alert is about, from what was just seen and what the list
--- already knows.
local function person(seen, facts, fallbackName)
	facts = facts or {}
	local class = seen.class or facts.class
	local level = seen.level or facts.level
	if seen.high then level = "??" end -- the client hides the level of players far above ours
	return {
		name = Names.Display(seen.name or fallbackName),
		class = class,
		level = level,
		kind = Fmt.Kind({ race = seen.race or facts.race, class = class }),
		guild = seen.guild or facts.guild,
	}
end

--- The first report's reason in quotes ("" without one), and "sanctioned by
--- Olaf, 3 d ago (+2)".
local function intel(subject)
	local first = subject.reports[1]
	local line = first.reason ~= "" and ("“" .. first.reason .. "”") or ""
	local by = L.ALERT_BY:format(Names.Display(first.author), Fmt.Ago(first.at))
	if #subject.reports > 1 then by = by .. L.MORE:format(#subject.reports - 1) end
	return line, by
end

--- The guild's kills and deaths against someone, as a tile; nil before any fight.
local function recordTile(label, kills, deaths)
	kills, deaths = kills or 0, deaths or 0
	if kills + deaths == 0 then return nil end
	return { kind = "record", label = label, kills = kills, deaths = deaths }
end

--- The contracts on someone, as a tile, and the contracts themselves; nil
--- when there are none.
local function contractTile(seen, listKey)
	local bounties = ns.Bounties
	if not (bounties and bounties.Worth) then return nil end
	local points, n, list, gold = bounties:Worth(seen, listKey)
	if not n or n == 0 then return nil end
	return { kind = "contract", points = points, gold = gold or 0 }, list
end

--- A contract in one short piece of text, for when the tiles are taken.
local function contractText(tile)
	local text
	if tile.gold > 0 then
		text = tile.gold .. " " .. ns.W.Inline("coin", 12) .. "  " .. L.TILE_POINTS_MORE:format(tile.points)
	else
		text = L.TILE_POINTS:format(tile.points)
	end
	return Fmt.Color(Fmt.GOLD, text)
end

local function spellTexture(spellID)
	local api = _G.C_Spell and _G.C_Spell.GetSpellTexture
	if not api or not spellID then return nil end
	local ok, texture = pcall(api, spellID)
	if ok and texture and not ns.Util.IsSecret(texture) then return texture end
	return nil
end

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------

--- A listed player is in front of us. `seen` is what was just observed
--- (name, class, race, level, guild); `caveat` marks a name-only match.
function Alerts:Player(subject, seen, caveat)
	if not cooled("p:" .. subject.key) then return false end
	local facts = subject.facts or seen
	local hex = Fmt.ClassHex(seen.class or (subject.facts and subject.facts.class))
	local display = Names.Display(seen.name or subject.name)
	local name = hex and Fmt.Color(hex, display) or display
	local what = Fmt.Describe({ level = seen.level or facts.level, race = seen.race or facts.race,
		class = seen.class or facts.class })

	if ns.settings.banner then
		local tiles = {}
		tiles[#tiles + 1] = recordTile(L.TILE_GUILD, subject.kills, subject.deaths)
		tiles[#tiles + 1] = contractTile(seen, subject.key)
		local line, by = intel(subject)
		if caveat then line = Fmt.Color(Fmt.AMBER, L.ALERT_NAME_ONLY) .. (line ~= "" and ("\n" .. line) or "") end
		showBanner({ title = L.ALERT_TITLE, color = RED, icon = "skull", who = person(seen, subject.facts, subject.name),
			tiles = tiles, line = line, by = by, lines = caveat and 2 or 1 })
	end
	if ns.settings.chat then
		ns:Print(L.ALERT_CHAT:format(name, what ~= "" and (" (" .. what .. ")") or "", Alerts.ReasonLine(subject)))
	end
	play(SOUND_KOS)
	return true
end

--- A member of a listed guild is in front of us: a quieter alert.
--- `bounty` is the bounty line when there is also a price on their head.
function Alerts:Guild(guildSubject, seen, bounty)
	if not ns.settings.guildAlerts then return false end
	if not cooled("g:" .. seen.key) then return false end
	local hex = Fmt.ClassHex(seen.class)
	local display = Names.Display(seen.name)
	local name = hex and Fmt.Color(hex, display) or display
	if ns.settings.banner then
		local who = person(seen)
		who.guild = guildSubject.name
		local line, by = intel(guildSubject)
		showBanner({ title = L.ALERT_GUILD_TITLE, color = AMBER, icon = "guild", who = who,
			tiles = { bounty and contractTile(seen) or nil }, line = line, by = by })
	end
	if ns.settings.chat then
		ns:Print(L.ALERT_GUILD_CHAT:format(name, guildSubject.name) .. (bounty and (". " .. bounty) or ""))
	end
	play(SOUND_GUILD)
	return true
end

--- An enemy with a price on their head who is not on the list itself.
function Alerts:Bounty(seen, line)
	if not ns.settings.bountyAlerts then return false end
	if not cooled("b:" .. seen.key) then return false end
	local hex = Fmt.ClassHex(seen.class)
	local display = Names.Display(seen.name)
	local name = hex and Fmt.Color(hex, display) or display
	local what = Fmt.Describe(seen)
	if ns.settings.banner then
		local tile, list = contractTile(seen)
		local first = list and list[1] and list[1].rec
		local terms, by = "", ""
		if first then
			terms = first.reward ~= "" and ("“" .. first.reward .. "”") or ""
			by = Names.Display(first.author) .. (#list > 1 and L.MORE:format(#list - 1) or "")
		end
		showBanner({ title = L.ALERT_BOUNTY_TITLE, color = GOLD, icon = "coin", who = person(seen),
			tiles = { tile }, line = terms, by = by })
	end
	if ns.settings.chat then
		ns:Print(L.ALERT_BOUNTY_CHAT:format(name, what ~= "" and (" (" .. what .. ")") or "", line))
	end
	play(SOUND_GUILD)
	return true
end

--- What is known about an enemy, as short lines: Kill on Sight and why, how
--- the guild and the player have fared against them, a bounty.
function Alerts.DossierLines(about)
	local lines = {}
	if about.subject then
		lines[#lines + 1] = Fmt.Color(Fmt.RED, L.TIP_TITLE) .. ": " .. Alerts.ReasonLine(about.subject)
		if (about.kills or 0) + (about.deaths or 0) > 0 then
			lines[#lines + 1] = L.TARGET_GUILD_SCORE:format(about.deaths, about.kills)
		end
	else
		lines[#lines + 1] = Fmt.Color(Fmt.GREY, L.TARGET_NOT_LISTED)
	end
	if about.myKills + about.myDeaths > 0 then
		lines[#lines + 1] = L.TARGET_MY_SCORE:format(about.myDeaths, about.myKills)
	end
	if about.bounty then lines[#lines + 1] = Fmt.Color(Fmt.GOLD, about.bounty) end
	return lines
end

--- An enemy player near us just went into stealth, using `spell` (its name;
--- `spellID` finds its icon).
function Alerts:Stealth(seen, spell, about, spellID)
	local hex = Fmt.ClassHex(seen.class)
	local display = Names.Display(seen.name)
	local name = hex and Fmt.Color(hex, display) or display
	local what = Fmt.Describe(seen)
	local listed = about.subject and (Fmt.Color(Fmt.RED, L.TIP_TITLE) .. ": " .. Alerts.ReasonLine(about.subject)) or nil
	if ns.settings.banner then
		local line, by = "", ""
		if about.subject then line, by = intel(about.subject) end
		showBanner({ title = L.ALERT_STEALTH_TITLE, color = VIOLET, icon = "stealth", kos = about.subject ~= nil,
			who = person(seen, about.subject and about.subject.facts),
			wide = { kind = "spell", name = spell, texture = spellTexture(spellID) }, line = line, by = by })
	end
	if ns.settings.chat then
		ns:Print(L.ALERT_STEALTH_CHAT:format(name, what ~= "" and (" (" .. what .. ")") or "", spell)
			.. (listed and (" " .. listed) or ""))
	end
	play(SOUND_KOS)
	return true
end

--- An enemy player has just targeted us (or, with `pet`, our pet). `about`
--- is Targeting:Dossier.
function Alerts:Targeted(seen, about, pet)
	local hex = Fmt.ClassHex(seen.class)
	local display = Names.Display(seen.name)
	local name = hex and Fmt.Color(hex, display) or display
	local what = Fmt.Describe(seen)
	local guild = seen.guild and Fmt.Color(Fmt.AMBER, "<" .. seen.guild .. ">") or nil
	local lines = Alerts.DossierLines(about)
	if ns.settings.banner then
		-- The guild's record against them, then our own; a contract takes a
		-- tile when one is free and the bottom line when not.
		local tiles = {}
		if about.subject then tiles[#tiles + 1] = recordTile(L.TILE_GUILD, about.kills, about.deaths) end
		tiles[#tiles + 1] = recordTile(L.TILE_YOU, about.myKills, about.myDeaths)
		local line, by = Fmt.Color(Fmt.GREY, L.TARGET_NOT_LISTED), ""
		if about.subject then line, by = intel(about.subject) end
		local contract = contractTile(seen, about.listKey)
		if contract and #tiles < 2 then
			tiles[#tiles + 1] = contract
		elseif contract then
			by = contractText(contract)
		end
		showBanner({ title = pet and L.ALERT_TARGET_PET_TITLE or L.ALERT_TARGET_TITLE, color = ORANGE, icon = "crosshair",
			kos = about.subject ~= nil, who = person(seen, about.subject and about.subject.facts), tiles = tiles,
			line = line, by = by })
	end
	if ns.settings.chat then
		ns:Print((pet and L.ALERT_TARGET_PET_CHAT or L.ALERT_TARGET_CHAT):format(name, what ~= "" and (" (" .. what .. ")") or "",
			guild and (" " .. guild) or "") .. " " .. table.concat(lines, " · "))
	end
	if ns.settings.targetSound then play(SOUND_TARGETED) end
	return true
end

--- Our own killing blow on an enemy player: a confirmed kill. `st` are the
--- player's totals, `tier` the rank they hold and `nextTier` the one they are
--- working towards.
function Alerts:Deal(seen, st, nextTier, tier)
	if not ns.settings.banner then return false end
	local parts = { L.DEAL_COUNT:format(st.kills) }
	if st.streak > 1 then parts[#parts + 1] = L.DEAL_STREAK:format(st.streak) end
	if nextTier then parts[#parts + 1] = L.DEAL_NEXT:format(nextTier.kills - st.kills, nextTier.title) end
	showBanner({ title = L.DEAL_TITLE, color = GREEN, icon = "check", who = person(seen),
		tag = st.streak > 1 and L.DEAL_STREAK:format(st.streak) or nil,
		wide = { kind = "rank", title = tier and tier.title or L.UNRANKED, next = nextTier and nextTier.title,
			have = st.kills, need = nextTier and nextTier.kills },
		line = table.concat(parts, " · ") })
	return true
end

--- One of our own achievements was just earned.
function Alerts:Achievement(a)
	if ns.settings.banner then
		showBanner({ title = L.ACH_TITLE, color = GOLD, icon = "chevrons",
			who = { name = a.name, glyph = "chevrons", glyphColor = GOLD }, line = a.desc })
	end
	play(SOUND_ACHIEVEMENT)
end

--- Show the banner with sample data (used by /bm test).
function Alerts:Test()
	showBanner({ title = L.ALERT_TITLE, color = RED, icon = "skull",
		who = { name = "Grimtusk Bloodaxe", class = 4, level = 60, kind = Fmt.Kind({ race = 2, class = 4 }),
			guild = "Hostile Takeover" },
		tiles = { { kind = "record", label = L.TILE_GUILD, kills = 3, deaths = 7 }, { kind = "contract", points = 25, gold = 50 } },
		line = "“Ganking lowbies in STV”", by = L.ALERT_BY:format("Olaf", "3 d ago") })
	play(SOUND_KOS)
end
