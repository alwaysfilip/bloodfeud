-- Noticing listed players. Forever closes the combat log to addons, so the
-- only enemies an addon can see are the ones the client shows the player:
-- nameplates, target, focus and mouseover.
local _, ns = ...

local Util, Names = ns.Util, ns.Names

local Detect = { paused = false }
ns.Detect = Detect

local function plain(value, kind)
	if value == nil or Util.IsSecret(value) then return nil end
	if kind and type(value) ~= kind then return nil end
	return value
end

--- Read what the client will tell us about a unit, if it is an enemy
--- player. Returns nil for anything else, or when identity is restricted.
function Detect.Inspect(unit)
	if not plain(UnitExists(unit)) then return nil end
	if not plain(UnitIsPlayer(unit)) then return nil end

	local hostile = plain(UnitIsEnemy("player", unit))
	if not hostile then
		-- In sanctuaries the other faction is not attackable, but still the enemy.
		local mine, theirs = plain(UnitFactionGroup("player"), "string"), plain(UnitFactionGroup(unit), "string")
		hostile = mine ~= nil and theirs ~= nil and mine ~= theirs
	end
	if not hostile then return nil end

	local name = Names.OfUnit(unit)
	if not name then return nil end
	local info = { unit = unit, name = name, key = Names.Key(name) }
	info.guid = plain(UnitGUID(unit), "string")
	local _, _, classID = UnitClass(unit)
	info.class = plain(classID, "number")
	local _, _, raceID = UnitRace(unit)
	info.race = plain(raceID, "number")
	local level = plain(UnitLevel(unit), "number")
	if level and level > 0 then info.level = level end
	if _G.GetGuildInfo then
		local guild = plain(_G.GetGuildInfo(unit), "string")
		if guild and guild ~= "" then info.guild = guild end
	end
	return info
end

--- Which list entry, if any, is this player? Returns key, how, where how is
--- "name", "guid" (renamed since being listed) or "first" (the entry was
--- typed with a first name only).
function Detect.Match(store, info)
	if store:IsListed(info.key) then return info.key, "name" end
	if info.guid then
		local key = store:KeyForGuid(info.guid)
		if key then return key, "guid" end
	end
	local first = Names.FirstKey(info.name)
	if first and store:IsListed(first) then return first, "first" end
	return nil
end

local function handle(unit)
	local session = ns.session
	if not session or Detect.paused then return end
	local info = Detect.Inspect(unit)
	if not info then return end
	if ns.Feuds then ns.Feuds:Saw(info) end
	local store = session.store

	local key, how = Detect.Match(store, info)
	if key then
		local subject = store:Player(key)
		if not subject then return end
		local known = subject.facts and subject.facts.guid
		local otherCharacter = known and info.guid and known ~= info.guid
		-- An entry typed with only a first name that has since been pinned to
		-- one character does not apply to everyone who shares that first name.
		if how == "first" and otherCharacter then return end

		ns.Alerts:Player(subject, info, otherCharacter)
		if not otherCharacter then
			local now = GetServerTime()
			store:SetFacts(key, {
				guid = (not known) and info.guid or nil, -- the first sighting pins the character
				cur = info.name, class = info.class, race = info.race, level = info.level, guild = info.guild,
			}, session.me, now)
			if ns.Sightings then ns.Sightings:Report(key, info) end
		end
		ns:Fire("LISTED_UNIT", unit, key)
		return
	end

	if info.guild and store:IsGuildListed(info.guild) then
		local guild = store:Guild(Util.Fold(info.guild))
		if guild then ns.Alerts:Guild(guild, info) end
		ns:Fire("LISTED_GUILD_UNIT", unit, info)
	end
end

--- Look at a unit; safe to call for anything, at any time.
function Detect.Scan(unit)
	local ok, err = pcall(handle, unit)
	if not ok then ns:Debug("scan %s failed: %s", tostring(unit), tostring(err)) end
end

--- Look again at every nameplate currently on screen.
function Detect.ScanNameplates()
	for i = 1, 40 do
		Detect.Scan("nameplate" .. i)
	end
end

local function updatePause()
	local inInstance, kind = false, nil
	if _G.IsInInstance then
		local ok, a, b = pcall(_G.IsInInstance)
		if ok then inInstance, kind = a, b end
	end
	-- Dungeons, raids and PvP matches: identity is restricted there, and a
	-- battleground full of enemies is not what the list is for.
	Detect.paused = (inInstance and kind ~= "none") and true or false
end

function Detect:Init()
	ns:On("NAME_PLATE_UNIT_ADDED", function(unit) Detect.Scan(unit) end)
	ns:On("PLAYER_TARGET_CHANGED", function() Detect.Scan("target") end)
	ns:On("UPDATE_MOUSEOVER_UNIT", function() Detect.Scan("mouseover") end)
	ns:On("PLAYER_FOCUS_CHANGED", function() Detect.Scan("focus") end)
	ns:On("PLAYER_ENTERING_WORLD", updatePause)
	ns:On("ZONE_CHANGED_NEW_AREA", updatePause)
	updatePause()
end
