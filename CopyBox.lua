local ns = select(2, ...)

-- A window with some text in a real text box, all selected, so it can be copied (Ctrl+C)
-- and pasted outside the game. The terminal's own prompt can't reach the clipboard (only a
-- real text box can), so anything meant to be copied out opens here: .debug log, for one.
--
--   ns:ShowText(title, text or list of lines)
--   ns:ShowText(title, text, { compact = true })   one line (a link, a style string): a slim bar in the
--       terminal's look, sized to the text (wrapping onto a few lines when it's long), that closes by
--       itself once Ctrl+C has copied it
--
-- The box can be scrolled and clicked into, but not edited (typing puts the text back).
-- Esc or the Close button closes it.

local C = {}
ns.CopyBox = C

local frame, edit, scroll, titleFS, hintFS, current = nil, nil, nil, nil, nil, ""
local link, linkEdit, linkTitle, linkHint, linkBox -- the slim one-line bar (below)

local W, H = 700, 440

local function Build()
	if frame then return end
	local Theme = ns.Theme
	frame = CreateFrame("Frame", "TerminalCopyFrame", UIParent, "BackdropTemplate")
	frame:SetSize(W, H)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	frame:Hide()
	tinsert(UISpecialFrames, "TerminalCopyFrame") -- Esc closes it

	titleFS = frame:CreateFontString(nil, "OVERLAY")
	titleFS:SetFontObject(Theme.fonts.row)
	titleFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
	hintFS = frame:CreateFontString(nil, "OVERLAY")
	hintFS:SetFontObject(Theme.fonts.small)
	hintFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -14)

	local ok, sf = pcall(CreateFrame, "ScrollFrame", "TerminalCopyScroll", frame, "UIPanelScrollFrameTemplate")
	if not ok or not sf then sf = CreateFrame("ScrollFrame", "TerminalCopyScroll", frame) end
	scroll = sf
	sf:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -40)
	sf:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 46)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 48)))
	end)

	edit = CreateFrame("EditBox", nil, sf)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(Theme.fonts.small)
	edit:SetWidth(W - 56)
	edit:SetMaxLetters(0)
	edit:SetScript("OnEscapePressed", function() C.Hide() end)
	-- read-only: whatever is typed is put back
	edit:SetScript("OnTextChanged", function(self, user)
		if user and self:GetText() ~= current then
			self:SetText(current)
			self:HighlightText()
		end
	end)
	sf:SetScrollChild(edit)

	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(90, 24)
	close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)
	close:SetText(CLOSE or "Close")
	close:SetScript("OnClick", function() C.Hide() end)
	C.close = close

	C.frame, C.edit = frame, edit
end

local function Style()
	local Theme = ns.Theme
	local t = Theme.Get()
	local br, bg, bb = Theme.RGB(t.bg)
	local er, eg, eb = Theme.RGB(t.border)
	frame:SetBackdropColor(br, bg, bb, math.max(0.97, t.bgAlpha or 0.97))
	frame:SetBackdropBorderColor(er, eg, eb, 1)
	local tr, tg, tb = Theme.RGB(t.text)
	local ar, ag, ab = Theme.RGB(t.accent)
	local dr, dg, db = Theme.RGB(t.dim)
	titleFS:SetTextColor(ar, ag, ab)
	hintFS:SetTextColor(dr, dg, db)
	edit:SetTextColor(tr, tg, tb)
end

--- The text currently in the window (for tests and callers).
function C.Text() return current end

function C.Hide()
	if frame then
		edit:ClearFocus()
		frame:Hide()
	end
	if link and link:IsShown() then
		link:Hide()
		linkEdit:ClearFocus()
	end
end

----------------------------------------------------------------------
-- One line (a link): a slim bar in the terminal's look, where the terminal sits, the text
-- selected. Ctrl+C copies it and the bar goes; Esc (or clicking elsewhere) closes it.
----------------------------------------------------------------------

local function BuildLink()
	if link then return end
	local Theme = ns.Theme
	link = CreateFrame("Frame", "TerminalLinkFrame", UIParent, "BackdropTemplate")
	link:SetFrameStrata("DIALOG")
	link:SetClampedToScreen(true)
	link:EnableMouse(true)
	link:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	link:Hide()
	tinsert(UISpecialFrames, "TerminalLinkFrame")

	linkTitle = link:CreateFontString(nil, "OVERLAY")
	linkTitle:SetFontObject(Theme.fonts.small)
	linkTitle:SetPoint("TOPLEFT", link, "TOPLEFT", 10, -7)
	linkTitle:SetJustifyH("LEFT")
	linkTitle:SetWordWrap(false)
	linkHint = link:CreateFontString(nil, "OVERLAY")
	linkHint:SetFontObject(Theme.fonts.small)
	linkHint:SetPoint("TOPRIGHT", link, "TOPRIGHT", -10, -7)
	linkTitle:SetPoint("RIGHT", linkHint, "LEFT", -12, 0)

	-- the text sits on the prompt's own darker strip
	linkBox = link:CreateTexture(nil, "BACKGROUND", nil, 1)
	linkBox:SetPoint("TOPLEFT", link, "TOPLEFT", 1, -24)
	linkBox:SetPoint("BOTTOMRIGHT", link, "BOTTOMRIGHT", -1, 1)

	linkEdit = CreateFrame("EditBox", nil, link)
	linkEdit:SetMultiLine(false)
	linkEdit:SetAutoFocus(false)
	linkEdit:SetFontObject(Theme.fonts.row)
	linkEdit:SetPoint("TOPLEFT", linkBox, "TOPLEFT", 9, 0)
	linkEdit:SetPoint("BOTTOMRIGHT", linkBox, "BOTTOMRIGHT", -9, 0)
	linkEdit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	linkEdit:SetScript("OnEscapePressed", function() C.Hide() end)
	linkEdit:SetScript("OnEnterPressed", function() C.Hide() end) -- (a wrapped bar is multi-line: Enter would add a line)
	linkEdit:SetScript("OnEditFocusLost", function() C.Hide() end)
	linkEdit:SetScript("OnTextChanged", function(self, user) -- read-only
		if user and self:GetText() ~= current then
			self:SetText(current)
			self:HighlightText()
		end
	end)
	-- gone once copied (the copy itself is the game's own, on this key)
	linkEdit:SetScript("OnKeyDown", function(_, key)
		if key == "C" and IsControlKeyDown() then
			C.copied = true
			C_Timer.After(0.1, C.Hide)
		end
	end)
	C.linkFrame, C.linkEdit = link, linkEdit
end

local function ShowLink(title, text)
	BuildLink()
	local Theme = ns.Theme
	local t = Theme.Get()
	link:SetBackdropColor(Theme.RGB(t.bg))
	link:SetBackdropBorderColor(Theme.RGB(t.border))
	linkBox:SetColorTexture(Theme.RGB(t.promptBg or t.bg))
	linkTitle:SetTextColor(Theme.RGB(t.accent))
	linkHint:SetTextColor(Theme.RGB(t.dim))
	linkEdit:SetTextColor(Theme.RGB(t.text))
	linkTitle:SetText(title)
	linkHint:SetText("Ctrl+C copies  ·  Esc closes")
	-- as wide as the text needs (and the title line), within reason
	local measure = link.measure or link:CreateFontString(nil, "OVERLAY")
	link.measure = measure
	measure:SetFontObject(Theme.fonts.row)
	measure:SetText(text)
	local w = (measure:GetStringWidth() or 300) + 40
	local tw = (linkTitle:GetStringWidth() or 0) + (linkHint:GetStringWidth() or 0) + 44
	-- text wider than the bar wraps onto a few lines (a style string: it has a space after each ';' for that)
	-- instead of scrolling off: a long text gets a narrower, taller bar in the middle of the screen; a link
	-- the width it needs, where the terminal sits
	local long = w > 700
	local MAX_W = long and 560 or 700
	local width = math.max(320, math.min(MAX_W, math.max(w, tw)))
	local lines = math.max(1, math.min(8, math.ceil((w - 40) / (width - 40))))
	C.linkLines = lines
	-- the box is sized and made multi-line before the text goes in, so the text is laid out (wrapped)
	-- before it's selected: selected first, only the first line showed as highlighted
	link:SetSize(width, 24 + lines * (t.fontSize + 5) + 12)
	linkEdit:SetMultiLine(lines > 1)
	linkEdit:SetText("")
	linkEdit:SetText(text)
	linkEdit:SetCursorPosition(0)
	link:ClearAllPoints()
	local pt = ns.db and ns.db.point
	if long or not pt then
		link:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	else
		link:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
	end
	link:Show()
	C_Timer.After(0.05, function()
		if link:IsShown() then
			linkEdit:SetFocus()
			linkEdit:HighlightText()
		end
	end)
end

function C.Show(title, text, options)
	local opts = options or {}
	C.copied = false
	if opts.compact then
		current = tostring(text or "")
		if frame then frame:Hide() end
		return ShowLink(tostring(title or "Terminal"), current)
	end
	if link then link:Hide() end
	if type(text) == "table" then
		local lines = {}
		for i, l in ipairs(text) do lines[i] = tostring(l) end
		text = table.concat(lines, "\n")
	end
	current = tostring(text or "")
	Build()
	Style()
	titleFS:SetText(tostring(title or "Terminal"))
	hintFS:SetText("Ctrl+C copies everything  -  Esc closes")
	edit:SetText(current)
	scroll:SetVerticalScroll(0)
	frame:Show()
	-- a moment later, so the key that ran the command isn't typed into the box
	C_Timer.After(0.05, function()
		if frame:IsShown() then
			edit:SetFocus()
			edit:HighlightText()
		end
	end)
end

function ns:ShowText(title, text, options) C.Show(title, text, options) end
