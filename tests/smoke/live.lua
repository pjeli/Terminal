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
	UI.lastScan, UI.lastOverview = nil, nil
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
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	UI.lastScan, UI.lastOverview = nil, nil
	ns.db.easyMode = save.easy
	UI:EasyChanged()
	UI:Hide(); FlushAll()
end
