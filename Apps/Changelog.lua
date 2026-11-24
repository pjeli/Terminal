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
		v = "1.8.4", when = "in testing",
		items = {
			"Find gear by its bonus: where it grows (\"haunted bonus\", bonus:swamp, bonus:area) or what it's against (\"against undead\", bonus:troll), read from the item's own tooltip; | group by bonus.",
			"A bonus goes with the rest of a search: \"argent dawn rewards against trolls\", \"reputation rewards that deal 2x damage to trolls\", \"faction rewards with a bonus in mountainous areas\".",
			"\"what layer am i on\" says WoW Forever hides your layer since its November 20 hotfix, instead of a number that no longer means anything.",
			"Nothing relies on your realm's name any more (the game no longer gives it): alts, mail, lockouts, upgrade picks and sharing with Battle.net friends go by names alone.",
		},
	},
	{
		v = "1.8.0", when = "released November 2026",
		items = {
			"With Pawn installed, the scales it shows judge your upgrades: no exporting and pasting (.weights picks still come first; .weights paste for a string).",
			"Ask Terminal how: \"how do i send to party\", \"what does shift enter do\": its own help as rows, Enter writes the example.",
			"Faction rewards are found by what they are: \"@faction cenarion tailoring\" lists its tailoring patterns.",
			"Group by category: rewards, loot or your bags as recipes, weapons, gear, consumables, pets and mounts; then by subtype (recipes by profession).",
			"Track or untrack your PvP quests in one go: \"untrack pvp quests\", \"track battleground quests\".",
			"After an update the empty prompt says what's new: Enter on it opens the changelog.",
			"A \"Keep your session\" checkbox in the options panel; Ctrl+Space (or another chord bound to Terminal) no longer types its space.",
			"Fixed: a \"Warband bank\" at 0c in your gold with Baganator; and the fixes of a release review.",
		},
	},
	{
		v = "1.7.0", when = "released November 2026",
		items = {
			"A new look: icons drawn like the bags', framed in their item's quality colour; the Forever theme's names parchment-white, the letters you typed gold.",
			"A quieter kind column: a dot of each kind's colour, and no column at all when you asked for one kind; the classic frame has the game's stone grain and a shade.",
			"Recipes: a recipe you don't know and its \"where to learn\" say the same (the Merchant's Favor and its vendor, a trainer, the recipe item), and it's drawn in the colour is:orange... judge it by.",
			"Quests: \"can i take\", is:cantake, \"quests near me\", the zones' counts and \"quest upgrades\" judge a quest by the same rules.",
			"\"train the next rank\" and the prompt's examples agree, and send you to a trainer who can teach the rank (\"nearest expert tailoring trainer\").",
			"!t answers ignore your own Filter and Sort picks, and \"my level\" is the asker's.",
			"\"<faction> > rewards\" lists AtlasLoot's rewards too; factions not in WoW Forever yet have none listed, and a reward's vendor is one of yours, the nearest.",
			"Smaller fixes: is:upgrade over @loot, no boss's drop chance on a trash row, \"skinner\" finds trainers of your side, a quest's giver of your side, pet food vendors, places in Simple mode.",
		},
	},
	{
		v = "1.6.0", when = "released November 2026",
		items = {
			"TradeSkillMaster's auction house prices: with TSM installed, its prices come first and Auctionator's fill in the rest; either one alone does it all (\"what should i auction\", \"am i undercut\", sort:ahvalue).",
			"DungeonJournal: right-click an item, a quest or a dungeon for \"Show in Dungeon Journal\"; \"my favorites\" (@favorite) lists the items you starred in it, and is:favorite finds them in any list of items.",
			"New setting \"Thank players who buff you\" (off unless turned on): a /thank to a player outside your group who buffs you; with OneForAll's own option on, Terminal leaves it to OneForAll.",
			"\"library book rewards\" without OneForAll: just the Library's three reward tiers, each with how many books it takes.",
			"No more short freeze half a minute after logging in: the recipes you haven't learned are read a little at a time.",
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
	CL.NewsDone() -- (read: the empty prompt's "what's new" goes)
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
	db.newsFor = now -- (the empty prompt says so too, until read: CL.NewsLine)
	local top = CL.LOG[1]
	local n = top and top.v == now and type(top.items) == "table" and #top.items or 0
	if n > 0 then
		ns:Print(L["Updated to %s: %d new things. .changelog shows them"]:format(now, n))
	else
		ns:Print(L["Updated to %s. .changelog shows what's new"]:format(now))
	end
	return true
end
--- (1.7.5) After an update the empty prompt says what's new, the first suggestion, until you open the changelog
--- (Enter on that empty prompt does, Shift+Right writes .changelog) or start typing in a prompt that showed it: the
--- chat line at login is easily lost among the game's and other addons'. Not on a fresh install (CL.Announce: the tour
--- comes first there). nil when there's nothing new to say.
function CL.NewsLine()
	local db = ns.db
	local now = ns.version
	if type(db) ~= "table" or type(now) ~= "string" or db.newsFor ~= now or db.newsSeen == now then return nil end
	return "try: .changelog (" .. L["what's new in %s"]:format(now) .. ")"
end
--- What's new read (the changelog opened) or passed over (typed over): not said again for this version.
function CL.NewsDone()
	local db = ns.db
	if type(db) == "table" and db.newsFor ~= nil then db.newsSeen = db.newsFor end
	if ns.Easy then ns.Easy.newsShown = nil end
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
