local ns = select(2, ...)
local L = ns.L
local H = ns.Highlight
local I = ns.Integrations
local Safe, Str, Num, Lower = ns.Safe, ns.Str, ns.Num, ns.Lower
local AddOnVersion = I._.AddOnVersion

----------------------------------------------------------------------
-- What's Training (0.53.7, the player's ask): the spells, ranks, weapon skills, pet abilities and grimoires your class
-- has still to learn become @training, each with when you can learn it, what it costs and where it's taught, as What's
-- Training works them out. Read through its public API (WT_API, its forever branch; version 1), never its own tables:
--
--   WT_API.GetSpells()      every spell it sorts, with its status (learn now, next level, later, needs a rank or a
--                           talent first, a pet ability, ignored, known), level, cost at your faction's prices, link
--   WT_API.GetSource(id)    where it's taught: your class trainer, a weapon master (which, and where), a quest, an item
--   its callbacks           Ready, SpellsChanged, LevelChanged, IgnoredChanged: the list made again (ns:Changed)
--   WT_API.GetCatalog(cls)  every class's spells and weapon masters (0.56.1): @spell's other classes' spells, "druid
--                           spells", "dagger trainer" (Providers/ClassSpells.lua); ClassReady: their names came in
--
-- Known spells are @spell's; the ones you ignored in What's Training are listed last, said so. Enter opens What's
-- Training's window on the spell and points at it; Shift+Enter lists who teaches it, the nearest first (Enter on one:
-- the map on it); the row menu puts it in the chat box. Search/WhatsTraining.lua:
-- "what can i train", "what do i learn next level", "how much is training", "<spell> > learn" (where it's taught).
----------------------------------------------------------------------

local WT = {}
ns.WhatsTraining = WT
local training = { on = false }
I.whatstraining = training

WT.ADDON = "WhatsTraining"
WT.MIN_VERSION = 1 -- (the API's version this was written for: its GetSpells, GetSource, Status and callbacks)

--- What's Training's public API when it's there and new enough, else nil.
function WT.Api()
	local api = rawget(_G, "WT_API")
	if type(api) ~= "table" then return nil end
	local ok, v = pcall(function() return api.version end)
	if not (ok and type(v) == "number" and v >= WT.MIN_VERSION) then return nil end
	return api
end

--- Is What's Training loaded (with its API or not)?
local function Loaded()
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	if not isLoaded then return WT.Api() ~= nil end
	local ok, yes = pcall(isLoaded, WT.ADDON)
	return ok and yes == true
end
WT.Loaded = Loaded

----------------------------------------------------------------------
-- What a spell's status is to Terminal
----------------------------------------------------------------------

-- state: what you can do about it now; the order lists show them in (What's Training's own: learn now first)
WT.STATES = { "now", "needsrank", "nextlevel", "later", "pet", "needstalent", "ignored" }
local ORDER = {}
for i, s in ipairs(WT.STATES) do ORDER[s] = i end
-- the API's status keys (WT_API.Status) -> { state, weapon, pet }; the known ones left out (@spell has your spells)
local KEYS = {
	AVAILABLE = { "now" }, MISSINGREQS = { "needsrank" }, NEXTLEVEL = { "nextlevel" }, NOTLEVEL = { "later" },
	MISSINGTALENT = { "needstalent" }, PET = { "pet", false, true }, IGNORED = { "ignored" }, IGNORED_PET = { "ignored", false, true },
	WEAPON_AVAILABLE = { "now", true }, WEAPON_NEXTLEVEL = { "nextlevel", true }, WEAPON_NOTLEVEL = { "later", true },
	WEAPON_IGNORED = { "ignored", true },
	-- (a weapon skill you know: not listed, but "where do i learn daggers" still finds its weapon masters: WT.Known)
	WEAPON_KNOWN = { "known", true },
	KNOWN = false, KNOWN_PET = false,
}
local states -- status value -> { state, weapon, pet } or false (known), made from the API's own Status table
local function StateOf(api, status)
	if not states then
		states = {}
		local S = api.Status
		for k, v in pairs(KEYS) do
			local ok, value = pcall(function() return S[k] end)
			if ok and type(value) == "string" then states[value] = v end
		end
	end
	return states[status]
end
function WT.ForgetStates() states = nil end -- (tests: another API)

-- (each state's colour and how a row says it; What's Training's colours: green now, blue soon, red later)
local HEX = { now = "|cff40ff40", needsrank = "|cffff9933", nextlevel = "|cff82c5ff", later = "|cffff5050", pet = "|cffffffff",
	needstalent = "|cffffffff", ignored = "|cffffffa0", known = "|cff9d9d9d" }
WT.HEX = HEX
local RGB = { now = { 0.25, 1, 0.25 }, needsrank = { 1, 0.6, 0.2 }, nextlevel = { 0.51, 0.77, 1 }, later = { 1, 0.31, 0.31 },
	pet = { 1, 1, 1 }, needstalent = { 1, 1, 1 }, ignored = { 1, 1, 0.63 }, known = { 0.62, 0.62, 0.62 } }
WT.RGB = RGB
WT.SAY = { now = L["learn now"], needsrank = L["needs another rank first"], nextlevel = L["next level"], later = L["later"],
	pet = L["pet ability"], needstalent = L["needs a talent"], ignored = L["ignored"], known = L["known"] }
-- (the words a row is found by: its state's, and what it is)
local WORDS = { now = "now available learnable trainable", needsrank = "requirements needs rank", nextlevel = "next level soon coming",
	later = "later", pet = "pet", needstalent = "talent", ignored = "ignored hidden", known = "known" }

local function SpellName(id)
	if type(id) ~= "number" then return nil end
	return Str(Safe(C_Spell and C_Spell.GetSpellName, id)) or Str((Safe(_G.GetSpellInfo, id)))
end
WT.SpellName = SpellName

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local SEP = ns.DETAIL_SEP
local DIM, GOLD = { 0.6, 0.6, 0.6 }, { 1, 0.82, 0 }
local ICON = "Interface\\Icons\\INV_Misc_Book_09"

--- Where a row's spell is taught, from what the list says of it (no call): "trainer", "weaponMaster", "quest", "item".
local function SourceKind(e)
	if e.quest then return "quest" end
	if e.isItem then return "item" end
	if e.weapon then return "weaponMaster" end
	return "trainer"
end
WT.SourceKind = SourceKind
WT.SOURCE = { trainer = L["your class trainer"], weaponMaster = L["a weapon master"], quest = L["a quest"], item = L["an item"],
	pet = L["a pet trainer"] }

--- What the row says after its name: its state (and level, when not now), its cost, where it's taught when that's not
--- your class trainer.
local function Detail(e)
	local parts = { HEX[e.state] .. WT.SAY[e.state] .. "|r" }
	if e.state ~= "now" and e.state ~= "known" and e.level then parts[#parts + 1] = L["Lv %s"]:format(e.level) end
	if (e.cost or 0) > 0 then parts[#parts + 1] = ns.Money(e.cost) end
	local src = SourceKind(e)
	if src ~= "trainer" then parts[#parts + 1] = L["from %s"]:format(WT.SOURCE[src]) end
	return table.concat(parts, SEP)
end
WT.Detail = Detail

--- A row's words for chat: its link, rank, level and cost ("[Fireball] (Rank 5), level 22, 1g 80s").
local function ShareText(e)
	local what = (type(e.link) == "string" and e.link:find("|H", 1, true)) and e.link or ("[" .. tostring(e.spellName or e.name) .. "]")
	local bits = {}
	if e.rank then bits[#bits + 1] = e.rank end
	if e.level then bits[#bits + 1] = L["level %d"]:format(e.level) end
	if (e.cost or 0) > 0 then bits[#bits + 1] = ns.Money(e.cost, true) end
	return #bits > 0 and (what .. " " .. table.concat(bits, ", ")) or what
end
WT.ShareText = ShareText

-- the quests' names (Questie's, else the game's), the weapon masters' names and places, the item's name
local function QuestTitle(qid)
	local row = I.QuestRow and I.QuestRow(qid)
	if row and Str(row.name) then return row.name end
	return Str(Safe(C_QuestLog and C_QuestLog.GetTitleForQuestID, qid)) or L["Quest #%d"]:format(qid)
end
WT.QuestTitle = QuestTitle

--- A weapon skill's masters for your faction when What's Training doesn't say (TrainerSpells' @training rows):
--- Providers/ClassSpells.lua's, { { npc, name, uiMapId, x, y } }.
function WT.MastersOf(e)
	local CS = ns.ClassSpells
	local _, list = nil, nil
	if CS and CS.WeaponMasters and type(e.wtId) == "number" then _, list = CS.WeaponMasters({ e.wtId }) end
	return list or {}
end

--- Where it's taught, as tooltip lines: { text, colour }.
function WT.SourceLines(e)
	local api = WT.Api()
	local ok, src = false, nil
	if api and e.wtId ~= nil then ok, src = pcall(api.GetSource, e.wtId) end
	src = ok and type(src) == "table" and src or nil
	local kind = src and src.kind or SourceKind(e)
	local out = {}
	if kind == "quest" then
		local names = {}
		for i, qid in ipairs(src and src.quests or {}) do
			if i > 3 then names[#names + 1] = L["and %d more"]:format(#src.quests - 3) break end
			names[#names + 1] = QuestTitle(qid)
		end
		out[#out + 1] = #names > 0 and L["From a quest: %s"]:format(table.concat(names, ", ")) or L["From a quest"]
		if src and Num(src.level) then out[#out + 1] = L["The quest needs level %d"]:format(src.level) end
	elseif kind == "weaponMaster" then
		local list = {}
		for i, t in ipairs(src and src.trainers or WT.MastersOf(e)) do
			if i > 4 then break end
			local zone = t.uiMapId and I.ZoneName and I.ZoneName(t.uiMapId)
			list[#list + 1] = tostring(t.name) .. (zone and (" (" .. zone .. ")") or "")
		end
		out[#out + 1] = #list > 0 and L["Weapon masters: %s"]:format(table.concat(list, ", ")) or L["From a weapon master"]
	elseif kind == "item" then
		local id = src and src.itemId or e.itemID
		local n = id and (Str(Safe(C_Item and C_Item.GetItemNameByID, id)) or Str((Safe(C_Item and C_Item.GetItemInfo, id))))
		out[#out + 1] = n and L["From an item: %s"]:format(n) or L["From an item"]
	else
		out[#out + 1] = e.pet and L["Taught by a pet trainer"] or L["Taught by your class trainer"]
	end
	return out
end

local function Tooltip(e, t)
	local shown = false
	if e.isItem and e.itemID then shown = pcall(t.SetHyperlink, t, "item:" .. e.itemID)
	elseif type(e.wtId) == "number" then shown = pcall(t.SetHyperlink, t, "spell:" .. e.wtId) end
	if not shown then t:SetText(e.name, GOLD[1], GOLD[2], GOLD[3]) end
	t:AddLine(" ")
	local c = RGB[e.state] or DIM
	local said = (e.state == "now" and L["You can learn it now"]) or (e.state == "nextlevel" and L["You can learn it at level %d (next level)"]:format(e.level or 0))
		or (e.state == "later" and L["You can learn it at level %d"]:format(e.level or 0))
		or (e.state == "needsrank" and L["Learn the rank before it first"]) or (e.state == "needstalent" and L["It needs a talent first"])
		or (e.state == "pet" and L["A pet ability: taught by a pet trainer"]) or (e.state == "ignored" and L["Ignored in What's Training"])
		or (e.state == "known" and L["You know it"]) or ""
	t:AddLine(said, c[1], c[2], c[3], true)
	-- what it needs first: earlier ranks, a talent
	local needs = {}
	for _, id in ipairs(e.requiredIds or {}) do needs[#needs + 1] = SpellName(id) or ("#" .. tostring(id)) end
	if #needs > 0 then t:AddLine(L["Needs first: %s"]:format(table.concat(needs, ", ")), 1, 1, 1, true) end
	if e.requiredTalentId then t:AddLine(L["Needs the talent: %s"]:format(SpellName(e.requiredTalentId) or ("#" .. tostring(e.requiredTalentId))), 1, 1, 1, true) end
	if (e.cost or 0) > 0 then
		t:AddDoubleLine(L["Costs"], ns.Money(e.cost), 1, 1, 1, 1, 1, 1)
		if e.baseCost and e.baseCost ~= e.cost then t:AddLine(L["%s without your discount"]:format(ns.Money(e.baseCost)), DIM[1], DIM[2], DIM[3]) end
	end
	for _, line in ipairs(WT.SourceLines(e)) do t:AddLine(line, 1, 1, 1, true) end
	ns.KeyHints(t, L["Enter: show in What's Training    Shift+Enter: list who teaches it, the nearest first"], DIM[1], DIM[2], DIM[3], true)
end

----------------------------------------------------------------------
-- What's Training's window, on a spell
----------------------------------------------------------------------

local function Window() return rawget(_G, "WhatsTrainingFloatingFrame") end
WT.Window = Window

--- The window's row showing this spell, while it shows it.
local function RowFor(f, e)
	for _, row in ipairs(type(f.rows) == "table" and f.rows or {}) do
		local s = rawget(row, "currentSpell")
		if type(s) == "table" and (s.id == e.wtId or (e.itemID and s.itemId == e.itemID)) and row.IsVisible and row:IsVisible() then
			return row
		end
	end
end
WT.RowFor = RowFor

WT.FILTER_AFTER, WT.TOGGLE_AFTER = 2, 5 -- (looks before its search is set to the spell, before the other view is tried)

--- What's Training's window on this row's spell, pointing at it: opened (/wt) when it isn't up; the spell not on show,
--- its search set to the spell's name (what you'd type there), then its other view (spells or weapon skills).
function WT.Open(e)
	local f = Window()
	if not (f and f:IsShown()) then
		local slash = _G.SlashCmdList and _G.SlashCmdList.WHATSTRAINING
		if type(slash) ~= "function" then
			ns:Print(L["What's Training's window isn't ready yet."])
			return
		end
		local ok, err = pcall(slash, "")
		if not ok then ns:Trace("training: /wt failed: " .. tostring(err)) end
		f = Window()
	end
	if not (f and f:IsShown()) then
		ns:Print(L["What's Training's window didn't open."])
		return
	end
	local tries, filtered, toggled = 0, false, false
	H:When(function()
		local w = Window()
		if not (w and w:IsShown()) then return false end
		local row = RowFor(w, e)
		if row then return row end
		tries = tries + 1
		if tries >= WT.FILTER_AFTER and not filtered then
			filtered = true
			local box = rawget(w, "searchBox")
			if box and box.SetText then pcall(box.SetText, box, Lower(tostring(e.spellName or e.name))) end
		elseif tries >= WT.TOGGLE_AFTER and not toggled then
			toggled = true
			local b = rawget(w, "weaponSkillToggleButton")
			if b and b.Click and b.IsShown and b:IsShown() then pcall(b.Click, b) end
		end
		return nil
	end, function(row) H:Show(row) end, 30, function()
		ns:Trace("training: nothing to point at for " .. tostring(e.name))
	end)
	ns:Trace("training: opened What's Training on " .. tostring(e.name))
end

local function OpenRow(e) WT.Open(e) end
--- Shift+Enter: who teaches it, the nearest first ("where to learn <it>": Search/WhatsTraining.lua's > learn); Enter on
--- one of them shows it on the map (0.53.9, the player: "an option to pinpoint the NPC that does the training").
--- Shift+Left comes back.
local function WhoTeaches(e)
	local P, UI = ns.Pipes, ns.UI
	if not (P and P.Phrase and UI and UI.WalkTo) then return end
	UI:WalkTo(P.Phrase(tostring(e.name), "learn"), e)
end
WT.WhoTeaches = WhoTeaches

----------------------------------------------------------------------
-- The list
----------------------------------------------------------------------

--- A row for one of the API's spells, or nil for a known one.
function WT.Row(api, s)
	if type(s) ~= "table" or s.id == nil or type(s.name) ~= "string" or s.name == "" then return nil end
	local st = StateOf(api, s.status)
	if not st then return nil end
	local rank = Str(s.subText)
	local e = {
		kind = "training", -- (a known weapon skill's too, which no list collects: WT.Known)
		key = s.id, wtId = s.id, spellName = s.name, rank = rank,
		name = rank and (s.name .. " (" .. rank .. ")") or s.name,
		state = st[1], weapon = st[2] or nil, pet = st[3] or nil, status = s.status,
		level = Num(s.level), cost = Num(s.cost) or 0, baseCost = Num(s.baseCost),
		quest = s.quest == true or nil, isItem = s.isItem == true or nil, itemID = s.isItem and Num(s.itemId) or nil,
		requiredIds = type(s.requiredIds) == "table" and s.requiredIds or nil, requiredTalentId = Num(s.requiredTalentId),
		link = Str(s.link), icon = s.icon or ICON,
		activate = OpenRow, tooltip = Tooltip, secondary = WhoTeaches, secondaryStaysOpen = true, shareLink = ShareText,
	}
	e.color = HEX[e.state]
	e.detail = Detail(e)
	local src = SourceKind(e)
	e.text = table.concat({ "train training trainable", WORDS[e.state], e.weapon and "weapon skill" or "",
		e.pet and "pet" or "", src == "quest" and "quest" or "", src == "item" and "book tome grimoire" or "",
		rank and Lower(rank) or "", e.level and ("level " .. e.level) or "" }, " ")
	return e
end

--- @training's rows: what you've still to learn, What's Training's order (learn now first; then by level and name).
--- The weapon skills you know are kept apart (WT.Known): not listed, but a chain starts from them ("daggers > learn").
local known = {}
function WT.Known() return known end
function WT.Collect()
	known = {}
	local api = WT.Api()
	if not api then return {} end
	local ok, spells = pcall(api.GetSpells)
	if not (ok and type(spells) == "table") then return {} end
	local rows = {}
	for _, s in ipairs(spells) do
		local e = WT.Row(api, s)
		if e and e.state == "known" then known[#known + 1] = e
		elseif e then rows[#rows + 1] = e end
	end
	table.sort(rows, function(a, b)
		if a.state ~= b.state then return ORDER[a.state] < ORDER[b.state] end
		if (a.weapon == true) ~= (b.weapon == true) then return not a.weapon end -- (spells, then weapon skills)
		if a.level ~= b.level then return (a.level or 0) < (b.level or 0) end
		return a.name < b.name
	end)
	ns.RankInOrder(rows)
	return rows
end

--- Is the API's list ready (its login reading done)?
function WT.Ready()
	local api = WT.Api()
	if not api then return false end
	local ok, yes = pcall(api.IsReady)
	return ok and yes == true
end

local list -- (the last collect's rows)

----------------------------------------------------------------------
-- Setup (at login, with the other integrations: Setup.lua)
----------------------------------------------------------------------

local function Changed() ns:Changed("training") end
--- ClassReady: a class's names, rank texts and links came in (WT_API.LoadClass): every class's spells read again.
local function ClassReady()
	local CS = ns.ClassSpells
	if CS then CS.Forget(); CS.ForgetRows() end
	ns:Changed("classspells")
end
WT.ClassReady = ClassReady
WT.CALLBACKS = { "READY", "SPELLS_CHANGED", "LEVEL_CHANGED", "IGNORED_CHANGED" }

local function SetupWhatsTraining()
	local api = WT.Api()
	if training.on or not api then return end
	training.on = true
	ns:RegisterProvider("training", {
		label = L["Training"],
		color = "ff82c5ff", -- (What's Training's "coming soon" blue)
		aliases = { "training", "train", "trainable", "whatstraining" },
		guard = 1,
		-- nothing yet: What's Training still reading your spells, or nothing left to learn
		leadRow = ns.EmptyLead(function()
			return WT.Ready() and L["Nothing left to train: What's Training has every spell as known"]
				or L["What's Training is still reading your spells: a moment"]
		end, function() return not (list and #list > 0) end),
		collect = function()
			if not WT.Api() then list = {} return list end -- (What's Training went away: no stale rows)
			list = WT.Collect()
			return list
		end,
	})
	-- (its callbacks: the list made again when a spell's status changes, you level, or ignore one; Ready: the first list)
	for _, k in ipairs(WT.CALLBACKS) do
		local ok, ev = pcall(function() return api.Event[k] end)
		if ok and type(ev) == "string" then
			local okR, err = pcall(api.RegisterCallback, WT, ev, Changed)
			if not okR then ns:Trace("training: callback " .. ev .. " failed: " .. tostring(err)) end
		end
	end
	-- (every class's spells, its catalog: their names, once What's Training has loaded them)
	local ok, ev = pcall(function() return api.Event.CLASS_READY end)
	if ok and type(ev) == "string" then
		local okR, err = pcall(api.RegisterCallback, WT, ev, ClassReady)
		if not okR then ns:Trace("training: callback " .. ev .. " failed: " .. tostring(err)) end
	end
end
I._.SetupWhatsTraining = SetupWhatsTraining

--- .integrations' line about What's Training.
function WT.Status()
	if training.on then
		local p = ns.providers.training
		local rows = p and ns:GetEntries(p) or {}
		local left, now = 0, 0
		for _, e in ipairs(rows) do
			if e.state ~= "ignored" then left = left + 1 end
			if e.state == "now" then now = now + 1 end
		end
		return L["found (%s). %d spells to learn, %d now"]:format(AddOnVersion(WT.ADDON), left, now)
	end
	if Loaded() then return L["found (%s), without the API Terminal reads: update What's Training"]:format(AddOnVersion(WT.ADDON)) end
	return L["not found"]
end
