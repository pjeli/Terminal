-- More item sources in the sources chain (Steps/Chains.lua): the containers an item comes out of (QuestieDB's itemDrops),
-- OneForAll's reagent sources (skinned from, fished in, disenchanted, found in, made: OneForAll/Reagents.lua), the
-- tokens it comes from (AtlasLoot's Token data: Questions/Tokens.lua), and what a token turns into ("what does libram
-- of focus give": the tokens' "rewards" definition).
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local P, I, OA = ns.Pipes, ns.Integrations, ns.OneForAll

local function Find(rows, name)
	for _, r in ipairs(rows) do if r.name == name then return r end end
end
local function Names(rows)
	local t = {}
	for i, r in ipairs(rows) do t[i] = tostring(r.name) end
	return table.concat(t, ", ")
end

io.write("[chains: more sources, and what tokens give]\n")
do
	local save = { providers = ns.providers, order = ns.providerOrder, name = C_Item.GetItemNameByID, AL = rawget(_G, "AtlasLoot"),
		field = I.ItemField, npc = I.NpcRow, obj = I.ObjectName, quest = I.QuestRow, npcField = I.NpcField,
		qii = ns.Filters.QuestieItemIds, lib = rawget(_G, "OneForAll"), on = OA.on, failed = I.failed, print = ns.Print,
		class = rawget(_G, "UnitClass"), easy = ns.db.easyMode }
	local ok, err = pcall(function()
		ns.db.easyMode = false; UI:EasyChanged()
		ns.Print = function() end
		local NAMES = { [7971] = "Black Pearl", [7973] = "Big-mouth Clam", [17962] = "Blue Sack of Gems", [12361] = "Blue Sapphire",
			[18333] = "Libram of Focus", [18330] = "Arcanum of Focus", [18335] = "Pristine Black Diamond", [20928] = "Qiraji Bindings of Command",
			[21330] = "Conqueror's Spaulders", [21350] = "Mantle of the Oracle", [4235] = "Heavy Hide", [6291] = "Raw Brilliant Smallfish",
			[10939] = "Greater Magic Essence", [7974] = "Zesty Clam Meat" }
		C_Item.GetItemNameByID = function(id) return NAMES[id] end
		local IDS = {}
		for id, n in pairs(NAMES) do IDS[ns.Lower(n)] = id end
		ns.Filters.QuestieItemIds = function(w) return IDS[w] and { IDS[w] } or {} end
		-- Questie: Black Pearl comes out of a clam
		local FIELDS = { [7971] = { itemDrops = { 7973 } } }
		I.ItemField = function(id, f) return FIELDS[id] and FIELDS[id][f] end
		I.NpcRow = function(id) return id == 4422 and { kind = "npc", key = 4422, name = "Agathelos the Raging", detail = "Boss" } or nil end
		I.ObjectName, I.QuestRow = function() return nil end, function() return nil end
		I.NpcField = function(id, f) if f == "friendlyToFaction" then return "AH" end end
		-- AtlasLoot: tokens (a sack of gems holds the pearl; a Libram is turned in for its arcanum, with a diamond and the
		-- libram itself after the 0; the bindings are each class's own)
		local TOKENS = {
			[17962] = { 12361, 7971, { 1529, "1-2" }, type = 2 },
			[18333] = { 18330, 0, 18333, 18335, { 14344, 4 }, type = 4 },
			[20928] = { "CLASS_WARRIOR", 21330, 0, "CLASS_PRIEST", 21350, type = 6 },
			[34399] = { 34399, 0, { 34664, "1" }, type = 7 }, -- (bought with: gives nothing)
		}
		local asked = {}
		_G.AtlasLoot = { Data = { Token = {
			GetTokenData = function(id) return TOKENS[id] end,
			GetClassItemsForToken = function(id, class) asked[#asked + 1] = class; if id == 20928 and class == "PRIEST" then return { 21350 } end end,
		} } }
		_G.UnitClass = function() return "Priest", "PRIEST" end
		local function Rows(list) return function() local out = {} for i, r in ipairs(list) do local e = {} for k, v in pairs(r) do e[k] = v end e.key = e.key or i out[i] = e end return out end end
		ns.providers, ns.providerOrder = {}, {}
		ns:RegisterProvider("recipes", { label = "Recipe", aliases = { "recipe" }, collect = Rows({}) })
		ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = Rows({}) })
		ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = Rows({
			{ name = "Blue Sack of Gems", itemID = 17962, detail = "Trash  Blackrock Depths" },
			{ name = "Libram of Focus", itemID = 18333, detail = "Trash  Dire Maul" },
			{ name = "Qiraji Bindings of Command", itemID = 20928, detail = "Twin Emperors  Temple of Ahn'Qiraj" },
			{ name = "Robes of Ghostly Hatred", itemID = 34399, detail = "Vendor  Shattrath" } }) })
		ns:RegisterProvider("stored", { label = "Stored", aliases = { "stored" }, collect = Rows({}) })
		ns.Tokens.Forget(); P.ClearCrafts(); P.ClearSteps()

		-- containers: QuestieDB's itemDrops ("where to find black pearl"), Enter walks on to the clam's own sources
		check(P.Canonical("where to find black pearl") == "black pearl > sources", "where to find black pearl: its sources")
		local rows = P.Search("black pearl > sources")
		local clam, sack = Find(rows, "Big-mouth Clam"), Find(rows, "Blue Sack of Gems")
		check(clam and clam.detail == "Contains it" and clam.pipeNext == "sources" and clam.pipeHow == "found in",
			"Found in a clam (Questie's itemDrops), Enter: the clam's sources: " .. Names(rows))
		-- and the token it's in: AtlasLoot's sack of gems
		check(sack and sack.detail:find("Contains it", 1, true) and sack.pipeHow == "found in", "and in a sack of gems (AtlasLoot's token data)")
		rows = P.Search("arcanum of focus > sources")
		local libram = Find(rows, "Libram of Focus")
		check(libram and libram.detail:find("Gives it", 1, true) and libram.pipeHow == "from" and #rows == 1,
			"an arcanum: from its Libram (and not from the diamond turned in with it): " .. Names(rows))
		rows = P.Search("pristine black diamond > sources")
		check(#rows == 1 and rows[1].noActivate, "what's turned in with a token doesn't come from it: " .. Names(rows))

		-- what a token gives: "what does libram of focus give" (a token's name, exactly), the first group only
		check(P.Canonical("what does libram of focus give") == "libram of focus > rewards"
			and P.Canonical("what does blue sack of gems contain") == "blue sack of gems > rewards"
			and P.Canonical("what does robes of ghostly hatred give") == nil and P.Canonical("what does zzqq give") == nil,
			"what does <token> give: the token's rewards; not a token: not this")
		rows = P.Search("libram of focus > rewards")
		check(#rows == 1 and rows[1].name == "Arcanum of Focus" and rows[1].detail:find("From Libram of Focus", 1, true),
			"a Libram gives its arcanum: " .. Names(rows))
		rows = P.Search("blue sack of gems > gives")
		check(Find(rows, "Black Pearl") and Find(rows, "Blue Sapphire") and Find(rows, "Blue Sack of Gems") == nil,
			"a sack: everything in it (> gives: the rewards link): " .. Names(rows))
		-- per class: yours first (AtlasLoot's pick for your class), each saying whose
		rows = P.Search("qiraji bindings of command > rewards")
		check(#rows == 2 and rows[1].name == "Mantle of the Oracle" and rows[1].detail:find("Priest", 1, true)
			and rows[2].detail:find("Warrior", 1, true) and asked[#asked] == "PRIEST",
			"class tokens: your class's first, each said: " .. Names(rows) .. " / " .. tostring(rows[1] and rows[1].detail))

		-- (1.4.4) the idle warm-up reads the loot list's tokens ahead, a slice a frame (every loot row is looked at: it
		-- was all read in one go by the first question); asked for before that's done, what's left is read at once
		do
			local list = ns:GetEntries(ns.providers.loot)
			local clockWas, t = _G.debugprofilestop, 0
			_G.debugprofilestop = function() t = t + 10 return t end -- (every look at the clock: a slice has gone by)
			local Tok = _G.AtlasLoot.Data.Token
			local gets, getWas = 0, Tok.GetTokenData
			Tok.GetTokenData = function(id) gets = gets + 1 return getWas(id) end
			ns.Tokens.Forget()
			ns.Tokens.Warm(list)
			local x = ns.Tokens.index
			check(x and x.list == list and x.at == 2 and gets == 1, "the warm-up's first slice: one loot row read, the rest left for later frames: "
				.. tostring(x and x.at) .. " / " .. gets)
			T.FlushAll()
			check(ns.Tokens.index == x and x.at == math.huge and #x.ids == 3 and gets == 4, "later frames read the rest (3 tokens among 4 rows): "
				.. tostring(x.at) .. " / " .. #x.ids .. " / " .. gets)
			check(ns.Tokens.Index() == x and gets == 4, "asked then: nothing is read again: " .. gets)
			ns.Tokens.Forget(); gets = 0
			ns.Tokens.Warm(list)
			local y = ns.Tokens.Index()
			check(y ~= x and y.at == math.huge and #y.ids == 3 and gets == 4, "asked before the warm-up is done: what's left is read at once, nothing twice: "
				.. #y.ids .. " / " .. gets)
			T.FlushAll()
			check(gets == 4 and #y.ids == 3 and ns.Tokens.index == y, "the warm-up's later slices then find nothing left to do: " .. gets)
			ns.Tokens.Warm(list)
			check(ns.Tokens.index == y and gets == 4, "a list read already isn't read again")
			local hooked = false
			for _, fn in ipairs(ns.afterWarm.loot or {}) do if fn == ns.Tokens.Warm then hooked = true end end
			check(hooked, "it runs after the warm-up builds the loot list")
			_G.debugprofilestop, Tok.GetTokenData = clockWas, getWas
			ns.Tokens.Forget()
		end

		-- OneForAll's reagent sources
		_G.OneForAll = {
			REAGENT_SOURCES = {
				[4235] = { sk = { 4422, 9999 }, skn = 11 }, [6291] = { f = "Dun Morogh, Nowhere Land" },
				[10939] = { c = { 0, "3x Lesser Magic Essence" }, de = { 16, 30 } }, [7974] = { ci = "Big-mouth Clam" },
				[118] = { d = { 94 } }, -- (Questie's already: nothing of Terminal's)
			},
			REAGENT_MOBS = { [9999] = { "Snow Leopard", 1426, 50, 50 } },
		}
		I.failed, OA.on = {}, nil
		OA.Forget(); OA.Reagents.relation = nil
		I._.SetupOneForAll()
		check(OA.Reagents.Data() and OA.Reagents.Data().n == 4, "OneForAll's reagent sources read: those Terminal says")
		check(P.Canonical("where to farm heavy hide") == "heavy hide > sources", "where to farm heavy hide: its sources")
		P.ClearSteps()
		rows = P.Search("heavy hide > sources")
		local boss, leopard = Find(rows, "Agathelos the Raging"), Find(rows, "Snow Leopard")
		check(boss and boss.detail:find("Skinning", 1, true) and boss.pipeHow == "skinned from" and boss.kind == "npc",
			"skinned from: the NPC's row (Enter: the map): " .. Names(rows))
		check(leopard and leopard.noActivate and leopard.detail == "Skinning", "one Questie doesn't know: OneForAll's name for it")
		rows = P.Search("raw brilliant smallfish > sources")
		local dm, nowhere = Find(rows, "Dun Morogh"), Find(rows, "Nowhere Land")
		check(dm and dm.kind == "maps" and dm.mapID == 1426 and dm.pipeHow == "fished in" and nowhere and nowhere.noActivate,
			"fished in: the zone's map row, a zone not known just named: " .. Names(rows))
		rows = P.Search("greater magic essence > sources")
		check(Find(rows, "Disenchanting items of item level 16-30") and Find(rows, "3x Lesser Magic Essence")
			and Find(rows, "3x Lesser Magic Essence").detail == "Crafted", "disenchanting, and what makes it: " .. Names(rows))
		rows = P.Search("zesty clam meat > sources")
		local c2 = Find(rows, "Big-mouth Clam")
		check(c2 and c2.itemID == 7973 and c2.pipeNext == "sources", "found in an item: its row, Enter: its sources: " .. Names(rows))
		check(OA.Status():find("4 reagents' sources", 1, true), ".integrations says it: " .. tostring(OA.Status()))

		-- without OneForAll and AtlasLoot: only Questie's
		_G.OneForAll, _G.AtlasLoot = nil, nil
		OA.Forget(); ns.Tokens.Forget(); P.ClearSteps()
		rows = P.Search("heavy hide > sources")
		check(#rows == 1 and rows[1].noActivate, "without OneForAll: no skinning: " .. Names(rows))
		rows = P.Search("black pearl > sources")
		check(Find(rows, "Big-mouth Clam") and not Find(rows, "Blue Sack of Gems"), "without AtlasLoot: the clam still")
		check(P.Canonical("what does libram of focus give") == nil, "and no token question")
	end)
	-- (the OneForAll sources definition goes with it)
	local defs = P.relations.sources or {}
	for i = #defs, 1, -1 do if defs[i].addon == "OneForAll" then table.remove(defs, i) end end
	OA.Reagents.relation = nil
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	C_Item.GetItemNameByID, _G.AtlasLoot, _G.OneForAll, _G.UnitClass = save.name, save.AL, save.lib, save.class
	I.ItemField, I.NpcRow, I.ObjectName, I.QuestRow, I.NpcField = save.field, save.npc, save.obj, save.quest, save.npcField
	ns.Filters.QuestieItemIds, OA.on, I.failed, ns.Print = save.qii, save.on, save.failed, save.print
	OA.Forget(); ns.Tokens.Forget(); P.ClearCrafts(); P.ClearSteps()
	ns.db.easyMode = save.easy; UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	if not ok then check(false, "pipes_sources: " .. tostring(err)) end
end
