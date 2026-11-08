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
