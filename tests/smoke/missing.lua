-- Recipes you don't have yet, and where to learn them (MissingRecipes.lua, 0.45.14): "blacksmithing recipes i'm
-- missing", "recipes i can learn now", @recipe is:unknown / is:learnable; what trainers' and vendors' windows showed
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local MR, P, I = ns.MissingRecipes, ns.Professions, ns.Integrations

io.write("[recipes to learn]\n")
do
	local was = { store = P.Store, profs = P.PlayerProfessions, AL = _G.AtlasLoot, field = I.ItemField, npcRow = I.NpcRow,
		known = _G.IsPlayerSpell, guid = _G.UnitGUID, uname = _G.UnitName, isTT = _G.IsTradeskillTrainer,
		nts = _G.GetNumTrainerServices, tsi = _G.GetTrainerServiceInfo, tsc = _G.GetTrainerServiceCost,
		tsr = _G.GetTrainerServiceSkillReq, nmi = _G.GetMerchantNumItems, mid = _G.GetMerchantItemID,
		mf = _G.C_MerchantFrame, inst = C_Item.GetItemInfoInstant, names = C_Item.GetItemNameByID,
		trainers = ns.db.recipeTrainers, vendors = ns.db.recipeVendors, easy = ns.db.easyMode }
	ns.db.recipeTrainers, ns.db.recipeVendors = nil, nil
	ns.db.easyMode = false; UI:EasyChanged()
	-- your professions: Blacksmithing 60 (its window read), Tailoring 1 (read), Alchemy 5 (not read since this came in)
	local store = {
		[164] = { name = "Blacksmithing", skillLine = 164, list = {}, unknown = {
			{ id = 92661, name = "Copper Chain Belt", icon = 1, item = 92857 },
			{ id = 96645, name = "Thorium Belt", icon = 2, item = 92406 },
			{ id = 93326, name = "Rough Grinding Stone", icon = 3, item = 93470 },
			{ id = 99001, name = "Anvil", icon = 4 } } },
		[197] = { name = "Tailoring", skillLine = 197, list = {}, unknown = { { id = 93915, name = "Brown Linen Shirt", icon = 5, item = 94344 } } },
		[171] = { name = "Alchemy", skillLine = 171, list = {} }, -- (read before 0.45.14: no list of what you don't know)
	}
	P.Store = function() return store end
	P.PlayerProfessions = function() return { { name = "Blacksmithing", rank = 60, skillLine = 164 },
		{ name = "Tailoring", rank = 1, skillLine = 197 }, { name = "Alchemy", rank = 5, skillLine = 171 },
		{ name = "Herbalism", rank = 50, skillLine = 182 } } end
	-- AtlasLoot: Copper Chain Belt is a trainer's (no plans), Thorium Belt has plans (12700) at 250; the shirt at 10
	local DATA = { [92661] = { 92857, 2, 35 }, [96645] = { 92406, 2, 250 }, [93915] = { 94344, 8, 10 } }
	_G.AtlasLoot = { Data = {
		Profession = { GetProfessionData = function(s) return DATA[s] end, GetCraftSpellForCreatedItem = function() return nil end },
		Recipe = { GetRecipeForSpell = function(s) return s == 96645 and 92700 or nil end,
			GetRecipeData = function(id) return id == 92700 and { 2, 250, 96645 } or nil end,
			IsRecipe = function(id) return id == 92700 end } } }
	C_Item.GetItemNameByID = function(id) return ({ [92700] = "Plans: Thorium Belt" })[id] or (was.names and was.names(id)) end
	-- Questie: who sells the plans
	I.ItemField = function(id, f) if id == 92700 and f == "vendors" then return { 503 } end return nil end
	I.NpcRow = function(id) return id == 503 and { kind = "npc", key = 503, name = "Plans Seller", detail = "Blacksmithing Supplies" } or nil end
	local learnedNow = {}
	_G.IsPlayerSpell = function(id) return learnedNow[id] == true end
	ns.providers.missing._dirty = true

	-- the question
	local Q = MR.Question
	local q = Q("blacksmithing recipes i'm missing")
	check(q and q.profs[1] == "Blacksmithing" and not q.learnable, "blacksmithing recipes i'm missing: Blacksmithing's, all of them")
	q = Q("recipes i can learn now")
	check(q and q.learnable and #q.profs == 0, "recipes i can learn now: those your skill allows")
	check(Q("recipes i dont know") and Q("missing recipes") and Q("tailoring patterns i don't have yet") and Q("learnable recipes").learnable,
		"other ways to ask")
	check(Q("blacksmithing recipes") == nil and Q("recipes that need copper bar") == nil and Q("@recipe is:unknown") == nil
		and Q("thorium belt") == nil, "other searches stay searches")

	-- the list: easiest first, the skill each needs and how it's learned
	local rows, note = MR.Answer(Q("blacksmithing recipes i'm missing"))
	local names = {}
	for _, e in ipairs(rows) do names[#names + 1] = e.name end
	check(table.concat(names, ",") == "Copper Chain Belt,Thorium Belt,Anvil,Rough Grinding Stone",
		"easiest first, the ones whose skill isn't known last: " .. table.concat(names, ","))
	local by = {}
	for _, e in ipairs(rows) do by[e.name] = e end
	check(by["Copper Chain Belt"].detail:find("^Blacksmithing 35  ·  Trainer"), "a trainer's, the skill it needs: " .. by["Copper Chain Belt"].detail)
	check(by["Thorium Belt"].detail:find("^Blacksmithing 250  ·  Vendor$"), "its plans are sold: " .. by["Thorium Belt"].detail)
	check(by["Rough Grinding Stone"].detail:find("How it's learned isn't known", 1, true), "nothing says how: said so")
	check(by["Copper Chain Belt"].canLearn and not by["Thorium Belt"].canLearn and by["Thorium Belt"].color, "what your 60 allows; the rest greyed")
	check(note:find("^Recipes you don't know yet: Blacksmithing") and not note:find("Alchemy", 1, true), "the note: " .. note)
	rows, note = MR.Answer(Q("recipes i'm missing"))
	check(#rows == 5 and note:find("open your Alchemy window once to list its recipes", 1, true) and not note:find("Herbalism", 1, true),
		"every profession's; a crafting one not read yet: open its window (gathering ones have none): " .. note)

	-- a trainer's window: what each recipe costs, the skill it needs (the game's own words)
	_G.IsTradeskillTrainer = function() return true end
	_G.UnitGUID = function(u) if u == "npc" then return "Creature-0-1-2-3-601-0000AB" end return was.guid and was.guid(u) end
	_G.UnitName = function(u) if u == "npc" then return "Grumnus" end return was.uname and was.uname(u) end
	local SERV = { { "Blacksmithing", "header" }, { "Copper Chain Belt", "available", 150, "Blacksmithing", 35 },
		{ "Anvil", "unavailable", 5000, "Blacksmithing", 100 } }
	_G.GetNumTrainerServices = function() return #SERV end
	_G.GetTrainerServiceInfo = function(i) return SERV[i][1], SERV[i][2] end
	_G.GetTrainerServiceCost = function(i) return SERV[i][3] end
	_G.GetTrainerServiceSkillReq = function(i) return SERV[i][4], SERV[i][5] end
	MR.events:GetScript("OnEvent")(MR.events, "TRAINER_SHOW"); FlushAll()
	check(MR.TrainerFor("Copper Chain Belt") and MR.TrainerFor("Copper Chain Belt").cost == 150 and MR.TrainerFor("anvil").rank == 100
		and MR.TrainerFor("Blacksmithing") == nil and MR.TrainerFor("Anvil").who == "Grumnus", "a trainer's window read: costs, skill, who (no headers)")
	-- a vendor's window: the plans are limited supply there
	_G.UnitGUID = function(u) if u == "npc" then return "Creature-0-1-2-3-503-0000AB" end return was.guid and was.guid(u) end
	_G.GetMerchantNumItems = function() return 2 end
	_G.GetMerchantItemID = function(i) return i == 1 and 92700 or 2901 end
	_G.C_MerchantFrame = { GetItemInfo = function(i) return { price = 5000, numAvailable = i == 1 and 1 or -1 } end }
	C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, id == 2901 and 7 or 9 end
	MR.events:GetScript("OnEvent")(MR.events, "MERCHANT_SHOW"); FlushAll()
	check(MR.Limited(92700, 503) == true and MR.Limited(2901, 503) == nil and MR.Limited(92700, 999) == nil,
		"a vendor's window read: the plans in limited supply there (only recipe items kept)")
	rows = MR.Answer(Q("blacksmithing recipes i'm missing"))
	by = {}
	for _, e in ipairs(rows) do by[e.name] = e end
	check(by["Copper Chain Belt"].detail:find("Trainer 1", 1, true) and by["Copper Chain Belt"].detail:find("50", 1, true),
		"the trainer's cost: " .. by["Copper Chain Belt"].detail)
	check(by["Anvil"].detail:find("^Blacksmithing 100  ·  Trainer"), "AtlasLoot doesn't list it, a trainer's window did: its skill and cost: " .. by["Anvil"].detail)
	check(by["Thorium Belt"].detail:find("Vendor (limited supply)", 1, true), "limited supply: " .. by["Thorium Belt"].detail)
	-- the tooltip says where each part is from
	local lines = {}
	local tip = { SetText = function(_, s) lines[#lines + 1] = s end, AddLine = function(_, s) lines[#lines + 1] = s end,
		AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. "=" .. b end }
	by["Copper Chain Belt"].tooltip(by["Copper Chain Belt"], tip)
	local all = table.concat(lines, "\n")
	check(all:find("Requires Blacksmithing 35 (you have 60)", 1, true) and all:find("(seen at Grumnus)", 1, true), "tooltip: skill, trainer and where seen: " .. all)
	lines = {}
	by["Thorium Belt"].tooltip(by["Thorium Belt"], tip)
	all = table.concat(lines, "\n")
	check(all:find("Its recipe: Plans: Thorium Belt  (AtlasLoot)", 1, true) and all:find("Sold by Plans Seller  ·  limited supply", 1, true),
		"tooltip: the plans, who sells them, limited supply: " .. all)

	-- only what your skill allows
	rows, note = MR.Answer(Q("recipes i can learn now"))
	names = {}
	for _, e in ipairs(rows) do names[#names + 1] = e.name end
	check(table.concat(names, ",") == "Copper Chain Belt" and note:find("^Recipes you can learn now") and note:find("1 whose skill isn't known left out", 1, true),
		"recipes i can learn now: " .. table.concat(names, ",") .. " / " .. note)
	rows, note = MR.Answer(Q("tailoring recipes i can learn now"))
	check(#rows == 0 and note:find("None you can learn yet: the next, Brown Linen Shirt, needs Tailoring 10", 1, true), "none yet: the next one: " .. note)

	-- Advanced: @recipe is:unknown / is:learnable; @recipe alone keeps to yours
	local res = UI:Search("@recipe is:unknown")
	local n = 0
	for _, e in ipairs(res) do if e.kind == "missing" then n = n + 1 end end
	check(n == 5, "@recipe is:unknown: the recipes you don't know: " .. n)
	res = UI:Search("@recipe is:learnable")
	check(#res == 1 and res[1].name == "Copper Chain Belt", "@recipe is:learnable: " .. tostring(res[1] and res[1].name))
	res = UI:Search("@recipe belt")
	for _, e in ipairs(res) do if e.kind == "missing" then n = -1 end end
	check(n ~= -1, "@recipe belt: only yours")
	check(ns.Easy.ToAdvanced("blacksmithing recipes i'm missing") == "@recipe is:unknown blacksmithing "
		and ns.Easy.ToAdvanced("recipes i can learn now") == "@recipe is:learnable ", "Alt+`: " .. ns.Easy.ToAdvanced("blacksmithing recipes i'm missing"))
	check(table.concat({ ns.Easy.Verbs(by["Thorium Belt"]) }, "/") == "where to learn/link in chat", "verbs")

	-- in Simple mode, the question answers; Enter on one is "where to learn <it>"
	ns.db.easyMode = true; UI:EasyChanged()
	res = UI:SearchText("blacksmithing recipes i'm missing")
	check(res[1] and res[1].name == "Copper Chain Belt" and UI.answerNote and UI.answerNote:find("^Recipes you don't know yet"), "Simple: the answer")
	UI:Open("blacksmithing recipes i'm missing"); FlushAll()
	res[1].activate(res[1])
	check(T.query() == "where to learn Copper Chain Belt", "Enter: where to learn it: " .. tostring(T.query()))
	UI:Hide(); FlushAll()
	ns.db.easyMode = false; UI:EasyChanged()

	-- the learn chain says the trainer's cost, and the plans' limited supply
	local Pp = ns.Pipes
	Pp.ClearSteps(); Pp.ClearCrafts()
	local chain = Pp.Search("Copper Chain Belt > learn")
	check(chain[1] and chain[1].name == "Taught by a Blacksmithing trainer" and chain[1].detail:find("^costs", 1) and chain[1].detail:find("(seen at Grumnus)", 1, true)
		and chain[1].detail:find("learn at Blacksmithing 35", 1, true), "where to learn: the cost a trainer's window showed: " .. tostring(chain[1] and chain[1].detail))
	chain = Pp.Search("Anvil > learn")
	check(chain[1] and chain[1].name == "Taught by a Blacksmithing trainer" and chain[1].detail:find("learn at Blacksmithing 100", 1, true),
		"a recipe AtlasLoot doesn't list, a trainer's window did: " .. tostring(chain[1] and chain[1].detail))
	chain = Pp.Search("Thorium Belt > learn")
	local seller
	for _, e in ipairs(chain) do if e.name == "Plans Seller" then seller = e end end
	check(seller and seller.detail:find("limited supply", 1, true), "the plans' vendor: limited supply: " .. tostring(seller and seller.detail))

	-- learned since the window was read: gone
	learnedNow[92661] = true
	ns.providers.missing._dirty = true
	rows = MR.Answer(Q("blacksmithing recipes i'm missing"))
	for _, e in ipairs(rows) do if e.name == "Copper Chain Belt" then n = -2 end end
	check(n ~= -2 and #rows == 3, "a recipe learned since: not listed")

	P.Store, P.PlayerProfessions, _G.AtlasLoot, I.ItemField, I.NpcRow = was.store, was.profs, was.AL, was.field, was.npcRow
	_G.IsPlayerSpell, _G.UnitGUID, _G.UnitName, _G.IsTradeskillTrainer = was.known, was.guid, was.uname, was.isTT
	_G.GetNumTrainerServices, _G.GetTrainerServiceInfo, _G.GetTrainerServiceCost, _G.GetTrainerServiceSkillReq = was.nts, was.tsi, was.tsc, was.tsr
	_G.GetMerchantNumItems, _G.GetMerchantItemID, _G.C_MerchantFrame = was.nmi, was.mid, was.mf
	C_Item.GetItemInfoInstant, C_Item.GetItemNameByID = was.inst, was.names
	ns.db.recipeTrainers, ns.db.recipeVendors = was.trainers, was.vendors
	ns.db.easyMode = was.easy; UI:EasyChanged()
	ns.providers.missing._dirty = true
	Pp.ClearSteps(); Pp.ClearCrafts()
end
