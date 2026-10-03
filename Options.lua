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
	s:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
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
	local r, g, b = T.RGB(prev)
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
		ns:Print("set it from the terminal instead:  .set " .. key .. " rrggbb")
	end
end

local function Swatch(key, x, y)
	local b = CreateFrame("Button", nil, panel, "BackdropTemplate")
	b:SetSize(18, 18)
	b:SetPoint("TOPLEFT", x, y)
	b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	b:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	b:SetScript("OnClick", function() PickColor(key) end)
	local l = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	l:SetPoint("LEFT", b, "RIGHT", 6, 0)
	l:SetText(T.FIELDS[key].label)
	O.widgets[key] = b
end

----------------------------------------------------------------------
-- Colour example: a small sample beside the theme buttons, drawn with the current colours
----------------------------------------------------------------------

local pv = CreateFrame("Frame", nil, panel, "BackdropTemplate")
pv:SetSize(196, 52)
pv:SetPoint("TOPLEFT", 440, -88)
pv:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
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
	local ar, ag, ab = T.RGB(t.accent)
	pv.band:SetColorTexture(ar, ag, ab, 0.18)
	ns.Fuzzy.matchColor = "|cff" .. t.match
	pv.label:SetText(ns.Fuzzy.Colorize("Heavy Linen Bandage", { [1] = true, [4] = true, [5] = true, [13] = true, [14] = true, [15] = true }))
	pv.label:SetTextColor(T.RGB(t.text))
	pv.detail:SetText("First Aid")
	pv.detail:SetTextColor(T.RGB(t.dim))
end
O.PaintPreview = PaintPreview

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------

Label("Terminal", "GameFontNormalLarge", 16, -16)
Label("Theme and layout of the terminal. Everything here can also be set from the terminal, e.g.  .set accent ff79c6", "GameFontHighlightSmall", 16, -40)

-- Themes: a dropdown
Label("Theme", "GameFontNormal", 16, -70)
local menu = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
menu:SetSize(200, 22)
menu:SetPoint("TOPLEFT", 16, -90)
local arrow = menu:CreateTexture(nil, "OVERLAY")
arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
arrow:SetSize(12, 12)
arrow:SetPoint("RIGHT", -8, 0)
arrow:SetRotation(-math.pi / 2) -- pointing down
O.widgets.themeMenu = menu

local list = CreateFrame("Frame", nil, panel, "BackdropTemplate")
list:SetPoint("TOPLEFT", menu, "BOTTOMLEFT", 0, -2)
list:SetSize(200, #T.PRESET_ORDER * 20 + 8)
list:SetFrameStrata("DIALOG")
list:SetBackdrop({ bgFile = WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
list:SetBackdropColor(0.05, 0.04, 0.03, 0.97)
list:SetBackdropBorderColor(0.69, 0.5, 0.25, 1)
list:Hide()
O.widgets.themeList = list
O.themeItems = {}
for i, id in ipairs(T.PRESET_ORDER) do
	local item = CreateFrame("Button", nil, list)
	item:SetSize(192, 20)
	item:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
	local hl = item:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.82, 0, 0.18)
	item.text = item:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	item.text:SetPoint("LEFT", 8, 0)
	item.text:SetText(T.PRESETS[id].label)
	item:SetScript("OnClick", function()
		list:Hide()
		T.ApplyPreset(id)
	end)
	O.themeItems[id] = item
end
menu:SetScript("OnClick", function() list:SetShown(not list:IsShown()) end)
panel:HookScript("OnHide", function() list:Hide() end)

-- Prompt character: type anything (up to 4 characters) or pick one
Label("Prompt character", "GameFontNormal", 16, -150)
local promptBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
promptBox:SetSize(46, 20)
promptBox:SetPoint("TOPLEFT", 22, -168)
promptBox:SetAutoFocus(false)
promptBox:SetMaxLetters(4)
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

-- characters the game's fonts can draw
O.PROMPT_PICKS = { ">", "$", "#", "%", "\194\187", "::", ">>", "~" }
for i, ch in ipairs(O.PROMPT_PICKS) do
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(34, 22)
	b:SetPoint("TOPLEFT", 76 + (i - 1) * 38, -167)
	b:SetText((ch:gsub("|", "||")))
	b:SetScript("OnClick", function() T.Set("promptText", ch) end)
	O.widgets["prompt_" .. i] = b
end

-- Colours
Label("Colours", "GameFontNormal", 16, -202)
local colourKeys = { "prompt", "accent", "match", "text", "dim", "bg", "promptBg", "border" }
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

local fontButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
fontButton:SetSize(150, 22)
fontButton:SetPoint("TOPLEFT", 16, -446)
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
frameButton:SetPoint("TOPLEFT", 16, -472)
frameButton:SetScript("OnClick", function()
	T.Set("frame", T.Get().frame == "classic" and "flat" or "classic")
end)
O.widgets.frame = frameButton

local hintsCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
hintsCheck:SetSize(24, 24)
hintsCheck:SetPoint("TOPLEFT", 180, -445)
hintsCheck:SetScript("OnClick", function(self) T.Set("hints", self:GetChecked() and "on" or "off") end)
Label(T.FIELDS.hints.label, "GameFontHighlight", 206, -450)
O.widgets.hints = hintsCheck

local scanCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
scanCheck:SetSize(24, 24)
scanCheck:SetPoint("TOPLEFT", 180, -470)
scanCheck:SetScript("OnClick", function(self) T.Set("autoScan", self:GetChecked() and "on" or "off") end)
Label(T.FIELDS.autoScan.label, "GameFontHighlight", 206, -475)
O.widgets.autoScan = scanCheck

local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
open:SetSize(130, 22)
open:SetPoint("TOPLEFT", 16, -508)
open:SetText("Open terminal")
open:SetScript("OnClick", function() ns.UI:Open() end)

local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
reset:SetSize(130, 22)
reset:SetPoint("TOPLEFT", 156, -508)
reset:SetText("Reset to defaults")
reset:SetScript("OnClick", function() T.Reset() end)

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
			w:SetBackdropColor(T.RGB(t[key]))
		end
	end
	O.widgets.font:SetText("Font: " .. t.font:sub(1, 1):upper() .. t.font:sub(2))
	O.widgets.frame:SetText("Frame: " .. (t.frame == "classic" and "Classic" or "Flat"))
	if not O.widgets.promptText:HasFocus() then O.widgets.promptText:SetText(t.promptText) end
	O.widgets.hints:SetChecked(t.hints and true or false)
	O.widgets.autoScan:SetChecked(t.autoScan and true or false)
	local cur = T.PRESETS[t.preset]
	O.widgets.themeMenu:SetText(cur and cur.label or "Custom")
	for id, item in pairs(O.themeItems) do
		local label = T.PRESETS[id].label
		item.text:SetText(id == t.preset and ("|cffffd100" .. label .. "|r") or label)
	end
	for i, ch in ipairs(O.PROMPT_PICKS) do
		local b = O.widgets["prompt_" .. i]
		if ch == t.promptText then b:LockHighlight() else b:UnlockHighlight() end
	end
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

ns:RegisterProvider("terminal", {
	label = "Terminal",
	color = "ff33ff99",
	aliases = { "terminal", "theme", "themes" },
	collect = function()
		local out = {
			{
				key = "options",
				name = "Terminal Options",
				icon = "Interface\\Icons\\INV_Misc_Gear_01",
				text = "settings preferences theme colours colors font layout customize prompt",
				activate = function() O.Open() end,
			},
		}
		for _, id in ipairs(T.PRESET_ORDER) do
			out[#out + 1] = {
				key = "theme:" .. id,
				name = "Theme: " .. T.PRESETS[id].label,
				icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01",
				text = "theme colours colors look skin",
				activate = function()
					T.ApplyPreset(id)
					-- reopen on the theme list so the new look can be compared straight away
					C_Timer.After(0, function() ns.UI:Open("theme ") end)
				end,
			}
		end
		return out
	end,
})
