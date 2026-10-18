local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations

-- TrainerSpells (D4KiR's), 0.57.1, the author's ask. WoW Forever (Interface 16001) loads its TrainerSpells_Camelot.toc,
-- whose tables are its data/forever files' (WoW Forever's spells, costs and trainers; not Classic Era's): those are the
-- ones read here, by the global names that build sets. Its data is read
-- while it's installed, never copied into Terminal (its licence: all rights reserved). It has no API: its global tables
-- are read as they are, each checked first; one that isn't in the shape expected is left out and said once in chat
-- (I.Failed: what's unavailable), the rest still used.
--
--   class spells         TrainerSpellsBuiltin[CLASS][level][spellID] = { cost, rank, race, faction }: every class's
--                        spells without What's Training (Providers/ClassSpells.lua; What's Training first when both),
--                        and @training, your class's spells still to learn, when What's Training isn't there
--   weapon skills        TrainerSpellsWeaponSkills: { trainers = { [npc] = { zoneID (an area), x, y, names } }, zones =
--                        { [area] = { uiMapID } }, skills = { [spellID] = { cost, level, classes, trainers = { Alliance =
--                        { npc ids }, Horde = ... } } } }: who teaches a weapon ("polearm trainer"), @training's weapon skills
--   trainers             TrainerSpells{Class,Profession,Pet,Portal}Trainers: { npcID, faction, names, tags, locations =
--                        { { uiMapID, x, y } } }: @npc's trainers when Questie isn't there ("nearest mage trainer",
--                        "nearest portal trainer", "where to learn ..."), each a spot on the map
--   profession training  TrainerSpellsBuiltin_Profession[profession][skill][spellID] = { cost, icon }: the recipes a
--                        trainer teaches you don't know, among @recipe is:unknown's ("recipes i'm missing",
--                        Providers/MissingRecipes.lua), with their cost and skill; @profession's next rank

local TS = {}
ns.TrainerSpells = TS
TS.ADDON, TS.NAME = "TrainerSpells", "TrainerSpells"

local Safe, Str, Num, Lower = ns.Safe, ns.Str, ns.Num, ns.Lower
local SEP = ns.DETAIL_SEP

--- Is TrainerSpells loaded?
function TS.Loaded()
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	if not isLoaded then return false end
	local ok, yes = pcall(isLoaded, TS.ADDON)
	return ok and yes == true
end

local parts = {} -- each part read once: its result, or false (not usable)
local spellNames, profSplit, classStatic = {}, {}, {} -- (the caches below: a spell's name, each profession's ranks and
-- crafts, your class's spells by name; none of these change in a session)
function TS.Forget() parts, spellNames, profSplit, classStatic = {}, {}, {}, {} end -- (tests)

--- One part of its data: `global` read and made usable by `make(raw)` (which gives the part, or nil and why). A part
--- whose table is missing or not in the shape expected is said once (`lost`: what's unavailable without it); `optional`:
--- a table some builds don't have, left out quietly when missing.
local function Part(key, global, lost, make, optional)
	local got = parts[key]
	if got ~= nil then return got or nil end
	if not TS.Loaded() then return nil end
	local raw = rawget(_G, global)
	local res, why
	if type(raw) ~= "table" then
		why = global .. " is " .. (raw == nil and "missing" or ("a " .. type(raw)))
		if raw == nil and optional then parts[key] = false return nil end
	else
		local ok, a, b = pcall(make, raw)
		if ok then res, why = a, b else why = tostring(a) end
	end
	if res == nil then
		I.Failed(TS.NAME, lost, why or (global .. ": nothing in the shape expected"))
		parts[key] = false
		return nil
	end
	parts[key] = res
	return res
end

----------------------------------------------------------------------
-- Class spells
----------------------------------------------------------------------

local CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true,
	WARLOCK = true, DRUID = true }
local FACTION = { A = "a", H = "h", Alliance = "a", Horde = "h" }

--- Every class's spells: CLASS -> { { id, level, raceFile, faction ("a"/"h"), rank, cost }, ... }, or nil. Weapon skills and
--- riding aren't class spells (its weapon skill list, TrainerSpellsWeaponSkills.order, leaves them out).
function TS.ClassData()
	return Part("class", "TrainerSpellsBuiltin", L["Class spells from it are unavailable."], function(raw)
		local skip = {}
		local ws = rawget(_G, "TrainerSpellsWeaponSkills")
		for _, id in ipairs(type(ws) == "table" and type(ws.order) == "table" and ws.order or {}) do
			if type(id) == "number" then skip[id] = true end
		end
		local out, good, bad = {}, 0, 0
		for cls, levels in pairs(raw) do
			if CLASSES[cls] and type(levels) == "table" then
				local list = {}
				for level, spells in pairs(levels) do
					if type(level) == "number" and type(spells) == "table" then
						for id, d in pairs(spells) do
							if type(id) == "number" and type(d) == "table" then
								if not skip[id] then
									list[#list + 1] = { id = id, level = level, raceFile = Str(d.race), faction = FACTION[d.faction or ""],
										rank = Num(d.rank), cost = Num(d.cost) }
								end
								good = good + 1
							else
								bad = bad + 1
							end
						end
					else
						bad = bad + 1
					end
				end
				out[cls] = list
			elseif CLASSES[cls] then
				bad = bad + 1
			end
		end
		if good == 0 then return nil, "TrainerSpellsBuiltin: no class spell in the shape expected (" .. bad .. " entries not)" end
		if bad > 0 then ns:Trace(("trainerspells: %d class spell entries not in the shape expected, left out"):format(bad)) end
		return out
	end)
end

----------------------------------------------------------------------
-- Trainers: @npc's, when Questie isn't there
----------------------------------------------------------------------

-- each class's name in English, as trainers' titles are matched (Search/Filters/Npcs.lua reads English titles, as
-- Questie writes them)
local CLASS_EN = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
local ICON = "Interface\\Icons\\INV_Misc_Book_11"

--- A name in the client's language from TrainerSpells' { enUS = ..., deDE = ... }, else English.
local function Named(names)
	if type(names) ~= "table" then return nil end
	return Str(names[ns.LOCALE or "enUS"]) or Str(names.enUS)
end

--- A trainer's first place with a map and coordinates: uiMapID, x, y (0-100), or nil.
local function PlaceOf(locs)
	for _, l in ipairs(type(locs) == "table" and locs or {}) do
		if type(l) == "table" and Num(l.uiMapID) and Num(l.x) and Num(l.y) then return l.uiMapID, l.x, l.y end
	end
end

-- (weapon skills and their weapon masters)
--- TrainerSpellsWeaponSkills: { skills = { [spell id] = { cost, level, classes = { CLASS = true }, trainers = { Alliance =
--- { master, ... }, Horde = { ... } } } }, masters = { [npc id] = { npc, name, uiMapId, x, y, faction } } }, or nil. Its
--- trainers' zoneID is an area (Orgrimmar's 1637), its zones table the map of each (uiMapID): a master without one is
--- kept, without a place.
function TS.WeaponData()
	return Part("weapons", "TrainerSpellsWeaponSkills", L["Its weapon masters are unavailable."], function(raw)
		if type(raw.skills) ~= "table" then return nil, "TrainerSpellsWeaponSkills.skills is " .. type(raw.skills) end
		local zones = type(raw.zones) == "table" and raw.zones or {}
		local npcs = type(raw.trainers) == "table" and raw.trainers or {}
		local masters, skills, bad = {}, {}, 0
		local function Master(id, faction)
			local m = masters[id]
			if m then return m end
			local t = npcs[id]
			local name = type(t) == "table" and Named(t.names)
			if not name then bad = bad + 1 return nil end
			local zone = Num(t.zoneID) and zones[t.zoneID]
			local ui = type(zone) == "table" and Num(zone.uiMapID) or nil
			m = { npc = id, name = name, uiMapId = ui, x = ui and Num(t.x) or nil, y = ui and Num(t.y) or nil, faction = faction }
			masters[id] = m
			return m
		end
		for id, sk in pairs(raw.skills) do
			if type(id) == "number" and type(sk) == "table" and type(sk.classes) == "table" then
				local s = { id = id, cost = Num(sk.cost) or 0, level = Num(sk.level) or 1, classes = {}, trainers = { Alliance = {}, Horde = {} } }
				for cls, yes in pairs(sk.classes) do if CLASSES[cls] and yes then s.classes[cls] = true end end
				local tr = type(sk.trainers) == "table" and sk.trainers or {}
				for _, fac in ipairs({ "Alliance", "Horde" }) do
					for _, npc in ipairs(type(tr[fac]) == "table" and tr[fac] or {}) do
						local m = type(npc) == "number" and Master(npc, fac)
						if m then s.trainers[fac][#s.trainers[fac] + 1] = m end
					end
				end
				skills[id] = s
			else
				bad = bad + 1
			end
		end
		if not next(skills) then return nil, "TrainerSpellsWeaponSkills: no weapon skill in the shape expected (" .. bad .. " entries not)" end
		if bad > 0 then ns:Trace(("trainerspells: %d weapon skill entries not in the shape expected, left out"):format(bad)) end
		return { skills = skills, masters = masters }
	end)
end

--- A trainer's row: one of @npc's, a spot on the map (Enter opens the map there with the pin, as a mailbox's does).
local function TrainerRow(t, title, shown)
	local id, name = Num(t.npcID), Named(t.names)
	if not (id and name) then return nil end
	local ui, x, y = PlaceOf(t.locations)
	local cont, wx, wy
	if ui and I.SpotXY then cont, wx, wy = I.SpotXY(ui, { x, y }) end
	local zone = ui and I.ZoneName and I.ZoneName(ui) or nil
	local fac = t.faction == "A" and "A" or t.faction == "H" and "H" or "AH"
	return {
		key = id, npcID = id, kind = "npc", name = name, _lname = Lower(name), sub = title, icon = ICON,
		-- (what Questie would say of it: its title, whom it's friendly to, that it trains; the filters read these)
		fields = { subName = title, friendlyToFaction = fac }, roles = { TRAINER = true },
		detail = shown .. (zone and (SEP .. zone) or ""), distNote = zone and (shown .. SEP .. zone) or shown,
		text = Lower(table.concat({ shown, title, "trainer", zone or "" }, " ")),
		ui = ui, mapID = ui, px = x, py = y, wcont = cont, wx = wx, wy = wy, pinName = name,
		secure = ui and ns.Maps.SECURE or nil, isOpen = ns.Maps.IsOpenFor, after = ui and I.SpotAfter or nil,
		activate = I.PinObject, secondary = I.PinObject, fromTrainerSpells = true,
	}
end

--- Every trainer TrainerSpells knows (class, profession, pet, portal, weapon masters), as @npc rows, or nil.
function TS.TrainerRows()
	return Part("trainers", "TrainerSpellsClassTrainers", L["Its trainers are unavailable."], function(classes)
		local out, seen, bad = {}, {}, 0
		local function Add(t, title, shown)
			if type(t) ~= "table" then bad = bad + 1 return end
			local row = TrainerRow(t, title, shown)
			if not row then bad = bad + 1 return end
			if not seen[row.key] then seen[row.key] = true; out[#out + 1] = row end
		end
		local CS = ns.ClassSpells
		for cls, list in pairs(classes) do
			if CLASS_EN[cls] and type(list) == "table" then
				local shown = L["%s Trainer"]:format(CS and CS.ClassName and CS.ClassName(cls) or CLASS_EN[cls])
				for _, t in ipairs(list) do Add(t, CLASS_EN[cls] .. " Trainer", shown) end
			end
		end
		local profs = rawget(_G, "TrainerSpellsProfessionTrainers")
		for prof, list in pairs(type(profs) == "table" and profs or {}) do
			if type(prof) == "string" and type(list) == "table" then
				for _, t in ipairs(list) do
					local tags = type(t) == "table" and t.tags or nil
					local tag = Named({ enUS = type(tags) == "table" and tags.enUS })
					-- (the title the filters read says which profession: "Journeyman Tailor" does; "Cenarion Circle",
					-- "Physician", "Innkeeper" (its tags, on WoW Forever) don't, so the profession is said after it)
					local title = tag or (prof .. " Trainer")
					if tag and not Lower(tag):find(Lower(prof):sub(1, 4), 1, true) then title = tag .. " (" .. prof .. " Trainer)" end
					Add(t, title, Named(tags) or title)
				end
			end
		end
		local pets = rawget(_G, "TrainerSpellsPetTrainers")
		for _, list in pairs(type(pets) == "table" and pets or {}) do
			for _, t in ipairs(type(list) == "table" and list or {}) do Add(t, "Pet Trainer", L["Pet Trainer"]) end
		end
		local portals = rawget(_G, "TrainerSpellsPortalTrainers")
		for _, list in pairs(type(portals) == "table" and portals or {}) do
			for _, t in ipairs(type(list) == "table" and list or {}) do Add(t, "Portal Trainer", L["Portal Trainer"]) end
		end
		-- the weapon masters ("polearm trainer": trainer:polearm keeps those who teach it, Search/Filters/Npcs.lua)
		local w = TS.WeaponData()
		local ids = {}
		for id in pairs(w and w.masters or {}) do ids[#ids + 1] = id end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local m = w.masters[id]
			Add({ npcID = m.npc, names = { enUS = m.name }, faction = m.faction == "Alliance" and "A" or "H",
				locations = m.uiMapId and { { uiMapID = m.uiMapId, x = m.x, y = m.y } } or nil }, "Weapon Master", L["Weapon Master"])
		end
		if #out == 0 then return nil, "no trainer in the shape expected (" .. bad .. " entries not)" end
		if bad > 0 then ns:Trace(("trainerspells: %d trainers not in the shape expected, left out"):format(bad)) end
		table.sort(out, function(a, b) return a.key < b.key end)
		return out
	end)
end

----------------------------------------------------------------------
-- Profession training: @recipe is:unknown's trainer recipes, @profession's next rank
----------------------------------------------------------------------

-- the game's skill line of each profession -> TrainerSpells' name for it (English: its tables' keys)
TS.PROF_KEY = { [171] = "Alchemy", [164] = "Blacksmithing", [185] = "Cooking", [333] = "Enchanting", [202] = "Engineering",
	[129] = "First Aid", [182] = "Herbalism", [165] = "Leatherworking", [186] = "Mining", [393] = "Skinning", [197] = "Tailoring" }

--- Each profession's spells a trainer teaches: profession -> { { id, skill, cost, icon }, ... }, and by spell id
--- (TS.Taught), or nil.
function TS.ProfData()
	return Part("prof", "TrainerSpellsBuiltin_Profession", L["Its profession training is unavailable."], function(raw)
		local out, byId, good, bad = {}, {}, 0, 0
		for prof, skills in pairs(raw) do
			if type(prof) == "string" and type(skills) == "table" then
				local list = {}
				for skill, spells in pairs(skills) do
					if type(skill) == "number" and type(spells) == "table" then
						for id, d in pairs(spells) do
							if type(id) == "number" and type(d) == "table" then
								local r = { id = id, skill = skill, cost = Num(d.cost), icon = d.icon, prof = prof }
								list[#list + 1] = r
								byId[id] = byId[id] or r
								good = good + 1
							else
								bad = bad + 1
							end
						end
					else
						bad = bad + 1
					end
				end
				table.sort(list, function(a, b) if a.skill ~= b.skill then return a.skill < b.skill end return a.id < b.id end)
				out[prof] = list
			end
		end
		if good == 0 then return nil, "TrainerSpellsBuiltin_Profession: no profession spell in the shape expected (" .. bad .. " not)" end
		if bad > 0 then ns:Trace(("trainerspells: %d profession entries not in the shape expected, left out"):format(bad)) end
		return { list = out, byId = byId }
	end)
end

--- What a trainer charges for a profession spell and the skill it needs: { cost, rank (the skill), from }, or nil
--- (Providers/MissingRecipes.lua: a recipe's trainer, before its window was opened).
function TS.Taught(id)
	local d = TS.ProfData()
	local r = d and type(id) == "number" and d.byId[id]
	return r and { cost = r.cost, rank = r.skill, from = TS.NAME } or nil
end

--- A spell's name, asked of the game once (one it hasn't loaded yet asked again next time).
local function SpellName(id)
	local n = spellNames[id]
	if n then return n end
	n = Str(Safe(C_Spell and C_Spell.GetSpellName, id))
	spellNames[id] = n
	return n
end
-- (in your spellbook, known, or the player's: Providers/ClassSpells.lua's, as What's Training asks it)
local function KnownSpell(id)
	local CS = ns.ClassSpells
	if CS and CS.Known then return CS.Known(id) end
	local f = _G.IsPlayerSpell
	return f and Safe(f, id) == true or false
end
TS.SpellName, TS.KnownSpell = SpellName, KnownSpell

--- A profession's rank (Journeyman, Expert...): a spell of the profession's own name ("Tailoring", its rank "Expert").
local function IsRank(name, pr, key)
	local n = Lower(name)
	return n == Lower(pr.name or "") or n == Lower(key)
end

--- A profession's spells in TrainerSpells, split: its ranks (Journeyman, Expert...) and the crafts a trainer teaches,
--- each by the skill it needs. Made once per profession (its names in your language: pr.name).
local function Split(pr)
	local d = TS.ProfData()
	local key = d and pr and TS.PROF_KEY[pr.skillLine or 0]
	if not key then return nil end
	local id = key .. "|" .. tostring(pr.name)
	local got = profSplit[id]
	if got then return got end
	local ranks, crafts, all = {}, {}, true
	for _, r in ipairs(d.list[key] or {}) do -- (by skill)
		local name = SpellName(r.id)
		if not name then all = false
		elseif IsRank(name, pr, key) then ranks[#ranks + 1] = r
		else crafts[#crafts + 1] = { r = r, name = name } end
	end
	got = { ranks = ranks, crafts = crafts }
	if all then profSplit[id] = got end -- (a name not loaded yet: made again next time)
	return got
end

--- Your profession's spells a trainer teaches (not its ranks) that you don't know: { { id, name, icon, skill, cost },
--- ... }, skill first (Providers/MissingRecipes.lua lists them with the recipes your windows list: a window not opened
--- yet, its trainer's still are). pr: Professions.PlayerProfessions()'s.
function TS.Unknown(pr)
	local sp = Split(pr)
	local out = {}
	for _, c in ipairs(sp and sp.crafts or {}) do
		local r = c.r
		if not KnownSpell(r.id) then
			if not c.icon then c.icon = r.icon or Safe(C_Spell and C_Spell.GetSpellTexture, r.id) or ICON end
			out[#out + 1] = { id = r.id, name = c.name, skill = r.skill, cost = r.cost, icon = c.icon }
		end
	end
	return out
end

--- Your profession's next rank at a trainer (the first you don't know): { id, title ("Journeyman"), skill (what it
--- needs), cost, now (your skill's there) }, or nil (every rank known, or TrainerSpells not there).
function TS.NextRank(pr)
	local sp = Split(pr)
	local ranks = sp and sp.ranks or {}
	if #ranks == 0 then return nil end
	-- (the first after the last one you know: Expert replaces Journeyman in the spellbook)
	local ids = {}
	for i, r in ipairs(ranks) do ids[i] = r.id end
	local CS = ns.ClassSpells
	local known = CS and CS.KnownRanks and CS.KnownRanks(ids) or {}
	for i, r in ipairs(ranks) do
		-- (a rank raises your cap 100 past the skill it needs: Journeyman, at 50, to 150; a cap that high has it)
		if not known[i] and (pr.maxRank or 0) < r.skill + 100 then
			local title = Str(Safe(C_Spell and C_Spell.GetSpellSubtext, r.id))
			return { id = r.id, title = title, skill = r.skill, cost = r.cost, now = (pr.rank or 0) >= r.skill }
		end
	end
	return nil
end

----------------------------------------------------------------------
-- @training without What's Training: your class's spells still to learn (What's Training's own rows when it's there)
----------------------------------------------------------------------

local function ClassOfPlayer() return select(2, Safe(UnitClass, "player")) end

local function TrainingTooltip(e, t)
	if not pcall(t.SetHyperlink, t, "spell:" .. tostring(e.wtId)) then t:SetText(e.name, 1, 0.82, 0) end
	t:AddLine(" ")
	local said = (e.state == "now" and L["You can learn it now"])
		or (e.state == "nextlevel" and L["You can learn it at level %d (next level)"]:format(e.level or 0))
		or (e.state == "later" and L["You can learn it at level %d"]:format(e.level or 0))
		or (e.state == "needsrank" and L["Learn the rank before it first"]) or (e.state == "known" and L["You know it"]) or ""
	local WT = ns.WhatsTraining
	local c = WT and WT.RGB and WT.RGB[e.state] or { 1, 1, 1 } -- (What's Training's colours: green now, blue soon, red later)
	t:AddLine(said, c[1], c[2], c[3], true)
	if (e.cost or 0) > 0 then t:AddDoubleLine(L["Costs"], ns.Money(e.cost), 1, 1, 1, 1, 1, 1) end
	for _, line in ipairs(WT and WT.SourceLines and WT.SourceLines(e) or {}) do t:AddLine(line, 1, 1, 1, true) end
	t:AddLine(L["As TrainerSpells lists it."], 0.6, 0.6, 0.6)
	ns.KeyHints(t, L["Enter: list who teaches it, the nearest first    Shift+Enter: link it in chat"], 0.6, 0.6, 0.6, true)
end

local function Teaches(e) local WT = ns.WhatsTraining; if WT and WT.WhoTeaches then WT.WhoTeaches(e) end end
-- (its link asked for when it's used, not for every row a list makes)
local function LinkOf(e)
	local l = rawget(e, "link")
	if l == nil then
		l = Str(Safe(C_Spell and C_Spell.GetSpellLink, e.wtId)) or false
		e.link = l
	end
	return l or nil
end
local function LinkTraining(e) ns.LinkInChat(LinkOf(e) or e.name) end
local function ShareTraining(e)
	LinkOf(e)
	local WT = ns.WhatsTraining
	return WT and WT.ShareText and WT.ShareText(e) or e.name
end

-- the words a row is found by (What's Training's rows': Providers/Integrations/WhatsTraining.lua)
local WORDS = { now = "now available learnable trainable", needsrank = "requirements needs rank", nextlevel = "next level soon coming",
	later = "later", known = "known" }

local function TrainingRow(id, name, rank, state, level, cost, weapon, icon)
	local WT = ns.WhatsTraining
	local e = {
		kind = "training", key = id, wtId = id, spellName = name, rank = rank,
		name = rank and (name .. " (" .. rank .. ")") or name,
		state = state, weapon = weapon or nil, level = level, cost = cost or 0,
		icon = icon or Safe(C_Spell and C_Spell.GetSpellTexture, id) or ICON,
		activate = Teaches, staysOpen = true, tooltip = TrainingTooltip, secondary = LinkTraining,
		shareLink = ShareTraining, getLink = LinkOf, fromTrainerSpells = true,
	}
	e.color = WT and WT.HEX and WT.HEX[state] or nil
	e.detail = WT and WT.Detail and WT.Detail(e) or ""
	e.text = table.concat({ "train training trainable", WORDS[state] or "", weapon and "weapon skill" or "",
		rank and Lower(rank) or "", level and ("level " .. level) or "" }, " ")
	return e
end

local function Before(a, b) -- (a's rank comes before b's)
	if a.r.level ~= b.r.level then return a.r.level < b.r.level end
	return (a.r.rank or 0) < (b.r.rank or 0)
end

local trainingKnown = {} -- (the weapon skills you know: "daggers > learn" starts from them, Search/WhatsTraining.lua)
function TS.TrainingKnown() return trainingKnown end

--- @training's rows from TrainerSpells: your class's spells (your race's and faction's) and weapon skills you don't
--- know, each learn now, next level, later, or after an earlier rank ("needsrank": one not known, or a first rank no
--- trainer teaches: a talent's or a quest's). What's Training's order: learn now first, then by level and name.
function TS.TrainingRows()
	trainingKnown = {}
	local data = TS.ClassData()
	local cls = ClassOfPlayer()
	if not (data and cls) then return {} end
	local level = Num(Safe(UnitLevel, "player")) or 1
	local race = Str((select(2, Safe(UnitRace, "player"))))
	local fac = FACTION[Str(Safe(UnitFactionGroup, "player")) or ""]
	-- your class's spells (your race's and faction's), each with its name and icon and its ranks together: made once
	local id = cls .. "|" .. tostring(race) .. "|" .. tostring(fac)
	local st = classStatic[id]
	if not st then
		local mine, byName, all = {}, {}, true
		for _, r in ipairs(data[cls] or {}) do
			if (not r.raceFile or not race or r.raceFile == race) and (not r.faction or not fac or r.faction == fac) then
				local name = SpellName(r.id)
				if name then
					local k = { r = r, name = name }
					mine[#mine + 1] = k
					byName[name] = byName[name] or {}
					table.insert(byName[name], k)
				else
					all = false
				end
			end
		end
		for _, list in pairs(byName) do table.sort(list, Before) end
		st = { mine = mine, byName = byName }
		if all then classStatic[id] = st end -- (a name not loaded yet: made again next time)
	end
	local mine, byName = st.mine, st.byName
	for _, k in ipairs(mine) do k.known = KnownSpell(k.r.id) end
	-- (a rank a later one replaced: the spellbook says it isn't known, but it was learned; 0.57.2, the player's level
	-- 30 warrior had Battle Shout Rank 1 to learn)
	for _, list in pairs(byName) do
		local last = 0
		for i, k in ipairs(list) do if k.known then last = i end end
		for i = 1, last do list[i].known = true end
	end
	local rows = {}
	for _, k in ipairs(mine) do
		if not k.known then
			local r = k.r
			local state = (r.level > level + 1 and "later") or (r.level == level + 1 and "nextlevel") or "now"
			if state == "now" then
				local earlier, anyKnown = false, false
				for _, o in ipairs(byName[k.name]) do
					if o.known then anyKnown = true end
					if o ~= k and not o.known and Before(o, k) then earlier = true end
				end
				-- (a later rank of a spell whose first no trainer teaches, none of it known: a talent's, a quest's)
				if earlier or ((r.rank or 0) > 1 and not anyKnown and #byName[k.name] == 1) then state = "needsrank" end
			end
			-- (the game's rank text; else TrainerSpells' rank, for a spell of more than one; its icon: each asked once)
			if k.rank == nil then
				k.rank = Str(Safe(C_Spell and C_Spell.GetSpellSubtext, r.id))
					or (r.rank and (r.rank > 1 or #byName[k.name] > 1) and L["Rank %d"]:format(r.rank)) or false
				k.icon = Safe(C_Spell and C_Spell.GetSpellTexture, r.id) or ICON
			end
			rows[#rows + 1] = TrainingRow(r.id, k.name, k.rank or nil, state, r.level, r.cost, nil, k.icon)
		end
	end
	local w = TS.WeaponData()
	for id, sk in pairs(w and w.skills or {}) do
		local name = sk.classes[cls] and SpellName(id)
		if name then
			local known = KnownSpell(id)
			local state = (known and "known") or (sk.level > level + 1 and "later") or (sk.level == level + 1 and "nextlevel") or "now"
			local e = TrainingRow(id, name, nil, state, sk.level, sk.cost, true)
			if known then trainingKnown[#trainingKnown + 1] = e else rows[#rows + 1] = e end
		end
	end
	local ORDER = { now = 1, needsrank = 2, nextlevel = 3, later = 4 }
	table.sort(rows, function(a, b)
		if a.state ~= b.state then return ORDER[a.state] < ORDER[b.state] end
		if (a.weapon == true) ~= (b.weapon == true) then return not a.weapon end -- (spells, then weapon skills)
		if a.level ~= b.level then return (a.level or 0) < (b.level or 0) end
		return a.name < b.name
	end)
	ns.RankInOrder(rows)
	return rows
end

----------------------------------------------------------------------
-- Starting (at login: Setup.lua's I.Setup) and .integrations
----------------------------------------------------------------------

local function SetupTrainerSpells()
	if TS.on or not TS.Loaded() then return end
	TS.on = true
	-- (each part read now, so one not as expected is said at login, not on a keystroke)
	local classes = TS.ClassData()
	TS.WeaponData()
	local trainers = TS.TrainerRows()
	-- its trainers as @npc only with no Questie (Questie knows every NPC, these among them; it takes @npc if it comes)
	if trainers and not ns.providers.npc then
		ns:RegisterProvider("npc", {
			label = L["NPC"], color = "ffe0a060", aliases = { "npc", "npcs", "n" },
			explicit = true, trainersOnly = true, -- (Setup.lua: Questie's still missing for every other NPC)
			collect = function() return TS.TrainerRows() or {} end,
		})
	end
	-- @training, your class's spells still to learn, when What's Training hasn't made it (its rows are richer: its
	-- discounts, talents, pet abilities and books; it's set up first, Setup.lua)
	if classes and not ns.providers.training then
		local list
		ns:RegisterProvider("training", {
			label = L["Training"], color = "ff82c5ff", aliases = { "training", "train", "trainable" },
			fromTrainerSpells = true, guard = 1,
			events = { "PLAYER_LEVEL_UP", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED" },
			leadRow = ns.EmptyLead(L["Nothing left to train: you know every spell TrainerSpells lists for you"],
				function() return not (list and #list > 0) end),
			collect = function() list = TS.TrainingRows() return list end,
		})
	end
	-- (its profession training: @recipe is:unknown's trainer recipes, @profession's next rank)
	TS.ProfData()
	ns:Changed("missing")
	ns:Changed("professions")
	local CS = ns.ClassSpells
	if CS and CS.Forget then CS.Forget() end -- (its class spells and weapon masters, when What's Training's aren't there)
	if CS and CS.ForgetRows then CS.ForgetRows() end
end
I._.SetupTrainerSpells = SetupTrainerSpells

--- .integrations' line about TrainerSpells.
function TS.Status()
	if not TS.Loaded() then return L["not found"] end
	local AddOnVersion = I._.AddOnVersion
	local said = {}
	local c, t, p = TS.ClassData(), TS.TrainerRows(), TS.ProfData()
	if p then
		local n = 0
		for _, list in pairs(p.list) do n = n + #list end
		said[#said + 1] = L["%d profession spells (@recipe is:unknown, @profession)"]:format(n)
	end
	if t then
		local p2 = ns.providers.npc
		said[#said + 1] = (p2 and p2.trainersOnly) and L["%d trainers (@npc, without Questie)"]:format(#t)
			or L["%d trainers (Questie's @npc has them)"]:format(#t)
	end
	if c then
		local CS = ns.ClassSpells
		said[#said + 1] = (CS and CS.Api and CS.Api()) and L["class spells (What's Training's used)"] or L["class spells (without What's Training)"]
		local tr = ns.providers.training
		if tr and tr.fromTrainerSpells then said[#said + 1] = L["@training (without What's Training)"] end
	end
	return L["found (%s)."]:format(AddOnVersion and AddOnVersion(TS.ADDON) or "?") .. (#said > 0 and (" " .. table.concat(said, ", ")) or "")
end
