-- OneForAll's armory (1.0.3, the player's ask; Providers/Integrations/OneForAll/Armory.lua): reputation rewards (each faction's,
-- @reputation rows only its questions and "> rewards" list since 1.0.11; no @repreward:
-- the standing each needs, yours: can you buy it), @itemset (the sets, pieces you have, bonuses; Enter, "> pieces":
-- its pieces, where each comes from; no @setpiece since 1.0.10); "argent dawn rewards", "what can i buy at honored", "my class
-- sets", "pieces of battlegear of might" in Simple mode; standing: and class:mine on them; the other faction's left
-- out; a table not in the shape expected said once; without OneForAll: none.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, OA, L, F = ns.Integrations, ns.OneForAll, ns.L, ns.Filters
local A = OA.Armory

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[oneforall: reputation rewards, item sets and their pieces]\n")
do
	local KINDS = { "book", "tame", "itemset" }
	local save = { providers = ns.providers, order = ns.providerOrder, print = ns.Print, lib = rawget(_G, "OneForAll"),
		spot = I.SpotXY, failed = I.failed, on = OA.on, easy = ns.db.easyMode, class = _G.UnitClass, side = _G.UnitFactionGroup,
		fac = rawget(_G, "GetFactionInfoByID"), rep = rawget(_G, "C_Reputation"), count = _G.GetItemCount, eq = _G.IsEquippedItem,
		citem = C_Item and C_Item.GetItemCount, ceq = C_Item and C_Item.IsEquippedItem, walk = UI.WalkTo }
	local said = {}
	ns.Print = function(_, m) said[#said + 1] = m end
	local function Said(s) for _, m in ipairs(said) do if m:find(s, 1, true) then return m end end end
	local function Fresh()
		for _, id in ipairs(KINDS) do
			ns.providers[id] = nil
			for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
		end
		I.failed, OA.on = {}, nil
		OA.Forget()
		I._.SetupOneForAll()
		ns:AliasesChanged()
	end
	local ok, err = pcall(function()
		ns.providers, ns.providerOrder = {}, {}
		local skip = {}
		for _, k in ipairs(KINDS) do skip[k] = true end
		for _, id in ipairs(save.order) do
			if not skip[id] then ns.providers[id] = save.providers[id]; ns.providerOrder[#ns.providerOrder + 1] = id end
		end
		_G.UnitClass = function() return "Warrior", "WARRIOR" end
		_G.UnitFactionGroup = function() return "Alliance" end
		-- the game: honored with the Argent Dawn (6), Timbermaw not met; a Helm of Might worn, its belt in the bank
		local STAND = { [529] = 6 }
		_G.C_Reputation = nil
		_G.GetFactionInfoByID = function(id) if STAND[id] then return "Faction " .. id, "", STAND[id] end end
		local HAVE, WORN = { [16864] = 1 }, { [16866] = true }
		local function Count(id) return HAVE[id] or 0 end
		local function Worn(id) return WORN[id] == true end
		_G.GetItemCount, _G.IsEquippedItem = Count, Worn
		if C_Item then C_Item.GetItemCount, C_Item.IsEquippedItem = Count, Worn end
		-- its tables (Data/Armory.lua's shape), a few of each
		_G.OneForAll = {
			BOOKS = { { name = "A Book", questId = 1, itemId = 2 } },
			ARMORY_REPUTATION = {
				{ id = 529, n = "Argent Dawn", st = 1, v = { { 10856, "Argent Quartermaster Hasana", 1420, 83.3, 68.1, "Tirisfal Glades" } },
					i = { { 13724, "Enriched Manna Biscuit", nil, 1, 133989, 4, "other", { 10856 } },
						{ 22014, "Hallowed Brazier", nil, 1, 133879, 5, "other", { 10856 } },
						{ 19446, "Formula: Enchant Bracer - Mana Regeneration", nil, 1, 134327, 6, "recipe", { 10856 } },
						{ 18171, "Arcane Mantle of the Dawn", "Shoulder", 3, "inv_shoulder_02", 7, "gear", { 10856 } } } },
				{ id = 576, n = "Timbermaw Hold", st = 1, v = { { 11557, "Meilosh", 1448, 65.7, 2.8, "Felwood" } },
					i = { { 20253, "Pattern: Warbear Harness", nil, 1, 134939, 4, "recipe", { 11557 } } } },
				{ id = 2586, n = "Azeroth Commerce Authority", st = 1, side = "A", v = {}, i = { { 262765, "ACA Tabard", "Tabard", 1, 1, 7, "other", {} } } },
				{ id = 2587, n = "Durotar Supply and Logistics", st = 1, side = "H", v = {}, i = { { 262764, "DSL Tabard", "Tabard", 1, 1, 7, "other", {} } } },
				{ id = 270, n = "Zandalar Tribe", st = 0, v = {}, i = { { 20757, "Formula: Brilliant Mana Oil", nil, 1, 1, 4, "recipe", {} } } },
			},
			ARMORY_SETS = {
				{ id = 209, n = "Battlegear of Might", g = "raid", st = 0, sub = "Tier 1 - Molten Core", arm = "Plate", lv = 60, cls = { "WARRIOR" },
					b = { { 3, "Increases the block value of your shield by 30." }, { 5, "A Rage point now and then." } },
					i = { { 16866, "Helm of Might", "Head", 4, 133077, { "Molten Core - Garr" } }, { 16864, "Belt of Might", "Waist", 4, 132517, { "Molten Core - Lucifron" } },
						{ 16865, "Breastplate of Might", "Chest", 4, 132738, { "Molten Core - Golemagg" } } } },
				{ id = 261, n = "Spirit of Eskhandar", g = "raid", st = 1, sub = "world bosses", arm = "Cloth", cls = { "MAGE", "PRIEST", "WARLOCK" },
					b = {}, i = { { 18205, "Eskhandar's Collar", "Neck", 4, 0, {} } } }, -- (0: no icon, as OneForAll's unnamed pieces)
				{ id = 241, n = "Scale of the Gods", g = "raid", st = 1, sub = "Onyxia's Lair", cls = {}, b = {},
					i = { { 17064, "Shard of the Scale", "Trinket", 4, 134317, { "Onyxia's Lair - Onyxia" } } } },
			},
		}
		I.SpotXY = function(ui, c) return 2, c[1] * 10, c[2] * 10 end
		-- your reputations: the Argent Dawn met, Timbermaw not (the chain starts from a faction's row)
		ns.providers.reputation = { id = "reputation", label = "Reputation", aliases = { "reputation", "rep" }, _dirty = true,
			collect = function() return { { key = 529, name = "Argent Dawn", factionID = 529, reaction = 6 } } end }
		Fresh()
		local ps = ns.providers.itemset
		check(ps and not ns.providers.setpiece and not ns.providers.repreward and ns:ResolveProvider("tierset") == ps
			and ns:ResolveProvider("setpiece") == ps, "@itemset (@setpiece its other name); no @repreward, no @setpiece")
		check(ns:ResolveProvider("sets") ~= ps, "@sets: still your equipment sets")
		check(not Said(L["Its reputation rewards are unavailable."]) and not Said(L["OneForAll's item sets are unavailable; @itemset uses AtlasLoot's when it's installed."]),
			"its tables as expected: nothing said: " .. tostring(said[1]))
		-- (review, 1.0.21) what the question reads per keystroke, made once with the data
		local ad = A.Factions()[1]
		check(ad.words[1] == "argent" and ad.words[2] == "dawn" and A.Sets()[1].norm == " battlegear of might ", "a faction's words and a set's name, kept with their data")
		check(ns.Filters._.StandingWords().honored == 6 and A.Question("what can i buy at honored").standing == 6, "standings: the filters' words")
		-- the rewards
		A.ForgetRewards()
		local rw = A.Rewards()
		local by = {}
		for _, e in ipairs(rw) do by[e.itemID] = e end
		check(#rw == 6 and by[262765] and not by[262764] and not by[20757], "your faction's, both sides', none not in Forever yet: " .. Names(rw))
		check(by[22014].reaction == 6 and by[22014].canBuy and by[19446].canBuy == false and by[18171].canBuy == false,
			"OneForAll's rank + 1 is the game's standing; honored: the honored reward bought, not the exalted one")
		check(by[20253].mine == nil and by[20253].canBuy == false, "a faction not met: not yet")
		check(by[22014].ui == 1420 and by[22014].pinName == "Argent Quartermaster Hasana", "Enter: its quartermaster on the map")
		check(by[22014].kind == "reputation" and by[22014].repReward, "a reward is a Reputation row")
		check(table.concat({ ns.Easy.Verbs(by[22014]) }, "/") == L["show on map"] .. "/" .. L["set waypoint"], "its verbs: the map's")
		-- "<faction> > rewards": from the faction's row
		local got = ns.Pipes.Run("rewards", { { kind = "reputation", factionID = 529, name = "Argent Dawn" } })
		check(#got == 4 and got[1].itemID == 13724 and got[4].itemID == 18171, "argent dawn > rewards: its four, by standing: " .. Names(got))
		check(#ns.Pipes.Run("rewards", { by[22014] }) == 0, "a reward's own row: no rewards of its own")
		-- (review, 1.0.16) the chain as typed: its rows say their kind and are counted when picked; a view on a reward is one
		local chained = UI:Search("argent dawn > rewards")
		check(#chained == 4 and chained[1].kindLabel == ns:KindLabel(ns.providers.reputation) and chained[1].freqKey ~= nil,
			"argent dawn > rewards: its four, as Reputation rows: " .. Names(chained) .. " / " .. tostring(chained[1] and chained[1].kindLabel))
		check(table.concat({ ns.Easy.Verbs(chained[1]) }, "/") == L["show on map"] .. "/" .. L["set waypoint"], "a chained reward's verbs: the map's")
		local again = UI:Search("argent dawn > rewards > rewards")
		check(not (again[1] and again[1].itemID), "> rewards of a reward: none: " .. Names(again))
		local res = UI:Search("@reputation")
		local leak = false
		for _, e in ipairs(res) do if e.repReward then leak = true end end
		check(not leak, "@reputation: the factions, not the rewards")
		-- @itemset: pieces you have, worn or in the bank
		local sets = ns:GetEntries(ps)
		local sb = {}
		for _, e in ipairs(sets) do sb[e.name] = e end
		check(#sets == 3 and sb["Battlegear of Might"].owned == 2 and sb["Battlegear of Might"].total == 3, "2 of 3 pieces: worn and in the bank")
		check((sb["Battlegear of Might"].detail or ""):find(L["%d of %d pieces"]:format(2, 3), 1, true)
			and (sb["Battlegear of Might"].detail or ""):find(L["not in WoW Forever yet"], 1, true), "said, with not in Forever yet")
		res = UI:Search("@itemset class:mine")
		check(#res == 2 and not res[3], "class:mine: the warrior's and the set for any class: " .. Names(res))
		res = UI:Search("@itemset class:priest")
		local esk
		for _, e in ipairs(res) do if e.name == "Spirit of Eskhandar" then esk = e end end
		check(#res == 2 and esk and not sb["Battlegear of Might"].anyClass, "class:priest: a set for three classes, and one for every class (as class:mine): " .. Names(res))
		check(esk.icon == "Interface\\Icons\\INV_Chest_Chain", "an icon of 0: the set's own fallback: " .. tostring(esk.icon))
		-- Enter on a set: its pieces
		local walked
		UI.WalkTo = function(_, t) walked = t end
		sb["Battlegear of Might"].activate(sb["Battlegear of Might"])
		UI.WalkTo = save.walk
		check(walked == "Battlegear of Might > pieces ", "Enter on a set: its chain: " .. tostring(walked))
		res = UI:Search(walked)
		check(#res == 3 and res[1].set == "Battlegear of Might" and res[1].kind == "itemset" and res[1].name == "Helm of Might",
			walked .. ": its three pieces, in order: " .. Names(res))
		check(res[1].kindLabel == ns:KindLabel(ps) and res[1].freqKey ~= nil, "a piece says its kind, and is counted when picked: " .. tostring(res[1].kindLabel))
		res = UI:Search("@itemset")
		check(#res == 3, "@itemset: the sets, not their pieces: " .. Names(res))
		res = UI:Search("@itemset onyxia")
		check(#res == 1 and res[1].name == "Scale of the Gods", "@itemset onyxia: the set with a piece from Onyxia: " .. Names(res))
		-- (1.0.39, the player's call) a search that doesn't name it: a set by its name, not its text ("onyxia" isn't one's)
		local function Sets(r) local n = 0 for _, e in ipairs(r) do if e.kind == "itemset" then n = n + 1 end end return n end
		check(Sets(UI:Search("onyxia")) == 0 and Sets(UI:Search("scale of the gods")) == 1 and Sets(UI:Search("scale gods")) == 1,
			"a plain search: sets by their names only")
		check(Sets(UI:Search("onyx")) == 0 and Sets(UI:Search("@itemset onyx")) == 1, "...the narrowing too; @itemset by its text as ever")
		res = UI:Search("battlegear of might > pieces helm")
		check(#res == 1 and res[1].isDone and res[1].name == "Helm of Might", "> pieces helm: one, yours (worn): " .. Names(res))
		-- the questions
		for _, s in ipairs({ "argent dawn rewards", "what can i buy at honored", "rep rewards", "timbermaw recipes", "exalted rewards",
			"argent dawn rewards i can buy", "my class sets", "warrior sets", "item sets", "pieces of battlegear of might",
			"battlegear of might pieces", "tier sets", "what can i buy from argent dawn" }) do
			check(A.Question(s) ~= nil, s .. ": the armory question")
		end
		for _, s in ipairs({ "what can i buy", "rewards", "my equipment", "argent dawn", "honored", "druid sets", "pieces of eight", "my sets", "sets",
			"timbermaw vendor", "vendor in timbermaw", "timbermaw sells", "argent dawn quartermaster", "where to buy in argent dawn" }) do
			check(A.Question(s) == nil, s .. ": not it")
		end
		ns.db.easyMode = true; UI:EasyChanged()
		UI:Open("what can i buy at honored"); FlushAll()
		local r = UI.Results()
		check(#r == 3, "what can i buy at honored: every faction's up to honored (friendly's too): " .. Names(r))
		UI:Hide(); FlushAll()
		STAND[529] = 5
		A.ForgetRewards()
		UI:Open("what can i buy at honored"); FlushAll()
		r = UI.Results()
		check(#r == 3, "and when you're only friendly: what honored would let you buy, not nothing: " .. Names(r))
		STAND[529] = 6
		A.ForgetRewards()
		UI:Hide(); FlushAll()
		UI:Open("exalted rewards"); FlushAll()
		r = UI.Results()
		check(#r == 2 and r[1].reaction == 8 and r[2].reaction == 8, "exalted rewards: exalted's only: " .. Names(r))
		UI:Hide(); FlushAll()
		-- (review, 1.0.71) standing: after a question's words keeps its rewards, whatever was searched before
		do
			local easyS = ns.db.easyMode
			ns.db.easyMode = false
			UI.lastScan = nil
			UI:Search("@reputation")
			UI.lastScan = nil
			local after = UI:Search("exalted rewards standing:exalted")
			ns.db.easyMode = easyS
			local n = 0
			for _, e in ipairs(after) do if e.repReward then n = n + 1 end end
			check(n == 2, "exalted rewards standing:exalted after @reputation: its two rewards: " .. n)
		end
		UI:Open("argent dawn rewards i can buy"); FlushAll()
		r = UI.Results()
		check(#r == 2 and r[1].canBuy and r[2].canBuy, "argent dawn rewards i can buy: friendly's and honored's: " .. Names(r))
		UI:Hide(); FlushAll()
		UI:Open("my class sets"); FlushAll()
		r = UI.Results()
		check(r[1] and r[1].name == "Battlegear of Might" and #r == 2, "my class sets: the one started first: " .. Names(r))
		UI:Hide(); FlushAll()
		UI:Open("pieces of battlegear of might"); FlushAll()
		r = UI.Results()
		check(#r == 3, "pieces of battlegear of might: " .. Names(r))
		UI:Hide(); FlushAll()
		walked = nil
		UI.WalkTo = function(_, t) walked = t end
		sb["Battlegear of Might"].activate(sb["Battlegear of Might"])
		UI.WalkTo = save.walk
		check(walked == "pieces of battlegear of might", "Enter on a set in Simple mode: its question: " .. tostring(walked))
		UI:Hide(); FlushAll()
		check(A.ToAdvanced(A.Question("my class sets")) == "@itemset class:mine ", "to Advanced: " .. A.ToAdvanced(A.Question("my class sets")))
		check(A.ToAdvanced(A.Question("pieces of battlegear of might")) == "Battlegear of Might > pieces ", "to Advanced: the chain")
		ns.db.easyMode = false; UI:EasyChanged()
		local lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find(L["%d factions' rewards (> rewards)"]:format(4), 1, true), ".integrations: " .. lines)
		check(A.ToAdvanced(A.Question("argent dawn rewards")) == "@reputation is:reward argent dawn ", "to Advanced: @reputation's filters: "
			.. tostring(A.ToAdvanced(A.Question("argent dawn rewards"))))
		check(A.ToAdvanced(A.Question("timbermaw rewards")) == "@reputation is:reward timbermaw hold ", "to Advanced: a faction you haven't met too")
		check(A.ToAdvanced(A.Question("what can i buy at honored")) == "@reputation is:reward standing:<=honored ", "to Advanced: up to a standing: "
			.. tostring(A.ToAdvanced(A.Question("what can i buy at honored"))))
		-- (1.0.27, the player: "@reputation shows only Orgrimmar") the rewards in @reputation's own list, its filters,
		-- sort and groups
		local stub = ns.providers.reputation
		ns.providers.reputation = save.providers.reputation
		ns.providers.reputation._dirty = true
		A.ForgetRewards()
		local all = UI:Search("@reputation is:reward")
		check(#all == 6 and all[1].repReward, "@reputation is:reward: the quartermasters' rewards in its list: " .. #all)
		-- (1.0.40, the player's call) standing: alone is your factions'; with is:reward (or is:canbuy), the rewards'
		local function Kinds(r) local f, w = 0, 0 for _, e in ipairs(r) do if e.repReward then w = w + 1 else f = f + 1 end end return f, w end
		local _, w1 = Kinds(UI:Search("@reputation standing:honored"))
		local _, w2 = Kinds(UI:Search("@reputation is:reward standing:honored"))
		local _, w3 = Kinds(UI:Search("@reputation -is:reward standing:honored"))
		local honored = ns.Filters._.KEYS.standing("honored")
		ns.Filters.rewardsAsked = false
		local faction = honored({ kind = "reputation", name = "Argent Dawn", reaction = 6 })
		check(faction and w1 == 0 and w2 >= 1 and w3 == 0, "standing: your factions; with is:reward its rewards: " .. w1 .. "/" .. w2 .. "/" .. w3)
		local can = UI:Search("@reputation is:canbuy")
		local ok = #can > 0
		for _, e in ipairs(can) do if not e.canBuy then ok = false end end
		check(ok, "@reputation is:canbuy: those your standing allows: " .. #can)
		local sorted = UI:Search("@reputation is:reward sort:standing")
		local up = true
		for i = 2, #sorted do if (sorted[i].reaction or 0) < (sorted[i - 1].reaction or 0) then up = false end end
		check(#sorted == 6 and up, "sort:standing: the lowest first")
		local AG = ns.Aggregate
		check(AG.FIELDS.faction.text(all[1]) == all[1].faction and all[1].faction ~= nil and AG.FIELDS.standing.num(all[1]) == all[1].reaction,
			"Group's faction and standing fields")
		local timber = UI:Search("@reputation is:reward timbermaw")
		check(#timber == 1 and timber[1].itemID == 20253, "@reputation is:reward timbermaw: a faction's: " .. #timber)
		-- (1.0.39, the player's call) a plain search: a reward by its name, not its faction's or standing's words
		local function Rewards(r) local n = 0 for _, e in ipairs(r) do if e.repReward then n = n + 1 end end return n end
		check(Rewards(UI:Search("timbermaw")) == 0 and Rewards(UI:Search(ns.Lower(timber[1].name))) >= 1, "a plain search: rewards by their names only")
		-- (1.0.28, the player's ask) AtlasLoot's faction loot in @reputation too, by the standing it needs; one OneForAll lists once
		local lootWas = ns.providers.loot
		ns.providers.loot = { id = "loot", label = "Loot", aliases = {}, _dirty = true, collect = function() return {
			{ key = "al1", itemID = 21210, name = "Signet Ring of the Bronze Dragonflight", addon = "AtlasLootClassic_Factions", content = "BroodOfNozdormu",
				detail = "Exalted  Brood of Nozdormu" },
			{ key = "al2", itemID = 22014, name = "Hallowed Brazier", addon = "AtlasLootClassic_Factions", content = "ArgentDawn", detail = "Honored  Argent Dawn" },
			{ key = "al3", itemID = 9999, name = "A Dungeon Sword", addon = "AtlasLootClassic_DungeonsAndRaids", content = "SFK", detail = "Arugal  Shadowfang Keep" },
		} end }
		ns.providers.reputation._dirty = true
		local brood = UI:Search("@reputation is:reward brood")
		check(#brood == 1 and brood[1].itemID == 21210 and brood[1].reaction == 8 and brood[1].faction == "Brood of Nozdormu" and brood[1].canBuy == false
			and brood[1].kind == "reputation", "AtlasLoot's faction loot: a reward of its faction, at the standing it needs: " .. #brood)
		-- (review, 1.0.38) said as OneForAll's are; its faction a question of its own; the answer has it, as Alt+`'s line does
		check((brood[1].detail or ""):find(A.StandingName(8), 1, true) and (rawget(brood[1], "_ltext") or rawget(brood[1], "text") or ""):find(ns.Lower(L["reputation reward"]), 1, true),
			"AtlasLoot's reward said as OneForAll's: " .. tostring(brood[1].detail))
		-- (review, 1.0.73) the standing's name is Util.lua's, whatever OneForAll's says (and without it)
		do
			local snWas = A.StandingName
			A.StandingName = function() return "OFAWORD" end
			local one
			for _, e in ipairs(I.FactionLoot({}, {})) do if e.itemID == 21210 then one = e end end
			A.StandingName = snWas
			check(one and (one.detail or ""):find(ns.StandingName(8), 1, true) and not (one.detail or ""):find("OFAWORD", 1, true),
				"AtlasLoot's reward: the standing named by ns.StandingName: " .. tostring(one and one.detail))
		end
		local can
		for _, e in ipairs(I.FactionLoot({ ["brood of nozdormu"] = 8 }, {})) do if e.itemID == 21210 then can = e end end
		check(can and can.canBuy and (can.detail or ""):find(L["you can buy it"], 1, true) and (rawget(can, "text") or ""):find("canbuy", 1, true),
			"one your standing allows: says you can buy it, is:canbuy's word: " .. tostring(can and can.detail))
		local bq = A.Question("brood of nozdormu rewards")
		local ba = bq and A.Answer(bq)
		check(bq and ba and #ba == 1 and ba[1].itemID == 21210, "brood of nozdormu rewards: AtlasLoot's faction, a question; its reward: " .. tostring(ba and #ba))
		local adq = A.Question("argent dawn rewards")
		local ad = A.Answer(adq)
		local hasAL = false
		for _, e in ipairs(ad) do if e.itemID == 22014 then hasAL = true end end
		check(hasAL, "argent dawn rewards: AtlasLoot's too, as @reputation is:reward argent dawn lists them")
		local braziers = 0
		for _, e in ipairs(UI:Search("@reputation is:reward brazier")) do if e.itemID == 22014 then braziers = braziers + 1 end end
		check(braziers == 1, "an item both list: once (OneForAll's, with its quartermaster): " .. braziers)
		check(#UI:Search("@reputation dungeon sword") == 0, "a dungeon's loot: not a reward")
		-- (review, 1.0.38) one item in Loot and in reputation's rewards: still the clear winner
		local W = ns.UI._Scan.Winner
		local x1, x2 = { cat = "loot", sc = 2, e = { itemID = 21210 } }, { cat = "character", sc = 1, e = { itemID = 21210 } }
		check(W({ x1, x2 }, 2) == x1.e and W({ x1, { cat = "character", sc = 1, e = { itemID = 5 } } }, 2) == nil,
			"one item in two categories: the winner; two things: none")
		-- (review, 1.0.38) the bar's reward filters only where there are rewards; the reward rows kept over @reputation's own read
		local resWas = UI.results
		UI.results = { { kind = "reputation", name = "Orgrimmar", key = 76 } }
		local offered = {}
		for _, o in ipairs(ns.Bar.Options("filter")) do offered[o.id] = true end
		UI.results = { { kind = "reputation", name = "Orgrimmar", key = 76 }, { kind = "reputation", name = "Hallowed Brazier", repReward = true } }
		local offered2 = {}
		for _, o in ipairs(ns.Bar.Options("filter")) do offered2[o.id] = true end
		UI.results = resWas
		check(not offered["is:reward"] and not offered["is:canbuy"] and offered2["is:reward"], "reward filters: offered only with rewards shown")
		local r1 = A.Rewards()
		local rp = ns.providers.reputation
		rp._firedOwn, rp._collectedAt = true, GetTime()
		A.watch:GetScript("OnEvent")(A.watch, "UPDATE_FACTION")
		local kept = A.Rewards() == r1
		rp._firedOwn = false
		A.watch:GetScript("OnEvent")(A.watch, "UPDATE_FACTION")
		check(kept and A.Rewards() ~= r1, "the reward rows: kept over @reputation's own header read, made again on a real change")
		-- (review, 1.0.34) AtlasLoot's own: its rows read where they are, @loot not built inside @reputation
		local built = false
		ns.providers.loot = { id = "loot", label = "Loot", aliases = {}, atlasLoot = true, _dirty = true, collect = function() built = true return {} end }
		local rowsWas = I.loot.rows
		I.loot.rows, I.loot.factionRows = { { itemID = 21210, name = "Signet Ring of the Bronze Dragonflight", addon = "AtlasLootClassic_Factions",
			content = "BroodOfNozdormu", detail = "Exalted  Brood of Nozdormu" } }, nil
		local fl = I.FactionLoot({}, {})
		check(#fl == 1 and fl[1].reaction == 8 and not built, "AtlasLoot's faction loot read from its rows, @loot not built: " .. #fl)
		I.loot.rows, I.loot.factionRows = rowsWas, nil
		ns.providers.loot = lootWas
		ns.providers.reputation._dirty = true
		ns.providers.reputation = stub

		-- not in the shape expected: said once, the other still there
		said = {}
		OneForAll.ARMORY_SETS = { "renamed" }
		Fresh()
		-- (no AtlasLoot set data here: nothing to fall back on; with it, AtlasLoot's: tests/smoke/itemsets_atlasloot.lua)
		check(not ns.providers.itemset and A.Sets() == nil and A.Question("argent dawn rewards") ~= nil, "sets changed, no AtlasLoot sets here: no @itemset, the rewards still")
		check(Said(L["OneForAll's item sets are unavailable; @itemset uses AtlasLoot's when it's installed."]), "said in chat, naming the fallback (1.4.16): " .. tostring(said[1]))
		_G.OneForAll = nil
		Fresh()
		check(not ns.providers.itemset and A.Sets() == nil and A.Question("argent dawn rewards") == nil, "without OneForAll or AtlasLoot's sets: none, no question")
	end)
	_G.OneForAll = save.lib
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	ns.Print, I.SpotXY, UI.WalkTo = save.print, save.spot, save.walk
	I.failed, OA.on, _G.UnitClass, _G.UnitFactionGroup = save.failed, save.on, save.class, save.side
	_G.GetFactionInfoByID, _G.C_Reputation = save.fac, save.rep
	_G.GetItemCount, _G.IsEquippedItem = save.count, save.eq
	if C_Item then C_Item.GetItemCount, C_Item.IsEquippedItem = save.citem, save.ceq end
	ns.db.easyMode = save.easy; UI:EasyChanged()
	OA.Forget()
	UI:Hide(); FlushAll()
	if not ok then check(false, "oneforall_armory: " .. tostring(err)) end
end
