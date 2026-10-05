local ns = select(2, ...)
local H = ns.Highlight

local EQUIP_SLOTS = {
	"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot",
	"WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot",
	"Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot",
}

local QualityHex, Str, Secret = ns.QualityHex, ns.Str, ns.Secret -- (Util.lua)

local function BagLabel(bag)
	if bag == 0 then return "Backpack" end
	if Enum.BagIndex and bag == Enum.BagIndex.ReagentBag then return "Reagent bag" end
	return "Bag " .. bag
end

----------------------------------------------------------------------
-- Bag addons. With Bagnon or Baganator the game's own bag windows never show: their windows
-- do. Opening "your bags" and finding an item's button has to go through whichever is in use.
-- (Their windows belong to them, not Blizzard: showing them from here is what their own slash
-- commands and key bindings do.)
----------------------------------------------------------------------

local Bags = {}
ns.Bags = Bags

--- Bagnon, or Bagnonium (BagBrother's other front end), and its name.
function Bags.Bagnon()
	for _, name in ipairs({ "Bagnon", "Bagnonium" }) do
		local B = _G[name]
		if type(B) == "table" and type(B.Frames) == "table" and type(B.Owners) == "table" then return B, name end
	end
end

function Bags.Baganator()
	local B = _G.Baganator
	return type(B) == "table" and type(B.CallbackRegistry) == "table" and B or nil
end

--- The addon that shows your bags: "Bagnon" (or "Bagnonium"), "Baganator", or nil for the game's own.
function Bags.Active()
	local B, name = Bags.Bagnon()
	if B then
		local ok, on = pcall(B.Frames.IsEnabled, B.Frames, "inventory")
		if not ok or on ~= false then return name, B end
	end
	local G = Bags.Baganator()
	if G then return "Baganator", G end
end

local LAST_BAG = (Enum.BagIndex and Enum.BagIndex.ReagentBag) or ((NUM_BAG_SLOTS or 4) + 1)

--- Show your bags, in whichever window shows them. bags: the bag ids that must show (with the
--- game's own windows, each bag can be open or closed on its own).
function Bags.Open(bags)
	local which, A = Bags.Active()
	if which == "Baganator" then
		pcall(A.CallbackRegistry.TriggerEvent, A.CallbackRegistry, "BagShow")
	elseif which then
		pcall(A.Frames.Show, A.Frames, "inventory")
	else
		-- nothing open: all of them, as the bag key does
		local anyOpen = false
		for b = 0, LAST_BAG do
			if IsBagOpen(b) then anyOpen = true break end
		end
		if not anyOpen then OpenAllBags() end
		-- OpenAllBags does nothing while any bag but the backpack is open (the reagent bag left open,
		-- say): the bags the item is in are opened one by one
		for _, b in ipairs(bags or { 0 }) do
			if not IsBagOpen(b) then
				ns:Trace("items: bag " .. b .. " was closed, opening it")
				if b == 0 and OpenBackpack then pcall(OpenBackpack) elseif OpenBag then pcall(OpenBag, b) end
			end
		end
	end
	return which
end

-- Baganator's bag windows are named Baganator_<View>BackpackViewFrame<group>: found once, kept.
local baganatorRoots
local function BaganatorRoots()
	if not baganatorRoots or #baganatorRoots == 0 then
		baganatorRoots = {}
		for k, v in pairs(_G) do
			if type(k) == "string" and k:find("^Baganator_.*BackpackViewFrame") and type(v) == "table" and v.GetChildren then
				baganatorRoots[#baganatorRoots + 1] = v
			end
		end
	end
	return baganatorRoots
end

local function Num(f, method)
	local fn = f[method]
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, f)
	return ok and type(v) == "number" and v or nil
end

--- A bag button for bag/slot: Blizzard's and Baganator's answer GetBagID, Bagnon's GetBag.
local function IsSlot(f, bag, slot)
	local b = Num(f, "GetBagID") or Num(f, "GetBag")
	return b == bag and Num(f, "GetID") == slot
end

--- The visible button of bag/slot in whichever bag window is showing.
function Bags.FindButton(bag, slot)
	local function scan(f)
		if not f or not f:IsShown() or not f.EnumerateValidItems then return nil end
		for _, btn in f:EnumerateValidItems() do
			if btn:GetBagID() == bag and btn:GetID() == slot then return btn end
		end
	end
	local b = scan(_G.ContainerFrameCombinedBags)
	if b then return b end
	for i = 1, 13 do
		b = scan(_G["ContainerFrame" .. i])
		if b then return b end
	end
	local which, A = Bags.Active()
	local roots = {}
	if which == "Baganator" then
		roots = BaganatorRoots()
	elseif which then
		local ok, f = pcall(A.Frames.Get, A.Frames, "inventory")
		if ok and type(f) == "table" then roots = { f } end
	end
	for _, root in ipairs(roots) do
		if root.IsVisible and root:IsVisible() then
			local found = ns.FindFrame(root, function(f) return IsSlot(f, bag, slot) end, 8)
			if found then return found end
		end
	end
end
local FindBagButton = Bags.FindButton
local ShowInBags

--- Where an item is in your bags right now: { {bag, slot}, ... }.
function Bags.Locations(itemID)
	local locs = {}
	for bag = 0, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID then locs[#locs + 1] = { bag, slot } end
		end
	end
	return locs
end

ShowInBags = function(e)
	local bags, seen = {}, {}
	for _, loc in ipairs(e.locs or {}) do
		if not seen[loc[1]] then seen[loc[1]] = true; bags[#bags + 1] = loc[1] end
	end
	local which = Bags.Open(#bags > 0 and bags or nil)
	if which == "Baganator" and e.link then
		-- Baganator's own flash too
		local R = Bags.Baganator().CallbackRegistry
		C_Timer.After(0.2, function() pcall(R.TriggerEvent, R, "HighlightIdenticalItems", e.link) end)
	end
	ns:Trace("items: showing " .. tostring(e.name) .. " in " .. (which or "the game's bags"))
	if not e.locs then return end
	H:Find(function()
		local found = {}
		for _, loc in ipairs(e.locs) do
			local b = FindBagButton(loc[1], loc[2])
			if b then found[#found + 1] = b end
		end
		return #found > 0 and found or nil
	end)
end

--- Open your bags on an item you carry and point at it, as an Item result does. False when you
--- don't carry it (then nothing opens).
function Bags.ShowItem(itemID, link, name)
	local locs = Bags.Locations(itemID)
	if #locs == 0 then return false end
	ShowInBags({ name = name, link = link, locs = locs })
	return true
end

-- runs once the game has opened the character window on its equipment page: point at the slot
local function PointAtSlot(e)
	H:Find(function()
		local f = _G["Character" .. e.slotName]
		return f and f:IsVisible() and f or nil
	end)
end

-- fallback when the secure path isn't available
local function ShowEquipped(e)
	if not (CharacterFrame and CharacterFrame:IsShown()) then ToggleCharacter("PaperDollFrame") end
	PointAtSlot(e)
end

-- Open means the equipment page itself is showing: the window open on another page goes
-- through the game's own key too (it switches page), never ToggleCharacter from here (taint).
local function PaperDollOpen() return PaperDollFrame and PaperDollFrame:IsVisible() and true or false end
local CHAR_SECURE = { binding = "TOGGLECHARACTER0", buttons = { "CharacterMicroButton" }, click = ns.Secure.PAPERDOLL_CLICK }

-- Shift+Enter / Shift+click: use the item, as a right-click on it in your bags does (drink, eat,
-- read, open, equip...). The game presses it: a /use line on the secure macro button, so it's
-- allowed (Terminal's own code can't use items). Worn items are used by their slot (trinkets).
local function UseMacro(e)
	if e.slotId then return "/use " .. e.slotId end
	return e.itemID and ("/use item:" .. e.itemID) or nil
end
local USE_SPEC = { macro = UseMacro }
local function UseNeverOpen() return false end -- nothing has to be open first: always pressed
local function UsedAfter(e) ns:Trace("items: the game used " .. tostring(e.name)) end
-- only when the game couldn't be handed the press: in combat (Enter can't be rebound then), or
-- no secure button could be made
local function UseInCombat(e)
	if InCombatLockdown() then
		ns:Print("In combat: Terminal can't use " .. tostring(e.name) .. " (the game doesn't allow it then).")
	else
		ns:Trace("items: no secure button to use " .. tostring(e.name))
		ns:Print("Couldn't use " .. tostring(e.name) .. " from the terminal. Try it from your bags.")
	end
end

-- Quest items. A bag item is tied to its quest even without any other addon:
--   1. the game says so (GetContainerItemQuestInfo gives the quest an item starts),
--   2. the item's name is one of the quest log's item objectives ("Intact Limbs: 2/8"),
--   3. the item's name appears anywhere in a quest's objectives ("Bring me 8 Intact Limbs"),
--   4. for quest-class items, anywhere in a quest's description.
-- Then searching for the item brings its quest along (see UI:Search).

local function Plain(t)
	t = t:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return (t:gsub("\226\128\152", "'"):gsub("\226\128\153", "'")) -- curly apostrophes -> '
end

--- lowercase, apostrophes dropped, punctuation to spaces: "Darthalia\226\128\153s Orders!" == "darthalias orders"
local function N(t)
	t = ns.Lower(Plain(t)):gsub("'", ""):gsub("%p", " "):gsub("%s+", " ") -- keeps letters of every language
	return (t:gsub("^ ", ""):gsub(" $", ""))
end

--- The quest log as text: { { id, title, objectives = {lowercase...}, full = lowercase } ... }
--- and name -> quest for item objectives. Made from the Quest Log rows (Quests.lua reads the log once
--- per quest event, and keeps the pieces), not by reading the whole log again on every bag event;
--- kept until those rows are made again.
local questIndex, questIndexFrom
local function QuestIndex()
	local qp = ns.providers.quests
	local rows = qp and ns:GetEntries(qp) or {}
	if questIndex and rows == questIndexFrom then
		questIndex[1].questieItems, questIndex[1].questieDB = nil, nil -- (Questie's item needs: asked again per index of your bags)
		return questIndex[1], questIndex[2]
	end
	local list, exact = {}, {}
	for _, e in ipairs(rows) do
		if e.questID then
			local q = { id = e.questID, title = e.name, objectives = {} }
			q.ntitle = q.title and N(q.title) or ""
			for _, o in ipairs(e.objectives or {}) do
				local t = Plain(o[1])
				q.objectives[#q.objectives + 1] = N(t)
				if o[2] == "item" or o[2] == nil then
					local n = N((t:gsub("%d+%s*/%s*%d+", "")))
					if n ~= "" then exact[n] = q end
				end
			end
			q.full = N(table.concat(q.objectives, " ") .. " " .. (e.desc or "") .. " " .. (e.objText or ""))
			list[#list + 1] = q
		end
	end
	questIndex, questIndexFrom = { list, exact }, rows
	return list, exact
end

-- Questie knows which items each quest needs, even when the quest log doesn't say.
local function QuestieModule(name)
	local L = _G.QuestieLoader
	if not (L and L.ImportModule) then return nil end
	local ok, m = pcall(L.ImportModule, L, name)
	return ok and m or nil
end

--- Which of your quests needs which item, by Questie: item ID -> quest (the first in the log
--- wins). Worked out once per index of your bags (it used to be asked per item and quest).
local function QuestieItems(quests)
	if quests.questieItems ~= nil then return quests.questieItems or nil, quests.questieDB end
	quests.questieItems = false
	local Q = _G.Questie
	if not (Q and Q.API and Q.API.isReady) then return nil end
	local DB = QuestieModule("QuestieDB")
	if not (DB and DB.QueryQuestSingle) then return nil end
	local map = {}
	local function put(id, qq) if id ~= nil and not map[id] then map[id] = qq end end
	for _, qq in ipairs(quests) do
		local function get(field)
			local ok, v = pcall(DB.QueryQuestSingle, qq.id, field)
			return ok and v or nil
		end
		local req = get("requiredSourceItems")
		for _, id in ipairs(type(req) == "table" and req or {}) do put(id, qq) end
		put(get("sourceItemId"), qq)
		local objs = get("objectives")
		if type(objs) == "table" then
			for _, o in ipairs(type(objs[3]) == "table" and objs[3] or {}) do
				if type(o) == "table" then put(o[1], qq) end
			end
		end
	end
	quests.questieItems, quests.questieDB = map, DB
	return map, DB
end

local function QuestieFor(itemID, quests)
	local map, DB = QuestieItems(quests)
	if not map then return nil end
	if DB.QueryItemSingle then -- an item that starts a quest
		local ok, start = pcall(DB.QueryItemSingle, itemID, "startQuest")
		if ok and start then
			for _, qq in ipairs(quests) do if qq.id == start then return { id = qq.id, title = qq.title, how = "Questie" } end end
		end
	end
	local qq = map[itemID]
	if qq then return { id = qq.id, title = qq.title, how = "Questie" } end
end

-- a quest's words padded with spaces, made once per index (asked for every item)
local function Padded(qq, field, make)
	local v = qq[field]
	if not v then v = " " .. make(qq) .. " "; qq[field] = v end
	return v
end
local function TitleAndGoals(qq) return qq.ntitle .. " " .. table.concat(qq.objectives, " ") end
local function Title(qq) return qq.ntitle end
local function Full(qq) return qq.full end

--- The quest a bag item belongs to, or nil. Returns { id =, title =, how = }.
local function QuestFor(bag, slot, name, itemID, quests, exact)
	local isQuestItem = false
	if C_Container.GetContainerItemQuestInfo then
		local ok, qi = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
		if ok and type(qi) == "table" then
			isQuestItem = qi.isQuestItem and true or false
			if qi.questID then
				local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qi.questID)
				return { id = qi.questID, title = Str(title), how = "game" }
			end
		end
	end
	local lname = N(name)
	local q = exact[lname]
	if q then return { id = q.id, title = q.title, how = "objective" } end
	if #lname >= 3 then
		for _, qq in ipairs(quests) do
			for _, o in ipairs(qq.objectives) do
				if o:find(lname, 1, true) then return { id = qq.id, title = qq.title, how = "objective text" } end
			end
		end
		local viaQuestie = QuestieFor(itemID, quests)
		if viaQuestie then return viaQuestie end
		-- the item and its quest share a name ("Darthalia's Orders")
		for _, qq in ipairs(quests) do
			if #lname >= 6 and #qq.ntitle >= 6 and (qq.ntitle:find(lname, 1, true) or lname:find(qq.ntitle, 1, true)) then
				return { id = qq.id, title = qq.title, how = "quest title" }
			end
		end
		-- every word of a multi-word item name turns up in one quest's title and objectives
		local words = {}
		for w in lname:gmatch("%S+") do if #w >= 3 then words[#words + 1] = w end end
		if #words >= 2 then
			for _, qq in ipairs(quests) do
				local hay = Padded(qq, "pgoals", TitleAndGoals)
				local all = true
				for _, w in ipairs(words) do
					if not hay:find(" " .. w, 1, true) then all = false; break end
				end
				if all then return { id = qq.id, title = qq.title, how = "quest words" } end
			end
		end
		if not isQuestItem and C_Item.GetItemInfoInstant then
			local classID = select(6, C_Item.GetItemInfoInstant(itemID))
			isQuestItem = classID == (Enum.ItemClass and Enum.ItemClass.Questitem or 12)
		end
		if isQuestItem then
			for _, qq in ipairs(quests) do
				if qq.full:find(lname, 1, true) then return { id = qq.id, title = qq.title, how = "quest text" } end
			end
		end
	end
end

--- Is this bag item a quest item (the game flags it, it is quest-class, or it binds as a quest item)?
local function IsQuestItem(bag, slot, itemID)
	if C_Container.GetContainerItemQuestInfo then
		local ok, qi = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
		if ok and type(qi) == "table" and (qi.isQuestItem or qi.questID) then return true end
	end
	local classID = C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(itemID))
	if classID == (Enum.ItemClass and Enum.ItemClass.Questitem or 12) then return true end
	local bindType = C_Item.GetItemInfo and select(14, C_Item.GetItemInfo(itemID))
	return bindType == 4
end

--- Is the worn piece in this slot bound? The game's answer (C_Item.IsBound on its slot), else yes: wearing
--- binds a bind-on-equip piece (bind-to-account pieces are the rare exception).
local function WornBound(slotId)
	local IB, IL = C_Item.IsBound, _G.ItemLocation
	if IB and IL and IL.CreateFromEquipmentSlot then
		local ok, loc = pcall(IL.CreateFromEquipmentSlot, IL, slotId)
		if ok and loc then
			local ok2, b = pcall(IB, loc)
			if ok2 and type(b) == "boolean" and not Secret(b) then return b end
		end
	end
	return true
end

local STOP = { the = true, of = true, ["and"] = true, ["for"] = true, with = true, from = true, that = true, this = true, into = true }

--- No sure quest: the quests whose text shares the most with the item's name (best two).
--- A word counts when a quest's title, objectives or description holds it (ignoring a plural s
--- or possessive 's), longer words counting for more, and the title counting double.
local function GuessQuests(lname, quests)
	local words = {}
	for w in lname:gmatch("%S+") do
		if #w >= 4 and not STOP[w] then words[#words + 1] = (w:gsub("s$", "")) end
	end
	if #words == 0 then return nil end
	local scored = {}
	for _, qq in ipairs(quests) do
		local title = Padded(qq, "ptitle", Title)
		local hay = Padded(qq, "pfull", Full)
		local score = 0
		for _, w in ipairs(words) do
			if hay:find(" " .. w, 1, true) then score = score + #w end
			if title:find(" " .. w, 1, true) then score = score + #w end
		end
		if score > 0 then scored[#scored + 1] = { id = qq.id, score = score } end
	end
	table.sort(scored, function(a, b) return a.score > b.score end)
	local ids = {}
	for i = 1, math.min(2, #scored) do
		if i == 1 or scored[i].score * 2 >= scored[1].score then ids[#ids + 1] = scored[i].id end
	end
	return #ids > 0 and ids or nil
end

-- Item names the game hasn't loaded yet. Right after login a bag item's info can come without its name
-- (itemName nil, the link's text "[]"): Rumsey Rum, Ice Cold Milk... were left out (a row named "" matches
-- no search), and nothing built the list again once the names came, while the bag addon (which looks each
-- name up) showed them. Such an item is left out for now, its name is asked for, and the list is built
-- again once the names are in (or after 10 s). The event is listened to only while names are awaited.
local nameWait = { ids = {}, count = 0, asked = {} }
local nameFrame = CreateFrame("Frame")

local function NamesArrived()
	for k in pairs(nameWait.ids) do nameWait.ids[k] = nil end
	nameWait.count = 0
	pcall(nameFrame.UnregisterEvent, nameFrame, "GET_ITEM_INFO_RECEIVED")
	pcall(nameFrame.UnregisterEvent, nameFrame, "ITEM_DATA_LOAD_RESULT")
	if ns.providers.items then ns.providers.items._dirty = true end
end

local function NameOf(id, link, given)
	local name = Str(given)
	if name then return name end
	name = Str(link) and link:match("|h%[(.-)%]|h")
	if name and name ~= "" then return name end
	name = C_Item.GetItemNameByID and Str((select(2, pcall(C_Item.GetItemNameByID, id))))
	if name then return name end
	-- not loaded yet: ask (twice at most: some never come) and build the list again once it's in
	if id and C_Item.RequestLoadItemDataByID and (nameWait.asked[id] or 0) < 2 and not nameWait.ids[id] then
		nameWait.asked[id] = (nameWait.asked[id] or 0) + 1
		if nameWait.count == 0 then
			pcall(nameFrame.RegisterEvent, nameFrame, "GET_ITEM_INFO_RECEIVED")
			pcall(nameFrame.RegisterEvent, nameFrame, "ITEM_DATA_LOAD_RESULT")
			C_Timer.After(10, function() if nameWait.count > 0 then NamesArrived() end end)
		end
		nameWait.ids[id] = true
		nameWait.count = nameWait.count + 1
		pcall(C_Item.RequestLoadItemDataByID, id)
		ns:Trace("items: waiting for the name of item " .. tostring(id))
	end
	return nil
end
ns.ItemNames = { NameOf = NameOf, wait = nameWait, frame = nameFrame } -- (tests)

nameFrame:SetScript("OnEvent", function(_, _, id)
	if nameWait.count == 0 then return end
	if id and nameWait.ids[id] then
		nameWait.ids[id] = nil
		nameWait.count = nameWait.count - 1
	elseif not id then
		-- (a client that doesn't say which: whatever has a name now has arrived)
		for k in pairs(nameWait.ids) do
			if C_Item.GetItemNameByID and Str((select(2, pcall(C_Item.GetItemNameByID, k)))) then
				nameWait.ids[k] = nil
				nameWait.count = nameWait.count - 1
			end
		end
	end
	if nameWait.count <= 0 then NamesArrived() end
end)

ns:RegisterProvider("items", {
	label = "Item",
	color = "ffc8c8c8",
	aliases = { "items", "bag", "bags", "inventory", "equipped" }, -- (@gear: equipment only, below)
	events = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" },
	guard = 1,
	collect = function()
		local out, byID = {}, {}
		local quests, questExact = QuestIndex()

		local lastBag = (Enum.BagIndex and Enum.BagIndex.ReagentBag) or ((NUM_BAG_SLOTS or 4) + 1)
		-- each slot on its own: one item the client answers oddly for can't drop the whole list (every item
		-- vanished from search then, as if the bags were empty); what was read is traced for .debug log
		local read, failed, failedAt = 0, 0, nil
		local function Slot(bag, slot)
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if not (info and info.itemID) then return end
			read = read + 1
			local e = byID[info.itemID]
			if not e then
				local name = NameOf(info.itemID, info.hyperlink, info.itemName)
				if name then
					local _, itemType, subType, _, _, classID, subClassID = C_Item.GetItemInfoInstant(info.itemID)
					e = {
						key = info.itemID,
						name = name,
						icon = info.iconFileID,
						color = QualityHex(info.quality),
						link = info.hyperlink,
						text = table.concat({ itemType or "", subType or "" }, " "),
						count = 0,
						locs = {},
						firstBag = bag,
						itemID = info.itemID, classID = classID, subClassID = subClassID, subType = subType,
						activate = ShowInBags,
						secondary = UseInCombat, secondarySecure = USE_SPEC,
						secondaryIsOpen = UseNeverOpen, secondaryAfter = UsedAfter,
					}
					local q = QuestFor(bag, slot, name, info.itemID, quests, questExact)
					if q then
						e.questID, e.questItem = q.id, true
						e.text = e.text .. " quest " .. (q.title or "")
					elseif IsQuestItem(bag, slot, info.itemID) then
						e.questItem = true
						e.guessIDs = GuessQuests(N(name), quests)
					end
					byID[info.itemID] = e
					out[#out + 1] = e
				end
			end
			if e then
				e.count = e.count + (info.stackCount or 1)
				e.locs[#e.locs + 1] = { bag, slot }
				-- (is:soulbound / is:boe) one row per item: bound = some stack is bound, unbound = some stack isn't
				local b = info.isBound
				if b ~= nil and not Secret(b) then
					if b then e.bound = true else e.unbound = true end
				end
			end
		end
		for bag = 0, lastBag do
			local okn, slots = pcall(C_Container.GetContainerNumSlots, bag)
			for slot = 1, (okn and type(slots) == "number" and slots or 0) do
				local ok, err = pcall(Slot, bag, slot)
				if not ok then
					failed = failed + 1
					failedAt = failedAt or ("bag " .. bag .. " slot " .. slot .. ": " .. tostring(err))
				end
			end
		end
		ns:Trace(("items: %d bag slots with items, %d items listed, %d awaiting names%s"):format(read, #out, nameWait.count,
			failed > 0 and (", " .. failed .. " failed (first: " .. failedAt .. ")") or ""))
		for _, e in pairs(byID) do
			local where = BagLabel(e.firstBag)
			e.detail = (e.questID and "Quest  " or "") .. (e.count > 1 and ("x" .. e.count .. "  ") or "") .. where
		end

		for _, slotName in ipairs(EQUIP_SLOTS) do
			local slotId = GetInventorySlotInfo(slotName)
			local link = slotId and GetInventoryItemLink("player", slotId)
			if link then
				local itemID = C_Item.GetItemInfoInstant(link)
				local name = NameOf(itemID, link)
				if name then
					local _, _, quality = C_Item.GetItemInfo(link)
					local bound = WornBound(slotId)
					out[#out + 1] = {
						-- known by the item, as in your bags: equipping swaps places, and the history keeps the piece picked
						key = itemID or ("eq" .. slotId),
						name = name,
						icon = GetInventoryItemTexture("player", slotId),
						color = QualityHex(quality),
						link = link,
						text = "equipped " .. slotName:gsub("Slot", ""),
						detail = "Equipped: " .. slotName:gsub("Slot", ""),
						slotName = slotName, slotId = slotId, itemID = itemID,
						bound = bound or nil, unbound = (not bound) or nil,
						activate = ShowEquipped,
						secure = CHAR_SECURE,
						isOpen = PaperDollOpen,
						after = PointAtSlot,
						secondary = UseInCombat, secondarySecure = USE_SPEC,
						secondaryIsOpen = UseNeverOpen, secondaryAfter = UsedAfter,
					}
				end
			end
		end
		return out
	end,
})

-- Kinds within your bags: @consumable (potions, food, flasks, scrolls...) and @mats
-- (crafting materials: trade goods and reagents). Same entries as Item, filtered by the
-- item's class, labelled with its sub-type ("Potion  x5  Backpack"). Only with @: in a plain
-- search these are already found as Items.

local CONSUMABLE = (Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local TRADEGOODS = (Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
local REAGENT = (Enum.ItemClass and Enum.ItemClass.Reagent) or 5

local function IsCraftingReagent(itemID)
	if not (C_Item.GetItemInfo and itemID) then return false end
	local ok, r = pcall(function() return select(17, C_Item.GetItemInfo(itemID)) end)
	return ok and r == true
end

local function SubKind(id, def)
	ns:RegisterProvider(id, {
		label = def.label,
		color = def.color,
		aliases = def.aliases,
		explicit = true,
		follows = "items", -- made again whenever the item list is (Core's GetEntries)
		collect = function()
			local out = {}
			for _, e in ipairs(ns:GetEntries(ns.providers.items)) do
				if e.locs and def.want(e) then
					local c = {}
					for k, v in pairs(e) do c[k] = v end -- a copy: the Item entry keeps its own kind
					c.detail = (e.subType and e.subType ~= "" and (e.subType .. "  ") or "") .. (e.detail or "")
					out[#out + 1] = c
				end
			end
			return out
		end,
	})
end

SubKind("consumables", {
	label = "Consumable",
	color = "ff7fe08c",
	aliases = { "consumable", "consumables", "consume", "food", "drink", "potion", "potions", "flask", "elixir", "scroll" },
	want = function(e) return e.classID == CONSUMABLE end,
})

SubKind("mats", {
	label = "Crafting Mat",
	color = "ffd9b26a",
	aliases = { "craftingmats", "craftingmat", "mats", "mat", "materials", "material", "tradegoods", "tradegood" },
	want = function(e)
		return e.classID == TRADEGOODS or e.classID == REAGENT or IsCraftingReagent(e.itemID)
	end,
})

----------------------------------------------------------------------
-- @gear: the equipment among your items (weapons, armour, jewellery, trinkets...), in your bags or
-- worn. Enter shows it as an Item result does (your bags, or the character window on its slot).
-- Shift+Enter equips a bag item: an /equip line on the secure macro button, pressed by the game.
----------------------------------------------------------------------

--- The item's equipment slot type (INVTYPE_x), or nil. Asked by id, then by its link, then from its full
--- info: one answer missing (an item the client hasn't cached) mustn't leave gear out.
local function EquipLoc(e)
	local slots = ns.Filters and ns.Filters.SLOTS or {}
	for _, what in ipairs({ e.itemID or false, e.link or false }) do
		if what and C_Item.GetItemInfoInstant then
			local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, what)
			if ok and type(loc) == "string" and slots[loc] then return loc end
		end
	end
	if e.itemID and C_Item.GetItemInfo then
		local ok, _, _, _, _, _, _, _, _, loc = pcall(C_Item.GetItemInfo, e.itemID)
		if ok and type(loc) == "string" and slots[loc] then return loc end
	end
end

local function EquipMacro(e) return e.itemID and ("/equip item:" .. e.itemID) or nil end
local EQUIP_SPEC = { macro = EquipMacro }
local function EquippedAfter(e) ns:Trace("gear: the game equipped " .. tostring(e.name)) end
-- only when the game couldn't be handed the press (in combat, no secure button)
local function EquipFallback(e)
	if InCombatLockdown() then
		ns:Print("In combat: Terminal can't equip " .. tostring(e.name) .. " (the game doesn't allow it then).")
	else
		ns:Print("Couldn't equip " .. tostring(e.name) .. " from the terminal. Try it from your bags.")
	end
end
local function AlreadyWorn(e) ns:Print(tostring(e.name) .. " is already equipped.") end

local function ItemLevel(e)
	local get = C_Item.GetDetailedItemLevelInfo
	if not get then return nil end
	local ok, lvl = pcall(get, e.link or e.itemID)
	return ok and type(lvl) == "number" and lvl > 0 and lvl or nil
end

local function CanUse(id)
	if not (C_PlayerInfo and C_PlayerInfo.CanUseItem) then return true end
	local ok, yes = pcall(C_PlayerInfo.CanUseItem, id)
	return not ok or yes ~= false
end

ns:RegisterProvider("gear", {
	label = "Gear",
	color = "ff9fd3ff",
	aliases = { "gear", "equip", "armor", "armour", "weapon", "weapons" }, -- ("equipment" is the sets', EquipmentSets.lua)
	explicit = true, -- (a plain search already finds these as Items)
	follows = "items", -- made again whenever the item list is (Core's GetEntries)
	collect = function()
		local out = {}
		for _, e in ipairs(ns:GetEntries(ns.providers.items)) do
			local loc = EquipLoc(e)
			if loc then
				local c = {}
				for k, v in pairs(e) do c[k] = v end -- a copy: the Item entry keeps its own kind
				local lvl = ItemLevel(e)
				local usable = CanUse(e.itemID)
				c.equipLoc = loc
				-- known by the item, wherever it is: equipping swaps places (worn Item rows are known by their slot), and
				-- the history must keep the piece you picked, not whatever it replaced in that slot
				c.key = e.itemID or e.key
				c.detail = (_G[loc] or loc) .. (lvl and ("  ilvl " .. lvl) or "") .. "  "
					.. (e.slotId and "Equipped" or "In Bag") .. (usable and "" or "  can't use")
				c.text = (rawget(e, "_ltext") or "") .. (e.slotId and " equipped worn" or " in bag bags")
				if not usable then c.color = "|cff8a8a8a" end
				if e.slotId then
					c.secondary, c.secondarySecure, c.secondaryIsOpen, c.secondaryAfter = AlreadyWorn, nil, nil, nil
				else
					c.secondary, c.secondarySecure, c.secondaryIsOpen, c.secondaryAfter = EquipFallback, EQUIP_SPEC, UseNeverOpen, EquippedAfter
				end
				out[#out + 1] = c
			end
		end
		return out
	end,
})
