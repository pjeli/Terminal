-- OneForAll's window's tabs in @panel (1.0.14, the player's ask; Providers/Integrations/OneForAll/OneForAll.lua): a row a tab, read
-- from its own list (UI.panels), Enter opens its window on it (its OpenPanel); the game's panels stay; a list not in the
-- shape expected said once; without OneForAll: none.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local I, OA, L = ns.Integrations, ns.OneForAll, ns.L

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[oneforall: its window's tabs in @panel]\n")
do
	local save = { lib = rawget(_G, "OneForAll"), failed = I.failed, on = OA.on, print = ns.Print, extras = ns.PanelExtras, added = OA.panelsAdded,
		providers = ns.providers, order = ns.providerOrder }
	local said = {}
	ns.Print = function(_, m) said[#said + 1] = m end
	local KINDS = { "book", "tame", "itemset", "transport" }
	local function Fresh()
		for _, id in ipairs(KINDS) do
			ns.providers[id] = nil
			for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
		end
		I.failed, OA.on, OA.panelsAdded = {}, nil, nil
		ns.PanelExtras = {}
		OA.Forget()
		I._.SetupOneForAll()
		ns:AliasesChanged()
	end
	local function Panels()
		local p = ns.providers.panels
		p._dirty = true
		local mine, all = {}, ns:GetEntries(p)
		for _, e in ipairs(all) do if e.oneForAllTab then mine[#mine + 1] = e end end
		return mine, all
	end
	local ok, err = pcall(function()
		ns.providers, ns.providerOrder = {}, {}
		for _, id in ipairs(save.order) do ns.providers[id] = save.providers[id]; ns.providerOrder[#ns.providerOrder + 1] = id end
		local before = #select(2, Panels())
		local opened = {}
		_G.OneForAll = {
			BOOKS = { { name = "A Book", questId = 1, itemId = 2 } },
			UI = { panels = { { key = "settings", label = "Settings", order = 0 }, { key = "armory", label = "Armory", order = 1 },
				{ key = "dungeons", label = "Dungeons & Raids", order = 2 }, { key = 5, label = "Broken" } } },
		}
		function OneForAll:OpenPanel(key) opened[#opened + 1] = key end
		Fresh()
		local mine, all = Panels()
		check(Names(mine) == "OneForAll: Settings | OneForAll: Armory | OneForAll: Dungeons & Raids", "a row a tab, in its order: " .. Names(mine))
		check(#all == before + 3, "the game's panels stay: " .. #all .. " of " .. (before + 3))
		check(mine[1].noCombat == true, "not opened in combat (its window can hold secure buttons)")
		mine[3].activate(mine[3])
		check(opened[1] == "dungeons", "Enter: its window on that tab: " .. tostring(opened[1]))
		local res = UI:Search("@panel dungeons")
		local found = false
		for _, e in ipairs(res) do if e.oneForAllTab == "dungeons" then found = true end end
		check(found, "@panel dungeons: " .. Names(res))
		res = UI:Search("@panel ofa")
		check(#res >= 3, "@panel ofa: its tabs: " .. Names(res))
		local lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find(L["%d of its window's tabs (@panel)"]:format(3), 1, true), ".integrations: " .. lines)
		-- not in the shape expected: said; its panels gone, the game's stay
		said = {}
		OneForAll.OpenPanel = nil
		Fresh()
		mine, all = Panels()
		check(#mine == 0 and #all == before, "no OpenPanel: no rows of its own")
		local s = false
		for _, m in ipairs(said) do if m:find(L["Its window's tabs (in @panel) are unavailable."], 1, true) then s = true end end
		check(s, "said in chat: " .. tostring(said[1]))
		_G.OneForAll = nil
		Fresh()
		mine = Panels()
		check(#mine == 0, "without OneForAll: none")
	end)
	_G.OneForAll = save.lib
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	I.failed, OA.on, ns.Print, ns.PanelExtras, OA.panelsAdded = save.failed, save.on, save.print, save.extras, save.added
	OA.Forget()
	if ns.providers.panels then ns.providers.panels._dirty = true end
	if not ok then check(false, "oneforall_panels: " .. tostring(err)) end
end
