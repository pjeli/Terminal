-- Ammo on the empty prompt (0.64.2, the player: "a melee with a bow or gun and no arrows or bullets: try: nearest vendor
-- sells:arrow or sells:shot; a hunter: when the quiver or ammo pouch is low")
local T = ...
local ns, check = T.ns, T.check
local E = ns.Easy

io.write("[ammo: where to buy it, suggested]\n")
do
	local save = { slot = _G.GetInventorySlotInfo, id = _G.GetInventoryItemID, info = C_Item.GetItemInfoInstant, C = _G.C_Container,
		class = _G.UnitClass }
	-- items: a bow (2/2), a gun (2/3), a sword (2/7), arrows (6/2), bullets (6/3), a quiver (11/2)
	local CLASS = { [1] = { 2, 2 }, [2] = { 2, 3 }, [3] = { 2, 7 }, [10] = { 6, 2 }, [11] = { 6, 3 }, [20] = { 11, 2 }, [21] = { 11, 3 } }
	local worn, bags, quiver, pouch = {}, {}, nil, false
	_G.GetInventorySlotInfo = function(name) if name == "AmmoSlot" then return 0 end error("no such slot") end
	_G.GetInventoryItemID = function(_, slot) if slot == 20 and quiver then return pouch and 21 or 20 end return worn[slot] end
	C_Item.GetItemInfoInstant = function(id)
		local c = CLASS[id]
		if not c then return nil end
		return id, "x", "y", "z", 1, c[1], c[2]
	end
	_G.C_Container = {
		GetContainerNumSlots = function(bag) if bag == 0 then return #bags end if bag == 1 and quiver then return quiver end return 0 end,
		GetContainerItemInfo = function(bag, s) if bag == 0 and bags[s] then return { itemID = bags[s][1], stackCount = bags[s][2] } end end,
		ContainerIDToInventoryID = function(bag) return 19 + bag end,
	}
	local function Need(cls) return E.AmmoNeed(cls) end

	-- a warrior with a bow and no arrows: arrows; with some: none; a gun and no bullets: shot
	worn = { [18] = 1 }
	bags = {}
	check(Need("WARRIOR") == "arrow", "a warrior with a bow, no arrows: arrows to buy")
	bags = { { 10, 5 } }
	check(Need("WARRIOR") == nil, "some arrows: nothing to buy")
	worn = { [18] = 2 }
	check(Need("ROGUE") == "shot", "a gun and arrows only: bullets to buy")
	worn = { [18] = 3 }
	check(Need("WARRIOR") == nil, "no bow or gun: nothing")
	-- a bow in the main hand (a client with no ranged slot) counts too
	worn = { [16] = 1 }
	bags = {}
	check(Need("WARRIOR") == "arrow", "a bow in the main hand: arrows")

	-- a hunter: low is under a quarter of the quiver (or a stack, without one)
	worn = { [18] = 1 }
	bags = { { 10, 150 } }
	check(Need("HUNTER") == "arrow", "a hunter, 150 arrows and no quiver: low")
	bags = { { 10, 200 }, { 10, 100 } }
	check(Need("HUNTER") == nil, "300 arrows, no quiver: fine")
	quiver = 16 -- (16 slots: 3200 arrows; low under 800)
	check(Need("HUNTER") == "arrow", "300 arrows in a 16-slot quiver: low")
	bags = { { 10, 200 }, { 10, 200 }, { 10, 200 }, { 10, 200 } }
	check(Need("HUNTER") == nil, "800 arrows in a 16-slot quiver: fine")
	-- (an ammo pouch holds bullets: no room for arrows; review, 0.64.3)
	bags, pouch = { { 10, 200 }, { 10, 100 } }, true
	check(Need("HUNTER") == nil, "300 arrows and a 16-slot ammo pouch: fine (the pouch isn't for arrows)")
	quiver, pouch = nil, false

	-- a game with no ammo slot: never
	_G.GetInventorySlotInfo = function() error("no such slot") end
	bags = {}
	check(Need("HUNTER") == nil and Need("WARRIOR") == nil, "no ammo slot in the game: nothing to buy")
	_G.GetInventorySlotInfo = function() return nil end -- (a client that answers nothing rather than an error)
	check(Need("HUNTER") == nil and Need("WARRIOR") == nil, "an ammo slot the game doesn't name: nothing to buy")
	_G.GetInventorySlotInfo = function(name) if name == "AmmoSlot" then return 0 end error("no such slot") end

	-- the suggestion itself: Simple mode's words, Advanced's syntax, offered more often than the others
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	worn, bags = { [18] = 2 }, {}
	local I = ns.Integrations
	local missing = I.AddonMissing
	I.AddonMissing = function() return false end -- (Questie here)
	local found, adv
	for _, x in ipairs(E.PersonalTagged(false)) do if x[1] == "nearest vendor sells:shot" then found = x end end
	local hadNpc = ns.providers.npc
	if not hadNpc then ns:RegisterProvider("npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = function() return {} end }) end
	for _, x in ipairs(E.PersonalTagged(true)) do if x[1] == "@npc is:vendor sells:shot sort:nearest" then adv = x end end
	if not hadNpc then
		ns.providers.npc = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "npc" then table.remove(ns.providerOrder, i) end end
		ns:AliasesChanged()
	end
	check(found and found.todo, "try: nearest vendor sells:shot, as pressing")
	check(adv, "Advanced: @npc is:vendor sells:shot sort:nearest")
	bags = { { 11, 200 } }
	found = nil
	for _, x in ipairs(E.PersonalTagged(false)) do if x[1]:find("sells:", 1, true) then found = x end end
	check(not found, "bullets bought: not suggested")
	-- (the pool shown on the empty prompt: made again when your bags change, not a minute on; review, 0.64.3)
	local easy = ns.db.easyMode
	ns.db.easyMode = true
	bags = {}
	E.OnBags(); E.ammoShown = "x"; E.OnBags()
	local function Offered()
		for _, l in ipairs(E.ExamplePool()) do if l:find("sells:shot", 1, true) then return true end end
		return false
	end
	check(Offered(), "no bullets: the empty prompt offers where to buy them")
	bags = { { 11, 200 } }
	E.OnBags()
	check(not Offered(), "bullets bought: the next open doesn't offer it")
	ns.db.easyMode = easy
	I.AddonMissing = missing

	_G.GetInventorySlotInfo, _G.GetInventoryItemID, C_Item.GetItemInfoInstant, _G.C_Container, _G.UnitClass =
		save.slot, save.id, save.info, save.C, save.class
end
