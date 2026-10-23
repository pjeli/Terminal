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
		v = "0.66.13", when = "in testing",
		items = {
			"Undo in the prompt: Ctrl+Z undoes your last edit to what you typed (a word, a Ctrl+W, a paste), Ctrl+Y redoes it.",
			"Upgrades follow your talents: with no tree picked, .weights judges by the tree holding most of your talent points (31 in Fury: Fury), and follows a respec. .weights all goes back to that.",
			"Upgrades know your hit cap: hit past it counts for nothing (5% melee, 4% spells below 60; 9% and 16% at 60), so a +2% hit item isn't an upgrade once you're capped. .weights says where you stand.",
			"Sort by more than one field: sort:quality,-level sorts by quality, then by level on a tie. In Simple mode, Shift on a Sort pick makes it the \"then by\".",
			"Numbers in plain words: \"swords between level 20 and 30\", \"quests under level 25\", \"items worth more than 1g\", \"bags with at least 10 slots\", \"gear with durability below 50%\". New Advanced filters value:>1g and slots:>=10.",
			"Levels from yours: \"quests 3 levels above me\", \"dungeons around my level\", \"gear for next level\"; Advanced: lvl:me+3, lvl:me-2..me+3. A saved search or alias moves with you as you level.",
			"Top N: \"the 3 nearest mailboxes\", \"top 5 upgrades\", \"my 10 most valuable items\", \"the closest innkeeper\"; what acts on the list acts on just those. Advanced: | first 3.",
			"Dates in plain words: \"loot from yesterday\", \"mail older than 20 days\", \"auctions sold this week\", \"what killed me today\", \"in the last 3 days\". Advanced: since:yesterday, older:20d.",
			"An Advanced line in plain words: point at one in the prompt, or .explain it (\"@npc is:vendor sells:arrow sort:distance\": \"Vendors, that sell arrow, nearest first\"); .explain alone explains the last line you ran.",
			"Compare two searches: \"cloth but not in my bank\", \"linen plus my alts\"; Advanced: | except @bank, | also @stored.",
			"\"Why is this here?\" in a row's menu: which words it matched and where, the filters it passed, its sort value, and for an upgrade what it gains.",
			"Upgrades you can buy: \"upgrades i can buy\" (or \"vendor upgrades\") lists the friendly vendors selling a clear upgrade for you, nearest first, with what it gains and a standing it needs. Advanced: @npc sells:upgrade. Needs Questie.",
			"The cheapest upgrades on the auction house: with Auctionator and AtlasLoot, \"ah upgrades\" lists bind-on-equip upgrades at Auctionator's last-scanned price, the most gain per gold first (\"+12 for 3g 40s\").",
		},
	},
	{
		v = "0.66.0", when = "released October 2026",
		items = {
			"Your own key: bind any key to Terminal (^ on a German keyboard, Ctrl+Space) and it does what ` does: closes it, Alt+ it for Advanced mode, Tab+ it for fuzzy finding. The hints name your key.",
			"Quests that reward bags: \"bag quests\" lists the bags your race, class and faction can still get, most slots first. Advanced: @questie reward:bag sort:slots.",
			"Sort either way: an arrow shows the direction; pick a sort again to flip it. Advanced: sort:-level. Nearest or farthest: \"farthest innkeeper\", sort:distance and sort:-distance.",
			"Upgrades by talent tree: .weights fury, .weights holy, .weights bear (or tank, healer), with new weights made for WoW Forever. Your own: .weights set str=2 agi=1, or a Pawn scale with .weights pawn.",
			"Fewer commands: .xp, .history, .mail and the like are searched as anything is. .forget <alt> drops an alt; .forget history and .forget combatlog clear those.",
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
