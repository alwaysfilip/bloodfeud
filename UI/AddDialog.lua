-- The small dialog for adding a player or guild, or editing a reason.
local _, ns = ...

local W, Fmt, Names, Codec = ns.W, ns.Fmt, ns.Names, ns.Codec
local L = ns.L

local Dialog = {}
ns.AddDialog = Dialog

function Dialog:Build()
	local f = W.Panel(UIParent, "BloodFeudAddDialog")
	self.frame = f
	f:SetSize(380, 248)
	f:SetPoint("CENTER", 0, 90)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	W.Movable(f)
	f:Hide()
	tinsert(UISpecialFrames, "BloodFeudAddDialog")

	f.title = W.Label(f, "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", 16, -14)
	f.title:SetTextColor(0.94, 0.78, 0.37)

	f.nameLabel = W.Label(f, "GameFontDisableSmall")
	f.nameLabel:SetPoint("TOPLEFT", 16, -46)
	f.name = W.EditBox(f, 348, 26, 60)
	f.name:SetPoint("TOPLEFT", 16, -62)
	f.detail = W.Label(f, "GameFontDisableSmall")
	f.detail:SetPoint("TOPLEFT", 16, -92)
	f.detail:SetPoint("RIGHT", f, "RIGHT", -16, 0)

	local reasonLabel = W.Label(f, "GameFontDisableSmall", L.FIELD_REASON)
	reasonLabel:SetPoint("TOPLEFT", 16, -114)
	f.reason = W.EditBox(f, 348, 26)
	f.reason:SetPoint("TOPLEFT", 16, -130)
	f.reason:SetMaxBytes(Codec.MAX_REASON + 1)
	f.count = W.Label(f, "GameFontDisableSmall")
	f.count:SetPoint("TOPLEFT", 16, -160)

	f.hint = W.Label(f, "GameFontHighlightSmall", L.SHARED_HINT)
	f.hint:SetPoint("TOPLEFT", 16, -182)
	f.hint:SetTextColor(0.79, 0.78, 0.74)

	f.ok = W.Button(f, L.ADD, 170, 28, "danger")
	f.ok:SetPoint("BOTTOMLEFT", 16, 14)
	f.ok:SetScript("OnClick", function() Dialog:Submit() end)
	local cancel = W.Button(f, L.CANCEL, 170, 28)
	cancel:SetPoint("BOTTOMRIGHT", -16, 14)
	cancel:SetScript("OnClick", function() f:Hide() end)

	local function count()
		f.count:SetText(L.REASON_COUNT:format(#(f.reason:GetText() or ""), Codec.MAX_REASON))
	end
	f.reason:SetScript("OnTextChanged", count)
	f.reason:SetScript("OnEnterPressed", function() Dialog:Submit() end)
	f.name:SetScript("OnEnterPressed", function() f.reason:SetFocus() end)
	f.name:SetScript("OnTabPressed", function() f.reason:SetFocus() end)
	f.reason:SetScript("OnTabPressed", function() f.name:SetFocus() end)
	f.name:SetScript("OnEscapePressed", function() f:Hide() end)
	f.reason:SetScript("OnEscapePressed", function() f:Hide() end)
	f.name:SetScript("OnTextChanged", function() Dialog:UpdateDetail() end)
	count()
end

--- What we know about the name currently in the field.
function Dialog:UpdateDetail()
	local f, opts = self.frame, self.opts or {}
	if self.mode ~= "player" then
		f.detail:SetText("")
		return
	end
	local typed = Names.Canon(f.name:GetText() or "", true)
	local info = opts.info
	if info and typed and Names.Key(typed) == info.key then
		local what = Fmt.Describe(info)
		f.detail:SetText(what .. (info.guild and ((what ~= "" and " · " or "") .. "<" .. info.guild .. ">") or ""))
	else
		f.detail:SetText(L.NAME_HINT)
	end
end

--- mode: "player" (opts.info from Detect.Inspect, or opts.name),
---       "guild", or "edit" (opts.kind, opts.name, opts.reason).
function Dialog:Open(mode, opts)
	if not ns.session then
		ns:Print(L.MSG_NO_GUILD)
		return
	end
	if mode == "guild" and not ns:CanAdd("g") then
		ns:Print(L.MSG_NOT_OFFICER)
		return
	end
	if not self.frame then self:Build() end
	local f = self.frame
	self.mode, self.opts = mode, opts or {}
	opts = self.opts

	local name
	if mode == "guild" then
		f.title:SetText(L.DIALOG_ADD_GUILD)
		f.nameLabel:SetText(L.FIELD_GUILD)
		name = opts.name or ""
	elseif mode == "edit" then
		f.title:SetText(L.DIALOG_EDIT)
		f.nameLabel:SetText(opts.kind == "g" and L.FIELD_GUILD or L.FIELD_PLAYER)
		name = opts.kind == "g" and opts.name or Names.Display(opts.name)
	else
		f.title:SetText(L.DIALOG_ADD_PLAYER)
		f.nameLabel:SetText(L.FIELD_PLAYER)
		name = (opts.info and opts.info.name) or opts.name or ""
	end
	f.name:SetText(name)
	f.name:SetEnabled(mode ~= "edit")
	f.reason:SetText(opts.reason or "")
	f.ok:SetLabel(mode == "edit" and L.SAVE or L.ADD)
	self:UpdateDetail()
	f:Show()
	if name == "" then f.name:SetFocus() else f.reason:SetFocus() end
end

function Dialog:Submit()
	local f, opts = self.frame, self.opts
	local reason = f.reason:GetText() or ""
	local done
	if self.mode == "guild" then
		done = ns:AddGuild(f.name:GetText(), reason)
	elseif self.mode == "edit" then
		if opts.kind == "g" then
			done = ns:AddGuild(opts.name, reason)
		else
			done = ns:AddPlayer(opts.name, reason)
		end
	else
		local typed = Names.Canon(f.name:GetText() or "", true)
		local info = opts.info
		if info and typed and Names.Key(typed) == info.key then
			done = ns:AddPlayer(info.name, reason, info)
		else
			done = ns:AddPlayer(typed, reason)
		end
	end
	if done then f:Hide() end
end
