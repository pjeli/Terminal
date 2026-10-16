-- (review, 0.53.6) small fixes in the lists: a macro's #show line, .history's "|", the Quick Keybind row's text
local T = ...
local ns, check = T.ns, T.check

io.write("[review: macros, history, keybinds]\n")
do -- a macro starting with #show (any case): its first command is the detail
	local real = _G.GetMacroInfo
	_G.GetMacroInfo = function(i) if i == 1 then return "Hearth", 1, "#Show Hearthstone\n/use Hearthstone" end return real(i) end
	ns.providers.macros._dirty = true
	local hearth
	for _, e in ipairs(ns:GetEntries(ns.providers.macros)) do if e.name == "Hearth" then hearth = e end end
	_G.GetMacroInfo = real
	ns.providers.macros._dirty = true
	check(hearth and tostring(hearth.detail):find("/use Hearthstone", 1, true) and not tostring(hearth.detail):find("#Show", 1, true),
		"#Show: the macro's first command is said, not the directive: " .. tostring(hearth and hearth.detail))
end
do -- .history: a "|" typed ("linen|wool") said as "||" in chat
	local h = ns.db.history
	ns.db.history = { "linen|wool" }
	local out = ns:FindCommand("history").run("")
	ns.db.history = h
	check(out[2] and out[2]:find("linen||wool", 1, true), ".history escapes |: " .. tostring(out[2]))
end
do -- Quick Keybind Mode's row points at the button by the button's own text
	local a, b = _G.SETTINGS_QUICK_KEYBIND_BUTTON, _G.QUICK_KEYBIND_MODE
	_G.SETTINGS_QUICK_KEYBIND_BUTTON, _G.QUICK_KEYBIND_MODE = "Quick Keybind", "Quick Keybind Mode"
	ns.providers.keybinds._dirty = true
	local row = ns:GetEntries(ns.providers.keybinds)[1]
	_G.SETTINGS_QUICK_KEYBIND_BUTTON, _G.QUICK_KEYBIND_MODE = a, b
	ns.providers.keybinds._dirty = true
	check(row and row.rowText == "Quick Keybind" and row.name == "Quick Keybind Mode",
		"its row is the mode's name, pointing at the button's text: " .. tostring(row and row.rowText))
end
do -- @xp: read again on opening only once a minute has passed (alts' rested fills slowly)
	T.check(ns.providers.experience.refreshOnOpen == 60, "@xp's refresh on open: at most once a minute")
end
do -- in: on achievements: their detail (progress, points) isn't worked out per row: it never says a place
	local real, asked = _G.GetAchievementInfo, 0
	_G.GetAchievementInfo = function(...) asked = asked + 1 if real then return real(...) end end
	ns.providers.achievements._dirty = true
	local list = ns:GetEntries(ns.providers.achievements)
	asked = 0
	local f = ns.Filters.Parse("in:barrens")
	for _, e in ipairs(list) do ns.Filters.Pass(e, { f }) end
	_G.GetAchievementInfo = real
	ns.providers.achievements._dirty = true
	T.check(#list > 0 and asked == 0, ("in: over %d achievements: none read from the game for it (%d)"):format(#list, asked))
end
do -- @gear made again when a skill is learned (Plate Mail at a trainer: what you can use changes, no bag event)
	local p = ns.providers.gear
	ns:GetEntries(p)
	p._dirty = false
	T.ef.scripts.OnEvent(T.ef, "SKILL_LINES_CHANGED")
	T.FlushAll()
	T.check(p._dirty == true, "SKILL_LINES_CHANGED: @gear to be made again")
end
do -- an Item row's Enter opens your bags on where the item is now, not where it was when the list was made
	local B = ns.Bags
	local save = { open = B.Open, ids = B.BagIDs, n = C_Container.GetContainerNumSlots, info = C_Container.GetContainerItemInfo }
	local opened
	B.Open = function(bags) opened = bags return nil end
	B.BagIDs = function() return { 0, 1, 2 } end
	C_Container.GetContainerNumSlots = function() return 4 end
	C_Container.GetContainerItemInfo = function(bag, slot) if bag == 2 and slot == 3 then return { itemID = 4242 } end end
	B.Show({ itemID = 4242, name = "Moved Thing", locs = { { 1, 1 } } })
	B.Open, B.BagIDs, C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = save.open, save.ids, save.n, save.info
	T.check(opened and opened[1] == 2 and #opened == 1, "the item moved to bag 2: bag 2 opened, not bag 1: " .. tostring(opened and opened[1]))
end
do -- the items list made again (a bag changed): Questie isn't asked again what each item starts, nor each quest's needs
	local QD = ns.QuestieData
	local real = QD.DB
	local asked = { item = 0, quest = 0 }
	local fake = {
		QueryItemSingle = function() asked.item = asked.item + 1 return nil end,
		QueryQuestSingle = function() asked.quest = asked.quest + 1 return nil end,
	}
	QD.DB = function() return fake end
	ns.providers.items._dirty = true
	ns:GetEntries(ns.providers.items)
	local first = { item = asked.item, quest = asked.quest }
	asked.item, asked.quest = 0, 0
	ns.providers.items._dirty = true
	ns:GetEntries(ns.providers.items)
	QD.DB = real
	ns.providers.items._dirty = true
	T.check(first.item > 0 and asked.item == 0 and asked.quest == 0,
		("made again: Questie asked nothing again (items %d then %d, quests %d then %d)"):format(first.item, asked.item, first.quest, asked.quest))
end
do -- an item the client's own data says isn't equipment ("" slot): no GetItemInfo asked to make sure
	local inst, info = C_Item.GetItemInfoInstant, C_Item.GetItemInfo
	local asked = 0
	C_Item.GetItemInfoInstant = function(id) return 4243, "Trade Goods", "Cloth", "" end
	C_Item.GetItemInfo = function(...) asked = asked + 1 return info(...) end
	local loc = ns.ItemGear.EquipLoc({ itemID = 4243 })
	C_Item.GetItemInfoInstant, C_Item.GetItemInfo = inst, info
	T.check(loc == nil and asked == 0, "not equipment by the instant answer: GetItemInfo not asked: " .. asked)
end
do -- a damaged piece's repair cost asked once while it stays as worn (the list is made again after every loot)
	local DU = ns.Durability
	local TI = _G.C_TooltipInfo
	local asked = 0
	_G.C_TooltipInfo = { GetInventoryItem = function() asked = asked + 1 return { repairCost = 1234 } end }
	local a = DU.CostOf("|Hitem:777|h", 40, 100, 5)
	local b = DU.CostOf("|Hitem:777|h", 40, 100, 5)
	local c = DU.CostOf("|Hitem:777|h", 30, 100, 5) -- (worn more: asked again)
	_G.C_TooltipInfo = TI
	T.check(a == 1234 and b == 1234 and c == 1234 and asked == 2, "the cost asked once per wear: " .. asked)
end
do -- Baganator's bag windows: looked for again (at most once a second) while none shows, so a view made later is found
	local Roots = ns.Bags._BaganatorRoots
	local t = 1000
	local realTime = _G.GetTime
	_G.GetTime = function() return t end
	Roots(true) -- (none yet)
	local f = { GetChildren = function() end, IsShown = function() return true end }
	_G.Baganator_CategoryViewBackpackViewFrameelvui = f
	local soon = Roots()
	t = t + 1.5
	local later = Roots()
	_G.Baganator_CategoryViewBackpackViewFrameelvui = nil
	Roots(true)
	_G.GetTime = realTime
	T.check(#soon == 0 and later[1] == f, "a view made later: found once a second has passed")
end
do -- ns.NameWait (Items, Stored, Durability alike): asked twice at most, the list marked changed once in or after 10 s
	local C = _G.C_Item
	local req, byId = C.RequestLoadItemDataByID, C.GetItemNameByID
	local asked = 0
	C.RequestLoadItemDataByID = function() asked = asked + 1 end
	C.GetItemNameByID = function() return nil end
	local changed = 0
	local realChanged = ns.Changed
	ns.Changed = function(self, id) if id == "durability" then changed = changed + 1 end return realChanged(self, id) end
	local w = ns.NameWait("durability")
	local listening = {}
	w.frame.RegisterEvent = function(_, ev) listening[ev] = true end
	w.frame.UnregisterEvent = function(_, ev) listening[ev] = nil end
	T.check(w.Name(7777, "|cff|Hitem:7777|h[]|h|r") == nil and w.count == 1 and listening.GET_ITEM_INFO_RECEIVED
		and listening.ITEM_DATA_LOAD_RESULT, "a name not loaded: asked for, both events listened to")
	w.frame.scripts.OnEvent(w.frame, "GET_ITEM_INFO_RECEIVED", 1234) -- (someone else's)
	T.check(w.count == 1, "another item's event: still waiting")
	T.FlushAll() -- (10 s on: it never came)
	T.check(w.count == 0 and changed == 1 and not listening.GET_ITEM_INFO_RECEIVED, "it never came: given up after 10 s, the list made again, events dropped")
	w.Ask(7777); T.FlushAll()
	w.Ask(7777)
	T.check(asked == 2, "asked twice at most: " .. asked)
	T.check(w.Name(1, "|cff|Hitem:1|h[Linen Cloth]|h|r") == "Linen Cloth", "a link's name used at once")
	C.RequestLoadItemDataByID, C.GetItemNameByID, ns.Changed = req, byId, realChanged
end
do -- ns.HasText: a row's own text or a FontString's, exact (or starting with it); a secret text never compared
	local function FS(t) return { GetObjectType = function() return "FontString" end, GetText = function() return t end } end
	local function Row(own, ...)
		local regions = { ... }
		return { GetText = own and function() return own end or nil, GetRegions = function() return unpack(regions) end }
	end
	local was = _G.issecretvalue
	_G.issecretvalue = function(v) return v == "SECRET" end
	T.check(ns.HasText(Row(nil, FS("Swords")), "Swords") and not ns.HasText(Row(nil, FS("Swords 150/300")), "Swords")
		and ns.HasText(Row("Swords 150/300"), "Swords", true) and not ns.HasText(Row("SECRET", FS("Mace")), "SECRET")
		and ns.HasText(Row("SECRET", FS("Mace")), "Mace"), "exact, by prefix when asked, a secret skipped and the next text read")
	_G.issecretvalue = was
end

do -- (review, 0.53.6) "usable by you" is kept per character: with its surname where characters have one
	local F, name, regional, realm = T.ns.Filters, _G.UnitName, _G.RegionalUniqueNamesEnabled, _G.GetRealmName
	_G.UnitName = function() return "Plamen", "Warr" end
	_G.RegionalUniqueNamesEnabled = function() return true end
	_G.GetRealmName = function() return "Forever" end
	local a = F._MyName()
	_G.UnitName = function() return "Plamen", "Mage" end
	local b = F._MyName()
	T.check(a and b and a ~= b and a:find("Warr", 1, true), "two characters of one first name are two: " .. tostring(a) .. " / " .. tostring(b))
	_G.RegionalUniqueNamesEnabled = nil
	T.check(F._MyName() == "Plamen@Forever", "no surnames: the name and realm as before: " .. tostring(F._MyName()))
	T.check(T.ns.SurnameSeparator() == nil, "no surnames: no separator")
	_G.UnitName, _G.RegionalUniqueNamesEnabled, _G.GetRealmName = name, regional, realm
end

do -- (review, 0.53.6) the tour's card, made before .zen faded the interface, keeps its own alpha too (by name: a frame
	-- made while it's faded is kept as it's made, Zen.Made; one made earlier only by Z.OWN)
	local has = false
	for _, n in ipairs(T.ns.Zen.OWN) do if n == "TerminalTourCard" then has = true end end
	T.check(has, "the tour card is one of Terminal's own frames to .zen")
end

do -- (review, 0.53.6) where to send, said one way: SendAll with no channel says what the prompt says
	local n, why = T.ns.Share.SendAll({ { kind = "items", key = 1, name = "A" } }, {}, "linen")
	T.check(not n and why and why:find(">>> party", 1, true) and why:find("yell", 1, true) and why:find("officer", 1, true),
		"no channel: every channel named, as the prompt does: " .. tostring(why))
end

do -- (review, 0.53.6) is:upgrade reads what you wear once while it's the same; a row's lazy link isn't made for its key
	local ns, F = T.ns, T.ns.Filters
	local save = { link = _G.GetInventoryItemLink, stats = C_Item.GetItemStats, det = C_Item.GetDetailedItemLevelInfo,
		cached = C_Item.IsItemDataCachedByID }
	local worn, reads = "|cffffffff|Hitem:300::::::::|h[Helm]|h|r", 0
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return worn end end
	C_Item.GetItemStats = function(l) if tostring(l):find("item:300", 1, true) or tostring(l):find("item:301", 1, true) then reads = reads + 1 end return { ITEM_MOD_STAMINA_SHORT = 3 } end
	C_Item.GetDetailedItemLevelInfo = function() return 10, 10 end
	C_Item.IsItemDataCachedByID = function() return true end
	F.ClearCache()
	F.Parse("is:upgrade"); F.Parse("is:upgrade")
	T.check(reads == 1, "the same gear: read once for two searches: " .. reads)
	worn = "|cffffffff|Hitem:301::::::::|h[Helm]|h|r"
	F.Parse("is:upgrade")
	T.check(reads == 2, "another piece worn: read again: " .. reads)
	-- a loot row's link is made on each read: its key doesn't ask for it
	local made = 0
	local row = setmetatable({ itemID = 77 }, { __index = function(_, k) if k == "link" then made = made + 1 return "item:77" end end })
	T.check(ns.Filters._.StatKey(row) == 77 and made == 0, "the key from the row's id, its lazy link never made: " .. made)
	T.check(ns.Filters._.ItemKey(5, "|Hitem:5:0:0:0:0:0:-12|h") == "5:-12" and ns.Filters._.ItemKey(5, "item:5") == 5, "ItemKey: a random suffix kept")
	_G.GetInventoryItemLink, C_Item.GetItemStats, C_Item.GetDetailedItemLevelInfo, C_Item.IsItemDataCachedByID = save.link, save.stats, save.det, save.cached
	F.ClearCache()
end

do -- (review, 0.53.6) faction:friendly asks your faction once per search, not per row
	local F, was, asked = T.ns.Filters, _G.UnitFactionGroup, 0
	_G.UnitFactionGroup = function() asked = asked + 1 return "Horde" end
	local f = F.Parse("faction:friendly")
	local a, b = { kind = "flight", friendlyToFaction = "H" }, { kind = "flight", friendlyToFaction = "A" }
	local ra, rb = f(a), f(b)
	f(a)
	T.check(ra and not rb and asked == 1, "once per search: " .. asked)
	_G.UnitFactionGroup = was
end

do -- (review, 0.53.6) stat: on an item the client let go of since its info was kept: asked again, the search waits for it
	local F = T.ns.Filters
	local save = { info = C_Item.GetItemInfo, stats = C_Item.GetItemStats, cached = C_Item.IsItemDataCachedByID, req = C_Item.RequestLoadItemDataByID,
		instant = C_Item.GetItemInfoInstant }
	C_Item.GetItemInfoInstant = function(id) return id, "Armor", "Misc", "INVTYPE_FINGER", 1, 4, 0 end -- (armour: no effect text read)
	F.ClearCache(); F.ResetAsks()
	C_Item.GetItemInfo = function() return "Band", "|Hitem:400|h", 2, 30, 25, "Armor", "Misc", 1, "INVTYPE_FINGER" end
	C_Item.GetItemStats = function() return nil end
	local isCached, asked = true, 0
	C_Item.IsItemDataCachedByID = function() return isCached end
	C_Item.RequestLoadItemDataByID = function() asked = asked + 1 end
	local f = F.Parse("stat:stamina")
	F._.ItemInfo(400) -- (its info kept)
	isCached = false
	F.loading = false
	f({ itemID = 400 })
	T.check(F.loading == true and asked == 1, "asked again, the search told it's loading: " .. tostring(F.loading) .. " / " .. asked)
	C_Item.GetItemInfo, C_Item.GetItemStats, C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID = save.info, save.stats, save.cached, save.req
	C_Item.GetItemInfoInstant = save.instant
	F.loading = false
	F.ClearCache()
end

do -- (review, 0.53.6) slot:shirt in any language; one integration failing leaves the others to start
	local F = T.ns.Filters
	local save = { instant = C_Item.GetItemInfoInstant, body = _G.INVTYPE_BODY }
	_G.INVTYPE_BODY = "Hemd"
	C_Item.GetItemInfoInstant = function(id) return id, "Armor", "Misc", "INVTYPE_BODY", 1, 4, 0 end
	F.ClearCache()
	T.check(F.Parse("slot:shirt")({ itemID = 500, equipLoc = "INVTYPE_BODY" }), "slot:shirt finds a shirt on a German client")
	C_Item.GetItemInfoInstant, _G.INVTYPE_BODY = save.instant, save.body
	F.ClearCache()
	local I = T.ns.Integrations
	local started = {}
	local was = { a = I._.SetupAtlasLoot, q = I._.SetupQuestie, t = I._.SetupAttune }
	I._.SetupAtlasLoot = function() error("an AtlasLoot without its tables") end
	I._.SetupQuestie = function() started[#started + 1] = "Questie" end
	I._.SetupAttune = function() started[#started + 1] = "Attune" end
	local ok = pcall(I.Setup)
	T.check(ok and table.concat(started, ",") == "Questie,Attune", "AtlasLoot failing: Questie and Attune still start: " .. table.concat(started, ","))
	I._.SetupAtlasLoot, I._.SetupQuestie, I._.SetupAttune = was.a, was.q, was.t
end

do -- (review, 0.53.6) a place's filter doesn't parse in:<place> again (a second place filter inside it)
	local F, I = T.ns.Filters, T.ns.Integrations
	local parse, parsed = F.Parse, 0
	F.Parse = function(w, ...) if tostring(w):find("^in:") then parsed = parsed + 1 end return parse(w, ...) end
	local f = I.PlaceFilter({ key = "goldshire", name = "Goldshire" })
	F.Parse = parse
	T.check(parsed == 0 and f({ name = "x", _ltext = "a goldshire thing" }) and not f({ name = "y", _ltext = "elsewhere" }),
		"the place's own name tested plainly: " .. parsed)
end

do -- (review, 0.53.6) one walk over Questie's spawns: a dungeon's NPC by its entrances, other spawns as they are
	local I = T.ns.Integrations
	local seen, QD = {}, T.ns.QuestieData
	local uiWas = QD.UiMapOfArea
	QD.UiMapOfArea = function(a) return a == 12 and 1429 or nil end
	I._.EachSpot({ [12] = { { 40, 50 }, { -1, -1 }, "x" } }, function(cont, x, y, ui, c, door) seen[#seen + 1] = { c = c, door = door } end, true)
	T.check(#seen == 1 and seen[1].c[1] == 40 and not seen[1].door, "the real spawns only (no -1 spawns, nothing that isn't one): " .. #seen)
	QD.UiMapOfArea = uiWas
	local v = I.NearView({ name = "Box", zone = "Elwynn" }, 12.4, "Elwynn")
	T.check(v.name == "Box" and v._dist == 12.4 and v.nearRest == "Elwynn" and v.detail:find("Elwynn", 1, true), "a near view says how far and the rest")
end

do -- (review, 0.53.6) telling the guild: a lockdown check that errors doesn't break it (it was called unguarded)
	local was, sent = _G.C_ChatInfo, nil
	_G.C_ChatInfo = { InChatMessagingLockdown = function() error("no") end, SendChatMessage = function(t) sent = t end }
	local guild = _G.IsInGuild
	_G.IsInGuild = function() return true end
	local ok = pcall(T.ns.Extras.TellGuild, "hello")
	T.check(ok and sent == "hello", "sent, the check's error taken as no lockdown")
	_G.C_ChatInfo, _G.IsInGuild = was, guild
end

do -- (review, 0.53.6) a selected row with nothing to show: worked out once, not on every redraw
	local ns, UI = T.ns, T.ns.UI
	UI:Open("hearthstone"); T.FlushAll()
	local asked = 0
	local row = { kind = "zz", key = 1, name = "Nothing to show", getLink = function() asked = asked + 1 return nil end }
	UI.results = { row }
	UI.sel, UI.offset = 1, 0
	UI:UpdateTooltip(); UI:UpdateTooltip(); UI:UpdateTooltip()
	T.check(asked == 1, "its link asked for once: " .. asked)
	UI:ForgetTooltip()
	UI:UpdateTooltip()
	T.check(asked == 2, "drawn again once forgotten (a theme change)")
	UI:Hide(); T.FlushAll()
end

do -- (review, 0.53.6) .atop's graph: the columns already shown move over at once, only the newest glides
	local B = T.ns.Atop
	B.Open()
	local h = B.History()
	for i = 1, 48 do h[i] = (i % 5) / 10 end
	B.DrawBars(0.2)
	local g = B.graph
	T.check(g[1].shown == g[1].target and g[47].shown == g[47].target, "the older columns placed at once")
	B.Close()
end

do -- (review, 0.53.6) the row menu's backdrop set once, not on every right-click
	local ns, UI = T.ns, T.ns.UI
	UI:Open("hearthstone"); T.FlushAll()
	UI:ShowRowMenu(1)
	local m = _G.TerminalRowMenu
	local set, n = m.SetBackdrop, 0
	m.SetBackdrop = function(...) n = n + 1 return set(...) end
	UI:HideRowMenu(); UI:ShowRowMenu(1); UI:HideRowMenu(); UI:ShowRowMenu(1)
	m.SetBackdrop = set
	T.check(n == 0, "shown again: its backdrop as it was: " .. n)
	UI:HideRowMenu(); UI:Hide(); T.FlushAll()
end

do -- (review, 0.53.6) the profession spells read from the spellbook once until it changes
	local P = T.ns.Professions
	local get, asked = C_SpellBook and C_SpellBook.GetSpellBookItemInfo, 0
	if get then
		C_SpellBook.GetSpellBookItemInfo = function(...) asked = asked + 1 return get(...) end
		P.ForgetTradeSpells()
		P.TradeSpells(); local once = asked
		P.TradeSpells()
		T.check(asked == once, "read once while the spellbook is the same")
		P.tradeFrame.scripts.OnEvent(P.tradeFrame, "SPELLS_CHANGED")
		P.TradeSpells()
		T.check(once == 0 or asked > once, "read again once it changes")
		C_SpellBook.GetSpellBookItemInfo = get
	end
end

do -- (review, 0.53.6) one walk over what you wear: a slot name the client doesn't know is left out, the rest given
	local save = { info = _G.GetInventorySlotInfo, link = _G.GetInventoryItemLink }
	_G.GetInventorySlotInfo = function(n) if n == "HeadSlot" then return 1 end error("no such slot") end
	_G.GetInventoryItemLink = function(_, s) return s == 1 and "|cffffffff|Hitem:777::|h[Hat]|h|r" or nil end
	local got = {}
	for slotName, slotId, link, slotText, id in T.ns.WornSlots({ "BogusSlot", "HeadSlot" }) do got[#got + 1] = { slotName, slotId, id } end
	T.check(#got == 1 and got[1][1] == "HeadSlot" and got[1][2] == 1 and got[1][3] == 777, "the known slot with its item: " .. #got)
	_G.GetInventorySlotInfo, _G.GetInventoryItemLink = save.info, save.link
end

do -- (review, 0.53.6) the mail's auction subjects read a translation that numbers its argument ("%1$s")
	local MA = T.ns.Mail
	local was = _G.AUCTION_SOLD_MAIL_SUBJECT
	_G.AUCTION_SOLD_MAIL_SUBJECT = "Auktion erfolgreich: %1$s"
	MA.ResetSubjectsForTests()
	T.check(MA.AuctionSubject("Auktion erfolgreich: Linen Cloth") == "sold", "a numbered argument read as one")
	_G.AUCTION_SOLD_MAIL_SUBJECT = was
	MA.ResetSubjectsForTests()
end
