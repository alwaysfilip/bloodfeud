-- Loaded first: the shared namespace, saved variables, events and chat output.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.TITLE = "Business Meeting"
ns.FULL_TITLE = "Business Meeting - PvP"
-- The addon was called Blood Feud until 0.4.0. The two channel names below
-- are what its copies listen on, so they keep the old name: nobody sees
-- them, and changing them would cut off everyone who has not updated.
ns.PREFIX = "BloodFeud" -- state: hellos and updates
ns.PREFIX_SIGHT = "BloodFeudS" -- sightings, on their own throttle allowance
ns.L = {}
ns.debugLog = {}

local DEFAULTS = {
	sound = true, -- play a sound on a Kill on Sight alert
	banner = true, -- show the on-screen banner
	chat = true, -- print a chat line
	nameplates = true, -- mark listed players on their nameplate
	guildAlerts = true, -- quieter alert for members of a listed guild
	sightSend = true, -- tell the guild when I meet a listed player
	sightShow = true, -- show sightings reported by guildmates
	alertCooldown = 60, -- seconds before the same player alerts again
	revenge = true, -- offer to list an enemy who keeps killing me
	revengeCount = 2, -- ...after this many deaths to them
	revengeWindow = 30, -- ...within this many minutes
	radar = true, -- the radar window
	radarAuto = true, -- ...shown only while enemies are around
	radarSound = false, -- ...with a ping for each new enemy
	bgTargets = true, -- battleground enemy & flag carrier target list
	bgTargetsAllies = false, -- ...also list allies in the battleground targets window
	bgTimers = true, -- battleground countdown bars and score projection
	cdTracker = true, -- hybrid enemy cooldown tracker ("Counterclock")
	cdDuels = true, -- ...auto-open in 1v1 duels
	cdWorld = true, -- ...auto-open when targeting an enemy in the open world
	cdBG = false, -- ...also track target cooldowns inside battlegrounds
	capWarnings = true, -- warn in chat when Honor or BG Marks approach their cap
	hudFade = false, -- fade HUD windows while idle, restore on hover
	bountyAlerts = true, -- alert when someone with a bounty shows up
	dealBanner = true, -- a banner for my own killing blows on enemy players
	targetAlerts = true, -- alert when an enemy player targets me
	targetSound = true, -- ...with a sound
	targetPet = true, -- ...also when it is my pet they target
	stealthAlerts = true, -- alert when an enemy player near me goes into stealth
	debug = false,
}

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

function ns:InitDB()
	local db = _G.BusinessMeetingDB
	if type(db) ~= "table" then
		-- First run under the new name: take over what Blood Feud saved, which
		-- the stand-in addon of that name has had the game load for us.
		local old = _G.BloodFeudDB
		if type(old) == "table" then
			db = old
			db.importedFrom = "BloodFeud"
			self.imported = true
		else
			db = {}
		end
		_G.BusinessMeetingDB = db
	end
	db.schema = db.schema or 1
	db.settings = type(db.settings) == "table" and db.settings or {}
	db.guilds = type(db.guilds) == "table" and db.guilds or {}
	db.minimap = type(db.minimap) == "table" and db.minimap or {}
	for key, value in pairs(DEFAULTS) do
		if db.settings[key] == nil then db.settings[key] = value end
	end
	self.db = db
	self.settings = db.settings
end

ns.DEFAULTS = DEFAULTS

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------

local TAG = "|cffff5a4d[BM]|r "

function ns:Print(text)
	local frame = _G.DEFAULT_CHAT_FRAME
	if frame then
		frame:AddMessage(TAG .. tostring(text))
	else
		print(TAG .. tostring(text))
	end
end

--- Keeps the last few hundred lines in memory (and in the saved variables
--- when debug is on) so a problem can be read back from disk afterwards.
function ns:Debug(fmt, ...)
	local ok, text = pcall(string.format, fmt, ...)
	if not ok then text = tostring(fmt) end
	local log = self.debugLog
	log[#log + 1] = date("%H:%M:%S ") .. text
	if #log > 300 then table.remove(log, 1) end
	if self.settings and self.settings.debug then
		self:Print("|cff888888" .. text .. "|r")
	end
end

---------------------------------------------------------------------------
-- Events: one frame, many listeners, errors do not stop the others
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local listeners = {}
ns.eventFrame = frame

local function report(err)
	local handler = geterrorhandler and geterrorhandler()
	if handler then handler(err) end
	return err
end

--- Call fn(...) so that an error is reported but does not propagate.
function ns.Safe(fn, ...)
	return xpcall(fn, report, ...)
end

--- Listen for a game event. Unknown events (older or newer clients) are
--- skipped instead of raising.
function ns:On(event, fn)
	local list = listeners[event]
	if not list then
		if not pcall(frame.RegisterEvent, frame, event) then
			self:Debug("event not available: %s", event)
			return false
		end
		list = {}
		listeners[event] = list
	end
	list[#list + 1] = fn
	return true
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = listeners[event]
	if not list then return end
	for i = 1, #list do
		ns.Safe(list[i], ...)
	end
end)

---------------------------------------------------------------------------
-- Internal signals between modules
---------------------------------------------------------------------------

local signals = {}

--- Subscribe to an addon-internal signal such as "LIST_CHANGED".
function ns:Listen(signal, fn)
	local list = signals[signal]
	if not list then
		list = {}
		signals[signal] = list
	end
	list[#list + 1] = fn
end

function ns:Fire(signal, ...)
	local list = signals[signal]
	if not list then return end
	for i = 1, #list do
		ns.Safe(list[i], ...)
	end
end
