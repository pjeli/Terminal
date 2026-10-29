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
		v = "0.68.17", when = "in testing",
		items = {
			"\"nearest cooking fire\" and \"nearest moonwell\" (needs Questie or QuestieDB).",
			".tour shows a different \"nearest\" each time: a vendor, an innkeeper, an anvil, a forge...",
			".saved keep talents small keeps every class's talents but not their descriptions, most of their size.",
			"!t: your guild or group asks Terminal (\"!t nearest innkeeper\") and it answers for them. Off until you switch it on: .ask guild on.",
			"A smaller download that loads faster: only your language's translations are read, and the code comes without its comments.",
			"Spells by what they do: \"spells that stun\", \"instant spells\", \"spells with no cooldown\", \"30 yard spells\", any class's.",
			"Say what kind you want: \"hogger quest\", \"quests in westfall\", \"npcs in westfall\", \"linen recipes\" look only there.",
			"Asked as you'd say it: \"where is the nearest mailbox\", \"repair near me\", \"nearest innkeepers\", \"innkeeper in stormwind\".",
			"Typos as hands make them: \"linnen\", \"lien\" and \"linrn\" find Linen Cloth, \"marshal dughn\" Marshal Dughan; \"linken\" stays Linken.",
		},
	},
	{
		v = "0.68.0", when = "released October 2026",
		items = {
			".console: a Linux-like console over everything Terminal knows: ls, cd, cat, grep, pipes, up to four panes.",
			"Smaller saved data: your settings stay in Terminal.lua, everything else moves to TerminalCache.lua, safe to delete. .saved shows it and sets how much to keep.",
			".report: found a problem? It makes a report to paste on Terminal's CurseForge page.",
			"\"nearest forge\" and \"nearest anvil\", for blacksmiths and engineers (needs Questie or QuestieDB).",
			"Alt+` keeps your capitals, and \"not in my bank\" lists your items that aren't there.",
			"Flight paths, entrances, zone and fishing levels now come from the game's own data; @cvar explains each setting.",
		},
	},
	{
		v = "0.67.0", when = "released October 2026",
		items = {
			"Numbers, levels and dates in words: \"swords between level 20 and 30\", \"loot from yesterday\".",
			"Top N and comparisons: \"the 3 nearest mailboxes\", \"cloth but not in my bank\".",
			"Sort by more than one field, and Ctrl+Z / Ctrl+Y undo in the prompt.",
			".explain and \"Why is this here?\" say what a search does and why a row is listed.",
			"Upgrades follow your talents and hit cap; \"upgrades i can buy\" and \"ah upgrades\" find them for sale.",
		},
	},
	{
		v = "0.66.0", when = "released October 2026",
		items = {
			"Bind any key to Terminal; it does what ` does.",
			"\"bag quests\" lists the bags you can still get from quests.",
			"Sort either way: pick a sort again to flip it; \"farthest innkeeper\" too.",
			"Upgrades by talent tree (.weights fury, holy, bear), or your own Pawn scale.",
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
