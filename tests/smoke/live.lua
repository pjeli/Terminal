-- (0.51.12, the player's ask) a list that changes while its rows are shown (bags while you loot, the loot log) is
-- searched again in the background, and what it finds waits for F5, as data coming in does: nothing shifts under the
-- cursor; a list shown empty takes the new rows at once.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll

io.write("[live: a list changing while it's shown waits for F5]\n")
do
	local save = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	local rows = {}
	for i = 1, 30 do rows[i] = { name = ("Linen Cloth %02d"):format(i), itemID = 50000 + i, key = i } end
	local function Collect()
		local out = {}
		for i, r in ipairs(rows) do out[i] = r end
		return out
	end
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = Collect })
	ns:RegisterProvider("spells", { label = "Spell", aliases = { "spell" }, collect = function() return { { name = "Fireball", key = 1 } } end })
	ns.db.easyMode = false
	UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	UI:Open("linen")
	FlushAll()
	UI.sel, UI.offset = 12, 8
	local shown, picked = UI.results, UI.results[12]
	-- you loot one more: the bags change while the list is up
	table.insert(rows, 1, { name = "Linen Cloth 00", itemID = 50000, key = 0 })
	ns:Changed("items")
	FlushAll()
	check(UI.results == shown and UI.results[UI.sel] == picked and UI.held ~= nil,
		"the bags changed while shown: the list stays, the change held (" .. tostring(UI.held ~= nil) .. ")")
	check(tostring(UI.status:GetText()):find("F5", 1, true), "...the footer says F5 shows it: " .. tostring(UI.status:GetText()))
	T.key("F5")
	local has00
	for _, e in ipairs(UI.results) do if e.name == "Linen Cloth 00" then has00 = true end end
	check(has00 and #UI.results == 31 and UI.results[UI.sel] == picked and UI.sel - UI.offset == 4,
		"F5: the new list, the same row selected where it was (" .. #UI.results .. ")")
	-- a list not shown: no search for it
	local searches, real = 0, UI.Search
	UI.Search = function(self, ...) searches = searches + 1 return real(self, ...) end
	ns:Changed("spells")
	FlushAll()
	check(searches == 0, "a list whose rows aren't shown changed: nothing searched again (" .. searches .. ")")
	-- a list that changes each time it's read (its own events): searched again a few times at most
	local p = ns.providers.items
	local reads = 0
	p.collect = function() reads = reads + 1; ns:Changed("items") return Collect() end
	ns:Changed("items")
	for _ = 1, 40 do T.Flush() end
	UI.Search = real
	check(searches <= UI.LIVE_SAME + 1, "a list changing as it's read: searched again " .. UI.LIVE_SAME .. " times at most, not forever ("
		.. searches .. ")")
	p.collect = Collect
	UI:Hide(); FlushAll()
	-- shown empty: the new rows come at once
	UI:Open("wool")
	FlushAll()
	check(#UI.results == 0 or UI.results[1].noActivate, "(nothing has wool yet)")
	rows[#rows + 1] = { name = "Wool Cloth", itemID = 50100, key = 100 }
	ns:Changed("items")
	FlushAll()
	check(UI.results[1] and UI.results[1].name == "Wool Cloth" and not UI.held, "nothing was shown: the new row at once")
	UI:Hide(); FlushAll()

	-- (0.52.9, the player: after a /reload, F5 came and went while item data came in) F5 only for a list found twice in a
	-- row: one that changes again isn't offered; one found again is; an offered one is taken back only when sure
	UI:Open("linen")
	FlushAll()
	local base = {}
	for i, r in ipairs(rows) do base[i] = r end
	local seen = {}
	local tries = UI.CONFIRM_TRIES
	UI.CONFIRM_TRIES = 0 -- (the checks done by hand here, one search at a time)
	local function Redo() ns.providers.items._dirty = true; UI:QuietRedo(); FlushAll(); seen[#seen + 1] = UI.held ~= nil end
	table.insert(rows, 1, { name = "Linen Cloth B", itemID = 50600, key = 700 })
	Redo()
	rows[1] = { name = "Linen Cloth C", itemID = 50601, key = 701 }
	Redo()
	for i = #rows, 1, -1 do rows[i] = nil end
	for i, r in ipairs(base) do rows[i] = r end
	Redo()
	check(not seen[1] and not seen[2] and not seen[3] and UI.held == nil,
		"lists that keep changing (B, C, then the shown one again): F5 never offered")
	table.insert(rows, 1, { name = "Linen Cloth D", itemID = 50602, key = 702 })
	Redo()
	local once = UI.held ~= nil
	Redo()
	check(not once and UI.held ~= nil and tostring(UI.status:GetText()):find("F5", 1, true), "found twice in a row: F5 offered")
	for i = #rows, 1, -1 do rows[i] = nil end
	for i, r in ipairs(base) do rows[i] = r end
	Redo()
	local kept = UI.held ~= nil
	Redo()
	check(kept and UI.held == nil, "the shown list found again: F5 kept the first time, taken back once that's sure")
	UI.CONFIRM_TRIES = tries
	-- and by itself: a candidate is checked again a moment later (no other search needed)
	table.insert(rows, 1, { name = "Linen Cloth E", itemID = 50603, key = 703 })
	ns.providers.items._dirty = true
	UI:QuietRedo()
	FlushAll()
	check(UI.held ~= nil, "a candidate checked again by itself, then offered")
	for i = #rows, 1, -1 do rows[i] = nil end
	for i, r in ipairs(base) do rows[i] = r end
	UI:Hide(); FlushAll()

	-- (review, 0.51.25) the same rows with new data (one more Linen Cloth in a stack): put up in place, nothing held
	UI:Open("linen 05")
	FlushAll()
	local before05 = UI.results[1]
	rows[6] = { name = "Linen Cloth 05", itemID = 50005, key = 5, count = 7 }
	ns:Changed("items")
	FlushAll()
	check(UI.results[1] and UI.results[1].count == 7 and UI.results[1] ~= before05 and not UI.held,
		"the same row with a new count: the new one shown in its place, no F5 for it")
	UI:Hide(); FlushAll()
	-- (review, 0.51.25) changes a while apart are each searched again: not stopped for good after LIVE_SAME of them
	UI:Open("linen")
	FlushAll()
	for k = 1, UI.LIVE_SAME + 1 do
		rows[#rows + 1] = { name = "Grey Junk " .. k, itemID = 60000 + k, key = 200 + k }
		ns:Changed("items"); FlushAll()
		if UI.live.redoneAt then UI.live.redoneAt = UI.live.redoneAt - 10 end -- (a while passes)
	end
	table.insert(rows, 1, { name = "Linen Cloth Bolt", itemID = 50200, key = 300 })
	ns:Changed("items"); FlushAll()
	check(UI.held ~= nil, "after a few unrelated changes, a while apart: the next real one still held for F5 (same=" .. UI.live.same .. ")")
	UI:Hide(); FlushAll()
	-- (review, 0.51.25) a background search asked for while your own still runs over frames: yours, not its first
	-- frame's best kept up with the rest behind F5
	for i = 1, 300 do rows[#rows + 1] = { name = ("Wool Cloth %03d"):format(i), itemID = 70000 + i, key = 1000 + i } end
	ns.providers.items._dirty = true
	UI.lastScan, UI.lastExtra = nil, nil
	local realClock, tick = _G.debugprofilestop, 0
	_G.debugprofilestop = function() tick = tick + 1; return tick end
	UI:Open("wool")
	local partial = UI.searchJob ~= nil
	UI:QuietRedo()
	local job = UI.searchJob
	FlushAll()
	_G.debugprofilestop = realClock
	check(partial and job and not job.quiet and not UI.held,
		"a redo during your search (still going over frames): run as yours, its rows not held behind F5")
	UI:Hide(); FlushAll()
	-- (review, 0.51.25) held rows don't change what the shown list was searched with (>>> sends, the footer)
	UI:Open("linen >>> party")
	FlushAll()
	local group = UI.groupRows
	table.insert(rows, 1, { name = "Linen Cloth Roll", itemID = 50300, key = 400 })
	ns.providers.items._dirty = true
	UI:QuietRedo(); FlushAll() -- (as item data coming in asks)
	check(UI.held ~= nil and UI.groupRows == group, "held for F5: the shown list's >>> rows unchanged: held="
		.. tostring(UI.held ~= nil) .. " group=" .. tostring(group) .. " now=" .. tostring(UI.groupRows) .. " list=" .. tostring(UI.groupList) .. " #" .. #UI.results)
	T.key("F5")
	check(UI.groupRows ~= group, "...F5: the new list's")
	UI:Hide(); FlushAll()
	-- (review, 0.51.25) over frames: a background search started again mid-way, or F5 pressed while one runs, gives back
	-- the shown list's (not another background search's first frame's)
	local realClock2, tick2 = _G.debugprofilestop, 0
	local function Slow() _G.debugprofilestop = function() tick2 = tick2 + 5; return tick2 end end
	UI:Open("linen >>> party"); FlushAll()
	group = UI.groupRows
	table.insert(rows, 1, { name = "Linen Cloth Scrap", itemID = 50400, key = 500 })
	ns.providers.items._dirty = true
	Slow()
	UI:QuietRedo()
	local over = UI.searchJob ~= nil
	UI:QuietRedo() -- (started again: data came in meanwhile)
	FlushAll()
	_G.debugprofilestop = realClock2
	check(over and UI.held ~= nil and UI.groupRows == group, "a background search started again over frames: the shown list's >>> rows kept"
		.. " (over frames=" .. tostring(over) .. ")")
	-- F5 while another runs: the F5 list's kept when that one's held too
	table.insert(rows, 1, { name = "Linen Cloth Shred", itemID = 50500, key = 600 })
	ns.providers.items._dirty = true
	Slow()
	UI:QuietRedo()
	over = UI.searchJob ~= nil
	T.key("F5") -- (the list held before put up)
	local afterF5 = UI.groupRows
	FlushAll()
	_G.debugprofilestop = realClock2
	check(over and UI.held ~= nil and UI.groupRows == afterF5, "F5's list kept while a background search ran and was held")
	UI:Hide(); FlushAll()
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	ns.db.easyMode = save.easy
	UI:EasyChanged()
	UI:Hide(); FlushAll()
end
