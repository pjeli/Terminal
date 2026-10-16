-- What's Training (0.53.7, the player's ask: "integrate with this new version of WhatsTraining with public API and
-- offer it like we did for Attune"): @training lists the spells What's Training says you've still to learn (WT_API,
-- its forever branch), each with when, what it costs and where it's taught; Enter opens What's Training's window on
-- it and points at it; the questions ("what can i train", "how much is training"), the filters, "| sum cost", and
-- "> learn" (who teaches it).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, WT, L = ns.Integrations, ns.WhatsTraining, ns.L

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
local function Rows(text)
	UI.lastScan, UI.lastOverview = nil, nil
	UI:Open(text)
	FlushAll()
	return UI.Results()
end

io.write("[whatstraining: the spells you've still to learn, from What's Training's API]\n")
do
	local save = { api = rawget(_G, "WT_API"), addons = _G.C_AddOns, slash = _G.SlashCmdList.WHATSTRAINING, easy = ns.db.easyMode,
		show = ns.Highlight.Show, spellName = C_Spell.GetSpellName, trainers = ns.Pipes.Trainers, title = C_QuestLog.GetTitleForQuestID }
	local loaded = false
	_G.C_AddOns = setmetatable({ IsAddOnLoaded = function(n) return n == "WhatsTraining" and loaded end },
		{ __index = save.addons })
	ns.db.easyMode = false
	UI:EasyChanged()

	-- without What's Training: no @training, .integrations says so, its questions aren't asked, the hint says to install it
	check(not ns.providers.training and ns:ResolveProvider("training") == nil, "without What's Training: no @training")
	check(WT.Status() == L["not found"], ".integrations: not found: " .. tostring(WT.Status()))
	check(WT.Q.Question("what can i train") == nil, "without it: its question isn't asked")
	I.ForgetHint()
	check(I.MissingHint("@training") == L["Install %s for this."]:format("|cff" .. ns.Theme.Get().text .. "What's Training|r"),
		"@training without it: install What's Training (its name as it's written): " .. tostring(I.MissingHint("@training")))
	ns.db.easyMode = true
	I.ForgetHint()
	check(I.MissingHint("what can i train") ~= nil and I.MissingHint("what can i train"):find("What's Training", 1, true),
		"Simple mode: \"what can i train\" says to install it")
	I.ForgetHint()
	check(I.MissingHint("trainer") == nil or not I.MissingHint("trainer"):find("What's Training", 1, true), "\"trainer\" is Questie's, not What's Training's")
	ns.db.easyMode = false
	-- an old What's Training, without the API: said so, and the hint says to update it
	loaded = true
	check(WT.Status():find("update What's Training", 1, true), "an old What's Training: update it: " .. WT.Status())
	I.ForgetHint()
	check(I.MissingHint("@training"):find(L["Update %s for this."]:sub(1, 6), 1, true), "the hint: update it: " .. tostring(I.MissingHint("@training")))
	I.Setup(); FlushAll()
	check(not ns.providers.training, "an old What's Training: no @training (nothing it could read)")

	-- What's Training's API, as Api.lua makes it
	local Status = { AVAILABLE = "available", MISSINGREQS = "missingReqs", NEXTLEVEL = "nextLevel", NOTLEVEL = "notLevel",
		MISSINGTALENT = "missingTalent", IGNORED = "ignored", IGNORED_PET = "ignoredPet", KNOWN = "known", KNOWN_PET = "knownPet",
		PET = "pet", WEAPON_AVAILABLE = "weaponAvailable", WEAPON_NEXTLEVEL = "weaponNextLevel", WEAPON_NOTLEVEL = "weaponNotLevel",
		WEAPON_KNOWN = "weaponKnown", WEAPON_IGNORED = "weaponIgnored" }
	local Event = { READY = "Ready", SPELLS_CHANGED = "SpellsChanged", LEVEL_CHANGED = "LevelChanged", IGNORED_CHANGED = "IgnoredChanged" }
	local function S(id, name, rank, level, status, cost, extra)
		local s = { id = id, name = name, subText = rank, level = level, status = status, cost = cost, baseCost = cost,
			icon = "Interface\\Icons\\Spell_Fire_FlameBolt", quest = false, isItem = false }
		for k, v in pairs(extra or {}) do s[k] = v end
		return s
	end
	local spells = {
		S(118, "Polymorph", "Rank 1", 8, "known", 0),
		S(143, "Fireball", "Rank 2", 6, "available", 100),
		S(543, "Fire Ward", "Rank 1", 4, "available", 0, { quest = true }),
		S(227, "Staves", nil, 1, "weaponAvailable", 1000),
		S(145, "Fireball", "Rank 3", 12, "missingReqs", 600, { requiredIds = { 143 } }),
		S(7300, "Frost Armor", "Rank 2", 10, "nextLevel", 900),
		S(12824, "Polymorph", "Rank 2", 20, "notLevel", 1800, { requiredIds = { 118 }, baseCost = 2000 }),
		S("i:21214", "Frostbolt", "Rank 11", 60, "notLevel", 0, { isItem = true, itemId = 21214 }),
		S(17253, "Bite", "Rank 1", 1, "pet", 0),
		S(12505, "Pyroblast", "Rank 2", 24, "missingTalent", 2200, { requiredTalentId = 11366 }),
		S(130, "Slow Fall", nil, 12, "ignored", 700),
		S(1180, "Daggers", nil, 1, "weaponKnown", 0),
	}
	local ready, callbacks = true, {}
	local api = { version = 1, Status = Status, Event = Event }
	api.IsReady = function() return ready end
	api.GetSpells = function() return ready and spells or {} end
	api.IsIgnored = function(id) return id == 130 end
	api.GetSource = function(id)
		if id == 227 then
			return { kind = "weaponMaster", cost = 1000, trainers = { { npc = 2704, name = "Hanashi", zoneId = 1637, uiMapId = 1454, x = 40, y = 60 } } }
		elseif id == 543 then
			return { kind = "quest", quests = { 1950 }, level = 4 }
		elseif id == "i:21214" then
			return { kind = "item", itemId = 21214 }
		end
		return { kind = "trainer", cost = 100 }
	end
	api.RegisterCallback = function(owner, ev, fn) callbacks[ev] = callbacks[ev] or {}; table.insert(callbacks[ev], { owner, fn }) end
	local function Fire(ev) for _, c in ipairs(callbacks[ev] or {}) do c[2](ev) end end
	_G.WT_API = api
	C_Spell.GetSpellName = function(id) return ({ [118] = "Polymorph", [143] = "Fireball", [11366] = "Pyroblast" })[id] or save.spellName(id) end
	C_QuestLog.GetTitleForQuestID = function(id) if id == 1950 then return "Get the Scoop" end return save.title and save.title(id) end

	-- What's Training's window: /wt toggles it; it shows a few rows of one view (spells, or weapon skills), its search
	-- narrowing them
	local win, made, filter, view = nil, 0, "", "spells"
	local function Refresh()
		local i = 0
		for _, s in ipairs(spells) do
			local weapon = tostring(s.status):find("^weapon") ~= nil
			local text = (s.name .. (s.subText and (" (" .. s.subText .. ")") or "")):lower()
			if s.status ~= "known" and weapon == (view == "weapons") and (filter == "" or text:find(filter, 1, true)) and i < 3 then
				i = i + 1
				local row = win.rows[i]
				row.currentSpell = { id = s.id, itemId = s.itemId }
				row:Show()
			end
		end
		for k = i + 1, #win.rows do win.rows[k].currentSpell = nil; win.rows[k]:Hide() end
	end
	_G.SlashCmdList.WHATSTRAINING = function()
		if win and win:IsShown() then win:Hide() return end
		if not win then
			made = made + 1
			win = T.Obj("Frame")
			win.rows = { T.Obj("Button"), T.Obj("Button"), T.Obj("Button") }
			win.searchBox = T.Obj("EditBox")
			win.searchBox:SetScript("OnTextChanged", function(self) filter = self.text; Refresh() end)
			win.weaponSkillToggleButton = T.Obj("Button")
			win.weaponSkillToggleButton:Show()
			win.weaponSkillToggleButton.Click = function() view = view == "spells" and "weapons" or "spells"; Refresh() end
			_G.WhatsTrainingFloatingFrame = win
		end
		win:Show()
		Refresh()
	end
	local shown
	ns.Highlight.Show = function(self, target, ...) shown = target return save.show(self, target, ...) end

	WT.ForgetStates()
	I.Setup(); FlushAll()
	local P = ns.providers.training
	check(P and ns:ResolveProvider("training") == P and ns:ResolveProvider("train") == P and ns:ResolveProvider("whatstraining") == P,
		"@training, @train, @whatstraining")
	for _, ev in ipairs({ "Ready", "SpellsChanged", "LevelChanged", "IgnoredChanged" }) do
		check(callbacks[ev] and #callbacks[ev] == 1 and callbacks[ev][1][1] == WT, "listens to What's Training's " .. ev)
	end

	-- the list: learn now first, then needs a rank, next level, later, pet, needs a talent, ignored; the known left out
	local list = ns:GetEntries(P)
	check(Names(list) == "Fire Ward (Rank 1) | Fireball (Rank 2) | Staves | Fireball (Rank 3) | Frost Armor (Rank 2) | Polymorph (Rank 2) | "
		.. "Frostbolt (Rank 11) | Bite (Rank 1) | Pyroblast (Rank 2) | Slow Fall", "What's Training's order, the known left out: " .. Names(list))
	local res = Rows("@training")
	check(Names(res) == Names(list), "@training: the same order: " .. Names(res))
	local function Row(name, rows)
		for _, e in ipairs(rows or list) do if e.name == name then return e end end
	end
	local fb, poly, staves, ward, tome = Row("Fireball (Rank 2)"), Row("Polymorph (Rank 2)"), Row("Staves"), Row("Fire Ward (Rank 1)"), Row("Frostbolt (Rank 11)")
	local SEP = ns.DETAIL_SEP
	check(fb.detail == WT.HEX.now .. L["learn now"] .. "|r" .. SEP .. ns.Money(100), "learn now and its cost: " .. fb.detail)
	check(poly.detail == WT.HEX.later .. L["later"] .. "|r" .. SEP .. L["Lv %s"]:format(20) .. SEP .. ns.Money(1800), "later: its level: " .. poly.detail)
	check(staves.detail:find(L["from %s"]:format(L["a weapon master"]), 1, true) and staves.weapon and ward.detail:find(L["a quest"], 1, true)
		and tome.detail:find(L["an item"], 1, true) and tome.itemID == 21214, "where it's taught, when not your trainer")
	check(Row("Bite (Rank 1)").pet and Row("Slow Fall").state == "ignored" and Row("Pyroblast (Rank 2)").state == "needstalent"
		and Row("Fireball (Rank 3)").state == "needsrank", "each state")
	check(table.concat({ ns.Easy.Verbs(fb) }, "/") == L["show in What's Training"] .. "/" .. L["who teaches it"], "its verbs")
	check(fb.shareLink(fb) == "[Fireball] Rank 2, " .. L["level %d"]:format(6) .. ", " .. ns.Money(100, true), "to chat (the row menu): " .. fb.shareLink(fb))
	-- (0.53.9, the player: "an option to pinpoint the NPC that does the training") Shift+Enter: who teaches it
	UI:Open("@training")
	FlushAll()
	fb.secondary(fb)
	check(UI.edit:GetText() == "Fireball (Rank 2) > learn" and fb.secondaryStaysOpen and not fb.secondarySecure,
		"Shift+Enter: who teaches it (> learn), the terminal kept open: " .. UI.edit:GetText())
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("what can i train"); FlushAll()
	fb.secondary(fb)
	check(UI.edit:GetText() == "where to learn Fireball (Rank 2)", "Simple mode: its words: " .. UI.edit:GetText())
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Hide(); FlushAll()
	check(ns.Easy.BY_ID.spells and table.concat(ns.Easy.BY_ID.spells.kinds, " "):find("training", 1, true), "Simple mode: in Spells")

	-- the tooltip: when, what it needs first, the cost (and without your discount), where it's taught
	local lines = {}
	local tip = setmetatable({}, { __index = function(_, k)
		if k == "SetText" or k == "AddLine" then return function(_, s) lines[#lines + 1] = tostring(s) end end
		if k == "AddDoubleLine" then return function(_, a, b) lines[#lines + 1] = tostring(a) .. " = " .. tostring(b) end end
		return function() end
	end })
	poly.tooltip(poly, tip)
	local text = table.concat(lines, "\n")
	check(text:find(L["You can learn it at level %d"]:format(20), 1, true) and text:find(L["Needs first: %s"]:format("Polymorph"), 1, true)
		and text:find(L["Costs"] .. " = " .. ns.Money(1800), 1, true) and text:find(L["%s without your discount"]:format(ns.Money(2000)), 1, true)
		and text:find(L["Taught by your class trainer"], 1, true) and text:find(L["Enter: show in What's Training"]:sub(1, 10), 1, true),
		"Polymorph's tooltip: " .. text)
	lines = {}
	staves.tooltip(staves, tip)
	check(table.concat(lines, "\n"):find(L["Weapon masters: %s"]:format("Hanashi"):sub(1, -1), 1, true) ~= nil
		or table.concat(lines, "\n"):find("Hanashi", 1, true) ~= nil, "a weapon skill's tooltip names its weapon master: " .. table.concat(lines, "\n"))
	lines = {}
	ward.tooltip(ward, tip)
	check(table.concat(lines, "\n"):find(L["From a quest: %s"]:format("Get the Scoop"), 1, true), "a quest's spell: its quest named: " .. table.concat(lines, "\n"))
	lines = {}
	Row("Pyroblast (Rank 2)").tooltip(Row("Pyroblast (Rank 2)"), tip)
	check(table.concat(lines, "\n"):find(L["Needs the talent: %s"]:format("Pyroblast"), 1, true), "the talent it needs")

	-- Enter: What's Training's window opens (/wt) and its row for the spell is pointed at
	shown = nil
	fb.activate(fb); FlushAll()
	check(made == 1 and win:IsShown() and shown and shown.currentSpell and shown.currentSpell.id == 143, "Enter opens What's Training on Fireball")
	check(filter == "", "on show: no search typed in What's Training")
	-- a spell past the rows on show: its search set to its name, then it's there
	shown = nil
	local slow = Row("Slow Fall")
	slow.activate(slow); FlushAll()
	check(win:IsShown() and filter == "slow fall" and shown and shown.currentSpell.id == 130, "not on show: its search narrowed to it, then pointed at")
	-- a weapon skill: the other view
	shown = nil
	win.searchBox:SetText("")
	staves.activate(staves); FlushAll()
	check(view == "weapons" and shown and shown.currentSpell.id == 227, "a weapon skill: the weapon skills' view, then pointed at")
	-- a grimoire: its item
	shown = nil
	view = "spells"; win.searchBox:SetText("")
	tome.activate(tome); FlushAll()
	check(shown and shown.currentSpell.itemId == 21214, "a grimoire: its row (by its item) pointed at")
	-- closed: opened again (not toggled shut)
	win:Hide()
	shown = nil
	fb.activate(fb); FlushAll()
	check(made == 1 and win:IsShown() and shown and shown.currentSpell.id == 143, "closed: opened again on it")
	-- What's Training without its window: said so
	local slash = _G.SlashCmdList.WHATSTRAINING
	_G.SlashCmdList.WHATSTRAINING = nil
	win:Hide()
	local printed = {}
	local pr = ns.Print
	ns.Print = function(_, s) printed[#printed + 1] = s end
	fb.activate(fb); FlushAll()
	ns.Print = pr
	check(printed[1] == L["What's Training's window isn't ready yet."], "no /wt: said so: " .. tostring(printed[1]))
	_G.SlashCmdList.WHATSTRAINING = slash

	-- filters
	check(Names(Rows("@training is:learnable")) == "Fire Ward (Rank 1) | Fireball (Rank 2) | Staves", "is:learnable: now")
	check(Names(Rows("@training is:nextlevel")) == "Frost Armor (Rank 2)", "is:nextlevel")
	check(Names(Rows("@training is:later")) == "Polymorph (Rank 2) | Frostbolt (Rank 11)", "is:later")
	check(Names(Rows("@training is:weapon")) == "Staves", "is:weapon")
	check(Names(Rows("@training is:pet")) == "Bite (Rank 1)", "is:pet")
	check(Names(Rows("@training is:quest")) == "Fire Ward (Rank 1)", "is:quest: taught by a quest")
	check(Names(Rows("@training is:needstalent")) == "Pyroblast (Rank 2)" and Names(Rows("@training is:needsrank")) == "Fireball (Rank 3)",
		"is:needstalent, is:needsrank")
	check(Names(Rows("@training is:ignored")) == "Slow Fall", "is:ignored")
	check(Names(Rows("@training lvl:20")) == "Polymorph (Rank 2)", "lvl: its level")
	check(Names(Rows("@training lvl:60")) == "Frostbolt (Rank 11)", "a grimoire's lvl: the level What's Training says")
	local vals = table.concat(ns.Filters.ValuesFor("is", "@training "), " ")
	check(vals:find("nextlevel", 1, true) and vals:find("learnable", 1, true) and vals:find("weapon", 1, true) and not vals:find("vendor", 1, true),
		"Tab after @training is: offers its values: " .. vals)
	-- "| sum cost": what learning them all costs
	local r = Rows("@training is:learnable | sum cost")
	check(#r == 1 and r[1].name == ns.Gold.Text(1100), "| sum cost: " .. tostring(r[1] and r[1].name))

	-- the questions
	local Q = WT.Q
	local q = Q.Question("what can i train")
	check(q and q.state == "now", "\"what can i train\": what you can learn now")
	local rows, note = Q.Answer(q)
	check(Names(rows) == "Fire Ward (Rank 1) | Fireball (Rank 2) | Staves" and note:find(L["%d to learn now"]:format(3), 1, true)
		and note:find(ns.Money(1100), 1, true), "its answer and note: " .. Names(rows) .. " / " .. tostring(note))
	check(ns.QuestionToAdvanced("what can i train") == "@training is:learnable ", "as Advanced: " .. tostring(ns.QuestionToAdvanced("what can i train")))
	q = Q.Question("what can i learn")
	check(q and q.state == "now", "\"what can i learn\" (no recipe word): What's Training's")
	q = Q.Question("what do i learn next level")
	check(q and Names((Q.Answer(q))) == "Frost Armor (Rank 2)", "\"what do i learn next level\"")
	check(ns.QuestionToAdvanced("what do i learn next level") == "@training is:nextlevel ", "as Advanced: is:nextlevel")
	q = Q.Question("spells at level 20")
	check(q and q.level == 20 and Names((Q.Answer(q))) == "Polymorph (Rank 2)", "\"spells at level 20\"")
	q = Q.Question("weapon skills to learn")
	check(q and Names((Q.Answer(q))) == "Staves", "\"weapon skills to learn\"")
	q = Q.Question("when do i learn polymorph")
	check(q and Names((Q.Answer(q))) == "Polymorph (Rank 2)", "\"when do i learn polymorph\"")
	q = Q.Question("how much is training")
	rows, note = Q.Answer(q or {})
	check(q and q.money and note:find(ns.Money(1100), 1, true), "\"how much is training\": what learning now costs: " .. tostring(note))
	check(ns.QuestionToAdvanced("how much is training") == "@training is:learnable | sum cost ", "as Advanced: the sum")
	q = Q.Question("ignored spells")
	check(q and Names((Q.Answer(q))) == "Slow Fall", "\"ignored spells\": only when asked")
	check(Q.Question("my training") and Names((Q.Answer(Q.Question("my training")))):find("Slow Fall", 1, true) == nil,
		"\"my training\": everything but the ignored")
	check(Q.Question("recipes i can learn") == nil and Q.Question("where is the trainer") == nil and Q.Question("nearest trainer") == nil
		and Q.Question("training") == nil and Q.Question("what can i train in moonglade") == nil and Q.Question("@training") == nil,
		"not its questions: recipes, trainers, a word alone, words naming none of its spells, Advanced syntax")
	check(ns.MissingRecipes == nil or ns.MissingRecipes.Question("what can i learn") == nil, "\"what can i learn\" isn't the recipes'")
	check(ns.Spells == nil or ns.Spells.Question("spells to learn") == nil, "\"spells to learn\" isn't Spells.lua's")
	-- (in Simple mode, typed)
	ns.db.easyMode = true; UI:EasyChanged()
	res = Rows("what can i train")
	check(Names(res) == "Fire Ward (Rank 1) | Fireball (Rank 2) | Staves", "Simple mode: answered as typed: " .. Names(res))
	ns.db.easyMode = false; UI:EasyChanged()
	-- nothing now: when the next is
	local now = {}
	for i, s in ipairs(spells) do now[i] = s.status; if s.status == "available" or s.status == "weaponAvailable" then s.status = "notLevel" end end
	Fire("SpellsChanged"); FlushAll()
	rows = Q.Answer({ state = "now", words = {} })
	check(#rows == 1 and rows[1].name == L["Nothing to train right now: the next at level %d"]:format(1), "nothing now: the next level said: " .. Names(rows))
	for i, s in ipairs(spells) do s.status = now[i] end
	Fire("SpellsChanged"); FlushAll()

	-- > learn: who teaches it (your class's trainers, the nearest first; a weapon master; a quest; with none known, said so)
	local trainers = {
		{ key = 331, npcID = 331, kind = "npc", name = "Maginor Dumas", detail = "Mage Trainer" },
		{ key = 5497, npcID = 5497, kind = "npc", name = "Jennea Cannon", detail = "Mage Trainer" },
	}
	local asked
	ns.Pipes.Trainers = function(word) asked = word return word == "class" and trainers or {} end
	ns.Pipes.ClearSteps()
	res = Rows("fireball (rank 2) > learn")
	check(asked == "class" and Names(res) == "Jennea Cannon | Maginor Dumas", "> learn: your class's trainers: " .. Names(res))
	check(res[1].detail:find(L["Teaches it"], 1, true) and res[1].detail:find(L["costs %s"]:format(ns.Money(100)), 1, true), "each says it teaches it, and the cost: " .. res[1].detail)
	res = Rows("bite > learn")
	check(asked == "pet" and #res == 1 and res[1].name == L["Taught by a pet trainer"], "a pet ability: the pet trainers (none known: said so): " .. Names(res))
	res = Rows("staves > learn")
	check(Names(res) == "Hanashi" and res[1].detail:find(L["Teaches it"], 1, true), "a weapon skill: its weapon master: " .. Names(res))
	-- (Questie doesn't know him: Enter pins his spot, What's Training's, on the map)
	local said, pinned = {}, nil
	local pr2, map = ns.Print, rawget(_G, "C_Map")
	ns.Print = function(_, s) said[#said + 1] = s end
	_G.C_Map = setmetatable({ SetUserWaypoint = function(pt) pinned = pt return true end }, { __index = map })
	check(ns.Easy.Verbs(res[1]) == L["set waypoint"], "its verb: set waypoint")
	res[1].activate(res[1])
	ns.Print, _G.C_Map = pr2, map
	check(pinned and pinned.uiMapID == 1454 and said[1] and said[1]:find("Hanashi", 1, true), "Enter: the map pin on his spot, said: " .. tostring(said[1]))
	res = Rows("fire ward > learn")
	check(Names(res) == "Get the Scoop" and res[1].detail == L["Its quest"], "a quest's spell: its quest: " .. Names(res))
	ns.db.easyMode = true; UI:EasyChanged()
	res = Rows("where to learn staves")
	check(Names(res) == "Hanashi", "Simple mode: \"where to learn staves\": " .. Names(res))
	ns.db.easyMode = false; UI:EasyChanged()
	res = Rows("fireball > learn")
	check(res[1] and res[1].name:find("2", 1, true) and Names(res):find("Fireball (Rank 3)", 1, true), "two ranks: which one? " .. Names(res))
	ns.Pipes.Trainers = save.trainers
	ns.Pipes.ClearSteps()

	-- (0.53.9, the player: "dagger trainer", "daggers trainer", "where do i learn daggers" listed no one, Daggers being a
	-- skill you know) the weapon masters who teach a weapon skill, What's Training's, as Questie's NPCs: each pointed at
	-- on the map with Enter
	do
		local was = { npcRow = I.NpcRow, npcField = I.NpcField, here = I.Here, dist = I.NpcDistance, getSource = api.GetSource }
		local NPCS = {
			{ npcID = 2704, key = 2704, kind = "npc", name = "Hanashi", sub = "Weapon Master" },
			{ npcID = 11868, key = 11868, kind = "npc", name = "Sayoc", sub = "Weapon Master" },
			{ npcID = 3000, key = 3000, kind = "npc", name = "Other Master", sub = "Weapon Master" },
			{ npcID = 331, key = 331, kind = "npc", name = "Maginor Dumas", sub = "Mage Trainer" },
		}
		local BY, DIST = {}, { [2704] = 300, [11868] = 40, [3000] = 10, [331] = 5 }
		for _, n in ipairs(NPCS) do BY[n.key] = n end
		ns:RegisterProvider("npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = function() return NPCS end })
		ns:AliasesChanged()
		I.NpcRow = function(id) return BY[id] end
		I.NpcField = function(id, f)
			if f == "friendlyToFaction" then return "AH" end
			if f == "subName" then return BY[id] and BY[id].sub end
		end
		I.Here = function() return { cont = 1, x = 0, y = 0 } end
		I.NpcDistance = function(id) return DIST[id] end
		api.GetSource = function(id)
			if id == 1180 then
				return { kind = "weaponMaster", cost = 0, trainers = { { npc = 2704, name = "Hanashi", zoneId = 1637, uiMapId = 1454, x = 40, y = 60 },
					{ npc = 11868, name = "Sayoc", zoneId = 1637, uiMapId = 1454, x = 81, y = 19 } } }
			end
			return was.getSource(id)
		end
		ns.Pipes.ClearSteps(); ns.Pipes.ForgetTrainers()
		check(ns.Filters.WeaponSkillIds("dagger")[1] == 1180 and ns.Filters.WeaponSkillIds("swords")[2] == 202 and ns.Filters.WeaponSkillIds("dag") == nil,
			"the words for weapon skills")
		check(Names(Rows("@npc trainer:daggers")) == "Hanashi | Sayoc", "trainer:daggers: the weapon masters who teach it, not the others: "
			.. Names(Rows("@npc trainer:daggers")))
		check(Row("Daggers", ns:GetEntries(P)) == nil and WT.Known()[1] and WT.Known()[1].name == "Daggers" and WT.Known()[1].state == "known",
			"Daggers, known: not listed, kept apart")
		UI:Hide(); FlushAll() -- (the Advanced line shown would make the next Simple one Advanced too: UI:AutoAdvanced)
		ns.db.easyMode = true; UI:EasyChanged()
		for _, said in ipairs({ "dagger trainer", "daggers trainer", "nearest dagger trainer" }) do
			local got = UI:SearchText(said)
			local names = {}
			for _, e in ipairs(got) do if e.kind == "npc" then names[#names + 1] = e.name end end
			table.sort(names)
			check(table.concat(names, " | ") == "Hanashi | Sayoc", "Simple mode \"" .. said .. "\": its weapon masters: " .. table.concat(names, " | "))
		end
		-- (0.53.10, the player: in Orgrimmar, "daggers trainer" listed Sayoc, not Undercity's Archibald) one on another
		-- continent (no distance): listed too, after the nearest
		DIST[2704] = nil
		for _, said in ipairs({ "daggers trainer", "nearest dagger trainer" }) do
			local got = UI:SearchText(said)
			local names = {}
			for _, e in ipairs(got) do if e.kind == "npc" then names[#names + 1] = e.name end end
			check(table.concat(names, " | ") == "Sayoc | Hanashi", "\"" .. said .. "\": the one on another continent too, after: " .. table.concat(names, " | "))
		end
		local inn = UI:SearchText("nearest mage trainer")
		check(#inn == 1 and inn[1].name == "Maginor Dumas", "(a class trainer: as before)")
		DIST[2704] = 300
		check(ns.Easy.ToAdvanced("dagger trainer"):find("trainer:dagger", 1, true), "as Advanced: trainer:dagger: " .. ns.Easy.ToAdvanced("dagger trainer"))
		for _, said in ipairs({ "where do i learn daggers", "where do i learn dagger", "who trains daggers", "where can i train daggers" }) do
			local got = UI:SearchText(said)
			check(Names(got) == "Sayoc | Hanashi", "\"" .. said .. "\": its weapon masters, the nearest first: " .. Names(got))
		end
		local got = UI:SearchText("where do i learn daggers")
		check(got[1].detail:find("^40 yd") and got[1]._dist == 40, "how far each is: " .. tostring(got[1].detail))
		-- pinpointed: Questie's NPC, so Enter shows it on the map (with Questie's marker), Shift+Enter targets it
		check(rawget(got[1], "key") == nil and got[1].key == 11868 and got[1].kind == "npc" and ns.Easy.Verbs(got[1]) == L["show on map"],
			"each is Questie's NPC: Enter shows it on the map: " .. tostring(ns.Easy.Verbs(got[1])))
		ns.db.easyMode = false; UI:EasyChanged()
		-- without What's Training's word on it (a weapon it doesn't list for you): Terminal's own copy of its list (0.54.1)
		api.GetSource = function(id) if id == 1180 then return nil end return was.getSource(id) end
		check(Names(Rows("@npc trainer:daggers")) == "Sayoc", "not listed for you: Terminal's copy of the list (Sayoc teaches daggers): "
			.. Names(Rows("@npc trainer:daggers")))
		api.GetSource = was.getSource
		drop("npc")
		I.NpcRow, I.NpcField, I.Here, I.NpcDistance = was.npcRow, was.npcField, was.here, was.dist
		ns.Pipes.ClearSteps(); ns.Pipes.ForgetTrainers()
	end

	-- What's Training's callbacks: the list made again
	spells[2].status = "known"
	Fire("SpellsChanged"); FlushAll()
	check(Row("Fireball (Rank 2)", ns:GetEntries(P)) == nil, "a spell learned (SpellsChanged): gone from the list")
	spells[2].status = "available"
	Fire("LevelChanged"); FlushAll()
	check(Row("Fireball (Rank 2)", ns:GetEntries(P)) ~= nil, "LevelChanged: made again")
	-- still reading: the lead row says so
	ready = false
	Fire("SpellsChanged"); FlushAll()
	res = Rows("@training")
	check(res[1] and res[1].name == L["What's Training is still reading your spells: a moment"], "not ready: said so: " .. Names(res))
	ready = true
	Fire("Ready"); FlushAll()
	check(#ns:GetEntries(P) == 10, "Ready: the list")

	-- the tour's step: a question with an answer for you (what you can train now; else next level; else all of it)
	check(ns.Tour.TrainingText() == "what can i train", "the tour: what can i train")
	local was = {}
	for i, s in ipairs(spells) do was[i] = s.status; if s.status == "available" or s.status == "weaponAvailable" then s.status = "notLevel" end end
	Fire("SpellsChanged"); FlushAll()
	check(ns.Tour.TrainingText() == "what do i learn next level", "nothing now: what do i learn next level")
	for _, s in ipairs(spells) do if s.status == "nextLevel" then s.status = "notLevel" end end
	Fire("SpellsChanged"); FlushAll()
	check(ns.Tour.TrainingText() == "my training", "nothing next level either: all of it")
	for i, s in ipairs(spells) do s.status = was[i] end
	Fire("SpellsChanged"); FlushAll()

	-- .integrations, the hint gone, the examples and the tour
	check(WT.Status():find(L["found (%s). %d spells to learn, %d now"]:sub(1, 5), 1, true) and WT.Status():find("9 ", 1, true)
		and WT.Status():find("3 ", 1, true), ".integrations: " .. WT.Status())
	I.ForgetHint()
	check(I.MissingHint("@training") == nil, "with it: no hint")
	check(ns.Easy.HasForExample("WhatsTraining"), "its examples are offered")
	local has = false
	for _, x in ipairs(ns.Easy.SIMPLE) do if x[1] == "what can i train" and x[2] == "WhatsTraining" then has = true end end
	check(has, "\"what can i train\" among the examples")

	-- put back: What's Training gone
	drop("training")
	I.whatstraining.on = false
	WT.ForgetStates()
	_G.WT_API, _G.C_AddOns, _G.SlashCmdList.WHATSTRAINING, _G.WhatsTrainingFloatingFrame = save.api, save.addons, save.slash, nil
	ns.Highlight.Show = save.show
	C_Spell.GetSpellName, C_QuestLog.GetTitleForQuestID = save.spellName, save.title
	ns.db.easyMode = save.easy
	UI:EasyChanged()
	I.ForgetHint()
	ns.Pipes.ClearSteps()
	check(not ns.Easy.HasForExample("WhatsTraining"), "gone: its examples aren't offered")
end
