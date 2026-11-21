-- Minimap button (LibDBIcon) and the addon compartment entry.
local _, ns = ...

local W = ns.W
local L = ns.L

local Minimap = {}
ns.Minimap = Minimap

local function onClick(button)
	if button == "RightButton" then
		ns:OpenOptions()
	elseif IsShiftKeyDown() then
		local ok, info = pcall(ns.Detect.Inspect, "target")
		if ok and info then
			ns.AddDialog:Open("player", { info = info })
		else
			ns:Print(L.MSG_NO_TARGET)
		end
	else
		ns.MainFrame:Toggle()
	end
end

local function fillTooltip(tooltip)
	tooltip:AddLine(ns.TITLE, 0.94, 0.78, 0.37)
	local session = ns.session
	if session then
		local players, guilds = session.store:Counts()
		tooltip:AddLine(L.STATUS_COUNTS:format(players, guilds), 1, 1, 1)
	else
		tooltip:AddLine(L.STATUS_NO_GUILD, 0.66, 0.65, 0.61)
	end
	tooltip:AddLine(" ")
	tooltip:AddLine(L.MINIMAP_LEFT, 0.79, 0.78, 0.74)
	tooltip:AddLine(L.MINIMAP_SHIFT, 0.79, 0.78, 0.74)
	tooltip:AddLine(L.MINIMAP_RIGHT, 0.79, 0.78, 0.74)
end

--- Show or hide the minimap button according to the saved setting.
function Minimap:Apply()
	local icon = self.icon
	if not icon then return end
	if ns.db.minimap.hide then
		icon:Hide("BloodFeud")
	else
		icon:Show("BloodFeud")
	end
end

function Minimap:Init()
	local libStub = _G.LibStub
	if not libStub then return end
	local broker = libStub:GetLibrary("LibDataBroker-1.1", true)
	if not broker then return end
	local object = broker:NewDataObject("BloodFeud", {
		type = "launcher",
		text = ns.TITLE,
		icon = W.SKULL,
		OnClick = function(_, button) onClick(button) end,
		OnTooltipShow = fillTooltip,
	})
	local icon = libStub:GetLibrary("LibDBIcon-1.0", true)
	if icon and object then
		icon:Register("BloodFeud", object, ns.db.minimap)
		self.icon = icon
	end
end

-- Entry in the minimap's addon compartment (declared in the .toc).
function BloodFeud_OnAddonCompartmentClick(_, button)
	onClick(button)
end

function BloodFeud_OnAddonCompartmentEnter(_, menuButton)
	GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
	fillTooltip(GameTooltip)
	GameTooltip:Show()
end

function BloodFeud_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
