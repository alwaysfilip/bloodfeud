-- Noticing listed players. Forever closes the combat log to addons, so the
-- only enemies an addon can see are the ones the client shows the player:
-- nameplates, target, focus and mouseover.
local _, ns = ...

local Util, Names = ns.Util, ns.Names

local Detect = { paused = false }
ns.Detect = Detect

Detect.ALLY_KEEP_DAYS = 30 -- forget seen allies not met for this long
Detect.ALLY_MAX = 500

local OPPOSING = { Alliance = "Horde", Horde = "Alliance" }

local LIVE_UNITS = { "target", "focus", "mouseover", "targettarget", "focustarget", "mouseovertarget" }
for i = 1, 4 do LIVE_UNITS[#LIVE_UNITS + 1] = "party" .. i end
for i = 1, 40 do LIVE_UNITS[#LIVE_UNITS + 1] = "raid" .. i end
for i = 1, 40 do LIVE_UNITS[#LIVE_UNITS + 1] = "nameplate" .. i end

local function plain(value, kind)
	if value == nil or Util.IsSecret(value) then return nil end
	if kind and type(value) ~= kind then return nil end
	return value
end

local function safe(fn, ...)
	if not fn then return nil end
	local ok, v = pcall(fn, ...)
	return ok and v or nil
end

--- Safe canonical name of the current target, or nil when absent/secret.
function Detect.TargetName()
	if not plain(safe(_G.UnitExists, "target")) then return nil end
	return Names.OfUnit("target")
end

--- The player's own faction ("Alliance" or "Horde"), or nil when unknown.
function Detect.MyFaction()
	if not _G.UnitFactionGroup then return nil end
	local ok, faction = pcall(_G.UnitFactionGroup, "player")
	return ok and plain(faction, "string") or nil
end

--- True when `faction` is the opposing faction (Alliance <-> Horde).
function Detect.IsOpposingFaction(faction)
	local mine = Detect.MyFaction()
	return mine ~= nil and faction ~= nil and OPPOSING[mine] == faction
end

local function allyBook(faction, create)
	if not faction then return nil end
	local holder = ns.db or Detect
	local root = holder.allies
	if type(root) ~= "table" then
		if not create then return nil end
		root = {}
		holder.allies = root
	end
	local book = root[faction]
	if type(book) ~= "table" then
		if not create then return nil end
		book = { p = {}, g = {} }
		root[faction] = book
	else
		book.p = type(book.p) == "table" and book.p or {}
		book.g = type(book.g) == "table" and book.g or {}
	end
	return book
end

local function pruneTable(t, cutoff, maxCount)
	local keys = {}
	for k, ts in pairs(t) do
		if type(ts) ~= "number" or ts < cutoff then
			t[k] = nil
		else
			keys[#keys + 1] = k
		end
	end
	if #keys > maxCount then
		table.sort(keys, function(a, b) return t[a] > t[b] end)
		for i = maxCount + 1, #keys do t[keys[i]] = nil end
	end
end

function Detect:PruneAllies(now)
	local root = (ns.db or Detect).allies
	if type(root) ~= "table" then return end
	local cutoff = now - Detect.ALLY_KEEP_DAYS * 86400
	for _, book in pairs(root) do
		if type(book) == "table" then
			if type(book.p) == "table" then pruneTable(book.p, cutoff, Detect.ALLY_MAX) end
			if type(book.g) == "table" then pruneTable(book.g, cutoff, Detect.ALLY_MAX) end
		end
	end
end

function Detect:ForgetAlly(key, guild)
	local book = allyBook(Detect.MyFaction(), false)
	if not book then return end
	if key then book.p[key] = nil end
	if guild and guild ~= "" then book.g[Util.Fold(guild)] = nil end
end

--- Note a same-faction player (and their guild) so they cannot later be added
--- by name.
function Detect:RememberAlly(unit)
	if not plain(safe(_G.UnitExists, unit)) then return false end
	if not plain(safe(_G.UnitIsPlayer, unit)) then return false end
	local mine, theirs = Detect.MyFaction(), plain(safe(_G.UnitFactionGroup, unit), "string")
	if not (mine and theirs and mine == theirs) then return false end
	local name = Names.OfUnit(unit)
	if not name then return false end
	local key = Names.Key(name)
	local me = Names.Me()
	if me and key == Names.Key(me) then return false end
	local book = allyBook(mine, true)
	if not book then return false end
	local now = GetServerTime()
	book.p[key] = now
	if _G.GetGuildInfo then
		local guild = plain(safe(_G.GetGuildInfo, unit), "string")
		if guild and guild ~= "" then book.g[Util.Fold(guild)] = now end
	end
	return true
end

function Detect.RememberGroup()
	for i = 1, 4 do Detect:RememberAlly("party" .. i) end
	for i = 1, 40 do Detect:RememberAlly("raid" .. i) end
end

--- True when `unit` is a player who is not of the opposing faction (same
--- faction, or neutral).
function Detect.IsAllyUnit(unit)
	if not plain(safe(_G.UnitExists, unit)) then return false end
	if not plain(safe(_G.UnitIsPlayer, unit)) then return false end
	local mine, theirs = Detect.MyFaction(), plain(safe(_G.UnitFactionGroup, unit), "string")
	if mine and theirs then return OPPOSING[mine] ~= theirs end
	if _G.UnitIsFriend then
		local friend = plain(safe(_G.UnitIsFriend, "player", unit))
		if friend then return true end
	end
	return false
end

-- Check every currently visible player unit for `key`.
-- Returns "enemy" (opposing faction), "ally" (same faction / neutral), or nil.
local function liveRelation(key)
	local mine = Detect.MyFaction()
	for i = 1, #LIVE_UNITS do
		local unit = LIVE_UNITS[i]
		if plain(safe(_G.UnitExists, unit)) and plain(safe(_G.UnitIsPlayer, unit)) then
			local uname = Names.OfUnit(unit)
			if uname and Names.Key(uname) == key then
				local theirs = plain(safe(_G.UnitFactionGroup, unit), "string")
				if mine and theirs then
					if OPPOSING[mine] == theirs then
						Detect:ForgetAlly(key)
						return "enemy"
					end
					return "ally"
				end
				if _G.UnitIsFriend then
					local friend = plain(safe(_G.UnitIsFriend, "player", unit))
					if friend then return "ally" end
				end
			end
		end
	end
	return nil
end

local function onFriendList(key)
	local fl = _G.C_FriendList
	if fl and fl.GetNumFriends and fl.GetFriendInfoByIndex then
		local ok, n = pcall(fl.GetNumFriends)
		if ok and type(n) == "number" then
			for i = 1, n do
				local okInfo, info = pcall(fl.GetFriendInfoByIndex, i)
				if okInfo and type(info) == "table" and type(info.name) == "string" then
					local canon = Names.Canon(info.name)
					if canon and Names.Key(canon) == key then return true end
				end
			end
		end
	end
	local bn = _G.C_BattleNet
	local mine = Detect.MyFaction()
	if mine and bn and bn.GetNumFriends and bn.GetFriendNumGameAccounts and bn.GetFriendGameAccountInfo then
		local ok, n = pcall(bn.GetNumFriends)
		if ok and type(n) == "number" then
			for i = 1, n do
				local okAccts, accts = pcall(bn.GetFriendNumGameAccounts, i)
				if okAccts and type(accts) == "number" then
					for j = 1, accts do
						local okInfo, info = pcall(bn.GetFriendGameAccountInfo, i, j)
						if okInfo and type(info) == "table"
							and plain(info.clientProgram, "string") == "WoW"
							and plain(info.factionName, "string") == mine then
							local canon = Names.Canon(info.characterName)
							if canon and Names.Key(canon) == key then return true end
						end
					end
				end
			end
		end
	end
	return false
end

--- True when `name` (canonical or folded key) is known to be an ally (not from
--- the opposing faction): a visible same-faction/neutral unit, a guildmate,
--- a party/raid member, a friend, or a same-faction player seen earlier.
function Detect.IsAlly(name)
	if type(name) ~= "string" or name == "" then return false end
	local canon = Names.Canon(name)
	if not canon then return false end
	local key = Names.Key(canon)

	local live = liveRelation(key)
	if live then return live == "ally" end

	if ns.Roster and ns.Roster.IsMember(key) then return true end
	if ns.Users then
		local book = ns.Users:Book()
		if book and book[key] then return true end
	end
	if onFriendList(key) then return true end

	local book = allyBook(Detect.MyFaction(), false)
	if book and book.p[key] then return true end
	return false
end

--- True when `guildName` is our own guild or a guild we have seen same-faction
--- players wearing.
function Detect.IsAllyGuild(guildName)
	if type(guildName) ~= "string" or guildName == "" then return false end
	local gkey = Util.Fold(Util.Clean(guildName, ns.Codec.MAX_GUILD))
	if gkey == "" then return false end

	local myGuild = (ns.session and ns.session.guild) or (ns.Roster and ns.Roster.GuildName())
	if myGuild and Util.Fold(myGuild) == gkey then return true end

	local mine = Detect.MyFaction()
	if _G.GetGuildInfo then
		for i = 1, #LIVE_UNITS do
			local unit = LIVE_UNITS[i]
			if plain(safe(_G.UnitExists, unit)) and plain(safe(_G.UnitIsPlayer, unit)) then
				local ug = plain(safe(_G.GetGuildInfo, unit), "string")
				if ug and ug ~= "" and Util.Fold(ug) == gkey then
					local theirs = plain(safe(_G.UnitFactionGroup, unit), "string")
					if mine and theirs then
						if OPPOSING[mine] == theirs then
							Detect:ForgetAlly(nil, ug)
							return false
						end
						return true
					end
				end
			end
		end
	end

	local book = allyBook(mine, false)
	if book and book.g[gkey] then return true end
	return false
end

--- Read what the client will tell us about a unit, if it is a player of the
--- opposing faction (Alliance <-> Horde). Returns nil for allies (even in
--- duels or FFA arenas), NPCs, or when identity is restricted.
function Detect.Inspect(unit)
	if not plain(UnitExists(unit)) then return nil end
	if not plain(UnitIsPlayer(unit)) then return nil end

	local mine, theirs = Detect.MyFaction(), plain(UnitFactionGroup(unit), "string")
	if not (mine and theirs and OPPOSING[mine] == theirs) then return nil end

	local name = Names.OfUnit(unit)
	if not name then return nil end
	local info = { unit = unit, name = name, key = Names.Key(name), faction = theirs }
	info.guid = plain(UnitGUID(unit), "string")
	local _, _, classID = UnitClass(unit)
	info.class = plain(classID, "number")
	local _, _, raceID = UnitRace(unit)
	info.race = plain(raceID, "number")
	local level = plain(UnitLevel(unit), "number")
	if level and level > 0 then
		info.level = level
	elseif level and level < 0 then
		info.high = true -- the client hides the level of someone far above us
	end
	if _G.GetGuildInfo then
		local okG, rawGuild = pcall(_G.GetGuildInfo, unit)
		if okG and not Util.IsSecret(rawGuild) then
			info.guildChecked = true
			if type(rawGuild) == "string" and rawGuild ~= "" then info.guild = rawGuild end
		end
	end
	return info
end

--- Which list entry, if any, is this player? Returns key, how, where how is
--- "name", "guid" (renamed since being listed) or "first" (the entry was
--- typed with a first name only).
function Detect.Match(store, info)
	if store:IsListed(info.key) then return info.key, "name" end
	if info.guid then
		local key = store:KeyForGuid(info.guid)
		if key then return key, "guid" end
	end
	local first = Names.FirstKey(info.name)
	if first and store:IsListed(first) then
		-- An entry typed with only a first name that has since been pinned to
		-- one character does not apply to everyone who shares that first name.
		local facts = store:Get("f:" .. first)
		local known = facts and facts.guid
		if not (known and info.guid and known ~= info.guid) then return first, "first" end
	end
	return nil
end

local function handle(unit)
	local session = ns.session
	if not session or Detect.paused then return end
	local info = Detect.Inspect(unit)
	if not info then
		Detect:RememberAlly(unit)
		return
	end
	Detect:ForgetAlly(info.key, info.guild)
	if ns.Feuds then ns.Feuds:Saw(info) end
	if ns.Radar then ns.Radar:Saw(info, unit) end
	if ns.Targeting then ns.Targeting:Look(unit, info) end
	local store = session.store

	local key = Detect.Match(store, info)
	local subject = key and store:Player(key)
	if subject then
		local known = subject.facts and subject.facts.guid
		-- Listed by this exact name, but the entry was pinned to another
		-- character: alert with a caveat, and leave the entry's facts alone.
		local otherCharacter = known and info.guid and known ~= info.guid

		ns.Alerts:Player(subject, info, otherCharacter)
		if not otherCharacter then
			local now = GetServerTime()
			local guild = info.guild
			if guild == nil and info.guildChecked then guild = false end
			store:SetFacts(key, {
				guid = (not known) and info.guid or nil, -- the first sighting pins the character
				cur = info.name, class = info.class, race = info.race, level = info.level, guild = guild,
			}, session.me, now)
			if ns.Sightings then ns.Sightings:Report(key, info) end
		end
		ns:Fire("LISTED_UNIT", unit, key)
		return
	end

	-- Not on the list themselves: a price on their head, their guild, or both.
	local bounty = ns.Bounties and ns.Bounties:Line(info)
	local alerted = false
	if info.guild and store:IsGuildListed(info.guild) then
		local guild = store:Guild(Util.Fold(info.guild))
		if guild then alerted = ns.Alerts:Guild(guild, info, bounty) end
		ns:Fire("LISTED_GUILD_UNIT", unit, info)
	end
	if bounty and not alerted then ns.Alerts:Bounty(info, bounty) end
end

--- Look at a unit; safe to call for anything, at any time.
function Detect.Scan(unit)
	local ok, err = pcall(handle, unit)
	if not ok then ns:Debug("scan %s failed: %s", tostring(unit), tostring(err)) end
end

--- Look again at every nameplate currently on screen.
function Detect.ScanNameplates()
	for i = 1, 40 do
		Detect.Scan("nameplate" .. i)
	end
end

local function updatePause()
	local inInstance, kind = false, nil
	if _G.IsInInstance then
		local ok, a, b = pcall(_G.IsInInstance)
		if ok then inInstance, kind = a, b end
	end
	-- Dungeons, raids and PvP matches: identity is restricted there, and a
	-- battleground full of enemies is not what the list is for.
	Detect.paused = (inInstance and kind ~= "none") and true or false
end

function Detect:Init()
	self:PruneAllies(GetServerTime())
	ns:On("NAME_PLATE_UNIT_ADDED", function(unit) Detect.Scan(unit) end)
	ns:On("PLAYER_TARGET_CHANGED", function() Detect.Scan("target") end)
	ns:On("UPDATE_MOUSEOVER_UNIT", function() Detect.Scan("mouseover") end)
	ns:On("PLAYER_FOCUS_CHANGED", function() Detect.Scan("focus") end)
	ns:On("GROUP_ROSTER_UPDATE", function() Detect.RememberGroup() end)
	ns:On("PLAYER_ENTERING_WORLD", updatePause)
	ns:On("ZONE_CHANGED_NEW_AREA", updatePause)
	updatePause()
	Detect.RememberGroup()
end
