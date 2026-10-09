local ns = select(2, ...)
local T = ns.Theme

-- Options panel (Game Menu > Options > AddOns > Terminal) and the .options command.
-- Every control writes through Theme.Set / Theme.ApplyPreset, so changes show live in the
-- preview and the terminal, and the same settings stay reachable from  .set  in any client.

local O = {}
ns.Options = O
O.widgets = {}

local panel = CreateFrame("Frame", "TerminalOptionsPanel")
panel.name = "Terminal"
panel:Hide()
O.panel = panel

local function Label(text, template, x, y, parent)
	local fs = (parent or panel):CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FLAT = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 } -- (a white backdrop with a 1 px edge, coloured by each user)

----------------------------------------------------------------------
-- Controls
----------------------------------------------------------------------

local function Slider(key, x, y)
	local f = T.FIELDS[key]
	Label(f.label, "GameFontHighlight", x, y)
	local s = CreateFrame("Slider", nil, panel, "BackdropTemplate")
	s:SetOrientation("HORIZONTAL")
	s:SetSize(190, 14)
	s:SetPoint("TOPLEFT", x + 110, y - 1)
	s:SetBackdrop(FLAT)
	s:SetBackdropColor(0, 0, 0, 0.5)
	s:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	s:SetMinMaxValues(f.min, f.max)
	s:SetValueStep(f.step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:EnableMouseWheel(true)
	local value = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	value:SetPoint("LEFT", s, "RIGHT", 8, 0)
	s:SetScript("OnValueChanged", function(_, v)
		value:SetText(T.Format(key, v))
		if not O.syncing then T.Set(key, v) end
	end)
	s:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(self:GetValue() + delta * f.step)
	end)
	s.valueText = value
	O.widgets[key] = s
end

local function PickColor(key)
	local prev = T.Get()[key]
	local r, g, b = T.RGB(prev or T.Get().accent) -- (fzfColor unset: the selection colour)
	if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
		local function apply()
			local nr, ng, nb = ColorPickerFrame:GetColorRGB()
			T.Set(key, ("%02x%02x%02x"):format(math.floor(nr * 255 + 0.5), math.floor(ng * 255 + 0.5), math.floor(nb * 255 + 0.5)))
		end
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, hasOpacity = false,
			swatchFunc = apply,
			cancelFunc = function() T.Set(key, prev) end,
		})
	else
		ns:Print("Set it from the terminal instead:  .set " .. key .. " rrggbb")
	end
end

local function Swatch(key, x, y)
	local b = CreateFrame("Button", nil, panel, "BackdropTemplate")
	b:SetSize(18, 18)
	b:SetPoint("TOPLEFT", x, y)
	b:SetBackdrop(FLAT)
	b:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	if T.FIELDS[key].optional and b.RegisterForClicks then
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp") -- (right-click: back to the theme's own colour)
	end
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" and T.FIELDS[key].optional then T.Set(key, "accent") return end
		PickColor(key)
	end)
	local l = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	l:SetPoint("LEFT", b, "RIGHT", 6, 0)
	l:SetText(T.FIELDS[key].label .. (T.FIELDS[key].optional and "  |cff8a8a8a(right-click: selection colour)|r" or ""))
	O.widgets[key] = b
end

----------------------------------------------------------------------
-- Colour example: a small sample beside the theme buttons, drawn with the current colours
----------------------------------------------------------------------

local pv = CreateFrame("Frame", nil, panel, "BackdropTemplate")
pv:SetSize(196, 52)
pv:SetPoint("TOPLEFT", 440, -88)
pv:SetBackdrop(FLAT)
if pv.SetClipsChildren then pv:SetClipsChildren(true) end
Label("Example", "GameFontNormal", 440, -70)
O.preview = pv

pv.prompt = pv:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
pv.prompt:SetPoint("TOPLEFT", 8, -7)
pv.query = pv:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
pv.query:SetPoint("LEFT", pv.prompt, "RIGHT", 5, 0)
pv.caret = pv:CreateTexture(nil, "OVERLAY")
pv.caret:SetSize(2, 13)
pv.caret:SetPoint("LEFT", pv.query, "RIGHT", 1, 0)
pv.band = pv:CreateTexture(nil, "BACKGROUND", nil, 1)
pv.band:SetPoint("TOPLEFT", 3, -27)
pv.band:SetPoint("TOPRIGHT", -3, -27)
pv.band:SetHeight(20)
pv.label = pv:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pv.label:SetPoint("LEFT", pv.band, "LEFT", 6, 0)
pv.detail = pv:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pv.detail:SetPoint("RIGHT", pv.band, "RIGHT", -6, 0)

local function PaintPreview()
	local t = T.Get()
	local r, g, b = T.RGB(t.bg)
	pv:SetBackdropColor(r, g, b, t.bgAlpha)
	pv:SetBackdropBorderColor(T.RGB(t.border))
	pv.prompt:SetText("|cff" .. t.prompt .. t.promptText:gsub("|", "||") .. "|r")
	pv.query:SetText("hvy ban")
	pv.query:SetTextColor(T.RGB(t.text))
	pv.caret:SetColorTexture(T.RGB(t.accent))
	local box = t.cursor == "blinking-box" or t.cursor == "solid-box"
	pv.caret:SetSize(box and 8 or 2, 13)
	pv.caret:SetAlpha(box and 0.85 or 1)
	local ar, ag, ab = T.RGB(t.accent)
	pv.band:SetColorTexture(ar, ag, ab, 0.18)
	ns.Fuzzy.matchColor = "|cff" .. t.match
	pv.label:SetText(ns.Fuzzy.Colorize("Heavy Linen Bandage", { [1] = true, [4] = true, [5] = true, [13] = true, [14] = true, [15] = true }))
	pv.label:SetTextColor(T.RGB(t.text))
	pv.detail:SetText("First Aid")
	pv.detail:SetTextColor(T.RGB(t.dim))
end
O.PaintPreview = PaintPreview

-- The example plays on a loop, the way the terminal moves with the chosen animation and cursor:
-- it opens, the query is typed, the result comes in, the cursor blinks while idle, then it closes.
local QUERY = "hvy ban"
local TYPE_AT, TYPE_STEP, IDLE, GAP = 0.15, 0.11, 2.4, 0.5
local demo = { t = 0 }
O.demo = demo

local Ease, Move = T.Ease, T.Move
local STEP = 1 / 30 -- the example redraws 30 times a second, and only what changed

-- each setter touches the frame only when the value changed
local function Alpha(f, a)
	a = math.floor(a * 50 + 0.5) / 50
	if f._a ~= a then f._a = a; f:SetAlpha(a) end
end
local function PreviewAt(y) -- the example moved y pixels from its place (opening, closing)
	y = math.floor((y or 0) + 0.5)
	if pv._y == y then return end
	pv._y = y
	pv:ClearAllPoints()
	pv:SetPoint("TOPLEFT", 440, -88 + y)
end
local function LabelAt(dx)
	dx = math.floor(dx + 0.5)
	if pv.label._dx == dx then return end
	pv.label._dx = dx
	pv.label:ClearAllPoints()
	pv.label:SetPoint("LEFT", pv.band, "LEFT", 6 + dx, 0)
end

function O.AnimatePreview(elapsed)
	demo.t = demo.t + (elapsed or 0)
	demo.acc = (demo.acc or 0) + (elapsed or 0)
	if demo.acc < STEP and elapsed and elapsed > 0 and elapsed < STEP then return end
	demo.acc = 0
	local t = T.Get()
	local A = T.Animation(t) -- nil: animations off
	local open = A and A.open or 0
	local close = A and A.close or 0
	local typed = open + TYPE_AT + #QUERY * TYPE_STEP
	local rowFade = A and A.rowFade or 0
	local closeAt = typed + rowFade + IDLE
	local cycle = closeAt + close + GAP
	local c = demo.t % cycle
	demo.phase = c
	-- opening and closing: fade, and the style's drift (scaled to the example's size)
	local alpha, y = 1, 0
	if A and c < open then
		alpha, y = Ease(c / (A.fade or open)), -A.drift * 0.4 * (1 - Move(A, c / open))
	elseif c >= closeAt then
		local k = A and close > 0 and Ease((c - closeAt) / close) or 1
		alpha, y = 1 - k, A and -A.closeDrift * 0.4 * k or 0
	end
	Alpha(pv, alpha)
	PreviewAt(-y)
	-- typing, a letter at a time
	local n = math.max(0, math.min(#QUERY, math.floor((c - open - TYPE_AT) / TYPE_STEP) + 1))
	if c < open + TYPE_AT then n = 0 end
	if demo.typed ~= n then demo.typed = n; pv.query:SetText(QUERY:sub(1, n)) end
	-- the result comes in once typed, as rows do (fade; cascade swings it in from the left and,
	-- closing, back out)
	local k, dx = 0, 0
	local slide = A and A.slide or 0
	if c >= typed then
		local x = rowFade > 0 and (c - typed) / rowFade or 1
		k = Ease(x)
		dx = -slide * (1 - Move(A, x))
	end
	if A and A.foldOut and c >= closeAt then dx = -slide * Ease((c - closeAt) / close) end
	Alpha(pv.band, k)
	Alpha(pv.label, k)
	Alpha(pv.detail, k)
	LabelAt(dx)
	-- the cursor: solid while typing, then blinking (or not) as set, at the set speed
	local box = t.cursor == "blinking-box" or t.cursor == "solid-box"
	local blink = t.cursor == "blinking-line" or t.cursor == "blinking-box" or not T.CURSOR_LABELS[t.cursor]
	local a = 1
	local idle = c - typed - 0.45
	if blink and idle > 0 then
		local wave = math.cos(idle * math.pi * 2 * (t.blinkRate or 0.8))
		a = box and math.max(0, math.min(1, 0.5 + 1.4 * wave)) or (0.55 + 0.45 * wave)
	end
	Alpha(pv.caret, a * (box and 0.85 or 1))
end
pv:SetScript("OnUpdate", function(_, elapsed) O.AnimatePreview(elapsed) end)

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------

Label("Terminal", "GameFontNormalLarge", 16, -16)
Label("Theme and layout of the terminal. Everything here can also be set from the terminal, e.g.  .set accent ff79c6", "GameFontHighlightSmall", 16, -40)

-- Dropdowns: a button that opens a list of choices (themes, cursor styles)
local openLists = {}
local function Dropdown(x, y, w, ids, labelOf, onPick)
	local menu = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	menu:SetSize(w, 22)
	menu:SetPoint("TOPLEFT", x, y)
	local arrow = menu:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetSize(12, 12)
	arrow:SetPoint("RIGHT", -8, 0)
	arrow:SetRotation(-math.pi / 2) -- pointing down

	local list = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	list:SetPoint("TOPLEFT", menu, "BOTTOMLEFT", 0, -2)
	list:SetSize(w, #ids * 20 + 8)
	list:SetFrameStrata("DIALOG")
	list:SetBackdrop({ bgFile = WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	list:SetBackdropColor(0.05, 0.04, 0.03, 0.97)
	list:SetBackdropBorderColor(0.69, 0.5, 0.25, 1)
	list:Hide()
	openLists[#openLists + 1] = list
	local items = {}
	for i, id in ipairs(ids) do
		local item = CreateFrame("Button", nil, list)
		item:SetSize(w - 8, 20)
		item:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
		local hl = item:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 0.82, 0, 0.18)
		item.text = item:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		item.text:SetPoint("LEFT", 8, 0)
		item.text:SetText(labelOf(id))
		item:SetScript("OnClick", function()
			list:Hide()
			onPick(id)
		end)
		items[id] = item
	end
	menu:SetScript("OnClick", function()
		local show = not list:IsShown()
		for _, l in ipairs(openLists) do l:Hide() end
		list:SetShown(show)
	end)
	panel:HookScript("OnHide", function() list:Hide() end)
	return menu, list, items
end

-- marks the current choice in a dropdown's list in gold
local function MarkChoice(items, current, labelOf)
	for id, item in pairs(items) do
		local label = labelOf(id)
		item.text:SetText(id == current and ("|cffffd100" .. label .. "|r") or label)
	end
end

-- Themes
Label("Theme", "GameFontNormal", 16, -70)
local function ThemeLabel(id) return T.PRESETS[id].label end
O.widgets.themeMenu, O.widgets.themeList, O.themeItems = Dropdown(16, -90, 200, T.PRESET_ORDER, ThemeLabel, function(id) T.ApplyPreset(id) end)

-- Prompt character: type anything, up to 3 characters
Label("Prompt character", "GameFontNormal", 16, -150)
local promptBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
promptBox:SetSize(46, 20)
promptBox:SetPoint("TOPLEFT", 22, -168)
promptBox:SetAutoFocus(false)
promptBox:SetMaxLetters(3)
local function SavePrompt(self)
	local ok = T.Set("promptText", self:GetText())
	if not ok then self:SetText(T.Get().promptText) end
	self:ClearFocus()
end
promptBox:SetScript("OnEnterPressed", SavePrompt)
promptBox:SetScript("OnEditFocusLost", function(self)
	if self:GetText() ~= T.Get().promptText then SavePrompt(self) end
end)
promptBox:SetScript("OnEscapePressed", function(self)
	self:SetText(T.Get().promptText)
	self:ClearFocus()
end)
O.widgets.promptText = promptBox

-- Cursor style: a dropdown beside the prompt box
Label("Cursor", "GameFontNormal", 130, -150)
local function CursorLabel(id) return T.CURSOR_LABELS[id] end
O.widgets.cursor, O.widgets.cursorList, O.cursorItems = Dropdown(130, -168, 150, T.CURSOR_ORDER, CursorLabel, function(id) T.Set("cursor", id) end)

-- Animation style: a dropdown beside the cursor's (the example above plays it)
Label("Animation", "GameFontNormal", 296, -150)
local function AnimLabel(id) return T.ANIMATION_LABELS[id] end
O.widgets.animations, O.widgets.animationList, O.animationItems = Dropdown(296, -168, 150, T.ANIMATION_ORDER, AnimLabel, function(id)
	T.Set("animations", id)
	demo.t, demo.acc = 0, 1 -- the example plays the new style from the start
end)

-- Colours
Label("Colours", "GameFontNormal", 16, -202)
local colourKeys = { "prompt", "accent", "match", "text", "dim", "bg", "promptBg", "border", "fzfColor" }
for i, key in ipairs(colourKeys) do
	Swatch(key, 16 + ((i - 1) % 3) * 140, -222 - math.floor((i - 1) / 3) * 24)
end

-- Layout
Label("Layout", "GameFontNormal", 16, -300)
Slider("bgAlpha", 16, -322)
Slider("fontSize", 16, -346)
Slider("rows", 16, -370)
Slider("width", 16, -394)
Slider("scale", 16, -418)
Slider("blinkRate", 16, -442)

local fontButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
fontButton:SetSize(150, 22)
fontButton:SetPoint("TOPLEFT", 16, -474)
fontButton:SetScript("OnClick", function()
	local cur, list = T.Get().font, T.FONT_ORDER
	local nextIdx = 1
	for i, f in ipairs(list) do
		if f == cur then nextIdx = i % #list + 1 end
	end
	T.Set("font", list[nextIdx])
end)
O.widgets.font = fontButton

local frameButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
frameButton:SetSize(150, 22)
frameButton:SetPoint("TOPLEFT", 16, -502)
frameButton:SetScript("OnClick", function()
	T.Set("frame", T.Get().frame == "classic" and "flat" or "classic")
end)
O.widgets.frame = frameButton

-- fuzzy finding's glow (Tab+`): its style, a click steps through them (its colour is the last swatch)
local glowButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
glowButton:SetSize(150, 22)
glowButton:SetPoint("TOPLEFT", 16, -530)
glowButton:SetScript("OnClick", function()
	local cur, list = T.Get().fzfGlow, T.FZF_GLOW_ORDER
	local nextIdx = 1
	for i, g in ipairs(list) do
		if g == cur then nextIdx = i % #list + 1 end
	end
	T.Set("fzfGlow", list[nextIdx])
end)
O.widgets.fzfGlowButton = glowButton

-- an on/off setting: a checkbox at y in the right column, its label beside it (`note` greyed after the label)
local function Check(key, y, note)
	local c = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	c:SetSize(24, 24)
	c:SetPoint("TOPLEFT", 190, y)
	c:SetScript("OnClick", function(self) T.Set(key, self:GetChecked() and "on" or "off") end)
	local label = T.FIELDS[key].label .. (note and ("  |cff8a8a8a" .. note .. "|r") or "")
	O.widgets[key] = c
	return Label(label, "GameFontHighlight", 216, y - 5)
end
Check("hints", -472)
Check("syntax", -498, "(@kinds, filters, .commands)")
Check("suggest", -524, "(\"try: ...\")")
O.widgets.autoScanLabel = Check("autoScan", -550)

-- the panel's own actions, on a row of their own below everything else (O.Refresh moves the row under the
-- last row of settings shown)
O.actionRow = O.actionRow or {}
local function Action(x, w, text, onClick)
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetPoint("TOPLEFT", x, -562)
	O.actionRow[#O.actionRow + 1] = { b, x }
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end
Action(16, 130, "Open terminal", function() ns.UI:Open() end)
Action(156, 130, "Reset to defaults", function() T.Reset() end)
-- Sharing the look: Export opens the style string in a copy window (Ctrl+C); Import takes a pasted one
Action(296, 110, "Export style", function() ns:ShowText("Terminal style: paste it to a friend", T.Export(), { compact = true }) end)

local importDialog -- built on first use
local function BuildImportDialog()
	if importDialog then return importDialog end
	local d = CreateFrame("Frame", "TerminalStyleImport", UIParent, "BackdropTemplate")
	d:SetSize(520, 118)
	d:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	d:SetFrameStrata("DIALOG")
	d:SetClampedToScreen(true)
	d:SetBackdrop(FLAT)
	d:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
	d:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
	d:Hide()
	tinsert(UISpecialFrames, "TerminalStyleImport") -- Esc closes it

	local title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Import a Terminal style")
	local hint = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", 14, -30)
	hint:SetText("Paste a style string (Ctrl+V): it starts with " .. T.STYLE_MARK)

	local box = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
	box:SetSize(492, 22)
	box:SetPoint("TOPLEFT", 20, -50)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	d.box = box

	local status = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", 14, 12)
	status:SetPoint("RIGHT", d, "RIGHT", -200, 0)
	status:SetJustifyH("LEFT")
	status:SetWordWrap(false)
	d.status = status

	local function Apply()
		local ok, msg = T.Import(box:GetText())
		status:SetText(msg)
		status:SetTextColor(ok and 0.4 or 1, ok and 1 or 0.4, 0.4)
		if ok then
			box:ClearFocus()
			local shown = d.shownAt
			C_Timer.After(0.8, function() if d:IsShown() and d.shownAt == shown then d:Hide() end end) -- (not one opened since)
		end
	end
	d.Apply = Apply
	box:SetScript("OnEnterPressed", Apply)
	box:SetScript("OnEscapePressed", function() d:Hide() end)

	local apply = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
	apply:SetSize(90, 22)
	apply:SetPoint("BOTTOMRIGHT", -108, 8)
	apply:SetText("Apply")
	apply:SetScript("OnClick", Apply)
	local cancel = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
	cancel:SetSize(90, 22)
	cancel:SetPoint("BOTTOMRIGHT", -12, 8)
	cancel:SetText("Cancel")
	cancel:SetScript("OnClick", function() d:Hide() end)
	importDialog = d
	return d
end

--- Opens the paste dialog (empty, focused).
function O.ImportDialog()
	local d = BuildImportDialog()
	d.box:SetText("")
	d.status:SetText("")
	d.shownAt = (d.shownAt or 0) + 1
	d:Show()
	C_Timer.After(0.05, function() if d:IsShown() then d.box:SetFocus() end end)
	return d
end

Action(416, 110, "Import style", function() O.ImportDialog() end)

----------------------------------------------------------------------
-- Sync controls with the stored theme
----------------------------------------------------------------------

function O.Refresh()
	local t = T.Get()
	O.syncing = true
	for key, w in pairs(O.widgets) do
		local f = T.FIELDS[key]
		if f and f.kind == "number" then
			w:SetValue(t[key])
			w.valueText:SetText(T.Format(key, t[key]))
		elseif f and f.kind == "color" then
			w:SetBackdropColor(T.RGB(t[key] or t.accent))
		end
	end
	O.widgets.font:SetText("Font: " .. t.font:sub(1, 1):upper() .. t.font:sub(2))
	local cur = T.CURSOR_LABELS[t.cursor] and t.cursor or "blinking-line"
	O.widgets.cursor:SetText(CursorLabel(cur))
	MarkChoice(O.cursorItems, cur, CursorLabel)
	O.widgets.frame:SetText("Frame: " .. (t.frame == "classic" and "Classic" or "Flat"))
	O.widgets.fzfGlowButton:SetText("Fuzzy glow: " .. (T.FZF_GLOW_LABELS[t.fzfGlow] or "Breathing"))
	if not O.widgets.promptText:HasFocus() then O.widgets.promptText:SetText(t.promptText) end
	O.widgets.hints:SetChecked(t.hints and true or false)
	O.widgets.autoScan:SetChecked(t.autoScan and true or false)
	O.widgets.syntax:SetChecked(t.syntax and true or false)
	O.widgets.suggest:SetChecked(t.suggest ~= false)
	-- only where the game lets addons open profession windows: WoW Forever doesn't (db.noDirectOpen),
	-- so there each profession is indexed when you open it, and the option would do nothing
	local canScan = ns.db and ns.db.noDirectOpen == false
	O.widgets.autoScan:SetShown(canScan)
	O.widgets.autoScanLabel:SetShown(canScan)
	-- the panel's buttons sit under the last row shown
	for _, b in ipairs(O.actionRow or {}) do
		b[1]:ClearAllPoints()
		b[1]:SetPoint("TOPLEFT", b[2], canScan and -588 or -562)
	end
	local anim = T.ANIMATION_LABELS[t.animations] and t.animations or (t.animations == false and "off" or "smooth")
	O.widgets.animations:SetText(AnimLabel(anim))
	MarkChoice(O.animationItems, anim, AnimLabel)
	local preset = T.PRESETS[t.preset]
	O.widgets.themeMenu:SetText(preset and preset.label or "Custom")
	MarkChoice(O.themeItems, t.preset, ThemeLabel)
	PaintPreview()
	O.syncing = false
end

panel:SetScript("OnShow", O.Refresh)

----------------------------------------------------------------------
-- Registration and opening
----------------------------------------------------------------------

local function Register()
	if O.category or O.legacy then return true end
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Terminal")
		if ok and cat then
			pcall(Settings.RegisterAddOnCategory, cat)
			O.category = cat
			return true
		end
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
		O.legacy = true
		return true
	end
	return false
end

if not Register() then
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function() Register() end)
end

function O.Open()
	Register()
	if O.category and Settings and Settings.OpenToCategory then
		local id = (O.category.GetID and O.category:GetID()) or O.category.ID
		if not (id and pcall(Settings.OpenToCategory, id)) then pcall(Settings.OpenToCategory, "Terminal") end
		return true
	elseif O.legacy and InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		return true
	end
	return false
end

ns:RegisterCommand("options", {
	desc = "Open the Terminal options panel",
	aliases = { "settings", "prefs" },
	run = function()
		if not O.Open() then
			return { "The options panel isn't available in this client. Use .theme and .set instead." }
		end
	end,
})

----------------------------------------------------------------------
-- Searchable: type a theme's name, or "options"
----------------------------------------------------------------------

local function ReopenOnThemes() ns.UI:Open("theme ") end
--- A "Theme: x" row picked: its preset (the row's presetId) applied, then the terminal reopened on the
--- theme list so the new look can be compared straight away. One function for every row.
local function ApplyPresetRow(e)
	T.ApplyPreset(e.presetId)
	C_Timer.After(0, ReopenOnThemes)
end

-- the Terminal Options row: the game opens the settings on Terminal's page (a /run line on the secure button, as the
-- game options rows do), not Terminal's code; .options (a command can't carry a press) still opens it itself
local function OptionsMacro()
	Register()
	local c = O.category
	local id = c and ((c.GetID and c:GetID()) or c.ID)
	if id == nil or not (Settings and Settings.OpenToCategory) then return nil end
	return ("/run Settings.OpenToCategory(%s)"):format(type(id) == "number" and tostring(id) or ("%q"):format(tostring(id)))
end
local OPTIONS_SPEC = { macro = OptionsMacro }

ns:RegisterProvider("terminal", {
	label = "Terminal",
	color = "ffd1ffb2", -- (not the slash commands' green)
	aliases = { "terminal", "theme", "themes" },
	collect = function()
		local out = {
			{
				key = "options",
				name = "Terminal Options",
				icon = "Interface\\Icons\\INV_Misc_Gear_01",
				text = "settings preferences theme colours colors font layout customize prompt",
				secure = OPTIONS_SPEC, isOpen = ns.Never,
				activate = function() O.Open() end,
			},
		}
		for _, id in ipairs(T.PRESET_ORDER) do
			out[#out + 1] = {
				key = "theme:" .. id,
				name = "Theme: " .. T.PRESETS[id].label,
				icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01",
				text = "theme colours colors look skin",
				presetId = id,
				activate = ApplyPresetRow,
			}
		end
		return out
	end,
})
