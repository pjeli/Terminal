local ns = select(2, ...)
local L = ns.L

-- What's Training's spells in searches (0.53.7; the rows themselves: Providers/Integrations/WhatsTraining.lua):
--
--   fireball > learn          where a spell is taught: the nearest of your class's trainers (a pet trainer for a pet
--                             ability), its weapon masters, its quest, or where to get its book ("where to learn fireball")
--   "what can i train", "what do i learn next level", "spells at level 30", "weapon skills to learn", "how much is
--   training", "when do i learn fireball": @training with is:learnable / is:nextlevel / is:later / lvl: / is:weapon
--   @training is:learnable | sum cost   what learning it all costs
--
-- Filters: is:learnable (now), is:nextlevel, is:later, is:needsrank, is:needstalent, is:pet, is:weapon, is:ignored,
-- is:quest (taught by a quest); lvl: is its level; "| sum cost" adds up what it costs.

local WT = ns.WhatsTraining
local P = ns.Pipes
local F = ns.Filters
local Lower = ns.Lower
local SEP = ns.DETAIL_SEP

local function Rows()
	local p = ns.providers.training
	return p and ns:GetEntries(p) or {}
end

----------------------------------------------------------------------
-- Filters
----------------------------------------------------------------------

local IS = F._.IS
local function State(s) return function(e) return e.kind == "training" and e.state == s end end
do
	local learnable = IS.learnable -- (@recipe's: what your skill allows now; Npcs.lua)
	IS.learnable = function(e) if e.kind == "training" then return e.state == "now" end return learnable(e) end
	IS.canlearn = IS.learnable
	local quest = IS.quest -- (an item that starts a quest; Items.lua)
	IS.quest = function(e) if e.kind == "training" then return e.quest == true end return quest(e) end
end
IS.nextlevel, IS.soon = State("nextlevel"), State("nextlevel")
IS.later, IS.needsrank, IS.needstalent = State("later"), State("needsrank"), State("needstalent")
IS.ignored = State("ignored")
IS.weapon = function(e) return e.kind == "training" and e.weapon == true end
IS.pet = function(e) return e.kind == "training" and e.pet == true end
do
	local A = F.APPLIES.is
	local TRAINING = { "training" }
	for _, k in ipairs({ "nextlevel", "soon", "later", "needsrank", "needstalent", "ignored", "weapon", "pet" }) do A[k] = TRAINING end
	for _, k in ipairs({ "learnable", "quest" }) do
		local list = {}
		for _, v in ipairs(A[k] or {}) do list[#list + 1] = v end
		list[#list + 1] = "training"
		A[k] = list
	end
	A.canlearn = A.learnable
	-- (Tab and the pick list offer them, .filters says them)
	local V = F.VALUES.is
	for _, k in ipairs({ "nextlevel", "later", "needsrank", "needstalent", "weapon", "pet", "ignored" }) do V[#V + 1] = k end
	for i, h in ipairs(F.HELP) do
		if h[1] == "is:unknown" then
			table.insert(F.HELP, i + 1, { "is:nextlevel", L["@training: learnable (now) nextlevel later needsrank needstalent pet weapon ignored quest"] })
			break
		end
	end
end

-- "| sum cost": what learning the spells listed costs (Pipes.lua's summing steps)
do
	local A = ns.Aggregate
	if A and A.FIELDS then
		A.FIELDS.cost = { label = L["cost"], money = true, num = function(e) return e.kind == "training" and ns.Num(e.cost) or nil end }
		A.ALIASES.costs = "cost"
		table.insert(A.ORDER, 3, "cost")
	end
end

----------------------------------------------------------------------
-- The chain: where a spell is taught
----------------------------------------------------------------------

-- the trainers who teach it (Questie's NPCs friendly to you): your class's, or the pet trainers for a pet ability; the
-- nearest first
local function Trainers(word)
	local I = ns.Integrations
	local here = I and I.Here and I.Here() or nil
	local found = {}
	for _, e in ipairs(P.Trainers(word)) do
		-- (I.RowYards: Questie's spawns, or a row's own place: TrainerSpells' trainers without Questie; 0.57.1)
		found[#found + 1] = { e = e, d = here and I.RowYards and I.RowYards(e, here) or nil }
	end
	table.sort(found, function(a, b)
		if (a.d ~= nil) ~= (b.d ~= nil) then return a.d ~= nil end
		if a.d and b.d and a.d ~= b.d then return a.d < b.d end
		return tostring(a.e.name) < tostring(b.e.name)
	end)
	return found
end

local function Costs(e) return (e.cost or 0) > 0 and (SEP .. L["costs %s"]:format(ns.Money(e.cost))) or "" end
local HOW = L["taught by"]

-- a weapon master What's Training names, Questie's row of them when it has one; else a row of its own: its place on
-- the map (Enter: the map pin there)
local function WeaponMasterRow(t, e)
	local I = ns.Integrations
	local row = I and I.NpcRow and type(t.npc) == "number" and I.NpcRow(t.npc)
	local rest = L["Teaches it"] .. Costs(e)
	if row then
		local here = I.Here and I.Here()
		local d = here and I.NpcDistance and I.NpcDistance(t.npc, here) or nil
		return P.NearSaid(P.View(row, rest, nil, HOW), d, rest)
	end
	local zone = t.uiMapId and I and I.ZoneName and I.ZoneName(t.uiMapId)
	return { key = "wm:" .. tostring(t.npc or t.name), kind = "source", name = tostring(t.name), icon = "Interface\\Icons\\INV_Sword_04",
		detail = rest .. (zone and (SEP .. zone) or ""), pipeHow = HOW, actionVerb = L["set waypoint"],
		activate = function()
			local M = ns.Maps
			if not (M and M.Place and t.uiMapId and t.x and t.y) then return end
			local pin = M.Place({ name = tostring(t.name), mapID = t.uiMapId, pos = { x = t.x / 100, y = t.y / 100 } })
			if pin then ns:Print(M.PinLine(pin, tostring(t.name), zone)) end
		end }
end

-- (the weapon skills you know: a chain starts from them, no search lists them; made with @training's list)
P.LISTS.trainingknown = function()
	local p = ns.providers.training
	if not p then return {} end
	ns:GetEntries(p)
	local TS = ns.TrainerSpells
	if p.fromTrainerSpells and TS and TS.TrainingKnown then return TS.TrainingKnown() end -- (@training from TrainerSpells)
	return WT.Known()
end

WT.MasterRow = WeaponMasterRow -- (Search/ClassSpells.lua's weapon skills, without What's Training)

ns:RegisterRelation("learn", {
	aliases = { "learned", "taught", "teach", "teaches", "trainer", "trainers" },
	desc = L["where a spell is taught: your trainer, a weapon master, a quest, a book (What's Training or TrainerSpells)"],
	available = function() return ns.providers.training ~= nil end, addon = "WhatsTraining",
	seedAlso = { "training", "trainingknown" }, -- ("fireball > learn", "where to learn daggers": its spells looked in too)
	applies = function(e) return e.kind == "training" end,
	run = function(rows)
		local api = WT.Api()
		local out = {}
		local trainersFor = {}
		for _, e in ipairs(rows) do
			local ok, src = false, nil
			if api then ok, src = pcall(api.GetSource, e.wtId) end
			src = ok and type(src) == "table" and src or nil
			local kind = src and src.kind or WT.SourceKind(e)
			if kind == "weaponMaster" then
				-- (the nearest first; those Questie doesn't place after)
				local masters = {}
				for _, t in ipairs(src and src.trainers or WT.MastersOf(e)) do masters[#masters + 1] = WeaponMasterRow(t, e) end
				table.sort(masters, function(a, b)
					local da, db = rawget(a, "_dist"), rawget(b, "_dist")
					if (da ~= nil) ~= (db ~= nil) then return da ~= nil end
					if da and db and da ~= db then return da < db end
					return tostring(a.name) < tostring(b.name)
				end)
				for _, r in ipairs(masters) do out[#out + 1] = r end
			elseif kind == "quest" then
				local I = ns.Integrations
				for _, qid in ipairs(src and src.quests or {}) do
					local q = I and I.QuestRow and I.QuestRow(qid)
					if q then
						out[#out + 1] = P.View(q, L["Its quest"] .. SEP .. tostring(q.detail or ""), nil, HOW)
					else
						out[#out + 1] = { key = "wq:" .. qid, kind = "source", name = WT.QuestTitle(qid), noActivate = true,
							icon = "Interface\\GossipFrame\\AvailableQuestIcon", detail = L["Its quest"], pipeHow = HOW }
					end
				end
			elseif kind == "item" then
				-- (the book: where to get it, as "> sources" says)
				local id = src and src.itemId or e.itemID
				if id then
					for _, r in ipairs(P.Run("sources", { { itemID = id, name = e.spellName or e.name, kind = "items" } })) do out[#out + 1] = r end
				end
			else
				-- your class's trainers (a pet trainer: a pet ability; the Demon Trainers: a demon's, a grimoire they sell),
				-- once for every spell they teach
				local pet = e.pet == true
				local key = (rawget(e, "demon") and "demon") or (pet and "pet") or "class"
				if not trainersFor[key] then
					trainersFor[key] = true
					local list = Trainers(key)
					if #list == 0 then
						out[#out + 1] = { key = "wt:" .. key, kind = "source", noActivate = true, icon = "Interface\\Icons\\INV_Misc_Book_11",
							name = (key == "demon" and L["A grimoire, sold by the Demon Trainers"]) or (pet and L["Taught by a pet trainer"])
								or L["Taught by your class trainer"], detail = Costs(e):gsub("^" .. SEP, ""),
							pipeHow = HOW }
					end
					for i = 1, math.min(#list, P.TRAINERS) do
						local t = list[i]
						local rest = L["Teaches it"] .. Costs(e)
						out[#out + 1] = P.NearSaid(P.View(t.e, rest, nil, HOW), t.d, rest)
					end
				end
			end
		end
		return out
	end,
})

----------------------------------------------------------------------
-- The question: "what can i train", "what do i learn next level", "how much is training"
----------------------------------------------------------------------

local Q = {}
WT.Q = Q

local TRAIN = { train = true, training = true, trainable = true }
local SPELL = { spell = true, spells = true, ability = true, abilities = true, rank = true, ranks = true }
local LEARN = { learn = true, learnable = true, new = true }
local STATE = { now = "now", available = "now", currently = "now", soon = "nextlevel", coming = "nextlevel",
	upcoming = "nextlevel", later = "later", ignored = "ignored", hidden = "ignored" }
local MONEY = { cost = true, costs = true, much = true, price = true, gold = true, money = true, afford = true, expensive = true }
local ASK = { what = true, whats = true, which = true, when = true, can = true, could = true, show = true, list = true, my = true }
local FILL = {}
for w in ([[what whats which when can could will would should i im my me do does did to the a an at for is are there any show
	list all how need still left yet have got of in and with from get by it its this that be am]]):gmatch("%a+") do FILL[w] = true end
-- (another question's: recipes are MissingRecipes.lua's, trainers and where they are the NPCs')
local NOT = { recipe = true, recipes = true, trainer = true, trainers = true, nearest = true, where = true, closest = true }

--- Do these words (lowercase) name a row: each the start of a word of its name?
local function Names(e, words)
	local hay = " " .. Lower(tostring(e.name)):gsub("'", ""):gsub("[%p]", " ") .. " "
	for _, w in ipairs(words) do if not hay:find(" " .. w, 1, true) then return false end end
	return true
end

--- Does a row pass the question's state, level, weapon and pet (and its words)?
function Q.Keeps(q, e)
	if q.state and e.state ~= q.state then return false end
	if not q.state and e.state == "ignored" then return false end -- (ignored: only when asked for)
	if q.level and e.level ~= q.level then return false end
	if q.weapon and not e.weapon then return false end
	if q.pet and not e.pet then return false end
	return #q.words == 0 or Names(e, q.words)
end

function Q.Match(q)
	local out = {}
	for _, e in ipairs(Rows()) do if Q.Keeps(q, e) then out[#out + 1] = e end end
	return out
end

--- "what can i train", "spells to train", "what do i learn next level", "spells at level 30", "weapon skills to learn",
--- "ignored spells", "how much is training", "when do i learn fireball": { state, level, weapon, pet, money, words }, or
--- nil when the line isn't asking What's Training (or its words name none of its spells: a search).
function Q.Question(text)
	if not ns.providers.training then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local tokens = {}
	for w in t:gmatch("%S+") do tokens[#tokens + 1] = w end
	local train, spell, learn, asked = false, false, false, false
	local q = { words = {} }
	local i = 1
	while i <= #tokens do
		local w, nxt = tokens[i], tokens[i + 1]
		if NOT[w] then return nil end
		if TRAIN[w] then train = true
		elseif SPELL[w] then spell = true
		elseif LEARN[w] then learn = true
		elseif w == "next" and (nxt == "level" or nxt == "lvl") then q.state = "nextlevel"; i = i + 1
		elseif (w == "level" or w == "lvl") and tonumber(nxt) then q.level = tonumber(nxt); i = i + 1
		elseif w == "next" then q.state = "nextlevel"
		elseif STATE[w] then q.state = STATE[w]
		elseif MONEY[w] then q.money = true
		elseif w == "weapon" or w == "weapons" then q.weapon = true
		elseif (w == "skill" or w == "skills") and q.weapon then -- ("weapon skills")
		elseif w == "pet" or w == "pets" then q.pet = true
		else
			if ASK[w] then asked = true end
			if not FILL[w] then q.words[#q.words + 1] = w end
		end
		i = i + 1
	end
	local narrowed = q.state or q.level or q.weapon or q.pet or q.money
	-- what makes it this question: a training word; spells with what you'd ask of them; "learn" asked ("what can i
	-- learn", "when do i learn fireball", "what do i learn next level")
	local cue = train or (spell and (learn or narrowed)) or (learn and (asked or narrowed))
	if not cue then return nil end
	-- ("training" alone, "train set": a search, which finds the spells too)
	if not (asked or narrowed or spell or learn or #q.words > 0) then return nil end
	if #q.words == 0 and not q.state and not q.level then
		-- "what can i train", "how much is training": what you can learn now; "my training": everything
		for _, w in ipairs(tokens) do if w == "can" or w == "could" then q.state = "now" end end
		if q.money then q.state = "now" end
	end
	if #q.words > 0 and #Q.Match(q) == 0 then return nil end -- (words naming none: a search)
	return q
end

local NoteRow = ns.NoteRow

--- The answer: the rows, and the footer's note (how many you can learn now, and what that costs).
function Q.Answer(q)
	local rows = Q.Match(q)
	ns.ScoreInOrder(rows)
	local now, cost = 0, 0
	for _, e in ipairs(Rows()) do
		if e.state == "now" then now, cost = now + 1, cost + (e.cost or 0) end
	end
	local note = L["Training"] .. SEP .. L["%d to learn now"]:format(now) .. (cost > 0 and (SEP .. ns.Money(cost)) or "")
	if #rows == 0 then
		local say = L["Nothing to train that fits"]
		if q.state == "now" then
			local nxt
			for _, e in ipairs(Rows()) do
				if (e.state == "nextlevel" or e.state == "later") and e.level and (not nxt or e.level < nxt) then nxt = e.level end
			end
			say = nxt and L["Nothing to train right now: the next at level %d"]:format(nxt) or L["Nothing to train right now"]
		end
		local p = ns.providers.training
		if not WT.Ready() and not (p and p.fromTrainerSpells) then say = L["What's Training is still reading your spells: a moment"] end
		return { NoteRow(say) }, note
	end
	if q.money then
		local sum = 0
		for _, e in ipairs(rows) do sum = sum + (e.cost or 0) end
		note = L["Training"] .. SEP .. L["%d to learn: %s"]:format(#rows, ns.Money(sum))
	end
	return rows, note
end

--- The question as Advanced syntax (Alt+`): "@training is:learnable", "@training lvl:30", "@training is:learnable | sum cost".
function Q.ToAdvanced(q)
	local parts = { "@training" }
	local IS_WORD = { now = "learnable" }
	if q.state then parts[#parts + 1] = "is:" .. (IS_WORD[q.state] or q.state) end
	if q.level then parts[#parts + 1] = "lvl:" .. q.level end
	if q.weapon then parts[#parts + 1] = "is:weapon" end
	if q.pet then parts[#parts + 1] = "is:pet" end
	if not q.state then parts[#parts + 1] = "-is:ignored" end
	for _, w in ipairs(q.words) do parts[#parts + 1] = w end
	if q.money then parts[#parts + 1] = "| sum cost" end
	return table.concat(parts, " ") .. " "
end
