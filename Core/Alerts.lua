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
local SHOW_SECONDS = 7

---------------------------------------------------------------------------
-- Banner
---------------------------------------------------------------------------

local banner

local function createBanner()
	local f = CreateFrame("Frame", "BloodFeudAlertBanner", UIParent, "BackdropTemplate")
	f:SetSize(480, 86)
	f:SetPoint("TOP", UIParent, "TOP", 0, -150)
	f:SetFrameStrata("HIGH")
	f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 2 })
	f:SetBackdropColor(0.10, 0.05, 0.05, 0.92)
	f:EnableMouse(false)
	f:Hide()

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(44, 44)
	f.icon:SetPoint("LEFT", 14, 0)
	f.icon:SetTexture(SKULL)

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
	f.detail:SetMaxLines(2)
	return f
end

local function showBanner(title, r, g, b, name, detail)
	banner = banner or createBanner()
	banner:SetBackdropBorderColor(r, g, b, 1)
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
		if caveat then detail = Fmt.Color(Fmt.AMBER, L.ALERT_NAME_ONLY) .. "\n" .. detail end
		showBanner(L.ALERT_TITLE, 1, 0.42, 0.36, name .. (line ~= "" and ("  |cffe8e6df" .. line .. "|r") or ""), detail)
	end
	if ns.settings.chat then
		ns:Print(L.ALERT_CHAT:format(name, what ~= "" and (" (" .. what .. ")") or "", Alerts.ReasonLine(subject)))
	end
	play(SOUND_KOS)
	return true
end

--- A member of a listed guild is in front of us: a quieter alert.
function Alerts:Guild(guildSubject, seen)
	if not ns.settings.guildAlerts then return false end
	if not cooled("g:" .. seen.key) then return false end
	local hex = Fmt.ClassHex(seen.class)
	local display = Names.Display(seen.name)
	local name = hex and Fmt.Color(hex, display) or display
	if ns.settings.banner then
		local what = Fmt.Describe(seen)
		showBanner(L.ALERT_GUILD_TITLE, 1, 0.70, 0.28,
			name .. "  " .. Fmt.Color(Fmt.AMBER, "<" .. guildSubject.name .. ">"),
			(what ~= "" and (what .. " · ") or "") .. Alerts.ReasonLine(guildSubject))
	end
	if ns.settings.chat then
		ns:Print(L.ALERT_GUILD_CHAT:format(name, guildSubject.name))
	end
	play(SOUND_GUILD)
	return true
end

--- Show the banner with sample data (used by /feud test).
function Alerts:Test()
	showBanner(L.ALERT_TITLE, 1, 0.42, 0.36, "|cfffff468Grimtusk Bloodaxe|r  |cffe8e6df60 Orc Rogue|r",
		"“Ganking lowbies in STV” · " .. L.ALERT_BY:format("Olaf", "3 d ago"))
	play(SOUND_KOS)
end
