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
--   Attune  its attunements, dungeon quest lines, keys and class quests (@attune), with how far along you are and your
--       next step; Enter opens Attune's window on one and points at it; "<attunement> > steps" lists its steps.
--
--   What's Training (its public API, WT_API)  every spell, rank, weapon skill and pet ability your class has still to
--       learn (@training), with when, what it costs and where it's taught; Enter opens What's Training's window on one
--       and points at it; "<spell> > learn" lists who teaches it, the nearest first.
--
-- None of them is required; with none installed only the dungeon and raid entrance lists
-- (@dungeon, @raid: Terminal's own data) are left. .integrations shows what was found.

local I = {}
ns.Integrations = I
I.HINT_FEW = 2 -- (UI.HINT_FEW: a list with this many matches or fewer shows them as results)

-- Integrations/ is one module over several files, loaded in this order (Terminal.toc): Shared (this: the table and
-- the helpers every part uses), Loot (AtlasLoot), Distances (world positions), Objects (mailboxes), Entrances
-- (@dungeon/@raid), Flights (@flight), Questie (its data, NPCs, the name index), QuestieQuests (@questie, the Questie providers),
-- Attune (@attune), WhatsTraining (@training), Places (zones and towns by name), Setup (login, .integrations). What one file needs from another is on I (public)
-- or on I._ (Terminal's own, between these files only); a later file takes it into a local when it loads.
I._ = {}

local Safe = ns.Safe -- (Util.lua)
local L = ns.L

-- An integration Terminal can't use as it is (0.57.1, the author's call: "give output when an integration fails and what
-- to expect"): its addon is there, but not in the shape Terminal reads (a new version moved its data, or starting it
-- failed). Said once a session in chat, naming what's unavailable ("Questie's data isn't what Terminal expects (a new
-- version?): @npc and @questie are unavailable."); .integrations lists it. Each part of an addon is said on its own.
I.failed = {} -- addon name -> { { what, why }, ... }
--- `name`: the addon as players know it; `what`: what goes missing, a sentence ("@npc and @questie are unavailable.");
--- `why`: for the .debug trace (what was found instead).
function I.Failed(name, what, why)
	local list = I.failed[name] or {}
	I.failed[name] = list
	for _, f in ipairs(list) do if f.what == what then return end end
	list[#list + 1] = { what = what, why = why }
	ns:Trace("integrations: " .. tostring(name) .. ": " .. tostring(what) .. " (" .. tostring(why) .. ")")
	ns:Print(L["%s: its data isn't what Terminal expects (a new version?). %s"]:format(tostring(name), tostring(what)))
end
--- What .integrations says of an addon's failures ("" when none).
function I.FailedText(name)
	local list = I.failed[name]
	if not list or #list == 0 then return "" end
	local parts = {}
	for _, f in ipairs(list) do parts[#parts + 1] = f.what end
	return " |cffff6060" .. L["Not as expected:"] .. " " .. table.concat(parts, " ") .. "|r"
end

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
