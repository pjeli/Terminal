local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local OA = ns.OneForAll

-- @tame ("Hunter pet"): a hunter's pets on WoW Forever (1.0.2, the player's ask), OneForAll's lists of them, one kind
-- since 1.0.9 (the player: too many kinds; was @petability and @tame) and only on a hunter. Its rows are of two sorts:
-- each rank of each pet ability (`ability` set: its level, its training points, the families that learn it, learned or
-- not: OneForAll's record of your pets' spellbooks; Enter the beasts that teach it), and the beasts to tame (where each
-- is, on the map with Enter; its family and level, the ranks it teaches, the rare ones and why).
-- "where to learn bite 4", "cat abilities", "tameable cats", "rare pets in the barrens" ask for them (Simple mode).

local P = {}
OA.Pets = P
ns.HunterPets = P
local Lower, Num = ns.Lower, ns.Num
local SEP = ns.DETAIL_SEP
local ICONS = "Interface\\Icons\\"

-- a level as OneForAll writes it ("6-7", "43 (elite)", "60"): lowest, highest, elite
local function Levels(s)
	s = type(s) == "number" and tostring(s) or OA.Text(s)
	if not s then return nil end
	local lo = tonumber(s:match("^%s*(%d+)"))
	if not lo then return nil end
	return lo, tonumber(s:match("^%s*%d+%s*%-%s*(%d+)")) or lo, s:find("elite", 1, true) ~= nil
end

-- a beast where OneForAll says it is: its map and spot, or nothing (a dungeon's: no spot)
local function Spot(t, b)
	local ui, x, y = Num(b.mapID), Num(b.x), Num(b.y)
	if ui and x and y then t.ui, t.px, t.py = ui, x, y end
	return t
end

--- Its families, checked: { { name, icon, role, diet, abilities, trainer, note, tames = { beast, ... } } }, or nil.
function P.Families()
	return OA.Part("petfamilies", "PET_FAMILIES", L["@tame (its beasts to tame) is unavailable."], function(raw)
		local out = {}
		for i, f in ipairs(raw) do
			local name = type(f) == "table" and OA.Text(f.name)
			if name then
				local tames = {}
				for _, b in ipairs(type(f.tames) == "table" and f.tames or {}) do
					if type(b) == "table" and OA.Text(b.name) then
						tames[#tames + 1] = Spot({ name = b.name, level = OA.Text(b.level), zone = OA.Text(b.zone), npcID = Num(b.npcID), family = name }, b)
					end
				end
				local list = function(v)
					local t = {}
					for _, s in ipairs(type(v) == "table" and v or {}) do if OA.Text(s) then t[#t + 1] = s end end
					return t
				end
				out[#out + 1] = { name = name, order = i, icon = OA.Text(f.icon), role = OA.Text(f.role), note = OA.Text(f.note),
					diet = list(f.diet), abilities = list(f.abilities), trainer = list(f.trainer), tames = tames }
			end
		end
		if #out == 0 then return nil, "OneForAll.PET_FAMILIES: no family in the shape expected" end
		return out
	end)
end

--- Its abilities, checked: { { name, icon, source ("wild", "trainer"), families, effect, ranks = { { rank, level, tp,
--- desc, none (no beast known to teach it), teachers = { beast, ... } } } } }, or nil.
function P.Abilities()
	return OA.Part("petabilities", "PET_ABILITIES", L["Its pet abilities are unavailable."], function(raw)
		local out = {}
		for i, a in ipairs(raw) do
			local name = type(a) == "table" and OA.Text(a.name)
			if name and type(a.ranks) == "table" then
				local ranks = {}
				for _, r in ipairs(a.ranks) do
					local n = type(r) == "table" and Num(r.rank)
					if n then
						local teachers = {}
						for _, b in ipairs(type(r.learnFrom) == "table" and r.learnFrom or {}) do
							if type(b) == "table" and OA.Text(b.name) then
								teachers[#teachers + 1] = Spot({ name = b.name, level = OA.Text(b.level), zone = OA.Text(b.zone), npcID = Num(b.npcID),
									family = OA.Text(b.family) }, b)
							end
						end
						ranks[#ranks + 1] = { rank = n, level = Num(r.level), tp = Num(r.tp), desc = OA.Text(r.desc), none = r.noSource == true,
							teachers = teachers }
					end
				end
				local fams = {}
				for _, s in ipairs(type(a.families) == "table" and a.families or {}) do if OA.Text(s) then fams[#fams + 1] = s end end
				if #ranks > 0 then
					out[#out + 1] = { name = name, order = i, icon = OA.Text(a.icon), source = OA.Text(a.source), families = fams,
						effect = OA.Text(a.effect), ranks = ranks }
				end
			end
		end
		if #out == 0 then return nil, "OneForAll.PET_ABILITIES: no ability in the shape expected" end
		return out
	end)
end

--- Its rare and named beasts: { [npcID or name] = { why, speed, beast } } (optional: some versions have none).
function P.Rares()
	return OA.Part("petrares", "PET_RARES", L["Its rare beasts are unavailable."], function(raw)
		local out = {}
		for _, b in ipairs(raw) do
			if type(b) == "table" and OA.Text(b.name) then
				local t = Spot({ name = b.name, level = OA.Text(b.level), zone = OA.Text(b.zone), npcID = Num(b.npcID), family = OA.Text(b.family),
					why = OA.Text(b.why), speed = Num(b.speed) }, b)
				out[#out + 1] = t
			end
		end
		return out
	end, true)
end

-- an ability's rank as a key and a phrase ("bite 4"): what a beast teaches, and what Enter on a rank searches for
local function Teach(name, rank) return Lower(name) .. " " .. rank end

--- The highest rank of an ability your pets know, as OneForAll saw their spellbooks; nil when it hasn't looked
--- (not a hunter, or no pet called yet).
function P.KnownRank(name)
	local lib = OA.Lib()
	local db = rawget(_G, "OneForAllCharDB")
	if not (lib and type(db) == "table" and db.petAbilitiesScanned == true) then return nil end
	return Num(OA.Call(lib.GetKnownPetRank, lib, name)) or 0
end

local function Joined(t) return table.concat(t, ", ") end

local Walk = OA.Walk

-- Enter on a rank: the beasts that teach it (a pet trainer's: the nearest pet trainers), or why there's none
local function LearnRank(e)
	if e.source == "trainer" then return Walk("@npc trainer:pet sort:distance ") end
	if e.teachers == 0 then return ns:Print(L["OneForAll knows no beast that teaches %s."]:format(e.name)) end
	Walk("@tame \"" .. L["teaches %s"]:format(Teach(e.ability, e.rank)) .. ";\" sort:distance ")
end

local function AbilityTooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	if e.desc then t:AddLine(e.desc, 1, 1, 1, true) end
	t:AddLine(L["Pet level %d"]:format(e.level or 0) .. (e.tp and (SEP .. L["%d training points"]:format(e.tp)) or ""), 0.8, 0.8, 0.8)
	if #e.families > 0 then t:AddLine(Joined(e.families), 0.62, 0.62, 0.62, true) end
	if e.known ~= nil then
		t:AddLine(e.known and L["Your pets know it"] or L["Your pets don't know it yet"], e.known and 0.4 or 1, 1, e.known and 0.4 or 1)
	end
	t:AddLine(" ")
	if e.source == "trainer" then t:AddLine(L["Learned at a pet trainer. Enter: the nearest ones."], 0.8, 0.8, 0.8, true)
	elseif e.teachers > 0 then t:AddLine(L["%d beasts teach it: tame one and use it in a fight. Enter: the nearest."]:format(e.teachers), 0.8, 0.8, 0.8, true)
	else t:AddLine(L["OneForAll knows no beast that teaches it."], 1, 0.5, 0.3, true) end
	t:AddLine(L["Pet abilities from OneForAll"], 0.5, 0.5, 0.5)
end

--- The ability rows: one a rank, in OneForAll's order.
function P.AbilityRows()
	local out = {}
	for _, a in ipairs(P.Abilities() or {}) do
		local known = P.KnownRank(a.name)
		for _, r in ipairs(a.ranks) do
			local name = L["%s (Rank %d)"]:format(a.name, r.rank)
			local isKnown -- (nil: not looked at)
			if known ~= nil then isKnown = r.rank <= known end
			local how = (a.source == "trainer" and L["pet trainer"]) or (#r.teachers > 0 and L["%d beasts teach it"]:format(#r.teachers))
				or L["no beast known to teach it"]
			out[#out + 1] = {
				key = a.name .. "#" .. r.rank, kind = "tame", name = name, _lname = Lower(name), ability = a.name, rank = r.rank,
				level = r.level, tp = r.tp, desc = r.desc or a.effect, families = a.families, source = a.source, teachers = #r.teachers,
				known = isKnown, icon = a.icon and (ICONS .. a.icon) or "Interface\\Icons\\Ability_Hunter_BeastTraining", order = #out + 1,
				tooltip = AbilityTooltip, activate = LearnRank, secondary = LearnRank, generic = false,
				detail = (r.level and L["level %d"]:format(r.level) or "") .. (r.tp and (SEP .. L["%d TP"]:format(r.tp)) or "") .. SEP .. how
					.. (isKnown and (SEP .. L["learned"]) or ""),
				text = Lower(table.concat({ L["pet ability"], "pet ability", Teach(a.name, r.rank), Joined(a.families), a.source or "",
					r.desc or a.effect or "", isKnown and "learned" or "" }, " ")),
			}
		end
	end
	return out
end

local function TameTooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	t:AddLine(e.family .. (e.levelText and (SEP .. L["level %s"]:format(e.levelText)) or ""), 1, 1, 1)
	if e.zone then t:AddLine(e.zone .. (e.px and ("  " .. ("%.1f, %.1f"):format(e.px, e.py)) or ""), 1, 1, 1, true) end
	if e.why then t:AddLine(e.why, 1, 0.82, 0.4, true) end
	if e.speed then t:AddLine(L["Attack speed %.1f"]:format(e.speed), 0.8, 0.8, 0.8) end
	if #e.teaches > 0 then t:AddLine(L["Teaches %s"]:format(Joined(e.teachList)), 0.4, 1, 0.4, true) end
	local f = e.fam
	if f then
		if #f.diet > 0 then t:AddLine(L["Eats %s"]:format(Joined(f.diet)), 0.8, 0.8, 0.8, true) end
		if #f.abilities > 0 then t:AddLine(L["%s learn %s"]:format(f.name, Joined(f.abilities)), 0.8, 0.8, 0.8, true) end
		if f.note then t:AddLine(f.note, 0.62, 0.62, 0.62, true) end
	end
	if not e.px then t:AddLine(L["OneForAll has no spot for it on the map."], 0.62, 0.62, 0.62, true) end
	t:AddLine(L["Beasts from OneForAll"], 0.5, 0.5, 0.5)
end

local function NoSpot(e) ns:Print(L["OneForAll has no spot for %s yet."]:format(e.name)) end

local famIndex, abIndex -- (Index, below: families and abilities by name)
local beastRows -- (made once: OneForAll's beasts don't change in a session; the abilities' known ranks do)
function P.Forget() beastRows, famIndex, abIndex = nil, nil, nil end -- (tests)

--- @tame's rows: the ability ranks, then the beasts.
function P.Rows()
	local out = P.AbilityRows()
	beastRows = beastRows or P.TameRows()
	for _, e in ipairs(beastRows) do out[#out + 1] = e end
	return out
end
--- An @tame row of a beast (not an ability's rank)?
local function IsBeast(e) return e.ability == nil end
--- The ability ranks among @tame's rows.
function P.Ranks()
	local out = {}
	local p = ns.providers.tame
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do if not IsBeast(e) then out[#out + 1] = e end end
	return out
end
--- The beasts among them.
function P.Beasts()
	local out = {}
	local p = ns.providers.tame
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do if IsBeast(e) then out[#out + 1] = e end end
	return out
end

--- The beasts' rows: each beast once (its families' tames, the beasts that teach a rank, the rare ones), by family then level.
function P.TameRows()
	local fams = P.Families()
	if not fams then return {} end
	local famBy, beasts, list = {}, {}, {}
	for _, f in ipairs(fams) do famBy[f.name] = f end
	local function Add(b, family)
		local id = b.npcID or (b.name .. "@" .. (b.zone or ""))
		local e = beasts[id]
		if not e then
			e = { name = b.name, npcID = b.npcID, zone = b.zone, levelText = b.level, family = family or b.family, ui = b.ui, px = b.px, py = b.py,
				teaches = {}, teachList = {} }
			beasts[id] = e
			list[#list + 1] = e
		end
		e.family = e.family or family or b.family
		if not e.ui and b.ui then e.ui, e.px, e.py = b.ui, b.px, b.py end
		return e
	end
	for _, f in ipairs(fams) do for _, b in ipairs(f.tames) do Add(b, f.name) end end
	for _, a in ipairs(P.Abilities() or {}) do
		for _, r in ipairs(a.ranks) do
			for _, b in ipairs(r.teachers) do
				local e = Add(b)
				local k = Teach(a.name, r.rank)
				if not e.teaches[k] then e.teaches[k] = true; e.teachList[#e.teachList + 1] = a.name .. " " .. r.rank end
			end
		end
	end
	for _, b in ipairs(P.Rares() or {}) do
		local e = Add(b)
		e.rare, e.why, e.speed = true, b.why, b.speed
	end
	local out = {}
	for _, e in ipairs(list) do
		local f = famBy[e.family or ""]
		if f then -- (a family OneForAll doesn't list: left out)
			local lo, hi, elite = Levels(e.levelText)
			local teaches = {}
			for k in pairs(e.teaches) do teaches[#teaches + 1] = L["teaches %s"]:format(k) .. ";" end
			table.sort(teaches)
			local row = {
				key = e.npcID or e.name, kind = "tame", name = e.name, _lname = Lower(e.name), npcID = e.npcID, family = f.name, fam = f,
				levelText = e.levelText, minLevel = lo, maxLevel = hi, elite = elite, zone = e.zone, rare = e.rare, why = e.why, speed = e.speed,
				teaches = teaches, teachList = e.teachList, icon = f.icon and (ICONS .. f.icon) or "Interface\\Icons\\Ability_Hunter_BeastTaming",
				order = f.order * 1000 + (lo or 0), tooltip = TameTooltip, generic = false, pinName = e.name,
				detail = f.name .. (e.levelText and (SEP .. L["level %s"]:format(e.levelText)) or "") .. (e.zone and (SEP .. e.zone) or "")
					.. (e.rare and (SEP .. L["rare"]) or "") .. (#e.teachList > 0 and (SEP .. Joined(e.teachList)) or ""),
				text = Lower(table.concat({ L["tameable"], "tameable tame beast", f.name, e.zone or "", e.rare and (L["rare"] .. " rare") or "",
					elite and "elite" or "", table.concat(teaches, " "), e.why or "" }, " ")),
			}
			if e.ui then
				row.ui, row.px, row.py = e.ui, e.px, e.py
				if I.SpotXY then row.wcont, row.wx, row.wy = I.SpotXY(e.ui, { e.px, e.py }) end
				out[#out + 1] = I.SpotRow(row)
			else
				row.activate, row.secondary = NoSpot, NoSpot
				out[#out + 1] = row
			end
		end
	end
	table.sort(out, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.name < b.name end)
	return out
end

--- Is the character you're on a hunter? (The only class that tames: no one else is shown @tame.)
function P.Hunter() return select(2, ns.Safe(UnitClass, "player")) == "HUNTER" end

OA.AddSetup(function()
	if not P.Hunter() then return end
	local a, f = P.Abilities(), P.Families()
	if not (a or f) then return end
	if f then P.Rares() end
	ns:RegisterProvider("tame", {
		label = L["Hunter pet"], color = "ffc8a060",
		aliases = { "tame", "tames", "tameable", "beast", "beasts", "hunterpet", "hunterpets", "petability", "petabilities",
			"beasttraining", "petskill", "petskills" },
		lazy = true, events = { "UNIT_PET", "PET_BAR_UPDATE" }, guard = 1, collect = P.Rows, -- (a pet out, an ability learned)
	})
end)
OA.AddStatus(function()
	if not ns.providers.tame then return nil end
	local a, f = P.Abilities(), P.Families()
	local ranks = 0
	for _, x in ipairs(a or {}) do ranks = ranks + #x.ranks end
	return L["%d pet ability ranks and %d families (@tame)"]:format(ranks, f and #f or 0)
end)

----------------------------------------------------------------------
-- "where to learn bite 4", "who teaches dash", "cat abilities", "tameable cats", "rare pets in the barrens"
----------------------------------------------------------------------

local TAME = { tame = true, tames = true, tameable = true, taming = true, tamable = true }
local PETW = { pet = true, pets = true, beast = true, beasts = true }
local LEARN = { learn = true, learns = true, teach = true, teaches = true, teacher = true, teachers = true, taught = true, train = true }
local ABIL = { ability = true, abilities = true, skill = true, skills = true, spells = true }
local NEAR = { nearest = true, closest = true, nearby = true, near = true }
local ASK = { i = true, im = true, ["do"] = true, does = true, the = true, a = true, an = true, to = true, where = true, are = true, is = true,
	what = true, which = true, show = true, list = true, me = true, of = true, ["for"] = true, ["in"] = true, at = true, can = true,
	who = true, how = true, get = true, find = true, my = true, level = true, all = true, hunter = true, that = true, rank = true, from = true }
local RARE = { rare = true, rares = true, named = true, unique = true }

-- a family's name as typed ("cats", "wind serpents", "owls"): the family, and how many words it took
local ALIAS = { owl = "bird of prey", owls = "bird of prey", croc = "crocolisk", crocs = "crocolisk", serpent = "wind serpent",
	hound = "core hound", hounds = "core hound", vulture = "carrion bird", vultures = "carrion bird", lion = "cat", lions = "cat",
	tiger = "cat", tigers = "cat", panther = "cat", panthers = "cat", saber = "cat", sabers = "cat", wolves = "wolf", strider = "tallstrider" }
-- (each word as typed and as one of a few: "foxes" -> "fox", "turtles" -> "turtle", "wolves" -> "wolf")
local function Forms(w)
	if ALIAS[w] then return { ALIAS[w] } end
	local t = { w }
	if w:sub(-1) == "s" then t[#t + 1] = w:sub(1, -2) end
	if w:sub(-2) == "es" then t[#t + 1] = w:sub(1, -3) end
	if w:sub(-3) == "ves" then t[#t + 1] = w:sub(1, -4) .. "f" end
	return t
end
local function FamilyAt(words, i, by)
	for n = 3, 1, -1 do
		if words[i + n - 1] then
			-- (a plural on its first word or its last: "birds of prey", "wind serpents")
			for _, first in ipairs(Forms(words[i])) do
				for _, last in ipairs(n > 1 and Forms(words[i + n - 1]) or { first }) do
					local t = { first }
					for k = i + 1, i + n - 2 do t[#t + 1] = words[k] end
					if n > 1 then t[#t + 1] = last end
					local f = by[table.concat(t, " ")]
					if f then return f, n end
				end
			end
		end
	end
end

-- an ability's name as typed ("bite", "lightning breath", "mine"), and a rank after it: the ability, its rank, how many words
local function AbilityAt(words, i, by)
	for n = 3, 1, -1 do
		if words[i + n - 1] then
			local t = {}
			for k = i, i + n - 1 do t[#t + 1] = words[k] end
			local a = by[table.concat(t, " ")]
			if a then
				local r = tonumber(words[i + n] or "")
				if not r and words[i + n] == "rank" then r = tonumber(words[i + n + 1] or "") if r then n = n + 1 end end
				return a, r, n + (r and 1 or 0)
			end
		end
	end
end

-- families and abilities by their lowercase names: made once (P.Forget), not per keystroke (review, 1.0.21)
local function Index()
	if not famIndex then
		famIndex, abIndex = {}, {}
		for _, f in ipairs(P.Families() or {}) do famIndex[Lower(f.name)] = f end
		for _, a in ipairs(P.Abilities() or {}) do abIndex[(Lower(a.name):gsub("[%p]", ""))] = a end
	end
	return famIndex, abIndex
end

--- The question: { what = "teach" (the beasts that teach a rank, or an ability's ranks), "abilities" (a family's), "tame"
--- (beasts to tame); ability, rank, family, rare, near, mine (at your level), words }, or nil when the line isn't about pets.
function P.Question(text)
	if not ns.providers.tame then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local words = {}
	for w in t:gmatch("%S+") do words[#words + 1] = w end
	local fams, abs = Index()
	local q = { words = {} }
	local tame, pet, learn, abil = false, false, false, false
	local i = 1
	while words[i] do
		local w = words[i]
		local f, nf = FamilyAt(words, i, fams)
		local a, r, na = AbilityAt(words, i, abs)
		if a and not q.ability then q.ability, q.rank = a, r; i = i + na
		elseif f and not q.family then q.family = f; i = i + nf
		else
			if TAME[w] then tame = true
			elseif PETW[w] then pet = true
			elseif LEARN[w] then learn = true
			elseif ABIL[w] then abil = true
			elseif NEAR[w] then q.near = true
			elseif RARE[w] then q.rare = true
			elseif w == "my" and words[i + 1] == "level" then q.mine = true
			elseif not ASK[w] then q.words[#q.words + 1] = w end
			i = i + 1
		end
	end
	-- "where to learn bite 4", "who teaches dash", "pet dash", "wolf furious howl": an ability's ranks, or a rank's teachers.
	-- "bite 4" alone too, for a hunter; "where to learn charge" is the warrior's unless it says pet, beast or a family
	if q.ability and P.Abilities() then
		local hunter = P.Hunter()
		local sure = pet or q.family or tame
		if not (sure or (learn and hunter) or (q.rank and (learn or hunter))) then return nil end
		if #q.words > 0 then return nil end
		q.what = "teach"
		return q
	end
	if q.ability then return nil end
	-- "cat abilities", "pet abilities", "what can a boar learn"
	if (abil or learn) and (q.family or pet) and not tame and P.Abilities() then
		if #q.words > 0 then return nil end
		q.what = "abilities"
		return q
	end
	-- "tameable cats", "where to tame a wolf", "rare pets in the barrens", "what can i tame at my level"
	if (tame or (q.rare and (pet or q.family))) and P.Families() then
		if #q.words > 0 and not P.AnyTame(q.words) then return nil end
		q.what = "tame"
		return q
	end
	return nil
end

local Has = OA.Has
function P.AnyTame(words)
	-- (the list itself, not P.Beasts' copy of it)
	local p = ns.providers.tame
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do if IsBeast(e) and Has(e, words) then return true end end
	return false
end

-- the rows by how far each is from you (those with no spot after), each saying how far; nil: where you are isn't known
local Nearest = OA.Nearest

local function Level() return Num(UnitLevel and UnitLevel("player")) or 60 end

function P.Answer(q)
	q = q or {}
	if q.what == "teach" then
		local a = q.ability
		local ranks = {}
		for _, e in ipairs(P.Ranks()) do
			if e.ability == a.name and (not q.rank or e.rank == q.rank) then ranks[#ranks + 1] = e end
		end
		if #ranks == 0 then return { ns.NoteRow(L["%s has no rank %d"]:format(a.name, q.rank or 0)) }, L["Pet abilities"] end
		-- a rank of a wild ability: the beasts that teach it, nearest first
		local e = ranks[1]
		if q.rank and a.source ~= "trainer" then
			local key = L["teaches %s"]:format(Teach(a.name, q.rank)) .. ";"
			local rows = {}
			for _, b in ipairs(P.Beasts()) do
				if Has(b, { key }) and not (q.family and b.family ~= q.family.name) then rows[#rows + 1] = b end
			end
			local title = L["Beasts that teach %s"]:format(e.name) .. SEP .. (e.detail or "")
			if #rows == 0 then return { ns.NoteRow(L["OneForAll knows no beast that teaches %s."]:format(e.name)) }, title end
			local near = Nearest(rows)
			if near then return near, title end
			ns.ScoreInOrder(rows)
			return rows, title
		end
		ns.ScoreInOrder(ranks)
		return ranks, (a.source == "trainer" and L["%s: learned at a pet trainer"] or L["%s: its ranks"]):format(a.name)
	end
	if q.what == "abilities" then
		local all = P.Ranks()
		local rows, seen = {}, {}
		local f = q.family
		local can = {}
		if f then for _, n in ipairs(f.abilities) do can[n] = true end for _, n in ipairs(f.trainer) do can[n] = true end end
		for _, e in ipairs(all) do
			if (not f or can[e.ability]) and not seen[e.ability] then
				-- (each ability once: its highest rank your level allows, else its first)
				local best
				for _, r in ipairs(all) do
					if r.ability == e.ability and (not best or ((r.level or 0) <= Level() and r.rank > best.rank)) then best = r end
				end
				seen[e.ability] = true
				rows[#rows + 1] = best
			end
		end
		ns.ScoreInOrder(rows)
		return rows, f and L["What a %s learns"]:format(f.name) or L["Pet abilities"]
	end
	-- beasts to tame
	local rows = {}
	local lvl = Level()
	for _, e in ipairs(P.Beasts()) do
		local ok = Has(e, q.words) and not (q.family and e.family ~= q.family.name) and not (q.rare and not e.rare)
			and not (q.mine and (e.minLevel or 0) > lvl)
		if ok then rows[#rows + 1] = e end
	end
	local title = (q.rare and L["Rare beasts to tame"]) or (q.family and L["%s to tame"]:format(q.family.name)) or L["Beasts to tame"]
	if q.mine then title = title .. SEP .. L["up to level %d"]:format(lvl) end
	if #rows == 0 then return { ns.NoteRow(L["No beast to tame has that"]) }, title end
	if q.near then
		local near = Nearest(rows)
		if near then return near, title end
		title = title .. SEP .. L["where you are isn't known here"]
	end
	ns.ScoreInOrder(rows)
	return rows, title
end

function P.ToAdvanced(q)
	q = q or {}
	local w = q.words and #q.words > 0 and (table.concat(q.words, " ") .. " ") or ""
	if q.what == "teach" then
		if q.rank and q.ability.source ~= "trainer" then
			return "@tame \"" .. L["teaches %s"]:format(Teach(q.ability.name, q.rank)) .. ";\" sort:distance "
		end
		return "@tame is:ability " .. Lower(q.ability.name) .. " " .. (q.rank and (q.rank .. " ") or "")
	end
	if q.what == "abilities" then return "@tame is:ability " .. (q.family and (Lower(q.family.name) .. " ") or "") end
	return "@tame " .. (q.family and (Lower(q.family.name) .. " ") or "") .. (q.rare and "rare " or "") .. (q.near and "sort:distance " or "") .. w
end
