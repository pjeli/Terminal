-- (0.55.18, the rewrite's review) one query, three ways to write it: a Simple search, Alt+`'s line run in Advanced mode,
-- the bar's picks and the same typed as Advanced syntax all list the same results.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
io.write("[roundtrip: Simple, Alt+` and the bar find the same]\n")
local wasEasy = ns.db.easyMode
local E = ns.Easy
local function Names(res)
	local t = {}
	for _, e in ipairs(res or {}) do if ns.Bar.Real(e) then t[#t + 1] = tostring(e.name) end end
	table.sort(t)
	return table.concat(t, " | ")
end
local lines = {
	"linen", "linen cloth", "rare sword", "sword", "hearthstone", "use hearthstone", "cast frost nova", "frost", "fireball",
	"epic", "boe", "potion", "food", "stamina food", "not boe sword", "sword or axe", "q:rare+ sword", "sword sort:name",
	"hogger", "nearest innkeeper", "innkeeper", "vendor", "trainer", "mage trainer", "mining trainer",
	"reload", "dance", "emote dance", "map", "talents", "keybind", "sheathe", "camera", "quest", "kobold", "wolf",
	"mount", "raptor", "toy", "achievement", "gold", "durability", "mail", "my mail", "spells", "@spell nova",
	"@item linen", "in:bags linen", "usable", "upgrades", "ready", "todo", "done",
}
local bad, n = 0, 0
for _, line in ipairs(lines) do
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open(""); UI:SetQuery(line, #line); T.FlushAll()
	local simple = UI.Results()
	local overview = ns.Bar.Overview(simple)
	local shown = E.ShownKinds and E.ShownKinds(simple) or nil
	local adv = E.ToAdvanced(line, UI.category, shown)
	local s = Names(simple)
	UI:Hide(); T.FlushAll()
	if not overview then
		ns.db.easyMode = false; UI:EasyChanged()
		UI.lastScan, UI.lastExtra = nil, nil
		local a = Names(UI:Search(adv))
		n = n + 1
		if a ~= s then
			bad = bad + 1
		end
		check(a == s, ("%q in Simple mode, and Alt+`'s %q in Advanced: %s  //  %s"):format(line, adv, s:sub(1, 200), a:sub(1, 200)))
	end
end
check(n >= 30, "(lines compared: " .. n .. ")")
ns.db.easyMode = true; UI:EasyChanged()

do
local B = ns.Bar
local saved = { providers = ns.providers, order = ns.providerOrder }
ns.providers, ns.providerOrder = {}, {}
local ROWS = { { "Iron Sword", 2, "Elwynn" }, { "Arcanite Sword", 4, "Tanaris" }, { "Bronze Sword", 3, "Elwynn" }, { "Copper Sword", 1, "Tanaris" }, { "Mithril Sword", 3, "Duskwood" }, { "Mithril Axe", 3, "Duskwood" } }
ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
	local out = {}
	for i, r in ipairs(ROWS) do out[i] = { name = r[1], quality = r[2], zone = r[3], key = i } end
	return out
end })
ns:AliasesChanged()
ns.db.easyMode = true; UI:EasyChanged()
local function Names()
	local t = {}
	for _, e in ipairs(UI.Results()) do if B.Real(e) or e.kind == "aggregate" then t[#t + 1] = tostring(e.name) end end
	return table.concat(t, " | ")
end
local function Run(text, picks)
	B.Reset(); UI.lastScan, UI.lastExtra = nil, nil
	UI:Open(""); UI:SetQuery(text, #text); T.FlushAll()
	for _, p in ipairs(picks or {}) do B.Pick(p[1], p[2]) end
	T.FlushAll()
	local n = Names()
	local adv = E.ToAdvanced(UI.edit:GetText(), UI.category, E.ShownKinds(UI.Results()))
	UI:Hide(); T.FlushAll(); B.Reset()
	return n, adv
end
local function Adv(line)
	ns.db.easyMode = false; UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	UI:Open(""); UI:SetQuery(line, #line); T.FlushAll()
	local n = Names()
	UI:Hide(); T.FlushAll()
	ns.db.easyMode = true; UI:EasyChanged()
	return n
end
local cases = {
	{ "sword", { { "filter", "q:rare+" } }, "sword q:rare+ " },
	{ "sword", { { "sort", "name" } }, "sword sort:name " },
	{ "sword", { { "sort", "quality" } }, "sword sort:quality " },
	{ "sword", { { "group", "zone" } }, "sword | group by zone" },
	{ "mithril", { { "filter", "q:rare+" }, { "sort", "name" } }, "mithril q:rare+ sort:name " },
	{ "sword", { { "filter", "q:epic+" }, { "group", "zone" } }, "sword q:epic+ | group by zone" },
}
for _, c in ipairs(cases) do
	local barN, adv = Run(c[1], c[2])
	local typedN = select(1, Run(c[3]))
	local advN = Adv(adv)
	check(barN == typedN and barN == advN and barN ~= "", ("%q with the bar's picks = %q typed = Alt+`'s %q: [%s] [%s] [%s]"):format(c[1], c[3], adv, barN, typedN, advN))
end
ns.providers, ns.providerOrder = saved.providers, saved.order
ns:AliasesChanged()
B.Reset()
end
ns.db.easyMode = wasEasy; UI:EasyChanged()
UI.lastScan, UI.lastExtra, UI.category, UI.categoryAuto = nil, nil, nil, nil
