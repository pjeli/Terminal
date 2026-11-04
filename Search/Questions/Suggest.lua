local ns = select(2, ...)
local L = ns.L

-- "What should I do?" (0.61.0, the player's ask: "if someone types a 'what should i do now' type search, or maybe by
-- default / empty, they can be presented with some suggestion results that detail leveling a certain profession, or a
-- certain dungeon for upgrades, or nearest repair if dura low, or nearest class / weapon trainer if missing something";
-- then "nearby vendor if player has junk to sell", "quest if their zone has a lot of quests available their level",
-- "class quest if it is time").
--
-- What's worth doing now, from what Terminal already knows of your character, the most pressing first. Each row says
-- why, and Enter searches for it (plain words, so Simple and Advanced mode alike; its tooltip writes the search in
-- Advanced syntax). Asked for ("what should i do", "what now", "suggestions"), every list is read. "try: what should i
-- do" is one of the empty prompt's examples, weighted up when something is (SG.Pressing: only lists already read, so
-- opening the terminal builds none; the player: "I actually prefer an empty bar on key press").
--
--   Repair your gear        your lowest piece under SG.REPAIR_PCT %        nearest repair
--   Sell your junk          grey items (or bags nearly full)               nearest vendor
--   Train new spells        class spells you can learn now                 nearest <class> trainer / what can i train
--   Learn a weapon skill    weapon skills a weapon master teaches you now  nearest <weapon> trainer
--   <Profession>: next rank skill at the cap, the next rank learnable      nearest <profession> trainer
--   Class quest             one of Attune's class quests for your level    steps for <its name> (Enter on a step: Attune)
--   Turn in quests          quests in your log ready to turn in            quests to turn in
--   Quests here / Move on   quests at your level in your zone (Questie)    quests here / where should i quest
--   Run a dungeon           the dungeon that fits your level best          <dungeon> upgrades
--   Post on the AH          bag items worth more there (Auctionator)       what should i auction
--   Level <profession>      a crafting profession under its cap            <profession> plan

local SG = {}
ns.Suggest = SG

local Lower, Safe, Str, Num = ns.Lower, ns.Safe, ns.Str, ns.Num
local SEP = ns.DETAIL_SEP

SG.MAX = 8            -- rows when asked
SG.CACHE_FOR = 10     -- seconds the rows are kept (the empty prompt opens often)
SG.REPAIR_PCT = 30    -- a worn piece this low (or broken): repair
SG.JUNK_MIN = 3       -- grey items to be worth a trip (fewer, when bags are nearly full)
SG.BAGS_LOW = 4       -- free bag slots that count as nearly full
SG.ZONE_QUESTS = 5    -- quests at your level in your zone to stay; under 2, move on
SG.RANK_LEVEL = { [75] = 10, [150] = 20, [225] = 35 } -- (a rank's cap: the level its next rank asks)
SG.GATHERING = { herbalism = true, skinning = true, fishing = true } -- (no recipes: no plan to level them by)

local function Has(addon)
	local I = ns.Integrations
	return not (I and I.AddonMissing and I.AddonMissing(addon))
end

--- A list's rows: built when asked (`build`); else only if it's been read and is up to date: the empty prompt builds no
--- list (tests/smoke/opencost.lua: the player's CPU spike on opening, 0.53.1) and says nothing from one out of date (a
--- spell learned since). `stale`: the last one read will do (the caller checks what it takes from it).
local function Entries(id, build, stale)
	local p = ns.providers[id]
	if not p then return {} end
	if build then return ns:GetEntries(p) or {} end
	local list = rawget(p, "_entries")
	if rawget(p, "_dirty") and not stale then return {} end
	return type(list) == "table" and list or {}
end

--- Still in your log and ready to turn in, as the game says now (the quest log's list is made again on every open: the
--- empty prompt reads the last one, a quest turned in since not taken for one).
local function StillReady(e)
	local id = Num(rawget(e, "questID"))
	local Q = C_QuestLog
	if not (id and Q) then return false end
	if Q.GetLogIndexForQuestID and not Num(Safe(Q.GetLogIndexForQuestID, id)) then return false end
	local f = Q.ReadyForTurnIn or Q.IsComplete
	return f ~= nil and Safe(f, id) == true
end

--- A list another one reads through ns:GetEntries is up to date (built when asked; the empty prompt builds none).
local function Ready(id, build)
	if build then return true end
	local p = ns.providers[id]
	return p ~= nil and rawget(p, "_entries") ~= nil and not rawget(p, "_dirty")
end

local function Level() return Num(Safe(UnitLevel, "player")) end

--- What to search for "the nearest X": with Questie, nearest; without, the word (its list still has them).
local function Nearest(what, without)
	return Has("Questie") and ("nearest " .. what) or (without or what)
end

local function Row(c)
	return {
		kind = "suggestion", kindLabel = "", name = c.name, detail = c.detail or "", icon = c.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
		key = "suggest:" .. c.id, searchText = c.search, raw = true, staysOpen = true, actionVerb = L["search this"],
		_score = c.score or 0, suggestId = c.id,
		activate = function(e)
			local UI = ns.UI
			if UI and UI.WalkTo then UI:WalkTo(e.searchText) end
		end,
		tooltip = function(e, t)
			t:AddLine(e.name, 1, 0.82, 0)
			if e.detail ~= "" then t:AddLine(ns.Plain(e.detail), 0.85, 0.85, 0.85, true) end
			t:AddLine(" ")
			t:AddDoubleLine(L["Enter searches"], e.searchText, 0.6, 0.6, 0.6, 1, 1, 1)
			local adv = ns.QueryToAdvanced and ns.QueryToAdvanced(e.searchText)
			adv = adv and adv:gsub("%s+$", "")
			if adv and adv ~= "" and adv ~= e.searchText then t:AddDoubleLine(L["Advanced"], adv, 0.6, 0.6, 0.6, 0.6, 0.85, 1) end
		end,
	}
end

----------------------------------------------------------------------
-- What's worth doing: each check gives its suggestion, or nil
----------------------------------------------------------------------

local CHECKS = {}

-- your gear wearing out
CHECKS[#CHECKS + 1] = function(build)
	local DU = ns.Durability
	if not (DU and DU.Total) then return end
	local ok, cost, damaged, low
	if build then
		Entries("durability", true) -- (made again once your gear wore or was repaired: DU.Total reads the last one made)
		ok, cost, damaged, low = pcall(DU.Total)
	else
		-- (the empty prompt: your worn pieces' wear as the game says now, no list made; the bill isn't read)
		ok, cost, damaged, low = true, nil, 0, 100
		for slot = 1, 19 do
			local cur, max = Safe(GetInventoryItemDurability, slot)
			cur, max = Num(cur), Num(max)
			if cur and max and max > 0 and cur < max then
				damaged = damaged + 1
				low = math.min(low, math.floor(100 * cur / max))
			end
		end
	end
	if not ok or not low or damaged == 0 or low > SG.REPAIR_PCT then return end
	local parts = { L["lowest piece %d%%"]:format(low) }
	if cost and cost > 0 then parts[#parts + 1] = L["repair all: %s"]:format(ns.Money(cost)) end
	return { id = "repair", name = L["Repair your gear"], detail = table.concat(parts, SEP), icon = "Interface\\Icons\\Trade_BlackSmithing",
		search = Nearest("repair", "durability"), score = 100 - low }
end

-- grey items to sell (and your bags filling up)
CHECKS[#CHECKS + 1] = function()
	local C = C_Container
	if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return end
	local items, value, free = 0, 0, 0
	local bags = ns.Bags and ns.Bags.BagIDs and ns.Bags.BagIDs() or { 0, 1, 2, 3, 4 }
	for _, bag in ipairs(bags) do
		if bag ~= -2 then -- (the keyring holds keys, not junk)
			-- (a herb or ammo bag's free slots aren't room for loot: bag type 0 only)
			local n, kind = 0, 0
			if C.GetContainerNumFreeSlots then n, kind = Safe(C.GetContainerNumFreeSlots, bag) end
			if (Num(kind) or 0) == 0 then free = free + (Num(n) or 0) end
			for s = 1, Num(Safe(C.GetContainerNumSlots, bag)) or 0 do
				local info = Safe(C.GetContainerItemInfo, bag, s)
				if type(info) == "table" and info.quality == 0 and not info.hasNoValue then
					local n = Num(info.stackCount) or 1
					items = items + n
					local price = C_Item and C_Item.GetItemInfo and select(11, Safe(C_Item.GetItemInfo, info.itemID))
					value = value + (Num(price) or 0) * n
				end
			end
		end
	end
	if items == 0 or (items < SG.JUNK_MIN and free > SG.BAGS_LOW) then return end
	local parts = { (items == 1 and L["%d grey item"] or L["%d grey items"]):format(items) }
	if value > 0 then parts[#parts + 1] = ns.Money(value) end
	if free <= SG.BAGS_LOW then parts[#parts + 1] = (free == 1 and L["%d bag slot free"] or L["%d bag slots free"]):format(free) end
	return { id = "junk", name = L["Sell your junk"], detail = table.concat(parts, SEP), icon = "Interface\\Icons\\INV_Misc_Coin_02",
		search = Nearest("vendor", "vendor"), score = 40 + (free <= SG.BAGS_LOW and 35 or 0) + math.min(items, 20) }
end

--- A weapon skill's word as Simple mode's trainers take it ("Two-Handed Swords" -> "sword"), or nil: by its spell id
--- (F.WEAPON_SKILLS' words, the shortest; the client's names have spaces and hyphens no trainer word has).
function SG.WeaponWord(name)
	local F = ns.Filters
	if not (F and F.WeaponSkillIds and F.WEAPON_SKILLS) then return nil end
	local ids = F.WeaponSkillIds(Lower(name))
	if not ids then return nil end
	local best
	for w, list in pairs(F.WEAPON_SKILLS) do
		for _, id in ipairs(list) do
			if id == ids[1] and (not best or #w < #best or (#w == #best and w < best)) then best = w end
		end
	end
	return best
end

-- your class's spells, and weapon skills, to learn now (What's Training's or TrainerSpells' list)
CHECKS[#CHECKS + 1] = function(build)
	local spells, cost, weapons = 0, 0, {}
	for _, e in ipairs(Entries("training", build)) do
		if rawget(e, "state") == "now" or e.state == "now" then
			if e.weapon then weapons[#weapons + 1] = e
			elseif not e.pet then spells, cost = spells + 1, cost + (Num(e.cost) or 0) end
		end
	end
	local out = {}
	if spells > 0 then
		local parts = { (spells == 1 and L["%d spell to learn"] or L["%d spells to learn"]):format(spells) }
		if cost > 0 then parts[#parts + 1] = ns.Money(cost) end
		out[#out + 1] = { id = "train", name = L["Train new spells"], detail = table.concat(parts, SEP), icon = "Interface\\Icons\\INV_Misc_Book_09",
			search = Has("Questie") and "nearest class trainer" or "what can i train", score = 70 + math.min(spells, 10) }
	end
	if #weapons > 0 then
		local names, word = {}, nil
		local F = ns.Filters
		for _, e in ipairs(weapons) do
			local n = Str(e.name)
			if n then
				names[#names + 1] = n
				if not word then word = SG.WeaponWord(n) end
			end
		end
		out[#out + 1] = { id = "weapon", name = L["Learn a weapon skill"], detail = table.concat(names, ", "), icon = "Interface\\Icons\\INV_Sword_04",
			search = Has("Questie") and ("nearest " .. (word or "weapon") .. " trainer") or "what can i train", score = 50 }
	end
	return out
end

-- a profession at its cap with its next rank learnable; or one to level (a crafting one under its cap)
CHECKS[#CHECKS + 1] = function(build)
	local P = ns.Professions
	if not (P and P.PlayerProfessions) then return end
	local TS = ns.TrainerSpells
	local out, levelUp, level = {}, nil, Level()
	for _, pr in ipairs((P.PlayerProfessions())) do
		local name, rank, max = pr.name, pr.rank or 0, pr.maxRank or 0
		local lw = Lower(name)
		local nr = TS and TS.NextRank and select(2, pcall(TS.NextRank, pr)) or nil
		if type(nr) ~= "table" then nr = nil end
		local capped = max > 0 and rank >= max
		-- (without TrainerSpells to say: the level each rank asks, Journeyman 10, Expert 20, Artisan 35)
		local need = SG.RANK_LEVEL[max]
		if (nr and nr.now) or (capped and not nr and max < 300 and not (need and level and level < need)) then
			local parts = { L["skill %d/%d"]:format(rank, max) }
			if nr and nr.title then parts[#parts + 1] = nr.title end
			if nr and (nr.cost or 0) > 0 then parts[#parts + 1] = ns.Money(nr.cost) end
			out[#out + 1] = { id = "rank:" .. lw, name = L["%s: train the next rank"]:format(name), detail = table.concat(parts, SEP),
				icon = pr.icon, search = Has("Questie") and ("nearest " .. lw .. " trainer") or (lw .. " training"), score = capped and 75 or 45 }
		-- (asked only: on the empty prompt's count, SG.Pressing, nearly everyone has one to level: not pressing)
		elseif build and max > 0 and rank < max and not SG.GATHERING[lw] then
			-- (the one furthest from its cap)
			local gap = (max - rank) / max
			if not levelUp or gap > levelUp.gap then
				levelUp = { gap = gap, id = "level:" .. lw, name = L["Level %s"]:format(name), detail = L["skill %d/%d"]:format(rank, max),
					icon = pr.icon, search = lw .. " plan", score = 20 + math.floor(gap * 10) }
			end
		end
	end
	if levelUp then out[#out + 1] = levelUp end
	return out
end

-- one of your class quests, now that you're its level (Attune)
CHECKS[#CHECKS + 1] = function(build)
	local AT = ns.Attune
	local level = Level()
	if not (AT and AT.RecOf and AT.Mine and level) then return end
	local best
	for _, e in ipairs(Entries("attune", build)) do
		local rec = AT.RecOf(e)
		if rec and rec.group == "class" then
			local need = rec.minLevel or rec.level
			-- (nil: Attune doesn't track it for you, another class's listed with its option for every class's)
			local ok, pct = pcall(AT.Mine, rec)
			pct = ok and Num(pct) or nil
			if pct and need and level >= need and pct < 100 and (not best or need < best.need) then best = { e = e, need = need, pct = pct } end
		end
	end
	if not best or not Str(best.e.name) then return end
	local parts = { L["Lv %d"]:format(best.need), best.pct > 0 and L["%d%% done"]:format(best.pct) or L["not started"] }
	return { id = "classquest", name = L["Class quest: %s"]:format(Str(best.e.name) or "?"), detail = table.concat(parts, SEP),
		-- (Enter: that quest's steps, each Enter opening Attune on it; 0.61.0, the player's ask)
		icon = "Interface\\Icons\\INV_Misc_Note_01", search = "steps for " .. Lower(Str(best.e.name)), score = 60 }
end

-- quests ready to turn in
CHECKS[#CHECKS + 1] = function(build)
	local names = {}
	for _, e in ipairs(Entries("quests", build, true)) do
		if e.complete and (build or StillReady(e)) then names[#names + 1] = Str(e.name) or "?" end
	end
	if #names == 0 then return end
	local shown = {}
	for i = 1, math.min(3, #names) do shown[i] = names[i] end
	return { id = "turnin", name = (#names == 1 and L["Turn in %d quest"] or L["Turn in %d quests"]):format(#names),
		detail = table.concat(shown, ", ") .. (#names > 3 and ", ..." or ""), icon = "Interface\\GossipFrame\\ActiveQuestIcon",
		search = "quests to turn in", score = 55 + math.min(#names, 10) }
end

-- quests at your level where you are (Questie): many, stay; next to none, move on
CHECKS[#CHECKS + 1] = function(build)
	local Z = ns.Zones
	local level = Level()
	if not (Z and Z.QuestCounts and level and Has("Questie")) then return end
	if not Ready("questie", build) then return end
	local ok, counts = pcall(Z.QuestCounts, level)
	if not ok or type(counts) ~= "table" then return end
	local zone = Str(Safe(GetRealZoneText))
	local here = zone and counts[zone] or 0
	if here >= SG.ZONE_QUESTS then
		return { id = "zone", name = L["Quests here: %s"]:format(zone), detail = L["%d quests at your level"]:format(here),
			icon = "Interface\\GossipFrame\\AvailableQuestIcon", search = "quests here", score = 35 }
	end
	if here < 2 then
		local best, n = nil, 0
		for z, c in pairs(counts) do if c > n or (c == n and best and z < best) then best, n = z, c end end
		if best and n >= SG.ZONE_QUESTS and best ~= zone then
			return { id = "moveon", name = L["Move on: %s"]:format(best), detail = L["%d quests at your level"]:format(n),
				icon = "Interface\\Icons\\INV_Misc_Map_01", search = "where should i quest", score = 33 }
		end
	end
end

-- bag items worth posting on the auction house (Auctionator's prices): what they'd bring together
CHECKS[#CHECKS + 1] = function(build)
	local AN = ns.Auctionator
	if not (AN and AN.On and AN.On()) then return end
	local rows, total = AN.ToPost(build)
	if #rows == 0 or total < AN.WORTH_POSTING then return end
	return { id = "auction", name = L["Post on the auction house"], icon = "Interface\\Icons\\INV_Misc_Coin_01",
		detail = (#rows == 1 and L["%d item"] or L["%d items"]):format(#rows) .. SEP .. L["about %s"]:format(AN.About(total)),
		search = "what should i auction", score = 37 + math.min(math.floor(total / 100000), 20) }
end

-- the dungeon that fits your level best (its upgrades, with AtlasLoot)
CHECKS[#CHECKS + 1] = function(build)
	local Z = ns.Zones
	local level = Level()
	if not (Z and Z.Answer and level and level >= 13 and Ready("dungeon", build)) then return end
	local ok, rows = pcall(Z.Answer, "dungeon", level)
	local top = ok and type(rows) == "table" and rows[1]
	if type(top) ~= "table" or top.noActivate or not top.name then return end
	local name = Str(top.name)
	if not name then return end
	local lname = Lower(name):gsub(" %(.*%)$", "")
	return { id = "dungeon", name = L["Run %s"]:format(name), detail = ns.Plain(top.detail or ""), icon = "Interface\\Icons\\INV_Misc_Key_03",
		search = Has("AtlasLoot") and (lname .. " upgrades") or lname, score = 30 }
end

----------------------------------------------------------------------
-- The rows
----------------------------------------------------------------------

local cache = {}

--- The suggestions, the most pressing first (at most `max`). build: read every list (asked for); else those read already.
function SG.Rows(build, max)
	local now = (type(GetTime) == "function" and GetTime()) or 0
	local key = (build and "b" or "e") .. ":" .. tostring(Level()) .. ":" .. tostring(Str(Safe(GetRealZoneText)))
	local c = cache[key]
	local all
	if c and now - c.at < SG.CACHE_FOR then all = c.rows
	else
		local found = {}
		for _, check in ipairs(CHECKS) do
			local ok, got = pcall(check, build)
			if ok and type(got) == "table" then
				if got.id then found[#found + 1] = got
				else for _, g in ipairs(got) do if type(g) == "table" and g.id then found[#found + 1] = g end end end
			end
		end
		table.sort(found, function(a, b)
			if a.score ~= b.score then return a.score > b.score end
			return a.id < b.id
		end)
		all = {}
		for i, f in ipairs(found) do all[i] = Row(f) end
		cache[key] = { at = now, rows = all }
	end
	local out = {}
	for i = 1, math.min(max or SG.MAX, #all) do out[i] = all[i] end
	return out
end
function SG.Forget() cache = {} end -- (tests; and a list changed by hand)

--- Anything worth doing, from lists already read (the empty prompt's "try: what should i do": opening builds no list).
function SG.Pressing()
	return #SG.Rows(false, 1) > 0
end

----------------------------------------------------------------------
-- The question: "what should i do", "what now", "suggestions"
----------------------------------------------------------------------

local ASKS = {}
for _, s in ipairs({ "what should i do", "what should i do now", "what should i do next", "what can i do", "what can i do now",
	"what do i do", "what do i do now", "what do i do next", "what now", "what next", "whats next", "what to do", "what to do now",
	"what should i work on", "what should i be doing", "what else", "anything to do", "something to do", "suggest",
	"suggestions", "suggest something", "ideas", "im bored", "i am bored", "bored", "now what", "next steps",
	"what should i do today" }) do ASKS[s] = true end
-- ("help me", "todo list": a search and is:todo's word, as before; release review, 0.63.0)

function SG.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if ASKS[t] or ASKS[(t:gsub("^so ", ""):gsub(" please$", ""))] then return { said = t } end
	return nil
end

function SG.Answer()
	local rows = SG.Rows(true, SG.MAX)
	if #rows == 0 then
		return { ns.NoteRow(L["Nothing pressing: your gear, training and quests are in order"]) }, L["Things to do"]
	end
	return rows, L["Things to do"] .. SEP .. L["Enter searches for it"]
end

--- Not a search: the question stays as typed (Advanced mode answers it the same).
function SG.ToAdvanced() return nil end

----------------------------------------------------------------------
-- "quests to turn in", "turn in quests", "quests ready": your quest log's quests ready to turn in
----------------------------------------------------------------------

local TI = {}
ns.TurnIn = TI
local QUEST = { quest = true, quests = true }
-- ("completed", "finished", "done quests": the quests you've done, is:done, as before)
local READY = { ready = true, complete = true }

function TI.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = " " .. t:gsub("%s+", " ") .. " "
	local quest, ready = false, false
	for w in t:gmatch("%S+") do
		if QUEST[w] then quest = true elseif READY[w] then ready = true end
	end
	if t:find(" turn in ", 1, true) or t:find(" turnin ", 1, true) or t:find(" hand in ", 1, true) or t:find(" to turn ", 1, true) then ready = true end
	if not (quest and ready) then return nil end
	-- (only those words: "quests to turn in", "completed quests", "which quests are ready", not "done quest chains in zangarmarsh")
	local FILL = { which = true, are = true, i = true, can = true, my = true, to = true, the = true, turn = true, ["in"] = true, hand = true,
		turnin = true, what = true, is = true, now = true, all = true, any = true, ["for"] = true, me = true, of = true }
	for w in t:gmatch("%S+") do if not (QUEST[w] or READY[w] or FILL[w]) then return nil end end
	return {}
end

-- (a search question, docs/QUESTIONS.md 4.1: its line is its answer and its Alt+`; Footer the footer, None the rows when
-- nothing is found)
function TI.Line() return "@questlog is:complete sort:list " end
function TI.Footer() return L["Ready to turn in"] end
function TI.None() return { ns.NoteRow(L["No quest in your log is ready to turn in"]) } end

----------------------------------------------------------------------
-- "quests here", "quests in this zone": Questie's quests at your level in the zone you're in, not done yet
----------------------------------------------------------------------

local QH = {}
ns.QuestsHere = QH
local HERE = {}
for _, s in ipairs({ "quests here", "quests in this zone", "quests in my zone", "quests around here", "quests for me here",
	"zone quests", "what quests are here", "quests in zone", "what quests can i do here", "quests i can do here",
	"quests here for my level", "quests at my level here" }) do HERE[s] = true end

function QH.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if HERE[t] then return {} end
	return nil
end

local function Band(level) return math.max(1, level - 2), level + 3 end

function QH.Answer()
	local Z = ns.Zones
	local level = Level()
	local zone = Str(Safe(GetRealZoneText))
	if not (Z and Z.QuestFitter and level and zone) then return { ns.NoteRow(L["Your zone isn't known here"]) }, L["Quests here"] end
	if not Has("Questie") then return { ns.NoteRow(L["Needs Questie: it knows every quest and where it starts"]) }, L["Quests here"] end
	local fits = Z.QuestFitter(level)
	local rows = {}
	for _, e in ipairs(Entries("questie", true)) do
		if rawget(e, "zone") == zone and fits(e) then rows[#rows + 1] = e end
	end
	table.sort(rows, function(a, b)
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
		return tostring(a.name) < tostring(b.name)
	end)
	ns.ScoreInOrder(rows)
	local lo, hi = Band(level)
	local note = L["Quests here"] .. SEP .. zone .. SEP .. L["Lv %d-%d"]:format(lo, hi)
	if #rows == 0 then return { ns.NoteRow(L["No quests at your level here: try \"where should i quest\""]) }, note end
	return rows, note
end

--- '@questie lvl:21-26 in:"the barrens"', as Advanced mode writes the same quests.
function QH.ToAdvanced()
	local level = Level()
	local zone = Str(Safe(GetRealZoneText))
	if not (level and zone) then return nil end
	local lo, hi = Band(level)
	local z = Lower(zone)
	-- (by level, as the answer lists them; 0.63.7, review: by name)
	return ("@questie lvl:%d-%d in:%s sort:level "):format(lo, hi, z:find(" ", 1, true) and ('"' .. z .. '"') or z)
end

----------------------------------------------------------------------
-- "what can i craft", "what can i cook", "tailoring i can make": your recipes you have every reagent for
----------------------------------------------------------------------

local CC = {}
ns.CanCraft = CC
local CRAFT = { craft = true, make = true, cook = true, brew = true, craftable = true }
local CRAFT_FILL = { what = true, whats = true, can = true, i = true, could = true, ["do"] = true, now = true, right = true,
	things = true, stuff = true, recipes = true, items = true, my = true, me = true, with = true, from = true, the = true,
	have = true, all = true, which = true, to = true, ["for"] = true, ["in"] = true }
-- (what you craft from: filler only after with, from, in, my: "what can i make with my mats"; "craft bags", "craftable
-- bags" are searches for bags; release review, 0.63.0)
local CRAFT_FROM = { bags = true, mats = true, materials = true, reagents = true, inventory = true }
local CRAFT_FROM_AFTER = { with = true, from = true, ["in"] = true, my = true, the = true }

--- { profs = { your professions named } } or nil: a craft word, and nothing but filler and your professions.
function CC.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	-- (a craft word first: asked on every keystroke, your professions read only when it may be this)
	local craft = false
	for w in t:gmatch("%S+") do if CRAFT[w] then craft = true break end end
	if not craft then return nil end
	local profs, named, any = {}, false, false
	local P = ns.Professions
	local mine, prev
	for w in t:gmatch("%S+") do
		local after = prev
		prev = w
		if CRAFT[w] then
			if w == "cook" then profs[#profs + 1] = "cooking" end -- (a word of the question, not one asked by: "cook" alone is a search)
		elseif CRAFT_FILL[w] then any = true
		elseif CRAFT_FROM[w] and after and CRAFT_FROM_AFTER[after] then any = true
		else
			-- (a profession of yours by its whole name: "make leather" is a search for leather)
			if not mine then mine = P and P.PlayerProfessions and (P.PlayerProfessions()) or {} end
			local hit
			for _, pr in ipairs(mine) do if w == Lower(pr.name) then hit = w end end
			if not hit then return nil end
			profs[#profs + 1] = hit
			named = true
		end
	end
	-- ("craft", "cook", "make" alone: searches; "what can i craft", "craftable", "tailoring i can make": this)
	if not (any or named or t:find("craftable", 1, true)) then return nil end
	return { profs = profs }
end

function CC.Answer(q)
	local F = ns.Filters
	local ok = F and F._ and F._.IS and F._.IS.craftable
	local want = {}
	for _, n in ipairs(q.profs or {}) do want[n] = true end
	local rows = {}
	if ok then
		for _, e in ipairs(Entries("recipes", true)) do
			if e.recipeID ~= nil and (not next(want) or (e.profName and want[Lower(e.profName)])) and ok(e) then rows[#rows + 1] = e end
		end
	end
	table.sort(rows, function(a, b) return tostring(a.name) < tostring(b.name) end)
	ns.ScoreInOrder(rows)
	if #rows == 0 then return { ns.NoteRow(L["Nothing to craft from what's in your bags"]) }, L["You can craft"] end
	return rows, L["You can craft"]
end

--- As Advanced syntax: its answer and its Alt+` (docs/QUESTIONS.md 4.1); its professions by prof:, the recipe's own
--- (Smelting's recipes are Mining's: the word "mining" missed them, 1.0.78).
function CC.Line(q)
	local parts = { "@recipe", "is:craftable" }
	if #q.profs > 0 then parts[#parts + 1] = "prof:" .. table.concat(q.profs, "|"):gsub(" ", "_") end
	parts[#parts + 1] = "sort:name"
	return table.concat(parts, " ") .. " "
end
function CC.Footer() return L["You can craft"] end
function CC.None() return { ns.NoteRow(L["Nothing to craft from what's in your bags"]) } end

----------------------------------------------------------------------
-- "quests per zone", "my quests by zone", "items by quality": a list grouped by a field, as Advanced mode writes it
-- ("@questie | group by zone"); the search runs that line (UI/Results.lua's TakeAggregate), Enter on a group lists it
----------------------------------------------------------------------

local PF = {}
ns.PerField = PF
-- (fields a list is grouped by: not the ones summed up, value, price, count)
local GROUPS = { zone = true, instance = true, dungeon = true, raid = true, boss = true, quality = true, type = true,
	subtype = true, slot = true, level = true, ilvl = true, kind = true, owner = true }
local LEAD = { how = true, many = true, number = true, of = true, count = true, the = true, show = true, list = true, all = true }

local function GroupField(w)
	local A = ns.Aggregate
	if not (A and A.FIELDS) then return nil end
	local name = A.FIELDS[w] and w or (A.ALIASES and A.ALIASES[w])
	return name and A.FIELDS[name] and GROUPS[name] and name or nil
end

--- "quests": Questie's (your log's without Questie, or "my quests"); another word: the list it names ("items", "mounts").
local function ListFor(word, mine)
	if word == "quests" or word == "quest" then
		return (not mine and ns.providers.questie and Has("Questie")) and "@questie" or "@questlog"
	end
	-- (a list's own name or alias, whole, as it's written: not the start of one, "a by zone" isn't @achievements, nor a
	-- plural made up, "keys"; release review, 0.63.0)
	-- (written as the kind's own word, as Alt+` writes every other list: "items by zone" is @item, not @items; Alt+` of
	-- it read @item, FRONT_END.md 10.8)
	if not ns.aliasMap then ns:ResolveProvider("") end
	local map = ns.aliasMap or {}
	local one = word:sub(-1) == "s" and word:sub(1, -2)
	local said = map[word] and word or (one and #one > 1 and map[one] and one) or nil
	if not said then return nil end
	local p = map[said]
	return (p and not p.noKind and ns:KindName(p)) or ("@" .. said)
end

--- { line = "@questie | group by zone " } or nil: [how many] [my] <list> per|by|in each|for each <field>.
function PF.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local w = {}
	for x in t:gmatch("%S+") do w[#w + 1] = x end
	local i = 1
	while w[i] and LEAD[w[i]] do i = i + 1 end
	local mine = w[i] == "my"
	if mine then i = i + 1 end
	local what = w[i]
	if not what then return nil end
	i = i + 1
	local by = w[i]
	if by == "per" or by == "by" or by == "each" then i = i + 1
	elseif (by == "in" or by == "for") and w[i + 1] == "each" then i = i + 2
	else return nil end
	if w[i] == "each" then i = i + 1 end -- ("per each zone")
	local field = w[i] and GroupField(w[i])
	if not field or w[i + 1] then return nil end
	local list = ListFor(what, mine)
	if not list then return nil end
	return { line = list .. " | group by " .. field .. " " }
end

-- (a search question: its line is its answer, searched with its steps; Questions.lua's Q.StepLine reads it at the steps
-- stage, the filters typed after it before its "|")

----------------------------------------------------------------------
-- "who gives the defias brotherhood", "where do i turn in the defias brotherhood": a quest's giver or turn-in NPC
-- (1.0.47, the reach audit: "who gives ..." was the /who list). Questie's startedBy / finishedBy; "who" alone and "who
-- 20-30" stay the /who list.
----------------------------------------------------------------------

local QP = {}
ns.QuestPeople = QP
local GIVES = { "^who gives (.+)$", "^who starts (.+)$", "^who offers (.+)$", "^who has the quest (.+)$",
	"^where do i get the quest (.+)$", "^where do i pick up (.+)$", "^who gives out (.+)$" }
local TAKES = { "^who takes (.+)$", "^who do i turn in (.+) to$", "^who do i turn (.+) in to$", "^where do i turn in (.+)$",
	"^where to turn in (.+)$", "^where do i hand in (.+)$", "^who do i give (.+) to$", "^where do i turn (.+) in$" }
local function Plain(s) return (s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")) end
local byName, byNameOf -- (Questie's quests by their name as a question reads it, made once a list)
local function QuestNamed(said)
	local p = ns.providers.questie
	local list = p and p._entries
	if not list then return nil end
	if byNameOf ~= list then
		byName, byNameOf = {}, list
		for _, e in ipairs(list) do
			local n = type(e.name) == "string" and Plain(Lower(e.name):gsub("'", ""):gsub("%p", " ")) or nil
			local id = e.qid
			-- (every quest of the name: a chain's parts and the other faction's twin share one; review, 1.0.68)
			if n and id then
				local b = byName[n]
				if not b then b = { id = id, name = e.name, ids = {} }; byName[n] = b end
				b.ids[#b.ids + 1] = id
			end
		end
	end
	local s = Plain((said:gsub("^the quest ", ""):gsub("^quest ", ""):gsub(" quest$", "")))
	return byName[s] or byName[(s:gsub("^the ", ""))] or byName["the " .. s]
end
function QP.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = Plain(t)
	for _, set in ipairs({ { GIVES, false }, { TAKES, true } }) do
		for _, pat in ipairs(set[1]) do
			local rest = t:match(pat)
			local q = rest and QuestNamed(rest)
			if q then return { id = q.id, ids = q.ids, name = q.name, finish = set[2] } end
		end
	end
	return nil
end
--- Which of a name's quests the answer is about: those in your log, else those your race and class can take, else all.
function QP.Which(ids)
	local log = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
	local QR = ns.QuestRewards
	local inLog, mine = {}, {}
	for _, id in ipairs(ids) do
		if log and Safe(log, id) then inLog[#inLog + 1] = id end
		if not QR or not QR.ForYou or QR.ForYou(id) then mine[#mine + 1] = id end
	end
	return (#inLog > 0 and inLog) or (#mine > 0 and mine) or ids
end
function QP.Answer(q)
	local QD = ns.QuestieData
	local DB = QD and QD.DB and QD.DB()
	local I = ns.Integrations
	local title = q.name .. SEP .. (q.finish and L["turn in"] or L["quest giver"])
	local rows, seen, what = {}, {}, nil
	for _, qid in ipairs(QP.Which(q.ids or { q.id })) do
		local by = DB and Safe(DB.QueryQuestSingle, qid, q.finish and "finishedBy" or "startedBy")
		if type(by) == "table" then
			for _, id in ipairs(type(by[1]) == "table" and by[1] or {}) do
				local r = not seen[id] and I and I.NpcRow and I.NpcRow(id)
				if r then seen[id] = true; rows[#rows + 1] = r end
			end
			what = what or (type(by[2]) == "table" and by[2][1] and L["an object"]) or (type(by[3]) == "table" and by[3][1] and L["an item"]) or nil
		end
	end
	if #rows == 0 and what then
		return { ns.NoteRow(q.finish and L["Turn in: %s"]:format(what) or L["%s is started by %s."]:format(q.name, what)) }, title
	end
	if #rows == 0 then return { ns.NoteRow(L["Nothing has that. Check the spelling, or try other words."]) }, title end
	ns.ScoreInOrder(rows)
	return rows, title
end
--- Not a search: the question stays as typed (Advanced mode answers it the same).
function QP.ToAdvanced() return nil end

----------------------------------------------------------------------
-- "quests near me", "nearest quests": Questie's quests at your level, not done, whose giver is nearest; "turn ins near
-- me": your quests ready to turn in, by how near their turn-in NPC is (1.0.48, the reach audit: both were NPCs named
-- "quests", "turn ins")
----------------------------------------------------------------------

local NQ = {}
ns.NearQuests = NQ
local NEAR_SAID = { "near me", "nearby", "nearest", "closest", "close to me", "around me", "near here", "close by" }
local NQ_FILL = { i = true, can = true, ["do"] = true, take = true, to = true, that = true, me = true, my = true, ["for"] = true,
	level = true, at = true, the = true, get = true, pick = true, up = true, show = true, list = true, any = true, some = true,
	what = true, which = true, are = true, near = true, quest = true, quests = true }
local TURN_SAID = { "turn ins", "turn in", "turnins", "turnin", "hand ins", "hand in" }
NQ.MAX = 30
function NQ.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = " " .. t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "") .. " "
	local near
	for _, p in ipairs(NEAR_SAID) do
		local a, b = t:find(" " .. p .. " ", 1, true)
		if a then near = true; t = t:sub(1, a) .. t:sub(b) end
	end
	if not near then return nil end
	local turn = false
	for _, p in ipairs(TURN_SAID) do
		local a, b = t:find(" " .. p .. " ", 1, true)
		if a then turn = true; t = t:sub(1, a) .. t:sub(b) end
	end
	local quest = turn
	for w in t:gmatch("%S+") do
		if w == "quest" or w == "quests" then quest = true
		elseif not NQ_FILL[w] then return nil end
	end
	if not quest then return nil end
	return { turn = turn }
end
function NQ.Answer(q)
	local I = ns.Integrations
	local here = I and I.Here and I.Here()
	local title = (q.turn and L["Ready to turn in"] or L["Quests here"]) .. SEP .. L["nearest first"]
	if not Has("Questie") then return { ns.NoteRow(L["Needs Questie: it knows every quest and where it starts"]) }, title end
	if not here then return { ns.NoteRow(ns.UpperFirst(L["where you are isn't known here"])) }, title end
	local QD = ns.QuestieData
	local DB = QD and QD.DB and QD.DB()
	local found = {}
	local function Add(row, npcID, note)
		local d = npcID and I.NpcDistance and I.NpcDistance(npcID, here)
		if d then found[#found + 1] = { d = d, v = I.NearView(row, d, note) } end
	end
	if q.turn then
		local seen = {}
		for _, e in ipairs(Entries("quests", true)) do
			if e.complete and e.questID then
				local by = DB and Safe(DB.QueryQuestSingle, e.questID, "finishedBy")
				local npc = type(by) == "table" and type(by[1]) == "table" and by[1][1]
				local row = npc and not seen[npc] and I.NpcRow and I.NpcRow(npc)
				if row then seen[npc] = true; Add(row, npc, e.name) end
			end
		end
	else
		local Z = ns.Zones
		local level = Level()
		local fits = Z and Z.QuestFitter and level and Z.QuestFitter(level)
		for _, e in ipairs(fits and Entries("questie", true) or {}) do
			if fits(e) then
				local npc, giver = I.QuestGiver and I.QuestGiver(e.qid)
				if npc then Add(e, npc, giver) end
			end
		end
	end
	table.sort(found, function(a, b) return a.d < b.d end)
	local rows = {}
	for i = 1, math.min(#found, NQ.MAX) do rows[i] = found[i].v end
	if #rows == 0 then
		return { ns.NoteRow(q.turn and L["No quest in your log is ready to turn in"] or L["No quests at your level here: try \"where should i quest\""]) }, title
	end
	ns.ScoreInOrder(rows)
	return rows, title
end
--- Not a search: the question stays as typed (Advanced mode answers it the same).
function NQ.ToAdvanced() return nil end

----------------------------------------------------------------------
-- "deadmines bosses", "bosses in the deadmines": an instance's bosses from AtlasLoot, each leading to its loot (1.0.50,
-- the reach audit)
----------------------------------------------------------------------

local IB = {}
ns.InstanceBosses = IB
local BOSS_WORDS = { boss = true, bosses = true }
local IB_FILL = { ["in"] = true, of = true, the = true, at = true, ["for"] = true, all = true, list = true, show = true, what = true,
	which = true, are = true, me = true, my = true }
local function BossWalk(e)
	local P = ns.Pipes
	local line = P and P.Phrase and P.Phrase(e.name, "drops") or (e.name .. " > drops")
	if ns.UI and ns.UI.WalkTo then ns.UI:WalkTo(line, e) end
end
function IB.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local boss, rest = false, {}
	for w in t:gmatch("%S+") do
		if BOSS_WORDS[w] then boss = true elseif not IB_FILL[w] then rest[#rest + 1] = w end
	end
	if not boss or #rest == 0 then return nil end
	local P = ns.Pipes
	if not (P and P.BossLoot) then return nil end
	local want = table.concat(rest, " ")
	-- (the instance's whole name, with or without "the", or its shorthand's; or the start of its name, 4 letters or more:
	-- "st bosses" listed the Stockade's with Stratholme's, "boss a" every instance's; review, 1.0.68)
	local S = ns.Shorthand -- ("vc bosses": its full name, Shorthand.lua)
	local exp = S and type(S[want]) == "table" and S[want] or {}
	local names = { [want] = true, ["the " .. want] = true }
	for _, f in ipairs(exp) do if type(f) == "string" then names[f] = true end end
	local function Fits(li)
		if names[li] then return true end
		if #want < 4 then return false end
		return li:sub(1, #want) == want or li:sub(1, #want + 4) == "the " .. want
	end
	local found, whole = {}, {}
	for _, pl in ipairs(P.BossPlaces and P.BossPlaces() or {}) do
		if Fits(pl.linst) then
			found[#found + 1] = pl
			if names[pl.linst] then whole[#whole + 1] = pl end
		end
	end
	if #whole > 0 then found = whole end -- (the instance named whole, not the others its name starts)
	if #found == 0 then return nil end
	local place = found[1].inst
	for _, f in ipairs(found) do if f.linst ~= found[1].linst then place = ns.UpperFirst(want) break end end
	return { bosses = found, place = place }
end
function IB.Answer(q)
	local rows = {}
	for _, f in ipairs(q.bosses) do
		rows[#rows + 1] = { key = "boss:" .. f.boss .. ":" .. f.inst, name = f.boss, kind = "pipe", kindLabel = L["Bosses"], detail = f.inst .. SEP
			.. (f.n == 1 and L["%d item"] or L["%d items"]):format(f.n), activate = BossWalk, staysOpen = true,
			icon = "Interface\\Icons\\INV_Misc_Bone_ElfSkull_01" }
	end
	table.sort(rows, function(a, b) if a.detail ~= b.detail then return a.detail < b.detail end return a.name < b.name end)
	ns.ScoreInOrder(rows)
	return rows, L["Bosses"] .. SEP .. q.place
end
--- Not a search: the question stays as typed (Advanced mode answers it the same).
function IB.ToAdvanced() return nil end

----------------------------------------------------------------------
-- "how many linen do i have", "do i have linen cloth", "count my linen": the items with that name, how many in all and
-- where (your bags, your bank, your alts: @stored's count when a bag addon keeps them), the most first (1.0.51, the
-- reach audit)
----------------------------------------------------------------------

local HV = {}
ns.HaveQ = HV
local HAVE_SAID = { "^how many (.+) do i have$", "^how much (.+) do i have$", "^how many (.+) have i got$", "^how many (.+) do i own$",
	"^do i have any (.+)$", "^do i have (.+)$", "^count my (.+)$", "^count of my (.+)$", "^how many (.+) are in my bags$" }
HV.MAX = 8
-- (what isn't an item you carry: your money, a list of its own; "how much gold do i have" listed items called gold)
HV.NOT_ITEMS = { gold = true, money = true, silver = true, copper = true, mail = true, quests = true, quest = true,
	mounts = true, pets = true, toys = true, achievements = true, friends = true, alts = true, bags = true, slots = true,
	spells = true, talents = true, recipes = true, professions = true, mats = true, items = true, ["bag space"] = true,
	["free slots"] = true, ["free bag slots"] = true }
function HV.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	for _, pat in ipairs(HAVE_SAID) do
		local what = t:match(pat)
		if what then
			what = what:gsub("^the ", ""):gsub("^my ", ""):gsub("^any ", ""):gsub(" left$", "")
			if what ~= "" and not what:find("^%d") and not HV.NOT_ITEMS[what] then return { what = what } end
		end
	end
	return nil
end
local function Counted(e, stored)
	local id = e.itemID or rawget(e, "key")
	local count = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	local bags = id and Num(Safe(count, id)) or 0
	local all = id and Num(Safe(count, id, true)) or bags
	local st = stored and stored[id]
	local alts = st and math.max(0, (st.total or 0) - all) or 0
	local parts = { L["have %d"]:format(bags) }
	if all > bags then parts[1] = parts[1] .. " " .. L["(+%d bank)"]:format(all - bags) end
	if alts > 0 then parts[#parts + 1] = L["%d on alts"]:format(alts) end
	return all + alts, table.concat(parts, SEP)
end
function HV.Answer(q)
	local words = {}
	for w in q.what:gmatch("%S+") do words[#words + 1] = w end
	local stored = {}
	for _, e in ipairs(Entries("stored", true)) do local id = e.itemID or rawget(e, "key") if id then stored[id] = e end end
	local seen, found = {}, {}
	local function Look(list)
		for _, e in ipairs(list) do
			local id = e.itemID or rawget(e, "key")
			local n = rawget(e, "_lname") or Lower(tostring(e.name))
			local ok = id and not seen[id]
			for _, w in ipairs(words) do if ok and not n:find(w, 1, true) then ok = false end end
			if ok then
				seen[id] = true
				local total, said = Counted(e, stored)
				found[#found + 1] = { total = total, v = setmetatable({ detail = said, count = total }, { __index = e }) }
			end
		end
	end
	Look(Entries("items", true))
	local list = {}
	for _, e in pairs(stored) do list[#list + 1] = e end
	Look(list)
	table.sort(found, function(a, b)
		if a.total ~= b.total then return a.total > b.total end
		return tostring(a.v.name) < tostring(b.v.name)
	end)
	local rows = {}
	for i = 1, math.min(#found, HV.MAX) do rows[i] = found[i].v end
	local title = L["Count"] .. SEP .. q.what
	if #rows == 0 then return { ns.NoteRow(L["You don't carry %s."]:format(q.what)) }, title end
	ns.ScoreInOrder(rows)
	return rows, title
end
--- The same items, where they are: your bags' (@item), and with a bag addon's records your bank's and alts' (@stored:
--- only what isn't in your bags; review, 1.0.70: @stored alone left an item only in your bags out).
function HV.ToAdvanced(q)
	-- (the words as Advanced mode writes them, "linen cloth|type:cloth": Alt+` again reads the same; its own lists left out)
	local words = ns.LineToAdvanced and ns.LineToAdvanced(q.what) or q.what
	repeat local n; words, n = words:gsub("^%s*@%S+%s*", "") until n == 0
	return (ns.providers.stored and "@item @stored " or "@item ") .. (words:gsub("%s+$", "")) .. " "
end

----------------------------------------------------------------------
-- "quests that start from an item", "quests started by items": the quests Questie says an item starts (startedBy's
-- items), each with the item (1.0.52, the reach audit)
----------------------------------------------------------------------

local QS = {}
ns.ItemQuests = QS
local QS_SAID = { "quests that start from an item", "quests that start from items", "quests started by an item",
	"quests started by items", "quests from items", "item started quests", "quests an item starts", "quests items start",
	"quest starting items", "items that start quests", "items that start a quest" }
local QS_SET = {}
for _, s in ipairs(QS_SAID) do QS_SET[s] = true end
function QS.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return QS_SET[t] and {} or nil
end
function QS.Answer()
	local QD = ns.QuestieData
	local DB = QD and QD.DB and QD.DB()
	local title = L["Started by %s"]:format(L["an item"])
	if not (DB and Has("Questie")) then return { ns.NoteRow(L["Needs Questie: it knows every quest and where it starts"]) }, title end
	local rows = {}
	for _, e in ipairs(Entries("questie", true)) do
		local by = Safe(DB.QueryQuestSingle, e.qid, "startedBy")
		local items = type(by) == "table" and type(by[3]) == "table" and by[3]
		local id = items and items[1]
		if id then
			local name = DB.QueryItemSingle and Str(Safe(DB.QueryItemSingle, id, "name"))
			rows[#rows + 1] = setmetatable({ detail = name and L["Started by %s"]:format(name) or L["Started by %s"]:format(L["an item"]) }, { __index = e })
		end
	end
	if #rows == 0 then return { ns.NoteRow(L["Nothing has that. Check the spelling, or try other words."]) }, title end
	ns.ScoreInOrder(rows)
	return rows, title
end
--- Not a search: the question stays as typed (Advanced mode answers it the same).
function QS.ToAdvanced() return nil end

----------------------------------------------------------------------
-- "what level is hogger", "what level is the stockade", "duskwood level": the level Terminal has for it (an NPC's from
-- Questie, a dungeon's or a raid's, a zone's range), its row saying it (1.0.55, the reach audit)
----------------------------------------------------------------------

local LV = {}
ns.LevelOf = LV
local LV_SAID = { "^what level is (.+)$", "^what level are (.+)$", "^what lvl is (.+)$", "^level of (.+)$", "^(.+) level range$", "^(.+) levels$", "^(.+) level$", "^how high is (.+)$" }
local function Named(list, want)
	for _, e in ipairs(list) do
		local n = rawget(e, "_lname") or Lower(tostring(e.name))
		if n == want or n == "the " .. want then return e end
	end
end
local function LevelSaid(lo, hi)
	if not lo then return nil end
	hi = hi or lo
	return lo == hi and L["Lv %d"]:format(lo) or L["Lv %d-%d"]:format(lo, hi)
end
function LV.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	for _, pat in ipairs(LV_SAID) do
		local what = t:match(pat)
		if what then
			what = what:gsub("^the ", "")
			if what ~= "" and what ~= "my" and what ~= "your" then
				-- a dungeon or a raid, a zone, an NPC (Questie's), in that order. (Asked on every keystroke: the small
				-- instance lists, the zones' table, the NPCs' names text; no map or NPC list built here, review 1.0.67)
				for _, kind in ipairs({ "dungeon", "raid" }) do
					local e = ns.providers[kind] and Named(Entries(kind, true), what)
					if e and e.minLevel then return { row = e, said = LevelSaid(e.minLevel, e.level) } end
				end
				local Z = ns.Zones
				for _, z in ipairs(Z and Z.LIST or {}) do
					local zn = z[6] and Lower(z[6])
					if zn and (zn == what or zn == "the " .. what) and z[2] then
						local m = ns.providers.maps and Named(Entries("maps"), what)
						return { row = m, name = z[6], said = LevelSaid(z[2], z[3]) }
					end
				end
				local I = ns.Integrations
				local id = I and I.NpcIdNamed and (I.NpcIdNamed(what) or I.NpcIdNamed("the " .. what))
				if id and I.NpcField then
					local lo, hi = Num(I.NpcField(id, "minLevel")), Num(I.NpcField(id, "maxLevel"))
					local e = lo and I.NpcRow and I.NpcRow(id)
					if e then return { row = e, said = LevelSaid(lo, hi) } end
				end
			end
			return nil
		end
	end
	return nil
end
function LV.Answer(q)
	local name = q.row and q.row.name or q.name
	local title = L["Level"] .. SEP .. tostring(name)
	if not q.row then return { ns.NoteRow(tostring(name) .. ": " .. q.said) }, title end
	local d = q.row.detail
	return { setmetatable({ detail = q.said .. ((d and d ~= "" and not tostring(d):find(q.said, 1, true)) and (SEP .. d) or "") }, { __index = q.row }) }, title
end
--- Not a search: the question stays as typed (Advanced mode answers it the same).
function LV.ToAdvanced() return nil end

----------------------------------------------------------------------
-- "what are my bags worth", "bag value", "what's my stuff worth": what your bags sell to a vendor for, summed (with
-- Auctionator, AuctionValues.lua's AhValueQ answers first, with the auction house's worth). The search runs the line
-- (1.0.56, the reach audit).
----------------------------------------------------------------------

local BW = {}
ns.BagWorth = BW
-- (junk: not what it's worth here, "what is my junk worth" is the junk search's; a word that turns the question away)
local BW_LISTS = { bags = true, bag = true, stuff = true, inventory = true, items = true, things = true, junk = false }
local BW_FILL = { the = true, my = true, of = true, what = true, whats = true, are = true, is = true, how = true, much = true,
	["in"] = true, total = true, all = true, me = true, i = true, ["do"] = true, have = true, vendor = true, sell = true, ["for"] = true }
function BW.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local list, worth = false, false
	for w in t:gmatch("%S+") do
		if BW_LISTS[w] then list = true
		elseif w == "worth" or w == "value" then worth = true
		elseif not BW_FILL[w] then return nil end
	end
	if not (list and worth) then return nil end
	return { line = "in:bags | sum value " }
end

----------------------------------------------------------------------
-- "bigger bags", "bags with more slots": bags bigger than your smallest one, the most slots first, each saying where it
-- comes from (its loot row's boss, its recipe, its quest), from your bags, AtlasLoot, your recipes and those you could
-- learn (1.0.57, the reach audit). Its own answer: no one Advanced line lists the same rows (review, 1.0.70).
----------------------------------------------------------------------

local BB = {}
ns.BiggerBags = BB
local BB_BIG = { bigger = true, larger = true, better = true, biggest = true, largest = true, more = true }
local BB_FILL = { bags = true, bag = true, with = true, slots = true, slot = true, ["for"] = true, me = true, my = true, the = true,
	than = true, mine = true, some = true, any = true, a = true, show = true, find = true, where = true, to = true, get = true }
--- Your smallest bag's slots (bags 1-4; an empty bag slot: 0, any bag is bigger), or nil when the game won't say.
function BB.Smallest()
	local num = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
	if not num then return nil end
	local least
	for bag = 1, 4 do
		local n = Num(Safe(num, bag)) or 0
		if not least or n < least then least = n end
	end
	return least
end
function BB.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local big, bag = false, false
	for w in t:gmatch("%S+") do
		if BB_BIG[w] then big = true
		elseif w == "bag" or w == "bags" then bag = true end
		if not (BB_BIG[w] or BB_FILL[w]) then return nil end
	end
	if not (big and bag) then return nil end
	local n = BB.Smallest() or 0
	return { least = n, line = ("bag slots:>%d sort:slots "):format(n) }
end
BB.MAX = 50
BB.LISTS = { "items", "loot", "recipes", "missing" } -- (your bags', AtlasLoot's, your recipes', those you could learn)
function BB.Answer(q)
	local F = ns.Filters
	local bigger = F and F.Parse(("slots:>%d"):format(q.least))
	local title = ns.UpperFirst(L["bags"]) .. SEP .. L["with %s slots"]:format("> " .. q.least)
	if not bigger then return { ns.NoteRow(L["Nothing has that. Check the spelling, or try other words."]) }, title end
	local rows, seen = {}, {}
	for _, kind in ipairs(BB.LISTS) do
		for _, e in ipairs(ns.providers[kind] and Entries(kind, true) or {}) do
			local id = F.ItemOf and F.ItemOf(e) or e.itemID
			local ok, yes = pcall(bigger, e)
			if ok and yes and not (id and seen[id]) then
				if id then seen[id] = true end
				rows[#rows + 1] = e
			end
		end
	end
	-- (the most slots first, then cut: Bar.SortRows only scores the rows, so the cut kept the lists' order; review, 1.0.68)
	if ns.Bar and ns.Bar.Order then rows = ns.Bar.Order(rows, "slots") end
	for i = #rows, BB.MAX + 1, -1 do rows[i] = nil end
	if #rows == 0 then return { ns.NoteRow(L["Nothing has that. Check the spelling, or try other words."]) }, title end
	ns.ScoreInOrder(rows)
	return rows, title
end
--- Not a search: the question stays as typed (Advanced mode answers it the same).
function BB.ToAdvanced() return nil end

----------------------------------------------------------------------
-- "achievements almost done", "quests almost done": those under way, the closest to done first (sort:progress: an
-- achievement's criteria, a quest's objectives; 1.0.59, the reach audit)
----------------------------------------------------------------------

local AD = {}
ns.AlmostDone = AD
local AD_NEAR = { almost = true, nearly = true, closest = true, close = true }
local AD_FILL = { done = true, finished = true, complete = true, completed = true, to = true, my = true, the = true, i = true,
	am = true, im = true, that = true, are = true, which = true, what = true, show = true, list = true, me = true, ["in"] = true,
	progress = true }
local AD_KINDS = { achievement = "achievements", achievements = "achievements", quest = "quests", quests = "quests" }
AD.MAX = 50
function AD.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local near, kind = false, nil
	for w in t:gmatch("%S+") do
		if AD_NEAR[w] then near = true
		elseif AD_KINDS[w] then kind = AD_KINDS[w]
		elseif not AD_FILL[w] then return nil end
	end
	if not (near and kind) then return nil end
	return { kind = kind }
end
function AD.Answer(q)
	local A = ns.Aggregate
	local found = {}
	for _, e in ipairs(Entries(q.kind, true)) do
		local f = A and A.Progress and A.Progress(e)
		if f and f > 0 and f < 1 and not rawget(e, "completed") and not e.complete then found[#found + 1] = { f = f, e = e } end
	end
	table.sort(found, function(a, b) if a.f ~= b.f then return a.f > b.f end return tostring(a.e.name) < tostring(b.e.name) end)
	local rows = {}
	for i = 1, math.min(#found, AD.MAX) do rows[i] = found[i].e end
	local title = L["Progress"] .. SEP .. L["the most first"]
	if #rows == 0 then return { ns.NoteRow(L["Nothing has that. Check the spelling, or try other words."]) }, title end
	ns.ScoreInOrder(rows)
	return rows, title
end
--- Not a search: the question stays as typed (Advanced mode answers it the same; "@achievement is:todo sort:progress"
--- listed the ones not begun too; review, 1.0.70).
function AD.ToAdvanced() return nil end

----------------------------------------------------------------------
-- "where is my hearth", "my hearthstone location": where your hearthstone takes you (the game's GetBindLocation) and
-- whether it's ready (1.0.60, the reach audit)
----------------------------------------------------------------------

local HB = {}
ns.HearthBind = HB
HB.ITEM = 6948 -- (the Hearthstone)
local HB_SET = {}
for _, s in ipairs({ "where is my hearth", "where is my hearthstone", "my hearthstone location", "my hearth location", "hearth location",
	"hearthstone location", "where am i bound", "where is my home", "where is my hearth set", "where is my hearthstone set",
	"where does my hearthstone go", "where does my hearth go", "hearthstone set to", "where is my inn" }) do HB_SET[s] = true end
function HB.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return HB_SET[t] and {} or nil
end
--- The hearthstone's cooldown said: "ready", "12 min left"; nil when the game won't say.
function HB.Cooldown()
	local cd = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown
	local start, dur = Safe(cd, HB.ITEM)
	start, dur = Num(start), Num(dur)
	if not (start and dur) then return nil end
	local left = start > 0 and dur > 1.5 and (start + dur - GetTime()) or 0
	if left <= 0 then return L["ready"] end
	return L["%s left"]:format(ns.Left(left)) -- (Util.lua's one "how long is left"; review, 1.0.73)
end
function HB.Answer()
	local where = Str(Safe(_G.GetBindLocation))
	local title = ns.UpperFirst(L["in %s"]:format(where or "?"))
	if not where then return { ns.NoteRow(L["The game doesn't say where your hearthstone is set"]) }, title end
	local cd = HB.Cooldown()
	local said = where .. (cd and (SEP .. cd) or "")
	for _, e in ipairs(Entries("items", true)) do
		if e.itemID == HB.ITEM then return { setmetatable({ detail = said }, { __index = e }) }, title end
	end
	return { ns.NoteRow(said) }, title
end
--- Not a search: the question stays as typed (Advanced mode answers it the same).
function HB.ToAdvanced() return nil end

----------------------------------------------------------------------
-- "how long to level", "xp per hour", "time to level": experience an hour this session, and the time to your next level
-- at that rate (Providers/Experience.lua's X.Rate; 1.0.61, the reach audit)
----------------------------------------------------------------------

local XR = {}
ns.XpRate = XR
local XR_SET = {}
for _, s in ipairs({ "how long to level", "how long until i level", "how long till i level", "how long to next level",
	"how long to ding", "time to level", "time to next level", "time until next level", "xp per hour", "exp per hour",
	"experience per hour", "xp an hour", "xp rate", "xp hr", "exp hr", "leveling speed", "levelling speed", "my xp rate",
	"how fast am i leveling", "how fast am i levelling" }) do XR_SET[s] = true end
function XR.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return XR_SET[t] and {} or nil
end
local function Dur(secs)
	secs = math.max(0, math.floor(secs + 0.5))
	local h, m = math.floor(secs / 3600), math.floor(secs % 3600 / 60)
	if h == 0 then return L["%d min"]:format(math.max(1, m)) end
	return m == 0 and L["%d h"]:format(h) or L["%d h %d min"]:format(h, m)
end
function XR.Answer()
	local X = ns.Experience
	local rate, secs, me
	if X and X.Rate then rate, secs, me = X.Rate() end -- (an "and" keeps only the first of several results)
	local title = L["Experience"]
	if me and me.maxed then return { ns.NoteRow(L["Max level"]) }, title end
	if not rate then return { ns.NoteRow(L["No experience gained this session yet"]) }, title end
	if rate <= 0 then return { ns.NoteRow(L["No experience gained this session yet"], L["this session: %s"]:format(Dur(secs))) }, title end
	local left = math.max(0, me.max - me.xp)
	return {
		ns.NoteRow(L["%s experience an hour"]:format(ns.Thousands and ns.Thousands(math.floor(rate)) or tostring(math.floor(rate))),
			L["this session: %s"]:format(Dur(secs))),
		ns.NoteRow(L["Level %d in about %s"]:format(me.level + 1, Dur(left / rate * 3600))),
	}, title
end
--- Not a search: the question stays as typed (Advanced mode answers it the same).
function XR.ToAdvanced() return nil end
