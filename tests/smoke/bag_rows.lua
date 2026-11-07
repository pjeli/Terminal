-- Rows that show an item in your bags (Bags.SECURE, Bags.ShownFor; 1.1.6) asked whether their bags are open on every
-- hover: a row without its own bag places (@stored's, the loot log's, a chain's) scanned every bag slot each time.
-- 1.1.14, review: none carried, no scan; a scan kept until the bags change.
local T = ...
local ns, check = T.ns, T.check
local Bg = ns.Bags

io.write("[bag rows: whether the bags are open, without a scan per hover]\n")
do
	local was = { loc = Bg.Locations, count = C_Item.GetItemCount, open = _G.IsBagOpen }
	local scans, carried = 0, { [2589] = 3 }
	Bg.Locations = function(id) scans = scans + 1 return id == 2589 and { { 0, 4 } } or {} end
	C_Item.GetItemCount = function(id) return carried[id] or 0 end
	local open = {}
	_G.IsBagOpen = function(b) return open[b] or false end
	Bg._scanFrame.scripts.OnEvent(Bg._scanFrame, "BAG_UPDATE_DELAYED") -- (what earlier tests' hovers kept: the mock bags never send it)
	local row = { itemID = 2589, name = "Linen Cloth" } -- (no locs: a chain's or @stored's row)
	check(Bg.ShownFor(row) == false and scans == 1, "carried, the bags closed: the press (one scan)")
	for _ = 1, 5 do Bg.ShownFor(row) end
	check(scans == 1, "hovered again and again: no scan more (" .. scans .. ")")
	open[0] = true
	check(Bg.ShownFor(row) == true and scans == 1, "the bag opened: nothing to press, still no scan")
	Bg._scanFrame.scripts.OnEvent(Bg._scanFrame, "BAG_UPDATE_DELAYED")
	Bg.ShownFor(row)
	check(scans == 2, "the bags changed: scanned again")
	local none = { itemID = 1234, name = "Not Carried" }
	check(Bg.ShownFor(none) == true and scans == 2, "none carried: nothing to press, no scan")
	Bg.Locations, C_Item.GetItemCount, _G.IsBagOpen = was.loc, was.count, was.open
	Bg._scanFrame.scripts.OnEvent(Bg._scanFrame, "BAG_UPDATE_DELAYED")
end

io.write("[bag rows: review 1.1.18: a fight, Ctrl+Enter, bag addons Terminal doesn't know, the keyring, where it is now]\n")
do
	local UI, FlushAll, log, logHas = T.UI, T.FlushAll, T.log, T.logHas
	local was = { count = C_Item.GetItemCount, open = _G.IsBagOpen, loc = Bg.Locations, combat = _G.InCombatLockdown,
		isv = _G.issecurevariable, oab = _G.OpenAllBags, print = ns.Print }
	local where, open, fighting = { { 2, 3 } }, {}, false
	C_Item.GetItemCount = function() return 1 end
	_G.IsBagOpen = function(b) return open[b] or false end
	Bg.Locations = function() return where end
	_G.InCombatLockdown = function() return fighting end
	local said
	ns.Print = function(_, m) said = m end
	local function Fresh() Bg._scanFrame.scripts.OnEvent(Bg._scanFrame, "BAG_UPDATE_DELAYED") end
	local ran = 0
	local row = Bg.Pressed({ itemID = 2589, name = "Linen Cloth", locs = { { 0, 1 } }, activate = function() ran = ran + 1 end })
	-- where it is now, not where the row was made: its own locs say the backpack (open), it's in bag 2 (closed)
	open[0] = true; Fresh()
	check(row.isOpen(row) == false, "the item moved to a closed bag: the press, not the row's old place")
	-- a fight: bags up, nothing to press: its step runs; bags closed: refused, said
	open[2] = true; Fresh()
	fighting = true
	ns.providers.bagrowtest = nil
	local function Run(e, opts)
		local p = { label = "BR", aliases = { "bagrowtest" }, explicit = true, collect = function() return { e } end }
		ns:RegisterProvider("bagrowtest", p); ns:AliasesChanged()
		UI:Open("@bagrowtest linen"); FlushAll()
		UI.sel = 1
		said = nil
		UI:Activate(1, opts)
		FlushAll()
	end
	ran = 0
	Run(row)
	check(ran == 1 and not tostring(said):find("combat", 1, true), "in a fight, its bags up: its step runs: " .. tostring(said))
	open[2] = false; Fresh()
	ran = 0
	Run(row)
	check(ran == 0 and tostring(said):find("combat", 1, true), "in a fight, its bags closed: refused, said: " .. tostring(said))
	fighting = false
	-- Ctrl+Enter with the bags up: the terminal stays
	open[2] = true; Fresh()
	Run(row, { keepOpen = true })
	check(UI:IsShown(), "Ctrl+Enter, the bags up: Terminal stays open")
	UI:Hide(); FlushAll()
	-- a bag addon Terminal doesn't know: the game's bag functions are its own; no press, its OpenAllBags opens it
	open[2] = false; Fresh()
	_G.issecurevariable = function(name) return not (name == "OpenAllBags") end
	local opened = 0
	_G.OpenAllBags = function() opened = opened + 1 end
	check(Bg.AddonOwned() and row.isOpen(row) == true, "an addon's OpenAllBags: nothing for the game to press")
	said = nil
	Bg.ShowItem(2589, nil, "Linen Cloth")
	check(opened == 1 and said == nil, "its window opened by its own OpenAllBags, nothing said")
	_G.issecurevariable, _G.OpenAllBags = was.isv, was.oab
	-- after the game's press: nothing said, even if the bags it opened aren't the game's
	said = nil
	Bg.ShowItem(2589, nil, "Linen Cloth")
	check(said == nil, "with the bag key there, out of a fight: nothing said (the press opened them)")
	-- only on the keyring: the bag key doesn't open it: no press, said
	local keyring = Enum and Enum.BagIndex and Enum.BagIndex.Keyring
	if keyring then
		where = { { keyring, 1 } }; Fresh()
		check(row.isOpen(row) == true, "only on the keyring: no press")
		said = nil
		Bg.ShowItem(2589, nil, "Linen Cloth")
		check(tostring(said):find("Open your bags", 1, true), "and said where to look: " .. tostring(said))
	end
	ns.providers.bagrowtest = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "bagrowtest" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
	C_Item.GetItemCount, _G.IsBagOpen, Bg.Locations, _G.InCombatLockdown, ns.Print = was.count, was.open, was.loc, was.combat, was.print
	Fresh()
end
