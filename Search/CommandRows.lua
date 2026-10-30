local ns = select(2, ...)
local L = ns.L

-- The rows a search lists that aren't a list's own: the .commands and the arguments one takes as you type them, and the
-- empty terminal's recent picks (split from Search.lua as they were, 0.69.8). Search.lua is the search engine.

local UI = ns.UI
local Scan = UI._Scan
local SLICE_CHECK = UI.SLICE_CHECK -- rows scored between looks at the clock
local PseudoEntries = Scan.PseudoEntries
-- scoring and sorting (Score.lua), as locals: they run for every row
local Score = ns.Score
local NO_POS = Score.NO_POS
local FreqBonus, ScoreEntry = Score.FreqBonus, Score.ScoreEntry
local SortAndTrim = Score.SortAndTrim

local function RunCmd(e, args) return e.cmd.run(args or "", ns) end
local cmdList, cmdGen, cmdKey -- the command rows, made again only when a command is registered (Core's commandsGen)

function UI:CommandEntries()
	-- (made again when the terminal's key changes too: their details say it; 0.65.1)
	local keyNow = ns.ToggleLabel()
	if cmdList and cmdGen == ns.commandsGen and cmdKey == keyNow then return cmdList end
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
			detail = ns.KeyHint(c.desc),
			text = table.concat(c.aliases, " "),
			freqKey = "cmd:" .. name,
			cmd = c,
			activate = RunCmd,
		}
	end
	cmdList, cmdGen, cmdKey = list, ns.commandsGen, keyNow
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
