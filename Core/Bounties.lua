-- Bounties: any guildmate can put a price on an enemy player or a whole enemy
-- guild. The reward is points (and, on trust, whatever the poster promises in
-- the reward text: an addon cannot move gold). A killing blow on the target
-- claims it; the bounty stays up until its poster or an officer takes it down,
-- so it can be claimed again.
local _, ns = ...

local Util, Codec, Names, Roster = ns.Util, ns.Codec, ns.Names, ns.Roster
local L = ns.L

local Bounties = {}
ns.Bounties = Bounties

local function session()
	local s = ns.session
	if not s then ns:Print(L.MSG_NO_GUILD) end
	return s
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------

--- Live bounties that apply to an enemy player we can see: on them by name
--- (or by the list entry they were matched to), or on their guild.
function Bounties:For(info, listKey)
	local s = ns.session
	if not s or not info then return {} end
	local out, seen = {}, {}
	local function add(scope, key)
		if not key or not s.store:HasBounty(scope, key) then return end
		local list = s.store:Bounties(scope, key)
		for i = 1, #list do
			if not seen[list[i].key] then
				seen[list[i].key] = true
				out[#out + 1] = list[i]
			end
		end
	end
	add("p", info.key)
	if listKey and listKey ~= info.key then add("p", listKey) end
	-- A bounty posted with only a first name applies to everyone called that,
	-- the way a first-name entry on the list does before it is pinned.
	local first = info.name and Names.FirstKey(info.name)
	if first and first ~= listKey then add("p", first) end
	if info.guild then add("g", Util.Fold(info.guild)) end
	return out
end

--- Total points on offer for this player, and how many bounties.
function Bounties:Worth(info, listKey)
	local list = self:For(info, listKey)
	local points = 0
	for i = 1, #list do points = points + list[i].rec.points end
	return points, #list, list
end

--- One line for alerts and tooltips: "Bounty: 25 points (Olaf: 50 gold)".
function Bounties:Line(info, listKey)
	local points, n, list = self:Worth(info, listKey)
	if n == 0 then return nil end
	local first = list[1].rec
	local by = Names.Display(first.author) .. (first.reward ~= "" and (": " .. first.reward) or "")
	if n > 1 then by = by .. L.MORE:format(n - 1) end
	return L.BOUNTY_LINE:format(points, by)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

--- The player's own live bounty on a target, or nil. `name` as typed.
function Bounties:Mine(scope, name)
	local s = ns.session
	if not s or type(name) ~= "string" then return nil end
	local key
	if scope == "p" then
		local canon = Names.Canon(name, true)
		key = canon and Names.Key(canon)
	else
		key = Util.Fold(Util.Clean(name, Codec.MAX_GUILD))
	end
	local rec = key and key ~= "" and s.store:Get(Codec.BountyId(scope, key, s.meKey))
	if rec and not rec.del then return rec end
	return nil
end

--- Post (or change) the player's bounty. scope "p" (player) or "g" (guild).
--- Leave points or reward nil to keep what an existing bounty has.
function ns:PostBounty(scope, name, points, reward)
	local s = session()
	if not s then return nil end
	if scope == "p" then
		name = Names.Canon(name or "", true)
		if not name then
			self:Print(L.MSG_NO_TARGET)
			return nil
		end
		if Names.Key(name) == s.meKey then
			self:Print(L.MSG_SELF)
			return nil
		end
	else
		name = Util.Clean(name or "", Codec.MAX_GUILD)
		if name == "" then return nil end
	end
	local existing = Bounties:Mine(scope, name)
	points = tonumber(points) or (existing and existing.points) or 10
	reward = reward or (existing and existing.reward) or ""
	local rec = s.store:PostBounty(scope, name, points, reward, s.me, nil, GetServerTime())
	self:Print(L.MSG_BOUNTY_POSTED:format(scope == "g" and ("<" .. name .. ">") or Names.Display(name), rec.points))
	if scope == "p" and not name:find("-", 1, true) then
		self:Print(L.MSG_BOUNTY_FIRST_NAME:format(Names.Display(name)))
	end
	if not existing and ns.Progress then ns.Progress:Bump("posted") end
	return rec
end

--- Take a bounty down: its poster, or an officer.
function ns:RemoveBounty(id)
	local s = session()
	if not s then return false end
	local rec = s.store:Get(id)
	if not rec or rec.del then return false end
	if rec.akey ~= s.meKey and not Roster.AmOfficer() then
		self:Print(L.MSG_NOT_YOURS:format(Names.Display(rec.author)))
		return false
	end
	s.store:Remove(id, s.me, GetServerTime())
	self:Print(L.MSG_BOUNTY_REMOVED:format(rec.scope == "g" and ("<" .. rec.name .. ">") or Names.Display(rec.name)))
	return true
end

---------------------------------------------------------------------------
-- Claiming
---------------------------------------------------------------------------

--- Called by Progress for every killing blow on an enemy player.
function Bounties:OnKill(info, listKey, st)
	local s = ns.session
	if not s then return end
	local list = self:For(info, listKey)
	local now = GetServerTime()
	for i = 1, #list do
		local rec = list[i].rec
		if rec.akey ~= s.meKey then -- your own bounty pays nothing
			if s.store:Claim(rec.id, s.me, now) then
				st.points = st.points + rec.points
				st.claims = st.claims + 1
				if ns.settings.chat then
					ns:Print(L.MSG_BOUNTY_CLAIMED_YOU:format(
						rec.scope == "g" and ("<" .. rec.name .. ">") or Names.Display(rec.name), rec.points,
						Names.Display(rec.author), rec.reward ~= "" and (" " .. L.BOUNTY_PROMISED:format(rec.reward)) or ""))
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- What guildmates did
---------------------------------------------------------------------------

local function subjectOf(rec)
	if rec.scope == "g" then return "<" .. rec.name .. ">" end
	return Names.Display(rec.name)
end

--- Chat lines for fresh bounty changes sent by their writer.
function Bounties.Announce(rec, sender)
	if not ns.settings.chat then return end
	local s = ns.session
	if not s or GetServerTime() - rec.ts > 120 then return end
	if Names.Key(sender) == s.meKey then return end
	if rec.k == "b" then
		if rec.del then
			ns:Print(L.MSG_BOUNTY_DOWN:format(Names.Display(sender), subjectOf(rec)))
		else
			ns:Print(L.MSG_BOUNTY_UP:format(Names.Display(sender), subjectOf(rec), rec.points,
				rec.reward ~= "" and (", " .. rec.reward) or ""))
		end
	elseif rec.k == "k" then
		local bounty = s.store:Get(rec.bid)
		if not bounty or bounty.del then return end
		ns:Print(L.MSG_BOUNTY_CLAIMED:format(Names.Display(rec.author), subjectOf(bounty), bounty.points))
	end
end
