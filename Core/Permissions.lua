-- Who may write what. One pure function, used both to gate the interface and
-- to check edits that arrive straight from their writer.
--
--   player report  its author, or an officer
--   guild report   officers only
--   facts          any guild member
--   score          its author only
--   member totals  that member only
--   rank tier      officers only
--   bounty         its poster, or an officer
--   bounty claims  the claimer only
--
-- What this can and cannot do: an edit whose writer is the sender is checked,
-- because the game server stamps the sender and it cannot be forged. State
-- that one member relays on behalf of another cannot be verified (there is no
-- way to sign a message), so it is accepted and attributed in the log instead.
local _, ns = ...

local Permissions = {}
ns.Permissions = Permissions

local OWN = { c = true, m = true, k = true }

--- May `actorKey` (folded character name) write this record?
--- roster must provide IsOfficer(key) -> boolean.
function Permissions.CanWrite(rec, actorKey, roster)
	if rec.k == "f" then return true end
	if OWN[rec.k] then return rec.akey == actorKey end
	if rec.k == "g" or rec.k == "t" then return roster.IsOfficer(actorKey) and true or false end
	if rec.akey == actorKey then return true end
	return roster.IsOfficer(actorKey) and true or false
end

--- Does checking this direct edit need the guild roster? Writing your own
--- record never does; anything an officer may do for others does.
function Permissions.NeedsRoster(rec, actorKey)
	if rec.k == "f" or OWN[rec.k] then return false end
	if rec.k == "g" or rec.k == "t" then return true end
	return rec.akey ~= actorKey
end

--- Interface gate: may `actorKey` add a report of this kind at all?
function Permissions.CanAdd(kind, actorKey, roster)
	if kind == "g" or kind == "t" then return roster.IsOfficer(actorKey) and true or false end
	return true
end
