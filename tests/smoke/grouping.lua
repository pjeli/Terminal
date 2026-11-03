-- Grouping inside groups (1.0.29-1.0.30, the player: "a generalized solution for other kinds / searches too"): in Simple
-- mode the bar's Group groups whatever a search keeps, whatever kind: a group stepped into (as a filter word, q:rare,
-- in:"Duskwood", or as a "| field:value" step for a field no filter says), stepped into again, a typed "| group by"
-- stepped into, "| first N"; Sort works inside too. Steps that sum, count or group keep their own.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local B, E = ns.Bar, ns.Easy

io.write("[grouping inside groups]\n")
do
	local rows = {}
	local zones = { "Elwynn Forest", "Westfall", "Duskwood" }
	-- (qualities and zones apart: each quality has rows in two zones or more)
	for i = 1, 12 do
		rows[i] = { key = i, name = "Probe Blade " .. i, quality = (i % 3) + 1, zone = zones[(math.floor((i - 1) / 2) % 3) + 1], level = 10 + i }
	end
	local had = ns.providers.groupprobe
	ns:RegisterProvider("groupprobe", { label = "Probe", aliases = { "groupprobe" }, collect = function() return rows end })
	local items
	for _, c in ipairs(E.CATEGORIES) do if c.id == "items" then items = c end end
	table.insert(items.kinds, "groupprobe")
	if E.Reindex then E.Reindex() end
	local easy = ns.db.easyMode
	ns.db.easyMode = true
	UI:EasyChanged()
	local function Groups()
		local g, n, first = 0, 0, nil
		for _, e in ipairs(UI.Results()) do
			n = n + 1
			if e.kind == "aggregate" then g = g + 1; first = first or e end
		end
		return g, n, first
	end
	local ok, err = pcall(function()
		UI:Open(""); FlushAll()
		UI:SetQuery("probe blade", 11); FlushAll()
		B.Pick("group", "quality"); FlushAll()
		local g, _, first = Groups()
		check(g == 3 and first, "a search grouped by quality: " .. g)
		first.activate(first); FlushAll()
		local _, n = Groups()
		check(n == 4 and not B.state.group, "stepped into a quality: its 4 rows, the bar's group taken off: " .. n .. " '" .. UI.edit:GetText() .. "'")
		B.Pick("group", "zone"); FlushAll()
		local g2, _, z = Groups()
		check(g2 >= 2 and z, "then grouped by zone inside it: " .. g2)
		z.activate(z); FlushAll()
		local _, n2 = Groups()
		check(n2 >= 1 and n2 < 4, "stepped in again: that zone's of that quality: " .. n2 .. " '" .. UI.edit:GetText() .. "'")
		B.Pick("group", "level"); FlushAll()
		local g3 = Groups()
		check(g3 == n2, "and grouped a third time (by level): " .. g3)
		B.Pick("group", "level"); FlushAll()
		B.Pick("sort", "level"); FlushAll()
		local r = UI.Results()
		check(#r >= 1 and B.state.sort ~= nil and (not r[2] or (r[1].level or 0) ~= (r[2].level or 0)), "and sorted inside: " .. tostring(B.state.sort))
		-- a typed group stepped into, then the bar's Group
		UI:Hide(); FlushAll(); B.Reset()
		UI:Open(""); FlushAll()
		UI:SetQuery("probe blade | group by zone", 27); FlushAll()
		local tg, _, t1 = Groups()
		check(tg == 3 and t1, "a typed group by zone: " .. tg)
		t1.activate(t1); FlushAll()
		B.Pick("group", "quality"); FlushAll()
		check((Groups()) >= 2, "stepped into it, then the bar's Group by quality: " .. (Groups()))
		-- a field no filter says (kind): stepped into as a "| kind:" step, then the bar's Group still groups
		UI:Hide(); FlushAll(); B.Reset()
		UI:Open(""); FlushAll()
		UI:SetQuery('probe blade | kind:"Probe"', 26); FlushAll()
		B.Pick("group", "quality"); FlushAll()
		check((Groups()) == 3 and UI.edit:GetText():find("| kind:", 1, true), "a \"| kind:\" step kept, the bar's Group over it: " .. (Groups()))
		-- (review, 1.0.35) Alt+` writes that Group after the step (it groups what the step keeps); not after a summing step
		local adv = ns.LineToAdvanced(UI.edit:GetText())
		check(adv:find('| kind:"Probe" | group by quality', 1, true) ~= nil, "Alt+`: the bar's Group after a keeping step: " .. adv)
		check(not ns.LineToAdvanced("probe blade | sum level"):find("group by", 1, true), "...not after a summing one")
		-- the first N, then the bar's Group
		UI:Hide(); FlushAll(); B.Reset()
		UI:Open(""); FlushAll()
		UI:SetQuery("probe blade | first 5", 20); FlushAll()
		B.Pick("group", "quality"); FlushAll()
		check((Groups()) >= 2, "| first 5, then the bar's Group: " .. (Groups()))
		-- a step that sums: its own, the bar's Group not over it ("| count by zone" is a typed group: the bar's Group picked
		-- takes its place, as before)
		UI:Hide(); FlushAll(); B.Reset()
		UI:Open(""); FlushAll()
		UI:SetQuery("probe blade | sum level", 23); FlushAll()
		B.Pick("group", "quality"); FlushAll()
		check(UI.barGroupIgnored == true, "| sum level: the bar's Group not over a sum")
	end)
	UI:Hide(); FlushAll(); B.Reset()
	for i = #items.kinds, 1, -1 do if items.kinds[i] == "groupprobe" then table.remove(items.kinds, i) end end
	if E.Reindex then E.Reindex() end
	if not had then
		ns.providers.groupprobe = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "groupprobe" then table.remove(ns.providerOrder, i) end end
		ns:AliasesChanged()
	end
	ns.db.easyMode = easy
	UI:EasyChanged()
	if not ok then check(false, "grouping: " .. tostring(err)) end
end
