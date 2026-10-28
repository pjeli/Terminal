local ns = select(2, ...)
local L = ns.L

-- Simple mode (the default; "easy" in the code: this file was Easy.lua, its table is still ns.Easy):
-- Terminal for players who'll never type @npc or q:rare+.
--   - Opens with nothing listed. Typing lists the categories that have it ("Items  Rumsey Rum +2 more",
--     "Emotes  /dance"), best match first; Enter, a click or Tab picks one, and only it is searched (Questie's
--     lists included). Shift+Left goes back to all of them; clearing the prompt lets the category go. Almost every list is
--     in some category, the ones hard mode only searches with their @kind too (emotes, slash commands,
--     console settings, Questie's quests and NPCs, your alts' bags); the mailboxes, the party's quests and the recipes
--     you don't know yet are reached by their questions ("nearest mailbox", "party quests", "recipes i'm missing").
--   - Everyday words act as filters: "rare sword", "epic", "boe", "ready", "todo", "innkeeper"
--     (a soft filter: a row passes the filter, or has the word in its name, so "Bound Fire" is still found).
--   - The footer says what Enter and Shift+Enter do for the selected row; no ghost completions of syntax.
--   - The first word can say what to do: use, cast, summon, equip, target, where, nearest (E.ACTIONS).
--   - .help in plain sentences. Advanced syntax (@kind, key:value, >> channel) isn't taken: a row on top says
--     it's Advanced mode's and offers the switch. .commands and /slash still run.
-- Advanced syntax typed in Simple mode is searched as typed, Simple mode kept (0.55.9; 0.54.1-0.55.8 it switched).
-- The empty prompt's faint examples (both modes, and the ones made for the character) are in Examples.lua.
-- What its words mean is beside it in Reading/: single words in Words.lua, phrases in PlainNumbers.lua (numbers, dates,
-- levels, orders), StepWords.lua (top N, comparisons) and Joins.lua (pairs, "not", "or"); .explain in Explain.lua.

local E = {}
ns.Easy = E

local Lower = ns.Lower

-- Alt+` (E.temp): Advanced mode for this one run of the terminal, Simple again once it closes. Holds what the
-- Simple prompt said ({ from = text, category = id }), given back to Down's recall afterwards.
E.temp = nil
-- Simple mode for this one run, for a player in Advanced mode: a result handed over from fuzzy finding with Enter
-- (UI:FuzzyPop). Ends with the terminal, like E.temp.
E.tempSimple = nil

--- Is easy mode on? It is unless the player chose hard mode (db.easyMode == false) or Alt+` made this run Advanced.
function E.On()
	if E.tempSimple or E.reading then return true end -- (reading: plain words printed as Advanced, ns.QueryToAdvanced)
	if E.temp then return false end
	local db = ns.db
	return not (db and db.easyMode == false)
end

--- Switch; the terminal searches again.
function E.Set(on)
	if not ns.db then return end
	E.temp, E.tempSimple = nil, nil
	ns.db.easyMode = on and true or false
	local UI = ns.UI
	if UI and UI.EasyChanged then UI:EasyChanged() end
end

----------------------------------------------------------------------
-- Categories: what a search's rows are sorted into
----------------------------------------------------------------------

local function IsEmote(e) return e.emote ~= nil end
E.IsEmote = IsEmote -- (Words.lua's action words: "do" keeps to emotes)
local function NotEmote(e) return e.emote == nil end

-- Each searches these kinds (provider ids; those not loaded are skipped, a category with none never shows),
-- and only the rows `keep` says yes to when it has one (one list, two categories: emotes and slash commands).
-- 0.48.4 (the player: "Game" held windows and keybindings while console settings had a category of their own; your
-- bags and your alts' were two): named for what you'd do with a result, not where Terminal gets it. Windows to open,
-- Settings to change, Commands to run; Items wherever they are; Dungeon loot (the loot tables) apart from Recent (what
-- dropped for you, how you died). `was` = the ids a category took over (a pick kept from before, another addon's
-- simpleCategory "game": E.BY_ID finds them).
E.CATEGORIES = {
	-- (0.55.16, the player: "separate out Items / inventory from Stored / bank & alts": two again, as before 0.48.4)
	{ id = "items", label = L["Items"], kinds = { "items" }, icon = "Interface\\Icons\\INV_Misc_Bag_08", was = { "bags" } },
	{ id = "stored", label = L["Bank & alts"], kinds = { "stored", "shared" }, icon = "Interface\\Icons\\INV_Misc_Bag_10", was = { "alts" } },
	{ id = "quests", label = L["Quests"], kinds = { "quests", "questie", "attune" }, icon = "Interface\\GossipFrame\\AvailableQuestIcon" },
	{ id = "spells", label = L["Spells"], kinds = { "spells", "talents", "training", "classspells" }, icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
	{ id = "crafting", label = L["Crafting"], kinds = { "professions", "recipes", "camp" }, icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ id = "npcs", label = L["NPCs"], kinds = { "npc" }, icon = "Interface\\Icons\\INV_Misc_Head_Human_01" },
	{ id = "places", label = L["Places"], kinds = { "maps", "dungeon", "raid", "flight", "corpse" }, icon = "Interface\\Icons\\INV_Misc_Map_01" },
	{ id = "loot", label = L["Dungeon loot"], kinds = { "loot" }, icon = "Interface\\Icons\\INV_Box_02" },
	{ id = "recent", label = L["Recent"], kinds = { "lootlog", "combatlog" }, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
		was = { "lootlog", "combat" } },
	{ id = "people", label = L["Guild & friends"], kinds = { "guild", "friends", "who" }, icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
	{ id = "group", label = L["Group"], kinds = { "group" }, icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude" },
	{ id = "collections", label = L["Collections"], kinds = { "mounts", "toys", "pets", "titles", "achievements" },
		icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
	{ id = "character", label = L["Character"],
		kinds = { "gold", "experience", "lockouts", "durability", "mail", "auctions", "reputation", "currency", "skills", "equipmentset" },
		icon = "Interface\\Icons\\INV_Misc_Book_09" },
	{ id = "calendar", label = L["Calendar"], kinds = { "calendar" }, icon = "Interface\\Icons\\INV_Misc_Note_06" },
	{ id = "windows", label = L["Windows"], kinds = { "panels" }, icon = "Interface\\Icons\\INV_Misc_Book_11" },
	{ id = "settings", label = L["Settings"], kinds = { "gameoptions", "keybinds", "cvars", "addons", "addonoptions", "terminal" },
		icon = "Interface\\Icons\\INV_Misc_Gear_01", was = { "game", "console" } },
	{ id = "commands", label = L["Commands"], kinds = { "slash", "macros" }, keep = NotEmote, icon = "Interface\\Icons\\INV_Misc_Note_01",
		was = { "slash" } },
	{ id = "emotes", label = L["Emotes"], kinds = { "slash" }, keep = IsEmote, icon = "Interface\\Icons\\Spell_Shadow_SoothingKiss" },
}
E.BY_ID = {}
for _, c in ipairs(E.CATEGORIES) do
	E.BY_ID[c.id] = c
	for _, old in ipairs(c.was or {}) do E.BY_ID[old] = E.BY_ID[old] or c end
end

--- A list another addon registers once Terminal has loaded (Terminal:RegisterProvider; docs/PROVIDERS.md): its
--- Simple-mode category (`simpleCategory`: an existing category's id, "game" say, or { id, label, icon } for a new one),
--- else Simple mode never shows its rows; and its verbs (`verbs`: { enter, shift }, or function(e) -> enter, shift) for
--- the footer and the right-click menu. Terminal's own lists are in E.CATEGORIES and E.VERBS already.
local byKind -- (kind -> the categories listing it, in order: E.CategoryOf; made again after E.Adopt)
function E.Adopt(p)
	if type(p) ~= "table" or type(p.id) ~= "string" then return end
	if p.verbs ~= nil and E.VERBS[p.id] == nil then E.VERBS[p.id] = p.verbs end
	local c = p.simpleCategory
	if type(c) == "string" then c = { id = c } end
	if type(c) ~= "table" or type(c.id) ~= "string" then return end
	local cat = E.BY_ID[c.id]
	if not cat then
		cat = { id = c.id, label = c.label or p.label or c.id, kinds = {}, icon = c.icon or "Interface\\Icons\\INV_Misc_QuestionMark" }
		E.CATEGORIES[#E.CATEGORIES + 1] = cat
		E.BY_ID[c.id] = cat
	end
	for _, k in ipairs(cat.kinds) do if k == p.id then return end end
	cat.kinds[#cat.kinds + 1] = p.id
	byKind = nil
end

--- The categories to sort into: every one with at least one of its kinds loaded.
function E.Visible()
	local out = {}
	for _, c in ipairs(E.CATEGORIES) do
		local any = false
		for _, id in ipairs(c.kinds) do
			if ns.providers[id] then any = true break end
		end
		if any then out[#out + 1] = c end
	end
	return out
end

--- The category a row belongs in (the first shown one listing its kind that keeps it), or nil. (Every category holding
--- a row's own list is shown: its list is loaded. Not E.Visible() made again per row: review, 0.53.6.)
--- (0.59.0, the stress test: tests/stress.py) The categories listing each kind, in order, made once (E.Adopt starts it
--- again): every category's every kind was walked for each match, 200,000 matches a frame of half a second in Simple
--- mode's overview.
local function ByKind()
	if not byKind then
		byKind = {}
		for _, c in ipairs(E.CATEGORIES) do
			for _, id in ipairs(c.kinds) do
				local list = byKind[id]
				if not list then list = {}; byKind[id] = list end
				list[#list + 1] = c
			end
		end
	end
	return byKind
end
--- The map made again (a category's lists changed some other way than E.Adopt).
function E.Reindex() byKind = nil end
function E.CategoryOf(e)
	if not e or not e.kind then return nil end
	local list = ByKind()[e.kind]
	for i = 1, list and #list or 0 do
		local c = list[i]
		if not c.keep then return c.id end
		local ok, yes = pcall(c.keep, e)
		if ok and yes then return c.id end
	end
end

--- The category every row of this kind goes to, when that doesn't hang on the row (its first category keeps them all);
--- else nil (CategoryOf, row by row). For the overview: a kind's 50,000 rows looked up once (0.63.7, review).
function E.FixedCategory(kind)
	local list = kind and ByKind()[kind]
	local c = list and list[1]
	if c and not c.keep then return c.id end
	return nil
end

--- The kinds a category searches, as a set (nil for an unknown one).
function E.Kinds(id)
	local c = E.BY_ID[id or ""]
	if not c then return nil end
	local set = {}
	for _, k in ipairs(c.kinds) do
		if ns.providers[k] then set[k] = true end
	end
	return set
end

----------------------------------------------------------------------
-- What Enter and Shift+Enter do, in words, for the selected row
----------------------------------------------------------------------

-- What Enter and Shift+Enter do, by kind: { Enter's, Shift+Enter's }, or a function(e) giving both (rows of one kind
-- that differ: a worn item, a passive spell, an addon with a minimap button...). Shift+Enter's is said only when the
-- row has a Shift+Enter (E.Verbs). Printing in your own chat window is "show in chat" everywhere; the game's chat box
-- is "put in the chat box", or "link in chat" when it carries a link.
--- An item's, and gear's alike (0.45.21: equipment found with @item does what @gear's does, Items.lua GearActions): a
--- bag piece of equipment equips, a worn one is used only when it has a use (nothing to equip: no Shift+Enter).
local function ItemVerbs(e)
	local enter = e.slotId and L["show on character"] or L["show in bags"]
	if e.equipLoc then
		if e.slotId then return enter, e.onUse and L["use"] or nil end
		return enter, L["equip"]
	end
	return enter, L["use"]
end
local function SpellVerbs(e)
	return L["show in spellbook"], (not e.passive) and L["cast"] or nil
end
local function TalentVerbs(e)
	return e.other and L["Wowhead link"] or L["show in talents"], L["link in chat"]
end
local function AddonVerbs(e)
	local shift = L["turn on/off"]
	if e.launch then return L["open"], shift end -- (its minimap button)
	if e.opt then return L["options"], shift end
	return L["show in AddOn list"], shift
end
local function WhoVerbs(e)
	if e.lead then return L["ask the server"], nil end
	return L["whisper"], L["invite"]
end
local function TerminalVerbs(e)
	return e.presetId and L["apply"] or L["open"]
end
local function SourceVerbs(e) -- (a chain's source: a vein or chest at its spot, else the item crafted)
	if e.found or e.pipeHow == L["gathered from"] then return L["show on map"], L["set waypoint"] end -- (a recipe's chest too)
	return L["show in bags"]
end
local function QuestVerbs(e) -- (one to drop: grey, or in a zone left behind, QuestDrop.lua)
	return L["show in quest log"], e.drop and L["drop"] or L["track"]
end
local function MailVerbs(e) -- (your own mail at an open mailbox: pointed at in the inbox; Mail.lua)
	local open = e.mailKind == "mail" and e.mine and ns.Mail and ns.Mail.open
	return open and L["show in inbox"] or L["show in chat"], L["nearest mailbox"]
end
local function AuctionVerbs(e) -- (the auction house's news: as mail; an auction up now: Auctions.lua)
	if e.mailKind == "auction" then return MailVerbs(e) end
	return L["show in chat"], L["put in the chat box"]
end
-- (a worn piece: the character window; one in your bags: the bags; the whole bill: chat. Shift+Enter: the nearest repair)
local function DurabilityVerbs(e)
	local enter = (e and e.duraKind == "total" and L["show in chat"]) or (e and e.dura and e.dura.bag and L["show in bags"])
		or L["show on character"]
	return enter, L["nearest repair"]
end
-- (an on/off setting: Shift+Enter turns it on or off; other settings only open)
local function AddonOptionVerbs(e)
	return L["open its options"], (e and e.opt and e.opt.toggle) and L["turn on or off"] or nil
end
local function LockoutVerbs(e) -- (your own: the game's lockout link; an alt's: in words, Lockouts.lua)
	return L["show in chat"], (e.mine and not e.world) and L["link in chat"] or L["put in the chat box"]
end
local function GroupVerbs(e) -- (Shift+Enter: your buff they're missing, when you have one: Group.lua)
	return L["target"], e.buffWith and L["cast %s"]:format(e.buffWith) or nil
end
local PLACE = { L["show on map"], L["set waypoint"] }
-- (0.49.2, review: a zone only moves a waypoint you have, Maps.lua's PinOnly: "set waypoint" was said with none set)
local function MapVerbs(e) return L["show on map"], ns.Maps and ns.Maps.PinVerb(e) or nil end
local TO_CHAT = { L["show in chat"], L["put in the chat box"] } -- ("put in the chat box", "link in chat": RowMenu.lua compares them, translated alike)
E.VERBS = {
	items = ItemVerbs, consumables = ItemVerbs, mats = ItemVerbs, gear = ItemVerbs, reagent = { L["show in bags"] },
	source = SourceVerbs,
	stored = { L["show in bags"], L["show in chat"] }, bank = { L["show in bags"], L["show in chat"] }, shared = { L["whisper"], L["show in chat"] }, lootlog = { L["show in bags"], L["link in chat"] },
	loot = { L["show in AtlasLoot"], L["link in chat"] },
	history = { L["search it again"] }, -- (a line you ran: Providers/History.lua)
	buyback = { L["buy back"], L["link in chat"] }, -- (what you sold: Providers/Buyback.lua; away from a vendor it says where)
	mail = MailVerbs, auctions = AuctionVerbs, group = GroupVerbs, lockouts = LockoutVerbs, durability = DurabilityVerbs,
	calendar = { L["show in calendar"], L["put in the chat box"] },
	combatlog = TO_CHAT, gold = TO_CHAT, experience = TO_CHAT, calc = TO_CHAT,
	spells = SpellVerbs, talents = TalentVerbs,
	npc = { L["show on map"], L["target"] },
	maps = MapVerbs, dungeon = PLACE, raid = PLACE, corpse = PLACE, mailbox = PLACE, forge = PLACE, anvil = PLACE,
	cookingfire = PLACE, moonwell = PLACE, object = PLACE, flight = PLACE,
	guild = { L["whisper"], L["invite"] }, friends = { L["whisper"], L["invite"] }, who = WhoVerbs,
	questie = { L["Wowhead link"], L["show in game"] },
	attune = { L["show in Attune"], L["put in the chat box"] },
	-- (TrainerSpells' rows, What's Training not there: Enter lists who teaches it, Shift+Enter links it; 0.57.2)
	training = function(e)
		if rawget(e, "fromTrainerSpells") then return L["who teaches it"], L["link in chat"] end
		return L["show in What's Training"], L["who teaches it"]
	end,
	classspells = { L["Wowhead link"], L["link in chat"] },
	addonoptions = AddonOptionVerbs,
	quests = QuestVerbs,
	missing = { L["where to learn"], L["link in chat"] }, -- (a recipe you don't know yet: MissingRecipes.lua)
	toys = { L["use"], L["show in journal"] }, pets = { L["summon"], L["show in journal"] }, mounts = { L["summon"], L["show in journal"] },
	titles = { L["wear"] },
	achievements = { L["show"], L["link in chat"] },
	professions = { L["open"], L["link in chat"] }, recipes = { L["show recipe"], L["link in chat"] },
	addons = AddonVerbs,
	camp = { L["show recipe"], L["make / use"] },
	slash = { L["run"], L["put in the chat box"] }, emote = { L["do it"], L["put in the chat box"] },
	cmd = { L["run"] }, advanced = { L["switch to Advanced mode"] }, send = { L["send"] },
	equipmentset = { L["equip"], L["show in manager"] },
	macros = { L["run"], L["show in Macros"] },
	cvars = { L["edit"], L["reset to default"] },
	reputation = { L["show"], L["watch"] },
	skills = { L["show"], L["show in chat"] },
	currency = { L["show"] }, panels = { L["open"] },
	gameoptions = { L["show in options"] }, keybinds = { L["show in keybindings"], L["quick keybind mode"] },
	terminal = TerminalVerbs,
}

--- The two verbs for a row: Enter's, and Shift+Enter's (nil when it has none).
function E.Verbs(e)
	if not e or e.noActivate then return nil end
	if e.catId then return L["look in %s"]:format(tostring(e.name)) end
	-- a chain's row: Enter walks on, Shift+Enter does what the row's own Enter does
	local nxt = rawget(e, "pipeNext")
	if nxt then
		return nxt == "sources" and L["where to get it"] or L["its mats"], (E.Verbs(rawget(e, "pipeOf"))) or L["open"]
	end
	if e.completion then return e.kind == "pipe" and L["pick it"] or L["search there"] end
	if e.actionVerb then return e.actionVerb, nil end -- (as given: a translated verb may hold capitals, "im Chat verlinken")
	local v = E.VERBS[(e.emote and "emote") or e.kind or ""]
	local enter, shift
	if type(v) == "function" then enter, shift = v(e)
	elseif v then enter, shift = v[1], v[2]
	else shift = L["more"] end -- (a kind without verbs)
	if not (e.secondary or e.secondarySecure) then shift = nil end -- (no Shift+Enter: none said)
	return enter or L["open"], shift
end

----------------------------------------------------------------------
-- An action word's row: Enter does what the word says (the words themselves: Words.lua's E.ACTIONS)
----------------------------------------------------------------------

local Never = ns.Never

--- A row as the action wants it: its Shift+Enter action made its Enter (a view on the row, which stays as it is);
--- rows whose usual action is the one wanted come back as they are.
local function LinkText(e) return ns.Share and ns.Share.Text(e) or e.name end
local LINK_SPEC = ns.ChatBoxSpec(LinkText) -- (the game opens the chat box with the row's link: Core.lua)
local function LinkNow(e) ns.LinkInChat(LinkText(e)) end -- (combat: Terminal's own)

function E.ActionView(e, act)
	local how = act.map and act.map[e.kind]
	if how == "l" then
		return setmetatable({ secure = LINK_SPEC, isOpen = Never, after = false, activate = LinkNow, actionVerb = act.verb or Lower(act.label),
			actionOf = e }, { __index = e })
	end
	if how ~= "s" or not (e.secondary or e.secondarySecure) then return e end
	return setmetatable({
		secure = e.secondarySecure or false, isOpen = e.secondaryIsOpen or Never, after = e.secondaryAfter or false,
		activate = e.secondary or false, actionVerb = act.verb or Lower(act.label), actionOf = e, -- (false: never the row's own Enter)
	}, { __index = e })
end

----------------------------------------------------------------------
-- Alt+`: what a Simple search says, written in Advanced mode's syntax
----------------------------------------------------------------------


-- (the lists the rows shown come from: Printers.lua's, which Alt+` names)
E.ShownKinds = ns.ShownKinds

--- A plain-word question or chain as Advanced mode writes it: Questions.lua's one list of them (Scan.ANSWERS), read
--- at run time.
local function QuestionToAdvanced(text) return ns.QuestionToAdvanced and ns.QuestionToAdvanced(text) end
E.QuestionToAdvanced = QuestionToAdvanced

--- Simple mode's words as Advanced mode writes them (Alt+`): Search.lua's ns.LineToAdvanced, the one printer.
function E.ToAdvanced(text, category, shown, noGroup)
	return ns.LineToAdvanced(text, category, shown, noGroup)
end

----------------------------------------------------------------------
-- Advanced mode's syntax in Simple mode: not taken, the player is told where it lives
----------------------------------------------------------------------

--- Is this word Advanced mode's syntax (an @kind, a key:value filter, >>)? (The lexer's test, Lex.lua: what it calls a
--- syntax or op token.)
function E.IsAdvancedWord(w)
	return ns.Lex.IsAdvanced(w)
end

----------------------------------------------------------------------
-- One mode (0.54.1, the player's call: "we don't need .simple and .advanced anymore; we just start simple and have it
-- switch to advanced when syntax is used"): Simple mode; since 0.55.9 (the player: "keep them in simple mode as much
-- as we can") a line with Advanced syntax is searched as typed in Simple mode, no switch. Alt+` writes the line as
-- Advanced syntax (closed, nothing: 0.57.0); Alt+` again or Shift+Left brings the Simple words back. db.easyMode == false (Advanced for good) is no longer
-- offered, and a saved one from before is dropped at load (Core.lua).
----------------------------------------------------------------------

ns:RegisterCommand("fuzzy", {
	desc = L["Pure fuzzy finding, this once (.fzf too; also Tab+`: hold Tab, press `): every list, by name only; Enter takes the result back to the search, Shift+Enter with its list named (@kind name)"],
	aliases = { "fzf" },
	run = function(args)
		-- (after this press is done: running a command closes the terminal first)
		C_Timer.After(0, function() ns.UI:FuzzyOnce(args) end)
		return {}
	end,
})

--- .help in Simple mode: plain sentences.
function E.HelpLines()
	return {
		L["Terminal: type the name of anything (an item, a quest, a spell, a mount, a place, an NPC, an emote) and press Enter to open it."],
		L["Typing lists where it was found (Items, Quests, Settings, Emotes...): pick one with Enter, Tab or a click, then the thing itself; something named exactly what you typed comes first, to open at once. Shift+Left goes back to all of them (and back from wherever Enter took you)."],
		L["Start with what to do: use, cast, summon, equip, wear, target, where, nearest (\"use hearthstone\", \"nearest innkeeper\")."],
		L["Shift+Enter does the other thing (use the item, cast the spell, target the NPC); the footer says which. Right-click a row, or press Shift+Right, for all it can do; the speaker button under the prompt sends or copies every result at once (\"All 8 to party\")."],
		L["Words like rare, epic, boe, food, potion, stamina, ready, todo, vendor, trainer narrow the search: \"stamina food\", \"vendor ratchet\" (a place's NPCs)."],
		L["Ask where to go: \"where should i level\", \"what dungeon should i do\", \"where should i fish\" (or \"zones for level 35\")."],
		L["Flight paths you haven't learned: \"nearest unlearned flight master\", \"unlearned flight paths\" (a flight master's map tells Terminal which you know)."],
		L["\"or\" and \"not\" work too: \"sword or axe\", \"rare ring not boe\", \"potion not minor\"."],
		L["Put words in quotes to find them together, as they are: \"outlaw saber\" finds the Outlaw Saber, not every name with both words."],
		L["Down on an empty prompt brings back your last search; Up goes through what you ran before. Esc closes."],
		L["Ask \"what should i do\": gear to repair, junk to sell, spells to train, a class quest, quests to turn in, a dungeon for your level. Enter searches for the one you pick."],
		L["Alt+` turns what you typed into Advanced mode's command line; Alt+` again, or Shift+Left, brings your words back (Simple again once it closes)."],
		L["Tab+` (hold Tab, press `; or .fuzzy / .fzf) is pure fuzzy finding: every list at once, by name only. Enter takes the result back here, Shift+Enter with its list named (@npc Hogger)."],
		L["Ask about your fights: \"what killed me\", \"who crit me\", \"my biggest crit\" (what Terminal saw in the combat log)."],
		L["Spells you haven't put anywhere: \"spells not on my bars\" (not on any bar or key; passives left out)."],
		L["With What's Training or TrainerSpells, any class's spells, known or not: \"travel form\", \"healing wave\", \"druid spells\", \"upcoming spells\" (the level each rank is learned at). \"spellid claw\" gives a spell's id to copy, \"spellid 1082\" the spell. Talents by what they do: \"healing talents\", \"shaman crit talents\"."],
		L["Recipes you don't have yet: \"blacksmithing recipes i'm missing\" lists them with the skill each needs and how it's learned (trainer and cost, vendor and limited supply, a drop, a quest); \"recipes i can learn now\" only those your skill allows."],
		L["Clean out your quest log: \"quests to drop\" lists the grey ones and those in zones you've left behind. Shift+Enter drops one (Terminal asks first); \"Drop all\" on top, or right-click, drops them together after you've seen the list."],
		L["Your group: \"who is dead\", \"who needs fortitude\", \"who is out of range\", \"group healers\", \"missing buffs\", \"missing consumables\" (Enter targets them, Shift+Enter casts your buff on them; the speaker button's All to party says what's missing in one line)."],
		L["Quests with your party: \"party quests\" (who is on each of yours; Enter shares it), \"quests to share\" (the ones someone lacks); the speaker button's All to party says them in one line."],
		L["Your mail on every character, as Terminal last saw it: \"my mail\", \"mail running out\", \"cod mail\", \"mail from bob\" (who sent it, gold, COD, what's attached, when it runs out). Open a mailbox once on each character. \"sent mail\" shows what you sent in the last hour, and \"incoming mail\" the auction house's news on its way (sold, won, outbid, expired)."],
		L["Your auctions: \"my auctions\", \"what am i selling\", \"auctions sold\": what each character has on the auction house as Terminal saw it posted, with its price and time left, and the auction house's news."],
		L["Your lockouts on every character: \"my lockouts\", \"raid lockouts\", \"am i saved\" (bosses down and when each resets; Enter names the bosses)."],
		L["With Attune: \"my attunements\", \"raid attunements\", \"my keys\", \"class quests\" (how far along you are, and your next step); \"how do i get into mc\" or \"steps for molten core\" lists the steps first to last. Enter opens Attune on it."],
		L["With What's Training or TrainerSpells: \"what can i train\", \"what do i learn next level\", \"spells at level 30\", \"how much is training\" (every spell you've still to learn, when, and what it costs); \"where to learn fireball\" or \"dagger trainer\" lists who teaches it, the nearest first; Enter on a trainer shows them on the map."],
		L["After a death: \"where is my body\" shows your corpse (how far, the arrow pointing at it) and the nearest spirit healers; \"nearest spirit healer\" on its own too. Enter opens the map on it."],
		L["Your gear's wear: \"durability\", \"repair cost\", \"what needs repair\", \"broken gear\" (each piece's durability and what repairing it costs, the whole bill on top; Shift+Enter finds the nearest repair vendor)."],
		L["Other addons' settings: type what a setting is called (\"questie map icons\") to find it in any addon that uses Ace3's options; Enter opens that addon's options on it, Shift+Enter turns an on/off setting on or off."],
		L["The calendar: \"holidays\", \"what's on this week\", \"today\", \"next darkmoon faire\", \"my invites\", \"guild events\" (Enter opens it in the calendar)."],
		L["Level a profession: \"blacksmithing plan\" or \"level blacksmithing\" lists the recipes that still give skill by how many times your materials make each (bags and bank, and with your alts); the footer says about how many points they'd give."],
		L["Follow the chain: \"mats for thorium belt\", \"what uses copper bar\", \"where to get thorium bar\", \"where to learn thorium belt\" (its recipe, or a trainer). Enter on a row goes one step further, Shift+Enter opens it."],
		L["Find guildies by what they do: \"guild blacksmith\", \"guild priest online\" (Enter whispers them, Shift+Enter invites)."],
		L["Gear: upgrades lists what you can get that beats what you wear, the biggest first, and its tooltip says why; quest upgrades lists the quests whose reward is one (with Questie). .weights shows how they're judged and picks your talent tree (.weights arms, .weights resto), or sets your own weights (.weights set, or a Pawn scale string)."],
		L["When a list changes while you look at it (your bags as you loot, item data coming in), it stays put and the footer says so: F5 shows the new one."],
		L["Alt+click an item (or a spell, quest, achievement) in chat to look it up here."],
		L["Copy what you found, to paste outside the game: add \"to csv\" or \"to text\" (\"linen to csv\"). Every result opens in a box; Ctrl+C copies it and closes the box."],
		L["Ctrl+Enter does it and keeps the terminal open (for things that don't open a window)."],
		L["F1 (or .keybinds) shows every key, for each mode; Esc there brings you back."],
		L["Commands start with a dot: .options, .theme, .weights, .zen, .changelog... (type a dot to see them all)."],
		L["Make your own: .alias rep durability makes .rep show your durability (any search, a /slash command or another .command; .alias lists yours, .unalias rep forgets one)."],
		L["New here? .tour shows Terminal in a few short steps."],
		L["The bar under the prompt narrows, sorts and groups what's found: Filter, Sort and Group (Alt+F, Alt+S, Alt+G open them, Up/Down and Enter pick); the speaker button sends or copies every result."],
		L["Advanced syntax (@kinds, key:value filters, sort:name, sending to chat) works right here as you type it: your words stay as they are, and the bar under the prompt shows what it picks; .help advanced lists it all."],
	}
end


-- Terminal's own lists registered before this file loaded (RegisterProvider adopts only once Easy exists): their own
-- verbs and Simple mode categories (`verbs`, `simpleCategory`: another addon's list registered early)
for _, id in ipairs(ns.providerOrder or {}) do E.Adopt(ns.providers[id]) end
