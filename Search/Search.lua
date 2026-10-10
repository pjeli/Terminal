local ns = select(2, ...)

-- The search engine: the searches themselves (SearchText: Advanced and Simple mode, the Simple overview of categories,
-- fuzzy finding, the "Search Questie for this" rows, close spellings), command and argument rows, the empty terminal's
-- recent picks. Scoring a row and sorting the matches are in Score.lua. Moved out of UI.lua (0.43.15) as it was: the
-- window (UI.lua) shows what these give and runs them a slice at a time (UI:RunSearch).

local UI = ns.UI
local Fuzzy = ns.Fuzzy
local function EasyOn() return ns.Easy ~= nil and ns.Easy.On() end
local EASY_NONE = "Nothing has that. Check the spelling, or try other words."
local EASY_NO_NPCS = "\"nearest\" needs Questie (or QuestieDB): it knows where NPCs stand."
local EASY_NOWHERE = "Can't tell where you are here (in a dungeon?)."
local EASY_NONE_NEAR = "None of those on this continent that Questie knows of."
local EASY_NO_FLIGHTS = "No flight path like that on this continent."
local EASY_ALL_FLIGHTS = "You know every flight path on this continent."
local MISSING_GONE = "Restart the game for the recipes you don't know: this update added a file, and a /reload doesn't load new files."
local EASY_FLIGHTS_UNCHECKED = "Terminal doesn't know your flight paths here yet: open any flight master's map on this continent."
local SLICE_CHECK = UI.SLICE_CHECK -- rows scored between looks at the clock
local QUESTION_MARK = 134400 -- (an icon for rows without one)
-- scoring and sorting (Score.lua), as locals: they run for every row
local Score = ns.Score
local NO_POS, TEXT_SCORE, MAX_RESULTS = Score.NO_POS, Score.TEXT_SCORE, Score.MAX_RESULTS
local FreqBonus, ScoreEntry, TokenScore, RowText = Score.FreqBonus, Score.ScoreEntry, Score.TokenScore, Score.RowText
local NearLimit, NearWord, SortAndTrim = Score.NearLimit, Score.NearWord, Score.SortAndTrim

local function PseudoEntries(lines)
	local out = {}
	for i, line in ipairs(lines) do
		out[i] = { name = line, raw = true, icon = false, noActivate = true, kindLabel = "", detail = "" }
	end
	return out
end

-- The search's helpers (a table: SearchText's steps and what they share)
local Scan = {}

--- For a search run by UI:RunSearch (in a coroutine): a function that says when this frame's share is used up.
--- Called directly (tests, other code), the search never pauses.
function Scan.Budget(self)
	local slicing = self.sliceUntil ~= nil and coroutine.running() ~= nil
	return function() return slicing and debugprofilestop() > self.sliceUntil end
end

--- Can the last keystroke's matches stand for these words? One more letter on the last word, or one more word, only
--- narrows (every row that has the new words had the old ones); never when the last word turned into shorthand
--- ("br" -> "brd": the shorthand matches rows the shorter word didn't), nor the other way ("sw" -> "swo": the
--- shorthand matched only its full name and the word itself).
function Scan.Narrows(last, tokens)
	local n, ln = #tokens, #last
	if n ~= ln and n ~= ln + 1 then return false end
	for i = 1, ln do
		local a, b = last[i], tokens[i]
		if (i < n and a ~= b) or (i == n and b:sub(1, #a) ~= a)
			or (i == n and a ~= b and tokens.short and tokens.short[i])
			or (a ~= b and last.short and last.short[i]) then return false end
	end
	return true
end

----------------------------------------------------------------------
-- Searching
----------------------------------------------------------------------

local function RunCmd(e, args) return e.cmd.run(args or "", ns) end
local cmdList, cmdCount -- the command rows, made again only when commands are added

function UI:CommandEntries()
	if cmdList and cmdCount == #ns.commandOrder then return cmdList end
	local list = {}
	for _, name in ipairs(ns.commandOrder) do
		local c = ns.commands[name]
		list[#list + 1] = {
			kind = "cmd",
			kindLabel = "|cff33ff99cmd|r",
			name = name,
			_lname = name,
			key = name,
			icon = "Interface\\Icons\\INV_Misc_Note_01",
			detail = c.desc,
			text = table.concat(c.aliases, " "),
			freqKey = "cmd:" .. name,
			cmd = c,
			activate = RunCmd,
		}
	end
	cmdList, cmdCount = list, #ns.commandOrder
	return list
end

local function RunArg(e) return e.cmd.run(e.argLine, ns) end

--- The arguments a command takes, as rows, while you type them: ".theme " lists the themes,
--- ".set cursor " the cursor styles. A command's `complete(args)` gives them, as strings or
--- { value, detail }. Each row runs the command with that argument (Enter, a click, or Tab and
--- the arrows to pick one). With nothing typed yet, the command itself comes first, so Enter
--- still runs it as typed. Nil when the command takes no listed arguments, or none match.
function UI:ArgEntries(text)
	local word, rest = text:match("^%s*(%S+)%s(.*)$")
	local c = word and ns:FindCommand(word)
	if not (c and c.complete) then return nil end
	local ok, list = pcall(c.complete, rest)
	if not ok or type(list) ~= "table" then return nil end
	local before, argWord = rest:match("^(.-)(%S*)$")
	local lw = ns.Lower(argWord)
	local out = {}
	for i, cand in ipairs(list) do
		local val, detail = cand, nil
		if type(cand) == "table" then val, detail = cand[1], cand[2] end
		local lv = type(val) == "string" and ns.Lower(val)
		local at = lv and (lw == "" and 1 or lv:find(lw, 1, true))
		if at then
			out[#out + 1] = {
				kind = "cmd", kindLabel = "|cff33ff99." .. c.name .. "|r", icon = "Interface\\Icons\\INV_Misc_Note_01",
				name = val, _lname = lv, key = c.name .. " " .. val, freqKey = "cmd:" .. c.name,
				detail = detail or "", cmd = c, argLine = before .. val, activate = RunArg, _nameHit = true,
				_score = (at == 1 and 1000 or 500) - i, -- starts with what's typed first, then in the list's order
			}
		end
	end
	if #out == 0 then return nil end
	if lw == "" then
		for _, e in ipairs(self:CommandEntries()) do
			if e.name == c.name then
				e._score, e._pos = 2000, NO_POS
				table.insert(out, 1, e)
				break
			end
		end
	end
	self.args = rest
	self.posTokens = lw ~= "" and { lw } or nil
	table.sort(out, function(a, b) return a._score > b._score end)
	return out
end

--- Used by "/" and "." modes: first word picks the entry, the rest is its arguments.
function UI:WordSearch(entries, text)
	local word, rest = text:match("^%s*(%S*)%s*(.*)$")
	self.args = rest
	local tokens
	if word ~= "" and word ~= "/" then tokens = { ns.Lower(word) } end
	self.posTokens = tokens
	local out = {}
	for _, e in ipairs(entries) do
		if not tokens then
			e._score, e._pos = 0, NO_POS
			out[#out + 1] = e
		else
			local s = ScoreEntry(e, tokens)
			if s then
				e._score = s + FreqBonus(e)
				out[#out + 1] = e
			end
		end
	end
	return SortAndTrim(out)
end

--- A command typed by its exact name or alias (".fzf", ".rl") comes first, whatever else its letters match.
function UI:ExactCommandFirst(list, text)
	local word = text:match("^%s*(%S+)")
	local c = word and ns:FindCommand(word)
	if not c then return list end
	for i, e in ipairs(list) do
		if e.cmd == c then
			if i > 1 then table.remove(list, i); table.insert(list, 1, e) end
			break
		end
	end
	return list
end

--- What follows each ":" of the recent picks' freqKeys ("kind:key"), and the numbers those read as: a compact row whose
--- own key isn't one of them can't be a recent pick, so its freqKey (a string its metatable makes) isn't needed.
local function RecentKeys(rank)
	local keys = {}
	for k in pairs(rank) do
		-- (what follows the first ":" is enough while no kind's id has one; what follows each costs nothing more)
		local at = type(k) == "string" and k:find(":", 1, true)
		while at do
			local key = k:sub(at + 1)
			keys[key] = true
			local num = tonumber(key)
			if num and num == num then keys[num] = true end
			at = k:find(":", at + 1, true)
		end
	end
	return keys
end

--- The empty terminal: what you picked last, newest first, then your all-time favourites. Spread over frames like the
--- search. In a heavy list read only because a recent pick names it (loot, NPCs...: thousands of compact rows), a
--- row's freqKey is made only when its own key is one a recent pick has (RecentKeys); a key that isn't a string or a
--- whole number below 1e14 is looked at by its freqKey as before.
function UI:FrequentEntries()
	local out = {}
	local rank = {}
	for i, key in ipairs(ns.db.recent or {}) do rank[key] = i end
	-- providers named by recent picks are read even if they're heavy (map, options, loot)
	local want = {}
	for key in pairs(rank) do want[key:match("^([^:]+):") or ""] = true end
	local freq, keys = ns.db.freq, nil
	local overBudget = Scan.Budget(self)
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		if not p.explicit and not p.lazy then
			local list = ns:GetEntries(p)
			for i = 1, #list do
				local e = list[i]
				local r = rank[e.freqKey]
				local f = freq[e.freqKey]
				if r then
					e._score, e._pos = 10000 - r, NO_POS
					out[#out + 1] = e
				elseif f and f > 0 then
					e._score, e._pos = f, NO_POS
					out[#out + 1] = e
				end
				if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
			end
		elseif want[id] then
			-- (only the recent picks count here: a list only searched with @kind, or not on an empty prompt)
			local list = ns:GetEntries(p)
			for i = 1, #list do
				local e = list[i]
				local fk
				if not e._compact then
					fk = e.freqKey
				else
					fk = rawget(e, "freqKey")
					if fk == nil then
						keys = keys or RecentKeys(rank)
						local key = rawget(e, "key")
						if key == nil or key == false then key = e.name end -- (as CompactMeta makes it: key, else name)
						if keys[key] then
							fk = e.freqKey
						else
							local t = type(key)
							if t ~= "string" and (t ~= "number" or key % 1 ~= 0 or key <= -1e14 or key >= 1e14) then fk = e.freqKey end
						end
					end
				end
				local r = fk ~= nil and rank[fk]
				if r then
					e._score, e._pos = 10000 - r, NO_POS
					out[#out + 1] = e
				end
				if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
			end
		end
	end
	if #out == 0 then
		-- (nothing picked yet: what to type, in the words of the mode you're in)
		return PseudoEntries(ns.Said({
			"Type the name of anything: an item, a quest, a spell, a mount, a place, an NPC, an emote",
			"Start with what to do: use, cast, summon, equip, where, nearest (\"nearest innkeeper\")",
			"Ask in plain words: \"where should i level\", \"mats for thorium belt\", \"what killed me\"",
			"Type a sum like  3*45g  or  12.5% of 800  for the calculator",
			"Right-click a result (or Shift+Right) to send it to chat, or every result at once",
			"Change the look with  .theme  and  .set , or  .options",
		}, {
			"Type to fuzzy-search items, quests (by text), spells, recipes, camp objects...",
			"Start with  /  for slash commands,  .  for terminal commands (try .help)",
			"Add  @questlog  /  @item  /  @recipe  to search a single kind (@questie: every quest, with Questie)",
			"Type a sum like  3*45g  or  12.5% of 800  for the calculator",
			"End a search with  >> party  (or guild, raid, say, whisper Name) to send the result to chat;  >>> party  sends every result at once",
			"Change the look with  .theme  and  .set , or  .options",
		}))
	end
	return SortAndTrim(out)
end

UI.DATA_RETRY, UI.DATA_RETRIES = 1.1, 8 -- (seconds between, and how many: about 9 s of the game loading item data)

--- A filter met item or spell data the game was still loading ("stamina food" right after login: the food's text
--- isn't in yet, so it failed stamina): the same search runs again in a moment, from scratch (the narrowing state
--- left those rows out), until the data is in or a few tries have gone by. Typing anything ends it.
function UI:RetryWhenLoaded(text)
	local F = ns.Filters
	if not (F and F.loading) then
		if self.dataRetry and self.dataRetry.text ~= text then self.dataRetry = nil end
		return
	end
	local r = self.dataRetry
	-- (the prompt as typed: the searched text may be trimmed or have lost a ">> party")
	if not r or r.text ~= text then r = { text = text, tries = 0, typed = UI.edit:GetText() }; self.dataRetry = r end
	if r.waiting or r.tries >= UI.DATA_RETRIES then return end
	r.waiting = true
	C_Timer.After(UI.DATA_RETRY, function()
		r.waiting = false
		if self.dataRetry ~= r or not self:IsShown() or UI.edit:GetText() ~= r.typed then return end
		r.tries = r.tries + 1
		ns:Trace(("search: item data was still loading, searching %q again (%d)"):format(text, r.tries))
		self.lastScan, self.lastOverview = nil, nil
		self.refreshedAt, self.searchedText = nil, nil
		self:Refresh()
	end)
end

function UI:Search(text)
	if ns.Filters then ns.Filters.loading = nil end
	-- arithmetic: the answer is the top result (see Calc.lua)
	local calc = not self.fzf and ns.Calc and ns.Calc.Entry(text)
	local res = self:SearchText(text)
	if calc then table.insert(res, 1, calc) end
	self:RetryWhenLoaded(text)
	return res
end

--- A quest item among the matches brings its quest along, right below it ("Intact Limbs" -> its
--- quest); an item with no sure quest brings the likeliest ones, marked "maybe". Adds to `out`.
local function LinkQuests(out)
	local quests = ns.providers.quests
	if not quests then return end
	local linked, from, guessed = {}, {}, {}
	local present = {} -- quests already among the results
	local guessers -- (rows with only likely quests: they link what no sure one did, after all of those)
	-- one look at each match. Compact rows are skipped unread (_compact is a field of their own, or of the row a
	-- "nearest" view stands for): only item and quest-log rows carry a quest, and those are never compact; the big
	-- lists' thousands of matches went through their metatables here, three times each
	for i = 1, #out do
		local e = out[i]
		if not e._compact then
			local qid, isQuest = e.questID, e.kind == "quests"
			if isQuest then
				present[e] = true
			elseif qid then
				local best = linked[qid]
				if not best or e._score > best then linked[qid] = e._score; from[qid] = e end
			elseif e.guessIDs then
				guessers = guessers or {}
				guessers[#guessers + 1] = e
			end
		end
	end
	for k = 1, guessers and #guessers or 0 do
		local e = guessers[k]
		for _, id in ipairs(e.guessIDs) do
			if not linked[id] then
				linked[id] = e._score; from[id] = e; guessed[id] = true
			end
		end
	end
	if not next(linked) then return end
	for _, q in ipairs(ns:GetEntries(quests)) do
		local s = linked[q.questID]
		if s then
			if not present[q] then
				q._pos = NO_POS
				out[#out + 1] = q
			end
			-- directly under its item when the item itself was searched for by name; an item
			-- that only matched through its quest's text stays below the quest
			local it = from[q.questID]
			if not present[q] or it._nameHit then
				q._score = s - 0.001
				UI.linked[q] = it
				UI.linkedGuess[q] = guessed[q.questID] or nil
			end
		end
	end
end

--- Simple mode: an action word ("use hearthstone", "nearest innkeeper"; Easy.ACTIONS) first, or a nearest-type one
--- last ("mining trainer nearby"), taken out of the tokens. The action, or nil.
function Scan.TakeAction(tokens, filters)
	local a = ns.Easy.Action(tokens[1])
	if a and (#tokens > 1 or filters) then
		table.remove(tokens, 1)
		return a
	end
	if #tokens > 1 then
		-- "nearest"/"nearby"/"closest" said last: "mining trainer nearby"
		local b = ns.Easy.Action(tokens[#tokens])
		if b and b.nearest then
			table.remove(tokens)
			return b
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
	for i = 1, #tokens do
		local xs = SH[tokens[i]]
		if xs then
			tokens.short = tokens.short or {}
			tokens.short[i] = xs
		end
	end
end

--- Simple mode's "nearest ...": a game object asked for ("nearest mailbox": QuestieDB's objects; an entrance) or flight
--- paths ("nearest unlearned flight master": Flights.lua) give their rows at once; else where you are, for the NPCs that
--- match. Returns the rows to list now (rows, or a line saying why not), or nil, your position and the faction filter to
--- add ("nearest repair": someone who'll serve you, so only NPCs friendly to your faction; "nearest hogger": a name,
--- anyone).
function Scan.NearestStart(tokens, filters, softWords)
	local I = ns.Integrations
	local okind = I and I.ObjectKind and I.ObjectKind(tokens)
	-- (the flight paths' words left to be in their names or zones, and "unlearned"/"learned" when said)
	local rest, state
	if not okind and I and I.FlightAsked and ns.providers.flight then
		rest, state = I.FlightAsked(tokens, softWords, not ns.providers.npc)
		if rest then okind = "flight" end
	end
	if okind then
		local spot = I.Here()
		if not spot then return PseudoEntries({ EASY_NOWHERE }) end
		local keep
		if filters or (rest and #rest > 0) then
			keep = function(e)
				if filters and not ns.Filters.Pass(e, filters) then return false end
				for k = 1, rest and #rest or 0 do if not ns.Filters.RowHas(e, rest[k]) then return false end end
				return true
			end
		end
		local rows = I.NearestObjectRows(okind, spot, keep)
		local unchecked = okind == "flight" and I.Flights and not I.Flights.Checked(spot.cont)
		if rows and #rows > 0 then
			if unchecked then UI.flightNote = I.Flights.UNCHECKED_NOTE end -- (the footer: each row says "not checked yet")
			return rows
		end
		if rows and okind == "flight" then
			-- no flight master's map read on this continent yet: nothing to say of what you know here (the footer says
			-- so when there are rows); else, nothing narrowed it but the everyday words: every one here is known
			if unchecked then return PseudoEntries({ EASY_FLIGHTS_UNCHECKED }) end
			local only = #rest == 0 and (filters and #filters or 0) == (softWords and #softWords or 0)
			return PseudoEntries({ (state == "unlearned" and only) and EASY_ALL_FLIGHTS or EASY_NO_FLIGHTS })
		end
		if rows then return PseudoEntries({ EASY_NONE }) end
	end
	if not ns.providers.npc then return PseudoEntries({ EASY_NO_NPCS }) end
	local here = ns.Integrations and ns.Integrations.Here()
	if not here then return PseudoEntries({ EASY_NOWHERE }) end
	local role = false
	for _, w in ipairs(softWords or {}) do if ns.Easy.ROLE_WORDS[w] then role = true break end end
	return nil, here, role and ns.Filters and ns.Filters.Parse("faction:friendly")
end

--- A row with a distance, as a view saying how far and what it is ("120 yd  Mining Trainer", a spot row its zone:
--- "120 yd  The Barrens", or what it says after a distance: `distNote`; `nearRest`, which the arrow's live text keeps),
--- scored closest first.
local function NearView(e, d)
	local rest = rawget(e, "distNote") or (rawget(e, "wcont") and e.zone) or e.sub
	return setmetatable({ detail = ("%.0f yd"):format(d) .. (rest and ("  " .. rest) or ""), _score = 1e6 - d, _dist = d,
		nearRest = rest }, { __index = e })
end
Scan.NearView = NearView -- (tests)

--- Would row a's view (da yards away) sort before row b's (db)? Better (Score.lua) on the views NearView makes: the
--- score, then the name, then the key, read through to the rows as the views would.
local function Closer(da, a, db, b)
	local sa, sb = 1e6 - da, 1e6 - db
	if sa ~= sb then return sa > sb end
	local an, bn = a._lname or "", b._lname or ""
	if an ~= bn then return an < bn end
	return tostring(a.key) < tostring(b.key)
end

-- The closest rows so far, a heap of parallel lists (yards, row, place in the matches, its view once made) with the
-- farthest of them on top. A new one at the bottom (k) goes up past the closer ones; one put on top goes down.
local function HeapSwap(hd, he, hi, hv, a, b)
	hd[a], hd[b] = hd[b], hd[a]
	he[a], he[b] = he[b], he[a]
	hi[a], hi[b] = hi[b], hi[a]
	hv[a], hv[b] = hv[b], hv[a]
end
local function HeapUp(hd, he, hi, hv, k)
	while k > 1 do
		local p = math.floor(k / 2)
		if not Closer(hd[p], he[p], hd[k], he[k]) then return end
		HeapSwap(hd, he, hi, hv, p, k)
		k = p
	end
end
local function HeapDown(hd, he, hi, hv, size)
	local k = 1
	while true do
		local l, r, w = k * 2, k * 2 + 1, k
		if l <= size and Closer(hd[w], he[w], hd[l], he[l]) then w = l end
		if r <= size and Closer(hd[w], he[w], hd[r], he[r]) then w = r end
		if w == k then return end
		HeapSwap(hd, he, hi, hv, w, k)
		k = w
	end
end

--- The matched rows that have a distance (Questie's NPCs, rows with a place of their own: @mailbox), each as a view
--- saying how far (NearView) and scored closest first; sort:nearest keeps every other row too, after them; in the
--- order they came. Every row's distance is measured (I.RowYards: no table made), but only the MAX_RESULTS closest get
--- a view: a search keeps no more (SortAndTrim), and none of these rows brings a quest along (LinkQuests: NPCs and
--- spots carry none). Pauses with the search, showing the closest so far.
function Scan.NearestViews(out, here, sortNear, overBudget)
	local yards, max = ns.Integrations.RowYards, MAX_RESULTS
	local hd, he, hi, hv, size = {}, {}, {}, {}, 0
	local others, at = {}, {} -- (sort:nearest: the rows with no distance, as they are, and where they came)
	for i = 1, #out do
		local e = out[i]
		local d = yards(e, here)
		if d then
			if size < max then
				size = size + 1
				hd[size], he[size], hi[size], hv[size] = d, e, i, nil
				HeapUp(hd, he, hi, hv, size)
			elseif Closer(d, e, hd[1], he[1]) then
				hd[1], he[1], hi[1], hv[1] = d, e, i, nil
				HeapDown(hd, he, hi, hv, size)
			end
		elseif sortNear then
			others[#others + 1] = e
			at[#at + 1] = i
		end
		if i % 32 == 0 and overBudget() then
			-- (this frame's look: the rows so far, the closest as views, each made once: the final list keeps it; the
			-- list handed over is copied at once, so the views come off it again)
			local n = #others
			for k = 1, size do
				local v = hv[k]
				if not v then v = NearView(he[k], hd[k]); hv[k] = v end
				others[n + k] = v
			end
			coroutine.yield(others)
			for k = n + size, n + 1, -1 do others[k] = nil end
		end
	end
	-- the closest in the order they came (at most max: an insertion sort), each among the others where it came
	local order = {}
	for k = 1, size do
		local p, j = hi[k], #order
		while j > 0 and hi[order[j]] > p do order[j + 1] = order[j]; j = j - 1 end
		order[j + 1] = k
	end
	local kept, o, n = {}, 1, #others
	for j = 1, #order do
		local k = order[j]
		while o <= n and at[o] < hi[k] do kept[#kept + 1] = others[o]; o = o + 1 end
		kept[#kept + 1] = hv[k] or NearView(he[k], hd[k])
	end
	for q = o, n do kept[#kept + 1] = others[q] end
	return kept
end

-- Answered before any search, in this order: each gives rows and the footer's note (true third: the note is a
-- chain's path), or nothing when the line isn't its kind
Scan.ANSWERS = {
	-- "what dropped", "what did we get", "what did i loot": LootLog.lua (before chains: "what drops did we get" isn't "what drops <item>")
	function(text)
		local q = ns.LootLog and ns.LootLog.Question(text)
		if q then return ns.LootLog.Answer(q) end
	end,
	-- a chain ("thorium belt > mats", "mats for thorium belt"): Pipes.lua
	function(text)
		-- (Simple mode takes only the plain words: a ">" typed there is refused like any Advanced syntax)
		local chain = ns.Pipes and ns.Pipes.Canonical(text, ns.Easy and ns.Easy.On and ns.Easy.On() or nil)
		if not chain then return nil end
		local rows, trail = ns.Pipes.Search(chain)
		return rows, trail, true
	end,
	-- "what killed me", "who crit me": CombatLog.lua
	function(text)
		local q = ns.CombatLog and ns.CombatLog.Question(text)
		if q then return ns.CombatLog.Answer(q) end
	end,
	-- "where should i level", "what dungeon should i do", "where should i fish": Zones.lua
	function(text)
		local q, said
		if ns.Zones then q, said = ns.Zones.Question(text) end
		if q then return ns.Zones.Answer(q, said) end
	end,
	-- "spells not on my bars": Spells.lua
	function(text)
		local q = ns.Spells and ns.Spells.Question(text)
		if q then return ns.Spells.Answer(q) end
	end,
	-- "quests to drop", "grey quests": QuestDrop.lua
	function(text)
		local q = ns.QuestDrop and ns.QuestDrop.Question(text)
		if q then return ns.QuestDrop.Answer(q) end
	end,
	-- "blacksmithing recipes i'm missing", "recipes i can learn now": MissingRecipes.lua
	function(text)
		local q = ns.MissingRecipes and ns.MissingRecipes.Question(text)
		if q then return ns.MissingRecipes.Answer(q) end
	end,
}

-- SearchText's steps share one table per search (q):
--   text; simple: Simple mode; blocked: Advanced syntax typed in Simple mode ("send": a ">>"); kinds: the lists asked
--   for (a set of ids: @kinds, an action word's, a category's); tokens: the words searched, lowercase; filters: every
--   filter; hard: the typed key:value ones (and a place's, an action's, a category's test); softs / softWords: Simple
--   mode's everyday words' filters, and the words; fsig: the filters' signature (a narrowing needs the same); sortNear:
--   Advanced sort:nearest; act: Simple mode's action word; here: where you are ("nearest"); easyCat: Simple mode's
--   category searched; empty: no words left to search; overBudget: this frame's share is used up (UI:RunSearch)

-- Simple mode: a plain word in a "|" list or after "-" is an everyday word when it is one ("-junk" = not grey)
local function PlainWord(lw)
	return ns.Easy.Word(lw) or function(e) return ns.Filters.RowHas(e, lw) end
end

--- The list without one filter (a category's own test), or nil when nothing is left.
local function Without(list, keep)
	if not list then return nil end
	local rest = {}
	for _, f in ipairs(list) do if f ~= keep then rest[#rest + 1] = f end end
	return #rest > 0 and rest or nil
end

--- What a search tells the window, cleared for this one.
function Scan.ResetFlags(self)
	self.closeSpellings = nil -- (set when only close spellings matched: the footer says so)
	self.softRelaxed = nil -- (easy mode: nothing passed every everyday word, the closest shown: the footer says so)
	self.linkedGuess = {}
	self.linked = {} -- quest entry -> the item that brought it along (drawn with an arrow)
	self.answerNote, self.pipeTrail = nil, nil -- (a question's note, a chain's path: only for their own searches)
	self.flightNote = nil -- (flight paths listed on a continent no flight master's map was read on: Scan.FlightNote)
	self.missingNote = nil -- (recipes you don't know listed, a profession's window not read yet: MissingRecipes.LeadRow)
end

--- A chain or a question in plain words: its own answer (Scan.ANSWERS), not a search. The rows, or nil.
function Scan.Answer(self, text)
	for _, ask in ipairs(Scan.ANSWERS) do
		local rows, note, isTrail = ask(text)
		if rows then
			self.noPosition, self.action, self.place = nil, nil, nil
			if self.categoryAuto then self.category, self.categoryAuto = nil, nil end
			self.posTokens = {}
			if isTrail then self.pipeTrail = note else self.answerNote = note end
			return rows
		end
	end
end

--- Flight paths among the rows while no flight master's map has been read on your continent: the footer says so (what
--- they say of themselves there is "not checked yet"). Only for searches of the flight paths' list (@flight, Simple
--- mode's Places), and compact rows (never flight paths) aren't read: a row's kind goes through their __index.
function Scan.FlightNote(res)
	local I = ns.Integrations
	local FL = I and I.Flights
	if not FL then return end
	for i = 1, #res do
		local e = res[i]
		if not rawget(e, "_compact") and e.kind == "flight" then
			local here = I.Here()
			if here and not FL.Checked(here.cont) then UI.flightNote = FL.UNCHECKED_NOTE end
			return
		end
	end
end

--- The rows a search ends with (q.kinds and q.blocked as they are by then).
function Scan.Finish(q, res)
	if q.kinds and q.kinds.flight then Scan.FlightNote(res) end
	-- a list that asks the server first (@who), or says why it lists nothing (@recipe is:unknown): its own row on top
	-- (given the rows so far)
	local function Leads(set)
		for k in pairs(set) do
			local p = ns.providers[k]
			local row = p and p.leadRow and p.leadRow(p, q.text, res)
			if row then row.lead = true; table.insert(res, 1, row) end -- (asks something: not a result to send)
		end
	end
	if q.kinds then Leads(q.kinds) end
	if q.also then Leads(q.also) end
	if q.missingGone then table.insert(res, 1, PseudoEntries({ MISSING_GONE })[1]) end
	local blocked = q.blocked
	if not blocked then return res end
	-- only a ">>" typed: where sending lives in Simple mode (the right-click menu); else the Advanced row
	local out = { blocked == "send" and ns.Easy.SEND_ROW or ns.Easy.ADVANCED_ROW }
	for i = 1, #res do out[i + 1] = res[i] end
	return out
end

--- The typed words, read: @kinds, sort:nearest, filters (key:value; Simple mode's everyday words), the words searched.
--- The search's table (q).
function Scan.Parse(self, text)
	local kinds, tokens, filters, fsig = nil, {}, nil, {}
	local softs, hard, softWords -- (the everyday words' filters, the typed key:value ones, the everyday words)
	local simple = EasyOn()
	-- Simple mode doesn't take Advanced syntax (@kind, key:value, >>): a row on top says where it lives (Refresh
	-- already took a ">>" off); the plain words are still searched
	local blocked = simple and self.blockedSyntax or nil
	local sortNear -- Advanced "sort:nearest": NPCs closest first, the rest after
	local advAct -- Advanced "do:use": each row's Enter that action (as Simple mode's "use ...")
	self.noPosition = nil
	local words = {}
	for w in text:gmatch("%S+") do words[#words + 1] = w end
	-- Simple mode: two everyday words that mean one thing ("attack power food", "spell power")
	if simple then
		ns.Easy.JoinPairs(words)
		ns.Easy.JoinLogic(words) -- "sword or axe" -> sword|axe, "not boe" -> -boe
	end
	local plainWord = simple and PlainWord or nil
	for _, w in ipairs(words) do
		if simple and ns.Easy.IsAdvancedWord(w) then
			blocked = true
		elseif ns.Filters and ns.Filters.SortOf and ns.Filters.SortOf(w) then
			sortNear = true
			fsig[#fsig + 1] = "^near"
		elseif ns.Filters and ns.Filters.ActionOf and ns.Filters.ActionOf(w) then
			advAct = ns.Filters.ActionOf(w)
			fsig[#fsig + 1] = "!" .. advAct.label
		elseif w:sub(1, 1) == "@" then
			local p = ns:ResolveProvider(w:sub(2))
			if p then
				kinds = kinds or {}
				kinds[p.id] = true
			end
		else
			-- lvl:20-30, slot:wrist, zone:ashenvale, is:todo... (Filters.lua); anything else is text
			local f = ns.Filters and ns.Filters.Parse(w, plainWord)
			-- Simple mode: a few everyday words are strict ("upgrades": only what suits you, never relaxed away)
			if not f and simple and ns.Easy.HARD_WORDS[ns.Lower(w)] then f = ns.Filters.Parse(ns.Easy.WORDS[ns.Lower(w)]) end
			-- easy mode: everyday words ("rare", "ready", "vendor") are soft filters (Easy.lua)
			local soft = not f and ns.Easy and ns.Easy.Word(w)
			if f or soft then
				filters = filters or {}
				filters[#filters + 1] = f or soft
				fsig[#fsig + 1] = (soft and "~" or "") .. ns.Lower(w)
				if soft then
					softs, softWords = softs or {}, softWords or {}
					softs[#softs + 1] = soft
					softWords[#softWords + 1] = ns.Lower(w)
				else
					hard = hard or {}
					hard[#hard + 1] = f
				end
			else
				tokens[#tokens + 1] = ns.Lower(w)
			end
		end
	end
	-- "@profession is:skillup": what's asked is recipes (only they have a difficulty): searched too
	if kinds and kinds.professions and not kinds.recipes and ns.Filters and ns.Filters.RecipeWord then
		for _, w in ipairs(words) do
			if ns.Filters.RecipeWord(w) then kinds.recipes = true break end
		end
	end
	-- "@recipe is:unknown": the recipes you don't know are their own list (MissingRecipes.lua): searched too; with no
	-- @kind ("is:learnable" alone) along with every other list (also). Its file not loaded (it came with an update and a
	-- /reload doesn't load a new file): a line says so (missingGone, Scan.Finish)
	local also, missingGone
	if not simple and (not kinds or kinds.recipes or kinds.professions) and not (kinds and kinds.missing) and ns.Filters
		and ns.Filters.MissingWord then
		for _, w in ipairs(words) do
			if ns.Filters.MissingWord(w) then
				if not ns.providers.missing then missingGone = true
				elseif kinds then kinds.missing = true
				else also = { missing = true } end
				break
			end
		end
	end
	return { text = text, simple = simple, blocked = blocked, kinds = kinds, tokens = tokens, filters = filters,
		hard = hard, softs = softs, softWords = softWords, fsig = fsig, sortNear = sortNear, advAct = advAct,
		also = also, missingGone = missingGone }
end

--- Simple mode: an action word and a place named among the words, taken out of them (q.act, q.tokens, q.filters).
function Scan.ActionAndPlace(self, q)
	local simple, tokens, filters, hard, fsig = q.simple, q.tokens, q.filters, q.hard, q.fsig
	-- Simple mode: the first word can say what to do ("use hearthstone", "nearest innkeeper"; Easy.ACTIONS)
	local act
	if simple and tokens[1] then act = Scan.TakeAction(tokens, filters) end
	if not simple and q.advAct then
		-- Advanced "do:use": the action's lists when no @kind says which, and its own test (do:do = emotes)
		act = q.advAct
		if not q.kinds then
			q.kinds = {}
			for k in pairs(act.map) do if ns.providers[k] then q.kinds[k] = true end end
		end
		if act.keep then
			filters, hard = filters or {}, hard or {}
			filters[#filters + 1], hard[#hard + 1] = act.keep, act.keep
		end
	end
	self.action = act
	-- Simple mode: a place named among the words ("vendor ratchet", "trainer in booty bay", "food barrens"): NPCs
	-- there, other rows that name it (Integrations.FindPlace / PlaceFilter); checked after the cheaper filters
	self.place = nil
	if simple and #tokens > 0 and ns.Integrations and ns.Integrations.FindPlace then
		local place, rest = ns.Integrations.FindPlace(tokens)
		if place and (#rest > 0 or filters or act) then
			tokens = rest
			local f = ns.Integrations.PlaceFilter(place)
			filters, hard = filters or {}, hard or {}
			filters[#filters + 1] = f
			hard[#hard + 1] = f
			fsig[#fsig + 1] = "@" .. place.key
			self.place = place
		end
	end
	q.act, q.tokens, q.filters, q.hard = act, tokens, filters, hard
end

--- The words searched in the end (q.tokens, q.empty), and the ones to light up.
function Scan.Prepare(self, q)
	local tokens, softs = q.tokens, q.softs
	-- easy mode: the little words of a sentence aren't asked for ("food that gives stamina", "shield from kresh")
	if ns.Easy and ns.Easy.On() and #tokens > 0 then tokens = Scan.DropStop(tokens, softs) end
	local empty = #tokens == 0
	-- "brd", "strat", "sw": also the place's full name (Shorthand.lua), looked up once per search (before
	-- the Simple overview, which scores with them too)
	Scan.FillShorthand(tokens)
	-- (set before any early return: rows listed straight away, "nearest mailbox", light up these words, not the last search's)
	self.posTokens = tokens
	q.tokens, q.empty = tokens, empty
end

--- Simple mode with no @kind: an action word's lists, else a category (picked, or the only one that has it). The rows
--- to finish with instead of searching (just the prompt, "nearest" stopping early, the categories to pick from), or
--- nil: q.kinds, q.easyCat (and q.here for "nearest") say what to search.
function Scan.SimpleScope(self, q)
	local simple, kinds, tokens, filters, hard, fsig, act = q.simple, q.kinds, q.tokens, q.filters, q.hard, q.fsig, q.act
	local empty, blocked, softs, softWords = q.empty, q.blocked, q.softs, q.softWords
	-- easy mode (no @kind typed): nothing typed lists nothing (a line says what to do, and the category picked
	-- is let go); typed: the categories that have it, to pick from (EasyOverview); a category picked stands for
	-- its @kinds, and its own test (Emotes: the slash rows that are emotes)
	local easyCat, here
	if simple and not kinds then
		-- (no reset of lastScan here: its signature holds the lists and filters searched, so a category picked
		-- for you, or by you, narrows keystroke by keystroke like Advanced does)
		-- a category picked for you (only one had it) is worked out again with every keystroke
		if self.categoryAuto then self.category, self.categoryAuto = nil, nil end
		if empty and not filters then
			self.category = nil
			-- just the prompt: its faint placeholder says what to type (UpdateGhost); Down asked for your recent picks
			return self.showRecent and not blocked and self:FrequentEntries() or {}
		end
		if act and act.map then
			-- an action word: the kinds it works on, no categories to pick from
			kinds = {}
			for k in pairs(act.map) do if ns.providers[k] then kinds[k] = true end end
			if act.keep then
				filters, hard = filters or {}, hard or {}
				filters[#filters + 1], hard[#hard + 1] = act.keep, act.keep
				fsig[#fsig + 1] = "!" .. act.label
			end
			if act.nearest then
				local early, friendly
				early, here, friendly = Scan.NearestStart(tokens, filters, softWords)
				if early then q.kinds, q.filters, q.hard = kinds, filters, hard return early end
				if friendly then
					filters, hard = filters or {}, hard or {}
					filters[#filters + 1], hard[#hard + 1] = friendly, friendly
					fsig[#fsig + 1] = "faction:friendly"
				end
			end
			fsig[#fsig + 1] = "!" .. act.label
		else
			easyCat = self.category and ns.Easy.BY_ID[self.category]
			if not easyCat then
				local ov, kept, from = self:EasyOverview(tokens, filters, hard, softs, softWords, table.concat(fsig, " "))
				-- only one category has it: straight to its results (no step to take)
				if #ov == 1 and ov[1].catId then
					self.category, self.categoryAuto = ov[1].catId, true
					easyCat = ns.Easy.BY_ID[ov[1].catId]
					self.softRelaxed = nil
					q.overview, q.overviewFrom = kept, from -- (its lists' rows were just scored: Scan.Collect lists them)
				else
					return ov
				end
			end
		end
	end
	if easyCat then
		kinds = ns.Easy.Kinds(easyCat.id)
		if easyCat.keep then
			filters = filters or {}
			filters[#filters + 1] = easyCat.keep
			hard = hard or {}
			hard[#hard + 1] = easyCat.keep
			fsig[#fsig + 1] = "#" .. easyCat.id
		end
	end
	q.kinds, q.filters, q.hard, q.easyCat, q.here = kinds, filters, hard, easyCat, here
end

--- The lists searched (the @kinds or the category's, else every list not only searched by @kind), the signature a
--- narrowing must match, and whether every one is built already (nothing to collect again). A list searched without
--- being named (no @kind, category or action) that has a `plain` view gives only that (`included.plain`: earned
--- achievements, not every one).
function Scan.Lists(q)
	local kinds, fsig = q.kinds, q.fsig
	local included = {}
	local fresh = true -- every list read is already built (nothing to re-collect)
	local sig = {}
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		local inc
		if kinds then inc = kinds[id] else inc = not p.explicit or (q.also ~= nil and q.also[id]) end
		if inc then
			included[#included + 1] = p
			sig[#sig + 1] = id
			if not kinds and p.plain then
				included.plain = included.plain or {}
				included.plain[p] = true
				sig[#sig] = id .. "~" -- (its plain view: never a narrowing of the whole list, nor the other way)
			end
			if p._dirty or not p._entries then fresh = false end
		end
	end
	sig = table.concat(sig, ",") .. "|" .. table.concat(fsig, " ") -- (other filters: not a narrowing of the last scan)
	return included, sig, fresh
end

--- The rows a search reads of a list it includes: its plain view when Scan.Lists said so, else all of them.
local function RowsOf(included, p)
	local list = ns:GetEntries(p)
	if included.plain and included.plain[p] then return p.plain(p, list) end
	return list
end
Scan.RowsOf = RowsOf

--- Simple mode, a category opened for you (the only one with matches): the overview has just scored its lists' rows,
--- each match's score for the words left in its _score (q.overview, UI:EasyOverview). The rows it kept of p's list,
--- when what it read is this same list; nil: the list is scored as usual (Questie's, only looked up by name there; a
--- list built again since).
local function OverviewRows(q, p, list)
	local ov = q.overview
	if not ov then return nil end
	local lkey = q.easyCat.id .. "/" .. p.id
	if q.overviewFrom[lkey] == list then return ov.rows[lkey] end
end

--- Those rows as matches: what Collect's consider gives a match on top of its score for the words (kind: as consider
--- is given it). A row is in one list of a category (as every category in Easy.CATEGORIES is), so each gets it once.
local function AddOverviewRows(out, rows, kind, overBudget)
	for i = 1, #rows do
		local e = rows[i]
		e._score = e._score + FreqBonus(e, kind) + (rawget(e, "_rank") or 0) -- (rank: a list's own order, < 1)
		out[#out + 1] = e
		if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
	end
end

--- Every row of the lists that has the words and passes the filters, scored; or the last keystroke's matches scored
--- again when the words only grew (Scan.Narrows); or, in a category Simple mode opened for you, the rows its overview
--- just scored (OverviewRows: the same rows, in the same order, scored once). Spread over frames (q.overBudget, set here).
function Scan.Collect(self, q, included, sig, fresh)
	local empty, filters, tokens = q.empty, q.filters, q.tokens
	local Pass = ns.Filters and ns.Filters.Pass
	local out = {}
	-- typing one more letter, or one more word, can only narrow the matches: score just the last
	-- ones again (every one of them had the earlier words, so a new word still picks from them)
	local last = self.lastScan
	if last and last.gen ~= ns.entriesGen then last, self.lastScan = nil, nil end -- (its rows may be freed lists')
	local candidates
	if not empty and fresh and last and last.sig == sig and Scan.Narrows(last.tokens, tokens) then candidates = last.matches end
	-- kind: the list's id when known (compact rows of kinds never picked are then not read for it)
	local function consider(e, kind)
		if empty then
			if filters and not Pass(e, filters) then return end
			e._score = FreqBonus(e, kind) + (rawget(e, "_rank") or 0)
			-- (compact rows get no field more: Render works their letters out on screen, none with no words)
			if rawget(e, "_compact") then e._pos = nil else e._pos = NO_POS end
			out[#out + 1] = e
		else
			local s = ScoreEntry(e, tokens)
			if s and (not filters or Pass(e, filters)) then -- (filters only on what matched: cheaper)
				e._score = s + FreqBonus(e, kind) + (rawget(e, "_rank") or 0) -- (rank: a list's own order, < 1)
				out[#out + 1] = e
			end
		end
	end
	self.lastSearchNarrowed = candidates and true or false
	-- run by UI:RunSearch: past this frame's share, hand back what matched so far and go on
	-- in the next frame (tens of thousands of NPCs or quests no longer hitch one frame)
	local overBudget = Scan.Budget(self)
	-- (narrowing in a category opened for you: the last keystroke's matches still having the words are the rows the
	-- overview kept of each list, in that order; every list must have them, else the matches are scored as before)
	local kept
	if candidates and q.overview then
		kept = {}
		for k, p in ipairs(included) do
			kept[k] = OverviewRows(q, p, p._entries)
			if not kept[k] then kept = nil break end
		end
	end
	if kept then
		for k = 1, #included do AddOverviewRows(out, kept[k], nil, overBudget) end
	elseif candidates then
		for i = 1, #candidates do
			consider(candidates[i])
			if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
		end
	else
		for _, p in ipairs(included) do
			local list = RowsOf(included, p)
			if overBudget() then coroutine.yield(out) end -- (reading the list may have taken the share)
			local id = p.id
			local rows = OverviewRows(q, p, list)
			if rows then
				AddOverviewRows(out, rows, id, overBudget)
			else
				for i = 1, #list do
					consider(list[i], id)
					if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
				end
			end
		end
	end
	q.overBudget = overBudget
	return out
end

--- The matches kept for the next keystroke; nothing matched: Simple mode's closest by the everyday words, else close
--- spellings (added to out).
function Scan.Fallbacks(self, q, out, included, sig)
	local empty, tokens, filters, hard, softs, overBudget = q.empty, q.tokens, q.filters, q.hard, q.softs, q.overBudget
	if not empty then
		-- (out itself: SortAndTrim leaves it as it is; rows added to it below only make the net wider)
		self.lastScan = { sig = sig, gen = ns.entriesGen, tokens = tokens, matches = out }
		-- easy mode, nothing passed every everyday word ("rare shield wailing caverns" for a green shield):
		-- the rows with the typed words, those passing more of the everyday words first
		if #out == 0 and softs then self:RelaxSoft(included, tokens, hard, softs, out, overBudget) end
		-- nothing has every word: names within an edit or two of them ("hearhtstone")
		if #out == 0 then self:CloseSpellings(included, tokens, filters, out, overBudget) end
	end
end

--- "nearest" / sort:nearest: the rows with a distance, closest first (Scan.NearestViews). The rows, and the rows to
--- stop with instead (none near), if any.
function Scan.Nearest(self, q, out)
	local sortNear, here, overBudget = q.sortNear, q.here, q.overBudget
	-- "sort:nearest" (Advanced): where you are, once (an instance or no map: no sorting, the footer says so)
	if sortNear and not here then
		here = ns.Integrations and ns.Integrations.Here and ns.Integrations.Here()
		if not here then self.noPosition = true end
	end
	-- "nearest": the NPCs that matched, closest first, how far in the detail column (none known: left out;
	-- sort:nearest keeps every other row, after the NPCs)
	if here then
		out = Scan.NearestViews(out, here, sortNear, overBudget)
		if #out == 0 and not sortNear then return out, PseudoEntries({ EASY_NONE_NEAR }) end
	end
	q.here = here
	return out
end

--- The best rows, in order: a quest item's quest brought along, Simple mode's action on each, the "Search <list> for
--- this" rows (an action word with nothing to do it to: a line saying so).
--- A quest from your log and its Questie copy both listed (Simple mode's Quests, @quests @questie): only the log's row
--- (it opens your quest log), as a hint row isn't offered for a list whose copy you have (UI.HINT_SAME).
function Scan.OneQuest(res)
	local inLog
	for i = 1, #res do
		local e = res[i]
		if e.kind == "quests" and e.questID then inLog = inLog or {}; inLog[e.questID] = true end
	end
	if not inLog then return res end
	local out = {}
	for i = 1, #res do
		local e = res[i]
		if not (e.kind == "questie" and inLog[rawget(e, "key")]) then out[#out + 1] = e end
	end
	return out
end

function Scan.Finalize(self, q, out)
	local text, kinds, tokens, empty, filters, act, overBudget = q.text, q.kinds, q.tokens, q.empty, q.filters, q.act, q.overBudget
	if not empty and (not kinds or kinds.quests) then LinkQuests(out) end
	local res = SortAndTrim(out, nil, overBudget)
	if kinds and kinds.quests and kinds.questie then res = Scan.OneQuest(res) end
	if act and act.map and #res == 0 then return PseudoEntries({ EASY_NONE }) end -- ("use xyzzy": say so)
	-- an action word: each row's Enter does it ("use": the item's Shift+Enter action)
	if act and act.map then
		for i = 1, #res do res[i] = ns.Easy.ActionView(res[i], act) end
	end
	-- nothing here has what was typed in its name, but a list only searched with @kind does
	-- (Questie's quests, NPCs): a row on top offers it (Tab or Enter adds the @kind)
	if not kinds and not empty and not filters then
		local hints, at = self:BigListHint(text, tokens, res, overBudget)
		for i, hint in ipairs(hints or {}) do table.insert(res, math.min((at or 1) + i - 1, #res + 1), hint) end
	end
	return res
end

function UI:SearchText(text)
	Scan.ResetFlags(self)
	if self.fzf then
		self.noPosition, self.action, self.place = nil, nil, nil
		return self:FuzzySearch(text)
	end
	-- a chain or a question in plain words: its own answer, not a search (Scan.ANSWERS)
	local answer = Scan.Answer(self, text)
	if answer then return answer end
	local q = Scan.Parse(self, text)
	Scan.ActionAndPlace(self, q)
	Scan.Prepare(self, q)
	local rows = Scan.SimpleScope(self, q)
	if rows then return Scan.Finish(q, rows) end
	-- nothing typed: just the prompt (Down brings back the last search, else your recent picks)
	if q.empty and not q.kinds and not q.filters then
		self.lastScan, self.lastOverview = nil, nil
		return self.showRecent and self:FrequentEntries() or {}
	end
	local included, sig, fresh = Scan.Lists(q)
	local out = Scan.Collect(self, q, included, sig, fresh)
	Scan.Fallbacks(self, q, out, included, sig)
	-- easy mode: nothing in the picked category: the categories that have it instead
	if q.easyCat and #out == 0 then
		local keep = q.easyCat.keep
		self.category, self.categoryAuto, self.closeSpellings, self.softRelaxed = nil, nil, nil, nil
		return Scan.Finish(q, self:EasyOverview(q.tokens, Without(q.filters, keep), Without(q.hard, keep), Without(q.softs, keep), q.softWords))
	end
	local stop
	out, stop = Scan.Nearest(self, q, out)
	if stop then return Scan.Finish(q, stop) end
	return Scan.Finish(q, Scan.Finalize(self, q, out))
end

--- Pure fuzzy finding (Tab+`, UI.fzf), like fzf: every list there is (the ones only searched with @kind too),
--- each typed word matched by its letters in order against the NAME only (no text, initials, shorthand, close
--- spellings, filters, @kinds, picks history, hint rows or linked quests). The best FZF_MAX, to go through with the
--- arrow keys. Lists made from another one (@gear, @consumable, @mats: copies of the item rows) are left out, and a
--- row two lists share is listed once; every list is read whole (no plain view). Narrows from the last keystroke's
--- matches and is spread over frames like the usual search.
local FZF_MAX = 500
local FZF_LEN = 0.001 -- (equal matches: the shorter name first, as fzf does)
function UI:FuzzySearch(text)
	local tokens = {}
	for w in text:gmatch("%S+") do tokens[#tokens + 1] = ns.Lower(w) end
	self.posTokens = tokens
	if #tokens == 0 then self.lastFzf = nil return {} end
	local included, sig, fresh = {}, {}, true
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		if not p.follows then
			included[#included + 1] = p
			sig[#sig + 1] = id
			if p._dirty or not p._entries then fresh = false end
		end
	end
	sig = table.concat(sig, ",")
	-- one more letter or one more word only narrows (letters in order: "frst" holds whatever "frs" didn't lose)
	local last, candidates = self.lastFzf, nil
	if last and last.gen ~= ns.entriesGen then last, self.lastFzf = nil, nil end
	local n = #tokens
	if fresh and last and last.sig == sig and Scan.Narrows(last.tokens, tokens) then candidates = last.matches end
	local out, seen = {}, {}
	local score = Fuzzy.score
	local function consider(e)
		local name = e.name
		if type(name) ~= "string" then return end
		local lname, total = e._lname, 0
		for i = 1, n do
			local s = score(tokens[i], name, lname)
			if not s then return end
			total = total + s
		end
		if seen[e] or e.noActivate then return end -- (only matches are remembered: no table of every row)
		seen[e] = true
		e._score, e._pos = total - #name * FZF_LEN, nil
		if not rawget(e, "_compact") then e._nameHit = true end
		out[#out + 1] = e
	end
	self.lastSearchNarrowed = candidates and true or false
	local overBudget = Scan.Budget(self)
	if candidates then
		for i = 1, #candidates do
			consider(candidates[i])
			if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
		end
	else
		for _, p in ipairs(included) do
			local list = ns:GetEntries(p)
			if overBudget() then coroutine.yield(out) end
			for i = 1, #list do
				consider(list[i])
				if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
			end
		end
	end
	self.lastFzf = { sig = sig, gen = ns.entriesGen, tokens = tokens, matches = out }
	return SortAndTrim(out, FZF_MAX, overBudget)
end

--- The text a prompt keeps when it turns to pure fuzzy finding: its plain words (no @kinds, key:value filters,
--- -not / a|b words, sort:, nor a ">> channel"; a .command or /slash line: nothing), a space after them.
function UI.FuzzyPlain(text)
	local first = text:match("^%s*(.)")
	if first == "." or first == "/" then return "" end
	if ns.Share then
		local query, rest = ns.Share.Split(text)
		if rest then text = query end
	end
	local F, out = ns.Filters, {}
	for w in text:gmatch("%S+") do
		local key = w:match("^(%a+):")
		local skip = w:sub(1, 1) == "@" or w:find("^[-!]%a") or w:find("[|&]")
			or (F and F.SortOf and F.SortOf(w)) or (key and F and F.IsKey and F.IsKey(key))
		if not skip then out[#out + 1] = w end
	end
	return #out > 0 and (table.concat(out, " ") .. " ") or ""
end

local function PickCategory(e) UI:SetCategory(e.catId) end
local SOFT_PASS = 2.0 -- easy mode's relaxed pass: each everyday word a row passes (beats any score gap)

--- The words Questie's lists are looked up by in the overview: by name only, the typed words and the everyday words
--- as name words ("sword": NPCs called Sword...), never with a key:value filter.
local function OverviewNameWords(tokens, hard, softWords)
	local nameWords = tokens
	if softWords and not hard then
		nameWords = {}
		for k = 1, #tokens do nameWords[k] = tokens[k] end
		for k = 1, #softWords do nameWords[#nameWords + 1] = softWords[k] end
	end
	return nameWords
end

--- The overview's row for a category: its best match and how many more (Enter or a click picks it).
local function CategoryRow(c, best, bestScore, count)
	return {
		name = c.label, catId = c.id, kind = "category", icon = c.icon or QUESTION_MARK, kindLabel = "",
		detail = tostring(best) .. (count > 1 and ("  +%d more"):format(count - 1) or ""),
		staysOpen = true, activate = PickCategory, _score = bestScore or 0, _pos = NO_POS,
	}
end

--- Easy mode, typed before a category is picked: one row per category that has matches ("Bags  Rumsey Rum
--- +2 more"), the best match first; Enter or a click picks it. Questie's lists are counted by their name index.
--- Spread over frames like the search.
--- (fsig: the search's filter signature. When the words only grew since the last overview, under the same filters
--- and the same lists, each list is scanned from the rows that matched last time, not in full: lastOverview.)
function UI:EasyOverview(tokens, filters, hard, softs, softWords, fsig)
	local reuse, last = nil, self.lastOverview
	if last and fsig and last.sig == fsig and last.gen == ns.entriesGen and #tokens > 0 and Scan.Narrows(last.tokens, tokens) then
		reuse = last
	end
	local keep = { sig = fsig, tokens = tokens, rows = {} }
	local from = {} -- (the whole list each kept one was found in: SearchText takes the rows if their category opens)
	local overBudget = Scan.Budget(self)
	-- (pausing shows what's already on screen: an empty list collapsed the frame to the bare prompt for a frame)
	local function tick() if overBudget() then coroutine.yield(UI.Results()) end end
	local Pass = ns.Filters and ns.Filters.Pass
	local empty = #tokens == 0
	-- Questie's lists are looked up by name only (OverviewNameWords)
	local nameWords = OverviewNameWords(tokens, hard, softWords)
	-- relaxed: nothing anywhere passed every everyday word, so they only rank (as in RelaxSoft)
	local function scan(relaxed)
		local out = {}
		for _, c in ipairs(ns.Easy.Visible()) do
			local count, best, bestScore = 0, nil, nil
			local logged = 0 -- (quests from your log whose names Questie's lookup counts too: one quest, not two)
			for _, id in ipairs(c.kinds) do
				local p = ns.providers[id]
				if p and p.hintFind and not self.place then
					if #nameWords > 0 and not hard and not relaxed then
						local first, n = p.hintFind(p, nameWords, tick)
						if first and (n or 0) > 0 then
							if id == "questie" then n = math.max(0, n - logged) end
							count = count + n
							if not bestScore then best, bestScore = first, TEXT_SCORE end
						end
					end
				elseif p then
					local gen = ns.entriesGen
					local list = ns:GetEntries(p)
					local lkey = c.id .. "/" .. id
					local whole = list
					-- (a list rebuilt meanwhile is scanned in full: its old rows may be gone)
					if reuse and not relaxed and gen == ns.entriesGen and reuse.rows[lkey] then list = reuse.rows[lkey] end
					local kept = (not relaxed and not empty) and {} or nil
					if kept then keep.rows[lkey], from[lkey] = kept, whole end
					local need = filters
					if relaxed then need = hard end -- (nil: no typed key:value filter)
					for i = 1, #list do
						local e = list[i]
						local sc = (not c.keep or c.keep(e)) and (empty and 0 or ScoreEntry(e, tokens)) or nil
						if sc and (not need or Pass(e, need)) then
							-- (its score for the words kept on it: when this is the only category, its rows are listed
							-- without being scored again, Scan.Collect; a search writes every match's _score anyway)
							if kept then kept[#kept + 1] = e; e._score = sc end
							if relaxed then
								for k = 1, #softs do
									local ok, yes = pcall(softs[k], e)
									if ok and yes then sc = sc + SOFT_PASS * ns.Easy.Weight(softs[k]) end
								end
							end
							count = count + 1
							if not bestScore or sc > bestScore then best, bestScore = e.name, sc end
							if id == "quests" and #nameWords > 0 then
								local ln, all = rawget(e, "_lname") or "", true
								for w = 1, #nameWords do if not ln:find(nameWords[w], 1, true) then all = false break end end
								if all then logged = logged + 1 end
							end
						end
						if i % SLICE_CHECK == 0 then tick() end
					end
				end
			end
			if count > 0 then out[#out + 1] = CategoryRow(c, best, bestScore, count) end
		end
		return out
	end
	local out = scan(false)
	keep.gen = ns.entriesGen
	self.lastOverview = (fsig and #tokens > 0) and keep or nil
	self.lastOverviewReused = reuse ~= nil -- (tests)
	if #out == 0 and softs and not empty then
		out = scan(true)
		if #out > 0 then self.softRelaxed = true end
	end
	table.sort(out, function(a, b) return a._score > b._score end)
	if #out == 0 then return PseudoEntries({ EASY_NONE }) end
	-- (and what each category's lists had of the words, with the lists they were found in: Scan.SimpleScope)
	return out, keep, from
end


--- Easy mode: the typed words matched nothing that passes every everyday word. The rows with the words
--- (and every typed key:value filter) are listed instead, ranked by the everyday words they pass (what an item
--- is, "shield", counts for more than how rare it is: Easy.Weight).
function UI:RelaxSoft(included, tokens, hard, softs, out, overBudget)
	local Pass = ns.Filters and ns.Filters.Pass
	for _, p in ipairs(included) do
		local list = RowsOf(included, p)
		local id = p.id
		for i = 1, #list do
			local e = list[i]
			local sc = ScoreEntry(e, tokens)
			if sc and (not hard or Pass(e, hard)) then
				local passed = 0
				for k = 1, #softs do
					local ok, yes = pcall(softs[k], e)
					if ok and yes then passed = passed + ns.Easy.Weight(softs[k]) end
				end
				e._score = sc + passed * SOFT_PASS + FreqBonus(e, id) + (rawget(e, "_rank") or 0)
				out[#out + 1] = e
			end
			if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
		end
	end
	if #out > 0 then self.softRelaxed = true end
end

local NEAR_WORD = 1.0 -- a word matched by a close spelling (then each edit costs NEAR_EDIT)
local NEAR_EDIT = 10   -- (closer spellings always first; the usual score orders the rest)

--- The fallback when nothing has every typed word: rows whose name has, for each word it lacks, a
--- word within NearLimit edits ("fireblal": Fireball). Only runs on an empty result, so it may
--- cost more than the scan, but rows too short are skipped and it pauses with the search
--- (overBudget; never inside a pcall). Adds to `out`; the footer then says these are close spellings.
function UI:CloseSpellings(included, tokens, filters, out, overBudget)
	-- need: the shortest name that could hold a close spelling of one of the words
	local limits, need = {}, nil
	for i = 1, #tokens do
		limits[i] = NearLimit(#tokens[i])
		if limits[i] then
			local least = #tokens[i] - limits[i]
			if not need or least < need then need = least end
		end
	end
	if not need then return end
	local Pass = ns.Filters and ns.Filters.Pass
	local short, single = tokens.short, #tokens == 1
	for _, p in ipairs(included) do
		local list = RowsOf(included, p)
		if overBudget() then coroutine.yield(out) end
		local id = p.id
		for r = 1, #list do
			local e = list[r]
			local name, lname = e.name, rawget(e, "_lname")
			if type(name) == "string" and #name >= need then
				lname = lname or ns.Lower(name)
				local total, edits = 0, 0
				for i = 1, #tokens do
					local tk = tokens[i]
					-- (one word: nothing had it, so no row needs looking at as it is)
					local sc
					if not single then sc = TokenScore(tk, short and short[i], name, lname, RowText(e)) end
					if sc then
						total = total + sc
					else
						local d = limits[i] and NearWord(tk, lname, limits[i])
						if not d then total = nil break end
						total, edits = total + NEAR_WORD, edits + d
					end
				end
				if total and edits > 0 and (not filters or Pass(e, filters)) then
					e._score = total - edits * NEAR_EDIT + FreqBonus(e, id)
					e._pos = nil
					if not rawget(e, "_compact") then e._nameHit = true end
					out[#out + 1] = e
				end
			end
			if r % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
		end
	end
	if #out > 0 then self.closeSpellings = true end
end

-- the lists offered by that row, in order: big databases only searched with @kind
local HINT_KINDS = { "stored", "questie", "npc" }
-- a list's row is left out when one of your own results with every typed word in its name is of
-- these kinds: Questie's quests when the quest is in your log ("Steelsnap": your quest, and still
-- the row for Questie's NPC of that name). Lists not here are offered whatever you have (you have
-- no NPC rows); hintSecond lists (@stored: the same item on an alt) always are.
local HINT_SAME = { questie = { quests = true } }
UI.HINT_SAME = HINT_SAME

local function NameHasAll(e, tokens)
	local ln = rawget(e, "_lname") or (type(e.name) == "string" and ns.Lower(e.name)) or ""
	for i = 1, #tokens do
		if not ln:find(tokens[i], 1, true) then return false end
	end
	return true
end

-- (a row that writes into the prompt leaves a space after it, for the next word)
local function HintActivate(e)
	local t = e.completion
	if not t:find("%s$") then t = t .. " " end
	-- ("Search Questie for this" is a step: Shift+Left goes back; a pick list's "@item" is only typing)
	if e.syntaxRow then UI:SetQuery(t, #t) else UI:WalkTo(t, e) end
end

-- A list with this many matches or fewer shows them as results instead of a "Search ... for this"
-- row (a row to step through for one NPC was a wasted step). Questie's name index hands back as
-- many ids (Integrations' HINT_FEW, at least as many).
local HINT_FEW = 2
UI.HINT_FEW = HINT_FEW

--- What a big @kind list has of the words: the first name, how many (100 at most counted), and the rows themselves
--- when there are only fewMax or fewer (nil otherwise). Pauses with the search (overBudget, handing back res).
local function HintMatches(p, tokens, res, overBudget, fewMax)
	local firstName, count, few = nil, 0, nil
	if p.hintFind then
		-- the list's own name index (Questie's: one text, not its thousands of rows)
		local ids
		firstName, count, ids = p.hintFind(p, tokens, function() if overBudget() then coroutine.yield(res) end end)
		local want = math.min(count, fewMax)
		if firstName and count <= fewMax and p.hintRow and type(ids) == "table" and #ids >= want then
			few = {}
			for k = 1, want do
				local row = p.hintRow(p, ids[k])
				if not row then few = nil break end
				few[#few + 1] = row
			end
		end
	else
		local list = ns:GetEntries(p)
		few = {}
		for i = 1, #list do
			local e = list[i]
			if (p.hintFull and ScoreEntry(e, tokens)) or (not p.hintFull and NameHasAll(e, tokens)) then
				count = count + 1
				firstName = firstName or e.name
				if count <= fewMax then few[count] = e end
				if count >= 100 then break end
			end
			if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(res) end
		end
		if count > fewMax or count == 0 then few = nil end
	end
	return firstName, count, few
end

--- Only one or two: the rows themselves go where the hint would have gone (each once, and not one already listed).
local function AddFewRows(hints, few, res)
	for _, e in ipairs(few) do
		local dup = false
		for k = 1, #hints do if hints[k] == e then dup = true break end end
		for k = 1, #res do if res[k] == e then dup = true break end end
		if not dup then
			e._pos = nil
			if not rawget(e, "_compact") then e._nameHit = true end
			hints[#hints + 1] = e
		end
	end
end

--- The "Search <list> for this" row: Tab or Enter writes the @kind before the words.
local function HintRow(p, id, text, firstName, count)
	local kind = ns:KindName(p) or ("@" .. id)
	local query = text:gsub("^%s+", "")
	return {
		name = ("Search %s for this"):format(p.hintLabel or p.label), kindLabel = "|cff33ff99Tab|r",
		detail = firstName .. (count > 1 and ("  +%s more"):format(count >= 100 and "99" or count - 1) or ""),
		icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
		completion = kind .. " " .. query, staysOpen = true, activate = HintActivate,
		_score = math.huge, _pos = NO_POS,
	}
end

--- The "Search <list> for this" rows (and where they go), or nil. When an @kind list has a match:
--- by name (a plain substring look) in the huge lists, or a full match (hintFull: @stored, by item
--- and holder); on top, or second when your own results have the words in a name (see HINT_SAME).
--- A list with only HINT_FEW matches or fewer gives those rows instead of its hint row.
--- Spread over frames like the search.
function UI:BigListHint(text, tokens, res, overBudget)
	local typed = 0
	for i = 1, #tokens do typed = typed + #tokens[i] end
	if typed < 3 then return nil end
	-- your own results have it by name: a list is still offered, as the second row under your best
	-- one, unless one of yours is the same sort of thing (HINT_SAME: the quest in your log)
	local mine, kinds = false, nil
	for _, e in ipairs(res) do
		if NameHasAll(e, tokens) then
			mine = true
			kinds = kinds or {}
			kinds[e.kind or ""] = true
		end
	end
	local hints = {} -- one row per list that has it (a name can be a quest and an NPC both)
	local fewMax = UI.HINT_FEW -- (this many matches or fewer: the rows themselves)
	for _, id in ipairs(HINT_KINDS) do
		local p = ns.providers[id]
		local same = HINT_SAME[id]
		local covered = false
		if p and same and kinds and not p.hintSecond then
			for k in pairs(kinds) do
				if same[k] then covered = true break end
			end
		end
		if p and p.explicit and not covered then
			local firstName, count, few = HintMatches(p, tokens, res, overBudget, fewMax)
			if firstName and few and #few > 0 then
				-- only one or two: the rows themselves, where the hint would have gone
				AddFewRows(hints, few, res)
			elseif firstName then
				hints[#hints + 1] = HintRow(p, id, text, firstName, count)
			end
		end
	end
	if #hints > 0 then return hints, mine and 2 or 1 end
end

-- for the window (UI.lua): the "Search ... for this" rows' Enter
UI.HintActivate = HintActivate
