local ns = select(2, ...)
local L = ns.L

-- What single words mean in Simple mode: everyday words (E.WORDS: "rare" is q:rare, a soft filter), the game's own words
-- for them, a client's phrases (E.English), strict and stop words, action words ("use", "nearest"), the words for
-- trainers and the people a profession's are called. Moved out of Simple.lua as it was (its table is ns.Easy).

local E = ns.Easy
local Lower = ns.Lower
local IsEmote = E.IsEmote

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
	merchant = "is:vendor", merchants = "is:vendor", -- (0.56.10, the player: "merchant")
	innkeeper = "is:innkeeper", banker = "is:banker", auctioneer = "is:auctioneer",
	flightmaster = "is:flightmaster", stablemaster = "is:stablemaster", questgiver = "is:questgiver",
	-- (two words: "nearest spirit healer"; a graveyard is where one stands; 0.50.5)
	["spirit healer"] = "is:spirithealer", ["spirit healers"] = "is:spirithealer", ["spirit guide"] = "is:spirithealer",
	graveyard = "is:spirithealer", graveyards = "is:spirithealer",
	-- PvP NPCs: only the real ones ("nearby battlemaster", "nearest pvp vendor", "honor vendor")
	battlemaster = "is:battlemaster", battlemasters = "is:battlemaster",
	-- (0.56.8, a player's comment: "weapon master" alone, the nearest of them)
	weaponmaster = "is:weaponmaster", weaponmasters = "is:weaponmaster", ["weapon master"] = "is:weaponmaster",
	["weapon masters"] = "is:weaponmaster",
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
local ROLE_SPECS = { ["is:spirithealer"] = true, ["is:innkeeper"] = true, ["is:banker"] = true, ["is:auctioneer"] = true, ["is:flightmaster"] = true,
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
	["honor vendor"] = true, ["honor vendors"] = true, ["pvp quartermaster"] = true,
	weaponmaster = true, weaponmasters = true, ["weapon master"] = true, ["weapon masters"] = true }

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

--- A strict everyday word's filter ("upgrades": is:upgrade), made now (F.GearFit reads your level and gear when made),
--- or nil for any other word. `lw`: lowercase. (Easy.Word and Search.lua's Parse alike; review, 0.53.6.)
function E.Strict(lw)
	return E.HARD_WORDS[lw] and ns.Filters and ns.Filters.Parse(E.WORDS[lw]) or nil
end

--- The soft filter an everyday word stands for, or nil: a row passes when the filter says so, or when its
--- name has the word ("bound" still finds "Bound Fire Elemental"). Easy mode only.
function E.Word(w)
	if not E.On() then return nil end
	w = Lower(w)
	-- a strict word ("upgrades") is its filter made now: F.GearFit reads your level and gear when made, so a kept one
	-- would judge by the character as it was ("helm upgrades or boots upgrades" reaches here through the | pieces)
	if E.HARD_WORDS[w] then return E.Strict(w) end
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
-- Action words: "use hearthstone", "cast frost nova", "summon raptor", "target hogger", "nearest innkeeper"
----------------------------------------------------------------------

-- The first word of a search can say what to do. `map`: the kinds it looks in, and for each the row's action it
-- runs on Enter ("p" its usual one, "s" its Shift+Enter one); no map: any kind, the usual action (only the word
-- is dropped: "show", "open"). `keep`: only rows it says yes to. `nearest`: NPCs sorted by how far away they are.
E.ACTIONS = {
	use = { label = L["Use"], map = { items = "s", toys = "p", camp = "s" } },
	cast = { label = L["Cast"], map = { spells = "s" } },
	-- (spells too: "summon voidwalker", "summon imp" are a warlock's spells, cast on Enter; 0.50.7, review: nothing found)
	summon = { label = L["Summon"], map = { mounts = "p", pets = "p", spells = "s" } },
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
		mailbox = "p", forge = "p", anvil = "p", cookingfire = "p", moonwell = "p", flight = "p" } },
	nearest = { label = L["Nearest"], map = { npc = "p" }, nearest = true },
	closest = { label = L["Nearest"], map = { npc = "p" }, nearest = true },
	nearby = { label = L["Nearest"], map = { npc = "p" }, nearest = true },
	-- (the other way round: "farthest innkeeper", sort:-distance; 0.65.7, the player)
	farthest = { label = L["Farthest"], map = { npc = "p" }, nearest = true, far = true },
	furthest = { label = L["Farthest"], map = { npc = "p" }, nearest = true, far = true },
	who = { label = L["Who"], map = { who = "p" } },
	show = { label = L["Show"] }, open = { label = L["Open"] }, find = { label = L["Find"] },
}

-- the words that name what an NPC does (not who it is): "nearest" then keeps to NPCs friendly to you
E.ROLE_WORDS = { repair = true, repairs = true, inn = true, innkeeper = true, bank = true, banker = true, flight = true,
	fp = true, flightmaster = true, ah = true, auction = true, auctioneer = true, stable = true, stablemaster = true,
	vendor = true, vendors = true, merchant = true, merchants = true, trainer = true, trainers = true, questgiver = true, battlemaster = true,
	battlemasters = true, ["pvp vendor"] = true, ["pvp vendors"] = true, ["honor vendor"] = true,
	["honor vendors"] = true, ["pvp quartermaster"] = true, pvp = true, ["spirit healer"] = true, ["spirit healers"] = true,
	["spirit guide"] = true, graveyard = true, graveyards = true, weaponmaster = true, weaponmasters = true,
	["weapon master"] = true, ["weapon masters"] = true }
setmetatable(E.ROLE_WORDS, { __index = function(_, w) return E.GameRole(w) or nil end }) -- (the game's own words too)

--- "nearset", "neareset", "neares": "nearest" as it's often mistyped (0.56.8, a player's comment), "nearbby" too; a
--- word starting with "nea", within two letters of it (one of "nearby"). (Release review: "newest" and "nearly" were
--- taken for it: words of their own.)
local NOT_NEAR = { nearly = true, neatly = true }
function E.NearTypo(word)
	local D = ns.DidYouMean and ns.DidYouMean.Distance
	if not (D and type(word) == "string" and #word >= 5 and word:sub(1, 3) == "nea" and not NOT_NEAR[word]) then return nil end
	if D(word, "nearest", 2) <= 2 or D(word, "nearby", 1) <= 1 then return E.ACTIONS.nearest end
end

--- The action a search's first word names, or nil (only with another word after it, or an everyday word).
function E.Action(word) return E.On() and (E.ACTIONS[word] or E.NearTypo(word)) or nil end

-- the people a profession's trainer is said as ("skinner": the nearest skinning trainer; 0.56.8, a player's comment)
E.PROF_PEOPLE = { skinner = "skinning", skinners = "skinning", miner = "mining", miners = "mining", herbalist = "herbalism",
	herbalists = "herbalism", alchemist = "alchemy", alchemists = "alchemy", enchanter = "enchanting", enchanters = "enchanting",
	engineer = "engineering", engineers = "engineering", leatherworker = "leatherworking", leatherworkers = "leatherworking",
	tailor = "tailoring", tailors = "tailoring", blacksmith = "blacksmithing", blacksmiths = "blacksmithing",
	fisherman = "fishing", angler = "fishing" }

-- a word's pieces that are everyday words as their filters ("-boe" -> -is:boe, "sword|axe" -> type:sword|type:axe,
-- rare&sword -> q:rare&type:sword; plain pieces stay words: "-cloth")
local function PieceFilter(neg, a) return neg .. (E.WORDS[a] or a) end
local function AdvancedPart(w) return (w:gsub("([-!]?)([^|&]+)", PieceFilter)) end
E.AdvancedPart = AdvancedPart -- (Search.lua's printed query)

--- "enchanting trainer": with trainer said, a profession among the words (or the start of one: "enchant", "blacksmith")
--- or a class ("mage trainer") is what they teach, trainer:enchanting, not a word in their name or title: the
--- Journeyman Enchanter's title has "enchant", not "enchanting", so "nearest enchanting trainer" found nothing while
--- "nearest enchant trainer" did (0.49.8, the player's ask; Master Mage has no "trainer"). "first aid" is two words;
--- "pet trainer" and "hunter pet trainer" are the pet trainers, trainer:pet (0.49.10: the hunter's words were left to
--- match, and matched nothing); "demon trainer" and "warlock pet trainer" the warlocks' Demon Trainers, trainer:demon
--- (0.49.11); "pet trainer" alone your class's: a warlock's Demon Trainers, anyone else's the pet trainers (0.49.12). Gives the words left and the filters' text, or the words and nil. A search that names
--- one is a nearest search (0.49.9: "blacksmithing trainer" alone).
function E.TrainerProfs(words, trainerSaid)
	local F = ns.Filters
	local ProfNamed = trainerSaid and F and F.ProfNamed
	if not ProfNamed then return words, nil end
	-- (two words that are one class, not one of the game's here: left as words; review, 0.49.17)
	for k, w in ipairs(words) do
		if (w == "demon" and words[k + 1] == "hunter") or (w == "death" and words[k + 1] == "knight") then return words, nil end
	end
	local pet, demon, warlock, hunter = false, false, false, false
	for k, w in ipairs(words) do
		if w == "hunter" or w == "hunters" then hunter = true end
		if w == "pet" or w == "pets" then pet = true end
		if (w == "demon" or w == "demons") and words[k + 1] ~= "hunter" then demon = true end
		if w == "warlock" or w == "warlocks" then warlock = true end
	end
	if pet or demon then
		-- the warlocks' Demon Trainers ("demon trainer", "warlock pet trainer"), or the hunters' pet trainers ("pet
		-- trainer", "hunter pet trainer"): the words that say which go, whatever else was said stays
		local SAID = { pet = true, pets = true, hunter = true, hunters = true, demon = true, demons = true, warlock = true, warlocks = true }
		local kept = {}
		for _, w in ipairs(words) do if not SAID[w] then kept[#kept + 1] = w end end
		-- ("pet trainer" alone: your class's, the game's class token being the same in every language)
		if not (demon or warlock or hunter) and UnitClass and select(2, UnitClass("player")) == "WARLOCK" then warlock = true end
		return kept, { (demon or warlock) and "trainer:demon" or "trainer:pet" }
	end
	-- (0.61.0) "my", "class", "weapon(s)", "master(s)" name no one: set aside while the profession, class or weapon is
	-- looked for ("my mining trainer", "fist weapons trainer": trainer:mining, trainer:fist); with none named, "class
	-- trainer" / "my trainer" is your class's (trainer:class) and "weapon trainer" / "weapon master" the weapon masters
	local weaponSaid = false
	for _, w in ipairs(words) do if w == "weapon" or w == "weapons" then weaponSaid = true end end
	-- ("master" is set aside only with "weapon": "master leatherworking trainer" keeps it, a word of the search)
	local ASIDE = { my = true, class = true, weapon = true, weapons = true, master = weaponSaid, masters = weaponSaid }
	local kept, specs, aside = {}, nil, {}
	for k, w in ipairs(words) do
		local aid = w == "aid" and words[k - 1] == "first" -- (said with "first": taken with it)
		local prof = not aid and (w ~= "first" or words[k + 1] == "aid") and ProfNamed(w) or nil
		-- (first aid by name only: "firs" isn't it; review, 0.49.17)
		if (prof == "firstaid" or prof == "first aid") and w ~= "firstaid" and not (w == "first" and words[k + 1] == "aid") then
			prof = nil
		end
		if not prof and F.TrainerClass then prof = F.TrainerClass(w) end
		if not prof and F.TrainerWeapon then prof = F.TrainerWeapon(w) end -- ("dagger trainer": its weapon masters)
		if prof then
			specs = specs or {}
			specs[#specs + 1] = "trainer:" .. (prof:gsub(" ", ""))
		elseif ASIDE[w] then
			aside[w] = true
		elseif not aid then
			kept[#kept + 1] = w
		end
	end
	if not specs then
		if weaponSaid then specs = { "is:weaponmaster" }
		-- ("my trainer", "class trainer": your class's; "my riding trainer" names another one: a search, as before;
		-- release review, 0.63.0)
		elseif (aside.class or aside.my) and #kept == 0 then specs = { "trainer:class" }
		else return words, nil end
		return kept, specs
	end
	-- (several said: any of them, "mining herbalism trainer"; review, 0.49.17: both at once matched no one)
	if #specs > 1 then specs = { table.concat(specs, "|") } end
	return kept, specs
end
