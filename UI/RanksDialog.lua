-- Officers: rename the ranks and move their thresholds. Each row is one tier;
-- clearing a title switches that tier off for the whole guild.
local _, ns = ...

local W, Codec = ns.W, ns.Codec
local L = ns.L

local Dialog = {}
ns.RanksDialog = Dialog

local ROW_H = 28

function Dialog:Build()
	local f = W.Panel(UIParent, "BusinessMeetingRanksDialog")
	self.frame = f
	f:SetSize(380, 110 + Codec.MAX_TIERS * ROW_H)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	W.Movable(f)
	f:Hide()
	tinsert(UISpecialFrames, "BusinessMeetingRanksDialog")

	local title = W.Heading(f, L.DIALOG_RANKS)
	title:SetPoint("TOPLEFT", 16, -14)
	local killsHead = W.Caption(f, L.COL_KILLS)
	killsHead:SetPoint("TOPLEFT", 44, -44)
	local titleHead = W.Caption(f, L.COL_TITLE)
	titleHead:SetPoint("TOPLEFT", 130, -44)

	f.rows = {}
	for n = 1, Codec.MAX_TIERS do
		local y = -60 - (n - 1) * ROW_H
		local num = W.Label(f, "GameFontDisableSmall", tostring(n))
		num:SetPoint("TOPLEFT", 18, y - 6)
		local kills = W.EditBox(f, 76, 24, 6)
		kills:SetPoint("TOPLEFT", 44, y)
		kills:SetNumeric(true)
		local name = W.EditBox(f, 230, 24, Codec.MAX_TITLE)
		name:SetPoint("TOPLEFT", 130, y)
		f.rows[n] = { kills = kills, title = name }
	end

	local hint = W.Label(f, "GameFontDisableSmall", L.RANKS_HINT)
	hint:SetPoint("BOTTOMLEFT", 16, 50)
	hint:SetPoint("RIGHT", f, "RIGHT", -16, 0)

	local save = W.Button(f, L.SAVE, 110, 28, "danger")
	save:SetPoint("BOTTOMLEFT", 16, 14)
	save:SetScript("OnClick", function() Dialog:Submit() end)
	local reset = W.Button(f, L.RESET_DEFAULTS, 130, 28)
	reset:SetPoint("LEFT", save, "RIGHT", 6, 0)
	reset:SetScript("OnClick", function() Dialog:Fill(true) end)
	local cancel = W.Button(f, L.CANCEL, 100, 28)
	cancel:SetPoint("BOTTOMRIGHT", -16, 14)
	cancel:SetScript("OnClick", function() f:Hide() end)
end

--- Put the current ladder (or the built-in one) into the fields.
function Dialog:Fill(defaults)
	local s = ns.session
	local written = (not defaults and s) and s.store:Tiers() or {}
	for n = 1, Codec.MAX_TIERS do
		local row, rec, default = self.frame.rows[n], written[n], ns.Progress.DEFAULT_TIERS[n]
		local kills = rec and rec.kills or (default and default[1]) or nil
		local title = rec and rec.title or (default and default[2]) or ""
		row.kills:SetText(kills and tostring(kills) or "")
		row.title:SetText(title)
	end
end

function Dialog:Open()
	if not ns.session then
		ns:Print(L.MSG_NO_GUILD)
		return
	end
	if not ns.Roster.AmOfficer() then
		ns:Print(L.MSG_NOT_OFFICER)
		return
	end
	if not self.frame then self:Build() end
	self:Fill(false)
	self.frame:Show()
end

--- Write the tiers that differ from what the guild has now.
function Dialog:Submit()
	local s = ns.session
	if not s then return end
	local written = s.store:Tiers()
	-- A rank with a title needs a kill count: say so instead of dropping it.
	for n = 1, Codec.MAX_TIERS do
		local row = self.frame.rows[n]
		local title = ns.Util.Clean(row.title:GetText() or "", Codec.MAX_TITLE)
		if title ~= "" and not tonumber(row.kills:GetText() or "") then
			ns:Print(L.MSG_RANK_NEEDS_KILLS:format(n, title))
			row.kills:SetFocus()
			return
		end
	end
	local changed = 0
	for n = 1, Codec.MAX_TIERS do
		local row = self.frame.rows[n]
		local kills = tonumber(row.kills:GetText() or "")
		local title = ns.Util.Clean(row.title:GetText() or "", Codec.MAX_TITLE)
		if title == "" then kills = kills or 0 end
		local rec, default = written[n], ns.Progress.DEFAULT_TIERS[n]
		local curKills = rec and rec.kills or (default and default[1]) or 0
		local curTitle = rec and rec.title or (default and default[2]) or ""
		if kills then
			if curKills ~= kills or curTitle ~= title then
				if ns:SetTier(n, kills, title) then changed = changed + 1 end
			end
		end
	end
	ns:Print(L.MSG_RANKS_SAVED:format(changed))
	self.frame:Hide()
end
