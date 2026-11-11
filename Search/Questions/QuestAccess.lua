local ns = select(2, ...)
local L = ns.L

-- Can you take a quest, by QuestieDB's quest fields (QuestieDB/src/meta/questMeta.lua), read through LibQuestieDB's
-- public Quest.Get (Core/QuestieData.lua's QD.DB), never Questie's own QuestieDB.IsDoable. What each field asks, as
-- Questie reads it:
--
--   preQuestSingle (13)        any one of them done
--   preQuestGroup (12)         every one done (read only when there's no preQuestSingle, as Questie does); a positive id:
--                              it, or one of its own exclusiveTo, done; a negative id: that quest done
--   exclusiveTo (16)           none of them done or in your log ("one or the other")
--   requiredMaxLevel (32)      your level at most that
--   nextQuestInChain (22)      that quest not done or in your log (you're past this one)
--   parentQuest (25)           that quest in your log
--   breadcrumbForQuestId (27)  a breadcrumb whose quest is done or in your log leads nowhere
--   breadcrumbs (28)           none of this quest's breadcrumbs in your log (turn it in first)
--   requiredSpell (30)         known (a negative id: not known)
--   requiredMaxRep (20)        your reputation under it
--
-- What's done is the game's (C_QuestLog.IsQuestFlaggedCompleted, GetLogIndexForQuestID), as the rest of Terminal asks.
-- Z.QuestFitter ("where should i quest", the zones' quest counts, "quests near me"), is:cantake ("quests here",
-- sort:cantake) and "quest upgrades" leave out the quests that fail it. "why can't i take <quest>" says each reason;
-- "<quest> > unlocks" ("what does <quest> unlock", "what comes after <quest>") lists the quests it opens up.

local QA = {}
ns.QuestAccess = QA

local Safe, Str, Num, Lower = ns.Safe, ns.Str, ns.Num, ns.Lower
local SEP = ns.DETAIL_SEP

local function DB()
	local QD = ns.QuestieData
	local db = QD and QD.Ready() and QD.DB()
	return db and db.QueryQuestSingle and db or nil
end

-- a field as a list of quest ids (nil: none); one as a number (nil: none, or 0)
local function IdList(db, id, field)
	local v = Safe(db.QueryQuestSingle, id, field)
	if type(v) == "number" then return v ~= 0 and { v } or nil end
	if type(v) ~= "table" then return nil end
	local out
	for _, x in pairs(v) do
		if type(x) == "number" and x ~= 0 then out = out or {}; out[#out + 1] = x end
	end
	if out then table.sort(out) end
	return out
end
local function IdOne(db, id, field)
	local v = tonumber((Safe(db.QueryQuestSingle, id, field)))
	return v and v ~= 0 and v or nil
end
local function Pair(t) if type(t) == "table" and tonumber(t[1]) and tonumber(t[2]) then return { tonumber(t[1]), tonumber(t[2]) } end end

----------------------------------------------------------------------
-- A quest's fields, read once (they don't change in a session)
----------------------------------------------------------------------

local fieldsOf, fieldsCount = {}, 0
--- { single, group, excl, crumbs = { ids }, maxLevel, nextQ, parent, crumbFor, spell = number, maxRep = { factionId,
--- value } }: what QuestieDB says stands in the way of taking it, or nil when nothing does (or Questie isn't ready).
function QA.Fields(id)
	if type(id) ~= "number" then return nil end
	local kept = fieldsOf[id]
	if kept ~= nil then return kept or nil end
	local okDB, db = pcall(DB)
	db = okDB and db or nil
	if not db then return nil end -- (not ready: nothing kept, asked again)
	local r = {
		single = IdList(db, id, "preQuestSingle"), group = IdList(db, id, "preQuestGroup"),
		excl = IdList(db, id, "exclusiveTo"), crumbs = IdList(db, id, "breadcrumbs"),
		maxLevel = IdOne(db, id, "requiredMaxLevel"), nextQ = IdOne(db, id, "nextQuestInChain"),
		parent = IdOne(db, id, "parentQuest"), crumbFor = IdOne(db, id, "breadcrumbForQuestId"),
		spell = IdOne(db, id, "requiredSpell"), maxRep = Pair(Safe(db.QueryQuestSingle, id, "requiredMaxRep")),
	}
	if next(r) == nil then r = false end -- (most quests: one false kept, not a table)
	if fieldsCount > 20000 then fieldsOf, fieldsCount = {}, 0 end
	fieldsOf[id], fieldsCount = r, fieldsCount + 1
	return r or nil
end
function QA.Forget() fieldsOf, fieldsCount = {}, 0; QA.rev, QA.revOf = nil, nil end -- (tests: Questie's data read again)

----------------------------------------------------------------------
-- What you've done: the game's, asked once per quest per pass (`m`: one list's quests share it)
----------------------------------------------------------------------

local function Memo(m)
	m = m or {}
	if not m.qaDone then m.qaDone, m.qaLog, m.qaSpell = {}, {}, {} end
	return m
end
local function Done(id, m)
	local v = m.qaDone[id]
	if v == nil then
		local Q = C_QuestLog
		local f = (Q and Q.IsQuestFlaggedCompleted) or rawget(_G, "IsQuestFlaggedCompleted")
		v = f ~= nil and Safe(f, id) == true
		m.qaDone[id] = v
	end
	return v
end
local function InLog(id, m)
	local v = m.qaLog[id]
	if v == nil then
		local f = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
		v = f ~= nil and Num(Safe(f, id)) ~= nil
		m.qaLog[id] = v
	end
	return v
end
local function Known(spell, m)
	local v = m.qaSpell[spell]
	if v == nil then
		local CS = ns.ClassSpells
		if CS and CS.Known then v = CS.Known(spell) and true or false
		else
			local f = rawget(_G, "IsPlayerSpell")
			v = f ~= nil and Safe(f, spell) == true
		end
		m.qaSpell[spell] = v
	end
	return v
end
local function MyLevel()
	if ns.Asker then return ns.Asker.level end -- (a !t question: the asker's level, Core/Ask.lua)
	local l = Num(Safe(UnitLevel, "player"))
	return l and l > 0 and l or nil
end

-- of a list of quests, those your race, class and side can take (all of them when none is)
local function Yours(ids)
	local QR = ns.QuestRewards
	if not (QR and QR.ForYou) then return ids end
	local out = {}
	for _, x in ipairs(ids) do if QR.ForYou(x) then out[#out + 1] = x end end
	return #out > 0 and out or ids
end

--- The fields' test: true when nothing in them stops you. `out`: a list each reason is added to ({ what, ids, n }),
--- every one; without it, false at the first.
local function Check(id, level, m, out)
	local r = QA.Fields(id)
	if not r then return true end
	local blocked = false
	-- (true: stop now, the first reason is enough)
	local function Block(what, ids, n)
		blocked = true
		if not out then return true end
		out[#out + 1] = { what = what, ids = ids, n = n }
		return false
	end
	if r.maxLevel and level and level > r.maxLevel and Block("maxlevel", nil, r.maxLevel) then return false end
	-- (someone else's !t question: what you've done isn't what they have)
	if ns.Asker then return not blocked end
	if r.single then
		local any = false
		for _, p in ipairs(r.single) do if Done(math.abs(p), m) then any = true break end end
		if not any and Block("pre", Yours(r.single)) then return false end
	elseif r.group then
		for _, p in ipairs(r.group) do
			local missing
			if p < 0 then missing = not Done(-p, m)
			elseif not Done(p, m) then
				missing = true
				local pf = QA.Fields(p)
				for _, x in ipairs(pf and pf.excl or {}) do if Done(x, m) then missing = false break end end
			end
			if missing and Block("pre", { math.abs(p) }) then return false end
		end
	end
	for _, x in ipairs(r.excl or {}) do
		if Done(x, m) then if Block("excl", { x }) then return false end break end
		if InLog(x, m) then if Block("exclLog", { x }) then return false end break end
	end
	if r.nextQ then
		if Done(r.nextQ, m) then if Block("past", { r.nextQ }) then return false end
		elseif InLog(r.nextQ, m) and Block("pastLog", { r.nextQ }) then return false end
	end
	if r.parent and not InLog(r.parent, m) and Block("parent", { r.parent }) then return false end
	if r.crumbFor then
		if Done(r.crumbFor, m) then if Block("crumbDone", { r.crumbFor }) then return false end
		elseif InLog(r.crumbFor, m) and Block("crumbLog", { r.crumbFor }) then return false end
	end
	for _, c in ipairs(r.crumbs or {}) do
		if InLog(c, m) then if Block("crumbIn", { c }) then return false end break end
	end
	if r.spell then
		if r.spell > 0 and not Known(r.spell, m) and Block("spell", nil, r.spell) then return false end
		if r.spell < 0 and Known(-r.spell, m) and Block("nospell", nil, -r.spell) then return false end
	end
	if r.maxRep then
		local QR = ns.QuestRewards
		local mine = QR and QR.MyRep and QR.MyRep(r.maxRep[1])
		-- (not known: not held against it)
		if mine and mine >= r.maxRep[2] and Block("maxrep", nil, r.maxRep) then return false end
	end
	return not blocked
end

--- Can you take it, by QuestieDB's fields (prerequisites, exclusive quests, its level cap, breadcrumbs, spell,
--- reputation cap)? true when nothing there stops you, or Questie can't say. `level`: yours when nil. `memo`: a table
--- kept across one list's quests (the game is asked once per quest done or in your log).
function QA.CanTake(id, level, memo)
	if type(id) ~= "number" then return true end
	-- (most quests have none of these fields: said before a memo or your level is made, 1.3.13, review: is:cantake and
	-- the quest upgrades ask it once a row)
	if not QA.Fields(id) then return true end
	return Check(id, level or MyLevel(), Memo(memo), nil)
end

--- Every reason it stops you: { { what, ids, n } } (empty: none).
function QA.Reasons(id, level, memo)
	local out = {}
	if type(id) == "number" then Check(id, level or MyLevel(), Memo(memo), out) end
	return out
end

local function QuestName(id)
	local db = DB()
	return (db and Str(Safe(db.QueryQuestSingle, id, "name"))) or ("#" .. tostring(id))
end
local function SpellName(id)
	local S = C_Spell
	local n = S and S.GetSpellName and Str(Safe(S.GetSpellName, id))
	if not n and _G.GetSpellInfo then n = Str(Safe(_G.GetSpellInfo, id)) end
	return n or ("#" .. tostring(id))
end

--- A reason in plain words.
function QA.Say(r)
	local w, ids = r.what, r.ids
	local first = ids and ids[1] and QuestName(ids[1])
	if w == "maxlevel" then return L["Only up to level %d"]:format(r.n) end
	-- (any one of several: "Needs A / B first"; a breadcrumb of it in your log: turn that in first, "Needs <it> first")
	if w == "pre" or w == "crumbIn" then
		local names = {}
		for i, x in ipairs(ids) do names[i] = QuestName(x) end
		return L["Needs %s first"]:format(table.concat(names, " / "))
	end
	-- (done or in your log: "took", one text each)
	if w == "excl" or w == "exclLog" then return L["You took %s: it's one or the other"]:format(first) end
	if w == "past" or w == "pastLog" then return L["You took %s, which comes after it"]:format(first) end
	if w == "parent" then return L["Only while %s is in your log"]:format(first) end
	if w == "crumbDone" or w == "crumbLog" then return L["A breadcrumb to %s, which you've taken"]:format(first) end
	if w == "spell" then return L["Needs %s learned"]:format(SpellName(r.n)) end
	if w == "nospell" then return L["Not once you know %s"]:format(SpellName(r.n)) end
	if w == "maxrep" then
		local QR = ns.QuestRewards
		local st = QR and QR.StandingOfValue and QR.StandingOfValue(r.n[2])
		local fname = QR and QR.FactionName and QR.FactionName(r.n[1]) or tostring(r.n[1])
		return L["Only under %s with %s"]:format(ns.StandingName(st) or tostring(r.n[2]), fname)
	end
	return tostring(w)
end

----------------------------------------------------------------------
-- "why can't i take <quest>", "can i take <quest>", "why isn't <quest> offered"
----------------------------------------------------------------------

local WHY = { "^why cant i take (.+)$", "^why cant i get (.+)$", "^why cant i pick up (.+)$", "^why cant i do (.+)$",
	"^why cant i accept (.+)$", "^why cant i start (.+)$", "^why cant i see (.+)$", "^why dont i see (.+)$",
	"^can i take (.+)$", "^can i do (.+)$", "^can i pick up (.+)$", "^can i accept (.+)$", "^can i start (.+)$",
	"^why isnt (.+) offered$", "^why isnt (.+) available$", "^why is (.+) not offered$", "^why is (.+) not available$",
	"^why doesnt (.+) show up$", "^why doesnt (.+) show$" }
local ALLOW = { ["not"] = true } -- ("why is <quest> not offered": the question reads "not" itself)
local function Plain(s) return (s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")) end

function QA.Question(text)
	-- (someone's !t question: what you've done, your log, race and skills aren't theirs, so "can i take X" isn't
	-- answered for them: 1.3.13, review)
	if ns.Asker then return nil end
	local t = ns.QuestionText(text, ALLOW)
	if not t then return nil end
	t = Plain(t)
	local w = t:match("^(%S+)")
	if w ~= "why" and w ~= "can" then return nil end -- (cheap first: every line asks every question)
	local QP = ns.QuestPeople
	if not (QP and QP.Named) then return nil end
	for _, pat in ipairs(WHY) do
		local rest = t:match(pat)
		if rest then
			rest = rest:gsub(" yet$", ""):gsub(" now$", ""):gsub(" anymore$", ""):gsub(" any more$", "")
			local q = QP.Named(rest)
			if q then return { id = q.id, ids = q.ids, name = q.name } end
		end
	end
	return nil
end

-- a reason as a row: the quest it names (Enter, Shift+Enter and its tooltip are that quest's), its words the reason
local function Through(f) return function(v, ...) local b = rawget(v, "_of") local fn = b and b[f] if fn then return fn(b, ...) end end end
local PASS_ACTIVATE, PASS_SECONDARY, PASS_TIP = Through("activate"), Through("secondary"), Through("tooltip")
local function ReasonRow(text, qid)
	local I = ns.Integrations
	local base = qid and I and I.QuestRow and I.QuestRow(qid)
	if not base then return ns.NoteRow(text) end
	local own = base.detail
	local v = { name = text, _of = base, _pos = ns.UI and ns.UI.NO_POS or nil,
		detail = tostring(base.name) .. ((own and own ~= "") and (SEP .. own) or "") }
	if base.activate then v.activate = PASS_ACTIVATE end
	if base.secondary then v.secondary = PASS_SECONDARY end
	if base.tooltip then v.tooltip = PASS_TIP end
	return setmetatable(v, { __index = base })
end

function QA.Answer(q)
	local title = tostring(q.name)
	local db = DB()
	if not db then return { ns.NoteRow(L["Needs Questie: it knows every quest and where it starts"]) }, title end
	local QR, QP = ns.QuestRewards, ns.QuestPeople
	local m = Memo()
	-- (of a name's quests: yours, then the first not done: a chain's parts and the other side's twin share a name)
	local ids = (QP and QP.Which and QP.Which(q.ids or { q.id })) or q.ids or { q.id }
	local id = ids[1]
	for _, x in ipairs(ids) do if not Done(x, m) then id = x break end end
	local rows = {}
	local function Add(text, qid) rows[#rows + 1] = ReasonRow(text, qid) end
	if Done(id, m) then Add(ns.UpperFirst(L["done"]), id)
	elseif InLog(id, m) then Add(ns.UpperFirst(L["in log"]), id)
	else
		if QR and QR.ForYou and not QR.ForYou(id) then Add(L["Not for your race, class or faction"], id) end
		local level = MyLevel()
		local need = Num(Safe(db.QueryQuestSingle, id, "requiredLevel"))
		if need and level and need > level then Add(L["Requires level %d"]:format(need), id) end
		if QR and QR.RequiresSaid then
			local said, met = QR.RequiresSaid(id)
			for i, s in ipairs(said) do if met[i] == false then Add(s, nil) end end
		end
		for _, r in ipairs(QA.Reasons(id, level, m)) do Add(QA.Say(r), r.ids and r.ids[1] or nil) end
		if #rows == 0 then Add(L["Nothing stops you: you can take it"], id) end
	end
	ns.ScoreInOrder(rows)
	return rows, title
end

----------------------------------------------------------------------
-- What a quest unlocks: the quests whose prerequisites name it (a reverse index made once from Questie's quest list),
-- its nextQuestInChain, its childQuests, the quest it is a breadcrumb to
----------------------------------------------------------------------

local PRE_FIELDS = { "preQuestSingle", "preQuestGroup" }
--- quest id -> { the quests whose preQuestSingle or preQuestGroup name it }, made once per quest list; nil without it.
function QA.Reverse()
	local p = ns.providers.questie
	local list = p and ns:GetEntries(p)
	if type(list) ~= "table" or #list == 0 then return nil end
	if QA.revOf == list then return QA.rev end
	local db = DB()
	if not db then return nil end
	local rev = {}
	for _, e in ipairs(list) do
		local id = rawget(e, "key")
		if type(id) == "number" then
			for _, f in ipairs(PRE_FIELDS) do
				local v = Safe(db.QueryQuestSingle, id, f)
				if type(v) == "table" then
					for _, x in pairs(v) do
						if type(x) == "number" and x ~= 0 then
							x = math.abs(x)
							local t = rev[x]
							if not t then t = {}; rev[x] = t end
							if t[#t] ~= id then t[#t + 1] = id end
						end
					end
				end
			end
		end
	end
	QA.rev, QA.revOf = rev, list
	return rev
end

--- The quests this one opens up: { { id, how } }, the next in its chain first; yours (your race, class, side) when
--- some are.
function QA.Unlocks(id)
	local db = DB()
	if not (db and type(id) == "number") then return {} end
	local out, seen = {}, { [id] = true }
	local function Add(x, how) if x and not seen[x] then seen[x] = true; out[#out + 1] = { id = x, how = how } end end
	local r = QA.Fields(id)
	-- (what it leads to itself: the next in its chain, the quest it is a breadcrumb to, its child quests)
	if r and r.nextQ then Add(r.nextQ, L["next in its chain"]) end
	if r and r.crumbFor then Add(r.crumbFor, L["next in its chain"]) end
	for _, c in ipairs(IdList(db, id, "childQuests") or {}) do Add(c, L["next in its chain"]) end
	local after = {}
	for _, x in ipairs((QA.Reverse() or {})[id] or {}) do
		-- (one of several will do, every one of a group, or it alone: each said "needs it")
		after[#after + 1] = { id = x, how = L["needs it"], lv = tonumber((Safe(db.QueryQuestSingle, x, "questLevel"))) or 0 }
	end
	table.sort(after, function(a, b) if a.lv ~= b.lv then return a.lv < b.lv end return a.id < b.id end)
	for _, a in ipairs(after) do Add(a.id, a.how) end
	local QR = ns.QuestRewards
	if QR and QR.ForYou then
		local mine = {}
		for _, u in ipairs(out) do if QR.ForYou(u.id) then mine[#mine + 1] = u end end
		if #mine > 0 then out = mine end
	end
	return out
end

local function UnlockView(row, how)
	local m = Memo()
	local st = Done(row.qid or rawget(row, "key"), m) and L["done"] or (InLog(row.qid or rawget(row, "key"), m) and L["in log"]) or nil
	local d = row.detail
	local parts = { how }
	if st then parts[#parts + 1] = st end
	if d and d ~= "" then parts[#parts + 1] = d end
	return setmetatable({ detail = table.concat(parts, SEP) }, { __index = row })
end

if ns.RegisterRelation then
	-- "the missing diplomat > unlocks", "what does the missing diplomat unlock", "what comes after the missing diplomat"
	-- (Chains.lua's phrases): the quests it opens up, Questie's
	ns:RegisterRelation("unlocks", {
		aliases = { "unlock", "next", "after", "followups", "leadsto" },
		desc = L["the quests a quest opens up (Questie)"],
		available = function() return ns.providers.questie ~= nil end, addon = "Questie",
		seedKinds = { "questie" },
		applies = function(e) local QR = ns.QuestRewards return QR ~= nil and QR.QuestIdOf(e) ~= nil end,
		run = function(rows)
			local I, QR = ns.Integrations, ns.QuestRewards
			local out, seen = {}, {}
			for _, e in ipairs(rows) do
				local qid = QR.QuestIdOf(e)
				for _, u in ipairs(qid and QA.Unlocks(qid) or {}) do
					local row = not seen[u.id] and I and I.QuestRow and I.QuestRow(u.id)
					if row then seen[u.id] = true; out[#out + 1] = UnlockView(row, u.how) end
				end
			end
			return out
		end,
	})
	if ns.Pipes then ns.Pipes.LABELS.unlocks = "unlocks" end
end
