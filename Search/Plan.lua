local ns = select(2, ...)
local L = ns.L

-- A profession's levelling plan (0.48.2, the player's ask): Advanced "sort:plan" ("@recipe blacksmithing sort:plan"),
-- Simple mode "blacksmithing plan" / "level blacksmithing" / "leveling plan". Your recipes that still give a skill point
-- (orange or yellow: is:skillup), by how many times the materials you have make each: in your bags and bank, and with
-- what your alts hold (the bag addon's records, as @stored counts them). Materials a vendor sells you are left out of
-- the count (you'd buy them: a recipe made of those only says so, and isn't planned); sold means a vendor's window
-- showed it on sale in any number (MissingRecipes.lua keeps db.vendorItems), or Questie lists a vendor friendly to you.
--
-- The footer says the skill the materials would give: crafting the recipe with the best chance of a point first, again
-- and again while the materials last, each craft's chance as the game's: 1 while orange, then (grey - skill) / (grey -
-- yellow) through yellow and green, 0 at grey (the levels AtlasLoot's crafting data has: { item, profession, learned,
-- yellow, grey }); a recipe AtlasLoot doesn't know keeps the chance of the colour its window showed last (orange 1,
-- yellow 0.75, green 0.25). It stops at your skill's cap (train for more), and is an estimate: "about +12".

local PL = {}
ns.Plan = PL

local Safe, Num, Str, Lower = ns.Safe, ns.Num, ns.Str, ns.Lower

PL.SHOWN_CHANCE = { orange = 1, yellow = 0.75, green = 0.25, grey = 0 } -- (no levels known: the window's colour)
PL.STEPS = 600 -- (crafts planned at most: each looks over every recipe planned)

local function Diff()
	return ns.Filters and ns.Filters.DIFF or { orange = 0, yellow = 1, green = 2, grey = 3 }
end

----------------------------------------------------------------------
-- What a vendor sells
----------------------------------------------------------------------

local sold = {} -- item id -> true / false (false kept only once Questie could be asked)
local levels = {} -- recipe -> { yellow, grey } or false (AtlasLoot's data never changes: kept once it's loaded)

--- Whether a vendor sells the item to you in any number: a vendor's window showed it so, or Questie lists a vendor of it
--- friendly to you.
function PL.VendorSold(id)
	if type(id) ~= "number" then return false end
	local seen = ns.db and ns.db.vendorItems
	if seen and seen[id] then return true end
	local known = sold[id]
	if known ~= nil then return known end
	local I = ns.Integrations
	local DB = ns.QuestieData and ns.QuestieData.DB and Safe(ns.QuestieData.DB)
	if not (DB and I and I.ItemField) then return false end -- (Questie not there yet: asked again next time)
	local vendors = I.ItemField(id, "vendors")
	local yes = false
	if type(vendors) == "table" then
		for _, npc in ipairs(vendors) do
			local row = I.NpcRow and I.NpcRow(npc)
			if row and (not ns.Pipes or ns.Pipes.Friendly(row)) then yes = true break end
		end
	end
	sold[id] = yes
	return yes
end
function PL.Forget() sold, levels = {}, {} end -- (tests)

----------------------------------------------------------------------
-- A craft's chance of a skill point
----------------------------------------------------------------------

--- AtlasLoot's levels for a recipe (its spell): yellow, grey, or nil.
function PL.Levels(recipeID)
	if type(recipeID) ~= "number" then return nil end
	local c = levels[recipeID]
	if c ~= nil then
		if c then return c[1], c[2] end
		return nil
	end
	local AL = _G.AtlasLoot
	local Pr = AL and AL.Data and AL.Data.Profession
	if not (Pr and Pr.GetProfessionData) then return nil end -- (not loaded: asked again next time)
	local d = Safe(Pr.GetProfessionData, recipeID)
	local low, high
	if type(d) == "table" then low, high = Num(d[4]), Num(d[5]) end
	if low and high and low > 0 and high > low then
		levels[recipeID] = { low, high }
		return low, high
	end
	levels[recipeID] = false
end

--- A craft's chance of a skill point at this skill, and its colour then ("orange", "yellow", "green", "grey").
function PL.Chance(e, skill)
	local low, high = PL.Levels(e.recipeID)
	if low and skill then
		if skill < low then return 1, "orange" end
		if skill >= high then return 0, "grey" end
		return (high - skill) / (high - low), (skill < low + (high - low) / 2) and "yellow" or "green"
	end
	local D = Diff()
	local d = e.difficulty
	local colour = (d == D.orange and "orange") or (d == D.yellow and "yellow") or (d == D.green and "green")
		or (d == D.grey and "grey") or nil
	return colour and PL.SHOWN_CHANCE[colour] or 0, colour
end

----------------------------------------------------------------------
-- The plan
----------------------------------------------------------------------

-- your professions, by name (lowercase) and skill line
local function Professions()
	local P = ns.Professions
	local by = {}
	for _, pr in ipairs(P and P.PlayerProfessions and (P.PlayerProfessions()) or {}) do
		by[Lower(pr.name)] = pr
		if pr.skillLine then by[pr.skillLine] = pr end
	end
	return by
end

local function ProfOf(e, profs)
	return (e.profID and profs[e.profID]) or (e.profName and profs[Lower(e.profName)]) or nil
end

-- how many of each material: in bags and bank, and with your alts' too
local function Counts(ids)
	local Pi = ns.Pipes
	local own, all = {}, {}
	local stored = (Pi and Pi.StoredByID) and Pi.StoredByID() or {}
	for id in pairs(ids) do
		local n = Pi and Pi.ItemCount and Pi.ItemCount(id, true) or 0
		own[id] = n
		local st = stored[id]
		all[id] = math.max(n, (st and tonumber(st.total)) or 0)
	end
	return own, all
end

-- the materials that count (not sold by vendors): { { id, need } }
local function Mats(e)
	local out = {}
	for _, rg in ipairs(e.reagents or {}) do
		local id, need = rg[1], tonumber(rg[2]) or 1
		if type(id) == "number" and need > 0 and not PL.VendorSold(id) then out[#out + 1] = { id, need } end
	end
	return out
end

-- times the pool makes it (nil: vendor materials only), and the first material short
local function Crafts(mats, pool)
	if #mats == 0 then return nil end
	local n, short = math.huge, nil
	for _, m in ipairs(mats) do
		local k = math.floor((pool[m[1]] or 0) / m[2])
		if k < n then n = k end
		if k == 0 and not short then short = m[1] end
	end
	return n, short
end

--- The skill a pool of materials would give a profession's recipes, crafted best chance first while they last: the
--- skill reached (fractional: an expectation), and whether the cap stopped it. A recipe out of materials or gone grey
--- stays so (materials only go down, the skill only up): dropped from what's looked at. An orange one is made until it
--- turns yellow at once (its chance stays 1); a yellow or green one until a point is likely (its chance moves with the
--- skill), then everything is looked at again.
function PL.Simulate(plans, pool, rank, cap)
	local left = {}
	for id, n in pairs(pool) do left[id] = n end
	local active = {}
	for _, p in ipairs(plans) do
		if #p.mats > 0 then active[#active + 1] = { p = p, low = PL.Levels(p.e.recipeID) } end
	end
	local skill = rank
	for _ = 1, PL.STEPS do
		if cap and cap > 0 and skill >= cap then return cap, true end
		local best, bestChance, bestCan
		for i = #active, 1, -1 do
			local a = active[i]
			local can = Crafts(a.p.mats, left)
			local c = can > 0 and PL.Chance(a.p.e, skill) or 0
			if c <= 0 then
				active[i] = active[#active]
				active[#active] = nil
			elseif not best or c > bestChance or (c == bestChance and a.p.use < best.p.use) then
				best, bestChance, bestCan = a, c, can
			end
		end
		if not best then break end
		local k
		if bestChance >= 1 and best.low and skill < best.low then
			k = math.ceil(best.low - skill) -- (orange until its yellow level)
		else
			k = math.ceil(1 / bestChance)
		end
		k = math.max(1, math.min(bestCan, k))
		for _, m in ipairs(best.p.mats) do left[m[1]] = left[m[1]] - m[2] * k end
		skill = skill + bestChance * k
	end
	if cap and cap > 0 and skill >= cap then return cap, true end
	return skill, false
end

local function View(e, fields) return setmetatable(fields, { __index = e }) end

local function ItemName(id)
	local get = C_Item and C_Item.GetItemNameByID
	local n = get and Str(Safe(get, id))
	return n or L["item %s"]:format(tostring(id))
end

--- The rows of a search, planned: the recipes that still give skill (orange or yellow now), each a view saying how
--- many times your materials make it, by that (most first; vendor materials only, then none, last); and the footer's
--- note: the skill they'd give. Other rows are left out.
function PL.Rows(rows)
	local profs = Professions()
	local plans, ids, byProf, order = {}, {}, {}, {}
	for _, e in ipairs(rows or {}) do
		if e.kind == "recipes" and e.recipeID and type(e.reagents) == "table" then
			local pr = ProfOf(e, profs)
			local chance, colour = PL.Chance(e, pr and pr.rank)
			if chance > 0 and (colour == "orange" or colour == "yellow") then
				local p = { e = e, pr = pr, mats = Mats(e), chance = chance, colour = colour, use = 0 }
				for _, m in ipairs(p.mats) do p.use = p.use + m[2] end -- (equal chances: the one using less first)
				plans[#plans + 1] = p
				for _, m in ipairs(p.mats) do ids[m[1]] = true end
				local key = pr and pr.name or "?"
				if not byProf[key] then byProf[key] = {}; order[#order + 1] = key end
				local list = byProf[key]
				list[#list + 1] = p
			end
		end
	end
	local own, all = Counts(ids)
	for _, p in ipairs(plans) do
		p.own, p.short = Crafts(p.mats, own)
		p.all = Crafts(p.mats, all)
	end
	-- most crafts from bags and bank first, then with alts, then the better chance, then by name
	table.sort(plans, function(a, b)
		local va, vb = a.own == nil, b.own == nil -- (vendor materials only: after those you have something for)
		if va ~= vb then return vb end
		if (a.own or 0) ~= (b.own or 0) then return (a.own or 0) > (b.own or 0) end
		if (a.all or 0) ~= (b.all or 0) then return (a.all or 0) > (b.all or 0) end
		if a.chance ~= b.chance then return a.chance > b.chance end
		return tostring(a.e.name) < tostring(b.e.name)
	end)
	-- (vendor-only ones after the ones with none of their materials)
	local made, none, vendor = {}, {}, {}
	for _, p in ipairs(plans) do
		if p.own == nil then vendor[#vendor + 1] = p
		elseif (p.own or 0) == 0 and (p.all or 0) == 0 then none[#none + 1] = p
		else made[#made + 1] = p end
	end
	local out = {}
	local function Add(p)
		local d
		if p.own == nil then
			d = L["vendor materials only"]
		elseif p.own == 0 and p.all == 0 then
			d = L["missing %s"]:format(ItemName(p.short or p.mats[1][1]))
		else
			d = (p.own == 1 and L["1 craft"] or L["%d crafts"]:format(p.own))
			if p.all > p.own then d = d .. "  ·  " .. L["%d with alts"]:format(p.all) end
		end
		if p.pr then d = d .. "  ·  " .. p.pr.name end
		out[#out + 1] = View(p.e, { detail = d, planCrafts = p.own, planAlts = p.all, _score = 1e6 - #out })
	end
	for _, p in ipairs(made) do Add(p) end
	for _, p in ipairs(none) do Add(p) end
	for _, p in ipairs(vendor) do Add(p) end
	return out, PL.Note(order, byProf, own, all)
end

local function Round(x) return math.floor(x + 0.5) end

--- The footer's note: the skill your materials would give each profession planned.
function PL.Note(order, byProf, own, all)
	if #order == 0 then return L["Plan: no recipe of yours gives skill now"] end
	local parts, capped = {}, nil
	for _, name in ipairs(order) do
		local list = byProf[name]
		local pr = list[1].pr
		if pr then
			local reach, atCap = PL.Simulate(list, own, pr.rank, pr.maxRank)
			local reachAll, capAll = PL.Simulate(list, all, pr.rank, pr.maxRank)
			local gain, gainAll = Round(reach - pr.rank), Round(reachAll - pr.rank)
			parts[#parts + 1] = { name = name, rank = pr.rank, gain = gain, gainAll = gainAll, cap = pr.maxRank }
			if atCap or capAll then capped = pr.maxRank end
		end
	end
	if #parts == 0 then return L["Plan: recipes that give skill, by the crafts your materials cover"] end
	local s
	if #parts == 1 then
		local p = parts[1]
		if p.gain == 0 and p.gainAll == 0 then
			s = L["Plan: nothing to make %s from (vendor materials left out)"]:format(p.name)
		else
			s = L["Plan: about +%d %s (%d to %d) from bags and bank"]:format(p.gain, p.name, p.rank, p.rank + p.gain)
			if p.gainAll > p.gain then s = s .. ", " .. L["+%d with your alts' materials"]:format(p.gainAll) end
		end
	else
		local each = {}
		for _, p in ipairs(parts) do
			each[#each + 1] = ("%s +%d"):format(p.name, p.gain) .. (p.gainAll > p.gain and (" " .. L["(+%d with alts)"]:format(p.gainAll)) or "")
		end
		s = L["Plan: about %s"]:format(table.concat(each, ", "))
	end
	if capped then s = s .. "  ·  " .. L["%d is your cap: train for more"]:format(capped) end
	return s
end

----------------------------------------------------------------------
-- The question: "blacksmithing plan", "level blacksmithing", "leveling plan", "how do i level cooking"
----------------------------------------------------------------------

local ASK = {}
for w in ([[my me i the a an to of for how do does can should what which up skill points with is are it best
	fastest quickly quick next]]):gmatch("%a+") do ASK[w] = true end
-- (not "skillup": "blacksmithing skillup" stays Simple mode's is:skillup search)
local CUE = { plan = true, planner = true, level = true, leveling = true, levelling = true, lvl = true }
local ANY = { profession = true, professions = true, prof = true, profs = true, crafting = true, craft = true, trade = true,
	tradeskill = true, tradeskills = true }

--- The question: { profs = { your professions named }, words = what narrows it }, or nil when the line isn't asking
--- for a levelling plan. A plan word (plan, level, leveling) and a profession of yours named (or "profession").
function PL.Question(text)
	if type(text) ~= "string" or text:find("[@:>|]") or text:find("^%s*[%./]") then return nil end
	local t = Lower(text):gsub("'", ""):gsub("[%p]", " ")
	local mine = {}
	local P = ns.Professions
	for _, pr in ipairs(P and P.PlayerProfessions and (P.PlayerProfessions()) or {}) do mine[#mine + 1] = pr end
	local cue, any, profs, words, seen = false, false, {}, {}, {}
	for w in t:gmatch("%S+") do
		local prof
		for _, pr in ipairs(mine) do
			local ln = Lower(pr.name)
			-- (the name, or its first letters: "blacksmith", "tailor", "enchant")
			if w == ln or (#w >= 5 and ln:sub(1, #w) == w) then prof = pr end
		end
		if prof then
			if not seen[prof.name] then seen[prof.name] = true; profs[#profs + 1] = prof.name end
		elseif CUE[w] then cue = true
		elseif ANY[w] then any = true
		elseif not ASK[w] then words[#words + 1] = w end
	end
	if not cue or (#profs == 0 and not any) then return nil end
	return { profs = profs, words = words }
end

PL.NONE = L["Open a profession's window once: Terminal reads its recipes from it"]

function PL.Answer(q)
	local p = ns.providers.recipes
	local all = p and ns:GetEntries(p) or {}
	local want = {}
	for _, n in ipairs(q.profs or {}) do want[Lower(n)] = true end
	local rows = {}
	for _, e in ipairs(all) do
		local ok = e.recipeID ~= nil and (not next(want) or (e.profName and want[Lower(e.profName)]))
		if ok then
			local hay = (rawget(e, "_lname") or Lower(e.name)) .. " " .. (e._ltext or "")
			for _, w in ipairs(q.words or {}) do if not hay:find(w, 1, true) then ok = false break end end
		end
		if ok then rows[#rows + 1] = e end
	end
	if #rows == 0 then
		return { { name = PL.NONE, raw = true, icon = false, noActivate = true, kindLabel = "", detail = "",
			_pos = ns.UI and ns.UI.NO_POS or nil } }, L["Plan"]
	end
	local out, note = PL.Rows(rows)
	if #out == 0 then
		return { { name = L["None of these recipes gives skill now: train new ones"], raw = true, icon = false,
			noActivate = true, kindLabel = "", detail = "", _pos = ns.UI and ns.UI.NO_POS or nil } }, note
	end
	return out, note
end

--- The question as Advanced syntax (Alt+`): "@recipe blacksmithing sort:plan".
function PL.ToAdvanced(q)
	local parts = { "@recipe" }
	for _, n in ipairs(q.profs or {}) do parts[#parts + 1] = Lower(n) end
	for _, w in ipairs(q.words or {}) do parts[#parts + 1] = w end
	parts[#parts + 1] = "sort:plan"
	return table.concat(parts, " ") .. " "
end
