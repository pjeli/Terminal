-- (Terminal: Share, an addon of its own: Terminal's namespace is its public table, _G.Terminal. Not loaded, nothing of
-- this runs: no prefix registered, no message read.)
local ns = _G.Terminal
if not ns or not ns.Crypto then return end
local L = ns.L

-- The share shell, .ssh (0.58.1): friends' Terminals talk to each other. Two friends who type the same password see each other's bags
-- in their searches ("linen cloth": what you carry, your alts, and Bob 20, Ann 15). docs/SHARE.md has the design.
--
-- Who's heard: a character on your friend list, a guild member, a Battle.net friend's character. Every other message
-- is ignored, unanswered. The sender is the server's word (a whisper's sender, the guild channel, a Battle.net game
-- account), never the message's.
-- The password: never sent, never kept. It's turned into a key (iterated SHA-256, a slice a frame), and each side proves
-- it holds the key with an HMAC over both nonces and both names (Crypto.lua). A wrong password gets no answer.
-- What friends send lives here, in memory, and nowhere else: gone on /reload, logout, goodbye, 30 minutes of silence,
-- or once they're no longer a friend or guild member. Nothing of it is ever in ns.db.
--
-- SSH.Endpoint(env) is the protocol, with the game reached only through `env` (the tests run two, talking to each
-- other); SSH.game is this client's, its env made of the game's calls (at the end of this file).

local SSH = {}
ns.Ssh = SSH

local C = ns.Crypto
local Lower, Str, Num, Safe = ns.Lower, ns.Str, ns.Num, ns.Safe
local floor, concat, sort = math.floor, table.concat, table.sort

SSH.PREFIX = "TermSSH"
SSH.V = "2"                -- the protocol's version, each message's first character (2: 0.58.16, delta updates,
                           -- 150-piece snapshots, a session in hellos; a friend on another is told to update)
SSH.SALT = "Terminal.ssh.1" -- (the key is the same for every pair who typed the same password)
SSH.KDF_ROUNDS = 2000      -- SHA-256s a password guess costs
SSH.KDF_SLICE = 50         -- of them a frame
SSH.MIN_PASSWORD = 8
SSH.MAC_HEX = 32           -- a proof's length (128 bits, hex)
SSH.CHUNK = 200            -- a data message's payload, at most
SSH.MAX_PIECES = 150       -- a snapshot's messages, at most (30000 characters: ~2500 items in two places each)
SSH.MAX_ITEMS = 3000
SSH.MAX_PLACES = 64        -- characters and banks a snapshot names
SSH.HANDSHAKE_TIMEOUT = 30 -- s for an answer
SSH.HELLO_GAP = 5          -- s between handshakes a friend can start
SSH.MAX_PENDING = 20       -- handshakes under way at once
SSH.SEND_GAP = 15          -- s between snapshots to a friend
SSH.PING_EVERY = 600       -- s: "still here"
SSH.IDLE_DROP = 1800       -- s of silence and a friend's items go
SSH.RECHECK = 60           -- s: are they still a friend?
SSH.WAIT_KEEP = 600        -- s a "wants to connect" is shown
SSH.NOANSWER_KEEP = 30     -- s a "no answer" is shown, then forgotten (0.58.11, the player; 0.58.15: sooner)
SSH.BURST, SSH.RATE = 6, 1 -- the send queue: this many at once, then one a second (the game allows 10, then 1/s)
SSH.RETRY_TICK = 60        -- s: who to say hello to again is looked at
SSH.RETRY_EVERY = 600      -- s: a friend who didn't answer is said hello to again after this, then twice it... (8x at most)

-- the game's answers to a send (Enum.SendAddonMessageResult)
local SENT, THROTTLED = 0, { [3] = true, [8] = true }
local LOCKDOWN = 11

----------------------------------------------------------------------
-- Names
----------------------------------------------------------------------

--- A character's name as both sides write it: lowercase, its words joined by "-" ("Plamen Warr", "Plamen-Warr": both
--- "plamen-warr"; "Bob-Some Realm": "bob-some-realm").
function SSH.Canon(s)
	s = Lower(tostring(s or "")):gsub("[%s%-]+", "-")
	return (s:gsub("^%-+", ""):gsub("%-+$", ""))
end
local Canon = SSH.Canon

--- Your name and realm as you say them to a friend: "plamen-warr@classicbetapvp" (the name with its surname).
function SSH.Claim(name, realm)
	if not name then return nil end
	return Canon(name) .. "@" .. Canon((tostring(realm or "")):gsub("[%s%-']", ""))
end

local function ValidClaim(s)
	return type(s) == "string" and #s <= 80 and s:find("^[^,%s@]+@[^,%s@]*$") ~= nil
end

--- Does a claim ("bob@realm") name the character the server says sent it ("Bob", "Bob-Realm", "Plamen Warr")?
--- `myRealm` (as SSH.Claim writes it): the server writes a sender on your realm without one, so "Bob" is bob@<yours>
--- only (review, 0.58.16: bob@<any realm>, another friend's record taken over).
function SSH.ClaimIs(claim, sender, myRealm)
	local name, realm = tostring(claim or ""):match("^(.-)@(.*)$")
	if not name or name == "" then return false end
	local s = Canon(sender)
	if s == name then return myRealm == nil or myRealm == "" or realm == myRealm end
	return s == name .. "-" .. realm
end

local HEX16 = "^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$"
local function ValidNonce(n) return type(n) == "string" and n:find(HEX16) ~= nil end

----------------------------------------------------------------------
-- Items as text: "id:count;id:count", both in base 36
----------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function To36(n)
	n = floor(n)
	if n <= 0 then return "0" end
	local out = {}
	while n > 0 do
		local d = n % 36
		out[#out + 1] = DIGITS:sub(d + 1, d + 1)
		n = floor(n / 36)
	end
	return string.reverse(concat(out))
end
SSH.To36 = To36

-- A snapshot: { places = { { who, where } }, items = { [itemID] = { [place] = count } }, gold = copper or nil }.
-- where: b bags, k bank, m mail, v void storage, w warband bank. As text, three parts split by "!" (never "|", chat's
-- escape character: 0.58.2's "|" never got through Battle.net, every friend showed 0 items):
--   places  "Bob/b,Bobalt/k,/w"
--   items   "id:place.count,place.count;id:..." (all base 36; place counted from 0)
--   gold    base 36, or empty
--   mode    what they share ("limited", "all"...), a fourth part (0.58.4: .ssh says it beside their name)
SSH.WHERE = { b = true, k = true, m = true, v = true, w = true }

--- A snapshot of one character's bags (`counts`: { [itemID] = count }).
function SSH.Simple(who, counts)
	local items = {}
	for id, n in pairs(counts or {}) do items[id] = { [1] = n } end
	return { places = { { who = who, where = "b" } }, items = items }
end

local function Clean(who) return (tostring(who or ""):gsub("[,;|/!]", "")) end

--- A snapshot in its parts, as text: { places = "Bob/b,...", entries = { [itemID] = "0.k,1.3" }, ids = { in order },
--- gold = base 36 or "", mode }. (Delta updates compare two of these: SSH.Delta.)
function SSH.EncodeParts(snap)
	snap = snap or {}
	local places = {}
	for i, pl in ipairs(snap.places or {}) do places[i] = Clean(pl.who) .. "/" .. tostring(pl.where) end
	local ids, entries = {}, {}
	for id, at in pairs(snap.items or {}) do
		if type(id) == "number" and id > 0 and type(at) == "table" then
			local where = {}
			for pi = 1, #places do
				local n = at[pi]
				if type(n) == "number" and n > 0 then where[#where + 1] = To36(pi - 1) .. "." .. To36(n) end
			end
			if #where > 0 then
				ids[#ids + 1] = id
				entries[id] = concat(where, ",")
			end
		end
	end
	sort(ids)
	return {
		places = concat(places, ","), entries = entries, ids = ids,
		gold = type(snap.gold) == "number" and snap.gold > 0 and To36(snap.gold) or "",
		mode = type(snap.mode) == "string" and snap.mode:match("^%a+$") or "",
	}
end

--- The parts as one text, the items in order (the same bags make the same text).
function SSH.Join(parts)
	local items = {}
	for i, id in ipairs(parts.ids) do items[i] = To36(id) .. ":" .. parts.entries[id] end
	return parts.places .. "!" .. concat(items, ";") .. "!" .. parts.gold .. "!" .. parts.mode
end

--- A snapshot as text (SSH.EncodeParts, SSH.Join).
function SSH.Encode(snap) return SSH.Join(SSH.EncodeParts(snap)) end

--- An item's places and counts ("0.k,1.3") read: its total and the same text with only what's good in it (a place
--- among `nPlaces`, a count over 0, at most 16), or 0 when nothing is.
local function ParseEntry(list, nPlaces)
	local total, good = 0, {}
	for pa, pn in list:gmatch("(%w+)%.(%w+)") do
		local pi, c = tonumber(pa, 36), tonumber(pn, 36)
		if pi and c and c > 0 and c < 2 ^ 24 and pi < nPlaces and #good < 16 then
			good[#good + 1] = pa .. "." .. pn
			total = total + c
		end
	end
	return total, concat(good, ",")
end

--- An item's places and counts as a list: { { place (1-based), n } }. (Kept as text on a friend: lists are made only
--- for a tooltip or a breakdown.)
function SSH.Parts(entry)
	local out = {}
	for pa, pn in tostring(entry or ""):gmatch("(%w+)%.(%w+)") do out[#out + 1] = { place = tonumber(pa, 36) + 1, n = tonumber(pn, 36) } end
	return out
end

--- The text back: { places = { { who, where } }, items = { [itemID] = total }, entries = { [itemID] = "0.k,1.3" },
--- gold, mode }. At most MAX_PLACES places and MAX_ITEMS items; anything else in it ignored.
function SSH.Decode(text)
	local out = { places = {}, items = {}, entries = {} }
	local placesText, itemsText, goldText, modeText = tostring(text or ""):match("^([^!]*)!([^!]*)!(%w*)!?(%a*)$")
	if not placesText then return out end
	for who, where in placesText:gmatch("([^,/]*)/(%a)") do
		if #out.places >= SSH.MAX_PLACES then break end
		out.places[#out.places + 1] = { who = who, where = SSH.WHERE[where] and where or "b" }
	end
	local n, nPlaces = 0, #out.places
	for a, list in itemsText:gmatch("(%w+):([%w%.,]+)") do
		local id = tonumber(a, 36)
		if id and id > 0 and id < 2 ^ 31 and not out.items[id] then
			local total, clean = ParseEntry(list, nPlaces)
			if total > 0 then
				n = n + 1
				if n > SSH.MAX_ITEMS then break end
				out.items[id], out.entries[id] = total, clean
			end
		end
	end
	local g = goldText ~= "" and tonumber(goldText, 36) or nil
	out.gold = g and g > 0 and g < 2 ^ 53 and g or nil
	out.mode = modeText ~= "" and modeText or nil
	if out.mode and out.mode ~= "all" then out.gold = nil end -- (gold is shared with all only)
	return out
end

-- Delta updates (0.58.16, the stress test: .share all to 10 friends with 500 items each took 300 messages, 5 minutes,
-- for every bag change): after a friend has a whole snapshot, a change sends only what changed, "1U ver,base,i,n,..."
-- with "id:0.k,1.3" for an item changed or new, "id:x" for one gone, and the gold: "changes!gold". The friend applies
-- it to the snapshot `base`; one they don't have (a piece lost, a /reload) is asked for whole again ("1R").

--- What changed from `old` to `new` (SSH.EncodeParts), as a delta's text; nil when nothing did.
function SSH.Delta(old, new)
	local out = {}
	for _, id in ipairs(new.ids) do
		local e = new.entries[id]
		if old.entries[id] ~= e then out[#out + 1] = To36(id) .. ":" .. e end
	end
	for id in pairs(old.entries) do
		if not new.entries[id] then out[#out + 1] = To36(id) .. ":x" end
	end
	if #out == 0 and old.gold == new.gold then return nil end
	return concat(out, ";") .. "!" .. new.gold
end

--- A delta applied to a friend's items (SSH.Delta's text). False when it doesn't read.
function SSH.Apply(f, text)
	local changes, goldText = tostring(text or ""):match("^([^!]*)!(%w*)$")
	if not changes then return false end
	local nPlaces = #(f.places or {})
	local n = f.n or 0
	for a, list in changes:gmatch("(%w+):([%w%.,]+)") do
		local id = tonumber(a, 36)
		if id and id > 0 and id < 2 ^ 31 then
			if list == "x" then
				if f.items[id] then n = n - 1 end
				f.items[id], f.entries[id] = nil, nil
			else
				local total, clean = ParseEntry(list, nPlaces)
				if total > 0 and (f.items[id] or n < SSH.MAX_ITEMS) then
					if not f.items[id] then n = n + 1 end
					f.items[id], f.entries[id] = total, clean
				end
			end
		end
	end
	local g = goldText ~= "" and tonumber(goldText, 36) or nil
	f.gold = (f.mode == "all" and g and g > 0 and g < 2 ^ 53) and g or nil
	f.n = n
	return true
end

----------------------------------------------------------------------
-- The key
----------------------------------------------------------------------

--- The key from a password, a slice at a time (`later(fn)` runs fn on a later frame; nil: all at once). done(key).
function SSH.Derive(password, done, later)
	local rounds, slice = SSH.KDF_ROUNDS, SSH.KDF_SLICE
	local k = C.SHA256(SSH.SALT .. "\0" .. password)
	local left = rounds
	local function step()
		local n = math.min(slice, left)
		for _ = 1, n do k = C.SHA256(k .. password) end
		left = left - n
		if left > 0 and later then later(step) return end
		if left > 0 then return step() end
		password = nil -- (not kept by this closure either)
		done(k)
	end
	step()
end

local function Mac(key, label, nA, nB, idA, idB)
	return C.Hex(C.HMAC(key, label .. "|" .. nA .. "|" .. nB .. "|" .. idA .. "|" .. idB)):sub(1, SSH.MAC_HEX)
end
SSH.Mac = Mac

----------------------------------------------------------------------
-- An endpoint: the protocol
----------------------------------------------------------------------
-- env:
--   now()                     seconds
--   claim()                   your claim ("plamen-warr@realm")
--   send(route, text)         0 sent, 3/8 throttled (try again), 11 chat locked, else failed
--   eligible(route, peer)     the sender's name to show when it's a friend, guild member or Battle.net friend's
--                             character (a guild channel message: a guild member who isn't you), else nil
--   matches(claim, route)     the claim names the route's sender
--   items(mode)               the snapshot you share (SSH.Encode's shape) for a mode: "all", "limited", "mats",
--                             "consumables"
--   locked()                  the game locks chat messaging now
--   changed()                 a friend's items changed (the list is made again)
--   say(text)                 a line in your chat window
--   nonce()                   16 hex characters, never the same twice
--   broadcast()               { routes } a hello goes to: the guild channel, friends, Battle.net friends' characters
-- route: { kind = "whisper", target = "Bob-Realm" } | { kind = "guild", target = sender } | { kind = "bn", id = n,
--   name = character, bnetID = account id }

local E = {}
E.__index = E

function SSH.Endpoint(env)
	return setmetatable({ env = env, peers = {}, friends = {}, waiting = {}, queue = {}, tokens = SSH.BURST, refillAt = 0,
		mode = "limited", outVer = 0, recheckAt = 0, hellos = {}, tried = {} }, E)
end

-- Two records (0.58.3; in game, 0.58.2: connected, "items: 0" on both sides):
--   peers[routeKey]  a way to reach someone and its handshake: whisper "w:name" (the name as the server writes it,
--                    your own realm dropped: "Bob-Realm", "Bob" and the guild channel's "Bob" are one way), or
--                    Battle.net "b:<game account>". A friend can have several up at once (a guildmate who's also on
--                    your friend list, a Battle.net friend).
--   friends[claim]   a friend, however they reach you: what they sent (items, gold), when they were last heard, and
--                    the one way you send to them (the newest proven).
-- Before, each way was its own friend: the items came in on one and .ssh counted another, then a second way's
-- connection dropped the first.

--- The way a route reaches someone, one key whatever way the server writes the name.
function E:Key(route)
	if route.kind == "bn" then return "b:" .. tostring(route.id) end
	local c = Canon(route.target)
	local realm = tostring(self:Claim() or ""):match("@(.*)$") or ""
	if realm ~= "" and #c > #realm + 1 and c:sub(-(#realm + 1)) == "-" .. realm then c = c:sub(1, -(#realm + 2)) end
	return "w:" .. c
end

--- Where to answer: a guild channel message is answered by whisper.
local function Reply(route)
	if route.kind == "guild" then return { kind = "whisper", target = route.target } end
	return route
end

function E:Now() return self.env.now() end
function E:Claim() return self.env.claim() end

--- Queue a message (sent at once when the queue lets it). `tag` lets a newer one take an older's place ("data:claim").
--- `f`: a friend's items (counted while they wait: f.queued; friends take turns). `peer`: a handshake's, its time
--- started when it's sent (review, 0.58.16: started when queued, thirty hellos behind each other timed out unsent).
function E:Send(route, text, tag, f, peer)
	if tag then
		for i = #self.queue, 1, -1 do
			if self.queue[i].tag == tag then self:Unqueue(i) end
		end
	end
	local m = { route = route, text = text, tag = tag, f = f, peer = peer }
	if f then f.queued = (f.queued or 0) + 1 end
	if peer then peer.queuedMsg = m end -- (not timed out while it waits)
	local at = #self.queue + 1
	if not tag then
		-- (a handshake goes before any friend's items still waiting: it has HANDSHAKE_TIMEOUT to be answered)
		for i, q in ipairs(self.queue) do
			if q.tag and q.tag:sub(1, 5) == "data:" then at = i break end
		end
	end
	table.insert(self.queue, at, m)
	self:Pump()
end

--- A message taken out of the queue (a friend's items no longer counted as waiting).
function E:Unqueue(i)
	local m = table.remove(self.queue, i)
	if m and m.f then
		m.f.queued = math.max(0, (m.f.queued or 1) - 1)
		if m.f.queued == 0 then m.f.doneAt = self:Now() end
	end
	return m
end

--- The next message out: in order, but of friends' items the friend with the fewest pieces left first (review,
--- 0.58.16: a small update waited behind another friend's hundred pieces, and went stale there). A big snapshot
--- still goes one friend at a time: each has theirs as soon as can be.
function E:NextOut()
	local q = self.queue
	if not q[1].f then return 1 end
	local best, fewest = 1, nil
	for i, m in ipairs(q) do
		local f = m.f
		if f and (fewest == nil or (f.queued or 0) < fewest) then
			best, fewest = i, f.queued or 0
			if fewest <= 1 then break end
		end
	end
	return best
end

function E:Pump()
	local now = self:Now()
	if now >= self.refillAt then
		local add = floor((now - self.refillAt) * SSH.RATE) + 1
		self.tokens = math.min(SSH.BURST, self.tokens + add)
		self.refillAt = now + 1 / SSH.RATE
	end
	while self.tokens > 0 and #self.queue > 0 do
		if self.env.locked() then return end -- (nothing goes while chat is locked: sent once it isn't)
		local i = self:NextOut()
		local m = self.queue[i]
		local res = self.env.send(m.route, m.text)
		self.results = self.results or {}
		self.results[tostring(res)] = (self.results[tostring(res)] or 0) + 1 -- (.ssh debug)
		if THROTTLED[res] or res == LOCKDOWN then
			self.tokens = 0 -- (the game said wait: tried again on a later second, where it was)
			return
		end
		self:Unqueue(i)
		local p = m.peer
		if p and p.queuedMsg == m then p.queuedMsg = nil end
		if p and (p.state == "hello" or p.state == "challenged" or p.state == "proved") then p.since = now end
		self.sent = (self.sent or 0) + 1
		self.tokens = self.tokens - 1
	end
end

--- A way's record by route, made when `make`.
function E:Peer(route, make)
	local k = self:Key(route)
	local p = self.peers[k]
	if not p and make then
		p = { key = k, route = Reply(route) }
		self.peers[k] = p
	end
	return p
end

--- Handshakes others started, under way (yours aren't counted: review, 0.58.16, twenty online friends who don't run
--- it filled the count with your own hellos, and a guildmate who does never connected).
local function Pending(self)
	local n = 0
	for _, p in pairs(self.peers) do
		if p.state == "challenged" then n = n + 1 end
	end
	return n
end

--- This session's mark: in hellos (a friend connected already hears a hello to others and lets it be) and snapshot
--- numbers (a /reload counts from 0 again: its pieces never taken for the last session's).
function E:Session()
	if not self.sess then self.sess = self.env.nonce():sub(1, 4) end
	return self.sess
end

--- Say hello: to everyone broadcast() names, or to one route.
function E:Hello(route)
	if not self.key then return false end
	local now = self:Now()
	if route and route.kind == "guild" then
		-- (the guild channel: one message, answered by each member who has the password; the nonce is the one they echo)
		local n = self.env.nonce()
		self.hellos[n], self.lastBroadcast = now, n
		self:Tried("guild", now)
		self:Send(route, SSH.V .. "H " .. n .. "," .. self:Claim() .. "," .. self:Session())
		return true
	end
	if route then
		local p = self:Peer(route, true)
		-- (connected already this way: what they send still lands while it's proven again)
		if p.state == "up" then p.wasUp = true end
		p.state, p.nA, p.nB, p.since = "hello", self.env.nonce(), nil, now
		self:Tried(p.key, now)
		self:Send(p.route, SSH.V .. "H " .. p.nA .. "," .. self:Claim() .. "," .. self:Session(), nil, nil, p)
		return true
	end
	local seen = {}
	for _, r in ipairs(self.env.broadcast() or {}) do
		if r.kind == "guild" then
			self:Hello(r)
		elseif not seen[self:Key(r)] then
			seen[self:Key(r)] = true
			self:Hello(r)
		end
	end
	return true
end

--- A hello said to a way (or the guild channel): when, and how many times without an answer.
function E:Tried(k, now)
	local t = self.tried[k]
	if not t then t = { n = 0 }; self.tried[k] = t end
	t.n, t.at = t.n + 1, now
end

--- Hello again, now and then, to who isn't connected (review, 0.58.16: a hello lost, heard in a dungeon while chat was
--- locked, or a friend list not read yet at login, and nobody ever tried again): after RETRY_EVERY, then twice that...
--- up to 8 times it; a friend never tried yet (online since), at once. Connected ones hear the guild's and let it be.
function E:Retry(now)
	for _, r in ipairs(self.env.broadcast() or {}) do
		local k = r.kind == "guild" and "guild" or self:Key(r)
		if r.kind == "guild" or not self.peers[k] then
			local t = self.tried[k]
			local wait = t and SSH.RETRY_EVERY * 2 ^ math.min(math.max(t.n - 1, 0), 3) or 0
			if not t or now - (t.at or 0) >= wait then self:Hello(r) end
		end
	end
end

--- A way proven: its friend connected (a new friend is said so and sent what you share; a friend already connected
--- another way is sent it this way from now on).
function E:Up(p)
	local now = self:Now()
	p.state, p.mismatch, p.upAt, p.wasUp = "up", nil, now, nil
	-- (a new handshake: what was being put together, and what their deltas build on, is from before it)
	p.pieces, p.got, p.inKey = {}, 0, nil
	self.tried[p.key] = nil
	local f = self.friends[p.claim]
	local new = f == nil
	if new then
		f = { claim = p.claim, items = {}, entries = {}, places = {}, n = 0 }
		self.friends[p.claim] = f
	end
	f.name, f.route, f.key, f.last, f.ver = p.name or f.name, p.route, p.key, now, nil
	self.waiting[p.key] = nil
	if new then self.env.say(L["Share: connected to %s"]:format(f.name or "?")) end
	f.sentText = nil -- (sent again whole: this way may be a new one to them)
	self:Share(f, true)
	if new then self.env.changed() end
end

local function HasData(f) return next(f.items) ~= nil or f.gold ~= nil end

--- A friend gone: every way to them forgotten.
function E:Drop(f, why)
	if not self.friends[f.claim] then return end
	self.friends[f.claim] = nil
	for k, p in pairs(self.peers) do
		if p.claim == f.claim then self.peers[k] = nil end
	end
	if why then self.env.say(L["Share: %s disconnected (%s)"]:format(f.name or "?", why)) end
	if HasData(f) then self.env.changed() end
end

--- What you share, as text (the same text as before: not sent again), and in its parts (SSH.EncodeParts: a delta is
--- made from two of them). "none": an empty text, no parts.
function E:Snapshot(fresh)
	if self.mode == "none" then return "", nil end
	-- (made once for every friend a change is sent to: E:Changed starts it again)
	if fresh or not self.snapText or self.snapMode ~= self.mode then
		local snap = self.env.items(self.mode) or {}
		snap.mode = self.mode
		if self.mode ~= "all" then snap.gold = nil end -- (gold only with all, whatever items() gave)
		local parts = SSH.EncodeParts(snap)
		self.snapText, self.snapParts, self.snapMode = SSH.Join(parts), parts, self.mode
	end
	return self.snapText, self.snapParts
end

--- Send a friend what you share, now (`force`) or when it's been SEND_GAP since the last.
function E:Share(f, force)
	if not (f and self.friends[f.claim]) then return end
	local now = self:Now()
	local tag = "data:" .. f.claim .. ":"
	if (f.queued or 0) > 0 then
		-- (one still going out: the next waits for its last piece, then goes as what changed since. Review, 0.58.16: it
		-- was dropped for a whole new one at the back of the queue, and a big snapshot to six friends never ended)
		if not force then f.owed = true return end
		for i = #self.queue, 1, -1 do
			local t = self.queue[i].tag
			if t and t:sub(1, #tag) == tag then self:Unqueue(i) end
		end
	end
	-- (SEND_GAP since the last went out whole)
	local last = math.max(f.sentAt or 0, f.doneAt or 0)
	if not force and f.sentAt and now - last < SSH.SEND_GAP then f.owed = true return end
	local text, parts = self:Snapshot(force)
	if not force and text == f.sentText then f.owed = nil return end
	-- only what changed, when they have the last one whole and it's the same places and mode: "2U ver,base,i,n,..."
	local letter, payload, base = "D", text, ""
	local old = f.sentParts
	if not force and old and parts and f.sentVer and old.places == parts.places and old.mode == parts.mode then
		local delta = SSH.Delta(old, parts)
		if delta and #delta < #text / 2 then letter, payload, base = "U", delta, f.sentVer .. "," end
	end
	self.outVer = self.outVer + 1
	local ver = self:Session() .. To36(self.outVer)
	f.sentText, f.sentParts, f.sentVer, f.sentAt, f.owed, f.pingAt = text, parts, ver, now, nil, now
	-- (pieces of CHUNK characters, put back together as they were; a snapshot past MAX_PIECES is cut at its last whole
	-- item, so it still reads, and the next goes whole)
	local max = SSH.CHUNK * SSH.MAX_PIECES
	if #payload > max then
		local cut = payload:sub(1, max - 1):match("^(.*);") or ""
		payload = cut .. "!!" .. (self.mode or "")
		f.sentParts = nil
	end
	local pieces = {}
	for at = 1, math.max(1, #payload), SSH.CHUNK do pieces[#pieces + 1] = payload:sub(at, at + SSH.CHUNK - 1) end
	f.sentPieces = #pieces
	for i, piece in ipairs(pieces) do
		self:Send(f.route, SSH.V .. letter .. " " .. ver .. "," .. base .. i .. "," .. #pieces .. "," .. piece, tag .. i, f)
	end
end

--- Your bags changed: each friend is sent them (within SEND_GAP).
function E:Changed()
	self.snapText = nil
	for _, f in pairs(self.friends) do self:Share(f) end
end

--- A message from the game: prefix already checked, `route` from the server's sender.
function E:Receive(route, text)
	if type(text) ~= "string" or #text > 255 then return end
	local v, letter, rest = text:match("^(%d)(%u) ?(.*)$")
	if not v then return end
	local p = self:Peer(route)
	if v ~= SSH.V then
		-- (another version's hello, from someone you'd hear: said once, so it isn't a silent "no answer")
		if letter ~= "H" then return end
		local name = self.env.eligible(route, p)
		local k = self:Key(route)
		self.otherV = self.otherV or {}
		if name and self.key and not self.otherV[k] then
			self.otherV[k] = true
			self.env.say(L["Share: %s runs another version of Terminal: Share; you both need the newest to connect"]:format(name))
		end
		return
	end
	local name = self.env.eligible(route, p)
	if not name then return end -- (not a friend, a guild member or a Battle.net friend's: ignored)
	local now = self:Now()
	self.heard = self.heard or {}
	self.heard[letter] = (self.heard[letter] or 0) + 1 -- (.ssh debug)
	if letter == "H" then
		local nA, claim, sess = rest:match("^(%x+),([^,]+),?(%x*)$")
		if not (ValidNonce(nA) and ValidClaim(claim) and self.env.matches(claim, route)) then return end
		if not self.key then
			self.waiting[self:Key(route)] = { name = name, at = now }
			return
		end
		-- (the guild channel's hello from a friend connected, the same session of theirs: one to others, let be. Review,
		-- 0.58.16: answered, it broke the connection until it was made again. A hello to you alone is always answered:
		-- they dropped you, whatever you think)
		if route.kind == "guild" and p and p.state == "up" and p.claim == claim and sess ~= "" and p.sess == sess then return end
		if p and p.lastHello and now - p.lastHello < SSH.HELLO_GAP then return end
		-- (both said hello at once: the smaller claim's hello goes on, the other side answers it)
		local mine = self:Claim()
		local outstanding = p and p.state == "hello"
		if not outstanding and route.kind == "guild" then
			for _, at in pairs(self.hellos) do if now - at < SSH.HANDSHAKE_TIMEOUT then outstanding = true end end
		end
		if outstanding and mine < claim then
			-- (they may have heard yours before they had a password: said again to them, the same nonce, so an answer
			-- already on its way still fits)
			if not (p and p.state == "hello") then
				p = self:Peer(route, true)
				p.state, p.nA, p.since = "hello", self.lastBroadcast, now
			end
			if p.nA and (not p.resent or now - p.resent >= SSH.HELLO_GAP) then
				p.resent = now
				self:Send(p.route, SSH.V .. "H " .. p.nA .. "," .. mine .. "," .. self:Session(), nil, nil, p)
			end
			return
		end
		if not (p and p.state == "up") and Pending(self) >= SSH.MAX_PENDING then return end
		p = self:Peer(route, true)
		if p.state == "up" and p.claim == claim then p.wasUp = true end -- (what they send lands meanwhile)
		p.lastHello, p.name, p.claim, p.sess = now, name, claim, sess
		p.state, p.nA, p.nB, p.since = "challenged", nA, self.env.nonce(), now
		self:Send(p.route, SSH.V .. "C " .. nA .. "," .. p.nB .. "," .. mine .. "," .. self:Session(), nil, nil, p)
	elseif letter == "C" then
		local nA, nB, claim, sess = rest:match("^(%x+),(%x+),([^,]+),?(%x*)$")
		if not (self.key and ValidNonce(nA) and ValidNonce(nB) and ValidClaim(claim) and self.env.matches(claim, route)) then return end
		if not (p and p.state == "hello" and p.nA == nA) then
			-- (an answer to the guild channel's hello)
			local at = self.hellos[nA]
			if not (at and now - at < SSH.HANDSHAKE_TIMEOUT) then return end
			if p and p.state == "proved" and p.nB == nB then return end -- (the same answer twice)
			p = self:Peer(route, true)
			-- (connected already: answered all the same, they're waiting on it. Review, 0.58.16: let be, their side
			-- gave up on the connection)
			if p.state == "up" and p.claim == claim then p.wasUp = true end
			p.state, p.nA = "hello", nA
		end
		p.nB, p.claim, p.name, p.state, p.since, p.sess = nB, claim, name, "proved", now, sess
		self:Send(p.route, SSH.V .. "A " .. nA .. "," .. nB .. "," .. Mac(self.key, "I", nA, nB, self:Claim(), claim), nil, nil, p)
	elseif letter == "A" then
		local nA, nB, mac = rest:match("^(%x+),(%x+),(%x+)$")
		if not (self.key and p and p.state == "challenged" and p.nA == nA and p.nB == nB) then return end
		if mac ~= Mac(self.key, "I", nA, nB, p.claim, self:Claim()) then
			p.state, p.mismatch, p.wasUp = "mismatch", now, nil
			self.env.say(L["Share: %s's password doesn't match yours"]:format(name))
			return -- (no answer: a wrong password learns nothing)
		end
		self:Send(p.route, SSH.V .. "K " .. nA .. "," .. nB .. "," .. Mac(self.key, "R", nA, nB, p.claim, self:Claim()))
		self:Up(p)
	elseif letter == "K" then
		local nA, nB, mac = rest:match("^(%x+),(%x+),(%x+)$")
		if not (self.key and p and p.state == "proved" and p.nA == nA and p.nB == nB) then return end
		if mac ~= Mac(self.key, "R", nA, nB, self:Claim(), p.claim) then
			p.state, p.mismatch, p.wasUp = "mismatch", now, nil
			self.env.say(L["Share: %s's password doesn't match yours"]:format(name))
			return
		end
		self:Up(p)
	elseif letter == "D" or letter == "U" then
		local f = p and (p.state == "up" or p.wasUp) and self.friends[p.claim]
		if not f then return self:Stranger(route, p) end
		local ver, base, i, n, payload
		if letter == "D" then
			ver, i, n, payload = rest:match("^(%w+),(%d+),(%d+),(.*)$")
		else
			ver, base, i, n, payload = rest:match("^(%w+),(%w+),(%d+),(%d+),(.*)$")
		end
		i, n = tonumber(i), tonumber(n)
		if not (ver and i and n and n >= 1 and n <= SSH.MAX_PIECES and i >= 1 and i <= n) then return end
		f.last = now
		-- (the pieces are put together per way: one snapshot comes one way. Each piece says the snapshot's kind, number,
		-- base and count, all of them its key: review, 0.58.16, a number heard again with another count read a piece
		-- that wasn't there, an error)
		local key = letter .. ver .. "," .. (base or "") .. "," .. n
		if p.inKey ~= key then p.inKey, p.pieces, p.got = key, {}, 0 end
		if not p.pieces[i] then p.got = p.got + 1 end
		p.pieces[i] = payload
		if p.got < n then return end
		local text = concat(p.pieces, "", 1, n)
		p.pieces, p.got, p.inKey = {}, 0, nil
		if letter == "D" then
			local d = SSH.Decode(text)
			local count = 0
			for _ in pairs(d.items) do count = count + 1 end
			f.items, f.entries, f.places, f.gold, f.mode, f.n = d.items, d.entries, d.places, d.gold, d.mode, count
		elseif f.ver ~= base or not SSH.Apply(f, text) then
			-- (built on a snapshot we don't have: asked for whole, now and then)
			if not f.askedAt or now - f.askedAt >= SSH.HELLO_GAP then
				f.askedAt = now
				self:Send(p.route, SSH.V .. "R")
			end
			return
		end
		f.ver, f.gotAt = ver, now
		f.rows = nil -- (their @shared rows made again: SSH.Rows)
		self.env.changed()
	elseif letter == "R" then
		-- (they're missing what our last delta built on: the next goes whole)
		local f = p and (p.state == "up" or p.wasUp) and self.friends[p.claim]
		if not f or (f.resentAt and now - f.resentAt < SSH.HELLO_GAP) then return end
		f.resentAt = now
		f.sentParts = nil
		self:Share(f, true)
	elseif letter == "P" then
		local f = p and (p.state == "up" or p.wasUp) and self.friends[p.claim]
		if not f then return self:Stranger(route, p) end
		f.last = now
	elseif letter == "B" then
		local f = p and p.claim and self.friends[p.claim]
		if f and (p.state == "up" or p.wasUp) then
			self:Drop(f)
			self.env.say(L["Share: %s disconnected"]:format(f.name or name))
		elseif p then
			self.peers[p.key] = nil
		end
		self.waiting[self:Key(route)] = nil
	end
end

--- Data or a ping from a friend who thinks you're connected and you don't (you /reloaded): hello again, now and then.
function E:Stranger(route, p)
	if not self.key then return end
	local now = self:Now()
	if p and p.since and now - p.since < SSH.HANDSHAKE_TIMEOUT then return end
	if p and p.strangerAt and now - p.strangerAt < 6 * SSH.HELLO_GAP then return end
	if not p and Pending(self) >= SSH.MAX_PENDING then return end
	self:Hello(route)
	self:Peer(route).strangerAt = now
end

--- Every second: the queue, timeouts, pings, snapshots owed, friends who stopped being friends.
function E:Tick()
	local now = self:Now()
	self:Pump()
	for n, at in pairs(self.hellos) do
		if now - at >= SSH.HANDSHAKE_TIMEOUT then self.hellos[n] = nil end
	end
	if self.key and now >= (self.retryAt or 0) then
		if self.retryAt then self:Retry(now) end
		self.retryAt = now + SSH.RETRY_TICK
	end
	local recheck = now >= self.recheckAt
	if recheck then self.recheckAt = now + SSH.RECHECK end
	for _, f in pairs(self.friends) do
		if now - (f.last or now) >= SSH.IDLE_DROP then
			self:Drop(f, L["no word for 30 minutes"])
		elseif recheck and not self.env.eligible(f.route, self.peers[f.key]) then
			self:Drop(f, L["no longer a friend or guild member"])
		else
			if f.owed then self:Share(f) end
			if now - (f.pingAt or now) >= SSH.PING_EVERY then
				f.pingAt = now
				self:Send(f.route, SSH.V .. "P", "ping:" .. f.claim)
			end
		end
	end
	for k, p in pairs(self.peers) do
		if p.state == "hello" or p.state == "challenged" or p.state == "proved" then
			if not p.queuedMsg and now - (p.since or now) >= SSH.HANDSHAKE_TIMEOUT then
				-- (connected before it: still so, nothing disproved it)
				if p.wasUp then p.state, p.wasUp = "up", nil
				elseif p.state == "challenged" then self.peers[k] = nil else p.state, p.noAnswer = "noanswer", now end
			end
		elseif p.state == "noanswer" and now - (p.noAnswer or now) >= SSH.NOANSWER_KEEP then
			self.peers[k] = nil -- (no answer for a while: not said any more; a hello from them starts again)
		end
	end
	for k, w in pairs(self.waiting) do
		if now - w.at >= SSH.WAIT_KEEP then self.waiting[k] = nil end
	end
end

--- A key to use (`.ssh password`): hello to everyone.
function E:SetKey(key)
	-- (another password: the friends connected with the old one are said goodbye to; the same one: they stay)
	if self.key and self.key ~= key then self:Off() end
	self.key = key
	for k, p in pairs(self.peers) do
		if p.state ~= "up" then self.peers[k] = nil end
	end
	self.tried, self.retryAt = {}, self:Now() + SSH.RETRY_TICK
	self:Hello()
end

--- `.ssh off`: goodbye to every friend, the key and everything they sent forgotten.
function E:Off()
	local had, byes = false, {}
	for _, f in pairs(self.friends) do
		byes[#byes + 1] = f.route
		if HasData(f) then had = true end
	end
	self.peers, self.friends, self.waiting, self.queue, self.hellos, self.key = {}, {}, {}, {}, {}, nil
	self.tried, self.retryAt = {}, nil
	-- (a password still being made from: never used. Review, 0.58.16: .share off while it was, and it was set after)
	self.keyGen, self.deriving = (self.keyGen or 0) + 1, nil
	-- (the goodbyes through the queue: what the game says wait to goes a second later, the ticker kept until they're
	-- all gone. Review, 0.58.16: sent straight, past ten friends or in chat lockdown some were lost, and those friends
	-- showed your bags half an hour on)
	for _, r in ipairs(byes) do self:Send(r, SSH.V .. "B") end
	if had then self.env.changed() end
end

--- Goodbye at logout (the queue won't get another second).
function E:Bye()
	for _, f in pairs(self.friends) do pcall(self.env.send, f.route, SSH.V .. "B") end
end

--- The friends connected now, by name: { { name, n, friend } }.
function E:Connected()
	local out = {}
	for _, f in pairs(self.friends) do out[#out + 1] = { name = f.name or "?", n = f.n or 0, friend = f } end
	sort(out, function(a, b) return a.name < b.name end)
	return out
end

--- What every connected friend has: { [itemID] = { total, holders = { { who, count, friend, parts } } } } (parts: where
--- they keep it, { { who, where, n } }).
function E:Items()
	local out = {}
	for _, f in pairs(self.friends) do
		for id, n in pairs(f.items) do
			local x = out[id]
			if not x then x = { total = 0, holders = {} }; out[id] = x end
			x.total = x.total + n
			local parts = {}
			for _, pt in ipairs(SSH.Parts(f.entries and f.entries[id])) do
				local pl = f.places and f.places[pt.place]
				if pl then parts[#parts + 1] = { who = pl.who, where = pl.where, n = pt.n } end
			end
			x.holders[#x.holders + 1] = { key = f.claim, who = f.name or "?", count = n, friend = f, parts = parts }
		end
	end
	return out
end

--- Friends' gold (shared with .ssh all): { { who, gold, friend } }.
function E:Gold()
	local out = {}
	for _, f in pairs(self.friends) do
		if f.gold then out[#out + 1] = { who = f.name or "?", gold = f.gold, friend = f } end
	end
	sort(out, function(a, b) return a.who < b.who end)
	return out
end

----------------------------------------------------------------------
-- Rows: @shared
----------------------------------------------------------------------

local nameWait = ns.NameWait("shared")
SSH.nameFrame = nameWait.frame


local WHERE_SAID = { b = L["bags"], k = L["bank"], m = L["mail"], v = L["void storage"], w = L["warband bank"] }

-- A friend's item looks as @stored's does (0.58.5, the player: "keep consistency"; .ssh all's one long line of every
-- character stretched the tooltip across the screen): each character a line, its total and where ("Plamen Pally  53
-- bags 18, bank 35"), the total, as @stored's tooltip, chat line and Shift+Enter say them (Stored.lua's own functions);
-- the game's item tooltip above.
local WHERE_WORD = { b = "bags", k = "bank", m = "mail", v = "void", w = "warband" }

--- The row's holders as @stored's are: { [key] = { key, who, where, owner, count } }, a character's places apart;
--- a friend who shares only their bags is one holder, by their name.
local function StoredHolders(friends)
	local out = {}
	for _, h in ipairs(friends) do
		local f = h.friend or {}
		local claim = tostring(f.claim or h.key or h.who)
		if #(h.parts or {}) == 0 then
			out[claim] = { key = claim, who = h.who, where = "bags", owner = claim, count = h.count }
		else
			for _, pt in ipairs(h.parts) do
				local warband = pt.where == "w" or pt.who == ""
				local who = warband and L["%s (warband)"]:format(h.who) or pt.who
				local owner = claim .. "|" .. (warband and "" or pt.who)
				local key = owner .. "|" .. pt.where
				local had = out[key]
				out[key] = { key = key, who = who, where = WHERE_WORD[pt.where] or "bags", owner = owner,
					count = (had and had.count or 0) + pt.n }
			end
		end
	end
	return out
end
SSH.StoredHolders = StoredHolders

local function Holders(e)
	local list = {}
	for _, h in ipairs(e.friends or {}) do list[#list + 1] = h end
	sort(list, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.who < b.who
	end)
	return list
end
SSH.Holders = Holders

--- The item's own tooltip (the game's, as any item row's), then who has how many and where, as @stored's.
local function Tooltip(e, t)
	local shown = e.itemID and pcall(t.SetHyperlink, t, ns.ItemLink(e.itemID) or ("item:" .. e.itemID))
	if not shown then
		local c = e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
		t:SetText(e.name, c and c.r or 1, c and c.g or 1, c and c.b or 1)
	end
	t:AddLine(" ")
	t:AddLine(L["In your friends' bags now (.share)"], 1, 0.82, 0)
	ns.Stored.GroupLines(e, t)
	if e.others then t:AddLine(L["Other friends: %s"]:format(e.others), 0.6, 0.6, 0.6, true) end
	t:AddLine(" ")
	local top = Holders(e)[1]
	ns.KeyHints(t, L["Enter: whisper %s"]:format(top and top.who or "?") .. "    " .. L["Shift+Enter: show in chat"], 0.6, 0.6, 0.6)
end

--- The friend with the most, as a row Social.lua's whisper takes.
local function Top(e)
	local h = Holders(e)[1]
	if not h then return nil end
	local r = h.friend and h.friend.route or {}
	if r.kind == "bn" then return { name = h.who, bnetID = r.bnetID, whisperTo = r.name } end
	return { name = h.who, whisperTo = r.target }
end
SSH.Top = Top

local function Whisper(e)
	local t = Top(e)
	if t and ns.Social then ns.Social.Whisper(t) end
end

--- Shift+Enter, and what follows the link sent to chat: @stored's ("Linen Cloth: 230 in all", " x230: Plamen Pally 53
--- (bags 18, bank 35), ...").
local function Breakdown(e) return ns.Stored.Breakdown(e) end
SSH.Breakdown = Breakdown
local function ChatSummary(e, room) return ns.Stored.ChatSummary(e, room) end

local WHISPER = { macro = function(e)
	local t = Top(e)
	return t and ns.Social and ns.Social.WhisperMacro(t) or nil
end }

-- One row an item a friend (0.58.6, the player: "group and sort by Owner (Cad Man vs Cherry Tusks)"): an item two
-- friends carry is two rows, "Linen Cloth x20 · Cad Man" and "x15 · Cherry Tusks", each with its owner (Pipes.lua's
-- owner field: the bar's Group and Sort, sort:owner, | group by owner). The tooltip says who else has it.
--
-- (0.58.16, the stress test: tests/stress.py) Rows are compact (ns:CompactMeta): only what a search reads first is on
-- the row (its name, owner, count); the rest (link, quality, holders, detail...) is worked out when asked and kept.
-- Each friend's rows are kept on the friend and made again only when what they sent changed (or an item's name came
-- in): a friend's update no longer remakes every other friend's rows. 10 friends x 500 items: 96 ms and ~10 MB a
-- remake, before.

local ROW_PROTO = {
	tooltip = Tooltip, secure = WHISPER, isOpen = ns.Never, activate = Whisper,
	secondary = function(e) ns:Output(Breakdown(e)) end,
	shareExtra = ChatSummary,
}
local function Keep(t, k, v) if v ~= nil then rawset(t, k, v) end return v end
local ROW_LAZY = {
	quality = function(t) return Keep(t, "quality", ns.ItemQuality(t.itemID)) end,
	color = function(t) return ns.QualityHex(t.quality) end,
	icon = function(t) return Keep(t, "icon", C_Item and C_Item.GetItemIconByID and Safe(C_Item.GetItemIconByID, t.itemID)) end,
	link = function(t)
		local l = ns.ItemLink(t.itemID)
		if l then rawset(t, "link", l) return l end
		return "item:" .. t.itemID
	end,
	detail = function(t) return "x" .. t.total .. ns.DETAIL_SEP .. t.owner end,
	-- (the friend as a holder: who, how many, where they keep it)
	friends = function(t)
		local f = t.friend
		local parts = {}
		for _, pt in ipairs(SSH.Parts(f.entries and f.entries[t.itemID])) do
			local pl = f.places and f.places[pt.place]
			if pl then parts[#parts + 1] = { who = pl.who, where = pl.where, n = pt.n } end
		end
		return Keep(t, "friends", { { key = f.claim, who = f.name or "?", count = t.total, friend = f, parts = parts } })
	end,
	holders = function(t) return Keep(t, "holders", StoredHolders(t.friends)) end,
	-- (who else has it: read when its tooltip is drawn)
	others = function(t)
		local out = {}
		for _, o in pairs(SSH.game and SSH.game.friends or {}) do
			local n = o ~= t.friend and o.items[t.itemID]
			if n then out[#out + 1] = (o.name or "?") .. " " .. n end
		end
		sort(out)
		return #out > 0 and concat(out, ", ") or nil
	end,
}
local rowMeta, lowerName = nil, {}

--- A friend's rows: made when they sent something new, or names were still to come.
local function FriendRows(f, p)
	if f.rows and not f.rowsMissing then return f.rows end
	rowMeta = rowMeta or ns:CompactMeta(p, ROW_PROTO, ROW_LAZY)
	local rows, missing = {}, false
	local who = f.name or "?"
	local text = "shared friend " .. Lower(who)
	local claim = tostring(f.claim)
	for id, n in pairs(f.items) do
		local name = nameWait.Name(id)
		if name then
			local ln = lowerName[id]
			if not ln then ln = Lower(name); lowerName[id] = ln end
			rows[#rows + 1] = setmetatable({ _compact = true, key = id .. ":" .. claim, itemID = id, name = name, _lname = ln,
				_ltext = text, owner = who, total = n, friend = f }, rowMeta)
		else
			missing = true
		end
	end
	f.rows, f.rowsMissing = rows, missing or nil
	return rows
end

function SSH.Rows(ep, p)
	p = p or ns.providers.shared
	local out = {}
	for _, f in pairs(ep.friends) do
		for _, row in ipairs(FriendRows(f, p)) do out[#out + 1] = row end
	end
	-- friends' gold (.share all): a row each, "gold" finds them
	for _, g in ipairs(ep:Gold()) do
		local said = L["%s's gold"]:format(g.who)
		local holder = { who = g.who, count = 1, friend = g.friend } -- (Enter whispers them)
		out[#out + 1] = {
			key = "gold:" .. tostring(g.friend.claim), name = said, icon = "Interface\\Icons\\INV_Misc_Coin_01", owner = g.who,
			detail = ns.Money(g.gold), text = "shared friend gold money " .. g.who, money = g.gold,
			friends = { holder }, total = 1,
			tooltip = function(_, t)
				t:SetText(said, 1, 0.82, 0)
				t:AddLine(ns.Money(g.gold), 1, 1, 1)
				t:AddLine(L["All their characters' gold, as they share it (.share all)"], 0.6, 0.6, 0.6, true)
				ns.KeyHints(t, L["Enter: whisper %s"]:format(g.who), 0.6, 0.6, 0.6)
			end,
			secure = WHISPER, isOpen = ns.Never,
			activate = Whisper,
			secondary = function() ns:Output({ said .. ": " .. ns.Money(g.gold) }) end,
			shareLink = function() return said .. ": " .. ns.Money(g.gold, true) end,
		}
	end
	return out
end

function SSH.Busy()
	local n = nameWait.count
	if n > 0 then return L["Loading %d item names from the server for your friends' bags"]:format(n) end
end

ns:RegisterProvider("shared", {
	label = L["Shared"], -- (0.58.12, the player: "Rename @friendsbags to @shared")
	color = "ff7fd4ff",
	aliases = { "shared", "ssh" },
	busy = function() return SSH.Busy() end,
	hintLabel = L["your friends' bags"],
	collect = function(p) return SSH.game and SSH.Rows(SSH.game, p) or {} end,
})

----------------------------------------------------------------------
-- .ssh
----------------------------------------------------------------------

-- What you share (the player's call, 0.58.2): limited by default
local MODES = { all = true, limited = true, mats = true, consumables = true, none = true }
local MODE_ORDER = { "limited", "all", "mats", "consumables", "none" }
local MODE_SAID = {
	all = L["your gold, and everything on all your characters and in your banks"],
	limited = L["this character's crafting mats and consumables"],
	mats = L["this character's crafting mats"],
	consumables = L["this character's consumables"],
	none = L["nothing"],
}
SSH.MODES = MODES

--- What you share, set: friends connected are sent it now.
function SSH.SetMode(ep, m)
	if not MODES[m] then
		return { L["Share: what to share: .share limited (the default), .share all, .share mats, .share consumables or .share none"] }
	end
	ep.mode = m
	if ns.db then ns.db.sshShare = m end
	for _, f in pairs(ep.friends) do ep:Share(f, true) end
	return { L["Share: sharing %s"]:format(MODE_SAID[m]) }
end

--- Who isn't connected yet, said a line each: connecting, no answer, password doesn't match, wants to connect.
function SSH.Others(ep)
	local other = {}
	for _, p in pairs(ep.peers) do
		if p.claim and ep.friends[p.claim] then
			-- (a friend connected another way: said once, above)
		elseif p.state == "mismatch" then other[#other + 1] = L["%s: password doesn't match"]:format(p.name or "?")
		elseif p.state == "noanswer" then other[#other + 1] = L["%s: no answer"]:format(p.name or p.route.target or p.route.name or "?")
		elseif p.state ~= "up" then other[#other + 1] = L["%s: connecting"]:format(p.name or p.route.target or p.route.name or "?") end
	end
	for _, w in pairs(ep.waiting) do other[#other + 1] = L["%s wants to connect: type .share password"]:format(w.name) end
	sort(other)
	return other
end

function SSH.Status(ep)
	ep = ep or SSH.game
	local lines = {}
	if not ep then return { L["Share: not available"] } end
	if ep.deriving then
		lines[1] = L["Share: setting the password..."]
	elseif not ep.key then
		lines[1] = L["Share: no password yet. Type .share password <words> (8 characters or more), the same one as your friends"]
	else
		lines[1] = L["Share: password set (remembered: .share off forgets it); sharing %s"]:format(MODE_SAID[ep.mode] or ep.mode)
	end
	local up = ep:Connected()
	if #up > 0 then
		local parts = {}
		for i, c in ipairs(up) do
			local m = c.friend and c.friend.mode
			parts[i] = m and L["%s (items: %d, sharing: %s)"]:format(c.name, c.n, m) or L["%s (items: %d)"]:format(c.name, c.n)
		end
		lines[#lines + 1] = "  " .. L["Connected:"] .. " " .. concat(parts, ", ")
	elseif ep.key then
		lines[#lines + 1] = "  " .. L["Connected: nobody yet"]
	end
	for _, s in ipairs(SSH.Others(ep)) do lines[#lines + 1] = "  " .. s end
	return lines
end

--- `.ssh debug`: what was sent and heard, each way and each friend (to find why items don't arrive).
function SSH.Debug(ep)
	ep = ep or SSH.game
	local lines = {}
	local function counts(t)
		local out = {}
		for k, n in pairs(t or {}) do out[#out + 1] = k .. "=" .. n end
		sort(out)
		return #out > 0 and concat(out, " ") or "-"
	end
	local now = ep:Now()
	lines[1] = ("ssh debug: mode %s, key %s, queue %d, sent (game's answers) %s, heard %s"):format(tostring(ep.mode),
		ep.key and "set" or "none", #ep.queue, counts(ep.results), counts(ep.heard))
	local keys = {}
	for k in pairs(ep.peers) do keys[#keys + 1] = k end
	sort(keys)
	for _, k in ipairs(keys) do
		local p = ep.peers[k]
		lines[#lines + 1] = ("  way %s: %s %s%s"):format(k, tostring(p.state), tostring(p.claim or "?"),
			p.got and p.got > 0 and (" (pieces %d)"):format(p.got) or "")
	end
	for _, c in ipairs(ep:Connected()) do
		local f = c.friend
		local text = f.sentText or ""
		lines[#lines + 1] = ("  friend %s (%s): items %d%s, heard %ds ago, last data %s; sent to them by %s: %d characters"):format(c.name, tostring(f.mode or "?"), c.n,
			f.gold and (", gold " .. f.gold) or "", floor(now - (f.last or now)), f.gotAt and (floor(now - f.gotAt) .. "s ago") or "never",
			tostring(f.key), #text)
	end
	local mine = ep:Snapshot(true)
	lines[#lines + 1] = ("  you share: %d characters: %s"):format(#mine, mine:sub(1, 120))
	return lines
end

--- `.ssh password <words>`: the key, made over a few frames, then hello to everyone.
function SSH.SetPassword(ep, words, later, done)
	words = tostring(words or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #words < SSH.MIN_PASSWORD then
		return { L["Share: the password needs %d characters or more"]:format(SSH.MIN_PASSWORD) }
	end
	ep.keyGen = (ep.keyGen or 0) + 1
	local gen = ep.keyGen
	ep.deriving = true
	SSH.Derive(words, function(key)
		if ep.keyGen ~= gen then return end -- (.share off, or another password, meanwhile)
		ep.deriving = nil
		ep:SetKey(key)
		SSH.Remember(key)
		SSH.Badge()
		ep.env.say(L["Share: password set; saying hello to your friends and guild"])
		if done then done() end
	end, later)
	return { L["Share: setting the password (remembered as a key made from it, never as typed; .share off forgets it)"] }
end

-- The password remembered (0.58.6, the player: "saved and re-used automatically on login"): the key made from it, in
-- Terminal: Share's own saved variables (TerminalShareDB.key, hex), never the password as typed. At login it's used a
-- few seconds in (friends and guild read first) and everyone is said hello to. .ssh off forgets it.
-- (Anyone with your WTF folder could connect as you with it: the same as knowing the password, for this.)
SSH.LOGIN_WAIT = 5

local function Saved()
	if type(_G.TerminalShareDB) ~= "table" then _G.TerminalShareDB = {} end
	return _G.TerminalShareDB
end
function SSH.Remember(key) Saved().key = key and C.Hex(key) or nil end

local function Unhex(h) return (h:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end)) end

--- The remembered key, back in use (at login): true when there was one.
function SSH.Restore(ep)
	ep = ep or SSH.game
	local hex = Saved().key
	if type(hex) ~= "string" or not hex:find("^%x+$") or #hex ~= 64 then return false end
	if ep.key then return true end
	SSH.StartTicker()
	local ask = C_GuildInfo and C_GuildInfo.GuildRoster or _G.GuildRoster
	if ask then Safe(ask) end
	C_Timer.After(SSH.LOGIN_WAIT, function()
		if ep.key or Saved().key ~= hex then return end -- (a password typed meanwhile, or .ssh off)
		ep:SetKey(Unhex(hex))
		SSH.Badge()
		ep.env.say(L["Share: using your saved password; saying hello to your friends and guild"])
	end)
	return true
end

local function Later(fn) C_Timer.After(0, fn) end

-- (.share, 0.58.14, the player: ".ssh ... a fun throwback to secure shell but its probably confusing for WoW players":
-- .ssh is its alias)
ns:RegisterCommand("share", {
	aliases = { "ssh" },
	desc = L["The share shell: your bags in the searches of friends who run Terminal: Share. .share password <words>; what you share: .share limited, all, mats, consumables or none; .share off"],
	complete = function()
		local out = {
			{ "password", L["the password you and your friends agree on (remembered: .share off forgets it)"] },
			{ "connect", L["say hello to one friend again: .share connect <name>"] },
		}
		for _, m in ipairs(MODE_ORDER) do out[#out + 1] = { m, L["share %s"]:format(MODE_SAID[m]) } end
		out[#out + 1] = { "off", L["forget the password, say goodbye, drop what friends sent"] }
		return out
	end,
	run = function(args)
		local ep = SSH.game
		if not ep then return { L["Share: not available"] } end
		local word, rest = tostring(args or ""):match("^%s*(%S*)%s*(.-)%s*$")
		word = Lower(word)
		if word == "" or word == "status" then return SSH.Status(ep) end
		if word == "debug" then return SSH.Debug(ep) end
		if word == "password" or word == "pass" or word == "pw" then
			SSH.StartTicker()
			-- (the guild's members, read before their answers come: C_GuildInfo.GuildRoster)
			local ask = C_GuildInfo and C_GuildInfo.GuildRoster or _G.GuildRoster
			if ask then Safe(ask) end
			return SSH.SetPassword(ep, rest, Later)
		end
		if word == "off" then
			ep:Off()
			SSH.Remember(nil)
			if #ep.queue == 0 then SSH.StopTicker() end -- (else once the goodbyes are gone)
			SSH.Badge()
			return { L["Share: off. The password is forgotten and your friends' items are gone"] }
		end
		-- (.ssh all, .ssh mats...; .ssh share all too)
		if MODES[word] then return SSH.SetMode(ep, word) end
		if word == "share" then return SSH.SetMode(ep, Lower(rest)) end
		if word == "connect" then
			if not ep.key then return { L["Share: set the password first: .share password <words>"] } end
			if rest == "" then ep:Hello() return { L["Share: saying hello to your friends and guild"] } end
			local route = SSH.RouteFor(rest)
			if not route then return { L["Share: %s isn't on your friend list, in your guild or a Battle.net friend's character"]:format(rest) } end
			ep:Hello(route)
			return { L["Share: saying hello to %s"]:format(rest) }
		end
		return SSH.Status(ep)
	end,
})

----------------------------------------------------------------------
-- The badge at the end of the prompt (0.58.6, the player: "a little wifi icon at the very end of the Terminal prompt
-- box ... who you are connected to and how much they are sharing"): shown while the share shell is on (a password
-- set); the theme's accent with a friend connected, grey with none. Terminal's UI.AddBadge (Prompt.lua).
----------------------------------------------------------------------

-- A wifi sign (0.58.7, the player: "make the wifi icon look a little better"): a dot and three arcs over it, each arc a
-- line of small dots close enough to read as one stroke. The theme's accent with a friend connected, the arcs lit one
-- by one while connecting, grey with nobody.
local ARCS = { 4.5, 8.5, 12.5 }
local function DrawWifi(f)
	f.arcs = {}
	local cx, cy = 0, 5 -- (from the frame's bottom middle: the sign centred in its square, level with the text)
	f.center = f:CreateTexture(nil, "OVERLAY")
	f.center:SetSize(4, 4)
	f.center:SetPoint("CENTER", f, "BOTTOM", cx, cy)
	for k, r in ipairs(ARCS) do
		local arc = {}
		local n = math.ceil(r * math.pi / 2 / 1.1) + 1 -- (a dot every ~1.1 px along the arc)
		for i = 1, n do
			local a = math.pi / 4 + (i - 1) / (n - 1) * math.pi / 2
			local d = f:CreateTexture(nil, "OVERLAY")
			d:SetSize(2.2, 2.2)
			d:SetPoint("CENTER", f, "BOTTOM", cx + math.cos(a) * r, cy + math.sin(a) * r)
			arc[#arc + 1] = d
		end
		f.arcs[k] = arc
	end
end

local function Paint(list, r, g, b, a)
	for _, d in ipairs(list) do d:SetColorTexture(r, g, b, a) end
end

--- A handshake under way (or the key still being made): the sign's arcs light in turn.
function SSH.Connecting(ep)
	if ep.deriving then return true end
	for _, p in pairs(ep.peers) do
		if (p.state == "hello" or p.state == "challenged" or p.state == "proved") and not (p.claim and ep.friends[p.claim]) then return true end
	end
	return false
end

-- (0.58.15, the player: keep the connecting animation, "but it should just red or something if we haven't connected
-- to anyone") connected: the accent; connecting: its arcs light in turn; nobody, nothing under way: red.
local RED = { 0.9, 0.25, 0.2 }
local function BadgeColour(f)
	local ep = SSH.game
	if not (ep and f.arcs) then return end
	local ar, ag, ab = 0.4, 0.8, 1
	if ns.Theme and ns.Theme.RGB and ns.Theme.Get then ar, ag, ab = ns.Theme.RGB(ns.Theme.Get().accent) end
	local up = #ep:Connected()
	if up == 0 and not SSH.Connecting(ep) then
		f.state = "none"
		f.center:SetColorTexture(RED[1], RED[2], RED[3], 1)
		for _, arc in ipairs(f.arcs) do Paint(arc, RED[1], RED[2], RED[3], 1) end
		return
	end
	local lit = 3
	if up == 0 then lit = 1 + math.floor(GetTime() * 2) % 3 end -- (connecting)
	f.state = up > 0 and "up" or "connecting"
	f.center:SetColorTexture(ar, ag, ab, 1)
	for k, arc in ipairs(f.arcs) do
		if k <= lit then Paint(arc, ar, ag, ab, 1) else Paint(arc, 0.5, 0.5, 0.5, 0.55) end
	end
end
SSH.BadgeColour = BadgeColour

local function Ago(s)
	s = math.max(0, math.floor(s or 0))
	if s < 60 then return L["%ds ago"]:format(s) end
	return L["%dm ago"]:format(math.floor(s / 60))
end

--- The pop-out (0.58.9, the player: "simplify the tooltip a bit"): a line for you, a line a friend ("Cad Mán  39 items
--- · all · Battle.net"), when they were last heard only once it's been a while, then who's still connecting.
function SSH.BadgeTip(t)
	local ep = SSH.game
	local now = ep:Now()
	local up = ep:Connected()
	local function Items(n) return n == 1 and L["1 item"] or L["%d items"]:format(n) end
	local _, mine = ep:Snapshot()
	local n = mine and #mine.ids or 0
	t:AddDoubleLine(L["Sharing"], L["you: %s"]:format(Items(n) .. ns.DETAIL_SEP .. ep.mode), 1, 1, 1, 0.6, 0.6, 0.6)
	for _, c in ipairs(up) do
		local f = c.friend
		local how = { Items(c.n) }
		if f.mode then how[#how + 1] = f.mode end
		if f.gold then how[#how + 1] = ns.Money(f.gold) end
		how[#how + 1] = f.route and f.route.kind == "bn" and "Battle.net" or L["whisper"]
		local quiet = now - (f.last or now)
		if quiet >= 60 then how[#how + 1] = Ago(quiet) end
		t:AddDoubleLine(c.name, concat(how, ns.DETAIL_SEP), 1, 0.82, 0, 0.85, 0.85, 0.85)
	end
	if #up == 0 then t:AddLine(L["Connected: nobody yet"], 0.6, 0.6, 0.6) end
	for _, line in ipairs(SSH.Others(ep)) do t:AddLine(line, 0.55, 0.55, 0.55) end
	t:AddLine(" ")
	t:AddLine(L[".share off to disconnect"], 0.45, 0.45, 0.45)
end

--- The badge placed again (a friend connected or gone, their items in, the password set or forgotten); `wake`: seen
--- at full strength again (connected, disconnected).
function SSH.Badge(wake)
	local U = ns.UI
	if U and U.PlaceBadges and U.frame then U:PlaceBadges() end
	if wake and U and U.WakeBadge then U.WakeBadge("share") end
end

if ns.UI and ns.UI.AddBadge then
	ns.UI.AddBadge({
		id = "share",
		fade = 6, -- (seconds at full strength, then a faint mark until pointed at; 0.58.9, the player)
		draw = DrawWifi,
		shown = function() local ep = SSH.game return ep ~= nil and (ep.key ~= nil or ep.deriving == true) end,
		refresh = BadgeColour,
		tooltip = function(t) SSH.BadgeTip(t) end,
	})
end

----------------------------------------------------------------------
-- This client: the game's calls
----------------------------------------------------------------------

local function MyRealm()
	local r = Str(Safe(_G.GetNormalizedRealmName)) or Str(Safe(_G.GetRealmName)) or ""
	return Canon((r:gsub("[%s%-']", "")))
end

local function MyForms()
	local me = ns.CharacterName and ns.CharacterName()
	if not me then return {} end
	local c = Canon(me)
	return { [c] = true, [c .. "-" .. MyRealm()] = true }
end

local function Ambig(name)
	if type(_G.Ambiguate) == "function" then
		local s = Str(Safe(_G.Ambiguate, name, "none"))
		if s then return s end
	end
	return name
end

-- friends, guild members and Battle.net friends' characters, read at most every 10 s
local people, peopleAt = nil, -100
local function People()
	local now = GetTime()
	if people and now - peopleAt < 10 then return people end
	local realm = MyRealm()
	local names, bn, guild = {}, {}, {}
	local function add(set, name, shown)
		local c = Canon(name)
		if c == "" then return end
		set[c] = shown
		set[c .. "-" .. realm] = shown
	end
	local FL = C_FriendList
	for i = 1, (FL and FL.GetNumFriends and Num(Safe(FL.GetNumFriends)) or 0) do
		local f = Safe(FL.GetFriendInfoByIndex, i)
		local n = type(f) == "table" and Str(f.name)
		if n then add(names, n, Ambig(n)) end
	end
	for i = 1, (_G.IsInGuild and Safe(_G.IsInGuild) and Num(Safe(_G.GetNumGuildMembers)) or 0) do
		local n = Str((Safe(_G.GetGuildRosterInfo, i)))
		if n then add(names, n, Ambig(n)); add(guild, n, true) end
	end
	local B = C_BattleNet
	local wow = _G.BNET_CLIENT_WOW or "WoW"
	for i = 1, (Num(Safe(_G.BNGetNumFriends)) or 0) do
		local a = B and B.GetFriendAccountInfo and Safe(B.GetFriendAccountInfo, i)
		if type(a) == "table" then
			local accounts = {}
			local nGames = B.GetFriendNumGameAccounts and Num(Safe(B.GetFriendNumGameAccounts, i)) or 0
			for j = 1, nGames do accounts[#accounts + 1] = Safe(B.GetFriendGameAccountInfo, i, j) end
			if nGames == 0 then accounts[1] = a.gameAccountInfo end
			for _, g in ipairs(accounts) do
				local id, char = type(g) == "table" and Num(g.gameAccountID), type(g) == "table" and Str(g.characterName)
				if id and char and g.clientProgram == wow and (not g.wowProjectID or not _G.WOW_PROJECT_ID or g.wowProjectID == _G.WOW_PROJECT_ID) then
					local realmName = Str(g.realmName)
					bn[id] = { name = char, realm = realmName, bnetID = Num(a.bnetAccountID) }
					local full = realmName and (char .. "-" .. realmName:gsub("[%s']", "")) or char
					add(names, char, char)
					add(names, full, char)
				end
			end
		end
	end
	people, peopleAt = { names = names, bn = bn, guild = guild, guildN = Num(Safe(_G.GetNumGuildMembers)) or 0 }, now
	return people
end
SSH.People = People
function SSH.Forget() people = nil end

local function Eligible(route, peer)
	local P = People()
	if route.kind == "bn" then
		local b = P.bn[route.id]
		if not b then return nil end
		route.name, route.bnetID = b.name, b.bnetID
		return b.name
	end
	local sender = Str(route.target)
	if not sender then return nil end
	local c = Canon(sender)
	local mine = MyForms()
	if mine[c] then return nil end -- (your own guild message, heard back)
	if route.kind == "guild" then return Ambig(sender) end -- (the guild channel: only members are on it)
	local realm = MyRealm()
	local shown = P.names[c] or P.names[c .. "-" .. realm]
	if shown then return shown end
	-- (heard first on the guild channel, before the roster was read: still one of them while the roster says nothing)
	if peer and peer.viaGuild and P.guildN == 0 then return peer.name or Ambig(sender) end
	return nil
end

local function Matches(claim, route)
	if route.kind == "bn" then
		local b = People().bn[route.id]
		if not b then return false end
		local name, realm = claim:match("^(.-)@(.*)$")
		local c = Canon(b.name)
		-- (Battle.net may give the first name alone: the claim's surname after it)
		if not (name == c or name:sub(1, #c + 1) == c .. "-") then return false end
		return not b.realm or SSH.Claim("x", b.realm) == "x@" .. realm
	end
	return SSH.ClaimIs(claim, route.target, MyRealm())
end

local function Send(route, text)
	local CI = C_ChatInfo
	local ok, res
	if route.kind ~= "bn" and not (CI and CI.SendAddonMessage) then return -1 end
	if route.kind == "bn" then
		local f = (C_BattleNet and C_BattleNet.SendGameData) or _G.BNSendGameData
		if not f then return -1 end
		ok, res = pcall(f, route.id, SSH.PREFIX, text)
	elseif route.kind == "guild" then
		ok, res = pcall(CI.SendAddonMessage, SSH.PREFIX, text, "GUILD")
	else
		ok, res = pcall(CI.SendAddonMessage, SSH.PREFIX, text, "WHISPER", route.target)
	end
	if not ok then return -1 end
	if res == nil or res == true then return SENT end
	if res == false then return -1 end
	return Num(res) or -1
end

local function ClassOf(id)
	local f = C_Item and C_Item.GetItemInfoInstant
	if not f then return nil end
	return Num((select(6, Safe(f, id))))
end

--- Consumables: food, potions, elixirs, flasks, bandages, scrolls (the game's Consumable item class), as @consumable.
local function Consumable(id)
	return ClassOf(id) == ((_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Consumable) or 0)
end
SSH.Consumable = Consumable

--- Crafting mats: trade goods, reagents, and anything the game calls a crafting reagent, as @mats.
local function Mat(id)
	local IC = _G.Enum and _G.Enum.ItemClass
	local c = ClassOf(id)
	if c == ((IC and IC.Tradegoods) or 7) or c == ((IC and IC.Reagent) or 5) then return true end
	local f = C_Item and C_Item.GetItemInfo
	if not f then return false end
	local ok, r = pcall(function() return select(17, f(id)) end)
	return ok and r == true
end
SSH.Mat = Mat

-- each mode's items from this character's bags (all: every one)
local WANT = {
	limited = function(id) return Consumable(id) or Mat(id) end,
	mats = Mat,
	consumables = Consumable,
}

--- What your bags hold now: { [itemID] = count }.
local function BagItems()
	local out = {}
	local CC = C_Container
	if not (CC and CC.GetContainerNumSlots) then return out end
	local last = (_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or _G.NUM_BAG_SLOTS or 4) + 1
	for bag = 0, last do
		for slot = 1, (Num(Safe(CC.GetContainerNumSlots, bag)) or 0) do
			local info = Safe(CC.GetContainerItemInfo, bag, slot)
			local id = type(info) == "table" and Num(info.itemID)
			if id then out[id] = (out[id] or 0) + (Num(info.stackCount) or 1) end
		end
	end
	return out
end
SSH.BagItems = BagItems

-- where @stored keeps things, as a snapshot says it (worn gear, auctions and guild banks aren't shared)
local WHERE_CODE = { bags = "b", bank = "k", mail = "m", void = "v", warband = "w" }

--- Your gold: every character's (and the warband bank's), as @gold totals it; else this character's.
local function AllGold()
	local p = ns.providers.gold
	local mine
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		if e.goldKind == "total" then return Num(e.money) end
		if e.goldKind == "me" then mine = Num(e.money) end
	end
	return mine or Num(Safe(_G.GetMoney))
end

--- What you share in a mode, as a snapshot (SSH.Encode's shape). limited, mats, consumables: this character's bags;
--- all: everything there, your other characters and banks as @stored reads them (Syndicator or BagBrother), and gold.
function SSH.Snapshot(mode)
	local me = ns.CharacterName and ns.CharacterName() or "?"
	local places, index, items = {}, {}, {}
	local function place(who, where)
		local k = who .. "/" .. where
		if not index[k] then
			places[#places + 1] = { who = who, where = where }
			index[k] = #places
		end
		return index[k]
	end
	local function add(id, pi, n)
		local t = items[id]
		if not t then t = {}; items[id] = t end
		t[pi] = (t[pi] or 0) + n
	end
	local want = WANT[mode]
	local bags = place(me, "b")
	for id, n in pairs(BagItems()) do
		if mode == "all" or (want and want(id)) then add(id, bags, n) end
	end
	local gold
	if mode == "all" then
		local p = ns.providers.stored
		for _, e in ipairs(p and ns:GetEntries(p) or {}) do
			local id = e.itemID
			for _, h in pairs(type(e.holders) == "table" and e.holders or {}) do
				local w = WHERE_CODE[h.where]
				-- (what you carry is read live above)
				if id and w and (h.count or 0) > 0 and not (h.mine and h.where == "bags") then
					add(id, place(w == "w" and "" or (h.mine and me or tostring(h.who)), w), h.count)
				end
			end
		end
		gold = AllGold()
	end
	return { places = places, items = items, gold = gold }
end

local nonceN = 0
local function Nonce()
	nonceN = nonceN + 1
	local t = (type(_G.debugprofilestop) == "function" and _G.debugprofilestop()) or GetTime()
	return C.Hex(C.SHA256(tostring(t) .. "|" .. nonceN .. "|" .. math.random() .. "|" .. tostring((type(time) == "function" and time()) or 0)
		.. "|" .. tostring(SSH.claimNow or ""))):sub(1, 16)
end
SSH.Nonce = Nonce

--- Where a hello goes: the guild channel, each friend on your list who's online and not in your guild, each Battle.net
--- friend playing World of Warcraft who's on neither.
local function Broadcast()
	local out, done = {}, {}
	local P = People()
	if _G.IsInGuild and Safe(_G.IsInGuild) then
		out[#out + 1] = { kind = "guild" }
		for c in pairs(P.guild) do done[c] = true end
	end
	local FL = C_FriendList
	for i = 1, (FL and FL.GetNumFriends and Num(Safe(FL.GetNumFriends)) or 0) do
		local f = Safe(FL.GetFriendInfoByIndex, i)
		local n = type(f) == "table" and f.connected and Str(f.name)
		-- (a friend on your realm is "bob" here, "bob-realm" on the roster: review, 0.58.16, said hello twice)
		if n and not done[Canon(n)] and not done[Canon(n) .. "-" .. MyRealm()] then
			done[Canon(n)] = true
			out[#out + 1] = { kind = "whisper", target = n }
		end
	end
	for id, b in pairs(P.bn) do
		local c = Canon(b.name)
		if not done[c] and not done[c .. "-" .. MyRealm()] then
			out[#out + 1] = { kind = "bn", id = id, name = b.name, bnetID = b.bnetID }
		end
	end
	return out
end

--- `.ssh connect Bob`: the way to reach a friend by name, or nil when they're none of the three.
function SSH.RouteFor(name)
	local P = People()
	local c = Canon(ns.Share and ns.Share.WhisperTarget and ns.Share.WhisperTarget(name) or name)
	for id, b in pairs(P.bn) do
		if Canon(b.name) == c then return { kind = "bn", id = id, name = b.name, bnetID = b.bnetID } end
	end
	if P.names[c] or P.names[c .. "-" .. MyRealm()] then
		local target = ns.Share and ns.Share.WhisperTarget and ns.Share.WhisperTarget(name) or name
		return { kind = "whisper", target = target }
	end
	return nil
end

SSH.game = SSH.Endpoint({
	now = function() return GetTime() end,
	claim = function()
		local c = SSH.Claim(ns.CharacterName and ns.CharacterName(), MyRealm())
		SSH.claimNow = c
		return c or "?@"
	end,
	send = Send,
	eligible = Eligible,
	matches = Matches,
	items = SSH.Snapshot,
	locked = function() return ns.ChatLocked and ns.ChatLocked() or false end,
	changed = function() ns:Changed("shared"); SSH.Badge() end,
	say = function(text) ns:Print(text); SSH.Badge(true) end, -- (said: connected, disconnected... the badge with it)
	nonce = Nonce,
	broadcast = Broadcast,
})

local ticker
function SSH.StartTicker()
	if ticker or not (C_Timer and C_Timer.NewTicker) then return end
	ticker = C_Timer.NewTicker(1, function()
		local ep = SSH.game
		ep:Tick()
		-- (off, and the goodbyes all gone: stopped)
		if not ep.key and not ep.deriving and #ep.queue == 0 then SSH.StopTicker() return end
		local U = ns.UI
		local def = U and U.badges and (function() for _, d in ipairs(U.badges) do if d.id == "share" then return d end end end)()
		if def and def.frame and def.frame:IsShown() then BadgeColour(def.frame) end -- (connecting: the arcs light in turn)
	end)
end
function SSH.StopTicker()
	if ticker then ticker:Cancel(); ticker = nil end
end

--- The game's events, as the endpoint hears them (also the tests' way in).
function SSH.OnEvent(event, ...)
	local ep = SSH.game
	if event == "CHAT_MSG_ADDON" then
		local prefix, text, channel, sender = ...
		if Str(prefix) ~= SSH.PREFIX then return end
		text, channel, sender = Str(text), Str(channel), Str(sender) -- (secret while chat is locked: ignored)
		if not (text and channel and sender) then return end
		local route
		if channel == "WHISPER" then route = { kind = "whisper", target = sender }
		elseif channel == "GUILD" then route = { kind = "guild", target = sender }
		else return end -- (party, raid, channels: never read)
		ep:Receive(route, text)
		local p = ep:Peer(route)
		if p and channel == "GUILD" then p.viaGuild = true end
	elseif event == "BN_CHAT_MSG_ADDON" then
		local prefix, text, _, senderID = ...
		if Str(prefix) ~= SSH.PREFIX then return end
		text, senderID = Str(text), Num(senderID)
		if not (text and senderID) then return end
		ep:Receive({ kind = "bn", id = senderID }, text)
	elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYERBANKSLOTS_CHANGED" or event == "MAIL_INBOX_UPDATE"
		or event == "PLAYER_MONEY" then
		if ep.key then ep:Changed() end -- (sent only when what you share changed: Share compares the text)
	elseif event == "FRIENDLIST_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "BN_FRIEND_INFO_CHANGED"
		or event == "BN_FRIEND_LIST_SIZE_CHANGED" then
		people = nil
	elseif event == "PLAYER_LOGOUT" then
		ep:Bye()
	elseif event == "PLAYER_LOGIN" then
		if ns.db and MODES[ns.db.sshShare] then ep.mode = ns.db.sshShare end
		SSH.Restore(ep) -- (the password remembered: connected again by itself)
	end
end

do
	local CI = C_ChatInfo
	if CI and CI.RegisterAddonMessagePrefix then pcall(CI.RegisterAddonMessagePrefix, SSH.PREFIX) end
	local f = CreateFrame("Frame")
	for _, ev in ipairs({ "CHAT_MSG_ADDON", "BN_CHAT_MSG_ADDON", "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "MAIL_INBOX_UPDATE",
		"PLAYER_MONEY", "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE",
		"BN_FRIEND_INFO_CHANGED", "BN_FRIEND_LIST_SIZE_CHANGED", "PLAYER_LOGOUT", "PLAYER_LOGIN" }) do
		pcall(f.RegisterEvent, f, ev)
	end
	f:SetScript("OnEvent", function(_, event, ...) SSH.OnEvent(event, ...) end)
	SSH.frame = f
end
