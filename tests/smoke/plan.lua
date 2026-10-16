-- A profession's levelling plan (Plan.lua, 0.48.2, the player's ask): sort:plan / "blacksmithing plan": the recipes that
-- still give skill, by how many times your materials make each (bags and bank, with alts), vendor materials left out, and
-- the skill they'd give in the footer.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local PL, I = ns.Plan, ns.Integrations

io.write("[plan]\n")
local saved = { providers = ns.providers, order = ns.providerOrder, name = C_Item.GetItemNameByID, count = C_Item.GetItemCount,
	AL = _G.AtlasLoot, field = I.ItemField, npc = I.NpcRow, npcField = I.NpcField, profs = ns.Professions.PlayerProfessions,
	qdb = ns.QuestieData.DB, vendors = ns.db.vendorItems, easy = ns.db.easyMode, fac = _G.UnitFactionGroup }
local D = ns.Filters.DIFF
local NAMES = { [2840] = "Copper Bar", [2880] = "Weak Flux", [2589] = "Linen Cloth", [2835] = "Rough Stone",
	[2320] = "Coarse Thread", [2318] = "Light Leather", [2836] = "Coarse Stone" }
C_Item.GetItemNameByID = function(id) return NAMES[id] end
local BAGS, BANK = { [2840] = 20, [2589] = 4, [2836] = 30 }, { [2840] = 4 }
C_Item.GetItemCount = function(id, bank) return (BAGS[id] or 0) + (bank and (BANK[id] or 0) or 0) end
-- AtlasLoot's levels: { item, profession, learned, yellow, grey }
local DATA = { [2661] = { 2857, 2, 35, 75, 115 }, [2660] = { 2862, 2, 1, 15, 35 }, [2737] = { 2844, 2, 15, 55, 95 },
	[3116] = { 3470, 2, 25, 65, 105 }, [3320] = { 3473, 2, 30, 70, 110 }, [2665] = { 2863, 2, 75, 65, 80 },
	[3326] = { 3478, 2, 75, 75, 100 } }
_G.AtlasLoot = { Data = { Profession = { GetProfessionData = function(s) return DATA[s] end } } }
-- Questie: Coarse Thread sold by a vendor anyone can buy from; Light Leather only by one hostile to both sides
local FIELDS = { [2320] = { vendors = { 601 } }, [2318] = { vendors = { 602 } } }
I.ItemField = function(id, f) return FIELDS[id] and FIELDS[id][f] end
I.NpcRow = function(id) return { kind = "npc", key = id, npcID = id, name = "Vendor " .. id } end
I.NpcField = function(id, f) if f == "friendlyToFaction" then return id == 601 and "AH" or nil end end
ns.QuestieData.DB = function() return {} end
_G.UnitFactionGroup = function() return "Horde" end
ns.db.vendorItems = { [2880] = true } -- (a vendor's window showed Weak Flux on sale)
local rank, cap = 50, 75
ns.Professions.PlayerProfessions = function()
	return { { name = "Blacksmithing", rank = rank, maxRank = cap, skillLine = 164 } }, true
end

local function Rows(list) return function() local out = {} for i, r in ipairs(list) do local e = {} for k, v in pairs(r) do e[k] = v end e.key = e.key or i out[i] = e end return out end end
ns.providers, ns.providerOrder = {}, {}
local BS = "Blacksmithing"
ns:RegisterProvider("recipes", { label = "Recipe", aliases = { "recipe" }, collect = Rows({
	{ name = "Copper Chain Belt", recipeID = 2661, profName = BS, profID = 164, difficulty = D.orange, reagents = { { 2840, 6 } }, text = BS },
	{ name = "Rough Sharpening Stone", recipeID = 2660, profName = BS, profID = 164, difficulty = D.grey, reagents = { { 2835, 1 } }, text = BS },
	{ name = "Copper Mace", recipeID = 2737, profName = BS, profID = 164, difficulty = D.orange,
		reagents = { { 2840, 6 }, { 2880, 1 }, { 2589, 2 } }, text = BS },
	{ name = "Flux Trinket", recipeID = 3116, profName = BS, profID = 164, difficulty = D.orange, reagents = { { 2880, 2 } }, text = BS },
	{ name = "Forever Gizmo", recipeID = 900001, profName = BS, profID = 164, difficulty = D.yellow, reagents = { { 2840, 2 } }, text = BS },
	{ name = "Green Thing", recipeID = 900002, profName = BS, profID = 164, difficulty = D.green, reagents = { { 2840, 1 } }, text = BS },
	{ name = "Thread Bracers", recipeID = 3320, profName = BS, profID = 164, difficulty = D.orange,
		reagents = { { 2320, 3 }, { 2318, 2 } }, text = BS },
	-- (orange to AtlasLoot's levels at 50, grey in the game's window: the player's Coarse Sharpening Stone, 0.48.3)
	{ name = "Coarse Sharpening Stone", recipeID = 2665, profName = BS, profID = 164, difficulty = D.grey,
		reagents = { { 2836, 1 } }, text = BS },
}) })
ns:RegisterProvider("stored", { label = "Stored", aliases = { "stored" }, collect = Rows({ { name = "Copper Bar", itemID = 2840, total = 40 } }) })
ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = Rows({ { name = "Copper Bar", itemID = 2840 } }) })
PL.Forget()
ns.db.easyMode = false

do
	-- the chance of a point: orange 1, then down through yellow and green to grey (AtlasLoot's levels), else the window's colour
	local e = { recipeID = 2737 }
	check(PL.Chance(e, 50) == 1 and math.abs(PL.Chance(e, 75) - 0.5) < 1e-9 and PL.Chance(e, 95) == 0, "the game's chance by AtlasLoot's levels")
	check(select(2, PL.Chance(e, 60)) == "yellow" and select(2, PL.Chance(e, 80)) == "green", "yellow, then green")
	check(PL.Chance({ recipeID = 1, difficulty = D.yellow }) == 0.75, "no levels: the window's colour")
	-- AtlasLoot's levels aren't always Forever's: the window's colour wins when it's worse
	check(PL.Chance({ recipeID = 2665, difficulty = D.grey }, 50) == 0, "grey in the game's window, orange to AtlasLoot: grey")
	local c, col = PL.Chance({ recipeID = 3326, difficulty = D.yellow }, 50)
	check(c == 0.75 and col == "yellow", "yellow in the window, orange to AtlasLoot: yellow (" .. tostring(c) .. ", " .. tostring(col) .. ")")
	c, col = PL.Chance({ recipeID = 2737, difficulty = D.orange }, 60)
	check(math.abs(c - 0.875) < 1e-9 and col == "yellow", "AtlasLoot's worse colour still counts: " .. tostring(c) .. ", " .. tostring(col))
	check(PL.VendorSold(2880) and PL.VendorSold(2320) and not PL.VendorSold(2318) and not PL.VendorSold(2840),
		"sold: a vendor's window showed it, or a friendly Questie vendor; not one hostile to you")

	-- sort:plan: the recipes that give skill, by the crafts your bags and bank cover; vendor materials don't count
	local res = UI:Search("@recipe sort:plan")
	local names = {}
	for i, r in ipairs(res) do names[i] = r.name end
	check(table.concat(names, ",") == "Forever Gizmo,Copper Chain Belt,Copper Mace,Thread Bracers,Flux Trinket",
		"most crafts first; grey and green left out; none, then vendor materials only, last: " .. table.concat(names, ","))
	check(res[1].detail:find("12 crafts", 1, true) and res[1].detail:find("20 with alts", 1, true) and res[1].detail:find(BS, 1, true),
		"bags and bank, and with alts: " .. tostring(res[1].detail))
	check(res[3].planCrafts == 2 and res[3].planAlts == 2, "Copper Mace: two (the linen cloth; the flux is bought)")
	check(res[4].detail:find("missing Light Leather", 1, true), "none: what's missing (not the vendor's thread): " .. tostring(res[4].detail))
	check(res[5].detail:find("vendor materials only", 1, true), "vendor materials only: " .. tostring(res[5].detail))
	-- the footer: best chance first while the materials last (4 belts: 54; with alts 6 belts and 2 gizmos at 0.75: ~58)
	check(UI.answerNote == "Plan: about +4 Blacksmithing (50 to 54) from bags and bank, +8 with your alts' materials  ·  "
		.. "rough: some recipes' skill levels aren't known", "the skill they'd give (the Gizmo's levels unknown: rough): " .. tostring(UI.answerNote))
	-- (review, 0.48.6) a recipe with no levels known is counted a few points at most, not up to the cap
	local reach, atCap, rough = PL.Simulate({ { e = { recipeID = 900003, difficulty = D.orange }, mats = { { 2840, 1 } }, use = 1 } },
		{ [2840] = 100 }, 50, 75)
	check(math.abs(reach - (50 + PL.UNKNOWN_POINTS)) < 1e-9 and not atCap and rough,
		"no levels, materials for 100: about +" .. PL.UNKNOWN_POINTS .. ", rough: " .. tostring(reach))
	check(#UI:Search("sort:plan") == 5, "sort:plan alone plans your recipes")
	check(#UI:Search("@recipe sort:plan mace") == 1, "words narrow it")

	-- the cap stops it, and says so
	cap = 52
	UI:Search("@recipe sort:plan")
	check(UI.answerNote:find("+2 Blacksmithing (50 to 52)", 1, true) and UI.answerNote:find("52 is your cap", 1, true),
		"the cap: " .. tostring(UI.answerNote))
	cap = 75

	-- Simple mode: the question, and Alt+`
	local Q = PL.Question
	check(Q("blacksmithing plan") and Q("level blacksmithing") and Q("leveling plan for my blacksmith") and Q("profession plan")
		and Q("how do i level blacksmithing"), "questions")
	check(not Q("where should i level") and not Q("blacksmithing skillup") and not Q("plan") and not Q("level 20 sword")
		and not Q("@recipe sort:plan"), "not questions")
	check(ns.Easy.ToAdvanced("blacksmithing plan") == "@recipe blacksmithing sort:plan ", "Alt+`: " .. ns.Easy.ToAdvanced("blacksmithing plan"))
	-- (review, 0.53.6) a name of two words, whole: none of its words left to narrow by
	do
		local P = ns.Professions
		local real = P.PlayerProfessions
		P.PlayerProfessions = function() return { { name = "First Aid", skillLine = 129 }, { name = "Blacksmithing", skillLine = 164 } } end
		local q = Q("first aid plan")
		check(q and q.profs[1] == "First Aid" and #q.words == 0, "\"first aid plan\": First Aid's, nothing to narrow by: "
			.. tostring(q and q.words[1]))
		q = Q("level first aid bandage")
		check(q and q.profs[1] == "First Aid" and #q.words == 1 and q.words[1] == "bandage", "and the other words still narrow it")
		P.PlayerProfessions = real
	end
	-- (review, 0.53.6) Alt+` on a Simple line ending in ">> party" or "| sum value": kept as typed, after the words
	local adv = ns.Easy.ToAdvanced("hogger >> party")
	check(adv:find(" >> party$") and not adv:sub(1, -10):find(">>", 1, true), "Alt+`: \"hogger >> party\" -> " .. adv)
	adv = ns.Easy.ToAdvanced("cloth | sum value")
	check(adv:find(" | sum value$") and select(2, adv:gsub("sum value", "")) == 1, "Alt+`: \"cloth | sum value\" -> " .. adv)
	ns.db.easyMode = true
	res = UI:Search("level blacksmithing")
	check(#res == 5 and res[1].name == "Forever Gizmo" and UI.answerNote:find("+4 Blacksmithing", 1, true), "Simple mode asks it")
	res = UI:Search("blacksmithing plan copper")
	check(#res == 2, "its words narrow it: " .. #res)
	ns.db.easyMode = false

	-- a vendor's window: everything it sells in any number is kept as sold (MissingRecipes.lua's merchant read)
	local was = { n = _G.GetMerchantNumItems, id = _G.GetMerchantItemID, info = _G.GetMerchantItemInfo, mf = C_MerchantFrame,
		guid = _G.UnitGUID }
	_G.GetMerchantNumItems = function() return 2 end
	_G.GetMerchantItemID = function(i) return i == 1 and 5000 or 5001 end
	_G.C_MerchantFrame = nil
	_G.GetMerchantItemInfo = function(i) return "x", nil, 10, 1, i == 1 and -1 or 3 end
	_G.UnitGUID = function() return "Creature-0-0-0-0-4321-0000" end
	ns.MissingRecipes.ReadMerchant()
	check(ns.db.vendorItems[5000] and not ns.db.vendorItems[5001], "a vendor's unlimited goods are kept as sold, not limited ones")
	_G.GetMerchantNumItems, _G.GetMerchantItemID, _G.GetMerchantItemInfo, _G.C_MerchantFrame, _G.UnitGUID = was.n, was.id, was.info, was.mf, was.guid

	-- (0.49.2, review C8) a question's filler isn't a recipe's name; words that leave every recipe out say so (the recipes
	-- are read: not "open a profession's window"); "leveling plan" is every profession of yours
	local function Words(text) local q = Q(text) return q and table.concat(q.words, ",") end
	check(Words("whats the best way to level blacksmithing") == "" and Words("fastest way to level blacksmithing") == ""
		and Words("blacksmithing leveling guide") == "", "filler words aren't recipe names: "
		.. tostring(Words("whats the best way to level blacksmithing")) .. " / " .. tostring(Words("blacksmithing leveling guide")))
	res = UI:Search("whats the best way to level blacksmithing")
	check(#res == 5 and res[1].name == "Forever Gizmo", "whats the best way to level blacksmithing: the plan: " .. tostring(res[1] and res[1].name))
	local none = PL.Answer(Q("blacksmithing plan zzqx"))
	check(#none == 1 and none[1].name == PL.NO_MATCH and PL.NO_MATCH ~= PL.NONE, "words leaving every recipe out: "
		.. tostring(none[1] and none[1].name))
	local lp = Q("leveling plan")
	check(lp and #lp.profs == 0 and #lp.words == 0 and #UI:Search("leveling plan") == 5, "leveling plan: every profession of yours")
	check(not Q("level plan 20") and not Q("level") and not Q("plan"), "a plan word and a levelling word alone, nothing else")
end

ns.providers, ns.providerOrder = saved.providers, saved.order
ns:AliasesChanged()
C_Item.GetItemNameByID, C_Item.GetItemCount, _G.AtlasLoot = saved.name, saved.count, saved.AL
I.ItemField, I.NpcRow, I.NpcField, ns.Professions.PlayerProfessions = saved.field, saved.npc, saved.npcField, saved.profs
ns.QuestieData.DB, ns.db.vendorItems, ns.db.easyMode, _G.UnitFactionGroup = saved.qdb, saved.vendors, saved.easy, saved.fac
UI.lastScan, UI.lastOverview = nil, nil
PL.Forget()
