local ns = select(2, ...)
local L = ns.L

-- Quests and vendors by what you'd gain: "quest upgrades" (the quests near your level whose reward is an upgrade),
-- "upgrades i can buy" (friendly vendors' stock), and "quests that reward bags". What rewards what is Rewards.lua's,
-- loaded just before this (1.4.2: one file until then).

local QR = ns.QuestRewards
local Safe, Str = ns.Safe, ns.Str
local DB, QuestIdOf, QUEST, FILLER, ForYou = QR._.DB, QR._.QuestIdOf, QR._.QUEST, QR._.FILLER, QR._.ForYou

----------------------------------------------------------------------
-- Upgrades from quests: "quest upgrades", "upgrade quests", "quests with upgrades": the quests near your level you can
-- still take whose reward is an upgrade for you (is:upgrade on each reward), the biggest first, each saying what it
-- rewards and how far its giver is (with the arrow when it's selected).
----------------------------------------------------------------------

local UPG = { upgrade = true, upgrades = true }
QR.NEAR_BELOW, QR.NEAR_ABOVE = 6, 3 -- (quest levels taken: this far below yours, and above)
QR.UPGRADE_ASK = 60 -- (reward items asked of the server per answer; the answer is read again once they're in)

--- "quest upgrades" and the like (a quest word, an upgrade word, nothing else but little words): true.
function QR.UpgradeQuestion(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local quest, upg = false, false
	for w in t:gmatch("%S+") do
		if QUEST[w] then quest = true
		elseif UPG[w] then upg = true
		elseif not FILLER[w] then return nil end
	end
	return quest and upg or nil
end

local NoneRow = ns.NoteRow

--- The answer: the quests' rows, best first, and the footer's note.
function QR.UpgradeAnswer()
	local note = L["Quests whose reward is an upgrade for you"]
	local db = DB()
	local F = ns.Filters
	if not (db and F and F.GearFit) then return { NoneRow(L["Needs Questie: it knows what every quest rewards"]) }, note end
	local idx = QR.Index()
	if not idx then
		if QR.Building() then F.loading = true end -- (read again once the rewards are in: RetryWhenLoaded)
		return { NoneRow(L["Reading what Questie's quests reward: a moment"]) }, note
	end
	QR.RewardsOf(0) -- (the quests' rewards made, once)
	local me = UnitLevel and UnitLevel("player")
	me = type(me) == "number" and me > 0 and me or nil
	local fit = F.GearFit()
	local I = ns.Integrations
	local cached = C_Item and C_Item.IsItemDataCachedByID
	local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
	local asked, found = 0, {}
	for qid, items in pairs(QR.byQuest.map) do
		local ok = not (done and Safe(done, qid))
		if ok and me then
			local lvl = ns.Num(Safe(db.QueryQuestSingle, qid, "questLevel"))
			local need = ns.Num(Safe(db.QueryQuestSingle, qid, "requiredLevel"))
			if need and need > me then ok = false
			elseif lvl and lvl > 0 and (lvl < me - QR.NEAR_BELOW or lvl > me + QR.NEAR_ABOVE) then ok = false end
		end
		if ok then ok = ForYou(db, qid) end
		if ok then ok = QR.CanTakeNow(qid, me) end -- (no reward of a quest you can't pick up: QuestAccess.lua)
		if ok then
			-- (its rewards the game hasn't sent: asked for, a few, and the answer read again once they're in)
			for _, it in ipairs(items) do
				if cached and Safe(cached, it.id) == false and not (F.Known and F.Known(it.id)) and asked < QR.UPGRADE_ASK then
					asked = asked + 1
					if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, it.id) end
				end
			end
			local row = I and I.QuestRow and I.QuestRow(qid)
			if row and fit(row) then found[#found + 1] = { row = row, g = F.GainOf(row) } end
		end
	end
	if asked > 0 then F.loading = true end
	table.sort(found, function(a, b)
		if a.g.gain ~= b.g.gain then return a.g.gain > b.g.gain end
		return tostring(a.row.name) < tostring(b.row.name)
	end)
	local here = I and I.Here and I.Here()
	local rows = {}
	for i, f in ipairs(found) do
		local row = f.row
		local rest = L["Rewards %s"]:format(f.g.item or "?")
		local v = { detail = rest, _score = 1e6 - i }
		local npcID = I.QuestGiver and I.QuestGiver(row.qid or rawget(row, "key"))
		local d, w
		if type(npcID) == "number" and here and I.NpcDistance then d, w = I.NpcDistance(npcID, here) end
		-- (a giver in a dungeon: its entrance, the row saying which dungeon)
		local inside = type(npcID) == "number" and I.NpcDungeon and I.NpcDungeon(npcID)
		if inside then
			rest = rest .. ns.DETAIL_SEP .. L["giver in %s"]:format(inside)
			v.detail = rest
		end
		if d and w then
			v.detail = ns.NearDetail(d, rest)
			v._dist, v.wcont, v.wx, v.wy, v.nearRest = d, w.cont, w.x, w.y, rest
		end
		v = setmetatable(v, { __index = row })
		F.SetGain(v, f.g)
		rows[#rows + 1] = v
	end
	if #rows == 0 then
		return { NoneRow(asked > 0 and L["None yet: the rewards' details are still coming"] or L["No quest near your level rewards an upgrade for you"]) }, note
	end
	return rows, note
end


----------------------------------------------------------------------
-- Upgrades you can buy: "upgrades i can buy", "vendor upgrades": the friendly vendors whose stock (Questie's) holds a
-- clear upgrade for you, nearest first, each saying what and how much it gains, and a standing it needs (the item's own
-- tooltip says "Requires Timbermaw Hold - Honored"). Enter points at the vendor. Advanced: @npc sells:upgrade.
-- Reputation quartermasters, PvP vendors, limited-stock items, vendor blues at low levels, bags and quivers.
----------------------------------------------------------------------
local BUY = { buy = true, buyable = true, purchasable = true, purchase = true, sale = true, vendor = true, vendors = true,
	sell = true, sells = true, sold = true, merchant = true, merchants = true }
QR.VENDOR_ASK = 40 -- (vendor items asked of the server per answer; read again once they're in)
local vendorItems -- { { id = item, vendors = { npc ids } } }: equipment Questie's vendors sell (read once)
local standingOf = {} -- item id -> the standing it needs (false: none); QR.StandingNeeded
local vendorKept -- (the last judging of their stock: QR.VendorUpgrades)
--- The equipment Questie says vendors sell (read once a session: every Questie item looked at, tens of ms).
--- `mayYield`: in the search's coroutine and not under a pcall (a filter's is: a yield there is an error, "attempt to
--- yield across metamethod/C-call boundary", and the row dropped; review): spread over frames.
function QR.VendorItems(mayYield)
	if vendorItems then return vendorItems end
	local db = DB()
	if not (db and db.QueryItemSingle) then return nil end
	local started = debugprofilestop and debugprofilestop()
	local ids = db.ItemIds and db.ItemIds() or {}
	local inst = C_Item and C_Item.GetItemInfoInstant
	local SLOTS = ns.Filters and ns.Filters.SLOTS or {}
	local out = {}
	-- (in the search's coroutine: every Questie item read over several frames, not in one; review)
	local UI = ns.UI
	local slicing = mayYield and UI and UI.sliceUntil and coroutine.running() and debugprofilestop
	for i = 1, #ids do
		if slicing and i % 512 == 0 and UI.sliceUntil and debugprofilestop() > UI.sliceUntil then coroutine.yield(UI.Results()) end
		local id = ids[i]
		local okI, _, _, _, loc = false, nil, nil, nil, nil
		if inst then okI, _, _, _, loc = pcall(inst, id) end
		if not inst or (okI and type(loc) == "string" and SLOTS[loc]) then
			local v = Safe(db.QueryItemSingle, id, "vendors")
			if type(v) == "table" and #v > 0 then out[#out + 1] = { id = id, vendors = v } end
		end
	end
	vendorItems = out
	ns:Trace(("rewards: %d vendor items read%s"):format(#out, started and (" in %.0f ms"):format(debugprofilestop() - started) or ""))
	return out
end
function QR.ForgetVendorItems() vendorItems, standingOf, vendorKept = nil, {}, nil end -- (tests)

--- A standing the item needs, from its tooltip ("Requires Timbermaw Hold - Honored"): "Honored with Timbermaw Hold",
--- or nil.
local repPattern
function QR.StandingNeeded(id)
	if standingOf[id] ~= nil then return standingOf[id] or nil end
	local TI = rawget(_G, "C_TooltipInfo")
	if not (TI and TI.GetItemByID) then return nil end
	local cached = C_Item and C_Item.IsItemDataCachedByID
	if cached and Safe(cached, id) == false then return nil end
	if not repPattern then
		local fmt = Str(rawget(_G, "ITEM_REQ_REPUTATION")) or "Requires %s - %s"
		repPattern = ns.FormatPattern and ns.FormatPattern(fmt) or "^Requires (.+) %- (.+)$"
	end
	local ok, data = pcall(TI.GetItemByID, id)
	local found = false
	for _, line in ipairs(ok and type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
		local text = Str(line.leftText)
		local faction, standing
		if text then faction, standing = text:match(repPattern) end -- (not "text and ...": that keeps only the first)
		if faction and standing then found = L["%s with %s"]:format(standing, faction) break end
	end
	standingOf[id] = found
	return found or nil
end

--- The upgrades vendors sell: { [npc id] = { { id = item, g = gain } ... } } (best first), the items in it, and how many
--- items are still being asked of the server.
QR.VENDOR_KEEP = 2 -- (seconds the last judging stands: sells:upgrade's filter is made again on every keystroke)
function QR.VendorUpgrades(mayYield) -- (mayYield: as QR.VendorItems')
	local F = ns.Filters
	local items = QR.VendorItems(mayYield)
	if not (items and F and F.GearFit) then return nil end
	local now = GetTime and GetTime() or 0
	local k = vendorKept
	local key = F.FitKey and F.FitKey() or ""
	if k and k.items == items and k.key == key and now - k.at < QR.VENDOR_KEEP and k.asked == 0 then
		F.fitMade = true -- (as GearFit would say: their tooltips compare them)
		return k.by, k.n, 0
	end
	local fit = F.GearFit()
	local UI, count = ns.UI, 0
	local slicing = mayYield and UI and UI.sliceUntil and coroutine.running() and debugprofilestop
	local cached = C_Item and C_Item.IsItemDataCachedByID
	local asked, bySeller, n = 0, {}, 0
	for _, it in ipairs(items) do
		count = count + 1
		if slicing and count % 64 == 0 and UI.sliceUntil and debugprofilestop() > UI.sliceUntil then coroutine.yield(UI.Results()) end
		local probe = { kind = "vendoritem", itemID = it.id, key = it.id }
		if cached and Safe(cached, it.id) == false and not (F.Known and F.Known(it.id)) then
			if asked < QR.VENDOR_ASK then
				asked = asked + 1
				if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, it.id) end
			end
		elseif fit(probe) and not (F.GainOf(probe) or {}).byLevel then
			-- (by item levels alone, not stats: left out, as the auction house's list does; review)
			local g = F.GainOf(probe)
			n = n + 1
			for _, npc in ipairs(it.vendors) do
				if type(npc) == "number" then
					bySeller[npc] = bySeller[npc] or {}
					table.insert(bySeller[npc], { id = it.id, g = g })
				end
			end
		end
	end
	for _, list in pairs(bySeller) do table.sort(list, function(a, b) return (a.g and a.g.gain or 0) > (b.g and b.g.gain or 0) end) end
	vendorKept = { items = items, key = key, at = now, by = bySeller, n = n, asked = asked }
	return bySeller, n, asked
end

--- "upgrades i can buy", "vendor upgrades", "buyable upgrades", "upgrades for sale": true.
function QR.BuyQuestion(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local buy, upg = false, false
	for w in t:gmatch("%S+") do
		if BUY[w] then buy = true
		elseif UPG[w] then upg = true
		elseif not FILLER[w] or QUEST[w] then return nil end
	end
	return buy and upg or nil
end

--- What a vendor's row says: "Sells Thick War Axe (+12), Ironforge Breastplate (+5) · needs Honored with ...".
local function SellsDetail(list)
	local bits = {}
	for i, x in ipairs(list) do
		if i > 2 then bits[#bits + 1] = L["%d more"]:format(#list - 2) break end
		local name = C_Item and C_Item.GetItemNameByID and Str(Safe(C_Item.GetItemNameByID, x.id)) or ("#" .. x.id)
		local gain = x.g and x.g.gain and not x.g.byLevel and (" (+" .. (math.floor(x.g.gain * 10 + 0.5) / 10) .. ")") or ""
		bits[#bits + 1] = tostring(name) .. gain
	end
	local out = L["Sells %s"]:format(table.concat(bits, ", "))
	local need = list[1] and QR.StandingNeeded(list[1].id)
	if need then out = out .. ns.DETAIL_SEP .. L["needs %s"]:format(need) end
	return out
end
QR.SellsDetail = SellsDetail

--- The answer: the friendly vendors selling an upgrade, nearest first (those with no distance known after them).
function QR.BuyAnswer()
	local note = L["Vendors selling an upgrade for you"]
	local db = DB()
	if not db then return { NoneRow(L["Needs Questie: it knows what vendors sell"]) }, note end
	local bySeller, _, asked = QR.VendorUpgrades(true)
	if not bySeller then return { NoneRow(L["Needs Questie: it knows what vendors sell"]) }, note end
	if asked > 0 then ns.Filters.loading = true end
	local I, F = ns.Integrations, ns.Filters
	local friendly = F.Parse("faction:friendly")
	local here = I and I.Here and I.Here()
	local rows = {}
	for npc, list in pairs(bySeller) do
		local row = I and I.NpcRow and I.NpcRow(npc)
		if row and (not friendly or friendly(row)) then
			local rest = SellsDetail(list)
			local d = here and I.NpcDistance and I.NpcDistance(npc, here)
			local v
			if d then v = I.NearView(row, d, rest)
			else v = setmetatable({ detail = rest, _score = -(list[1].g and list[1].g.gain or 0) }, { __index = row }) end
			v.vendorUpgrades = list
			F.SetGain(v, list[1].g)
			rows[#rows + 1] = v
		end
	end
	table.sort(rows, function(a, b)
		if a._score ~= b._score then return a._score > b._score end
		return tostring(a.name) < tostring(b.name)
	end)
	if #rows == 0 then
		return { NoneRow(asked > 0 and L["None yet: the vendors' items are still coming in"] or L["No friendly vendor sells an upgrade for you"]) }, note
	end
	return rows, note
end
function QR.BuyToAdvanced() return "@npc sells:upgrade faction:friendly sort:distance " end

----------------------------------------------------------------------
-- Bags: "quests that reward bags", "bag quests", "which quests give a bag"; quivers and ammo pouches too. The quests
-- whose reward is one, that you can still take (your race and class, not done), the most slots first. A reward is a bag
-- by the item's class (the game knows it for every item at once); its slots are its tooltip's ("16 Slot Bag"), once the
-- game has the item.
----------------------------------------------------------------------

local CONTAINER, QUIVER_CLASS = 1, 11 -- (Enum.ItemClass: Container, Quiver; a quiver's subclass 2, an ammo pouch's 3)
local KIND_TEST = {
	bag = function(class) return class == CONTAINER end,
	quiver = function(class, sub) return class == QUIVER_CLASS and sub == 2 end,
	ammo = function(class, sub) return class == QUIVER_CLASS and sub == 3 end,
}
-- the words for each kind (reward:bag, "bag quests"); not "pouch", "satchel" or "sack": reward:pouch is the items named
-- so, as before 0.65.3, a Small Shot Pouch (an ammo pouch) among them (0.65.x review)
QR.KIND_WORDS = { bag = "bag", bags = "bag", container = "bag", containers = "bag", quiver = "quiver", quivers = "quiver",
	["ammo pouch"] = "ammo", ["ammo pouches"] = "ammo" }
-- the question's words too: those said in the plural ("quests that reward pouches"); one said alone is a name ("pouch
-- quest": the quests rewarding a pouch, as before)
local QUESTION_KINDS = setmetatable({ satchels = "bag", sacks = "bag", pouches = "bag" }, { __index = QR.KIND_WORDS })
-- (words saying the bags are yours, "quests in my bags": not this question)
local NOT_BAG_QUESTION = { my = true, mine = true }
local BAG_EXTRA = { big = true, bigger = true, biggest = true, large = true, larger = true, largest = true, slot = true,
	slots = true, ammo = true }

local kindCache = {} -- kind -> { idx = the index it was made from, list = { index entries } }

--- The quest rewards that are bags (or quivers, ammo pouches): index entries, each with sub (its kind's name, "Herb
--- Bag") once. Made once per index.
function QR.KindItems(kind)
	local idx = QR.Index()
	local test = KIND_TEST[kind]
	if not (idx and test) then return {} end
	local c = kindCache[kind]
	if c and c.idx == idx then return c.list end
	local get = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
	local list = {}
	for _, it in ipairs(idx) do
		local ok, _, _, sub, _, _, class, subID = false, nil, nil, nil, nil, nil, nil, nil
		if get then ok, _, _, sub, _, _, class, subID = pcall(get, it.id) end
		if ok and test(ns.Num(class), ns.Num(subID)) then
			it.sub, it.subID = Str(sub), ns.Num(subID)
			list[#list + 1] = it
		end
	end
	kindCache[kind] = { idx = idx, list = list }
	return list
end

-- a bag's slots, from its tooltip ("16 Slot Bag": the game's CONTAINER_SLOTS), kept once known
local slotsOf = {}
local slotPattern
--- How many slots a bag has (its tooltip says), or nil while the game hasn't the item (or this client can't say).
function QR.Slots(id)
	if slotsOf[id] then return slotsOf[id] end
	local TI = rawget(_G, "C_TooltipInfo")
	if not (TI and TI.GetItemByID) then return nil end
	if not slotPattern then
		local fmt = Str(rawget(_G, "CONTAINER_SLOTS")) or "%d Slot %s"
		-- (other languages: positional codes, "%1$d", and the game's plural forms, "|4ячейка:ячейки:ячеек;", read as any
		-- text; 0.65.x review)
		fmt = fmt:gsub("%%%d%$([ds])", "%%%1"):gsub("|4[^;]*;", "\1")
		slotPattern = "^" .. fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%d", "\2", 1):gsub("%%d", "\3")
			:gsub("%%s", ".+"):gsub("\1", ".-"):gsub("\2", "(%%d+)"):gsub("\3", "%%d+")
	end
	-- (an item the client hasn't loaded: no tooltip to read yet; asked for (a few per search, F.MayAsk), and read once
	-- it's in. 0.65.x review: every keystroke read 100 empty tooltips, and Advanced never asked for them)
	local cached = C_Item and C_Item.IsItemDataCachedByID
	if cached and Safe(cached, id) == false then
		local F = ns.Filters
		if F and F.MayAsk and F.MayAsk(id) and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		return nil
	end
	local ok, data = pcall(TI.GetItemByID, id)
	for _, line in ipairs(ok and type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
		local text = Str(line.leftText)
		local n = text and tonumber(text:match(slotPattern))
		if n then slotsOf[id] = n return n end
	end
	return nil
end
local questsCache = {} -- kind -> { list = KindItems' list it was made from, set }
function QR.ForgetSlots() slotsOf, slotPattern, kindCache, questsCache = {}, nil, {}, {} end -- (tests)

--- The quests rewarding one (bag, quiver, ammo pouch) that you can take (your race, class and side): quest id -> true.
--- Done ones too (is:done says). Made once per index (reward:bag's filter is made on every keystroke; its slots aren't
--- read here: 0.65.x review).
function QR.KindQuests(kind)
	local db = DB()
	if not db then return {} end
	local list = QR.KindItems(kind)
	local c = questsCache[kind]
	if c and c.list == list then return c.set end
	local out = {}
	for _, it in ipairs(list) do
		for _, qid in ipairs(it.quests) do
			if out[qid] == nil and ForYou(db, qid) then out[qid] = true end
		end
	end
	questsCache[kind] = { list = list, set = out }
	return out
end

--- A quest's reward bag (quiver, ammo pouch) with the most slots: its index entry, its slots (nil: not known yet), its
--- kind's name ("Herb Bag") and subclass; nil when it rewards none. Of the kind asked for when one was (reward:bag,
--- "quests that reward bags": QR.slotKind; 0.65.x review: a 14-slot quiver counted for reward:bag), else any.
function QR.RewardBag(e, kind)
	local id = QuestIdOf(e)
	if not id then return nil end
	local test = KIND_TEST[kind or QR.slotKind or ""]
	local best, bestN, bestSub, bestSubID
	local get = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
	for _, it in ipairs(QR.RewardsOf(id) or {}) do
		local ok, _, _, sub, _, _, class, subID = false, nil, nil, nil, nil, nil, nil, nil
		if get then ok, _, _, sub, _, _, class, subID = pcall(get, it.id) end
		class = ok and ns.Num(class)
		if (test and test(class, ns.Num(subID))) or (not test and (class == CONTAINER or class == QUIVER_CLASS)) then
			local n = QR.Slots(it.id)
			if not best or (n or 0) > (bestN or 0) then
				best, bestN, bestSub, bestSubID = it, n, Str(sub), class == CONTAINER and ns.Num(subID) or nil
			end
		end
	end
	return best, bestN, bestSub, bestSubID
end

--- The most slots a quest's reward bag has (sort:slots, | sum slots), or nil (no bag, or not known yet).
function QR.RewardSlots(e)
	local it, n = QR.RewardBag(e)
	return it and n or nil
end

--- What a bag quest's row says: "Rewards Tailor's Satchel · 12 slots" (an Herb Bag's kind too), then its own detail;
--- nil for a quest rewarding none (its own detail stays).
function QR.BagDetail(e)
	local it, n, sub, subID = QR.RewardBag(e)
	if not it then return nil end
	local what = L["Rewards %s"]:format(it.name)
	if n then what = what .. ns.DETAIL_SEP .. L["%d slots"]:format(n) end
	if subID and subID ~= 0 and sub then what = what .. ns.DETAIL_SEP .. sub end -- (a bag for one trade: said)
	local d = e.detail
	return what .. ((type(d) == "string" and d ~= "") and (ns.DETAIL_SEP .. d) or "")
end

--- The kind a typed word asks for (reward:bag, reward:quiver, rewards:ammo_pouch: their rows then say which bag and its
--- slots, Search.lua's showField): "reward:bag" -> "bag", "reward:ammo_pouch" -> "ammo"; else nil.
function QR.KindOfWord(w)
	local k, v = w:match("^(rewards?):(.+)$")
	return k and QR.KIND_WORDS[(v:gsub("_", " "))] or nil
end

-- (a quest search for bags, or sorted by slots: List.lua's FillRow says which bag and its slots)
ns.FIELD_DETAIL = ns.FIELD_DETAIL or {}
ns.FIELD_DETAIL.slots = function(e) return QR.BagDetail(e) end

-- sort:slots (the most slots first, then the lowest level: as the question lists them) and | sum slots
do
	local A = ns.Aggregate
	if A and A.FIELDS then A.FIELDS.slots = { label = L["slots"], num = function(e) return QR.SlotsOfRow(e) end } end
	local F = ns.Filters
	if F and F.SORTS then
		F.SORTS.slots = "slots"
		if F.VALUES and F.VALUES.sort then F.VALUES.sort[#F.VALUES.sort + 1] = "slots" end
		local AS = F.APPLIES and F.APPLIES.sort
		if AS then AS.slots = { "questie", "quests" } end
	end
	local B = ns.Bar
	if B and B.SORTS then B.SORTS[#B.SORTS + 1] = { id = "slots", label = L["Slots"], field = "slots", tie = "level" } end
end

--- "quests that reward bags", "bag quests", "quivers from quests": { kind = "bag" | "quiver" | "ammo" }, or nil.
function QR.BagQuestion(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local quest, kind = false, nil
	t = t:gsub("ammo pouch", "ammo_pouch")
	for w in t:gmatch("%S+") do
		local k = QUESTION_KINDS[(w:gsub("_", " "))]
		if NOT_BAG_QUESTION[w] then return nil end
		if QUEST[w] then quest = true
		elseif k then kind = kind or k
		elseif not (FILLER[w] or BAG_EXTRA[w]) then return nil end
	end
	if not (quest and kind) then return nil end
	return { kind = kind }
end

local BAG_NOTE = { bag = L["Quests that reward a bag"], quiver = L["Quests that reward a quiver"],
	ammo = L["Quests that reward an ammo pouch"] }

local KIND_VALUE = { bag = "bag", quiver = "quiver", ammo = "ammo_pouch" }
--- As Advanced syntax, its answer and its Alt+` (docs/QUESTIONS.md 4.1): "@questie reward:bag -is:done sort:slots"
--- (reward: keeps to your race, class and side; the detail says which bag and its slots, FIELD_DETAIL.slots).
function QR.BagLine(q)
	return "@questie reward:" .. (KIND_VALUE[q.kind] or "bag") .. " -is:done sort:slots "
end
function QR.BagFooter(q)
	local note = BAG_NOTE[q.kind] or BAG_NOTE.bag
	-- (how many you've done already: not listed, said)
	local db, done = DB(), C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
	local seen, n = {}, 0
	if db and done and QR.Index() then
		for _, it in ipairs(QR.KindItems(q.kind)) do
			for _, qid in ipairs(it.quests) do
				if not seen[qid] and ForYou(db, qid) and Safe(done, qid) then seen[qid] = true n = n + 1 end
			end
		end
	end
	if n > 0 then note = note .. ns.DETAIL_SEP .. L["%d done already, not listed"]:format(n) end
	return note
end
function QR.BagNone()
	if not DB() then return { NoneRow(L["Needs Questie: it knows what every quest rewards"]) } end
	if not QR.Index() then return { NoneRow(L["Reading what Questie's quests reward: a moment"]) } end
	return { NoneRow(L["No quest Questie knows of rewards one"]) }
end

--- Alt+`: the same in Advanced mode ("@questie reward:outlaw_sabre").
function QR.ToAdvanced(q)
	local first = q.items[1]
	-- (the name as reward: matches it: apostrophes left out)
	local name = (#q.items == 1 or first.ln == table.concat(q.words, " ")) and first.m or table.concat(q.words, " ")
	return "@questie reward:" .. name:gsub(" ", "_") .. " "
end
