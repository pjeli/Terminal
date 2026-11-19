-- (1.6.10-1.6.14, the design pass: the player's "look at Terminal from a design / aesthetic perspective")
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local Theme = ns.Theme

-- 1.6.10: game icons cropped and framed, an item's frame in its quality colour
io.write("[design: icons cropped, framed in their quality]\n")
do
	local function Row() return { icon = T.Obj("Texture"), iconBorder = T.Obj("Texture") } end
	check(UI.GameIcon(134414) and UI.GameIcon("Interface\\Icons\\INV_Misc_Note_01") and UI.GameIcon("interface/icons/inv_sword_04")
		and not UI.GameIcon("Interface\\GossipFrame\\AvailableQuestIcon") and not UI.GameIcon(nil),
		"game icons: file ids and Interface\\Icons paths, nothing else")
	local k = UI.ICON_CROP
	local r = Row()
	UI.SetIcon(r, { icon = "Interface\\Icons\\INV_Misc_Note_01" })
	check(r.icon.coord and r.icon.coord[1] == k and r.icon.coord[2] == 1 - k and r.iconBorder.shown == true,
		"a game icon: cropped and framed")
	check(r.iconBorder.color and r.iconBorder.color[1] == 0 and r.iconBorder.color[4] == UI.ICON_EDGE[4],
		"not an item: the dark line")
	UI.SetIcon(r, { icon = "Interface\\GossipFrame\\AvailableQuestIcon" })
	check(r.icon.coord[1] == 0 and r.icon.coord[2] == 1 and r.iconBorder.shown == false,
		"the next row's quest mark: whole again, unframed")
	UI.SetIcon(r, { icon = 1, iconCoords = { 0, 0.5, 0, 0.5 } })
	check(r.icon.coord[2] == 0.5 and r.iconBorder.shown == false, "a picture with its own coords keeps them")
	UI.SetIcon(r, { icon = false })
	check(r.icon.shown == false and r.iconBorder.shown == false, "no icon: neither shows")
	-- an epic item: its frame purple; a common one: the dark line
	local C = _G.C_Item
	local was = C.GetItemQualityByID
	C.GetItemQualityByID = function(id) return id == 19019 and 4 or 1 end
	UI.SetIcon(r, { icon = 135349, itemID = 19019 })
	local c = r.iconBorder.color
	check(c and math.abs(c[1] - 0xa3 / 255) < 0.01 and math.abs(c[3] - 0xee / 255) < 0.01 and c[4] == 1, "an epic item: framed purple")
	UI.SetIcon(r, { icon = 135349, itemID = 6948 })
	check(r.iconBorder.color[1] == 0 and r.iconBorder.color[4] == UI.ICON_EDGE[4], "a common item: the dark line")
	C.GetItemQualityByID = was
	-- drawn: the rows have the frame
	check(UI.rows[1] and UI.rows[1].iconBorder, "every row has an icon frame")
end
