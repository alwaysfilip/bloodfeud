# Blood Feud

A guild-shared Kill on Sight list for **World of Warcraft: Forever**.

One guild member marks an enemy player. Everyone else in the guild who runs
the addon gets the entry within seconds, and is alerted the moment they meet
that player themselves.

## What it does

- **Shared list.** Any member can list an enemy player with a reason. Several
  members can list the same enemy; each keeps their own reason, and the list
  shows how many of you have a score to settle.
- **Alert on sight.** A banner, a sound and a chat line when a listed player
  shows up as a nameplate, your target, your focus or under your mouse.
- **Marked in the world.** A skull above the nameplate, and the reason, who
  added it and where they were last seen in the tooltip.
- **Right-click to add.** "Add to Kill on Sight" in the menu of any enemy
  player, or `/feud add` with them targeted.
- **Enemy guilds.** Officers can list a whole guild. Its members give a
  quieter alert.
- **Sightings.** When someone meets a listed player, the guild gets one line:
  who, where, and who saw them.
- **Kill count.** Your killing blows on enemy players and your deaths to them
  are counted. For a listed player the list shows the whole guild's score.
- **Revenge.** When the same enemy kills you twice within 30 minutes, Blood
  Feud offers to put them on the list. Both numbers can be changed in the
  options.
- **Radar.** A small window listing the enemy players around you, the ones on
  the list or with a bounty first. Shift-click to list them, right-click to
  post a bounty.
- **Bounties.** Anyone can put a price on an enemy player or a whole guild.
  Points go to every guildmate who lands a killing blow, and the board shows
  who has collected.
- **Gold bounties.** A bounty can also carry gold, which goes to the first
  kill. Its poster then has 48 hours to send the gold by mail or trade. Blood
  Feud notices the gold leave and arrive by itself. Whoever has not paid in
  time is **Dishonored**: no rank, no bounty points and no new bounties until
  the debt is paid.
- **Ranks.** Your kills earn you a rank, from Recruit to Feudlord. Officers can
  rename the ranks and move the thresholds for the whole guild. Guildmates see
  each other's rank in the Ranks tab and in tooltips.
- **Achievements.** 31 of them, from First Blood to Clan Breaker. Your guild is
  told when you earn one, and can see which ones you have.

## Commands

| Command | |
|---|---|
| `/feud` | Open the list |
| `/feud add [reason]` | Add your target |
| `/feud add Firstname-Surname [reason]` | Add a player by name |
| `/feud remove Firstname-Surname` | Remove your own report |
| `/feud guild Guild Name = reason` | List a guild (officers) |
| `/feud score [Firstname-Surname]` | Your kills and deaths, or one enemy's score |
| `/feud radar` | Show or hide the radar |
| `/feud bounty [points] [50g] [note]` | Post a bounty on your target; `50g` puts 50 gold on it |
| `/feud bounty Firstname-Surname [points] [50g] [note]` | Post a bounty by name (with no enemy targeted) |
| `/feud bounty <Guild Name> [points] [50g] [note]` | Post a bounty on a guild |
| `/feud bounties` | Open the bounty board |
| `/feud debts` | Bounty gold you owe and are owed |
| `/feud rank` | Your rank, and the guild's ranks |
| `/feud rank set <n> <kills> <title>` | Change a rank (officers) |
| `/feud ach` | Your achievements |
| `/feud sync` | Ask the guild for changes now |
| `/feud log` | Recent changes and who sent them |
| `/feud options` | Open the options page |

## Who can do what

- Any member can add a player.
- A report can be removed by the member who wrote it, or by an officer.
- Only officers can list or unlist a guild.
- Any member can post a bounty. It can be taken down by its poster or an
  officer. A gold bounty that has been won can only be taken down by its
  poster once the gold is paid.
- On the gold of a won bounty, the poster can say it is sent, the winner can
  say it arrived or did not, and an officer can settle it either way.
- Only officers can change the ranks.
- Only you can write your own totals, achievements and bounty claims.

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
  bounty claims and most achievements build on those kills.
- **The radar is a list, not a map.** Addons cannot read where an enemy
  stands, so the radar shows who the game has shown you in the last minute,
  not their position.
- **Blood Feud cannot move gold, only watch it.** The poster of a won gold
  bounty pays by ordinary mail or trade. The addon sees the gold leave on the
  poster's side, which stops the 48-hour clock, and sees it arrive on the
  winner's side, which closes the debt. Incoming mail can only be read while
  you stand at a mailbox, so a payment by mail is confirmed the next time the
  winner opens theirs. The winner can also confirm by hand, or say the gold
  never came, and an officer can settle a dispute.

## An honest note on permissions

The rules above are enforced by the addon's interface, and again on every
live change, where the game server guarantees who the sender is. What cannot
be verified is state that one member passes on for another, because addons
have no way to sign a message. A member running a modified copy of the addon
could therefore push changes they have no right to make. Every accepted
change is logged with its real sender (`/feud log`), and an officer can
always undo it.

## Privacy

Blood Feud only talks on your guild's hidden addon channel. It sends the
list entries, what it saw of a listed player (class, level, guild), your
kill and death count against listed players, your total kills, deaths, best
streak, bounty points and achievements, the bounties you post and claim,
whether the gold of a won bounty was sent and received, and sightings of
listed players with your zone and coordinates. Sightings can be turned off in
the options. Nothing is sent anywhere else. To notice a bounty being paid,
the addon looks at who your mail and trades are with and how much gold is in
them; that stays on your computer, and only "sent" or "received" for the
bounty in question is shared.

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
