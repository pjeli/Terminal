-- @enchant from AtlasLoot first, OneForAll as the fallback (1.3.10, the player: "Have Atlasloot's data be the primary;
-- and OFA be the fallback, as Atlasloot is more popular"). Loot.lua notes Enchanting's spells that make no item while
-- indexing (I._.NoteEnchant, kept with the index); OneForAll/Enchants.lua's EN.Data picks AtlasLoot's when it has any.
local T = ...
local ns, check, FlushAll = T.ns, T.check, T.FlushAll
local I, EN = ns.Integrations, ns.Enchants

io.write("[enchants: AtlasLoot first, OneForAll the fallback]\n")
do
	local save = { al = rawget(_G, "AtlasLoot"), name = C_Spell.GetSpellName, desc = C_Spell.GetSpellDescription,
		ofa = EN.OFAData }
	-- AtlasLoot's profession data: [1] the item made, [2] the profession (10: Enchanting), [3] the skill it needs
	local PROF = {
		[13646] = { nil, 10, 170 }, -- Enchant Bracer - Lesser Deflection
		[20034] = { nil, 10, 300 }, -- Enchant Weapon - Crusader
		[13661] = { nil, 10, 180 }, -- Enchant Bracer - Strength (its name below: an agility one, for the test)
		[25124] = { 20744, 10, 45 }, -- Minor Wizard Oil: makes an item, not an enchant
		[2657] = { nil, 7, 1 }, -- Smelt Copper: Mining's
	}
	_G.AtlasLoot = { Data = { Profession = { GetProfessionData = function(id) return PROF[id] end } } }
	local NAMES = { [13646] = "Enchant Bracer - Lesser Deflection", [20034] = "Enchant Weapon - Crusader",
		[13661] = "Enchant 2H Weapon - Agility" }
	local TEXT = { [13661] = "Permanently enchant a two-handed melee weapon to grant +5 Agility." }
	C_Spell.GetSpellName = function(id) return NAMES[id] end
	C_Spell.GetSpellDescription = function(id) return TEXT[id] or "" end
	local ok, err = pcall(function()
		I._.ForgetEnchants()
		for id in pairs(PROF) do I._.NoteEnchant(id, _G.AtlasLoot) end
		local ids = I.LootEnchants()
		check(#ids == 3 and ids[1] == 13646 and ids[3] == 20034,
			"Enchanting's spells that make no item are AtlasLoot's enchants (not an oil, not Mining's): " .. table.concat(ids, ","))
		check(I.EnchantsText() == "13646 13661 20034", "kept with the index as their ids: " .. I.EnchantsText())
		-- AtlasLoot's first, OneForAll's there too
		EN.OFAData = function() return { { name = "OFA Only", prof = "Enchanting", spell = 1, c = 4, t = 512, m = 0, stats = {}, order = 1 } } end
		local data = EN.Data()
		check(data and #data == 4 and data[1].source == "AtlasLoot" and data[4].name == "OFA Only" and data[4].order == 4,
			"with AtlasLoot's enchants: theirs first, then OneForAll's it doesn't list (1.3.11)")
		local by = {}
		for _, o in ipairs(data) do by[o.spell] = o end
		check(by[13646].req == 170 and by[13646].locs[1] == "INVTYPE_WRIST", "the skill it needs from AtlasLoot, the slot from its name")
		check(by[13661].locs[1] == "INVTYPE_2HWEAPON" and by[13661].text:find("Agility", 1, true),
			"a two-hander's, what it gives from the game's description")
		local rows = EN.Rows()
		local crusader
		for _, e in ipairs(rows) do if e.spell == 20034 then crusader = e end end
		check(crusader and crusader.source == "AtlasLoot" and crusader.profName and crusader.need == 300,
			"its row: Enchanting 300, from AtlasLoot")
		local tip = { lines = {} }
		function tip:SetText(s) self.lines[#self.lines + 1] = s end
		function tip:AddLine(s) self.lines[#self.lines + 1] = s end
		pcall(crusader.tooltip, crusader, tip)
		check(table.concat(tip.lines, "|"):find(ns.L["Enchants from AtlasLoot"], 1, true), "its tooltip says AtlasLoot")
		-- (1.3.11, review) one spell in both: AtlasLoot's row with OneForAll's slot masks (any language) and stats;
		-- OneForAll's armor kit (not Enchanting's) kept; a name the slot can't be read from: no slot, so slot: reads it
		EN.OFAData = function() return {
			{ name = "Enchant Bracer - Lesser Deflection", prof = "Enchanting", spell = 13646, c = 4, t = 512, m = 0,
				stats = { ITEM_MOD_STAMINA_SHORT = 3 }, absent = true, order = 1, text = "OFA words" },
			{ name = "Light Armor Kit", prof = "Leatherworking", spell = 2152, c = 4, t = 1952, m = 0, stats = {}, order = 2 } } end
		NAMES[13646] = "Armschiene verzaubern - Geringe Ablenkung"
		NAMES[20034] = "Waffe verzaubern - Kreuzfahrer"
		data = EN.Data()
		by = {}
		for _, o in ipairs(data) do by[o.spell] = o end
		check(#data == 4 and by[13646].c == 4 and by[13646].t == 512 and by[13646].stats.ITEM_MOD_STAMINA_SHORT == 3
			and by[13646].absent and by[13646].source == "AtlasLoot" and by[2152] and by[2152].source == nil,
			"one spell in both: AtlasLoot's with OneForAll's slot and stats; OneForAll's armor kit kept")
		rows = EN.Rows()
		local rby = {}
		for _, e in ipairs(rows) do rby[e.spell] = e end
		local F = ns.Filters
		F.ClearCache()
		local wrist = F._.KEYS.slot("wrist")
		check(rby[13646].enchantSlots and wrist(rby[13646]) == true, "a German name, OneForAll's masks: on the wrist")
		check(rby[20034].enchantSlots == nil and rby[20034].enchantText:find("kreuzfahrer", 1, true),
			"a German name and no OneForAll option: no slot claimed, its name in its text")
		check(rby[13661].enchantText:find("enchant 2h weapon", 1, true) and rby[13661].enchantText:find("agility", 1, true),
			"its name and description are what stat: and slot: read")
		NAMES[13646], NAMES[20034] = "Enchant Bracer - Lesser Deflection", "Enchant Weapon - Crusader"
		-- a description not in yet: asked once; the list made again when it comes
		local asks, changed = 0, 0
		local req, chg = C_Spell.RequestLoadSpellData, ns.Changed
		C_Spell.RequestLoadSpellData = function() asks = asks + 1 end
		ns.Changed = function(self, k) if k == "enchant" then changed = changed + 1 end return chg(self, k) end
		EN.ForgetTexts()
		EN.OFAData = function() return nil end
		EN.Data(); EN.Data()
		local f = EN.descFrame
		check(asks == 2 and f ~= nil, "two descriptions not in: each asked for once: " .. asks)
		if f then
			f:GetScript("OnEvent")(f, "SPELL_DATA_LOAD_RESULT", 13646, true)
			f:GetScript("OnEvent")(f, "SPELL_DATA_LOAD_RESULT", 999, true)
			FlushAll()
		end
		check(changed == 1, "its data in: @enchant made again once: " .. changed)
		C_Spell.RequestLoadSpellData, ns.Changed = req, chg
		EN.ForgetTexts()
		-- none from AtlasLoot (not installed, no crafting module): OneForAll's
		EN.OFAData = function() return { { name = "OFA Only", prof = "Enchanting", spell = 1, c = 4, t = 512, m = 0, stats = {}, order = 1 } } end
		I._.ForgetEnchants()
		data = EN.Data()
		check(data and #data == 1 and data[1].name == "OFA Only" and data[1].source == nil, "without AtlasLoot's: OneForAll's")
	end)
	check(ok, "enchants from AtlasLoot: " .. tostring(err))
	I._.ForgetEnchants()
	_G.AtlasLoot = save.al
	C_Spell.GetSpellName, C_Spell.GetSpellDescription, EN.OFAData = save.name, save.desc, save.ofa
end
