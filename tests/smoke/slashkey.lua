-- The / key opens Terminal on a slash command (0.56.9, the player's ask): an override of the game's own / (the chat box),
-- out of combat only, while / is still the game's; the "/" lands in a fresh prompt once (UI/SlashKey.lua).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local SK = ns.SlashKey

io.write("[slashkey: / opens Terminal on a slash command]\n")
do
	local save = { action = _G.GetBindingAction, set = _G.SetOverrideBinding, combat = _G.InCombatLockdown, easy = ns.db.easyMode,
		print = ns.Print }
	local base, over, combat, said = { ["/"] = "OPENCHATSLASH" }, {}, false, {}
	_G.GetBindingAction = function(k) return base[k] or "" end
	_G.SetOverrideBinding = function(o, _, k, cmd) over[k] = cmd; return save.set and save.set(o, _, k, cmd) end
	_G.InCombatLockdown = function() return combat end
	ns.Print = function(_, m) said[#said + 1] = m end
	-- (0.56.14, the author's call) off unless turned on; a theme saved by the test builds, when it was on for everyone, too
	local theme = ns.db.theme
	ns.db.theme = { v = 3, preset = "forever", slashKey = true }
	check(ns.Theme.Get().slashKey == false and ns.Theme.Get().v == 4, "a test build's theme: off now")
	ns.db.theme = {}
	check(ns.Theme.Get().slashKey == false, "a new theme: off")
	ns.db.theme = theme
	ns.Theme.Set("slashKey", "off")
	SK.OnEvent(nil, "PLAYER_LOGIN")
	check(not SK.Applied() and over["/"] == nil, "off: / is the chat box's")
	ns.Theme.Set("slashKey", "on")
	check(SK.Applied() and over["/"] == "TERMINAL_SLASH", "turned on, / the game's chat key: Terminal's now: " .. tostring(over["/"]))
	check(#said == 0, "nothing said in chat (you turned it on)")
	-- combat: the chat box's again (taken off before the game locks bindings), back after
	SK.OnEvent(nil, "PLAYER_REGEN_DISABLED")
	check(not SK.Applied() and over["/"] == nil, "combat: / opens the chat box")
	combat = true
	SK.OnEvent(nil, "UPDATE_BINDINGS")
	check(not SK.Applied(), "not set again during the fight")
	combat = false
	SK.OnEvent(nil, "PLAYER_REGEN_ENABLED")
	check(SK.Applied() and over["/"] == "TERMINAL_SLASH", "out of combat: Terminal's again")
	-- off in the settings; / bound to something else of yours: left alone
	ns.Theme.Set("slashKey", "off")
	check(not SK.Applied() and over["/"] == nil, ".set slashKey off: the game's again")
	ns.Theme.Set("slashKey", "on")
	check(SK.Applied(), "on again")
	base["/"] = "MYMACRO"
	SK.Apply()
	check(not SK.Applied() and over["/"] == nil, "/ bound to something else: left alone")
	base["/"] = "OPENCHATSLASH"
	SK.Apply()

	-- the key: a fresh prompt with "/" (the slash commands), the key's own "/" not typed twice
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("hearthstone"); FlushAll()
	UI:Hide(); FlushAll() -- (closed a moment ago: Toggle would bring "hearthstone" back; / starts afresh)
	UI:SlashOpen(); FlushAll()
	check(UI:IsShown() and UI.edit:GetText() == "/" and UI.cursor == 1, "/: open on a fresh \"/\": " .. UI.edit:GetText())
	UI:OnChar("/"); FlushAll()
	check(UI.edit:GetText() == "/", "the key's own / isn't typed again: " .. UI.edit:GetText())
	UI:OnChar("r"); FlushAll()
	check(UI.edit:GetText() == "/r", "then typing goes on: " .. UI.edit:GetText())
	local slash = false
	for _, e in ipairs(UI.Results()) do if e.kind == "slash" then slash = true end end
	check(slash, "the slash commands listed")
	UI:Hide(); FlushAll()

	_G.GetBindingAction, _G.SetOverrideBinding, _G.InCombatLockdown = save.action, save.set, save.combat
	ns.Theme.Set("slashKey", "off")
	SK.OnEvent(nil, "PLAYER_REGEN_DISABLED") -- (the override off, as the other tests expect)
	ns.Print, ns.db.easyMode = save.print, save.easy
	UI:EasyChanged()
end
