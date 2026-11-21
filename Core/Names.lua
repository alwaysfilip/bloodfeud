-- Character names in WoW: Forever. There are no realms; a character is
-- identified by a first name and an optional surname, and the pair is unique
-- in the region. The client hands these out in three shapes:
--   UnitName(unit)         -> "First", "Surname"   (surname where older
--                                                    clients gave the realm)
--   display text           -> "First Surname"
--   chat senders and links -> "First-Surname"
-- Internally the addon uses one canonical spelling, "First-Surname", which
-- is also what chat commands and whispers accept. Everything that turns a
-- game value into a name goes through this file.
local _, ns = ...

local Util = ns.Util

local Names = {}
ns.Names = Names

local LINK_SEP = "-"

local function surnameSep()
	local consts = _G.Constants and _G.Constants.CharacterNameSeparatorConsts
	return (consts and consts.CHARACTERNAME_SURNAME_SEPARATOR) or " "
end

local function join(first, surname)
	if surname and surname ~= "" then return first .. LINK_SEP .. surname end
	return first
end

--- Canonical name from text in any of the three shapes. Returns nil for
--- empty input. Pass fixCase for something a person typed; names that come
--- from the game keep the capitalisation the game gave them.
function Names.Canon(text, fixCase)
	if Util.IsSecret(text) or type(text) ~= "string" then return nil end
	text = Util.Clean(text, 96)
	if text == "" then return nil end
	local sep = surnameSep()
	local first, rest = text:match("^([^%-%s]+)[%-%s]+(.+)$")
	if not first and sep ~= " " and sep ~= LINK_SEP then
		local at = text:find(sep, 1, true)
		if at and at > 1 then
			first, rest = text:sub(1, at - 1), text:sub(at + #sep)
		end
	end
	if first then
		rest = rest:gsub("[%-%s]+", LINK_SEP)
		if fixCase then
			first = Util.TitleCase(first)
			rest = rest:gsub("[^%-]+", Util.TitleCase)
		end
		return first .. LINK_SEP .. rest
	end
	return fixCase and Util.TitleCase(text) or text
end

--- Canonical name of a unit, or nil when it cannot be read (no such unit, or
--- the identity is a secret value in this context).
function Names.OfUnit(unit)
	local getter = _G.UnitNameUnmodified or _G.UnitName
	local ok, first, surname = pcall(getter, unit)
	if not ok or first == nil or Util.IsSecret(first) or Util.IsSecret(surname) then return nil end
	if type(first) ~= "string" or first == "" then return nil end
	if type(surname) ~= "string" then surname = nil end
	return Names.Canon(join(first, surname))
end

--- Canonical name of the sender of a chat or addon message.
function Names.OfSender(sender)
	return Names.Canon(sender)
end

--- "First-Surname" -> "First Surname" for showing to the player.
function Names.Display(canon)
	if type(canon) ~= "string" then return "" end
	return (canon:gsub(LINK_SEP, " "))
end

--- Identity key: the case-folded canonical name.
function Names.Key(canon)
	return Util.Fold(canon)
end

--- Key of just the first name, for entries typed without a surname.
function Names.FirstKey(canon)
	local first = canon:match("^([^%-]+)%-")
	return first and Util.Fold(first) or nil
end

--- The player's own canonical name (cached after the first successful read).
function Names.Me()
	if not Names.me then
		Names.me = Names.OfUnit("player")
	end
	return Names.me
end
