-- Sort by more than one field (0.66.4, the player): sort:quality,-count in Advanced; Simple mode's Sort takes a "then by"
-- with Shift. Search/Filters/Npcs.lua (SortOf), UI/Bar.lua (SortSpec, Keyed, SortRows, Order, PickThen).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local B, F = ns.Bar, ns.Filters

io.write("[multisort: sort:quality,-count; Sort's then by]\n")
do
	-- the words
	check(F.SortOf("sort:quality,-count") == "quality,-count", "sort:quality,-count read: " .. tostring(F.SortOf("sort:quality,-count")))
	check(F.SortOf("sort:quality,lvl,name") == "quality,level,name", "each part as its own word says: " .. tostring(F.SortOf("sort:quality,lvl,name")))
	check(F.SortOf("sort:quality,nearest") == "quality,distance" and F.SortOf("sort:best,level") == nil and F.SortOf("sort:level,") == nil
		and F.SortOf("sort:level,bogus") == nil, "plan and best stand alone (distance doesn't: 0.66.16); a part that isn't a sort: none")
	check(#F.SortList("quality,-count") == 2 and F.SortList("quality,-count")[2] == "-count", "its parts")

	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	local ROWS = {
		{ "Iron Sword", 2, 5 }, { "Arcanite Sword", 4, 1 }, { "Bronze Sword", 3, 9 }, { "Copper Sword", 2, 1 },
		{ "Mithril Sword", 3, 2 }, { "Tin Sword", 2, 7 },
	}
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
		local out = {}
		for i, r in ipairs(ROWS) do out[i] = { name = r[1], quality = r[2], count = r[3], key = i } end
		return out
	end })
	ns:AliasesChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	local function Names()
		local t = {}
		for _, e in ipairs(UI.Results()) do if B.Real(e) then t[#t + 1] = tostring(e.name):match("^(%S+)") end end
		return table.concat(t, " ")
	end
	-- Advanced: the best quality first, then the fewest first on a tie; and the most on a tie
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open(""); FlushAll()
	UI:SetQuery("@item sword sort:quality,-count"); FlushAll()
	check(Names() == "Arcanite Mithril Bronze Copper Iron Tin", "by quality, then the fewest: " .. Names())
	UI:SetQuery("@item sword sort:quality,count"); FlushAll()
	check(Names() == "Arcanite Bronze Mithril Tin Iron Copper", "by quality, then the most: " .. Names())
	-- an answer (not scored) in that order too
	local ordered = B.Order({ { name = "a", quality = 2, count = 1 }, { name = "b", quality = 2, count = 3 }, { name = "c", quality = 3, count = 1 } },
		"quality,count")
	check(ordered[1].name == "c" and ordered[2].name == "b" and ordered[3].name == "a", "B.Order: by quality, then count")
	-- past 5000 rows (the kept-best heap): the same order
	local big = {}
	for i = 1, 6000 do big[i] = { name = "r" .. i, quality = i % 3, count = i % 7 } end
	B.SortRows(big, "quality,-count", 5)
	table.sort(big, function(a, b) return (a._score or 0) > (b._score or 0) end)
	check(big[1].quality == 2 and big[1].count == 0 and big[5].quality == 2 and big[5].count == 0 and big[1]._score > big[2]._score,
		"past 5000 rows: the best quality, the fewest first: " .. big[1].quality .. "/" .. big[1].count)

	-- Simple mode: Sort's then by, with Shift
	ns.db.easyMode = true; UI:EasyChanged()
	UI:SetQuery("sword"); FlushAll()
	B.Pick("sort", "quality"); FlushAll()
	B.Pick("sort", "count", true); FlushAll()
	check(B.state.sort == "quality" and B.state.thenBy == "count", "Shift picked: then by count: " .. tostring(B.state.thenBy))
	check(Names() == "Arcanite Bronze Mithril Tin Iron Copper", "by quality, then the most: " .. Names())
	check(ns.QueryToAdvanced("sword"):find("sort:quality,count", 1, true), "Alt+` writes sort:quality,count: " .. ns.QueryToAdvanced("sword"))
	local same, why = T.SameAsAdvanced("sword")
	check(same, "the same as Advanced's: " .. tostring(why))
	-- the menu: its arrow, said as then by
	B.ShowMenu("sort", B.strip.buttons[2])
	local line, hint
	for _, b in ipairs(B.menu.lines) do
		if b:IsShown() and b.id == "count" then line = b end
		if b:IsShown() and b.fs:GetText() == ns.L["Shift: then by another"] then hint = b end
	end
	check(line and line.arrow:IsShown() and line.fs:GetText() == ns.L["then by %s"]:format(ns.L["Count"]) and hint,
		"the menu says then by Count, with its arrow, and how to pick one: " .. tostring(line and line.fs:GetText()))
	B.HideMenu()
	-- again: the other way round; a third time: gone
	B.Pick("sort", "count", true); FlushAll()
	check(B.state.thenBy == "-count" and Names() == "Arcanite Mithril Bronze Copper Iron Tin", "again: the fewest: " .. Names())
	B.Pick("sort", "count", true); FlushAll()
	check(B.state.thenBy == nil, "a third time: no then by")
	-- the sort itself changed to it: no then by
	B.Pick("sort", "count", true); FlushAll()
	B.Pick("sort", "count"); FlushAll()
	check(B.state.sort ~= nil and B.state.thenBy == nil, "the sort is count now: no then by of count")
	-- nothing sorted: Shift's pick is the sort
	B.Clear("sort"); FlushAll()
	B.Pick("sort", "quality", true); FlushAll()
	check(B.state.sort == "quality" and B.state.thenBy == nil, "nothing sorted yet: Shift's pick is the sort")
	-- a typed sort of several fields: the bar shows both; Shift takes it over
	B.Clear("sort"); FlushAll()
	UI:SetQuery("sword sort:quality,-count"); FlushAll()
	check(Names() == "Arcanite Mithril Bronze Copper Iron Tin", "typed in Simple mode: " .. Names())
	local opts = {}
	for _, o in ipairs(B.Options("sort")) do if o.on then opts[#opts + 1] = o.id .. (o.thenBy and "+" or "") end end
	check(table.concat(opts, " ") == "quality count+", "the bar: quality, then count: " .. table.concat(opts, " "))
	B.Pick("sort", "name", true); FlushAll()
	check(B.state.sort == "quality" and B.state.thenBy == "name" and not UI.edit:GetText():find("sort:", 1, true)
		and Names() == "Arcanite Bronze Mithril Copper Iron Tin",
		"Shift on another: the bar's own sort now, then by name, the typed word gone: " .. tostring(B.state.thenBy) .. " / "
		.. UI.edit:GetText() .. " / " .. Names())
	-- (review) the typed sort's first field clicked: turned round, its "then by" kept (it was never matched: the whole
	-- "quality,-count" was compared with "quality")
	B.Reset(); FlushAll()
	UI:SetQuery("sword sort:quality,-count"); FlushAll()
	B.Pick("sort", "quality"); FlushAll()
	check(B.state.sort == "-quality" and B.state.thenBy == "-count" and not UI.edit:GetText():find("sort:", 1, true)
		and Names() == "Copper Iron Tin Mithril Bronze Arcanite",
		"its first field clicked: the lowest quality first now, still then the fewest: " .. tostring(B.state.sort) .. " "
		.. tostring(B.state.thenBy) .. " / " .. Names())
	-- (review) the Sort button says "Distance" alone when distance is first: no row ties on yards to be sorted by more
	B.Reset(); FlushAll()
	UI:SetQuery("sword sort:distance,level"); FlushAll()
	check(B.Label("sort") == ns.L["Sort: %s"]:format(ns.L["Distance"]), "distance first: its label alone: " .. tostring(B.Label("sort")))
	UI:SetQuery("sword sort:quality,-count"); FlushAll()
	check(B.Label("sort") == ns.L["Sort: %s, %s"]:format(ns.L["Quality"], ns.L["Count"]), "a sort and its then by: " .. tostring(B.Label("sort")))

	B.Reset()
	UI:Hide(); FlushAll()
	ns.providers, ns.providerOrder, ns.db.easyMode = saved.providers, saved.order, saved.easy
	ns:AliasesChanged(); UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
end

io.write("[multisort: a field, then distance (0.66.16, the player's sort:level,distance)]\n")
do
	local I = ns.Integrations
	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	local save = { here = I.Here, dist = I.NpcDistance, field = I.NpcField, defs = I.NpcFlagDefs, group = _G.UnitFactionGroup }
	ns.providers, ns.providerOrder = {}, {}
	local NPCS = { { "Innkeeper Far", 1, 30 }, { "Innkeeper Near", 2, 30 }, { "Innkeeper Low", 3, 20 }, { "Innkeeper Mid", 4, 30 } }
	local DIST = { [1] = 900, [2] = 10, [3] = 500, [4] = 100 }
	local LVL = {}
	ns:RegisterProvider("npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = function()
		local out = {}
		for i, r in ipairs(NPCS) do out[i] = { name = r[1], key = r[2], npcID = r[2], activate = function() end }; LVL[r[2]] = r[3] end
		return out
	end })
	ns:AliasesChanged()
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	I.NpcDistance = function(id) return DIST[id] end
	I.NpcField = function(id, f)
		if f == "npcFlags" then return 128 end
		if f == "friendlyToFaction" then return "AH" end
		if f == "minLevel" or f == "maxLevel" then return LVL[id] end
	end
	I.NpcFlagDefs = function() return { VENDOR = 4, REPAIR = 4096, INNKEEPER = 128 } end
	_G.UnitFactionGroup = function() return "Alliance" end
	F.ClearCache()
	UI.lastScan, UI.lastExtra = nil, nil
	ns.db.easyMode = false; UI:EasyChanged()
	check(F.SortOf("sort:level,distance") == "level,distance" and F.SortOf("sort:level,-distance") == "level,-distance"
		and F.SortOf("sort:distance,level") == "distance,level", "distance in a list of sorts")
	local function Names(q)
		UI:Hide(); FlushAll()
		UI:Open(q); FlushAll()
		local t = {}
		for _, e in ipairs(UI.Results()) do if B.Real(e) then t[#t + 1] = tostring(e.name):gsub("Innkeeper ", "") end end
		return table.concat(t, " ")
	end
	check(Names("@npc is:innkeeper faction:friendly sort:level,distance ") == "Low Near Mid Far", "by level, then the nearest: " .. Names("@npc is:innkeeper faction:friendly sort:level,distance "))
	check(Names("@npc is:innkeeper faction:friendly sort:-level,-distance ") == "Far Mid Near Low", "the highest level, then the farthest: " .. Names("@npc is:innkeeper faction:friendly sort:-level,-distance "))
	check(Names("@npc is:innkeeper sort:distance,level ") == "Near Mid Low Far", "distance first: the nearest first")
	-- (review) more rows than a search lists: the lowest level first, however far (only the 100 nearest were kept, and
	-- the low-level innkeeper 500 yards off was left out)
	for i = 1, 150 do NPCS[#NPCS + 1] = { "Innkeeper Town" .. i, 100 + i, 30 }; DIST[100 + i] = i end
	ns:Changed("npc"); F.ClearCache()
	local many = Names("@npc is:innkeeper faction:friendly sort:level,distance ")
	check(many:match("^%S+") == "Low", "150 more near: the lowest level still first: " .. many:sub(1, 40))
	for i = #NPCS, 5, -1 do NPCS[i] = nil end
	UI:Hide(); FlushAll()
	I.Here, I.NpcDistance, I.NpcField, I.NpcFlagDefs, _G.UnitFactionGroup = save.here, save.dist, save.field, save.defs, save.group
	ns.providers, ns.providerOrder, ns.db.easyMode = saved.providers, saved.order, saved.easy
	ns:AliasesChanged(); UI:EasyChanged()
	F.ClearCache()
	UI.lastScan, UI.lastExtra = nil, nil
end
