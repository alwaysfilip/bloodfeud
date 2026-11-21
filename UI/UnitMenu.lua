-- Adds "Add to Kill on Sight" to the right-click menu of an enemy player.
local _, ns = ...

local Names = ns.Names
local L = ns.L

local UnitMenu = {}
ns.UnitMenu = UnitMenu

local TAGS = { "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS" }

local function build(_, root, context)
	local session = ns.session
	if not session or type(context) ~= "table" then return end
	local unit = context.unit
	local info, name
	if unit then
		info = ns.Detect.Inspect(unit)
		if not info then return end -- not an enemy player
		name = info.name
	elseif context.which == "ENEMY_PLAYER" and type(context.name) == "string" then
		local surname = type(context.surname) == "string" and context.surname or nil
		name = Names.Canon(surname and (context.name .. "-" .. surname) or context.name)
	end
	if not name then return end

	local key = Names.Key(name)
	root:CreateDivider()
	root:CreateTitle(ns.TITLE)
	if ns:MyReport("r", key) then
		root:CreateButton(L.MENU_REMOVE, function() ns:RemoveMine("r", key) end)
	else
		root:CreateButton(L.MENU_ADD, function()
			ns.AddDialog:Open("player", { info = info, name = name })
		end)
	end
end

function UnitMenu:Init()
	local menu = _G.Menu
	if not (menu and menu.ModifyMenu) then
		ns:Debug("Menu.ModifyMenu not available; no right-click entry")
		return
	end
	for i = 1, #TAGS do
		menu.ModifyMenu(TAGS[i], function(owner, root, context)
			local ok, err = pcall(build, owner, root, context)
			if not ok then ns:Debug("unit menu: %s", tostring(err)) end
		end)
	end
end
