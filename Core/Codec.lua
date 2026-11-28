-- Wire format. Every frame is one self-contained addon message of at most
-- 255 bytes, so a lost or locked-out frame never invalidates another one.
--
-- Records (the canonical text is also what gets hashed):
--   r  name ~ author ~ ts ~ mby ~ at ~ reason     player report
--   R  name ~ author ~ ts ~ mby                   player report, removed
--   g  name ~ author ~ ts ~ mby ~ at ~ reason     guild report
--   G  name ~ author ~ ts ~ mby                   guild report, removed
--   f  key ~ ts ~ mby ~ guid ~ cur ~ class ~ race ~ level ~ guild
--                                                 facts about a listed player
--   c  key ~ author ~ ts ~ kills ~ deaths          author's score against a
--                                                 listed player
--   m  author ~ ts ~ kills ~ deaths ~ best ~ points ~ achievements ~ bgKills ~ bgDeaths ~ duelWins ~ duelLosses
--                                                 a guildmate's own totals
--   t  n ~ ts ~ mby ~ kills ~ title               rank tier n (officers)
--   b  name ~ author ~ ts ~ mby ~ at ~ scope ~ points ~ gold ~ reward
--                                                 bounty on a player or guild
--   B  name ~ author ~ ts ~ mby ~ scope           bounty, removed
--   k  scope ~ target ~ poster ~ author ~ ts ~ count
--                                                 author's claims on a bounty
--   d  scope ~ target ~ poster ~ role ~ author ~ ts ~ state
--                                                 a mark on the gold debt of a
--                                                 won bounty (see below)
-- `mby` (last modifier) is left empty when it equals the author. A bounty's
-- scope is "p" (player) or "g" (guild).
--
-- Debt marks, by role: "s" the poster says the gold is sent (state "s", or
-- "n" for no longer); "w" the winner says it arrived ("r"), did not ("x"), or
-- takes that back ("n"); "o" an officer settles the matter ("o", or "n").
--
-- Frames:
--   H <proto> <count:3> <root:6> <flags:1> <64 bucket digests, 3 chars each>
--   U <proto> <bucket:1> <digest:3> <root:6> record ^ record ...
--   S <proto> key ~ name ~ map ~ x ~ y ~ time     (sighting, second prefix)
--   P 1 version ~ proto ~ ask                     (presence, second prefix)
local _, ns = ...

local Util = ns.Util
local Enc, Dec, Hash, Fold = Util.Enc, Util.Dec, Util.Hash, Util.Fold
local byte, char, sub, format, gsub = string.byte, string.char, string.sub, string.format, string.gsub
local concat = table.concat

local Codec = {}
ns.Codec = Codec

Codec.PROTO = 4 -- 2: totals/bounties (0.2.0); 3: gold/debts (0.3.0); 4: BG kills & duels (0.6.0)
Codec.BUCKETS = 64
Codec.DIGEST_MOD = 262144 -- 18 bits = 3 base-64 digits
Codec.MAX_FRAME = 255
Codec.MAX_NAME = 64 -- bytes; "First-Surname", possibly in a two-byte script
Codec.MAX_GUILD = 72
Codec.MAX_REASON = 100
Codec.MAX_GUID = 40
Codec.MAX_SCORE = 999999
Codec.MAX_TITLE = 32
Codec.MAX_REWARD = 40
Codec.MAX_POINTS = 100 -- per bounty claim
Codec.MAX_GOLD = 999999 -- whole gold pieces promised to the first kill
Codec.MAX_VERSION = 24
Codec.MAX_TIERS = 12
Codec.MAX_ACHIEVEMENTS = 48 -- bits in one 8-digit number
Codec.UPDATE_HEADER = 12
Codec.MAX_RECORD = 243 -- MAX_FRAME minus the update header

local PROTO_CHAR = Enc(Codec.PROTO)
local HELLO_LEN = 1 + 1 + 3 + 6 + 1 + Codec.BUCKETS * 3

---------------------------------------------------------------------------
-- Field escaping: "~" separates fields, "^" separates records
---------------------------------------------------------------------------

local function escOne(c)
	return format("%%%02X", byte(c))
end

local function esc(s)
	return (gsub(s, "[%%~%^%c]", escOne))
end

local function unescOne(hex)
	return char(tonumber(hex, 16))
end

local function unesc(s)
	return (gsub(s, "%%(%x%x)", unescOne))
end

local function split(s, sep)
	local out, n, from = {}, 0, 1
	while true do
		local at = s:find(sep, from, true)
		n = n + 1
		if not at then
			out[n] = sub(s, from)
			return out, n
		end
		out[n] = sub(s, from, at - 1)
		from = at + 1
	end
end

local function num(s)
	if s == "" then return nil end
	return Dec(s)
end

local function encNum(n)
	if n == nil then return "" end
	return Enc(n)
end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

--- Identity of a record: one report per (subject, author), one facts record
--- per player.
function Codec.Id(kind, key, akey)
	if kind == "f" then return "f:" .. key end
	if kind == "m" then return "m:" .. key end
	if kind == "t" then return "t:" .. key end
	return kind .. ":" .. key .. "/" .. akey
end

--- A bounty's id: scope ("p" or "g"), target key and poster key.
function Codec.BountyId(scope, key, pkey)
	return "b:" .. scope .. key .. "/" .. pkey
end

--- The id of `akey`'s claims on a bounty.
function Codec.ClaimId(scope, key, pkey, akey)
	return "k:" .. scope .. key .. "/" .. pkey .. "/" .. akey
end

--- The id of a debt mark. The winner's mark is per author, so that only the
--- real winner's word can be picked out; the other two have one writer or
--- one office.
function Codec.MarkId(scope, key, pkey, role, akey)
	local id = "d:" .. scope .. key .. "/" .. pkey .. "/" .. role
	if role == "w" then id = id .. "/" .. akey end
	return id
end

local MARK_STATES = { s = { s = true, n = true }, w = { r = true, x = true, n = true }, o = { o = true, n = true } }

--- Fill in the derived fields (keys, id) of a record table and return it.
function Codec.Normalize(rec)
	local k = rec.k
	if k == "f" then
		rec.id = Codec.Id("f", rec.key)
	elseif k == "c" then
		rec.akey = Fold(rec.author)
		rec.mby = rec.author -- only the author ever writes their own score
		rec.id = Codec.Id("c", rec.key, rec.akey)
	elseif k == "m" then
		rec.akey = Fold(rec.author)
		rec.key = rec.akey
		rec.mby = rec.author
		rec.id = Codec.Id("m", rec.akey)
	elseif k == "t" then
		rec.key = tostring(rec.n)
		rec.id = Codec.Id("t", rec.key)
	elseif k == "b" then
		rec.key = Fold(rec.name)
		rec.akey = Fold(rec.author)
		rec.id = Codec.BountyId(rec.scope, rec.key, rec.akey)
	elseif k == "k" then
		rec.pkey = Fold(rec.poster)
		rec.akey = Fold(rec.author)
		rec.mby = rec.author
		rec.bid = Codec.BountyId(rec.scope, rec.key, rec.pkey)
		rec.id = Codec.ClaimId(rec.scope, rec.key, rec.pkey, rec.akey)
	elseif k == "d" then
		rec.pkey = Fold(rec.poster)
		rec.akey = Fold(rec.author)
		rec.mby = rec.author
		rec.bid = Codec.BountyId(rec.scope, rec.key, rec.pkey)
		rec.id = Codec.MarkId(rec.scope, rec.key, rec.pkey, rec.role, rec.akey)
	else
		rec.key = Fold(rec.name)
		rec.akey = Fold(rec.author)
		rec.id = Codec.Id(rec.k, rec.key, rec.akey)
	end
	return rec
end

--- Canonical text of a record. Deterministic: equal records give equal text
--- on every client, which is what makes the digests comparable.
function Codec.EncodeRecord(rec)
	local k = rec.k
	if k == "f" then
		return concat({
			"f" .. esc(rec.key), Enc(rec.ts), esc(rec.mby), esc(rec.guid or ""), esc(rec.cur or ""),
			encNum(rec.class), encNum(rec.race), encNum(rec.level), esc(rec.guild or ""),
		}, "~")
	end
	if k == "c" then
		return concat({ "c" .. esc(rec.key), esc(rec.author), Enc(rec.ts), Enc(rec.kills), Enc(rec.deaths) }, "~")
	end
	if k == "m" then
		return concat({ "m" .. esc(rec.author), Enc(rec.ts), Enc(rec.kills or 0), Enc(rec.deaths or 0), Enc(rec.best or 0),
			Enc(rec.points or 0), Enc(rec.ach or 0), Enc(rec.bgKills or 0), Enc(rec.bgDeaths or 0),
			Enc(rec.duelWins or 0), Enc(rec.duelLosses or 0) }, "~")
	end
	if k == "t" then
		return concat({ "t" .. Enc(rec.n), Enc(rec.ts), esc(rec.mby), Enc(rec.kills), esc(rec.title) }, "~")
	end
	if k == "k" then
		return concat({ "k" .. rec.scope, esc(rec.key), esc(rec.poster), esc(rec.author), Enc(rec.ts), Enc(rec.count) },
			"~")
	end
	if k == "d" then
		return concat({ "d" .. rec.scope, esc(rec.key), esc(rec.poster), rec.role, esc(rec.author), Enc(rec.ts),
			rec.state }, "~")
	end
	local mby = rec.mby == rec.author and "" or esc(rec.mby)
	if k == "b" then
		if rec.del then
			return concat({ "B" .. esc(rec.name), esc(rec.author), Enc(rec.ts), mby, rec.scope }, "~")
		end
		return concat({ "b" .. esc(rec.name), esc(rec.author), Enc(rec.ts), mby, Enc(rec.at), rec.scope,
			Enc(rec.points), Enc(rec.gold or 0), esc(rec.reward or "") }, "~")
	end
	if rec.del then
		return concat({ (k == "r" and "R" or "G") .. esc(rec.name), esc(rec.author), Enc(rec.ts), mby }, "~")
	end
	return concat({ k .. esc(rec.name), esc(rec.author), Enc(rec.ts), mby, Enc(rec.at), esc(rec.reason or "") }, "~")
end

local function cleanName(s, max)
	return s ~= "" and Util.IsClean(s, max)
end

-- Accept a parsed record only in its canonical spelling, then derive its
-- keys, id and hash.
local function seal(rec, text)
	if Codec.EncodeRecord(rec) ~= text then return nil end
	Codec.Normalize(rec)
	rec.wire = text
	rec.hash = Hash(text)
	return rec
end

--- Parse one record. Returns nil for anything malformed; text fields must
--- already be clean (see Util.IsClean) and are never rewritten here.
function Codec.DecodeRecord(text)
	if type(text) ~= "string" or #text < 2 or #text > Codec.MAX_RECORD then return nil end
	local kind = sub(text, 1, 1)
	local parts, n = split(sub(text, 2), "~")
	for i = 1, n do parts[i] = unesc(parts[i]) end

	if kind == "f" then
		if n ~= 9 then return nil end
		local rec = {
			k = "f", key = parts[1], ts = Dec(parts[2]), mby = parts[3],
			guid = parts[4] ~= "" and parts[4] or nil, cur = parts[5] ~= "" and parts[5] or nil,
			class = num(parts[6]), race = num(parts[7]), level = num(parts[8]),
			guild = parts[9] ~= "" and parts[9] or nil,
		}
		if not rec.ts or rec.ts <= 0 then return nil end
		if not cleanName(rec.key, Codec.MAX_NAME) or Fold(rec.key) ~= rec.key then return nil end
		if not cleanName(rec.mby, Codec.MAX_NAME) then return nil end
		if rec.guid and not Util.IsClean(rec.guid, Codec.MAX_GUID) then return nil end
		if rec.cur and not Util.IsClean(rec.cur, Codec.MAX_NAME) then return nil end
		if rec.guild and not Util.IsClean(rec.guild, Codec.MAX_GUILD) then return nil end
		if (parts[6] ~= "" and not rec.class) or (parts[7] ~= "" and not rec.race)
			or (parts[8] ~= "" and not rec.level) then
			return nil
		end
		if rec.level and rec.level > 255 then return nil end
		if Codec.EncodeRecord(rec) ~= text then return nil end -- only the canonical spelling
		rec.id = Codec.Id("f", rec.key)
		rec.wire = text
		rec.hash = Hash(text)
		return rec
	end

	if kind == "c" then
		if n ~= 5 then return nil end
		local rec = { k = "c", key = parts[1], author = parts[2], ts = Dec(parts[3]),
			kills = Dec(parts[4]), deaths = Dec(parts[5]) }
		if not rec.ts or rec.ts <= 0 or not rec.kills or not rec.deaths then return nil end
		if rec.kills > Codec.MAX_SCORE or rec.deaths > Codec.MAX_SCORE then return nil end
		if not cleanName(rec.key, Codec.MAX_NAME) or Fold(rec.key) ~= rec.key then return nil end
		if not cleanName(rec.author, Codec.MAX_NAME) then return nil end
		if Codec.EncodeRecord(rec) ~= text then return nil end
		Codec.Normalize(rec)
		rec.wire = text
		rec.hash = Hash(text)
		return rec
	end

	if kind == "m" then
		if n ~= 11 then return nil end
		local rec = { k = "m", author = parts[1], ts = Dec(parts[2]), kills = Dec(parts[3]), deaths = Dec(parts[4]),
			best = Dec(parts[5]), points = Dec(parts[6]), ach = Dec(parts[7]), bgKills = Dec(parts[8]),
			bgDeaths = Dec(parts[9]), duelWins = Dec(parts[10]), duelLosses = Dec(parts[11]) }
		if not rec.ts or rec.ts <= 0 or not rec.kills or not rec.deaths or not rec.best or not rec.points
			or not rec.ach or not rec.bgKills or not rec.bgDeaths or not rec.duelWins or not rec.duelLosses then
			return nil
		end
		if rec.kills > Codec.MAX_SCORE or rec.deaths > Codec.MAX_SCORE or rec.best > Codec.MAX_SCORE
			or rec.points > Codec.MAX_SCORE * 100 or rec.bgKills > Codec.MAX_SCORE or rec.bgDeaths > Codec.MAX_SCORE
			or rec.duelWins > Codec.MAX_SCORE or rec.duelLosses > Codec.MAX_SCORE then
			return nil
		end
		if not cleanName(rec.author, Codec.MAX_NAME) then return nil end
		return seal(rec, text)
	end

	if kind == "t" then
		if n ~= 5 then return nil end
		local rec = { k = "t", n = Dec(parts[1]), ts = Dec(parts[2]), mby = parts[3], kills = Dec(parts[4]),
			title = parts[5] }
		if not rec.n or rec.n < 1 or rec.n > Codec.MAX_TIERS then return nil end
		if not rec.ts or rec.ts <= 0 or not rec.kills or rec.kills > Codec.MAX_SCORE then return nil end
		if not cleanName(rec.mby, Codec.MAX_NAME) or not Util.IsClean(rec.title, Codec.MAX_TITLE) then return nil end
		return seal(rec, text)
	end

	if kind == "k" then
		if n ~= 6 then return nil end
		local rec = { k = "k", scope = parts[1], key = parts[2], poster = parts[3], author = parts[4],
			ts = Dec(parts[5]), count = Dec(parts[6]) }
		if rec.scope ~= "p" and rec.scope ~= "g" then return nil end
		if not rec.ts or rec.ts <= 0 or not rec.count or rec.count < 1 or rec.count > Codec.MAX_SCORE then return nil end
		local keyMax = rec.scope == "g" and Codec.MAX_GUILD or Codec.MAX_NAME
		if not cleanName(rec.key, keyMax) or Fold(rec.key) ~= rec.key then return nil end
		if not cleanName(rec.poster, Codec.MAX_NAME) or not cleanName(rec.author, Codec.MAX_NAME) then return nil end
		return seal(rec, text)
	end

	if kind == "d" then
		if n ~= 7 then return nil end
		local rec = { k = "d", scope = parts[1], key = parts[2], poster = parts[3], role = parts[4], author = parts[5],
			ts = Dec(parts[6]), state = parts[7] }
		if rec.scope ~= "p" and rec.scope ~= "g" then return nil end
		if not rec.ts or rec.ts <= 0 then return nil end
		local states = MARK_STATES[rec.role]
		if not states or not states[rec.state] then return nil end
		local keyMax = rec.scope == "g" and Codec.MAX_GUILD or Codec.MAX_NAME
		if not cleanName(rec.key, keyMax) or Fold(rec.key) ~= rec.key then return nil end
		if not cleanName(rec.poster, Codec.MAX_NAME) or not cleanName(rec.author, Codec.MAX_NAME) then return nil end
		-- "Sent" is the poster's own word and nobody else's.
		if rec.role == "s" and Fold(rec.author) ~= Fold(rec.poster) then return nil end
		return seal(rec, text)
	end

	if kind == "b" or kind == "B" then
		local del = kind == "B"
		if n ~= (del and 5 or 9) then return nil end
		local rec = { k = "b", name = parts[1], author = parts[2], ts = Dec(parts[3]) }
		if del then
			rec.del, rec.scope = true, parts[5]
		else
			rec.at, rec.scope, rec.points, rec.gold, rec.reward = Dec(parts[5]), parts[6], Dec(parts[7]), Dec(parts[8]),
				parts[9]
			if not rec.at or not rec.points or rec.points < 1 or rec.points > Codec.MAX_POINTS then return nil end
			if not rec.gold or rec.gold > Codec.MAX_GOLD then return nil end
			if not Util.IsClean(rec.reward, Codec.MAX_REWARD) then return nil end
		end
		if rec.scope ~= "p" and rec.scope ~= "g" then return nil end
		if not rec.ts or rec.ts <= 0 then return nil end
		local nameMax = rec.scope == "g" and Codec.MAX_GUILD or Codec.MAX_NAME
		if not cleanName(rec.name, nameMax) or not cleanName(rec.author, Codec.MAX_NAME) then return nil end
		if parts[4] == "" then
			rec.mby = rec.author
		else
			if not cleanName(parts[4], Codec.MAX_NAME) or parts[4] == rec.author then return nil end
			rec.mby = parts[4]
		end
		return seal(rec, text)
	end

	local del = kind == "R" or kind == "G"
	local base = (kind == "r" or kind == "R") and "r" or ((kind == "g" or kind == "G") and "g") or nil
	if not base then return nil end
	if n ~= (del and 4 or 6) then return nil end

	local nameMax = base == "g" and Codec.MAX_GUILD or Codec.MAX_NAME
	local rec = { k = base, name = parts[1], author = parts[2], ts = Dec(parts[3]) }
	if not rec.ts or rec.ts <= 0 then return nil end
	if not cleanName(rec.name, nameMax) or not cleanName(rec.author, Codec.MAX_NAME) then return nil end
	if parts[4] == "" then
		rec.mby = rec.author
	else
		if not cleanName(parts[4], Codec.MAX_NAME) or parts[4] == rec.author then return nil end
		rec.mby = parts[4]
	end
	if del then
		rec.del = true
	else
		rec.at = Dec(parts[5])
		rec.reason = parts[6]
		if not rec.at or not Util.IsClean(rec.reason, Codec.MAX_REASON) then return nil end
	end
	if Codec.EncodeRecord(rec) ~= text then return nil end -- only the canonical spelling
	Codec.Normalize(rec)
	rec.wire = text
	rec.hash = Hash(text)
	return rec
end

--- Attach the canonical text and its hash to a locally built record.
function Codec.Seal(rec)
	Codec.Normalize(rec)
	rec.wire = Codec.EncodeRecord(rec)
	if rec.k == "f" and #rec.wire > Codec.MAX_RECORD then
		-- Facts must fit one frame. With extreme name lengths, give up the
		-- least important fields first.
		for _, field in ipairs({ "guild", "cur", "guid" }) do
			rec[field] = nil
			rec.wire = Codec.EncodeRecord(rec)
			if #rec.wire <= Codec.MAX_RECORD then break end
		end
	elseif rec.k == "b" and not rec.del then
		while #rec.wire > Codec.MAX_RECORD and rec.reward ~= "" do
			rec.reward = Util.Clean(Util.Truncate(rec.reward, #rec.reward - 1), Codec.MAX_REWARD)
			rec.wire = Codec.EncodeRecord(rec)
		end
	end
	rec.hash = Hash(rec.wire)
	return rec
end

--- Which of the 64 buckets a record id belongs to.
function Codec.Bucket(id)
	return Hash(id) % Codec.BUCKETS
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

--- Root hash over the transmitted (18-bit) bucket digests.
function Codec.Root(digests)
	local parts = {}
	for b = 0, Codec.BUCKETS - 1 do
		parts[b + 1] = Enc(digests[b] or 0, 3)
	end
	return Hash(concat(parts)), parts
end

--- Hello: "this is the state I hold". digests is 0-indexed, values < 2^18.
function Codec.EncodeHello(count, digests, flags)
	local root, parts = Codec.Root(digests)
	if count > 262143 then count = 262143 end
	return "H" .. PROTO_CHAR .. Enc(count, 3) .. Enc(root, 6) .. Enc(flags or 0, 1) .. concat(parts)
end

function Codec.DecodeHello(text)
	if type(text) ~= "string" or sub(text, 1, 1) ~= "H" then return nil end
	local proto = Dec(sub(text, 2, 2))
	if not proto then return nil end
	if proto ~= Codec.PROTO then return { proto = proto } end
	if #text ~= HELLO_LEN then return nil end
	local h = {
		proto = proto,
		count = Dec(sub(text, 3, 5)),
		root = Dec(sub(text, 6, 11)),
		flags = Dec(sub(text, 12, 12)),
		digests = {},
	}
	if not h.count or not h.root or not h.flags then return nil end
	for b = 0, Codec.BUCKETS - 1 do
		local d = Dec(sub(text, 13 + b * 3, 15 + b * 3))
		if not d then return nil end
		h.digests[b] = d
	end
	return h
end

--- Update header: which bucket the records belong to, the sender's digest
--- for that bucket and the sender's root. Records follow, "^" between them.
function Codec.UpdateHeader(bucket, digest, root)
	return "U" .. PROTO_CHAR .. Enc(bucket, 1) .. Enc(digest % Codec.DIGEST_MOD, 3) .. Enc(root, 6)
end

--- Build one update frame from as many of `wires` (in order) as fit.
--- Returns the frame text and how many records it took.
function Codec.EncodeUpdate(bucket, digest, root, wires)
	local text = Codec.UpdateHeader(bucket, digest, root)
	local taken = 0
	for i = 1, #wires do
		local w = wires[i]
		local extra = #w + (taken > 0 and 1 or 0)
		if #text + extra > Codec.MAX_FRAME then break end
		text = text .. (taken > 0 and "^" or "") .. w
		taken = taken + 1
	end
	return text, taken
end

function Codec.DecodeUpdate(text)
	local head = Codec.UPDATE_HEADER
	if type(text) ~= "string" or sub(text, 1, 1) ~= "U" or #text < head or #text > Codec.MAX_FRAME then return nil end
	local proto = Dec(sub(text, 2, 2))
	if not proto then return nil end
	if proto ~= Codec.PROTO then return { proto = proto } end
	local bucket, digest, root = Dec(sub(text, 3, 3)), Dec(sub(text, 4, 6)), Dec(sub(text, 7, 12))
	if not bucket or not digest or not root or bucket >= Codec.BUCKETS then return nil end
	local u = { proto = proto, bucket = bucket, digest = digest, root = root, records = {}, bad = 0 }
	if #text > head then
		local parts, n = split(sub(text, head + 1), "^")
		for i = 1, n do
			local rec = Codec.DecodeRecord(parts[i])
			-- A record must sit in the bucket the frame is about, or its
			-- digest trailer would be compared against the wrong bucket.
			if rec and Codec.Bucket(rec.id) == bucket then
				u.records[#u.records + 1] = rec
			else
				u.bad = u.bad + 1
			end
		end
	end
	return u
end

--- Sighting: ephemeral, never stored as authoritative state.
function Codec.EncodeSighting(s)
	return "S" .. PROTO_CHAR .. concat({
		esc(s.key), esc(s.name or ""), encNum(s.map), encNum(s.x), encNum(s.y), Enc(s.t),
	}, "~")
end

function Codec.DecodeSighting(text)
	if type(text) ~= "string" or sub(text, 1, 1) ~= "S" or #text > Codec.MAX_FRAME then return nil end
	local proto = Dec(sub(text, 2, 2))
	if proto ~= Codec.PROTO then return nil end
	local parts, n = split(sub(text, 3), "~")
	if n ~= 6 then return nil end
	for i = 1, n do parts[i] = unesc(parts[i]) end
	local s = {
		key = parts[1], name = parts[2] ~= "" and parts[2] or nil,
		map = num(parts[3]), x = num(parts[4]), y = num(parts[5]), t = Dec(parts[6]),
	}
	if not s.t or not cleanName(s.key, Codec.MAX_NAME) or Fold(s.key) ~= s.key then return nil end
	if s.name and not Util.IsClean(s.name, Codec.MAX_NAME) then return nil end
	if (s.x and s.x > 1000) or (s.y and s.y > 1000) then return nil end
	return s
end

--- Presence: "I run Business Meeting, this version", with an optional "and who
--- else does?". It rides on the second prefix and is deliberately not tied
--- to the state protocol: clients on any version can read it, which is how
--- the ones that need to update are found. Fields may be added at the end.
function Codec.EncodePresence(version, proto, ask)
	return "P1" .. esc(version or "") .. "~" .. Enc(proto) .. "~" .. (ask and "?" or "")
end

function Codec.DecodePresence(text)
	if type(text) ~= "string" or sub(text, 1, 2) ~= "P1" or #text > 96 then return nil end
	local parts, n = split(sub(text, 3), "~")
	if n < 2 then return nil end
	local version, proto = unesc(parts[1]), Dec(parts[2])
	if not proto or not Util.IsClean(version, Codec.MAX_VERSION) then return nil end
	return { version = version ~= "" and version or nil, proto = proto, ask = parts[3] == "?" }
end

--- Largest clean reason that still lets the whole record fit in one frame.
function Codec.FitReason(kind, name, author, mby, reason)
	reason = Util.Clean(reason or "", Codec.MAX_REASON)
	local probe = { k = kind, name = name, author = author, mby = mby, ts = 4294967295, at = 4294967295 }
	while true do
		probe.reason = reason
		if #Codec.EncodeRecord(probe) <= Codec.MAX_RECORD or reason == "" then return reason end
		reason = Util.Clean(Util.Truncate(reason, #reason - 1), Codec.MAX_REASON)
	end
end
