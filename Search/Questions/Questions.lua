local ns = select(2, ...)

-- The plain-word questions and chains (Scan.ANSWERS), answered before any search: one registry of them (ns.Questions),
-- which one gets a line when several could (Q.Ranked), how a line is read as one (Scan.ReadQuestion, for the answer and
-- for Alt+`), their rows filtered and sorted as a search's (Scan.AnswerView). docs/QUESTIONS.md is the design.

local Scan = ns.UI._Scan
local function EasyOn() return ns.Easy ~= nil and ns.Easy.On() end
local EASY_NONE, PseudoEntries = Scan.EASY_NONE, Scan.PseudoEntries

local Q = {}
ns.Questions = Q

-- An entry (docs/QUESTIONS.md, section 2): `id`; `ask(text, converting)` gives what the line asks (and a second value
-- for line/answer/toAdvanced) or nil when it isn't its kind; then either `line(q, extra)`, the Advanced line whose
-- search is its answer and its Alt+` (a search question: `note(q, rows)` its footer, `empty(q)` its rows when nothing
-- is found), or `answer` giving rows and the footer's note (true third: the note is a chain's path), or nil to pass the
-- line on, with `toAdvanced` the same question as Advanced mode writes it (Alt+`, nil: the words as typed); `examples`,
-- the lines it must answer (tests/smoke/question_registry.lua); `over`, the entries it beats when both understand a
-- line as well (section 3); `custom`, why its answer is its own. One list for the answer and Alt+`.
--- A module of its own (ns[name]): its Question; Line (the Advanced line answering what it asked, nil: its own answer),
--- Footer and None (its rows when nothing is found) for a search question (section 4.1); Answer and ToAdvanced for an own answer, or where Line gives
--- none ("my mail": the mail with the auction house's news). `more`: the entry's other fields.
local function Asks(name, more)
	local function Of(f) return function(...) local m = ns[name] if m and m[f] then return m[f](...) end end end
	local a = {
		id = name,
		ask = Of("Question"), -- (both its values: the zones' level said, "where should i level at 30")
		line = Of("Line"), note = Of("Footer"), empty = Of("None"), lead = Of("Lead"),
		answer = Of("Answer"), toAdvanced = Of("ToAdvanced"),
	}
	for k, v in pairs(more or {}) do a[k] = v end
	return a
end
Q.Asks = Asks
local function Words(list) return #list > 0 and (table.concat(list, " ") .. " ") or "" end
-- (the list's order is only the last tie-break now: Q.Ranked; the notes say where a line was settled by it before)
Scan.ANSWERS = {
	-- "what should i do", "what now", "suggestions": what's worth doing now (Search/Questions/Suggest.lua)
	Asks("Suggest", { examples = { "what should i do", "what now", "suggestions" },
		custom = "rows made from the game's state: no list holds them" }),
	-- "untrack quests", "track completed quests", "track rfc quests only", "untrack red quests": QuestTrack.lua
	Asks("QuestTrack", { over = { "GroupQuests" }, examples = { "untrack quests", "track completed quests", "untrack red quests" },
		custom = "its rows are the plan (to track, to untrack) with the row that does it" }),
	-- "history", "my history", "recent searches": what you ran, newest first (Providers/History.lua)
	Asks("History", { examples = { "history", "recent searches" } }),
	-- "quests to turn in", "turn in quests": your quest log's ready ones (Search/Questions/Suggest.lua)
	Asks("TurnIn", { examples = { "quests to turn in", "which quests are ready" } }),
	-- "who gives the defias brotherhood", "where do i turn in ...": its giver, its turn-in NPC (Suggest.lua)
	Asks("QuestPeople", { custom = "a quest's giver or turn-in NPC: no relation in the search for it" }),
	-- "why can't i take the defias brotherhood", "can i take ...", "why isn't ... offered": what stops you, each reason a
	-- row (QuestAccess.lua: QuestieDB's prerequisites, exclusive quests, level cap, breadcrumbs...)
	Asks("QuestAccess", { examples = { "why cant i take wanted hogger", "can i take wanted hogger", "why isnt wanted hogger offered" },
		custom = "reasons, not rows a list holds: what stops you taking one quest" }),
	-- "quests near me", "turn ins near me": the quests whose giver (turn-in) is nearest (Suggest.lua)
	Asks("NearQuests", { examples = { "quests near me", "turn ins near me" },
		custom = "quests by their giver's distance, turn-ins as NPCs" }),
	-- "deadmines bosses": an instance's bosses from AtlasLoot, each leading to its loot (Suggest.lua)
	Asks("InstanceBosses", { custom = "boss rows whose Enter walks to the drops chain" }),
	-- "quests that start from an item": the quests an item starts (Suggest.lua)
	Asks("ItemQuests", { examples = { "quests that start from an item" } }),
	-- "what level is hogger", "duskwood level": the level Terminal has for it (Suggest.lua)
	Asks("LevelOf", { custom = "one row from three kinds: the level is the answer", examples = { "what level is vancleef" } }),
	-- "bigger bags": bags bigger than your smallest (Suggest.lua)
	Asks("BiggerBags", { examples = { "bigger bags", "bags with more slots" },
		custom = "bags from four lists, one row per item, bigger than your smallest" }),
	-- "achievements almost done", "quests almost done": the closest to done first (Suggest.lua)
	Asks("AlmostDone", { examples = { "achievements almost done", "quests almost done" } }),
	-- "where is my hearth": where your hearthstone takes you, and its cooldown (Suggest.lua)
	Asks("HearthBind", { examples = { "where is my hearth", "where am i bound" }, custom = "a game value, not a list" }),
	-- "how long to level", "xp per hour": this session's experience an hour (Suggest.lua)
	Asks("XpRate", { examples = { "xp per hour", "how long to level" }, custom = "this session's experience" }),
	-- "quests for stormwind rep", "how do i get exalted with timbermaw": Rewards.lua's ns.RepQuests
	Asks("RepQuests", { custom = "ranked by the reputation the faction asked for gives" }),
	-- "tailoring quests", "daily quests", "quests that need honored with stormwind": Rewards.lua's ns.QuestNeeds
	Asks("QuestNeeds", { examples = { "tailoring quests", "daily quests" }, custom = "a standing needed: no filter says it" }),
	Asks("QuestsHere", { over = { "Zones" }, custom = "your level or zone not known: says so", examples = { "quests here", "zone quests" } }),
	Asks("CanCraft", { examples = { "what can i craft", "what can i cook" } }),
	-- "argent dawn rewards", "what can i buy at honored", "my class sets", "pieces of battlegear of might": OneForAll's
	-- armory, the item sets also AtlasLoot's (Providers/Integrations/OneForAll/Armory.lua; was before the auctions' "what can i buy")
	Asks("Armory", { over = { "Auctions" }, custom = "a faction's rewards by standing, sets started first, a set's pieces" }),
	-- "favor recipes i don't know", "nearest boat", "zeppelin to orgrimmar", "zone exits": OneForAll's world (World.lua)
	Asks("OneForAllWorld", { custom = "a boat or zeppelin by where it goes, roads of your map, Merchant's Favor recipes" }),
	-- "what should i auction": your bag items worth more on the auction house, with Auctionator (AuctionValues.lua;
	-- was before the auctions' question: "what can i sell on the ah" isn't about what you've posted)
	Asks("AuctionatorQ", { over = { "Auctions" }, custom = "bags and bank together, your alts', everywhere: one row per item" }),
	Asks("AhUpgradesQ", { custom = "gain per gold over one row per item" }), -- ("ah upgrades": AuctionValues.lua)
	-- ("ah value of my mats": "@mats | sum ahvalue", was ahead of the chains' "... mats")
	Asks("AhValueQ", { over = { "Chains" }, steps = true, line = function(q) return q.line end }),
	-- ("what are my bags worth": "in:bags | sum value"; Suggest.lua)
	Asks("BagWorth", { examples = { "what are my bags worth", "bag value" }, steps = true, line = function(q) return q.line end }),
	-- "what is in my bank": this character's bank (@bank, Providers/Stored.lua)
	Asks("MyBankQ", { examples = { "what is in my bank", "my bank" } }),
	-- "where to learn bite 4", "cat abilities", "tameable cats", "rare pets in the barrens": a hunter's pets, OneForAll's
	-- (Providers/Integrations/OneForAll/Pets.lua; was before the collections' "my pets" and the chains' "... learn")
	Asks("HunterPets", { over = { "CollectionsQ", "Chains" }, custom = "OneForAll's beasts aren't @npc rows; one row per ability" }),
	-- "mounts", "my pets", "toys", "favorite mounts", "raptor mounts": the list, by name (Providers/Collections.lua)
	Asks("CollectionsQ", { over = { "HaveQ" }, custom = "words name collected ones by their starts", examples = { "mounts", "favorite mounts", "how many mounts do i have" } }),
	-- "buyback", "what did i sell": what you sold since you logged in (Providers/Buyback.lua)
	Asks("BuybackQ", { over = { "Auctions" }, examples = { "buyback", "what did i sell" } }),
	-- "what dropped", "what did we get", "what did i loot": LootLog.lua (was before chains: "what drops did we get" isn't
	-- "what drops <item>")
	Asks("LootLog", { over = { "Chains" }, examples = { "what dropped", "what did i loot", "what drops did we get" } }),
	-- "how do i get into mc", "how do i get attuned to onyxia": its steps (Attunements.lua; was before the chains, whose
	-- "how do i get" is where to get an item)
	{ id = "AttuneHow", over = { "Chains" }, custom = "a chain already: the same pipeline either way",
		ask = function(text) local A = ns.Attune and ns.Attune.Q return A and A.How(text) end,
		answer = function(q) return ns.Attune.Q.Answer(q) end,
		toAdvanced = function(q) return ns.Attune.Q.ToAdvanced(q) end },
	-- "spellid claw", "spell id 1082": SpellIds.lua (was before the chains and searches: the words are a spell's name)
	{ id = "SpellIds", over = { "Chains" }, examples = { "spellid claw", "spell id 1082" }, custom = "rows made on the spot from four sources",
		ask = function(text) local S = ns.SpellIds return S and S.Question(text) end,
		answer = function(q) return ns.SpellIds.Answer(q) end,
		toAdvanced = function(q) return ns.SpellIds.ToAdvanced(q) end },
	-- "itemid linen cloth", "questid 176", "npcid hogger": SpellIds.lua's ns.ObjectIds
	Asks("ObjectIds", { examples = { "itemid linen cloth", "questid 176" }, custom = "rows made on the spot: no list of ids" }),
	-- "healing talents", "shaman crit talents", "druid regen talents": talents by what they do (Search/Questions/Talents.lua;
	-- was before the chains and searches: "talents for crit" isn't a chain, "crit" and "healing" aren't an item's stats here)
	{ id = "Talents", over = { "Chains" }, custom = "descriptions read with families of like words, yours first",
		ask = function(text) local T = ns.TalentsQ return T and T.Question(text) end,
		answer = function(q) return ns.TalentsQ.Answer(q) end },
	-- a chain ("thorium belt > mats", "mats for thorium belt"): Chains.lua. (a ">" chain runs whichever way it came, in
	-- either mode)
	{ id = "Chains", examples = { "mats for thorium belt", "thorium belt > mats" }, custom = "a chain: one pipeline either way",
		ask = function(text) return ns.Pipes and ns.Pipes.Canonical(text) end,
		answer = function(chain)
			local rows, trail = ns.Pipes.Search(chain)
			return rows, trail, true
		end,
		toAdvanced = function(chain) return chain .. " " end },
	-- "what killed me", "who crit me": CombatLog.lua
	Asks("CombatLog", { examples = { "what killed me", "who crit me" },
		-- (CB.Line is a log line's text)
		line = function(k) return ns.CombatLog.QuestionLine(k) end, note = function(k, rows) return ns.CombatLog.QuestionFooter(k, rows) end,
		empty = function() return {} end }),
	-- "where should i level", "what dungeon should i do", "where should i fish": Zones.lua
	Asks("Zones", { examples = { "where should i level", "what dungeon should i do" },
		custom = "zones ranked by fit, quest counts and distance" }),
	-- "spells not on my bars": Spells.lua
	{ id = "UnplacedSpells", examples = { "spells not on my bars" },
		ask = function(text) return ns.Spells and ns.Spells.Question(text) end,
		line = function(q) return ns.Spells.UnplacedLine(q) end, note = function(q, rows) return ns.Spells.UnplacedNote(q, rows) end,
		empty = function() return {} end },
	-- "blacksmithing recipes i'm missing", "recipes i can learn now": MissingRecipes.lua (was before the group's: "who is
	-- missing recipes" is about recipes)
	Asks("MissingRecipes", { over = { "Group", "WhatsTraining", "ClassSpells" }, examples = { "recipes i can learn now", "recipes i dont know" },
		answer = function() return nil end }), -- (a search question: MR.Answer is its footer's)
	-- "what can i train in tailoring", "tailoring training", "profession training": the recipes a trainer teaches you
	-- don't know (Search/Questions/ProfTraining.lua; was before What's Training's, whose "what can i train" is your
	-- class's spells)
	Asks("ProfTraining", { over = { "WhatsTraining" }, custom = "can-learn first, then the skill needed, with the next rank's text" }),
	-- "what can i train", "what do i learn next level", "how much is training", "when do i learn fireball": What's
	-- Training's spells (WhereToLearn.lua; after the recipes': "recipes i can learn" is theirs)
	{ id = "WhatsTraining", over = { "ClassSpells" }, custom = "what training costs: the list with its total",
		ask = function(text) local W = ns.WhatsTraining and ns.WhatsTraining.Q return W and W.Question(text) end,
		line = function(q) return ns.WhatsTraining.Q.Line(q) end, note = function(q, rows) return ns.WhatsTraining.Q.Footer(q, rows) end,
		empty = function(q) return ns.WhatsTraining.Q.None(q) end,
		-- ("how much is training": the list with what it costs in all, its own; a "| sum cost" line is one row)
		answer = function(q) return ns.WhatsTraining.Q.Answer(q) end,
		toAdvanced = function(q) return ns.WhatsTraining.Q.ToAdvanced(q) end },
	-- "druid spells", "upcoming spells", "when do i learn travel form": every class's spells (Search/Questions/ClassSpells.lua;
	-- after What's Training's, which answers for your class when it's there)
	{ id = "ClassSpells", custom = "the next level something is learned at, a rank at a level, a name your class's first",
		ask = function(text) local C = ns.ClassSpells and ns.ClassSpells.Q return C and C.Question(text) end,
		line = function(q) return ns.ClassSpells.Q.Line(q) end, note = function(q) return ns.ClassSpells.Q.Footer(q) end,
		empty = function(q) return ns.ClassSpells.Q.None(q) end,
		-- (the next level something is learned at, a rank at a level, a name your class's first: its own answer)
		answer = function(q) return ns.ClassSpells.Q.Answer(q) end,
		toAdvanced = function(q) return ns.ClassSpells.Q.ToAdvanced(q) end },
	-- "blacksmithing plan", "level blacksmithing", "leveling plan": Plan.lua (sort:plan's question)
	Asks("Plan", { examples = { "leveling plan" }, note = function() return nil end }), -- (its footer is sort:plan's; PL.Note is the plan's own)
	-- "quests to drop", "grey quests": QuestDrop.lua
	Asks("QuestDrop", { over = { "Attunements" }, examples = { "quests to drop", "grey quests" } }),
	-- "party quests", "quests to share", "same quests as my group": GroupQuests.lua (was before the group's: "party
	-- members missing quests" is about quests)
	Asks("GroupQuests", { over = { "Group", "Attunements" }, examples = { "party quests", "quests to share" } }),
	-- "my lockouts", "raid lockouts", "am i saved", "raid id": Lockouts.lua
	Asks("Lockouts", { examples = { "my lockouts", "am i saved", "lockouts by raid" } }),
	-- WoW Forever's Legacy and PvP ranks (Providers/Legacy.lua): "legacy points", "which legacy points am i missing",
	-- "what gives legacy points for mage" (@legacy is:todo cat:mage), "legacy rewards", "legacy perks", "my pvp rank",
	-- "what does pvp rank 11 unlock" (@pvprank lvl:11)
	Asks("LegacyPoints", { examples = { "legacy points", "which legacy points am i missing", "what gives legacy points for mage" } }),
	Asks("LegacyRewards", { examples = { "legacy rewards", "what can i claim with legacy points" } }),
	Asks("LegacyPerks", { examples = { "legacy perks", "my perks" } }),
	Asks("PvpRank", { examples = { "my pvp rank", "rank points", "what does pvp rank 11 unlock" } }),
	-- "what layer am i on", "my layer": the layer the creatures around you are on (Providers/Layer.lua)
	Asks("Layer", { examples = { "what layer am i on", "my layer" } }),
	-- "where are my friends", "friends location", "where is bob" (a friend sharing it): friends' places by Terminal: Share
	-- (Terminal_Share/Share.lua's ns.SharePlaces; .share settings location)
	Asks("SharePlaces", { examples = { "where are my friends", "friends location" } }),
	-- "library books", "books i still need", "nearest library book": the Library Books, OneForAll's else QuestieDB's
	-- (Providers/Integrations/OneForAll/Books.lua)
	Asks("LibraryBooks", { custom = "the reward tiers, and the nearest spot of each book" }),
	-- "enchants for my weapon", "enchants for bracers", "agility enchants", "enchants i can make": OneForAll's enchants
	-- (@enchant, Providers/Integrations/OneForAll/Enchants.lua)
	Asks("Enchants", { examples = { "enchants for my weapon", "enchants for bracers", "agility enchants", "enchants i can make" } }),
	-- "what can my pet eat", "who sells pet food", "nearest pet food vendor": a hunter's pet's food (@item is:petfood,
	-- @npc sells:petfood; Search/Questions/PetFood.lua)
	Asks("PetFood", { examples = { "what can my pet eat", "pet food", "who sells pet food", "nearest pet food vendor" } }),
	-- "summoned bosses in blackrock spire", "which bosses are summoned": OneForAll's (Providers/Integrations/OneForAll/Bosses.lua)
	Asks("OneForAllBosses", { examples = { "summoned bosses in blackrock spire", "which bosses are summoned" },
		custom = "OneForAll's bosses aren't a list: one row per boss, its level and type" }),
	-- "where is my body", "my corpse", "where did i die": Corpse.lua (and the nearest spirit healers)
	Asks("Corpse", { examples = { "where is my body", "my corpse" }, custom = "your corpse, then the nearest spirit healers" }),
	-- "durability", "repair cost", "what needs repair", "broken gear": Durability.lua
	Asks("Durability", { examples = { "durability", "repair cost" } }),
	-- "my auctions", "what am i selling", "auctions sold": Auctions.lua (never with a mail word: "auction mail" is the mail's)
	Asks("Auctions", { examples = { "my auctions", "auctions sold" } }),
	-- "my mail", "mail running out", "cod mail": Mail.lua
	Asks("Mail", { over = { "HaveQ" }, examples = { "my mail", "cod mail", "do i have mail" },
		custom = "your mail with the auction house's news and every mailbox" }),
	-- "how many linen do i have", "do i have linen cloth": how many in all and where (Suggest.lua. Was after the
	-- collections' and the mail's: "how many mounts do i have", "do i have mail" are theirs)
	Asks("HaveQ", { examples = { "how many linen do i have", "do i have linen cloth" },
		custom = "one row per item counting your bags, bank and alts together" }),
	-- "who is dead", "who needs fortitude", "who is out of range", "group healers": Group.lua
	Asks("Group", { examples = { "who is dead", "who is offline" } }),
	-- "quest upgrades", "quests with upgrades": the quests near your level whose reward is an upgrade (Rewards.lua)
	{ id = "QuestUpgrades", examples = { "quest upgrades", "quests with upgrades" },
		custom = "the reward that is an upgrade, its giver's distance or dungeon, near your level",
		ask = function(text)
			local R = ns.QuestRewards
			return R and R.UpgradeQuestion and R.UpgradeQuestion(text) or nil
		end,
		answer = function() return ns.QuestRewards.UpgradeAnswer() end },
	-- "upgrades i can buy", "vendor upgrades": the friendly vendors selling an upgrade for you (Rewards.lua)
	{ id = "VendorUpgrades", examples = { "upgrades i can buy", "vendor upgrades" },
		custom = "what each vendor sells that is an upgrade, and by how much",
		ask = function(text)
			local R = ns.QuestRewards
			return R and R.BuyQuestion and R.BuyQuestion(text) or nil
		end,
		answer = function() return ns.QuestRewards.BuyAnswer() end,
		toAdvanced = function() return ns.QuestRewards.BuyToAdvanced() end },
	-- "quests that reward bags", "bag quests" (Rewards.lua; was before the one by an item's name: "bags" names no item)
	{ id = "BagQuests", over = { "RewardQuests" }, examples = { "quests that reward bags", "bag quests" },
		ask = function(text) return ns.QuestRewards and ns.QuestRewards.BagQuestion(text) end,
		line = function(q) return ns.QuestRewards.BagLine(q) end, note = function(q) return ns.QuestRewards.BagFooter(q) end,
		empty = function(q) return ns.QuestRewards.BagNone(q) end },
	-- "outlaw sabre quest", "quest for outlaw sabre": the quests rewarding it (Rewards.lua; only when the words name a
	-- quest reward, and no quest is called that)
	{ id = "RewardQuests", custom = "the quests in the order of the items they reward, with the item's chain",
		ask = function(text) return ns.QuestRewards and ns.QuestRewards.Question(text) end,
		answer = function(q) return ns.QuestRewards.Answer(q) end,
		toAdvanced = function(q) return ns.QuestRewards.ToAdvanced(q) end },
	-- "my attunements", "raid attunements", "my keys", "class quests": Attune's list (Attunements.lua; was late: "dungeon
	-- quests to share", "grey dungeon quests" are the group's and the quest log's)
	{ id = "Attunements", custom = "words name attunements, else their steps' text",
		ask = function(text) local A = ns.Attune and ns.Attune.Q return A and A.List(text) end,
		line = function(q) return ns.Attune.Q.Line(q) end, note = function(q, rows) return ns.Attune.Q.Footer(q, rows) end,
		empty = function(q) return ns.Attune.Q.None(q) end,
		-- (words name attunements, else their steps' text: its own answer, as said; a search's words take both)
		answer = function(q) return ns.Attune.Q.Answer(q) end,
		toAdvanced = function(q) return ns.Attune.Q.ToAdvanced(q) end },
	-- "holidays", "what's on this week", "today", "next darkmoon faire", "my invites": Calendar.lua (its own today, this
	-- week: 0.66.8 review; was last: its words name what's on the calendar, or it's a search)
	Asks("Calendar", { ownDates = true, examples = { "holidays", "whats on this week" } }),
	-- "quests per zone", "items by quality": searched as "@questie | group by zone" (Suggest.lua; UI/Results.lua's
	-- TakeAggregate). Last: a line another question takes as well is that one's ("lockouts by raid": @lockout's)
	Asks("PerField", { perField = true, last = true, steps = true, examples = { "quests per zone", "items by quality" },
		line = function(q) return q.line end }),
}

----------------------------------------------------------------------
-- Which question gets a line (docs/QUESTIONS.md, section 3): every entry is asked; of those that take it, one marked
-- `last` loses to any other; one whose `over` names the other wins (a decision made on purpose, tested); else the one
-- that understands more of the line's words; else the earlier in the list.
----------------------------------------------------------------------

Q.PROBE = "zzqx" -- (a word nothing knows: an entry that no longer takes the line with it in a word's place understood it)

--- How many of the line's words entry `a` understands: those whose place taken by Q.PROBE makes it give the line up.
function Q.Understood(a, text)
	local words = {}
	for w in tostring(text):gmatch("%S+") do words[#words + 1] = w end
	local n = 0
	for i = 1, #words do
		local was = words[i]
		words[i] = Q.PROBE
		local ok, got = pcall(a.ask, table.concat(words, " "))
		words[i] = was
		if not (ok and got) then n = n + 1 end
	end
	return n
end

local function Beats(a, b)
	for _, id in ipairs(a.over or {}) do if id == b.id then return true end end
	return false
end

-- (the ranking of a line, kept for one search only (UI:Search's Q.Begin/Q.Finish): the answer asks of the same line
-- several times, as typed and as its variants; outside a search every call asks again, what it reads may have changed)
local memo, memoN, stamp = {}, 0, nil
function Q.Begin() stamp = {}; memo = {}; Q.lineDepth = 0 end
function Q.Finish() stamp = nil; memo = {} end

--- The entries that take `text`, best first: { { a = entry, q = what it asks, extra = its second value, n = the words
--- it understands (when another took it too), i = its place in the list } ... } (empty: none).
function Q.Ranked(text)
	if #Scan.ANSWERS ~= memoN then memo, memoN = {}, #Scan.ANSWERS end
	local got = stamp and memo[text]
	if got then return got end
	local out = {}
	for i, a in ipairs(Scan.ANSWERS) do
		local q, extra = a.ask(text)
		if q then out[#out + 1] = { a = a, q = q, extra = extra, i = i } end
	end
	if #out > 1 then
		for _, c in ipairs(out) do c.n = Q.Understood(c.a, text) end
		local function Before(x, y)
			if (x.a.last and true or false) ~= (y.a.last and true or false) then return not x.a.last end
			if Beats(x.a, y.a) then return true end
			if Beats(y.a, x.a) then return false end
			if x.n ~= y.n then return x.n > y.n end
			return x.i < y.i
		end
		-- (an insertion sort: a few entries, and `over` with the counts needn't be a strict order, which table.sort
		-- would refuse)
		for k = 2, #out do
			local c, j = out[k], k - 1
			while j >= 1 and Before(c, out[j]) do out[j + 1] = out[j]; j = j - 1 end
			out[j + 1] = c
		end
	end
	if stamp then memo[text] = out end
	return out
end

--- (tests, and who wants a question's rows without the window) What the search gives `text`, and the footer's note.
function Q.Answer(text)
	local UIs = ns.UI
	local rows = UIs:Search(text)
	return rows, UIs.answerNote
end

--- An entry by its id, or nil.
function Q.ById(id)
	for _, a in ipairs(Scan.ANSWERS) do if a.id == id then return a end end
	return nil
end

--- A plain-word question or chain as Advanced mode writes it (Alt+`: Easy.ToAdvanced), or nil when the line is none.
--- (0.55.7, the search's rewrite: a question whose answer no search gives, ranked or gathered its own way, "where should i
--- level" by how well each zone fits, "my mail" with the auction house's news, stays as it was said: its toAdvanced says
--- nil. Questions are answered in Advanced mode too, so what's written finds what was shown; "@map lvl:23" didn't.)
function ns.QuestionToAdvanced(text)
	-- ("items by zone q:rare": its filters before its step, as the search runs it: Q.StepLine)
	local stepped = Q.StepLine(text)
	if stepped then return stepped end
	return ns.QuestionToAdvancedOf(text)
end
--- The question's line with the filters and sorts typed after it (`tail`, words): before its first step ("| group by
--- zone": the search's, the steps sum up what it found) or its ">>"/">>>" part, where the search reads them. In the
--- order Alt+` prints a search (its filters, then its sort), so Alt+` of it is the same line: the filters typed go
--- before the line's sort, a sort typed takes the line's place ("my auctions sort:value": by value, not the list's
--- order). A line's words, a quoted value one word with its spaces ('zone:"the barrens"'): as the search reads them
--- (Lex).
local function RawWords(text)
	local out, i, n = {}, 1, #text
	while i <= n do
		local s = text:find("%S", i)
		if not s then break end
		local j = s
		while j <= n and not text:sub(j, j):find("%s") do
			if text:sub(j, j) == '"' then j = (text:find('"', j + 1, true) or n) + 1 else j = j + 1 end
		end
		out[#out + 1] = text:sub(s, j - 1)
		i = j
	end
	return out
end
Q.RawWords = RawWords

local function WithTail(line, tail)
	local body = (tostring(line):gsub("%s+$", ""))
	if not tail or #tail == 0 then return body .. " " end
	local step, send = body:find("%s|%s"), body:find("%s>>")
	local at = (step and send) and math.min(step, send) or step or send
	local head, rest = body, ""
	if at then head, rest = body:sub(1, at - 1), " " .. body:sub(at + 1) end
	local F = ns.Filters
	local filters, sort = {}, nil
	for _, w in ipairs(tail) do
		if F and F.SortOf and F.SortOf(w) then sort = w else filters[#filters + 1] = w end
	end
	local words, lineSort = {}, nil
	for _, w in ipairs(RawWords(head)) do
		if not lineSort and F and F.SortOf and F.SortOf(w) then lineSort = w else words[#words + 1] = w end
	end
	for _, w in ipairs(filters) do words[#words + 1] = w end
	if sort or lineSort then words[#words + 1] = sort or lineSort end
	return table.concat(words, " ") .. rest .. " "
end
Scan.WithTail = WithTail

function ns.QuestionToAdvancedOf(text)
	-- (the line read as Scan.Answer reads it, Scan.ReadQuestion: the question's form, then what was typed after it)
	local line, tail = Scan.ReadQuestion(text, function(t)
		local c = Q.Ranked(t)[1]
		if not c then return nil end
		local out = c.a.line and c.a.line(c.q, c.extra) or nil
		if out == nil and c.a.toAdvanced then out = c.a.toAdvanced(c.q, c.extra) end
		if out == nil then out = (t:gsub("^%s+", ""):gsub("%s+$", "")) .. " " end
		return out, c.a
	end)
	if line and tail then return WithTail(line, tail) end
	return line
end

--- A line whose question is answered by an Advanced line with steps ("quests per zone": "@questie | group by zone",
--- "what are my bags worth": "in:bags | sum value"): that line, the filters and sorts typed after the question before
--- its first step ("items by zone q:rare" -> "@item q:rare | group by zone"), with its search and steps (as A.Split
--- reads it); nil when the line's best question isn't such a one ("lockouts by raid": @lockout's own). Read at the
--- steps stage (the "per" recognizer below), so only the line and its Advanced words after it: never the line read
--- again from inside its reading.
function Q.StepLine(text)
	if type(text) ~= "string" then return nil end
	text = ns.Easy and ns.Easy.English and ns.Easy.English(text) or text
	-- (steps typed after the question, "items by quality | first 2": after its own, as Alt+` writes them; a question is
	-- never read with a "|" in it, so they were dropped and the line searched as plain words)
	local typed
	do
		local head, more = text:match("^(.-)%s+|%s+(.-)%s*$")
		if head and head ~= "" and more ~= "" then text, typed = head, more end
	end
	-- (every line is read so, and outside a search: the whole ranking only when a question whose line has steps
	-- (`steps`) takes it, else nothing to rewrite)
	local function Best(t)
		local any = false
		for _, a in ipairs(Scan.ANSWERS) do
			if a.steps and a.ask(t) then any = true break end
		end
		if not any then return nil, nil end
		local c = Q.Ranked(t)[1]
		return c and c.a.line and c.a.line(c.q, c.extra) or nil, c
	end
	local line, c = Best(text)
	local tail
	if not c then
		local rest
		rest, tail = Scan.SplitTail(text)
		if rest then line = Best(rest) end
	end
	if not (line and line:find("%s|%s")) then return nil end
	local full = WithTail(line, tail)
	if typed then full = full:gsub("%s+$", "") .. " | " .. typed .. " " end
	-- (its search and steps as A.Split reads them, split here: A.Split reads the line, which this is inside the reading of)
	local parts = {}
	for part in (full:gsub("%s+$", "") .. " | "):gmatch("(.-)%s+|%s+") do parts[#parts + 1] = (part:gsub("^%s+", "")) end
	local query, steps = parts[1], {}
	for k = 2, #parts do steps[#steps + 1] = parts[k] end
	if not query or #steps == 0 then return nil end
	return full, query, steps
end

-- the step line, "quests per zone": the whole line (before a send) said again as its Advanced line, which the search runs
-- ("@questie | group by zone"; UI/Results.lua's TakeAggregate). Its words stay the line's own for who reads them as typed
-- (Alt+` writes the line, not its search: ns.QueryToAdvanced reads the step line itself). In either mode.
ns.Phrase.Register({ id = "per", stage = "steps", priority = 40, classes = { op = true, syntax = true, word = true, quoted = true },
	modes = { simple = true, advanced = true },
	at = function(r, i)
		if i ~= 1 then return nil end
		-- (its search and steps as Q.StepLine made them: the line isn't read again from inside this reading; review)
		local line, query, steps = Q.StepLine(r.base)
		if not line then return nil end
		return { from = 1, to = r.sendEnd - 1, keep = true, kind = "per", line = line, query = query, list = steps }
	end })

--- A chain or a question in plain words: its own answer (Scan.ANSWERS), not a search. The rows, or nil.
--- (0.55.7, the search's rewrite: an answer is filtered and sorted as a search is: Advanced filters and sorts typed after
--- the question, "my auctions q:rare+ sort:value", and Simple mode's bar; Scan.AnswerView. Its group was already: "| group
--- by" sums up any rows.)
--- A search question's answer is the search of its line (section 4.1): its rows as the search gives them, true second.
function Scan.Answer(self, text)
	local got, tail = Scan.ReadQuestion(text, function(t) return Scan.Ask(self, t) end)
	if not got then return nil end
	if got.searchLine then return Scan.SearchLine(self, WithTail(got.searchLine, tail), got), true end
	return Scan.AnswerView(self, got, tail)
end

--- A search question answered: its line searched (its steps, "| group by zone", are the line's reading's: TakeAggregate
--- searched the part before them already, so here only that part, for who calls UI:Search itself), then its footer
--- (`note`) and, when nothing is found, its own row saying why (`empty`).
-- (never in a pcall: the search may yield, spread over frames; Q.Begin puts the depth back after an error)
Q.lineDepth = 0
function Scan.SearchLine(self, line, got)
	local at = line:find("%s|%s")
	local query = at and line:sub(1, at - 1) or line
	if Q.lineDepth > 2 then return PseudoEntries({ EASY_NONE }) end -- (a line that is a question again: never round)
	Q.lineDepth = Q.lineDepth + 1
	local rows = self:SearchText(query)
	Q.lineDepth = Q.lineDepth - 1
	-- (what the bar shows as typed is the prompt's: the line's own filters weren't typed, and taking one off the bar would
	-- cut the prompt where the line had it; a question's words typed after it are its own, as before)
	self.typedPicks = nil
	local a = got.entry
	local real = {}
	local Real = ns.Bar and ns.Bar.Real
	for _, e in ipairs(rows) do if not Real or Real(e) then real[#real + 1] = e end end
	if #real == 0 and a.empty then rows = a.empty(got.q) or rows end
	local note = a.note and a.note(got.q, real)
	if note ~= nil then self.answerNote = note end
	-- (a row on top doing it to them all, "Drop all 5": made from the rows found; not a result, the same either way)
	local lead = #real > 0 and a.lead and a.lead(got.q, real)
	if lead and #lead > 0 then
		local out = {}
		for _, e in ipairs(lead) do out[#out + 1] = e end
		for _, e in ipairs(rows) do out[#out + 1] = e end
		rows = out
	end
	return rows
end

--- How a line is read as a question, the same for its answer (Scan.Answer) and its Advanced form (Alt+`,
--- ns.QuestionToAdvancedOf): ask(t) -> what the question gives (nil: none takes t), the question (Scan.ANSWERS' entry).
--- Tried in this order: a chain, with the sorts typed after it ("deadmines > steps sort:line": only sorts, a filter at
--- the end is the last step's own); dates said after a question ("loot today", "my auctions sold this week": its
--- filters, before the question reads them as its own little words; not the calendar's, whose today is its own: 0.66.8
--- review); the line; the line with the Advanced filters and sorts typed after it ("my auctions q:rare+ sort:value");
--- dates and numbers said in words after it ("what killed me today": "what killed me since:today"). Gives what ask gave
--- and the words typed after the question (nil: none), or nil. The line with what its plain stage read said as filters
--- ("loot today" -> "loot since:today"), read off the line's reading (Phrase.lua, kept for the frame: the search reads
--- the same one next), not the line split again; dates: only the dates' recognizer asked (as E.PlainDates); the line
--- itself when nothing was read.
local DATES = { dates = true }
local function PlainSaid(text, dates)
	local r = ns.Phrase.ReadLine(text, { simple = true, parse = true, only = dates and DATES or nil })
	local out, any = {}, false
	for k, t in ipairs(r.toks) do
		local c = r.taken[k]
		if c and c.kind == "plain" then
			if c.from == k then
				for _, w in ipairs(c.words) do out[#out + 1] = w end
				any = true
			end
		else
			out[#out + 1] = t.text
		end
	end
	return any and table.concat(out, " ") or text
end

function Scan.ReadQuestion(text, ask)
	-- (a quest's or an NPC's whole name asked like a question, "What Is Going On?", "Who Is Stealing Our Cats?": the
	-- name, searched; three words or more, or a "?", so "mounts" or "my mail" are still asked)
	local I = ns.Integrations
	if EasyOn() and I and I.IsName and (text:find("?", 1, true) or select(2, text:gsub("%S+", "")) >= 3) and I.IsName(text) then
		return nil
	end
	if text:find(">", 1, true) then
		local rest, tail = Scan.SplitTail(text, true)
		local got = rest and ask(rest)
		if got then return got, tail end
	end
	if EasyOn() then
		local dated = PlainSaid(text, true)
		if dated ~= text then
			local rest, dtail = Scan.SplitTail(dated)
			local got, a
			if rest then got, a = ask(rest) end
			-- (a question that takes "today" as one of its little words, "loot today": its rows, the dates on them)
			local whole = false
			if not got and dtail then got, a = ask(text); whole = true end
			if got and not a.ownDates then return got, dtail end
			-- (the calendar's, asked the whole line: as below, not asked again; review)
			if got and whole then return got, nil end
		end
	end
	local got = ask(text)
	if got then return got, nil end
	local rest, tail = Scan.SplitTail(text)
	if rest then got = ask(rest) end
	if got then return got, tail end
	if EasyOn() then
		local again = PlainSaid(text)
		if again ~= text then
			rest, tail = Scan.SplitTail(again)
			if rest then got = ask(rest) end
			if got then return got, tail end
		end
	end
	return nil
end

--- The Advanced filters and sorts at the end of a line ("my auctions q:rare+ sort:value"): the line before them, and
--- them (nil: none, or a chain, whose last step takes its own).
function Scan.SplitTail(text, sortsOnly)
	local F = ns.Filters
	if not (F and F.Parse) or (text:find(">", 1, true) and not sortsOnly) then return nil end
	local words = RawWords(text)
	local tail = {}
	while #words > 1 do
		local w = words[#words]
		local so = F.SortOf and F.SortOf(w)
		if w:find(":", 1, true) and w:sub(1, 1) ~= "@" and (so or (not sortsOnly and F.Parse(w))) then
			table.insert(tail, 1, w)
			words[#words] = nil
		else
			break
		end
	end
	if #tail == 0 then return nil end
	return table.concat(words, " "), tail
end

--- A question's rows filtered and sorted: by the Advanced words after it (tail) and Simple mode's bar. Lines that aren't
--- results (a heading, a note) stay; the results between two of them are sorted among themselves (B.Order), or all of
--- them by distance (nearest first). Nothing left: a line saying so, under the answer's own lines on top.
function Scan.AnswerView(self, rows, tail)
	local F, B = ns.Filters, ns.Bar
	if not (F and B) then return rows end
	local filters, sort = {}, nil
	for _, w in ipairs(tail or {}) do
		local so = F.SortOf and F.SortOf(w)
		if so then sort = so else filters[#filters + 1] = F.Parse(w) end
	end
	local bar = EasyOn() and B.Active()
	if bar then
		for _, w in ipairs(bar.filters) do filters[#filters + 1] = F.Parse(w) end
		sort = B.SortWord(bar) or sort
	end
	if #filters == 0 and not sort then return rows end
	local Real = B.Real
	local out, kept, any, dropped = {}, {}, false, false
	-- (an answer's rows are what was asked for: its quartermaster rewards too, for standing:, which reads
	-- F.rewardsAsked; set by Scan.Parse, which a question never runs, so it was the last search's)
	local askedWas = F.rewardsAsked
	F.rewardsAsked = true
	for _, e in ipairs(rows) do
		if not Real(e) then out[#out + 1] = e
		elseif #filters == 0 or F.Pass(e, filters) then out[#out + 1] = e; kept[#kept + 1] = e; any = true
		else dropped = true end
	end
	F.rewardsAsked = askedWas
	-- (the row on top that does it to them all, "Untrack 4 quests", "Drop all 5": made again for the ones left)
	if dropped and any then
		local again = {}
		for _, e in ipairs(out) do
			local replan = type(e) == "table" and rawget(e, "replan")
			if replan then
				local row = replan(kept)
				if row then row._score = e._score; again[#again + 1] = row end
			else
				again[#again + 1] = e
			end
		end
		out = again
	end
	if not any then
		local head = {}
		for _, e in ipairs(out) do if type(e) == "table" and (e.lead or e.raw) then head[#head + 1] = e end end
		head[#head + 1] = PseudoEntries({ EASY_NONE })[1]
		return head
	end
	local sortBase, sortRev = ns.Filters.SortParts(sort)
	if sortBase == "distance" then
		local I = ns.Integrations
		local here = I and I.Here and I.Here()
		if not here then self.noPosition = true return out end
		local real, other = {}, {}
		for _, e in ipairs(out) do if Real(e) then real[#real + 1] = e else other[#other + 1] = e end end
		real = Scan.NearestViews(real, here, true, Scan.Budget(self), sortRev)
		-- (in their order: the views say it in their scores, which an answer isn't sorted by; 0.65.x review)
		for i, e in ipairs(real) do e._ord = i end
		table.sort(real, function(a, b)
			local sa, sb = tonumber(a._score) or 0, tonumber(b._score) or 0
			if sa ~= sb then return sa > sb end
			return a._ord < b._ord
		end)
		for _, e in ipairs(real) do other[#other + 1] = e end
		return other
	elseif sort then
		return B.Order(out, sort)
	end
	return out
end

--- The question's own answer (Scan.ANSWERS), as it gives it: the rows, or nil.
function Scan.Ask(self, text)
	-- (the entries that take the line, best first: the first whose answer gives rows answers; docs/QUESTIONS.md, 3)
	for _, c in ipairs(Q.Ranked(text)) do
		local a = c.a
		-- (a search question: its line, searched by Scan.Answer with what was typed after the question; section 4.1)
		if a.line then
			local line = a.line(c.q, c.extra)
			if line then return { searchLine = line, entry = a, q = c.q }, a end
		end
		local rows, note, isTrail
		if a.answer then rows, note, isTrail = a.answer(c.q, c.extra) end
		if rows then
			self.noPosition, self.action, self.place = nil, nil, nil
			if self.categoryAuto then self.category, self.categoryAuto = nil, nil end
			self.posTokens = {}
			if isTrail then self.pipeTrail = note else self.answerNote = note end
			-- (an answer's rows aren't scored: letters a search marked on them before ("@mail bob", then "my mail") are
			-- forgotten, worked out again when drawn: none, with nothing typed to mark)
			for i = 1, #rows do
				local e = rows[i]
				if type(e) == "table" and rawget(e, "_pos") ~= nil then e._pos = nil end
			end
			return rows, a
		end
	end
end
