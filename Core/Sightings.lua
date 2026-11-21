-- "X spotted in <zone> by <guildmate>": short-lived, rate-limited and never
-- part of the synced state. It rides on its own addon prefix so it has its
-- own share of the server's message allowance.
local _, ns = ...

local Codec, Names, Fmt = ns.Codec, ns.Names, ns.Fmt
local L = ns.L

local Sightings = { recent = {}, lastSent = 0 }
ns.Sightings = Sightings

local PER_PLAYER = 120 -- one report per listed player per two minutes, guild-wide
local MIN_GAP = 5 -- and never more than one of ours every few seconds
local MAX_AGE = 600

--- The player just met a listed enemy.
function Sightings:Report(key, info)
	local session = ns.session
	if not session then return end
	local now = GetServerTime()
	local map, x, y = Fmt.PlayerPosition()
	session.store:SetSeen(key, { at = now, map = map, x = x, y = y, by = session.me })

	if not ns.settings.sightSend then return end
	local last = self.recent[key]
	if last and now - last < PER_PLAYER then return end
	if now - self.lastSent < MIN_GAP then return end
	self.recent[key] = now
	self.lastSent = now
	ns.Comm.Send("sight", Codec.EncodeSighting({ key = key, name = info.name, map = map, x = x, y = y, t = now }))
end

--- A guildmate's sighting arrived.
function Sightings:OnFrame(sender, text)
	local session = ns.session
	if not session then return end
	local s = Codec.DecodeSighting(text)
	if not s or not session.store:IsListed(s.key) then return end
	local now = GetServerTime()
	if s.t > now + 120 or now - s.t > MAX_AGE then return end

	local last = self.recent[s.key]
	if not last or s.t > last then self.recent[s.key] = s.t end
	if Names.Key(sender) == session.meKey then return end -- our own report, echoed back

	local newer = session.store:SetSeen(s.key, { at = s.t, map = s.map, x = s.x, y = s.y, by = sender })
	if not newer or not ns.settings.sightShow then return end
	local subject = session.store:Player(s.key)
	if not subject then return end
	local what = Fmt.Describe(subject.facts)
	local zone = Fmt.Zone(s.map) or L.UNKNOWN
	ns:Print(L.SIGHTING:format(Fmt.PlayerName(subject), what ~= "" and (" (" .. what .. ")") or "", zone,
		Fmt.Color(Fmt.LINK, Fmt.Coords(s.x, s.y)), Names.Display(sender)))
end

function Sightings:Init()
	-- Forget old rate-limit entries now and then.
	C_Timer.NewTicker(300, function()
		local now = GetServerTime()
		for key, at in pairs(Sightings.recent) do
			if now - at > MAX_AGE then Sightings.recent[key] = nil end
		end
	end)
end
