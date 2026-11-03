local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations

-- OneForAll - Forever (Smoergi's, GPL-3; 1.0.1, the player's ask): its tables read while it's installed, never copied
-- into Terminal. It has no API: its whole namespace is the global OneForAll (its Data.lua: _G[ADDON] = FLT), so its
-- tables are read as they are, each checked first; one that isn't in the shape expected is left out and said once in
-- chat (I.Failed: what's unavailable), the rest still used. What each part makes is in Providers/OneForAll/:
--
--   BOOKS, BOOK_REWARD_TIERS, MAP_IDS     @book: the Library Books (Books.lua)
--   PET_ABILITIES, PET_FAMILIES, PET_RARES  @tame (a hunter's only): a hunter's pet abilities, who teaches each rank, the
--                                         beasts to tame (Pets.lua)
--   ARMORY_REPUTATION, ARMORY_SETS        @repreward and @itemset (Armory.lua)
--   WEAPON_TRAINERS, MERCHANT_RECIPES, MAP_LANDMARKS, DUNGEON_DROP_CHANCE
--                                         weapon masters, Merchant's Favor recipes, boats, zeppelins and the tram,
--                                         loot drop chances (World.lua)
--   GearValue, GearIndex                  is:upgrade judged by OneForAll's gear value, its suggested gear (Upgrades.lua)

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

-- each part's setup (its lists registered) and its line for .integrations, in this order (the files of
-- Providers/OneForAll/ add theirs)
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
