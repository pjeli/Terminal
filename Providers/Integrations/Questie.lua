local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local Safe = ns.Safe -- (Util.lua)
local RunSliced, WaypointLink, NearestSpawn = I.RunSliced, I._.WaypointLink, I._.NearestSpawn

----------------------------------------------------------------------
-- Questie
----------------------------------------------------------------------

local npc = { list = nil, busy = false, on = false }
I.npc = npc
local qdb = { list = nil, busy = false }
I.qdb = qdb

-- The data comes from QuestieData.lua: the QuestieDB addon alone, or through Questie (same data).
local QD = ns.QuestieData
local function QuestieReady() return QD.Ready() end -- (the data can be read: QuestieDB loaded, and Questie ready if installed)
local function QDB() return QD.DB() end

--- One field of a Questie NPC (minLevel, maxLevel, zoneID, npcFlags...), for the search filters.
-- the small fields filters ask of every NPC row on every keystroke ("vendor", "nearest repair"): read once per NPC
local SMALL = { npcFlags = true, friendlyToFaction = true, minLevel = true, maxLevel = true, zoneID = true, subName = true }
local fieldCache, NONE, fieldFrom = {}, {}, nil
function I.NpcField(id, field)
	-- (a small field read before: from the cache, without asking for the database first; review, 0.53.6)
	if fieldFrom and SMALL[field] then
		local byId = fieldCache[field]
		local v = byId and byId[id]
		if v ~= nil then
			if v == NONE then return nil end
			return v
		end
	end
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
	if not DB then return finish() end
	-- (its database without the calls Terminal reads: said, not an empty list with no word why; 0.57.1)
	if type(DB.QueryNPCSingle) ~= "function" or type(DB.NpcIds) ~= "function" then
		I.Failed("Questie", L["@npc is unavailable."], "QueryNPCSingle " .. type(DB.QueryNPCSingle) .. ", NpcIds " .. type(DB.NpcIds))
		return finish()
	end
	local okIds, ids = pcall(DB.NpcIds)
	if not okIds or type(ids) ~= "table" then
		I.Failed("Questie", L["@npc is unavailable."], "NpcIds: " .. tostring(ids))
		return finish()
	end
	npc.busy = true
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
		-- (ids but not one name: the database's shape changed; said, not an empty @npc with no word why. 0.63.7, review)
		if #ids > 0 and #out == 0 then I.Failed("Questie", L["@npc is unavailable."], "QueryNPCSingle(id, \"name\"): no names") end
		npc.list, npc.busy, npc.count = out, false, #out -- (count: said by .integrations once the list is freed)
		if names then npc.names, npc.nameQuery = table.concat(names) .. "\n", "QueryNPCSingle" end
		local p = ns.providers.npc
		if p then
			p._dirty = true
			-- built at login, never searched: freed like an unused list (~5 MB for WoW Forever's 11.7k NPCs); the names
			-- text stays for the hint rows, and the next @npc search builds it again
			if not p._usedAt then p._usedAt = GetTime() end
		end
		if ns.UI and ns.UI:IsShown() then ns.UI:QuietRedo() end -- (held for F5 when a list is shown)
		finish()
	end)
end

--- How many names in the text have every typed word (up to 100), the first one's id, the
--- first FEW ids (a list with only one or two matches shows them as results, not as a hint), and
--- the first one's line (its name, and an NPC's title in <>).
--- Scans for the longest word with a plain find (C speed) and checks the others on its line.
--- tick: called every so often (the search's own budget check, which may pause it a frame).
local function FindNames(blob, tokens, tick)
	if type(blob) ~= "string" or #tokens == 0 then return nil, 0 end
	local lead = tokens[1]
	for k = 2, #tokens do if #tokens[k] > #lead then lead = tokens[k] end end
	local pos, count, firstId, looked, ids, firstLine = 1, 0, nil, 0, {}, nil
	while count < 100 do
		local at = blob:find(lead, pos, true)
		if not at then break end
		local lineEnd = blob:find("\n", at, true) or (#blob + 1)
		local tab = blob:find("\t", at, true)
		if tab and tab < lineEnd then -- (a match in the name, not in the id after it)
			local all, name = true, nil
			-- the line cut out only to check the other words (review, 0.53.6), or for the first match's line
			if #tokens > 1 or not firstLine then
				local from = math.max(1, at - 120)
				local back = blob:sub(from, at):match(".*\n()")
				name = blob:sub(back and (from + back - 1) or at, tab - 1)
				for k = 1, #tokens do
					if tokens[k] ~= lead and not name:find(tokens[k], 1, true) then all = false break end
				end
			end
			if all then
				count = count + 1
				local id = tonumber(blob:sub(tab + 1, lineEnd - 1))
				firstId = firstId or id
				firstLine = firstLine or name
				if id and #ids < I.HINT_FEW then ids[#ids + 1] = id end
			end
		end
		pos = lineEnd
		looked = looked + 1
		if tick and looked % 64 == 0 then tick() end
	end
	return firstId, count, ids, firstLine
end
I.FindNames = FindNames

--- Are these words, in this order, whole words of an NPC's or a quest's name (not a title)? "dalaran mage", "stockade
--- guard", "orgrimmar reveler" are NPCs, not mages in Dalaran (0.68.19): Simple mode then reads no place in them.
function I.NamedAs(tokens)
	if #tokens < 2 then return false end
	local phrase = table.concat(tokens, " ")
	for _, t in ipairs({ npc, qdb }) do
		local blob, pos = t.names, 1
		while type(blob) == "string" do
			local at, stop = blob:find(phrase, pos, true)
			if not at then break end
			local lineEnd = blob:find("\n", stop, true) or (#blob + 1)
			local tab = blob:find("\t", stop, true)
			local from = math.max(1, at - 120)
			local back = blob:sub(from, at):match(".*\n()")
			local head = back and blob:sub(from + back - 1, at - 1) or ""
			if tab and tab < lineEnd and not head:find("<", 1, true)
				and not blob:sub(at - 1, at - 1):find("%w") and not blob:sub(stop + 1, stop + 1):find("%w") then
				return true
			end
			pos = stop + 1
		end
	end
	return false
end

--- The provider's hintFind: the first matching name (as the game writes it), the count, the
--- first ids (UI shows those rows themselves when there are only a few: hintRow), and the first
--- match's line in the index ("kyra boucher <reagent vendor>": lowercase, an NPC's title in <>),
--- for the overview to tell a match in the name from one in the title (0.56.11).
local function HintFind(t, tokens, tick)
	local id, count, ids, line = FindNames(t.names, tokens, tick)
	if not id then return nil, 0 end
	local DB = QDB()
	local name = DB and t.nameQuery and Safe(DB[t.nameQuery], id, "name")
	return type(name) == "string" and name or tostring(id), count, ids, line
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

-- rows by id for the chains (Chains.lua: an item's sellers and droppers, a quest that rewards it)
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
	-- (0.49.2, review: the first area pairs() gave and its first spawn, while the row's "N yd" and arrow are its nearest
	-- spawn on your continent: "nearest murloc forager" said 10 yd, Enter showed another zone and pinned it there, and
	-- ">> party" linked that spot. Where you are known: that same spawn.)
	local ui, c, isDoor = NearestSpawn(spawnsByZone, I.Here())
	if ui then return ui, { x = c[1] / 100, y = c[2] / 100 }, isDoor end
	-- (else the areas in order, the same answer every time; one out in the world before a dungeon's entrance)
	local zones = {}
	for zone in pairs(spawnsByZone) do if type(zone) == "number" then zones[#zones + 1] = zone end end
	table.sort(zones)
	local door
	for _, zone in ipairs(zones) do
		local spawns = spawnsByZone[zone]
		c = type(spawns) == "table" and spawns[1]
		-- (a dungeon's: its entrance, whatever spot it has inside (Questie's { -1, -1 } for most); 0.51.18, the player's
		-- ask: they had no location at all)
		local doors = type(c) == "table" and I.Entrances and I.Entrances(zone)
		if doors then
			if not door then door = { doors[1][1], { x = doors[1][2][1] / 100, y = doors[1][2][2] / 100 } } end
		elseif type(c) == "table" and c[1] and c[1] >= 0 then
			ui = QD.UiMapOfArea(zone)
			if ui then return ui, { x = c[1] / 100, y = c[2] / 100 } end
		end
	end
	if door then return door[1], door[2], true end
end

local function ShowNpc(e)
	local M = ns.Maps
	local mapID, pos, dungeon = NpcLocation(e.npcID)
	if not mapID then
		ns:Print(L["Questie has no known location for %s."]:format(e.npcName or e.name))
		return
	end
	if not InCombatLockdown() then
		-- Questie's own marker for it on the map
		local QM = QD.Module("QuestieMap")
		if QM and QM.ShowNPC then Safe(QM.ShowNPC, QM, e.npcID) end
	end
	M.ShowAfter({ name = (e.npcName or e.name) .. (dungeon and (" " .. L["(dungeon entrance)"]) or ""), mapID = mapID, pos = pos })
end

local function NpcPin(e)
	local mapID, pos = NpcLocation(e.npcID or (e.kind == "npc" and rawget(e, "key")) or nil)
	local name = e.npcName or e.name
	if not mapID then
		ns:Print(L["Questie has no known location for %s."]:format(name))
	else
		local pin = ns.Maps.Place({ name = name, mapID = mapID, pos = pos })
		if pin then ns:Print(ns.Maps.PinLine(pin, name)) return end
		ns:Print(L["Can't set a waypoint there."])
	end
end

I.NpcPin = NpcPin -- (the console's pin)

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
	if InCombatLockdown() then ns:Print(L["In combat: can't target %s from here; pinning it instead."]:format(tostring(e.name))) end
	NpcPin(e)
end

local function OpenNpcDirect(e)
	-- no press could be set up: the map shown already shows it; else it's pinned and where to open the map said (never
	-- opened from Terminal's own code: it taints the map; 0.50.7, review)
	if InCombatLockdown() then ns:Print(L["In combat: can't open %s now."]:format(e.name)) return end
	if not NpcLocation(e.npcID) then -- nowhere to show it: leave the map alone
		ns:Print(L["Questie has no known location for %s."]:format(e.npcName or e.name))
		return
	end
	if ns.Maps.MapOpen() then C_Timer.After(0.1, function() ShowNpc(e) end) return end
	NpcPin(e)
	ns:Print(L["Open %s from its button or key (opening it from Terminal's own code would taint it)."]:format(L["World Map"]))
end

-- (for QuestieQuests.lua: the quest rows' actions and the providers' setup)
local IP = I._
IP.HintFind, IP.NpcHintRow, IP.QuestHintRow, IP.IndexNPCs, IP.NpcLocation = HintFind, NpcHintRow, QuestHintRow, IndexNPCs, NpcLocation
IP.ShowNpc, IP.NpcPin, IP.OpenNpcDirect = ShowNpc, NpcPin, OpenNpcDirect
IP.NPC_TARGET, IP.NeverTargeted, IP.TargetFallback = NPC_TARGET, NeverTargeted, TargetFallback
