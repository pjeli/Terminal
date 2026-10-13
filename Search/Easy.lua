local ns = select(2, ...)
local L = ns.L

-- Simple mode (the default; "easy" in the code): Terminal for players who'll never type @npc or q:rare+.
--   - Opens with nothing listed. Typing lists the categories that have it ("Items  Rumsey Rum +2 more",
--     "Emotes  /dance"), best match first; Enter, a click or Tab picks one, and only it is searched (Questie's
--     lists included). Shift+Left goes back to all of them; clearing the prompt lets the category go. Every list is
--     in some category, the ones hard mode only searches with their @kind too (emotes, slash commands,
--     console settings, Questie's quests and NPCs, your alts' bags).
--   - Everyday words act as filters: "rare sword", "epic", "boe", "ready", "todo", "innkeeper"
--     (a soft filter: a row passes the filter, or has the word in its name, so "Bound Fire" is still found).
--   - The footer says what Enter and Shift+Enter do for the selected row; no ghost completions of syntax.
--   - The first word can say what to do: use, cast, summon, equip, target, where, nearest (E.ACTIONS).
--   - .help in plain sentences. Advanced syntax (@kind, key:value, >> channel) isn't taken: a row on top says
--     it's Advanced mode's and offers the switch. .commands and /slash still run.
-- `.advanced` (after a confirmation) switches to the full command line; `.simple` comes back.
-- The empty prompt's faint examples (both modes, and the ones made for the character) are in Examples.lua.

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
	if E.tempSimple then return true end
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
local function NotEmote(e) return e.emote == nil end

-- Each searches these kinds (provider ids; those not loaded are skipped, a category with none never shows),
-- and only the rows `keep` says yes to when it has one (one list, two categories: emotes and slash commands).
-- 0.48.4 (the player: "Game" held windows and keybindings while console settings had a category of their own; your
-- bags and your alts' were two): named for what you'd do with a result, not where Terminal gets it. Windows to open,
-- Settings to change, Commands to run; Items wherever they are; Dungeon loot (the loot tables) apart from Recent (what
-- dropped for you, how you died). `was` = the ids a category took over (a pick kept from before, another addon's
-- simpleCategory "game": E.BY_ID finds them).
E.CATEGORIES = {
	{ id = "items", label = L["Items"], kinds = { "items", "stored" }, icon = "Interface\\Icons\\INV_Misc_Bag_08", was = { "bags", "alts" } },
	{ id = "quests", label = L["Quests"], kinds = { "quests", "questie" }, icon = "Interface\\GossipFrame\\AvailableQuestIcon" },
	{ id = "spells", label = L["Spells"], kinds = { "spells", "talents" }, icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
	{ id = "crafting", label = L["Crafting"], kinds = { "professions", "recipes", "camp" }, icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ id = "npcs", label = L["NPCs"], kinds = { "npc" }, icon = "Interface\\Icons\\INV_Misc_Head_Human_01" },
	{ id = "places", label = L["Places"], kinds = { "maps", "dungeon", "raid", "flight" }, icon = "Interface\\Icons\\INV_Misc_Map_01" },
	{ id = "loot", label = L["Dungeon loot"], kinds = { "loot" }, icon = "Interface\\Icons\\INV_Box_02" },
	{ id = "recent", label = L["Recent"], kinds = { "lootlog", "combatlog" }, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
		was = { "lootlog", "combat" } },
	{ id = "people", label = L["Guild & friends"], kinds = { "guild", "friends", "who" }, icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
	{ id = "group", label = L["Group"], kinds = { "group" }, icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude" },
	{ id = "collections", label = L["Collections"], kinds = { "mounts", "toys", "pets", "titles", "achievements" },
		icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
	{ id = "character", label = L["Character"],
		kinds = { "gold", "experience", "lockouts", "mail", "auctions", "reputation", "currency", "skills", "equipmentset" },
		icon = "Interface\\Icons\\INV_Misc_Book_09" },
	{ id = "windows", label = L["Windows"], kinds = { "panels" }, icon = "Interface\\Icons\\INV_Misc_Book_11" },
	{ id = "settings", label = L["Settings"], kinds = { "gameoptions", "keybinds", "cvars", "addons", "terminal" },
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

--- The category a row belongs in (the first shown one listing its kind that keeps it), or nil.
function E.CategoryOf(e)
	if not e or not e.kind then return nil end
	for _, c in ipairs(E.Visible()) do
		for _, id in ipairs(c.kinds) do
			if id == e.kind then
				local ok, yes = true, true
				if c.keep then ok, yes = pcall(c.keep, e) end
				if ok and yes then return c.id end
			end
		end
	end
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
-- Everyday words: filters without the key:value
----------------------------------------------------------------------

E.WORDS = {
	poor = "q:poor", junk = "q:poor", grey = "q:poor", gray = "q:poor", common = "q:common", uncommon = "q:uncommon",
	rare = "q:rare", epic = "q:epic", legendary = "q:legendary",
	boe = "is:boe", soulbound = "is:soulbound", bound = "is:soulbound",
	usable = "is:usable", equippable = "is:equippable", craftable = "is:craftable",
	ready = "is:ready", passive = "is:passive", capped = "is:capped", unplaced = "is:unplaced",
	done = "is:done", completed = "is:done", finished = "is:done", earned = "is:done",
	todo = "is:todo", unfinished = "is:todo", unearned = "is:todo",
	-- consumables and stats: "stamina food", "agility elixir", "mana potion"
	food = "type:food", drink = "type:drink", potion = "type:potion", potions = "type:potion", elixir = "type:elixir",
	elixirs = "type:elixir", flask = "type:flask", bandage = "type:bandage", bandages = "type:bandage", scroll = "type:scroll",
	stamina = "stat:stamina", strength = "stat:strength", agility = "stat:agility", intellect = "stat:intellect",
	spirit = "stat:spirit", armor = "stat:armor",
	-- (two words that mean one thing: SearchText joins them first)
	["attack power"] = "stat:ap", ["spell power"] = "stat:sp", ["spell damage"] = "stat:sp", ["mana regen"] = "stat:mp5",
	["healing power"] = "stat:healing", crit = "stat:crit", mp5 = "stat:mp5",
	["weapon damage"] = "stat:weapondamage",
	-- gear that suits you: your level, your class, near what you wear there or better (strict: HARD_WORDS)
	upgrade = "is:upgrade", upgrades = "is:upgrade",
	-- recipes that still give skill (orange and yellow; strict: HARD_WORDS)
	skillup = "is:skillup", skillups = "is:skillup", ["skill up"] = "is:skillup", ["skill ups"] = "is:skillup",
	online = "is:online", offline = "is:offline",
	-- your mail (Mail.lua): "cod", "expiring", "unread"
	cod = "is:cod", expiring = "is:expiring", unread = "is:unread",
	-- what an item is and where it's worn: "shield", "plate", "boots", "ring"
	shield = "type:shield", shields = "type:shield", sword = "type:sword", swords = "type:sword", axe = "type:axe",
	axes = "type:axe", mace = "type:mace", maces = "type:mace", dagger = "type:dagger", daggers = "type:dagger",
	staff = "type:stave", staves = "type:stave", bow = "type:bow", bows = "type:bow", gun = "type:gun", guns = "type:gun",
	crossbow = "type:crossbow", wand = "type:wand", wands = "type:wand", polearm = "type:polearm",
	cloth = "type:cloth", leather = "type:leather", mail = "type:mail", plate = "type:plate",
	head = "slot:head", helm = "slot:helm", helmet = "slot:helmet", neck = "slot:neck", necklace = "slot:necklace",
	amulet = "slot:amulet", shoulder = "slot:shoulder", shoulders = "slot:shoulders", back = "slot:back",
	cloak = "slot:cloak", cape = "slot:cape", chest = "slot:chest", robe = "slot:robe", wrist = "slot:wrist",
	bracers = "slot:bracers", hands = "slot:hands", gloves = "slot:gloves", waist = "slot:waist", belt = "slot:belt",
	legs = "slot:legs", pants = "slot:pants", leggings = "slot:leggings", feet = "slot:feet", boots = "slot:boots",
	ring = "slot:ring", rings = "slot:rings", trinket = "slot:trinket", trinkets = "slot:trinkets", offhand = "slot:offhand",
	-- NPC roles, and the everyday names for them ("nearest repair", "nearest fp", "nearest ah")
	repair = "is:repair", repairs = "is:repair", inn = "is:inn", bank = "is:bank", flight = "is:flight",
	fp = "is:flight", ah = "is:auctioneer", auction = "is:auctioneer", stable = "is:stablemaster",
	vendor = "is:vendor", vendors = "is:vendor", trainer = "is:trainer", trainers = "is:trainer",
	innkeeper = "is:innkeeper", banker = "is:banker", auctioneer = "is:auctioneer",
	flightmaster = "is:flightmaster", stablemaster = "is:stablemaster", questgiver = "is:questgiver",
	-- PvP NPCs: only the real ones ("nearby battlemaster", "nearest pvp vendor", "honor vendor")
	battlemaster = "is:battlemaster", battlemasters = "is:battlemaster",
	["pvp vendor"] = "is:pvpvendor", ["pvp vendors"] = "is:pvpvendor", ["honor vendor"] = "is:pvpvendor",
	["honor vendors"] = "is:pvpvendor", ["pvp quartermaster"] = "is:pvpvendor", pvp = "is:pvp",
	-- flight paths, and whether you know them ("unlearned flight paths", "nearest unlearned flight master": Flights.lua)
	["flight path"] = "is:flightpath", ["flight paths"] = "is:flightpath", flightpath = "is:flightpath",
	flightpaths = "is:flightpath", ["flight point"] = "is:flightpath", ["flight points"] = "is:flightpath", taxi = "is:flightpath",
	unlearned = "is:unlearned", missing = "is:unlearned", undiscovered = "is:unlearned", unknown = "is:unlearned",
	learned = "is:learned", known = "is:learned", discovered = "is:learned",
}

-- The game's own words for them (0.47.12, translations: the client's language). Quality, slot, weapon and armour
-- kinds, roles, standings, classes and professions already come from the client in every language: "selten" is
-- q:rare on a German client, "Rücken" slot:back, "Einhandschwerter" type:sword, "Heiler" is:healer, "Ehrfürchtig"
-- standing:8, "Krieger" and "Bergbau" their trainers. Only for another language than English (English has its own
-- words above), made the first time one is asked for (the game's globals are there by then); a row passes one when
-- the filter says so or its name or text has the word, as the word alone found before.
local SLOT_GLOBALS = {
	INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back",
	INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest", INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands",
	INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "finger",
	INVTYPE_TRINKET = "trinket", INVTYPE_SHIELD = "shield", INVTYPE_2HWEAPON = "two-hand", INVTYPE_WEAPON = "one-hand",
	INVTYPE_WEAPONMAINHAND = "main hand", INVTYPE_WEAPONOFFHAND = "off hand", INVTYPE_HOLDABLE = "off hand",
	INVTYPE_RANGED = "ranged",
	HEADSLOT = "head", NECKSLOT = "neck", SHOULDERSLOT = "shoulder", BACKSLOT = "back", CHESTSLOT = "chest",
	WRISTSLOT = "wrist", HANDSSLOT = "hands", WAISTSLOT = "waist", LEGSSLOT = "legs", FEETSLOT = "feet",
	FINGER0SLOT = "finger", TRINKET0SLOT = "trinket", MAINHANDSLOT = "main hand", SECONDARYHANDSLOT = "off hand",
}
-- the professions by skill line (C_TradeSkillUI.GetTradeSkillDisplayName) and a spell named like them, trainer: words
local PROF_LINES = { { 171, 2259, "alchemy" }, { 164, 2018, "blacksmithing" }, { 333, 7411, "enchanting" },
	{ 202, 4036, "engineering" }, { 182, 2366, "herbalism" }, { 165, 2108, "leatherworking" }, { 186, 2575, "mining" },
	{ 393, 8613, "skinning" }, { 197, 3908, "tailoring" }, { 185, 2550, "cooking" }, { 129, 3273, "firstaid" },
	{ 356, 7620, "fishing" } }
local CLASS_WORDS = { WARRIOR = "warrior", PALADIN = "paladin", HUNTER = "hunter", ROGUE = "rogue", PRIEST = "priest",
	SHAMAN = "shaman", MAGE = "mage", WARLOCK = "warlock", DRUID = "druid" }
-- NPC roles by the minimap's tracking menu's names ("Gastwirt", "Aubergiste": "nächster Gastwirt" finds the innkeeper)
local NPC_ROLE_GLOBALS = { MINIMAP_TRACKING_INNKEEPER = "is:innkeeper", MINIMAP_TRACKING_BANKER = "is:banker",
	MINIMAP_TRACKING_AUCTIONEER = "is:auctioneer", MINIMAP_TRACKING_FLIGHTMASTER = "is:flightmaster",
	MINIMAP_TRACKING_REPAIR = "is:repair", MINIMAP_TRACKING_STABLEMASTER = "is:stablemaster",
	MINIMAP_TRACKING_BATTLEMASTER = "is:battlemaster", MINIMAP_TRACKING_TRAINER_CLASS = "is:classtrainer",
	MINIMAP_TRACKING_TRAINER_PROFESSION = "is:proftrainer", MERCHANT = "is:vendor" }
-- the game's words that name someone you'd walk to (E.ROLE_WORDS: "nearest" then keeps to NPCs friendly to you)
local ROLE_SPECS = { ["is:innkeeper"] = true, ["is:banker"] = true, ["is:auctioneer"] = true, ["is:flightmaster"] = true,
	["is:repair"] = true, ["is:stablemaster"] = true, ["is:battlemaster"] = true, ["is:classtrainer"] = true,
	["is:proftrainer"] = true, ["is:vendor"] = true }
local gameWords -- word -> filter text (nil until first asked; English: none)
local function Str(v) return type(v) == "string" and v ~= "" and v or nil end
--- The game's own words in the client's language -> the filter each stands for.
function E.GameWords()
	if gameWords then return gameWords end
	gameWords = {}
	local lang = ns.LOCALE or "enUS"
	if lang == "enUS" or lang == "enGB" then return gameWords end
	local function Add(word, spec)
		word = Str(word)
		if not word then return end
		local w = Lower(word):gsub("^%s+", ""):gsub("%s+$", "")
		if w ~= "" and #w >= 2 and rawget(E.WORDS, w) == nil and gameWords[w] == nil and not E.STOP[w] then gameWords[w] = spec end
	end
	for i = 0, 5 do Add(_G["ITEM_QUALITY" .. i .. "_DESC"], "q:" .. i) end
	for g, slot in pairs(SLOT_GLOBALS) do Add(_G[g], "slot:" .. slot:gsub(" ", "_")) end
	local F = ns.Filters
	local sub = (C_Item and C_Item.GetItemSubClassInfo) or _G.GetItemSubClassInfo
	local cls = (C_Item and C_Item.GetItemClassInfo) or _G.GetItemClassInfo
	if F and F.TYPE_IDS and sub then
		for word, ids in pairs(F.TYPE_IDS) do
			if not word:find(" ", 1, true) then
				for _, n in ipairs(ids) do
					local ok, name = pcall(sub, math.floor(n / 100), n % 100)
					if ok then Add(name, "type:" .. word) end
				end
			end
		end
	end
	if F and F.CLASS_WORDS and cls then
		for word, n in pairs(F.CLASS_WORDS) do
			local ok, name = pcall(cls, n)
			if ok then Add(name, "type:" .. word) end
		end
	end
	Add(_G.TANK, "is:tank"); Add(_G.HEALER, "is:healer"); Add(_G.DAMAGER, "is:dps")
	for g, spec in pairs(NPC_ROLE_GLOBALS) do Add(_G[g], spec) end
	for i = 1, 8 do
		Add(_G["FACTION_STANDING_LABEL" .. i], "standing:" .. i)
		Add(_G["FACTION_STANDING_LABEL" .. i .. "_FEMALE"], "standing:" .. i)
	end
	for _, names in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE or {}, _G.LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
		for token, name in pairs(names) do if CLASS_WORDS[token] then Add(name, "trainer:" .. CLASS_WORDS[token]) end end
	end
	local display = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
	local spellName = (C_Spell and C_Spell.GetSpellName) or _G.GetSpellInfo
	for _, p in ipairs(PROF_LINES) do
		if display then local ok, name = pcall(display, p[1]) if ok then Add(name, "trainer:" .. p[3]) end end
		if spellName then local ok, name = pcall(spellName, p[2]) if ok then Add(name, "trainer:" .. p[3]) end end
	end
	return gameWords
end
--- The filter one of the game's own words stands for, or nil (E.WORDS answers these too, after its own).
function E.GameWord(w) return type(w) == "string" and E.GameWords()[w] or nil end
function E.ForgetGameWords() gameWords = nil end -- (tests)
setmetatable(E.WORDS, { __index = function(_, w) return E.GameWord(w) end })
--- Whether one of the game's own words names an NPC role (or a class's or profession's trainer).
function E.GameRole(w)
	local g = E.GameWord(w)
	return g ~= nil and (ROLE_SPECS[g] or g:find("^trainer:") ~= nil)
end

-- Phrases in the client's language (0.47.12, translations): the top questions as each language asks them, from the
-- translations ("phrases: ..." keys: the language's phrasings, | between them, %s where the thing goes), each made the
-- English line it stands for before the search reads it ("nächster Gastwirt" = "nearest gastwirt", "Mats für
-- Thoriumgürtel" = "mats for thoriumgürtel"). English is always understood too. A key nobody translated is skipped.
E.PHRASES = {
	{ "mats for %s", L["phrases: mats for %s"], "mats" },
	{ "what uses %s", L["phrases: what uses %s"], "uses" },
	{ "where to learn %s", L["phrases: where to learn %s"], "learn" }, -- (before where to get: "the recipe for x")
	{ "where to get %s", L["phrases: where to get %s"], "sources" },
	{ "nearest %s", L["phrases: nearest %s"] },
	{ "where %s", L["phrases: where is %s"] },
}
local phrasePatterns -- { { Lua pattern, English line } } (made once)
local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"
local function Alternatives(said)
	local out = {}
	if type(said) ~= "string" or said:find("^phrases: ") then return out end
	for alt in (said .. "|"):gmatch("([^|]*)|") do
		alt = Lower(alt):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
		local a, b = alt:match("^(.-)%%s(.*)$")
		if a and not b:find("%s", 1, true) then out[#out + 1] = { a, b } end
	end
	return out
end
local function Patterns()
	if phrasePatterns then return phrasePatterns end
	phrasePatterns = {}
	for _, ph in ipairs(E.PHRASES) do
		for _, ab in ipairs(Alternatives(ph[2])) do
			phrasePatterns[#phrasePatterns + 1] = { "^" .. ab[1]:gsub(MAGIC, "%%%0") .. "(.+)" .. ab[2]:gsub(MAGIC, "%%%0") .. "$", ph[1] }
		end
	end
	return phrasePatterns
end
function E.ForgetPhrases() phrasePatterns = nil end -- (tests)

--- A line in the client's language as the English line it stands for, else the line as it is.
function E.English(text)
	if type(text) ~= "string" then return text end
	local pats = Patterns()
	if #pats == 0 or text:find("[@>|]") or text:find(":[^%s]") or text:find("^%s*[%./!%-]") then return text end
	local lt = Lower(text):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	for _, p in ipairs(pats) do
		local what = lt:match(p[1])
		if what and what:find("%S") then return p[2]:format(what) end
	end
	return text
end

--- Simple mode's words for a chain link in the client's language (its first phrasing, as written), or nil (English's).
function E.LocalPhrase(rel)
	for _, ph in ipairs(E.PHRASES) do
		if ph[3] == rel and #Alternatives(ph[2]) > 0 then
			for alt in (ph[2] .. "|"):gmatch("([^|]*)|") do
				alt = alt:gsub("^%s+", ""):gsub("%s+$", "")
				local _, n = alt:gsub("%%s", "")
				if n == 1 and not alt:find("%%[^s]") then return alt end
			end
		end
	end
end

-- everyday words that are strict filters, never relaxed away when nothing passes ("helm upgrades" lists no helmet you
-- can't wear)
E.HARD_WORDS = { unplaced = true, upgrade = true, upgrades = true, skillup = true, skillups = true, ["skill up"] = true, ["skill ups"] = true,
	battlemaster = true, battlemasters = true, ["pvp vendor"] = true, ["pvp vendors"] = true,
	["honor vendor"] = true, ["honor vendors"] = true, ["pvp quartermaster"] = true }

-- left out of a search typed like a sentence (only when another word is left)
E.STOP = { a = true, an = true, the = true, of = true, from = true, ["in"] = true, at = true, on = true, with = true,
	that = true, which = true, gives = true, give = true, giving = true, ["for"] = true, by = true, to = true, ["and"] = true,
	drops = true, dropped = true, drop = true, my = true, some = true, any = true, show = true, find = true, me = true,
	is = true, are = true }

local wordTests = {} -- everyday word -> soft test (made once)
local weights = setmetatable({}, { __mode = "k" }) -- soft test -> how much passing it counts when relaxed

-- quality words count for little when nothing passes every word: "rare shield" for a green shield is still
-- the shield people meant (what something is beats how rare it is)
local WEAK = { poor = true, junk = true, grey = true, gray = true, common = true, uncommon = true, rare = true,
	epic = true, legendary = true }

--- How much an everyday word's test counts in the relaxed ranking (UI:RelaxSoft): 1 for quality words, else 3.
function E.Weight(test) return weights[test] or 3 end

-- the word at the start of a word of the name ("nearest ah" isn't Sarah, "inn" isn't Finn, "ring" isn't Herring)
local wordPatterns = {}
local function NameHas(e, w)
	local ln = rawget(e, "_lname") or (type(e.name) == "string" and Lower(e.name)) or ""
	local pat = wordPatterns[w]
	if not pat then
		-- (a word's start for longer words: "sword" finds Swordsmith Ivan; short ones whole: "ah", "inn")
		pat = "%f[%w]" .. w:gsub("%p", "%%%0") .. (#w < 4 and "%f[%W]" or "")
		wordPatterns[w] = pat
	end
	return ln:find(pat) ~= nil
end

--- The soft filter an everyday word stands for, or nil: a row passes when the filter says so, or when its
--- name has the word ("bound" still finds "Bound Fire Elemental"). Easy mode only.
function E.Word(w)
	if not E.On() then return nil end
	w = Lower(w)
	-- a strict word ("upgrades") is its filter made now: F.GearFit reads your level and gear when made, so a kept one
	-- would judge by the character as it was ("helm upgrades or boots upgrades" reaches here through the | pieces)
	if E.HARD_WORDS[w] then return ns.Filters and ns.Filters.Parse(E.WORDS[w]) or nil end
	local spec = E.WORDS[w]
	if not spec then return nil end -- (not an everyday word: nothing kept, or every word typed would stay in the table)
	local t = wordTests[w]
	if t ~= nil then return t or nil end
	local f = ns.Filters and ns.Filters.Parse(spec)
	if not f then wordTests[w] = false return nil end
	if rawget(E.WORDS, w) == nil then -- (the game's own word: as the word alone found, its name or text, or the filter)
		local RowHas = ns.Filters.RowHas
		t = function(e) return f(e) or RowHas(e, w) end
	else
		t = function(e) return f(e) or NameHas(e, w) end
	end
	wordTests[w] = t
	weights[t] = (WEAK[w] or spec:find("^q:")) and 1 or 3
	return t
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
local function LockoutVerbs(e) -- (your own: the game's lockout link; an alt's: in words, Lockouts.lua)
	return L["show in chat"], (e.mine and not e.world) and L["link in chat"] or L["put in the chat box"]
end
local function GroupVerbs(e) -- (Shift+Enter: your buff they're missing, when you have one: Group.lua)
	return L["target"], e.buffWith and L["cast %s"]:format(e.buffWith) or nil
end
local PLACE = { L["show on map"], L["set waypoint"] }
local TO_CHAT = { L["show in chat"], L["put in the chat box"] } -- ("put in the chat box", "link in chat": RowMenu.lua compares them, translated alike)
E.VERBS = {
	items = ItemVerbs, consumables = ItemVerbs, mats = ItemVerbs, gear = ItemVerbs, reagent = { L["show in bags"] },
	source = SourceVerbs,
	stored = { L["show in bags"], L["show in chat"] }, lootlog = { L["show in bags"], L["link in chat"] },
	loot = { L["show in AtlasLoot"], L["link in chat"] },
	mail = MailVerbs, auctions = AuctionVerbs, group = GroupVerbs, lockouts = LockoutVerbs,
	combatlog = TO_CHAT, gold = TO_CHAT, experience = TO_CHAT, calc = TO_CHAT,
	spells = SpellVerbs, talents = TalentVerbs,
	npc = { L["show on map"], L["target"] },
	maps = PLACE, dungeon = PLACE, raid = PLACE, mailbox = PLACE, object = PLACE, flight = PLACE,
	guild = { L["whisper"], L["invite"] }, friends = { L["whisper"], L["invite"] }, who = WhoVerbs,
	questie = { L["Wowhead link"], L["show in game"] },
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
-- Action words: "use hearthstone", "cast frost nova", "summon raptor", "target hogger", "nearest innkeeper"
----------------------------------------------------------------------

-- The first word of a search can say what to do. `map`: the kinds it looks in, and for each the row's action it
-- runs on Enter ("p" its usual one, "s" its Shift+Enter one); no map: any kind, the usual action (only the word
-- is dropped: "show", "open"). `keep`: only rows it says yes to. `nearest`: NPCs sorted by how far away they are.
E.ACTIONS = {
	use = { label = L["Use"], map = { items = "s", toys = "p", camp = "s" } },
	cast = { label = L["Cast"], map = { spells = "s" } },
	summon = { label = L["Summon"], map = { mounts = "p", pets = "p" } },
	mount = { label = L["Summon"], map = { mounts = "p" } },
	ride = { label = L["Summon"], map = { mounts = "p" } },
	equip = { label = L["Equip"], map = { items = "s", equipmentset = "p" } },
	wear = { label = L["Wear"], map = { titles = "p", items = "s", equipmentset = "p" } },
	target = { label = L["Target"], map = { npc = "s" } },
	-- ("l": a link to the row in the chat box, for rows whose Shift+Enter is something else)
	link = { label = L["Link in chat"], verb = L["link in chat"], map = { achievements = "s", professions = "s", recipes = "s", talents = "s",
		lootlog = "s", loot = "s", items = "l", spells = "l", quests = "l" } },
	["do"] = { label = L["Do"], map = { slash = "p" }, keep = IsEmote },
	where = { label = L["Where is"], map = { npc = "p", maps = "p", quests = "p", questie = "s", dungeon = "p", raid = "p",
		mailbox = "p", flight = "p" } },
	nearest = { label = L["Nearest"], map = { npc = "p" }, nearest = true },
	closest = { label = L["Nearest"], map = { npc = "p" }, nearest = true },
	nearby = { label = L["Nearest"], map = { npc = "p" }, nearest = true },
	who = { label = L["Who"], map = { who = "p" } },
	show = { label = L["Show"] }, open = { label = L["Open"] }, find = { label = L["Find"] },
}

-- the words that name what an NPC does (not who it is): "nearest" then keeps to NPCs friendly to you
E.ROLE_WORDS = { repair = true, repairs = true, inn = true, innkeeper = true, bank = true, banker = true, flight = true,
	fp = true, flightmaster = true, ah = true, auction = true, auctioneer = true, stable = true, stablemaster = true,
	vendor = true, vendors = true, trainer = true, trainers = true, questgiver = true, battlemaster = true,
	battlemasters = true, ["pvp vendor"] = true, ["pvp vendors"] = true, ["honor vendor"] = true,
	["honor vendors"] = true, ["pvp quartermaster"] = true, pvp = true }
setmetatable(E.ROLE_WORDS, { __index = function(_, w) return E.GameRole(w) or nil end }) -- (the game's own words too)

--- The action a search's first word names, or nil (only with another word after it, or an everyday word).
function E.Action(word) return E.On() and E.ACTIONS[word] or nil end

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

local function KindWord(kind) return ns:KindName(ns.providers[kind]) end

--- The lists the rows a search shows come from (real results only: no category, hint, help, pick or completion row,
--- nor a row that asks something), as a set of list ids. Alt+` names only these: "use hearthstone" shows the
--- Hearthstone in your bags, so @item, not every list "use" looks in (@camp @item @toy).
function E.ShownKinds(rows)
	local set = {}
	for _, e in ipairs(rows or {}) do
		if type(e) == "table" and not (e.noActivate or e.raw or e.completion or e.catId or e.syntaxRow or e.lead) then
			local k = e.kind -- (an action's view: its row's kind)
			if type(k) == "string" and ns.providers[k] then set[k] = true end
		end
	end
	return set
end

--- Two everyday words that mean one thing joined into one ("attack power food" -> "attack power", "food"). Works on
--- the list in place.
function E.JoinPairs(words)
	local i = 1
	while i < #words do
		local pair = Lower(words[i] .. " " .. words[i + 1])
		if E.WORDS[pair] then words[i] = pair; table.remove(words, i + 1) end
		i = i + 1
	end
end

--- The action the words say (the first word, or "nearest" said last: "mining trainer nearby"), taken off the list;
--- nil when there's none.
local function ActionOf(words)
	local word = #words > 1 and Lower(words[1]) or nil
	local act = word and E.ACTIONS[word] or nil
	if act then
		table.remove(words, 1)
	elseif #words > 1 then
		local tail = E.ACTIONS[Lower(words[#words])]
		if tail and tail.nearest then act = tail; table.remove(words) end
	end
	return act, act and word
end

-- a word's pieces that are everyday words as their filters ("-boe" -> -is:boe, "sword|axe" -> type:sword|type:axe,
-- rare&sword -> q:rare&type:sword; plain pieces stay words: "-cloth")
local function PieceFilter(neg, a) return neg .. (E.WORDS[a] or a) end
-- what @flight already says (Alt+`: "nearest unlearned flight master" -> "@flight is:unlearned sort:nearest")
local FLIGHT_SAID = { ["is:flight"] = true, ["is:flightmaster"] = true, ["is:flightpath"] = true }
local function AdvancedPart(w) return (w:gsub("([-!]?)([^|&]+)", PieceFilter)) end

--- A Simple search as Advanced mode would type it: the lists the action word or the picked category looks in as @kinds
--- (given `shown`, E.ShownKinds of what the search shows, only those of them that show something: "use hearthstone"
--- -> "@item do:use hearthstone"; none showing: no @kind after an action word, whose do: stands for its lists, and all
--- of a category's), "nearest" as @npc sort:nearest (with faction:friendly for a role), a place as in:<place>,
--- everyday words as their key:value filters ("attack power" = stat:ap), sentence words dropped; other words (and any
--- Advanced syntax already typed) stay. Ends with a space to type on. "" for an empty search.
-- a plain-word question or chain, in Advanced syntax: chains as links ("mats for x" -> "x > mats"), the zone questions
-- as @map/@dungeon/@raid with lvl: or fish:, the combat ones as @combatlog words. Nil for anything else.
local function QuestionToAdvanced(text)
	local lq = ns.LootLog and ns.LootLog.Question and ns.LootLog.Question(text)
	if lq then return "@drop " .. ((lq.who == "me" and "you ") or (lq.who and (Lower(lq.who) .. " ")) or "") end
	local chain = ns.Pipes and ns.Pipes.Canonical(text)
	if chain then return chain .. " " end
	-- (the questions in the order the search asks them: Search.lua's Scan.ANSWERS)
	local cq = ns.CombatLog and ns.CombatLog.Question and ns.CombatLog.Question(text)
	if cq then return "@combatlog " .. ((cq == "killed" and "killed") or (cq == "crit" and "taken") or "dealt") .. " " end
	local Z = ns.Zones
	local q, said
	if Z and Z.Question then q, said = Z.Question(text) end
	if q then
		if q == "fish" then return "@map fish:mine " end
		local lv = said or (UnitLevel and UnitLevel("player"))
		local kind = (q == "dungeon" and "@dungeon") or (q == "raid" and "@raid") or "@map"
		return kind .. ((type(lv) == "number" and lv > 0) and (" lvl:" .. lv) or "") .. " "
	end
	local sq = ns.Spells and ns.Spells.Question and ns.Spells.Question(text)
	if sq then return "@spell is:unplaced " .. (#sq > 0 and (table.concat(sq, " ") .. " ") or "") end
	local mq = ns.MissingRecipes and ns.MissingRecipes.Question and ns.MissingRecipes.Question(text)
	if mq then
		local rest = {}
		for _, n in ipairs(mq.profs) do rest[#rest + 1] = Lower(n) end
		for _, w in ipairs(mq.words) do rest[#rest + 1] = w end
		return "@recipe " .. (mq.learnable and "is:learnable" or "is:unknown") .. " " .. (#rest > 0 and (table.concat(rest, " ") .. " ") or "")
	end
	local plq = ns.Plan and ns.Plan.Question and ns.Plan.Question(text)
	if plq then return ns.Plan.ToAdvanced(plq) end
	local dq = ns.QuestDrop and ns.QuestDrop.Question and ns.QuestDrop.Question(text)
	if dq then
		local which = (dq.grey and "is:grey -is:complete") or (dq.behind and "is:leftbehind -is:complete") or "is:drop"
		return "@quest " .. which .. " " .. (#dq.words > 0 and (table.concat(dq.words, " ") .. " ") or "")
	end
	local pq = ns.GroupQuests and ns.GroupQuests.Question and ns.GroupQuests.Question(text)
	if pq then return ns.GroupQuests.ToAdvanced(pq) end
	local lq2 = ns.Lockouts and ns.Lockouts.Question and ns.Lockouts.Question(text)
	if lq2 then return ns.Lockouts.ToAdvanced(lq2) end
	local aq = ns.Auctions and ns.Auctions.Question and ns.Auctions.Question(text)
	if aq then return ns.Auctions.ToAdvanced(aq) end
	local mq2 = ns.Mail and ns.Mail.Question and ns.Mail.Question(text)
	if mq2 then return ns.Mail.ToAdvanced(mq2) end
	local gq = ns.Group and ns.Group.Question and ns.Group.Question(text)
	if gq then return ns.Group.ToAdvanced(gq) end
end
E.QuestionToAdvanced = QuestionToAdvanced

function E.ToAdvanced(text, category, shown)
	text = E.English(text) -- (a phrase in the client's language: as its English line)
	local asked = QuestionToAdvanced(text)
	if asked then return asked end
	local words = {}
	for w in tostring(text or ""):gmatch("%S+") do words[#words + 1] = w end
	local kinds, filters, plain, seen = {}, {}, {}, {}
	local function Add(list, w) if w and not seen[w] then seen[w] = true; list[#list + 1] = w end end
	-- these lists as @kinds (sorted), those showing something when that's known; how many were named
	local function AddKinds(ids, all)
		local ks = {}
		for _, k in ipairs(ids) do if all or not shown or shown[k] then ks[#ks + 1] = k end end
		table.sort(ks)
		local n = #kinds
		for _, k in ipairs(ks) do Add(kinds, KindWord(k)) end
		return #kinds - n
	end
	E.JoinPairs(words) -- two everyday words that mean one thing ("attack power food")
	E.JoinLogic(words) -- "sword or axe" -> sword|axe, "not boe" -> -boe (made filters below)
	-- the first word can say what to do ("use hearthstone", "nearest innkeeper")
	local act, actWord = ActionOf(words)
	local nearest, doWord
	if act then
		nearest = act.nearest
		if act.map then
			local ids = {}
			for k in pairs(act.map) do ids[#ids + 1] = k end
			-- (none showing anything: no @kind, do:<word> stands for every list the action looks in)
			AddKinds(ids)
			-- what Enter does stays what was asked ("use hearthstone": do:use, not just the item shown in your bags)
			if not nearest and actWord then doWord = "do:" .. actWord end
		end
	end
	if not (act and act.map) and E.BY_ID[category or ""] then
		-- (none showing anything: all of them, there's no one word for a category)
		if AddKinds(E.BY_ID[category].kinds) == 0 then AddKinds(E.BY_ID[category].kinds, true) end
	end
	-- a place, when there's something else to look for in it ("vendor ratchet")
	local lower = {}
	for k, w in ipairs(words) do lower[k] = E.IsAdvancedWord(w) and w or Lower(w) end
	local I = ns.Integrations
	if #lower > 1 and I and I.FindPlace then
		local place, rest = I.FindPlace(lower)
		if place and rest and #rest > 0 then
			Add(filters, "in:" .. tostring(place.key):gsub(" ", "_"))
			lower = rest
		end
	end
	local role
	local others = 0
	local everyday = {} -- (the everyday words said: "nearest unlearned flight master" is the flight paths')
	for _, w in ipairs(lower) do if not E.STOP[w] then others = others + 1 end end
	for _, w in ipairs(lower) do
		if E.IsAdvancedWord(w) then
			if w:sub(1, 1) == "@" then Add(kinds, w) else Add(filters, w) end
		elseif w:find("[|&]") or w:find("^[-!]%a") then
			Add(filters, AdvancedPart(w))
		elseif E.WORDS[w] then
			Add(filters, E.WORDS[w])
			everyday[#everyday + 1] = w
			if E.ROLE_WORDS[w] then role = true end
		elseif not (E.STOP[w] and others > 0) then
			plain[#plain + 1] = w
		end
	end
	-- "nearest mailbox": its own list, not NPCs (a place said stays: "nearest mailbox in org")
	local okind = nearest and ns.Integrations and ns.Integrations.ObjectKind and ns.Integrations.ObjectKind(plain)
	if okind and ns.providers[okind] then
		return "@" .. okind .. " " .. (#filters > 0 and (table.concat(filters, " ") .. " ") or "") .. "sort:nearest "
	end
	-- "nearest unlearned flight master", "closest flight path": the flight paths' own list (Flights.lua), not NPCs; the
	-- words that only say flight path or flight master go (@flight says it), a name or a place stays
	local flight = nearest and I and I.FlightAsked and ns.providers.flight and I.FlightAsked(plain, everyday, not ns.providers.npc)
	if flight then
		local out = { KindWord("flight") }
		for _, w in ipairs(flight) do out[#out + 1] = w end
		for _, f in ipairs(filters) do if not FLIGHT_SAID[f] then out[#out + 1] = f end end
		out[#out + 1] = "sort:nearest"
		return table.concat(out, " ") .. " "
	end
	if nearest then Add(kinds, "@npc") end
	-- an NPC's role (trainer, vendor, innkeeper...) means one you can use: friendly to you ("mining trainer in org"
	-- never meant Ironforge's: the player's call, 0.41.16). Simple mode's nearest search keeps to that too; its place
	-- search keeps to the place only ("vendor crossroads" lists every vendor there; review, 0.48.6: left as it is).
	if role then Add(filters, "faction:friendly") end
	if nearest then Add(filters, "sort:nearest") end
	local out = {}
	for _, list in ipairs({ kinds, { doWord }, plain, filters }) do -- ("@spell do:cast frost nova": the verb first)
		for _, w in ipairs(list) do out[#out + 1] = w end
	end
	return #out > 0 and (table.concat(out, " ") .. " ") or ""
end

----------------------------------------------------------------------
-- Advanced mode's syntax in Simple mode: not taken, the player is told where it lives
----------------------------------------------------------------------

--- Is this word Advanced mode's syntax (an @kind, a key:value filter, >>)?
function E.IsAdvancedWord(w)
	-- (a ">" standing alone is a chain's link: Simple mode says chains in words, "mats for x", 0.45.13)
	if w == ">" or w:sub(1, 1) == "@" or w:sub(1, 2) == ">>" then return true end
	-- "-q:poor", "!is:boe", "q:rare|epic", "boe|slot:head": a key:value in any part (plain -word / a|b are Simple's too)
	for part in w:gmatch("[^|&]+") do
		local key = part:gsub("^[-!]", ""):match("^(%a+):")
		if key ~= nil and ns.Filters ~= nil and ns.Filters.IsKey(key) then return true end
	end
	return false
end

E.NOT_WORDS = { ["not"] = true, no = true, without = true, except = true }
E.OR_WORDS = { ["or"] = true }

--- Simple mode's "or" and "not" in words, made into F.Parse's - | &: "not boe" / "without cloth" -> "-boe", "-cloth";
--- "sword or axe" -> "sword|axe"; "rare sword or rare axe" -> "rare&sword|rare&axe": the words after "or" (up to the
--- next "or" or a "not") are one side, and as many words before it the other (a side already joined stands alone), so "rare
--- sword or axe" keeps rare for both. A "not"/"or" with nothing to join stays a word. Works on the list in place.
function E.JoinLogic(words)
	local i = 1
	while i < #words do -- not first: "sword or not boe" = sword|-boe
		local lw = Lower(words[i])
		if E.NOT_WORDS[lw] and not E.OR_WORDS[Lower(words[i + 1])] and not E.NOT_WORDS[Lower(words[i + 1])] then
			words[i] = "-" .. words[i + 1]
			table.remove(words, i + 1)
		end
		i = i + 1
	end
	i = 2
	while i < #words do
		if E.OR_WORDS[Lower(words[i])] then
			local stop = i + 1
			-- (a "not" after it is for the whole search: "rare sword or axe not boe")
			while stop + 1 <= #words and not E.OR_WORDS[Lower(words[stop + 1])] and not words[stop + 1]:find("^[-!]%a") do
				stop = stop + 1
			end
			local n = stop - i
			local from = i - 1
			if not words[from]:find("|", 1, true) then
				while from > 1 and i - from < n and not words[from - 1]:find("|", 1, true) do from = from - 1 end
			end
			local left = table.concat(words, "&", from, i - 1)
			local right = table.concat(words, "&", i + 1, stop)
			for _ = from, stop do table.remove(words, from) end
			table.insert(words, from, left .. "|" .. right)
			i = from + 1
		else
			i = i + 1
		end
	end
	return words
end

local function OfferAdvanced() C_Timer.After(0, E.ShowConfirm) end
--- The row shown on top when Advanced syntax was typed in Simple mode (Enter: the switch's confirmation).
E.ADVANCED_ROW = {
	name = L["@, >, >> and key:value are for Advanced mode"], kind = "advanced", kindLabel = "",
	detail = L["Enter to switch (or type .advanced)"], icon = "Interface\\Icons\\INV_Misc_Gear_01",
	activate = OfferAdvanced,
}

-- ">>" typed in Simple mode: sending is in the right-click menu here
E.SEND_ROW = {
	name = L["Right-click a result to send it to chat"], kind = "advanced", kindLabel = "", noActivate = true,
	detail = L["say, party, guild, whisper, or all of them at once (>> is Advanced mode's)"], icon = "Interface\\Icons\\INV_Letter_15",
}

----------------------------------------------------------------------
-- .advanced / .simple (the modes; db.easyMode == false is Advanced)
----------------------------------------------------------------------

local dialog -- the confirmation, on the Panel pattern (it takes the terminal's place)

local function Confirm(yes)
	if dialog then dialog:Hide() end
	if yes then
		E.Set(false)
		ns:Print(L["Advanced mode: the full command line (@kinds, key:value filters, .commands, >> chat). .help lists it all; .simple goes back."])
	end
end

local app = {}
function app.IsShown() return dialog and dialog:IsShown() or false end
function app.Close() if dialog then dialog:Hide() end end

E.CONFIRM_W, E.CONFIRM_PAD, E.CONFIRM_BODY_Y = 460, 14, 40 -- (the dialog is as tall as its text needs)

local function Button(parent, label, x, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(170, 24)
	b:SetPoint("BOTTOM", parent, "BOTTOM", x, E.CONFIRM_PAD)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

function E.ShowConfirm()
	local P = ns.Panel
	if InCombatLockdown() then
		ns:Print(L["In combat: type .advanced again once it's over."])
		return
	end
	if not dialog then
		dialog = P.Build("TerminalHardMode", app)
		dialog.title = P.Text(dialog, 15, "CENTER")
		dialog.title:SetPoint("TOP", 0, -E.CONFIRM_PAD)
		dialog.body = dialog:CreateFontString(nil, "OVERLAY")
		dialog.body:SetFontObject(ns.Theme.fonts.small)
		dialog.body:SetJustifyH("LEFT")
		dialog.body:SetWordWrap(true)
		dialog.body:SetPoint("TOP", 0, -E.CONFIRM_BODY_Y)
		dialog.body:SetWidth(E.CONFIRM_W - 40)
		dialog.yes = Button(dialog, L["Switch to Advanced"], -92, function() Confirm(true) end)
		dialog.no = Button(dialog, L["Stay in Simple"], 92, function() Confirm(false) end)
		dialog:SetScript("OnKeyDown", function(_, key)
			if key == "ENTER" then Confirm(true)
			elseif key == "ESCAPE" or key == "`" then Confirm(false) end
		end)
	end
	P.Opening(app)
	local t = P.Layout(dialog)
	dialog.title:SetText("|cff" .. t.text .. L["Switch to Advanced mode?"] .. "|r")
	dialog.body:SetText("|cff" .. t.dim .. L["The full command line: @kinds (@npc Hogger), key:value filters (q:rare+ lvl:20-30), .commands and >> to send to chat. Words like \"rare\" and \"use\" become plain search words. .simple comes back."]
		.. "|r")
	-- as tall as the text: title, text, buttons, with the same margin around each
	local h = dialog.body:GetStringHeight()
	h = type(h) == "number" and h > 0 and h or 42
	dialog:SetSize(E.CONFIRM_W, math.floor(E.CONFIRM_BODY_Y + h + E.CONFIRM_PAD + 24 + E.CONFIRM_PAD + 4))
	dialog:Show()
end

ns:RegisterCommand("advanced", {
	desc = L["Switch to Advanced mode: the full command line (@kinds, key:value filters, >> chat), after a confirmation"],
	aliases = { "hardmode", "hard" },
	run = function()
		if not E.On() and not E.temp then return { L["Already in Advanced mode (.simple goes back)."] } end
		-- after this press is done (the terminal closes on a command): the dialog takes its place
		C_Timer.After(0, E.ShowConfirm)
		return {}
	end,
})

ns:RegisterCommand("fuzzy", {
	desc = L["Pure fuzzy finding, this once (.fzf too; also Tab+`: hold Tab, press `): every list, by name only; Enter takes the result to Simple mode, Shift+Enter to Advanced"],
	aliases = { "fzf" },
	run = function(args)
		-- (after this press is done: running a command closes the terminal first)
		C_Timer.After(0, function() ns.UI:FuzzyOnce(args) end)
		return {}
	end,
})

ns:RegisterCommand("simple", {
	desc = L["Switch to Simple mode: plain words (use hearthstone, nearest innkeeper, stamina food), results sorted by where they are"],
	aliases = { "easymode", "easy" },
	run = function()
		if E.On() then return { L["Already in Simple mode (.advanced for the full command line)."] } end
		E.Set(true)
		return { L["Simple mode: type what you're looking for in plain words (\"use hearthstone\", \"nearest innkeeper\", \"stamina food\"). .advanced for the full command line."] }
	end,
})

--- .help in Simple mode: plain sentences.
function E.HelpLines()
	return {
		L["Terminal: type the name of anything (an item, a quest, a spell, a mount, a place, an NPC, an emote) and press Enter to open it."],
		L["Typing lists where it was found (Items, Quests, Settings, Emotes...): pick one with Enter, Tab or a click, then the thing itself; something named exactly what you typed comes first, to open at once. Shift+Left goes back to all of them (and back from wherever Enter took you)."],
		L["Start with what to do: use, cast, summon, equip, wear, target, where, nearest (\"use hearthstone\", \"nearest innkeeper\")."],
		L["Shift+Enter does the other thing (use the item, cast the spell, target the NPC); the footer says which. Right-click a row, or press Shift+Right, for all it can do: \"All 8 to party\" sends every result at once."],
		L["Words like rare, epic, boe, food, potion, stamina, ready, todo, vendor, trainer narrow the search: \"stamina food\", \"vendor ratchet\" (a place's NPCs)."],
		L["Ask where to go: \"where should i level\", \"what dungeon should i do\", \"where should i fish\" (or \"zones for level 35\")."],
		L["Flight paths you haven't learned: \"nearest unlearned flight master\", \"unlearned flight paths\" (a flight master's map tells Terminal which you know)."],
		L["\"or\" and \"not\" work too: \"sword or axe\", \"rare ring not boe\", \"potion not minor\"."],
		L["Down on an empty prompt brings back your last search; Up goes through what you ran before. Esc closes."],
		L["Alt+` turns what you typed into Advanced mode's command line, for that one time (Simple again once it closes)."],
		L["Tab+` (hold Tab, press `; or .fuzzy / .fzf) is pure fuzzy finding: every list at once, by name only. Enter takes the result to Simple mode, Shift+Enter to Advanced."],
		L["Ask about your fights: \"what killed me\", \"who crit me\", \"my biggest crit\" (what Terminal saw in the combat log)."],
		L["Spells you haven't put anywhere: \"spells not on my bars\" (not on any bar or key; passives left out)."],
		L["Recipes you don't have yet: \"blacksmithing recipes i'm missing\" lists them with the skill each needs and how it's learned (trainer and cost, vendor and limited supply, a drop, a quest); \"recipes i can learn now\" only those your skill allows."],
		L["Clean out your quest log: \"quests to drop\" lists the grey ones and those in zones you've left behind. Shift+Enter drops one (Terminal asks first); \"Drop all\" on top, or right-click, drops them together after you've seen the list."],
		L["Your group: \"who is dead\", \"who needs fortitude\", \"who is out of range\", \"group healers\", \"missing buffs\", \"missing consumables\" (Enter targets them, Shift+Enter casts your buff on them; right-click one and pick All to party to say what's missing in one line)."],
		L["Quests with your party: \"party quests\" (who is on each of yours; Enter shares it), \"quests to share\" (the ones someone lacks); right-click one and pick All to party to say them in one line."],
		L["Your mail on every character, as Terminal last saw it: \"my mail\", \"mail running out\", \"cod mail\", \"mail from bob\" (who sent it, gold, COD, what's attached, when it runs out). Open a mailbox once on each character. \"sent mail\" shows what you sent in the last hour, and \"incoming mail\" the auction house's news on its way (sold, won, outbid, expired)."],
		L["Your auctions: \"my auctions\", \"what am i selling\", \"auctions sold\": what each character has on the auction house as Terminal saw it posted, with its price and time left, and the auction house's news."],
		L["Your lockouts on every character: \"my lockouts\", \"raid lockouts\", \"am i saved\" (bosses down and when each resets; Enter names the bosses)."],
		L["Level a profession: \"blacksmithing plan\" or \"level blacksmithing\" lists the recipes that still give skill by how many times your materials make each (bags and bank, and with your alts); the footer says about how many points they'd give."],
		L["Follow the chain: \"mats for thorium belt\", \"what uses copper bar\", \"where to get thorium bar\", \"where to learn thorium belt\" (its recipe, or a trainer). Enter on a row goes one step further, Shift+Enter opens it."],
		L["Find guildies by what they do: \"guild blacksmith\", \"guild priest online\" (Enter whispers them, Shift+Enter invites)."],
		L["Ctrl+click an item (or a spell, quest, achievement) in chat to look it up here."],
		L["Ctrl+Enter does it and keeps the terminal open (for things that don't open a window)."],
		L["F1 (or .keybinds) shows every key, for each mode; Esc there brings you back."],
		L["Commands start with a dot: .options, .theme, .xp, .zen, .changelog... (type a dot to see them all)."],
		L["Want the full command line (@kinds, filters, chat)? Type .advanced"],
	}
end


-- Terminal's own lists registered before this file loaded (RegisterProvider adopts only once Easy exists): their own
-- verbs and Simple mode categories (`verbs`, `simpleCategory`: GroupQuests.lua's)
for _, id in ipairs(ns.providerOrder or {}) do E.Adopt(ns.providers[id]) end
