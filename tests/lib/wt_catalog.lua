-- What's Training's catalog as its Api.lua makes it, for the tests: each class's trainer and quest spells, its weapon
-- masters. Loaded by tests/smoke/classspells.lua and spellfacts.lua, each its own copy (until 1.7.4 classspells.lua
-- left it on T for the files after it). Returns { CatalogApi = function: a WT_API, loads = class -> LoadClass calls, CATALOG, Entry }.
local function Entry(id, level, extra)
	local e = { id = id, kind = "trainer", level = level, cost = 100, petAbility = false }
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end
local CATALOG = {
	WARRIOR = { Entry(100, 4), Entry(9001, 6, { races = { 3 } }), Entry(9002, 10, { kind = "quest", cost = 0, quest = { { races = { 1 }, level = 10 } } }),
		Entry(1180, 1, { kind = "weaponMaster", trainers = { Horde = { { npc = 11868, name = "Sayoc", uiMapId = 1454, x = 81.7, y = 19.6 },
			{ npc = 11870, name = "Archibald", uiMapId = 1458, x = 57.3, y = 32.8 } }, Alliance = { { npc = 11867, name = "Woo Ping", uiMapId = 1453, x = 63.9, y = 69.1 } } } }),
		Entry(200, 20, { kind = "weaponMaster", trainers = { Horde = { { npc = 11870, name = "Archibald", uiMapId = 1458, x = 57.3, y = 32.8 } },
			Alliance = { { npc = 11867, name = "Woo Ping", uiMapId = 1453, x = 57.1, y = 57.7 } } } }) },
	DRUID = { Entry(3029, 28, { requiredTalentId = 16942 }), Entry(783, 30) },
	SHAMAN = { Entry(332, 6), Entry(547, 12) },
	ROGUE = { Entry(1180, 1, { kind = "weaponMaster", trainers = { Horde = { { npc = 11868, name = "Sayoc", uiMapId = 1454, x = 81.7, y = 19.6 } } } }),
		Entry(196, 1, { kind = "weaponMaster", trainers = { Horde = { { npc = 2704, name = "Hanashi", uiMapId = 1454, x = 81.5, y = 19.6 } } } }) },
}
local loads = {}
local function CatalogApi()
	return { version = 1, Status = {}, Event = { CLASS_READY = "ClassReady" }, IsReady = function() return true end,
		GetSpells = function() return {} end, GetSource = function() end, RegisterCallback = function() end,
		GetCatalog = function(cls) return CATALOG[cls] or {} end,
		LoadClass = function(cls) loads[cls] = (loads[cls] or 0) + 1 return true end }
end
return { CatalogApi = CatalogApi, loads = loads, CATALOG = CATALOG, Entry = Entry }
