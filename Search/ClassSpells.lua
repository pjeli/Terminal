local ns = select(2, ...)
local L = ns.L

-- Questions about every class's spells (0.54.1; the rows: Providers/ClassSpells.lua):
--
--   "druid spells", "shaman spells at level 20", "mage abilities"   that class's spells, by the level each is learned
--   "upcoming spells", "new spells", "spells at level 30"            your class's, the next ones you learn (or at that
--                                                                    level); What's Training's answer when it's there
--   "when do i learn travel form"                                    the spell, the level it's learned at
--
--   "my spells", "known spells"                                      your spellbook, as @spell was before it listed
--                                                                    every class's (0.54.6)
--
-- In Advanced syntax: @spell class:druid lvl:20, @spell is:known.

local CS = ns.ClassSpells
local Q = {}
CS.Q = Q
local Lower = ns.Lower

local SPELL = { spell = true, spells = true, ability = true, abilities = true }
local NEXT = { upcoming = true, next = true, new = true, coming = true, soon = true }
-- (another question's: recipes, talents, your bars)
local NOT = { recipe = true, recipes = true, talent = true, talents = true, bar = true, bars = true, trainer = true,
	trainers = true, where = true, nearest = true, macro = true, macros = true }
local FILL = {}
for w in ([[what whats which when do does did can could will i my me the a an at for of in to is are there any show
	list all get learn learned learning have level lvl from by]]):gmatch("%a+") do FILL[w] = true end

--- The class a word names (its file, "DRUID"), in English or the client's words (plural too: "druids").
local function ClassOf(w)
	local up = w:upper():gsub("S$", "")
	for _, c in ipairs(CS.CLASSES) do
		if c == w:upper() or c == up then return c end
	end
	local m = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
	for file, name in pairs(type(m) == "table" and m or {}) do
		if type(name) == "string" and Lower(name) == w then return file end
	end
end
Q.ClassOf = ClassOf

--- "druid spells": { class, level }; "upcoming spells": { upcoming = true }; "spells at level 30": { level };
--- "when do i learn travel form": { words }; nil when the line isn't one of these.
function Q.Question(text)
	if not ns.providers.classspells then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local tokens = {}
	for w in t:gmatch("%S+") do tokens[#tokens + 1] = w end
	local q = { words = {} }
	local spell, upcoming, learn, when = false, false, false, false
	local i = 1
	while i <= #tokens do
		local w, nxt = tokens[i], tokens[i + 1]
		if NOT[w] then return nil end
		if SPELL[w] then spell = true
		elseif NEXT[w] then upcoming = true
		elseif (w == "level" or w == "lvl" or w == "at") and tonumber(nxt) then q.level = tonumber(nxt); i = i + 1
		elseif w == "learn" then learn = true
		elseif w == "my" or w == "known" or w == "know" then q.known = true
		elseif w == "when" then when = true
		elseif ClassOf(w) and not q.class then q.class = ClassOf(w)
		elseif not FILL[w] then q.words[#q.words + 1] = w end
		i = i + 1
	end
	if when and learn and #q.words > 0 then q.known = nil return q end -- ("when do i learn travel form")
	if not spell then return nil end
	if q.class then q.known = nil return q end -- ("druid spells", "shaman spells at level 20")
	if #q.words > 0 then return nil end -- ("fire spells": a search)
	if upcoming then q.upcoming, q.known = true, nil return q end
	if q.level then q.known = nil return q end
	if q.known then return q end -- ("my spells", "spells i know": your spellbook)
	return nil
end

--- Does one of the row's ranks come at this level (one you don't know yet, `unknown`)?
local function RankAt(e, level, unknown)
	for _, r in ipairs(rawget(e, "_s").ranks) do
		if r[2] == level and not (unknown and CS.Known(r[1])) then return true end
	end
	return false
end

local function Has(e, words)
	local l = " " .. Lower(e.name):gsub("'", "") .. " "
	for _, w in ipairs(words) do if not l:find(" " .. w, 1, true) then return false end end
	return true
end

--- The rows (by level, then name) and the footer's note.
function Q.Answer(q)
	local NoteRow = ns.NoteRow
	local mine = CS.MyClass()
	local lvl = ns.Safe(UnitLevel, "player")
	lvl = type(lvl) == "number" and lvl or 1
	local rows, note = {}, nil
	if q.known then
		local P = ns.providers.spells
		for _, e in ipairs(P and ns:GetEntries(P) or {}) do rows[#rows + 1] = e end
		table.sort(rows, function(a, b) return tostring(a.name) < tostring(b.name) end)
		if #rows == 0 then return { NoteRow(L["No spell that fits"]) }, L["Your spellbook"] end
		-- (no count: the footer says how many, after the bar's filter too; 0.55.15, the player's screenshot had it twice)
		return ns.ScoreInOrder(rows), L["Your spellbook"]
	elseif q.class then
		for _, e in ipairs(CS.Rows(q.class, q.class == mine, true)) do
			if not q.level or RankAt(e, q.level) then rows[#rows + 1] = e end
		end
		note = L["%s spells"]:format(ns.Plain(rows[1] and rows[1].classShown or q.class))
	elseif #q.words > 0 then
		-- your class's first; else any class's
		for _, e in ipairs(mine and CS.Rows(mine, true, true) or {}) do if Has(e, q.words) then rows[#rows + 1] = e end end
		if #rows == 0 then
			for _, cls in ipairs(CS.CLASSES) do
				if cls ~= mine then for _, e in ipairs(CS.Rows(cls, false)) do if Has(e, q.words) then rows[#rows + 1] = e end end end
			end
		end
		note = L["When it's learned"]
	elseif mine then
		local want = q.level
		local all = CS.Rows(mine, true, true)
		if q.upcoming then
			-- the next level you learn anything new at (a spell, or a rank of one)
			for _, e in ipairs(all) do
				for _, r in ipairs(rawget(e, "_s").ranks) do
					if r[2] > lvl and (not want or r[2] < want) and not CS.Known(r[1]) then want = r[2] end
				end
			end
		end
		for _, e in ipairs(want and all or {}) do
			if RankAt(e, want, q.upcoming) then rows[#rows + 1] = e end
		end
		note = want and L["Your spells at level %d"]:format(want) or L["Your spells"]
	end
	table.sort(rows, function(a, b)
		if a.level ~= b.level then return a.level < b.level end
		return a.name < b.name
	end)
	if #rows == 0 then
		return { NoteRow(q.upcoming and L["Nothing new to learn above your level"] or L["No spell that fits"]) }, note
	end
	return ns.ScoreInOrder(rows), note
end

function Q.ToAdvanced(q)
	if q.known then return "@spell is:known " end
	-- (as said, 0.55.7: the next level you learn something new at, which lvl:N+ didn't say, nor "when do i learn":
	-- your class's first. Search.lua's ns.QuestionToAdvanced)
	if q.upcoming or (not q.class and #(q.words or {}) > 0) then return nil end
	local parts = { "@spell" }
	if q.class then parts[#parts + 1] = "class:" .. Lower(q.class)
	else parts[#parts + 1] = "class:mine -is:known" end
	if q.level then parts[#parts + 1] = "lvl:" .. q.level
	elseif q.upcoming then
		local lvl = ns.Safe(UnitLevel, "player")
		if type(lvl) == "number" then parts[#parts + 1] = "lvl:" .. (lvl + 1) .. "+" end
	end
	for _, w in ipairs(q.words or {}) do parts[#parts + 1] = w end
	return table.concat(parts, " ") .. " "
end

----------------------------------------------------------------------
-- "where do i learn daggers" without What's Training (0.54.1, a player using another trainer addon): the weapon skills
-- as a list a chain starts from (no search lists them), and > learn on one: its weapon masters, the nearest first
----------------------------------------------------------------------

local P = ns.Pipes
local skillRows
--- The weapon skills, one row each (their names in your language); none while What's Training's own rows stand in.
P.LISTS.weaponskills = function()
	local WT = ns.WhatsTraining
	if WT and WT.Api and WT.Api() and ns.providers.training then return {} end
	if not skillRows then
		skillRows = {}
		for _, id in ipairs(ns.Filters.WEAPON_SKILL_IDS or {}) do
			local name = ns.Str(ns.Safe(C_Spell and C_Spell.GetSpellName, id))
			if name then
				skillRows[#skillRows + 1] = { key = "weaponskill:" .. id, kind = "weaponskill", name = name, skillId = id,
					_lname = Lower(name), icon = ns.Safe(C_Spell and C_Spell.GetSpellTexture, id) }
			end
		end
	end
	return skillRows
end
function CS.ForgetSkillRows() skillRows = nil end -- (tests)

ns:RegisterRelation("learn", {
	aliases = { "taught", "trainer", "trainers" },
	desc = L["where a weapon skill is taught: its weapon masters"],
	seedAlso = { "weaponskills" },
	applies = function(e) return e.kind == "weaponskill" end,
	run = function(rows)
		local I = ns.Integrations
		local WT = ns.WhatsTraining
		local out = {}
		for _, e in ipairs(rows) do
			local _, list = CS.WeaponMasters({ e.skillId })
			local masters = {}
			for _, t in ipairs(list or {}) do masters[#masters + 1] = WT and WT.MasterRow and WT.MasterRow(t, e) end
			table.sort(masters, function(a, b)
				local da, db = rawget(a, "_dist"), rawget(b, "_dist")
				if (da ~= nil) ~= (db ~= nil) then return da ~= nil end
				if da and db and da ~= db then return da < db end
				return tostring(a.name) < tostring(b.name)
			end)
			for _, r in ipairs(masters) do out[#out + 1] = r end
		end
		return out
	end,
})
