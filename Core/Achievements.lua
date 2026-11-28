-- The medals (achievements). The position in this list is the bit a
-- guildmate's client reads, so entries are only ever appended: never reorder
-- or remove one. Names are in the addon's own language; what has to be done
-- is said plainly.
-- test(st, d): st is the player's counters (see Progress), d the figures
-- derived from the fight book (victims, maxOne, maxDeathsOne, classes,
-- maxGuild).
local _, ns = ...

local function at(field, n)
	return function(st) return (st[field] or 0) >= n end
end

local function totalKills(n)
	return function(st) return ((st.kills or 0) + (st.bgKills or 0)) >= n end
end

local function derived(field, n)
	return function(_, d) return (d[field] or 0) >= n end
end

ns.Achievements = {
	--[[1]] { name = "First Blood", desc = "Land a killing blow on an enemy player.", test = totalKills(1) },
	--[[2]] { name = "Blooded", desc = "10 killing blows on enemy players.", test = totalKills(10) },
	--[[3]] { name = "Hired Gun", desc = "50 killing blows on enemy players.", test = totalKills(50) },
	--[[4]] { name = "Centurion", desc = "100 killing blows on enemy players.", test = totalKills(100) },
	--[[5]] { name = "Professional", desc = "500 killing blows on enemy players.", test = totalKills(500) },
	--[[6]] { name = "Living Legend", desc = "1000 killing blows on enemy players.", test = totalKills(1000) },
	--[[7]] { name = "Clean Run", desc = "3 kills without dying in between.", test = at("best", 3) },
	--[[8]] { name = "Untouchable", desc = "5 kills without dying in between.", test = at("best", 5) },
	--[[9]] { name = "Not a Scratch", desc = "10 kills without dying in between.", test = at("best", 10) },
	--[[10]] { name = "Payback", desc = "Kill a player who killed you in the last 30 minutes.", test = at("payback", 1) },
	--[[11]] { name = "Instant Karma", desc = "Kill your killer within 2 minutes.", test = at("karma", 1) },
	--[[12]] { name = "Never Forgets", desc = "Pay back 10 kills within 30 minutes.", test = at("payback", 10) },
	--[[13]] { name = "Target Down", desc = "Kill a player from the hit list (Kill on Sight).", test = at("listedKills", 1) },
	--[[14]] { name = "Crossing Names Off", desc = "Kill players from the hit list 25 times.", test = at("listedKills", 25) },
	--[[15]] { name = "Hostile Takeover", desc = "Kill a member of a listed guild.", test = at("guildListedKills", 1) },
	--[[16]] { name = "Bad Blood", desc = "Kill members of the same enemy guild 10 times.",
		test = derived("maxGuild", 10) },
	--[[17]] { name = "Standing Appointment", desc = "Kill the same enemy player 5 times.", test = derived("maxOne", 5) },
	--[[18]] { name = "Nemesis", desc = "Be killed by the same enemy player 5 times.",
		test = derived("maxDeathsOne", 5) },
	--[[19]] { name = "Black Book", desc = "Kill 25 different enemy players.", test = derived("victims", 25) },
	--[[20]] { name = "Infamous", desc = "Kill 100 different enemy players.", test = derived("victims", 100) },
	--[[21]] { name = "All Comers", desc = "Kill an enemy of 8 different classes.", test = derived("classes", 8) },
	--[[22]] { name = "Punching Up", desc = "Kill an enemy at least 5 levels above you.", test = at("giant", 1) },
	--[[23]] { name = "Night Shift", desc = "Get a kill between midnight and 5 in the morning.", test = at("night", 1) },
	--[[24]] { name = "First Contract", desc = "Fulfill a contract (a bounty).", test = at("claims", 1) },
	--[[25]] { name = "Reliable Contractor", desc = "Fulfill 10 contracts.", test = at("claims", 10) },
	--[[26]] { name = "Paying Client", desc = "Open a contract on someone.", test = at("posted", 1) },
	--[[27]] { name = "Naming Names", desc = "Add an enemy player to the hit list.", test = at("added", 1) },
	--[[28]] { name = "Spotter", desc = "Report 10 sightings of Kill on Sight players.", test = at("sightings", 10) },
	--[[29]] { name = "Eyes Everywhere", desc = "Report 100 sightings of Kill on Sight players.", test = at("sightings", 100) },
	--[[30]] { name = "Occupational Hazard", desc = "Die to enemy players 50 times.", test = at("deaths", 50) },
	--[[31]] { name = "It's Personal", desc = "Add someone to the hit list from the unfinished business prompt.",
		test = at("revengeAdds", 1) },
	--[[32]] { name = "Battleground Regular", desc = "Win your first battleground.", test = at("bgWins", 1) },
	--[[33]] { name = "War Veteran", desc = "Win 25 battlegrounds.", test = at("bgWins", 25) },
	--[[34]] { name = "Field Marshal", desc = "Land 100 killing blows in battlegrounds.", test = at("bgKills", 100) },
	--[[35]] { name = "Slaughterhouse", desc = "Land 500 killing blows in battlegrounds.", test = at("bgKills", 500) },
	--[[36]] { name = "Dominating Performance", desc = "Land 10 or more killing blows in a single battleground.",
		test = at("bgBestKB", 10) },
	--[[37]] { name = "Warsong Champion", desc = "Win 10 matches in Warsong Gulch.", test = at("wsgWins", 10) },
	--[[38]] { name = "Basin Tactician", desc = "Win 10 matches in Arathi Basin.", test = at("abWins", 10) },
	--[[39]] { name = "Island Raider", desc = "Win 10 matches in Darkspear Islands.", test = at("dsWins", 10) },
	--[[40]] { name = "Honor Bound", desc = "Win your first 1v1 duel.", test = at("duelWins", 1) },
	--[[41]] { name = "Duelist", desc = "Win 25 duels.", test = at("duelWins", 25) },
	--[[42]] { name = "Undefeated", desc = "Win 5 duels in a row.", test = at("duelBest", 5) },
}
