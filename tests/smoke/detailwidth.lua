-- (0.62.1, the player at 800 wide: "a lot of space in the detail column... we can get more of the good details
-- showing") a detail longer than its column takes the room its name doesn't use; long names keep NAME_SHARE of it.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local LY = UI.layout
io.write("[detail width: the room a short name leaves]\n")
local Theme = ns.Theme
local wasW = Theme.Get().width
Theme.Set("width", 800)
UI:Open(""); FlushAll()
local base, span = LY.DETAIL_W, LY.SPAN
check(base == 240 and span and span > 600, "800 wide: the detail's column 240, the room for name and detail " .. tostring(span))
local r = { detail = T.Obj("FontString"), label = T.Obj("FontString"), icon = T.Obj("Texture"), kind = T.Obj("FontString") }
-- (the harness's fonts: 7 px a character)
local LONG = ("AH 3s 77c each  ·  x185: 6g 97s 45c  ·  vendor 1s 66c")
r.label:SetText("Exploding Shot"); r.detail:SetText(LONG)
UI.FitDetail(r)
check(r.detailW == #LONG * 7 + 2, "a short name: the detail as wide as it is (" .. tostring(r.detailW) .. " for " .. (#LONG * 7) .. ")")
r.label:SetText(("A very long item name that goes on and on and on"):rep(2)); r.detail:SetText(LONG:rep(3))
UI.FitDetail(r)
local nameRoom = span - r.detailW - 8
check(math.abs(nameRoom - math.floor(span * UI.NAME_SHARE)) <= 1, "both long: the name keeps " .. UI.NAME_SHARE * 100 .. "%: " .. nameRoom .. " of " .. span)
r.label:SetText("Linen Cloth"); r.detail:SetText("x20  Backpack")
UI.FitDetail(r)
check(r.detailW == base, "a short detail: its column as before")
-- the rows drawn: a long detail beside a short name gets its room
local saved = { providers = ns.providers, order = ns.providerOrder }
ns.providers, ns.providerOrder = {}, {}
ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
	return { { name = "Exploding Shot", key = 1, detail = LONG }, { name = "Linen Cloth", key = 2, detail = "x20  Backpack" } }
end })
ns:AliasesChanged()
local easy = ns.db.easyMode
ns.db.easyMode = false; UI:EasyChanged()
UI.lastScan, UI.lastExtra = nil, nil
UI:SetQuery("@item ", 6); FlushAll()
local wide, kept
for i = 1, 10 do
	local row = UI.rows[i]
	if row and row.detail:GetText() == LONG then wide = row.detailW end
	if row and row.detail:GetText() == "x20  Backpack" then kept = row.detailW end
end
check(wide and wide > base and kept == base, "drawn: the long detail " .. tostring(wide) .. ", the short one " .. tostring(kept))
UI:Hide(); FlushAll()
ns.providers, ns.providerOrder = saved.providers, saved.order
ns:AliasesChanged()
ns.db.easyMode = easy; UI:EasyChanged()
Theme.Set("width", wasW)
UI.lastScan, UI.lastExtra = nil, nil
