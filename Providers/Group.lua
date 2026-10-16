local ns = select(2, ...)
local L = ns.L

-- Your group (@group, @party; Simple mode: "who is dead", "who needs fortitude", "who is out of range", "group
-- healers", under Group): every member (you too) with what the game says of them now: role, dead, offline, out of
-- range, and the group's buffs they're missing. A buff counts as one the group should have when someone in the group
-- can cast it: Fortitude with a priest, Arcane Intellect with a mage, Mark of the Wild with a druid, a Blessing with a
-- paladin, Divine Spirit (a talent) only once someone has it; Shadow Protection never on its own (ask for it by name:
-- "who needs shadow protection", missing:<any buff name>).
--
--   Enter        targets them (the game presses /target <unit>)
--   Shift+Enter  casts the first buff they're missing that you have, on them (/cast [@unit] <spell>)
--
-- What Midnight's API hides (Forever's API docs, Blizzard_APIDocumentationGenerated): only while an addon restriction
-- is active (C_RestrictedActions: in combat, in a boss fight, in a keystone, in a PvP match, on a restricted map), the
-- game hands addons secret values for: UnitInRange (SecretReturns), auras (SecretWhenUnitAuraRestricted:
-- C_Secrets.ShouldAurasBeSecret), roles, names and classes (SecretWhenUnitIdentityRestricted:
-- C_Secrets.ShouldUnitIdentityBeSecret), health (SecretReturns; not used here). Never secret: UnitIsDeadOrGhost,
-- UnitIsConnected, UnitLevel. Being in a dungeon alone hides nothing. Every value is read through the secret guards: a
-- hidden one shows as hidden (never compared), and a row says what the game hides right now and why.

local GR = {}
ns.Group = GR

local Safe, Num, Str, Lower, Secret = ns.Safe, ns.Num, ns.Str, ns.Lower, ns.Secret

-- the buffs, by family: the spells that give it (single first, the group version after; any rank: the name is the same),
-- the class that casts it, the words that name it, and the short name rows use
GR.BUFFS = {
	{ id = "fortitude", label = L["Fortitude"], chat = L["Fortitude"], class = "PRIEST", spells = { 1243, 21562 },
		names = { "Power Word: Fortitude", "Prayer of Fortitude" }, words = { "fortitude", "fort", "pwf", "stamina" } },
	{ id = "intellect", label = L["Intellect"], chat = L["Intellect"], class = "MAGE", spells = { 1459, 23028 },
		names = { "Arcane Intellect", "Arcane Brilliance" }, words = { "intellect", "int", "ai", "brilliance", "ab" } },
	{ id = "wild", label = L["Mark of the Wild"], chat = L["Mark of the Wild"], class = "DRUID", spells = { 1126, 21849 },
		names = { "Mark of the Wild", "Gift of the Wild" }, words = { "mark", "motw", "wild", "gotw" } },
	{ id = "spirit", label = L["Divine Spirit"], chat = L["Divine Spirit"], class = "PRIEST", talent = true, spells = { 14752, 27681 },
		names = { "Divine Spirit", "Prayer of Spirit" }, words = { "spirit", "ds" } },
	{ id = "shadow", label = L["Shadow Protection"], chat = L["Shadow Protection"], class = "PRIEST", optional = true, spells = { 976, 27683 },
		names = { "Shadow Protection", "Prayer of Shadow Protection" }, words = { "shadow" } },
	{ id = "blessing", label = L["a Blessing"], chat = L["Blessing"], class = "PALADIN",
		spells = { 20217, 19740, 19742, 1038, 19977, 20911, 25898, 25782, 25894, 25895, 25890, 25899 },
		names = { "Blessing of Kings", "Blessing of Might", "Blessing of Wisdom", "Blessing of Salvation", "Blessing of Light",
			"Blessing of Sanctuary", "Greater Blessing of Kings", "Greater Blessing of Might", "Greater Blessing of Wisdom",
			"Greater Blessing of Salvation", "Greater Blessing of Light", "Greater Blessing of Sanctuary" },
		words = { "blessing", "blessings", "bless", "paladin" } },
}
GR.BY_ID, GR.BY_WORD = {}, {}
for _, f in ipairs(GR.BUFFS) do
	GR.BY_ID[f.id] = f
	for _, w in ipairs(f.words) do GR.BY_WORD[w] = f end
end

-- Consumables: looked at only when asked ("missing consumables", missing:food / missing:elixir), never expected. Food =
-- the Well Fed buff (its name as the game says it, and the English one); a flask or elixir = a buff named with "elixir"
-- or "flask", or one of the classic ones whose buff says neither (English names: the player's client is English).
GR.ELIXIR_NAMES = {}
for n in ([[greater agility|greater intellect|greater armor|greater firepower|shadow power|frost power|fire power|
	mana regeneration|health ii|agility|lesser intellect|spirit of zanza|juju power|juju might|winterfall firewater|
	rage of ages|strike of the scorpok|spirit of boar|infallible mind|spiritual domination|distilled wisdom|
	supreme power|chromatic resistance|petrification]]):gmatch("[^|]+") do
	GR.ELIXIR_NAMES[(n:gsub("^%s+", ""):gsub("%s+$", ""))] = true
end
GR.WELL_FED = 19705 -- (the Well Fed buff's spell)
local SpellName
local foodName -- (Well Fed as the game names it, lowercase; worked out once)
local function IsFood(n)
	if foodName == nil then local fed = SpellName(GR.WELL_FED) foodName = fed and Lower(fed) or false end
	return n == "well fed" or (foodName and n == foodName) or false
end
local function IsElixir(n) return n:find("elixir", 1, true) ~= nil or n:find("flask", 1, true) ~= nil or GR.ELIXIR_NAMES[n] == true end
GR.CONS = {
	{ id = "food", chat = L["food"], label = L["food"], words = { "food", "fed", "wellfed" }, test = IsFood },
	{ id = "elixir", chat = L["flask or elixir"], label = L["a flask or elixir"], words = { "elixir", "elixirs", "flask", "flasks" }, test = IsElixir },
}
GR.CONS_BY_ID, GR.CONS_BY_WORD = {}, {}
for _, c in ipairs(GR.CONS) do
	GR.CONS_BY_ID[c.id] = c
	for _, w in ipairs(c.words) do GR.CONS_BY_WORD[w] = c end
end
GR.CONS_ALL = { consumables = true, consumable = true, cons = true }

function SpellName(id, fallback)
	local n = C_Spell and C_Spell.GetSpellName and Str(Safe(C_Spell.GetSpellName, id))
	if not n and _G.GetSpellInfo then n = Str((Safe(_G.GetSpellInfo, id))) end
	return n or fallback
end

--- A family's names as the game says them (lowercase -> true), worked out once per session.
local function Names(f)
	if f._names then return f._names end
	local set = {}
	for i, id in ipairs(f.spells) do
		set[Lower(SpellName(id, f.names[i]) or f.names[i])] = true
		set[Lower(f.names[i])] = true -- (and the English one)
	end
	f._names = set
	return set
end
GR.ResetNamesForTests = function() for _, f in ipairs(GR.BUFFS) do f._names = nil end foodName = nil end

--- The spell you'd cast for a family: its first spell you know (a single-target one before the group version), by
--- its name (casting a name casts its highest rank); nil when you know none.
function GR.YourSpell(f)
	local known = _G.IsPlayerSpell or (C_SpellBook and C_SpellBook.IsSpellKnown)
	if not known then return nil end
	for i, id in ipairs(f.spells) do
		if Safe(known, id) == true then return SpellName(id, f.names[i]) end
	end
	return nil
end

----------------------------------------------------------------------
-- Reading the group (secret values never compared: a hidden one is nil, and counted)
----------------------------------------------------------------------

local function Bool(v)
	if Secret(v) or v == nil then return nil end -- (secret first: comparing one is an error)
	return v == true
end

--- What the game hides right now, and why: { why = "in combat"... or nil }.
-- the restrictions in the order they're named (a boss fight first), and how
local WHY = { { "Encounter", L["in a boss fight"] }, { "ChallengeMode", L["in a keystone dungeon"] },
	{ "PvPMatch", L["in a PvP match"] }, { "Map", L["on this map"] }, { "Combat", L["in combat"] } }
function GR.Why()
	local R, E = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
	if R and R.IsAddOnRestrictionActive and E then
		for _, k in ipairs(WHY) do
			if E[k[1]] ~= nil and Safe(R.IsAddOnRestrictionActive, E[k[1]]) == true then return k[2] end
		end
		return nil
	end
	return (InCombatLockdown and InCombatLockdown()) and L["in combat"] or nil
end

local function AurasSecret() return C_Secrets and C_Secrets.ShouldAurasBeSecret and Safe(C_Secrets.ShouldAurasBeSecret) == true end

--- A member's buffs: lowercase name -> name; nil (and true) when the game hides them.
function GR.Buffs(unit)
	if AurasSecret() then return nil, true end
	local names = {}
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	for i = 1, 40 do
		local name
		if get then
			local a = Safe(get, unit, i, "HELPFUL")
			if type(a) ~= "table" or Secret(a) then break end
			name = a.name
		elseif _G.UnitBuff then
			name = Safe(_G.UnitBuff, unit, i)
			if name == nil then break end
		else
			break
		end
		if Secret(name) then return nil, true end
		name = Str(name)
		if name then names[Lower(name)] = name end
	end
	return names
end

local function Has(buffs, f)
	if not buffs then return nil end
	for n in pairs(Names(f)) do if buffs[n] then return true end end
	return false
end

--- Whether a member's buffs hold that consumable (nil: hidden).
local function HasCons(buffs, c)
	if not buffs then return nil end
	for n in pairs(buffs) do if c.test(n) then return true end end
	return false
end

--- A member's name as the game gives it: name and surname (WoW Forever: UnitName's second answer) or name-realm.
function GR.NameOf(unit)
	local name, second = Safe(UnitName, unit)
	name, second = Str(name), Str(second)
	if not name then return nil end
	if not second then return name end
	if _G.RegionalUniqueNamesEnabled and Safe(_G.RegionalUniqueNamesEnabled) then
		local C = _G.Constants and _G.Constants.CharacterNameSeparatorConsts
		return name .. (C and C.CHARACTERNAME_SURNAME_SEPARATOR or " ") .. second
	end
	return name .. "-" .. second
end

--- The group's units now: "player", then party1..4, or raid1..40 (you among them).
function GR.Units()
	local n = Num(Safe(GetNumGroupMembers)) or 0
	local out = {}
	if Safe(IsInRaid) == true then
		for i = 1, math.min(n, 40) do out[#out + 1] = "raid" .. i end
	else
		out[1] = "player"
		for i = 1, math.min(math.max(n - 1, 0), 4) do out[#out + 1] = "party" .. i end
	end
	return out
end

--- The unit a row's member is now (the group's order moves: found again by GUID), else the one it was read as.
function GR.UnitOf(e)
	if e.guid then
		for _, u in ipairs(GR.Units()) do
			local g = Str(Safe(UnitGUID, u))
			if g and g == e.guid then return u end
		end
	end
	return e.unit
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local ROLE_LABEL = { TANK = L["Tank"], HEALER = L["Healer"], DAMAGER = L["Damage"] }
-- (several of them: the answer's note and the line sent to chat say them alike)
local ROLE_PLURAL = { TANK = L["Tanks"], HEALER = L["Healers"], DAMAGER = L["Damage dealers"] }
local ROLE_WORDS = { TANK = "tank tanks", HEALER = "healer healers heals", DAMAGER = "dps damage damager" }
local RED, ORANGE, GREY, YELLOW = "|cffff4040", "|cffff9933", "|cff9d9d9d", "|cffffd200"

local function Icon(classFile)
	if not classFile then return "Interface\\Icons\\INV_Misc_GroupNeedMore" end
	return "Interface\\Icons\\ClassIcon_" .. classFile:sub(1, 1) .. Lower(classFile:sub(2))
end

-- Enter: the game targets them; Shift+Enter: the game casts your buff on them (both out of combat: in combat Enter
-- can't be handed to the game, and these say so)
local function TargetMacro(e) return "/target " .. GR.UnitOf(e) end
local function BuffMacro(e)
	if not e.buffWith then return nil end
	return ("/cast [@%s] %s"):format(GR.UnitOf(e), e.buffWith)
end
local TARGET_SPEC, BUFF_SPEC = { macro = TargetMacro }, { macro = BuffMacro }
-- (no press set up: in combat, or out of it when the press couldn't be armed; 0.50.7, review: "In combat" was said
-- either way)
local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function NoTarget(e)
	ns:Print((InCombat() and L["In combat: target %s from your party or raid frames."] or L["Couldn't target %s from here: use your party or raid frames."])
		:format(tostring(e.name)))
end
local function NoBuff(e)
	ns:Print((InCombat() and L["In combat: cast %s on %s from your bars."] or L["Couldn't cast %s on %s from here: use your bars."])
		:format(tostring(e.buffWith), tostring(e.name)))
end

--- What's sent: "Plamen Pally (Paladin, Healer): dead, out of range, needs Fortitude".
local function ShareText(e)
	local said = {}
	if e.dead then said[#said + 1] = e.ghost and L["a ghost"] or L["dead"] end
	if e.online == false then said[#said + 1] = L["offline"] end
	if e.inRange == false then said[#said + 1] = L["out of range"] end
	if e.missing and #e.missing > 0 then said[#said + 1] = L["needs %s"]:format(table.concat(e.missingLabels, ", ")) end
	local about = ns.Join(", ", e.className, e.roleLabel)
	local who = e.name .. (about ~= "" and (" (" .. about .. ")") or "")
	return who .. (#said > 0 and (": " .. table.concat(said, ", ")) or "")
end

local function Tooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	local about = ns.Join(ns.DETAIL_SEP, e.level and L["Level %d"]:format(e.level) or nil, e.className, e.roleLabel, e.zone)
	if about ~= "" then t:AddLine(about, 1, 1, 1) end
	if e.dead then t:AddLine(e.ghost and L["A ghost"] or L["Dead"], 1, 0.25, 0.25) end
	if e.online == false then t:AddLine(L["Offline"], 0.6, 0.6, 0.6) end
	if e.inRange == false then t:AddLine(L["Out of range (the game's own range test, as the raid frames fade)"], 1, 0.6, 0.2, true)
	elseif e.rangeHidden then t:AddLine(L["Range hidden by the game right now"], 0.6, 0.6, 0.6) end
	if e.buffsHidden then
		t:AddLine(L["Buffs hidden by the game right now"], 0.6, 0.6, 0.6)
	elseif e.missing and #e.missing > 0 then
		t:AddLine(L["Needs %s"]:format(table.concat(e.missingLabels, ", ")), 1, 0.82, 0, true)
	elseif e.buffs then
		t:AddLine(L["Has every buff the group can give"], 0.4, 1, 0.4, true)
	end
	if e.buffs then
		local list = {}
		for _, n in pairs(e.buffs) do list[#list + 1] = n end
		table.sort(list)
		if #list > 0 then t:AddLine(L["Buffs: %s"]:format(table.concat(list, ", ", 1, math.min(#list, 12)) .. (#list > 12 and ", ..." or "")), 0.7, 0.7, 0.7, true) end
		local cons = {}
		for _, n in ipairs(list) do
			local l = Lower(n)
			if IsFood(l) or IsElixir(l) then cons[#cons + 1] = n end
		end
		t:AddLine(L["Consumables: %s"]:format(#cons > 0 and table.concat(cons, ", ") or L["none"]), 0.7, 0.7, 0.7, true)
	end
	t:AddLine(L["Enter: target"] .. (e.buffWith and ("    " .. L["Shift+Enter: cast %s on them"]:format(e.buffWith)) or ""), 0.6, 0.6, 0.6, true)
end

local list -- (the last collect's rows)

--- A member, read now.
function GR.Read(unit, mine)
	if not mine and Safe(UnitExists, unit) ~= true then return nil end
	local m = { unit = unit, mine = mine or nil }
	m.name = (mine and ns.CharacterName()) or GR.NameOf(unit) or unit
	m.identityHidden = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret and Safe(C_Secrets.ShouldUnitIdentityBeSecret, unit) == true or nil
	local className, classFile = Safe(UnitClass, unit)
	m.className, m.classFile = Str(className), Str(classFile)
	m.guid = Str(Safe(UnitGUID, unit))
	m.level = Num(Safe(UnitLevel, unit))
	local dead, ghost, feign = Bool(Safe(UnitIsDeadOrGhost, unit)), Bool(Safe(UnitIsGhost, unit)), Bool(Safe(UnitIsFeignDeath, unit))
	m.dead = (dead and not feign) or nil
	m.ghost = (m.dead and ghost) or nil
	m.online = Bool(Safe(UnitIsConnected, unit))
	local role = Safe(UnitGroupRolesAssigned, unit)
	-- (a secret role is never compared: that's an error on this client, in a boss fight the collect failed)
	if Secret(role) then m.roleHidden, role = true, nil else role = Str(role) end
	if role and role ~= "NONE" then m.role = role end
	if mine then
		m.inRange = true
	else
		local r, checked = Safe(UnitInRange, unit)
		if Secret(r) or Secret(checked) then m.rangeHidden = true
		elseif checked == true then m.inRange = r == true end
	end
	local buffs, hidden = GR.Buffs(unit)
	m.buffs, m.buffsHidden = buffs, hidden or nil
	return m
end

--- Which families the group should have: their class is in the group (a talent's only once someone has it).
function GR.Expected(members)
	local classes, seen = {}, {}
	for _, m in ipairs(members) do
		if m.classFile then classes[m.classFile] = true end
		for _, f in ipairs(GR.BUFFS) do if Has(m.buffs, f) then seen[f.id] = true end end
	end
	local out = {}
	for _, f in ipairs(GR.BUFFS) do
		if classes[f.class] and not f.optional and (not f.talent or seen[f.id]) then out[#out + 1] = f end
	end
	return out
end

local function Row(m, expected, raidInfo)
	local missing, labels = nil, nil
	if m.buffs and not m.dead and m.online ~= false then
		missing, labels = {}, {}
		for _, f in ipairs(expected) do
			if not Has(m.buffs, f) then missing[#missing + 1] = f.id; labels[#labels + 1] = f.label end
		end
	end
	local cons
	if m.buffs and not m.dead and m.online ~= false then
		cons = {}
		for _, c in ipairs(GR.CONS) do cons[c.id] = HasCons(m.buffs, c) end
	end
	local buffWith
	for _, id in ipairs(missing or {}) do
		buffWith = GR.YourSpell(GR.BY_ID[id])
		if buffWith then break end
	end
	local d = {}
	local roleLabel = m.role and ROLE_LABEL[m.role]
	d[#d + 1] = (m.level and (L["Lv %d"]:format(m.level) .. " ") or "") .. (m.className or "")
	if roleLabel then d[#d + 1] = roleLabel end
	if m.dead then d[#d + 1] = RED .. (m.ghost and L["Ghost"] or L["Dead"]) .. "|r" end
	if m.online == false then d[#d + 1] = GREY .. L["Offline"] .. "|r" end
	if m.inRange == false then d[#d + 1] = ORANGE .. L["out of range"] .. "|r" elseif m.rangeHidden then d[#d + 1] = GREY .. L["range hidden"] .. "|r" end
	if m.buffsHidden then d[#d + 1] = GREY .. L["buffs hidden"] .. "|r"
	elseif labels and #labels > 0 then d[#d + 1] = YELLOW .. L["needs %s"]:format(table.concat(labels, ", ")) .. "|r" end
	if m.mine then d[#d + 1] = GREY .. L["(you)"] .. "|r" end
	if raidInfo and raidInfo.group then d[#d + 1] = GREY .. L["group %s"]:format(raidInfo.group) .. "|r" end
	local words = { "group party raid member" }
	if m.className then words[#words + 1] = Lower(m.className) end
	if m.role then words[#words + 1] = ROLE_WORDS[m.role] end
	if m.dead then words[#words + 1] = "dead" .. (m.ghost and " ghost" or "") end
	words[#words + 1] = m.online == false and "offline" or "online"
	if m.inRange == false then words[#words + 1] = "far outofrange" end
	if missing and #missing > 0 then
		words[#words + 1] = "unbuffed needs"
		for _, id in ipairs(missing) do words[#words + 1] = table.concat(GR.BY_ID[id].words, " ") end
	end
	if m.mine then words[#words + 1] = "you me" end
	return {
		key = m.guid or m.unit, name = m.name, unit = m.unit, guid = m.guid, mine = m.mine,
		classFile = m.classFile, className = m.className, level = m.level, role = m.role, roleLabel = roleLabel,
		dead = m.dead, ghost = m.ghost, online = m.online, inRange = m.inRange, rangeHidden = m.rangeHidden,
		buffs = m.buffs, buffsHidden = m.buffsHidden, missing = missing, missingLabels = labels, buffWith = buffWith, cons = cons,
		zone = raidInfo and raidInfo.zone,
		color = m.online == false and GREY or ns.ClassHex(m.classFile), icon = Icon(m.classFile),
		detail = table.concat(d, ns.DETAIL_SEP), text = table.concat(words, " "),
		tooltip = Tooltip, shareLink = ShareText, shareGroup = GR.ShareGroupOf,
		secure = TARGET_SPEC, isOpen = ns.Never, activate = NoTarget,
		secondarySecure = buffWith and BUFF_SPEC or nil, secondaryIsOpen = buffWith and ns.Never or nil,
		secondary = buffWith and NoBuff or nil,
	}
end

-- Whether a raid unit is you. UnitIsUnit's answer is secret where unit comparison is restricted: never compared, the GUIDs
-- then (0.50.7, review: compared as it came, an error there, and the list stayed empty)
local function IsMe(u)
	if u == "player" then return true end
	local v = Bool(Safe(UnitIsUnit, u, "player"))
	if v ~= nil then return v end
	local a, b = Str(Safe(UnitGUID, u)), Str(Safe(UnitGUID, "player"))
	return a ~= nil and a == b
end

function GR.Collect()
	local members = {}
	local units = GR.Units()
	local raid = Safe(IsInRaid) == true
	local raidInfo = {}
	for i, u in ipairs(units) do
		local m = GR.Read(u, u == "player" or (raid and IsMe(u)))
		if m then
			members[#members + 1] = m
			if raid and _G.GetRaidRosterInfo then
				local _, _, group, _, _, _, zone = Safe(_G.GetRaidRosterInfo, i)
				raidInfo[m] = { group = Num(group), zone = Str(zone) }
			end
		end
	end
	local expected = GR.Expected(members)
	local rows = {}
	local hidden = { range = 0, buffs = 0, roles = 0 }
	for i, m in ipairs(members) do
		rows[#rows + 1] = Row(m, expected, raidInfo[m])
		rows[#rows]._order = i
		if m.rangeHidden then hidden.range = hidden.range + 1 end
		if m.buffsHidden then hidden.buffs = hidden.buffs + 1 end
		if m.roleHidden or m.identityHidden then hidden.roles = hidden.roles + 1 end
	end
	-- you first, then the group's own order
	table.sort(rows, function(a, b)
		if (a.mine and true or false) ~= (b.mine and true or false) then return a.mine and true or false end
		return (a._order or 0) < (b._order or 0)
	end)
	local n = #rows
	for i, e in ipairs(rows) do e._rank = (n - i + 1) / (n + 1) * 0.5 end
	GR.hidden = hidden
	GR.expected = expected
	GR.solo = #units <= 1
	list = rows
	return rows
end

--- What the game hides right now, in words: "Range and buffs hidden by the game right now (in combat)"; nil when
--- nothing is.
-- (0.49.2, review: whole sentences, not "%s hidden ..." filled with "range", "buffs" and "and": a translation can make
-- its words agree, and a first letter outside ASCII was never made upper case)
local HIDDEN = {
	["r"] = L["Range hidden by the game right now"], ["b"] = L["Buffs hidden by the game right now"],
	["o"] = L["Roles hidden by the game right now"], ["rb"] = L["Range and buffs hidden by the game right now"],
	["ro"] = L["Range and roles hidden by the game right now"], ["bo"] = L["Buffs and roles hidden by the game right now"],
	["rbo"] = L["Range, buffs and roles hidden by the game right now"],
}
function GR.HiddenText()
	local h = GR.hidden
	if not h then return nil end
	local k = (h.range > 0 and "r" or "") .. (h.buffs > 0 and "b" or "") .. (h.roles > 0 and "o" or "")
	if k == "" then return nil end
	local why = GR.Why()
	return HIDDEN[k] .. (why and (" (" .. why .. ")") or "")
end

local NoteRow = ns.NoteRow

ns:RegisterProvider("group", {
	label = L["Group"],
	color = "ff7fe07f", -- (the party frame's green, apart from the slash commands')
	aliases = { "group", "party", "members" }, -- (@raid is the raids' entrances: Entrances.lua)
	explicit = true, -- (only with @group, Simple mode's Group category, or asked in words)
	refreshOnOpen = true, -- (range and buffs move all the time: read afresh on every open)
	-- (no per-unit events: UNIT_AURA, UNIT_HEALTH, UNIT_FLAGS and UNIT_CONNECTION fire for every unit, nameplates and all,
	-- hundreds a second in a fight, and each dirtied the list, so a search while typing read the whole group again
	-- about once a second: 4 ms and 1.3 MB of garbage in a 40-man raid. 0.47.0 review)
	events = { "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
		"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED" },
	guard = 1,
	-- a line on top: what the game hides right now, or that you're not in a group
	leadRow = function(p)
		ns:GetEntries(p)
		local h = GR.HiddenText()
		if h then return NoteRow(h) end
		if GR.solo then return NoteRow(L["You're not in a group: only you are listed"]) end
		return nil
	end,
	collect = function() return GR.Collect() end,
})

----------------------------------------------------------------------
-- The question: "who is dead", "who needs fortitude", "who is out of range", "group healers", "missing buffs"
----------------------------------------------------------------------

local ASK = {}
for w in ([[who whos is are the my our in not has have does do any anyone someone everyone which what of a an me i to
	with still out show list find get got there theres left any here our all their them it its please]]):gmatch("%a+") do ASK[w] = true end
local SUBJECT = { group = true, party = true, raid = true, members = true, member = true, groupmates = true, team = true }
local CUE = { dead = "dead", died = "dead", dying = "dead", ghost = "dead", ghosts = "dead", offline = "offline",
	disconnected = "offline", dc = "offline", dced = "offline", range = "far", far = "far", oor = "far", outofrange = "far",
	missing = "missing", needs = "missing", need = "missing", without = "missing", lacks = "missing", lacking = "missing",
	unbuffed = "missing", tank = "tank", tanks = "tank", healer = "healer",
	healers = "healer", heals = "healer", healing = "healer", dps = "dps", damage = "dps", inrange = "near" }

--- The question: { dead, offline, far, near, missing = { families }, buffWords = { other buff names }, roles = { ROLE }, words },
--- or nil when the line isn't about the group. About the group: a group word or "who" (or "unbuffed") and a cue; or,
--- without one, a missing word with what's missing named ("missing buffs", "needs fortitude", "missing consumables").
--- "buff" and "consumables" alone are no cue (0.47.0 review: "food buff", "agility buff", "consumables" were answered
--- as group questions, and typing "consecration" flashed the group up at "cons").
local BUFF_WORDS = { buff = true, buffs = true }
local NAME_FILLER = { of = true, the = true, protection = true } -- (left out of a buff's name looked for)
--- Is this word a group buff's or a consumable's word, or a word of a buff's name ("kings": Blessing of Kings)?
local function BuffWord(w)
	if GR.BY_WORD[w] or GR.CONS_BY_WORD[w] or NAME_FILLER[w] then return true end
	for _, f in ipairs(GR.BUFFS) do
		for n in pairs(Names(f)) do
			if (" " .. n .. " "):find(" " .. w .. " ", 1, true) then return true end
		end
	end
	return false
end
function GR.Question(text)
	local t = ns.QuestionText(text, { without = true, no = true })
	if not t then return nil end
	t = t:gsub("in range", "inrange"):gsub("out of range", "outofrange")
	local subject, who, cues, rest, consAll, named = false, false, {}, {}, false, false
	for w in t:gmatch("%S+") do
		if GR.CONS_ALL[w] then consAll, named = true, true
		elseif BUFF_WORDS[w] then named = true
		elseif SUBJECT[w] then subject = true
		elseif CUE[w] then
			-- (after other words, "without" is Simple mode's "not": "cloak without stamina", "food without spirit" are
			-- searches, never "Needs Fortitude, cloak"; 0.49.2, review)
			if not (w == "without" and #rest > 0) then cues[CUE[w]] = true end
			if w == "unbuffed" then subject, named = true, true end
		elseif w == "who" or w == "whos" then who = true
		elseif not ASK[w] then
			rest[#rest + 1] = w
			if GR.BY_WORD[w] or GR.CONS_BY_WORD[w] then named = true end
		end
	end
	if consAll then cues.missing = cues.missing or (subject or who) or nil end -- ("who has no consumables" reads as missing)
	if not next(cues) then return nil end
	if not (subject or who) and not (cues.missing and named) then return nil end
	-- (no group word nor "who": every other word must name a buff or consumable; an item, slot or type word makes it a
	-- search: "cloak needs stamina"; 0.49.2, review)
	if not (subject or who) then
		for _, w in ipairs(rest) do if not BuffWord(w) then return nil end end
	end
	local q = { dead = cues.dead, offline = cues.offline, far = cues.far, near = cues.near, words = {} }
	local roles = {}
	if cues.tank then roles[#roles + 1] = "TANK" end
	if cues.healer then roles[#roles + 1] = "HEALER" end
	if cues.dps then roles[#roles + 1] = "DAMAGER" end
	if #roles > 0 then q.roles = roles end
	if cues.missing then
		q.missing, q.buffWords, q.cons = {}, {}, {}
		if consAll then for _, c in ipairs(GR.CONS) do q.cons[#q.cons + 1] = c.id end end
		-- each word: a family's ("fortitude", "shadow": GR.BY_WORD), a consumable's, else part of one buff's name
		for _, w in ipairs(rest) do
			local f = GR.BY_WORD[w]
			local c = GR.CONS_BY_WORD[w]
			if f then
				q.missing[#q.missing + 1] = f.id
			elseif c then
				if not consAll then q.cons[#q.cons + 1] = c.id end
			elseif not NAME_FILLER[w] then -- (leftover words are one buff's name: "blessing of kings" -> "blessing kings")
				q.buffWords[#q.buffWords + 1] = w
			end
		end
		-- one blessing named ("blessing of kings", "greater blessing of might"): that buff by name, not every Blessing
		-- (0.50.7, review: "blessing" took the whole family, so a member with Might but no Kings wasn't listed)
		if #q.buffWords > 0 then
			for i = #q.missing, 1, -1 do
				if q.missing[i] == "blessing" then
					table.remove(q.missing, i)
					table.insert(q.buffWords, 1, "blessing")
				end
			end
		end
	else
		q.words = rest
	end
	return q
end

--- Whether a row lacks every buff named by these words (any aura whose name holds them all), nil when buffs are hidden.
local function LacksNamed(e, words)
	if not e.buffs then return nil end
	for n in pairs(e.buffs) do
		local all = true
		for _, w in ipairs(words) do if not n:find(w, 1, true) then all = false break end end
		if all then return false end
	end
	return true
end

local function Wanted(e, q)
	if q.dead and not e.dead then return false end
	if q.offline and e.online ~= false then return false end
	if q.far and e.inRange ~= false then return false end
	if q.near and e.inRange ~= true then return false end
	if q.roles then
		local any = false
		for _, r in ipairs(q.roles) do if e.role == r then any = true end end
		if not any then return false end
	end
	if q.missing then
		if e.dead or e.online == false then return false end
		local cons = q.cons and #q.cons > 0
		if #q.missing == 0 and #(q.buffWords or {}) == 0 and not cons then
			if not (e.missing and #e.missing > 0) then return false end
		end
		if cons then -- (lacking any of the consumables asked for)
			local lacks = false
			for _, id in ipairs(q.cons) do if e.cons and e.cons[id] == false then lacks = true end end
			if not lacks then return false end
		end
		for _, id in ipairs(q.missing) do
			if Has(e.buffs, GR.BY_ID[id]) ~= false then return false end
		end
		if q.buffWords and #q.buffWords > 0 and LacksNamed(e, q.buffWords) ~= true then return false end
	end
	for _, w in ipairs(q.words or {}) do
		if not Lower(e.name):find(w, 1, true) then return false end
	end
	return true
end

local function Labels(q)
	local out = {}
	for _, id in ipairs(q.missing or {}) do out[#out + 1] = GR.BY_ID[id].label end
	if q.buffWords and #q.buffWords > 0 then out[#out + 1] = table.concat(q.buffWords, " ") end
	for _, id in ipairs(q.cons or {}) do out[#out + 1] = GR.CONS_BY_ID[id].label end
	return table.concat(out, ", ")
end

--- The rows a question asks for, and the footer's note.
function GR.Answer(q)
	q = q or {}
	local p = ns.providers.group
	local all = p and ns:GetEntries(p) or {}
	local rows = {}
	for _, e in ipairs(all) do if Wanted(e, q) then rows[#rows + 1] = e end end
	for i, e in ipairs(rows) do e._score = 1e6 - i end
	local what = (q.dead and L["Dead"]) or (q.offline and L["Offline"]) or (q.far and L["Out of range"]) or (q.near and L["In range"])
		or (q.missing and ((Labels(q) ~= "" and L["Needs %s"]:format(Labels(q))) or L["Missing a buff the group can give"]))
		or (q.roles and ROLE_PLURAL[q.roles[1]]) or L["Your group"]
	local note = what .. ns.DETAIL_SEP .. L["%d of %d"]:format(#rows, #all)
	local hidden = GR.HiddenText()
	if (q.far or q.near) and GR.hidden and GR.hidden.range > 0 then note = note .. ns.DETAIL_SEP .. hidden
	elseif q.missing and GR.hidden and GR.hidden.buffs > 0 then note = note .. ns.DETAIL_SEP .. hidden
	elseif q.roles and GR.hidden and GR.hidden.roles > 0 then note = note .. ns.DETAIL_SEP .. hidden end
	if q.roles and #rows == 0 then
		local anyRole = false
		for _, e in ipairs(all) do if e.role then anyRole = true end end
		if not anyRole then note = note .. ns.DETAIL_SEP .. L["nobody has a role set (the group finder sets them)"] end
	end
	if GR.solo then note = note .. ns.DETAIL_SEP .. L["you're not in a group"] end
	if #rows == 0 and not (GR.hidden and (GR.hidden.range > 0 or GR.hidden.buffs > 0)) then
		local none = (q.dead and L["Nobody is dead"]) or (q.offline and L["Nobody is offline"]) or (q.far and L["Everyone is in range"])
			or (q.missing and L["Nobody needs it"]) or nil
		if none then note = none .. (GR.solo and (ns.DETAIL_SEP .. L["you're not in a group"]) or "") end
	end
	return rows, note
end

--- The question as Advanced syntax (Alt+`): "@group is:dead", "@group missing:fortitude".
function GR.ToAdvanced(q)
	local parts = { "@group" }
	if q.dead then parts[#parts + 1] = "is:dead" end
	if q.offline then parts[#parts + 1] = "is:offline" end
	if q.far then parts[#parts + 1] = "is:far" end
	if q.near then parts[#parts + 1] = "is:inrange" end
	for _, r in ipairs(q.roles or {}) do
		parts[#parts + 1] = "is:" .. ({ TANK = "tank", HEALER = "healer", DAMAGER = "dps" })[r]
	end
	if q.missing then
		local cons = q.cons or {}
		if #q.missing == 0 and #(q.buffWords or {}) == 0 and #cons == 0 then parts[#parts + 1] = "is:unbuffed" end
		for _, id in ipairs(q.missing) do parts[#parts + 1] = "missing:" .. id end
		if #cons == #GR.CONS then parts[#parts + 1] = "missing:consumables"
		else for _, id in ipairs(cons) do parts[#parts + 1] = "missing:" .. id end end
		if q.buffWords and #q.buffWords > 0 then parts[#parts + 1] = "missing:" .. table.concat(q.buffWords, "_") end
	end
	for _, w in ipairs(q.words or {}) do parts[#parts + 1] = w end
	return table.concat(parts, " ") .. " "
end

--- missing:<buff> (Filters): a family's word or id, else any buff name holding the words (_ for a space). The test, or
--- nil for an empty value.
function GR.MissingFilter(v)
	v = Lower(v or ""):gsub("_", " ")
	if v == "" then return nil end
	local f = GR.BY_ID[v] or GR.BY_WORD[v]
	if f then
		return function(e) return e.kind == "group" and not e.dead and e.online ~= false and Has(e.buffs, f) == false end
	end
	if GR.CONS_ALL[v] then -- (missing:consumables: lacking food or a flask/elixir)
		return function(e) return e.kind == "group" and e.cons ~= nil and (e.cons.food == false or e.cons.elixir == false) end
	end
	local c = GR.CONS_BY_ID[v] or GR.CONS_BY_WORD[v]
	if c then return function(e) return e.kind == "group" and e.cons ~= nil and e.cons[c.id] == false end end
	local words = {}
	for w in v:gmatch("%S+") do words[#words + 1] = w end
	return function(e) return e.kind == "group" and not e.dead and e.online ~= false and LacksNamed(e, words) == true end
end

----------------------------------------------------------------------
-- Every result at once (">>> party", the menu's "All N to party"): what's missing, said once per buff
----------------------------------------------------------------------

--- What a search asked of the group (Advanced words or plain ones): { dead, offline, far, near, roles, missing,
--- families, words, cons }.
function GR.AskOf(query)
	local ask = { families = {}, words = {}, cons = {}, roles = {} }
	local q = GR.Question(query or "")
	if q then
		ask.dead, ask.offline, ask.far, ask.near, ask.roles = q.dead, q.offline, q.far, q.near, q.roles or {}
		if q.missing then
			ask.missing = true
			for _, id in ipairs(q.missing) do ask.families[#ask.families + 1] = GR.BY_ID[id] end
			for _, w in ipairs(q.buffWords or {}) do ask.words[#ask.words + 1] = w end
			for _, id in ipairs(q.cons or {}) do ask.cons[#ask.cons + 1] = GR.CONS_BY_ID[id] end
		end
		return ask
	end
	local ROLE = { tank = "TANK", tanks = "TANK", healer = "HEALER", healers = "HEALER", dps = "DAMAGER", damage = "DAMAGER", damager = "DAMAGER" }
	for w in Lower(query or ""):gmatch("%S+") do
		local k, v = w:match("^(%a+):(.+)$")
		if k == "is" then
			for part in v:gmatch("[^|&]+") do
				if part == "dead" then ask.dead = true
				elseif part == "offline" then ask.offline = true
				elseif part == "far" or part == "outofrange" then ask.far = true
				elseif part == "inrange" or part == "near" then ask.near = true
				elseif ROLE[part] then ask.roles[#ask.roles + 1] = ROLE[part]
				elseif part == "unbuffed" then ask.missing = true end
			end
		elseif k == "missing" or k == "needs" then
			ask.missing = true
			for part in v:gmatch("[^|]+") do
				part = part:gsub("_", " ")
				local f, c = GR.BY_ID[part] or GR.BY_WORD[part], GR.CONS_BY_ID[part] or GR.CONS_BY_WORD[part]
				if f then ask.families[#ask.families + 1] = f
				elseif GR.CONS_ALL[part] then for _, x in ipairs(GR.CONS) do ask.cons[#ask.cons + 1] = x end
				elseif c then ask.cons[#ask.cons + 1] = c
				else ask.words[#ask.words + 1] = part end
			end
		end
	end
	return ask
end

-- names as short as they can be: the first word ("Plamen"), the whole name where two share it
local function ShortNames(rows)
	local count, out = {}, {}
	for _, e in ipairs(rows) do
		local first = tostring(e.name):match("^(%S+)") or tostring(e.name)
		count[first] = (count[first] or 0) + 1
	end
	for _, e in ipairs(rows) do
		local first = tostring(e.name):match("^(%S+)") or tostring(e.name)
		out[e] = count[first] > 1 and tostring(e.name) or first
	end
	return out
end

--- Packs sections ({ label, items } or { text }) into chat lines of at most `LM` characters, `ML` lines; what doesn't
--- fit is counted on the last ("+3 more"). An item too long for a line of its own is cut to fit (`fit(room)`). Sections
--- are joined with `between` ("  ·  "; party quests: ". ").
local function Pack(sections, ML, LM, between)
	local tokens = {}
	for i, s in ipairs(sections) do
		local sep = i > 1 and (between or ns.DETAIL_SEP) or ""
		if s.text then
			tokens[#tokens + 1] = { text = s.text, sep = sep }
		else
			for j, it in ipairs(s.items) do
				local text = type(it) == "table" and it.text or it
				tokens[#tokens + 1] = { text = (j == 1 and (s.label .. ": ") or "") .. text, sep = j == 1 and sep or ", ",
					fit = type(it) == "table" and it.fit or nil, lead = j == 1 and (s.label .. ": ") or "" }
			end
		end
	end
	local lines, line, sent = {}, nil, 0
	local function Room() return LM - (#lines == ML - 1 and 12 or 0) end
	for _, t in ipairs(tokens) do
		local text = t.text
		if #text > Room() and t.fit then text = t.lead .. t.fit(Room() - #t.lead) end -- (cut to fit a line)
		local joined = line and (line .. t.sep .. text) or text
		if #joined <= Room() then
			line = joined
		else
			if line then lines[#lines + 1] = line end
			line = nil
			if #lines >= ML or #text > Room() then break end
			line = text
		end
		sent = sent + 1
	end
	if line and #lines < ML then lines[#lines + 1] = line end
	local left = #tokens - sent
	if left > 0 and #lines > 0 then
		local more = L["+%s more"]:format(left)
		if #lines[#lines] + #more + 1 <= LM then lines[#lines] = lines[#lines] .. " " .. more
		elseif #lines < ML then lines[#lines + 1] = more end
	end
	return lines
end
GR.Pack = Pack -- (party quests' line: GroupQuests.lua)
GR.ShortNames = ShortNames

--- The group's rows as chat lines, as few words as they take: "Missing buffs: Fortitude (Cid, Bob), Mark of the Wild
--- (everyone), Blessing (all but Ann)"; asked about: "Dead: Bob  ·  Out of range: Cid"; consumables: "Missing
--- consumables: food (Bob, Cid), flask or elixir (everyone)". Dead and offline members aren't counted for buffs (they
--- can't be buffed). Every row of the group carries this (`shareGroup`), and Share's GroupLines uses it.
function GR.ShareGroupOf(rows, query, ML, LM)
	ML, LM = ML or 6, LM or 255
	local ask = GR.AskOf(query)
	local short = ShortNames(rows)
	local sections = {}
	local function State(on, label, test)
		if not on then return end
		local who = {}
		for _, e in ipairs(rows) do if test(e) then who[#who + 1] = short[e] end end
		sections[#sections + 1] = { label = label, items = #who > 0 and who or { L["nobody"] } }
	end
	State(ask.dead, L["Dead"], function(e) return e.dead end)
	State(ask.offline, L["Offline"], function(e) return e.online == false end)
	State(ask.far, L["Out of range"], function(e) return e.inRange == false end)
	State(ask.near, L["In range"], function(e) return e.inRange == true end)
	for _, r in ipairs(ask.roles) do
		State(true, ROLE_PLURAL[r], function(e) return e.role == r end)
	end
	if ask.missing or #sections == 0 then
		-- (who can be buffed: alive and online, their buffs readable; "everyone" and "all but" are said of the whole group,
		-- not only the rows a filtered search sends)
		local inList = {}
		for _, e in ipairs(list or {}) do inList[e] = true end
		local whole = rows
		for _, e in ipairs(rows) do if not inList[e] then whole = nil break end end
		whole = whole and list or rows
		local function Can(e) return not e.dead and e.online ~= false end
		local eligible, hidden, all = {}, 0, {}
		for _, e in ipairs(rows) do
			if Can(e) then
				if e.buffs then eligible[#eligible + 1] = e else hidden = hidden + 1 end
			end
		end
		for _, e in ipairs(whole) do if Can(e) and e.buffs then all[#all + 1] = e end end
		local wholeShort = ShortNames(whole)
		-- "everyone", "all but Ann", or the names (cut to fit a line when there are many)
		local function Item(label, test)
			local who, lackingAll, have = {}, 0, {}
			for _, e in ipairs(eligible) do if test(e) then who[#who + 1] = short[e] end end
			if #who == 0 then return nil end
			for _, e in ipairs(all) do
				if test(e) then lackingAll = lackingAll + 1 else have[#have + 1] = wholeShort[e] or short[e] end
			end
			local said
			if #who == lackingAll then
				if #have == 0 and #who > 1 then said = L["everyone"]
				elseif #have == 1 and #all >= 3 then said = L["all but %s"]:format(have[1]) end
			end
			if said then return label .. " (" .. said .. ")" end
			return { text = label .. " (" .. table.concat(who, ", ") .. ")", fit = function(room)
				local s, n = label .. " (", 0
				for i, w in ipairs(who) do
					local more = #who - i
					local add = (i > 1 and ", " or "") .. w
					if #s + #add + (more > 0 and (#tostring(more) + 3) or 0) + 1 > room then break end
					s, n = s .. add, i
				end
				return s .. (n < #who and (" +" .. (#who - n)) or "") .. ")"
			end }
		end
		local items = {}
		local fams = ask.families
		if #fams == 0 and #ask.words == 0 and #ask.cons == 0 then fams = GR.expected or {} end
		for _, f in ipairs(fams) do
			local it = Item(f.chat or f.label, function(e) return Has(e.buffs, f) == false end)
			if it then items[#items + 1] = it end
		end
		if #ask.words > 0 then
			local it = Item(table.concat(ask.words, " "), function(e) return LacksNamed(e, ask.words) == true end)
			if it then items[#items + 1] = it end
		end
		for _, c in ipairs(ask.cons) do
			local it = Item(c.chat, function(e) return e.cons ~= nil and e.cons[c.id] == false end)
			if it then items[#items + 1] = it end
		end
		local consOnly = #ask.cons > 0 and #ask.families == 0 and #ask.words == 0
		local why = GR.Why()
		if #items > 0 then
			if hidden > 0 then items[#items + 1] = L["%d with buffs hidden%s"]:format(hidden, why and (", " .. why) or "") end
			sections[#sections + 1] = { label = consOnly and L["Missing consumables"] or L["Missing buffs"], items = items }
		elseif #eligible == 0 and hidden > 0 then
			sections[#sections + 1] = { text = L["Buffs hidden by the game right now"] .. (why and (" (" .. why .. ")") or "") }
		elseif consOnly then
			sections[#sections + 1] = { text = L["Everyone has %s"]:format(table.concat((function() local t = {} for i, c in ipairs(ask.cons) do t[i] = c.label end return t end)(), " " .. L["and"] .. " ")) }
		elseif #ask.families > 0 or #ask.words > 0 then
			local t = {}
			for _, f in ipairs(ask.families) do t[#t + 1] = f.chat or f.label end
			if #ask.words > 0 then t[#t + 1] = table.concat(ask.words, " ") end
			sections[#sections + 1] = { text = L["Nobody is missing %s"]:format(table.concat(t, " " .. L["or"] .. " ")) }
		else
			sections[#sections + 1] = { text = L["Nobody is missing a buff the group can give"] }
		end
	end
	return Pack(sections, ML, LM), #rows
end
