# Business Meeting - PvP

World PvP for your guild in **World of Warcraft: Forever**. You are here on
business: there is a hit list, there are contracts, and somebody keeps the
books.

One guild member marks an enemy player Kill on Sight. Everyone else in the
guild who runs the addon gets the entry within seconds, and is alerted the
moment they meet that player themselves. Around that shared hit list sit a
radar, contracts (bounties) paid in points and gold, ranks, medals
(achievements) and alerts for whoever targets you or goes into stealth.

Formerly called Blood Feud. Updating keeps your saved data.

## The language

| In the addon | What it is |
|---|---|
| The hit list | The guild's shared list of enemy players marked Kill on Sight |
| Intel, sanctioned by | Why someone is on the list, and who put them there |
| Hostile guild | An enemy guild on the list |
| Confirmed kill | Your killing blow on an enemy player |
| Contract | A bounty on an enemy player or guild: opened by a client, fulfilled by a kill |
| Blacklisted | What you are when you do not pay the gold for a fulfilled contract |
| Rank, medal | Your standing from confirmed kills, and an achievement |
| Comms | The guildmates who run the addon |

What has to be understood in the middle of a fight is said plainly:
"Targeting you", "Stealth", "Kill on Sight".

## What it does

- **The hit list.** Any member can add an enemy player with intel. Several
  members can add the same enemy; each keeps their own intel, and the list
  shows how many of you have a score to settle.
- **Alert on sight.** A banner, a sound and a chat line when someone from the
  hit list shows up as a nameplate, your target, your focus or under your
  mouse. The banner is built like a unit frame: a portrait with the class
  icon and level, the name on a bar in the class colour, and tiles for the
  guild's record against them and any contract.
- **Marked in the world.** A skull above the nameplate, and the intel, who
  sanctioned it and where they were last seen in the tooltip.
- **Right-click to add.** "Add to the hit list (Kill on Sight)" in the menu of
  any enemy player, or `/bm add` with them targeted.
- **Hostile guilds.** Officers can list a whole enemy guild. Its members give
  a quieter alert.
- **Sightings.** When someone meets a player from the hit list, the guild gets
  one line: who, where, and who saw them.
- **Confirmed kills.** Your killing blows on enemy players and your deaths to
  them are counted, with a banner for each kill you confirm. For a player on
  the hit list, the list shows the whole guild's record.
- **Unfinished business.** When the same enemy kills you twice within 30
  minutes, Business Meeting offers to put them on the hit list. Both numbers
  can be changed in the options.
- **Radar.** A small window listing the enemy players around you, Kill on
  Sight and players with a contract on them first. Each row is a class icon
  and a bar that drains as the sighting gets older, with icons for what is
  known about them. Shift-click to add them, right-click to open a contract
  on them.
- **Contracts.** Anyone can open a contract on an enemy player or a whole
  guild. Points go to every guildmate who lands a killing blow, and the board
  shows who has collected.
- **Gold contracts.** A contract can also carry gold, which goes to the first
  kill. Whoever opened it then has 48 hours to pay by mail or trade. Business
  Meeting notices the gold leave and arrive by itself. Whoever has not paid in
  time is **blacklisted**: no rank, no contract points and no new contracts
  until the gold is paid.
- **Ranks.** Your confirmed kills earn you a rank, from Recruit to Boogeyman.
  Officers can rename the ranks and move the thresholds for the whole guild.
  Guildmates see each other's rank on the Ranks tab and in tooltips.
- **Medals.** 31 of them, from First Blood to Bad Blood. Your guild is told
  when you earn one, and can see which ones you have.
- **Targeting you.** When an enemy player targets you or your pet, you are
  told who it is: class, level, race and guild, whether they are Kill on Sight
  and why, how they have fared against the guild and against you, and any
  contract on them. They are marked on the radar and with a red cross on
  their nameplate for as long as it lasts.
- **Stealth alert.** When an enemy player you can see uses Stealth, Vanish,
  Prowl or Shadowmeld, you are told, and the radar keeps them marked as
  stealthed.
- **Comms.** The Comms tab lists the guildmates who run the addon, their
  version, who is online, and who needs to update before they can sync with
  you.

## Commands

| Command | |
|---|---|
| `/bm` | Open the hit list (`/meeting` and the old `/feud` work too) |
| `/bm add [intel]` | Add your target |
| `/bm add Firstname-Surname [intel]` | Add a player by name |
| `/bm remove Firstname-Surname` | Remove your own entry |
| `/bm guild Guild Name = intel` | List a hostile guild (officers) |
| `/bm score [Firstname-Surname]` | Your kills and deaths, or the record against one enemy |
| `/bm radar` | Show or hide the radar |
| `/bm bounty [points] [50g] [terms]` | Open a contract on your target; `50g` puts 50 gold on it |
| `/bm bounty Firstname-Surname [points] [50g] [terms]` | Open a contract on a player by name (with no enemy targeted) |
| `/bm bounty <Guild Name> [points] [50g] [terms]` | Open a contract on a guild |
| `/bm bounties` | Open the contracts |
| `/bm debts` | Contract gold you owe and are owed |
| `/bm users` | Which guildmates run the addon, and on which version |
| `/bm rank` | Your rank, and everyone else's |
| `/bm rank set <n> <kills> <name>` | Change a rank (officers) |
| `/bm ach` | Your medals |
| `/bm sync` | Ask the guild for changes now |
| `/bm log` | Recent changes and who sent them |
| `/bm options` | Open the options page |

## Who can do what

- Any member can add a player to the hit list.
- An entry can be removed by the member who wrote it, or by an officer.
- Only officers can list or unlist a hostile guild.
- Any member can open a contract. It can be withdrawn by whoever opened it or
  by an officer. A gold contract that has been fulfilled can only be withdrawn
  by whoever opened it once the gold is paid.
- On a fulfilled gold contract, whoever opened it can say the gold is sent,
  whoever fulfilled it can say it arrived or did not, and an officer can
  settle it either way.
- Only officers can change the ranks.
- Only you can write your own totals, medals and contract claims.

"Officer" means the guild master and every rank with the officer permission
ticked in the guild control panel.

## What to expect in Forever

Forever inherits the addon restrictions introduced in Midnight, and the addon
works within them rather than around them:

- **Enemies are only seen when the game shows them to you.** The combat log
  is closed to addons, so detection comes from nameplates, target, focus and
  mouseover. Turn on enemy nameplates to get the most out of it. A rogue in
  stealth behind you is not detected.
- **Nothing happens in dungeons, raids and battlegrounds.** Addon messages
  are locked there. Changes you make inside are kept and sent when you come
  out; changes others made are fetched then too.
- **It only syncs between members who are online at the same time.** There is
  no server. Whoever is online passes the list on to whoever logs in next.
- **Kills and deaths are counted in the open world only.** The client tells
  addons who landed a killing blow and, through the death recap, who killed
  you. It does not do so inside instances, so nothing is counted there. A
  kill only counts when it was your (or your pet's) killing blow. Ranks,
  contracts and most medals build on those kills.
- **"Targeting you" only covers enemies the game shows you.** An addon can
  ask who an enemy has targeted only for enemies with a nameplate, your own
  target and your focus. Someone out of sight, or in stealth, is not noticed.
- **The stealth alert sees the moment, not the rogue.** It fires when an
  enemy you can see goes into stealth. Someone who was already stealthed when
  they came near cannot be detected by any addon.
- **The radar is a list, not a map.** Addons cannot read where an enemy
  stands, so the radar shows who the game has shown you in the last minute,
  not their position.
- **The addon cannot move gold, only watch it.** Whoever opened a fulfilled gold
  contract pays by ordinary mail or trade. The addon sees the gold leave on
  their side, which stops the 48-hour clock, and sees it arrive on the other
  side, which settles the contract. Incoming mail can only be read while you
  stand at a mailbox, so a payment by mail is confirmed the next time the
  receiver opens theirs. The receiver can also confirm by hand, or say the
  gold never came, and an officer can settle a dispute.

## An honest note on permissions

The rules above are enforced by the addon's interface, and again on every
live change, where the game server guarantees who the sender is. What cannot
be verified is state that one member passes on for another, because addons
have no way to sign a message. A member running a modified copy of the addon
could therefore push changes they have no right to make. Every accepted
change is logged with its real sender (`/bm log`), and an officer can
always undo it.

## Privacy

Business Meeting only talks on your guild's hidden addon channel. It tells
your guild that you run the addon and which version, and it sends the
hit list entries, what it saw of a listed player (class, level, guild), your
kill and death count against listed players, your total kills, deaths, best
streak, contract points and medals, the contracts you open and fulfill,
whether the gold of a fulfilled contract was sent and received, and sightings of listed
players with your zone and coordinates. Sightings can be turned off in the
options. Nothing is sent anywhere else. To notice a contract being paid, the
addon looks at who your mail and trades are with and how much gold is in
them; that stays on your computer, and only "sent" or "received" for the
contract in question is shared.

## Development

The sync engine, storage and wire format are plain Lua with no dependency on
the game client, and are tested offline, including a simulation of many
clients on a lossy, throttled guild channel:

```sh
brew install luajit luacheck subversion
scripts/fetch-libs.sh     # embedded libraries into Libs/ (not committed)
scripts/link-addon.sh     # symlink this checkout into the game's AddOns folder
luajit tests/run.lua      # all tests
luacheck .                # lint
```

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager)
when a tag is pushed.

## License

MIT
