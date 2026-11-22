-- The dialog for posting a bounty on an enemy player or guild: points for
-- every kill, and optionally gold for the first one.
local _, ns = ...

local W, Names, Codec = ns.W, ns.Names, ns.Codec
local L = ns.L

local Dialog = { scope = "p" }
ns.BountyDialog = Dialog

function Dialog:Build()
	local f = W.Panel(UIParent, "BusinessMeetingBountyDialog")
	self.frame = f
	f:SetSize(380, 330)
	f:SetPoint("CENTER", 0, 90)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	W.Movable(f)
	f:Hide()
	tinsert(UISpecialFrames, "BusinessMeetingBountyDialog")

	f.title = W.Heading(f, L.DIALOG_BOUNTY)
	f.title:SetPoint("TOPLEFT", 16, -14)

	f.player = W.Button(f, L.FIELD_PLAYER, 110, 24)
	f.player:SetPoint("TOPLEFT", 16, -44)
	f.player:SetScript("OnClick", function() Dialog:SetScope("p") end)
	f.guild = W.Button(f, L.FIELD_GUILD, 110, 24)
	f.guild:SetPoint("LEFT", f.player, "RIGHT", 4, 0)
	f.guild:SetScript("OnClick", function() Dialog:SetScope("g") end)

	f.name = W.EditBox(f, 348, 26, 72)
	f.name:SetPoint("TOPLEFT", 16, -76)

	local pointsLabel = W.Caption(f, L.FIELD_POINTS)
	pointsLabel:SetPoint("TOPLEFT", 16, -112)
	f.points = W.EditBox(f, 70, 26, 3)
	f.points:SetPoint("TOPLEFT", 16, -128)
	f.points:SetNumeric(true)
	local pointsHint = W.Label(f, "GameFontDisableSmall", L.POINTS_HINT:format(Codec.MAX_POINTS))
	pointsHint:SetPoint("LEFT", f.points, "RIGHT", 8, 0)

	local goldLabel = W.Caption(f, L.FIELD_GOLD)
	goldLabel:SetPoint("TOPLEFT", 196, -112)
	f.gold = W.EditBox(f, 90, 26, 6)
	f.gold:SetPoint("TOPLEFT", 196, -128)
	f.gold:SetNumeric(true)
	local goldHint = W.Label(f, "GameFontDisableSmall", L.GOLD_HINT)
	goldHint:SetPoint("LEFT", f.gold, "RIGHT", 8, 0)

	local rewardLabel = W.Caption(f, L.FIELD_REWARD)
	rewardLabel:SetPoint("TOPLEFT", 16, -162)
	f.reward = W.EditBox(f, 348, 26)
	f.reward:SetPoint("TOPLEFT", 16, -178)
	f.reward:SetMaxBytes(Codec.MAX_REWARD + 1)

	f.hint = W.Label(f, "GameFontHighlightSmall", L.BOUNTY_HINT)
	f.hint:SetPoint("TOPLEFT", 16, -212)
	f.hint:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	f.hint:SetWordWrap(true)
	f.hint:SetTextColor(0.79, 0.78, 0.74)

	f.ok = W.Button(f, L.POST_BOUNTY, 170, 28, "danger")
	f.ok:SetPoint("BOTTOMLEFT", 16, 14)
	f.ok:SetScript("OnClick", function() Dialog:Submit() end)
	local cancel = W.Button(f, L.CANCEL, 170, 28)
	cancel:SetPoint("BOTTOMRIGHT", -16, 14)
	cancel:SetScript("OnClick", function() f:Hide() end)

	local order = { f.name, f.points, f.gold, f.reward }
	for i, box in ipairs(order) do
		box:SetScript("OnEnterPressed", function() Dialog:Submit() end)
		box:SetScript("OnEscapePressed", function() f:Hide() end)
		box:SetScript("OnTabPressed", function() order[i % #order + 1]:SetFocus() end)
	end
end

function Dialog:SetScope(scope)
	self.scope = scope
	self.frame.player:SetSelected(scope == "p")
	self.frame.guild:SetSelected(scope == "g")
end

--- opts: scope ("p" or "g"), name, points, gold, reward.
function Dialog:Open(opts)
	if not ns.session then
		ns:Print(L.MSG_NO_GUILD)
		return
	end
	if not self.frame then self:Build() end
	opts = opts or {}
	local f = self.frame
	self:SetScope(opts.scope or "p")
	local name = opts.name or ""
	-- Changing a bounty I already have up starts from what it says now.
	local existing = ns.Bounties:Mine(self.scope, name)
	if self.scope == "p" and name ~= "" then name = Names.Display(name) end
	local gold = opts.gold or (existing and existing.gold) or 0
	f.name:SetText(name)
	f.points:SetText(tostring(opts.points or (existing and existing.points) or 10))
	f.gold:SetText(gold > 0 and tostring(gold) or "")
	f.reward:SetText(opts.reward or (existing and existing.reward) or "")
	f:Show()
	if name == "" then f.name:SetFocus() else f.gold:SetFocus() end
end

function Dialog:Submit()
	local f = self.frame
	local name = f.name:GetText() or "" -- "First Surname" and stray spaces are sorted out by Names.Canon
	if ns:PostBounty(self.scope, name, tonumber(f.points:GetText()) or 10, f.reward:GetText() or "",
		tonumber(f.gold:GetText()) or 0) then
		f:Hide()
	end
end
