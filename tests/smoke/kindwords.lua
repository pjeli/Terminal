-- (1.0.45, the player's ask: the reach audit's part 1) every list's own name is a kind word: said alone it lists that
-- list, explicit ones too, with other words it searches in it; a game window of that name comes after the list's rows;
-- an everyday word only as yours ("my bank"); names stay names; Alt+` writes the list (Query.lua's Scan.KindWord).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local E = ns.Easy
io.write("[kind words: a list named by its own name]\n")
local easy = ns.db.easyMode
ns.db.easyMode = true; UI:EasyChanged()
local ok, err = pcall(function()
	local want = {
		macros = "@macro", ["my macros"] = "@macro", addons = "@addon", ["my addons"] = "@addon", ["slash commands"] = "@slash",
		["addon options"] = "@addonoption", guild = "@guild", ["guild online"] = "@guild is:online", ["friends online"] = "@friend is:online",
		["my friends"] = "@friend", ["my reputation"] = "@reputation", reputation = "@reputation", calendar = "@calendar",
		["my bags"] = "@item in:bags", bags = "@item in:bags", ["linen on my alts"] = "@stored linen", ["linen in my bank"] = "@bank linen",
		hearthstone = "hearthstone",
	}
	for line, adv in pairs(want) do
		local got = (E.ToAdvanced(line) or ""):gsub("%s+$", "")
		check(got == adv, line .. ": " .. adv .. " (got " .. got .. ")")
	end
	-- the list's rows, then the window of that name
	UI.lastScan, UI.lastOverview = nil, nil
	local res = UI:Search("macros")
	check(res[1] and res[1].kind == "macros" and res[#res].kind == "panels", "macros: your macros, then the Macros window")
	-- ordinary words stay ordinary
	check(not (E.ToAdvanced("10 slot bag") or ""):find("@", 1, true) and not (E.ToAdvanced("gold map") or ""):find("@gold", 1, true),
		"10 slot bag, gold map: not the lists")
	-- names stay names: a row named the line wins over the list
	local had = ns.providers.kwprobe
	ns:RegisterProvider("kwprobe", { label = "Kw Probe", aliases = { "kwprobe" }, collect = function() return { { name = "Calendar", key = 1 } } end })
	E.ForgetKinds()
	ns:GetEntries(ns.providers.kwprobe)
	check(not (E.ToAdvanced("calendar") or ""):find("@calendar", 1, true), "a row named Calendar: the name, not the list")
	if not had then
		ns.providers.kwprobe = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "kwprobe" then table.remove(ns.providerOrder, i) end end
		ns:AliasesChanged()
	end
	E.ForgetKinds()
end)
ns.db.easyMode = easy; UI:EasyChanged()
check(ok, "kind words: " .. tostring(err))
