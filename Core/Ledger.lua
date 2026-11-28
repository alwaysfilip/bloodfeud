-- War Ledger for World of Warcraft: Forever (inspired by Kinfolk: PvP WarLedger).
-- Tracks Honor vs. 25,000 cap (with cap warnings), Battleground Marks (WSG, AB,
-- AV, Darkspear Islands vs. 30 cap), PvP Rank / Rank Points, PvP Legacy Points,
-- BG reputations, and a PvP Vendor Catalog + Wishlist that calculates exactly
-- what resources and estimated battlegrounds remain.
local _, ns = ...

local Util, Names = ns.Util, ns.Names
local floor = math.floor

local Ledger = { warnedHonor = 0, warnedMarks = {}, events = {} }
ns.Ledger = Ledger

Ledger.HONOR_CAP = 25000
Ledger.MARK_CAP = 30
Ledger.WARN_HIGH = 0.85
Ledger.WARN_CRITICAL = 0.95

-- Classic/Forever BG Mark definitions (bag itemIDs + dynamic currency matching).
local MARK_DEFS = {
	{ key = "wsg", label = "Warsong Gulch Mark", itemID = 20558, match = "warsong" },
	{ key = "ab", label = "Arathi Basin Mark", itemID = 20559, match = "arathi" },
	{ key = "av", label = "Alterac Valley Mark", itemID = 20560, match = "alterac" },
	{ key = "ds", label = "Darkspear Islands Mark", itemID = nil, match = "darkspear" },
}

-- Classic/Forever BG faction names (Alliance & Horde).
local BG_REPS = {
	"silverwing sentinels", "warsong outriders",
	"league of arathor", "the defilers",
	"stormpike guard", "frostwolf clan",
	"theramore expeditionary force", "darkspear raiders",
}

local STANDING_NAMES = {
	[1] = "Hated", [2] = "Hostile", [3] = "Unfriendly", [4] = "Neutral",
	[5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted",
}

local function plain(value, kind)
	if value == nil or Util.IsSecret(value) then return nil end
	if kind and type(value) ~= kind then return nil end
	return value
end

local function isBGRep(name)
	local lo = Util.Fold(name or "")
	for i = 1, #BG_REPS do
		if lo == BG_REPS[i] or lo:find(BG_REPS[i], 1, true) then return true end
	end
	return false
end

local function matchMarkKey(name)
	local lo = Util.Fold(name or "")
	if not lo:find("mark", 1, true) then return nil end
	for i = 1, #MARK_DEFS do
		if lo:find(MARK_DEFS[i].match, 1, true) then return MARK_DEFS[i].key end
	end
	return nil
end

local function scanBagMarks(marks)
	local container = _G.C_Container
	if not (container and container.GetContainerNumSlots and container.GetContainerItemInfo) then return end
	local totals = {}
	for bag = 0, 4 do
		local okN, slots = pcall(container.GetContainerNumSlots, bag)
		slots = okN and plain(slots, "number") or 0
		for slot = 1, slots do
			local okI, info = pcall(container.GetContainerItemInfo, bag, slot)
			if okI and type(info) == "table" then
				local qty = plain(info.stackCount, "number") or 1
				local link = plain(info.hyperlink, "string")
				local name = plain(info.itemName, "string")
				if not name and link then name = link:match("%[(.-)%]") end
				local mkey = name and matchMarkKey(name)
				if mkey then
					totals[mkey] = (totals[mkey] or 0) + qty
					if marks[mkey] and name then marks[mkey].label = name end
				end
			end
		end
	end
	for mkey, qty in pairs(totals) do
		if marks[mkey] and qty > marks[mkey].count then marks[mkey].count = qty end
	end
end

--- Read current Forever PvP currencies, marks, rank and BG reputations.
function Ledger:Snapshot()
	local honor, honorCap = 0, Ledger.HONOR_CAP
	local rankPoints, rankCap, legacyPoints = 0, 0, nil
	local marks = {}
	for i = 1, #MARK_DEFS do
		local def = MARK_DEFS[i]
		local bagCount = 0
		if def.itemID then
			local getCount = (_G.C_Item and _G.C_Item.GetItemCount) or _G.GetItemCount
			if getCount then
				local ok, n = pcall(getCount, def.itemID, true)
				bagCount = ok and plain(n, "number") or 0
			end
		end
		marks[def.key] = { key = def.key, label = def.label, count = bagCount, cap = Ledger.MARK_CAP }
	end
	scanBagMarks(marks)

	local cur = _G.C_CurrencyInfo
	if cur and cur.GetCurrencyListSize and cur.GetCurrencyListInfo then
		local okN, n = pcall(cur.GetCurrencyListSize)
		n = okN and plain(n, "number") or 0
		for i = 1, n do
			local okI, info = pcall(cur.GetCurrencyListInfo, i)
			if okI and type(info) == "table" and not info.isHeader then
				local name = plain(info.name, "string")
				local qty = plain(info.quantity, "number") or 0
				local maxQ = plain(info.maxQuantity, "number") or 0
				if name then
					local lo = Util.Fold(name)
					local mkey = matchMarkKey(name)
					if mkey then
						marks[mkey].count = math.max(marks[mkey].count, qty)
						marks[mkey].label = name
						if maxQ > 0 then marks[mkey].cap = maxQ end
					elseif lo == "honor" or lo == "honor points" then
						honor = qty
						if maxQ > 0 then honorCap = maxQ end
					elseif lo:find("rank point", 1, true) then
						rankPoints = qty
						if maxQ > 0 then rankCap = maxQ end
					elseif lo:find("legacy", 1, true) and lo:find("pvp", 1, true) then
						legacyPoints = qty
					end
				end
			end
		end
	end

	-- Fallback for Honor / Rank when not listed as standard currencies.
	if honor == 0 and _G.UnitHonor then
		local ok, h = pcall(_G.UnitHonor, "player")
		h = ok and plain(h, "number")
		if h and h > 0 then honor = h end
	end
	local pvpRank = 0
	if _G.UnitHonorLevel then
		local ok, r = pcall(_G.UnitHonorLevel, "player")
		r = ok and plain(r, "number")
		if r and r > 0 then pvpRank = r end
	end
	if pvpRank == 0 and _G.GetPVPLifetimeStats then
		local ok, _, _, highest = pcall(_G.GetPVPLifetimeStats)
		highest = ok and plain(highest, "number")
		if highest and highest > 0 then pvpRank = highest end
	end

	-- Battleground reputations (C_Reputation with Classic GetFactionInfo fallback).
	local reps = {}
	local repApi = _G.C_Reputation
	if repApi and repApi.GetNumFactions and repApi.GetFactionDataByIndex then
		local okN, n = pcall(repApi.GetNumFactions)
		n = okN and plain(n, "number") or 0
		for i = 1, n do
			local okF, f = pcall(repApi.GetFactionDataByIndex, i)
			if okF and type(f) == "table" and not f.isHeader then
				local name = plain(f.name, "string")
				if name and isBGRep(name) then
					local reaction = plain(f.reaction, "number") or 4
					local low = plain(f.currentReactionThreshold, "number") or 0
					local high = plain(f.nextReactionThreshold, "number") or 0
					local curVal = plain(f.currentStanding, "number") or 0
					reps[#reps + 1] = {
						name = name, standing = STANDING_NAMES[reaction] or tostring(reaction),
						value = math.max(0, curVal - low), max = math.max(1, high - low),
						exalted = reaction >= 8,
					}
				end
			end
		end
	elseif _G.GetNumFactions and _G.GetFactionInfo then
		local okN, n = pcall(_G.GetNumFactions)
		n = okN and plain(n, "number") or 0
		for i = 1, n do
			local okF, name, _, reaction, low, high, curVal, _, _, isHeader = pcall(_G.GetFactionInfo, i)
			if okF and not isHeader then
				name = plain(name, "string")
				if name and isBGRep(name) then
					reaction = plain(reaction, "number") or 4
					low = plain(low, "number") or 0
					high = plain(high, "number") or 0
					curVal = plain(curVal, "number") or 0
					reps[#reps + 1] = {
						name = name, standing = STANDING_NAMES[reaction] or tostring(reaction),
						value = math.max(0, curVal - low), max = math.max(1, high - low),
						exalted = reaction >= 8,
					}
				end
			end
		end
	end

	local markList = {}
	for i = 1, #MARK_DEFS do markList[i] = marks[MARK_DEFS[i].key] end

	return {
		honor = honor, honorCap = honorCap,
		rank = pvpRank, rankPoints = rankPoints, rankCap = rankCap,
		legacyPoints = legacyPoints,
		marks = marks, markList = markList,
		reps = reps,
	}
end

--- Warn in chat when Honor or BG Marks approach their cap so nothing is wasted.
function Ledger:CheckCaps()
	if not ns.settings.capWarnings or not ns.settings.chat then return end
	local snap = self:Snapshot()
	if snap.honorCap > 0 then
		local ratio = snap.honor / snap.honorCap
		local level = ratio >= Ledger.WARN_CRITICAL and 2 or (ratio >= Ledger.WARN_HIGH and 1 or 0)
		if level > self.warnedHonor then
			self.warnedHonor = level
			ns:Print(ns.L.MSG_HONOR_CAP:format(snap.honor, snap.honorCap, floor(ratio * 100 + 0.5)))
		elseif level < self.warnedHonor then
			self.warnedHonor = level
		end
	end
	for i = 1, #snap.markList do
		local m = snap.markList[i]
		local near = m.cap > 0 and m.count >= m.cap - 2
		if near and not self.warnedMarks[m.key] then
			self.warnedMarks[m.key] = true
			ns:Print(ns.L.MSG_MARK_CAP:format(m.label, m.count, m.cap))
		elseif not near then
			self.warnedMarks[m.key] = nil
		end
	end
end

---------------------------------------------------------------------------
-- PvP Vendor Catalog & Character Wishlist
---------------------------------------------------------------------------

function Ledger:CatalogTable()
	if not ns.db then return {} end
	ns.db.vendorCatalog = type(ns.db.vendorCatalog) == "table" and ns.db.vendorCatalog or {}
	return ns.db.vendorCatalog
end

function Ledger:WishlistTable()
	local me = Names.Me()
	if not me or not ns.db then return {} end
	ns.db.wishlist = type(ns.db.wishlist) == "table" and ns.db.wishlist or {}
	local key = Names.Key(me)
	if type(ns.db.wishlist[key]) ~= "table" then ns.db.wishlist[key] = {} end
	return ns.db.wishlist[key]
end

local function readMerchantRow(i)
	local mf = _G.C_MerchantFrame
	if mf and mf.GetItemInfo then
		local ok, info = pcall(mf.GetItemInfo, i)
		if ok and type(info) == "table" then
			return plain(info.name, "string"), plain(info.texture, "string") or plain(info.texture, "number"),
				plain(info.price, "number")
		end
	end
	if _G.GetMerchantItemInfo then
		local ok, name, texture, price = pcall(_G.GetMerchantItemInfo, i)
		if ok then
			return plain(name, "string"), plain(texture, "string") or plain(texture, "number"),
				plain(price, "number")
		end
	end
	return nil
end

--- Scan the open merchant window and remember any items that cost Honor, Marks
--- or PvP Legacy Points.
function Ledger:ScanMerchant()
	local hasItemInfo = (_G.C_MerchantFrame and _G.C_MerchantFrame.GetItemInfo) or _G.GetMerchantItemInfo
	if not (_G.GetMerchantNumItems and hasItemInfo) then return 0 end
	local okN, n = pcall(_G.GetMerchantNumItems)
	n = okN and plain(n, "number") or 0
	if n <= 0 then return 0 end

	local catalog = self:CatalogTable()
	local added = 0
	for i = 1, n do
		local name, texture, price = readMerchantRow(i)
		local itemID = _G.GetMerchantItemID and select(2, pcall(_G.GetMerchantItemID, i))
		itemID = plain(itemID, "number")
		local link = _G.GetMerchantItemLink and select(2, pcall(_G.GetMerchantItemLink, i))
		link = plain(link, "string")
		if name and itemID then
			local honorCost, legacyCost = 0, 0
			local markCosts = {}
			local isPvP = false
			local costCount = _G.GetMerchantItemCostInfo and select(2, pcall(_G.GetMerchantItemCostInfo, i)) or 0
			costCount = plain(costCount, "number") or 0
			for j = 1, costCount do
				if _G.GetMerchantItemCostItem then
					local okC, _, val, costLink, costName = pcall(_G.GetMerchantItemCostItem, i, j)
					if okC then
						val = plain(val, "number") or 0
						local label = plain(costName, "string") or plain(costLink, "string") or ""
						local lo = Util.Fold(label)
						local mkey = matchMarkKey(label)
						if mkey and val > 0 then
							markCosts[mkey] = (markCosts[mkey] or 0) + val
							isPvP = true
						elseif lo:find("honor", 1, true) and val > 0 then
							honorCost = honorCost + val
							isPvP = true
						elseif lo:find("legacy", 1, true) and val > 0 then
							legacyCost = legacyCost + val
							isPvP = true
						end
					end
				end
			end
			if isPvP then
				catalog[itemID] = {
					id = itemID, key = "item:" .. tostring(itemID),
					name = name, link = link, icon = texture,
					gold = floor((price or 0) / 10000),
					honor = honorCost, legacy = legacyCost, marks = markCosts,
				}
				added = added + 1
			end
		end
	end
	if added > 0 then ns:Fire("LEDGER_CHANGED") end
	return added
end

function Ledger:IsWished(itemID)
	return self:WishlistTable()[itemID] and true or false
end

function Ledger:ToggleWish(itemID)
	local wl = self:WishlistTable()
	if wl[itemID] then wl[itemID] = nil else wl[itemID] = true end
	ns:Fire("LEDGER_CHANGED")
	return wl[itemID] and true or false
end

--- All cataloged PvP vendor items, wishlisted ones first.
function Ledger:CatalogList()
	local catalog = self:CatalogTable()
	local wl = self:WishlistTable()
	local list = {}
	for _, item in pairs(catalog) do
		if type(item) == "table" and item.id then
			list[#list + 1] = {
				key = item.key or ("item:" .. tostring(item.id)),
				id = item.id, name = item.name, link = item.link, icon = item.icon,
				gold = item.gold or 0, honor = item.honor or 0, legacy = item.legacy or 0, marks = item.marks or {},
				wished = wl[item.id] and true or false,
			}
		end
	end
	table.sort(list, function(a, b)
		if a.wished ~= b.wished then return a.wished end
		if a.honor ~= b.honor then return a.honor > b.honor end
		return (a.name or "") < (b.name or "")
	end)
	return list
end

local function myGold()
	if not _G.GetMoney then return 0 end
	local ok, copper = pcall(_G.GetMoney)
	copper = ok and plain(copper, "number") or 0
	return floor(math.max(0, copper) / 10000)
end

--- Compute missing resources for one catalog item against `snap` (optional).
function Ledger:ItemMissing(item, snap)
	snap = snap or self:Snapshot()
	local needHonor = math.max(0, (item.honor or 0) - (snap.honor or 0))
	local needLegacy = math.max(0, (item.legacy or 0) - (snap.legacyPoints or 0))
	local needGold = math.max(0, (item.gold or 0) - myGold())
	local needMarks = {}
	local anyMark = false
	for mkey, qty in pairs(item.marks or {}) do
		local have = snap.marks[mkey] and snap.marks[mkey].count or 0
		local miss = math.max(0, qty - have)
		needMarks[mkey] = miss
		if miss > 0 then anyMark = true end
	end
	local ready = needHonor == 0 and needLegacy == 0 and needGold == 0 and not anyMark
	return { ready = ready, needHonor = needHonor, needLegacy = needLegacy, needGold = needGold, needMarks = needMarks }
end

--- Compute total & missing Honor, BG Marks, Legacy Points, Gold and estimated BGs for the wishlist.
function Ledger:WishlistSummary()
	local snap = self:Snapshot()
	local catalog = self:CatalogTable()
	local wl = self:WishlistTable()
	local totalHonor, totalLegacy, totalGold, count = 0, 0, 0, 0
	local totalMarks = {}
	for itemID in pairs(wl) do
		local item = catalog[itemID]
		if item then
			count = count + 1
			totalHonor = totalHonor + (item.honor or 0)
			totalLegacy = totalLegacy + (item.legacy or 0)
			totalGold = totalGold + (item.gold or 0)
			for mkey, qty in pairs(item.marks or {}) do
				totalMarks[mkey] = (totalMarks[mkey] or 0) + qty
			end
		end
	end
	local needHonor = math.max(0, totalHonor - snap.honor)
	local needLegacy = math.max(0, totalLegacy - (snap.legacyPoints or 0))
	local haveGold = myGold()
	local needGold = math.max(0, totalGold - haveGold)
	local needMarks = {}
	for mkey, qty in pairs(totalMarks) do
		local have = snap.marks[mkey] and snap.marks[mkey].count or 0
		needMarks[mkey] = math.max(0, qty - have)
	end
	local avgHonor = ns.History and ns.History:Summary().avgHonor or 0
	local estBGs = (needHonor > 0 and avgHonor > 0) and math.ceil(needHonor / avgHonor) or nil
	return {
		count = count,
		totalHonor = totalHonor, needHonor = needHonor,
		totalLegacy = totalLegacy, needLegacy = needLegacy,
		totalMarks = totalMarks, needMarks = needMarks,
		totalGold = totalGold, haveGold = haveGold, needGold = needGold,
		estBGs = estBGs,
	}
end

function Ledger:Init()
	local events = self.events
	events.MERCHANT_SHOW = ns:On("MERCHANT_SHOW", function() Ledger:ScanMerchant() end)
	events.MERCHANT_UPDATE = ns:On("MERCHANT_UPDATE", function() Ledger:ScanMerchant() end)
	events.CURRENCY_DISPLAY_UPDATE = ns:On("CURRENCY_DISPLAY_UPDATE", function()
		Ledger:CheckCaps()
		ns:Fire("LEDGER_CHANGED")
	end)
	events.BAG_UPDATE_DELAYED = ns:On("BAG_UPDATE_DELAYED", function()
		Ledger:CheckCaps()
		ns:Fire("LEDGER_CHANGED")
	end)
	events.UPDATE_FACTION = ns:On("UPDATE_FACTION", function() ns:Fire("LEDGER_CHANGED") end)
	ns:Listen("BG_MATCH_SAVED", function() Ledger:CheckCaps() end)
end
