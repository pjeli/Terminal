local ns = select(2, ...)
local L = ns.L

-- A hunter's pet food: "what can my pet eat" (your bags' food your pet eats: @item is:petfood) and "who sells pet food",
-- "nearest pet food vendor" (Questie's vendors of food of your pet's diet: @npc sells:petfood, nearest first). Only for a
-- hunter with a pet out; otherwise the answer says so.
--
-- The game says what your pet eats: C_PetInfo.GetPetFoodTypes() (its diet's names, in the client's language) and
-- C_PetInfo.CanPetEatItem(itemID) (Forever's PetHappiness.lua and ItemUtil.lua call both); an older client's global
-- GetPetFoodTypes() gives the names as several values. Food you don't carry is judged by QuestieDB's item field
-- `foodType` (cmangos' item_template.FoodType, QuestieDB's itemMeta.lua: 1 meat, 2 fish, 3 cheese, 4 bread, 5 fungus,
-- 6 fruit, 7 raw meat, 8 raw fish) against the diet's names (English; a meat eater eats raw meat too), and where a
-- name isn't one of those (another language), by asking CanPetEatItem of each food.

local PF = {}
ns.PetFood = PF
local Safe, Str, Num, Lower = ns.Safe, ns.Str, ns.Num, ns.Lower
local SEP = ns.DETAIL_SEP

-- a diet's name -> the food types it eats (QuestieDB's foodType numbers)
PF.DIET = { meat = { 1, 7 }, fish = { 2, 8 }, cheese = { 3 }, bread = { 4 }, fungus = { 5 }, fruit = { 6 }, ["raw meat"] = { 7 },
	["raw fish"] = { 8 } }
PF.FOOD_CLASSES = { [0] = true, [7] = true } -- (Consumable, Trade Goods: raw meat and fish are trade goods)

local foods -- { { id, ft, vendors } }: every Questie item with a food type that a vendor sells (read once)
local foodType = {} -- item id -> its food type (false: none)
local vendorsOf = { key = nil, set = nil, foods = nil } -- the last diet's vendors

--- Your pet's diet, the game's: { names (its words), types ({ [food type] = true }), unknown (a name not read),
--- key }; nil and why ("class": not a hunter, "pet": no pet out, "diet": the game says none).
local dietAt, dietGot, dietWhy -- (asked per row by is:petfood: read once a frame)
function PF.Diet()
	local now = GetTime and GetTime()
	if now and dietAt == now then return dietGot, dietWhy end
	dietGot, dietWhy = PF.ReadDiet()
	dietAt = now
	return dietGot, dietWhy
end
function PF.ReadDiet()
	local _, class = Safe(UnitClass, "player")
	if class ~= "HUNTER" then return nil, "class" end
	if not (_G.UnitExists and Safe(UnitExists, "pet") == true) then return nil, "pet" end
	local got
	local C = rawget(_G, "C_PetInfo")
	if C and type(C.GetPetFoodTypes) == "function" then got = Safe(C.GetPetFoodTypes)
	elseif type(rawget(_G, "GetPetFoodTypes")) == "function" then got = { Safe(_G.GetPetFoodTypes) } end
	local names, types, unknown = {}, {}, false
	for _, n in ipairs(type(got) == "table" and got or {}) do
		n = Str(n)
		if n then
			names[#names + 1] = n
			local ids = PF.DIET[Lower(n)]
			if ids then for _, i in ipairs(ids) do types[i] = true end else unknown = true end
		end
	end
	if #names == 0 then return nil, "diet" end
	return { names = names, types = types, unknown = unknown, key = table.concat(names, "\001") }
end

--- The diet's names as the game's pet tooltip says them ("Diet: Meat, Fish"), or nil.
function PF.DietText(d)
	d = d or PF.Diet()
	if not d then return nil end
	local delim = Str(rawget(_G, "PET_FOOD_DELIMIT")) or ", "
	local list = table.concat(d.names, delim)
	local tpl = Str(rawget(_G, "PET_DIET_TEMPLATE"))
	if tpl and select(2, tpl:gsub("%%s", "")) == 1 and not tpl:find("%%[^s]") then return (tpl:gsub("%%s", (list:gsub("%%", "%%%%")))) end
	return list
end

local function DB()
	local QD = ns.QuestieData
	local db = QD and QD.DB()
	return db and db.QueryItemSingle and db or nil
end

--- An item's food type, QuestieDB's (nil: none, or no QuestieDB).
function PF.FoodType(id)
	local got = foodType[id]
	if got ~= nil then return got or nil end
	local db = DB()
	if not db then return nil end
	local ft = Num(Safe(db.QueryItemSingle, id, "foodType"))
	if ft == 0 then ft = nil end
	foodType[id] = ft or false
	return ft
end

local function CanEat(id)
	local C = rawget(_G, "C_PetInfo")
	if not (C and type(C.CanPetEatItem) == "function") then return nil end
	local ok, yes = pcall(C.CanPetEatItem, id)
	if not ok or ns.Secret(yes) or type(yes) ~= "boolean" then return nil end
	return yes
end

--- Does your pet eat this item? The game's answer (CanPetEatItem) when it gives one, else its food type against the
--- diet. False with no pet out.
function PF.Eats(id)
	id = Num(id)
	local d = id and PF.Diet()
	if not d then return false end
	local yes = CanEat(id)
	if yes ~= nil then return yes end
	local ft = PF.FoodType(id)
	return ft ~= nil and d.types[ft] == true
end

--- Every Questie item with a food type that a vendor sells: { { id, ft, vendors } }, read once a session (nil without
--- QuestieDB).
function PF.Foods()
	if foods then return foods end
	local db = DB()
	if not db then return nil end
	local started = debugprofilestop and debugprofilestop()
	local ids = db.ItemIds and db.ItemIds() or {}
	local inst = C_Item and C_Item.GetItemInfoInstant or _G.GetItemInfoInstant
	local out = {}
	for i = 1, #ids do
		local id = ids[i]
		local class
		if inst then class = select(6, Safe(inst, id)) end
		if class == nil or PF.FOOD_CLASSES[class] then
			local ft = Num(Safe(db.QueryItemSingle, id, "foodType"))
			if ft and ft > 0 then
				foodType[id] = ft
				local v = Safe(db.QueryItemSingle, id, "vendors")
				if type(v) == "table" and #v > 0 then out[#out + 1] = { id = id, ft = ft, vendors = v } end
			end
		end
	end
	foods = out
	ns:Trace(("petfood: %d vendor foods read%s"):format(#out, started and (" in %.0f ms"):format(debugprofilestop() - started) or ""))
	return out
end
function PF.Forget() foods, foodType, vendorsOf, dietAt = nil, {}, {}, nil end -- (tests)

--- The vendors (NPC ids) selling food your pet eats: { [npc] = true }; {} with no pet out, nil without QuestieDB.
function PF.Vendors()
	local d = PF.Diet()
	if not d then return {} end
	local list = PF.Foods()
	if not list then return nil end
	if vendorsOf.key == d.key and vendorsOf.foods == list then return vendorsOf.set end
	local set = {}
	for _, f in ipairs(list) do
		if d.types[f.ft] or (d.unknown and CanEat(f.id)) then
			for _, npc in pairs(f.vendors) do if type(npc) == "number" then set[npc] = true end end
		end
	end
	vendorsOf = { key = d.key, foods = list, set = set }
	return set
end

----------------------------------------------------------------------
-- The questions
----------------------------------------------------------------------

local PET = { pet = true, pets = true }
local FOOD = { food = true, foods = true, eat = true, eats = true, feed = true, diet = true, eating = true }
local SELL = { sells = true, sell = true, sold = true, buy = true, vendor = true, vendors = true, merchant = true, merchants = true,
	seller = true, sellers = true, where = true }
local NEAR = { nearest = true, closest = true, nearby = true, near = true }
local FILL = { what = true, can = true, could = true, does = true, ["do"] = true, my = true, i = true, the = true, a = true,
	["for"] = true, to = true, who = true, ["in"] = true, me = true, will = true, is = true, are = true, which = true, of = true,
	any = true, some = true, show = true, list = true, hunter = true, hunters = true, your = true, get = true, items = true,
	item = true, bags = true, bag = true, have = true, carry = true, from = true }

--- The question: { what = "eat" (your bags' food it eats) | "sell" (vendors of it) }, or nil.
function PF.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local pet, food, sell = false, false, false
	for w in t:gmatch("%S+") do
		if PET[w] then pet = true
		elseif FOOD[w] then food = true
		elseif SELL[w] or NEAR[w] then sell = true
		elseif not FILL[w] then return nil end
	end
	if not (pet and food) then return nil end
	return { what = sell and "sell" or "eat" }
end

-- (search questions, docs/QUESTIONS.md 4.1: the line is the answer and its Alt+`)
function PF.Line(q)
	if q and q.what == "sell" then return "@npc sells:petfood faction:friendly sort:distance " end
	return "@item is:petfood "
end
function PF.Footer(q)
	local d = PF.Diet()
	if not d then return nil end
	if q and q.what == "sell" then return L["Vendors of your pet's food"] .. SEP .. table.concat(d.names, ", ") end
	return PF.DietText(d)
end
function PF.None(q)
	if not PF.Diet() then return { ns.NoteRow(L["Only for a hunter with a pet out: the game tells its diet then"]) } end
	if q and q.what == "sell" then
		if not DB() then return { ns.NoteRow(L["Needs Questie: it knows what vendors sell"]) } end
		return { ns.NoteRow(L["No friendly vendor Questie knows sells your pet's food"]) }
	end
	return { ns.NoteRow(L["Nothing in your bags your pet eats"]) }
end
