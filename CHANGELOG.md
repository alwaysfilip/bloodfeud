# Business Meeting - PvP

## 0.4.0

- New name: Blood Feud is now **Business Meeting - PvP**. Your saved data
  comes along, and the addon still syncs with guildmates on 0.3.x. The
  command is `/bm` (`/meeting` and the old `/feud` work too).
- New language to go with the name: you are here on business. Enemy players
  marked Kill on Sight are on the guild's hit list, with intel and who
  sanctioned it. Enemy guilds are hostile guilds, a killing blow is a
  confirmed kill, and bounties are contracts that are opened and fulfilled.
  Whoever does not pay the gold for a fulfilled contract is blacklisted.
  "Targeting you", "Stealth" and "Kill on Sight" are unchanged.
- New built-in ranks, from Recruit to Boogeyman, and achievements are now
  medals with new names. Ranks your officers have set themselves are kept.
- The tabs are now Hit list, Guilds, Contracts, Ranks, Medals and Comms.
- A "Kill confirmed" banner for each of your killing blows, with your count
  and how far it is to the next rank. Can be turned off in the options.
- A new look for every window: near-black panels with gold brackets in the
  corners, titles, tabs and buttons in narrow capitals, and alert banners
  whose brackets take the colour of the alert.
- A new icon, a necktie in a crosshair, for the addon list, the minimap
  button and the window.
- If you installed by hand: unpack the new version into `Interface/AddOns` as
  usual. It contains a small `BloodFeud` folder that hands your old data over
  and then switches itself off; you can delete it after the first login.

## 0.3.1

- Targeting you: an alert when an enemy player targets you, with their class,
  level, race and guild, whether they are Kill on Sight and why, how many
  times they have killed your guildmates and you, and any bounty on them.
  They are marked "ON YOU" on the radar, come first there, and get a red cross
  on their nameplate. Works for enemies with a nameplate, your target and
  your focus. Can be turned off in the options, as can its sound.
- The same when an enemy targets your pet ("ON PET"), with its own switch.
- Stealth alert: when an enemy player you can see uses Stealth, Vanish, Prowl
  or Shadowmeld, you get an alert, and the radar marks them as stealthed for
  as long as it remembers them. Can be turned off in the options.
- New Addon tab: which guildmates run Blood Feud, on which version, who is
  online, and who needs to update before they can sync with you. `/feud users`
  prints the same in chat, and Refresh asks everyone online to report in.
- The "guildmates online with the addon" count in the window is now accurate.
- Syncs with 0.3.0. Guildmates on 0.3.0 or older show up once their copy has
  synced something, with the version worked out from that.

## 0.3.0

- Gold bounties: a bounty can carry gold, which goes to the first guildmate
  to land the killing blow. Its poster then has 48 hours to send the gold by
  mail or trade.
- Payment is noticed without anyone clicking: the poster's side sees the gold
  leave (which stops the clock), the winner's side sees it arrive in the
  mailbox or in a trade (which closes the debt). The winner can also mark it
  paid by hand or say it never came, and an officer can settle a dispute.
- Dishonored: whoever has not paid in time loses their rank and bounty points
  in the Ranks tab and in tooltips, and cannot post new bounties, until the
  debt is paid.
- The bounty board shows the gold and where each debt stands. `/feud bounty`
  takes gold as `50g`, and `/feud debts` lists what you owe and are owed.
- Needs everyone on 0.3.0 to sync. Bounties posted with 0.2.0 have to be
  posted again.
- The file on CurseForge is now named `BloodFeud-v0.3.0`.

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
