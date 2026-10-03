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

-- Where the equipment sets live in the character window, depending on the client's layout:
-- the retail/Cataclysm side tabs (third tab: equipment manager pane), or the Wrath-style
-- "Equipment Manager" button that opens the GearManagerDialog.
local PANES = {
	function() return _G.PaperDollFrame and _G.PaperDollFrame.EquipmentManagerPane end,
	function() return _G.PaperDollEquipmentManagerPane end,
	function() return _G.GearManagerDialog end,
}
-- this client (Forever): the Equipment Manager is the second side tab
local TABS = { "PaperDollSideBarTab2", "PaperDollSidebarTab2" }
-- other clients, tried only when no tab is found by its tooltip
local OPENERS = { "PaperDollSidebarTab3", "GearManagerToggleButton" }
-- the arrow that opens the character window's right-hand pane (with the side tabs)
local EXPANDERS = { "CharacterFrameRightPaneToggleButton", "CharacterFrameExpandButton" }

local function Pane()
	for _, get in ipairs(PANES) do
		local ok, p = pcall(get)
		if ok and type(p) == "table" and p.IsVisible and p:IsVisible() then return p end
	end
end

local function Named(f)
	local ok, n = pcall(function() return f:GetName() end)
	return ok and type(n) == "string" and n or nil
end

--- For .debug: the character window's named buttons that look like tabs or the gear manager.
local function DescribeButtons()
	local names = {}
	local function walk(f, depth)
		if not f or depth > 4 or not f.GetChildren then return end
		for _, c in ipairs({ f:GetChildren() }) do
			local n = Named(c)
			if n and (n:find("Tab") or n:find("Gear") or n:find("Equip") or n:find("Sidebar")) then
				names[#names + 1] = n .. ((c.IsVisible and c:IsVisible()) and "" or " (hidden)")
			end
			walk(c, depth + 1)
		end
	end
	walk(_G.CharacterFrame, 0)
	return #names > 0 and table.concat(names, ", ") or "none found"
end

--- A button in the character window that opens the equipment sets. First the side tab or
--- button whose tooltip is "Equipment Manager" (the tabs' order differs between clients),
--- then known names.
local function Shown(f) return f and f.Click and f.IsVisible and f:IsVisible() end

local function FindOpener(byName)
	for _, n in ipairs(TABS) do
		if Shown(_G[n]) then return _G[n], n end
	end
	local want = { (_G.EQUIPMENT_MANAGER or "Equipment Manager"):lower(), "equipment manager", "equipment set", "gear set" }
	local hit = ns.FindFrame(_G.CharacterFrame, function(f)
		if not f.Click then return false end
		local texts = { f.tooltip, f.tooltipText, f.GetText and select(2, pcall(f.GetText, f)) or nil }
		for _, t in ipairs(texts) do
			if type(t) == "string" then
				t = t:lower()
				for _, w in ipairs(want) do if t:find(w, 1, true) then return true end end
			end
		end
		return false
	end, 8)
	if hit then return hit, Named(hit) or "the Equipment Manager button" end
	if not byName then return nil end
	for _, n in ipairs(OPENERS) do
		local b = _G[n]
		if b and b.Click and b.IsVisible and b:IsVisible() then return b, n end
	end
end

--- The character window's expand arrow: on this client the side tabs (with the Equipment
--- Manager) only show once the window is expanded.
local function FindExpander()
	local cf = _G.CharacterFrame
	for _, n in ipairs(EXPANDERS) do
		if Shown(_G[n]) then return _G[n] end
	end
	return ns.FindFrame(cf, function(f)
		local n = Named(f)
		return f.Click and n and (n:find("ExpandButton") or n:find("PaneToggle")) and true or false
	end, 6)
end

--- Runs once the character window is open: switch to its equipment sets page, scroll the
--- list to the set and point at it (nothing is equipped).
--- Presses the right-pane arrow, once. Only a plain :Click(): running the button's own
--- handlers or the window's expand function from Terminal's code tainted the character
--- window (Blizzard's health text then errors on a secret value the next time it opens).
local function PressExpander(x)
	ns:Trace("equipment sets: expanding the character window (" .. tostring(Named(x) or "arrow") .. ")")
	pcall(x.Click, x, "LeftButton")
end

local run = 0 -- each Shift+Enter starts a new run; older ones stop

local function ShowInManager(e)
	local H = ns.Highlight
	run = run + 1
	local mine = run
	local clicked, expanded = false, false
	-- stop as soon as the window is closed again (a second Shift+Enter toggles it shut) or
	-- another Shift+Enter has started: never click in a window that's going away
	local function gone() return mine ~= run or not PaperDollOpen() or InCombatLockdown() end
	local function open()
		if clicked or gone() or Pane() then return end
		local b, name = FindOpener(false)
		local x = not b and FindExpander()
		if x then
			-- collapsed window: expand it first; the tabs appear and are found on a later try
			if not expanded then
				expanded = true
				PressExpander(x)
			end
			return
		end
		if not b then b, name = FindOpener(true) end
		if b then
			clicked = true
			ns:Trace("equipment sets: clicking " .. tostring(name))
			pcall(b.Click, b)
		elseif not e._noOpener then
			e._noOpener = true
			ns:Trace("equipment sets: no Equipment Manager button found yet")
		end
	end
	open()
	local scrolled = false
	H:When(function()
		if gone() then return { stopped = true } end
		open() -- the window may still be building its buttons
		local p = Pane()
		if not p then return nil end
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
		if row.stopped then ns:Trace("equipment sets: window closed or replaced, stopped") return end
		H:Show(row)
	end, 20, function()
		ns:Trace("equipment sets: " .. (Pane() and ("no row for " .. tostring(e.name)) or "the equipment sets page didn't open")
			.. "; character window buttons: " .. DescribeButtons())
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
