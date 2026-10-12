local ns = select(2, ...)

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
	{ id = "fortitude", label = "Fortitude", class = "PRIEST", spells = { 1243, 21562 },
		names = { "Power Word: Fortitude", "Prayer of Fortitude" }, words = { "fortitude", "fort", "pwf", "stamina" } },
	{ id = "intellect", label = "Intellect", class = "MAGE", spells = { 1459, 23028 },
		names = { "Arcane Intellect", "Arcane Brilliance" }, words = { "intellect", "int", "ai", "brilliance", "ab" } },
	{ id = "wild", label = "Mark of the Wild", class = "DRUID", spells = { 1126, 21849 },
		names = { "Mark of the Wild", "Gift of the Wild" }, words = { "mark", "motw", "wild", "gotw" } },
	{ id = "spirit", label = "Divine Spirit", class = "PRIEST", talent = true, spells = { 14752, 27681 },
		names = { "Divine Spirit", "Prayer of Spirit" }, words = { "spirit", "ds" } },
	{ id = "shadow", label = "Shadow Protection", class = "PRIEST", optional = true, spells = { 976, 27683 },
		names = { "Shadow Protection", "Prayer of Shadow Protection" }, words = { "shadow" } },
	{ id = "blessing", label = "a Blessing", class = "PALADIN",
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

local function SpellName(id, fallback)
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
GR.ResetNamesForTests = function() for _, f in ipairs(GR.BUFFS) do f._names = nil end end

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
	if v == nil or Secret(v) then return nil end
	return v == true
end

--- What the game hides right now, and why: { why = "in combat"... or nil }.
function GR.Why()
	local R, E = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
	if R and R.IsAddOnRestrictionActive and E then
		for _, k in ipairs({ { "Encounter", "in a boss fight" }, { "ChallengeMode", "in a keystone dungeon" },
			{ "PvPMatch", "in a PvP match" }, { "Map", "on this map" }, { "Combat", "in combat" } }) do
			if E[k[1]] ~= nil and Safe(R.IsAddOnRestrictionActive, E[k[1]]) == true then return k[2] end
		end
		return nil
	end
	return (InCombatLockdown and InCombatLockdown()) and "in combat" or nil
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

local ROLE_LABEL = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
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
local function NoTarget(e) ns:Print(("In combat: target %s from your party or raid frames."):format(tostring(e.name))) end
local function NoBuff(e) ns:Print(("In combat: cast %s on %s from your bars."):format(tostring(e.buffWith), tostring(e.name))) end

--- What's sent: "Plamen Pally (Paladin, Healer): dead, out of range, needs Fortitude".
local function ShareText(e)
	local said = {}
	if e.dead then said[#said + 1] = e.ghost and "a ghost" or "dead" end
	if e.online == false then said[#said + 1] = "offline" end
	if e.inRange == false then said[#said + 1] = "out of range" end
	if e.missing and #e.missing > 0 then said[#said + 1] = "needs " .. table.concat(e.missingLabels, ", ") end
	local who = e.name .. ((e.className or e.roleLabel) and (" (" .. table.concat({ e.className, e.roleLabel }, ", ") .. ")") or "")
	return who .. (#said > 0 and (": " .. table.concat(said, ", ")) or "")
end

local function Tooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	t:AddLine(table.concat({ e.level and ("Level " .. e.level) or nil, e.className, e.roleLabel, e.zone }, "  ·  "), 1, 1, 1)
	if e.dead then t:AddLine(e.ghost and "A ghost" or "Dead", 1, 0.25, 0.25) end
	if e.online == false then t:AddLine("Offline", 0.6, 0.6, 0.6) end
	if e.inRange == false then t:AddLine("Out of range (the game's own range test, as the raid frames fade)", 1, 0.6, 0.2, true)
	elseif e.rangeHidden then t:AddLine("Range: hidden by the game right now", 0.6, 0.6, 0.6) end
	if e.buffsHidden then
		t:AddLine("Buffs: hidden by the game right now", 0.6, 0.6, 0.6)
	elseif e.missing and #e.missing > 0 then
		t:AddLine("Needs " .. table.concat(e.missingLabels, ", "), 1, 0.82, 0, true)
	elseif e.buffs then
		t:AddLine("Has every buff the group can give", 0.4, 1, 0.4, true)
	end
	if e.buffs then
		local list = {}
		for _, n in pairs(e.buffs) do list[#list + 1] = n end
		table.sort(list)
		if #list > 0 then t:AddLine("Buffs: " .. table.concat(list, ", ", 1, math.min(#list, 12)) .. (#list > 12 and ", ..." or ""), 0.7, 0.7, 0.7, true) end
	end
	t:AddLine("Enter: target" .. (e.buffWith and ("    Shift+Enter: cast " .. e.buffWith .. " on them") or ""), 0.6, 0.6, 0.6, true)
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
	if Secret(role) then m.roleHidden = true else role = Str(role) end
	if role and role ~= "NONE" and not m.roleHidden then m.role = role end
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
	local buffWith
	for _, id in ipairs(missing or {}) do
		buffWith = GR.YourSpell(GR.BY_ID[id])
		if buffWith then break end
	end
	local d = {}
	local roleLabel = m.role and ROLE_LABEL[m.role]
	d[#d + 1] = (m.level and ("Lv " .. m.level .. " ") or "") .. (m.className or "")
	if roleLabel then d[#d + 1] = roleLabel end
	if m.dead then d[#d + 1] = RED .. (m.ghost and "Ghost" or "Dead") .. "|r" end
	if m.online == false then d[#d + 1] = GREY .. "Offline|r" end
	if m.inRange == false then d[#d + 1] = ORANGE .. "out of range|r" elseif m.rangeHidden then d[#d + 1] = GREY .. "range hidden|r" end
	if m.buffsHidden then d[#d + 1] = GREY .. "buffs hidden|r"
	elseif labels and #labels > 0 then d[#d + 1] = YELLOW .. "needs " .. table.concat(labels, ", ") .. "|r" end
	if m.mine then d[#d + 1] = GREY .. "(you)|r" end
	if raidInfo and raidInfo.group then d[#d + 1] = GREY .. "group " .. raidInfo.group .. "|r" end
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
		buffs = m.buffs, buffsHidden = m.buffsHidden, missing = missing, missingLabels = labels, buffWith = buffWith,
		zone = raidInfo and raidInfo.zone,
		color = m.online == false and GREY or ns.ClassHex(m.classFile), icon = Icon(m.classFile),
		detail = table.concat(d, "  ·  "), text = table.concat(words, " "),
		tooltip = Tooltip, shareLink = ShareText,
		secure = TARGET_SPEC, isOpen = ns.Never, activate = NoTarget,
		secondarySecure = buffWith and BUFF_SPEC or nil, secondaryIsOpen = buffWith and ns.Never or nil,
		secondary = buffWith and NoBuff or nil,
	}
end

function GR.Collect()
	local members = {}
	local units = GR.Units()
	local raid = Safe(IsInRaid) == true
	local raidInfo = {}
	for i, u in ipairs(units) do
		local m = GR.Read(u, u == "player" or (raid and Safe(UnitIsUnit, u, "player") == true))
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

--- What the game hides right now, in words: "range and buffs are hidden by the game right now (in combat)"; nil when
--- nothing is.
function GR.HiddenText()
	local h = GR.hidden
	if not h then return nil end
	local what = {}
	if h.range > 0 then what[#what + 1] = "range" end
	if h.buffs > 0 then what[#what + 1] = "buffs" end
	if h.roles > 0 then what[#what + 1] = "roles" end
	if #what == 0 then return nil end
	local why = GR.Why()
	local s = table.concat(what, #what == 2 and " and " or ", ")
	return s:gsub("^%l", string.upper) .. " hidden by the game right now" .. (why and (" (" .. why .. ")") or "")
end

local function NoteRow(text)
	return { name = text, raw = true, icon = false, noActivate = true, kindLabel = "", detail = "" }
end

ns:RegisterProvider("group", {
	label = "Group",
	color = "ff7fe07f", -- (the party frame's green, apart from the slash commands')
	aliases = { "group", "party", "members" }, -- (@raid is the raids' entrances: Entrances.lua)
	explicit = true, -- (only with @group, Simple mode's Group category, or asked in words)
	refreshOnOpen = true, -- (range and buffs move all the time)
	events = { "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION", "PLAYER_ROLES_ASSIGNED", "UNIT_FLAGS", "UNIT_AURA", "UNIT_HEALTH",
		"PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
		"ADDON_RESTRICTION_STATE_CHANGED" },
	guard = 1,
	-- a line on top: what the game hides right now, or that you're not in a group
	leadRow = function(p)
		ns:GetEntries(p)
		local h = GR.HiddenText()
		if h then return NoteRow(h) end
		if GR.solo then return NoteRow("You're not in a group: only you are listed") end
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
	unbuffed = "missing", buff = "missing", buffs = "missing", tank = "tank", tanks = "tank", healer = "healer",
	healers = "healer", heals = "healer", healing = "healer", dps = "dps", damage = "dps", inrange = "near" }

--- The question: { dead, offline, far, near, missing = { families }, buffWords = { other buff names }, roles = { ROLE }, words },
--- or nil when the line isn't about the group.
function GR.Question(text)
	if type(text) ~= "string" or text:find("[@:>|]") or text:find("^%s*[%./]") then return nil end
	local t = Lower(text):gsub("'", ""):gsub("[%p]", " ")
	t = t:gsub("in range", "inrange"):gsub("out of range", "outofrange")
	local subject, who, cues, rest = false, false, {}, {}
	for w in t:gmatch("%S+") do
		if SUBJECT[w] then subject = true
		elseif CUE[w] then cues[CUE[w]] = true; if w == "buff" or w == "buffs" or w == "unbuffed" then subject = true end
		elseif w == "who" or w == "whos" then who = true
		elseif not ASK[w] then rest[#rest + 1] = w end
	end
	if not (subject or who) or not next(cues) then return nil end
	local q = { dead = cues.dead, offline = cues.offline, far = cues.far, near = cues.near, words = {} }
	local roles = {}
	if cues.tank then roles[#roles + 1] = "TANK" end
	if cues.healer then roles[#roles + 1] = "HEALER" end
	if cues.dps then roles[#roles + 1] = "DAMAGER" end
	if #roles > 0 then q.roles = roles end
	if cues.missing then
		q.missing, q.buffWords = {}, {}
		local i = 1
		while i <= #rest do -- (a buff's own words: "shadow protection", "mark of the wild", "kings")
			local w = rest[i]
			local f = GR.BY_WORD[w]
			if f then
				q.missing[#q.missing + 1] = f.id
			else
				q.buffWords[#q.buffWords + 1] = w
			end
			i = i + 1
		end
		-- leftover words are one buff's name ("thorns", "blessing of kings" -> "kings")
		local drop = { of = true, the = true, protection = true }
		local kept = {}
		for _, w in ipairs(q.buffWords) do if not drop[w] then kept[#kept + 1] = w end end
		q.buffWords = kept
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
		if #q.missing == 0 and #(q.buffWords or {}) == 0 then
			if not (e.missing and #e.missing > 0) then return false end
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
	local what = (q.dead and "Dead") or (q.offline and "Offline") or (q.far and "Out of range") or (q.near and "In range")
		or (q.missing and ((Labels(q) ~= "" and ("Needs " .. Labels(q))) or "Missing a buff the group can give"))
		or (q.roles and ({ TANK = "Tanks", HEALER = "Healers", DAMAGER = "Damage dealers" })[q.roles[1]]) or "Your group"
	local note = what .. ("  ·  %d of %d"):format(#rows, #all)
	local hidden = GR.HiddenText()
	if (q.far or q.near) and GR.hidden and GR.hidden.range > 0 then note = note .. "  ·  " .. hidden
	elseif q.missing and GR.hidden and GR.hidden.buffs > 0 then note = note .. "  ·  " .. hidden
	elseif q.roles and GR.hidden and GR.hidden.roles > 0 then note = note .. "  ·  " .. hidden end
	if q.roles and #rows == 0 then
		local anyRole = false
		for _, e in ipairs(all) do if e.role then anyRole = true end end
		if not anyRole then note = note .. "  ·  nobody has a role set (the group finder sets them)" end
	end
	if GR.solo then note = note .. "  ·  you're not in a group" end
	if #rows == 0 and not (GR.hidden and (GR.hidden.range > 0 or GR.hidden.buffs > 0)) then
		local none = (q.dead and "Nobody is dead") or (q.offline and "Nobody is offline") or (q.far and "Everyone is in range")
			or (q.missing and "Nobody needs it") or nil
		if none then note = none .. (GR.solo and "  ·  you're not in a group" or "") end
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
		if #q.missing == 0 and #(q.buffWords or {}) == 0 then parts[#parts + 1] = "is:unbuffed" end
		for _, id in ipairs(q.missing) do parts[#parts + 1] = "missing:" .. id end
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
	local words = {}
	for w in v:gmatch("%S+") do words[#words + 1] = w end
	return function(e) return e.kind == "group" and not e.dead and e.online ~= false and LacksNamed(e, words) == true end
end
