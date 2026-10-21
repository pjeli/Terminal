local ns = select(2, ...)
local L = ns.L

-- The search engine: the searches themselves (SearchText: Advanced and Simple mode, the Simple overview of categories,
-- fuzzy finding, the "Search Questie for this" rows, close spellings), command and argument rows, the empty terminal's
-- recent picks. Scoring a row and sorting the matches are in Score.lua. Moved out of UI.lua (0.43.15) as it was: the
-- window (UI.lua) shows what these give and runs them a slice at a time (UI:RunSearch).

local UI = ns.UI
local Fuzzy = ns.Fuzzy
local function EasyOn() return ns.Easy ~= nil and ns.Easy.On() end
local EASY_NONE = L["Nothing has that. Check the spelling, or try other words."]
local EASY_NO_NPCS = L["\"nearest\" needs Questie (or QuestieDB): it knows where NPCs stand."]
local EASY_NOWHERE = L["Can't tell where you are here (in a dungeon?)."]
local EASY_NONE_NEAR = L["None of those on this continent that Questie knows of."]
local EASY_TRAINERS_ONLY = L["None of those near you. Without Questie, Terminal knows only trainers (TrainerSpells'): install Questie for every other NPC."]
local EASY_NO_FLIGHTS = L["No flight path like that on this continent."]
local EASY_ALL_FLIGHTS = L["You know every flight path on this continent."]
local MISSING_GONE = L["Restart the game for the recipes you don't know: this update added a file, and a /reload doesn't load new files."]
local GROUP_QUESTS_GONE = L["Restart the game for party quests: this update added a file, and a /reload doesn't load new files."]
local EASY_FLIGHTS_UNCHECKED = L["Terminal doesn't know your flight paths here yet: open any flight master's map on this continent."]
local SLICE_CHECK = UI.SLICE_CHECK -- rows scored between looks at the clock
local QUESTION_MARK = 134400 -- (an icon for rows without one)
-- scoring and sorting (Score.lua), as locals: they run for every row
local Score = ns.Score
local NO_POS, TEXT_SCORE, MAX_RESULTS = Score.NO_POS, Score.TEXT_SCORE, Score.MAX_RESULTS
local FreqBonus, ScoreEntry, TokenScore, RowText = Score.FreqBonus, Score.ScoreEntry, Score.TokenScore, Score.RowText
local NearLimit, NearWord, SortAndTrim = Score.NearLimit, Score.NearWord, Score.SortAndTrim

local function PseudoEntries(lines) -- (lines saying something: ns.NoteRow each)
	local out = {}
	for i, line in ipairs(lines) do out[i] = ns.NoteRow(line) end
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

--- The typed words, split at spaces, but a "quoted phrase" is one string (0.52.13, the player's ask: "outlaw saber"
--- is one thing, not two words): the words, and the phrases (quote marks off, inner spaces as one) apart, in order.
--- An open quote runs to the end (while it's being typed). A quote inside a word joins the phrase to it, quote marks
--- off: in:"elwynn forest" is the word in:elwynn forest, -"outlaw saber" the word -outlaw saber.
function Scan.Words(text)
	local words, phrases = {}, {}
	text = text or ""
	local i, n = 1, #text
	while i <= n do
		local s = text:find("%S", i)
		if not s then break end
		local q = text:find('"', s, true)
		local e = (text:find("%s", s) or n + 1) - 1
		if q and q <= e then
			local close = text:find('"', q + 1, true) or n + 1
			local inside = text:sub(q + 1, close - 1):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
			local before = text:sub(s, q - 1)
			-- (what follows the closing quote up to the next space stays with it: "a b"c is the phrase, then c)
			local after_e = (text:find("%s", close + 1) or n + 1) - 1
			local after = close <= n and text:sub(close + 1, after_e) or ""
			if before == "" then
				if inside ~= "" then phrases[#phrases + 1] = inside end
				if after ~= "" then words[#words + 1] = after end
			elseif inside ~= "" or after ~= "" then
				words[#words + 1] = before .. inside .. after
			else
				words[#words + 1] = before
			end
			i = math.max(after_e, close) + 1
		else
			words[#words + 1] = text:sub(s, e)
			i = e + 1
		end
	end
	return words, phrases
end
ns.Words = Scan.Words -- (what's said of a search reads its words the same way: Share.lua)

--- Can the last keystroke's matches stand for these words? One more letter on the last word, or one more word, only
--- narrows (every row that has the new words had the old ones); never when the last word turned into shorthand
--- ("br" -> "brd": the shorthand matches rows the shorter word didn't), nor the other way ("sw" -> "swo": the
--- shorthand matched only its full name and the word itself).
function Scan.Narrows(last, tokens)
	local n, ln = #tokens, #last
	if n ~= ln and n ~= ln + 1 then return false end
	local ea, eb = last.exact, tokens.exact
	for i = 1, ln do
		local a, b = last[i], tokens[i]
		-- (a word turned into a "quoted phrase" or back: it matches other rows, not fewer of the same)
		if ((ea and ea[a]) or false) ~= ((eb and eb[b]) or false) then return false end
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
local cmdList, cmdGen -- the command rows, made again only when a command is registered (Core's commandsGen)

function UI:CommandEntries()
	if cmdList and cmdGen == ns.commandsGen then return cmdList end
	local list = {}
	for _, name in ipairs(ns.commandOrder) do
		local c = ns.commands[name]
		list[#list + 1] = {
			kind = "cmd",
			-- (your own aliases, Aliases.lua: labelled so, and what they run decides how: a search stays open on it, a
			-- slash command is pressed by the game, as a slash row is)
			kindLabel = "|cff33ff99" .. (c.isAlias and L["alias"] or L["cmd"]) .. "|r",
			staysOpen = c.staysOpen, secure = c.secure, isOpen = c.isOpen, after = c.after,
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
	cmdList, cmdGen = list, ns.commandsGen
	return list
end

local function RunArg(e) return e.cmd.run(e.argLine, ns) end

--- The arguments a command takes, as rows, while you type them: ".theme " lists the themes,
--- ".set cursor " the cursor styles. A command's `complete(args)` gives them, as strings or
--- { value, detail }. Each row runs the command with that argument (Enter, a click, or Tab and
--- the arrows to pick one). With nothing typed yet, the command itself comes first, so Enter
--- still runs it as typed. Nil when the command takes no listed arguments, or none match.
function UI:ArgEntries(text)
	-- (a password being typed: nothing offered for its words, Enter running what's typed. 0.59.0, review: ".share join raid
	-- correct horse at" + Enter joined with "correct horse mats", the completion's)
	if ns.SecretLine("." .. text) then return nil end
	local word, rest = text:match("^%s*(%S+)%s(.*)$")
	local c = word and ns:FindCommand(word)
	if not (c and c.complete) then return nil end
	local ok, list = pcall(c.complete, rest)
	if not ok or type(list) ~= "table" then return nil end
	local before, argWord = rest:match("^(.-)(%S*)$")
	local lw = ns.Lower(argWord)
	local whole = ns.Lower((rest:gsub("^%s+", "")))
	-- (a list with an argument of several words, "share on": its arguments are whole ones, matched against all that's
	-- typed; else each is the last word's, after the words before it. 0.51.5: "share on" matched by "on" ran
	-- "share share on")
	local several = false
	for _, cand in ipairs(list) do
		local v = type(cand) == "table" and cand[1] or cand
		if type(v) == "string" and v:find("%s") then several = true break end
	end
	local out = {}
	for i, cand in ipairs(list) do
		local val, detail = cand, nil
		if type(cand) == "table" then val, detail = cand[1], cand[2] end
		local lv = type(val) == "string" and ns.Lower(val)
		local at
		if several and lv then
			at = (lv:sub(1, #whole) == whole and 1) or (whole ~= "" and lv:find(whole, 1, true)) or nil
		else
			at = lv and (lw == "" and 1 or lv:find(lw, 1, true))
		end
		if at then
			out[#out + 1] = {
				kind = "cmd", kindLabel = "|cff33ff99." .. c.name .. "|r", icon = "Interface\\Icons\\INV_Misc_Note_01",
				name = val, _lname = lv, key = c.name .. " " .. val, freqKey = "cmd:" .. c.name,
				detail = detail or "", cmd = c, argLine = several and val or (before .. val), activate = RunArg, _nameHit = true,
				-- (an argument that searches, .missed's: Terminal stays open on it; the command's own word, else it closes)
				staysOpen = c.argStaysOpen and c.argStaysOpen(val) or nil,
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
--- A compact row's pick key ("kind:key"), made only when it can be one of the recent picks (`keys`: RecentKeys), or
--- for a key RecentKeys can't vouch for; nil otherwise (no string made per row of a big list).
local function CompactFreqKey(e, keys)
	local fk = rawget(e, "freqKey")
	if fk ~= nil then return fk end
	local key = rawget(e, "key")
	if key == nil or key == false then key = e.name end -- (as CompactMeta makes it: key, else name)
	if keys[key] then return e.freqKey end
	local t = type(key)
	if t ~= "string" and (t ~= "number" or key % 1 ~= 0 or key <= -1e14 or key >= 1e14) then return e.freqKey end
	return nil
end

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
			local picked -- (how often each of this list was picked, for its compact rows: once per list)
			for i = 1, #list do
				local e = list[i]
				local r, f
				if not e._compact then
					local fk = e.freqKey
					r, f = rank[fk], freq[fk]
				else
					-- (a compact row: its "kind:key" made only when it can be a recent pick, its count looked up by its own
					-- key; review, 0.53.6: two strings made per row of achievements, toys, maps... each time)
					keys = keys or RecentKeys(rank)
					local fk = CompactFreqKey(e, keys)
					r = fk ~= nil and rank[fk] or nil
					if picked == nil then picked = ns:FreqKind(id) or false end
					local key = rawget(e, "key")
					if key == nil or key == false then key = e.name end
					f = picked and key ~= nil and picked[key] or nil
				end
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
					keys = keys or RecentKeys(rank)
					fk = CompactFreqKey(e, keys)
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
			L["Type the name of anything: an item, a quest, a spell, a mount, a place, an NPC, an emote"],
			L["Start with what to do: use, cast, summon, equip, where, nearest (\"nearest innkeeper\")"],
			L["Ask in plain words: \"where should i level\", \"mats for thorium belt\", \"what killed me\""],
			L["Type a sum like  3*45g  or  12.5% of 800  for the calculator"],
			L["Right-click a result (or Shift+Right) to send it to chat, or every result at once"],
			L["Change the look with  .theme  and  .set , or  .options"],
		}, {
			L["Type to fuzzy-search items, quests (by text), spells, recipes, camp objects..."],
			L["Start with  /  for slash commands,  .  for terminal commands (try .help)"],
			L["Add  @questlog  /  @item  /  @recipe  to search a single kind (@questie: every quest, with Questie)"],
			L["Type a sum like  3*45g  or  12.5% of 800  for the calculator"],
			L["End a search with  >> party  (or guild, raid, say, whisper Name) to send the result to chat;  >>> party  sends every result at once"],
			L["Change the look with  .theme  and  .set , or  .options"],
		}))
	end
	return SortAndTrim(out)
end

UI.DATA_RETRY, UI.DATA_RETRIES = 1.1, 8 -- (seconds between, and how many: about 9 s of the game loading item data)
local BEST_BASE = 1e6 -- (sort:best: an upgrade's score, its gain added: above every other row's)

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
		ns:Trace(("search: item data was still loading, searching %q again (%d)"):format(ns.MaskSecret(text), r.tries))
		self.lastScan, self.lastExtra = nil, nil
		self.refreshedAt, self.searchedText = nil, nil
		self.quietRedo = true -- (the list stays as it is till this search is done: UI:Refresh)
		self:Refresh()
	end)
end

function UI:Search(text)
	if ns.Filters then
		ns.Filters.loading = nil
		ns.Filters.fitMade = nil -- (is:upgrade's filter says so when it's made: its rows' tooltips say why)
		if ns.Filters.ResetAsks then ns.Filters.ResetAsks() end -- (items the client hasn't loaded: a few asked per search)
	end
	-- arithmetic: the answer is the top result (see Calc.lua)
	local calc = not self.fzf and ns.Calc and ns.Calc.Entry(text)
	-- (a sum answered: its characters aren't words to look for close spellings of, nor is "Nothing has that" said
	-- under the answer; 0.50.7, review: "3*45g" ran a close-spellings pass over every list on each keystroke)
	self.calcAnswered = calc and true or nil
	local res = self:SearchText(text)
	if calc then
		for i = #res, 1, -1 do
			if res[i].noActivate and res[i].name == EASY_NONE then table.remove(res, i) end
		end
		table.insert(res, 1, calc)
	end
	-- "| sum value", "| group zone": what was found, summed up (Pipes.lua; its item data asked for as filters do)
	local agg = self.aggregate
	if agg and agg.fromBar and ns.Bar and ns.Bar.Overview(res) then agg = nil end -- (the bar's Group: not over the categories)
	-- (the rows before they're summed up: the bar's Sort and Group menus read what fields they have; Bar.lua)
	self.ungrouped = nil
	if agg and ns.Aggregate then self.ungrouped = res; res = ns.Aggregate.Apply(agg, res, agg.base) end
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
--- last ("mining trainer nearby"), taken out of the tokens. The action and its word, or nil.
function Scan.TakeAction(tokens, filters)
	local a = ns.Easy.Action(tokens[1])
	if a and (#tokens > 1 or filters) then
		return a, table.remove(tokens, 1)
	end
	if #tokens > 1 then
		-- "nearest"/"nearby"/"closest" said last: "mining trainer nearby"
		local b = ns.Easy.Action(tokens[#tokens])
		if b and b.nearest then
			return b, table.remove(tokens)
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

--- Simple mode's "nearest ...": a game object asked for ("nearest mailbox": QuestieDB's objects; an entrance) or flight
--- paths ("nearest unlearned flight master": Flights.lua) give their rows at once; else where you are, for the NPCs that
--- match. Returns the rows to list now (rows, or a line saying why not), or nil, your position and the faction filter to
--- add ("nearest repair": someone who'll serve you, so only NPCs friendly to your faction; "nearest hogger": a name,
--- anyone).
--- Simple mode's role words typed (trainer, vendor, innkeeper... soft or strict): the faction:friendly filter, else nil.
function Scan.RoleFriendly(softWords, strictWords)
	for _, list in ipairs({ softWords or false, strictWords or false }) do
		for _, w in ipairs(list or {}) do
			if ns.Easy.ROLE_WORDS[w] then return ns.Filters and ns.Filters.Parse("faction:friendly") end
		end
	end
	return nil
end

function Scan.NearestStart(tokens, filters, softWords, strictWords)
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
	return nil, here, Scan.RoleFriendly(softWords, strictWords)
end

--- A row with a distance, as a view saying how far and what it is ("120 yd  Mining Trainer", a spot row its zone:
--- "120 yd  The Barrens", or what it says after a distance: `distNote`; `nearRest`, which the arrow's live text keeps),
--- scored closest first.
local function NearView(e, d)
	local rest = rawget(e, "distNote") or (rawget(e, "wcont") and e.zone) or e.sub
	-- (an NPC in a dungeon: how far its entrance is, and which dungeon; 0.51.18)
	local inside = e.kind == "npc" and e.inDungeon
	if inside then rest = (rest and (rest .. ns.DETAIL_SEP) or "") .. L["in %s"]:format(inside) end
	return ns.Integrations.NearView(e, d, rest)
end
Scan.NearView = NearView -- (tests)
UI._Scan = Scan -- (tests)

--- Would row a's view (da yards away) sort before row b's (db)? Better (Score.lua) on the views NearView makes: the
--- score, then the name, then the key, read through to the rows as the views would.
local function Closer(da, a, db, b)
	local sa, sb = 1e6 - da, 1e6 - db
	if sa ~= sb then return sa > sb end
	local an, bn = a._lname or "", b._lname or ""
	if an ~= bn then return an < bn end
	return Score.KeyLess(a.key, b.key)
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
	-- "what should i do", "what now", "suggestions": what's worth doing now (Search/Suggest.lua; first: its lines are its own)
	Asks("Suggest"),
	-- "quests to turn in", "completed quests": your quest log's ready ones; "quests here": Questie's at your level in
	-- your zone (Search/Suggest.lua)
	Asks("TurnIn"),
	Asks("QuestsHere"),
	Asks("CanCraft"),
	-- "what dropped", "what did we get", "what did i loot": LootLog.lua (before chains: "what drops did we get" isn't "what drops <item>")
	{ ask = function(text) return ns.LootLog and ns.LootLog.Question(text) end,
		answer = function(q) return ns.LootLog.Answer(q) end,
		toAdvanced = function(q)
			return "@drop " .. ((q.who == "me" and "is:mine ") or (q.who and ("looter:" .. ns.Lower(q.who):gsub("%s+", "_") .. " ")) or "")
		end },
	-- "how do i get into mc", "how do i get attuned to onyxia": its steps (Search/Attune.lua; before the chains, whose "how
	-- do i get" is where to get an item)
	{ ask = function(text) local Q = ns.Attune and ns.Attune.Q return Q and Q.How(text) end,
		answer = function(q) return ns.Attune.Q.Answer(q) end,
		toAdvanced = function(q) return ns.Attune.Q.ToAdvanced(q) end },
	-- "spellid claw", "spell id 1082": SpellIds.lua (before the chains and searches: the words are a spell's name)
	{ ask = function(text) local S = ns.SpellIds return S and S.Question(text) end,
		answer = function(q) return ns.SpellIds.Answer(q) end,
		toAdvanced = function(q) return ns.SpellIds.ToAdvanced(q) end },
	-- "healing talents", "shaman crit talents", "druid regen talents": talents by what they do (Search/Talents.lua; before
	-- the chains and searches: "talents for crit" isn't a chain, "crit" and "healing" aren't an item's stats here)
	{ ask = function(text) local Q = ns.TalentsQ return Q and Q.Question(text) end,
		answer = function(q) return ns.TalentsQ.Answer(q) end,
		toAdvanced = function(q) return ns.TalentsQ.ToAdvanced(q) end },
	-- a chain ("thorium belt > mats", "mats for thorium belt"): Pipes.lua. (Simple mode takes only the plain words: a ">"
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
	-- don't know (Search/ProfTraining.lua; before What's Training's, whose "what can i train" is your class's spells)
	Asks("ProfTraining"),
	-- "what can i train", "what do i learn next level", "how much is training", "when do i learn fireball": What's
	-- Training's spells (Search/WhatsTraining.lua; after the recipes': "recipes i can learn" is theirs)
	{ ask = function(text) local Q = ns.WhatsTraining and ns.WhatsTraining.Q return Q and Q.Question(text) end,
		answer = function(q) return ns.WhatsTraining.Q.Answer(q) end,
		toAdvanced = function(q) return ns.WhatsTraining.Q.ToAdvanced(q) end },
	-- "druid spells", "upcoming spells", "when do i learn travel form": every class's spells (Search/ClassSpells.lua;
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
	-- "outlaw sabre quest", "quest for outlaw sabre": the quests rewarding it (Rewards.lua; only when the words name a
	-- quest reward, and no quest is called that)
	{ ask = function(text) return ns.QuestRewards and ns.QuestRewards.Question(text) end,
		answer = function(q) return ns.QuestRewards.Answer(q) end,
		toAdvanced = function(q) return ns.QuestRewards.ToAdvanced(q) end },
	-- "my attunements", "raid attunements", "my keys", "class quests": Attune's list (Search/Attune.lua; late: "dungeon quests
	-- to share", "grey dungeon quests" are the group's and the quest log's)
	{ ask = function(text) local Q = ns.Attune and ns.Attune.Q return Q and Q.List(text) end,
		answer = function(q) return ns.Attune.Q.Answer(q) end,
		toAdvanced = function(q) return ns.Attune.Q.ToAdvanced(q) end },
	-- "holidays", "what's on this week", "today", "next darkmoon faire", "my invites": Calendar.lua (last: its words name
	-- what's on the calendar, or it's a search)
	Asks("Calendar"),
}

--- A plain-word question or chain as Advanced mode writes it (Alt+`: Easy.ToAdvanced), or nil when the line is none.
--- (0.55.7, the search's rewrite: a question whose answer no search gives, ranked or gathered its own way, "where should i
--- level" by how well each zone fits, "my mail" with the auction house's news, stays as it was said: its toAdvanced says
--- nil. Questions are answered in Advanced mode too, so what's written finds what was shown; "@map lvl:23" didn't.)
function ns.QuestionToAdvanced(text)
	local function Print(t)
		for _, a in ipairs(Scan.ANSWERS) do
			local q, extra = a.ask(t, true)
			if q then
				local line = a.toAdvanced(q, extra)
				if line == nil then line = (t:gsub("^%s+", ""):gsub("%s+$", "")) .. " " end
				return line
			end
		end
	end
	-- (a chain with a sort after it: the chain, then the sort, as Scan.Answer reads it)
	if text:find(">", 1, true) then
		local rest, tail = Scan.SplitTail(text, true)
		local line = rest and Print(rest)
		if line then return (line:gsub("%s+$", "")) .. " " .. table.concat(tail, " ") .. " " end
	end
	local line = Print(text)
	if line then return line end
	-- (a question with Advanced filters or sorts after it, as Scan.Answer reads it: the question's form, then them;
	-- 0.55.18, review: "who crit me sort:name" was written as a search of its words, which found nothing)
	local rest, tail = Scan.SplitTail(text)
	line = rest and Print(rest)
	if line then return (line:gsub("%s+$", "")) .. " " .. table.concat(tail, " ") .. " " end
end

----------------------------------------------------------------------
-- The query printed: Advanced syntax for what a line asks (Alt+`, Advanced syntax typed after plain words, the right-
-- click menu's chat lines). 0.55.4, the search's rewrite: the line is read by the search's own steps and its query
-- written out, so what's printed is what's searched (Easy.lua's Convert read the words a second way, and drifted:
-- "vendor ratchet" said faction:friendly the search never asked for, a place needed other words the search didn't).
----------------------------------------------------------------------

--- `text` (plain words, maybe with Advanced syntax in it) as Advanced syntax, ending with a space to type on ("" for
--- nothing). category: Simple mode's category picked (its lists as @kinds); shown: the lists the rows shown come from
--- (E.ShownKinds), so an action or a category names only those ("use hearthstone": @item, not @camp @item @toy).
--- noGroup: leave the bar's group step out (the caller puts it after what follows).
function ns.QueryToAdvanced(text, category, shown, noGroup)
	text = ns.Easy and ns.Easy.English and ns.Easy.English(text) or text
	local asked = ns.QuestionToAdvanced(text)
	if asked then
		-- (a question: what Simple mode's bar picked after it, as its search takes them: Scan.AnswerView)
		local bar = ns.Easy and ns.Easy.On() and ns.Bar and ns.Bar.Active()
		if not bar then return asked end
		local line = asked:gsub("%s+$", "")
		for _, w in ipairs(bar.filters) do line = line .. " " .. w end
		if bar.sort then line = line .. " sort:" .. bar.sort end
		if bar.group and not noGroup then line = line .. " | group by " .. bar.group end
		return line .. " "
	end
	local scratch = {} -- (the steps say things to the window: not to this one)
	-- (the words read as plain words, whatever mode the terminal is in: Alt+` writes what Simple mode would search)
	local E = ns.Easy
	local was = E.reading
	E.reading = true
	local ok, q = pcall(function()
		local r = Scan.Parse(scratch, text)
		Scan.ActionAndPlace(scratch, r)
		Scan.Prepare(scratch, r)
		return r
	end)
	E.reading = was
	if not ok then error(q) end
	local out, seen = {}, {}
	local function Add(w) if w and w ~= "" and not seen[w] then seen[w] = true; out[#out + 1] = w end end
	local function KindWord(id) return ns:KindName(ns.providers[id]) end
	-- the lists: @kinds typed; an action's (those showing something; none showing: do:<word> stands for them all); a
	-- category's (those showing, else all of them); a trainer's word or "nearest": the NPCs
	local act = q.act
	local function AddKinds(set, all)
		local ids, n = {}, 0
		for k in pairs(set or {}) do if all or not shown or shown[k] then ids[#ids + 1] = k end end
		table.sort(ids)
		for _, k in ipairs(ids) do if ns.providers[k] then Add(KindWord(k)); n = n + 1 end end
		return n
	end
	if q.typedKinds then
		AddKinds(q.kinds, true)
	elseif act and act.map then
		local set = {}
		for k in pairs(act.map) do set[k] = true end
		AddKinds(set)
	elseif category and ns.Easy.BY_ID[category] then
		local set = {}
		for _, k in ipairs(ns.Easy.BY_ID[category].kinds) do set[k] = true end
		if AddKinds(set) == 0 then AddKinds(set, true) end
	end
	local nearest = act and act.nearest
	-- (0.55.18) the words shown found nothing passing every everyday word, so the closest were listed (UI.softRelaxed,
	-- this very line): those words written as words, not as filters nothing passes ("linen cloth": not type:cloth)
	local relaxed = {}
	local UIr = ns.UI
	local function Trim(t) return (t:gsub("^%s+", ""):gsub("%s+$", "")) end
	if UIr and UIr.softRelaxed and UIr.edit and ns.Lower(Trim(UIr.edit:GetText() or "")) == ns.Lower(Trim(text)) then
		for i, f in ipairs(q.softs or {}) do relaxed[f] = q.softWords and q.softWords[i] or true end
	end
	-- (an everyday word for a kind of item, "sword": that kind, or the word in a name; written so, sword|type:sword, as
	-- type:sword alone left out what's named so without the item data saying it; 0.55.18)
	local softWord = {}
	for i, f in ipairs(q.softs or {}) do softWord[f] = q.softWords and q.softWords[i] end
	local specs, plainWords = {}, {}
	for _, f in ipairs(q.filters or {}) do
		local spec = q.specOf and q.specOf[f]
		local w = softWord[f]
		if spec and w and spec:find("^type:") and not w:find("[%s|]") then spec = w .. "|" .. spec end
		if relaxed[f] then
			if type(relaxed[f]) == "string" then plainWords[#plainWords + 1] = relaxed[f] end
		elseif spec then
			specs[#specs + 1] = spec
		end
	end
	table.sort(specs, function(a, b) -- (a place first: "in:ratchet is:vendor"; else as said)
		local pa, pb = a:find("^in:") ~= nil, b:find("^in:") ~= nil
		if pa ~= pb then return pa end
		return false
	end)
	local I = ns.Integrations
	if nearest then
		-- "nearest mailbox": its own list, not NPCs; "nearest unlearned flight master": the flight paths' (the words that
		-- only say flight path or flight master go, @flight says it)
		local okind = I and I.ObjectKind and I.ObjectKind(q.tokens)
		if okind and ns.providers[okind] then
			local line = { "@" .. okind }
			for _, sp in ipairs(specs) do line[#line + 1] = sp end
			line[#line + 1] = "sort:nearest"
			return table.concat(line, " ") .. " "
		end
		local rest = I and I.FlightAsked and ns.providers.flight and I.FlightAsked(q.tokens, q.softWords, not ns.providers.npc)
		if rest then
			local SAID = { ["is:flight"] = true, ["is:flightmaster"] = true, ["is:flightpath"] = true }
			local line = { KindWord("flight") }
			for _, w in ipairs(rest) do line[#line + 1] = w end
			for _, sp in ipairs(specs) do if not SAID[sp] then line[#line + 1] = sp end end
			line[#line + 1] = "sort:nearest"
			return table.concat(line, " ") .. " "
		end
	end
	if q.trainerAsked or nearest then Add(KindWord("npc") or "@npc") end
	-- what Enter does stays what was asked ("use hearthstone": do:use)
	if act and act.map and not nearest and q.actWord then Add("do:" .. q.actWord) end
	for _, w in ipairs(q.tokens) do Add(q.exact and q.exact[w] and ('"' .. w .. '"') or w) end
	for _, w in ipairs(plainWords) do Add(w) end
	-- (a value of several words, read without its quotes, in:The Barrens: written with them again, in:"The Barrens";
	-- 0.55.16, the player's screenshot: Alt+` wrote in:The Barrens, which searched for "Barrens" as a word too)
	-- (each piece of a | or & list on its own, after its - or key: -"outlaw saber", type:dagger|"pirate saber"; review)
	local function Quoted(sp)
		if sp:find('"', 1, true) or not sp:find("%s") then return sp end
		return (sp:gsub("[^|&]+", function(piece)
			local neg, key, v = piece:match("^([-!]?)(%a+:)(.+)$")
			if not key then neg, v = piece:match("^([-!]?)(.+)$"); key = "" end
			if v and v:find("%s") then return neg .. key .. '"' .. v .. '"' end
			return piece
		end))
	end
	for i, sp in ipairs(specs) do specs[i] = Quoted(sp) end
	for _, sp in ipairs(specs) do Add(sp) end
	-- an NPC's role (trainer, vendor...) nearest: one who'll serve you (Scan.NearestStart)
	if nearest and Scan.RoleFriendly(q.softWords, q.strictWords) then Add("faction:friendly") end
	if nearest or q.sortNear then Add("sort:nearest") end
	if q.sortPlan then Add("sort:plan") end
	if q.sortBest then Add("sort:best") end
	if q.sortField then Add("sort:" .. q.sortField) end
	local line = table.concat(out, " ")
	if q.group and not noGroup then line = line .. (line ~= "" and " " or "") .. "| group by " .. q.group end
	return line ~= "" and (line .. " ") or ""
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
Scan.VOLATILE = { "is:ready", "is:offcooldown", "near:" }
function Scan.Volatile(t)
	t = t:lower()
	for _, v in ipairs(Scan.VOLATILE) do
		local at = t:find(v, 1, true)
		if at and (at == 1 or t:sub(at - 1, at - 1):find("[%s|!%-]")) then return true end
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

--- What a search tells the window, cleared for this one.
function Scan.ResetFlags(self)
	self.closeSpellings = nil -- (set when only close spellings matched: the footer says so)
	self.softRelaxed = nil -- (easy mode: nothing passed every everyday word, the closest shown: the footer says so)
	self.linkedGuess = {}
	self.linked = {} -- quest entry -> the item that brought it along (drawn with an arrow)
	self.answerNote, self.pipeTrail = nil, nil -- (a question's note, a chain's path: only for their own searches)
	self.flightNote = nil -- (flight paths listed on a continent no flight master's map was read on: Scan.FlightNote)
	self.missingNote = nil -- (recipes you don't know listed, a profession's window not read yet: MissingRecipes.LeadRow)
	self.overviewWinner = nil -- (Simple mode's overview: the clear winner shown above its categories: Scan.Overview)
	self.typedPicks = nil -- (Simple mode: the filters and the sort typed as words, which the bar shows: Bar.lua)
end

--- A chain or a question in plain words: its own answer (Scan.ANSWERS), not a search. The rows, or nil.
--- (0.55.7, the search's rewrite: an answer is filtered and sorted as a search is: Advanced filters and sorts typed after
--- the question, "my auctions q:rare+ sort:value", and Simple mode's bar; Scan.AnswerView. Its group was already: "| group
--- by" sums up any rows.)
function Scan.Answer(self, text)
	-- (a chain with a sort after it, "deadmines > steps sort:line": the chain, then sorted; 0.55.21. Only sorts: a filter
	-- typed at the end is the last step's own)
	if text:find(">", 1, true) then
		local rest, tail = Scan.SplitTail(text, true)
		local rows = rest and Scan.Ask(self, rest)
		if rows then return Scan.AnswerView(self, rows, tail) end
	end
	local rows = Scan.Ask(self, text)
	local tail
	if not rows then
		local rest
		rest, tail = Scan.SplitTail(text)
		if rest then rows = Scan.Ask(self, rest) end
		if not rows then return nil end
	end
	return Scan.AnswerView(self, rows, tail)
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
	local out, any = {}, false
	for _, e in ipairs(rows) do
		if not Real(e) then out[#out + 1] = e
		elseif #filters == 0 or F.Pass(e, filters) then out[#out + 1] = e; any = true end
	end
	if not any then
		local head = {}
		for _, e in ipairs(out) do if type(e) == "table" and (e.lead or e.raw) then head[#head + 1] = e end end
		head[#head + 1] = PseudoEntries({ EASY_NONE })[1]
		return head
	end
	if sort == "nearest" then
		local I = ns.Integrations
		local here = I and I.Here and I.Here()
		if not here then self.noPosition = true return out end
		local real, other = {}, {}
		for _, e in ipairs(out) do if Real(e) then real[#real + 1] = e else other[#other + 1] = e end end
		real = Scan.NearestViews(real, here, true, Scan.Budget(self))
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

--- The rows a search ends with (q.kinds as they are by then): its lists' lead lines on top.
function Scan.Finish(q, res)
	if q.kinds and q.kinds.flight then Scan.FlightNote(res) end
	-- a list that asks the server first (@who), or says why it lists nothing (@recipe is:unknown): its own row on top
	-- (given the rows so far)
	local function Leads(set)
		-- (in the lists' own order, the last one's on top: not the set's hash order, which could change between sessions;
		-- review, 0.53.6)
		for _, k in ipairs(ns.providerOrder) do
			local p = set[k] and ns.providers[k]
			local row = p and p.leadRow and p.leadRow(p, q.text, res)
			if row then row.lead = true; table.insert(res, 1, row) end -- (asks something: not a result to send)
		end
	end
	if q.kinds then Leads(q.kinds) end
	if q.also then Leads(q.also) end
	if q.missingGone then table.insert(res, 1, PseudoEntries({ MISSING_GONE })[1]) end
	if q.goneLine then table.insert(res, 1, PseudoEntries({ q.goneLine })[1]) end
	return res
end

--- The line read into the query: @kinds, sort:, do:, filters (key:value; Simple mode's everyday words), the words
--- searched, and what Simple mode's bar has picked. The query (q).
function Scan.Parse(self, text)
	local simple = EasyOn()
	local q = { text = text, simple = simple, tokens = {}, fsig = {} }
	self.noPosition = nil
	-- ("quoted phrases" apart: searched as one string each, never a filter or an everyday word; 0.52.13)
	local words, phrases = Scan.Words(text)
	-- Simple mode: two everyday words that mean one thing ("attack power food", "spell power"), "sword or axe" ->
	-- sword|axe, "not boe" -> -boe
	if simple then
		ns.Easy.JoinPairs(words)
		ns.Easy.JoinLogic(words)
	end
	local plainWord = simple and PlainWord or nil
	local F = ns.Filters
	local tokens, kinds = q.tokens, nil
	-- (Simple mode: the filters typed as words, for the bar to show as picked and take back out of the line: Bar.lua)
	local function Picked(spec, word)
		if simple and spec then q.picks = q.picks or {}; q.picks[#q.picks + 1] = { spec = spec, word = word } end
	end
	for _, w in ipairs(words) do
		-- (each word's sort: and do: read once, and lowered once; review, 0.53.6: up to three and five times a word)
		local lw = ns.Lower(w)
		local sort = F and F.SortOf and F.SortOf(w)
		local act, actWord
		if not sort and F and F.ActionOf then act, actWord = F.ActionOf(w) end
		if sort then
			-- sort:nearest, sort:plan (recipes that give skill, by how many times your materials make them: Plan.lua),
			-- sort:best (the biggest upgrades first), sort:name / level / ilvl / quality / value / count (Scan.Finalize)
			if sort == "plan" then q.sortPlan = true
			elseif sort == "best" then q.sortBest = true
			elseif sort == "nearest" then q.sortNear = true
			else q.sortField = sort end
			-- (Simple mode: the bar shows it as its Sort, and takes the word back out of the line: Bar.lua)
			if simple then q.typedSort = { id = sort, word = w, drop = true } end
			q.fsig[#q.fsig + 1] = "^" .. (sort == "nearest" and "near" or sort)
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
				Scan.AddFilter(q, f, "hard", lw, nil, spec)
				Picked(spec, w)
			elseif strict then
				Scan.AddFilter(q, strict, "strict", lw, lw, ns.Easy.WORDS[lw])
				Picked(ns.Easy.WORDS[lw], w)
				-- ("upgrades": the biggest first, as sort:best; 0.51.14, the player's ask)
				if ns.Easy.WORDS[lw] == "is:upgrade" then q.sortBest = true end
			else
				-- everyday words ("rare", "ready", "vendor") are soft filters in Simple mode (Easy.lua)
				local soft = ns.Easy and ns.Easy.Word(w)
				if soft then
					Scan.AddFilter(q, soft, "soft", "~" .. lw, lw, ns.Easy.WORDS[lw])
					Picked(ns.Easy.WORDS[lw], w)
				else
					tokens[#tokens + 1] = lw
				end
			end
		end
	end
	-- the "quoted phrases": words like any other, but each must be in a row as it is (Score: tokens.exact)
	for _, ph in ipairs(phrases) do
		local l = ns.Lower(ph)
		tokens[#tokens + 1] = l
		q.exact = q.exact or {}
		q.exact[l] = true
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
		if bar.sort == "nearest" then q.sortNear = true elseif bar.sort then q.sortField = bar.sort end
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

--- The action (an action word first, "use hearthstone"; a nearest-type word last; do:use) and a place named among the
--- words, taken out of them.
function Scan.ActionAndPlace(self, q)
	local simple = q.simple
	local act = q.advAct
	if simple and not act and q.tokens[1] then act, q.actWord = Scan.TakeAction(q.tokens, q.filters) end
	Scan.UseAction(q, act)
	-- Simple mode: a place named among the words ("vendor ratchet", "trainer in booty bay", "food barrens"): NPCs
	-- there, other rows that name it (Integrations.FindPlace / PlaceFilter); checked after the cheaper filters
	self.place = nil
	local I = ns.Integrations
	if simple and #q.tokens > 0 and I and I.FindPlace then
		local place, rest = I.FindPlace(q.tokens)
		if place and (#rest > 0 or q.filters or act) then
			q.tokens = rest
			Scan.AddFilter(q, I.PlaceFilter(place), "hard", "@" .. place.key, nil, "in:" .. tostring(place.key):gsub(" ", "_"))
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
	self.action = act
end

--- The words searched in the end (q.tokens, q.empty), and the ones to light up.
function Scan.Prepare(self, q)
	local tokens = q.tokens
	-- Simple mode: the little words of a sentence aren't asked for ("food that gives stamina", "shield from kresh")
	-- (a trainer's profession said: as an everyday word, the sentence's little words go: "mining trainer in org", "the
	-- enchanting trainer"; review, 0.49.17)
	if q.simple and #tokens > 0 then tokens = Scan.DropStop(tokens, q.softs or q.strictWords or q.trainerAsked) end
	tokens.exact = q.exact -- ("quoted phrases": as they are; DropStop's list is a new one)
	-- "brd", "strat", "sw": also the place's full name (Shorthand.lua), looked up once per search (before
	-- the Simple overview, which scores with them too)
	Scan.FillShorthand(tokens)
	-- (set before any early return: rows listed straight away, "nearest mailbox", light up these words, not the last search's)
	self.posTokens = tokens
	q.tokens, q.empty = tokens, #tokens == 0
end

--- Simple mode with no @kind typed: "nearest" (where you are; a game object or flight path listed at once), else a
--- category (picked, or the only one that has it). The rows to finish with instead of searching (just the prompt,
--- "nearest" stopping early, the categories to pick from), or nil: q.kinds, q.easyCat (and q.here) say what to search.
function Scan.SimpleScope(self, q)
	if not q.simple then return end
	-- (no reset of lastScan here: its signature holds the lists and filters searched, so a category picked for you, or
	-- by you, narrows keystroke by keystroke like Advanced does)
	-- a category picked for you (only one had it) is worked out again with every keystroke (an @kind typed: none; review,
	-- 0.55.18: the one opened for "horse" stayed on for "@item iron", the footer said Collections)
	if self.categoryAuto then self.category, self.categoryAuto = nil, nil end
	if q.typedKinds then return end
	if q.empty and not q.filters then
		self.category = nil
		-- just the prompt: its faint placeholder says what to type (UpdateGhost); Down asked for your recent picks
		if self.showRecent then return self:FrequentEntries() end
		-- (0.61.0, the player: "by default / empty, they can be presented with some suggestion results": a few things
		-- worth doing, from lists already read; .options turns it off)
		local SG = ns.Suggest
		if SG and not self.fzf then
			local rows = SG.EmptyRows()
			if #rows > 0 then
				self.answerNote = L["Things to do"]
				return rows
			end
		end
		return {}
	end
	local act = q.act
	if act and act.map then
		-- an action word: its lists (Scan.UseAction), no categories to pick from
		if act.nearest then
			local early, here, friendly = Scan.NearestStart(q.tokens, q.filters, q.softWords, q.strictWords)
			if early then return early end
			q.here = here
			Scan.AddFilter(q, friendly, "hard", "faction:friendly", nil, "faction:friendly")
		end
		return
	end
	local easyCat = self.category and ns.Easy.BY_ID[self.category]
	if not easyCat then return Scan.Overview(self, q) end -- (the categories; or the only one, opened for you)
	q.kinds, q.easyCat = ns.Easy.Kinds(easyCat.id), easyCat
	-- (a list only searched when asked, the recipes you don't know with is:unknown: with its category's; ALSO_CATEGORY)
	for id in pairs(q.also or {}) do if Scan.ALSO_CATEGORY[id] == easyCat.id then q.kinds[id] = true end end
	Scan.AddFilter(q, easyCat.keep, "hard", easyCat.keep and ("#" .. easyCat.id))
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
			-- (a list made from another, @gear from @item: stale while that one is, though it has no events of its own;
			-- review, 0.48.6: narrowing kept a sold sword in @gear)
			local src = p.follows and ns.providers[p.follows]
			if src and (src._dirty or not src._entries) then fresh = false end
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

--- Every row of the lists that has the words and passes the filters, scored; or the last keystroke's matches scored
--- again when the words only grew (Scan.Narrows). Spread over frames (q.overBudget, set here).
function Scan.Collect(self, q, included, sig, fresh)
	local empty, filters, tokens = q.empty, q.filters, q.tokens
	local Pass = ns.Filters and ns.Filters.Pass
	local out = {}
	-- typing one more letter, or one more word, can only narrow the matches: score just the last
	-- ones again (every one of them had the earlier words, so a new word still picks from them)
	-- (q.slot: which narrowing this is: the search's own, or the lists Simple mode's overview only counted, searched after
	-- it opened their category: Scan.Search)
	local slot = q.slot or "lastScan"
	local last = self[slot]
	if last and last.gen ~= ns.entriesGen then last, self[slot] = nil, nil end -- (its rows may be freed lists')
	local candidates
	if not empty and fresh and last and last.sig == sig and not q.volatile and Scan.Narrows(last.tokens, tokens) then
		candidates = last.matches
	end
	-- kind: the list's id when known (compact rows of kinds never picked are then not read for it)
	local function consider(e, kind, picked)
		if empty then
			if filters and not Pass(e, filters) then return end
			e._score = FreqBonus(e, kind, picked) + (rawget(e, "_rank") or 0)
			-- (compact rows get no field more: Render works their letters out on screen, none with no words)
			if rawget(e, "_compact") then e._pos = nil else e._pos = NO_POS end
			out[#out + 1] = e
		else
			local s = ScoreEntry(e, tokens)
			if s and (not filters or Pass(e, filters)) then -- (filters only on what matched: cheaper)
				e._score = s + FreqBonus(e, kind, picked) + (rawget(e, "_rank") or 0) -- (rank: a list's own order, < 1)
				out[#out + 1] = e
			end
		end
	end
	self.lastSearchNarrowed = candidates and true or false
	-- run by UI:RunSearch: past this frame's share, hand back what matched so far and go on
	-- in the next frame (tens of thousands of NPCs or quests no longer hitch one frame)
	local overBudget = Scan.Budget(self)
	-- (which list each run of matches came from, kept with them: narrowing the next keystroke gives each its list's id,
	-- so a compact row's pick history is looked up once per list, as the full scan does, not once per row; review,
	-- 0.53.6. A last mark with no id: rows added after, close spellings, are looked up per row as before)
	local spans = {}
	local function Span(id) spans[#spans + 1] = { from = #out + 1, id = id } end
	if candidates then
		local sp, j, id, picked = last.spans, 0, nil, nil
		for i = 1, #candidates do
			while sp and sp[j + 1] and sp[j + 1].from <= i do
				j = j + 1
				id = sp[j].id
				picked = id and ns:FreqKind(id) or nil
				Span(id)
			end
			consider(candidates[i], id, picked)
			if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
		end
	else
		for _, p in ipairs(included) do
			local list = RowsOf(included, p)
			if overBudget() then coroutine.yield(out) end -- (reading the list may have taken the share)
			local id = p.id
			Span(id)
			local picked = ns:FreqKind(id) -- (what was picked of this list: once, not per row)
			for i = 1, #list do
				consider(list[i], id, picked)
				if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
			end
		end
	end
	Span(nil)
	q.overBudget, q.spans = overBudget, spans
	return out
end

--- The matches kept for the next keystroke; nothing matched: Simple mode's closest by the everyday words, else close
--- spellings (added to out).
function Scan.Fallbacks(self, q, out, included, sig)
	local empty, tokens, hard, softs, overBudget = q.empty, q.tokens, q.hard, q.softs, q.overBudget
	if not empty then
		-- (out itself: SortAndTrim leaves it as it is; rows added to it below only make the net wider)
		-- (not while a filter met data still loading: the rows it couldn't judge are left out, and the next letter
		-- would narrow from what's left, judge nothing and never ask again)
		local slot = q.slot or "lastScan"
		if not (ns.Filters and ns.Filters.loading) then
			self[slot] = { sig = sig, gen = ns.entriesGen, tokens = tokens, matches = out, spans = q.spans }
		else
			self[slot] = nil
		end
		-- easy mode, nothing passed every everyday word ("rare shield wailing caverns" for a green shield):
		-- the rows with the typed words, those passing more of the everyday words first
		if #out == 0 and softs then self:RelaxSoft(included, tokens, hard, softs, out, overBudget) end
		-- nothing has every word: names within an edit or two of them ("hearhtstone"); not for a sum the calculator answered
		-- (nor for a sum: "lnen clth | count" counts nothing, not the close spellings; review, 0.53.6)
		-- (with the hard filters only: an everyday word, relaxed above, is no reason to leave a close spelling out)
		if #out == 0 and not self.calcAnswered and not (ns.Aggregate and ns.Aggregate.Summing(self.aggregate)) then
			self:CloseSpellings(included, tokens, hard, out, overBudget)
		end
	end
end

--- A category Simple mode's overview opened for you: its lists the overview only counted by name (Questie's, @stored)
--- searched now, as the overview found the rest (strictly, relaxed, or by close spellings), with a narrowing of their
--- own (lastExtra). The matches, those added to a copy of `matched`.
function Scan.Extra(self, q, matched)
	local out = {}
	for i = 1, #matched do out[i] = matched[i] end
	local eq = setmetatable({ kinds = q.extraKinds, slot = "lastExtra" }, { __index = q })
	local included, sig, fresh = Scan.Lists(eq)
	local narrowed = self.lastSearchNarrowed -- (the overview's: what the search narrowed is its matches, not these few lists)
	local more = Scan.Collect(self, eq, included, sig, fresh)
	self.lastSearchNarrowed = narrowed
	if not (ns.Filters and ns.Filters.loading) and not q.empty then
		self.lastExtra = { sig = sig, gen = ns.entriesGen, tokens = q.tokens, matches = more, spans = eq.spans }
	end
	if self.softRelaxed and q.softs and #more == 0 then
		more = {}
		self:RelaxSoft(included, q.tokens, q.hard, q.softs, more, eq.overBudget)
	elseif self.closeSpellings and #more == 0 then
		more = {}
		self:CloseSpellings(included, q.tokens, q.hard, more, eq.overBudget)
	end
	for i = 1, #more do out[#out + 1] = more[i] end
	return out
end

--- "nearest" / sort:nearest: the rows with a distance, closest first (Scan.NearestViews). The rows, and the rows to
--- stop with instead (none near), if any.
--- Does the search look at the NPCs alone (@npc, Simple mode's NPCs)?
function Scan.NpcOnly(kinds)
	if type(kinds) ~= "table" then return false end
	local any = false
	for k, v in pairs(kinds) do
		if v then
			if k ~= "npc" then return false end
			any = true
		end
	end
	return any
end

--- A list of NPCs alone, sorted nearest first by default (0.56.10, the player: "all NPC lists should be sorted by
--- nearest by default", trainers, merchants, reagent vendors). What was typed still counts first (release review: 120
--- nearer NPCs whose names had hogger's letters left Hogger out): an NPC named it, then those whose names have every
--- word, then the rest (a title's word, "reagent"); within each, the closest first, those with no place known last.
--- Only the best `limit` are kept (as many as the search keeps), each a view saying how far.
local function NearBand(e, tokens, n, joined)
	if n == 0 then return 0 end
	local ln = rawget(e, "_lname") or (type(e.name) == "string" and ns.Lower(e.name)) or ""
	if ln == joined then return 2 end
	for k = 1, n do if not ln:find(tokens[k], 1, true) then return 0 end end
	return 1
end
function Scan.NearDefault(out, here, tokens, limit, overBudget)
	local yards, n = ns.Integrations.RowYards, #tokens
	local joined = n > 0 and table.concat(tokens, " ") or nil
	local hc, he, hd, size = {}, {}, {}, 0 -- (a heap, the lowest on top: the best `limit` so far)
	local function Swap(a, b) hc[a], hc[b], he[a], he[b], hd[a], hd[b] = hc[b], hc[a], he[b], he[a], hd[b], hd[a] end
	local function Up(i)
		while i > 1 do
			local p = math.floor(i / 2)
			if hc[i] < hc[p] then Swap(i, p); i = p else return end
		end
	end
	local function Down(i)
		while true do
			local l, r, w = i * 2, i * 2 + 1, i
			if l <= size and hc[l] < hc[w] then w = l end
			if r <= size and hc[r] < hc[w] then w = r end
			if w == i then return end
			Swap(i, w); i = w
		end
	end
	for i = 1, #out do
		local e = out[i]
		local d = yards(e, here)
		local c = NearBand(e, tokens, n, joined) * 2e6 + (d and (1e6 - math.min(d, 999999)) or 0)
		if size < limit then
			size = size + 1
			hc[size], he[size], hd[size] = c, e, d
			Up(size)
		elseif c > hc[1] then
			hc[1], he[1], hd[1] = c, e, d
			Down(1)
		end
		if overBudget and i % 32 == 0 and overBudget() then
			local snap = {}
			for k = 1, size do snap[k] = he[k] end
			coroutine.yield(snap)
		end
	end
	local kept = {}
	for k = 1, size do
		local v = hd[k] and NearView(he[k], hd[k]) or setmetatable({}, { __index = he[k] })
		v._score = hc[k]
		kept[k] = v
	end
	return kept
end

function Scan.Nearest(self, q, out)
	local sortNear, here, overBudget = q.sortNear, q.here, q.overBudget
	-- a list of NPCs alone, no sort asked for: the nearest first (Scan.NearDefault); not where nothing's known of where
	-- you are, nor summed up ("@npc trainer | count": every match counted; release review)
	if not sortNear and not here and not q.sortField and not q.act and Scan.NpcOnly(q.kinds)
		and not (ns.Aggregate and ns.Aggregate.Summing(self.aggregate)) then
		local I = ns.Integrations
		here = I and I.Here and I.Here() or nil
		if here then
			q.here, q.nearDefault = here, true
			return Scan.NearDefault(out, here, q.tokens or {}, q.easyCat and Score.LIST_MAX or MAX_RESULTS, overBudget)
		end
	end
	-- "sort:nearest" (Advanced): where you are, once (an instance or no map: no sorting, the footer says so)
	if sortNear and not here then
		here = ns.Integrations and ns.Integrations.Here and ns.Integrations.Here()
		if not here then self.noPosition = true end
	end
	-- "nearest": the NPCs that matched, closest first, how far in the detail column (none known: left out;
	-- sort:nearest keeps every other row, after the NPCs, as a weapon's trainers do: q.keepFar, Scan.TrainerWords)
	if here then
		local keep = sortNear or q.keepFar
		out = Scan.NearestViews(out, here, keep, overBudget)
		if #out == 0 and not keep then
			-- (TrainerSpells' trainers as @npc, no Questie: only trainers are known; 0.57.1)
			local p = ns.providers.npc
			return out, PseudoEntries({ (p and p.trainersOnly) and EASY_TRAINERS_ONLY or EASY_NONE_NEAR })
		end
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
	-- (summed up, "| count": only what was found, no quest brought along)
	if not empty and (not kinds or kinds.quests) and not self.aggregate then LinkQuests(out) end
	-- sort:best (Simple mode's "upgrades"): the biggest upgrades first, by how much each beats what you wear (the gain
	-- is:upgrade worked out for it); the other rows after them, as they were
	if q.sortBest and ns.Filters and ns.Filters.GainOf and ns.Filters.fitMade then
		local GainOf = ns.Filters.GainOf
		for i = 1, #out do
			local g = GainOf(out[i])
			if g then out[i]._score = BEST_BASE + g.gain end
		end
	end
	-- (a Simple mode category: every match its row counted, up to Score.LIST_MAX; not "nearest", measured for the
	-- closest MAX_RESULTS only)
	-- (summed up, "| sum value": every match as it is, nothing to sort or trim; release review: at most 5000 counted)
	if ns.Aggregate and ns.Aggregate.Summing(self.aggregate) then
		-- (a quest in your log counted once, not with its Questie copy too; review, 0.53.6)
		if kinds and kinds.quests and kinds.questie then out = Scan.OneQuest(out) end
		return out
	end
	-- (Simple mode's bar: sorted by name, level, value... the rows that have it first, in its order; Bar.lua)
	if q.sortField and ns.Bar then ns.Bar.SortRows(out, q.sortField) end
	local limit = (q.easyCat and (not q.here or q.nearDefault)) and Score.LIST_MAX or nil
	local res = SortAndTrim(out, limit, overBudget)
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
	-- a phrase in the client's language: the English line it stands for (Easy.lua's E.PHRASES)
	if ns.Easy and ns.Easy.English then text = ns.Easy.English(text) end
	-- a chain or a question in plain words: its own answer, not a search (Scan.ANSWERS)
	local answer = Scan.Answer(self, text)
	if answer then return answer end
	local q = Scan.Parse(self, text)
	Scan.ActionAndPlace(self, q)
	Scan.Prepare(self, q)
	if q.simple then
		local act = q.act
		self.typedPicks = { filters = q.picks or {}, sort = q.typedSort or (act and act.nearest and q.actWord and { id = "nearest", word = q.actWord }) or nil }
	end
	local rows = Scan.SimpleScope(self, q)
	if rows then return Scan.Finish(q, rows) end
	-- nothing typed: just the prompt (Down brings back the last search, else your recent picks)
	if q.empty and not q.kinds and not q.filters then
		self.lastScan, self.lastExtra = nil, nil
		if self.showRecent then return self:FrequentEntries() end
		return {}
	end
	-- (a category the overview opened for you: its matches are found already, and its lists only counted are searched
	-- now; else the search)
	local out = q.matched
	if out then
		if q.extraKinds then out = Scan.Extra(self, q, out) end
	else
		local included, sig, fresh = Scan.Lists(q)
		out = Scan.Collect(self, q, included, sig, fresh)
		Scan.Fallbacks(self, q, out, included, sig)
	end
	-- easy mode: nothing in the picked category: the categories that have it instead
	if q.easyCat and #out == 0 then
		local keep = q.easyCat.keep
		self.category, self.categoryAuto, self.closeSpellings, self.softRelaxed = nil, nil, nil, nil
		-- (with the search's own signature, the category's test and "#id" left out, and what was typed: the clear winner
		-- and narrowing as when no category was picked; review, 0.48.6)
		if keep then Scan.DropFilters(q, { [keep] = true }, "#" .. q.easyCat.id) end
		q.kinds, q.easyCat = nil, nil
		return Scan.Finish(q, Scan.Overview(self, q, true))
	end
	local stop
	out, stop = Scan.Nearest(self, q, out)
	if stop then return Scan.Finish(q, stop) end
	-- "sort:plan": the recipes that still give skill, by the crafts your materials cover; the footer says the skill
	if q.sortPlan and ns.Plan then
		local note
		out, note = ns.Plan.Rows(out)
		self.answerNote = note
	end
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
		for i = n, 1, -1 do -- (the last word first: narrowing, only it can turn a row away)
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
	if ns.Aggregate then text = (ns.Aggregate.Split(text)) end -- (nor "| sum value")
	-- (quoted phrases as their words, no quote marks: every letter is searched there; a quoted filter value stays with its
	-- filter; release review)
	local words, phrases = Scan.Words(text)
	local F, out = ns.Filters, {}
	for _, w in ipairs(words) do
		local key = w:match("^(%a+):")
		local skip = w:sub(1, 1) == "@" or w:find("^[-!][%a\128-\255]") or w:find("[|&]") -- ("-малое" too, 0.49.2)
			or (F and F.SortOf and F.SortOf(w)) or (key and F and F.IsKey and F.IsKey(key))
		if not skip then out[#out + 1] = w end
	end
	for _, ph in ipairs(phrases) do out[#out + 1] = ph end
	return #out > 0 and (table.concat(out, " ") .. " ") or ""
end

-- Ranking the categories (0.56.11, the player: "reagent" listed NPCs last, under a keybinding named Toggle Reagent Bag,
-- when three dozen reagent vendors matched). A category's best match decides, as before; Questie's lists are scored
-- as a row would be (HintScore: they were all given the lowest score, a match in some text), and then:
local ROLE_MIN, ROLE_BONUS = 3, 2.0 -- a word that is the title of several NPCs names a job (Reagent Vendor): those are wanted
local BREADTH, BREADTH_MAX = 0.15, 0.75 -- more matches, a little higher (by log2 of the count): close best matches told apart
local PICK_BONUS, PICK_MAX = 1.0, 3 -- each time the category was picked for these words (db.catPicks), up to three times
local PICKS_KEPT = 300 -- (words remembered; the longest unused go first)

--- The categories picked for these words before (Simple mode's overview): category id -> times, the words as typed
--- counting fully and longer ones they start ("reag" as "reagent" is typed) for half. Empty when there are none.
function UI.CategoryPicks(want)
	local all, out = ns.db and ns.db.catPicks, {}
	if type(all) ~= "table" or type(want) ~= "string" then return out end
	local exact, longer = {}, {}
	local function Add(into, t)
		for cat, n in pairs(t) do
			if cat ~= "t" and type(n) == "number" then into[cat] = (into[cat] or 0) + math.min(n, PICK_MAX) end
		end
	end
	if type(all[want]) == "table" then Add(exact, all[want]) end
	if #want >= 3 then
		for text, t in pairs(all) do
			if text ~= want and type(t) == "table" and text:sub(1, #want) == want then Add(longer, t) end
		end
	end
	-- (up to three picks in all: the longer words' together count half, never more; release review: "reagent",
	-- "reagents" and "reagent vendor" added up to 4.5 for "rea")
	for cat, n in pairs(exact) do out[cat] = n end
	for cat, n in pairs(longer) do out[cat] = math.min(PICK_MAX, (out[cat] or 0) + math.min(n, PICK_MAX) * 0.5) end
	return out
end

--- A category picked from the overview for these words (Enter, a click, Tab): remembered for the next time.
function UI.NoteCategoryPick(want, catId)
	if type(want) ~= "string" or want == "" or type(catId) ~= "string" or not ns.db then return end
	local all = ns.db.catPicks
	if type(all) ~= "table" then all = {}; ns.db.catPicks = all end
	local t = all[want]
	if type(t) ~= "table" then
		t = {}
		all[want] = t
		local n, oldest, oldestT = 0, nil, nil
		for text, o in pairs(all) do
			n = n + 1
			local ot = type(o) == "table" and tonumber(o.t) or 0
			if text ~= want and (not oldestT or ot < oldestT) then oldest, oldestT = text, ot end
		end
		if n > PICKS_KEPT and oldest then all[oldest] = nil end
	end
	t[catId] = math.min((t[catId] or 0) + 1, PICK_MAX)
	t.t = time and time() or 0
end

--- What a category's row adds to its best match: its count, a job's title (Questie's NPCs), the player's picks.
local function CategoryBonus(b, count, picks)
	local bonus = math.min(BREADTH_MAX, BREADTH * math.log(math.max(count, 1)) / math.log(2))
	if b.role then bonus = bonus + ROLE_BONUS end
	return bonus + (picks[b.c.id] or 0) * PICK_BONUS
end

--- A Questie list's first match, scored as a row of it would be: each word by its score in the name, else in the
--- NPC's title (the index line's "<...>"), else as found in some text. And whether a word was only in the title.
local function HintScore(words, first, line)
	local name, title
	if type(line) == "string" then
		name, title = line:match("^(.-) <(.*)>$")
		name = name or line
	else
		name = ns.Lower(tostring(first))
	end
	local total, inTitle = 0, false
	for k = 1, #words do
		local s = Fuzzy.score(words[k], name)
		if not s and title then
			s = Fuzzy.score(words[k], title)
			if s then inTitle = true end
		end
		total = total + (s or TEXT_SCORE)
	end
	return total, inTitle
end
UI._HintScore = HintScore -- (tests)

local function PickCategory(e)
	UI.NoteCategoryPick(e.pickText, e.catId)
	UI:SetCategory(e.catId)
end
local SOFT_PASS = 2.0 -- easy mode's relaxed pass: each everyday word a row passes (beats any score gap)

--- How many of Simple mode's everyday words a row passes, each counted by its weight (Easy.Weight: "shield" counts for
--- more than "rare"). `weights`: SoftWeights(softs), worked out once per search, not per row (review, 0.53.6: the
--- overview and RelaxSoft each had a copy, weighing every filter again for every row).
local function SoftWeights(softs)
	local w = {}
	for k = 1, #softs do w[k] = ns.Easy.Weight(softs[k]) end
	return w
end
local function SoftPassed(softs, weights, e)
	local passed = 0
	for k = 1, #softs do
		local ok, yes = pcall(softs[k], e)
		if ok and yes then passed = passed + weights[k] end
	end
	return passed
end

--- The words Questie's lists are looked up by in the overview: by name only, the typed words and the everyday words
--- as name words ("sword": NPCs called Sword...; "battlemaster", a strict one: NPCs titled so), never with any other
--- hard filter (a "not", an "or").
local function OverviewNameWords(tokens, hard, softWords, strictWords)
	local nameWords = tokens
	if (softWords or strictWords) and not hard then
		nameWords = {}
		for k = 1, #tokens do nameWords[k] = tokens[k] end
		for _, list in ipairs({ softWords or false, strictWords or false }) do
			for k = 1, list and #list or 0 do nameWords[#nameWords + 1] = list[k] end
		end
	end
	return nameWords
end

--- What was typed, as a name would be written (lowercase, one space between words), for the overview's clear winner.
function Scan.Typed(text)
	if type(text) ~= "string" then return nil end
	local t = ns.Lower(text):gsub('"', ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	if t == "" then return nil end
	return t
end

-- A category of several lists: which of them had matches, after its name, as the results' kind column names them
-- (0.48.4, the player: "Game  World Map +3 more" didn't say the 3 were keybindings), the most matches first.
local KINDS_SHOWN = 3
local function KindsNote(c, counts)
	local loaded, found = 0, {}
	for i, id in ipairs(c.kinds) do
		local p = ns.providers[id]
		if p then
			loaded = loaded + 1
			if (counts[id] or 0) > 0 then found[#found + 1] = { p = p, n = counts[id], i = i } end
		end
	end
	if loaded < 2 or #found == 0 then return nil end
	table.sort(found, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.i < b.i end)
	local parts = {}
	for k = 1, math.min(#found, KINDS_SHOWN) do
		local p = found[k].p
		parts[k] = ns:KindLabel(p)
	end
	local note = table.concat(parts, ns.DETAIL_SEP)
	if #found > KINDS_SHOWN then note = note .. "  " .. L["+%d more"]:format(#found - KINDS_SHOWN) end
	return note
end

--- The overview's row for a category: its best match and how many more (Enter or a click picks it), and what it holds.
local function CategoryRow(c, best, bestScore, count, counts, hinted)
	return {
		count = count, countExact = not hinted or nil, -- (what stepping in should list: UI:SetCategory, UI:NoteCountChange)
		name = c.label, catId = c.id, kind = "category", icon = c.icon or QUESTION_MARK, kindLabel = "",
		detail = tostring(best) .. (count > 1 and ("  " .. L["+%d more"]:format(count - 1)) or ""),
		labelNote = KindsNote(c, counts),
		staysOpen = true, activate = PickCategory, _score = bestScore or 0, _pos = NO_POS,
	}
end

-- The clear winner (0.48.4, the player's ask): a row named exactly what was typed ("world map", "hearthstone"; a
-- leading "the", or a command's "/" or ".", not needed), shown above the categories to act on at once. Only when every
-- such row is in one category, and there are no more than WINNER_MAX of them (your bags' Hearthstone and the one on an
-- alt: one thing); names in two categories (Mining, the profession and the skill) are for the categories to tell apart.
local WINNER_MAX = 2
local function ExactName(name, want)
	if type(name) ~= "string" then return false end
	-- (by length first: it's asked of every match, thousands in a broad search; nothing made unless it may be it)
	local n, w = #name, #want
	if n == w then return name == want end
	if n == w + 1 then
		local b = name:byte(1)
		return (b == 47 or b == 46) and name:sub(2) == want -- ("/dance", ".mem")
	end
	if n == w + 4 then return name:sub(1, 4) == "the " and name:sub(5) == want end
	return false
end
local function Winner(exacts, cats)
	if cats < 2 or #exacts == 0 or #exacts > WINNER_MAX then return nil end
	local best
	for _, x in ipairs(exacts) do
		if x.cat ~= exacts[1].cat then return nil end
		if not best or x.sc > best.sc then best = x end
	end
	return best.e
end

--- Simple mode, before a category is picked: one row per category that has matches ("Items  Rumsey Rum +2 more", and
--- which of its lists had them), the best match first; Enter or a click picks it. A row named exactly what was typed
--- (Scan.Typed) goes above them when it's the clear winner (Winner). 0.55.5, the search's rewrite: a view of one search,
--- not a second one. The lists of every category are searched as any search is (Scan.Collect: the same scoring,
--- narrowing, relaxing and close spellings), then the matches are grouped by category (Easy.CategoryOf); Questie's lists
--- are counted by their name index (hintFind), as reading them whole on every keystroke would cost too much.
--- Returns the category rows; or nil, with the only category that has matches opened for you (self.category,
--- categoryAuto; q.kinds, q.easyCat) and its rows in q.matched when they're all here (none of them only counted).
--- noAuto: the category rows even when there's one (a picked category that had nothing: Scan.Search's fallback).
-- A list only searched when asked for (Scan.Parse's q.also, "is:unknown": the recipes you don't know) and the category
-- its rows show in, in Simple mode (0.55.18, review: typed there, it found nothing).
Scan.ALSO_CATEGORY = { missing = "crafting" }

function Scan.Overview(self, q, noAuto)
	local tokens, empty = q.tokens, q.empty
	-- the lists: every category's, but Questie's (counted by name below)
	local kinds, hinting = {}, {}
	for _, c in ipairs(ns.Easy.Visible()) do
		for _, id in ipairs(c.kinds) do
			local p = ns.providers[id]
			-- (with a place, read whole: a name lookup can't say where)
			if p and p.hintFind and not self.place then hinting[#hinting + 1] = { c = c, p = p } elseif p then kinds[id] = true end
		end
	end
	for id in pairs(q.also or {}) do if ns.providers[id] and Scan.ALSO_CATEGORY[id] then kinds[id] = true end end
	local oq = setmetatable({ kinds = kinds }, { __index = q }) -- (the query, over those lists)
	local included, sig, fresh = Scan.Lists(oq)
	local out = Scan.Collect(self, oq, included, sig, fresh)
	Scan.Fallbacks(self, oq, out, included, sig)
	q.overBudget = oq.overBudget
	local relaxed = self.softRelaxed or self.closeSpellings
	-- each match to its category (a list in two categories, the slash commands and the emotes, by the category's test)
	local byCat, order = {}, {}
	local want = Scan.Typed(q.text)
	local exacts = {} -- (rows named exactly what was typed: the clear winner, maybe)
	local loggedNames = {} -- (your quest log's matches: Questie's name count has them too)
	local overBudget = q.overBudget
	for i, e in ipairs(out) do
		-- (spread over frames too: 0.59.0, the stress test, 200,000 matches sorted into categories in one frame)
		if overBudget and i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(UI.Results()) end
		local c = ns.Easy.BY_ID[ns.Easy.CategoryOf(e) or Scan.ALSO_CATEGORY[e.kind] or ""]
		if c then
			local b = byCat[c.id]
			if not b then b = { c = c, rows = {}, counts = {} }; byCat[c.id] = b; order[#order + 1] = b end
			b.rows[#b.rows + 1] = e
			b.counts[e.kind] = (b.counts[e.kind] or 0) + 1
			if not b.score or e._score > b.score then b.best, b.score = e.name, e._score end
			if want and not relaxed and not empty and not e.noActivate
				and ExactName(rawget(e, "_lname") or (type(e.name) == "string" and ns.Lower(e.name)), want) then
				exacts[#exacts + 1] = { e = e, cat = c.id, sc = e._score }
			end
			if e.kind == "quests" then loggedNames[#loggedNames + 1] = rawget(e, "_lname") or "" end
		end
	end
	-- Questie's lists, by name (the typed words and the everyday words as name words; never with another hard filter,
	-- which a name can't be judged by, nor with a place, nor once nothing passed the everyday words)
	local hardOther = q.hard and #q.hard > (q.strictWords and #q.strictWords or 0) or nil
	local nameWords = OverviewNameWords(tokens, hardOther, q.softWords, q.strictWords)
	if #nameWords > 0 and not hardOther and not relaxed and not self.place then
		local function tick() if overBudget and overBudget() then coroutine.yield(UI.Results()) end end
		for _, h in ipairs(hinting) do
			local c, p = h.c, h.p
			local first, n, ids, line = p.hintFind(p, nameWords, tick)
			if first and (n or 0) > 0 then
				if p.id == "questie" then -- (a quest from your log counted once: its row here, not Questie's name count too)
					for _, ln in ipairs(loggedNames) do
						local all = true
						for w = 1, #nameWords do if not ln:find(nameWords[w], 1, true) then all = false break end end
						if all then n = n - 1 end
					end
					n = math.max(0, n)
				end
				if n > 0 then
					local b = byCat[c.id]
					if not b then b = { c = c, rows = {}, counts = {} }; byCat[c.id] = b; order[#order + 1] = b end
					b.hinted, b.n = true, (b.n or 0) + n
					b.counts[p.id] = (b.counts[p.id] or 0) + n
					local sc, inTitle = HintScore(nameWords, first, line)
					if inTitle and n >= ROLE_MIN then b.role = true end
					if not b.score or sc > b.score then b.best, b.score = first, sc end
					-- (the only one, named exactly that: Hogger)
					if want and not empty and n == 1 and ExactName(ns.Lower(tostring(first)), want) and p.hintRow
						and type(ids) == "table" and ids[1] then
						local row = p.hintRow(p, ids[1])
						if row and not row.noActivate then
							if row._score == nil then row._score = TEXT_SCORE end
							exacts[#exacts + 1] = { e = row, cat = c.id, sc = TEXT_SCORE + FreqBonus(row, p.id) }
						end
					end
				end
			end
		end
	end
	self.overviewWinner = nil
	local rows = {}
	local picks = UI.CategoryPicks(want)
	for _, b in ipairs(order) do
		local count = #b.rows + (b.n or 0)
		local row = CategoryRow(b.c, b.best, b.score, count, b.counts, b.hinted)
		row._score, row.pickText = row._score + CategoryBonus(b, count, picks), want
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b) return a._score > b._score end)
	if #rows == 0 then
		-- (0.56.2, the player: "Did you mean...?") the phrases closest to it, under the note; the note keeps what was
		-- typed, for .missed when the terminal closes on it (DidYouMean.lua)
		local none = PseudoEntries({ EASY_NONE })
		none[1].missedText = q.text
		local DYM = ns.DidYouMean
		for _, r in ipairs(DYM and not empty and DYM.Rows(q.text) or {}) do none[#none + 1] = r end
		return none
	end
	-- only one category has it: straight to its results (no step to take); its rows are these, unless some were only
	-- counted by name (Questie's: then the category is searched as picked)
	if #rows == 1 and not noAuto then
		local b = byCat[rows[1].catId]
		self.category, self.categoryAuto = b.c.id, true
		q.kinds, q.easyCat = ns.Easy.Kinds(b.c.id), b.c
		for id in pairs(q.also or {}) do if Scan.ALSO_CATEGORY[id] == b.c.id then q.kinds[id] = true end end
		Scan.AddFilter(q, b.c.keep, "hard", b.c.keep and ("#" .. b.c.id))
		-- its matches are found already; its lists only counted by name (Questie's, @stored) are searched after (q.extraKinds)
		q.matched = b.rows
		for _, h in ipairs(hinting) do
			if h.c == b.c then q.extraKinds = q.extraKinds or {}; q.extraKinds[h.p.id] = true end
		end
		return nil
	end
	-- copying every result ("linen to csv"): every category's rows, not the categories themselves (release review: the
	-- CSV had a line per category); summed up too, "q:rare type:sword | group by dungeon" (0.55.12, the player's
	-- screenshot: the categories were grouped, none has a dungeon: 0 results)
	local summing = ns.Aggregate and ns.Aggregate.Summing(self.aggregate)
	if not noAuto and ((self.sendTo and self.sendTo.copy and self.sendTo.all) or summing) then
		q.kinds = {}
		for _, b in ipairs(order) do for k in pairs(ns.Easy.Kinds(b.c.id) or {}) do q.kinds[k] = true end end
		-- (the rows found already, the lists only counted by name searched after: not every list read a second time, which
		-- also took the overview's narrowing away; 0.55.18, review: two full passes a keystroke)
		local cats = {}
		for _, b in ipairs(order) do cats[b.c] = true end
		q.matched = out
		for _, h in ipairs(hinting) do
			if cats[h.c] then q.extraKinds = q.extraKinds or {}; q.extraKinds[h.p.id] = true end
		end
		return nil
	end
	-- (the clear winner on top, to act on at once; the categories still narrow the rest)
	local winner = not relaxed and Winner(exacts, #rows) or nil
	if winner then
		table.insert(rows, 1, winner)
		self.overviewWinner = winner
	end
	return rows
end

--- Easy mode: the typed words matched nothing that passes every everyday word. The rows with the words
--- (and every typed key:value filter) are listed instead, ranked by the everyday words they pass (what an item
--- is, "shield", counts for more than how rare it is: Easy.Weight).
function UI:RelaxSoft(included, tokens, hard, softs, out, overBudget)
	local Pass = ns.Filters and ns.Filters.Pass
	local weights
	for _, p in ipairs(included) do
		local list = RowsOf(included, p)
		local id = p.id
		for i = 1, #list do
			local e = list[i]
			local sc = ScoreEntry(e, tokens)
			if sc and (not hard or Pass(e, hard)) then
				weights = weights or SoftWeights(softs)
				e._score = sc + SoftPassed(softs, weights, e) * SOFT_PASS + FreqBonus(e, id) + (rawget(e, "_rank") or 0)
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
	local exact = tokens.exact
	for i = 1, #tokens do
		limits[i] = not (exact and exact[tokens[i]]) and NearLimit(#tokens[i]) or nil -- (a "quoted phrase": as it is only)
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
					if not single then sc = TokenScore(tk, short and short[i], name, lname, RowText(e), exact and exact[tk]) end
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
		name = L["Search %s for this"]:format(p.hintLabel or p.label), kindLabel = "|cff33ff99Tab|r",
		detail = firstName .. (count > 1 and ("  " .. L["+%d more"]:format(count >= 100 and 99 or count - 1)) or ""),
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
