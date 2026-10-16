local ns = select(2, ...)
local L = ns.L

-- Every class's spells, known or not (0.54.1, a player's ask: "'travel form' doesn't list the spell since I don't
-- currently have it. Ideally it'd tell me that it's a druid spell trainable at level 30"; "healing wave" on a druid
-- found only a talent; "druid spells" found nothing). @classspell: a row per spell of every class (ClassSpellData.lua,
-- What's Training's data), with the level each rank is learned at; your own class's only those you don't know yet
-- (the spellbook has the rest). Enter shows its Wowhead page, Shift+Enter links it in chat. class:druid narrows to a
-- class; "druid spells", "upcoming spells" are Search/ClassSpells.lua's questions.

local CS = {}
ns.ClassSpells = CS

local Safe, Str, Lower = ns.Safe, ns.Str, ns.Lower
CS.MINE_RANK, CS.OTHER_RANK = -1, -1.6 -- (below your spellbook's and @training's rows among equal matches)
CS.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local parsed -- CLASS -> { { id, level, race, faction ("a"/"h"), talent, quest }, ... }
--- The data read: each class's ranks, by level.
function CS.Data()
	if parsed then return parsed end
	parsed = {}
	for cls, s in pairs(ns.ClassSpellData or {}) do
		local list = {}
		for entry in s:gmatch("[^,]+") do
			local id, level, marks = entry:match("^(%d+):(%d+)(.*)$")
			if id then
				local r = { tonumber(id), tonumber(level) }
				for m in marks:gmatch(":([^:]+)") do
					if m:sub(1, 1) == "r" then r.race = tonumber(m:sub(2))
					elseif m == "a" or m == "h" then r.faction = m
					elseif m == "t" then r.talent = true
					elseif m == "q" then r.quest = true end
				end
				list[#list + 1] = r
			end
		end
		parsed[cls] = list
	end
	return parsed
end
function CS.Forget() parsed = nil end -- (tests)

function CS.MyClass()
	local ok, name, file = pcall(UnitClass, "player")
	if ok then return file, name end
end
local function ClassName(file)
	local m = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
	return (type(m) == "table" and Str(m[file])) or (file:sub(1, 1) .. file:sub(2):lower())
end
CS.ClassName = function(file) return ClassName(file) end
local function Known(id)
	local f = rawget(_G, "IsPlayerSpell") or (C_SpellBook and C_SpellBook.IsSpellKnown)
	return f and Safe(f, id) == true or false
end
CS.Known = Known

--- A class's spells by name, in the order they're first learned: { name, ranks = { {id, level, quest, talent}, ... },
--- level (the first rank's), quest, talent }. `mine`: your class (your race's and faction's alone).
function CS.Spells(cls, mine)
	local race, faction
	if mine then
		race = select(3, Safe(UnitRace, "player"))
		local f = Str(Safe(UnitFactionGroup, "player"))
		faction = f == "Alliance" and "a" or f == "Horde" and "h" or nil
	end
	local byName, out = {}, {}
	for _, r in ipairs(CS.Data()[cls] or {}) do
		local fits = not mine or ((not r.race or r.race == race) and (not r.faction or not faction or r.faction == faction))
		local name = fits and Str(Safe(C_Spell and C_Spell.GetSpellName, r[1]))
		if name and not ns.Secret(name) then
			local s = byName[name]
			if not s then
				s = { name = name, ranks = {}, level = r[2] }
				byName[name] = s
				out[#out + 1] = s
			end
			s.ranks[#s.ranks + 1] = { r[1], r[2], r.quest, r.talent }
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
CS.Levels = Levels

local function Tooltip(e, t)
	local s = rawget(e, "_s")
	local shown = pcall(t.SetHyperlink, t, "spell:" .. s.ranks[1][1])
	if not shown then t:SetText(e.name, 1, 0.82, 0) end
	t:AddLine(" ") -- (whose spell it is, the row says already: 0.54.8, the player)
	local lvl = Safe(UnitLevel, "player")
	for i, r in ipairs(s.ranks) do
		if i > 14 then t:AddLine(L["and %d more"]:format(#s.ranks - 14), 0.6, 0.6, 0.6) break end
		local rank = Str(Safe(C_Spell and C_Spell.GetSpellSubtext, r[1]))
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
	if not mine then others[cls] = rows end
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
-- Weapon masters (0.54.1: "dagger trainer" and "where do i learn daggers" without What's Training too)
----------------------------------------------------------------------

--- The weapon masters who teach any of these weapon skills (spell ids) to your faction: What's Training's when it's
--- there, else Terminal's copy of its list (ClassSpellData.lua). A set of NPC ids, and their records { npc, name,
--- uiMapId, x, y } (x, y: 0-100).
function CS.WeaponMasters(ids)
	local WT = ns.WhatsTraining
	if WT and WT.Api and WT.Api() and WT.MasterIds then
		local set, list = WT.MasterIds(ids)
		if set and next(set) then return set, list end
	end
	local f = Str(Safe(UnitFactionGroup, "player"))
	f = f == "Alliance" and "a" or f == "Horde" and "h" or nil
	local want = {}
	for _, id in ipairs(ids or {}) do want[id] = true end
	local set, list = {}, {}
	for npc, m in pairs(ns.WeaponMasterData or {}) do
		local teaches = false
		for _, sk in ipairs(m[6]) do if want[sk] then teaches = true break end end
		if teaches and (not f or m[1] == f) then
			set[npc] = true
			list[#list + 1] = { npc = npc, name = m[5], uiMapId = m[2], x = m[3], y = m[4] }
		end
	end
	table.sort(list, function(a, b) return a.npc < b.npc end)
	return set, list
end
