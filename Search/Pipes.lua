local ns = select(2, ...)

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
P.LABELS = { mats = "mats", uses = "used in", sources = "sources", alts = "alts", learn = "learn" }

--- The relation's name for a typed word (its name or an alias), or nil.
function P.Find(word)
	if type(word) ~= "string" or word == "" then return nil end
	local w = ns.Lower(word)
	for _, name in ipairs(P.order) do
		if w == name then return name end
		for _, def in ipairs(P.relations[name]) do
			for _, a in ipairs(def.aliases) do
				if w == a then return name end
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
	{ "^where is (.+) taught$", "learn" }, { "^where to get the recipe for (.+)$", "learn" },
	{ "^where is the recipe for (.+)$", "learn" }, { "^recipe sources? for (.+)$", "learn" },
	{ "^where to get (.+)$", "sources" }, { "^where do i get (.+)$", "sources" }, { "^where can i get (.+)$", "sources" },
	{ "^where to buy (.+)$", "sources" }, { "^where can i buy (.+)$", "sources" }, { "^how to get (.+)$", "sources" },
	{ "^how do i get (.+)$", "sources" }, { "^sources? for (.+)$", "sources" }, { "^sources? of (.+)$", "sources" },
	{ "^where does (.+) drop$", "sources" }, { "^who sells (.+)$", "sources" }, { "^what drops (.+)$", "sources" },
}

-- Simple mode's words for a one-link chain (it never shows ">"): what Enter writes and what the footer says
P.SIMPLE = { mats = "mats for %s", uses = "what uses %s", sources = "where to get %s", learn = "where to learn %s" }
P.SIMPLE_LABEL = { mats = "Mats for %s", uses = "What uses %s", sources = "Where to get %s", alts = "%s on your alts",
	learn = "Where to learn %s", ["?"] = "Which %s?" }

local function SimpleOn() return ns.Easy and ns.Easy.On and ns.Easy.On() end

--- The line that asks for `rel` of `name`: Simple mode's words ("mats for Thorium Bar"), else the chain ("Thorium Bar >
--- mats").
function P.Phrase(name, rel)
	local f = SimpleOn() and P.SIMPLE[rel]
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

--- The chain a line means: the line itself when it has links, the chain its plain words say ("mats for x" ->
--- "x > mats"), else nil. `words`: only the plain words (Simple mode: a ">" typed there is Advanced syntax, refused
--- like an @kind, 0.45.13).
function P.Canonical(text, words)
	if type(text) ~= "string" then return nil end
	if P.Split(text) then
		if words then return nil end
		-- (only a ">" standing alone, and not Advanced's other syntax using ">")
		return text:gsub("^%s+", ""):gsub("%s+$", "")
	end
	-- (Advanced syntax isn't a phrase: @kind, key:value, | and > in filters; a ":" before a space is a name's own,
	-- "where to get Pattern: Linen Belt")
	if text:find("[@>|]") or text:find(":[^%s]") or text:find("^%s*[%./!%-]") then return nil end
	-- (cheap first: every phrase starts or ends with one of these words; this runs on every search)
	local first, last = text:match("^%s*(%S+)"), text:match("(%S+)%s*$")
	if not first or not (P.FIRST[first:lower()] or P.LAST[last:lower()]) then return nil end
	local lt = ns.Lower(text):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	for _, ph in ipairs(P.PHRASES) do
		local what = lt:match(ph[1])
		if what and what:find("%S") then
			what = what:gsub("^the ", ""):gsub("^a ", ""):gsub("^an ", "")
			return what .. " > " .. ph[2]
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local Safe = ns.Safe
local function Entries(id)
	local p = ns.providers[id]
	return p and ns:GetEntries(p) or {}
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

local REAGENT_LABEL = "|cffd9b26aReagent|r"
local SOURCE_LABEL = "|cffd9b26aSource|r"
local function ShowItem(e)
	if not (ns.Bags and ns.Bags.ShowItem(e.itemID, e.link, e.name)) then ns:Print("You don't carry " .. tostring(e.name) .. ".") end
end

----------------------------------------------------------------------
-- Relations
----------------------------------------------------------------------

-- mats: the reagents (several rows: what they need together)
ns:RegisterRelation("mats", {
	aliases = { "reagents", "reagent", "materials", "mat" },
	desc = "its reagents, with how many you have",
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
				local parts = { ("need %d"):format(n), ("have %d"):format(bags) }
				if all > bags then parts[#parts] = parts[#parts] .. (" (+%d bank)"):format(all - bags) end
				if elsewhere > 0 then parts[#parts + 1] = ("%d on alts"):format(elsewhere) end
				local q = C_Item and C_Item.GetItemQualityByID and Safe(C_Item.GetItemQualityByID, id)
				out[#out + 1] = {
					key = id, kind = "reagent", kindLabel = REAGENT_LABEL, freqKey = "reagent:" .. id,
					name = name, itemID = id, link = "item:" .. id, icon = Icon(id),
					color = ns.QualityHex and ns.QualityHex(q) or nil,
					detail = table.concat(parts, "  ·  "), need = n, count = bags, total = all + elsewhere,
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
	desc = "what it goes into",
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

-- an item's NPCs Questie lists in `field` (vendors, npcDrops), `max` at most, as views saying what they are to it
local function AddNpcs(out, I, id, field, what, max, how)
	local list = I.ItemField(id, field)
	if type(list) ~= "table" then return end
	local n = 0
	for _, nid in ipairs(list) do
		local row = type(nid) == "number" and I.NpcRow and I.NpcRow(nid)
		if row then
			out[#out + 1] = View(row, what .. "  ·  " .. tostring(row.detail or ""), nil, how)
			n = n + 1
			if n >= max then break end
		end
	end
end

-- a vein or chest with no known spot: said so (the row is still one to send: "gathered from Copper Vein")
local function NoSpot(e) ns:Print("No known spot for " .. tostring(e.name) .. ".") end

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
	for _, oname in ipairs(order) do
		local row = { key = "obj:" .. oname, kind = "source", kindLabel = SOURCE_LABEL, name = oname, pipeHow = how or "gathered from",
			icon = "Interface\\Icons\\INV_Ore_Copper_01", detail = what or "Gathered or found here", activate = NoSpot, found = true }
		local spot = I.NearestSpawn and I.NearestSpawn(byName[oname], here)
		if spot and ns.Maps then
			row.ui, row.mapID, row.px, row.py, row.zone = spot.ui, spot.ui, spot.px, spot.py, spot.zone
			row.wcont, row.wx, row.wy = spot.wcont, spot.wx, spot.wy
			row.detail = row.detail .. "  ·  " .. (spot.d and ("%.0f yd  "):format(spot.d) or "") .. tostring(spot.zone or "")
			row.secure, row.isOpen, row.after = ns.Maps.SECURE, ns.Maps.IsOpenFor, I.SpotAfter
			row.activate, row.secondary = I.PinObject, I.PinObject
		end
		out[#out + 1] = row
	end
end

-- what each kind of source is to the thing looked for, in the list and in chat ("Sells it" / "sold by"): an item's
-- own, or (where to learn a recipe) its recipe item's
P.ITEM_WORDS = { sells = "Sells it", sold = "sold by", drops = "Drops it", dropped = "dropped by",
	found = "Gathered or found here", gathered = "gathered from", quest = "A quest's reward", reward = "a reward from" }
P.RECIPE_WORDS = { sells = "Sells the recipe", sold = "the recipe is sold by", drops = "Drops the recipe",
	dropped = "the recipe drops from", found = "The recipe is found here", gathered = "the recipe is found in",
	quest = "The recipe is a quest's reward", reward = "the recipe is a reward from" }

-- an item's sellers and droppers, the veins/herbs/chests it's found in (by name, once each, at the spot nearest you)
-- and the quests rewarding it, from Questie, said in `w`'s words
local function AddQuestie(out, I, id, w)
	AddNpcs(out, I, id, "vendors", w.sells, 15, w.sold)
	AddNpcs(out, I, id, "npcDrops", w.drops, 15, w.dropped)
	local objs = I.ItemField(id, "objectDrops")
	if type(objs) == "table" and I.ObjectName then AddObjects(out, I, objs, w.found, w.gathered) end
	local quests = I.ItemField(id, "questRewards")
	if type(quests) == "table" and I.QuestRow then
		for _, qid in ipairs(quests) do
			local q = type(qid) == "number" and I.QuestRow(qid)
			if q then out[#out + 1] = View(q, w.quest .. "  ·  " .. tostring(q.detail or ""), nil, w.reward) end
		end
	end
end

-- sources: where to get an item (crafted, sold, dropped, gathered, a quest's reward, AtlasLoot's bosses, your alts)
ns:RegisterRelation("sources", {
	aliases = { "source", "get", "where", "from" },
	desc = "where to get it",
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
				out[#out + 1] = View(own, "Crafted  ·  your recipe" .. (own.detail and ("  ·  " .. own.detail) or ""), SOURCE_LABEL, "crafted:")
			else
				local rg, spell = AtlasCraft(id)
				if rg then
					local sname = spell and C_Spell and C_Spell.GetSpellName and Safe(C_Spell.GetSpellName, spell)
					out[#out + 1] = {
						key = "craft:" .. id, kind = "source", kindLabel = SOURCE_LABEL, name = name, itemID = id,
						link = "item:" .. id, icon = Icon(id), reagents = rg,
						detail = "Crafted" .. (sname and ("  ·  " .. sname) or "") .. "  ·  (a recipe you don't have)", pipeHow = "crafted:",
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
			if stored[id] then out[#out + 1] = View(stored[id], "On your alts  ·  " .. tostring(stored[id].detail or "")) end
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
	if e.kind == "recipes" and type(e.recipeID) == "number" then return e.recipeID, id end
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
		local detail = "Teaches it" .. (t.title ~= "" and ("  ·  " .. t.title) or "") .. (t.d and ("  ·  %.0f yd"):format(t.d) or "")
		out[#out + 1] = View(t.e, detail, nil, "taught by")
	end
end

-- the recipe item: where to get it (Questie, AtlasLoot's bosses, your alts)
local function AddRecipeItem(out, rid, prof, need, stored)
	local skill = prof and need and ("  ·  " .. ProfName(prof) .. " " .. need) or ""
	out[#out + 1] = { key = "recipe:" .. rid, kind = "source", kindLabel = SOURCE_LABEL, name = ItemName(rid) or ("item " .. rid),
		itemID = rid, link = "item:" .. rid, icon = Icon(rid), detail = "Teaches it" .. skill, pipeHow = "taught by",
		activate = ShowItem }
	local I = ns.Integrations
	if I and I.ItemField then AddQuestie(out, I, rid, P.RECIPE_WORDS) end
	local by = LootIndex()
	for k, l in ipairs(by[rid] or {}) do
		if k > 15 then break end
		out[#out + 1] = l
	end
	if stored[rid] then out[#out + 1] = View(stored[rid], "Your alts hold the recipe  ·  " .. tostring(stored[rid].detail or "")) end
end

ns:RegisterRelation("learn", {
	aliases = { "learned", "taught", "teach", "teaches", "trainer", "trainers", "recipesource" },
	desc = "where to learn the recipe: its recipe item, or a trainer",
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
			if own then out[#out + 1] = View(own, "You know it" .. (own.detail and ("  ·  " .. own.detail) or "")) end
			rid = rid or (Rc and Rc.GetRecipeForSpell and Safe(Rc.GetRecipeForSpell, spell)) or nil
			if type(rid) == "number" then
				AddRecipeItem(out, rid, prof, need, stored)
			elseif data then
				-- AtlasLoot knows the craft but no recipe item for it: a trainer teaches it
				local pname = prof and ProfName(prof) or nil
				out[#out + 1] = { key = "trainer:" .. spell, kind = "source", kindLabel = SOURCE_LABEL, noActivate = true,
					name = pname and ("Taught by a " .. pname .. " trainer") or "Taught by a trainer",
					icon = "Interface\\Icons\\INV_Misc_Book_11",
					detail = "No recipe item teaches it (AtlasLoot)" .. (pname and need and ("  ·  learn at " .. pname .. " " .. need) or "") }
				if prof then AddTrainers(out, prof, need) end
			end
		end
		return out
	end,
})

-- alts: who holds an item on your alts, in banks, the mail...
ns:RegisterRelation("alts", {
	aliases = { "stored", "who", "bank", "holders" },
	desc = "who holds it on your alts and banks",
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
	if k == nil then return e end
	return tostring(e.kind) .. ":" .. tostring(k)
end

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
		for _, def in ipairs(P.relations[name]) do
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

P.SEED_KINDS = { "recipes", "items", "loot", "stored" }

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
local function SeedParse(text)
	local kinds, filters, words = {}, {}, {}
	for w in (text or ""):gmatch("%S+") do
		if w:sub(1, 1) == "@" and #w > 1 then
			-- (as the search reads an @kind: its id, an alias or the start of its id)
			local p = ns:ResolveProvider(w:sub(2))
			if p then kinds[#kinds + 1] = p.id else words[#words + 1] = w end
		else
			local f = (w:find("[:|]") or w:find("^[-!]%a")) and ns.Filters and ns.Filters.Parse(w)
			if f then filters[#filters + 1] = f else words[#words + 1] = w end
		end
	end
	if #kinds == 0 then kinds = P.SEED_KINDS end
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
local function SeedByReagentName(whole)
	local ids, out = {}, {}
	for _, r in ipairs(Entries("recipes")) do
		for _, rg in ipairs(r.reagents or {}) do
			local n = type(rg[1]) == "number" and ItemName(rg[1])
			if n and ns.Lower(n) == whole then ids[#ids + 1] = rg[1] end
		end
	end
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
--- (third result: rows, best first).
function P.Seed(text)
	local kinds, filters, tokens, whole = SeedParse(text)
	local from = SeedFrom(kinds, tokens)
	local gen = ns.entriesGen
	local all, exact, subs, near, cands = SeedScan(kinds, filters, tokens, whole, from)
	-- (for the next keystroke: not when a list was rebuilt meanwhile, the rows looked at may be its old ones)
	lastSeed = #tokens > 0 and gen == ns.entriesGen and { gen = gen, kinds = kinds, tokens = tokens, cands = cands } or nil
	if #exact > 0 then return Once(exact) end
	-- nothing of yours by that name: an item the game or Questie knows by exactly that name (a reagent you don't
	-- carry: "where to get copper ore")
	if #subs == 0 and #all == 0 and whole ~= "" then
		local out = SeedByReagentName(whole)
		if #out > 0 then return Once(out) end
	end
	if #tokens == 0 then return Once(all) end -- (only filters typed: every row that passes)
	if #subs == 0 then return {}, near end
	return SeedChoices(subs)
end

-- what walking on from a row means: a reagent -> where to get it; a recipe or crafted item -> its mats
local function NextOf(e, from)
	if e.kind == "reagent" then return "sources" end
	if from ~= "mats" and P.Reagents(e) then return "mats" end
end

local function Walk(v)
	local UI = ns.UI
	local t = v.pipeChain
	-- (Simple mode: the next step in its own words, "where to get Thorium Bar", never a ">" chain)
	if SimpleOn() and v.pipeName and P.SIMPLE[v.pipeNext] then t = P.Phrase(v.pipeName, v.pipeNext) end
	UI:SetQuery(t, #t)
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
local function PickRelation(e) local UI = ns.UI UI:SetQuery(e.completion, #e.completion) end

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
	return (t:gsub("(%a)([%w']*)", function(x, y) return x:upper() .. y end))
end

-- "Keep typing" while the first part has under 3 letters (and no @kind or filter)
local function KeepTyping(stages, trail)
	-- (a name still being typed: "where to get t" would match half of AtlasLoot)
	local letters = #(stages[1].text:gsub("@%S+", ""):gsub("%S+:%S*", ""):gsub("[%s%p]", ""))
	if letters < 3 and not stages[1].text:find("[@:]") then
		return { Line("Keep typing the name: " .. trail[1]) }, trail[1]
	end
end

-- the first part's rows, kept by its text (the closest name or the names to pick from ride on the list)
local function SeedRows(key, stages)
	local rows = Cached(key)
	if not rows then
		local near, choices
		rows, near, choices = P.Seed(stages[1].text)
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
		local out = { Line(("%d names have \"%s\": pick one"):format(rows.choices.total, trail[1])) }
		for i, e in ipairs(rows.choices) do out[#out + 1] = Pick(e, i, oneRel, rest) end
		return out, trail[1] .. " > ?"
	end
	local out = { Line(("Nothing called \"%s\" in your bags, recipes, AtlasLoot or alts"):format(trail[1])) }
	if rows.near then
		local d = Pick(rows.near, 1, oneRel, rest)
		d.name = "Did you mean " .. d.name .. "?"
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
			out[#out + 1] = { name = a[1], kind = "pipe", kindLabel = "|cff33ff99link|r", detail = a[2],
				completion = done, staysOpen = true, activate = PickRelation, _score = 1e6 - #out }
		end
	end
	if #out == 0 then out[1] = Line(("No link called \"%s\": mats, uses, sources, learn, alts"):format(s.word or "")) end
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
P.SIMPLE_NONE = { mats = "No mats for %s: it isn't crafted", uses = "Nothing uses %s", sources = "Nowhere known to get %s",
	alts = "No %s on your alts", learn = "Nowhere known to learn %s" }

local function NothingThere(trail, stages, rel, from)
	local f = SimpleOn() and #stages == 2 and (stages[2].rest or "") == "" and P.SIMPLE_NONE[rel]
	local said = table.concat(trail, " > ")
	if f then return { Line(f:format(from or trail[1])) }, said end
	return { Line("Nothing there: " .. (SimpleOn() and P.SimpleLabel(said) or said)) }, said
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
	desc = "Chains: pass a search on with > (thorium belt > mats, copper bar > uses, mageweave > sources), or in plain words (mats for thorium belt)",
	aliases = { "pipes", "pipe", "links" },
	run = function()
		local lines = { "Chains: a  >  passes what a search found on (Enter on a row walks on, Shift+Enter opens it):" }
		for _, name in ipairs(P.order) do
			local def = P.relations[name][1]
			lines[#lines + 1] = ("  %s%s  -  %s"):format(name, #def.aliases > 0 and (" (" .. table.concat(def.aliases, ", ") .. ")") or "", def.desc)
		end
		lines[#lines + 1] = "In plain words: mats for thorium belt, what uses copper bar, where to get thorium bar, who sells mageweave, where to learn thorium belt."
		return lines
	end,
})
