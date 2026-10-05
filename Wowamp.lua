local ns = select(2, ...)

-- .wowamp: an easter egg. A small music player in the spirit of cliamp (the terminal music player), where the
-- terminal sits: ten made-up radio stations, each themed on a place in Azeroth, playing the game's own music,
-- with a spectrum visualizer, a progress bar and a station list.
--
-- How it plays (as Leatrix Plus's music player does): PlaySoundFile(fileID, "Master", false, true) gives a
-- handle, StopSound(handle) stops it; a played file sends no "finished" event, so each track's length is known
-- (the data below, from Leatrix Plus's music list) and the next one is started on a timer. While it plays, the
-- zone music is switched off (it would play over the radio) and switched back on when the radio stops, after
-- a /reload too. The radio keeps playing with the window closed (.wowamp stop, or P in the window, stops it).
--
-- The visualizer is made up (the game gives addons no audio to measure): bars driven by each station's tempo,
-- colours and feel (Moonwell's lo-fi low and smooth, WAR Radio's tall and punchy...), in one of cliamp-like
-- styles (bars, blocks, mirror, wave, peaks, off), moving only while a track plays, resting once fallen.
--
-- Keys in the window (only these are taken; any other key reaches the game): Up/Down pick a station, Enter
-- tunes in, 1-9 and 0 tune straight in, N or Right next track, B or Left back, P play/stop, S shuffle,
-- V the visualizer's style, Esc or ` close. It doesn't open in combat and closes when combat starts (keys can't be passed on in combat);
-- the music plays on.

local W = {}
ns.Wowamp = W

local Theme = ns.Theme
local Panel = ns.Panel

-- Stations: name, place, genre, a line from the DJ, the visualizer's colours (low, high), its tempo, and
-- the tracks: { file ID, seconds, title } (file IDs and lengths from Leatrix Plus's music list).
W.STATIONS = {
	{ id = "lionspride", name = "Lion's Pride FM", place = "Goldshire, Elwynn Forest", genre = "Tavern & folk", tag = "Live from the inn: a lute, a fire and an ale that's mostly foam.", lo = "ffd36b", hi = "ff8a2a", bpm = 96, tracks = {
		{ 53737, 47, "Tavern Alliance 01" },
		{ 53738, 51, "Tavern Alliance 02" },
		{ 53744, 48, "Tavern Horde 01" },
		{ 53745, 39, "Tavern Horde 02" },
		{ 53746, 47, "Tavern Horde 03" },
		{ 53680, 54, "Day Plains 01" },
		{ 53681, 77, "Day Plains 02" },
		{ 53492, 56, "Day Forest 01" },
		{ 53493, 73, "Day Forest 02" },
		{ 53494, 65, "Day Forest 03" },
	} },
	{ id = "classical", name = "Stormwind Classical 101.7", place = "Trade District, Stormwind", genre = "Orchestral", tag = "Brass, choirs and the Cathedral bells. Long live the King.", lo = "8ab4ff", hi = "ffd200", bpm = 72, tracks = {
		{ 53202, 55, "Stormwind 01 (moment)" },
		{ 53203, 36, "Stormwind 02 (moment)" },
		{ 53204, 70, "Stormwind 03 (moment)" },
		{ 53205, 62, "Stormwind 04" },
		{ 53206, 61, "Stormwind 05" },
		{ 53207, 54, "Stormwind 06" },
		{ 53208, 87, "Stormwind 07" },
		{ 53209, 77, "Stormwind 08" },
		{ 53211, 67, "Stormwind Intro (moment)" },
		{ 53223, 161, "WoW Main Theme" },
		{ 625564, 170, "WoW Intro" },
		{ 53224, 48, "Angelic 01" },
		{ 53250, 16, "Sacred 01" },
		{ 53251, 19, "Sacred 02" },
	} },
	{ id = "warradio", name = "WAR Radio 66.6", place = "Valley of Strength, Orgrimmar", genre = "War drums", tag = "Lok'tar! Drums from the Valley of Strength, all day, all night.", lo = "ff5a2a", hi = "ffd060", bpm = 132, tracks = {
		{ 53198, 69, "Orgrimmar 01" },
		{ 53199, 62, "Orgrimmar 02 (moment)" },
		{ 53200, 62, "Orgrimmar 02" },
		{ 53299, 64, "Day Barrens 01" },
		{ 53300, 64, "Day Barrens 02" },
		{ 53301, 55, "Day Barrens 03" },
		{ 53302, 67, "Night Barrens 01" },
		{ 53303, 41, "Night Barrens 02" },
		{ 53304, 47, "Night Barrens 03" },
		{ 53684, 47, "PvP 01" },
		{ 53685, 53, "PvP 02" },
		{ 53686, 40, "PvP 03" },
		{ 53687, 63, "PvP 04" },
		{ 53688, 62, "PvP 05" },
		{ 53225, 48, "Battle 01" },
		{ 53226, 62, "Battle 02" },
		{ 53227, 27, "Battle 03" },
		{ 53228, 36, "Battle 04" },
		{ 53229, 45, "Battle 05" },
		{ 53230, 62, "Battle 06" },
	} },
	{ id = "openskies", name = "Open Skies 92.4", place = "The Rises, Thunder Bluff", genre = "Easy listening", tag = "Wind over the mesas. Earth Mother willing, no Grimtotem calls in today.", lo = "8fd18a", hi = "f2d58a", bpm = 80, tracks = {
		{ 53213, 117, "Thunder Bluff Walking 01" },
		{ 53214, 116, "Thunder Bluff Walking 02" },
		{ 53215, 121, "Thunder Bluff Walking 03" },
		{ 53680, 54, "Day Plains 01" },
		{ 53681, 77, "Day Plains 02" },
		{ 53682, 58, "Night Plains 01" },
		{ 53683, 69, "Night Plains 02" },
		{ 53577, 120, "Day Mountain 01" },
		{ 53578, 67, "Day Mountain 02" },
		{ 53579, 80, "Day Mountain 03" },
	} },
	{ id = "moonwell", name = "Moonwell Lo-fi 88.1", place = "Darnassus, Teldrassil", genre = "Elven lo-fi", tag = "Starlight beats to quest and relax to. Elune-adore.", lo = "b38cff", hi = "6ee7e0", bpm = 70, tracks = {
		{ 53184, 85, "Darnassus Walking 01" },
		{ 53185, 69, "Darnassus Walking 02" },
		{ 53186, 68, "Darnassus Walking 03" },
		{ 53188, 53, "Warrior Terrace" },
		{ 53453, 50, "Enchanted Forest 01" },
		{ 53454, 67, "Enchanted Forest 02" },
		{ 53455, 235, "Enchanted Forest 03" },
		{ 53456, 61, "Enchanted Forest 04" },
		{ 53457, 71, "Enchanted Forest 05" },
		{ 53495, 53, "Night Forest 01" },
		{ 53496, 43, "Night Forest 02" },
		{ 53497, 59, "Night Forest 03" },
		{ 53498, 54, "Night Forest 04" },
		{ 53236, 64, "Magic 01 (moment)" },
		{ 53237, 33, "Magic 01 01" },
		{ 53238, 39, "Magic 01 02" },
	} },
	{ id = "underground", name = "The Undercity Underground", place = "Ruins of Lordaeron, Tirisfal", genre = "Gothic", tag = "Broadcasting from the sewers. The Dark Lady is listening.", lo = "6ee7a8", hi = "9b59ff", bpm = 84, tracks = {
		{ 53216, 67, "Undercity 01" },
		{ 53217, 86, "Undercity 02" },
		{ 53218, 76, "Undercity 03" },
		{ 53426, 55, "Cursed Land 01" },
		{ 53427, 59, "Cursed Land 02" },
		{ 53428, 64, "Cursed Land 03" },
		{ 53429, 79, "Cursed Land 04" },
		{ 53430, 83, "Cursed Land 05" },
		{ 53431, 74, "Cursed Land 06" },
		{ 53486, 71, "Day Evil Forest 01" },
		{ 53487, 72, "Day Evil Forest 02" },
		{ 53488, 71, "Day Evil Forest 03" },
		{ 53489, 57, "Night Evil Forest 01" },
		{ 53490, 76, "Night Evil Forest 02" },
		{ 53491, 71, "Night Evil Forest 03" },
		{ 53234, 62, "Haunted 01" },
		{ 53235, 60, "Haunted 02" },
		{ 53231, 36, "Gloomy 01" },
		{ 53232, 40, "Gloomy 02" },
		{ 53252, 26, "Spooky 01 (moment)" },
	} },
	{ id = "necropolis", name = "Necropolis Nights", place = "Naxxramas, Eastern Plaguelands", genre = "Doom & dark ambient", tag = "Kel'Thuzad on the late shift. Requests by bone scroll only.", lo = "5fd3ff", hi = "2a6bff", bpm = 66, tracks = {
		{ 53591, 61, "Naxxramas Abomination Boss 01" },
		{ 53592, 67, "Naxxramas Abomination Boss 02" },
		{ 53593, 61, "Naxxramas Abomination Wing 01" },
		{ 53594, 67, "Naxxramas Abomination Wing 02" },
		{ 53595, 61, "Naxxramas Abomination Wing 03" },
		{ 53596, 58, "Naxxramas Frostwyrm 01" },
		{ 53597, 82, "Naxxramas Frostwyrm 02" },
		{ 53598, 62, "Naxxramas Frostwyrm 03" },
		{ 53599, 60, "Naxxramas Frostwyrm 04" },
		{ 53602, 95, "Naxxramas Kel'Thuzad 01" },
		{ 53603, 97, "Naxxramas Kel'Thuzad 02" },
		{ 53604, 76, "Naxxramas Kel'Thuzad 03" },
		{ 53605, 87, "Naxxramas Plague Boss 01" },
		{ 53606, 88, "Naxxramas Plague Wing 01" },
		{ 53607, 72, "Naxxramas Plague Wing 02" },
		{ 53608, 77, "Naxxramas Plague Wing 03" },
		{ 53609, 60, "Naxxramas Spider Boss 01" },
		{ 53610, 64, "Naxxramas Spider Boss 02" },
		{ 53611, 89, "Naxxramas Spider Wing 01" },
		{ 53612, 67, "Naxxramas Spider Wing 02" },
		{ 53613, 47, "Naxxramas Spider Wing 03" },
		{ 53614, 102, "Naxxramas Walking 01" },
		{ 53615, 72, "Naxxramas Walking 02" },
		{ 53616, 87, "Naxxramas Walking 03" },
		{ 53617, 82, "Naxxramas Walking 04" },
		{ 53618, 100, "Naxxramas Walking 05" },
		{ 53619, 99, "Naxxramas Walking 06" },
	} },
	{ id = "junglebeats", name = "Zul'Gurub Jungle Beats", place = "Stranglethorn Vale", genre = "Tribal", tag = "Voodoo, drums and a raptor somewhere close. Stay on the path, mon.", lo = "3fdc5a", hi = "ffb000", bpm = 118, tracks = {
		{ 53541, 46, "Day Jungle 01" },
		{ 53542, 99, "Day Jungle 02" },
		{ 53543, 48, "Day Jungle 03" },
		{ 53544, 55, "Night Jungle 01" },
		{ 53545, 53, "Night Jungle 02" },
		{ 53546, 89, "Night Jungle 03" },
		{ 53254, 85, "Zul'Gurub Voodoo" },
		{ 53695, 97, "Soggy Place 01" },
		{ 53696, 98, "Soggy Place 02" },
		{ 53697, 91, "Soggy Place 03" },
		{ 53698, 90, "Soggy Place 04" },
		{ 53699, 70, "Soggy Place 05" },
		{ 53253, 35, "Swamp 01" },
	} },
	{ id = "static", name = "Silithus Static 13.0", place = "Cenarion Hold, Silithus", genre = "Desert mystery", tag = "The sands hum at night. Don't listen to the whispers in between tracks.", lo = "f2c46b", hi = "c0392b", bpm = 76, tracks = {
		{ 53432, 66, "Day Desert 01" },
		{ 53433, 81, "Day Desert 02" },
		{ 53434, 54, "Day Desert 03" },
		{ 53435, 78, "Night Desert 01" },
		{ 53436, 62, "Night Desert 02" },
		{ 53437, 58, "Night Desert 03" },
		{ 53239, 144, "Ahn'Qiraj Intro 01" },
		{ 53261, 67, "Ahn'Qiraj Exterior Walking 01" },
		{ 53262, 85, "Ahn'Qiraj Exterior Walking 02" },
		{ 53263, 58, "Ahn'Qiraj Exterior Walking 03" },
		{ 53264, 59, "Ahn'Qiraj Exterior Walking 04" },
		{ 53240, 61, "Mystery 01" },
		{ 53241, 54, "Mystery 02" },
		{ 53242, 61, "Mystery 03" },
		{ 53243, 64, "Mystery 04" },
		{ 53244, 82, "Mystery 05" },
		{ 53245, 65, "Mystery 06" },
		{ 53246, 83, "Mystery 07" },
		{ 53247, 83, "Mystery 08" },
		{ 53249, 62, "Mystery 10" },
	} },
	{ id = "gnomeregan", name = "Gnomeregan Frequency", place = "Tinker Town, Ironforge", genre = "Tinker tech", tag = "Broadcast on a borrowed frequency. Radiation levels: mostly fine.", lo = "ffe14a", hi = "4ad7ff", bpm = 104, tracks = {
		{ 53189, 65, "Gnomeregan 01" },
		{ 53190, 65, "Gnomeregan 02" },
		{ 53812, 73, "Day Volcanic 01" },
		{ 53813, 87, "Day Volcanic 02" },
		{ 53814, 71, "Night Volcanic 01" },
		{ 53815, 64, "Night Volcanic 02" },
		{ 53580, 64, "Night Mountain 01" },
		{ 53581, 63, "Night Mountain 02" },
		{ 53582, 69, "Night Mountain 03" },
		{ 53583, 64, "Night Mountain 04" },
	} },
}

W.rand = function(n) return math.random(n) end -- (tests replace it)

local state = { station = nil, order = {}, pos = 1, playing = false, handle = nil, startedAt = 0, gen = 0, fails = 0 }
W.state = state

----------------------------------------------------------------------
-- Sound and settings
----------------------------------------------------------------------

local function GetCV(name)
	local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
	if not get then return nil end
	local ok, v = pcall(get, name)
	return ok and v or nil
end
local function SetCV(name, value)
	local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
	if set then pcall(set, name, value) end
end

local function DB()
	local db = ns.db
	if not db then return {} end
	db.wowamp = db.wowamp or { shuffle = true }
	return db.wowamp
end

-- the zone music off while the radio plays (it would play over it); back on when it stops
local function ZoneMusicOff()
	if GetCV("Sound_EnableMusic") == "1" then
		SetCV("Sound_EnableMusic", "0")
		DB().musicWasOn = true
	end
end
local function ZoneMusicBack()
	local db = DB()
	if db.musicWasOn then
		SetCV("Sound_EnableMusic", "1")
		db.musicWasOn = nil
	end
end

local function StopHandle()
	if state.handle and _G.StopSound then pcall(_G.StopSound, state.handle) end
	state.handle = nil
end

----------------------------------------------------------------------
-- The player
----------------------------------------------------------------------

function W.Station() return state.station and W.STATIONS[state.station] or nil end
function W.Track()
	local st = W.Station()
	return st and st.tracks[state.order[state.pos] or 1] or nil
end
function W.Elapsed() return state.playing and math.max(0, GetTime() - state.startedAt) or 0 end

local Redraw -- (the window's, below)

local function Order(st)
	local order = {}
	for i = 1, #st.tracks do order[i] = i end
	if DB().shuffle then
		for i = #order, 2, -1 do
			local j = W.rand(i)
			order[i], order[j] = order[j], order[i]
		end
	end
	return order
end

local PlayCurrent

local function Advance(step)
	local st = W.Station()
	if not st then return end
	state.pos = state.pos + step
	if state.pos > #state.order then
		state.order = Order(st) -- a new round (reshuffled)
		state.pos = 1
	elseif state.pos < 1 then
		state.pos = #state.order
	end
	PlayCurrent()
end

-- The game cuts a playing file short when it loses focus (with sound in the background off) or at a loading
-- screen, and doesn't start it again: once a second, while the radio plays, ask whether the track still plays
-- (C_Sound.IsPlaying, where the client has it) and start it again if it stopped early. It starts from its
-- beginning: a played file can't be resumed part-way. Back in the game, the music comes back within a second.
local function Watch(gen, track)
	C_Timer.After(1, function()
		if state.gen ~= gen or not state.playing or not state.handle then return end
		local ok, on = pcall(C_Sound.IsPlaying, state.handle)
		if ok and on == false and W.Elapsed() < track[2] - 2 then
			state.cuts = (state.cuts or 0) + 1
			if state.cuts <= 3 then ns:Trace("wowamp: the game cut " .. tostring(track[3]) .. " short; starting it again") end
			PlayCurrent(true)
			return
		end
		Watch(gen, track)
	end)
end
W.CAN_WATCH = function() return C_Sound and type(C_Sound.IsPlaying) == "function" end

PlayCurrent = function(again)
	if not again then state.cuts = 0 end
	local st, track = W.Station(), W.Track()
	if not (st and track) then return end
	StopHandle()
	ZoneMusicOff()
	local ok, willPlay, handle = pcall(_G.PlaySoundFile, track[1], "Master", false, true)
	state.gen = state.gen + 1
	local gen = state.gen
	state.playing, state.startedAt = true, GetTime()
	if ok and willPlay then
		state.handle, state.fails = handle, 0
		ns:Trace(("wowamp: %s - %s (%d, %ds)"):format(st.name, track[3], track[1], track[2]))
		-- the next track when this one ends (a file sends no event when it's done)
		C_Timer.After(track[2] + 1, function()
			if state.gen == gen and state.playing then Advance(1) end
		end)
		if W.CAN_WATCH() then Watch(gen, track) end
	else
		-- the game wouldn't play it (sound off, a file this client lacks): try the next, but not forever
		state.fails = state.fails + 1
		ns:Trace(("wowamp: the game didn't play %s (%d)"):format(track[3], track[1]))
		if state.fails >= #st.tracks then
			W.Stop()
			ns:Print("WoWamp: the game plays no music for that station. Is the game's sound on?")
			return
		end
		C_Timer.After(0.5, function()
			if state.gen == gen and state.playing then Advance(1) end
		end)
	end
	if Redraw then Redraw(true) end
end

--- Tunes in to station i (its number, or its id): a fresh (shuffled) order, from its first track.
function W.Tune(i)
	if type(i) == "string" then
		for n, st in ipairs(W.STATIONS) do if st.id == i then i = n break end end
	end
	local st = W.STATIONS[i]
	if not st then return false end
	state.station = i
	state.order, state.pos, state.fails = Order(st), 1, 0
	DB().station = st.id
	PlayCurrent()
	return true
end

function W.Next() if state.station then Advance(1) end end
--- Back: the track before, or this one from its start once it's been playing a few seconds (as players do).
function W.Prev()
	if not state.station then return end
	if W.Elapsed() > 4 then PlayCurrent() else Advance(-1) end
end

function W.Stop()
	state.gen = state.gen + 1 -- (any waiting next-track timer does nothing)
	state.playing = false
	StopHandle()
	ZoneMusicBack()
	if Redraw then Redraw(true) end
end

--- Play/stop: stopped, it starts again (the current track, from its start: a file can't be paused).
function W.Toggle()
	if state.playing then W.Stop()
	elseif state.station then PlayCurrent()
	else W.Tune(W.Remembered() or 1) end
end

function W.SetShuffle(on)
	DB().shuffle = on and true or false
	local st = W.Station()
	if st then
		-- the rest of the round follows the new setting; the current track keeps playing
		local current = state.order[state.pos]
		state.order = Order(st)
		for k, n in ipairs(state.order) do
			if n == current then state.order[k], state.order[1] = state.order[1], n break end
		end
		state.pos = 1
	end
	if Redraw then Redraw(true) end
end

--- The station last tuned to (its number), if any.
function W.Remembered()
	local id = DB().station
	for n, st in ipairs(W.STATIONS) do if st.id == id then return n end end
end

function W.Find(text)
	text = ns.Lower and ns.Lower(text or "") or tostring(text or ""):lower()
	if text == "" then return nil end
	local n = tonumber(text)
	if n and W.STATIONS[n] then return n end
	for i, st in ipairs(W.STATIONS) do
		local hay = (ns.Lower and ns.Lower(st.name .. " " .. st.id .. " " .. st.place .. " " .. st.genre)) or (st.name .. " " .. st.id):lower()
		if hay:find(text, 1, true) then return i end
	end
end

-- after a /reload or a login the radio isn't playing any more: the zone music comes back if it was switched off
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function() if not state.playing then ZoneMusicBack() end end)

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local WIDTH, HEIGHT = 580, 392
local BARS, VIS_H = 36, 84
local ROW_H, LIST_ROWS = 14, 10
local FPS = 60
local FPS_OFF = 15 -- the visualizer off: only the progress bar moves
local SEGS = 10 -- lit segments a bar has in the Blocks style
local PAD = 5 -- the bars' space inside the box, below and above
local PROG_W = WIDTH - 20 - 110 -- the progress bar (the time sits to its right)

local frame, title, statusText, visBox, nowText, stationText, tagText, progBg, progFill, timeText, listHead, footer, tipText
local bars, caps, rows, blocks = {}, {}, {}, {}
local cursor = 1
local vis = { h = {}, target = {}, peak = {}, hold = {}, lit = {}, acc = 0, retarget = 0, resting = true }
W.vis = vis
local Text = Panel.Text
local lo, hi = { 1, 1, 1 }, { 1, 1, 1 }
local colourKey -- the station colours lo/hi hold ("lo hi" hex)
local barW = (WIDTH - 20 - 12 - (BARS - 1) * 3) / BARS

-- How each station moves (a guess at its music; the game gives no audio to measure): energy (how tall),
-- rise/fall (how fast bars climb and drop: low = smooth), every (seconds between new heights), wobble
-- (how much they jitter), kick (the beat's punch in the bass), tilt (bass over treble; negative: treble),
-- mid (a hump in the middle bands), swell (slow breathing, 0-1), sweep (a wave rolling across the bands),
-- glitch (chance a band spikes).
W.FEEL = {
	lionspride = { energy = 0.62, rise = 7, fall = 2.4, every = 0.12, wobble = 0.5, kick = 0.35, tilt = 0.45, swell = 0.2 },
	classical = { energy = 0.68, rise = 3.2, fall = 1.3, every = 0.2, wobble = 0.3, kick = 0.08, tilt = 0.25, swell = 0.55, sweep = 0.22 },
	warradio = { energy = 0.95, rise = 13, fall = 3.6, every = 0.07, wobble = 0.6, kick = 0.75, tilt = 0.6, swell = 0.1 },
	openskies = { energy = 0.52, rise = 3.8, fall = 1.5, every = 0.18, wobble = 0.35, kick = 0.12, tilt = 0.4, swell = 0.4, sweep = 0.1 },
	moonwell = { energy = 0.36, rise = 2.8, fall = 1.1, every = 0.24, wobble = 0.28, kick = 0.16, tilt = 0.5, swell = 0.3 },
	underground = { energy = 0.55, rise = 5, fall = 1.7, every = 0.16, wobble = 0.45, kick = 0.2, tilt = 0.65, swell = 0.45 },
	necropolis = { energy = 0.6, rise = 3.6, fall = 1.1, every = 0.22, wobble = 0.3, kick = 0.35, tilt = 0.85, swell = 0.5 },
	junglebeats = { energy = 0.85, rise = 11, fall = 3.2, every = 0.08, wobble = 0.55, kick = 0.65, tilt = 0.5, swell = 0.15 },
	static = { energy = 0.5, rise = 5, fall = 1.6, every = 0.13, wobble = 0.7, kick = 0.1, tilt = -0.1, mid = 0.6, swell = 0.4 },
	gnomeregan = { energy = 0.72, rise = 15, fall = 4.8, every = 0.06, wobble = 0.9, kick = 0.3, tilt = 0.2, swell = 0.1, glitch = 0.05 },
}
local DEFAULT_FEEL = { energy = 0.7, rise = 8, fall = 2.6, every = 0.1, wobble = 0.5, kick = 0.4, tilt = 0.5, swell = 0.2 }
local function Feel() local st = W.Station(); return st and W.FEEL[st.id] or DEFAULT_FEEL end

-- Visualizer styles (V cycles, as cliamp's do): bars with falling caps, LED blocks, bars mirrored about the
-- middle, a wave of dots, the falling caps alone, or off (the box folds away and the window gets shorter).
W.STYLES = { "bars", "blocks", "mirror", "wave", "peaks", "off" }
W.STYLE_LABELS = { bars = "Bars", blocks = "Blocks", mirror = "Mirror", wave = "Wave", peaks = "Peaks", off = "Off" }
local function CurrentStyle()
	local s = DB().style
	return W.STYLE_LABELS[s] and s or "bars"
end
W.Style = CurrentStyle

local function Clock(s)
	s = math.max(0, math.floor(s or 0))
	return ("%02d:%02d"):format(math.floor(s / 60), s % 60)
end

local function Mix(f)
	return lo[1] + (hi[1] - lo[1]) * f, lo[2] + (hi[2] - lo[2]) * f, lo[3] + (hi[3] - lo[3]) * f
end

--- The visualizer's colours: the playing station's (else the one under the cursor). Returns whether they changed.
local function StationColours()
	local st = W.Station() or W.STATIONS[cursor] or W.STATIONS[1]
	local key = st.lo .. " " .. st.hi
	if key == colourKey then return false end
	colourKey = key
	lo[1], lo[2], lo[3] = Theme.RGB(st.lo)
	hi[1], hi[2], hi[3] = Theme.RGB(st.hi)
	return true
end

--- New heights for the bars to reach, in the station's feel: its energy and tilt, a kick on its beat, slow
--- breathing, jitter.
local function Retarget()
	local st = W.Station()
	if not (state.playing and st) then
		for i = 1, BARS do vis.target[i] = 0 end
		return
	end
	local f = Feel()
	local t = W.Elapsed()
	local beat = (t * (st.bpm or 90) / 60) % 1
	local kick = math.max(0, 1 - beat * 3.5) -- strong just after each beat, gone by a third of the way
	local swell = 1 - (f.swell or 0) * 0.5 * (1 + math.sin(t * 2 * math.pi / 11)) -- an 11 s breath
	for i = 1, BARS do
		local x = (i - 1) / (BARS - 1)
		local weight = 1 - (f.tilt or 0.5) * x
		if f.mid then weight = weight * (1 + f.mid * (1 - math.abs(2 * x - 1))) * 0.75 end
		local jitter = 1 - (f.wobble or 0.5) + (f.wobble or 0.5) * (W.rand(1000) / 1000)
		local v = (f.energy or 0.7) * weight * swell * (0.45 + 0.55 * jitter)
		v = v + (f.kick or 0) * kick * (x < 0.3 and 1 or 0.3)
		if f.sweep then v = v + f.sweep * (0.5 + 0.5 * math.sin(t * 1.4 - x * 7)) end
		local glitch = f.glitch and W.rand(1000) <= f.glitch * 1000
		if glitch then v = 0.7 + 0.3 * (W.rand(1000) / 1000) end
		v = math.max(0, math.min(1, v))
		-- blended with the last target (a glitch spike isn't): the shape flows from one to the next
		vis.target[i] = glitch and v or ((vis.target[i] or 0) * 0.35 + v * 0.65)
	end
end

local function BarX(i) return 6 + (i - 1) * (barW + 3) end
local SPAN = VIS_H - 2 * PAD

--- Where everything sits for the style (run when the style changes, not every frame).
local function ApplyStyle()
	if not visBox then return end
	local style = CurrentStyle()
	for i = 1, BARS do
		local bar, cap = bars[i], caps[i]
		bar:ClearAllPoints()
		if style == "mirror" then
			bar:SetPoint("CENTER", visBox, "BOTTOMLEFT", BarX(i) + barW / 2, VIS_H / 2)
		else
			bar:SetPoint("BOTTOMLEFT", visBox, "BOTTOMLEFT", BarX(i), PAD)
		end
		bar:Hide()
		cap:SetSize(barW, style == "wave" and 3 or 2)
		cap:ClearAllPoints() -- (Render sets the style's one point; setting it again just moves it)
		cap:Hide()
		if blocks[i] then for k = 1, SEGS do blocks[i][k]:Hide() end end
		vis.lit[i] = -1
	end
	if style == "blocks" then
		local segH = SPAN / SEGS
		for i = 1, BARS do
			blocks[i] = blocks[i] or {}
			for k = 1, SEGS do
				local b = blocks[i][k]
				if not b then
					b = visBox:CreateTexture(nil, "ARTWORK")
					b:SetTexture("Interface\\Buttons\\WHITE8X8")
					blocks[i][k] = b
				end
				b:SetSize(barW, math.max(1, segH - 2))
				b:ClearAllPoints()
				b:SetPoint("BOTTOMLEFT", visBox, "BOTTOMLEFT", BarX(i), PAD + (k - 1) * segH)
				b:SetVertexColor(Mix((k - 1) / (SEGS - 1)))
				b:Hide()
			end
		end
	end
	-- Off: the box folds away and the window is that much shorter
	local off = style == "off"
	visBox:SetShown(not off)
	nowText:ClearAllPoints()
	nowText:SetPoint("TOPLEFT", 12, off and -34 or (-32 - VIS_H - 10))
	W.FitHeight()
end
W.ApplyStyle = ApplyStyle

--- The game's "Sound in Background" off: the radio goes quiet whenever you tab out (and comes back with you).
function W.BackgroundSoundOff() return GetCV("Sound_EnableSoundWhenGameIsInBG") == "0" end

local TIP_H = 14
--- The window's height: shorter with the visualizer off, a line taller while the tip shows.
function W.FitHeight()
	if not frame then return end
	local h = CurrentStyle() == "off" and (HEIGHT - VIS_H - 8) or HEIGHT
	local tip = W.BackgroundSoundOff()
	if tipText then tipText:SetShown(tip) end
	frame:SetHeight(h + (tip and TIP_H or 0))
end

--- Draws the bars' current heights in the style.
local function Render(style)
	if style == "off" then return end
	local t = W.Elapsed()
	for i = 1, BARS do
		local h, peak = vis.h[i] or 0, vis.peak[i] or 0
		local bar, cap = bars[i], caps[i]
		if style == "bars" or style == "mirror" then
			bar:SetHeight(math.max(1, h * SPAN))
			bar:SetVertexColor(Mix(h))
			bar:SetShown(h > 0.01)
			if style == "bars" then
				cap:SetPoint("BOTTOMLEFT", visBox, "BOTTOMLEFT", BarX(i), PAD + peak * SPAN + 1)
				cap:SetShown(peak > 0.02)
			end
		elseif style == "blocks" then
			-- only when the lit count changes: textures shown/hidden, nothing moved
			local lit = math.floor(h * SEGS + 0.5)
			local top = math.min(SEGS, math.floor(peak * SEGS + 0.5))
			local key = lit * 100 + top
			if vis.lit[i] ~= key then
				vis.lit[i] = key
				local col = blocks[i]
				for k = 1, SEGS do col[k]:SetShown(k <= lit or (k == top and top > lit)) end
			end
		elseif style == "wave" then
			-- a dot per band on a wave whose height is the band's level, rolling with the music
			local y = VIS_H / 2 + (SPAN / 2) * h * math.sin(t * 3 + i * 0.55)
			cap:SetPoint("CENTER", visBox, "BOTTOMLEFT", BarX(i) + barW / 2, y)
			cap:SetVertexColor(Mix(h))
			cap:SetShown(state.playing or h > 0.01)
		elseif style == "peaks" then
			cap:SetPoint("BOTTOMLEFT", visBox, "BOTTOMLEFT", BarX(i), PAD + peak * SPAN)
			cap:SetVertexColor(Mix(peak))
			cap:SetShown(peak > 0.02)
		end
	end
end

--- The levels move toward their targets in the station's feel (up at `rise`, down at `fall`); peaks hold,
--- then fall. Returns whether anything still moves.
local function Step(dt)
	local f = Feel()
	local rise, fall = f.rise or 9, f.fall or 2.8
	if not state.playing then rise, fall = 9, 2.8 end -- (stopped: everything drops at the usual speed)
	-- eased: a bar covers the same share of the way each moment (fast when far, gentle as it arrives),
	-- so it never jerks to a stop; a small ripple rolls across the bands so they're never still between beats
	local up, down = 1 - math.exp(-dt * rise * 1.5), 1 - math.exp(-dt * fall * 2.2)
	vis.phase = (vis.phase or 0) + dt -- (the ripple's own clock: frame time, steady whatever the track does)
	local t = vis.phase
	local ripple = state.playing and (0.03 + (f.energy or 0.7) * 0.08) or 0
	local speed = 4 + (f.rise or 9) * 0.3
	local moving = false
	for i = 1, BARS do
		local h, target = vis.h[i] or 0, vis.target[i] or 0
		if ripple > 0 then target = math.max(0, math.min(1, target + ripple * math.sin(t * speed + i * 0.7))) end
		h = h + (target - h) * (h < target and up or down)
		if h < 0.002 and target == 0 then h = 0 end
		vis.h[i] = h
		local peak, hold = vis.peak[i] or 0, vis.hold[i] or 0
		if h >= peak then peak, hold = h, 0.45
		elseif hold > 0 then hold = hold - dt
		else peak = math.max(h, peak - dt * 0.9) end
		vis.peak[i], vis.hold[i] = peak, hold
		if h > 0.002 or peak > 0.002 or target > 0 then moving = true end
	end
	return moving
end

local function DrawBars(dt)
	local moving = Step(dt)
	if bars[1] then Render(CurrentStyle()) end
	return moving
end

function W.SetStyle(style)
	if not W.STYLE_LABELS[style] then return false end
	DB().style = style
	ApplyStyle()
	if Redraw then Redraw(true) end
	return true
end

function W.NextStyle()
	local cur, list = CurrentStyle(), W.STYLES
	for k, s in ipairs(list) do
		if s == cur then return W.SetStyle(list[k % #list + 1]) end
	end
	return W.SetStyle("bars")
end

local shownTime -- what the time text shows (whole seconds * 10000 + the track's length): set only when it changes
local function DrawProgress()
	local track = W.Track()
	local total = track and track[2] or 0
	local el = math.min(W.Elapsed(), total)
	progFill:SetWidth(math.max(1, total > 0 and PROG_W * el / total or 0))
	progFill:SetShown(state.playing and total > 0)
	local key = math.floor(el) * 10000 + total
	if key ~= shownTime then
		shownTime = key
		timeText:SetText(Clock(el) .. " / " .. Clock(total))
	end
end

local function OnUpdate(_, elapsed)
	vis.acc = vis.acc + elapsed
	local off = CurrentStyle() == "off"
	if vis.acc < 1 / (off and FPS_OFF or FPS) then return end
	local dt = math.min(vis.acc, 0.2)
	vis.acc = 0
	local moving = false
	if not off then
		vis.retarget = vis.retarget - dt
		if vis.retarget <= 0 then
			vis.retarget = Feel().every or 0.1
			Retarget()
		end
		moving = DrawBars(dt)
	end
	DrawProgress()
	-- stopped and the bars have fallen: nothing left to move, the loop rests
	if not state.playing and not moving then
		vis.resting = true
		frame:SetScript("OnUpdate", nil)
	end
end

local function Wake()
	if frame and frame:IsShown() and vis.resting then
		vis.resting = false
		vis.acc = 0
		frame:SetScript("OnUpdate", OnUpdate)
	end
end
W.Wake = Wake

local function Style()
	local t = Panel.Layout(frame, WIDTH, HEIGHT)
	local br, bg, bb = Theme.RGB(t.border)
	local pr, pg, pb = Theme.RGB(t.promptBg or t.bg)
	visBox:SetBackdropColor(pr, pg, pb, 1)
	visBox:SetBackdropBorderColor(br, bg, bb, 1)
	progBg:SetColorTexture(pr, pg, pb, 1)
	local ar, ag, ab = Theme.RGB(t.accent)
	progFill:SetColorTexture(ar, ag, ab, 1)
	local tr, tg, tb = Theme.RGB(t.text)
	local dr, dg, db = Theme.RGB(t.dim)
	nowText:SetTextColor(tr, tg, tb)
	stationText:SetTextColor(dr, dg, db)
	tagText:SetTextColor(dr, dg, db)
	timeText:SetTextColor(tr, tg, tb)
	statusText:SetTextColor(dr, dg, db)
	listHead:SetTextColor(ar, ag, ab)
	footer:SetTextColor(dr, dg, db)
	tipText:SetTextColor(ar, ag, ab)
	for _, r in ipairs(rows) do r.band:SetColorTexture(ar, ag, ab, 0.22) end
	W.colors = { text = t.text, dim = t.dim, accent = t.accent }
end

local function Hex(c) return (tostring(c or "ffffff"):gsub("^|c", ""):gsub("^ff(%x%x%x%x%x%x)$", "%1")) end

--- Everything but the moving parts: title, now playing, the station list. `wake`: something changed, so
--- the bars and progress move again.
Redraw = function(wake)
	if not (frame and frame:IsShown()) then return end
	local t = Theme.Get()
	local acc, dim = Hex(t.accent), Hex(t.dim)
	title:SetText(Theme.FixColors(("|cff%sWoWamp|r  |cff%s~ radio for the road|r"):format(acc, dim)))
	local st, track = W.Station(), W.Track()
	local shuffle = DB().shuffle and "shuffle" or "in order"
	statusText:SetText((state.playing and "> playing" or "|| stopped") .. "  ·  " .. shuffle .. "  ·  " .. W.STYLE_LABELS[CurrentStyle()])
	if st and track then
		nowText:SetText(track[3])
		stationText:SetText(("%s  ·  %s  ·  %s"):format(st.name, st.genre, st.place))
		tagText:SetText('"' .. st.tag .. '"')
	else
		nowText:SetText("Nothing playing")
		stationText:SetText("Pick a station and press Enter (or its number)")
		tagText:SetText("")
	end
	-- the blocks are coloured once, when placed: again when the station's colours change
	if StationColours() and CurrentStyle() == "blocks" then ApplyStyle() end
	for i, r in ipairs(rows) do
		local s = W.STATIONS[i]
		if s then
			local on = state.station == i
			local mark = on and (state.playing and ">" or "||") or " "
			r.left:SetText(Theme.FixColors(("|cff%s%s|r %s  %s"):format(acc, mark, i % 10, s.name)))
			r.right:SetText(Theme.FixColors(("|cff%s%s|r"):format(dim, s.genre)))
			r.band:SetShown(i == cursor)
			r:Show()
		else
			r:Hide()
		end
	end
	DrawProgress()
	W.FitHeight()
	if wake or state.playing then Wake() end
end
W.Redraw = function() Redraw(true) end

local function Build()
	if frame then return end
	frame = Panel.Build("TerminalWowamp", W)
	frame:EnableMouse(true)
	frame:SetScript("OnKeyDown", function(self, key) W.KeyDown(self, key) end)
	frame:SetScript("OnHide", function()
		frame:SetScript("OnUpdate", nil) -- (a hidden frame runs none anyway; it starts again on open)
		vis.resting = true
	end)

	title = Text(frame, 14)
	title:SetPoint("TOPLEFT", 12, -10)
	statusText = Text(frame, 11, "RIGHT")
	statusText:SetPoint("TOPRIGHT", -12, -12)

	visBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	visBox:SetPoint("TOPLEFT", 10, -32)
	visBox:SetSize(WIDTH - 20, VIS_H)
	visBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	for i = 1, BARS do
		local b = visBox:CreateTexture(nil, "ARTWORK")
		b:SetTexture("Interface\\Buttons\\WHITE8X8")
		b:SetWidth(barW)
		b:Hide()
		bars[i] = b
		local c = visBox:CreateTexture(nil, "OVERLAY")
		c:SetTexture("Interface\\Buttons\\WHITE8X8")
		c:SetSize(barW, 2)
		c:Hide()
		caps[i] = c
	end
	nowText = Text(frame, 15)
	nowText:SetPoint("TOPLEFT", 12, -32 - VIS_H - 10)
	nowText:SetWidth(WIDTH - 24)
	stationText = Text(frame, 11)
	stationText:SetPoint("TOPLEFT", nowText, "BOTTOMLEFT", 0, -5)
	stationText:SetWidth(WIDTH - 24)
	tagText = Text(frame, 11)
	tagText:SetPoint("TOPLEFT", stationText, "BOTTOMLEFT", 0, -4)
	tagText:SetWidth(WIDTH - 24)

	progBg = frame:CreateTexture(nil, "ARTWORK")
	progBg:SetPoint("TOPLEFT", tagText, "BOTTOMLEFT", 0, -10)
	progBg:SetSize(PROG_W, 6)
	progFill = frame:CreateTexture(nil, "OVERLAY")
	progFill:SetPoint("TOPLEFT", progBg, "TOPLEFT", 0, 0)
	progFill:SetHeight(6)
	timeText = Text(frame, 12, "RIGHT")
	timeText:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
	timeText:SetPoint("TOP", progBg, "TOP", 0, 5)

	listHead = Text(frame, 11)
	listHead:SetPoint("TOPLEFT", progBg, "BOTTOMLEFT", 0, -11)
	listHead:SetText("STATIONS")
	for i = 1, LIST_ROWS do
		local r = CreateFrame("Button", nil, frame)
		r:SetSize(WIDTH - 20, ROW_H)
		r:SetPoint("TOPLEFT", listHead, "BOTTOMLEFT", -2, -4 - (i - 1) * ROW_H)
		r.band = r:CreateTexture(nil, "BACKGROUND")
		r.band:SetAllPoints()
		r.band:Hide()
		r.left = Text(r, 12)
		r.left:SetPoint("LEFT", 4, 0)
		r.right = Text(r, 11, "RIGHT")
		r.right:SetPoint("RIGHT", -4, 0)
		r:SetScript("OnClick", function() cursor = i; W.Tune(i) end)
		r:SetScript("OnEnter", function() cursor = i; Redraw() end)
		rows[i] = r
	end

	footer = Text(frame, 10)
	footer:SetPoint("BOTTOMLEFT", 12, 9)
	tipText = Text(frame, 10)
	tipText:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 4)
	tipText:SetWidth(WIDTH - 24)
	tipText:SetText("Tip: turn on Sound in Background (Options > Audio) and the radio keeps playing while you're tabbed out.")
	tipText:Hide()
	footer:SetText("Up/Down + Enter tune in · N next · B back · P play/stop · S shuffle · V style · Esc close (plays on)")
	W.frame = frame
end

local NUMS = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9, ["0"] = 10 }

--- The player's keys are kept; any other key goes on to the game.
function W.KeyDown(self, key)
	local mine = true
	local n = #W.STATIONS
	if key == "ESCAPE" or key == "`" then
		W.Close()
	elseif key == "UP" then
		cursor = (cursor - 2) % n + 1; Redraw()
	elseif key == "DOWN" then
		cursor = cursor % n + 1; Redraw()
	elseif key == "ENTER" or key == "NUMPADENTER" then
		W.Tune(cursor)
	elseif NUMS[key] and W.STATIONS[NUMS[key]] then
		cursor = NUMS[key]; W.Tune(cursor)
	elseif key == "N" or key == "RIGHT" then
		W.Next()
	elseif key == "B" or key == "LEFT" then
		W.Prev()
	elseif key == "P" then
		W.Toggle()
	elseif key == "S" then
		W.SetShuffle(not DB().shuffle)
	elseif key == "V" then
		W.NextStyle()
	else
		mine = false
	end
	if self and self.SetPropagateKeyboardInput and not InCombatLockdown() then
		pcall(self.SetPropagateKeyboardInput, self, not mine)
	end
end

function W.IsShown() return frame and frame:IsShown() or false end

function W.Open()
	if InCombatLockdown() then
		ns:Print("WoWamp takes over a few keys, which the game doesn't allow in combat. (The music plays on.)")
		return false
	end
	Build()
	Style()
	Panel.Opening(W)
	cursor = state.station or W.Remembered() or 1
	StationColours()
	ApplyStyle()
	frame:Show()
	vis.resting = true
	Redraw(true)
	if not state.playing then
		-- the bars at rest; the first frame draws them flat
		for i = 1, BARS do vis.h[i], vis.target[i], vis.peak[i], vis.hold[i] = 0, 0, 0, 0 end
	end
	return true
end

function W.Close(why)
	if not frame or not frame:IsShown() then return end
	frame:Hide()
	if why == "combat" then ns:Print("WoWamp closed: combat started. The music plays on.") end
end

ns:RegisterCommand("wowamp", {
	desc = "WoWamp: radio stations playing the game's music (.wowamp stop, next, or a station)",
	aliases = { "radio", "amp" },
	complete = function(args)
		if (args or ""):find("%s") then return {} end
		local out = { { "stop", "stop the radio" }, { "next", "skip this track" } }
		for i, st in ipairs(W.STATIONS) do out[#out + 1] = { st.id, i .. "  " .. st.name .. "  ·  " .. st.genre } end
		return out
	end,
	run = function(args)
		args = strtrim(args or "")
		if args == "" then W.Open() return {} end
		local a = ns.Lower and ns.Lower(args) or args:lower()
		if a == "stop" then W.Stop() return { "WoWamp: stopped." } end
		if a == "next" or a == "skip" then
			if not state.station then return { "WoWamp: nothing playing. Try .wowamp" } end
			W.Next()
			local t = W.Track()
			return { "WoWamp: " .. (t and t[3] or "next") }
		end
		local i = W.Find(args)
		if not i then return { "WoWamp: no station called '" .. args .. "'. Try .wowamp" } end
		W.Tune(i)
		local st, t = W.STATIONS[i], W.Track()
		return { ("WoWamp: %s  ·  %s"):format(st.name, t and t[3] or "") }
	end,
})
