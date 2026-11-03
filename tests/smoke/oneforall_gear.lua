-- OneForAll's gear value (1.0.5, the player's ask; Providers/Integrations/OneForAll/Gear.lua): while it's installed, is:upgrade
-- takes its verdict (up by a percent, the slot empty: one; down, the same, worn, unknown: not), in place of Terminal's
-- weights; Terminal's own when you picked roles in .weights; Terminal's checks before stay (your level, what you can
-- use). @loot has its planner's gear (1.0.25: was @gearplan; one AtlasLoot lists already left out), each by its source
-- (source:quest, source:raid...; "raid loot", "dungeon gear"); "Why is this here?" says whose
-- verdict it was.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local I, OA, L, F = ns.Integrations, ns.OneForAll, ns.L, ns.Filters
local G = OA.Gear

io.write("[oneforall: its gear value decides upgrades]\n")
do
	local KINDS = { "book", "tame", "itemset", "transport", "loot" } -- (@loot: OneForAll's own, AtlasLoot's left out here)
	local save = { providers = ns.providers, order = ns.providerOrder, print = ns.Print, lib = rawget(_G, "OneForAll"), failed = I.failed,
		on = OA.on, gii = C_Item.GetItemInfo, gis = C_Item.GetItemStats, gdl = C_Item.GetDetailedItemLevelInfo, gii2 = C_Item.GetItemInfoInstant,
		cached = C_Item.IsItemDataCachedByID, name = C_Item.GetItemNameByID, level = _G.UnitLevel, class = _G.UnitClass, can = C_PlayerInfo.CanUseItem,
		link = _G.GetInventoryItemLink, id = _G.GetInventoryItemID, roles = F.MyRoles, side = _G.UnitFactionGroup }
	local said = {}
	ns.Print = function(_, m) said[#said + 1] = m end
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
		-- a level 20 warrior in a Str helm; helms Terminal's weights and OneForAll's judge apart
		local ITEMS = {
			[990] = { "Worn Helm", "|Hitem:990|h", 2, 20, 15, "Armor", "Mail", 1, "INVTYPE_HEAD" },
			[991] = { "Agi Helm", "|Hitem:991|h", 2, 22, 18, "Armor", "Mail", 1, "INVTYPE_HEAD" }, -- (Terminal: a warrior wants no agility much)
			[992] = { "Big Str Helm", "|Hitem:992|h", 2, 22, 18, "Armor", "Mail", 1, "INVTYPE_HEAD" }, -- (Terminal: an upgrade)
			[993] = { "Too High Helm", "|Hitem:993|h", 2, 40, 40, "Armor", "Mail", 1, "INVTYPE_HEAD" },
			[994] = { "Some Ring", "|Hitem:994|h", 2, 20, 15, "Armor", "Misc", 1, "INVTYPE_FINGER" },
			[996] = { "Plain Helm", "|Hitem:996|h", 2, 20, 15, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		}
		local STATS = { [990] = { ITEM_MOD_STRENGTH_SHORT = 5 }, [991] = { ITEM_MOD_AGILITY_SHORT = 6 }, [992] = { ITEM_MOD_STRENGTH_SHORT = 12 },
			[993] = { ITEM_MOD_STRENGTH_SHORT = 30 }, [994] = { ITEM_MOD_STAMINA_SHORT = 3 }, [996] = { ITEM_MOD_STRENGTH_SHORT = 6 } }
		local function IdOf(x) return tonumber(tostring(x):match("item:(%d+)")) or tonumber(x) end
		C_Item.GetItemInfo = function(id) local t = ITEMS[IdOf(id) or 0] if t then return unpack(t) end end
		C_Item.GetItemStats = function(link) return STATS[IdOf(link)] end
		C_Item.GetDetailedItemLevelInfo = function(link) local t = ITEMS[IdOf(link)] return t and t[4] end
		C_Item.GetItemInfoInstant = function(id) local t = ITEMS[IdOf(id)] return IdOf(id), t and t[6], t and t[7], t and t[9] end
		C_Item.IsItemDataCachedByID = function() return true end
		C_Item.GetItemNameByID = function(id) local t = ITEMS[id] return t and t[1] end
		_G.UnitLevel = function() return 20 end
		_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
		_G.UnitFactionGroup = function() return "Alliance" end
		C_PlayerInfo.CanUseItem = function() return true end
		_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:990|h[Worn Helm]|h" end end
		_G.GetInventoryItemID = function(_, slot) if slot == 1 then return 990 end end
		F.MyRoles = function() return nil end
		F.ClearCache()
		-- Terminal's own, without OneForAll
		_G.OneForAll = nil
		Fresh()
		local fit = F.GearFit()
		check(fit({ itemID = 992, kind = "items" }) and not fit({ itemID = 991, kind = "items" }), "without OneForAll: Terminal's weights (Str over Agi)")
		-- OneForAll's verdict: it thinks the Agi helm the upgrade, the Str one a downgrade
		local CHANGE = { [991] = { "up", 14.6 }, [992] = { "down", 3 }, [993] = { "up", 80 }, [994] = { "new" }, [990] = { "worn" }, [996] = { "new" } }
		local calls = {}
		_G.OneForAll = {
			BOOKS = { { name = "A Book", questId = 1, itemId = 2 } },
			GearValue = { Change = function(id) calls[id] = (calls[id] or 0) + 1 local c = CHANGE[id] if c then return c[1], c[2] end end },
			-- (its entries as UI/GearPlanner.lua's buildIndex makes them: a boss's with its dungeon, a quest's id, a profession)
			GearIndex = function() return { { id = 992, name = "Big Str Helm", src = "SFK - Arugal", boss = "Arugal", d = { name = "Shadowfang Keep", minLevel = 18 }, lvl = 18 },
				{ id = 995, name = "Quest Boots", src = "Quest: The Test", qid = 100, side = "H" },
				{ id = 991, src = "Gnomeregan - trash", boss = "trash mobs", d = { name = "Gnomeregan", minLevel = 18 }, lvl = 18 },
				{ id = 991, src = "a second time" },
				{ id = 1001, name = "Our Quest Boots", src = "Quest: Ours", qid = 101, side = "A" },
				{ id = 1002, name = "Raid Crown", src = "MC - Garr", boss = "Garr", d = { name = "Molten Core", raid = true, minLevel = 60 } },
				{ id = 1003, name = "Crafted Belt", src = "Blacksmithing 200", prof = "Blacksmithing" },
				{ id = 1004, name = "Rep Cloak", src = "Argent Dawn (Honored)" } } end,
		}
		Fresh()
		check(G.Available() and G.Judge(), "its verdict there")
		F.ClearCache()
		fit = F.GearFit()
		local agi, str = { itemID = 991, kind = "items" }, { itemID = 992, kind = "items" }
		check(fit(agi) and not fit(str), "OneForAll's verdict: its upgrade, not its downgrade")
		check(F.GainOf(agi).oneForAll == 14.6 and F.GainOf(agi).gain == 14.6, "the gain: its percent")
		check(not fit({ itemID = 993, kind = "items" }), "Terminal's checks stay: above your level, whatever OneForAll says")
		local ring = { itemID = 994, kind = "items" }
		check(fit(ring) and F.GainOf(ring).empty, "the slot empty (its \"new\"): an upgrade")
		check(not fit({ itemID = 990, kind = "items" }), "the one you wear: not")
		C_PlayerInfo.CanUseItem = function(id) return id ~= 991 end
		F.ClearCache()
		fit = F.GearFit()
		check(not fit({ itemID = 991, kind = "items" }), "one your class can't use: not, whatever OneForAll says")
		C_PlayerInfo.CanUseItem = function() return true end
		-- "Why is this here?": whose verdict
		F.ClearCache()
		fit = F.GearFit()
		fit(agi)
		local why = table.concat(UI:WhyLines(agi), "\n")
		check(why:find(L["an upgrade by OneForAll's gear value: %d%% over what you wear"]:format(15), 1, true), "why: OneForAll's, by how much: " .. why)
		-- (review, 1.0.13) "new" with a helm worn: what's worn is worth nothing by its weights, not an empty slot
		local plain = { itemID = 996, kind = "items" }
		check(fit(plain) and not F.GainOf(plain).empty, "\"new\" over a worn helm: an upgrade, its slot not empty")
		why = table.concat(UI:WhyLines(plain), "\n")
		check(why:find(L["an upgrade by OneForAll's gear value: what you wear there is worth nothing by its weights"], 1, true), "why: " .. why)
		-- a copy with a random suffix: Terminal's judgement (OneForAll's is of the bare item), not OneForAll's
		local monkey = { itemID = 991, kind = "items", link = "|cff1eff00|Hitem:991::::::612:|h[Agi Helm of the Monkey]|h|r" }
		calls[991] = 0
		check(not fit(monkey) and calls[991] == 0, "a random suffix: not asked of OneForAll, Terminal's weights (Agi for a warrior: not)")
		-- one the client hasn't got: not asked of OneForAll either (it would ask the server)
		F.ClearCache()
		-- (judged once while the client had it, then dropped from its cache: as read then, never asked of OneForAll)
		local have991 = true
		C_Item.IsItemDataCachedByID = function(id) return id ~= 991 or have991 end -- (before the filter is made: it keeps the call)
		fit = F.GearFit()
		fit({ itemID = 991, kind = "items" })
		have991 = false
		calls[991] = 0
		fit({ itemID = 991, kind = "items" })
		check(calls[991] == 0, "an item the client hasn't got: not asked of OneForAll")
		C_Item.IsItemDataCachedByID = function() return true end
		F.ClearCache()
		fit = F.GearFit()
		-- roles picked in .weights: Terminal's own
		F.MyRoles = function() return { "fury" } end
		check(G.Judge() == nil, "roles picked: OneForAll's verdict not taken")
		F.MyRoles = function() return nil end
		-- its planner's gear: @loot's (no @gearplan), each by where it comes from
		local pl = ns.providers.loot
		check(pl and ns.providers.gearplan == nil, "@loot from OneForAll's planner, without AtlasLoot; no @gearplan")
		local rows = ns:GetEntries(pl)
		local by, names = {}, {}
		for _, e in ipairs(rows) do by[e.itemID] = e; names[#names + 1] = e.name end
		check(#rows == 6 and not by[995] and by[991].name == "Agi Helm", "each item once, the other faction's left out, a name from the game: " .. table.concat(names, " | "))
		check(by[992].detail == "Arugal  Shadowfang Keep" and by[992].kind == "loot" and by[992].kindLabel ~= nil,
			"a boss's said as AtlasLoot's rows are: " .. tostring(by[992].detail))
		local function Src(q)
			local out = {}
			for _, e in ipairs(UI:Search("@loot " .. q)) do out[#out + 1] = e.itemID end
			table.sort(out)
			return table.concat(out, ",")
		end
		check(Src("source:dungeon") == "991,992" and Src("source:raid") == "1002" and Src("source:quest") == "1001"
			and Src("source:crafted") == "1003" and Src("source:rep") == "1004", "source: dungeon, raid, quest, crafted, reputation: "
			.. Src("source:dungeon") .. " / " .. Src("source:raid") .. " / " .. Src("source:quest"))
		local res = UI:Search("@loot is:upgrade")
		check(#res == 1 and res[1].itemID == 991, "@loot is:upgrade: OneForAll's upgrade among its gear: " .. tostring(res[1] and res[1].name))
		check(ns.Integrations.LootPlace(by[1002]).kind == "raid" and ns.Integrations.LootPlace(by[1001]) == nil, "its raid's place a raid's (left out of upgrades, as AtlasLoot's raids), a quest's none")
		-- (review, 1.0.34) to chat: a boss's "dropped by", a quest's, a recipe's or a faction's "from"; Shift+Enter pressed by the game
		local SH = ns.Share
		check(SH.LootSource(by[992]) == L["dropped by %s in %s"]:format("Arugal", "Shadowfang Keep") and SH.LootSource(by[1001]) == L["from %s"]:format("Quest: Ours")
			and SH.LootSource(by[1003]) == L["from %s"]:format("Blacksmithing 200") and SH.LootSource(by[1004]) == L["from %s"]:format("Argent Dawn (Honored)")
			and SH.LootSource({ kind = "loot", addon = "AtlasLootClassic_Factions", detail = "Exalted  Brood of Nozdormu" }) == L["from %s"]:format("Brood of Nozdormu (Exalted)"),
			"to chat: a boss's dropped by, the rest from: " .. tostring(SH.LootSource(by[1001])))
		check(by[1001].secondarySecure and by[1001].secondaryIsOpen, "Shift+Enter: the chat box opened by the game's press")
		-- (review, 1.0.34) made once for OneForAll's index: the same rows again, an item named since added
		local raw = OneForAll.GearIndex()
		local nameWas = C_Item.GetItemNameByID
		C_Item.GetItemNameByID = function(id) if id ~= 991 then return nameWas(id) end end
		OneForAll.GearIndex = function() return raw end
		G.Forget()
		local r1 = G.Rows()
		local r2 = G.Rows()
		C_Item.GetItemNameByID = nameWas
		local r3 = G.Rows()
		local named = false
		for _, e in ipairs(r3) do if e.itemID == 991 then named = true end end
		check(r1 == r2 and r2 == r3 and #r1 == 6 and named, "OneForAll's rows made once for its index; one named since added: " .. #r1)
		G.Forget()
		-- Simple mode: "raid loot"
		ns.db.easyMode = true
		-- (review, 1.0.35) "from quests", "from reputation": not loot's source words (they took "rewards from quests")
		for _, line in ipairs({ "rewards from quests", "gear from quests", "reputation from quests", "patterns from reputation" }) do
			local adv = ns.Easy.ToAdvanced(line)
			check(not tostring(adv):find("source:", 1, true), line .. ": no source: filter: " .. tostring(adv))
		end
		local raid = {}
		for _, e in ipairs(UI:Search("raid loot")) do if e.itemID then raid[#raid + 1] = e.itemID end end
		check(#raid == 1 and raid[1] == 1002, "raid loot (Simple mode): the raid's: " .. table.concat(raid, ","))
		ns.db.easyMode = false
		-- AtlasLoot's rows by their module and place
		local I = ns.Integrations
		check(I.LootSource({ kind = "loot", addon = "AtlasLootClassic_Crafting" }) == "crafted"
			and I.LootSource({ kind = "loot", addon = "AtlasLootClassic_Factions" }) == "reputation"
			and I.LootSource({ kind = "loot", addon = "AtlasLootClassic_PvP" }) == "pvp", "AtlasLoot's: its crafting, factions, PvP modules")
		local lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find(L["its gear value decides is:upgrade"], 1, true), ".integrations: " .. lines)
		-- its GearValue changed: Terminal's own again
		OneForAll.GearValue = { Change = "moved" }
		F.ClearCache()
		fit = F.GearFit()
		check(not G.Available() and fit({ itemID = 992, kind = "items" }), "its GearValue changed: Terminal's weights")
	end)
	_G.OneForAll = save.lib
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	ns.Print, I.failed, OA.on = save.print, save.failed, save.on
	C_Item.GetItemInfo, C_Item.GetItemStats, C_Item.GetDetailedItemLevelInfo = save.gii, save.gis, save.gdl
	C_Item.GetItemInfoInstant, C_Item.IsItemDataCachedByID, C_Item.GetItemNameByID = save.gii2, save.cached, save.name
	_G.UnitLevel, _G.UnitClass, C_PlayerInfo.CanUseItem = save.level, save.class, save.can
	_G.GetInventoryItemLink, _G.GetInventoryItemID, F.MyRoles = save.link, save.id, save.roles
	_G.UnitFactionGroup = save.side
	F.ClearCache()
	OA.Forget()
	if not ok then check(false, "oneforall_gear: " .. tostring(err)) end
end
