-- Toys, pets and titles (Collections.lua); unearned achievements, currency numbers, addons on/off,
-- .reload and targeting an NPC.
local T = ...
local ns, UI, F, S, check, log, key, names, Obj, FlushAll = T.ns, T.UI, T.F, T.S, T.check, T.log, T.key, T.names, T.Obj, T.FlushAll

local function logFind(text, from)
	for i = from or 1, #log do if log[i]:find(text, 1, true) then return true end end
	return false
end
local function macro() local mp = _G.TerminalMacroProxy; return mp and mp.attrs and mp.attrs.macrotext end
local function press(q, shift)
	UI:Open(q)
	if shift then _G.IsShiftKeyDown = function() return true end end
	key("ENTER")
	_G.IsShiftKeyDown = function() return false end
	local armed, text = S.armed, macro()
	UI:Disarm(); UI:Hide(); FlushAll()
	return armed, text
end
-- Collections.lua registers a kind only where the client has its API: loaded again once mocked
local function reload() assert(loadfile("Terminal/Providers/Collections.lua"))("Terminal", ns) end
-- and taken out again once its mock is gone (the rest of the run has no such API)
local function drop(id)
	ns.providers[id] = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
end

io.write("[toys]\n")
do
	local save = { tb = _G.C_ToyBox, pj = _G.C_PetJournal, has = _G.PlayerHasToy, ne = _G.GetNumExpansions, cont = _G.C_Container.GetItemCooldown }
	-- the journal shows only uncollected toys with a search typed: the read must see past that
	local state = { collected = false, uncollected = true, unusable = false, src = { true, false }, exp = { true }, search = "zzz" }
	local TOYS = { [1001] = "Toy Train Set", [1002] = "Piccolo of the Flaming Fire", [1003] = "Not Mine" }
	local order = { 1001, 1002, 1003 }
	local function visible()
		local out = {}
		local allSrc = state.src[1] and state.src[2]
		for _, id in ipairs(order) do
			local owned = id ~= 1003
			if ((owned and state.collected) or (not owned and state.uncollected)) and allSrc and state.search == "" then out[#out + 1] = id end
		end
		return out
	end
	_G.C_ToyBox = {
		GetNumToys = function() return #visible() end,
		GetToyFromIndex = function(i) return visible()[i] end,
		GetToyInfo = function(id) return id, TOYS[id], 7, id == 1001 end,
		GetCollectedShown = function() return state.collected end, SetCollectedShown = function(v) state.collected = v end,
		GetUncollectedShown = function() return state.uncollected end, SetUncollectedShown = function(v) state.uncollected = v end,
		GetUnusableShown = function() return state.unusable end, SetUnusableShown = function(v) state.unusable = v end,
		IsSourceTypeFilterChecked = function(i) return state.src[i] end, SetSourceTypeFilter = function(i, v) state.src[i] = v end,
		SetAllSourceTypeFilters = function(v) state.src[1], state.src[2] = v, v end,
		IsExpansionTypeFilterChecked = function(i) return state.exp[i] end, SetExpansionTypeFilter = function(i, v) state.exp[i] = v end,
		SetAllExpansionTypeFilters = function(v) state.exp[1] = v end,
		SetFilterString = function(s) state.search = s end,
	}
	_G.C_PetJournal = { GetNumPetSources = function() return 2 end }
	_G.GetNumExpansions = function() return 1 end
	_G.PlayerHasToy = function(id) return id ~= 1003 end
	_G.ToyBox = Obj("Frame"); ToyBox.searchBox = Obj("EditBox"); ToyBox.searchBox.text = "zzz"
	_G.C_Container.GetItemCooldown = function(id) if id == 1002 then return GetTime() - 10, 300, 1 end return 0, 0, 1 end
	reload()
	local p = ns.providers.toys
	check(p and ns:ResolveProvider("toy") == p, "@toy is a kind")
	local t = names(ns:GetEntries(p))
	check(t["Toy Train Set"] and t["Piccolo of the Flaming Fire"] and not t["Not Mine"], "the toys you own, whatever the journal's filters show")
	check(state.collected == false and state.uncollected == true and state.src[2] == false and state.search == "zzz",
		"the journal's filters are put back as they were")
	check(t["Toy Train Set"].detail == "Favorite" and t["Toy Train Set"].kind == "toys", "favourite shown: " .. tostring(t["Toy Train Set"].detail))
	check(t["Piccolo of the Flaming Fire"].detail:find("ready in 4m", 1, true), "cooldown shown: " .. tostring(t["Piccolo of the Flaming Fire"].detail))
	check(p.selfEvents and p.guard, "opening the filters fires TOYS_UPDATED: those events are ignored")
	local armed, text = press("@toy train")
	check(armed == "MACRO" and text == "/use item:1001", "Enter uses the toy, pressed by the game: " .. tostring(text))
	armed, text = press("@toy train", true)
	check(armed == "MACRO" and text and text:find("S(true,3)", 1, true) and text:find('B:SetText("Toy Train Set")', 1, true) and #text <= S.MACRO_MAX,
		"Shift+Enter: the game opens the toy box with the toy searched: " .. tostring(text))
	_G.C_ToyBox, _G.C_PetJournal, _G.PlayerHasToy, _G.GetNumExpansions, _G.C_Container.GetItemCooldown = save.tb, save.pj, save.has, save.ne, save.cont
	_G.ToyBox = nil
end

io.write("[pets]\n")
do
	local save = _G.C_PetJournal
	local summoned
	_G.C_PetJournal = {
		SummonPetByGUID = function() end,
		GetOwnedPetIDs = function() return { "BattlePet-0-000001", "BattlePet-0-000002" } end,
		GetPetInfoByPetID = function(g)
			if g == "BattlePet-0-000001" then return 40, "Sir Squeaks", 12, 0, 0, 1, true, "Mechanical Squirrel", 5, 9 end
			return 41, nil, 1, 0, 0, 1, false, "Black Tabby Cat", 6, 2
		end,
		GetSummonedPetGUID = function() return summoned end,
	}
	reload()
	local p = ns.providers.pets
	check(p and ns:ResolveProvider("battlepet") == p and ns:ResolveProvider("companion") == p, "@pet is a kind")
	local t = names(ns:GetEntries(p))
	local sq = t["Sir Squeaks"]
	check(sq and t["Black Tabby Cat"], "your pets, by their own name or their species'")
	check(sq and sq.detail == "Lv 12  Mechanical Squirrel  Favorite", "level, species and favourite shown: " .. tostring(sq and sq.detail))
	summoned = "BattlePet-0-000001"
	check(sq.detail:find("out now", 1, true), "the pet that's out says so")
	local armed, text = press("@pet squeaks")
	check(armed == "MACRO" and text == '/run C_PetJournal.SummonPetByGUID("BattlePet-0-000001")', "Enter summons it, pressed by the game: " .. tostring(text))
	armed, text = press("@pet squeaks", true)
	check(armed == "MACRO" and text and text:find("S(true,2)", 1, true) and text:find('"Mechanical Squirrel"', 1, true),
		"Shift+Enter: the pet journal, searched for its species: " .. tostring(text))
	-- a client without GetOwnedPetIDs: the journal's list, owned ones only
	_G.C_PetJournal = {
		SummonPetByGUID = function() end,
		GetNumPets = function() return 2 end,
		GetPetInfoByIndex = function(i)
			if i == 1 then return "BattlePet-0-000003", 50, true, nil, 3, false, false, "Snowshoe Rabbit", 1 end
			return nil, 51, false, nil, 1, false, false, "Unowned Thing", 1
		end,
	}
	p._dirty = true
	t = names(ns:GetEntries(p))
	check(t["Snowshoe Rabbit"] and not t["Unowned Thing"], "by the journal's list: only pets you own")
	_G.C_PetJournal = save
end

io.write("[titles]\n")
do
	local save = { n = _G.GetNumTitles, k = _G.IsTitleKnown, nm = _G.GetTitleName, cur = _G.GetCurrentTitle, set = _G.SetCurrentTitle }
	local current = 5
	_G.GetNumTitles = function() return 6 end
	_G.IsTitleKnown = function(i) return i == 1 or i == 5 end
	_G.GetTitleName = function(i) return ({ [1] = "Private ", [5] = " the Explorer", [6] = "Unknown" })[i], true end
	_G.GetCurrentTitle = function() return current end
	_G.SetCurrentTitle = function() end
	reload()
	local p = ns.providers.titles
	local t = names(ns:GetEntries(p))
	check(p and t["Private"] and t["the Explorer"] and not t["Unknown"], "known titles, without their spaces")
	check(t["No title"] and t["No title"].key == -1, "a row for no title (-1)")
	check(t["the Explorer"].detail == "Current" and t["Private"].detail == "" and t["No title"].detail == "", "the current one is marked")
	current = 0
	check(t["No title"].detail == "Current", "no title worn: that row is current")
	local armed, text = press("@title explorer")
	check(armed == "MACRO" and text == "/run SetCurrentTitle(5)", "Enter sets it, pressed by the game: " .. tostring(text))
	armed, text = press("@title no title")
	check(text == "/run SetCurrentTitle(-1)", "no title: -1: " .. tostring(text))
	_G.GetNumTitles, _G.IsTitleKnown, _G.GetTitleName, _G.GetCurrentTitle, _G.SetCurrentTitle = save.n, save.k, save.nm, save.cur, save.set
end

io.write("[collections: kind colours]\n")
do
	local function rgb(c) return tonumber(c:sub(3, 4), 16), tonumber(c:sub(5, 6), 16), tonumber(c:sub(7, 8), 16) end
	for _, id in ipairs({ "toys", "pets", "titles", "guild", "friends", "who", "gold" }) do
		local r1, g1, b1 = rgb(ns.providers[id].color)
		for _, other in ipairs(ns.providerOrder) do
			local o = ns.providers[other]
			if other ~= id and o.color then
				local r2, g2, b2 = rgb(o.color)
				if math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) < 60 then
					check(false, id .. "'s colour is too close to " .. other .. "'s")
				end
			end
		end
	end
end

for _, id in ipairs({ "toys", "pets", "titles" }) do drop(id) end

io.write("[achievements: unearned ones]\n")
do
	local save = { info = _G.GetAchievementInfo, num = _G.GetCategoryNumAchievements, nc = _G.GetAchievementNumCriteria, ci = _G.GetAchievementCriteriaInfo }
	_G.GetCategoryNumAchievements = function() return 3 end
	_G.GetAchievementInfo = function(_, i)
		if i == 2 then return 8, "Level 20", 10, false, 1, 1, 1, "Reach level 20.", 0, 1 end
		if i == 3 then return 9, "Fishing Ace", 5, false, 1, 1, 1, "Catch 50 fish.", 0, 1 end
		return 7, "Level 10", 10, true, 1, 1, 1, "Reach level 10.", 0, 1
	end
	local crit = 0
	_G.GetAchievementNumCriteria = function(id) crit = crit + 1; return id == 8 and 10 or 1 end
	_G.GetAchievementCriteriaInfo = function(id, i)
		if id == 9 then return "Fish", 0, false, 12, 50 end
		return "c" .. i, 0, i <= 3, 0, 1
	end
	ns.providers.achievements._dirty = true
	local plain = names(UI:Search("level"))
	check(plain["Level 10"] and not plain["Level 20"], "plain searches: earned achievements only")
	local all = names(UI:Search("@achievement level"))
	local a20, a10 = all["Level 20"], all["Level 10"]
	check(a20 and a10, "@achievement lists the unearned ones too")
	check(a20 and a20.kind == "achievements" and a10.kind == "achievements" and a20.freqKey == "achievements:8", "earned or not, the rows are one kind")
	check(a10.completed == true and a20.completed == false, "rows say whether they're earned (completed)")
	check(crit == 0, "progress isn't worked out for every row up front")
	check(a20.progress == "3/10" and a20.detail == "3/10  10 pts", "unearned: its criteria done so far: " .. tostring(a20.detail))
	check(a20.color == "|cff8a8a8a" and a10.color == nil, "unearned rows are greyed")
	check(a10.progress == nil and a10.detail == "Done  10 pts", "earned rows as before: " .. tostring(a10.detail))
	local fish = names(UI:Search("@ach fishing"))["Fishing Ace"]
	check(fish and fish.progress == "12/50", "one counted criterion: its count: " .. tostring(fish and fish.progress))
	local before = crit
	local _ = a20.detail
	check(crit == before, "progress kept until criteria move")
	-- criteria moved (CRITERIA_UPDATE bumps a number): read again next time
	_G.GetAchievementCriteriaInfo = function(_, i) return "c" .. i, 0, i <= 4, 0, 1 end
	local lazy
	local idx = getmetatable(a20).__index
	for i = 1, 20 do local n, v = debug.getupvalue(idx, i); if n == "lazy" then lazy = v end end
	local prog = lazy and lazy.progress
	for i = 1, 20 do
		local n, v = debug.getupvalue(prog, i)
		if n == "critGen" then debug.setupvalue(prog, i, v + 1) end
	end
	check(a20.progress == "4/10", "criteria moved: progress read again: " .. tostring(a20.progress))
	-- one list (0.44.15: the earned ones were a second list): plain searches read its earned rows, picked out once
	-- per list and freed with it; .mem and .kinds show it once; Simple mode's Collections and recent picks read it all
	local p = ns.providers.achievements
	check(ns:ResolveProvider("achievement") == p and ns:ResolveProvider("achievements") == p and ns:ResolveProvider("ach") == p
		and not p.explicit, "@achievement(s): the one list, also read by plain searches")
	local list = ns:GetEntries(p)
	local view = p.plain(p, list)
	check(#view == 1 and view[1].name == "Level 10" and p.plain(p, list) == view, "its plain view: the earned rows, picked out once")
	local close = names(UI:Search("levle"))
	check(close["Level 10"] and not close["Level 20"], "close spellings in a plain search: earned ones only too")
	local function Lines(cmd)
		local n = 0
		for _, l in ipairs(ns:FindCommand(cmd).run("") or {}) do if l:find("@achievement", 1, true) then n = n + 1 end end
		return n
	end
	check(Lines("mem") == 1 and Lines("kinds") == 1, ".mem and .kinds show achievements once: " .. Lines("mem") .. ", " .. Lines("kinds"))
	check(ns.Easy.CategoryOf(a20) == "collections", "an achievement row belongs in Collections (where Simple mode searches them)")
	local savedF = { recent = ns.db.recent, freq = ns.db.freq }
	ns.db.recent, ns.db.freq = {}, {}
	ns:Bump("achievements:8")
	UI.showRecent = true
	local recent = names(UI:SearchText(""))
	UI.showRecent = nil
	ns.db.recent, ns.db.freq = savedF.recent, savedF.freq
	ns.freqKinds = nil
	check(recent["Level 20"], "an unearned achievement picked before is among your recent picks")
	p._usedAt = GetTime() - p.idleDrop - 1
	ns:DropIdle()
	local upv = {}
	for i = 1, 30 do local n, v = debug.getupvalue(p.plain, i); if not n then break end upv[n] = v end
	check(p._entries == nil and upv.earned == nil and upv.earnedOf == nil, "unused a while: freed, its earned view with it")
	_G.GetAchievementInfo, _G.GetCategoryNumAchievements, _G.GetAchievementNumCriteria, _G.GetAchievementCriteriaInfo = save.info, save.num, save.nc, save.ci
	p._dirty = true
end

io.write("[currency numbers]\n")
do
	ns.providers.currency._dirty = true
	local v = names(ns:GetEntries(ns.providers.currency))["Valor"]
	check(v and v.quantity == 5 and v.maxQuantity == 100, "currency rows carry quantity and maxQuantity")
	local saveInfo = C_CurrencyInfo.GetCurrencyListInfo
	C_CurrencyInfo.GetCurrencyListInfo = function(i)
		if i == 1 then return { name = "Crests", currencyID = 2914, iconFileID = 1, quantity = 40, maxQuantity = 0, maxWeeklyQuantity = 90, quantityEarnedThisWeek = 30 } end
	end
	C_CurrencyInfo.GetCurrencyListLink = function(i) return "|Hcurrency:" .. (100 + i) .. "|h" end
	C_CurrencyInfo.GetCurrencyIDFromLink = function(l) return tonumber(l:match("currency:(%d+)")) end
	ns.providers.currency._dirty = true
	local c = names(ns:GetEntries(ns.providers.currency))["Crests"]
	check(c and c.currencyID == 2914 and c.maxQuantity == 0 and c.maxWeeklyQuantity == 90 and c.quantityEarnedThisWeek == 30, "id, uncapped, the weekly cap and this week's")
	C_CurrencyInfo.GetCurrencyListInfo = saveInfo
	ns.providers.currency._dirty = true
	v = names(ns:GetEntries(ns.providers.currency))["Valor"]
	check(v and v.currencyID == 102, "no id in the info: read from its link: " .. tostring(v and v.currencyID))
	C_CurrencyInfo.GetCurrencyListLink, C_CurrencyInfo.GetCurrencyIDFromLink = nil, nil
	ns.providers.currency._dirty = true
end

io.write("[addons on / off]\n")
do
	local base = _G.C_AddOns
	local on = { Addon1 = true, Addon2 = false, Terminal = true }
	local calls = {}
	_G.C_AddOns = setmetatable({
		GetNumAddOns = function() return 3 end,
		GetAddOnInfo = function(i) local n = ({ "Addon1", "Addon2", "Terminal" })[i]; return n, n == "Terminal" and "Terminal" or ("Cool " .. n), "notes" end,
		IsAddOnLoaded = function(n) return n ~= "Addon2" end,
		GetAddOnEnableState = function(n, char) calls[#calls + 1] = "state " .. tostring(char); return on[n] and 2 or 0 end,
		EnableAddOn = function(n, char) calls[#calls + 1] = "enable " .. n .. " " .. tostring(char); on[n] = true end,
		DisableAddOn = function(n, char) calls[#calls + 1] = "disable " .. n .. " " .. tostring(char); on[n] = false end,
	}, { __index = base })
	ns.providers.addons._dirty = true
	local a = names(ns:GetEntries(ns.providers.addons))
	check(a["Cool Addon1"] and a["Cool Addon1"].detail == "enabled", "an addon's state shown: " .. tostring(a["Cool Addon1"] and a["Cool Addon1"].detail))
	check(a["Cool Addon2"] and a["Cool Addon2"].detail == "disabled", "a disabled one: " .. tostring(a["Cool Addon2"] and a["Cool Addon2"].detail))
	local mark = #log
	UI:Open("@addon cool addon1")
	local row = UI.Results()[1]
	check(row and row.name == "Cool Addon1", "the addon is found")
	_G.IsShiftKeyDown = function() return true end
	key("ENTER")
	_G.IsShiftKeyDown = function() return false end
	local found = false
	for _, c in ipairs(calls) do if c == "disable Addon1 Tester" then found = true end end
	check(found, "Shift+Enter turns it off, for this character: " .. table.concat(calls, ", "))
	check(logFind("Cool Addon1 disabled: .reload to apply", mark + 1) and not S.armed, "...and says .reload applies it (no game press)")
	check(row.detail == "disabled (.reload to apply)" and ns.providers.addons._dirty, "the row shows it at once: " .. tostring(row.detail))
	UI:Hide(); FlushAll()
	a = names(ns:GetEntries(ns.providers.addons))
	a["Cool Addon2"].secondary(a["Cool Addon2"])
	check(on.Addon2 == true and logFind("Cool Addon2 enabled: .reload to apply", mark + 1), "a disabled one is turned on")
	a["Terminal"].secondary(a["Terminal"])
	check(on.Terminal == true and logFind("can't turn itself off", mark + 1), "never Terminal itself")
	-- an addon with a minimap button and an options page: the page is a row of its own
	local opened
	_G.Settings = { OpenToCategory = function(id) opened = id; return true end }
	_G.SettingsPanel = Obj("Frame")
	local cat = { GetName = function() return "Cool Addon1" end, GetID = function() return 42 end }
	SettingsPanel.GetAllCategories = function() return { cat } end
	_G.Minimap = Obj("Frame")
	local mm = Obj("Button"); mm.__name = "Addon1MinimapButton"; mm.Click = function() end
	Minimap.GetChildren = function() return mm end
	ns.providers.addons._dirty = true
	a = names(ns:GetEntries(ns.providers.addons))
	local o = a["Cool Addon1 options"]
	check(a["Cool Addon1"].detail == "Minimap button  ·  disabled (.reload to apply)", "what Enter does and its state: " .. tostring(a["Cool Addon1"].detail))
	check(o and S.Resolve(o.secure, o).macro == "/run Settings.OpenToCategory(42)", "its options page: a row, opened by the game")
	o.activate(o)
	check(opened == 42, "...and without the game's press, from here")
	check(not a["Cool Addon2 options"], "no extra row for addons without both")
	_G.Settings, _G.SettingsPanel, _G.Minimap = nil, nil, nil
	_G.C_AddOns = base
	ns.providers.addons._dirty = true
end

io.write("[.reload]\n")
do
	local saveUI, saveRL = _G.C_UI, _G.ReloadUI
	local how
	_G.C_UI = { Reload = function() how = "C_UI" end }
	_G.ReloadUI = function() how = "ReloadUI" end
	local c = ns:FindCommand("rl")
	check(c and c.name == "reload", ".rl is .reload")
	c.run("", ns)
	check(how == "C_UI", ".reload reloads the UI: " .. tostring(how))
	_G.C_UI = nil
	c.run("", ns)
	check(how == "ReloadUI", "...with ReloadUI where C_UI has none")
	_G.C_UI, _G.ReloadUI = saveUI, saveRL
end

io.write("[npc: Shift+Enter targets]\n")
do
	local I = ns.Integrations
	-- Questie with one NPC (the earlier Questie tests took theirs away)
	local QDB = { NPCPointers = { [12] = true },
		QueryNPCSingle = function(id) return id == 12 and "Marshal McBride" or nil end,
		GetNPC = function(_, id) if id == 12 then return { spawns = { [9] = { { 50, 40 } } } } end end }
	local QZ = { GetUiMapIdByAreaId = function(_, z) return z == 9 and 37 or nil end, GetDungeonLocation = function() return nil end }
	_G.Questie = { API = { isReady = true } }
	_G.QuestieLoader = { ImportModule = function(_, n) return ({ QuestieDB = QDB, ZoneDB = QZ })[n] end }
	_G.C_Map = { CanSetUserWaypointOnMap = function() return true end, SetUserWaypoint = function(pt) log[#log + 1] = "Waypoint " .. pt.uiMapID end }
	I.npc.on, I.npc.list, I.npc.names = false, nil, nil
	I.Setup(); FlushAll()
	check(ns.providers.npc and I.npc.list and #I.npc.list == 1, "Questie's NPC indexed")
	local armed, text = press("@npc marshal", true)
	check(armed == "MACRO" and text == "/targetexact Marshal McBride", "Shift+Enter targets the NPC, pressed by the game: " .. tostring(text))
	local n = I.npc.list[1]
	check(n.secure and n.secure.binding == "TOGGLEWORLDMAP", "Enter still opens the map on it (and pins it)")
	check(n.secondaryIsOpen(n) == false, "always pressed")
	local realCombat, mark = _G.InCombatLockdown, #log
	_G.InCombatLockdown = function() return true end
	UI:Open("@npc marshal"); UI:Activate(1, { secondary = true })
	_G.InCombatLockdown = realCombat
	check(logFind("can't target Marshal McBride", mark + 1) and logFind("Waypoint 37", mark + 1) and not S.armed, "in combat: says so and pins it instead")
	UI:Hide(); FlushAll()
	-- clean up (as the Questie tests do)
	drop("npc"); drop("questie"); drop("loot")
	_G.Questie, _G.QuestieLoader, _G.C_Map = nil, nil, nil
	I.npc.on, I.npc.list, I.npc.names = false, nil, nil
end

io.write("[addons: the character with a surname]\n")
do
	-- WoW Forever: characters have surnames. UnitName gives "Plamen", "Warr"; the AddOn list keys this character
	-- as "Plamen Warr". "Plamen" alone is another (old) character, with its own settings.
	local base = { addons = _G.C_AddOns, un = _G.UnitName, reg = _G.RegionalUniqueNamesEnabled, const = _G.Constants }
	_G.UnitName = function(u) if u == "player" then return "Plamen", "Warr" end return base.un and base.un(u) end
	_G.RegionalUniqueNamesEnabled = function() return true end
	_G.Constants = setmetatable({ CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }, { __index = base.const })
	local perChar = { ["Plamen Warr"] = { Addon1 = false }, ["Plamen"] = { Addon1 = true } }
	local saves = 0
	_G.C_AddOns = setmetatable({
		GetNumAddOns = function() return 1 end,
		GetAddOnInfo = function() return "Addon1", "Cool Addon1", "notes" end,
		IsAddOnLoaded = function() return false end,
		GetAddOnEnableState = function(n, char) local t = perChar[char]; if not t then return 1 end return t[n] and 2 or 0 end,
		EnableAddOn = function(n, char) if perChar[char] then perChar[char][n] = true end end,
		DisableAddOn = function(n, char) if perChar[char] then perChar[char][n] = false end end,
		SaveAddOns = function() saves = saves + 1 end,
	}, { __index = base.addons })
	check(ns.CharacterName() == "Plamen Warr", "this character's name has its surname: " .. tostring(ns.CharacterName()))
	ns.providers.addons._dirty = true
	local a = names(ns:GetEntries(ns.providers.addons))
	check(a["Cool Addon1"] and a["Cool Addon1"].detail == "disabled", "an addon off for Plamen Warr shows disabled (not Plamen's on): " .. tostring(a["Cool Addon1"] and a["Cool Addon1"].detail))
	-- Shift+Enter toggles it, both ways, on this character only
	a["Cool Addon1"].secondary(a["Cool Addon1"])
	check(perChar["Plamen Warr"].Addon1 == true and perChar["Plamen"].Addon1 == true, "Shift+Enter turns it on for Plamen Warr")
	ns.providers.addons._dirty = true
	a = names(ns:GetEntries(ns.providers.addons))
	check(a["Cool Addon1"].detail == "enabled (.reload to apply)", "and shows enabled: " .. tostring(a["Cool Addon1"].detail))
	a["Cool Addon1"].secondary(a["Cool Addon1"])
	check(perChar["Plamen Warr"].Addon1 == false, "pressed again, it's off again (a toggle)")
	check(saves == 2, "each change is saved (SaveAddOns), so the reload keeps it: " .. tostring(saves))
	-- the game not taking a change: said, not claimed
	local logged
	local basePrint = ns.Print
	ns.Print = function(_, m) logged = m end
	local realEnable = C_AddOns.EnableAddOn
	rawset(C_AddOns, "EnableAddOn", function() end)
	ns.providers.addons._dirty = true
	a = names(ns:GetEntries(ns.providers.addons))
	a["Cool Addon1"].secondary(a["Cool Addon1"])
	check(logged and logged:find("didn't turn", 1, true), "a change the game didn't take is reported: " .. tostring(logged))
	rawset(C_AddOns, "EnableAddOn", realEnable)
	ns.Print = basePrint
	_G.C_AddOns, _G.UnitName, _G.RegionalUniqueNamesEnabled, _G.Constants = base.addons, base.un, base.reg, base.const
	ns.providers.addons._dirty = true
end
