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
P.LABELS = { mats = "mats", uses = "used in", sources = "sources", alts = "alts" }

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
	{ "^where to get (.+)$", "sources" }, { "^where do i get (.+)$", "sources" }, { "^where can i get (.+)$", "sources" },
	{ "^where to buy (.+)$", "sources" }, { "^where can i buy (.+)$", "sources" }, { "^how to get (.+)$", "sources" },
	{ "^how do i get (.+)$", "sources" }, { "^sources? for (.+)$", "sources" }, { "^sources? of (.+)$", "sources" },
	{ "^where does (.+) drop$", "sources" }, { "^who sells (.+)$", "sources" }, { "^what drops (.+)$", "sources" },
}

P.FIRST, P.LAST = {}, {}
for _, ph in ipairs(P.PHRASES) do
	local f = ph[1]:match("^%^(%a[%a']*)")
	if f then P.FIRST[f] = true end
	local l = ph[1]:match("(%a+)%$$")
	if l then P.LAST[l] = true end
end
P.FIRST.mat, P.FIRST.material, P.FIRST.reagent, P.FIRST.use, P.FIRST.source = true, true, true, true, true

--- The chain a line means: the line itself when it has links, the chain its plain words say ("mats for x" ->
--- "x > mats"), else nil.
function P.Canonical(text)
	if type(text) ~= "string" then return nil end
	if P.Split(text) then
		-- (only a ">" standing alone, and not Advanced's other syntax using ">")
		return text:gsub("^%s+", ""):gsub("%s+$", "")
	end
	if text:find("[@:>|]") or text:find("^%s*[%./!%-]") then return nil end
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

local function View(e, detail, label)
	return setmetatable({ detail = detail, kindLabel = label or nil }, { __index = e })
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
				out[#out + 1] = View(own, "Crafted  ·  your recipe" .. (own.detail and ("  ·  " .. own.detail) or ""), SOURCE_LABEL)
			else
				local rg, spell = AtlasCraft(id)
				if rg then
					local sname = spell and C_Spell and C_Spell.GetSpellName and Safe(C_Spell.GetSpellName, spell)
					out[#out + 1] = {
						key = "craft:" .. id, kind = "source", kindLabel = SOURCE_LABEL, name = name, itemID = id,
						link = "item:" .. id, icon = Icon(id), reagents = rg,
						detail = "Crafted" .. (sname and ("  ·  " .. sname) or "") .. "  ·  (a recipe you don't have)",
						activate = ShowItem,
					}
				end
			end
			if I and I.ItemField then
				local function Npcs(field, what, max)
					local list = I.ItemField(id, field)
					if type(list) ~= "table" then return end
					local n = 0
					for _, nid in ipairs(list) do
						local row = type(nid) == "number" and I.NpcRow and I.NpcRow(nid)
						if row then
							out[#out + 1] = View(row, what .. "  ·  " .. tostring(row.detail or ""))
							n = n + 1
							if n >= max then break end
						end
					end
				end
				Npcs("vendors", "Sells it", 15)
				Npcs("npcDrops", "Drops it", 15)
				-- gathered or found: veins, herbs, chests (by name, once each)
				local objs = I.ItemField(id, "objectDrops")
				if type(objs) == "table" and I.ObjectName then
					local seen = {}
					for _, oid in ipairs(objs) do
						local oname = type(oid) == "number" and I.ObjectName(oid)
						if oname and not seen[oname] then
							seen[oname] = true
							out[#out + 1] = { key = "obj:" .. oname, kind = "source", kindLabel = SOURCE_LABEL, name = oname,
								detail = "Gathered or found here", icon = "Interface\\Icons\\INV_Ore_Copper_01", noActivate = true }
						end
					end
				end
				local quests = I.ItemField(id, "questRewards")
				if type(quests) == "table" and I.QuestRow then
					for _, qid in ipairs(quests) do
						local q = type(qid) == "number" and I.QuestRow(qid)
						if q then out[#out + 1] = View(q, "A quest's reward  ·  " .. tostring(q.detail or "")) end
					end
				end
			end
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

-- a row's name score for every word (nil: some word doesn't match)
local function NameScore(e, tokens)
	local ln = rawget(e, "_lname") or (type(e.name) == "string" and ns.Lower(e.name)) or ""
	local sum = 0
	for _, tk in ipairs(tokens) do
		local s = ns.Fuzzy.score(tk, ln, ln)
		if not s then return nil end
		sum = sum + s
	end
	return sum, ln
end

P.SEED_KINDS = { "recipes", "items", "loot", "stored" }

--- Where a chain starts: rows of your recipes, bags, AtlasLoot and alts whose names have the words (an @kind picks the
--- lists, key:value filters narrow them). An exact name keeps only those rows (or "mats for thorium belt" would add up
--- every belt); else the best match, or with only filters typed, every row that passes.
function P.Seed(text)
	local kinds, filters, words = {}, {}, {}
	for w in (text or ""):gmatch("%S+") do
		if w:sub(1, 1) == "@" and #w > 1 then
			local id = ns.aliasMap and ns.aliasMap[ns.Lower(w:sub(2))]
			if id then kinds[#kinds + 1] = id else words[#words + 1] = w end
		else
			local f = (w:find("[:|]") or w:find("^[-!]%a")) and ns.Filters and ns.Filters.Parse(w)
			if f then filters[#filters + 1] = f else words[#words + 1] = w end
		end
	end
	if #kinds == 0 then kinds = P.SEED_KINDS end
	local tokens = Tokens(table.concat(words, " "))
	local whole = table.concat(tokens, " ")
	local scored, exact = {}, {}
	for _, kind in ipairs(kinds) do
		for _, e in ipairs(Entries(kind)) do
			if not (e.noActivate or e.raw) then
				local s, ln = 0, nil
				if #tokens > 0 then s, ln = NameScore(e, tokens) end
				if s then
					local ok = true
					for _, f in ipairs(filters) do
						local okF, yes = pcall(f, e)
						if not (okF and yes) then ok = false break end
					end
					if ok then
						scored[#scored + 1] = { e = e, s = s }
						if ln and ln == whole then exact[#exact + 1] = e end
					end
				end
			end
		end
	end
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
	if #exact > 0 then return Once(exact) end
	-- nothing of yours by that name: an item the game or Questie knows by exactly that name (a reagent you don't
	-- carry: "where to get copper ore")
	if #scored == 0 and whole ~= "" then
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
		if #out > 0 then return Once(out) end
	end
	table.sort(scored, function(a, b) return a.s > b.s end)
	if #tokens == 0 then
		local all = {}
		for _, x in ipairs(scored) do all[#all + 1] = x.e end
		return Once(all)
	end
	return scored[1] and { scored[1].e } or {}
end

-- what walking on from a row means: a reagent -> where to get it; a recipe or crafted item -> its mats
local function NextOf(e, from)
	if e.kind == "reagent" then return "sources" end
	if from ~= "mats" and P.Reagents(e) then return "mats" end
end

local function Walk(v)
	local UI = ns.UI
	local t = v.pipeChain
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
		pipeChain = chain .. " " .. name .. " > " .. nxt, pipeNext = nxt, pipeOf = e,
		activate = Walk, staysOpen = true, secure = false, isOpen = false, after = false,
		secondary = Opens, secondarySecure = e.secure or false, secondaryIsOpen = e.isOpen or false,
		secondaryAfter = e.after or false, secondaryStaysOpen = false,
	}, { __index = e })
end

local function Line(text) return { name = text, kind = "pipe", noActivate = true, raw = true, _score = 1e12 } end
local function PickRelation(e) local UI = ns.UI UI:SetQuery(e.completion, #e.completion) end

--- Runs a chain: rows, and the footer's trail ("thorium belt > mats > thorium bar > sources").
-- each part's rows, by the chain up to it: typing on in the last part doesn't redo the ones before it (kept while
-- no list was rebuilt and nothing was still loading)
local stepCache, stepGen = {}, -1
local function Cached(key) if stepGen == ns.entriesGen then return stepCache[key] end end
local function Keep(key, rows)
	if P.loading then return end
	if stepGen ~= ns.entriesGen then stepCache, stepGen = {}, ns.entriesGen end
	stepCache[key] = rows
end
P.ClearSteps = function() stepCache, stepGen = {}, -1 end

function P.Search(chain)
	local stages = P.Split(chain)
	if not stages then return {}, nil end
	P.loading = false
	local trail = { (stages[1].text:gsub("^%s+", ""):gsub("%s+$", "")) }
	-- (a name still being typed: "where to get t" would match half of AtlasLoot)
	local letters = #(stages[1].text:gsub("@%S+", ""):gsub("%S+:%S*", ""):gsub("[%s%p]", ""))
	if letters < 3 and not stages[1].text:find("[@:]") then
		return { Line("Keep typing the name: " .. trail[1]) }, trail[1]
	end
	local key = ns.Lower(trail[1])
	local rows = Cached(key)
	if not rows then
		rows = P.Seed(stages[1].text)
		Keep(key, rows)
	end
	if #rows == 0 then
		return { Line(("Nothing called \"%s\" in your bags, recipes, AtlasLoot or alts"):format(trail[1])) }, trail[1]
	end
	local from
	-- (walking on from the last part's rows: the chain up to its link word, then the row's name)
	local base = chain:sub(1, (chain:find(">[^>]*$"))) .. " " .. (stages[#stages].word or "")
	for i = 2, #stages do
		local s = stages[i]
		local name = P.Find(s.word)
		if not name then
			-- still being typed (or not one): the relations these rows can go through, to pick from
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
			if #out == 0 then out[1] = Line(("No link called \"%s\": mats, uses, sources, alts"):format(s.word or "")) end
			trail[#trail + 1] = "?"
			return out, table.concat(trail, " > ")
		end
		key = key .. " > " .. name
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
			local kept = {}
			for _, e in ipairs(rows) do
				local sc = NameScore(e, tokens)
				if sc then kept[#kept + 1] = { e = e, s = sc } end
			end
			table.sort(kept, function(a, b) return a.s > b.s end)
			rows = {}
			for _, k in ipairs(kept) do rows[#rows + 1] = k.e end
			trail[#trail + 1] = (s.rest:gsub("^%s+", ""):gsub("%s+$", ""))
			if i < #stages then from = nil end -- (narrowed to a row: the next link starts from it)
		end
		if #rows == 0 then
			return { Line("Nothing there: " .. table.concat(trail, " > ")) }, table.concat(trail, " > ")
		end
	end
	local out = {}
	for i, e in ipairs(rows) do
		local v = (#stages > 1) and P.WalkView(e, base, from) or e
		if v == e then v = setmetatable({}, { __index = e }) end
		v._score = 1e6 - i
		out[#out + 1] = v
	end
	return out, table.concat(trail, " > ")
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
		lines[#lines + 1] = "In plain words: mats for thorium belt, what uses copper bar, where to get thorium bar, who sells mageweave."
		return lines
	end,
})
