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
		v = "0.65.1", when = "in testing",
		items = {
			"Keyboards without a plain ` (German, French and others): the key you bind to Terminal (Key Bindings > AddOns > Terminal, or .bind) does in it what ` does: it closes it, Alt+ that key writes the search in Advanced mode, Tab+ it is fuzzy finding. Bound alone, a key like ^ or ² works too, and the hints, F1 and the windows' footers name your key instead of `.",
		},
	},
	{
		v = "0.65.0", when = "released October 2026",
		items = {
			"Your collections in plain words: \"mounts\", \"my pets\", \"toys\" list them by name with how many you have; \"favorite mounts\" keeps the journal's favorites, \"raptor mounts\" the ones named so. Enter summons or uses one, Shift+Enter shows it in the journal. Advanced: @mount is:favorite (on pets and toys too).",
			"Buyback anywhere: \"buyback\" or \"what did i sell\" (@buyback) lists what you've sold since you logged in, with when and for how much, without opening a vendor; at any vendor Enter buys one back.",
			"Out of arrows or bullets with a bow or gun (a hunter: running low), the empty prompt suggests \"nearest vendor sells:arrow\" (or sells:shot); out of a reagent your spells use (a priest's candles, a paladin's symbols, a mage's runes or Arcane Powder, a druid's seeds, a shaman's ankhs), \"nearest reagent vendor\"; a rogue out of flash powder, the vendors that sell it. Each goes as soon as you've bought some.",
			"is:enchanted and is:unenchanted on gear in your bags, bank and alts' (@item is:unenchanted, @bank is:enchanted); is:unenchanted keeps to gear an enchant goes on.",
			"Each tab over the prompt shows a small x while the pointer is on it: a click closes that tab (as a right-click or Ctrl+Shift+W does).",
		},
	},
	{
		v = "0.64.0", when = "released October 2026",
		items = {
			"Ctrl+R searches what you ran, as a shell's does: type to find a line, Ctrl+R again for an older one, Enter puts it in the prompt and searches it, Esc goes back. \"history\" (or @history) lists what you ran, newest first, with when each ran; Enter searches one again.",
			"Track and untrack quests in bulk: \"untrack quests\", \"track completed quests\", \"untrack dungeon quests\", \"track class quest\", \"track rfc quests only\" (and untrack the rest), \"untrack red quests\", \"track nearby quests\". The answer lists what changes; Enter does it, Questie's tracker too. A place means the quests listed under it in your log (\"track thunderbluff quests\"). Advanced: any quest search, then >>> track, >>> untrack or >>> track only.",
			"@auction: your auctions' prices are each item's, as the Auctions tab shows them, and a sale is listed once, even when its mail was read before the game knew the buyer.",
			"Fixes and speed-ups from a review of the whole addon: a filter after a question acts only on what it leaves (\"untrack quests is:red\"), sort:name sorts lists of any size, in:rfc / in:tb on your quest log mean those places, >> party on a Simple mode category picks it, and big searches, Simple mode's categories, spell IDs, talents and quest rewards are quicker and lighter as you type.",
		},
	},
	{
		v = "0.63.0", when = "released October 2026",
		items = {
			"Ask \"what should i do\" (or \"what now\") for what's worth doing now, the most pressing first: gear to repair, junk to sell, spells or a weapon skill to train, a profession's next rank or one to level, your class quest, quests to turn in, quests at your level here or a better zone, the dungeon for your level. Enter searches for it (a class quest: its steps); its tooltip shows the Advanced syntax.",
			"\"try: what should i do\" is one of Simple mode's empty prompt examples, coming up sooner when there's something worth doing; the prompt itself stays empty.",
			"New plain questions: \"quests per zone\" (@questie | group by zone), \"quests to turn in\" (@questlog is:complete), \"quests here\" (Questie's at your level in your zone), \"what can i craft\" (@recipe is:craftable), \"low durability\", \"dungeons at my level\".",
			"\"nearest class trainer\" lists your class's trainers and \"nearest weapon trainer\" the weapon masters (trainer:class, is:weaponmaster), not NPCs with those words in their names; \"nearest fist weapons trainer\" finds the fist weapon masters (trainer:fist).",
			"Enter on a group steps into it: the words you typed to find it go (\"@questie Death\" grouped by zone, Enter on Deathknell: @questie in:\"Deathknell\"), not left beside it.",
			"Auctionator: with it installed, items have an AH value (sort:ahvalue, | sum ahvalue); \"what should i auction\" lists your bag items worth more on the auction house than at a vendor, with what each would bring; \"ah value of my mats\" sums them up; @auction says the auction house's price now and which of yours are undercut (\"am i undercut\", is:undercut).",
			"\"what should i auction in my bank\", \"... on my alts\", \"... everywhere\": the same with your bank and alts; @stored sort:ahvalue. A search sorted by AH value (or with is:auctionable) shows it in each row's detail.",
			"@bank is this character's own bank; @stored is still every character's. \"what is in my bank\" lists it.",
			"A long detail takes the room its name doesn't need, so wide windows show it whole.",
			"Terminal: Share shares only with characters on your own realm: a Battle.net friend playing on another realm (another ruleset, PvE beside PvP) isn't connected to, and their items aren't shown. The other faction on your realm still is.",
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
	local fn = KEYS and KEYS[key]
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
