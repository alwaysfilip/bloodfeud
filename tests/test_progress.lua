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
