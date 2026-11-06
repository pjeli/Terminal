-- Terminal's own settings as rows (UI/Options.lua): "terminal settings", a setting's words, Enter and Shift+Enter.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local Th, E = ns.Theme, ns.Easy

local function Find(res, name)
	for i, e in ipairs(res) do if e.name == name then return e, i end end
end
local function Names(res, n)
	local t = {}
	for i = 1, math.min(#res, n or 8) do t[i] = tostring(res[i].name) end
	return table.concat(t, " | ")
end
local function Search(q) UI:Open(q); FlushAll() return UI.Results() end
local function Close() UI:Hide(); FlushAll() end
local saved = {}
for _, k in ipairs(Th.ORDER) do saved[k] = Th.Get()[k] end

io.write("[settings: \"terminal settings\" lists them, in .set's order]\n")
for _, simple in ipairs({ true, false }) do
	ns.db.easyMode = simple
	UI:EasyChanged()
	local mode = simple and "Simple" or "Advanced"
	local res = Search("terminal settings")
	local first, second = res[1], res[2]
	check(first and first.name == "Terminal Options" and second and second.setKey == "promptText",
		mode .. ": the options first, then every setting from the first: " .. Names(res, 4))
	local n = 0
	for _, e in ipairs(res) do if e.setKey then n = n + 1 end end
	check(n >= #Th.ORDER - 2, mode .. ": every setting listed (" .. n .. " of " .. #Th.ORDER .. ")")
	Close()
	-- (a setting found by its everyday words)
	for q, want in pairs({ ["bigger font"] = "Font size", ["zen dimming"] = "Zen dimming", cursor = "Cursor", opacity = "Opacity",
		["see through"] = "Opacity", ["slash key"] = "Open on /", ["expiry warning"] = "Mail expiry warning" }) do
		res = Search(q)
		local got = res[1] and res[1].name
		if simple and res[1] and res[1].catId then UI:SetCategory(res[1].catId); FlushAll(); res = UI.Results(); got = res[1] and res[1].name end
		check(got == want, mode .. ": \"" .. q .. "\" finds " .. want .. ": " .. Names(res, 3))
		Close()
	end
end
ns.db.easyMode = false
UI:EasyChanged()

io.write("[settings: each row says its value; Enter changes it, Shift+Enter puts the default back]\n")
do
	Th.Set("hints", "on", true); Th.Set("cursor", "blinking-line", true)
	local res = Search("terminal settings")
	local hints, hi = Find(res, "Key hints in footer")
	local cursor = Find(res, "Cursor")
	check(hints and hints.detail:find("on", 1, true) and cursor and cursor.detail == "Blinking line",
		"the value beside each: " .. tostring(hints and hints.detail) .. " / " .. tostring(cursor and cursor.detail))
	local a, b = E.Verbs(hints)
	check(a == "turn off" and b == nil, "an on/off one at its default: turn off, nothing to reset: " .. tostring(a) .. "/" .. tostring(b))
	check(select(1, E.Verbs(cursor)) == "pick a value", "a choice: pick a value")
	UI.sel = hi
	UI:Activate(hi)
	check(Th.Get().hints == false and UI:IsShown(), "Enter turns it off, the terminal staying open")
	check(hints.detail:find("off", 1, true) and hints.detail:find("default", 1, true), "its row says so at once, and the default: " .. hints.detail)
	a, b = E.Verbs(hints)
	check(a == "turn on" and b == "reset to default", "now: turn on, or reset: " .. tostring(a) .. "/" .. tostring(b))
	UI:Activate(hi, { secondary = true })
	check(Th.Get().hints == true and UI:IsShown(), "Shift+Enter: back to the default, still open")
	-- (a tooltip: what it does, now, the .set line, the keys)
	local lines = {}
	local tip = { SetText = function(_, s) lines[#lines + 1] = s end, AddLine = function(_, s) lines[#lines + 1] = s end,
		AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "=" .. r end }
	cursor.tooltip(cursor, tip)
	local said = table.concat(lines, "\n")
	check(said:find("The text cursor", 1, true) and said:find(".set cursor blinking-line", 1, true) and said:find("pick a value", 1, true),
		"its tooltip says what it does and how: " .. said:gsub("\n", " / "))
	-- (Enter on a choice: its values listed under the prompt, as .set's own list)
	local _, ci = Find(UI.Results(), "Cursor")
	UI.sel = ci
	UI:Activate(ci)
	FlushAll()
	local q = UI.edit:GetText()
	local vals = UI.Results()
	check(q == ".set cursor " and Find(vals, "solid-line") ~= nil, "Enter on Cursor: \".set cursor \" and its styles: " .. q .. " -> " .. Names(vals, 5))
	local solid = Find(vals, "solid-line")
	check(solid and solid.detail == "Solid line", "each by its name: " .. tostring(solid and solid.detail))
	Close()
end

io.write("[settings: .set lists values for numbers and colours too; .set alone opens the list]\n")
do
	Th.Set("fontSize", "13", true)
	local out = ns.commands.set.complete("fontSize ")
	local said = {}
	for _, o in ipairs(out) do said[#said + 1] = o[1] .. "=" .. o[2] end
	local s = table.concat(said, ";")
	check(s:find("14=14  +1", 1, true) and s:find("12=12  -1", 1, true) and s:find("(default)", 1, true) and s:find("lowest", 1, true),
		".set fontSize <Tab>: a step either way, the default, the ends: " .. s)
	out = ns.commands.set.complete("accent ")
	check(out[1] and out[1][1]:match("^%x%x%x%x%x%x$") and out[1][2]:find("the theme's own", 1, true), ".set accent: the theme's own colour: " .. tostring(out[1] and out[1][2]))
	out = ns.commands.set.complete("fzfColor ")
	check(out[1] and out[1][1] == "accent", ".set fzfColor: the selection colour")
	check(ns.commands.set.run("") == nil, ".set alone prints nothing")
	FlushAll()
	check(UI:IsShown() and UI.edit:GetText() == Th.SETTINGS_SEARCH, "and opens Terminal on the settings: " .. tostring(UI.edit:GetText()))
	Close()
	local list = ns.commands.set.run("list")
	check(type(list) == "table" and #list == #Th.ORDER + 1, ".set list prints them in chat")
end

io.write("[settings: only those that do something here]\n")
do
	local was, tt = ns.db.noDirectOpen, rawget(_G, "TomTom")
	ns.db.noDirectOpen, _G.TomTom = true, nil
	ns.providers.terminal._dirty = true
	local res = Search("terminal settings")
	check(not Find(res, "Index professions at login") and not Find(res, "Waypoints go to"), "no profession indexing on WoW Forever, no waypoints without TomTom")
	Close()
	ns.db.noDirectOpen, _G.TomTom = false, { AddWaypoint = function() end }
	ns.providers.terminal._dirty = true
	res = Search("terminal settings")
	check(Find(res, "Index professions at login") and Find(res, "Waypoints go to"), "both where they work")
	Close()
	ns.db.noDirectOpen, _G.TomTom = was, tt
	ns.providers.terminal._dirty = true
end

for k, v in pairs(saved) do Th.Get()[k] = v end
