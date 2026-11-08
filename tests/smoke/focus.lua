-- Out of focus (1.1.7, the player: with .zen off, a click outside Terminal leaves it open, out of focus, its keys the
-- game's; a click on it or its open key gives it the keyboard back). Keys.lua's UI:Blur / UI:Focus.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll

io.write("[focus: a click outside leaves Terminal up, its keys the game's]\n")
do
	local F = _G.TerminalFrame
	local over = false
	local wasOver = F.IsMouseOver
	F.IsMouseOver = function() return over end
	local function Click(on)
		over = on
		UI.focusWatch.scripts.OnEvent(UI.focusWatch, "GLOBAL_MOUSE_DOWN", "LeftButton")
		FlushAll()
	end
	local zenWas = ns.Zen.active
	ns.Zen.active = false
	UI:Open(""); FlushAll()
	T.typeText("hog"); FlushAll()
	check(UI:IsShown() and F.kb == true and not UI.blurred, "(open, typing: the keyboard Terminal's)")
	-- a click on the world
	Click(false)
	check(UI:IsShown() and UI.blurred and F.kb == false and UI.caret.shown == false and T.query() == "hog",
		"a click outside: still up, out of focus, the keyboard the game's, no cursor: " .. tostring(F.kb))
	-- (something asks for the keys meanwhile, a fight ending: they stay the game's)
	UI:EnterKeys()
	check(F.kb == false and UI.blurred, "the keyboard asked for while out of focus: still the game's")
	-- a click on Terminal: back, as it was
	Click(true)
	check(UI:IsShown() and not UI.blurred and F.kb == true and UI.caret.shown ~= false and T.query() == "hog",
		"a click on it: in focus again, the text as it was")
	-- its open key while out of focus gives the keyboard back; a second press closes it
	Click(false)
	UI:Toggle()
	check(UI:IsShown() and not UI.blurred and F.kb == true, "out of focus, its key: back in focus, not closed")
	UI:Toggle(); FlushAll()
	check(not UI:IsShown(), "and again: closed")
	-- closed while out of focus, opened again: in focus
	UI:Open("x"); FlushAll()
	Click(false)
	UI:Hide(); FlushAll()
	UI:Open("x"); FlushAll()
	check(not UI.blurred and F.kb == true, "closed out of focus, opened again: in focus")
	-- a click on its row menu, its tooltip...: Terminal's own
	local menu = _G.TerminalRowMenu
	if menu then
		local mo = menu.IsMouseOver
		menu.shown, menu.IsMouseOver = true, function() return true end
		Click(false)
		check(not UI.blurred, "a click on its row menu: still in focus")
		menu.shown, menu.IsMouseOver = false, mo
	end
	-- .zen on: its dimming takes the click (and closes the terminal), nothing here
	ns.Zen.active = true
	Click(false)
	check(not UI.blurred and F.kb == true, ".zen on: not out of focus (its dimming closes it)")
	ns.Zen.active = zenWas
	UI:Hide(); FlushAll()
	F.IsMouseOver = wasOver
end

io.write("[focus: review 1.1.19: the toggle key's ` isn't typed when it gives the keys back]\n")
do
	local F = _G.TerminalFrame
	local wasOver = F.IsMouseOver
	local over = false
	F.IsMouseOver = function() return over end
	local zenWas = ns.Zen.active
	ns.Zen.active = false
	UI:Open(""); FlushAll()
	T.typeText("hog"); FlushAll()
	UI.focusWatch.scripts.OnEvent(UI.focusWatch, "GLOBAL_MOUSE_DOWN", "LeftButton")
	check(UI.blurred, "(out of focus)")
	UI.swallowTick = nil
	UI:Toggle()
	check(not UI.blurred and UI.swallowTick ~= nil and T.query() == "hog",
		"` gave the keys back, its character to come dropped (DropTick): " .. tostring(UI.swallowTick))
	UI:Hide(); FlushAll()
	ns.Zen.active = zenWas
	F.IsMouseOver = wasOver
end

io.write("[focus: 1.2.1: a Shift chord bound to Terminal doesn't type its character into a kept search]\n")
do -- (a player on CurseForge: "I used shift+~, enter "nearest vendor", close terminal, go to reopen and it will have
	-- "nearest vendor~" unless I empty the text first")
	local F = _G.TerminalFrame
	local Th = ns.Theme
	local was = { keep = Th.Get().keepSession, tabs = ns.db.tabs, time = _G.GetTime, bind = _G.GetBindingKey,
		shift = _G.IsShiftKeyDown, easy = ns.db.easyMode }
	local now, bound = 1000, "SHIFT-`"
	_G.GetTime = function() return now end
	_G.GetBindingKey = function(action) if action == "TERMINAL_TOGGLE" then return bound end return was.bind(action) end
	Th.Get().keepSession = true
	ns.db.tabs = nil
	ns.db.easyMode = false; UI:EasyChanged()
	local function Reopen(ch)
		_G.IsShiftKeyDown = function() return true end
		UI:Toggle()
		F.scripts.OnChar(F, ch)
		_G.IsShiftKeyDown = was.shift
		FlushAll()
	end
	Reopen("~")
	check(UI:IsShown() and T.query() == "", "Shift+` opens it, its ~ not typed: " .. T.query())
	T.typeText("linen"); FlushAll()
	UI:Hide(); FlushAll()
	now = now + 600
	Reopen("~")
	check(UI:IsShown() and T.query() == "linen", "reopened on the kept search: no ~ after it: " .. T.query())
	F.scripts.OnChar(F, "~"); FlushAll()
	check(T.query() == "linen~", "a ~ typed after that is typed: " .. T.query())
	UI:Hide(); FlushAll()
	-- a German keyboard: Shift+^ types °
	bound = "SHIFT-^"
	ns.db.tabs = { list = { { text = "linen" } }, cur = 1 }
	now = now + 600
	Reopen("°")
	check(T.query() == "linen", "Shift+^ bound: its ° not typed: " .. T.query())
	UI:Hide(); FlushAll()
	check(not ns.IsToggleChar("a") and not ns.IsToggleChar(" ") and not ns.IsToggleChar("@"),
		"a letter, a space, a symbol with Shift up: never the key's")
	ns.db.tabs, Th.Get().keepSession = was.tabs, was.keep
	ns.db.easyMode = was.easy; UI:EasyChanged()
	_G.GetTime, _G.GetBindingKey, _G.IsShiftKeyDown = was.time, was.bind, was.shift
end
