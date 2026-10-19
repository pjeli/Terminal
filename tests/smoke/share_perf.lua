-- Terminal: Share under the game's events (0.60.0 review, measured: tests/stress.py and a review's scripts): bag events
-- in a burst, friends connecting at login, a big guild's roster events, hellos to friends who don't run it.
local T = ...
local ns, check = T.ns, T.check
local SSH = ns.Ssh

io.write("[share: under the game's events]\n")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "tests/smoke/"
local H = assert(loadfile(here .. "../share_net.lua"))(T)
local Net, Up = H.Net, H.Up
local hmacWas = ns.Crypto.HMAC
ns.Crypto.HMAC = H.QuickHMAC
local KEY = "default|made-up key"

do
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob" }, items = { [1500] = 4 }, mode = "limited" })
	local B = net.Add("Bob", { friends = { ann = "Ann" } })
	A:JoinGroup("default", KEY, "limited", true)
	B:JoinGroup("default", KEY, nil, true)
	A:Hello(); B:Hello()
	net.Tick(20)
	check(Up(A, "Bob") and B:Items()[1500], "Ann and Bob connected, Bob has Ann's mat")
	local built = 0
	local items = A.env.items
	A.env.items = function(...) built = built + 1; return items(...) end

	-- a burst of bag events (selling greys): what's shared made once, not once an event
	net.Tick(20) -- (past SEND_GAP)
	built = 0
	for i = 1, 10 do
		if i == 5 then A.me.items[1500] = 9 end
		A:Changed()
	end
	check(built <= 1, "ten bag events in a second: what you share made once at most: " .. built)
	net.Tick(3)
	check(B:Items()[1500] and B:Items()[1500].total == 9, "...and the change still reaches Bob a moment later: "
		.. tostring(B:Items()[1500] and B:Items()[1500].total))

	-- a friend connecting again (force): what you share as it is, not made again (an event starts it again when it changes)
	net.Tick(20)
	A:Changed()
	built = 0
	A:Share(A.friends["bob@realm"], true)
	check(built == 0, "sent again whole to a friend: the snapshot made since the last change, not made again: " .. built)
	A.env.items = items

	-- the send queue: an answer to a handshake goes before hellos still waiting (a login's hundreds of whispers to friends
	-- who don't run Terminal: the answer waited behind them past the other side's timeout, and never connected)
	local queue, tokens, refill = A.queue, A.tokens, A.refillAt
	A.queue, A.tokens, A.refillAt = {}, 0, net.t + 1000
	for i = 1, 3 do A:Send({ kind = "whisper", target = "Nobody" .. i }, SSH.V .. "H 1,x@realm,s,") end
	A:Send({ kind = "whisper", target = "Bob" }, SSH.V .. "C 1,2,ann@realm,s,ab")
	A:Send({ kind = "whisper", target = "Nobody4" }, SSH.V .. "H 1,x@realm,s,")
	check(A.queue[1].text:sub(2, 2) == "C" and A.queue[5].route.target == "Nobody4",
		"an answer goes before the hellos waiting; a hello after them: " .. A.queue[1].text)
	A.queue, A.tokens, A.refillAt = queue, tokens, refill
end

-- a big guild's roster events: the people known read again at most every 2 s, not at once for the next message; the
-- roster read once a member
do
	local was = { rawget(_G, "IsInGuild"), rawget(_G, "GetNumGuildMembers"), rawget(_G, "GetGuildRosterInfo"), rawget(_G, "GetTime") }
	local t, reads = 5000, 0
	_G.GetTime = function() return t end
	_G.IsInGuild = function() return true end
	_G.GetNumGuildMembers = function() return 3 end
	_G.GetGuildRosterInfo = function(i)
		reads = reads + 1
		if i <= 3 then return "Member" .. i .. "-Realm", nil, nil, nil, nil, nil, nil, nil, true, nil, nil, nil, nil, nil, nil, nil, "Player-1-" .. i end
	end
	SSH.Forget()
	SSH.People()
	check(reads == 3, "the roster read once a member: " .. reads)
	reads = 0
	SSH.OnEvent("GUILD_ROSTER_UPDATE")
	SSH.People()
	check(reads == 0, "a roster event: not read again for the next message at once")
	t = t + 2
	SSH.People()
	check(reads == 3, "...but within 2 s: " .. reads)
	_G.IsInGuild, _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.GetTime = was[1], was[2], was[3], was[4]
	SSH.Forget()
end

-- what you share reads @stored as it last read it: a change to it isn't read then and there (in a bag event, in combat,
-- inside Syndicator's callback), but in @stored's own time; once it has, what you share is made again
do
	local p = ns.providers.stored
	if p then
		local entriesWas, dirtyWas = p._entries, p._dirty
		p._entries, p._dirty = { { itemID = 2589, holders = { { mine = true, where = "bank", count = 3 } } } }, true
		local get, asked = ns.GetEntries, 0
		ns.GetEntries = function(self, q, ...) if q == p then asked = asked + 1 end return get(self, q, ...) end
		SSH.Snapshot("limited")
		ns.GetEntries = get
		check(asked == 0, "@stored changed: what you share uses what it last read, not read again then and there: " .. asked)
		-- once @stored has read itself again (another list): what you share made again, once
		local changed = 0
		local ep = { On = function() return true end, Changed = function() changed = changed + 1 end }
		p._entries = {}
		check(SSH.StoredMoved(ep) and changed == 1 and not SSH.StoredMoved(ep) and changed == 1,
			"...@stored read again in its own time: shared again, once: " .. changed)
		p._entries, p._dirty = entriesWas, dirtyWas
	end
end

ns.Crypto.HMAC = hmacWas
