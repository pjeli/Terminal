-- Your corpse and spirit healers (Corpse.lua, 0.50.5, the player's ask): "where is my body" lists your corpse (how far,
-- the arrow, Enter: the map on it) and the nearest spirit healers; "nearest spirit healer" and @npc is:spirithealer.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local C, I, L = ns.Corpse, ns.Integrations, ns.L

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[corpse: your body and the nearest spirit healers]\n")
do
	local save = { dead = _G.UnitIsDeadOrGhost, DI = _G.C_DeathInfo, map = _G.C_Map,
		here = I.Here, spot = I.SpotXY, dist = I.NpcDistance, zone = I.ZoneName, providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode,
		defs = I.NpcFlagDefs, field = I.NpcField }
	check(ns.providers.corpse and ns:ResolveProvider("corpse") == ns.providers.corpse and ns:ResolveProvider("body") == ns.providers.corpse,
		"@corpse, @body")
	-- the questions
	for _, s in ipairs({ "where is my body", "where's my corpse", "my corpse", "corpse", "find my body", "corpse run", "where did i die" }) do
		check(C.Question(s) ~= nil, s .. ": the corpse question")
	end
	for _, s in ipairs({ "body armor", "corpse lily", "my body pillow", "@corpse", "spirit healer" }) do
		check(C.Question(s) == nil, s .. ": not it")
	end

	-- alive: nothing to find
	_G.UnitIsDeadOrGhost = function() return false end
	ns.providers.corpse._dirty = true
	check(#UI:Search("@corpse") == 0, "alive: no corpse row")
	local rows = C.Answer({})
	check(rows[1].noActivate and rows[1].name == L["You're alive: no corpse to find."], "alive: said so")

	-- dead: the game says where, on the continent's map (the zone's doesn't)
	_G.UnitIsDeadOrGhost = function() return true end
	_G.C_DeathInfo = { GetCorpseMapPosition = function(map) if map == 1415 then return { x = 0.4, y = 0.6 } end end }
	_G.C_Map = setmetatable({}, { __index = save.map })
	C_Map.GetBestMapForUnit = function() return 1429 end
	C_Map.GetMapInfo = function(map) if map == 1429 then return { parentMapID = 1415 } end return { parentMapID = 0 } end
	I.SpotXY = function(ui, c) if ui == 1415 and c[1] == 40 and c[2] == 60 then return 1, 30, 40 end end
	I.ZoneName = function(ui) return ui == 1415 and "Eastern Kingdoms" or nil end
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	-- Questie's NPCs: a spirit healer by its flag, one by its id, an innkeeper
	local DIST = { [6491] = 300, [7777] = 90, [6740] = 20, [8888] = 500 }
	I.NpcDistance = function(id) return DIST[id] end
	I.NpcFlagDefs = function() return { INNKEEPER = 128, SPIRIT_HEALER = 16384 } end
	local FIELDS = { [7777] = { npcFlags = 16384, name = "Graveyard Keeper", friendlyToFaction = "AH" },
		[6491] = { npcFlags = 0, name = "Spirit Healer", friendlyToFaction = "AH" }, [6740] = { npcFlags = 128, name = "Innkeeper Allison" },
		[8888] = { npcFlags = 0, friendlyToFaction = "AH" } } -- (no name in the database: the row's own)
	I.NpcField = function(id, f) return FIELDS[id] and FIELDS[id][f] end
	-- (just the two kinds: yours, and Questie's NPCs)
	local corpse = ns.providers.corpse
	ns.providers, ns.providerOrder = { corpse = corpse }, { "corpse" }
	ns:RegisterProvider("npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = function()
		return { { key = 6491, npcID = 6491, name = "Spirit Healer" }, { key = 7777, npcID = 7777, name = "Graveyard Keeper" },
			{ key = 6740, npcID = 6740, name = "Innkeeper Allison" },
			-- (one known by its row's name alone: Questie's database isn't asked each NPC's name; 0.50.7, review)
			{ key = 8888, npcID = 8888, name = "Spirit Healer" } }
	end })
	ns:AliasesChanged()
	UI.lastScan = nil
	ns.Filters.ClearCache()
	ns.providers.corpse._dirty = true
	local res = UI:Search("@corpse")
	local row = res[1]
	check(#res == 1 and row.name == L["Your corpse"] and row.ui == 1415 and row.px == 40 and row.py == 60 and row.wcont == 1,
		"dead: your corpse, where the game says: " .. Names(res))
	check(table.concat({ ns.Easy.Verbs(row) }, "/") == "show on map/set waypoint" and row.secure == ns.Maps.SECURE, "Enter: the map on it; Shift+Enter: a pin")
	ns.db.easyMode = true
	UI:Hide(); FlushAll()
	UI:Open("where is my body"); FlushAll()
	rows = UI.Results()
	check(Names(rows) == L["Your corpse"] .. " | Graveyard Keeper | Spirit Healer | Spirit Healer", "where is my body: it, then the nearest spirit healers: " .. Names(rows))
	check(rows[1].detail:find("^50 yd") and rows[2].detail:find("^90 yd"), "how far each is: " .. tostring(rows[1].detail))
	check(tostring(UI.status:GetText()):find(L["Your corpse"], 1, true), "the footer says so")
	check(ns.Easy.ToAdvanced("where is my body") == "@corpse ", "Alt+`: @corpse")
	UI:Hide(); FlushAll()
	-- "nearest spirit healer": the healers alone, closest first
	UI:Open("nearest spirit healer"); FlushAll()
	rows = UI.Results()
	check(Names(rows) == "Graveyard Keeper | Spirit Healer | Spirit Healer", "nearest spirit healer: " .. Names(rows))
	UI:Hide(); FlushAll()
	UI:Open("nearest graveyard"); FlushAll()
	rows = UI.Results()
	check(Names(rows) == "Graveyard Keeper | Spirit Healer | Spirit Healer", "nearest graveyard: the same: " .. Names(rows))
	UI:Hide(); FlushAll()
	ns.db.easyMode = false
	-- (0.50.7, review) near: asks for the yards alone (no spot table made per NPC)
	local yards, ry = 0, I.RowYards
	I.RowYards = function(...) yards = yards + 1 return ry(...) end
	ns.Filters.ClearCache()
	res = UI:Search("@npc near:250")
	I.RowYards = ry
	check(yards > 0 and #res == 2, "near:250: by RowYards: " .. yards .. " / " .. Names(res))
	ns.Filters.ClearCache()
	res = UI:Search("@npc is:spirithealer")
	check(#res == 3 and not Names(res):find("Innkeeper", 1, true), "@npc is:spirithealer: " .. Names(res))
	-- in an instance the game doesn't say: said so, the healers still listed
	_G.C_DeathInfo = { GetCorpseMapPosition = function() return nil end }
	rows = C.Answer({})
	check(rows[1].noActivate and rows[1].name:find("doesn't say", 1, true) and #rows == 4, "no position: said so: " .. Names(rows))

	_G.UnitIsDeadOrGhost, _G.C_DeathInfo, _G.C_Map = save.dead, save.DI, save.map
	I.Here, I.SpotXY, I.NpcDistance, I.ZoneName = save.here, save.spot, save.dist, save.zone
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	UI.lastScan = nil
	I.NpcFlagDefs, I.NpcField, ns.db.easyMode = save.defs, save.field, save.easy
	ns.Filters.ClearCache()
	ns.providers.corpse._dirty = true
end

-- (0.50.7, review) in:bags: your own bags' rows (they say "x5  Backpack", "Bag 2"), not only your alts'
io.write("[in:bags: your own bags]\n")
do
	local KEYS = ns.Filters._.KEYS
	local mine = { name = "Linen Cloth", kind = "items", firstBag = 0, detail = "x5  Backpack" }
	local worn = { name = "Sword", kind = "items", slotId = 16, detail = "Main Hand" }
	check(KEYS["in"]("bags")(mine) and KEYS["in"]("bag")(mine) and not KEYS["in"]("bags")(worn) and KEYS["in"]("equipped")(worn),
		"in:bags: your bags' rows, not what you wear")
end
