-- (1.5.3, the player's ask) DungeonJournal (ForeverDungeonJournal): "Show in Dungeon Journal" in a row's menu (an item
-- it lists, a quest, a dungeon), @favourite (the items starred in it), is:favourite, "my favourites". Its namespace is
-- a global table read defensively; a shape it doesn't have: off, said.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L, I = ns.L, ns.Integrations
local DJ, Q = ns.DungeonJournal, ns.DungeonJournalFavourites
io.write("[dungeonjournal: open in it, its favourites]\n")

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows or {}) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end
local function Unregister()
	ns.providers.favorite = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "favorite" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
end

check(DJ and not DJ.On() and DJ.Target({ kind = "loot", itemID = 2840 }) == nil, "without it: off, no page for a row")
check(not ns.providers.favorite and Q.Question("my favourites") == nil, "without it: no @favourite, no question")
check(I.AddonMissing("ForeverDungeonJournal"), "@favourite's addon: missing")

local save = { addons = _G.C_AddOns, lib = rawget(_G, "ForeverDungeonJournal_NS"), frame = rawget(_G, "ForeverDungeonJournalFrame"),
	cdb = rawget(_G, "ForeverDungeonJournalCharacterDB"), easy = ns.db.easyMode }
local ok, err = pcall(function()
	local loaded = { ForeverDungeonJournal = true }
	_G.C_AddOns = setmetatable({ IsAddOnLoaded = function(n) if loaded[n] ~= nil then return loaded[n] end return save.addons.IsAddOnLoaded(n) end },
		{ __index = save.addons })
	local calls = {}
	local function Log(a, b, c) calls[#calls + 1] = tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) end
	local frame = { shown = false }
	function frame:IsShown() return self.shown end
	function frame:Show() self.shown = true end
	_G.ForeverDungeonJournalFrame = frame
	local SOURCES = { [2840] = { dungeonName = "Hall of Thanes", bossIndex = 2, bossName = "Plunder", mode = "bosses" },
		[2589] = { dungeonName = "Sunken Temple", questID = 1446, questName = "Jammal'an the Prophet", mode = "quests" } }
	local N = {
		DB = { ["Hall of Thanes"] = { quests = { { id = 96395, name = "An Ancient Grudge" } } }, ["Scarlet Monastery: Graveyard"] = {},
			["Scarlet Monastery: Library"] = {}, ["Dire Maul: North"] = {}, ["Sunken Temple"] = { quests = { { id = 1446 } } } },
		ORDER = { "Hall of Thanes", "Scarlet Monastery: Graveyard", "Scarlet Monastery: Library", "Sunken Temple", "Dire Maul: North" },
		INSTANCE_ID_TO_DUNGEON = { [3065] = "Hall of Thanes", [189] = "Scarlet Monastery", [109] = "Sunken Temple" },
		GetItemSource = function(id) return SOURCES[id] end,
		OpenItemSource = function(id) Log("item", id); frame.shown = true; return SOURCES[id] ~= nil end,
		OpenBossPage = function(d, b) Log("boss", d, b) end,
		OpenQuestPage = function(d, q) Log("quest", d, q) end,
		ToggleJournal = function() Log("toggle"); frame.shown = not frame.shown end,
	}
	local favs = {
		["2840"] = { id = 2840, name = "Copper Bar", slot = "Trade Goods", quality = 1, dungeon = "Hall of Thanes", boss = "Plunder" },
		["9999"] = { id = 9999, name = "Gone Cloak", slot = "Back", quality = 3, dungeon = "Sunken Temple", questID = 1446, questName = "Jammal'an the Prophet" },
		["7777"] = { id = 7777, name = "Library Robe", quality = 2, dungeon = "Scarlet Monastery: Library", boss = "Arcanist Doan" },
	}
	N.IsFavouriteItem = function(id) return favs[tostring(id)] ~= nil end
	_G.ForeverDungeonJournal_NS = N
	_G.ForeverDungeonJournalCharacterDB = { favouriteItems = favs }

	-- which of its pages: by the instance's ID, else by name; wings: the first; a raid: none
	check(DJ.On() and DJ.Dungeon(3065, "The Hall of Thanes") == "Hall of Thanes", "by its instance ID: " .. tostring(DJ.Dungeon(3065, "The Hall of Thanes")))
	check(DJ.Dungeon(109, "Temple of Atal'Hakkar") == "Sunken Temple", "its own name for it, by ID: Sunken Temple")
	check(DJ.Dungeon(429, "Dire Maul (North)") == "Dire Maul: North", "a wing named in brackets: its \"Dire Maul: North\"")
	check(DJ.Dungeon(189, "Scarlet Monastery") == "Scarlet Monastery: Graveyard", "one instance of wings: the first of them")
	check(DJ.Dungeon(409, "Molten Core") == nil, "a raid it doesn't list: none")
	-- a row's page
	local t = DJ.Target({ kind = "loot", itemID = 2840 })
	check(t and t.item == 2840, "an item it lists: its page")
	check(DJ.Target({ kind = "items", itemID = 4306 }) == nil, "an item it doesn't list: none")
	t = DJ.Target({ kind = "quests", questID = 96395 })
	check(t and t.dungeon == "Hall of Thanes" and t.quest == 96395, "a quest it lists: its dungeon's quest page")
	t = DJ.Target({ kind = "questie", qid = 1446 })
	check(t and t.dungeon == "Sunken Temple" and t.quest == 1446, "Questie's quest rows too (qid)")
	t = DJ.Target({ kind = "dungeon", name = "Temple of Atal'Hakkar", instanceID = 109 })
	check(t and t.dungeon == "Sunken Temple" and not t.quest, "a dungeon's entrance: its page")
	check(DJ.Target({ kind = "favorite", itemID = 2840 }) == nil, "its own favourites: Enter does it already")

	-- opening: shown first, the page asked again a moment after (it picks its own as it's shown)
	calls = {}
	check(DJ.Open({ dungeon = "Sunken Temple" }) and frame.shown, "a dungeon: opened")
	FlushAll()
	check(calls[1] == "toggle,nil,nil" and calls[2] == "boss,Sunken Temple,nil" and calls[3] == "boss,Sunken Temple,nil" and #calls == 3,
		"the journal shown, the dungeon's page, asked again a moment after: " .. table.concat(calls, " / "))
	calls = {}
	DJ.Open({ dungeon = "Hall of Thanes", quest = 96395 }); FlushAll()
	check(calls[1] == "quest,Hall of Thanes,96395" and #calls == 1, "already shown: its quest page, once: " .. table.concat(calls, " / "))
	frame.shown = false; calls = {}
	check(DJ.Open({ item = 2840 }), "an item: opened")
	FlushAll()
	check(calls[1] == "item,2840,nil" and #calls == 2, "its own opener (it shows the journal itself), again a moment after: " .. table.concat(calls, " / "))
	check(not DJ.Open({ item = 4306 }), "an item it doesn't list: not opened")

	-- @favourite
	DJ.Setup()
	local p = ns.providers.favorite
	check(p and ns:ResolveProvider("favorites") == p and ns:ResolveProvider("fav") == p and ns:ResolveProvider("favourite") == p
		and ns:ResolveProvider("favourites") == p, "@favorite (and its spellings, the UK ones too) while it's there")
	check(ns:KindName(p) == "@favorite" and p.label == L["Favorite"], "(1.6.0, the player's ask) US spelling first: named @favorite: " .. tostring(ns:KindName(p)))
	local rows = p and ns:GetEntries(p) or {}
	check(Names(rows) == "Copper Bar | Library Robe | Gone Cloak", "this character's favourites, by its dungeons' order: " .. Names(rows))
	local bar, cloak = rows[1], rows[3]
	check(bar and bar.itemID == 2840 and bar.link == "item:2840" and tostring(bar.detail):find("Plunder", 1, true)
		and tostring(bar.detail):find("Hall of Thanes", 1, true), "an item's row, where it drops: " .. tostring(bar and bar.detail))
	check(cloak and tostring(cloak.detail):find("Jammal'an the Prophet", 1, true), "a quest's reward: the quest: " .. tostring(cloak and cloak.detail))
	frame.shown = true; calls = {}
	if bar then bar.activate(bar) end
	check(calls[1] == "item,2840,nil", "Enter: the journal on its page: " .. table.concat(calls, " / "))
	calls = {}
	if cloak then cloak.activate(cloak) end
	check(calls[1] == "boss,Sunken Temple,nil", "one it no longer lists: its dungeon's page: " .. table.concat(calls, " / "))
	check(ns.Easy.Verbs(bar) == L["show in Dungeon Journal"], "its verbs say so")
	-- unstarred in its window: gone the next time Terminal opens
	favs["7777"] = nil
	UI:Open("@favourite"); FlushAll()
	check(#UI.Results() == 2, "made again as Terminal opens: " .. Names(UI.Results()))
	UI:Hide(); FlushAll()

	-- is:favourite: an item starred there, among another list's items (a probe list of items, as a bag's)
	ns:RegisterProvider("djprobe", { label = "Probe", color = "ff123456", aliases = { "djprobe" }, explicit = true,
		collect = function()
			return { { name = "Copper Bar", itemID = 2840, link = "item:2840", activate = function() end },
				{ name = "Hearthstone", itemID = 6948, link = "item:6948", activate = function() end } }
		end })
	ns.db.easyMode = false; UI:EasyChanged()
	local res = UI:Search("@djprobe is:favourite")
	check(#res == 1 and res[1].itemID == 2840, "is:favourite: the items starred there: " .. Names(res))
	res = UI:Search("@djprobe -is:favourite")
	check(#res == 1 and res[1].itemID == 6948, "and -is:favourite leaves them out: " .. Names(res))

	-- the row menu: "Show in Dungeon Journal" on an item it lists, the journal opened on it
	local function Line(label)
		for i = 1, 30 do
			local b = _G["TerminalRowMenuLine" .. i]
			if not b then return nil end
			if b.shown ~= false and b.fs:GetText() == label then return b end
		end
	end
	UI:Open("@djprobe copper"); FlushAll()
	local shown
	for i, r in ipairs(UI.Results()) do if r.itemID == 2840 then UI.sel = i; UI:ShowRowMenu(i) shown = r break end end
	local line = Line(L["Show in Dungeon Journal"])
	check(shown and line, "an item it lists: the menu offers its page")
	frame.shown = false; calls = {}
	if line then UI:MenuPicked(line); FlushAll() end
	check(calls[1] == "item,2840,nil" and not UI:IsShown(), "picked: Terminal closed, the journal on it: " .. table.concat(calls, " / "))
	UI:HideRowMenu(); UI:Hide(); FlushAll()
	UI:Open("@djprobe hearth"); FlushAll()
	for i, r in ipairs(UI.Results()) do if r.itemID == 6948 then UI.sel = i; UI:ShowRowMenu(i) break end end
	check(Line(L["Show in Dungeon Journal"]) == nil, "an item it doesn't list: no such line")
	UI:HideRowMenu(); UI:Hide(); FlushAll()

	-- "my favourites": the list, in either mode; "favorite mounts" stays the collections'
	check(Q.Question("my favourites") and Q.Question("dungeon journal favorites") and Q.Question("show my favs"), "the question, its spellings")
	check(Q.Question("favorite mounts") == nil and Q.Question("favourite food") == nil, "other favourites: not it")
	check(ns.QuestionToAdvanced("my favourites") == "@favorite " and ns.QuestionToAdvanced("my favorites") == "@favorite ",
		"to Advanced: @favorite, either spelling asked: " .. tostring(ns.QuestionToAdvanced("my favourites")))
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("my favourites"); FlushAll()
	local got = {}
	for _, e in ipairs(UI.Results()) do if e.kind == "favorite" then got[#got + 1] = e.name end end
	check(#got == 2, "Simple mode: \"my favourites\" lists them: " .. table.concat(got, ", "))
	UI:Hide(); FlushAll()

	-- .integrations
	local lines = table.concat(ns:FindCommand("integrations").run("") or {}, " / ")
	check(lines:find("DungeonJournal:", 1, true) and lines:find(L["found (%s). %d favorites (@favorite); right-click a row: Show in Dungeon Journal"]:format(
		tostring(I._.AddOnVersion("ForeverDungeonJournal") or "?"), 2), 1, true), ".integrations: its line: " .. lines)
	check(not I.AddonMissing("ForeverDungeonJournal"), "not missing while there")

	-- a version without what Terminal reads: off, said so; nothing opened, no error
	_G.ForeverDungeonJournal_NS = { DB = N.DB }
	check(not DJ.On() and DJ.Target({ kind = "loot", itemID = 2840 }) == nil and not DJ.IsFavourite(2840), "its dungeons' order gone: off")
	check(DJ.Status() == L["found (%s), but not its API for other addons: update %s"]:format(I._.AddOnVersion("ForeverDungeonJournal"),
		"DungeonJournal"), ".integrations says so, as other integrations do: " .. DJ.Status())
	_G.ForeverDungeonJournal_NS = setmetatable({ OpenBossPage = false }, { __index = N })
	N.OpenBossPage = nil
	local printed = {}
	local pr = ns.Print
	ns.Print = function(_, m) printed[#printed + 1] = m end
	I.failed.DungeonJournal = nil
	check(not DJ.Open({ dungeon = "Sunken Temple" }) and printed[1] and printed[1]:find(L["Show in Dungeon Journal is unavailable."], 1, true)
		and not printed[1]:find("OpenBossPage", 1, true), "an opener gone: said as other integrations say it (no function names), not opened: " .. tostring(printed[1]))
	DJ.Open({ dungeon = "Sunken Temple" })
	check(#printed == 1, "said once")
	local integ = table.concat(ns:FindCommand("integrations").run("") or {}, " / ")
	check(integ:find("DungeonJournal:", 1, true) and integ:find(L["Not as expected:"], 1, true), "(review) and on its .integrations line: " .. integ)
	I.failed.DungeonJournal = nil
	ns.Print = pr
end)
_G.C_AddOns, _G.ForeverDungeonJournal_NS, _G.ForeverDungeonJournalFrame, _G.ForeverDungeonJournalCharacterDB = save.addons, save.lib, save.frame, save.cdb
ns.db.easyMode = save.easy; UI:EasyChanged()
Unregister()
ns.providers.djprobe = nil
for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "djprobe" then table.remove(ns.providerOrder, i) end end
ns:AliasesChanged()
UI:HideRowMenu(); UI:Hide(); FlushAll()
check(ok, "dungeonjournal: " .. tostring(err))
check(not DJ.On() and not ns.providers.favorite, "(gone again)")
