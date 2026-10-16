-- (review, 0.53.6) small fixes in the lists: a macro's #show line, .history's "|", the Quick Keybind row's text
local T = ...
local ns, check = T.ns, T.check

io.write("[review: macros, history, keybinds]\n")
do -- a macro starting with #show (any case): its first command is the detail
	local real = _G.GetMacroInfo
	_G.GetMacroInfo = function(i) if i == 1 then return "Hearth", 1, "#Show Hearthstone\n/use Hearthstone" end return real(i) end
	ns.providers.macros._dirty = true
	local hearth
	for _, e in ipairs(ns:GetEntries(ns.providers.macros)) do if e.name == "Hearth" then hearth = e end end
	_G.GetMacroInfo = real
	ns.providers.macros._dirty = true
	check(hearth and tostring(hearth.detail):find("/use Hearthstone", 1, true) and not tostring(hearth.detail):find("#Show", 1, true),
		"#Show: the macro's first command is said, not the directive: " .. tostring(hearth and hearth.detail))
end
do -- .history: a "|" typed ("linen|wool") said as "||" in chat
	local h = ns.db.history
	ns.db.history = { "linen|wool" }
	local out = ns:FindCommand("history").run("")
	ns.db.history = h
	check(out[2] and out[2]:find("linen||wool", 1, true), ".history escapes |: " .. tostring(out[2]))
end
do -- Quick Keybind Mode's row points at the button by the button's own text
	local a, b = _G.SETTINGS_QUICK_KEYBIND_BUTTON, _G.QUICK_KEYBIND_MODE
	_G.SETTINGS_QUICK_KEYBIND_BUTTON, _G.QUICK_KEYBIND_MODE = "Quick Keybind", "Quick Keybind Mode"
	ns.providers.keybinds._dirty = true
	local row = ns:GetEntries(ns.providers.keybinds)[1]
	_G.SETTINGS_QUICK_KEYBIND_BUTTON, _G.QUICK_KEYBIND_MODE = a, b
	ns.providers.keybinds._dirty = true
	check(row and row.rowText == "Quick Keybind" and row.name == "Quick Keybind Mode",
		"its row is the mode's name, pointing at the button's text: " .. tostring(row and row.rowText))
end
do -- @xp: read again on opening only once a minute has passed (alts' rested fills slowly)
	T.check(ns.providers.experience.refreshOnOpen == 60, "@xp's refresh on open: at most once a minute")
end
do -- in: on achievements: their detail (progress, points) isn't worked out per row: it never says a place
	local real, asked = _G.GetAchievementInfo, 0
	_G.GetAchievementInfo = function(...) asked = asked + 1 if real then return real(...) end end
	ns.providers.achievements._dirty = true
	local list = ns:GetEntries(ns.providers.achievements)
	asked = 0
	local f = ns.Filters.Parse("in:barrens")
	for _, e in ipairs(list) do ns.Filters.Pass(e, { f }) end
	_G.GetAchievementInfo = real
	ns.providers.achievements._dirty = true
	T.check(#list > 0 and asked == 0, ("in: over %d achievements: none read from the game for it (%d)"):format(#list, asked))
end
