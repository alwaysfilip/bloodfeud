-- Bounties: any guildmate can put a price on an enemy player or a whole enemy
-- guild. A killing blow on the target claims it.
--
-- A bounty of points only stays up until its poster or an officer takes it
-- down, and can be claimed again and again. A bounty with gold goes to the
-- first kill: it is then won, and its poster owes the winner the gold (see
-- Debts for how that promise is kept).
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

local function subjectOf(rec)
	if rec.scope == "g" then return "<" .. rec.name .. ">" end
	return Names.Display(rec.name)
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------

--- Bounties still to be had that apply to an enemy player we can see: on
--- them by name (or by the list entry they were matched to), or on their
--- guild. A gold bounty somebody already won is no longer one of them.
function Bounties:For(info, listKey)
	local s = ns.session
	if not s or not info then return {} end
	local out, seen = {}, {}
	local function add(scope, key)
		if not key or not s.store:HasBounty(scope, key) then return end
		local list = s.store:Bounties(scope, key)
		for i = 1, #list do
			if not seen[list[i].key] and not list[i].winner then
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

--- Total points on offer for this player, how many bounties, the bounties,
--- and the gold on offer.
function Bounties:Worth(info, listKey)
	local list = self:For(info, listKey)
	local points, gold = 0, 0
	for i = 1, #list do
		points = points + list[i].rec.points
		gold = gold + (list[i].rec.gold or 0)
	end
	return points, #list, list, gold
end

--- One line for alerts and tooltips: "Bounty: 25 points and 50 gold (Olaf)".
function Bounties:Line(info, listKey)
	local points, n, list, gold = self:Worth(info, listKey)
	if n == 0 then return nil end
	local first = list[1].rec
	local by = Names.Display(first.author) .. (first.reward ~= "" and (": " .. first.reward) or "")
	if n > 1 then by = by .. L.MORE:format(n - 1) end
	if gold > 0 then return L.BOUNTY_LINE_GOLD:format(points, gold, by) end
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
--- Leave points, reward or gold nil to keep what an existing bounty has.
function ns:PostBounty(scope, name, points, reward, gold)
	local s = session()
	if not s then return nil end
	if scope == "p" then
		name = Names.Canon(name or "", true)
		if not name then
			self:Print(L.MSG_NO_TARGET)
			return nil
		end
		local key = Names.Key(name)
		if key == s.meKey then
			self:Print(L.MSG_SELF)
			return nil
		end
		if self.Detect.IsAlly(key) then
			self:Print(L.MSG_ALLY:format(Names.Display(name)))
			return nil
		end
	else
		name = Util.Clean(name or "", Codec.MAX_GUILD)
		if name == "" then return nil end
		if self.Detect.IsAllyGuild(name) then
			self:Print(L.MSG_ALLY_GUILD:format(name))
			return nil
		end
	end
	local now = GetServerTime()
	-- Whoever has not paid for the last one does not get to post the next.
	local disgrace = ns.Debts and ns.Debts:Dishonor(s.meKey)
	if disgrace then
		self:Print(L.MSG_BOUNTY_DISHONORED:format(disgrace.gold, Names.Display(disgrace.winner)))
		return nil
	end
	local existing = Bounties:Mine(scope, name)
	local debt = existing and s.store:Debt(existing, now)
	if debt and debt.open then
		self:Print(L.MSG_BOUNTY_WON_PAY:format(Names.Display(debt.winner), debt.gold))
		return nil
	end
	points = tonumber(points) or (existing and existing.points) or 10
	reward = reward or (existing and existing.reward) or ""
	gold = tonumber(gold) or (existing and existing.gold) or 0
	if debt then
		-- Won and paid: posting it again starts a fresh one.
		s.store:Remove(existing.id, s.me, now)
	end
	local rec = s.store:PostBounty(scope, name, points, reward, s.me, nil, now, gold)
	self:Print(L.MSG_BOUNTY_POSTED:format(subjectOf(rec), rec.points))
	if rec.gold > 0 then self:Print(L.MSG_BOUNTY_GOLD:format(rec.gold)) end
	if scope == "p" and not name:find("-", 1, true) then
		self:Print(L.MSG_BOUNTY_FIRST_NAME:format(Names.Display(name)))
	end
	if not existing and ns.Progress then ns.Progress:Bump("posted") end
	return rec
end

--- Take a bounty down: its poster, or an officer. A poster cannot take down
--- a bounty that was won until the gold is paid; an officer can, which also
--- cancels the debt.
function ns:RemoveBounty(id)
	local s = session()
	if not s then return false end
	local rec = s.store:Get(id)
	if not rec or rec.del or rec.k ~= "b" then return false end
	local officer = Roster.AmOfficer()
	if rec.akey ~= s.meKey and not officer then
		self:Print(L.MSG_NOT_YOURS:format(Names.Display(rec.author)))
		return false
	end
	local debt = s.store:Debt(rec, GetServerTime())
	if debt and debt.open and not officer then
		self:Print(L.MSG_BOUNTY_WON_PAY:format(Names.Display(debt.winner), debt.gold))
		return false
	end
	s.store:Remove(id, s.me, GetServerTime())
	self:Print(L.MSG_BOUNTY_REMOVED:format(subjectOf(rec)))
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
					ns:Print(L.MSG_BOUNTY_CLAIMED_YOU:format(subjectOf(rec), rec.points, Names.Display(rec.author),
						rec.reward ~= "" and (" " .. L.BOUNTY_PROMISED:format(rec.reward)) or ""))
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- What guildmates did
---------------------------------------------------------------------------

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
			local extra = (rec.gold or 0) > 0 and L.BOUNTY_UP_GOLD:format(rec.gold) or ""
			ns:Print(L.MSG_BOUNTY_UP:format(Names.Display(sender), subjectOf(rec), rec.points,
				extra .. (rec.reward ~= "" and (", " .. rec.reward) or "")))
		end
	elseif rec.k == "k" then
		local bounty = s.store:Get(rec.bid)
		if not bounty or bounty.del then return end
		if (bounty.gold or 0) > 0 then
			-- The two it concerns are told by Debts; this is for everyone else.
			if s.store:Winner(bounty) == rec and bounty.akey ~= s.meKey then
				ns:Print(L.MSG_BOUNTY_WON:format(Names.Display(rec.author), subjectOf(bounty), Names.Display(bounty.author),
					bounty.gold))
			end
		else
			ns:Print(L.MSG_BOUNTY_CLAIMED:format(Names.Display(rec.author), subjectOf(bounty), bounty.points))
		end
	end
end
