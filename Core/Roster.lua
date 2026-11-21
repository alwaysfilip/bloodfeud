-- Who is in the guild, and who counts as an officer. Used to gate the
-- interface and to check edits that arrive straight from their writer.
--
-- "Officer" has to mean the same thing on every member's client, so it is
-- derived only from guild data: the guild master, plus every rank that has
-- the "officer" permission ticked in the guild control panel.
local _, ns = ...

local Util, Names = ns.Util, ns.Names

local Roster = { members = {}, officers = {}, rankOfficer = {}, count = 0, ready = false }
ns.Roster = Roster

local OFFICER_FLAG = 22 -- id of the "officer" checkbox in Blizzard_GuildControlUI

local function rankIsOfficer(rankIndex)
	if rankIndex == 0 then return true end
	local cached = Roster.rankOfficer[rankIndex]
	if cached ~= nil then return cached end
	local result = rankIndex <= 1 -- fallback when the permission cannot be read
	local api = _G.C_GuildInfo and _G.C_GuildInfo.GuildControlGetRankFlags
	if api then
		local ok, flags = pcall(api, rankIndex + 1)
		if ok and type(flags) == "table" then
			local flag = flags[OFFICER_FLAG]
			if flag ~= nil and not Util.IsSecret(flag) then result = flag and true or false end
		end
	end
	Roster.rankOfficer[rankIndex] = result
	return result
end
Roster.RankIsOfficer = rankIsOfficer

local function fromRosterApi()
	local total = _G.GetNumGuildMembers and _G.GetNumGuildMembers() or 0
	local getInfo = _G.GetGuildRosterInfo
	local loaded = 0
	if not getInfo or type(total) ~= "number" then return 0 end
	for i = 1, total do
		local ok, name, _, rankIndex = pcall(getInfo, i)
		if ok and type(rankIndex) == "number" then
			local canon = Names.Canon(name)
			if canon then
				Roster.members[Names.Key(canon)] = rankIndex
				loaded = loaded + 1
			end
		end
	end
	return loaded
end

-- Fallback: the guild as a "club", which carries each member's role.
local function fromClubApi()
	local club = _G.C_Club
	if not (club and club.GetGuildClubId and club.GetClubMembers and club.GetMemberInfo) then return 0 end
	local ok, clubId = pcall(club.GetGuildClubId)
	if not ok or not clubId then return 0 end
	local okMembers, ids = pcall(club.GetClubMembers, clubId)
	if not okMembers or type(ids) ~= "table" then return 0 end
	local moderator = _G.Enum and _G.Enum.ClubRoleIdentifier and _G.Enum.ClubRoleIdentifier.Moderator or 3
	local loaded = 0
	for i = 1, #ids do
		local okInfo, info = pcall(club.GetMemberInfo, clubId, ids[i])
		if okInfo and type(info) == "table" then
			local canon = Names.Canon(info.name)
			if canon then
				local key = Names.Key(canon)
				local order = info.guildRankOrder
				Roster.members[key] = type(order) == "number" and order - 1 or 9
				if type(info.role) == "number" then Roster.officers[key] = info.role <= moderator end
				loaded = loaded + 1
			end
		end
	end
	return loaded
end

--- Rebuild the member table from whatever the client offers.
function Roster:Refresh()
	self.members, self.officers, self.rankOfficer = {}, {}, {}
	local loaded = 0
	if _G.IsInGuild and _G.IsInGuild() then
		loaded = fromRosterApi()
		if loaded == 0 then loaded = fromClubApi() end
	end
	self.count = loaded
	self.ready = loaded > 0
	ns:Fire("ROSTER_CHANGED")
end

--- Ask the server for a fresh roster; the result arrives as an event.
function Roster:Request()
	local guildInfo = _G.C_GuildInfo
	if guildInfo and guildInfo.GuildRoster then
		pcall(guildInfo.GuildRoster)
	elseif _G.GuildRoster then
		pcall(_G.GuildRoster)
	end
end

--- Name of the player's guild, or nil while it is unknown or absent.
function Roster.GuildName()
	if not (_G.IsInGuild and _G.IsInGuild()) then return nil end
	local name = _G.GetGuildInfo and _G.GetGuildInfo("player")
	if type(name) ~= "string" or name == "" or Util.IsSecret(name) then return nil end
	return name
end

function Roster.Ready()
	return Roster.ready
end

--- Is the member with this folded name an officer?
function Roster.IsOfficer(key)
	local known = Roster.officers[key]
	if known ~= nil then return known end
	local rankIndex = Roster.members[key]
	if rankIndex == nil then return false end
	return rankIsOfficer(rankIndex)
end

--- Is the player an officer? Uses the same rule others apply to them.
function Roster.AmOfficer()
	local me = Names.Me()
	if me and Roster.members[Names.Key(me)] ~= nil then
		return Roster.IsOfficer(Names.Key(me))
	end
	if _G.IsGuildLeader and _G.IsGuildLeader() then return true end
	local _, _, rankIndex = _G.GetGuildInfo("player")
	if type(rankIndex) == "number" then return rankIsOfficer(rankIndex) end
	return false
end

local pending = false

local function refreshSoon()
	if pending then return end
	pending = true
	C_Timer.After(1, function()
		pending = false
		Roster:Refresh()
	end)
end

function Roster:Init()
	ns:On("GUILD_ROSTER_UPDATE", refreshSoon)
	ns:On("GUILD_RANKS_UPDATE", refreshSoon)
	ns:On("PLAYER_GUILD_UPDATE", function()
		Roster:Request()
		refreshSoon()
	end)
	self:Request()
	refreshSoon()
end
