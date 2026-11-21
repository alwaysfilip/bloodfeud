-- Pure helpers: UTF-8 handling, name folding, hashing and number encoding.
-- Nothing in this file may touch the WoW API without a guard, so it also runs
-- under plain Lua 5.1 / LuaJIT for the offline tests.
local _, ns = ...

local Util = {}
ns.Util = Util

local byte, char, sub, format = string.byte, string.char, string.sub, string.format
local floor, concat = math.floor, table.concat
local bxor = bit.bxor

---------------------------------------------------------------------------
-- Secret values (Midnight-era restriction, inherited by Forever)
---------------------------------------------------------------------------

local issecretvalue = _G.issecretvalue

--- True when `v` is a secret value that must not be inspected or compared.
function Util.IsSecret(v)
	if issecretvalue then
		return issecretvalue(v) and true or false
	end
	return false
end

---------------------------------------------------------------------------
-- UTF-8
---------------------------------------------------------------------------

-- Length of the valid UTF-8 sequence starting at byte i, or nil when invalid.
local function seqLen(s, i)
	local c = byte(s, i)
	if not c then return nil end
	if c < 0x80 then return 1 end
	if c >= 0xC2 and c <= 0xDF then
		local c2 = byte(s, i + 1)
		if c2 and c2 >= 0x80 and c2 <= 0xBF then return 2 end
	elseif c >= 0xE0 and c <= 0xEF then
		local c2, c3 = byte(s, i + 1, i + 2)
		if c2 and c3 and c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF then return 3 end
	elseif c >= 0xF0 and c <= 0xF4 then
		local c2, c3, c4 = byte(s, i + 1, i + 3)
		if c2 and c3 and c4 and c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF
			and c4 >= 0x80 and c4 <= 0xBF then
			return 4
		end
	end
	return nil
end

--- Cut `s` to at most `maxBytes` without splitting a UTF-8 sequence.
function Util.Truncate(s, maxBytes)
	if #s <= maxBytes then return s end
	local i, last = 1, 0
	while i <= #s do
		local n = seqLen(s, i) or 1
		if i + n - 1 > maxBytes then break end
		last = i + n - 1
		i = i + n
	end
	return sub(s, 1, last)
end

--- Normalise free text for storage and transport: drops invalid UTF-8 and
--- UI escape pipes, turns control characters into spaces, collapses runs of
--- spaces, trims, and caps the byte length.
function Util.Clean(s, maxBytes)
	if type(s) ~= "string" then return "" end
	local out, n, i = {}, 0, 1
	local lastSpace = true -- also trims leading spaces
	while i <= #s do
		local len = seqLen(s, i)
		if not len then
			i = i + 1 -- invalid byte: drop it
		else
			local c = byte(s, i)
			if len == 1 and (c < 32 or c == 127) then c = 32 end
			-- "|" starts colour codes, textures and hyperlinks in WoW text, so
			-- it is dropped outright.
			local pipe = len == 1 and c == 124
			if len == 1 and c == 32 then
				if not lastSpace then
					n = n + 1
					out[n] = " "
					lastSpace = true
				end
			elseif not pipe then
				n = n + 1
				out[n] = sub(s, i, i + len - 1)
				lastSpace = false
			end
			i = i + len
		end
	end
	if lastSpace and n > 0 then
		out[n] = nil -- trailing space
	end
	local res = concat(out)
	if maxBytes and #res > maxBytes then
		res = Util.Truncate(res, maxBytes)
		res = res:gsub(" +$", "")
	end
	return res
end

--- True when `s` is already in the form Clean() would produce. Receivers use
--- this to reject text instead of rewriting it, so every client hashes the
--- exact same bytes.
function Util.IsClean(s, maxBytes)
	return type(s) == "string" and Util.Clean(s, maxBytes) == s
end

local function decode2(s, i)
	local c1, c2 = byte(s, i, i + 1)
	return (c1 - 0xC0) * 64 + (c2 - 0x80)
end

local function encode2(cp)
	return char(0xC0 + floor(cp / 64), 0x80 + cp % 64)
end

-- Lower-case mapping for the scripts WoW allows in character names on EU/US
-- realms: Latin-1, Latin Extended-A and basic Cyrillic. string.lower only
-- handles ASCII, so "Élodie" and "élodie" would otherwise be two keys.
local function lowerCP(cp)
	if cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7 then return cp + 32 end
	if cp >= 0x100 and cp <= 0x17F then
		if cp == 0x130 or cp == 0x131 or cp == 0x138 or cp == 0x149 or cp == 0x17F then return cp end
		if cp == 0x178 then return 0xFF end
		if (cp >= 0x139 and cp <= 0x148) or (cp >= 0x179 and cp <= 0x17E) then
			return cp % 2 == 1 and cp + 1 or cp
		end
		return cp % 2 == 0 and cp + 1 or cp
	end
	if cp >= 0x410 and cp <= 0x42F then return cp + 32 end
	if cp >= 0x400 and cp <= 0x40F then return cp + 80 end
	return cp
end

local function upperCP(cp)
	if cp >= 0xE0 and cp <= 0xFE and cp ~= 0xF7 then return cp - 32 end
	if cp == 0xFF then return 0x178 end
	if cp >= 0x100 and cp <= 0x17F then
		if cp == 0x130 or cp == 0x131 or cp == 0x138 or cp == 0x149 or cp == 0x17F then return cp end
		if (cp >= 0x139 and cp <= 0x148) or (cp >= 0x179 and cp <= 0x17E) then
			return cp % 2 == 0 and cp - 1 or cp
		end
		return cp % 2 == 1 and cp - 1 or cp
	end
	if cp >= 0x430 and cp <= 0x44F then return cp - 32 end
	if cp >= 0x450 and cp <= 0x45F then return cp - 80 end
	return cp
end

local function mapCase(s, asciiFrom, asciiTo, asciiDelta, mapFn, firstOnly)
	local out, n, i = {}, 0, 1
	while i <= #s do
		local len = seqLen(s, i) or 1
		local piece
		if firstOnly and i > 1 then
			piece = sub(s, i)
			len = #s - i + 1
		elseif len == 1 then
			local c = byte(s, i)
			if c >= asciiFrom and c <= asciiTo then c = c + asciiDelta end
			piece = char(c)
		elseif len == 2 then
			piece = encode2(mapFn(decode2(s, i)))
		else
			piece = sub(s, i, i + len - 1)
		end
		n = n + 1
		out[n] = piece
		i = i + len
	end
	return concat(out)
end

--- Case-folded form used as the identity key for player and guild names.
function Util.Fold(s)
	return mapCase(s, 65, 90, 32, lowerCP, false)
end

--- "grimtusk" -> "Grimtusk": the shape the game itself uses for names.
function Util.TitleCase(s)
	return mapCase(Util.Fold(s), 97, 122, -32, upperCP, true)
end

--- "Name-Realm" -> "Name". Forever has no realms, but sender names may still
--- arrive with a suffix.
function Util.ShortName(full)
	if type(full) ~= "string" then return full end
	local dash = full:find("-", 1, true)
	if dash and dash > 1 then return sub(full, 1, dash - 1) end
	return full
end

---------------------------------------------------------------------------
-- Hashing: 32-bit FNV-1a
---------------------------------------------------------------------------

local MOD32 = 4294967296

--- 32-bit FNV-1a. The multiply is split into 16-bit halves because a plain
--- h * 16777619 exceeds the 2^53 range that Lua doubles hold exactly.
function Util.Hash(s)
	local h = 2166136261
	for i = 1, #s do
		local lo = h % 256
		h = h - lo + bxor(lo, byte(s, i))
		h = ((h % 65536) * 16777619 + ((floor(h / 65536) * 16777619) % 65536) * 65536) % MOD32
	end
	return h
end

---------------------------------------------------------------------------
-- Numbers as base-64 text (printable, no separators)
---------------------------------------------------------------------------

local ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
local DIGIT, VALUE = {}, {}
for i = 1, 64 do
	local c = sub(ALPHABET, i, i)
	DIGIT[i - 1] = c
	VALUE[byte(c)] = i - 1
end

--- Encode a non-negative integer, left-padded with "0" to `width` if given.
function Util.Enc(n, width)
	n = floor(n)
	local out = ""
	repeat
		out = DIGIT[n % 64] .. out
		n = floor(n / 64)
	until n == 0
	if width then
		while #out < width do out = "0" .. out end
	end
	return out
end

--- Decode text produced by Enc(); nil when it contains anything else.
function Util.Dec(s)
	if type(s) ~= "string" or s == "" or #s > 8 then return nil end
	local n = 0
	for i = 1, #s do
		local v = VALUE[byte(s, i)]
		if not v then return nil end
		n = n * 64 + v
	end
	return n
end

---------------------------------------------------------------------------
-- Presentation helpers
---------------------------------------------------------------------------

--- Compact relative time such as "2 min ago".
function Util.Ago(seconds, L)
	L = L or ns.L or {}
	if not seconds or seconds < 0 then seconds = 0 end
	if seconds < 60 then return L.AGO_NOW or "just now" end
	if seconds < 3600 then return format(L.AGO_MIN or "%d min ago", floor(seconds / 60)) end
	if seconds < 86400 then return format(L.AGO_HOUR or "%d h ago", floor(seconds / 3600)) end
	return format(L.AGO_DAY or "%d d ago", floor(seconds / 86400))
end

--- Shallow copy.
function Util.Copy(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end
