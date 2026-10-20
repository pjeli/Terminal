-- Terminal: Share, the 0.60.0 review's findings (each failed before its fix): the ticker after a login with saved
-- passwords, a friend who dropped you getting your items back, the guild channel carrying hellos only, pings ahead of
-- others' big syncs, a wrong password tried again in time, leaving a group not joined yet, Battle.net without a realm,
-- pieces cut on whole characters.
local T = ...
local ns, check = T.ns, T.check
local SSH = ns.Ssh

io.write("[share: the 0.60.0 review]\n")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "tests/smoke/"
local H = assert(loadfile(here .. "../share_net.lua"))(T)
local Net, Up = H.Net, H.Up
local hmacWas = ns.Crypto.HMAC
ns.Crypto.HMAC = H.QuickHMAC
local KEY = "default|made-up key"
local HEXKEY = string.rep("ab", 32)

-- logging in with saved passwords: the ticker still runs once the groups are joined
do
	local ep = SSH.game
	local tickers, newWas, dbWas = {}, C_Timer.NewTicker, _G.TerminalShareDB
	C_Timer.NewTicker = function(_, f)
		local t = { f = f }
		function t:Cancel() self.cancelled = true end
		tickers[#tickers + 1] = t
		return t
	end
	ep:Off(); SSH.StopTicker()
	_G.TerminalShareDB = { groups = { default = { key = HEXKEY, mode = "limited", kdf = SSH.KDF_ID } } }
	SSH.OnEvent("PLAYER_LOGIN")
	if tickers[1] then tickers[1].f() end -- (a second in: the groups not joined yet)
	T.FlushAll() -- (LOGIN_WAIT)
	local live = 0
	for _, t in ipairs(tickers) do if not t.cancelled then live = live + 1 end end
	check(#tickers >= 1 and ep:On() and live == 1, "saved passwords at login: joined, and the ticker running: " .. live .. " of " .. #tickers)
	ep:Off(); SSH.ForgetGroups(); SSH.StopTicker()
	C_Timer.NewTicker, _G.TerminalShareDB = newWas, dbWas
end

-- a friend who dropped you (30 minutes' silence, say), you the same session: your items again when you reconnect
do
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob" }, items = { [1500] = 15 }, mode = "limited" })
	local B = net.Add("Bob", { friends = { ann = "Ann" }, items = { [1600] = 20 }, mode = "limited" })
	A:JoinGroup("default", KEY, "limited", true)
	B:JoinGroup("default", KEY, "limited", true)
	A:Hello(); B:Hello()
	net.Tick(10)
	check(Up(B, "Ann") and B:Items()[1500], "connected: Bob has Ann's mat")
	local wholes = 0
	for _, m in ipairs(net.sent) do if m.from == "Ann" and m.text:find("^4D ") then wholes = wholes + 1 end end
	check(wholes == 1, "...sent whole once on connecting, not again for Bob's asking: " .. wholes)
	B:Drop(B.friends["ann@realm"], "no word for 30 minutes")
	check(not Up(B, "Ann") and not B:Items()[1500], "Bob drops Ann")
	net.t = net.t + 700 -- (Ann's next ping)
	net.Tick(40)
	check(Up(B, "Ann") and B:Items()[1500] and B:Items()[1500].total == 15, "...connected again: Ann's items back: "
		.. tostring(B:Items()[1500] and B:Items()[1500].total))
end

-- the guild channel: hellos only. Anything else there from a guild member is let be (it raised an error, and said
-- hello to the whole guild)
do
	local net = Net()
	local A = net.Add("Ann", { guild = "g", items = { [1500] = 1 } })
	net.Add("Mal", { guild = "g" })
	A:JoinGroup("default", KEY, "limited", true)
	net.Run()
	A.peers, net.sent = {}, {}
	local ok1, err1 = pcall(A.Receive, A, { kind = "guild", target = "Mal" }, "4P")
	local ok2, err2 = pcall(A.Receive, A, { kind = "guild", target = "Mal" }, "4D x1,1,1,")
	check(ok1 and ok2 and #net.sent == 0, "4P or 4D on the guild channel: no error, no hello: " .. tostring(err1 or err2) .. ", " .. #net.sent)
end

-- a ping goes ahead of other friends' pieces (behind a big first sync, friends who had theirs heard nothing for half an
-- hour, and dropped you)
do
	local sent, t = {}, 0
	local E = SSH.Endpoint({ now = function() return t end, send = function(_, x) sent[#sent + 1] = x return 0 end,
		locked = function() return false end })
	local fc, fd = { claim = "cal" }, { claim = "dan" }
	E.tokens, E.refillAt = 0, 1e9
	for i = 1, 50 do E:Send({}, "dataC" .. i, "data:cal:" .. i, fc) end
	for i = 1, 50 do E:Send({}, "dataD" .. i, "data:dan:" .. i, fd) end
	E:Send({}, "4P", "ping:bob")
	check(E.queue[1].text == "4P", "a ping ahead of 100 pieces for others: " .. E.queue[1].text)
	-- a wrong password's way, tried again in time (it was kept for good, never said hello to again)
	E.peers.x = { state = "mismatch", mismatch = 0 }
	E.env.broadcast = function() return {} end
	t = SSH.NOANSWER_KEEP + 1
	E:Tick()
	check(E.peers.x == nil, "a password that didn't match: forgotten after a while, to be tried again")
end

-- .share leave a group remembered, not joined (still waiting at login, or one past five): forgotten
do
	local dbWas = _G.TerminalShareDB
	_G.TerminalShareDB = { groups = { raid = { key = HEXKEY, mode = "all", kdf = SSH.KDF_ID } } }
	local out = ns:FindCommand("ssh").run("leave raid")
	check(_G.TerminalShareDB.groups.raid == nil and out[1]:find("raid", 1, true) and not out[1]:find("not in", 1, true),
		".share leave a remembered group not joined: forgotten: " .. tostring(out[1]))
	_G.TerminalShareDB = dbWas
end

-- Battle.net without a realm: only a character of your own realm
do
	local hadBN = rawget(_G, "C_BattleNet")
	_G.C_BattleNet = hadBN or {}
	local bnN, gai, ac, ng = _G.BNGetNumFriends, C_BattleNet.GetFriendGameAccountInfo, C_BattleNet.GetFriendAccountInfo,
		C_BattleNet.GetFriendNumGameAccounts
	_G.BNGetNumFriends = function() return 1 end
	C_BattleNet.GetFriendAccountInfo = function() return { bnetAccountID = 9, isOnline = true } end
	C_BattleNet.GetFriendNumGameAccounts = function() return 1 end
	C_BattleNet.GetFriendGameAccountInfo = function()
		return { gameAccountID = 91, characterName = "Zed", clientProgram = "WoW", isOnline = true }
	end
	SSH.Forget()
	local M = SSH.game.env.matches
	-- (0.60.1: and no realm at all from Battle.net: not taken, whatever realm the claim says)
	check(not M("zed@realm", { kind = "bn", id = 91 }) and not M("zed@elsewhere", { kind = "bn", id = 91 }),
		"Battle.net gives no realm: not taken (it can't be told to be on your realm)")
	-- (0.60.1, the player: "if a friend of mine is playing on a different Forever ruleset (PvE server instead of PvP
	-- server), I can still see their character's items. This should not happen") another realm: not a friend to share
	-- with; your realm, whatever faction: one
	local realm, faction = "Realm", "Horde"
	C_BattleNet.GetFriendGameAccountInfo = function()
		return { gameAccountID = 91, characterName = "Zed", clientProgram = "WoW", isOnline = true, realmName = realm, factionName = faction }
	end
	SSH.Forget()
	check(M("zed@realm", { kind = "bn", id = 91 }) and SSH.game.env.eligible({ kind = "bn", id = 91 }),
		"a Battle.net friend's character on your realm: shared with")
	faction = "Alliance"
	SSH.Forget()
	check(SSH.game.env.eligible({ kind = "bn", id = 91 }), "...the other faction on your realm too")
	realm = "ClassicBetaPvE"
	SSH.Forget()
	check(not SSH.game.env.eligible({ kind = "bn", id = 91 }) and not M("zed@classicbetapve", { kind = "bn", id = 91 })
		and not M("zed@realm", { kind = "bn", id = 91 }), "a Battle.net friend's character on another realm (PvE): not heard, whatever it claims")
	check(not SSH.People().names["zed"], "...nor its name taken for a friend of yours on your realm")
	-- (0.60.2, the player: "no longer able to connect to my friend on the same realm") Battle.net's realm id isn't
	-- GetRealmID()'s numbering: the realm's name decides, an id differing or not
	local idWas, guidWas = rawget(_G, "GetRealmID"), rawget(_G, "UnitGUID")
	_G.GetRealmID = function() return 4619 end
	local rname = "Realm"
	C_BattleNet.GetFriendGameAccountInfo = function()
		return { gameAccountID = 91, characterName = "Zed", clientProgram = "WoW", isOnline = true, realmName = rname, realmID = 1,
			playerGuid = "Player-4619-0000ABCD" }
	end
	SSH.Forget()
	check(SSH.game.env.eligible({ kind = "bn", id = 91 }) and M("zed@realm", { kind = "bn", id = 91 }),
		"your realm by name, whatever Battle.net's realm id says: connected")
	-- no realm name: the server in the GUID, as yours
	rname = nil
	_G.UnitGUID = function(u) if u == "player" then return "Player-4619-00001234" end end
	SSH.Forget()
	check(SSH.game.env.eligible({ kind = "bn", id = 91 }), "no realm name: your server in its GUID, connected")
	_G.UnitGUID = function(u) if u == "player" then return "Player-4620-00001234" end end
	SSH.Forget()
	check(not SSH.game.env.eligible({ kind = "bn", id = 91 }), "...another server in its GUID: not")
	check(table.concat(SSH.Debug(), "\n"):find("left out (another realm): Zed (no realm)", 1, true),
		".share debug says who was left out for another realm")
	_G.GetRealmID, _G.UnitGUID = idWas, guidWas
	_G.BNGetNumFriends, C_BattleNet.GetFriendGameAccountInfo, C_BattleNet.GetFriendAccountInfo = bnN, gai, ac
	C_BattleNet.GetFriendNumGameAccounts = ng
	_G.C_BattleNet = hadBN
	SSH.Forget()
end

-- a snapshot's pieces end on whole characters (a name's "á" cut in two may not be sent)
do
	local t = 0
	local E = SSH.Endpoint({ now = function() return t end, send = function() return 0 end, locked = function() return false end,
		nonce = function() return "00000000000000aa" end,
		items = function()
			local items = {}
			for i = 1, 60 do items[1000 + i] = { [1] = i } end
			return { places = { { who = "x" .. string.rep("á", 120), where = "b" }, { who = "y" .. string.rep("é", 120), where = "k" } }, items = items }
		end })
	E.groups.default = { name = "default", key = "k", mode = "all" }
	local f = { claim = "bob@realm", route = { kind = "whisper", target = "Bob" }, items = {}, groups = { default = true } }
	E.friends[f.claim] = f
	E.tokens, E.refillAt = 0, 1e9
	E:Share(f, true)
	local bad, n, whole = nil, 0, {}
	for _, m in ipairs(E.queue) do
		local i, count, piece = m.text:match("^%dD %w+,(%d+),(%d+),(.*)$")
		if piece then
			n = n + 1
			whole[tonumber(i)] = piece
			local first, last = piece:byte(1), piece:byte(#piece)
			if (first and first >= 128 and first < 192) or (last and last >= 192) then bad = i end
		end
	end
	check(n >= 2 and not bad, "pieces cut on whole characters: " .. n .. " pieces, a bad one: " .. tostring(bad))
	check(table.concat(whole) == E:Snapshot("all"), "...together, the snapshot as it was")
end

ns.Crypto.HMAC = hmacWas
