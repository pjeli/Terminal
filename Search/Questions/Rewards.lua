local ns = select(2, ...)
local L = ns.L

-- Quests by what they reward, and the quests that lead up to one.
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

local index -- { { ln = lowercase name, m = it without apostrophes, name, id, quests = { quest ids } } }
local building = false

--- The items some quest rewards (Questie's): nil while they're read (in the background, a few ms a frame: Build) or
--- without Questie's data.
function QR.Index()
	if not index and not building then QR.Build() end
	return index
end
--- Is the index being read now (a slice at a time)?
function QR.Building() return building end

--- Reads them, a slice at a time (every Questie item once: 15-20 thousand on WoW Forever). Started once Questie's
--- quests are indexed, or when first asked.
function QR.Build()
	if index or building then return end
	local db = DB()
	local I = ns.Integrations
	if not (db and db.ItemIds and I and I.RunSliced) then return end
	local ids = db.ItemIds() or {}
	if #ids == 0 then return end -- (not there yet: asked again next time)
	building = true
	local out = {}
	I.RunSliced("rewards: items quests reward", #ids, function(i)
		local id = ids[i]
		local ok, qs = pcall(db.QueryItemSingle, id, "questRewards")
		if ok and type(qs) == "table" and next(qs) ~= nil then
			local quests = {}
			for _, q in pairs(qs) do if type(q) == "number" then quests[#quests + 1] = q end end
			table.sort(quests)
			local okN, name = pcall(db.QueryItemSingle, id, "name")
			name = okN and Str(name) or nil
			if name and #quests > 0 then
				local ln = Lower(name)
				out[#out + 1] = { ln = ln, m = (ln:gsub("'", "")), name = name, id = id, quests = quests }
			end
		end
	end, function()
		index, building = out, false
		QR.lastKey, QR.lastItems = nil, nil
		QR.ForgetClose() -- (the close spellings found were the old index's entries: 0.50.7, a review test)
	end)
end
function QR.Forget() index, building, QR.lastKey, QR.lastItems, QR.lastPool = nil, false, nil, nil, nil QR.ForgetClose(); QR.byQuest = nil end -- (tests: Questie's data read again)

--- What a quest rewards: { index entries } (name, id), or nil (none, or not read yet). Made from the index once.
function QR.RewardsOf(qid)
	local idx = QR.Index()
	if not idx then return nil end
	local by = QR.byQuest
	if not by or by.idx ~= idx then
		by = { idx = idx, map = {} }
		for _, it in ipairs(idx) do
			for _, q in ipairs(it.quests) do
				local t = by.map[q]
				if not t then t = {}; by.map[q] = t end
				t[#t + 1] = it
			end
		end
		QR.byQuest = by
	end
	return by.map[qid]
end

-- a word typed: at the start of one of the name's words ("sab" is in Outlaw Sabre, "low" isn't in Glowing Wand). The
-- word's pattern, made once per search
local function StartPattern(tk) return "%f[%w\128-\255]" .. tk:gsub("%p", "%%%0") end

QR.CLOSE_LEN = 5 -- (a word this long or longer may be a close spelling of the name's: "saber", Sabre)
local closeSeen, closeOrder = {}, {} -- word -> { [entry] = edits }: the last few words' close spellings, per word
function QR.ForgetClose() closeSeen, closeOrder = {}, {} end
local function CloseOf(tk, idx)
	local c = closeSeen[tk]
	if c then return c end
	c = {}
	local S = ns.Score
	local limit = S and S.NearLimit(#tk, tk)
	if limit then
		for _, it in ipairs(idx) do
			local d = S.NearWord(tk, it.m, limit)
			if d then c[it] = d end
		end
	end
	closeSeen[tk] = c
	closeOrder[#closeOrder + 1] = tk
	if #closeOrder > 8 then closeSeen[table.remove(closeOrder, 1)] = nil end
	return c
end

local function Shorter(a, b)
	if #a.ln ~= #b.ln then return #a.ln < #b.ln end
	return a.id < b.id
end

--- The items some quest rewards whose names have these (lowercase, apostrophes left out) words: the exact name, else
--- every word at the start of one of the name's words, else (two words or more) every word there or a close spelling of
--- one ("outlaw saber": Outlaw Sabre; only words of CLOSE_LEN letters or more). `oneClose`: one word may be a close
--- spelling too (reward:saber, typed on purpose). `typing`: the last word is still being typed (no space after it): no
--- close spelling of it is looked for (every new letter was a pass over the whole index, 50-150 ms). { entry }, best
--- first; {} when none. The last answer is kept (asked again as the search refreshes, and by Alt+`).
function QR.Items(tokens, oneClose, typing)
	local idx = QR.Index()
	if not idx then
		-- (still being read, a slice at a time: the search asks again once it's in)
		if building and #tokens > 0 then
			if ns.Filters then ns.Filters.loading = true end
			if ns.Pipes then ns.Pipes.loading = true end
		end
		return {}
	end
	if #tokens == 0 then return {} end
	local whole = table.concat(tokens, " ")
	local key = whole .. (oneClose and "\1" or "") .. (typing and "\2" or "")
	if QR.lastKey == key then return QR.lastItems end
	local exact, typed = {}, {}
	local pats = {}
	for k, tk in ipairs(tokens) do pats[k] = StartPattern(tk) end
	-- (a word typed on, or one more: what has them is among what had the words before)
	local pool = idx
	local last = QR.lastPool
	if last and last.idx == idx and QR.Grew(last.tokens, tokens) then pool = last.items end
	local passed = {}
	for _, it in ipairs(pool) do
		if it.m == whole then
			exact[#exact + 1] = it
			passed[#passed + 1] = it
		else
			local all = true
			for _, pat in ipairs(pats) do
				if not it.m:find(pat) then all = false break end
			end
			if all then typed[#typed + 1] = it; passed[#passed + 1] = it end
		end
	end
	local kept = {}
	for k, tk in ipairs(tokens) do kept[k] = tk end
	QR.lastPool = { idx = idx, tokens = kept, items = passed }
	local out = exact
	if #out == 0 and #typed > 0 then table.sort(typed, Shorter) out = typed end
	if #out == 0 and (#tokens >= 2 or oneClose) then
		local close, sets = {}, {}
		for k, tk in ipairs(tokens) do
			if #tk >= QR.CLOSE_LEN and not (typing and k == #tokens) then sets[k] = CloseOf(tk, idx) end
		end
		if next(sets) then
			for _, it in ipairs(idx) do
				local edits = 0
				for k in ipairs(tokens) do
					local d = (it.m:find(pats[k]) and 0) or (sets[k] and sets[k][it])
					if not d then edits = nil break end
					edits = edits + d
				end
				if edits and edits > 0 then close[#close + 1] = { it = it, d = edits } end
			end
			table.sort(close, function(a, b)
				if a.d ~= b.d then return a.d < b.d end
				return Shorter(a.it, b.it)
			end)
			for _, c in ipairs(close) do out[#out + 1] = c.it end
		end
	end
	QR.lastKey, QR.lastItems = key, out
	return out
end

--- Are `now`'s words `before`'s typed on: each of before's the start of now's there, maybe more words after?
function QR.Grew(before, now)
	if type(before) ~= "table" or #now < #before then return false end
	for k, w in ipairs(before) do
		if now[k]:sub(1, #w) ~= w then return false end
	end
	return true
end

QR.MAX_ITEMS = 10 -- (items whose quests are listed: "sword" would name hundreds)

local function ForYou(db, id) return QR.ForYouIn(db, id) end -- (QuestFacts.lua's: your race, class and side)

--- The quest ids rewarding those items (each once, in the items' order): those your race and class can take, or every
--- one when none fits; and each one's item.
local function QuestsOf(items)
	local out, seen = {}, {}
	for k, it in ipairs(items) do
		if k > QR.MAX_ITEMS then break end
		for _, q in ipairs(it.quests) do
			if not seen[q] then seen[q] = it; out[#out + 1] = q end
		end
	end
	local db = DB()
	local mine = {}
	for _, q in ipairs(out) do if not db or ForYou(db, q) then mine[#mine + 1] = q end end
	if #mine > 0 and #mine < #out then
		local keep = {}
		for _, q in ipairs(mine) do keep[q] = seen[q] end
		return mine, keep
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
	if e.kind == "attune" then return e.qid end -- (an Attune step that's a quest: Attune.lua)
end
QR.QuestIdOf = QuestIdOf

local Fk = ns.Filters and ns.Filters._
if Fk and Fk.KEYS then
	-- reward:<item>: the quests whose reward is that item (its name, part of it, or a close spelling; _ for a space)
	Fk.KEYS.reward = function(v)
		if v == "" then return nil end
		-- reward:bag, reward:quiver, reward:ammo_pouch: any bag (quiver, ammo pouch) as a reward
		local kind = QR.KIND_WORDS[(v:gsub("_", " "))]
		if kind then
			local set
			return function(e)
				local id = QuestIdOf(e)
				if not id then return false end
				-- (the reward index still being read: said, so the search is made again once it's in)
				if not QR.Index() and QR.Building() and ns.Filters then ns.Filters.loading = true end
				if not set then set = QR.KindQuests(kind) end
				return set[id] ~= nil
			end
		end
		local tokens = {}
		-- (apostrophes left out, as the names are: "agamaggan's_clutch")
		for w in v:gsub("_", " "):gsub("'", ""):gmatch("%S+") do tokens[#tokens + 1] = w end
		local set -- (looked up on the first quest row, then kept for the search)
		return function(e)
			local id = QuestIdOf(e)
			if not id then return false end
			if not set then
				local _, by = QuestsOf(QR.Items(tokens, true))
				set = by
			end
			return set[id] ~= nil
		end
	end
	Fk.KEYS.rewards = Fk.KEYS.reward -- (.filters' line and which lists it judges: Filters/Others.lua, with sells:)
	-- slots:>=10: a bag's slots; a quest's, the bag it rewards
	Fk.KEYS.slots = function(v)
		local r = ns.Filters.Range(v)
		return r and function(e) return r(QR.SlotsOfRow(e)) end
	end
end

-- (a container's item class: bags, quivers, ammo pouches; the game's Enum, else 1 as it has always been)
local CONTAINER = (Enum and Enum.ItemClass and Enum.ItemClass.Container) or 1
--- A row's bag slots: a bag item's own, a quest's rewarded bag's; nil for anything else (a bag's slots are read from its
--- tooltip, so only items the game calls containers are read).
function QR.SlotsOfRow(e)
	if type(e) ~= "table" then return nil end
	if e.kind == "questie" or e.kind == "quests" then return QR.RewardSlots(e) end
	-- (a recipe's, or one to learn's: the bag it makes, Filters' ItemOf; 1.0.80, "bigger bags" left every recipe out)
	local id = tonumber(rawget(e, "itemID"))
	if not id and (e.kind == "recipes" or e.kind == "missing") and ns.Filters and ns.Filters.ItemOf then id = tonumber(ns.Filters.ItemOf(e)) end
	if not id then return nil end
	local inst = C_Item and C_Item.GetItemInfoInstant
	if not inst then return nil end
	local ok, _, _, _, _, _, classID = pcall(inst, id)
	if not ok or classID ~= CONTAINER then return nil end
	return QR.Slots(id)
end

----------------------------------------------------------------------
-- Simple mode: "outlaw sabre quest", "quest for outlaw sabre"
----------------------------------------------------------------------

-- the words a question about a quest's reward is made of, besides the item's name
local QUEST = { quest = true, quests = true }
local FILLER = {}
for w in ([[quest quests reward rewards rewarded rewarding gives give gave for that which what whats where wheres the a an
	is are does do did from get got with by of as to i can me my mine our we you in on at near nearby nearest close closest
	around here there this these those zone zones area level levels low high show list find all any some every open
	available daily weekly has have had which one ones still left new old good best grey gray drop party group share
	shared complete completed done]]):gmatch("%S+") do FILLER[w] = true end

-- is some quest of Questie's called with these words (every one in its name: "blade of the sea quest" is the quest
-- Blade of the Sea, its little words aside)? Then the words are a search
local notCalled -- (the last words no quest is called: typed on, none is either)
local function QuestCalled(words)
	local I = ns.Integrations
	local list = I and I.qdb and I.qdb.list
	if notCalled and notCalled.list == list and QR.Grew(notCalled.words, words) then return false end
	for _, e in ipairs(list or {}) do
		local ln = rawget(e, "_lname") or (type(e.name) == "string" and Lower(e.name)) or ""
		if ln:find("'", 1, true) then ln = ln:gsub("'", "") end -- (once per quest, not per word: 0.50.7, review)
		local all = true
		for _, w in ipairs(words) do
			if not ln:find(w, 1, true) then all = false break end
		end
		if all then return true end
	end
	local copy = {}
	for k, w in ipairs(words) do copy[k] = w end
	notCalled = { list = list, words = copy }
	return false
end

--- The question: { words = the item's words, items = the quest rewards they name, best first }, or nil when the line
--- isn't it (no quest word, no quest reward named, or a quest called that).
function QR.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local quest, words = false, {}
	for w in t:gmatch("%S+") do
		if QUEST[w] then quest = true elseif not FILLER[w] and #w >= 3 then words[#words + 1] = w end
	end
	if not quest or #words == 0 then return nil end
	-- (the last word still being typed: the line's last, no space after it, and not "quest")
	local typing = not text:find("%s$") and t:match("(%S+)%s*$") == words[#words]
	local items = QR.Items(words, nil, typing)
	if #items == 0 or QuestCalled(words) then return nil end -- (the cheaper miss first)
	return { words = words, items = items }
end

-- a quest row as this answer shows it: what it rewards first
local function RewardView(row, it)
	local d = row.detail
	return setmetatable({ detail = L["Rewards %s"]:format(it.name) .. ((d and d ~= "") and (ns.DETAIL_SEP .. d) or ""),
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
		return { ns.NoteRow(L["No quest Questie knows of rewards it"]) }, note
	end
	local simple = ns.Easy and ns.Easy.On and ns.Easy.On()
	return rows, note .. ns.DETAIL_SEP .. (simple and L["quest chain for <quest>: the quests before it"] or L["<quest> > chain: the quests before it"])
end

-- (QuestUpgrades.lua's and QuestFacts.lua's: read once those files load)
QR._ = { DB = DB, QuestIdOf = QuestIdOf, QuestsOf = QuestsOf, QUEST = QUEST, FILLER = FILLER, ForYou = ForYou }
