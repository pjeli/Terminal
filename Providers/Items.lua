local ns = select(2, ...)
local H = ns.Highlight

local EQUIP_SLOTS = {
	"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot",
	"WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot",
	"Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot",
}

local function QualityHex(q)
	local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	return c and c.hex
end

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

--- Show your bags, in whichever window shows them.
function Bags.Open()
	local which, A = Bags.Active()
	if which == "Baganator" then
		pcall(A.CallbackRegistry.TriggerEvent, A.CallbackRegistry, "BagShow")
	elseif which then
		pcall(A.Frames.Show, A.Frames, "inventory")
	elseif not IsBagOpen(0) then
		OpenAllBags()
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
	local lastBag = (Enum.BagIndex and Enum.BagIndex.ReagentBag) or ((NUM_BAG_SLOTS or 4) + 1)
	for bag = 0, lastBag do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID then locs[#locs + 1] = { bag, slot } end
		end
	end
	return locs
end

ShowInBags = function(e)
	local which = Bags.Open()
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
	end, 8)
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
	end, 8)
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

-- Quest items. A bag item is tied to its quest even without any other addon:
--   1. the game says so (GetContainerItemQuestInfo gives the quest an item starts),
--   2. the item's name is one of the quest log's item objectives ("Intact Limbs: 2/8"),
--   3. the item's name appears anywhere in a quest's objectives ("Bring me 8 Intact Limbs"),
--   4. for quest-class items, anywhere in a quest's description.
-- Then searching for the item brings its quest along (see UI:Search).

local function Str(v)
	if type(v) ~= "string" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

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
--- and name -> quest for item objectives.
local function QuestIndex()
	local list, exact = {}, {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return list, exact end
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			local q = { id = info.questID, title = Str(info.title), objectives = {} }
				q.ntitle = q.title and N(q.title) or ""
			local texts = {}
			local ok, objs = pcall(C_QuestLog.GetQuestObjectives, info.questID)
			for _, o in ipairs(ok and type(objs) == "table" and objs or {}) do
				local t = Str(o.text)
				if t then
					t = Plain(t)
					q.objectives[#q.objectives + 1] = N(t)
					if o.type == "item" or o.type == nil then
						local n = N((t:gsub("%d+%s*/%s*%d+", "")))
						if n ~= "" then exact[n] = q end
					end
				end
			end
			if #q.objectives == 0 and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then -- classic-style log
				for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
					local okb, t, typ = pcall(GetQuestLogLeaderBoard, j, i)
					t = okb and Str(t)
					if t then
						t = Plain(t)
						q.objectives[#q.objectives + 1] = N(t)
						if typ == "item" then
							local n = N((t:gsub("%d+%s*/%s*%d+", "")))
							if n ~= "" then exact[n] = q end
						end
					end
				end
			end
			texts[#texts + 1] = table.concat(q.objectives, " ")
			if GetQuestLogQuestText then
				local okq, desc, obj = pcall(GetQuestLogQuestText, i)
				if okq then texts[#texts + 1] = (Str(desc) or "") .. " " .. (Str(obj) or "") end
			end
			q.full = N(table.concat(texts, " "))
			list[#list + 1] = q
		end
	end
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

ns:RegisterProvider("items", {
	label = "Item",
	color = "ffc8c8c8",
	aliases = { "items", "bag", "bags", "inventory", "gear", "equipped" },
	events = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" },
	guard = 1,
	collect = function()
		local out, byID = {}, {}
		local quests, questExact = QuestIndex()

		local lastBag = (Enum.BagIndex and Enum.BagIndex.ReagentBag) or ((NUM_BAG_SLOTS or 4) + 1)
		for bag = 0, lastBag do
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID then
					local e = byID[info.itemID]
					if not e then
						local name = info.itemName or (info.hyperlink and info.hyperlink:match("%[(.-)%]"))
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
							}
							local q = QuestFor(bag, slot, name, info.itemID, quests, questExact)
							if q then
								e.questID = q.id
								e.text = e.text .. " quest " .. (q.title or "")
							elseif IsQuestItem(bag, slot, info.itemID) then
								e.guessIDs = GuessQuests(N(name), quests)
							end
							byID[info.itemID] = e
							out[#out + 1] = e
						end
					end
					if e then
						e.count = e.count + (info.stackCount or 1)
						e.locs[#e.locs + 1] = { bag, slot }
					end
				end
			end
		end
		for _, e in pairs(byID) do
			local where = BagLabel(e.firstBag)
			e.detail = (e.questID and "Quest  " or "") .. (e.count > 1 and ("x" .. e.count .. "  ") or "") .. where
		end

		for _, slotName in ipairs(EQUIP_SLOTS) do
			local slotId = GetInventorySlotInfo(slotName)
			local link = slotId and GetInventoryItemLink("player", slotId)
			if link then
				local name = link:match("%[(.-)%]")
				if name then
					local itemID = C_Item.GetItemInfoInstant(link)
					local _, _, quality = C_Item.GetItemInfo(link)
					out[#out + 1] = {
						key = "eq" .. slotId,
						name = name,
						icon = GetInventoryItemTexture("player", slotId),
						color = QualityHex(quality),
						link = link,
						text = "equipped " .. slotName:gsub("Slot", ""),
						detail = "Equipped: " .. slotName:gsub("Slot", ""),
						slotName = slotName,
						activate = ShowEquipped,
						secure = CHAR_SECURE,
						isOpen = PaperDollOpen,
						after = PointAtSlot,
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
		events = { "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE" },
		guard = 1,
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
