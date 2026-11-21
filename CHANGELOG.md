# Blood Feud

## 0.2.0

- Radar: a small window listing the enemy players around you, the ones on the
  list or with a bounty first. Shift-click to list them, right-click to post a
  bounty. `/feud radar` to show or hide it.
- Bounties: put a price in points (and, on trust, a promise such as "50 gold")
  on an enemy player or a whole guild. Every killing blow by a guildmate
  claims it. New Bounties tab, alerts and tooltip lines for players with a
  bounty, and "Put a bounty on them" in the right-click menu.
- Ranks: your kills earn a rank, from Recruit to Feudlord. Officers can rename
  the ranks and move the thresholds for the guild. New Ranks tab, and your
  guildmates' rank in their tooltip.
- Achievements: 31 of them, announced to the guild when earned. New
  Achievements tab.
- Needs everyone on 0.2.0 to sync: 0.1.0 clients are told to update.

## 0.1.0

First version, for World of Warcraft: Forever (1.60.1).

- Guild-shared Kill on Sight list: any member can list an enemy player, and
  several members can each attach their own reason to the same enemy.
- Alert (banner, sound, chat line) when you meet a listed player through a
  nameplate, your target, focus or mouseover.
- Tooltip lines, a skull above the nameplate, and "Add to Kill on Sight" in
  the right-click menu of enemy players.
- Officers can list whole enemy guilds; their members give a quieter alert.
- Sightings: your guild sees where a listed player was just met.
- Sync over the guild addon channel that keeps working around the lockdown
  in dungeons, raids and battlegrounds, and never resurrects removed entries.
- Kill counting: your killing blows on enemy players and your deaths to them
  are counted. For listed players the guild's combined score is shown in the
  list, the tooltip and with `/feud score`.
- Revenge: when the same enemy player kills you several times in a short
  while (2 times in 30 minutes by default), you are offered to put them on
  the list. Never in instances or battlegrounds.
