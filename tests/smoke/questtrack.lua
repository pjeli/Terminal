-- Tracking quests in bulk (QuestTrack.lua, 0.63.3, from a player's comment): "untrack quests", "track completed quests",
-- "untrack dungeon quests", "track class quest", "track rfc quests only", "untrack red quests", "track nearby quests";
-- the tracker's limit, Questie's tracker, ">>> track" / ">>> untrack" / ">> track", the filters and Alt+`.
local T = ...
local ns, UI, S, check, key, FlushAll = T.ns, T.UI, T.S, T.check, T.key, T.FlushAll
local QK = ns.QuestTrack

io.write("[quest tracking]\n")
do
	local Q = C_QuestLog
	local save = {
		num = Q.GetNumQuestLogEntries, info = Q.GetInfo, obj = Q.GetQuestObjectives, ready = Q.ReadyForTurnIn,
		tag = Q.GetQuestTagInfo, wt = Q.GetQuestWatchType, add = Q.AddQuestWatch, rem = Q.RemoveQuestWatch,
		max = Q.GetMaxNumQuestsCanWatch, nw = Q.GetNumQuestWatches, idx = Q.GetLogIndexForQuestID,
		pi = _G.C_PlayerInfo, map = _G.C_Map, uiMap = _G.GetQuestUiMapID, ul = _G.UnitLevel,
		zone = _G.GetRealZoneText, sub = _G.GetSubZoneText, cn = _G.LOCALIZED_CLASS_NAMES_MALE,
		questie = rawget(_G, "Questie"), loader = rawget(_G, "QuestieLoader"), easy = ns.db.easyMode,
		print = ns.Print, out = ns.Output,
	}
	-- a level 15 warrior's log in the Barrens
	local quests = {
		{ title = "Durotar", isHeader = true },
		{ title = "Lazy Peons", questID = 201, level = 4 },
		{ title = "Thwarting Kolkar Aggression", questID = 202, level = 12 },
		{ title = "The Barrens", isHeader = true },
		{ title = "Raptor Thieves", questID = 203, level = 15 },
		{ title = "Fungal Spores", questID = 204, level = 18 },
		{ title = "Ragefire Chasm", isHeader = true },
		{ title = "Searching for the Lost Satchel", questID = 205, level = 15 },
		{ title = "Hidden Enemies", questID = 206, level = 16 },
		{ title = "Warrior", isHeader = true },
		{ title = "Veteran Uzzek", questID = 207, level = 20 },
		{ title = "Wailing Caverns", isHeader = true },
		{ title = "Leaders of the Fang", questID = 208, level = 22 },
		{ title = "Burning Steppes", isHeader = true },
		{ title = "Attunement to the Core", questID = 209, level = 60 },
	}
	local DIFF = { [201] = 0, [202] = 1, [203] = 2, [204] = 3, [205] = 2, [206] = 2, [207] = 4, [208] = 4, [209] = 4 }
	local TAG = { [205] = 81, [206] = 81, [209] = 62 } -- (Dungeon, Raid; Wailing Caverns' only by its header)
	local MAP = { [202] = 1411, [203] = 1413, [204] = 1413 }
	local watched, questieOn, limit = {}, {}, nil
	local function Watch(...) watched = {} for _, id in ipairs({ ... }) do watched[id] = true end end
	Q.GetNumQuestLogEntries = function() return #quests end
	Q.GetInfo = function(i) return quests[i] end
	Q.GetQuestObjectives = function() return {} end
	Q.ReadyForTurnIn = function(id) return id == 201 end
	Q.GetQuestTagInfo = function(id) return TAG[id] and { tagID = TAG[id], tagName = "x" } or nil end
	Q.GetQuestWatchType = function(id) return watched[id] and 0 or nil end
	Q.GetNumQuestWatches = function() local n = 0 for _ in pairs(watched) do n = n + 1 end return n end
	Q.GetMaxNumQuestsCanWatch = function() return limit end
	Q.AddQuestWatch = function(id)
		if limit and Q.GetNumQuestWatches() >= limit then return false end
		watched[id] = true
		return true
	end
	-- (Questie's hook on Forever: a native removal untracks it on Questie's tracker too)
	Q.RemoveQuestWatch = function(id) watched[id] = nil; questieOn[id] = nil end
	Q.GetLogIndexForQuestID = function(id) return 1 end
	_G.C_PlayerInfo = setmetatable({ GetContentDifficultyQuestForPlayer = function(id) return DIFF[id] end }, { __index = save.pi })
	_G.C_Map = setmetatable({ GetBestMapForUnit = function() return 1413 end, GetMapLevels = function() end }, { __index = save.map })
	_G.GetQuestUiMapID = function(id) return MAP[id] or 0 end
	_G.UnitLevel = function() return 15 end
	_G.GetRealZoneText = function() return "The Barrens" end
	_G.GetSubZoneText = function() return "The Crossroads" end
	_G.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", MAGE = "Mage" }
	_G.Questie, _G.QuestieLoader = nil, nil
	local said = {}
	ns.Output = function(_, lines) for _, l in ipairs(lines or {}) do said[#said + 1] = l end end
	local printed = {}
	ns.Print = function(_, m) printed[#printed + 1] = m end
	ns.db.easyMode = true; UI:EasyChanged()
	ns.providers.quests._dirty = true

	local function Ask(line)
		local q = QK.Question(line)
		if not q then return nil end
		local rows, note = QK.Answer(q)
		return rows, note, q
	end
	local function Ids(rows)
		local t = {}
		for _, e in ipairs(rows or {}) do t[#t + 1] = e.lead and "do" or tostring(e.questID) end
		return table.concat(t, ",")
	end
	local function W()
		local t = {}
		for id in pairs(watched) do t[#t + 1] = id end
		table.sort(t)
		return table.concat(t, ",")
	end

	-- the marks the quest log rows carry now
	local rows = {}
	for _, e in ipairs(ns:GetEntries(ns.providers.quests)) do rows[e.questID] = e end
	check(rows[207].diffName == "red" and rows[204].diffName == "orange" and rows[201].diffName == "grey" and rows[202].diffName == "green",
		"each quest's colour for your level, the log's own")
	check(rows[205].instance == "dungeon" and rows[208].instance == "dungeon" and rows[209].instance == "raid" and rows[203].instance == nil,
		"a dungeon's by its tag or its header (Wailing Caverns), a raid's by its tag")
	check(rows[207].classQuest and not rows[203].classQuest, "a class quest: under its class's name in the log")

	-- "untrack quests": every tracked one
	Watch(202, 203, 205, 207)
	local r, note = Ask("untrack quests")
	check(r and Ids(r) == "do,202,203,205,207" and r[1].name == "Untrack 4 quests", "untrack quests: the four tracked: " .. Ids(r))
	check(r[2].detail:find("to untrack", 1, true), "each row says what happens to it: " .. tostring(r[2].detail))
	r[1].activate()
	check(W() == "" and said[#said]:find("Stopped tracking 4 quests", 1, true), "Enter: none tracked, a line says so: " .. tostring(said[#said]))
	check(Ask("untrack all") and Ask("untrack everything") and Ask("stop tracking quests"), "\"untrack all\", \"stop tracking quests\"")
	local _, note2 = Ask("untrack quests")
	check(note2 == "None of them is tracked", "nothing tracked: said: " .. tostring(note2))

	-- "track completed quests"
	r = Ask("track completed quests")
	check(Ids(r) == "do,201" and r[1].name == "Track 1 quest", "track completed quests: " .. Ids(r))
	r[1].activate()
	check(W() == "201", "tracked: " .. W())
	local _, n3 = Ask("track completed quests")
	check(n3 == "Already tracked, all of them", "again: already: " .. tostring(n3))

	-- "untrack dungeon quests": the dungeons' (by tag or header) and the raids'
	Watch(203, 205, 208, 209)
	r = Ask("untrack dungeon quests")
	check(Ids(r) == "do,205,208,209", "untrack dungeon quests: " .. Ids(r))
	check(Ids(Ask("untrack raid quests")) == "do,209", "untrack raid quests: the raid's only")

	-- "track class quest"
	Watch()
	r = Ask("track class quest")
	check(Ids(r) == "do,207", "track class quest: " .. Ids(r))

	-- "track rfc quests only": those two tracked, every other one untracked
	Watch(202, 203, 207)
	r = Ask("track rfc quests only")
	check(r[1].name == "Track 2, untrack 3" and Ids(r) == "do,205,206,202,203,207", "rfc only: track 2, untrack 3: " .. Ids(r))
	r[1].activate()
	check(W() == "205,206", "only the rfc quests tracked: " .. W())
	check(QK.Question("only track ragefire chasm quests").only and QK.Question("just track rfc quests").only, "\"only track\", \"just track\", the full name")

	-- "untrack red quests": by the log's colour
	Watch(203, 207, 208)
	check(Ids(Ask("untrack red quests")) == "do,207,208", "untrack red quests: " .. Ids(Ask("untrack red quests")))
	check(Ids(Ask("untrack red and orange quests")) == "do,207,208", "red and orange: the tracked ones")

	-- "track nearby quests": under your zone's name in the log, or on your map
	Watch()
	check(Ids(Ask("track nearby quests")) == "do,203,204", "nearby: the Barrens' two: " .. Ids(Ask("track nearby quests")))
	check(Ids(Ask("track quests in this zone")) == "do,203,204", "\"in this zone\" too")

	-- a place typed as one word, or with its apostrophe left out (0.63.4, the player: "track thunderbluff quests")
	quests[#quests + 1] = { title = "Thunder Bluff", isHeader = true }
	quests[#quests + 1] = { title = "The Hunter's Way", questID = 210, level = 10 }
	ns.providers.quests._dirty = true
	Watch()
	check(Ids(Ask("track thunderbluff quests")) == "do,210" and Ids(Ask("track thunder bluff quests")) == "do,210"
		and Ids(Ask("track tb quests")) == "do,210", "thunderbluff, thunder bluff, tb: " .. Ids(Ask("track thunderbluff quests")))
	check(Ids(Ask("track hunters way quest")) == "do,210", "a title's apostrophe left out")
	-- (0.63.5, the player: Alt+` on it searched the words in every quest's text, and took in more) a place said is the
	-- log's heading, in the answer and in its Advanced form alike; a quest that only mentions it isn't one
	quests[#quests + 1] = { title = "Mulgore", isHeader = true }
	quests[#quests + 1] = { title = "Journey to Thunder Bluff", questID = 211, level = 9 }
	ns.providers.quests._dirty = true
	Watch(210, 211, 203)
	check(Ids(Ask("untrack thunder bluff quests")) == "do,210", "the heading's quests only: " .. Ids(Ask("untrack thunder bluff quests")))
	check(QK.ToAdvanced(QK.Question("untrack thunder bluff quests")) == '@quest in:"Thunder Bluff" >>> untrack',
		"Alt+`: the heading: " .. QK.ToAdvanced(QK.Question("untrack thunder bluff quests")))
	check(QK.ToAdvanced(QK.Question("untrack thunderbluff quests")) == '@quest in:"Thunder Bluff" >>> untrack', "one word: the same")
	ns.db.easyMode = false; UI:EasyChanged()
	local function Same(question)
		local plain = Ask(question)
		local line = QK.ToAdvanced(QK.Question(question))
		UI:Open(line); FlushAll()
		local adv = UI.Results()[1] and UI.Results()[1].name
		UI:Hide(); FlushAll()
		local name = plain and plain[1] and plain[1].name or "Nothing to change"
		return name == adv, question .. " -> " .. line .. ": " .. tostring(plain and plain[1] and plain[1].name) .. " / " .. tostring(adv)
	end
	for _, line in ipairs({ "untrack thunder bluff quests", "untrack thunderbluff quests", "untrack quests", "untrack red quests",
		"untrack dungeon quests", "track rfc quests only", "track completed quests", "track nearby quests",
		"track quest journey to thunder bluff", "untrack mulgore and thunder bluff quests" }) do
		check(Same(line))
	end
	check(QK.ToAdvanced(QK.Question("track quest journey to thunder bluff")) == '@quest "journey to thunder bluff" >>> track',
		"a quest's name: its title, in quotes: " .. QK.ToAdvanced(QK.Question("track quest journey to thunder bluff")))
	check(QK.ToAdvanced(QK.Question("untrack mulgore and thunder bluff quests")) == '@quest in:Mulgore|"Thunder Bluff" >>> untrack',
		"two places: " .. QK.ToAdvanced(QK.Question("untrack mulgore and thunder bluff quests")))
	Watch()
	check(Ids(Ask("track mulgore and thunder bluff quests")) == "do,211,210", "both headings' quests: " .. Ids(Ask("track mulgore and thunder bluff quests")))
	ns.db.easyMode = true; UI:EasyChanged()
	for _ = 1, 4 do quests[#quests] = nil end
	ns.providers.quests._dirty = true
	-- by name: a quest's title
	Watch()
	check(Ids(Ask("track quest raptor thieves")) == "do,203", "a quest by its title")

	-- not these
	check(QK.Question("track hogger") == nil and QK.Question("quests to track") == nil and QK.Question("tracking quests") == nil
		and QK.Question("untrack") == nil, "lines that aren't it")

	-- the tracker's limit: the first that fit, said
	limit = 3
	Watch(207)
	r = Ask("track quests")
	check(r[1].detail:find("the tracker holds 3: 2 fit", 1, true), "the room said first: " .. tostring(r[1].detail))
	said = {}
	r[1].activate()
	check(W() == "201,202,207" and said[2] and said[2]:find("Not changed (the tracker holds 3 at most)", 1, true),
		"the first that fit tracked, the rest said: " .. W() .. " / " .. tostring(said[2]))
	limit = nil

	-- Questie's tracker: tracked on it alone (auto-track) counts; untracking reaches it
	_G.Questie = { db = { profile = { trackerEnabled = true } } }
	_G.QuestieLoader = { ImportModule = function(_, name)
		if name == "QuestieTracker" then return { IsTrackedByQuestie = function(id) return questieOn[id] == true end } end
	end }
	Watch()
	questieOn = { [203] = true, [204] = true }
	r = Ask("untrack quests")
	check(Ids(r) == "do,203,204" and r[1].detail:find("Questie", 1, true), "tracked on Questie's tracker: counted: " .. Ids(r) .. " / " .. tostring(r[1].detail))
	r[1].activate()
	check(next(questieOn) == nil, "untracked there too")
	_G.Questie.db.profile.trackerEnabled = false
	questieOn = { [203] = true }
	check(QK.Tracked(203) == false, "Questie's tracker off: the game's tracker only")
	_G.Questie, _G.QuestieLoader = nil, nil

	-- the filters, and Alt+`
	Watch(203)
	local F = ns.Filters
	check(F.Parse("is:tracked")(rows[203]) and not F.Parse("is:tracked")(rows[204]) and F.Parse("is:untracked")(rows[204]),
		"is:tracked / is:untracked")
	check(F.Parse("is:red")(rows[207]) and F.Parse("is:orange")(rows[204]) and not F.Parse("is:red")(rows[204]), "is:red, is:orange on a quest")
	check(F.Parse("is:dungeon")(rows[208]) and F.Parse("is:raid")(rows[209]) and F.Parse("is:class")(rows[207]) and F.Parse("is:here")(rows[203])
		and not F.Parse("is:here")(rows[205]), "is:dungeon, is:raid, is:class, is:here on quests")
	check(QK.ToAdvanced(QK.Question("track completed quests")) == "@quest is:complete >>> track"
		and QK.ToAdvanced(QK.Question("track rfc quests only")) == '@quest in:"Ragefire Chasm" >>> track only'
		and QK.ToAdvanced(QK.Question("untrack red quests")) == "@quest is:red >>> untrack",
		"Alt+`: " .. QK.ToAdvanced(QK.Question("track rfc quests only")))
	check(ns.Easy.ToAdvanced("untrack dungeon quests") == "@quest is:dungeon|raid >>> untrack",
		"the question's Advanced form: " .. tostring(ns.Easy.ToAdvanced("untrack dungeon quests")))

	-- typed in the terminal: the answer, its top row first; Enter on it does it
	Watch()
	UI:Open("track completed quests"); FlushAll()
	check(UI.Results()[1] and UI.Results()[1].name == "Track 1 quest" and UI.sel == 1,
		"typed: the answer, \"Track 1 quest\" selected: " .. tostring(UI.Results()[1] and UI.Results()[1].name))
	key("ENTER"); FlushAll()
	check(W() == "201", "Enter: tracked: " .. W())
	UI:Hide(); FlushAll()

	-- ">>> track": one row; Enter tracks every quest listed
	ns.db.easyMode = false; UI:EasyChanged()
	Watch()
	UI:Open("@quest is:red >>> track"); FlushAll()
	local top = UI.Results()[1]
	check(#UI.Results() == 1 and top.name == "Track 3 quests", ">>> track collapses into one row: " .. tostring(top.name))
	local status = UI.status and UI.status:GetText() or ""
	check(status:find("Enter changes the tracker", 1, true), "the footer says so: " .. status)
	S.armed = nil
	key("ENTER"); FlushAll()
	check(W() == "207,208,209" and S.armed == nil and not UI:IsShown(), "Enter: the three tracked, nothing pressed: " .. W())
	UI:Open("@quest is:red >>> untrack"); FlushAll()
	key("ENTER"); FlushAll()
	check(W() == "", ">>> untrack: gone")
	Watch(201, 203)
	UI:Open("@quest rfc >>> track only"); FlushAll()
	check(UI.Results()[1].name == "Track 2, untrack 2", ">>> track only: " .. tostring(UI.Results()[1].name))
	key("ENTER"); FlushAll()
	check(W() == "205,206", ">>> track only: those alone: " .. W())
	-- (the Advanced form Alt+` gives works as typed)
	Watch(205, 208, 209, 203)
	UI:Open("@quest is:dungeon|raid >>> untrack"); FlushAll()
	check(UI.Results()[1].name == "Untrack 3 quests", "is:dungeon|raid >>> untrack: " .. tostring(UI.Results()[1].name))
	UI:Hide(); FlushAll()
	-- ">> track": the selected one; not a quest: said
	Watch()
	UI:Open("@quest raptor >> track"); FlushAll()
	key("ENTER"); FlushAll()
	check(W() == "203", ">> track: the selected quest: " .. W())
	UI:Open("hearthstone >> track"); FlushAll()
	printed = {}
	key("ENTER"); FlushAll()
	check(printed[1] and printed[1]:find("Only quests in your log can be tracked", 1, true), ">> track on an item: said")
	UI:Hide(); FlushAll()

	Q.GetNumQuestLogEntries, Q.GetInfo, Q.GetQuestObjectives, Q.ReadyForTurnIn = save.num, save.info, save.obj, save.ready
	Q.GetQuestTagInfo, Q.GetQuestWatchType, Q.AddQuestWatch, Q.RemoveQuestWatch = save.tag, save.wt, save.add, save.rem
	Q.GetMaxNumQuestsCanWatch, Q.GetNumQuestWatches, Q.GetLogIndexForQuestID = save.max, save.nw, save.idx
	_G.C_PlayerInfo, _G.C_Map, _G.GetQuestUiMapID, _G.UnitLevel = save.pi, save.map, save.uiMap, save.ul
	_G.GetRealZoneText, _G.GetSubZoneText, _G.LOCALIZED_CLASS_NAMES_MALE = save.zone, save.sub, save.cn
	_G.Questie, _G.QuestieLoader = save.questie, save.loader
	ns.Print, ns.Output = save.print, save.out
	ns.db.easyMode = save.easy; UI:EasyChanged()
	ns.providers.quests._dirty = true
end
