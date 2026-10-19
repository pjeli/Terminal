-- Terminal: Share, the share shell (.ssh, 0.58.1): two (and three) endpoints talking over a pretend network. Each is
-- SSH.Endpoint with an env of its own: who's on its friend list and in its guild, what it carries, what the "server"
-- says sent each message.
local T = ...
local ns, check = T.ns, T.check
local SSH = ns.Ssh

io.write("[share: the share shell's protocol]\n")

local roundsWas = SSH.KDF_ROUNDS
SSH.KDF_ROUNDS = 3 -- (the harness's SHA-256 is plain arithmetic: a real key costs seconds here)

-- (the pretend network: tests/share_net.lua)
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "tests/smoke/"
local H = assert(loadfile(here .. "../share_net.lua"))(T)
local Key, Net, Up = H.Key, H.Net, H.Up
local GOOD, BAD = Key("correct horse battery"), Key("wrong horse battery")

-- names, claims, items as text
do
	check(SSH.Canon("Plamen Warr") == "plamen-warr" and SSH.Canon("Plamen-Warr") == "plamen-warr" and SSH.Canon("Bob-Some Realm") == "bob-some-realm",
		"a name the same both ways it's written")
	check(SSH.ClaimIs("plamen-warr@realm", "Plamen Warr") and SSH.ClaimIs("bob@realm", "Bob-Realm") and SSH.ClaimIs("bob@realm", "Bob")
		and not SSH.ClaimIs("bob@realm", "Bobby") and not SSH.ClaimIs("bob@realm", "Bob-Other"), "a claim names its sender, and only it")
	local snap = SSH.Simple("Bob Warr", { [2589] = 35, [6948] = 1, [190000] = 1234 })
	snap.places[2] = { who = "Bobalt", where = "k" }
	snap.places[3] = { who = "", where = "w" }
	snap.items[2589][2], snap.items[777] = 5, { [3] = 2 }
	snap.gold = 123456789
	local text = SSH.Encode(snap)
	local back = SSH.Decode(text)
	check(back.items[2589] == 40 and back.items[6948] == 1 and back.items[190000] == 1234 and back.items[777] == 2 and back.gold == 123456789,
		"a snapshot as text and back: " .. text)
	check(back.places[1].who == "Bob Warr" and back.places[2].where == "k" and back.places[3].where == "w"
		and #SSH.Parts(back.entries[2589]) == 2 and SSH.Parts(back.entries[2589])[2].n == 5, "...where each is kept")
	for _, junk in ipairs({ "", "zz;;x:y:z;-1:5", "a|b|c|d", "|1:zz.5|", "x/b|1:0.-1;2:0.3|" }) do
		local ok, d = pcall(SSH.Decode, junk)
		check(ok and type(d.items) == "table", "rubbish read without an error: " .. junk)
	end
	check(SSH.Decode("x/b!1:5.3!").items[1] == nil, "a place that isn't named: ignored")
	-- (0.58.4, in game: friends' gold seen while they shared limited) gold comes only with all
	local lim = SSH.Decode("Bob/b!1:0.3!2s!limited")
	check(lim.items[1] == 3 and lim.gold == nil and lim.mode == "limited", "gold in a limited snapshot: not taken")
	local all = SSH.Decode("Bob/b!1:0.3!2s!all")
	check(all.gold == 100 and all.mode == "all", "...with all, it is")
end

-- two friends, the same password: connected both ways, each counting the other's items
do
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob" }, items = { [2589] = 15, [118] = 4 } })
	local B = net.Add("Bob", { friends = { ann = "Ann" }, items = { [2589] = 20, [2770] = 7 } })
	A:SetKey(GOOD)
	net.Run()
	check(not Up(A, "Bob") and B.waiting["w:ann"], "Bob without a password: no connection; Ann waits in .ssh")
	B:SetKey(GOOD)
	net.Run()
	check(Up(A, "Bob") and Up(B, "Ann"), "the same password: connected both ways")
	local ai, bi = A:Items(), B:Items()
	check(ai[2589] and ai[2589].total == 20 and ai[2770] and ai[2770].total == 7 and bi[2589].total == 15 and bi[118].total == 4,
		"each has the other's items")
	check(net.Said("Ann: Share: connected to Bob") and net.Said("Bob: Share: connected to Ann"), "each is told")
	-- the password never goes over the wire; nor does the key
	local leaked = false
	for _, m in ipairs(net.sent) do
		if m.text:find("horse", 1, true) or m.text:find(GOOD, 1, true) or m.text:find(ns.Crypto.Hex(GOOD), 1, true) then leaked = true end
	end
	check(not leaked, "neither the password nor the key is ever sent")
	-- bags change: sent again, not more than once each SEND_GAP
	B.me.items[2589] = 2
	B:Changed()
	net.Run()
	check(A:Items()[2589].total == 20, "a change within 15 s waits")
	net.Tick(SSH.SEND_GAP)
	check(A:Items()[2589].total == 2, "...then it's sent: " .. A:Items()[2589].total)
	local before = #net.sent
	B:Changed()
	net.Tick(SSH.SEND_GAP + 1)
	local d = 0
	for i = before + 1, #net.sent do if net.sent[i].text:find("^3D") then d = d + 1 end end
	check(d == 0, "bags that didn't change aren't sent again")
	-- what's shared: limited by default (this character's mats and consumables), mats, consumables, all (alts, gold)
	check(SSH.Endpoint({}).defaultMode == "limited", "limited is the default")
	B.me.items[1500] = 9 -- (a crafting mat here)
	B:SetMode("limited")
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	check(A:Items()[1500] and not A:Items()[2589] and not A:Items()[2770], "limited: the crafting mat, not the rest")
	B:SetMode("mats")
	B.me.items[400] = 1
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	check(A:Items()[1500] and not A:Items()[400], "mats: mats only")
	B.me.items[400] = nil
	B.me.alt, B.me.gold = { [2589] = 100, [3000] = 1 }, 5000000
	B:SetMode("all")
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	local h = A:Items()[2589] and A:Items()[2589].holders[1]
	check(A:Items()[2589].total == 102 and A:Items()[3000] and h and #h.parts == 2, "all: an alt's bank too: " .. tostring(A:Items()[2589].total))
	local said = ns.Stored.ChatSummary({ holders = SSH.StoredHolders(A:Items()[2589].holders), total = 102 })
	check(said == " x102: Bobalt 100 (bank), Bob 2 (bags)", "...where it's kept, as @stored says it: " .. tostring(said))
	local gold = A:Gold()
	check(#gold == 1 and gold[1].gold == 5000000 and gold[1].who == "Bob", "all: gold")
	B:SetMode("limited")
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	check(#A:Gold() == 0 and not A:Items()[3000], "back to limited: no gold, no alts")
	check(table.concat(SSH.Status(A), " "):find("Bob %(items: %d+, sharing: limited, in default%)"), ".ssh says what each friend shares: "
		.. table.concat(SSH.Status(A), " / "))
	-- whatever the bags say, limited sends no gold
	B.me.gold = 777
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2)
	check(#A:Gold() == 0, "limited never sends gold")
	B.me.alt, B.me.gold, B.me.items[1500] = nil, nil, nil
	-- share consumables, then nothing
	B:SetMode("consumables")
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	check(not A:Items()[2770] and not A:Items()[2589] and next(A:Items()) == nil, "share consumables: only those (none here)")
	B.me.items[400] = 3
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	check(A:Items()[400] and A:Items()[400].total == 3 and not A:Items()[2770], "...a consumable is")
	B:SetMode("none")
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	check(next(A:Items()) == nil and Up(A, "Bob"), "share none: still connected, nothing seen")
	-- goodbye
	B:SetMode("all")
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	local changes = net.changed
	B:Off()
	net.Run()
	check(not Up(A, "Bob") and next(A:Items()) == nil and net.changed > changes, ".ssh off: goodbye, Ann drops what Bob sent")
	check(not B:On() and next(B.peers) == nil, "...Bob forgets the key and everyone")
end

-- From here, a quick stand-in for HMAC (the harness's SHA-256 is plain arithmetic: a few handshakes would take the whole
-- instruction budget). The handshake above ran on the real one; crypto.lua checks it against the standard vectors. The
-- stand-in still differs for every key and message, so a wrong password or a relayed proof still fails.
local hmacWas = ns.Crypto.HMAC
ns.Crypto.HMAC = H.QuickHMAC

-- a wrong password: no connection; the side that checked says so; the other hears nothing back
do
	local net = Net()
	local A = net.Add("Ann", { friends = { carl = "Carl" } })
	local C = net.Add("Carl", { friends = { ann = "Ann" } })
	C:SetKey(BAD)
	net.Run()
	A:SetKey(GOOD)
	net.Run()
	check(not Up(A, "Carl") and not Up(C, "Ann"), "different passwords: not connected")
	check(net.Said("password doesn't match"), "the side that checked says the password doesn't match: " .. table.concat(net.says, " / "))
	local said = 0
	for _, m in ipairs(net.sent) do if m.text:find("^3K") then said = said + 1 end end
	check(said == 0, "no proof is ever sent back to a wrong password")
	net.Tick(SSH.HANDSHAKE_TIMEOUT + 1)
	local status = table.concat(SSH.Status(C), " / ") .. " // " .. table.concat(SSH.Status(A), " / ")
	check(status:find("doesn't match", 1, true) or status:find("no answer", 1, true), ".ssh says what happened: " .. status)
	-- (0.58.11, the player) "no answer" is forgotten after a while
	local function NoAnswers()
		local n = 0
		for _, ep in ipairs({ A, C }) do
			for _, p in pairs(ep.peers) do if p.state == "noanswer" then n = n + 1 end end
		end
		return n
	end
	local had = NoAnswers()
	net.Tick(SSH.NOANSWER_KEEP + 1)
	check(had > 0 and NoAnswers() == 0, "a no answer is said, then forgotten after a while: " .. had)
end

-- anyone not a friend, a guild member or a Battle.net friend's character: ignored, never answered
do
	local net = Net()
	local A = net.Add("Ann", { friends = {} })
	local M = net.Add("Mal", { friends = { ann = "Ann" } })
	A:SetKey(GOOD)
	M:SetKey(GOOD) -- (even with the right password)
	M:Hello({ kind = "whisper", target = "Ann" })
	net.Run()
	check(net.SaidTo("Ann", "Mal") == 0 and not Up(A, "Mal") and next(A.waiting) == nil, "a stranger's hello: no answer, not even a wait")
	-- data from a stranger is ignored too
	A:Receive({ kind = "whisper", target = "Mal" }, "3D 1,1,1,1kh:z")
	check(next(A:Items()) == nil, "a stranger's items: ignored")
end

-- a claim that isn't its sender (Mal saying he's Bob): ignored
do
	local net = Net()
	local A = net.Add("Ann", { friends = { mal = "Mal", bob = "Bob" } })
	net.Add("Mal", { friends = { ann = "Ann" } })
	A:SetKey(GOOD)
	net.sent = {}
	A:Receive({ kind = "whisper", target = "Mal" }, "3H 00000000000000aa,bob@realm,0000," .. SSH.Tag("default"))
	check(net.SaidTo("Ann", "Mal") == 0, "a hello claiming another's name: no answer")
end

-- a relay: Mal (a friend of both, without the password) passes Ann's proof to Bob as his own; the proof names Ann and
-- Mal, Bob expects one naming Mal and Bob: refused
do
	local net = Net()
	local A = net.Add("Ann", { friends = { mal = "Mal" } })
	local B = net.Add("Bob", { friends = { mal = "Mal" } })
	A:SetKey(GOOD)
	B:SetKey(GOOD)
	net.inbox, net.sent = {}, {}
	A.peers, B.peers = {}, {} -- (their hellos to Mal unanswered: forgotten)
	local mal = SSH.Claim("Mal", "realm")
	-- Mal says hello to Bob with Ann's nonce; Bob challenges
	A:Hello({ kind = "whisper", target = "Mal" })
	local nA = A.peers["w:mal"].nA
	net.inbox = {}
	B:Receive({ kind = "whisper", target = "Mal" }, "3H " .. nA .. "," .. mal .. ",0000," .. SSH.Tag("default"))
	local challenge = net.sent[#net.sent].text
	local nB = challenge:match("^3C %x+,(%x+),")
	check(nB ~= nil, "Bob challenges Mal: " .. challenge)
	-- Mal hands Bob's challenge to Ann, as if it were his own; Ann proves to Mal
	net.inbox = {}
	A:Receive({ kind = "whisper", target = "Mal" }, "3C " .. nA .. "," .. nB .. "," .. mal .. ",0000," .. SSH.Tag("default"))
	local proof = net.sent[#net.sent].text
	check(proof:find("^3A "), "Ann sends Mal her proof: " .. proof)
	-- Mal passes it on to Bob
	net.inbox = {}
	B:Receive({ kind = "whisper", target = "Mal" }, proof)
	check(not Up(B, "Mal"), "relayed, Ann's proof doesn't connect Mal to Bob")
	check(net.Said("Bob: Share: Mal's password doesn't match"), "...Bob refuses it")
	-- (and a proof sent back as the answer to itself: the two proofs are labelled I and R)
	local p = B.peers["w:mal"]
	check(p.state == "mismatch", "...and Bob's record says so")
end

-- both say hello at once (the guild channel): one handshake goes on, both connect, once
do
	local net = Net()
	local A = net.Add("Ann", { guild = "Gilded" })
	local B = net.Add("Bob", { guild = "Gilded" })
	local C = net.Add("Cat", { guild = "Gilded" })
	A:JoinGroup("default", GOOD, nil, true); B:JoinGroup("default", GOOD, nil, true) -- (keys set together)
	A:Hello()
	B:Hello()
	net.Run()
	check(Up(A, "Bob") and Up(B, "Ann"), "both said hello on the guild channel: connected")
	local n = 0
	for _ in pairs(A.peers) do n = n + 1 end
	check(n == 1, "...once (one record each): " .. n)
	check(not Up(A, "Cat") and C.waiting["w:ann"] and C.waiting["w:bob"], "a guild member without the password: waiting, not connected")
	-- a guild member who joins later
	C:SetKey(GOOD)
	net.Tick(10) -- (the send queue: a few at once, then one a second)
	check(Up(C, "Ann") and Up(C, "Bob") and Up(A, "Cat") and Up(B, "Cat"), "the third, later: connected to both")
	-- your own guild message heard back is ignored (the env says you aren't eligible to yourself)
	net.sent = {}
	A:Receive({ kind = "guild", target = "Ann" }, "3H 00000000000000ab,ann@realm,0000," .. SSH.Tag("default"))
	check(#net.sent == 0, "your own hello heard back: nothing")
end

-- the send queue: a burst, then one a second; the game's "throttled" tried again; nothing while chat is locked
do
	local net = Net()
	local many = {}
	for i = 1, 400 do many[100000 + i * 37] = i end
	local A = net.Add("Ann", { friends = { bob = "Bob" } })
	local B = net.Add("Bob", { friends = { ann = "Ann" }, items = many })
	A:SetKey(GOOD)
	B:SetKey(GOOD)
	net.Run()
	check(Up(A, "Bob"), "connected")
	local pieces = 0
	for _, m in ipairs(B.queue) do if m.text:find("^3D") then pieces = pieces + 1 end end
	check(pieces > 0, "a big bag: the rest of its pieces wait in the queue: " .. pieces)
	B:Send({ kind = "whisper", target = "Ann" }, "3C 0000000000000001,0000000000000002,bob@realm")
	check(B.queue[1].text:find("^3C"), "a handshake goes before items still waiting: " .. B.queue[1].text)
	table.remove(B.queue, 1)
	for _, m in ipairs(net.sent) do check(#m.text <= 255, "each message fits (255): " .. #m.text) end
	net.Tick(60)
	local got = A:Items()
	local n, ok = 0, true
	for id, c in pairs(many) do
		n = n + 1
		if not (got[id] and got[id].total == c) then ok = false end
	end
	check(ok and n == 400, "400 items in pieces, all arrive, one a second")
	-- throttled: kept and sent later
	net.throttle = 2
	local before = #net.sent
	B:Send({ kind = "whisper", target = "Ann" }, "3P")
	check(#net.sent == before and #B.queue == 1, "the game says wait: kept in the queue")
	net.Tick(3)
	check(#B.queue == 0 and #net.sent == before + 1, "...sent a moment later")
	-- locked
	net.locked = true
	B:Send({ kind = "whisper", target = "Ann" }, "3P")
	net.Tick(3)
	check(#B.queue == 1, "chat locked: nothing sent")
	net.locked = false
	net.Tick(2)
	check(#B.queue == 0, "...sent once it isn't")
end

-- delta updates (0.58.16, the stress test): once a friend has a whole snapshot, a change sends only what changed;
-- one built on a snapshot they don't have is asked for whole again
do
	local net = Net()
	local many = {}
	for i = 1, 300 do many[200000 + i] = i end
	local A = net.Add("Ann", { friends = { bob = "Bob" } })
	local B = net.Add("Bob", { friends = { ann = "Ann" }, items = many })
	A:SetKey(GOOD)
	B:SetKey(GOOD)
	net.Tick(40)
	check(A:Items()[200001] and A:Items()[200300].total == 300, "the whole snapshot first")
	local function Sent(letter)
		local n = 0
		for _, m in ipairs(net.sent) do if m.from == "Bob" and m.text:find("^3" .. letter .. " ") then n = n + 1 end end
		return n
	end
	net.sent = {}
	many[200005], many[200010], many[200999] = 77, nil, 4
	B:Changed()
	net.Tick(SSH.SEND_GAP * 3)
	check(Sent("U") == 1 and Sent("D") == 0, "a bag change: one small update, not the whole snapshot: " .. Sent("U") .. " / " .. Sent("D"))
	local it = A:Items()
	check(it[200005].total == 77 and not it[200010] and it[200999].total == 4 and it[200300].total == 300,
		"...changed, gone and new items as they are now")
	-- a delta built on what Ann doesn't have (her copy lost): asked for whole, sent whole
	A.friends["bob@realm"].ver = "zz"
	net.sent = {}
	many[200006] = 66
	B:Changed()
	net.Tick(SSH.SEND_GAP * 3 + 20)
	local asked = 0
	for _, m in ipairs(net.sent) do if m.from == "Ann" and m.text == "3R" then asked = asked + 1 end end
	check(asked == 1 and Sent("D") > 0 and A:Items()[200006].total == 66, "a delta on a snapshot Ann doesn't have: she asks, it comes whole")
	-- nothing changed: nothing sent
	net.sent = {}
	B:Changed()
	net.Tick(SSH.SEND_GAP * 3)
	check(Sent("U") == 0 and Sent("D") == 0, "nothing changed: nothing sent")
	check(SSH.Delta(SSH.EncodeParts(SSH.Simple("x", { [1] = 2 })), SSH.EncodeParts(SSH.Simple("x", { [1] = 2 }))) == nil, "the same parts: no delta")
end

-- memory only: silence drops a friend's items; so does no longer being a friend
do
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob" } })
	local B = net.Add("Bob", { friends = { ann = "Ann" }, items = { [2589] = 5 } })
	A:SetKey(GOOD)
	B:SetKey(GOOD)
	net.Run()
	check(A:Items()[2589], "connected, items there")
	A.me.friends.bob = nil -- (unfriended)
	net.Tick(SSH.RECHECK + 1)
	check(not Up(A, "Bob") and not A:Items()[2589], "no longer a friend: dropped within a minute")
	-- silence
	A.me.friends.bob = "Bob"
	A:Hello({ kind = "whisper", target = "Bob" })
	net.Run()
	check(Up(A, "Bob"), "friends again: connected")
	B.queue = {}
	local sendWas = B.env.send
	B.env.send = function() return 0 end -- (Bob goes quiet: nothing he sends arrives)
	net.Tick(SSH.IDLE_DROP + 2)
	B.env.send = sendWas
	check(not Up(A, "Bob") and not A:Items()[2589], "30 minutes without a word: dropped")
	-- Bob still thinks they're connected: his ping makes Ann say hello again
	net.sent = {}
	A:Receive({ kind = "whisper", target = "Bob" }, "3P")
	net.Run()
	check(Up(A, "Bob"), "a ping from a friend Ann had dropped: connected again")
end

-- friends AND guildmates, a whisper's sender written "Bob-Realm" and the guild channel's "Bob" (0.58.2, in game: connected,
-- "items: 0" on both sides): each heard on two ways; their items arrive whichever way, counted once
do
	local net = Net()
	net.suffix = "-Realm"
	local A = net.Add("Ann", { guild = "Gilded", friends = { bob = "Bob" }, items = { [118] = 4 } })
	local B = net.Add("Bob", { guild = "Gilded", friends = { ann = "Ann" }, items = { [2589] = 20 } })
	A:SetKey(GOOD)
	net.Tick(3)
	net.t = net.t + SSH.HANDSHAKE_TIMEOUT -- (Bob types his password later)
	B:SetKey(GOOD)
	net.Tick(40)
	local ai, bi = A:Items(), B:Items()
	check(ai[2589] and ai[2589].total == 20, "Ann has Bob's items, once: " .. tostring(ai[2589] and ai[2589].total))
	check(bi[118] and bi[118].total == 4, "Bob has Ann's items, once: " .. tostring(bi[118] and bi[118].total))
	check(#A:Connected() == 1 and A:Connected()[1].n == 1 and #B:Connected() == 1 and B:Connected()[1].n == 1,
		".ssh: one friend each, with their items counted")
	-- and it stays so: pings, a change
	B.me.items[2589] = 25
	B:Changed()
	net.Tick(SSH.PING_EVERY + 5)
	check(A:Items()[2589] and A:Items()[2589].total == 25 and #A:Connected() == 1, "...a change arrives; still one friend")
	check((net.pipes or 0) == 0, "no message ever has a \"|\" (chat's escape character): " .. tostring(net.pipes))
end

-- another password typed: the old friends are said goodbye to
do
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob" } })
	local B = net.Add("Bob", { friends = { ann = "Ann" } })
	A:SetKey(GOOD)
	B:SetKey(GOOD)
	net.Run()
	A:SetKey(BAD)
	net.Run()
	check(not Up(B, "Ann") and not Up(A, "Bob"), "a new password: no longer connected to those with the old one")
end

-- (review, 0.58.16) what the protocol's review found, each kept
do
	-- a big snapshot to several friends while bags keep changing: it goes out once, then only what changed; friends
	-- take turns in the queue; everyone ends with the bags as they are (it was dropped for a whole one at the back of the
	-- queue each time, and never ended)
	local net = Net()
	local many = {}
	for i = 1, 600 do many[100000 + i * 37] = i end
	local B = net.Add("Bob", { friends = { a1 = "A1", a2 = "A2", a3 = "A3", a4 = "A4" }, items = many })
	local As = {}
	for k = 1, 4 do As[k] = net.Add("A" .. k, { friends = { bob = "Bob" } }) end
	for k = 1, 4 do As[k]:SetKey(GOOD) end
	B:SetKey(GOOD)
	net.Tick(15)
	for k = 1, 4 do check(Up(As[k], "Bob"), "connected: A" .. k) end
	local id = 100000 + 37
	for step = 1, 12 do
		many[id] = 5000 + step
		B:Changed()
		net.Tick(30)
	end
	net.Tick(60)
	local D, U = 0, 0
	for _, m in ipairs(net.sent) do
		if m.from == "Bob" then
			local l = m.text:match("^3(%u) ")
			if l == "D" then D = D + 1 elseif l == "U" then U = U + 1 end
		end
	end
	local pieces = B.friends["a1@realm"].sentPieces
	local ok = true
	for k = 1, 4 do
		local x = As[k]:Items()[id]
		if not (x and x.total == 5012) then ok = false end
	end
	check(ok and #B.queue == 0, "bags changing under a big snapshot: every friend ends with them as they are, the queue empty")
	check(U >= 4 and D <= 4 * 60, "...the snapshot once, then what changed: " .. D .. " whole pieces, " .. U .. " updates")
	check(pieces == 1, "...the last to each a small update: " .. tostring(pieces))
	-- a small update to one friend while another's whole snapshot goes: it doesn't wait behind it
	local f1, f2 = B.friends["a1@realm"], B.friends["a2@realm"]
	f1.sentParts = nil
	B:Share(f1, true)
	net.Tick(3)
	net.sent = {}
	many[id] = 7777
	B.snaps = {}
	f2.sentAt, f2.doneAt = nil, nil
	B:Share(f2)
	net.Tick(2)
	check(As[2]:Items()[id] and As[2]:Items()[id].total == 7777 and #B.queue > 10,
		"a small update while another friend's snapshot is going: it goes first (" .. #B.queue .. " pieces left behind it)")
end

do
	-- your own hellos don't fill the handshake count: twenty-five friends who don't run it, and a guildmate who does
	local net = Net()
	local fr = {}
	for i = 1, 25 do fr["ghost" .. i] = "Ghost" .. i end
	local A = net.Add("Zoe", { friends = fr, guild = "Gilded" })
	local G = net.Add("Abe", { guild = "Gilded" })
	A:SetKey(GOOD)
	net.Tick(3) -- (Zoe's hello heard before Abe has the password)
	G:SetKey(GOOD)
	net.Tick(40)
	check(Up(A, "Abe") and Up(G, "Zoe"), "many hellos of your own out: a guildmate's hello still answered, connected")
	-- a handshake's time starts when its hello goes, not when it's queued: the 60th, a minute later, still answered
	local fr2 = {}
	for i = 1, 59 do fr2["ghost" .. i] = "Ghost" .. i end
	local net2 = Net()
	local P = net2.Add("Pat", { friends = fr2 })
	local Z = net2.Add("Zed", { friends = { pat = "Pat" } })
	Z:JoinGroup("default", GOOD, nil, true)
	P:SetKey(GOOD)
	P.me.friends.zed = "Zed"
	P:Hello({ kind = "whisper", target = "Zed" })
	net2.Tick(70)
	check(Up(P, "Zed"), "a hello queued behind fifty-nine others: answered, connected: " .. tostring(P.peers["w:zed"] and P.peers["w:zed"].state) .. " " .. tostring(Z.peers["w:pat"] and Z.peers["w:pat"].state))
end

do
	-- a snapshot's number heard again with another count: no error, nothing mixed (a /reload counts from 0 again)
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob" } })
	local B = net.Add("Bob", { friends = { ann = "Ann" }, items = { [2589] = 5 } })
	A:SetKey(GOOD)
	B:SetKey(GOOD)
	net.Run()
	local r = { kind = "whisper", target = "Bob" }
	local ok = pcall(function()
		A:Receive(r, "3D zz,5,10,Bob/b!")
		A:Receive(r, "3D zz,6,10,xx")
		A:Receive(r, "3D zz,1,3,Bob/b!")
		A:Receive(r, "3D zz,2,3,1kh:0.3;")
	end)
	check(ok, "the same number with another count: no error")
	local mine = B.friends["ann@realm"].sentVer or ""
	check(mine:sub(1, #B:Session()) == B:Session() and #B:Session() == 4, "a snapshot's number starts with this session's mark: " .. mine)
	-- a way made again: what was half put together is forgotten
	A.peers["w:bob"].pieces, A.peers["w:bob"].inKey = { "x" }, "Dold,,5"
	A.peers["w:bob"].sess = "beef" -- (Bob /reloaded: another session)
	A:Up(A.peers["w:bob"])
	check(next(A.peers["w:bob"].pieces) == nil and A.peers["w:bob"].inKey == nil and A.friends["bob@realm"].ver == nil,
		"connected again: pieces and their base from before forgotten")
	-- a friend on another version: said once, not a silent "no answer"
	net.says = {}
	A:Receive(r, "1H 00000000000000aa,bob@realm")
	A:Receive(r, "1H 00000000000000ab,bob@realm")
	local said = 0
	for _, t in ipairs(net.says) do if t:find("another version", 1, true) then said = said + 1 end end
	check(said == 1, "another version's hello: said once: " .. said)
end

do
	-- a hello lost (chat locked, in a dungeon): said again a while later
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob" } })
	local B = net.Add("Bob", { friends = { ann = "Ann" } })
	B:SetKey(GOOD)
	net.inbox = {} -- (lost)
	A:JoinGroup("default", GOOD, nil, true) -- (and Ann's own hello never went: a friend list read after it)
	net.Tick(SSH.RETRY_EVERY + SSH.RETRY_TICK + 5)
	check(Up(A, "Bob") and Up(B, "Ann"), "...hello said again later: connected")
	-- and not again and again to who never answers: twice the wait each time
	local net2 = Net()
	local C = net2.Add("Cat", { friends = { nobody = "Nobody" } })
	C:SetKey(GOOD)
	net2.Tick(SSH.RETRY_EVERY * 6)
	local n = net2.SaidTo("Cat", "Nobody")
	check(n >= 2 and n <= 4, "who never answers: said hello to now and then, less often: " .. n)
end

do
	-- goodbyes the game says wait to: still said (.share off)
	local net = Net()
	local A = net.Add("Ann", { friends = { bob = "Bob" } })
	local B = net.Add("Bob", { friends = { ann = "Ann" }, items = { [2589] = 5 } })
	A:SetKey(GOOD)
	B:SetKey(GOOD)
	net.Run()
	check(Up(B, "Ann"), "connected")
	net.throttle = 3
	A:Off()
	net.Tick(5)
	check(not Up(B, "Ann"), ".share off while the game says wait: the goodbye still goes")
	-- a password being made when .share off is typed: never used
	local later = {}
	local slice = SSH.KDF_SLICE
	SSH.KDF_SLICE = 1 -- (made over frames)
	SSH.SetPassword(A, "correct horse battery", function(fn) later[#later + 1] = fn end)
	SSH.KDF_SLICE = slice
	check(#later > 0 and A.deriving, "the password made over frames")
	A:Off()
	local guard = 0
	while #later > 0 and guard < 1000 do table.remove(later, 1)(); guard = guard + 1 end
	check(not A:On() and not A.deriving, ".share off while the password was being set: it isn't set after")
end

do
	-- the guild channel's hello again (.share connect) while connected: the connection holds, items still come
	local net = Net()
	local A = net.Add("Ann", { guild = "Gilded" })
	local B = net.Add("Bob", { guild = "Gilded", items = { [2589] = 5 } })
	A:JoinGroup("default", GOOD, nil, true); B:JoinGroup("default", GOOD, nil, true)
	A:Hello()
	net.Tick(5)
	check(Up(A, "Bob") and Up(B, "Ann"), "connected on the guild channel")
	net.sent = {}
	A:Hello()
	net.Tick(2)
	local churn = 0
	for _, m in ipairs(net.sent) do if m.from == "Bob" and m.text:find("^3C ") then churn = churn + 1 end end
	check(churn == 0, "the guild's hello again, heard by a friend connected: let be, no handshake again: " .. churn)
	B.me.items[2589] = 9
	B:Changed()
	net.Tick(SSH.HANDSHAKE_TIMEOUT + 20)
	check(B.peers["w:ann"] and B.peers["w:ann"].state == "up" and Up(A, "Bob"), "a hello again: still connected both ways")
	check(A:Items()[2589] and A:Items()[2589].total == 9, "...and a change still arrives")
	-- said hello again to one way while connected: what they send still lands meanwhile
	A:Hello({ kind = "whisper", target = "Bob" })
	B.me.items[2589] = 11
	B.friends["ann@realm"].sentAt, B.friends["ann@realm"].doneAt = nil, nil
	B:Changed()
	-- (only what Bob sent Ann: the handshake isn't through yet)
	for i = #net.inbox, 1, -1 do
		if net.inbox[i].to ~= "ann" then table.remove(net.inbox, i) end
	end
	net.Run()
	check(A:Items()[2589] and A:Items()[2589].total == 11 and Up(A, "Bob"), "...a way proven again: its items still land: "
		.. tostring(A:Items()[2589] and A:Items()[2589].total) .. " q" .. #B.queue .. " " .. tostring(A.peers["w:bob"].state) .. " " .. tostring(A.peers["w:bob"].wasUp))
	-- a sender on your realm ("Bob") is bob@<your realm> only
	check(SSH.ClaimIs("bob@realm", "Bob", "realm") and not SSH.ClaimIs("bob@other", "Bob", "realm")
		and SSH.ClaimIs("bob@other", "Bob-Other", "realm"), "a claim with no realm in its sender: yours only")
end

ns.Crypto.HMAC = hmacWas
SSH.KDF_ROUNDS = roundsWas
