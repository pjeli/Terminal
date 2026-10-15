-- (0.51.16, the player's ask) .tour: a few searches to try, one step at a time; on a fresh install the empty prompt's
-- first suggestion is the tour.
local T = ...
local ns, UI, check, FlushAll, key = T.ns, T.UI, T.check, T.FlushAll, T.key
local L = ns.L

io.write("[tour: .tour, and the first suggestion on a fresh install]\n")
do
	local save = { offered = ns.db.tourOffered, history = ns.db.history, easy = ns.db.easyMode }
	-- a fresh install: nothing run yet, the tour never offered
	ns.db.tourOffered, ns.db.history = nil, {}
	ns.Easy.Set(true)
	UI:Open("")
	FlushAll()
	check(UI:SuggestionText() == ".tour", "fresh install: the first suggestion is .tour: " .. tostring(UI:SuggestionText()))
	UI:Hide(); FlushAll()
	UI:Open("")
	FlushAll()
	check(UI:SuggestionText() ~= ".tour", "...once: " .. tostring(UI:SuggestionText()))
	UI:Hide(); FlushAll()
	-- (review, 0.51.25) suggestions off: not spent unseen
	ns.db.tourOffered = nil
	local realGet = ns.Theme.Get
	ns.Theme.Get = function() local t = realGet() local c = {} for k, v in pairs(t) do c[k] = v end c.suggest = false return c end
	UI:Open(""); FlushAll(); UI:Hide(); FlushAll()
	ns.Theme.Get = realGet
	check(not ns.db.tourOffered, "suggestions off: the tour's offer not spent")
	-- someone who has used Terminal: not offered
	ns.db.tourOffered, ns.db.history = nil, { "hearthstone" }
	UI:Open("")
	FlushAll()
	check(UI:SuggestionText() ~= ".tour", "lines run already: no tour offered")
	UI:Hide(); FlushAll()
	ns.db.history = save.history

	-- (0.51.24, the player: the tour showed the Hearthstone every time) your bags' items, and the game's settings
	local saveP, saveO = {}, {}
	for k, v in pairs(ns.providers) do saveP[k] = v end
	for i, v in ipairs(ns.providerOrder) do saveO[i] = v end
	local function drop(id)
		ns.providers[id] = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
	end
	local BAGS = { { name = "Hearthstone", key = 6948, itemID = 6948, firstBag = 0, locs = { { 0, 1 } } },
		{ name = "Bolt of Linen Cloth", key = 2996, itemID = 2996, firstBag = 0, locs = { { 0, 2 } } },
		{ name = "Minor Healing Potion", key = 118, itemID = 118, firstBag = 0, locs = { { 0, 3 } } },
		{ name = "Spiced Wolf Meat", key = 2680, itemID = 2680, firstBag = 0, locs = { { 0, 4 } } },
		{ name = "Large Round Shield", key = 2129, itemID = 2129, firstBag = 0, locs = { { 0, 5 } } },
		{ name = "Worn Shortsword", key = 25, itemID = 25, slotId = 16, locs = {} } }
	local bags = BAGS
	drop("items"); drop("gameoptions")
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, events = {}, collect = function()
		local out = {}
		for i, e in ipairs(bags) do local c = {} for k, v in pairs(e) do c[k] = v end out[i] = c end
		return out
	end })
	ns:RegisterProvider("gameoptions", { label = "Options", aliases = { "option" }, collect = function()
		return { { name = "Display Class Colors", key = "o1" }, { name = "Enable Damage Meter", key = "o2" } }
	end })
	ns:AliasesChanged()
	-- (what the game says of them: the potion and the food are consumables, the food's Well Fed gives Stamina, the shield
	-- is worn in the off hand)
	local realSpell, realRandom, realInstant, realSpellApi = C_Item.GetItemSpell, math.random, C_Item.GetItemInfoInstant, _G.C_Spell
	local INSTANT = { [6948] = { "Miscellaneous", "Junk", "", 15, 0 }, [2996] = { "Trade Goods", "Cloth", "", 7, 5 },
		[118] = { "Consumable", "Potion", "", 0, 1 }, [2680] = { "Consumable", "Food & Drink", "", 0, 5 },
		[2129] = { "Armor", "Shields", "INVTYPE_SHIELD", 4, 6 } }
	C_Item.GetItemInfoInstant = function(id)
		local t = INSTANT[tonumber(id) or 0]
		if t then return id, t[1], t[2], t[3], 1, t[4], t[5] end
		return realInstant(id)
	end
	C_Item.GetItemSpell = function(id)
		if id == 118 or id == 6948 then return "Use", 1 elseif id == 2680 then return "Well Fed", 555 end
	end
	_G.C_Spell = setmetatable({ GetSpellDescription = function(id)
		if id == 555 then return "Restores 61 health over 15 sec. If you spend at least 10 seconds eating you will become well fed and gain 4 Stamina and Spirit for 15 min." end
		if id == 1 then return "Restores 80 health." end
	end, IsSpellDataCached = function() return true end }, { __index = realSpellApi })
	ns.Filters.ClearCache(); ns.Filters.ClearEffects()
	math.random = function(n) return n and 1 or 0.5 end

	-- .tour (from Advanced mode: the tour is in Simple mode): a card above the terminal says what each step shows
	ns.db.easyMode = false
	UI:EasyChanged()
	ns:FindCommand("tour").run("")
	FlushAll()
	local card = ns.Tour.Card()
	check(UI:IsShown() and ns.Tour.StepIndex() == 1 and card and card:IsShown() and card.title:GetText() == L["Welcome to Terminal"]
		and card.head:GetText() == L["Tour: step %d of %d"]:format(1, #ns.Tour.STEPS), ".tour: the welcome card, above the terminal: "
		.. tostring(card and card.title:GetText()))
	check(ns.Easy.On(), "...in Simple mode")
	-- (0.51.21, the player's screenshot: at the top of the screen the card sat over the prompt) no room above: below
	check(UI:SuggestionText() == nil, "no other example in the prompt while the tour's card says what to do")
	local F, at = _G.TerminalFrame, nil
	local realTop, realScreen, realPoint = F.GetTop, UIParent.GetTop, card.SetPoint
	card.SetPoint = function(self, p) at = p end
	F.GetTop, UIParent.GetTop = function() return 760 end, function() return 768 end
	ns.Tour.ShowCard()
	check(at == "TOPLEFT" and ns.Tour.below, "the terminal at the top of the screen: the card below it, not over the prompt: " .. tostring(at))
	F.GetTop = function() return 400 end
	ns.Tour.ShowCard()
	check(at == "BOTTOMLEFT" and not ns.Tour.below, "room above: the card above it")
	F.GetTop, UIParent.GetTop, card.SetPoint = realTop, realScreen, realPoint
	check(tostring(card.keys:GetText()):find(L["Enter: next"], 1, true) and tostring(card.keys:GetText()):find(L["Esc: end the tour"], 1, true),
		"the card says the keys: " .. tostring(card.keys:GetText()))
	-- Enter: the next step, its search typed, the row it's about selected
	key("ENTER")
	FlushAll()
	local sel = UI.Results()[UI.sel]
	check(ns.Tour.StepIndex() == 2 and UI.edit:GetText() == "bolt of linen cloth" and sel and sel.itemID == 2996
		and card.title:GetText() == L["Type to find"], "Enter: step 2, an item from your bags typed (not the Hearthstone), it selected: "
		.. tostring(UI.edit:GetText()) .. " / " .. tostring(sel and sel.name))
	check(UI:IsShown(), "...nothing was used: the terminal is still open")
	key("ENTER")
	FlushAll()
	sel = UI.Results()[UI.sel]
	check(ns.Tour.StepIndex() == 3 and sel and sel.catId ~= nil, "step 3: a category selected: " .. tostring(sel and sel.name))
	-- Shift+Left: back
	_G.IsShiftKeyDown = function() return true end
	key("LEFT")
	_G.IsShiftKeyDown = function() return false end
	FlushAll()
	check(ns.Tour.StepIndex() == 2 and UI.edit:GetText() == "bolt of linen cloth", "Shift+Left: back a step")
	-- typing: the tour ends, the key types
	key("A")
	FlushAll()
	check(not ns.Tour.Active() and not card:IsShown(), "typing: the tour is over, its card gone")
	-- to the end: Enter on the last closes it
	ns.Tour.Start()
	FlushAll()
	for _ = 2, #ns.Tour.STEPS do key("ENTER") FlushAll() end
	check(ns.Tour.StepIndex() == #ns.Tour.STEPS and card.title:GetText() == L["That's it"]
		and tostring(card.keys:GetText()):find(L["Enter: close the tour"], 1, true), "the last step: " .. tostring(card.title:GetText()))
	key("ENTER")
	FlushAll()
	check(not ns.Tour.Active() and not UI:IsShown() and not card:IsShown(), "Enter on the last: the tour and the terminal close")
	-- Esc mid-tour: over
	ns.Tour.Start()
	FlushAll()
	key("ESCAPE")
	FlushAll()
	check(not ns.Tour.Active() and not UI:IsShown() and not ns.Easy.On(), "Esc mid-tour: over, closed, Advanced again")

	-- (0.51.22, the player's ask) Questie's and AtlasLoot's steps (0.51.23: Attune's too): what they bring when installed;
	-- the ones that aren't, named with what installing them adds
	local I = ns.Integrations
	local realMissing, Q = I.AddonMissing, ns.Attune.Q
	local realHow = Q.How
	local function Titles()
		local t = {}
		for _, st in ipairs(ns.Tour.STEPS) do t[#t + 1] = st.title end
		return table.concat(t, " | ")
	end
	local function StepTitled(title)
		for i, st in ipairs(ns.Tour.STEPS) do if st.title == title then return i, st end end
	end
	local function Without(...)
		local gone = {}
		for _, n in ipairs({ ... }) do gone[n] = true end
		I.AddonMissing = function(name) return gone[name] == true end
		ns.Tour.Start()
		FlushAll()
	end
	-- all three: their steps search with them; the Dalaran key's steps (a Horde player: the Sewer Key)
	Q.How = function(t) if t == "how do i get the dalaran key" then return { steps = "Dalaran Sewer Key" } end end
	Without()
	local _, qs = StepTitled(L["The nearest of anything (Questie)"])
	local _, as = StepTitled(L["Upgrades (AtlasLoot)"])
	local _, ts = StepTitled(L["Keys and attunements (Attune)"])
	check(qs and qs.text == "nearest mailbox" and as and as.text == "upgrades" and ts and ts.text == "how do i get the dalaran key",
		"all installed: their steps search with them, Attune's the Dalaran key: " .. Titles())
	check(not StepTitled(L["More with addons"]) and StepTitled(L["Find a setting"]), "...no card to install any; a setting found too")
	UI:Hide(); FlushAll()
	-- an Alliance player: City of Dalaran's quests
	Q.How = function(t) if t == "how do i get attuned to city of dalaran" then return { steps = "City of Dalaran" } end end
	Without()
	_, ts = StepTitled(L["Keys and attunements (Attune)"])
	check(ts and ts.text == "how do i get attuned to city of dalaran", "no Dalaran key for you: City of Dalaran's steps: " .. tostring(ts and ts.text))
	UI:Hide(); FlushAll()
	Q.How = realHow
	-- one missing: its own card
	Without("Attune")
	local ai, as2 = StepTitled(L["Add Attune"])
	check(as2 and as2.text == "" and as2.say:find("Install Attune", 1, true) and not StepTitled(L["Keys and attunements (Attune)"]),
		"Attune missing: a card saying what installing it adds: " .. Titles())
	UI:Hide(); FlushAll()
	-- two missing: one card naming both
	Without("Questie", "AtlasLoot")
	local mi, ms = StepTitled(L["More with addons"])
	check(ms and ms.text == "" and ms.say:find("Questie:", 1, true) and ms.say:find("AtlasLoot:", 1, true) and not ms.say:find("Attune:", 1, true), "Questie and AtlasLoot missing: one card naming both: " .. Titles())
	for _ = 2, mi do key("ENTER") FlushAll() end
	check(ns.Tour.Card().title:GetText() == L["More with addons"] and UI.edit:GetText() == "", "...shown on its card, nothing searched")
	UI:Hide(); FlushAll()
	-- none of them: the card names all three
	Without("Questie", "AtlasLoot", "Attune")
	_, ms = StepTitled(L["More with addons"])
	check(ms and ms.say:find("Attune:", 1, true), "none installed: the card names all three: " .. Titles())
	UI:Hide(); FlushAll()
	I.AddonMissing = realMissing

	-- (0.51.24, the player's ask) a setting found by name, in every tour: one of the game's that's there
	local function Step(title) local _, st = StepTitled(title) return st end
	ns.Tour.Start(); FlushAll()
	local set, use = Step(L["Find a setting"]), Step(L["Say what to do"])
	check(set and set.text == "enable damage meter", "a setting step: one of the settings there (the damage meter): " .. tostring(set and set.text))
	-- (0.51.25, the player: "use elixir of fortitude" is no quicker than your bags) a kind of thing you have, not its name
	check(use and use.text == "use stamina food" and use.say:find("use stamina food", 1, true),
		"say what to do: a kind of thing you have (stamina food), not an item's name: " .. tostring(use and use.text))
	local useAt = StepTitled(L["Say what to do"])
	for _ = 2, useAt do key("ENTER") FlushAll() end
	local usel = UI.Results()[UI.sel]
	check(UI.edit:GetText() == "use stamina food" and usel and usel.itemID == 2680,
		"...typed, the food it found selected: " .. tostring(usel and usel.name))
	UI:Hide(); FlushAll()
	math.random = function(n) return n or 0.5 end
	ns.Tour.STEPS = ns.Tour.Steps()
	check(Step(L["Say what to do"]).text == "equip shield", "...or a kind of gear you have: " .. Step(L["Say what to do"]).text)
	-- no stat food or gear: a plain kind (the potion)
	bags = { BAGS[1], BAGS[2], BAGS[3] }
	ns.providers.items._dirty = true
	ns.Tour.STEPS = ns.Tour.Steps()
	check(Step(L["Say what to do"]).text == "use potion", "no stat food or gear: a plain kind of thing: " .. Step(L["Say what to do"]).text)
	bags = BAGS
	ns.providers.items._dirty = true
	for i = 1, 6 do
		math.random = function(n) return n and ((i - 1) % n) + 1 or 0.5 end
		ns.Tour.STEPS = ns.Tour.Steps()
		check(ns.Tour.STEPS[2].text ~= "hearthstone", "never the Hearthstone while there's something else: " .. ns.Tour.STEPS[2].text)
	end
	math.random = function(n) return n and 1 or 0.5 end
	UI:Hide(); FlushAll()
	-- nothing in your bags but the Hearthstone: it, as before
	bags = { BAGS[1] }
	ns.providers.items._dirty = true
	ns.Tour.Start(); FlushAll()
	check(ns.Tour.STEPS[2].text == "hearthstone" and Step(L["Say what to do"]).text == "use hearthstone", "only the Hearthstone: it")
	UI:Hide(); FlushAll()
	-- (review, 0.51.25) the Hearthstone by its id: a German client's "Ruhestein" left out of step 2 too, and named when
	-- it's all there is
	bags = { { name = "Ruhestein", key = 6948, itemID = 6948, firstBag = 0, locs = { { 0, 1 } } }, BAGS[2] }
	ns.providers.items._dirty = true
	for i = 1, 4 do
		math.random = function(n) return n and ((i - 1) % n) + 1 or 0.5 end
		ns.Tour.STEPS = ns.Tour.Steps()
		check(ns.Tour.STEPS[2].text == "bolt of linen cloth", "never the Hearthstone, whatever it's called: " .. ns.Tour.STEPS[2].text)
	end
	bags = { bags[1] }
	ns.providers.items._dirty = true
	ns.Tour.STEPS = ns.Tour.Steps()
	check(ns.Tour.STEPS[2].text == "ruhestein" and Step(L["Say what to do"]).text == "use ruhestein",
		"only the Hearthstone: by its name in your language: " .. ns.Tour.STEPS[2].text .. " / " .. Step(L["Say what to do"]).text)
	math.random = function(n) return n and 1 or 0.5 end
	bags = BAGS
	ns.providers.items._dirty = true

	-- (review, 0.51.25) the terminal hidden by the game (the game menu's Esc closes every window): the tour and its card go
	ns.Tour.Start(); FlushAll()
	key("ENTER"); FlushAll()
	_G.TerminalFrame:Hide()
	_G.TerminalFrame:GetScript("OnHide")(_G.TerminalFrame) -- (as the game runs it)
	FlushAll()
	check(not ns.Tour.Active() and not ns.Tour.Card():IsShown(), "hidden by the game: the tour over, its card gone")
	UI:Hide(); FlushAll()
	-- (review, 0.51.25) the game's text box has the keys (clicked into, in combat): Enter goes on, Esc ends it, typing too
	ns.Tour.Start(); FlushAll()
	local activated = false
	local realActivate = UI.Activate
	UI.Activate = function() activated = true end
	UI.edit:GetScript("OnEnterPressed")(UI.edit)
	FlushAll()
	check(ns.Tour.StepIndex() == 2 and not activated, "the text box's Enter: the next step, nothing done")
	UI.edit:GetScript("OnKeyDown")(UI.edit, "B")
	check(not ns.Tour.Active(), "...typing there ends it")
	ns.Tour.Start(); FlushAll()
	UI.edit:GetScript("OnEscapePressed")(UI.edit)
	FlushAll()
	check(not ns.Tour.Active() and not UI:IsShown() and not activated, "...Esc there ends it")
	UI.Activate = realActivate
	-- (review, 0.51.25) in a category, Shift+Left is the list's (back to the categories), not the tour's
	ns.Tour.Start(); FlushAll()
	key("ENTER"); FlushAll(); key("ENTER"); FlushAll()
	UI.category = "x"
	check(ns.Tour.Key("LEFT", true) == false and ns.Tour.StepIndex() == 3, "Shift+Left in a category: the list's")
	UI.category = nil
	check(ns.Tour.Key("LEFT", true) == true and ns.Tour.StepIndex() == 2, "...else back a step")
	UI:Hide(); FlushAll()
	-- (review, 0.51.25) the last card says the key that opens Terminal: yours
	local realKey = _G.GetBindingKey
	for _, case in ipairs({ { "`", L["` (under Esc)"] }, { "CTRL-SPACE", "CTRL-SPACE" }, { nil, "/term" } }) do
		_G.GetBindingKey = function(a) if a == "TERMINAL_TOGGLE" then return case[1] end end
		ns.Tour.STEPS = ns.Tour.Steps()
		local last = ns.Tour.STEPS[#ns.Tour.STEPS].say
		check(last:find(case[2], 1, true) == 7, "the last card: " .. tostring(case[1]) .. " -> " .. last)
	end
	_G.GetBindingKey = realKey

	for k in pairs(ns.providers) do ns.providers[k] = nil end
	for k, v in pairs(saveP) do ns.providers[k] = v end
	for i = #ns.providerOrder, 1, -1 do ns.providerOrder[i] = nil end
	for i, v in ipairs(saveO) do ns.providerOrder[i] = v end
	ns:AliasesChanged()
	C_Item.GetItemSpell, math.random, C_Item.GetItemInfoInstant, _G.C_Spell = realSpell, realRandom, realInstant, realSpellApi
	ns.Filters.ClearCache(); ns.Filters.ClearEffects()

	ns.db.tourOffered, ns.db.easyMode = save.offered, save.easy
	UI:EasyChanged()
	UI:Hide(); FlushAll()
end
