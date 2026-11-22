-- Who in the guild runs Business Meeting, and on which version.
--
-- Every client says so now and then on the guild's addon channel (a
-- "presence" frame: version and protocol), and answers when someone asks.
-- Clients too old to say it are still noticed by their sync frames, which
-- carry their protocol number. What has been heard is remembered per guild,
-- so the list also knows the members who are offline right now.
local _, ns = ...

local Util, Names, Codec, Roster = ns.Util, ns.Names, ns.Codec, ns.Roster

local Users = {}
ns.Users = Users

Users.LOGIN_DELAY = { 8, 20 } -- seconds after login before the first "here I am"
Users.PING_PERIOD = { 780, 1020 } -- then roughly every quarter of an hour
Users.RETRY = 60 -- when it could not be sent (in an instance)
Users.REPLY_DELAY = { 1, 8 } -- answering a "who is there?", spread out
Users.REPLY_GAP = 30 -- but never more often than this
Users.ASK_GAP = 60
Users.RECENT = 1200 -- heard this recently counts as online when the roster cannot say
Users.KEEP_DAYS = 60 -- forget members not heard from for this long

-- Versions from before presence existed, by the protocol their sync speaks.
local OLD_VERSIONS = { [1] = "v0.1.0", [2] = "v0.2.0", [3] = "v0.3.0" }

local function between(range)
	return range[1] + (range[2] - range[1]) * math.random()
end

--- This copy's version, as the .toc states it ("dev" for an unpackaged one).
function Users.Version()
	if Users.version then return Users.version end
	local version
	local meta = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata
	if meta then
		local ok, value = pcall(meta, ns.ADDON, "Version")
		if ok and type(value) == "string" then version = value end
	end
	version = Util.Clean(version or "", Codec.MAX_VERSION)
	if version == "" or version:find("@", 1, true) then version = "dev" end
	Users.version = version
	return version
end

--- What has been heard, for the guild we are in: key -> { n, v, p, t }.
function Users:Book()
	local s = ns.session
	if not s then return nil end
	local data = s.store.data
	if type(data.users) ~= "table" then data.users = {} end
	return data.users
end

--- A guildmate was heard using the addon. `version` is nil when only their
--- protocol number is known (a sync frame).
function Users:Heard(name, version, proto)
	local s, book = ns.session, self:Book()
	if not book or type(name) ~= "string" then return end
	local key = Names.Key(name)
	if key == s.meKey then return end
	local e = book[key]
	local changed = not e
	if not e then
		e = {}
		book[key] = e
	end
	e.n = name
	e.t = GetServerTime()
	if version then
		changed = changed or e.v ~= version
		e.v = version
	elseif proto and e.p ~= proto then
		e.v = nil -- they changed version, and we do not know to which
	end
	if proto then
		changed = changed or e.p ~= proto
		e.p = proto
	end
	if changed then ns:Fire("USERS_CHANGED") end
end

--- Tell the guild this copy is here; with `ask`, also ask who else is.
function Users:Ping(ask)
	if not ns.session then return false end
	local now = GetTime()
	local sent = ns.Comm.Send("sight", Codec.EncodePresence(Users.Version(), Codec.PROTO, ask))
	if sent then
		self.lastPing = now
		self.nextPing = now + between(Users.PING_PERIOD)
	else
		self.nextPing = now + Users.RETRY
	end
	return sent
end

--- Ask everyone to say they are here, for an up-to-date list. Returns false
--- when asked too recently.
function Users:Ask()
	local now = GetTime()
	if self.lastAsk and now - self.lastAsk < Users.ASK_GAP then return false end
	self.lastAsk = now
	Roster:Request()
	return self:Ping(true)
end

function Users:OnFrame(sender, text)
	local s = ns.session
	local p = Codec.DecodePresence(text)
	if not s or not p then return end
	self:Heard(sender, p.version, p.proto)
	if not p.ask or Names.Key(sender) == s.meKey or self.replying then return end
	if self.lastPing and GetTime() - self.lastPing < Users.REPLY_GAP then return end
	self.replying = true
	C_Timer.After(between(Users.REPLY_DELAY), function()
		Users.replying = false
		ns.Safe(Users.Ping, Users)
	end)
end

--- Can this protocol sync with ours? "ok", "old" (they must update) or
--- "new" (we must).
function Users.Standing(proto)
	if not proto or proto == Codec.PROTO then return "ok" end
	return proto < Codec.PROTO and "old" or "new"
end

--- Everyone known to run the addon, online first:
--- { key, name, version, proto, t, online, standing, me }.
function Users:List()
	local s, book = ns.session, self:Book()
	local out = {}
	if not book then return out end
	local now = GetServerTime()
	local cutoff = now - Users.KEEP_DAYS * 86400
	for key, e in pairs(book) do
		-- Only a complete roster can say that someone has left the guild.
		if type(e) ~= "table" or (e.t or 0) < cutoff or (Roster.complete and Roster.members[key] == nil) then
			book[key] = nil
		else
			local online = Roster.online[key]
			if online == nil then online = now - e.t <= Users.RECENT end
			out[#out + 1] = {
				key = key, name = e.n or key, version = e.v or OLD_VERSIONS[e.p], proto = e.p, t = e.t,
				online = online and true or false, standing = Users.Standing(e.p),
			}
		end
	end
	out[#out + 1] = { key = s.meKey, name = s.me, version = Users.Version(), proto = Codec.PROTO, t = now, online = true,
		standing = "ok", me = true }
	table.sort(out, function(a, b)
		if a.online ~= b.online then return a.online end
		return a.key < b.key
	end)
	return out
end

--- { have, total (guild members, 0 when unknown), online, old, new }.
function Users:Summary()
	local list = self:List()
	local sum = { have = #list, total = Roster.total or 0, online = 0, old = 0, new = 0 }
	for i = 1, #list do
		local u = list[i]
		if u.online then sum.online = sum.online + 1 end
		if u.standing == "old" then sum.old = sum.old + 1 elseif u.standing == "new" then sum.new = sum.new + 1 end
	end
	if sum.total < sum.have then sum.total = 0 end -- a roster that knows fewer than we do is not the whole guild
	return sum, list
end

function Users:Init()
	local function schedule()
		Users.nextPing = ns.session and (GetTime() + between(Users.LOGIN_DELAY)) or nil
	end
	ns:Listen("SESSION_CHANGED", schedule)
	schedule()
	C_Timer.NewTicker(5, function()
		if Users.nextPing and GetTime() >= Users.nextPing then ns.Safe(Users.Ping, Users) end
	end)
	ns:Listen("ROSTER_CHANGED", function() ns:Fire("USERS_CHANGED") end)
end
