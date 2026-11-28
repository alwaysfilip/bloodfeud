local T = ...
local ns = T.load()
local Sim = assert(loadfile(T.root .. "/tests/sim.lua"))()
local Codec, Store = ns.Codec, ns.Store

local DAY = 86400

local function enemyName(i)
	return "Enemy" .. string.char(65 + i % 26) .. string.char(97 + math.floor(i / 26) % 26)
		.. string.char(97 + math.floor(i / 676) % 26)
end

-- A guild state with n listed players (every third one with facts).
local function seedData(n, now)
	local data = {}
	local s = Store.New(data, now)
	local authors = { "Olaf", "Kari", "Per", "Ingrid" }
	for i = 1, n do
		local name = enemyName(i)
		s:Report("r", name, "Reason number " .. i .. " for the list", authors[i % #authors + 1], nil, now - 2000 + i)
		if i % 3 == 0 then
			s:SetFacts(name:lower(), { guid = "Player-1-" .. string.format("%08X", i), class = i % 9 + 1, race = i % 8 + 1,
				level = i % 60 + 1, guild = "Hostile Takeover" }, "Kari", now - 500 + i % 400)
		end
	end
	data.dirty = {}
	return data
end

local function guild(sim, names, data, opts)
	local clients = {}
	for i, name in ipairs(names) do
		local o = { data = data and Sim.Clone(data) or nil }
		for k, v in pairs(opts and opts[name] or {}) do o[k] = v end
		clients[i] = sim:AddClient(name, o)
	end
	return clients
end

local NAMES = { "Olaf", "Kari", "Per", "Ingrid", "Astrid", "Bjorn" }

T.test("sync: an edit reaches everyone in seconds and costs one frame", function()
	local sim = Sim.New(ns, 1)
	local c = guild(sim, NAMES)
	sim:Run(60)
	T.ok(sim.frames.H <= 3, "an idle, agreeing guild exchanges almost no hellos: " .. sim.frames.H)
	sim:ResetCounters()

	c[1].store:Report("r", "Grimtusk", "Ganking lowbies in STV", "Olaf", nil, c[1].env.time())
	sim:Run(5)
	for _, client in ipairs(c) do
		T.ok(client.store:IsListed("grimtusk"), client.name .. " has the entry")
	end
	T.eq(sim.frames.U, 1, "one update frame")
	T.eq(sim.frames.H, 0, "no hello needed")
	T.ok(not c[1].store:IsDirty("r:grimtusk/olaf"), "the echo cleared the unsent flag")
	T.ok(sim:Converged())

	-- and stays quiet afterwards
	sim:ResetCounters()
	sim:Run(300)
	T.eq(sim.frames.total, 0, "nothing more to say")
end)

T.test("sync: a fresh install catches up from a 50-entry guild", function()
	local sim = Sim.New(ns, 2)
	local now = sim:Time()
	guild(sim, { "Olaf", "Kari", "Per", "Ingrid", "Astrid" }, seedData(50, now))
	sim:Run(60)
	sim:ResetCounters()
	local fresh = sim:AddClient("Newbie")
	local took = T.ok(sim:RunUntilConverged(180), "converges")
	T.ok(took <= 60, "within a minute: " .. took)
	local players = fresh.store:Counts()
	T.eq(players, 50)
	T.eq(sim.throttled, 0, "nobody hit the server throttle")
	T.ok(sim.frames.U <= 75, "update frames: " .. sim.frames.U)
	T.ok(sim.frames.H <= 4, "hellos: " .. sim.frames.H)
	T.ok(sim.maxFrame <= 255)
	sim:ResetCounters()
	sim:Run(120)
	T.ok(sim.frames.total <= 1, "quiet after convergence: " .. sim.frames.total)
end)

T.test("sync: two members listing the same enemy both keep their report", function()
	local sim = Sim.New(ns, 3)
	local c = guild(sim, NAMES)
	sim:Run(40)
	c[1].store:Report("r", "Grimtusk", "Ganked me", "Olaf", nil, c[1].env.time())
	c[2].store:Report("r", "grimtusk", "Camped me", "Kari", nil, c[2].env.time())
	sim:Run(15)
	T.ok(sim:Converged())
	for _, client in ipairs(c) do
		T.eq(#client.store:Player("grimtusk").reports, 2, client.name .. " sees both reports")
	end
end)

T.test("sync: removal rights are enforced on direct edits", function()
	local sim = Sim.New(ns, 4)
	local c = guild(sim, NAMES, nil, { Astrid = { officer = true } })
	local olaf, kari, astrid = c[1], c[2], c[5]
	sim:Run(40)
	olaf.store:Report("r", "Grimtusk", "Ganked me", "Olaf", nil, olaf.env.time())
	olaf.store:Report("r", "Vexara", "Repeat offender", "Olaf", nil, olaf.env.time())
	sim:Run(10)
	T.ok(sim:Converged())

	-- Kari's client misbehaves and removes Olaf's report without the right to.
	kari.store:Remove("r:grimtusk/olaf", "Kari", kari.env.time())
	sim:Run(30)
	for _, client in ipairs(c) do
		if client ~= kari then
			T.ok(client.store:IsListed("grimtusk"), client.name .. " refused the removal")
		end
	end
	T.ok(olaf.sync.stats.denied >= 1, "and counted it as denied")
	local log = olaf.data.log[#olaf.data.log]
	T.eq(log.a, "denied")
	T.eq(log.via, "Kari")

	-- A permanently disagreeing client must not make the guild chatter.
	sim:Run(900)
	sim:ResetCounters()
	sim:Run(3600)
	T.ok(sim.frames.total <= 90, "frames in an hour with one divergent client: " .. sim.frames.total)
	T.eq(sim.throttled, 0)

	-- An officer may remove anyone's report, and the author their own.
	astrid.store:Remove("r:vexara/olaf", "Astrid", astrid.env.time())
	sim:Run(15)
	for _, client in ipairs(c) do
		T.ok(not client.store:IsListed("vexara"), client.name .. " accepted the officer's removal")
	end
	olaf.store:Remove("r:grimtusk/olaf", "Olaf", olaf.env.time())
	sim:Run(15)
	T.ok(sim:Converged(), "everyone agrees again once the author removes it")
end)

T.test("sync: guild reports need an officer; unknown rank is deferred, not refused", function()
	local sim = Sim.New(ns, 5)
	local c = guild(sim, NAMES, nil, { Astrid = { officer = true } })
	local olaf, kari, astrid = c[1], c[2], c[5]
	sim:Run(40)
	olaf.store:Report("g", "Hostile Takeover", "I say so", "Olaf", nil, olaf.env.time())
	sim:Run(15)
	T.ok(not kari.store:IsGuildListed("Hostile Takeover"), "a member cannot list a guild")

	kari.rosterReady = false -- roster not loaded yet on Kari's client
	astrid.store:Report("g", "Red Ledger", "War", "Astrid", nil, astrid.env.time())
	sim:Run(10)
	T.ok(c[3].store:IsGuildListed("Red Ledger"), "others accept the officer's guild report")
	T.ok(not kari.store:IsGuildListed("Red Ledger"), "Kari waits for the roster")
	kari.rosterReady = true
	sim:Run(5)
	T.ok(kari.store:IsGuildListed("Red Ledger"), "and applies it once the roster is known")
end)

T.test("sync: a member in a raid catches up, and their own edit survives the lockdown", function()
	local sim = Sim.New(ns, 6)
	local c = guild(sim, NAMES)
	local per = c[3]
	sim:Run(40)
	per.locked = true
	sim:ResetCounters()
	for i = 1, 5 do
		c[1].store:Report("r", enemyName(i), "added during the raid", "Olaf", nil, c[1].env.time())
		sim:Run(20)
	end
	c[1].store:Remove("r:" .. enemyName(1):lower() .. "/olaf", "Olaf", c[1].env.time())
	per.store:Report("r", "Raidganker", "Killed me at the entrance", "Per", nil, per.env.time())
	sim:Run(200)
	T.eq(per.sent, 0, "nothing leaves a locked client")
	T.ok(not c[1].store:IsListed("raidganker"))
	T.ok(per.store:IsDirty("r:raidganker/per"), "the edit is kept as unsent")

	per.locked = false
	sim:ResetCounters()
	local took = T.ok(sim:RunUntilConverged(90), "converges after the raid")
	T.ok(took <= 45, "took " .. took)
	T.ok(c[1].store:IsListed("raidganker"), "the raider's own edit arrived")
	T.eq(select(1, per.store:Counts()), 5)
	T.ok(sim.frames.total <= 14, "frames: " .. sim.frames.total)
end)

T.test("sync: an unsent edit survives logging out while locked", function()
	local sim = Sim.New(ns, 7)
	local c = guild(sim, NAMES)
	local per = c[3]
	sim:Run(40)
	per.locked = true
	per.store:Report("r", "Raidganker", "Killed me", "Per", nil, per.env.time())
	sim:Run(5)
	sim:Logout(per)
	sim:Run(600)
	per.locked = false
	sim:Login(per)
	sim:Run(10)
	T.ok(c[1].store:IsListed("raidganker"), "delivered at next login")
	T.ok(sim:Converged())
end)

T.test("sync: thirty raiders unlocking together cost about as much as one", function()
	local sim = Sim.New(ns, 8)
	local now = sim:Time()
	local data = seedData(40, now)
	local names = {}
	for i = 1, 40 do names[i] = "Member" .. string.char(64 + math.ceil(i / 26)) .. string.char(96 + (i - 1) % 26 + 1) end
	local c = guild(sim, names, data)
	sim:Run(60)
	for i = 1, 30 do c[i].locked = true end
	for i = 1, 5 do
		c[31].store:Report("r", "Late" .. enemyName(i), "added mid-raid", names[31], nil, c[31].env.time())
		sim:Run(30)
	end
	sim:Run(400)
	for i = 1, 30 do c[i].locked = false end
	sim:ResetCounters()
	local took = T.ok(sim:RunUntilConverged(120), "all forty agree")
	T.ok(took <= 45, "took " .. took)
	sim:Run(60)
	T.ok(sim.frames.H <= 4, "hellos do not scale with the raid size: " .. sim.frames.H)
	T.ok(sim.frames.total <= 20, "total frames: " .. sim.frames.total)
	T.eq(sim.throttled, 0)
end)

T.test("sync: two halves of a guild with different additions merge both ways", function()
	local sim = Sim.New(ns, 9)
	local now = sim:Time()
	local a, b = seedData(20, now), seedData(20, now)
	local sa, sb = Store.New(a, now), Store.New(b, now)
	for i = 1, 6 do sa:Report("r", "OnlyA" .. enemyName(i), "left half", "Olaf", nil, now + i) end
	for i = 1, 4 do sb:Report("r", "OnlyB" .. enemyName(i), "right half", "Kari", nil, now + i) end
	sb:Remove("r:" .. enemyName(4):lower() .. "/olaf", "Olaf", now + 50)
	a.dirty, b.dirty = {}, {}
	local c = {}
	for i, name in ipairs(NAMES) do
		c[i] = sim:AddClient(name, { data = Sim.Clone(i <= 3 and a or b) })
	end
	local took = T.ok(sim:RunUntilConverged(180), "converges")
	T.ok(took <= 90, "took " .. took)
	T.eq(select(1, c[1].store:Counts()), 20 - 1 + 6 + 4)
	T.eq(sim.throttled, 0)
end)

T.test("sync: a member returning after 200 days cannot resurrect a removed entry", function()
	local sim = Sim.New(ns, 10)
	local now = sim:Time()
	local base = seedData(10, now)
	local returner = Sim.Clone(base) -- still holds everything, including the victim
	local victim = "r:" .. enemyName(4):lower() .. "/olaf"
	local s = Store.New(base, now)
	s:Remove(victim, "Olaf", now + 10)
	base.dirty = {}

	sim.epoch = sim.epoch + 200 * DAY
	local c = guild(sim, { "Olaf", "Kari", "Per" }, base)
	local fresh = sim:AddClient("Newbie") -- never saw the removal
	sim:Run(90)
	T.eq(c[1].store:Get(victim), nil, "the old removal is buried, not synced")
	T.ok(c[1].store:Grave(victim))

	local z = sim:AddClient("Zed", { data = returner })
	T.ok(z.store:IsListed(enemyName(4):lower()), "the returner still lists the victim")
	local took = T.ok(sim:RunUntilConverged(180), "converges")
	T.ok(took <= 90, "took " .. took)
	sim:Run(60)
	for _, client in ipairs(sim.clients) do
		T.ok(not client.store:IsListed(enemyName(4):lower()), client.name .. " does not list the removed player")
	end
	T.ok(fresh.store:Grave(victim), "the newcomer learned the removal")
	T.eq(select(1, z.store:Counts()), 9)
end)

T.test("sync: converges despite 20% message loss", function()
	local sim = Sim.New(ns, 11, { loss = 0.2 })
	local now = sim:Time()
	local c = guild(sim, NAMES, seedData(30, now))
	sim:Run(40)
	for i = 1, 10 do
		local who = c[i % #c + 1]
		who.store:Report("r", "Lossy" .. enemyName(i), "over a bad link", who.name, nil, who.env.time())
		sim:Run(3)
	end
	local took = T.ok(sim:RunUntilConverged(2400), "eventually consistent")
	T.ok(took <= 1500, "took " .. took)
	T.eq(select(1, c[1].store:Counts()), 40)
end)

T.test("sync: clock skew between clients does not lose edits", function()
	local sim = Sim.New(ns, 12)
	local c = guild(sim, NAMES, nil, { Kari = { skew = 2 }, Per = { skew = -2 }, Astrid = { officer = true, skew = -2 } })
	sim:Run(40)
	c[2].store:Report("r", "Grimtusk", "from a fast clock", "Kari", nil, c[2].env.time())
	sim:Run(5)
	-- the officer, on a slow clock, removes it one second later by their watch
	c[5].store:Remove("r:grimtusk/kari", "Astrid", c[5].env.time())
	sim:Run(10)
	T.ok(sim:Converged())
	for _, client in ipairs(c) do
		T.ok(not client.store:IsListed("grimtusk"), client.name .. ": the removal won despite the slower clock")
	end
end)

T.test("sync: hostile and broken frames are ignored", function()
	local sim = Sim.New(ns, 13)
	local c = guild(sim, NAMES)
	sim:Run(40)
	local future = Codec.Seal({ k = "r", name = "Forever", author = "Mallory", mby = "Mallory",
		ts = sim:Time() + 10 * DAY, at = sim:Time(), reason = "unremovable" })
	local b = Codec.Bucket(future.id)
	sim:Inject("Mallory", (Codec.EncodeUpdate(b, 1, 1, { future.wire })))
	local P = ns.Util.Enc(Codec.PROTO)
	sim:Inject("Mallory", "U" .. P)
	sim:Inject("Mallory", "H" .. P .. string.rep("~", 202))
	sim:Inject("Mallory", string.rep("\255", 255))
	sim:Inject("Mallory", "")
	sim:Inject("Mallory", "U" .. ns.Util.Enc(Codec.PROTO + 1) .. "zzzzzzzzzzzzzzz")
	sim:Run(10)
	for _, client in ipairs(c) do
		T.ok(not client.store:IsListed("forever"), client.name .. " refused the future-dated entry")
		T.eq(client.store:Count(), 0)
	end
	T.ok(c[1].sync.newerSeen, "a newer protocol version is noticed")
end)

T.test("sync: twenty installs over five minutes are all served", function()
	local sim = Sim.New(ns, 14)
	local now = sim:Time()
	guild(sim, { "Olaf", "Kari", "Per", "Ingrid", "Astrid" }, seedData(60, now))
	sim:Run(60)
	sim:ResetCounters()
	for i = 1, 20 do
		sim:AddClient("Fresh" .. string.char(96 + i))
		sim:Run(15)
	end
	local took = T.ok(sim:RunUntilConverged(240), "everyone converges")
	T.ok(took <= 120, "took " .. took .. " after the last login")
	T.eq(sim.throttled, 0)
	for _, client in ipairs(sim.clients) do
		T.eq(select(1, client.store:Counts()), 60, client.name)
	end
end)

T.test("sync: a 1000-entry list reaches a fresh install", function()
	local sim = Sim.New(ns, 15)
	local now = sim:Time()
	guild(sim, { "Olaf", "Kari", "Per", "Ingrid", "Astrid" }, seedData(1000, now))
	sim:Run(60)
	sim:ResetCounters()
	local fresh = sim:AddClient("Newbie")
	local took = T.ok(sim:RunUntilConverged(1800), "converges")
	T.eq(select(1, fresh.store:Counts()), 1000)
	T.eq(sim.throttled, 0)
	io.write(string.format("        1000 entries: %d s, %d update frames, largest frame %d bytes\n", took, sim.frames.U,
		sim.maxFrame))
	T.ok(took <= 240, "took " .. took)
	T.ok(sim.frames.U <= 700, "update frames: " .. sim.frames.U)
	T.ok(sim.frames.H <= 3, "hellos: " .. sim.frames.H)
end)

T.test("sync: PROTO 4 member BG kills and duel records converge across the guild", function()
	local sim = Sim.New(ns, 16)
	local c = guild(sim, NAMES)
	sim:Run(40)
	c[1].store:SetMember("Olaf", {
		kills = 12, deaths = 4, best = 5, points = 40, ach = 2 ^ 31 + 2 ^ 39,
		bgKills = 38, bgDeaths = 11, duelWins = 9, duelLosses = 2,
	}, c[1].env.time())
	sim:Run(15)
	T.ok(sim:Converged(), "PROTO 4 member totals converged")
	for _, client in ipairs(c) do
		local m = T.ok(client.store:Member("olaf"), client.name .. " holds Olaf's member record")
		T.eq(m.kills, 12)
		T.eq(m.bgKills, 38)
		T.eq(m.bgDeaths, 11)
		T.eq(m.duelWins, 9)
		T.eq(m.duelLosses, 2)
	end
end)
