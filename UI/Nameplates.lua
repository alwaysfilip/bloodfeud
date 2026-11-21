-- A skull above the nameplate of a listed player (amber for a member of a
-- listed guild). Needs enemy nameplates to be shown.
local _, ns = ...

local W = ns.W

local Nameplates = { marks = {}, pool = {} }
ns.Nameplates = Nameplates

local function acquire()
	local f = table.remove(Nameplates.pool)
	if f then return f end
	f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(26, 26)
	f.icon = f:CreateTexture(nil, "OVERLAY")
	f.icon:SetAllPoints()
	f.icon:SetTexture(W.SKULL)
	return f
end

local function release(unit)
	local f = Nameplates.marks[unit]
	if not f then return end
	Nameplates.marks[unit] = nil
	f:Hide()
	f:ClearAllPoints()
	f:SetParent(UIParent)
	Nameplates.pool[#Nameplates.pool + 1] = f
end

local function attach(unit, r, g, b)
	if not ns.settings.nameplates then return end
	local api = _G.C_NamePlate
	if not (api and api.GetNamePlateForUnit) then return end
	local plate = api.GetNamePlateForUnit(unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
	local f = Nameplates.marks[unit] or acquire()
	Nameplates.marks[unit] = f
	f:SetParent(plate)
	f:ClearAllPoints()
	f:SetPoint("BOTTOM", plate, "TOP", 0, 0)
	f.icon:SetVertexColor(r, g, b)
	f:Show()
end

local function mark(unit, r, g, b)
	if type(unit) ~= "string" or unit:sub(1, 9) ~= "nameplate" then return end
	-- Attaching to a nameplate can be refused by the client; never let that
	-- surface as an error.
	local ok, err = pcall(attach, unit, r, g, b)
	if not ok then ns:Debug("nameplate mark: %s", tostring(err)) end
end

function Nameplates:Clear()
	for unit in pairs(self.marks) do
		release(unit)
	end
end

function Nameplates:Init()
	ns:Listen("LISTED_UNIT", function(unit) mark(unit, 1, 1, 1) end)
	ns:Listen("LISTED_GUILD_UNIT", function(unit) mark(unit, 1, 0.70, 0.28) end)
	ns:On("NAME_PLATE_UNIT_REMOVED", function(unit)
		if type(unit) == "string" then release(unit) end
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
	ns:Listen("LIST_CHANGED", function(id)
		if type(id) == "string" and id:sub(1, 5) ~= "seen:" then rescan() end
	end)
	ns:Listen("SESSION_CHANGED", rescan)
end
