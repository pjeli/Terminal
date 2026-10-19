-- Terminal: Share's groups (0.59.0, the player: ".share join group1 password1"): endpoints in several groups, each with
-- its password and what you share in it. The pretend network is tests/share_net.lua.
local T = ...
local ns, check = T.ns, T.check
local SSH = ns.Ssh

io.write("[share: groups]\n")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "tests/smoke/"
local H = assert(loadfile(here .. "../share_net.lua"))(T)
local Key, Net, Up = H.Key, H.Net, H.Up
local roundsWas = SSH.KDF_ROUNDS
SSH.KDF_ROUNDS = 3
local GOOD = Key("correct horse battery")
local hmacWas = ns.Crypto.HMAC
ns.Crypto.HMAC = H.QuickHMAC

-- groups (0.59.0, the player: ".share join group1 password1"): each its own password and what you share in it
do
	local function Derived(pw, group)
		local k
		SSH.Derive(pw, function(x) k = x end, nil, group)
		return k
	end
	check(Derived("correct horse battery", "default") == GOOD and Derived("correct horse battery", "raid") ~= GOOD,
		"the default group's key is the one made before groups; the same password in another group, another key")
	-- (keys as they come out of Derive, made up here: the harness's SHA-256 is slow)
	local function GKey(pw, group) return group .. "|" .. pw end
	local RAID = GKey("raid night password", "raid")
	check(SSH.Union({ "mats", "consumables" }) == "limited" and SSH.Union({ "limited", "all" }) == "all"
		and SSH.Union({ "none", "mats" }) == "mats" and SSH.Union({}) == "none" and SSH.Union({ "none" }) == "none",
		"what groups share together: mats and consumables are limited; all is all")
	check(SSH.GroupName("Raid-Team") == "raid-team" and not SSH.GroupName("two words") and not SSH.GroupName("")
		and not SSH.GroupName(string.rep("x", 17)) and #SSH.Mark("k1", "0001", "a@r") == 8
		and SSH.Mark("k1", "0001", "a@r") ~= SSH.Mark("k2", "0001", "a@r") and SSH.Mark("k1", "0001", "a@r") ~= SSH.Mark("k1", "0002", "a@r"),
		"a group's name: one word, 16 at most; its mark, 8 hex from its key, another each session")

	-- Ann: raid (all) and default (limited); Bob: raid only; Cat: default only; Dan: both
	local net = Net()
	local everyone = { ann = "Ann", bob = "Bob", cat = "Cat", dan = "Dan" }
	local function Friends(me) local t = {} for k, v in pairs(everyone) do if k ~= me then t[k] = v end end return t end
	local A = net.Add("Ann", { friends = Friends("ann"), items = { [1500] = 4, [2589] = 7 }, mode = "limited" })
	A.me.alt, A.me.gold = { [3000] = 2 }, 99999
	local B = net.Add("Bob", { friends = Friends("bob") })
	local C = net.Add("Cat", { friends = Friends("cat") })
	local D = net.Add("Dan", { friends = Friends("dan") })
	A:JoinGroup("raid", RAID, "all", true)
	A:JoinGroup("default", GOOD, "limited")
	B:JoinGroup("raid", RAID)
	C:JoinGroup("default", GOOD)
	D:JoinGroup("raid", RAID, nil, true)
	D:JoinGroup("default", GOOD)
	net.Tick(40)
	check(Up(B, "Ann") and Up(C, "Ann") and Up(D, "Ann"), "each connected to Ann in the groups they share")
	check(not Up(B, "Cat") and not Up(C, "Bob"), "Bob (raid) and Cat (default) have no group in common: not connected")
	check(B:Items()[3000] and #B:Gold() == 1, "Bob, in raid where Ann shares all: her alt's bank and her gold")
	check(C:Items()[1500] and not C:Items()[2589] and not C:Items()[3000] and #C:Gold() == 0,
		"Cat, in default where Ann shares limited: her crafting mat, nothing else")
	check(D:Items()[3000] and #D:Gold() == 1, "Dan, in both: what both groups share together (all)")
	local fa = A.friends["dan@realm"]
	check(fa and fa.groups.raid and fa.groups.default and A.friends["bob@realm"].groups.raid and not A.friends["bob@realm"].groups.default,
		"Ann knows which groups she has with each")
	-- what Ann shares in raid: mats now; Dan (both) gets limited, Bob mats
	A:SetMode("mats", "raid")
	net.Tick(5)
	check(B:Items()[1500] and not B:Items()[3000] and #B:Gold() == 0, "raid set to mats: Bob gets the mat only")
	check(D:Items()[1500] and not D:Items()[3000] and D.friends["ann@realm"].mode == "limited", "Dan, in both: limited (mats and default's limited)")
	-- Ann leaves raid: Bob (only raid) is said goodbye to; Dan stays, in default
	net.says = {}
	A:LeaveGroup("raid")
	net.Tick(5)
	check(not Up(B, "Ann") and not Up(A, "Bob") and next(B:Items()) == nil, "Ann leaves raid: Bob, raid only, disconnected")
	check(Up(D, "Ann") and D.friends["ann@realm"].groups.default and not D.friends["ann@realm"].groups.raid,
		"...Dan still connected, in default only")
	check(Up(C, "Ann") and A:On() and not A.groups.raid, "...Cat as she was; Ann still sharing")
end

do
	-- the same group, another password: not connected in it; another group in common still connects
	local function GKey(pw, group) return group .. "|" .. pw end
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob" }, items = { [1500] = 1 } })
	local B = net.Add("Bob", { friends = { ann = "Ann" }, items = { [1501] = 1 } })
	A:JoinGroup("raid", GKey("raid night password", "raid"), nil, true)
	A:JoinGroup("default", GOOD)
	B:JoinGroup("raid", GKey("not the raid password", "raid"), nil, true)
	B:JoinGroup("default", GOOD)
	net.Tick(40)
	check(Up(A, "Bob") and A.friends["bob@realm"].groups.default and not A.friends["bob@realm"].groups.raid,
		"another password in raid: connected in default only")
	-- (0.59.0: marks made from keys: another raid password is another mark, raid just not in common)
	check(not net.Said("password for raid"), "...raid's other password: not in common, nothing to say it doesn't match")
	-- a group joined later, on the guild channel: proven again, both groups, connected all along
	local net2 = Net()
	local P = net2.Add("Pat", { guild = "G", items = { [1500] = 1 } })
	local Q = net2.Add("Quin", { guild = "G", items = { [1501] = 1 } })
	P:JoinGroup("default", GOOD)
	Q:JoinGroup("default", GOOD)
	net2.Tick(10)
	check(Up(P, "Quin") and not P.friends["quin@realm"].groups.raid, "connected in default")
	local RAID = GKey("raid night password", "raid")
	Q:JoinGroup("raid", RAID)
	P:JoinGroup("raid", RAID)
	net2.Tick(40)
	check(Up(P, "Quin") and Up(Q, "Pat") and P.friends["quin@realm"].groups.raid and Q.friends["pat@realm"].groups.raid
		and P.friends["quin@realm"].groups.default, "a group joined later: both groups, still connected")
	-- five groups each: every message still fits
	local net3 = Net()
	local X = net3.Add("Xavier-Longname", { friends = { ["yolanda-longname"] = "Yolanda-Longname" } })
	local Y = net3.Add("Yolanda-Longname", { friends = { ["xavier-longname"] = "Xavier-Longname" } })
	for i = 1, SSH.MAX_GROUPS do
		local name = "group-number-" .. i
		local k = GKey("password " .. i .. " here", name)
		X:JoinGroup(name, k, nil, true)
		Y:JoinGroup(name, k, nil, true)
	end
	X:Hello()
	Y:Hello()
	net3.Tick(20)
	local longest = 0
	for _, m in ipairs(net3.sent) do if #m.text > longest then longest = #m.text end end
	local n = 0
	for _ in pairs((X.friends["yolanda-longname@realm"] or {}).groups or {}) do n = n + 1 end
	check(n == SSH.MAX_GROUPS and longest <= 255, "five groups in common: proven in one handshake, every message fits: " .. n .. ", " .. longest)
end

-- (review, 0.59.0) what the groups' review found, each kept
do
	local function GKey(pw, group) return group .. "|" .. pw end
	-- what you share goes by the groups proven on the way you send by, not every way's together
	local net = Net()
	local V = net.Add("Vic", { friends = { bob = "Bob" }, items = { [3000] = 1 }, mode = "all" })
	local B = net.Add("Bob", { friends = { vic = "Vic" } })
	V:JoinGroup("close", GKey("close friends pw", "close"), "all", true)
	V:JoinGroup("public", GKey("public pw here", "public"), "none")
	B:JoinGroup("close", GKey("close friends pw", "close"))
	net.Tick(20)
	check(Up(V, "Bob") and V:ModeFor(V.friends["bob@realm"]) == "all", "Bob, in close: all")
	local w2 = { key = "b:99", route = { kind = "bn", id = 99 }, claim = "bob@realm", name = "Bob", groups = { public = true },
		state = "proved", sess = "abcd" }
	V.peers["b:99"] = w2
	V:Up(w2)
	local f = V.friends["bob@realm"]
	check(f.key == "b:99" and V:ModeFor(f) == "none" and not f.groups.close, "a second way proven in public only: what goes by it, public's (none): "
		.. V:ModeFor(f))
	-- a friend dropped: what was still queued for them doesn't go after the goodbye
	net.throttle = 1000
	f.sentParts = nil
	V:Share(f, true)
	local queued = 0
	for _, m in ipairs(V.queue) do if m.f == f then queued = queued + 1 end end
	V:Drop(f)
	local left = 0
	for _, m in ipairs(V.queue) do if m.f == f then left = left + 1 end end
	net.throttle = 0
	check(queued > 0 and left == 0, "dropped: their queued items gone from the queue: " .. queued .. " -> " .. left)
end

do
	local function GKey(pw, group) return group .. "|" .. pw end
	-- leaving your last group: every friend said goodbye to, past the queue's six at once
	local net = Net()
	local fr = {}
	for i = 1, 8 do fr["f" .. i] = "F" .. i end
	local A = net.Add("Ann", { friends = fr })
	local Fs = {}
	for i = 1, 8 do Fs[i] = net.Add("F" .. i, { friends = { ann = "Ann" } }); Fs[i]:SetKey(GOOD) end
	A:SetKey(GOOD)
	net.Tick(30)
	local up = 0
	for i = 1, 8 do if Up(Fs[i], "Ann") then up = up + 1 end end
	A:LeaveGroup("default")
	net.Tick(10)
	local still = 0
	for i = 1, 8 do if Up(Fs[i], "Ann") then still = still + 1 end end
	check(up == 8 and still == 0 and not A:On(), "the last group left: all eight said goodbye to: " .. up .. " -> " .. still)
	-- a group joined that a friend isn't in: nothing sent again whole
	local net2 = Net()
	local P = net2.Add("Pat", { friends = { quin = "Quin" }, items = { [1500] = 3, [1501] = 4 } })
	local Q = net2.Add("Quin", { friends = { pat = "Pat" }, items = { [1502] = 5 } })
	P:SetKey(GOOD)
	Q:SetKey(GOOD)
	net2.Tick(20)
	net2.sent = {}
	P:JoinGroup("raid", GKey("raid pw words", "raid"))
	net2.Tick(30)
	local whole = 0
	for _, m in ipairs(net2.sent) do if m.text:find("^4D ") then whole = whole + 1 end end
	check(Up(P, "Quin") and Up(Q, "Pat") and whole == 0, "a group joined that Quin isn't in: proven again, nothing sent whole: " .. whole)
	-- the guild's hello from a friend connected, whoever said hello first: let be, on both sides
	local net3 = Net()
	local X = net3.Add("Xia", { guild = "G" })
	local Y = net3.Add("Yan", { guild = "G" })
	X:JoinGroup("default", GOOD, nil, true)
	X:Hello()
	net3.Tick(2)
	Y:JoinGroup("default", GOOD, nil, true)
	net3.Tick(2)
	X:Hello()
	net3.Tick(20)
	check(Up(X, "Yan") and Up(Y, "Xia"), "connected on the guild channel")
	net3.sent = {}
	Y:Hello({ kind = "guild" })
	X:Hello({ kind = "guild" })
	net3.Tick(5)
	local again = 0
	for _, m in ipairs(net3.sent) do if m.text:find("^4C ") then again = again + 1 end end
	check(again == 0, "the guild's hello again from either side: let be, no handshake again: " .. again)
end

do
	local function GKey(pw, group) return group .. "|" .. pw end
	-- both say hello at once while connected: the way keeps taking what comes
	local net = Net()
	local P = net.Add("Pat", { guild = "G" })
	local Q = net.Add("Quin", { guild = "G" })
	P:JoinGroup("default", GOOD)
	Q:JoinGroup("default", GOOD)
	net.Tick(20)
	local p = P.peers["w:quin"]
	check(p and p.state == "up", "connected")
	P.hellos["00000000000000ff"], P.lastBroadcast = net.t, "00000000000000ff"
	p.lastHello = nil
	P:Receive({ kind = "guild", target = "Quin" }, "4H 0000000000000123,quin@realm,9999," .. SSH.Mark(GOOD, "9999", "quin@realm"))
	check(P.peers["w:quin"].wasUp == true, "both said hello at once: the connected way still takes what comes meanwhile")
	-- a group's every proof failing on the way you send by: that friend dropped
	local net2 = Net()
	local A = net2.Add("Ann", { friends = { bob = "Bob" } })
	local B = net2.Add("Bob", { friends = { ann = "Ann" } })
	A:SetKey(GOOD)
	B:SetKey(GOOD)
	net2.Tick(20)
	local w = A.peers["w:bob"]
	local m = SSH.Mark(GOOD, "beef", "bob@realm")
	w.state, w.nA, w.nB, w.offer, w.markOf = "challenged", "0000000000000001", "0000000000000002", { m }, { [m] = "default" }
	A:Proven(w, m .. ":" .. string.rep("0", 32), "I", "bob@realm", "ann@realm", "Bob")
	check(not A.friends["bob@realm"], "no group proven any more on the way you send by: dropped")
	-- the same hello again while you challenge it: the same challenge
	local net3 = Net()
	local C = net3.Add("Zed", { friends = { dan = "Dan" } }) -- (its name after Dan's: it challenges, not says hello again)
	net3.Add("Dan", { friends = { zed = "Zed" } })
	C:SetKey(GOOD)
	net3.Run()
	local hello = "4H 00000000000000c1,dan@realm,dd01," .. SSH.Mark(GOOD, "dd01", "dan@realm")
	C:Receive({ kind = "whisper", target = "Dan" }, hello)
	C:Pump()
	local first = net3.sent[#net3.sent].text:match("^4C %x+,(%x+),")
	net3.t = net3.t + SSH.HELLO_GAP + 1
	C:Receive({ kind = "whisper", target = "Dan" }, hello)
	C:Pump()
	local second = net3.sent[#net3.sent].text:match("^4C %x+,(%x+),")
	check(first and first == second, "the same hello again while challenging it: the same challenge: " .. tostring(first) .. " / " .. tostring(second))
	-- a password being made for another group goes on when your last group is left
	local net4 = Net()
	local E = net4.Add("Eve", { friends = {} })
	E:SetKey(GOOD)
	local later = {}
	local slice = SSH.KDF_SLICE
	SSH.KDF_SLICE = 1
	local rememberWas, badgeWas = SSH.Remember, SSH.Badge
	SSH.Remember, SSH.Badge = function() end, function() end
	SSH.JoinWithPassword(E, "raid", "raid words here", function(fn) later[#later + 1] = fn end)
	SSH.KDF_SLICE = slice
	E:LeaveGroup("default")
	local guard = 0
	while #later > 0 and guard < 100 do table.remove(later, 1)(); guard = guard + 1 end
	SSH.Remember, SSH.Badge = rememberWas, badgeWas
	check(E.groups.raid and not E.groups.default, "the last group left while another's password was being made: that one still joined")
end

-- (0.59.0, the player: "hide the group name and make guessing password slower")
do
	-- a group's mark comes from its key: another password, another mark; another session, another mark; no name in it
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob" } })
	local B = net.Add("Bob", { friends = { ann = "Ann" } })
	A:JoinGroup("raid", "raid|right words", nil, true)
	B:JoinGroup("raid", "raid|other words", nil, true)
	A:Hello(); B:Hello()
	net.Tick(20)
	check(not Up(A, "Bob") and B.waiting["w:ann"] ~= nil, "raid with another password: its marks differ, not in common, not connected")
	local named
	for _, m in ipairs(net.sent) do if m.text:find("raid", 1, true) then named = m.text end end
	check(named == nil, "no message names the group: " .. tostring(named))
	-- someone without the key, answering your guild hello with your own marks sent back: no proof to guess at
	local net2 = Net()
	local Ann = net2.Add("Ann", { guild = "G" })
	net2.Add("Eve", { guild = "G" })
	Ann:JoinGroup("default", GOOD)
	local nA
	for n in pairs(Ann.hellos) do nA = n end
	local sentBefore = #net2.sent
	Ann:Receive({ kind = "guild", target = "Eve" }, "4C " .. nA .. ",00000000000000e1,eve@realm,0000," .. Ann:Marks())
	local proofs = 0
	for i = sentBefore + 1, #net2.sent do if net2.sent[i].text:find("^4A ") then proofs = proofs + 1 end end
	check(nA and proofs == 0, "your own marks sent back by someone without the key: no proof given")
	local before = A:Marks()
	A.sess = "abcd" -- (another session: a /reload)
	A.markCache = {}
	check(A:Marks() ~= before and #before == 8, "another session: another mark for the same group (a guildmate can't follow it)")
	-- guessing a password costs many hashes; the key is made a slice of a frame at a time, by the clock, saying how far
	check(roundsWas >= 4000 and roundsWas <= 5000, "a password's key: 4,000 SHA-256s, each guess the same, light on the game: " .. roundsWas)
	check(SSH.KDF_MS <= 2, "...2 ms of them a frame at most: " .. SSH.KDF_MS)
	local rounds, clockWas, shaWas = SSH.KDF_ROUNDS, _G.debugprofilestop, ns.Crypto.SHA256
	SSH.KDF_ROUNDS = 200
	ns.Crypto.SHA256 = function(m) return ("%032x"):format(#m) end -- (the harness's SHA-256 is slow; the slicing's what's tried)
	local ms = 0
	_G.debugprofilestop = function() ms = ms + 1; return ms end -- (every look at the clock: 1 ms)
	local later, done, seen = {}, nil, {}
	SSH.Derive("words here!", function(k) done = k end, function(fn) later[#later + 1] = fn end, "raid", function(x) seen[#seen + 1] = x end)
	local steps = 1
	while #later > 0 and steps < 1000 do table.remove(later, 1)(); steps = steps + 1 end
	_G.debugprofilestop = clockWas
	SSH.KDF_ROUNDS = rounds
	ns.Crypto.SHA256 = shaWas
	check(done and steps >= 2 and seen[#seen] == 1 and seen[1] < 1, "...over several frames by the clock, how far said each: " .. steps .. " frames")
	local ep = SSH.Endpoint({ now = function() return 0 end })
	ep.deriving, ep.derivingDone = { raid = {} }, { raid = 0.42 }
	check(SSH.DerivingLine(ep):find("42", 1, true) ~= nil, ".share says how far: " .. SSH.DerivingLine(ep))
end

ns.Crypto.HMAC = hmacWas
SSH.KDF_ROUNDS = roundsWas
