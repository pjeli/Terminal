-- Your items (Items.lua, Bags.lua): what's worn and carried is listed, wherever it is; the fallbacks never open the
-- game's windows from Terminal's code. (0.49.2 review: the ranged slot, the keyring, the character window's fallback.)
local T = ...
local ns, check, Obj, FlushAll, names = T.ns, T.check, T.Obj, T.FlushAll, T.names

-- worn: a helm on the head (slot 1) and, where the client has it, a bow in the ranged slot (18)
local LINKS = { [1] = "|cffffffff|Hitem:610|h[Partsy Helm]|h|r", [18] = "|cffffffff|Hitem:609|h[Partsy Bow]|h|r" }
local INSTANT = { [609] = { "Weapon", "Bows", "INVTYPE_RANGED" }, [610] = { "Armor", "Plate", "INVTYPE_HEAD" } }
local function Worn(slots)
	local was = { gsi = _G.GetInventorySlotInfo, gil = _G.GetInventoryItemLink, inst = C_Item.GetItemInfoInstant }
	_G.GetInventorySlotInfo = function(n)
		local id = slots[n]
		if not id then error("Invalid inventory slot in GetInventorySlotInfo") end -- (a slot name the client doesn't know)
		return id
	end
	_G.GetInventoryItemLink = function(_, slot) return LINKS[slot] end
	C_Item.GetItemInfoInstant = function(x)
		local id = tonumber(x) or (type(x) == "string" and tonumber(x:match("item:(%d+)")))
		local i = id and INSTANT[id]
		if i then return id, i[1], i[2], i[3], 1, 2, 2 end
		return was.inst(x)
	end
	ns.providers.items._dirty, ns.providers.gear._dirty = true, true
	return function()
		_G.GetInventorySlotInfo, _G.GetInventoryItemLink, C_Item.GetItemInfoInstant = was.gsi, was.gil, was.inst
		ns.providers.items._dirty, ns.providers.gear._dirty = true, true
	end
end

io.write("[items: a worn ranged weapon (0.49.2 review)]\n")
do
	-- this client's paper doll has a ranged slot (CharacterRangedSlot): bows, guns, wands, thrown, relics
	local restore = Worn({ HeadSlot = 1, MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18 })
	local items = names(ns:GetEntries(ns.providers.items))
	local bow = items["Partsy Bow"]
	check(bow and bow.slotId == 18 and bow.slotName == "RangedSlot", "the bow in the ranged slot is one of your items (worn)")
	local gear = names(ns:GetEntries(ns.providers.gear))
	check(gear["Partsy Bow"] and gear["Partsy Bow"].equipLoc == "INVTYPE_RANGED", "...and of your gear: @gear")
	restore()
	-- a client without the slot: the name errors there; everything else worn is still listed
	restore = Worn({ HeadSlot = 1, MainHandSlot = 16, SecondaryHandSlot = 17 })
	items = names(ns:GetEntries(ns.providers.items))
	check(items["Partsy Helm"] and not items["Partsy Bow"] and items["Hearthstone"],
		"a client that doesn't know the ranged slot: the rest of what you wear and carry is still listed")
	restore()
end

io.write("[items: keys in the keyring (0.49.2 review)]\n")
do
	local was = { ab = _G.C_ActionBar, kr = Enum.BagIndex.Keyring, n = C_Container.GetContainerNumSlots, i = C_Container.GetContainerItemInfo }
	Enum.BagIndex.Keyring = -1
	local shown = true
	_G.C_ActionBar = setmetatable({ ShouldShowKeyring = function() return shown end }, { __index = was.ab or {} })
	local key = { itemID = 5396, itemName = "Partsy Key", iconFileID = 1, stackCount = 1, quality = 1,
		hyperlink = "|cffffffff|Hitem:5396|h[Partsy Key]|h|r" }
	C_Container.GetContainerNumSlots = function(b) if b == -1 then return 4 end return was.n(b) end
	C_Container.GetContainerItemInfo = function(b, s) if b == -1 then return s == 2 and key or nil end return was.i(b, s) end
	ns.providers.items._dirty = true
	local row = names(ns:GetEntries(ns.providers.items))["Partsy Key"]
	check(row and row.locs[1][1] == -1 and row.locs[1][2] == 2 and tostring(row.detail):find("Keyring", 1, true),
		"a key on your keyring is one of your items, said to be there: " .. tostring(row and row.detail))
	local locs = ns.Bags.Locations(5396)
	check(#locs == 1 and locs[1][1] == -1 and locs[1][2] == 2, "...and found there to be shown (@stored's Enter, the chains)")
	check(names(ns:GetEntries(ns.providers.items))["Hearthstone"], "your bags are read as before")
	-- a client that shows no keyring: not read
	shown = false
	ns.providers.items._dirty = true
	check(not names(ns:GetEntries(ns.providers.items))["Partsy Key"] and #ns.Bags.Locations(5396) == 0, "no keyring shown: not read")
	_G.C_ActionBar, Enum.BagIndex.Keyring = was.ab, was.kr
	C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = was.n, was.i
	ns.providers.items._dirty = true
end

io.write("[items: a worn piece with no route to the character window (0.49.2 review)]\n")
do
	-- Enter's own fallback (no character key or button, the press couldn't be made): never ToggleCharacter from Terminal's
	-- code (the character window then held what it wrote); said, or the slot pointed at when the equipment page shows
	local restore = Worn({ HeadSlot = 1 })
	local was = { tc = _G.ToggleCharacter, cf = _G.CharacterFrame, pdf = _G.PaperDollFrame, print = ns.Print, show = ns.Highlight.Show,
		slot = _G.CharacterHeadSlot }
	local toggled, said, shown = false, nil, nil
	_G.ToggleCharacter = function() toggled = true end
	_G.CharacterFrame = Obj("Frame"); CharacterFrame.shown = false
	_G.PaperDollFrame = Obj("Frame"); PaperDollFrame.shown = false
	_G.CharacterHeadSlot = Obj("Button"); CharacterHeadSlot.shown = true
	ns.Print = function(_, msg) said = msg end
	ns.Highlight.Show = function(_, target) shown = target end
	local helm = names(ns:GetEntries(ns.providers.items))["Partsy Helm"]
	if helm then helm.activate(helm) end
	FlushAll()
	check(helm and not toggled and said and said:find("Open your character window", 1, true) and shown == nil,
		"the equipment page not showing: said where to open it, nothing opened from here: " .. tostring(said))
	said = nil
	PaperDollFrame.shown = true
	if helm then helm.activate(helm) end
	FlushAll()
	check(not toggled and said == nil and shown == CharacterHeadSlot, "showing: its slot pointed at")
	_G.ToggleCharacter, _G.CharacterFrame, _G.PaperDollFrame, ns.Print = was.tc, was.cf, was.pdf, was.print
	ns.Highlight.Show, _G.CharacterHeadSlot = was.show, was.slot
	restore()
end
