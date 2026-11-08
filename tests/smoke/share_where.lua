-- Terminal: Share: where friends are (1.2.2, the player: "players using the Share module can share location with each
-- other as well; have this be a toggle option .share settings; off by default"). Protocol.lua's "W", Share.lua's
-- setting, rows and question. The pretend network is tests/share_net.lua.
local T = ...
local ns, check = T.ns, T.check
local SSH = ns.Ssh

io.write("[share: where friends are]\n")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "tests/smoke/"
local H = assert(loadfile(here .. "../share_net.lua"))(T)
local Key, Net, Up = H.Key, H.Net, H.Up
local GOOD = Key("where are you")
local hmacWas = ns.Crypto.HMAC
ns.Crypto.HMAC = H.QuickHMAC

local function Ws(net, from, to)
	local out = {}
	for _, m in ipairs(net.sent) do
		if m.from == from and m.text:find("^5W") and (not to or SSH.Canon(m.route.target or "") == SSH.Canon(to)) then out[#out + 1] = m.text end
	end
	return out
end

do
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob", carl = "Carl", dan = "Dan" } })
	local B = net.Add("Bob", { friends = { ann = "Ann" } })
	local C = net.Add("Carl", { friends = { ann = "Ann" } }) -- (no group with Ann)
	A.env.where = function() local w = A.me.where if w then return w[1], w[2], w[3] end end
	A.me.where = { 1429, 0.4, 0.6 }
	A:JoinGroup("default", GOOD, nil, true)
	B:JoinGroup("default", GOOD)
	net.Tick(40)
	check(Up(B, "Ann") and Up(A, "Bob") and not Up(C, "Ann"), "(Ann and Bob connected; Carl in no group with her)")
	-- off by default: nothing sent
	net.Tick(30)
	check(#Ws(net, "Ann") == 0 and #B:Places() == 0, "off (the default): where Ann is never goes out")
	-- on: Bob has it at once
	A:SetWhere(true)
	net.Run()
	local p = B:Places()[1]
	check(p and p.name == "Ann" and p.map == 1429 and math.abs(p.x - 0.4) < 1e-4 and math.abs(p.y - 0.6) < 1e-4,
		"turned on: Bob has where Ann is at once: " .. tostring(p and p.map) .. " " .. tostring(p and p.x))
	check(#Ws(net, "Ann", "Carl") == 0, "...and Carl, in no group with her, never")
	-- standing still: not again for a minute; moving: every 15 s
	local n = #Ws(net, "Ann")
	net.Tick(20)
	check(#Ws(net, "Ann") == n, "standing still: not sent again within the minute")
	net.Tick(SSH.WHERE_STILL - 18)
	check(#Ws(net, "Ann") == n + 1, "...then once, a minute on (Bob's row stays)")
	A.me.where = { 1429, 0.45, 0.6 }
	n = #Ws(net, "Ann")
	net.Tick(SSH.WHERE_EVERY + SSH.WHERE_LOOK)
	p = B:Places()[1]
	check(#Ws(net, "Ann") == n + 1 and p and math.abs(p.x - 0.45) < 1e-4, "moved: sent within 15 s: " .. tostring(p and p.x))
	check(A.friends["bob@realm"].pingAt == net.t - SSH.WHERE_LOOK + 1 or A.friends["bob@realm"].pingAt >= net.t - SSH.WHERE_EVERY,
		"a place sent counts as still here (no ping besides): " .. tostring(A.friends["bob@realm"].pingAt) .. " at " .. net.t)
	-- a friend connecting later has it at once
	local D = net.Add("Dan", { friends = { ann = "Ann" } })
	D:JoinGroup("default", GOOD)
	net.Tick(40)
	p = D:Places()[1]
	check(Up(D, "Ann") and p and p.name == "Ann", "Dan, connecting later: has where Ann is as he connects")
	-- in a dungeon (the game doesn't say): "stopped" once, Bob's row gone
	A.me.where = nil
	n = #Ws(net, "Ann", "Bob")
	net.Tick(SSH.WHERE_LOOK + 1)
	local ws = Ws(net, "Ann", "Bob")
	check(#ws == n + 1 and ws[#ws] == "5W" and #B:Places() == 0, "in a dungeon: \"stopped\" said once, Bob's row gone: " .. tostring(ws[#ws]))
	net.Tick(10)
	check(#Ws(net, "Ann", "Bob") == n + 1, "...and not said again")
	-- out again; then turned off: "stopped"
	A.me.where = { 1429, 0.5, 0.5 }
	net.Tick(SSH.WHERE_LOOK + 1)
	check(#B:Places() == 1, "out again: back")
	A:SetWhere(false)
	net.Run()
	ws = Ws(net, "Ann", "Bob")
	check(ws[#ws] == "5W" and #B:Places() == 0, "turned off: they're told, the row goes")
	-- heard of no more: dropped after WHERE_GONE
	A:SetWhere(true)
	net.Run()
	check(#B:Places() == 1, "(on again)")
	net.t = net.t + SSH.WHERE_GONE
	B:Tick()
	check(#B:Places() == 0, "no word for " .. SSH.WHERE_GONE .. " s: Bob drops it")
	-- bad places are let be; a stranger's isn't read
	B:Receive({ kind = "whisper", target = "Ann" }, "5W 1429,20000,5")
	B:Receive({ kind = "whisper", target = "Ann" }, "5W x,1,1")
	check(#B:Places() == 0, "a place off the map, or not numbers: let be")
	C:Receive({ kind = "whisper", target = "Ann" }, "5W 1429,5000,5000")
	check(#C:Places() == 0, "from someone not connected: not kept")
	-- many friends moving: no more often than WHERE_PER_FRIEND s each
	check(math.max(SSH.WHERE_EVERY, 10 * SSH.WHERE_PER_FRIEND) >= 30, "ten friends: a place each 30 s at most (the queue's 1/s kept for bags)")
end

ns.Crypto.HMAC = hmacWas

io.write("[share: .share settings location, its rows and the question]\n")
do
	local savedDB = _G.TerminalShareDB
	_G.TerminalShareDB = {}
	local ep = SSH.game
	local wasOn = ep.whereOn
	check(SSH.Setting("location") == false, "location: off by default")
	local out = SSH.SettingsCmd("location on")
	check(SSH.Setting("location") == true and ep.whereOn == true and _G.TerminalShareDB.settings.location == true,
		".share settings location on: on, remembered: " .. tostring(out and out[1]))
	SSH.SettingsCmd("location off")
	check(SSH.Setting("location") == false and ep.whereOn == false, ".share settings location off")
	out = SSH.SettingsCmd("bogus on")
	check(out and out[1]:find("bogus"), ".share settings bogus: said there's none: " .. tostring(out and out[1]))
	out = SSH.SettingsCmd("list")
	check(out and #out == 2 and out[2]:find("location = off"), ".share settings list: each in chat: " .. tostring(out and out[2]))
	out = SSH.SettingsCmd("location maybe")
	check(out and out[1]:find("on or off"), "a value that's neither: said how")
	check(SSH.RESERVED.settings, "a group can't be called settings")
	-- its row: Enter turns it on
	local rows = {}
	SSH.SettingRows(rows)
	check(#rows == 1 and rows[1].name == "Share your location" and rows[1].staysOpen, "its row: Share your location")
	local printWas = ns.Print
	ns.Print = function() end
	rows[1].activate(rows[1])
	ns.Print = printWas
	check(SSH.Setting("location") == true, "Enter on its row: on")
	SSH.SetSetting("location", false)
	-- where you are, as the game says it
	local was = { inst = _G.IsInInstance, map = _G.C_Map }
	_G.C_Map = setmetatable({ GetBestMapForUnit = function() return 1429 end,
		GetPlayerMapPosition = function() return { x = 0.42, y = 0.65 } end }, { __index = was.map })
	_G.IsInInstance = function() return false end
	local m, x, y = SSH.WhereNow()
	check(m == 1429 and x == 0.42 and y == 0.65, "outside: the zone's map and where on it")
	_G.IsInInstance = function() return true, "party" end
	check(SSH.WhereNow() == nil, "in a dungeon: nothing (never sent from one)")
	_G.IsInInstance = function() return false end
	_G.C_Map.GetPlayerMapPosition = function() return { x = 0, y = 0 } end
	check(SSH.WhereNow() == nil, "0, 0 (the game doesn't know): nothing")
	_G.IsInInstance, _G.C_Map = was.inst, was.map
	-- a friend's place as a row: Enter's map and pin
	local f = { claim = "bob@realm", name = "Bob", items = {}, where = { map = 1429, x = 0.42, y = 0.65, at = ep:Now() } }
	local r = SSH.PlaceRow({ name = "Bob", map = 1429, x = 0.42, y = 0.65, at = ep:Now(), friend = f })
	check(r.ui == 1429 and r.mapID == 1429 and math.abs(r.px - 42) < 1e-6 and r.detail:find("42, 65") and r.activate and r.secure,
		"a friend's place: a spot row (the map and its pin): " .. tostring(r.detail))
	-- the question
	local SP = ns.SharePlaces
	check(SP.Question("where are my friends") and SP.Question("friends location") and SP.Question("where are my friends on the map"),
		"\"where are my friends\", \"friends location\": asked")
	check(not SP.Question("where is hogger") and not SP.Question("friends") and not SP.Question("location"),
		"\"where is hogger\" (nobody sharing by that name), \"friends\" alone: not")
	local friendsWas = ep.friends
	ep.friends = { ["bob@realm"] = f }
	local q = SP.Question("where is bob")
	check(q and q.who == "bob" and SP.Line(q) == "@shared where bob ", "\"where is bob\", Bob sharing his: his row: " .. tostring(q and SP.Line(q)))
	local all = SSH.Rows(ep)
	local place, setting
	for _, e in ipairs(all) do
		if e.key == "where:bob@realm" then place = e end
		if e.key == "sharesetting:location" then setting = e end
	end
	check(place and setting, "@shared lists Bob's place and the setting")
	ep.friends = friendsWas
	check(SP.None()[1] and SP.None()[1].name:find(".share settings location on", 1, true), "nobody sharing: says how to turn it on")
	ep.whereOn = wasOn
	_G.TerminalShareDB = savedDB
end

io.write("[share: where you are, per group (a group's own wins) and your class]\n")
do -- (the player: "allow a global locations setting and a per-group locations setting", "per-group having priority")
	local hw = ns.Crypto.HMAC
	ns.Crypto.HMAC = H.QuickHMAC
	local RAID, DEF = Key("raid group"), Key("default group")
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob", cat = "Cat" } })
	local B = net.Add("Bob", { friends = { ann = "Ann" } })
	local C = net.Add("Cat", { friends = { ann = "Ann" } })
	A.env.where = function() return 1429, 0.4, 0.6, "MAGE" end
	A:JoinGroup("raid", RAID, nil, true)
	A:JoinGroup("default", DEF, nil, true)
	B:JoinGroup("raid", RAID)
	C:JoinGroup("default", DEF)
	net.Tick(40)
	check(Up(B, "Ann") and Up(C, "Ann"), "(Bob in raid, Cat in default, both with Ann)")
	-- global off, raid's own on: Bob only
	A:SetGroupWhere("raid", true)
	net.Tick(2)
	check(#B:Places() == 1 and #C:Places() == 0, "global off, raid's own on: Bob (raid) sees Ann, Cat (default) doesn't")
	check(B:Places()[1].class == "MAGE", "her class comes with it (her dot's colour): " .. tostring(B:Places()[1].class))
	-- global on, raid's own off: Cat only; Bob told she stopped
	A:SetWhere(true)
	A:SetGroupWhere("raid", false)
	net.Tick(2)
	check(#B:Places() == 0 and #C:Places() == 1, "global on, raid's own off: the group's own wins (Cat sees her, Bob's told she stopped)")
	-- raid back to the global setting: both
	A:SetGroupWhere("raid", nil)
	net.Tick(2)
	check(#B:Places() == 1 and #C:Places() == 1, "raid back to the global setting (on): both")
	check(A:GroupWhere(A.groups.raid) and A.groups.raid.where == nil, "(raid follows the global one)")
	-- a friend in both groups: shared when either shares it
	A:SetWhere(false)
	A:SetGroupWhere("default", true)
	net.Tick(2)
	check(#B:Places() == 0 and #C:Places() == 1, "global off, default's own on: Cat only")
	-- an older message without a class still reads
	B:Receive({ kind = "whisper", target = "Ann" }, "5W 1429,5000,5000")
	check(#B:Places() == 1 and B:Places()[1].class == nil, "a place without a class (an older 1.2.2 build): read, a white dot")
	-- .share raid location: the game's commands on an endpoint
	local savedDB = _G.TerminalShareDB
	_G.TerminalShareDB = { groups = { raid = { key = "x" } } }
	local out = SSH.GroupLocationCmd(A, "raid", "on")
	check(A.groups.raid.where == true and _G.TerminalShareDB.groups.raid.location == true and out[1]:find("raid"),
		".share raid location on: raid's own, remembered: " .. tostring(out[1]))
	out = SSH.GroupLocationCmd(A, "raid", "default")
	check(A.groups.raid.where == nil and _G.TerminalShareDB.groups.raid.location == nil, ".share raid location default: as the global setting again")
	out = SSH.GroupLocationCmd(A, "nosuch", "on")
	check(out[1]:find("nosuch"), "a group you're not in: said")
	-- remembered again (a code shown, a rename): its own setting kept
	_G.TerminalShareDB.groups.raid.location = false
	SSH.Remember("raid", string.rep("k", 32), "limited", nil)
	check(_G.TerminalShareDB.groups.raid.location == false, "the group remembered again: its own location kept")
	_G.TerminalShareDB = savedDB
	ns.Crypto.HMAC = hw
end

io.write("[share: friends as class-coloured dots on the world map]\n")
do -- (the player: "player locations should show up as a dot. Regular class-colored dot")
	local D = SSH.Dots
	local W = _G.WorldMapFrame
	local was = { sc = rawget(W, "ScrollContainer"), id = rawget(W, "GetMapID"), shown = W.shown, colors = _G.RAID_CLASS_COLORS, map = _G.C_Map,
		cc = _G.C_ClassColor, friends = SSH.game.friends }
	local canvas = CreateFrame("Frame")
	canvas.GetWidth = function() return 1000 end
	canvas.GetHeight = function() return 600 end
	canvas.GetFrameLevel = function() return 5 end
	W.ScrollContainer = { Child = canvas, GetCanvasScale = function() return 2 end }
	W.GetMapID = function() return 1429 end
	W.shown = true
	_G.C_ClassColor = nil
	_G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
	local now = SSH.game:Now()
	SSH.game.friends = {
		["bob@realm"] = { claim = "bob@realm", name = "Bob", items = {}, where = { map = 1429, x = 0.4, y = 0.6, at = now, class = "MAGE" } },
		["cat@realm"] = { claim = "cat@realm", name = "Cat", items = {}, where = { map = 1411, x = 0.5, y = 0.5, at = now } },
	}
	_G.C_Map = setmetatable({ GetWorldPosFromMapPos = function() return nil end }, { __index = was.map })
	check(D.Start() ~= nil, "a frame of the map's own places them (runs only while it shows)")
	local n = D.Refresh()
	local pin = D.pins[1]
	check(n == 1 and pin and pin.shown and pin.place and pin.place.name == "Bob", "Bob, on the zone shown: a dot; Cat, elsewhere: none")
	check(pin.w == 6 and pin.h == 6, "the dot's size kept on screen at any zoom (12 at a canvas scale of 2: 6): " .. tostring(pin.w))
	local r, g, b
	pin.dot.SetVertexColor = function(_, rr, gg, bb) r, g, b = rr, gg, bb end
	D.Refresh()
	check(r == 0.25 and g == 0.78 and b == 0.92, "in his class's colour (a mage's)")
	-- Cat's zone on the continent shown: placed through the world position
	_G.C_Map = setmetatable({
		GetWorldPosFromMapPos = function(m) if m == 1411 then return 1, { x = 100, y = 200 } end end,
		GetMapPosFromWorldPos = function(cont, world, shown) if cont == 1 and shown == 1429 then return 1429, { x = 0.7, y = 0.2 } end end,
	}, { __index = was.map })
	check(D.Refresh() == 2 and D.pins[2].place.name == "Cat", "Cat's zone on the map shown: her dot too")
	pin.dot.SetVertexColor = function(_, rr, gg, bb) r, g, b = rr, gg, bb end
	D.Refresh()
	-- the map closed: hidden
	W.shown = false
	D.Refresh()
	check(not D.pins[1].shown and not D.pins[2].shown, "the map closed: no dots")
	-- a dot's tooltip and its click: a waypoint on them
	W.shown = true
	D.Refresh()
	local placed
	local M = ns.Maps
	local placeWas, printWas = M.Place, ns.Print
	M.Place = function(t) placed = t return t end
	ns.Print = function() end
	D.pins[1].scripts.OnClick(D.pins[1])
	M.Place, ns.Print = placeWas, printWas
	check(placed and placed.mapID == 1429 and placed.pos.x == 0.4 and placed.name == "Bob", "a click on Bob's dot: a waypoint on him")
	local ok = pcall(D.pins[1].scripts.OnEnter, D.pins[1])
	check(ok, "pointed at: who and where, no error")
	W.ScrollContainer, W.GetMapID, W.shown = was.sc, was.id, was.shown
	_G.RAID_CLASS_COLORS, _G.C_Map, _G.C_ClassColor = was.colors, was.map, was.cc
	SSH.game.friends = was.friends
	D.Refresh()
end
