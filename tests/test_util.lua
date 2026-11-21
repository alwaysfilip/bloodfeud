local T = ...
local ns = T.load()
local Util = ns.Util

T.test("hash: FNV-1a golden vectors", function()
	T.eq(Util.Hash(""), 0x811C9DC5)
	T.eq(Util.Hash("a"), 0xE40C292C)
	T.eq(Util.Hash("foobar"), 0xBF9CF968)
	-- non-ASCII bytes go through the same path
	T.ok(Util.Hash("Élodie") ~= Util.Hash("Elodie"))
	T.ok(Util.Hash("Élodie") >= 0 and Util.Hash("Élodie") < 4294967296)
end)

T.test("enc/dec: round trip and rejection", function()
	for _, n in ipairs({ 0, 1, 63, 64, 4095, 262143, 1795252375, 4294967295 }) do
		T.eq(Util.Dec(Util.Enc(n)), n, "round trip " .. n)
	end
	T.eq(Util.Enc(5, 3), "005")
	T.eq(#Util.Enc(4294967295), 6)
	T.eq(Util.Dec(""), nil)
	T.eq(Util.Dec("a~b"), nil)
	T.eq(Util.Dec("123456789"), nil)
end)

T.test("fold: ASCII, Latin-1, Latin Extended-A, Cyrillic", function()
	T.eq(Util.Fold("Grimtusk"), "grimtusk")
	T.eq(Util.Fold("ÉLODIE"), "élodie")
	T.eq(Util.Fold("Ångström"), "ångström")
	T.eq(Util.Fold("ŽIVA"), "živa")
	T.eq(Util.Fold("ŁUKASZ"), "łukasz")
	T.eq(Util.Fold("ИВАН"), "иван")
	T.eq(Util.Fold("Ÿ"), "ÿ")
	T.eq(Util.Fold("×"), "×") -- multiplication sign is not a letter
	T.eq(Util.Fold(Util.Fold("ÉLODIE")), "élodie") -- idempotent
end)

T.test("titlecase: the shape the game uses for names", function()
	T.eq(Util.TitleCase("grimtusk"), "Grimtusk")
	T.eq(Util.TitleCase("GRIMTUSK"), "Grimtusk")
	T.eq(Util.TitleCase("élodie"), "Élodie")
	T.eq(Util.TitleCase("иван"), "Иван")
	T.eq(Util.Fold(Util.TitleCase("ŽIVA")), "živa")
end)

T.test("clean: control chars, pipes, spaces, invalid UTF-8, caps", function()
	T.eq(Util.Clean("  ganking   lowbies \n in STV  "), "ganking lowbies in STV")
	T.eq(Util.Clean("|cffff0000red|r |Hitem:1|h[x]|h"), "cffff0000redr Hitem:1h[x]h")
	T.eq(Util.Clean("ok\255\254bad"), "okbad")
	T.eq(Util.Clean("\195"), "") -- truncated sequence
	T.eq(Util.Clean(nil), "")
	T.eq(Util.Clean("ééééé", 5), "éé") -- never splits a sequence
	T.eq(Util.Clean("ab cd", 3), "ab") -- no trailing space after the cut
	T.ok(Util.IsClean("Ganking lowbies in STV", 100))
	T.ok(not Util.IsClean("two  spaces", 100))
	T.ok(not Util.IsClean("pipe|here", 100))
	T.ok(not Util.IsClean("too long", 3))
	T.ok(not Util.IsClean(42, 100))
end)

T.test("shortname and ago", function()
	T.eq(Util.ShortName("Olaf-Realm"), "Olaf")
	T.eq(Util.ShortName("Olaf"), "Olaf")
	T.eq(Util.Ago(5), "just now")
	T.eq(Util.Ago(125), "2 min ago")
	T.eq(Util.Ago(7300), "2 h ago")
	T.eq(Util.Ago(3 * 86400 + 5), "3 d ago")
end)
