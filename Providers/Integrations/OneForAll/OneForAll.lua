local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations

-- OneForAll - Forever (Smoergi's, GPL-3): its tables read while it's installed, never copied into Terminal. It has no
-- API: its whole namespace is the global OneForAll (its Data.lua: _G[ADDON] = FLT), so its tables are read as they are,
-- each checked first; one that isn't in the shape expected is left out and said once in chat (I.Failed: what's
-- unavailable), the rest still used. What each part makes is in Providers/Integrations/OneForAll/:
--
--   BOOKS, BOOK_REWARD_TIERS, MAP_IDS     @book: the Library Books (Books.lua)
--   PET_ABILITIES, PET_FAMILIES, PET_RARES  a hunter's only: its pet abilities' ranks in @spell, who teaches each, the
--                                         beasts to tame in @npc (is:tameable) and its questions (Pets.lua)
--   ARMORY_REPUTATION, ARMORY_SETS        "> rewards" (reputation rewards) and @itemset (Armory.lua)
--   WEAPON_TRAINERS, MERCHANT_RECIPES, MAP_LANDMARKS, DUNGEON_DROP_CHANCE
--                                         weapon masters, Merchant's Favor recipes (on @recipe's unknown ones), boats, zeppelins and the tram,
--                                         loot drop chances (World.lua)
--   GearValue, GearIndex                  is:upgrade judged by OneForAll's gear value, its suggested gear (Upgrades.lua)
--   UI.panels, OpenPanel                  its window's tabs as @panel rows (below)

local OA = {}
ns.OneForAll = OA
OA.ADDON, OA.NAME = "OneForAll", "OneForAll"

local Safe = ns.Safe

--- Is OneForAll loaded, its namespace there?
function OA.Loaded()
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	if not isLoaded then return false end
	local ok, yes = pcall(isLoaded, OA.ADDON)
	return ok and yes == true and type(rawget(_G, "OneForAll")) == "table"
end

--- Its namespace, or nil.
function OA.Lib()
	if not OA.Loaded() then return nil end
	return rawget(_G, "OneForAll")
end

--- Its TOC Version, as text.
function OA.Version() return I._.AddOnVersion(OA.ADDON) end

local parts = {} -- each part read once: its result, or false (not usable)
function OA.Forget() parts = {} end -- (tests)

--- One part of its data: its namespace's `field` made usable by `make(raw, lib)` (which gives the part, or nil and why).
--- A part whose table is missing or not in the shape expected is said once (`lost`: what's unavailable without it);
--- `optional`: a table some versions don't have, left out quietly when missing.
function OA.Part(key, field, lost, make, optional)
	local got = parts[key]
	if got ~= nil then return got or nil end
	local lib = OA.Lib()
	if not lib then return nil end
	local raw = rawget(lib, field)
	local res, why
	if type(raw) ~= "table" then
		why = "OneForAll." .. field .. " is " .. (raw == nil and "missing" or ("a " .. type(raw)))
		if raw == nil and optional then parts[key] = false return nil end
	else
		local ok, a, b = pcall(make, raw, lib)
		if ok then res, why = a, b else why = tostring(a) end
	end
	if res == nil then
		I.Failed(OA.NAME, lost, why or ("OneForAll." .. field .. ": nothing in the shape expected"))
		parts[key] = false
		return nil
	end
	parts[key] = res
	return res
end

--- One of its functions called (its own code, in a pcall): its results, or nil when it's not there or errors.
function OA.Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	return Safe(fn, ...)
end

--- A text from its data: a string, else nil.
function OA.Text(v) return type(v) == "string" and v ~= "" and v or nil end

--- Does every word (lowercase) appear in a row's name or its text? The parts' questions ask it of whole lists per
--- keystroke: each looked for in each, no string joined per row.
function OA.Has(e, words)
	if not words or #words == 0 then return true end
	local n, t = rawget(e, "_lname") or "", rawget(e, "_ltext") or rawget(e, "text") or ""
	for i = 1, #words do
		local w = words[i]
		if not (n:find(w, 1, true) or t:find(w, 1, true)) then return false end
	end
	return true
end

--- A search to walk to (the last one kept for Shift+Left to go back: UI:WalkTo), from a row's Enter.
function OA.Walk(text, e)
	local UI = ns.UI
	if UI and UI.WalkTo then UI:WalkTo(text, e) elseif UI and UI.SetQuery then UI:SetQuery(text, #text) end
end

--- Has the character you're on turned this quest in?
function OA.QuestDone(id)
	local f = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or _G.IsQuestFlaggedCompleted
	return f and Safe(f, id) == true or false
end

--- Your faction as OneForAll's tables say it: "A", "H", or nil.
function OA.Side()
	local f = UnitFactionGroup and Safe(UnitFactionGroup, "player")
	return (f == "Alliance" and "A") or (f == "Horde" and "H") or nil
end

--- The rows by how far each is from you, nearest first, each a view saying so (I.NearView: the English "N yd" the
--- list's distance column reads back, translated there, kept up to date as you walk); those with no spot after. Nil
--- when where you are isn't known.
function OA.Nearest(rows)
	local here = I.Here and I.Here()
	if not here then return nil end
	local near, far = {}, {}
	for _, e in ipairs(rows) do
		local d = I.RowYards and I.RowYards(e, here)
		if d then near[#near + 1] = { e = e, d = d } else far[#far + 1] = e end
	end
	table.sort(near, function(a, b) return a.d < b.d end)
	local out = {}
	for i, n in ipairs(near) do out[i] = I.NearView(n.e, n.d, rawget(n.e, "detail")) end
	for _, e in ipairs(far) do out[#out + 1] = e end
	return out
end

--- A name as its words, lowercase, no marks, one space between ("Ashbringer's Might" -> "ashbringers might"): how
--- the parts match what's typed against OneForAll's names (not ns.Norm, which drops the spaces).
function OA.Words(s) return (ns.Lower(tostring(s or "")):gsub("'", ""):gsub("[%p]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end

-- each part's setup (its lists registered) and its line for .integrations, in this order (the files of
-- Providers/Integrations/OneForAll/ add theirs)
OA.SETUPS, OA.STATUS = {}, {}
function OA.AddSetup(fn) OA.SETUPS[#OA.SETUPS + 1] = fn end
--- `fn` -> a few words for .integrations ("39 Library Books (@book)"), or nil (that part not there).
function OA.AddStatus(fn) OA.STATUS[#OA.STATUS + 1] = fn end

--- .integrations' line: found, its version and what each part gave; or not found.
function OA.Status()
	if not OA.Loaded() then return L["not found"] end
	local said = {}
	for _, fn in ipairs(OA.STATUS) do
		local ok, s = pcall(fn)
		if ok and type(s) == "string" and s ~= "" then said[#said + 1] = s end
	end
	return L["%s (%s)."]:format("OneForAll", OA.Version()) .. (#said > 0 and (" " .. table.concat(said, ", ")) or "")
end

----------------------------------------------------------------------
-- Its window's tabs in @panel: "OneForAll: Dungeons & Raids", Enter opens its window on it (its own OpenPanel; its
-- window is its own frame, not Blizzard's). The tabs are read from its list (UI.panels: key, label), so a new one in a
-- new version is there too. Opening a tab hidden in its settings shows it again, as its own buttons do.
----------------------------------------------------------------------

--- Its tabs, checked: { { key, label } } in its order, or nil.
function OA.Tabs()
	return OA.Part("tabs", "UI", L["Its window's tabs (in @panel) are unavailable."], function(raw, lib)
		if type(lib.OpenPanel) ~= "function" then return nil, "OneForAll.OpenPanel is " .. type(lib.OpenPanel) end
		local out = {}
		for _, spec in ipairs(type(raw.panels) == "table" and raw.panels or {}) do
			if type(spec) == "table" and OA.Text(spec.key) and OA.Text(spec.label) then out[#out + 1] = { key = spec.key, label = spec.label } end
		end
		if #out == 0 then return nil, "OneForAll.UI.panels: no tab in the shape expected" end
		return out
	end, true)
end

local function OpenTab(e)
	local lib = OA.Lib()
	if not (lib and type(lib.OpenPanel) == "function") then return ns:Trace("oneforall: OpenPanel is gone") end
	local ok, err = pcall(lib.OpenPanel, lib, e.oneForAllTab)
	if not ok then ns:Trace("oneforall: OpenPanel " .. tostring(e.oneForAllTab) .. " failed: " .. tostring(err)) end
end

--- @panel's rows for its tabs.
function OA.PanelRows()
	local out = {}
	for _, t in ipairs(OA.Tabs() or {}) do
		local name = "OneForAll: " .. t.label
		out[#out + 1] = { key = "oneforall:" .. t.key, name = name, oneForAllTab = t.key, icon = "Interface\\Icons\\INV_Misc_Book_09",
			text = "oneforall ofa " .. ns.Lower(t.label) .. " " .. t.key, activate = OpenTab,
			noCombat = true } -- (its window holds secure craft buttons once its Professions tab is made: shown in combat, blocked)
	end
	return out
end

OA.AddSetup(function()
	if not OA.Tabs() or OA.panelsAdded then return end
	OA.panelsAdded = true
	ns.PanelExtras = ns.PanelExtras or {}
	table.insert(ns.PanelExtras, function() return OA.Loaded() and OA.PanelRows() or {} end)
	ns:Changed("panels")
end)
OA.AddStatus(function()
	local t = OA.Tabs()
	return t and L["%d of its window's tabs (@panel)"]:format(#t) or nil
end)

local function SetupOneForAll()
	if OA.on or not OA.Loaded() then return end
	OA.on = true
	-- (each part on its own: one failing leaves the others)
	for _, fn in ipairs(OA.SETUPS) do
		local ok, err = pcall(fn)
		if not ok then ns:Trace("oneforall: a part failed to start: " .. tostring(err)) end
	end
end
I._.SetupOneForAll = SetupOneForAll
