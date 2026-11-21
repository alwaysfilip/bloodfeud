-- Members' totals, the rank ladder, bounties and bounty claims: the wire
-- format, the store and how they spread through the guild.
local T = ...
local ns = T.load()
local Sim = assert(loadfile(T.root .. "/tests/sim.lua"))()
local Codec, Store, Permissions = ns.Codec, ns.Store, ns.Permissions

local NOW = 1795252375
local DAY = 86400

local function roundTrip(rec)
	local back = Codec.DecodeRecord(rec.wire)
	T.ok(back, "decodes: " .. rec.wire)
	T.eq(back.wire, rec.wire)
	T.eq(back.id, rec.id)
	return back
end

T.test("progress: new record kinds round-trip and reject bad input", function()
	local s = Store.New({}, NOW)
	local m = roundTrip(s:SetMember("Kari-Frost", { kills = 120, deaths = 33, best = 7, points = 40, ach = 2 ^ 40 + 5 }, NOW))
	T.eq(m.kills, 120)
	T.eq(m.ach, 2 ^ 40 + 5)
	T.eq(m.id, "m:kari-frost")

	local t = roundTrip(s:SetTier(3, 25, "Raider", "Astrid-Vale", NOW))
	T.eq(t.title, "Raider")
	T.eq(t.id, "t:3")

	local b = roundTrip(s:PostBounty("p", "Grimtusk-Bloodaxe", 15, "50 gold", "Olaf-Stormborn", nil, NOW))
	T.eq(b.points, 15)
	T.eq(b.reward, "50 gold")
	T.eq(b.id, "b:pgrimtusk-bloodaxe/olaf-stormborn")
	local g = roundTrip(s:PostBounty("g", "Hostile Takeover", 999, "", "Olaf-Stormborn", nil, NOW))
	T.eq(g.points, Codec.MAX_POINTS, "points are capped")

	local k = roundTrip(s:Claim(b.id, "Kari-Frost", NOW + 1))
	T.eq(k.count, 1)
	T.eq(k.bid, b.id)
	T.eq(s:Claim(b.id, "Kari-Frost", NOW + 2).count, 2)

	local gone = roundTrip(s:Remove(b.id, "Olaf-Stormborn", NOW + 3))
	T.ok(gone.del)
	T.eq(gone.scope, "p")

	-- Malformed input
	T.eq(Codec.DecodeRecord("mKari~1~2~3~4~5"), nil, "member with a field missing")
	T.eq(Codec.DecodeRecord("t" .. ns.Util.Enc(13) .. "~1~Astrid~0~Too high"), nil, "tier out of range")
	T.eq(Codec.DecodeRecord("bGrim~Olaf~1~~1~x~1~"), nil, "unknown bounty scope")
	T.eq(Codec.DecodeRecord("bGrim~Olaf~1~~1~p~0~"), nil, "bounty worth nothing")
	T.eq(Codec.DecodeRecord("kp~Grim~Olaf~Kari~1~1"), nil, "claim on an unfolded key")
end)

T.test("progress: claims travel only while their bounty is up, points do not", function()
	local s = Store.New({}, NOW)
	local b = s:PostBounty("p", "Grimtusk", 10, "", "Olaf", nil, NOW)
	local k = s:Claim(b.id, "Kari", NOW + 1)
	T.ok(s:InSet(k.id))
	local view = s:Bounties("p", "grimtusk")[1]
	T.eq(view.total, 1)
	T.eq(view.claims[1].author, "Kari")
	T.ok(s:HasBounty("p", "grimtusk"))

	s:Remove(b.id, "Olaf", NOW + 2)
	T.ok(not s:InSet(k.id), "claims of a removed bounty leave the synced set")
	T.ok(not s:HasBounty("p", "grimtusk"))
	T.eq(s:Claim(b.id, "Kari", NOW + 3), nil, "nothing to claim any more")
	T.eq(#s:Bounties(), 0)

	-- Posted again: the claims of the earlier posting do not come back
	local again = s:PostBounty("p", "Grimtusk", 50, "", "Olaf", nil, NOW + 100)
	T.eq(again.id, b.id)
	T.eq(s:Bounties("p", "grimtusk")[1].total, 0, "a new posting starts with no claims")
	T.ok(not s:InSet(k.id), "the old claim stays out of the synced set")
	local k2 = s:Claim(b.id, "Kari", NOW + 101)
	T.eq(k2.count, 1, "and the count starts again")
	T.ok(s:InSet(k2.id))
	T.eq(s:Bounties("p", "grimtusk")[1].total, 1)
	s:Remove(b.id, "Olaf", NOW + 102)

	-- Once the removal is buried, the claim goes too.
	s:Age(NOW + (Store.TOMB_DAYS + 1) * DAY)
	T.eq(s:Get(k.id), nil)

	-- Members' totals do not depend on any bounty, and fade after a year.
	local m = s:SetMember("Kari", { kills = 3, deaths = 1, best = 2, points = 10, ach = 1 }, NOW)
	T.eq(s:SetMember("Kari", { kills = 3, deaths = 1, best = 2, points = 10, ach = 1 }, NOW + 5), nil, "no change")
	T.ok(s:InSet(m.id))
	s:Age(NOW + (Store.MEMBER_DAYS + 1) * DAY)
	T.eq(s:Member("kari"), nil)
end)

T.test("progress: who may write totals, tiers, bounties and claims", function()
	local roster = { IsOfficer = function(key) return key == "astrid" end }
	local s = Store.New({}, NOW)
	local m = s:SetMember("Kari", { kills = 1 }, NOW)
	T.ok(Permissions.CanWrite(m, "kari", roster))
	T.ok(not Permissions.CanWrite(m, "astrid", roster), "not even an officer writes someone else's totals")

	local t = s:SetTier(1, 5, "Blooded", "Astrid", NOW)
	T.ok(Permissions.CanWrite(t, "astrid", roster))
	T.ok(not Permissions.CanWrite(t, "kari", roster))
	T.ok(Permissions.NeedsRoster(t, "astrid"))

	local b = s:PostBounty("p", "Grimtusk", 10, "", "Olaf", nil, NOW)
	T.ok(Permissions.CanWrite(b, "olaf", roster))
	T.ok(Permissions.CanWrite(b, "astrid", roster), "an officer may take a bounty down")
	T.ok(not Permissions.CanWrite(b, "kari", roster))
	T.ok(not Permissions.NeedsRoster(b, "olaf"))

	local k = s:Claim(b.id, "Kari", NOW)
	T.ok(Permissions.CanWrite(k, "kari", roster))
	T.ok(not Permissions.CanWrite(k, "olaf", roster), "a poster cannot claim in someone else's name")
	T.ok(not Permissions.NeedsRoster(k, "kari"))
end)

T.test("progress: bounties, claims, totals and tiers reach the whole guild", function()
	local sim = Sim.New(ns, 21)
	local names = { "Olaf", "Kari", "Per", "Astrid" }
	local c = {}
	for i, name in ipairs(names) do c[i] = sim:AddClient(name, { officer = name == "Astrid" }) end
	local olaf, kari, per, astrid = c[1], c[2], c[3], c[4]
	sim:Run(40)

	local b = olaf.store:PostBounty("p", "Grimtusk", 20, "50 gold", "Olaf", nil, olaf.env.time())
	kari.store:SetMember("Kari", { kills = 12, deaths = 4, best = 3, points = 0, ach = 3 }, kari.env.time())
	astrid.store:SetTier(2, 15, "Bloodhound", "Astrid", astrid.env.time())
	sim:Run(15)
	T.ok(sim:Converged())
	T.ok(per.store:HasBounty("p", "grimtusk"))
	T.eq(per.store:Member("kari").kills, 12)
	T.eq(per.store:Tiers()[2].title, "Bloodhound")

	kari.store:Claim(b.id, "Kari", kari.env.time())
	sim:Run(10)
	T.eq(per.store:Bounties("p", "grimtusk")[1].total, 1)

	-- A member cannot change the ladder or claim in someone else's name.
	per.store:SetTier(2, 1, "Per's Pals", "Per", per.env.time())
	per.store:SetMember("Kari", { kills = 999 }, per.env.time())
	sim:Run(20)
	T.eq(olaf.store:Tiers()[2].title, "Bloodhound", "tier edit by a member refused")
	-- Totals in Kari's name look like relayed state, which cannot be told
	-- from a forgery; Kari's own client answers with the real numbers (the
	-- game does this in Progress:Defend) and the newer write wins.
	T.eq(olaf.store:Member("kari").kills, 999)
	kari.store:SetMember("Kari", { kills = 12, deaths = 4, best = 3, points = 0, ach = 3 }, kari.env.time())
	sim:Run(15)
	T.eq(olaf.store:Member("kari").kills, 12, "the author's correction wins everywhere")

	-- The poster takes the bounty down; the claim goes with it.
	olaf.store:Remove(b.id, "Olaf", olaf.env.time())
	sim:Run(15)
	T.ok(not kari.store:HasBounty("p", "grimtusk"))
	T.eq(#kari.store:Bounties(), 0)
end)

T.test("gold: bounties with gold and debt marks round-trip, bad ones are refused", function()
	local s = Store.New({}, NOW)
	local b = roundTrip(s:PostBounty("p", "Grimtusk-Bloodaxe", 15, "for the camping", "Olaf-Stormborn", nil, NOW, 50))
	T.eq(b.gold, 50)
	T.eq(roundTrip(s:PostBounty("g", "Hostile Takeover", 5, "", "Olaf-Stormborn", nil, NOW)).gold, 0, "gold is optional")
	T.eq(s:PostBounty("p", "Vexara", 5, "", "Olaf-Stormborn", nil, NOW, 5e9).gold, Codec.MAX_GOLD, "and capped")

	s:Claim(b.id, "Kari-Frost", NOW + 10)
	local sent = roundTrip(s:SetMark(b.id, "s", "s", "Olaf-Stormborn", NOW + 20))
	T.eq(sent.id, "d:pgrimtusk-bloodaxe/olaf-stormborn/s")
	T.eq(sent.bid, b.id)
	local got = roundTrip(s:SetMark(b.id, "w", "r", "Kari-Frost", NOW + 30))
	T.eq(got.id, "d:pgrimtusk-bloodaxe/olaf-stormborn/w/kari-frost")
	local ruled = roundTrip(s:SetMark(b.id, "o", "o", "Astrid-Vale", NOW + 40))
	T.eq(ruled.id, "d:pgrimtusk-bloodaxe/olaf-stormborn/o")
	T.eq(s:SetMark(b.id, "o", "o", "Astrid-Vale", NOW + 41), nil, "no change, no write")

	local E = ns.Util.Enc
	T.eq(Codec.DecodeRecord("dp~grimtusk~Olaf~s~Kari~" .. E(NOW) .. "~s"), nil, "only the poster can say sent")
	T.eq(Codec.DecodeRecord("dp~grimtusk~Olaf~w~Kari~" .. E(NOW) .. "~s"), nil, "a state of another role")
	T.eq(Codec.DecodeRecord("dp~grimtusk~Olaf~q~Kari~" .. E(NOW) .. "~r"), nil, "unknown role")
	T.ok(Codec.DecodeRecord("dp~grimtusk~Olaf~w~Kari~" .. E(NOW) .. "~x"), "a well-formed one parses")
	T.eq(Codec.DecodeRecord("bGrim~Olaf~" .. E(NOW) .. "~~" .. E(NOW) .. "~p~" .. E(5) .. "~note"), nil,
		"a 0.2.0 bounty, without the gold field")
end)

T.test("gold: the first kill wins, and the debt runs its course", function()
	local HOUR = 3600
	local s = Store.New({}, NOW)
	local b = s:PostBounty("p", "Grimtusk", 10, "", "Olaf", nil, NOW, 50)
	T.eq(s:Winner(b), nil)
	T.eq(s:Debt(b, NOW), nil, "nobody is owed anything yet")

	local claim = T.ok(s:Claim(b.id, "Kari", NOW + 100))
	T.eq(s:Winner(b), claim)
	T.eq(s:Claim(b.id, "Per", NOW + 200), nil, "the gold was already won")
	T.eq(s:Claim(b.id, "Kari", NOW + 300), nil, "also for the winner: once is once")
	T.eq(s:Bounties("p", "grimtusk")[1].winner, claim)

	local d = T.ok(s:Debt(b, NOW + 100))
	T.eq(d.winner, "Kari")
	T.eq(d.poster, "Olaf")
	T.eq(d.gold, 50)
	T.eq(d.state, "owed")
	T.eq(d.due, NOW + 100 + 48 * HOUR)
	T.ok(d.open and not d.late)
	T.eq(next(s:Dishonor(NOW + 100 + 47 * HOUR)), nil, "still in time")
	T.ok(s:Debt(b, NOW + 100 + 49 * HOUR).late, "overdue after 48 hours")
	T.eq(s:Dishonor(NOW + 100 + 49 * HOUR).olaf.winner, "Kari", "and the poster is in disgrace")

	-- The poster sends it: the clock stops, even past the deadline
	T.ok(s:SetMark(b.id, "s", "s", "Olaf", NOW + 40 * HOUR))
	d = s:Debt(b, NOW + 60 * HOUR)
	T.eq(d.state, "sent")
	T.ok(d.open and not d.late)
	-- Someone who is not the winner has no say
	s:SetMark(b.id, "w", "r", "Per", NOW + 41 * HOUR)
	T.eq(s:Debt(b, NOW + 60 * HOUR).state, "sent", "a bystander's 'received' is not looked at")
	-- The winner says it never came: the clock runs again, from the claim
	s:SetMark(b.id, "w", "x", "Kari", NOW + 42 * HOUR)
	d = s:Debt(b, NOW + 60 * HOUR)
	T.eq(d.state, "disputed")
	T.ok(d.late)
	-- ...then gets it
	s:SetMark(b.id, "w", "r", "Kari", NOW + 61 * HOUR)
	d = s:Debt(b, NOW + 62 * HOUR)
	T.eq(d.state, "paid")
	T.ok(not d.open and not d.late)
	T.eq(next(s:Dishonor(NOW + 62 * HOUR)), nil)
	T.eq(#s:Debts(NOW + 62 * HOUR), 1)

	-- An officer can close a debt whatever the two say
	local b2 = s:PostBounty("p", "Vexara", 10, "", "Olaf", nil, NOW, 20)
	s:Claim(b2.id, "Per", NOW + 10)
	s:SetMark(b2.id, "w", "x", "Per", NOW + 20)
	s:SetMark(b2.id, "o", "o", "Astrid", NOW + 30)
	T.eq(s:Debt(b2, NOW + 99 * HOUR).state, "settled")
	T.ok(not s:Debt(b2, NOW + 99 * HOUR).late)
	s:SetMark(b2.id, "o", "n", "Astrid", NOW + 40)
	T.eq(s:Debt(b2, NOW + 99 * HOUR).state, "disputed", "and take that back")

	-- Who won is the earliest claim, whatever order the claims arrive in
	local a, c = Store.New({}, NOW), Store.New({}, NOW)
	local posted = a:PostBounty("p", "Zulrakka", 10, "", "Olaf", nil, NOW, 5)
	c:Merge(Codec.DecodeRecord(posted.wire), NOW)
	local first = a:Claim(posted.id, "Kari", NOW + 50)
	local second = c:Claim(posted.id, "Per", NOW + 60) -- Per had not heard of Kari's kill yet
	a:Merge(Codec.DecodeRecord(second.wire), NOW + 70)
	c:Merge(Codec.DecodeRecord(first.wire), NOW + 70)
	T.eq(a:Winner(a:Get(posted.id)).author, "Kari")
	T.eq(c:Winner(c:Get(posted.id)).author, "Kari", "both agree on the earlier kill")
	T.eq(a:Dump(), c:Dump())

	-- Changing the gold makes it a new posting: old kills do not win it
	local p = s:PostBounty("p", "Sylveth", 10, "", "Olaf", nil, NOW)
	s:Claim(p.id, "Kari", NOW + 5)
	T.eq(s:Bounties("p", "sylveth")[1].total, 1)
	p = s:PostBounty("p", "Sylveth", 10, "", "Olaf", nil, NOW + 50, 30)
	T.eq(s:Winner(p), nil, "a kill from before the gold was offered does not win it")
	T.ok(s:Claim(p.id, "Per", NOW + 60))
	T.eq(s:Winner(s:Get(p.id)).author, "Per")
	-- ...and so do the marks of the earlier posting
	s:SetMark(p.id, "s", "s", "Olaf", NOW + 70)
	local again = s:PostBounty("p", "Sylveth", 10, "", "Olaf", nil, NOW + 80, 40)
	s:Claim(again.id, "Kari", NOW + 90)
	T.eq(s:Debt(s:Get(again.id), NOW + 91).state, "owed", "an old 'sent' does not carry over")
end)

T.test("gold: who may put which mark on a debt", function()
	local roster = { IsOfficer = function(key) return key == "astrid" end }
	local s = Store.New({}, NOW)
	local b = s:PostBounty("p", "Grimtusk", 10, "", "Olaf", nil, NOW, 50)
	s:Claim(b.id, "Kari", NOW + 1)
	local sent = s:SetMark(b.id, "s", "s", "Olaf", NOW + 2)
	T.ok(Permissions.CanWrite(sent, "olaf", roster))
	T.ok(not Permissions.CanWrite(sent, "kari", roster))
	T.ok(not Permissions.NeedsRoster(sent, "olaf"))
	local got = s:SetMark(b.id, "w", "r", "Kari", NOW + 3)
	T.ok(Permissions.CanWrite(got, "kari", roster))
	T.ok(not Permissions.CanWrite(got, "olaf", roster), "the poster cannot confirm their own payment")
	T.ok(not Permissions.CanWrite(got, "astrid", roster))
	local ruled = s:SetMark(b.id, "o", "o", "Astrid", NOW + 4)
	T.ok(Permissions.CanWrite(ruled, "astrid", roster))
	T.ok(Permissions.NeedsRoster(ruled, "astrid"))
	local fake = Codec.Seal({ k = "d", scope = "p", key = "grimtusk", poster = "Olaf", role = "o", author = "Olaf",
		ts = NOW + 5, state = "o" })
	T.ok(not Permissions.CanWrite(fake, "olaf", roster), "a member cannot settle their own debt")
end)

T.test("gold: a won bounty and its marks reach the whole guild", function()
	local sim = Sim.New(ns, 31)
	local c = {}
	for i, name in ipairs({ "Olaf", "Kari", "Per", "Astrid" }) do c[i] = sim:AddClient(name, { officer = name == "Astrid" }) end
	local olaf, kari, per, astrid = c[1], c[2], c[3], c[4]
	sim:Run(40)
	local b = olaf.store:PostBounty("p", "Grimtusk", 20, "", "Olaf", nil, olaf.env.time(), 50)
	sim:Run(10)
	kari.store:Claim(b.id, "Kari", kari.env.time())
	sim:Run(10)
	for _, client in ipairs(c) do
		local debt = T.ok(client.store:Debt(client.store:Get(b.id), client.env.time()), client.name .. " sees the debt")
		T.eq(debt.winner, "Kari")
		T.eq(debt.state, "owed")
	end
	T.eq(per.store:Claim(b.id, "Per", per.env.time()), nil, "too late for Per")

	-- The poster cannot settle it himself; the winner's word does
	olaf.store:SetMark(b.id, "o", "o", "Olaf", olaf.env.time())
	sim:Run(15)
	T.eq(per.store:Debt(per.store:Get(b.id), per.env.time()).state, "owed", "a member's 'settled' is refused")
	olaf.store:SetMark(b.id, "o", "n", "Olaf", olaf.env.time())
	olaf.store:SetMark(b.id, "s", "s", "Olaf", olaf.env.time())
	sim:Run(10)
	T.eq(astrid.store:Debt(astrid.store:Get(b.id), astrid.env.time()).state, "sent")
	kari.store:SetMark(b.id, "w", "r", "Kari", kari.env.time())
	sim:Run(10)
	T.eq(olaf.store:Debt(olaf.store:Get(b.id), olaf.env.time()).state, "paid")
	T.eq(per.store:Debt(per.store:Get(b.id), per.env.time()).state, "paid")

	-- An officer settles another one
	local b2 = olaf.store:PostBounty("p", "Vexara", 20, "", "Olaf", nil, olaf.env.time(), 10)
	sim:Run(10)
	per.store:Claim(b2.id, "Per", per.env.time())
	sim:Run(10)
	astrid.store:SetMark(b2.id, "o", "o", "Astrid", astrid.env.time())
	sim:Run(10)
	T.eq(kari.store:Debt(kari.store:Get(b2.id), kari.env.time()).state, "settled")
end)
