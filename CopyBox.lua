local ns = select(2, ...)

-- A window with some text in a real text box, all selected, so it can be copied (Ctrl+C)
-- and pasted outside the game. The terminal's own prompt can't reach the clipboard (only a
-- real text box can), so anything meant to be copied out opens here: .debug log, for one.
--
--   ns:ShowText(title, text or list of lines)
--
-- The box can be scrolled and clicked into, but not edited (typing puts the text back).
-- Esc, the Close button or clicking away from nothing closes it.

local C = {}
ns.CopyBox = C

local frame, edit, scroll, titleFS, hintFS, current = nil, nil, nil, nil, nil, ""

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
end

function C.Show(title, text)
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

function ns:ShowText(title, text) C.Show(title, text) end
