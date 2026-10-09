local ns = select(2, ...)

-- Filters typed into the search as key:value words, alongside the words matched by name. Each
-- works on the kinds that have what it looks at; a row it can't judge is left out. Unknown keys or
-- values stay ordinary search words. (".filters" lists them in the game.)
--
--   lvl:20-30 lvl:<30 lvl:40-    quest level, NPC level, the level an item needs
--   ilvl:60+                     item level
--   q:rare  q:rare+              item quality (poor common uncommon rare epic legendary, or 0-5)
--   stat:stamina  stat:sta>=10   an item stat, or what a consumable's effect gives (stamina, strength, agility, intellect, spirit,
--                                armor, attack power, spell power, crit, hit, dodge, mp5, fire...)
--   slot:wrist                   an item's equipment slot
--   type:mail  type:sword        item type or subtype
--   in:bank  in:deadmines        where: bags/bank/mail/guild (stored), a quest's or NPC's zone,
--                                a loot item's dungeon or boss (zone: and from: are the same)
--   on:plamen                    stored on that character (or guild, warband)
--   count:20+                    how many (bags, alts and banks)
--   trainer:mage trainer:class   Questie trainers by what they teach (a class, a profession, pet,
--                                riding; class = your class, mine = mining); is:classtrainer, is:proftrainer
--   faction:horde                Questie NPCs friendly to the Horde (alliance, neutral = both,
--                                friendly = to your own faction)
--   standing:honored+            reputations by standing (names or 1-8; <friendly, 4-6, honored-exalted)
--   sells:linen_cloth            Questie NPCs that sell an item (its name, part of it, or its id)
--   is:done is:todo is:complete  quests: finished / not yet / ready to turn in; achievements: done / todo
--   is:usable is:equippable      items you can use / wear
--   is:upgrade                   gear that suits you now: your level, your class, near what you wear there or better
--   is:quest is:soulbound is:boe items: quest items, bound ones, bind on equip not yet bound
--   is:ready is:passive          spells off cooldown (quests: = is:complete) / passive spells
--   is:capped                    currencies at their cap (or this week's)
--   is:craftable                 recipes you have every reagent for
--   is:skillup                   recipes that still give skill (orange or yellow; also is:orange/yellow/green/grey)
--   is:vendor is:trainer ...     Questie NPCs by what they do

local F = {}
ns.Filters = F

-- (private helpers the other files in this folder share; not for use outside it)
local P = {}
F._ = P

local Lower = ns.Lower

-- The filters are split over this folder, loaded in this order: Core (ranges, parsing, -x and a|b, the KEYS and IS
-- tables), Items (item info, stats, effect texts, slots, quality), Upgrades (is:upgrade), Others (levels, counts,
-- recipes, quests, spells, currencies, reputations; the values Tab offers and .filters' list), Npcs (NPC roles,
-- trainers, factions, distance, places, sells:). Each adds its keys and is: values to the tables below.

-- A cache of what was used lately (per item id, per text): the current table and the one before it. Once the current
-- one holds `cap` entries it becomes the one before and the older one goes; a value found in the one before is kept
-- again in the current one (it's still in use). So a search over somewhat more than `cap` items keeps them all: a wipe
-- at the cap emptied everything, and every keystroke asked for each of them again.
local function Generations(cap) return { new = {}, old = {}, n = 0, cap = cap } end
--- Keeps v for k in the current table (a full one becomes the one before first), and gives v back.
local function Keep(c, k, v)
	if c.n >= c.cap then c.old, c.new, c.n = c.new, {}, 0 end
	c.new[k], c.n = v, c.n + 1
	return v
end
--- What was kept for k, or nil. One found in the older table is kept again in the current one.
local function Kept(c, k)
	local v = c.new[k]
	if v ~= nil then return v end
	v = c.old[k]
	if v ~= nil then Keep(c, k, v) end
	return v
end
--- Forgets everything kept (F.ClearCache and the like).
local function Forget(c) c.new, c.old, c.n = {}, {}, 0 end
P.Generations, P.Keep, P.Kept, P.Forget = Generations, Keep, Kept, Forget
P.CACHE_MAX = 4000 -- (the item caches' and place texts' `cap`: at most twice that kept)

-- the NPC a row is (Questie's), and a field of it
local function NpcID(e) return e.kind == "npc" and (rawget(e, "key") or e.npcID) or nil end
local function NpcField(e, field)
	local id = NpcID(e)
	local I = ns.Integrations
	return id and I and I.NpcField and I.NpcField(id, field) or nil
end
P.NpcID, P.NpcField = NpcID, NpcField

--- A number range from "20", "20-30", "20-", "-30", "20+", "<30", "<=30", ">20", ">=20" ("30-20" is 20-30).
local function Range(v)
	local lo, hi
	local a, b = v:match("^(%d*)%-(%d*)$")
	if a then
		lo, hi = tonumber(a), tonumber(b)
		if not lo and not hi then return nil end
		if lo and hi and lo > hi then lo, hi = hi, lo end
	elseif v:match("^%d+%+$") then
		lo = tonumber(v:match("%d+"))
	elseif v:match("^<=?%d+$") then
		hi = tonumber(v:match("%d+")) - (v:find("=", 1, true) and 0 or 1)
	elseif v:match("^>=?%d+$") then
		lo = tonumber(v:match("%d+")) + (v:find("=", 1, true) and 0 or 1)
	elseif v:match("^=?%d+$") then
		lo = tonumber(v:match("%d+")); hi = lo
	else
		return nil
	end
	return function(x) return type(x) == "number" and (not lo or x >= lo) and (not hi or x <= hi) end
end
F.Range = Range

----------------------------------------------------------------------
-- Keys: key -> function(value) giving a test, or nil when the value isn't one this key takes
----------------------------------------------------------------------

local KEYS = {}

-- is:<value> -> its test (each file adds its own)
local IS = {}
P.KEYS, P.IS = KEYS, IS

KEYS.is = function(v)
	-- (worn item levels are read once per filter: a new one per search)
	if v == "upgrade" or v == "upgrades" then return F.GearFit() end
	return IS[v]
end

--- Is this a filter key (lvl, stat, is...)? For the prompt's colours.
function F.IsKey(key) return KEYS[Lower(key or "")] ~= nil end

-- the keys whose value is matched as text: a _ in it stands for a space (the search splits on spaces,
-- so "in:elwynn forest" can't reach us whole; stat words keep their _: attack_power is the game's key)
local SPACED = { ["in"] = true, zone = true, from = true, where = true, on = true, who = true, type = true,
	trainer = true, slot = true, sells = true, sold = true, standing = true, rep = true }

local traced -- a failing filter has been traced for this search (the parse of a search's words starts the next)

--- A filter for one typed word, or nil when it isn't one (then it's searched as text).
local function ParseOne(word)
	local key, value = word:match("^(%a+):(.+)$")
	if not key then return nil end
	key = Lower(key)
	local make = KEYS[key]
	if not make then return nil end
	value = Lower(value)
	if SPACED[key] then value = value:gsub("_", " ") end
	return make(value) or nil
end

--- Does the row have this (lowercase) text in its name or its searchable text? (-word, a|b words)
local function RowHas(e, lw)
	local ln = rawget(e, "_lname")
	if not ln then
		local n = e.name
		ln = type(n) == "string" and Lower(n) or ""
	end
	if ln:find(lw, 1, true) then return true end
	local lt = rawget(e, "_ltext")
	if not lt then
		local t = rawget(e, "text")
		lt = type(t) == "string" and Lower(t) or nil
	end
	return lt and lt:find(lw, 1, true) and true or false
end
F.RowHas = RowHas

--- A word's filter, or nil when it's a plain search word. key:value ("q:rare"), and ways to combine:
---   -key:value / !key:value / -word   not that ("-is:soulbound", "-cloth", "!q:poor")
---   key:a|b, key:a|key2:b, word|word  any of them ("q:rare|epic", "slot:head|chest", "sword|axe", "is:boe|q:epic")
---   a&b inside a | list               all of them ("q:rare&type:sword|q:epic&type:axe"; Simple's "rare sword or
---                                     epic axe" is made into rare&sword|epic&axe)
--- Each piece can carry its own - ("sword|-boe"). A bare piece takes the word's first key when that makes a filter
--- ("q:rare|epic" = q:rare or q:epic); else it's a plain word, which matches rows with it in their name or text, or,
--- with `plain`, what plain(word) gives (Simple mode's everyday words: "-junk" = not grey). A plain word alone
--- (no -, | or &) stays a search word: nil. A bad keyed piece makes the whole word a search word.
local function Piece(atom, key, plain)
	local neg = false
	if atom:find("^[-!]%a") then neg, atom = true, atom:sub(2) end
	local f
	if atom:find("^%a+:") then
		f = ParseOne(atom)
		if not f then return nil end
	else
		f = key and ParseOne(key .. ":" .. atom)
		if not f then -- (a plain word: "is:boe|cloak")
			local lw = Lower(atom)
			f = plain and plain(lw) or function(e) return RowHas(e, lw) end
		end
	end
	if neg then
		local g = f
		return function(e) return not g(e) end
	end
	return f
end

local function All(list)
	if #list == 1 then return list[1] end
	return function(e)
		for i = 1, #list do if not list[i](e) then return false end end
		return true
	end
end

local function Any(list)
	if #list == 1 then return list[1] end
	return function(e)
		for i = 1, #list do if list[i](e) then return true end end
		return false
	end
end

function F.Parse(word, plain)
	traced = false
	if type(word) ~= "string" or word == "" then return nil end
	local neg = false
	if word:find("^[-!]%a") then neg, word = true, word:sub(2) end
	local f
	if word:find("[|&]") then
		local key = word:match("^(%a+):")
		local ors = {}
		for part in (word .. "|"):gmatch("([^|]*)|") do
			local ands = {}
			for atom in (part .. "&"):gmatch("([^&]*)&") do
				if atom ~= "" then
					local pf = Piece(atom, key, plain)
					if not pf then return nil end -- (still being typed, or not a filter: a search word)
					ands[#ands + 1] = pf
				end
			end
			if #ands > 0 then ors[#ors + 1] = All(ands) end
		end
		if #ors == 0 then return nil end
		f = Any(ors)
	else
		f = ParseOne(word)
		if not f and neg and not word:find(":", 1, true) then f = Piece(word, nil, plain) end
	end
	if not f then return nil end
	if neg then
		local g = f
		return function(e) return not g(e) end
	end
	return f
end

--- Every filter passes this row. A filter that errors leaves the row out, and says so once per search
--- in .debug log (rows silently dropped looked like "the filter finds nothing").
function F.Pass(e, filters)
	for i = 1, #filters do
		local ok, yes = pcall(filters[i], e)
		if not ok then
			if not traced then
				traced = true
				ns:Trace("filter error: " .. tostring(yes) .. " (row " .. tostring(rawget(e, "name") or e.name) .. ")")
			end
			return false
		end
		if not yes then return false end
	end
	return true
end
