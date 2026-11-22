-- The player's own war record: lifetime totals, killing streaks, bounty
-- points, achievements and rank. Kept per character in the saved variables,
-- and published to the guild as one "member" record so everyone can see each
-- other's rank and achievements.
local _, ns = ...

local Util, Names, Codec = ns.Util, ns.Names, ns.Codec
local L = ns.L
local floor = math.floor

local Progress = {}
ns.Progress = Progress

Progress.PAYBACK_SECONDS = 30 * 60 -- killing someone who killed you this recently
Progress.KARMA_SECONDS = 120
Progress.GIANT_LEVELS = 5
Progress.ANNOUNCE_SECONDS = 120 -- only speak about fresh changes
Progress.HOLD_SECONDS = 40 -- after first hearing a guildmate, listen before publishing
Progress.PUBLISH_EVERY = 5 -- how often held-back totals are retried

---------------------------------------------------------------------------
-- Ranks: built in, renamed and moved by officers through "t" records
---------------------------------------------------------------------------

-- The built-in ranks: every killing blow on an enemy player is a confirmed kill.
Progress.DEFAULT_TIERS = {
	{ 1, "Recruit" }, { 10, "Associate" }, { 25, "Operator" }, { 50, "Specialist" },
	{ 100, "Enforcer" }, { 200, "Cleaner" }, { 400, "Assassin" }, { 750, "Ghost" },
	{ 1200, "Phantom" }, { 2000, "Boogeyman" },
}

--- The guild's ladder: { {n, kills, title, custom}, ... } sorted by kills,
--- built-in tiers overridden by the officers' edits. Switched-off tiers
--- (empty title) are left out.
function Progress.Ladder(store)
	local written = store and store:Tiers() or {}
	local ladder = {}
	for n = 1, Codec.MAX_TIERS do
		local rec, default = written[n], Progress.DEFAULT_TIERS[n]
		local kills, title = default and default[1], default and default[2]
		if rec then kills, title = rec.kills, rec.title end
		if title and title ~= "" then
			ladder[#ladder + 1] = { n = n, kills = kills, title = title, custom = rec ~= nil }
		end
	end
	table.sort(ladder, function(a, b)
		if a.kills ~= b.kills then return a.kills < b.kills end
		return a.n < b.n
	end)
	return ladder
end

--- Rank title for a kill count, and the next tier (or nil at the top).
function Progress.RankFor(kills, ladder)
	local rank, nextTier
	for i = 1, #ladder do
		if kills >= ladder[i].kills then
			rank = ladder[i]
		else
			nextTier = ladder[i]
			break
		end
	end
	return rank, nextTier
end

---------------------------------------------------------------------------
-- Local totals
---------------------------------------------------------------------------

local COUNTERS = { "kills", "deaths", "streak", "best", "points", "claims", "posted", "added", "sightings",
	"revengeAdds", "listedKills", "guildListedKills", "payback", "karma", "giant", "night" }

function Progress:Stats()
	local me = Names.Me()
	if not me or not ns.db then return nil end
	ns.db.stats = type(ns.db.stats) == "table" and ns.db.stats or {}
	local key = Names.Key(me)
	local st = ns.db.stats[key]
	if type(st) ~= "table" then
		st = {}
		ns.db.stats[key] = st
	end
	for i = 1, #COUNTERS do
		if type(st[COUNTERS[i]]) ~= "number" then st[COUNTERS[i]] = 0 end
	end
	st.classes = type(st.classes) == "table" and st.classes or {}
	st.guilds = type(st.guilds) == "table" and st.guilds or {}
	st.earned = type(st.earned) == "table" and st.earned or {}
	return st
end

--- Figures that come from the per-enemy fight book rather than counters.
function Progress:Derived(st)
	local d = { victims = 0, maxOne = 0, maxDeathsOne = 0, classes = 0, maxGuild = 0 }
	local book = ns.Feuds and ns.Feuds:Book() or {}
	for _, e in pairs(book) do
		if type(e) == "table" then
			if (e.k or 0) > 0 then d.victims = d.victims + 1 end
			if (e.k or 0) > d.maxOne then d.maxOne = e.k end
			if (e.d or 0) > d.maxDeathsOne then d.maxDeathsOne = e.d end
		end
	end
	for _ in pairs(st.classes) do d.classes = d.classes + 1 end
	for _, n in pairs(st.guilds) do
		if n > d.maxGuild then d.maxGuild = n end
	end
	return d
end

---------------------------------------------------------------------------
-- Achievements
---------------------------------------------------------------------------

--- Bit value of achievement i in the published set.
local function bitOf(i)
	return 2 ^ (i - 1)
end

function Progress.Has(ach, i)
	return floor((ach or 0) / bitOf(i)) % 2 == 1
end

function Progress.CountBits(ach)
	local n = 0
	for i = 1, Codec.MAX_ACHIEVEMENTS do
		if Progress.Has(ach, i) then n = n + 1 end
	end
	return n
end

--- The set of earned achievements as one number, for the member record.
function Progress:Bits(st)
	local n = 0
	for i in pairs(st.earned) do
		if type(i) == "number" and i >= 1 and i <= Codec.MAX_ACHIEVEMENTS then n = n + bitOf(i) end
	end
	return n
end

--- Award everything the totals now qualify for. Returns the new ones.
function Progress:Check(st)
	local list = ns.Achievements or {}
	local d = self:Derived(st)
	local now = GetServerTime()
	local new = {}
	for i = 1, #list do
		local a = list[i]
		if not st.earned[i] then
			local ok, met = pcall(a.test, st, d)
			if ok and met then
				st.earned[i] = now
				new[#new + 1] = a
			end
		end
	end
	return new
end

local function celebrate(list)
	for i = 1, #list do
		local a = list[i]
		if ns.settings.chat then ns:Print(L.ACH_EARNED_YOU:format(a.name, a.desc)) end
		if ns.Alerts and ns.Alerts.Achievement then ns.Alerts:Achievement(a) end
	end
end

---------------------------------------------------------------------------
-- Publishing and defending the member record
---------------------------------------------------------------------------

--- What the member record should say right now.
function Progress:Totals(st)
	return { kills = st.kills, deaths = st.deaths, best = st.best, points = st.points, ach = self:Bits(st) }
end

local GROWING = { "kills", "deaths", "best", "points" }

--- Take over whatever a record in my name knows that this computer does not:
--- after a reinstall, or when I also play on another computer, the guild
--- remembers more than the local file. These numbers only ever grow, so the
--- larger one is the true one. Returns true when something was taken.
function Progress:Absorb(st, rec)
	local took = false
	for i = 1, #GROWING do
		local f = GROWING[i]
		if rec[f] > st[f] then
			st[f] = rec[f]
			took = true
		end
	end
	for i = 1, Codec.MAX_ACHIEVEMENTS do
		if Progress.Has(rec.ach, i) and not st.earned[i] then
			st.earned[i] = rec.ts
			took = true
		end
	end
	return took
end

--- Absorb the record the guild list holds for me, if any.
function Progress:Adopt(st)
	local s = ns.session
	local rec = s and s.store:Member(s.meKey)
	return rec and self:Absorb(st, rec) or false
end

--- After logging in nothing is published until the guild has had the chance
--- to send what it remembers about me, so that an older (or empty) local
--- file cannot overwrite it: either somebody demonstrably holds exactly the
--- list we hold, or a guildmate has been on the air for a while. Alone, there
--- is nobody to publish to, and nothing is written.
function Progress:Ready()
	local s = ns.session
	if not s or not self.boundAt then return false end
	local agreed = s.store.data.agreedAt
	if agreed and agreed >= self.boundServer then return true end
	if not self.heardAt and s.sync:PeerCount() > 0 then self.heardAt = GetTime() end
	return self.heardAt ~= nil and GetTime() - self.heardAt >= Progress.HOLD_SECONDS
end

function Progress:Publish()
	local s = ns.session
	local st = self:Stats()
	if not s or not st or not self:Ready() then return nil end
	self:Adopt(st)
	local totals = self:Totals(st)
	if not s.store:Member(s.meKey) and totals.kills + totals.deaths + totals.points + totals.ach == 0 then
		return nil -- nothing to tell yet
	end
	return s.store:SetMember(s.me, totals, GetServerTime())
end

--- A record in my name arrived. What it knows beyond this computer is taken
--- over (see Absorb); where it says less, it is stale or was made up by
--- whoever relayed it, and is answered with the real numbers. Relayed state
--- cannot be verified, so a made-up record can add to my totals but never
--- take anything away.
function Progress:Defend(rec)
	local s = ns.session
	local st = self:Stats()
	if not s or not st or rec.akey ~= s.meKey then return end
	if self:Absorb(st, rec) then ns:Fire("PROGRESS_CHANGED") end
	if not self:Ready() then return end -- the publish at the end of the hold covers it
	local want = self:Totals(st)
	for f, v in pairs(want) do
		if rec[f] ~= v then
			ns:Debug("correcting totals relayed in my name")
			s.store:SetMember(s.me, want, GetServerTime())
			return
		end
	end
end

--- Bump a counter by one (or `n`), award, publish. Returns the new value.
function Progress:Bump(field, n)
	local st = self:Stats()
	if not st then return nil end
	st[field] = (st[field] or 0) + (n or 1)
	celebrate(self:Check(st))
	self:Publish()
	ns:Fire("PROGRESS_CHANGED")
	return st[field]
end

---------------------------------------------------------------------------
-- Fights
---------------------------------------------------------------------------

local function myLevel()
	local level = _G.UnitLevel and _G.UnitLevel("player")
	if type(level) == "number" and not Util.IsSecret(level) then return level end
	return nil
end

--- A killing blow on an enemy player. `e` is the fight-book entry for them
--- (already counted), `listed` whether they are on the Kill on Sight list.
function Progress:OnKill(info, key, listed, e)
	local st = self:Stats()
	if not st then return end
	local now = GetServerTime()
	st.kills = st.kills + 1
	st.streak = st.streak + 1
	if st.streak > st.best then st.best = st.streak end
	if info.class then st.classes[info.class] = true end
	if listed then st.listedKills = st.listedKills + 1 end
	local s = ns.session
	if info.guild then
		local gkey = Util.Fold(info.guild)
		st.guilds[gkey] = (st.guilds[gkey] or 0) + 1
		if s and s.store:IsGuildListed(info.guild) then st.guildListedKills = st.guildListedKills + 1 end
	end
	-- Did they kill us lately?
	local lastDeath = 0
	for _, t in ipairs(e and e.r or {}) do
		if t > lastDeath then lastDeath = t end
	end
	if lastDeath > 0 and now - lastDeath <= Progress.PAYBACK_SECONDS then
		st.payback = st.payback + 1
		if now - lastDeath <= Progress.KARMA_SECONDS then st.karma = st.karma + 1 end
	end
	-- info.high: the client hid their level, which it does for players far
	-- above ours.
	local mine = myLevel()
	if info.high or (mine and info.level and info.level - mine >= Progress.GIANT_LEVELS) then
		st.giant = st.giant + 1
	end
	local clock = date("*t")
	if clock and clock.hour and clock.hour < 5 then st.night = st.night + 1 end

	if ns.Bounties then ns.Bounties:OnKill(info, key, st) end
	if ns.settings.dealBanner and ns.Alerts and ns.Alerts.Deal then
		local _, nextTier = Progress.RankFor(st.kills, Progress.Ladder(s and s.store))
		ns.Alerts:Deal(info, st, nextTier)
	end
	celebrate(self:Check(st))
	self:Publish()
	ns:Fire("PROGRESS_CHANGED")
end

--- Any death in the open world, whoever or whatever caused it, ends a
--- killing streak.
function Progress:EndStreak()
	local st = self:Stats()
	if st and st.streak > 0 then
		st.streak = 0
		ns:Fire("PROGRESS_CHANGED")
	end
end

--- A death to an enemy player we could identify.
function Progress:OnDeath()
	local st = self:Stats()
	if not st then return end
	st.deaths = st.deaths + 1
	st.streak = 0
	celebrate(self:Check(st))
	self:Publish()
	ns:Fire("PROGRESS_CHANGED")
end

---------------------------------------------------------------------------
-- What guildmates did
---------------------------------------------------------------------------

local function announce(rec, old)
	if not ns.settings.chat or not old then return end
	local s = ns.session
	if not s or rec.akey == s.meKey then return end
	if GetServerTime() - rec.ts > Progress.ANNOUNCE_SECONDS then return end
	local who = Names.Display(rec.author)
	local list = ns.Achievements or {}
	for i = 1, #list do
		if Progress.Has(rec.ach, i) and not Progress.Has(old.ach, i) then
			ns:Print(L.ACH_EARNED:format(who, list[i].name))
		end
	end
	local ladder = Progress.Ladder(s.store)
	local before, after = Progress.RankFor(old.kills, ladder), Progress.RankFor(rec.kills, ladder)
	if after and (not before or after.kills > before.kills) then
		ns:Print(L.RANK_UP:format(who, after.title))
	end
end

--- Everyone the guild knows about, with rank: list of
--- { key, name, kills, deaths, best, points, ach, rank, me, dishonored }.
function Progress:Roll()
	local s = ns.session
	if not s then return {} end
	local ladder = Progress.Ladder(s.store)
	local disgrace = s.store:Dishonor(GetServerTime())
	local out = {}
	local function add(key, name, t, ts, me)
		out[#out + 1] = {
			key = key, name = name, kills = t.kills, deaths = t.deaths, best = t.best, points = t.points, ach = t.ach,
			rank = Progress.RankFor(t.kills, ladder), me = me, ts = ts,
			-- An unpaid bounty debt past its deadline: no rank and no bounty
			-- points to show for as long as it stands.
			dishonored = disgrace[key],
		}
	end
	local members = s.store:Members()
	for i = 1, #members do
		local rec = members[i]
		if rec.akey ~= s.meKey then add(rec.akey, rec.author, rec, rec.ts, false) end
	end
	-- My own row comes from this computer: it is never behind, and it is
	-- there before anything has been published.
	local st = self:Stats()
	if st then add(s.meKey, s.me, self:Totals(st), GetServerTime(), true) end
	table.sort(out, function(a, b)
		if a.kills ~= b.kills then return a.kills > b.kills end
		return a.key < b.key
	end)
	return out
end

--- My own rank title and progress text.
function Progress:MyRank()
	local s = ns.session
	local st = self:Stats()
	if not st then return nil end
	return Progress.RankFor(st.kills, Progress.Ladder(s and s.store))
end

---------------------------------------------------------------------------
-- Officers: the ladder
---------------------------------------------------------------------------

--- Change tier n. Officers only. Returns the record, or nil.
function ns:SetTier(n, kills, title)
	local s = self.session
	if not s then
		self:Print(L.MSG_NO_GUILD)
		return nil
	end
	if not ns.Roster.AmOfficer() then
		self:Print(L.MSG_NOT_OFFICER)
		return nil
	end
	n = tonumber(n)
	kills = tonumber(kills)
	if not n or n < 1 or n > Codec.MAX_TIERS or n ~= floor(n) or not kills or kills < 0 then return nil end
	return s.store:SetTier(n, kills, title or "", s.me, GetServerTime())
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

function Progress:Init()
	ns:Listen("LIST_CHANGED", function(_, rec, old)
		if not rec or rec.k ~= "m" then return end
		local s = ns.session
		if s and rec.akey == s.meKey then
			Progress:Defend(rec)
		else
			announce(rec, old)
		end
	end)
	local function onSession()
		local st = Progress:Stats()
		if not st or not ns.session then return end
		Progress.boundAt, Progress.boundServer, Progress.heardAt = GetTime(), GetServerTime(), nil
		Progress:Adopt(st)
		celebrate(Progress:Check(st))
	end
	ns:Listen("SESSION_CHANGED", onSession)
	-- The guild is usually bound before this module starts (and always after
	-- a /reload), in which case the signal has already gone by.
	if ns.session then onSession() end
	-- Whatever could not be published yet (see Ready) goes out once it can.
	-- Publish writes nothing when the guild already has the current totals.
	C_Timer.NewTicker(Progress.PUBLISH_EVERY, function() ns.Safe(Progress.Publish, Progress) end)
end
