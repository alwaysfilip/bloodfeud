-- World PvP Hotspots: aggregates recent open-world activity across the guild
-- (sightings, open-world kills/deaths and fresh radar contacts) over a rolling
-- 60-minute window. Purely guild-local — no external server or world channel.
local _, ns = ...

local Fmt = ns.Fmt

local Hotspots = { events = {} }
ns.Hotspots = Hotspots

Hotspots.WINDOW = 60 * 60 -- 60 minutes
Hotspots.MAX_EVENTS = 250

--- Record one open-world activity event: kind = "sighting"|"kill"|"death"|"radar".
function Hotspots:Record(kind, mapID, x, y, who)
	if not mapID then return end
	local now = GetServerTime()
	local list = self.events
	list[#list + 1] = { t = now, kind = kind, map = mapID, x = x, y = y, who = who }
	while #list > Hotspots.MAX_EVENTS do
		table.remove(list, 1)
	end
	ns:Fire("HOTSPOTS_CHANGED")
end

--- Active zones over the last hour, hottest first.
function Hotspots:List(now)
	now = now or GetServerTime()
	local cutoff = now - Hotspots.WINDOW
	local kept, byMap = {}, {}
	for i = 1, #self.events do
		local e = self.events[i]
		if e.t >= cutoff then
			kept[#kept + 1] = e
			local z = byMap[e.map]
			if not z then
				z = {
					key = "zone:" .. tostring(e.map), map = e.map, zone = Fmt.Zone(e.map) or ("Map " .. tostring(e.map)),
					sightings = 0, kills = 0, deaths = 0, radar = 0, total = 0, score = 0,
					lastAt = 0, lastX = nil, lastY = nil,
				}
				byMap[e.map] = z
			end
			if e.kind == "sighting" then
				z.sightings = z.sightings + 1
				z.score = z.score + 2
			elseif e.kind == "kill" then
				z.kills = z.kills + 1
				z.score = z.score + 3
			elseif e.kind == "death" then
				z.deaths = z.deaths + 1
				z.score = z.score + 2
			else
				z.radar = z.radar + 1
				z.score = z.score + 1
			end
			z.total = z.total + 1
			if e.t >= z.lastAt then
				z.lastAt = e.t
				if e.x and e.y then z.lastX, z.lastY = e.x, e.y end
			end
		end
	end
	self.events = kept

	local out = {}
	for _, z in pairs(byMap) do out[#out + 1] = z end
	table.sort(out, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		if a.lastAt ~= b.lastAt then return a.lastAt > b.lastAt end
		return a.zone < b.zone
	end)
	return out
end
