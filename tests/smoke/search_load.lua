-- Searching under load (0.59.0, the stress test: tests/stress.py): what a frame does stays bounded however many rows
-- match. Each look at the clock here is 1 ms (deterministic), so a search spreads over "frames" by how often it looks.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local E = ns.Easy

io.write("[search under load]\n")

-- a row's category, worked out from a map made once (not every category's every list walked for each match)
do
	local cats = rawget(E, "CATEGORIES")
	local looked = 0
	E.CATEGORIES = nil
	setmetatable(E, { __index = function(_, k) if k == "CATEGORIES" then looked = looked + 1; return cats end end })
	E.Adopt({ id = "loadtest", label = "Load test", simpleCategory = "npcs" }) -- (the map made again after this)
	local row = { kind = "loadtest", name = "x" }
	local cat
	for _ = 1, 500 do cat = E.CategoryOf(row) end
	local after = looked
	setmetatable(E, nil)
	E.CATEGORIES = cats
	local npcs = E.BY_ID.npcs.kinds
	for i = #npcs, 1, -1 do if npcs[i] == "loadtest" then table.remove(npcs, i) end end
	E.Reindex()
	check(cat == "npcs" and after <= 3, "a row's category: from a map made once (again after a list joins one), not every category walked each row: " .. after)
	check(E.CategoryOf(row) == nil, "...made again when told: the list gone from it")
end

-- the first frame's best-so-far: no more than a few ms of picking, whatever was matched
do
	local list = {}
	for i = 1, 5000 do list[i] = { _score = i, _lname = "r" .. i, key = i } end
	local looks = 0
	local top = UI.SortAndTrim(list, nil, nil, function() looks = looks + 1; return true end)
	check(#top == ns.Score.MAX_RESULTS and looks == 1 and top[1]._score < 5000,
		"told to stop: the best of what it looked at, at once (" .. looks .. " looks, best " .. tostring(top[1] and top[1]._score) .. ")")
	local all = UI.SortAndTrim(list)
	check(all[1]._score == 5000 and #all == ns.Score.MAX_RESULTS, "...not told: the best of all")
end

-- Simple mode's overview of thousands of matches: sorted into categories a slice a frame
do
	local rows = {}
	for i = 1, 6000 do rows[i] = { kind = "loadrows", name = "Kalimdor Row " .. i, _lname = "kalimdor row " .. i, key = i } end
	local rows2 = {}
	for i = 1, 50 do rows2[i] = { kind = "loadrows2", name = "Kalimdor Loot " .. i, _lname = "kalimdor loot " .. i, key = i } end
	ns:RegisterProvider("loadrows", { label = "Load rows", aliases = { "loadrows" }, simpleCategory = "npcs",
		collect = function() return rows end })
	ns:RegisterProvider("loadrows2", { label = "Load rows 2", aliases = { "loadrows2" }, simpleCategory = "loot",
		collect = function() return rows2 end })
	ns:GetEntries(ns.providers.loadrows)
	ns:GetEntries(ns.providers.loadrows2)
	local clockWas, ms = _G.debugprofilestop, 0
	_G.debugprofilestop = function() ms = ms + 1; return ms end
	local catOf = E.CategoryOf
	local inSlice, most = 0, 0
	E.CategoryOf = function(e) inSlice = inSlice + 1; return catOf(e) end
	local easy = ns.db.easyMode
	ns.db.easyMode = true
	UI:Hide()
	UI:Open("kalimdor")
	most = math.max(most, inSlice)
	local guard = 0
	while UI.searchJob and guard < 5000 do
		inSlice = 0
		UI:ContinueSearch(UI.searchJob)
		most = math.max(most, inSlice)
		guard = guard + 1
	end
	E.CategoryOf = catOf
	_G.debugprofilestop = clockWas
	ns.db.easyMode = easy
	local found
	for _, e in ipairs(UI.Results()) do if e.catId == "npcs" then found = e end end
	check(found and found.count and found.count >= 6000, "the overview counts them all: " .. tostring(found and found.count))
	check(most > 0 and most <= 3000, "...a slice of them a frame, not 6000 in one: " .. most)
	UI:Hide()
	ns.providers.loadrows, ns.providers.loadrows2 = nil, nil
	for i = #ns.providerOrder, 1, -1 do
		local id = ns.providerOrder[i]
		if id == "loadrows" or id == "loadrows2" then table.remove(ns.providerOrder, i) end
	end
	ns:AliasesChanged()
	for _, id in ipairs({ "npcs", "loot" }) do
		local kinds = E.BY_ID[id].kinds
		for i = #kinds, 1, -1 do if kinds[i] == "loadrows" or kinds[i] == "loadrows2" then table.remove(kinds, i) end end
	end
	E.Reindex()
end
