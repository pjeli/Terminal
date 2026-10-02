local ns = select(2, ...)
local H = ns.Highlight

-- Other addons, picked up when you log in:
--
--   AtlasLoot (Classic / Forever)  every item in its loot tables becomes searchable
--       ("Loot": item, "Boss  Instance"). Enter opens AtlasLoot on that boss and difficulty
--       and points at the item.
--   Questie  NPCs, searched with @npc. Enter opens the world map on the NPC, puts Questie's
--       marker for it there and drops the map pin; Shift+Enter only moves the pin.
--
-- Neither addon is required; with neither installed this file does nothing. .integrations
-- shows what was found.

local I = {}
ns.Integrations = I

local function Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

----------------------------------------------------------------------
-- AtlasLoot
----------------------------------------------------------------------

local loot = { rows = {}, byKey = {}, pending = {}, modules = 0, loaded = 0, on = false }
I.loot = loot

local function AL() return _G.AtlasLoot end

--- AtlasLoot's own addon is loaded and enabled (not just a leftover AtlasLoot table from a
--- plugin or library), with the loot database Terminal reads.
local CORE = { "AtlasLootClassic", "AtlasLoot", "AtlasLootForever" }
local function AtlasLootPresent()
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	if isLoaded then
		local any = false
		for _, name in ipairs(CORE) do
			local ok, yes = pcall(isLoaded, name)
			if ok and yes then any = true; break end
		end
		if not any then return false end
	end
	local a = AL()
	return type(a) == "table" and a.ItemDB and a.ItemDB.Storage and a.Loader and true or false
end

--- Rows for one loaded loot module: one per item and instance (the first boss and
--- difficulty it drops on), kept apart from names, which arrive from the server over time.
local function IndexModule(addon, storage)
	local A = AL()
	local added = 0
	local diffs = Safe(storage.GetDifficultys, storage) or {}
	local ndiff = math.max(#diffs, 1)
	for content, c in pairs(storage) do
		if type(c) == "table" and type(c.items) == "table" then
			local inst = Safe(c.GetName, c, true)
			if type(inst) ~= "string" then inst = tostring(content) end
			for boss = 1, #c.items do
				local bossName = Safe(c.GetNameForItemTable, c, boss, true)
				if type(bossName) ~= "string" then bossName = "?" end
				for d = 1, ndiff do
					local list = Safe(A.ItemDB.GetItemTable, A.ItemDB, addon, content, boss, d)
					if type(list) == "table" then
						for _, row in ipairs(list) do
							local id = type(row) == "table" and row[2]
							if type(id) == "number" and id > 0 then
								local key = addon .. ":" .. tostring(content) .. ":" .. id
								if not loot.byKey[key] then
									local r = { key = key, itemID = id, addon = addon, content = content, boss = boss, diff = d,
										inst = inst, bossName = bossName }
									loot.byKey[key] = r
									loot.rows[#loot.rows + 1] = r
									loot.pending[#loot.pending + 1] = id
									added = added + 1
								end
							end
						end
					end
				end
			end
		end
	end
	return added
end

local function Dirty()
	if ns.providers.loot then ns.providers.loot._dirty = true end
end

-- Ask the server for item names a little at a time; the provider refreshes as they arrive.
local function PumpNames()
	if loot.pumping then return end
	loot.pumping = true
	local i = 1
	local function step()
		if InCombatLockdown() then return C_Timer.After(5, step) end
		local stop = math.min(i + 100, #loot.pending)
		while i <= stop do
			local id = loot.pending[i]
			if not (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) and C_Item.RequestLoadItemDataByID then
				C_Item.RequestLoadItemDataByID(id)
			end
			i = i + 1
		end
		if i <= #loot.pending then C_Timer.After(0.5, step) else loot.pumping = false; loot.pending = {} end
	end
	step()
end

--- Loads AtlasLoot's loot modules one at a time (they are load-on-demand) so there is no
--- single long pause, indexing each as it arrives.
local function LoadLootModules()
	local A = AL()
	local list = Safe(A.Loader.GetLootModuleList, A.Loader)
	local mods = {}
	for _, m in ipairs(list and list.module or {}) do mods[#mods + 1] = m.addonName end
	for _, m in ipairs(list and list.custom or {}) do mods[#mods + 1] = m.addonName end
	loot.modules = #mods
	local i = 0
	local function nextModule()
		if InCombatLockdown() then return C_Timer.After(5, nextModule) end
		i = i + 1
		local addon = mods[i]
		if not addon then
			loot.done = true
			Dirty()
			return PumpNames()
		end
		Safe(A.Loader.LoadModule, A.Loader, addon)
		local storage = A.ItemDB.Storage[addon]
		if storage then
			loot.loaded = loot.loaded + 1
			IndexModule(addon, storage)
			Dirty()
		end
		C_Timer.After(1.5, nextModule)
	end
	nextModule()
end

local function OpenLoot(e)
	local A = AL()
	local GUI = A and A.GUI
	if not (GUI and GUI.frame) then
		ns:Print("AtlasLoot's window isn't ready yet.")
		return
	end
	local f = GUI.frame
	if not f:IsShown() then f:Show() end
	Safe(f.moduleSelect.SetSelected, f.moduleSelect, e.addon)
	Safe(f.subCatSelect.SetSelected, f.subCatSelect, e.content)
	Safe(f.boss.SetSelected, f.boss, e.boss)
	if f.difficulty then Safe(f.difficulty.SetSelected, f.difficulty, e.diff) end
	H:When(function()
		local frame = GUI.ItemFrame and GUI.ItemFrame.frame
		for _, b in ipairs(frame and frame.ItemButtons or {}) do
			if b.ItemID == e.itemID and b:IsVisible() then return b end
		end
	end, function(b) H:Show(b, 6) end, 30)
end

local function SetupAtlasLoot()
	if loot.on or not AtlasLootPresent() then return end
	loot.on = true
	ns:RegisterProvider("loot", {
		label = "Loot",
		color = "ffd9a441",
		aliases = { "loot", "drop", "drops", "atlasloot", "al" },
		lazy = true,
		events = { "GET_ITEM_INFO_RECEIVED" },
		guard = 5,
		collect = function()
			local out = {}
			if not AtlasLootPresent() then return out end -- AtlasLoot went away: no stale loot rows
			for _, r in ipairs(loot.rows) do
				local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.itemID)
				if type(name) == "string" and name ~= "" then
					out[#out + 1] = {
						key = r.key, name = name,
						icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.itemID) or nil,
						detail = r.bossName .. "  " .. r.inst,
						text = r.inst .. " " .. r.bossName .. " loot drop atlasloot",
						link = "item:" .. r.itemID,
						itemID = r.itemID, addon = r.addon, content = r.content, boss = r.boss, diff = r.diff,
						activate = OpenLoot,
					}
				end
			end
			return out
		end,
	})
	C_Timer.After(8, LoadLootModules)
end

----------------------------------------------------------------------
-- Questie
----------------------------------------------------------------------

local npc = { list = nil, busy = false, on = false }
I.npc = npc

local function QuestieReady()
	local Q = _G.Questie
	return Q and Q.API and Q.API.isReady and _G.QuestieLoader and true or false
end

local function QModule(name) return Safe(_G.QuestieLoader.ImportModule, _G.QuestieLoader, name) end

--- NPC names, a slice at a time so the game doesn't stall while Questie's database is read.
local function IndexNPCs()
	if npc.list or npc.busy or not QuestieReady() then return end
	local DB = QModule("QuestieDB")
	if not (DB and DB.NPCPointers and DB.QueryNPCSingle) then return end
	npc.busy = true
	local ids = {}
	for id in pairs(DB.NPCPointers) do if type(id) == "number" then ids[#ids + 1] = id end end
	table.sort(ids)
	local out, i = {}, 1
	local function step()
		local stop = math.min(i + 1500, #ids)
		while i <= stop do
			local id = ids[i]
			local name = Safe(DB.QueryNPCSingle, id, "name")
			if type(name) == "string" and name ~= "" then out[#out + 1] = { id = id, name = name } end
			i = i + 1
		end
		if i <= #ids then
			C_Timer.After(0, step)
		else
			npc.list, npc.busy = out, false
			if ns.providers.npc then ns.providers.npc._dirty = true end
		end
	end
	step()
end

--- Where the NPC stands: uiMapID, position {x,y} (0-1), and whether that's a dungeon's
--- entrance rather than the NPC itself.
local function NpcLocation(id)
	local DB, Z = QModule("QuestieDB"), QModule("ZoneDB")
	local n = DB and Safe(DB.GetNPC, DB, id)
	if not (n and n.spawns and Z) then return end
	for zone, spawns in pairs(n.spawns) do
		local c = spawns and spawns[1]
		if c and c[1] and c[1] >= 0 then
			local dl = Safe(Z.GetDungeonLocation, Z, zone)
			if type(dl) == "table" and dl[1] then
				local ui = Safe(Z.GetUiMapIdByAreaId, Z, dl[1][1])
				if ui then return ui, { x = dl[1][2] / 100, y = dl[1][3] / 100 }, true end
			else
				local ui = Safe(Z.GetUiMapIdByAreaId, Z, zone)
				if ui then return ui, { x = c[1] / 100, y = c[2] / 100 } end
			end
		end
	end
end

local function ShowNpc(e)
	local M = ns.Maps
	local mapID, pos, dungeon = NpcLocation(e.npcID)
	if not mapID then
		ns:Print("Questie has no known location for " .. e.name .. ".")
		return
	end
	if not InCombatLockdown() then
		-- Questie's own marker for it on the map
		local QM = QModule("QuestieMap")
		if QM and QM.ShowNPC then Safe(QM.ShowNPC, QM, e.npcID) end
	end
	M.ShowAfter({ name = e.name .. (dungeon and " (dungeon entrance)" or ""), mapID = mapID, pos = pos })
end

local function NpcPin(e)
	local mapID, pos = NpcLocation(e.npcID)
	if not mapID then
		ns:Print("Questie has no known location for " .. e.name .. ".")
	elseif ns.Maps.Place({ name = e.name, mapID = mapID, pos = pos }) then
		ns:Print("Waypoint set: " .. e.name)
	else
		ns:Print("Can't set a waypoint there.")
	end
end

local function OpenNpcDirect(e)
	-- no map keybinding to ride on: open the map ourselves (never in combat)
	if InCombatLockdown() then ns:Print("In combat: can't open " .. e.name .. " now.") return end
	if ToggleWorldMap and not ns.Maps.MapOpen() then pcall(ToggleWorldMap) end
	C_Timer.After(0.1, function() ShowNpc(e) end)
end

local function SetupQuestie()
	if npc.on or not (_G.Questie and _G.QuestieLoader) then return end
	npc.on = true
	ns:RegisterProvider("npc", {
		label = "NPC",
		color = "ffe0a060",
		aliases = { "npc", "npcs", "n", "mob", "vendor", "questie" },
		explicit = true, -- tens of thousands of names: only searched with @npc
		noCombat = true,
		guard = 10,
		collect = function()
			local out = {}
			for _, n in ipairs(npc.list or {}) do
				out[#out + 1] = {
					key = n.id, name = n.name, icon = "Interface\\Icons\\INV_Misc_Head_Human_01",
					detail = "NPC  #" .. n.id, text = "npc questie " .. n.id,
					npcID = n.id,
					secure = ns.Maps.SECURE,
					isOpen = ns.Maps.MapOpen,
					after = ShowNpc,
					activate = OpenNpcDirect,
					secondary = NpcPin,
				}
			end
			return out
		end,
	})
	if QuestieReady() then
		C_Timer.After(2, IndexNPCs)
	elseif _G.Questie.API and _G.Questie.API.RegisterOnReady then
		Safe(_G.Questie.API.RegisterOnReady, function() C_Timer.After(2, IndexNPCs) end)
	end
end

----------------------------------------------------------------------

function I.Setup()
	SetupAtlasLoot()
	SetupQuestie()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() I.Setup() end)

ns:RegisterCommand("integrations", {
	desc = "Show which other addons Terminal found (AtlasLoot, Questie)",
	run = function()
		local lines = { "Integrations:" }
		lines[#lines + 1] = "  AtlasLoot: " .. (loot.on
			and ("found. %d loot modules, %d indexed, %d items%s"):format(loot.modules, loot.loaded, #loot.rows, loot.done and "" or " (still loading)")
			or "not found")
		lines[#lines + 1] = "  Questie: " .. (npc.on
			and (npc.list and ("found. %d NPCs indexed (search with @npc)"):format(#npc.list)
				or (QuestieReady() and "found, indexing NPCs..." or "found, waiting for Questie to finish loading"))
			or "not found")
		for _, l in ipairs(lines) do print("Terminal " .. l) end
		return lines
	end,
})
