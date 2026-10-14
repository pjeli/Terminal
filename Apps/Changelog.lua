local ns = select(2, ...)
local L = ns.L

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
		v = "0.50.2", when = "in testing",
		items = {
			"With Attune: @attune lists its attunements, dungeon quest lines, keys and class quests (yours, for your faction), each with how far along you are and your next step, your alts' progress in the tooltip. Enter opens Attune on it and points at it, Shift+Enter puts it in the chat box. Simple mode: \"my attunements\", \"raid attunements\", \"my keys\", \"class quests\", \"attunements to do\", \"am i attuned to mc\". The steps, first to last: \"how do i get into molten core\", \"steps for the deadmines\" (Advanced: <attunement> > steps; Enter on a step opens Attune on its box), and the attunements a quest is part of (<quest> > attunement). Advanced: is:raid, is:dungeon, is:key, is:class, is:done, is:todo, class:<class>.",
			"Reaching for Questie, AtlasLoot or Attune without it installed (@questie, @npc, @loot, @attune, > chain, > steps, reward:, sells:, \"nearest innkeeper\", \"molten core loot\", \"how do i get into mc\") adds a line to the footer saying which addon to add for it.",
			"Alt+click a link in chat to look it up in Terminal (it was Ctrl+click, which is also the game's dressing room: both opened at once). Ctrl+click is the dressing room's alone again.",
		},
	},
	{
		v = "0.50.0", when = "released October 2026",
		items = {
			"The calendar: @calendar (Simple mode: \"holidays\", \"what's on this week\", \"today\", \"next darkmoon faire\", \"my invites\", \"guild events\") lists what's on from today to the end of next month, each with when it starts and ends to the minute: holidays such as the Darkmoon Faire or the Stranglethorn Fishing Extravaganza, your, your guild's and your communities' events with your answer, invitations you haven't answered yet, raid resets. Enter opens the calendar on the event, Shift+Enter puts it in the chat box. Advanced: is:holiday, is:invite, when:week.",
			"Quests by their reward: \"outlaw sabre quest\" or \"quest for outlaw sabre\" lists the quest that rewards it, for your faction (Advanced: @questie reward:outlaw_sabre). And the quests before one: \"quest chain for the missing diplomat\" (Advanced: <quest> > chain) lists them first to last.",
			"Trainers by what they teach, the nearest ones without saying \"nearest\": \"enchanting trainer\", \"mage trainer\", \"hunter pet trainer\", \"demon trainer\" (\"pet trainer\" alone is your class's), several professions at once; the Journeyman Enchanter, the Herbalists and the Master Mages are in. A place said keeps to it: \"mining trainer in org\".",
			"\"recipes to learn\" keeps to the ones your skill allows now, and the footer says how many more need more skill; \"all recipes to learn\" or \"recipes i'm missing\" lists every one.",
			"Opening a profession window no longer says \"Indexed Blacksmithing: 120 known recipes\" in chat (debug mode still does).",
			"A full review, the keys and clicks: Enter does what the footer says after a Shift+Enter or a click set it up; a window opened while lists still load closes Terminal and is pointed at; AltGr letters type (Polish, Czech, Hungarian layouts); a key you bound to Terminal closes it too; F1, .changelog and .atop catch the mouse and close when Terminal opens.",
			"Searches: \"not\" and \"-\" work with any language's letters; \"cloak without stamina\", \"reset my keybinds\", \"where is the ah\" and \"how do i get to orgrimmar\" are searches again, not other questions; \"what does my group need\" asks the group; \"leveling plan\" plans all your professions; sqrt(2), max(3, 5) and the like add up; items \"of the Monkey\" and \"of the Bear\" each keep their own stats.",
			"Your things: worn bows, wands and relics, and keys on the keyring, are found; \"what killed me\" answers with this character's deaths only; a new sale's news stays until its own mail comes; @mail, @drop and @combatlog say why when they're empty; camp objects and talents open right with their window already up; Questie's NPCs open and get pinned at the spawn the row measures; Quick Keybind Mode starts from the Keybindings page's own button.",
		},
	},
	{
		v = "0.49.0", when = "released October 2026",
		items = {
			"Raid lockouts: @lockout (Simple mode: \"my lockouts\", \"raid lockouts\", \"am i saved\") lists what each of your characters is saved to, how many bosses are down and when it resets; Enter names the bosses, Shift+Enter links your own in chat.",
			"Profession levelling plans: \"blacksmithing plan\" or \"level blacksmithing\" (Advanced: @recipe blacksmithing sort:plan) lists your recipes that still give skill by how many times your materials make each, from bags and bank and with your alts; vendor materials don't count, and the footer says about how many points they'd give.",
			"Simple mode's categories are named for what you'd do: Items (your bags, bank and alts together), Windows, Settings, Commands, Dungeon loot and Recent (your drops and deaths). Each says what it holds, and something named exactly what you typed comes first, ready to open.",
			"Your auctions: @auction (Simple mode: \"my auctions\", \"what am i selling\") lists what each character has on the auction house as Terminal saw it posted, with its price and time left, then the auction house's news (sold, won, outbid, expired), each item with its own icon, quality and count. The news moved there from @mail; \"incoming mail\" still shows it.",
			"Mail carrying an item is drawn in that item's colour, with its icon.",
			"An auction that comes back to you by mail (it failed, expired or was cancelled) no longer counts in @stored as still on the auction house.",
			"Legacy Challenges opens the Legacy window on its Challenges page; Legacy Rewards and Legacy Tree open the window and point at their tab, also when it's already open on another page (the game gives Terminal no clean way to switch to those two).",
			".zen hides the frame-rate counter too, and brings it back as Terminal closes.",
			"Up on an empty prompt brings back a line you ran; Down then goes into its results like any search, Up from the top result goes further back, and Shift+Left steps back toward the empty prompt.",
			"Listed on CurseForge for WoW Forever only (0.48.0 also showed up for retail).",
			"A full review's fixes: currencies under a folded header are listed; a profession window's search or filters no longer shrink its saved recipes; load-on-demand addons say so instead of asking for a reload; nearest mailbox works right after login; clicks and the right-click menu do what Enter does (>> party sends from the click, not on hover); a fight closing the keys window (F1) brings your search back afterwards.",
			"Searches are quicker once you've picked things before, and your alts' items are counted again in the background rather than as you type. Row details, and the games' and windows' key hints, read the same way everywhere; .debug reset lets Terminal try again what the game once blocked.",
		},
	},
	{
		v = "0.48.0", when = "released October 2026",
		items = {
			"Terminal speaks German, French, Spanish, Russian and Chinese (simplified), going by your game's language. In those languages Simple mode also understands the game's own words (qualities, slots, weapon kinds, roles, standings, classes, professions) and the main questions in your words: \"nearest ...\", \"mats for ...\", \"where to get ...\", \"where to learn ...\", \"where is ...\". English always works too. Help translate on Terminal's CurseForge page (Localization).",
			"Party quests: \"party quests\" (Advanced: @group quests) shows who in your party is on each of your quests; Enter shares one, \"quests to share\" lists the ones someone lacks, and >>> party says it in one line. Where the game doesn't say who's on what, Terminal learns it from sharing.",
			"Mail on its way: what you send anyone shows in @mail for the hour it takes to arrive (\"sent mail\"), and the auction house's news shows before you reach a mailbox (\"incoming mail\"): sold (with its price and when the gold is due), won, outbid and expired.",
			"Typing a filter offers only the values that make sense for the lists you named: \"@questlog is:\" offers quest states, not online or equippable.",
			"Terminal's games and radio are an addon of their own now (Terminal Extras, in its own folder), loaded the first time you use one, so Terminal alone takes less memory. Keep it switched on in your AddOn list to play.",
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

	footer = Panel.Footer(frame, 10, L["Up/Down, PgUp/PgDn, mouse wheel scroll"] .. "  ·  " .. Panel.CLOSE)
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
	title:SetText(Theme.FixColors(("|cff%s%s|r"):format(Hex(t.accent), L["changelog"])))
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
	if not Panel.CanOpen(L["The changelog takes the arrow keys while open, which the game doesn't allow in combat."]) then return false end
	Build()
	Layout()
	Panel.Opening(CL) -- (straight in, where the terminal was: it and the other panels go)
	frame:Show()
	CL.ScrollTo(0) -- the newest at the top
	return true
end

function CL.Close(why)
	Panel.Close(frame, why, L["Changelog"])
end

ns:RegisterCommand("changelog", {
	desc = L["What changed in Terminal, newest first (scroll back through the last few versions; Esc closes)"],
	aliases = { "changes", "news", "whatsnew" },
	run = function() CL.Open() end,
})
