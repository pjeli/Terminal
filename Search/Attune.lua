local ns = select(2, ...)
local L = ns.L

-- Attune's attunements in searches (0.50.2; the rows themselves: Providers/Integrations/Attune.lua):
--
--   molten core > steps          an attunement's steps, first to last, each line of quests in turn ("steps for mc",
--                                "how do i get into mc", "how do i get attuned to onyxia")
--   attunement to the core > attunement   the attunements a quest, item or NPC is a step of
--   "my attunements", "raid attunements", "attunements to do", "keys", "class quests", "druid class quests", "am i
--   attuned to mc": @attune with is:raid / is:dungeon / is:key / is:class / is:done / is:todo / class:<class>

local AT = ns.Attune
local P = ns.Pipes
local Lower = ns.Lower

local function Rows()
	local p = ns.providers.attune
	return p and ns:GetEntries(p) or {}
end

local function RecTarget(e)
	if type(e) ~= "table" or e.kind ~= "attune" then return nil end
	local idx = AT.Index()
	if not idx then return nil end
	if e.isStep then return e.linkAttune and idx.byId[tostring(e.linkAttune)] or nil end
	return idx.byId[tostring(e.attuneId)]
end

----------------------------------------------------------------------
-- The chains
----------------------------------------------------------------------

if ns.RegisterRelation then
	local function Available() return ns.providers.attune ~= nil end
	ns:RegisterRelation("steps", {
		aliases = { "step", "attunesteps" },
		desc = L["an attunement's steps, first to last (Attune)"],
		available = Available, addon = "Attune",
		seedKinds = { "attune" },
		seedNone = L["No attunement called \"%s\" that Attune lists for you"],
		-- (an attunement with steps, or a step that's another attunement: that one's)
		applies = function(e)
			local rec = RecTarget(e)
			return rec ~= nil and #rec.steps > 0
		end,
		run = function(rows)
			local out = {}
			for _, e in ipairs(rows) do
				local rec = RecTarget(e)
				if rec then
					for _, r in ipairs(AT.StepRows(rec, L["a step of %s"]:format(AT.RowName(rec)))) do out[#out + 1] = r end
				end
			end
			return out
		end,
	})

	-- what an attunement needs a row for: a quest (Questie's, your log's, a step's), an item, an NPC
	local function Needs(e)
		local idx = AT.Index()
		if not (idx and type(e) == "table") then return nil end
		local QR = ns.QuestRewards
		local q = (QR and QR.QuestIdOf and QR.QuestIdOf(e))
		local found = q and idx.byQuest[q]
		if found then return found end
		local item = P.ItemOf(e)
		found = item and idx.byItem[item]
		if found then return found end
		local npc = e.kind == "npc" and e.npcID or (e.kind == "attune" and e.npcID) or nil
		return npc and idx.byNpc[npc] or nil
	end
	ns:RegisterRelation("attunement", {
		aliases = { "attunements", "attune" },
		desc = L["the attunements a quest, item or NPC is a step of (Attune)"],
		available = Available, addon = "Attune",
		-- (from a quest, yours or Questie's, or an item of yours; else a step of Attune's by that name: "core fragment",
		-- "darkmaster gandling")
		seedKinds = { "quests", "questie", "items" },
		seedFallback = function(text)
			local want = " " .. Lower(tostring(text)):gsub("'", ""):gsub("[%p]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "") .. " "
			local idx = AT.Index()
			local out = {}
			for _, rec in ipairs(idx and idx.list or {}) do
				for i, r in ipairs(rec.steps) do
					local n = " " .. Lower(r.title):gsub("'", ""):gsub("[%p]", " "):gsub("%s+", " ") .. " "
					if n == want then out[#out + 1] = AT.StepRows(rec)[i] end
				end
			end
			return out
		end,
		seedNone = L["No quest, item or step of an attunement called \"%s\""],
		applies = function(e) return Needs(e) ~= nil end,
		run = function(rows)
			local want = {}
			for _, e in ipairs(rows) do
				for _, aid in ipairs(Needs(e) or {}) do want[aid] = true end
			end
			local out = {}
			-- (what Attune lists for you: your faction's, your class's)
			for _, r in ipairs(Rows()) do
				if want[tostring(r.attuneId)] then out[#out + 1] = r end
			end
			return out
		end,
	})

	P.LABELS.steps, P.LABELS.attunement = "steps", "attunement"
	P.SIMPLE.steps = "steps for %s"
	P.SIMPLE_LABEL.steps, P.SIMPLE_LABEL.attunement = L["Steps for %s"], L["Attunements with %s"]
	P.SIMPLE_NONE.steps = L["Attune has no steps for %s"]
	P.SIMPLE_NONE.attunement = L["%s isn't a step of any attunement"]
	-- (the general phrases: "steps for mc", "molten core steps"; the questions about getting in are answered below)
	for _, ph in ipairs({ { "^steps for (.+)$", "steps" }, { "^steps of (.+)$", "steps" }, { "^(.+) steps$", "steps" } }) do
		table.insert(P.PHRASES, 1, ph)
		local f = ph[1]:match("^%^(%a[%a']*)")
		if f then P.FIRST[f] = true end
		local l = ph[1]:match("(%a+)%$$")
		if l then P.LAST[l] = true end
	end
end

----------------------------------------------------------------------
-- The question: "my attunements", "raid attunements", "keys", "class quests", "how do i get into mc"
----------------------------------------------------------------------

local Q = {}
AT.Q = Q

local FILL = {}
for w in ([[my me i am im the in a an of is are do does did have has any what whats which how show list check see all for
	on to still this that it its there theres we our was were be been got get can could with yet now currently
	attune attunes attunement attunements attuned]]):gmatch("%a+") do FILL[w] = true end
local CUE = { attune = true, attunes = true, attunement = true, attunements = true, attuned = true }
local GROUP = { raid = "raid", raids = "raid", dungeon = "dungeon", dungeons = "dungeon", key = "key", keys = "key" }
local STATE = { done = "done", finished = "done", completed = "done", complete = "done", todo = "todo", unfinished = "todo",
	incomplete = "todo", left = "todo", remaining = "todo", missing = "todo", need = "todo", needed = "todo", started = "todo" }
local QUEST = { quest = true, quests = true, questline = true, questlines = true, line = true, lines = true, chain = true,
	chains = true }
local STEPS = { step = true, steps = true }
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- the class a word names (English, or the client's own names), or nil
local function ClassOf(w)
	for _, c in ipairs(CLASSES) do
		if w == Lower(c) then return c end
		for _, t in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
			if type(t) == "table" and type(t[c]) == "string" and Lower(t[c]) == w then return c end
		end
	end
end

-- a word in a row's name (a word's start; apostrophes left out: "onyxias"), or its shorthand's full name ("mc")
local function Has(e, w)
	local hay = " " .. Lower(tostring(e.name)):gsub("'", ""):gsub("[%p]", " ") .. " "
	if hay:find(" " .. w, 1, true) then return true end
	for _, full in ipairs(ns.Shorthand and ns.Shorthand[w] or {}) do
		if hay:find(" " .. full:gsub("'", ""), 1, true) then return true end
	end
	return false
end
local function HasAll(e, words)
	for _, w in ipairs(words) do if not Has(e, w) then return false end end
	return true
end
Q.Has = Has

-- the rows named by these words (every word in the name), Attune's order
local function Named(words, keep)
	local out = {}
	if #words == 0 then return out end
	for _, e in ipairs(Rows()) do
		if HasAll(e, words) and (not keep or keep(e)) then out[#out + 1] = e end
	end
	return out
end

-- "how do i get into <x>", "how do i get attuned to <x>", "how do i get the <x> key": the steps of what lets you in
local HOW = {
	{ "^how do i get into (.+)$", "in" }, { "^how to get into (.+)$", "in" }, { "^how can i get into (.+)$", "in" },
	{ "^how do i enter (.+)$", "in" }, { "^how to enter (.+)$", "in" }, { "^how do i get in (.+)$", "in" },
	{ "^how do i get attuned to (.+)$", "any" }, { "^how do i get attuned for (.+)$", "any" }, { "^how to get attuned to (.+)$", "any" },
	{ "^how do i attune to (.+)$", "any" }, { "^how do i attune for (.+)$", "any" }, { "^how to attune to (.+)$", "any" },
	{ "^how do i get the (.+) key$", "key" }, { "^how do i get (.+) key$", "key" }, { "^how to get the (.+) key$", "key" },
	{ "^how to get (.+) key$", "key" },
}

local function Words(s)
	local out = {}
	for w in s:gmatch("%S+") do if not (w == "the" or w == "a" or w == "an") then out[#out + 1] = w end end
	return out
end

-- the names of Attune's steps (lowercase, marks left out), made once
local stepNames
--- Is the line (lowercase, marks left out) the start of a step's name, or part of it ("attunement to the core",
--- "attunement to th" while it's typed)?
function Q.NamesStep(t)
	if not t:find(" ", 1, true) then return false end
	if not stepNames then
		local idx = AT.Index()
		if not idx then return false end
		stepNames = {}
		for _, rec in ipairs(idx.list) do
			for _, r in ipairs(rec.steps) do
				stepNames[#stepNames + 1] = " " .. Lower(r.title):gsub("'", ""):gsub("[%p]", " "):gsub("%s+", " ") .. " "
			end
		end
	end
	for _, n in ipairs(stepNames) do
		if n:find(" " .. t, 1, true) then return true end
	end
	return false
end
function Q.Forget() stepNames = nil end -- (tests: Attune's data made again)

local function Clean(text)
	if not ns.providers.attune or type(text) ~= "string" or text:find("[@:>|]") or text:find("^%s*[%./]") then return nil end
	local t = Lower(text):gsub("'", ""):gsub("[%p]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return t ~= "" and t or nil
end
local function IsKey(e) return AT.RecOf(e) and AT.RecOf(e).group == "key" end

--- "how do i get into mc", "how do i get attuned to onyxia", "how do i get the scholomance key", "mc attunement steps":
--- { steps = the row's name } (its steps: asked before the chains, whose "how do i get" is where to get an item), or
--- nil when no attunement is named ("how do i get into deadmines": the dungeon's quests don't let you in).
function Q.How(text)
	local t = Clean(text)
	if not t then return nil end
	for _, h in ipairs(HOW) do
		local what = t:match(h[1])
		if what then
			local rows = Named(Words(what), h[2] == "key" and IsKey or nil)
			if h[2] == "in" then
				local into = {}
				for _, e in ipairs(rows) do
					local g = AT.RecOf(e) and AT.RecOf(e).group
					if g == "key" or g == "raid" or g == "misc" then into[#into + 1] = e end
				end
				rows = into
			end
			if #rows == 0 then return nil end
			return { steps = rows[1].name }
		end
	end
	-- "molten core attunement steps": an attunement word, a steps word, and a name
	local cue, steps, words = false, false, {}
	for w in t:gmatch("%S+") do
		if CUE[w] then cue = true
		elseif STEPS[w] then steps = true
		elseif not FILL[w] then words[#words + 1] = w end
	end
	if not (cue and steps and #words > 0) then return nil end
	local rows = Named(words)
	return #rows > 0 and { steps = rows[1].name } or nil
end

--- The rows a list question's words name: every word in the name, else in what its steps name (a word's start:
--- "attunement for core fragment"); every row when there are no words.
function Q.Match(q)
	local all, rows = Rows(), {}
	for _, e in ipairs(all) do
		if Q.Keeps(q, e) and HasAll(e, q.words) then rows[#rows + 1] = e end
	end
	if #rows == 0 and #q.words > 0 then
		for _, e in ipairs(all) do
			local ok = Q.Keeps(q, e)
			local hay = " " .. (e._ltext or "")
			for _, w in ipairs(q.words) do if ok and not hay:find(" " .. w, 1, true) then ok = false end end
			if ok then rows[#rows + 1] = e end
		end
	end
	return rows
end

--- "my attunements", "raid attunements", "attunements to do", "my keys", "class quests", "druid class quests", "am i
--- attuned to mc": { group, state, class, words }, or nil when the line isn't asking for Attune's list, or its words
--- name none of them ("what dungeon quests should i do", "attune options": other questions, or a search). Asked late,
--- after the zones', the group's and the quest log's questions.
function Q.List(text)
	local t = Clean(text)
	if not t then return nil end
	-- (a quest's name, "attunement to the core": a search for it, which finds its attunement too)
	if Q.NamesStep(t) then return nil end
	-- ("to do", "not done yet": to do)
	t = (" " .. t .. " "):gsub(" to do ", " todo "):gsub("^ ", ""):gsub(" $", "")
	local cue, keyCue, strong = false, false, false
	local q = { words = {} }
	local tokens = {}
	for w in t:gmatch("%S+") do tokens[#tokens + 1] = w end
	for i, w in ipairs(tokens) do
		local nxt, prev = tokens[i + 1], tokens[i - 1]
		local cls = ClassOf(w)
		if CUE[w] then
			cue = true
			if w ~= "attune" and w ~= "attunes" then strong = true end -- ("attune" alone: the addon, its command)
		elseif STEPS[w] then return nil -- (Q.How's, or a chain's: "steps for mc")
		elseif w == "class" and ((nxt and QUEST[nxt]) or (prev and QUEST[prev])) then q.group, cue, strong = "class", true, true
		elseif (w == "dungeon" or w == "dungeons") and nxt and QUEST[nxt] then q.group, cue, strong = "dungeon", true, true
		elseif GROUP[w] then
			q.group = GROUP[w]
			if q.group == "key" then keyCue = true end
		elseif STATE[w] then
			-- ("not done": to do)
			q.state = (prev == "not" and STATE[w] == "done") and "todo" or STATE[w]
		elseif w == "not" and nxt and STATE[nxt] then
			-- (read with the next word)
		elseif QUEST[w] then
			-- (the class's or the dungeon's quests: said above)
		elseif cls and q.group ~= "dungeon" then q.class = cls
		elseif not FILL[w] then q.words[#q.words + 1] = w end
	end
	if q.class and not q.group then
		-- ("warlock quests" alone is a search; "warlock class quests" was read above)
		if not cue then return nil end
		q.group = "class"
	end
	if not cue then
		-- keys: "my keys", "dungeon keys", "scholomance key"; never "keys" alone (your keyring's)
		if not keyCue then return nil end
		local said = false
		for _, w in ipairs(tokens) do if w == "my" or w == "dungeon" or w == "dungeons" then said = true end end
		if not said and #q.words == 0 then return nil end
		if #q.words > 0 and #Named(q.words, IsKey) == 0 then return nil end
		if q.group == "dungeon" then q.group = "key" end
	elseif not strong and not q.group and not q.state and #q.words == 0 then
		return nil -- ("attune" alone: a search, which finds the addon, its command and the attunements)
	end
	-- (words naming none of them: not this question; "attune settings", "dungeon quests to share")
	if #q.words > 0 and #Q.Match(q) == 0 then return nil end
	return q
end

--- Either question: Q.How's, else Q.List's.
function Q.Question(text) return Q.How(text) or Q.List(text) end

Q.NOTE = { raid = L["Raid attunements"], dungeon = L["Dungeon quests"], key = L["Keys"], class = L["Class quests"],
	misc = L["Attunements"] }

local NoteRow = ns.NoteRow

--- Does an @attune row pass the question's group, state and class?
function Q.Keeps(q, e)
	local rec = AT.RecOf(e)
	if not rec then return false end
	if q.group and rec.group ~= q.group then return false end
	if q.class and rec.a.CLASS ~= q.class then return false end
	if q.state then
		local pct = AT.Mine(rec)
		local done = pct ~= nil and pct >= 100
		if q.state == "done" and not done then return false end
		if q.state == "todo" and (done or #rec.keys == 0) then return false end
	end
	return true
end

--- The answer: the rows (a chain's for steps: rows, its trail, true), and the footer's note.
function Q.Answer(q)
	if q.steps then
		local rows, trail = P.Search(q.steps .. " > steps")
		return rows, trail, true
	end
	local rows, done = Q.Match(q), 0
	for i, e in ipairs(rows) do
		e._score = 1e6 - i
		local rec = AT.RecOf(e)
		local pct = rec and AT.Mine(rec)
		if pct and pct >= 100 then done = done + 1 end
	end
	local note = Q.NOTE[q.group or "misc"]
	if #rows == 0 then
		local none = (q.class and q.class ~= select(2, ns.Safe(UnitClass, "player")))
			and L["No class quests for that class: Attune lists your class's (its options can list every class's)"]
			or L["No attunement has that"]
		return { NoteRow(none) }, note
	end
	return rows, note .. "  ·  " .. L["%d of %d done"]:format(done, #rows)
end

--- The question as Advanced syntax (Alt+`): "@attune is:raid mc", "molten core > steps".
function Q.ToAdvanced(q)
	if q.steps then return q.steps .. " > steps " end
	local parts = { "@attune" }
	if q.group then parts[#parts + 1] = "is:" .. q.group end
	if q.state then parts[#parts + 1] = "is:" .. q.state end
	if q.class then parts[#parts + 1] = "class:" .. Lower(q.class) end
	for _, w in ipairs(q.words) do parts[#parts + 1] = w end
	return table.concat(parts, " ") .. " "
end
