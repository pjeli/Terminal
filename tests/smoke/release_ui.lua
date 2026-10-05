local T = ...
-- Release review (0.39): style strings, the slim copy bar, the import dialog, WoWamp's window

do -- a style string changes only the look: layout and behaviour keys in it are skipped
	local ns, check = T.ns, T.check
	local Th = ns.Theme
	local saved = {}
	for k, v in pairs(Th.Get()) do saved[k] = v end
	Th.Reset()
	local width, scale, autoScan = Th.Get().width, Th.Get().scale, Th.Get().autoScan
	local ok, msg = Th.Import(Th.STYLE_MARK .. "accent=ff0000; width=900; scale=2; autoScan=off")
	local t = Th.Get()
	check(ok and t.accent == "ff0000", "the look's settings apply: " .. tostring(msg))
	check(t.width == width and t.scale == scale and t.autoScan == autoScan, "a pasted string can't change the layout or behaviour: " .. tostring(t.width) .. " " .. tostring(t.scale))
	check(msg:find("3 unknown", 1, true), "the skipped ones are counted: " .. tostring(msg))
	-- only layout keys: nothing to apply
	check(not Th.Import(Th.STYLE_MARK .. "width=900"), "a string with only layout keys applies nothing")
	local cur = Th.Get()
	for k in pairs(cur) do cur[k] = nil end
	for k, v in pairs(saved) do cur[k] = v end
	Th.Changed()
end

do -- the slim copy bar has a line for every line the wrapped text takes
	local ns, check = T.ns, T.check
	local C = ns.CopyBox
	-- ten words that each fill a line (the mock measures 7 px a character): wrapped at spaces they need
	-- ten lines (eight at most); dividing the whole width by a line's gave six, cutting the rest off
	local words = {}
	for i = 1, 10 do words[i] = ("w"):rep(39) .. i % 10 end
	ns:ShowText("Long", table.concat(words, " "), { compact = true })
	check(C.linkLines == 8, "each long word gets its own line (eight at most): " .. tostring(C.linkLines))
	-- two words a line: five lines
	words = {}
	for i = 1, 10 do words[i] = ("w"):rep(34) .. i % 10 end
	ns:ShowText("Long", table.concat(words, " "), { compact = true })
	check(C.linkLines == 5, "two words a line: five lines: " .. tostring(C.linkLines))
	ns:ShowText("Wowhead", "https://www.wowhead.com/forever/quest=610", { compact = true })
	check(C.linkLines == 1, "a short link stays one line")
	C.Hide()
end

do -- the import dialog: a successful Apply's closing timer leaves a dialog opened again since alone
	local ns, check = T.ns, T.check
	local Th = ns.Theme
	local saved = {}
	for k, v in pairs(Th.Get()) do saved[k] = v end
	local d = ns.Options.ImportDialog()
	d.box:SetText(Th.STYLE_MARK .. "accent=abcdef")
	d.Apply()
	d:Hide()
	ns.Options.ImportDialog() -- opened again before the timer fires
	T.FlushAll()
	check(d:IsShown(), "the dialog opened again stays open")
	d:Hide()
	local cur = Th.Get()
	for k in pairs(cur) do cur[k] = nil end
	for k, v in pairs(saved) do cur[k] = v end
	Th.Changed()
end

do -- WoWamp: the blocks are coloured again only when the station's colours change; Off moves no bars
	local ns, check = T.ns, T.check
	local W = ns.Wowamp
	local base = { psf = _G.PlaySoundFile, ss = _G.StopSound, get = C_CVar.GetCVar, set = C_CVar.SetCVar }
	_G.PlaySoundFile = function() return true, 700 end
	_G.StopSound = function() end
	C_CVar.GetCVar = function() return "1" end
	C_CVar.SetCVar = function() end
	W.Open()
	W.SetStyle("blocks")
	W.Tune("moonwell")
	local F = W.frame
	local upd = F.scripts.OnUpdate
	for _ = 1, 10 do upd(F, 1 / 60) end
	check(W.vis.lit[1] >= 0, "blocks light up")
	W.Redraw() -- same station: the blocks stay as they are
	check(W.vis.lit[1] >= 0, "a redraw with the same colours doesn't place the blocks again")
	W.Tune("warradio")
	check(W.vis.lit[1] == -1, "another station's colours: the blocks are coloured again")
	-- Off: nothing to draw, the bars stay where they were; the loop still rests once stopped
	for _ = 1, 10 do upd(F, 1 / 60) end
	W.SetStyle("off")
	local h1 = W.vis.h[1]
	upd = F.scripts.OnUpdate
	for _ = 1, 30 do upd(F, 1 / 60) end
	check(W.vis.h[1] == h1, "visualizer off: the bars aren't moved")
	W.Stop()
	upd = F.scripts.OnUpdate
	if upd then for _ = 1, 10 do upd(F, 0.1) end end
	check(F.scripts.OnUpdate == nil and W.vis.resting, "visualizer off and stopped: the loop rests")
	W.SetStyle("bars"); W.Close()
	_G.PlaySoundFile, _G.StopSound, C_CVar.GetCVar, C_CVar.SetCVar = base.psf, base.ss, base.get, base.set
end
