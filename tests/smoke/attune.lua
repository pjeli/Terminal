-- Attune (0.50.2, the player's ask: "integrate it ... class quests, keys, quest chains, all in there, consistently like
-- Questie and AtlasLoot"): @attune lists Attune's attunements, dungeon quest lines, keys and class quests with how far
-- along you are (Attune_DB's record); Enter opens Attune's window on one and points at it; "> steps" lists the steps,
-- "> attunement" the attunements a quest is a step of; Simple mode's questions.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, AT = ns.Integrations, ns.Attune

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end
local function drop(id)
	ns.providers[id] = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
end

io.write("[attune: attunements, quest lines, keys and class quests from Attune]\n")
do
	local save = { lang = _G.AttuneLang, data = _G.Attune_Data, db = _G.Attune_DB, name = _G.UnitName, class = _G.UnitClass,
		faction = _G.UnitFactionGroup, level = _G.UnitLevel, slash = _G.SlashCmdList.Attune, easy = ns.db.easyMode,
		last = _G.AttuneLastViewed, show = ns.Highlight.Show }
	-- without Attune: no @attune, .integrations says so, the questions and the chains aren't Attune's
	check(not ns.providers.attune and ns:ResolveProvider("attune") == nil, "without Attune: no @attune")
	check(AT.Status() == ns.L["not found"], ".integrations: Attune not found: " .. tostring(AT.Status()))
	check(AT.Q.Question("my attunements") == nil and AT.Q.Question("how do i get into molten core") == nil,
		"without Attune: its questions aren't asked")
	check(ns.Pipes.Find("steps") == nil and ns.Pipes.Canonical("steps for molten core") == nil, "without Attune: no > steps")

	-- Attune's tables, as its files make them
	local lang = {
		DUNGEONS = "DUNGEONS", KEYS = "KEYS", RAIDS = "RAIDS", MISC = "MISC", CLASS_DRUID = "DRUID", CLASS_WARRIOR = "WARRIOR",
		["World of Warcraft"] = "World of Warcraft", ["Molten Core"] = "Molten Core", ["The Deadmines"] = "The Deadmines",
		["Onyxia's Lair"] = "Onyxia's Lair", Scholomance = "Scholomance", Naxxramas = "Naxxramas",
		["Q1_7848"] = "Attunement to the Core", ["Q2_7848"] = "Recover a Core Fragment.", ["I_18412"] = "Core Fragment",
		["Q1_168"] = "Collecting Memories", ["I_1894"] = "Miners' Union Card", ["Q1_65"] = "The Defias Brotherhood",
		["Q1_132"] = "The Defias Brotherhood, Part Two", ["Q1_5923"] = "Heeding the Call", ["Q1_5924"] = "Heeding the Call",
		["Q1_5921"] = "Moonglade", ["Q1_5537"] = "Skeleton Key", ["N1_1853"] = "Darkmaster Gandling", ["Q1_4182"] = "Dragonkin Menace",
		["Q1_1"] = "A Warrior's Training", ["Q1_901"] = "Dwarf One", ["Q1_902"] = "Dwarf Two", ["Q1_911"] = "Elf One",
		["Q1_912"] = "Elf Two", ["Q1_920"] = "Together",
	}
	_G.AttuneLang = setmetatable(lang, { __index = function(t, k) rawset(t, k, k) return k end }) -- (AceLocale's: the key back)
	local W = "World of Warcraft"
	local function A(id, name, group, faction, extra)
		local a = { ID = id, NAME = name, EXPAC = W, GROUP = group, FACTION = faction, ICON = "Interface\\Icons\\INV_Misc_Key_03",
			DESC = "Its rules.", GROUPSIZE = 5, LEVELS = "55" }
		for k, v in pairs(extra or {}) do a[k] = v end
		return a
	end
	local function S(aid, id, typ, wh, follows, stage, extra)
		local s = { ID_ATTUNE = aid, ID = id, TYPE = typ, STEP = "", LOCATION = "Blackrock Mountain", ID_WOWHEAD = wh,
			ICON = "Interface\\Icons\\inv_scroll_03", FOLLOWS = follows, STAGE = stage }
		for k, v in pairs(extra or {}) do s[k] = v end
		return s
	end
	_G.Attune_Data = {
		attunes = {
			A("170", "The Deadmines", "DUNGEONS", "Alliance", { LEVELS = "17-26" }),
			A("410", "Scholomance", "DUNGEONS", "Alliance"),
			A("5103", "Bear Form", "DRUID", "Alliance", { CLASS = "DRUID", GROUPSIZE = 1 }),
			A("5200", "A Warrior's Training", "WARRIOR", "Both", { CLASS = "WARRIOR", GROUPSIZE = 1 }),
			A("150", "Scholomance", "KEYS", "Alliance"),
			A("20", "Molten Core", "RAIDS", "Both", { GROUPSIZE = 40 }),
			A("30", "Onyxia's Lair", "RAIDS", "Horde", { GROUPSIZE = 40 }),
			A("40", "Onyxia's Lair", "RAIDS", "Alliance", { GROUPSIZE = 40 }),
			A("60", "Naxxramas", "RAIDS", "Both", { GROUPSIZE = 40 }),
			A("99", "Old Ways", "MISC", "Both", { DEPRECATED = 1 }),
		},
		steps = {
			S("20", "20", "Level", "55", "0", "1", { STEP = "Reach level 55", LOCATION = "" }),
			S("20", "30", "Pick Up", "7848", "20", "2"),
			S("20", "40", "Item", "18412", "30", "3", { LOCATION = "Blackrock Depths" }),
			S("20", "45", "Turn In", "7848", "40", "4"),
			S("20", "50", "End", "0", "45", "5", { STEP = "Attuned", LOCATION = "" }),
			-- the Deadmines: two lines, drawn side by side (stages), listed one after the other
			S("170", "10", "Level", "10", "0", "10", { STEP = "Reach level 10", LOCATION = "" }),
			S("170", "510", "Pick Up", "168", "10", "20", { LOCATION = "Stormwind City" }),
			S("170", "310", "Quest", "65", "10", "20", { LOCATION = "Westfall" }),
			S("170", "520", "Item", "1894", "510", "30", { LOCATION = "Westfall", COUNT = 4 }),
			S("170", "320", "Quest", "132", "310", "30", { LOCATION = "Redridge Mountains" }),
			S("170", "530", "Turn In", "168", "520", "40", { LOCATION = "Stormwind City" }),
			S("170", "540", "Spacer", "", "530", "50", { STEP = "Spacer", LOCATION = "" }),
			S("170", "600", "End", "0", "540&320", "60", { STEP = "Attuned", LOCATION = "" }),
			-- a class quest: the same quest for each race, either one
			S("5103", "10", "Level", "10", "0", "10", { STEP = "Reach level 10", LOCATION = "" }),
			S("5103", "20", "Quest", "5923", "10", "20", { LOCATION = "Teldrassil", OR = true }),
			S("5103", "21", "Quest", "5924", "10", "20", { LOCATION = "Teldrassil", OR = true }),
			S("5103", "30", "Quest", "5921", "21|20", "30", { LOCATION = "Moonglade" }),
			S("5103", "70", "End", "0", "30", "70", { LOCATION = "" }),
			S("5200", "10", "Quest", "1", "0", "10", { LOCATION = "Durotar" }),
			S("5200", "20", "End", "0", "10", "20", { LOCATION = "" }),
			S("150", "10", "Quest", "5537", "0", "10", { LOCATION = "Western Plaguelands" }),
			S("150", "20", "Kill", "1853", "10", "20", { LOCATION = "Scholomance" }),
			S("150", "30", "End", "0", "20", "30", { LOCATION = "" }),
			S("40", "10", "Quest", "4182", "0", "10", { LOCATION = "Burning Steppes" }),
			S("40", "20", "Attune", "20", "10", "20", { STEP = "Molten Core", LOCATION = "" }),
			S("40", "30", "End", "0", "20", "30", { LOCATION = "" }),
			S("410", "10", "Quest", "5537", "0", "10", { LOCATION = "Western Plaguelands" }),
			S("410", "20", "End", "0", "10", "20", { LOCATION = "" }),
			-- (retired, so not listed: its steps split by race, either branch leading on)
			S("99", "10", "Level", "10", "0", "10", { STEP = "Reach level 10", LOCATION = "" }),
			S("99", "20", "Quest", "901", "10", "20"), S("99", "30", "Quest", "902", "20", "30"),
			S("99", "21", "Quest", "911", "10", "20"), S("99", "31", "Quest", "912", "21", "30"),
			S("99", "40", "Quest", "920", "30|31", "40"), S("99", "50", "End", "0", "40", "50"),
		},
		quests = { [7848] = { 55, 5 } }, npcs = { [1853] = { "61", "Elite", "Undead" } },
		questGivers = { [7848] = { 1415, 50, 50, "Lothos Riftwaker" } },
	}
	_G.Attune_DB = { showDeprecatedAttunes = false, showAllClassQuests = false, toons = {
		["Tester Prime"] = { owner = 1, class = "WARRIOR", attuned = {},
			done = { ["20-20"] = 1, ["20-30"] = 1, ["170-10"] = 1, ["170-510"] = 1, ["170-310"] = 1, ["170-320"] = 1, ["5200-10"] = 1, ["5200-20"] = 1 } },
		["Tester Alt"] = { owner = 1, class = "DRUID", attuned = {},
			done = { ["20-20"] = 1, ["20-30"] = 1, ["20-40"] = 1, ["20-45"] = 1, ["20-50"] = 1 } },
		["Guildie Bob"] = { owner = 0, class = "MAGE", done = { ["20-50"] = 1 } },
	} }
	_G.UnitName = function() return "Tester", "Prime" end -- (WoW Forever: first and last names)
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	_G.UnitFactionGroup = function() return "Alliance" end
	_G.UnitLevel = function() return 60 end
	-- Attune's window: /attune toggles it; the first time it's made, on AttuneLastViewed; its tree selects by path
	local selected, made = {}, 0
	local function Node(id) local n = T.Obj("Frame"); n.__name = "Attune_Node_" .. id; _G[n.__name] = n; return n end
	local function Draw(path)
		local aid = path:match("\001([^\001]+)$")
		for k in pairs(_G) do if type(k) == "string" and k:find("^Attune_Node_") then _G[k]:Hide() end end
		for _, s in ipairs(_G.Attune_Data.steps) do
			if s.ID_ATTUNE == aid then local n = _G["Attune_Node_" .. s.ID] or Node(s.ID); n:Show() end
		end
	end
	-- (AceGUI's TreeGroup: a pick unfolds the groups it's given as parts; a joined path, as Attune picks
	-- AttuneLastViewed, unfolds none)
	local tree = { type = "TreeGroup", buttons = {}, status = { groups = { ["World of Warcraft"] = true, ["World of Warcraft\001RAIDS"] = true } } }
	function tree.SelectByPath(self, ...)
		local parts = { ... }
		local path = table.concat(parts, "\001")
		for i = 1, #parts do self.status.groups[table.concat(parts, "\001", 1, i)] = true end
		selected[#selected + 1] = path
		_G.AttuneLastViewed = path
		local b = T.Obj("Button"); b.uniquevalue = path; b:Show()
		self.buttons = { b }
		Draw(path)
	end
	_G.SlashCmdList.Attune = function(msg)
		local f = _G.Attune_MainFrame
		if f and f:IsShown() then f:Hide() return end
		if not f then
			made = made + 1
			f = T.Obj("Frame")
			f.obj = { children = { tree } }
			_G.Attune_MainFrame = f
			tree:SelectByPath(_G.AttuneLastViewed)
		end
		f:Show()
	end
	local shown
	ns.Highlight.Show = function(self, target, ...) shown = target return save.show(self, target, ...) end
	ns.db.easyMode = false
	AT.Forget(); AT.ForgetToon(); AT.Q.Forget()
	I.Setup(); FlushAll()

	local P = ns.providers.attune
	check(P and ns:ResolveProvider("attune") == P and ns:ResolveProvider("attunement") == P and ns:ResolveProvider("attunements") == P,
		"@attune, @attunement, @attunements")
	local res = UI:Search("@attune")
	-- what Attune lists for you: your faction's, your class's class quests, not the retired one; a key named as one
	check(Names(res) == "The Deadmines | Scholomance | A Warrior's Training | Scholomance key | Molten Core | Onyxia's Lair | Naxxramas",
		"Attune's list for an Alliance warrior, in its order: " .. Names(res))
	local function Row(name, rows)
		for _, e in ipairs(rows or res) do if e.name == name then return e end end
	end
	local mc = Row("Molten Core")
	-- how far along: the steps Attune saw you do (2 of 5), and the next one
	check(mc.detail == "Raid attunement  ·  Lv 55  ·  40%  ·  next: Core Fragment", "Molten Core's detail: " .. tostring(mc.detail))
	check(Row("A Warrior's Training").detail:find("done", 1, true) and Row("A Warrior's Training").icon:find("ReadyCheck", 1, true),
		"a finished class quest: done: " .. tostring(Row("A Warrior's Training").detail))
	check(Row("Naxxramas").detail:find("no steps yet", 1, true), "an attunement Attune has no steps for: said so: " .. Row("Naxxramas").detail)
	-- the Deadmines: the level, then one line's pick-up done, the other line finished: the card is next
	local dm = Row("The Deadmines")
	check(dm.detail:find("next: Miners' Union Card", 1, true), "the Deadmines' next step: " .. dm.detail)
	check(table.concat({ ns.Easy.Verbs(mc) }, "/") == "show in Attune/put in the chat box", "its verbs: " .. table.concat({ ns.Easy.Verbs(mc) }, "/"))
	check(mc.kindLabel:find("Attunement", 1, true), "labelled Attunement")

	-- the tooltip: the group, the rules, progress, the next steps, your alts
	local lines = {}
	local tip = setmetatable({}, { __index = function(_, k)
		if k == "SetText" or k == "AddLine" then return function(_, s) lines[#lines + 1] = tostring(s) end end
		if k == "AddDoubleLine" then return function(_, a, b) lines[#lines + 1] = tostring(a) .. " = " .. tostring(b) end end
		return function() end
	end })
	mc.tooltip(mc, tip)
	local text = table.concat(lines, "\n")
	check(text:find("Its rules.", 1, true) and text:find("Progress = 40% (2 of 5 steps)", 1, true) and text:find("get: Core Fragment", 1, true)
		and text:find("Tester Alt done", 1, true) and not text:find("Bob", 1, true) and text:find("Enter: show in Attune", 1, true),
		"Molten Core's tooltip (your alts, not your guild's): " .. text)

	-- Enter: Attune's window opens on it (the first time made on it), pointing at it in the tree
	shown = nil
	mc.activate(mc); FlushAll()
	check(made == 1 and _G.Attune_MainFrame:IsShown() and _G.AttuneLastViewed == "World of Warcraft\001RAIDS\00120", "Enter opens Attune on Molten Core")
	check(#selected == 1 and shown and shown.uniquevalue == _G.AttuneLastViewed, "the first open picks it once (its group unfolded), and it's pointed at")
	-- open: another one is picked in its tree (no toggling it shut)
	shown = nil
	dm.activate(dm); FlushAll()
	check(_G.Attune_MainFrame:IsShown() and selected[#selected] == "World of Warcraft\001DUNGEONS\001170" and shown and shown.uniquevalue == selected[#selected],
		"open already: the Deadmines picked and pointed at: " .. tostring(selected[#selected]))
	-- closed again: shown, then picked
	_G.Attune_MainFrame:Hide()
	mc.activate(mc); FlushAll()
	check(made == 1 and _G.Attune_MainFrame:IsShown() and selected[#selected]:find("\00120$"), "closed: opened again and Molten Core picked")
	-- its results page (no tree): back to the tree, which opens on it
	local toggled = 0
	_G.Attune_ToggleView = function() toggled = toggled + 1; _G.Attune_MainFrame.obj.children = { tree }; tree:SelectByPath(_G.AttuneLastViewed) end
	_G.Attune_MainFrame.obj.children = {}
	dm.activate(dm); FlushAll()
	check(toggled == 1 and selected[#selected]:find("\001170$"), "on its results page: back to the attunements, on the Deadmines")
	_G.Attune_ToggleView = nil
	-- (review, 0.50.2) made the first time on a group you folded: picked again by its parts, unfolding it
	_G.Attune_MainFrame, tree.status.groups, made = nil, {}, 0
	local before = #selected
	dm.activate(dm); FlushAll()
	check(made == 1 and #selected == before + 2 and tree.status.groups["World of Warcraft\001DUNGEONS"] and shown and shown.uniquevalue == selected[#selected],
		"a folded group: unfolded and pointed at: " .. (#selected - before))
	-- Shift+Enter: the chat box
	check(mc.shareLink(mc) == "Molten Core (Attune): 40%, next: Core Fragment", "Shift+Enter's words: " .. mc.shareLink(mc))
	check(mc.secondarySecure and mc.secondaryIsOpen == ns.ChatBoxNeverOpen, "Shift+Enter: the game opens the chat box")

	-- filters
	res = UI:Search("@attune is:raid")
	check(Names(res) == "Molten Core | Onyxia's Lair | Naxxramas", "is:raid: " .. Names(res))
	res = UI:Search("@attune is:key")
	check(Names(res) == "Scholomance key", "is:key: " .. Names(res))
	res = UI:Search("@attune is:done")
	check(Names(res) == "A Warrior's Training", "is:done: " .. Names(res))
	res = UI:Search("@attune is:todo is:raid")
	check(Names(res) == "Molten Core | Onyxia's Lair", "is:todo (Naxxramas has no steps): " .. Names(res))
	res = UI:Search("@attune is:class class:warrior")
	check(Names(res) == "A Warrior's Training", "is:class class:warrior: " .. Names(res))
	res = UI:Search("core fragment")
	check(Row("Molten Core", res) ~= nil, "a step's name finds its attunement: " .. Names(res))

	-- > steps: first to last, each line in turn; done and next said; the same quest for each race once
	res = UI:Search("molten core > steps")
	check(Names(res) == "Reach level 55 | Attunement to the Core | Core Fragment | Attunement to the Core", "Molten Core's steps: " .. Names(res))
	check(res[1].detail:find("^step 1 of 4") and res[1].detail:find("done", 1, true) and res[3].detail:find("next", 1, true)
		and res[2].detail:find("pick up", 1, true) and res[4].detail:find("turn in", 1, true), "each says its step: " .. res[3].detail)
	check(res[2].qid == 7848 and res[3].itemID == 18412, "a quest step carries its quest, an item step its item")
	res = UI:Search("deadmines > steps")
	check(Names(res) == "Reach level 10 | Collecting Memories | Miners' Union Card | Collecting Memories | The Defias Brotherhood | The Defias Brotherhood, Part Two",
		"the Deadmines: each line in turn: " .. Names(res))
	check(res[3].detail:find("get 4", 1, true), "an item needed four times: " .. res[3].detail)
	-- Enter on a step: Attune on its attunement, pointing at the step's box
	shown = nil
	res[3].activate(res[3]); FlushAll()
	check(selected[#selected]:find("\001170$") and shown == _G.Attune_Node_520, "Enter on a step: its box pointed at")
	check(table.concat({ ns.Easy.Verbs(res[3]) }, "/") == "show in Attune/put in the chat box", "a step's verbs")
	-- a step that's another attunement: that one's steps, and Enter opens it
	res = UI:Search("@attune onyxia > steps")
	check(Names(res) == "Dragonkin Menace | Molten Core", "Onyxia's: a quest, then Molten Core: " .. Names(res))
	local link = res[2]
	link.activate(link); FlushAll()
	check(selected[#selected]:find("\00120$"), "Enter on the Molten Core step opens Molten Core")
	-- the quest step's tooltip: Attune's objective and giver
	lines = {}
	res = UI:Search("molten core > steps")
	res[2].tooltip(res[2], tip)
	text = table.concat(lines, "\n")
	check(text:find("Recover a Core Fragment.", 1, true) and text:find("Lothos Riftwaker", 1, true) and text:find("Step 2 of 4 of Molten Core (Attune)", 1, true),
		"a quest step's tooltip: " .. text)

	-- (review, 0.50.2) a chain split by race: each branch whole, then what either leads to
	local split = {}
	for i, r in ipairs(AT.Index().byId["99"].steps) do split[i] = r.title end
	check(table.concat(split, ",") == "Reach level 10,Dwarf One,Dwarf Two,Elf One,Elf Two,Together", "branches in turn: " .. table.concat(split, ","))
	-- the next step: one your race can take first (the other branch's after it)
	local QR, forYou = ns.QuestRewards, ns.QuestRewards.ForYou
	QR.ForYou = function(q) return q ~= 901 end
	local nx = AT.NextSteps(AT.Index().byId["99"])
	check(nx[1] and nx[1].title == "Elf One" and nx[2] and nx[2].title == "Dwarf One", "next: yours first: " .. tostring(nx[1] and nx[1].title))
	QR.ForYou = forYou
	-- the level a quest needs isn't its level
	check(not text:find("Level 55", 1, true), "a quest step's tooltip doesn't call the level it needs its level")
	-- an alt Attune hasn't seen the class of: no progress on a class quest
	check(AT.Progress(AT.Index().byId["5200"], { class = "UNKNOWN", done = { ["5200-10"] = 1 } }, false) == nil, "an alt of unknown class: no class quest progress")
	-- UnitName without the second part: the one record starting with the first name
	AT.ForgetToon()
	_G.UnitName = function() return "Guildie" end
	check(select(2, AT.MyToon()) == "Guildie Bob", "UnitName's first name alone: the record that starts with it")
	_G.UnitName = function() return "Tester" end
	AT.ForgetToon()
	check(AT.MyToon() == nil, "two records start with it: none taken")
	-- (review, 0.53.6) both names, no record of them yet: not an alt's with the same first name
	_G.UnitName = function() return "Guildie", "Newcomer" end
	AT.ForgetToon()
	check(AT.MyToon() == nil, "both names and no record of them: not the record of another Guildie")
	_G.UnitName = function() return "Tester", "Prime" end
	AT.ForgetToon()

	-- > attunement: the attunements a quest is a step of
	res = UI:Search("molten core > steps > attunement")
	check(Names(res) == "Molten Core", "a step's attunement: " .. Names(res))
	check(ns.Pipes.Find("steps") == "steps" and ns.Pipes.Find("attunement") == "attunement", "the links are there with Attune")
	-- (review, 0.50.2) from a name typed: a quest, an item or an NPC that's a step
	res = UI:Search("attunement to the core > attunement")
	check(Names(res) == "Molten Core", "a quest's name > attunement: " .. Names(res))
	res = UI:Search("darkmaster gandling > attunement")
	check(Names(res) == "Scholomance key", "an NPC's name > attunement: " .. Names(res))

	-- Simple mode
	ns.db.easyMode = true
	local function Open(s)
		UI:Hide(); FlushAll()
		UI:Open(s); FlushAll()
		return UI.Results(), tostring(UI.status:GetText())
	end
	local rows, foot = Open("my attunements")
	check(#rows == 7 and foot:find("Attunements", 1, true) and foot:find("1 of 7 done", 1, true), "my attunements: " .. Names(rows) .. " / " .. foot)
	rows, foot = Open("raid attunements")
	check(Names(rows) == "Molten Core | Onyxia's Lair | Naxxramas" and foot:find("Raid attunements", 1, true), "raid attunements: " .. Names(rows))
	rows = Open("am i attuned to mc")
	check(Names(rows) == "Molten Core", "am i attuned to mc (shorthand): " .. Names(rows))
	rows = Open("dungeon keys")
	check(Names(rows) == "Scholomance key", "dungeon keys: " .. Names(rows))
	rows = Open("class quests")
	check(Names(rows) == "A Warrior's Training", "class quests: yours: " .. Names(rows))
	rows = Open("druid class quests")
	check(#rows == 1 and rows[1].noActivate and rows[1].name:find("your class", 1, true), "another class's: said why there's none: " .. Names(rows))
	rows = Open("attunements to do")
	check(Names(rows) == "The Deadmines | Scholomance | Scholomance key | Molten Core | Onyxia's Lair", "attunements to do: " .. Names(rows))
	rows, foot = Open("how do i get into molten core")
	check(Names(rows) == "Reach level 55 | Attunement to the Core | Core Fragment | Attunement to the Core", "how do i get into molten core: its steps: " .. Names(rows))
	check(foot:find("Steps for", 1, true), "the footer says so: " .. foot)
	rows = Open("how do i get into scholomance")
	check(#rows == 2 and rows[1].name == "Skeleton Key" and rows[2].name == "Darkmaster Gandling", "getting into Scholomance: the key's steps: " .. Names(rows))
	rows = Open("steps for the deadmines")
	check(#rows == 6, "steps for the deadmines: " .. Names(rows))
	-- not Attune's: a place without an attunement, keys alone, a quest search
	check(AT.Q.Question("how do i get into deadmines") == nil and AT.Q.Question("how do i get into stormwind") == nil
		and AT.Q.Question("keys") == nil and AT.Q.Question("warlock quests") == nil and AT.Q.Question("deadmines quests") == nil,
		"not Attune's questions")
	check(AT.Q.Question("attunement to the core") == nil and AT.Q.Question("attunement to th") == nil,
		"a quest's name is a search, not the question, while it's typed too")
	-- (review, 0.50.2) other questions' words, and the addon's own name: not Attune's list
	for _, s in ipairs({ "what dungeon quests should i do", "dungeon quests for my level", "dungeon quests to share", "grey dungeon quests",
		"dungeon quests to drop", "attune settings", "attune options", "attune" }) do
		check(AT.Q.Question(s) == nil, s .. ": not Attune's list")
	end
	check(AT.Q.Question("dungeon quests") and AT.Q.Question("dungeon quests").group == "dungeon", "dungeon quests: Attune's")
	-- Alt+`: the same as Advanced syntax
	check(ns.Easy.ToAdvanced("raid attunements") == "@attune is:raid ", "Alt+`: " .. ns.Easy.ToAdvanced("raid attunements"))
	check(ns.Easy.ToAdvanced("how do i get into mc") == "Molten Core > steps ", "Alt+` of the steps: " .. ns.Easy.ToAdvanced("how do i get into mc"))
	check(ns.Easy.ToAdvanced("warrior class quests i need") == "@attune is:class is:todo class:warrior ",
		"Alt+`: " .. ns.Easy.ToAdvanced("warrior class quests i need"))
	UI:Hide(); FlushAll()
	ns.db.easyMode = false

	-- Attune's option for every class's class quests: they're listed too
	_G.Attune_DB.showAllClassQuests = true
	P._dirty = true
	res = UI:Search("@attune is:class")
	local bear = Row("Bear Form (DRUID)", res)
	check(Names(res) == "Bear Form (DRUID) | A Warrior's Training" and bear and (bear.detail:find("Druid", 1, true) or bear.detail:find("DRUID", 1, true)) ~= nil
		and not bear.detail:find("%%"),
		"every class's with Attune's option, another class's said: " .. Names(res) .. " / " .. tostring(Row("Bear Form", res) and Row("Bear Form", res).detail))
	res = UI:Search("bear form > steps")
	check(Names(res) == "Reach level 10 | Heeding the Call | Moonglade", "the same quest for each race once: " .. Names(res))
	_G.Attune_DB.showAllClassQuests = false
	P._dirty = true

	check(AT.Status():find("7 attunements", 1, true) and AT.Status():find("1 done", 1, true), ".integrations: " .. AT.Status())

	-- (review, 0.53.6) a step named "Quest #id" while Questie wasn't ready: named again once it is
	do
		local QD = ns.QuestieData
		local readyWas, onReadyWas, dbWas, title168 = QD.Ready, QD.OnReady, QD.DB, lang["Q1_168"]
		local later
		QD.Ready = function() return false end
		QD.OnReady = function(fn) later = fn end
		QD.DB = function() return nil end
		lang["Q1_168"] = nil
		local function Title()
			for _, rec in ipairs(AT.Index().list) do
				for _, r in ipairs(rec.steps) do for _, q in ipairs(r.qids or {}) do if q == 168 then return r.title end end end
			end
		end
		AT.Forget()
		local before = Title()
		lang["Q1_168"] = title168
		QD.Ready = readyWas
		if later then later() end
		check(before == ns.L["Quest #%d"]:format(168) and Title() == "Collecting Memories",
			"named again once Questie is ready: " .. tostring(before) .. " -> " .. tostring(Title()))
		QD.OnReady, QD.DB = onReadyWas, dbWas
	end

	-- put back: Attune gone
	drop("attune")
	I.attune.on = false
	AT.Forget(); AT.ForgetToon(); AT.Q.Forget()
	_G.AttuneLang, _G.Attune_Data, _G.Attune_DB = save.lang, save.data, save.db
	_G.UnitName, _G.UnitClass, _G.UnitFactionGroup, _G.UnitLevel = save.name, save.class, save.faction, save.level
	_G.SlashCmdList.Attune, _G.AttuneLastViewed, _G.Attune_MainFrame = save.slash, save.last, nil
	for k in pairs(_G) do if type(k) == "string" and k:find("^Attune_Node_") then _G[k] = nil end end
	ns.Highlight.Show = save.show
	ns.db.easyMode = save.easy
	ns.Pipes.ClearSteps()
end
