-- The search engine's parts (Search/Score.lua, Search/Search.lua's steps) and its speed-ups: the same rows in the same
-- order as the plain way of working them out, with less work (counted).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll

-- every list swapped for these test ones while a block runs, put back after (the other files see them as they were)
local saved = { providers = ns.providers, order = ns.providerOrder }
local function Use(defs)
	ns.providers, ns.providerOrder = {}, {}
	for _, d in ipairs(defs) do ns:RegisterProvider(d[1], d[2]) end
	UI.lastScan, UI.lastOverview, UI.lastFzf = nil, nil, nil
end
local function Restore()
	ns.providers, ns.providerOrder = saved.providers, saved.order
	ns:AliasesChanged()
	UI.lastScan, UI.lastOverview, UI.lastFzf = nil, nil, nil
end
local function Rows(list)
	return function()
		local out = {}
		for i, r in ipairs(list) do
			local e = {}
			for k, v in pairs(r) do e[k] = v end
			e.key = e.key or i
			out[i] = e
		end
		return out
	end
end
-- a list of compact rows (as Questie's, AtlasLoot's): reads of the named fields through the metatable are counted
-- in counts[field]
local function CompactList(names, counts, extra)
	return function(p)
		local meta = ns:CompactMeta(p, extra and extra.proto, extra and extra.lazy)
		local index = meta.__index
		meta.__index = function(t, k)
			if counts[k] then counts[k] = counts[k] + 1 end
			return index(t, k)
		end
		local out = {}
		for i, n in ipairs(names) do out[i] = setmetatable({ _compact = true, key = i, name = n }, meta) end
		return out
	end
end
-- "Name|detail" of each row, in order
local function Sig(res)
	local t = {}
	for i, e in ipairs(res) do t[i] = tostring(e.name) .. "|" .. tostring(e.detail) end
	return table.concat(t, " ; ")
end
-- each block: an error is a failure, and the lists are put back whatever happens
local function Run(title, fn)
	io.write("[search parts: " .. title .. "]\n")
	local ok, err = pcall(fn)
	Restore()
	ns.db.easyMode = false
	UI:Hide(); FlushAll()
	if not ok then check(false, title .. ": " .. tostring(err)) end
end

Run("Score.lua: the scoring and sorting the window and Search.lua use", function()
	local S = ns.Score
	check(type(S) == "table", "ns.Score is there")
	for _, f in ipairs({ "FreqBonus", "ScoreEntry", "TokenScore", "RowText", "NearLimit", "NearWord", "Positions", "Better", "SortAndTrim" }) do
		check(type(S[f]) == "function", "ns.Score." .. f)
	end
	check(UI.NO_POS == S.NO_POS and UI.Positions == S.Positions and UI.SortAndTrim == S.SortAndTrim
		and UI._Better == S.Better and UI._FreqBonus == S.FreqBonus, "the window's copies are Score.lua's")
	check(S.MAX_RESULTS == 100 and S.TEXT_SCORE == 1.0, "the constants moved as they were")
	check(type(UI.HintActivate) == "function" and UI.HINT_FEW == 2 and type(UI.HINT_SAME) == "table", "Search.lua's exports stay")
end)

Run("a quest item brings its quest; compact rows aren't read for one", function()
	local counts = { questID = 0, guessIDs = 0 }
	local names = {}
	for i = 1, 300 do names[i] = "Wolfpelt " .. i end
	Use({
		{ "quests", { label = "Quest", aliases = { "questlog" }, collect = Rows({ { name = "Wolves Across the Border", questID = 33 } }) } },
		{ "items", { label = "Item", aliases = { "item" }, collect = Rows({ { name = "Wolf Tail", questID = 33 }, { name = "Wolf Fang", guessIDs = { 33 } } }) } },
		{ "big", { label = "Big", aliases = { "big" }, collect = CompactList(names, counts) } },
	})
	local res = UI:Search("wolf")
	local tail, quest
	for i, e in ipairs(res) do
		if e.name == "Wolf Tail" then tail = i elseif e.name == "Wolves Across the Border" then quest = i end
	end
	check(tail and quest and quest == tail + 1 and UI.linked[res[quest]] == res[tail], "the quest comes right under its item: " .. Sig(res))
	check(#res == 100, "the big list's rows are among them: " .. #res)
	check(counts.questID == 0 and counts.guessIDs == 0,
		("the big list's rows weren't read for a quest (questID %d, guessIDs %d reads)"):format(counts.questID, counts.guessIDs))
end)

Run("quests brought along: the best item links, sure ones before guesses, the first guess wins", function()
	Use({
		{ "quests", { label = "Quest", aliases = { "questlog" }, collect = Rows({
			{ name = "Ra Quest A", questID = 1 }, { name = "Bounty B", questID = 2 }, { name = "Cleanup C", questID = 3 } }) } },
		{ "items", { label = "Item", aliases = { "item" }, collect = Rows({
			{ name = "Ragged Cloth", guessIDs = { 3, 2 } }, -- (a guess listed before the sure ones: they still win)
			{ name = "Brass Ring", questID = 2 }, { name = "Rat Tail", questID = 2 }, { name = "Raw Meat", guessIDs = { 3 } },
			{ name = "Rat Bait", questID = 1 } }) } },
	})
	local res = UI:Search("ra")
	local at = {}
	for i, e in ipairs(res) do at[e.name] = i end
	local A, B, C = res[at["Ra Quest A"]], res[at["Bounty B"]], res[at["Cleanup C"]]
	local function Score(n) return res[at[n]] and res[at[n]]._score end
	check(A and B and C, "the three quests are listed: " .. Sig(res))
	check(Score("Rat Tail") > Score("Brass Ring"), "(Rat Tail matches better than Brass Ring)")
	check(UI.linked[B] == res[at["Rat Tail"]] and not UI.linkedGuess[B] and B._score == Score("Rat Tail") - 0.001,
		"B: brought by the best of its sure items (Rat Tail, not Brass Ring), just under it: " .. Sig(res))
	check(UI.linked[C] == res[at["Ragged Cloth"]] and UI.linkedGuess[C] == true and C._score == Score("Ragged Cloth") - 0.001,
		"C: guessed by the first item that guesses it, not by Raw Meat")
	check(UI.linked[A] == res[at["Rat Bait"]] and A._score == Score("Rat Bait") - 0.001,
		"A (found by its own name) moves under the item named like the words: " .. Sig(res))
	check(at["Bounty B"] > at["Rat Tail"] and at["Cleanup C"] > at["Ragged Cloth"] and at["Ra Quest A"] > at["Rat Bait"], "each under its item")
end)

-- the empty terminal's recent picks, worked out as they always were (every row's freqKey made and looked up): the
-- rows picked and their scores, sorted as the window sorts them
local function OldFrequent()
	local picked = {}
	local rank = {}
	for i, key in ipairs(ns.db.recent or {}) do rank[key] = i end
	local want = {}
	for key in pairs(rank) do want[key:match("^([^:]+):") or ""] = true end
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		if (not p.explicit and not p.lazy) or want[id] then
			for _, e in ipairs(ns:GetEntries(p)) do
				local r = rank[e.freqKey]
				local f = ns.db.freq[e.freqKey]
				if r then picked[#picked + 1] = { e, 10000 - r }
				elseif f and f > 0 and not p.explicit and not p.lazy then picked[#picked + 1] = { e, f } end
			end
		end
	end
	local rows = {}
	for i, x in ipairs(picked) do x[1]._score = x[2]; rows[i] = x[1] end
	local sorted = UI.SortAndTrim(rows)
	local scores = {}
	for i, e in ipairs(sorted) do scores[i] = e._score end
	return sorted, scores
end

-- compact rows from { name, key } pairs (a key false or left out: the name stands for it, as CompactMeta makes the
-- freqKey); metaOf: the list whose metatable they take (its kind, as earned achievements share the full list's rows)
local function CompactRows(specs, counts, metaOf)
	local made
	return function(p)
		if made then return made end
		local meta = ns:CompactMeta(metaOf and ns.providers[metaOf] or p)
		local index = meta.__index
		meta.__index = function(t, k)
			if counts and counts[k] then counts[k] = counts[k] + 1 end
			return index(t, k)
		end
		made = {}
		for i, s in ipairs(specs) do made[i] = setmetatable({ _compact = true, name = s[1], key = s[2] }, meta) end
		return made
	end
end

Run("recent picks: the same rows and scores; a big list's rows aren't each made a freqKey", function()
	local counts = { freqKey = 0 }
	local npcs = {}
	for i = 1, 400 do npcs[i] = { "Npc " .. i, i } end
	local odd = 0.1 + 0.2 -- (its freqKey says "npc:0.3", though it isn't 0.3)
	for _, s in ipairs({ { "Npc Zero", 0 }, { "Npc Half", 1.5 }, { "Npc Big", 1e15 }, { "Npc Odd", odd }, { "Name Fallback", false }, { "No Key" } }) do
		npcs[#npcs + 1] = s
	end
	local toys = {}
	for i = 1, 20 do toys[i] = { "Toy " .. i, i } end
	local achs = {}
	for i = 1, 12 do achs[i] = { "Deed " .. i, i } end
	local allAchs = CompactRows(achs, nil, "aearned")
	Use({
		{ "items", { label = "Item", aliases = { "item" }, collect = Rows({ { name = "Linen Cloth", key = 2589 }, { name = "Copper Bar", key = 2840 }, { name = "Rough Stone", key = 2835 } }) } },
		{ "toys", { label = "Toy", aliases = { "toy" }, collect = CompactRows(toys) } },
		{ "loot", { label = "Loot", aliases = { "loot" }, lazy = true, collect = CompactRows({ { "Fang", "AL:RFK:1234" }, { "Claw", "AL:RFK:1235" }, { "Hide", "AL:WC:1" } }) } },
		{ "npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = CompactRows(npcs, counts) } },
		{ "maps", { label = "Map", aliases = { "map" }, lazy = true, collect = function() error("a list no recent pick names is read") end } },
		{ "alist", { label = "Deeds", aliases = { "deeds" }, explicit = true, lazy = true, collect = allAchs } },
		{ "aearned", { label = "Deeds", lazy = true, collect = function()
			local out = {}
			for i, e in ipairs(ns:GetEntries(ns.providers.alist)) do if i % 2 == 1 then out[#out + 1] = e end end
			return out
		end } },
	})
	local savedRecent, savedFreq = ns.db.recent, ns.db.freq
	ns.db.recent = { "npc:0", "npc:1.5", "npc:1e+15", "npc:0.3", "npc:Name Fallback", "npc:No Key", "npc:42",
		"loot:AL:RFK:1234", "items:2840", "toys:3", "aearned:7", "npc:Npc 9" }
	ns.db.freq = { ["items:2589"] = 5, ["toys:9"] = 2, ["npc:77"] = 3, ["toys:3"] = 1, ["loot:AL:WC:1"] = 4 }
	ns.freqKinds = nil
	local ok, err = pcall(function()
		local oldRows, oldScores = OldFrequent()
		counts.freqKey = 0
		local newRows = UI:FrequentEntries()
		local same = #oldRows == #newRows
		for i = 1, math.max(#oldRows, #newRows) do
			if oldRows[i] ~= newRows[i] or oldScores[i] ~= (newRows[i] and newRows[i]._score) then same = false end
		end
		check(same, "the same rows, order and scores as with every freqKey made: " .. Sig(newRows) .. "  //  " .. Sig(oldRows))
		check(#newRows == 13, "every kind of key found (0, 1.5, 1e15, a float shown as 0.3, by name, keys with colons): " .. #newRows)
		check(counts.freqKey <= 12, "the NPC list's 406 rows weren't each made a freqKey (" .. counts.freqKey .. " made)")
	end)
	ns.db.recent, ns.db.freq, ns.freqKinds = savedRecent, savedFreq, nil
	if not ok then error(err, 0) end
end)

-- A made-up world for "nearest": NPC spawns as QuestieDB gives them (area 12 = map 1429 on continent 1, area 40 =
-- map 1436 on continent 2), map % -> yards (* 1000), you at 30%, 80% of map 1429. Returns the function that puts the
-- game back (and forgets the distances worked out here).
local function World(spawns)
	local I, QD = ns.Integrations, ns.QuestieData
	local save = { db = QD.DB, ui = QD.UiMapOfArea, map = _G.C_Map }
	local DB = { QueryNPCSingle = function(id, field) if field == "spawns" then return spawns[id] end end }
	QD.DB = function() return DB end
	QD.UiMapOfArea = function(area) return area == 12 and 1429 or 1436 end
	_G.C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return { x = 0.30, y = 0.80 } end,
		GetWorldPosFromMapPos = function(map, p) return map == 1429 and 1 or 2, { x = p.x * 1000, y = p.y * 1000 } end }
	I._.ResetDistances()
	return function() QD.DB, QD.UiMapOfArea, _G.C_Map = save.db, save.ui, save.map; I._.ResetDistances() end
end
local function Upvalue(fn, name)
	for i = 1, 200 do
		local n, v = debug.getupvalue(fn, i)
		if not n then return nil end
		if n == name then return v end
	end
end
-- 600 NPCs (names repeat: equal distances are told apart by name, then key; every fifth stands on the other continent,
-- some share a spot) and three mailbox-like rows with spots of their own
local function NearLists()
	local spawns, npcs = {}, {}
	for i = 1, 600 do
		npcs[i] = { ("Npc %02d"):format(i % 40), i }
		local spot = i % 7 == 0 and { 31, 79 } or { (i * 37) % 100, (i * 53) % 100 }
		spawns[i] = { [i % 5 == 0 and 40 or 12] = { spot } }
	end
	Use({
		{ "npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = CompactRows(npcs) } },
		{ "spots", { label = "Spot", aliases = { "spots" }, explicit = true, collect = Rows({
			{ name = "Mailbox", wcont = 1, wx = 310, wy = 790, zone = "Elwynn" }, { name = "Mailbox", wcont = 2, wx = 0, wy = 0, zone = "Far" },
			{ name = "Mailbox", wcont = 1, wx = 300, wy = 800, zone = "Elwynn" } }) } },
	})
	return spawns
end
-- what the nearest search listed before only the closest got views: a view for every row with a distance, the best 100
local function OldNearest(here)
	local I, all = ns.Integrations, {}
	for _, id in ipairs({ "npc", "spots" }) do
		for _, e in ipairs(ns:GetEntries(ns.providers[id])) do
			local d = I.RowDistance(e, here)
			if d then
				local zone = rawget(e, "wcont") and e.zone
				all[#all + 1] = { name = e.name, _lname = e._lname, key = e.key, _score = 1e6 - d,
					detail = ("%.0f yd"):format(d) .. (zone and ("  " .. zone) or ""), _dist = d }
			else
				all[#all + 1] = { name = e.name, _lname = e._lname, key = e.key, _score = e._score, detail = e.detail }
			end
		end
	end
	return UI.SortAndTrim(all)
end
local function SameNear(res, want)
	if #res ~= #want then return false end
	for i = 1, #want do
		local a, b = res[i], want[i]
		if not (a.name == b.name and a.key == b.key and a.detail == b.detail and a._dist == b._dist) then return false end
	end
	return true
end

Run("nearest: views only for the closest; the same rows, order and distances as a view for each", function()
	local restore = World(NearLists())
	local ok, err = pcall(function()
		local I = ns.Integrations
		local here = I.Here()
		-- the distance alone is RowDistance's, for every row
		local same, n = true, 0
		for _, id in ipairs({ "npc", "spots" }) do
			for _, e in ipairs(ns:GetEntries(ns.providers[id])) do
				local d = I.RowYards(e, here)
				if d ~= (I.RowDistance(e, here)) then same = false end
				if d then n = n + 1 end
			end
		end
		check(same and n == 482, "RowYards gives RowDistance's yards for every row (" .. n .. " with a distance)")
		-- the search: views made only for the closest 100
		local made, realSet = 0, _G.setmetatable
		_G.setmetatable = function(t, m) if type(t) == "table" and rawget(t, "_dist") then made = made + 1 end return realSet(t, m) end
		local res = UI:Search("@npc @spots sort:nearest")
		_G.setmetatable = realSet
		local want = OldNearest(here)
		check(#res == 100 and SameNear(res, want), "the same 100 rows, order, details and distances: " .. Sig(res) .. "  //  " .. Sig(want))
		check(made <= 100, "views made only for the closest (" .. made .. " for 482 rows with a distance)")
		check(res[1]._dist and res[1].detail:find(" yd", 1, true) and res[100]._dist, "every listed row is a view (more than 100 have a distance)")
		-- a test's own distances (I.NpcDistance put in its place) are still asked
		local saveNpc = I.NpcDistance
		I.NpcDistance = function(id) return id == 3 and 1 or nil end
		local fake = UI:Search("@npc sort:nearest")
		I.NpcDistance = saveNpc
		check(fake[1] and fake[1].key == 3 and fake[1].detail == "1 yd" and fake[2] and not fake[2]._dist, "a replaced NpcDistance is asked: " .. Sig(fake))
		-- spread over frames: what a pause shows holds the closest so far as views, made once and kept for the end
		local Scan = Upvalue(UI.SearchText, "Scan")
		local out = {}
		for _, id in ipairs({ "npc", "spots" }) do for _, e in ipairs(ns:GetEntries(ns.providers[id])) do out[#out + 1] = e end end
		local whole = Scan.NearestViews(out, here, true, function() return false end)
		local co = coroutine.create(function() return Scan.NearestViews(out, here, true, function() return true end) end)
		local pauses, shown, okShown = 0, {}, true
		while true do
			local done, got = coroutine.resume(co)
			check(done, "the views go on after a pause: " .. tostring(got))
			if coroutine.status(co) == "dead" then
				local kept = got
				check(#kept == #whole and SameNear(kept, whole), "paused or not, the same list")
				local reused = 0
				for _, v in ipairs(kept) do if shown[v] then reused = reused + 1 end end
				check(reused > 0, "the views a pause showed are the ones listed in the end: " .. reused)
				break
			end
			pauses = pauses + 1
			local views = 0
			for _, v in ipairs(got) do if rawget(v, "_dist") then views = views + 1; shown[v] = true end end
			if views == 0 or views > 100 then okShown = false end
		end
		check(pauses > 10 and okShown, "each pause showed the closest so far, 100 at most (" .. pauses .. " pauses)")
	end)
	restore()
	if not ok then error(err, 0) end
end)

-- "name|key|detail|score" of each row, in order
local function Full(res)
	local t = {}
	for i, e in ipairs(res) do t[i] = ("%s|%s|%s|%.9f"):format(tostring(e.name), tostring(e.key), tostring(e.detail), e._score or -1) end
	return table.concat(t, " ; ")
end

Run("Simple mode: the only category with matches opens without its rows scored again; the same results", function()
	ns.db.easyMode = true
	local syll = { "ka", "ro", "mi", "ten", "dar", "vel", "ish", "gor", "lan", "bru", "sa", "nok", "fi", "zul" }
	local seed, loot = 11, {}
	for i = 1, 1500 do
		local name = ""
		for _ = 1, 3 do seed = (seed * 1103515245 + 12345) % 2147483648; name = name .. syll[math.floor(seed / 65536) % #syll + 1] end
		loot[i] = { name:sub(1, 1):upper() .. name:sub(2) .. (i % 3 == 0 and " Blade" or " Charm"), "AL:" .. i }
	end
	local questie = { { "Wolf Hunt", 1 }, { "Wolves at Dawn", 2 }, { "A Wolf's Den", 3 }, { "Bear Necessities", 4 } }
	Use({
		{ "items", { label = "Item", aliases = { "item" }, collect = Rows({ { name = "Linen Cloth" }, { name = "Hearthstone" } }) } },
		{ "quests", { label = "Quest", aliases = { "questlog" }, collect = Rows({ { name = "Wolves Across the Border", questID = 33 } }) } },
		{ "loot", { label = "Loot", aliases = { "loot" }, lazy = true, collect = CompactRows(loot) } },
		{ "questie", { label = "Questie", aliases = { "questie" }, hintLabel = "Questie's quests", explicit = true, collect = CompactRows(questie),
			hintFind = function(_, tokens)
				local first, n = nil, 0
				for _, q in ipairs(questie) do
					local ln, all = q[1]:lower(), true
					for _, tk in ipairs(tokens) do if not ln:find(tk, 1, true) then all = false end end
					if all then n = n + 1; first = first or q[1] end
				end
				return first, n
			end } },
		{ "slash", { label = "Slash", aliases = { "slash" }, explicit = true, collect = Rows({
			{ name = "/yawn", emote = "YAWN", text = "emote yawn" }, { name = "/dance", emote = "DANCE" }, { name = "/reload" } }) } },
	})
	local calls, base = 0, ns.Fuzzy.score
	ns.Fuzzy.score = function(...) calls = calls + 1 return base(...) end
	local ok, err = pcall(function()
		local autos, fewer, narrowed = 0, 0, 0
		-- "kar..." only loot has; "wolv" your quest log and Questie's quests (a list only looked up by name in the
		-- overview); "yaw" an emote (a category with its own test)
		local opened = {}
		for _, phrase in ipairs({ "karo", "kar ro", "wolv", "yaw" }) do
			UI:Open("")
			for k = 1, #phrase do
				local part = phrase:sub(1, k)
				local ov = UI.lastOverview
				local before = 0
				for _, rows in pairs(ov and ov.rows or {}) do before = before + #rows end
				calls = 0
				UI:SetQuery(part, #part)
				local got, n = Full(UI.Results()), calls
				if UI.categoryAuto then
					autos = autos + 1
					opened[UI.category] = true
					-- the same category picked by hand: no overview, its lists searched the usual way
					local scanWas, ovWas, catWas = UI.lastScan, UI.lastOverview, UI.category
					UI.lastScan, UI.lastOverview, UI.categoryAuto = nil, nil, nil
					calls = 0
					local want = Full(UI:Search(part))
					check(got == want, ("'%s' (%s opened for you): the same rows, order and scores as picked by hand (%s  //  %s)"):format(part, catWas, got, want))
					if catWas == "loot" and n < calls then fewer = fewer + 1 end -- (picked by hand: all 1500 loot rows scored)
					-- narrowing: only what the last overview kept is scored, once (it was twice); the rows drawn work out
					-- their matched letters with the same scorer (a few more)
					if ov and k > 1 and ov.tokens and #ov.tokens > 0 and catWas == "loot" then
						narrowed = narrowed + 1
						check(n <= (before + 20) * #UI.posTokens, ("'%s': %d words scored for %d rows kept by the last keystroke"):format(part, n, before))
					end
					UI.lastScan, UI.lastOverview, UI.category, UI.categoryAuto = scanWas, ovWas, catWas, true
				end
			end
			UI:Hide(); FlushAll()
		end
		check(autos >= 6 and fewer >= 2 and narrowed >= 2, ("categories opened for you %d times, loot scored less than picked by hand %d, narrowed %d"):format(autos, fewer, narrowed))
		check(opened.loot and opened.quests and opened.emotes, "opened: loot, quests (with Questie's, scored the usual way), emotes (its own test)")
	end)
	ns.Fuzzy.score = base
	if not ok then error(err, 0) end
end)
