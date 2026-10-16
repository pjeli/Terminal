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
		v = "0.53.5", when = "in testing",
		items = {
			"Filters take a quoted value, with or without a |: q:\"Rare\", quality:\"Rare\", in:\"Elwynn Forest\". Enter on a group of a summed search writes the filter you would type (q:rare, in:\"Elwynn Forest\").",
			".zen: the faded interface takes no clicks or hovers; a click on it closes the terminal.",
			"Opening and closing the terminal costs less: the empty prompt's suggestions no longer read your bags, quests and professions again, and .zen's fade sets the interface's alpha in steps.",
			"Summed searches: \"by dungeon\" is dungeons, \"by raid\" raids, \"by instance\" either (not world bosses, battlegrounds, professions or factions); grouping by anything leaves out what has none of it, with no \"no ...\" group.",
			"@dungeon and @raid list an instance behind two doors (Blackrock Mountain) once, at the nearer door.",
			"Tabs: Ctrl+T opens a tab, Ctrl+1-4 or Ctrl+Tab switch, Ctrl+Shift+W closes one. Each keeps its search and mode, the one shown updates itself (no F5), and a dot marks one whose lists changed.",
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
	{
		v = "0.52.0", when = "released October 2026",
		items = {
			"Upgrades: \"upgrades\" lists gear you can get (about your level, from dungeons you can enter) that beats what you wear, the biggest first, and its tooltip says why: a line per stat, gains in green, losses in red. Advanced mode: @loot is:upgrade sort:best.",
			"Quest upgrades (with Questie): \"quest upgrades\" lists the quests near your level whose reward is an upgrade for you, with what each rewards and how far its giver is. Advanced mode: @questie is:upgrade sort:best.",
			"Lists stay put while you look at them: when your bags, the loot log, mail or item data change, the new list waits for F5 and the footer says so; a row whose count changed updates in place.",
			".tour: Terminal in a few short steps, each search typed for you and its result highlighted, including what Questie, AtlasLoot and Attune add when they're installed. A fresh install suggests it first.",
			"What Terminal learns of items is kept between sessions: after a /reload, upgrades and item colours are right from the first search.",
			"An NPC inside a dungeon says which one on its row, and its distance, arrow and map pin point at the dungeon's entrance.",
			".zen's dimming is adjustable: Options > Zen dimming (or .set zenDim 0.4).",
			"@xp also lists the alts your bag addon knows of that Terminal hasn't seen yet (log in on each once).",
			"Fixes: items in a list no longer show white until you scroll past them; a Simple mode category lists everything its row counted; a command's choices of more than one word are picked whole; the Options panel fits its frame; Terminal Extras has its own icon; and many smaller fixes from a review.",
		},
	},
	{
		v = "0.51.0", when = "released October 2026",
		items = {
			"Your corpse: \"where is my body\" (@corpse) shows where it lies, how far and which way, and the nearest spirit healers (\"nearest spirit healer\", @npc is:spirithealer).",
			"Your gear's wear: \"durability\" or \"repair cost\" (@durability) lists each piece's durability and repair cost, the whole bill on top.",
			"Other addons' settings: type a setting's name to find it in any Ace3 addon (@addonoption); Enter opens it, Shift+Enter toggles it.",
			"With Attune: @attune, \"my attunements\", \"how do i get into molten core\": your attunements and keys, your progress and next step.",
			"Your own commands: .alias rep durability makes .rep run that search, slash command or .command; .unalias forgets one.",
			"Reaching for Questie, AtlasLoot, Attune or your alts' bags without the addon: the footer says which to install.",
			"Alt+click a chat link to look it up in Terminal (Ctrl+click is the dressing room's again).",
			"in:warband is gone (WoW Forever has no warband bank).",
			"A review of the whole addon: many fixes (\"who needs blessing of kings\", in:bags, \"summon voidwalker\", spells on macros, upgrades for one-handers, the row menu's Send) and less work while you type and play.",
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
