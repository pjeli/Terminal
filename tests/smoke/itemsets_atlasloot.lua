-- @itemset without OneForAll (1.4.9, Providers/Integrations/OneForAll/Armory.lua): AtlasLoot's public set data
-- (AtlasLoot.Data.ItemSet, Data.Requirements), read while it's installed. It gives no list of its sets, so they're the
-- sets of the items in its loot list; a set's name is the game's, where a piece comes from is its loot rows' boss and
-- place, its classes those AtlasLoot lets wear its first piece. OneForAll's list comes first whenever it's there.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L, I, OA = ns.L, ns.Integrations, ns.OneForAll
local A = ns.Armory

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows or {}) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[item sets from AtlasLoot, without OneForAll]\n")
do
	local save = { providers = ns.providers, order = ns.providerOrder, print = ns.Print, lib = rawget(_G, "OneForAll"), on = OA.on,
		failed = I.failed, atlas = rawget(_G, "AtlasLoot"), loaded = OA.Loaded, class = _G.UnitClass, side = _G.UnitFactionGroup,
		count = _G.GetItemCount, eq = _G.IsEquippedItem, citem = C_Item and C_Item.GetItemCount, ceq = C_Item and C_Item.IsEquippedItem,
		inst = C_Item and C_Item.GetItemInfoInstant, name = C_Item and C_Item.GetItemNameByID, unknown = rawget(_G, "UNKNOWN"),
		head = rawget(_G, "INVTYPE_HEAD"), chest = rawget(_G, "INVTYPE_CHEST"), waist = rawget(_G, "INVTYPE_WAIST"),
		clock = _G.debugprofilestop, walk = UI.WalkTo, bg = ns.background }
	local ok, err = pcall(function()
		_G.OneForAll = nil
		OA.Loaded = function() return type(rawget(_G, "OneForAll")) == "table" end
		_G.UnitClass = function() return "Warrior", "WARRIOR" end
		_G.UnitFactionGroup = function() return "Alliance" end
		_G.UNKNOWN, _G.INVTYPE_HEAD, _G.INVTYPE_CHEST, _G.INVTYPE_WAIST = "Unknown", "Head", "Chest", "Waist"
		-- the game: the Helm of Might worn, its belt in the bank
		local HAVE, WORN = { [16864] = 1 }, { [16866] = true }
		local function Count(id) return HAVE[id] or 0 end
		local function Worn(id) return WORN[id] == true end
		_G.GetItemCount, _G.IsEquippedItem = Count, Worn
		C_Item.GetItemCount, C_Item.IsEquippedItem = Count, Worn
		local INFO = { [16866] = { "Plate", "INVTYPE_HEAD", 101, 4, 4 }, [16865] = { "Plate", "INVTYPE_CHEST", 102, 4, 4 },
			[16864] = { "Plate", "INVTYPE_WAIST", 103, 4, 4 }, [16813] = { "Cloth", "INVTYPE_HEAD", 201, 4, 1 },
			[16815] = { "Cloth", "INVTYPE_ROBE", 202, 4, 1 }, [12940] = { "One-Handed Swords", "INVTYPE_WEAPON", 301, 2, 7 } }
		C_Item.GetItemInfoInstant = function(id)
			local x = INFO[id]
			if x then return id, "Armor", x[1], x[2], x[3], x[4], x[5] end
		end
		C_Item.GetItemNameByID = function(id) return id == 16864 and "Belt of Might" or nil end
		-- AtlasLoot's set data: Might (a warrior's), Prophecy (a priest's), Dal'Rend's Arms (anyone's), and a set number the
		-- game doesn't know here
		local SETS = { [209] = { 16866, 16865, 16864 }, [210] = { 16813, 16815 }, [41] = { 12940 }, [999] = { 5555 } }
		local OF = { [16866] = 209, [16865] = 209, [16813] = 210, [16815] = 210, [12940] = 41, [5555] = 999 }
		local NAME = { [209] = "Battlegear of Might", [210] = "Vestments of Prophecy", [41] = "Dal'Rend's Arms" }
		local asked, bonusIn = 0, false
		_G.AtlasLoot = { Data = {
			ItemSet = {
				GetSetIDforItemID = function(id) asked = asked + 1 return OF[id] end,
				GetSetItems = function(set) return SETS[set] end,
				GetSetName = function(set) return NAME[set] or UNKNOWN end,
				GetSetBonusString = function(set)
					if set == 209 then return "(3) Set: |cffffffffIncreases the block value of your shield by 30.|r\n(5) Set: |cffffffffGain 5 Rage when you parry.|r\n" end
					if set == 210 and bonusIn then return "(3) Set: |cffffffff-0.1 sec to the casting time of your Flash Heal.|r\n" end
					return false -- (the game hasn't sent the bonus's text yet)
				end,
			},
			Requirements = {
				HasRequirements = function(id) return OF[id] == 209 or OF[id] == 210 end,
				ClassCanUseItem = function(class, id) return (OF[id] == 209 and class == "WARRIOR") or (OF[id] == 210 and class == "PRIEST") end,
			},
		} }
		local LOOT = {
			{ name = "Helm of Might", itemID = 16866, detail = "Garr  Molten Core" },
			{ name = "Some Ring", itemID = 4001, detail = "Garr  Molten Core" },
			{ name = "Breastplate of Might", itemID = 16865, detail = "Golemagg the Incinerator  Molten Core" },
			{ name = "Circlet of Prophecy", itemID = 16813, detail = "Garr  Molten Core" },
			{ name = "Robes of Prophecy", itemID = 16815, detail = "Golemagg the Incinerator  Molten Core" },
			{ name = "Helm of Might", itemID = 16866, detail = "Trash  Molten Core" }, -- (twice in its lists: once a set)
			{ name = "Dal'Rend's Sacred Charge", itemID = 12940, detail = "Warchief Rend Blackhand  Upper Blackrock Spire" },
			{ name = "Odd Thing", itemID = 5555, detail = "Nobody  Nowhere" },
		}
		local function Lists()
			ns.providers, ns.providerOrder = {}, {}
			for _, id in ipairs(save.order) do
				if id ~= "itemset" and id ~= "loot" and id ~= "book" then ns.providers[id] = save.providers[id]; ns.providerOrder[#ns.providerOrder + 1] = id end
			end
			ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = function()
				local out = {}
				for i, r in ipairs(LOOT) do local e = {} for k, v in pairs(r) do e[k] = v end e.key = i out[i] = e end
				return out
			end })
		end
		local function Fresh()
			Lists()
			I.failed, OA.on = {}, nil
			OA.Forget(); A.ForgetAtlasSets()
			I._.SetupOneForAll(); I._.SetupItemSets()
			ns:AliasesChanged()
			if ns.Pipes and ns.Pipes.ClearSteps then ns.Pipes.ClearSteps() end
			UI.lastScan, UI.lastExtra = nil, nil
		end

		Fresh()
		local p = ns.providers.itemset
		check(p ~= nil and ns:ResolveProvider("itemsets") == p and p.follows == "loot", "without OneForAll: @itemset from AtlasLoot, made again with its loot list")
		local rows = p and ns:GetEntries(p) or {}
		check(Names(rows) == "Battlegear of Might | Vestments of Prophecy | Dal'Rend's Arms",
			"the sets of its loot's items, as its lists meet them, each once; a set the game doesn't know left out: " .. Names(rows))
		local by = {}
		for _, e in ipairs(rows) do by[e.name] = e end
		local might, proph, rend = by["Battlegear of Might"], by["Vestments of Prophecy"], by["Dal'Rend's Arms"]
		check(might and might.total == 3 and might.owned == 2 and might.setID == 209 and might.source == "AtlasLoot",
			"a set: its pieces, those you have (worn, in the bank): " .. tostring(might and might.owned) .. "/" .. tostring(might and might.total))
		check(might and might.classFile == "WARRIOR" and not might.anyClass and might.armor == "Plate" and might.sub == "Molten Core" and might.icon == 102,
			"whose it is (AtlasLoot's requirements), its armour (the game's word), where it drops, its chest's icon: "
				.. tostring(might and might.classFile) .. " / " .. tostring(might and might.armor) .. " / " .. tostring(might and might.sub) .. " / " .. tostring(might and might.icon))
		check(might and might.detail == ns.Detail("Molten Core", L["%d of %d pieces"]:format(2, 3), "Plate", "Warrior"), "its line: " .. tostring(might and might.detail))
		check(might and #might.bonuses == 2 and might.bonuses[1].pieces == 3 and might.bonuses[2].text == "Gain 5 Rage when you parry.",
			"its bonuses, read back from AtlasLoot's words: " .. tostring(might and #might.bonuses))
		check(rend and rend.anyClass == true and rend.classFiles == nil and rend.armor == nil and rend.sub == "Upper Blackrock Spire",
			"a set anyone may wear (no requirement): any class; a weapon set has no armour: " .. tostring(rend and rend.detail))
		check(rend and rend.detail == ns.Detail("Upper Blackrock Spire", L["%d of %d pieces"]:format(0, 1), L["any class"]), "(no empty part in its line): " .. tostring(rend and rend.detail))

		-- its tooltip; bonuses the game hadn't sent are asked for again when shown
		local function Tip(e)
			local tip = { lines = {} }
			function tip:SetText(t) self.lines[#self.lines + 1] = t end
			function tip:AddLine(t) self.lines[#self.lines + 1] = t end
			function tip:SetHyperlink(l) self.lines[#self.lines + 1] = l end
			e.tooltip(e, tip)
			return table.concat(tip.lines, "\n")
		end
		local all = Tip(might)
		check(all:find(L["Item sets from AtlasLoot"], 1, true) and not all:find("OneForAll", 1, true)
			and all:find(L["(%d) Set: %s"]:format(3, "Increases the block value of your shield by 30."), 1, true)
			and all:find("Belt of Might", 1, true), "a set's tooltip: whose list, its bonuses, its pieces (one not in the loot named by the game): " .. all)
		check(proph and #proph.bonuses == 0 and not Tip(proph):find("Flash Heal", 1, true), "bonuses not sent yet: none said")
		bonusIn = true
		check(Tip(proph):find("Flash Heal", 1, true) ~= nil, "shown again once they're in: asked for anew")

		-- its pieces: where each comes from is its loot rows'
		local pieces = A.PieceRows(209)
		check(#pieces == 3 and pieces[1].name == "Helm of Might" and pieces[1].slot == "Head" and pieces[1].have == "equipped"
			and pieces[1].sources[1] == "Garr, Molten Core" and pieces[1].sources[2] == "Trash, Molten Core" and pieces[1].source == "AtlasLoot",
			"a set's pieces: the slot as the game says it, the boss and place of each loot row: " .. Names(pieces) .. " / " .. tostring(pieces[1] and pieces[1].sources[1]))
		check(pieces[3] and pieces[3].name == "Belt of Might" and #pieces[3].sources == 0
			and Tip(pieces[3]):find(L["AtlasLoot lists it in no boss's loot"], 1, true), "a piece in no loot list: said in AtlasLoot's name")
		local res = UI:Search("battlegear of might > pieces")
		check(#res == 3 and res[1].setPiece and res[1].name == "Helm of Might", "<set> > pieces: " .. Names(res))

		-- searched and asked as OneForAll's are
		local function Has(list, name) for _, e in ipairs(list) do if e.name == name then return true end end return false end
		res = UI:Search("@itemset class:mine")
		check(#res == 2 and Has(res, "Battlegear of Might") and Has(res, "Dal'Rend's Arms"), "@itemset class:mine: a warrior's and anyone's: " .. Names(res))
		res = UI:Search("@itemset class:priest")
		check(#res == 2 and Has(res, "Vestments of Prophecy") and not Has(res, "Battlegear of Might"), "@itemset class:priest: " .. Names(res))
		res = UI:Search("@itemset golemagg")
		check(#res == 2, "@itemset golemagg: the sets with a piece of his: " .. Names(res))
		check(A.Question("my class sets") ~= nil and A.Question("pieces of battlegear of might") ~= nil and A.Question("item sets") ~= nil, "the questions, as with OneForAll")
		local lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find("  " .. L["Item sets:"] .. " " .. L["%d from AtlasLoot (@itemset)"]:format(3), 1, true), ".integrations says whose they are: " .. lines)

		-- every loot row is looked at once; the idle warm-up reads them ahead a slice a frame
		local was = asked
		check(A.AtlasSets() ~= nil and asked == was, "asked again: AtlasLoot isn't asked about its items twice: " .. (asked - was))
		A.ForgetAtlasSets()
		local t = 0
		_G.debugprofilestop = function() t = t + 10 return t end -- (every look at the clock: a slice has gone by)
		asked, ns.background = 0, 0
		local list = ns:GetEntries(ns.providers.loot)
		A.WarmAtlasSets(list)
		check(asked == 1, "the warm-up's first slice: one loot row, the rest left for later frames: " .. asked)
		FlushAll()
		check(asked == 7, "later frames read the rest (seven items in eight rows): " .. asked)
		check(#A.AtlasSets() == 3 and asked == 7, "asked then: all there, nothing read again: " .. asked)
		local hooked = false
		for _, fn in ipairs(ns.afterWarm.loot or {}) do if fn == A.WarmAtlasSets then hooked = true end end
		check(hooked, "it runs after the warm-up builds the loot list")
		_G.debugprofilestop = save.clock

		-- OneForAll's sets come first, and AtlasLoot isn't asked for them
		_G.OneForAll = { ARMORY_SETS = { { id = 1, n = "Its Own Set", i = { { 16866, "Helm of Might", "Head", 4, 0, { "Garr" } } } } } }
		asked = 0
		Fresh()
		local sets, source = A.Sets()
		check(source == "OneForAll" and sets and sets[1].name == "Its Own Set" and asked == 0 and ns.providers.itemset and ns.providers.itemset.follows == nil,
			"with OneForAll: its sets, AtlasLoot's not read: " .. tostring(source) .. " / " .. asked)
		A.WarmAtlasSets(ns:GetEntries(ns.providers.loot)); FlushAll()
		check(asked == 0, "nor read ahead")
		lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(not lines:find(L["Item sets:"], 1, true), ".integrations: on OneForAll's line then")
		_G.OneForAll = nil

		-- an AtlasLoot with no set data, or none at all: no @itemset
		_G.AtlasLoot.Data.ItemSet = nil
		Fresh()
		check(not ns.providers.itemset and A.Sets() == nil, "an AtlasLoot with no set data: no @itemset")
		local miss = I.MissingFor and I.MissingFor("@itemset")
		check(miss and miss.name == "OneForAll" and miss.also == "AtlasLoot", "reaching for @itemset then: OneForAll or AtlasLoot named")
		_G.AtlasLoot = nil
		Fresh()
		check(not ns.providers.itemset, "no AtlasLoot: none either")
	end)
	_G.OneForAll, _G.AtlasLoot = save.lib, save.atlas
	OA.Loaded = save.loaded
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	ns.Print, ns.background, UI.WalkTo = save.print, save.bg, save.walk
	_G.UnitClass, _G.UnitFactionGroup, _G.GetItemCount, _G.IsEquippedItem = save.class, save.side, save.count, save.eq
	C_Item.GetItemCount, C_Item.IsEquippedItem, C_Item.GetItemInfoInstant, C_Item.GetItemNameByID = save.citem, save.ceq, save.inst, save.name
	_G.UNKNOWN, _G.INVTYPE_HEAD, _G.INVTYPE_CHEST, _G.INVTYPE_WAIST = save.unknown, save.head, save.chest, save.waist
	_G.debugprofilestop = save.clock
	I.failed, OA.on = save.failed, save.on
	OA.Forget(); A.ForgetAtlasSets()
	if ns.Pipes and ns.Pipes.ClearSteps then ns.Pipes.ClearSteps() end
	if I.ForgetHint then I.ForgetHint() end
	UI.lastScan, UI.lastExtra = nil, nil
	check(ok, "item sets from AtlasLoot: " .. tostring(err))
end
