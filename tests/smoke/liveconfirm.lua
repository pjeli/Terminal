-- (release review, 0.53.0) a list that changes several times while shown: each change is searched again and F5 brings
-- the newest. A new candidate (0.52.9: offered once sure) counts as something new, and its checks are its own, so neither
-- runs out while the list keeps changing.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll

io.write("[live lists: several changes in a row, F5 has the newest]\n")
local save = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode, time = _G.GetTime }
local rows = {}
for i = 1, 30 do rows[i] = { name = ("Linen Cloth %02d"):format(i), itemID = 50000 + i, key = i } end
local function Collect() local out = {} for i, r in ipairs(rows) do out[i] = r end return out end
ns.providers, ns.providerOrder = {}, {}
ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = Collect })
ns.db.easyMode = false
UI:EasyChanged()
_G.GetTime = function() return T.clock() end
UI.lastScan, UI.lastExtra = nil, nil
UI:Open("linen")
FlushAll()
local function HeldHas(name)
	for _, e in ipairs(UI.held or {}) do if e.name == name then return true end end
	return false
end
-- four loots a few seconds apart: each one ends up in what F5 brings
for k = 1, 4 do
	table.insert(rows, 1, { name = "Linen Cloth L" .. k, itemID = 51000 + k, key = 900 + k })
	ns:Changed("items")
	FlushAll()
	check(HeldHas("Linen Cloth L" .. k), ("loot %d of 4 in a row: F5 has it (searched again: %d)"):format(k, UI.live.same))
end
-- and more, a while apart each: past the checks one search had (6), F5 still has the newest
for k = 5, 9 do
	table.insert(rows, 1, { name = "Linen Cloth L" .. k, itemID = 51000 + k, key = 900 + k })
	ns:Changed("items")
	FlushAll()
	if UI.live.redoneAt then UI.live.redoneAt = UI.live.redoneAt - 20 end -- (a while passes)
	check(HeldHas("Linen Cloth L" .. k), ("loot %d: F5 still has the newest"):format(k))
end
UI:ShowNewResults()
local up = false
for _, e in ipairs(UI.Results()) do if e.name == "Linen Cloth L9" then up = true end end
check(up and UI.held == nil, "F5: the newest list up")
UI:Hide(); FlushAll()

ns.providers, ns.providerOrder = save.providers, save.order
ns:AliasesChanged()
UI.lastScan, UI.lastExtra = nil, nil
ns.db.easyMode = save.easy
UI:EasyChanged()
_G.GetTime = save.time
