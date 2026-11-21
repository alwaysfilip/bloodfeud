local T = ...
local ns = T.load()
local Util, Codec = ns.Util, ns.Codec

local NOW = 1795252375

local function report(over)
	local rec = { k = "r", name = "Grimtusk", author = "Olaf", mby = "Olaf", ts = NOW, at = NOW - 50,
		reason = "Ganking lowbies in STV" }
	for k, v in pairs(over or {}) do rec[k] = v end
	return Codec.Seal(rec)
end

T.test("record: player report round trip", function()
	local rec = report()
	T.eq(rec.id, "r:grimtusk/olaf")
	local back = T.ok(Codec.DecodeRecord(rec.wire), "decodes")
	T.eq(back.id, rec.id)
	T.eq(back.name, "Grimtusk")
	T.eq(back.author, "Olaf")
	T.eq(back.mby, "Olaf")
	T.eq(back.ts, NOW)
	T.eq(back.at, NOW - 50)
	T.eq(back.reason, "Ganking lowbies in STV")
	T.eq(back.hash, rec.hash)
	T.eq(Codec.EncodeRecord(back), rec.wire)
end)

T.test("record: officer edit keeps author, carries modifier", function()
	local rec = report({ mby = "Astrid" })
	local back = T.ok(Codec.DecodeRecord(rec.wire))
	T.eq(back.author, "Olaf")
	T.eq(back.mby, "Astrid")
	T.eq(back.id, "r:grimtusk/olaf")
end)

T.test("record: tombstone, guild report and facts round trip", function()
	local tomb = Codec.Seal({ k = "r", name = "Grimtusk", author = "Olaf", mby = "Astrid", ts = NOW, del = true })
	local back = T.ok(Codec.DecodeRecord(tomb.wire))
	T.ok(back.del)
	T.eq(back.id, "r:grimtusk/olaf")
	T.eq(back.reason, nil)

	local guild = Codec.Seal({ k = "g", name = "Hostile Takeover", author = "Astrid", mby = "Astrid", ts = NOW, at = NOW,
		reason = "War declared" })
	back = T.ok(Codec.DecodeRecord(guild.wire))
	T.eq(back.id, "g:hostile takeover/astrid")
	T.eq(back.name, "Hostile Takeover")

	local facts = Codec.Seal({ k = "f", key = "grimtusk", mby = "Kari", ts = NOW, guid = "Player-1234-0ABCDEF0",
		cur = "Grimtusk", class = 4, race = 2, level = 60, guild = "Hostile Takeover" })
	back = T.ok(Codec.DecodeRecord(facts.wire))
	T.eq(back.id, "f:grimtusk")
	T.eq(back.guid, "Player-1234-0ABCDEF0")
	T.eq(back.class, 4)
	T.eq(back.level, 60)
	T.eq(back.guild, "Hostile Takeover")

	local sparse = Codec.Seal({ k = "f", key = "grimtusk", mby = "Kari", ts = NOW, level = 12 })
	back = T.ok(Codec.DecodeRecord(sparse.wire))
	T.eq(back.guid, nil)
	T.eq(back.guild, nil)
	T.eq(back.level, 12)
end)

T.test("record: separators and percent in free text survive", function()
	local rec = report({ reason = "50% ~ dead ^ twice" })
	local back = T.ok(Codec.DecodeRecord(rec.wire))
	T.eq(back.reason, "50% ~ dead ^ twice")
	T.ok(not rec.wire:sub(2):find("^", 1, true), "no raw record separator inside a record")
end)

T.test("record: malformed and non-canonical input is rejected", function()
	local wire = report().wire
	T.eq(Codec.DecodeRecord(""), nil)
	T.eq(Codec.DecodeRecord("x" .. wire:sub(2)), nil)
	T.eq(Codec.DecodeRecord(wire .. "~extra"), nil)
	T.eq(Codec.DecodeRecord(wire:gsub("Olaf", "", 1)), nil) -- empty author
	-- leading zero on the timestamp: same value, different spelling
	local ts = Util.Enc(NOW)
	T.eq(Codec.DecodeRecord((wire:gsub("~" .. ts .. "~", "~0" .. ts .. "~", 1))), nil)
	-- modifier spelled out although it equals the author
	local tomb = Codec.Seal({ k = "r", name = "Grimtusk", author = "Olaf", mby = "Olaf", ts = NOW, del = true })
	T.eq(Codec.DecodeRecord(tomb.wire .. "Olaf"), nil)
	-- dirty text is refused, not rewritten
	T.eq(Codec.DecodeRecord((wire:gsub("Ganking", "Gan%%7Cking", 1))), nil)
	T.eq(Codec.DecodeRecord(string.rep("r", 300)), nil)
end)

T.test("record: worst-case sizes still fit one frame", function()
	local name = string.rep("é", 12) -- 24 bytes: longest legal Cyrillic/Latin name
	local reason = Codec.FitReason("r", name, name, "Ж" .. name:sub(3), string.rep("~", 200))
	local rec = Codec.Seal({ k = "r", name = name, author = name, mby = "Ж" .. name:sub(3), ts = 4294967295,
		at = 4294967295, reason = reason })
	T.ok(#rec.wire <= Codec.MAX_RECORD, "report fits: " .. #rec.wire)
	T.ok(Codec.DecodeRecord(rec.wire), "and decodes")
	T.ok(#reason > 0, "some reason is left")

	local guild = string.rep("W", 24)
	reason = Codec.FitReason("g", guild, name, name, string.rep("x", 200))
	T.eq(#reason, Codec.MAX_REASON)
	local g = Codec.Seal({ k = "g", name = guild, author = name, mby = name, ts = NOW, at = NOW, reason = reason })
	T.ok(#g.wire <= Codec.MAX_RECORD, "guild report fits: " .. #g.wire)

	local facts = Codec.Seal({ k = "f", key = Util.Fold(name), mby = name, ts = 4294967295,
		guid = "Player-5827-0123ABCD", cur = name, class = 13, race = 99, level = 60, guild = guild })
	T.ok(#facts.wire <= Codec.MAX_RECORD, "facts fit: " .. #facts.wire)

	-- Absurdly long names: the record sheds fields rather than overflow.
	local long = string.rep("é", 32)
	local huge = Codec.Seal({ k = "f", key = Util.Fold(long), mby = long, ts = 4294967295,
		guid = "Player-5827-0123ABCD", cur = long, class = 13, race = 99, level = 60, guild = string.rep("W", 72) })
	T.ok(#huge.wire <= Codec.MAX_RECORD, "oversized facts trimmed: " .. #huge.wire)
	T.eq(huge.guild, nil)
	T.ok(Codec.DecodeRecord(huge.wire), "and still decode")
	reason = Codec.FitReason("r", long, long, long, string.rep("x", 200))
	local big = Codec.Seal({ k = "r", name = long, author = long, mby = long, ts = 4294967295, at = 4294967295,
		reason = reason })
	T.ok(#big.wire <= Codec.MAX_RECORD, "report with maximal names fits: " .. #big.wire)
end)

T.test("hello: fixed length, round trip, version gate", function()
	local digests = {}
	for b = 0, 63 do digests[b] = (b * 4099 + 7) % Codec.DIGEST_MOD end
	local text = Codec.EncodeHello(123, digests, 0)
	T.eq(#text, 204)
	T.ok(#text <= Codec.MAX_FRAME)
	local h = T.ok(Codec.DecodeHello(text))
	T.eq(h.count, 123)
	T.eq(h.root, (Codec.Root(digests)))
	for b = 0, 63 do T.eq(h.digests[b], digests[b]) end
	T.eq(Codec.DecodeHello(text:sub(1, -2)), nil)
	local newer = Codec.DecodeHello("H" .. ns.Util.Enc(Codec.PROTO + 1) .. text:sub(3))
	T.eq(newer.proto, Codec.PROTO + 1)
	T.eq(newer.digests, nil)
end)

T.test("update: packs what fits, keeps to one bucket", function()
	local wires, bucket = {}, nil
	local i = 0
	while #wires < 8 do
		i = i + 1
		local rec = report({ name = "Enemy" .. string.char(65 + i % 26) .. string.char(97 + math.floor(i / 26)) })
		bucket = bucket or Codec.Bucket(rec.id)
		if Codec.Bucket(rec.id) == bucket then wires[#wires + 1] = rec.wire end
	end
	local text, taken = Codec.EncodeUpdate(bucket, 777, 4242, wires)
	T.ok(#text <= Codec.MAX_FRAME, "frame size " .. #text)
	T.ok(taken >= 3 and taken < 8, "took " .. taken)
	local u = T.ok(Codec.DecodeUpdate(text))
	T.eq(u.bucket, bucket)
	T.eq(u.digest, 777)
	T.eq(u.root, 4242)
	T.eq(#u.records, taken)
	T.eq(u.bad, 0)

	-- a record smuggled into the wrong bucket is dropped
	local other = (bucket + 1) % Codec.BUCKETS
	u = T.ok(Codec.DecodeUpdate((Codec.EncodeUpdate(other, 1, 1, { wires[1] }))))
	T.eq(#u.records, 0)
	T.eq(u.bad, 1)

	-- header only
	u = T.ok(Codec.DecodeUpdate(Codec.UpdateHeader(bucket, 5, 6)))
	T.eq(#u.records, 0)
end)

T.test("sighting: round trip and validation", function()
	local text = Codec.EncodeSighting({ key = "grimtusk", name = "Grimtusk", map = 1434, x = 452, y = 621, t = NOW })
	local s = T.ok(Codec.DecodeSighting(text))
	T.eq(s.key, "grimtusk")
	T.eq(s.map, 1434)
	T.eq(s.x, 452)
	T.eq(s.t, NOW)
	T.eq(Codec.DecodeSighting((text:gsub("grimtusk", "Grimtusk", 1))), nil) -- key must be folded
	local bare = T.ok(Codec.DecodeSighting(Codec.EncodeSighting({ key = "grimtusk", t = NOW })))
	T.eq(bare.map, nil)
end)

T.test("fuzz: garbage never raises", function()
	local seed = 12345
	local function rnd(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n
	end
	local base = { report().wire, Codec.EncodeHello(1, {}, 0), Codec.UpdateHeader(3, 9, 77) .. report().wire }
	for _ = 1, 4000 do
		local s = base[rnd(#base) + 1]
		local bytes = { s:byte(1, -1) }
		for _ = 1, rnd(6) + 1 do
			bytes[rnd(#bytes) + 1] = rnd(256)
		end
		if rnd(4) == 0 then bytes[#bytes] = nil end
		local text = string.char(unpack(bytes))
		Codec.DecodeRecord(text)
		Codec.DecodeHello(text)
		Codec.DecodeUpdate(text)
		Codec.DecodeSighting(text)
	end
end)

T.test("record: score round trip and validation", function()
	local rec = Codec.Seal({ k = "c", key = "grimtusk-bloodaxe", author = "Olaf-Stormborn", ts = 1795252375,
		kills = 3, deaths = 12 })
	T.eq(rec.id, "c:grimtusk-bloodaxe/olaf-stormborn")
	T.eq(rec.mby, "Olaf-Stormborn")
	local back = T.ok(Codec.DecodeRecord(rec.wire))
	T.eq(back.kills, 3)
	T.eq(back.deaths, 12)
	T.eq(back.id, rec.id)
	T.eq(back.hash, rec.hash)
	local zero = Codec.Seal({ k = "c", key = "a", author = "B", ts = 5, kills = 0, deaths = 0 })
	T.ok(Codec.DecodeRecord(zero.wire), "zero scores parse")
	T.eq(Codec.DecodeRecord(rec.wire .. "~1"), nil, "extra field")
	T.eq(Codec.DecodeRecord("cGrimtusk~Olaf~1~1~1"), nil, "key must be folded")
	T.eq(Codec.DecodeRecord("cgrimtusk~Olaf~1~00~1"), nil, "non-canonical number")
	T.eq(Codec.DecodeRecord("cgrimtusk~Olaf~1~zzzzzz~1"), nil, "beyond the maximum")
end)

T.test("presence: round trip, forward compatible, garbage refused", function()
	local p = T.ok(Codec.DecodePresence(Codec.EncodePresence("v0.3.1", 3)))
	T.eq(p.version, "v0.3.1")
	T.eq(p.proto, 3)
	T.ok(not p.ask)
	T.ok(Codec.DecodePresence(Codec.EncodePresence("v0.3.1", 3, true)).ask)
	T.eq(Codec.DecodePresence(Codec.EncodePresence("", 7)).version, nil, "an unknown version is fine")
	T.eq(Codec.DecodePresence(Codec.EncodePresence("v1", 9) .. "~more~fields").proto, 9, "later fields are ignored")
	T.eq(Codec.DecodePresence("P2x~3~"), nil, "another presence format")
	T.eq(Codec.DecodePresence("P1v1"), nil)
	T.eq(Codec.DecodePresence("P1v1~!!~"), nil)
	T.eq(Codec.DecodePresence("P1" .. string.rep("v", 40) .. "~3~"), nil, "version too long")
	T.eq(Codec.DecodePresence(nil), nil)
	T.eq(Codec.DecodeSighting(Codec.EncodePresence("v0.3.1", 3)), nil, "older clients read it as no sighting")
end)
