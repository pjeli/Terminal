-- (Terminal: Share, an addon of its own: Terminal's namespace is its public table, _G.Terminal. Not loaded, nothing of
-- this runs: no prefix registered, no message read.)
local ns = _G.Terminal
if not ns or not ns.Crypto then return end
local L = ns.L

-- The share shell, .ssh (0.58.1): friends' Terminals talk to each other. Two friends in the same group see each other's bags
-- in their searches ("linen cloth": what you carry, your alts, and Bob 20, Ann 15). docs/SHARE.md has the design.
--
-- Who's heard: a character on your friend list, a guild member, a Battle.net friend's character. Every other message
-- is ignored, unanswered. The sender is the server's word (a whisper's sender, the guild channel, a Battle.net game
-- account), never the message's.
-- A group's secret is a code Terminal makes (120 random bits), handed to a friend by invite once they say yes, or given
-- by hand (.share code). Never sent otherwise: each side proves it holds the group's key, made from the code, with an
-- HMAC over both nonces and both names (Crypto.lua). Codes only (share-invites, the player: "Codes Only for the WoW
-- Forever release"): a typed password could be guessed at home by anyone in the guild, against the hellos' marks.
-- Groups (0.59.0): each a code of its own and what you share in it; a group's name is only yours (a friend may call
-- it something else; .share rename). Each friend sees from you what you share in the groups you have in common.
-- What friends send lives here, in memory, and nowhere else: gone on /reload, logout, goodbye, 30 minutes of silence,
-- or once they're no longer a friend or guild member. Nothing of it is ever in ns.db.
--
-- SSH.Endpoint(env) is the protocol, with the game reached only through `env` (the tests run two, talking to each
-- other): this file. SSH.game is this client's, its env made of the game's calls: Share.lua (0.69.8, split off).

local SSH = {}
ns.Ssh = SSH

local C = ns.Crypto
local Lower, Str, Num, Safe = ns.Lower, ns.Str, ns.Num, ns.Safe
local floor, concat, sort = math.floor, table.concat, table.sort

SSH.PREFIX = "TermSSH"
SSH.V = "5"                -- the protocol's version, each message's first character (2: 0.58.16, delta updates,
                           -- 150-piece snapshots, a session in hellos; 3: groups; 4: 0.59.0, groups' marks made from
                           -- their keys; 5: codes only, invites. A friend on another is told to update)
SSH.MAX_GROUPS = 5         -- groups at once (a hello names each; a proof is one per group, in one message)
SSH.GROUP_LEN = 16         -- a group's name: letters, digits, "-" and "_", this long at most
SSH.DEFAULT_GROUP = "default" -- the group an invite makes when you have none
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

SSH.NAME_MAX = 48 -- (bytes of a place's name a friend sends: a character's name and realm, with room)

--- A place's name as a friend sent it, safe to show: no "|" (the game's escapes: a texture, a link, a colour), no control
--- characters, at most NAME_MAX bytes, cut between two letters (0.63.7, review: shown as sent, in rows and tooltips).
function SSH.SafeName(who)
	who = tostring(who or ""):gsub("[|%c]", "")
	if #who > SSH.NAME_MAX then
		local cut = SSH.NAME_MAX
		-- (not inside a letter: back over its continuation bytes, 10xxxxxx, to its first)
		while cut > 0 and (who:byte(cut + 1) or 0) >= 0x80 and (who:byte(cut + 1) or 0) < 0xC0 do cut = cut - 1 end
		who = who:sub(1, cut)
	end
	return who
end

--- The text back: { places = { { who, where } }, items = { [itemID] = total }, entries = { [itemID] = "0.k,1.3" },
--- gold, mode }. At most MAX_PLACES places and MAX_ITEMS items; anything else in it ignored.
function SSH.Decode(text)
	local out = { places = {}, items = {}, entries = {} }
	local placesText, itemsText, goldText, modeText = tostring(text or ""):match("^([^!]*)!([^!]*)!(%w*)!?(%a*)$")
	if not placesText then return out end
	for who, where in placesText:gmatch("([^,/]*)/(%a)") do
		if #out.places >= SSH.MAX_PLACES then break end
		out.places[#out.places + 1] = { who = SSH.SafeName(who), where = SSH.WHERE[where] and where or "b" }
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
	out.mode = modeText ~= "" and SSH.MODES and SSH.MODES[modeText] and modeText or nil -- (a mode Terminal knows)
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
--- login to the next). A wrong key makes another mark: the groups just aren't in common ("no answer").
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
-- Codes (branch share-invites): a group's secret made by Terminal, not typed
----------------------------------------------------------------------
-- A typed password is something a guildmate can guess at home against your hellos' marks; a code is 120 random bits,
-- which nobody can. "TS1-" and 25 characters of Crockford's base 32 (no I, L, O or U; I and L typed read as 1, O as 0),
-- the last a check that catches one wrong character and most swapped ones. A group's key is made from its code alone
-- (`SSH.KeyOfCode`), whatever each friend calls the group: names stay your own.

SSH.CODE_PREFIX = "TS1"
SSH.CODE_SALT = "Terminal.ssh.code.1"
SSH.CODE_ID = "code1" -- (a key made from a code, remembered with it as `kdf`)
local B32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
local B32_VALUE = {}
for i = 1, 32 do B32_VALUE[B32:sub(i, i)] = i - 1 end
for k, v in pairs({ O = "0", I = "1", L = "1" }) do B32_VALUE[k] = B32_VALUE[v] end

local function CodeCheck(values)
	local sum = 0
	for i, v in ipairs(values) do sum = sum + (2 * i + 1) * v end
	return sum % 32
end

--- A code from 15 random bytes (120 bits): "TS1-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX".
function SSH.CodeFromBytes(bytes)
	local values, acc, bits = {}, 0, 0
	for i = 1, 15 do
		acc, bits = acc * 256 + (bytes:byte(i) or 0), bits + 8
		while bits >= 5 do
			bits = bits - 5
			local p = 2 ^ bits
			local v = floor(acc / p)
			values[#values + 1], acc = v, acc - v * p
		end
	end
	values[#values + 1] = CodeCheck(values)
	local out = {}
	for i, v in ipairs(values) do out[i] = B32:sub(v + 1, v + 1) end
	local s = concat(out)
	return SSH.CODE_PREFIX .. "-" .. s:sub(1, 5) .. "-" .. s:sub(6, 10) .. "-" .. s:sub(11, 15) .. "-" .. s:sub(16, 20) .. "-" .. s:sub(21, 25)
end

--- Typed or pasted text read as a code: the code as Terminal writes it, or nil and why ("typo", or nil: not a code at
--- all). Capitals or not, spaces and dashes anywhere, O for 0 and I or L for 1 all read.
function SSH.ReadCode(text)
	local s = tostring(text or ""):upper():gsub("[%s%-_]", "")
	-- (its "TS1" typed "TSI" or "TSL" too)
	if not (s:sub(1, 2) == "TS" and B32_VALUE[s:sub(3, 3)] == 1) then return nil end
	s = s:sub(4)
	if #s ~= 25 then return nil, "typo" end
	local values = {}
	for i = 1, 25 do
		local v = B32_VALUE[s:sub(i, i)]
		if not v then return nil, "typo" end
		values[i] = v
	end
	local check = table.remove(values)
	if CodeCheck(values) ~= check then return nil, "typo" end
	values[#values + 1] = check
	local out = {}
	for i, v in ipairs(values) do out[i] = B32:sub(v + 1, v + 1) end
	local c = concat(out)
	return SSH.CODE_PREFIX .. "-" .. c:sub(1, 5) .. "-" .. c:sub(6, 10) .. "-" .. c:sub(11, 15) .. "-" .. c:sub(16, 20) .. "-" .. c:sub(21, 25)
end

--- A group's key from its code (as SSH.ReadCode writes it): the same for everyone with the code.
function SSH.KeyOfCode(code) return C.HMAC(SSH.CODE_SALT, code) end

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
--   offered()                 (optional) an invite came in, or went (the badge, the prompt's suggestion)
--   joined(name, key, mode, code)  (optional) a group joined by an invite: remember it
-- route: { kind = "whisper", target = "Bob-Realm" } | { kind = "guild", target = sender } | { kind = "bn", id = n,
--   name = character, bnetID = account id }

local E = {}
E.__index = E

function SSH.Endpoint(env)
	return setmetatable({ env = env, peers = {}, friends = {}, waiting = {}, queue = {}, tokens = SSH.BURST, refillAt = 0,
		defaultMode = "limited", outVer = 0, recheckAt = 0, hellos = {}, tried = {}, groups = {}, snaps = {}, groupGen = 0,
		markCache = {}, invites = {}, offers = {} }, E)
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

--- The default group's key (the tests' way in).
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

--- A group called something else (its name is yours alone: friends know it by its key): true, or false when there's
--- no such group or the new name is taken. Everything that names it follows: friends' and handshakes' groups,
--- invites waiting.
function E:Rename(old, new)
	local g = self.groups[old]
	if not g or self.groups[new] then return false end
	self.groups[old], self.groups[new], g.name = nil, g, new
	self.groupGen = self.groupGen + 1 -- (marks read again: a mark now names the new name)
	local function Move(t) if t and t[old] ~= nil then t[new], t[old] = t[old], nil end end
	for _, f in pairs(self.friends) do Move(f.groups) end
	for _, p in pairs(self.peers) do
		Move(p.groups)
		for m, n in pairs(p.markOf or {}) do if n == old then p.markOf[m] = new end end
	end
	for _, inv in pairs(self.invites) do if inv.group == old then inv.group = new end end
	return true
end

--- A friend sent what you share with them again, whole, when that changed (a group's mode, a group left).
function E:Reshare(f)
	if self.friends[f.claim] and self:ModeFor(f) ~= f.sentMode then self:Share(f, true) end
end

--- A group left: friends you have only it in common with are said goodbye to and dropped; the others are told
--- ("3L <mark>") and sent what you share with them now.
function E:LeaveGroup(name, rejoining)
	local g = self.groups[name]
	if not g then return false end
	-- (the last group left: everyone said goodbye to, as .share off does, the queue kept for it. Review, 0.59.0: the
	-- goodbyes queued here were then dropped with the queue)
	local others = false
	for n in pairs(self.groups) do if n ~= name then others = true end end
	if not others and not rejoining then
		self:Off()
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

----------------------------------------------------------------------
-- Invites (branch share-invites): a group's secret handed to a friend, only once they say yes
----------------------------------------------------------------------
-- A -> B   5N id,group        an invite to a group (its name as A calls it; nothing secret)
-- B -> A   5J id              yes (only to the invite B heard, from the character it came from)
-- B -> A   5X id              no thanks
-- A -> B   5G id,c:<code>     the group's code
-- Whispers or Battle.net game data only (the guild channel carries hellos only). Each needs the sender to be someone
-- you'd hear (a friend, a guild member, a Battle.net friend's character), the server's word for who sent it. An
-- invite waits INVITE_KEEP, then it's gone on both sides. Then the code's key: hellos, marks made from it, proofs.
-- No kick and no new code pushed to a group (the player, share-invites: "consider this a rare case and probably better
-- to just force users to start over with a trust set"): a group has no owner, so anyone in it could push one at
-- everyone. To leave someone out, friends start a new group and invite whom they trust.

SSH.INVITE_KEEP = 600 -- s an invite waits for a yes
SSH.INVITE_SAY_GAP = 60 -- s: the same person's invite again isn't said again before this

--- A group's secret as an invite sends it: "c:<code>" (nil: a group with no code, the tests' keys).
local function SecretOf(g)
	return g.code and ("c:" .. g.code) or nil
end

--- A secret as an invite sends it, read: key and code, or nil (codes only: a key sent bare, as 0.69's "k:", isn't taken).
local function ReadSecret(s)
	local v = tostring(s or ""):match("^c:(.+)$")
	local code = v and SSH.ReadCode(v)
	if code then return SSH.KeyOfCode(code), code end
	return nil
end
SSH.ReadSecret = ReadSecret

--- Invite someone (a route and the name to show) to one of your groups: true, or false and why.
function E:Invite(route, name, group)
	local g = self.groups[group]
	if not (g and g.code) then return false, "group" end -- (codes only: a group with no code has nothing to hand on)
	local k, now = self:Key(route), self:Now()
	-- (one invite a person: a new one takes the old one's place)
	for id, inv in pairs(self.invites) do
		if inv.key == k or now - inv.at >= SSH.INVITE_KEEP then self.invites[id] = nil end
	end
	local id = self.env.nonce()
	self.invites[id] = { key = k, route = Reply(route), name = name, group = group, at = now }
	self:Send(Reply(route), SSH.V .. "N " .. id .. "," .. group)
	return true
end

--- Invites waiting for an answer, either way, still in time: { { name, group, mine = true (you invited them) } }.
function E:Invites()
	local now, out = self:Now(), {}
	for id, inv in pairs(self.invites) do
		if now - inv.at < SSH.INVITE_KEEP then out[#out + 1] = { name = inv.name, group = inv.group, mine = true, left = SSH.INVITE_KEEP - (now - inv.at) }
		else self.invites[id] = nil end
	end
	for k, o in pairs(self.offers) do
		if now - o.at < SSH.INVITE_KEEP then out[#out + 1] = { name = o.name, group = o.group, key = k, accepted = o.accepted, left = SSH.INVITE_KEEP - (now - o.at) }
		else self.offers[k] = nil end
	end
	sort(out, function(a, b) if a.mine ~= b.mine then return not a.mine end return tostring(a.name) < tostring(b.name) end)
	return out
end

--- Whether an invite is waiting either way (yours, or one to you), the ones that ran out dropped first: the badge
--- shows, and the ticker runs, while one is (0.69.7 review: with no group the ticker never ran, so an invite to you
--- never ran out and the badge kept showing it).
function E:InvitesWaiting()
	local now = self:Now()
	for id, inv in pairs(self.invites) do if now - inv.at >= SSH.INVITE_KEEP then self.invites[id] = nil end end
	for k, o in pairs(self.offers) do if now - o.at >= SSH.INVITE_KEEP then self.offers[k] = nil end end
	return next(self.invites) ~= nil or next(self.offers) ~= nil
end

--- The invite you heard from someone, by name (any capitals, the name alone or with its realm), or the only one when
--- there's one and no name is given: the offer and its key, or nil.
function E:Offer(name)
	local now, found, n = self:Now(), nil, 0
	for k, o in pairs(self.offers) do
		if now - o.at < SSH.INVITE_KEEP then
			n = n + 1
			if name == nil or name == "" then found = found or { k, o }
			else
				local c = Canon(name)
				if Canon(o.name) == c or Canon(o.name):match("^[^%-]+") == c or (k:match("^w:(.*)$") == c) then found = { k, o } end
			end
		else
			self.offers[k] = nil
		end
	end
	if (name == nil or name == "") and n ~= 1 then return nil, n end
	if found then return found[2], found[1] end
	return nil, n
end

--- Yes to an invite (E:Offer's): asked for the code.
function E:Accept(o)
	if not o or self:Now() - o.at >= SSH.INVITE_KEEP then return false end
	o.accepted = true
	self:Send(o.route, SSH.V .. "J " .. o.id)
	return true
end

--- No thanks to an invite: they're told, and it's gone.
function E:Decline(o, key)
	if not o then return false end
	self.offers[key] = nil
	self:Send(o.route, SSH.V .. "X " .. o.id)
	if self.env.offered then pcall(self.env.offered) end
	return true
end

--- A name for a group joined by an invite: the inviter's name for it, or with "-2", "-3"... when you have a group
--- of that name with another secret.
function E:FreeLabel(label, key)
	label = SSH.GroupName(label) or SSH.DEFAULT_GROUP
	local g = self.groups[label]
	if not g or g.key == key then return label end
	for i = 2, 9 do
		local try = label:sub(1, SSH.GROUP_LEN - 2) .. "-" .. i
		local h = self.groups[try]
		if not h or h.key == key then return try end
	end
	return nil
end

--- A group joined with the secret an invite brought: remembered (env.joined), hello to everyone.
function E:JoinSecret(label, key, code, mode)
	local g = self:JoinGroup(label, key, mode or (self.groups[label] and self.groups[label].mode) or self.defaultMode)
	g.code = code
	if self.env.joined then pcall(self.env.joined, label, key, g.mode, code) end
	return g
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
	if not tag or tag:sub(1, 5) == "ping:" then
		-- (a ping too: 0.60.0 review, behind a big first sync to others, friends who had theirs heard nothing for half an
		-- hour and dropped you)
		-- (a handshake goes before any friend's items still waiting: it has HANDSHAKE_TIMEOUT to be answered. An answer,
		-- C A K, before hellos too: a login's hellos to every friend, most not running Terminal, and an answer waited
		-- behind them past the other side's timeout, never connecting. 0.60.0 review)
		local hello = text:sub(2, 2) == "H"
		for i, q in ipairs(self.queue) do
			if (q.tag and q.tag:sub(1, 5) == "data:") or (not hello and not q.tag and q.text:sub(2, 2) == "H") then at = i break end
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
		-- (the guild channel: one message, answered by each member in a group with you; the nonce is the one they echo)
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
	local wantWhole = p.wantWhole
	p.wantWhole = nil
	if same and not wantWhole and self:ModeFor(f) == f.sentMode then
		self:Share(f)
	else
		f.sentText = nil -- (sent again whole: this way, or this session of theirs, may be new)
		self:Share(f, true)
	end
	if new then
		self.env.changed()
		-- (new here: what they share asked for whole. They may have you still, the same session, and send only what
		-- changes, which would never come. 0.60.0 review: dropped after 30 minutes' silence, connected again, and their
		-- items never came back. "R n": not sent again if they already did since connecting)
		self:Send(p.route, SSH.V .. "R n")
	end
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
	-- (as made since the last change: E:Changed starts them again. 0.60.0 review: made again whole for every friend
	-- connecting, 50 ms each at login with 2000 items)
	local text, parts = self:Snapshot(mode)
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
	if letter == "D" then f.wholeAt = now end
	-- (pieces of CHUNK characters, put back together as they were; a snapshot past MAX_PIECES is cut at its last whole
	-- item, so it still reads, and the next goes whole)
	local max = (SSH.CHUNK - 3) * SSH.MAX_PIECES -- (a piece may end up to 3 short: below)
	if #payload > max then
		local cut = payload:sub(1, max - 1):match("^(.*);") or ""
		payload = cut .. "!!" .. mode
		f.sentParts = nil
	end
	local pieces = {}
	-- (each piece ends on a whole character: a name's "á" isn't cut in two, which the game may not send. 0.60.0 review)
	local at, len = 1, #payload
	repeat
		local stop = math.min(at + SSH.CHUNK - 1, len)
		while stop > at and stop < len do
			local b = payload:byte(stop + 1)
			if b < 128 or b >= 192 then break end
			stop = stop - 1
		end
		pieces[#pieces + 1] = payload:sub(at, stop)
		at = stop + 1
	until at > len
	f.sentPieces = #pieces
	-- (queued here, not by Send: none of theirs is waiting, so nothing to take the place of, and no queue walked a piece)
	for i, piece in ipairs(pieces) do
		local m = { route = f.route, text = SSH.V .. letter .. " " .. ver .. "," .. base .. i .. "," .. #pieces .. "," .. piece, tag = tag .. i, f = f }
		f.queued = (f.queued or 0) + 1
		self.queue[#self.queue + 1] = m
	end
	self:Pump()
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
	-- (a burst of them, selling greys, looting a run of mobs: the first sent now, the rest owed, sent by the tick a
	-- second on. 0.60.0 review: what you share was made again every bag event, 91 times selling 30 greys)
	local now = self:Now()
	if self.changedAt and now - self.changedAt < 1 then
		for _, f in pairs(self.friends) do f.owed = true end
		return
	end
	self.changedAt = now
	for _, f in pairs(self.friends) do self:Share(f) end
end

--- A message from the game: prefix already checked, `route` from the server's sender.
function E:Receive(route, text)
	if type(text) ~= "string" or #text > 255 then return end
	local v, letter, rest = text:match("^(%d)(%u) ?(.*)$")
	if not v then return end
	-- (the guild channel carries hellos only; everything else goes by whisper. 0.60.0 review: a guild member's "4P" there
	-- raised an error and said hello to the whole guild, every time)
	if route.kind == "guild" and letter ~= "H" then return end
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
			-- (they may have heard yours before they were in the group: said again to them, the same nonce, so an answer
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
		if not good then return end -- (no answer: a wrong key learns nothing)
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
		-- (they're missing what our last delta built on: the next goes whole. "R n": they've just connected to you as a
		-- new friend: whole, unless it already went whole since this way came up; their handshake with you not done
		-- here yet, whole when it is)
		local f = p and (p.state == "up" or p.wasUp) and self.friends[p.claim]
		if rest == "n" then
			if not f then
				if p and p.state ~= "up" then p.wantWhole = true end
				return
			end
			if (f.wholeAt or -1) >= (p.upAt or 0) then return end
		end
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
	elseif letter == "N" then
		-- (an invite: said, kept until you answer or it's too old; the same person's again said once a minute at most)
		local id, label = rest:match("^(%x+),(.+)$")
		label = label and SSH.GroupName(label)
		if not (ValidNonce(id) and label) then return end
		local k = self:Key(route)
		local old = self.offers[k]
		self.offers[k] = { id = id, group = label, name = name, route = Reply(route), at = now }
		if not (old and old.group == label and now - (old.saidAt or 0) < SSH.INVITE_SAY_GAP) then
			self.offers[k].saidAt = now
			self.env.say(L["Share: %s invites you to share bags in the group %s. Type .share accept %s to join (or .share decline %s)"]:format(name, label, name, name))
		else
			self.offers[k].saidAt = old.saidAt
		end
		if self.env.offered then pcall(self.env.offered) end
	elseif letter == "J" or letter == "X" then
		-- (their answer to your invite: only from the character you invited, while it's still waiting)
		local id = rest:match("^(%x+)$")
		local inv = id and self.invites[id]
		if not (inv and inv.key == self:Key(route) and now - inv.at < SSH.INVITE_KEEP) then return end
		self.invites[id] = nil
		local g = self.groups[inv.group]
		if letter == "X" then
			self.env.say(L["Share: %s said no thanks to %s"]:format(name, inv.group))
		elseif g and SecretOf(g) then
			self:Send(inv.route, SSH.V .. "G " .. id .. "," .. SecretOf(g))
			self.env.say(L["Share: %s accepted; connecting in %s"]:format(name, inv.group))
		end
		if self.env.offered then pcall(self.env.offered) end
	elseif letter == "G" then
		-- (the code of a group whose invite you accepted: joined, under its name or another if yours has it)
		local id, secret = rest:match("^(%x+),(.+)$")
		local k = self:Key(route)
		local o = self.offers[k]
		if not (o and o.accepted and o.id == id and now - o.at < SSH.INVITE_KEEP) then return end
		self.offers[k] = nil
		local key, code = ReadSecret(secret)
		if not key then return end
		local label = self:FreeLabel(o.group, key)
		local n = 0
		for _ in pairs(self.groups) do n = n + 1 end
		if not label or (not self.groups[label] and n >= SSH.MAX_GROUPS) then
			self.env.say(L["Share: you're in %d groups already; .share leave one, then ask %s to invite you again"]:format(SSH.MAX_GROUPS, name))
		else
			self:JoinSecret(label, key, code)
			self.env.say(label == o.group and L["Share: joined %s with %s; connecting"]:format(label, name)
				or L["Share: joined %s's group %s as %s (you have a group called %s already); connecting"]:format(name, o.group, label, o.group))
		end
		if self.env.offered then pcall(self.env.offered) end
	elseif letter == "P" then
		local f = p and (p.state == "up" or p.wasUp) and self.friends[p.claim]
		if not f then return self:Stranger(route, p) end
		f.last = now
	elseif letter == "B" then
		local f = p and p.claim and self.friends[p.claim]
		if f and (p.state == "up" or p.wasUp) then
			self:Drop(f)
			self.env.say(L["Share: %s disconnected"]:format(f.name or name))
		elseif p and not (p.state == "hello" or p.state == "challenged" or p.state == "proved") then
			-- (a handshake under way goes on: the goodbye was for the connection before it)
			self.peers[p.key] = nil
		end
		self.waiting[self:Key(route)] = nil
	end
end

--- A list of proofs ("mark:mac.mark:mac") checked against the groups offered in this handshake: the set of groups
--- proven ({ [name] = true }) and their marks in order, or nil when none is (the way marked a mismatch). Each group whose
--- proof fails is said ("Bob's code for raid doesn't match yours"). `idA`/`idB`: the hello's sender, then the
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
			else
				self.env.say(L["Share: %s's code for %s doesn't match yours"]:format(name, g.name))
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
	local q = self:Peer(route)
	if q then q.strangerAt = now end
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
		elseif p.state == "mismatch" and now - (p.mismatch or now) >= SSH.NOANSWER_KEEP then
			self.peers[k] = nil -- (the same: tried again in time, they may have typed it again. 0.60.0 review: kept for good)
		end
	end
	for k, w in pairs(self.waiting) do
		if now - w.at >= SSH.WAIT_KEEP then self.waiting[k] = nil end
	end
	-- (invites that ran out: yours unanswered said once, as theirs you said yes to and never got the code for)
	local gone = false
	for id, inv in pairs(self.invites) do
		if now - inv.at >= SSH.INVITE_KEEP then
			self.invites[id], gone = nil, true
			self.env.say(L["Share: %s didn't answer your invite to %s (they may need a newer Terminal); .share invite %s to ask again"]:format(inv.name, inv.group, inv.name))
		end
	end
	for k, o in pairs(self.offers) do
		if now - o.at >= SSH.INVITE_KEEP then
			self.offers[k], gone = nil, true
			if o.accepted then self.env.say(L["Share: %s's invite to %s ran out before it came through; ask them to invite you again"]:format(o.name, o.group)) end
		end
	end
	if gone and self.env.offered then pcall(self.env.offered) end
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
	self.invites = {} -- (yours, waiting: the groups are gone. Invites to you stay: you may still say yes)
	self.groupGen = self.groupGen + 1
	self.tried, self.retryAt = {}, nil
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

-- (what Share.lua, the game's side, reads of this file's own: one copy)
SSH._ = { SENT = SENT }
