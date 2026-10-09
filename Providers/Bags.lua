local ns = select(2, ...)
local H = ns.Highlight

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

local function NumOf(f, method)
	local fn = f[method]
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, f)
	return ok and type(v) == "number" and v or nil
end

--- A bag button for bag/slot: Blizzard's and Baganator's answer GetBagID, Bagnon's GetBag.
local function IsSlot(f, bag, slot)
	local b = NumOf(f, "GetBagID") or NumOf(f, "GetBag")
	return b == bag and NumOf(f, "GetID") == slot
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
Bags.Show = ShowInBags -- (Items.lua: an Item result's Enter)

--- Open your bags on an item you carry and point at it, as an Item result does. False when you
--- don't carry it (then nothing opens).
function Bags.ShowItem(itemID, link, name)
	local locs = Bags.Locations(itemID)
	if #locs == 0 then return false end
	ShowInBags({ name = name, link = link, locs = locs })
	return true
end
