-- Filters, the parts that keep searches cheap: the caches per item (two generations, so a working set a little over
-- the cap stays kept), type:/slot:/is:equippable from the client's own item data, in: on compact rows (no fields
-- written onto them), and Fuzzy.score's scattered-letters look (the same scores, no string.sub per letter per row).
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local F = ns.Filters
local function P(w) local f = F.Parse(w); assert(f, "not a filter: " .. w); return f end

-- each block: an error is a failure, and what it swapped is put back whatever happens
local function Run(title, fn, restore)
	io.write("[filters parts: " .. title .. "]\n")
	local ok, err = pcall(fn)
	if restore then restore() end
	F.ClearCache()
	if not ok then check(false, title .. ": " .. tostring(err)) end
end

-- How many times `target` (a C function: string.sub, string.lower) is called while fn runs: a call hook, with the
-- run's runaway guard (an instruction count) kept and put back after.
local function CountCalls(target, fn)
	local n = 0
	local hook, mask, count = debug.gethook()
	debug.sethook(function(ev)
		if ev == "count" then error("INSTRUCTION LIMIT HIT") end
		if debug.getinfo(2, "f").func == target then n = n + 1 end
	end, "c", 20000000)
	local ok, err = pcall(fn)
	debug.sethook(hook, mask, count)
	if not ok then error(err, 0) end
	return n
end

do -- the two-generation cache itself
	local G = F._
	Run("two generations: bounded, and what's used stays", function()
		local c = G.Generations(3)
		for i = 1, 3 do G.Keep(c, i, "v" .. i) end
		check(G.Kept(c, 1) == "v1" and G.Kept(c, 3) == "v3" and G.Kept(c, 4) == nil, "kept while the first table has room")
		G.Keep(c, 4, "v4") -- (the first table is full: it becomes the one before)
		check(G.Kept(c, 4) == "v4" and G.Kept(c, 2) == "v2", "a full table becomes the one before; both are read")
		-- 2 was found in the one before: it came back into the current table, so it outlives the next turn
		G.Keep(c, 5, "v5"); G.Keep(c, 6, "v6") -- (current: 4, 2, 5, then full: 6 starts a new one)
		check(G.Kept(c, 2) == "v2" and G.Kept(c, 1) == nil and G.Kept(c, 3) == nil,
			"what was used is still there two turns on; what wasn't is gone")
		local n = 0
		for _ in pairs(c.new) do n = n + 1 end
		for _ in pairs(c.old) do n = n + 1 end
		check(n <= 2 * 3, "never more than two tables' worth: " .. n)
		G.Keep(c, 7, false)
		check(G.Kept(c, 7) == false, "false is kept (an item with no effect text)")
		G.Forget(c)
		check(G.Kept(c, 2) == nil and G.Kept(c, 7) == nil and c.n == 0, "Forget empties both")
	end)
end

do -- item info, stats, effect texts and classes per item: a working set over the cap isn't asked again on every search
	local save = { info = C_Item.GetItemInfo, stats = C_Item.GetItemStats, inst = C_Item.GetItemInfoInstant,
		spell = C_Item.GetItemSpell, desc = C_Spell.GetSpellDescription, cached = C_Item.IsItemDataCachedByID }
	local function Restore()
		C_Item.GetItemInfo, C_Item.GetItemStats, C_Item.GetItemInfoInstant = save.info, save.stats, save.inst
		C_Item.GetItemSpell, C_Spell.GetSpellDescription, C_Item.IsItemDataCachedByID = save.spell, save.desc, save.cached
	end
	local asks = { info = 0, stats = 0, inst = 0, spell = 0 }
	local function Mock()
		C_Item.GetItemInfo = function(id)
			asks.info = asks.info + 1
			if type(id) ~= "number" then return nil end
			return "Item " .. id, "|Hitem:" .. id .. "|h[Item]|h", id % 5, 20, 10, "Armor", "Mail", 1, "INVTYPE_WRIST", 1, 1, 4, 3, 2
		end
		C_Item.GetItemStats = function() asks.stats = asks.stats + 1 return { ITEM_MOD_STAMINA_SHORT = 3 } end
		C_Item.GetItemInfoInstant = function(id) asks.inst = asks.inst + 1 return id, "Consumable", "Food & Drink", "", 1, 0, 5 end
		C_Item.GetItemSpell = function(id) asks.spell = asks.spell + 1 return "spell", 500000 + id end
		C_Spell.GetSpellDescription = function() return "Well fed: gain 6 Stamina for 15 min." end
		C_Item.IsItemDataCachedByID = nil
	end
	local function Pass(f, from, n)
		local rows = {}
		for i = 1, n do rows[i] = { itemID = from + i } end
		local hits = 0
		for i = 1, n do if f(rows[i]) then hits = hits + 1 end end
		return hits
	end
	Run("item info: a working set a little over the cap", function()
		Mock()
		local f = P("q:3")
		F.ClearCache()
		asks.info = 0
		Pass(f, 10000, 3000); Pass(f, 10000, 3000)
		check(asks.info == 3000, "well under the cap: each item asked once: " .. asks.info)
		-- 10% over the cap: a wipe at the cap emptied everything and every item was asked again on every search
		F.ClearCache()
		local N = 4400
		asks.info = 0
		local first = Pass(f, 20000, N)
		check(asks.info == N, "the first look asks for each: " .. asks.info)
		asks.info = 0
		local again = Pass(f, 20000, N)
		check(again == first, "the same answers")
		check(asks.info <= N - 4000, "the next search over the same items asks for few of them again (" .. asks.info .. " of " .. N .. ")")
		asks.info = 0
		Pass(f, 20000, N)
		check(asks.info <= N - 4000, "and the one after it too (" .. asks.info .. ")")
	end, Restore)
	Run("stats: a working set a little over the cap", function()
		Mock()
		local f = P("stat:sta")
		F.ClearCache()
		local N = 4400
		Pass(f, 30000, N)
		asks.stats = 0
		check(Pass(f, 30000, N) == N, "every item has the stat")
		check(asks.stats <= N - 4000, "stats asked again for few of them (" .. asks.stats .. " of " .. N .. ")")
	end, Restore)
	Run("effect texts and item classes: a working set a little over the cap", function()
		Mock()
		C_Item.GetItemStats = function() asks.stats = asks.stats + 1 return {} end -- (food: no item stats, its effect text)
		local f = P("stat:stamina")
		F.ClearCache()
		local N = 4400
		check(Pass(f, 40000, N) == N, "food: its effect gives stamina")
		asks.spell, asks.inst = 0, 0
		check(Pass(f, 40000, N) == N, "again")
		check(asks.spell <= N - 4000, "effect texts read again for few of them (" .. asks.spell .. " of " .. N .. ")")
		check(asks.inst <= 2 * (N - 4000), "item classes asked again for few of them (" .. asks.inst .. ")")
	end, Restore)
	-- the items a search keeps coming back to stay kept while new ones keep coming (a hit in the older table goes back
	-- into the current one): without that they went with the older table two turns later and were asked again
	-- (item info and stats keep theirs written out, for speed; effect texts and classes use F._.Keep/Kept, tested above)
	Run("items in use stay kept while new ones keep coming", function()
		Mock()
		local hot = {}
		for i = 1, 100 do hot[i] = { itemID = 50000 + i } end
		-- each turn: the hot items, a new lot of 3000, the hot items again (what that last look asks for is counted)
		local function Turns(f, field)
			F.ClearCache()
			local hotAsks, fresh = 0, 60000
			for turn = 1, 3 do
				for _, e in ipairs(hot) do f(e) end
				for i = 1, 3000 do f({ itemID = fresh + i }) end
				fresh = fresh + 3000
				local mark = asks[field]
				for _, e in ipairs(hot) do f(e) end
				if turn > 1 then hotAsks = hotAsks + asks[field] - mark end
			end
			return hotAsks
		end
		local info, stats = Turns(P("q:3"), "info"), Turns(P("stat:sta"), "stats")
		check(info == 0, "item info: the items in use were never asked for again (" .. info .. ")")
		check(stats == 0, "stats: the items in use were never asked for again (" .. stats .. ")")
	end, Restore)
end

do -- type:, slot: and is:equippable from the client's own item data (GetItemInfoInstant): no full item info read
	local save = { info = C_Item.GetItemInfo, inst = C_Item.GetItemInfoInstant, wrist = _G.INVTYPE_WRIST, head = _G.INVTYPE_HEAD }
	local function Restore()
		C_Item.GetItemInfo, C_Item.GetItemInfoInstant = save.info, save.inst
		_G.INVTYPE_WRIST, _G.INVTYPE_HEAD = save.wrist, save.head
	end
	-- name, link, quality, ilvl, minLevel, type, subType, stack, equipLoc, texture, price, class, subclass, bindType
	local ITEMS = {
		[601] = { "Runed Blade", "|Hitem:601|h", 3, 30, 25, "Weapon", "One-Handed Swords", 1, "INVTYPE_WEAPON", 1, 0, 2, 7, 2 },
		[602] = { "Great Axe", "|Hitem:602|h", 2, 30, 25, "Weapon", "Two-Handed Axes", 1, "INVTYPE_2HWEAPON", 1, 0, 2, 1, 2 },
		[603] = { "Iron Helm", "|Hitem:603|h", 2, 28, 23, "Armor", "Plate", 1, "INVTYPE_HEAD", 1, 0, 4, 4, 1 },
		[604] = { "Wolf Bracers", "|Hitem:604|h", 2, 20, 15, "Armor", "Mail", 1, "INVTYPE_WRIST", 1, 0, 4, 3, 2 },
		[605] = { "Light Leather", "|Hitem:605|h", 1, 10, 0, "Trade Goods", "Leather", 20, "", 1, 0, 7, 6, 0 },
		[606] = { "Healing Potion", "|Hitem:606|h", 1, 15, 10, "Consumable", "Potion", 20, "", 1, 0, 0, 1, 0 },
		[607] = { "Oak Shield", "|Hitem:607|h", 2, 22, 17, "Armor", "Shields", 1, "INVTYPE_SHIELD", 1, 0, 4, 6, 2 },
		[608] = { "Epées Courbes", "|Hitem:608|h", 2, 22, 17, "Arme", "Épées à une main", 1, "INVTYPE_WEAPONMAINHAND", 1, 0, 2, 7, 2 },
		[609] = { "Hunting Bow", "|Hitem:609|h", 2, 20, 15, "Weapon", "Bows", 1, "INVTYPE_RANGED", 1, 0, 2, 2, 2 },
		[610] = { "Silk Robe", "|Hitem:610|h", 2, 20, 15, "Armor", "Cloth", 1, "INVTYPE_ROBE", 1, 0, 4, 1, 2 },
	}
	local infoAsks, instAsks = 0, 0
	local hasInfo, hasInstant = {}, {} -- (false: the game has nothing for it)
	local function Mock()
		C_Item.GetItemInfo = function(id)
			infoAsks = infoAsks + 1
			local t = ITEMS[id]
			if t and hasInfo[id] ~= false then return unpack(t) end
		end
		C_Item.GetItemInfoInstant = function(id)
			instAsks = instAsks + 1
			local t = ITEMS[id]
			if t and hasInstant[id] ~= false then return id, t[6], t[7], t[9], t[10], t[12], t[13] end
		end
		_G.INVTYPE_WRIST, _G.INVTYPE_HEAD = "Wrist", "Head"
	end
	local WORDS = { "type:weapon", "type:sword", "type:one-handed_swords", "type:axe", "type:armor", "type:plate", "type:mail",
		"type:leather", "type:potion", "type:shield", "type:épées", "type:arme", "type:bow", "type:cloth", "type:trade",
		"slot:head", "slot:helm", "slot:wrist", "slot:bracers", "slot:2h", "slot:1h", "slot:one-hand", "slot:weapon",
		"slot:offhand", "slot:mainhand", "slot:shield", "slot:chest", "slot:robe", "slot:ranged", "slot:feet",
		"is:equippable", "is:wearable", "slot:head|wrist", "-is:equippable", "type:sword|axe" }
	local function Answers(rows)
		local out = {}
		for _, w in ipairs(WORDS) do
			local f = P(w)
			for _, e in ipairs(rows) do out[#out + 1] = w .. " " .. tostring(e.itemID or e.recipeID) .. "=" .. tostring(f(e) and true or false) end
		end
		return out
	end
	local function Rows()
		local rows = {}
		for id in pairs(ITEMS) do rows[#rows + 1] = { itemID = id } end
		table.sort(rows, function(a, b) return a.itemID < b.itemID end)
		rows[#rows + 1] = { recipeID = 7001, makesItem = 603 } -- (a recipe: what it makes)
		return rows
	end
	Run("the same answers from the client's item data as from the full item info", function()
		Mock()
		local rows = Rows()
		-- the full item info alone (no GetItemInfoInstant: as before)
		C_Item.GetItemInfoInstant = nil
		F.ClearCache()
		local full = Answers(rows)
		-- the client's item data alone (the full item info is never kept: each row asks Instant)
		Mock()
		F.ClearCache()
		infoAsks, instAsks = 0, 0
		local instant = Answers(rows)
		check(infoAsks == 0 and instAsks > 0, "type:, slot: and is:equippable never read the full item info: " .. infoAsks .. " reads, " .. instAsks .. " Instant")
		local diff = {}
		for i = 1, #full do if full[i] ~= instant[i] then diff[#diff + 1] = full[i] .. " / " .. tostring(instant[i]) end end
		check(#full == #instant and #diff == 0, "every answer the same (" .. #full .. " looked at): " .. table.concat(diff, ", "))
		local yes = 0
		for _, a in ipairs(full) do if a:find("=true", 1, true) then yes = yes + 1 end end
		check(yes > 30 and yes < #full - 30, "(a fair mix of yes and no: " .. yes .. " of " .. #full .. ")")
	end, Restore)
	Run("an item the client hasn't loaded: judged by its own item data, nothing asked of the server", function()
		Mock()
		hasInfo[601], hasInfo[603], hasInfo[604] = false, false, false -- (GetItemInfo: nothing yet, it would ask the server)
		F.ClearCache()
		infoAsks = 0
		local blade, helm, bracers, potion = { itemID = 601 }, { itemID = 603 }, { itemID = 604 }, { itemID = 606 }
		check(P("type:sword")(blade) and P("type:weapon")(blade) and not P("type:axe")(blade), "type: on an item not loaded")
		check(P("slot:head")(helm) and P("slot:helm")(helm) and P("slot:bracers")(bracers) and not P("slot:head")(bracers), "slot: on items not loaded")
		check(P("is:equippable")(helm) and not P("is:equippable")(potion), "is:equippable on an item not loaded")
		check(infoAsks == 0, "and the full item info isn't asked for: " .. infoAsks)
		hasInfo = {}
	end, Restore)
	Run("nothing from the client's item data (the server's own items): the full item info, as before", function()
		Mock()
		hasInstant[601], hasInstant[603] = false, false
		F.ClearCache()
		infoAsks = 0
		check(P("type:sword")({ itemID = 601 }) and P("slot:head")({ itemID = 603 }) and P("is:equippable")({ itemID = 603 }),
			"type:, slot:, is:equippable from the full item info")
		check(infoAsks >= 1, "the full item info was read: " .. infoAsks)
		-- an answer for another item (a client that turns an id into another) counts as none
		C_Item.GetItemInfoInstant = function(id) instAsks = instAsks + 1 return 1, "Miscellaneous", "Junk", "" end
		F.ClearCache()
		check(P("type:sword")({ itemID = 601 }) and P("slot:head")({ itemID = 603 }) and not P("type:junk")({ itemID = 601 }),
			"an answer for another item id is not taken")
		hasInstant = {}
	end, Restore)
	Run("an item whose full info is kept already: no call to the game at all", function()
		Mock()
		F.ClearCache()
		local helm = { itemID = 603 }
		check(P("q:2")(helm), "(q: reads and keeps the helm's full info)")
		infoAsks, instAsks = 0, 0
		check(P("slot:head")(helm) and P("type:plate")(helm) and P("is:equippable")(helm), "slot:, type:, is:equippable")
		check(infoAsks == 0 and instAsks == 0, "answered from what's kept: " .. infoAsks .. " reads, " .. instAsks .. " Instant")
	end, Restore)
	-- (every list swapped for a loot list while it runs, put back after)
	local lists = { providers = ns.providers, order = ns.providerOrder }
	Run("in a search: @loot type:sword reads no full item info", function()
		Mock()
		F.ClearCache()
		ns.providers, ns.providerOrder = {}, {}
		ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = function()
			local list = {}
			for id, t in pairs(ITEMS) do list[#list + 1] = { name = t[1], itemID = id, key = "l" .. id, detail = "Boss  Dungeon" } end
			return list
		end })
		UI.lastScan = nil
		ns:GetEntries(ns.providers.loot)
		infoAsks = 0
		local found = T.names(UI:Search("@loot type:sword"))
		check(found["Runed Blade"] and not found["Great Axe"] and not found["Iron Helm"], "@loot type:sword: the sword")
		found = T.names(UI:Search("@loot slot:head|wrist"))
		check(found["Iron Helm"] and found["Wolf Bracers"] and not found["Runed Blade"], "@loot slot:head|wrist")
		check(infoAsks == 0, "no full item info read for the searches: " .. infoAsks)
	end, function()
		Restore()
		ns.providers, ns.providerOrder = lists.providers, lists.order
		ns:AliasesChanged()
		UI.lastScan = nil
	end)
end

do -- in:, zone:, from: on compact rows (Questie's quests, AtlasLoot's items): no field written onto them
	Run("in: on compact rows writes nothing onto them, and answers as on full rows", function()
		F.ClearCache()
		local p = { id = "questiex", label = "Questie" }
		local meta = ns:CompactMeta(p, {}, { detail = function(t)
			return "Lv " .. tostring(rawget(t, "level")) .. "  " .. tostring(rawget(t, "zone"))
		end })
		local ZONES = { "Ashenvale", "The Barrens", "Elwynn Forest", "Duskwood" }
		local quests, loot = {}, {}
		for i = 1, 40 do
			quests[i] = setmetatable({ _compact = true, key = i, name = "Quest " .. i, level = 10 + i % 7, zone = ZONES[i % 4 + 1],
				_ltext = "quest" }, meta)
			loot[i] = setmetatable({ _compact = true, key = "l" .. i, itemID = 900 + i, name = "Item " .. i,
				detail = (i % 3 == 0 and "Garr" or "Lucifron") .. "  " .. (i % 2 == 0 and "Molten Core" or "Blackwing Lair") }, meta)
		end
		local function Raw(rows)
			local n = 0
			for _, e in ipairs(rows) do for _ in pairs(e) do n = n + 1 end end
			return n
		end
		local function Full(rows) -- (the same rows as plain tables: written onto, as before)
			local out = {}
			for i, e in ipairs(rows) do
				local c = {}
				for k, v in pairs(e) do if k ~= "_compact" then c[k] = v end end
				c.detail = e.detail
				out[i] = c
			end
			return out
		end
		local fullQ, fullL = Full(quests), Full(loot)
		local before = Raw(quests) + Raw(loot)
		local mismatches, yes = 0, 0
		for _, w in ipairs({ "in:ashenvale", "zone:barrens", "in:lv_12", "from:garr", "in:molten_core", "where:lair", "in:nowhere",
			"in:ashenvale|duskwood", "-from:garr" }) do
			local f = P(w)
			for _ = 1, 2 do -- (twice: the second look reads what the first kept)
				for i = 1, #quests do
					local a, b = f(quests[i]) and true or false, f(fullQ[i]) and true or false
					if a ~= b then mismatches = mismatches + 1 end
					if a then yes = yes + 1 end
					a, b = f(loot[i]) and true or false, f(fullL[i]) and true or false
					if a ~= b then mismatches = mismatches + 1 end
					if a then yes = yes + 1 end
				end
			end
		end
		check(mismatches == 0 and yes > 100, "the same answers as on full rows (" .. yes .. " yes, " .. mismatches .. " different)")
		check(Raw(quests) + Raw(loot) == before, "no field written onto the compact rows: " .. before .. " -> " .. (Raw(quests) + Raw(loot)))
		local wrote = false
		for _, e in ipairs(fullQ) do if rawget(e, "_lzone") then wrote = true end end
		check(wrote, "(full rows still keep their lowercase copies, as before)")
		-- a zone's name the game changes (another language after a reload): read afresh, not an old copy
		quests[1].zone = "Orneval"
		check(P("in:orneval")(quests[1]) and not P("in:ashenvale")(quests[1]), "a row's new text is what's matched")
	end)
end

do -- Fuzzy.score: the needle's letters made once per needle (no string.sub per letter per row), the same scores
	-- Fuzzy.score as it was before (0.44.8), to compare with
	local Old = (function()
		local MIN = -math.huge
		local LEAD, TRAIL, INNER = -0.005, -0.005, -0.01
		local CONSEC, SLASH, WORD, CAPITAL, DOT = 1.0, 0.9, 0.8, 0.7, 0.6
		local MAXLEN, EXACT = 256, 100
		local byte, find, ssub = string.byte, string.find, string.sub
		local function bonusFor(last, cur)
			if last == 47 then return SLASH end
			if last == 45 or last == 95 or last == 32 or last == 58 or last == 40 or last == 91 then return WORD end
			if last == 46 then return DOT end
			if last >= 97 and last <= 122 and cur >= 65 and cur <= 90 then return CAPITAL end
			return 0
		end
		local function substringScore(needle, hay, lhay, n, m)
			local best, at
			local p = find(lhay, needle, 1, true)
			while p do
				local last = p > 1 and byte(hay, p - 1) or 47
				local s = (p - 1) * LEAD + bonusFor(last, byte(hay, p)) + (n - 1) * CONSEC + (m - (p + n - 1)) * TRAIL
				if not best or s > best then best, at = s, p end
				p = find(lhay, needle, p + 1, true)
			end
			return best, at
		end
		local rowM, rowD, rowM2, rowD2 = {}, {}, {}, {}
		local rowB, rowL, rowLo = {}, {}, {}
		return function(needle, hay, lhay)
			local n, m = #needle, #hay
			if n == 0 then return 0 end
			if n > m or m > MAXLEN then return nil end
			lhay = lhay or ns.Lower(hay)
			if n == m then
				if lhay == needle then return EXACT, true end
				return nil
			end
			local sub = substringScore(needle, hay, lhay, n, m)
			if sub then return sub, true end
			local Lo = rowLo
			local pos = find(lhay, ssub(needle, 1, 1), 1, true)
			if not pos then return nil end
			local first = pos
			Lo[1] = pos
			for i = 2, n do
				pos = find(lhay, ssub(needle, i, i), pos + 1, true)
				if not pos then return nil end
				Lo[i] = pos
			end
			local B, Lb = rowB, rowL
			local last = first > 1 and byte(hay, first - 1) or 47
			for j = first, m do
				local c = byte(hay, j)
				B[j] = bonusFor(last, c)
				Lb[j] = byte(lhay, j)
				last = c
			end
			local Mp, Dp, Mc, Dc = rowM, rowD, rowM2, rowD2
			for i = 1, n do
				local nc = byte(needle, i)
				local prev = MIN
				local gap = (i == n) and TRAIL or INNER
				local lo = Lo[i]
				local hi = (i == n) and m or (m - n + i)
				Mc[lo - 1], Dc[lo - 1] = MIN, MIN
				for j = lo, hi do
					if Lb[j] == nc then
						local s
						if i == 1 then
							s = (j - 1) * LEAD + B[j]
						else
							local a, b = Mp[j - 1] + B[j], Dp[j - 1] + CONSEC
							s = a > b and a or b
						end
						Dc[j] = s
						prev = (s > prev + gap) and s or (prev + gap)
					else
						Dc[j] = MIN
						prev = prev + gap
					end
					Mc[j] = prev
				end
				Mp, Mc = Mc, Mp
				Dp, Dc = Dc, Dp
			end
			local r = Mp[m]
			if r == MIN then return nil end
			return r
		end
	end)()
	local Fuzzy = ns.Fuzzy
	Run("Fuzzy.score: the same scores as before, on random names and needles", function()
		local seed = 12345
		local function rand(n) seed = (seed * 1103515245 + 12345) % 2147483648; return math.floor(seed / 65536) % n + 1 end
		local CH = { "a", "b", "c", "d", "e", "k", "r", "o", "s", "t", "A", "K", "R", "S", "T", " ", " ", "-", "_", ":", "(", "[",
			"/", ".", "'", "1", "9", "é", "É", "ü", "ß", "한", "글" }
		local function word(len)
			local t = {}
			for i = 1, len do t[i] = CH[rand(#CH)] end
			return table.concat(t)
		end
		local same, differ, scattered, substr, none, first = 0, 0, 0, 0, 0, nil
		for round = 1, 1500 do
			local hay = word(rand(40) - 1)
			local lhay = ns.Lower(hay)
			local needle
			local pick = rand(4)
			if pick == 1 and #lhay > 0 then -- (letters of the name in order: a scattered match)
				local t, at = {}, 0
				while at < #lhay and #t < 6 do
					at = at + rand(3)
					if at <= #lhay then t[#t + 1] = lhay:sub(at, at) end
				end
				needle = table.concat(t)
			elseif pick == 2 and #lhay > 2 then -- (a piece of it as it is)
				local a = rand(#lhay - 1)
				needle = lhay:sub(a, a + rand(4))
			else
				needle = ns.Lower(word(rand(6)))
			end
			for _, lh in ipairs(round % 4 == 0 and { lhay, false } or { lhay }) do -- (now and then the name lowercased by score)
				local a1, a2 = Old(needle, hay, lh or nil)
				local b1, b2 = Fuzzy.score(needle, hay, lh or nil)
				if a1 == b1 and a2 == b2 then same = same + 1 else
					differ = differ + 1
					first = first or (("%q in %q: %s,%s / %s,%s"):format(needle, hay, tostring(a1), tostring(a2), tostring(b1), tostring(b2)))
				end
				if a1 and a2 then substr = substr + 1 elseif a1 then scattered = scattered + 1 else none = none + 1 end
			end
		end
		check(differ == 0, "every score the same (" .. same .. " compared): " .. tostring(first))
		check(scattered > 150 and substr > 150 and none > 150, "(a fair mix: " .. scattered .. " scattered, " .. substr .. " as they are, " .. none .. " none)")
		-- needles longer than a row, a full match, the cap
		local edge = { { "abc", "ab" }, { "abc", "ABC" }, { "abc", "abc" }, { "", "abc" }, { "ab", ("x"):rep(300) .. "ab" },
			{ "ace", "Abc Def Efg" }, { "kar", "Karo Anlan" }, { "zulth", "Zul'Gurub The" } }
		local edgeSame = true
		for _, c in ipairs(edge) do
			local a1, a2 = Old(c[1], c[2])
			local b1, b2 = Fuzzy.score(c[1], c[2])
			if a1 ~= b1 or a2 ~= b2 then edgeSame = false end
		end
		check(edgeSame, "the same on the edges (longer needle, full match, empty needle, over the length cap)")
	end)
	Run("Fuzzy.score: no string.sub per letter per row for scattered matches", function()
		local names = {}
		for i = 1, 300 do names[i] = "Kxaxrx Row " .. i end -- (k-a-r scattered in every one)
		local lnames = {}
		for i = 1, #names do lnames[i] = ns.Lower(names[i]) end
		Fuzzy.score("kar", names[1], lnames[1]) -- (the needle's letters are made here, once)
		local guard
		local subs = CountCalls(string.sub, function()
			for i = 1, #names do guard = Fuzzy.score("kar", names[i], lnames[i]) or guard end
		end)
		check(guard ~= nil, "(the names do match, scattered)")
		check(subs == 0, "string.sub calls while scoring " .. #names .. " rows: " .. subs)
	end)
end

do -- NPC titles (trainer:, is:classtrainer, is:proftrainer, is:pvp): lowercased and read once per title, not per row
	local I = ns.Integrations
	local save = { nf = I.NpcField, defs = I.NpcFlagDefs, class = _G.UnitClass }
	local TITLES = { "Warrior Trainer", "Undead Mage Trainer", "Master Mage", "Image Collector", "Journeyman Blacksmith",
		"Miner", "Weaponsmith", "Warsong Gulch Battlemaster", "Officer Accessories Quartermaster", "Riding Instructor" }
	-- (the trainers by Questie's flag: Master Mage, Miner and Image Collector have no "trainer" in their titles)
	local TRAINS = { ["Master Mage"] = true, Miner = true, ["Image Collector"] = true, ["Journeyman Blacksmith"] = true }
	Run("trainer titles: the same answers, each title lowercased once", function()
		local DEFS = { TRAINER = 16, BATTLEMASTER = 2048 }
		local meta = ns:CompactMeta({ id = "npc", label = "NPC" }, {}, {})
		local rows, flags = {}, {}
		for i = 1, 400 do
			local sub = (i % 4 ~= 0) and TITLES[i % #TITLES + 1] or nil
			rows[i] = setmetatable({ _compact = true, key = 70000 + i, name = "NPC " .. i, sub = sub }, meta)
			flags[70000 + i] = sub and TRAINS[sub] and 16 or 0
		end
		I.NpcField = function(id, f) if f == "npcFlags" then return flags[id] end end
		I.NpcFlagDefs = function() return DEFS end
		_G.UnitClass = function() return "Mage", "MAGE", 8 end
		F.ClearCache()
		local WANT = { -- title -> the words that pass it
			["Warrior Trainer"] = { "trainer:warrior", "is:classtrainer" },
			["Undead Mage Trainer"] = { "trainer:mage", "trainer:class", "is:classtrainer" },
			["Master Mage"] = { "trainer:mage", "trainer:class", "is:classtrainer" },
			["Image Collector"] = {},
			["Journeyman Blacksmith"] = { "trainer:blacksmithing", "is:proftrainer" },
			Miner = { "trainer:mining", "trainer:mine", "is:proftrainer" },
			Weaponsmith = {},
			["Warsong Gulch Battlemaster"] = { "is:battlemaster", "is:pvp" },
			["Officer Accessories Quartermaster"] = { "is:pvpvendor", "is:pvp" },
			["Riding Instructor"] = { "trainer:riding" },
		}
		local WORDS = { "trainer:warrior", "trainer:mage", "trainer:class", "trainer:blacksmithing", "trainer:mining", "trainer:mine",
			"trainer:riding", "is:classtrainer", "is:proftrainer", "is:battlemaster", "is:pvpvendor", "is:pvp" }
		local filters = {}
		for i, w in ipairs(WORDS) do filters[i] = P(w) end -- (parsed first: a parse lowercases its own value)
		local wrong = {}
		local lowers = CountCalls(string.lower, function()
			for _ = 1, 2 do
				for i, w in ipairs(WORDS) do
					local f = filters[i]
					for _, e in ipairs(rows) do
						local sub = rawget(e, "sub")
						local want = false
						for _, x in ipairs(sub and WANT[sub] or {}) do if x == w then want = true end end
						if (f(e) and true or false) ~= want then wrong[#wrong + 1] = w .. " " .. tostring(sub) end
					end
				end
			end
		end)
		check(#wrong == 0, "each title answered as before: " .. table.concat(wrong, ", ", 1, math.min(#wrong, 4)))
		check(lowers <= #TITLES, "titles lowercased once each, not per row: " .. lowers .. " lowercasings for " .. #rows .. " NPCs x "
			.. #WORDS .. " filters x 2")
	end, function()
		I.NpcField, I.NpcFlagDefs, _G.UnitClass = save.nf, save.defs, save.class
	end)
end
