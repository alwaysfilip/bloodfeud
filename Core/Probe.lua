-- /feud probe: a diagnostic report of how this client answers the questions
-- the addon depends on (name shapes, guild ranks, what is readable about an
-- enemy, whether addon messages loop back). It is saved to the addon's
-- SavedVariables so it can be read from disk after a /reload.
--
-- Names are masked to their shape ("Aaaa-Aaaaaaa") so the report says how
-- names are formatted without recording whose they are.
local _, ns = ...

local Util, Names, Roster = ns.Util, ns.Names, ns.Roster

local Probe = {}
ns.Probe = Probe

local function mask(value)
	if value == nil then return "nil" end
	if Util.IsSecret(value) then return "<secret>" end
	if type(value) ~= "string" then return "<" .. type(value) .. ":" .. tostring(value) .. ">" end
	local out = value:gsub("[\194-\244][\128-\191]*", "ü"):gsub("%u", "A"):gsub("%l", "a"):gsub("%d", "9")
	return '"' .. out .. '"'
end

local function show(value)
	if value == nil then return "nil" end
	if Util.IsSecret(value) then return "<secret>" end
	return tostring(value)
end

local function try(fn, ...)
	if type(fn) ~= "function" then return false, "missing" end
	return pcall(fn, ...)
end

local function describeUnit(add, unit)
	add("[" .. unit .. "]")
	local ok, exists = try(_G.UnitExists, unit)
	add("  exists: " .. show(ok and exists))
	if not (ok and exists and not Util.IsSecret(exists)) then return end
	add("  UnitIsPlayer: " .. show(select(2, try(_G.UnitIsPlayer, unit))))
	add("  UnitIsEnemy(player): " .. show(select(2, try(_G.UnitIsEnemy, "player", unit))))
	add("  UnitCanAttack(player): " .. show(select(2, try(_G.UnitCanAttack, "player", unit))))
	add("  faction: " .. show(select(2, try(_G.UnitFactionGroup, unit))))
	for _, fname in ipairs({ "UnitName", "UnitNameUnmodified", "UnitFullName" }) do
		local okName, a, b = try(_G[fname], unit)
		add(("  %s: %s, %s"):format(fname, okName and mask(a) or ("error " .. tostring(a)), okName and mask(b) or "-"))
	end
	local nameUtil = _G.NameUtil
	if nameUtil and nameUtil.GetUnmodifiedUnitFullName then
		local okFull, full = try(nameUtil.GetUnmodifiedUnitFullName, unit)
		add("  NameUtil.GetUnmodifiedUnitFullName: " .. (okFull and mask(full) or ("error " .. tostring(full))))
	end
	add("  canonical: " .. mask(Names.OfUnit(unit)))
	add("  UnitGUID: " .. mask(select(2, try(_G.UnitGUID, unit))))
	local okClass, _, classFile, classID = try(_G.UnitClass, unit)
	add("  UnitClass: " .. (okClass and (show(classFile) .. " / " .. show(classID)) or "error"))
	local okRace, _, raceFile, raceID = try(_G.UnitRace, unit)
	add("  UnitRace: " .. (okRace and (show(raceFile) .. " / " .. show(raceID)) or "error"))
	add("  UnitLevel: " .. show(select(2, try(_G.UnitLevel, unit))))
	local okGuild, guild, rankName, rankIndex = try(_G.GetGuildInfo, unit)
	add(("  GetGuildInfo: %s, rank %s (%s)"):format(okGuild and mask(guild) or "error", okGuild and mask(rankName) or "-",
		okGuild and show(rankIndex) or "-"))
	local info = select(2, pcall(ns.Detect.Inspect, unit))
	add("  Detect.Inspect: " .. (type(info) == "table" and "enemy player, readable" or show(info)))

	local plates = _G.C_NamePlate
	if plates and plates.GetNamePlateForUnit then
		local okPlate, plate = try(plates.GetNamePlateForUnit, unit)
		if okPlate and plate then
			local forbidden = plate.IsForbidden and plate:IsForbidden()
			add("  nameplate: found, forbidden=" .. show(forbidden))
			if not forbidden then
				local okAttach, err = pcall(function()
					local f = CreateFrame("Frame", nil, plate)
					f:SetSize(8, 8)
					f:SetPoint("BOTTOM", plate, "TOP", 0, 2)
					f:Show()
					f:Hide()
					f:SetParent(nil)
				end)
				add("  nameplate attach: " .. (okAttach and "ok" or ("error " .. tostring(err))))
			end
		else
			add("  nameplate: none for this unit" .. (okPlate and "" or (" (" .. tostring(plate) .. ")")))
		end
	end
end

local function collect(add)
	add("Blood Feud probe " .. date("%Y-%m-%d %H:%M:%S"))
	local okBuild, version, build, buildDate, toc = try(_G.GetBuildInfo)
	add(("build: %s %s %s toc %s"):format(show(okBuild and version), show(build), show(buildDate), show(toc)))
	add("WOW_PROJECT_ID: " .. show(_G.WOW_PROJECT_ID) .. "  locale: " .. show(select(2, try(_G.GetLocale))))
	local meta = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata
	add("addon version: " .. show(meta and select(2, try(meta, ns.ADDON, "Version"))))

	add("")
	add("== names ==")
	add("RegionalUniqueNamesEnabled: " .. show(select(2, try(_G.RegionalUniqueNamesEnabled))))
	local consts = _G.Constants and _G.Constants.CharacterNameSeparatorConsts
	add("surname separator: " .. (consts and ("%q"):format(tostring(consts.CHARACTERNAME_SURNAME_SEPARATOR)) or "n/a")
		.. "  realm separator: " .. (consts and ("%q"):format(tostring(consts.CHARACTERNAME_REALMNAME_SEPARATOR)) or "n/a"))
	add("GetNormalizedRealmName: " .. mask(select(2, try(_G.GetNormalizedRealmName))))
	local playerInfo = _G.C_PlayerInfo
	add("C_PlayerInfo.ShouldDisplaySurname: " .. show(playerInfo and select(2, try(playerInfo.ShouldDisplaySurname))))
	describeUnit(add, "player")

	add("")
	add("== guild ==")
	add("IsInGuild: " .. show(select(2, try(_G.IsInGuild))))
	local okGuild, guildName, rankName, rankIndex = try(_G.GetGuildInfo, "player")
	add(("GetGuildInfo(player): %s, rank %s (%s)"):format(okGuild and mask(guildName) or "error", mask(rankName),
		show(rankIndex)))
	add("IsGuildLeader: " .. show(select(2, try(_G.IsGuildLeader))))
	local guildInfo = _G.C_GuildInfo
	add("C_GuildInfo.IsGuildOfficer: " .. show(guildInfo and select(2, try(guildInfo.IsGuildOfficer))))
	add("Roster.AmOfficer (addon rule): " .. show(Roster.AmOfficer()) .. "  roster loaded: " .. Roster.count)
	local total = select(2, try(_G.GetNumGuildMembers))
	add("GetNumGuildMembers: " .. show(total) .. "  GetGuildRosterInfo: " .. type(_G.GetGuildRosterInfo))
	if type(_G.GetGuildRosterInfo) == "function" and type(total) == "number" then
		for i = 1, math.min(total, 4) do
			local ok, name, rName, rIndex = pcall(_G.GetGuildRosterInfo, i)
			add(("  member %d: %s rank %s (%s)"):format(i, ok and mask(name) or "error", mask(rName), show(rIndex)))
		end
	end
	local numRanks = select(2, try(_G.GuildControlGetNumRanks))
	add("GuildControlGetNumRanks: " .. show(numRanks))
	if guildInfo and guildInfo.GuildControlGetRankFlags and type(numRanks) == "number" then
		for order = 1, math.min(numRanks, 10) do
			local ok, flags = pcall(guildInfo.GuildControlGetRankFlags, order)
			if ok and type(flags) == "table" then
				add(("  rank order %d: flag22=%s flag4=%s flags=%d addonRule=%s"):format(order, show(flags[22]), show(flags[4]),
					#flags, show(Roster.RankIsOfficer(order - 1))))
			else
				add(("  rank order %d: %s"):format(order, ok and type(flags) or ("error " .. tostring(flags))))
			end
		end
	end
	local club = _G.C_Club
	if club and club.GetGuildClubId then
		local okClub, clubId = try(club.GetGuildClubId)
		add("C_Club.GetGuildClubId: " .. (okClub and (clubId and "present" or "nil") or "error"))
		if okClub and clubId and club.GetClubMembers then
			local okMembers, ids = try(club.GetClubMembers, clubId)
			add("  club members: " .. (okMembers and type(ids) == "table" and #ids or "error"))
			if okMembers and type(ids) == "table" and ids[1] and club.GetMemberInfo then
				local okInfo, info = try(club.GetMemberInfo, clubId, ids[1])
				if okInfo and type(info) == "table" then
					add(("  first member: name %s role %s guildRankOrder %s"):format(mask(info.name), show(info.role),
						show(info.guildRankOrder)))
				end
			end
		end
	end

	add("")
	add("== restrictions ==")
	add("issecretvalue: " .. type(_G.issecretvalue))
	local chatInfo = _G.C_ChatInfo
	add("InChatMessagingLockdown: " .. show(chatInfo and select(2, try(chatInfo.InChatMessagingLockdown))))
	local okInstance, inInstance, instanceType = try(_G.IsInInstance)
	add("IsInInstance: " .. show(okInstance and inInstance) .. " / " .. show(instanceType))
	local restricted = _G.C_RestrictedActions
	local types = _G.Enum and _G.Enum.AddOnRestrictionType
	if restricted and restricted.IsAddOnRestrictionActive and types then
		for name, value in pairs(types) do
			add(("  restriction %s: %s"):format(name, show(select(2, try(restricted.IsAddOnRestrictionActive, value)))))
		end
	end

	add("")
	add("== target / mouseover / focus ==")
	describeUnit(add, "target")
	describeUnit(add, "mouseover")
	describeUnit(add, "focus")

	add("")
	add("== kills and deaths ==")
	local feuds = ns.Feuds
	add(("events registered: PARTY_KILL=%s PLAYER_DEAD=%s  UnitTokenFromGUID: %s"):format(show(feuds.events.PARTY_KILL),
		show(feuds.events.PLAYER_DEAD), type(_G.UnitTokenFromGUID)))
	local st = feuds.stats
	add(("this session: PARTY_KILL %d (secret %d, mine %d, identified %d), deaths %d (killer identified %d)"):format(
		st.kills, st.killsSecret, st.killsMine, st.killsKnown, st.deaths, st.deathsKnown))
	local recap = _G.C_DeathRecap
	add("C_DeathRecap: " .. type(recap) .. "  HasRecapEvents: " .. show(recap and select(2, try(recap.HasRecapEvents))))
	if recap and recap.GetRecapEvents then
		local okEvents, events = try(recap.GetRecapEvents)
		if okEvents and type(events) == "table" then
			add("  newest recap: " .. #events .. " events")
			for i = 1, math.min(#events, 3) do
				local e = events[i]
				if type(e) == "table" then
					local fields = {}
					for k, v in pairs(e) do
						local shown = (type(v) == "string") and mask(v) or show(v)
						fields[#fields + 1] = tostring(k) .. "=" .. shown
					end
					table.sort(fields)
					add(("  event %d: %s"):format(i, table.concat(fields, " ")))
				else
					add(("  event %d: %s"):format(i, show(e)))
				end
			end
			local okKiller, killer, why = pcall(feuds.Killer, feuds)
			add("  killer identified: " .. (okKiller and (killer and ("yes " .. mask(killer.name)) or ("no (" .. show(why) .. ")"))
				or ("error " .. tostring(killer))))
		else
			add("  GetRecapEvents: " .. (okEvents and type(events) or ("error " .. tostring(events))))
		end
	end

	add("")
	add("== who targets me ==")
	local ts = ns.Targeting.stats
	add(("this session: looks %d, could not tell %d, enemies seen targeting me %d  UnitIsUnit: %s"):format(ts.checks,
		ts.unknown, ts.hits, type(_G.UnitIsUnit)))
	for _, unit in ipairs({ "target", "focus", "nameplate1" }) do
		if select(2, try(_G.UnitExists, unit)) == true then
			local theirs = unit .. "target"
			add(("[%s] has a target: %s  UnitIsUnit(%s, player): %s  its GUID: %s  Targeting.Check: %s"):format(unit,
				show(select(2, try(_G.UnitExists, theirs))), theirs, show(select(2, try(_G.UnitIsUnit, theirs, "player"))),
				mask(select(2, try(_G.UnitGUID, theirs))), show(select(2, pcall(ns.Targeting.Check, unit)))))
		end
	end

	add("")
	add("== stealth ==")
	local ss = ns.Stealth.stats
	local known = {}
	for name in pairs(ns.Stealth.names) do known[#known + 1] = name end
	table.sort(known)
	add(("UNIT_SPELLCAST_SUCCEEDED registered: %s  this session: casts by others %d, spell withheld %d, stealth seen %d"):format(
		show(ns.Stealth.events.UNIT_SPELLCAST_SUCCEEDED), ss.casts, ss.secret, ss.hits))
	add("spell names watched: " .. table.concat(known, ", ") .. "  C_Spell.GetSpellName: "
		.. type(_G.C_Spell and _G.C_Spell.GetSpellName))
	for id, english in pairs(ns.Stealth.KNOWN) do
		add(("  spell %d (%s) is called here: %s"):format(id, english,
			show(_G.C_Spell and _G.C_Spell.GetSpellName and select(2, try(_G.C_Spell.GetSpellName, id)))))
	end

	add("")
	add("== mail and trade (bounty gold) ==")
	local debts = ns.Debts
	local function kinds(names)
		local parts = {}
		for _, name in ipairs(names) do parts[#parts + 1] = name .. "=" .. type(_G[name]) end
		return table.concat(parts, " ")
	end
	add("mail: " .. kinds({ "GetInboxNumItems", "GetInboxHeaderInfo", "SendMail", "SetSendMailMoney", "GetSendMailMoney",
		"hooksecurefunc" }))
	add("trade: " .. kinds({ "GetPlayerTradeMoney", "GetTargetTradeMoney", "GetMoney" }) .. "  ERR_TRADE_COMPLETE="
		.. type(_G.ERR_TRADE_COMPLETE))
	local events = {}
	for _, name in ipairs({ "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "TRADE_SHOW", "TRADE_ACCEPT_UPDATE",
		"TRADE_CLOSED", "UI_INFO_MESSAGE" }) do
		events[#events + 1] = name .. "=" .. show(debts.events[name])
	end
	add("events registered: " .. table.concat(events, " "))
	local ds = debts.stats
	add(("this session: inbox scans %d, mails with gold read %d, senders unreadable %d, gold mails sent %d, trades %d")
		:format(ds.scans, ds.mails, ds.unreadable, ds.sends, ds.trades))
	-- With the mailbox open, what one inbox line looks like to an addon.
	if _G.GetInboxNumItems and _G.GetInboxHeaderInfo then
		local okCount, count = try(_G.GetInboxNumItems)
		add("inbox now: " .. show(okCount and count) .. " mails (0 unless a mailbox is open)")
		if okCount and type(count) == "number" and count > 0 then
			local okMail, _, _, sender, _, money = try(_G.GetInboxHeaderInfo, 1)
			add("  first mail: sender " .. (okMail and mask(sender) or "error") .. ", money " .. show(okMail and money))
		end
	end

	add("")
	add("== interface APIs ==")
	add("Menu.ModifyMenu: " .. type(_G.Menu and _G.Menu.ModifyMenu))
	add("TooltipDataProcessor.AddTooltipPostCall: " .. type(_G.TooltipDataProcessor and _G.TooltipDataProcessor.AddTooltipPostCall))
	add("Settings.RegisterAddOnSetting: " .. type(_G.Settings and _G.Settings.RegisterAddOnSetting))
	add("AddonCompartmentFrame: " .. type(_G.AddonCompartmentFrame))
	add("C_CreatureInfo.GetClassInfo: " .. type(_G.C_CreatureInfo and _G.C_CreatureInfo.GetClassInfo))
	add("C_Map.GetPlayerMapPosition: " .. type(_G.C_Map and _G.C_Map.GetPlayerMapPosition))
	local map, x, y = ns.Fmt.PlayerPosition()
	add("position: map " .. show(map) .. " x " .. show(x) .. " y " .. show(y) .. " zone " .. show(ns.Fmt.Zone(map)))
	local libStub = _G.LibStub
	add("ChatThrottleLib: " .. show(_G.ChatThrottleLib and _G.ChatThrottleLib.version))
	for _, lib in ipairs({ "CallbackHandler-1.0", "LibDataBroker-1.1", "LibDBIcon-1.0" }) do
		local okLib, _, minor = pcall(function() return libStub:GetLibrary(lib, true) end)
		add(lib .. ": " .. (okLib and show(minor) or "error"))
	end

	add("")
	add("== session ==")
	local session = ns.session
	if session then
		local players, guilds = session.store:Counts()
		local stats = session.sync.stats
		add(("guild bound, me=%s, %d players, %d guilds, %d synced records"):format(mask(session.me), players, guilds,
			session.store:Count()))
		add(("frames sent: H=%d U=%d  denied=%d bad=%d  peers=%d  locked=%s"):format(stats.H, stats.U, stats.denied, stats.bad,
			session.sync:PeerCount(), show(session.sync.locked)))
	else
		add("no session (not in a guild, or guild name not loaded yet)")
	end
	add("prefix registration: " .. show(ns.Comm.registered and ns.Comm.registered[2]) .. " / "
		.. show(ns.Comm.registeredSight and ns.Comm.registeredSight[2]))
end

--- Run the probe. The addon-message loopback part finishes a few seconds
--- later; `done(lines)` is called then.
function Probe:Run(done)
	local lines = {}
	local function add(text) lines[#lines + 1] = text end
	local okCollect, err = pcall(collect, add)
	if not okCollect then add("PROBE ERROR: " .. tostring(err)) end

	add("")
	add("== addon message loopback ==")
	local nonce = "P" .. tostring(math.random(100000, 999999))
	local heard
	ns.Comm.onRaw = function(prefix, text, sender)
		if prefix == ns.PREFIX_SIGHT and text == nonce then heard = sender end
	end
	local chatInfo = _G.C_ChatInfo
	if ns.Comm.CanSend() and chatInfo and chatInfo.SendAddonMessage then
		local okSend, result = pcall(chatInfo.SendAddonMessage, ns.PREFIX_SIGHT, nonce, "GUILD")
		add("SendAddonMessage(GUILD): " .. (okSend and show(result) or ("error " .. tostring(result))))
	else
		add("not sent: cannot send right now (no guild, or addon chat is locked)")
	end

	C_Timer.After(3, function()
		ns.Comm.onRaw = nil
		add("heard our own message back: " .. (heard and ("yes, sender " .. mask(heard) .. " -> canonical "
			.. mask(Names.OfSender(heard)) .. ", matches me: " .. show(Names.OfSender(heard) == Names.Me())) or "no"))
		add("")
		add("== recent debug log ==")
		for i = math.max(1, #ns.debugLog - 25), #ns.debugLog do
			add(ns.debugLog[i])
		end
		ns.db.probe = { at = GetServerTime(), lines = lines }
		if done then done(lines) end
	end)
end
