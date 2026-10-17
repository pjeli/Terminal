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
		v = "0.55.12", when = "in testing",
		items = {
			"A bar under the prompt in Simple mode: Filter, Sort and Group a click away, and a speaker button to send every result to chat or copy them all (a single result: right-click it). Words you type like \"rare\" or \"nearest\" show on it, and questions (\"my auctions\") are filtered and sorted too. Advanced mode sorts as well: sort:name, sort:level, sort:ilvl, sort:quality, sort:value, sort:count.",
			"Advanced syntax typed in Simple mode (@kinds, key:value, sort:name, sending to chat, \"| group by\") now works right there: your words stay as typed and the bar shows what it picks. Alt+` again, or Shift+Left, brings back your words after Alt+`.",
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
	{
		v = "0.53.0", when = "released October 2026",
		items = {
			"The empty prompt's suggestions fit where you are (a city, out in the world, a dungeon) and the addons you have.",
			"Upgrades: the tooltip shows the game's own comparison, only clear upgrades are listed (never what you wear already), and F5 is offered only once a new list is sure.",
			"Copy results to paste elsewhere: >> text or >> csv (>>> for every result; in Simple mode, \"linen to csv\"). Ctrl+C copies and closes the box.",
			"Words in quotes are found together, as they are: \"outlaw saber\".",
			"Advanced mode sums up a search after a | standing alone: \"in:bags | sum value\" (what it all sells for), \"@quest | group by zone\", \"@item | count by quality\". Enter on a group lists its rows.",
			"Closed and opened again within 5 seconds, the terminal has your text back, in the mode it was in; Esc clears it.",
			".atop: Left/Right switch CPU % between a share of all addons and a share of a frame.",
			"A smaller download: only what the game runs.",
			"Fixes from a review before release: rings, trinkets and two weapons are judged against each piece you wear; a list that changes several times while you look at it keeps up; Simple mode's \"to csv\" copies every row, and copied coins keep their g/s/c; Enter on a total says it in chat; and smaller ones.",
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
