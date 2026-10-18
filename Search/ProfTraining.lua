local ns = select(2, ...)
local L = ns.L

-- Profession training in plain words (0.57.1): what a trainer still has to teach you in your professions. Its rows are
-- @recipe is:unknown's (Providers/MissingRecipes.lua): the recipes a trainer teaches that you don't know, as your
-- profession windows and the trainers' windows listed them, and TrainerSpells when it's installed (with their cost and
-- the skill they need); a profession's next rank is on its @profession row (Providers/Recipes.lua).
--
--   "what can i train in tailoring", "tailoring training", "profession training", "how much is tailoring training",
--   "what can i learn at the tailoring trainer": @recipe is:learnable tailoring trainer (| sum cost)
--
-- Before What's Training's question ("what can i train" alone is your class's spells) and after the recipes' ("recipes
-- i can learn" is MissingRecipes.lua's).

local PT = {}
ns.ProfTraining = PT

local Lower = ns.Lower
local SEP = ns.DETAIL_SEP
local F = ns.Filters

-- | sum cost: a recipe's trainer cost; is:learnable on @profession: its next rank, your skill there (Recipes.lua)
do
	local G = ns.Aggregate
	local cost = G and G.FIELDS and G.FIELDS.cost
	if cost then
		local num = cost.num
		cost.num = function(e)
			if e.kind == "missing" or e.kind == "professions" then return ns.Num(rawget(e, "cost")) end
			return num(e)
		end
	end
	local IS = F._.IS
	local learnable = IS.learnable
	IS.learnable = function(e) if e.kind == "professions" then return rawget(e, "canLearn") == true end return learnable(e) end
	IS.canlearn = IS.learnable
end

local function Rows()
	local p = ns.providers.missing
	return p and ns:GetEntries(p) or {}
end

----------------------------------------------------------------------
-- The question
----------------------------------------------------------------------

-- the professions by their English names (as typed in any language) and the ways they're said
local PROF_WORDS = {
	alchemy = 171, blacksmithing = 164, smithing = 164, cooking = 185, enchanting = 333, engineering = 202, firstaid = 129,
	herbalism = 182, leatherworking = 165, mining = 186, skinning = 393, tailoring = 197,
}
local TRAIN = { train = true, training = true, trainable = true }
local LEARN = { learn = true, learnable = true }
local MONEY = { cost = true, costs = true, much = true, price = true, gold = true, money = true, afford = true }
local ALL = { profession = true, professions = true, prof = true, profs = true, crafting = true, trade = true, trades = true }
local ASK = { what = true, whats = true, which = true, can = true, could = true, show = true, list = true, my = true, how = true }
local FILL = {}
for w in ([[what whats which when can could will would should i im my me do does to the a an at for is are there any show
	list all how need still left yet have got of in and with from get by it its this that be am now next]]):gmatch("%a+") do FILL[w] = true end
-- (another question's: recipes are MissingRecipes.lua's; a trainer's place is a search: "nearest tailoring trainer")
local NOT = { recipe = true, recipes = true, nearest = true, where = true, closest = true, nearby = true }

--- Your professions: by skill line, and by their names in the client's language ("schneiderei").
local function Yours()
	local P = ns.Professions
	local byLine, byName = {}, {}
	for _, pr in ipairs(P and P.PlayerProfessions and (P.PlayerProfessions()) or {}) do
		if pr.skillLine then byLine[pr.skillLine] = pr end
		byName[Lower(pr.name)] = pr
	end
	return byLine, byName
end

--- "what can i train in tailoring", "tailoring training", "profession training": { profs = { names } or nil (all),
--- missing = { words named a profession you don't have }, state ("now"), money }, or nil when the line isn't asking
--- this.
function PT.Question(text)
	if not ns.providers.missing then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("first aid", "firstaid")
	-- (no word of training, learning, a trainer or its cost: not this question, before your professions are read; it's
	-- asked on every keystroke; review, 0.57.7)
	local cue = false
	for w in t:gmatch("%S+") do
		if TRAIN[w] or LEARN[w] or MONEY[w] or w == "trainer" or w == "trainers" then cue = true break end
	end
	if not cue then return nil end
	local byLine, byName = Yours()
	local q = { words = {}, missing = {} }
	local train, learn, asked, trainer, all = false, false, false, false, false
	local profs, seen = {}, {}
	for w in t:gmatch("%S+") do
		if NOT[w] then return nil end
		local line = PROF_WORDS[w]
		local pr = (line and byLine[line]) or byName[w]
		if pr or line then
			if not pr then q.missing[#q.missing + 1] = w
			elseif not seen[pr.name] then seen[pr.name] = true; profs[#profs + 1] = pr.name end
		elseif TRAIN[w] then train = true
		elseif LEARN[w] then learn = true
		elseif w == "trainer" or w == "trainers" then trainer = true
		elseif MONEY[w] then q.money = true
		elseif ALL[w] then all = true
		elseif w == "now" or w == "can" or w == "could" then q.state = "now"; asked = true
		else
			if ASK[w] then asked = true end
			if not FILL[w] then q.words[#q.words + 1] = w end
		end
	end
	if #profs == 0 and #q.missing == 0 and not all then return nil end
	-- what makes it this question: training said; learning asked ("what can i learn at the tailoring trainer"); its cost
	if not (train or (learn and (asked or trainer)) or (trainer and asked) or (q.money and (train or trainer))) then return nil end
	if #q.words > 0 then return nil end -- (other words: a search)
	if q.money then q.state = "now" end
	q.profs = #profs > 0 and profs or nil
	return q
end

--- Does a row pass the question? (a trainer teaches it; the profession asked; your skill there, when "now")
function PT.Keeps(q, e)
	local s = rawget(e, "sources")
	if not (type(s) == "table" and s.trainer) then return false end
	if q.state == "now" and not e.canLearn then return false end
	if q.profs then
		for _, p in ipairs(q.profs) do if e.profName == p then return true end end
		return false
	end
	return true
end

local NoteRow = ns.NoteRow

--- Each profession asked about's next rank, as the footer says it ("next rank (Expert) at skill 125: 1g").
local function NextRanks(q)
	local TS = ns.TrainerSpells
	local P = ns.Professions
	if not (TS and TS.NextRank and P and P.PlayerProfessions) then return "" end
	local want = {}
	for _, n in ipairs(q.profs or {}) do want[n] = true end
	local said = {}
	for _, pr in ipairs((P.PlayerProfessions())) do
		if q.profs and want[pr.name] or (not q.profs and #said < 2) then
			local nr = TS.NextRank(pr)
			if nr then
				said[#said + 1] = pr.name .. ": " .. L["next rank%s at skill %d"]:format(nr.title and (" (" .. nr.title .. ")") or "",
					nr.skill) .. ((nr.cost or 0) > 0 and (": " .. ns.Money(nr.cost)) or "")
			end
		end
	end
	return #said > 0 and (SEP .. table.concat(said, SEP)) or ""
end

--- The rows, and the footer's note (how many you can learn now, and what that costs; the next rank).
function PT.Answer(q)
	local rows = {}
	local now, cost = 0, 0
	for _, e in ipairs(Rows()) do
		if PT.Keeps(q, e) then rows[#rows + 1] = e end
		if PT.Keeps({ profs = q.profs, state = "now" }, e) then now, cost = now + 1, cost + (rawget(e, "cost") or 0) end
	end
	table.sort(rows, function(a, b)
		if (a.canLearn == true) ~= (b.canLearn == true) then return a.canLearn == true end
		if (a.need or 0) ~= (b.need or 0) then return (a.need or 0) < (b.need or 0) end
		return tostring(a.name) < tostring(b.name)
	end)
	ns.ScoreInOrder(rows)
	local note = L["Profession training"] .. SEP .. L["%d to learn now"]:format(now) .. (cost > 0 and (SEP .. ns.Money(cost)) or "")
	if q.money then
		local sum = 0
		for _, e in ipairs(rows) do sum = sum + (rawget(e, "cost") or 0) end
		note = L["Profession training"] .. SEP .. L["%d to learn: %s"]:format(#rows, ns.Money(sum))
	end
	note = note .. NextRanks(q)
	if #rows == 0 then
		local say
		if #q.missing > 0 and not q.profs then
			say = L["You don't have that profession"]
		else
			local P = ns.Professions
			local any = P and P.PlayerProfessions and #(P.PlayerProfessions()) > 0
			say = any and (q.state == "now" and L["Nothing a trainer can teach you right now"] or L["Nothing left for a trainer to teach you"])
				or L["You have no profession a trainer teaches yet"]
		end
		return { NoteRow(say) }, note
	end
	return rows, note
end

--- The question as Advanced syntax (Alt+`): "@recipe is:learnable tailoring trainer | sum cost".
function PT.ToAdvanced(q)
	local parts = { "@recipe", q.state == "now" and "is:learnable" or "is:unknown" }
	for _, p in ipairs(q.profs or {}) do
		local w = Lower(p)
		parts[#parts + 1] = w:find(" ", 1, true) and ('"' .. w .. '"') or w -- ("first aid": a quoted phrase)
	end
	parts[#parts + 1] = "trainer"
	if q.money then parts[#parts + 1] = "| sum cost" end
	return table.concat(parts, " ") .. " "
end
