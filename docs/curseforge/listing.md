# CurseForge listing for Business Meeting - PvP

Everything to paste into the project's General and Description pages. The
description is the part between the two rulers at the bottom; it is plain
Markdown (set the editor to Markdown before pasting).

| Field | Value |
|---|---|
| Game | World of Warcraft |
| Project type | Addons |
| Name | `Business Meeting - PvP` |
| Summary | `Here on business. World PvP for your guild: a shared Kill on Sight hit list, radar, contracts paid in gold, ranks, medals, and alerts for whoever targets you.` |
| Main category | PvP |
| Extra categories | Guild, Tooltip (pick the closest ones the form offers) |
| License | MIT License |
| Source | The GitHub repository |
| Logo | `docs/curseforge/logo.png` (400 x 400 PNG, original artwork) |

The project was created as "Blood Feud". Rename it on the General page; do
not create a new project, or the files and the review start over.

Notes for passing review, from CurseForge's moderation policy:

- The description has to say what the addon adds to the game. Vague or very
  short descriptions are the most common reason for a request for changes.
- No external download links anywhere. Links to source or a personal site
  belong at the bottom of the description, which is where the one below is.
- Every upload needs a change log. The packager sends `CHANGELOG.md`.
- If moderators ask for changes, edit the project. Do not delete it and
  start over.

Screenshots from the game would help: the hit list window, an alert with a
marked nameplate, the radar with someone "ON YOU".

---

## Business Meeting - PvP

World PvP for your guild in World of Warcraft: Forever. You are here on
business: there is a hit list, there are contracts, and somebody keeps the
books.

Mark an enemy player Kill on Sight and add your intel. Every guildmate who
runs the addon has the entry within seconds, and each of you is alerted the
moment you meet that player in the world.

*Formerly called Blood Feud. Updating keeps your saved data.*

### The language

| In the addon | What it is |
|---|---|
| The hit list | The guild's shared list of enemy players marked Kill on Sight |
| Intel, sanctioned by | Why someone is on the list, and who put them there |
| Hostile guild | An enemy guild on the list |
| Confirmed kill | Your killing blow on an enemy player |
| Contract | A bounty on an enemy player or guild: opened by a client, fulfilled by a kill |
| Blacklisted | What you are if you do not pay the gold for a fulfilled contract |
| Rank, medal | Your standing from confirmed kills, and an achievement |

What you need to read in the middle of a fight is said plainly: "Targeting
you", "Stealth", "Kill on Sight".

### What it adds

- **A hit list the whole guild shares.** Any member can add an enemy player
  with intel. Several members can add the same enemy, each with their own
  intel.
- **An alert on sight.** A banner, a sound and a chat line when someone from
  the hit list shows up as a nameplate, your target, your focus or under your
  mouse.
- **A mark in the world.** A skull above their nameplate, and the intel, who
  sanctioned it and where they were last seen in their tooltip.
- **Add with a right-click.** "Add to the hit list (Kill on Sight)" in the
  menu of any enemy player, or `/bm add` with them targeted.
- **Hostile guilds.** Officers can list a whole enemy guild. Its members give
  a quieter alert.
- **Sightings.** When someone meets a player from the hit list, the guild gets
  one chat line saying who, where, and who saw them.
- **Confirmed kills.** Your killing blows on enemy players and your deaths to
  them are counted. For a player on the hit list, the list shows the whole
  guild's record against them.
- **Unfinished business.** When the same enemy player kills you twice within
  30 minutes, you are offered to put them on the hit list with one click.
- **A radar.** A small window listing the enemy players around you, Kill on
  Sight and players with a contract on them first.
- **Contracts.** Open a contract on an enemy player or a whole guild. Every
  killing blow by a guildmate earns the points.
- **Gold contracts that get paid.** Put gold on a contract and it goes to the
  first kill. You then have 48 hours to pay by mail or trade, and the addon
  notices the gold leave and arrive by itself. Not paying gets you
  **blacklisted** in front of the whole guild until you do.
- **Ranks.** Your confirmed kills earn you a rank, from Recruit to Boogeyman.
  Officers can rename the ranks and move the thresholds for the whole guild.
- **Medals.** 31 achievements, from First Blood to Bad Blood, announced to
  your guild when you earn them.
- **Targeting you.** When an enemy player targets you or your pet, you are
  told who it is: class, level and guild, whether they are Kill on Sight, and
  how they have fared against your guild. They are marked on the radar and on
  their nameplate.
- **Stealth alert.** When an enemy player you can see uses Stealth, Vanish,
  Prowl or Shadowmeld, you are told, and the radar keeps them marked.
- **Comms.** A tab listing the guildmates who run the addon, their version,
  and who needs to update.

### How to use it

1. Everyone in the guild who wants the hit list installs the addon.
2. Target an enemy player and type `/bm add` followed by your intel, or
   right-click them and choose "Add to the hit list (Kill on Sight)".
3. Type `/bm` to open the window.

| Command | What it does |
|---|---|
| `/bm` | Open the hit list |
| `/bm add [intel]` | Add your target |
| `/bm add Firstname-Surname [intel]` | Add a player by name |
| `/bm remove Firstname-Surname` | Remove your own entry |
| `/bm guild Guild Name = intel` | List a hostile guild (officers) |
| `/bm score [Firstname-Surname]` | Kills and deaths, or the record against one enemy |
| `/bm radar` | Show or hide the radar |
| `/bm bounty [Firstname-Surname] [points] [50g] [terms]` | Open a contract on someone; `50g` puts 50 gold on it |
| `/bm debts` | Contract gold you owe and are owed |
| `/bm rank` | Your rank, and everyone else's |
| `/bm ach` | Your medals |
| `/bm users` | Which guildmates run the addon |
| `/bm log` | Recent changes and who sent them |
| `/bm options` | Open the options page |

### Who can change what

- Any member can add a player to the hit list.
- An entry can be removed by the member who wrote it, or by an officer.
- Only officers can list or unlist a hostile guild.
- Any member can open a contract; whoever opened it or an officer can
  withdraw it.
- On a fulfilled gold contract: whoever opened it says the gold is sent,
  whoever fulfilled it says it arrived, and an officer can settle a dispute.
- Only officers can change the ranks.

An officer is the guild master or anyone whose rank has the officer
permission ticked in the guild control panel.

### Good to know

Forever limits what addons may see and send, and the addon works within
those limits:

- **It sees the enemies the game shows you.** Addons cannot read the combat
  log in Forever, so detection comes from nameplates, your target, focus and
  mouseover. Turn on enemy nameplates to get the most out of it. A stealthed
  player you cannot see is not detected.
- **Kills and deaths are counted in the open world.** A kill counts when it
  was your (or your pet's) killing blow. Your killer is read from the death
  recap. Ranks, contracts and medals build on those kills.
- **"Targeting you" covers the enemies the game shows you:** those with a
  nameplate, your target and your focus.
- **The stealth alert fires when an enemy you can see goes into stealth.**
  Someone already stealthed when they came near cannot be detected.
- **The radar is a list, not a map.** Addons cannot read where an enemy
  stands, so it shows who the game has shown you in the last minute.
- **It cannot move gold, only watch it.** Contract gold is paid by ordinary
  mail or trade. The addon sees it leave on one side and arrive on the other.
  Incoming mail can only be read at a mailbox, so a payment by mail is
  confirmed the next time the receiver opens theirs.
- **It is quiet in dungeons, raids and battlegrounds.** Addon messages are
  locked there. Changes you make inside are kept and sent when you come out,
  and changes others made are fetched then.
- **It syncs between members who are online.** There is no server. Whoever is
  online passes the hit list on to whoever logs in next.
- **Permissions are enforced by the addon, not by a server.** The rules above
  are applied in the interface and checked again on every live change. A
  member running a modified copy of the addon could get around them, so every
  accepted change is logged with its real sender (`/bm log`) and an officer
  can always undo it.

### Privacy

The addon only talks on your guild's hidden addon channel. It tells your
guild that you run the addon and which version, and it sends the hit list
entries, what it saw of a listed player (class, level and guild), your kill
and death count against listed players, your totals, rank and medals, the
contracts you open and fulfill, whether the gold of a fulfilled contract was
sent and received, and sightings of listed players with your zone and
coordinates. Sightings can be turned off in the options. Nothing is sent
anywhere else. To notice a contract being paid, the addon looks at the sender
and gold of your mail and trades; that stays on your computer.

### Source and issues

The source code is on GitHub, under the MIT license:
https://github.com/alwaysfilip/business-meeting-pvp

---
