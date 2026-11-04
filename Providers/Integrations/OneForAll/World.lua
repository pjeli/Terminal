local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local OA = ns.OneForAll

-- OneForAll's world (1.0.4, the player's ask): its weapon masters (who teaches which weapon: the third source after
-- What's Training and TrainerSpells, ClassSpells.lua's CS.WeaponMasters), its drop chances on AtlasLoot's loot
-- (Classic's numbers, Loot.lua's rows), the recipes the Merchant's Favor buys (a way to learn the ones you don't know:
-- MissingRecipes.lua's rows) and @transport (the boats, zeppelins, airships and the tram, and where each zone's roads
-- cross into the next).
-- "favor recipes i don't know", "nearest boat", "zeppelin to orgrimmar", "zone exits" ask for them (Simple mode).

local W = {}
OA.World = W
ns.OneForAllWorld = W
local Lower, Num = ns.Lower, ns.Num
local SEP = ns.DETAIL_SEP

local Norm = OA.Words

local Side = OA.Side
-- "A", "H", "AH" or nil (both): is it for you?
local function ForMe(sides)
	local me = Side()
	return not (sides and me) or sides:find(me, 1, true) ~= nil
end

-- a zone's name for a map id: the game's, else OneForAll's MAP_IDS read backwards
local zoneBack
local favorBy -- (W.FavorOf's: "<profession>\001<recipe>" (lower case) -> its recipe)
local function ZoneOf(ui)
	local n = I.ZoneName and I.ZoneName(ui)
	if n then return n end
	if not zoneBack then
		zoneBack = {}
		local lib = OA.Lib()
		for name, id in pairs(lib and type(lib.MAP_IDS) == "table" and lib.MAP_IDS or {}) do
			if type(name) == "string" and Num(id) then zoneBack[Num(id)] = name end
		end
	end
	return zoneBack[ui]
end
function W.Forget() zoneBack, favorBy = nil, nil end -- (tests)

----------------------------------------------------------------------
-- Weapon masters
----------------------------------------------------------------------

--- Its weapon masters in CS.WeaponMasters' shape: { [weapon skill spell] = { Alliance = { { npc, name, uiMapId, x, y } },
--- Horde = { ... } } }, or nil.
function W.WeaponMasters()
	return OA.Part("weaponmasters", "WEAPON_TRAINERS", L["Its weapon masters are unavailable."], function(raw, lib)
		local spells = type(lib.WEAPON_SKILL_SPELL) == "table" and lib.WEAPON_SKILL_SPELL
		if not spells then return nil, "OneForAll.WEAPON_SKILL_SPELL is missing" end
		local by, n = {}, 0
		for _, t in ipairs(raw) do
			local npc, fac = type(t) == "table" and Num(t.npc), type(t) == "table" and ({ A = "Alliance", H = "Horde" })[t.side]
			if npc and fac and type(t.skills) == "table" then
				local rec = { npc = npc, name = OA.Text(t.name), uiMapId = Num(t.map), x = Num(t.x), y = Num(t.y) }
				for _, sub in ipairs(t.skills) do
					local spell = Num(spells[sub])
					if spell then
						by[spell] = by[spell] or {}
						by[spell][fac] = by[spell][fac] or {}
						table.insert(by[spell][fac], rec)
					end
				end
				n = n + 1
			end
		end
		if n == 0 then return nil, "OneForAll.WEAPON_TRAINERS: no weapon master in the shape expected" end
		return by
	end, true)
end

----------------------------------------------------------------------
-- Drop chances
----------------------------------------------------------------------

--- Its drop chances: { [instance] = { [boss] = { [itemID] = percent } } }, both names as Norm makes them; or nil.
function W.DropChances()
	return OA.Part("dropchance", "DUNGEON_DROP_CHANCE", L["Its drop chances are unavailable."], function(raw)
		local out, n = {}, 0
		for inst, bosses in pairs(raw) do
			if type(inst) == "string" and type(bosses) == "table" then
				local t = {}
				for boss, items in pairs(bosses) do
					if type(boss) == "string" and type(items) == "table" then
						local it = {}
						for id, pct in pairs(items) do
							if Num(id) and Num(pct) then it[Num(id)] = Num(pct); n = n + 1 end
						end
						t[Norm(boss)] = it
					end
				end
				out[Norm(inst)] = t
			end
		end
		if n == 0 then return nil, "OneForAll.DUNGEON_DROP_CHANCE: no drop chance in the shape expected" end
		return out
	end, true)
end

--- A boss's items' chances to drop ({ [item id] = percent }), or nil when OneForAll doesn't say.
function W.BossChances(inst, boss)
	local d = W.DropChances()
	local i = d and d[Norm(inst)]
	return i and i[Norm(boss)] or nil
end
--- An item's chance to drop when OneForAll lists it under one boss only (percent), or nil: the boss's name not needed
--- (AtlasLoot names bosses and instances in the client's language, OneForAll in English: on another client no name
--- matched; 1.0.84, review). An item under two bosses with other chances says none.
local byItem = { from = nil, at = {} }
function W.ItemChance(id)
	local d = W.DropChances()
	if not d or type(id) ~= "number" then return nil end
	if byItem.from ~= d then
		local at = {}
		for _, bosses in pairs(d) do
			for _, items in pairs(bosses) do
				for i, pct in pairs(items) do
					if at[i] == nil then at[i] = pct elseif at[i] ~= pct then at[i] = false end
				end
			end
		end
		byItem.from, byItem.at = d, at
	end
	return byItem.at[id] or nil
end

--- An item's chance to drop from a boss of an instance (percent), or nil when OneForAll doesn't say.
function W.DropChance(inst, boss, id)
	local b = W.BossChances(inst, boss)
	return b and b[id] or nil
end

--- A chance as a row says it: "12%", "4.8%", "0.28%".
function W.ChanceText(pct)
	local s = (pct >= 10 and ("%d"):format(math.floor(pct + 0.5))) or (pct >= 1 and ("%.1f"):format(pct)) or ("%.2f"):format(pct)
	return L["%s%% to drop"]:format((s:gsub("%.0$", "")))
end

----------------------------------------------------------------------
-- The Merchant's Favor recipes
----------------------------------------------------------------------

--- Its Merchant's Favor recipes, checked: { { profession, name, skill, cost } }, and where each faction buys them:
--- { Alliance = { zone, x, y, vendors = { [profession] = { name, x, y } } }, Horde = ... }; or nil.
function W.FavorData()
	return OA.Part("favor", "MERCHANT_RECIPES", L["Its Merchant's Favor recipes are unavailable."], function(raw, lib)
		local out = {}
		for _, r in ipairs(raw) do
			local prof, name = type(r) == "table" and OA.Text(r.profession), type(r) == "table" and OA.Text(r.name)
			if prof and name then out[#out + 1] = { profession = prof, name = name, skill = Num(r.skill), cost = Num(r.cost) } end
		end
		if #out == 0 then return nil, "OneForAll.MERCHANT_RECIPES: no recipe in the shape expected" end
		local where = {}
		local hubs = type(lib.TRADE_HUBS) == "table" and lib.TRADE_HUBS or {}
		local maps = type(lib.MAP_IDS) == "table" and lib.MAP_IDS or {}
		for fac, h in pairs(hubs) do
			if type(h) == "table" then
				where[fac] = { name = OA.Text(h.name), zone = OA.Text(h.zone), place = OA.Text(h.place), ui = Num(maps[h.zone or ""]), vendors = {} }
			end
		end
		for _, v in ipairs(type(lib.PROFESSION_VENDORS) == "table" and lib.PROFESSION_VENDORS or {}) do
			if type(v) == "table" and OA.Text(v.profession) then
				if where.Alliance and OA.Text(v.alliance) then where.Alliance.vendors[v.profession] = { name = v.alliance, x = Num(v.ax), y = Num(v.ay) } end
				if where.Horde and OA.Text(v.horde) then where.Horde.vendors[v.profession] = { name = v.horde, x = Num(v.hx), y = Num(v.hy) } end
			end
		end
		local prefix = type(lib.RECIPE_PREFIX) == "table" and lib.RECIPE_PREFIX or {}
		return { recipes = out, where = where, prefix = prefix }
	end, true)
end

-- (1.0.12, the player: too many kinds; was @favor) No kind of their own: a recipe you don't know yet (@recipe
-- is:unknown, Providers/MissingRecipes.lua) says it's bought with the Merchant's Favor, what it costs and your faction's
-- vendor, as one of the ways to learn it.
--- What the Merchant's Favor says of a recipe of a profession (their names): { cost, skill, vendor, place, zone } or nil.
function W.FavorOf(name, prof)
	local d = W.FavorData()
	if not (d and type(name) == "string" and type(prof) == "string") then return nil end
	if not favorBy then
		favorBy = {}
		for _, r in ipairs(d.recipes) do favorBy[Lower(r.profession) .. "\001" .. Lower(r.name)] = r end
	end
	local r = favorBy[Lower(prof) .. "\001" .. Lower(name)]
	if not r then return nil end
	local fac = UnitFactionGroup and UnitFactionGroup("player")
	local hub = d.where[fac or ""]
	local v = hub and hub.vendors[r.profession]
	return { cost = r.cost, skill = r.skill, vendor = v and v.name, place = hub and hub.place, zone = hub and hub.zone }
end

----------------------------------------------------------------------
-- @transport: boats, zeppelins, airships, the tram, and the roads into the next zone
----------------------------------------------------------------------

W.WAYS = { ship = L["Boat to %s"], zeppelin = L["Zeppelin to %s"], air = L["Airship to %s"], tram = L["Tram to %s"], road = L["Road to %s"] }
local WAY_WORDS = { ship = "boat ship ferry", zeppelin = "zeppelin zep", air = "airship", tram = "tram deeprun", road = "road exit border" }

--- Its transports: { { way ("ship", "zeppelin", "air", "tram", "road"), ui, x, y, to (a place's name), sides } }, or nil.
function W.Transports()
	return OA.Part("transport", "MAP_LANDMARKS", L["@transport (its boats, zeppelins and the tram) is unavailable."], function(raw, lib)
		local out = {}
		local function Add(way, ui, x, y, to, sides)
			ui, x, y = Num(ui), Num(x), Num(y)
			if ui and x and y and OA.Text(to) then
				local w = { way = way, ui = ui, x = x, y = y, to = to, sides = OA.Text(sides) }
				out[#out + 1] = w
				return w
			end
		end
		-- (the zeppelins are the Horde's: OneForAll marks them "Horde only"; review, 1.0.13)
		for _, z in ipairs(type(raw.zeppelin) == "table" and raw.zeppelin or {}) do
			if type(z) == "table" then for k = 4, #z do Add("zeppelin", z[1], z[2], z[3], z[k], "H") end end
		end
		for _, way in ipairs({ "ship", "air" }) do
			for _, s in ipairs(type(raw[way]) == "table" and raw[way] or {}) do
				if type(s) == "table" then for k = 5, #s do Add(way, s[1], s[2], s[3], s[k], s[4]) end end
			end
		end
		for _, t in ipairs(type(raw.tram) == "table" and raw.tram or {}) do
			if type(t) == "table" then Add("tram", t[1], t[2], t[3], t[4]) end
		end
		-- (the roads: a table of their own, some versions have none)
		local roads = lib.ZONE_TRANSITIONS
		for _, r in ipairs(type(roads) == "table" and roads or {}) do
			if type(r) == "table" and Num(r[4]) then
				local to = ZoneOf(Num(r[4]))
				if to then
					local w = Add("road", r[1], r[2], r[3], to)
					if w then w.target = Num(r[4]) end
				end
			end
		end
		if #out == 0 then return nil, "OneForAll.MAP_LANDMARKS: no boat, zeppelin or tram in the shape expected" end
		return out
	end)
end

local function TransportTooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	if e.zone then t:AddLine(e.zone .. "  " .. ("%.1f, %.1f"):format(e.px, e.py), 1, 1, 1) end
	if e.sides == "A" then t:AddLine(L["Alliance only"], 0.4, 0.6, 1) elseif e.sides == "H" then t:AddLine(L["Horde only"], 1, 0.4, 0.4) end
	t:AddLine(L["Ways from OneForAll"], 0.5, 0.5, 0.5)
end

--- @transport's rows: a way each (a dock's every destination its own), your faction's and both sides'.
function W.TransportRows()
	local out = {}
	for i, w in ipairs(W.Transports() or {}) do
		if ForMe(w.sides) then
			local zone = ZoneOf(w.ui)
			local name = W.WAYS[w.way]:format(w.to)
			local row = {
				key = w.way .. ":" .. w.ui .. ":" .. w.x .. ":" .. w.to, kind = "transport", name = name, _lname = Lower(name), way = w.way, to = w.to,
				sides = w.sides, zone = zone, ui = w.ui, px = w.x, py = w.y, target = w.target, order = (w.way == "road" and 10000 or 0) + i,
				icon = (w.way == "road" and "Interface\\Icons\\INV_Misc_Map_01") or (w.way == "tram" and "Interface\\Icons\\INV_Misc_Gear_01")
					or "Interface\\Icons\\Ability_Mount_RidingHorse",
				tooltip = TransportTooltip, generic = false, pinName = name,
				detail = (zone or "") .. ((w.sides == "A" and (SEP .. L["Alliance only"])) or (w.sides == "H" and (SEP .. L["Horde only"])) or ""),
				text = Lower(table.concat({ WAY_WORDS[w.way], L["transport"], w.to, zone or "" }, " ")),
			}
			if I.SpotXY then row.wcont, row.wx, row.wy = I.SpotXY(w.ui, { w.x, w.y }) end
			out[#out + 1] = I.SpotRow(row)
		end
	end
	return out
end

OA.AddSetup(function()
	W.WeaponMasters()
	W.DropChances()
	if W.FavorData() and ns.MissingRecipes then
		ns.MissingRecipes.FavorOf = W.FavorOf
		if ns.providers.missing then ns:Changed("missing") end
	end
	if W.Transports() then
		ns:RegisterProvider("transport", {
			label = L["Transport"], color = "ff80c0d0",
			aliases = { "transport", "transports", "boat", "boats", "ship", "ships", "zeppelin", "zeppelins", "tram" },
			namesOnly = true, -- (a search that doesn't name it: by the ways' names only, Scan.NameMode)
			lazy = true, collect = W.TransportRows,
		})
	end
end)
OA.AddStatus(function()
	local parts = {}
	local f, t = W.FavorData(), W.Transports()
	if f then parts[#parts + 1] = L["%d Merchant's Favor recipes (on the recipes you don't know)"]:format(#f.recipes) end
	if t then parts[#parts + 1] = L["%d ways (@transport)"]:format(#t) end
	if W.DropChances() then parts[#parts + 1] = L["drop chances on @loot"] end
	if W.WeaponMasters() then parts[#parts + 1] = L["weapon masters"] end
	return #parts > 0 and table.concat(parts, ", ") or nil
end)

----------------------------------------------------------------------
-- "favor recipes", "alchemy favor recipes i don't know", "nearest boat", "zeppelin to orgrimmar", "zone exits"
----------------------------------------------------------------------

local FAVOR = { favor = true, favour = true }
local UNKNOWN = { dont = true, unknown = true, missing = true, unlearned = true, need = true, learn = true }
local KNOWN = { know = true, known = true, learned = true, have = true }
local WAYW = { boat = "ship", boats = "ship", ship = "ship", ships = "ship", ferry = "ship", zeppelin = "zeppelin", zeppelins = "zeppelin",
	zep = "zeppelin", zepp = "zeppelin", airship = "air", airships = "air", tram = "tram", exit = "road", exits = "road", road = "road",
	roads = "road" }
local NEAR = { nearest = true, closest = true, nearby = true, near = true }
local ASK = { i = true, im = true, ["do"] = true, the = true, a = true, an = true, where = true, are = true, is = true, what = true,
	which = true, show = true, list = true, me = true, of = true, ["for"] = true, ["in"] = true, at = true, can = true, get = true,
	my = true, all = true, yet = true, merchants = true, merchant = true, recipes = true, recipe = true, with = true, buy = true,
	take = true, catch = true, here = true, zone = true, out = true, ways = true, way = true, from = true, this = true }

--- The question: { what = "favor" (prof, unknown, known) | "way" (way, to, near, here) }, or nil.
function W.Question(text)
	local favorOn = W.FavorData() ~= nil and ns.providers.missing ~= nil
	if not (favorOn or ns.providers.transport) then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local words = {}
	for w in t:gmatch("%S+") do words[#words + 1] = w end
	local favor, way, profs = false, nil, {}
	for _, w in ipairs(words) do
		if FAVOR[w] then favor = true end
		if WAYW[w] and not way then way = WAYW[w] end
	end
	if favor and favorOn then
		local q = { what = "favor", words = {} }
		for i, w in ipairs(words) do
			if FAVOR[w] then -- (the word itself)
			elseif UNKNOWN[w] or (w == "not" and KNOWN[words[i + 1] or ""]) then q.unknown = true
			elseif KNOWN[w] then q.known = not q.unknown or nil
			elseif w == "not" then q.unknown = true
			elseif not ASK[w] then q.words[#q.words + 1] = w end
		end
		if q.unknown then q.known = nil end
		-- (only the ones you don't know are listed: "favor recipes i know" is a search)
		if q.known then return nil end
		-- other words: a profession or a recipe's name
		if #q.words > 0 then
			local any = false
			local p = ns.providers.missing
			for _, e in ipairs(p and ns:GetEntries(p) or {}) do
				if type(e.sources) == "table" and e.sources.favor and OA.Has(e, q.words) then any = true break end
			end
			if not any then return nil end
		end
		return q
	end
	if way and ns.providers.transport then
		-- (none of that way for you, the Alliance's "zeppelin": the search's, its masters; review, 1.0.36: "OneForAll
		-- knows no way like that")
		local any = false
		for _, e in ipairs(ns:GetEntries(ns.providers.transport)) do if e.way == way then any = true break end end
		if not any then return nil end
		local q = { what = "way", way = way, words = {} }
		local toAt
		for i, w in ipairs(words) do
			if w == "to" and not toAt then toAt = i end
		end
		for i, w in ipairs(words) do
			if NEAR[w] then q.near = true
			elseif WAYW[w] or (toAt and i == toAt) then -- (said)
			elseif toAt and i > toAt then q.to = (q.to and (q.to .. " ") or "") .. w
			elseif not ASK[w] then q.words[#q.words + 1] = w end
		end
		-- ("zone exits", "exits here": your zone's)
		if way == "road" then
			q.here = true
			if q.to then return q end
			if #q.words > 0 then return nil end
			return q
		end
		if #q.words > 0 then return nil end
		return q
	end
	return nil
end

--- The recipes you don't know yet that the Merchant's Favor buys (@recipe is:unknown's rows that say so).
function W.FavorRecipes()
	local out = {}
	local p = ns.providers.missing
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		if type(e.sources) == "table" and e.sources.favor then out[#out + 1] = e end
	end
	return out
end

local Has = OA.Has

local Nearest = OA.Nearest

local function HereMap()
	local f = C_Map and C_Map.GetBestMapForUnit
	return f and Num(ns.Safe(f, "player")) or nil
end

function W.Answer(q)
	q = q or {}
	if q.what == "favor" then
		local rows = {}
		for _, e in ipairs(W.FavorRecipes()) do
			if Has(e, q.words) then rows[#rows + 1] = e end
		end
		ns.ScoreInOrder(rows)
		local title = L["Merchant's Favor recipes you don't know"]
		if #rows == 0 then
			return { ns.NoteRow(L["None you don't know, in the professions Terminal has indexed (open each once)"]) }, title
		end
		return rows, title
	end
	local rows = {}
	local here = q.here and HereMap()
	local want = q.to and Norm(q.to)
	for _, e in ipairs(ns:GetEntries(ns.providers.transport)) do
		local ok = e.way == q.way and Has(e, q.words) and not (want and not Norm(e.to):find(want, 1, true))
			and not (here and not q.to and e.ui ~= here)
		if ok then rows[#rows + 1] = e end
	end
	local title = W.WAYS[q.way]:format(q.to or "...")
	if q.way == "road" and not q.to then title = L["Roads out of here"] end
	if #rows == 0 then return { ns.NoteRow(L["OneForAll knows no way like that"]) }, title end
	if q.near or q.way ~= "road" or q.to then
		local near = Nearest(rows)
		if near then return near, title end
	end
	ns.ScoreInOrder(rows)
	return rows, title
end

function W.ToAdvanced(q)
	q = q or {}
	local w = q.words and #q.words > 0 and (table.concat(q.words, " ") .. " ") or ""
	if q.what == "favor" then return "@recipe is:unknown favor " .. w end
	local word = ({ ship = "boat", zeppelin = "zeppelin", air = "airship", tram = "tram", road = "road" })[q.way] or ""
	-- ("zone exits": your zone's roads, as the question lists them; review, 1.0.42: every road in the game)
	local here = ""
	if q.here and not q.to then
		local zone = ZoneOf(HereMap())
		if zone then here = "in:" .. Lower(zone):gsub("%s+", "_") .. " " end
	end
	return "@transport " .. word .. " " .. (q.to and (q.to .. " ") or "") .. here .. "sort:distance " .. w
end
