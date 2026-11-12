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
		v = "1.4.16", when = "in testing",
		items = {
			"Item sets without OneForAll: with AtlasLoot alone, @itemset lists the sets, their pieces, where each drops and the set bonuses; Enter opens AtlasLoot on the set, and \"my class sets\" lists your class's.",
			"Library Books without OneForAll: with Questie (or QuestieDB) alone, @book lists every book, where it lies and how far along you are.",
			"\"library book rewards\" lists each reward as an item you can hover, under its tier; without OneForAll, Questie's reward quests and what they give.",
			".integrations lists only the addons Terminal found, with what each gives.",
			"Legacy rewards: Enter finds the innkeeper who gives them on a game client in any language.",
			"A misspelled long word finds its close spellings in under half the time.",
			"No hitch on a hunter's first \"pet food\" question or a first \"what does <token> give\": both lists are read ahead while the game is idle.",
		},
	},
	{
		v = "1.4.0", when = "released November 2026",
		items = {
			"Quest suggestions only list quests you can actually take (QuestieDB's prerequisites, either-or quests, level caps, breadcrumbs); \"why can't i take <quest>\" says what stops you, and \"what does <quest> unlock\" what comes after it.",
			"WoW Forever's Legacy: \"which legacy points am i missing\", \"what gives legacy points for mage\", \"legacy rewards\" (and where to claim them), \"legacy perks\"; and PvP ranks: \"my pvp rank\", \"what does pvp rank 11 unlock\".",
			"Enchants (with AtlasLoot or OneForAll): @enchant lists every enchant with its slot, what it gives and how you get it; \"enchants for bracers\", \"enchants for my weapon\", \"agility enchants\", \"enchants i can make\"; Enter opens its recipe or where to learn it.",
			"\"Where to get\" knows more: the clams, sacks and boxes an item comes out of, who to skin, where to fish, what to disenchant (with OneForAll); and \"what does <token> give\" lists what a token, libram or sack turns into (AtlasLoot).",
			"Hunters: \"what can my pet eat\", \"nearest pet food vendor\". Loot rows' tooltips say the boss's level and type (and its drop rate from AtlasLoot); \"summoned bosses in blackrock spire\". Currency tooltips add your alts' amounts (Syndicator).",
			"Fixed: on WoW Forever, Enter on an achievement or a Legacy challenge opens the Legacy window's Challenges by the achievement button, without leaving the Legacy window tainted.",
			"Many fixes from three reviews: enchants from both addons together and in every language, the Legacy points kept up to date, \"feed pet\" finds the spell again.",
		},
	},
	{
		v = "1.3.0", when = "released November 2026",
		items = {
			"Terminal: Share: friends can share where they are (.share settings location on; off by default; .share <group> location on or off for one group, which wins): each is a class-coloured dot on your world map and a row in your searches, \"where are my friends\"; Enter or a click puts a waypoint on them.",
			"Terminal: Share: guild members and friends who share where they are with OpenMap show too, dots and rows alike (.share settings openmap on; off by default).",
			"The empty prompt's suggestions know your professions (the nearest anvil or forge for blacksmiths and miners, your trainer when it's time to train) and suggest Terminal's own settings you haven't tried (.zen, .ask guild on, .share settings openmap on...).",
			"A footer too long for its line (\"recipes i can learn now\") wraps onto more lines, the terminal growing downwards, instead of being cut off.",
			"When someone asks Terminal (!t) in a chat it doesn't answer in yet, it says plainly what to type to turn it on (.ask group on).",
			"Fixed: with .zen on, your target's highlight on the party and raid frames no longer shows through the faded interface; with Shift+` bound to Terminal, opening it on a kept search no longer types a ~.",
			"Many fixes from three reviews: friends' places and dots, OpenMap players' places in a big guild, suggestions typed with their note, the footer and .zen.",
		},
	},
	{
		v = "1.2.0", when = "released November 2026",
		items = {
			"With TomTom (or an arrow addon taking its waypoints): Enter (\"show via TomTom\") and Shift+Enter send their waypoints to TomTom's arrow; .set waypoints map, tomtom or both, or Options.",
			"Terminal's own settings are searchable: \"terminal settings\" (or .set) lists each with its value, \"bigger font\" or \"cursor\" finds one; Enter changes it, Shift+Enter puts its default back.",
			"Right-click a loot row and pick Find sources: the search goes on to where to get it (who drops, sells or makes it); Shift+Left goes back.",
			"Fixed: after Terminal showed an item in the game's own bags, food and drink in them could fail to work until a /reload; the game now opens your bags itself.",
			"With .zen off, a click outside Terminal leaves it open but out of focus: your keys go to the game until you click it or press its key again.",
			"Keep your session (on by default, .set keepSession): Terminal opens again on the search you left, with its results, and your tabs, after a /reload too; the empty prompt's tips mention Ctrl+T for another tab.",
			"The addon options panel says that more settings are in Terminal itself: terminal settings or .set.",
			"\"what layer am i on\" or \"my layer\" (@layer): the layer the creatures you mouse over or target are on.",
			"Many fixes from a release review: showing items in your bags (in a fight, with Ctrl+Enter, with any bag addon), settings, focus and tabs.",
		},
	},
}

local Theme = ns.Theme
local Panel = ns.Panel
local W_MIN, H = 520, 420
local STEP = 40 -- pixels a line of scrolling moves

local frame, title, versionText, box, scroll, content, body, thumb, footer

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

local sc -- (the scrolling box: Panel.Scroller)

--- Scroll to `to` pixels from the top (kept inside the text), and move the thumb.
function CL.ScrollTo(to) if sc then sc.ScrollTo(to) end end
function CL.Offset() return sc and sc.offset or 0 end

local KEYS -- (the scroller's, and Esc / ` close: made with it)

--- Its keys are kept; any other key goes on to the game.
function CL.KeyDown(self, key)
	local fn = KEYS and KEYS[ns.TickAs(key)] -- (the terminal's key, whichever: 0.65.1)
	if fn then fn() end
	Panel.Propagate(self, fn)
end

local function Build()
	if frame then return end
	frame = Panel.Build("TerminalChangelog", CL)
	frame:SetScript("OnKeyDown", function(self, key) CL.KeyDown(self, key) end)

	title, versionText = Panel.Header(frame)

	sc = Panel.Scroller(frame, -32, STEP)
	box, scroll, content, thumb = sc.box, sc.scroll, sc.content, sc.thumb
	KEYS = Panel.Keys(sc, { ESCAPE = function() CL.Close() end, ["`"] = function() CL.Close() end })
	body = Text(content, 12)
	body:SetPoint("TOPLEFT")
	body:SetWordWrap(true) -- (the one text that wraps)
	body:SetJustifyV("TOP")
	if body.SetSpacing then body:SetSpacing(3) end

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

--- After an update: the first login on a new version says so, once, in one line: how many things the version's entry
--- lists and where to read them. A fresh install says nothing (its first open offers the tour). The version seen is
--- kept (db.versionSeen); one who used Terminal before that was kept (0.69 and before) counts as updating, so the
--- release that brings this says it too.
function CL.Announce()
	local db = ns.db
	local now = ns.version
	if type(db) ~= "table" or type(now) ~= "string" or now == "dev" then return false end
	local seen = db.versionSeen
	db.versionSeen = now
	if seen == now then return false end
	if seen == nil and not (db.tourOffered or (type(db.history) == "table" and #db.history > 0)) then return false end
	local top = CL.LOG[1]
	local n = top and top.v == now and type(top.items) == "table" and #top.items or 0
	if n > 0 then
		ns:Print(L["Updated to %s: %d new things. .changelog shows them"]:format(now, n))
	else
		ns:Print(L["Updated to %s. .changelog shows what's new"]:format(now))
	end
	return true
end
do
	-- (a few seconds in: after the game's and other addons' login lines, not lost among them)
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		if C_Timer and C_Timer.After then C_Timer.After(4, CL.Announce) else CL.Announce() end
	end)
end
