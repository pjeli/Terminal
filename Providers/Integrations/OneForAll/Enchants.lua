local ns = select(2, ...)
local L = ns.L
local OA = ns.OneForAll

-- @enchant: OneForAll's enchant options (its ENCHANT_OPTIONS and ENCHANTS, read while it's installed, never copied):
-- enchants, armor kits, spurs, shield spikes, counterweights, scopes, arcanums and shoulder enchants, a row each, with
-- the slot it goes on (the game's slot names, from OneForAll's item class / inventory type / subclass masks), what it
-- gives (OneForAll's text and stats: stat: and slot: read them, Filters/Items.lua), how you get it (a profession and
-- its skill, or OneForAll's source) and whether you know it. Enter: a recipe you know opens as its recipe row does (its
-- fields copied); one you don't, the learn chain ("where to learn ..."); one no profession makes, where to get its item.
-- "enchants for my weapon", "enchants for bracers", "agility enchants", "enchants i can make" ask for them.
--
-- 1.3.10 (the player: "Have Atlasloot's data be the primary; and OFA be the fallback, as Atlasloot is more popular"):
-- the rows come from AtlasLoot when it has any: the Enchanting spells on its crafting pages that make no item (kept
-- with its loot index, Loot.lua's I.LootEnchants), each named and described by the game in its language, the skill it
-- needs from AtlasLoot, the slot from its English name ("Enchant Bracer - ..."). OneForAll's options only without them.
-- Set up on its own (Setup.lua's "Enchants"), so it needs neither addon in particular.

local EN = {}
OA.Enchants = EN
ns.Enchants = EN
local Safe, Lower, Num, Str = ns.Safe, ns.Lower, ns.Num, ns.Str
local SEP = ns.DETAIL_SEP
local GREY = "|cff8a8a8a"
EN.ICON = "Interface\\Icons\\Trade_Engraving"

-- its professions (English, as it names them) -> the skill line (the game's name for it, an icon)
local PROF = { Enchanting = { 333, "Interface\\Icons\\Trade_Engraving" }, Leatherworking = { 165, "Interface\\Icons\\Trade_LeatherWorking" },
	Blacksmithing = { 164, "Interface\\Icons\\Trade_BlackSmithing" }, Engineering = { 202, "Interface\\Icons\\Trade_Engineering" },
	Tailoring = { 197, "Interface\\Icons\\Trade_Tailoring" } }
-- the game's inventory type numbers (its t mask's bits) -> the slot type
local INVTYPE = { [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [4] = "INVTYPE_BODY", [5] = "INVTYPE_CHEST",
	[6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND",
	[11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET", [13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD", [15] = "INVTYPE_RANGED",
	[16] = "INVTYPE_CLOAK", [17] = "INVTYPE_2HWEAPON", [20] = "INVTYPE_ROBE", [21] = "INVTYPE_WEAPONMAINHAND",
	[22] = "INVTYPE_WEAPONOFFHAND", [23] = "INVTYPE_HOLDABLE", [25] = "INVTYPE_THROWN", [26] = "INVTYPE_RANGEDRIGHT" }
-- weapon subclasses (its m mask's bits): two-handed, one-handed, ranged (a scope's)
local TWO, ONE, RANGED = { 1, 5, 6, 8, 10 }, { 0, 4, 7, 13, 15 }, { 2, 3, 18 }
local SHIELD = 6 -- (an armor subclass)
local ONE_LOCS = { "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND" }
-- the English words a slot type goes by ("bracers" find a wrist enchant), beside the game's name
local LOC_WORDS = { INVTYPE_WRIST = "wrist bracer bracers", INVTYPE_FEET = "feet boots boot", INVTYPE_HAND = "hands gloves glove",
	INVTYPE_CLOAK = "back cloak cape", INVTYPE_HEAD = "head helm helmet", INVTYPE_LEGS = "legs leg pants leggings",
	INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest robe", INVTYPE_SHOULDER = "shoulder shoulders", INVTYPE_SHIELD = "shield",
	INVTYPE_2HWEAPON = "weapon 2h two-hand two-handed", INVTYPE_WEAPON = "weapon 1h one-hand", INVTYPE_RANGED = "ranged scope",
	INVTYPE_NECK = "neck necklace amulet", INVTYPE_HOLDABLE = "off hand offhand held", INVTYPE_WAIST = "waist belt",
	INVTYPE_FINGER = "finger ring" }
-- OneForAll's resistance keys -> the game's stat keys (as GetItemStats names them: stat:fire reads RESISTANCE2)
local RES = { HOLY_RES = "RESISTANCE1_NAME", FIRE_RES = "RESISTANCE2_NAME", NATURE_RES = "RESISTANCE3_NAME",
	FROST_RES = "RESISTANCE4_NAME", SHADOW_RES = "RESISTANCE5_NAME", ARCANE_RES = "RESISTANCE6_NAME" }

local function Bit(mask, n) return math.floor(mask / 2 ^ n) % 2 == 1 end
local function AnyBit(mask, list) for _, n in ipairs(list) do if Bit(mask, n) then return true end end return false end

--- The slot types an option goes on, and the slot as the game names it ("Wrist", "Weapon", "Two-Hand").
function EN.Slots(c, t, m)
	local locs, label = {}, {}
	local seen = {}
	local function Add(loc, name)
		if not seen[loc] then seen[loc] = true; locs[#locs + 1] = loc end
		name = name or ns.GameText(loc, nil)
		if name and not seen["n:" .. name] then seen["n:" .. name] = true; label[#label + 1] = name end
	end
	if c == 2 then
		local two, one, ranged = AnyBit(m, TWO), AnyBit(m, ONE), AnyBit(m, RANGED)
		if m == 0 or (two and one) then
			local w = ns.GameText("WEAPON", "Weapon")
			for _, loc in ipairs(ONE_LOCS) do Add(loc, w) end
			Add("INVTYPE_2HWEAPON", w)
		elseif two then Add("INVTYPE_2HWEAPON", ns.GameText("INVTYPE_2HWEAPON", "Two-Hand"))
		elseif one then for _, loc in ipairs(ONE_LOCS) do Add(loc, ns.GameText("INVTYPE_WEAPON", "One-Hand")) end end
		if ranged then
			local r = ns.GameText("INVTYPE_RANGED", "Ranged")
			Add("INVTYPE_RANGED", r); Add("INVTYPE_RANGEDRIGHT", r)
		end
	elseif t == 0 then
		if Bit(m, SHIELD) then Add("INVTYPE_SHIELD", ns.GameText("SHIELDSLOT", "Shield")) end
	else
		for n = 1, 26 do
			local loc = INVTYPE[n]
			if loc and Bit(t, n) then
				Add(loc, (loc == "INVTYPE_SHIELD" and ns.GameText("SHIELDSLOT", "Shield")) or (loc == "INVTYPE_ROBE" and ns.GameText("INVTYPE_CHEST", nil)) or nil)
			end
		end
	end
	return locs, table.concat(label, ", ")
end

--- OneForAll's options, checked: { { e, name, prof, spell, item, req, src, absent, c, t, m, text, stats, order } }, or nil.
function EN.OFAData()
	return OA.Part("enchants", "ENCHANT_OPTIONS", L["@enchant (its enchants) is unavailable."], function(raw, lib)
		local texts = type(lib.ENCHANTS) == "table" and lib.ENCHANTS or {}
		local out, bad = {}, 0
		for i, o in ipairs(raw) do
			local name = type(o) == "table" and OA.Text(o.n)
			local c, t, m = type(o) == "table" and Num(o.c), type(o) == "table" and Num(o.t), type(o) == "table" and Num(o.m)
			local spell, item = type(o) == "table" and Num(o.s), type(o) == "table" and Num(o.i)
			if name and c and (spell or item) then
				local d = texts[o.e]
				local stats = {}
				if type(d) == "table" and type(d[2]) == "table" then
					for k, v in pairs(d[2]) do
						if type(k) == "string" and type(v) == "number" then stats[RES[k] or k] = v end
					end
				end
				out[#out + 1] = { e = o.e, name = name, prof = OA.Text(o.p), spell = spell, item = item, req = Num(o.req),
					src = OA.Text(o.src), absent = o.st == 0, c = c, t = t or 0, m = m or 0,
					text = type(d) == "table" and OA.Text(d[1]) or nil, stats = stats, order = i }
			else
				bad = bad + 1
			end
		end
		if #out == 0 then return nil, "OneForAll.ENCHANT_OPTIONS: no option in the shape expected (" .. bad .. " entries not)" end
		if bad > 0 then ns:Trace(("oneforall: %d enchant options not in the shape expected, left out"):format(bad)) end
		return out
	end)
end

-- an enchant's slot from its English name ("Enchant 2H Weapon - Agility": the words between "Enchant" and " - ")
local AL_SLOTS = {
	bracer = { "INVTYPE_WRIST" }, boots = { "INVTYPE_FEET" }, gloves = { "INVTYPE_HAND" }, cloak = { "INVTYPE_CLOAK" },
	chest = { "INVTYPE_CHEST", "INVTYPE_ROBE" }, shield = { "INVTYPE_SHIELD" }, ["2h weapon"] = { "INVTYPE_2HWEAPON" },
	weapon = { "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_2HWEAPON" },
}
EN.AL_SLOTS = AL_SLOTS
--- The slot types an enchant goes on by its name, and the slot as the game names it; nothing for a name that isn't
--- English or doesn't say (stat: and slot: then read its text).
function EN.SlotsOfName(name)
	local part = type(name) == "string" and name:match("^Enchant (.-) %- ")
	local locs = part and AL_SLOTS[Lower(part)]
	if not locs then return {}, "" end
	local label = (part:lower() == "weapon" and ns.GameText("WEAPON", "Weapon"))
		or (locs[1] == "INVTYPE_SHIELD" and ns.GameText("SHIELDSLOT", "Shield")) or ns.GameText(locs[1], part)
	return locs, label
end

local function SpellName(id)
	local f = C_Spell and C_Spell.GetSpellName
	local n = f and Str(Safe(f, id))
	if not n and _G.GetSpellInfo then n = Str(Safe(_G.GetSpellInfo, id)) end
	return n
end
local function SpellText(id)
	local f = C_Spell and C_Spell.GetSpellDescription or _G.GetSpellDescription
	local s = f and Str(Safe(f, id))
	if s and s ~= "" then return s end
	if C_Spell and C_Spell.RequestLoadSpellData then Safe(C_Spell.RequestLoadSpellData, id) end -- (in a moment, next time)
	return nil
end

--- AtlasLoot's enchants as options (the shape OneForAll's are in, the slot worked out: locs, slotName), or nil when
--- AtlasLoot has none (not installed, its index not read yet, no crafting module).
function EN.FromAtlasLoot()
	local I = ns.Integrations
	local ids = I and I.LootEnchants and I.LootEnchants() or {}
	if #ids == 0 then return nil end
	local A = rawget(_G, "AtlasLoot")
	local P = type(A) == "table" and type(A.Data) == "table" and A.Data.Profession
	local out = {}
	for i, id in ipairs(ids) do
		local name = SpellName(id)
		if name then
			local d = P and P.GetProfessionData and Safe(P.GetProfessionData, id)
			local locs, slotName = EN.SlotsOfName(name)
			out[#out + 1] = { e = id, name = name, prof = "Enchanting", spell = id, req = type(d) == "table" and Num(d[3]) or nil,
				c = 0, t = 0, m = 0, locs = locs, slotName = slotName, text = SpellText(id), stats = {}, order = i,
				source = "AtlasLoot" }
		end
	end
	return #out > 0 and out or nil
end

--- The options @enchant lists: AtlasLoot's when it has any, else OneForAll's (nil: neither).
function EN.Data()
	return EN.FromAtlasLoot() or EN.OFAData()
end

-- a profession's name in the game's words, else OneForAll's
local function ProfName(p)
	local pr = p and PROF[p]
	local f = pr and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
	return f and Str(Safe(f, pr[1])) or p
end

-- your recipe rows by their spell (the recipe index: Recipes.lua)
local function YourRecipes()
	local p = ns.providers.recipes
	local by = {}
	for _, r in ipairs(p and ns:GetEntries(p) or {}) do
		if type(r.recipeID) == "number" then by[r.recipeID] = r end
	end
	return by
end
-- (what opens a recipe row, copied onto the enchant you know)
local RECIPE_FIELDS = { "recipeID", "profID", "profName", "profSpell", "profWindow", "getLink", "activate", "secure", "isOpen",
	"after", "reagents", "secondary", "secondarySecure", "secondaryIsOpen" }

local function SpellLink(e)
	local f = C_Spell and C_Spell.GetSpellLink or _G.GetSpellLink
	return Str(f and Safe(f, e.spell)) or e.name
end
local function ItemLink(e)
	local f = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
	return Str(f and select(2, Safe(f, e.itemID))) or e.name
end
local function Walk(e, rel)
	local P = ns.Pipes
	OA.Walk(P and P.Phrase and P.Phrase(rel == "sources" and (e.itemName or e.name) or e.name, rel) or e.name, e)
end
local function WalkLearn(e) Walk(e, "learn") end
local function WalkSources(e) Walk(e, "sources") end
-- (you know it, the window not read yet: nothing to open it on)
local function NotIndexed() ns:Print(L["Open a profession's window once: Terminal reads its recipes from it"]) end
local SPELL_CHATBOX, ITEM_CHATBOX = ns.ChatBoxSpec(SpellLink), ns.ChatBoxSpec(ItemLink)

local function Tooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	if e.effect then t:AddLine(e.effect, 1, 1, 1, true) end
	if e.slotName ~= "" then t:AddLine(e.slotName, 0.8, 0.8, 0.8) end
	t:AddLine(e.how, 0.8, 0.8, 0.8, true)
	if e.known then t:AddLine(L["You know it"], 0.4, 1, 0.4) end
	if e.absent then t:AddLine(L["not in WoW Forever yet"], 1, 0.5, 0.3) end
	t:AddLine(e.source == "AtlasLoot" and L["Enchants from AtlasLoot"] or L["Enchants from OneForAll"], 0.5, 0.5, 0.5)
end

--- The rows: one an option, in OneForAll's order (its professions, the skill each needs).
function EN.Rows()
	local mine = YourRecipes()
	local known = _G.IsPlayerSpell or (C_SpellBook and C_SpellBook.IsSpellKnown)
	local out = {}
	for _, o in ipairs(EN.Data() or {}) do
		local locs, slotName
		if o.locs then locs, slotName = o.locs, o.slotName else locs, slotName = EN.Slots(o.c, o.t, o.m) end
		local pname = ProfName(o.prof)
		local how = (o.prof and o.spell) and (pname .. (o.req and (" " .. o.req) or "")) or o.src or ""
		local rec = o.spell and mine[o.spell]
		local isKnown = rec ~= nil or (o.spell ~= nil and known ~= nil and Safe(known, o.spell) == true)
		local icon = (o.item and Safe(C_Item and C_Item.GetItemIconByID, o.item))
			or (o.spell and Safe(C_Spell and C_Spell.GetSpellTexture, o.spell)) or (PROF[o.prof or ""] or {})[2] or EN.ICON
		local words = {}
		for _, loc in ipairs(locs) do words[#words + 1] = LOC_WORDS[loc] or "" end
		local row = {
			key = o.spell and ("s" .. o.spell) or ("i" .. o.item), name = o.name, _lname = Lower(o.name), icon = icon,
			spell = o.spell, itemID = (not o.spell) and o.item or nil, itemName = o.name,
			profName = o.prof and pname or nil, profLine = o.prof and PROF[o.prof] and PROF[o.prof][1] or nil, need = o.req,
			enchantSlots = locs, enchantStats = o.stats, enchantText = o.text and Lower(o.text) or nil, effect = o.text,
			slotName = slotName, how = how, known = isKnown or nil, absent = o.absent or nil, order = o.order, source = o.source,
			color = o.absent and GREY or nil, tooltip = Tooltip,
			detail = ns.Detail(slotName ~= "" and slotName or nil, o.text, how, isKnown and L["You know it"] or nil,
				o.absent and L["not in WoW Forever yet"] or nil),
			text = Lower(table.concat({ "enchant enchantment", o.text or "", slotName, table.concat(words, " "), pname or "",
				o.prof or "", o.src or "", isKnown and "known learned" or "" }, " ")),
		}
		if rec then
			for _, k in ipairs(RECIPE_FIELDS) do row[k] = rec[k] end
		elseif o.spell then
			-- (you know it, its window's recipes not read yet: says so; else where to learn it)
			if isKnown then row.activate = NotIndexed else row.activate, row.staysOpen = WalkLearn, true end
			row.getLink, row.secondary = SpellLink, function(e) ns.LinkInChat(SpellLink(e)) end
			row.secondarySecure, row.secondaryIsOpen = SPELL_CHATBOX, ns.ChatBoxNeverOpen
		else
			-- (an arcanum, a mantle: its item, where to get it)
			row.activate, row.staysOpen = WalkSources, true
			row.getLink, row.secondary = ItemLink, function(e) ns.LinkInChat(ItemLink(e)) end
			row.secondarySecure, row.secondaryIsOpen = ITEM_CHATBOX, ns.ChatBoxNeverOpen
		end
		out[#out + 1] = row
	end
	return out
end

local function Verbs(e)
	if e.recipeID then return L["show recipe"], L["link in chat"] end
	if e.spell then return (not e.known) and L["where to learn"] or nil, L["link in chat"] end
	return L["where to get it"], L["link in chat"]
end

--- @enchant, with AtlasLoot (its enchants come in with its loot index, a moment after login) or OneForAll.
function EN.Setup()
	local I = ns.Integrations
	local atlas = I and I.LoadedCore and I.LoadedCore()
	if not (atlas or EN.OFAData()) or ns.providers.enchant then return end
	ns:RegisterProvider("enchant", {
		label = L["Enchant"], color = "ffb48cff", aliases = { "enchant", "enchants", "enchantment", "enchantments" },
		lazy = true, follows = "recipes", -- (made again with your recipe index: the ones you know open as recipes)
		events = { "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE" }, guard = 1,
		collect = EN.Rows,
	})
	if ns.Easy and ns.Easy.VERBS then ns.Easy.VERBS.enchant = Verbs end
	-- "where to learn <enchant>": a recipe the learn chain knows by its spell (AtlasLoot's, a trainer's window), else the
	-- profession and skill OneForAll says
	if ns.RegisterRelation and not EN.learnRelation then
		EN.learnRelation = true
		ns:RegisterRelation("learn", {
			aliases = { "learned", "taught", "teach", "teaches", "trainer", "trainers" },
			desc = L["where to learn the recipe: its recipe item, or a trainer"],
			available = function() return ns.providers.enchant ~= nil end,
			seedAlso = { "enchant" },
			applies = function(e) return e.kind == "enchant" and e.spell ~= nil and not e.recipeID end,
			run = function(rows)
				local P = ns.Pipes
				local out = {}
				for _, e in ipairs(rows) do
					local got = P.Run("learn", { { kind = "missing", key = e.spell, recipeID = e.spell, name = e.name, profLine = e.profLine } })
					if #got == 0 and e.profName then
						got = { { key = "enchant:" .. e.spell, kind = "source", noActivate = true, icon = "Interface\\Icons\\INV_Misc_Book_11",
							name = L["learn at %s %s"]:format(e.profName, e.need or ""), detail = e.source == "AtlasLoot" and L["Enchants from AtlasLoot"] or L["Enchants from OneForAll"] } }
					end
					for _, r in ipairs(got) do out[#out + 1] = r end
				end
				return out
			end,
		})
	end
end
if ns.Integrations and ns.Integrations._ then ns.Integrations._.SetupEnchants = EN.Setup end
OA.AddStatus(function()
	local d = EN.OFAData()
	return d and L["%d enchants (@enchant)"]:format(#d) or nil
end)

----------------------------------------------------------------------
-- "enchants for my weapon", "enchants for bracers", "agility enchants", "enchants i can make": search questions, each
-- its @enchant line (Search/Questions/Questions.lua's registry)
----------------------------------------------------------------------

local ENCHANT = { enchant = true, enchants = true, enchantment = true, enchantments = true }
local KNOW = { make = true, craft = true, know = true, known = true, learned = true, have = true }
local MY_WEAPON = { weapon = true, weapons = true, mainhand = true }
local FILL = {}
for w in ([[what whats which can could i im ive my me mine is are the a an of for to on in at do does show list all any
	there good best get with]]):gmatch("%S+") do FILL[w] = true end
local SLOT_WORDS = { wrist = true, feet = true, hands = true, back = true, head = true, legs = true, chest = true, shoulder = true,
	shield = true, weapon = true, ranged = true, neck = true, waist = true }

local function SlotWord(w)
	local F = ns.Filters
	return SLOT_WORDS[w] or (F and F.SLOT_ALIAS and F.SLOT_ALIAS[w] ~= nil) or false
end
local function StatWord(w)
	local F = ns.Filters
	return F and F.STAT_WORDS and F.STAT_WORDS[w] ~= nil or false
end

-- your main hand's slot as a slot: word ("2h", "1h"), "weapon" when nothing's in it
local function MainHandSlot()
	local id = _G.GetInventoryItemID and Num(Safe(_G.GetInventoryItemID, "player", 16))
	local f = C_Item and C_Item.GetItemInfoInstant or _G.GetItemInfoInstant
	local loc = id and f and select(4, Safe(f, id))
	if loc == "INVTYPE_2HWEAPON" then return "2h" end
	if type(loc) == "string" and loc ~= "" then return "1h" end
	return "weapon"
end

local function AnyHas(words)
	local p = ns.providers.enchant
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do if OA.Has(e, words) then return true end end
	return false
end

--- The question: { known, slot (a slot: word), stats (stat: words), words (narrowing: a name) }, or nil.
function EN.Question(text)
	if not ns.providers.enchant then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local any, known, my, slot, stats, rest = false, false, false, nil, {}, {}
	for w in t:gmatch("%S+") do
		if ENCHANT[w] then any = true
		elseif KNOW[w] then known = true
		elseif w == "my" then my = true
		elseif my and MY_WEAPON[w] then slot = MainHandSlot()
		elseif SlotWord(w) then slot = w
		elseif StatWord(w) then stats[#stats + 1] = w
		elseif not FILL[w] then rest[#rest + 1] = w end
	end
	if not any then return nil end
	if #rest > 0 and not AnyHas(rest) then return nil end
	if not (known or slot or #stats > 0 or #rest > 0) then return nil end -- ("enchants" alone: the list's own name)
	return { known = known or nil, slot = slot, stats = stats, words = rest }
end

function EN.Line(q)
	local parts = { "@enchant" }
	if q.known then parts[#parts + 1] = "is:known" end
	if q.slot then parts[#parts + 1] = "slot:" .. q.slot end
	for _, s in ipairs(q.stats or {}) do parts[#parts + 1] = "stat:" .. s end
	for _, w in ipairs(q.words or {}) do parts[#parts + 1] = w end
	parts[#parts + 1] = "sort:list"
	return table.concat(parts, " ") .. " "
end
