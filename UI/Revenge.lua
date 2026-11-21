-- The revenge prompt: shown after the same enemy player has killed you
-- several times within a short while, outside instances and battlegrounds.
-- It never takes keyboard focus, so it does not get in the way of releasing
-- or typing in chat.
local _, ns = ...

local W, Fmt, Names = ns.W, ns.Fmt, ns.Names
local L = ns.L

local Revenge = {}
ns.Revenge = Revenge

local SOUND = 8960 -- SOUNDKIT.READY_CHECK

function Revenge:Build()
	local f = W.Panel(UIParent, "BloodFeudRevengeFrame")
	self.frame = f
	f:SetSize(400, 214)
	f:SetPoint("TOP", UIParent, "TOP", 0, -250)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	W.Movable(f)
	f:Hide()
	tinsert(UISpecialFrames, "BloodFeudRevengeFrame")

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(30, 30)
	f.icon:SetPoint("TOPLEFT", 16, -14)
	f.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")

	f.title = W.Label(f, "GameFontNormalLarge", L.REVENGE_TITLE)
	f.title:SetPoint("LEFT", f.icon, "RIGHT", 10, 0)
	f.title:SetTextColor(1, 0.42, 0.36)

	f.text = W.Label(f, "GameFontHighlight")
	f.text:SetPoint("TOPLEFT", 16, -54)
	f.text:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	f.text:SetJustifyH("LEFT")
	f.text:SetWordWrap(true)

	f.detail = W.Label(f, "GameFontDisableSmall")
	f.detail:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -6)
	f.detail:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	f.detail:SetJustifyH("LEFT")
	f.detail:SetWordWrap(true)

	local reasonLabel = W.Label(f, "GameFontDisableSmall", L.FIELD_REASON)
	reasonLabel:SetPoint("BOTTOMLEFT", 16, 82)
	f.reason = W.EditBox(f, 368, 26)
	f.reason:SetPoint("BOTTOMLEFT", 16, 52)
	f.reason:SetMaxBytes(ns.Codec.MAX_REASON + 1)
	f.reason:SetScript("OnEnterPressed", function() Revenge:Accept() end)

	f.ok = W.Button(f, L.REVENGE_ADD, 180, 28, "danger")
	f.ok:SetPoint("BOTTOMLEFT", 16, 14)
	f.ok:SetScript("OnClick", function() Revenge:Accept() end)
	local no = W.Button(f, L.REVENGE_NO, 180, 28)
	no:SetPoint("BOTTOMRIGHT", -16, 14)
	no:SetScript("OnClick", function() f:Hide() end)
end

--- key: list key the fight is filed under; info: the killer as Detect saw
--- them; deaths: how many times within the window.
function Revenge:Show(key, info, deaths)
	if not ns.session then return end
	if not self.frame then self:Build() end
	local f = self.frame
	self.key, self.info = key, info

	local display = Names.Display(info.name)
	local hex = Fmt.ClassHex(info.class)
	local name = hex and Fmt.Color(hex, display) or display
	local minutes = ns.settings.revengeWindow or 30
	f.text:SetText(L.REVENGE_TEXT:format(name, deaths, minutes))

	local parts = {}
	local what = Fmt.Describe(info)
	if what ~= "" then parts[#parts + 1] = what end
	if info.guild then parts[#parts + 1] = "<" .. info.guild .. ">" end
	local subject = ns.session.store:Player(key)
	if subject then
		parts[#parts + 1] = L.REVENGE_LISTED:format(#subject.reports)
	end
	f.detail:SetText(table.concat(parts, " · "))

	f.reason:SetText(L.REVENGE_REASON:format(deaths, minutes))
	f:Show()
	if ns.settings.sound and _G.PlaySound then pcall(_G.PlaySound, SOUND, "Master") end
end

function Revenge:Accept()
	local f, info = self.frame, self.info
	if not info then return end
	local done = ns:AddPlayer(info.name, f.reason:GetText() or "", info)
	if done then
		f.reason:ClearFocus()
		f:Hide()
		if ns.Progress then ns.Progress:Bump("revengeAdds") end
	end
end
