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
-- names the relation; the rest of that part narrows what it gave, by name. Recipes come from your own professions and,
-- for any crafted item, from AtlasLoot's crafting data; sellers, droppers, gathering spots and the containers an item comes
-- out of from Questie; the tokens it comes from (Questions/Tokens.lua, AtlasLoot's) and what it's skinned from, fished
-- in, disenchanted from (Providers/Integrations/OneForAll/Reagents.lua): other "sources" definitions. (Revived
-- from the shelved `pipes` branch.) (This was Pipes.lua; the "|" steps, sums and groups, are Aggregate.lua beside it.)

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
	-- what an NPC drops, what a vendor sells: only when the words name one (P.PHRASE_NPC)
	{ "^what does (.+) drop$", "drops" }, { "^what do (.+) drop$", "drops" }, { "^drops from (.+)$", "drops" },
	{ "^loot from (.+)$", "drops" }, { "^(.+) loot$", "drops" }, { "^(.+) drops$", "drops" },
	-- a quest's rewards and its chain in words (only when the words name a quest: "what does stamina give", "rewards
	-- from dungeons" aren't)
	{ "^what does (.+) give$", "rewards", "quest" }, { "^what does (.+) reward$", "rewards", "quest" },
	{ "^rewards for (.+)$", "rewards", "quest" }, { "^rewards from (.+)$", "rewards", "quest" },
	{ "^what do i get for (.+)$", "rewards", "quest" },
	-- (what a token or a bag turns into, AtlasLoot's: Tokens.lua's "rewards"; only when the words name one: "what does
	-- libram of focus give", "what does blue sack of gems contain")
	{ "^what does (.+) give$", "rewards", "token" }, { "^what do i get for (.+)$", "rewards", "token" },
	{ "^what does (.+) turn into$", "rewards", "token" }, { "^what does (.+) contain$", "rewards", "token" },
	{ "^whats in (.+)$", "rewards", "token" }, { "^what's in (.+)$", "rewards", "token" }, { "^what is in (.+)$", "rewards", "token" },
	-- (what a quest opens up, QuestAccess.lua's "unlocks": the quests after it, not the chain before it)
	{ "^next quests? after (.+)$", "unlocks", "quest" }, { "^what comes after (.+)$", "unlocks", "quest" },
	{ "^what does (.+) unlock$", "unlocks", "quest" }, { "^what does (.+) lead to$", "unlocks", "quest" },
	{ "^what quests? comes? after (.+)$", "unlocks", "quest" }, { "^quests? after (.+)$", "unlocks", "quest" },
	{ "^what follows (.+)$", "unlocks", "quest" },
	{ "^what does (.+) sell$", "sells" }, { "^what do (.+) sell$", "sells" }, { "^items sold by (.+)$", "sells" },
	{ "^what is sold by (.+)$", "sells" }, { "^whats sold by (.+)$", "sells" }, { "^(.+) wares$", "sells" },
	{ "^what does (.+) have for sale$", "sells" },
	-- where to farm or find something: its sources, when the words aren't an NPC's or a place's ("where do i find
	-- hogger" stays where he is: P.PHRASE_THING)
	{ "^where to farm (.+)$", "sources", "thing" }, { "^where do i farm (.+)$", "sources", "thing" },
	{ "^where can i farm (.+)$", "sources", "thing" }, { "^where to find (.+)$", "sources", "thing" },
	{ "^where do i find (.+)$", "sources", "thing" }, { "^where can i find (.+)$", "sources", "thing" },
	{ "^best place to farm (.+)$", "sources", "thing" }, { "^farming (.+)$", "sources", "thing" },
	{ "^where to get (.+)$", "sources" }, { "^where do i get (.+)$", "sources" }, { "^where can i get (.+)$", "sources" },
	{ "^where to buy (.+)$", "sources" }, { "^where can i buy (.+)$", "sources" }, { "^how to get (.+)$", "sources" },
	{ "^how do i get (.+)$", "sources" }, { "^sources? for (.+)$", "sources" }, { "^sources? of (.+)$", "sources" },
	{ "^where does (.+) drop$", "sources" }, { "^who sells (.+)$", "sources" }, { "^what drops (.+)$", "sources" },
	{ "^who drops (.+)$", "sources" }, { "^what mobs? drops? (.+)$", "sources" }, { "^which mobs? drops? (.+)$", "sources" },
	{ "^vendors? that sells? (.+)$", "sources" }, { "^vendors? selling (.+)$", "sources" }, { "^which vendors? sells? (.+)$", "sources" },
	{ "^what vendors? sells? (.+)$", "sources" }, { "^who has (.+) for sale$", "sources" },
	-- the quests before one (Rewards.lua): "quest chain for the missing diplomat", "quest chain for outlaw sabre"
	{ "^quest chain for (.+)$", "chain" }, { "^quest chain of (.+)$", "chain" }, { "^chain for (.+)$", "chain" },
	{ "^quests? before (.+)$", "chain" }, { "^what leads to (.+)$", "chain" }, { "^prereqs? for (.+)$", "chain" },
	{ "^(.+) quest chain$", "chain" }, { "^(.+) chain$", "chain", "quest" }, -- (after "quest chain": its name without
	-- "quest"; only a quest's name: "heavy chain" is an item's)
}

-- (the phrases whose words must name an NPC or a boss: "hogger loot" is Hogger's, "deadmines loot" and "raid loot" not)
P.PHRASE_NPC = { drops = true, sells = true }

-- Simple mode's words for a one-link chain (it never shows ">"): what Enter writes and what the footer says
P.SIMPLE = { mats = "mats for %s", uses = "what uses %s", sources = "where to get %s", learn = "where to learn %s",
	chain = "quest chain for %s", drops = "what does %s drop", sells = "what does %s sell", rewards = "rewards for %s",
	unlocks = "what comes after %s" }
P.SIMPLE_LABEL = { mats = L["Mats for %s"], uses = L["What uses %s"], sources = L["Where to get %s"], alts = L["%s on your alts"],
	learn = L["Where to learn %s"], chain = L["Quest chain for %s"], ["?"] = L["Which %s?"], drops = L["Drops from %s"],
	sells = L["Sold by %s"], rewards = L["%s rewards"], unlocks = L["What comes after %s"] }

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
P.FIRST.prereq = true -- ("^prereqs? for" starts with prereq too)
P.FIRST.vendor = true -- ("^vendors? that sells?": "vendor that sells x")

--- The chain a line means: the line itself when it has links, the chain its plain words say ("mats for x" -> "x >
--- mats"), else nil. `words`: only the plain words (Simple mode: a ">" typed there is Advanced syntax, refused like an
--- @kind).
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
			if not P.NotAName(what) and not (P.PHRASE_NPC[ph[2]] and not P.NpcNamed(what))
				and not (ph[3] == "thing" and P.NotAThing(what)) and not (ph[3] == "quest" and not P.QuestNamed(what))
				and not (ph[3] == "token" and not (P.TokenNamed and P.TokenNamed(what))) then
				return what .. " > " .. ph[2]
			end
		end
	end
	return nil
end

-- what a phrase caught that names no item: your group ("what does my group need" is the group's question, Group.lua), a
-- way somewhere ("how do i get to orgrimmar"). They said "Nothing called 'my group'".
local GROUP_WORDS = { my = true, our = true, the = true, group = true, party = true, raid = true, members = true,
	member = true, groupmates = true, team = true }
-- (words that point at something without naming it: "my mats", "where to get it", "what drops here")
local POINTERS = { my = true, our = true, the = true, it = true, its = true, there = true, here = true, this = true, that = true,
	these = true, those = true, them = true, me = true, money = true }
function P.NotAName(what)
	-- (a way somewhere, "to orgrimmar", "into mc": not an item)
	if what == "to" or what:find("^to ") or what == "into" or what:find("^into ") or what:find("^in ") then return true end
	local pointing = true
	for w in what:gmatch("%S+") do if not POINTERS[w] then pointing = false break end end
	if pointing then return true end
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
	local name = ns.ItemName(id)
	if name then return name end
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
-- (the game's own bags are opened by the game's press, never from here: Bags.lua's Bags.Pressed)
local Pressed = ns.Bags.Pressed

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
				out[#out + 1] = Pressed({
					key = id, kind = "reagent", kindLabel = REAGENT_LABEL, freqKey = "reagent:" .. id,
					name = name, itemID = id, link = "item:" .. id, icon = Icon(id),
					color = ns.QualityHex and ns.QualityHex(q) or nil,
					detail = table.concat(parts, ns.DETAIL_SEP), need = n, count = bags, total = all + elsewhere,
					-- short on this character first (what to go and get), then in the recipe's order
					_order = ((all >= n) and 1000 or 0) + i,
				}, ShowItem)
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

-- drops, sells: what an NPC drops (AtlasLoot's loot of a boss by that name; any other creature: the items whose Questie
-- npcDrops list it) and what a vendor sells (the items whose Questie vendors list it). "what does hogger drop", "what
-- does innkeeper farley sell" (Advanced: "hogger > drops", "farley > sells"). (@loot's rows by their boss's lowercase
-- name, and the bosses by instance, made once a loot list. Only loot that drops: AtlasLoot's faction, crafting, PvP and
-- collection pages name a standing or a profession where a boss goes, "Honored @ Argent Dawn")
local bossBy, bossFrom, bossPlaces
local NOT_DROPS = { reputation = true, crafted = true, pvp = true, collection = true }
local function BossLoot()
	local list = Entries("loot")
	if bossFrom ~= list then
		bossBy, bossFrom, bossPlaces = {}, list, {}
		local I = ns.Integrations
		local placeOf = {} -- ("boss\tinstance" -> its place's entry)
		for _, l in ipairs(list) do
			local boss, inst = nil, nil
			if I and I.LootSplit and not (I.LootSource and NOT_DROPS[I.LootSource(l)]) then
				boss, inst = I.LootSplit(rawget(l, "detail") or l.detail)
			end
			if boss and boss ~= "" and boss ~= "?" then
				local k = ns.Lower(boss)
				local t = bossBy[k]
				if not t then t = {}; bossBy[k] = t end
				t[#t + 1] = l
				if inst and inst ~= "" then
					local pk = k .. "\t" .. ns.Lower(inst)
					local pl = placeOf[pk]
					if not pl then
						pl = { boss = boss, inst = inst, linst = ns.Lower(inst), n = 0 }
						placeOf[pk] = pl
						bossPlaces[#bossPlaces + 1] = pl
					end
					pl.n = pl.n + 1
				end
			end
		end
	end
	return bossBy
end
P.BossLoot = BossLoot
--- Every boss with loot, by instance: { { boss, inst, linst (lowercase), n (items) } } (Trash Mobs once per instance).
function P.BossPlaces()
	BossLoot()
	return bossPlaces or {}
end
--- Do these (lowercase) words name an NPC Questie knows, or a boss AtlasLoot lists? (Questie's names text, not the NPC
--- list: asked on a keystroke, it built the list and kept it from being let go)
function P.NpcNamed(what)
	if BossLoot()[what] then return true end
	local I = ns.Integrations
	return (I and I.NpcIdNamed and I.NpcIdNamed(what)) ~= nil
end
--- Do these (lowercase) words name a quest Questie knows: its whole name, or the start of one (four letters or more)?
--- (The quests' names kept once a list.)
local questNames, questNamesFrom
function P.QuestNamed(what)
	local I = ns.Integrations
	local list = I and I.qdb and I.qdb.list
	if type(list) ~= "table" then return false end
	if questNamesFrom ~= list then
		questNames, questNamesFrom = {}, list
		for _, e in ipairs(list) do
			local n = rawget(e, "_lname") or (type(e.name) == "string" and ns.Lower(e.name)) or nil
			-- (its letters and numbers: 'Wanted: "Hogger"' is said "wanted hogger")
			if n then questNames[#questNames + 1] = (n:gsub("[^%w%s\128-\255]", ""):gsub("%s+", " ")) end
		end
		table.sort(questNames)
	end
	what = what:gsub("[^%w%s\128-\255]", ""):gsub("%s+", " ")
	if what == "" then return false end
	-- (sorted: the first name at or after the words is the one they start, if any)
	local lo, hi = 1, #questNames
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		if questNames[mid] < what then lo = mid + 1 else hi = mid - 1 end
	end
	local n = questNames[lo]
	if not n then return false end
	if n == what then return true end
	if n:sub(1, #what) == what and #what >= 4 then return true end
	-- ("the defias brotherhood" said without "the")
	local t = "the " .. what
	lo, hi = 1, #questNames
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		if questNames[mid] < t then lo = mid + 1 else hi = mid - 1 end
	end
	n = questNames[lo]
	return n ~= nil and n:sub(1, #t) == t
end
-- (the last words of an NPC's role said, not a thing: "flight master", "mage trainer", "quest giver")
local ROLE_LAST = { trainer = true, trainers = true, master = true, masters = true, giver = true, givers = true,
	keeper = true, keepers = true, healer = true, healers = true, house = true, houses = true }
--- Do these (lowercase) words name an NPC or a place rather than a thing ("where do i find hogger", "where can i find
--- the stockade": where they are, not sources)?
function P.NotAThing(what)
	if P.NpcNamed(what) then return true end
	-- (an NPC's role or a kind of object: where the nearest is, not its sources: "where do i find an innkeeper", "where
	-- can i find a mailbox", "where do i find the auction house")
	local E, I0 = ns.Easy, ns.Integrations
	if (E and E.ROLE_WORDS and E.ROLE_WORDS[what]) or (E and E.PROF_PEOPLE and E.PROF_PEOPLE[what])
		or (I0 and I0.OBJECT_KINDS and I0.OBJECT_KINDS[what]) or ROLE_LAST[what:match("(%S+)$") or ""] then return true end
	local I = ns.Integrations
	if I and I.FindPlace then
		local words = {}
		for w in what:gmatch("%S+") do words[#words + 1] = w end
		local place, rest = I.FindPlace(words)
		if place and (not rest or #rest == 0) then return true end
	end
	return false
end
--- An item's row in a chain's answer (what an NPC drops or sells, what a quest rewards), or nil while its name loads.
local function NpcItemRow(id, detail, how)
	local name = ItemName(id)
	if not name then return nil end
	local q = C_Item and C_Item.GetItemQualityByID and Safe(C_Item.GetItemQualityByID, id)
	return Pressed({ key = id, kind = "reagent", kindLabel = SOURCE_LABEL, freqKey = "reagent:" .. id, name = name, itemID = id,
		link = "item:" .. id, icon = Icon(id), color = ns.QualityHex and ns.QualityHex(q) or nil, detail = detail,
		pipeHow = how }, ShowItem)
end
P.ItemRow = NpcItemRow
local function NpcOf(e) return e.kind == "npc" and (e.npcID or rawget(e, "key")) or nil end
ns:RegisterRelation("drops", {
	aliases = { "drop", "loot", "dropped" },
	desc = L["what an NPC drops: a boss's loot (AtlasLoot), a creature's (Questie)"],
	seedKinds = { "npc" },
	applies = function(e) return NpcOf(e) ~= nil end,
	run = function(rows)
		local out, seen = {}, {}
		local I = ns.Integrations
		for _, e in ipairs(rows) do
			local name = tostring(e.name)
			for _, l in ipairs(BossLoot()[ns.Lower(name)] or {}) do
				if #out >= P.MAX_OUT then break end
				if not seen[l.itemID] then seen[l.itemID] = true; out[#out + 1] = l end
			end
			local ids, busy = I and I.NpcItems and I.NpcItems(NpcOf(e), "drops")
			if busy then P.loading = true end
			for _, id in ipairs(ids or {}) do
				if #out >= P.MAX_OUT then break end
				if not seen[id] then
					local r = NpcItemRow(id, L["Drops from %s"]:format(name), L["dropped by %s"]:format(name))
					if r then seen[id] = true; out[#out + 1] = r end
				end
			end
		end
		return out
	end,
})
ns:RegisterRelation("sells", {
	aliases = { "sold", "stock", "wares", "vendor" },
	desc = L["what a vendor sells (Questie)"],
	available = function() return ns.providers.npc ~= nil end, addon = "Questie",
	seedKinds = { "npc" },
	applies = function(e) return NpcOf(e) ~= nil end,
	run = function(rows)
		local out, seen = {}, {}
		local I = ns.Integrations
		for _, e in ipairs(rows) do
			local name = tostring(e.name)
			local ids, busy = I and I.NpcItems and I.NpcItems(NpcOf(e), "sold")
			if busy then P.loading = true end
			for _, id in ipairs(ids or {}) do
				if #out >= P.MAX_OUT then break end
				if not seen[id] then
					local r = NpcItemRow(id, L["Sold by %s"]:format(name), L["Sold by %s"]:format(name))
					if r then seen[id] = true; out[#out + 1] = r end
				end
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
-- List.lua's NavTick); no known spot on your continent: just what it is
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
--- to both, or not known, isn't)? Sellers are only the ones you can buy from.
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
P.ARTICLES = { "the ", "a ", "an " } -- (a name's own, put back when it's looked up by name: P.Seed)
P.NPCS_LOOKED = 400 -- (the NPCs of one list looked at for their distance: a world drop names hundreds)

-- an item's NPCs Questie lists in `field` (vendors, npcDrops), the nearest `max`, as views saying what they are to it
-- and how far ("  ·  120 yd"); `friendly`: only those friendly to you (sellers)
-- (friendly: only those who'd serve you; none would: those who wouldn't, said so (`others`, "Sells it to the other
-- faction only"), not "Nowhere known to get it": 0.68.17, a Horde quartermaster's armour asked for by an Alliance player)
local function AddNpcList(out, I, list, what, max, how, friendly, others)
	if type(list) ~= "table" or not I.NpcRow then return end
	local here = I.Here and I.Here() or nil
	local got, theirs = {}, {}
	for k, nid in ipairs(list) do
		if k > P.NPCS_LOOKED then break end
		local row = type(nid) == "number" and I.NpcRow and I.NpcRow(nid)
		if row then
			local mine = not friendly or P.Friendly(row)
			if mine or (others and #theirs < max) then
				local d = here and I.NpcDistance and I.NpcDistance(nid, here) or nil
				local t = mine and got or theirs
				t[#t + 1] = { row = row, d = d, i = k }
			end
		end
	end
	if #got == 0 and #theirs > 0 then got, what = theirs, others end
	table.sort(got, NearFirst)
	for k = 1, math.min(#got, max) do
		local g = got[k]
		local rest = what .. ((g.row.detail and g.row.detail ~= "") and (ns.DETAIL_SEP .. tostring(g.row.detail)) or "")
		out[#out + 1] = NearSaid(View(g.row, rest, nil, how), g.d, rest)
	end
end
--- NPCs by id (Questie's NPC rows), the nearest `max`, each a view saying `what` it is to the item and how far; the
--- sources' other definitions' (OneForAll's skinning, Providers/Integrations/OneForAll/Reagents.lua).
P.AddNpcs = AddNpcList
local function AddNpcs(out, I, id, field, ...) return AddNpcList(out, I, I.ItemField(id, field), ...) end

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
	found = L["Gathered or found here"], gathered = L["gathered from"], quest = L["A quest's reward"], reward = L["a reward from"],
	theirs = L["Sells it to the other faction only"], contains = L["Contains it"], foundIn = L["found in"] }
P.RECIPE_WORDS = { sells = L["Sells the recipe"], sold = L["the recipe is sold by"], drops = L["Drops the recipe"],
	dropped = L["the recipe drops from"], found = L["The recipe is found here"], gathered = L["the recipe is found in"],
	quest = L["The recipe is a quest's reward"], reward = L["the recipe is a reward from"],
	theirs = L["Sells the recipe to the other faction only"] }

-- an item's sellers and droppers, the veins/herbs/chests it's found in (by name, once each, at the spot nearest you)
-- and the quests rewarding it, from Questie, said in `w`'s words
local function AddQuestie(out, I, id, w)
	AddNpcs(out, I, id, "vendors", w.sells, 15, w.sold, true, w.theirs) -- (only those who'd sell to you)
	AddNpcs(out, I, id, "npcDrops", w.drops, 15, w.dropped)
	local objs = I.ItemField(id, "objectDrops")
	if type(objs) == "table" and I.ObjectName then AddObjects(out, I, objs, w.found, w.gathered) end
	-- (the items it comes out of: clams, lockboxes, bags, QuestieDB's itemDrops; Enter on one: where to get that)
	local boxes = w.contains and I.ItemField(id, "itemDrops")
	if type(boxes) == "table" then
		for k, bid in ipairs(boxes) do
			if k > 15 then break end
			local r = type(bid) == "number" and bid ~= id and NpcItemRow(bid, w.contains, w.foundIn)
			if r then out[#out + 1] = r end
		end
	end
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
					out[#out + 1] = Pressed({
						key = "craft:" .. id, kind = "source", kindLabel = SOURCE_LABEL, name = name, itemID = id,
						link = "item:" .. id, icon = Icon(id), reagents = rg,
						detail = L["Crafted"] .. (sname and (ns.DETAIL_SEP .. sname) or "") .. ns.DETAIL_SEP .. L["(a recipe you don't have)"], pipeHow = L["crafted:"],
					}, ShowItem)
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

-- (ChainLearn.lua's and ChainRun.lua's: the learn relation and the running of a chain read these)
P._ = { Entries = Entries, ItemOf = ItemOf, ItemName = ItemName, Icon = Icon, AtlasCraft = AtlasCraft, LootIndex = LootIndex,
	OwnRecipes = OwnRecipes, StoredByID = StoredByID, SOURCE_LABEL = SOURCE_LABEL, REAGENT_LABEL = REAGENT_LABEL,
	ShowItem = ShowItem, View = View, NearSaid = NearSaid, AddQuestie = AddQuestie, SimpleOn = SimpleOn }
