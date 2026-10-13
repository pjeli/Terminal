local ns = select(2, ...)
local L = ns.L

-- Filters for the other rows: levels (lvl:), counts (count:), recipes (is:craftable, is:skillup), quests and
-- achievements (is:done/todo/complete), spells (is:ready, is:passive), currencies (is:capped), reputations
-- (standing:), guild and friends (is:online); then the values Tab offers after "key:" and .filters' list.

local F = ns.Filters
local P = F._
local KEYS, IS = P.KEYS, P.IS
local Range = F.Range
local NpcID, NpcField = P.NpcID, P.NpcField
local ItemInfo = P.ItemInfo
local Lower = ns.Lower
local Secret = ns.Secret

--- The quest a row is (not a quest item that merely belongs to one).
local function QuestOf(e)
	local q = rawget(e, "qid") or e.qid
	if q then return q end
	if e.kind == "quests" then return e.questID end
end

----------------------------------------------------------------------
-- What rows know
----------------------------------------------------------------------

--- Level range of a row: items (the level they need), quests, Questie NPCs, dungeons, zones.
local function Levels(e)
	if e.itemID then
		local info = ItemInfo(e.itemID)
		local l = info and info.minLevel
		if type(l) == "number" then return l, l end
		return nil
	end
	if NpcID(e) then
		local lo, hi = NpcField(e, "minLevel"), NpcField(e, "maxLevel")
		if type(lo) == "number" then return lo, type(hi) == "number" and hi or lo end
		return nil
	end
	local l = e.level
	if type(l) == "number" then
		local lo = e.minLevel -- (dungeons and raids: their range)
		if type(lo) == "number" and lo <= l then return lo, l end
		return l, l
	end
	if e.kind == "maps" and ns.Zones then -- (zones: their level band)
		local z = ns.Zones.Of(e.mapID)
		if z and z.min then return z.min, z.max end
	end
end

local function Count(e)
	local n = e.total or e.count
	return type(n) == "number" and n or nil
end

local function Craftable(e)
	local rg = e.reagents
	if type(rg) ~= "table" or #rg == 0 then return false end
	local count = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	if not count then return false end
	for _, r in ipairs(rg) do
		local have = count(r[1], true) or 0
		if have < (r[2] or 1) then return false end
	end
	return true
end

-- Recipe difficulty, as the profession window colours it: Enum.TradeskillRelativeDifficulty (Optimal 0 = orange,
-- Medium 1 = yellow, Easy 2 = green, Trivial 3 = grey). Kept with each recipe when its window was last read
-- (Professions.lua: `diff`, refreshed whenever the window's list updates, as it does after a skill-up).
local DIFF = (Enum and Enum.TradeskillRelativeDifficulty) or {}
F.DIFF = {
	orange = DIFF.Optimal or 0, yellow = DIFF.Medium or 1, green = DIFF.Easy or 2, grey = DIFF.Trivial or 3,
}
local function Difficulty(e)
	local d = e.recipeID and e.difficulty
	return type(d) == "number" and d or nil
end
local function DiffIs(which) return function(e) return Difficulty(e) == F.DIFF[which] end end
local function SkillUp(e)
	local d = Difficulty(e)
	return d ~= nil and (d == F.DIFF.orange or d == F.DIFF.yellow)
end
-- is: values only recipes answer: "@profession is:skillup" searches the recipes too
F.RECIPE_IS = { skillup = true, skillups = true, orange = true, yellow = true, green = true, grey = true, gray = true,
	trivial = true, craftable = true }
-- is: values only the recipes you don't know answer: "@recipe is:unknown" searches those too (MissingRecipes.lua)
F.MISSING_IS = { unknown = true, unlearned = true, missing = true, learnable = true, canlearn = true }
--- Does this typed word ask for the recipes you don't know (is:unknown, is:learnable)?
function F.MissingWord(w)
	for v in Lower(w):gmatch("is:(%a+)") do if F.MISSING_IS[v] then return true end end
	return false
end
--- Does this typed word filter by something only recipes have (is:skillup, is:orange|yellow, -is:grey)?
function F.RecipeWord(w)
	for v in Lower(w):gmatch("is:(%a+)") do if F.RECIPE_IS[v] then return true end end
	return false
end

local function Done(q)
	return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q) and true or false
end

local function Complete(e)
	if e.kind ~= "quests" or not e.questID then return false end
	local f = C_QuestLog and (C_QuestLog.ReadyForTurnIn or C_QuestLog.IsComplete)
	return f and f(e.questID) and true or false
end

-- A spell off cooldown now (not cached: it changes). The global cooldown doesn't count; passives are never
-- ready; a cooldown the game keeps secret (in combat) can't be judged.
local GCD = 1.5
local function SpellReady(e)
	if e.kind ~= "spells" or e.passive or type(e.spellID) ~= "number" then return false end
	local start, duration, enabled
	if C_Spell and C_Spell.GetSpellCooldown then
		local ok, cd = pcall(C_Spell.GetSpellCooldown, e.spellID)
		if not ok or type(cd) ~= "table" then return false end
		start, duration, enabled = cd.startTime, cd.duration, cd.isEnabled
	elseif _G.GetSpellCooldown then
		local ok, s, d, en = pcall(_G.GetSpellCooldown, e.spellID)
		if not ok then return false end
		start, duration, enabled = s, d, en
	else
		return false
	end
	if Secret(start) or Secret(duration) or Secret(enabled) then return false end
	if enabled == false or enabled == 0 then return false end -- (waits for something to end first: not ready)
	if type(duration) ~= "number" or type(start) ~= "number" then return false end
	if duration <= GCD or start <= 0 then return true end
	return start + duration <= GetTime()
end

--- is:ready: a spell off cooldown, or a quest ready to turn in.
local function Ready(e)
	if e.kind == "spells" then return SpellReady(e) end
	return Complete(e)
end

-- Currencies (rows: quantity, maxQuantity; maxWeeklyQuantity, quantityEarnedThisWeek): at the cap, or this week's.
local Number = ns.Num
local function Capped(e)
	if e.kind ~= "currency" then return false end
	local n, max = Number(e.quantity), Number(e.maxQuantity)
	if n and max and max > 0 and n >= max then return true end
	local week, wmax = Number(e.quantityEarnedThisWeek), Number(e.maxWeeklyQuantity)
	return week ~= nil and wmax ~= nil and wmax > 0 and week >= wmax
end

--- Done / not done: quests by the game's record; achievements by their row's completed (rows without it aren't judged).
local function DoneOf(e)
	local q = QuestOf(e)
	if q then return Done(q) end
	if e.kind == "achievements" and type(e.completed) == "boolean" then return e.completed end
	return nil
end

-- Reputation standings 1-8 (Hated .. Exalted): the game's names (both genders' where they differ), and English
-- always. Rows carry reaction (Reputation.lua); friendship and renown factions have none and are left out.
local STANDING_ENGLISH = { "hated", "hostile", "unfriendly", "neutral", "friendly", "honored", "revered", "exalted" }
local standingWords -- lowercase name -> 1-8 (made on first use: the game's globals are all in by then)
local function StandingWords()
	if standingWords then return standingWords end
	standingWords = {}
	for i, w in ipairs(STANDING_ENGLISH) do standingWords[w] = i end
	for i = 1, 8 do
		for _, g in ipairs({ _G["FACTION_STANDING_LABEL" .. i], _G["FACTION_STANDING_LABEL" .. i .. "_FEMALE"] }) do
			if type(g) == "string" and g ~= "" then standingWords[Lower(g)] = i end
		end
	end
	return standingWords
end
--- The standing names for Tab: the game's own (lowercase), else English.
local function StandingNames()
	local out = {}
	for i = 1, 8 do
		local g = _G["FACTION_STANDING_LABEL" .. i]
		out[i] = type(g) == "string" and g ~= "" and Lower(g):gsub(" ", "_") or STANDING_ENGLISH[i]
	end
	return out
end
--- A standing value as a range: names stand for their numbers (honored+ = 6+, <friendly = <5, honored-exalted = 6-8).
local function StandingRange(v)
	local words = StandingWords()
	local bad = false
	local text = v:gsub("[^%d%-%+<>=]+", function(w)
		local n = words[(w:gsub("^%s+", ""):gsub("%s+$", ""))]
		if not n then bad = true return w end
		return tostring(n)
	end)
	if bad then return nil end
	return Range(text)
end
-- (tests: Npcs.lua's F.ClearSold forgets the standing names too)
P.ClearStanding = function() standingWords = nil end
----------------------------------------------------------------------
-- Keys for these rows
----------------------------------------------------------------------

KEYS.lvl = function(v)
	local r = Range(v)
	return r and function(e)
		local lo, hi = Levels(e)
		if not lo then return false end
		if lo == hi then return r(lo) end
		for l = lo, hi do if r(l) then return true end end -- (an NPC of levels 10-12)
		return false
	end
end
KEYS.level = KEYS.lvl

-- fish: zones by the fishing skill they need (Zones.lua): fish:mine (your skill: the zones you can fish), fish:150 (what
-- 150 is enough for), fish:130-205 (needing that much). The Advanced form of "where should i fish".
KEYS.fish = function(v)
	local Z = ns.Zones
	local need
	if v == "mine" or v == "me" or v == "my" then
		need = function() return (Z and Z.FishingSkill and Z.FishingSkill()) or 0 end
	elseif tonumber(v) then
		local n = tonumber(v)
		need = function() return n end
	end
	local r = not need and Range(v)
	if not (need or r) then return nil end
	local skill -- (read once per filter: the first row asks)
	return function(e)
		local z = e.kind == "maps" and Z and Z.Of(e.mapID)
		if not (z and z.fish) then return false end
		if r then return r(z.fish) end
		skill = skill or need()
		return z.fish <= skill
	end
end
KEYS.fishing = KEYS.fish

KEYS.count = function(v)
	local r = Range(v)
	return r and function(e) return r(Count(e)) end
end
KEYS.qty = KEYS.count

-- class: a row's class (talents: yours and other classes'): an English or the game's class name, its start, or mine
local function Squash(x) return (Lower(tostring(x or "")):gsub("[%s_%-']", "")) end
KEYS.class = function(v)
	if v == "" then return nil end
	if v == "mine" or v == "me" or v == "my" or v == "myclass" then
		local ok, _, file = pcall(UnitClass, "player")
		local mine = ok and file or nil
		return function(e) return e.classFile ~= nil and e.classFile == mine end
	end
	local want = Squash(v)
	return function(e)
		if not e.classFile then return false end
		local f, n = Squash(e.classFile), Squash(e.className)
		return f:sub(1, #want) == want or n:sub(1, #want) == want
	end
end

-- do:<action> (Advanced): Simple mode's action words written as Advanced syntax ("use hearthstone" -> "@item
-- do:use hearthstone", Alt+`): not a filter (every row stays); the search makes each row's Enter that action, as Simple
-- mode's action word does (Search.lua's Scan.Parse, Easy.ActionView); with no @kind, the action's own lists
--- "do:use" -> the action (Easy.ACTIONS) and its word, else nil.
function F.ActionOf(word)
	if type(word) ~= "string" then return nil end
	local k, v = word:match("^(%a+):(%a+)$")
	if not (k and Lower(k) == "do") then return nil end
	local a = ns.Easy and ns.Easy.ACTIONS[Lower(v)]
	if a and a.map and not a.nearest then return a, Lower(v) end
end
KEYS["do"] = function(v)
	if not F.ActionOf("do:" .. v) then return nil end
	return function() return true end
end

KEYS.standing = function(v)
	local r = StandingRange(v)
	return r and function(e) return e.kind == "reputation" and r(e.reaction) or false end
end
KEYS.rep = KEYS.standing

IS.done = function(e) return DoneOf(e) == true end
IS.todo = function(e) return DoneOf(e) == false end
IS.complete = Complete
IS.ready = Ready
IS.passive = function(e) return e.kind == "spells" and e.passive == true end
-- spells you can cast that aren't on any bar or key (Spells.lua)
IS.unplaced = function(e) return e.kind == "spells" and ns.Spells ~= nil and ns.Spells.Unplaced(e) end
IS.capped = Capped
IS.craftable = Craftable
IS.skillup, IS.orange, IS.yellow = SkillUp, DiffIs("orange"), DiffIs("yellow")
IS.green = DiffIs("green")
local RecipeGrey = DiffIs("grey")
-- grey: a recipe the window shows grey, or a quest the quest log shows grey for your level (Quests.lua's `grey`)
IS.grey = function(e)
	if e.kind == "quests" then return e.grey == true end
	return RecipeGrey(e)
end
-- quests in a zone you've left behind (its levels, as the world map says them, top out below yours), and the ones to
-- drop: grey or left behind, not complete ("quests to drop", QuestDrop.lua)
IS.leftbehind = function(e) return e.kind == "quests" and e.behind ~= nil end
IS.drop = function(e) return e.kind == "quests" and e.drop == true end
IS.outleveled, IS.outlevelled, IS.droppable = IS.leftbehind, IS.leftbehind, IS.drop
-- guild members and friends (Social.lua)
IS.online = function(e) return e.online == true end
IS.offline = function(e) return e.online == false end
-- your mail (Mail.lua): COD, running out within 3 days, unread, sent back to you, from the auction house, with gold
local function MailIs(test) return function(e) return e.kind == "mail" and e.mailKind == "mail" and test(e, e.mail) or false end end
IS.cod = MailIs(function(_, m) return m.cod ~= nil end)
IS.expiring = MailIs(function(e) return e.soon == true end)
IS.unread = MailIs(function(_, m) return not m.read end)
IS.returned = MailIs(function(_, m) return m.returned == true end)
-- (the auction house's news on its way counts as auction mail, a sale with its price as gold; mail you sent: is:sent,
-- to others and to your alts)
IS.auction = function(e) return e.kind == "mail" and (e.mailKind == "auction" or (e.mailKind == "mail" and e.mail.auction ~= nil)) or false end
IS.money = function(e)
	return e.kind == "mail" and ((e.mailKind == "auction" and e.money ~= nil) or (e.mailKind == "mail" and e.mail.money ~= nil)) or false
end
IS.sent = function(e) return e.kind == "mail" and (e.mailKind == "sent" or (e.mailKind == "mail" and e.mail.sent ~= nil)) or false end
IS.incoming = function(e) return e.kind == "mail" and e.mailKind == "auction" or false end
IS.pending, IS.expected = IS.incoming, IS.incoming
IS.gold, IS.ah = IS.money, IS.auction
-- your group (Group.lua): dead (or a ghost), the role set, out of range (the game's own test; hidden in combat: not
-- judged), missing a buff the group can give; is:online / is:offline above read the same `online`
local function GroupIs(test) return function(e) return e.kind == "group" and test(e) or false end end
IS.dead = GroupIs(function(e) return e.dead == true end)
IS.alive = GroupIs(function(e) return not e.dead end)
IS.tank = GroupIs(function(e) return e.role == "TANK" end)
IS.healer = GroupIs(function(e) return e.role == "HEALER" end)
IS.dps = GroupIs(function(e) return e.role == "DAMAGER" end)
IS.far = GroupIs(function(e) return e.inRange == false end)
IS.inrange = GroupIs(function(e) return e.inRange == true end)
IS.unbuffed = GroupIs(function(e) return e.missing ~= nil and #e.missing > 0 end)
IS.outofrange, IS.near, IS.damage, IS.damager, IS.healers, IS.tanks = IS.far, IS.inrange, IS.dps, IS.dps, IS.healer, IS.tank
-- missing:<buff>: group members lacking it (fortitude, int, mark, spirit, shadow, blessing, or any buff's name)
-- quests with your party (GroupQuests.lua): someone in your party lacks it and the game lets you share it; someone in
-- your party is on it too
local function PartyIs(test) return function(e) return e.kind == "groupquests" and test(e) or false end end
IS.shareable = PartyIs(function(e) return e.canShare == true end)
IS.together = PartyIs(function(e) return e.together == true end)
IS.sharable, IS.toshare, IS.common, IS.same = IS.shareable, IS.shareable, IS.together, IS.together
-- lockouts (Lockouts.lua): a raid's (world bosses too) or a dungeon's
IS.raid = function(e) return e.kind == "lockouts" and e.isRaid == true end
IS.dungeon = function(e) return e.kind == "lockouts" and not e.isRaid end
IS.raids, IS.dungeons, IS.heroic = IS.raid, IS.dungeon, IS.dungeon
KEYS.missing = function(v) return ns.Group and ns.Group.MissingFilter(v) or nil end
KEYS.needs = KEYS.missing
IS.notdone, IS.undone = IS.todo, IS.todo
IS.maxed, IS.offcooldown = IS.capped, IS.ready
IS.skillups, IS.gray, IS.trivial = IS.skillup, IS.grey, IS.grey

-- the values Tab offers after "key:" (the main spellings only)
F.VALUES = {
	is = { "done", "todo", "complete", "ready", "usable", "equippable", "upgrade", "online", "offline", "quest", "soulbound", "boe", "craftable", "skillup",
		"orange", "yellow", "green", "grey", "leftbehind", "drop", "passive", "unplaced",
		"capped", "vendor", "trainer", "classtrainer", "proftrainer", "flightmaster", "innkeeper", "banker", "repair",
		"auctioneer", "questgiver", "stablemaster", "battlemaster", "pvpvendor", "pvp", "flightpath", "learned", "unlearned", "unknown", "learnable",
		"cod", "expiring", "unread", "returned", "auction", "money", "sent", "incoming", "dead", "tank", "healer", "dps", "far", "inrange", "unbuffed",
		"shareable", "together", "raid", "dungeon" },
	missing = { "fortitude", "intellect", "wild", "spirit", "shadow", "blessing" },
	standing = StandingNames(),
	q = F.QUALITIES, quality = F.QUALITIES,
	stat = F.STATS, stats = F.STATS,
	["in"] = { "bags", "bank", "mail", "guild", "warband", "equipped" },
	faction = { "horde", "alliance", "neutral", "friendly" },
	sort = { "nearest", "plan" },
	fish = { "mine", "75", "150", "225", "300" },
	class = { "mine", "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" },
	["do"] = { "use", "cast", "summon", "equip", "wear", "target", "link", "where" },
	near = { "100", "300", "500", "1000" },
	trainer = { "class", "classes", "profession", "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage",
		"warlock", "druid", "blacksmithing", "leatherworking", "tailoring", "alchemy", "engineering", "enchanting",
		"herbalism", "mining", "skinning", "cooking", "fishing", "firstaid", "pet", "riding" },
}

-- Which lists each value judges (0.47.7, the player: "@questlog is:" offered online, ready, equippable...): the pick
-- list and Tab offer only the values that judge a list typed (@kinds; "@group quests" = the party quests). A key's "*"
-- covers all its values; a key or value with nothing here is offered everywhere. Keep it in step with the tests above
-- (tests/smoke/search.lua walks every is: value).
local ITEMS = { "items", "gear", "consumables", "mats", "loot", "lootlog", "stored" }
local MADE = { "items", "gear", "consumables", "mats", "loot", "lootlog", "stored", "recipes", "missing" } -- (and what recipes make)
local OWN = { "items", "gear", "consumables", "mats" } -- (stacks of yours: bound or not)
local RECIPES = { "recipes", "professions" } -- (@profession is:skillup searches the recipes too)
-- (done / todo: turned in or not, by the game's record: Questie's quests and achievements; a quest in your log is never
-- done, so the quest log isn't offered them. Its own: complete (ready to turn in), grey, leftbehind, drop)
local QUESTS = { "questie", "achievements" }
local PEOPLE = { "guild", "friends", "who", "group" }
local NPC = { "npc" }
local MAIL = { "mail" }
local GROUP = { "group" }
local SPOTS = { "npc", "mailbox", "dungeon", "raid", "flight" }
F.APPLIES = {
	is = {
		done = QUESTS, todo = QUESTS, complete = { "quests" }, ready = { "spells" }, -- (ready on a quest = complete: offered once)
		usable = ITEMS, equippable = ITEMS, upgrade = ITEMS, quest = MADE, soulbound = OWN, boe = MADE,
		online = PEOPLE, offline = PEOPLE,
		craftable = RECIPES, skillup = RECIPES, orange = RECIPES, yellow = RECIPES, green = RECIPES,
		grey = { "recipes", "professions", "quests" }, leftbehind = { "quests" }, drop = { "quests" },
		passive = { "spells" }, unplaced = { "spells" }, capped = { "currency" },
		vendor = NPC, trainer = NPC, classtrainer = NPC, proftrainer = NPC, innkeeper = NPC, banker = NPC, repair = NPC,
		auctioneer = NPC, questgiver = NPC, stablemaster = NPC, battlemaster = NPC, pvpvendor = NPC, pvp = NPC,
		flightmaster = { "npc", "flight" }, flightpath = { "flight" }, learned = { "flight", "recipes", "professions" },
		unlearned = { "flight", "recipes", "professions", "missing" }, unknown = { "flight", "recipes", "professions", "missing" },
		learnable = { "recipes", "professions", "missing" },
		cod = MAIL, expiring = MAIL, unread = MAIL, returned = MAIL, auction = MAIL, money = MAIL, sent = MAIL, incoming = MAIL,
		dead = GROUP, tank = GROUP, healer = GROUP, dps = GROUP, far = GROUP, inrange = GROUP, unbuffed = GROUP,
		shareable = { "groupquests" }, together = { "groupquests" },
		raid = { "lockouts" }, dungeon = { "lockouts" },
	},
	missing = { ["*"] = GROUP },
	standing = { ["*"] = { "reputation" } },
	q = { ["*"] = MADE }, quality = { ["*"] = MADE }, stat = { ["*"] = MADE }, stats = { ["*"] = MADE },
	["in"] = { ["*"] = { "items", "gear", "consumables", "mats", "stored", "mail" } },
	faction = { ["*"] = { "npc", "flight" } },
	sort = { nearest = SPOTS, plan = RECIPES }, near = { ["*"] = SPOTS },
	fish = { ["*"] = { "maps" } },
	class = { ["*"] = { "talents" } },
	trainer = { ["*"] = NPC },
}

--- The lists the typed words name: every @kind (a set of provider ids), "@group" with "quests" being the party quests'
--- (as Search.lua's Scan.Parse reads it); nil when none is named.
function F.KindsTyped(text)
	local kinds
	local quests = false
	for w in tostring(text or ""):gmatch("%S+") do
		if w:sub(1, 1) == "@" then
			local p = ns.ResolveProvider and ns:ResolveProvider(w:sub(2))
			if p then kinds = kinds or {}; kinds[p.id] = true end
		elseif Lower(w) == "quests" or Lower(w) == "quest" then
			quests = true
		end
	end
	if kinds and kinds.group and quests then kinds.group, kinds.groupquests = nil, true end
	return kinds
end

--- The values Tab and the pick list offer after "key:", for what `before` (the words before it) names: those that judge
--- a list typed, all of them with no @kind typed. Nil when the key has no values to offer.
function F.ValuesFor(key, before)
	key = Lower(key or "")
	local values = F.VALUES[key]
	if not values then return nil end
	local kinds = F.KindsTyped(before)
	local applies = F.APPLIES[key]
	if not (kinds and applies) then return values end
	local out = {}
	for _, v in ipairs(values) do
		local where = applies[v] or applies["*"]
		local fits = where == nil
		for _, k in ipairs(where or {}) do if kinds[k] then fits = true break end end
		if fits then out[#out + 1] = v end
	end
	return out
end

-- the keys, in the order .filters lists them, with an example each
F.HELP = {
	{ "lvl:20-30", L["quest/NPC level, or the level an item needs (also lvl:<30, lvl:40-, lvl:20+)"] },
	{ "ilvl:60+", L["item level"] },
	{ "q:rare+", L["item quality: poor common uncommon rare epic legendary"] },
	{ "stat:stamina", L["an item stat, or what a consumable gives (elixirs, potions, food); with a number: stat:sta>=10 (str agi sta int spi armor ap sp crit hit mp5 fire...)"] },
	{ "slot:wrist", L["item slot, or what a recipe makes or enchants (bracers boots gloves cloak helm ring 2h...)"] },
	{ "type:mail", L["item type or subtype (cloth, sword, potion...)"] },
	{ "in:bank", L["where: bags/bank/mail/guild, a quest's or NPC's zone, a loot item's dungeon or boss"] },
	{ "on:name", L["@stored: on that character (or guild, warband)"] },
	{ "count:20+", L["how many you have"] },
	{ "class:mage", L["talents of that class (class:mine: yours); without it your own class's come first"] },
	{ "fish:mine", L["@map: zones your fishing skill is enough for (fish:150: what 150 is enough for; fish:130-205: needing that much)"] },
	{ "trainer:mage", L["@npc trainers by what they teach: a class, a profession (trainer:mining finds Miners too), class (your class), classes (any), profession, pet, riding, weapon"] },
	{ "faction:horde", L["@npc: friendly to the Horde / alliance / neutral (both) / friendly (to you)"] },
	{ "standing:honored+", L["reputation standing: hated hostile unfriendly neutral friendly honored revered exalted (also standing:<friendly, standing:4-6)"] },
	{ "near:500", L["@npc: within that many yards of you (near:<300, near:200-800)"] },
	{ "sort:nearest", L["Questie NPCs closest to you first, with how far (the other rows stay, after them)"] },
	{ "sort:plan", L["levelling a profession: your recipes that still give skill, by how many times your materials make each (bags and bank; with alts too), vendor-bought materials left out; the footer says the skill they'd give"] },
	{ "do:use", L["what Enter does, as Simple mode's action words: use cast summon equip wear target link where (do:cast frost nova)"] },
	{ "sells:linen_cloth", L["@npc: Questie vendors selling an item (its name, part of it, or its id; nothing for an unknown item)"] },
	{ "is:drop", L["quests to drop: grey (the quest log shows it grey) or leftbehind (in a zone you've outlevelled), not complete; >>> drop drops every quest listed, Terminal asks first"] },
	{ "is:todo", L["quests: done todo complete (ready = complete) grey leftbehind drop; achievements: done todo; items: usable equippable quest soulbound boe; recipes: craftable skillup (orange or yellow) orange yellow green grey"] },
	{ "is:ready", L["spells: ready (off cooldown) passive unplaced (not on any bar or key); currencies: capped; NPCs: vendor trainer classtrainer proftrainer flightmaster innkeeper banker repair..."] },
	{ "is:unknown", L["@recipe: the recipes of your professions you don't know yet, with how each is learned (is:learnable: those your skill allows now)"] },
	{ "is:unlearned", L["@flight: flight paths you haven't learned (learned: those you have; one no flight master's map has shown yet counts as unlearned)"] },
	{ "is:dead", L["@group: dead (or a ghost); tank healer dps (the role set); far (out of range) inrange; unbuffed; online offline; missing:fortitude (int, mark, spirit, shadow, blessing, or any buff's name)"] },
	{ "is:shareable", L["@group quests: your quests with who in your party is on each; is:shareable: someone lacks it and you can share it (Enter shares); is:together: someone is on it too"] },
	{ "is:raid", L["@lockout: your characters' raid lockouts (is:dungeon: dungeons'), with bosses down and when each resets; on:<character>"] },
	{ "is:expiring", L["@mail: mail running out within 3 days; cod unread returned (sent back to you) auction money (gold attached) sent (the last hour's, to others too) incoming (the auction house's news: sold, won, outbid, expired); on:<character>"] },
	{ "in:elwynn_forest", L["a value of several words: _ for the space (in:elwynn_forest, type:one-handed_swords)"] },
	{ "-is:soulbound", L["not that: - or ! before a filter or a word (-is:boe, !q:poor, -cloth)"] },
	{ "q:rare|epic", L["any of them: | between values, filters or words (slot:head|chest, is:boe|q:epic, sword|axe)"] },
	{ "q:rare&type:sword|q:epic&type:axe", L["& joins what must all hold inside a | list (each piece can have its own -)"] },
}
