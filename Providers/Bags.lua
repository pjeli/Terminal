local ns = select(2, ...)
local L = ns.L
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
local BAGNON_NAMES = { "Bagnon", "Bagnonium" }
function Bags.Bagnon()
	for _, name in ipairs(BAGNON_NAMES) do
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

--- The keyring's bag id when this client shows one (C_ActionBar.ShouldShowKeyring, as the game's bag bar asks), else nil.
function Bags.Keyring()
	local id = Enum.BagIndex and Enum.BagIndex.Keyring
	local should = C_ActionBar and C_ActionBar.ShouldShowKeyring
	if type(id) ~= "number" or type(should) ~= "function" then return nil end
	local ok, on = pcall(should)
	return ok and not ns.Secret(on) and on == true and id or nil
end

--- Your bags' ids, in order: the backpack to the reagent bag, then the keyring when the client shows one.
function Bags.BagIDs()
	local ids = {}
	for b = 0, LAST_BAG do ids[#ids + 1] = b end
	local k = Bags.Keyring()
	if k then ids[#ids + 1] = k end
	return ids
end

-- The game's own bag windows are opened by the game, on the Enter press: its Backpack & Bags key (ToggleAllBags, which
-- opens every bag whenever any one of them isn't open). Never from Terminal's code (1.1.6, a friend of the player's
-- "couldn't eat anything"): OpenAllBags / OpenBag from here made the bag windows' item buttons hold the bag number
-- Terminal's code wrote (their "bagid" attribute is written only when it changes), and a right-click on food then
-- reached C_Container.UseContainerItem tainted, which the game blocks for anything that casts (eating, drinking) until
-- a /reload.
Bags.SECURE = { binding = "OPENALLBAGS" }

--- Whether the bags `bags` (ids) show. Read only: IsBagOpen writes nothing.
local function AllOpen(bags)
	if not IsBagOpen then return false end
	for _, b in ipairs(bags) do
		local ok, open = pcall(IsBagOpen, b)
		if not (ok and open) then return false end
	end
	return true
end

--- The bag ids of locations { {bag, slot}, ... }, each once.
local function BagsOf(locs)
	local bags, seen = {}, {}
	for _, loc in ipairs(locs or {}) do
		if not seen[loc[1]] then seen[loc[1]] = true; bags[#bags + 1] = loc[1] end
	end
	return bags
end

--- A row that shows its item in your bags (Enter: `isOpen` with Bags.SECURE): true when Enter has nothing for the game
--- to press: a bag addon's window shows them (Terminal opens that one: its own frames, not Blizzard's), you don't carry
--- it (the row's own step says so), or every bag it's in is open already (the row's step only points at it).
-- (1.1.14, review: a row without its own `locs`, @stored's, the loot log's, a chain's, asked this on every hover and
-- twice for a row with no Shift+Enter of its own: each a scan of every bag slot. Skipped when you carry none (one call
-- to the game), and what a scan found kept until your bags change.)
local scanned = {} -- item id -> its locations, until BAG_UPDATE_DELAYED
local function Carried(id)
	local count = C_Item and C_Item.GetItemCount
	if not count then return true end
	local ok, n = pcall(count, id)
	return not (ok and type(n) == "number" and not ns.Secret(n) and n == 0)
end
function Bags.ShownFor(e)
	if Bags.Active() then return true end
	local locs = e.locs
	if type(locs) ~= "table" or #locs == 0 then
		local id = e.itemID
		if not id or not Carried(id) then return true end
		locs = scanned[id]
		if not locs then locs = Bags.Locations(id); scanned[id] = locs end
	end
	if #locs == 0 then return true end
	return AllOpen(BagsOf(locs))
end
do
	local f = CreateFrame("Frame")
	pcall(f.RegisterEvent, f, "BAG_UPDATE_DELAYED")
	pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", function() scanned = {} end)
	Bags._scanFrame = f -- (tests)
end

--- Row `e` (a plain table whose `activate` shows its item in your bags, through Bags.ShowItem / Bags.Show) given the
--- game's press for the game's own bags: Enter presses their key when they're closed, then runs that same step.
function Bags.Pressed(e)
	e.secure, e.isOpen, e.after = Bags.SECURE, Bags.ShownFor, e.activate
	return e
end

--- Show your bags, in whichever window shows them. bags: the bag ids that must show. A bag addon's window is shown
--- here; the game's own are never opened from here (Bags.SECURE: the game's press does that): false then when one of
--- `bags` is closed (said by the caller).
function Bags.Open(bags)
	local which, A = Bags.Active()
	if which == "Baganator" then
		pcall(A.CallbackRegistry.TriggerEvent, A.CallbackRegistry, "BagShow")
	elseif which then
		pcall(A.Frames.Show, A.Frames, "inventory")
	elseif not AllOpen(bags or { 0 }) then
		ns:Trace("items: the game's bags are closed and Terminal's code doesn't open them (the press does)")
		return which, false
	end
	return which, true
end

-- Baganator's bag windows are named Baganator_<View>BackpackViewFrame<group>: kept once found, looked for again (at
-- most once a second: every name in _G) while none of them shows, as switching its view makes another one. the walk ran
-- on every 0.1 s poll while none was found, and a view made later was never searched.
local baganatorRoots, rootsAt
local function AnyShown(list)
	for _, f in ipairs(list) do
		local ok, shown = pcall(f.IsShown, f)
		if ok and shown then return true end
	end
	return false
end
local function BaganatorRoots()
	local now = GetTime and GetTime() or 0
	if not baganatorRoots or (not AnyShown(baganatorRoots) and (not rootsAt or now - rootsAt >= 1)) then
		rootsAt = now
		baganatorRoots = {}
		for k, v in pairs(_G) do
			if type(k) == "string" and k:find("^Baganator_.*BackpackViewFrame") and type(v) == "table" and v.GetChildren then
				baganatorRoots[#baganatorRoots + 1] = v
			end
		end
	end
	return baganatorRoots
end

ns.Bags._BaganatorRoots = function(reset) -- (tests; `reset`: forget what was found)
	if reset then baganatorRoots, rootsAt = nil, nil end
	return BaganatorRoots()
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
	for _, bag in ipairs(Bags.BagIDs()) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID then locs[#locs + 1] = { bag, slot } end
		end
	end
	return locs
end

ShowInBags = function(e)
	-- (where it is now: the row may be an older list's, kept while a new one waits for F5, and the stack moved or was
	-- sold since; one pass over the bags, on Enter only.)
	local now = e.itemID and Bags.Locations(e.itemID)
	local locs = (now and #now > 0) and now or e.locs
	local bags = BagsOf(locs)
	local which, shown = Bags.Open(#bags > 0 and bags or nil)
	if not shown then
		-- (no press: in a fight, or a client without the bag key's command. Opening them here would taint them)
		ns:Print(L["Open your bags to see %s (opening them from Terminal's own code would taint them)."]:format(tostring(e.name)))
		return
	end
	if which == "Baganator" and e.link then
		-- Baganator's own flash too
		local R = Bags.Baganator().CallbackRegistry
		C_Timer.After(0.2, function() pcall(R.TriggerEvent, R, "HighlightIdenticalItems", e.link) end)
	end
	ns:Trace("items: showing " .. tostring(e.name) .. " in " .. (which or "the game's bags"))
	if not locs then return end
	H:Find(function()
		local found = {}
		for _, loc in ipairs(locs) do
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
