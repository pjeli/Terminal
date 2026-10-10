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
		trainers = ns.db.recipeTrainers, vendors = ns.db.recipeVendors, easy = ns.db.easyMode, npcField = I.NpcField,
		here = I.Here, dist = I.NpcDistance, fac = _G.UnitFactionGroup }
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
	-- (sellers: only those friendly to you, 0.45.16; this one sells to everyone)
	I.NpcField = function(id, f) if f == "friendlyToFaction" then return "AH" end end
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
	check(#rows == 1 and rows[1].noActivate and rows[1].name:find("None you can learn yet: the next, Brown Linen Shirt, needs Tailoring 10", 1, true)
		and note == "Recipes you can learn now: Tailoring", "none yet: a line names the next one: " .. tostring(rows[1] and rows[1].name) .. " / " .. note)

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
	-- (0.45.16, the player's call) not a kind: no @missing; @recipe's filter reaches it, and it's written that way
	check(ns:ResolveProvider("missing") == nil and ns:ResolveProvider("miss") == nil and ns:ResolveProvider("tolearn") == nil
		and ns:ResolveProvider("recipe to learn") == nil, "no @missing (nor its old names)")
	check(UI:ResultText(by["Thorium Belt"]) == "@recipe is:unknown Thorium Belt", "Shift+Right writes @recipe: " .. tostring(UI:ResultText(by["Thorium Belt"])))
	local kinds = table.concat(ns.commands.kinds.run() or {}, "\n")
	check(not kinds:find("Recipe to learn", 1, true), ".kinds doesn't list it")
	-- (0.45.22, the player: .mem still said @missing) named by how a search reaches it, wherever a list is named
	local mem = table.concat(ns.commands.mem.run() or {}, "\n")
	check(not mem:find("@missing", 1, true) and mem:find("@recipe is:unknown (Recipe to learn)", 1, true),
		".mem names it @recipe is:unknown, never @missing")
	check(ns:KindName(ns.providers.missing) == "@recipe is:unknown" and ns:KindName(ns.providers.items) == "@item"
		and ns:KindName(ns.providers.recipes) == "@recipe", "ns:KindName: a list's first alias, a list no @ names by its filter")
	check(ns.Easy.ToAdvanced("anvil", nil, { missing = true }):find("@missing", 1, true) == nil, "(Alt+` never writes @missing)")
	UI:Open(""); FlushAll()
	UI:SetQuery("@missi", 6); FlushAll()
	local done = UI:Completion()
	check(not (done and done:find("missing", 1, true)), "Tab doesn't complete @missi: " .. tostring(done))
	UI:Hide(); FlushAll()
	-- (0.45.17) Shift+Right's "write it" is a step: Shift+Left goes back to what was typed
	UI:Open("@recipe is:unknown"); FlushAll()
	for i, e in ipairs(UI.Results()) do if e.name == "Thorium Belt" then UI.sel = i end end
	local s1 = _G.IsShiftKeyDown
	_G.IsShiftKeyDown = function() return true end
	T.key("RIGHT"); FlushAll()
	local written = T.query()
	T.key("LEFT"); FlushAll()
	_G.IsShiftKeyDown = s1
	UI.frame.scripts.OnKeyUp(UI.frame, "LEFT")
	check(written == "@recipe is:unknown Thorium Belt " and T.query() == "@recipe is:unknown", "Shift+Right writes it, Shift+Left takes it back: " .. tostring(written) .. " / " .. tostring(T.query()))
	UI:Hide(); FlushAll()
	-- sellers: only those friendly to you (a Horde character: an Alliance-only seller isn't one); nearest first, how far
	I.NpcField = function(id, f) if f == "friendlyToFaction" then return "A" end end
	_G.UnitFactionGroup = function() return "Horde" end
	ns.providers.missing._dirty = true
	local hostile = MR.Answer(Q("blacksmithing recipes i'm missing"))
	local tb
	for _, e in ipairs(hostile) do if e.name == "Thorium Belt" then tb = e end end
	check(tb and not tb.detail:find("Vendor", 1, true), "its only seller won't sell to you: no vendor said: " .. tostring(tb and tb.detail))
	I.NpcField = function(id, f) if f == "friendlyToFaction" then return "AH" end end
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	I.NpcDistance = function(id) return id == 503 and 250 or nil end
	ns.providers.missing._dirty = true
	for _, e in ipairs(MR.Answer(Q("blacksmithing recipes i'm missing"))) do if e.name == "Thorium Belt" then tb = e end end
	lines = {}
	tb.tooltip(tb, tip)
	check(table.concat(lines, "\n"):find("Sold by Plans Seller  ·  250 yd", 1, true), "tooltip: the seller, how far: " .. table.concat(lines, " / "))
	-- (0.45.15) the footer names a profession whose window would list more; none with is:learnable: a line says why
	res = UI:Search("@recipe is:unknown")
	check(UI.missingNote and UI.missingNote:find("open your Alchemy window once", 1, true), "footer: open the window not read yet: " .. tostring(UI.missingNote))
	UI:Search("@recipe is:unknown blacksmithing")
	check(UI.missingNote == nil, "footer: not when the profession asked about was read")
	res = UI:Search("@recipe is:learnable tailoring")
	check(#res == 1 and res[1].noActivate and res[1].name:find("the next, Brown Linen Shirt, needs Tailoring 10", 1, true),
		"@recipe is:learnable, none yet: a line names the next: " .. tostring(res[1] and res[1].name))
	res = UI:Search("@recipe is:learnable anvil")
	check(#res == 1 and res[1].name:find("the next, Anvil, needs Blacksmithing 100", 1, true), "the next of those the words name: " .. tostring(res[1] and res[1].name))
	-- is:learnable with no @kind: the list is searched along with the others
	res = UI:Search("is:learnable")
	check(res[1] and res[1].name == "Copper Chain Belt", "is:learnable alone: " .. tostring(res[1] and res[1].name))
	-- the file not loaded (an update added it; a /reload doesn't load new files): a line says to restart
	local mp = ns.providers.missing
	ns.providers.missing = nil
	res = UI:Search("@recipe is:unknown")
	ns.providers.missing = mp
	check(res[1] and res[1].noActivate and res[1].name:find("^Restart the game"), "not loaded: restart: " .. tostring(res[1] and res[1].name))

	-- in Simple mode, the question answers; Enter on one is "where to learn <it>"
	ns.db.easyMode = true; UI:EasyChanged()
	res = UI:SearchText("blacksmithing recipes i'm missing")
	check(res[1] and res[1].name == "Copper Chain Belt" and UI.answerNote and UI.answerNote:find("^Recipes you don't know yet"), "Simple: the answer")
	UI:Open("blacksmithing recipes i'm missing"); FlushAll()
	res[1].activate(res[1])
	check(T.query() == "where to learn Copper Chain Belt", "Enter: where to learn it: " .. tostring(T.query()))
	UI:Hide(); FlushAll()
	-- (0.45.16-17, the player) back from a recipe's sources: Shift+Left (wherever the cursor is) goes back to the list
	-- while that search is untouched, the recipe picked selected again; the footer says so
	local F = UI.frame
	local function ShiftLeft()
		local s0 = _G.IsShiftKeyDown
		_G.IsShiftKeyDown = function() return true end
		T.key("LEFT")
		_G.IsShiftKeyDown = s0
	end
	UI:Open("blacksmithing recipes i'm missing"); FlushAll()
	local picked
	for i, e in ipairs(UI.Results()) do if e.name == "Thorium Belt" then picked, UI.sel = e, i end end
	check(picked and UI.sel > 1, "a recipe further down the list: " .. tostring(UI.sel))
	picked.activate(picked); FlushAll()
	check(T.query() == "where to learn " .. picked.name and UI:WalkTop() ~= nil, "Enter: its sources: " .. tostring(T.query()))
	local th = ns.Theme.Get()
	local widthWas = th.width
	th.width = 1600 -- (room for every hint: the mock's text widths count colour codes)
	UI:SetStatus()
	th.width = widthWas
	check((UI.hints:GetText() or ""):find("Shift+Left|r back", 1, true), "the footer: Shift+Left back: " .. tostring(UI.hints:GetText()))
	UI:SetStatus()
	T.key("HOME"); T.key("RIGHT"); FlushAll() -- (the cursor moved: still the same search)
	ShiftLeft(); FlushAll()
	check(T.query() == "blacksmithing recipes i'm missing" and UI.Results()[UI.sel] == picked,
		"Shift+Left: back to the list, the recipe picked selected: " .. tostring(T.query()) .. " / " .. tostring(UI.Results()[UI.sel] and UI.Results()[UI.sel].name))
	ShiftLeft(); FlushAll()
	check(T.query() == "blacksmithing recipes i'm missing" and UI:SelRange() == nil, "the key still held (the game's repeats): nothing more")
	F.scripts.OnKeyUp(F, "LEFT")
	ShiftLeft(); FlushAll()
	check(T.query() == "blacksmithing recipes i'm missing" and UI:SelRange() ~= nil, "let go, nothing to go back to: Shift+Left selects again")
	T.key("BACKSPACE"); FlushAll()
	check(T.query() == "blacksmithing recipes i'm missin", "Backspace deletes (it never goes back): " .. tostring(T.query()))
	-- a Shift+Left that went back, held as the terminal closed: the next open's first one counts
	UI.backHeld = GetTime()
	UI:Hide(); FlushAll(); UI:Open(""); FlushAll()
	check(UI.backHeld == nil, "opening forgets a Shift+Left still held")
	-- typed on since: no going back
	UI:SetQuery("blacksmithing recipes i'm missing"); FlushAll()
	picked = UI.Results()[1]
	picked.activate(picked); FlushAll()
	T.typeText("x"); T.key("BACKSPACE"); FlushAll()
	ShiftLeft(); FlushAll()
	check(T.query() == "where to learn " .. picked.name and UI:SelRange() ~= nil, "typed on: the trail is gone, Shift+Left selects: " .. tostring(T.query()))
	F.scripts.OnKeyUp(F, "LEFT")
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

	-- (0.45.15, the player's "learnable and unknown showing 0 results") no window read since 0.45.14: a line says which to open
	local read = { [164] = { name = "Blacksmithing", skillLine = 164, list = {} }, [197] = { name = "Tailoring", skillLine = 197, list = {} },
		[171] = { name = "Alchemy", skillLine = 171, list = {} } }
	P.Store = function() return read end
	ns.providers.missing._dirty = true
	res = UI:Search("@recipe is:unknown")
	check(#res == 1 and res[1].noActivate and res[1].name == "Open your Blacksmithing, Tailoring and Alchemy windows once: Terminal lists the recipes you don't know from them",
		"@recipe is:unknown, no window read: open them: " .. tostring(res[1] and res[1].name))
	res = UI:Search("@recipe is:learnable")
	check(#res == 1 and res[1].name:find("^Open your"), "@recipe is:learnable, no window read: open them")
	rows, note = MR.Answer(Q("blacksmithing recipes i'm missing"))
	check(#rows == 1 and rows[1].name == "Open your Blacksmithing window once: Terminal lists the recipes you don't know from it"
		and note == "Recipes you don't know yet: Blacksmithing", "the question, no window read: " .. tostring(rows[1] and rows[1].name) .. " / " .. note)
	-- every window read, nothing you don't know
	for _, pd in pairs(read) do pd.unknown = {} end
	ns.providers.missing._dirty = true
	rows = MR.Answer(Q("recipes i'm missing"))
	check(#rows == 1 and rows[1].name == "You know every recipe your profession windows listed", "you know them all: " .. tostring(rows[1] and rows[1].name))
	-- no crafting profession
	P.PlayerProfessions = function() return { { name = "Herbalism", rank = 50, skillLine = 182 } } end
	ns.providers.missing._dirty = true
	rows = MR.Answer(Q("recipes i'm missing"))
	check(#rows == 1 and rows[1].name == "None of your professions has recipes to learn", "no crafting profession: " .. tostring(rows[1] and rows[1].name))

	P.Store, P.PlayerProfessions, _G.AtlasLoot, I.ItemField, I.NpcRow = was.store, was.profs, was.AL, was.field, was.npcRow
	I.NpcField, I.Here, I.NpcDistance, _G.UnitFactionGroup = was.npcField, was.here, was.dist, was.fac
	_G.IsPlayerSpell, _G.UnitGUID, _G.UnitName, _G.IsTradeskillTrainer = was.known, was.guid, was.uname, was.isTT
	_G.GetNumTrainerServices, _G.GetTrainerServiceInfo, _G.GetTrainerServiceCost, _G.GetTrainerServiceSkillReq = was.nts, was.tsi, was.tsc, was.tsr
	_G.GetMerchantNumItems, _G.GetMerchantItemID, _G.C_MerchantFrame = was.nmi, was.mid, was.mf
	C_Item.GetItemInfoInstant, C_Item.GetItemNameByID = was.inst, was.names
	ns.db.recipeTrainers, ns.db.recipeVendors = was.trainers, was.vendors
	ns.db.easyMode = was.easy; UI:EasyChanged()
	ns.providers.missing._dirty = true
	Pp.ClearSteps(); Pp.ClearCrafts()
end
