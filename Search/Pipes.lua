local ns = select(2, ...)
local L = ns.L

-- Chains: pass what one search found on through a relation, and on again.
--
--   thorium belt > mats                    the belt's reagents, with how many you have (and on alts)
--   thorium belt > mats thorium bar > sources   where to get one of them: crafted, sold, dropped, gathered...
--   copper bar > uses chain belt > mats    what Copper Bar goes into, narrowed to the Chain Belt, then its mats
--   @recipe is:craftable > mats > alts     every craftable recipe's reagents, then who holds them
--
-- In plain words (Simple mode, or any mode): "mats for thorium belt", "what uses copper bar", "where to get thorium
-- bar", "who sells mageweave", "what can i make with linen cloth". The footer shows the chain ("thorium belt > mats
-- > thorium bar > sources"). Enter on a row walks on (a reagent: where to get it; a recipe or crafted item: its
-- mats); Shift+Enter does what Enter does anywhere else (open the recipe, show the NPC on the map, the item in your
-- bags).
--
-- A link is a ">" standing on its own (spaces around it: lvl:>20 is a filter; ">>" sends to chat). The word after it
-- names the relation; the rest of that part narrows what it gave, by name. Recipes come from your own professions
-- and, for any crafted item, from AtlasLoot's crafting data; sellers, droppers and gathering spots from Questie.
-- (Revived from the shelved `pipes` branch, 0.36.0.)

local P = {}
ns.Pipes = P

P.MAX_LEFT = 50 -- rows passed on from one part to the next
P.MAX_OUT = 150 -- rows a relation gives at most
P.relations = {} -- name -> { definition, ... }
P.order = {}

function ns:RegisterRelation(name, def)
	def.name = name
	def.aliases = def.aliases or {}
	local list = P.relations[name]
	if not list then
		list = {}
		P.relations[name] = list
		P.order[#P.order + 1] = name
	end
	list[#list + 1] = def
end

-- how the footer says each one
P.LABELS = { mats = "mats", uses = "used in", sources = "sources", alts = "alts", learn = "learn", chain = "chain" }

--- Whether a relation can be used now: one of its definitions is (Attune's need Attune: `available`).
function P.Available(name)
	for _, def in ipairs(P.relations[name] or {}) do
		if not def.available or def.available() then return true end
	end
	return false
end

--- The relation's name for a typed word (its name or an alias), or nil.
function P.Find(word)
	if type(word) ~= "string" or word == "" then return nil end
	local w = ns.Lower(word)
	for _, name in ipairs(P.order) do
		if P.Available(name) then
			if w == name then return name end
			for _, def in ipairs(P.relations[name]) do
				for _, a in ipairs(def.aliases) do
					if w == a then return name end
				end
			end
		end
	end
end

--- The parts of a chained query, or nil when there's no link. Each part: { text }; every part after the first:
--- word (the relation as typed), rest (the words narrowing it).
function P.Split(text)
	if type(text) ~= "string" or not text:find(">", 1, true) then return nil end
	local parts, cur, any = {}, {}, false
	for word in text:gmatch("%S+") do
		if word == ">" then
			parts[#parts + 1] = table.concat(cur, " ")
			cur, any = {}, true
		else
			cur[#cur + 1] = word
		end
	end
	if not any then return nil end
	parts[#parts + 1] = table.concat(cur, " ")
	local stages = { { text = parts[1] } }
	for i = 2, #parts do
		local word, rest = parts[i]:match("^(%S*)%s*(.-)$")
		-- "used in" is two words
		if ns.Lower(word) == "used" and ns.Lower(rest):match("^in%f[%A]") then word, rest = "uses", rest:gsub("^%a+%s*", "") end
		stages[#stages + 1] = { text = parts[i], word = word, rest = rest }
	end
	return stages
end

-- plain words that mean a chain: { pattern (lowercase), relation }; the capture is what to start from
P.PHRASES = {
	{ "^mats? for (.+)$", "mats" }, { "^materials? for (.+)$", "mats" }, { "^reagents? for (.+)$", "mats" },
	{ "^mats (.+)$", "mats" }, { "^(.+) mats$", "mats" }, { "^(.+) reagents$", "mats" }, { "^(.+) materials$", "mats" },
	{ "^what do i need for (.+)$", "mats" }, { "^what does (.+) need$", "mats" }, { "^how do i make (.+)$", "mats" },
	{ "^how to make (.+)$", "mats" }, { "^how to craft (.+)$", "mats" },
	{ "^what uses (.+)$", "uses" }, { "^what can i make with (.+)$", "uses" }, { "^(.+) used in$", "uses" },
	{ "^uses? for (.+)$", "uses" }, { "^uses of (.+)$", "uses" }, { "^recipes with (.+)$", "uses" },
	{ "^what is (.+) used for$", "uses" }, { "^whats (.+) used for$", "uses" }, { "^what's (.+) used for$", "uses" },
	-- (before the sources: "where to get the recipe for x" is where to learn it)
	{ "^where to learn (.+)$", "learn" }, { "^where do i learn (.+)$", "learn" }, { "^where can i learn (.+)$", "learn" },
	{ "^how to learn (.+)$", "learn" }, { "^how do i learn (.+)$", "learn" }, { "^who teaches (.+)$", "learn" },
	{ "^where to train (.+)$", "learn" }, { "^where do i train (.+)$", "learn" }, { "^where can i train (.+)$", "learn" },
	{ "^who trains (.+)$", "learn" },
	{ "^where is (.+) taught$", "learn" }, { "^where to get the recipe for (.+)$", "learn" },
	{ "^where is the recipe for (.+)$", "learn" }, { "^recipe sources? for (.+)$", "learn" },
	{ "^where to get (.+)$", "sources" }, { "^where do i get (.+)$", "sources" }, { "^where can i get (.+)$", "sources" },
	{ "^where to buy (.+)$", "sources" }, { "^where can i buy (.+)$", "sources" }, { "^how to get (.+)$", "sources" },
	{ "^how do i get (.+)$", "sources" }, { "^sources? for (.+)$", "sources" }, { "^sources? of (.+)$", "sources" },
	{ "^where does (.+) drop$", "sources" }, { "^who sells (.+)$", "sources" }, { "^what drops (.+)$", "sources" },
	-- the quests before one (Rewards.lua, 0.49.16): "quest chain for the missing diplomat", "quest chain for outlaw sabre"
	{ "^quest chain for (.+)$", "chain" }, { "^quest chain of (.+)$", "chain" }, { "^chain for (.+)$", "chain" },
	{ "^quests? before (.+)$", "chain" }, { "^what leads to (.+)$", "chain" }, { "^prereqs? for (.+)$", "chain" },
	{ "^(.+) quest chain$", "chain" },
}

-- Simple mode's words for a one-link chain (it never shows ">"): what Enter writes and what the footer says
P.SIMPLE = { mats = "mats for %s", uses = "what uses %s", sources = "where to get %s", learn = "where to learn %s",
	chain = "quest chain for %s" }
P.SIMPLE_LABEL = { mats = L["Mats for %s"], uses = L["What uses %s"], sources = L["Where to get %s"], alts = L["%s on your alts"],
	learn = L["Where to learn %s"], chain = L["Quest chain for %s"], ["?"] = L["Which %s?"] }

local function SimpleOn() return ns.Easy and ns.Easy.On and ns.Easy.On() end

--- The line that asks for `rel` of `name`: Simple mode's words ("mats for Thorium Bar"), else the chain ("Thorium Bar >
--- mats").
function P.Phrase(name, rel)
	-- (the client's language's own words when translated: E.English reads them back)
	local f = SimpleOn() and ((ns.Easy.LocalPhrase and ns.Easy.LocalPhrase(rel)) or P.SIMPLE[rel])
	return f and f:format(name) or (name .. " > " .. rel)
end

--- The footer's trail in Simple mode's words ("core leather belt > mats" -> "Mats for core leather belt"); a trail of
--- more links, or one still being picked, as it is.
function P.SimpleLabel(trail)
	if type(trail) ~= "string" then return trail end
	local name, rel = trail:match("^([^>]-) > ([^>]-)$")
	local key = rel and (rel == "used in" and "uses" or rel)
	local f = key and P.SIMPLE_LABEL[key]
	return f and f:format(name) or trail
end

P.FIRST, P.LAST = {}, {}
for _, ph in ipairs(P.PHRASES) do
	local f = ph[1]:match("^%^(%a[%a']*)")
	if f then P.FIRST[f] = true end
	local l = ph[1]:match("(%a+)%$$")
	if l then P.LAST[l] = true end
end
P.FIRST.mat, P.FIRST.material, P.FIRST.reagent, P.FIRST.use, P.FIRST.source = true, true, true, true, true
P.FIRST.prereq = true -- ("^prereqs? for" starts with prereq too; review, 0.49.17)

--- The chain a line means: the line itself when it has links, the chain its plain words say ("mats for x" ->
--- "x > mats"), else nil. `words`: only the plain words (Simple mode: a ">" typed there is Advanced syntax, refused
--- like an @kind, 0.45.13).
function P.Canonical(text, words)
	if type(text) ~= "string" then return nil end
	if P.Split(text) then
		if words then return nil end
		-- (only a ">" standing alone, and not Advanced's other syntax using ">")
		return (text:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	-- (Advanced syntax isn't a phrase: @kind, key:value, | and > in filters; a ":" before a space is a name's own,
	-- "where to get Pattern: Linen Belt")
	if text:find("[@>|]") or text:find(":[^%s]") or text:find("^%s*[%./!%-]") then return nil end
	-- (cheap first: every phrase starts or ends with one of these words; this runs on every search)
	local first, last = text:match("^%s*(%S+)"), text:match("(%S+)%s*$")
	if not first or not (P.FIRST[first:lower()] or P.LAST[last:lower()]) then return nil end
	local lt = ns.Lower(text):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	for _, ph in ipairs(P.PHRASES) do
		local what = P.Available(ph[2]) and lt:match(ph[1])
		if what and what:find("%S") then
			what = what:gsub("^the ", ""):gsub("^a ", ""):gsub("^an ", "")
			if not P.NotAName(what) then return what .. " > " .. ph[2] end
		end
	end
	return nil
end

-- (0.49.2, review) what a phrase caught that names no item: your group ("what does my group need" is the group's
-- question, Group.lua), a way somewhere ("how do i get to orgrimmar"). They said "Nothing called 'my group'".
local GROUP_WORDS = { my = true, our = true, the = true, group = true, party = true, raid = true, members = true,
	member = true, groupmates = true, team = true }
function P.NotAName(what)
	if what == "to" or what:find("^to ") then return true end
	local group = false
	for w in what:gmatch("%S+") do
		if not GROUP_WORDS[w] then return false end
		if w ~= "my" and w ~= "our" and w ~= "the" then group = true end
	end
	return group
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local Safe = ns.Safe
-- lists a chain can start from that no search lists (What's Training's weapon skills you know: "daggers > learn"):
-- id -> function giving its rows
P.LISTS = {}
local function Entries(id)
	local p = ns.providers[id]
	if p then return ns:GetEntries(p) end
	local list = P.LISTS[id]
	return list and list() or {}
end
local function ItemOf(e)
	local F = ns.Filters
	local id = F and F.ItemOf and F.ItemOf(e) or e.itemID
	if not id and e.kind == "stored" then id = rawget(e, "key") end
	return type(id) == "number" and id or nil
end
P.ItemOf = ItemOf
local function ItemCount(id, bank)
	local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	if not f then return 0 end
	local ok, n = pcall(f, id, bank)
	return ok and type(n) == "number" and n or 0
end
P.ItemCount = ItemCount -- (bags; with `bank`, bank too: Plan.lua)
local function ItemName(id)
	local get = C_Item and C_Item.GetItemNameByID
	local name = get and Safe(get, id)
	if type(name) == "string" and name ~= "" and not (ns.Secret and ns.Secret(name)) then return name end
	local info = C_Item and C_Item.GetItemInfo and Safe(C_Item.GetItemInfo, id)
	if type(info) == "string" and info ~= "" then return info end
	if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	-- (not loaded yet: the search runs again in a moment, UI:RetryWhenLoaded, so the row isn't missing for good)
	if ns.Filters then ns.Filters.loading = true end
	P.loading = true
end
local function Icon(id)
	local get = C_Item and C_Item.GetItemIconByID or _G.GetItemIcon
	return get and Safe(get, id) or nil
end

-- AtlasLoot's crafting data: the spell that makes an item, and that spell's reagents (its data never changes: kept
-- per item, false for none)
local crafts, craftCount = {}, 0
local function AtlasCraft(itemID)
	local c = crafts[itemID]
	if c ~= nil then
		if c then return c[1], c[2] end
		return nil
	end
	local AL = _G.AtlasLoot
	local Pr = AL and AL.Data and AL.Data.Profession
	if not (Pr and Pr.GetCraftSpellForCreatedItem and Pr.GetProfessionData) then return nil end -- (not loaded: not kept)
	local out, spell
	local ok, sp = pcall(Pr.GetCraftSpellForCreatedItem, itemID)
	if ok and sp then
		local ok2, data = pcall(Pr.GetProfessionData, sp)
		if ok2 and type(data) == "table" and type(data[6]) == "table" then
			out = {}
			for i, rid in ipairs(data[6]) do
				if type(rid) == "number" then out[#out + 1] = { rid, type(data[7]) == "table" and data[7][i] or 1 } end
			end
			if #out == 0 then out = nil else spell = sp end
		end
	end
	if craftCount > 20000 then crafts, craftCount = {}, 0 end
	crafts[itemID], craftCount = out and { out, spell } or false, craftCount + 1
	return out, spell
end
P.ClearCrafts = function() crafts, craftCount = {}, 0 end -- (tests)

-- the loot rows by item, and the crafted ones (AtlasLoot's crafting pages), made once per loot list
local lootBy, lootCrafted, lootFrom
local function LootIndex()
	local list = (ns.providers.loot and ns:GetEntries(ns.providers.loot)) or {}
	if lootFrom ~= list then
		lootBy, lootCrafted, lootFrom = {}, {}, list
		for _, l in ipairs(list) do
			local id = l.itemID
			if id then
				local t = lootBy[id]
				if not t then t = {}; lootBy[id] = t end
				t[#t + 1] = l
				if #t == 1 and AtlasCraft(id) then lootCrafted[#lootCrafted + 1] = l end
			end
		end
	end
	return lootBy, lootCrafted
end
P.AtlasCraft = AtlasCraft
--- AtlasLoot's loot rows of an item (its bosses), or {}.
function P.LootRowsOf(id) return (LootIndex())[id] or {} end

-- your own recipes, by the item they make
local ownBy, ownFrom
local function OwnRecipes()
	local list = Entries("recipes")
	if ownFrom ~= list then
		ownBy, ownFrom = {}, list
		for _, r in ipairs(list) do
			local id = type(r.reagents) == "table" and #r.reagents > 0 and ItemOf(r)
			if id and not ownBy[id] then ownBy[id] = r end
		end
	end
	return ownBy
end

--- A row's reagents ({ { itemID, count }... }): a recipe's own, else your recipe for the item, else AtlasLoot's.
function P.Reagents(e)
	if type(e.reagents) == "table" and #e.reagents > 0 then return e.reagents end
	local id = ItemOf(e)
	if not id then return nil end
	local own = OwnRecipes()[id]
	if own then return own.reagents end
	return (AtlasCraft(id))
end

local function StoredByID()
	local by = {}
	for _, e in ipairs(Entries("stored")) do
		local id = e.itemID or rawget(e, "key")
		if id then by[id] = e end
	end
	return by
end

P.StoredByID = StoredByID -- (@stored's rows by item: what your alts hold, Plan.lua)

local REAGENT_LABEL = "|cffd9b26a" .. L["Reagent"] .. "|r"
local SOURCE_LABEL = "|cffd9b26a" .. L["Source"] .. "|r"
local function ShowItem(e)
	if not (ns.Bags and ns.Bags.ShowItem(e.itemID, e.link, e.name)) then ns:Print(L["You don't carry %s."]:format(tostring(e.name))) end
end

----------------------------------------------------------------------
-- Relations
----------------------------------------------------------------------

-- mats: the reagents (several rows: what they need together)
ns:RegisterRelation("mats", {
	aliases = { "reagents", "reagent", "materials", "mat" },
	desc = L["its reagents, with how many you have"],
	applies = function(e) return P.Reagents(e) ~= nil end,
	run = function(rows)
		local need, order = {}, {}
		for _, e in ipairs(rows) do
			for _, rg in ipairs(P.Reagents(e) or {}) do
				local id = rg[1]
				if type(id) == "number" then
					if not need[id] then order[#order + 1] = id end
					need[id] = (need[id] or 0) + (tonumber(rg[2]) or 1)
				end
			end
		end
		local stored = #order > 0 and StoredByID() or {}
		local out = {}
		for i, id in ipairs(order) do
			local name = ItemName(id)
			if name then
				local bags, all = ItemCount(id), ItemCount(id, true)
				local st = stored[id]
				local elsewhere = st and math.max(0, (st.total or 0) - all) or 0
				local n = need[id]
				local parts = { L["need %d"]:format(n), L["have %d"]:format(bags) }
				if all > bags then parts[#parts] = parts[#parts] .. " " .. L["(+%d bank)"]:format(all - bags) end
				if elsewhere > 0 then parts[#parts + 1] = L["%d on alts"]:format(elsewhere) end
				local q = C_Item and C_Item.GetItemQualityByID and Safe(C_Item.GetItemQualityByID, id)
				out[#out + 1] = {
					key = id, kind = "reagent", kindLabel = REAGENT_LABEL, freqKey = "reagent:" .. id,
					name = name, itemID = id, link = "item:" .. id, icon = Icon(id),
					color = ns.QualityHex and ns.QualityHex(q) or nil,
					detail = table.concat(parts, ns.DETAIL_SEP), need = n, count = bags, total = all + elsewhere,
					-- short on this character first (what to go and get), then in the recipe's order
					_order = ((all >= n) and 1000 or 0) + i,
					activate = ShowItem,
				}
			end
		end
		table.sort(out, function(a, b) return a._order < b._order end)
		return out
	end,
})

-- uses: what an item goes into (your recipes, and every crafted item AtlasLoot knows)
ns:RegisterRelation("uses", {
	aliases = { "usedin", "recipes", "crafts", "makes" },
	desc = L["what it goes into"],
	applies = function(e) return ItemOf(e) ~= nil end,
	run = function(rows)
		local ids = {}
		for _, e in ipairs(rows) do ids[ItemOf(e)] = true end
		local out, made = {}, {}
		local function Takes(reagents)
			for _, rg in ipairs(reagents or {}) do if ids[rg[1]] then return true end end
			return false
		end
		for _, r in ipairs(Entries("recipes")) do
			if Takes(r.reagents) then
				out[#out + 1] = r
				local m = ItemOf(r)
				if m then made[m] = true end
			end
		end
		-- (AtlasLoot's crafted items: its crafting pages are among the loot rows, as the items they make)
		local _, crafted = LootIndex()
		for _, l in ipairs(crafted) do
			if #out >= P.MAX_OUT then break end
			local id = l.itemID
			if not made[id] and Takes(AtlasCraft(id)) then
				made[id] = true
				out[#out + 1] = l
			end
		end
		return out
	end,
})

-- (`how`: what the row is to the item, said when it's sent to chat: "sold by", "dropped by"...)
local function View(e, detail, label, how)
	return setmetatable({ detail = detail, kindLabel = label or nil, pipeHow = how }, { __index = e })
end
P.View = View

-- a view of an NPC or spot with how far it is said first, as "nearest" says it ("80 yd  Sells it  ·  Vendor"): the
-- selected row's arrow sits just left of the distance, and keeps it up to date as you walk (`_dist`, `nearRest`:
-- List.lua's NavTick); no known spot on your continent: just what it is (0.45.17, the player's screenshot: the arrow
-- sat mid-row, the distance cut off at the end)
local function NearSaid(v, d, rest)
	if d then
		v.detail, v._dist, v.nearRest = ns.NearDetail(d, rest), d, rest
	else
		v.detail = rest
	end
	return v
end
P.NearSaid = NearSaid

--- Is this Questie NPC friendly to you (as faction:friendly judges it: "A", "H" or "AH" holding your side; one hostile
--- to both, or not known, isn't)? Sellers are only the ones you can buy from (0.45.16, the player's ask).
local friendlyTest
function P.Friendly(row)
	local F = ns.Filters
	if friendlyTest == nil then friendlyTest = (F and F.Parse and F.Parse("faction:friendly")) or false end
	if not friendlyTest then return true end -- (no filters: nothing to judge by)
	return Safe(friendlyTest, row) == true
end

-- nearer first; one with no known spot on your continent after, in Questie's order
local function NearFirst(a, b)
	if (a.d ~= nil) ~= (b.d ~= nil) then return a.d ~= nil end
	if a.d and b.d and a.d ~= b.d then return a.d < b.d end
	return a.i < b.i
end
P.NPCS_LOOKED = 400 -- (the NPCs of one list looked at for their distance: a world drop names hundreds)

-- an item's NPCs Questie lists in `field` (vendors, npcDrops), the nearest `max`, as views saying what they are to it
-- and how far ("  ·  120 yd"); `friendly`: only those friendly to you (sellers)
local function AddNpcs(out, I, id, field, what, max, how, friendly)
	local list = I.ItemField(id, field)
	if type(list) ~= "table" then return end
	local here = I.Here and I.Here() or nil
	local got = {}
	for k, nid in ipairs(list) do
		if k > P.NPCS_LOOKED then break end
		local row = type(nid) == "number" and I.NpcRow and I.NpcRow(nid)
		if row and (not friendly or P.Friendly(row)) then
			local d = here and I.NpcDistance and I.NpcDistance(nid, here) or nil
			got[#got + 1] = { row = row, d = d, i = k }
		end
	end
	table.sort(got, NearFirst)
	for k = 1, math.min(#got, max) do
		local g = got[k]
		local rest = what .. ((g.row.detail and g.row.detail ~= "") and (ns.DETAIL_SEP .. tostring(g.row.detail)) or "")
		out[#out + 1] = NearSaid(View(g.row, rest, nil, how), g.d, rest)
	end
end

-- a vein or chest with no known spot: said so (the row is still one to send: "gathered from Copper Vein")
local function NoSpot(e) ns:Print(L["No known spot for %s."]:format(tostring(e.name))) end

-- the objects an item is gathered or found from, one row per name, at the spawn nearest you (QuestieDB's objects): a
-- spot row like a mailbox's, Enter shows it on the map, Shift+Enter pins it, >> sends it with a map pin
local function AddObjects(out, I, objs, what, how)
	local byName, order = {}, {}
	for _, oid in ipairs(objs) do
		local oname = type(oid) == "number" and I.ObjectName(oid)
		if oname then
			if not byName[oname] then byName[oname] = {}; order[#order + 1] = oname end
			local ids = byName[oname]
			ids[#ids + 1] = oid
		end
	end
	local here = #order > 0 and I.Here and I.Here() or nil
	local made = {}
	for k, oname in ipairs(order) do
		local row = { key = "obj:" .. oname, kind = "source", kindLabel = SOURCE_LABEL, name = oname, pipeHow = how or L["gathered from"],
			icon = "Interface\\Icons\\INV_Ore_Copper_01", detail = what or L["Gathered or found here"], activate = NoSpot, found = true }
		local spot = I.NearestSpawn and I.NearestSpawn(byName[oname], here)
		if spot and ns.Maps then
			row.ui, row.mapID, row.px, row.py, row.zone = spot.ui, spot.ui, spot.px, spot.py, spot.zone
			row.wcont, row.wx, row.wy = spot.wcont, spot.wx, spot.wy
			NearSaid(row, spot.d, row.detail .. (spot.zone and (ns.DETAIL_SEP .. tostring(spot.zone)) or ""))
			row.secure, row.isOpen, row.after = ns.Maps.SECURE, ns.Maps.IsOpenFor, I.SpotAfter
			row.activate, row.secondary = I.PinObject, I.PinObject
		end
		made[#made + 1] = { row = row, d = spot and spot.d or nil, i = k }
	end
	table.sort(made, NearFirst) -- (nearest first, as the sellers and droppers)
	for _, m in ipairs(made) do out[#out + 1] = m.row end
end

-- what each kind of source is to the thing looked for, in the list and in chat ("Sells it" / "sold by"): an item's
-- own, or (where to learn a recipe) its recipe item's
P.ITEM_WORDS = { sells = L["Sells it"], sold = L["sold by"], drops = L["Drops it"], dropped = L["dropped by"],
	found = L["Gathered or found here"], gathered = L["gathered from"], quest = L["A quest's reward"], reward = L["a reward from"] }
P.RECIPE_WORDS = { sells = L["Sells the recipe"], sold = L["the recipe is sold by"], drops = L["Drops the recipe"],
	dropped = L["the recipe drops from"], found = L["The recipe is found here"], gathered = L["the recipe is found in"],
	quest = L["The recipe is a quest's reward"], reward = L["the recipe is a reward from"] }

-- an item's sellers and droppers, the veins/herbs/chests it's found in (by name, once each, at the spot nearest you)
-- and the quests rewarding it, from Questie, said in `w`'s words
local function AddQuestie(out, I, id, w)
	AddNpcs(out, I, id, "vendors", w.sells, 15, w.sold, true) -- (only those who'd sell to you)
	AddNpcs(out, I, id, "npcDrops", w.drops, 15, w.dropped)
	local objs = I.ItemField(id, "objectDrops")
	if type(objs) == "table" and I.ObjectName then AddObjects(out, I, objs, w.found, w.gathered) end
	local quests = I.ItemField(id, "questRewards")
	if type(quests) == "table" and I.QuestRow then
		for _, qid in ipairs(quests) do
			local q = type(qid) == "number" and I.QuestRow(qid)
			if q then out[#out + 1] = View(q, w.quest .. ns.DETAIL_SEP .. tostring(q.detail or ""), nil, w.reward) end
		end
	end
end

-- sources: where to get an item (crafted, sold, dropped, gathered, a quest's reward, AtlasLoot's bosses, your alts)
ns:RegisterRelation("sources", {
	aliases = { "source", "get", "where", "from" },
	desc = L["where to get it"],
	applies = function(e) return ItemOf(e) ~= nil end,
	run = function(rows)
		local I = ns.Integrations
		local out = {}
		local stored = StoredByID()
		for _, e in ipairs(rows) do
			local id = ItemOf(e)
			local name = ItemName(id) or e.name
			-- crafted: your recipe for it, else AtlasLoot's (its mats are one step on)
			local own = OwnRecipes()[id]
			if own then
				out[#out + 1] = View(own, L["Crafted"] .. ns.DETAIL_SEP .. L["your recipe"] .. (own.detail and (ns.DETAIL_SEP .. own.detail) or ""), SOURCE_LABEL, L["crafted:"])
			else
				local rg, spell = AtlasCraft(id)
				if rg then
					local sname = spell and C_Spell and C_Spell.GetSpellName and Safe(C_Spell.GetSpellName, spell)
					out[#out + 1] = {
						key = "craft:" .. id, kind = "source", kindLabel = SOURCE_LABEL, name = name, itemID = id,
						link = "item:" .. id, icon = Icon(id), reagents = rg,
						detail = L["Crafted"] .. (sname and (ns.DETAIL_SEP .. sname) or "") .. ns.DETAIL_SEP .. L["(a recipe you don't have)"], pipeHow = L["crafted:"],
						activate = ShowItem,
					}
				end
			end
			if I and I.ItemField then AddQuestie(out, I, id, P.ITEM_WORDS) end
			-- AtlasLoot's bosses
			if not AtlasCraft(id) then
				local by = LootIndex()
				for k, l in ipairs(by[id] or {}) do
					if k > 15 then break end
					out[#out + 1] = l
				end
			end
			if stored[id] then out[#out + 1] = View(stored[id], L["On your alts"] .. ns.DETAIL_SEP .. tostring(stored[id].detail or "")) end
		end
		return out
	end,
})

----------------------------------------------------------------------
-- learn: where a recipe is learned (0.45.12, the player's ask). The game doesn't say: this client's profession window
-- lists recipes you don't know, but C_TradeSkillUI.GetRecipeSourceText gives nothing for them (the player's probe).
-- So: AtlasLoot's recipe items (its Data.Recipe: [Plans: Thorium Belt] teaches the spell; GetRecipeForSpell is the
-- reverse) and where to get that item (Questie, AtlasLoot's bosses, your alts); a craft AtlasLoot knows with no recipe
-- item is taught by a trainer, said with that evidence, and the nearest trainers of its profession Questie knows (a
-- trainer whose rank tops out below the skill the recipe needs left out).
----------------------------------------------------------------------

-- AtlasLoot's profession numbers: the word trainer: takes, the skill line
P.AL_PROFS = {
	[1] = { "firstaid", 129, "First Aid" }, [2] = { "blacksmithing", 164, "Blacksmithing" },
	[3] = { "leatherworking", 165, "Leatherworking" }, [4] = { "alchemy", 171, "Alchemy" }, [5] = { "herbalism", 182, "Herbalism" },
	[6] = { "cooking", 185, "Cooking" }, [7] = { "mining", 186, "Mining" }, [8] = { "tailoring", 197, "Tailoring" },
	[9] = { "engineering", 202, "Engineering" }, [10] = { "enchanting", 333, "Enchanting" }, [11] = { "fishing", 356, "Fishing" },
	[12] = { "skinning", 393, "Skinning" }, [14] = { "jewelcrafting", 755, "Jewelcrafting" }, [15] = { "inscription", 773, "Inscription" },
}
-- the highest skill a trainer of each rank teaches (classic's ranks; a title with none of these: kept)
P.RANK_CAP = { { "grand master", 450 }, { "master", 375 }, { "artisan", 300 }, { "expert", 225 }, { "journeyman", 150 },
	{ "apprentice", 75 } }
P.TRAINERS = 5 -- (the nearest ones listed)

local function AtlasRecipes()
	local AL = _G.AtlasLoot
	local D = AL and AL.Data
	return D and D.Recipe, D and D.Profession
end

--- The craft a row stands for: its spell, the item it makes, the recipe item (when the row is one); nil when neither
--- your recipes nor AtlasLoot say.
function P.LearnOf(e)
	local id = ItemOf(e)
	-- (a recipe you know, or one you don't yet: MissingRecipes.lua)
	if (e.kind == "recipes" or e.kind == "missing") and type(e.recipeID) == "number" then return e.recipeID, id, e.recipeItem end
	if not id then return nil end
	local Rc = AtlasRecipes()
	if Rc and Rc.IsRecipe and Safe(Rc.IsRecipe, id) then
		local d = Safe(Rc.GetRecipeData, id)
		if type(d) == "table" and type(d[3]) == "number" and d[3] ~= 0 then return d[3], nil, id end
	end
	local own = OwnRecipes()[id]
	if own and type(own.recipeID) == "number" then return own.recipeID, id end
	local _, spell = AtlasCraft(id)
	if spell then return spell, id end
	return nil
end

-- a profession's name in the game's words (the English one when the client doesn't say)
local function ProfName(prof)
	local f = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
	local n = f and Safe(f, prof[2])
	if type(n) == "string" and n ~= "" and not (ns.Secret and ns.Secret(n)) then return n end
	return prof[3]
end

--- AtlasLoot's profession entry (P.AL_PROFS) for a skill line, or for a profession's name (the game's or English).
function P.ProfOfLine(line)
	if type(line) ~= "number" then return nil end
	for _, pr in pairs(P.AL_PROFS) do if pr[2] == line then return pr end end
end
function P.ProfOfName(name)
	if type(name) ~= "string" then return nil end
	local ln = ns.Lower(name)
	for _, pr in pairs(P.AL_PROFS) do
		if ns.Lower(pr[3]) == ln or ns.Lower(ProfName(pr)) == ln then return pr end
	end
end

local function RankCap(title)
	for _, r in ipairs(P.RANK_CAP) do if title:find(r[1], 1, true) then return r[2] end end
end

-- the NPC list's trainers of a profession friendly to you, made once per list
local trainersOf = { list = nil, by = {} }
local function Trainers(word)
	local p, F = ns.providers.npc, ns.Filters
	if not (p and F and F.Parse) then return {} end
	local list = ns:GetEntries(p)
	local busy = p.busy and p.busy()
	if busy then P.loading = true; F.loading = true end -- (Questie's NPCs still being read: asked again once they're in)
	if trainersOf.list ~= list then trainersOf.list, trainersOf.by = list, {} end
	local got = trainersOf.by[word]
	if got then return got end
	got = {}
	local isTrainer, friendly = F.Parse("trainer:" .. word), F.Parse("faction:friendly")
	if isTrainer then
		for _, e in ipairs(list) do
			if Safe(isTrainer, e) and (not friendly or Safe(friendly, e)) then got[#got + 1] = e end
		end
	end
	if not busy and #list > 0 then trainersOf.by[word] = got end
	return got
end
P.Trainers = Trainers -- (What's Training's spells: trainer:class, trainer:pet; Search/WhatsTraining.lua)
P.ForgetTrainers = function() trainersOf.list, trainersOf.by = nil, {} end -- (tests)

-- the nearest trainers who teach up to `need`, as rows saying so
local function AddTrainers(out, prof, need)
	local I = ns.Integrations
	local here = I and I.Here and I.Here() or nil
	local list = {}
	for _, e in ipairs(Trainers(prof[1])) do
		local id = e.npcID or rawget(e, "key")
		local title = rawget(e, "sub") or (I and I.NpcField and I.NpcField(id, "subName")) or ""
		local cap = type(title) == "string" and RankCap(ns.Lower(title)) or nil
		if not (cap and need and cap < need) then
			local d = here and I.NpcDistance and I.NpcDistance(id, here) or nil
			list[#list + 1] = { e = e, d = d, title = title }
		end
	end
	table.sort(list, function(a, b)
		if (a.d ~= nil) ~= (b.d ~= nil) then return a.d ~= nil end
		if a.d and b.d and a.d ~= b.d then return a.d < b.d end
		return tostring(a.e.name) < tostring(b.e.name)
	end)
	for i = 1, math.min(#list, P.TRAINERS) do
		local t = list[i]
		local rest = L["Teaches it"] .. (t.title ~= "" and (ns.DETAIL_SEP .. t.title) or "")
		out[#out + 1] = NearSaid(View(t.e, rest, nil, L["taught by"]), t.d, rest)
	end
end

-- the recipe item: where to get it (Questie, AtlasLoot's bosses, your alts)
local function AddRecipeItem(out, rid, prof, need, stored)
	local skill = prof and need and (ns.DETAIL_SEP .. ProfName(prof) .. " " .. need) or ""
	out[#out + 1] = { key = "recipe:" .. rid, kind = "source", kindLabel = SOURCE_LABEL, name = ItemName(rid) or L["item %d"]:format(rid),
		itemID = rid, link = "item:" .. rid, icon = Icon(rid), detail = L["Teaches it"] .. skill, pipeHow = L["taught by"],
		activate = ShowItem }
	local I = ns.Integrations
	local from = #out + 1
	if I and I.ItemField then AddQuestie(out, I, rid, P.RECIPE_WORDS) end
	-- (a vendor's window showed it in limited supply there, or always in stock: MissingRecipes.lua keeps what it saw)
	local MR = ns.MissingRecipes
	for k = from, #out do
		local v = out[k]
		local nid = v.pipeHow == P.RECIPE_WORDS.sold and (v.npcID or rawget(v, "key") or v.key)
		local lim = nid and MR and MR.Limited(rid, nid)
		if lim ~= nil then
			local say = ns.DETAIL_SEP .. (lim and L["limited supply"] or L["always in stock"])
			rawset(v, "detail", v.detail .. say)
			if rawget(v, "nearRest") then rawset(v, "nearRest", v.nearRest .. say) end -- (kept when the distance updates)
		end
	end
	local by = LootIndex()
	for k, l in ipairs(by[rid] or {}) do
		if k > 15 then break end
		out[#out + 1] = l
	end
	if stored[rid] then out[#out + 1] = View(stored[rid], L["Your alts hold the recipe"] .. ns.DETAIL_SEP .. tostring(stored[rid].detail or "")) end
end

ns:RegisterRelation("learn", {
	aliases = { "learned", "taught", "teach", "teaches", "trainer", "trainers", "recipesource" },
	desc = L["where to learn the recipe: its recipe item, or a trainer"],
	applies = function(e) return P.LearnOf(e) ~= nil end,
	run = function(rows)
		local _, Pr = AtlasRecipes()
		local Rc = AtlasRecipes()
		local stored = StoredByID()
		local out = {}
		for _, e in ipairs(rows) do
			local spell, made, rid = P.LearnOf(e)
			local data = Pr and Pr.GetProfessionData and Safe(Pr.GetProfessionData, spell)
			data = type(data) == "table" and data or nil
			local prof = data and P.AL_PROFS[data[2]] or nil
			local need = data and tonumber(data[3]) or nil
			made = made or (data and data[1]) or nil
			-- you know it already: said first
			local own = (e.kind == "recipes" and e) or (made and OwnRecipes()[made]) or nil
			if own then out[#out + 1] = View(own, L["You know it"] .. (own.detail and (ns.DETAIL_SEP .. own.detail) or "")) end
			rid = rid or (Rc and Rc.GetRecipeForSpell and Safe(Rc.GetRecipeForSpell, spell)) or nil
			if type(rid) == "number" then
				AddRecipeItem(out, rid, prof, need, stored)
			else
				-- AtlasLoot knows the craft but no recipe item for it, or a trainer's window listed it: a trainer
				-- teaches it (what it costs, when a trainer's window showed it: MissingRecipes.lua)
				local MR = ns.MissingRecipes
				local sname = (e.kind == "recipes" or e.kind == "missing") and e.name
					or (C_Spell and C_Spell.GetSpellName and Safe(C_Spell.GetSpellName, spell)) or e.name
				local seen = MR and MR.TrainerFor(sname)
				if data or seen then
					prof = prof or P.ProfOfLine(e.profLine) or (seen and P.ProfOfName(seen.skill)) or nil
					need = need or (seen and seen.rank) or nil
					local pname = prof and ProfName(prof) or nil
					local why = (seen and seen.cost) and (L["costs %s"]:format(ns.Money(seen.cost))
						.. (seen.who and (" " .. L["(seen at %s)"]:format(seen.who)) or "")) or L["No recipe item teaches it (AtlasLoot)"]
					out[#out + 1] = { key = "trainer:" .. spell, kind = "source", kindLabel = SOURCE_LABEL, noActivate = true,
						name = pname and L["Taught by a %s trainer"]:format(pname) or L["Taught by a trainer"],
						icon = "Interface\\Icons\\INV_Misc_Book_11",
						detail = why .. (pname and need and (ns.DETAIL_SEP .. L["learn at %s %s"]:format(pname, need)) or "") }
					if prof then AddTrainers(out, prof, need) end
				end
			end
		end
		return out
	end,
})

-- alts: who holds an item on your alts, in banks, the mail...
ns:RegisterRelation("alts", {
	aliases = { "stored", "who", "bank", "holders" },
	desc = L["who holds it on your alts and banks"],
	applies = function(e) return ItemOf(e) ~= nil and e.kind ~= "stored" end,
	run = function(rows)
		local by = StoredByID()
		local out = {}
		for _, e in ipairs(rows) do
			local s = by[ItemOf(e)]
			if s then out[#out + 1] = s end
		end
		return out
	end,
})

----------------------------------------------------------------------
-- Running a chain
----------------------------------------------------------------------

local function Id(e)
	local k = rawget(e, "key")
	if k == nil then
		-- (a view, View's or NearSaid's: the row it shows and how it was found; review, 0.48.6: each view was its own, so
		-- a trade supplier selling three of the reagents was listed three times, and passed on three times)
		local mt = getmetatable(e)
		local base = mt and type(mt.__index) == "table" and mt.__index or nil
		k = base and rawget(base, "key")
		if k == nil then return e end
		return tostring(base.kind) .. ":" .. tostring(k) .. "|" .. tostring(rawget(e, "pipeHow") or "")
	end
	return tostring(e.kind) .. ":" .. tostring(k)
end
P.Id = Id -- (tests)

--- The rows a relation gives for these, each once.
function P.Run(name, rows)
	local out, seen = {}, {}
	for _, def in ipairs(P.relations[name] or {}) do
		local mine = {}
		for _, e in ipairs(rows) do
			if def.applies(e) then mine[#mine + 1] = e end
		end
		if #mine > 0 then
			local ok, res = pcall(def.run, mine)
			if not ok then
				ns:Trace("chain " .. name .. " failed: " .. tostring(res))
			elseif type(res) == "table" then
				for _, r in ipairs(res) do
					local id = Id(r)
					if type(r.name) == "string" and r.name ~= "" and not seen[id] then
						seen[id] = true
						out[#out + 1] = r
						if #out >= P.MAX_OUT then break end
					end
				end
			end
		end
	end
	return out
end

--- The relations some of these rows can go through: { name, desc }.
function P.Applicable(rows)
	local out = {}
	for _, name in ipairs(P.order) do
		local desc
		for _, def in ipairs(P.Available(name) and P.relations[name] or {}) do
			for _, e in ipairs(rows) do
				if def.applies(e) then desc = def.desc break end
			end
			if desc then break end
		end
		if desc then out[#out + 1] = { name, desc } end
	end
	return out
end

local function Tokens(text)
	local t = {}
	for w in ns.Lower(text or ""):gmatch("%S+") do t[#t + 1] = w end
	return t
end

-- a row's name score for every word (nil: some word doesn't match), its lowercase name, and whether every word is in
-- it as typed (not only its letters scattered: "core" is in "Comfortable", c-o-r-e)
local function NameScore(e, tokens)
	local ln = rawget(e, "_lname") or (type(e.name) == "string" and ns.Lower(e.name)) or ""
	local sum, whole = 0, true
	for _, tk in ipairs(tokens) do
		local s, sub = ns.Fuzzy.score(tk, ln, ln)
		if not s then return nil end
		sum = sum + s
		-- (an apostrophe left out still counts: "agamaggans clutch")
		if not sub and tk:find("'", 1, true) == nil and ln:find("'", 1, true) then
			sub = ln:gsub("'", ""):find(tk, 1, true) ~= nil
		end
		whole = whole and (sub and true or false)
	end
	return sum, ln, whole
end

-- (the recipes you don't know last: "where to learn anvil", a recipe AtlasLoot doesn't list)
P.SEED_KINDS = { "recipes", "items", "loot", "stored", "missing" }

P.CHOICES = 8 -- (names offered when the words fit several)

-- The last seed's look, for the next keystroke: { gen, kinds, tokens, cands = the rows whose names had every word,
-- filters aside, in order }. One more letter or word only narrows those (a name with the new words had the old ones),
-- so while the same lists stand (none rebuilt since) the next look goes over them alone.
local lastSeed

-- one more letter on the last word, or one more word
local function Grew(last, tokens)
	local n, ln = #tokens, #last
	if ln == 0 or (n ~= ln and n ~= ln + 1) then return false end
	for i = 1, ln do
		local a, b = last[i], tokens[i]
		if (i < n and a ~= b) or (i == n and b:sub(1, #a) ~= a) then return false end
	end
	return true
end

-- the last look's rows when they can stand for these lists and words; nil: look at every row
local function SeedFrom(kinds, tokens)
	local last = lastSeed
	if not (last and last.gen == ns.entriesGen and #last.kinds == #kinds and Grew(last.tokens, tokens)) then return nil end
	for k, kind in ipairs(kinds) do
		if last.kinds[k] ~= kind then return nil end
		local p = ns.providers[kind]
		if p and (p._dirty or not p._entries) then return nil end -- (to be collected again: its rows may change)
	end
	for _, kind in ipairs(kinds) do Entries(kind) end -- (read as the whole look reads them: nothing to collect)
	if last.gen ~= ns.entriesGen then return nil end -- (reading one rebuilt it: a list made from another)
	return last.cands
end

-- The typed words: the lists an @kind picks (else P.SEED_KINDS), the key:value filters, and the name's words
-- (lowercase), alone and joined.
local function SeedParse(text, seedKinds, alsoKinds)
	local kinds, filters, words = {}, {}, {}
	for w in (text or ""):gmatch("%S+") do
		if w:sub(1, 1) == "@" and #w > 1 then
			-- (as the search reads an @kind: its id, an alias or the start of its id)
			local p = ns:ResolveProvider(w:sub(2))
			if p then kinds[#kinds + 1] = p.id else words[#words + 1] = w end
		else
			local f = (w:find("[:|]") or w:find("^[-!][%a\128-\255]")) and ns.Filters and ns.Filters.Parse(w) -- ("-малое", 0.49.2)
			if f then filters[#filters + 1] = f else words[#words + 1] = w end
		end
	end
	if #kinds == 0 then
		kinds = seedKinds or P.SEED_KINDS
		if alsoKinds then
			local all = {}
			for _, k in ipairs(kinds) do all[#all + 1] = k end
			for _, k in ipairs(alsoKinds) do all[#all + 1] = k end
			kinds = all
		end
	end
	local tokens = Tokens(table.concat(words, " "))
	local whole = table.concat(tokens, " ")
	return kinds, filters, tokens, whole
end

-- a name's words without a leading article ("the black book" -> "black book"): the plain words drop it ("mats for the
-- black book" asks for "black book > mats"), so a name with one is exact without it too
local function Bare(ln)
	return ln:match("^the (.+)$") or ln:match("^an? (.+)$")
end

-- The rows of those lists whose names have the words and that pass the filters: the exact names (else those exact
-- but for a leading article), those with every word in the name as typed ({ row, score, lowercase name }), and the
-- closest of the rest; with no words, every row that passes. `from`: the last look's rows, standing for every list
-- (SeedFrom). Also gives the rows whose names had the words (filters aside), for the next keystroke.
local function SeedScan(kinds, filters, tokens, whole, from)
	local all, exact, exactBare = {}, {}, {}
	local subs, near, nearS = {}, nil, nil -- (every word in the name as typed; the closest of the rest)
	local wantAll = #tokens == 0
	local cands = {}
	-- (run in the spread-out search's coroutine: AtlasLoot's thousands of rows go over several frames, UI:RunSearch)
	local UI, n = ns.UI, 0
	local slicing = UI and UI.sliceUntil and coroutine.running() and debugprofilestop
	for k = 1, from and 1 or #kinds do
		for _, e in ipairs(from or Entries(kinds[k])) do
			n = n + 1
			if slicing and n % 64 == 0 and UI.sliceUntil and debugprofilestop() > UI.sliceUntil then coroutine.yield(UI.Results()) end
			local s, ln, typed = 0, nil, false
			if not wantAll then s, ln, typed = NameScore(e, tokens) end
			-- (help lines left out: asked only of a match, compact rows answer these through their metatable)
			if s and not (e.noActivate or e.raw) then
				if not wantAll then cands[#cands + 1] = e end
				do
					local ok = true
					for _, f in ipairs(filters) do
						local okF, yes = pcall(f, e)
						if not (okF and yes) then ok = false break end
					end
					if ok then
						if wantAll then all[#all + 1] = e
						elseif typed then subs[#subs + 1] = { e, s, ln }
						elseif not nearS or s > nearS then near, nearS = e, s end
						if ln and ln == whole then exact[#exact + 1] = e
						elseif ln and typed and Bare(ln) == whole then exactBare[#exactBare + 1] = e end
					end
				end
			end
		end
	end
	return all, #exact > 0 and exact or exactBare, subs, near, cands
end

-- each item once (a recipe and the item it makes are one), at most MAX_LEFT
local function Once(list)
	local out, seen = {}, {}
	for _, e in ipairs(list) do
		local id = ItemOf(e) or Id(e)
		if not seen[id] then
			seen[id] = true
			out[#out + 1] = e
			if #out >= P.MAX_LEFT then break end
		end
	end
	return out
end

-- reagent rows for the items known by exactly this (lowercase) name: your recipes' reagents, else Questie's items
-- (your recipes' reagents by lowercase name, made once per recipes list: every keystroke whose words matched no name
-- read every reagent's name again; made again while some names are still coming. Review, 0.53.6)
local reagents = { list = nil, byName = nil, whole = false }
local function ReagentIds(whole)
	local list = Entries("recipes")
	if reagents.list ~= list or not reagents.whole then
		local byName, all, seen = {}, true, {}
		for _, r in ipairs(list) do
			for _, rg in ipairs(r.reagents or {}) do
				local id = rg[1]
				if type(id) == "number" and not seen[id] then
					local n = ItemName(id)
					if n then
						seen[id] = true
						local ln = ns.Lower(n)
						byName[ln] = byName[ln] or {}
						table.insert(byName[ln], id)
					else
						all = false
					end
				end
			end
		end
		reagents.list, reagents.byName, reagents.whole = list, byName, all
	end
	return reagents.byName[whole]
end

local function SeedByReagentName(whole)
	local out = {}
	local ids = ReagentIds(whole) or {}
	if #ids == 0 and ns.Filters and ns.Filters.QuestieItemIds then ids = ns.Filters.QuestieItemIds(whole) end
	for _, id in ipairs(ids) do
		out[#out + 1] = { key = id, kind = "reagent", kindLabel = REAGENT_LABEL, name = ItemName(id) or whole,
			itemID = id, link = "item:" .. id, icon = Icon(id), activate = ShowItem }
	end
	return out
end

-- one name (a recipe and the item it makes are one): its rows; several: which one?
local function SeedChoices(subs)
	local byName, names = {}, {}
	for _, m in ipairs(subs) do
		local g = byName[m[3]]
		if not g then g = { rows = {}, s = m[2] }; byName[m[3]] = g; names[#names + 1] = m[3] end
		g.rows[#g.rows + 1] = m[1]
		if m[2] > g.s then g.s = m[2] end
	end
	if #names == 1 then return Once(byName[names[1]].rows) end
	table.sort(names, function(a, b)
		if byName[a].s ~= byName[b].s then return byName[a].s > byName[b].s end
		return a < b
	end)
	local choices = {}
	for i = 1, math.min(#names, P.CHOICES) do choices[i] = byName[names[i]].rows[1] end
	choices.total = #names
	return {}, nil, choices
end

--- Where a chain starts: rows of your recipes, bags, AtlasLoot and alts whose names have the words (an @kind picks the
--- lists, key:value filters narrow them). An exact name keeps only those rows (or "mats for thorium belt" would add up
--- every belt); else the one name that has every word as typed; with only filters typed, every row that passes.
--- Never a guess (0.44.4: "core leather belt" gave Comfortable Leather Hat's mats, its letters scattered in the name):
--- no name with every word -> {} and the closest name (second result); several -> {} and those names to pick from
--- (third result: rows, best first); `applies` (a row -> whether the link can go on from it) keeps, of several names,
--- those it can, when some can. `alsoKinds`: lists looked in as well as the usual ones (a relation's other
--- definitions' own: "fireball > learn" looks in What's Training's spells too, P.AlsoSeeds).
function P.Seed(text, seedKinds, alsoKinds, applies)
	local kinds, filters, tokens, whole = SeedParse(text, seedKinds, alsoKinds)
	local from = SeedFrom(kinds, tokens)
	local gen = ns.entriesGen
	local all, exact, subs, near, cands = SeedScan(kinds, filters, tokens, whole, from)
	-- (for the next keystroke: not when a list was rebuilt meanwhile, the rows looked at may be its old ones)
	lastSeed = #tokens > 0 and gen == ns.entriesGen and { gen = gen, kinds = kinds, tokens = tokens, cands = cands } or nil
	if #exact > 0 then return Once(exact) end
	-- nothing of yours by that name: an item the game or Questie knows by exactly that name (a reagent you don't
	-- carry: "where to get copper ore")
	if #subs == 0 and #all == 0 and whole ~= "" and not seedKinds then
		local out = SeedByReagentName(whole)
		if #out > 0 then return Once(out) end
	end
	if #tokens == 0 then return Once(all) end -- (only filters typed: every row that passes)
	if #subs == 0 then return {}, near end
	-- (the names the chain's link can go on from, when some can: "where to learn dagger" is the Daggers weapon skill,
	-- not a pick among every dagger AtlasLoot knows; 0.53.9)
	if applies and #subs > 1 then
		local fit = {}
		for _, m in ipairs(subs) do if applies(m[1]) then fit[#fit + 1] = m end end
		if #fit > 0 then subs = fit end
	end
	return SeedChoices(subs)
end

-- what walking on from a row means: a reagent -> where to get it; a recipe or crafted item -> its mats
local function NextOf(e, from)
	if e.kind == "reagent" then return "sources" end
	if e.kind == "attune" then return nil end -- (Attune's steps open Attune: an item step isn't walked on to its mats)
	if from ~= "mats" and P.Reagents(e) then return "mats" end
end

local function Walk(v)
	local UI = ns.UI
	local t = v.pipeChain
	-- (Simple mode: the next step in its own words, "where to get Thorium Bar", never a ">" chain)
	if SimpleOn() and v.pipeName and P.SIMPLE[v.pipeNext] then t = P.Phrase(v.pipeName, v.pipeNext) end
	UI:WalkTo(t, v) -- (the step before kept: Shift+Left goes back to it)
end
local function Opens(v, ...)
	local o = v.pipeOf
	if o and o.activate then return o.activate(o, ...) end
end

--- A row as a chain shows it: Enter walks on (when there's a step), Shift+Enter does the row's own Enter.
function P.WalkView(e, chain, from)
	local nxt = NextOf(e, from)
	if not nxt then return e end
	local name = type(e.name) == "string" and e.name:gsub("%s+x%d+$", "") or ""
	return setmetatable({
		pipeChain = chain .. " " .. name .. " > " .. nxt, pipeNext = nxt, pipeOf = e, pipeName = name,
		activate = Walk, staysOpen = true, secure = false, isOpen = false, after = false,
		secondary = Opens, secondarySecure = e.secure or false, secondaryIsOpen = e.isOpen or false,
		secondaryAfter = e.after or false, secondaryStaysOpen = false,
	}, { __index = e })
end

local function Line(text) return { name = text, kind = "pipe", noActivate = true, raw = true, _score = 1e12 } end
local function PickRelation(e) local UI = ns.UI UI:WalkTo(e.completion, e) end -- (Shift+Left: back to the choices)

-- each part's rows, by the chain up to it: typing on in the last part doesn't redo the ones before it (kept while
-- no list was rebuilt and nothing was still loading; at most STEPS_MAX, then it starts over: a key a letter typed)
P.STEPS_MAX = 64
local stepCache, stepGen, stepCount = {}, -1, 0
local function Cached(key) if stepGen == ns.entriesGen then return stepCache[key] end end
local function Keep(key, rows)
	-- (an item name, or data a filter reads, still loading: the answer is short; the search runs again once it's in)
	if P.loading or (ns.Filters and ns.Filters.loading) then return end
	if stepGen ~= ns.entriesGen then stepCache, stepGen, stepCount = {}, ns.entriesGen, 0 end
	if stepCache[key] == nil then
		if stepCount >= P.STEPS_MAX then stepCache, stepCount = {}, 0 end
		stepCount = stepCount + 1
	end
	stepCache[key] = rows
end
P.ClearSteps = function() stepCache, stepGen, stepCount, lastSeed = {}, -1, 0, nil end

--- What a link's rows came from, for chat: the one row passed on ("Thorium Belt"), else the first part as typed
--- (several rows: "copper" -> "Copper"; its @kind and filters left out); nil when neither says.
function P.FromName(left, typed)
	if #left == 1 and type(left[1].name) == "string" then
		local n = ns.Plain(left[1].name):gsub("%s+x%d+$", "")
		if n ~= "" then return n end
	end
	if type(typed) ~= "string" then return nil end
	local t = typed:gsub("@%S+", ""):gsub("%S+:%S*", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	if t == "" then return nil end
	return ns.Titled(t)
end

-- "Keep typing" while the first part has under 3 letters (and no @kind or filter)
local function KeepTyping(stages, trail)
	-- (a name still being typed: "where to get t" would match half of AtlasLoot)
	local letters = #(stages[1].text:gsub("@%S+", ""):gsub("%S+:%S*", ""):gsub("[%s%p]", ""))
	if letters < 3 and not stages[1].text:find("[@:]") then
		return { Line(L["Keep typing the name: %s"]:format(trail[1])) }, trail[1]
	end
end

-- the first link's own way to start, when it has one (chain: Questie's quests by name, else the quests rewarding an item
-- by that name; Rewards.lua)
local function FirstDef(stages)
	local name = stages[2] and P.Find(stages[2].word)
	return name and P.relations[name] and P.relations[name][1] or nil, name
end

--- The lists a relation's other definitions start from as well (`seedAlso`: What's Training's spells for "> learn"),
--- those that are there; nil: none.
function P.AlsoSeeds(name)
	local out
	for k, def in ipairs(name and P.relations[name] or {}) do
		if k > 1 and def.seedAlso and (not def.available or def.available()) then
			for _, kind in ipairs(def.seedAlso) do
				if ns.providers[kind] or P.LISTS[kind] then out = out or {}; out[#out + 1] = kind end
			end
		end
	end
	return out
end

-- the first part's rows, kept by its text (the closest name or the names to pick from ride on the list)
local function SeedRows(key, stages)
	local def, name = FirstDef(stages)
	local kinds = def and def.seedKinds
	local also = not kinds and P.AlsoSeeds(name) or nil
	if kinds or also then key = key .. " @" .. name end -- (the same words start another list there)
	local rows = Cached(key)
	if not rows then
		local near, choices
		rows, near, choices = P.Seed(stages[1].text, kinds, also, name and function(e)
			for _, d in ipairs(P.relations[name]) do
				if not d.available or d.available() then
					local ok, yes = pcall(d.applies, e)
					if ok and yes then return true end
				end
			end
			return false
		end)
		if #rows == 0 and not choices and def and def.seedFallback then
			local fb = def.seedFallback(stages[1].text)
			if fb and #fb > 0 then rows, near = Once(fb), nil end
		end
		rows.near, rows.choices = near, choices -- (kept with them: the cache hands back the list alone)
		Keep(key, rows)
	end
	return rows
end

-- a name to pick, or the closest one offered: Enter writes the chain with it
local function Pick(e, i, oneRel, rest)
	local n = ns.Plain(tostring(e.name)):gsub("%s+x%d+$", "")
	-- (Simple mode: "mats for <Name>", never a ">" chain)
	local done = oneRel and P.Phrase(n, oneRel) or (n .. " " .. rest)
	return { name = n, kind = "pipe", kindLabel = e.kindLabel or e.label, detail = e.detail, icon = e.icon,
		completion = done, staysOpen = true, activate = PickRelation, _score = 1e6 - i }
end

-- never a guess: the names to pick from, or the closest one offered (Enter writes the chain with it)
local function NoSeedRows(chain, stages, rows, trail)
	-- (the links after the name, made again from the stages: spaces typed twice made an offset into the chain miss)
	local after = {}
	for i = 2, #stages do after[#after + 1] = "> " .. stages[i].text end
	local rest = table.concat(after, " ")
	local oneRel = #stages == 2 and P.Find(stages[2].word) and (stages[2].rest or "") == "" and P.Find(stages[2].word)
	if rows.choices then
		local out = { Line(L["%d names have \"%s\": pick one"]:format(rows.choices.total, trail[1])) }
		for i, e in ipairs(rows.choices) do out[#out + 1] = Pick(e, i, oneRel, rest) end
		return out, trail[1] .. " > ?"
	end
	local def = FirstDef(stages)
	local out = { Line(((def and def.seedNone) or L["Nothing called \"%s\" in your bags, recipes, AtlasLoot or alts"]):format(trail[1])) }
	if rows.near then
		local d = Pick(rows.near, 1, oneRel, rest)
		d.name = L["Did you mean %s?"]:format(d.name)
		out[2] = d
	end
	return out, trail[1]
end

-- a link still being typed (or not one): the relations these rows can go through, to pick from
local function RelationChoices(chain, s, rows, trail)
	local out = {}
	local lw = ns.Lower(s.word or "")
	local before = chain:sub(1, (chain:find(">[^>]*$")) or #chain)
	for _, a in ipairs(P.Applicable(P.Left(rows))) do
		if lw == "" or a[1]:sub(1, #lw) == lw or (P.LABELS[a[1]] or ""):sub(1, #lw) == lw then
			local done = before .. " " .. a[1] .. " "
			out[#out + 1] = { name = a[1], kind = "pipe", kindLabel = "|cff33ff99" .. L["link"] .. "|r", detail = a[2],
				completion = done, staysOpen = true, activate = PickRelation, _score = 1e6 - #out }
		end
	end
	if #out == 0 then
		local names = {}
		for _, name in ipairs(P.order) do if P.Available(name) then names[#names + 1] = name end end
		out[1] = Line(L["No link called \"%s\": %s"]:format(s.word or "", table.concat(names, ", ")))
	end
	trail[#trail + 1] = "?"
	return out, table.concat(trail, " > ")
end

local function ByScore(a, b) return a.s > b.s end

-- the rows whose names have every word, best first
local function NarrowByName(rows, tokens)
	local kept = {}
	for _, e in ipairs(rows) do
		local sc = NameScore(e, tokens)
		if sc then kept[#kept + 1] = { e = e, s = sc } end
	end
	table.sort(kept, ByScore)
	rows = {}
	for _, k in ipairs(kept) do rows[#rows + 1] = k.e end
	return rows
end

-- the last part's rows as the chain shows them: Enter walks on where there's a step; each says what the chain makes
-- of it (for chat)
local function FinalRows(rows, stages, base, from, lastRel, lastFrom)
	local out = {}
	for i, e in ipairs(rows) do
		local v = (#stages > 1) and P.WalkView(e, base, from) or e
		if v == e then v = setmetatable({}, { __index = e }) end
		v._score = 1e6 - i
		-- (what the chain says this row is, for chat: "Mats for Thorium Belt: 8x [Thorium Bar]", Share.ChainContext)
		v.pipeRel, v.pipeFrom = lastRel, lastFrom
		out[#out + 1] = v
	end
	return out
end

-- The lists a chain reads (the usual ones, and any @kind's), built again first when they changed since: the steps
-- kept go with the lists they were made from (bars you just bought show in "have" at once). A list never built isn't
-- built here (no step read it).
local function Refreshed(text)
	for _, k in ipairs(P.SEED_KINDS) do
		local p = ns.providers[k]
		if p and p._entries then ns:GetEntries(p) end
	end
	for w in text:gmatch("@(%S+)") do
		local p = ns:ResolveProvider(w)
		if p and p._entries then ns:GetEntries(p) end
	end
end

-- Simple mode's words for a link that gave nothing ("Nothing uses Hearthstone"): it never shows ">"
P.SIMPLE_NONE = { mats = L["No mats for %s: it isn't crafted"], uses = L["Nothing uses %s"], sources = L["Nowhere known to get %s"],
	alts = L["No %s on your alts"], learn = L["Nowhere known to learn %s"], chain = L["No quests lead up to %s"] }

local function NothingThere(trail, stages, rel, from)
	local f = SimpleOn() and #stages == 2 and (stages[2].rest or "") == "" and P.SIMPLE_NONE[rel]
	local said = table.concat(trail, " > ")
	if f then return { Line(f:format(from or trail[1])) }, said end
	return { Line(L["Nothing there: %s"]:format(SimpleOn() and P.SimpleLabel(said) or said)) }, said
end

--- Runs a chain: rows, and the footer's trail ("thorium belt > mats > thorium bar > sources").
function P.Search(chain)
	local stages = P.Split(chain)
	if not stages then return {}, nil end
	P.loading = false
	Refreshed(stages[1].text)
	local trail = { (stages[1].text:gsub("^%s+", ""):gsub("%s+$", "")) }
	local wait, said = KeepTyping(stages, trail)
	if wait then return wait, said end
	local key = ns.Lower(trail[1])
	local rows = SeedRows(key, stages)
	if #rows == 0 then return NoSeedRows(chain, stages, rows, trail) end
	local from, lastRel, lastFrom
	-- (walking on from the last part's rows: the chain up to its link word, then the row's name)
	local base = chain:sub(1, (chain:find(">[^>]*$"))) .. " " .. (stages[#stages].word or "")
	for i = 2, #stages do
		local s = stages[i]
		local name = P.Find(s.word)
		if not name then return RelationChoices(chain, s, rows, trail) end
		key = key .. " > " .. name
		lastRel, lastFrom = name, P.FromName(P.Left(rows), i == 2 and trail[1] or nil)
		local got = Cached(key)
		if not got then
			got = P.Run(name, P.Left(rows))
			Keep(key, got)
		end
		rows = got
		trail[#trail + 1] = P.LABELS[name] or name
		from = name
		local tokens = Tokens(s.rest)
		if #tokens > 0 then key = key .. " " .. table.concat(tokens, " ") end
		if #tokens > 0 then
			rows = NarrowByName(rows, tokens)
			trail[#trail + 1] = (s.rest:gsub("^%s+", ""):gsub("%s+$", ""))
			if i < #stages then from = nil end -- (narrowed to a row: the next link starts from it)
		end
		if #rows == 0 then return NothingThere(trail, stages, name, lastFrom) end
	end
	return FinalRows(rows, stages, base, from, lastRel, lastFrom), table.concat(trail, " > ")
end

--- The rows to pass on: real results (not hints or help lines), each once, at most MAX_LEFT.
function P.Left(rows)
	local out, seen = {}, {}
	for _, e in ipairs(rows or {}) do
		if not (e.raw or e.noActivate or e.completion or e.kind == "calc") then
			local o = rawget(e, "pipeOf") or e
			local id = Id(o)
			if not seen[id] then
				seen[id] = true
				out[#out + 1] = o
				if #out >= P.MAX_LEFT then break end
			end
		end
	end
	return out
end

ns:RegisterCommand("chains", {
	desc = L["Chains: pass a search on with > (thorium belt > mats, copper bar > uses, mageweave > sources), or in plain words (mats for thorium belt)"],
	aliases = { "pipes", "pipe", "links" },
	run = function()
		local lines = { L["Chains: a  >  passes what a search found on (Enter on a row walks on, Shift+Enter opens it):"] }
		for _, name in ipairs(P.order) do
			-- (only the links you can use: steps and attunement need Attune, chain Questie; review, 0.53.6)
			local def = P.Available(name) and P.relations[name][1]
			if def then
				lines[#lines + 1] = ("  %s%s  -  %s"):format(name, #def.aliases > 0 and (" (" .. table.concat(def.aliases, ", ") .. ")") or "", def.desc)
			end
		end
		lines[#lines + 1] = L["In plain words: mats for thorium belt, what uses copper bar, where to get thorium bar, who sells mageweave, where to learn thorium belt."]
		return lines
	end,
})

----------------------------------------------------------------------
-- Summing up (0.52.13, the player's ask): Advanced mode's "|" standing alone ends the search; what follows works on
-- every row it found (not only the 100 a list shows), as a shell's pipe:
--
--   in:bags | sum value             what all of it would sell for at a vendor: one row
--   @quest | group zone             a row per zone with how many are there, the most first ("group by zone" too)
--   @item | count                   how many were found; "count by quality": a row per quality, as group
--   in:bags | sum value by quality  a total per quality (and all of them on top); "| avg ilvl by slot"
--   @quest | zone:"Elwynn Forest"   only the rows with that (a group's Enter writes it: Shift+Left goes back)
--
-- Steps chain: "in:bags | q:rare | sum value". The words are fields (ns.Aggregate.FIELDS); a row without one is
-- left out of a sum, and of the groups (0.53.4: no "no zone" group).
----------------------------------------------------------------------

local A = {}
ns.Aggregate = A

local FP = ns.Filters and ns.Filters._ or {}
local function Info(e)
	local id = ns.Filters and ns.Filters.ItemOf and ns.Filters.ItemOf(e)
	return id and FP.ItemInfo and FP.ItemInfo(id) or nil
end
local function Num(n) return type(n) == "number" and n or nil end
local function Count(e) return FP.Count and FP.Count(e) or Num(e.total) or Num(e.count) end
local function Str(s) return type(s) == "string" and s ~= "" and s or nil end

--- A loot row's boss, place and the place's kind ("dungeon", "raid", "world": AtlasLoot's World Bosses; nil: not
--- known, an index from before 0.51.9)
--- ("Edwin VanCleef  The Deadmines": two spaces between them, Loot.lua's GroupText). Only a dungeon's or a raid's:
--- AtlasLoot's other tables (battlegrounds, professions, factions, PvP...) are no instance and their pages no boss
--- (0.53.1, the player: "count by dungeon" listed Arathi Basin and Leatherworking).
local function LootParts(e)
	if e.kind ~= "loot" then return nil end
	local I = ns.Integrations
	local where = I and I.LootPlace and I.LootPlace(e)
	local kind = where and where.kind
	if where and kind ~= "dungeon" and kind ~= "raid" and kind ~= "world" then return nil end
	local d = Str(e.detail)
	if not d then return nil end
	local boss, place = d:match("^(.-)  (.+)$")
	return Str(boss), Str(place), kind
end

--- A loot row's place when it's of this kind (0.53.3, the player: "by raid" listed dungeons, "by dungeon" raids;
--- "by instance" is either).
local function PlaceOfKind(want)
	return function(e)
		local _, place, kind = LootParts(e)
		if want and kind ~= want then return nil end
		if kind == "world" then return nil end -- (World Bosses: a boss's, out in the world, no instance)
		return place
	end
end

local InstanceOf = PlaceOfKind(nil)
local areaNames = {} -- (an area's name, asked once: it doesn't change)
local function ZoneOf(e)
	local z = Str(e.zone)
	if z then return z end
	if FP.NpcID and FP.NpcID(e) then
		local area = FP.NpcField(e, "zoneID")
		if type(area) ~= "number" or area <= 0 then return nil end
		local got = areaNames[area]
		if got == nil then
			got = C_Map and C_Map.GetAreaInfo and Str(C_Map.GetAreaInfo(area)) or false
			areaNames[area] = got
		end
		return got or nil
	end
	return InstanceOf(e)
end

local function QualityName(q)
	local s = type(q) == "number" and _G["ITEM_QUALITY" .. q .. "_DESC"]
	local name = Str(s) or (type(q) == "number" and ns.Filters and ns.Filters.QUALITIES and ns.Filters.QUALITIES[q + 1])
	if not name then return nil end
	return name, ns.QualityHex and ns.QualityHex(q) -- (the whole code, "|cff0070dd")
end

--- The fields: text (what a row is grouped by) and/or num (what's summed); money: a num that's copper. order: groups by
--- this number, not by size (qualities: the best first). label: how a row says it.
A.FIELDS = {
	kind = { label = L["kind"], text = function(e)
		local p = e.kind and ns.providers[e.kind]
		return p and Str(p.label) or nil
	end },
	zone = { label = L["zone"], text = ZoneOf },
	dungeon = { label = L["dungeon"], text = PlaceOfKind("dungeon") },
	raid = { label = L["raid"], text = PlaceOfKind("raid") },
	instance = { label = L["instance"], text = InstanceOf },
	boss = { label = L["boss"], text = function(e) return (LootParts(e)) end },
	quality = { label = L["quality"], num = function(e)
		local q = Num(e.quality)
		if q then return q end
		local info = Info(e)
		return info and Num(info.quality)
	end, text = function(e, f) return (QualityName(f.num(e))) end, order = true },
	type = { label = L["type"], text = function(e) local i = Info(e); return i and Str(i.type) end },
	subtype = { label = L["subtype"], text = function(e) local i = Info(e); return i and Str(i.subType) end },
	slot = { label = L["slot"], text = function(e)
		local i = Info(e)
		local loc = i and Str(i.equipLoc)
		return loc and Str(_G[loc]) or nil
	end },
	level = { label = L["level"], num = function(e) return FP.Levels and (FP.Levels(e)) or nil end, order = true },
	ilvl = { label = L["item level"], num = function(e) local i = Info(e); return i and Num(i.ilvl) end, order = true },
	count = { label = L["count"], num = function(e) return Count(e) or 1 end },
	-- (the combat log's hits: sort:damage; 0.55.7)
	damage = { label = L["damage"], num = function(e) return e.kind == "combatlog" and Num(e.amount) or nil end },
	price = { label = L["price"], money = true, num = function(e) local i = Info(e); return i and Num(i.sell) end },
	value = { label = L["value"], money = true, num = function(e)
		local i = Info(e)
		local sell = i and Num(i.sell)
		return sell and sell * (Count(e) or 1) or nil
	end },
}
A.ALIASES = { q = "quality", lvl = "level", itemlevel = "ilvl", ["in"] = "zone", where = "zone", place = "zone",
	area = "zone", dungeons = "dungeon", raids = "raid", instances = "instance", bosses = "boss", from = "boss", qty = "count", amount = "count", number = "count",
	worth = "value", gold = "value", money = "value", vendor = "value", sell = "value", list = "kind", kinds = "kind",
	sub = "subtype", subtypes = "subtype", types = "type", slots = "slot", zones = "zone", qualities = "quality" }
A.ORDER = { "value", "price", "count", "kind", "zone", "instance", "dungeon", "raid", "boss", "quality", "type", "subtype", "slot", "level", "ilvl" }
A.OPS = { count = "count", group = "group", sum = "sum", total = "sum", avg = "avg", average = "avg", mean = "avg" }

local function FieldOf(word)
	word = ns.Lower(word or "")
	local name = A.FIELDS[word] and word or A.ALIASES[word]
	return name and A.FIELDS[name] and name or nil
end
A.FieldOf = FieldOf

--- The search and its steps: "in:bags | sum value" -> "in:bags", { "sum value" }. A "|" counts only standing alone,
--- outside quotes ("sword|axe" is either); nil steps when there's none.
function A.Split(text)
	if type(text) ~= "string" or not text:find("|", 1, true) then return text, nil end
	local parts, from, quoted = {}, 1, false
	for i = 1, #text do
		local c = text:sub(i, i)
		if c == '"' then
			quoted = not quoted
		elseif c == "|" and not quoted then
			local before, after = i == 1 and " " or text:sub(i - 1, i - 1), i == #text and " " or text:sub(i + 1, i + 1)
			if before:find("%s") and after:find("%s") then
				parts[#parts + 1] = text:sub(from, i - 1)
				from = i + 1
			end
		end
	end
	if #parts == 0 then return text, nil end
	parts[#parts + 1] = text:sub(from)
	local query = table.remove(parts, 1):gsub("%s+$", "")
	for k, p in ipairs(parts) do parts[k] = p:gsub("^%s+", ""):gsub("%s+$", "") end
	return query, parts
end

--- One step read: { op = "sum", field = "value", by = "zone" }, { where = field, value = "elwynn forest", exact = true },
--- or { bad = what to say } (still being typed, or a word it doesn't know).
local function ParseStep(step)
	local field, value = step:match("^(%a+):(.*)$")
	if field then
		local f = FieldOf(field)
		if not f then return { bad = L["no field called %s"]:format(field) } end
		local exact = value:match('^"(.*)"?$')
		value = (exact or value):gsub('"', ""):gsub("^%s+", ""):gsub("%s+$", "")
		if value == "" then return { bad = L["say what %s to keep: %s:\"...\""]:format(field, field) } end
		-- (a number: kept by its range, as the filters read one; review, 0.53.6: "| lvl:20-30" kept nothing, "| lvl:2"
		-- kept level 25 as "2" is in "25")
		local fd = A.FIELDS[f]
		if fd.num and not fd.text then
			local test = ns.Filters and ns.Filters.Range and ns.Filters.Range(value)
			if not test then return { bad = L["a number or a range: %s:20-30"]:format(field) } end
			return { where = f, value = ns.Lower(value), test = test }
		end
		return { where = f, value = ns.Lower(value), exact = exact ~= nil }
	end
	local ws = {}
	for w in step:gmatch("%S+") do ws[#ws + 1] = ns.Lower(w) end
	local op = A.OPS[ws[1] or ""]
	if not op then
		-- (a step's start, "| co": still being typed, the line on top says what goes there)
		for name in pairs(A.OPS) do if ws[1] and #ws == 1 and name:sub(1, #ws[1]) == ws[1] then return { bad = "" } end end
		return { bad = ws[1] and L["no step called %s"]:format(ws[1]) or "" }
	end
	-- the words after it: "[by] field [by field]" ("sum value", "sum by value", "sum value by zone", "group by zone")
	local k = 2
	local function Next()
		if ws[k] == "by" or ws[k] == "of" then k = k + 1 end
		local w = ws[k]
		k = k + 1
		return w
	end
	local first, second = Next(), Next()
	if ws[k] then return { bad = L["one field to sum, one to group by: sum value by zone"] } end
	if op == "count" or op == "group" then
		if second then return { bad = L["group by one field: group by zone"] } end
		if not first then
			if op == "group" then return { bad = L["group by what: zone, kind, quality..."] } end
			return { op = "count" }
		end
		local by = FieldOf(first)
		if not by then return { bad = L["no field called %s"]:format(first) } end
		if A.FIELDS[by].money then return { bad = L["group by what: zone, kind, quality..."] } end -- (copper amounts)
		return { op = "group", by = by }
	end
	if not first then return { bad = L["%s of what: value, count, level..."]:format(ws[1]) } end
	local field = FieldOf(first)
	if not field or not A.FIELDS[field].num then return { bad = L["no number called %s"]:format(first) } end
	local by
	if second then
		by = FieldOf(second)
		if not by then return { bad = L["no field called %s"]:format(second) } end
		if A.FIELDS[by].money then return { bad = L["group by what: zone, kind, quality..."] } end
	end
	return { op = op, field = field, by = by }
end
A.ParseStep = ParseStep

--- The steps typed after the search, read: { wheres = { ... }, last = the summing step or nil, bad = what to say, base =
--- the search with its keeping steps }.
function A.Parse(steps, query)
	local spec = { wheres = {} }
	local base = { query or "" }
	for k, step in ipairs(steps) do
		local s = ParseStep(step)
		if s.bad then spec.bad = s.bad; spec.badStep = step; return spec end
		if s.where then
			spec.wheres[#spec.wheres + 1] = s
			base[#base + 1] = step
		elseif k < #steps then
			spec.bad = L["a sum, count or group is the last step"]
			return spec
		else
			spec.last = s
		end
	end
	spec.text = table.concat(steps, " | ")
	spec.base = table.concat(base, " | ") -- (a group's Enter: this, then its own "| zone:...")
	spec.query = query or ""
	table.remove(base, 1)
	spec.keepSteps = base -- (the keeping steps typed, each as typed: a group's Enter puts its filter before them)
	return spec
end

local function Real(e) return not (e.raw or e.noActivate or e.completion or e.lead or e.kind == "calc") end
-- "1 result", "3 results" (the footer's words: 0.55.10, the player's screenshot said "1 results")
local function ResultsN(n) return (n == 1 and L["%s result"] or L["%s results"]):format(n) end

local function TextOf(name, e)
	local f = A.FIELDS[name]
	if f.text then return f.text(e, f) end
	local n = f.num(e)
	return n and tostring(n) or nil
end

local function KeepsRow(w, e)
	if w.test then return w.test(A.FIELDS[w.where].num(e)) end -- (a number's step: by its range, "lvl:20-30")
	local t = TextOf(w.where, e)
	if not t then return false end
	-- (quote marks aren't compared: a step's value has none, "Captain" Cookie's group neither; release review)
	local lt = ns.Lower(ns.Plain(t)):gsub('"', "")
	if lt == w.value then return true end
	return not w.exact and lt:find(w.value, 1, true) ~= nil
end

--- A number as a row says it (copper as gold, silver and copper), and as plain text (copied: no coin icons).
local function Shown(field, n)
	local f = A.FIELDS[field]
	if f.money then
		if not ns.Gold then return tostring(n) .. "c", tostring(n) .. "c" end
		return ns.Money(n), ns.Money(n, true)
	end
	local t = math.floor(n) == n and tostring(n) or ("%.1f"):format(n)
	return t, t
end

local ICON = "Interface\\Icons\\INV_Misc_Note_01"
local function Row(name, detail, key, label)
	return { kind = "aggregate", kindLabel = "|cff33ff99" .. label .. "|r", icon = ICON, raw = true, _score = 0,
		_pos = ns.UI and ns.UI.NO_POS, name = name, detail = detail, key = key, noActivate = true }
end

--- A total's Enter: it's said in the chat window (only to you), the search kept in the history (release review: Enter
--- did nothing, and Up never brought a summed-up search back).
local function SayTotal(e)
	ns:Print(ns.Share and ns.Share.Clean(e.copyName or e.name) .. (e.detail ~= "" and ("  (" .. ns.Share.Clean(e.copyDetail or e.detail) .. ")") or "")
		or tostring(e.name))
end
local function Said(r)
	r.noActivate, r.activate, r.actionVerb = nil, SayTotal, L["show in chat"]
	return r
end

--- What a group's Enter writes: the search with the group's own filter added, as you'd type it (0.53.1, the player: the
--- filters work without a "|", so "@loot q:rare", not "@loot | quality:\"Rare\""); a field no filter says the same of
--- (kind, slot, a name with quote marks in it) keeps its rows by a step, "| slot:\"Finger\"".
local DrillTo
local FILTER_OF = {
	quality = function(g, f) local q = f.num(g.sample) return q and ns.Filters.QUALITIES and ns.Filters.QUALITIES[q + 1] and ("q:" .. ns.Filters.QUALITIES[q + 1]) end,
	level = function(g) return "lvl:" .. g.text end,
	ilvl = function(g) return "ilvl:" .. g.text end,
	count = function(g) return "count:" .. g.text end,
	zone = function(g) return 'in:"' .. g.text .. '"' end,
	dungeon = function(g) return 'in:"' .. g.text .. '"' end,
	raid = function(g) return 'in:"' .. g.text .. '"' end,
	instance = function(g) return 'in:"' .. g.text .. '"' end,
	boss = function(g) return 'in:"' .. g.text .. '"' end,
	type = function(g) return 'type:"' .. g.text .. '"' end,
	subtype = function(g) return 'type:"' .. g.text .. '"' end,
}
DrillTo = function(spec, by, g)
	local text = ns.Plain(g.text)
	local make = not text:find('"', 1, true) and FILTER_OF[by]
	local word = make and make({ text = text, sample = g.sample }, A.FIELDS[by])
	local steps = {}
	for _, st in ipairs(spec.keepSteps or {}) do steps[#steps + 1] = " | " .. st end
	-- (a space after the filter: the caret right after a key:value would list its values to pick, not the rows)
	-- (after the steps too: the caret after "| q:rare" listed q:'s values; review, 0.53.6)
	-- (the line has it already: not written twice; 0.55.10, the player's screenshot had in:"Winterspring" seven times)
	local q = spec.query:gsub("%s+$", "")
	if word and (" " .. q .. " "):find(" " .. word .. " ", 1, true) then return q .. table.concat(steps) .. " " end
	if word then return q .. " " .. word .. table.concat(steps) .. " " end
	return spec.base .. " | " .. by .. ':"' .. (text:gsub('"', "")) .. '" '
end

--- A group's Enter: the same search, keeping that group's rows (Shift+Left goes back).
local function Drill(e)
	local UI = ns.UI
	if not (UI and e.drillTo) then return end
	-- (the bar's Group made these groups: its rows aren't grouped again; Shift+Left brings the Group back with the step)
	local B = ns.Bar
	local saved = B and B.Save()
	if e.drillFromBar and B then B.state.group = nil end
	UI:WalkTo(e.drillTo, e, saved)
end

--- The rows the search found, put through the steps: the kept rows (only "where" steps), or the summed-up rows. Rows
--- whose item data isn't in yet ask for it and the search runs again (Filters.loading: UI:RetryWhenLoaded).
--- `base`: the text before the summing step (a group's Enter keeps its rows: base | field:"value").
--- Do the steps change what the search gives (sum it up, or keep some of its rows)? Then the search hands over every
--- match, untrimmed and with no close spellings, and A.Apply sorts and trims what's kept (review, 0.53.6: a keeping
--- step alone ran over the best 100: "| zone:\"Cap Cove\"" listed 9 of a group's 30).
function A.Summing(spec)
	return spec ~= nil and not spec.bad and (spec.last ~= nil or #(spec.wheres or {}) > 0)
end

function A.Apply(spec, res, base)
	local rows = {}
	for _, e in ipairs(res or {}) do if Real(e) then rows[#rows + 1] = e end end
	if spec.bad then
		-- (still being typed, or a word it doesn't know: the rows as they are, with a line saying what goes there)
		local fields = {}
		for _, name in ipairs(A.ORDER) do fields[#fields + 1] = name end
		local hint = Row(spec.bad ~= "" and spec.bad or L["| count, | sum value, | group by zone, | avg level"],
			L["fields: %s"]:format(table.concat(fields, ", ")), "aggregate:hint", L["sum up"])
		local out = { hint }
		for _, e in ipairs(res or {}) do out[#out + 1] = e end
		return out
	end
	for _, w in ipairs(spec.wheres) do
		local kept = {}
		for _, e in ipairs(rows) do if KeepsRow(w, e) then kept[#kept + 1] = e end end
		rows = kept
	end
	local s = spec.last
	if not s then return ns.UI.SortAndTrim(rows) end
	local n = #rows
	if s.op == "count" then
		local r = Row(ResultsN(n), base or "", "aggregate:count:" .. n, L["count"])
		Said(r)
		return { r }
	end
	local f = s.field and A.FIELDS[s.field]
	-- one total ("sum value") or one per group ("group zone", "sum value by zone")
	local groups, order = {}, {}
	local total, have = 0, 0
	local texts -- (each row's group, read once: a zone is a Questie lookup per NPC row; review, 0.53.6)
	if s.by then -- (by raid: the raids' rows alone, no "no raid" group; by slot: what has one; 0.53.4, the player)
		local kept = {}
		texts = {}
		for _, e in ipairs(rows) do
			local t = TextOf(s.by, e)
			if t then kept[#kept + 1] = e; texts[#kept] = t end
		end
		rows, n = kept, #kept
	end
	for i, e in ipairs(rows) do
		local v = f and f.num(e)
		if v then total, have = total + v, have + 1 end
		if s.by then
			local t = texts[i]
			local g = groups[t]
			if not g then
				g = { text = t, n = 0, sum = 0, have = 0, sample = e }
				groups[t] = g
				order[#order + 1] = g
			end
			g.n = g.n + 1
			if v then g.sum, g.have = g.sum + v, g.have + 1 end
		end
	end
	local function Value(sum, got)
		if s.op == "avg" then return got > 0 and sum / got or nil end
		return sum
	end
	local function Detail(cnt, got)
		local parts = { ResultsN(cnt) }
		if f and got < cnt then parts[#parts + 1] = L["%d with no %s"]:format(cnt - got, f.label) end
		return table.concat(parts, ns.DETAIL_SEP)
	end
	local loading = ns.Filters and ns.Filters.loading
	local opLabel = s.op == "avg" and L["average"] or s.op == "sum" and L["sum"] or L["group"]
	if not s.by then
		local v = Value(total, have)
		local name, plain = L["nothing to %s"]:format(opLabel), nil
		if v then name, plain = Shown(s.field, v) end
		local detail = (s.op == "avg" and L["average %s of %s"] or L["%s of %s"]):format(f.label, Detail(n, have))
		if loading then detail = detail .. ns.DETAIL_SEP .. L["item data still coming in"] end
		local r = Row(name, detail, "aggregate:" .. s.op .. ":" .. tostring(v) .. ":" .. n, opLabel)
		r.copyName = plain
		Said(r)
		return { r }
	end
	local byField = A.FIELDS[s.by]
	for _, g in ipairs(order) do
		if f then g.value = Value(g.sum, g.have) else g.value = g.n end -- (an average of none: none, not the count)
		if byField.order and byField.num then g.rank = byField.num(g.sample) end
	end
	table.sort(order, function(a, b)
		if byField.order and a.rank and b.rank and a.rank ~= b.rank then return a.rank > b.rank end
		local va, vb = a.value or -math.huge, b.value or -math.huge
		if va ~= vb then return va > vb end
		return tostring(a.text) < tostring(b.text)
	end)
	local out = {}
	if f and s.op == "sum" then -- (all of them on top)
		local shown, plain = Shown(s.field, total)
		out[1] = Row(L["All: %s"]:format(shown), L["%s of %s"]:format(f.label, Detail(n, have)),
			"aggregate:all:" .. total .. ":" .. n, opLabel)
		out[1].copyName = L["All: %s"]:format(plain)
		Said(out[1])
	end
	for _, g in ipairs(order) do
		local name = g.text
		if s.by == "quality" and g.text then
			local _, hex = QualityName(byField.num(g.sample))
			if hex then name = hex .. g.text .. "|r" end -- (0.52.14, the player's screenshot: "|c" put before it showed)
		end
		local detail, copyDetail = ResultsN(g.n), nil
		if f then
			local shown, plain = "-", "-"
			if g.value then shown, plain = Shown(s.field, g.value) end
			detail, copyDetail = shown .. ns.DETAIL_SEP .. Detail(g.n, g.have), plain .. ns.DETAIL_SEP .. Detail(g.n, g.have)
		end
		local r = Row(name, detail, "aggregate:" .. s.by .. ":" .. tostring(g.text) .. ":" .. g.n .. ":" .. tostring(g.value), opLabel)
		r.copyDetail = copyDetail
		if g.text and base then
			r.noActivate, r.activate, r.staysOpen = nil, Drill, true
			r.drillTo = DrillTo(spec, s.by, g)
			r.drillFromBar = spec.fromBar -- (Simple mode's bar's Group: let go on the way in, Drill)
			r.actionVerb = L["list them"]
		end
		out[#out + 1] = r
	end
	if loading and out[1] then out[1].detail = out[1].detail .. ns.DETAIL_SEP .. L["item data still coming in"] end
	return out
end
