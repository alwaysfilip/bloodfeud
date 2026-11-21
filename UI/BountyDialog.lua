-- The dialog for posting a bounty on an enemy player or guild.
local _, ns = ...

local W, Names, Codec = ns.W, ns.Names, ns.Codec
local L = ns.L

local Dialog = { scope = "p" }
ns.BountyDialog = Dialog

function Dialog:Build()
	local f = W.Panel(UIParent, "BloodFeudBountyDialog")
	self.frame = f
	f:SetSize(380, 270)
	f:SetPoint("CENTER", 0, 90)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	W.Movable(f)
	f:Hide()
	tinsert(UISpecialFrames, "BloodFeudBountyDialog")

	f.title = W.Label(f, "GameFontNormalLarge", L.DIALOG_BOUNTY)
	f.title:SetPoint("TOPLEFT", 16, -14)
	f.title:SetTextColor(0.94, 0.78, 0.37)

	f.player = W.Button(f, L.FIELD_PLAYER, 110, 24)
	f.player:SetPoint("TOPLEFT", 16, -44)
	f.player:SetScript("OnClick", function() Dialog:SetScope("p") end)
	f.guild = W.Button(f, L.FIELD_GUILD, 110, 24)
	f.guild:SetPoint("LEFT", f.player, "RIGHT", 4, 0)
	f.guild:SetScript("OnClick", function() Dialog:SetScope("g") end)

	f.name = W.EditBox(f, 348, 26, 72)
	f.name:SetPoint("TOPLEFT", 16, -76)

	local pointsLabel = W.Label(f, "GameFontDisableSmall", L.FIELD_POINTS)
	pointsLabel:SetPoint("TOPLEFT", 16, -112)
	f.points = W.EditBox(f, 80, 26, 3)
	f.points:SetPoint("TOPLEFT", 16, -128)
	f.points:SetNumeric(true)
	local pointsHint = W.Label(f, "GameFontDisableSmall", L.POINTS_HINT:format(Codec.MAX_POINTS))
	pointsHint:SetPoint("LEFT", f.points, "RIGHT", 10, 0)

	local rewardLabel = W.Label(f, "GameFontDisableSmall", L.FIELD_REWARD)
	rewardLabel:SetPoint("TOPLEFT", 16, -162)
	f.reward = W.EditBox(f, 348, 26)
	f.reward:SetPoint("TOPLEFT", 16, -178)
	f.reward:SetMaxBytes(Codec.MAX_REWARD + 1)

	f.hint = W.Label(f, "GameFontHighlightSmall", L.BOUNTY_HINT)
	f.hint:SetPoint("TOPLEFT", 16, -208)
	f.hint:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	f.hint:SetTextColor(0.79, 0.78, 0.74)

	f.ok = W.Button(f, L.POST_BOUNTY, 170, 28, "danger")
	f.ok:SetPoint("BOTTOMLEFT", 16, 14)
	f.ok:SetScript("OnClick", function() Dialog:Submit() end)
	local cancel = W.Button(f, L.CANCEL, 170, 28)
	cancel:SetPoint("BOTTOMRIGHT", -16, 14)
	cancel:SetScript("OnClick", function() f:Hide() end)

	for _, box in ipairs({ f.name, f.points, f.reward }) do
		box:SetScript("OnEnterPressed", function() Dialog:Submit() end)
		box:SetScript("OnEscapePressed", function() f:Hide() end)
	end
	f.name:SetScript("OnTabPressed", function() f.points:SetFocus() end)
	f.points:SetScript("OnTabPressed", function() f.reward:SetFocus() end)
	f.reward:SetScript("OnTabPressed", function() f.name:SetFocus() end)
end

function Dialog:SetScope(scope)
	self.scope = scope
	self.frame.player:SetSelected(scope == "p")
	self.frame.guild:SetSelected(scope == "g")
end

--- opts: scope ("p" or "g"), name, points, reward.
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
	f.name:SetText(name)
	f.points:SetText(tostring(opts.points or (existing and existing.points) or 10))
	f.reward:SetText(opts.reward or (existing and existing.reward) or "")
	f:Show()
	if name == "" then f.name:SetFocus() else f.reward:SetFocus() end
end

function Dialog:Submit()
	local f = self.frame
	local name = f.name:GetText() or "" -- "First Surname" and stray spaces are sorted out by Names.Canon
	if ns:PostBounty(self.scope, name, tonumber(f.points:GetText()) or 10, f.reward:GetText() or "") then
		f:Hide()
	end
end
