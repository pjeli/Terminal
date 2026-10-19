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
-- Groups (0.59.0, the player: ".share join group1 password1"): each group a name and a password of its own, and what you
-- share in it; .share password is the group "default". Friends who joined the same group with the same password see
-- each other; each sees from you what you share in the groups you have in common (all of them together).
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
SSH.V = "4"                -- the protocol's version, each message's first character (2: 0.58.16, delta updates,
                           -- 150-piece snapshots, a session in hellos; 3: groups; 4: 0.59.0, groups' marks made from
                           -- their keys. A friend on another is told to update)
SSH.SALT = "Terminal.ssh.1" -- (the key is the same for every pair who typed the same password)
SSH.KDF_ROUNDS = 1000      -- SHA-256s a password guess costs (2000 until 0.59.0; 20000 and then 4000 were too much for
                           -- the game's CPU, the player: "bring it down and maybe consider asking user to have special
                           -- characters, numbers, capitalizations": the password's own strength does the work now,
                           -- SSH.PasswordProblem. Once, as it's typed: at login the remembered key is used)
SSH.KDF_MS = 2             -- ms of them a frame, the clock looked at after each (the game's frame stays smooth)
SSH.KDF_SLICE = 100000     -- of them a frame at most (the tests make it 1: a key made over frames)
SSH.KDF_ID = "s1000"      -- the way keys are made, remembered with them: a key made another way is typed again
SSH.MIN_PASSWORD = 8        -- characters, no spaces, three kinds of them (SSH.PasswordProblem; 0.59.3, the player)
SSH.MAX_GROUPS = 5         -- groups at once (a hello names each; a proof is one per group, in one message)
SSH.GROUP_LEN = 16         -- a group's name: letters, digits, "-" and "_", this long at most
SSH.DEFAULT_GROUP = "default" -- .share password's
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
-- for every bag change): after a friend has a whole snapshot, a change sends only what changed, "3U ver,base,i,n,..."
-- with "id:0.k,1.3" for an item changed or new, "id:x" for one gone, and the gold: "changes!gold". The friend applies
-- it to the snapshot `base`; one they don't have (a piece lost, a /reload) is asked for whole again ("3R").

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

--- A group's salt: the default group's is the one keys were made with before groups (a remembered key still fits).
local function Salt(group)
	if group == nil or group == SSH.DEFAULT_GROUP then return SSH.SALT end
	return SSH.SALT .. "|" .. group
end

--- The key from a password, a slice at a time (`later(fn)` runs fn on a later frame; nil: all at once). done(key).
--- `group`: the group's name (its salt: the same password in two groups is two keys).
--- `progress(share done, 0 to 1)` after each frame's slice. A frame's slice is KDF_MS of hashing (the clock looked at
--- after every hash: a slow machine's frame never takes more than one hash past it), KDF_SLICE at most.
function SSH.Derive(password, done, later, group, progress)
	local rounds, slice = SSH.KDF_ROUNDS, SSH.KDF_SLICE
	local SHA = C.SHA256
	local k = SHA(Salt(group) .. "\0" .. password)
	local left = rounds
	local clock = later and type(_G.debugprofilestop) == "function" and _G.debugprofilestop or nil
	local function step()
		local t0, n = clock and clock(), 0
		while left > 0 do
			k = SHA(k .. password)
			left, n = left - 1, n + 1
			if later and (n >= slice or (clock and clock() - t0 >= SSH.KDF_MS)) then break end
		end
		if progress then pcall(progress, 1 - left / rounds) end
		if left > 0 then later(step) return end
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
-- Groups
----------------------------------------------------------------------

--- A group's name as typed, made plain ("Raid-Team" -> "raid-team"), or nil when it can't be one.
function SSH.GroupName(s)
	s = Lower(tostring(s or ""))
	-- (letters of any language: a character of several bytes counted once; review, 0.59.0)
	if s == "" or #(s:gsub("[\128-\191]", "")) > SSH.GROUP_LEN or not s:find("^[%w_%-\128-\255]+$") then return nil end
	return s
end

--- A group's mark in a hello (0.59.0, the player: "hide the group name"): 8 hex characters of an HMAC under the group's
--- key, over the session and the character saying it. Only who has the key can make it or tell which group it is; it
--- names no group, and it's another every session (a guildmate can't tell your groups apart, or the same group from one
--- login to the next). A wrong password makes another mark: the groups just aren't in common ("no answer").
function SSH.Mark(key, sess, claim)
	return C.Hex(C.HMAC(key, "M|" .. tostring(sess) .. "|" .. tostring(claim))):sub(1, 8)
end

-- What several groups' modes share together: limited is mats and consumables; all is everything.
local WIDE = { none = {}, mats = { m = true }, consumables = { c = true }, limited = { m = true, c = true } }
function SSH.Union(modes)
	local m, c = false, false
	for _, x in ipairs(modes) do
		if x == "all" then return "all" end
		local w = WIDE[x] or {}
		m, c = m or w.m == true, c or w.c == true
	end
	if m and c then return "limited" end
	return m and "mats" or c and "consumables" or "none"
end

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
--                             "consumables" (for a friend: the modes of the groups you have in common, together)
--   locked()                  the game locks chat messaging now
--   changed()                 a friend's items changed (the list is made again)
--   say(text)                 a line in your chat window
--   nonce()                   16 hex characters, never the same twice
--   broadcast()               { routes } a hello goes to: the guild channel, friends, Battle.net friends' characters
--   proven(claim, route)      (optional) a way just proven for that claim
-- route: { kind = "whisper", target = "Bob-Realm" } | { kind = "guild", target = sender } | { kind = "bn", id = n,
--   name = character, bnetID = account id }

local E = {}
E.__index = E

function SSH.Endpoint(env)
	return setmetatable({ env = env, peers = {}, friends = {}, waiting = {}, queue = {}, tokens = SSH.BURST, refillAt = 0,
		defaultMode = "limited", outVer = 0, recheckAt = 0, hellos = {}, tried = {}, groups = {}, snaps = {}, groupGen = 0,
		markCache = {} }, E)
end

-- Two records (0.58.3; in game, 0.58.2: connected, "items: 0" on both sides):
--   peers[routeKey]  a way to reach someone and its handshake: whisper "w:name" (the name as the server writes it,
--                    your own realm dropped: "Bob-Realm", "Bob" and the guild channel's "Bob" are one way), or
--                    Battle.net "b:<game account>". A friend can have several up at once (a guildmate who's also on
--                    your friend list, a Battle.net friend).
--   friends[claim]   a friend, however they reach you: what they sent (items, gold), when they were last heard, the
--                    one way you send to them (the newest proven), and the groups you have in common (f.groups:
--                    every proven way's p.groups).
--   groups[name]     the groups you joined: { name, key, mode }. Hellos name them by marks (SSH.Mark): yours, made
--                    with your session and claim; a friend's, made with theirs.
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

--- In a group (any): sharing is on.
function E:On() return next(self.groups) ~= nil end

--- Your groups' marks as someone (`claim`, their session `sess`) writes them: { [mark] = group name }. Made once a
--- session of theirs (and again when your groups change): a hello, an answer and a goodbye each need them.
function E:MarksOf(claim, sess)
	local k = tostring(claim) .. "|" .. tostring(sess)
	local c = self.markCache[k]
	if c and c.gen == self.groupGen then return c.map end
	local map = {}
	for name, g in pairs(self.groups) do map[SSH.Mark(g.key, sess, claim)] = name end
	-- (a few entries: a friend's every session would be one each, so the cache starts again past a hundred)
	local n = 0
	for _ in pairs(self.markCache) do n = n + 1 end
	if n > 100 then self.markCache = {} end
	self.markCache[k] = { gen = self.groupGen, map = map }
	return map
end

--- Your groups' marks, sorted, as your hello says them: "1a2b3c4d.5e6f7a8b".
function E:Marks()
	local out = {}
	for m in pairs(self:MarksOf(self:Claim(), self:Session())) do out[#out + 1] = m end
	sort(out)
	return concat(out, ".")
end

--- Group names, sorted, from a set of marks ({ [mark] = name }): "default.raid".
local function NamesOf(markOf)
	local out = {}
	for _, n in pairs(markOf) do out[#out + 1] = n end
	sort(out)
	return concat(out, ".")
end

--- Groups' names, sorted and said: "default, raid".
local function Names(set)
	local out = {}
	for n in pairs(set or {}) do out[#out + 1] = n end
	sort(out)
	return concat(out, ", ")
end
SSH.Names = Names

--- What you share with a friend: the groups you have in common, their modes together.
function E:ModeFor(f)
	local modes = {}
	for name in pairs(f.groups or {}) do
		local g = self.groups[name]
		if g then modes[#modes + 1] = g.mode end
	end
	return SSH.Union(modes)
end

--- What you share in all your groups together (the badge's count; .share debug).
function E:WidestMode()
	local modes = {}
	for _, g in pairs(self.groups) do modes[#modes + 1] = g.mode end
	return SSH.Union(modes)
end

--- A group joined with its key (another key for a group you're in: that group left first, its friends said goodbye
--- to). Hello to everyone: friends connected already are proven again, with this group too.
function E:JoinGroup(name, key, mode, quiet)
	local g = self.groups[name]
	if g and g.key ~= key then self:LeaveGroup(name, true) g = nil end
	if not g then
		g = { name = name, key = key, mode = mode or self.defaultMode or "limited" }
		self.groups[name] = g
		self.groupGen = self.groupGen + 1
	end
	for k, p in pairs(self.peers) do
		if p.state ~= "up" and not p.wasUp then self.peers[k] = nil end
	end
	self.waiting = {}
	self.tried, self.retryAt = {}, self:Now() + SSH.RETRY_TICK
	if not quiet then self:Hello() end -- (quiet: more groups to come, one hello after them)
	return g
end

--- The default group's key (.share password; the tests' way in).
function E:SetKey(key) return self:JoinGroup(SSH.DEFAULT_GROUP, key) end

--- What you share in a group (nil: in every group, and in groups joined later): friends whose share changed are
--- sent it.
function E:SetMode(mode, name)
	if name then
		if not self.groups[name] then return false end
		self.groups[name].mode = mode
	else
		self.defaultMode = mode
		for _, g in pairs(self.groups) do g.mode = mode end
	end
	for _, f in pairs(self.friends) do self:Reshare(f) end
	return true
end

--- A friend sent what you share with them again, whole, when that changed (a group's mode, a group left).
function E:Reshare(f)
	if self.friends[f.claim] and self:ModeFor(f) ~= f.sentMode then self:Share(f, true) end
end

--- A group left: friends you have only it in common with are said goodbye to and dropped; the others are told
--- ("3L <mark>") and sent what you share with them now.
function E:LeaveGroup(name, rejoining)
	-- (its password still being made from: never used; review, 0.59.0: it was joined after the leave)
	if self.deriving and self.deriving[name] then
		self.deriving[name] = nil
		if self.derivingDone then self.derivingDone[name] = nil end
		if next(self.deriving) == nil then self.deriving = nil end
	end
	local g = self.groups[name]
	if not g then return false end
	-- (the last group left: everyone said goodbye to, as .share off does, the queue kept for it. Review, 0.59.0: the
	-- goodbyes queued here were then dropped with the queue. A password being made for another group goes on)
	local others = false
	for n in pairs(self.groups) do if n ~= name then others = true end end
	if not others and not rejoining then
		local deriving = self.deriving
		self:Off()
		self.deriving = deriving
		return true
	end
	local myMark = SSH.Mark(g.key, self:Session(), self:Claim()) -- (said to those who stay: "3L <mark>")
	self.groups[name] = nil
	self.groupGen = self.groupGen + 1
	for claim, f in pairs(self.friends) do
		if f.groups and f.groups[name] then
			f.groups[name] = nil
			for _, p in pairs(self.peers) do
				if p.claim == claim and p.groups then p.groups[name] = nil end
			end
			if next(f.groups) == nil then
				self:Send(f.route, SSH.V .. "B")
				self:Drop(f)
			else
				self:Send(f.route, SSH.V .. "L " .. myMark)
				self:Reshare(f)
				f.rows = nil -- (their @shared rows say their groups: made again)
				self.env.changed()
			end
		end
	end
	return true
end

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
	if not self:On() then return false end
	local now = self:Now()
	if route and route.kind == "guild" then
		-- (the guild channel: one message, answered by each member who has the password; the nonce is the one they echo)
		local n = self.env.nonce()
		self.hellos[n], self.lastBroadcast = now, n
		self:Tried("guild", now)
		self:Send(route, SSH.V .. "H " .. n .. "," .. self:Claim() .. "," .. self:Session() .. "," .. self:Marks())
		return true
	end
	if route then
		local p = self:Peer(route, true)
		-- (connected already this way: what they send still lands while it's proven again)
		if p.state == "up" then p.wasUp = true end
		p.state, p.nA, p.nB, p.since = "hello", self.env.nonce(), nil, now
		self:Tried(p.key, now)
		self:Send(p.route, SSH.V .. "H " .. p.nA .. "," .. self:Claim() .. "," .. self:Session() .. "," .. self:Marks(), nil, nil, p)
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
	self.tried[p.key] = nil
	local f = self.friends[p.claim]
	local new = f == nil
	if new then
		f = { claim = p.claim, items = {}, entries = {}, places = {}, n = 0 }
		self.friends[p.claim] = f
	end
	-- (proven again, the same way and the same session of theirs, a group joined say: what's under way goes on, and
	-- only what changed is sent. Review, 0.59.0: every friend was sent everything whole again, both ways, for a group
	-- joined that most weren't in. Anything else, a new way or they /reloaded: from nothing, whole)
	local same = not new and f.key == p.key and p.sess ~= nil and p.sess ~= "" and f.sess == p.sess
	if not same then p.pieces, p.got, p.inKey, f.ver = {}, 0, nil, nil end
	f.name, f.route, f.key, f.last, f.sess = p.name or f.name, p.route, p.key, now, p.sess
	if self.env.proven then pcall(self.env.proven, p.claim, p.route) end -- (the game's: a Battle.net claim kept by its account)
	-- (the groups you have in common: the ones proven on this way, the one you send by. Review, 0.59.0: every way's
	-- together, and a way proven in one group got what another way's group shares)
	local groups = {}
	for n in pairs(p.groups or {}) do if self.groups[n] then groups[n] = true end end
	f.groups = groups
	f.rows = nil -- (their @shared rows say their groups: made again)
	self.waiting[p.key] = nil
	if new then self.env.say(L["Share: connected to %s"]:format(f.name or "?")) end
	if same and self:ModeFor(f) == f.sentMode then
		self:Share(f)
	else
		f.sentText = nil -- (sent again whole: this way, or this session of theirs, may be new)
		self:Share(f, true)
	end
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
	-- (what was still waiting to go to them: not sent after a goodbye. Review, 0.59.0: a hundred pieces went on after it)
	local ping = "ping:" .. f.claim
	for i = #self.queue, 1, -1 do
		local m = self.queue[i]
		if m.f == f or m.tag == ping then self:Unqueue(i) end
	end
	if why then self.env.say(L["Share: %s disconnected (%s)"]:format(f.name or "?", why)) end
	if HasData(f) then self.env.changed() end
end

--- What you share in a mode, as text (the same text as before: not sent again), and in its parts (SSH.EncodeParts: a
--- delta is made from two of them). "none": an empty text, no parts. Made once a mode for every friend a change is
--- sent to (E:Changed starts them again).
function E:Snapshot(mode, fresh)
	mode = mode or self:WidestMode()
	if mode == "none" then return "", nil end
	local s = self.snaps[mode]
	if fresh or not s then
		local snap = self.env.items(mode) or {}
		snap.mode = mode
		if mode ~= "all" then snap.gold = nil end -- (gold only with all, whatever items() gave)
		local parts = SSH.EncodeParts(snap)
		s = { text = SSH.Join(parts), parts = parts }
		self.snaps[mode] = s
	end
	return s.text, s.parts
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
	local mode = self:ModeFor(f)
	local text, parts = self:Snapshot(mode, force)
	if not force and text == f.sentText then f.owed = nil return end
	-- only what changed, when they have the last one whole and it's the same places and mode: "2U ver,base,i,n,..."
	local letter, payload, base = "D", text, ""
	local old = f.sentParts
	if not force and old and parts and f.sentVer and old.places == parts.places and old.mode == parts.mode then
		local delta = self:DeltaOf(old, parts)
		if delta and #delta < #text / 2 then letter, payload, base = "U", delta, f.sentVer .. "," end
	end
	self.outVer = self.outVer + 1
	local ver = self:Session() .. To36(self.outVer)
	f.sentText, f.sentParts, f.sentVer, f.sentAt, f.owed, f.pingAt, f.sentMode = text, parts, ver, now, nil, now, mode
	-- (pieces of CHUNK characters, put back together as they were; a snapshot past MAX_PIECES is cut at its last whole
	-- item, so it still reads, and the next goes whole)
	local max = SSH.CHUNK * SSH.MAX_PIECES
	if #payload > max then
		local cut = payload:sub(1, max - 1):match("^(.*);") or ""
		payload = cut .. "!!" .. mode
		f.sentParts = nil
	end
	local pieces = {}
	for at = 1, math.max(1, #payload), SSH.CHUNK do pieces[#pieces + 1] = payload:sub(at, at + SSH.CHUNK - 1) end
	f.sentPieces = #pieces
	for i, piece in ipairs(pieces) do
		self:Send(f.route, SSH.V .. letter .. " " .. ver .. "," .. base .. i .. "," .. #pieces .. "," .. piece, tag .. i, f)
	end
end

--- What changed from one snapshot's parts to another's, worked out once for every friend who had the same one
--- (0.59.0, the stress test: 50 friends were 50 deltas of the same two snapshots a bag change). Kept by the old parts,
--- weakly: gone with them.
function E:DeltaOf(old, new)
	local cache = self.deltas
	if not cache then cache = setmetatable({}, { __mode = "k" }); self.deltas = cache end
	local c = cache[old]
	if c and c.new == new then return c.delta or nil end
	local d = SSH.Delta(old, new)
	cache[old] = { new = new, delta = d or false }
	return d
end

--- Your bags changed: each friend is sent them (within SEND_GAP).
function E:Changed()
	self.snaps = {}
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
		if name and self:On() and not self.otherV[k] then
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
		local nA, claim, sess, theirs = rest:match("^(%x+),([^,]+),(%x*),([%x%.]*)$")
		if not (ValidNonce(nA) and ValidClaim(claim) and self.env.matches(claim, route)) then return end
		-- (the groups you have in common: their marks that your groups' keys make for them)
		local mineAsTheirs = self:MarksOf(claim, sess)
		local common, nCommon = {}, 0
		for t in theirs:gmatch("%x+") do
			if mineAsTheirs[t] and not common[t] and nCommon < SSH.MAX_GROUPS then common[t] = mineAsTheirs[t]; nCommon = nCommon + 1 end
		end
		if nCommon == 0 then
			self.waiting[self:Key(route)] = { name = name, at = now }
			return
		end
		-- (the guild channel's hello from a friend connected, the same session of theirs and the same groups: one to
		-- others, let be. Review, 0.58.16: answered, it broke the connection until it was made again. A hello to you
		-- alone is always answered: they dropped you, whatever you think; another group joined is proven too)
		local commonText = NamesOf(common)
		if route.kind == "guild" and p and p.state == "up" and p.claim == claim and sess ~= "" and p.sess == sess
			and p.common == commonText then return end
		-- (the same hello again while you challenge it, sent late from a busy queue: your challenge again, the same nonce,
		-- so their proof of it still fits. Review, 0.59.0: a new nonce, and their proof of the first was ignored)
		if p and p.state == "challenged" and p.nA == nA and p.claim == claim and p.nB then
			if not p.reChallenged or now - p.reChallenged >= SSH.HELLO_GAP then
				p.reChallenged = now
				self:Send(p.route, SSH.V .. "C " .. nA .. "," .. p.nB .. "," .. self:Claim() .. "," .. self:Session() .. "," .. concat(p.offer or {}, "."), nil, nil, p)
			end
			return
		end
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
				if p.state == "up" then p.wasUp = true end -- (review, 0.59.0)
				p.state, p.nA, p.since = "hello", self.lastBroadcast, now
			end
			if p.nA and (not p.resent or now - p.resent >= SSH.HELLO_GAP) then
				p.resent = now
				self:Send(p.route, SSH.V .. "H " .. p.nA .. "," .. mine .. "," .. self:Session() .. "," .. self:Marks(), nil, nil, p)
			end
			return
		end
		if not (p and p.state == "up") and Pending(self) >= SSH.MAX_PENDING then return end
		p = self:Peer(route, true)
		if p.state == "up" and p.claim == claim then p.wasUp = true end -- (what they send lands meanwhile)
		p.lastHello, p.name, p.claim, p.sess = now, name, claim, sess
		-- (the challenge names them by your own marks, made with your key, session and name: someone without the key can't
		-- send theirs back as an answer and be given proofs to guess at)
		local byName = {}
		for m, n in pairs(self:MarksOf(mine, self:Session())) do byName[n] = m end
		local offer, markOf = {}, {}
		for _, n in pairs(common) do
			local m = byName[n]
			if m then offer[#offer + 1], markOf[m] = m, n end
		end
		sort(offer)
		p.offer, p.markOf, p.common = offer, markOf, commonText
		p.state, p.nA, p.nB, p.since = "challenged", nA, self.env.nonce(), now
		self:Send(p.route, SSH.V .. "C " .. nA .. "," .. p.nB .. "," .. mine .. "," .. self:Session() .. "," .. concat(offer, "."), nil, nil, p)
	elseif letter == "C" then
		local nA, nB, claim, sess, offered = rest:match("^(%x+),(%x+),([^,]+),(%x*),([%x%.]*)$")
		if not (self:On() and ValidNonce(nA) and ValidNonce(nB) and ValidClaim(claim) and self.env.matches(claim, route)) then return end
		-- (the groups they offer, by their marks: made with your groups' keys for their session and name, each once)
		local theirs = self:MarksOf(claim, sess)
		local offer, markOf = {}, {}
		for t in offered:gmatch("%x+") do
			if theirs[t] and not markOf[t] and #offer < SSH.MAX_GROUPS then markOf[t] = theirs[t]; offer[#offer + 1] = t end
		end
		if #offer == 0 then return end
		sort(offer)
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
		p.offer, p.markOf, p.common = offer, markOf, NamesOf(markOf)
		-- (a proof for each group: "mark:mac.mark:mac", each with that group's key)
		local proofs = {}
		for i, t in ipairs(offer) do proofs[i] = t .. ":" .. Mac(self.groups[markOf[t]].key, "I", nA, nB, self:Claim(), claim) end
		self:Send(p.route, SSH.V .. "A " .. nA .. "," .. nB .. "," .. concat(proofs, "."), nil, nil, p)
	elseif letter == "A" then
		local nA, nB, list = rest:match("^(%x+),(%x+),([%x:%.]+)$")
		if not (self:On() and p and p.state == "challenged" and p.nA == nA and p.nB == nB) then return end
		local good, answers = self:Proven(p, list, "I", p.claim, self:Claim(), name)
		if not good then return end -- (no answer: a wrong password learns nothing)
		for i, t in ipairs(answers) do answers[i] = t .. ":" .. Mac(self.groups[p.markOf[t]].key, "R", nA, nB, p.claim, self:Claim()) end
		self:Send(p.route, SSH.V .. "K " .. nA .. "," .. nB .. "," .. concat(answers, "."))
		p.groups = good
		self:Up(p)
	elseif letter == "K" then
		local nA, nB, list = rest:match("^(%x+),(%x+),([%x:%.]+)$")
		if not (self:On() and p and p.state == "proved" and p.nA == nA and p.nB == nB) then return end
		local good = self:Proven(p, list, "R", self:Claim(), p.claim, name)
		if not good then return end
		p.groups = good
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
	elseif letter == "L" then
		-- (they left one of your groups: what you share with them is what's left in common; none left, they're gone)
		local t = rest:match("^(%x+)$")
		local f = p and (p.state == "up" or p.wasUp) and self.friends[p.claim]
		local gname = f and t and self:MarksOf(f.claim, f.sess or "")[t]
		local g = gname and self.groups[gname]
		if not (f and g and f.groups and f.groups[g.name]) then return end
		f.groups[g.name] = nil
		for _, q in pairs(self.peers) do
			if q.claim == f.claim and q.groups then q.groups[g.name] = nil end
		end
		if next(f.groups) == nil then
			self:Drop(f)
			self.env.say(L["Share: %s disconnected"]:format(f.name or name))
		else
			self:Reshare(f)
			f.rows = nil -- (their @shared rows say their groups: made again)
			self.env.changed()
		end
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

--- A list of proofs ("mark:mac.mark:mac") checked against the groups offered in this handshake: the set of groups
--- proven ({ [name] = true }) and their marks in order, or nil when none is (the way marked a mismatch). Each group whose
--- proof fails is said ("Bob's password for raid doesn't match yours"). `idA`/`idB`: the hello's sender, then the
--- challenger.
function E:Proven(p, list, label, idA, idB, name)
	local offered = {}
	for _, t in ipairs(p.offer or {}) do offered[t] = true end
	local markOf = p.markOf or {}
	local good, marks, n = {}, {}, 0
	for t, mac in list:gmatch("(%x+):(%x+)") do
		local g = offered[t] and markOf[t] and self.groups[markOf[t]]
		if g then
			offered[t] = nil
			if mac == Mac(g.key, label, p.nA, p.nB, idA, idB) then
				good[g.name], n = true, n + 1
				marks[#marks + 1] = t
			elseif g.name == SSH.DEFAULT_GROUP then
				self.env.say(L["Share: %s's password doesn't match yours"]:format(name))
			else
				self.env.say(L["Share: %s's password for %s doesn't match yours"]:format(name, g.name))
			end
		end
	end
	if n == 0 then
		p.state, p.mismatch, p.wasUp = "mismatch", self:Now(), nil
		-- (connected by this way, and none of its groups proven any more: they're not who you share with now)
		local f = p.claim and self.friends[p.claim]
		if f and f.key == p.key then self:Drop(f, L["no group in common any more"]) end
		return nil
	end
	return good, marks
end

--- Data or a ping from a friend who thinks you're connected and you don't (you /reloaded): hello again, now and then.
function E:Stranger(route, p)
	if not self:On() then return end
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
	if self:On() and now >= (self.retryAt or 0) then
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

--- `.share off`: goodbye to every friend, every group and everything they sent forgotten.
function E:Off()
	local had, byes = false, {}
	for _, f in pairs(self.friends) do
		byes[#byes + 1] = f.route
		if HasData(f) then had = true end
	end
	self.peers, self.friends, self.waiting, self.queue, self.hellos = {}, {}, {}, {}, {}
	self.groups, self.snaps, self.markCache = {}, {}, {}
	self.groupGen = self.groupGen + 1
	self.tried, self.retryAt = {}, nil
	-- (a password still being made from: never used. Review, 0.58.16: .share off while it was, and it was set after)
	self.deriving, self.derivingDone = nil, nil
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
local WHERE_ORDER = { "b", "k", "m", "v", "w" }

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
	local f = e.friend
	if f and f.groups and next(f.groups) and not (f.groups[SSH.DEFAULT_GROUP] and not next(f.groups, next(f.groups))) then
		t:AddLine(L["Shared in: %s"]:format(Names(f.groups)), 0.6, 0.6, 0.6, true)
	end
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
	-- (where they keep it, bags and bank apart: "x20 · Cad Man · bags 12, bank 8"; 0.59.0, the player: "distinctly
	-- separated as in Bank vs in Bags")
	detail = function(t)
		local f = t.friend
		local by = {}
		for _, pt in ipairs(SSH.Parts(f.entries and f.entries[t.itemID])) do
			local pl = f.places and f.places[pt.place]
			local w = pl and pl.where or "b"
			by[w] = (by[w] or 0) + pt.n
		end
		local where = {}
		for _, w in ipairs(WHERE_ORDER) do
			if by[w] then where[#where + 1] = WHERE_SAID[w] .. " " .. by[w] end
		end
		local d = "x" .. t.total .. ns.DETAIL_SEP .. t.owner
		if #where > 0 then d = d .. ns.DETAIL_SEP .. concat(where, ", ") end
		return Keep(t, "detail", d)
	end,
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
	-- (the groups you have in common: "raid linen" finds raid friends' linen)
	local text = "shared friend " .. Lower(who) .. " " .. Names(f.groups):gsub(",", "")
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

-- (this character's bank, as @stored has it, is in what limited, mats and consumables share: when @stored's records
-- change, Syndicator's word after the game's bag events, what you share is sent again. Review, 0.59.0)
if ns.changedHooks then
	ns.changedHooks[#ns.changedHooks + 1] = function(id)
		if id == "stored" and SSH.game and SSH.game:On() then SSH.game:Changed() end
	end
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
	limited = L["this character's crafting mats and consumables, in its bags and bank"],
	mats = L["this character's crafting mats, in its bags and bank"],
	consumables = L["this character's consumables, in its bags and bank"],
	none = L["nothing"],
}
SSH.MODES = MODES

-- (a group can't be named as a word .share takes)
local RESERVED = { password = true, pass = true, pw = true, join = true, leave = true, off = true, connect = true,
	debug = true, status = true, share = true }
for m in pairs(MODES) do RESERVED[m] = true end
SSH.RESERVED = RESERVED

local function Saved()
	if type(_G.TerminalShareDB) ~= "table" then _G.TerminalShareDB = {} end
	local db = _G.TerminalShareDB
	if type(db.groups) ~= "table" then db.groups = {} end
	-- (anything else in it, a hand edit or another version's: dropped, not an error at login)
	for k, v in pairs(db.groups) do
		if type(k) ~= "string" or type(v) ~= "table" then db.groups[k] = nil end
	end
	-- (0.58.6-0.58.16 remembered one key: the default group's now)
	if type(db.key) == "string" then
		db.groups[SSH.DEFAULT_GROUP] = db.groups[SSH.DEFAULT_GROUP] or { key = db.key }
		db.key = nil
	end
	return db
end
SSH.Saved = Saved

--- What you share, set: in one group, or (no group) in every group and those joined later. Friends whose share
--- changed are sent it now; it's remembered.
function SSH.SetMode(ep, m, group)
	if not MODES[m] then
		return { L["Share: what to share: .share limited (the default), .share all, .share mats, .share consumables or .share none"] }
	end
	if group and not ep.groups[group] then return { L["Share: you're not in %s"]:format(group) } end
	ep:SetMode(m, group)
	local db = Saved()
	if group then
		if db.groups[group] then db.groups[group].mode = m end
		return { L["Share: sharing %s in %s"]:format(MODE_SAID[m], group) }
	end
	db.mode = m
	for _, g in pairs(db.groups) do g.mode = m end
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
	for _, w in pairs(ep.waiting) do
		other[#other + 1] = ep:On() and L["%s wants to connect: no group in common (another group, or another password)"]:format(w.name)
			or L["%s wants to connect: type .share password"]:format(w.name)
	end
	sort(other)
	return other
end

--- A password being made into a key: how far ("Share: setting the password... 40%"), the least along of them.
function SSH.DerivingLine(ep)
	local least
	for name in pairs(ep.deriving or {}) do
		local x = ep.derivingDone and ep.derivingDone[name] or 0
		if not least or x < least then least = x end
	end
	return L["Share: setting the password... %d%%"]:format(math.floor((least or 0) * 100))
end

function SSH.Status(ep)
	ep = ep or SSH.game
	local lines = {}
	if not ep then return { L["Share: not available"] } end
	if not ep:On() then
		lines[1] = ep.deriving and SSH.DerivingLine(ep)
			or L["Share: not in a group yet. Type .share password <password> (8 characters or more, no spaces: capitals, numbers, symbols), the same as your friends, or .share join <group> <password> for a group of its own"]
	else
		lines[1] = L["Share: your groups (remembered: .share leave <group> or .share off forgets them)"]
		local names = {}
		for n in pairs(ep.groups) do names[#names + 1] = n end
		sort(names)
		for _, n in ipairs(names) do
			lines[#lines + 1] = "  " .. L["%s: sharing %s"]:format(n, MODE_SAID[ep.groups[n].mode] or ep.groups[n].mode)
		end
		if ep.deriving then lines[#lines + 1] = "  " .. SSH.DerivingLine(ep) end
	end
	local up = ep:Connected()
	if #up > 0 then
		local parts = {}
		for i, c in ipairs(up) do
			local f = c.friend or {}
			local m, gs = f.mode, Names(f.groups)
			if gs == "" then
				parts[i] = m and L["%s (items: %d, sharing: %s)"]:format(c.name, c.n, m) or L["%s (items: %d)"]:format(c.name, c.n)
			else
				parts[i] = m and L["%s (items: %d, sharing: %s, in %s)"]:format(c.name, c.n, m, gs)
					or L["%s (items: %d, in %s)"]:format(c.name, c.n, gs)
			end
		end
		lines[#lines + 1] = "  " .. L["Connected:"] .. " " .. concat(parts, ", ")
	elseif ep:On() then
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
	local gs = {}
	local mine = ep:MarksOf(ep:Claim(), ep:Session())
	for m, n in pairs(mine) do gs[#gs + 1] = n .. "=" .. ep.groups[n].mode .. "/" .. m end
	sort(gs)
	lines[1] = ("ssh debug: groups %s, queue %d, sent (game's answers) %s, heard %s"):format(#gs > 0 and concat(gs, " ") or "none",
		#ep.queue, counts(ep.results), counts(ep.heard))
	local keys = {}
	for k in pairs(ep.peers) do keys[#keys + 1] = k end
	sort(keys)
	for _, k in ipairs(keys) do
		local p = ep.peers[k]
		lines[#lines + 1] = ("  way %s: %s %s%s%s"):format(k, tostring(p.state), tostring(p.claim or "?"),
			p.groups and (" [" .. Names(p.groups) .. "]") or "", p.got and p.got > 0 and (" (pieces %d)"):format(p.got) or "")
	end
	for _, c in ipairs(ep:Connected()) do
		local f = c.friend
		local text = f.sentText or ""
		lines[#lines + 1] = ("  friend %s (%s; groups %s): items %d%s, heard %ds ago, last data %s; sent to them by %s: %d characters (%s)"):format(
			c.name, tostring(f.mode or "?"), Names(f.groups), c.n, f.gold and (", gold " .. f.gold) or "", floor(now - (f.last or now)),
			f.gotAt and (floor(now - f.gotAt) .. "s ago") or "never", tostring(f.key), #text, tostring(f.sentMode))
	end
	local mine = ep:Snapshot(nil, true)
	lines[#lines + 1] = ("  you share (all your groups together): %d characters: %s"):format(#mine, mine:sub(1, 120))
	return lines
end

--- What's wrong with a password, said; nil when it's strong enough (0.59.1, the player: "asking user to have special
--- characters, numbers, capitalizations ... to strengthen the password"; 0.59.3: "No spaces allowed in password. Allow 8
--- character passwords"): MIN_PASSWORD characters or more, no spaces, with three kinds of them (a capital, a small
--- letter, a number, a symbol, a letter of another script). Only typing it is checked: both sides type the same.
function SSH.PasswordProblem(words)
	words = tostring(words or "")
	if words:find("%s") then return L["Share: a password can't have spaces"] end
	local n = #(words:gsub("[\128-\191]", "")) -- (characters, not bytes)
	-- (a letter of another script, Cyrillic, Chinese, is a kind of its own: it has no capitals here)
	local kinds = (words:find("%u") and 1 or 0) + (words:find("%l") and 1 or 0) + (words:find("%d") and 1 or 0)
		+ (words:find("%p") and 1 or 0) + (words:find("[\128-\255]") and 1 or 0)
	if n >= SSH.MIN_PASSWORD and kinds >= 3 then return nil end
	return L["Share: a password needs %d characters or more, no spaces, with three of: a capital, a small letter, a number, a symbol"]:format(SSH.MIN_PASSWORD)
end

--- `.share join <group> <words>` (`.share password <words>`: the group "default"): the key, made over a few frames, then
--- hello to everyone.
function SSH.JoinWithPassword(ep, group, words, later, done)
	words = tostring(words or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local problem = SSH.PasswordProblem(words)
	if problem then return { problem } end
	-- (those joined, and those whose password is still being made from)
	local n, counted = 0, {}
	for name in pairs(ep.groups) do n, counted[name] = n + 1, true end
	for name in pairs(ep.deriving or {}) do if not counted[name] then n = n + 1 end end
	if not (ep.groups[group] or (ep.deriving and ep.deriving[group])) and n >= SSH.MAX_GROUPS then
		return { L["Share: %d groups at most; .share leave one first"]:format(SSH.MAX_GROUPS) }
	end
	-- (each group's own: another group's being made meanwhile goes on; .share off or leaving it drops it)
	local gen = {}
	ep.deriving = ep.deriving or {}
	ep.deriving[group] = gen
	ep.derivingDone = ep.derivingDone or {}
	ep.derivingDone[group] = 0
	SSH.Derive(words, function(key)
		if not (ep.deriving and ep.deriving[group] == gen) then return end
		ep.deriving[group] = nil
		if ep.derivingDone then ep.derivingDone[group] = nil end
		if next(ep.deriving) == nil then ep.deriving = nil end
		local db = Saved()
		local saved = db.groups[group]
		local mode = type(saved) == "table" and MODES[saved.mode] and saved.mode or ep.defaultMode
		ep:JoinGroup(group, key, mode)
		SSH.StartTicker() -- (stopped meanwhile by a .share leave of another group: on again)
		SSH.Remember(group, key, mode)
		SSH.Badge()
		if group == SSH.DEFAULT_GROUP then
			ep.env.say(L["Share: password set; saying hello to your friends and guild"])
		else
			ep.env.say(L["Share: joined %s; saying hello to your friends and guild"]:format(group))
		end
		if done then done() end
	end, later, group, function(x)
		-- (how far it is: .share and the badge's pop-out say it)
		if ep.deriving and ep.deriving[group] == gen and ep.derivingDone then ep.derivingDone[group] = x end
	end)
	if group == SSH.DEFAULT_GROUP then
		return { L["Share: setting the password (remembered as a key made from it, never as typed; .share off forgets it)"] }
	end
	return { L["Share: joining %s (its password remembered as a key made from it, never as typed; .share leave %s forgets it)"]:format(group, group) }
end

--- `.share password <words>`: the default group's.
function SSH.SetPassword(ep, words, later, done) return SSH.JoinWithPassword(ep, SSH.DEFAULT_GROUP, words, later, done) end

-- The passwords remembered (0.58.6, the player: "saved and re-used automatically on login"): each group's key made from
-- its password, and what you share in it, in Terminal: Share's own saved variables (TerminalShareDB.groups[name] =
-- { key = hex, mode }), never a password as typed. At login they're used a few seconds in (friends and guild read
-- first) and everyone is said hello to once. .share leave <group> forgets one; .share off, all.
-- (Anyone with your WTF folder could connect as you with them: the same as knowing the passwords, for this.)
SSH.LOGIN_WAIT = 5

--- A group's key remembered (nil: forgotten), with what you share in it.
function SSH.Remember(group, key, mode)
	local db = Saved()
	if key then db.groups[group] = { key = C.Hex(key), mode = mode, kdf = SSH.KDF_ID } else db.groups[group] = nil end
end
--- Every group forgotten (.share off).
function SSH.ForgetGroups() Saved().groups = {} end

local function Unhex(h) return (h:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end)) end

--- The groups remembered: { name = { key (raw), mode } } of those that read.
local function Remembered()
	local out, n, stale = {}, 0, {}
	local names = {}
	for name in pairs(Saved().groups) do names[#names + 1] = name end
	sort(names)
	for _, name in ipairs(names) do
		local g = Saved().groups[name]
		local hex = type(g) == "table" and g.key
		if SSH.GroupName(name) == name and type(hex) == "string" and #hex == 64 and hex:find("^%x+$") and n < SSH.MAX_GROUPS then
			-- (a key made the way before, fewer rounds: no friend's matches it now; its password is typed again)
			if g.kdf ~= SSH.KDF_ID then stale[#stale + 1] = name
			else out[name], n = { key = Unhex(hex), mode = MODES[g.mode] and g.mode or nil }, n + 1 end
		end
	end
	return out, n, stale
end

--- The remembered groups, back in use (at login): true when there was one.
function SSH.Restore(ep)
	ep = ep or SSH.game
	local _, n, stale = Remembered()
	if #stale > 0 then
		-- (0.59.0: keys are made with ten times the rounds; those remembered from before are forgotten, said once)
		for _, name in ipairs(stale) do Saved().groups[name] = nil end
		ep.env.say(L["Share: passwords are kept safer now; type yours again: %s"]:format(concat(stale, ", ")))
	end
	if n == 0 then return false end
	SSH.StartTicker()
	local ask = C_GuildInfo and C_GuildInfo.GuildRoster or _G.GuildRoster
	if ask then Safe(ask) end
	C_Timer.After(SSH.LOGIN_WAIT, function()
		local joined, n = 0, 0
		for _ in pairs(ep.groups) do n = n + 1 end
		for name, g in pairs(Remembered()) do
			-- (a group joined meanwhile, or forgotten: as it is now; five at most with those joined meanwhile)
			if not ep.groups[name] and n < SSH.MAX_GROUPS then
				n = n + 1
				ep:JoinGroup(name, g.key, g.mode or ep.defaultMode, true)
				joined = joined + 1
			end
		end
		if joined == 0 then return end
		ep:Hello()
		SSH.Badge()
		ep.env.say(L["Share: using your saved passwords; saying hello to your friends and guild"])
	end)
	return true
end

local function Later(fn) C_Timer.After(0, fn) end

-- (.share, 0.58.14, the player: ".ssh ... a fun throwback to secure shell but its probably confusing for WoW players":
-- .ssh is its alias)
ns:RegisterCommand("share", {
	aliases = { "ssh" },
	desc = L["The share shell: your bags in the searches of friends who run Terminal: Share. .share password <words>, or .share join <group> <words> for a group of its own; what you share: .share limited, all, mats, consumables or none (.share <group> all: in one group); .share leave <group>; .share off"],
	complete = function()
		local out = {
			{ "password", L["the password you and your friends agree on (remembered: .share off forgets it)"] },
			{ "join", L["join a group of its own, with its own password: .share join <group> <words>"] },
			{ "connect", L["say hello to one friend again: .share connect <name>"] },
		}
		for _, m in ipairs(MODE_ORDER) do out[#out + 1] = { m, L["share %s"]:format(MODE_SAID[m]) } end
		local ep = SSH.game
		local names = {}
		for n in pairs(ep and ep.groups or {}) do names[#names + 1] = n end
		sort(names)
		for _, n in ipairs(names) do
			out[#out + 1] = { n, L["what you share in %s: .share %s all, limited, mats, consumables or none"]:format(n, n) }
		end
		if #names > 0 then out[#out + 1] = { "leave", L["leave a group: .share leave <group> (its password forgotten)"] } end
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
		if word == "password" or word == "pass" or word == "pw" or word == "join" then
			local group = SSH.DEFAULT_GROUP
			if word == "join" then
				local typed, words = rest:match("^(%S*)%s*(.-)$")
				group = SSH.GroupName(typed)
				if not group or RESERVED[group] then
					return { L["Share: a group's name is one word of letters and digits, %d at most, and not one .share takes: .share join <group> <password>"]:format(SSH.GROUP_LEN) }
				end
				rest = words
			end
			SSH.StartTicker()
			-- (the guild's members, read before their answers come: C_GuildInfo.GuildRoster)
			local ask = C_GuildInfo and C_GuildInfo.GuildRoster or _G.GuildRoster
			if ask then Safe(ask) end
			return SSH.JoinWithPassword(ep, group, rest, Later)
		end
		if word == "leave" then
			local group = SSH.GroupName(rest)
			if not (group and (ep.groups[group] or (ep.deriving and ep.deriving[group]))) then
				if rest == "" then return { L["Share: which group? .share leave <group>"] } end
				return { L["Share: you're not in %s"]:format(rest) }
			end
			ep:LeaveGroup(group)
			SSH.Remember(group, nil)
			if #ep.queue == 0 and not ep:On() and not ep.deriving then SSH.StopTicker() end
			SSH.Badge()
			return { L["Share: left %s; its password is forgotten"]:format(group) }
		end
		if word == "off" then
			ep:Off()
			SSH.ForgetGroups()
			if #ep.queue == 0 then SSH.StopTicker() end -- (else once the goodbyes are gone)
			SSH.Badge()
			return { L["Share: off. The password is forgotten and your friends' items are gone"] }
		end
		-- (.ssh all, .ssh mats...; .ssh share all too)
		-- (.share limited raid: the mode, then the group, as well as .share raid limited)
		if MODES[word] and rest ~= "" then return SSH.SetMode(ep, word, SSH.GroupName(rest) or rest) end
		if MODES[word] then return SSH.SetMode(ep, word) end
		if word == "share" then return SSH.SetMode(ep, Lower(rest)) end
		-- (.share raid all: what you share in one group)
		if ep.groups[word] then
			if rest == "" then return { L["%s: sharing %s"]:format(word, MODE_SAID[ep.groups[word].mode] or ep.groups[word].mode) } end
			return SSH.SetMode(ep, Lower(rest), word)
		end
		if word == "connect" then
			if not ep:On() then return { L["Share: set the password first: .share password <words>"] } end
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
	local widest = ep:WidestMode()
	local _, mine = ep:Snapshot(widest)
	local n = mine and #mine.ids or 0
	-- (the groups always, each with what you share in it: "default: limited"; 0.59.0, the player: "put the channel name in
	-- the wifi tooltip, default if it is default". Each friend's groups too once there are several)
	local names = {}
	for g in pairs(ep.groups) do names[#names + 1] = g end
	sort(names)
	local several = #names > 1
	t:AddDoubleLine(L["Sharing"], L["you: %s"]:format(Items(n)), 1, 1, 1, 0.6, 0.6, 0.6)
	if #names > 0 then
		local gs = {}
		for i, g in ipairs(names) do gs[i] = g .. ": " .. ep.groups[g].mode end
		t:AddDoubleLine(several and L["Groups"] or L["Group"], concat(gs, ns.DETAIL_SEP), 0.6, 0.6, 0.6, 0.85, 0.85, 0.85)
	end
	for _, c in ipairs(up) do
		local f = c.friend
		local how = { Items(c.n) }
		if f.mode then how[#how + 1] = f.mode end
		if several then how[#how + 1] = Names(f.groups) end
		if f.gold then how[#how + 1] = ns.Money(f.gold) end
		how[#how + 1] = f.route and f.route.kind == "bn" and "Battle.net" or L["whisper"]
		local quiet = now - (f.last or now)
		if quiet >= 60 then how[#how + 1] = Ago(quiet) end
		t:AddDoubleLine(c.name, concat(how, ns.DETAIL_SEP), 1, 0.82, 0, 0.85, 0.85, 0.85)
	end
	if ep.deriving then t:AddLine(SSH.DerivingLine(ep), 0.6, 0.6, 0.6) end
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
		shown = function() local ep = SSH.game return ep ~= nil and (ep:On() or ep.deriving ~= nil) end,
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
	local names, bn, guild, guids, bnNames = {}, {}, {}, {}, {}
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
		if n then
			add(names, n, Ambig(n))
			local guid = Str(f.guid)
			if guid then add(guids, n, guid) end
		end
	end
	for i = 1, (_G.IsInGuild and Safe(_G.IsInGuild) and Num(Safe(_G.GetNumGuildMembers)) or 0) do
		local n = Str((Safe(_G.GetGuildRosterInfo, i)))
		if n then
			add(names, n, Ambig(n)); add(guild, n, true)
			-- (the roster's 17th answer: the character's GUID)
			local guid = Str((select(17, Safe(_G.GetGuildRosterInfo, i))))
			if guid then add(guids, n, guid) end
		end
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
					bn[id] = { name = char, realm = realmName, bnetID = Num(a.bnetAccountID), guid = Str(g.playerGuid) }
					local full = realmName and (char .. "-" .. realmName:gsub("[%s']", "")) or char
					if not names[Canon(char)] then add(bnNames, char, true) end
					add(names, char, char)
					add(names, full, char)
				end
			end
		end
	end
	people, peopleAt = { names = names, bn = bn, guild = guild, guids = guids, bnNames = bnNames, guildN = Num(Safe(_G.GetNumGuildMembers)) or 0 }, now
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

-- A name claimed over Battle.net, with a surname Battle.net didn't give, kept by the Battle.net account first proven
-- with it (0.59.1, the player: "resolve this B.net loose name issue"): { [claim] = bnetAccountID }, this session.
local bnOwner = {}
SSH.bnOwner = bnOwner

local function Matches(claim, route)
	if route.kind == "bn" then
		local P = People()
		local b = P.bn[route.id]
		if not b then return false end
		local name, realm = claim:match("^(.-)@(.*)$")
		local c = Canon(b.name)
		-- (Battle.net may give the first name alone: the claim's surname after it)
		local exact = name == c
		if not (exact or name:sub(1, #c + 1) == c .. "-") then return false end
		if b.realm and SSH.Claim("x", b.realm) ~= "x@" .. realm then return false end
		-- (0.59.1) The character claimed, as your friend list or guild roster knows it: by its GUID, it's this Battle.net
		-- friend's character or not. One the game knows only by its name (a friend list or roster without GUIDs, or a
		-- Battle.net friend whose GUID isn't given): a surname claimed over Battle.net isn't taken for it; they connect
		-- the way they're known by instead.
		local key = (realm == MyRealm() or realm == "") and name or (name .. "-" .. realm)
		local withRealm = name .. "-" .. (realm ~= "" and realm or MyRealm()) -- (the roster writes "Name-Realm")
		local knownGuid = P.guids[key] or P.guids[withRealm]
		if knownGuid and b.guid then return knownGuid == b.guid end
		if not exact then
			if (P.names[key] and not P.bnNames[key]) or (P.names[withRealm] and not P.bnNames[withRealm]) then return false end
			-- (a surname no one else is known by: the Battle.net account that first proved it keeps it)
			local owner = bnOwner[claim]
			if owner and b.bnetID and owner ~= b.bnetID then return false end
		end
		return true
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
	elseif want then
		-- (0.59.0, the player: "also share the character bank inventory of the same types of items": this character's
		-- bank as @stored has it, Syndicator or BagBrother)
		local p = ns.providers.stored
		for _, e in ipairs(p and ns:GetEntries(p) or {}) do
			local id = e.itemID
			for _, h in pairs(id and type(e.holders) == "table" and e.holders or {}) do
				if h.mine and h.where == "bank" and (h.count or 0) > 0 and want(id) then add(id, place(me, "k"), h.count) end
			end
		end
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
	proven = function(claim, route)
		if route.kind == "bn" and route.bnetID and not bnOwner[claim] then bnOwner[claim] = route.bnetID end
	end,
})

local ticker
function SSH.StartTicker()
	if ticker or not (C_Timer and C_Timer.NewTicker) then return end
	ticker = C_Timer.NewTicker(1, function()
		local ep = SSH.game
		ep:Tick()
		-- (off, and the goodbyes all gone: stopped)
		if not ep:On() and not ep.deriving and #ep.queue == 0 then SSH.StopTicker() return end
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
		if ep:On() then ep:Changed() end -- (sent only when what you share changed: Share compares the text)
	elseif event == "FRIENDLIST_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "BN_FRIEND_INFO_CHANGED"
		or event == "BN_FRIEND_LIST_SIZE_CHANGED" then
		people = nil
	elseif event == "PLAYER_LOGOUT" then
		ep:Bye()
	elseif event == "PLAYER_LOGIN" then
		-- (what you share: Terminal's setting until 0.58.16, Terminal: Share's own since groups)
		local db = Saved()
		if not MODES[db.mode] and ns.db and MODES[ns.db.sshShare] then db.mode = ns.db.sshShare end
		local def = db.groups[SSH.DEFAULT_GROUP]
		if type(def) == "table" and not MODES[def.mode] then def.mode = db.mode end
		if ns.db then ns.db.sshShare = nil end
		ep.defaultMode = MODES[db.mode] and db.mode or "limited"
		SSH.Restore(ep) -- (the passwords remembered: connected again by itself)
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
