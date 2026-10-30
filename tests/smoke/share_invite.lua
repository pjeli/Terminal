-- Terminal: Share's invites and codes (branch share-invites): a group's secret made by Terminal, handed to a friend
-- only after their yes; codes read back however they're typed; no kick: leaving someone out is starting over.
local T = ...
local ns, check = T.ns, T.check
local SSH = ns.Ssh

io.write("[share: invites and codes]\n")

local here = debug.getinfo(1, "S").source:sub(2):gsub("share_invite%.lua$", "")
local H = assert(loadfile(here .. "../share_net.lua"))(T)
local Net, Up = H.Net, H.Up
local hmacWas = ns.Crypto.HMAC
ns.Crypto.HMAC = H.QuickHMAC
local savedDB = _G.TerminalShareDB
_G.TerminalShareDB = {}

local function Bytes(seed)
	local t = {}
	for i = 1, 15 do t[i] = string.char((seed * 37 + i * 11) % 256) end
	return table.concat(t)
end
local CODE, CODE2 = SSH.CodeFromBytes(Bytes(1)), SSH.CodeFromBytes(Bytes(2))
local W = function(name) return { kind = "whisper", target = name } end
local function Said(net, pattern) return net.Said(pattern) end

-- codes: written and read back
do
	check(CODE:match("^TS1%-%w%w%w%w%w%-%w%w%w%w%w%-%w%w%w%w%w%-%w%w%w%w%w%-%w%w%w%w%w$") ~= nil, "a code: TS1 and five groups of five: " .. CODE)
	check(not CODE:find("[ILOU]", 5), "...no I, L, O or U in it")
	check(SSH.ReadCode(CODE) == CODE, "read back as written")
	local typed = CODE:lower():gsub("%-", " "):gsub("0", "o"):gsub("1", "l")
	check(SSH.ReadCode(typed) == CODE, "read back typed small, with spaces, O for 0 and L for 1: " .. typed)
	check(SSH.ReadCode("  " .. CODE:gsub("%-", "") .. "  ") == CODE, "...or with no dashes at all")
	-- one character wrong, or two next to each other swapped: a typo, said
	local body = CODE:gsub("%-", ""):sub(4)
	local B32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
	local wrong = 0
	for i = 1, #body do
		local c = body:sub(i, i)
		local other = c == "A" and "B" or "A"
		local _, why = SSH.ReadCode("TS1" .. body:sub(1, i - 1) .. other .. body:sub(i + 1))
		if why == "typo" then wrong = wrong + 1 end
	end
	check(wrong == #body, "every one-character typo caught: " .. wrong .. " of " .. #body)
	local swapped, caught = 0, 0
	for i = 1, #body - 1 do
		local a, b = body:sub(i, i), body:sub(i + 1, i + 1)
		if a ~= b then
			swapped = swapped + 1
			local _, why = SSH.ReadCode("TS1" .. body:sub(1, i - 1) .. b .. a .. body:sub(i + 2))
			if why == "typo" then caught = caught + 1 end
		end
	end
	check(caught >= swapped - 2, "two characters swapped: nearly always caught: " .. caught .. " of " .. swapped)
	check(select(2, SSH.ReadCode("TS1-ABCD")) == "typo", "too short: a typo")
	check(SSH.ReadCode("correct horse") == nil and select(2, SSH.ReadCode("correct horse")) == nil, "a password isn't a code at all")
	check(SSH.KeyOfCode(CODE) == SSH.KeyOfCode(SSH.ReadCode(typed)) and SSH.KeyOfCode(CODE) ~= SSH.KeyOfCode(CODE2),
		"the key: the same from the code however typed, another for another code")
	local a, b = SSH.MakeCode(), SSH.MakeCode()
	check(SSH.ReadCode(a) == a and a ~= b, "Terminal's codes read back, and are never the same twice: " .. a)
end

-- the whole way: Ann invites Bob, Bob says yes, the code comes, they're connected
local function Pair()
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob", carl = "Carl" }, items = { [2589] = 5 } })
	local B = net.Add("Bob", { friends = { ann = "Ann", carl = "Carl" }, items = { [2589] = 7 } })
	A:JoinGroup("default", SSH.KeyOfCode(CODE), nil, true).code = CODE
	return net, A, B
end
do
	local net, A, B = Pair()
	local joined
	B.env.joined = function(name, key, mode, code) joined = { name = name, key = key, code = code } end
	check(A:Invite(W("Bob"), "Bob", "default"), "Ann invites Bob")
	net.Run()
	check(Said(net, "Bob: Share: Ann invites you to share bags in the group default. Type .share accept Ann"), "Bob is told how to say yes")
	check(not B:On() and #B:Invites() == 1, "...and isn't in it yet: the invite waits")
	for _, m in ipairs(net.sent) do check(not m.text:find(CODE:gsub("%-", "%%-"), 1), "the invite itself holds no code: " .. m.text) end
	local o = B:Offer("ann")
	check(o and B:Accept(o), "Bob says yes (found by the name, any capitals)")
	net.Run()
	check(B.groups.default and B.groups.default.key == A.groups.default.key and B.groups.default.code == CODE, "the code came: Bob is in default, Ann's code")
	check(joined and joined.name == "default" and joined.code == CODE, "...and remembers it")
	check(Said(net, "Ann: Share: Bob accepted; connecting in default") and Said(net, "Bob: Share: joined default with Ann"), "both are told")
	net.Tick(3)
	check(Up(A, "Bob") and Up(B, "Ann") and A:Items()[2589] and A:Items()[2589].total == 7, "connected both ways, items shared")
	check(#A:Invites() == 0 and #B:Invites() == 0, "no invite left waiting either way")
end

-- only what was asked for, only from who was asked
do
	local net, A, B = Pair()
	local C = net.Add("Carl", { friends = { ann = "Ann", bob = "Bob" } })
	A:Invite(W("Bob"), "Bob", "default")
	net.Run()
	local id = B:Offer("Ann").id
	-- the code before a yes: not taken
	B:Receive(W("Ann"), "5G " .. id .. ",c:" .. CODE)
	check(not B:On(), "a code without a yes: not taken")
	-- someone else answering Ann's invite to Bob: no code for them
	net.sent = {}
	A:Receive(W("Carl"), "5J " .. id)
	net.Run()
	local leaked = false
	for _, m in ipairs(net.sent) do if m.text:find("^5G ") then leaked = true end end
	check(not leaked and not C:On(), "Carl saying yes to Bob's invite: no code sent")
	-- someone else sending Bob a code for Ann's invite after his yes: not taken
	B:Accept(B:Offer("Ann"))
	B:Receive(W("Carl"), "5G " .. id .. ",c:" .. CODE2)
	check(not B.groups.default or B.groups.default.key ~= SSH.KeyOfCode(CODE2), "a code from someone else than who invited: not taken")
	net.Run()
	check(B.groups.default and B.groups.default.code == CODE, "...Ann's own comes, and is")
	-- invites never come over the guild channel, nor from strangers
	local net2 = Net()
	local P = net2.Add("Pat", { guild = "G" })
	net2.Add("Mal", { guild = "G" })
	P:Receive({ kind = "guild", target = "Mal" }, "5N 00000000000000aa,default")
	P:Receive(W("Stranger"), "5N 00000000000000ab,default")
	check(#P:Invites() == 0, "an invite on the guild channel, or from a stranger: ignored")
end

-- no thanks; no answer; too late
do
	local net, A, B = Pair()
	A:Invite(W("Bob"), "Bob", "default")
	net.Run()
	local o, k = B:Offer()
	check(o and B:Decline(o, k), "Bob says no thanks (the only invite: no name needed)")
	net.Run()
	check(Said(net, "Ann: Share: Bob said no thanks to default") and #A:Invites() == 0 and #B:Invites() == 0, "Ann is told; it's gone both ways")
	-- unanswered: said when it runs out
	A:Invite(W("Bob"), "Bob", "default")
	net.Run()
	net.Tick(SSH.INVITE_KEEP + 1)
	check(Said(net, "Ann: Share: Bob didn't answer your invite to default"), "an invite nobody answered: said when it runs out")
	check(#B:Invites() == 0, "...gone on Bob's side too")
	-- a yes too late: no code
	A:Invite(W("Bob"), "Bob", "default")
	net.Run()
	local late = B:Offer("Ann")
	net.t = net.t + SSH.INVITE_KEEP + 1
	check(not B:Accept(late), "a yes after it ran out: refused")
	-- the same invite again within a minute isn't said twice
	net.says = {}
	A:Invite(W("Bob"), "Bob", "default")
	A:Invite(W("Bob"), "Bob", "default")
	net.Run()
	local n = 0
	for _, s in ipairs(net.says) do if s:find("invites you") then n = n + 1 end end
	check(n == 1 and #A:Invites() == 1, "invited twice in a row: said once, one invite waiting: " .. n)
end

-- Bob's own default group (with friends of his): Ann's comes in as default-2, and both work
do
	local net, A, B = Pair()
	local C = net.Add("Carl", { friends = { bob = "Bob" } })
	B:JoinGroup("default", SSH.KeyOfCode(CODE2), nil, true).code = CODE2
	C:JoinGroup("default", SSH.KeyOfCode(CODE2), nil, true).code = CODE2
	A:Invite(W("Bob"), "Bob", "default")
	net.Run()
	B:Accept(B:Offer("Ann"))
	net.Run()
	net.Tick(5)
	check(B.groups["default-2"] and B.groups["default-2"].code == CODE and B.groups.default.code == CODE2, "Bob keeps his default; Ann's is default-2")
	check(Said(net, "Bob: Share: joined Ann's group default as default%-2"), "...and he's told")
	B:Hello()
	net.Tick(5)
	check(Up(B, "Ann") and Up(B, "Carl"), "connected with Ann (her default) and Carl (his)")
end

-- codes only: a group with no code (a key alone, as 0.69's typed passwords made) isn't invited to, and a key sent bare
-- ("k:<hex>", 0.69's way) isn't taken
do
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob" } })
	local B = net.Add("Bob", { friends = { ann = "Ann" } })
	local key = H.QuickHMAC("raid", "typed")
	A:JoinGroup("raid", key, nil, true)
	check(not A:Invite(W("Bob"), "Bob", "raid") and next(A.invites) == nil, "a group with no code: no invite")
	check(SSH.ReadSecret("k:" .. ("ab"):rep(32)) == nil and SSH.ReadSecret("c:" .. SSH.CodeFromBytes(("x"):rep(15))) ~= nil,
		"a key sent bare: not taken; a code: taken")
	-- (a "G" carrying a bare key, as if Ann sent one after Bob's yes: Bob joins nothing)
	A:JoinGroup("crew", SSH.KeyOfCode(CODE2), nil, true).code = CODE2
	A:Invite(W("Bob"), "Bob", "crew")
	net.Run()
	local o = B:Offer("Ann")
	B:Accept(o)
	local id = o and o.id
	net.sent, net.inbox = {}, {}
	B:Receive(W("Ann"), SSH.V .. "G " .. tostring(id) .. ",k:" .. ("ab"):rep(32))
	check(B.groups.crew == nil and next(B.groups) == nil, "a bare key after a yes: not joined")
end

-- no kick and no new code pushed (the player: "better to just force users to start over with a trust set"): a friend
-- connected in the group can't move you to another code; leaving someone out is a new group, invited to, the old left
do
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob", carl = "Carl" } })
	local B = net.Add("Bob", { friends = { ann = "Ann", carl = "Carl" } })
	local C = net.Add("Carl", { friends = { ann = "Ann", bob = "Bob" } })
	for _, ep in ipairs({ A, B, C }) do ep:JoinGroup("raid", SSH.KeyOfCode(CODE), nil, true).code = CODE end
	for _, ep in ipairs({ A, B, C }) do ep:Hello() end
	net.Tick(10)
	check(Up(A, "Bob") and Up(A, "Carl") and Up(B, "Carl"), "three in raid, all connected")
	B:Receive(W("Ann"), SSH.V .. "W " .. SSH.Mark(A.groups.raid.key, A:Session(), A:Claim()) .. ",c:" .. CODE2)
	check(B.groups.raid.code == CODE and Up(B, "Ann"), "a new code pushed by a friend connected in the group: not taken")
	-- starting over without Carl: a new group, Bob invited to it, raid left by both
	A:JoinGroup("crew", SSH.KeyOfCode(CODE2), nil, true).code = CODE2
	A:Invite(W("Bob"), "Bob", "crew")
	net.Run()
	B:Accept(B:Offer("Ann"))
	net.Run()
	A:LeaveGroup("raid")
	B:LeaveGroup("raid")
	net.Tick(20)
	check(B.groups.crew and B.groups.crew.code == CODE2 and Up(A, "Bob") and Up(B, "Ann"), "...Ann and Bob start over in crew: connected")
	check(not Up(A, "Carl") and not Up(B, "Carl") and not Up(C, "Ann") and not Up(C, "Bob"), "...Carl, left in raid alone: connected to neither")
end

-- the commands: who, which group, made for you when you have none
do
	local net = Net()
	local A = net.Add("Ann", { friends = { ["plamen-warr"] = "Plamen Warr", bob = "Bob", bobby = "Bobby" } })
	A.env.joined = function(n, k, m, c) SSH.Remember(n, k, m, c) end -- (as the game's does)
	net.Add("Plamen Warr", { friends = { ann = "Ann" } })
	local list = {
		{ name = "Plamen Warr", route = W("Plamen Warr"), how = "friend" },
		{ name = "Bob", route = W("Bob"), how = "guild" },
		{ name = "Bobby", route = W("Bobby"), how = "friend" },
	}
	check(SSH.FindPerson("plamen warr", list).name == "Plamen Warr" and SSH.FindPerson("plam", list).name == "Plamen Warr", "a name, whole or its start")
	check(SSH.FindPerson("bob", list).name == "Bob", "...a whole name wins over a longer one starting so")
	local none, could = SSH.FindPerson("bo", list)
	check(none == nil and #could == 2, "...two starting so: which one")
	local lines = table.concat(SSH.InviteCmd(A, "plamen warr", list), " / ")
	check(A.groups.default and A.groups.default.code and lines:find("made the group default", 1, true) and lines:find("invited Plamen Warr to default", 1, true),
		"no group yet: .share invite makes default, with a code, and invites: " .. lines)
	check(_G.TerminalShareDB.groups.default and _G.TerminalShareDB.groups.default.code == A.groups.default.code, "...the code remembered")
	lines = table.concat(SSH.InviteCmd(A, "bob raid", list), " / ")
	check(A.groups.raid and lines:find("invited Bob to raid", 1, true), "a group named that you don't have: made: " .. lines)
	lines = table.concat(SSH.InviteCmd(A, "bobby", list), " / ")
	check(lines:find("which group", 1, true) and lines:find("default, raid", 1, true), "two groups and none named: which one: " .. lines)
	lines = table.concat(SSH.InviteCmd(A, "Zed", list), " / ")
	check(lines:find("isn't online", 1, true), "someone not there: said: " .. lines)
	lines = table.concat(SSH.CodeCmd(A, "raid"), " / ")
	check(lines:find("raid's code is in the box", 1, true), ".share code: in the box to copy: " .. lines)
	lines = table.concat(SSH.CodeCmd(A, ""), " / ")
	check(lines:find("which group", 1, true), ".share code with two groups: which one")
	local share = ns:FindCommand("share")
	local kick, newcode = share.run("kick Bob")[1], share.run("newcode raid")[1]
	check(kick:find("no owner", 1, true) and kick:find(".share new", 1, true) and newcode == kick,
		".share kick / newcode: none, said how to start over: " .. tostring(kick))
	lines = table.concat(SSH.NewCmd(A, "alts"), " / ")
	check(A.groups.alts and A.groups.alts.code and lines:find("made alts", 1, true), ".share new: a group with a code")
	-- joining with a code typed by hand
	local net2 = Net()
	local B = net2.Add("Bob", { friends = {} })
	lines = table.concat(SSH.JoinWithCode(B, "raid", SSH.ReadCode(A.groups.raid.code:lower())), " / ")
	check(B.groups.raid and B.groups.raid.key == A.groups.raid.key, ".share join raid <code typed small>: the same key as Ann's: " .. lines)
	-- answering
	lines = table.concat(SSH.AnswerCmd(B, "", false), " / ")
	check(lines:find("no invite is waiting", 1, true), ".share accept with nothing waiting: said")
	-- remembered codes come back at login
	check(_G.TerminalShareDB.groups.alts.kdf == SSH.CODE_ID, "a code's group remembered as one")
end

-- the empty prompt suggests an invite waiting for you, before anything else
do
	local E = ns.Easy
	local ep = SSH.game
	ep.offers["w:ann"] = { id = "00000000000000aa", group = "default", name = "Ann", route = W("Ann"), at = ep:Now() }
	check(E.NextExample() == "try: .share accept Ann", "an invite waiting: the prompt suggests saying yes: " .. tostring(E.NextExample()))
	ep.offers["w:ann"] = nil
	check(E.NextExample() ~= "try: .share accept Ann", "...and not once it's gone")
end

_G.TerminalShareDB = savedDB
ns.Crypto.HMAC = hmacWas
