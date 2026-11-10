-- @enchant from AtlasLoot first, OneForAll as the fallback (1.3.10, the player: "Have Atlasloot's data be the primary;
-- and OFA be the fallback, as Atlasloot is more popular"). Loot.lua notes Enchanting's spells that make no item while
-- indexing (I._.NoteEnchant, kept with the index); OneForAll/Enchants.lua's EN.Data picks AtlasLoot's when it has any.
local T = ...
local ns, check = T.ns, T.check
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
		check(data and #data == 3 and data[1].source == "AtlasLoot", "with AtlasLoot's enchants: theirs, OneForAll's left aside")
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
		-- none from AtlasLoot (not installed, no crafting module): OneForAll's
		I._.ForgetEnchants()
		data = EN.Data()
		check(data and #data == 1 and data[1].name == "OFA Only" and data[1].source == nil, "without AtlasLoot's: OneForAll's")
	end)
	check(ok, "enchants from AtlasLoot: " .. tostring(err))
	I._.ForgetEnchants()
	_G.AtlasLoot = save.al
	C_Spell.GetSpellName, C_Spell.GetSpellDescription, EN.OFAData = save.name, save.desc, save.ofa
end
