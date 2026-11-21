-- What the player can do to the list. Every entry point (window, slash
-- command, right-click menu) goes through these, so the rules live in one
-- place: you need a guild, guild reports need an officer, and a report can be
-- removed by its author or an officer.
local _, ns = ...

local Util, Codec, Names, Roster, Permissions = ns.Util, ns.Codec, ns.Names, ns.Roster, ns.Permissions
local L = ns.L

local function session()
	local s = ns.session
	if not s then ns:Print(L.MSG_NO_GUILD) end
	return s
end

local roster = { IsOfficer = Roster.IsOfficer }

--- May the player add a report of this kind ("r" or "g")?
function ns:CanAdd(kind)
	local s = self.session
	if not s then return false end
	if kind == "g" then return Roster.AmOfficer() end
	return Permissions.CanAdd(kind, s.meKey, roster)
end

--- The player's own live report on a subject, or nil.
function ns:MyReport(kind, key)
	local s = self.session
	if not s then return nil end
	local rec = s.store:Get(Codec.Id(kind, key, s.meKey))
	if rec and not rec.del then return rec end
	return nil
end

--- Add (or update the reason of) the player's report on an enemy player.
--- `name` is canonical; `info` is what Detect.Inspect saw, when available.
function ns:AddPlayer(name, reason, info)
	local s = session()
	if not s then return nil end
	if not name or name == "" then
		self:Print(L.MSG_NO_TARGET)
		return nil
	end
	local key = Names.Key(name)
	if key == s.meKey then
		self:Print(L.MSG_SELF)
		return nil
	end
	local now = GetServerTime()
	local rec = s.store:Report("r", name, reason or "", s.me, nil, now)
	if info then
		s.store:SetFacts(key, { guid = info.guid, cur = info.name, class = info.class, race = info.race,
			level = info.level, guild = info.guild }, s.me, now)
	end
	self:Print(L.MSG_YOU_ADDED:format(Names.Display(name)))
	return rec
end

--- Add the current target, which must be an enemy player.
function ns:AddTarget(reason)
	if not session() then return nil end
	local ok, info = pcall(self.Detect.Inspect, "target")
	if not ok or not info then
		local shown = _G.UnitExists("target") and Names.OfUnit("target")
		self:Print(shown and L.MSG_NOT_ENEMY:format(Names.Display(shown)) or L.MSG_NO_TARGET)
		return nil
	end
	return self:AddPlayer(info.name, reason, info)
end

--- Add (or update) a guild report. Officers only.
function ns:AddGuild(guildName, reason)
	local s = session()
	if not s then return nil end
	if not Roster.AmOfficer() then
		self:Print(L.MSG_NOT_OFFICER)
		return nil
	end
	guildName = Util.Clean(guildName or "", Codec.MAX_GUILD)
	if guildName == "" then return nil end
	local rec = s.store:Report("g", guildName, reason or "", s.me, nil, GetServerTime())
	self:Print(L.MSG_YOU_ADDED:format("<" .. guildName .. ">"))
	return rec
end

--- Remove the player's own report. Returns true when something was removed.
function ns:RemoveMine(kind, key)
	local s = session()
	if not s then return false end
	local mine = self:MyReport(kind, key)
	if not mine then
		self:Print(L.MSG_NOT_LISTED:format(key))
		return false
	end
	s.store:Remove(mine.id, s.me, GetServerTime())
	self:Print(L.MSG_YOU_REMOVED:format(kind == "g" and ("<" .. mine.name .. ">") or Names.Display(mine.name)))
	return true
end

--- Remove every report on a subject. Officers only; for guild reports the
--- same rule applies because only officers may write them at all.
function ns:RemoveAll(kind, key)
	local s = session()
	if not s then return false end
	if not Roster.AmOfficer() then
		self:Print(L.MSG_NOT_OFFICER)
		return false
	end
	local subject = kind == "g" and s.store:Guild(key) or s.store:Player(key)
	if not subject then return false end
	local now = GetServerTime()
	for i = 1, #subject.reports do
		s.store:Remove(subject.reports[i].id, s.me, now)
	end
	self:Print(L.MSG_REMOVED:format(Names.Display(s.me), kind == "g" and ("<" .. subject.name .. ">")
		or Names.Display(subject.name)))
	return true
end

--- Ask the guild for changes now instead of waiting for the next exchange.
function ns:SyncNow()
	local s = session()
	if not s then return end
	s.sync:ScheduleHello(GetTime(), true)
end
