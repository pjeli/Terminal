-- A hunter's pet food (Search/Questions/PetFood.lua): "what can my pet eat" (@item is:petfood: the game's CanPetEatItem,
-- else QuestieDB's foodType against GetPetFoodTypes' diet), "who sells pet food" / "nearest pet food vendor" (@npc
-- sells:petfood faction:friendly sort:distance: Questie's vendors of food of that diet); not a hunter, or no pet out: a note.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local PF, F, Q, L = ns.PetFood, ns.Filters, ns.Questions, ns.L

io.write("[pet food: what can my pet eat, who sells pet food]\n")
do
	local was = { class = _G.UnitClass, exists = _G.UnitExists, pet = rawget(_G, "C_PetInfo"), qd = ns.QuestieData.DB,
		providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode, tpl = rawget(_G, "PET_DIET_TEMPLATE"),
		inst = C_Item.GetItemInfoInstant }
	local ok, err = pcall(function()
		local class, out = "WARRIOR", false
		_G.UnitClass = function() return "Warrior", class end
		_G.UnitExists = function(u) return u == "pet" and out end
		local diet, eats = { "Meat", "Fish" }, { [1001] = true }
		_G.C_PetInfo = { GetPetFoodTypes = function() return diet end, CanPetEatItem = function(id) return eats[id] == true end }
		_G.PET_DIET_TEMPLATE = "Diet: %s"
		-- QuestieDB: 2001 raw meat (a vendor sells it), 2002 bread, 2003 an unknown kind of food, 2004 a sword
		local ITEMS = { [2001] = { foodType = 7, vendors = { 501 } }, [2002] = { foodType = 4, vendors = { 502 } },
			[2003] = { foodType = 3, vendors = { 503 } }, [2004] = { foodType = 0, vendors = { 504 } } }
		ns.QuestieData.DB = function()
			return { QueryItemSingle = function(id, field) return ITEMS[id] and ITEMS[id][field] end,
				ItemIds = function() return { 2001, 2002, 2003, 2004 } end }
		end
		C_Item.GetItemInfoInstant = function(id) if id == 2004 then return id, nil, nil, nil, nil, 2, 0 end return id, nil, nil, nil, nil, 0, 5 end
		PF.Forget()

		-- the question, in its words; others' lines left alone
		local function What(t) local q = PF.Question(t) return q and q.what end
		check(What("what can my pet eat") == "eat" and What("pet food") == "eat" and What("what does my pet eat") == "eat"
			and What("feed my pet") == "eat" and What("who sells pet food") == "sell" and What("nearest pet food vendor") == "sell"
			and What("where to buy pet food") == "sell", "the questions: what it eats, who sells it")
		check(What("pet trainer") == nil and What("my pets") == nil and What("pet food recipes") == nil and What("food") == nil,
			"not the pet trainers', the collections', or a recipe search")
		check(PF.Line({ what = "eat" }) == "@item is:petfood " and PF.Line({ what = "sell" }) == "@npc sells:petfood faction:friendly sort:distance ",
			"its lines: your bags' food it eats; its vendors, friendly, nearest first")
		check(Q.Ranked("what can my pet eat")[1].a.id == "PetFood" and Q.Ranked("nearest pet food vendor")[1].a.id == "PetFood",
			"the registry gives them to it")

		-- not a hunter: nothing eats, the note says why
		local petfood, sells = F.Parse("is:petfood"), F.Parse("sells:petfood")
		check(PF.Diet() == nil and not petfood({ kind = "items", itemID = 1001 }) and next(PF.Vendors()) == nil,
			"not a hunter: no diet, nothing it eats, no vendor")
		local none = PF.None({ what = "eat" })
		check(none[1].name == L["Only for a hunter with a pet out: the game tells its diet then"], "the note says it's for a hunter with a pet out")
		-- a hunter with no pet out: the same
		class = "HUNTER"; PF.Forget()
		local _, why = PF.Diet()
		check(why == "pet" and not petfood({ kind = "items", itemID = 1001 }), "a hunter without a pet out: no diet yet")
		out = true; PF.Forget()

		-- the game's answer for what you carry
		check(petfood({ kind = "items", itemID = 1001 }) and not petfood({ kind = "items", itemID = 1002 }) and not petfood({ kind = "spells" }),
			"is:petfood: the game says what it eats")
		check(PF.Footer({ what = "eat" }) == "Diet: Meat, Fish", "the footer: its diet, as the game's pet tooltip says it: " .. tostring(PF.Footer({ what = "eat" })))
		-- no CanPetEatItem (an older client): Questie's food type against the diet; a meat eater eats raw meat
		_G.C_PetInfo.CanPetEatItem = nil; PF.Forget()
		check(petfood({ kind = "items", itemID = 2001 }) and not petfood({ kind = "items", itemID = 2002 }) and not petfood({ kind = "items", itemID = 1001 }),
			"no CanPetEatItem: Questie's food types (raw meat for a meat eater, no bread)")
		-- vendors: those of food of its diet, by Questie; the search's filter on NPC rows
		local v = PF.Vendors()
		check(v[501] and not v[502] and not v[503] and not v[504], "the vendors of raw meat, not of bread or a sword")
		check(sells({ kind = "npc", key = 501 }) and not F.Parse("sells:petfood")({ kind = "npc", key = 502 }) and not sells({ kind = "items", key = 501 }),
			"sells:petfood on NPC rows")
		-- a diet in another language: each food asked of the game
		diet = { "Fleisch" }; eats = { [2003] = true }
		_G.C_PetInfo.CanPetEatItem = function(id) return eats[id] == true end
		PF.Forget()
		v = PF.Vendors()
		check(v[503] and not v[501], "a diet's name it can't read: each food asked of the game")
		check(PF.Footer({ what = "sell" }) == L["Vendors of your pet's food"] .. ns.DETAIL_SEP .. "Fleisch", "the vendors' footer names the diet")

		-- the search: your bags' food it eats, Simple and Advanced alike
		ns.providers, ns.providerOrder = {}, {}
		ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
			return { { key = 2003, itemID = 2003, name = "Fine Cheese" }, { key = 1002, itemID = 1002, name = "Linen Cloth" } }
		end })
		ns:AliasesChanged()
		UI.lastScan, UI.lastExtra = nil, nil
		ns.db.easyMode = true; UI:EasyChanged()
		local rows, note = Q.Answer("what can my pet eat")
		local names = {}
		for _, e in ipairs(rows) do if ns.Bar.Real(e) then names[#names + 1] = e.name end end
		check(table.concat(names, ",") == "Fine Cheese" and note == "Diet: Fleisch", "\"what can my pet eat\": your food it eats: "
			.. table.concat(names, ",") .. " / " .. tostring(note))
		check(ns.QueryToAdvanced("what can my pet eat") == "@item is:petfood ", "Alt+`: its line")
		eats = {}; PF.Forget(); UI.lastScan, UI.lastExtra = nil, nil
		rows = Q.Answer("what can my pet eat")
		check(rows[1] and rows[1].name == L["Nothing in your bags your pet eats"], "nothing it eats: said: " .. tostring(rows[1] and rows[1].name))
	end)
	_G.UnitClass, _G.UnitExists, _G.C_PetInfo, ns.QuestieData.DB = was.class, was.exists, was.pet, was.qd
	_G.PET_DIET_TEMPLATE, C_Item.GetItemInfoInstant = was.tpl, was.inst
	ns.providers, ns.providerOrder = was.providers, was.order
	ns:AliasesChanged()
	ns.db.easyMode = was.easy; UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	PF.Forget()
	check(ok, "pet food: " .. tostring(err))
end
