local ns = select(2, ...)
local L = ns.L

-- What QuestieDB says about a quest besides its rewards: the chain that leads up to it (<quest> > chain), whether your
-- race, class and side can take it, the reputation it gives ("quests for <faction> rep"), and what it needs (a skill,
-- a standing, a spell); with their filters (is:foryou, is:cantake). Rewards.lua and QuestUpgrades.lua load just before
-- this (1.4.2: one file until then).

local QR = ns.QuestRewards
local Safe, Lower, Str = ns.Safe, ns.Lower, ns.Str
local Fk = ns.Filters and ns.Filters._
local DB, QuestsOf, QuestIdOf = QR._.DB, QR._.QuestsOf, QR._.QuestIdOf

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

-- can you take this quest: your race and class (Questie's requiredRaces / requiredClasses bits)? (your race and class,
-- read once: they don't change in a session)
local myRace, myClass, myFaction
local factionOk = {} -- quest id -> its givers are your faction's (kept: a character's faction doesn't change)

--- Is a quest given by your side? Many quests name no race at all; their giver says whose they are (Questie's
--- friendlyToFaction: "A", "H", "AH"). One an NPC of yours gives (or any of them), or an object or an item: yes; only
--- the other side's NPCs: no; not known: yes.
local function YourSide(db, id)
	local known = factionOk[id]
	if known ~= nil then return known end
	if not myFaction then
		local g = Str(Safe(UnitFactionGroup, "player"))
		-- (not known yet, early in a login: asked again next time, nothing kept; 0.65.x review)
		if not g then return true end
		myFaction = g == "Alliance" and "A" or g == "Horde" and "H" or false
	end
	local ok = true
	local by = myFaction and db.QueryNPCSingle and Safe(db.QueryQuestSingle, id, "startedBy")
	local npcs = type(by) == "table" and type(by[1]) == "table" and by[1] or nil
	if npcs and #npcs > 0 and not ((type(by[2]) == "table" and by[2][1]) or (type(by[3]) == "table" and by[3][1])) then
		local any, theirs = false, false
		for _, nid in ipairs(npcs) do
			local f = Str(Safe(db.QueryNPCSingle, nid, "friendlyToFaction"))
			if not f or f:find(myFaction, 1, true) then any = true break end
			theirs = true
		end
		ok = any or not theirs
	end
	factionOk[id] = ok
	return ok
end
function QR.ForgetFaction() myRace, myClass, myFaction, factionOk = nil, nil, nil, {} end -- (tests)

local function ForYou(db, id)
	if not myRace then myRace = UnitRace and tonumber((select(3, Safe(UnitRace, "player")))) end
	if not myClass then myClass = UnitClass and tonumber((select(3, Safe(UnitClass, "player")))) end
	local race, class = myRace, myClass
	return Has(Safe(db.QueryQuestSingle, id, "requiredRaces"), race) and Has(Safe(db.QueryQuestSingle, id, "requiredClasses"), class)
		and YourSide(db, id)
end
QR.ForYouIn = ForYou -- (Rewards.lua and QuestUpgrades.lua ask it with the database they hold)

--- Can you take this quest (your race and class, as Questie knows it; true without Questie)?
function QR.ForYou(id)
	local db = DB()
	return not db or ForYou(db, id)
end

--- The quests that lead up to this one, first to last, ending with it: { quest ids }. Every one of preQuestGroup; of
--- preQuestSingle the one you can take (else the first). With OneForAll, first the prerequisites it knows of a dungeon
--- quest that Questie doesn't list.
function QR.Chain(id)
	local db = DB()
	if not db then return { id } end
	local ofa = ns.OneForAll and ns.OneForAll.Attunements
	local out, state = {}, {}
	local function Visit(q, depth)
		if state[q] or (depth > 0 and #out >= QR.MAX_CHAIN - 1) or depth > QR.MAX_CHAIN then return end -- (the quest itself last)
		state[q] = "seen" -- (a loop in the data stops here)
		for _, p in ipairs(ofa and ofa.Before(q) or {}) do Visit(p, depth + 1) end
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

-- (how it was found says which quest it comes before: two chains sharing a quest each keep it, and their steps whole)
local function ChainView(row, i, n, last, before)
	local d = row.detail
	local say = last and L["the quest itself"] or L["step %d of %d"]:format(i, n)
	return setmetatable({ detail = say .. ((d and d ~= "") and (ns.DETAIL_SEP .. d) or ""), pipeHow = L["before %s"]:format(before) },
		{ __index = row })
end

if ns.RegisterRelation then
	-- "the defias brotherhood > rewards", "what does the defias brotherhood give": what a quest rewards, Questie's; a
	-- faction's quartermaster's rewards are this link's too (OneForAll, Armory.lua)
	ns:RegisterRelation("rewards", {
		aliases = { "reward", "gives", "questrewards" },
		desc = L["what a quest rewards (Questie)"],
		available = function() return ns.providers.questie ~= nil end, addon = "Questie",
		seedKinds = { "questie", "quests" },
		applies = function(e) return QuestIdOf(e) ~= nil end,
		run = function(rows)
			local P = ns.Pipes
			local out, seen = {}, {}
			for _, e in ipairs(rows) do
				local list = QR.RewardsOf(QuestIdOf(e))
				if list == nil and not QR.Index() then
					QR.Build()
					if P then P.loading = true end -- (Questie's rewards still being read: asked again once they're in)
				end
				for _, it in ipairs(list or {}) do
					if not seen[it.id] and P and P.ItemRow then
						local r = P.ItemRow(it.id, L["Rewards"] .. ns.DETAIL_SEP .. tostring(e.name), L["Rewards"])
						if r then seen[it.id] = true; out[#out + 1] = r end
					end
				end
			end
			return out
		end,
	})
	if ns.Pipes then ns.Pipes.LABELS.rewards = "rewards" end
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

----------------------------------------------------------------------
-- Quests by the reputation they give: QuestieDB's quest field 26, reputationReward, a list of { factionId, value }
-- pairs (classicQuestFixes.lua writes {{factionIDs.HORDE, 50}}); a value can be negative (an opposing faction's loss),
-- only gains count. repreward:<faction> on quest rows, their tooltip's lines, and "quests for stormwind rep", "how do i
-- get exalted with timbermaw".
----------------------------------------------------------------------

local repOf, repCount = {}, 0 -- quest id -> its { { fid, value } } gains (false: none)
--- What a quest gives in reputation: { { factionId, value } } (gains only), or nil.
function QR.RepRewards(id)
	if type(id) ~= "number" then return nil end
	local kept = repOf[id]
	if kept ~= nil then return kept or nil end
	-- (a QuestieDB not in the shape expected gives nothing, never an error: asked from every quest tooltip)
	local okDB, db = pcall(DB)
	db = okDB and db or nil
	-- (Questie not ready yet, right after login: nothing kept, asked again later)
	if not (db and db.QueryQuestSingle) then return nil end
	local raw = Safe(db.QueryQuestSingle, id, "reputationReward")
	local out
	if type(raw) == "table" then
		for _, p in ipairs(raw) do
			local fid, v = type(p) == "table" and tonumber(p[1]), type(p) == "table" and tonumber(p[2])
			if fid and v and v > 0 then out = out or {}; out[#out + 1] = { fid, v } end
		end
	end
	if repCount > 20000 then repOf, repCount = {}, 0 end
	repOf[id], repCount = out or false, repCount + 1
	return out
end
function QR.ForgetRep() repOf, repCount = {}, 0 end -- (tests)

local factionNames = {} -- faction id -> its name (false: none)
--- A faction's name: your reputations' (the row), else the game's for its id.
function QR.FactionName(fid)
	local n = factionNames[fid]
	if n ~= nil then return n or nil end
	local p = ns.providers.reputation
	for _, e in ipairs(p and p._entries or {}) do
		if e.factionID == fid and not e.repReward then n = e.name break end
	end
	if not n then
		local C = rawget(_G, "C_Reputation")
		local d = C and C.GetFactionDataByID and Safe(C.GetFactionDataByID, fid)
		n = type(d) == "table" and Str(d.name) or nil
	end
	if not n and _G.GetFactionInfoByID then n = Str(Safe(_G.GetFactionInfoByID, fid)) end
	factionNames[fid] = n or false
	return n
end
--- The faction ids whose name has these words (lowercase): your reputations', and OneForAll's factions. The factions
--- Questie's quests name (what they give, what they need), with the game's names: the ones you haven't met are in no
--- reputation list. Made once, when Questie's quests are in.
local questFactions
function QR.QuestFactions()
	if questFactions then return questFactions end
	local qp = ns.providers.questie
	local list = qp and rawget(qp, "_entries")
	if not (list and DB()) then return {} end
	local seen, out = {}, {}
	for _, e in ipairs(list) do
		local id = QuestIdOf(e)
		for _, r in ipairs(id and QR.RepRewards(id) or {}) do
			if not seen[r[1]] then seen[r[1]] = true; out[#out + 1] = r[1] end
		end
		local need = id and QR.Requires(id)
		if need and need.rep and not seen[need.rep[1]] then seen[need.rep[1]] = true; out[#out + 1] = need.rep[1] end
	end
	local named = {}
	for _, fid in ipairs(out) do
		local n = QR.FactionName(fid)
		if n then named[#named + 1] = { id = fid, name = n } end
	end
	questFactions = named
	return named
end
function QR.ForgetQuestFactions() questFactions = nil end -- (tests)
--- (each word the start of one of the name's words, three letters or more: "quests for s rep" named Stormwind and
--- Darnassus)
function QR.FactionsNamed(words)
	local out, any = {}, false
	for _, w in ipairs(words) do if #w < 3 then return nil end end
	local function Try(fid, name)
		if not (fid and name) then return end
		local ln = " " .. Lower(name)
		for _, w in ipairs(words) do if not ln:find(" " .. w, 1, true) then return end end
		out[fid], any = true, true
		factionNames[fid] = factionNames[fid] or name
	end
	local p = ns.providers.reputation
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do if not e.repReward then Try(e.factionID, e.name) end end
	local A = ns.Armory
	for _, f in ipairs(A and A.Factions and A.Factions() or {}) do Try(f.id, f.name) end
	if not any then for _, f in ipairs(QR.QuestFactions()) do Try(f.id, f.name) end end
	return any and out or nil
end
--- The reputation a quest gives with these factions, the most of them (0: none).
local function RepWith(id, fids)
	local best = 0
	for _, r in ipairs(QR.RepRewards(id) or {}) do if fids[r[1]] and r[2] > best then best = r[2] end end
	return best
end
QR.RepWith = RepWith

if Fk and Fk.KEYS then
	-- repreward:stormwind: the quests that give reputation with it ("rep:" is your standing: Others.lua's)
	Fk.KEYS.repreward = function(v)
		local words = {}
		for w in Lower(v):gsub("_", " "):gmatch("%S+") do words[#words + 1] = w end
		local fids = #words > 0 and QR.FactionsNamed(words)
		if not fids then return nil end
		return function(e)
			local id = QuestIdOf(e)
			return id ~= nil and RepWith(id, fids) > 0
		end
	end
end

local RQ = {}
ns.RepQuests = RQ
local RQ_PATS = { "^quests? for (.+) rep$", "^quests? for (.+) reputation$", "^quests? that give (.+) rep$",
	"^quests? that give (.+) reputation$", "^quests? giving (.+) rep$", "^quests? giving (.+) reputation$", "^(.+) rep quests$",
	"^(.+) reputation quests$", "^rep quests for (.+)$", "^reputation quests for (.+)$", "^how do i get rep with (.+)$",
	"^how to get rep with (.+)$", "^how do i get reputation with (.+)$", "^how to get reputation with (.+)$",
	"^how do i raise (.+) rep$", "^how do i raise (.+) reputation$", "^how to raise (.+) rep$", "^how to raise (.+) reputation$" }
local STAND_PAT = { "^how do i get (%a+) with (.+)$", "^how to get (%a+) with (.+)$", "^how do i become (%a+) with (.+)$" }
RQ.MAX = 50
function RQ.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	local what, standing
	for _, p in ipairs(RQ_PATS) do what = t:match(p) if what then break end end
	if not what then
		for _, p in ipairs(STAND_PAT) do
			local st, f = t:match(p)
			local words = ns.Filters and ns.Filters._ and ns.Filters._.StandingWords and ns.Filters._.StandingWords() or {}
			if st and words[st] then standing, what = words[st], f break end
		end
	end
	if not what then return nil end
	what = what:gsub("^the ", "")
	local words = {}
	for w in what:gmatch("%S+") do words[#words + 1] = w end
	local fids = QR.FactionsNamed(words)
	if not fids then return nil end
	return { fids = fids, said = what, standing = standing }
end
function RQ.Answer(q)
	local title = L["Quests"] .. ns.DETAIL_SEP .. ns.UpperFirst(q.said)
	local rows = {}
	-- (how to get a standing: your standing with it first)
	if q.standing then
		local p = ns.providers.reputation
		for _, e in ipairs(p and ns:GetEntries(p) or {}) do if not e.repReward and q.fids[e.factionID] then rows[#rows + 1] = e break end end
	end
	local db = DB()
	if not db then return { ns.NoteRow(L["Needs Questie: it knows every quest and where it starts"]) }, title end
	local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
	local found = {}
	local qp = ns.providers.questie
	for _, e in ipairs(qp and ns:GetEntries(qp) or {}) do
		local id = QuestIdOf(e)
		local v = id and RepWith(id, q.fids) or 0
		if v > 0 and not (done and Safe(done, id)) and QR.ForYou(id) then found[#found + 1] = { v = v, e = e } end
	end
	table.sort(found, function(a, b) if a.v ~= b.v then return a.v > b.v end return tostring(a.e.name) < tostring(b.e.name) end)
	for i = 1, math.min(#found, RQ.MAX) do
		local f = found[i]
		rows[#rows + 1] = setmetatable({ detail = ("+%d"):format(f.v) .. ns.DETAIL_SEP .. tostring(f.e.detail or "") }, { __index = f.e })
	end
	if #rows == 0 then return { ns.NoteRow(L["Nothing has that. Check the spelling, or try other words."]) }, title end
	ns.ScoreInOrder(rows)
	return rows, title
end
-- (its own answer: ranked by the reputation the faction asked for gives, which no sort knows; Alt+` lists the same
-- quests, the ones you can take: is:foryou)
function RQ.ToAdvanced(q) return "@questie repreward:" .. (q.said:gsub("%s+", "_")) .. " is:foryou -is:done " end

----------------------------------------------------------------------
-- What a quest needs, QuestieDB's quest fields as its questMeta.lua says them: requiredSkill (18) { skillLineId, value
-- }, requiredMinRep (19) { factionId, value } (reputation points: Honored 9000, Revered 21000, Exalted 42000),
-- specialFlags (24) a bitmask (1: repeatable), questFlags (23) a bitmask (4096: daily). Read defensively: anything not
-- in that shape is nothing. Filters skill:<profession>, is:repeatable, is:daily; the tooltip says it; "quests here" and
-- "quests near me" leave out what you can't take yet; "tailoring quests", "daily quests", "quests that need honored
-- with stormwind".
----------------------------------------------------------------------

local needOf, needCount = {}, 0
local function Bit(n, b) n = tonumber(n) return n ~= nil and n >= 0 and math.floor(n / b) % 2 == 1 end
local function Pair(t) if type(t) == "table" and tonumber(t[1]) and tonumber(t[2]) then return { tonumber(t[1]), tonumber(t[2]) } end end
--- { skill = { line, value }, rep = { factionId, value }, repeatable, daily }, or nil when it needs nothing of these.
function QR.Requires(id)
	if type(id) ~= "number" then return nil end
	local kept = needOf[id]
	if kept ~= nil then return kept or nil end
	local okDB, db = pcall(DB)
	db = okDB and db or nil
	if not (db and db.QueryQuestSingle) then return nil end -- (not ready: nothing kept)
	local out
	do
		local skill = Pair(Safe(db.QueryQuestSingle, id, "requiredSkill"))
		local rep = Pair(Safe(db.QueryQuestSingle, id, "requiredMinRep"))
		local repeatable = Bit(Safe(db.QueryQuestSingle, id, "specialFlags"), 1)
		local daily = Bit(Safe(db.QueryQuestSingle, id, "questFlags"), 4096)
		if skill or rep or repeatable or daily then out = { skill = skill, rep = rep, repeatable = repeatable or nil, daily = daily or nil } end
	end
	if needCount > 20000 then needOf, needCount = {}, 0 end
	needOf[id], needCount = out or false, needCount + 1
	return out
end
function QR.ForgetRequires() needOf, needCount = {}, 0 end -- (tests)

-- reputation points to a standing (1-8)
local REP_FLOOR = { { 42000, 8 }, { 21000, 7 }, { 9000, 6 }, { 3000, 5 }, { 0, 4 }, { -3000, 3 }, { -6000, 2 } }
function QR.StandingOfValue(v)
	v = tonumber(v)
	if not v then return nil end
	for _, f in ipairs(REP_FLOOR) do if v >= f[1] then return f[2] end end
	return 1
end
--- Your skill in a skill line (0: not learned), your reputation points with a faction (nil: not known).
function QR.MySkill(line)
	local Pr = ns.Professions
	for _, p in ipairs(Pr and Pr.PlayerProfessions and (Pr.PlayerProfessions()) or {}) do
		if p.skillLine == line then return p.rank or 0 end
	end
	return 0
end
function QR.MyRep(fid)
	local C = rawget(_G, "C_Reputation")
	local d = C and C.GetFactionDataByID and Safe(C.GetFactionDataByID, fid)
	if type(d) == "table" and ns.Num(d.currentStanding) then return ns.Num(d.currentStanding) end
	if _G.GetFactionInfoByID then
		local v = select(6, Safe(_G.GetFactionInfoByID, fid))
		return ns.Num(v)
	end
	return nil
end
--- Can you take it now, by QuestieDB's prerequisites, exclusive quests, level cap, breadcrumbs, spell and reputation
--- cap (Search/Questions/QuestAccess.lua, loaded after this file)? true without it.
function QR.CanTakeNow(id, level, memo)
	local QA = ns.QuestAccess
	return not (QA and QA.CanTake) or QA.CanTake(id, level, memo)
end
--- Can you take it, by what it needs (a profession's skill, a standing)? true when it needs neither, or the game won't say.
--- (memo: a table kept across one list's quests, so your skills and standings are read once each)
function QR.MeetsRequires(id, memo)
	local r = QR.Requires(id)
	if not r then return true end
	memo = memo or {}
	if r.skill then
		local k = "s" .. r.skill[1]
		if memo[k] == nil then memo[k] = QR.MySkill(r.skill[1]) end
		if memo[k] < r.skill[2] then return false end
	end
	if r.rep then
		local k = "r" .. r.rep[1]
		if memo[k] == nil then memo[k] = QR.MyRep(r.rep[1]) or false end
		if memo[k] and memo[k] < r.rep[2] then return false end
	end
	return true
end
--- What it needs, said: "Needs Tailoring 150 (have 75)", "Needs Honored with Stormwind (Friendly)", "Daily"; { lines },
--- and { [line] = false } for each need you don't meet (the tooltip's red).
function QR.RequiresSaid(id)
	local r = QR.Requires(id)
	local out, met = {}, {}
	if not r then return out, met end
	local P = ns.Pipes
	if r.skill then
		local pr = P and P.ProfOfLine and P.ProfOfLine(r.skill[1])
		local name = (C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName and Str(Safe(C_TradeSkillUI.GetTradeSkillDisplayName, r.skill[1])))
			or (pr and pr[3]) or tostring(r.skill[1])
		local have = QR.MySkill(r.skill[1])
		out[#out + 1] = L["Needs %s"]:format(name .. " " .. r.skill[2]) .. " (" .. L["have %d"]:format(have) .. ")"
		met[#out] = have >= r.skill[2]
	end
	if r.rep then
		local need = QR.StandingOfValue(r.rep[2])
		local fname = QR.FactionName(r.rep[1]) or tostring(r.rep[1])
		local points = QR.MyRep(r.rep[1])
		local mine = QR.StandingOfValue(points)
		-- (a need that isn't a standing's start, Darkmoon's 5500: the points too, so a red line says why)
		local floor = false
		for _, f in ipairs(REP_FLOOR) do if f[1] == r.rep[2] then floor = true end end
		local have = mine and ns.StandingName(mine) or nil
		if have and not floor then have = have .. ", " .. points .. "/" .. r.rep[2] end
		out[#out + 1] = L["Needs %s"]:format((ns.StandingName(need) or "?") .. " " .. L["with %s"]:format(fname))
			.. (have and (" (" .. have .. ")") or "")
		met[#out] = points == nil or points >= r.rep[2]
	end
	if r.daily then out[#out + 1] = ns.GameText("DAILY", L["Daily"]) end
	if r.repeatable then out[#out + 1] = ns.GameText("REPEATABLE", L["Repeatable"]) end
	return out, met
end

if Fk and Fk.KEYS then
	-- skill:tailoring: the quests that need that profession (Chains.lua's P.ProfOfName; "skill:tail" the start of one)
	Fk.KEYS.skill = function(v)
		local P = ns.Pipes
		local want = Lower((v:gsub("_", " ")))
		if want == "any" then -- (skill:any: a profession, whichever)
			return function(e) local id = QuestIdOf(e) local r = id and QR.Requires(id) return r ~= nil and r.skill ~= nil end
		end
		local pr = P and P.ProfOfName and P.ProfOfName(want)
		local squashed = want:gsub(" ", "") -- ("skill:first_a": the start of firstaid)
		if not pr and P and P.AL_PROFS and #squashed >= 3 then
			for _, x in pairs(P.AL_PROFS) do if x[1]:sub(1, #squashed) == squashed then pr = x break end end
		end
		if not pr then return nil end
		local line = pr[2]
		return function(e)
			local r = QuestIdOf(e) and QR.Requires(QuestIdOf(e))
			return r ~= nil and r.skill ~= nil and r.skill[1] == line
		end
	end
	if Fk.IS then
		Fk.IS.repeatable = function(e) local id = QuestIdOf(e) local r = id and QR.Requires(id) return r ~= nil and r.repeatable == true end
		Fk.IS.daily = function(e) local id = QuestIdOf(e) local r = id and QR.Requires(id) return r ~= nil and r.daily == true end
	end
end

local QN = {}
ns.QuestNeeds = QN
QN.MAX = 50
local QN_FILL = { quest = true, quests = true, i = true, can = true, ["do"] = true, my = true, the = true, ["for"] = true, show = true,
	list = true, all = true, any = true, some = true, that = true, which = true, what = true, are = true,
	need = true, needs = true, needing = true, require = true, requires = true, requiring = true } -- ("quests needing tailoring")
function QN.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	-- "quests that need honored with stormwind"
	local st, f = t:match("^quests? that needs? (%a+) with (.+)$")
	if not st then st, f = t:match("^quests? needing (%a+) with (.+)$") end
	if st then
		local words = ns.Filters and ns.Filters._ and ns.Filters._.StandingWords and ns.Filters._.StandingWords() or {}
		local need = words[st]
		local fw = {}
		for w in f:gsub("^the ", ""):gmatch("%S+") do fw[#fw + 1] = w end
		local fids = need and QR.FactionsNamed(fw)
		if fids then return { what = "rep", fids = fids, need = need, said = f } end
		return nil
	end
	-- "tailoring quests", "first aid quests", "profession quests", "daily quests", "dailies", "repeatable quests"
	local quest, daily, repeatable, anyProf = false, false, false, false
	local rest = {}
	for w in t:gmatch("%S+") do
		if w == "quest" or w == "quests" then quest = true
		elseif w == "daily" or w == "dailies" or w == "dailys" then daily = true; quest = quest or w ~= "daily"
		elseif w == "repeatable" or w == "repeatables" or w == "repeating" then repeatable = true
		elseif w == "profession" or w == "professions" then anyProf = true
		elseif not QN_FILL[w] then rest[#rest + 1] = w end
	end
	if not quest then return nil end
	local P = ns.Pipes
	local prof = #rest > 0 and P and P.ProfOfName and P.ProfOfName(table.concat(rest, " "))
	if #rest > 0 and not prof then return nil end -- ("hogger quests": a search)
	if daily and not prof then return { what = "daily" } end
	if repeatable and not prof then return { what = "repeatable" } end
	if prof or anyProf then return { what = "skill", prof = prof or nil } end
	return nil
end
function QN.Answer(q)
	local db = DB()
	local title = L["Quests"]
	if not db then return { ns.NoteRow(L["Needs Questie: it knows every quest and where it starts"]) }, title end
	local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
	-- (every match, then those you can take first, the lowest level first, then cut: the first 50 by id were the
	-- answer)
	local found = {}
	local qp = ns.providers.questie
	local memo = {}
	for _, e in ipairs(qp and ns:GetEntries(qp) or {}) do
		local id = QuestIdOf(e)
		local r = id and QR.Requires(id)
		-- (a standing needed only: daily, repeatable and a profession are searches, QN.Line)
		local ok = r and q.what == "rep" and r.rep and q.fids[r.rep[1]] and QR.StandingOfValue(r.rep[2]) >= q.need
		if ok and not (done and Safe(done, id) and not r.daily and not r.repeatable) and QR.ForYou(id) then
			found[#found + 1] = { e = e, id = id, can = QR.MeetsRequires(id, memo), lv = tonumber(e.level) or 0 }
		end
	end
	table.sort(found, function(a, b)
		if a.can ~= b.can then return a.can end
		if a.lv ~= b.lv then return a.lv < b.lv end
		return tostring(a.e.name) < tostring(b.e.name)
	end)
	local rows = {}
	for i = 1, math.min(#found, QN.MAX) do
		local said = QR.RequiresSaid(found[i].id)
		rows[i] = setmetatable({ detail = table.concat(said, ns.DETAIL_SEP) }, { __index = found[i].e })
	end
	if #found == 0 then return { ns.NoteRow(L["Questie knows no quest like that here"]) }, title end
	ns.ScoreInOrder(rows)
	if #found > #rows then rows[#rows + 1] = ns.NoteRow(L["+%d more"]:format(#found - #rows)) end
	return rows, title
end
--- As Advanced syntax, its answer and its Alt+` (docs/QUESTIONS.md 4.1): those you can take first, then by level, each
--- saying what it needs (sort:cantake's detail); nil for a standing needed ("quests that need honored with stormwind":
--- its own answer, no filter says a standing needed).
function QN.Line(q)
	if q.what == "daily" then return "@questie is:daily is:foryou sort:cantake " end
	if q.what == "repeatable" then return "@questie is:repeatable is:foryou sort:cantake " end
	if q.what == "skill" then return "@questie skill:" .. (q.prof and q.prof[1] or "any") .. " is:foryou -is:done sort:cantake " end
	return nil
end
function QN.Footer() return L["Quests"] end
function QN.None()
	if not DB() then return { ns.NoteRow(L["Needs Questie: it knows every quest and where it starts"]) } end
	return { ns.NoteRow(L["Questie knows no quest like that here"]) }
end

if Fk and Fk.IS then
	-- is:foryou: a quest your race, class and side may take; is:cantake: and whose needs you meet, nothing in QuestieDB
	-- stopping you (prerequisites, an exclusive quest done, a level cap...: QR.CanTakeNow)
	Fk.IS.foryou = function(e) local id = QuestIdOf(e) return id ~= nil and QR.ForYou(id) end
	Fk.IS.cantake = function(e) local id = QuestIdOf(e) return id ~= nil and QR.ForYou(id) and QR.MeetsRequires(id) and QR.CanTakeNow(id) end
	-- is:itemstart: a quest an item starts (Questie's startedBy, its items; "quests that start from an item")
	Fk.IS.itemstart = function(e)
		local db, id = DB(), QuestIdOf(e)
		local by = db and id and Safe(db.QueryQuestSingle, id, "startedBy")
		return type(by) == "table" and type(by[3]) == "table" and by[3][1] ~= nil
	end
end
--- The item that starts a quest, by name ("Started by Grimy Note"): is:itemstart's detail.
function QR.StartItemDetail(e)
	local db, id = DB(), QuestIdOf(e)
	local by = db and id and Safe(db.QueryQuestSingle, id, "startedBy")
	local item = type(by) == "table" and type(by[3]) == "table" and by[3][1]
	if not item then return nil end
	local name = db.QueryItemSingle and Str(Safe(db.QueryItemSingle, item, "name"))
	return L["Started by %s"]:format(name or L["an item"])
end
ns.FIELD_DETAIL.itemstart = function(e) return QR.StartItemDetail(e) end
ns.SHOW_FIELD_FOR = ns.SHOW_FIELD_FOR or {}
ns.SHOW_FIELD_FOR["is:itemstart"] = "itemstart"
-- sort:cantake: the quests you can take first, then by level, then by name; its detail says what each needs
do
	local A, F, B = ns.Aggregate, ns.Filters, ns.Bar
	if A and A.FIELDS then
		A.FIELDS.cantake = { label = ns.Lower(L["Can take"]), num = function(e)
			local id = QuestIdOf(e)
			if not id then return nil end
			return (QR.ForYou(id) and QR.MeetsRequires(id) and QR.CanTakeNow(id)) and 0 or 1
		end }
	end
	if B and B.SORTS then B.SORTS[#B.SORTS + 1] = { id = "cantake", label = L["Can take"], field = "cantake", asc = true, tie = "level" } end
	ns.FIELD_DETAIL.cantake = function(e)
		local id = QuestIdOf(e)
		local said = id and QR.RequiresSaid(id)
		-- (and the first thing QuestieDB says stops you: "Needs <quest> first")
		local QA = ns.QuestAccess
		local why = id and QA and QA.Reasons and QA.Reasons(id)[1]
		if why then said = said or {}; said[#said + 1] = QA.Say(why) end
		local own = rawget(e, "detail") or e.detail
		if not said or #said == 0 then return own end
		return table.concat(said, ns.DETAIL_SEP) .. ((own and own ~= "") and (ns.DETAIL_SEP .. own) or "")
	end
end
