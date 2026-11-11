-- OneForAll's dungeon bosses (Providers/Integrations/OneForAll/Bosses.lua): each one's level, creature type and whether it's
-- summoned, on @loot's tooltips (Loot.lua's I.LootTipMore, with AtlasLoot's drop rate where OneForAll gave none), in
-- "what level is vancleef" (LevelOf) and "summoned bosses in blackrock spire"; without OneForAll: nothing said.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, OA, L, Q = ns.Integrations, ns.OneForAll, ns.L, ns.Questions
local B = OA.Bosses
local SEP = ns.DETAIL_SEP

io.write("[oneforall: boss levels, types, summoned; AtlasLoot's drop rates]\n")
do
	local was = { lib = rawget(_G, "OneForAll"), easy = ns.db.easyMode, failed = I.failed, print = ns.Print, al = rawget(_G, "AtlasLoot") }
	-- (AtlasLoot's two parts read here: a boss table's npcID, its drop rates)
	local A = { ItemDB = { Storage = {} }, Data = {} }
	_G.AtlasLoot = A
	local ok, err = pcall(function()
		ns.Print = function() end
		local learned = {}
		_G.OneForAll = {
			DUNGEONS = {
				{ name = "The Deadmines", bosses = { { name = "Edwin VanCleef", npcID = 639 }, { name = "Cookie", npcID = 645 } } },
				{ name = "Lower Blackrock Spire", bosses = { { name = "Urok Doomhowl", npcID = 10584 }, { name = "Highlord Omokk", npcID = 9196 } } },
				{ name = "Upper Blackrock Spire", bosses = { { name = "Solakar Flamewreath", npcID = 10264 }, { name = "General Drakkisath", npcID = 10363 } } },
				{ name = "City of Dalaran", bosses = { { name = "Arcanic Enigma" } } },
			},
			BOSS_LEVELS = { [639] = "21", [10584] = "60", [10264] = "60", [10363] = "62", ["Arcanic Enigma"] = "30" },
			BOSS_TYPES = { [639] = "Humanoid", [10584] = "Humanoid", [10264] = "Dragonkin", [10363] = "Dragonkin" },
			BOSS_SUMMONED = { [10584] = true, [10264] = true },
		}
		OA.Forget()
		-- by its id, its names, part of its name; what OneForAll says of it
		local vc = B.Find(nil, nil, 639)
		check(vc and vc.name == "Edwin VanCleef" and B.Find("Edwin VanCleef", "The Deadmines") == vc and B.Find("edwin vancleef") == vc
			and B.Named("vancleef") == vc and B.Named("edwin vancleef") == vc and B.Named("van") == nil and B.Find("Nobody") == nil,
			"a boss by its NPC id, its name (with its instance or not), part of its name")
		check(B.Said(vc) == L["Level %s"]:format("21") .. SEP .. "Humanoid", "its level and type: " .. tostring(B.Said(vc)))
		local urok = B.Find(nil, nil, 10584)
		check(B.Said(urok) == L["Level %s"]:format("60") .. SEP .. "Humanoid" .. SEP .. L["Summoned"], "summoned: said: " .. tostring(B.Said(urok)))
		check(B.Said(B.Find("Cookie")) == nil and B.Said(B.Find("Arcanic Enigma")) == L["Level %s"]:format("30"),
			"nothing known: nothing said; a level kept by name")
		-- the level OneForAll learned in game (its own GetBossLevel) first
		_G.OneForAll.GetBossLevel = function(self, boss) return learned[boss.npcID] end
		learned[645] = "20"
		check(B.Said(B.Find("Cookie")) == L["Level %s"]:format("20"), "a level OneForAll learned in game")
		_G.OneForAll.GetBossLevel = nil

		-- "summoned bosses in blackrock spire": both spires', no other
		ns.db.easyMode = true; UI:EasyChanged()
		local q = B.Question("summoned bosses in blackrock spire")
		check(q and q.inst["lower blackrock spire"] and q.inst["upper blackrock spire"] and not q.inst["the deadmines"],
			"the question: both spires")
		check(B.Question("summoned bosses in nowhere land") == nil and B.Question("bosses in the deadmines") == nil
			and B.Question("summoned pets") == nil, "an instance it doesn't know, no \"summoned\", no bosses: not its")
		local rows = B.Answer(q)
		local names = {}
		for _, e in ipairs(rows) do names[#names + 1] = e.name end
		check(table.concat(names, ",") == "Urok Doomhowl,Solakar Flamewreath" and rows[1].detail:find("Lower Blackrock Spire", 1, true)
			and rows[2].detail:find("Dragonkin", 1, true), "the summoned ones, each with its instance, level and type: " .. table.concat(names, ","))
		check(Q.Ranked("summoned bosses in blackrock spire")[1].a.id == "OneForAllBosses" and #B.Answer(B.Question("which bosses are summoned")) == 2,
			"asked as a question; every instance's")
		local none = B.Answer(B.Question("summoned bosses in the deadmines"))
		check(none[1].noActivate and none[1].name == L["OneForAll knows no summoned boss there"], "none there: said")

		-- "what level is vancleef": Questie has no NPC by that name here; OneForAll's boss
		UI.lastScan, UI.lastExtra = nil, nil
		local res = Q.Answer("what level is vancleef")
		local r = res[1]
		check(r and tostring(r.name):find("Edwin VanCleef", 1, true) and tostring(r.name):find(L["Lv %d"]:format(21), 1, true)
			and tostring(r.name):find("The Deadmines", 1, true), "what level is vancleef: OneForAll's: " .. tostring(r and r.name))
		-- (1.3.13, review) "<words> level" isn't asked about a boss by part of its name ("hunter level": Blind Hunter)
		local LV = ns.LevelOf
		check(LV.Question("vancleef level") == nil and LV.Question("what level is vancleef") ~= nil,
			"\"vancleef level\": not a boss by part of its name; \"what level is vancleef\": it is")

		-- @loot's tooltip: the boss's line; AtlasLoot's drop rate where OneForAll gave none
		A.ItemDB.Storage.ZZBosses = { DM = { items = { { npcID = { 639 } } } } }
		A.Data.Droprate = { GetData = function(_, npc, item) return npc == 639 and item == 5193 and 23.08 or nil end }
		local lines = {}
		local tip = { AddLine = function(_, s) lines[#lines + 1] = s end }
		I.LootTipMore({ detail = "Edwin VanCleef  The Deadmines", itemID = 5193, addon = "ZZBosses", content = "DM", boss = 1 }, tip)
		check(lines[2] == "Edwin VanCleef: " .. B.Said(vc) and lines[3] == ns.OneForAllWorld.ChanceText(23.08) .. SEP .. "AtlasLoot",
			"a loot row's tooltip: its boss, AtlasLoot's drop rate: " .. table.concat(lines, " | "))
		lines = {}
		I.LootTipMore({ detail = "Edwin VanCleef  The Deadmines" .. SEP .. "20% to drop", itemID = 5193, addon = "ZZBosses", content = "DM", boss = 1 }, tip)
		check(#lines == 2 and lines[2]:find("Edwin VanCleef", 1, true), "OneForAll's chance on the row: no second one")
		-- (its module not loaded: by the names alone; on another client's names nothing)
		lines = {}
		I.LootTipMore({ detail = "Edwin VanCleef  The Deadmines", itemID = 5193, addon = "Unloaded", content = "DM", boss = 1 }, tip)
		check(#lines == 2, "no module loaded: the boss by its name, no drop rate")
		lines = {}
		I.LootTipMore({ detail = "Edwin VanCleef  Die Todesminen", itemID = 1, addon = "Unloaded", content = "DM", boss = 1 }, tip)
		check(#lines == 2, "an instance's name it doesn't know: the boss by its own")
		lines = {}
		I.LootTipMore({ detail = "Nobody  Nowhere", itemID = 1, addon = "Unloaded", content = "DM", boss = 1 }, tip)
		check(#lines == 0, "a boss it doesn't know: nothing added")

		-- the tooltip itself: a loot row's lines after the item's
		check(I.loot.meta and setmetatable({ _compact = true }, I.loot.meta).tipMore ~= nil, "loot rows carry the tooltip's extra lines")
		local row = setmetatable({ _compact = true, key = "ZZBosses:DM:5193", itemID = 5193, addon = "ZZBosses", content = "DM", boss = 1, diff = 1,
			page = 0, detail = "Edwin VanCleef  The Deadmines", name = "Blackened Defias Belt" }, I.loot.meta)
		UI:Open(""); FlushAll()
		UI.results = { row }; UI.sel = 1
		local TT = _G.TerminalTooltip
		local real = TT and TT.AddLine
		local seen = {}
		if TT then TT.AddLine = function(self, s, ...) seen[#seen + 1] = tostring(s) if real then return real(self, s, ...) end end end
		UI:ForgetTooltip(); UI:UpdateTooltip()
		if TT then TT.AddLine = real end
		check(table.concat(seen, "|"):find("Edwin VanCleef: ", 1, true), "drawn on the row's tooltip: " .. table.concat(seen, "|"))
		UI:Hide(); FlushAll()

		-- without OneForAll: nothing
		_G.OneForAll = nil; OA.Forget()
		lines = {}
		I.LootTipMore({ detail = "Edwin VanCleef  The Deadmines", itemID = 5193, addon = "Unloaded", content = "DM", boss = 1 }, tip)
		check(#lines == 0 and B.Question("summoned bosses") == nil and B.Named("vancleef") == nil, "without OneForAll: nothing said")
	end)
	_G.OneForAll = was.lib
	_G.AtlasLoot = was.al
	ns.db.easyMode = was.easy; UI:EasyChanged()
	I.failed, ns.Print = was.failed, was.print
	UI.lastScan, UI.lastExtra = nil, nil
	OA.Forget()
	check(ok, "oneforall bosses: " .. tostring(err))
end
