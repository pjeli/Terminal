-- The code-quality pass over Pipes.lua and Easy.lua (0.44.x): Simple mode's everyday words keep only themselves,
-- the chains' caches stay bounded, and a seed narrowed from the last keystroke finds what a full look finds.
local T = ...
local ns, check = T.ns, T.check
local E = ns.Easy

-- a function's upvalue by name (the caches are file locals)
local function Upvalue(fn, want)
	for i = 1, 200 do
		local n, v = debug.getupvalue(fn, i)
		if n == nil then return nil end
		if n == want then return v end
	end
end
local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

-- E.Word keeps a test only for an everyday word: every other word typed in Simple mode used to stay in its table
-- (as false) for the whole session
do
	local was, temp, tempSimple = ns.db.easyMode, E.temp, E.tempSimple
	ns.db.easyMode, E.temp, E.tempSimple = true, nil, nil
	local tests = Upvalue(E.Word, "wordTests")
	check(type(tests) == "table", "E.Word's tests are found (wordTests)")
	local before = Count(tests)
	local none = true
	for i = 1, 50 do
		if E.Word("zzqqword" .. i) ~= nil then none = false end
	end
	check(none, "a word that isn't an everyday word has no test")
	check(Count(tests) == before, "nor is anything kept for it: " .. before .. " -> " .. Count(tests))
	local mid = Count(tests)
	local rare = E.Word("rare")
	check(type(rare) == "function" and E.Word("Rare") == rare and Count(tests) <= mid + 1,
		"an everyday word's test is made once and kept")
	check(E.Word("upgrades") ~= E.Word("upgrades"), "a strict word's filter is still made new each time")
	ns.db.easyMode, E.temp, E.tempSimple = was, temp, tempSimple
end

-- a small world for the chains: recipes, bags, AtlasLoot rows (with `filler` made-up ones), alts
local P = ns.Pipes
local NAMES = { [12359] = "Thorium Bar", [7077] = "Heart of Fire", [12406] = "Thorium Belt", [9999] = "Thorium Belt of Doom",
	[3575] = "Iron Bar", [2770] = "Copper Ore", [9998] = "Comfortable Leather Hat", [9997] = "Agamaggan's Clutch",
	[2589] = "Linen Cloth", [2996] = "Bolt of Linen Cloth", [12407] = "Thorium Bracers" }
local function World(filler)
	local saved = { providers = ns.providers, order = ns.providerOrder, name = C_Item.GetItemNameByID }
	C_Item.GetItemNameByID = function(id) return NAMES[id] end
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
	local loot = { { name = "Thorium Belt", itemID = 12406, detail = "Boss  Instance" },
		{ name = "Belt of the Fang", itemID = 1001, detail = "Lord Cobrahn  Wailing Caverns" },
		{ name = "Fang of the Crystal Spider", itemID = 1002, detail = "?  Wailing Caverns" },
		{ name = "A help line", noActivate = true } }
	local syll = { "ka", "ro", "mi", "ten", "dar", "vel", "ish", "gor", "lan", "the", "bru", "sa", "nok", "fi", "zul", "an", "bel", "tor", "hi", "um" }
	local s = 7
	for i = 1, filler or 0 do
		local parts = {}
		for w = 1, 2 do
			local name = ""
			for _ = 1, 2 + (i + w) % 2 do s = (s * 1103515245 + 12345) % 2147483648; name = name .. syll[math.floor(s / 65536) % #syll + 1] end
			parts[w] = name:sub(1, 1):upper() .. name:sub(2)
		end
		loot[#loot + 1] = { name = table.concat(parts, " "), itemID = 50000 + i, detail = "Boss  Instance" }
	end
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("recipes", { label = "Recipe", aliases = { "recipe" }, collect = Rows({
		{ name = "Thorium Belt", recipeID = 16645, makesItem = 12406, reagents = { { 12359, 12 }, { 7077, 2 } } },
		{ name = "Thorium Belt of Doom", recipeID = 99, makesItem = 9999, reagents = { { 3575, 1 } } },
		{ name = "Thorium Bracers", recipeID = 94, makesItem = 12407, reagents = { { 12359, 8 } } },
		{ name = "Comfortable Leather Hat", recipeID = 98, makesItem = 9998, reagents = { { 2770, 12 } } },
		{ name = "Agamaggan's Clutch", recipeID = 97, makesItem = 9997, reagents = { { 2770, 3 } } },
		{ name = "Bolt of Linen Cloth", recipeID = 96, makesItem = 2996, reagents = { { 2589, 2 } } } }) })
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = Rows({
		{ name = "Thorium Bar", itemID = 12359 }, { name = "Linen Cloth", itemID = 2589 }, { name = "Copper Ore", itemID = 2770 } }) })
	ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = Rows(loot) })
	ns:RegisterProvider("stored", { label = "Stored", aliases = { "stored" }, collect = Rows({
		{ name = "Thorium Bar", key = 12359, itemID = 12359, total = 46, detail = "Alt 30" } }) })
	P.ClearCrafts(); P.ClearSteps()
	-- (the restore, and the AtlasLoot rows the list is made from: a test may add one and mark the list dirty)
	return function()
		ns.providers, ns.providerOrder = saved.providers, saved.order
		ns:AliasesChanged()
		C_Item.GetItemNameByID = saved.name
		T.UI.lastScan, T.UI.lastOverview = nil, nil
		P.ClearCrafts(); P.ClearSteps()
	end, loot
end
local function Names(rows)
	local t = {}
	for i, e in ipairs(rows or {}) do t[i] = tostring(e.name) .. "/" .. tostring(e.detail) end
	return table.concat(t, ", ")
end

-- the chains' step cache stays bounded: every chain prefix typed (a key a letter) stayed in it until a list was rebuilt
do
	local Restore = World()
	local want = Names(P.Search("thorium belt > mats"))
	local seeds, realSeed = 0, P.Seed
	P.Seed = function(...) seeds = seeds + 1 return realSeed(...) end
	P.Search("thorium belt > mats")
	check(seeds == 0, "a chain typed again reuses its kept steps")
	for i = 1, 150 do P.Search(("zzqq%03d > mats"):format(i)) end
	P.Seed = realSeed
	local cache = Upvalue(P.ClearSteps, "stepCache")
	local max = P.STEPS_MAX or 64
	check(type(cache) == "table" and Count(cache) <= max, "150 chains typed: at most " .. max .. " steps kept: " .. Count(cache))
	check(Names(P.Search("thorium belt > mats")) == want and want:find("Thorium Bar", 1, true),
		"the same rows once the cache has started over: " .. want)
	-- (0.44.16) the terminal closed: a chain's kept steps and names go (they held rows of lists freed meanwhile)
	P.Seed("thorium")
	check(Count(Upvalue(P.ClearSteps, "stepCache")) > 0 and Upvalue(P.Seed, "lastSeed") ~= nil, "(steps and names kept while open)")
	local tf = _G.TerminalFrame
	tf.scripts.OnHide(tf)
	T.FlushAll()
	check(Count(Upvalue(P.ClearSteps, "stepCache")) == 0 and Upvalue(P.Seed, "lastSeed") == nil, "closed: nothing of a chain kept")
	Restore()
end

-- a chain's start typed on narrows from the last keystroke's look (the names that had the words): the same rows,
-- closest name and names to pick from as a look over every row, for far fewer names scored
do
	local Restore, loot = World(400)
	local function Seed(text)
		local rows, near, choices = P.Seed(text)
		local t = {}
		for i, e in ipairs(rows) do t[i] = tostring(e.kind) .. ":" .. tostring(rawget(e, "key")) end
		local c = {}
		for i, e in ipairs(choices or {}) do c[i] = tostring(e.kind) .. ":" .. tostring(rawget(e, "key")) end
		return ("rows=%s near=%s choices=%s/%s"):format(table.concat(t, ","), near and tostring(near.name) or "-",
			table.concat(c, ","), tostring(choices and choices.total))
	end
	local texts = {}
	local function Typed(name, back)
		for i = 1, #name do texts[#texts + 1] = name:sub(1, i) end
		if back then for i = #name - 1, 1, -1 do texts[#texts + 1] = name:sub(1, i) end end
	end
	Typed("thorium belt", true) -- (several names, then one)
	Typed("agamaggans clutch") -- (an apostrophe left out)
	Typed("core leather belt") -- (no name has every word: the closest)
	Typed("belt of the fang", true) -- (one more word at a time)
	Typed("kar")
	texts[#texts + 1] = "thorium b"
	texts[#texts + 1] = "thorium b -doom" -- (a filter added: the same words, the rows looked at again)
	texts[#texts + 1] = "thorium be -doom"
	local scored, real = 0, ns.Fuzzy.score
	ns.Fuzzy.score = function(...) scored = scored + 1 return real(...) end
	-- typed on, as the search does it
	P.ClearSteps()
	local typed = {}
	for i, t in ipairs(texts) do typed[i] = Seed(t) end
	local typedScored = scored
	-- each one looked for over every row
	scored = 0
	local same, first = true, nil
	for i, t in ipairs(texts) do
		P.ClearSteps()
		local full = Seed(t)
		if full ~= typed[i] then
			same = false
			first = first or (t .. ": " .. typed[i] .. " / " .. full)
		end
	end
	local fullScored = scored
	check(same, "typed on: the same seed as a look over every row (" .. #texts .. " texts)" .. (first and (": " .. first) or ""))
	check(typedScored * 2 < fullScored, "typing on scores fewer names: " .. typedScored .. " vs " .. fullScored)
	-- a list rebuilt between keystrokes: its new rows are found
	P.ClearSteps()
	Seed("thorium belt ")
	loot[#loot + 1] = { name = "Thorium Belt of Fire", itemID = 12408, detail = "Ragnaros  Molten Core" }
	ns.providers.loot._dirty = true
	local after = Seed("thorium belt o")
	P.ClearSteps()
	check(after:find("loot:", 1, true) and after == Seed("thorium belt o"), "a rebuilt list's new row is among the names to pick: " .. after)
	loot[#loot] = nil
	ns.providers.loot._dirty = true
	local gone = Seed("thorium belt of")
	check(gone == Seed("thorium belt of") and not gone:find("loot:", 1, true), "and not once it's taken out again: " .. gone)
	ns.Fuzzy.score = real
	Restore()
end
