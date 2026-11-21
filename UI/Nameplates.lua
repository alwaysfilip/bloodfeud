-- A skull above the nameplate of a listed player (amber for a member of a
-- listed guild), and a red cross beside the nameplate of an enemy who has
-- you targeted. Needs enemy nameplates to be shown.
local _, ns = ...

local W = ns.W

-- marks: the skulls, by nameplate unit. aims: the "targeting you" crosses.
local Nameplates = { marks = {}, aims = {}, pool = {} }
ns.Nameplates = Nameplates

local AIM = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" -- the red cross

local function acquire()
	local f = table.remove(Nameplates.pool)
	if f then return f end
	f = CreateFrame("Frame", nil, UIParent)
	f.icon = f:CreateTexture(nil, "OVERLAY")
	f.icon:SetAllPoints()
	return f
end

local function release(set, unit)
	local f = set[unit]
	if not f then return end
	set[unit] = nil
	f:Hide()
	f:ClearAllPoints()
	f:SetParent(UIParent)
	Nameplates.pool[#Nameplates.pool + 1] = f
end

local function attach(set, unit, texture, size, dx, r, g, b)
	if not ns.settings.nameplates then return end
	local api = _G.C_NamePlate
	if not (api and api.GetNamePlateForUnit) then return end
	local plate = api.GetNamePlateForUnit(unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
	local f = set[unit] or acquire()
	set[unit] = f
	f:SetParent(plate)
	f:SetSize(size, size)
	f:ClearAllPoints()
	f:SetPoint("BOTTOM", plate, "TOP", dx, 0)
	f.icon:SetTexture(texture)
	f.icon:SetVertexColor(r, g, b)
	f:Show()
end

local function mark(set, unit, ...)
	if type(unit) ~= "string" or unit:sub(1, 9) ~= "nameplate" then return end
	-- Attaching to a nameplate can be refused by the client; never let that
	-- surface as an error.
	local ok, err = pcall(attach, set, unit, ...)
	if not ok then ns:Debug("nameplate mark: %s", tostring(err)) end
end

local function skull(unit, r, g, b)
	mark(Nameplates.marks, unit, W.SKULL, 26, 0, r, g, b)
end

function Nameplates:Clear()
	for unit in pairs(self.marks) do
		release(self.marks, unit)
	end
end

--- Put a cross on the nameplate of everyone who has us targeted, and take
--- it off the ones who no longer do.
function Nameplates:Aims()
	local targeting, radar = ns.Targeting, ns.Radar
	local want = {}
	if targeting and radar and ns.settings.nameplates then
		for unit, key in pairs(radar.plates) do
			if targeting:Is(key) then want[unit] = true end
		end
	end
	for unit in pairs(self.aims) do
		if not want[unit] then release(self.aims, unit) end
	end
	for unit in pairs(want) do
		if not self.aims[unit] then mark(self.aims, unit, AIM, 20, 26, 1, 1, 1) end
	end
end

function Nameplates:Init()
	ns:Listen("LISTED_UNIT", function(unit) skull(unit, 1, 1, 1) end)
	ns:Listen("LISTED_GUILD_UNIT", function(unit) skull(unit, 1, 0.70, 0.28) end)
	ns:Listen("TARGETING_CHANGED", function() Nameplates:Aims() end)
	ns:On("NAME_PLATE_UNIT_REMOVED", function(unit)
		if type(unit) == "string" then
			release(Nameplates.marks, unit)
			release(Nameplates.aims, unit)
		end
	end)

	-- When the list changes, the marks on screen may be wrong: redo them.
	local pending = false
	local function rescan()
		if pending then return end
		pending = true
		C_Timer.After(0.5, function()
			pending = false
			Nameplates:Clear()
			ns.Detect.ScanNameplates()
		end)
	end
	-- Only the records that decide who is marked or alerted for: reports,
	-- guild reports, facts (a first-name entry being pinned) and bounties.
	-- Scores, totals, claims and sightings change all the time and must not
	-- make the alerts replay for whoever is standing in front of us.
	local RESCAN = { r = true, g = true, f = true, b = true }
	ns:Listen("LIST_CHANGED", function(id)
		if type(id) == "string" and id:sub(2, 2) == ":" and RESCAN[id:sub(1, 1)] then rescan() end
	end)
	ns:Listen("SESSION_CHANGED", rescan)
end
