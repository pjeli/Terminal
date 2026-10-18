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

local index -- { { ln = lowercase name, m = it without apostrophes, name, id, quests = { quest ids } } }
local building = false

--- The items some quest rewards (Questie's): nil while they're read (in the background, a few ms a frame: Build) or
--- without Questie's data.
function QR.Index()
	if not index and not building then QR.Build() end
	return index
end

--- Reads them, a slice at a time (every Questie item once: 15-20 thousand on WoW Forever; review, 0.49.17: read at once
--- in the first keystroke that asked, a hitch). Started once Questie's quests are indexed, or when first asked.
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
function QR.Forget() index, building, QR.lastKey, QR.lastItems = nil, false, nil, nil QR.ForgetClose(); QR.byQuest = nil end -- (tests: Questie's data read again)

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
-- word's pattern, made once per search (0.50.7, review: made again for every item of the index, per word)
local function StartPattern(tk) return "%f[%w\128-\255]" .. tk:gsub("%p", "%%%0") end

QR.CLOSE_LEN = 5 -- (a word this long or longer may be a close spelling of the name's: "saber", Sabre)
local closeSeen, closeOrder = {}, {} -- word -> { [entry] = edits }: the last few words' close spellings, per word
function QR.ForgetClose() closeSeen, closeOrder = {}, {} end
local function CloseOf(tk, idx)
	local c = closeSeen[tk]
	if c then return c end
	c = {}
	local S = ns.Score
	local limit = S and S.NearLimit(#tk)
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
--- close spelling of it is looked for (every new letter was a pass over the whole index, 50-150 ms; review, 0.57.7).
--- { entry }, best first; {} when none. The last answer is kept (asked again as the search refreshes, and by Alt+`).
function QR.Items(tokens, oneClose, typing)
	local idx = QR.Index()
	if not idx then
		-- (still being read, a slice at a time: the search asks again once it's in; 0.50.7, review: nothing was found and
		-- nothing asked again, a chain's empty answer kept)
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
	for _, it in ipairs(idx) do
		if it.m == whole then
			exact[#exact + 1] = it
		else
			local all = true
			for _, pat in ipairs(pats) do
				if not it.m:find(pat) then all = false break end
			end
			if all then typed[#typed + 1] = it end
		end
	end
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

QR.MAX_ITEMS = 10 -- (items whose quests are listed: "sword" would name hundreds)

local ForYou -- (below)

--- The quest ids rewarding those items (each once, in the items' order): those your race and class can take, or every
--- one when none fits (review, 0.49.17: the Horde's quest, and its chain, were listed to a human); and each one's item.
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
		local tokens = {}
		-- (apostrophes left out, as the names are: "agamaggan's_clutch"; 0.50.7, review)
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
end

----------------------------------------------------------------------
-- Simple mode: "outlaw sabre quest", "quest for outlaw sabre"
----------------------------------------------------------------------

-- the words a question about a quest's reward is made of, besides the item's name
-- (review, 0.49.17: "quests near me" was the quests rewarding a Bear Shawl, "quests in my zone" a Bone Ring: the little
-- words of a question about quests aren't an item's; words under 3 letters never are)
local QUEST = { quest = true, quests = true }
local FILLER = {}
for w in ([[quest quests reward rewards rewarded rewarding gives give gave for that which what whats where wheres the a an
	is are does do did from get got with by of as to i can me my mine our we you in on at near nearby nearest close closest
	around here there this these those zone zones area level levels low high show list find all any some every open
	available daily weekly has have had which one ones still left new old good best grey gray drop party group share
	shared complete completed done]]):gmatch("%S+") do FILLER[w] = true end

-- is some quest of Questie's called with these words (every one in its name: "blade of the sea quest" is the quest
-- Blade of the Sea, its little words aside)? Then the words are a search
local function QuestCalled(words)
	local I = ns.Integrations
	local list = I and I.qdb and I.qdb.list
	for _, e in ipairs(list or {}) do
		local ln = rawget(e, "_lname") or (type(e.name) == "string" and Lower(e.name)) or ""
		if ln:find("'", 1, true) then ln = ln:gsub("'", "") end -- (once per quest, not per word: 0.50.7, review)
		local all = true
		for _, w in ipairs(words) do
			if not ln:find(w, 1, true) then all = false break end
		end
		if all then return true end
	end
	return false
end

--- The question: { words = the item's words, items = the quest rewards they name, best first }, or nil when the line
--- isn't it (no quest word, no quest reward named, or a quest called that).
function QR.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t -- ("what's", as the other questions read it)
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

----------------------------------------------------------------------
-- Upgrades from quests (0.51.15, the player's ask): "quest upgrades", "upgrade quests", "quests with upgrades": the
-- quests near your level you can still take whose reward is an upgrade for you (is:upgrade on each reward), the
-- biggest first, each saying what it rewards and how far its giver is (with the arrow when it's selected).
----------------------------------------------------------------------

local UPG = { upgrade = true, upgrades = true }
QR.NEAR_BELOW, QR.NEAR_ABOVE = 6, 3 -- (quest levels taken: this far below yours, and above)
QR.UPGRADE_ASK = 60 -- (reward items asked of the server per answer; the answer is read again once they're in)

--- "quest upgrades" and the like (a quest word, an upgrade word, nothing else but little words): true.
function QR.UpgradeQuestion(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local quest, upg = false, false
	for w in t:gmatch("%S+") do
		if QUEST[w] then quest = true
		elseif UPG[w] then upg = true
		elseif not FILLER[w] then return nil end
	end
	return quest and upg or nil
end

local NoneRow = ns.NoteRow

--- The answer: the quests' rows, best first, and the footer's note.
function QR.UpgradeAnswer()
	local note = L["Quests whose reward is an upgrade for you"]
	local db = DB()
	local F = ns.Filters
	if not (db and F and F.GearFit) then return { NoneRow(L["Needs Questie: it knows what every quest rewards"]) }, note end
	local idx = QR.Index()
	if not idx then
		if building then F.loading = true end -- (read again once the rewards are in: RetryWhenLoaded)
		return { NoneRow(L["Reading what Questie's quests reward: a moment"]) }, note
	end
	QR.RewardsOf(0) -- (the quests' rewards made, once)
	local me = UnitLevel and UnitLevel("player")
	me = type(me) == "number" and me > 0 and me or nil
	local fit = F.GearFit()
	local I = ns.Integrations
	local cached = C_Item and C_Item.IsItemDataCachedByID
	local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
	local asked, found = 0, {}
	for qid, items in pairs(QR.byQuest.map) do
		local ok = not (done and Safe(done, qid))
		if ok and me then
			local lvl = ns.Num(Safe(db.QueryQuestSingle, qid, "questLevel"))
			local need = ns.Num(Safe(db.QueryQuestSingle, qid, "requiredLevel"))
			if need and need > me then ok = false
			elseif lvl and lvl > 0 and (lvl < me - QR.NEAR_BELOW or lvl > me + QR.NEAR_ABOVE) then ok = false end
		end
		if ok then ok = ForYou(db, qid) end
		if ok then
			-- (its rewards the game hasn't sent: asked for, a few, and the answer read again once they're in)
			for _, it in ipairs(items) do
				if cached and Safe(cached, it.id) == false and not (F.Known and F.Known(it.id)) and asked < QR.UPGRADE_ASK then
					asked = asked + 1
					if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, it.id) end
				end
			end
			local row = I and I.QuestRow and I.QuestRow(qid)
			if row and fit(row) then found[#found + 1] = { row = row, g = F.GainOf(row) } end
		end
	end
	if asked > 0 then F.loading = true end
	table.sort(found, function(a, b)
		if a.g.gain ~= b.g.gain then return a.g.gain > b.g.gain end
		return tostring(a.row.name) < tostring(b.row.name)
	end)
	local here = I and I.Here and I.Here()
	local rows = {}
	for i, f in ipairs(found) do
		local row = f.row
		local rest = L["Rewards %s"]:format(f.g.item or "?")
		local v = { detail = rest, _score = 1e6 - i }
		local npcID = I.QuestGiver and I.QuestGiver(row.qid or rawget(row, "key"))
		local d, w
		if type(npcID) == "number" and here and I.NpcDistance then d, w = I.NpcDistance(npcID, here) end
		-- (a giver in a dungeon: its entrance, the row saying which dungeon)
		local inside = type(npcID) == "number" and I.NpcDungeon and I.NpcDungeon(npcID)
		if inside then
			rest = rest .. ns.DETAIL_SEP .. L["giver in %s"]:format(inside)
			v.detail = rest
		end
		if d and w then
			v.detail = ns.NearDetail(d, rest)
			v._dist, v.wcont, v.wx, v.wy, v.nearRest = d, w.cont, w.x, w.y, rest
		end
		v = setmetatable(v, { __index = row })
		F.SetGain(v, f.g)
		rows[#rows + 1] = v
	end
	if #rows == 0 then
		return { NoneRow(asked > 0 and L["None yet: the rewards' details are still coming"] or L["No quest near your level rewards an upgrade for you"]) }, note
	end
	return rows, note
end

--- Alt+`: the same in Advanced mode.
-- (as said: the quests near your level, not done, for your race and class; "@questie is:upgrade" had none of that; 0.55.7)
function QR.UpgradeToAdvanced() return nil end

--- Alt+`: the same in Advanced mode ("@questie reward:outlaw_sabre").
function QR.ToAdvanced(q)
	local first = q.items[1]
	-- (the name as reward: matches it: apostrophes left out; 0.50.7, review)
	local name = (#q.items == 1 or first.ln == table.concat(q.words, " ")) and first.m or table.concat(q.words, " ")
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
-- (your race and class, read once: they don't change in a session; review, 0.53.6: asked for every reward quest, thousands
-- a refresh)
local myRace, myClass
function ForYou(db, id)
	if not myRace then myRace = UnitRace and tonumber((select(3, Safe(UnitRace, "player")))) end
	if not myClass then myClass = UnitClass and tonumber((select(3, Safe(UnitClass, "player")))) end
	local race, class = myRace, myClass
	return Has(Safe(db.QueryQuestSingle, id, "requiredRaces"), race) and Has(Safe(db.QueryQuestSingle, id, "requiredClasses"), class)
end

--- Can you take this quest (your race and class, as Questie knows it; true without Questie)?
function QR.ForYou(id)
	local db = DB()
	return not db or ForYou(db, id)
end

--- The quests that lead up to this one, first to last, ending with it: { quest ids }. Every one of preQuestGroup; of
--- preQuestSingle the one you can take (else the first).
function QR.Chain(id)
	local db = DB()
	if not db then return { id } end
	local out, state = {}, {}
	local function Visit(q, depth)
		if state[q] or (depth > 0 and #out >= QR.MAX_CHAIN - 1) or depth > QR.MAX_CHAIN then return end -- (the quest itself last)
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

-- (how it was found says which quest it comes before: two chains sharing a quest each keep it, and their steps whole;
-- review, 0.49.17)
local function ChainView(row, i, n, last, before)
	local d = row.detail
	local say = last and L["the quest itself"] or L["step %d of %d"]:format(i, n)
	return setmetatable({ detail = say .. ((d and d ~= "") and (ns.DETAIL_SEP .. d) or ""), pipeHow = L["before %s"]:format(before) },
		{ __index = row })
end

if ns.RegisterRelation then
	ns:RegisterRelation("chain", {
		aliases = { "questchain", "prereqs", "prereq", "prequests", "before", "leadup" },
		desc = L["the quests that lead up to a quest, first to last (Questie)"],
		available = function() return ns.providers.questie ~= nil end, addon = "Questie",
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
					local root = I and I.QuestRow and I.QuestRow(chain[#chain])
					local before = root and tostring(root.name) or tostring(e.name)
					for i, id in ipairs(chain) do
						local row = I and I.QuestRow and I.QuestRow(id)
						if row then out[#out + 1] = ChainView(row, i, #chain - 1, i == #chain, before) end
					end
				end
			end
			return out
		end,
	})
end
