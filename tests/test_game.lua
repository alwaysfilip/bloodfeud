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

	world:Fire("ADDON_LOADED", "BusinessMeeting")
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
	T.ok(SlashCmdList.BUSINESSMEETING, "slash command registered")
	T.ok(world.iconRegistered, "minimap button registered")
	T.eq(world.checkboxes, 18, "options page built")
	T.eq(world.sliders, 2, "revenge sliders built")

	-- Names in their three shapes
	T.eq(Names.Canon("Grimtusk Bloodaxe"), "Grimtusk-Bloodaxe")
	T.eq(Names.Canon("grimtusk-bloodaxe", true), "Grimtusk-Bloodaxe")
	T.eq(Names.Canon("grimtusk", true), "Grimtusk")
	T.eq(Names.Display("Grimtusk-Bloodaxe"), "Grimtusk Bloodaxe")
	T.eq(Names.Canon(Stub.SECRET), nil)

	-- Add the target with a slash command
	world.units.target = GRIMTUSK
	SlashCmdList.BUSINESSMEETING("add Ganking lowbies in STV")
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
	T.ok(BusinessMeetingAlertBanner and BusinessMeetingAlertBanner:IsShown(), "banner shown")
	-- built like a unit frame: portrait with the class icon and level, the name on a plate
	local banner = BusinessMeetingAlertBanner
	T.eq(banner.title:GetText(), "KILL ON SIGHT")
	T.eq(banner.name:GetText(), "GRIMTUSK BLOODAXE", "the name in capitals on the plate")
	T.eq(banner.portrait.shows, "class", "the class icon is the portrait")
	T.eq(banner.portrait.badge.text:GetText(), "60", "the level in the badge")
	T.ok(banner.sub:GetText():find("Orc Rogue", 1, true), banner.sub:GetText())
	T.ok(banner.sub:GetText():find("<Hostile Takeover>", 1, true), "the guild under the name")
	T.ok(banner.detail:GetText():find("“", 1, true), "the intel on the bottom line")
	T.ok(banner.by:GetText():find("sanctioned by", 1, true), banner.by:GetText())
	T.ok(not banner.badge:IsShown(), "no extra Kill on Sight badge on the Kill on Sight alert itself")
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
		if m.prefix == "BloodFeudS" and m.text:sub(1, 1) == "S" then sightings = sightings + 1 end
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
	T.ok(chatHas(world, "Kari Frost put Vexara Nightfall", chatFrom), "announced in chat")

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
	T.ok(chatHas(world, "Hostile guild nearby", chatFrom))
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
	T.ok(table.concat(GameTooltip.lines, "\n"):find("Hostile guild", 1, true), "tooltip for a listed guild")

	-- Right-click menu
	local buttons = {}
	local root = {
		CreateDivider = function() end,
		CreateTitle = function() end,
		CreateButton = function(_, text, fn) buttons[#buttons + 1] = { text = text, fn = fn } end,
	}
	world.menus.MENU_UNIT_ENEMY_PLAYER(nil, root, { unit = "target", which = "ENEMY_PLAYER" })
	T.eq(#buttons, 2)
	T.ok(buttons[1].text:find("Remove", 1, true), "already listed by me: offers removal")
	T.ok(buttons[2].text:find("contract", 1, true), "and a contract")
	world.menus.MENU_UNIT_ENEMY_PLAYER(nil, root, { unit = "focus", which = "ENEMY_PLAYER" })
	T.ok(buttons[3].text:find("Add", 1, true), "not listed by me: offers adding")
	buttons[3].fn()
	noErrors(world)
	T.ok(BusinessMeetingAddDialog:IsShown(), "add dialog opened from the menu")
	ns.AddDialog.frame.reason:SetText("Guild war")
	ns.AddDialog:Submit()
	noErrors(world)
	T.ok(store:IsListed("dravok-ashmane"), "added from the dialog")
	T.ok(not BusinessMeetingAddDialog:IsShown())

	-- A sighting from a guildmate
	chatFrom = #world.chat + 1
	world:Receive("BloodFeudS", Codec.EncodeSighting({ key = "vexara-nightfall", name = "Vexara-Nightfall", map = 1434,
		x = 300, y = 400, t = GetServerTime() }), "Kari-Frost")
	world:Advance(1)
	noErrors(world)
	T.ok(chatHas(world, "spotted in Stranglethorn Vale", chatFrom), "sighting shown")
	T.eq(store:GetSeen("vexara-nightfall").by, "Kari-Frost")

	-- The window
	SlashCmdList.BUSINESSMEETING("")
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
	SlashCmdList.BUSINESSMEETING("remove dravok-ashmane")
	world.units.target = nil
	SlashCmdList.BUSINESSMEETING("add shadowfel-grimm camping the flight path")
	T.ok(store:IsListed("shadowfel-grimm"))
	T.eq(store:Player("shadowfel-grimm").reports[1].name, "Shadowfel-Grimm")
	SlashCmdList.BUSINESSMEETING("add zulrakka")
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
	SlashCmdList.BUSINESSMEETING("add olaf-stormborn")
	T.ok(not store:IsListed("olaf-stormborn"))
	noErrors(world)

	-- Lockdown: nothing is sent while addon chat is locked, then it goes out
	world:Advance(15)
	world.locked = true
	local before = #world.sent
	SlashCmdList.BUSINESSMEETING("add raidganker-foul killed me at the entrance")
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
		SlashCmdList.BUSINESSMEETING(command)
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
	T.ok(BusinessMeetingDB.probe and #BusinessMeetingDB.probe.lines > 30, "saved for reading from disk")

	-- Becoming an officer unlocks guild reports and removing others' reports
	world.myRank = 1
	world.roster[1][2] = 1
	world:Fire("GUILD_ROSTER_UPDATE")
	world:Advance(2)
	T.ok(ns.Roster.AmOfficer())
	SlashCmdList.BUSINESSMEETING("guild Red Ledger = camping our raid")
	T.ok(store:IsGuildListed("Red Ledger"))
	T.ok(ns:RemoveAll("r", "vexara-nightfall"))
	T.ok(not store:IsListed("vexara-nightfall"))
	noErrors(world)

	-- Leaving the guild ends the session; the data stays for next time
	world.inGuild = false
	world:Fire("PLAYER_GUILD_UPDATE")
	world:Advance(2)
	T.eq(ns.session, nil)
	T.ok(BusinessMeetingDB.guilds["Northwind Trading"], "list kept in saved variables")
	SlashCmdList.BUSINESSMEETING("add someone")
	T.ok(chatHas(world, "need to be in a guild"))
	main:Refresh()
	world:Advance(2)
	noErrors(world)
end)

T.test("game: kills, deaths, scores and the revenge prompt", function()
	local keep = BusinessMeetingDB
	BusinessMeetingDB = nil -- a fresh install
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 }, { "Kari-Frost", 5 } }
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
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
	T.ok(not (_G.BusinessMeetingRevengeFrame and _G.BusinessMeetingRevengeFrame:IsShown()), "no prompt after one death")
	world:Fire("PLAYER_DEAD") -- the same recap again must not count twice
	world:Advance(2)
	T.eq(book["vexara-nightfall"].d, 1, "a repeated recap counts once")

	world:Advance(600)
	world.recap = { { sourceName = "Unknown pet", timestamp = 205 }, { sourceGUID = "Player-1-0000DDDD", timestamp = 200 } }
	world:Fire("PLAYER_DEAD")
	world:Advance(2)
	noErrors(world)
	T.eq(book["vexara-nightfall"].d, 2, "credited past an unidentified killing blow")
	T.ok(_G.BusinessMeetingRevengeFrame and _G.BusinessMeetingRevengeFrame:IsShown(), "revenge offered on the second death")
	T.ok(_G.BusinessMeetingRevengeFrame.text:GetText():find("2 times", 1, true), "prompt says how often")

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
	_G.BusinessMeetingRevengeFrame:Hide()
	world:Fire("PLAYER_DEAD")
	world:Advance(2)
	T.ok(not _G.BusinessMeetingRevengeFrame:IsShown(), "no prompt for someone I already listed")
	T.ok(chatHas(world, "Killed by"), "death by a listed player is announced")

	-- Our killing blow, with them targeted
	world.units.target = VEX
	world:Fire("PARTY_KILL", "Player-1-00000001", "Player-1-0000DDDD")
	noErrors(world)
	T.eq(book["vexara-nightfall"].k, 1, "kill counted")
	T.ok(chatHas(world, "Kill confirmed:"), "kill announced")
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
	SlashCmdList.BUSINESSMEETING("score")
	SlashCmdList.BUSINESSMEETING("score Vexara-Nightfall")
	T.ok(chatHas(world, "Guild record: kills 51, deaths 3"))
	noErrors(world)

	-- Inside an instance nothing is counted
	world.instance = "pvp"
	world:Fire("PLAYER_ENTERING_WORLD")
	world.recap = { { sourceGUID = "Player-1-0000DDDD", timestamp = 400 } }
	world:Fire("PLAYER_DEAD")
	world:Advance(2)
	T.eq(book["vexara-nightfall"].d, 3, "battleground deaths are not counted")
	noErrors(world)
	BusinessMeetingDB = keep -- the next test reloads the first session's data
end)

T.test("game: saved variables survive a reload", function()
	local saved = BusinessMeetingDB
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 } }
	BusinessMeetingDB = saved
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
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

T.test("game: radar, bounties, ranks and achievements", function()
	local keep = BusinessMeetingDB
	BusinessMeetingDB = nil
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 }, { "Kari-Frost", 5 }, { "Astrid-Vale", 1 } }
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	noErrors(world)
	local store = ns.session.store
	local Codec, Progress = ns.Codec, ns.Progress

	-- The radar picks up an enemy and shows itself (radar on, auto mode)
	local MORG = { name = "Morgash", surname = "Gorefist", guid = "Player-1-0000EEEE", isPlayer = true, enemy = true,
		faction = "Horde", class = 1, race = 2, level = 60, guild = "Hostile Takeover" }
	T.ok(not (_G.BusinessMeetingRadarFrame and _G.BusinessMeetingRadarFrame:IsShown()), "radar hidden with nobody around")
	world.units.nameplate3 = MORG
	world:Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
	world:Advance(1)
	noErrors(world)
	T.ok(_G.BusinessMeetingRadarFrame and _G.BusinessMeetingRadarFrame:IsShown(), "radar appears")
	local visible = ns.Radar:Visible()
	T.eq(#visible, 1)
	T.eq(visible[1].tag, 0, "an ordinary enemy")
	T.ok(_G.BusinessMeetingRadarFrame.rows[1].name:GetText():find("Morgash Gorefist", 1, true))

	-- A guildmate posts a bounty on him: it is announced, tagged and alerted
	local now = GetServerTime()
	local bounty = Codec.Seal({ k = "b", scope = "p", name = "Morgash-Gorefist", author = "Kari-Frost", mby = "Kari-Frost",
		ts = now, at = now, points = 25, reward = "50 gold" })
	local chatFrom = #world.chat + 1
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(bounty.id), 1, 1, { bounty.wire })), "Kari-Frost")
	world:Advance(1)
	noErrors(world)
	T.ok(store:HasBounty("p", "morgash-gorefist"), "bounty stored")
	T.ok(chatHas(world, "Kari Frost opened a contract on Morgash Gorefist: 25 points, 50 gold", chatFrom), "announced")
	T.eq(ns.Radar:Visible()[1].tag, 2, "radar tags the bounty")
	-- His nameplate is still up, and is looked at again now that he has a price
	T.ok(chatHas(world, "Open contract nearby", chatFrom), "bounty alert")
	world.units.target = MORG
	world:Fire("PLAYER_TARGET_CHANGED")
	world.tooltipUnit = "target"
	GameTooltip.lines = {}
	world.tooltipHook(GameTooltip)
	T.ok(table.concat(GameTooltip.lines, "\n"):find("Open contract: 25 points", 1, true), "tooltip shows the bounty")

	-- Our killing blow claims it, counts toward rank and earns achievements
	chatFrom = #world.chat + 1
	world:Fire("PARTY_KILL", "Player-1-00000001", "Player-1-0000EEEE")
	world:Advance(1)
	noErrors(world)
	local claim = store:Get(Codec.ClaimId("p", "morgash-gorefist", "kari-frost", "olaf-stormborn"))
	T.ok(claim, "claim written")
	T.eq(claim.count, 1)
	T.ok(chatHas(world, "Contract fulfilled", chatFrom), "we are told")
	local st = Progress:Stats()
	T.eq(st.kills, 1)
	T.eq(st.points, 25)
	T.eq(st.claims, 1)
	T.ok(st.earned[1], "First Blood")
	T.ok(st.earned[24], "Bounty Hunter")
	T.ok(chatHas(world, "Medal earned: |cfff0c75eFirst Blood", chatFrom))
	-- Right after login nothing is published yet: the guild may still be
	-- about to send what it remembers of us.
	T.eq(store:Member("olaf-stormborn"), nil, "totals held back just after login")
	world:Advance(Progress.HOLD_SECONDS + 2 * Progress.PUBLISH_EVERY)
	noErrors(world)
	local me = store:Member("olaf-stormborn")
	T.ok(me, "member record published once the hold is over")
	T.eq(me.kills, 1)
	T.eq(me.points, 25)
	T.ok(Progress.Has(me.ach, 1) and Progress.Has(me.ach, 24), "achievements published")
	T.eq(Progress:MyRank().title, "Recruit")

	-- Killing them again, without dying, builds a streak
	for _ = 1, 2 do world:Fire("PARTY_KILL", "Player-1-00000001", "Player-1-0000EEEE") end
	world:Advance(1)
	T.eq(st.best, 3)
	T.ok(st.earned[7], "Hat Trick")
	T.eq(store:Get(claim.id).count, 3)
	-- Dying ends the streak
	world.recap = { { sourceGUID = "Player-1-0000EEEE", timestamp = 50 } }
	world:Fire("PLAYER_DEAD")
	world:Advance(2)
	T.eq(st.streak, 0)
	T.eq(st.deaths, 1)

	-- Posting our own bounty, from the slash command (nobody targeted: by name)
	world.units.target = nil
	SlashCmdList.BUSINESSMEETING("bounty zulrakka-venomtongue 15 a fine axe")
	noErrors(world)
	local mine = store:Get(Codec.BountyId("p", "zulrakka-venomtongue", "olaf-stormborn"))
	T.ok(mine, "bounty posted")
	T.eq(mine.points, 15)
	T.eq(mine.reward, "a fine axe")
	T.ok(st.earned[26], "Price on Their Head")
	-- Posting again without points or reward keeps what it had
	SlashCmdList.BUSINESSMEETING("bounty zulrakka-venomtongue")
	mine = store:Get(mine.id)
	T.eq(mine.points, 15, "points kept")
	T.eq(mine.reward, "a fine axe", "reward kept")
	SlashCmdList.BUSINESSMEETING("bounty zulrakka-venomtongue 30")
	mine = store:Get(mine.id)
	T.eq(mine.points, 30, "points changed")
	T.eq(mine.reward, "a fine axe", "reward still kept")
	SlashCmdList.BUSINESSMEETING("bounty <Red Ledger> 5")
	T.ok(store:HasBounty("g", "red ledger"), "a bounty on a whole guild")
	-- Our own bounty pays us nothing
	local ZUL = { name = "Zulrakka", surname = "Venomtongue", guid = "Player-1-0000FFFF", isPlayer = true, enemy = true,
		faction = "Horde", class = 8, race = 8, level = 54 }
	world.units.focus = ZUL
	world:Fire("PLAYER_FOCUS_CHANGED")
	world:Fire("PARTY_KILL", "Player-1-00000001", "Player-1-0000FFFF")
	T.eq(store:Get(Codec.ClaimId("p", "zulrakka-venomtongue", "olaf-stormborn", "olaf-stormborn")), nil)
	T.eq(st.points, 75)

	-- A guildmate's totals: rank-ups and achievements are announced
	local function member(kills, ach, ts)
		return Codec.Seal({ k = "m", author = "Kari-Frost", ts = ts, kills = kills, deaths = 2, best = 4, points = 0,
			ach = ach })
	end
	local m1 = member(9, 1, GetServerTime())
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(m1.id), 1, 1, { m1.wire })), "Kari-Frost")
	world:Advance(1)
	chatFrom = #world.chat + 1
	local m2 = member(10, 1 + 2, GetServerTime() + 1)
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(m2.id), 1, 1, { m2.wire })), "Kari-Frost")
	world:Advance(1)
	noErrors(world)
	T.ok(chatHas(world, "Kari Frost earned a medal: |cfff0c75eBlooded", chatFrom), "achievement announced")
	T.ok(chatHas(world, "Kari Frost now holds the rank of |cfff0c75eAssociate", chatFrom), "rank-up announced")
	-- Their rank in their tooltip
	world.units.mouseover = { name = "Kari", surname = "Frost", guid = "Player-1-00000002", isPlayer = true,
		faction = "Alliance", class = 4, race = 1, level = 60, guildmate = true }
	world.tooltipUnit = "mouseover"
	GameTooltip.lines = {}
	world.tooltipHook(GameTooltip)
	T.ok(table.concat(GameTooltip.lines, "\n"):find("Business Meeting: Associate (confirmed kills: 10)", 1, true), "guildmate's rank")

	-- Only officers change the ladder; an officer's change renames the rank
	T.eq(ns:SetTier(2, 10, "Bloodhound"), nil, "a member cannot edit ranks")
	local tier = Codec.Seal({ k = "t", n = 2, ts = GetServerTime(), mby = "Astrid-Vale", kills = 8, title = "Bloodhound" })
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(tier.id), 1, 1, { tier.wire })), "Astrid-Vale")
	world:Advance(1)
	local ladder = Progress.Ladder(store)
	T.eq(ladder[2].title, "Bloodhound")
	T.eq(Progress.RankFor(9, ladder).title, "Bloodhound", "the threshold moved too")
	local forgedTier = Codec.Seal({ k = "t", n = 1, ts = GetServerTime(), mby = "Kari-Frost", kills = 0, title = "Kari" })
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(forgedTier.id), 1, 1, { forgedTier.wire })), "Kari-Frost")
	world:Advance(1)
	T.eq(Progress.Ladder(store)[1].title, "Recruit", "a member's tier edit is refused")

	-- Totals in my name that say less than this computer knows (stale, or
	-- made up by whoever relayed them) are corrected by my own client
	local forged = Codec.Seal({ k = "m", author = "Olaf-Stormborn", ts = GetServerTime() + 5, kills = 0, deaths = 0,
		best = 0, points = 0, ach = 0 })
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(forged.id), 1, 1, { forged.wire })), "Kari-Frost")
	world:Advance(1)
	T.eq(st.kills, 4, "nothing is taken away locally")
	T.eq(store:Member("olaf-stormborn").kills, 4, "and the guild gets the real numbers back")
	T.ok(Progress.Has(store:Member("olaf-stormborn").ach, 1), "achievements included")

	-- Every tab of the window renders, and the dialogs open
	local main = ns.MainFrame
	main:Show()
	for _, tab in ipairs({ "r", "g", "b", "m", "a" }) do
		main:SetTab(tab)
		world:Advance(1)
		noErrors(world)
		if main.frame.rows[1]:IsShown() then
			main.frame.rows[1].scripts.OnEnter(main.frame.rows[1])
			main.frame.rows[1].scripts.OnLeave(main.frame.rows[1])
		end
		noErrors(world)
	end
	main:SetTab("b")
	T.eq(#main.items, 3, "three bounties on the board")
	main:SetTab("m")
	T.eq(#main.items, 2, "two guildmates with totals")
	T.ok(not main.frame.add:IsShown(), "only officers see Edit ranks")
	main:SetTab("a")
	T.eq(#main.items, #ns.Achievements)
	T.ok(main.frame.notice:GetText():find("of " .. #ns.Achievements .. " medals earned", 1, true))

	-- Taking our bounty down from the board
	main:SetTab("b")
	main.selected = mine.id
	main:UpdateActions()
	T.ok(main.frame.removeMine:IsEnabled())
	main.frame.removeMine:Click()
	T.ok(not store:HasBounty("p", "zulrakka-venomtongue"), "taken down")
	main.selected = bounty.id
	main:UpdateActions()
	T.ok(not main.frame.removeMine:IsEnabled(), "not someone else's")

	ns.BountyDialog:Open({ scope = "p", name = "Morgash-Gorefist" })
	ns.BountyDialog.frame.points:SetText("40")
	ns.BountyDialog:Submit()
	T.eq(store:Get(Codec.BountyId("p", "morgash-gorefist", "olaf-stormborn")).points, 40, "posted from the dialog")
	ns.RanksDialog:Open()
	T.ok(not (_G.BusinessMeetingRanksDialog and _G.BusinessMeetingRanksDialog:IsShown()), "ranks dialog is for officers")
	SlashCmdList.BUSINESSMEETING("rank")
	SlashCmdList.BUSINESSMEETING("radar")
	T.eq(ns.settings.radar, false, "radar toggled off")
	T.ok(not _G.BusinessMeetingRadarFrame:IsShown())
	noErrors(world)

	-- Reinstall: the guild remembers our totals
	ns.db.stats = nil
	world:Fire("PLAYER_ENTERING_WORLD")
	ns:Fire("SESSION_CHANGED")
	T.eq(Progress:Stats().kills, 4, "totals adopted from the guild after a wipe")
	T.ok(Progress:Stats().earned[1], "and the achievements")
	noErrors(world)
	BusinessMeetingDB = keep
end)

T.test("game: totals survive a reinstall, and are published at login", function()
	local keep = BusinessMeetingDB
	BusinessMeetingDB = nil
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 }, { "Kari-Frost", 5 } }
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	local store, Codec, Progress = ns.session.store, ns.Codec, ns.Progress

	-- A fresh install: nothing local. A guildmate passes on what the guild
	-- remembers of us, from before the reinstall.
	local old = Codec.Seal({ k = "m", author = "Olaf-Stormborn", ts = GetServerTime() - 86400, kills = 120, deaths = 30,
		best = 6, points = 75, ach = 1 + 2 + 4 })
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(old.id), 1, 1, { old.wire })), "Kari-Frost")
	world:Advance(Progress.HOLD_SECONDS + 2 * Progress.PUBLISH_EVERY)
	noErrors(world)
	local st = Progress:Stats()
	T.eq(st.kills, 120, "kills taken over from the guild")
	T.eq(st.points, 75)
	T.ok(st.earned[1] and st.earned[2] and st.earned[3], "achievements too")
	T.eq(store:Member("olaf-stormborn").kills, 120, "the guild's record is not overwritten with zeros")
	T.eq(Progress:MyRank().title, "Enforcer")

	-- From there the count goes on
	world.units.target = { name = "Vexara", surname = "Nightfall", guid = "Player-1-0000DDDD", isPlayer = true,
		enemy = true, faction = "Horde", class = 8, race = 5, level = 58 }
	world:Fire("PLAYER_TARGET_CHANGED")
	world:Fire("PARTY_KILL", "Player-1-00000001", "Player-1-0000DDDD")
	world:Advance(1)
	T.eq(store:Member("olaf-stormborn").kills, 121)

	-- Played on another computer meanwhile: its newer record is taken over
	-- too, not "corrected" back down to what this computer knew
	local other = Codec.Seal({ k = "m", author = "Olaf-Stormborn", ts = GetServerTime() + 3, kills = 200, deaths = 31,
		best = 6, points = 75, ach = 1 + 2 + 4 + 8 })
	world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(other.id), 1, 1, { other.wire })), "Kari-Frost")
	world:Advance(1)
	T.eq(st.kills, 200, "the other computer's kills")
	T.ok(st.earned[4], "and its achievements")
	T.eq(store:Member("olaf-stormborn").kills, 200)
	world:Fire("PARTY_KILL", "Player-1-00000001", "Player-1-0000DDDD")
	world:Advance(1)
	T.eq(store:Member("olaf-stormborn").kills, 201)

	-- A reload: the guild is bound before the totals module starts, and the
	-- totals still go out without any fight (here: changed while offline).
	local saved = BusinessMeetingDB
	saved.stats["olaf-stormborn"].kills = 230
	-- A guildmate saying anything at all is enough to know we are not alone
	local function hello(w, n)
		local someone = n.Codec.Seal({ k = "r", name = "Sylveth-Thorn", author = "Kari-Frost", mby = "Kari-Frost",
			ts = GetServerTime(), at = GetServerTime(), reason = "x" })
		w:Receive("BloodFeud", (n.Codec.EncodeUpdate(n.Codec.Bucket(someone.id), 1, 1, { someone.wire })), "Kari-Frost")
	end
	local world2 = Stub.Install()
	world2.roster = { { "Olaf-Stormborn", 3 }, { "Kari-Frost", 5 } }
	BusinessMeetingDB = saved
	local ns2 = world2:LoadAddon(T.root)
	world2:Fire("ADDON_LOADED", "BusinessMeeting")
	world2:Fire("PLAYER_LOGIN")
	world2:Advance(ns2.Progress.HOLD_SECONDS + 60)
	T.eq(ns2.session.store:Member("olaf-stormborn").kills, 201, "alone, nothing is written")
	T.eq(ns2.Progress:Roll()[1].kills, 230, "though my own row in the Ranks tab is current")
	hello(world2, ns2)
	world2:Advance(ns2.Progress.HOLD_SECONDS + 2 * ns2.Progress.PUBLISH_EVERY)
	T.eq(#world2.errors, 0, table.concat(world2.errors, " | "))
	T.eq(ns2.session.store:Member("olaf-stormborn").kills, 230, "published once a guildmate is around")

	-- A brand-new install with nothing to tell publishes nothing
	BusinessMeetingDB = nil
	local world3 = Stub.Install()
	world3.roster = { { "Olaf-Stormborn", 3 }, { "Kari-Frost", 5 } }
	local ns3 = world3:LoadAddon(T.root)
	world3:Fire("ADDON_LOADED", "BusinessMeeting")
	world3:Fire("PLAYER_LOGIN")
	world3:Advance(3)
	hello(world3, ns3)
	world3:Advance(ns3.Progress.HOLD_SECONDS + 2 * ns3.Progress.PUBLISH_EVERY)
	T.eq(ns3.session.store:Member("olaf-stormborn"), nil, "no empty record")
	T.eq(#ns3.Progress:Roll(), 1, "my own row is shown all the same")
	BusinessMeetingDB = keep
end)

T.test("game: bounty, radar and streak edge cases", function()
	local keep = BusinessMeetingDB
	BusinessMeetingDB = nil
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 }, { "Kari-Frost", 5 }, { "Astrid-Vale", 1 } }
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	local store, Codec, Progress = ns.session.store, ns.Codec, ns.Progress
	local ME = "Player-1-00000001"
	local function receive(rec, sender)
		world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(rec.id), 1, 1, { rec.wire })), sender)
		world:Advance(1)
	end
	local function enemy(first, surname, guid, more)
		local u = { name = first, surname = surname, guid = guid, isPlayer = true, enemy = true, faction = "Horde",
			class = 1, race = 2, level = 60 }
		for k, v in pairs(more or {}) do u[k] = v end
		return u
	end
	local function plate(n, unit)
		world.units["nameplate" .. n] = unit
		world:Fire(unit and "NAME_PLATE_UNIT_ADDED" or "NAME_PLATE_UNIT_REMOVED", "nameplate" .. n)
	end

	-- The dialog copes with stray spaces in the name
	ns.BountyDialog:Open({})
	ns.BountyDialog.frame.name:SetText("  morgash gorefist ")
	ns.BountyDialog.frame.points:SetText("20")
	ns.BountyDialog:Submit()
	T.ok(store:HasBounty("p", "morgash-gorefist"), "stored under the real name")

	-- A bounty on a member of a listed guild: the guild alert carries it
	local now = GetServerTime()
	receive(Codec.Seal({ k = "g", name = "Hostile Takeover", author = "Astrid-Vale", mby = "Astrid-Vale", ts = now,
		at = now, reason = "War" }), "Astrid-Vale")
	local MORG = enemy("Morgash", "Gorefist", "Player-1-0000EEEE", { guild = "Hostile Takeover" })
	local chatFrom = #world.chat + 1
	plate(1, MORG)
	T.ok(chatHas(world, "Hostile guild nearby", chatFrom))
	T.ok(chatHas(world, "Open contract: 20 points", chatFrom), "the guild alert mentions the bounty")
	-- and with guild alerts switched off, the bounty alert takes over
	ns.settings.guildAlerts = false
	world:Advance(61)
	chatFrom = #world.chat + 1
	world.units.target = MORG
	world:Fire("PLAYER_TARGET_CHANGED")
	T.ok(chatHas(world, "Open contract nearby", chatFrom), "bounty alert without the guild alert")
	ns.settings.guildAlerts = true

	-- With an enemy targeted, /feud bounty is about them, whatever is typed
	SlashCmdList.BUSINESSMEETING("bounty a fine axe")
	local mine = store:Get(Codec.BountyId("p", "morgash-gorefist", "olaf-stormborn"))
	T.eq(mine.reward, "a fine axe", "everything typed is the reward")
	T.eq(mine.points, 20, "points kept")
	T.eq(store:Get(Codec.BountyId("p", "a", "olaf-stormborn")), nil, "no bounty on a player called A")
	SlashCmdList.BUSINESSMEETING("bounty 25")
	mine = store:Get(mine.id)
	T.eq(mine.points, 25)
	T.eq(mine.reward, "a fine axe")
	world.units.target = nil
	-- reopening the dialog starts from what the bounty says now
	ns.BountyDialog:Open({ scope = "p", name = "Morgash-Gorefist" })
	T.eq(ns.BountyDialog.frame.points:GetText(), "25")
	T.eq(ns.BountyDialog.frame.reward:GetText(), "a fine axe")
	ns.BountyDialog.frame:Hide()
	noErrors(world)

	-- The radar: someone whose nameplate stays up is not "new" again, and
	-- lingers for a minute after it goes
	local fresh = 0
	ns:Listen("RADAR_NEW", function() fresh = fresh + 1 end)
	world:Advance(120)
	world.units.mouseover = MORG
	world:Fire("UPDATE_MOUSEOVER_UNIT")
	world.units.mouseover = nil
	T.eq(fresh, 0, "still the same enemy")
	world:Advance(90)
	T.eq(#ns.Radar:Visible(), 1, "on the radar for as long as the nameplate is up")
	plate(1, nil)
	world:Advance(30)
	T.eq(#ns.Radar:Visible(), 1, "lingers after the nameplate goes")
	world:Advance(40)
	T.eq(#ns.Radar:Visible(), 0, "and leaves a minute later")

	-- A bounty posted with only a first name applies to that first name
	now = GetServerTime()
	receive(Codec.Seal({ k = "b", scope = "p", name = "Grimtusk", author = "Kari-Frost", mby = "Kari-Frost", ts = now,
		at = now, points = 30, reward = "" }), "Kari-Frost")
	chatFrom = #world.chat + 1
	plate(2, enemy("Grimtusk", "Bloodaxe", "Player-1-0000AAAA"))
	T.ok(chatHas(world, "Open contract nearby", chatFrom), "first-name bounty alerts for Grimtusk Bloodaxe")
	world:Fire("PARTY_KILL", ME, "Player-1-0000AAAA")
	T.ok(store:Get(Codec.ClaimId("p", "grimtusk", "kari-frost", "olaf-stormborn")), "and pays out")
	chatFrom = #world.chat + 1
	SlashCmdList.BUSINESSMEETING("bounty Sylveth 5")
	T.ok(chatHas(world, "No surname given", chatFrom), "the poster is told what a first name means")

	-- A streak ends with any death, also one whose killer we never saw
	local st = Progress:Stats()
	world:Fire("PARTY_KILL", ME, "Player-1-0000AAAA")
	T.eq(st.streak, 2)
	world.recap = { { sourceName = "Somebody Unseen", timestamp = 900 } }
	world:Fire("PLAYER_DEAD")
	world:Advance(2)
	T.eq(st.streak, 0, "streak over")
	T.eq(st.deaths, 0, "but not a counted death to an enemy player")
	world:Fire("PARTY_KILL", ME, "Player-1-0000AAAA")
	T.eq(st.best, 2)
	T.ok(not st.earned[7], "no Hat Trick across a death")

	-- A first-name entry pinned to one character is not its namesakes
	SlashCmdList.BUSINESSMEETING("add zulrakka camping the graveyard")
	plate(3, enemy("Zulrakka", "Venomtongue", "Player-1-0000FFFF"))
	world:Advance(1)
	T.eq(store:Player("zulrakka").facts.guid, "Player-1-0000FFFF", "pinned")
	chatFrom = #world.chat + 1
	plate(4, enemy("Zulrakka", "Other", "Player-1-00001111"))
	world:Advance(1)
	T.ok(not chatHas(world, "Kill on Sight nearby", chatFrom), "no alert for the namesake")
	T.eq((ns.Radar.Tag(ns.Detect.Inspect("nameplate4"))), 0, "not Kill on Sight on the radar")
	T.eq((ns.Radar.Tag(ns.Detect.Inspect("nameplate3"))), 3, "the real one is")
	local listedKills = st.listedKills
	world:Fire("PARTY_KILL", ME, "Player-1-00001111")
	T.eq(st.listedKills, listedKills, "killing the namesake is not a listed kill")
	T.eq(ns.Feuds:Book()["zulrakka-other"].k, 1, "it is filed under their own name")
	world:Fire("PARTY_KILL", ME, "Player-1-0000FFFF")
	T.eq(st.listedKills, listedKills + 1, "killing the listed one is")
	noErrors(world)

	-- A bounty posted from the row of a first-name entry shows on that row
	local main = ns.MainFrame
	main:Show()
	world:Advance(1)
	main.selected = "zulrakka"
	main:OnBounty()
	T.eq(ns.BountyDialog.frame.name:GetText(), "Zulrakka Venomtongue")
	ns.BountyDialog:Submit()
	T.ok(store:HasBounty("p", "zulrakka-venomtongue"))
	world:Advance(1)
	local marked = false
	for _, row in ipairs(main.frame.rows) do
		if row.item and row.item.key == "zulrakka" then marked = row.cells[1]:GetText():find("Media\\coin", 1, true) ~= nil end
	end
	T.ok(marked, "the row shows the bounty mark")
	noErrors(world)

	-- Guildmates' totals changing must not replay the alert for whoever is
	-- standing in front of us
	world:Advance(61)
	chatFrom = #world.chat + 1
	receive(Codec.Seal({ k = "m", author = "Kari-Frost", ts = GetServerTime(), kills = 3, deaths = 1, best = 2,
		points = 0, ach = 1 }), "Kari-Frost")
	world:Advance(2)
	T.ok(not chatHas(world, "Kill on Sight nearby", chatFrom), "no alert replay for a guildmate's kill")

	-- An enemy whose level the client hides is far above us
	world.units.focus = enemy("Gorrak", "Skullsplitter", "Player-1-00002222", { level = -1 })
	world:Fire("PLAYER_FOCUS_CHANGED")
	T.ok(ns.Detect.Inspect("focus").high)
	world:Fire("PARTY_KILL", ME, "Player-1-00002222")
	T.ok(st.earned[22], "Giant Slayer")
	noErrors(world)
	BusinessMeetingDB = keep
end)

T.test("game: an officer edits the ranks", function()
	local keep = BusinessMeetingDB
	BusinessMeetingDB = nil
	local world = Stub.Install()
	world.myRank = 1
	world.roster = { { "Olaf-Stormborn", 1 }, { "Kari-Frost", 5 } }
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	local store = ns.session.store
	T.ok(ns.Roster.AmOfficer())

	ns.RanksDialog:Open()
	local f = ns.RanksDialog.frame
	T.ok(f:IsShown())
	T.eq(f.rows[2].title:GetText(), "Associate", "starts from the built-in ranks")
	-- a title without a kill count is not dropped silently
	f.rows[11].title:SetText("Legend")
	f.rows[11].kills:SetText("")
	local chatFrom = #world.chat + 1
	ns.RanksDialog:Submit()
	T.ok(chatHas(world, "needs a number of kills", chatFrom))
	T.ok(f:IsShown(), "the dialog stays open")
	T.eq(store:Tiers()[11], nil)
	f.rows[11].kills:SetText("3000")
	f.rows[2].title:SetText("Bloodhound")
	ns.RanksDialog:Submit()
	T.ok(not f:IsShown())
	T.eq(store:Tiers()[11].title, "Legend")
	T.eq(store:Tiers()[2].title, "Bloodhound")
	T.eq(store:Tiers()[1], nil, "unchanged ranks are not written")
	T.eq(ns.Progress.RankFor(5000, ns.Progress.Ladder(store)).title, "Legend")

	chatFrom = #world.chat + 1
	SlashCmdList.BUSINESSMEETING("rank set 13 5 Foo")
	T.ok(chatHas(world, "/bm rank set <1-12>", chatFrom), "out-of-range tier explains itself")
	SlashCmdList.BUSINESSMEETING("rank set 3 30 Marauder")
	T.eq(store:Tiers()[3].kills, 30)
	T.eq(#world.errors, 0, table.concat(world.errors, " | "))
	BusinessMeetingDB = keep
end)

T.test("game: gold bounties, payment by mail and trade, and dishonor", function()
	local keep = BusinessMeetingDB
	BusinessMeetingDB = nil
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 }, { "Kari-Frost", 5 }, { "Astrid-Vale", 1 } }
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	noErrors(world)
	local store, Codec, Progress, Debts = ns.session.store, ns.Codec, ns.Progress, ns.Debts
	local ME, GOLD = "Player-1-00000001", 10000
	local function receive(rec, sender)
		world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(rec.id), 1, 1, { rec.wire })), sender)
		world:Advance(1)
	end
	local function enemy(first, surname, guid)
		return { name = first, surname = surname, guid = guid, isPlayer = true, enemy = true, faction = "Horde",
			class = 1, race = 2, level = 60 }
	end
	local function bountyBy(author, name, points, gold)
		local now = GetServerTime()
		return Codec.Seal({ k = "b", scope = "p", name = name, author = author, mby = author, ts = now, at = now,
			points = points, gold = gold, reward = "" })
	end
	local function mark(bounty, role, state, author)
		return Codec.Seal({ k = "d", scope = "p", key = bounty.key, poster = bounty.author, role = role, author = author,
			ts = GetServerTime(), state = state })
	end
	local function debt(bounty) return store:Debt(store:Get(bounty.id), GetServerTime()) end
	local function mailbox()
		world:Fire("MAIL_SHOW")
		world:Fire("MAIL_INBOX_UPDATE")
		world:Advance(1)
	end

	-- A guildmate posts 50 gold on Morgash; my killing blow wins it
	local onMorgash = bountyBy("Kari-Frost", "Morgash-Gorefist", 25, 50)
	local chatFrom = #world.chat + 1
	receive(onMorgash, "Kari-Frost")
	T.ok(chatHas(world, "25 points and 50 gold to the first kill", chatFrom), "announced with its gold")
	world.units.target = enemy("Morgash", "Gorefist", "Player-1-0000EEEE")
	world:Fire("PLAYER_TARGET_CHANGED")
	T.ok(chatHas(world, "Open contract: 25 points and 50 gold", chatFrom), "the alert names the gold")
	T.eq(BusinessMeetingAlertBanner.title:GetText(), "OPEN CONTRACT")
	local contractTile = BusinessMeetingAlertBanner.tiles[1]
	T.ok(contractTile:IsShown() and not BusinessMeetingAlertBanner.tiles[2]:IsShown(), "one tile: the contract")
	T.eq(contractTile.gold, 50, "the gold on the tile")
	T.eq(contractTile.points, 25)
	T.ok(contractTile.value:GetText():find("Media\\coin", 1, true), "with a coin, not the letter g")
	chatFrom = #world.chat + 1
	world:Fire("PARTY_KILL", ME, "Player-1-0000EEEE")
	world:Advance(1)
	noErrors(world)
	T.eq(store:Winner(store:Get(onMorgash.id)).author, "Olaf-Stormborn", "I won it")
	T.ok(chatHas(world, "You fulfilled the contract on Morgash Gorefist. Kari Frost owes you 50 gold", chatFrom))
	local st = Progress:Stats()
	T.eq(st.points, 25)
	world:Fire("PARTY_KILL", ME, "Player-1-0000EEEE")
	T.eq(st.points, 25, "a won gold bounty pays no second time")
	T.eq(ns.Bounties:Line(ns.Detect.Inspect("target")), nil, "and is no longer a bounty to be had")
	T.eq(debt(onMorgash).state, "owed")

	-- She sends it by mail; I am told, and my mailbox confirms it
	chatFrom = #world.chat + 1
	receive(mark(onMorgash, "s", "s", "Kari-Frost"), "Kari-Frost")
	T.ok(chatHas(world, "Kari Frost says the 50 gold for the contract on Morgash Gorefist is sent", chatFrom))
	T.eq(debt(onMorgash).state, "sent")
	world.inbox = { { sender = "Thrall", subject = "Hello", money = 0 },
		{ sender = "Kari Frost", subject = "Bounty", money = 50 * GOLD } }
	chatFrom = #world.chat + 1
	mailbox()
	noErrors(world)
	T.eq(debt(onMorgash).state, "paid", "the gold in the inbox closes the debt")
	T.ok(chatHas(world, "Received 50 gold from Kari Frost", chatFrom))
	local receipt = store:Get(Codec.MarkId("p", "morgash-gorefist", "kari-frost", "w", "olaf-stormborn"))
	T.eq(receipt.state, "r", "my receipt is on record")

	-- The same mail, still in the inbox, does not pay for a second debt
	local onZul = bountyBy("Kari-Frost", "Zulrakka-Venomtongue", 10, 50)
	receive(onZul, "Kari-Frost")
	world.units.focus = enemy("Zulrakka", "Venomtongue", "Player-1-0000FFFF")
	world:Fire("PLAYER_FOCUS_CHANGED")
	world:Fire("PARTY_KILL", ME, "Player-1-0000FFFF")
	world:Advance(1)
	T.eq(debt(onZul).state, "owed")
	mailbox()
	T.eq(debt(onZul).state, "owed", "one mail, one debt")
	world.inbox[#world.inbox + 1] = { sender = "Kari-Frost", subject = "Bounty", money = 50 * GOLD }
	mailbox()
	T.eq(debt(onZul).state, "paid", "a second mail pays the second debt")
	T.eq(Debts.stats.unreadable, 0)

	-- Now I am the poster. A slash command with gold, and Kari wins it
	world.units.target, world.units.focus = nil, nil
	SlashCmdList.BUSINESSMEETING("bounty grimtusk-bloodaxe 20 30g for the camping")
	local mine = T.ok(store:Get(Codec.BountyId("p", "grimtusk-bloodaxe", "olaf-stormborn")))
	T.eq(mine.points, 20)
	T.eq(mine.gold, 30)
	T.eq(mine.reward, "for the camping")
	local function claimBy(bounty, who)
		return Codec.Seal({ k = "k", scope = "p", key = bounty.key, poster = bounty.author, author = who,
			ts = GetServerTime(), count = 1 })
	end
	chatFrom = #world.chat + 1
	receive(claimBy(mine, "Kari-Frost"), "Kari-Frost")
	T.ok(chatHas(world, "Kari Frost fulfilled your contract on Grimtusk Bloodaxe. You owe them 30 gold", chatFrom))
	T.eq(debt(mine).state, "owed")
	T.ok(not ns:RemoveBounty(mine.id), "a won bounty cannot be taken down unpaid")
	SlashCmdList.BUSINESSMEETING("bounty grimtusk-bloodaxe 20 1g")
	T.eq(store:Get(mine.id).gold, 30, "nor have its gold lowered")
	chatFrom = #world.chat + 1
	SlashCmdList.BUSINESSMEETING("debts")
	T.ok(chatHas(world, "you owe Kari Frost 30 gold for the contract on Grimtusk Bloodaxe (47 h left)", chatFrom))

	-- Too little gold in the mail does not count; the full amount does
	_G.SetSendMailMoney(10 * GOLD)
	_G.SendMail("Kari Frost", "part", "")
	world:Fire("MAIL_SEND_SUCCESS")
	T.eq(debt(mine).state, "owed")
	chatFrom = #world.chat + 1
	_G.SetSendMailMoney(30 * GOLD)
	_G.SendMail("kari-frost", "bounty", "")
	world:Fire("MAIL_SEND_SUCCESS")
	noErrors(world)
	T.eq(debt(mine).state, "sent", "my mail stops the clock")
	T.ok(chatHas(world, "Payment noted: 30 gold to Kari Frost", chatFrom))
	chatFrom = #world.chat + 1
	receive(mark(mine, "w", "r", "Kari-Frost"), "Kari-Frost")
	T.eq(debt(mine).state, "paid")
	T.ok(chatHas(world, "Kari Frost has your 30 gold", chatFrom))
	T.ok(ns:RemoveBounty(mine.id), "paid: now it can come down")

	-- Paying in a trade, seen from the poster's side
	SlashCmdList.BUSINESSMEETING("bounty vexara-nightfall 5 10 gold")
	local onVex = T.ok(store:Get(Codec.BountyId("p", "vexara-nightfall", "olaf-stormborn")))
	T.eq(onVex.gold, 10, "'10 gold' is gold too")
	T.eq(onVex.points, 5)
	receive(claimBy(onVex, "Kari-Frost"), "Kari-Frost")
	world.units.NPC = { name = "Kari", surname = "Frost", guid = "Player-1-00000002", isPlayer = true, faction = "Alliance" }
	world:Fire("TRADE_SHOW")
	world.tradeGive, world.tradeGet = 10 * GOLD, 0
	world:Fire("TRADE_ACCEPT_UPDATE", 1, 0)
	world:Fire("TRADE_ACCEPT_UPDATE", 1, 1)
	world.money = world.money - 10 * GOLD
	world:Fire("TRADE_CLOSED")
	world:Fire("UI_INFO_MESSAGE", 1, "Trade complete.")
	world:Advance(3)
	noErrors(world)
	T.eq(debt(onVex).state, "sent", "the trade is noticed")
	T.eq(Debts.stats.trades, 1)

	-- ...and from the winner's side, where the client does not say "complete"
	local onSyl = bountyBy("Kari-Frost", "Sylveth-Thorn", 10, 20)
	receive(onSyl, "Kari-Frost")
	world.units.target = enemy("Sylveth", "Thorn", "Player-1-00003333")
	world:Fire("PLAYER_TARGET_CHANGED")
	world:Fire("PARTY_KILL", ME, "Player-1-00003333")
	world:Advance(1)
	T.eq(debt(onSyl).state, "owed")
	local complete = _G.ERR_TRADE_COMPLETE
	_G.ERR_TRADE_COMPLETE = nil
	-- a cancelled trade changes nothing
	world:Fire("TRADE_SHOW")
	world.tradeGive, world.tradeGet = 0, 20 * GOLD
	world:Fire("TRADE_ACCEPT_UPDATE", 0, 1)
	world:Fire("TRADE_CLOSED")
	world:Advance(3)
	T.eq(debt(onSyl).state, "owed")
	world:Fire("TRADE_SHOW")
	world:Fire("TRADE_ACCEPT_UPDATE", 1, 1)
	world.money = world.money + 20 * GOLD
	world:Fire("TRADE_CLOSED")
	world:Fire("TRADE_CLOSED")
	world:Advance(3)
	_G.ERR_TRADE_COMPLETE = complete
	noErrors(world)
	T.eq(debt(onSyl).state, "paid", "my purse grew by what was offered: received")
	world.units.NPC, world.units.target = nil, nil

	-- The dialog takes gold, and reopens with it
	ns.BountyDialog:Open({ scope = "p", name = "Dravok-Ashmane" })
	ns.BountyDialog.frame.points:SetText("15")
	ns.BountyDialog.frame.gold:SetText("75")
	ns.BountyDialog:Submit()
	local onDravok = T.ok(store:Get(Codec.BountyId("p", "dravok-ashmane", "olaf-stormborn")))
	T.eq(onDravok.gold, 75)
	ns.BountyDialog:Open({ scope = "p", name = "Dravok-Ashmane" })
	T.eq(ns.BountyDialog.frame.gold:GetText(), "75")
	ns.BountyDialog.frame:Hide()

	-- The board: status, and the winner's buttons
	local onGor = bountyBy("Kari-Frost", "Gorrak-Skullsplitter", 10, 40)
	receive(onGor, "Kari-Frost")
	world.units.target = enemy("Gorrak", "Skullsplitter", "Player-1-00002222")
	world:Fire("PLAYER_TARGET_CHANGED")
	world:Fire("PARTY_KILL", ME, "Player-1-00002222")
	world:Advance(1)
	world.units.target = nil
	local main = ns.MainFrame
	main:Show("b")
	world:Advance(1)
	noErrors(world)
	local function rowOf(id)
		for _, row in ipairs(main.frame.rows) do
			if row:IsShown() and row.item and row.item.key == id then return row end
		end
	end
	local row = T.ok(rowOf(onGor.id), "the won bounty is on the board")
	T.ok(row.cells[3]:GetText():find("40", 1, true) and row.cells[3]:GetText():find("Media\\coin", 1, true), "gold column")
	T.ok(row.cells[6]:GetText():find("Fulfilled by Olaf Stormborn", 1, true), row.cells[6]:GetText())
	T.ok(row.cells[6]:GetText():find("payment due, 47 h left", 1, true), row.cells[6]:GetText())
	row.scripts.OnEnter(row)
	row.scripts.OnLeave(row)
	T.ok(rowOf(onDravok.id).cells[6]:GetText():find("first kill takes the gold", 1, true), "an open gold bounty says so")
	main.selected = onGor.id
	main:UpdateActions()
	T.ok(main.frame.edit:IsShown() and main.frame.edit:IsEnabled(), "the winner can mark it paid")
	T.eq(main.frame.edit.label:GetText(), "MARK AS PAID")
	T.ok(not main.frame.bounty:IsEnabled(), "nothing to dispute before she says it is sent")
	T.ok(not main.frame.removeAll:IsShown(), "settling is for officers")
	receive(mark(onGor, "s", "s", "Kari-Frost"), "Kari-Frost")
	main:UpdateActions()
	T.ok(main.frame.bounty:IsEnabled())
	main.frame.bounty:Click()
	T.eq(debt(onGor).state, "disputed", "'Not received' reopens it")
	main:UpdateActions()
	main.frame.edit:Click()
	T.eq(debt(onGor).state, "paid", "'Mark as paid' closes it")
	noErrors(world)

	-- 48 hours pass. Kari never paid for Hakkar: she is Dishonored
	local onHak = bountyBy("Kari-Frost", "Hakkar-Bloodtusk", 10, 60)
	receive(onHak, "Kari-Frost")
	world.units.target = enemy("Hakkar", "Bloodtusk", "Player-1-00004444")
	world:Fire("PLAYER_TARGET_CHANGED")
	world:Fire("PARTY_KILL", ME, "Player-1-00004444")
	world:Advance(1)
	world.units.target = nil
	-- ...and neither did I for Dravok, whom Kari killed
	receive(claimBy(onDravok, "Kari-Frost"), "Kari-Frost")
	world:Advance(Debts.CHECK_EVERY + 1) -- the watch has seen both debts in time
	T.eq(Debts:Dishonor("kari-frost"), nil)
	chatFrom = #world.chat + 1
	world.epoch = world.epoch + 48 * 3600 + 120
	world:Advance(Debts.CHECK_EVERY + 1)
	noErrors(world)
	T.ok(debt(onHak).late and debt(onDravok).late)
	T.ok(chatHas(world, "Kari Frost is now |cffff8a80blacklisted|r: 60 gold owed to Olaf Stormborn", chatFrom), "the guild hears of it")
	T.ok(chatHas(world, "You are |cffff8a80blacklisted|r: the 75 gold you owe Kari Frost", chatFrom), "and so do I, of mine")
	T.eq(Debts:Dishonor("kari-frost").gold, 60)
	local kari, me
	for _, m in ipairs(Progress:Roll()) do
		if m.key == "kari-frost" then kari = m elseif m.me then me = m end
	end
	T.eq(kari, nil, "Kari has published no totals, so no row") -- her disgrace shows where she is shown:
	world.units.mouseover = { name = "Kari", surname = "Frost", guid = "Player-1-00000002", isPlayer = true,
		faction = "Alliance", class = 4, race = 1, level = 60, guildmate = true }
	world.tooltipUnit = "mouseover"
	GameTooltip.lines = {}
	world.tooltipHook(GameTooltip)
	T.ok(table.concat(GameTooltip.lines, "\n"):find("Blacklisted|r (owes 60 gold to Olaf Stormborn)", 1, true), "in her tooltip")
	T.ok(me.dishonored, "my own row is marked")
	main:SetTab("m")
	world:Advance(1)
	local mineRow
	for _, r in ipairs(main.frame.rows) do
		if r:IsShown() and r.item and r.item.me then mineRow = r end
	end
	T.ok(mineRow.cells[2]:GetText():find("Blacklisted", 1, true), "no rank while in disgrace")
	T.ok(mineRow.cells[6]:GetText():find("|r", 1, true) and mineRow.cells[6]:GetText():find("0", 1, true), "bounty points count for nothing")
	mineRow.scripts.OnEnter(mineRow)
	mineRow.scripts.OnLeave(mineRow)
	chatFrom = #world.chat + 1
	SlashCmdList.BUSINESSMEETING("bounty someone-else 5")
	T.eq(store:Get(Codec.BountyId("p", "someone-else", "olaf-stormborn")), nil, "no new bounties while Dishonored")
	T.ok(chatHas(world, "pay the 75 gold you owe Kari Frost", chatFrom))
	noErrors(world)

	-- Paying, even late, clears my name
	_G.SetSendMailMoney(75 * GOLD)
	_G.SendMail("Kari Frost", "sorry", "")
	world:Fire("MAIL_SEND_SUCCESS")
	T.eq(debt(onDravok).state, "sent")
	T.eq(Debts:Dishonor("olaf-stormborn"), nil, "paid up: no longer Dishonored")
	SlashCmdList.BUSINESSMEETING("bounty someone-else 5")
	T.ok(store:Get(Codec.BountyId("p", "someone-else", "olaf-stormborn")), "and bounties can be posted again")

	-- An officer settles Kari's debt: her name is cleared too
	chatFrom = #world.chat + 1
	receive(mark(onHak, "o", "o", "Astrid-Vale"), "Astrid-Vale")
	T.eq(debt(onHak).state, "settled")
	T.eq(Debts:Dishonor("kari-frost"), nil)
	T.ok(chatHas(world, "Astrid Vale settled the debt for the contract on Hakkar Bloodtusk", chatFrom))
	-- A member's attempt to settle is refused
	local onLast = bountyBy("Kari-Frost", "Morgash-Gorefist", 5, 5)
	receive(Codec.Seal({ k = "B", scope = "p", name = "Morgash-Gorefist", author = "Kari-Frost", mby = "Kari-Frost",
		ts = GetServerTime(), del = true }), "Kari-Frost")
	onLast.ts = GetServerTime() + 1
	onLast.at = onLast.ts
	receive(Codec.Seal(onLast), "Kari-Frost")
	world.units.target = enemy("Morgash", "Gorefist", "Player-1-0000EEEE")
	world:Fire("PLAYER_TARGET_CHANGED")
	world:Fire("PARTY_KILL", ME, "Player-1-0000EEEE")
	world:Advance(1)
	T.eq(debt(onLast).state, "owed", "posted again after being paid: a fresh debt")
	receive(mark(onLast, "o", "o", "Kari-Frost"), "Kari-Frost")
	T.eq(debt(onLast).state, "owed", "the debtor cannot settle her own debt")
	T.eq(ns:SettleDebt(onLast.id, true), nil, "nor can I, as a member")
	noErrors(world)
	BusinessMeetingDB = keep
end)

T.test("game: an officer settles a debt from the board", function()
	local keep = BusinessMeetingDB
	BusinessMeetingDB = nil
	local world = Stub.Install()
	world.myRank = 1
	world.roster = { { "Olaf-Stormborn", 1 }, { "Kari-Frost", 5 }, { "Per-Hauk", 5 } }
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	local store, Codec = ns.session.store, ns.Codec
	local now = GetServerTime()
	local function receive(rec, sender)
		world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(rec.id), 1, 1, { rec.wire })), sender)
		world:Advance(1)
	end
	local b = Codec.Seal({ k = "b", scope = "p", name = "Grimtusk-Bloodaxe", author = "Kari-Frost", mby = "Kari-Frost",
		ts = now, at = now, points = 10, gold = 50, reward = "" })
	receive(b, "Kari-Frost")
	receive(Codec.Seal({ k = "k", scope = "p", key = b.key, poster = b.author, author = "Per-Hauk", ts = now + 2,
		count = 1 }), "Per-Hauk")
	local main = ns.MainFrame
	main:Show("b")
	world:Advance(1)
	main.selected = b.id
	main:UpdateActions()
	T.ok(not main.frame.edit:IsShown(), "neither poster nor winner: no say of my own")
	T.ok(main.frame.removeAll:IsShown() and main.frame.removeAll:IsEnabled(), "but an officer can settle")
	T.eq(main.frame.removeAll.label:GetText(), "SETTLE THE DEBT (OFFICER)")
	main.frame.removeAll:Click()
	T.eq(store:Debt(store:Get(b.id), GetServerTime()).state, "settled")
	main:UpdateActions()
	T.ok(not main.frame.removeAll:IsEnabled(), "nothing left to settle")
	-- An officer can also take a won, unpaid bounty down, which cancels the debt
	local b2 = Codec.Seal({ k = "b", scope = "p", name = "Vexara-Nightfall", author = "Kari-Frost", mby = "Kari-Frost",
		ts = now, at = now, points = 10, gold = 5, reward = "" })
	receive(b2, "Kari-Frost")
	receive(Codec.Seal({ k = "k", scope = "p", key = b2.key, poster = b2.author, author = "Per-Hauk", ts = now + 2,
		count = 1 }), "Per-Hauk")
	T.ok(ns:RemoveBounty(b2.id))
	T.eq(#store:Debts(GetServerTime()), 1, "only the settled one is left")
	T.eq(#world.errors, 0, table.concat(world.errors, " | "))
	BusinessMeetingDB = keep
end)

T.test("game: who in the guild runs the addon", function()
	local keep = BusinessMeetingDB
	BusinessMeetingDB = nil
	local world = Stub.Install()
	-- name, rank, online
	world.roster = { { "Olaf-Stormborn", 3, true }, { "Kari-Frost", 5, true }, { "Per-Hauk", 5, false },
		{ "Astrid-Vale", 1, true }, { "Ingrid-Dahl", 5, true }, { "Bjorn-Ironside", 0, false } }
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	local Codec, Users = ns.Codec, ns.Users
	local function presences()
		local n, last = 0, nil
		for _, m in ipairs(world.sent) do
			if m.prefix == "BloodFeudS" and m.text:sub(1, 1) == "P" then n, last = n + 1, m.text end
		end
		return n, last
	end

	-- Alone so far: the list is me
	local sum, list = Users:Summary()
	T.eq(sum.have, 1)
	T.eq(sum.total, 6, "guild size from the roster")
	T.ok(list[1].me)
	T.eq(list[1].version, "test")

	-- Shortly after login this copy says it is here
	T.eq(presences(), 0)
	world:Advance(Users.LOGIN_DELAY[2] + 6)
	local count, frame = presences()
	T.eq(count, 1, "one presence frame after login")
	local mine = T.ok(Codec.DecodePresence(frame))
	T.eq(mine.version, "test")
	T.eq(mine.proto, Codec.PROTO)
	T.ok(not mine.ask)

	-- Guildmates report in: one current, one newer, and one too old to say so
	world:Receive("BloodFeudS", Codec.EncodePresence("v0.3.1", Codec.PROTO), "Kari-Frost")
	world:Receive("BloodFeudS", Codec.EncodePresence("v0.9.0", Codec.PROTO + 1), "Astrid-Vale")
	world:Receive("BloodFeud", "H" .. ns.Util.Enc(2) .. "whatever an old hello looked like", "Per-Hauk")
	world:Receive("BloodFeudS", "P1" .. string.rep("x", 200), "Ingrid-Dahl") -- garbage is not a user
	world:Advance(1)
	noErrors(world)
	sum, list = Users:Summary()
	T.eq(sum.have, 4, "me and three others")
	T.eq(sum.online, 3, "the roster says Per is offline")
	T.eq(sum.old, 1)
	T.eq(sum.new, 1)
	local by = {}
	for _, u in ipairs(list) do by[u.key] = u end
	T.eq(by["kari-frost"].version, "v0.3.1")
	T.eq(by["kari-frost"].standing, "ok")
	T.ok(by["kari-frost"].online)
	T.eq(by["astrid-vale"].standing, "new")
	T.eq(by["per-hauk"].version, "v0.2.0", "known by the protocol their sync speaks")
	T.eq(by["per-hauk"].standing, "old")
	T.ok(not by["per-hauk"].online)
	T.eq(by["ingrid-dahl"], nil)
	T.ok(list[#list].key == "per-hauk", "offline members come last")

	-- Someone asks who is here: we answer, once
	count = presences()
	world:Advance(Users.REPLY_GAP)
	world:Receive("BloodFeudS", Codec.EncodePresence("v0.3.1", Codec.PROTO, true), "Kari-Frost")
	world:Receive("BloodFeudS", Codec.EncodePresence("v0.3.1", Codec.PROTO, true), "Ingrid-Dahl")
	world:Advance(Users.REPLY_DELAY[2] + 2)
	T.eq(presences(), count + 1, "one answer to two questions")
	T.ok(Users:Summary().have == 5, "and Ingrid is on the list now")

	-- The Addon tab, its summary and the Refresh button
	local main = ns.MainFrame
	main:Show("u")
	world:Advance(1)
	noErrors(world)
	T.eq(#main.items, 5)
	local notice = main.frame.notice:GetText()
	T.ok(notice:find("5 of 6 guild members have Business Meeting", 1, true), notice)
	T.ok(notice:find("4 online now", 1, true), notice)
	T.ok(notice:find("1 need to update", 1, true), notice)
	local text = {}
	for _, row in ipairs(main.frame.rows) do
		if row:IsShown() then
			text[#text + 1] = row.cells[1]:GetText() .. " " .. row.cells[2]:GetText() .. " " .. row.cells[3]:GetText()
			row.scripts.OnEnter(row)
			row.scripts.OnLeave(row)
		end
	end
	text = table.concat(text, "\n")
	T.ok(text:find("Per Hauk v0.2.0", 1, true), text)
	T.ok(text:find("needs to update", 1, true))
	T.ok(text:find("newer than yours", 1, true))
	T.ok(main.frame.status:GetText():find("3 guildmates on comms", 1, true), main.frame.status:GetText())
	T.eq(main.frame.add.label:GetText(), "REFRESH")
	count = presences()
	world:Advance(Users.ASK_GAP)
	local chatFrom = #world.chat + 1
	main.frame.add:Click()
	local after, asked = presences()
	T.eq(after, count + 1)
	T.ok(Codec.DecodePresence(asked).ask, "Refresh asks everyone to report in")
	main.frame.add:Click()
	T.eq(presences(), after, "but not twice in a minute")
	T.ok(chatHas(world, "Asked a moment ago", chatFrom))
	chatFrom = #world.chat + 1
	SlashCmdList.BUSINESSMEETING("users")
	T.ok(chatHas(world, "5 of 6 guild members have Business Meeting, 4 online now.", chatFrom))
	T.ok(chatHas(world, "Per Hauk  v0.2.0  offline · needs to update", chatFrom))
	noErrors(world)

	-- Per updates: his next presence says so
	world:Receive("BloodFeudS", Codec.EncodePresence("v0.3.1", Codec.PROTO), "Per-Hauk")
	world:Advance(1)
	T.eq(Users:Summary().old, 0)
	-- ...and if he is later heard syncing on another protocol, the version
	-- we knew no longer holds
	world:Receive("BloodFeud", "H" .. ns.Util.Enc(1) .. "an even older hello", "Per-Hauk")
	world:Advance(1)
	for _, u in ipairs(Users:List()) do
		if u.key == "per-hauk" then T.eq(u.version, "v0.1.0", "not the v0.3.1 he said before") end
	end
	world:Receive("BloodFeudS", Codec.EncodePresence("v0.3.1", Codec.PROTO), "Per-Hauk")
	world:Advance(1)

	-- The list is remembered across sessions, and follows who is in the guild
	local saved = BusinessMeetingDB
	local world2 = Stub.Install()
	world2.roster = { { "Olaf-Stormborn", 3, true }, { "Kari-Frost", 5, false }, { "Per-Hauk", 5, true } } -- two have left
	BusinessMeetingDB = saved
	local ns2 = world2:LoadAddon(T.root)
	world2:Fire("ADDON_LOADED", "BusinessMeeting")
	world2:Fire("PLAYER_LOGIN")
	world2:Advance(3)
	local sum2, list2 = ns2.Users:Summary()
	T.eq(sum2.have, 3, "Kari and Per remembered; Astrid and Ingrid left the guild")
	T.eq(sum2.total, 3)
	T.eq(sum2.online, 2, "me and Per")
	by = {}
	for _, u in ipairs(list2) do by[u.key] = u end
	T.ok(by["kari-frost"] and not by["kari-frost"].online)
	-- ...and forgets those not heard from in two months
	world2.epoch = world2.epoch + (ns2.Users.KEEP_DAYS + 1) * 86400
	T.eq(ns2.Users:Summary().have, 1)
	T.eq(#world2.errors, 0, table.concat(world2.errors, " | "))
	BusinessMeetingDB = keep
end)

T.test("game: an enemy who targets you", function()
	local keep = BusinessMeetingDB
	BusinessMeetingDB = nil
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 }, { "Kari-Frost", 5 } }
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	local Codec, Targeting = ns.Codec, ns.Targeting
	local function receive(rec, sender)
		world:Receive("BloodFeud", (Codec.EncodeUpdate(Codec.Bucket(rec.id), 1, 1, { rec.wire })), sender)
		world:Advance(1)
	end
	local MORG = { name = "Morgash", surname = "Gorefist", guid = "Player-1-0000EEEE", isPlayer = true, enemy = true,
		faction = "Horde", class = 1, race = 2, level = 60, guild = "Hostile Takeover" }
	local ZUL = { name = "Zulrakka", surname = "Venomtongue", guid = "Player-1-0000FFFF", isPlayer = true, enemy = true,
		faction = "Horde", class = 8, race = 8, level = 54 }

	-- Two enemies on screen, neither looking at me
	world.units.nameplate1, world.units.nameplate2 = MORG, ZUL
	world:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	world:Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
	ZUL.targets = MORG -- busy with someone else
	world:Advance(2)
	noErrors(world)
	T.eq(Targeting:Count(), 0)
	T.ok(not chatHas(world, "Targeting you"))

	-- Morgash targets me: alert, sound, radar and nameplate
	local chatFrom = #world.chat + 1
	MORG.targets = "player"
	world:Advance(1)
	noErrors(world)
	T.ok(Targeting:Is("morgash-gorefist"))
	T.eq(Targeting:Count(), 1)
	T.ok(chatHas(world, "Targeting you:|r |cfffff468Morgash Gorefist|r (60 Orc Rogue) |cffffb347<Hostile Takeover>|r.", chatFrom),
		world.chat[#world.chat])
	T.ok(chatHas(world, "Not on the hit list", chatFrom), "says he is not Kill on Sight")
	T.ok(BusinessMeetingAlertBanner:IsShown())
	T.eq(BusinessMeetingAlertBanner.title:GetText(), "TARGETING YOU")
	T.eq(world.lastSound, 8960)
	local visible = ns.Radar:Visible()
	T.eq(visible[1].info.key, "morgash-gorefist", "whoever has me targeted is first on the radar")
	T.ok(visible[1].targeting and not visible[2].targeting)
	T.ok(_G.BusinessMeetingRadarFrame.rows[1].tag:GetText():find("ON YOU", 1, true))
	T.ok(_G.BusinessMeetingRadarFrame.title:GetText():find("1 ON YOU", 1, true), _G.BusinessMeetingRadarFrame.title:GetText())
	T.ok(ns.Nameplates.aims.nameplate1, "a cross on his nameplate")
	T.eq(ns.Nameplates.aims.nameplate2, nil)
	local row = _G.BusinessMeetingRadarFrame.rows[1]
	row.scripts.OnEnter(row)
	row.scripts.OnLeave(row)
	noErrors(world)

	-- He looks away and back within the cooldown: marked again, but no new alert
	chatFrom = #world.chat + 1
	MORG.targets = nil
	world:Advance(1)
	T.eq(Targeting:Count(), 0)
	T.eq(ns.Nameplates.aims.nameplate1, nil, "the cross comes off")
	MORG.targets = "player"
	world:Advance(1)
	T.ok(Targeting:Is("morgash-gorefist"))
	T.ok(not chatHas(world, "Targeting you", chatFrom), "no repeat within the cooldown")

	-- Now he is Kill on Sight, with a history: the next alert says so
	MORG.targets = nil
	world:Advance(1)
	SlashCmdList.BUSINESSMEETING("add morgash-gorefist Ganked the whole raid")
	local score = Codec.Seal({ k = "c", key = "morgash-gorefist", author = "Kari-Frost", ts = GetServerTime(), kills = 3,
		deaths = 7 })
	receive(score, "Kari-Frost")
	world.recap = { { sourceGUID = "Player-1-0000EEEE", timestamp = 77 } }
	world:Fire("PLAYER_DEAD")
	world:Advance(Targeting.COOLDOWN + 2)
	chatFrom = #world.chat + 1
	MORG.targets = "player"
	world:Advance(1)
	noErrors(world)
	T.ok(chatHas(world, "Targeting you", chatFrom), "alerts again after the cooldown")
	T.ok(chatHas(world, "Kill on Sight|r: “Ganked the whole raid”", chatFrom), "says he is Kill on Sight, and why")
	T.ok(chatHas(world, "Against the guild: kills 8, deaths 3", chatFrom), "the guild's score against him")
	T.ok(chatHas(world, "Against you: kills 1, deaths 0", chatFrom), "and my own")
	-- the banner says the same with a badge and two tiles instead of sentences
	local banner = BusinessMeetingAlertBanner
	T.ok(banner.badge:IsShown(), "Kill on Sight badge")
	T.eq(banner.tiles[1].kills, 3, "guild record: kills")
	T.eq(banner.tiles[1].deaths, 8, "guild record: deaths")
	T.eq(banner.tiles[2].kills, 0, "my own record: kills")
	T.eq(banner.tiles[2].deaths, 1, "my own record: deaths")
	T.ok(not banner.wide:IsShown())
	local about = Targeting:Dossier(ns.Detect.Inspect("nameplate1"))
	T.eq(about.deaths, 8)
	T.eq(about.kills, 3)
	T.eq(about.myDeaths, 1)
	T.ok(_G.BusinessMeetingRadarFrame.rows[1].tag:GetText():find("Media\\skull", 1, true), "the skull stays next to ON YOU")

	-- Zulrakka targets me while I have her targeted myself: marked, no alert
	world.units.target = ZUL
	world:Fire("PLAYER_TARGET_CHANGED")
	chatFrom = #world.chat + 1
	ZUL.targets = "player"
	world:Advance(1)
	T.ok(Targeting:Is("zulrakka-venomtongue"))
	T.ok(not chatHas(world, "Targeting you", chatFrom), "no alert about my own target")
	T.eq(Targeting:Count(), 2)
	world.units.target = nil

	-- When the client withholds the comparison, their target's identity still tells
	ZUL.targets, MORG.targets = nil, nil
	world:Advance(1)
	T.eq(Targeting:Count(), 0)
	world.compareSecret = true
	ZUL.targets = "player"
	world:Advance(1)
	T.ok(Targeting:Is("zulrakka-venomtongue"), "found through the GUID of her target")
	T.eq(ns.Radar:Visible()[1].info.key, "zulrakka-venomtongue", "on the radar she now comes before the Kill on Sight")
	ZUL.targets = MORG
	world:Advance(1)
	T.ok(not Targeting:Is("zulrakka-venomtongue"))
	world.compareSecret = false
	noErrors(world)

	-- Out of sight: we can no longer say they target us
	MORG.targets = "player"
	world:Advance(1)
	T.ok(Targeting:Is("morgash-gorefist"))
	world.units.nameplate1 = nil
	world:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	world:Advance(Targeting.LOST + 1)
	T.ok(not Targeting:Is("morgash-gorefist"))
	T.eq(ns.Nameplates.aims.nameplate1, nil)

	-- Alerts off: still marked, but quiet
	ns.settings.targetAlerts = false
	world:Advance(Targeting.COOLDOWN + 2)
	chatFrom = #world.chat + 1
	ZUL.targets = "player"
	world:Advance(1)
	T.ok(Targeting:Is("zulrakka-venomtongue"))
	T.ok(not chatHas(world, "Targeting you", chatFrom))
	ns.settings.targetAlerts = true

	-- Not in instances
	world.instance = "pvp"
	world:Fire("PLAYER_ENTERING_WORLD")
	world:Advance(1)
	T.eq(Targeting:Count(), 0)
	T.ok(Targeting.stats.checks > 0 and Targeting.stats.hits >= 4)
	noErrors(world)
	BusinessMeetingDB = keep
end)

T.test("game: an enemy on your pet, and one going into stealth", function()
	local keep = BusinessMeetingDB
	BusinessMeetingDB = nil
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 } }
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	local Targeting, Stealth = ns.Targeting, ns.Stealth
	local MORG = { name = "Morgash", surname = "Gorefist", guid = "Player-1-0000EEEE", isPlayer = true, enemy = true,
		faction = "Horde", class = 1, race = 2, level = 60, guild = "Hostile Takeover" }
	world.units.nameplate1 = MORG
	world.units.pet = { name = "Fang", guid = "Pet-0-00001234", isPlayer = false }
	world:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	world:Advance(1)

	-- He goes for the pet
	local chatFrom = #world.chat + 1
	MORG.targets = "pet"
	world:Advance(0.3)
	local on, what = Targeting:Is("morgash-gorefist")
	T.ok(on, "noticed within a few tenths of a second")
	T.eq(what, "pet")
	T.eq(Targeting:Count(), 0, "not counted as on me")
	T.ok(chatHas(world, "Targeting your pet:|r |cfffff468Morgash Gorefist|r", chatFrom))
	T.eq(BusinessMeetingAlertBanner.title:GetText(), "TARGETING YOUR PET")
	world:Advance(1)
	T.ok(_G.BusinessMeetingRadarFrame.rows[1].tag:GetText():find("ON PET", 1, true))
	T.ok(ns.Nameplates.aims.nameplate1, "marked on the nameplate too")

	-- ...then for me: that is news again, cooldown or not
	chatFrom = #world.chat + 1
	MORG.targets = "player"
	world:Advance(0.3)
	T.eq(select(2, Targeting:Is("morgash-gorefist")), "me")
	T.eq(Targeting:Count(), 1)
	T.ok(chatHas(world, "Targeting you:", chatFrom))

	-- Pet alerts can be switched off on their own
	ns.settings.targetPet = false
	MORG.targets = "pet"
	world:Advance(0.3)
	T.ok(not Targeting:Is("morgash-gorefist"), "with the option off, the pet does not count")
	ns.settings.targetPet = true
	-- and the pet is also found when the client withholds comparisons
	world.compareSecret = true
	world:Advance(0.3)
	T.eq(select(2, Targeting:Is("morgash-gorefist")), "pet")
	world.compareSecret = false
	MORG.targets = nil
	world:Advance(0.3)
	T.eq(Targeting:Is("morgash-gorefist"), false)
	noErrors(world)

	-- An ordinary spell is nothing; Vanish is
	chatFrom = #world.chat + 1
	world:Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", "Cast-1", 133)
	T.ok(not chatHas(world, "Stealth:", chatFrom))
	world.units.target = MORG
	world:Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", "Cast-2", 1856)
	world:Fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-2", 1856) -- the same cast, seen through my target
	world.units.target = nil
	noErrors(world)
	T.ok(chatHas(world, "Stealth:|r |cfffff468Morgash Gorefist|r (60 Orc Rogue) used Vanish near you.", chatFrom))
	T.eq(Stealth.stats.hits, 1, "one alert for one cast")
	T.eq(BusinessMeetingAlertBanner.title:GetText(), "STEALTH")
	T.ok(BusinessMeetingAlertBanner.wide:IsShown(), "the spell gets the wide tile")
	T.eq(BusinessMeetingAlertBanner.wide.spellName:GetText(), "Vanish")
	T.eq(world.lastSound, 8959)
	-- his nameplate goes, the radar remembers him as stealthed
	world.units.nameplate1 = nil
	world:Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	world:Advance(1)
	local entry = ns.Radar:Visible()[1]
	T.ok(entry.stealth, "marked on the radar")
	T.eq(entry.stealthSpell, "Vanish")
	T.ok(_G.BusinessMeetingRadarFrame.rows[1].tag:GetText():find("Media\\stealth", 1, true), "a stealth icon on the radar row")
	local row = _G.BusinessMeetingRadarFrame.rows[1]
	T.ok(row.fresh < 1, "the bar has started to drain now that he is out of view")
	T.eq(row.level:GetText(), "60")
	row.scripts.OnEnter(row)
	row.scripts.OnLeave(row)
	-- seen again: no longer stealthed
	world:Advance(3)
	world.units.nameplate1 = MORG
	world:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	T.ok(not ns.Radar:Visible()[1].stealth)
	noErrors(world)

	-- A listed player's stealth alert says they are Kill on Sight
	SlashCmdList.BUSINESSMEETING("add morgash-gorefist Opens from stealth")
	world:Advance(Stealth.COOLDOWN + 1)
	chatFrom = #world.chat + 1
	world:Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", "Cast-3", 1784)
	T.ok(chatHas(world, "used Stealth near you. |cffff8a80Kill on Sight|r: “Opens from stealth”", chatFrom))

	-- What is ignored: a withheld spell, my own casts, friendly players
	world:Advance(Stealth.COOLDOWN + 1)
	chatFrom = #world.chat + 1
	world:Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", "Cast-4", Stub.SECRET)
	T.eq(Stealth.stats.secret, 1)
	world:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", 1784)
	world.units.nameplate5 = { name = "Bob", surname = "Friendly", guid = "Player-1-00009999", isPlayer = true,
		enemy = false, faction = "Alliance", class = 4, race = 1, level = 60 }
	world:Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate5", "Cast-6", 5215)
	T.ok(not chatHas(world, "Stealth:", chatFrom))
	noErrors(world)

	-- Alerts off: quiet, but still on the radar
	ns.settings.stealthAlerts = false
	chatFrom = #world.chat + 1
	world:Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", "Cast-7", 5215)
	T.ok(not chatHas(world, "Stealth:", chatFrom))
	T.eq(ns.Radar.list["morgash-gorefist"].stealthSpell, "Prowl")
	ns.settings.stealthAlerts = true

	-- Not in instances
	world:Advance(Stealth.COOLDOWN + 1)
	world.instance = "pvp"
	world:Fire("PLAYER_ENTERING_WORLD")
	chatFrom = #world.chat + 1
	world:Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", "Cast-8", 1784)
	T.ok(not chatHas(world, "Stealth:", chatFrom))
	noErrors(world)

	-- A client in another language: the spells are known by what it calls them
	BusinessMeetingDB = nil
	local world2 = Stub.Install()
	world2.locale = "deDE"
	world2.spells[1784] = "Verstohlenheit"
	world2.roster = { { "Olaf-Stormborn", 3 } }
	local ns2 = world2:LoadAddon(T.root)
	world2:Fire("ADDON_LOADED", "BusinessMeeting")
	world2:Fire("PLAYER_LOGIN")
	world2:Advance(3)
	world2.units.nameplate1 = MORG
	world2:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	world2:Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", "Cast-1", 1784)
	T.ok(chatHas(world2, "used Verstohlenheit near you"), "found by its local name")
	T.eq(#world2.errors, 0, table.concat(world2.errors, " | "))
	T.eq(ns2.Stealth:Spell(133), nil)
	BusinessMeetingDB = keep
end)

T.test("game: capitals keep colour codes, and frames carry the corner brackets", function()
	BusinessMeetingDB = nil
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 }, { "Kari-Frost", 5 } }
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	local W = ns.W
	T.eq(W.Caps("Hit list · |cffd4a94e3 on you|r"), "HIT LIST · |cFFD4A94E3 ON YOU|r")
	T.eq(W.Caps(nil), nil)
	-- icons inside text: the game's class sheet, and our own glyphs
	T.ok(W.ClassInline(4, 14):find("UI-Classes-Circles:14:14:0:0:256:256:127:190:0:64", 1, true), W.ClassInline(4, 14))
	T.eq(W.ClassInline(nil, 14), "", "nothing when the class is not known")
	T.ok(W.Inline("skull", 12, 255, 138, 128):find("Media\\skull:12:12:0:0:32:32:0:32:0:32:255:138:128", 1, true))
	T.eq(W.NameCaps("Grimtusk Bloodaxe"), "GRIMTUSK BLOODAXE")
	T.eq(W.NameCaps("Grímtusk"), "Grímtusk", "a name with letters upper() cannot handle is left alone")
	local inkR, _, _, light = W.Ink(1, 0.96, 0.41)
	T.ok(inkR < 0.1 and not light, "dark ink on a light class colour")
	inkR, _, _, light = W.Ink(0.0, 0.44, 0.87)
	T.ok(inkR == 1 and light, "white ink on a dark one")
	-- A client without the narrow font keeps the font it had
	local plain = { SetFont = function() error("invalid font") end }
	T.eq(W.CapsFont(plain, 12), plain, "a missing font file does not stop the window being built")
	ns.MainFrame:Toggle()
	local f = ns.MainFrame.frame
	T.eq(#f.brackets, 8, "two bars in each of four corners")
	T.eq(f.tabs.r.label:GetText(), "HIT LIST")
	T.ok(f.tabs.r.underline:IsShown(), "the open tab is underlined")
	T.ok(not f.tabs.b.underline:IsShown(), "the others are not")
	ns.MainFrame:SetTab("b")
	T.ok(f.tabs.b.underline:IsShown() and not f.tabs.r.underline:IsShown(), "the underline follows the tab")
	ns.Alerts:Test()
	T.eq(#BusinessMeetingAlertBanner.brackets, 4, "the banner has brackets in two corners")
	T.eq(#world.errors, 0, table.concat(world.errors, " | "))
end)

T.test("game: the new name takes over Blood Feud's saved data, and a kill is confirmed", function()
	local keep = BusinessMeetingDB
	BusinessMeetingDB = nil
	local world = Stub.Install()
	world.roster = { { "Olaf-Stormborn", 3 } }
	-- What Blood Feud left behind, loaded by the stand-in that ships under its name
	local old = { schema = 1, settings = { sound = false }, guilds = {},
		stats = { ["olaf-stormborn"] = { kills = 7, deaths = 2, best = 3 } } }
	_G.BloodFeudDB, _G.BloodFeudLegacy = old, true
	world.addons.BloodFeud = true
	local ns = world:LoadAddon(T.root)
	world:Fire("ADDON_LOADED", "BusinessMeeting")
	world:Fire("PLAYER_LOGIN")
	world:Advance(3)
	noErrors(world)
	T.eq(BusinessMeetingDB, old, "the old data is now ours")
	T.eq(BusinessMeetingDB.importedFrom, "BloodFeud")
	T.eq(ns.settings.sound, false, "settings came along")
	T.eq(ns.Progress:Stats().kills, 7, "and the totals")
	T.ok(chatHas(world, "Blood Feud is now Business Meeting - PvP"), "the player is told once")
	T.ok(world.disabled.BloodFeud, "the stand-in is switched off for the coming sessions")
	T.ok(not chatHas(world, "still installed and running"), "the stand-in is not mistaken for the old addon")
	T.eq(_G.SLASH_BUSINESSMEETING1, "/bm")
	T.eq(_G.SLASH_BUSINESSMEETING2, "/meeting")
	T.eq(_G.SLASH_BUSINESSMEETING3, "/feud", "the old command still works")
	T.eq(ns.Progress:MyRank().title, "Recruit", "seven kills: the first rank")

	-- A killing blow is a confirmed kill, with the way to the next rank
	world.units.nameplate1 = { name = "Morgash", surname = "Gorefist", guid = "Player-1-0000EEEE", isPlayer = true,
		enemy = true, faction = "Horde", class = 1, race = 2, level = 60 }
	world:Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	world:Fire("PARTY_KILL", "Player-1-00000001", "Player-1-0000EEEE")
	noErrors(world)
	T.eq(BusinessMeetingAlertBanner.title:GetText(), "KILL CONFIRMED")
	local detail = BusinessMeetingAlertBanner.detail:GetText()
	T.ok(detail:find("Confirmed kill 8", 1, true), detail)
	T.ok(detail:find("2 more to Associate", 1, true), detail)
	local rank = BusinessMeetingAlertBanner.spec.wide
	T.eq(rank.kind, "rank", "the way to the next rank as a bar")
	T.eq(rank.title, "Recruit")
	T.eq(rank.next, "Associate")
	T.eq(rank.have, 8)
	T.eq(rank.need, 10)
	T.eq(BusinessMeetingAlertBanner.wide.barText:GetText(), "8 / 10")
	ns.settings.dealBanner = false
	BusinessMeetingAlertBanner:Hide()
	world:Fire("PARTY_KILL", "Player-1-00000001", "Player-1-0000EEEE")
	T.ok(not BusinessMeetingAlertBanner:IsShown(), "the banner can be switched off")
	world:Fire("PARTY_KILL", "Player-1-00000001", "Player-1-0000EEEE") -- the tenth
	T.eq(ns.Progress:MyRank().title, "Associate")

	-- Next session: nothing to take over any more, and nothing said
	local saved = BusinessMeetingDB
	local world2 = Stub.Install()
	world2.roster = { { "Olaf-Stormborn", 3 } }
	BusinessMeetingDB = saved
	_G.BloodFeudDB, _G.BloodFeudLegacy = nil, nil
	local ns2 = world2:LoadAddon(T.root)
	world2:Fire("ADDON_LOADED", "BusinessMeeting")
	world2:Fire("PLAYER_LOGIN")
	world2:Advance(3)
	T.eq(ns2.Progress:Stats().kills, 10)
	T.ok(not chatHas(world2, "Blood Feud is now"))
	T.eq(world2.disabled.BloodFeud, nil)

	-- The old addon itself still installed next to the new one: say so, switch it off
	BusinessMeetingDB = nil
	local world3 = Stub.Install()
	world3.roster = { { "Olaf-Stormborn", 3 } }
	_G.BloodFeudDB = { schema = 1, settings = {}, guilds = {} }
	world3.addons.BloodFeud = true
	world3:LoadAddon(T.root)
	world3:Fire("ADDON_LOADED", "BusinessMeeting")
	world3:Fire("PLAYER_LOGIN")
	world3:Advance(3)
	T.ok(chatHas(world3, "still installed and running next to this one"))
	T.ok(world3.disabled.BloodFeud)
	T.eq(#world3.errors, 0, table.concat(world3.errors, " | "))
	_G.BloodFeudDB = nil
	BusinessMeetingDB = keep
end)
