-- Chains (Pipes.lua, 0.43.12): "thorium belt > mats", "mats for thorium belt", walking on, the footer's trail
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local P = ns.Pipes

local saved = { providers = ns.providers, order = ns.providerOrder, name = C_Item.GetItemNameByID, count = C_Item.GetItemCount,
	AL = _G.AtlasLoot, field = ns.Integrations.ItemField, npc = ns.Integrations.NpcRow, obj = ns.Integrations.ObjectName,
	quest = ns.Integrations.QuestRow }
local NAMES = { [12359] = "Thorium Bar", [7077] = "Heart of Fire", [12655] = "Enchanted Thorium Bar", [12406] = "Thorium Belt",
	[2840] = "Copper Bar", [2857] = "Chain Belt", [2770] = "Copper Ore", [3575] = "Iron Bar", [9999] = "Other Belt" }
C_Item.GetItemNameByID = function(id) return NAMES[id] end
local COUNT = { [12359] = 4, [2840] = 30 }
C_Item.GetItemCount = function(id, bank) return (COUNT[id] or 0) + (bank and id == 12359 and 2 or 0) end
-- AtlasLoot's crafting data: Copper Bar is smelted from ore, Chain Belt is made of copper bars
local SPELL = { [2840] = 2657, [2857] = 2661, [12406] = 16645 }
local DATA = { [2657] = { 2840, 7, nil, nil, nil, { 2770 }, { 1 } }, [2661] = { 2857, 2, nil, nil, nil, { 2840 }, { 4 } },
	[16645] = { 12406, 2, nil, nil, nil, { 12359, 7077 }, { 12, 2 } } }
_G.AtlasLoot = { Data = { Profession = {
	GetCraftSpellForCreatedItem = function(id) return SPELL[id] end,
	GetProfessionData = function(s) return DATA[s] end,
} } }
-- Questie: who sells and drops what
local FIELDS = { [12359] = { vendors = { 501 } }, [2770] = { objectDrops = { 1731 }, npcDrops = { 502 } } }
ns.Integrations.ItemField = function(id, f) return FIELDS[id] and FIELDS[id][f] end
ns.Integrations.NpcRow = function(id) return id == 501 and { kind = "npc", key = 501, name = "Thorium Trader", detail = "Vendor" }
	or id == 502 and { kind = "npc", key = 502, name = "Ore Golem", detail = "Elemental" } or nil end
ns.Integrations.ObjectName = function(id) return id == 1731 and "Copper Vein" or nil end
ns.Integrations.QuestRow = function() return nil end

local function Rows(list) return function() local out = {} for i, r in ipairs(list) do local e = {} for k, v in pairs(r) do e[k] = v end e.key = e.key or i out[i] = e end return out end end
ns.providers, ns.providerOrder = {}, {}
local recipe0 = { name = "Copper Chain", recipeID = 1, makesItem = 1, reagents = { { 2770, 1 } } }
local recipe = { name = "Thorium Belt", recipeID = 16645, makesItem = 12406, reagents = { { 12359, 12 }, { 7077, 2 } }, detail = "Blacksmithing" }
ns:RegisterProvider("recipes", { label = "Recipe", aliases = { "recipe" }, collect = Rows({ recipe, recipe0,
	{ name = "Thorium Belt of Doom", recipeID = 99, makesItem = 9999, reagents = { { 3575, 1 } } } }) })
ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = Rows({ { name = "Copper Bar", itemID = 2840 } }) })
ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = Rows({ { name = "Chain Belt", itemID = 2857, detail = "Blacksmithing  Crafting" } }) })
ns:RegisterProvider("stored", { label = "Stored", aliases = { "stored" }, collect = Rows({}) })

P.ClearCrafts(); P.ClearSteps()
do
	check(P.Canonical("mats for thorium belt") == "thorium belt > mats" and P.Canonical("what uses copper bar") == "copper bar > uses"
		and P.Canonical("where to get thorium bar") == "thorium bar > sources" and P.Canonical("Thorium Belt > mats") == "Thorium Belt > mats",
		"plain words and links read as chains")
	check(P.Canonical("thorium belt") == nil and P.Canonical("hogger >> party") == nil and P.Canonical("@item lvl:>20") == nil
		and P.Canonical("where should i level") == nil, "other searches aren't chains")
	-- mats: only the exact recipe (not every belt), with how many you have
	local rows, trail = P.Search("thorium belt > mats")
	check(#rows == 2 and trail == "thorium belt > mats", "thorium belt > mats: two reagents: " .. #rows .. " " .. tostring(trail))
	local bar
	for _, r in ipairs(rows) do if r.itemID == 12359 then bar = r end end
	check(bar and bar.detail:find("need 12", 1, true) and bar.detail:find("have 4", 1, true) and bar.detail:find("+2 bank", 1, true),
		"a reagent: need, have, bank: " .. tostring(bar and bar.detail))
	-- through the search, in Simple words, with the trail in the footer
	local res = UI:SearchText("mats for thorium belt")
	check(#res == 2 and UI.pipeTrail == "thorium belt > mats", "mats for thorium belt: the mats, the trail: " .. tostring(UI.pipeTrail))
	-- walking on: Enter on a reagent = where to get it
	check(bar.pipeChain == "thorium belt > mats Thorium Bar > sources", "Enter on a reagent walks on: " .. tostring(bar.pipeChain))
	rows, trail = P.Search(bar.pipeChain)
	check(trail == "thorium belt > mats > Thorium Bar > sources" and rows[1] and rows[1].name == "Thorium Trader"
		and rows[1].detail:find("Sells it", 1, true), "sources: who sells it: " .. tostring(trail))
	-- used in: what copper bar goes into (AtlasLoot's crafts), then that one's mats
	rows, trail = P.Search("copper bar > used in chain belt > mats")
	check(trail == "copper bar > used in > chain belt > mats" and #rows == 1 and rows[1].name == "Copper Bar"
		and rows[1].detail:find("need 4", 1, true), "copper bar > used in > chain belt > mats: " .. tostring(trail))
	-- and on: copper bar's sources: crafted (smelted), and its ore's
	rows = P.Search("copper bar > sources")
	check(rows[1] and rows[1].detail:find("Crafted", 1, true) and rows[1].pipeNext == "mats", "copper bar > sources: crafted, and Enter goes to its mats")
	rows = P.Search("copper ore > sources")
	local vein, golem
	for _, r in ipairs(rows) do if r.name == "Copper Vein" then vein = r elseif r.name == "Ore Golem" then golem = r end end
	check(vein and golem and golem.detail:find("Drops it", 1, true), "copper ore > sources: the vein and who drops it")
	-- picking a link
	rows = P.Search("thorium belt > ")
	local names = {}
	for _, r in ipairs(rows) do names[#names + 1] = r.name end
	check(table.concat(names, ","):find("mats", 1, true) and rows[1].completion, "after > : the links that fit, to pick: " .. table.concat(names, ","))
	rows = P.Search("thorium belt > zzz")
	check(#rows == 1 and rows[1].noActivate, "an unknown link says so")
	rows = P.Search("zzqq belt > mats")
	check(#rows == 1 and rows[1].noActivate and rows[1].name:find("Nothing called", 1, true), "nothing to start from: says so")
	-- a name still being typed isn't looked up yet
	rows = P.Search("t > sources")
	check(#rows == 1 and rows[1].noActivate and rows[1].name:find("Keep typing", 1, true), "under 3 letters: keep typing")
	-- a reagent the client hasn't loaded: asked for, and the search runs again (Filters.loading)
	ns.Filters.loading = nil
	NAMES[7077] = nil
	P.ClearSteps()
	rows = P.Search("thorium belt > mats")
	check(#rows == 1 and ns.Filters.loading == true, "a reagent not loaded yet: searched again in a moment")
	NAMES[7077] = "Heart of Fire"
	rows = P.Search("thorium belt > mats")
	check(#rows == 2, "loaded: both reagents (nothing kept from the incomplete answer)")
	ns.Filters.loading = nil
	-- sent to chat with what the chain says (0.43.19): "Mats for Thorium Belt: 12x [Thorium Bar]"
	local SH = ns.Share
	rows = P.Search("thorium belt > mats")
	bar = nil
	for _, r in ipairs(rows) do if r.itemID == 12359 then bar = r end end
	local line = bar and SH.Line(bar, "mats for thorium belt") or ""
	check(line:find("^Mats for Thorium Belt: 12x ") and line:find("Thorium Bar", 1, true), "a reagent sent: its chain and count: " .. line)
	local mac = bar and SH.Macro(bar, { cmd = "/p", query = "thorium belt > mats" }) or ""
	check(mac:find("^/p Mats for Thorium Belt: 12x ") ~= nil, "the chat line too: " .. mac)
	rows = P.Search("thorium bar > sources")
	line = rows[1] and SH.Line(rows[1], "where to get thorium bar") or ""
	check(line == "Where to get Thorium Bar: sold by Thorium Trader", "a source sent: how it gives it: " .. line)
	rows = P.Search("copper bar > used in")
	line = rows[1] and SH.Line(rows[1], "what uses copper bar") or ""
	check(line == "Copper Bar is used in: Chain Belt", "used in, sent (an AtlasLoot crafting page isn't \"dropped by\"): " .. line)
	check(SH.Line({ name = "Hearthstone" }, "hearth") == "Hearthstone", "a row not from a chain: as before")
	-- several rows passed on: the words typed name them
	check(P.FromName({ { name = "A" }, { name = "B" } }, "@recipe copper q:rare") == "Copper" and P.FromName({ { name = "Copper Bar x3" } }) == "Copper Bar",
		"what a link came from: the one row, else the words typed")
	-- Shift+Enter on a walking row does the row's own thing, and closes
	local opened
	local r0 = { name = "X", kind = "recipes", reagents = { { 1, 1 } }, activate = function() opened = true end }
	local v = P.WalkView(r0, "a > uses", "uses")
	check(v.pipeNext == "mats" and v.staysOpen and v.secondaryStaysOpen == false, "a walking row: Enter stays, Shift+Enter closes")
	v.secondary(v)
	check(opened, "Shift+Enter runs the row's own Enter")
end

ns.providers, ns.providerOrder = saved.providers, saved.order
ns:AliasesChanged()
C_Item.GetItemNameByID, C_Item.GetItemCount, _G.AtlasLoot = saved.name, saved.count, saved.AL
ns.Integrations.ItemField, ns.Integrations.NpcRow, ns.Integrations.ObjectName, ns.Integrations.QuestRow = saved.field, saved.npc, saved.obj, saved.quest
UI.lastScan, UI.lastOverview = nil, nil
P.ClearCrafts(); P.ClearSteps()
