local ns = select(2, ...)

-- The line read into the query (q): what SearchText's steps share (Scan.Parse, then Scan.ActionAndPlace and
-- Scan.Prepare), its filters kept together (Scan.AddFilter), Simple mode's action word, trainer words and roles, the
-- sentence's little words dropped. Moved out of Search.lua as it was.

local UI = ns.UI
local Scan = UI._Scan
local function EasyOn() return ns.Easy ~= nil and ns.Easy.On() end
local GROUP_QUESTS_GONE = Scan.GROUP_QUESTS_GONE

--- Simple mode: an action word ("use hearthstone", "nearest innkeeper"; Easy.ACTIONS) first, or a nearest-type one
--- last ("mining trainer nearby"), taken out of the tokens. The action and its word, or nil.
-- (an article before it: "the nearest mailbox", as top N leaves "the 3 nearest mailboxes"; 0.66.x, the player)
local ARTICLE = { the = true, a = true, an = true }
-- (what a request may start with before "nearest": passed over then, Scan.TakeAction)
local LEAD_IN = { where = true, ["where's"] = true, wheres = true, what = true, ["what's"] = true, whats = true, is = true,
	are = true, find = true, show = true, me = true, get = true, take = true, to = true, i = true, need = true, want = true,
	please = true, pls = true, ["i'm"] = true, im = true, looking = true, ["for"] = true }
-- (said last, meaning nearest: Scan.TakeAction)
local NEAR_ME = { ["near me"] = true, ["around me"] = true, ["close by"] = true, ["near by"] = true }
--- (src: each token's source, Parse's q.tokenSrc, taken out with them; the third result: the words' sources taken)
function Scan.TakeAction(tokens, filters, src)
	local first = 1
	while first < #tokens and ARTICLE[tokens[first]] do first = first + 1 end
	-- (a request's lead-in, when "nearest" follows it: "where is the nearest mailbox" listed nothing, "find the nearest
	-- innkeeper" and "show me the closest anvil" nothing, "whats the nearest innkeeper" a Watchmaster; 0.68.11, review)
	local k = first
	while k < #tokens and (LEAD_IN[tokens[k]] or ARTICLE[tokens[k]]) do k = k + 1 end
	if k > first then
		local near = ns.Easy.Action(tokens[k])
		if near and near.nearest and (#tokens > k or filters) then first = k end
	end
	local a = ns.Easy.Action(tokens[first])
	if a and (#tokens > first or filters) then
		local taken = {}
		for _ = 1, first - 1 do
			table.remove(tokens, 1)
			if src then taken[#taken + 1] = table.remove(src, 1) end
		end
		if src then taken[#taken + 1] = table.remove(src, 1) end
		return a, table.remove(tokens, 1), taken
	end
	-- "near me" said after what's wanted: "repair near me" (it read as the word "near"; 0.68.11, review), "innkeeper near
	-- me in stormwind" (0.68.16: only the last two words were looked at)
	if #tokens > 2 or (#tokens == 2 and filters) then
		for j = #tokens - 1, 1, -1 do
			if NEAR_ME[tokens[j] .. " " .. tokens[j + 1]] then
				local taken = {}
				if src then taken[2] = table.remove(src, j + 1); taken[1] = table.remove(src, j) end
				local said = tokens[j] .. " " .. tokens[j + 1]
				table.remove(tokens, j + 1); table.remove(tokens, j)
				return ns.Easy.ACTIONS.nearby, said, taken
			end
		end
	end
	if #tokens > 1 then
		-- "nearest"/"nearby"/"closest" said last: "mining trainer nearby"
		local b = ns.Easy.Action(tokens[#tokens])
		if b and b.nearest then
			local taken = src and { table.remove(src, #tokens) } or {}
			return b, table.remove(tokens), taken
		end
	end
end

--- Simple mode: the tokens without a sentence's little words (Easy.STOP), unless nothing else would be left (and no
--- everyday word was typed).
function Scan.DropStop(tokens, softs)
	local kept = {}
	for k = 1, #tokens do if not ns.Easy.STOP[tokens[k]] then kept[#kept + 1] = tokens[k] end end
	if #kept > 0 or softs then return kept end
	return tokens
end

--- tokens.short[i]: the full names of word i when it's a shorthand ("brd", "strat", "sw").
function Scan.FillShorthand(tokens)
	local SH = ns.Shorthand
	if not SH then return end
	local exact = tokens.exact
	for i = 1, #tokens do
		local xs = not (exact and exact[tokens[i]]) and SH[tokens[i]]
		if xs then
			tokens.short = tokens.short or {}
			tokens.short[i] = xs
		end
	end
end

-- SearchText's steps share one table per search, the query (q). What's asked, however it was said (plain words, Advanced
-- syntax, Simple mode's bar):
--   text; simple: Simple mode (plain words read as everyday words, the categories); kinds: the lists asked for (a set of
--   ids: @kinds, an action's, a category's), typedKinds: @kinds typed; tokens: the words searched, lowercase (exact: the
--   "quoted" ones; short: shorthand); filters: every filter, kept by Scan.AddFilter with its views: hard (never relaxed
--   away: typed key:value, strict everyday words, a place's, an action's, a category's, the bar's), softs / softWords
--   (Simple mode's everyday words: a row passes, or has the word in its name; relaxed when nothing passes them all),
--   strictWords, fsig (the signature a narrowing must match); act: the action (an action word, do:); sortNear /
--   sortPlan / sortBest / sortField: the sort; here: where you are ("nearest"); keepFar: rows with no distance kept
--   after the near ones; easyCat: Simple mode's category searched; empty: no words left; overBudget: this frame's share
--   is used up (UI:RunSearch)

-- Simple mode: a plain word in a "|" list or after "-" is an everyday word when it is one ("-junk" = not grey)
local function PlainWord(lw)
	return ns.Easy.Word(lw) or function(e) return ns.Filters.RowHas(e, lw) end
end

--- One filter for the query, every view of it kept together (0.55.4, the search's rewrite: seven places appended to
--- filters, hard and fsig by hand, and drifted). how: "hard" (a typed key:value, a place's, an action's, a category's,
--- the bar's), "strict" (a strict everyday word: hard, and its word), "soft" (an everyday word: relaxed when nothing
--- passes). sig: its part of the signature a narrowing must match (nil: none). spec: how Advanced syntax writes it.
function Scan.AddFilter(q, f, how, sig, word, spec)
	if not f then return end
	q.filters = q.filters or {}
	q.filters[#q.filters + 1] = f
	-- (what it is in Advanced syntax, for printing the query: Scan.Print; none for one the lists or the action say)
	if spec then q.specOf = q.specOf or {}; q.specOf[f] = spec end
	if how == "soft" then
		q.softs, q.softWords = q.softs or {}, q.softWords or {}
		q.softs[#q.softs + 1] = f
		q.softWords[#q.softWords + 1] = word
	else
		q.hard = q.hard or {}
		q.hard[#q.hard + 1] = f
		if how == "strict" then
			q.strictWords = q.strictWords or {}
			q.strictWords[#q.strictWords + 1] = word
		end
	end
	if sig then q.fsig[#q.fsig + 1] = sig end
	-- (a filter whose answer changes while you type, a cooldown or where you stand: the next keystroke doesn't narrow
	-- from the rows it kept, it reads every row again; review, 0.57.7: "@spell is:ready f" kept Fireball out after its
	-- cooldown ended)
	for _, t in ipairs({ spec, sig }) do
		if type(t) == "string" and Scan.Volatile(t) then q.volatile = true end
	end
end

--- Is this filter's answer one that changes by itself (is:ready, near:)?
-- (where you are, what's tracked: they change too; 0.63.7, review: "@quest is:here r" in Durotar, then "ra" in the
-- Barrens, narrowed Durotar's rows to nothing)
Scan.VOLATILE = { "is:ready", "is:offcooldown", "near:", "is:here", "is:nearby", "is:tracked", "is:untracked", "is:watched" }
function Scan.Volatile(t)
	t = t:lower()
	for _, v in ipairs(Scan.VOLATILE) do
		local at = t:find(v, 1, true)
		if at and (at == 1 or t:sub(at - 1, at - 1):find("[%s|!%-]")) then return true end
	end
	-- (a piece that takes the first one's key: "is:passive|ready", "is:done&here"; review, 1.0.18)
	for key, rest in t:gmatch("([%a]+):([^%s]*[|&][^%s]*)") do
		for piece in rest:gmatch("[^|&]+") do
			local p = key .. ":" .. piece:gsub("^[-!]", "")
			for _, v in ipairs(Scan.VOLATILE) do
				if p == v or (v:sub(-1) == ":" and p:sub(1, #v) == v) then return true end
			end
		end
	end
	return false
end

--- Those filters (a set of tests) taken out again: a category's own test, the everyday words a trainer's word stands for.
--- The words said stay (softWords: the overview and the trainer words still read them); `sig`, when given, leaves fsig.
function Scan.DropFilters(q, drop, sig)
	local function Keep(list)
		if not list then return nil end
		local out = {}
		for _, f in ipairs(list) do if not drop[f] then out[#out + 1] = f end end
		return #out > 0 and out or nil
	end
	q.filters, q.hard, q.softs = Keep(q.filters), Keep(q.hard), Keep(q.softs)
	if sig then
		local fs = {}
		for _, w in ipairs(q.fsig) do if w ~= sig then fs[#fs + 1] = w end end
		q.fsig = fs
	end
end

--- The line read into the query: @kinds, sort:, do:, filters (key:value; Simple mode's everyday words), the words
--- searched, and what Simple mode's bar has picked. The query (q).
--- how: { noAlt = the claims that may be plain words read as plain words (UI:Search's second look) } or nil.
function Scan.Parse(self, text, how)
	local simple = EasyOn()
	local q = { text = text, simple = simple, tokens = {}, fsig = {} }
	self.noPosition = nil
	-- the line read (Phrase.lua): its words, "quoted phrases" apart (searched as one string each, never a filter or an
	-- everyday word; 0.52.13); Simple mode: numbers in plain words read as their filters ("under level 25" is lvl:<25,
	-- "worth more than 1g" value:>1g; 0.66.5, PlainNumbers.lua's plain stage), two everyday words that mean one thing as one
	-- ("attack power food", "spell power"), "sword or axe" as sword|axe, "not boe" as -boe (its join stage)
	local r = ns.Phrase.ReadLine(text, { simple = simple, parse = true, noAlt = how and how.noAlt or nil })
	q.reading = r
	local units = r.units
	local words, Low = {}, ns.Phrase.Low
	for k, u in ipairs(units) do words[k] = u.word end
	-- (where in the line each filter, sort and word came from: the claim's span, docs/FRONT_END.md 4.4; also what the
	-- bar takes back out of the line, Bar.lua's DropTyped)
	local function Span(u)
		local sp = u and ns.Phrase.Span(r, u.from, u.to)
		if sp then
			sp.by = u.by
			-- (a join's words around a "quoted phrase", not "big boe" boe: the bar takes out each of its words, never the
			-- phrase between them; FRONT_END.md invariant 7)
			if u.parts and ns.Phrase.HasQuoted(r, u.from, u.to) then sp.pieces = ns.Phrase.Pieces(r, u) end
		end
		return sp
	end
	local function Src(f, u)
		local sp = f and Span(u)
		if not sp then return nil end
		q.src = q.src or {}
		q.src[f] = sp
		return sp
	end
	local plainWord = simple and PlainWord or nil
	local F = ns.Filters
	local tokens, kinds = q.tokens, nil
	-- (Simple mode: the filters typed as words, for the bar to show as picked and take back out of the line: Bar.lua; a
	-- number said in words, its words: shown on the bar whatever its key; src: where they are in the line, the bar
	-- takes that span out, not every word that reads the same)
	local function Picked(spec, u, sp)
		if simple and spec then
			q.picks = q.picks or {}
			local phrase = u.claim and u.phrase or nil
			q.picks[#q.picks + 1] = { spec = spec, word = phrase or u.word, plain = phrase and true or nil, src = sp or Span(u) }
		end
	end
	q.tokenSrc = {} -- (each search word's unit: where in the line it came from; Scan.ActionAndPlace)
	-- (each search word as it was typed, its case kept: what Alt+` writes, "Hogger"; ns.QueryToAdvanced)
	local typedOf = {}
	q.typedOf = typedOf
	for _, u in ipairs(units) do
		local w = u.word
		-- (each word's sort: and do: read once, and lowered once; review, 0.53.6: up to three and five times a word)
		local lw = Low(u)
		local sort = F and F.SortOf and F.SortOf(w)
		local act, actWord
		if not sort and F and F.ActionOf then act, actWord = F.ActionOf(w) end
		if sort then
			-- sort:distance, sort:plan (recipes that give skill, by how many times your materials make them: Plan.lua),
			-- sort:best (the biggest upgrades first), sort:name / level / ilvl / quality / value / count (Scan.Finalize)
			local parts = F.SortList(sort)
			local first = F.SortParts(parts[1])
			if sort == "plan" then q.sortPlan = true
			elseif sort == "best" then q.sortBest = true
			elseif first == "distance" then
				-- (the nearest or the farthest first: rows that tie on yards are rare, the rest of the list isn't asked)
				q.sortNear, q.sortFar = true, parts[1] == "-distance" or nil
			else
				q.sortField = sort
				-- (distance after a field, sort:level,distance: how far each is, worked out to break the field's ties)
				for k = 2, #parts do if F.SortParts(parts[k]) == "distance" then q.sortNear = true end end
			end
			-- (Simple mode: the bar shows it as its Sort, and takes the word back out of the line: Bar.lua)
			-- (an order said in words, "most valuable": those words; 0.66.7)
			-- (one span: where the sort is said, the bar's too)
			q.srcSort = Span(u)
			if simple then q.typedSort = { id = sort, word = u.claim and u.phrase or w, drop = true, src = q.srcSort } end
			q.fsig[#q.fsig + 1] = "^" .. (sort == "distance" and "near" or sort == "-distance" and "far" or sort)
		elseif act then
			q.advAct, q.actWord = act, actWord -- (do:use: each row's Enter that action, as "use ..." says it; Scan.UseAction)
		elseif w:sub(1, 1) == "@" then
			local p = ns:ResolveProvider(w:sub(2))
			if p then
				kinds = kinds or {}
				kinds[p.id] = true
			end
		else
			-- lvl:20-30, slot:wrist, zone:ashenvale, is:todo... (Filters.lua); anything else is text
			local f = F and F.Parse(w, plainWord)
			-- Simple mode: a few everyday words are strict ("upgrades": only what suits you, never relaxed away). They're
			-- everyday words all the same (review, 0.48.6): "my upgrades" drops its "my", "nearest battlemaster" keeps to
			-- friendly NPCs, and the overview looks Questie's NPCs up by them
			local strict = not f and simple and ns.Easy.HARD_WORDS[lw] and ns.Easy.Strict(lw)
			if f then
				-- (written as Advanced does: Simple mode's "-boe", "sword|axe" as -is:boe, type:sword|type:axe)
				local spec = (simple and not ns.Easy.IsAdvancedWord(w)) and ns.Easy.AdvancedPart(lw) or w
				-- (printed: a kind of item turned down, "-cloth", turns down what's named so too, as "sword" alone is
				-- written sword|type:sword: -cloth|type:cloth, not -type:cloth that let Linen Cloth back. 0.63.7, review)
				local printed = spec
				local neg, a = lw:match("^([-!])(%a+)$")
				if simple and neg and spec == neg .. tostring(ns.Easy.WORDS[a]) and spec:find("^[-!]type:") then
					printed = neg .. a .. "|" .. ns.Easy.WORDS[a]
				end
				Scan.AddFilter(q, f, "hard", lw, nil, printed)
				Picked(spec, u, Src(f, u))
			elseif strict then
				Scan.AddFilter(q, strict, "strict", lw, lw, ns.Easy.WORDS[lw])
				Picked(ns.Easy.WORDS[lw], u, Src(strict, u))
				-- ("upgrades": the biggest first, as sort:best; 0.51.14, the player's ask)
				if ns.Easy.WORDS[lw] == "is:upgrade" then q.sortBest = true end
			else
				-- everyday words ("rare", "ready", "vendor") are soft filters in Simple mode (Simple.lua)
				local soft = ns.Easy and ns.Easy.Word(w)
				if soft then
					Scan.AddFilter(q, soft, "soft", "~" .. lw, lw, ns.Easy.WORDS[lw])
					Picked(ns.Easy.WORDS[lw], u, Src(soft, u))
				else
					tokens[#tokens + 1] = lw
					q.tokenSrc[#tokens] = u
					if not typedOf[lw] then typedOf[lw] = w end
				end
			end
		end
	end
	-- the "quoted phrases": words like any other, but each must be in a row as it is (Score: tokens.exact)
	for _, t in ipairs(r.toks) do
		if t.class == "quoted" and t.value ~= "" then
			local l = t.low
			tokens[#tokens + 1] = l
			if not typedOf[l] then typedOf[l] = t.value end
			q.tokenSrc[#tokens] = { word = t.value, from = t.i, to = t.i, by = "quoted" }
			q.exact = q.exact or {}
			q.exact[l] = true
		end
	end
	tokens.exact = q.exact
	q.typedKinds = kinds ~= nil
	-- "@spell": your spellbook and the spells you don't know yet, any class's (@classspell's rows), are one list to search
	-- (0.54.6, the player: as @talent is); an action (do:cast) only the spellbook's, which can be cast
	if kinds and kinds.spells and ns.providers.classspells and not q.advAct then kinds.classspells = true end
	-- "sort:plan": what's planned is recipes (with no @kind, or with @profession: searched too)
	if q.sortPlan and (not kinds or kinds.professions) then
		kinds = kinds or {}
		kinds.recipes = true
	end
	-- "@profession is:skillup": what's asked is recipes (only they have a difficulty): searched too
	if kinds and kinds.professions and not kinds.recipes and F and F.RecipeWord then
		for _, w in ipairs(words) do
			if F.RecipeWord(w) then kinds.recipes = true break end
		end
	end
	-- "@recipe is:unknown": the recipes you don't know are their own list (MissingRecipes.lua): searched too; with no
	-- @kind ("is:learnable" alone) along with every other list (also). Its file not loaded (it came with an update and a
	-- /reload doesn't load a new file): a line says so (missingGone, Scan.Finish)
	-- (Simple mode too since 0.55.18: Advanced syntax typed there is searched as typed, and the bar's "Not known yet",
	-- "Can learn now" are these filters; review: Simple mode left the list out)
	local barWords = simple and ns.Bar and ns.Bar.Active() and ns.Bar.Active().filters or {}
	-- (standing: keeps rewards only when they're asked for: F.AsksRewards, Others.lua; 1.0.40)
	if F and F.AsksRewards then F.rewardsAsked = F.AsksRewards(text, barWords) end
	local missingWords = {}
	for _, w in ipairs(words) do missingWords[#missingWords + 1] = w end
	for _, w in ipairs(barWords) do missingWords[#missingWords + 1] = w end
	if (not kinds or kinds.recipes or kinds.professions) and not (kinds and kinds.missing) and F
		and F.MissingWord then
		for _, w in ipairs(missingWords) do
			if F.MissingWord(w) then
				if not ns.providers.missing then q.missingGone = true
				elseif kinds then kinds.missing = true
				else q.also = { missing = true } end
				break
			end
		end
	end
	-- "@group quests": the quests in your log with who in your party is on them (GroupQuests.lua), not your group's members
	if kinds and kinds.group then
		for i = #tokens, 1, -1 do
			if tokens[i] == "quests" or tokens[i] == "quest" then
				table.remove(tokens, i)
				table.remove(q.tokenSrc, i)
				if ns.providers.groupquests then kinds.group, kinds.groupquests = nil, true else q.goneLine = GROUP_QUESTS_GONE end
				break
			end
		end
	end
	q.kinds = kinds
	-- Simple mode's bar (Bar.lua, 0.55.1): its filters taken as typed ones (hard: never relaxed away), its sort
	local bar = simple and ns.Bar and ns.Bar.Active()
	if bar then
		for _, w in ipairs(bar.filters) do Scan.AddFilter(q, F and F.Parse(w), "hard", "!bar:" .. w, nil, w) end
		if bar.sort == "distance" or bar.sort == "-distance" then q.sortNear, q.sortFar = true, bar.sort == "-distance" or nil
		elseif bar.sort then q.sortField = bar.sort end
		-- (Sort's "then by", Shift picked: on a tie, by it; 0.66.4)
		if bar.thenBy and q.sortField then q.sortField = F.SortList(q.sortField)[1] .. "," .. bar.thenBy end
		q.group = bar.group
	end
	return q
end

--- Simple mode: "enchanting trainer" is the trainers who teach enchanting, not the word in their title (the Journeyman
--- Enchanter's: Easy.TrainerProfs; 0.49.8, the player's ask); said alone, the nearest (ActionAndPlace). Looked at after
--- a place is taken (review, 0.49.17: "trainer in mage quarter" was the mage trainers, its place lost). Sets
--- q.trainerAsked, and the words and filters left.
function Scan.TrainerWords(q)
	local softWords, tokens = q.softWords, q.tokens
	-- "skinner", "miner", "herbalist" said alone: that profession's trainers (0.56.8, a player's comment: "skinner" is the
	-- nearest skinning trainer, ActionAndPlace)
	local prof = q.simple and #tokens == 1 and not (softWords and #softWords > 0) and ns.Easy.PROF_PEOPLE[tokens[1]]
	if prof then
		local spec = "trainer:" .. prof
		local f = ns.Filters and ns.Filters.Parse(spec)
		if f then
			q.tokens, q.trainerAsked = {}, true
			Scan.AddFilter(q, f, "hard", spec, nil, spec)
		end
		return
	end
	if not (q.simple and softWords and (#tokens > 0 or #softWords > 1)) then return end
	local said = false
	for _, w in ipairs(softWords) do if w == "trainer" or w == "trainers" then said = true end end
	-- ("dagger trainer": the weapon skill's weapon masters, the word no longer an item type; 0.53.9, the player)
	local F, weapons = ns.Filters, {}
	if said and F and F.TrainerWeapon then
		for _, w in ipairs(softWords) do if F.TrainerWeapon(w) then weapons[#weapons + 1] = w end end
	end
	local asked = tokens
	if #weapons > 0 then
		asked = {}
		for _, w in ipairs(tokens) do asked[#asked + 1] = w end
		for _, w in ipairs(weapons) do asked[#asked + 1] = w end
	end
	local kept, specs = ns.Easy.TrainerProfs(asked, said)
	if not specs then return end
	-- (a weapon's few masters, two or three in your capitals: those on another continent listed too, after the nearest;
	-- 0.53.10, the player: "daggers trainer" in Orgrimmar listed Sayoc, not Undercity's Archibald)
	if #weapons > 0 then q.keepFar = true end
	-- the trainer:<what> filter says trainer by the title: the word's own is:trainer (Questie's trainer flag) goes, or
	-- the Demon Trainers, who sell grimoires (a vendor's flag), were left out (0.49.13, the player's report)
	local drop = {}
	for _, w in ipairs({ "trainer", "trainers" }) do local t = ns.Easy.Word(w); if t then drop[t] = true end end
	for _, w in ipairs(weapons) do local t = ns.Easy.Word(w); if t then drop[t] = true end end
	Scan.DropFilters(q, drop)
	for _, spec in ipairs(specs) do
		local f = ns.Filters.Parse(spec)
		if f then
			q.tokens, q.trainerAsked = kept, true
			Scan.AddFilter(q, f, "hard", spec, nil, spec)
		end
	end
end

--- The action, in either mode (0.55.4: Simple mode's action word and Advanced do: went two ways): its lists when no
--- @kind says which, and its own test (do = emotes). Only an action that works on lists has them ("show" doesn't).
function Scan.UseAction(q, act)
	q.act = act
	if not (act and act.map) then return end
	if not q.typedKinds then
		q.kinds = {}
		for k in pairs(act.map) do if ns.providers[k] then q.kinds[k] = true end end
	end
	Scan.AddFilter(q, act.keep, "hard")
	q.fsig[#q.fsig + 1] = "!" .. act.label
end

--- Are the words all an NPC's role ("inn", "bank banker", "weapon master")? Nothing else typed.
function Scan.OnlyRoles(q)
	if #q.tokens > 0 or q.typedKinds then return false end
	local any = false
	for _, list in ipairs({ q.softWords or {}, q.strictWords or {} }) do
		for _, w in ipairs(list) do
			-- ("trainer" alone: which trainer isn't said, a list as before; "skinner", "mage trainer" are the nearest)
			if not ns.Easy.ROLE_WORDS[w] or w == "trainer" or w == "trainers" then return false end
			any = true
		end
	end
	return any
end

-- (an object's words that, said alone, aren't the nearest of it: Scan.ActionAndPlace)
local OBJECT_NOT_ALONE = { mail = true, post = true }

--- The action (an action word first, "use hearthstone"; a nearest-type word last; do:use) and a place named among the
--- words, taken out of them.
function Scan.ActionAndPlace(self, q)
	local simple = q.simple
	local act = q.advAct
	-- (the action's and the place's words: claims on the line's reading, where they came from: Phrase.Note)
	local src = q.tokenSrc
	if src and #src ~= #q.tokens then src = nil end
	if simple and not act and q.tokens[1] then
		local taken
		act, q.actWord, taken = Scan.TakeAction(q.tokens, q.filters, src)
		if act then q.srcAction = ns.Phrase.Note(q.reading, taken, "action", { spec = act.label, word = q.actWord }) end
		-- (1.0.48, the reach audit: "camps nearby", "mailbox near me" were NPCs named so) nearest and a list's own name that
		-- isn't NPCs: that list, nearest first (the kind word is taken below, Scan.KindWord)
		local Ih = ns.Integrations
		-- (only lists whose rows have a place, and never beside an NPC role read: "nearest recipe vendor" is a vendor,
		-- "nearest achievement" no list's; review, 1.0.66)
		if act and act.nearest and ns.Easy.KindWord and not Scan.RoleRead(q) then
			for i, w in ipairs(q.tokens) do
				local k = ns.Easy.KindWord(w)
				if not k and q.tokens[i + 1] then k = ns.Easy.KindWord(w .. " " .. q.tokens[i + 1]) end
				-- (a place's list, mailboxes, dungeons, with where you are not known: as before, "can't tell where you are")
				local place = Ih and ((Ih.OBJECT_KINDS and Ih.OBJECT_KINDS[w]) or (Ih.ENTRANCE_KINDS and Ih.ENTRANCE_KINDS[w]))
				if place and not (Ih.Here and Ih.Here()) then k = nil end
				if k and k.ids and not k.ids.npc and not k.ids.quests and not k.ids.questie and not k.mine and Scan.Placed(k.ids) then
					q.sortNear, q.sortFar = true, act.far or nil -- ("farthest mailbox": the other way round)
					act, q.actWord, q.srcAction = nil, nil, nil
					q.fsig[#q.fsig + 1] = "^near"
					q.nearList = true
					break
				end
			end
		end
	end
	Scan.UseAction(q, act)
	-- Simple mode: a place named among the words ("vendor ratchet", "trainer in booty bay", "food barrens"): NPCs
	-- there, other rows that name it (Integrations.FindPlace / PlaceFilter); checked after the cheaper filters
	self.place = nil
	local I = ns.Integrations
	if simple and #q.tokens > 0 and I and I.FindPlace then
		local place, rest = I.FindPlace(q.tokens)
		-- (only a sentence's little words left are nothing more to look for: "deadmines entrance", "in the deadmines" are the
		-- dungeon by its name, not everything standing in it; 0.68.11, review)
		local more = false
		for _, w in ipairs(rest or {}) do if not ns.Easy.STOP[w] then more = true break end end
		-- (words that are a name, the place's among them, are that name: "dalaran mage", "stockade guard"; 0.68.16; a
		-- sentence's little words at either end aren't the name's: "innkeeper in westfall" is "in westfall" once the role
		-- is taken, a quest's name has that, 0.68.16)
		if place and more and I.NamedAs then
			local a, b = 1, #q.tokens
			while a <= b and ns.Easy.STOP[q.tokens[a]] do a = a + 1 end
			while b >= a and ns.Easy.STOP[q.tokens[b]] do b = b - 1 end
			if b > a and I.NamedAs({ unpack(q.tokens, a, b) }) then place = nil end
		end
		if place and (more or q.filters or act) then
			-- (the place's words: the run of tokens rest goes without)
			local placed
			if src and #rest < #q.tokens then
				local k = 1
				while k <= #rest and rest[k] == q.tokens[k] do k = k + 1 end
				local m = #q.tokens - #rest
				local same = true
				for j = k, #rest do if rest[j] ~= q.tokens[j + m] then same = false end end
				if same then
					placed = {}
					for j = k, k + m - 1 do placed[#placed + 1] = src[j] end
					for _ = 1, m do table.remove(src, k) end
				end
			end
			q.tokens = rest
			if not placed then q.tokenSrc = nil end
			local f = I.PlaceFilter(place)
			Scan.AddFilter(q, f, "hard", "@" .. place.key, nil, "in:" .. tostring(place.key):gsub(" ", "_"))
			local c = ns.Phrase.Note(q.reading, placed, "place", { spec = "in:" .. tostring(place.key):gsub(" ", "_") })
			if c and f then q.src = q.src or {}; q.src[f] = c end
			self.place = place
		end
	end
	if simple then Scan.TrainerWords(q) end
	-- "blacksmithing trainer", "mage trainer" said alone: the nearest of them (0.49.9, the player's ask: it listed nothing,
	-- the NPCs being searched only when asked for); a place said keeps to the place ("mining trainer in org")
	if simple and not act and q.trainerAsked and not self.place then
		act = ns.Easy.ACTIONS.nearest
		Scan.UseAction(q, act)
	end
	-- (0.56.8, a player's comment: "if I search for inn, bank, skinner, weapon master, I'm looking for the nearest") NPC
	-- roles said alone ("inn", "bank", "repair", "weapon master"): the nearest of them, as "nearest inn" lists; not with a
	-- place said ("vendor goldshire"), nor with the bar's own sort picked
	-- (nowhere known, in a dungeon: listed as before, not "can't tell where you are")
	if simple and not act and not self.place and not q.sortField and ns.providers.npc and Scan.OnlyRoles(q)
		and ns.Integrations and ns.Integrations.Here and ns.Integrations.Here() then
		act = ns.Easy.ACTIONS.nearest
		Scan.UseAction(q, act)
		q.nearImplied = true
	end
	-- an object said alone ("mailbox", "anvil", "mailboxes in westfall"): the nearest of them, as a role is (0.68.16: a
	-- writ's text, an NPC called the Anvil); a place said keeps to it
	if simple and not act and not q.sortField and I and I.ObjectKind and I.OBJECT_KINDS and I.Here then
		local said = Scan.DropStop(q.tokens)
		local w = table.concat(said, " ")
		-- (not a word that's more than the object: "mail" is armour and your mail, "post" a word; 0.68.16)
		if #said > 0 and #said <= 2 and not OBJECT_NOT_ALONE[w] and I.ObjectKind(said) and I.OBJECT_KINDS[w] and I.Here() then
			act = ns.Easy.ACTIONS.nearest
			Scan.UseAction(q, act)
			q.nearImplied = true
		end
	end
	-- a word naming the kind of thing wanted: its category searched (Scan.SimpleScope), as if picked; not beside an
	-- action word's lists, a trainer's word or a category you picked
	if simple and not (act and act.map) and not q.trainerAsked and not (self.category and not self.categoryAuto) then
		Scan.KindWord(q)
	end
	-- (1.0.62, the reach audit) "rare", "elite" beside NPCs ("rare mobs near me", "elite npcs", "rare spawns in westfall"),
	-- or with a place and nothing else ("rare in westfall"): an NPC's rank, not an item's quality
	if simple then Scan.RankWords(self, q, act) end
	-- (the nearest of a list named: where you are, for its rows' distances; Scan.Nearest)
	if q.nearList and not q.here then q.here = I and I.Here and I.Here() or nil end
	self.action = act
end

--- Do all these lists' rows have a place ("nearest" sorts them by distance): sort:distance's lists (Others.lua's
--- F.APPLIES), and camps.
function Scan.Placed(ids)
	local F = ns.Filters
	local spots = F and F.APPLIES and F.APPLIES.sort and F.APPLIES.sort.distance or {}
	local any = false
	for id in pairs(ids) do
		local ok = id == "camp"
		for _, s in ipairs(spots) do if s == id then ok = true break end end
		if not ok then return false end
		any = true
	end
	return any
end
--- Was an NPC's role read among the words (is:vendor, is:trainer, trainer:...)?
function Scan.RoleRead(q)
	local E = ns.Easy
	for _, list in ipairs({ q.softWords or {}, q.strictWords or {} }) do
		for _, w in ipairs(list) do
			if E.ROLE_WORDS[w] or (E.PROF_PEOPLE and E.PROF_PEOPLE[w]) then return true end
		end
	end
	return false
end

--- Simple mode: "hogger quest", "quests in westfall", "npcs in westfall", "linen recipes" (0.68.14, the player's call:
--- the word was searched as a word, and "quests in westfall" found an NPC named Quartermaster Lewis). The first word
--- that names a kind (E.KindWord) is taken out and its category kept as q.kindCat (q.kindOnly: the one list a word like
--- "mounts" names). 1.0.45 (the player's ask): every list's own name is one too (q.kindIds: the lists it names, searched
--- alone, explicit ones included: "linen on my alts" @stored, "guild online" @guild), and a kind word said alone (with
--- "my", "list", "show" and such) lists its lists ("macros", "my addons", "slash commands"), unless a row elsewhere is
--- named the line (names stay names). A game window of that name comes along after them (Scan.KindExtras).
local ALONE = { my = true, list = true, show = true, all = true, every = true, me = true, the = true, your = true, mine = true }
-- (a list said with what it holds, "which alt has linen", "my bank has copper": those words go with it; 1.0.49)
local KIND_FILLER = { has = true, have = true, had = true, got = true, holds = true, hold = true, carries = true, carry = true,
	keeps = true, which = true, what = true }
-- (a thing's general word beside a list said as yours, "items on my alts": the list's rows are those; 1.0.49)
local KIND_GENERAL = { item = true, items = true, thing = true, things = true, stuff = true }
--- Is anything (not a window, not one of `ids`' rows) named `lname` in the lists built? (Each list read once per
--- word until a list changes: "macros" typed went over every loot row, again for Alt+`; review, 1.0.67)
local takenSeen, takenGen = {}, nil
local function NameTaken(lname, ids)
	if takenGen ~= ns.entriesGen then takenSeen, takenGen = {}, ns.entriesGen end
	local seen = takenSeen[lname]
	if not seen then seen = {}; takenSeen[lname] = seen end
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		if p and not p.explicit and id ~= "panels" and not ids[id] then
			local got = seen[id]
			if got == nil then
				got = false
				for _, e in ipairs(p._entries or {}) do
					if rawget(e, "_lname") == lname then got = true break end
				end
				seen[id] = got
			end
			if got then return true end
		end
	end
	return false
end
local NPC_WORDS = { mob = true, mobs = true, npc = true, npcs = true, spawn = true, spawns = true, creature = true, creatures = true }
--- Simple mode's "rare" and "elite" as an NPC's rank: beside an NPC word, the nearest NPCs, or a place said alone with them.
function Scan.RankWords(self, q, act)
	local npcs = q.kindCat == "npcs" or (q.kindIds and q.kindIds.npc) or (act and act.map and act.map.npc)
	-- (with a place, only when nothing else is said: a sentence's little words aside, no other everyday word: "rare
	-- swords westfall" is green swords; review, 1.0.66)
	local onlyRank = true
	local STOP = ns.Easy.STOP or {}
	for _, w in ipairs(q.tokens) do if w ~= "elite" and w ~= "rare" and not STOP[w] then onlyRank = false end end
	for _, list in ipairs({ q.softWords or {}, q.strictWords or {} }) do
		for _, w in ipairs(list) do if w ~= "rare" and w ~= "elite" then onlyRank = false end end
	end
	if not (npcs or (self.place and onlyRank)) then return end
	local F = ns.Filters
	if not F then return end
	local rare, elite = false, false
	for i = #(q.softWords or {}), 1, -1 do
		if q.softWords[i] == "rare" then
			local f = q.softs and q.softs[i]
			if f then Scan.DropFilters(q, { [f] = true }, "~rare") end
			table.remove(q.softWords, i)
			rare = true
		end
	end
	for i = #q.tokens, 1, -1 do
		local w = q.tokens[i]
		if w == "elite" or w == "elites" then elite = true; table.remove(q.tokens, i); q.tokenSrc = nil
		elseif w == "rare" or w == "rares" then rare = true; table.remove(q.tokens, i); q.tokenSrc = nil end
	end
	-- (the nearest NPCs said with an NPC word, "rare mobs near me": the word's said by the action)
	if (rare or elite) and act and act.map and act.map.npc then
		for i = #q.tokens, 1, -1 do if NPC_WORDS[q.tokens[i]] then table.remove(q.tokens, i); q.tokenSrc = nil end end
	end
	local spec = (rare and elite and "is:rareelite") or (rare and "is:rare") or (elite and "is:elite") or nil
	if spec then
		Scan.AddFilter(q, F.Parse(spec), "hard", spec, nil, spec)
		q.kindIds = q.kindIds or (not act and { npc = true }) or q.kindIds -- (an NPC's rank: @npc's)
	end
end

--- Is the word said as yours ("my bank", "linen in my bank")?
local function Mine(text, w)
	local pat = "%smy%s+" .. w:gsub("%p", "%%%0") .. "[%s%p]"
	return (" " .. ns.Lower(tostring(text or "")) .. " "):find(pat) ~= nil
end
function Scan.KindWord(q)
	local E = ns.Easy
	local tokens = q.tokens
	if not (E and E.KindWord) or q.typedKinds then return end -- (an @kind typed names the lists: "@questlog stormwind rep")
	local exact = q.exact
	local function Take(k, word, alone)
		if k.ids and (alone or not k.cat or k.mine or not E.KIND_WORDS[word]) then
			q.kindIds, q.kindCat = k.ids, nil
			for id in pairs(k.ids) do q.kindCat = q.kindCat or (E.FirstCategory and E.FirstCategory(id)) end
		else
			q.kindCat, q.kindOnly = k.cat, k.kind
		end
		q.kindWord, q.kindAlone = word, alone or nil
		-- (its filter on its own rows: the window that comes along isn't in your bags; Scan.KindExtras)
		local f = k.filter and ns.Filters and ns.Filters.Parse(k.filter)
		if f then Scan.AddFilter(q, function(e) return e.kind == "panels" or f(e) end, "hard", k.filter, nil, k.filter) end
	end
	-- (a list said as yours comes first: "items on my alts" is your alts', not your bags; 1.0.49, the reach audit)
	local first = 1
	for i = 1, #tokens do
		local kk = not (exact and exact[tokens[i]]) and E.KindWord(tokens[i])
		if kk and kk.ids and Mine(q.text, tokens[i]) then
			first = i
			for j = #tokens, 1, -1 do
				if j ~= i and (KIND_GENERAL[tokens[j]] or KIND_FILLER[tokens[j]]) then
					table.remove(tokens, j)
					if j < first then first = first - 1 end
					q.tokenSrc = nil
				end
			end
			break
		end
	end
	for i = first, #tokens do
		local w, nx = tokens[i], tokens[i + 1]
		local k, n = nil, 1
		if nx and not (exact and (exact[w] or exact[nx])) then
			k = E.KindWord(w .. " " .. nx)
			if k then n = 2 end
		end
		if not k then k = not (exact and exact[w]) and E.KindWord(w) or nil end
		-- (as yours only; "bags", "gold" said alone are yours too)
		if k and k.mine and not Mine(q.text, w) and not (k.mineAlone and #tokens == 1 and not q.filters) then k = nil end
		if k then
			local more = q.filters ~= nil and #q.filters > 0
			for j, x in ipairs(tokens) do
				if more then break end
				if (j < i or j >= i + n) and not E.STOP[x] and not ALONE[x] and not E.KindWord(x) then more = true end
			end
			if not more then
				-- alone: its lists, unless it's something's name ("Bags", a quest); a category word without lists of its
				-- own ("creatures") searched as before
				if not k.ids then return end
				local said = {}
				for _, x in ipairs(tokens) do if not ALONE[x] and not E.STOP[x] then said[#said + 1] = x end end
				if NameTaken(table.concat(said, " "), k.ids) then return end
				for j = #tokens, 1, -1 do tokens[j] = nil end
				q.tokenSrc = nil
				Take(k, n == 2 and (w .. " " .. nx) or w, true)
				return
			end
			for _ = 1, n do table.remove(tokens, i) end
			local src = q.tokenSrc
			if src and #src == #tokens + n then for _ = 1, n do table.remove(src, i) end else q.tokenSrc = nil end
			-- (what it holds said with it: "which alt has linen" is the alts' linen)
			if k.ids then
				for j = #tokens, 1, -1 do if KIND_FILLER[tokens[j]] then table.remove(tokens, j); q.tokenSrc = nil end end
			end
			Take(k, n == 2 and (w .. " " .. nx) or w, false)
			return
		end
	end
	-- an everyday word said as yours, "linen in my bank", "my mail": that list, the word's filter let go
	for idx, w in ipairs(q.softWords or {}) do
		local k = E.KindWord(w)
		if k and k.ids and k.mine and Mine(q.text, w) then
			local f = q.softs and q.softs[idx]
			if f then Scan.DropFilters(q, { [f] = true }, "~" .. w) end
			table.remove(q.softWords, idx)
			Take(k, w, #tokens == 0)
			return
		end
	end
end

--- The words searched in the end (q.tokens, q.empty), and the ones to light up.
function Scan.Prepare(self, q)
	local tokens = q.tokens
	-- Simple mode: the little words of a sentence aren't asked for ("food that gives stamina", "shield from kresh")
	-- (a trainer's profession said: as an everyday word, the sentence's little words go: "mining trainer in org", "the
	-- enchanting trainer"; review, 0.49.17)
	-- (a kind said, "quests in westfall": the little words go even when nothing else is left, the kind was what was said)
	if q.simple and #tokens > 0 then tokens = Scan.DropStop(tokens, q.softs or q.strictWords or q.trainerAsked or q.kindCat) end
	tokens.exact = q.exact -- ("quoted phrases": as they are; DropStop's list is a new one)
	-- "brd", "strat", "sw": also the place's full name (Shorthand.lua), looked up once per search (before
	-- the Simple overview, which scores with them too)
	Scan.FillShorthand(tokens)
	-- (set before any early return: rows listed straight away, "nearest mailbox", light up these words, not the last search's)
	self.posTokens = tokens
	-- (sorted by AH value or price, or is:auctionable: the rows' detail says it, List.lua's FillRow; 0.62.2, the player:
	-- "the value disappears from the details column when I add my bank into the mix")
	-- (0.65.6, the player's screenshot: "the advanced version of the bags search loses the slots in the details
	-- column") a quest search for bags (reward:bag, sort:slots) says which bag and its slots: Rewards.lua. A sort turned
	-- round (sort:-ahvalue) says it too.
	local sf = q.sortField and ((ns.Filters.SortList(q.sortField)[1] or ""):gsub("^%-", ""))
	local auctionable, bags = false, nil
	for w in ns.Lower(q.text or ""):gmatch("%S+") do
		if w == "is:auctionable" then auctionable = true
		elseif ns.QuestRewards and ns.QuestRewards.KindOfWord then bags = bags or ns.QuestRewards.KindOfWord(w) end
	end
	-- (the kind asked for: sort:slots and the detail say that kind's bag, as "quests that reward bags" does)
	if ns.QuestRewards then ns.QuestRewards.slotKind = bags end
	self.showField = (sf == "ahvalue" or sf == "ahprice" or sf == "slots") and sf or (auctionable and "ahvalue")
		or (bags and "slots") or nil
	q.tokens, q.empty = tokens, #tokens == 0
end
