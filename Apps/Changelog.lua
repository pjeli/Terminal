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
		v = "0.56.7", when = "in testing",
		items = {
			"The bar's button says Group again.",
			"Every class's spells (\"travel form\", \"druid spells\", \"upcoming spells\") and the weapon masters (\"dagger trainer\") come straight from What's Training now, so they stay as up to date as it is. Without What's Training the footer says to install it.",
			"Grouped results say how many groups and how many results they hold: \"14 groups · 34 results\".",
			"When plain words find nothing, Terminal offers what you may have meant: a spelling put right, a phrase it understands, or the category a word names. .missed lists the searches that found nothing, to try again.",
			"A result's menu says \"Whisper to target\" with your target's full name, and the whisper reaches them (it went to \"%t\" before).",
			"Battle.net friends show the name the Friends window shows, even when the game keeps it from addons.",
			"Attune's new look: Enter opens it on the right attunement (its Archived group too) and points at it in the list or the icon view; a step out of view is scrolled to; steps are lettered left to right as its chart draws them, a split's branches each their own letter; side quests are named by its \"Inside the dungeon\" box; its short names (\"ubrs\", \"dal key\") find attunements.",
			"The bar underlines the F of Filter, the S of Sort and the G of Group: Alt+F, Alt+S and Alt+G open them.",
		},
	},
	{
		v = "0.56.0", when = "released October 2026",
		items = {
			"A bar under the prompt: Filter, Sort and Group a click away (or Alt+F, Alt+S, Alt+G), and a speaker button that sends every result to chat or copies them all.",
			"Your words stay your words: Advanced syntax typed in plain words works right there, and the bar shows what it picks. Alt+` writes the line in Advanced syntax; Alt+` again or Shift+Left brings your words back.",
			"Questions take the bar too: \"my auctions\" sorted by value, \"my spells\" not on your action bars. Alt+` writes what they ask so it finds the same.",
			"Each list's own filters on the bar: not on my action bars, quests to drop, needs repair, unread mail, sold auctions, holidays and more.",
			"Advanced mode sorts too: sort:name, sort:level, sort:ilvl, sort:quality, sort:value, sort:count.",
			"Attunement steps numbered as Attune lays them out (1, 2a, 2b, 3a...), side quests marked; Sort \"Line by line\" lists each line of quests in turn.",
			"Items and Bank & alts are two categories again; one result is sent or copied from its right-click menu.",
			"The search underneath is simpler and quicker: the categories are one search that narrows as you type, and many fixes from a review.",
		},
	},
	{
		v = "0.55.0", when = "released October 2026",
		items = {
			"One mode: type in plain words, and Advanced syntax (@npc, q:rare, >> party) works as soon as you type it, the words before it written in it too. .simple and .advanced are gone.",
			"Every class's spells under @spell, known or not, with the level each rank is learned at: \"travel form\", \"druid spells\", \"upcoming spells\", @spell class:druid; \"my spells\" for your spellbook.",
			"Spell IDs: \"spellid claw\" lists every rank's ID to copy, \"spellid 1082\" shows the spell; tooltips show the ID too.",
			"Talents by what they do: \"healing talents\", \"shaman crit talents\", \"druid regen talents\"; druid talents are found from every class.",
			".weights shows how upgrades are judged and picks your roles: .weights feral healer counts an upgrade for either.",
			"Weapon masters by weapon (\"dagger trainer\") without What's Training too.",
			"Alt+` with Terminal closed opens it as ` does; Up goes through every line you ran.",
			"Tooltips: what Enter and Shift+Enter do, a line each, said the same way everywhere.",
		},
	},
	{
		v = "0.54.0", when = "released October 2026",
		items = {
			"With What's Training: @training, \"what can i train\", \"what do i learn next level\", \"how much is training\": every spell you've still to learn, when, and what it costs. Enter opens What's Training on it; Shift+Enter lists who teaches it, the nearest first.",
			"Weapon masters: \"dagger trainer\" or \"where do i learn daggers\" lists the ones who teach it, the nearest first.",
			"Tabs: Ctrl+T opens one, Ctrl+1-4 or Ctrl+Tab switch, Ctrl+Shift+W closes one; each keeps its own search.",
			"Summed searches group \"by dungeon\", \"by raid\" or \"by instance\" as they say, and filters take quoted values: q:\"Rare\", in:\"Elwynn Forest\".",
			"@dungeon and @raid list Blackrock Mountain's instances once, at the nearer door.",
			".zen's faded interface takes no clicks; a click on it closes the terminal.",
			"Faster: narrowing a search is up to twice as fast, and opening the terminal costs less.",
			"Fixes from a review: tabs, summed searches, stats (mp5, healing, ranged attack power), characters who share a first name, chat lines in other languages, and many smaller ones.",
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
