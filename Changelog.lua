local ns = select(2, ...)

-- .changelog: what changed, newest first, in a window where the terminal sits (like .btop).
-- Arrows, Page Up/Down, Home/End and the mouse wheel scroll; Esc or ` closes. Only those keys are
-- taken: any other key still reaches the game. Choosing which keys pass on isn't allowed in combat,
-- so it doesn't open in combat and closes when combat starts.
--
-- Kept up to date with every change: the top entry is the version in testing (its v is the TOC's
-- version); a release gets its date. The newest four versions are kept.

local CL = {}
ns.Changelog = CL

CL.LOG = {
	{
		v = "0.36.0", when = "released October 2026",
		items = {
			"@spell: your spellbook in search. Enter opens the book on the spell's category and page and highlights it; Shift+Enter casts it.",
			"@gear: the equipment in your bags and on you, with its slot, item level and In Bag / Equipped. Shift+Enter equips it.",
			"@cvar: the game's console settings with their value and default. Enter fills in /console to change one, Shift+Enter its default.",
			"stat: on consumables (what an elixir, potion or food gives) and on recipes (what a craft makes, what an enchant gives): @consumable stat:str, @recipe stat:stam slot:bracers.",
			"slot: takes everyday words: bracers, boots, gloves, cloak, helm, ring, 2h...",
			".btop: your addons' CPU and memory, live and searchable.",
			".snake: Snake, for fun.",
			".changelog: this window.",
			"Fixes: the history keeps the gear you equipped, not the piece it replaced; a window opened by the press still gets its highlight; macros stay within the game's 255 characters.",
			"Smoother: @cvar updates just the setting that changed, stat: and slot: filters do less work per row, and a long frame no longer crashes the snake into a wall.",
		},
	},
	{
		v = "0.33.1", when = "released October 2026",
		items = {
			"Search filters across kinds: lvl: ilvl: q: stat: slot: type: in: on: count: faction: trainer: is: (Tab completes values; .filters lists them).",
			"The prompt colours what it understands: @kinds, filters, .commands, /slash commands and plain words.",
			"Long prompts wrap onto more lines instead of scrolling sideways.",
			"A paste goes straight back to the coloured prompt, with a short reminder to press Ctrl+V again.",
			"AtlasLoot's index is kept between sessions; profession pages show the items they craft (no test items).",
			"@questie searches quest objectives; Questie's lists are built in the background with no CPU spike at login.",
			"Fixes: skills the game lists twice show once; no login-indexing checkbox where the game won't allow it.",
		},
	},
	{
		v = "0.30.3", when = "released October 2026",
		items = {
			"@keybind: every bindable action. Enter opens Options > Keybindings on it; a row starts Quick Keybind Mode.",
			"Animations play on every open, not only the first.",
			"Recipes are indexed per character (namesakes no longer share one index).",
			"Big lists (your alts and banks, Questie's quests and NPCs) are offered by a row on top when only they have a match; Tab adds the @kind.",
			"Those offer rows stay out of the history.",
		},
	},
	{
		v = "0.29.3", when = "released September 2026",
		items = {
			"Animation styles: Smooth, Snappy, Floaty, Cascade, Drop Down or Off, previewed in the options.",
			"Much less CPU while idle and while other addons spread taint; .mem shows Terminal's CPU.",
			"Shift+Enter uses items; big searches are spread over frames; lists are built ahead of use.",
			"MIT license.",
		},
	},
}

local Theme = ns.Theme
local W_MIN, H = 520, 420
local STEP = 40 -- pixels a line of scrolling moves

local frame, title, versionText, box, scroll, content, body, thumb, footer
local offset = 0

local function Text(parent, size, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(Theme.fonts.input)
	if size then
		local font, _, flags = fs:GetFont()
		if font then fs:SetFont(font, size, flags) end
	end
	fs:SetJustifyH(justify or "LEFT")
	return fs
end

local function Hex(c) return (tostring(c or "ffffff"):gsub("^|c", ""):gsub("^ff(%x%x%x%x%x%x)$", "%1")) end

--- The whole log as one text with colour codes: each version's number in the accent colour, when it
--- came dimmed, then its changes.
function CL.Text()
	local t = Theme.Get()
	local acc, dim, txt = Hex(t.accent), Hex(t.dim), Hex(t.text)
	local out = {}
	for i, entry in ipairs(CL.LOG) do
		if i > 1 then out[#out + 1] = "" end
		out[#out + 1] = ("|cff%s%s|r   |cff%s%s|r"):format(acc, entry.v, dim, entry.when or "")
		for _, item in ipairs(entry.items) do
			out[#out + 1] = ("|cff%s-|r |cff%s%s|r"):format(acc, txt, (item:gsub("|", "||")))
		end
	end
	return table.concat(out, "\n")
end

local function MaxOffset()
	if not (content and scroll) then return 0 end
	return math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
end
CL.MaxOffset = MaxOffset

--- Scroll to `to` pixels from the top (kept inside the text), and move the thumb.
function CL.ScrollTo(to)
	offset = math.max(0, math.min(MaxOffset(), to or 0))
	if scroll then scroll:SetVerticalScroll(offset) end
	if thumb and scroll then
		local viewH, max = scroll:GetHeight() or 1, MaxOffset()
		local total = viewH + max
		local h = math.max(16, viewH * viewH / math.max(1, total))
		thumb:SetHeight(h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", box, "TOPRIGHT", -3, -4 - (max > 0 and (viewH - h) * offset / max or 0))
		thumb:SetShown(max > 0)
	end
end
function CL.Offset() return offset end

local KEYS = {
	UP = function() CL.ScrollTo(offset - STEP) end,
	DOWN = function() CL.ScrollTo(offset + STEP) end,
	PAGEUP = function() CL.ScrollTo(offset - (scroll:GetHeight() or 200) + STEP) end,
	PAGEDOWN = function() CL.ScrollTo(offset + (scroll:GetHeight() or 200) - STEP) end,
	HOME = function() CL.ScrollTo(0) end,
	END = function() CL.ScrollTo(MaxOffset()) end,
	ESCAPE = function() CL.Close() end,
	["`"] = function() CL.Close() end,
}

--- Its keys are kept; any other key goes on to the game.
function CL.KeyDown(self, key)
	local fn = KEYS[key]
	if fn then fn() end
	if self and self.SetPropagateKeyboardInput and not InCombatLockdown() then
		pcall(self.SetPropagateKeyboardInput, self, not fn)
	end
end

local function Build()
	if frame then return end
	frame = CreateFrame("Frame", "TerminalChangelog", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:Hide()
	frame:EnableKeyboard(true)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnKeyDown", function(self, key) CL.KeyDown(self, key) end)
	frame:SetScript("OnMouseWheel", function(_, delta) CL.ScrollTo(offset - delta * STEP) end)
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:SetScript("OnEvent", function() CL.Close("combat") end)

	title = Text(frame, 13)
	title:SetPoint("TOPLEFT", 12, -10)
	versionText = Text(frame, 12, "RIGHT")
	versionText:SetPoint("TOPRIGHT", -12, -10)

	box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	box:SetPoint("TOPLEFT", 10, -32)
	box:SetPoint("BOTTOMRIGHT", -10, 30)
	box:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

	scroll = CreateFrame("ScrollFrame", nil, box)
	scroll:SetPoint("TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", -14, 8)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	body = Text(content, 12)
	body:SetPoint("TOPLEFT")
	body:SetWordWrap(true)
	body:SetJustifyV("TOP")
	if body.SetSpacing then body:SetSpacing(3) end

	thumb = box:CreateTexture(nil, "ARTWORK")
	thumb:SetColorTexture(1, 1, 1, 1)
	thumb:SetWidth(3)

	footer = Text(frame, 11)
	footer:SetPoint("BOTTOMLEFT", 12, 10)
	footer:SetText("Up/Down, PgUp/PgDn, mouse wheel scroll  ·  Esc or ` close")
	CL.frame = frame
end

local function Layout()
	local t = Theme.Get()
	local W = math.max(W_MIN, t.width or 640)
	frame:SetSize(W, H)
	frame:SetScale(t.scale or 1)
	frame:ClearAllPoints()
	local term = _G.TerminalFrame
	if term then frame:SetPoint("TOP", term, "TOP", 0, 0) else frame:SetPoint("CENTER") end
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	local r, g, b = Theme.RGB(t.bg)
	frame:SetBackdropColor(r, g, b, math.max(0.9, t.bgAlpha or 0.95))
	local br, bg, bb = Theme.RGB(t.border)
	frame:SetBackdropBorderColor(br, bg, bb, 1)
	box:SetBackdropBorderColor(br, bg, bb, 1)
	local ar, ag, ab = Theme.RGB(t.accent)
	thumb:SetColorTexture(ar, ag, ab, 0.8)
	local dr, dg, db = Theme.RGB(t.dim)
	footer:SetTextColor(dr, dg, db)
	versionText:SetTextColor(dr, dg, db)
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Terminal", "Version")
	title:SetText(Theme.FixColors(("|cff%schangelog|r"):format(Hex(t.accent))))
	versionText:SetText("Terminal " .. tostring(version or CL.LOG[1].v))
	-- the text wraps at the box's width; the scroll child is as tall as it
	local width = W - 20 - 24
	body:SetWidth(width)
	body:SetText(Theme.FixColors(CL.Text()))
	content:SetWidth(width)
	local h = body:GetStringHeight()
	content:SetHeight(math.max(1, (type(h) == "number" and h or 0) + 6))
end

function CL.IsShown() return frame and frame:IsShown() or false end
function CL.Parts() return scroll, content, body end -- (tests)

function CL.Open()
	if InCombatLockdown() then
		ns:Print("The changelog takes the arrow keys while open, which the game doesn't allow in combat.")
		return false
	end
	Build()
	Layout()
	-- straight in, where the terminal was (its closing animation would play under it)
	if ns.UI and ns.UI.HideNow then ns.UI:HideNow() end
	if ns.Btop and ns.Btop.IsShown and ns.Btop.IsShown() then ns.Btop.Close() end
	if ns.Snake and ns.Snake.IsShown and ns.Snake.IsShown() then ns.Snake.Close() end
	frame:Show()
	CL.ScrollTo(0) -- the newest at the top
	return true
end

function CL.Close(why)
	if not frame or not frame:IsShown() then return end
	frame:Hide()
	if why == "combat" then ns:Print("Changelog closed: combat started.") end
end

ns:RegisterCommand("changelog", {
	desc = "What changed in Terminal, newest first (scroll back through the last few versions; Esc closes)",
	aliases = { "changes", "news", "whatsnew" },
	run = function() CL.Open() end,
})
