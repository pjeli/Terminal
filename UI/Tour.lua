local ns = select(2, ...)
local L = ns.L

-- .tour (0.51.16; made plainer in 0.51.20, the player: "not very intuitive and simple: it should highlight some basic
-- results and be very clear"): a few short steps. A card above the terminal says what the step shows, in a sentence or
-- two; the step's search is typed for you and the result it's about is selected (the highlighted row). Enter goes on,
-- Shift+Left goes back, Esc ends it; typing ends it too, and you carry on from there. Up and Down, Tab and the mouse
-- work as ever. In Simple mode (for the tour, when you use Advanced). The empty prompt's first suggestion on a fresh
-- install is ".tour" (Examples.lua: E.NextExample).

local T = {}
ns.Tour = T

-- { text: typed into the prompt, pick: the row to select (its name, lowercase; "first"; "category"; or a test of the
-- row, else the first), title, say }. Questie's, AtlasLoot's and Attune's steps show what they bring when they're
-- installed (0.51.22, 0.51.23: the player's asks); the ones that aren't are named on one card, with what installing
-- them adds. With none of them, two steps of the game's own: an item from your bags, and a setting.
local function HasAddon(name)
	local I = ns.Integrations
	return not (I and I.AddonMissing and I.AddonMissing(name))
end

--- Attune's step: the Dalaran key's steps (the Horde's Sewer Key; the Alliance's City of Dalaran quests), else the
--- attunements you have.
local function AttuneText()
	local Q = ns.Attune and ns.Attune.Q
	for _, t in ipairs({ "how do i get the dalaran key", "how do i get attuned to city of dalaran" }) do
		local ok, how = pcall(function() return Q and Q.How and Q.How(t) end)
		if ok and how then return t end
	end
	return "my attunements"
end

--- Your bags' items: the Hearthstone left out (0.51.24, the player: the tour showed it every time), every one, and the
--- Hearthstone's row (nil: none in your bags).
local HEARTHSTONE = 6948 -- (by its id: its name is the client's language's; review, 0.51.25)
local function BagItems()
	local p = ns.providers and ns.providers.items
	if not p then return {}, {} end
	local ok, rows = pcall(ns.GetEntries, ns, p)
	if not (ok and type(rows) == "table") then return {}, {} end
	local some, every, hearth = {}, {}, nil
	for _, e in ipairs(rows) do
		if e.firstBag and type(e.name) == "string" and e.name:find("%S") then
			every[#every + 1] = e
			if e.itemID ~= HEARTHSTONE then some[#some + 1] = e else hearth = e end
		end
	end
	return some, every, hearth
end
local function Random(t) return t[1] and t[math.random(#t)] or nil end
local function PickItem(e)
	local id, name = e.itemID, ns.Lower(e.name)
	return function(r) return (id and r.itemID == id) or (type(r.name) == "string" and ns.Lower(r.name) == name) end
end

--- The setting step's search: one of the game's settings that's there (its name in your client's language), at random:
--- nameplates, the damage meter, class colours, auto loot (0.51.24, the player's examples).
local SETTINGS = { "ENABLE_DAMAGE_METER", "RAID_USE_CLASS_COLORS", "UNIT_NAMEPLATES_AUTOMODE", "SHOW_CLASS_COLOR_IN_V_KEY",
	"AUTO_LOOT_DEFAULT_TEXT" }
local SETTINGS_EN = { ENABLE_DAMAGE_METER = "Enable Damage Meter", RAID_USE_CLASS_COLORS = "Display Class Colors",
	UNIT_NAMEPLATES_AUTOMODE = "Always Show Nameplates", SHOW_CLASS_COLOR_IN_V_KEY = "Class Colors in Nameplates",
	AUTO_LOOT_DEFAULT_TEXT = "Auto Loot" }
local function SettingText()
	local names = {}
	local p = ns.providers and ns.providers.gameoptions
	local ok, rows = pcall(function() return p and ns:GetEntries(p) end)
	for _, e in ipairs(ok and type(rows) == "table" and rows or {}) do
		if type(e.name) == "string" then names[ns.Lower(e.name)] = true end
	end
	local there, known = {}, {}
	for _, g in ipairs(SETTINGS) do
		local n = ns.Str and ns.Str(_G[g]) or (type(_G[g]) == "string" and _G[g]) or nil
		n = ns.Lower(n or SETTINGS_EN[g])
		known[#known + 1] = n
		if names[n] then there[#there + 1] = n end
	end
	return Random(there) or known[#known]
end

--- "Say what to do" (0.51.25, the player: "use elixir of fortitude" is no quicker than your bags): a kind of thing, not
--- its name, that something in your bags is: "use stamina food", "equip shield"; else "use food". Its line and the
--- filters its rows pass, or nil.
local STATS = { "stamina", "strength", "agility", "intellect", "spirit" }
local KINDS = { "food", "elixir", "potion", "scroll", "flask" }
local GEAR = { "shield", "sword", "axe", "mace", "dagger", "staff", "bow", "gun", "wand", "helm", "cloak", "gloves", "belt",
	"boots", "ring", "trinket", "bracers" }
local PLAIN = { "food", "drink", "potion", "bandage", "elixir", "scroll" }
local function DoLine(rows)
	local F, E = ns.Filters, ns.Easy
	if not (F and F.Parse and F.Pass and E and E.WORDS and #rows > 0) then return nil end
	local function Filters(...)
		local out = {}
		for _, w in ipairs({ ... }) do
			local ok, f = pcall(F.Parse, E.WORDS[w] or w)
			if not (ok and f) then return nil end
			out[#out + 1] = f
		end
		return out
	end
	local function Has(fs)
		if not fs then return false end
		for _, e in ipairs(rows) do if F.Pass(e, fs) then return true end end
		return false
	end
	local best, plain = {}, {}
	for _, st in ipairs(STATS) do
		for _, k in ipairs(KINDS) do
			local fs = Filters(st, k)
			if Has(fs) then best[#best + 1] = { "use " .. st .. " " .. k, fs } end
		end
	end
	for _, g in ipairs(GEAR) do
		local fs = Filters(g, "equippable")
		if Has(fs) then best[#best + 1] = { "equip " .. g, fs } end
	end
	for _, k in ipairs(PLAIN) do
		local fs = Filters(k)
		if Has(fs) then plain[#plain + 1] = { "use " .. k, fs } end
	end
	local c = Random(best) or Random(plain)
	if c then return c[1], c[2] end
end

--- The key that opens Terminal, as the last card says it (bound on first run to `, or Ctrl+` when that's taken; any
--- other the player chose; none: /term). (Review, 0.51.25: the card always said `.)
local function ToggleKey()
	local ok, key = pcall(_G.GetBindingKey or function() end, "TERMINAL_TOGGLE")
	if not ok or type(key) ~= "string" or key == "" then return "/term" end
	if key == "`" then return L["` (under Esc)"] end
	local okT, text = pcall(_G.GetBindingText or function() end, key, "KEY_")
	return okT and type(text) == "string" and text ~= "" and text or key
end

local MISSING = {
	{ name = "Questie", title = L["Add Questie"],
		say = L["Install Questie (or QuestieDB) and Terminal knows every NPC and quest: the nearest innkeeper, mailbox, trainer or vendor with an arrow pointing the way, every quest by its text, and who gives it."],
		line = L["Questie: the nearest innkeeper, mailbox, trainer or vendor with an arrow pointing the way, and every quest."] },
	{ name = "AtlasLoot", title = L["Add AtlasLoot"],
		say = L["Install AtlasLoot and Terminal knows every dungeon's loot: type upgrades for gear that beats what you wear, or a dungeon's name for what drops there."],
		line = L["AtlasLoot: every dungeon's loot, and the upgrades in it for you."] },
	{ name = "Attune", title = L["Add Attune"],
		say = L["Install Attune and Terminal knows every attunement, key and dungeon quest line: ask how to get a key and its steps are listed in order, with how far along you are."],
		line = L["Attune: every attunement, key and dungeon quest line, step by step."] },
}

function T.Steps()
	local some, every, hearth = BagItems()
	local item = Random(some) or hearth -- (only the Hearthstone: it, by its name in your language)
	local steps = {
		{ text = "", title = L["Welcome to Terminal"],
			say = L["Find anything in the game by typing a few letters, then press Enter to go straight to it. A few quick steps show you how."] },
		(item and item ~= hearth) and { text = ns.Lower(item.name), pick = PickItem(item), title = L["Type to find"],
			say = L["Type a name and Terminal finds it as you type: here, something from your bags. The best match is selected (the highlighted row): Enter would open your bags and point at it."] }
		or { text = item and ns.Lower(item.name) or "hearthstone", pick = item and PickItem(item) or "hearthstone", title = L["Type to find"],
			say = L["Type a name and Terminal finds it as you type. The best match is selected (the highlighted row): Enter would take you to it, opening the right window and pointing at it."] },
		{ text = "map", pick = "category", title = L["Pick a category"],
			say = L["What's found is sorted into categories (windows, places, key bindings, settings...): Tab or a click opens one, Shift+Left goes back."] },
	}
	local function Add(s) steps[#steps + 1] = s end
	local setting = SettingText()
	Add({ text = setting, title = L["Find a setting"],
		pick = function(e) return (e.kind == "gameoptions" and type(e.name) == "string" and ns.Lower(e.name) == setting)
			or e.catId == "settings" end, -- (none: the first row)
		say = L["The game's options are found by name too (nameplates, the damage meter, class colors...): Enter opens the options window on the setting and points at it, no clicking through pages."] })
	local missing = {}
	for _, m in ipairs(MISSING) do if not HasAddon(m.name) then missing[#missing + 1] = m end end
	if HasAddon("Questie") then
		Add({ text = "nearest mailbox", pick = "first", title = L["The nearest of anything (Questie)"],
			say = L["With Questie, Terminal knows every NPC and quest: ask for the nearest mailbox, innkeeper, trainer or vendor, and each row says how far it is while an arrow points the way."] })
	end
	if HasAddon("AtlasLoot") then
		Add({ text = "upgrades", pick = function(e) return e.catId == "loot" or e.kind == "loot" end,
			title = L["Upgrades (AtlasLoot)"],
			say = L["With AtlasLoot, Terminal knows every dungeon's loot: upgrades lists gear you can get that beats what you wear, the biggest first, and its tooltip says why."] })
	end
	if HasAddon("Attune") then
		Add({ text = AttuneText(), pick = "first", title = L["Keys and attunements (Attune)"],
			say = L["With Attune, Terminal knows every attunement, key and dungeon quest line: ask how to get a key (here, Dalaran's) and its steps are listed in order, with the ones you've done."] })
	end
	if #missing == 1 then
		Add({ text = "", title = missing[1].title, say = missing[1].say })
	elseif #missing > 1 then
		local lines = { L["Install these addons and Terminal finds more:"] }
		for _, m in ipairs(missing) do lines[#lines + 1] = "- " .. m.line end
		Add({ text = "", title = L["More with addons"], say = table.concat(lines, "\n") })
	end
	-- (what to do with a kind of thing you have: Terminal finds which; else the Hearthstone)
	local line, fs = DoLine(every)
	if line then
		Add({ text = line, title = L["Say what to do"],
			pick = function(e) return e.itemID ~= nil and ns.Filters.Pass(e, fs) end,
			say = L["Say what to do and what kind of thing, not its name: Terminal finds what you have that fits (here, %s). Enter does it; right-click a row to see everything it can do."]:format(line) })
	else
		Add({ text = "use " .. (hearth and ns.Lower(hearth.name) or "hearthstone"), pick = "first", title = L["Say what to do"],
			say = L["Start with what you want to do: use, cast, equip, target. Enter does it. Right-click a row to see everything it can do."] })
	end
	Add({ text = "", title = L["That's it"],
		say = L["Press %s to open Terminal any time. F1 shows every key, .help what you can ask, and .tour shows this again."]:format(ToggleKey()) })
	return steps
end
T.STEPS = {} -- (made when the tour starts: your bags and the settings aren't read while the addon loads)

local tour -- { i = the step, picked = its row selected already }

local function Step() return tour and T.STEPS[tour.i] end

----------------------------------------------------------------------
-- The card above the terminal
----------------------------------------------------------------------

local card
local PAD, GAP = 12, 6

local function Card()
	if card then return card end
	local Theme = ns.Theme
	card = CreateFrame("Frame", "TerminalTourCard", UIParent, "BackdropTemplate")
	if ns.Zen then ns.Zen.Made(card) end -- (made while .zen has the interface faded: kept up, Zen.lua)
	card:SetFrameStrata("DIALOG")
	card:SetClampedToScreen(true)
	card:EnableMouse(false)
	card.head = card:CreateFontString(nil, "OVERLAY")
	card.head:SetFontObject(Theme.fonts.small)
	card.head:SetPoint("TOPLEFT", PAD, -PAD)
	card.head:SetJustifyH("LEFT")
	card.title = card:CreateFontString(nil, "OVERLAY")
	card.title:SetFontObject(Theme.fonts.input)
	card.title:SetPoint("TOPLEFT", card.head, "BOTTOMLEFT", 0, -4)
	card.title:SetJustifyH("LEFT")
	card.body = card:CreateFontString(nil, "OVERLAY")
	card.body:SetFontObject(Theme.fonts.row)
	card.body:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
	card.body:SetJustifyH("LEFT")
	card.body:SetJustifyV("TOP")
	if card.body.SetWordWrap then card.body:SetWordWrap(true) end
	card.keys = card:CreateFontString(nil, "OVERLAY")
	card.keys:SetFontObject(Theme.fonts.small)
	card.keys:SetPoint("TOPLEFT", card.body, "BOTTOMLEFT", 0, -10)
	card.keys:SetJustifyH("LEFT")
	return card
end
T.Card = function() return card end -- (tests)

--- The card shown for the step (nil: hidden).
local function ShowCard()
	local UI = ns.UI
	local s = Step()
	local frame = UI.frame
	if not (s and frame and frame:IsShown()) then
		if card then card:Hide() end
		return
	end
	local Theme = ns.Theme
	local t = Theme.Get()
	local c = Card()
	local function Scale(f)
		local ok, v = pcall(f.GetEffectiveScale, f)
		return ok and type(v) == "number" and v > 0 and v or 1
	end
	local scale = Scale(frame) / Scale(UIParent) -- (the terminal's own scale: the card is UIParent's)
	local fw = frame.GetWidth and frame:GetWidth()
	local w = math.max(260, (type(fw) == "number" and fw or 400) * scale)
	c:SetWidth(w)
	-- (above the terminal, else below it when there's no room above: clamped to the screen, it sat over the prompt;
	-- 0.51.21, the player's screenshot)
	c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	local r, g, b = Theme.RGB(t.bg)
	c:SetBackdropColor(r, g, b, 0.97)
	c:SetBackdropBorderColor(Theme.RGB(t.accent))
	c.head:SetText(L["Tour: step %d of %d"]:format(tour.i, #T.STEPS))
	c.head:SetTextColor(Theme.RGB(t.accent))
	c.title:SetText(s.title)
	c.title:SetTextColor(Theme.RGB(t.text))
	c.body:SetWidth(w - PAD * 2)
	c.body:SetText(s.say)
	c.body:SetTextColor(Theme.RGB(t.text))
	local last = tour.i >= #T.STEPS
	local keys = (last and L["Enter: close the tour"] or L["Enter: next"])
		.. (tour.i > 1 and ("     " .. L["Shift+Left: back"]) or "") .. "     " .. L["Esc: end the tour"]
	c.keys:SetText(keys)
	c.keys:SetTextColor(Theme.RGB(t.dim))
	local function H(fs, d)
		local ok, v = pcall(fs.GetStringHeight, fs)
		return ok and type(v) == "number" and v > 0 and v or d
	end
	local h = PAD + H(c.head, 12) + 4 + H(c.title, 16) + 6 + H(c.body, 30) + 10 + H(c.keys, 12) + PAD
	c:SetHeight(h)
	c:ClearAllPoints()
	local top = frame.GetTop and frame:GetTop()
	local screen = UIParent.GetTop and UIParent:GetTop()
	T.below = type(top) == "number" and type(screen) == "number" and (top * scale + GAP + h > screen) or false
	if T.below then c:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -GAP) else c:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, GAP) end
	c:Show()
end
T.ShowCard = ShowCard

----------------------------------------------------------------------
-- The steps
----------------------------------------------------------------------

--- Go to step i (the terminal open on it), or end the tour past the last one.
local function Go(i)
	local UI = ns.UI
	if i < 1 then i = 1 end
	if i > #T.STEPS then
		T.Stop()
		UI:Hide()
		return
	end
	tour = { i = i }
	local E = ns.Easy
	if E and not E.On() then E.tempSimple = true end -- (the tour is in Simple mode; Advanced again once it closes)
	local text = T.STEPS[i].text
	if UI:IsShown() then UI:SetOrResearch(text) else UI:Open(text) end
	T.Arrived()
	ShowCard()
end

function T.Start()
	T.STEPS = T.Steps() -- (which addons are there: now)
	if type(ns.db) == "table" then ns.db.tourOffered = true end -- (taken: not suggested again)
	Go(1)
end
function T.Next() if tour then Go(tour.i + 1) end end
function T.Back() if tour then Go(tour.i - 1) end end
function T.Stop()
	tour = nil
	if card then card:Hide() end
end
function T.Active() return tour ~= nil end
function T.StepIndex() return tour and tour.i end

--- The step's results are in: the row it's about selected (once: Up and Down are yours after).
function T.Arrived()
	local s = Step()
	if not s or tour.picked or not s.pick then return end
	local UI = ns.UI
	if UI.searchJob then return end -- (still searching: once it's done)
	-- (the step's own search: not the last step's rows, its search not started yet; review, 0.51.25)
	if UI.searchedText ~= s.text then return end
	tour.picked = true
	local at
	for i, e in ipairs(UI.results) do
		if not e.noActivate then
			if s.pick == "first" or (s.pick == "category" and e.catId)
				or (type(s.pick) == "function" and s.pick(e))
				or (type(s.pick) == "string" and type(e.name) == "string" and ns.Lower(e.name) == s.pick) then
				at = i
				break
			end
		end
	end
	if not at and type(s.pick) == "function" then -- (none of the kind it's about: the first)
		for i, e in ipairs(UI.results) do if not e.noActivate then at = i break end end
	end
	if at then
		UI.sel = at
		UI.offset = math.max(0, math.min(at - 1, #UI.results - (UI.layout and UI.layout.ROWS or 10)))
		UI:Render()
	end
end

--- A key while the tour is on: Enter goes on, Shift+Left back, Esc ends it (true: it was the tour's). Typing ends it
--- (the key does what it does); Up, Down, Tab and the like are the list's as ever.
local TYPED = { BACKSPACE = true, DELETE = true, SPACE = true }
function T.Key(key, shift)
	if not tour then return false end
	if key == "ENTER" or key == "NUMPADENTER" then T.Next() return true end
	if key == "ESCAPE" then T.Stop() ns.UI:Hide() return true end
	-- (in a category, Shift+Left is the list's: back to the categories, as step 3's card says; review, 0.51.25)
	if key == "LEFT" and shift then
		if ns.UI.category then return false end
		T.Back()
		return true
	end
	if TYPED[key] or (type(key) == "string" and #key == 1) then T.Stop() end
	return false
end

ns:RegisterCommand("tour", {
	desc = L["A quick tour of Terminal in a few short steps (Enter goes on, Esc ends it)"],
	aliases = { "intro", "tutorial" },
	run = function()
		-- (after this press is done: running a command closes the terminal first)
		C_Timer.After(0, T.Start)
		return {}
	end,
})
