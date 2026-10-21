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

function TI.Answer()
	local rows = {}
	for _, e in ipairs(Entries("quests", true)) do if e.complete then rows[#rows + 1] = e end end
	ns.ScoreInOrder(rows)
	if #rows == 0 then return { ns.NoteRow(L["No quest in your log is ready to turn in"]) }, L["Ready to turn in"] end
	return rows, L["Ready to turn in"]
end

function TI.ToAdvanced() return "@questlog is:complete " end

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

function CC.ToAdvanced(q)
	return "@recipe is:craftable " .. ((#q.profs > 0) and (table.concat(q.profs, " ") .. " ") or "")
end

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
	if not ns.aliasMap then ns:ResolveProvider("") end
	local map = ns.aliasMap or {}
	if map[word] then return "@" .. word end
	local one = word:sub(-1) == "s" and word:sub(1, -2)
	if one and #one > 1 and map[one] then return "@" .. one end
	return nil
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

--- (searched as its Advanced line: TakeAggregate; nothing to answer here: nil, the other questions asked on)
function PF.Answer() return nil end

--- The line as the search runs it, or nil: a "per" line with the Advanced filters and sorts typed after it before its
--- "|" ("items by zone q:rare" -> "@item q:rare | group by zone"), unless another question takes it ("lockouts by raid":
--- @lockout's; release review, 0.63.0).
function PF.Line(text)
	local head, tail = text, {}
	while true do
		local h, last = head:match("^(.-)%s+(%S+)%s*$")
		if not (h and last and last:find("^[-!]?%a+:%S")) then break end
		table.insert(tail, 1, last)
		head = h
	end
	-- ("ah value of my mats": "@mats | sum ahvalue", with Auctionator, asked before the others: Search/Auctionator.lua;
	-- else a "per" line no other question takes)
	local AN = ns.Auctionator
	local q = AN and AN.ValueQuestion and AN.ValueQuestion(head)
	if not q then
		q = PF.Question(head)
		if not q or (ns.PerFieldTaken and ns.PerFieldTaken(head)) then return nil end
	end
	local list, step = q.line:match("^(.-)%s*(|.*)$")
	return (list .. (#tail > 0 and (" " .. table.concat(tail, " ")) or "") .. " " .. step)
end

function PF.ToAdvanced(q) return q.line end
