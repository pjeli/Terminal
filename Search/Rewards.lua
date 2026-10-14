local ns = select(2, ...)
local L = ns.L

-- Quests by what they reward, and the quests that lead up to one (0.49.16, the player's ask: "outlaw saber quest" listed
-- the Baron Aquanis quest, not the one whose reward is the Outlaw Sabre).
--
-- - Simple mode: "outlaw sabre quest", "quest for outlaw sabre", "which quest rewards outlaw sabre": the quests whose
--   reward is that item (a close spelling counts: saber, sabre). Only when the words name a quest reward and no quest is
--   called that ("hogger quest" stays a search).
-- - Advanced mode: @questie reward:outlaw_sabre (Alt+` writes it); the item's name, part of it or a close spelling.
-- - Chains: <quest> > chain lists the quests that lead up to it, first to last, the quest itself at the end; Simple
--   mode: "quest chain for the missing diplomat", "quest chain for outlaw sabre" (the chain of the quest rewarding it).
--
-- What rewards what is Questie's: each item lists the quests rewarding it (its "questRewards"), read once per session
-- into a list of the items some quest rewards (a cold read of every item, as sells: does: tens of ms, timed in .debug).
-- What leads up to a quest is Questie's too: preQuestGroup (every one of them) and preQuestSingle (any one: the one
-- your race and class can take).

local QR = {}
ns.QuestRewards = QR

local Safe, Lower, Str = ns.Safe, ns.Lower, ns.Str

local function DB()
	local QD = ns.QuestieData
	local db = QD and QD.Ready() and QD.DB()
	return db and db.QueryItemSingle and db.QueryQuestSingle and db or nil
end

----------------------------------------------------------------------
-- The items quests reward
----------------------------------------------------------------------

local index -- { { ln = lowercase name, name, id, quests = { quest ids } } }: the items some quest rewards

--- The items some quest rewards (Questie's), read the first time asked; nil without Questie's data.
function QR.Index()
	if index then return index end
	local db = DB()
	if not (db and db.ItemIds) then return nil end
	local started = _G.debugprofilestop and _G.debugprofilestop()
	local out = {}
	for _, id in ipairs(db.ItemIds() or {}) do
		local ok, qs = pcall(db.QueryItemSingle, id, "questRewards")
		if ok and type(qs) == "table" and next(qs) ~= nil then
			local quests = {}
			for _, q in pairs(qs) do if type(q) == "number" then quests[#quests + 1] = q end end
			table.sort(quests)
			local okN, name = pcall(db.QueryItemSingle, id, "name")
			name = okN and Str(name) or nil
			if name and #quests > 0 then out[#out + 1] = { ln = Lower(name), name = name, id = id, quests = quests } end
		end
	end
	index = out
	ns:Trace(("rewards: %d Questie items some quest rewards%s"):format(#out,
		started and (" in %.0f ms"):format(_G.debugprofilestop() - started) or ""))
	return index
end
function QR.Forget() index = nil end -- (tests; Questie's data read again)

-- does the name have this word as typed, or within a close spelling of one of its words ("saber": Sabre)?
local function WordIn(tk, ln)
	if ln:find(tk, 1, true) then return 0 end
	local S = ns.Score
	local limit = S and S.NearLimit(#tk)
	return limit and S.NearWord(tk, ln, limit) or nil
end

--- The items some quest rewards whose names have these (lowercase) words: the exact name, else every word in the name,
--- else every word within a close spelling ("outlaw saber": Outlaw Sabre). { entry }, best first; {} when none.
function QR.Items(tokens)
	local idx = QR.Index()
	if not idx or #tokens == 0 then return {} end
	local whole = table.concat(tokens, " ")
	local exact, typed, close = {}, {}, {}
	for _, it in ipairs(idx) do
		if it.ln == whole then
			exact[#exact + 1] = it
		else
			local edits = 0
			for _, tk in ipairs(tokens) do
				local d = WordIn(tk, it.ln)
				if not d then edits = nil break end
				edits = edits + d
			end
			if edits == 0 then typed[#typed + 1] = it
			elseif edits then close[#close + 1] = { it = it, d = edits } end
		end
	end
	if #exact > 0 then return exact end
	local function Shorter(a, b)
		if #a.ln ~= #b.ln then return #a.ln < #b.ln end
		return a.id < b.id
	end
	if #typed > 0 then table.sort(typed, Shorter) return typed end
	table.sort(close, function(a, b)
		if a.d ~= b.d then return a.d < b.d end
		return Shorter(a.it, b.it)
	end)
	local out = {}
	for _, c in ipairs(close) do out[#out + 1] = c.it end
	return out
end

QR.MAX_ITEMS = 10 -- (items whose quests are listed: "sword" would name hundreds)

--- The quest ids rewarding those items (each once, in the items' order).
local function QuestsOf(items)
	local out, seen = {}, {}
	for k, it in ipairs(items) do
		if k > QR.MAX_ITEMS then break end
		for _, q in ipairs(it.quests) do
			if not seen[q] then seen[q] = it; out[#out + 1] = q end
		end
	end
	return out, seen
end

----------------------------------------------------------------------
-- Advanced: reward:<item>
----------------------------------------------------------------------

-- a quest row's id: Questie's (its key), the quest log's (questID)
local function QuestIdOf(e)
	if type(e) ~= "table" then return nil end
	if e.kind == "questie" then return e.qid or rawget(e, "key") end
	if e.kind == "quests" then return e.questID end
end
QR.QuestIdOf = QuestIdOf

local Fk = ns.Filters and ns.Filters._
if Fk and Fk.KEYS then
	-- reward:<item>: the quests whose reward is that item (its name, part of it, or a close spelling; _ for a space)
	Fk.KEYS.reward = function(v)
		if v == "" then return nil end
		local tokens = {}
		for w in v:gsub("_", " "):gmatch("%S+") do tokens[#tokens + 1] = w end
		local set -- (looked up on the first quest row, then kept for the search)
		return function(e)
			local id = QuestIdOf(e)
			if not id then return false end
			if not set then
				local _, by = QuestsOf(QR.Items(tokens))
				set = by
			end
			return set[id] ~= nil
		end
	end
	Fk.KEYS.rewards = Fk.KEYS.reward
	local F = ns.Filters
	if F.APPLIES then F.APPLIES.reward = { ["*"] = { "questie", "quests" } } end
	if F.HELP then
		table.insert(F.HELP, 12, { "reward:outlaw_sabre", L["@questie, @quest: the quests whose reward is that item (its name, part of it, or a close spelling)"] })
	end
end

----------------------------------------------------------------------
-- Simple mode: "outlaw sabre quest", "quest for outlaw sabre"
----------------------------------------------------------------------

-- the words a question about a quest's reward is made of, besides the item's name
local QUEST = { quest = true, quests = true }
local FILLER = {}
for w in ([[quest quests reward rewards rewarded rewarding gives give gave for that which what the a an is does do from
	get got with by of as to i can me my]]):gmatch("%S+") do FILLER[w] = true end

-- is some quest of Questie's called this (or does its name have these words as typed)? Then the words are a search
local function QuestCalled(whole)
	local I = ns.Integrations
	local list = I and I.qdb and I.qdb.list
	for _, e in ipairs(list or {}) do
		local ln = rawget(e, "_lname") or (type(e.name) == "string" and Lower(e.name)) or ""
		if ln:find(whole, 1, true) then return true end
	end
	return false
end

--- The question: { words = the item's words, items = the quest rewards they name, best first }, or nil when the line
--- isn't it (no quest word, no quest reward named, or a quest called that).
function QR.Question(text)
	if type(text) ~= "string" or text:find("[@:>|]") or text:find("^%s*[%./!%-]") then return nil end
	local t = Lower(text):gsub("[%?%!%.,;\"]", " ")
	local quest, words = false, {}
	for w in t:gmatch("%S+") do
		if QUEST[w] then quest = true elseif not FILLER[w] then words[#words + 1] = w end
	end
	if not quest or #words == 0 or #table.concat(words) < 3 then return nil end
	local items = QR.Items(words)
	if #items == 0 or QuestCalled(table.concat(words, " ")) then return nil end -- (the cheaper miss first)
	return { words = words, items = items }
end

-- a quest row as this answer shows it: what it rewards first
local function RewardView(row, it)
	local d = row.detail
	return setmetatable({ detail = L["Rewards %s"]:format(it.name) .. ((d and d ~= "") and ("  ·  " .. d) or ""),
		rewardItem = it.id }, { __index = row })
end

--- The answer: the quests rewarding the item(s) the words name, and the footer's note.
function QR.Answer(q)
	local I = ns.Integrations
	local ids, by = QuestsOf(q.items)
	local rows = {}
	for _, id in ipairs(ids) do
		local row = I and I.QuestRow and I.QuestRow(id)
		if row then
			local v = RewardView(row, by[id])
			v._score = 1e6 - #rows
			rows[#rows + 1] = v
		end
	end
	local first = q.items[1]
	local named = (#q.items == 1 or first.ln == table.concat(q.words, " ")) and first.name or nil
	local note = named and L["Quests that reward %s"]:format(named) or L["Quests that reward \"%s\""]:format(table.concat(q.words, " "))
	if #rows == 0 then
		return { { name = L["No quest Questie knows of rewards it"], raw = true, icon = false, noActivate = true, kindLabel = "",
			detail = "" } }, note
	end
	local simple = ns.Easy and ns.Easy.On and ns.Easy.On()
	return rows, note .. "  ·  " .. (simple and L["quest chain for <quest>: the quests before it"] or L["<quest> > chain: the quests before it"])
end

--- Alt+`: the same in Advanced mode ("@questie reward:outlaw_sabre").
function QR.ToAdvanced(q)
	local first = q.items[1]
	local name = (#q.items == 1 or first.ln == table.concat(q.words, " ")) and first.ln or table.concat(q.words, " ")
	return "@questie reward:" .. name:gsub(" ", "_") .. " "
end

----------------------------------------------------------------------
-- The chain: the quests that lead up to one
----------------------------------------------------------------------

QR.MAX_CHAIN = 40 -- (quests in one chain at most)

-- a quest's field as a list of quest ids
local function Ids(db, id, field)
	local v = Safe(db.QueryQuestSingle, id, field)
	local out = {}
	if type(v) == "table" then
		for _, x in pairs(v) do if type(x) == "number" then out[#out + 1] = x end end
		table.sort(out)
	elseif type(v) == "number" and v > 0 then
		out[1] = v
	end
	return out
end

-- does this bit mask have bit n (1-based) set? (0 or none: everyone)
local function Has(mask, n)
	if type(mask) ~= "number" or mask == 0 or not n then return true end
	return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

-- can you take this quest: your race and class (Questie's requiredRaces / requiredClasses bits)?
local function ForYou(db, id)
	local race = UnitRace and select(3, UnitRace("player"))
	local class = UnitClass and select(3, UnitClass("player"))
	return Has(Safe(db.QueryQuestSingle, id, "requiredRaces"), race) and Has(Safe(db.QueryQuestSingle, id, "requiredClasses"), class)
end

--- The quests that lead up to this one, first to last, ending with it: { quest ids }. Every one of preQuestGroup; of
--- preQuestSingle the one you can take (else the first).
function QR.Chain(id)
	local db = DB()
	if not db then return { id } end
	local out, state = {}, {}
	local function Visit(q, depth)
		if state[q] or #out >= QR.MAX_CHAIN or depth > QR.MAX_CHAIN then return end
		state[q] = "seen" -- (a loop in the data stops here)
		for _, p in ipairs(Ids(db, q, "preQuestGroup")) do Visit(p, depth + 1) end
		local single = Ids(db, q, "preQuestSingle")
		if #single > 0 then
			local pick = single[1]
			for _, p in ipairs(single) do if ForYou(db, p) then pick = p break end end
			Visit(pick, depth + 1)
		end
		out[#out + 1] = q
	end
	Visit(id, 0)
	return out
end

local function ChainView(row, i, n, last)
	local d = row.detail
	local say = last and L["the quest itself"] or L["step %d of %d"]:format(i, n)
	return setmetatable({ detail = say .. ((d and d ~= "") and ("  ·  " .. d) or ""), pipeHow = L["before it"] }, { __index = row })
end

if ns.RegisterRelation then
	ns:RegisterRelation("chain", {
		aliases = { "questchain", "prereqs", "prereq", "prequests", "before", "leadup" },
		desc = L["the quests that lead up to a quest, first to last (Questie)"],
		-- (a chain asked of a name: Questie's quests by that name; else the quests rewarding an item by that name)
		seedKinds = { "questie" },
		seedFallback = function(text)
			local q = QR.Question("quest " .. tostring(text))
			if not q then return nil end
			local I = ns.Integrations
			local rows = {}
			for _, id in ipairs((QuestsOf(q.items))) do
				local row = I and I.QuestRow and I.QuestRow(id)
				if row then rows[#rows + 1] = row end
			end
			return rows
		end,
		seedNone = L["No quest called \"%s\" (or rewarding it) that Questie knows of"],
		applies = function(e) return QuestIdOf(e) ~= nil end,
		run = function(rows)
			local I = ns.Integrations
			local out = {}
			for _, e in ipairs(rows) do
				local chain = QR.Chain(QuestIdOf(e))
				if #chain > 1 then
					for i, id in ipairs(chain) do
						local row = I and I.QuestRow and I.QuestRow(id)
						if row then out[#out + 1] = ChainView(row, i, #chain - 1, i == #chain) end
					end
				end
			end
			return out
		end,
	})
end
