local T = ...
local ns = T.load()
local Codec, Store, Permissions = ns.Codec, ns.Store, ns.Permissions

local DAY = 86400
local NOW = 1795252375

local function newStore(now)
	return Store.New({}, now or NOW)
end

T.test("store: add, list, facts and sightings", function()
	local s = newStore()
	s:Report("r", "Grimtusk", "Ganking lowbies", "Olaf", nil, NOW)
	s:Report("r", "Grimtusk", "Corpse camped me", "Kari", nil, NOW + 5)
	s:Report("r", "Vexara", "Repeat offender", "Olaf", nil, NOW + 6)
	local players, guilds = s:Counts()
	T.eq(players, 2)
	T.eq(guilds, 0)
	T.ok(s:IsListed("grimtusk"))
	T.ok(not s:IsListed("nobody"))

	local p = T.ok(s:Player("grimtusk"))
	T.eq(#p.reports, 2)
	T.eq(p.reports[1].author, "Olaf") -- oldest first
	T.eq(p.name, "Grimtusk")

	T.ok(s:SetFacts("grimtusk", { guid = "Player-1-AAAA", class = 4, level = 58, guild = "Hostile Takeover" }, "Kari", NOW + 10))
	T.eq(s:SetFacts("grimtusk", { class = 4, level = 58 }, "Per", NOW + 11), nil, "no change, no write")
	T.ok(s:SetFacts("grimtusk", { level = 59 }, "Per", NOW + 12))
	T.eq(s:Player("grimtusk").facts.level, 59)
	T.eq(s:Player("grimtusk").facts.guild, "Hostile Takeover", "unobserved fields are kept")
	T.ok(s:SetFacts("grimtusk", { guild = false }, "Per", NOW + 13))
	T.eq(s:Player("grimtusk").facts.guild, nil, "false clears")
	T.eq(s:KeyForGuid("Player-1-AAAA"), "grimtusk")
	T.eq(s:SetFacts("nobody", { level = 1 }, "Per", NOW), nil, "no facts for unlisted players")

	T.ok(s:SetSeen("grimtusk", { at = NOW + 20, map = 1434, x = 450, y = 620, by = "Kari" }))
	T.ok(not s:SetSeen("grimtusk", { at = NOW + 15, map = 1, by = "Per" }), "older sighting ignored")
	T.eq(s:GetSeen("grimtusk").by, "Kari")
end)

T.test("store: an author's second report replaces the first, keeps creation time", function()
	local s = newStore()
	local first = s:Report("r", "Grimtusk", "one", "Olaf", nil, NOW)
	local second = s:Report("r", "grimtusk", "two", "Olaf", nil, NOW)
	T.eq(second.id, first.id)
	T.ok(second.ts > first.ts, "version always moves forward, even within one second")
	T.eq(second.at, first.at)
	T.eq(second.name, "Grimtusk", "display name of the live report is kept")
	T.eq(#s:Player("grimtusk").reports, 1)
	T.eq(s:Player("grimtusk").reports[1].reason, "two")
end)

T.test("store: remove leaves a tombstone that beats older live versions", function()
	local a, b = newStore(), newStore()
	local live = a:Report("r", "Grimtusk", "x", "Olaf", nil, NOW)
	T.eq(b:Merge(Codec.DecodeRecord(live.wire), NOW), "new")
	local tomb = T.ok(a:Remove(live.id, "Olaf", NOW))
	T.ok(not a:IsListed("grimtusk"))
	T.eq(b:Merge(Codec.DecodeRecord(tomb.wire), NOW), "replaced")
	T.ok(not b:IsListed("grimtusk"))
	T.eq(b:Merge(Codec.DecodeRecord(live.wire), NOW), "older", "the old live version cannot come back")
	T.eq(a:Remove(live.id, "Olaf", NOW), nil, "nothing live to remove")
	-- re-adding is a new, newer version
	local again = a:Report("r", "Grimtusk", "back at it", "Olaf", nil, NOW)
	T.ok(again.ts > tomb.ts)
	T.eq(b:Merge(Codec.DecodeRecord(again.wire), NOW), "replaced")
	T.ok(b:IsListed("grimtusk"))
end)

T.test("store: merge is order-independent (random permutations)", function()
	-- Build a pile of competing versions, including same-second conflicts.
	local src = newStore()
	local versions = {}
	local function keep(rec) versions[#versions + 1] = rec.wire end
	local names = { "Grimtusk", "Vexara", "Morgash", "Zulrakka", "Sylveth" }
	local authors = { "Olaf", "Kari", "Per" }
	for i, name in ipairs(names) do
		for j, author in ipairs(authors) do
			keep(src:Report("r", name, "reason " .. i .. j, author, nil, NOW + i))
			if (i + j) % 2 == 0 then keep(src:Remove("r:" .. name:lower() .. "/" .. author:lower(), "Astrid", NOW + i)) end
			if (i + j) % 3 == 0 then keep(src:Report("r", name, "again " .. i .. j, author, nil, NOW + i)) end
		end
		keep(src:Report("r", name, "anchor", "Ingrid", nil, NOW))
		keep(src:SetFacts(name:lower(), { level = 50 + i, class = i }, "Kari", NOW + i))
		keep(src:SetFacts(name:lower(), { level = 51 + i }, "Per", NOW + i))
	end
	-- two different writers, same id, same second
	keep(Codec.Seal({ k = "r", name = "Tie", author = "Olaf", mby = "Olaf", ts = NOW, at = NOW, reason = "first" }))
	keep(Codec.Seal({ k = "r", name = "Tie", author = "Olaf", mby = "Olaf", ts = NOW, at = NOW, reason = "second" }))
	keep(Codec.Seal({ k = "r", name = "Tie", author = "Olaf", mby = "Astrid", ts = NOW, del = true }))
	keep(Codec.Seal({ k = "g", name = "Hostile Takeover", author = "Astrid", mby = "Astrid", ts = NOW, at = NOW, reason = "war" }))

	local seed = 99
	local function rnd(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n + 1
	end
	local reference
	for _ = 1, 25 do
		local order = {}
		for i = 1, #versions do order[i] = versions[i] end
		for i = #order, 2, -1 do
			local j = rnd(i)
			order[i], order[j] = order[j], order[i]
		end
		local s = newStore(NOW + 100)
		for i = 1, #order do
			s:Merge(Codec.DecodeRecord(order[i]), NOW + 100)
			if i % 7 == 0 then s:Merge(Codec.DecodeRecord(order[rnd(i)]), NOW + 100) end -- duplicates
		end
		local dump = s:Dump() .. "|" .. s:Root()
		reference = reference or dump
		T.eq(dump, reference, "same final state whatever the delivery order")
	end
	T.ok(reference:find("fgrimtusk", 1, true), "facts of listed players are in the synced set")
end)

T.test("store: digests are incremental and survive a reload", function()
	local data = {}
	local s = Store.New(data, NOW)
	for i = 1, 120 do
		s:Report("r", "Enemy" .. string.char(64 + (i % 26) + 1) .. string.char(96 + math.floor(i / 26) + 1), "r" .. i,
			i % 2 == 0 and "Olaf" or "Kari", nil, NOW + i)
	end
	for i = 1, 120, 3 do
		local name = "Enemy" .. string.char(64 + (i % 26) + 1) .. string.char(96 + math.floor(i / 26) + 1)
		s:SetFacts(name:lower(), { level = i % 60 + 1 }, "Per", NOW + 200 + i)
		if i % 2 == 1 then s:Remove("r:" .. name:lower() .. "/kari", "Kari", NOW + 300 + i) end
	end
	local reloaded = Store.New(data, NOW + 400)
	T.eq(reloaded:Root(), s:Root(), "root after reload")
	T.eq(reloaded:Count(), s:Count())
	T.eq(reloaded:Dump(), s:Dump())
	for b = 0, 63 do T.eq(reloaded:Digest(b), s:Digest(b), "bucket " .. b) end
	local total = 0
	for b = 0, 63 do total = total + #s:BucketIds(b) end
	T.eq(total, s:Count(), "every synced record sits in exactly one bucket")
end)

T.test("store: facts leave the synced set with the last live report", function()
	local s = newStore()
	local r = s:Report("r", "Grimtusk", "x", "Olaf", nil, NOW)
	s:SetFacts("grimtusk", { level = 60 }, "Kari", NOW)
	T.eq(s:Count(), 2)
	T.ok(s:InSet("f:grimtusk"))
	s:Remove(r.id, "Olaf", NOW + 1)
	T.eq(s:Count(), 1, "only the tombstone is synced")
	T.ok(not s:InSet("f:grimtusk"))
	s:Report("r", "Grimtusk", "again", "Kari", nil, NOW + 2)
	T.ok(s:InSet("f:grimtusk"), "facts return with a new report")
	T.eq(s:Count(), 3)
end)

T.test("store: old removals are buried and rebut zombies", function()
	local data = {}
	local s = Store.New(data, NOW)
	local live = s:Report("r", "Grimtusk", "x", "Olaf", nil, NOW)
	local zombie = Codec.DecodeRecord(live.wire)
	s:SetFacts("grimtusk", { level = 60 }, "Kari", NOW)
	local tomb = s:Remove(live.id, "Olaf", NOW + 10)
	T.eq(s:Count(), 1)

	local later = NOW + 179 * DAY
	s:Age(later)
	T.eq(s:Count(), 1, "still synced on day 179")
	later = NOW + 181 * DAY
	s:Age(later)
	T.eq(s:Count(), 0, "out of the synced set after 180 days")
	T.eq(s:Get(live.id), nil)
	T.ok(s:Grave(live.id), "kept in the graveyard")
	T.eq(s:Get("f:grimtusk"), nil, "orphaned facts dropped")

	T.eq(s:Merge(zombie, later), "rebut", "a returning member's old copy is refused")
	T.ok(not s:IsListed("grimtusk"))
	T.eq(s:Merge(Codec.DecodeRecord(tomb.wire), later), "grave")

	-- A member who never had the tombstone takes the zombie, then is corrected.
	local fresh = newStore(later)
	T.eq(fresh:Merge(Codec.DecodeRecord(live.wire), later), "new")
	T.eq(fresh:Merge(Codec.DecodeRecord(tomb.wire), later), "buried")
	T.ok(not fresh:IsListed("grimtusk"))
	T.eq(fresh:Count(), 0)

	-- The graveyard survives a reload, and a genuine re-add still works.
	local reloaded = Store.New(data, later)
	T.eq(reloaded:Merge(Codec.DecodeRecord(live.wire), later), "rebut")
	local again = reloaded:Report("r", "Grimtusk", "back", "Olaf", nil, later)
	T.ok(again.ts > tomb.ts)
	T.ok(reloaded:IsListed("grimtusk"))
	T.eq(reloaded:Grave(live.id), nil)
	T.eq(s:Merge(Codec.DecodeRecord(again.wire), later), "new", "others accept the re-add over their buried removal")
end)

T.test("store: timestamps from the future are refused", function()
	local s = newStore()
	local ahead = Codec.Seal({ k = "r", name = "Grimtusk", author = "Olaf", mby = "Olaf", ts = NOW + 3600, at = NOW,
		reason = "x" })
	T.eq(s:Merge(ahead, NOW), "future")
	T.ok(not s:IsListed("grimtusk"))
	local skewed = Codec.Seal({ k = "r", name = "Grimtusk", author = "Olaf", mby = "Olaf", ts = NOW + 60, at = NOW,
		reason = "x" })
	T.eq(s:Merge(skewed, NOW), "new", "small clock skew is tolerated")
end)

T.test("store: dirty flags and the change log", function()
	local data = {}
	local s = Store.New(data, NOW)
	local seen = 0
	s:OnChange(function() seen = seen + 1 end)
	local r = s:Report("r", "Grimtusk", "x", "Olaf", nil, NOW)
	T.ok(s:IsDirty(r.id))
	T.eq(#s:DirtyIds(), 1)
	T.eq(seen, 1)
	T.eq(#Store.New(data, NOW):DirtyIds(), 1, "unsent edits survive a reload")
	s:ClearDirty(r.id)
	T.eq(#s:DirtyIds(), 0)

	local other = newStore()
	local theirs = other:Report("r", "Grimtusk", "newer", "Olaf", "Astrid", NOW + 50)
	s:MarkDirty(r.id)
	T.eq(s:Merge(Codec.DecodeRecord(theirs.wire), NOW + 50, "Kari"), "replaced")
	T.ok(not s:IsDirty(r.id), "a newer remote version supersedes our unsent edit")
	local last = data.log[#data.log]
	T.eq(last.a, "edit")
	T.eq(last.by, "Astrid")
	T.eq(last.via, "Kari")
	T.eq(last.prev, r.wire, "the superseded version is kept for the journal")
end)

T.test("store: guild reports", function()
	local s = newStore()
	s:Report("g", "Hostile Takeover", "war", "Astrid", nil, NOW)
	T.ok(s:IsGuildListed("hostile takeover"))
	T.ok(s:IsGuildListed("HOSTILE TAKEOVER"))
	T.ok(not s:IsGuildListed("Red Ledger"))
	T.eq(#s:Guilds(), 1)
	T.eq(s:Guild("hostile takeover").reports[1].reason, "war")
	s:Remove("g:hostile takeover/astrid", "Bjorn", NOW + 1)
	T.ok(not s:IsGuildListed("Hostile Takeover"))
end)

T.test("permissions: who may write what", function()
	local officers = { astrid = true }
	local roster = { IsOfficer = function(key) return officers[key] end }
	local report = Codec.Seal({ k = "r", name = "Grimtusk", author = "Olaf", mby = "Olaf", ts = NOW, at = NOW, reason = "x" })
	local guild = Codec.Seal({ k = "g", name = "Hostile Takeover", author = "Astrid", mby = "Astrid", ts = NOW, at = NOW,
		reason = "x" })
	local facts = Codec.Seal({ k = "f", key = "grimtusk", mby = "Kari", ts = NOW, level = 60 })
	T.ok(Permissions.CanWrite(report, "olaf", roster), "author")
	T.ok(Permissions.CanWrite(report, "astrid", roster), "officer")
	T.ok(not Permissions.CanWrite(report, "kari", roster), "another member")
	T.ok(Permissions.CanWrite(guild, "astrid", roster), "officer on a guild report")
	T.ok(not Permissions.CanWrite(guild, "olaf", roster), "member on a guild report")
	T.ok(Permissions.CanWrite(facts, "kari", roster), "anyone may record facts")
	T.ok(Permissions.CanAdd("r", "kari", roster))
	T.ok(not Permissions.CanAdd("g", "kari", roster))
	T.ok(Permissions.CanAdd("g", "astrid", roster))
end)

T.test("store: scores sum per player, travel only while listed, reload", function()
	local data = {}
	local s = Store.New(data, NOW)
	T.eq(s:SetScore("grimtusk", "Olaf", 1, 2, NOW), nil, "no score for an unlisted player")
	s:Report("r", "Grimtusk", "x", "Kari", nil, NOW)
	local mine = T.ok(s:SetScore("grimtusk", "Olaf", 1, 2, NOW + 1))
	T.eq(mine.id, "c:grimtusk/olaf")
	T.eq(s:SetScore("grimtusk", "Olaf", 1, 2, NOW + 2), nil, "unchanged, no write")
	s:SetScore("grimtusk", "Kari", 4, 0, NOW + 3)
	local kills, deaths, list = s:Score("grimtusk")
	T.eq(kills, 5)
	T.eq(deaths, 2)
	T.eq(#list, 2)
	T.eq(s:Player("grimtusk").kills, 5)
	T.eq(#s:DirtyIds(), 3)
	local logged = #data.log
	s:SetScore("grimtusk", "Olaf", 2, 2, NOW + 4)
	T.eq(#data.log, logged, "scores stay out of the change log")

	local count = s:Count()
	s:Remove(Codec.Id("r", "grimtusk", "kari"), "Kari", NOW + 5)
	T.ok(not s:InSet("c:grimtusk/olaf"), "unlisted: scores leave the synced set")
	T.eq(s:Count(), count - 2, "tombstone replaces the report, two scores leave")
	s:Report("r", "Grimtusk", "back", "Per", nil, NOW + 6)
	T.ok(s:InSet("c:grimtusk/olaf"), "relisted: scores come back")

	local again = Store.New(data, NOW + 7)
	T.eq(again:Dump(), s:Dump(), "survives a reload")
	T.eq(select(1, again:Score("grimtusk")), 6)
	T.eq(again:Remove("c:grimtusk/olaf", "Olaf", NOW + 8), nil, "scores are not removable like reports")
end)

T.test("permissions: scores belong to their author", function()
	local roster = { IsOfficer = function(key) return key == "astrid" end }
	local rec = Codec.Seal({ k = "c", key = "grimtusk", author = "Olaf", ts = NOW, kills = 1, deaths = 0 })
	T.ok(Permissions.CanWrite(rec, "olaf", roster))
	T.ok(not Permissions.CanWrite(rec, "kari", roster))
	T.ok(not Permissions.CanWrite(rec, "astrid", roster), "not even an officer")
end)
