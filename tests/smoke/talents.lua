-- Other classes' talents (Talents.lua, 0.44.7): read through the game's view-loadout config, kept per build, listed
-- below your own class's; class: narrows to one class; Enter shows the Wowhead page.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check

io.write("[other classes' talents]\n")
do
	local TL, P = ns.Talents, ns.providers.talents
	local save = { ct = _G.C_ClassTalents, consts = _G.Constants, gci = _G.GetClassInfo, gnc = _G.GetNumClasses,
		spec = _G.GetSpecializationInfoForClassID, nspec = _G.GetNumSpecializationsForClassID, uc = _G.UnitClass,
		traits = {}, cache = ns.db.talentCache, show = ns.ShowText, easy = ns.db.easyMode }
	for k, v in pairs(C_Traits) do save.traits[k] = v end
	ns.db.easyMode = false
	local VIEW = -3
	_G.Constants = _G.Constants or {}
	_G.Constants.TraitConsts = _G.Constants.TraitConsts or {}
	_G.Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID = VIEW
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	local CLASSES = { { "Warrior", "WARRIOR" }, { "Mage", "MAGE" }, { "Priest", "PRIEST" } }
	_G.GetNumClasses = function() return #CLASSES end
	_G.GetClassInfo = function(i) local c = CLASSES[i]; if c then return c[1], c[2], i end end
	-- two mage specs share one tree (classic tabs in one tree): read once
	_G.GetNumSpecializationsForClassID = function(id) return id == 2 and 2 or 1 end
	_G.GetSpecializationInfoForClassID = function(id, i) return id * 10 + i end
	local TREE = { [11] = 77, [21] = 88, [22] = 88, [31] = 99 }
	local viewed, inits = nil, 0
	_G.C_ClassTalents = {
		GetTraitTreeForSpec = function(spec) return TREE[spec] end,
		InitializeViewLoadout = function(spec) viewed = TREE[spec]; inits = inits + 1 end,
	}
	local NODES = {
		[88] = { { 2001, "Ice Barrier", 2, 1 }, { 2002, "Improved Frostbolt", 2, 5 }, { 2003, "Cruel Winter", 1, 3 } },
		[99] = { { 3001, "Improved Renew", 1, 3 } },
	}
	local function Node(tree, id) for _, n in ipairs(NODES[tree] or {}) do if n[1] == id then return n end end end
	C_Traits.GetTreeNodes = function(tree)
		if NODES[tree] then local out = {} for i, n in ipairs(NODES[tree]) do out[i] = n[1] end return out end
		return save.traits.GetTreeNodes(tree)
	end
	C_Traits.GetGroupDisplayInfoByTreeID = function(tree)
		if tree == 88 then return { { groupID = 1, displayName = "Arcane", orderIndex = 1 }, { groupID = 2, displayName = "Frost", orderIndex = 2 } } end
		if tree == 99 then return { { groupID = 1, displayName = "Holy", orderIndex = 1 } } end
		return save.traits.GetGroupDisplayInfoByTreeID(tree)
	end
	C_Traits.GetNodeInfo = function(config, id)
		if config == VIEW then
			local n = Node(viewed, id)
			return n and { isVisible = true, ranksPurchased = 0, maxRanks = n[4], groupIDs = { n[3] }, entryIDs = { id } } or nil
		end
		return save.traits.GetNodeInfo(config, id)
	end
	C_Traits.GetEntryInfo = function(config, e)
		if config == VIEW then return { definitionID = -e } end
		return save.traits.GetEntryInfo(config, e)
	end
	C_Traits.GetDefinitionInfo = function(d)
		if d < 0 then local n = Node(viewed, -d) return n and { spellID = 50000 + n[1], overrideName = n[2] } end
		return save.traits.GetDefinitionInfo(d)
	end

	local rcc = _G.RAID_CLASS_COLORS
	_G.RAID_CLASS_COLORS = { MAGE = { colorStr = "ff3fc7eb" } }
	ns.db.talentCache, TL.triedOthers = nil, nil
	P._dirty = true
	local by = {}
	for _, e in ipairs(ns:GetEntries(P)) do by[e.name] = e end
	local ib = by["Ice Barrier"]
	check(ib and ib.classFile == "MAGE" and ib.other and ib.detail:find("Mage", 1, true) and ib.detail:find("Frost", 1, true)
		and by["Improved Renew"] and by["Deflection"] and not by["Deflection"].other, "other classes' talents listed with class and tree: "
		.. tostring(ib and ib.detail))
	check(ib and ib.detail:find("^|cff3fc7ebMage|r") and not ib.detail:find("|cff|c", 1, true),
		"the class name in its colour, no stray colour code: " .. tostring(ib and ib.detail))
	_G.RAID_CLASS_COLORS = rcc
	check(inits == 3, "each class's tree read once (two mage specs share one): " .. inits)
	check(ns.db.talentCache and ns.db.talentCache.classes.MAGE and #ns.db.talentCache.classes.MAGE == 3, "kept in the saved variables")
	-- your own class first among equal matches
	local res = UI:Search("@talent cruel")
	check(res[1] and res[1].name == "Cruelty" and res[2] and res[2].name == "Cruel Winter", "your class first: "
		.. tostring(res[1] and res[1].name) .. ", " .. tostring(res[2] and res[2].name))
	res = UI:Search("@talent ice barrier")
	check(res[1] and res[1].name == "Ice Barrier", "another class's talent by name")
	-- class: narrows
	res = UI:Search("@talent class:mage")
	local onlyMage = #res == 3
	for _, e in ipairs(res) do onlyMage = onlyMage and e.classFile == "MAGE" end
	check(onlyMage, "class:mage: the mage's talents only: " .. #res)
	res = UI:Search("@talent class:mine")
	local mine = #res > 0
	for _, e in ipairs(res) do mine = mine and e.classFile == "WARRIOR" end
	check(mine, "class:mine: yours")
	check(#UI:Search("@talent class:pri") == 1, "class: by its start")
	check(#UI:Search("@talent mage frost") >= 2, "the class name is a word too (\"mage frost\")")
	-- Enter: the Wowhead page (its tree isn't yours to open)
	local shown
	ns.ShowText = function(_, title, text) shown = text end
	ib.activate(ib)
	check(shown == "https://www.wowhead.com/forever/spell=52001", "Enter shows the Wowhead page: " .. tostring(shown))
	-- a rebuild comes from the saved copy: no view loadout again
	P._dirty = true
	ns:GetEntries(P)
	check(inits == 3, "rebuilt from the saved copy")
	-- a client without the view loadout: none, nothing kept, not asked again this session
	ns.db.talentCache, TL.triedOthers = nil, nil
	_G.C_ClassTalents = nil
	P._dirty = true
	by = {}
	for _, e in ipairs(ns:GetEntries(P)) do by[e.name] = e end
	check(by["Deflection"] and not by["Ice Barrier"] and ns.db.talentCache == nil and TL.triedOthers, "no view loadout: your own only")

	for k, v in pairs(save.traits) do C_Traits[k] = v end
	_G.C_ClassTalents, _G.Constants, _G.GetClassInfo, _G.GetNumClasses = save.ct, save.consts, save.gci, save.gnc
	_G.GetSpecializationInfoForClassID, _G.GetNumSpecializationsForClassID, _G.UnitClass = save.spec, save.nspec, save.uc
	ns.db.talentCache, ns.ShowText, ns.db.easyMode, TL.triedOthers = save.cache, save.show, save.easy, nil
	P._dirty = true
end
