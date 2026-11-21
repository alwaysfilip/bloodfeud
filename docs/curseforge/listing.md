# CurseForge listing for Blood Feud

Everything to paste into the "Create project" form. The description is the
part between the two rulers at the bottom; it is plain Markdown.

| Field | Value |
|---|---|
| Game | World of Warcraft |
| Project type | Addons |
| Name | `Blood Feud` |
| Summary | `A Kill on Sight list your whole guild shares: mark an enemy player once, and every guildmate is alerted when they meet them.` |
| Main category | PvP |
| Extra categories | Guild, Tooltip (pick the closest ones the form offers) |
| License | MIT License |
| Source | `https://github.com/alwaysfilip/bloodfeud` (once the repository exists) |
| Logo | `docs/curseforge/logo.png` (400 x 400 PNG, original artwork) |

Notes for passing review the first time, from CurseForge's moderation policy:

- The project is only sent to the moderators once a file has been uploaded.
- The description has to say what the addon adds to the game. Vague or very
  short descriptions are the most common reason for a request for changes.
- No external download links anywhere. Links to source or a personal site
  belong at the bottom of the description, which is where the one below is.
- Every later upload needs a change log. The packager sends `CHANGELOG.md`.
- If moderators ask for changes, edit the project. Do not delete it and
  start over.

Screenshots are optional for an addon like this, but two would help once the
addon has run in game: the list window, and the alert with a marked nameplate.

---

## Blood Feud

Blood Feud gives your guild one shared Kill on Sight list for World of
Warcraft: Forever, with a radar, bounties, ranks and achievements built on
top. Mark an enemy player and give a reason. Every guildmate
who runs the addon has the entry within seconds, and each of you is alerted
the moment you meet that player in the world.

### What it adds

- **A list the whole guild shares.** Any member can list an enemy player with
  a reason. Several members can list the same enemy, each with their own
  reason, and the list shows how many of you have a score to settle.
- **An alert on sight.** A banner, a sound and a chat line when a listed
  player shows up as a nameplate, your target, your focus or under your mouse.
- **A mark in the world.** A skull above the nameplate of a listed player, and
  the reason, who added it and where they were last seen in their tooltip.
- **Add with a right-click.** "Add to Kill on Sight" in the menu of any enemy
  player, or `/feud add` with them targeted.
- **Enemy guilds.** Officers can list a whole guild. Its members give a
  quieter alert.
- **Sightings.** When someone meets a listed player, the guild gets one chat
  line saying who, where, and who saw them.
- **A kill count.** Your killing blows on enemy players and your deaths to
  them are counted. For a listed player, the list shows the whole guild's
  score against them.
- **Revenge.** When the same enemy player kills you twice within 30 minutes,
  Blood Feud offers to put them on the list with one click. Both numbers can
  be changed in the options.
- **A radar.** A small window listing the enemy players around you, the ones
  on the list or with a bounty first.
- **Bounties.** Put a price on an enemy player or a whole guild. Every killing
  blow by a guildmate claims it, and the board shows who has collected.
- **Ranks.** Your kills earn you a rank, from Recruit to Feudlord. Officers can
  rename the ranks and move the thresholds for the whole guild.
- **Achievements.** 31 of them, from First Blood to Clan Breaker, announced to
  your guild when you earn them.

### How to use it

1. Everyone in the guild who wants the list installs Blood Feud.
2. Target an enemy player and type `/feud add` followed by a reason, or
   right-click them and choose "Add to Kill on Sight".
3. Type `/feud` to open the list.

| Command | What it does |
|---|---|
| `/feud` | Open the list |
| `/feud add [reason]` | Add your target |
| `/feud add Firstname-Surname [reason]` | Add a player by name |
| `/feud remove Firstname-Surname` | Remove your own report |
| `/feud guild Guild Name = reason` | List a guild (officers) |
| `/feud score [Firstname-Surname]` | Your kills and deaths, or one enemy's score |
| `/feud radar` | Show or hide the radar |
| `/feud bounty [Firstname-Surname] [points] [reward]` | Post a bounty |
| `/feud rank` | Your rank and the guild's ranks |
| `/feud ach` | Your achievements |
| `/feud log` | Recent changes and who sent them |
| `/feud options` | Open the options page |

### Who can change the list

- Any member can add a player.
- A report can be removed by the member who wrote it, or by an officer.
- Only officers can list or unlist a guild.
- Any member can post a bounty; its poster or an officer can take it down.
- Only officers can change the ranks.

An officer is the guild master or anyone whose rank has the officer
permission ticked in the guild control panel.

### Good to know

Forever limits what addons may see and send, and Blood Feud works within
those limits:

- **It sees the enemies the game shows you.** Addons cannot read the combat
  log in Forever, so detection comes from nameplates, your target, focus and
  mouseover. Turn on enemy nameplates to get the most out of it. A stealthed
  player you cannot see is not detected.
- **Kills and deaths are counted in the open world.** A kill counts when it
  was your (or your pet's) killing blow. Your killer is read from the death
  recap. Ranks, bounties and achievements build on those kills.
- **The radar is a list, not a map.** Addons cannot read where an enemy
  stands, so it shows who the game has shown you in the last minute.
- **Bounty gold is on trust.** The addon tracks points; any gold promised in
  a bounty is paid by its poster.
- **It is quiet in dungeons, raids and battlegrounds.** Addon messages are
  locked there. Changes you make inside are kept and sent when you come out,
  and changes others made are fetched then.
- **It syncs between members who are online.** There is no server. Whoever is
  online passes the list on to whoever logs in next.
- **Permissions are enforced by the addon, not by a server.** The rules above
  are applied in the interface and checked again on every live change. A
  member running a modified copy of the addon could get around them, so every
  accepted change is logged with its real sender (`/feud log`) and an officer
  can always undo it.

### Privacy

Blood Feud only talks on your guild's hidden addon channel. It sends the
list entries, what it saw of a listed player (class, level and guild), your
kill and death count against listed players, your totals, rank and
achievements, the bounties you post and claim, and sightings of listed players
with your zone and coordinates. Sightings can be
turned off in the options. Nothing is sent anywhere else.

### Source and issues

The source code is on GitHub, under the MIT license:
https://github.com/alwaysfilip/bloodfeud

---
