local ns = select(2, ...)

-- .changelog: what changed, newest first, in a window where the terminal sits (like .atop).
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
		v = "0.37.4", when = "released October 2026",
		items = {
			"Share your look: Export style on the options page (or .style) gives it as one line to copy, TERM1:..., short enough for a chat message; Import style (or .style TERM1:...) applies a pasted one. Colours, opacity, frame, font, cursor, animation and prompt text travel; width, rows and scale stay yours.",
			"The style string shows in the slim copy bar (as a Wowhead link does): a narrow bar in the middle of the screen, the text wrapped onto a few lines and all selected; it goes once Ctrl+C has copied it.",
			"Opacity can be set to the exact hundredth (presets' 0.96 and 0.97 no longer round to 0.95).",
		},
	},
	{
		v = "0.37.0", when = "released October 2026",
		items = {
			"Review pass: every result that opens a game window now goes through the game's own key or a macro the game presses (the panels, slash commands, options, the addon list); a recipe picked from Terminal is pointed at, never clicked, so the window's own Create button stays the game's.",
			"stat:mp5 works; filters with spaces take _ (in:elwynn_forest); lvl:30-20 means 20-30; >>party without the space sends too; r is raid.",
			"Faster: arrow keys and hovering repaint only what changed, bare @kind searches allocate nothing per row, zone filters cache area names, .atop costs nothing while its bars rest, Tab completion is safe on Korean and Cyrillic names.",
			"Quest text that the game keeps secret no longer breaks the quest list; @equipment is the equipment sets, @settings the game options.",
			".forget also clears the history; .bind says so in combat; a filter that errors is traced in .debug log instead of silently hiding rows.",
		},
	},
	{
		v = "0.36.13", when = "released October 2026",
		items = {
			"@questie >> party (or guild...) sends the quest as a Questie link, clickable with its tooltip for anyone with Questie, instead of just its name. Quests in your log the game won't link go the same way.",
			".btop is now .atop (AddOn top).",
			"Fix: opening the terminal no longer opens a profession window (Enchanting) when a profession is the selected result.",
			"Herbalism's recipes and camp objects (Incense Candle) open its Gardening window. Terminal learns the spell you open a profession with, and otherwise finds it among the profession's own spells.",
			"@camp: Shift+Enter uses the camp object from your bags, or opens its profession and makes it when you have none.",
			"Achievements: Shift+Enter links one in chat; their colour is now rose, apart from Camp's orange.",
			"Professions: Shift+Enter links the profession (all your recipes) in chat; Enter opens its window.",
			"Send a result to chat: end a search with >> party, guild, raid, say, yell, officer, instance, whisper <name> or a channel number. Items, spells, achievements, recipes and quests go as links, NPCs as a map pin, professions as a link to all your recipes.",
			"Shift+Right at the end of the prompt writes the selected result into it (@npc Thrall), to build on: add >> guild to send it.",
		},
	},
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
}

local Theme = ns.Theme
local Panel = ns.Panel
local W_MIN, H = 520, 420
local STEP = 40 -- pixels a line of scrolling moves

local frame, title, versionText, box, scroll, content, body, thumb, footer
local offset = 0

local Text = Panel.Text

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
	frame = Panel.Build("TerminalChangelog", CL)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnKeyDown", function(self, key) CL.KeyDown(self, key) end)
	frame:SetScript("OnMouseWheel", function(_, delta) CL.ScrollTo(offset - delta * STEP) end)

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
	body:SetWordWrap(true) -- (the one text that wraps)
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
	local W = math.max(W_MIN, Theme.Get().width or 640)
	local t = Panel.Layout(frame, W, H)
	local br, bg, bb = Theme.RGB(t.border)
	box:SetBackdropBorderColor(br, bg, bb, 1)
	local ar, ag, ab = Theme.RGB(t.accent)
	thumb:SetColorTexture(ar, ag, ab, 0.8)
	local dr, dg, db = Theme.RGB(t.dim)
	footer:SetTextColor(dr, dg, db)
	versionText:SetTextColor(dr, dg, db)
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ns.name, "Version")
	title:SetText(Theme.FixColors(("|cff%schangelog|r"):format(Hex(t.accent))))
	versionText:SetText(ns.name .. " " .. tostring(version or CL.LOG[1].v))
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
	Panel.Opening(CL) -- (straight in, where the terminal was: it and the other panels go)
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
