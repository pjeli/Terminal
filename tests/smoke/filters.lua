-- Filters: quest/bound/BoE items, ready and passive spells, capped currencies, reputation standing,
-- achievements done/todo, and Questie vendors (sells:).
local T = ...
local ns, UI, check, names = T.ns, T.UI, T.check, T.names
local F = ns.Filters
local function P(w) local f = F.Parse(w); assert(f, "not a filter: " .. w); return f end

do -- items: is:quest, is:soulbound, is:boe
	F.ClearCache()
	local base = { info = C_Item.GetItemInfo, instant = C_Item.GetItemInfoInstant, slots = C_Container.GetContainerNumSlots,
		get = C_Container.GetContainerItemInfo, isBound = C_Item.IsBound, loc = _G.ItemLocation,
		link = _G.GetInventoryItemLink, slotInfo = _G.GetInventorySlotInfo }
	-- name, link, quality, ilvl, minLevel, type, subType, stack, equipLoc, texture, price, class, subclass, bindType
	local ITEMS = {
		[300] = { "Gnoll Paw", "|Hitem:300|h", 1, 5, 0, "Quest", "Quest", 20, "", 1, 0, 12, 0, 4 },
		[301] = { "Silver Ring", "|Hitem:301|h", 2, 20, 15, "Armor", "Miscellaneous", 1, "INVTYPE_FINGER", 1, 0, 4, 0, 2 },
		[302] = { "Wolf Cloak", "|Hitem:302|h", 2, 20, 15, "Armor", "Cloth", 1, "INVTYPE_CLOAK", 1, 0, 4, 1, 1 },
		[303] = { "Linen Cloth", "|Hitem:303|h", 1, 5, 0, "Trade Goods", "Cloth", 20, "", 1, 0, 7, 5, 0 },
		[304] = { "Bronze Band", "|Hitem:304|h", 2, 22, 17, "Armor", "Miscellaneous", 1, "INVTYPE_FINGER", 1, 0, 4, 0, 2 },
	}
	C_Item.GetItemInfo = function(id)
		if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
		local t = ITEMS[id]; if t then return unpack(t) end
	end
	C_Item.GetItemInfoInstant = function(x)
		local id = type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))
		local t = ITEMS[id]
		if t then return id, t[6], t[7], t[9], 1, t[12], t[13] end
		return base.instant(x)
	end
	-- rows as they come
	check(P("is:quest")({ itemID = 303, questID = 9 }) and P("is:quest")({ itemID = 303, questItem = true }), "is:quest: an item tied to a quest")
	check(P("is:quest")({ itemID = 300 }) and not P("is:quest")({ itemID = 303 }), "is:quest: a quest-class item; trade goods aren't")
	check(not P("is:quest")({ kind = "quests", questID = 9 }), "is:quest: a quest itself isn't a quest item")
	check(P("is:soulbound")({ itemID = 302, bound = true }) and not P("is:soulbound")({ itemID = 302, unbound = true })
		and not P("is:soulbound")({ itemID = 302 }), "is:soulbound: a bound stack (rows that can't say: left out)")
	check(P("is:boe")({ itemID = 301, unbound = true }) and not P("is:boe")({ itemID = 301, bound = true })
		and P("is:boe")({ itemID = 301, bound = true, unbound = true }), "is:boe: bind on equip with a stack not bound yet")
	check(P("is:boe")({ itemID = 301, detail = "Hogger  Elwynn" }) and not P("is:boe")({ itemID = 302 }), "is:boe: a loot row by the item's bind type")
	check(P("is:boe")({ recipeID = 50, makesItem = 301 }), "is:boe: what a recipe makes")
	-- from your bags: one row per item, bound / unbound per stack
	local BAG = {
		{ itemID = 301, itemName = "Silver Ring", iconFileID = 1, stackCount = 1, quality = 2, hyperlink = "|Hitem:301|h[Silver Ring]|h", isBound = false },
		{ itemID = 302, itemName = "Wolf Cloak", iconFileID = 1, stackCount = 1, quality = 2, hyperlink = "|Hitem:302|h[Wolf Cloak]|h", isBound = true },
		{ itemID = 300, itemName = "Gnoll Paw", iconFileID = 1, stackCount = 3, quality = 1, hyperlink = "|Hitem:300|h[Gnoll Paw]|h", isBound = true },
		{ itemID = 303, itemName = "Linen Cloth", iconFileID = 1, stackCount = 20, quality = 1, hyperlink = "|Hitem:303|h[Linen Cloth]|h", isBound = false },
		{ itemID = 301, itemName = "Silver Ring", iconFileID = 1, stackCount = 1, quality = 2, hyperlink = "|Hitem:301|h[Silver Ring]|h", isBound = true },
	}
	C_Container.GetContainerNumSlots = function(b) return b == 0 and #BAG or 0 end
	C_Container.GetContainerItemInfo = function(b, s) return b == 0 and BAG[s] or nil end
	-- worn: the game says whether it's bound
	_G.GetInventorySlotInfo = function(n) return n == "Finger0Slot" and 11 or nil end
	_G.GetInventoryItemLink = function(_, slot) if slot == 11 then return "|Hitem:304|h[Bronze Band]|h" end end
	local wornBound = false
	_G.ItemLocation = { CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end }
	C_Item.IsBound = function(loc) return loc.slot == 11 and wornBound end
	ns.providers.items._dirty = true
	local rows = ns:GetEntries(ns.providers.items)
	local ring
	for _, e in ipairs(rows) do if e.itemID == 301 and not e.slotId then ring = e end end
	check(ring and ring.bound and ring.unbound, "a merged row: bound and unbound when its stacks differ")
	local found = names(UI:Search("@item is:soulbound"))
	check(found["Wolf Cloak"] and found["Gnoll Paw"] and found["Silver Ring"] and not found["Linen Cloth"] and not found["Bronze Band"],
		"@item is:soulbound: bound stacks in your bags (the worn band isn't, the game says)")
	found = names(UI:Search("@item is:boe"))
	check(found["Silver Ring"] and found["Bronze Band"] and not found["Wolf Cloak"] and not found["Gnoll Paw"], "@item is:boe: bind on equip, not bound yet")
	found = names(UI:Search("@item is:quest"))
	check(found["Gnoll Paw"] and not found["Silver Ring"] and not found["Linen Cloth"], "@item is:quest")
	wornBound = true
	ns.providers.items._dirty = true
	found = names(UI:Search("@item is:boe"))
	check(not found["Bronze Band"] and names(UI:Search("@item is:soulbound"))["Bronze Band"], "a worn piece the game says is bound: soulbound, not BoE")
	C_Item.IsBound = nil
	ns.providers.items._dirty = true
	check(names(UI:Search("@item is:soulbound"))["Bronze Band"], "no answer from the game: worn counts as bound")
	found = names(UI:Search("@gear is:boe"))
	check(found["Silver Ring"] and not found["Wolf Cloak"], "@gear keeps the binding (copies of the item rows)")
	-- negation and OR (0.42.7)
	found = names(UI:Search("@item -is:soulbound"))
	check(found["Linen Cloth"] and not found["Wolf Cloak"] and not found["Gnoll Paw"], "-is:soulbound: not bound")
	found = names(UI:Search("@item !is:quest"))
	check(found["Linen Cloth"] and found["Wolf Cloak"] and not found["Gnoll Paw"], "!is:quest: the same as -")
	found = names(UI:Search("@item is:quest|is:boe"))
	check(found["Gnoll Paw"] and found["Silver Ring"] and not found["Wolf Cloak"] and not found["Linen Cloth"], "is:quest|is:boe: either")
	found = names(UI:Search("@item is:quest|boe"))
	check(found["Gnoll Paw"] and found["Silver Ring"] and not found["Wolf Cloak"], "is:quest|boe: a part with no key takes the first key")
	found = names(UI:Search("@item cloak|linen"))
	check(found["Wolf Cloak"] and found["Linen Cloth"] and not found["Gnoll Paw"] and not found["Silver Ring"], "cloak|linen: either word")
	found = names(UI:Search("@item -cloth"))
	check(not found["Linen Cloth"] and found["Gnoll Paw"] and found["Silver Ring"], "-cloth: not with the word (name or text)")
	found = names(UI:Search("@item -is:quest|is:boe"))
	check(found["Wolf Cloak"] and found["Linen Cloth"] and not found["Gnoll Paw"] and not found["Silver Ring"], "-a|b: neither")
	check(F.Parse("cloak") == nil and F.Parse("-30") == nil and F.Parse("-") == nil and F.Parse("is:nope|is:boe") == nil,
		"a plain word, a range, a lone dash and a bad part stay search words")
	check(F.Parse("q:rare|") ~= nil, "q:rare| (the next part still being typed) is q:rare")
	local seg = UI:SyntaxSegments("@item -is:boe q:rare|epic")
	local filt = seg[3][3]
	check(seg[5][3] == filt and seg[3][3] ~= seg[1][3], "-key:value and a|b are coloured as filters")
	-- Simple mode: "or" / "not" in words
	local E = ns.Easy
	local w = E.JoinLogic({ "rare", "sword", "or", "axe", "not", "boe" })
	check(#w == 3 and w[2] == "sword|axe" and w[3] == "-boe", "JoinLogic: sword or axe, not boe")
	w = E.JoinLogic({ "not" })
	check(#w == 1 and w[1] == "not", "JoinLogic: a lone not stays a word")
	check(E.IsAdvancedWord("-q:poor") and E.IsAdvancedWord("boe|q:epic") and not E.IsAdvancedWord("-boe")
		and not E.IsAdvancedWord("sword|axe"), "Simple refuses key:value in - and | words, takes plain ones")
	check(E.ToAdvanced("rare sword or axe not boe") == "type:sword|type:axe -is:boe q:rare "
		or E.ToAdvanced("rare sword or axe not boe"):find("type:sword|type:axe", 1, true) and E.ToAdvanced("rare sword or axe not boe"):find("-is:boe", 1, true),
		"Alt+`: or / not become | and - filters (" .. E.ToAdvanced("rare sword or axe not boe") .. ")")
	found = names(UI:Search("@item is:boe|cloak"))
	check(found["Silver Ring"] and found["Wolf Cloak"] and not found["Gnoll Paw"], "is:boe|cloak: a plain part among filters")
	w = E.JoinLogic({ "rare", "sword", "or", "rare", "axe" })
	check(#w == 1 and w[1] == "rare&sword|rare&axe", "JoinLogic: rare sword or rare axe = two whole sides (" .. table.concat(w, " ") .. ")")
	w = E.JoinLogic({ "cheap", "rare", "sword", "or", "epic", "axe", "or", "blue", "mace" })
	check(#w == 2 and w[1] == "cheap" and w[2] == "rare&sword|epic&axe|blue&mace", "JoinLogic: a chain of two-word sides (" .. table.concat(w, " ") .. ")")
	w = E.JoinLogic({ "sword", "or", "not", "boe" })
	check(#w == 1 and w[1] == "sword|-boe", "JoinLogic: sword or not boe")
	check(E.ToAdvanced("rare sword or rare axe"):find("q:rare&type:sword|q:rare&type:axe", 1, true),
		"Alt+`: rare sword or rare axe (" .. E.ToAdvanced("rare sword or rare axe") .. ")")
	found = names(UI:Search("@item is:quest&gnoll|is:boe&silver"))
	check(found["Gnoll Paw"] and found["Silver Ring"] and not found["Bronze Band"] and not found["Wolf Cloak"], "a&b|c&d: both halves of either side")
	found = names(UI:Search("@item cloak|-is:soulbound"))
	check(found["Wolf Cloak"] and found["Linen Cloth"] and not found["Gnoll Paw"], "a piece's own -")
	ns.db.easyMode = nil
	found = names(UI:Search("cloak or gnoll"))
	check(found["Wolf Cloak"] and found["Gnoll Paw"] and not found["Linen Cloth"], "Simple: cloak or gnoll")
	found = names(UI:Search("ring without boe"))
	check(not found["Silver Ring"] and found["Bronze Band"], "Simple: ring without boe (the worn band counts as bound here)")
	found = names(UI:Search("cloth not linen"))
	check(found["Wolf Cloak"] and not found["Linen Cloth"], "Simple: cloth not linen (the cloak is cloth)")
	found = names(UI:Search("bound cloak or quest paw"))
	check(found["Wolf Cloak"] and found["Gnoll Paw"] and not found["Silver Ring"], "Simple: two whole sides of an or")
	found = names(UI:Search("boe ring or boe cloak"))
	check(found["Silver Ring"] and not found["Wolf Cloak"], "Simple: boe ring or boe cloak keeps boe on both sides (the cloak is bound)")
	ns.db.easyMode = false
	C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.IsBound, _G.ItemLocation = base.info, base.instant, base.isBound, base.loc
	C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = base.slots, base.get
	_G.GetInventoryItemLink, _G.GetInventorySlotInfo = base.link, base.slotInfo
	ns.providers.items._dirty = true
	if ns.providers.gear then ns.providers.gear._dirty = true end
	F.ClearCache()
end

do -- spells: is:ready (off cooldown, the GCD doesn't count), is:passive
	F.ClearCache()
	local baseCD, baseGCD, baseGT = C_Spell.GetSpellCooldown, _G.GetSpellCooldown, _G.GetTime
	local now = 1000
	_G.GetTime = function() return now end
	local CD = { [1] = { startTime = 0, duration = 0, isEnabled = true }, [2] = { startTime = 990, duration = 30, isEnabled = true },
		[3] = { startTime = 999.5, duration = 1.5, isEnabled = true }, [4] = { startTime = 950, duration = 30, isEnabled = true },
		[5] = { startTime = 0, duration = 0, isEnabled = false } }
	C_Spell.GetSpellCooldown = function(id) return CD[id] end
	local function sp(id, passive) return { kind = "spells", spellID = id, passive = passive } end
	check(P("is:ready")(sp(1)) and not P("is:ready")(sp(2)), "is:ready: off cooldown / on cooldown")
	check(P("is:ready")(sp(3)) and P("is:ready")(sp(4)), "is:ready: the global cooldown doesn't count; a cooldown run out does")
	check(not P("is:ready")(sp(5)) and not P("is:ready")(sp(1, true)), "is:ready: waiting to start, and passives, aren't ready")
	_G.issecretvalue = function(v) return v == "SECRET" end
	CD[6] = { startTime = "SECRET", duration = "SECRET", isEnabled = true }
	check(not P("is:ready")(sp(6)), "is:ready: a secret cooldown can't be judged")
	_G.issecretvalue = nil
	C_Spell.GetSpellCooldown = nil
	_G.GetSpellCooldown = function(id) if id == 1 then return 0, 0, 1 end return 990, 30, 1 end
	check(P("is:ready")(sp(1)) and not P("is:ready")(sp(2)), "is:ready: the older GetSpellCooldown too")
	local baseReady = C_QuestLog.ReadyForTurnIn
	C_QuestLog.ReadyForTurnIn = function(id) return id == 7 end
	check(P("is:ready")({ kind = "quests", questID = 7 }) and not P("is:ready")({ kind = "quests", questID = 8 }), "is:ready on quests: ready to turn in")
	C_QuestLog.ReadyForTurnIn = baseReady
	check(P("is:passive")(sp(1, true)) and not P("is:passive")(sp(1, false)) and not P("is:passive")({ passive = true }), "is:passive: passive spells")
	-- in a search
	local spells = ns.providers.spells
	local save = spells._entries
	local list = { { name = "Fireball", spellID = 1 }, { name = "Fire Blast", spellID = 2 }, { name = "Fire Mastery", spellID = 9, passive = true } }
	for _, e in ipairs(list) do e.kind = "spells"; e.kindLabel = "Spell"; e._lname = ns.Lower(e.name); e.key = e.name; e.freqKey = "spells:" .. e.name end
	spells._entries, spells._dirty = list, false
	_G.GetSpellCooldown = nil
	C_Spell.GetSpellCooldown = function(id) return CD[id] or { startTime = 0, duration = 0, isEnabled = true } end
	local found = names(UI:Search("@spell fire is:ready"))
	check(found["Fireball"] and not found["Fire Blast"] and not found["Fire Mastery"], "@spell fire is:ready")
	found = names(UI:Search("@spell fire is:passive"))
	check(found["Fire Mastery"] and not found["Fireball"], "@spell fire is:passive")
	spells._entries, spells._dirty = save, true
	C_Spell.GetSpellCooldown, _G.GetSpellCooldown, _G.GetTime = baseCD, baseGCD, baseGT
end

do -- currencies: is:capped
	F.ClearCache()
	local function cur(t) t.kind = "currency"; return t end
	check(P("is:capped")(cur({ quantity = 2000, maxQuantity = 2000 })) and not P("is:capped")(cur({ quantity = 10, maxQuantity = 2000 })), "is:capped: at the cap")
	check(not P("is:capped")(cur({ quantity = 500, maxQuantity = 0 })) and not P("is:capped")(cur({ quantity = 500 })), "is:capped: uncapped currencies never are")
	check(P("is:capped")(cur({ quantity = 100, maxQuantity = 0, quantityEarnedThisWeek = 50, maxWeeklyQuantity = 50 })), "is:capped: this week's cap reached")
	check(not P("is:capped")({ quantity = 5, maxQuantity = 5 }), "is:capped: only currencies")
	check(P("is:maxed")(cur({ quantity = 5, maxQuantity = 5 })), "is:maxed = is:capped")
end

do -- reputation: standing:
	F.ClearCache()
	local function rep(n) return { kind = "reputation", reaction = n } end
	check(P("standing:honored")(rep(6)) and not P("standing:honored")(rep(5)), "standing:honored")
	check(P("standing:honored+")(rep(8)) and P("standing:honored+")(rep(6)) and not P("standing:honored+")(rep(5)), "standing:honored+: honored or better")
	check(P("standing:<friendly")(rep(4)) and not P("standing:<friendly")(rep(5)), "standing:<friendly")
	check(P("standing:4-6")(rep(5)) and not P("standing:4-6")(rep(7)) and P("standing:friendly-revered")(rep(7)), "standing:4-6 and name ranges")
	check(F.Parse("standing:pals") == nil, "an unknown standing stays text")
	check(not P("standing:neutral")({ kind = "reputation", standing = "Good Friend" }) and not P("standing:4")({ reaction = 4 }),
		"factions without a standing (friendship, renown) and other rows are left out")
	-- the game's own names (another language)
	_G.FACTION_STANDING_LABEL6 = "Ehrfürchtig"
	F.ClearCache()
	check(P("standing:ehrfürchtig+")(rep(7)) and P("standing:honored")(rep(6)), "the game's own standing names, and English still")
	_G.FACTION_STANDING_LABEL6 = nil
	F.ClearCache()
	-- rows from the provider carry reaction
	local baseC, baseGT, baseFI, baseN = _G.C_Reputation, _G.GetText, _G.GetFactionInfo, _G.GetNumFactions
	_G.C_Reputation = {
		GetNumFactions = function() return 3 end,
		GetFactionDataByIndex = function(i)
			return ({ { name = "Stormwind", factionID = 72, reaction = 6, currentReactionThreshold = 9000, nextReactionThreshold = 21000, currentStanding = 12000 },
				{ name = "Darnassus", factionID = 69, reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 3000, currentStanding = 100 },
				{ name = "Valdrakken Accord", factionID = 2510, reaction = 4 } })[i]
		end,
		IsMajorFaction = function(id) return id == 2510 end,
	}
	ns.providers.reputation._dirty = true
	local byName = {}
	for _, e in ipairs(ns:GetEntries(ns.providers.reputation)) do byName[e.name] = e end
	check(byName.Stormwind and byName.Stormwind.reaction == 6 and byName.Darnassus.reaction == 4, "reputation rows carry their standing as a number")
	check(byName["Valdrakken Accord"] and byName["Valdrakken Accord"].reaction == nil, "renown factions have none")
	local found = names(UI:Search("@rep standing:honored+"))
	check(found.Stormwind and not found.Darnassus and not found["Valdrakken Accord"], "@rep standing:honored+")
	_G.C_Reputation, _G.GetText, _G.GetFactionInfo, _G.GetNumFactions = baseC, baseGT, baseFI, baseN
	ns.providers.reputation._dirty = true
end

do -- achievements: is:done / is:todo
	F.ClearCache()
	check(P("is:done")({ kind = "achievements", completed = true }) and not P("is:done")({ kind = "achievements", completed = false }), "is:done: completed achievements")
	check(P("is:todo")({ kind = "achievements", completed = false, progress = "3/10" }) and not P("is:todo")({ kind = "achievements", completed = true }), "is:todo: achievements not done")
	check(not P("is:done")({ kind = "achievements" }) and not P("is:todo")({ kind = "achievements" }), "achievements that don't say: left out")
	check(not P("is:done")({ completed = true }), "only achievement rows by completed")
end

do -- @npc sells:<item>: Questie's vendors per item
	F.ClearCache()
	local baseQ, baseL, baseLib, baseNF = _G.Questie, _G.QuestieLoader, _G.LibQuestieDB, ns.Integrations.NpcField
	local ITEMS = { [2320] = { name = "Coarse Thread", vendors = { 1, 2 } }, [6256] = { name = "Fishing Pole", vendors = { 3 } },
		[2901] = { name = "Mining Pick", vendors = { 2 } }, [6365] = { name = "Strong Fishing Pole", vendors = { 4 } },
		[7005] = { name = "Skinning Knife" } }
	local reads = 0
	local DB = { QueryItemSingle = function(id, f) reads = reads + 1; return ITEMS[id] and ITEMS[id][f] end, QueryNPCSingle = function() end }
	_G.Questie = { API = { isReady = true } }
	_G.QuestieLoader = { ImportModule = function(_, n) return n == "QuestieDB" and DB or nil end }
	_G.LibQuestieDB = { Item = { GetAllIds = function() return { 2320, 2901, 6256, 6365, 7005 } end } }
	local function npc(id) return { kind = "npc", key = id } end
	check(P("sells:coarse_thread")(npc(1)) and P("sells:coarse_thread")(npc(2)) and not P("sells:coarse_thread")(npc(3)), "sells:coarse_thread: its vendors")
	check(P("sells:fishing_pole")(npc(3)) and not P("sells:fishing_pole")(npc(4)), "sells: an exact name wins over longer ones")
	check(P("sells:pick")(npc(2)) and not P("sells:pick")(npc(1)), "sells: part of a name")
	check(P("sells:6365")(npc(4)) and not P("sells:6365")(npc(3)), "sells: by item id")
	check(not P("sells:nothing_like_it")(npc(1)) and not P("sells:skinning_knife")(npc(1)), "an unknown item, or one nobody sells: no NPC")
	check(not P("sells:coarse_thread")({ name = "not an NPC" }), "only NPC rows")
	local before = reads
	local f = P("sells:coarse_thread")
	for i = 1, 50 do f(npc(i)) end
	check(reads == before, "worked out once per value, not per row: " .. (reads - before) .. " reads")
	-- your own items by name: no scan of Questie's names
	F.ClearCache()
	local items = ns.providers.items
	local saveE = items._entries
	items._entries = { { itemID = 2901, name = "Mining Pick" } }
	reads = 0
	check(P("sells:mining_pick")(npc(2)) and reads == 1, "an item you carry: found by its name, only its vendors read (" .. reads .. ")")
	items._entries = saveE
	-- Questie not there: nothing passes, and it's asked again later
	F.ClearCache()
	_G.Questie = nil
	check(not P("sells:coarse_thread")(npc(1)), "no Questie: nothing passes")
	_G.Questie = { API = { isReady = true } }
	check(P("sells:coarse_thread")(npc(1)), "and once Questie is ready it does")
	check(F.Parse("sells:") == nil, "sells: needs a value")
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB, ns.Integrations.NpcField = baseQ, baseL, baseLib, baseNF
	F.ClearCache()
end

do -- Tab values and .filters
	local has = {}
	for _, v in ipairs(F.VALUES.is) do has[v] = true end
	check(has.quest and has.soulbound and has.boe and has.ready and has.passive and has.capped, "Tab offers the new is: values")
	check(#F.VALUES.standing == 8 and F.VALUES.standing[6] == "honored", "Tab offers the eight standings")
	local help = {}
	for _, h in ipairs(F.HELP) do help[#help + 1] = h[1] .. " " .. h[2] end
	help = table.concat(help, "\n")
	check(help:find("standing:", 1, true) and help:find("sells:", 1, true) and help:find("soulbound", 1, true) and help:find("capped", 1, true)
		and help:find("passive", 1, true), ".filters tells of them")
	UI:Open("@rep standing:hon"); check(UI:AcceptCompletion() and UI.edit:GetText() == "@rep standing:honored ", "Tab: standing:hon -> standing:honored")
	UI:Hide()
end

do -- items whose names the game hasn't loaded yet (after login): left out, asked for, listed once they arrive
	local ns, UI, check = T.ns, T.UI, T.check
	local bag = _G.C_Container
	local real = { n = bag.GetContainerNumSlots, i = bag.GetContainerItemInfo, byid = C_Item.GetItemNameByID, req = C_Item.RequestLoadItemDataByID }
	local loaded, asked = false, {}
	local slots = {
		{ itemID = 6948, itemName = "Hearthstone", iconFileID = 1, stackCount = 1, quality = 1, hyperlink = "|cnIQ1:|Hitem:6948::::::::30:1491::75:::::::|h[Hearthstone]|h|r" },
		-- as the client gives it right after login: no name yet, an empty link text
		{ itemID = 20709, iconFileID = 1, stackCount = 3, quality = 1, hyperlink = "|cnIQ1:|Hitem:20709::::::::30:1491:::::::::|h[]|h|r" },
	}
	bag.GetContainerNumSlots = function(b) return b == 0 and #slots or 0 end
	bag.GetContainerItemInfo = function(b, s) return b == 0 and slots[s] or nil end
	C_Item.GetItemNameByID = function(id) if id == 20709 and loaded then return "Rumsey Rum Light" end end
	C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
	ns.providers.items._dirty = true
	local rows = T.names(ns:GetEntries(ns.providers.items))
	local blank = false
	for _, e in ipairs(ns:GetEntries(ns.providers.items)) do if e.name == "" then blank = true end end
	check(rows.Hearthstone and not blank, "an item with no name yet makes no blank row (a row named \"\" matches no search)")
	check(asked[1] == 20709 and ns.ItemNames.wait.count == 1, "its name is asked for")
	-- the name arrives: the list is built again and it's found
	loaded = true
	slots[2].itemName, slots[2].hyperlink = "Rumsey Rum Light", "|cnIQ1:|Hitem:20709::::::::30:1491:::::::::|h[Rumsey Rum Light]|h|r"
	local f = ns.ItemNames.frame
	f.scripts.OnEvent(f, "GET_ITEM_INFO_RECEIVED", 20709, true)
	check(ns.ItemNames.wait.count == 0 and ns.providers.items._dirty, "once the name is in, the item list is built again")
	local r = UI:Search("rumsey")
	check(r[1] and r[1].name == "Rumsey Rum Light", "and the item is found: " .. tostring(r[1] and r[1].name))
	-- a name that loads already, through GetItemNameByID, needs no wait
	loaded = true
	slots[2].itemName, slots[2].hyperlink = nil, "|cnIQ1:|Hitem:20709::::::::30:1491:::::::::|h[]|h|r"
	ns.providers.items._dirty = true
	rows = T.names(ns:GetEntries(ns.providers.items))
	check(rows["Rumsey Rum Light"] and ns.ItemNames.wait.count == 0, "a name the game has (by id) is used straight away")
	bag.GetContainerNumSlots, bag.GetContainerItemInfo, C_Item.GetItemNameByID, C_Item.RequestLoadItemDataByID = real.n, real.i, real.byid, real.req
	ns.providers.items._dirty = true
end

do -- one bag slot the client answers oddly for can't drop the whole item list
	local ns, check = T.ns, T.check
	local bag = _G.C_Container
	local real = { n = bag.GetContainerNumSlots, i = bag.GetContainerItemInfo }
	local slots = {
		{ itemID = 6948, itemName = "Hearthstone", iconFileID = 1, stackCount = 1, quality = 1, hyperlink = "|Hitem:6948|h[Hearthstone]|h" },
		"boom",
		{ itemID = 1179, itemName = "Ice Cold Milk", iconFileID = 1, stackCount = 5, quality = 1, hyperlink = "|Hitem:1179|h[Ice Cold Milk]|h" },
	}
	bag.GetContainerNumSlots = function(b) return b == 0 and #slots or 0 end
	bag.GetContainerItemInfo = function(b, s)
		if b == 0 and slots[s] == "boom" then error("odd answer") end
		return b == 0 and slots[s] or nil
	end
	local mark = #T.log
	ns.providers.items._dirty = true
	local rows = T.names(ns:GetEntries(ns.providers.items))
	check(rows.Hearthstone and rows["Ice Cold Milk"] and not ns.providers.items._warned, "a slot that errors is skipped; the rest are listed")
	local traced = false
	local D = ns.Debug
	for _, r in ipairs(D and D.trace or {}) do if tostring(r.msg):find("1 failed (first: bag 0 slot 2", 1, true) then traced = true end end
	check(traced, "the failed slot is traced for .debug log")
	bag.GetContainerNumSlots, bag.GetContainerItemInfo = real.n, real.i
	ns.providers.items._dirty = true
end

do -- recipes: is:skillup (orange and yellow), is:orange/yellow/green/grey; "@profession is:skillup" searches recipes
	local api = C_TradeSkillUI
	local gri, base, ids, linked, guild, npc = api.GetRecipeInfo, api.GetBaseProfessionInfo, api.GetAllRecipeIDs, api.IsTradeSkillLinked, api.IsTradeSkillGuild, api.IsNPCCrafting
	api.GetBaseProfessionInfo = function() return { professionID = 171, professionName = "Alchemy" } end
	api.GetAllRecipeIDs = function() return { 11, 12, 13 } end
	api.IsTradeSkillLinked, api.IsTradeSkillGuild, api.IsNPCCrafting = nil, nil, nil
	local DIFF = { [11] = 0, [12] = 1, [13] = 3 } -- (Mana Well is a camp object: @camp)
	api.GetRecipeInfo = function(id)
		local i = gri(id)
		if type(i) ~= "table" then return i end
		local c = {}
		for k, v in pairs(i) do c[k] = v end
		c.relativeDifficulty = DIFF[id]
		if id == 13 then c.learned = true end
		return c
	end
	ns.Professions.Snapshot(); T.FlushAll()
	ns.providers.recipes._dirty = true
	local all = names(UI:Search("@recipe"))
	local found = names(UI:Search("@recipe is:skillup"))
	check(all["Elixir of Strength"] and all["Greater Mana Potion"], "the open profession's recipes are indexed")
	check(found["Elixir of Strength"] and not found["Greater Mana Potion"], "is:skillup: orange yes, grey no")
	found = names(UI:Search("@recipe is:grey"))
	check(found["Greater Mana Potion"] and not found["Elixir of Strength"], "is:grey")
	found = names(UI:Search("@recipe is:orange|yellow"))
	check(found["Elixir of Strength"] and not found["Greater Mana Potion"], "is:orange|yellow")
	found = names(UI:Search("@profession is:skillup"))
	check(found["Elixir of Strength"] and not found["Greater Mana Potion"], "@profession is:skillup lists the recipes")
	local e
	for _, r in ipairs(UI:Search("@recipe elixir of strength")) do if r.name == "Elixir of Strength" then e = r end end
	check(e and e.color == "|cffff8040", "recipes are coloured as the window colours them: " .. tostring(e and e.color))
	ns.db.easyMode = nil
	found = names(UI:Search("elixir skillup"))
	check(found["Elixir of Strength"], "Simple: skillup")
	found = names(UI:Search("mana skillup"))
	check(not found["Greater Mana Potion"], "Simple: skillup is strict (a grey recipe never comes back as the closest)")
	ns.db.easyMode = false
	api.GetRecipeInfo = gri
	ns.Professions.Snapshot(); T.FlushAll()
	api.GetBaseProfessionInfo, api.GetAllRecipeIDs, api.IsTradeSkillLinked, api.IsTradeSkillGuild, api.IsNPCCrafting = base, ids, linked, guild, npc
	ns.providers.recipes._dirty = true
end
