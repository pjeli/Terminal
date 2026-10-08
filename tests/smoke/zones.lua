-- Zones (level bands from Leatrix Maps): the three questions in plain words, their answers, lvl: on zones and
-- dungeons, and the map rows' level text.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local Z, F = ns.Zones, ns.Filters

-- questions, and searches that only look like them
do
	local function Q(text) return (Z.Question(text)) end
	check(Q("where should i level") == "level" and Q("Where should I quest?") == "level"
		and Q("what quests should i do") == "level", "zones: 'where should i level' is a question")
	check(Q("what dungeon should i do") == "dungeon" and Q("which instance") == "dungeon", "zones: dungeon questions")
	check(Q("what raid should i do") == "raid", "zones: raid question")
	check(Q("where should i fish") == "fish" and Q("where can i fish") == "fish" and Q("fishing zones") == "fish",
		"zones: fishing questions")
	local _, lv = Z.Question("zones for level 35")
	check(Z.Question("zones for level 35") == "level" and lv == 35, "zones: a level said in the question")
	local k2, l2 = Z.Question("dungeon for 25")
	check(k2 == "dungeon" and l2 == 25, "zones: 'dungeon for 25'")
	check(not Q("dungeon") and not Q("fishing") and not Q("where is hogger") and not Q("where do i turn in hogger quest")
		and not Q("fishing trainer") and not Q("best sword") and not Q("where to fish in feralas")
		and not Q("@dungeon lvl:25") and not Q(".help where should i level") and not Q("nearest dungeon"),
		"zones: searches that look like questions stay searches")
end

-- answers
do
	local save = { lvl = UnitLevel, gp = _G.GetProfessions, gpi = _G.GetProfessionInfo }
	UnitLevel = function() return 23 end
	local rows, note = Z.Answer("level")
	check(note == "Zones for level 23" and #rows > 0, "zones: level answer says the level")
	local first = rows[1]
	check(first and first.kind == "maps" and first.mapID and Z.Of(first.mapID).min <= 23 and Z.Of(first.mapID).max >= 23,
		"zones: the first zone is in range for you")
	local okAll = true
	for _, r in ipairs(rows) do
		local z = Z.Of(r.mapID)
		if not (z.min - 2 <= 23 and 23 <= z.max + 2) then okAll = false end
	end
	check(okAll, "zones: only zones near your level")
	check(rows[1]._score > rows[#rows]._score and first.detail:find("Lv ", 1, true), "zones: ranked, level in the detail")
	local said = Z.Answer("level", 55)
	check(#said > 0 and Z.Of(said[1].mapID).max >= 55, "zones: a said level is used instead of yours")

	-- fishing: skill 130 = zones up to 130 first (the most demanding first), then the next tier(s)
	_G.GetProfessions = function() return nil, nil, nil, 4 end
	_G.GetProfessionInfo = function(i) if i == 4 then return "Fishing", nil, 130, 300, 0, 0, 356 end end
	local fish, fnote = Z.Answer("fish")
	check(fnote == "Your fishing: 130" and #fish > 0 and Z.Of(fish[1].mapID).fish == 130, "zones: best fishing first")
	local sawNeed = false
	for _, r in ipairs(fish) do
		if Z.Of(r.mapID).fish > 130 then sawNeed = r.detail:find("needs", 1, true) ~= nil end
	end
	check(sawNeed, "zones: the next fishing zones say what they need")
	_G.GetProfessions = function() return end
	local _, none = Z.Answer("fish")
	check(none:find("haven't learned", 1, true), "zones: no Fishing learned")

	-- dungeons: the entrance rows whose range fits
	if ns.providers.dungeon then
		local d, dn = Z.Answer("dungeon", 25)
		local fits = #d > 0
		for _, r in ipairs(d) do if not (r.minLevel - 3 <= 25 and 25 <= r.level + 1) then fits = false end end
		check(dn == "Dungeons for level 25" and fits, "zones: dungeons for a level")
		local names = {}
		local dup = false
		for _, r in ipairs(d) do if names[r.name] then dup = true end names[r.name] = true end
		check(not dup, "zones: one row per dungeon")
	end

	-- through the search: the answer, and its footer note
	local res = UI:SearchText("where should i level")
	check(#res > 0 and res[1].kind == "maps" and UI.answerNote == "Zones for level 23", "zones: the search answers it")
	-- a level said in the question, through the search (before 0.43.15 the search dropped it: `a and f()` keeps one value)
	UI:SearchText("zones for level 35")
	check(UI.answerNote == "Zones for level 35", "the search answers for the level said: " .. tostring(UI.answerNote))
	UI:SearchText("hearthstone")
	check(UI.answerNote == nil, "zones: a plain search drops the note")
	UnitLevel, _G.GetProfessions, _G.GetProfessionInfo = save.lvl, save.gp, save.gpi
end

-- lvl: on zones and dungeons, and the level text
do
	local ashen = { kind = "maps", mapID = 1440, name = "Ashenvale" }
	check(F.Parse("lvl:25")(ashen) and not F.Parse("lvl:40")(ashen), "zones: lvl: on a zone row")
	local city = { kind = "maps", mapID = 1453, name = "Stormwind City" }
	check(not F.Parse("lvl:25")(city), "zones: a city has no level")
	local dun = { kind = "dungeon", minLevel = 22, level = 30, name = "Blackfathom Deeps" }
	check(F.Parse("lvl:24")(dun) and not F.Parse("lvl:35")(dun), "zones: lvl: on a dungeon's range")
	check(Z.LevelText(Z.Of(1440)) == "Lv 18-30" and Z.LevelText(Z.Of(2482)) == "Lv 60" and Z.LevelText(Z.Of(1453)) == nil,
		"zones: level text")
end

-- "fishing spots" asks the same; the questions have Advanced forms (Alt+`), with fish: on zones (0.43.18)
do
	local E, F = ns.Easy, ns.Filters
	check(Z.Question("fishing spots") == "fish" and Z.Question("fishing pools") == "fish" and Z.Question("leveling spots") == "level",
		"fishing spots / pools, leveling spots: questions")
	check(Z.Question("spots") == nil and Z.Question("fishing") == nil, "a lone word stays a search")
	check(Z.Question("dungeon locations") == nil and Z.Question("raid places") == nil and Z.Question("quest areas") == nil
		and Z.Question("instance locations") == nil, "place words ask only about fishing and levelling (0.43.27)")
	local saveLvl, saveGP, saveGPI = UnitLevel, _G.GetProfessions, _G.GetProfessionInfo
	UnitLevel = function() return 23 end
	check(E.ToAdvanced("where should i fish") == "@map fish:mine " and E.ToAdvanced("fishing spots") == "@map fish:mine ",
		"fishing questions -> @map fish:mine: " .. E.ToAdvanced("where should i fish"))
	check(E.ToAdvanced("where should i level") == "@map lvl:23 " and E.ToAdvanced("what dungeon should i do") == "@dungeon lvl:23 "
		and E.ToAdvanced("dungeon for 30") == "@dungeon lvl:30 " and E.ToAdvanced("what raid should i do") == "@raid lvl:23 ",
		"level and dungeon questions -> lvl: on @map/@dungeon/@raid: " .. E.ToAdvanced("where should i level"))
	check(E.ToAdvanced("mats for thorium belt") == "thorium belt > mats " and E.ToAdvanced("what killed me") == "@combatlog killed ",
		"chains and combat questions: their Advanced forms")
	-- fish: on zone rows
	_G.GetProfessions = function() return nil, nil, nil, 4 end
	_G.GetProfessionInfo = function(i) if i == 4 then return "Fishing", nil, 130, 300, 0, 0, 356 end end
	local stv, azs, elw, sw = { kind = "maps", mapID = 1434 }, { kind = "maps", mapID = 1447 }, { kind = "maps", mapID = 1429 }, { kind = "maps", mapID = 1453 }
	local mine = F.Parse("fish:mine")
	check(mine(stv) and mine(elw) and mine(sw) and not mine(azs), "fish:mine: the zones your skill (130) is enough for")
	check(F.Parse("fish:205")(azs) and not F.Parse("fish:100")(stv), "fish:<skill>: what that skill is enough for")
	check(F.Parse("fish:200-400")(azs) and not F.Parse("fish:200-400")(stv), "fish:<range>: zones needing that much")
	check(not mine({ kind = "npc", key = 1 }), "fish: only judges zones")
	UnitLevel, _G.GetProfessions, _G.GetProfessionInfo = saveLvl, saveGP, saveGPI
end
