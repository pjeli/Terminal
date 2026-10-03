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

-- The character window's equipment sets page, opened by the game itself: Shift+Enter is bound
-- to a macro of /click lines (character micro button, the right-pane arrow when the pane is
-- closed, the Equipment Manager side tab), so every click runs as the player's own. Clicking
-- those from Terminal's code tainted the character window (its health text then errors on a
-- secret value). Afterwards Terminal only looks for the set's row and points at it.

local function Named(f)
	local ok, n = pcall(function() return f:GetName() end)
	return ok and type(n) == "string" and n or nil
end

local function ManagerPane()
	local pd = _G.PaperDollFrame
	local p = pd and pd.EquipmentManagerPane
	return type(p) == "table" and p or nil
end

local function PaneShown()
	local p = ManagerPane()
	return p and p.IsVisible and p:IsVisible() and true or false
end

--- The Equipment Manager side tab: the one whose pane is the equipment manager (the tabs'
--- order differs between clients), else the one with its tooltip, else this client's name.
local function EquipTab()
	local pane = ManagerPane()
	local get = _G.GetPaperDollSideBarFrame
	for i = 1, 6 do
		for _, fmt in ipairs({ "PaperDollSidebarTab%d", "PaperDollSideBarTab%d" }) do
			local t = _G[fmt:format(i)]
			if type(t) == "table" then
				if pane and get then
					local ok, f = pcall(get, i)
					if ok and f == pane then return t end
				end
				local tip = type(t.tooltip) == "string" and t.tooltip:lower() or ""
				if tip ~= "" and tip == (_G.EQUIPMENT_MANAGER or "Equipment Manager"):lower() then return t end
			end
		end
	end
	local t = _G.PaperDollSideBarTab2 or _G.PaperDollSidebarTab2
	return type(t) == "table" and t or nil
end

--- Is the right-hand pane (with the side tabs) open? The character window keeps that in
--- CharacterFrame.rightPaneCollapsed (and the characterFrameCollapsed setting), which hold
--- while the window is closed. (Guessing from shown flags got it wrong the second time,
--- and the arrow then closed the pane while the tab opened the sets: a half-open window.)
local function RightPaneOpen(tab)
	local cf = _G.CharacterFrame
	if cf and type(cf.rightPaneCollapsed) == "boolean" then return not cf.rightPaneCollapsed end
	local cv = GetCVar and GetCVar("characterFrameCollapsed")
	if cv == "1" or cv == "0" then return cv == "0" end
	-- neither known: read the tab's own shown flags
	local f, n = tab, 0
	while f and f ~= cf and n < 8 do
		if f.IsShown and not f:IsShown() then return false end
		f = f.GetParent and f:GetParent() or nil
		n = n + 1
	end
	return true
end

--- The /click lines that get from wherever the character window is to its equipment sets.
local function ManagerMacro()
	local tab = EquipTab()
	local tabName = tab and Named(tab)
	if not tabName then return nil end
	local lines = {}
	local pd = _G.PaperDollFrame
	if not (pd and pd:IsVisible()) then
		if not _G.CharacterMicroButton then return nil end
		lines[#lines + 1] = "/click CharacterMicroButton"
	end
	local cf = _G.CharacterFrame
	local toggle = (cf and cf.RightPaneToggleButton) or _G.CharacterFrameRightPaneToggleButton
	if toggle and Named(toggle) and not RightPaneOpen(tab) then
		lines[#lines + 1] = "/click " .. Named(toggle)
	end
	lines[#lines + 1] = "/click " .. tabName
	return table.concat(lines, "\n")
end

--- Runs once the equipment sets page is showing: scroll the list to the set and point at it.
local function ShowInManager(e)
	local H = ns.Highlight
	local scrolled = false
	H:When(function()
		local p = ManagerPane()
		if not (p and p:IsVisible()) then return nil end
		local function find()
			return ns.FindFrame(p, function(f)
				if f.setID ~= nil then return f.setID == e.setID end
				if not f.Click then return false end
				if f.GetText then
					local ok, t = pcall(f.GetText, f)
					if ok and t == e.name then return true end
				end
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
		ns:Trace("equipment sets: " .. (PaneShown() and ("no row for " .. tostring(e.name)) or "the equipment sets page isn't showing"))
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
					secondarySecure = { macro = ManagerMacro },
					secondaryIsOpen = PaneShown,
					secondaryAfter = ShowInManager,
					noCombatSecondary = true,
				}
			end
		end
		return out
	end,
})
