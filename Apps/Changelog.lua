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
		v = "0.60.0", when = "released October 2026",
		items = {
			"Terminal: Share, a new addon that comes with Terminal (turn it off in the AddOn list if you don't want it): friends who run it and type the same password (.share password <password>) see what's in each other's bags in their searches. \"linen cloth\" lists yours, your alts' and your friends', with how many each has and where, bags and bank apart (@shared; Bank & alts in Simple mode).",
			"Groups: .share join <group> <password> for a group of its own, five at most, each sharing what you choose (.share raid all, .share default limited). Friends see what you share in the groups you have in common; .share leave <group> leaves one.",
			"What you share: .share limited (the default) is this character's crafting mats and consumables, in its bags and bank; .share all adds everything on all your characters and in your banks, and your gold; .share mats and .share consumables are just those; .share off stops.",
			"Private and light: only friends, guild members and Battle.net friends' characters are heard; passwords and group names are never sent, and passwords show as *s wherever you type them; a password needs 8 characters or more, no spaces, with three of: capitals, small letters, numbers, symbols; and a key made from each is remembered, so you connect again by yourself when you log in. A wifi sign at the end of the prompt shows who's connected. After the first sync only what changed is sent, and a burst of bag changes goes as one.",
			"A Battle.net friend's character is checked against your friend list and guild roster before it's taken for one of them: a friend with the same name can't pass for another.",
			"Searches over very large lists keep every frame short: Simple mode's categories and a search's first results no longer stall with hundreds of thousands of rows.",
		},
	},
	{
		v = "0.58.0", when = "released October 2026",
		items = {
			"TrainerSpells works with Terminal: without What's Training it gives @training (your class's spells, weapon skills and pet abilities still to learn) and every class's spells; without Questie its trainers and weapon masters are @npc.",
			"Profession training: the recipes a trainer teaches that you don't know are listed with your recipes to learn, with their skill and cost (\"what can i train in tailoring\"), and each profession shows its next rank.",
			"\"polearm trainer\" and the like list only the weapon masters who teach that weapon to your faction.",
			"When another addon's data isn't what Terminal expects, chat says once what's unavailable; .integrations has one Training line, for What's Training or TrainerSpells.",
			"Fixes and speed-ups from a review: Down after closing brings back what you typed, filters like is:ready stay right as you type, sold auctions keep their price, and more.",
		},
	},
	{
		v = "0.57.0", when = "released October 2026",
		items = {
			"Upgrades weigh only what you want: gear whose stats your class or role doesn't use (Intellect and Spell Power for a warrior) is never an upgrade, whatever its item level, and spells' hit and crit or feral attack power count only for those who use them.",
			"NPC lists are sorted nearest first (trainers, merchants, reagent vendors...), an NPC named what you typed still on top. An NPC's role said alone (\"inn\", \"bank\", \"repair\", \"weapon master\", \"skinner\") lists the nearest, and \"nearest\" mistyped still means nearest.",
			"Simple mode's categories come in a better order: NPCs whose title has your word (\"reagent\": the reagent vendors) near the top, and the category you picked for those words before higher each time.",
			"When plain words find nothing, Terminal offers what you may have meant: a spelling put right, a phrase it understands, or the category a word names. .missed lists the searches that found nothing.",
			"@auction lists your sales of the last 30 days (\"auctions sold\"): the price, the buyer and what you got. Auctions posted one after another each keep their own price.",
			"Every class's spells and the weapon masters come straight from What's Training, as up to date as it is.",
			"Attune's new look: Enter opens it on the right attunement and points at it, or at a step; steps are lettered as its chart draws them; its short names (\"ubrs\", \"dal key\") find attunements.",
			"The bar: its button says Group, the F, S and G of its keys are underlined, and grouped results say how many groups and results they hold.",
			"The / key can open Terminal on a slash command, the \"/\" already typed: turn it on with .set slashKey on, or Options.",
			"Whisper to target uses your target's full name and reaches them; Battle.net friends show the name the Friends window shows.",
			"In combat only Ctrl+` opens Terminal: a ` hit by accident in a fight says so in chat instead of taking your next keys. Tab+` and /term open it as before; / never opens it in combat.",
			"Alt+` only switches what you typed between plain words and Advanced syntax; it no longer opens or closes Terminal.",
			".credits: a thank-you to the people who kept Terminal going.",
			"Fixes from a review: the send button with a player targeted, sales told twice, refused auction posts, and more.",
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
