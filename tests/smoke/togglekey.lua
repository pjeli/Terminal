-- The terminal's own key on keyboards without a plain ` (0.65.1, a player on CurseForge: "how can I keybind the terminal
-- when using the QWERTZ/German-layout?"): the key bound to the terminal does in it what ` does (closes it; Alt+ and Tab+
-- with it too), and the hints name that key.
local T = ...
local ns, UI, check, key, query, FlushAll = T.ns, T.UI, T.check, T.key, T.query, T.FlushAll

io.write("[the terminal's key: ^, Ctrl+Space, as ` is]\n")
do
	local save = { key = _G.GetBindingKey, action = _G.GetBindingAction, alt = _G.IsAltKeyDown, ctrl = _G.IsControlKeyDown,
		easy = ns.db.easyMode }
	local bound = {}
	_G.GetBindingKey = function(action)
		local a, b
		for _, k in ipairs({ "`", "^", "CTRL-SPACE", "F9", "." }) do
			if bound[k] == action then if a then b = b or k else a = k end end
		end
		return a, b
	end
	_G.GetBindingAction = function(k) return bound[k] or "" end
	local function withAlt(fn) _G.IsAltKeyDown = function() return true end; fn(); _G.IsAltKeyDown = save.alt end
	local function withCtrl(fn) _G.IsControlKeyDown = function() return true end; fn(); _G.IsControlKeyDown = save.ctrl end

	-- which keys: ` always; a symbol bound alone; never a letter, digit or one of Terminal's syntax characters
	bound = { ["^"] = "TERMINAL_TOGGLE" }
	check(ns.IsTickKey("`") and ns.IsTickKey("^") and not ns.IsTickKey("A") and not ns.IsTickKey("SPACE"),
		"^ bound to the terminal: the terminal's key, as ` is")
	bound = { ["."] = "TERMINAL_TOGGLE" }
	check(not ns.IsTickKey("."), "a character a search needs (.) never closes it, bound or not")
	check(ns.KeyLabel("CTRL-SPACE") == "Ctrl+Space" and ns.KeyLabel("CTRL-SHIFT-F12") == "Ctrl+Shift+F12"
		and ns.KeyLabel("NUMPAD5") == "Numpad5" and ns.KeyLabel("^") == "^", "keys named as hints name them")
	bound = { ["`"] = "TERMINAL_TOGGLE", F9 = "TERMINAL_TOGGLE" }
	check(ns.ToggleLabel() == "`" and ns.KeyHint("Esc or ` close") == "Esc or ` close", "` one of them: the hints as written")

	-- ^ alone: it closes the open terminal, from the drawn prompt and from the game's text box
	bound = { ["^"] = "TERMINAL_TOGGLE" }
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("")
	key("^")
	check(not UI:IsShown(), "^ in the open terminal: closed, as ` does")
	UI:Open("")
	UI.edit.scripts.OnKeyDown(UI.edit, "^")
	check(not UI:IsShown(), "^ in the game's text box: closed too")
	-- Alt+^: this search in Advanced mode, its ^ not typed after it
	UI:Open("")
	T.typeText("cast frost nova")
	withAlt(function() key("^", "^") end)
	FlushAll()
	check(UI:IsShown() and ns.Easy.temp ~= nil and query():find("do:cast frost nova", 1, true) and not query():find("^", 1, true), "Alt+^: Advanced mode for this search, no ^ typed: " .. query())
	UI:Hide(); FlushAll()
	UI:EndAdvancedOnce()
	-- opened by ^: its character not typed into the prompt
	UI:Open("^hea")
	check(UI.edit:GetText() == "hea", "^ that opened it, not typed: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	-- the hints name it
	check(ns.ToggleLabel() == "^" and ns.KeyHint("Esc or ` close") == "Esc or ^ close", "hints: Esc or ^ close")
	local P = ns.Panel
	local fs = P.Footer(CreateFrame("Frame"), 10, P.CLOSE)
	check(fs:GetText() == "Esc or ^ close", "a window's footer says ^: " .. tostring(fs:GetText()))
	local rows = ns.KeysWindow.Rows("advanced")
	local found = false
	for _, r in ipairs(rows) do if r.key == "^ or Esc" then found = true end end
	check(found, "F1's keys say ^ or Esc")
	-- (0.65.1 review) .help says ^; what a command prints of the game's or a player's text keeps its `
	local helpSays = table.concat(ns.commands.help.run(""), "\n")
	check(helpSays:find("Alt+^", 1, true) and not helpSays:find("Alt+`", 1, true), ".help says Alt+^")
	local said
	local chat = _G.DEFAULT_CHAT_FRAME
	_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said = m end }
	ns:Output({ "Mail from Bob: `run` this macro" })
	_G.DEFAULT_CHAT_FRAME = chat
	check(said == "Mail from Bob: `run` this macro", "a player's text printed as it is, its ` kept: " .. tostring(said))
	-- (0.65.1 review) the apps' own keys: ^ closes the changelog, F1, the credits, atop, as ` does
	check(ns.TickAs("^") == "`" and ns.TickAs("A") == "A", "^ is ` to the apps' key tables")
	-- (0.65.1 review) the row menu closed with the terminal's key: its character isn't typed after it
	UI:Open("")
	T.typeText("hearth")
	FlushAll()
	local before = query()
	if UI.results[1] then
		UI:ShowRowMenu(1, true)
		key("^", "^")
		check(query() == before, "the row menu closed with ^: no ^ typed: " .. query())
	end
	UI:Hide(); FlushAll()

	-- bound with a modifier (Ctrl+Space): Ctrl+Space closes, Alt+Ctrl+Space is Alt+`'s; the hints say Ctrl+Space
	bound = { ["CTRL-SPACE"] = "TERMINAL_TOGGLE" }
	UI:Open("")
	withCtrl(function() key("SPACE") end)
	check(not UI:IsShown(), "Ctrl+Space bound: it closes the open terminal")
	UI:Open("")
	T.typeText("cast frost nova")
	withCtrl(function() withAlt(function() key("SPACE") end) end)
	FlushAll()
	check(UI:IsShown() and ns.Easy.temp ~= nil, "Alt+Ctrl+Space: Advanced mode for this search, as Alt+`")
	UI:Hide(); FlushAll()
	UI:EndAdvancedOnce()
	check(ns.KeyHint("Alt+` again") == "Alt+Ctrl+Space again", "hints: Alt+Ctrl+Space")
	-- (0.65.1 review) its Ctrl said once, and twice through it is the same
	local combat = ns.KeyHint(ns.L["In combat, Ctrl+` opens Terminal."])
	check(combat == "In combat, Ctrl+Space opens Terminal." and ns.KeyHint(combat) == combat, "in combat: Ctrl+Space, not Ctrl+Ctrl+Space: " .. combat)
	withCtrl(function() check(ns.TickAs("SPACE") == "`", "Ctrl+Space is ` to the apps' key tables (it quits a game, not passed to the game)") end)
	check(ns.TickAs("SPACE") == "SPACE", "Space alone types")
	-- (0.65.1 review) CTRL-` alone (the first run's choice when ` is taken): the hints as written, ` closes the open terminal
	bound = { ["CTRL-`"] = "TERMINAL_TOGGLE" }
	_G.GetBindingKey = function(action) for k, v in pairs(bound) do if v == action then return k end end end
	check(ns.ToggleLabel() == "`" and ns.KeyHint("in combat, Ctrl+` only") == "in combat, Ctrl+` only", "CTRL-` bound: hints as written, no Ctrl+Ctrl+`")
	-- (0.65.1 review) a key that types bound alone (Numpad5): hints don't name it (it types in the prompt)
	bound = { NUMPAD5 = "TERMINAL_TOGGLE" }
	check(ns.ToggleLabel() == "`", "Numpad5 bound: hints say ` (Numpad5 types)")
	-- (0.65.1 review) AltGr (Ctrl+Alt) on a key that types isn't one of Terminal's: CTRL-Q bound to fuzzy finding, AltGr+Q types @
	bound = { ["CTRL-Q"] = "TERMINAL_FUZZY", ["CTRL-SPACE"] = "TERMINAL_TOGGLE" }
	_G.GetBindingAction = function(k) return bound[k] or "" end
	local own
	withCtrl(function() withAlt(function() own = UI.OwnBinding("Q") end) end)
	check(own == nil, "AltGr+Q with Ctrl+Q bound to fuzzy finding: typed, not fuzzy finding: " .. tostring(own))
	bound = { ["CTRL-Q"] = "TERMINAL_TOGGLE" }
	withCtrl(function() withAlt(function() own = UI.OwnBinding("Q") end) end)
	check(own == nil, "AltGr+Q with Ctrl+Q the terminal's key: typed (AltGr), not Alt+`'s: " .. tostring(own))
	bound = { ["CTRL-Q"] = "TERMINAL_FUZZY", ["CTRL-SPACE"] = "TERMINAL_TOGGLE" }
	withCtrl(function() withAlt(function() own = UI.OwnBinding("SPACE") end) end)
	check(own == "TERMINAL_TOGGLE", "Alt+Ctrl+Space with Ctrl+Space the terminal's: still Alt+`'s")

	_G.GetBindingKey, _G.GetBindingAction, _G.IsAltKeyDown, _G.IsControlKeyDown = save.key, save.action, save.alt, save.ctrl
	ns.db.easyMode = save.easy; UI:EasyChanged()
	UI.lastScan = nil
end
