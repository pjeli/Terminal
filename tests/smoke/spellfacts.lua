-- (0.68.8, the player's pick) What a spell does: its facts as the game gives them (Providers/Spells.lua's SP.Facts) for
-- cast:, cost:, range:, cd:, its description in the words searched ("spells that stun"), and Simple mode's words for them.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local SP, F, E = ns.Spells, ns.Filters, ns.Easy

-- a pretend game: each spell's info, cost, cooldown, tooltip and description
local SPELLS = {
	[501] = { name = "Frost Nova", cast = 0, range = 0, cost = { { name = "MANA", cost = 55 } }, cd = 25000, desc = "Blasts enemies near the caster, freezing them in place." },
	[502] = { name = "Fireball", cast = 2500, range = 35, cost = { { name = "MANA", cost = 30 } }, cd = 0, desc = "Hurls a fiery ball." },
	[503] = { name = "Arcane Missiles", cast = 0, range = 30, cost = { { name = "MANA", cost = 85 } }, cd = 0, channeled = true, desc = "Launches Arcane Missiles." },
	[504] = { name = "Heroic Strike", cast = 0, range = 5, cost = { { name = "RAGE", cost = 15 } }, cd = 0, desc = "A strong attack." },
	[505] = { name = "Arcane Mind", cast = 0, range = 0, cost = {}, cd = 0, passive = true, desc = "Increases your maximum mana." },
	[506] = { name = "Shoot", cast = 0, range = 30, cost = {}, cd = 0, desc = "Shoot your wand." },
	[507] = { name = "Hammer of Justice", cast = 0, range = 10, cost = { { name = "MANA", cost = 50 } }, cd = 60000, desc = "Stuns the target for 6 sec." },
}
local was = { spell = _G.C_Spell, tip = _G.C_TooltipInfo, base = _G.GetSpellBaseCooldown, word = _G.SPELL_CAST_CHANNELED,
	book = _G.C_SpellBook }
local requested, cached = {}, {}
_G.SPELL_CAST_CHANNELED = "Channeled"
_G.C_Spell = setmetatable({
	GetSpellInfo = function(id) local s = SPELLS[id]; return s and { name = s.name, iconID = 1, castTime = s.cast, minRange = 0, maxRange = s.range } end,
	GetSpellName = function(id) return SPELLS[id] and SPELLS[id].name end,
	IsSpellPassive = function(id) return SPELLS[id] and SPELLS[id].passive == true or false end,
	GetSpellPowerCost = function(id) return SPELLS[id] and SPELLS[id].cost end,
	GetSpellDescription = function(id) return (SPELLS[id] and cached[id] ~= false) and SPELLS[id].desc or "" end,
	IsSpellDataCached = function(id) return cached[id] ~= false end,
	RequestLoadSpellData = function(id) requested[#requested + 1] = id end,
}, { __index = was.spell })
_G.C_TooltipInfo = setmetatable({ GetSpellByID = function(id)
	local s = SPELLS[id]
	return s and { lines = { { leftText = s.name }, { leftText = s.channeled and "Channeled" or "Instant" } } }
end }, { __index = was.tip or {} })
_G.GetSpellBaseCooldown = function(id) return SPELLS[id] and SPELLS[id].cd, 1500 end
SP.ForgetFacts()

local ok, err = pcall(function()
	io.write("[spell facts: cast:, cost:, range:, cd:]\n")
	local rows = {}
	for id in pairs(SPELLS) do rows[#rows + 1] = { name = SPELLS[id].name, spellID = id } end
	table.sort(rows, function(a, b) return a.spellID < b.spellID end)
	rows[#rows + 1] = { name = "Not a spell" } -- (an item's row: no spellID)
	rows[#rows + 1] = { name = "Unknown", spellID = 999 } -- (the game says nothing of it)
	local function Pass(filter)
		local f = F.Parse(filter)
		if not f then return "(no filter)" end
		local t = {}
		for _, e in ipairs(rows) do if f(e) then t[#t + 1] = e.name end end
		return table.concat(t, ", ")
	end
	local function Is(filter, want)
		local got = Pass(filter)
		check(got == want, filter .. ": " .. want .. " (got " .. got .. ")")
	end
	Is("cast:instant", "Frost Nova, Heroic Strike, Shoot, Hammer of Justice")
	Is("cast:channeled", "Arcane Missiles")
	Is("cast:2.5", "Fireball")
	Is("cast:>=2", "Fireball")
	Is("cost:0", "Shoot")
	Is("cost:none", "Shoot")
	Is("cost:mana", "Frost Nova, Fireball, Arcane Missiles, Hammer of Justice")
	Is("cost:rage", "Heroic Strike")
	Is("cost:<50", "Fireball, Heroic Strike, Shoot")
	Is("range:melee", "Heroic Strike")
	Is("range:self", "Frost Nova")
	Is("range:30", "Arcane Missiles, Shoot")
	Is("range:>=30", "Fireball, Arcane Missiles, Shoot")
	Is("cd:0", "Fireball, Arcane Missiles, Heroic Strike, Shoot")
	Is("cd:>20", "Frost Nova, Hammer of Justice")
	Is("cooldown:60", "Hammer of Justice")
	-- (not instant: the rest, rows that aren't spells too)
	Is("-cast:instant", "Fireball, Arcane Missiles, Arcane Mind, Not a spell, Unknown")
	check(F.Parse("cast:soon") == nil and F.Parse("range:far") == nil, "a value it can't read: no filter")

	io.write("[spell facts: said in words, Tab and .filters]\n")
	local said = {}
	for _, w in ipairs({ "cast:instant", "cast:channeled", "cast:<2", "cost:0", "cost:mana", "cost:<100", "range:melee", "range:self",
			"range:30", "cd:0", "cd:<10" }) do said[#said + 1] = E.SayFilter(w) end
	check(table.concat(said, " | ") == "instant | channeled | with a cast of under 2 sec | that cost nothing | that cost mana | "
		.. "costing under 100 | at melee range | on yourself | with a range of 30 yards | with no cooldown | with a cooldown of under 10 sec",
		"each said in words: " .. table.concat(said, " | "))
	local values = F.ValuesFor("cast", "@spell")
	check(values and values[1] == "instant" and F.ValuesFor("range", "@item") and #F.ValuesFor("range", "@item") == 0,
		"Tab offers them for @spell, not for items")
	local help = {}
	for _, h in ipairs(F.HELP) do help[h[1]] = h[2] end
	check(help["cast:instant"] and help["cost:0"] and help["range:30"] and help["cd:0"], ".filters lists all four")

	io.write("[spell facts: Simple mode's words]\n")
	local function Adv(text) return (ns.QueryToAdvanced(text) or ""):gsub("%s+$", "") end
	local cases = {
		{ "instant spells", "cast:instant" }, { "channeled spells", "cast:channeled" }, { "spells with no cooldown", "cd:0" },
		{ "spells that cost no mana", "cost:0" }, { "melee range abilities", "range:melee" }, { "30 yard spells", "range:30" },
		{ "30 yard range spells", "range:30" }, { "spells with a range over 20 yards", "range:>20" },
		{ "spells with a cooldown under 10 seconds", "cd:<10" }, { "10 sec cooldown spells", "cd:10" },
		{ "spells costing under 100 mana", "cost:<100" }, { "spells under 100 mana", "cost:<100" },
		{ "cast time under 2", "cast:<2" },
	}
	for _, c in ipairs(cases) do
		local adv = Adv(c[1])
		check(adv:find(c[2], 1, true) ~= nil, '"' .. c[1] .. '" reads ' .. c[2] .. ": " .. adv)
	end
	-- (and what was there before stays: an item named with the word, a potion, a count)
	local easyWas = ns.db.easyMode
	ns.db.easyMode = true
	local instant = E.Word("instant")
	ns.db.easyMode = easyWas
	check(instant and instant({ name = "Instant Poison" }) and instant({ name = "Shoot", spellID = 506 })
		and not instant({ name = "Fireball", spellID = 502 }), '"instant": instant spells, and still a name that says it (Instant Poison)')
	check(not Adv("mana potion"):find("cost:", 1, true), '"mana potion" is still a potion: ' .. Adv("mana potion"))
	check(not Adv("mana regen"):find("cost:", 1, true), '"mana regen" is still mp5: ' .. Adv("mana regen"))
	-- (0.68.9, review) a spell's fields only in a line about spells: elsewhere the words stay, and money is money
	for _, c in ipairs({ { "vendor within 300 yards", "range:" }, { "drinks over 4000 mana", "cost:" },
		{ "toys with a cooldown under 10", "cd:" }, { "items that cost under 100", "cost:" } }) do
		check(not Adv(c[1]):find(c[2], 1, true), '"' .. c[1] .. '" has no spell filter: ' .. Adv(c[1]))
	end
	check(Adv("cost under 1 gold"):find("value:<1g", 1, true) and Adv("items costing over 50 silver"):find("value:>50s", 1, true),
		"money after cost is a value again: " .. Adv("cost under 1 gold") .. " / " .. Adv("items costing over 50 silver"))

	io.write("[spell facts: what a spell does is searched]\n")
	-- a description: lowercase, one line; one not in yet is asked for once, within the budget
	check(SP.Desc(507) == "stuns the target for 6 sec.", "a description, lowercase: " .. tostring(SP.Desc(507)))
	cached[502] = false
	local budget = { n = 1 }
	check(SP.Desc(502, budget) == nil and SP.Desc(502, budget) == nil and #requested == 1 and budget.n == 0,
		"not in yet: asked for once, within the budget")
	cached[503] = false
	check(SP.Desc(503, budget) == nil and #requested == 1, "the budget spent: not asked this time")
	-- (its data arrives with no description: none, not asked again)
	SP.descFrame:GetScript("OnEvent")(SP.descFrame, "SPELL_DATA_LOAD_RESULT", 502)
	FlushAll()
	check(SP.Desc(502) == "", "in with nothing to say: no description")
	cached[502], cached[503] = nil, nil
	SP.ForgetFacts()
	-- your spellbook: "stun" finds Hammer of Justice by what it does
	_G.C_SpellBook = {
		GetNumSpellBookSkillLines = function() return 1 end,
		GetSpellBookSkillLineInfo = function() return { name = "Holy", itemIndexOffset = 0, numSpellBookItems = 2 } end,
		GetSpellBookItemInfo = function(i)
			if i == 1 then return { spellID = 507, itemType = 1 } end
			if i == 2 then return { spellID = 506, itemType = 1 } end
		end,
	}
	ns.providers.spells._dirty = true
	local found = {}
	for _, e in ipairs(ns:GetEntries(ns.providers.spells)) do found[e.name] = e end
	local hoj = found["Hammer of Justice"]
	local words = hoj and (rawget(hoj, "_ltext") or hoj.text)
	check(words and tostring(words):find("stuns the target", 1, true), "a spellbook row's words have what it does: " .. tostring(words))
	local r = UI:Search("@spell stuns")
	check(r[1] and r[1].name == "Hammer of Justice", "@spell stuns: the spell that stuns: " .. tostring(r[1] and r[1].name))
	r = UI:Search("@spell cast:instant cd:>30")
	check(r[1] and r[1].name == "Hammer of Justice", "@spell cast:instant cd:>30: " .. tostring(r[1] and r[1].name))
	-- every class's spells (What's Training's): a druid's found by what it does, on a warrior
	local CS = ns.ClassSpells
	local saveApi, saveClass = rawget(_G, "WT_API"), _G.UnitClass
	SPELLS[783] = { name = "Travel Form", cast = 0, range = 0, cost = { { name = "MANA", cost = 40 } }, cd = 0,
		desc = "Shapeshift into travel form, increasing movement speed by 40%." }
	_G.WT_API = T.WTCatalogApi and T.WTCatalogApi()
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	CS.Forget(); CS.ForgetRows()
	ns.providers.classspells._dirty = true
	r = UI:Search("@classspell movement speed")
	local first = r[1] and r[1].name
	_G.WT_API, _G.UnitClass = saveApi, saveClass
	CS.Forget(); CS.ForgetRows()
	ns.providers.classspells._dirty = true
	check(first == "Travel Form", "another class's spell found by what it does: " .. tostring(first))
end)

_G.C_Spell, _G.C_TooltipInfo, _G.GetSpellBaseCooldown, _G.SPELL_CAST_CHANNELED, _G.C_SpellBook =
	was.spell, was.tip, was.base, was.word, was.book
SP.ForgetFacts()
ns.providers.spells._dirty = true
check(ok, "spell facts ran: " .. tostring(err))
