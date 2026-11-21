-- Plays a whole session against an imitation of the WoW API (wowstub.lua):
-- every file the .toc lists is loaded, then the player logs in, lists an
-- enemy, meets them, hears from guildmates, opens the window and so on.
-- The point is to catch Lua errors in the game-facing code before it ever
-- runs in the client.
local T = ...
local Stub = assert(loadfile(T.root .. "/tests/wowstub.lua"))()

local function chatHas(world, needle, from)
	for i = from or 1, #world.chat do
		if world.chat[i]:find(needle, 1, true) then return true end
	end
	return false
end

local function noErrors(world)
	T.eq(#world.errors, 0, "Lua errors raised: " .. table.concat(world.errors, " | "))
end

local GRIMTUSK = { name = "Grimtusk", surname = "Bloodaxe", guid = "Player-1-0000AAAA", isPlayer = true, enemy = true,
	faction = "Horde", class = 4, race = 2, level = 60, guild = "Hostile Takeover" }

T.test("game: a full session runs without Lua errors", function()
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 }, { "Kari-Frost", 5 }, { "Astrid-Vale", 1 }, { "Bjorn-Ironside", 0 } }
	local ns, loaded = world:LoadAddon(T.root)
	T.ok(#loaded >= 25, "files loaded from the toc: " .. #loaded)
	local Codec, Names = ns.Codec, ns.Names

	world:Fire("ADDON_LOADED", "BloodFeud")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	noErrors(world)
	local session = T.ok(ns.session, "a session is bound to the guild")
	T.eq(session.guild, "Northwind Trading")
	T.eq(session.me, "Olaf-Stormborn")
	T.ok(ns.Roster.ready, "roster loaded")
	T.ok(ns.Roster.IsOfficer("astrid-vale"), "rank with the officer flag")
	T.ok(ns.Roster.IsOfficer("bjorn-ironside"), "guild master")
	T.ok(not ns.Roster.IsOfficer("kari-frost"))
	T.ok(not ns.Roster.AmOfficer())
	T.ok(SlashCmdList.BLOODFEUD, "slash command registered")
	T.ok(world.iconRegistered, "minimap button registered")
	T.eq(world.checkboxes, 9, "options page built")
	T.eq(world.sliders, 2, "revenge sliders built")

	-- Names in their three shapes
	T.eq(Names.Canon("Grimtusk Bloodaxe"), "Grimtusk-Bloodaxe")
	T.eq(Names.Canon("grimtusk-bloodaxe", true), "Grimtusk-Bloodaxe")
	T.eq(Names.Canon("grimtusk", true), "Grimtusk")
	T.eq(Names.Display("Grimtusk-Bloodaxe"), "Grimtusk Bloodaxe")
	T.eq(Names.Canon(Stub.SECRET), nil)

	-- Add the target with a slash command
	world.units.target = GRIMTUSK
	SlashCmdList.BLOODFEUD("add Ganking lowbies in STV")
	noErrors(world)
	local store = session.store
	T.ok(store:IsListed("grimtusk-bloodaxe"), "target is on the list")
	local subject = store:Player("grimtusk-bloodaxe")
	T.eq(subject.reports[1].reason, "Ganking lowbies in STV")
	T.eq(subject.reports[1].author, "Olaf-Stormborn")
	T.eq(subject.facts.guid, "Player-1-0000AAAA")
	T.eq(subject.facts.level, 60)
	T.eq(subject.facts.guild, "Hostile Takeover")
	T.ok(chatHas(world, "Added Grimtusk Bloodaxe"))

	-- The edit goes out as addon messages and our own echo clears the flag
	world:Advance(3)
	noErrors(world)
	local states = 0
	for _, m in ipairs(world.sent) do
		T.ok(#m.text <= 255)
		if m.prefix == "BloodFeud" and m.text:sub(1, 1) == "U" then states = states + 1 end
	end
	T.ok(states >= 1, "update frames sent: " .. states)
	T.eq(#store:DirtyIds(), 0, "echo cleared the unsent flags")

	-- Meeting the player: alert, sound, nameplate mark, sighting to the guild
	local chatFrom = #world.chat + 1
	world:Fire("PLAYER_TARGET_CHANGED")
	noErrors(world)
	T.ok(chatHas(world, "Kill on Sight nearby", chatFrom), "chat alert")
	T.ok(BloodFeudAlertBanner and BloodFeudAlertBanner:IsShown(), "banner shown")
	T.eq(world.lastSound, 8959)
	world.units.nameplate1 = GRIMTUSK
	world:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	noErrors(world)
	T.ok(ns.Nameplates.marks.nameplate1, "nameplate marked")
	world:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	T.eq(ns.Nameplates.marks.nameplate1, nil)
	world:Advance(1)
	local sightings = 0
	for _, m in ipairs(world.sent) do
		if m.prefix == "BloodFeudS" then sightings = sightings + 1 end
	end
	T.eq(sightings, 1, "one sighting sent, not one per event")
	T.ok(store:GetSeen("grimtusk-bloodaxe"), "last seen recorded")

	-- A unit whose identity is secret is ignored quietly
	world.units.mouseover = { secret = true, isPlayer = true, enemy = true }
	world:Fire("UPDATE_MOUSEOVER_UNIT")
	noErrors(world)

	-- A guildmate adds someone
	local now = GetServerTime()
	local theirs = Codec.Seal({ k = "r", name = "Vexara-Nightfall", author = "Kari-Frost", mby = "Kari-Frost", ts = now,
		at = now, reason = "Repeat offender" })
	chatFrom = #world.chat + 1
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(theirs.id), 1, 1, { theirs.wire })), "Kari-Frost")
	world:Advance(1)
	noErrors(world)
	T.ok(store:IsListed("vexara-nightfall"), "guildmate's entry stored")
	T.ok(chatHas(world, "Kari Frost added Vexara Nightfall", chatFrom), "announced in chat")

	-- A member cannot list a guild; an officer can
	local guildByMember = Codec.Seal({ k = "g", name = "Red Ledger", author = "Kari-Frost", mby = "Kari-Frost", ts = now,
		at = now, reason = "x" })
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(guildByMember.id), 1, 1, { guildByMember.wire })), "Kari-Frost")
	local guildByOfficer = Codec.Seal({ k = "g", name = "Hostile Takeover", author = "Astrid-Vale", mby = "Astrid-Vale",
		ts = now, at = now, reason = "War" })
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(guildByOfficer.id), 1, 1, { guildByOfficer.wire })),
		"Astrid-Vale")
	world:Advance(1)
	noErrors(world)
	T.ok(not store:IsGuildListed("Red Ledger"), "member's guild report refused")
	T.ok(store:IsGuildListed("Hostile Takeover"), "officer's guild report accepted")
	T.ok(chatHas(world, "without the right to"), "refusal is announced")

	-- A member of a listed guild gives the quieter alert
	world.units.focus = { name = "Dravok", surname = "Ashmane", guid = "Player-1-0000BBBB", isPlayer = true, enemy = true,
		faction = "Horde", class = 3, race = 8, level = 52, guild = "Hostile Takeover" }
	chatFrom = #world.chat + 1
	world:Fire("PLAYER_FOCUS_CHANGED")
	noErrors(world)
	T.ok(chatHas(world, "Listed guild nearby", chatFrom))
	T.eq(world.lastSound, 3081)

	-- Tooltip lines
	world.tooltipUnit = "target"
	GameTooltip.lines = {}
	world.tooltipHook(GameTooltip)
	noErrors(world)
	T.ok(table.concat(GameTooltip.lines, "\n"):find("Kill on Sight", 1, true), "tooltip has the Kill on Sight block")
	world.tooltipUnit = "focus"
	GameTooltip.lines = {}
	world.tooltipHook(GameTooltip)
	T.ok(table.concat(GameTooltip.lines, "\n"):find("Guild on the list", 1, true), "tooltip for a listed guild")

	-- Right-click menu
	local buttons = {}
	local root = {
		CreateDivider = function() end,
		CreateTitle = function() end,
		CreateButton = function(_, text, fn) buttons[#buttons + 1] = { text = text, fn = fn } end,
	}
	world.menus.MENU_UNIT_ENEMY_PLAYER(nil, root, { unit = "target", which = "ENEMY_PLAYER" })
	T.eq(#buttons, 1)
	T.ok(buttons[1].text:find("Remove", 1, true), "already listed by me: offers removal")
	world.menus.MENU_UNIT_ENEMY_PLAYER(nil, root, { unit = "focus", which = "ENEMY_PLAYER" })
	T.ok(buttons[2].text:find("Add", 1, true), "not listed by me: offers adding")
	buttons[2].fn()
	noErrors(world)
	T.ok(BloodFeudAddDialog:IsShown(), "add dialog opened from the menu")
	ns.AddDialog.frame.reason:SetText("Guild war")
	ns.AddDialog:Submit()
	noErrors(world)
	T.ok(store:IsListed("dravok-ashmane"), "added from the dialog")
	T.ok(not BloodFeudAddDialog:IsShown())

	-- A sighting from a guildmate
	chatFrom = #world.chat + 1
	world:Receive("BloodFeudS", Codec.EncodeSighting({ key = "vexara-nightfall", name = "Vexara-Nightfall", map = 1434,
		x = 300, y = 400, t = GetServerTime() }), "Kari-Frost")
	world:Advance(1)
	noErrors(world)
	T.ok(chatHas(world, "spotted in Stranglethorn Vale", chatFrom), "sighting shown")
	T.eq(store:GetSeen("vexara-nightfall").by, "Kari-Frost")

	-- The window
	SlashCmdList.BLOODFEUD("")
	world:Advance(1)
	noErrors(world)
	local main = ns.MainFrame
	T.ok(main.frame:IsShown(), "window open")
	T.eq(#main.items, 3, "three listed players")
	local names = {}
	for i = 1, 3 do names[#names + 1] = main.frame.rows[i].cells[1]:GetText() end
	T.ok(table.concat(names, "|"):find("Grimtusk Bloodaxe", 1, true), "row shows the display name")
	main.frame.search:SetText("offender")
	T.eq(#main.items, 1, "search filters on the reason")
	main.frame.search:SetText("")
	main.frame.rows[1].scripts.OnEnter(main.frame.rows[1])
	main.frame.rows[1].scripts.OnLeave(main.frame.rows[1])
	main:SetTab("g")
	T.eq(#main.items, 1, "one listed guild")
	T.ok(not main.frame.add:IsEnabled(), "a member cannot add guilds")
	main:SetTab("r")
	noErrors(world)

	-- Remove my own report through the window
	main.selected = "grimtusk-bloodaxe"
	main:UpdateActions()
	T.ok(main.frame.removeMine:IsEnabled())
	main.frame.removeMine:Click()
	noErrors(world)
	T.ok(not store:IsListed("grimtusk-bloodaxe"), "my report is gone")
	main.selected = "vexara-nightfall"
	main:UpdateActions()
	T.ok(not main.frame.removeMine:IsEnabled(), "cannot remove someone else's report")
	T.ok(not ns:RemoveAll("r", "vexara-nightfall"), "and not as a non-officer either")
	T.ok(store:IsListed("vexara-nightfall"))

	-- Typed add, with and without a surname
	SlashCmdList.BLOODFEUD("remove dravok-ashmane")
	world.units.target = nil
	SlashCmdList.BLOODFEUD("add shadowfel-grimm camping the flight path")
	T.ok(store:IsListed("shadowfel-grimm"))
	T.eq(store:Player("shadowfel-grimm").reports[1].name, "Shadowfel-Grimm")
	SlashCmdList.BLOODFEUD("add zulrakka")
	T.ok(store:IsListed("zulrakka"))
	-- an entry typed with only a first name still matches the full name
	world.units.target = { name = "Zulrakka", surname = "Venomtongue", guid = "Player-1-0000CCCC", isPlayer = true,
		enemy = true, faction = "Horde", class = 8, race = 8, level = 54 }
	chatFrom = #world.chat + 1
	world:Fire("PLAYER_TARGET_CHANGED")
	T.ok(chatHas(world, "Kill on Sight nearby", chatFrom), "first-name entry matched")
	T.eq(store:Player("zulrakka").facts.guid, "Player-1-0000CCCC", "and is now pinned to that character")
	T.eq(store:Player("zulrakka").name, "Zulrakka-Venomtongue")
	-- adding yourself is refused
	SlashCmdList.BLOODFEUD("add olaf-stormborn")
	T.ok(not store:IsListed("olaf-stormborn"))
	noErrors(world)

	-- Lockdown: nothing is sent while addon chat is locked, then it goes out
	world:Advance(15)
	world.locked = true
	local before = #world.sent
	SlashCmdList.BLOODFEUD("add raidganker-foul killed me at the entrance")
	world:Advance(20)
	T.eq(#world.sent, before, "silent while locked")
	T.ok(#store:DirtyIds() >= 1, "kept as unsent")
	world.locked = false
	world:Advance(20)
	T.ok(#world.sent > before, "sent after the lockdown")
	T.eq(#store:DirtyIds(), 0)
	noErrors(world)

	-- Everything else a player can type
	for _, command in ipairs({ "log", "test", "help", "sync", "options", "set sound off", "set nonsense on",
		"guild Red Ledger = camping", "remove nobody-here" }) do
		SlashCmdList.BLOODFEUD(command)
	end
	T.eq(world.optionsOpened, 7)
	T.eq(ns.settings.sound, false)
	T.ok(chatHas(world, "Only officers can do that"))
	noErrors(world)

	-- The probe
	local lines
	ns.Probe:Run(function(result) lines = result end)
	world:Advance(4)
	noErrors(world)
	local report = table.concat(T.ok(lines, "probe finished"), "\n")
	T.ok(report:find("heard our own message back: yes", 1, true), "loopback detected")
	T.ok(report:find('"Aaaa", "Aaaaaaaaa"', 1, true), "names are masked to their shape")
	T.ok(not report:find("Olaf", 1, true), "no real names in the report")
	T.ok(not report:find("PROBE ERROR", 1, true), report)
	T.ok(BloodFeudDB.probe and #BloodFeudDB.probe.lines > 30, "saved for reading from disk")

	-- Becoming an officer unlocks guild reports and removing others' reports
	world.myRank = 1
	world.roster[1][2] = 1
	world:Fire("GUILD_ROSTER_UPDATE")
	world:Advance(2)
	T.ok(ns.Roster.AmOfficer())
	SlashCmdList.BLOODFEUD("guild Red Ledger = camping our raid")
	T.ok(store:IsGuildListed("Red Ledger"))
	T.ok(ns:RemoveAll("r", "vexara-nightfall"))
	T.ok(not store:IsListed("vexara-nightfall"))
	noErrors(world)

	-- Leaving the guild ends the session; the data stays for next time
	world.inGuild = false
	world:Fire("PLAYER_GUILD_UPDATE")
	world:Advance(2)
	T.eq(ns.session, nil)
	T.ok(BloodFeudDB.guilds["Northwind Trading"], "list kept in saved variables")
	SlashCmdList.BLOODFEUD("add someone")
	T.ok(chatHas(world, "need to be in a guild"))
	main:Refresh()
	world:Advance(2)
	noErrors(world)
end)

T.test("game: kills, deaths, scores and the revenge prompt", function()
	local keep = BloodFeudDB
	BloodFeudDB = nil -- a fresh install
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 }, { "Kari-Frost", 5 } }
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BloodFeud")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	local store = ns.session.store
	local Codec = ns.Codec

	-- An unlisted enemy, seen on a nameplate, kills us twice within the window
	local VEX = { name = "Vexara", surname = "Nightfall", guid = "Player-1-0000DDDD", isPlayer = true, enemy = true,
		faction = "Horde", class = 8, race = 5, level = 58 }
	world.units.nameplate2 = VEX
	world:Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
	world.units.nameplate2 = nil -- the plate is gone by the time we read the recap
	world.recap = { { sourceName = "Vexara Nightfall", timestamp = 100 } }
	world:Fire("PLAYER_DEAD")
	world:Advance(2)
	noErrors(world)
	local book = ns.Feuds:Book()
	T.eq(book["vexara-nightfall"].d, 1, "first death counted from the recap name")
	T.ok(not (_G.BloodFeudRevengeFrame and _G.BloodFeudRevengeFrame:IsShown()), "no prompt after one death")
	world:Fire("PLAYER_DEAD") -- the same recap again must not count twice
	world:Advance(2)
	T.eq(book["vexara-nightfall"].d, 1, "a repeated recap counts once")

	world:Advance(600)
	world.recap = { { sourceName = "Unknown pet", timestamp = 205 }, { sourceGUID = "Player-1-0000DDDD", timestamp = 200 } }
	world:Fire("PLAYER_DEAD")
	world:Advance(2)
	noErrors(world)
	T.eq(book["vexara-nightfall"].d, 2, "credited past an unidentified killing blow")
	T.ok(_G.BloodFeudRevengeFrame and _G.BloodFeudRevengeFrame:IsShown(), "revenge offered on the second death")
	T.ok(_G.BloodFeudRevengeFrame.text:GetText():find("2 times", 1, true), "prompt says how often")

	-- Accepting lists them with the suggested reason and publishes our score
	ns.Revenge:Accept()
	noErrors(world)
	T.ok(store:IsListed("vexara-nightfall"), "listed from the prompt")
	local mine = store:Player("vexara-nightfall").reports[1]
	T.ok(mine.reason:find("Killed me 2 times", 1, true), "suggested reason used: " .. mine.reason)
	local score = store:Get(Codec.Id("c", "vexara-nightfall", "olaf-stormborn"))
	T.ok(score, "score record published once listed")
	T.eq(score.deaths, 2)
	T.eq(score.kills, 0)

	-- A third death within the window does not prompt again (already listed)
	world.recap = { { sourceGUID = "Player-1-0000DDDD", timestamp = 300 } }
	_G.BloodFeudRevengeFrame:Hide()
	world:Fire("PLAYER_DEAD")
	world:Advance(2)
	T.ok(not _G.BloodFeudRevengeFrame:IsShown(), "no prompt for someone I already listed")
	T.ok(chatHas(world, "Killed by"), "death by a listed player is announced")

	-- Our killing blow, with them targeted
	world.units.target = VEX
	world:Fire("PARTY_KILL", "Player-1-00000001", "Player-1-0000DDDD")
	noErrors(world)
	T.eq(book["vexara-nightfall"].k, 1, "kill counted")
	T.ok(chatHas(world, "You killed"), "kill announced")
	-- Someone else's kill is not ours
	world:Fire("PARTY_KILL", "Player-1-00000099", "Player-1-0000DDDD")
	T.eq(book["vexara-nightfall"].k, 1, "a party member's kill is theirs to count")

	-- A guildmate's score adds to the guild total
	local now = GetServerTime()
	local theirs = Codec.Seal({ k = "c", key = "vexara-nightfall", author = "Kari-Frost", ts = now, kills = 4, deaths = 1 })
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(theirs.id), 1, 1, { theirs.wire })), "Kari-Frost")
	world:Advance(1)
	local kills, deaths = store:Score("vexara-nightfall")
	T.eq(kills, 5, "guild kills")
	T.eq(deaths, 4, "guild deaths")
	-- ...but nobody may write someone else's score
	local forged = Codec.Seal({ k = "c", key = "vexara-nightfall", author = "Olaf-Stormborn", ts = now + 5, kills = 0,
		deaths = 99 })
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(forged.id), 1, 1, { forged.wire })), "Kari-Frost")
	world:Advance(1)
	T.eq(store:Get(forged.id).deaths, 3, "a score relayed in my name is corrected by me")
	T.ok(store:Get(forged.id).ts > forged.ts, "with a newer record that wins everywhere")
	local direct = Codec.Seal({ k = "c", key = "vexara-nightfall", author = "Kari-Frost", ts = now + 9, kills = 50,
		deaths = 0 })
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(direct.id), 1, 1, { direct.wire })), "Astrid-Vale")
	world:Advance(1)
	-- Relayed state cannot be verified, so it is taken; Kari's own client is
	-- the one that corrects it (see Feuds:Defend).
	T.eq(store:Get(direct.id).kills, 50, "relayed state about a third person is accepted")

	-- The window and the score command run cleanly
	ns.MainFrame:Toggle()
	world:Advance(1)
	SlashCmdList.BLOODFEUD("score")
	SlashCmdList.BLOODFEUD("score Vexara-Nightfall")
	T.ok(chatHas(world, "Guild score: 51 kills, 3 deaths"))
	noErrors(world)

	-- Inside an instance nothing is counted
	world.instance = "pvp"
	world:Fire("PLAYER_ENTERING_WORLD")
	world.recap = { { sourceGUID = "Player-1-0000DDDD", timestamp = 400 } }
	world:Fire("PLAYER_DEAD")
	world:Advance(2)
	T.eq(book["vexara-nightfall"].d, 3, "battleground deaths are not counted")
	noErrors(world)
	BloodFeudDB = keep -- the next test reloads the first session's data
end)

T.test("game: saved variables survive a reload", function()
	local saved = BloodFeudDB
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 } }
	BloodFeudDB = saved
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BloodFeud")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	T.eq(#world.errors, 0, table.concat(world.errors, " | "))
	local session = T.ok(ns.session)
	T.ok(session.store:IsListed("shadowfel-grimm"), "entries are back")
	T.ok(session.store:IsGuildListed("Red Ledger"))
	T.eq(ns.settings.sound, false, "settings are back")
	world:Advance(12)
	local players = session.store:Counts()
	T.ok(world.chat[#world.chat]:find(players .. " players", 1, true), "login summary printed")
end)
