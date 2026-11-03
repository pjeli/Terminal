local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local OA = ns.OneForAll

-- OneForAll's world (1.0.4, the player's ask): its weapon masters (who teaches which weapon: the third source after
-- What's Training and TrainerSpells, ClassSpells.lua's CS.WeaponMasters), its drop chances on AtlasLoot's loot
-- (Classic's numbers, Loot.lua's rows), @favor (the recipes the Merchant's Favor buys, yours or not, and where) and
-- @transport (the boats, zeppelins, airships and the tram, and where each zone's roads cross into the next).
-- "favor recipes i don't know", "nearest boat", "zeppelin to orgrimmar", "zone exits" ask for them (Simple mode).

local W = {}
OA.World = W
ns.OneForAllWorld = W
local Lower, Num = ns.Lower, ns.Num
local SEP = ns.DETAIL_SEP

local function Norm(s) return (Lower(tostring(s or "")):gsub("'", ""):gsub("[%p]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end

local function Side()
	local f = UnitFactionGroup and UnitFactionGroup("player")
	return (f == "Alliance" and "A") or (f == "Horde" and "H") or nil
end
-- "A", "H", "AH" or nil (both): is it for you?
local function ForMe(sides)
	local me = Side()
	return not (sides and me) or sides:find(me, 1, true) ~= nil
end

-- a zone's name for a map id: the game's, else OneForAll's MAP_IDS read backwards
local zoneBack
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
function W.Forget() zoneBack = nil end -- (tests)

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

--- An item's chance to drop from a boss of an instance (percent), or nil when OneForAll doesn't say.
function W.DropChance(inst, boss, id)
	local d = W.DropChances()
	local i = d and d[Norm(inst)]
	local b = i and i[Norm(boss)]
	return b and b[id] or nil
end

--- A chance as a row says it: "12%", "4.8%", "0.28%".
function W.ChanceText(pct)
	local s = (pct >= 10 and ("%d"):format(math.floor(pct + 0.5))) or (pct >= 1 and ("%.1f"):format(pct)) or ("%.2f"):format(pct)
	return L["%s%% to drop"]:format((s:gsub("%.0$", "")))
end

----------------------------------------------------------------------
-- @favor: the Merchant's Favor recipes
----------------------------------------------------------------------

--- Its Merchant's Favor recipes, checked: { { profession, name, skill, cost } }, and where each faction buys them:
--- { Alliance = { zone, x, y, vendors = { [profession] = { name, x, y } } }, Horde = ... }; or nil.
function W.FavorData()
	return OA.Part("favor", "MERCHANT_RECIPES", L["@favor (its Merchant's Favor recipes) is unavailable."], function(raw, lib)
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

-- your professions (their names, lower case) and the recipes you know in them, as Terminal indexed them
local function YourRecipes()
	local profs, known = {}, {}
	local store = ns.Professions and ns.Professions.Store and ns.Professions.Store()
	for _, pdata in pairs(type(store) == "table" and store or {}) do
		if type(pdata) == "table" and type(pdata.name) == "string" then
			profs[Lower(pdata.name)] = true
			for _, r in ipairs(pdata.list or {}) do
				if type(r) == "table" and r.learned ~= false and type(r.name) == "string" then known[Lower(r.name)] = true end
			end
		end
	end
	return profs, known
end

local function FavorTooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	t:AddLine(e.profession .. (e.skill and (SEP .. L["skill %d"]:format(e.skill)) or ""), 1, 1, 1)
	if e.cost then t:AddLine(L["%d Merchant's Favor"]:format(e.cost), 1, 0.82, 0.4) end
	if e.known ~= nil then t:AddLine(e.known and L["You know it"] or L["You don't know it yet"], e.known and 0.4 or 1, 1, e.known and 0.4 or 1) end
	if e.vendorName then
		t:AddLine(e.vendorName .. (e.zone and (SEP .. (e.place and (e.place .. ", ") or "") .. e.zone) or ""), 0.8, 0.8, 0.8, true)
	end
	t:AddLine(L["Merchant's Favor recipes from OneForAll"], 0.5, 0.5, 0.5)
end

local function NoSpot(e) ns:Print(L["OneForAll has no spot for %s yet."]:format(e.vendorName or e.name)) end

--- @favor's rows: a recipe each, your faction's vendor for it, known or not (nil: not your profession).
function W.FavorRows()
	local d = W.FavorData()
	if not d then return {} end
	local fac = UnitFactionGroup and UnitFactionGroup("player")
	local hub = d.where[fac or ""]
	local profs, known = YourRecipes()
	local out = {}
	for i, r in ipairs(d.recipes) do
		local name = (OA.Text(d.prefix[r.profession]) or "") .. r.name
		local isKnown
		if profs[Lower(r.profession)] then isKnown = known[Lower(r.name)] == true end
		local v = hub and hub.vendors[r.profession]
		local row = {
			key = r.profession .. ":" .. r.name, kind = "favor", name = name, _lname = Lower(name), recipeName = r.name, profession = r.profession,
			skill = r.skill, cost = r.cost, known = isKnown, vendorName = v and v.name, zone = hub and hub.zone, place = hub and hub.place, order = i,
			icon = "Interface\\Icons\\INV_Scroll_03", tooltip = FavorTooltip, generic = false, pinName = v and v.name,
			detail = r.profession .. (r.skill and (SEP .. L["skill %d"]:format(r.skill)) or "") .. (r.cost and (SEP .. L["%d Favor"]:format(r.cost)) or "")
				.. (isKnown and (SEP .. L["learned"]) or ""),
			text = Lower(table.concat({ L["Merchant's Favor"], "merchants favor recipe", r.profession, isKnown and "learned" or "" }, " ")),
		}
		if v and v.x and hub.ui then
			row.ui, row.px, row.py = hub.ui, v.x, v.y
			if I.SpotXY then row.wcont, row.wx, row.wy = I.SpotXY(hub.ui, { v.x, v.y }) end
			out[#out + 1] = I.SpotRow(row)
		else
			row.activate, row.secondary = NoSpot, NoSpot
			out[#out + 1] = row
		end
	end
	return out
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
			if ui and x and y and OA.Text(to) then out[#out + 1] = { way = way, ui = ui, x = x, y = y, to = to, sides = OA.Text(sides) } end
		end
		for _, z in ipairs(type(raw.zeppelin) == "table" and raw.zeppelin or {}) do
			if type(z) == "table" then for k = 4, #z do Add("zeppelin", z[1], z[2], z[3], z[k]) end end
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
					Add("road", r[1], r[2], r[3], to)
					out[#out].target = Num(r[4])
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
	if W.FavorData() then
		ns:RegisterProvider("favor", {
			label = L["Merchant's Favor recipe"], color = "ffe0a050",
			aliases = { "favor", "favour", "merchantsfavor", "favorrecipe", "favorrecipes" },
			lazy = true, events = { "TRADE_SKILL_CLOSE", "CRAFT_CLOSE", "LEARNED_SPELL_IN_SKILL_LINE" }, guard = 1, collect = W.FavorRows,
		})
	end
	if W.Transports() then
		ns:RegisterProvider("transport", {
			label = L["Transport"], color = "ff80c0d0",
			aliases = { "transport", "transports", "boat", "boats", "ship", "ships", "zeppelin", "zeppelins", "tram" },
			lazy = true, collect = W.TransportRows,
		})
	end
end)
OA.AddStatus(function()
	local parts = {}
	local f, t = W.FavorData(), W.Transports()
	if f then parts[#parts + 1] = L["%d Merchant's Favor recipes (@favor)"]:format(#f.recipes) end
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
	if not (ns.providers.favor or ns.providers.transport) then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local words = {}
	for w in t:gmatch("%S+") do words[#words + 1] = w end
	local favor, way, profs = false, nil, {}
	for _, w in ipairs(words) do
		if FAVOR[w] then favor = true end
		if WAYW[w] and not way then way = WAYW[w] end
	end
	if favor and ns.providers.favor then
		local q = { what = "favor", words = {} }
		for i, w in ipairs(words) do
			if FAVOR[w] then -- (the word itself)
			elseif UNKNOWN[w] or (w == "not" and KNOWN[words[i + 1] or ""]) then q.unknown = true
			elseif KNOWN[w] then q.known = not q.unknown or nil
			elseif w == "not" then q.unknown = true
			elseif not ASK[w] then q.words[#q.words + 1] = w end
		end
		if q.unknown then q.known = nil end
		-- other words: a profession or a recipe's name
		if #q.words > 0 then
			local any = false
			for _, e in ipairs(ns:GetEntries(ns.providers.favor)) do
				local hay = (rawget(e, "_lname") or "") .. " " .. (rawget(e, "_ltext") or rawget(e, "text") or "")
				local all = true
				for _, w in ipairs(q.words) do if not hay:find(w, 1, true) then all = false break end end
				if all then any = true break end
			end
			if not any then return nil end
		end
		return q
	end
	if way and ns.providers.transport then
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

local function Has(e, words)
	local hay = (rawget(e, "_lname") or "") .. " " .. (rawget(e, "_ltext") or rawget(e, "text") or "")
	for _, w in ipairs(words or {}) do if not hay:find(w, 1, true) then return false end end
	return true
end

local function Nearest(rows)
	local here = I.Here and I.Here()
	if not here then return nil end
	local near, far = {}, {}
	for _, e in ipairs(rows) do
		local d = I.RowYards(e, here)
		if d then near[#near + 1] = { e = e, d = d } else far[#far + 1] = e end
	end
	table.sort(near, function(a, b) return a.d < b.d end)
	local out = {}
	for i, n in ipairs(near) do
		out[i] = setmetatable({ _score = 1e6 - n.d, _dist = n.d, detail = L["%.0f yd"]:format(n.d) .. SEP .. (rawget(n.e, "detail") or "") },
			{ __index = n.e })
	end
	for _, e in ipairs(far) do out[#out + 1] = e end
	return out
end

local function HereMap()
	local f = C_Map and C_Map.GetBestMapForUnit
	return f and Num(ns.Safe(f, "player")) or nil
end

function W.Answer(q)
	q = q or {}
	if q.what == "favor" then
		local rows = {}
		for _, e in ipairs(ns:GetEntries(ns.providers.favor)) do
			if Has(e, q.words) and not (q.unknown and e.known ~= false) and not (q.known and e.known ~= true) then rows[#rows + 1] = e end
		end
		ns.ScoreInOrder(rows)
		local title = (q.unknown and L["Merchant's Favor recipes you don't know"]) or (q.known and L["Merchant's Favor recipes you know"])
			or L["Merchant's Favor recipes"]
		if #rows == 0 then
			return { ns.NoteRow(q.unknown and L["None you don't know, in the professions Terminal has indexed (open each once)"]
				or L["No Merchant's Favor recipe has that"]) }, title
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
	if q.what == "favor" then
		return "@favor " .. (q.unknown and "is:unlearned " or q.known and "is:learned " or "") .. w
	end
	local word = ({ ship = "boat", zeppelin = "zeppelin", air = "airship", tram = "tram", road = "road" })[q.way] or ""
	return "@transport " .. word .. " " .. (q.to and (q.to .. " ") or "") .. "sort:distance " .. w
end
