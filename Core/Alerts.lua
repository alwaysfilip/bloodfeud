-- What the player sees and hears when someone on the list is nearby.
local _, ns = ...

local Names, Fmt = ns.Names, ns.Fmt
local L = ns.L

local Alerts = { last = {} }
ns.Alerts = Alerts

local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local FLAT = "Interface\\Buttons\\WHITE8x8"
local SOUND_KOS = 8959 -- SOUNDKIT.RAID_WARNING
local SOUND_GUILD = 3081 -- SOUNDKIT.TELL_MESSAGE
local SOUND_ACHIEVEMENT = 888 -- SOUNDKIT.LEVEL_UP
local SOUND_TARGETED = 8960 -- SOUNDKIT.READY_CHECK
local SHOW_SECONDS = 7

---------------------------------------------------------------------------
-- Banner
---------------------------------------------------------------------------

local banner

local function createBanner()
	local f = CreateFrame("Frame", "BusinessMeetingAlertBanner", UIParent, "BackdropTemplate")
	f:SetSize(480, 110)
	f:SetPoint("TOP", UIParent, "TOP", 0, -150)
	f:SetFrameStrata("HIGH")
	-- Near-black, with a dim edge and bright corner brackets in the alert's colour
	f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
	f:SetBackdropColor(0.043, 0.047, 0.059, 0.94)
	ns.W.Brackets(f, { 1, 1, 1 }, 16, { "TOPLEFT", "BOTTOMRIGHT" })
	f:EnableMouse(false)
	f:Hide()

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(44, 44)
	f.icon:SetPoint("LEFT", 14, 0)
	f.icon:SetTexture(SKULL)

	f.title = ns.W.CapsFont(f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), 12)
	f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, 10)
	f.title:SetJustifyH("LEFT")

	f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.name:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
	f.name:SetJustifyH("LEFT")

	f.detail = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.detail:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
	f.detail:SetPoint("RIGHT", f, "RIGHT", -12, 0)
	f.detail:SetJustifyH("LEFT")
	f.detail:SetWordWrap(true)
	f.detail:SetMaxLines(4)
	return f
end

--- `icon` is the skull for someone on the list; everything else gets the
--- addon's own mark.
local function showBanner(title, r, g, b, name, detail, icon)
	banner = banner or createBanner()
	banner:SetBackdropBorderColor(r * 0.45, g * 0.45, b * 0.45, 1)
	ns.W.TintBrackets(banner, r, g, b)
	banner.icon:SetTexture(icon or ns.W.ICON)
	banner.title:SetText(title:upper())
	banner.title:SetTextColor(r, g, b)
	banner.name:SetText(name)
	banner.detail:SetText(detail)
	banner:SetAlpha(1)
	banner:Show()
	local token = (banner.token or 0) + 1
	banner.token = token
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
	local guild = seen.guild or (subject.facts and subject.facts.guild)

	if ns.settings.banner then
		local line = what
		if guild then line = (line ~= "" and (line .. " · ") or "") .. Fmt.Color(Fmt.AMBER, "<" .. guild .. ">") end
		local detail = Alerts.ReasonLine(subject)
		local bounty = ns.Bounties and ns.Bounties:Line(seen, subject.key)
		if bounty then detail = detail .. "\n" .. Fmt.Color(Fmt.GOLD, bounty) end
		if caveat then detail = Fmt.Color(Fmt.AMBER, L.ALERT_NAME_ONLY) .. "\n" .. detail end
		showBanner(L.ALERT_TITLE, 1, 0.42, 0.36, name .. (line ~= "" and ("  |cffe8e6df" .. line .. "|r") or ""), detail,
			SKULL)
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
		local what = Fmt.Describe(seen)
		showBanner(L.ALERT_GUILD_TITLE, 1, 0.70, 0.28,
			name .. "  " .. Fmt.Color(Fmt.AMBER, "<" .. guildSubject.name .. ">"),
			(what ~= "" and (what .. " · ") or "") .. Alerts.ReasonLine(guildSubject)
				.. (bounty and ("\n" .. Fmt.Color(Fmt.GOLD, bounty)) or ""), SKULL)
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
		local guild = seen.guild and ("  " .. Fmt.Color(Fmt.AMBER, "<" .. seen.guild .. ">")) or ""
		showBanner(L.ALERT_BOUNTY_TITLE, 0.94, 0.78, 0.37, name .. guild, (what ~= "" and (what .. " · ") or "") .. line)
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

--- An enemy player near us just went into stealth, using `spell`.
function Alerts:Stealth(seen, spell, about)
	local hex = Fmt.ClassHex(seen.class)
	local display = Names.Display(seen.name)
	local name = hex and Fmt.Color(hex, display) or display
	local what = Fmt.Describe(seen)
	local guild = seen.guild and Fmt.Color(Fmt.AMBER, "<" .. seen.guild .. ">") or nil
	local listed = about.subject and (Fmt.Color(Fmt.RED, L.TIP_TITLE) .. ": " .. Alerts.ReasonLine(about.subject)) or nil
	if ns.settings.banner then
		local line = what
		if guild then line = (line ~= "" and (line .. " · ") or "") .. guild end
		showBanner(L.ALERT_STEALTH_TITLE, 0.72, 0.55, 1, name .. (line ~= "" and ("  |cffe8e6df" .. line .. "|r") or ""),
			L.ALERT_STEALTH_DETAIL:format(spell) .. (listed and ("\n" .. listed) or ""))
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
		local line = what
		if guild then line = (line ~= "" and (line .. " · ") or "") .. guild end
		showBanner(pet and L.ALERT_TARGET_PET_TITLE or L.ALERT_TARGET_TITLE, 1, 0.55, 0.2,
			name .. (line ~= "" and ("  |cffe8e6df" .. line .. "|r") or ""), table.concat(lines, "\n"))
	end
	if ns.settings.chat then
		ns:Print((pet and L.ALERT_TARGET_PET_CHAT or L.ALERT_TARGET_CHAT):format(name, what ~= "" and (" (" .. what .. ")") or "",
			guild and (" " .. guild) or "") .. " " .. table.concat(lines, " · "))
	end
	if ns.settings.targetSound then play(SOUND_TARGETED) end
	return true
end

--- Our own killing blow on an enemy player: a confirmed kill. `st` are the
--- player's totals, `nextTier` the rank they are working towards.
function Alerts:Deal(seen, st, nextTier)
	if not ns.settings.banner then return false end
	local hex = Fmt.ClassHex(seen.class)
	local display = Names.Display(seen.name)
	local name = hex and Fmt.Color(hex, display) or display
	local what = Fmt.Describe(seen)
	local parts = { L.DEAL_COUNT:format(st.kills) }
	if st.streak > 1 then parts[#parts + 1] = L.DEAL_STREAK:format(st.streak) end
	if nextTier then parts[#parts + 1] = L.DEAL_NEXT:format(nextTier.kills - st.kills, nextTier.title) end
	showBanner(L.DEAL_TITLE, 0.56, 0.82, 0.56, name .. (what ~= "" and ("  |cffe8e6df" .. what .. "|r") or ""),
		table.concat(parts, " · "))
	return true
end

--- One of our own achievements was just earned.
function Alerts:Achievement(a)
	if ns.settings.banner then
		showBanner(L.ACH_TITLE, 0.94, 0.78, 0.37, Fmt.Color(Fmt.GOLD, a.name), a.desc)
	end
	play(SOUND_ACHIEVEMENT)
end

--- Show the banner with sample data (used by /bm test).
function Alerts:Test()
	showBanner(L.ALERT_TITLE, 1, 0.42, 0.36, "|cfffff468Grimtusk Bloodaxe|r  |cffe8e6df60 Orc Rogue|r",
		"“Ganking lowbies in STV” · " .. L.ALERT_BY:format("Olaf", "3 d ago"), SKULL)
	play(SOUND_KOS)
end
