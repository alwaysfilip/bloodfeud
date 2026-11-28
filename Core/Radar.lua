-- The radar: which enemy players are around right now. Forever does not let
-- addons read where an enemy stands, so this is a list, not a map: everyone
-- the client has shown us (nameplate, target, mouseover, focus) in the last
-- minute, with the ones on the list or with a bounty first.
local _, ns = ...

local Util = ns.Util

local Radar = { list = {}, plates = {}, newAt = 0 }
ns.Radar = Radar

Radar.KEEP = 60 -- seconds an enemy stays on the radar after last being seen
Radar.FORGET = 300 -- and in memory, for the "new enemy" check
Radar.STEALTH_GRACE = 1.5 -- the client may still show them for a moment after the cast

--- Priority tags: 3 Kill on Sight, 2 bounty, 1 member of a listed guild.
function Radar.Tag(info, s)
	s = s or ns.session
	if not s then return 0, nil end
	local key = ns.Detect.Match(s.store, info)
	if key then return 3, key end
	if ns.Bounties and ns.Bounties:Worth(info) > 0 then return 2, nil end
	if info.guild and s.store:IsGuildListed(info.guild) then return 1, nil end
	return 0, nil
end

--- Detect saw an enemy player through `unit`.
function Radar:Saw(info, unit)
	if not info or not info.key then return end
	local now = GetTime()
	local entry = self.list[info.key]
	-- Someone whose nameplate is still up never left, however long ago the
	-- client last gave us a reason to look at them.
	local fresh = not entry or (not entry.plate and now - entry.at > Radar.KEEP)
	if not entry then
		entry = {}
		self.list[info.key] = entry
	end
	entry.info = Util.Copy(info)
	entry.info.unit = nil
	entry.at = now
	-- Seen again a while after going into stealth: they are out of it.
	if entry.stealth and now - entry.stealth > Radar.STEALTH_GRACE then entry.stealth, entry.stealthSpell = nil, nil end
	if type(unit) == "string" and unit:find("^nameplate") then
		local previous = self.plates[unit]
		if previous and previous ~= info.key then self:PlateGone(unit) end -- the token was reused
		entry.plate = unit
		self.plates[unit] = info.key
	end
	if fresh then
		entry.first = now
		self.newAt = now
		if ns.Hotspots and ns.Fmt then
			local map, x, y = ns.Fmt.PlayerPosition()
			if map then ns.Hotspots:Record("radar", map, x, y, info.name) end
		end
		ns:Fire("RADAR_NEW", entry)
	end
	ns:Fire("RADAR_CHANGED")
end

--- An enemy we can see just went into stealth (`spell` is what they used).
--- Their nameplate is about to go; the radar keeps them, marked, for as long
--- as it remembers anyone.
function Radar:Stealthed(info, spell)
	local entry = self.list[info.key]
	if not entry then return end
	entry.stealth, entry.stealthSpell = GetTime(), spell
	ns:Fire("RADAR_CHANGED")
end

--- A nameplate left the screen: whoever it showed is out of sight.
function Radar:PlateGone(unit)
	local key = self.plates[unit]
	if not key then return end
	self.plates[unit] = nil
	local entry = self.list[key]
	if entry and entry.plate == unit then
		entry.plate = nil
		entry.at = GetTime() -- seen until this moment: linger from now
	end
	ns:Fire("RADAR_CHANGED")
end

--- Enemies to show, most important and most recent first:
--- { info, at, plate, tag, listKey, targeting, stealth }.
function Radar:Visible()
	local now = GetTime()
	local out = {}
	local s = ns.session
	for key, entry in pairs(self.list) do
		local age = now - entry.at
		if entry.plate or age <= Radar.KEEP then
			entry.tag, entry.listKey = Radar.Tag(entry.info, s)
			local on, what = false, nil
			if ns.Targeting then on, what = ns.Targeting:Is(key) end
			entry.targeting = on and what or false -- "me", "pet" or false
			out[#out + 1] = entry
		elseif age > Radar.FORGET then
			self.list[key] = nil
		end
	end
	local weight = { me = 2, pet = 1 }
	table.sort(out, function(a, b)
		-- Whoever has us targeted comes first, then whoever is on the pet.
		local wa, wb = weight[a.targeting] or 0, weight[b.targeting] or 0
		if wa ~= wb then return wa > wb end
		if a.tag ~= b.tag then return a.tag > b.tag end
		local pa, pb = a.plate and 1 or 0, b.plate and 1 or 0
		if pa ~= pb then return pa > pb end
		if a.at ~= b.at then return a.at > b.at end
		return a.info.key < b.info.key
	end)
	return out
end

function Radar:Clear()
	self.list, self.plates = {}, {}
	ns:Fire("RADAR_CHANGED")
end

function Radar:Init()
	ns:On("NAME_PLATE_UNIT_REMOVED", function(unit) Radar:PlateGone(unit) end)
	-- Entering an instance: whoever was around outside is not any more.
	ns:On("PLAYER_ENTERING_WORLD", function() Radar:Clear() end)
end
