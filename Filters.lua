local ns = select(2, ...)

-- Filters typed into the search as key:value words, alongside the words matched by name:
--   lvl:20-30  lvl:20  lvl:<30  lvl:40-   quest level, or the level an item needs
--   slot:wrist                            an item's equipment slot (the game's own name for it)
--   zone:ashenvale                        a quest's zone
--   is:done  is:todo                      a quest you've finished / not finished
--   is:usable                             an item your character can use or wear now
-- A row the filter can't judge (no level, not an item...) is left out. Unknown keys or values
-- stay ordinary search words.

local F = {}
ns.Filters = F

local function ItemInfo(id)
	local get = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if not (get and id) then return nil end
	local ok, name, _, _, _, minLevel, _, _, _, equipLoc = pcall(get, id)
	if ok and name then return minLevel, equipLoc end
end

--- The quest a row is (not a quest item that merely belongs to one).
local function QuestOf(e)
	local q = rawget(e, "qid") or e.qid
	if q then return q end
	if e.kind == "quests" then return e.questID end
end

local function Level(e)
	local id = e.itemID
	if id then
		local minLevel = ItemInfo(id)
		return type(minLevel) == "number" and minLevel or nil
	end
	local l = e.level
	return type(l) == "number" and l or nil
end

local function Done(q)
	return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q) and true or false
end

local function Usable(e)
	local id = e.itemID
	if not id then return false end
	local minLevel = ItemInfo(id)
	if type(minLevel) == "number" and minLevel > (UnitLevel("player") or 0) then return false end
	if C_PlayerInfo and C_PlayerInfo.CanUseItem then
		local ok, yes = pcall(C_PlayerInfo.CanUseItem, id)
		if ok then return yes and true or false end
	end
	return true
end

-- key -> function(value) giving a test, or nil when the value isn't one this key takes
local KEYS = {}

KEYS.lvl = function(v)
	local lo, hi
	local a, b = v:match("^(%d*)%-(%d*)$")
	if a then
		lo, hi = tonumber(a), tonumber(b)
		if not lo and not hi then return nil end
	elseif v:match("^<=?%d+$") then
		hi = tonumber(v:match("%d+")) - (v:find("=", 1, true) and 0 or 1)
	elseif v:match("^>=?%d+$") then
		lo = tonumber(v:match("%d+")) + (v:find("=", 1, true) and 0 or 1)
	elseif v:match("^%d+$") then
		lo = tonumber(v); hi = lo
	else
		return nil
	end
	return function(e)
		local l = Level(e)
		return l ~= nil and (not lo or l >= lo) and (not hi or l <= hi)
	end
end
KEYS.level = KEYS.lvl

KEYS.slot = function(v)
	if v == "" then return nil end
	return function(e)
		if not e.itemID then return false end
		local _, loc = ItemInfo(e.itemID)
		if type(loc) ~= "string" or loc == "" then return false end
		local shown = _G[loc]
		return (type(shown) == "string" and ns.Lower(shown):find(v, 1, true))
			or loc:lower():find(v, 1, true) and true or false
	end
end

KEYS.zone = function(v)
	if v == "" then return nil end
	return function(e)
		local z = e.zone
		return type(z) == "string" and ns.Lower(z):find(v, 1, true) and true or false
	end
end

local IS = {
	done = function(e) local q = QuestOf(e); return q ~= nil and Done(q) end,
	todo = function(e) local q = QuestOf(e); return q ~= nil and not Done(q) end,
	usable = Usable,
}
IS.notdone, IS.undone, IS.use, IS.wearable = IS.todo, IS.todo, IS.usable, IS.usable
KEYS.is = function(v) return IS[v] end

--- A filter for one typed word, or nil when it isn't one (then it's searched as text).
function F.Parse(word)
	local key, value = word:match("^(%a+):(.+)$")
	if not key then return nil end
	local make = KEYS[ns.Lower(key)]
	return make and make(ns.Lower(value)) or nil
end

--- Every filter passes this row.
function F.Pass(e, filters)
	for i = 1, #filters do
		local ok, yes = pcall(filters[i], e)
		if not (ok and yes) then return false end
	end
	return true
end

F.KEYS = KEYS
