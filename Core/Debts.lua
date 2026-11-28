-- Gold on a bounty is a promise: an addon cannot move gold. This module holds
-- the poster to it. When a gold bounty is won, its poster owes the winner the
-- gold and has 48 hours to send it by mail or trade. Who has not paid by then
-- is Dishonored for the whole guild to see, until they pay.
--
-- Payment is noticed on both sides without anyone clicking anything:
--   the poster's client sees the gold leave (a mail sent, a trade completed)
--     and marks the debt "sent", which stops the clock;
--   the winner's client sees it arrive (a mail in the inbox, a trade) and
--     marks it "received", which closes the debt.
-- The winner can also mark it by hand, or say it never arrived, and an
-- officer can settle a debt whatever the two of them say.
local _, ns = ...

local Util, Names, Roster = ns.Util, ns.Names, ns.Roster
local L = ns.L
local floor = math.floor

local Debts = { known = {}, events = {},
	-- What the client actually let us see, for /bm probe.
	stats = { scans = 0, mails = 0, unreadable = 0, sends = 0, trades = 0 } }
ns.Debts = Debts

Debts.COPPER = 10000 -- copper in one gold
Debts.FRESH_SECONDS = 120 -- only speak about what just happened
Debts.CHECK_EVERY = 60

local function plain(value, kind)
	if value == nil or Util.IsSecret(value) then return nil end
	if kind and type(value) ~= kind then return nil end
	return value
end

local function subject(bounty)
	if bounty.scope == "g" then return "<" .. bounty.name .. ">" end
	return Names.Display(bounty.name)
end
Debts.Subject = subject

--- "36 h left", "25 min left" or "overdue".
function Debts.Left(debt, now)
	local left = debt.due - now
	if left <= 0 then return L.DEBT_OVERDUE end
	if left >= 3600 then return L.DEBT_HOURS_LEFT:format(floor(left / 3600)) end
	return L.DEBT_MINUTES_LEFT:format(math.max(1, floor(left / 60)))
end

--- Is the character behind `key` (a folded name as typed or shown, with or
--- without surname) the one called `name`?
local function same(key, name)
	local full = Names.Key(name)
	if key == full then return true end
	if key == Names.FirstKey(name) then return true end -- typed with the first name only
	return key:match("^([^%-]+)%-") == full -- stored without a surname
end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------

function Debts:All()
	local s = ns.session
	if not s then return {} end
	return s.store:Debts(GetServerTime())
end

--- Open debts where I am the poster (mine = "poster") or the winner.
function Debts:Mine(role)
	local s = ns.session
	local out = {}
	if not s then return out end
	local all = self:All()
	for i = 1, #all do
		local d = all[i]
		if d.open and ((role == "poster" and d.pkey == s.meKey) or (role == "winner" and d.wkey == s.meKey)) then
			out[#out + 1] = d
		end
	end
	return out
end

--- The overdue debt that makes this guildmate Dishonored, or nil.
function Debts:Dishonor(key)
	local s = ns.session
	if not s then return nil end
	return s.store:Dishonor(GetServerTime())[key]
end

---------------------------------------------------------------------------
-- Marks
---------------------------------------------------------------------------

local function debtOf(bid)
	local s = ns.session
	if not s then
		ns:Print(L.MSG_NO_GUILD)
		return nil
	end
	local bounty = s.store:Get(bid)
	local debt = bounty and s.store:Debt(bounty, GetServerTime())
	return debt, s
end

--- The poster: "I have sent the gold" (or, with false, "I have not").
function ns:MarkSent(bid, sent)
	local debt, s = debtOf(bid)
	if not debt or debt.pkey ~= s.meKey then return nil end
	return s.store:SetMark(bid, "s", sent == false and "n" or "s", s.me, GetServerTime())
end

--- The winner: "r" the gold arrived, "x" it has not, "n" neither.
function ns:MarkReceived(bid, state)
	local debt, s = debtOf(bid)
	if not debt or debt.wkey ~= s.meKey then return nil end
	return s.store:SetMark(bid, "w", state or "r", s.me, GetServerTime())
end

--- An officer closes a debt, whatever the two parties say.
function ns:SettleDebt(bid, settled)
	local debt, s = debtOf(bid)
	if not debt then return nil end
	if not Roster.AmOfficer() then
		self:Print(L.MSG_NOT_OFFICER)
		return nil
	end
	return s.store:SetMark(bid, "o", settled == false and "n" or "o", s.me, GetServerTime())
end

---------------------------------------------------------------------------
-- Gold seen leaving or arriving
---------------------------------------------------------------------------

--- I sent `copper` to the character behind `toKey`: mark what I owe them as
--- sent, oldest debt first, for as far as the amount goes. Returns how many.
function Debts:GoldSent(toKey, copper)
	local s = ns.session
	if not s or not toKey or not copper then return 0 end
	local now = GetServerTime()
	local n = 0
	for _, d in ipairs(s.store:Debts(now)) do
		local price = d.gold * Debts.COPPER
		if d.pkey == s.meKey and (d.state == "owed" or d.state == "disputed") and same(toKey, d.winner)
			and copper >= price then
			if s.store:SetMark(d.bounty.id, "s", "s", s.me, now) then
				copper = copper - price
				n = n + 1
				ns:Print(L.MSG_DEBT_SENT_YOU:format(d.gold, Names.Display(d.winner), subject(d.bounty)))
			end
		end
	end
	return n
end

--- `copper` arrived from the character behind `fromKey`: mark what they owe
--- me as received, oldest debt first. Returns how many.
function Debts:GoldReceived(fromKey, copper)
	local s = ns.session
	if not s or not fromKey or not copper then return 0 end
	local now = GetServerTime()
	local n = 0
	for _, d in ipairs(s.store:Debts(now)) do
		local price = d.gold * Debts.COPPER
		if d.wkey == s.meKey and d.open and same(fromKey, d.poster) and copper >= price then
			if s.store:SetMark(d.bounty.id, "w", "r", s.me, now) then
				copper = copper - price
				n = n + 1
				ns:Print(L.MSG_DEBT_RECEIVED_YOU:format(d.gold, Names.Display(d.poster), subject(d.bounty)))
			end
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Mail
---------------------------------------------------------------------------

--- Which inbox mails have already been counted toward a debt, per character:
--- { [fingerprint] = how many such mails }.
function Debts:MailBook()
	local me = Names.Me()
	if not me or not ns.db then return {} end
	ns.db.mail = type(ns.db.mail) == "table" and ns.db.mail or {}
	local key = Names.Key(me)
	if type(ns.db.mail[key]) ~= "table" then ns.db.mail[key] = {} end
	return ns.db.mail[key]
end

--- Look through the inbox (only possible at a mailbox) for gold from someone
--- who owes me. A mail counts once, however long it stays in the inbox.
function Debts:ScanInbox()
	local getCount, getHeader = _G.GetInboxNumItems, _G.GetInboxHeaderInfo
	if not (getCount and getHeader) then return end
	self.stats.scans = self.stats.scans + 1
	if #self:Mine("winner") == 0 then return end
	local ok, count = pcall(getCount)
	count = ok and plain(count, "number") or 0
	local mails, present = {}, {}
	for i = 1, count do
		local okHeader, _, _, sender, mailSubject, money = pcall(getHeader, i)
		if okHeader then
			sender, money = plain(sender, "string"), plain(money, "number")
			if not sender then
				self.stats.unreadable = self.stats.unreadable + 1
			elseif money and money > 0 then
				local canon = Names.Canon(sender)
				if canon then
					local key = Names.Key(canon)
					local mark = key .. "\1" .. money .. "\1" .. (plain(mailSubject, "string") or "")
					present[mark] = (present[mark] or 0) + 1
					mails[#mails + 1] = { key = key, copper = money, mark = mark }
				end
			end
		end
	end
	self.stats.mails = self.stats.mails + #mails
	-- Mails that have left the inbox (gold taken, deleted) free their slot.
	local book = self:MailBook()
	for mark, used in pairs(book) do
		local have = present[mark] or 0
		if used > have then book[mark] = have > 0 and have or nil end
	end
	local met = {}
	for i = 1, #mails do
		local mail = mails[i]
		met[mail.mark] = (met[mail.mark] or 0) + 1
		if met[mail.mark] > (book[mail.mark] or 0) and self:GoldReceived(mail.key, mail.copper) > 0 then
			book[mail.mark] = (book[mail.mark] or 0) + 1
		end
	end
end

function Debts:HookMail()
	local hook = _G.hooksecurefunc
	if not hook then return end
	-- The mail window sets the amount, then sends: remember both.
	if _G.SetSendMailMoney then
		pcall(hook, "SetSendMailMoney", function(copper) Debts.sendMoney = plain(copper, "number") end)
	end
	if _G.SendMail then
		pcall(hook, "SendMail", function(recipient)
			recipient = plain(recipient, "string")
			local canon = recipient and Names.Canon(recipient, true)
			local copper = Debts.sendMoney
			if not copper and _G.GetSendMailMoney then
				local ok, value = pcall(_G.GetSendMailMoney)
				copper = ok and plain(value, "number") or nil
			end
			Debts.pendingMail = canon and copper and copper > 0 and { key = Names.Key(canon), copper = copper } or nil
		end)
	end
end

---------------------------------------------------------------------------
-- Trade
---------------------------------------------------------------------------

local function tradeMoney(fn)
	if not fn then return nil end
	local ok, value = pcall(fn)
	return ok and plain(value, "number") or nil
end

function Debts:OnTradeShow()
	self.trade = { partner = Names.OfUnit("NPC") }
end

--- Both sides pressing Trade is the last moment the amounts can be read.
function Debts:OnTradeAccept(mine, theirs)
	local t = self.trade
	if not t then return end
	if mine == 1 and theirs == 1 then
		t.gave = tradeMoney(_G.GetPlayerTradeMoney) or 0
		t.got = tradeMoney(_G.GetTargetTradeMoney) or 0
		t.purse = tradeMoney(_G.GetMoney)
		t.accepted = true
	else
		t.accepted = false
	end
end

--- The trade went through: credit what changed hands.
function Debts:TradeDone()
	local t = self.trade
	self.trade = nil
	if not t or not t.accepted or not t.partner then return end
	self.stats.trades = self.stats.trades + 1
	local key = Names.Key(t.partner)
	if t.gave > 0 then self:GoldSent(key, t.gave) end
	if t.got > 0 then self:GoldReceived(key, t.got) end
end

--- The window closed. The client says "Trade complete" when it went through;
--- where that message cannot be had, the purse tells: it changed by exactly
--- what the two sides offered.
function Debts:OnTradeClosed()
	local t = self.trade
	if not t or not t.accepted then
		self.trade = nil
		return
	end
	C_Timer.After(1.5, function()
		if Debts.trade ~= t then return end -- already handled, or a new trade began
		local purse = tradeMoney(_G.GetMoney)
		if purse and t.purse and t.got ~= t.gave and purse - t.purse == t.got - t.gave then
			ns.Safe(Debts.TradeDone, Debts)
		else
			Debts.trade = nil
		end
	end)
end

---------------------------------------------------------------------------
-- Telling the people involved
---------------------------------------------------------------------------

--- Chat lines about what I owe and am owed. Returns how many were printed.
function Debts:Remind()
	local now = GetServerTime()
	local n = 0
	for _, d in ipairs(self:Mine("poster")) do
		if d.late then
			ns:Print(L.DEBT_YOU_OWE_LATE:format(d.gold, Names.Display(d.winner), subject(d.bounty)))
			n = n + 1
		elseif d.state ~= "sent" then
			ns:Print(L.DEBT_YOU_OWE:format(Names.Display(d.winner), d.gold, subject(d.bounty), Debts.Left(d, now)))
			n = n + 1
		end
	end
	for _, d in ipairs(self:Mine("winner")) do
		if d.state == "sent" then
			ns:Print(L.DEBT_SENT_TO_YOU:format(Names.Display(d.poster), d.gold, subject(d.bounty)))
		else
			ns:Print(L.DEBT_OWES_YOU:format(Names.Display(d.poster), d.gold, subject(d.bounty), Debts.Left(d, now)))
		end
		n = n + 1
	end
	return n
end

--- A gold bounty was just won (the claim record arrived or was written).
local function onClaim(rec, old)
	local s = ns.session
	if not s or old or not ns.settings.chat then return end
	if GetServerTime() - rec.ts > Debts.FRESH_SECONDS then return end
	local bounty = s.store:Get(rec.bid)
	if not bounty or s.store:Winner(bounty) ~= rec then return end
	if bounty.akey == s.meKey then
		ns:Print(L.MSG_DEBT_NEW_YOU:format(Names.Display(rec.author), subject(bounty), bounty.gold))
	elseif rec.akey == s.meKey then
		ns:Print(L.MSG_DEBT_NEW_WINNER:format(subject(bounty), Names.Display(bounty.author), bounty.gold))
	end
end

--- A guildmate's fresh mark on a debt, sent by themselves.
function Debts.Announce(rec, sender)
	local s = ns.session
	if not s or not ns.settings.chat then return end
	if GetServerTime() - rec.ts > Debts.FRESH_SECONDS or Names.Key(sender) == s.meKey then return end
	local bounty = s.store:Get(rec.bid)
	local debt = bounty and s.store:Debt(bounty, GetServerTime())
	if not debt then return end
	local poster, winner = debt.pkey == s.meKey, debt.wkey == s.meKey
	local who = Names.Display(rec.author)
	if rec.role == "s" and rec.state == "s" and winner then
		ns:Print(L.DEBT_SENT_TO_YOU:format(who, debt.gold, subject(bounty)))
	elseif rec.role == "w" and rec.akey == debt.wkey and poster then
		if rec.state == "r" then
			ns:Print(L.MSG_DEBT_CONFIRMED:format(who, debt.gold, subject(bounty)))
		elseif rec.state == "x" then
			ns:Print(L.MSG_DEBT_DISPUTED:format(who, debt.gold, subject(bounty)))
		end
	elseif rec.role == "o" and rec.state == "o" and (poster or winner) then
		ns:Print(L.MSG_DEBT_SETTLED:format(who, subject(bounty)))
	end
end

--- Notice debts running out while we are online.
function Debts:Check()
	local s = ns.session
	if not s then return end
	local seen = {}
	for _, d in ipairs(self:All()) do
		local id = d.bounty.id
		seen[id] = true
		local was = self.known[id]
		self.known[id] = d.late
		if d.late and was == false and ns.settings.chat then
			if d.pkey == s.meKey then
				ns:Print(L.DEBT_YOU_OWE_LATE:format(d.gold, Names.Display(d.winner), subject(d.bounty)))
			else
				ns:Print(L.MSG_DISHONORED:format(Names.Display(d.poster), d.gold, Names.Display(d.winner), subject(d.bounty)))
			end
			ns:Fire("PROGRESS_CHANGED")
		end
	end
	for id in pairs(self.known) do
		if not seen[id] then self.known[id] = nil end
	end
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

function Debts:Init()
	local events = self.events
	self:HookMail()
	events.MAIL_SEND_SUCCESS = ns:On("MAIL_SEND_SUCCESS", function()
		local mail = Debts.pendingMail
		Debts.pendingMail, Debts.sendMoney = nil, nil
		if mail then
			Debts.stats.sends = Debts.stats.sends + 1
			Debts:GoldSent(mail.key, mail.copper)
		end
	end)
	events.MAIL_FAILED = ns:On("MAIL_FAILED", function() Debts.pendingMail = nil end)
	local scanning = false
	events.MAIL_INBOX_UPDATE = ns:On("MAIL_INBOX_UPDATE", function()
		if scanning then return end
		scanning = true
		C_Timer.After(0.5, function()
			scanning = false
			ns.Safe(Debts.ScanInbox, Debts)
		end)
	end)
	events.MAIL_SHOW = ns:On("MAIL_SHOW", function()
		if ns.settings.chat and #Debts:Mine("poster") > 0 then Debts:Remind() end
	end)

	events.TRADE_SHOW = ns:On("TRADE_SHOW", function() Debts:OnTradeShow() end)
	events.TRADE_ACCEPT_UPDATE = ns:On("TRADE_ACCEPT_UPDATE", function(mine, theirs) Debts:OnTradeAccept(mine, theirs) end)
	events.TRADE_CLOSED = ns:On("TRADE_CLOSED", function() Debts:OnTradeClosed() end)
	events.UI_INFO_MESSAGE = ns:On("UI_INFO_MESSAGE", function(a, b)
		if not Debts.trade then return end
		local done = _G.ERR_TRADE_COMPLETE
		local sa, sb = plain(a, "string"), plain(b, "string")
		if done and (sa == done or sb == done) then Debts:TradeDone() end
	end)

	ns:Listen("LIST_CHANGED", function(_, rec, old)
		if rec and rec.k == "k" then onClaim(rec, old) end
	end)
	C_Timer.After(20, function()
		if ns.settings.chat then ns.Safe(Debts.Remind, Debts) end
		ns.Safe(Debts.Check, Debts)
	end)
	C_Timer.NewTicker(Debts.CHECK_EVERY, function() ns.Safe(Debts.Check, Debts) end)
end
