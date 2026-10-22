-- Upgrade weights by talent tree (0.65.11, the player: "our own single role profile, split by talent tree (.weights fury
-- vs .weights arms), a single simplified stat weight scale good enough for 1-60"): Search/Filters/Upgrades.lua.
local T = ...
local ns, check = T.ns, T.check
local F = ns.Filters

io.write("[weightstrees: our own scale, one per talent tree]\n")
do
	-- every tree: its main stat 1 (so the trees and your own weights read alike, and a clear upgrade's least gain is one
	-- point of it); none weighs a stat Terminal doesn't read
	local KNOWN = {}
	for _, k in ipairs((function() local t = {} for w in F.STAT_LIST:gmatch("%S+") do t[#t + 1] = w end return t end)()) do KNOWN[k] = true end
	KNOWN.feralap = true
	local bad = {}
	for class, list in pairs(F.ROLES) do
		for _, r in ipairs(list) do
			local s = F.Scaled(r[2])
			for k, v in pairs(r[2]) do
				if not KNOWN[k] then bad[#bad + 1] = class .. "/" .. r[1] .. ": " .. k end
				if math.abs((s[k] or 0) - v) > 1e-9 then bad[#bad + 1] = class .. "/" .. r[1] .. ": main stat not 1 (" .. k .. ")" end
			end
			if not F.ROLE_SAY[r[1]] then bad[#bad + 1] = class .. "/" .. r[1] .. ": no name" end
		end
		check(F.WEIGHTS[class] ~= nil, class .. ": its levelling tree's weights when none is picked")
	end
	check(#bad == 0, "every tree's main stat is 1, its stats all read, its name said: " .. table.concat(bad, "; "))
	check(F.WEIGHTS.DRUID == F.ROLES.DRUID[2][2] and F.ROLES.DRUID[2][1] == "feral", "a druid none picked: feral")

	-- block value apart from block chance (a shield's 30 block value isn't 30% block); a school's spell damage its own
	local k = F.StatKinds({ ITEM_MOD_BLOCK_VALUE_SHORT = 30, ITEM_MOD_BLOCK_RATING_SHORT = 2, ITEM_MOD_FROST_DAMAGE_SHORT = 12,
		ITEM_MOD_SPELL_HEALING_DONE_SHORT = 20, ITEM_MOD_SPELL_POWER_SHORT = 9 })
	check(k.blockv == 30 and k.block == 2 and k.frost == 12 and k.heal == 20 and k.sp == 9,
		"block value, block chance, frost spell damage, healing and spell damage read apart")
	local function Tree(class, id) for _, r in ipairs(F.ROLES[class]) do if r[1] == id then return r[2] end end end
	check(F.Worth({ frost = 12 }, Tree("MAGE", "frost")) > 0 and F.Worth({ frost = 12 }, Tree("MAGE", "fire")) == 0,
		"frost spell damage: a frost mage's, not a fire mage's")
	check(F.Worth({ sp = 10 }, Tree("PRIEST", "holy")) == 0 and F.Worth({ heal = 10 }, Tree("PRIEST", "holy")) > 0,
		"a healer: healing counts, spell damage doesn't (on Forever it doesn't heal)")
	check(F.Worth({ blockv = 30 }, Tree("WARRIOR", "protection")) < F.Worth({ block = 2 }, Tree("WARRIOR", "protection")) * 10,
		"a shield's block value is points, not per cent")

	-- the words: a tree's name and short names, a role's word as the tree that plays it for your class
	check(F.TreeOf("prot", "WARRIOR") == "protection" and F.TreeOf("tank", "WARRIOR") == "protection"
		and F.TreeOf("tank", "DRUID") == "bear" and F.TreeOf("healer", "PRIEST") == "holy" and F.TreeOf("healer", "SHAMAN") == "restoration"
		and F.TreeOf("caster", "DRUID") == "balance" and F.TreeOf("melee", "HUNTER") == "survival" and F.TreeOf("tank", "MAGE") == nil,
		"tree words: prot, tank, healer, caster, melee, for each class")
	local save = { class = _G.UnitClass, roles = ns.db.upgradeRoles, custom = ns.db.upgradeCustom }
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	ns.db.upgradeRoles, ns.db.upgradeCustom = nil, nil
	local weights = ns:FindCommand("weights")
	local lines = table.concat(weights.run("fury", ns), "\n")
	check(F.MyRoles() and F.MyRoles()[1] == "fury" and lines:find(F.ROLE_SAY.fury, 1, true), ".weights fury: " .. lines)
	weights.run("arms", ns)
	check(F.MyRoles()[1] == "arms" and F.MyWeightSets()[1][1] == Tree("WARRIOR", "arms"), ".weights arms: judged by arms")
	weights.run("tank", ns)
	check(F.MyRoles()[1] == "protection", ".weights tank: a warrior's protection")
	-- a role kept before 0.65.11 ("dps", "tank"): the tree that plays it now
	ns.db.upgradeRoles[F._MyName()] = { "dps" }
	check(F.MyRoles()[1] == "arms", "a role kept from before, dps: arms")
	weights.run("all", ns)

	-- (0.65.11) your own weights scaled by their main stat, not their biggest number: Pawn weighs 1% hit at 10-25 Strength,
	-- and scaled by it +3 Strength was no upgrade at all
	local s = F.Scaled({ str = 2, hit = 25, dps = 14 })
	check(s.str == 1 and s.hit == 12.5 and s.dps == 7, "scaled by Strength: str 1, hit 12.5, dps 7")
	check(F.ClearGain({ str = 3 }, {}, s) ~= nil, "+3 Strength over nothing: an upgrade by them")
	s = F.Scaled({ sp = 2, spellhit = 20 })
	check(s.sp == 1 and s.spellhit == 10, "no main stat: by spell damage")

	-- (0.65.x review) items' stats kept by 0.65.10, read with the old stat kinds (a shield's block value as block chance,
	-- no spell schools), are let go: the store's version raised
	local S = ns.ItemStore
	local savedStore = ns.db.itemStore
	local okB, _, build = pcall(_G.GetBuildInfo)
	ns.db.itemStore = { build = okB and tostring(build) or "?", v = 3, facts = { new = { [91] = "INVTYPE_SHIELD;25;30;2;block=20,sta=2;" }, old = {}, n = 1 } }
	S.NewSession()
	check(S.Get("facts", 91) == nil, "item stats kept before the stat kinds changed: read again, not used")
	ns.db.itemStore = savedStore
	S.NewSession()

	-- (0.65.x review) a ranged weapon's DPS is its own: a hunter's bow counts, a melee stat stick's DPS little; a caster's
	-- wand counts, a staff's next to nothing
	local kr = F.StatKinds({ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 }, true)
	check(kr.rdps == 10 and kr.dps == nil and F.StatKinds({ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 }).dps == 10, "the ranged slot's DPS: rdps")
	check(F.ClearGain({ dps = 20 }, { dps = 10, agi = 5 }, Tree("HUNTER", "beastmastery")) == nil
		and F.ClearGain({ rdps = 20 }, { rdps = 10, agi = 5 }, Tree("HUNTER", "beastmastery")) ~= nil,
		"a hunter: +10 melee DPS for -5 Agility no upgrade; +10 bow DPS for -5 Agility one")
	check(F.ClearGain({ dps = 30 }, { dps = 12, int = 3 }, Tree("MAGE", "frost")) == nil, "a mage: a staff's DPS over a dagger's Intellect: no")
	local pw = F.ParsePawn('( Pawn: v1: "x": Agility=1, Dps=3 )')
	check(pw.dps == 3 and pw.rdps == 3, "Pawn's plain Dps: either slot's weapon")
	-- (0.65.x review) a tree word for a class whose tree is named otherwise: prot for a druid, holy for a shaman
	check(F.TreeOf("prot", "DRUID") == "bear" and F.TreeOf("holy", "SHAMAN") == "restoration" and F.TreeOf("resto", "PRIEST") == "holy"
		and F.TreeOf("holy", "MAGE") == nil and F.TreeOf("feral", "WARRIOR") == "feral", "prot, holy, resto for each class")
	-- (0.65.x review) Intellect 0.05 next to Healing 1: scaled by the healing, else a point of Intellect was an upgrade
	local sh = F.Scaled({ int = 0.05, heal = 1 })
	check(sh.heal == 1 and F.ClearGain({ int = 1 }, {}, sh) == nil, "a tiny main stat beside a big one: by the big one")
	-- (0.65.x review) .weights lists every stat (the main stat too) and says the class's levelling tree is the one used
	_G.UnitClass = function() return "Warlock", "WARLOCK", 9 end
	ns.db.upgradeRoles = nil
	local list = table.concat(weights.run("", ns), "\n")
	local _, aff = list:gsub(F.ROLE_SAY.affliction, "")
	check(list:find("int 1", 1, true) and aff == 1 and list:find(ns.L["(now: your class's levelling tree)"], 1, true)
		and not list:find("All-round", 1, true), ".weights: every stat, the levelling tree said once: " .. list)

	_G.UnitClass, ns.db.upgradeRoles, ns.db.upgradeCustom = save.class, save.roles, save.custom
	F.ClearCache()
end
