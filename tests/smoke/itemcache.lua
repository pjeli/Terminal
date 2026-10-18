-- An item's bind type is asked of the game once, not on every Items list made again (review, 0.57.7): each bag item not
-- tied to a quest asked GetItemInfo again after every BAG_UPDATE_DELAYED.
local T = ...
local ns, check = T.ns, T.check

io.write("[items: a bag item's bind type asked once]\n")
do
	local was, calls = C_Item.GetItemInfo, 0
	C_Item.GetItemInfo = function(id)
		calls = calls + 1
		return "x", "l", 1, 1, 1, "t", "s", 1, "", 1, 1, 15, 0, 1 -- (14th: binds when picked up)
	end
	local P = ns.providers.items
	P._dirty = true
	ns:GetEntries(P)
	local first = calls
	P._dirty = true
	ns:GetEntries(P)
	-- (other reads ask GetItemInfo too, a name not cached yet: the second time only those)
	check(first > 0 and calls - first < first, "made again: the bind types not asked again: " .. first .. " then " .. (calls - first))
	C_Item.GetItemInfo = was
	P._dirty = true
end

-- (review, 0.57.7) with Syndicator's records in use and its callbacks heard, the game's bag events don't make @stored again
-- (Syndicator says, after it has read them); with BagBrother's, they still do
io.write("[stored: Syndicator's callbacks, not the game's bag events]\n")
do
	local S, p = ns.Stored, ns.providers.stored
	local save = { hooked = S.hooked, source = S.Source }
	S.hooked, S.Source = true, function() return "Syndicator" end
	check(p.ignoreEvent("BAG_UPDATE_DELAYED") == true, "Syndicator in use: a bag event left to its callback")
	S.Source = function() return "BagBrother" end
	check(not p.ignoreEvent("BAG_UPDATE_DELAYED"), "BagBrother's records: the bag event makes the list again")
	S.hooked, S.Source = save.hooked, save.source
end
