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
		v = "0.41.10", when = "in testing",
		items = {
			"Simple mode (the default): type in plain words and pick where it was found (Bags, Quests, NPCs, Emotes...). Everything is searched, no @ needed. .advanced switches to the full command line, .simple comes back.",
			"Alt+` in Simple mode turns what you typed into Advanced mode's command line (\"nearest innkeeper\" becomes @npc is:innkeeper sort:nearest) for that one time; Simple again once it closes. Pressed with Terminal closed, it opens in Advanced.",
			"Plain words do the work: \"stamina food\", \"attack power food\", \"rare sword\", \"use hearthstone\", \"nearest innkeeper\", \"vendor goldshire\", \"mining trainer in org\".",
			"Opens as just the prompt, with a suggestion to try (Shift+Right takes it; an option turns them off). Down brings back your last search (Simple) or your recent picks (Advanced); Up, your last command.",
			"NPCs show their title (Mining Trainer, Banker) and, when selected, an arrow pointing the way to them.",
			"Advanced: sort:nearest puts NPCs closest first; near:500 keeps those within 500 yards; in:goldshire and in:ratchet know the towns, as Simple mode does.",
			"Advanced: typing @ lists every kind, and a filter like stat: or q: its values, to pick from: Tab and Shift+Tab go down and up, Enter writes it. Anything picked into the prompt leaves a space for the next word.",
			"trainer: finds every trainer of a kind, whatever their title (Miner, Herbalist, Fisherman, riding instructors); trainer:class means your own class, trainer:mine the mining trainers.",
			"@panel Legacy opens WoW Forever's Legacy window (also found as \"challenges\"), even with its button moved off the bar.",
			"Right-click any row for everything it can do.",
			"Search: initials (scb, zg), shorthand (brd, sw, org), close spellings (hearhtstone), and emotes as slash commands (/dance).",
			"AtlasLoot Forever: WoW Forever's own items (Snake Eye Kaleidoscope...) show up under Loot: their names come from the server, and Terminal keeps asking until they do.",
			"QuestieDB alone is enough for Questie's quests and NPCs; Questie itself isn't needed.",
			"Lighter and steadier: NPC distances and roles are worked out once, the right-click menu closes when combat starts, and the prompt no longer covers its bottom border.",
		},
	},
	{
		v = "0.39.5", when = "released October 2026",
		items = {
			"Fixes from a review pass: a pasted style string changes only the look (never your width, rows or settings); the copy bar never cuts off a style string's last line; a reopened Import style dialog stays open; reading the toy and pet journals never changes their filters when a read fails.",
			"Lighter: WoWamp redraws its time once a second instead of every frame and idles with the visualizer off; earned achievements no longer re-read the whole list; sells: looks its sellers up once per search.",
		},
	},
	{
		v = "0.39.4", when = "released October 2026",
		items = {
			"New kinds: @toy (Enter uses it), @pet (Enter summons it) and @title (Enter wears it; a No title row too). Shift+Enter shows a toy or pet in the Collections journal.",
			"@achievement lists the ones you haven't earned too, greyed with their progress (3/10); plain searches still show only what you've earned.",
			"New filters: is:quest, is:soulbound and is:boe on items; is:passive and is:ready (off cooldown) on spells; is:capped on currencies; standing:honored+ on reputations; is:done / is:todo on achievements; @npc sells:<item> (vendors from Questie, sells:copper_rod).",
			"Fix: items whose names the game hadn't loaded yet when you logged in (Rumsey Rum, Ice Cold Milk...) were missing from search, as Items and Consumables; they're listed as soon as their names come in. One item the game answers oddly for can no longer hide all the others.",
			"@addon: Shift+Enter turns an addon on or off for this character (.reload to apply), and shows its real state: on WoW Forever characters have surnames, and the first name alone pointed at another character's AddOn list; the change is saved, so the reload keeps it; an addon's options page has a row of its own. @npc: Shift+Enter targets the NPC.",
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
