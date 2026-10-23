-- Top N (0.66.7, the player): "| first 3" in Advanced; "the 3 nearest mailboxes", "top 5 upgrades", "my 10 most valuable
-- items", "5 swords", "the closest innkeeper" in plain words. Search/Pipes.lua (A.Parse, A.Apply), Easy.lua (TopN,
-- ORDER_WORDS), UI/Results.lua (TakeAggregate).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local E, B, A = ns.Easy, ns.Bar, ns.Aggregate

io.write("[topn: the first N, in words and as | first N]\n")
do
	local CASES = {
		{ "the 3 nearest mailboxes", "the nearest mailboxes", 3 },
		{ "top 5 upgrades", "upgrades", 5 },
		{ "my 10 most valuable items", "my most valuable items", 10 },
		{ "5 swords", "swords", 5 },
		{ "three swords", "swords", 3 },
		{ "the closest innkeeper", "the closest innkeeper", 1 },
		{ "first 3 quests", "quests", 3 },
		-- not top N
		{ "3 stacks of linen", "3 stacks of linen", nil },
		{ "10 slot bag", "10 slot bag", nil },
		{ "level 20 swords", "level 20 swords", nil },
		{ "two handed swords", "two handed swords", nil },
		{ "3 + 4", "3 + 4", nil },
		{ "closest innkeeper", "closest innkeeper", nil },
		{ "20", "20", nil },
	}
	for _, c in ipairs(CASES) do
		local rest, n = E.TopN(c[1])
		check(rest == c[2] and n == c[3], ("%q -> %q, %s: %q, %s"):format(c[1], c[2], tostring(c[3]), tostring(rest), tostring(n)))
	end
	-- the step
	local spec = A.Parse({ "first 3" }, "sword")
	check(spec.first == 3 and not spec.bad and not A.Summing(spec), "| first 3: a keeping step, not a sum")
	check(A.Parse({ "first x" }, "sword").bad and A.Parse({ "first" }, "sword").bad == "", "| first x: said; | first: still typed")
	spec = A.Parse({ "first 2", "sum value" }, "sword")
	check(spec.first == 2 and spec.last and spec.last.op == "sum", "| first 2 | sum value")
	check(A.Parse({ "sum value", "first 2" }, "sword").bad, "a sum is the last step")

	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	local ROWS = { { "Iron Sword", 2, 5 }, { "Arcanite Sword", 4, 1 }, { "Bronze Sword", 3, 9 }, { "Copper Sword", 1, 1 },
		{ "Mithril Sword", 3, 2 } }
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
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open(""); FlushAll()
	UI:SetQuery("@item sword sort:quality | first 2"); FlushAll()
	check(Names() == "Arcanite Bronze", "the 2 best: " .. Names())
	UI:SetStatus()
	check(tostring(UI.status:GetText()):find(ns.L["%d of %d"]:format(2, 5), 1, true), "the footer: 2 of 5: " .. tostring(UI.status:GetText()))
	UI:SetQuery("@item sword sort:count | first 2 | sum count"); FlushAll()
	local r = UI.Results()[1]
	check(r and tostring(r.name):find("14", 1, true), "the 2 most counted, summed: 9 + 5 = 14: " .. tostring(r and r.name))
	-- Simple mode: in words; Alt+` writes the step
	ns.db.easyMode = true; UI:EasyChanged()
	UI:SetQuery("the 2 best quality sword"); FlushAll()
	check(Names() == "Arcanite Bronze", "the 2 best quality sword: " .. Names())
	local adv = ns.Easy.ToAdvanced("the 2 best quality sword")
	check(adv:find("sort:quality", 1, true) and adv:find("| first 2", 1, true), "Alt+` writes sort:quality ... | first 2: " .. adv)
	UI:SetQuery("2 sword"); FlushAll()
	check(#UI.Results() == 2, "2 sword: two of them: " .. #UI.Results())
	UI:SetQuery("the cheapest sword"); FlushAll()
	check(#UI.Results() == 1, "the cheapest sword: one")
	UI:Hide(); FlushAll()
	ns.providers, ns.providerOrder, ns.db.easyMode = saved.providers, saved.order, saved.easy
	ns:AliasesChanged(); UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
end

io.write("[topn: the nearest few NPCs]\n")
do
	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	local NPCS = { { "Innkeeper Farley", 295 }, { "Innkeeper Allison", 6740 }, { "Innkeeper Far Away", 9999 }, { "Innkeeper Near", 7 } }
	ns:RegisterProvider("npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = function()
		local out = {}
		for i, r in ipairs(NPCS) do out[i] = { name = r[1], key = r[2], npcID = r[2], activate = function() end } end
		return out
	end })
	UI.lastScan = nil
	local I = ns.Integrations
	local save = { here = I.Here, dist = I.NpcDistance, field = I.NpcField, defs = I.NpcFlagDefs, group = _G.UnitFactionGroup }
	local DIST = { [295] = 120, [6740] = 40, [7] = 10 }
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	I.NpcDistance = function(id) return DIST[id] end
	I.NpcField = function(id, f) if f == "npcFlags" then return 128 end if f == "friendlyToFaction" then return "AH" end end
	I.NpcFlagDefs = function() return { VENDOR = 4, REPAIR = 4096, INNKEEPER = 128 } end
	_G.UnitFactionGroup = function() return "Alliance" end
	ns.Filters.ClearCache()
	ns.db.easyMode = true; UI:EasyChanged()
	local function Names()
		local t = {}
		for _, e in ipairs(UI.Results()) do if B.Real(e) then t[#t + 1] = tostring(e.name) end end
		return table.concat(t, " | ")
	end
	UI:Open(""); FlushAll()
	UI:SetQuery("the 2 nearest innkeeper"); FlushAll()
	check(Names() == "Innkeeper Near | Innkeeper Allison", "the 2 nearest innkeepers: " .. Names())
	UI:SetQuery("the closest innkeeper"); FlushAll()
	check(Names() == "Innkeeper Near", "the closest innkeeper: one: " .. Names())
	UI:SetQuery("the 2 farthest innkeeper"); FlushAll()
	check(Names():find("^Innkeeper Far Away") and #UI.Results() == 2, "the 2 farthest, the unknown first: " .. Names())
	UI:Hide(); FlushAll()
	I.Here, I.NpcDistance, I.NpcField, I.NpcFlagDefs, _G.UnitFactionGroup = save.here, save.dist, save.field, save.defs, save.group
	ns.providers, ns.providerOrder, ns.db.easyMode = saved.providers, saved.order, saved.easy
	ns:AliasesChanged(); UI:EasyChanged()
	ns.Filters.ClearCache()
	UI.lastScan, UI.lastExtra = nil, nil
end
