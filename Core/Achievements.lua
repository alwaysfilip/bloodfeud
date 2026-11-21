-- The achievements. The position in this list is the bit a guildmate's client
-- reads, so entries are only ever appended: never reorder or remove one.
-- test(st, d): st is the player's counters (see Progress), d the figures
-- derived from the fight book (victims, maxOne, maxDeathsOne, classes,
-- maxGuild).
local _, ns = ...

local function at(field, n)
	return function(st) return (st[field] or 0) >= n end
end

local function derived(field, n)
	return function(_, d) return (d[field] or 0) >= n end
end

ns.Achievements = {
	--[[1]] { name = "First Blood", desc = "Land a killing blow on an enemy player.", test = at("kills", 1) },
	--[[2]] { name = "Blooded", desc = "10 killing blows on enemy players.", test = at("kills", 10) },
	--[[3]] { name = "Seasoned Hunter", desc = "50 killing blows on enemy players.", test = at("kills", 50) },
	--[[4]] { name = "Centurion", desc = "100 killing blows on enemy players.", test = at("kills", 100) },
	--[[5]] { name = "Slaughterer", desc = "500 killing blows on enemy players.", test = at("kills", 500) },
	--[[6]] { name = "Thousand Cuts", desc = "1000 killing blows on enemy players.", test = at("kills", 1000) },
	--[[7]] { name = "Hat Trick", desc = "3 kills without dying in between.", test = at("best", 3) },
	--[[8]] { name = "Rampage", desc = "5 kills without dying in between.", test = at("best", 5) },
	--[[9]] { name = "Untouchable", desc = "10 kills without dying in between.", test = at("best", 10) },
	--[[10]] { name = "Payback", desc = "Kill a player who killed you in the last 30 minutes.", test = at("payback", 1) },
	--[[11]] { name = "Instant Karma", desc = "Kill your killer within 2 minutes.", test = at("karma", 1) },
	--[[12]] { name = "Debt Collector", desc = "Pay back 10 kills within 30 minutes.", test = at("payback", 10) },
	--[[13]] { name = "Kill on Sight", desc = "Kill a player on the guild's list.", test = at("listedKills", 1) },
	--[[14]] { name = "Executioner", desc = "Kill players on the guild's list 25 times.", test = at("listedKills", 25) },
	--[[15]] { name = "Guild War", desc = "Kill a member of a guild on the list.", test = at("guildListedKills", 1) },
	--[[16]] { name = "Clan Breaker", desc = "Kill members of the same enemy guild 10 times.",
		test = derived("maxGuild", 10) },
	--[[17]] { name = "Old Friends", desc = "Kill the same enemy player 5 times.", test = derived("maxOne", 5) },
	--[[18]] { name = "Nemesis", desc = "Be killed by the same enemy player 5 times.",
		test = derived("maxDeathsOne", 5) },
	--[[19]] { name = "Rogues' Gallery", desc = "Kill 25 different enemy players.", test = derived("victims", 25) },
	--[[20]] { name = "Most Wanted", desc = "Kill 100 different enemy players.", test = derived("victims", 100) },
	--[[21]] { name = "Every Calling", desc = "Kill an enemy of 8 different classes.", test = derived("classes", 8) },
	--[[22]] { name = "Giant Slayer", desc = "Kill an enemy at least 5 levels above you.", test = at("giant", 1) },
	--[[23]] { name = "Night Shift", desc = "Get a kill between midnight and 5 in the morning.", test = at("night", 1) },
	--[[24]] { name = "Bounty Hunter", desc = "Claim a bounty.", test = at("claims", 1) },
	--[[25]] { name = "Professional", desc = "Claim 10 bounties.", test = at("claims", 10) },
	--[[26]] { name = "Price on Their Head", desc = "Post a bounty.", test = at("posted", 1) },
	--[[27]] { name = "Marked", desc = "Put an enemy player on the list.", test = at("added", 1) },
	--[[28]] { name = "Lookout", desc = "Report 10 sightings of listed players.", test = at("sightings", 10) },
	--[[29]] { name = "Watchtower", desc = "Report 100 sightings of listed players.", test = at("sightings", 100) },
	--[[30]] { name = "Thick Skin", desc = "Die to enemy players 50 times.", test = at("deaths", 50) },
	--[[31]] { name = "Get Even", desc = "Put someone on the list from the revenge prompt.",
		test = at("revengeAdds", 1) },
}
