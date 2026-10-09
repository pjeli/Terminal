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
		v = "0.45.8", when = "in testing",
		items = {
			"Flight paths: \"nearest unlearned flight master\" points you to the closest flight path you haven't learned yet (Enter opens the map on its flight master, Shift+Enter sets a waypoint), and \"unlearned flight paths\" lists them all. Terminal learns which ones you know from the first flight master's map you open on each continent, per character (until then they say \"not checked yet\"); a row's tooltip shows your alts' too. Advanced: @flight is:unlearned sort:nearest.",
			"Guild professions: guild members now show their professions, so \"guild blacksmith\", \"guild skinner\" or \"guild herbalists\" (Advanced: @guild skinner) finds them, offline ones too.",
			"Spells you haven't put anywhere: \"spells not on my bars\" lists the spells you can cast that aren't on any action bar you can see or on a key (a macro casting one counts; passives and auto attacks left out). Advanced: @spell is:unplaced.",
		},
	},
	{
		v = "0.45.0", when = "released October 2026",
		items = {
			"Send every result at once: right-click a result (or Shift+Right) and pick \"All 8 to party\" (guild, raid, say...): \"Mats for Thorium Belt (2): 12x [Thorium Bar], 2x [Heart of Fire]\" or a whole dungeon's loot (\"Weapons from Razorfen Kraul (12): ...\"), with item links. Advanced: mats for thorium belt >>> party (the list becomes one row saying how many go where).",
			"Every class's talents: \"ice barrier\" finds the mage talent even on your warrior (your own class's come first); Enter shows it on Wowhead. Advanced: class:mage.",
			"The footer and the right-click menu say what Enter and Shift+Enter really do on every row (equip, summon, run, track, set waypoint...), in Advanced mode too, and the menu lists each action once.",
			"Alike things work alike: Enter on a mailbox opens the map on it, Ctrl+Enter keeps Terminal open after using an item or toy, a quest in your log isn't listed twice, nearest lists keep each NPC's title, drops and AtlasLoot items show their quality's colour (Shift+Enter links an AtlasLoot item), a chain's \"gathered from\" vein shows on the map.",
			"Action words reach more: \"equip <set>\", \"link <recipe, talent or item>\", \"where is <dungeon>\"; Alt+` keeps them (Advanced: do:use, do:cast...) and names only the lists your results come from (\"use hearthstone\" becomes @item do:use hearthstone).",
			"Simple mode's tips and messages no longer show @ or >>, and both .help texts cover everything; levels, counts, slot names and times are written one way; kind colours and names are clearer.",
			"The .lootlog command is gone: ask \"what dropped\" (Advanced: @drop) to see the loot log.",
			"Quicker typing: chains (\"mats for ...\") and Simple mode's categories answer faster key by key, and type:, slot: and is:equippable no longer wait on item data; other classes' talents take a third of the memory; tidier code throughout.",
			"Fixes: chains never guess: \"mats for core leather belt\" no longer gives another recipe's mats; with no such name it offers the closest, and when several names fit it asks which. Chains also count bars you just bought, take @kinds (@recipe thorium belt > mats) and names like \"Pattern: Linen Belt\". \"upgrades\" no longer calls any +1 stat better than gear with no stats. Sending every result names everything asked for (\"Swords and axes\"), reaches whispers to first and last names, and never sends twice. A tooltip stuck on \"Retrieving item information\" fills in once the item arrives. The loot log keeps two of the same drop apart. The first Alt+` after a /reload opens in Advanced; .zen off leaves bars other addons hide alone. A click on the second line of a long prompt puts the cursor there; Shift+Enter on an equipment set lists its items as links; the mount journal points at the mount in its list.",
		},
	},
	{
		v = "0.44.0", when = "released October 2026",
		items = {
			"Ask in plain words: \"where should i level\", \"what dungeon should i do\", \"where should i fish\" (also \"fishing spots\", \"zones for level 35\"), \"what killed me\", \"what dropped\", \"what did bob get\". Alt+` shows any of them in Advanced form.",
			"Chains: \"mats for thorium belt\" (with how many you have, bank and alts too), \"where to get thorium bar\", \"what uses copper bar\". Enter goes one step further, the footer shows the path, and a row sent to chat says what it is: \"Mats for Thorium Belt: 12x [Thorium Bar]\". Advanced: thorium belt > mats > alts; .chains lists them.",
			"Experience: @xp (Simple mode: \"xp\") shows your level, experience and rested experience, and your alts' as of when you last played them, their rested topped up for the time away.",
			"A loot log: @drop (Simple mode: Loot log) keeps what dropped (green and better) and who got it, with the boss and zone, across sessions.",
			"@combatlog keeps your deaths and what killed you, from the game's Death Recap.",
			"Stored items sent to chat say who holds how many: \"[Linen Cloth] x53: Alt 28 (bank), Bob 20 (bags 12, bank 8)\".",
			"Zones show their level range, and lvl: works on zones and dungeons; fish: finds zones your fishing skill is enough for.",
			"\"upgrades\" weighs the stats your class wants against what you wear, not just item level.",
			"PvP NPCs: \"nearby battlemaster\", \"nearest pvp vendor\" (Advanced: is:battlemaster, is:pvpvendor).",
			"Ctrl+click an item, spell or quest link in chat to look it up in Terminal.",
			".zen hides the menu and bag buttons, XP bar and quest tracker (action bars and minimap stay) to play from Terminal.",
			"Fuzzy mode's glow: breathing, steady, bright, a thin line or off, in any colour (options panel).",
			"Simple mode keeps its footer once you start typing; @loot comes before @drop when picking a kind.",
			"Quicker searches and tidier code; the loot list no longer rebuilds while item names come in.",
			"Fixes: @loot now has AtlasLoot's classic dungeons and WoW Forever's own (it had only Burning Crusade's); Shift+Enter on an NPC only targets it (no map pin); a level said in a question is used; a death could go unrecorded; \"boss loot\" and \"dungeon locations\" are searches again.",
		},
	},
	{
		v = "0.43.0", when = "released October 2026",
		items = {
			"Your guild and friends: @guild and @friend (Simple mode: Guild & friends). Search by class, rank, zone, notes or profession (where the server tells it): \"@guild priest online\", \"@guild blacksmith\", \"@guild in:undercity\", \"@guild officer\". Battle.net friends show the character they're playing. Enter whispers them, Shift+Enter invites them.",
			"@who (Simple mode: \"who priest undercity\"): Enter on the top row asks the server, and the answer comes into the list to search, whisper and invite; lvl: and in: go into the /who.",
			"\"or\" and \"not\": \"sword or axe\", \"rare sword or epic axe\", \"rare ring not boe\" (also without, except). Advanced: | between values, filters or words (q:rare|epic, slot:head|chest, sword|axe), & for both inside one (q:rare&type:sword|q:epic&type:axe), and - or ! for not (-is:soulbound, !q:poor, -cloth).",
			"Your gold: @gold (Simple mode: \"gold\"). With Baganator or Bagnon, every alt's gold too, guild banks and the warband bank, with the total on top. Enter lists it in chat, Shift+Enter puts it in the chat box.",
			"Skill-ups: \"skillup\" (Advanced: is:skillup, also with @profession) lists recipes that still give skill, orange and yellow; is:orange, is:yellow, is:green, is:grey too. Recipes show in their difficulty colour, as of the last time you opened that profession.",
			"Simple mode: Shift+Right opens the selected result's menu (open, use, link or send to chat...), to pick from with Up/Down and Enter.",
			"The Group Finder's pages: \"group browser\" and \"who listing\" open the Dungeons window straight to that tab.",
			"Dungeon and raid entrances are WoW Forever's own, with level ranges: The Drowned City, the Hall of Thanes and the rest are there, and other expansions' are gone.",
			"The \"try:\" suggestions in the empty prompt are made for your character: your class trainer, your professions' skill-ups, a dungeon at your level, where you are, what's in your bags.",
			"Pure fuzzy finding: Tab+` (hold Tab, press `; or .fuzzy). Every list at once, matched by name only, like fzf: no @, no filters, no extras; go through the results with Up/Down. Enter takes the result to Simple mode, Shift+Enter to Advanced. A soft glow round the prompt says it's on; Tab+` again closes it.",
			"Loot sent to chat says where it drops: \"[Thunderfury] dropped by Garr in Molten Core\" (>> guild, the right-click menu's chat lines, Link in chat).",
			"Fixes: typing Advanced syntax in Simple mode could raise an error during a long search; \"upgrades\" inside an or-search kept using your gear and level from the first search; an invisible click area could stay on screen after a window closed Terminal; one failing reagent name could empty a profession's recipe list.",
			"Lighter and quicker: NPC role searches (vendor, repair, trainer), item type and stat filters do less work per row; tidier code throughout.",
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
local Hex = Panel.Hex

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
	Panel.Propagate(self, fn)
end

local function Build()
	if frame then return end
	frame = Panel.Build("TerminalChangelog", CL)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnKeyDown", function(self, key) CL.KeyDown(self, key) end)
	frame:SetScript("OnMouseWheel", function(_, delta) CL.ScrollTo(offset - delta * STEP) end)

	title, versionText = Panel.Header(frame)

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

	footer = Panel.Footer(frame, 10, "Up/Down, PgUp/PgDn, mouse wheel scroll  ·  Esc or ` close")
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

function CL.IsShown() return Panel.Shown(frame) end
function CL.Parts() return scroll, content, body end -- (tests)

function CL.Open()
	if not Panel.CanOpen("The changelog takes the arrow keys while open, which the game doesn't allow in combat.") then return false end
	Build()
	Layout()
	Panel.Opening(CL) -- (straight in, where the terminal was: it and the other panels go)
	frame:Show()
	CL.ScrollTo(0) -- the newest at the top
	return true
end

function CL.Close(why)
	Panel.Close(frame, why, "Changelog")
end

ns:RegisterCommand("changelog", {
	desc = "What changed in Terminal, newest first (scroll back through the last few versions; Esc closes)",
	aliases = { "changes", "news", "whatsnew" },
	run = function() CL.Open() end,
})
