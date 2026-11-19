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

-- 1.6.11: Forever's names parchment-white, matched letters gold; an untouched saved Forever theme takes them
io.write("[design: Forever's names and matched letters]\n")
do
	local P = Theme.PRESETS.forever
	check(P.text ~= P.match and P.match == "ffd100" and Theme.DEFAULTS.text == P.text and Theme.DEFAULTS.match == P.match,
		"Forever: names and matched letters apart, the defaults the same")
	local was = ns.db.theme
	ns.db.theme = { v = 4, preset = "forever", text = "ffd100", match = "ffffff", dim = "c9c2b0", bg = "47331f" }
	local t = Theme.Get()
	check(t.v == 5 and t.text == P.text and t.match == P.match and t.dim == P.dim, "an untouched Forever theme from 1.6.10: the new colours")
	ns.db.theme = { v = 4, preset = "forever", text = "ffd100", match = "ff0000", dim = "c9c2b0" }
	t = Theme.Get()
	check(t.v == 5 and t.text == "ffd100" and t.match == "ff0000", "a tuned one: kept as it was")
	ns.db.theme = { v = 4, preset = "midnight", text = "ffd100", match = "ffffff", dim = "c9c2b0" }
	check(Theme.Get().text == "ffd100", "another preset: kept")
	ns.db.theme = was
	Theme.Get()
end

-- 1.6.12: the kind column quiet: the name in the details' colour after a dot of the kind's colour, the selected row's in it
io.write("[design: the kind column]\n")
do
	local r = { kind = T.Obj("FontString"), kindDot = T.Obj("Texture") }
	local shownWas = UI.layout.kindShown
	UI.layout.kindShown = true -- (the column shown: 1.6.16 hides it for one kind asked for)
	UI.SetKind(r, { kindLabel = "|cff9d7bffSpell|r" }, false)
	check(r.kind:GetText() == "Spell" and r.kindDot.shown == true and r.kindDotHex == "9d7bff", "a row: its kind plain, a dot in its colour")
	UI.SetKind(r, { kindLabel = "|cff9d7bffSpell|r" }, true)
	check(r.kind:GetText() == "|cff9d7bffSpell|r" and r.kindDot.shown == true, "the selected row: its kind in its colour")
	UI.SetKind(r, { kindLabel = "" }, false)
	check(r.kind:GetText() == "" and r.kindDot.shown == false, "no kind: no dot")
	UI.SetKind(r, { kindLabel = "plain" }, false)
	check(r.kind:GetText() == "plain" and r.kindDot.shown == false, "a kind without a colour: no dot")
	UI.layout.kindShown = shownWas
	-- drawn: the selection's row coloured, the others plain, and the colour follows the selection
	local saved = { providers = ns.providers, order = ns.providerOrder }
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("spells", { label = "Spell", aliases = { "spell" }, color = "ff9d7bff", collect = function()
		return { { name = "Charge", key = 1 }, { name = "Cleave", key = 2 }, { name = "Rend", key = 3 } }
	end })
	ns:AliasesChanged()
	local easy = ns.db.easyMode
	ns.db.easyMode = false; UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	-- (a plain search: "@spell" asks for one kind, and its column is hidden since 1.6.16)
	UI:SetQuery("e", 1); FlushAll()
	local rows = UI.rows
	local function Coloured(i) return (rows[i].kind:GetText() or ""):find("|cff9d7bff", 1, true) ~= nil end
	check(UI.sel == 1 and Coloured(1) and not Coloured(2) and rows[2].kind:GetText() == "Spell" and rows[2].kindDot.shown == true,
		"drawn: the selected row's kind coloured, the next plain with its dot")
	UI:Move(1); FlushAll()
	check(UI.sel == 2 and Coloured(2) and not Coloured(1), "the colour follows the selection")
	UI:Hide(); FlushAll()
	ns.providers, ns.providerOrder = saved.providers, saved.order
	ns:AliasesChanged()
	ns.db.easyMode = easy; UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
end

-- 1.6.14: the classic frame's depth: the stone grain in a lighter shade of the background, a shade toward the bottom
io.write("[design: the classic frame's depth]\n")
do
	local was = CopyTable(Theme.Get()) -- (put back whole: a colour set makes the theme "custom")
	UI:Open(""); FlushAll()
	Theme.Set("frame", "classic")
	check(UI.grain and UI.grain.shown == true and UI.grain.lastPoint, "the classic frame: its grain shows")
	local bg = { Theme.RGB(Theme.Darken(Theme.Get().bg, UI.GRAIN_LIGHTEN)) }
	local c = UI.grainColor
	check(c and math.abs(c[1] - bg[1]) < 0.01 and math.abs(c[3] - bg[3]) < 0.01 and c[4] < 0.5, "in a lighter shade of the background, faint")
	Theme.Set("bg", "102030")
	check(math.abs(UI.grainColor[3] - math.min(1, 0x30 * UI.GRAIN_LIGHTEN / 255)) < 0.01, "a new background: the grain follows it")
	Theme.Set("frame", "flat")
	check(UI.grain.shown == false and UI.shade.shown == false, "the flat frame stays flat")
	UI:Hide(); FlushAll()
	ns.db.theme = was
	Theme.Changed()
end

-- 1.6.16: the kind column on one line, its dot in a gap of its own; hidden when the search asked for one kind
io.write("[design: the kind column's width, and hidden for one kind asked for]\n")
do
	local LY = UI.layout
	local saved = { providers = ns.providers, order = ns.providerOrder }
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("missingrecipes", { label = "Recipe to Learn", aliases = { "learnable" }, color = "ff9ec9b4", collect = function()
		return { { name = "Crispy Bat Wing", key = 1, detail = "Cooking 1  ·  Vendor" }, { name = "Peace Tea", key = 2, detail = "Cooking 25  ·  Trainer" } }
	end })
	ns:RegisterProvider("spells", { label = "Spell", aliases = { "spell" }, color = "ff9d7bff", collect = function()
		return { { name = "Cleave", key = 1, detail = "Rank 1" } }
	end })
	ns:AliasesChanged()
	local easy = ns.db.easyMode
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open(""); FlushAll()
	UI:ApplyTheme()
	-- (the harness's fonts: 7 px a character; "Recipe to Learn" is 15)
	check(UI.KIND_W == 15 * 7 + 2 and UI.rows[1].kind.w == UI.KIND_W, "the column as wide as the widest kind's name: " .. tostring(UI.KIND_W))
	UI.lastScan, UI.lastExtra = nil, nil
	UI:SetQuery("@learnable ", 11); FlushAll()
	local r1 = UI.rows[1]
	check(LY.kindShown == false and r1.kind:GetText() == "" and r1.kindDot.shown == false and r1.kind.w == 1,
		"one kind asked for (@learnable), every row of it: the column hidden")
	check(r1.detail.lastPoint and r1.detail.lastPoint[4] == 0 and LY.SPAN == LY.SPAN_BASE - 9 - 8,
		"the names and details take its room")
	UI.lastScan, UI.lastExtra = nil, nil
	UI:SetQuery("c", 1); FlushAll()
	check(LY.kindShown == true and #UI.Results() >= 2, "a plain search: the column shows")
	local row
	for i = 1, 10 do if UI.rows[i] and (UI.rows[i].kind:GetText() or ""):find("Recipe to Learn", 1, true) then row = UI.rows[i] end end
	local dp = row and row.kindDot.lastPoint
	check(dp and dp[2] == row.kind and dp[4] == -(15 * 7 + 5) and 15 * 7 + 5 + UI.KIND_DOT_SIZE < UI.KIND_W + UI.KIND_GAP,
		"the dot before the name, inside the gap before the details: " .. tostring(dp and dp[4]))
	check(row.detail.lastPoint[4] == -UI.KIND_GAP, "the details end before the gap")
	UI:Hide(); FlushAll()
	ns.providers, ns.providerOrder = saved.providers, saved.order
	ns:AliasesChanged()
	ns.db.easyMode = easy; UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	UI:ApplyTheme()
end
