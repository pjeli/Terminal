local ns = select(2, ...)

-- Other addons, picked up when you log in:
--
--   AtlasLoot (Classic, Forever, or AtlasLoot Continued)  every item in its loot tables becomes searchable
--       ("Loot": item, "Boss  Instance"). Enter opens AtlasLoot on that boss and difficulty
--       and points at the item.
--   Questie  every quest in its database, searched with @questie (Enter: its Wowhead link, ready
--       to copy; Shift+Enter: the quest log for quests you're on, otherwise the quest giver on
--       the map), and NPCs, searched with @npc.
--       Enter opens the world map on the NPC, puts Questie's marker for it there and drops
--       the map pin; Shift+Enter targets it (/targetexact, pressed by the game; in combat it only
--       moves the pin).
--
-- Neither addon is required; with neither installed only the dungeon and raid entrance lists
-- (@dungeon, @raid: Terminal's own data) are left. .integrations shows what was found.

local I = {}
ns.Integrations = I
I.HINT_FEW = 2 -- (UI.HINT_FEW: a list with this many matches or fewer shows them as results)

-- Integrations/ is one module over several files, loaded in this order (Terminal.toc): Shared (this: the table and
-- the helpers every part uses), Loot (AtlasLoot), Distances (world positions), Objects (mailboxes), Entrances
-- (@dungeon/@raid), Questie (its data, NPCs, the name index), QuestieQuests (@questie, the Questie providers),
-- Places (zones and towns by name), Setup (login, .integrations). What one file needs from another is on I (public)
-- or on I._ (Terminal's own, between these files only); a later file takes it into a local when it loads.
I._ = {}

local Safe = ns.Safe -- (Util.lua)

--- An addon's TOC Version, as text ("?" when unknown).
local function AddOnVersion(name)
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
	return tostring(meta and Safe(meta, name, "Version") or "?")
end

--- The link of the map pin just set (C_Map.SetUserWaypoint), or nil.
local function WaypointLink()
	local link = C_Map and C_Map.GetUserWaypointHyperlink and Safe(C_Map.GetUserWaypointHyperlink)
	return type(link) == "string" and link ~= "" and link or nil
end
I._.AddOnVersion, I._.WaypointLink = AddOnVersion, WaypointLink

--- NPC names, a slice at a time so the game doesn't stall while Questie's database is read.
--- Work through n items a few milliseconds per frame (SLICE_MS), however long each takes, so
--- indexing never stalls a frame; then done(). A failing item is skipped and traced. The time
--- taken goes to the trace (.debug log).
local SLICE_MS = 5
local function Now() return _G.debugprofilestop and _G.debugprofilestop() or (GetTime() * 1000) end
local function RunSliced(what, n, each, done)
	local i, started = 1, Now()
	ns.background = (ns.background or 0) + 1 -- (the prewarm waits while indexing runs)
	local function batch()
		local stop = Now() + SLICE_MS
		while i <= n do
			each(i)
			i = i + 1
			if Now() > stop then break end
		end
	end
	local function step()
		local ok, err = pcall(batch)
		if not ok then
			ns:Trace(("%s: item %d failed: %s"):format(what, i, tostring(err)))
			i = i + 1
		end
		if i <= n then return C_Timer.After(0, step) end
		ns:Trace(("%s: %d in %.0f ms"):format(what, n, Now() - started))
		ns.background = math.max(0, (ns.background or 1) - 1)
		done()
	end
	step()
end

I.RunSliced = RunSliced
