local ns = select(2, ...)

-- Questie's quest, NPC and item data, read from the QuestieDB addon alone or through Questie.
--
-- Newer Questie keeps its database in a separate addon, QuestieDB, which publishes it as
-- `LibQuestieDB` (entities `Quest`, `Npc`, `Item` with `Get(id, field)` and `GetAllIds()`, plus whole
-- support tables such as the zone maps). Questie's own `QueryQuestSingle` *is* `LibQuestieDB.Quest.Get`,
-- so reading LibQuestieDB gives the same answers, and with QuestieDB alone (no Questie: a Blizzard-like
-- UI) @questie, @npc and the Questie filters still work. When Questie is installed, its corrections and
-- translations go into that same shared data during its start-up, so reads wait until it is ready.
-- An older Questie with the data built in (no LibQuestieDB) is read through its QuestieLoader modules.
--
-- `QD.DB()` gives a Questie-shaped table: QueryQuestSingle/QueryNPCSingle/QueryItemSingle(id, field),
-- QuestIds()/NpcIds()/ItemIds() (ascending id lists), npcFlags (the flag bits of this game version).
-- `QD.UiMapOfArea(areaId)` and `QD.DungeonLocation(areaId)` stand in for Questie's ZoneDB.

local QD = {}
ns.QuestieData = QD

local Safe = ns.Safe

--- The QuestieDB addon's library, when it is loaded and has what Terminal reads.
function QD.Lib()
	local L = rawget(_G, "LibQuestieDB")
	if type(L) ~= "table" then return nil end
	local q, n = L.Quest, L.Npc
	if type(q) == "table" and type(q.Get) == "function" and type(n) == "table" and type(n.Get) == "function" then return L end
end

function QD.HasQuestie() return type(rawget(_G, "Questie")) == "table" end

function QD.QuestieReady()
	local Q = rawget(_G, "Questie")
	return type(Q) == "table" and Q.API and Q.API.isReady and rawget(_G, "QuestieLoader") and true or false
end

--- One of Questie's own modules (QuestieLink, QuestieMap, ZoneDB...), only once Questie is ready.
function QD.Module(name)
	if not QD.QuestieReady() then return nil end
	local L = rawget(_G, "QuestieLoader")
	local m = L and L.ImportModule and Safe(L.ImportModule, L, name)
	return type(m) == "table" and m or nil
end

--- A Questie module whether or not Questie says it's ready (QuestieLink only reads; a test, an old Questie).
function QD.AnyModule(name)
	local L = rawget(_G, "QuestieLoader")
	local m = type(L) == "table" and L.ImportModule and Safe(L.ImportModule, L, name)
	return type(m) == "table" and m or nil
end

--- Is the data there to read now? QuestieDB alone: from login. With Questie: once it's ready.
function QD.Ready()
	if QD.HasQuestie() then
		if not QD.QuestieReady() then return false end
		return QD.Lib() ~= nil or QD.Module("QuestieDB") ~= nil
	end
	return QD.Lib() ~= nil
end

--- Where the data comes from: "Questie", "QuestieDB", or nil.
function QD.Source()
	if QD.HasQuestie() then return "Questie" end
	if QD.Lib() then return "QuestieDB" end
end

local function SortedKeys(t)
	local ids = {}
	for id in pairs(type(t) == "table" and t or {}) do if type(id) == "number" then ids[#ids + 1] = id end end
	table.sort(ids)
	return ids
end

local function LibIds(entity)
	local ids = entity and entity.GetAllIds and Safe(entity.GetAllIds)
	if type(ids) ~= "table" then return {} end
	if #ids > 0 or next(ids) == nil then return ids end
	return SortedKeys(ids) -- (a hashmap after all)
end

-- the flag bits for NPC roles: shared, or this flavour's rules (WoW Forever plays by Classic's)
local function LibNpcFlags(L)
	local E = L.Enum
	if type(E) ~= "table" then return nil end
	if type(E.npcFlags) == "table" then return E.npcFlags end
	local flavor = L.flavor
	local by = E.byExpansion
	if type(by) ~= "table" then return nil end
	local set = by[(type(flavor) == "table" and (flavor.rules or flavor.expansion)) or "Classic"] or by.Classic
	return type(set) == "table" and set.npcFlags or nil
end

local libDB, libFrom -- made once per library table
local QUESTIE_DB = {} -- (an older Questie: its module, wrapped the same way)

--- The data, Questie-shaped, or nil while it can't be read (see Ready).
function QD.DB()
	if not QD.Ready() then return nil end
	local L = QD.Lib()
	if L then
		if libFrom ~= L then
			libFrom = L
			local item = L.Item
			libDB = {
				QueryQuestSingle = L.Quest.Get,
				QueryNPCSingle = L.Npc.Get,
				QueryItemSingle = item and item.Get or nil,
				QuestIds = function() return LibIds(L.Quest) end,
				NpcIds = function() return LibIds(L.Npc) end,
				ItemIds = function() return LibIds(item) end,
				npcFlags = LibNpcFlags(L),
				source = "QuestieDB",
			}
		end
		-- Questie's own flag table (it knows its client) when Questie is there
		local M = QD.Module("QuestieDB")
		if M and type(M.npcFlags) == "table" then libDB.npcFlags = M.npcFlags end
		return libDB
	end
	local M = QD.Module("QuestieDB")
	if not (M and (M.QueryQuestSingle or M.QueryNPCSingle or M.QueryItemSingle)) then return nil end
	local w = QUESTIE_DB
	if w.module ~= M then
		w.module = M
		w.QueryQuestSingle, w.QueryNPCSingle, w.QueryItemSingle = M.QueryQuestSingle, M.QueryNPCSingle, M.QueryItemSingle
		-- (an older Questie gives an NPC's spawns through GetNPC)
		w.GetNPC = M.GetNPC and function(_, id) return M:GetNPC(id) end or nil
		w.QuestIds = function() return SortedKeys(M.QuestPointers) end
		w.NpcIds = function() return SortedKeys(M.NPCPointers) end
		w.ItemIds = function()
			if type(M.ItemPointers) == "table" then return SortedKeys(M.ItemPointers) end
			local L = rawget(_G, "LibQuestieDB") -- (a Questie between the two: ids from the library)
			return type(L) == "table" and LibIds(L.Item) or {}
		end
		w.source = "Questie"
	end
	w.npcFlags = M.npcFlags
	return w
end

----------------------------------------------------------------------
-- Zones: area id -> the game's map id, dungeon entrances (Questie's ZoneDB, else QuestieDB's tables)
----------------------------------------------------------------------

local zones -- { map = areaId -> uiMapId, dungeons, alt = alternative area -> dungeon area }

-- QuestieDB keeps the maps as Lua text ("return { ... }"), decoded by whoever reads them
local function Decode(v)
	if type(v) == "table" then return v end
	if type(v) ~= "string" then return nil end
	local load = rawget(_G, "loadstring") or rawget(_G, "load")
	local fn = load and load(v)
	local ok, t = false, nil
	if fn then ok, t = pcall(fn) end
	return ok and type(t) == "table" and t or nil
end

local function LibZones()
	if zones ~= nil then return zones or nil end
	local L = QD.Lib()
	if not L then return nil end
	zones = false
	local S = L.Support
	local Z = S and S.Get and Safe(S.Get, "ZoneDB")
	local P = type(Z) == "table" and Z.private
	if type(P) ~= "table" then return nil end
	local map = Decode(P.areaIdToUiMapId)
	if not map then return nil end
	local copy = {}
	for k, v in pairs(map) do copy[k] = v end
	for k, v in pairs(Decode(P.areaIdToUiMapIdOverride) or {}) do copy[k] = v end
	local dungeons = type(P.dungeons) == "table" and P.dungeons or {}
	local alt = {}
	for areaId, d in pairs(dungeons) do
		for _, a in ipairs(type(d) == "table" and type(d[2]) == "table" and d[2] or {}) do alt[a] = areaId end
	end
	zones = { map = copy, dungeons = dungeons, alt = alt }
	return zones
end

function QD.UiMapOfArea(areaId)
	local Z = QD.Module("ZoneDB")
	if Z and Z.GetUiMapIdByAreaId then return Safe(Z.GetUiMapIdByAreaId, Z, areaId) end
	local z = LibZones()
	local ui = z and z.map[areaId]
	return ui and ui ~= 0 and ui or nil
end

--- A dungeon's entrances ({ { areaId, x, y }, ... }, percentages), or nil when the area isn't one.
function QD.DungeonLocation(areaId)
	local Z = QD.Module("ZoneDB")
	if Z and Z.GetDungeonLocation then return Safe(Z.GetDungeonLocation, Z, areaId) end
	local z = LibZones()
	if not z then return nil end
	local d = z.dungeons[areaId] or z.dungeons[z.alt[areaId] or false]
	return type(d) == "table" and d[4] or nil
end

--- Run fn once the data can be read: now, at Questie's ready, or (QuestieDB alone) now as well.
function QD.OnReady(fn)
	if QD.Ready() then return fn() end
	local Q = rawget(_G, "Questie")
	if type(Q) == "table" and Q.API and Q.API.RegisterOnReady then Safe(Q.API.RegisterOnReady, fn) end
end

QD.ResetForTests = function() libDB, libFrom, zones = nil, nil, nil; QUESTIE_DB.module = nil end
