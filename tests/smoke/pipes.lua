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
	{ name = "Thorium Belt of Doom", recipeID = 99, makesItem = 9999, reagents = { { 3575, 1 } } },
	{ name = "Comfortable Leather Hat", recipeID = 98, makesItem = 9998, reagents = { { 2770, 12 } } },
	{ name = "Agamaggan's Clutch", recipeID = 97, makesItem = 9997, reagents = { { 2770, 3 } } } }) })
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
	-- never a guess (0.44.4): "core leather belt" isn't Comfortable Leather Hat (c-o-r-e scattered in "Comfortable")
	rows = P.Search("core leather belt > mats")
	check(#rows == 2 and rows[1].noActivate and rows[1].name:find("Nothing called", 1, true)
		and rows[2].name == "Did you mean Comfortable Leather Hat?" and rows[2].completion == "Comfortable Leather Hat > mats",
		"no name with every word: says so, offers the closest (Enter writes it): " .. tostring(rows[2] and rows[2].name))
	res = UI:SearchText("mats for core leather belt")
	check(res[1] and res[1].noActivate and not (res[2] and res[2].itemID), "Simple words too: no mats listed: " .. tostring(res[1] and res[1].name))
	-- several names have every word: which one?
	rows = P.Search("thorium > mats")
	check(rows[1] and rows[1].name:find("names have", 1, true) and #rows == 3 and rows[2].completion
		and rows[2].completion:find("> mats$"), "several names: pick one: " .. tostring(rows[1] and rows[1].name))
	-- one name (the recipe, and maybe its item): its mats; an apostrophe left out still finds it
	rows = P.Search("agamaggans > mats")
	check(#rows == 1 and rows[1].need == 3, "one name, apostrophe left out: its mats: " .. tostring(rows[1] and rows[1].name))
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

-- every result at once (0.44.2): ">>> party", the menu's "All N to party"
do
	local SH = ns.Share
	local q, rest, all = SH.Split("mats for thorium belt >>> party")
	check(q == "mats for thorium belt " and rest == "party" and all == true, ">>> splits off the channel, marked all")
	q, rest, all = SH.Split("copper >>>guild")
	check(rest == "guild" and all, ">>>guild too")
	q, rest, all = SH.Split("copper >> party")
	check(rest == "party" and not all, ">> stays one result")
	local to = SH.Channel("w Bob")
	check(to.chat == "WHISPER" and to.target == "Bob" and SH.Channel("party").chat == "PARTY" and SH.Channel("3").target == 3,
		"channels carry the game's chat type")
	-- mats: one line, the chain said once, each reagent with its count
	local rows = P.Search("thorium belt > mats")
	local lines, n = SH.GroupLines(rows, "thorium belt > mats")
	check(#lines == 1 and n == 2 and lines[1]:find("^Mats for Thorium Belt %(2%): 12x ") and lines[1]:find("2x [^,]*Heart of Fire")
		and select(2, lines[1]:gsub("Mats for", "")) == 1, "mats in one line: " .. tostring(lines[1]))
	-- loot from one boss: the boss said once, not on every item
	local loot = {}
	for i = 1, 5 do loot[i] = { kind = "loot", key = i, name = "Jett Item " .. i, detail = "Lorgus Jett  Blackfathom Deeps" } end
	loot[6] = { name = "hint", noActivate = true }
	lines = SH.GroupLines(loot, "@loot lorgus jett")
	check(#lines == 1 and lines[1] == "Dropped by Lorgus Jett in Blackfathom Deeps (5): Jett Item 1, Jett Item 2, Jett Item 3, Jett Item 4, Jett Item 5",
		"loot: the boss once, hint rows left out: " .. tostring(lines[1]))
	-- a long list: split into lines of at most 255, the rest counted
	local many = {}
	for i = 1, 200 do many[i] = { kind = "item", key = i, name = ("Some Long Item Name Number %03d"):format(i) } end
	lines = SH.GroupLines(many, "item")
	local ok = #lines == SH.GROUP_LINES
	for _, l in ipairs(lines) do ok = ok and #l <= 255 end
	check(ok and lines[#lines]:find("%+%d+ more$"), "many: " .. SH.GROUP_LINES .. " lines of at most 255, the rest counted: " .. tostring(lines[#lines]):sub(-20))
	-- sent by Terminal in the press (a macro the game runs holds 255 characters in all)
	local savedChat = _G.C_ChatInfo
	local sent = {}
	_G.C_ChatInfo = { SendChatMessage = function(msg, chat, lang, target) sent[#sent + 1] = { msg, chat, target } end,
		InChatMessagingLockdown = function() return false end }
	local wasEasy = ns.db.easyMode
	ns.db.easyMode = false
	UI:Open("mats for thorium belt >>> party"); T.FlushAll()
	check(UI.sendTo and UI.sendTo.all, "the prompt: send all")
	local foot = UI.status and UI.status:GetText() or ""
	check(foot:find("Enter sends all 2 to party", 1, true), "footer says how many go where: " .. foot)
	local mark = #T.log
	T.key("ENTER"); T.FlushAll()
	check(#sent == 1 and sent[1][2] == "PARTY" and sent[1][1]:find("^Mats for Thorium Belt %(2%)") and not UI:IsShown(),
		"Enter: one line to party, terminal closed: " .. tostring(sent[1] and sent[1][1]))
	check(not T.logHas("Secure.Arm", mark + 1), "nothing armed for the game to press")
	-- the game's chat lockdown (an encounter): says so, sends nothing
	sent = {}
	_G.C_ChatInfo.InChatMessagingLockdown = function() return true end
	local n2, why = SH.SendAll(rows, { chat = "PARTY", label = "party" }, "")
	check(not n2 and why:find("doesn't let addons", 1, true) and #sent == 0, "chat lockdown: nothing sent, says why")
	_G.C_ChatInfo.InChatMessagingLockdown = function() return false end
	-- no channel yet: says so
	local printed = {}
	local pr = ns.Print
	ns.Print = function(_, m) printed[#printed + 1] = m end
	UI:Open("mats for thorium belt >>> zzz"); T.FlushAll()
	T.key("ENTER"); T.FlushAll()
	check(#sent == 0 and (printed[1] or ""):find("No channel called zzz", 1, true), "a bad channel: says so: " .. tostring(printed[1]))
	ns.Print = pr
	UI:Hide(); T.FlushAll()
	-- the right-click menu: "All 2 to <channel>" for each channel you're in (Simple mode too)
	local g = { _G.IsInGroup, _G.IsInRaid, _G.IsInGuild }
	_G.IsInGroup = function(c) return c ~= 2 end
	_G.IsInRaid = function() return false end
	_G.IsInGuild = function() return true end
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("mats for thorium belt"); T.FlushAll()
	UI:ShowRowMenu(1)
	local m, byLabel, labels = _G.TerminalRowMenu, {}, {}
	for _, b in ipairs(m.lines) do if b:IsShown() then byLabel[b.fs:GetText()] = b; labels[#labels + 1] = b.fs:GetText() end end
	local all3 = table.concat(labels, ",")
	check(byLabel["All 2 to party"] and byLabel["All 2 to guild"] and byLabel["All 2 to say"], "menu: All N to each channel: " .. all3)
	local b = byLabel["All 2 to guild"]
	if b then b.scripts.PreClick(b, "LeftButton"); b.scripts.PostClick(b, "LeftButton") end
	T.FlushAll()
	check(#sent == 1 and sent[1][2] == "GUILD" and sent[1][1]:find("^Mats for Thorium Belt %(2%)") and not UI:IsShown(),
		"menu: All 2 to guild sends them: " .. tostring(sent[1] and sent[1][1]))
	_G.IsInGroup, _G.IsInRaid, _G.IsInGuild = g[1], g[2], g[3]
	ns.db.easyMode = wasEasy; UI:EasyChanged()

	-- what the filters say they are (0.44.2): "@loot razorfen kraul type:weapon" -> "Weapons ..."
	check(SH.Describe("@loot razorfen kraul type:weapon") == "Weapons" and SH.Describe("hogger") == nil
		and SH.Describe("@loot q:rare+ type:sword|type:axe") == "Rare or better swords and axes"
		and SH.Describe("@item type:plate slot:feet is:upgrade") == "Plate boot upgrades"
		and SH.Describe("@loot slot:feet stat:agility lvl:20-30") == "Boots with agility (level 20-30)"
		and SH.Describe("@loot type:staff -is:boe") == "Staves",
		"filters described: " .. tostring(SH.Describe("@loot q:rare+ type:sword|type:axe")) .. " / " .. tostring(SH.Describe("@item type:plate slot:feet is:upgrade")))
	-- a whole instance: the instance said once, each item only its boss
	local rfk = {
		{ kind = "loot", key = 1, name = "Corpsemaker", detail = "Overlord Ramtusk  Razorfen Kraul" },
		{ kind = "loot", key = 2, name = "Pronged Reaver", detail = "Charlga Razorflank  Razorfen Kraul" },
		{ kind = "loot", key = 3, name = "Plains Ring", detail = "Trash Mobs  Razorfen Kraul" },
	}
	lines = SH.GroupLines(rfk, "@loot razorfen kraul")
	check(lines[1] == "Loot from Razorfen Kraul (3): Corpsemaker (Overlord Ramtusk), Pronged Reaver (Charlga Razorflank), Plains Ring (trash)",
		"one instance, many bosses: " .. tostring(lines[1]))
	lines = SH.GroupLines(rfk, "@loot razorfen kraul type:weapon")
	check(lines[1]:find("^Weapons from Razorfen Kraul %(3%): Corpsemaker"), "with a filter: says they're weapons: " .. tostring(lines[1]))
	lines = SH.GroupLines(loot, "@loot lorgus jett type:weapon")
	check(lines[1]:find("^Weapons dropped by Lorgus Jett in Blackfathom Deeps %(5%)"), "one boss, a filter: " .. tostring(lines[1]))

	-- items the client hasn't loaded: asked for ahead (prefetch), and party waits for them; say can't wait
	local cachedWas, reqWas = C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID
	local cached, asks = { [101] = true }, {}
	C_Item.IsItemDataCachedByID = function(id) return cached[id] == true end
	C_Item.RequestLoadItemDataByID = function(id) asks[#asks + 1] = id end
	local items = { { kind = "item", key = 101, itemID = 101, name = "Loaded" }, { kind = "item", key = 102, itemID = 102, name = "Not Yet" } }
	check(SH.Prefetch(items) == 1 and asks[1] == 102 and SH.Prefetch(items) == 0, "prefetch asks for the unloaded ones, once")
	sent = {}
	local r = SH.SendAll(items, { chat = "PARTY", label = "party" }, "")
	check(r == true and #sent == 0, "party: waits for the item to load")
	cached[102] = true
	T.FlushAll()
	check(#sent == 1 and sent[1][2] == "PARTY", "loaded: sent")
	cached[102] = nil
	sent = {}
	SH.SendAll(items, { chat = "PARTY", label = "party" }, "")
	T.FlushAll()
	check(#sent == 1, "never loaded: sent anyway after the wait (as names)")
	sent = {}
	r = SH.SendAll(items, { chat = "SAY", label = "say" }, "")
	check(r == 1 and #sent == 1, "say needs the key press: sent at once")
	C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID = cachedWas, reqWas
	_G.C_ChatInfo = savedChat
	UI:Hide(); T.FlushAll()
end

ns.providers, ns.providerOrder = saved.providers, saved.order
ns:AliasesChanged()
C_Item.GetItemNameByID, C_Item.GetItemCount, _G.AtlasLoot = saved.name, saved.count, saved.AL
ns.Integrations.ItemField, ns.Integrations.NpcRow, ns.Integrations.ObjectName, ns.Integrations.QuestRow = saved.field, saved.npc, saved.obj, saved.quest
UI.lastScan, UI.lastOverview = nil, nil
P.ClearCrafts(); P.ClearSteps()
