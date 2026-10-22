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
	local said
	local chat = _G.DEFAULT_CHAT_FRAME
	_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said = m end }
	ns:Output({ ns.L["Esc or ` close"] })
	_G.DEFAULT_CHAT_FRAME = chat
	check(said == "Esc or ^ close", "a command's answer says ^ too: " .. tostring(said))

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

	_G.GetBindingKey, _G.GetBindingAction, _G.IsAltKeyDown, _G.IsControlKeyDown = save.key, save.action, save.alt, save.ctrl
	ns.db.easyMode = save.easy; UI:EasyChanged()
	UI.lastScan = nil
end
