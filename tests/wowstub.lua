-- A small imitation of the WoW client API: enough to load every addon file
-- in the order the .toc gives and to play through a session. It checks that
-- the game-facing code runs without Lua errors; it cannot check that the
-- real client behaves the way this imitation does.
local Stub = {}

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
Stub.SECRET = SECRET

local Methods = {}
local WidgetMT = {}
local function noop() end
WidgetMT.__index = function(_, key)
	local m = Methods[key]
	if m then return m end
	-- Widget methods are PascalCase: accept any of them and do nothing. Other
	-- keys are the addon's own fields, which read as nil on a real frame.
	if type(key) == "string" and key:match("^%u") then return noop end
	return nil
end

local function widget(world, kind, name)
	local o = setmetatable({ kind = kind, widgetName = name, scripts = {}, attrs = {}, shown = true, text = "",
		enabled = true, value = 0, min = 0, max = 0, lines = {}, alpha = 1 }, WidgetMT)
	world.widgets[#world.widgets + 1] = o
	return o
end

function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:GetScript(name) return self.scripts[name] end
function Methods:HookScript(name, fn) self.scripts[name] = fn end
function Methods:HasScript() return true end
function Methods:RegisterEvent(event)
	local list = self.world.events[event] or {}
	self.world.events[event] = list
	list[#list + 1] = self
end
function Methods:Show()
	local was = self.shown
	self.shown = true
	if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Methods:Hide() self.shown = false end
function Methods:SetShown(v) if v then self:Show() else self:Hide() end end
function Methods:IsShown() return self.shown end
function Methods:IsVisible() return self.shown end
function Methods:SetText(t)
	self.text = t or ""
	if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function Methods:GetText() return self.text end
function Methods:SetEnabled(v) self.enabled = v and true or false end
function Methods:Enable() self.enabled = true end
function Methods:Disable() self.enabled = false end
function Methods:IsEnabled() return self.enabled end
function Methods:CreateFontString() local w = widget(self.world, "FontString"); w.world = self.world; return w end
function Methods:CreateTexture() local w = widget(self.world, "Texture"); w.world = self.world; return w end
function Methods:GetThumbTexture() local w = widget(self.world, "Texture"); w.world = self.world; return w end
function Methods:SetMinMaxValues(a, b) self.min, self.max = a, b end
function Methods:GetMinMaxValues() return self.min, self.max end
function Methods:SetValue(v)
	self.value = v
	if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
end
function Methods:GetValue() return self.value end
function Methods:GetVerticalScrollRange() return 0 end
function Methods:GetVerticalScroll() return 0 end
function Methods:IsForbidden() return false end
function Methods:AddLine(text) self.lines[#self.lines + 1] = text end
function Methods:AddMessage(text) self.world.chat[#self.world.chat + 1] = text end
function Methods:GetUnit() return "name", self.world.tooltipUnit end
function Methods:SetOwner() self.lines = {} end
function Methods:SetAttribute(k, v)
	if self.world and self.world.inCombat then error("ADDON_ACTION_BLOCKED: SetAttribute in combat") end
	self.attrs[k] = v
end
function Methods:GetAttribute(k) return self.attrs[k] end
function Methods:SetAlpha(a) self.alpha = a end
function Methods:GetAlpha() return self.alpha end
function Methods:Click(...) if self.scripts.OnClick then self.scripts.OnClick(self, ...) end end
function Methods:DoubleClick(...) if self.scripts.OnDoubleClick then self.scripts.OnDoubleClick(self, ...) end end

--- Install the imitation as globals and return the world that controls it.
function Stub.Install()
	local world = {
		now = 1000, epoch = 1795252375, timers = {}, events = {}, widgets = {}, chat = {}, sent = {}, errors = {},
		units = {}, menus = {}, roster = {}, friends = {}, bnetFriends = {}, inGuild = true, locked = false,
		inCombat = false, guild = "Northwind Trading", me = { first = "Olaf", surname = "Stormborn" },
		myFaction = "Alliance", myRank = 3, loopback = true,
		bgScores = {}, bgWinner = nil, bgRunTimeMs = 0, instanceName = nil, spiritHealerTime = 0,
		widgetsData = {}, pois = {}, containerItems = {}, currencies = {}, reputations = {}, merchant = {}, bags = {},
		pvpStats = { hk = 0, dk = 0, highestRank = 0, honorLevel = 0, honor = 0 },
	}
	local G = _G

	local function frame(kind, name)
		local w = widget(world, kind, name)
		w.world = world
		if name then G[name] = w end
		return w
	end

	G.issecretvalue = function(v) return v == SECRET end
	G.CreateFrame = function(kind, name) return frame(kind, name) end
	G.UIParent = frame("Frame")
	G.GameTooltip = frame("GameTooltip")
	G.DEFAULT_CHAT_FRAME = frame("ScrollingMessageFrame")
	G.UISpecialFrames = {}
	G.tinsert = table.insert
	G.date = os.date
	G.GetTime = function() return world.now end
	G.GetServerTime = function() return math.floor(world.epoch + world.now) end
	G.geterrorhandler = function() return function(err) world.errors[#world.errors + 1] = tostring(err) end end
	G.C_Timer = {
		After = function(delay, fn) world.timers[#world.timers + 1] = { at = world.now + delay, fn = fn } end,
		NewTicker = function(period, fn)
			local t = { at = world.now + period, fn = fn, period = period }
			function t:Cancel() self.cancelled = true end
			world.timers[#world.timers + 1] = t
			return t
		end,
	}

	-- Guild
	G.IsInGuild = function() return world.inGuild end
	G.IsGuildLeader = function() return world.myRank == 0 end
	G.GetGuildInfo = function(unit)
		if unit == "player" then
			if not world.inGuild then return nil end
			return world.guild, "Rank" .. world.myRank, world.myRank
		end
		local u = world.units[unit]
		if u and u.guild then return u.guild, "Member", 4 end
		return nil
	end
	G.GetNumGuildMembers = function() return #world.roster end
	G.GetGuildRosterInfo = function(i)
		local m = world.roster[i]
		-- name, rank name, rank index, level, class, zone, note, officer note, online
		if m then return m[1], "Rank" .. m[2], m[2], 60, "Class", "Zone", "", "", m[3] end
	end
	G.GuildControlGetNumRanks = function() return 6 end
	G.C_GuildInfo = {
		GuildRoster = function() world:Fire("GUILD_ROSTER_UPDATE") end,
		GuildControlGetRankFlags = function(order)
			local flags = {}
			for i = 1, 22 do flags[i] = false end
			flags[22] = order <= 2 -- guild master and the first rank below are officers
			return flags
		end,
		IsGuildOfficer = function() return world.myRank <= 1 end,
	}

	-- Units
	-- A unit's `targets` field says who it has targeted: "player", another
	-- token, or a unit table. "<unit>target" resolves through it.
	local function unitOf(token)
		if token == "player" then
			return { name = world.me.first, surname = world.me.surname, guid = "Player-1-00000001", isPlayer = true,
				faction = world.myFaction, class = 1, race = 1, level = 60 }
		end
		local base = type(token) == "string" and token:match("^(.+)target$")
		if base then
			local unit = unitOf(base)
			local target = unit and unit.targets
			if target == nil then return nil end
			if type(target) == "table" then return target end
			return unitOf(target)
		end
		return world.units[token]
	end
	-- world.compareSecret: the client withholds unit comparisons.
	G.UnitIsUnit = function(a, b)
		if world.compareSecret then return SECRET end
		local ua, ub = unitOf(a), unitOf(b)
		if not ua or not ub then return false end
		return ua == ub or (ua.guid ~= nil and ua.guid == ub.guid)
	end
	local function field(token, key)
		local u = unitOf(token)
		if not u then return nil end
		if u.secret then return SECRET end
		return u[key]
	end
	G.UnitExists = function(token) return unitOf(token) ~= nil end
	G.UnitIsPlayer = function(token) local u = unitOf(token); return u and u.isPlayer or false end
	G.UnitIsEnemy = function(_, token) local u = unitOf(token); return u and u.enemy or false end
	G.UnitIsFriend = function(_, token)
		local u = unitOf(token)
		return u ~= nil and not u.enemy and u.faction == world.myFaction
	end
	G.UnitCanAttack = G.UnitIsEnemy
	G.C_FriendList = {
		GetNumFriends = function() return #world.friends end,
		GetFriendInfoByIndex = function(i)
			local f = world.friends[i]
			return type(f) == "string" and { name = f } or f
		end,
	}
	G.C_BattleNet = {
		GetNumFriends = function() return #world.bnetFriends end,
		GetFriendNumGameAccounts = function(i)
			local f = world.bnetFriends[i]
			return f and #f or 0
		end,
		GetFriendGameAccountInfo = function(i, j)
			local f = world.bnetFriends[i]
			return f and f[j] or nil
		end,
	}
	G.UnitFactionGroup = function(token) return field(token, "faction") end
	G.UnitName = function(token) return field(token, "name"), field(token, "surname") end
	G.UnitNameUnmodified = G.UnitName
	G.UnitFullName = G.UnitName
	G.UnitGUID = function(token) return field(token, "guid") end
	G.UnitClass = function(token) return "Class", "ROGUE", field(token, "class") end
	G.UnitRace = function(token) return "Race", "Orc", field(token, "race") end
	G.UnitLevel = function(token) return field(token, "level") end
	G.UnitHealth = function(token) return field(token, "hp") or 100 end
	G.UnitHealthMax = function(token) return field(token, "maxHp") or 100 end
	G.UnitIsInMyGuild = function(token) local u = unitOf(token); return u and u.guildmate or false end
	G.InCombatLockdown = function() return world.inCombat and true or false end
	G.GetInstanceInfo = function()
		return world.instanceName or "Azeroth", world.instance or "none"
	end
	G.GetNumBattlefieldScores = function() return #world.bgScores end
	G.RequestBattlefieldScoreData = function() world.scoreRequests = (world.scoreRequests or 0) + 1 end
	G.GetBattlefieldWinner = function() return world.bgWinner end
	G.GetBattlefieldInstanceRunTime = function() return world.bgRunTimeMs or 0 end
	G.GetAreaSpiritHealerTime = function() return world.spiritHealerTime or 0 end
	G.C_PvP = {
		GetScoreInfo = function(i) return world.bgScores[i] end,
	}
	G.C_UIWidgetManager = {
		GetAllWidgetsBySetID = function(setID) return world.widgetsData[setID] or {} end,
		GetTopCenterWidgetSetID = function() return world.topWidgetSetID or 1 end,
		GetDoubleStatusBarWidgetVisualizationInfo = function(id) return world.widgetsData["bar:" .. id] end,
		GetIconAndTextWidgetVisualizationInfo = function(id) return world.widgetsData["icon:" .. id] end,
		GetTextWithStateWidgetVisualizationInfo = function(id) return world.widgetsData["text:" .. id] end,
	}
	G.GetPVPLifetimeStats = function()
		return world.pvpStats.hk, world.pvpStats.dk, world.pvpStats.highestRank
	end
	G.UnitHonorLevel = function() return world.pvpStats.honorLevel or 0 end
	G.UnitHonor = function() return world.pvpStats.honor or 0 end
	G.C_CurrencyInfo = {
		GetCurrencyListSize = function() return #world.currencies end,
		GetCurrencyListInfo = function(i) return world.currencies[i] end,
		GetCurrencyInfo = function(id)
			for _, c in ipairs(world.currencies) do
				if c.currencyID == id then return c end
			end
			return nil
		end,
	}
	G.C_Reputation = {
		GetNumFactions = function() return #world.reputations end,
		GetFactionDataByIndex = function(i) return world.reputations[i] end,
	}
	G.C_Item = {
		GetItemCount = function(itemID) return world.bags[itemID] or 0 end,
	}
	G.C_Container = {
		GetContainerNumSlots = function(bag) return bag == 0 and #world.containerItems or 0 end,
		GetContainerItemInfo = function(bag, slot) return bag == 0 and world.containerItems[slot] or nil end,
	}
	G.C_AreaPoiInfo = {
		GetAreaPOIForMap = function()
			local ids = {}
			for id in pairs(world.pois) do ids[#ids + 1] = id end
			return ids
		end,
		GetAreaPOIInfo = function(_, id) return world.pois[id] end,
	}
	G.GetMerchantNumItems = function() return #world.merchant end
	G.GetMerchantItemInfo = function(i)
		local m = world.merchant[i]
		if not m then return nil end
		return m.name, m.texture or "Interface\\Icons\\INV_Misc_QuestionMark", m.price or 0, 1, -1, false, m.extendedCost
	end
	G.GetMerchantItemID = function(i) return world.merchant[i] and world.merchant[i].itemID end
	G.GetMerchantItemLink = function(i) return world.merchant[i] and world.merchant[i].link end
	G.GetMerchantItemCostInfo = function(i)
		local m = world.merchant[i]
		return m and m.costs and #m.costs or 0
	end
	G.GetMerchantItemCostItem = function(i, j)
		local c = world.merchant[i] and world.merchant[i].costs and world.merchant[i].costs[j]
		if not c then return nil end
		return c.texture, c.value, c.link, c.name
	end
	G.DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
	G.DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
	G.UnitTokenFromGUID = function(guid)
		for token, u in pairs(world.units) do
			if u.guid == guid then return token end
		end
		return nil
	end
	-- Mail and trade. world.inbox: list of { sender, subject, money } (copper);
	-- world.money: the purse; world.tradeGive / world.tradeGet: copper offered.
	world.inbox, world.money, world.sendMoney = {}, 1000000, 0
	G.hooksecurefunc = function(name, fn)
		local original = G[name]
		G[name] = function(...)
			local a, b, c = original(...)
			fn(...)
			return a, b, c
		end
	end
	G.SetSendMailMoney = function(copper) world.sendMoney = copper end
	G.GetSendMailMoney = function() return world.sendMoney end
	G.SendMail = function(recipient) world.mailed = { to = recipient, copper = world.sendMoney } end
	G.GetInboxNumItems = function() return #world.inbox, #world.inbox end
	G.GetInboxHeaderInfo = function(i)
		local m = world.inbox[i]
		if not m then return nil end
		return nil, nil, m.sender, m.subject, m.money, 0, 30, 0, false, false, true, true, false
	end
	G.GetMoney = function() return world.money end
	G.GetPlayerTradeMoney = function() return world.tradeGive or 0 end
	G.GetTargetTradeMoney = function() return world.tradeGet or 0 end
	G.ERR_TRADE_COMPLETE = "Trade complete."
	-- world.recap: list of { sourceName, sourceGUID, timestamp }, newest first
	G.C_DeathRecap = {
		HasRecapEvents = function() return world.recap ~= nil end,
		GetRecapEvents = function() return world.recap or {} end,
	}

	-- Addon messages
	local function deliver(prefix, text, sender)
		world.timers[#world.timers + 1] = { at = world.now + 0.2, fn = function()
			world:Fire("CHAT_MSG_ADDON", prefix, text, "GUILD", sender)
		end }
	end
	G.C_ChatInfo = {
		RegisterAddonMessagePrefix = function() return 0 end,
		InChatMessagingLockdown = function() return world.locked end,
		SendAddonMessage = function(prefix, text, channel)
			assert(#text <= 255, "addon message over 255 bytes")
			assert(channel == "GUILD")
			if world.locked then return 11 end
			world.sent[#world.sent + 1] = { prefix = prefix, text = text }
			if world.loopback then deliver(prefix, text, world.me.first .. "-" .. world.me.surname) end
			return 0
		end,
	}
	G.ChatThrottleLib = { version = 32 }
	function G.ChatThrottleLib:SendAddonMessage(_, prefix, text, chattype, _, _, callback, arg)
		local result = G.C_ChatInfo.SendAddonMessage(prefix, text, chattype)
		if callback then callback(arg, result == 0, result) end
	end
	function world:Receive(prefix, text, sender) deliver(prefix, text, sender) end

	-- Libraries
	local libs = {
		["LibDataBroker-1.1"] = { NewDataObject = function(_, _, obj) world.broker = obj; return obj end },
		["LibDBIcon-1.0"] = { Register = function() world.iconRegistered = true end, Show = function() end,
			Hide = function() end },
	}
	G.LibStub = { GetLibrary = function(_, name) return libs[name], 1 end }

	-- Interface frameworks
	G.Enum = {
		SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, AddOnMessageLockdown = 11 },
		TooltipDataType = { Unit = 2 },
		ClubRoleIdentifier = { Owner = 1, Leader = 2, Moderator = 3, Member = 4 },
		AddOnRestrictionType = { Combat = 0, Chat = 5 },
	}
	G.Menu = { ModifyMenu = function(tag, cb) world.menus[tag] = cb end }
	G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) world.tooltipHook = fn end }
	local category = { GetID = function() return 7 end }
	G.Settings = {
		VarType = { Boolean = "boolean", Number = "number" },
		RegisterVerticalLayoutCategory = function() return category end,
		RegisterAddOnSetting = function() return { SetValueChangedCallback = function() end } end,
		RegisterProxySetting = function() return {} end,
		CreateCheckbox = function() world.checkboxes = (world.checkboxes or 0) + 1 end,
		CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
		CreateSlider = function() world.sliders = (world.sliders or 0) + 1 end,
		RegisterAddOnCategory = function() end,
		OpenToCategory = function(id) world.optionsOpened = id end,
	}
	G.SlashCmdList = {}
	G.IsShiftKeyDown = function() return world.shift or false end
	G.IsInInstance = function() return world.instance and true or false, world.instance or "none" end
	G.PlaySound = function(id) world.sounds = (world.sounds or 0) + 1; world.lastSound = id end
	G.C_Map = {
		GetBestMapForUnit = function() return 1434 end,
		GetPlayerMapPosition = function() return { GetXY = function() return 0.452, 0.621 end } end,
		GetMapInfo = function() return { name = "Stranglethorn Vale" } end,
	}
	G.C_CreatureInfo = {
		GetClassInfo = function(id) return { className = "Rogue", classFile = "ROGUE", classID = id } end,
		GetRaceInfo = function(id) return { raceName = "Orc", raceID = id } end,
	}
	G.RAID_CLASS_COLORS = { ROGUE = { r = 1, g = 0.96, b = 0.41, colorStr = "fffff468" } }
	G.CLASS_ICON_TCOORDS = { ROGUE = { 0.49609375, 0.7421875, 0, 0.25 } }
	G.C_NamePlate = { GetNamePlateForUnit = function(token) return world.units[token] and frame("NamePlate") or nil end }
	-- world.addons: other addons that are loaded; world.disabled: switched off by us
	world.addons, world.disabled = {}, {}
	G.C_AddOns = {
		GetAddOnMetadata = function() return "test" end,
		IsAddOnLoaded = function(name) return world.addons[name] or false end,
		DisableAddOn = function(name) world.disabled[name] = true end,
	}
	G.C_RestrictedActions = { IsAddOnRestrictionActive = function() return false end }
	G.C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
	G.GetBuildInfo = function() return "1.60.1", "70959", "Nov 1 2026", 16001 end
	G.GetLocale = function() return world.locale or "enUS" end
	-- world.spells: spell id -> the name this client has for it
	world.spells = { [1784] = "Stealth", [1856] = "Vanish", [5215] = "Prowl", [58984] = "Shadowmeld", [133] = "Fireball" }
	G.C_Spell = {
		GetSpellName = function(id) return world.spells[id] end,
		GetSpellTexture = function(id) return world.spells[id] and ("Interface\\Icons\\Spell_" .. tostring(id)) or nil end,
	}
	G.GetNormalizedRealmName = function() return nil end
	G.RegionalUniqueNamesEnabled = function() return true end
	G.WOW_PROJECT_ID = 18
	G.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " ",
		CHARACTERNAME_REALMNAME_SEPARATOR = "-" } }

	function world:Fire(event, ...)
		local list = self.events[event]
		if not list then return end
		for i = 1, #list do
			local handler = list[i].scripts.OnEvent
			if handler then handler(list[i], event, ...) end
		end
	end

	--- Let virtual time pass, running timers and frame OnUpdate scripts.
	function world:Advance(seconds)
		local stop = self.now + seconds
		while self.now < stop do
			self.now = self.now + 0.1
			local due = {}
			for i = #self.timers, 1, -1 do
				local t = self.timers[i]
				if t.cancelled then
					table.remove(self.timers, i)
				elseif t.at <= self.now then
					due[#due + 1] = t
					if t.period then t.at = t.at + t.period else table.remove(self.timers, i) end
				end
			end
			table.sort(due, function(a, b) return a.at < b.at end)
			for i = 1, #due do due[i].fn() end
			for i = 1, #self.widgets do
				local w = self.widgets[i]
				if w.shown and w.scripts.OnUpdate then w.scripts.OnUpdate(w, 0.1) end
			end
		end
	end

	--- Load the addon exactly as the client would: the files the .toc lists,
	--- in that order (libraries are imitated above, so those are skipped).
	function world:LoadAddon(root)
		local ns = {}
		local loaded = {}
		for line in io.lines(root .. "/BusinessMeeting.toc") do
			line = line:gsub("%s+$", "")
			if line ~= "" and line:sub(1, 1) ~= "#" and not line:find("^Libs") then
				local path = root .. "/" .. line:gsub("\\", "/")
				local chunk = assert(loadfile(path), "toc lists a file that does not load: " .. line)
				chunk("BusinessMeeting", ns)
				loaded[#loaded + 1] = line
			end
		end
		self.ns = ns
		return ns, loaded
	end

	return world
end

return Stub
