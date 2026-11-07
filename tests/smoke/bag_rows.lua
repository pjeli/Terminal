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
