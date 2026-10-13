-- Terminal Extras (Apps/Extras.lua, 0.47.8, the player's ask): the games and the radio in a load-on-demand addon of
-- their own; Terminal keeps stand-in commands that load it the first time one is run.
local T = ...
local ns, check = T.ns, T.check

io.write("[terminal extras: loaded on demand]\n")
do
	local X = ns.Extras
	check(X and X.stubs and X.stubs.snake and X.stubs.typing and X.stubs.wowamp, "Terminal keeps the stand-ins")
	io.write(("  (the extras take %.0f KB of Lua memory once loaded)\n"):format(_G.SMOKE_EXTRAS_KB or 0))
	-- the harness loaded the extras: their real commands replaced the stand-ins
	check(ns.commands.snake ~= X.stubs.snake and ns.commands.typing ~= X.stubs.typing, "loaded: the real commands")
	check(ns:FindCommand("wpm") == ns.commands.typing and ns:FindCommand("radio") == ns.commands.wowamp, "aliases reach them")
	-- as the game starts: only the stand-ins; running one loads the extras, which put the real one in its place
	local real = { snake = ns.commands.snake, typing = ns.commands.typing }
	ns.commands.snake = X.stubs.snake
	local AO = _G.C_AddOns
	local loads, loadedNow, reason = 0, false, nil
	_G.C_AddOns = setmetatable({
		IsAddOnLoaded = function(n) if n == X.ADDON then return loadedNow end return true end,
		LoadAddOn = function(n)
			loads = loads + 1
			if reason then return false, reason end
			if n == X.ADDON then loadedNow = true; ns.commands.snake = real.snake; return true end
			return false, "MISSING"
		end }, { __index = AO })
	local opened = false
	local openWas = ns.Snake.Open
	ns.Snake.Open = function() opened = true return true end
	ns:FindCommand("snake").run("")
	check(loads == 1 and loadedNow and opened and ns.commands.snake == real.snake, "the stand-in loaded the extras and opened Snake")
	ns:FindCommand("snake").run("")
	check(loads == 1, "loaded once")
	-- switched off in the AddOn list, or not installed: said
	ns.commands.snake, loadedNow, opened = X.stubs.snake, false, false
	local said
	local printWas = ns.Print
	ns.Print = function(_, s) said = s end
	reason = "DISABLED"
	ns:FindCommand("snake").run("")
	check(not opened and said and said:find("switched off", 1, true), "switched off: said: " .. tostring(said))
	reason = "MISSING"
	ns:FindCommand("snake").run("")
	check(said and said:find("isn't installed", 1, true), "missing: said")
	-- loaded, but without the command (an old copy): said, never the stand-in running itself
	reason = nil
	ns.commands.typing = X.stubs.typing
	local typingWas = real.typing
	_G.C_AddOns.LoadAddOn = function() loadedNow = true return true end
	ns:FindCommand("typing").run("")
	check(said and said:find("isn't in it", 1, true), "an old copy without it: said")
	ns.Print = printWas
	ns.Snake.Open = openWas
	ns.commands.snake, ns.commands.typing = real.snake, typingWas
	_G.C_AddOns = AO
	-- the radio's zone music, back after a /reload (the extras not loaded then)
	ns.db.wowamp = ns.db.wowamp or {}
	ns.db.wowamp.musicWasOn = true
	local cv
	local cvWas = _G.C_CVar
	_G.C_CVar = setmetatable({ SetCVar = function(k, v) cv = k .. "=" .. v end }, { __index = cvWas })
	local wowampWas = ns.Wowamp
	ns.Wowamp = nil
	X.loginFrame.scripts.OnEvent(X.loginFrame, "PLAYER_LOGIN")
	check(cv == "Sound_EnableMusic=1" and ns.db.wowamp.musicWasOn == nil, "the zone music back at login")
	-- the radio playing (the extras loaded since, and it's on): the zone music stays off
	cv = nil
	ns.db.wowamp.musicWasOn = true
	ns.Wowamp = wowampWas
	local playingWas = wowampWas.Playing
	wowampWas.Playing = function() return true end
	X.loginFrame.scripts.OnEvent(X.loginFrame, "PLAYER_LOGIN")
	wowampWas.Playing = playingWas
	check(cv == nil and ns.db.wowamp.musicWasOn == true and type(playingWas) == "function", "the radio playing: the zone music stays off (WoWamp says so)")
	ns.db.wowamp.musicWasOn = nil
	ns.Wowamp, _G.C_CVar = wowampWas, cvWas
	-- none of the extras' files is in Terminal's own TOC
	local toc = io.open("Terminal/Terminal.toc"):read("*a")
	check(not toc:find("Snake.lua", 1, true) and not toc:find("Wowamp.lua", 1, true) and toc:find("Apps\\Extras.lua", 1, true),
		"Terminal's TOC: only the stand-ins")
end
