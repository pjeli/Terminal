-- What a game-pressed macro may call (0.46.2), how .debug blames a /run line's blocks, and the after-press taint check.
--
-- A /run line runs tainted even when the game presses it: the game blames what it does on "*** ForceTaint_Strong ***"
-- (0.46.1: WorldMapFrame:SetMapID from one left the map's pins blocked in combat). So a /run line may only call the
-- game's own C functions (C_*, a few legacy C globals) and Lua's; anything else (Blizzard's Lua: a window's functions,
-- a frame's methods) fails this test, unless it's on ALLOW below with the reason no clean route exists. Lines that
-- aren't /run (/click, /cast, /use, /equip, chat) are the game's own commands: clean.
local T = ...
local ns, UI, check, Flush, FlushAll = T.ns, T.UI, T.check, T.Flush, T.FlushAll
local S, D = ns.Secure, ns.Debug

-- Blizzard Lua a /run line still calls: each with the files that may and why it stays (no game call or named button does
-- it, and nothing protected sits behind it). A new one fails the test; an entry no file uses any more fails it too.
local ALLOW = {
	ChatEdit_InsertLink = { files = { "Core/Core.lua" }, why = "puts text in the chat box: no game call or button does" },
	ChatFrame_OpenChat = { files = { "Core/Core.lua" }, why = "opens the chat box with text: no game call or button does" },
	OpenAchievementFrameToAchievement = { files = { "Providers/Achievements.lua" }, why = "no game call opens an achievement; nothing protected in that window" },
	ToggleAchievementFrame = { files = { "Providers/Achievements.lua" }, why = "(the same line's fallback)" },
	AddonList = { files = { "Providers/Panels.lua", "Providers/Addons.lua" }, why = "no game call or button opens the AddOn list; nothing protected in it" },
	ShowUIPanel = { files = { "Providers/Panels.lua", "Providers/Addons.lua", "Providers/Keybinds.lua" }, why = "the AddOn list / Quick Keybind Mode (above / below)" },
	HideUIPanel = { files = { "Providers/Keybinds.lua" }, why = "the settings window stepping aside for Quick Keybind Mode" },
	SettingsPanel = { files = { "Providers/Keybinds.lua" }, why = "read, to hide it for Quick Keybind Mode" },
	QuickKeybindFrame = { files = { "Providers/Keybinds.lua" }, why = "no game call or button starts Quick Keybind Mode" },
	-- the whisper box (SO.WhisperMacro: built from pieces, so only the run-time lint sees it)
	ChatFrame_SendTell = { files = {}, why = "opens the whisper box: no game call or button does" },
	ChatFrame_SendBNetTell = { files = {}, why = "opens a Battle.net whisper box: no game call or button does" },
	ChatFrameUtil = { files = {}, why = "(the same, newer clients' name)" },
}
-- the game's own functions that aren't in a C_ table (legacy C API), and Lua's
local C_GLOBALS = { SetCurrentTitle = true, BNGetNumFriends = true, GetTime = true, UnitName = true }
local LUA = { ipairs = true, pairs = true, type = true, tostring = true, tonumber = true, select = true, unpack = true,
	print = true, math = true, string = true, table = true, next = true, pcall = true }
local KEYWORDS = {}
for w in ("and break do else elseif end false for function if in local nil not or repeat return then true until while"):gmatch("%a+") do
	KEYWORDS[w] = true
end

--- The globals a piece of Lua code (a /run line's) uses: { name = true }. Locals it declares (local x, for k, v,
--- function(a, b)) and fields after . or : aren't globals; string literals and format placeholders are left out.
local function NoStrings(code)
	local out, i, n = {}, 1, #code
	while i <= n do
		local c = code:sub(i, i)
		if c == '"' or c == "'" then
			local j = i + 1
			while j <= n and code:sub(j, j) ~= c do
				if code:sub(j, j) == "\\" then j = j + 1 end
				j = j + 1
			end
			out[#out + 1] = ' "" '
			i = j + 1
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
	return table.concat(out)
end

local function Globals(code)
	code = code:gsub("%%[%-%d%.]*[dsqfx]", " 0 "):gsub("%%%%", " ")
	code = NoStrings(code)
	local locals, out = {}, {}
	for list in code:gmatch("local%s+([%a_][%w_%s,]*)") do
		for n in list:gmatch("[%a_][%w_]*") do if not KEYWORDS[n] then locals[n] = true end end
	end
	for list in code:gmatch("for%s+([%a_][%w_%s,]*)") do
		for n in list:gmatch("[%a_][%w_]*") do if n ~= "in" then locals[n] = true end end
	end
	for list in code:gmatch("function%s*%(([^)]*)%)") do
		for n in list:gmatch("[%a_][%w_]*") do locals[n] = true end
	end
	local i = 1
	while true do
		local s, e, name = code:find("([%a_][%w_]*)", i)
		if not s then break end
		local before = s > 1 and code:sub(s - 1, s - 1) or ""
		local field = before == "." or before == ":"
		if not field and not code:sub(s - 1, s - 1):match("[%w_]") then
			if not (KEYWORDS[name] or locals[name] or LUA[name] or C_GLOBALS[name] or name:match("^C_")) then out[name] = true end
		end
		i = e + 1
	end
	return out
end

--- The /run lines of a macro's text: the code after each "/run " (or "/script ").
local function RunLines(text)
	local out = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local code = line:match("^%s*/run%s+(.*)$") or line:match("^%s*/script%s+(.*)$")
		if code then out[#out + 1] = code end
	end
	return out
end

--- Every string literal in a Lua file (its text as written, escapes kept): { text, line }. Comments are skipped.
local function Literals(src)
	local out, i, n, line = {}, 1, #src, 1
	while i <= n do
		local c = src:sub(i, i)
		if c == "\n" then line = line + 1; i = i + 1
		elseif src:sub(i, i + 1) == "--" then
			local long = src:match("^%-%-%[(=*)%[", i)
			if long then
				local close = src:find("]" .. long .. "]", i, true)
				local chunk = src:sub(i, close or n)
				for _ in chunk:gmatch("\n") do line = line + 1 end
				i = (close or n) + #long + 2
			else
				local nl = src:find("\n", i, true) or n + 1
				i = nl
			end
		elseif c == '"' or c == "'" then
			local j = i + 1
			while j <= n do
				local d = src:sub(j, j)
				if d == "\\" then j = j + 2
				elseif d == c or d == "\n" then break
				else j = j + 1 end
			end
			out[#out + 1] = { text = src:sub(i + 1, j - 1), line = line }
			i = j + 1
		elseif src:match("^%[=*%[", i) then
			local eq = src:match("^%[(=*)%[", i)
			local close = src:find("]" .. eq .. "]", i, true) or n
			local body = src:sub(i + #eq + 2, close - 1)
			out[#out + 1] = { text = body, line = line }
			for _ in body:gmatch("\n") do line = line + 1 end
			i = close + #eq + 2
		else
			i = i + 1
		end
	end
	return out
end

--- A literal's text with its escapes read (\n, \", \\, \124): what the game gets.
local function Unescape(t)
	return (t:gsub("\\(%d%d?%d?)", function(d) return string.char(tonumber(d)) end):gsub("\\n", "\n"):gsub('\\"', '"')
		:gsub("\\'", "'"):gsub("\\\\", "\\"))
end

local function Allowed(name, file)
	local a = ALLOW[name]
	if not a then return false end
	if not file then return true end
	for _, f in ipairs(a.files) do if f == file then return true end end
	return false
end

io.write("[macros: /run lines call the game's own functions only]\n")
do
	-- the lint itself, on lines it must judge right
	local g = Globals('QuestMapFrame_OpenToQuestDetails(33)')
	check(g.QuestMapFrame_OpenToQuestDetails, "the lint: Blizzard Lua is caught")
	g = Globals('C_Map.OpenWorldMap(%d)')
	check(next(g) == nil, "the lint: a game call passes")
	g = Globals('local b=PlayerSpellsFrame.SpellBookFrame if b.GoToSpell then b:GoToSpell(%d,true) end')
	check(g.PlayerSpellsFrame and not g.b and not g.GoToSpell, "the lint: a local's methods are judged by where it came from")
	g = Globals('local q=%d C_QuestLog.SetSelectedQuest(q) StaticPopup_Show("ABANDON_QUEST",C_QuestLog.GetTitleForQuestID(q))')
	check(g.StaticPopup_Show and not g.q and not g.ABANDON_QUEST, "the lint: string literals aren't names, locals aren't globals")
	g = Globals('C_Timer.After(.1,function() local t="x" if not ChatEdit_InsertLink(t) then ChatFrame_OpenChat(t) end end)')
	check(g.ChatEdit_InsertLink and g.ChatFrame_OpenChat and not g.t, "the lint: inside a function body too")
	g = Globals('for i=1,BNGetNumFriends() do local a=C_BattleNet.GetFriendAccountInfo(i) if a and a.battleTag=="x" then (ChatFrame_SendBNetTell or ChatFrameUtil.SendBNetTell)(a.accountName) end end')
	check(g.ChatFrame_SendBNetTell and g.ChatFrameUtil and not g.a and not g.i and not g.BNGetNumFriends, "the lint: a called (a or b) and legacy C globals")

	-- every /run line written in the code: Blizzard Lua only where ALLOW lets it
	local used, bad, scanned = {}, {}, 0
	for path in io.lines("Terminal/Terminal.toc") do
		path = path:gsub("\r", "")
		if path:match("%.lua$") and not path:match("^#") then
			local file = path:gsub("\\", "/")
			local fh = io.open("Terminal/" .. file)
			if fh then
				local src = fh:read("*a"); fh:close()
				for _, lit in ipairs(Literals(src)) do
					if lit.text:find("/run", 1, true) or lit.text:find("/script", 1, true) then
						for _, code in ipairs(RunLines(Unescape(lit.text))) do
							scanned = scanned + 1
							for name in pairs(Globals(code)) do
								if Allowed(name, file) then used[name] = true
								else bad[#bad + 1] = ("%s:%d calls %s"):format(file, lit.line, name) end
							end
						end
					end
				end
			end
		end
	end
	table.sort(bad)
	check(scanned >= 10, "the code's /run lines were found: " .. scanned)
	check(#bad == 0, "no /run line written in the code calls Blizzard Lua (a game call, /click or a binding instead, or ALLOW with its reason): "
		.. table.concat(bad, "; "))
	-- and every macro the code handed the game while the tests ran (lines built from pieces too)
	local runBad, runCount = {}, 0
	for text in pairs(_G.SMOKE_MACROS or {}) do
		for _, code in ipairs(RunLines(text)) do
			runCount = runCount + 1
			for name in pairs(Globals(code)) do
				if Allowed(name) then used[name] = true
				else runBad[#runBad + 1] = name .. " in " .. text:gsub("\n", " | "):sub(1, 90) end
			end
		end
	end
	table.sort(runBad)
	check(runCount >= 5 and #runBad == 0, "no macro handed to the game during the tests calls Blizzard Lua (" .. runCount .. " /run lines): "
		.. table.concat(runBad, "; "))
	-- the old routes are gone
	local gone = {}
	for text in pairs(_G.SMOKE_MACROS or {}) do
		for _, name in ipairs({ "QuestMapFrame_OpenToQuestDetails", "GoToSpell", "OpenToSpellBookTab", "StaticPopup_Show",
			"QuestMapQuestOptions_AbandonQuest", "Settings.OpenToCategory", "ToggleCharacter", "SetCollectionsJournalShown", "SetMapID" }) do
			if text:find(name, 1, true) then gone[#gone + 1] = name end
		end
	end
	check(#gone == 0, "none of the routes 0.46.2 replaced is pressed any more: " .. table.concat(gone, ", "))
	-- ALLOW stays honest: each entry is still used (in the code, or by a line built at run time)
	local stale = {}
	for name, a in pairs(ALLOW) do
		if not used[name] and #a.files > 0 then stale[#stale + 1] = name end
	end
	table.sort(stale)
	check(#stale == 0, "every ALLOW entry is still needed: " .. table.concat(stale, ", "))
end

io.write("[macros: .debug blames a /run line's blocks on Terminal's press]\n")
do
	local FT = "*** ForceTaint_Strong ***"
	local clock = 5000
	local realTime = _G.GetTime
	_G.GetTime = function() return clock end
	for i = #D.events, 1, -1 do D.events[i] = nil end
	for i = #S.presses, 1, -1 do S.presses[i] = nil end
	local realPrint = ns.Print
	local printed = {}
	ns.Print = function(_, m) printed[#printed + 1] = m end
	local mine, others = D.count, D.others
	-- no /run press this session: another addon's (or your own macro's)
	D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", FT, "Button:SetPassThroughButtons()")
	check(D.count == mine and D.others == others + 1 and D.events[#D.events].cheap, "no /run press of Terminal's: counted as another's")
	-- a /run press just before: Terminal's, its macro named, the chat line printed
	S.NotePress("/run C_Map.OpenWorldMap(1413)", "Enter")
	clock = clock + 0.4
	D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", FT, "Button:SetPassThroughButtons()")
	local ev = D.events[#D.events]
	check(D.count == mine + 1 and ev.runPress and ev.runPress.via == "Enter" and not ev.cheap,
		"a ForceTaint_Strong block 0.4 s after Terminal's /run press: Terminal's")
	local lines = table.concat(D.Describe(ev), "\n")
	check(lines:find("Terminal's /run press", 1, true) and lines:find("0.4 s before (Enter): /run C_Map.OpenWorldMap(1413)", 1, true),
		"its record names the press: " .. lines:sub(1, 200))
	check(printed[#printed] and printed[#printed]:find("Blocked Button:SetPassThroughButtons()", 1, true), "and says so in chat, as Terminal's own")
	-- the same call again at once (taint spreading): folded into that record
	D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", FT, "Button:SetPassThroughButtons()")
	check(ev.times == 2 and D.count == mine + 2, "repeats fold into its record: x" .. tostring(ev.times))
	-- minutes later (delayed taint): another's, but the last /run press is named so the player can judge
	clock = clock + 240
	D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", FT, "Frame:SetAttribute()")
	ev = D.events[#D.events]
	lines = table.concat(D.Describe(ev), "\n")
	check(ev.cheap and ev.lastRun and lines:find("Terminal's last /run press was", 1, true) and lines:find("OpenWorldMap", 1, true),
		"4 minutes later: another's, the last /run press named: " .. lines:sub(1, 220))
	-- a press with no /run line (a /click) is noted but never blamed for a ForceTaint_Strong block
	S.NotePress("/click LegacyMicroButton", "Enter")
	clock = clock + 0.2
	local p, ago = S.LastRunPress(clock)
	check(p and p.text:find("OpenWorldMap", 1, true) and ago > 200, "a /click press isn't a /run press")
	-- another addon's block is never Terminal's, /run press or not
	S.NotePress("/run C_Map.OpenWorldMap(1)", "click")
	local before = D.count
	D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", "SomeAddon", "UseAction()")
	check(D.count == before, "another addon's own block isn't blamed on Terminal's press")
	ns.Print = realPrint
	_G.GetTime = realTime
	for i = #D.events, 1, -1 do D.events[i] = nil end
	for i = #S.presses, 1, -1 do S.presses[i] = nil end
	FlushAll()
end

io.write("[macros: who wrote the windows' fields, read after each press]\n")
do
	local realCheck = _G.issecurevariable
	local function Traced(text)
		for _, l in ipairs(D.trace) do if l.msg:find(text, 1, true) then return true end end
		return false
	end
	for i = #D.trace, 1, -1 do D.trace[i] = nil end
	local savedQM, savedMap = _G.QuestMapFrame, _G.WorldMapFrame
	local map = T.Obj("Frame"); map.mapID = 1413
	local qm = T.Obj("Frame"); qm.DetailsFrame = { questID = 33 }
	_G.WorldMapFrame, _G.QuestMapFrame = map, qm
	local tainted = {}
	_G.issecurevariable = function(t, k)
		if tainted[t] and tainted[t][k] then return false, "*** ForceTaint_Strong ***" end
		return true
	end
	-- clean: nothing traced
	S.NotePress("/run C_Map.OpenWorldMap(1413)", "Enter"); FlushAll()
	check(not Traced("taint:"), "clean fields: nothing traced")
	-- the quest details' quest written by a /run line: traced once, with the press
	tainted[qm.DetailsFrame] = { questID = true }
	S.NotePress("/run QuestMapFrame_OpenToQuestDetails(33)", "click"); FlushAll()
	check(Traced("taint: QuestMapFrame.DetailsFrame.questID was written by *** ForceTaint_Strong *** (after /run QuestMapFrame_OpenToQuestDetails(33))"),
		"a tainted field is traced, with the press before it")
	local n = 0
	for _, l in ipairs(D.trace) do if l.msg:find("QuestMapFrame.DetailsFrame.questID", 1, true) then n = n + 1 end end
	S.NotePress("/click QuestLogMicroButton", "Enter"); FlushAll()
	local n2 = 0
	for _, l in ipairs(D.trace) do if l.msg:find("QuestMapFrame.DetailsFrame.questID", 1, true) then n2 = n2 + 1 end end
	check(n == 1 and n2 == 1, "traced once per change, not on every press: " .. n .. "/" .. n2)
	-- (the map's own: written by the game again, then by a /run line again: traced again)
	tainted[qm.DetailsFrame] = nil
	S.TaintCheck("x")
	tainted[qm.DetailsFrame] = { questID = true }
	S.TaintCheck("y")
	local n3 = 0
	for _, l in ipairs(D.trace) do if l.msg:find("QuestMapFrame.DetailsFrame.questID", 1, true) then n3 = n3 + 1 end end
	check(n3 == 2, "clean again, then tainted again: traced again")
	-- no issecurevariable (an old client): nothing read, nothing traced
	_G.issecurevariable = nil
	for i = #D.trace, 1, -1 do D.trace[i] = nil end
	check(next(S.TaintCheck("z")) == nil and not Traced("taint:"), "no issecurevariable: nothing read")
	-- the Enter press notes its macro (the macro button's PreClick, on the half of the key press it acts on)
	for i = #S.presses, 1, -1 do S.presses[i] = nil end
	local proxy = _G.TerminalMacroProxy
	if proxy and proxy.scripts and proxy.scripts.PreClick then
		S.armed = "MACRO"
		proxy.attrs.macrotext = "/run C_Map.OpenWorldMap(7)"
		proxy.scripts.PreClick(proxy, "LeftButton", false) -- (key up: not the half it acts on)
		proxy.scripts.PreClick(proxy, "LeftButton", true)
		S.armed = nil
		check(#S.presses == 1 and S.presses[1].text == "/run C_Map.OpenWorldMap(7)" and S.presses[1].via == "Enter",
			"the macro button's press is noted once, on key down: " .. #S.presses)
	end
	for i = #S.presses, 1, -1 do S.presses[i] = nil end
	_G.WorldMapFrame, _G.QuestMapFrame, _G.issecurevariable = savedMap, savedQM, realCheck
	FlushAll()
end
