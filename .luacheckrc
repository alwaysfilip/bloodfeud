std = "lua51"
max_line_length = 140
codes = true
exclude_files = { "Libs", ".release" }

-- Addon files receive (addonName, namespace) as varargs.
ignore = {
	"212/self", -- unused self in methods
}

globals = {
	"BloodFeudDB",
	"BloodFeud_OnAddonCompartmentClick",
	"BloodFeud_OnAddonCompartmentEnter",
	"BloodFeud_OnAddonCompartmentLeave",
	"SLASH_BLOODFEUD1", "SLASH_BLOODFEUD2",
	"SlashCmdList",
	"StaticPopupDialogs",
}

read_globals = {
	"bit", "issecretvalue", "strsplit", "strtrim", "wipe", "tinsert", "tremove", "date", "time", "format",
	"C_AddOns", "C_ChatInfo", "C_ClassColor", "C_CreatureInfo", "C_GuildInfo", "C_Map", "C_NamePlate",
	"C_RestrictedActions", "C_Timer", "C_TooltipInfo",
	"ChatThrottleLib", "LibStub",
	"CreateFrame", "CreateColor", "UIParent", "GameTooltip", "DEFAULT_CHAT_FRAME", "ChatFontNormal",
	"GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontHighlight", "GameFontHighlightSmall",
	"GameFontDisable", "GameFontDisableSmall", "RAID_CLASS_COLORS", "UISpecialFrames", "BackdropTemplateMixin",
	"Enum", "Menu", "MenuUtil", "Settings", "TooltipDataProcessor", "StaticPopup_Show", "StaticPopup_Hide",
	"PlaySound", "PlaySoundFile", "SOUNDKIT", "RaidNotice_AddMessage", "RaidWarningFrame", "ChatTypeInfo",
	"GetTime", "GetServerTime", "GetBuildInfo", "GetLocale", "GetRealmName", "GetNormalizedRealmName",
	"GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "IsInGuild", "IsInInstance", "InCombatLockdown",
	"UnitName", "UnitFullName", "UnitGUID", "UnitClass", "UnitRace", "UnitLevel", "UnitExists", "UnitIsPlayer",
	"UnitIsEnemy", "UnitIsFriend", "UnitCanAttack", "UnitFactionGroup", "UnitIsUnit", "UnitIsDeadOrGhost",
	"GetPlayerInfoByGUID", "Ambiguate", "WOW_PROJECT_ID", "IsShiftKeyDown", "IsControlKeyDown",
	"hooksecurefunc", "geterrorhandler", "securecallfunction", "debugstack", "ChatEdit_InsertLink",
	"OpenWorldMap", "TargetUnit", "GetMouseFoci", "GetCursorPosition",
}

files["tests/*.lua"] = {
	std = "luajit",
	globals = { "bit", "BloodFeudDB", "GameTooltip" },
	read_globals = { "BloodFeudAlertBanner", "BloodFeudAddDialog", "SlashCmdList", "GetServerTime" },
}
