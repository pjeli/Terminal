-- The apps on the Panel pattern (UI/Panel.lua: .atop, F1's keys window, the changelog, the extras' games and radio)
-- and the theme settings they follow (0.49.2, review)
local T = ...
local ns, UI, check, key = T.ns, T.UI, T.check, T.key
local Panel, K, Theme = ns.Panel, ns.KeysWindow, ns.Theme

io.write("[apps catch the mouse]\n")
do
	-- (0.49.2, review: only WoWamp and the terminal caught it; a click on F1's or the changelog's text over a mob
	-- targeted it, a drag on .atop turned the camera)
	ns.Changelog.Open(); ns.Changelog.Close()
	K.Open("simple"); K.Close()
	ns.Atop.Open(); ns.Atop.Close()
	ns.Snake.Open(); ns.Snake.Close()
	local loose = {}
	for _, f in ipairs(Panel.Frames()) do
		if f.mouse ~= true then loose[#loose + 1] = tostring(f:GetName()) end
	end
	check(#Panel.Frames() >= 4 and #loose == 0, "every app's frame catches the mouse (clicks and drags don't reach the world): "
		.. table.concat(loose, ", "))
end

io.write("[keys window: the header names the mode in use]\n")
do
	-- (0.49.2, review: the header was worked out after the terminal had closed, which ends fuzzy finding and Alt+`'s
	-- Advanced: F1 in fuzzy finding opened on its tab and said "you're in Simple mode")
	local was = ns.db.easyMode
	ns.db.easyMode = true; UI:EasyChanged()
	local function Header() local h = select(7, K.Parts()); return h and h:GetText() or "" end
	UI:FuzzyOnce("hearth"); T.FlushAll()
	K.flipAt = nil
	key("F1")
	check(K.IsShown() and K.Mode() == "fuzzy" and Header():find(K.LABELS.fuzzy, 1, true) ~= nil,
		"F1 in fuzzy finding: the header says so: " .. Header())
	K.Show("simple")
	check(Header():find(K.LABELS.fuzzy, 1, true) ~= nil, "on another tab it still names the mode in use: " .. Header())
	K.Close(); T.FlushAll()
	UI:Open(""); T.FlushAll()
	UI:SetQuery("hearthstone"); T.FlushAll()
	UI:AdvancedOnce(); T.FlushAll()
	K.flipAt = nil
	key("F1")
	check(K.IsShown() and K.Mode() == "advanced" and Header():find(K.LABELS.advanced, 1, true) ~= nil,
		"Alt+`'s Advanced: the header says Advanced: " .. Header())
	K.Close(); T.FlushAll()
	K.Open() -- (.keybinds with the terminal closed: the lasting mode)
	check(Header():find(K.LABELS.simple, 1, true) ~= nil, ".keybinds: the lasting mode: " .. Header())
	K.Close(); T.FlushAll()
	ns.db.easyMode = was; UI:EasyChanged()
end

io.write("[wowamp: shuffle off plays on in order]\n")
do
	-- (0.49.2, review: track 5 playing, S for in order put it first in 1..n: 5,2,3,4,1,6..., so 2 came next, not 6)
	local W = ns.Wowamp
	local base = { rand = W.rand, psf = _G.PlaySoundFile, ss = _G.StopSound, get = C_CVar.GetCVar, set = C_CVar.SetCVar }
	_G.PlaySoundFile = function() return true, 1 end
	_G.StopSound = function() end
	C_CVar.GetCVar = function() return "0" end
	C_CVar.SetCVar = function() end
	W.rand = function() return 1 end
	ns.db.wowamp = ns.db.wowamp or {}
	local shuffleWas, stationWas = ns.db.wowamp.shuffle, ns.db.wowamp.station
	ns.db.wowamp.shuffle = true
	W.Tune(1)
	local st = W.Station()
	W.state.order = { 3, 7, 5, 1, 2, 4, 6, 8, 9, 10 }
	W.state.pos = 3 -- (track 5 playing, shuffled)
	W.SetShuffle(false)
	check(W.Track() == st.tracks[5], "shuffle off: the current track keeps playing")
	W.Next()
	check(W.Track() == st.tracks[6], "in order: track 6 is next: " .. tostring(W.state.order[W.state.pos]))
	W.SetShuffle(true)
	check(W.Track() == st.tracks[6] and W.state.pos == 1, "shuffle on again: the current track first, the rest shuffled")
	W.Stop()
	T.FlushAll()
	ns.db.wowamp.shuffle, ns.db.wowamp.station = shuffleWas, stationWas
	W.rand, _G.PlaySoundFile, _G.StopSound, C_CVar.GetCVar, C_CVar.SetCVar = base.rand, base.psf, base.ss, base.get, base.set
end

io.write("[theme: a colour set to what it was keeps the theme]\n")
do
	-- (0.49.2, review: a swatch opened and cancelled set the colour it had, and the theme became Custom)
	local t = Theme.Get()
	local saved = CopyTable(t)
	Theme.ApplyPreset("forever")
	Theme.Set("accent", Theme.Get().accent)
	check(Theme.Get().preset == "forever", "the same colour again: still the theme: " .. tostring(Theme.Get().preset))
	local info
	local cpf = _G.ColorPickerFrame
	_G.ColorPickerFrame = { SetupColorPickerAndShow = function(_, i) info = i end,
		GetColorRGB = function() return Theme.RGB(info.pick or Theme.Get().accent) end }
	local sw = ns.Options.widgets.accent
	sw.scripts.OnClick(sw, "LeftButton")
	info.swatchFunc() -- (the picker shows the colour it opened on)
	info.cancelFunc()
	check(Theme.Get().preset == "forever", "the colour picker opened and cancelled: still the theme: " .. tostring(Theme.Get().preset))
	sw.scripts.OnClick(sw, "LeftButton")
	info.pick = "123456"; info.swatchFunc()
	check(Theme.Get().preset == "custom" and Theme.Get().accent == "123456", "a colour tried in the picker: Custom")
	info.cancelFunc()
	check(Theme.Get().preset == "forever" and Theme.Get().accent == Theme.PRESETS.forever.accent,
		"Cancel puts the colour back: the theme again: " .. tostring(Theme.Get().preset))
	_G.ColorPickerFrame = cpf
	for k in pairs(t) do t[k] = nil end
	for k, v in pairs(saved) do t[k] = v end
	Theme.Changed()
end

io.write("[atop: the game's own keys go on to the game]\n")
do
	-- (0.49.2, review: atop kept every key, so Print Screen, Ctrl+R's frame rate and the volume keys did nothing)
	local B = ns.Atop
	local was = { action = _G.GetBindingAction, ctrl = _G.IsControlKeyDown }
	_G.GetBindingAction = function(c) return ({ ["CTRL-R"] = "TOGGLEFPS", ["CTRL-F"] = "TARGETFOCUS" })[c] or "" end
	B.Open()
	local F = B.frame
	local function Down(k) F.scripts.OnKeyDown(F, k) end
	Down("PRINTSCREEN")
	check(F.propagate == true, "Print Screen: the game's (a screenshot)")
	Down("LCTRL")
	check(F.propagate == true, "a modifier goes on, as from the terminal")
	_G.IsControlKeyDown = function() return true end
	Down("R")
	check(F.propagate == true and B.IsShown(), "Ctrl+R: the game's frame rate")
	Down("F")
	check(F.propagate == false, "Ctrl+F bound to targeting: atop keeps it")
	_G.IsControlKeyDown = was.ctrl
	Down("DOWN")
	check(F.propagate == false and B.state.sel == 2, "its own keys are kept and work")
	Down("ESCAPE")
	check(F.propagate == false and not B.IsShown(), "Esc closes it (not passed on)")
	_G.GetBindingAction = was.action
end

io.write("[atop: all addons' graphs start again on open]\n")
do
	-- (0.49.2, review: each addon's own history started again, all addons' didn't: reopened an hour later, the old
	-- samples sat next to the new ones as if no time had passed)
	local B = ns.Atop
	B.Open()
	for _ = 1, 5 do B.Tick(0.6) end
	B.Tick(10.1)
	check(#B.History() >= 6 and #B.MemHistory() >= 2, "(samples while open)")
	B.Close()
	B.Open()
	check(#B.History() == 1 and #B.MemHistory() == 1, "reopened: the CPU and memory graphs start again: "
		.. #B.History() .. ", " .. #B.MemHistory())
	B.Close()
end

io.write("[apps' text follows the font]\n")
do
	-- (0.49.2, review: an app's texts set their font face once, when made: after .set font an app kept the old face,
	-- and F1's rows made later took the new one: two faces in one window)
	local made = {}
	local parent = T.Obj("Frame")
	parent.CreateFontString = function()
		local fs = T.Obj("FontString")
		fs.SetFontObject = function(self, o) self.fontObject = o end
		fs.SetFont = function(self, path) self.ownFace = path end
		made[#made + 1] = fs
		return fs
	end
	local fs = Panel.Text(parent, 12)
	local obj = type(Theme.FontAt) == "function" and Theme.FontAt(12) or nil
	check(obj ~= nil and fs.fontObject == obj and fs.ownFace == nil, "an app's text at a size uses the font object for it (no face of its own)")
	if obj then
		local face
		local setWas = rawget(obj, "SetFont")
		obj.SetFont = function(_, path, size) face = { path, size } return true end
		local fontWas = Theme.Get().font
		Theme.Set("font", "morpheus")
		check(face and face[1] == Theme.FONTS.morpheus and face[2] == 12, "after .set font, that font object has the new face at its size")
		Theme.Set("font", fontWas)
		obj.SetFont = setWas
	end
	if obj then
		check(Panel.Text(parent, 11).fontObject == Theme.FontAt(11) and Theme.FontAt(11) ~= obj, "another size: a font object of its own")
	end
	check(Panel.Text(parent).fontObject == Theme.fonts.input, "no size: the input font itself")
end

io.write("[credits: .credits thanks the people who kept Terminal going]\n")
do
	local CR = ns.Credits
	check(CR and ns.commands.credits and ns.commands.credits.run, ".credits is a command")
	ns.commands.credits.run("")
	check(CR.IsShown() and CR.frame.mouse == true, "it opens (catching the mouse)")
	local txt = CR.Body():GetText() or ""
	local missing = {}
	for _, n in ipairs({ "Caite", "Brother", "Wesslan", "Beefnerd", "Cazador", "Kass", "TJ" }) do
		if not txt:find(n, 1, true) then missing[#missing + 1] = n end
	end
	check(#missing == 0 and txt:find("Kass|r", 1, true) and txt:find("and |c", 1, true) and txt:find("believing in me", 1, true),
		"every name, in the accent colour, in the thanks: " .. txt)
	CR.frame.scripts.OnKeyDown(CR.frame, "ESCAPE")
	check(not CR.IsShown(), "Esc closes it")
	CR.Open()
	CR.frame.scripts.OnMouseDown(CR.frame, "LeftButton")
	check(not CR.IsShown(), "a click closes it")
	CR.Open()
	CR.frame.scripts.OnKeyDown(CR.frame, "W")
	check(CR.IsShown() and CR.frame.propagate == true, "other keys go on to the game: " .. tostring(CR.frame.propagate))
	CR.Close()
end
