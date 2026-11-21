-- The game side of syncing: the guild addon channel, the lockdown state, and
-- the session that ties a Store and a Sync engine to the player's guild.
local _, ns = ...

local Util, Names, Roster = ns.Util, ns.Names, ns.Roster
local L = ns.L

local Comm = {}
ns.Comm = Comm

---------------------------------------------------------------------------
-- Sending and the lockdown
---------------------------------------------------------------------------

--- True when addon messages to the guild can be sent right now. Inside
--- dungeons, raids and PvP matches the client locks addon chat.
function Comm.CanSend()
	if not (_G.IsInGuild and _G.IsInGuild()) then return false end
	local locked = _G.C_ChatInfo and _G.C_ChatInfo.InChatMessagingLockdown
	if locked then
		local ok, value = pcall(locked)
		if ok and not Util.IsSecret(value) and value then return false end
	end
	return true
end

local function onSent(channel, didSend, result)
	if didSend then return end
	ns:Debug("send failed on %s: %s", tostring(channel), tostring(result))
	local session = ns.session
	if session and channel == "state" then session.sync:OnThrottled() end
end

--- Hand one frame to the guild channel. channel is "state" or "sight".
--- Returns false when it could not even be queued.
function Comm.Send(channel, text)
	if not Comm.CanSend() then return false end
	local prefix = channel == "sight" and ns.PREFIX_SIGHT or ns.PREFIX
	local ctl = _G.ChatThrottleLib
	if ctl and ctl.SendAddonMessage then
		-- ChatThrottleLib shares the client's bandwidth fairly between addons
		-- and retries for us when the server reports a throttle.
		local ok = pcall(ctl.SendAddonMessage, ctl, "NORMAL", prefix, text, "GUILD", nil, "BloodFeud", onSent, channel)
		return ok
	end
	local ok, result = pcall(_G.C_ChatInfo.SendAddonMessage, prefix, text, "GUILD")
	local success = _G.Enum and _G.Enum.SendAddonMessageResult and _G.Enum.SendAddonMessageResult.Success or 0
	onSent(channel, ok and (result == true or result == success), result)
	return ok
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function onAddonMessage(prefix, text, channel, sender)
	-- In restricted contexts these can be secret values, which must not even
	-- be compared.
	if Util.IsSecret(prefix) or Util.IsSecret(text) or Util.IsSecret(channel) or Util.IsSecret(sender) then return end
	if prefix ~= ns.PREFIX and prefix ~= ns.PREFIX_SIGHT then return end
	if channel ~= "GUILD" or type(text) ~= "string" then return end
	if Comm.onRaw then Comm.onRaw(prefix, text, sender) end
	local session = ns.session
	if not session then return end
	local who = Names.OfSender(sender)
	if not who then return end
	if prefix == ns.PREFIX then
		session.sync:OnFrame(who, text)
	elseif ns.Sightings then
		ns.Sightings:OnFrame(who, text)
	end
end

---------------------------------------------------------------------------
-- Session: the list of the guild the player is in right now
---------------------------------------------------------------------------

local function announce(rec, sender, _, direct)
	-- Only speak about changes as they happen, never about the backlog that
	-- arrives while catching up.
	if not direct or not ns.settings.chat then return end
	if rec.k == "b" or rec.k == "k" then
		if ns.Bounties then ns.Bounties.Announce(rec, sender) end
		return
	end
	if rec.k ~= "r" and rec.k ~= "g" then return end
	local now = GetServerTime()
	if now - rec.ts > 120 then return end
	local subject = rec.k == "g" and ("<" .. rec.name .. ">") or Names.Display(rec.name)
	if rec.del then
		ns:Print(L.MSG_REMOVED:format(Names.Display(sender), subject))
	else
		ns:Print(L.MSG_ADDED:format(Names.Display(sender), subject, rec.reason or ""))
	end
end

local function denied(rec, sender)
	if not ns.settings.chat then return end
	local subject
	if rec.k == "t" then
		subject = L.RANK_LADDER
	elseif rec.k == "m" or rec.k == "k" or rec.k == "c" then
		subject = Names.Display(rec.author)
	else
		subject = (rec.k == "g" or rec.scope == "g") and ("<" .. rec.name .. ">") or Names.Display(rec.name)
	end
	ns:Print(L.MSG_DENIED:format(Names.Display(sender), subject))
end

function ns:UnbindGuild()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	if self.session then
		self.session = nil
		self:Fire("SESSION_CHANGED")
	end
end

--- Open (or create) the list for this guild and start syncing it.
function ns:BindGuild(guildName)
	if self.session and self.session.guild == guildName then return end
	self:UnbindGuild()
	local me = Names.Me()
	if not me then return end

	local data = self.db.guilds[guildName]
	if type(data) ~= "table" then
		data = {}
		self.db.guilds[guildName] = data
	end
	local store = ns.Store.New(data, GetServerTime())
	local sync = ns.Sync.New(store, {
		now = GetTime,
		time = GetServerTime,
		random = function(a, b) return a + (b - a) * math.random() end,
		send = Comm.Send,
		canSend = Comm.CanSend,
		me = me,
		roster = { Ready = Roster.Ready, IsOfficer = Roster.IsOfficer },
	})
	sync.onApplied = announce
	sync.onDenied = denied

	self.session = { guild = guildName, store = store, sync = sync, me = me, meKey = Names.Key(me) }
	store:OnChange(function(id, rec, old)
		ns:Fire("LIST_CHANGED", id, rec, old)
	end)
	sync:Start()
	self.ticker = C_Timer.NewTicker(0.5, function()
		ns.Safe(sync.Tick, sync)
		if sync.newerSeen and not ns.toldNewer then
			ns.toldNewer = true
			ns:Print(L.MSG_NEWER)
		end
	end)
	self:Debug("session bound to the guild list") -- no names: the debug log ends up in the probe report
	self:Fire("SESSION_CHANGED")
end

--- Follow the player in and out of guilds.
function ns:CheckGuild()
	local guild = Roster.GuildName()
	if guild then
		self:BindGuild(guild)
	elseif not (_G.IsInGuild and _G.IsInGuild()) then
		self:UnbindGuild()
	end
	-- In a guild whose name has not loaded yet: keep what we have and wait
	-- for the next roster event.
end

function Comm:Init()
	local register = _G.C_ChatInfo and _G.C_ChatInfo.RegisterAddonMessagePrefix
	if register then
		Comm.registered = { pcall(register, ns.PREFIX) }
		Comm.registeredSight = { pcall(register, ns.PREFIX_SIGHT) }
	end
	ns:On("CHAT_MSG_ADDON", onAddonMessage)
	ns:On("PLAYER_GUILD_UPDATE", function() ns:CheckGuild() end)
	ns:On("GUILD_ROSTER_UPDATE", function() ns:CheckGuild() end)
	ns:On("ADDON_RESTRICTION_STATE_CHANGED", function() ns:Fire("LOCK_CHANGED") end)
	ns:On("PLAYER_ENTERING_WORLD", function() ns:Fire("LOCK_CHANGED") end)
	ns:CheckGuild()
end
