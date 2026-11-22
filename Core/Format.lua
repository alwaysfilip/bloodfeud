-- Turning stored facts into text: class colours, "60 Orc Rogue", zone names.
local _, ns = ...

local Util, Names = ns.Util, ns.Names
local format, floor = string.format, math.floor

local Fmt = {}
ns.Fmt = Fmt

Fmt.RED = "ffff8a80"
Fmt.AMBER = "ffffb347"
Fmt.GOLD = "fff0c75e"
Fmt.GREY = "ffa9a69b"
Fmt.LINK = "ff8fd3ff"

function Fmt.Color(hex, text)
	return "|c" .. hex .. text .. "|r"
end

local function classInfo(classID)
	local api = _G.C_CreatureInfo and _G.C_CreatureInfo.GetClassInfo
	if not api or not classID then return nil end
	local ok, info = pcall(api, classID)
	if ok and type(info) == "table" then return info end
	return nil
end

--- Localised class name for a class id, or nil.
function Fmt.ClassName(classID)
	local info = classInfo(classID)
	return info and info.className or nil
end

--- Localised race name for a race id, or nil.
function Fmt.RaceName(raceID)
	local api = _G.C_CreatureInfo and _G.C_CreatureInfo.GetRaceInfo
	if not api or not raceID then return nil end
	local ok, info = pcall(api, raceID)
	if ok and type(info) == "table" then return info.raceName end
	return nil
end

--- Colour code (AARRGGBB) for a class id, or nil.
function Fmt.ClassHex(classID)
	local info = classInfo(classID)
	local file = info and info.classFile
	if not file then return nil end
	local colors = _G.RAID_CLASS_COLORS
	local color = colors and colors[file]
	if not color and _G.C_ClassColor and _G.C_ClassColor.GetClassColor then
		local ok, c = pcall(_G.C_ClassColor.GetClassColor, file)
		if ok then color = c end
	end
	if not color then return nil end
	if color.colorStr then return color.colorStr end
	return format("ff%02x%02x%02x", floor((color.r or 1) * 255 + 0.5), floor((color.g or 1) * 255 + 0.5),
		floor((color.b or 1) * 255 + 0.5))
end

--- Class token ("ROGUE") for a class id, or nil.
function Fmt.ClassFile(classID)
	local info = classInfo(classID)
	return info and info.classFile or nil
end

--- Class colour as r, g, b (0..1) for a class id, or nil.
function Fmt.ClassRGB(classID)
	local hex = Fmt.ClassHex(classID)
	if type(hex) ~= "string" or #hex < 8 then return nil end
	local r, g, b = tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), tonumber(hex:sub(7, 8), 16)
	if not (r and g and b) then return nil end
	return r / 255, g / 255, b / 255
end

--- "Orc Rogue": race and class without the level; "" when neither is known.
function Fmt.Kind(facts)
	if not facts then return "" end
	local parts = {}
	local race = Fmt.RaceName(facts.race)
	if race then parts[#parts + 1] = race end
	local class = Fmt.ClassName(facts.class)
	if class then parts[#parts + 1] = class end
	return table.concat(parts, " ")
end

--- Display name of a listed player, coloured by class when it is known.
function Fmt.PlayerName(subject)
	local text = Names.Display(subject.name)
	local hex = subject.facts and Fmt.ClassHex(subject.facts.class)
	if hex then return Fmt.Color(hex, text) end
	return text
end

--- "60 Orc Rogue" from whatever is known; "" when nothing is.
function Fmt.Describe(facts)
	if not facts then return "" end
	local parts = {}
	if facts.level then parts[#parts + 1] = tostring(facts.level) end
	local race = Fmt.RaceName(facts.race)
	if race then parts[#parts + 1] = race end
	local class = Fmt.ClassName(facts.class)
	if class then parts[#parts + 1] = class end
	return table.concat(parts, " ")
end

--- Zone name for a map id, or nil.
--- "4–9": kills in green, deaths in red; a grey dash before any fight.
function Fmt.Score(kills, deaths)
	kills, deaths = kills or 0, deaths or 0
	if kills + deaths == 0 then return Fmt.Color(Fmt.GREY, "–") end
	return Fmt.Color("ff8fd18f", tostring(kills)) .. Fmt.Color(Fmt.GREY, "–") .. Fmt.Color(Fmt.RED, tostring(deaths))
end

function Fmt.Zone(mapID)
	local api = _G.C_Map and _G.C_Map.GetMapInfo
	if not api or not mapID then return nil end
	local ok, info = pcall(api, mapID)
	if ok and type(info) == "table" then return info.name end
	return nil
end

--- " 45, 62" from per-mille coordinates; "" when unknown.
function Fmt.Coords(x, y)
	if not x or not y then return "" end
	return format(" %d, %d", floor(x / 10 + 0.5), floor(y / 10 + 0.5))
end

--- "2 min ago" for a server timestamp.
function Fmt.Ago(ts)
	if not ts then return "" end
	local now = _G.GetServerTime and _G.GetServerTime() or ts
	return Util.Ago(now - ts, ns.L)
end

--- Where the player stands: map id and per-mille x, y (any may be nil).
function Fmt.PlayerPosition()
	local map = _G.C_Map
	if not (map and map.GetBestMapForUnit and map.GetPlayerMapPosition) then return nil end
	local ok, mapID = pcall(map.GetBestMapForUnit, "player")
	if not ok or type(mapID) ~= "number" then return nil end
	local okPos, pos = pcall(map.GetPlayerMapPosition, mapID, "player")
	if okPos and pos and pos.GetXY then
		local x, y = pos:GetXY()
		if type(x) == "number" and type(y) == "number" and not Util.IsSecret(x) then
			return mapID, floor(x * 1000 + 0.5), floor(y * 1000 + 0.5)
		end
	end
	return mapID
end
