local ns = select(2, ...)

-- The plain-word questions and chains (Scan.ANSWERS), answered before any search: their one list, the order a line is
-- read as one (Scan.ReadQuestion, for the answer and for Alt+`), their rows filtered and sorted as a search's
-- (Scan.AnswerView). Moved out of Search.lua as it was.

local Scan = ns.UI._Scan
local function EasyOn() return ns.Easy ~= nil and ns.Easy.On() end
local EASY_NONE, PseudoEntries = Scan.EASY_NONE, Scan.PseudoEntries

-- The plain-word questions and chains, answered before any search, in this order. Each: `ask(text, converting)` gives
-- what the line asks (and a second value for answer/toAdvanced) or nil when it isn't its kind; `answer` gives rows and
-- the footer's note (true third: the note is a chain's path); `toAdvanced` the same question as Advanced mode writes it
-- (Alt+`, Easy.ToAdvanced). One list for both (review, 0.53.6: Easy.lua kept its own copy in the same order by hand,
-- and the two had drifted before).
local function Asks(name) -- a module with Question, Answer and ToAdvanced of its own (ns[name])
	return {
		ask = function(text) -- (both its values: the zones' level said, "where should i level at 30")
			local m = ns[name]
			if m and m.Question then return m.Question(text) end
		end,
		answer = function(q, extra) return ns[name].Answer(q, extra) end,
		toAdvanced = function(q, extra) return ns[name].ToAdvanced(q, extra) end,
	}
end
local function Words(list) return #list > 0 and (table.concat(list, " ") .. " ") or "" end
Scan.ANSWERS = {
	-- "what should i do", "what now", "suggestions": what's worth doing now (Search/Questions/Suggest.lua; first: its lines are its own)
	Asks("Suggest"),
	-- "untrack quests", "track completed quests", "track rfc quests only", "untrack red quests": QuestTrack.lua (its
	-- lines start with what to do)
	Asks("QuestTrack"),
	-- "history", "my history", "recent searches": what you ran, newest first (Providers/History.lua)
	Asks("History"),
	-- "quests to turn in", "turn in quests": your quest log's ready ones; "quests here": Questie's at your level in
	-- your zone (Search/Questions/Suggest.lua)
	Asks("TurnIn"),
	Asks("QuestsHere"),
	Asks("CanCraft"),
	-- "what should i auction": your bag items worth more on the auction house, with Auctionator (AuctionValues.lua;
	-- before the auctions' question: "what can i sell on the ah" isn't about what you've posted)
	Asks("AuctionatorQ"),
	Asks("AhUpgradesQ"), -- ("ah upgrades", "cheapest upgrades on the ah": AuctionValues.lua, 0.66.13)
	Asks("AhValueQ"), -- ("ah value of my mats": "@mats | sum ahvalue", ahead of the chains' "... mats")
	-- "what is in my bank": this character's bank (@bank, Providers/Stored.lua)
	Asks("MyBankQ"),
	-- "mounts", "my pets", "toys", "favorite mounts", "raptor mounts": the list, by name (Providers/Collections.lua)
	Asks("CollectionsQ"),
	-- "buyback", "what did i sell": what you sold since you logged in (Providers/Buyback.lua)
	Asks("BuybackQ"),
	-- "what dropped", "what did we get", "what did i loot": LootLog.lua (before chains: "what drops did we get" isn't "what drops <item>")
	{ ask = function(text) return ns.LootLog and ns.LootLog.Question(text) end,
		answer = function(q) return ns.LootLog.Answer(q) end,
		toAdvanced = function(q)
			return "@drop " .. ((q.who == "me" and "is:mine ") or (q.who and ("looter:" .. ns.Lower(q.who):gsub("%s+", "_") .. " ")) or "")
		end },
	-- "how do i get into mc", "how do i get attuned to onyxia": its steps (Attunements.lua; before the chains, whose "how
	-- do i get" is where to get an item)
	{ ask = function(text) local Q = ns.Attune and ns.Attune.Q return Q and Q.How(text) end,
		answer = function(q) return ns.Attune.Q.Answer(q) end,
		toAdvanced = function(q) return ns.Attune.Q.ToAdvanced(q) end },
	-- "spellid claw", "spell id 1082": SpellIds.lua (before the chains and searches: the words are a spell's name)
	{ ask = function(text) local S = ns.SpellIds return S and S.Question(text) end,
		answer = function(q) return ns.SpellIds.Answer(q) end,
		toAdvanced = function(q) return ns.SpellIds.ToAdvanced(q) end },
	-- "healing talents", "shaman crit talents", "druid regen talents": talents by what they do (Search/Questions/Talents.lua; before
	-- the chains and searches: "talents for crit" isn't a chain, "crit" and "healing" aren't an item's stats here)
	{ ask = function(text) local Q = ns.TalentsQ return Q and Q.Question(text) end,
		answer = function(q) return ns.TalentsQ.Answer(q) end,
		toAdvanced = function(q) return ns.TalentsQ.ToAdvanced(q) end },
	-- a chain ("thorium belt > mats", "mats for thorium belt"): Chains.lua. (Simple mode takes only the plain words: a ">"
	-- typed there is refused like any Advanced syntax; written for Advanced mode, a ">" chain is one too)
	-- (a ">" chain runs whichever way it came, in either mode; 0.55.4)
	{ ask = function(text) return ns.Pipes and ns.Pipes.Canonical(text) end,
		answer = function(chain)
			local rows, trail = ns.Pipes.Search(chain)
			return rows, trail, true
		end,
		toAdvanced = function(chain) return chain .. " " end },
	-- "what killed me", "who crit me": CombatLog.lua
	{ ask = function(text) return ns.CombatLog and ns.CombatLog.Question(text) end,
		answer = function(q) return ns.CombatLog.Answer(q) end,
		toAdvanced = function(q)
			return "@combatlog is:mine " .. ((q == "killed" and "is:death") or (q == "crit" and "is:taken sort:damage") or "is:dealt sort:damage") .. " "
		end },
	-- "where should i level", "what dungeon should i do", "where should i fish": Zones.lua
	Asks("Zones"),
	-- "spells not on my bars": Spells.lua
	{ ask = function(text) return ns.Spells and ns.Spells.Question(text) end,
		answer = function(q) return ns.Spells.Answer(q) end,
		toAdvanced = function(q) return "@spell is:unplaced " .. Words(q) end },
	-- "blacksmithing recipes i'm missing", "recipes i can learn now": MissingRecipes.lua (before the group's: "who is missing
	-- recipes" is about recipes)
	{ ask = function(text) return ns.MissingRecipes and ns.MissingRecipes.Question(text) end,
		answer = function(q) return ns.MissingRecipes.Answer(q) end,
		toAdvanced = function(q)
			local rest = {}
			for _, n in ipairs(q.profs) do rest[#rest + 1] = ns.Lower(n) end
			for _, w in ipairs(q.words) do rest[#rest + 1] = w end
			return "@recipe " .. (q.learnable and "is:learnable" or "is:unknown") .. " " .. Words(rest)
		end },
	-- "what can i train in tailoring", "tailoring training", "profession training": the recipes a trainer teaches you
	-- don't know (Search/Questions/ProfTraining.lua; before What's Training's, whose "what can i train" is your class's spells)
	Asks("ProfTraining"),
	-- "what can i train", "what do i learn next level", "how much is training", "when do i learn fireball": What's
	-- Training's spells (WhereToLearn.lua; after the recipes': "recipes i can learn" is theirs)
	{ ask = function(text) local Q = ns.WhatsTraining and ns.WhatsTraining.Q return Q and Q.Question(text) end,
		answer = function(q) return ns.WhatsTraining.Q.Answer(q) end,
		toAdvanced = function(q) return ns.WhatsTraining.Q.ToAdvanced(q) end },
	-- "druid spells", "upcoming spells", "when do i learn travel form": every class's spells (Search/Questions/ClassSpells.lua;
	-- after What's Training's, which answers for your class when it's there)
	{ ask = function(text) local Q = ns.ClassSpells and ns.ClassSpells.Q return Q and Q.Question(text) end,
		answer = function(q) return ns.ClassSpells.Q.Answer(q) end,
		toAdvanced = function(q) return ns.ClassSpells.Q.ToAdvanced(q) end },
	-- "blacksmithing plan", "level blacksmithing", "leveling plan": Plan.lua (sort:plan's question)
	Asks("Plan"),
	-- "quests to drop", "grey quests": QuestDrop.lua
	{ ask = function(text) return ns.QuestDrop and ns.QuestDrop.Question(text) end,
		answer = function(q) return ns.QuestDrop.Answer(q) end,
		toAdvanced = function(q)
			local which = (q.grey and "is:grey -is:complete") or (q.behind and "is:leftbehind -is:complete") or "is:drop"
			return "@quest " .. which .. " " .. Words(q.words)
		end },
	-- "party quests", "quests to share", "same quests as my group": GroupQuests.lua (before the group's: "party members
	-- missing quests" is about quests)
	Asks("GroupQuests"),
	-- "my lockouts", "raid lockouts", "am i saved", "raid id": Lockouts.lua
	Asks("Lockouts"),
	-- "where is my body", "my corpse", "where did i die": Corpse.lua (and the nearest spirit healers)
	Asks("Corpse"),
	-- "durability", "repair cost", "what needs repair", "broken gear": Durability.lua
	Asks("Durability"),
	-- "my auctions", "what am i selling", "auctions sold": Auctions.lua (never with a mail word: "auction mail" is the mail's)
	Asks("Auctions"),
	-- "my mail", "mail running out", "cod mail": Mail.lua
	Asks("Mail"),
	-- "who is dead", "who needs fortitude", "who is out of range", "group healers": Group.lua
	Asks("Group"),
	-- "quest upgrades", "quests with upgrades": the quests near your level whose reward is an upgrade (Rewards.lua)
	{ ask = function(text)
			local R = ns.QuestRewards
			return R and R.UpgradeQuestion and R.UpgradeQuestion(text) or nil
		end,
		answer = function() return ns.QuestRewards.UpgradeAnswer() end,
		toAdvanced = function() return ns.QuestRewards.UpgradeToAdvanced() end },
	-- "upgrades i can buy", "vendor upgrades": the friendly vendors selling an upgrade for you (Rewards.lua; 0.66.12)
	{ ask = function(text)
			local R = ns.QuestRewards
			return R and R.BuyQuestion and R.BuyQuestion(text) or nil
		end,
		answer = function() return ns.QuestRewards.BuyAnswer() end,
		toAdvanced = function() return ns.QuestRewards.BuyToAdvanced() end },
	-- "outlaw sabre quest", "quest for outlaw sabre": the quests rewarding it (Rewards.lua; only when the words name a
	-- quest reward, and no quest is called that)
	-- "quests that reward bags", "bag quests" (Rewards.lua; before the one by an item's name: "bags" names no item)
	{ ask = function(text) return ns.QuestRewards and ns.QuestRewards.BagQuestion(text) end,
		answer = function(q) return ns.QuestRewards.BagAnswer(q) end,
		toAdvanced = function(q) return ns.QuestRewards.BagToAdvanced(q) end },
	{ ask = function(text) return ns.QuestRewards and ns.QuestRewards.Question(text) end,
		answer = function(q) return ns.QuestRewards.Answer(q) end,
		toAdvanced = function(q) return ns.QuestRewards.ToAdvanced(q) end },
	-- "my attunements", "raid attunements", "my keys", "class quests": Attune's list (Attunements.lua; late: "dungeon quests
	-- to share", "grey dungeon quests" are the group's and the quest log's)
	{ ask = function(text) local Q = ns.Attune and ns.Attune.Q return Q and Q.List(text) end,
		answer = function(q) return ns.Attune.Q.Answer(q) end,
		toAdvanced = function(q) return ns.Attune.Q.ToAdvanced(q) end },
	-- "holidays", "what's on this week", "today", "next darkmoon faire", "my invites": Calendar.lua (last: its words name
	-- what's on the calendar, or it's a search)
	(function() local a = Asks("Calendar"); a.ownDates = true; return a end)(), -- (its own today, this week: 0.66.8 review)
	-- "quests per zone", "items by quality": searched as "@questie | group by zone" (Suggest.lua; UI/Results.lua's
	-- TakeAggregate). Last: a line another question takes is that one's ("lockouts by raid": @lockout's)
	(function() local a = Asks("PerField"); a.perField = true; return a end)(),
}

--- A plain-word question or chain as Advanced mode writes it (Alt+`: Easy.ToAdvanced), or nil when the line is none.
--- (0.55.7, the search's rewrite: a question whose answer no search gives, ranked or gathered its own way, "where should i
--- level" by how well each zone fits, "my mail" with the auction house's news, stays as it was said: its toAdvanced says
--- nil. Questions are answered in Advanced mode too, so what's written finds what was shown; "@map lvl:23" didn't.)
function ns.QuestionToAdvanced(text)
	-- ("items by zone q:rare": its filters before its step, as the search runs it: Suggest.lua's PF.Line)
	local per = ns.PerField and ns.PerField.Line and (ns.PerField.Line(text))
	if per then return per end
	return ns.QuestionToAdvancedOf(text)
end
--- The question's line with the filters and sorts typed after it: before its ">>"/">>>" part, where the search reads
--- them (0.63.7, review: "untrack quests is:red" was written "@quest >>> untrack is:red", which untracked them all).
local function WithTail(line, tail)
	local tailText = table.concat(tail, " ")
	local head, send = line:match("^(.-)%s+(>>.-)%s*$")
	if head then return head .. " " .. tailText .. " " .. send .. " " end
	return (line:gsub("%s+$", "")) .. " " .. tailText .. " "
end
Scan.WithTail = WithTail

function ns.QuestionToAdvancedOf(text)
	-- (the line read as Scan.Answer reads it, Scan.ReadQuestion: the question's form, then what was typed after it)
	local line, tail = Scan.ReadQuestion(text, function(t)
		for _, a in ipairs(Scan.ANSWERS) do
			local q, extra = a.ask(t, true)
			if q then
				local out = a.toAdvanced(q, extra)
				if out == nil then out = (t:gsub("^%s+", ""):gsub("%s+$", "")) .. " " end
				return out, a
			end
		end
	end)
	if line and tail then return WithTail(line, tail) end
	return line
end

--- Does a question other than "per field"'s take this line? (Suggest.lua's PF.Line: "lockouts by raid" stays @lockout's)
function ns.PerFieldTaken(text)
	for _, a in ipairs(Scan.ANSWERS) do
		if a.perField then return false end
		local ok, q = pcall(a.ask, text)
		if ok and q then return true end
	end
	return false
end

--- A chain or a question in plain words: its own answer (Scan.ANSWERS), not a search. The rows, or nil.
--- (0.55.7, the search's rewrite: an answer is filtered and sorted as a search is: Advanced filters and sorts typed after
--- the question, "my auctions q:rare+ sort:value", and Simple mode's bar; Scan.AnswerView. Its group was already: "| group
--- by" sums up any rows.)
function Scan.Answer(self, text)
	local rows, tail = Scan.ReadQuestion(text, function(t) return Scan.Ask(self, t) end)
	if rows then return Scan.AnswerView(self, rows, tail) end
	return nil
end

--- How a line is read as a question, the same for its answer (Scan.Answer) and its Advanced form (Alt+`,
--- ns.QuestionToAdvancedOf): ask(t) -> what the question gives (nil: none takes t), the question (Scan.ANSWERS' entry).
--- Tried in this order: a chain, with the sorts typed after it ("deadmines > steps sort:line": only sorts, a filter at
--- the end is the last step's own; 0.55.21); dates said after a question ("loot today", "my auctions sold this week":
--- its filters, before the question reads them as its own little words; not the calendar's, whose today is its own:
--- 0.66.8 review); the line; the line with the Advanced filters and sorts typed after it ("my auctions q:rare+
--- sort:value"); dates and numbers said in words after it ("what killed me today": "what killed me since:today";
--- 0.66.8). Gives what ask gave and the words typed after the question (nil: none), or nil.
--- The line with what its plain stage read said as filters ("loot today" -> "loot since:today"), read off the line's
--- reading (Phrase.lua, kept for the frame: the search reads the same one next), not the line split again; dates: only
--- the dates' recognizer asked (as E.PlainDates); the line itself when nothing was read.
local DATES = { dates = true }
local function PlainSaid(text, dates)
	local r = ns.Phrase.ReadLine(text, { simple = true, parse = true, only = dates and DATES or nil })
	local out, any = {}, false
	for k, t in ipairs(r.toks) do
		local c = r.taken[k]
		if c and c.kind == "plain" then
			if c.from == k then
				for _, w in ipairs(c.words) do out[#out + 1] = w end
				any = true
			end
		else
			out[#out + 1] = t.text
		end
	end
	return any and table.concat(out, " ") or text
end

function Scan.ReadQuestion(text, ask)
	-- (a quest's or an NPC's whole name asked like a question, "What Is Going On?", "Who Is Stealing Our Cats?": the
	-- name, searched; three words or more, or a "?", so "mounts" or "my mail" are still asked; 0.68.19)
	local I = ns.Integrations
	if EasyOn() and I and I.IsName and (text:find("?", 1, true) or select(2, text:gsub("%S+", "")) >= 3) and I.IsName(text) then
		return nil
	end
	if text:find(">", 1, true) then
		local rest, tail = Scan.SplitTail(text, true)
		local got = rest and ask(rest)
		if got then return got, tail end
	end
	if EasyOn() then
		local dated = PlainSaid(text, true)
		if dated ~= text then
			local rest, dtail = Scan.SplitTail(dated)
			local got, a
			if rest then got, a = ask(rest) end
			-- (a question that takes "today" as one of its little words, "loot today": its rows, the dates on them)
			local whole = false
			if not got and dtail then got, a = ask(text); whole = true end
			if got and not a.ownDates then return got, dtail end
			-- (the calendar's, asked the whole line: as below, not asked again; review)
			if got and whole then return got, nil end
		end
	end
	local got = ask(text)
	if got then return got, nil end
	local rest, tail = Scan.SplitTail(text)
	if rest then got = ask(rest) end
	if got then return got, tail end
	if EasyOn() then
		local again = PlainSaid(text)
		if again ~= text then
			rest, tail = Scan.SplitTail(again)
			if rest then got = ask(rest) end
			if got then return got, tail end
		end
	end
	return nil
end

--- The Advanced filters and sorts at the end of a line ("my auctions q:rare+ sort:value"): the line before them, and
--- them (nil: none, or a chain, whose last step takes its own).
function Scan.SplitTail(text, sortsOnly)
	local F = ns.Filters
	if not (F and F.Parse) or (text:find(">", 1, true) and not sortsOnly) then return nil end
	local words = {}
	for w in text:gmatch("%S+") do words[#words + 1] = w end
	local tail = {}
	while #words > 1 do
		local w = words[#words]
		local so = F.SortOf and F.SortOf(w)
		if w:find(":", 1, true) and w:sub(1, 1) ~= "@" and (so or (not sortsOnly and F.Parse(w))) then
			table.insert(tail, 1, w)
			words[#words] = nil
		else
			break
		end
	end
	if #tail == 0 then return nil end
	return table.concat(words, " "), tail
end

--- A question's rows filtered and sorted: by the Advanced words after it (tail) and Simple mode's bar. Lines that aren't
--- results (a heading, a note) stay; the results between two of them are sorted among themselves (B.Order), or all of
--- them by distance (nearest first). Nothing left: a line saying so, under the answer's own lines on top.
function Scan.AnswerView(self, rows, tail)
	local F, B = ns.Filters, ns.Bar
	if not (F and B) then return rows end
	local filters, sort = {}, nil
	for _, w in ipairs(tail or {}) do
		local so = F.SortOf and F.SortOf(w)
		if so then sort = so else filters[#filters + 1] = F.Parse(w) end
	end
	local bar = EasyOn() and B.Active()
	if bar then
		for _, w in ipairs(bar.filters) do filters[#filters + 1] = F.Parse(w) end
		sort = bar.sort or sort
	end
	if #filters == 0 and not sort then return rows end
	local Real = B.Real
	local out, kept, any, dropped = {}, {}, false, false
	for _, e in ipairs(rows) do
		if not Real(e) then out[#out + 1] = e
		elseif #filters == 0 or F.Pass(e, filters) then out[#out + 1] = e; kept[#kept + 1] = e; any = true
		else dropped = true end
	end
	-- (the row on top that does it to them all, "Untrack 4 quests", "Drop all 5": made again for the ones left; 0.63.7,
	-- review: "untrack quests is:red" showed two and untracked all four)
	if dropped and any then
		local again = {}
		for _, e in ipairs(out) do
			local replan = type(e) == "table" and rawget(e, "replan")
			if replan then
				local row = replan(kept)
				if row then row._score = e._score; again[#again + 1] = row end
			else
				again[#again + 1] = e
			end
		end
		out = again
	end
	if not any then
		local head = {}
		for _, e in ipairs(out) do if type(e) == "table" and (e.lead or e.raw) then head[#head + 1] = e end end
		head[#head + 1] = PseudoEntries({ EASY_NONE })[1]
		return head
	end
	local sortBase, sortRev = ns.Filters.SortParts(sort)
	if sortBase == "distance" then
		local I = ns.Integrations
		local here = I and I.Here and I.Here()
		if not here then self.noPosition = true return out end
		local real, other = {}, {}
		for _, e in ipairs(out) do if Real(e) then real[#real + 1] = e else other[#other + 1] = e end end
		real = Scan.NearestViews(real, here, true, Scan.Budget(self), sortRev)
		-- (in their order: the views say it in their scores, which an answer isn't sorted by; 0.65.x review)
		for i, e in ipairs(real) do e._ord = i end
		table.sort(real, function(a, b)
			local sa, sb = tonumber(a._score) or 0, tonumber(b._score) or 0
			if sa ~= sb then return sa > sb end
			return a._ord < b._ord
		end)
		for _, e in ipairs(real) do other[#other + 1] = e end
		return other
	elseif sort then
		return B.Order(out, sort)
	end
	return out
end

--- The question's own answer (Scan.ANSWERS), as it gives it: the rows, or nil.
function Scan.Ask(self, text)
	for _, a in ipairs(Scan.ANSWERS) do
		local q, extra = a.ask(text)
		local rows, note, isTrail
		if q then rows, note, isTrail = a.answer(q, extra) end
		if rows then
			self.noPosition, self.action, self.place = nil, nil, nil
			if self.categoryAuto then self.category, self.categoryAuto = nil, nil end
			self.posTokens = {}
			if isTrail then self.pipeTrail = note else self.answerNote = note end
			-- (an answer's rows aren't scored: letters a search marked on them before ("@mail bob", then "my mail") are
			-- forgotten, worked out again when drawn: none, with nothing typed to mark)
			for i = 1, #rows do
				local e = rows[i]
				if type(e) == "table" and rawget(e, "_pos") ~= nil then e._pos = nil end
			end
			return rows, a
		end
	end
end
