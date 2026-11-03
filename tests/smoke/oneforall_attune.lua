-- @attune without Attune (1.0.7, the player's ask; Providers/Integrations/OneForAll/Attunements.lua): OneForAll's dungeon keys and
-- raid attunements made into Attune's records, so the rows, "> steps", "my keys", "how do i get into onyxia" and is:done
-- work as with Attune; how far along from the game (the key yours: done; else up to the last quest turned in); your
-- faction's chain only; Attune installed: never these.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, OA, L = ns.Integrations, ns.OneForAll, ns.L
local AT, K = ns.Attune, ns.OneForAll.Attunements

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

io.write("[oneforall: its keys and raid attunements as @attune, without Attune]\n")
do
	local save = { lib = rawget(_G, "OneForAll"), failed = I.failed, on = OA.on, side = _G.UnitFactionGroup, easy = ns.db.easyMode,
		done = C_QuestLog.IsQuestFlaggedCompleted, count = C_Item.GetItemCount, data = _G.Attune_Data, attuneOn = I.attune.on,
		print = ns.Print, show = ns.ShowText }
	local said, shown = {}, nil
	ns.Print = function(_, m) said[#said + 1] = m end
	ns.ShowText = function(_, title, text) shown = text end
	local doneQ, have = {}, {}
	local ok, err = pcall(function()
		_G.Attune_Data = nil
		I.attune.on = false
		drop("attune")
		_G.UnitFactionGroup = function() return "Alliance" end
		C_QuestLog.IsQuestFlaggedCompleted = function(id) return doneQ[id] == true end
		C_Item.GetItemCount = function(id) return have[id] or 0 end
		_G.OneForAll = {
			BOOKS = { { name = "A Book", questId = 1, itemId = 2 } },
			DUNGEON_KEYS = {
				["Scarlet Monastery: Armory"] = { { item = 7146, name = "The Scarlet Key", required = true, summary = "Opens the doors.",
					steps = { { name = "Clear the Library", pickup = "Scarlet Monastery: Library" }, { name = "Open Doan's Strongbox" } } } },
				["Scarlet Monastery: Cathedral"] = { { item = 7146, name = "The Scarlet Key", required = true,
					steps = { { name = "Clear the Library" }, { name = "Open Doan's Strongbox" } } } },
				["Upper Blackrock Spire"] = { { item = 12344, name = "Seal of Ascension", required = true,
					steps = { { quest = 4742, name = "Seal of Ascension", level = 60, requires = 57, pickup = "Vaelan, Lower Blackrock Spire (12.0, 34.0)",
						objective = "Bring the three gemstones.", turnin = "Vaelan" } } } },
				["Blackrock Depths"] = { { item = 11000, name = "Shadowforge Key", required = false, steps = { { quest = 3802, name = "Dark Iron Legacy" } } } },
				["Onyxia's Lair"] = { { item = 16309, name = "Drakefire Amulet", required = true, summary = "Needed to enter Onyxia's Lair.",
					steps = {
						{ quest = 4182, name = "Dragonkin Menace", level = 54, requires = 48, faction = "Alliance", pickup = "Helendis Riverhorn, Burning Steppes (85.8, 69.0)" },
						{ quest = 4183, name = "The True Masters", level = 54, requires = 48, faction = "Alliance" },
						{ quest = 6502, name = "Drakefire Amulet", level = 60, requires = 50, faction = "Alliance" },
						{ quest = 4903, name = "Warlord's Command", level = 60, requires = 55, faction = "Horde" },
						{ quest = 6602, name = "Blood of the Black Dragon Champion", level = 60, requires = 55, faction = "Horde" },
					} } },
				["Broken"] = "not a list",
			},
		}
		I.failed, OA.on = {}, nil
		OA.Forget(); K.Forget(); AT.Forget(); AT.ForgetToon(); AT.Q.Forget()
		I._.SetupOneForAll()
		ns:AliasesChanged()
		local P = ns.providers.attune
		check(P and ns:ResolveProvider("attunement") == P and AT.fallback == K, "@attune from OneForAll, Attune not installed")
		local res = UI:Search("@attune")
		-- the raid first; one Scarlet Key for both wings; your faction's amulet only; a key's name says it's one
		check(Names(res) == "Drakefire Amulet (Onyxia's Lair) | Shadowforge Key (Blackrock Depths) | The Scarlet Key (Scarlet Monastery: Armory, Cathedral)"
			.. " | Seal of Ascension (Upper Blackrock Spire key)", "the rows, in order: " .. Names(res))
		local function Row(name, rows)
			for _, e in ipairs(rows or res) do if e.name:find(name, 1, true) == 1 then return e end end
		end
		local ony = Row("Drakefire")
		check(ony.detail:find("Raid attunement", 1, true) and ony.detail:find("Lv 48-60", 1, true) and ony.detail:find("next: Dragonkin Menace", 1, true),
			"Onyxia's: nothing done yet, its first step next: " .. ony.detail)
		-- a quest turned in: every step up to it done
		doneQ[4183] = true
		K.ForgetDone()
		check(ony.detail:find("66%", 1, true) and ony.detail:find("next: Drakefire Amulet", 1, true), "two of three done: " .. ony.detail)
		-- the key yours: all of it
		local sk = Row("The Scarlet Key")
		check(sk.detail:find("next: Clear the Library", 1, true), "a key's steps that aren't quests: the first next: " .. sk.detail)
		have[7146] = 1
		K.ForgetDone()
		check(sk.detail:find("done", 1, true) and sk.icon:find("ReadyCheck", 1, true), "the key in your bags: done: " .. sk.detail)
		res = UI:Search("@attune is:done")
		check(Names(res) == "The Scarlet Key (Scarlet Monastery: Armory, Cathedral)", "is:done: " .. Names(res))
		res = UI:Search("@attune is:raid")
		check(Names(res) == "Drakefire Amulet (Onyxia's Lair)", "is:raid: " .. Names(res))
		-- the steps, numbered
		res = UI:Search("drakefire amulet > steps")
		check(Names(res) == "Dragonkin Menace | The True Masters | Drakefire Amulet" and res[1].detail:find("step 1 of 3", 1, true)
			and res[1].detail:find("Helendis Riverhorn, Burning Steppes", 1, true) and not res[1].detail:find("85.8", 1, true)
			and res[1].detail:find("done", 1, true) and res[3].detail:find("next", 1, true),
			"the steps: " .. Names(res) .. " / " .. tostring(res[1] and res[1].detail))
		-- a step's tooltip: OneForAll's words for it
		local lines = {}
		local tip = setmetatable({}, { __index = function(_, k)
			if k == "SetText" or k == "AddLine" then return function(_, s) lines[#lines + 1] = tostring(s) end end
			if k == "AddDoubleLine" then return function(_, a, b) lines[#lines + 1] = tostring(a) .. " = " .. tostring(b) end end
			return function() end
		end })
		local seal = UI:Search("seal of ascension > steps")[1]
		seal.tooltip(seal, tip)
		local text = table.concat(lines, "\n")
		check(text:find("Bring the three gemstones.", 1, true) and text:find("Vaelan", 1, true) and text:find("(OneForAll)", 1, true),
			"a step's tooltip: " .. text)
		seal.activate(seal)
		check(shown == I.WOWHEAD_QUEST:format(4742), "Enter on a quest step: its Wowhead link: " .. tostring(shown))
		-- a quest's attunements
		res = UI:Search("@attune shadowforge")
		check(#res == 1 and res[1].detail:find("Key", 1, true), "an optional key: " .. tostring(res[1] and res[1].detail))
		-- Simple mode's questions
		ns.db.easyMode = true
		local function Open(s)
			UI:Hide(); FlushAll()
			UI:Open(s); FlushAll()
			return UI.Results(), tostring(UI.status:GetText())
		end
		local rows = Open("how do i get into onyxia")
		check(Names(rows) == "Dragonkin Menace | The True Masters | Drakefire Amulet", "how do i get into onyxia: " .. Names(rows))
		rows = Open("my keys")
		check(#rows == 3 and Names(rows):find("Scarlet Key", 1, true), "my keys: " .. Names(rows))
		ns.db.easyMode = false
		-- the Horde's chain for a Horde character
		_G.UnitFactionGroup = function() return "Horde" end
		ns:Changed("attune"); FlushAll()
		res = UI:Search("@attune is:raid > steps")
		check(Names(res) == "Warlord's Command | Blood of the Black Dragon Champion", "a Horde character: the Horde's chain: " .. Names(res))
		local lines2 = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines2:find(L["%d keys and raid attunements (@attune: Attune isn't installed)"]:format(5), 1, true), ".integrations: " .. lines2)
		UI:Hide(); FlushAll()
		-- Attune installed: Attune's, never OneForAll's
		drop("attune")
		AT.fallback, K.on, I.attune.on = nil, nil, true
		OA.on = nil
		OA.Forget(); AT.Forget()
		I._.SetupOneForAll()
		check(ns.providers.attune == nil and AT.fallback == nil, "with Attune: OneForAll's never registered")
	end)
	for _, id in ipairs({ "attune", "book", "tame", "itemset", "transport", "gearplan" }) do drop(id) end
	_G.OneForAll, _G.Attune_Data, I.attune.on = save.lib, save.data, save.attuneOn
	I.failed, OA.on = save.failed, save.on
	_G.UnitFactionGroup, ns.db.easyMode = save.side, save.easy
	C_QuestLog.IsQuestFlaggedCompleted, C_Item.GetItemCount = save.done, save.count
	ns.Print, ns.ShowText = save.print, save.show
	AT.fallback, AT.meta, AT.stepMeta, K.on = nil, nil, nil, nil
	OA.Forget(); K.Forget(); AT.Forget(); AT.ForgetToon(); AT.Q.Forget()
	ns.Pipes.ClearSteps()
	if not ok then check(false, "oneforall_attune: " .. tostring(err)) end
end
