-- The addon's page in the game's Options > AddOns list.
local _, ns = ...

local L = ns.L

local Options = {}
ns.Options = Options

local CHECKS = {
	{ "banner", L.OPT_BANNER, L.OPT_BANNER_TIP },
	{ "sound", L.OPT_SOUND, L.OPT_SOUND_TIP },
	{ "chat", L.OPT_CHAT, L.OPT_CHAT_TIP },
	{ "nameplates", L.OPT_NAMEPLATES, L.OPT_NAMEPLATES_TIP },
	{ "guildAlerts", L.OPT_GUILD_ALERTS, L.OPT_GUILD_ALERTS_TIP },
	{ "sightSend", L.OPT_SIGHT_SEND, L.OPT_SIGHT_SEND_TIP },
	{ "sightShow", L.OPT_SIGHT_SHOW, L.OPT_SIGHT_SHOW_TIP },
	{ "revenge", L.OPT_REVENGE, L.OPT_REVENGE_TIP },
}

local SLIDERS = {
	{ "revengeCount", L.OPT_REVENGE_COUNT, L.OPT_REVENGE_COUNT_TIP, 2, 10, 1 },
	{ "revengeWindow", L.OPT_REVENGE_WINDOW, L.OPT_REVENGE_WINDOW_TIP, 5, 120, 5 },
}

function Options:Init()
	local settings = _G.Settings
	if not (settings and settings.RegisterVerticalLayoutCategory and settings.RegisterAddOnSetting
		and settings.CreateCheckbox and settings.RegisterAddOnCategory) then
		ns:Debug("Settings API not available; use /feud set <option> on|off")
		return
	end
	local boolean = settings.VarType and settings.VarType.Boolean or "boolean"
	local category = settings.RegisterVerticalLayoutCategory(ns.TITLE)
	for i = 1, #CHECKS do
		local key, label, tip = CHECKS[i][1], CHECKS[i][2], CHECKS[i][3]
		local setting = settings.RegisterAddOnSetting(category, "BloodFeud_" .. key, key, ns.settings, boolean, label,
			ns.DEFAULTS[key])
		settings.CreateCheckbox(category, setting, tip)
		if key == "nameplates" and setting and setting.SetValueChangedCallback then
			setting:SetValueChangedCallback(function()
				ns.Nameplates:Clear()
				ns.Detect.ScanNameplates()
			end)
		end
	end
	if settings.CreateSlider and settings.CreateSliderOptions then
		local number = settings.VarType and settings.VarType.Number or "number"
		for i = 1, #SLIDERS do
			local key, label, tip, lo, hi, step = unpack(SLIDERS[i])
			local ok, err = pcall(function()
				local setting = settings.RegisterAddOnSetting(category, "BloodFeud_" .. key, key, ns.settings, number,
					label, ns.DEFAULTS[key])
				local options = settings.CreateSliderOptions(lo, hi, step)
				if options.SetLabelFormatter and _G.MinimalSliderWithSteppersMixin then
					options:SetLabelFormatter(_G.MinimalSliderWithSteppersMixin.Label.Right)
				end
				settings.CreateSlider(category, setting, options, tip)
			end)
			if not ok then ns:Debug("slider %s: %s", key, tostring(err)) end
		end
	end
	if settings.RegisterProxySetting then
		local minimap = settings.RegisterProxySetting(category, "BloodFeud_minimap", boolean, L.OPT_MINIMAP, true,
			function() return not ns.db.minimap.hide end,
			function(value)
				ns.db.minimap.hide = not value
				ns.Minimap:Apply()
			end)
		settings.CreateCheckbox(category, minimap, L.OPT_MINIMAP_TIP)
	end
	settings.RegisterAddOnCategory(category)
	self.category = category
end

--- Open the options page (falls back to a hint when the API is missing).
function ns:OpenOptions()
	local settings, category = _G.Settings, Options.category
	if settings and settings.OpenToCategory and category and category.GetID then
		settings.OpenToCategory(category:GetID())
	else
		self:Print("/feud set <banner|sound|chat|nameplates|guildAlerts|sightSend|sightShow|revenge> on|off")
	end
end
