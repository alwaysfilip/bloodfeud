-- Adds the Kill on Sight and bounty lines to the tooltip of an enemy player,
-- and a guildmate's Business Meeting rank to theirs.
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

local function addBounty(tooltip, info, key)
	local line = ns.Bounties and ns.Bounties:Line(info, key)
	if line then tooltip:AddLine(line, 0.94, 0.78, 0.37) end
end

--- A guildmate: their Business Meeting rank, if they run the addon.
local function addGuildmate(tooltip, session, unit)
	if not _G.UnitIsInMyGuild then return end
	local ok, inGuild = pcall(_G.UnitIsInMyGuild, unit)
	if not (ok and not Util.IsSecret(inGuild) and inGuild) then return end
	local name = Names.OfUnit(unit)
	if not name then return end
	local key = Names.Key(name)
	local disgrace = ns.Debts and ns.Debts:Dishonor(key)
	if disgrace then
		tooltip:AddLine(L.TIP_DISHONORED:format(disgrace.gold, Names.Display(disgrace.winner)), 1, 0.54, 0.50)
		return
	end
	local rec = session.store:Member(key)
	if not rec then return end
	local total = ns.Progress.TotalKills(rec)
	local rank = ns.Progress.RankFor(total, ns.Progress.Ladder(session.store))
	if (rec.bgKills or 0) > 0 then
		tooltip:AddLine(L.TIP_GUILDMATE_SPLIT:format(rank and rank.title or L.UNRANKED, total, rec.kills or 0, rec.bgKills),
			0.94, 0.78, 0.37)
	else
		tooltip:AddLine(L.TIP_GUILDMATE:format(rank and rank.title or L.UNRANKED, total), 0.94, 0.78, 0.37)
	end
end

local function onUnit(tooltip)
	if tooltip ~= GameTooltip then return end
	local session = ns.session
	if not session or ns.Detect.paused then return end
	if type(tooltip.GetUnit) ~= "function" then return end
	local _, unit = tooltip:GetUnit()
	if not unit or Util.IsSecret(unit) then return end
	local info = ns.Detect.Inspect(unit)
	if not info then
		addGuildmate(tooltip, session, unit)
		return
	end

	local key = ns.Detect.Match(session.store, info)
	if key then
		local subject = session.store:Player(key)
		if not subject then return end
		addPlayer(tooltip, subject)
		addBounty(tooltip, info, key)
	elseif info.guild and session.store:IsGuildListed(info.guild) then
		local guild = session.store:Guild(Util.Fold(info.guild))
		if guild then addGuild(tooltip, guild) end
		addBounty(tooltip, info)
	elseif ns.Bounties and ns.Bounties:Line(info) then
		tooltip:AddLine(" ")
		addBounty(tooltip, info)
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
