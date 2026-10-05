-- Review fixes in the support files: Filters, Share, Panel (atop, snake, changelog), Commands, Options.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local F = ns.Filters

do -- filters: stat:mp5 (a digit in the stat word), swapped ranges, _ for a space, one trace per search
	F.ClearCache()
	local function P(w) local f = F.Parse(w); assert(f, "not a filter: " .. w); return f end
	local base = { info = C_Item.GetItemInfo, stats = C_Item.GetItemStats }
	C_Item.GetItemInfo = function(id)
		if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
		if id == 200 then return "Spirit Band", "|Hitem:200|h", 2, 30, 25, "Armor", "Miscellaneous", 1, "INVTYPE_FINGER" end
	end
	C_Item.GetItemStats = function() return { ITEM_MOD_MANA_REGENERATION_SHORT = 6 } end
	local band = { itemID = 200 }
	check(F.Parse("stat:mp5") ~= nil and P("stat:mp5")(band), "stat:mp5 is a filter (its word has a digit) and finds mana regen")
	check(P("stat:mp5>=5")(band) and not P("stat:mp5>6")(band), "stat:mp5>=5: with a number")
	check(F.Parse("stat:5mp") == nil, "a stat word still starts with a letter")
	check(F.Range("30-20")(25) and F.Range("30-20")(20) and not F.Range("30-20")(31), "a range given backwards (30-20) is 20-30")
	check(P("in:elwynn_forest")({ zone = "Elwynn Forest" }) and not P("in:elwynn_forest")({ zone = "Elwynn" }), "in:elwynn_forest: _ stands for a space")
	check(P("type:one-handed_swords")({ itemID = 200 }) == false, "type: takes _ as a space too (no match here)")
	C_Item.GetItemInfo = function(id)
		if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
		if id == 201 then return "Blade", "|Hitem:201|h", 2, 30, 25, "Weapon", "One-Handed Swords", 1, "INVTYPE_WEAPON" end
	end
	F.ClearCache()
	check(P("type:one-handed_swords")({ itemID = 201 }) and P("type:sword")({ itemID = 201 }), "type:one-handed_swords finds the sword's subtype")
	check(P("stat:attack_power") ~= nil, "stat: keeps its _ (attack_power is the game's own key)")
	local has = false
	for _, h in ipairs(F.HELP) do if h[2]:find("_ for the space", 1, true) then has = true end end
	check(has, ".filters says how to write a space")
	C_Item.GetItemInfo, C_Item.GetItemStats = base.info, base.stats
	F.ClearCache()

	-- a filter that errors: the row is left out, and .debug log says so once per search, not per row
	local D = ns.Debug
	local function traces()
		local n = 0
		for _, l in ipairs(D.trace) do if l.msg:find("^filter error:") then n = n + 1 end end
		return n
	end
	local before = traces()
	local boom = { function() error("boom") end }
	F.Parse("lvl:20") -- (a search's words are parsed first)
	check(F.Pass({ name = "a" }, boom) == false and F.Pass({ name = "b" }, boom) == false, "a failing filter leaves rows out")
	check(traces() == before + 1, "and is traced once for the search: " .. (traces() - before))
	F.Parse("plain") -- the next search
	F.Pass({ name = "c" }, boom)
	check(traces() == before + 2, "the next search traces it again")
end

do -- in: caches what it lowercases: the row's zone/detail (on the row, like _ltext), area names per id
	local function P(w) local f = F.Parse(w); assert(f, "not a filter: " .. w); return f end
	local row = { zone = "Dun Morogh", detail = "x5  Backpack" }
	check(P("in:morogh")(row) and rawget(row, "_lzone") == "dun morogh", "the lowercase zone is kept on the row")
	check(P("in:backpack")(row) and rawget(row, "_ldetail") == "x5  backpack", "and the lowercase detail")
	row.detail = "x7  Bank"
	check(not P("in:backpack")(row) and P("in:bank")(row) and rawget(row, "_ldetail") == "x7  bank", "a changed detail is read again")
	local saveNF, saveMap = ns.Integrations.NpcField, _G.C_Map
	ns.Integrations.NpcField = function(id, f) if f == "zoneID" then return 1537 end end
	local asked = 0
	_G.C_Map = { GetAreaInfo = function(a) asked = asked + 1; return a == 1537 and "Ironforge" or nil end }
	local a, b = { kind = "npc", key = 41 }, { kind = "npc", key = 42 }
	check(P("in:ironforge")(a) and P("in:ironforge")(b) and P("in:iron")(a), "NPCs in an area by its name")
	check(asked == 1, "the area's name is asked of the game once, not per row per search: " .. asked)
	F.ClearCache()
	P("in:ironforge")(a)
	check(asked == 2, "ClearCache forgets area names too")
	ns.Integrations.NpcField, _G.C_Map = saveNF, saveMap
	F.ClearCache()
end

do -- >> channel: ">>party" without a space, r for raid, numbers only 1-20 while typed
	local SH = ns.Share
	local q, rest = SH.Split("copper >>party")
	check(q == "copper " and rest == "party", ">>party (no space) ends the search too: " .. tostring(q) .. "|" .. tostring(rest))
	q, rest = SH.Split("a >> b >> guild")
	check(q == "a >> b " and rest == "guild", "with two, the last >> is the one")
	check(select(2, SH.Split("lvl:>>20 copper")) == nil, "a >> inside a word isn't one")
	check(SH.Channel("r").cmd == "/raid" and SH.Channel("raid").label == "raid", "r is short for raid")
	check(SH.IsStart("r") and SH.IsStart("2") and SH.IsStart("20") and SH.IsStart("1"), "r, 2, 20 can still become a channel")
	check(not SH.IsStart("0") and not SH.IsStart("21") and not SH.IsStart("200") and not SH.IsStart("05"), "0, 21, 200: no channel starts so (Channel takes 1-20)")
	UI:Open("hearthstone >>party")
	check(UI.sendTo and UI.sendTo.cmd == "/p" and UI.Results()[1] and UI.Results()[1].name == "Hearthstone", "in the prompt: hearthstone >>party sends to the party")
	UI:Hide()
end

do -- the panels share one pattern (Panel.lua): built alike, laid where the terminal is, one closes the others
	local Pn = ns.Panel
	check(type(Pn.Text) == "function" and type(Pn.Build) == "function" and type(Pn.Layout) == "function", "Panel.Text/Build/Layout")
	ns.Atop.Open(); ns.Snake.Open(); ns.Changelog.Open()
	local reg = Pn.Registered()
	local seen = {}
	for _, app in ipairs(reg) do seen[app] = true end
	check(#reg == 3 and seen[ns.Atop] and seen[ns.Snake] and seen[ns.Changelog], "atop, snake and the changelog are registered once each: " .. #reg)
	check(ns.Changelog.IsShown() and not ns.Atop.IsShown() and not ns.Snake.IsShown(), "opening one closes the others")
	for _, f in ipairs({ ns.Atop.frame, ns.Snake.frame, ns.Changelog.frame }) do
		check(f.kb == true and f.scripts.OnEvent ~= nil and f.shown ~= nil, "each frame reads the keyboard and watches for combat")
	end
	-- a fourth app registers the same way and closes the rest
	local app = {}
	local fr = Pn.Build("TerminalTestPanel", app)
	app.IsShown = function() return fr:IsShown() end
	app.Close = function() fr:Hide() end
	Pn.Layout(fr, 300, 200)
	check(fr.w == 300 and fr.h == 200 and fr.lastPoint and fr.lastPoint[1] == "TOP" and fr.lastPoint[2] == _G.TerminalFrame, "Layout: sized, hung from the terminal's top")
	check(fr.bgColor and fr.bgColor[4] >= 0.9, "its background is at least 0.9 opaque")
	Pn.Opening(app); fr:Show()
	check(not ns.Changelog.IsShown() and app.IsShown(), "a new panel opening closes the changelog")
	ns.Changelog.Open()
	check(not app.IsShown(), "and the changelog closes it")
	ns.Changelog.Close()
	-- the registry doesn't grow when an app is rebuilt (Build runs once per app: `if frame then return end`)
	check(#Pn.Registered() == 4, "registered once per app")
	-- combat closes through the shared handler
	fr:Show()
	fr.scripts.OnEvent(fr, "PLAYER_REGEN_DISABLED")
	check(not app.IsShown(), "combat starting closes a panel (the shared handler)")
	for i = #reg, 1, -1 do if reg[i] == app then table.remove(reg, i) end end
end

do -- atop: a settled display redraws nothing; colours are triples, not hex parsed per bar per tick
	local B = ns.Atop
	local base = { addons = _G.C_AddOns, prof = _G.C_AddOnProfiler, enum = Enum.AddOnProfilerMetric,
		upd = _G.UpdateAddOnMemoryUsage, mem = _G.GetAddOnMemoryUsage, fps = _G.GetFramerate }
	local LIST = { { "Terminal", "Terminal", 0.20, 3000 }, { "Questie", "Questie", 1.10, 90000 } }
	_G.C_AddOns = setmetatable({ GetNumAddOns = function() return #LIST end,
		GetAddOnInfo = function(i) return LIST[i][1], LIST[i][2] end,
		IsAddOnLoaded = function() return true end }, { __index = base.addons })
	Enum.AddOnProfilerMetric = { RecentAverageTime = 3 }
	_G.C_AddOnProfiler = { GetAddOnMetric = function(name) for _, a in ipairs(LIST) do if a[1] == name then return a[3] end end end,
		GetOverallMetric = function() return 1.30 end }
	_G.UpdateAddOnMemoryUsage = function() end
	_G.GetAddOnMemoryUsage = function(name) for _, a in ipairs(LIST) do if a[1] == name then return a[4] end end end
	_G.GetFramerate = function() return 60 end
	B.Open()
	B.Tick(0.6) -- a sample
	for _ = 1, 30 do B.Tick(0.04) end -- the bars glide toward it
	B.DrawBars(1) -- and are snapped to their values
	local draws = 0
	local function count(tex)
		tex.SetHeight = function() draws = draws + 1 end
		tex.SetWidth = function() draws = draws + 1 end
		tex.SetVertexColor = function() draws = draws + 1 end
	end
	for _, bar in ipairs(B.graph) do count(bar) end
	for _, r in ipairs(B.rows) do count(r.bar) end
	B.DrawBars(0.3)
	check(draws == 0, "settled: a tick redraws no bar: " .. draws)
	local newest = B.graph[#B.graph]
	check(math.abs(newest.shown - newest.target) < 0.0001, "the bars sit at their values")
	LIST[2][3] = 0.3
	B.Tick(0.6) -- a new sample: the newest column changes
	check(draws > 0, "a changed value is drawn again: " .. draws)
	draws = 0
	B.DrawBars(1)
	check(draws > 0, "a snap (k = 1) draws everything")
	local m1, m2, m3 = B.MemTexts()
	check(m3.text:find("^" .. ns.name .. " "), "the addon's own memory line is named after it (ns.name): " .. tostring(m3.text))
	check(B.cols == nil, "the unused B.cols export is gone")
	B.Close()
	_G.C_AddOns, _G.C_AddOnProfiler, Enum.AddOnProfilerMetric = base.addons, base.prof, base.enum
	_G.UpdateAddOnMemoryUsage, _G.GetAddOnMemoryUsage, _G.GetFramerate = base.upd, base.mem, base.fps
	check(F.KEYS == nil, "the unused Filters.KEYS export is gone")
end

do -- .bind in combat says so and binds nothing; .forget clears the recent picks too
	local realCombat, realSet = _G.InCombatLockdown, _G.SetBinding
	local set = false
	_G.SetBinding = function() set = true; return true end
	_G.InCombatLockdown = function() return true end
	local out = ns.commands.bind.run("CTRL-SPACE")
	check(not set and out[1]:find("combat", 1, true), ".bind in combat: says so, binds nothing (SetBinding is blocked then)")
	_G.InCombatLockdown = realCombat
	out = ns.commands.bind.run("CTRL-SPACE")
	check(set and out[1]:find("bound to CTRL-SPACE", 1, true), "out of combat it binds")
	_G.SetBinding = realSet
	ns.db.freq.x = 3
	ns.db.recent = { "items:6948", "spells:101" }
	ns.commands.forget.run("")
	check(next(ns.db.freq) == nil and #ns.db.recent == 0, ".forget clears the usage counts and the recent picks")
end

do -- theme rows share one activate function and carry their preset
	local rows = ns:GetEntries(ns.providers.terminal)
	local fn, n = nil, 0
	for _, e in ipairs(rows) do
		if e.presetId then
			n = n + 1
			fn = fn or e.activate
			check(e.activate == fn and e.key == "theme:" .. e.presetId, "every theme row runs the same function, reading its presetId")
		end
	end
	check(n == #ns.Theme.PRESET_ORDER and fn ~= nil, "a row per preset: " .. n)
	local Th = ns.Theme
	local was = Th.Get().preset
	for _, e in ipairs(rows) do if e.presetId == "dracula" then e.activate(e) end end
	check(Th.Get().preset == "dracula", "activating a row applies its preset")
	T.FlushAll() -- (it reopens on the theme list)
	UI:Hide()
	Th.ApplyPreset(was ~= "custom" and was or "forever")
end

do -- ">>party" (no space) is coloured like ">> party"
	local UI, t = T.UI, T.ns.Theme.Get()
	local segs = UI:SyntaxSegments("hearthstone >>party")
	local col = {}
	for _, sg in ipairs(segs) do col[("hearthstone >>party"):sub(sg[1], sg[2])] = sg[3] end
	T.check(col[">>"] == t.accent and col.party == T.ns.Theme.SYNTAX.filter, ">>party: arrows accent, channel filter colour")
	segs = UI:SyntaxSegments("hearthstone >>nowhere x")
	for _, sg in ipairs(segs) do col[("hearthstone >>nowhere x"):sub(sg[1], sg[2])] = sg[3] end
	T.check(col.nowhere == T.ns.Theme.SYNTAX.bad, ">>nowhere: the word in red")
end

do -- style strings: export, import, the .style command and the options dialog
	local ns, UI, check = T.ns, T.UI, T.check
	local Th = ns.Theme
	local saved = {}
	for k, v in pairs(Th.Get()) do saved[k] = v end
	-- export: one line, the marker, every style key, nothing else, short enough for a chat message
	Th.ApplyPreset("dracula")
	Th.Set("promptText", "a;=")
	local s = Th.Export()
	check(s:sub(1, #Th.STYLE_MARK) == Th.STYLE_MARK and not s:find("[\n\r]"), "export starts with the marker, one line: " .. s)
	check(#s <= 255, "a style string fits a chat message (" .. #s .. ")")
	for _, k in ipairs(Th.STYLE_KEYS) do check(s:find("; " .. k .. "=", 1, true) or s:find(":" .. k .. "=", 1, true), "export carries " .. k) end
	check(not s:find("width=", 1, true) and not s:find("hints=", 1, true), "layout and behaviour settings stay out")
	check(s:find("promptText=a%3B%3D", 1, true), "the prompt text's ; and = are escaped: " .. s)
	check(s:find("; accent=", 1, true), "settings are separated by '; ' so the text can wrap where it's shown")
	-- the string without the spaces imports too (an old one, or one retyped)
	do
		Th.Reset()
		local okc = Th.Import((s:gsub("; ", ";")))
		check(okc and Th.Get().accent == "bd93f9", "a style string without the spaces imports too")
	end
	-- import: back to the defaults first, then the string brings the look back exactly
	Th.Reset()
	check(Th.Get().accent ~= "bd93f9", "reset: Dracula's accent gone")
	local ok, msg = Th.Import(s)
	check(ok, "import applies: " .. tostring(msg))
	local t = Th.Get()
	check(t.accent == "bd93f9" and t.bg == "282a36" and t.frame == "flat" and t.promptText == "a;=" and t.bgAlpha == 0.97, "every setting came back: " .. tostring(t.accent) .. " " .. tostring(t.promptText))
	-- the colours are Dracula's exactly, so the preset is recognised (the prompt text isn't part of a preset)
	check(t.preset == "dracula" and Th.MatchPreset(t) == "dracula", "the imported colours are recognised as Dracula: " .. tostring(t.preset))
	-- a chat line around the string is ignored
	Th.Reset()
	ok = Th.Import("[Party] Plamen: here " .. s .. " try it")
	check(ok and Th.Get().accent == "bd93f9", "a style pasted with a chat line around it still imports")
	-- unknown keys skipped, counted
	Th.Reset()
	ok, msg = Th.Import(Th.STYLE_MARK .. "accent=ff0000;futureKey=1")
	check(ok and Th.Get().accent == "ff0000" and msg:find("1 unknown", 1, true), "unknown keys skipped and counted: " .. tostring(msg))
	-- a bad value: nothing changes
	Th.Reset()
	local before = Th.Get().accent
	ok, msg = Th.Import(Th.STYLE_MARK .. "accent=notacolour;bg=000000")
	check(not ok and Th.Get().accent == before and Th.Get().bg ~= "000000", "a bad value applies nothing: " .. tostring(msg))
	check(not Th.Import("hello there"), "not a style string: refused")
	check(not Th.Import(Th.STYLE_MARK), "an empty style string: refused")
	-- the preset is recognised from a preset's colours
	Th.Reset()
	Th.Import(Th.STYLE_MARK .. "bg=000a00;border=0f6b26;accent=00ff66;prompt=00ff66;text=c8ffc8;dim=4f8f5f;match=9dff9d;bgAlpha=0.95;frame=flat;promptBg=" .. Th.PRESETS.matrix.promptBg)
	check(Th.Get().preset == "matrix", "Matrix's colours imported are the Matrix preset: " .. tostring(Th.Get().preset))
	-- the command: .style opens the copy box with the string; .style <string> applies it
	local shown, shownOpts
	local baseShow = ns.ShowText
	ns.ShowText = function(_, title, text, opts) shown, shownOpts = text, opts end
	ns.commands.style.run("")
	check(shown == Th.Export() and shownOpts and shownOpts.compact, ".style opens the look as a string in the slim copy bar (closes on Ctrl+C)")
	ns.ShowText = baseShow
	-- the slim bar wraps a long text onto a few lines instead of one scrolling line
	local C = ns.CopyBox
	ns:ShowText("Terminal style", Th.Export(), { compact = true })
	check(C.linkFrame and C.linkFrame:IsShown() and (C.linkLines or 1) > 1 and (C.linkLines or 9) <= 8, "a style string wraps onto a few lines: " .. tostring(C.linkLines))
	check(C.linkFrame:GetWidth() <= 560, "a long text gets the narrow bar: " .. tostring(C.linkFrame:GetWidth()))
	check(C.linkFrame.lastPoint and C.linkFrame.lastPoint[1] == "CENTER", "the long bar is centred on the screen")
	check(C.linkEdit.text == Th.Export(), "the text is in the box")
	-- selected once more when it gets focus (a click into it, the timer): a wrapped box drew its highlight late
	local hl = false
	C.linkEdit.HighlightText = function() hl = true end
	C.linkEdit.scripts.OnEditFocusGained(C.linkEdit)
	C.linkEdit.HighlightText = nil
	check(hl, "focus selects the text")
	ns:ShowText("Wowhead", "https://www.wowhead.com/forever/quest=610", { compact = true })
	check(C.linkLines == 1, "a short link stays one line")
	C.Hide()
	Th.Reset()
	local out = ns.commands.style.run("import " .. Th.STYLE_MARK .. "accent=123456")
	check(Th.Get().accent == "123456" and out[1] and out[1]:find("applied", 1, true), ".style import <string> applies it: " .. tostring(out[1]))
	out = ns.commands.style.run(Th.STYLE_MARK .. "accent=654321")
	check(Th.Get().accent == "654321", ".style <string> (no 'import') applies too")
	-- the options dialog
	local d = ns.Options.ImportDialog()
	check(d and d:IsShown(), "the import dialog opens")
	d.box:SetText(Th.STYLE_MARK .. "accent=abcdef")
	d.Apply()
	check(Th.Get().accent == "abcdef", "Apply in the dialog imports the pasted string")
	d.box:SetText("nope"); d.Apply()
	check(Th.Get().accent == "abcdef" and d.status:GetText():find("not a Terminal style", 1, true), "a bad paste says so and changes nothing")
	d:Hide()
	-- back as it was
	local cur = Th.Get()
	for k in pairs(cur) do cur[k] = nil end
	for k, v in pairs(saved) do cur[k] = v end
	Th.Changed()
end

do -- .wowamp: radio stations playing the game's music
	local ns, check = T.ns, T.check
	local W = ns.Wowamp
	local played, stopped, cvars = {}, {}, { Sound_EnableMusic = "1" }
	local base = { psf = _G.PlaySoundFile, ss = _G.StopSound, get = C_CVar.GetCVar, set = C_CVar.SetCVar, rand = W.rand }
	local nextHandle = 100
	_G.PlaySoundFile = function(id, channel, _, _) nextHandle = nextHandle + 1; played[#played + 1] = { id = id, channel = channel, h = nextHandle }; return true, nextHandle end
	_G.StopSound = function(h) stopped[#stopped + 1] = h end
	C_CVar.GetCVar = function(n) return cvars[n] end
	C_CVar.SetCVar = function(n, v) cvars[n] = v end
	W.rand = function(n) return n end -- (no shuffling: the order stays as listed)
	-- the stations: every track has a file ID, a length and a title; ten of them, themed on places
	check(#W.STATIONS == 10, "ten stations: " .. #W.STATIONS)
	local okData = true
	for _, st in ipairs(W.STATIONS) do
		if not (st.name and st.place and st.genre and st.tag and st.lo and st.hi and st.bpm and #st.tracks >= 5) then okData = false end
		for _, tr in ipairs(st.tracks) do
			if not (type(tr[1]) == "number" and tr[2] >= 10 and type(tr[3]) == "string") then okData = false end
		end
	end
	check(okData, "every station has its theme and its tracks (file ID, seconds, title)")
	-- tuning in plays the station's first track on the Master channel, and switches the zone music off
	W.Tune("classical")
	local st = W.Station()
	check(st and st.id == "classical" and #played == 1 and played[1].id == st.tracks[1][1] and played[1].channel == "Master",
		"tuning in plays the station's first track on Master: " .. tostring(played[1] and played[1].id))
	check(cvars.Sound_EnableMusic == "0", "the zone music is off while the radio plays")
	check(ns.db.wowamp.station == "classical", "the station is remembered")
	-- the track's length later, the next one starts (the old one stopped)
	for _ = 1, 50 do if #played >= 2 then break end T.Flush() end
	check(#played == 2 and played[2].id == st.tracks[2][1] and stopped[#stopped] == played[1].h, "when a track ends the next starts: " .. #played)
	-- next / back
	W.Next()
	check(played[#played].id == st.tracks[3][1], "next: the third track")
	W.Prev()
	check(played[#played].id == st.tracks[2][1], "back (just started): the track before")
	-- a stop makes any waiting next-track timer do nothing, and the zone music comes back
	local before = #played
	W.Stop()
	check(not W.state.playing and cvars.Sound_EnableMusic == "1", "stopped: the zone music is back on")
	T.FlushAll()
	check(#played == before, "a stopped radio starts nothing when the old track's timer fires")
	-- zone music the player had off stays off
	cvars.Sound_EnableMusic = "0"
	W.Tune(1); W.Stop()
	check(cvars.Sound_EnableMusic == "0", "zone music that was off stays off after the radio stops")
	-- the game won't play a station at all: it gives up instead of trying forever
	_G.PlaySoundFile = function() return false end
	local printed
	local basePrint = ns.Print
	ns.Print = function(_, m) printed = m end
	W.Tune(2)
	for _ = 1, 40 do T.Flush() end
	check(not W.state.playing and printed and printed:find("no music", 1, true), "nothing plays: it stops and says so")
	ns.Print = basePrint
	_G.PlaySoundFile = function(id, channel) nextHandle = nextHandle + 1; played[#played + 1] = { id = id, channel = channel, h = nextHandle }; return true, nextHandle end
	-- shuffle: the order follows the setting, the current track kept
	W.rand = base.rand
	W.Tune("necropolis")
	local current = W.Track()
	W.SetShuffle(true)
	check(W.Track() == current and ns.db.wowamp.shuffle == true, "shuffle on: the current track keeps playing")
	-- the window: opens where the terminal is, takes only its keys, plays on when closed
	cvars.Sound_EnableMusic = "1"
	check(W.Open() and W.IsShown() and not T.UI:IsShown(), ".wowamp opens the player in the terminal's place")
	local F = W.frame
	local count = #played
	W.KeyDown(F, "DOWN"); W.KeyDown(F, "ENTER")
	check(#played == count + 1 and W.state.station ~= 7, "Down then Enter tunes in to the next station")
	W.KeyDown(F, "3")
	check(W.state.station == 3, "a number key tunes straight in")
	W.KeyDown(F, "N")
	check(W.state.pos == 2, "N: the next track")
	W.KeyDown(F, "P")
	check(not W.state.playing, "P stops")
	W.KeyDown(F, "P")
	check(W.state.playing, "P plays again")
	local passed
	F.SetPropagateKeyboardInput = function(_, on) passed = on end
	W.KeyDown(F, "W")
	check(passed == true, "other keys reach the game (W still walks)")
	W.KeyDown(F, "S")
	check(passed == false, "the player's own keys are kept")
	-- the visualizer moves while playing, and rests once stopped and fallen
	local upd = F.scripts and F.scripts.OnUpdate
	check(upd ~= nil, "the bars move while a track plays")
	if upd then for _ = 1, 10 do upd(F, 0.05) end end
	local any = false
	for i = 1, 36 do if (W.vis.h[i] or 0) > 0 then any = true end end
	check(any, "the bars rise with the music")
	W.Stop()
	upd = F.scripts and F.scripts.OnUpdate
	if upd then for _ = 1, 60 do upd(F, 0.05) end end
	check(F.scripts.OnUpdate == nil and W.vis.resting, "stopped and fallen: the loop rests (no OnUpdate)")
	W.Toggle()
	W.KeyDown(F, "ESCAPE")
	check(not W.IsShown() and W.state.playing, "Esc closes the window; the music plays on")
	-- combat: doesn't open, and closes with the music still on
	_G.InCombatLockdown = function() return true end
	check(not W.Open(), "not opened in combat")
	_G.InCombatLockdown = function() return false end
	W.Open(); W.Close("combat")
	check(not W.IsShown() and W.state.playing, "closed by combat, the music plays on")
	-- the other panels close it
	W.Open(); ns.Snake.Open()
	check(not W.IsShown() and ns.Snake.IsShown(), "opening Snake closes the player")
	ns.Snake.Close()
	-- the command
	local out = ns.commands.wowamp.run("naxx")
	check(W.Station().id == "necropolis" and out[1]:find("Necropolis", 1, true), ".wowamp <name> tunes in: " .. tostring(out[1]))
	out = ns.commands.wowamp.run("stop")
	check(not W.state.playing and cvars.Sound_EnableMusic == "1", ".wowamp stop stops it and the zone music comes back")
	out = ns.commands.wowamp.run("nowhere")
	check(out[1]:find("no station", 1, true), "an unknown station says so")
	check(#ns.commands.wowamp.complete("") >= 12, "Tab completes stop, next and the stations")
	_G.PlaySoundFile, _G.StopSound, C_CVar.GetCVar, C_CVar.SetCVar, W.rand = base.psf, base.ss, base.get, base.set, base.rand
end

do -- .wowamp: tracks the game cuts short come back; each station's own feel; visualizer styles
	local ns, check = T.ns, T.check
	local W = ns.Wowamp
	local played, playing = {}, {}
	local nextHandle = 500
	local base = { psf = _G.PlaySoundFile, ss = _G.StopSound, cs = _G.C_Sound, get = C_CVar.GetCVar, set = C_CVar.SetCVar }
	_G.PlaySoundFile = function(id) nextHandle = nextHandle + 1; played[#played + 1] = id; playing[nextHandle] = true; return true, nextHandle end
	_G.StopSound = function(h) playing[h] = nil end
	C_CVar.GetCVar = function() return "1" end
	C_CVar.SetCVar = function() end
	-- (1) the game cuts the playing file (focus lost, a loading screen): it's started again within a second
	_G.C_Sound = { IsPlaying = function(h) return playing[h] == true end }
	W.Tune("moonwell")
	local first, n = played[#played], #played
	for _ = 1, 3 do T.Flush() end
	check(#played == n, "while the track plays, nothing restarts it")
	playing[W.state.handle] = nil -- the game cut it
	for _ = 1, 5 do if #played > n then break end T.Flush() end
	check(#played == n + 1 and played[#played] == first and W.state.playing, "a track the game cut short starts again: " .. #played)
	-- without C_Sound.IsPlaying nothing watches (and nothing breaks)
	_G.C_Sound = nil
	W.Tune("moonwell")
	check(W.state.playing, "no IsPlaying on the client: it plays as before")
	-- (2) each station its own feel: Moonwell's lo-fi stays low and smooth, WAR Radio tall and punchy
	local function Average(id)
		W.Tune(id)
		local total, steps = 0, 0
		for _ = 1, 40 do
			-- (the retarget step: what the bars aim for)
			local upd = W.frame and W.frame.scripts and W.frame.scripts.OnUpdate
			if upd then upd(W.frame, 0.11) end
			for i = 1, 36 do total = total + (W.vis.target[i] or 0) end
			steps = steps + 36
		end
		return total / steps
	end
	W.Open()
	local low, high = Average("moonwell"), Average("warradio")
	check(low < 0.4 and high > low * 1.6, ("Moonwell lo-fi sits low, WAR Radio high: %.2f vs %.2f"):format(low, high))
	check(W.FEEL.moonwell.rise < W.FEEL.warradio.rise and W.FEEL.moonwell.fall < W.FEEL.warradio.fall, "Moonwell's bars move smoothly, WAR Radio's sharply")
	local feels = 0
	for _, st in ipairs(W.STATIONS) do if W.FEEL[st.id] then feels = feels + 1 end end
	check(feels == #W.STATIONS, "every station has its own feel")
	-- (3) styles: V cycles bars -> blocks -> mirror -> wave -> peaks -> off -> bars, remembered
	W.SetStyle("bars")
	local seen = {}
	for _ = 1, #W.STYLES do
		W.KeyDown(W.frame, "V")
		seen[#seen + 1] = W.Style()
	end
	check(table.concat(seen, ",") == "blocks,mirror,wave,peaks,off,bars", "V cycles the styles: " .. table.concat(seen, ","))
	W.SetStyle("blocks")
	check(ns.db.wowamp.style == "blocks", "the style is remembered")
	local upd = W.frame.scripts.OnUpdate
	if upd then for _ = 1, 10 do upd(W.frame, 0.05) end end
	check(W.vis.lit[1] and W.vis.lit[1] >= 0, "blocks light up with the music")
	W.SetStyle("off")
	if upd then for _ = 1, 3 do upd(W.frame, 0.05) end end
	check(W.state.playing, "with the visualizer off the music plays on")
	check(not W.SetStyle("disco") and W.Style() == "off", "an unknown style is refused")
	W.SetStyle("bars")
	-- (4) shorter than it was (452)
	check(W.frame.h and W.frame.h <= 400, "the player is shorter: " .. tostring(W.frame.h))
	W.Stop(); W.Close()
	_G.PlaySoundFile, _G.StopSound, _G.C_Sound, C_CVar.GetCVar, C_CVar.SetCVar = base.psf, base.ss, base.cs, base.get, base.set
end

do -- .wowamp: smooth motion; Off folds the visualizer away and shortens the window
	local ns, check = T.ns, T.check
	local W = ns.Wowamp
	local base = { psf = _G.PlaySoundFile, ss = _G.StopSound, get = C_CVar.GetCVar, set = C_CVar.SetCVar }
	_G.PlaySoundFile = function() return true, 900 end
	_G.StopSound = function() end
	C_CVar.GetCVar = function() return "0" end
	C_CVar.SetCVar = function() end
	W.Open()
	W.SetStyle("bars")
	W.Tune("moonwell")
	local F = W.frame
	local upd = F.scripts.OnUpdate
	-- run a while, then watch: every bar visibly moves within half a second, none jumps in one frame
	for _ = 1, 60 do upd(F, 1 / 60) end
	local maxJump, lowest, hiH, loH = 0, 1, {}, {}
	for i = 1, 36 do hiH[i], loH[i] = W.vis.h[i], W.vis.h[i] end
	for _ = 1, 60 do
		local before = {}
		for i = 1, 36 do before[i] = W.vis.h[i] end
		upd(F, 1 / 60)
		for i = 1, 36 do
			local h = W.vis.h[i]
			maxJump = math.max(maxJump, math.abs(h - before[i]))
			hiH[i], loH[i] = math.max(hiH[i], h), math.min(loH[i], h)
		end
	end
	for i = 1, 36 do lowest = math.min(lowest, hiH[i] - loH[i]) end
	check(lowest > 0.015, ("every bar moves visibly within a second (lo-fi too): smallest range %.3f"):format(lowest))
	check(maxJump < 0.08, ("no bar jumps in one frame: largest step %.3f"):format(maxJump))
	-- Off: the box folds away and the window is shorter; back on, it returns
	local tall = F.h
	W.SetStyle("off")
	check(F.h < tall - 60, "Off: the window is shorter: " .. tostring(tall) .. " -> " .. tostring(F.h))
	W.SetStyle("bars")
	check(F.h == tall, "back to a style: the window's full height again")
	W.Stop(); W.Close()
	_G.PlaySoundFile, _G.StopSound, C_CVar.GetCVar, C_CVar.SetCVar = base.psf, base.ss, base.get, base.set
end

do -- .wowamp: with Sound in Background off, a tip says so (and the window makes room for it)
	local ns, check = T.ns, T.check
	local W = ns.Wowamp
	local cv = { Sound_EnableSoundWhenGameIsInBG = "0", Sound_EnableMusic = "0" }
	local base = { get = C_CVar.GetCVar }
	C_CVar.GetCVar = function(n) return cv[n] end
	W.SetStyle("bars")
	W.Open()
	local F = W.frame
	local withTip = F.h
	check(W.BackgroundSoundOff() and withTip > 392, "background sound off: the tip shows and the window grows for it: " .. tostring(withTip))
	cv.Sound_EnableSoundWhenGameIsInBG = "1"
	W.Redraw()
	check(not W.BackgroundSoundOff() and F.h == 392, "background sound on: no tip, the usual height: " .. tostring(F.h))
	cv.Sound_EnableSoundWhenGameIsInBG = "0"
	W.SetStyle("off")
	check(F.h == withTip - 84 - 8, "visualizer off with the tip: both add up: " .. tostring(F.h))
	W.SetStyle("bars"); W.Close()
	C_CVar.GetCVar = base.get
end
