-- The providers/core clean-up (0.44.8 refactor, package C): what moved keeps its contract (ns.Bags in Bags.lua,
-- ns.Guarded in Debug.lua), and the speed-ups give the same results.
local T = ...
local ns, UI, check, Obj, FlushAll = T.ns, T.UI, T.check, T.Obj, T.FlushAll

io.write("[providers parts: guarded calls]\n")
do
	local D = ns.Debug
	check(type(ns.Guarded) == "function" and ns.Professions.Guarded == ns.Guarded, "ns.Guarded (Debug.lua) is Professions.Guarded too")
	local save = { blocked = ns.db.blockedCalls, count = D.count, events = #D.events, print = ns.Print }
	ns.db.blockedCalls = {}
	ns.Print = function() end
	local calls = 0
	check(ns.Guarded("PartsFine", function() calls = calls + 1 end) == true and calls == 1, "a call that goes through: true")
	local blocked = ns.Guarded("PartsBlocked", function()
		calls = calls + 1
		D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", "Terminal", "PartsBlocked()")
	end)
	check(blocked == false and calls == 2 and ns.db.blockedCalls.PartsBlocked == true, "blocked by the game: false, and remembered")
	check(ns.Professions.Guarded("PartsBlocked", function() calls = calls + 1 end) == false and calls == 2,
		"never tried again, asked through either name")
	check(ns.Guarded("PartsNoFunction", nil) == false, "nothing to call: false")
	for i = #D.events, save.events + 1, -1 do D.events[i] = nil end
	ns.db.blockedCalls, D.count, ns.Print = save.blocked, save.count, save.print
end

io.write("[providers parts: shared helpers]\n")
do
	check(ns.Never() == false and ns.ChatBoxNeverOpen == ns.Never, "ns.Never (Core.lua) is also the chat box spec's isOpen")
	local p = ns.providers.lootlog
	local saveLog = ns.db.lootLog
	ns.db.lootLog = { { link = "|cff1eff00|Hitem:2589::::::::|h[Partsy Cloth]|h|r", id = 2589, who = "Bob", t = 1, src = "loot" } }
	p._dirty = true
	local row = ns:GetEntries(p)[1]
	check(row and row.secondaryIsOpen == ns.Never, "the loot log's rows share ns.Never")
	ns.db.lootLog = saveLog
	p._dirty = true
	-- the profession window's recipe list scrolled through ns.ScrollBoxTo: its nodes' data, or the data's recipeInfo
	local asked = {}
	local function window(nodes)
		return { CraftingPage = { RecipeList = { ScrollBox = { ScrollToElementDataByPredicate = function(_, pred)
			for _, n in ipairs(nodes) do if pred(n) then asked[#asked + 1] = n end end
		end } } } }
	end
	local a = { GetData = function() return { recipeInfo = { recipeID = 11 } } end }
	local b = { GetData = function() return { recipeID = 12 } end }
	local c = { GetData = function() return { recipeInfo = { recipeID = 13 } } end }
	local Scroll = ns.Professions.ScrollToRecipe
	check(Scroll(window({ a, b, c }), 12) == true and asked[1] == b and #asked == 1, "the recipe list: scrolled to the node whose data is the recipe")
	asked = {}
	check(Scroll(window({ a, b, c }), 13) == true and asked[1] == c and #asked == 1, "or whose data's recipeInfo is")
	check(Scroll({}, 11) == false and Scroll({ CraftingPage = { RecipeList = {} } }, 11) == false, "no list: false")
	local bad = { CraftingPage = { RecipeList = { ScrollBox = { ScrollToElementDataByPredicate = function() error("x") end } } } }
	check(Scroll(bad, 11) == false, "a list that errors: false")
end

io.write("[providers parts: frame names]\n")
do
	local named, unnamed, failing, numbered = Obj("Frame"), Obj("Frame"), Obj("Frame"), Obj("Frame")
	named.GetName = function() return "PartsFrame" end
	unnamed.GetName = function() return nil end
	failing.GetName = function() error("forbidden") end
	numbered.GetName = function() return 7 end
	local FN = ns.FrameName
	check(FN(named) == "PartsFrame" and FN(unnamed) == nil and FN(failing) == nil and FN(numbered) == nil,
		"ns.FrameName: a string name, else nil")
	check(FN(nil) == nil and FN({}) == nil and FN(3) == nil and FN("x") == nil and FN(true) == nil, "ns.FrameName: never an error")
	-- (a walk over UIParent's children asks every child: no closure made per call, so nothing is left to collect)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 20000 do FN(named) end
	local grew = collectgarbage("count") - before
	collectgarbage("restart")
	check(grew < 64, ("ns.FrameName makes nothing per call: %.0f KB over 20000 calls"):format(grew))
end

io.write("[providers parts: addons]\n")
do
	local base, saveName = _G.C_AddOns, ns.CharacterName
	local me = saveName()
	local asked, states = 0, {}
	ns.CharacterName = function() asked = asked + 1; return saveName() end
	_G.C_AddOns = setmetatable({
		GetNumAddOns = function() return 3 end,
		GetAddOnInfo = function(i) local n = ({ "PartsA", "PartsB", "PartsC" })[i]; return n, "Parts " .. n, "notes" end,
		IsAddOnLoaded = function(n) return n ~= "PartsB" end,
		GetAddOnEnableState = function(n, char) states[#states + 1] = tostring(char); return n == "PartsC" and 0 or 2 end,
	}, { __index = base })
	local p = ns.providers.addons
	p._dirty = true
	local a = {}
	for _, e in ipairs(ns:GetEntries(p)) do a[e.key] = e end
	check(asked == 1, "the addon list works out this character's name once, not once per addon: " .. asked)
	check(#states == 3 and states[1] == tostring(me) and states[2] == states[1] and states[3] == states[1],
		"every addon's state asked for this character: " .. table.concat(states, ", "))
	check(a.PartsA and a.PartsA.enabled == true and a.PartsA.detail == "enabled"
		and a.PartsB and a.PartsB.enabled == true and a.PartsB.detail == "enabled (.reload to apply)"
		and a.PartsC and a.PartsC.enabled == false and a.PartsC.detail == "disabled (.reload to apply)",
		"each addon's state as before: " .. tostring(a.PartsB and a.PartsB.detail) .. " / " .. tostring(a.PartsC and a.PartsC.detail))
	_G.C_AddOns, ns.CharacterName = base, saveName
	p._dirty = true
end

io.write("[providers parts: other classes' talent rows kept]\n")
do
	local TL, P = ns.Talents, ns.providers.talents
	local save = { cache = ns.db.talentCache, uc = _G.UnitClass, rcc = _G.RAID_CLASS_COLORS, tex = C_Spell.GetSpellTexture,
		tried = TL.triedOthers, easy = ns.db.easyMode }
	ns.db.easyMode = false
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	_G.RAID_CLASS_COLORS = { MAGE = { colorStr = "ff3fc7eb" } }
	local okB, _, build = pcall(GetBuildInfo) -- (the saved copy's key, as Talents.lua makes it)
	local function saved()
		return { key = TL.CACHE_FORMAT .. ":" .. tostring(okB and build or "?"), names = { MAGE = "Mage" },
			classes = { MAGE = { { 2001, "Ice Barrier", 52001, "Frost", 2, 1, 135988 }, { 2002, "Partsy Frostbolt", 52002, "Frost", 2, 5 } } } }
	end
	ns.db.talentCache, TL.triedOthers = saved(), nil
	local texture
	C_Spell.GetSpellTexture = function(id) if id == 52002 then return texture end return 1 end
	local function others()
		P._dirty = true
		local by = {}
		for _, e in ipairs(ns:GetEntries(P)) do if e.other then by[e.name] = e end end
		return by
	end
	local a = others()
	local ib, fb = a["Ice Barrier"], a["Partsy Frostbolt"]
	check(ib and fb and ib.detail == "|cff3fc7ebMage|r  ·  Frost  ·  1 rank" and fb.detail == "|cff3fc7ebMage|r  ·  Frost  ·  5 ranks"
		and ib.icon == 135988 and fb.icon == nil and ib.key == "MAGE:2001", "another class's talent rows: " .. tostring(ib and ib.detail))
	texture = 4242
	local b = others()
	check(b["Ice Barrier"] == ib and b["Partsy Frostbolt"] == fb, "a rebuild uses the same rows again, not new tables")
	check(fb.icon == 4242 and ib.icon == 135988 and ib.detail == "|cff3fc7ebMage|r  ·  Frost  ·  1 rank"
		and rawget(ib, "_ltext") == "frost mage talent" and ib.className == "Mage" and ib._rank == TL.OTHER_RANK,
		"...the same fields, and an icon the saved copy lacks asked again as a new row would: " .. tostring(fb.icon))
	local res = UI:Search("@talent class:mage")
	check(#res == 2 and res[1].classFile == "MAGE" and res[2].classFile == "MAGE", "class:mage still lists them: " .. #res)
	res = UI:Search("@talent partsy frostbolt")
	check(res[1] and res[1].name == "Partsy Frostbolt", "and finds one by name")
	-- something a row shows changed: made again
	_G.RAID_CLASS_COLORS = { MAGE = { colorStr = "ff0000ff" } }
	local c = others()
	local ib2 = c["Ice Barrier"]
	check(ib2 and ib2 ~= ib and ib2.detail == "|cff0000ffMage|r  ·  Frost  ·  1 rank", "the class's colour changed: its rows made again")
	ns.db.talentCache = saved() -- (another saved copy: read again)
	local d = others()
	check(d["Ice Barrier"] and d["Ice Barrier"] ~= ib2 and d["Ice Barrier"].detail == ib2.detail, "a new saved copy: made again")
	ns.db.talentCache, _G.UnitClass, _G.RAID_CLASS_COLORS, C_Spell.GetSpellTexture = save.cache, save.uc, save.rcc, save.tex
	TL.triedOthers, ns.db.easyMode = save.tried, save.easy
	P._dirty = true
end

io.write("[providers parts: bags]\n")
do
	local B = ns.Bags
	local all = true
	for _, k in ipairs({ "Bagnon", "Baganator", "Active", "Open", "FindButton", "Locations", "ShowItem", "Show" }) do
		all = all and type(B[k]) == "function"
	end
	check(all, "ns.Bags (Bags.lua) has every function it had, and Show")
	local p = ns.providers.items
	p._dirty = true
	local row
	for _, e in ipairs(ns:GetEntries(p)) do if e.locs then row = e break end end
	check(row and row.activate == B.Show, "a bag item's Enter is ns.Bags.Show")
end

io.write("[providers parts: a camp object knows its window (0.49.2 review)]\n")
do
	-- Fish Bowl is made in the Bait and Tackle window (a trade spell's: kept as "spell:Bait and Tackle"), whose own info
	-- says id 0 on this client: only its names tell it's showing
	local P = ns.Professions
	local was = { profs = P.PlayerProfessions, pf = _G.ProfessionsFrame, ts = _G.C_TradeSkillUI, last = P.lastSpell,
		sel = P.SelectRecipe, count = C_Item.GetItemCount, recipes = ns.db.recipes }
	ns.db.recipes = { [P.CharKey()] = {
		["spell:Bait and Tackle"] = { name = "Bait and Tackle", spell = "Bait and Tackle", parent = "Fishing", list = {
			{ id = 5001, name = "Fish Bowl", icon = 1, learned = true, reagents = {}, item = 7001 } } } } }
	P.PlayerProfessions = function() return { { name = "Fishing", rank = 50, maxRank = 75, skillLine = 356 } } end
	_G.ProfessionsFrame = Obj("Frame"); ProfessionsFrame.shown = true
	_G.C_TradeSkillUI = setmetatable({ GetChildProfessionInfo = function() return nil end,
		GetBaseProfessionInfo = function() return { professionID = 0, professionName = "Bait and Tackle" } end }, { __index = was.ts })
	P.SelectRecipe = function() end
	C_Item.GetItemCount = function() return 0 end -- (none in your bags: Shift+Enter makes one)
	ns.providers.camp._dirty = true
	local camp
	for _, e in ipairs(ns:GetEntries(ns.providers.camp)) do if e.name == "Fish Bowl" then camp = e end end
	check(camp and camp.secure and camp.secure.spell == "Bait and Tackle", "Fish Bowl (@camp) opens with Bait and Tackle")
	check(camp and camp.isOpen(camp) == true,
		"its window showing (its info says id 0): open, so Enter presses nothing (the /cast would shut it), as its recipe row")
	local v = camp and UI.SecureView(camp, true)
	local r = v and ns.Secure.Resolve(v.secure, v)
	check(r and r.macro == "/run C_TradeSkillUI.CraftRecipe(5001,1)",
		"Shift+Enter with its window open: just made (no /cast toggling the window each press): " .. tostring(r and r.macro))
	P.lastSpell = nil
	if v then v.after(v) end
	check(P.lastSpell and P.lastSpell.name == "Bait and Tackle" and P.lastSpell.parent == "Fishing",
		"the after-step says which spell's window it is (for indexing it)")
	ProfessionsFrame.shown = false
	v = camp and UI.SecureView(camp, true)
	r = v and ns.Secure.Resolve(v.secure, v)
	check(camp and camp.isOpen(camp) == false and r and r.macro == "/cast Bait and Tackle\n/run C_TradeSkillUI.CraftRecipe(5001,1)",
		"the window closed: Enter casts it, Shift+Enter opens it and makes it")
	ns.db.recipes, P.PlayerProfessions, _G.ProfessionsFrame, _G.C_TradeSkillUI = was.recipes, was.profs, was.pf, was.ts
	P.lastSpell, P.SelectRecipe, C_Item.GetItemCount = was.last, was.sel, was.count
	ns.providers.camp._dirty, ns.providers.recipes._dirty = true, true
end

-- a profession window mocked for P.Snapshot: `win` gives the window's own info, `ids` its recipes per profession id,
-- `info` each recipe's
local function MockWindow(win, ids, info, schematic)
	return {
		GetBaseProfessionInfo = function() return win() end,
		GetAllRecipeIDs = function() return ids[win().professionID] or {} end,
		GetRecipeInfo = function(id) return info(id) end,
		GetRecipeSchematic = schematic or function() return { reagentSlotSchematics = {} } end,
	}
end

io.write("[providers parts: the spell a window was opened with (0.49.2 review)]\n")
do
	local P = ns.Professions
	local was = { profs = P.PlayerProfessions, pf = _G.ProfessionsFrame, ts = _G.C_TradeSkillUI, last = P.lastSpell,
		cast = P.lastCast, read = P.lastRead, sel = P.SelectRecipe, recipes = ns.db.recipes, print = ns.Print }
	local store = { ["spell:Smelting"] = { name = "Smelting", spell = "Smelting", parent = "Mining", list = {
		{ id = 2657, name = "Smelt Copper", icon = 1, learned = true, reagents = {} } } } }
	ns.db.recipes = { [P.CharKey()] = store }
	P.PlayerProfessions = function() return { { name = "Mining", rank = 50, maxRank = 75, skillLine = 186 },
		{ name = "Blacksmithing", rank = 40, maxRank = 75, skillLine = 164 } } end
	_G.ProfessionsFrame = Obj("Frame"); ProfessionsFrame.shown = true
	local window = { professionID = 186, professionName = "Mining" } -- (Smelting's window: its info names Mining)
	local names = { [2657] = "Smelt Copper", [2662] = "Copper Chain Pants" }
	_G.C_TradeSkillUI = MockWindow(function() return window end, { [186] = { 2657 }, [164] = { 2662 } },
		function(id) return names[id] and { name = names[id], icon = 1, learned = true } end)
	P.SelectRecipe, ns.Print = function() end, function() end
	P.lastSpell, P.lastCast = nil, nil
	ns.providers.recipes._dirty = true
	local smelt
	for _, e in ipairs(ns:GetEntries(ns.providers.recipes)) do if e.name == "Smelt Copper" then smelt = e end end
	check(smelt and smelt.isOpen(smelt), "Smelting's window showing: Enter on Smelt Copper presses nothing, it only points")
	if smelt then smelt.after(smelt) end -- (that Enter's after-step)
	-- Blacksmithing opened a moment later: what its window lists is Blacksmithing's, not Smelting's
	window = { professionID = 164, professionName = "Blacksmithing" }
	P.Snapshot(); FlushAll()
	check(store[164] and store[164].list[1] and store[164].list[1].name == "Copper Chain Pants" and not store[164].spell
		and store["spell:Smelting"] and store["spell:Smelting"].list[1].name == "Smelt Copper",
		"Blacksmithing opened right after Enter on a Smelting recipe: indexed as Blacksmithing, Smelting's list kept")
	-- Smelting's own window read again just after: still Smelting's (under Mining)
	if smelt then smelt.after(smelt) end
	window = { professionID = 186, professionName = "Mining" }
	P.Snapshot(); FlushAll()
	check(store["spell:Smelting"] and store["spell:Smelting"].parent == "Mining" and store["spell:Smelting"].list[1].name == "Smelt Copper"
		and not store[186], "its own window read again: kept as Smelting's")
	ns.db.recipes, P.PlayerProfessions, _G.ProfessionsFrame, _G.C_TradeSkillUI = was.recipes, was.profs, was.pf, was.ts
	P.lastSpell, P.lastCast, P.lastRead, P.SelectRecipe, ns.Print = was.last, was.cast, was.read, was.sel, was.print
	ns.providers.recipes._dirty, ns.providers.camp._dirty = true, true
end

io.write("[providers parts: a list update reads the window only when it changed (0.49.2 review)]\n")
do
	local P = ns.Professions
	local was = { profs = P.PlayerProfessions, pf = _G.ProfessionsFrame, ts = _G.C_TradeSkillUI, last = P.lastSpell,
		cast = P.lastCast, read = P.lastRead, recipes = ns.db.recipes, print = ns.Print }
	local key = P.CharKey()
	ns.db.recipes = { [key] = {} }
	local rank = 50
	P.PlayerProfessions = function() return { { name = "Blacksmithing", rank = rank, maxRank = 75, skillLine = 164 } } end
	_G.ProfessionsFrame = Obj("Frame"); ProfessionsFrame.shown = true
	local reads, ids = 0, { 2662, 2663 }
	_G.C_TradeSkillUI = MockWindow(function() return { professionID = 164, professionName = "Blacksmithing" } end, { [164] = ids },
		function(id)
			reads = reads + 1
			return { name = "Recipe " .. id, icon = 1, learned = true, relativeDifficulty = rank < 60 and 0 or 1 }
		end)
	ns.Print = function() end
	P.lastSpell, P.lastCast, P.lastRead = nil, nil, nil
	local ev = P.events
	local function fire(event) ev.scripts.OnEvent(ev, event); FlushAll() end
	fire("TRADE_SKILL_SHOW")
	check(reads == 2, "the window opened: every recipe read: " .. reads)
	reads = 0
	fire("TRADE_SKILL_LIST_UPDATE")
	check(reads == 0, "a list update with nothing it lists changed (a bag change while it's open): not read again: " .. reads)
	rank = 61
	fire("TRADE_SKILL_LIST_UPDATE")
	local bs = ns.db.recipes[key][164]
	check(reads == 2 and bs and bs.list[1].diff == 1, "a skill-up: read again, the colours with it: " .. reads)
	reads = 0
	ids[3] = 2664
	fire("TRADE_SKILL_LIST_UPDATE")
	check(reads == 3, "another recipe listed: read again: " .. reads)
	reads = 0
	fire("NEW_RECIPE_LEARNED")
	check(reads == 3, "a recipe learned: always read again: " .. reads)
	reads = 0
	fire("SKILL_LINES_CHANGED"); fire("TRADE_SKILL_LIST_UPDATE")
	check(reads == 3, "after a skill change, the next list update reads it again: " .. reads)
	-- (0.50.7, review) the skills list's own read fired it (it opens folded groups): not a skill change
	do
		local sk, md, marks = ns.providers.skills, P.MarkDirty, 0
		P.MarkDirty = function(...) marks = marks + 1 return md(...) end
		local own, at = sk._firedOwn, sk._collectedAt
		sk._firedOwn, sk._collectedAt = true, GetTime()
		fire("SKILL_LINES_CHANGED")
		check(marks == 0, "fired by the skills list's own read: the recipes aren't read again: " .. marks)
		sk._firedOwn, sk._collectedAt = own, at
		P.MarkDirty = md
	end
	reads = 0
	ns.db.recipes[key][164] = nil -- (the list it made dropped since: Prune)
	fire("TRADE_SKILL_LIST_UPDATE")
	check(reads == 3 and ns.db.recipes[key][164], "the list it made gone: read again: " .. reads)
	ns.db.recipes, P.PlayerProfessions, _G.ProfessionsFrame, _G.C_TradeSkillUI = was.recipes, was.profs, was.pf, was.ts
	P.lastSpell, P.lastCast, P.lastRead, ns.Print = was.last, was.cast, was.read, was.print
	ns.providers.recipes._dirty, ns.providers.camp._dirty = true, true
	if ns.providers.missing then ns.providers.missing._dirty = true end
end

io.write("[providers parts: one need per reagent slot (0.49.2 review)]\n")
do
	local P = ns.Professions
	local was = { profs = P.PlayerProfessions, pf = _G.ProfessionsFrame, ts = _G.C_TradeSkillUI, last = P.lastSpell,
		cast = P.lastCast, read = P.lastRead, recipes = ns.db.recipes, print = ns.Print }
	local key = P.CharKey()
	ns.db.recipes = { [key] = {} }
	P.PlayerProfessions = function() return { { name = "Blacksmithing", rank = 50, maxRank = 75, skillLine = 164 } } end
	_G.ProfessionsFrame = Obj("Frame"); ProfessionsFrame.shown = true
	_G.C_TradeSkillUI = MockWindow(function() return { professionID = 164, professionName = "Blacksmithing" } end, { [164] = { 2662 } },
		function() return { name = "Copper Chain Pants", icon = 1, learned = true } end,
		function() return { outputItemID = 2852, reagentSlotSchematics = {
			-- one slot whose reagent comes in tiers (any one of them does), an optional slot, a plain one
			{ quantityRequired = 2, required = true, reagents = { { itemID = 2840 }, { itemID = 2841 }, { itemID = 2842 } } },
			{ quantityRequired = 1, required = false, reagents = { { itemID = 4000 } } },
			{ quantityRequired = 3, reagents = { { itemID = 2880 } } } } } end)
	ns.Print = function() end
	P.lastSpell, P.lastCast = nil, nil
	P.Snapshot(); FlushAll()
	local r = ns.db.recipes[key][164] and ns.db.recipes[key][164].list[1]
	local got = {}
	for _, rg in ipairs(r and r.reagents or {}) do got[#got + 1] = rg[1] .. "x" .. rg[2] end
	check(table.concat(got, ",") == "2840x2,2880x3",
		"each slot one need (its first reagent), optional slots left out: " .. table.concat(got, ","))
	ns.db.recipes, P.PlayerProfessions, _G.ProfessionsFrame, _G.C_TradeSkillUI = was.recipes, was.profs, was.pf, was.ts
	P.lastSpell, P.lastCast, P.lastRead, ns.Print = was.last, was.cast, was.read, was.print
	ns.providers.recipes._dirty, ns.providers.camp._dirty = true, true
	if ns.providers.missing then ns.providers.missing._dirty = true end
end

io.write("[providers parts: no recipes indexed yet (0.49.2 review)]\n")
do
	local P = ns.Professions
	local was = { recipes = ns.db.recipes, nd = ns.db.noDirectOpen, profs = P.PlayerProfessions, easy = ns.db.easyMode }
	ns.db.recipes = { [P.CharKey()] = {} }
	P.PlayerProfessions = function() return { { name = "Blacksmithing", rank = 40, maxRank = 75, skillLine = 164 } } end
	ns.db.easyMode = false
	local p = ns.providers.recipes
	ns.db.noDirectOpen = nil
	p._dirty = true
	local row = ns:GetEntries(p)[1]
	check(row and row.key == "scan" and not row.noActivate and ns.Easy.Verbs(row) == "scan your professions",
		"a client that may let addons open profession windows: the scan row, and the footer says so: " .. tostring(row and ns.Easy.Verbs(row)))
	ns.db.noDirectOpen = true -- (WoW Forever: the game blocks it)
	p._dirty = true
	row = ns:GetEntries(p)[1]
	check(row and row.noActivate and not row.activate and ns.Easy.Verbs(row) == nil
		and row.name == "Open a profession's window once: Terminal reads its recipes from it",
		"where the game won't let addons open them: a note saying what indexes them, nothing to run: " .. tostring(row and row.name))
	local said = table.concat(ns.commands.profs.run(), "\n")
	check(said:find("not indexed (open it once)", 1, true) and not said:find("Index my recipes", 1, true),
		".profs there: open it once (no scan to pick): " .. said)
	ns.db.recipes, ns.db.noDirectOpen, P.PlayerProfessions, ns.db.easyMode = was.recipes, was.nd, was.profs, was.easy
	p._dirty = true
	if ns.providers.missing then ns.providers.missing._dirty = true end
	ns.providers.camp._dirty = true
end

-- (review, 0.53.6) the open window's profession read through ns.Num / ns.Str: a secret name is never taken (nor
-- compared: on the client that's an error)
do
	local P = T.ns.Professions
	local was, real = _G.issecretvalue, P.PlayerProfessions
	_G.issecretvalue = function(v) return v == "SECRET" end
	P.PlayerProfessions = function() return {} end
	local api = {
		GetChildProfessionInfo = function() return { professionName = "SECRET", professionID = 171 } end,
		GetBaseProfessionInfo = function() return { professionName = "Alchemy", professionID = 171, parentProfessionID = "SECRET" } end,
	}
	local key, name = P._ResolveProfession(api, {})
	T.check(key == 171 and name == "Alchemy", "a secret child name: the base profession's, never the secret: " .. tostring(name))
	_G.issecretvalue, P.PlayerProfessions = was, real
end
