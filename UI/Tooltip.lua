-- Adds the Kill on Sight lines to the tooltip of a listed player.
local _, ns = ...

local Util, Fmt, Names = ns.Util, ns.Fmt, ns.Names
local L = ns.L

local Tooltip = {}
ns.Tooltip = Tooltip

local MAX_REPORTS = 3

local function addPlayer(tooltip, subject)
	tooltip:AddLine(" ")
	tooltip:AddLine(L.TIP_TITLE, 1, 0.54, 0.50)
	for i = 1, math.min(#subject.reports, MAX_REPORTS) do
		local rec = subject.reports[i]
		if rec.reason ~= "" then tooltip:AddLine("“" .. rec.reason .. "”", 1, 1, 1, true) end
		tooltip:AddLine(L.TIP_BY:format(Names.Display(rec.author), Fmt.Ago(rec.at)), 0.79, 0.78, 0.74)
	end
	if #subject.reports > MAX_REPORTS then
		tooltip:AddLine(L.MORE:format(#subject.reports - MAX_REPORTS), 0.66, 0.65, 0.61)
	end
	if (subject.kills or 0) + (subject.deaths or 0) > 0 then
		tooltip:AddLine(L.TIP_SCORE:format(subject.kills, subject.deaths), 0.79, 0.78, 0.74)
	end
	local seen = subject.seen
	if seen then
		local zone = Fmt.Zone(seen.map)
		tooltip:AddLine(L.TIP_SEEN:format(Fmt.Ago(seen.at), zone and (" · " .. zone) or "")
			.. (seen.by and L.TIP_SEEN_BY:format(Names.Display(seen.by)) or ""), 0.79, 0.78, 0.74, true)
	end
end

local function addGuild(tooltip, guild)
	local first = guild.reports[1]
	tooltip:AddLine(" ")
	tooltip:AddLine(L.TIP_GUILD_TITLE, 1, 0.70, 0.28)
	if first.reason ~= "" then tooltip:AddLine("“" .. first.reason .. "”", 1, 1, 1, true) end
	tooltip:AddLine(L.TIP_BY:format(Names.Display(first.author), Fmt.Ago(first.at)), 0.79, 0.78, 0.74)
end

local function onUnit(tooltip)
	if tooltip ~= GameTooltip then return end
	local session = ns.session
	if not session or ns.Detect.paused then return end
	if type(tooltip.GetUnit) ~= "function" then return end
	local _, unit = tooltip:GetUnit()
	if not unit or Util.IsSecret(unit) then return end
	local info = ns.Detect.Inspect(unit)
	if not info then return end

	local key, how = ns.Detect.Match(session.store, info)
	if key then
		local subject = session.store:Player(key)
		if not subject then return end
		local known = subject.facts and subject.facts.guid
		if how == "first" and known and info.guid and known ~= info.guid then return end
		addPlayer(tooltip, subject)
	elseif info.guild and session.store:IsGuildListed(info.guild) then
		local guild = session.store:Guild(Util.Fold(info.guild))
		if guild then addGuild(tooltip, guild) end
	end
end

local function safeOnUnit(tooltip)
	-- A tooltip is drawn constantly; a failure here must stay silent.
	local ok, err = pcall(onUnit, tooltip)
	if not ok then ns:Debug("tooltip: %s", tostring(err)) end
end

function Tooltip:Init()
	local processor = _G.TooltipDataProcessor
	local unitType = _G.Enum and _G.Enum.TooltipDataType and _G.Enum.TooltipDataType.Unit
	if processor and processor.AddTooltipPostCall and unitType then
		processor.AddTooltipPostCall(unitType, safeOnUnit)
	elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
		GameTooltip:HookScript("OnTooltipSetUnit", safeOnUnit)
	else
		ns:Debug("no tooltip hook available")
	end
end
