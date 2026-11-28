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
	{ "dealBanner", L.OPT_DEAL_BANNER, L.OPT_DEAL_BANNER_TIP },
	{ "bountyAlerts", L.OPT_BOUNTY_ALERTS, L.OPT_BOUNTY_ALERTS_TIP },
	{ "targetAlerts", L.OPT_TARGET_ALERTS, L.OPT_TARGET_ALERTS_TIP },
	{ "targetSound", L.OPT_TARGET_SOUND, L.OPT_TARGET_SOUND_TIP },
	{ "targetPet", L.OPT_TARGET_PET, L.OPT_TARGET_PET_TIP },
	{ "stealthAlerts", L.OPT_STEALTH, L.OPT_STEALTH_TIP },
	{ "radar", L.OPT_RADAR, L.OPT_RADAR_TIP },
	{ "radarAuto", L.OPT_RADAR_AUTO, L.OPT_RADAR_AUTO_TIP },
	{ "radarSound", L.OPT_RADAR_SOUND, L.OPT_RADAR_SOUND_TIP },
	{ "bgTargets", L.OPT_BG_TARGETS, L.OPT_BG_TARGETS_TIP },
	{ "bgTargetsAllies", L.OPT_BG_TARGETS_ALLIES, L.OPT_BG_TARGETS_ALLIES_TIP },
	{ "bgTimers", L.OPT_BG_TIMERS, L.OPT_BG_TIMERS_TIP },
	{ "cdTracker", L.OPT_CD_TRACKER, L.OPT_CD_TRACKER_TIP },
	{ "cdDuels", L.OPT_CD_DUELS, L.OPT_CD_DUELS_TIP },
	{ "cdWorld", L.OPT_CD_WORLD, L.OPT_CD_WORLD_TIP },
	{ "cdBG", L.OPT_CD_BG, L.OPT_CD_BG_TIP },
	{ "capWarnings", L.OPT_CAP_WARNINGS, L.OPT_CAP_WARNINGS_TIP },
	{ "hudFade", L.OPT_HUD_FADE, L.OPT_HUD_FADE_TIP },
}

local SLIDERS = {
	{ "revengeCount", L.OPT_REVENGE_COUNT, L.OPT_REVENGE_COUNT_TIP, 2, 10, 1 },
	{ "revengeWindow", L.OPT_REVENGE_WINDOW, L.OPT_REVENGE_WINDOW_TIP, 5, 120, 5 },
}

function Options:Init()
	local settings = _G.Settings
	if not (settings and settings.RegisterVerticalLayoutCategory and settings.RegisterAddOnSetting
		and settings.CreateCheckbox and settings.RegisterAddOnCategory) then
		ns:Debug("Settings API not available; use /bm set <option> on|off")
		return
	end
	local boolean = settings.VarType and settings.VarType.Boolean or "boolean"
	local category = settings.RegisterVerticalLayoutCategory(ns.TITLE)
	for i = 1, #CHECKS do
		local key, label, tip = CHECKS[i][1], CHECKS[i][2], CHECKS[i][3]
		local setting = settings.RegisterAddOnSetting(category, "BusinessMeeting_" .. key, key, ns.settings, boolean, label,
			ns.DEFAULTS[key])
		settings.CreateCheckbox(category, setting, tip)
		if key == "nameplates" and setting and setting.SetValueChangedCallback then
			setting:SetValueChangedCallback(function()
				ns.Nameplates:Clear()
				ns.Detect.ScanNameplates()
				ns.Nameplates:Aims()
			end)
		elseif (key == "radar" or key == "radarAuto") and setting and setting.SetValueChangedCallback then
			setting:SetValueChangedCallback(function() ns.RadarUI:Update() end)
		elseif (key == "bgTargets" or key == "bgTargetsAllies") and setting and setting.SetValueChangedCallback then
			setting:SetValueChangedCallback(function() if ns.BGTargets then ns.BGTargets:Update() end end)
		elseif key == "bgTimers" and setting and setting.SetValueChangedCallback then
			setting:SetValueChangedCallback(function() if ns.BGTimersUI then ns.BGTimersUI:Update() end end)
		elseif (key == "cdTracker" or key == "cdDuels" or key == "cdWorld" or key == "cdBG")
			and setting and setting.SetValueChangedCallback then
			setting:SetValueChangedCallback(function()
				if ns.Cooldowns then ns.Cooldowns:OnTargetChanged() end
				if ns.CooldownsUI then ns.CooldownsUI:Update() end
			end)
		elseif key == "hudFade" and setting and setting.SetValueChangedCallback then
			setting:SetValueChangedCallback(function()
				if ns.RadarUI and ns.RadarUI.ApplyAlpha then ns.RadarUI:ApplyAlpha() end
				if ns.BGTargets and ns.BGTargets.ApplyAlpha then ns.BGTargets:ApplyAlpha() end
				if ns.BGTimersUI and ns.BGTimersUI.ApplyAlpha then ns.BGTimersUI:ApplyAlpha() end
				if ns.CooldownsUI and ns.CooldownsUI.ApplyAlpha then ns.CooldownsUI:ApplyAlpha() end
			end)
		end
	end
	if settings.CreateSlider and settings.CreateSliderOptions then
		local number = settings.VarType and settings.VarType.Number or "number"
		for i = 1, #SLIDERS do
			local key, label, tip, lo, hi, step = unpack(SLIDERS[i])
			local ok, err = pcall(function()
				local setting = settings.RegisterAddOnSetting(category, "BusinessMeeting_" .. key, key, ns.settings, number,
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
		local minimap = settings.RegisterProxySetting(category, "BusinessMeeting_minimap", boolean, L.OPT_MINIMAP, true,
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
		self:Print("/bm set <option> on|off - /bm help lists the options")
	end
end
