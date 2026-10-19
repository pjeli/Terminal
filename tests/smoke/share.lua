-- Terminal: Share, the share shell (.ssh, 0.58.1): two (and three) endpoints talking over a pretend network. Each is
-- SSH.Endpoint with an env of its own: who's on its friend list and in its guild, what it carries, what the "server"
-- says sent each message.
local T = ...
local ns, check = T.ns, T.check
local SSH = ns.Ssh

io.write("[share: the share shell's protocol]\n")

local roundsWas = SSH.KDF_ROUNDS
SSH.KDF_ROUNDS = 3 -- (the harness's SHA-256 is plain arithmetic: a real key costs seconds here)

local function Key(pw)
	local k
	SSH.Derive(pw, function(x) k = x end)
	return k
end
local GOOD, BAD = Key("correct horse battery"), Key("wrong horse battery")

--- A pretend network: endpoints by lowercase name, messages delivered in order on Run().
local function Net()
	local net = { t = 1000, eps = {}, inbox = {}, sent = {}, says = {}, locked = false, throttle = 0, changed = 0,
		suffix = "" } -- (suffix: how a whisper's sender is written, "-Realm"; the guild channel's never has it)
	local function Who(s) return (SSH.Canon(s):gsub("%-realm$", "")) end
	function net.Add(name, opts)
		opts = opts or {}
		local me = { name = name, friends = opts.friends or {}, guild = opts.guild, items = opts.items or {}, realm = "realm" }
		local env = {
			now = function() return net.t end,
			claim = function() return SSH.Claim(name, me.realm) end,
			send = function(route, text)
				if net.throttle > 0 then net.throttle = net.throttle - 1; return 3 end
				if text:find("|", 1, true) then net.pipes = (net.pipes or 0) + 1 end -- (chat's escape character: never sent)
				net.sent[#net.sent + 1] = { from = name, route = route, text = text }
				if route.kind == "guild" then
					for other, ep in pairs(net.eps) do
						if other ~= name:lower() and ep.me.guild and ep.me.guild == me.guild then
							net.inbox[#net.inbox + 1] = { to = other, route = { kind = "guild", target = name }, text = text }
						end
					end
				else
					net.inbox[#net.inbox + 1] = { to = Who(route.target), route = { kind = "whisper", target = name .. net.suffix }, text = text }
				end
				return 0
			end,
			eligible = function(route)
				local who = route.target
				if Who(who) == Who(name) then return nil end
				if route.kind == "guild" then return who end
				if me.friends[Who(who)] then return who end
				local o = net.eps[Who(who)]
				if o and me.guild and o.me.guild == me.guild then return who end
				return nil
			end,
			matches = function(claim, route) return SSH.ClaimIs(claim, route.target) end,
			-- (here: ids under 1000 are consumables, 1000-1999 crafting mats; me.alt: an alt's bank, me.gold: all gold)
			items = function(mode)
				local keep = ({ limited = function(id) return id < 2000 end, consumables = function(id) return id < 1000 end,
					mats = function(id) return id >= 1000 and id < 2000 end })[mode]
				local out = {}
				for id, n in pairs(me.items) do if mode == "all" or (keep and keep(id)) then out[id] = n end end
				local snap = SSH.Simple(name, out)
				if mode == "all" then
					if me.alt then
						snap.places[2] = { who = name .. "alt", where = "k" }
						for id, n in pairs(me.alt) do
							snap.items[id] = snap.items[id] or {}
							snap.items[id][2] = n
						end
					end
					snap.gold = me.gold
				end
				return snap
			end,
			locked = function() return net.locked end,
			changed = function() net.changed = net.changed + 1 end,
			say = function(text) net.says[#net.says + 1] = name .. ": " .. text end,
			nonce = (function()
				local n = 0
				return function() n = n + 1; return ("%08x%08x"):format(#name * 7919 + name:byte(1), n) end
			end)(),
			broadcast = function()
				local out = {}
				if me.guild then out[#out + 1] = { kind = "guild" } end
				for c, shown in pairs(me.friends) do out[#out + 1] = { kind = "whisper", target = shown } end
				return out
			end,
		}
		local ep = SSH.Endpoint(env)
		ep.me = me
		ep.mode = opts.mode or "all"
		net.eps[name:lower()] = ep
		return ep
	end
	function net.Run(max)
		local n = 0
		while #net.inbox > 0 and n < (max or 500) do
			local m = table.remove(net.inbox, 1)
			local ep = net.eps[m.to]
			if ep then ep:Receive(m.route, m.text) end
			n = n + 1
		end
	end
	function net.Tick(seconds)
		for _ = 1, seconds do
			net.t = net.t + 1
			for _, ep in pairs(net.eps) do ep:Tick() end
			net.Run()
		end
	end
	function net.SaidTo(from, to)
		local n = 0
		for _, m in ipairs(net.sent) do
			if m.from == from and m.route.target and SSH.Canon(m.route.target) == SSH.Canon(to) then n = n + 1 end
		end
		return n
	end
	function net.Said(pattern)
		for _, s in ipairs(net.says) do if s:find(pattern) then return true end end
		return false
	end
	return net
end

local function Up(ep, name)
	for _, c in ipairs(ep:Connected()) do if c.name == name then return c end end
	return nil
end

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
		and #back.parts[2589] == 2 and back.parts[2589][2].n == 5, "...where each is kept")
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
	for i = before + 1, #net.sent do if net.sent[i].text:find("^1D") then d = d + 1 end end
	check(d == 0, "bags that didn't change aren't sent again")
	-- what's shared: limited by default (this character's mats and consumables), mats, consumables, all (alts, gold)
	check(SSH.Endpoint({}).mode == "limited", "limited is the default")
	B.me.items[1500] = 9 -- (a crafting mat here)
	B.mode = "limited"
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	check(A:Items()[1500] and not A:Items()[2589] and not A:Items()[2770], "limited: the crafting mat, not the rest")
	B.mode = "mats"
	B.me.items[400] = 1
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	check(A:Items()[1500] and not A:Items()[400], "mats: mats only")
	B.me.items[400] = nil
	B.me.alt, B.me.gold = { [2589] = 100, [3000] = 1 }, 5000000
	B.mode = "all"
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	local h = A:Items()[2589] and A:Items()[2589].holders[1]
	check(A:Items()[2589].total == 102 and A:Items()[3000] and h and #h.parts == 2, "all: an alt's bank too: " .. tostring(A:Items()[2589].total))
	local said = ns.Stored.ChatSummary({ holders = SSH.StoredHolders(A:Items()[2589].holders), total = 102 })
	check(said == " x102: Bobalt 100 (bank), Bob 2 (bags)", "...where it's kept, as @stored says it: " .. tostring(said))
	local gold = A:Gold()
	check(#gold == 1 and gold[1].gold == 5000000 and gold[1].who == "Bob", "all: gold")
	B.mode = "limited"
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	check(#A:Gold() == 0 and not A:Items()[3000], "back to limited: no gold, no alts")
	check(table.concat(SSH.Status(A), " "):find("Bob %(items: %d+, sharing: limited%)"), ".ssh says what each friend shares: "
		.. table.concat(SSH.Status(A), " / "))
	-- whatever the bags say, limited sends no gold
	B.me.gold = 777
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2)
	check(#A:Gold() == 0, "limited never sends gold")
	B.me.alt, B.me.gold, B.me.items[1500] = nil, nil, nil
	-- share consumables, then nothing
	B.mode = "consumables"
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	check(not A:Items()[2770] and not A:Items()[2589] and next(A:Items()) == nil, "share consumables: only those (none here)")
	B.me.items[400] = 3
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	check(A:Items()[400] and A:Items()[400].total == 3 and not A:Items()[2770], "...a consumable is")
	B.mode = "none"
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	check(next(A:Items()) == nil and Up(A, "Bob"), "share none: still connected, nothing seen")
	-- goodbye
	B.mode = "all"
	B:Share(B.friends["ann@realm"], true)
	net.Tick(2) -- (the send queue: one a second once its burst is spent)
	local changes = net.changed
	B:Off()
	net.Run()
	check(not Up(A, "Bob") and next(A:Items()) == nil and net.changed > changes, ".ssh off: goodbye, Ann drops what Bob sent")
	check(not B.key and next(B.peers) == nil, "...Bob forgets the key and everyone")
end

-- From here, a quick stand-in for HMAC (the harness's SHA-256 is plain arithmetic: a few handshakes would take the whole
-- instruction budget). The handshake above ran on the real one; crypto.lua checks it against the standard vectors. The
-- stand-in still differs for every key and message, so a wrong password or a relayed proof still fails.
local hmacWas = ns.Crypto.HMAC
ns.Crypto.HMAC = function(key, msg)
	local s = tostring(key) .. "\0" .. tostring(msg)
	local a, b = 7, 13
	for i = 1, #s do
		local c = s:byte(i)
		a = (a * 31 + c) % 2147483629
		b = (b * 37 + c * 3 + i) % 2147483587
	end
	local out = {}
	for i = 1, 4 do out[i] = string.char(a % 256, b % 256, math.floor(a / 256) % 256, math.floor(b / 256) % 256); a, b = math.floor(a / 7) + b, math.floor(b / 5) + a end
	return table.concat(out, "", 1, 4) .. table.concat(out, "", 1, 4)
end

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
	for _, m in ipairs(net.sent) do if m.text:find("^1K") then said = said + 1 end end
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
	A:Receive({ kind = "whisper", target = "Mal" }, "1D 1,1,1,1kh:z")
	check(next(A:Items()) == nil, "a stranger's items: ignored")
end

-- a claim that isn't its sender (Mal saying he's Bob): ignored
do
	local net = Net()
	local A = net.Add("Ann", { friends = { mal = "Mal", bob = "Bob" } })
	net.Add("Mal", { friends = { ann = "Ann" } })
	A:SetKey(GOOD)
	net.sent = {}
	A:Receive({ kind = "whisper", target = "Mal" }, "1H 00000000000000aa,bob@realm")
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
	B:Receive({ kind = "whisper", target = "Mal" }, "1H " .. nA .. "," .. mal)
	local challenge = net.sent[#net.sent].text
	local nB = challenge:match("^1C %x+,(%x+),")
	check(nB ~= nil, "Bob challenges Mal: " .. challenge)
	-- Mal hands Bob's challenge to Ann, as if it were his own; Ann proves to Mal
	net.inbox = {}
	A:Receive({ kind = "whisper", target = "Mal" }, "1C " .. nA .. "," .. nB .. "," .. mal)
	local proof = net.sent[#net.sent].text
	check(proof:find("^1A "), "Ann sends Mal her proof: " .. proof)
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
	A.key, B.key = GOOD, GOOD -- (keys set together)
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
	A:Receive({ kind = "guild", target = "Ann" }, "1H 00000000000000ab,ann@realm")
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
	for _, m in ipairs(B.queue) do if m.text:find("^1D") then pieces = pieces + 1 end end
	check(pieces > 0, "a big bag: the rest of its pieces wait in the queue: " .. pieces)
	B:Send({ kind = "whisper", target = "Ann" }, "1C 0000000000000001,0000000000000002,bob@realm")
	check(B.queue[1].text:find("^1C"), "a handshake goes before items still waiting: " .. B.queue[1].text)
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
	B:Send({ kind = "whisper", target = "Ann" }, "1P")
	check(#net.sent == before and #B.queue == 1, "the game says wait: kept in the queue")
	net.Tick(3)
	check(#B.queue == 0 and #net.sent == before + 1, "...sent a moment later")
	-- locked
	net.locked = true
	B:Send({ kind = "whisper", target = "Ann" }, "1P")
	net.Tick(3)
	check(#B.queue == 1, "chat locked: nothing sent")
	net.locked = false
	net.Tick(2)
	check(#B.queue == 0, "...sent once it isn't")
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
	A:Receive({ kind = "whisper", target = "Bob" }, "1P")
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

ns.Crypto.HMAC = hmacWas
SSH.KDF_ROUNDS = roundsWas
