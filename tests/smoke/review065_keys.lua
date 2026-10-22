-- 0.65.x review (0.65.10): the terminal's key as a Shift or Alt chord, and closing the bar's menus with it.
-- review of 0.65.1/0.65.2: the terminal's own key
local T = ...
local ns, UI, check, key, query, FlushAll = T.ns, T.UI, T.check, T.key, T.query, T.FlushAll
local function say(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end io.write("  >> " .. table.concat(t, " ") .. "\n") end
local save = { key = _G.GetBindingKey, action = _G.GetBindingAction, alt = _G.IsAltKeyDown, ctrl = _G.IsControlKeyDown,
	shift = _G.IsShiftKeyDown, easy = ns.db.easyMode }
local bound = {}
_G.GetBindingKey = function(action)
	local a, b
	local ks = {}
	for k in pairs(bound) do ks[#ks + 1] = k end
	table.sort(ks)
	for _, k in ipairs(ks) do if bound[k] == action then if a then b = b or k else a = k end end end
	return a, b
end
_G.GetBindingAction = function(k) return bound[k] or "" end
local function with(name, fn) local was = _G[name]; _G[name] = function() return true end; fn(); _G[name] = was end

io.write("[K1: Shift+Space bound: hints say it, it doesn't work]\n")
do
	bound = { ["SHIFT-SPACE"] = "TERMINAL_TOGGLE" }
	ns.db.easyMode = true; UI:EasyChanged()
	local label = ns.ToggleLabel()
	local hint = ns.KeyHint("Esc or ` close")
	say("label:", label, "hint:", hint)
	UI:Open("")
	T.typeText("abc")
	with("IsShiftKeyDown", function() key("SPACE", " ") end)
	FlushAll()
	say("after Shift+Space: shown", UI:IsShown(), "query '" .. query() .. "'")
	check(not (hint:find("Shift+Space", 1, true) and UI:IsShown()),
		"K1 the footer says 'Esc or Shift+Space close' but Shift+Space doesn't close (typed: '" .. query() .. "')")
	UI:Hide(); FlushAll()
end

io.write("[K2: Ctrl+Space bound, a bar menu open: Ctrl+Space picks the menu line instead of closing]\n")
do
	bound = { ["CTRL-SPACE"] = "TERMINAL_TOGGLE" }
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("")
	T.typeText("linen")
	FlushAll()
	local B = ns.Bar
	with("IsAltKeyDown", function() key("F", "f") end)
	local opened = B.menu and B.menu.which
	FlushAll()
	say("menu open:", opened, B.menu and B.menu:IsShown())
	if B.menu and B.menu:IsShown() then
		key("DOWN"); key("DOWN")
		say("line picked by keys:", B.menu.keySel, tostring(B.menu.lines[B.menu.keySel].id))
		local before = #B.state.filters
		T.withCtrl(function() key("SPACE") end)
		FlushAll()
		say("after Ctrl+Space: menu", B.menu:IsShown(), "terminal", UI:IsShown(), "filters picked", #B.state.filters, "was", before)
		-- (as ` does there: the menu closes, nothing picked, the terminal stays)
		check(not B.menu:IsShown() and #B.state.filters == before, "K2 Ctrl+Space (the terminal's key) in the bar's menu: closes it, picks nothing (filters " .. #B.state.filters .. ")")
		B.Reset()
	end
	UI:Hide(); FlushAll()
end

io.write("[K3: ^ bound, a bar menu open: ^ closes it and is typed]\n")
for _, k in ipairs({ "`", "^" }) do
	bound = { [k] = "TERMINAL_TOGGLE" }
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("")
	T.typeText("linen")
	FlushAll()
	local B = ns.Bar
	with("IsAltKeyDown", function() key("F", "f") end)
	FlushAll()
	if B.menu and B.menu:IsShown() then
		key(k, k)
		FlushAll()
		say(k .. " in bar menu: query '" .. query() .. "' menu shown", B.menu:IsShown())
		check(query() == "linen", "K3 " .. k .. " closing the bar's menu is not typed: '" .. query() .. "'")
	else
		say("bar menu didn't open")
	end
	UI:Hide(); FlushAll()
end

io.write("[K4: Alt+Q bound: never opens; in it, Alt+Q is Alt+` (Advanced), not close]\n")
do
	bound = { ["ALT-Q"] = "TERMINAL_TOGGLE" }
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Hide(); FlushAll()
	with("IsAltKeyDown", function() UI:Toggle() end)
	say("label", ns.ToggleLabel(), "hint", ns.KeyHint("Esc or ` close"), "opened by Alt+Q:", UI:IsShown())
	check(UI:IsShown(), "K4 the key bound (Alt+Q) opens the terminal")
	UI:Hide(); FlushAll()
	UI:Open("")
	T.typeText("hearth")
	with("IsAltKeyDown", function() key("Q", "q") end)
	FlushAll()
	say("Alt+Q in the open terminal: shown", UI:IsShown(), "temp Advanced", tostring(ns.Easy.temp ~= nil), "query '" .. query() .. "'")
	check(not UI:IsShown(), "K4b Alt+Q (bound, the footer says 'Esc or Alt+Q close') closes the open terminal")
	UI:Hide(); FlushAll()
	if UI.EndAdvancedOnce then UI:EndAdvancedOnce() end
end

_G.GetBindingKey, _G.GetBindingAction, _G.IsAltKeyDown, _G.IsControlKeyDown, _G.IsShiftKeyDown = save.key, save.action, save.alt, save.ctrl, save.shift
ns.db.easyMode = save.easy; UI:EasyChanged()
UI.lastScan = nil
