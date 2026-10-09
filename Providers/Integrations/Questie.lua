local ns = select(2, ...)
local I = ns.Integrations
local Safe = ns.Safe -- (Util.lua)
local RunSliced, WaypointLink = I.RunSliced, I._.WaypointLink

----------------------------------------------------------------------
-- Questie
----------------------------------------------------------------------

local npc = { list = nil, busy = false, on = false }
I.npc = npc
local qdb = { list = nil, busy = false }
I.qdb = qdb

-- The data comes from QuestieData.lua: the QuestieDB addon alone, or through Questie (same data).
local QD = ns.QuestieData
local QuestieReady = QD.Ready -- (the data can be read: QuestieDB loaded, and Questie ready if installed)
local function QDB() return QD.DB() end

--- One field of a Questie NPC (minLevel, maxLevel, zoneID, npcFlags...), for the search filters.
-- the small fields filters ask of every NPC row on every keystroke ("vendor", "nearest repair"): read once per NPC
local SMALL = { npcFlags = true, friendlyToFaction = true, minLevel = true, maxLevel = true, zoneID = true, subName = true }
local fieldCache, NONE, fieldFrom = {}, {}, nil
function I.NpcField(id, field)
	local DB = QDB()
	if not DB then return nil end
	if not SMALL[field] then return Safe(DB.QueryNPCSingle, id, field) or nil end
	if fieldFrom ~= DB then fieldCache, fieldFrom = {}, DB end -- (another database: QuestieDB reloaded, tests)
	local byId = fieldCache[field]
	if not byId then byId = {}; fieldCache[field] = byId end
	local v = byId[id]
	if v == nil then
		v = Safe(DB.QueryNPCSingle, id, field)
		if v == nil then v = NONE end
		byId[id] = v
	end
	if v == NONE then return nil end
	return v
end
I.ClearNpcFields = function() fieldCache = {} end

--- Questie's names for the NPC flag bits (they differ between game versions).
function I.NpcFlagDefs()
	local DB = QDB()
	return DB and DB.npcFlags or nil
end
I._.ClearNpcFields = I.ClearNpcFields

-- Each list's names are also kept as one text ("\n<name, lowercase>\t<id>" per line), for the
-- "Search Questie for this" rows: built along with the list the first time, and kept when the list
-- is freed, so plain searches never need the list itself (npc.names, qdb.names; FindNames).

-- an NPC's title ("Mining Trainer", "Banker"), lowercase too: searched as the row's text ("mining trainer in org")
local function NpcSub(DB, id)
	local sub = ns.Str(Safe(DB.QueryNPCSingle, id, "subName"))
	if not sub then return nil end
	return sub, ns.Lower(sub)
end

local function NpcListRow(DB, id, name, meta)
	local lname = ns.Lower(name)
	local sub, lsub = NpcSub(DB, id)
	return setmetatable({ _compact = true, key = id, name = name, _lname = lname, sub = sub, _ltext = lsub }, meta), lname, lsub
end

local function IndexNPCs(after)
	local function finish() if after then after() end end
	if npc.list or npc.busy or not QuestieReady() then return finish() end
	local DB = QDB()
	if not (DB and DB.QueryNPCSingle) then return finish() end
	npc.busy = true
	local ids = DB.NpcIds()
	local out, meta = {}, npc.meta
	local names = not npc.names and {} or nil
	RunSliced("questie: NPCs", #ids, function(i)
		local id = ids[i]
		local name = Safe(DB.QueryNPCSingle, id, "name")
		if ns.Str(name) then
			-- compact: the name, title and id; everything else is shared (npc.meta)
			local row, lname, lsub = NpcListRow(DB, id, name, meta)
			out[#out + 1] = row
			-- (the title on the name's line: "mining trainer" finds Makaru; the name shown comes from the id)
			if names then names[#names + 1] = "\n" .. lname .. (lsub and (" <" .. lsub .. ">") or "") .. "\t" .. id end
		end
	end, function()
		npc.list, npc.busy = out, false
		if names then npc.names, npc.nameQuery = table.concat(names) .. "\n", "QueryNPCSingle" end
		local p = ns.providers.npc
		if p then
			p._dirty = true
			-- built at login, never searched: freed like an unused list (~5 MB for WoW Forever's 11.7k NPCs); the names
			-- text stays for the hint rows, and the next @npc search builds it again
			if not p._usedAt then p._usedAt = GetTime() end
		end
		if ns.UI and ns.UI:IsShown() then ns.UI:Refresh() end
		finish()
	end)
end

--- How many names in the text have every typed word (up to 100), the first one's id, and the
--- first FEW ids (a list with only one or two matches shows them as results, not as a hint).
--- Scans for the longest word with a plain find (C speed) and checks the others on its line.
--- tick: called every so often (the search's own budget check, which may pause it a frame).
local function FindNames(blob, tokens, tick)
	if type(blob) ~= "string" or #tokens == 0 then return nil, 0 end
	local lead = tokens[1]
	for k = 2, #tokens do if #tokens[k] > #lead then lead = tokens[k] end end
	local pos, count, firstId, looked, ids = 1, 0, nil, 0, {}
	while count < 100 do
		local at = blob:find(lead, pos, true)
		if not at then break end
		local lineEnd = blob:find("\n", at, true) or (#blob + 1)
		local tab = blob:find("\t", at, true)
		if tab and tab < lineEnd then -- (a match in the name, not in the id after it)
			local from = math.max(1, at - 120)
			local back = blob:sub(from, at):match(".*\n()")
			local name = blob:sub(back and (from + back - 1) or at, tab - 1)
			local all = true
			for k = 1, #tokens do
				if tokens[k] ~= lead and not name:find(tokens[k], 1, true) then all = false break end
			end
			if all then
				count = count + 1
				local id = tonumber(blob:sub(tab + 1, lineEnd - 1))
				firstId = firstId or id
				if id and #ids < I.HINT_FEW then ids[#ids + 1] = id end
			end
		end
		pos = lineEnd
		looked = looked + 1
		if tick and looked % 64 == 0 then tick() end
	end
	return firstId, count, ids
end
I.FindNames = FindNames

--- The provider's hintFind: the first matching name (as the game writes it), the count, and the
--- first ids (UI shows those rows themselves when there are only a few: hintRow).
local function HintFind(t, tokens, tick)
	local id, count, ids = FindNames(t.names, tokens, tick)
	if not id then return nil, 0 end
	local DB = QDB()
	local name = DB and t.nameQuery and Safe(DB[t.nameQuery], id, "name")
	return type(name) == "string" and name or tostring(id), count, ids
end

--- A list's row by id: from the list when it's built (sorted by id: a binary search), else made
--- on the spot like the list makes it (the NPC list may have been freed; quests still indexing).
local function ListRow(list, id)
	if not list then return nil end
	local lo, hi = 1, #list
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		local k = rawget(list[mid], "key")
		if k == id then return list[mid] elseif k < id then lo = mid + 1 else hi = mid - 1 end
	end
end

local function NpcHintRow(_, id)
	local row = ListRow(npc.list, id)
	if row then return row end
	local DB = QDB()
	local name = DB and Safe(DB.QueryNPCSingle, id, "name")
	if not ns.Str(name) then return nil end
	return (NpcListRow(DB, id, name, npc.meta))
end

local function QuestHintRow(_, id)
	local row = ListRow(qdb.list, id)
	if row then return row end
	local DB = QDB()
	local name = DB and Safe(DB.QueryQuestSingle, id, "name")
	if not ns.Str(name) then return nil end
	return setmetatable({ _compact = true, key = id, name = name, _lname = ns.Lower(name),
		level = Safe(DB.QueryQuestSingle, id, "questLevel"), _ltext = "quest questie" }, qdb.meta)
end

-- rows by id for the chains (Pipes.lua: an item's sellers and droppers, a quest that rewards it)
function I.NpcRow(id) return NpcHintRow(nil, id) end
function I.QuestRow(id) return QuestHintRow(nil, id) end
--- One field of Questie's item (vendors, npcDrops, objectDrops, questRewards...), or nil.
function I.ItemField(id, field)
	local DB = QDB()
	return DB and DB.QueryItemSingle and Safe(DB.QueryItemSingle, id, field) or nil
end
--- A game object's name (a vein, a herb, a chest), or nil.
function I.ObjectName(id)
	local DB = QDB()
	local name = DB and DB.QueryObjectSingle and Safe(DB.QueryObjectSingle, id, "name")
	return ns.Str(name)
end

--- Where the NPC stands: uiMapID, position {x,y} (0-1), and whether that's a dungeon's
--- entrance rather than the NPC itself.
local function NpcLocation(id)
	local DB = QDB()
	local spawnsByZone = DB and Safe(DB.QueryNPCSingle, id, "spawns")
	if type(spawnsByZone) ~= "table" and DB and DB.GetNPC then
		local n = Safe(DB.GetNPC, DB, id)
		spawnsByZone = type(n) == "table" and n.spawns or nil
	end
	if type(spawnsByZone) ~= "table" then return end
	for zone, spawns in pairs(spawnsByZone) do
		local c = type(spawns) == "table" and spawns[1]
		if type(c) == "table" and c[1] and c[1] >= 0 then
			local dl = QD.DungeonLocation(zone)
			if type(dl) == "table" and dl[1] then
				local ui = QD.UiMapOfArea(dl[1][1])
				if ui then return ui, { x = dl[1][2] / 100, y = dl[1][3] / 100 }, true end
			else
				local ui = QD.UiMapOfArea(zone)
				if ui then return ui, { x = c[1] / 100, y = c[2] / 100 } end
			end
		end
	end
end

local function ShowNpc(e)
	local M = ns.Maps
	local mapID, pos, dungeon = NpcLocation(e.npcID)
	if not mapID then
		ns:Print("Questie has no known location for " .. (e.npcName or e.name) .. ".")
		return
	end
	if not InCombatLockdown() then
		-- Questie's own marker for it on the map
		local QM = QD.Module("QuestieMap")
		if QM and QM.ShowNPC then Safe(QM.ShowNPC, QM, e.npcID) end
	end
	M.ShowAfter({ name = (e.npcName or e.name) .. (dungeon and " (dungeon entrance)" or ""), mapID = mapID, pos = pos })
end

local function NpcPin(e)
	local mapID, pos = NpcLocation(e.npcID)
	local name = e.npcName or e.name
	if not mapID then
		ns:Print("Questie has no known location for " .. name .. ".")
	else
		local pin = ns.Maps.Place({ name = name, mapID = mapID, pos = pos })
		if pin then ns:Print(ns.Maps.PinLine(pin, name)) return end
		ns:Print("Can't set a waypoint there.")
	end
end

--- A map pin link where the NPC stands, for chat (>> party): the waypoint is set (a C API), then its link.
function I.NpcPinLink(e)
	local mapID, pos = NpcLocation(e.npcID)
	if not (mapID and pos and ns.Maps and ns.Maps.Place and ns.Maps.Place({ name = e.name, mapID = mapID, pos = pos })) then return nil end
	return WaypointLink()
end

-- Shift+Enter targets the NPC: "/targetexact <name>" on the secure macro button, pressed by the game
-- (targeting is protected: never from Terminal's code). The waypoint stays on Enter (the map opens on
-- the NPC and pins it, Maps.ShowAfter); without the press (in combat: Enter can't be bound then),
-- Shift+Enter says so and only pins it.
local function TargetMacro(e) return "/targetexact " .. (e.npcName or e.name) end
local NPC_TARGET = { macro = TargetMacro }
local NeverTargeted = ns.Never
local function TargetFallback(e)
	if InCombatLockdown() then ns:Print("In combat: can't target " .. tostring(e.name) .. " from here; pinning it instead.") end
	NpcPin(e)
end

local function OpenNpcDirect(e)
	-- no map keybinding to ride on: open the map ourselves (never in combat)
	if InCombatLockdown() then ns:Print("In combat: can't open " .. e.name .. " now.") return end
	if not NpcLocation(e.npcID) then -- nowhere to show it: leave the map alone
		ns:Print("Questie has no known location for " .. (e.npcName or e.name) .. ".")
		return
	end
	if ToggleWorldMap and not ns.Maps.MapOpen() then pcall(ToggleWorldMap) end
	C_Timer.After(0.1, function() ShowNpc(e) end)
end

-- (for QuestieQuests.lua: the quest rows' actions and the providers' setup)
local IP = I._
IP.HintFind, IP.NpcHintRow, IP.QuestHintRow, IP.IndexNPCs, IP.NpcLocation = HintFind, NpcHintRow, QuestHintRow, IndexNPCs, NpcLocation
IP.ShowNpc, IP.NpcPin, IP.OpenNpcDirect = ShowNpc, NpcPin, OpenNpcDirect
IP.NPC_TARGET, IP.NeverTargeted, IP.TargetFallback = NPC_TARGET, NeverTargeted, TargetFallback
