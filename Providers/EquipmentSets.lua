local ns = select(2, ...)

-- Equipment sets (the character window's Equipment Manager). Search by the set's name, or
-- only sets with @equipmentset (also @set, @sets, @outfit). Enter equips the set; Shift+Enter
-- opens the character window on its equipment sets page and points at the set (through the
-- game's own character key; without one, it lists the set's items in chat instead).
-- Equipping and opening windows are blocked in combat, so in combat the entry does nothing.

local function API() return _G.C_EquipmentSet end

local function Info(id)
	local E = API()
	if not (E and E.GetEquipmentSetInfo) then return nil end
	local ok, name, icon, setID, isEquipped, numItems, numEquipped, numInInventory, numLost =
		pcall(E.GetEquipmentSetInfo, id)
	if not ok or type(name) ~= "string" or name == "" then return nil end
	return {
		name = name, icon = icon, id = setID or id, equipped = isEquipped and true or false,
		items = numItems or 0, worn = numEquipped or 0, bags = numInInventory or 0, lost = numLost or 0,
	}
end

local function Equip(e)
	local E = API()
	if InCombatLockdown() then
		ns:Print("In combat: can't change equipment sets now.")
		return
	end
	local info = Info(e.setID)
	if info and info.equipped then
		ns:Print(e.name .. " is already equipped.")
		return
	end
	local ok, res = pcall(E.UseEquipmentSet, e.setID)
	if not ok or res == false then
		ns:Print("Couldn't equip " .. e.name .. (info and info.lost > 0 and (" (" .. info.lost .. " missing)") or "") .. ".")
		return
	end
	ns:Print("Equipping " .. e.name .. (info and info.lost > 0 and (" (" .. info.lost .. " item" .. (info.lost == 1 and "" or "s") .. " missing)") or "") .. ".")
end

local SLOT_NAMES = {
	[1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist",
	[7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Finger",
	[13] = "Trinket", [14] = "Trinket", [15] = "Back", [16] = "Main hand", [17] = "Off hand",
	[18] = "Ranged", [19] = "Tabard",
}

--- The set's items, one line each, for chat.
local function ListItems(e)
	local E = API()
	local lines = { e.name .. ":" }
	local ids = E and E.GetItemIDs and select(2, pcall(E.GetItemIDs, e.setID))
	if type(ids) ~= "table" then
		ns:Output({ e.name .. ": no item list available." })
		return
	end
	for slot = 1, 19 do
		local itemID = ids[slot]
		if type(itemID) == "number" and itemID > 0 then
			local _, link = C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)
			local name = link or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ("item " .. itemID)
			local have = C_Item.GetItemCount and C_Item.GetItemCount(itemID, false) or 1
			local worn = GetInventoryItemID and GetInventoryItemID("player", slot) == itemID
			lines[#lines + 1] = "  " .. (SLOT_NAMES[slot] or ("Slot " .. slot)) .. ": " .. name
				.. ((not worn and (have or 0) == 0) and "  (missing)" or "")
		end
	end
	if #lines == 1 then lines[#lines + 1] = "  (no items saved in this set)" end
	ns:Output(lines)
end

local function PaperDollOpen()
	local cf, pd = _G.CharacterFrame, _G.PaperDollFrame
	return cf and cf:IsShown() and pd and pd:IsShown() and true or false
end

--- Runs once the character window is open: switch to its equipment sets page, scroll the
--- list to the set and point at it (nothing is equipped).
local function ShowInManager(e)
	local H = ns.Highlight
	local pd = _G.PaperDollFrame
	local function pane() return pd and pd.EquipmentManagerPane end
	local p = pane()
	if not (p and p:IsVisible()) then
		local tab = _G.PaperDollSidebarTab3 -- the character window's equipment sets tab
		if tab and tab.Click then
			ns:Trace("equipment sets: clicking the equipment sets tab")
			pcall(tab.Click, tab)
		end
	end
	local scrolled = false
	H:When(function()
		p = pane()
		if not (p and p:IsVisible()) then return nil end
		local function find()
			return ns.FindFrame(p, function(f)
				if f.setID ~= nil then return f.setID == e.setID end
				if not f.Click then return false end
				for _, r in ipairs({ f:GetRegions() }) do
					if r.GetObjectType and r:GetObjectType() == "FontString" and r:GetText() == e.name then return true end
				end
				return false
			end, 8)
		end
		local row = find()
		if not row and not scrolled and p.ScrollBox and p.ScrollBox.ScrollToElementDataByPredicate then
			scrolled = true
			pcall(p.ScrollBox.ScrollToElementDataByPredicate, p.ScrollBox, function(node)
				local d = type(node) == "table" and (node.GetData and node:GetData() or node)
				return type(d) == "table" and d.setID == e.setID
			end)
			row = find()
		end
		return row
	end, function(row)
		H:Show(row)
	end, 20, function()
		ns:Trace("equipment sets: no row for " .. tostring(e.name) .. " in the character window")
	end)
end

ns:RegisterProvider("equipmentset", {
	label = "Equipment Set",
	color = "ff9fe0c0",
	aliases = { "equipmentset", "equipmentsets", "equipment", "set", "sets", "outfit", "outfits" },
	noCombat = true, -- equipping is blocked in combat
	events = { "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED" },
	guard = 1,
	collect = function()
		local out = {}
		local E = API()
		if not (E and E.GetEquipmentSetIDs) then return out end
		local ok, ids = pcall(E.GetEquipmentSetIDs)
		if not ok or type(ids) ~= "table" then return out end
		for _, id in ipairs(ids) do
			local s = Info(id)
			if s then
				local state
				if s.equipped then
					state = "Equipped"
				elseif s.lost > 0 then
					state = s.lost .. " missing"
				else
					state = s.worn .. "/" .. s.items .. " worn"
				end
				out[#out + 1] = {
					key = s.id,
					name = s.name,
					icon = s.icon or "Interface\\Icons\\INV_Chest_Chain_04",
					detail = "Set  " .. state,
					text = "equipment set gear outfit",
					setID = s.id,
					activate = Equip,
					-- Shift+Enter: the character window's equipment sets page, through the
					-- game's character key; ListItems is the fallback without one
					secondary = ListItems,
					secondarySecure = { binding = "TOGGLECHARACTER0", buttons = { "CharacterMicroButton" } },
					secondaryIsOpen = PaperDollOpen,
					secondaryAfter = ShowInManager,
					noCombatSecondary = true,
				}
			end
		end
		return out
	end,
})
