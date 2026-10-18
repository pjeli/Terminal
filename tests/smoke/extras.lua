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

-- (0.49.3, the player's ask) the games tell your guild a score with the typing test's keys, said in the footer: Enter on
-- the game-over screen tells it (once a game, a score worth telling, with the [Terminal] banner) and closes the game (the
-- chat shows it; .zen's interface comes back), Tab plays again
io.write("[extras: games tell your guild]\n")
do
	local save = { chat = _G.C_ChatInfo, guild = _G.IsInGuild, print = ns.Print, combat = _G.InCombatLockdown }
	local sent, printed = {}, nil
	_G.C_ChatInfo = setmetatable({ SendChatMessage = function(text, chan) sent[#sent + 1] = { text, chan } end,
		InChatMessagingLockdown = function() return false end }, { __index = save.chat })
	_G.IsInGuild = function() return true end
	_G.InCombatLockdown = function() return false end
	ns.Print = function(_, s) printed = s end
	local games = {
		{ ns.Snake, "^%[Terminal%] Snake: 23 points %(a new best%)", function(g) g.score = 23; g.newBest = true end },
		{ ns.Tetris, "^%[Terminal%] Tetris: 4200 points, 31 lines%.", function(g) g.score, g.lines, g.newBest = 4200, 31, false end },
		{ ns.LootRun, "^%[Terminal%] Loot Run: 3150 points, level 4 %(a new best%)", function(g) g.score, g.level, g.newBest = 3150, 4, true end },
	}
	for _, it in ipairs(games) do
		local G, want, set = it[1], it[2], it[3]
		G.Open()
		local g = G.game
		-- in play Enter tells nobody (Tetris drops a piece with it), and the footer says the game's keys
		local before = #sent
		G.KeyDown(G.frame, "ENTER")
		check(#sent == before and G.IsShown(), "in play: Enter tells nobody")
		G.Draw()
		check(not G.footer:GetText():find(ns.L["Enter tell your guild"], 1, true), "in play: the footer says the game's keys")
		g.keys = g.keys and {} -- (Tetris: the Enter is let go)
		-- game over (a moment ago): the footer says Enter tells your guild, Tab plays again (as the typing test's)
		g.over, g.overAt = true, GetTime() - 5
		set(g)
		G.Draw()
		check(G.footer:GetText():find(ns.L["Enter tell your guild"], 1, true) and G.footer:GetText():find(ns.L["Tab again"], 1, true),
			"game over: the footer says Enter tells your guild, Tab plays again: " .. tostring(G.footer:GetText()))
		-- Tab plays again
		G.KeyDown(G.frame, "TAB")
		check(not g.over and not g.sent and G.IsShown(), "Tab: a new game")
		-- a score of 0: nothing to tell (the footer doesn't offer it), Enter does nothing
		g.over, g.score, g.overAt = true, 0, GetTime() - 5
		G.Draw()
		check(not G.footer:GetText():find(ns.L["Enter tell your guild"], 1, true), "a score of 0: the footer doesn't offer telling")
		G.KeyDown(G.frame, "ENTER")
		check(#sent == before and G.IsShown(), "a score of 0: nobody told, the game stays")
		-- a score: Enter tells your guild, once, and closes (the chat shows it; .zen's interface comes back)
		set(g)
		G.KeyDown(G.frame, "ENTER")
		local line = sent[#sent]
		check(#sent == before + 1 and line[2] == "GUILD" and line[1]:find(want) and line[1]:find("^%[Terminal%]") and not line[1]:find("CurseForge", 1, true) and not line[1]:find("?", 1, true)
			and #line[1] <= 255, "game over, Enter: the guild told: " .. tostring(line and line[1]))
		check(g.sent and not G.IsShown(), "and the game closes")
		check(not G.TellGuild() and #sent == before + 1 and tostring(printed):find("heard", 1, true), "only once a game")
		G.Reset()
		G.Close()
	end
	check(ns.Game.OverKeys(5, false):find(ns.L["Enter tell your guild"], 1, true) and ns.Game.OverKeys(5, true):find(ns.L["Your guild heard it"], 1, true)
		and not ns.Game.OverKeys(0, false):find(ns.L["Enter tell your guild"], 1, true), "the game-over keys say Enter (when there's a score)")
	-- (review, 0.49.17) filling the board again ties the best: not "a new best"
	ns.Snake.game.score, ns.Snake.game.won, ns.Snake.game.newBest = 297, true, false
	check(not ns.Snake.Brag():find("new best", 1, true), "a tie isn't a new best: " .. ns.Snake.Brag())
	-- not in a guild: said, nothing sent
	ns.Snake.Open()
	ns.Snake.game.over, ns.Snake.game.score = true, 3
	_G.IsInGuild = function() return false end
	local n = #sent
	ns.Snake.KeyDown(ns.Snake.frame, "ENTER")
	check(#sent == n and tostring(printed):find("not in a guild", 1, true) and not ns.Snake.game.sent, "not in a guild: said, nothing sent")
	ns.Snake.Reset(); ns.Snake.Close()
	_G.C_ChatInfo, _G.IsInGuild, ns.Print, _G.InCombatLockdown = save.chat, save.guild, save.print, save.combat
end

do -- (review, 0.53.6) each real command as its stand-in names it: one description and the same other names
	local ns, check = T.ns, T.check
	local X = ns.Extras
	local same = true
	for _, c in ipairs(X.COMMANDS) do
		local real = ns.commands[c[1]]
		if not real or real == X.stubs[c[1]] or real.desc ~= c[2] or table.concat(real.aliases or {}, ",") ~= table.concat(c[3] or {}, ",") then
			same = false
		end
	end
	check(same, "the extras' commands: their stand-ins' words")
	check(type(ns.commands.wowamp.complete) == "function" and #ns.commands.wowamp.complete("") > 2, ".wowamp completes its stations")
	-- the best kept alike: a game that isn't one isn't "a new best"
	local g = { score = 1 }
	local was = ns.db.snakeBest
	ns.db.snakeBest = 5
	ns.Game.KeepBest(g, "snakeBest")
	check(g.newBest == false and ns.db.snakeBest == 5, "under the best: kept as it was")
	g.score = 9
	ns.Game.KeepBest(g, "snakeBest")
	check(g.newBest == true and ns.db.snakeBest == 9, "over it: the new best")
	ns.db.snakeBest = was
end

do -- (review, 0.53.6) Tetris draws its stack again only when a piece locks, not on every row a piece falls
	local ns, check = T.ns, T.check
	local TT = ns.Tetris
	TT.Open()
	local before = TT.stackDraws
	for _ = 1, 3 do TT.Drop(false); TT.DrawChanged() end
	check(TT.stackDraws == before, "falling rows: the stack left as it was: " .. (TT.stackDraws - before))
	TT.HardDrop()
	if TT.game.dirty then TT.DrawChanged() end
	check(TT.stackDraws == before + 1, "a piece locked: the stack drawn once: " .. (TT.stackDraws - before))
	-- (review, 0.57.7) game over: the board drawn again (the piece that ended it shows)
	before = TT.stackDraws
	TT.GameOver()
	TT.DrawChanged()
	check(TT.stackDraws == before + 1, "game over: the board drawn again: " .. (TT.stackDraws - before))
	TT.Close()
end

do -- (review, 0.53.6) Snake places only the new head on a move; the old tail's texture is used again
	local ns, check = T.ns, T.check
	local S = ns.Snake
	S.Open()
	S.Draw()
	local placedBefore = {}
	for c, t in pairs(S.placed) do placedBefore[c] = t end
	local head = S.game.body[1]
	local tex = S.placed[head]
	local moved = 0
	local set = tex.SetPoint
	tex.SetPoint = function(...) moved = moved + 1 return set(...) end
	S.Step(); S.Draw()
	tex.SetPoint = set
	local n = 0
	for _ in pairs(S.placed) do n = n + 1 end
	check(n == #S.game.body and S.placed[head] == tex and moved == 0, "a move: the old head stays where it was placed: " .. moved)
	S.Close()
end
