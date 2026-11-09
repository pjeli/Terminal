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
		v = "1.2.9", when = "in testing",
		items = {
			"Terminal: Share: friends can share where they are (.share settings location on; off by default; .share <group> location on or off for one group, which wins): each is a class-coloured dot on your world map and a row in your searches, \"where are my friends\"; Enter or a click puts a waypoint on them.",
			"Terminal: Share: guild members and friends who share where they are with OpenMap show too, dots and rows alike (.share settings openmap on; off by default).",
			"A footer too long for its line (\"recipes i can learn now\") wraps onto more lines, the terminal growing downwards, instead of being cut off.",
			"Fixes from a review of sharing where you are: friends on an older Terminal: Share no longer drop you every 30 minutes, and places go out ahead of bags and cost less.",
			"Fixes from a review of the latest changes: OpenMap players' places cost less in a big guild, the footer is laid out only when it changes, and .zen also fades the boxes of raid frames made while it's open.",
			"Fixed: with .zen on, your target's highlight on the party and raid frames no longer shows through the faded interface.",
			"When someone asks Terminal (!t) in a chat it doesn't answer in yet, it now says plainly what to type to turn it on (.ask group on).",
			"Fixed: with Shift+` (or another Shift chord) bound to Terminal, opening it on a kept search no longer types a ~ after it.",
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
	{
		v = "1.1.0", when = "released November 2026",
		items = {
			"With OneForAll: @book lists the Library Books, where each is and which you've turned in; \"books i still need\", \"nearest library book\".",
			"With OneForAll, for hunters: @spell has your pet's abilities (each rank, learned or not; Enter: who teaches it), @npc says which beasts you can tame; \"where to learn bite 4\", \"tameable cats\", \"rare pets\".",
			"@reputation lists every quartermaster's reward (OneForAll's, and AtlasLoot's faction loot) and whether you can buy it yet (\"argent dawn rewards\", is:canbuy); with OneForAll, @itemset has each set's pieces (\"my class sets\").",
			"With OneForAll: \"upgrades\" go by its gear value for your talents, and @loot has the gear its planner knows (quest rewards, crafted, reputation), each by its source (\"raid loot\", \"dungeon gear\"), with drop chances.",
			"With OneForAll: recipes you don't know say if the Merchant's Favor buys them; @transport (boats, zeppelins, the tram, roads); @attune has its dungeon keys when Attune isn't installed; @panel opens its window on any tab.",
			"Many more plain-word questions: \"who gives <quest>\", \"quests near me\", \"what does hogger drop\", \"how many linen do i have\", \"what level is hogger\", \"where is my hearth\", \"xp per hour\", \"bigger bags\", \"quests for stormwind rep\", \"tailoring quests\".",
			"A question shows the same rows as its Alt+` line, and Advanced mode has new words for them: sort:list, sort:progress, sort:need, prof:, is:foryou, is:cantake, is:elite, is:rare, repreward:, skill:.",
			"Quest tooltips say what a quest needs (red when you lack it) and the reputation it gives.",
			"Inside a group you stepped into, the bar's Group and Sort work too; kinds and categories are in Title Case on English clients.",
			"Console: grep -A, -B, -C and -H; sed, awk and grep behave as on Linux in more cases.",
			"Many fixes and lighter typing from a full review; Terminal is on Wago too, for WoWUp and the Wago app.",
		},
	},
	{
		v = "1.0.0", when = "released November 2026",
		items = {
			"Share by invite: .share invite <name>, and they type .share accept. Groups get codes Terminal makes that nobody can guess; typed passwords are gone, so invite your friends again.",
			"Simple mode's questions in German, Spanish, French, Russian and Chinese: \"Quests zum Abbrechen\", \"où est mon corps\", \"mis subastas\" and 45 more.",
			"Stats, food and weapon damage in your language: \"Ausdauer Essen\" finds stamina food; shorthand like \"brd\" and your language's little words too.",
			"Other languages: trainers found by their translated titles, Chinese searches that find only names with the characters typed, fonts with Russian, Chinese and Korean letters.",
			"After an update, one line in chat says how many new things there are; .changelog shows them.",
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
