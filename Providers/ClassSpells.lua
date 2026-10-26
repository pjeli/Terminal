local ns = select(2, ...)
local L = ns.L

-- Every class's spells, known or not (0.54.1, a player's ask: "'travel form' doesn't list the spell since I don't
-- currently have it. Ideally it'd tell me that it's a druid spell trainable at level 30"; "healing wave" on a druid
-- found only a talent; "druid spells" found nothing). @classspell: a row per spell of every class, with the level each
-- rank is learned at; your own class's only those you don't know yet (the spellbook has the rest). Enter shows its
-- Wowhead page, Shift+Enter links it in chat. class:druid narrows to a class; "druid spells", "upcoming spells" are
-- Search/Questions/ClassSpells.lua's questions.
--
-- The spells come from What's Training (0.56.1, the player: "I would prefer to rely on WT"): its WT_API.GetCatalog,
-- every class's trainer and quest spells with their levels, races and factions, and its weapon masters. Terminal
-- kept a copy of that data before. Without What's Training, TrainerSpells' (0.57.1: its class spells by level, read
-- while it's installed, Integrations/TrainerSpells.lua); with neither these lists are empty and the footer says to
-- install What's Training.

local CS = {}
ns.ClassSpells = CS

local Safe, Str, Lower = ns.Safe, ns.Str, ns.Lower
CS.MINE_RANK, CS.OTHER_RANK = -1, -1.6 -- (below your spellbook's and @training's rows among equal matches)
CS.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local cachedFor -- (the API the data below was read from: another one, read again)
local bySkill -- weapon skill id -> faction -> { trainer records }, read once from the catalogs (CS.Forget: again)

--- What's Training's API when it has the catalog (GetCatalog), else nil.
function CS.Api()
	local WT = ns.WhatsTraining
	local api = WT and WT.Api and WT.Api()
	if not api then return nil end
	local ok, f = pcall(function() return api.GetCatalog end)
	api = ok and type(f) == "function" and api or nil
	if api and api ~= cachedFor then
		cachedFor = api
		if CS.Forget then CS.Forget() end
	end
	return api
end

--- One class's catalog from What's Training (a list of its entries), or nil.
local loading = {}
local function Catalog(api, cls)
	if not loading[cls] and type(api.LoadClass) == "function" then
		-- (its names, rank texts and links loaded: asked once per class; ClassReady says when, Integrations/WhatsTraining)
		loading[cls] = true
		pcall(api.LoadClass, cls)
	end
	local ok, cat = pcall(api.GetCatalog, cls)
	return ok and type(cat) == "table" and cat or nil
end

local FACTION = { Alliance = "a", Horde = "h" }
local parsed -- CLASS -> { { id, level, races, raceFiles (a set), faction ("a"/"h"), talent, quest, name, rank }, ... }

--- TrainerSpells' class spells when What's Training's catalog isn't there: CLASS -> { { id, level, raceFiles, faction,
--- rank }, ... } (Integrations/TrainerSpells.lua reads and checks them), or nil.
function CS.FromTrainerSpells()
	local TS = ns.TrainerSpells
	return TS and TS.ClassData and TS.ClassData() or nil
end

--- The data: each class's ranks, by level (What's Training's trainer and quest spells; not its weapon skills or tomes;
--- else TrainerSpells').
function CS.Data()
	if parsed then return parsed end
	local api = CS.Api()
	if not api then
		local ts = CS.FromTrainerSpells()
		if not ts then return {} end -- (not kept: What's Training or TrainerSpells may come later)
		parsed = {}
		for _, cls in ipairs(CS.CLASSES) do
			local list = {}
			for _, r in ipairs(ts[cls] or {}) do
				list[#list + 1] = { r.id, r.level, raceFiles = r.raceFiles, faction = r.faction, rank = r.rank }
			end
			table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
			parsed[cls] = list
		end
		return parsed
	end
	parsed = {}
	for _, cls in ipairs(CS.CLASSES) do
		local list = {}
		for _, e in ipairs(Catalog(api, cls) or {}) do
			if type(e) == "table" and type(e.id) == "number" and type(e.level) == "number" and (e.kind == "trainer" or e.kind == "quest") then
				-- (a copy: a quest's variants' races are added to it, and What's Training's own list isn't Terminal's to grow)
				local races = type(e.races) == "table" and { unpack(e.races) } or nil
				if e.kind == "quest" and type(e.quest) == "table" then -- (a quest's races: each of its variants')
					for _, v in ipairs(e.quest) do
						if type(v) ~= "table" or type(v.races) ~= "table" then races = nil break end
						races = races or {}
						for _, r in ipairs(v.races) do races[#races + 1] = r end
					end
				end
				list[#list + 1] = { e.id, e.level, races = races, faction = FACTION[e.faction], talent = e.requiredTalentId ~= nil or nil,
					quest = e.kind == "quest" or nil, name = Str(e.name), rank = Str(e.subText) }
			end
		end
		table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
		parsed[cls] = list
	end
	return parsed
end
function CS.Forget() parsed, bySkill = nil, nil end -- (What's Training's names came in; tests)
function CS.ForgetLoads() loading = {} end -- (tests)

function CS.MyClass()
	local ok, name, file = pcall(UnitClass, "player")
	if ok then return file, name end
end
local function ClassName(file)
	local m = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
	return (type(m) == "table" and Str(m[file])) or (file:sub(1, 1) .. file:sub(2):lower())
end
CS.ClassName = function(file) return ClassName(file) end
--- Is this spell (this rank of it) yours? Asked as What's Training and TrainerSpells ask it: in your spellbook, known,
--- or the player's own (0.57.2: IsPlayerSpell alone missed spells WoW Forever's spellbook has). A rank a later one
--- replaced may still say no: CS.KnownRanks.
local function Known(id)
	if type(id) ~= "number" then return false end
	local SB = C_SpellBook
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	if SB and SB.IsSpellInSpellBook and Safe(SB.IsSpellInSpellBook, id, bank, false) == true then return true end
	if SB and SB.IsSpellKnown and Safe(SB.IsSpellKnown, id, bank) == true then return true end
	local f = rawget(_G, "IsPlayerSpell")
	return f and Safe(f, id) == true or false
end
CS.Known = Known

--- Which of a spell's ranks (in the order they're learned) you have: the ones you know, and every one before the last
--- you know (a new rank replaces the one before it in the spellbook, which then says it isn't known: a level 30
--- warrior's Battle Shout Rank 1; 0.57.2). A list of true/false, one per rank.
function CS.KnownRanks(ids)
	local out, last = {}, 0
	for i, id in ipairs(ids) do
		out[i] = Known(id)
		if out[i] then last = i end
	end
	for i = 1, last do out[i] = true end
	return out
end

local function Has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

--- A class's spells by name, in the order they're first learned: { name, ranks = { {id, level, quest, talent}, ... },
--- level (the first rank's), quest, talent }. `mine`: your class (your race's and faction's alone).
function CS.Spells(cls, mine)
	local race, faction, raceFile
	if mine then
		race = select(3, Safe(UnitRace, "player"))
		raceFile = Str(select(2, Safe(UnitRace, "player"))) -- (TrainerSpells names races by the game's file name: "Scourge")
		local f = Str(Safe(UnitFactionGroup, "player"))
		faction = f == "Alliance" and "a" or f == "Horde" and "h" or nil
	end
	local byName, out = {}, {}
	for _, r in ipairs(CS.Data()[cls] or {}) do
		local fits = not mine or ((not r.races or not race or Has(r.races, race)) and (not r.faction or not faction or r.faction == faction)
			and (not r.raceFiles or not raceFile or r.raceFiles[raceFile])) -- (TrainerSpells': one race or a list of them)
		local name = fits and (Str(Safe(C_Spell and C_Spell.GetSpellName, r[1])) or r.name)
		if name and not ns.Secret(name) then
			local s = byName[name]
			if not s then
				s = { name = name, ranks = {}, level = r[2] }
				byName[name] = s
				out[#out + 1] = s
			end
			s.ranks[#s.ranks + 1] = { r[1], r[2], r.quest, r.talent, r.rank }
			if r.quest then s.quest = true end
			if r.talent then s.talent = true end
		end
	end
	return out
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local function FirstId(e) return rawget(e, "_s").ranks[1][1] end
local function Link(e) return Safe(C_Spell and C_Spell.GetSpellLink, FirstId(e)) end
CS.WOWHEAD = "https://www.wowhead.com/forever/spell=%d"
local function ShowOnWowhead(e)
	ns:ShowText(L["Wowhead: %s"]:format(tostring(e.name)), CS.WOWHEAD:format(FirstId(e)), { compact = true })
end
local function LinkIt(e) ns.LinkInChat(Link(e)) end
local CHATBOX = ns.ChatBoxSpec(Link)

--- "level 30", "levels 10-60 (6 ranks)".
local function Levels(s)
	local first, last = s.ranks[1][2], s.ranks[#s.ranks][2]
	if #s.ranks == 1 then return L["level %d"]:format(first) end
	return L["levels %d-%d (%d ranks)"]:format(first, last, #s.ranks)
end

local function Tooltip(e, t)
	local s = rawget(e, "_s")
	local shown = pcall(t.SetHyperlink, t, "spell:" .. s.ranks[1][1])
	if not shown then t:SetText(e.name, 1, 0.82, 0) end
	t:AddLine(" ") -- (whose spell it is, the row says already: 0.54.8, the player)
	local lvl = Safe(UnitLevel, "player")
	for i, r in ipairs(s.ranks) do
		if i > 14 then t:AddLine(L["and %d more"]:format(#s.ranks - 14), 0.6, 0.6, 0.6) break end
		local rank = Str(Safe(C_Spell and C_Spell.GetSpellSubtext, r[1])) or r[5]
		local left = (rank and (rank .. "  ") or "") .. L["level %d"]:format(r[2]) .. (r[3] and ("  " .. L["(a quest)"]) or "")
		local mine = e.mine and type(lvl) == "number" and r[2] <= lvl
		t:AddDoubleLine(left, L["ID %d"]:format(r[1]), mine and 0.25 or 1, 1, mine and 0.25 or 1, 0.6, 0.6, 0.6)
	end
	if s.talent then t:AddLine(L["A rank needs a talent first"], 1, 1, 1, true) end
	ns.KeyHints(t, L["Enter: show its Wowhead page    Shift+Enter: link it in chat"], 0.6, 0.6, 0.6, true)
end

local LAZY = {
	detail = function(t)
		local s = rawget(t, "_s")
		local parts = { t.classShown, Levels(s) }
		if s.quest then parts[#parts + 1] = L["a quest"] end
		if rawget(t, "known") then
			parts[#parts + 1] = L["you know it"]
		elseif t.mine then
			local lvl = Safe(UnitLevel, "player")
			if type(lvl) == "number" and s.level <= lvl then parts[#parts + 1] = "|cff40ff40" .. L["you can learn it now"] .. "|r" end
		end
		return ns.Detail(unpack(parts))
	end,
	icon = function(t) return Safe(C_Spell and C_Spell.GetSpellTexture, FirstId(t)) or "Interface\\Icons\\INV_Misc_Book_09" end,
	spellID = FirstId,
	level = function(t) return rawget(t, "_s").level end,
}

local others = {} -- class -> its rows: another class's never change (made once a session)

--- A class's rows: your own class's only those you don't know (`all`: every one, those you know said so).
function CS.Rows(cls, mine, all)
	if not mine and others[cls] then return others[cls] end
	local cname = ClassName(cls)
	local hex = ns.ClassHex and ns.ClassHex(cls)
	local shown = hex and (hex .. cname .. "|r") or cname
	local meta = ns:CompactMeta(ns.providers.classspells, {
		classFile = cls, className = cname, classShown = shown, mine = mine or nil,
		getLink = Link, activate = ShowOnWowhead, tooltip = Tooltip,
		secondary = LinkIt, secondarySecure = CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen,
	}, LAZY)
	local rows = {}
	local ltext = Lower(cname .. " spell spells ability abilities class")
	for _, s in ipairs(CS.Spells(cls, mine)) do
		local known = false
		if mine then for _, r in ipairs(s.ranks) do if Known(r[1]) then known = true break end end end
		if not known or all then
			rows[#rows + 1] = setmetatable({ _compact = true, key = cls .. ":" .. s.ranks[1][1], name = s.name, _s = s,
				_rank = mine and CS.MINE_RANK or CS.OTHER_RANK, _lname = Lower(s.name),
				_ltext = ltext .. (s.quest and " quest" or ""), known = known or nil }, meta)
		end
	end
	if not mine and #rows > 0 then others[cls] = rows end -- (none: What's Training not there yet)
	return rows
end
function CS.ForgetRows() others = {} end -- (tests)

ns:RegisterProvider("classspells", {
	-- (one list with your spellbook since 0.54.6: its rows say Spell, in the spellbook's colour too; 0.54.7, the player)
	label = L["Spell"],
	color = "ff9d7bff",
	-- (0.54.6: reached through @spell, which looks in these too; its words, @classspell and the rest, are @spell's now)
	aliases = {}, noKind = true, reach = "@spell", oneWith = "spells", -- (part of @spell to the player: its colour too)
	events = { "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP" },
	guard = 2,
	collect = function()
		local out = {}
		local mine = CS.MyClass()
		for _, cls in ipairs(CS.CLASSES) do
			for _, e in ipairs(CS.Rows(cls, cls == mine)) do out[#out + 1] = e end
		end
		return out
	end,
})

----------------------------------------------------------------------
-- Weapon masters ("dagger trainer", trainer:daggers): What's Training's or TrainerSpells', for every class's weapon skills
----------------------------------------------------------------------

--- What's Training's weapon masters: weapon skill id -> faction -> { trainer records }, or nil without it.
local function WTMasters()
	local api = CS.Api()
	if not api then return nil end
	if not bySkill then
		bySkill = {}
		for _, cls in ipairs(CS.CLASSES) do
			for _, e in ipairs(Catalog(api, cls) or {}) do
				if type(e) == "table" and e.kind == "weaponMaster" and e.id ~= nil and type(e.trainers) == "table" then
					local f = bySkill[e.id] or {}
					bySkill[e.id] = f
					for fac, ts in pairs(e.trainers) do
						f[fac] = f[fac] or {}
						for _, t in ipairs(type(ts) == "table" and ts or {}) do
							if type(t) == "table" and type(t.npc) == "number" then f[fac][#f[fac] + 1] = t end
						end
					end
				end
			end
		end
	end
	return bySkill
end

--- TrainerSpells' weapon masters (0.57.1: "polearm trainer" without What's Training listed every weapon master), in
--- the same shape, or nil.
local function TSMasters()
	local TS = ns.TrainerSpells
	local w = TS and TS.WeaponData and TS.WeaponData()
	if not w then return nil end
	local out = {}
	for id, s in pairs(w.skills) do out[id] = s.trainers end
	return out
end

--- The weapon masters who teach any of these weapon skills (spell ids) to your faction: a set of NPC ids, and their
--- records { npc, name, uiMapId, x, y } (x, y: 0-100). What's Training's; TrainerSpells' when it has none of them (not
--- installed, or not those skills); nil with neither.
function CS.WeaponMasters(ids)
	local faction = Str(Safe(UnitFactionGroup, "player"))
	local function From(by)
		local set, list = {}, {}
		for _, id in ipairs(ids or {}) do
			for fac, ts in pairs(by[id] or {}) do
				if not faction or fac == faction then
					for _, t in ipairs(ts) do
						if not set[t.npc] then set[t.npc] = true; list[#list + 1] = t end
					end
				end
			end
		end
		table.sort(list, function(a, b) return a.npc < b.npc end)
		return set, list
	end
	local wt, ts = WTMasters(), nil
	if wt then
		local set, list = From(wt)
		if next(set) then return set, list end
	end
	ts = TSMasters()
	if ts then return From(ts) end
	if wt then return From(wt) end
	return nil
end
