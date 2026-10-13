-- Translations (0.47.11): ns.L gives the English (the key) for any text no language file translates; the language files
-- load only for their own client language; what's shown is translated, while text Terminal reads back stays English.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local L = ns.L

io.write("[translations: ns.L and the language files]\n")
do
	check(L["Nothing to send"] == "Nothing to send" and L["%d yd"]:format(12) == "12 yd", "a text no file translates: the English")
	-- every language file: nothing for another language, and only strings for its own
	local langs = { "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
	for _, lang in ipairs(langs) do
		local chunk = loadfile("Terminal/Locales/" .. lang .. ".lua")
		check(chunk ~= nil, lang .. ": its file is there")
		if chunk then
			local other = { LOCALE = (lang == "deDE") and "frFR" or "deDE", L = {} }
			chunk("Terminal", other)
			check(next(other.L) == nil, lang .. ": nothing set on another language's client")
			local own = { LOCALE = lang, L = setmetatable({}, { __index = function(_, k) return k end }) }
			local ok, err = pcall(chunk, "Terminal", own)
			local strings = true
			for k, v in pairs(own.L) do if type(k) ~= "string" or type(v) ~= "string" then strings = false end end
			check(ok and strings, lang .. ": loads on its own client, texts only: " .. tostring(err))
		end
	end
	local toc = io.open("Terminal/Terminal.toc"):read("*a")
	local core, first = toc:find("Core\\Core.lua", 1, true), toc:find("Locales\\", 1, true)
	local locale = toc:find("Core\\Locale.lua", 1, true)
	check(core and first and locale and core < first and first < locale,
		"the language files load right after Core.lua (ns.L), before anything uses a text")
	check(not toc:find("Locales\\enUS.lua", 1, true), "enUS.lua (the list for CurseForge) isn't loaded by the game")
end

io.write("[translations: shown translated, read back in English]\n")
do
	-- the distance column: the row's detail keeps "N yd" (List.lua reads it back); the column shows the translation
	local I = ns.Integrations
	local was = { here = I.Here, dist = I.NpcDistance, facing = I.Facing, bearing = I.Bearing, rowDist = I.RowDistance }
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	I.NpcDistance = function() return 133, { cont = 1, x = 133, y = 0 } end
	I.RowDistance = function() return 133, { cont = 1, x = 133, y = 0 } end
	I.Facing = function() return 0 end
	I.Bearing = function() return 0.5 end
	rawset(L, "%d yd", "%d m")
	local list = { setmetatable({ detail = "133 yd  Innkeeper", _dist = 133 }, { __index = { kind = "npc", key = 9001, name = "Bob" } }),
		setmetatable({ detail = "250 yd  Banker", _dist = 250 }, { __index = { kind = "npc", key = 9002, name = "Ann" } }) }
	UI:Open("zzqqxxyy"); T.FlushAll()
	UI.results, UI.sel, UI.offset = list, 1, 0
	UI:Render()
	local r = UI.rows[1]
	check(UI.rows[2].dist:IsShown() and UI.rows[2].dist:GetText() == "250 m" and UI.rows[2].detail:GetText() == "Banker"
		and r.dist:GetText() == "133 m" and r.detail:GetText() == "Innkeeper",
		"the distance column in the client's language: " .. tostring(UI.rows[2].dist:GetText()) .. " / " .. tostring(UI.rows[2].detail:GetText()))
	I.NpcDistance = function() return 120, { cont = 1, x = 120, y = 0 } end -- (walking: the arrow keeps it up)
	UI:SelectionChanged(); UI.sel = 2; UI:SelectionChanged(); UI.sel = 1; UI:SelectionChanged()
	check(r.dist:GetText() == "120 m" and list[1].detail == "120 yd  Innkeeper", "as you walk: translated, the detail still English: "
		.. tostring(r.dist:GetText()) .. " / " .. tostring(list[1].detail))
	UI:Hide(); T.FlushAll()
	rawset(L, "%d yd", nil)
	I.Here, I.NpcDistance, I.Facing, I.Bearing, I.RowDistance = was.here, was.dist, was.facing, was.bearing, was.rowDist

	-- the empty prompt's example: "try:" shown translated; Shift+Right still types the example (SuggestionText reads "try:")
	local E = ns.Easy
	local wasPool, wasDb = E.ExamplePool, ns.db.easyMode
	ns.db.easyMode = true
	rawset(L, "try:", "versuch:")
	UI:Open(""); T.FlushAll()
	local ex = E.Example()
	if type(ex) == "string" and ex:sub(1, 4) == "try:" then
		check(UI.ghost:IsShown() and (UI.ghost:GetText() or ""):sub(1, 8) == "versuch:", "the example's \"try:\" in the client's language: "
			.. tostring(UI.ghost:GetText()))
		check(UI:SuggestionText() == ex:match("^try:%s*(.-)%s*$"):gsub("%s*%b()$", ""), "Shift+Right still types the example itself")
	else
		check(false, "an example starting try: in the empty prompt: " .. tostring(ex))
	end
	UI:Hide(); T.FlushAll()
	rawset(L, "try:", nil)
	ns.db.easyMode, E.ExamplePool = wasDb, wasPool

	-- "link hearthstone" in another language: the action's verb as translated (capitals kept: the German run showed "Im
	-- chat verlinken" and "Im Chat verlinken" both, the verb lowercased no longer matched the menu's own chat-box line)
	do
		local link = E.ACTIONS.link
		local was = { verb = link.verb, label = link.label }
		rawset(L, "link in chat", "im Chat verlinken"); rawset(L, "Link in chat", "Im Chat verlinken")
		link.verb, link.label = L["link in chat"], L["Link in chat"]
		local hearth = { kind = "items", name = "Hearthstone", itemID = 6948, link = "item:6948", secondary = function() end,
			secondarySecure = { macro = function() return "/use item:6948" end } }
		UI:Open(""); T.FlushAll()
		UI.results, UI.sel = { E.ActionView(hearth, link) }, 1
		UI:ShowRowMenu(1)
		local labels = {}
		for _, b in ipairs(_G.TerminalRowMenu.lines) do if b:IsShown() then labels[#labels + 1] = b.fs:GetText() end end
		UI:HideRowMenu(); UI:Hide(); T.FlushAll()
		local links = 0
		for _, l in ipairs(labels) do if ns.Lower(l) == "im chat verlinken" then links = links + 1 end end
		check(labels[1] == "Im Chat verlinken" and links == 1, "a translated link verb: once, as written: " .. table.concat(labels, ", "))
		link.verb, link.label = was.verb, was.label
		rawset(L, "link in chat", nil); rawset(L, "Link in chat", nil)
	end

	-- a drop of your own: "you" in the client's language, still told apart as yours (the German run showed "you")
	do
		local was = ns.db.lootLog
		local me = ns.CharacterName and ns.CharacterName() or UnitName("player")
		ns.db.lootLog = { { t = time(), id = 2589, link = "|cff1eff00|Hitem:2589::::::::|h[Linen Cloth]|h|r", who = me } }
		rawset(L, "you", "du")
		ns.providers.lootlog._dirty = true
		local row = ns:GetEntries(ns.providers.lootlog)[1]
		check(row and row.mine and row.detail:sub(1, 2) == "du", "your drop: said in your language, still yours: " .. tostring(row and row.detail))
		rawset(L, "you", nil)
		ns.db.lootLog = was
		ns.providers.lootlog._dirty = true
	end

	-- the row menu leaves out its chat-box line when Enter's or Shift+Enter's verb already is one: both sides translated
	-- alike (RowMenu compares L[...] with Easy's verbs: an English literal on one side breaks it in every other language)
	for _, f in ipairs({ "Search/Easy.lua", "UI/RowMenu.lua" }) do
		local src = io.open("Terminal/" .. f):read("*a")
		local bare = 0
		for line in src:gmatch("[^\n]+") do
			local code = line:gsub("%-%-.*$", "")
			for _, w in ipairs({ "link in chat", "put in the chat box" }) do
				local plain = code:gsub('L%["' .. w:gsub("%p", "%%%0") .. '"%]', "")
				if plain:find('"' .. w .. '"', 1, true) then bare = bare + 1 end
			end
		end
		check(bare == 0, f .. ": the chat-box verbs only as L[...] (" .. bare .. " English literals)")
	end
end

io.write("[translations: the game's own words (another client's language)]\n")
do
	local F, E = ns.Filters, ns.Easy
	local G = _G
	local save = { inst = C_Item.GetItemInfoInstant, info = C_Item.GetItemInfo, sub = C_Item.GetItemSubClassInfo,
		cls = C_Item.GetItemClassInfo, locale = ns.LOCALE, easy = ns.db.easyMode }
	local globals = { "ITEM_QUALITY2_DESC", "ITEM_QUALITY3_DESC", "INVTYPE_CLOAK", "INVTYPE_HAND", "INVTYPE_1HWEAPON", "TANK",
		"HEALER", "DAMAGER", "FACTION_STANDING_LABEL8", "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE", "BACKSLOT" }
	local was = {}
	for _, g in ipairs(globals) do was[g] = G[g] end
	-- a German client: the game's names in German, its numbers as ever
	local ITEMS = {
		[9101] = { "Kurzschwert", "Waffe", "Einhandschwerter", "INVTYPE_WEAPON", 2, 7, 3 },
		[9102] = { "Grober Umhang", "Rüstung", "Stoff", "INVTYPE_CLOAK", 4, 1, 2 },
		[9103] = { "Lederhandschuhe", "Rüstung", "Leder", "INVTYPE_HAND", 4, 2, 3 },
	}
	C_Item.GetItemInfoInstant = function(id)
		local t = ITEMS[id]
		if t then return id, t[2], t[3], t[4], 1, t[5], t[6] end
		return save.inst(id)
	end
	C_Item.GetItemInfo = function(id)
		local t = ITEMS[id]
		if t then return t[1], "|Hitem:" .. id .. "|h[" .. t[1] .. "]|h", t[7], 10, 5, t[2], t[3], 1, t[4], 1, 0, t[5], t[6], 2 end
		return save.info(id)
	end
	F.ClearCache()
	local sword = { kind = "items", itemID = 9101, name = "Kurzschwert" }
	local cloak = { kind = "items", itemID = 9102, name = "Grober Umhang" }
	local gloves = { kind = "items", itemID = 9103, name = "Lederhandschuhe" }
	-- English words in any client: by the game's numbers and slot types
	check(F.Parse("type:sword")(sword) and F.Parse("type:swords")(sword) and not F.Parse("type:sword")(cloak)
		and F.Parse("type:weapon")(sword) and F.Parse("type:cloth")(cloak) and F.Parse("type:armor")(gloves),
		"type: English words on a German client (the game's numbers)")
	G.INVTYPE_CLOAK, G.INVTYPE_HAND = "Rücken", "Hände"
	F.ClearCache()
	check(F.Parse("slot:back")(cloak) and F.Parse("slot:cloak")(cloak) and F.Parse("slot:hands")(gloves)
		and F.Parse("slot:gloves")(gloves) and not F.Parse("slot:back")(gloves), "slot: back and hands on a German client (slot types)")
	check(F.Parse("type:einhandschwerter")(sword) and F.Parse("slot:rücken")(cloak), "the client's own names still work")
	-- the game's words in Simple mode
	G.ITEM_QUALITY2_DESC, G.ITEM_QUALITY3_DESC, G.BACKSLOT = "Selten", "Rar", "Rücken"
	G.TANK, G.HEALER, G.DAMAGER, G.FACTION_STANDING_LABEL8 = "Tank", "Heiler", "Schaden", "Ehrfürchtig"
	G.LOCALIZED_CLASS_NAMES_MALE, G.LOCALIZED_CLASS_NAMES_FEMALE = { WARRIOR = "Krieger" }, { WARRIOR = "Kriegerin" }
	C_Item.GetItemSubClassInfo = function(c, s) return (c == 2 and s == 7) and "Einhandschwerter" or (c == 4 and s == 1) and "Stoff" or nil end
	C_Item.GetItemClassInfo = function(c) return c == 2 and "Waffe" or c == 4 and "Rüstung" or nil end
	ns.LOCALE = "deDE"; E.ForgetGameWords()
	check(E.GameWord("rar") == "q:3" and E.WORDS["selten"] == "q:2" and E.WORDS["rücken"] == "slot:back"
		and E.WORDS["hände"] == "slot:hands" and E.WORDS["einhandschwerter"] == "type:sword" and E.WORDS["waffe"] == "type:weapon"
		and E.WORDS["heiler"] == "is:healer" and E.WORDS["ehrfürchtig"] == "standing:8" and E.WORDS["krieger"] == "trainer:warrior"
		and E.WORDS["kriegerin"] == "trainer:warrior",
		"the game's words: quality, slot, kind, role, standing, class: " .. tostring(E.WORDS["rar"]) .. " " .. tostring(E.WORDS["rücken"]))
	check(rawget(E.WORDS, "rar") == nil and E.WORDS.rare == "q:rare" and E.WORDS.zzz == nil, "English's own words first; others nothing")
	ns.db.easyMode = true
	local rar = E.Word("rar")
	check(rar and rar(sword) and not rar(cloak) and E.Word("rücken")(cloak) and not E.Word("rücken")(sword),
		"Simple mode: \"rar\" passes the rare sword, \"rücken\" the cloak")
	check(E.Word("einhandschwerter")(sword) and E.Word("waffe")(sword), "Simple mode: a weapon by its kind's name")
	check(E.Word("heiler")({ kind = "talents", name = "Ann", text = "Priester Heiler" }) and not E.Word("heiler")(sword),
		"a game word still finds what the word alone did (its name or text has it)")
	local trainer = { kind = "npc", key = 9201, name = "Bob", sub = "Warrior Trainer" }
	local mage = { kind = "npc", key = 9202, name = "Ann", sub = "Mage Trainer" }
	check(F.Parse("trainer:krieger")(trainer) and not F.Parse("trainer:krieger")(mage) and E.Word("krieger")(trainer),
		"trainer: and Simple's word in the client's language (Questie's titles are English)")
	ns.LOCALE = "enUS"; E.ForgetGameWords()
	check(E.WORDS["rücken"] == nil and E.WORDS["rar"] == nil, "an English client: no extra words")
	-- put back
	ns.LOCALE, ns.db.easyMode = save.locale, save.easy; E.ForgetGameWords()
	C_Item.GetItemInfoInstant, C_Item.GetItemInfo, C_Item.GetItemSubClassInfo, C_Item.GetItemClassInfo = save.inst, save.info, save.sub, save.cls
	for _, g in ipairs(globals) do G[g] = was[g] end
	F.ClearCache()
end

io.write("[translations: phrases in the client's language]\n")
do
	local E, P = ns.Easy, ns.Pipes
	local save = { easy = ns.db.easyMode, locale = ns.LOCALE, inn = _G.MINIMAP_TRACKING_INNKEEPER }
	check(E.English("nearest innkeeper") == "nearest innkeeper" and E.English("nächster gastwirt") == "nächster gastwirt",
		"nothing translated: every line as it is")
	rawset(L, "phrases: nearest %s", "nächster %s | nächste %s | %s in der Nähe")
	rawset(L, "phrases: mats for %s", "Mats für %s | was brauche ich für %s")
	-- (E.PHRASES read the translations when the file loaded: a test puts them in as a language file would have)
	local wasPh = {}
	for i, ph in ipairs(E.PHRASES) do wasPh[i] = ph[2]; ph[2] = L[ph[2]] or ph[2] end
	E.ForgetPhrases()
	check(E.English("Nächster Gastwirt") == "nearest gastwirt" and E.English("gastwirt in der nähe") == "nearest gastwirt"
		and E.English("Was brauche ich für  Thorium Belt") == "mats for thorium belt", "a phrase in the client's language: its English line: "
		.. tostring(E.English("Nächster Gastwirt")))
	check(E.English("hogger") == "hogger" and E.English("@npc nächster x") == "@npc nächster x" and E.English("nächster") == "nächster",
		"anything else as it is")
	-- the search reads the English line: the same answer either way
	ns.db.easyMode = true
	local a = UI:Search("mats for zzqqyy belt")
	local b = UI:Search("Mats für zzqqyy belt")
	check(a[1] and b[1] and a[1].name == b[1].name and #a == #b, "the search answers the phrase as the English: " .. tostring(b[1] and b[1].name))
	-- Simple mode writes the chain in the client's language (read back the same way)
	check(P.Phrase("Thorium Bar", "mats") == "Mats für Thorium Bar" and P.Phrase("Thorium Bar", "uses") == "what uses Thorium Bar",
		"Simple mode's chain words in the client's language, English where untranslated: " .. P.Phrase("Thorium Bar", "mats"))
	-- Alt+`: "nächster Gastwirt" (the game's word for innkeeper) as Advanced writes "nearest innkeeper"
	_G.MINIMAP_TRACKING_INNKEEPER = "Gastwirt"
	ns.LOCALE = "deDE"; E.ForgetGameWords()
	local want = E.ToAdvanced("nearest innkeeper")
	check(E.ToAdvanced("nächster Gastwirt") == want and E.ROLE_WORDS["gastwirt"], "Alt+`: the phrase and the game's word for the role: "
		.. E.ToAdvanced("nächster Gastwirt") .. " / " .. want)
	-- put back
	ns.LOCALE, ns.db.easyMode, _G.MINIMAP_TRACKING_INNKEEPER = save.locale, save.easy, save.inn
	E.ForgetGameWords()
	for i, ph in ipairs(E.PHRASES) do ph[2] = wasPh[i] end
	rawset(L, "phrases: nearest %s", nil); rawset(L, "phrases: mats for %s", nil)
	E.ForgetPhrases()
end
