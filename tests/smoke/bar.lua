-- Simple mode's bar (0.55.1, experimental; the player: "tabs for filtering, sorting, grouping, and a little
-- announcement horn"): UI/Bar.lua. Shown in Simple mode with words typed, gone in Advanced; its filters, sort and group
-- run in the search; Alt+` (or Advanced syntax typed) writes them into the line.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local B, E = ns.Bar, ns.Easy

io.write("[bar: Simple mode's filter, sort, group and horn]\n")
do
	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	local ROWS = {
		{ name = "Iron Sword", quality = 2 }, { name = "Arcanite Sword", quality = 4 }, { name = "Bronze Sword", quality = 3 },
		{ name = "Copper Sword", quality = 1 }, { name = "Mithril Sword", quality = 3 },
	}
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
		local out = {}
		for i, r in ipairs(ROWS) do out[i] = { name = r.name, quality = r.quality, key = i } end
		return out
	end })
	ns:AliasesChanged()
	UI.lastScan, UI.lastOverview = nil, nil
	ns.db.easyMode = true; UI:EasyChanged()
	local function Names()
		local t = {}
		for _, e in ipairs(UI.Results()) do if B.Real(e) then t[#t + 1] = tostring(e.name) end end
		return table.concat(t, " | ")
	end

	UI:Open(""); FlushAll()
	check((UI.barH or 0) == 0, "nothing typed: no bar")
	UI:SetQuery("sword"); FlushAll()
	check(UI.barH == B.H and B.strip and B.strip:IsShown(), "words typed in Simple mode: the bar shows")
	local ids = {}
	for _, o in ipairs(B.Options("filter")) do ids[#ids + 1] = o.id end
	ids = table.concat(ids, " ")
	check(ids:find("q:rare+", 1, true) and not ids:find("is:online", 1, true), "Filter offers what fits the items shown, not what doesn't: " .. ids)

	-- Filter: rare or better
	B.Pick("filter", "q:rare+"); FlushAll()
	check(Names() == "Arcanite Sword | Bronze Sword | Mithril Sword" or Names():find("Arcanite") and not Names():find("Iron") and not Names():find("Copper"),
		"Rare or better: only those: " .. Names())
	-- Sort: by name, then by quality (the best first)
	B.Pick("sort", "name"); FlushAll()
	check(Names() == "Arcanite Sword | Bronze Sword | Mithril Sword", "sorted by name: " .. Names())
	B.Pick("sort", "quality"); FlushAll()
	check(Names():find("^Arcanite Sword"), "sorted by quality, the best first: " .. Names())
	B.Clear("filter"); B.Clear("sort"); FlushAll()
	check(Names():find("Copper Sword", 1, true), "cleared: every sword again: " .. Names())
	-- Group: a row per quality
	B.Pick("group", "quality"); FlushAll()
	local groups = 0
	for _, e in ipairs(UI.Results()) do if e.kind == "aggregate" then groups = groups + 1 end end
	check(groups >= 3, "grouped by quality: a row per quality: " .. groups)
	B.Clear("group"); FlushAll()

	-- Advanced syntax typed: the bar goes, what it picked written into the line
	B.Pick("filter", "q:rare+"); B.Pick("sort", "name"); FlushAll()
	UI:SetQuery("sword >>", 8); FlushAll()
	check(UI.edit:GetText():find("q:rare+", 1, true) and UI.edit:GetText():find("sort:name", 1, true) and UI.edit:GetText():find(">>$"),
		"Advanced syntax typed: the bar's picks written in: " .. UI.edit:GetText())
	check((UI.barH or 0) == 0 and not B.Active(), "and the bar is gone (the line is Advanced)")
	UI:Hide(); FlushAll()

	-- Alt+`: written in too, the group step last
	UI:Open(""); UI:SetQuery("sword"); FlushAll()
	B.Pick("group", "quality"); FlushAll()
	UI:AdvancedOnce(); FlushAll()
	check(UI.edit:GetText():find("| group by quality%s*$"), "Alt+`: the group step written last: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	check(not B.Active() and #B.state.filters == 0, "closed: nothing picked any more")

	-- the prompt cleared: what was picked goes
	UI:Open(""); UI:SetQuery("sword"); FlushAll()
	B.Pick("filter", "q:epic+"); FlushAll()
	UI:SetQuery(""); FlushAll()
	check(#B.state.filters == 0, "the prompt cleared: the filter goes")

	-- the horn: the selected result's sending and copying lines only
	UI:SetQuery("sword"); FlushAll()
	local shown, share
	local was = UI.ShowRowMenu
	UI.ShowRowMenu = function(_, idx, keys, s) shown, share = idx, s end
	B.Horn()
	UI.ShowRowMenu = was
	check(shown == UI.sel and share == true, "the horn: the row menu's sending lines for the selected result")
	UI:Hide(); FlushAll()

	-- Advanced mode's own sort:name (the bar's sorts in Advanced syntax)
	ns.db.easyMode = false; UI:EasyChanged()
	local res = UI:Search("@item sword sort:name")
	check(res[1] and res[1].name == "Arcanite Sword" and res[#res].name == "Mithril Sword", "sort:name in Advanced mode: "
		.. tostring(res[1] and res[1].name) .. " .. " .. tostring(res[#res] and res[#res].name))

	ns.providers, ns.providerOrder = saved.providers, saved.order
	ns:AliasesChanged()
	ns.db.easyMode = saved.easy; UI:EasyChanged()
	UI.lastScan, UI.lastOverview = nil, nil
	B.Reset()
end
