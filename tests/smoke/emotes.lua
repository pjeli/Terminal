-- Emotes (/dance, /silly) are slash rows read from the game's EMOTE<i>_CMD<j> strings, pressed by the game.
local T = ...
local ns, UI, S, check, log, logHas, key, FlushAll = T.ns, T.UI, T.S, T.check, T.log, T.logHas, T.key, T.FlushAll

io.write("[emotes as slash commands]\n")
do
	local set = {
		EMOTE1_TOKEN = "DANCE", EMOTE1_CMD1 = "/dance", EMOTE1_CMD2 = "/dance",
		EMOTE2_TOKEN = "SILLY", EMOTE2_CMD1 = "/silly", EMOTE2_CMD2 = "/joke",
		-- a gap in the numbering (the game's list has them)
		EMOTE5_TOKEN = "WAVE", EMOTE5_CMD1 = "/wave",
		-- an emote named like a real slash command: the command wins
		EMOTE6_TOKEN = "FOO", EMOTE6_CMD1 = "/foo",
	}
	for k, v in pairs(set) do _G[k] = v end
	local saveCount = ns.providers.slash._dirty
	_G.SLASH_EMOTETEST1 = "/emotetest"; SlashCmdList.EMOTETEST = function() end -- the list is re-read
	ns.providers.slash._dirty = true
	local rows = ns:GetEntries(ns.providers.slash)
	local by, foos = {}, 0
	for _, e in ipairs(rows) do
		by[e.name] = e
		if e.name == "/foo" then foos = foos + 1 end
	end
	check(by["/dance"] and by["/dance"].emote == "DANCE", "/dance is listed")
	check(by["/dance"] and not by["/dance"].detail:find("/dance", 1, true), "a repeated command isn't listed as its own alias: " .. tostring(by["/dance"] and by["/dance"].detail))
	check(by["/silly"] and by["/silly"].detail:find("/joke", 1, true), "/silly with its other name: " .. tostring(by["/silly"] and by["/silly"].detail))
	check(by["/wave"], "an emote after a gap in the numbering is listed")
	check(foos == 1 and not by["/foo"].emote, "a slash command of the same name wins over the emote")

	local r = UI:WordSearch(rows, "/joke")
	check(r[1] and r[1].name == "/silly", "the other name finds it: " .. tostring(r[1] and r[1].name))
	r = UI:WordSearch(rows, "/dnce")
	check(r[1] and r[1].name == "/dance", "fuzzy: /dnce finds /dance: " .. tostring(r[1] and r[1].name))

	-- Enter: the game runs the line (a macro runs an emote like chat does)
	UI:Open("/wave")
	local mark = #log
	key("ENTER")
	local mp = _G.TerminalMacroProxy
	check(S.armed == "MACRO" and mp and mp.attrs.macrotext == "/wave", "Enter: the game presses /wave: " .. tostring(mp and mp.attrs.macrotext))
	check(not logHas("CHAT /wave", mark + 1), "...not Terminal's chat box")
	mp.scripts.PostClick(mp, "LeftButton", true); FlushAll()
	UI:Disarm(); UI:Hide(); FlushAll()

	-- MAXEMOTEINDEX, when the client has it, bounds the walk
	local out = {}
	_G.MAXEMOTEINDEX = 2
	ns.SlashEmotes(out, {})
	check(#out == 2, "MAXEMOTEINDEX stops the walk: " .. #out)
	_G.MAXEMOTEINDEX = nil

	for k in pairs(set) do _G[k] = nil end
	_G.SLASH_EMOTETEST1, SlashCmdList.EMOTETEST = nil, nil
	ns.providers.slash._dirty = saveCount or true
end
