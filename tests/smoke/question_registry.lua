-- The questions' registry (docs/QUESTIONS.md): every entry has an id, which question gets a line when several could
-- (Q.Ranked: `last`, `over`, the words understood, then the list's order), and every entry's examples are its own.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local Scan = UI._Scan
local Q = ns.Questions
local easy = ns.db.easyMode
ns.db.easyMode = true; UI:EasyChanged()
local unitLevel = _G.UnitLevel
_G.UnitLevel = function() return 30 end

local ok, err = pcall(function()
	-- [questions: ids] every entry has its own id; `over` names entries that exist
	do
		local seen, bad = {}, {}
		for i, a in ipairs(Scan.ANSWERS) do
			if type(a.id) ~= "string" or seen[a.id] then bad[#bad + 1] = tostring(a.id or ("#" .. i)) end
			seen[a.id or i] = true
		end
		for _, a in ipairs(Scan.ANSWERS) do
			for _, o in ipairs(a.over or {}) do if not seen[o] then bad[#bad + 1] = a.id .. " over " .. o end end
		end
		check(#Scan.ANSWERS > 50 and #bad == 0, "[questions: ids] every entry named once, every `over` an entry: " .. table.concat(bad, ", "))
		check(Q.ById("HaveQ") and Q.ById("HaveQ").id == "HaveQ" and Q.ById("nope") == nil, "[questions: ids] Q.ById")
	end

	-- [questions: ranking] the rule itself, over stand-ins: `last` loses, `over` wins outright, then the words
	-- understood, then the list's order
	do
		local function Fake(id, test, more)
			local a = { id = id, ask = function(t) return test(t) and {} or nil end, answer = function() return { { name = id } } end,
				toAdvanced = function() return nil end }
			for k, v in pairs(more or {}) do a[k] = v end
			return a
		end
		-- "zzqa one two": A wants all three words, B only "zzqa" (the rest a free slot)
		local A = Fake("zzA", function(t) return t == "zzqa one two" end)
		local B = Fake("zzB", function(t) return t:find("^zzqa ") ~= nil end)
		table.insert(Scan.ANSWERS, 1, B)
		table.insert(Scan.ANSWERS, 2, A)
		local r = Q.Ranked("zzqa one two")
		check(#r == 2 and r[1].a == A and r[1].n == 3 and r[2].n == 1,
			"[questions: ranking] the entry understanding more words wins, wherever it is in the list: " .. tostring(r[1] and r[1].a.id))
		B.over = { "zzA" }
		r = Q.Ranked("zzqa one two")
		check(r[1].a == B, "[questions: ranking] `over` wins outright")
		B.over, B.last = nil, true
		table.remove(Scan.ANSWERS, 2); table.insert(Scan.ANSWERS, 1, A) -- (A first, B second)
		local C = Fake("zzC", function(t) return t == "zzqa one two" end)
		table.insert(Scan.ANSWERS, 3, C)
		r = Q.Ranked("zzqa one two")
		check(r[1].a == A and r[2].a == C and r[3].a == B,
			"[questions: ranking] a tie: the earlier in the list; `last` after every other: " .. tostring(r[1].a.id) .. " " .. tostring(r[2].a.id) .. " " .. tostring(r[3].a.id))
		-- the answer asks them in that order: the first with rows answers, nil passes the line on
		A.answer = function() return nil end
		ns.db.easyMode = false; UI:EasyChanged()
		local res = UI:Search("zzqa one two")
		check(res[1] and res[1].name == "zzC", "[questions: ranking] an answer that says nil passes the line to the next: " .. tostring(res[1] and res[1].name))
		ns.db.easyMode = true; UI:EasyChanged()
		for k = #Scan.ANSWERS, 1, -1 do local x = Scan.ANSWERS[k] if x == A or x == B or x == C then table.remove(Scan.ANSWERS, k) end end
	end

	-- [questions: examples] each entry's examples are its own: when it takes one, it gets it; when it doesn't here (the
	-- harness lacks its data), no other entry takes it either. Two entries that understand an example as well must be
	-- settled by `over` (the list's order isn't a reason)
	do
		local wrong, ties, mine, unread = {}, {}, 0, 0
		for _, a in ipairs(Scan.ANSWERS) do
			for _, line in ipairs(a.examples or {}) do
				local r = Q.Ranked(line)
				local top = r[1]
				local owned = false
				for _, c in ipairs(r) do if c.a == a then owned = true end end
				if not owned then
					unread = unread + 1
					if top then wrong[#wrong + 1] = line .. " -> " .. tostring(top.a.id) .. " (" .. a.id .. "'s, not read here)" end
				elseif top.a ~= a then
					wrong[#wrong + 1] = line .. " -> " .. tostring(top.a.id) .. " (" .. a.id .. "'s)"
				else
					mine = mine + 1
					local second = r[2]
					if second and second.n == top.n and not second.a.last then
						local declared = false
						for _, o in ipairs(a.over or {}) do if o == second.a.id then declared = true end end
						if not declared then ties[#ties + 1] = line .. ": " .. a.id .. " = " .. second.a.id end
					end
				end
			end
		end
		io.write(("[questions: examples] %d answered by their entry, %d whose entry has no data here\n"):format(mine, unread))
		check(mine > 50 and #wrong == 0, "[questions: examples] every example is its entry's: " .. table.concat(wrong, "; "))
		check(#ties == 0, "[questions: examples] no example settled by the list's order: " .. table.concat(ties, "; "))
	end

	-- [questions: words understood] a free slot counts for less than a word a question knows: "how many mounts do i
	-- have" is the collections' (it knows "mounts"), "do i have mail" the mail's, "how many linen do i have" the count's
	do
		local function Top(line) local c = Q.Ranked(line)[1] return c and c.a.id end
		check(Top("how many mounts do i have") == "CollectionsQ" and Top("do i have mail") == "Mail"
			and Top("how many linen do i have") == "HaveQ",
			"[questions: words understood] " .. tostring(Top("how many mounts do i have")) .. " " .. tostring(Top("do i have mail")))
		local hv = Q.ById("HaveQ")
		local mounts = Q.Understood(hv, "how many mounts do i have")
		check(mounts == 5, "[questions: words understood] the count understands all but its slot: " .. tostring(mounts))
	end

	-- [questions: answer = Alt+`] a search question's answer is its line's search (docs/QUESTIONS.md, 4.1): typed in
	-- Simple mode it lists what its Alt+` line lists typed in Advanced mode, row for row; the filters typed after it go into
	-- the line; its note is the footer; nothing found: its own row. With sort:list, 150 rows in their list's order (not
	-- their names', not cut at 100)
	do
		local B = ns.Bar
		local saved = { providers = ns.providers, order = ns.providerOrder }
		ns.providers, ns.providerOrder = {}, {}
		local ROWS = {}
		for i = 1, 150 do ROWS[i] = { name = ("Thing %03d"):format(151 - i), key = i, quality = i % 5 } end
		ns.RankInOrder(ROWS)
		ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function() return ROWS end })
		ns:AliasesChanged()
		UI.lastScan, UI.lastExtra = nil, nil
		local LINE = { id = "zzLine",
			ask = function(t) local w = ns.QuestionText(t) return w and w:find("^zzq my things") and {} or nil end,
			line = function() return "@item sort:list " end, note = function() return "My things" end,
			empty = function() return { ns.NoteRow("None of your things") } end }
		table.insert(Scan.ANSWERS, 1, LINE)
		local function Shown()
			local t = {}
			for _, e in ipairs(UI.Results()) do if B.Real(e) then t[#t + 1] = tostring(e.name) end end
			return t
		end
		local function Typed(line, simple)
			ns.db.easyMode = simple; UI:EasyChanged()
			UI:Open(""); UI:SetQuery(line, #line); T.FlushAll()
			local rows, note, first = Shown(), UI.answerNote, UI.Results()[1]
			UI:Hide(); T.FlushAll()
			return rows, note, first
		end
		local simple, note = Typed("zzq my things", true)
		ns.db.easyMode = true; UI:EasyChanged()
		local adv = ns.QueryToAdvanced("zzq my things")
		local advanced = Typed(adv, false)
		check(adv == "@item sort:list ", "[questions: answer = Alt+`] Alt+` writes its line: " .. tostring(adv))
		check(#simple == 150 and simple[1] == "Thing 150" and simple[150] == "Thing 001" and table.concat(simple, ",") == table.concat(advanced, ","),
			"[questions: answer = Alt+`] the same rows, in the list's order, all 150: " .. #simple .. " " .. tostring(simple[1]) .. " / " .. #advanced)
		check(note == "My things", "[questions: answer = Alt+`] its note is the footer: " .. tostring(note))
		ns.db.easyMode = true; UI:EasyChanged()
		local tailAdv = ns.QueryToAdvanced("zzq my things q:4")
		local tailSimple = Typed("zzq my things q:4", true)
		local tailAdvanced = Typed(tailAdv, false)
		check(tailAdv == "@item q:4 sort:list " and #tailSimple == 30 and table.concat(tailSimple, ",") == table.concat(tailAdvanced, ","),
			"[questions: answer = Alt+`] a filter typed after it goes into its line: " .. tostring(tailAdv) .. " " .. #tailSimple .. "/" .. #tailAdvanced)
		local _, _, none = Typed("zzq my things q:6", true)
		check(none and none.name == "None of your things", "[questions: answer = Alt+`] nothing found: its own row: " .. tostring(none and none.name))
		-- (sort:list on rows with no rank: the order the list gives them; a sorted list with words is still cut to 100)
		for _, e in ipairs(ROWS) do e._rank = nil end
		ns.db.easyMode = false; UI:EasyChanged()
		local plain = UI:Search("@item sort:list")
		local firstReal
		for _, e in ipairs(plain) do if B.Real(e) then firstReal = firstReal or e end end
		check(firstReal and firstReal.name == "Thing 150", "[questions: sort:list] no rank: the list's order: " .. tostring(firstReal and firstReal.name))
		local worded = UI:Search("@item thing sort:list")
		local nWorded = 0
		for _, e in ipairs(worded) do if B.Real(e) then nWorded = nWorded + 1 end end
		check(nWorded == 100, "[questions: sort:list] with words: the best 100 as before: " .. nWorded)
		check(ns.Filters.SortOf("sort:list") == "list" and ns.Filters.SortOf("sort:order") == "list", "[questions: sort:list] its words")
		table.remove(Scan.ANSWERS, 1)
		ns.providers, ns.providerOrder = saved.providers, saved.order
		ns:AliasesChanged()
		UI.lastScan, UI.lastExtra = nil, nil
		ns.db.easyMode = true; UI:EasyChanged()
	end

	-- [questions: every search question] each entry's examples that its line answers here: the question typed in Simple
	-- mode lists the rows its Alt+` line lists typed in Advanced mode, row for row (docs/QUESTIONS.md, invariant 1)
	do
		local B = ns.Bar
		local function Shown(line, simple)
			ns.db.easyMode = simple; UI:EasyChanged()
			UI.lastScan, UI.lastExtra = nil, nil
			UI:Open(""); UI:SetQuery(line, #line); T.FlushAll()
			local t = {}
			for _, e in ipairs(UI.Results()) do if B.Real(e) then t[#t + 1] = tostring(e.kind) .. ":" .. tostring(e.name) end end
			UI:Hide(); T.FlushAll()
			return table.concat(t, " | ")
		end
		local n, differ = 0, {}
		for _, a in ipairs(Scan.ANSWERS) do
			for _, line in ipairs(a.examples or {}) do
				local c = Q.Ranked(line)[1]
				local own = c and c.a == a and a.line and a.line(c.q, c.extra)
				if own and not own:find("%s|%s") then
					n = n + 1
					ns.db.easyMode = true; UI:EasyChanged()
					local adv = ns.QueryToAdvanced(line)
					local simple, advanced = Shown(line, true), Shown(adv, false)
					if simple ~= advanced then differ[#differ + 1] = line .. " [" .. simple .. "] vs " .. adv .. " [" .. advanced .. "]" end
				end
			end
		end
		ns.db.easyMode = true; UI:EasyChanged()
		io.write(("[questions: every search question] %d examples answered by their line\n"):format(n))
		check(n >= 20 and #differ == 0, "[questions: every search question] the question and its Alt+` list the same: " .. n .. " " .. table.concat(differ, "; "))
	end

	-- [questions: sort:grey, prof:] the quest log's grey quests first, then by level, then by name; a recipe's own
	-- profession (Smelting's recipes are Mining's)
	do
		local rows = { { name = "B", kind = "quests", level = 5 }, { name = "C", kind = "quests", level = 3, grey = true },
			{ name = "A", kind = "quests", level = 5 }, { name = "D", kind = "quests", level = 1 } }
		ns.Bar.SortRows(rows, "grey")
		table.sort(rows, function(x, y) return x._score > y._score end)
		local order = {}
		for i, e in ipairs(rows) do order[i] = e.name end
		check(table.concat(order) == "CDAB", "[questions: sort:grey] grey, then level, then name: " .. table.concat(order))
		local mining = ns.Filters.Parse("prof:mining")
		check(mining({ kind = "recipes", profName = "Mining", name = "Smelt Copper" }) and not mining({ kind = "recipes", profName = "Tailoring" })
			and ns.Filters.Parse("prof:first_aid")({ profName = "First Aid" }), "[questions: prof:] the recipe's own profession")
	end

	-- [questions: quest filters] is:foryou (your race, class and side may take it), is:cantake (and you meet its needs),
	-- is:started (some progress), sort:cantake (those you can take first, then by level); 1.0.79
	do
		local QR, F = ns.QuestRewards, ns.Filters
		local save = { fy = QR.ForYou, mr = QR.MeetsRequires, prog = ns.Aggregate.Progress }
		QR.ForYou = function(id) return id ~= 2 end
		QR.MeetsRequires = function(id) return id ~= 3 end
		local A, B, C = { kind = "questie", qid = 1, key = 1, name = "A", level = 9 }, { kind = "questie", qid = 2, key = 2, name = "B", level = 1 },
			{ kind = "questie", qid = 3, key = 3, name = "C", level = 2 }
		local fy, ct = F.Parse("is:foryou"), F.Parse("is:cantake")
		check(fy(A) and not fy(B) and fy(C) and ct(A) and not ct(B) and not ct(C) and not fy({ kind = "items", key = 1 }),
			"[questions: quest filters] is:foryou / is:cantake")
		local rows = { C, B, A }
		ns.Bar.SortRows(rows, "cantake")
		table.sort(rows, function(x, y) return x._score > y._score end)
		check(rows[1] == A and rows[2] == B and rows[3] == C, "[questions: quest filters] sort:cantake: those you can take first, then by level: "
			.. rows[1].name .. rows[2].name .. rows[3].name)
		ns.Aggregate.Progress = function(e) return e.p end
		local st = F.Parse("is:started")
		check(st({ kind = "achievements", p = 0.5 }) and not st({ kind = "achievements", p = 0 }) and not st({ kind = "achievements" }),
			"[questions: quest filters] is:started: some progress")
		QR.ForYou, QR.MeetsRequires, ns.Aggregate.Progress = save.fy, save.mr, save.prog
		-- (reward:bag while the reward index is still read: said, so the search is made again; it stayed empty before)
		local idx, building = QR.Index, QR.Building
		QR.Index, QR.Building = function() return nil end, function() return true end
		F.loading = nil
		local bag = F.Parse("reward:bag")
		local passed = bag(A)
		QR.Index, QR.Building = idx, building
		check(not passed and F.loading == true, "[questions: quest filters] reward:bag while the index is read: says it's loading")
		F.loading = nil
	end

	-- [questions: own answers say why] an entry with no `custom` reason is a search question: it has a line, and every
	-- example it takes here is answered by it (docs/QUESTIONS.md, invariant 4)
	do
		local bad = {}
		for _, a in ipairs(Scan.ANSWERS) do
			if type(a.custom) ~= "string" then
				if not a.line then bad[#bad + 1] = a.id .. " (no line)" end
				for _, line in ipairs(a.examples or {}) do
					local c = Q.Ranked(line)[1]
					if c and c.a == a and not (a.line and a.line(c.q, c.extra)) then bad[#bad + 1] = a.id .. ": " .. line end
				end
			end
		end
		check(#bad == 0, "[questions: own answers say why] " .. table.concat(bad, ", "))
	end

	-- [questions: bags you can make] a recipe's bag is the bag it makes ("bigger bags", slots:; 1.0.80: recipes were
	-- left out, their rows have makesItem, not itemID)
	do
		local QR = ns.QuestRewards
		local save = { slots = QR.Slots, inst = C_Item.GetItemInfoInstant }
		QR.Slots = function(id) return id == 4245 and 14 or nil end
		C_Item.GetItemInfoInstant = function(id) if id == 4245 then return id, nil, nil, nil, nil, 1, 0 end return save.inst(id) end
		local made = QR.SlotsOfRow({ kind = "recipes", recipeID = 3813, makesItem = 4245, name = "Small Silk Pack" })
		local learn = QR.SlotsOfRow({ kind = "missing", recipeID = 3813, makesItem = 4245, name = "Small Silk Pack" })
		QR.Slots, C_Item.GetItemInfoInstant = save.slots, save.inst
		check(made == 14 and learn == 14, "[questions: bags you can make] a recipe's bag: " .. tostring(made) .. " / " .. tostring(learn))
	end

	-- [questions: step lines] a search question whose line has steps is read at the steps stage, its tail before the "|"
	do
		local SL = Q.StepLine
		local full, query, steps = SL("items by zone q:rare")
		check(full == "@item q:rare | group by zone " and query == "@item q:rare" and steps and steps[1] == "group by zone" and #steps == 1,
			"[questions: step lines] " .. tostring(full) .. " / " .. tostring(query) .. " / " .. tostring(steps and steps[1]))
		check(SL("lockouts by raid") == nil and SL("my mail") == nil and SL("@item | count") == nil,
			"[questions: step lines] another question's line, an own answer, Advanced: none")
		check(Scan.WithTail("@item | group by zone ", { "q:rare" }) == "@item q:rare | group by zone "
			and Scan.WithTail("@quest >>> untrack", { "is:red" }) == "@quest is:red >>> untrack "
			and Scan.WithTail("@a | first 3 >> party", { "x:y" }) == "@a x:y | first 3 >> party ",
			"[questions: step lines] Scan.WithTail: the words before the first step or send")
	end

	-- [questions: one search] the ranking is kept while a search runs, asked again outside one
	do
		local n = 0
		local A = { id = "zzCount", ask = function(t) if t == "zzqcount" then n = n + 1 return {} end end,
			answer = function() return { { name = "x" } } end, toAdvanced = function() return nil end }
		table.insert(Scan.ANSWERS, 1, A)
		Q.Ranked("zzqcount"); Q.Ranked("zzqcount")
		check(n == 2, "[questions: one search] outside a search: asked each time")
		n = 0
		Q.Begin(); Q.Ranked("zzqcount"); Q.Ranked("zzqcount"); Q.Finish()
		check(n == 1, "[questions: one search] inside one: asked once")
		table.remove(Scan.ANSWERS, 1)
	end

	-- [review 1.0.82] steps typed after a step question; the bar's group and "then by" in Alt+`; a quoted value after one
	do
		local full = Q.StepLine("items by quality | first 2")
		check(full == "@item | group by quality | first 2 ", "[review 1.0.82] steps typed after its own: " .. tostring(full))
		local rest, tail = Scan.SplitTail('quests to turn in zone:"the barrens"')
		check(rest == "quests to turn in" and tail and #tail == 1 and tail[1] == 'zone:"the barrens"',
			"[review 1.0.82] a quoted value after a question: " .. tostring(rest) .. " / " .. tostring(tail and tail[1]))
		check(Scan.WithTail('@quest is:done sort:list ', { 'zone:"the barrens"' }) == '@quest is:done zone:"the barrens" sort:list ',
			"[review 1.0.82] WithTail keeps a quoted value whole")
		local B = ns.Bar
		local saved = B.Save()
		ns.db.easyMode = true; UI:EasyChanged()
		B.state.group = "quality"
		local adv = ns.QueryToAdvanced("items by zone")
		check(adv:find("group by zone", 1, true) and not adv:find("group by quality", 1, true),
			"[review 1.0.82] the bar's group isn't written after a step question's own: " .. adv)
		B.state.group, B.state.sort, B.state.thenBy = nil, "level", "name"
		adv = ns.QueryToAdvanced("quests to turn in")
		check(adv:find("sort:level,name", 1, true), "[review 1.0.82] the bar's then-by in Alt+` of a question: " .. adv)
		check(B.SortWord({ sort = "distance", thenBy = "name" }) == "distance" and B.SortWord({ sort = "-level,name", thenBy = "zone" }) == "-level,zone",
			"[review 1.0.82] SortWord: never after distance, the first field kept")
		B.Restore(saved)
		ns.db.easyMode = easy; UI:EasyChanged()
	end
end)
_G.UnitLevel = unitLevel
ns.db.easyMode = easy; UI:EasyChanged()
if not ok then check(false, "questions: " .. tostring(err)) end
