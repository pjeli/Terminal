local ns = select(2, ...)

-- Simple mode (the default; "easy" in the code): Terminal for players who'll never type @npc or q:rare+.
--   - Opens with nothing listed. Typing lists the categories that have it ("Bags  Rumsey Rum +2 more",
--     "Emotes  /dance"), best match first; Enter, a click or Tab picks one, and only it is searched (Questie's
--     lists included). Tab goes back to all of them; clearing the prompt lets the category go. Every list is
--     in some category, the ones hard mode only searches with their @kind too (emotes, slash commands,
--     console settings, Questie's quests and NPCs, your alts' bags).
--   - Everyday words act as filters: "rare sword", "epic", "boe", "ready", "todo", "innkeeper"
--     (a soft filter: a row passes the filter, or has the word in its name, so "Bound Fire" is still found).
--   - The footer says what Enter and Shift+Enter do for the selected row; no ghost completions of syntax.
--   - The first word can say what to do: use, cast, summon, equip, target, where, nearest (E.ACTIONS).
--   - .help in plain sentences. Advanced syntax (@kind, key:value, >> channel) isn't taken: a row on top says
--     it's Advanced mode's and offers the switch. .commands and /slash still run.
-- `.advanced` (after a confirmation) switches to the full command line; `.simple` comes back.

local E = {}
ns.Easy = E

local Lower = ns.Lower
local Safe, Str, Num = ns.Safe, ns.Str, ns.Num

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
E.CATEGORIES = {
	{ id = "bags", label = "Bags", kinds = { "items" }, icon = "Interface\\Icons\\INV_Misc_Bag_08" },
	{ id = "quests", label = "Quests", kinds = { "quests", "questie" }, icon = "Interface\\GossipFrame\\AvailableQuestIcon" },
	{ id = "spells", label = "Spells", kinds = { "spells", "talents" }, icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
	{ id = "crafting", label = "Crafting", kinds = { "professions", "recipes", "camp" }, icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ id = "npcs", label = "NPCs", kinds = { "npc" }, icon = "Interface\\Icons\\INV_Misc_Head_Human_01" },
	{ id = "places", label = "Places", kinds = { "maps", "dungeon", "raid" }, icon = "Interface\\Icons\\INV_Misc_Map_01" },
	{ id = "loot", label = "Loot", kinds = { "loot" }, icon = "Interface\\Icons\\INV_Box_02" },
	{ id = "alts", label = "Alts & bank", kinds = { "stored" }, icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue" },
	{ id = "people", label = "Guild & friends", kinds = { "guild", "friends", "who" }, icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
	{ id = "collections", label = "Collections", kinds = { "mounts", "toys", "pets", "titles", "achievementlist" },
		icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
	{ id = "character", label = "Character", kinds = { "gold", "reputation", "currency", "skills", "equipmentset" },
		icon = "Interface\\Icons\\INV_Misc_Book_09" },
	{ id = "emotes", label = "Emotes", kinds = { "slash" }, keep = IsEmote, icon = "Interface\\Icons\\Spell_Shadow_SoothingKiss" },
	{ id = "slash", label = "Slash commands", kinds = { "slash" }, keep = NotEmote, icon = "Interface\\Icons\\INV_Misc_Note_01" },
	{ id = "game", label = "Game", kinds = { "panels", "gameoptions", "macros", "keybinds", "addons", "terminal" },
		icon = "Interface\\Icons\\INV_Misc_Gear_01" },
	{ id = "console", label = "Console settings", kinds = { "cvars" }, icon = "Interface\\Icons\\Trade_Engineering" },
}
E.BY_ID = {}
for _, c in ipairs(E.CATEGORIES) do E.BY_ID[c.id] = c end

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
	ready = "is:ready", passive = "is:passive", capped = "is:capped",
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
}

-- everyday words that are strict filters, never relaxed away when nothing passes ("helm upgrades" lists no helmet you
-- can't wear)
E.HARD_WORDS = { upgrade = true, upgrades = true, skillup = true, skillups = true, ["skill up"] = true, ["skill ups"] = true,
	battlemaster = true, battlemasters = true, ["pvp vendor"] = true, ["pvp vendors"] = true,
	["honor vendor"] = true, ["honor vendors"] = true, ["pvp quartermaster"] = true, pvp = true }

-- left out of a search typed like a sentence (only when another word is left)
E.STOP = { a = true, an = true, the = true, of = true, from = true, ["in"] = true, at = true, on = true, with = true,
	that = true, which = true, gives = true, give = true, giving = true, ["for"] = true, by = true, to = true, ["and"] = true,
	drops = true, dropped = true, drop = true, my = true, some = true, any = true, show = true, find = true, me = true,
	is = true, are = true }

local wordTests = {} -- word -> soft test (made once)
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
	local t = wordTests[w]
	if t ~= nil then return t or nil end
	local spec = E.WORDS[w]
	local f = spec and ns.Filters and ns.Filters.Parse(spec)
	if not f then wordTests[w] = false return nil end
	t = function(e) return f(e) or NameHas(e, w) end
	wordTests[w] = t
	weights[t] = WEAK[w] and 1 or 3
	return t
end

----------------------------------------------------------------------
-- What Enter and Shift+Enter do, in words, for the selected row
----------------------------------------------------------------------

E.VERBS = {
	items = { "show in bags", "use" }, consumable = { "show in bags", "use" }, mats = { "show in bags", "use" },
	gear = { "show", "equip" },
	stored = { "show in bags", "who has it" },
	spells = { "show in spellbook", "cast" },
	npc = { "show on map", "target" },
	gold = { "list in chat", "put in the chat box" }, guild = { "whisper", "invite" }, friends = { "whisper", "invite" }, who = { "whisper", "invite" },
	questie = { "Wowhead link", "show in game" },
	quests = { "show in quest log" },
	maps = { "show on map" },
	toys = { "use", "show in journal" },
	pets = { "summon", "show in journal" },
	titles = { "wear" },
	achievements = { "show", "link in chat" }, achievementlist = { "show", "link in chat" },
	professions = { "open", "link in chat" },
	addons = { "options", "turn on/off" },
	camp = { "show recipe", "make / use" },
	loot = { "show loot" },
	slash = { "run", "put in chat" }, emote = { "do it", "put in chat" },
	cmd = { "run" }, advanced = { "switch to Advanced mode" },
}

--- The two verbs for a row: Enter's, and Shift+Enter's (nil when it has none).
function E.Verbs(e)
	if not e or e.noActivate then return nil end
	if e.catId then return "look in " .. tostring(e.name) end
	if e.completion then return "search there" end
	if e.actionVerb then return Lower(e.actionVerb), nil end
	local v = E.VERBS[(e.emote and "emote") or e.kind or ""]
	local enter = v and v[1] or "open"
	local shift = v and v[2]
	if not shift and (e.secondary or e.secondarySecure) then shift = "more" end
	return enter, shift
end

----------------------------------------------------------------------
-- Action words: "use hearthstone", "cast frost nova", "summon raptor", "target hogger", "nearest innkeeper"
----------------------------------------------------------------------

-- The first word of a search can say what to do. `map`: the kinds it looks in, and for each the row's action it
-- runs on Enter ("p" its usual one, "s" its Shift+Enter one); no map: any kind, the usual action (only the word
-- is dropped: "show", "open"). `keep`: only rows it says yes to. `nearest`: NPCs sorted by how far away they are.
E.ACTIONS = {
	use = { label = "Use", map = { items = "s", toys = "p", camp = "s" } },
	cast = { label = "Cast", map = { spells = "s" } },
	summon = { label = "Summon", map = { mounts = "p", pets = "p" } },
	mount = { label = "Summon", map = { mounts = "p" } },
	ride = { label = "Summon", map = { mounts = "p" } },
	equip = { label = "Equip", map = { items = "s" } },
	wear = { label = "Wear", map = { titles = "p", items = "s" } },
	target = { label = "Target", map = { npc = "s" } },
	link = { label = "Link in chat", map = { achievementlist = "s", professions = "s" } },
	["do"] = { label = "Do", map = { slash = "p" }, keep = IsEmote },
	where = { label = "Where is", map = { npc = "p", maps = "p", quests = "p", questie = "s" } },
	nearest = { label = "Nearest", map = { npc = "p" }, nearest = true },
	closest = { label = "Nearest", map = { npc = "p" }, nearest = true },
	nearby = { label = "Nearest", map = { npc = "p" }, nearest = true },
	who = { label = "Who", map = { who = "p" } },
	show = { label = "Show" }, open = { label = "Open" }, find = { label = "Find" },
}

-- the words that name what an NPC does (not who it is): "nearest" then keeps to NPCs friendly to you
E.ROLE_WORDS = { repair = true, repairs = true, inn = true, innkeeper = true, bank = true, banker = true, flight = true,
	fp = true, flightmaster = true, ah = true, auction = true, auctioneer = true, stable = true, stablemaster = true,
	vendor = true, vendors = true, trainer = true, trainers = true, questgiver = true, battlemaster = true,
	battlemasters = true, ["pvp vendor"] = true, ["pvp vendors"] = true, ["honor vendor"] = true,
	["honor vendors"] = true, ["pvp quartermaster"] = true, pvp = true }

--- The action a search's first word names, or nil (only with another word after it, or an everyday word).
function E.Action(word) return E.On() and E.ACTIONS[word] or nil end

local function False() return false end

--- A row as the action wants it: its Shift+Enter action made its Enter (a view on the row, which stays as it is);
--- rows whose usual action is the one wanted come back as they are.
function E.ActionView(e, act)
	local how = act.map and act.map[e.kind]
	if how ~= "s" or not (e.secondary or e.secondarySecure) then return e end
	return setmetatable({
		secure = e.secondarySecure or false, isOpen = e.secondaryIsOpen or False, after = e.secondaryAfter or false,
		activate = e.secondary or false, actionVerb = act.label, actionOf = e, -- (false: never the row's own Enter)
	}, { __index = e })
end

----------------------------------------------------------------------
-- Alt+`: what a Simple search says, written in Advanced mode's syntax
----------------------------------------------------------------------

local function KindWord(kind)
	local p = ns.providers[kind]
	return p and ("@" .. ((p.aliases and p.aliases[1]) or p.id)) or nil
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
	local act = #words > 1 and E.ACTIONS[Lower(words[1])] or nil
	if act then
		table.remove(words, 1)
	elseif #words > 1 then
		local tail = E.ACTIONS[Lower(words[#words])]
		if tail and tail.nearest then act = tail; table.remove(words) end
	end
	return act
end

-- a word's pieces that are everyday words as their filters ("-boe" -> -is:boe, "sword|axe" -> type:sword|type:axe,
-- rare&sword -> q:rare&type:sword; plain pieces stay words: "-cloth")
local function PieceFilter(neg, a) return neg .. (E.WORDS[a] or a) end
local function AdvancedPart(w) return (w:gsub("([-!]?)([^|&]+)", PieceFilter)) end

--- A Simple search as Advanced mode would type it: the picked category or the action word's kinds as @kinds,
--- "nearest" as @npc sort:nearest (with faction:friendly for a role), a place as in:<place>, everyday words as their
--- key:value filters ("attack power" = stat:ap), sentence words dropped; other words (and any Advanced syntax
--- already typed) stay. Ends with a space to type on. "" for an empty search.
function E.ToAdvanced(text, category)
	local words = {}
	for w in tostring(text or ""):gmatch("%S+") do words[#words + 1] = w end
	local kinds, filters, plain, seen = {}, {}, {}, {}
	local function Add(list, w) if w and not seen[w] then seen[w] = true; list[#list + 1] = w end end
	E.JoinPairs(words) -- two everyday words that mean one thing ("attack power food")
	E.JoinLogic(words) -- "sword or axe" -> sword|axe, "not boe" -> -boe (made filters below)
	-- the first word can say what to do ("use hearthstone", "nearest innkeeper")
	local act = ActionOf(words)
	local nearest
	if act then
		nearest = act.nearest
		if act.map then
			local ks = {}
			for k in pairs(act.map) do ks[#ks + 1] = k end
			table.sort(ks)
			for _, k in ipairs(ks) do Add(kinds, KindWord(k)) end
		end
	end
	if not (act and act.map) and E.BY_ID[category or ""] then
		for _, k in ipairs(E.BY_ID[category].kinds) do Add(kinds, KindWord(k)) end
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
	for _, w in ipairs(lower) do if not E.STOP[w] then others = others + 1 end end
	for _, w in ipairs(lower) do
		if E.IsAdvancedWord(w) then
			if w:sub(1, 1) == "@" then Add(kinds, w) else Add(filters, w) end
		elseif w:find("[|&]") or w:find("^[-!]%a") then
			Add(filters, AdvancedPart(w))
		elseif E.WORDS[w] then
			Add(filters, E.WORDS[w])
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
	if nearest then Add(kinds, "@npc") end
	-- an NPC's role (trainer, vendor, innkeeper...) means one you can use: friendly to you, as Simple mode's place
	-- and nearest searches keep to ("mining trainer in org" never meant Ironforge's)
	if role then Add(filters, "faction:friendly") end
	if nearest then Add(filters, "sort:nearest") end
	local out = {}
	for _, list in ipairs({ kinds, plain, filters }) do
		for _, w in ipairs(list) do out[#out + 1] = w end
	end
	return #out > 0 and (table.concat(out, " ") .. " ") or ""
end

----------------------------------------------------------------------
-- The empty prompt's faint examples (a different one each time it opens)
----------------------------------------------------------------------

E.EXAMPLES = {
	"try: stamina food", "try: nearest innkeeper", "try: use hearthstone", "try: dance", "try: rare sword",
	"try: where is hogger", "try: nearest repair", "try: shield that drops from kresh",
	"try: attack power food", "try: vendor goldshire", "try: mining trainer in org", "try: stormwind", "try: gold",
	"try: nearest mailbox", "try: nearest dungeon", "try: sword or axe", "try: rare ring not boe", "try: group browser",
	"try: who priest undercity", "try: weapon damage", "try: online", "try: where should i level",
	"try: what dungeon should i do", "try: where should i fish", "try: nearby battlemaster", "try: nearest pvp vendor",
}
-- Advanced mode's: its syntax (@kinds, key:value filters, >> chat, .commands)
E.ADV_EXAMPLES = {
	"try: @npc is:vendor in:barrens", "try: @gear slot:feet ilvl:20+", "try: hogger >> party",
	"try: @item q:rare+ is:boe", "try: @questie lvl:20-25 in:ashenvale", "try: @item stat:sta>=10",
	"try: @npc trainer:class faction:friendly", "try: @recipe stat:agility", "try: linen cloth >> guild",
	"try: @npc sells:coarse_thread", "try: @stored linen cloth", "try: @gold", "try: @achievement is:todo",
	"try: @dungeon sort:nearest", "try: @map lvl:30", "try: @dungeon lvl:25", "try: @recipe is:skillup", "try: @friend is:online", "try: @who orc lvl:20-30",
	"try: @item is:boe|q:epic", "try: @spell is:ready", "try: @gear slot:head|chest -is:soulbound", "try: @item q:rare|epic", "try: @npc is:repair sort:nearest", "try: @npc trainer:mining near:500", "try: @cvar changed", "try: .filters (every key:value)", "try: .theme dracula",
	"tip: Up = last command, Down = recent picks",
}
-- Examples made for the character playing (their class, professions, bags, level, where they are, guild): mixed in
-- with the fixed ones, every other suggestion. Worked out from lists already built (never a big list on its own),
-- again after a minute or when the level or zone changed.
local SLOT_WORDS = { "helm", "boots", "gloves", "belt", "bracers", "cloak", "ring", "chest", "legs", "shoulders" }
local PRIMARY = { WARRIOR = "str", PALADIN = "str", DEATHKNIGHT = "str", ROGUE = "agi", HUNTER = "agi",
	MAGE = "int", WARLOCK = "int", PRIEST = "int", DRUID = "int", SHAMAN = "int" }
E.rand = math.random

local function Entries(id)
	local p = ns.providers[id]
	if not p then return {} end
	local ok, list = pcall(ns.GetEntries, ns, p)
	return ok and type(list) == "table" and list or {}
end
local function Pick(list)
	if #list == 0 then return nil end
	return list[E.rand(1, #list)]
end
local function Short(s, n) return type(s) == "string" and s ~= "" and #s <= (n or 28) and s or nil end

--- A working Advanced example: its @kinds known, its filters parse (made from game data, so checked here).
local function Valid(ex)
	for w in ex:gmatch("%S+") do
		if w:sub(1, 1) == "@" and not ns:ResolveProvider(w:sub(2)) then return false end
		if w:find("^[-!]?%a+:%S") and not (ns.Filters and ns.Filters.Parse(w)) then return false end
	end
	return true
end

--- What the examples are made from: the character (level, class), its professions and consumables, a dungeon about
--- its level, where it is, its guild.
local function Gather()
	local f = {}
	f.level = UnitLevel and Num(Safe(UnitLevel, "player"))
	local className, classFile = Safe(UnitClass, "player")
	className, f.classFile = Str(className), Str(classFile)
	f.cls = className and Lower(className)
	-- professions you have (their rows' names), and a consumable you carry
	local profs = {}
	for _, e in ipairs(Entries("professions")) do
		local n = Short(e.name and Lower(e.name), 20)
		if n then profs[#profs + 1] = n end
	end
	f.prof = Pick(profs)
	f.carry = {}
	for _, e in ipairs(Entries("consumables")) do
		local n = Short(e.name and Lower(e.name), 24)
		if n then f.carry[#f.carry + 1] = n end
	end
	-- a dungeon about your level (WoW Forever's entrances)
	local fit = {}
	local I = ns.Integrations
	local level = f.level
	for _, d in ipairs(I and I.ENTRANCES or {}) do
		if level and not d[5] and d[6] and level >= d[6] - 3 and level <= d[7] then fit[#fit + 1] = Lower(d[1]):gsub(" %(.*%)$", "") end
	end
	f.dungeon = Pick(fit)
	local zoneName = GetRealZoneText and Str(Safe(GetRealZoneText))
	f.zone = Short(zoneName and Lower(zoneName), 22)
	f.inGuild = IsInGuild and Safe(IsInGuild)
	return f
end

-- Advanced mode's, each kept only if it works here (its @kinds known, its filters parse)
local function AdvancedExamples(f, add, out)
	local level, zone, prof = f.level, f.zone, f.prof
	if f.classFile and PRIMARY[f.classFile] then add("@gear stat:" .. PRIMARY[f.classFile] .. " is:upgrade") end
	if prof then add("@recipe is:skillup " .. prof); add("@npc trainer:" .. prof:gsub(" ", "") .. " sort:nearest") end
	if f.inGuild then add("@guild is:online") end
	if level then add("@questie lvl:" .. level .. "-" .. (level + 2) .. (zone and (" in:" .. zone:gsub(" ", "_")) or "")) end
	if f.dungeon then add("@loot " .. f.dungeon .. " is:upgrade") end
	local kept = {}
	for _, ex in ipairs(out) do if Valid(ex:gsub("^try: ", "")) then kept[#kept + 1] = ex end end
	return kept
end

local function SimpleExamples(f, add, out)
	local prof, dungeon = f.prof, f.dungeon
	if f.cls then add("nearest " .. f.cls .. " trainer") end
	if prof then add(prof .. " skillup"); add("nearest " .. prof .. " trainer") end
	if #f.carry > 0 then add("use " .. Pick(f.carry)) end
	if f.level and f.level < 60 then add(Pick(SLOT_WORDS) .. " upgrades") end
	if dungeon then add(dungeon); add(dungeon .. " upgrades") end
	if f.zone then add("vendor " .. f.zone) end
	if f.inGuild then add("online") end
	add("nearest flight master")
	return out
end

function E.PersonalExamples(advanced)
	local out = {}
	local function add(s) if s then out[#out + 1] = "try: " .. s end end
	local f = Gather()
	if advanced then return AdvancedExamples(f, add, out) end
	return SimpleExamples(f, add, out)
end

local function Examples() return E.On() and E.EXAMPLES or E.ADV_EXAMPLES end
local pool = { at = 0 }
--- The list the suggestions come from: the character's own examples between the fixed ones (one of each in turn).
local function Pool()
	local adv = not E.On()
	local now = GetTime and GetTime() or 0
	local level = UnitLevel and Num(Safe(UnitLevel, "player"))
	local zone = GetRealZoneText and Str(Safe(GetRealZoneText))
	if pool.list and pool.adv == adv and pool.level == level and pool.zone == zone and now - (pool.made or 0) < 60 then return pool.list end
	local fixed, mine = Examples(), {}
	local ok, got = pcall(E.PersonalExamples, adv)
	if ok and type(got) == "table" then mine = got end
	local list, i, j = {}, 1, 1
	while i <= #fixed or j <= #mine do
		if j <= #mine then list[#list + 1] = mine[j]; j = j + 1 end
		if i <= #fixed then list[#list + 1] = fixed[i]; i = i + 1 end
	end
	pool.list, pool.adv, pool.level, pool.zone, pool.made = list, adv, level, zone, now
	return list
end
E.ExamplePool = Pool
function E.NextExample()
	local list = Pool()
	pool.at = pool.at % #list + 1
	return list[pool.at]
end
function E.Example()
	local list = Pool()
	return list[(math.max(1, pool.at) - 1) % #list + 1]
end

----------------------------------------------------------------------
-- Advanced mode's syntax in Simple mode: not taken, the player is told where it lives
----------------------------------------------------------------------

--- Is this word Advanced mode's syntax (an @kind, a key:value filter, >>)?
function E.IsAdvancedWord(w)
	if w:sub(1, 1) == "@" or w:sub(1, 2) == ">>" then return true end
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
	name = "@, >> and key:value are for Advanced mode", kind = "advanced", kindLabel = "",
	detail = "Enter to switch (or type .advanced)", icon = "Interface\\Icons\\INV_Misc_Gear_01",
	activate = OfferAdvanced,
}

-- ">>" typed in Simple mode: sending is in the right-click menu here
E.SEND_ROW = {
	name = "Right-click a result to send it to chat", kind = "advanced", kindLabel = "", noActivate = true,
	detail = "say, party, guild, whisper (>> is Advanced mode's)", icon = "Interface\\Icons\\INV_Letter_15",
}

----------------------------------------------------------------------
-- .advanced / .simple (the modes; db.easyMode == false is Advanced)
----------------------------------------------------------------------

local dialog -- the confirmation, on the Panel pattern (it takes the terminal's place)

local function Confirm(yes)
	if dialog then dialog:Hide() end
	if yes then
		E.Set(false)
		ns:Print("Advanced mode: the full command line (@kinds, key:value filters, .commands, >> chat). .help lists it all; .simple goes back.")
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
		ns:Print("Not in combat: type .advanced again afterwards.")
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
		dialog.yes = Button(dialog, "Switch to Advanced", -92, function() Confirm(true) end)
		dialog.no = Button(dialog, "Stay in Simple", 92, function() Confirm(false) end)
		dialog:SetScript("OnKeyDown", function(_, key)
			if key == "ENTER" then Confirm(true)
			elseif key == "ESCAPE" or key == "`" then Confirm(false) end
		end)
	end
	P.Opening(app)
	local t = P.Layout(dialog)
	dialog.title:SetText("|cff" .. t.text .. "Switch to Advanced mode?|r")
	dialog.body:SetText("|cff" .. t.dim .. "The full command line: @kinds (@npc Hogger), key:value filters (q:rare+ lvl:20-30), "
		.. ".commands and >> to send to chat. Words like \"rare\" and \"use\" become plain search words. "
		.. ".simple comes back.|r")
	-- as tall as the text: title, text, buttons, with the same margin around each
	local h = dialog.body:GetStringHeight()
	h = type(h) == "number" and h > 0 and h or 42
	dialog:SetSize(E.CONFIRM_W, math.floor(E.CONFIRM_BODY_Y + h + E.CONFIRM_PAD + 24 + E.CONFIRM_PAD + 4))
	dialog:Show()
end

ns:RegisterCommand("advanced", {
	desc = "Switch to Advanced mode: the full command line (@kinds, key:value filters, >> chat), after a confirmation",
	aliases = { "hardmode", "hard" },
	run = function()
		if not E.On() and not E.temp then return { "Already in Advanced mode (.simple goes back)." } end
		-- after this press is done (the terminal closes on a command): the dialog takes its place
		C_Timer.After(0, E.ShowConfirm)
		return {}
	end,
})

ns:RegisterCommand("fuzzy", {
	desc = "Pure fuzzy finding, this once (.fzf too; also Tab+`: hold Tab, press `): every list, by name only; Enter takes the result to Simple mode, Shift+Enter to Advanced",
	aliases = { "fzf" },
	run = function(args)
		-- (after this press is done: running a command closes the terminal first)
		C_Timer.After(0, function() ns.UI:FuzzyOnce(args) end)
		return {}
	end,
})

ns:RegisterCommand("simple", {
	desc = "Switch to Simple mode: plain words (use hearthstone, nearest innkeeper, stamina food), results sorted by where they are",
	aliases = { "easymode", "easy" },
	run = function()
		if E.On() then return { "Already in Simple mode (.advanced for the full command line)." } end
		E.Set(true)
		return { "Simple mode: type what you're looking for in plain words (\"use hearthstone\", \"nearest innkeeper\", \"stamina food\"). .advanced for the full command line." }
	end,
})

--- .help in Simple mode: plain sentences.
function E.HelpLines()
	return {
		"Terminal: type the name of anything (an item, a quest, a spell, a mount, a place, an NPC, an emote) and press Enter to open it.",
		"Typing lists where it was found (Bags, Quests, Emotes...): pick one with Enter or a click, then the thing itself. Tab goes back to all of them.",
		"Start with what to do: use, cast, summon, equip, wear, target, where, nearest (\"use hearthstone\", \"nearest innkeeper\").",
		"Shift+Enter does the other thing (use the item, cast the spell, target the NPC); the footer says which. Right-click a row, or press Shift+Right, for all it can do.",
		"Words like rare, epic, boe, food, potion, stamina, ready, todo, vendor, trainer narrow the search: \"stamina food\", \"vendor ratchet\" (a place's NPCs).",
		"Ask where to go: \"where should i level\", \"what dungeon should i do\", \"where should i fish\" (or \"zones for level 35\").",
		"\"or\" and \"not\" work too: \"sword or axe\", \"rare ring not boe\", \"potion not minor\".",
		"Down on an empty prompt brings back your last search; Up goes through what you ran before. Esc closes.",
		"Alt+` turns what you typed into Advanced mode's command line, for that one time (Simple again once it closes).",
		"Tab+` (hold Tab, press `; or .fuzzy / .fzf) is pure fuzzy finding: every list at once, by name only. Enter takes the result to Simple mode, Shift+Enter to Advanced.",
		"Ctrl+click an item (or a spell, quest, achievement) in chat to look it up here.",
		"Want the full command line (@kinds, filters, .commands, chat)? Type .advanced",
	}
end

