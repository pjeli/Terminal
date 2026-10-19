"""Terminal under load: python3 tests/stress.py [friends,...] [items,...] [--groups 1,3,5] [--search 20000,100000,200000]
(needs: pip install lupa)

Runs the smoke harness for a loaded Terminal and Terminal: Share, then measures three things.

1. Sharing with friends: for each number of friends and of items each shares (".share all": every item in two places
   on average):
     snapshot   what one friend sends: its text, the messages it takes, the time to make it (SSH.Encode)
     queue      a full round to every friend at the game's pace (6 at once, then 1 a second): how long until the last
                friend has it
     receive    reading every friend's snapshot back (SSH.Decode)
     update     a bag change after that (5 items): the delta update's messages, and the round to every friend
     rows       the @shared list made from nothing (each friend's items: a row each), how many, the Lua memory the
                friends' items and rows take; then one friend's update (only their rows made again)
     search     a plain search and an @shared search over them (UI:Search: every list, as the terminal searches)

2. Groups (.share join): 1 group against several, each sharing another mode (all, limited, mats, consumables, none),
   friends spread over them (every third in two). For the side that shares: the handshake (its proofs, one per group
   in common), the first sync to everyone, then a bag change (5 items): the snapshots made (one per mode in use), the
   time it takes, the messages it sends. What friends receive is one snapshot each whatever the groups, so their side
   is part 1's.

3. Searching many entries: lists of made-up rows (compact, as @npc's) spread over many categories, every one searched by
   a plain search. Each search as the terminal runs it, a slice a frame: the time to the first results, the longest
   frame, the total, the frames, the results; in Advanced and in Simple mode (its categories).

Times are this harness's (Lua 5.1 through lupa, a mocked game): the game's own Lua is of the same kind, so the
numbers compare with tests/bench.py's, not with the game's frame budget exactly. A frame past ~16 ms (60 fps) or a
round past ~5 minutes is where it starts to show.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _env
repo = _env.enter()
from lupa import lua51 as L
rt = L.LuaRuntime(unpack_returned_tuples=True)
sys.stdout.flush()
saved = os.dup(1)
devnull = os.open(os.devnull, os.O_WRONLY)
os.dup2(devnull, 1)
try:
    rt.execute(open(os.path.join(repo, "tests", "smoke.lua"), encoding="utf-8").read())
finally:
    sys.stdout.flush()
    os.dup2(saved, 1)

args = sys.argv[1:]
def opt(name, default):
    if name in args:
        i = args.index(name)
        v = args[i + 1]
        del args[i:i + 2]
        return v
    return default
groupsArg = opt("--groups", "1,3,5")
searchArg = opt("--search", "20000,100000,200000")
friends = [int(x) for x in (args[0] if len(args) > 0 else "1,5,10,25,50").split(",")]
items = [int(x) for x in (args[1] if len(args) > 1 else "100,500,2000").split(",")]
groups = [int(x) for x in groupsArg.split(",")] if groupsArg != "none" else []
sizes = [int(x) for x in searchArg.split(",")] if searchArg != "none" else []

PRELUDE = """
debug.sethook() -- the smoke run's instruction limit
local ns, UI = _G.Terminal, _G.Terminal.UI
local SSH = ns.Ssh
local clock = os.clock
local syll = { "ka", "ro", "mi", "ten", "dar", "vel", "ish", "gor", "lan", "the", "bru", "sa", "nok", "fi", "zul", "an" }
local names = {}
--- An item's (or a row's) made-up name: syllables, so searches match some and not others.
local function NameOf(id)
	local n = names[id]
	if n then return n end
	local s, parts = id, {}
	for w = 1, 2 do
		local word = ""
		for _ = 1, 2 + (id + w) % 2 do s = (s * 1103515245 + 12345) % 2147483648; word = word .. syll[math.floor(s / 65536) % #syll + 1] end
		parts[w] = word:sub(1, 1):upper() .. word:sub(2)
	end
	n = table.concat(parts, " ")
	names[id] = n
	return n
end
C_Item.GetItemNameByID = function(id) return NameOf(id) end
C_Item.GetItemIconByID = function() return 134400 end

--- A friend's ".share all" snapshot: n items, each in one or two of four places (bags, bank, an alt's bags, the
--- warband bank); friends share half their items with the next (common mats).
local function Snap(f, n)
	local snap = { places = { { who = "Friend" .. f, where = "b" }, { who = "Friend" .. f, where = "k" },
		{ who = "Alt" .. f, where = "b" }, { who = "", where = "w" } }, items = {}, gold = 123456789, mode = "all" }
	for i = 1, n do
		local id = 100000 + ((i + f * math.floor(n / 2)) % (n * 3))
		local at = { [1 + i % 4] = 1 + (i * 7) % 200 }
		if i % 2 == 0 then at[1 + (i + 1) % 4] = 1 + (i * 3) % 20 end
		snap.items[id] = at
	end
	return snap
end
"""

# ---------------------------------------------------------------- 1. friends
res = rt.execute(PRELUDE + """
local friendsList, itemsList = ...
local ep = SSH.game
local out = {}
local function say(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
say("1. Sharing with friends")
say("%-7s %-5s | %-27s | %-12s | %-11s | %-9s | %-30s | %s", "friends", "items", "snapshot (each)", "full round", "update",
	"receive", "rows: all / one friend's update", "search: plain / @shared")

for _, n in ipairs(itemsList) do
	-- what one friend sends
	local snap = Snap(1, n)
	local t0 = clock()
	local text = SSH.Encode(snap)
	local encMs = (clock() - t0) * 1000
	local max = SSH.CHUNK * SSH.MAX_PIECES
	local pieces = math.ceil(math.min(#text, max) / SSH.CHUNK)
	-- a bag change: 5 items' counts
	local changed = Snap(1, n)
	local k = 0
	for id, at in pairs(changed.items) do
		k = k + 1
		if k > 5 then break end
		at[1] = (at[1] or 0) + 3
	end
	local delta = SSH.Delta(SSH.EncodeParts(snap), SSH.EncodeParts(changed)) or ""
	local updMsgs = math.max(1, math.ceil(#delta / SSH.CHUNK))
	for _, F in ipairs(friendsList) do
		-- every friend's snapshot read back
		local texts = {}
		for f = 1, F do texts[f] = SSH.Encode(Snap(f, n)) end
		collectgarbage("collect")
		local mem0 = collectgarbage("count")
		t0 = clock()
		ep.friends, ep.peers = {}, {}
		for f = 1, F do
			local d = SSH.Decode(texts[f])
			local c = 0
			for _ in pairs(d.items) do c = c + 1 end
			ep.friends["friend" .. f .. "@realm"] = { claim = "friend" .. f .. "@realm", name = "Friend" .. f, items = d.items,
				entries = d.entries, places = d.places, gold = d.gold, mode = d.mode, n = c, last = GetTime(),
				route = { kind = "whisper", target = "Friend" .. f }, groups = { default = true } }
		end
		local decMs = (clock() - t0) * 1000
		-- the list made again
		ns:Changed("shared")
		t0 = clock()
		local rows = ns:GetEntries(ns.providers.shared)
		local rowsMs = (clock() - t0) * 1000
		collectgarbage("collect")
		local memKB = collectgarbage("count") - mem0
		-- one friend's update: their rows made again, the list put together
		ep.friends["friend1@realm"].rows = nil
		ns:Changed("shared")
		t0 = clock()
		ns:GetEntries(ns.providers.shared)
		local oneMs = (clock() - t0) * 1000
		-- searches (the terminal's whole search: every list)
		local q = NameOf(100000 + 5):sub(1, 4):lower()
		t0 = clock(); local plain = UI:Search(q); local plainMs = (clock() - t0) * 1000
		t0 = clock(); local shared = UI:Search("@shared " .. q); local sharedMs = (clock() - t0) * 1000
		-- a full round: each friend sent your snapshot (the queue: BURST at once, then RATE a second)
		local msgs = F * pieces
		local secs = math.max(0, msgs - SSH.BURST) / SSH.RATE
		local updSecs = math.max(0, F * updMsgs - SSH.BURST) / SSH.RATE
		say("%-7d %-5d | %6d chars %3d msgs %5.1fms | %5ds %4dmsg | %2dmsg %4ds | %6.1f ms | %6d rows %6.1fms %6.0fKB %5.1fms | %6.1f / %6.1f ms (%d/%d)",
			F, n, #text, pieces, encMs, secs, msgs, updMsgs, updSecs, decMs, #rows, rowsMs, memKB, oneMs, plainMs, sharedMs, #plain, #shared)
	end
end
ep.friends, ep.peers = {}, {}
ns:Changed("shared")
return table.concat(out, "\\n")
""", rt.table_from(friends), rt.table_from(items))
print(res)

# ---------------------------------------------------------------- 2. groups
if groups:
    res = rt.execute(PRELUDE + """
local groupsList, itemsList, friendsList = ...
local out = {}
local function say(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
say("")
say("2. Groups: one against several (the side that shares; friends get one snapshot each whatever the groups)")
say("%-6s %-7s %-5s | %-36s | %-22s | %s", "groups", "friends", "items", "handshake: proofs / A message / CPU", "first sync: msgs / CPU",
	"a bag change: snapshots / CPU / msgs")
local MODES = { "all", "limited", "mats", "consumables", "none" }
local burst = SSH.BURST
SSH.BURST = 1e9 -- (the queue drained at once: CPU only, the pace is part 1's)
-- one HMAC, as the harness makes it (the game's is quicker: its bit library)
local t0 = clock()
for _ = 1, 20 do SSH.Mac("k", "I", "0123456789abcdef", "0123456789abcdef", "a@r", "b@r") end
local macMs = (clock() - t0) * 1000 / 20
for _, n in ipairs(itemsList) do
	for _, F in ipairs(friendsList) do
		for _, G in ipairs(groupsList) do
			local now, sent = 0, 0
			local function Filtered(mode)
				local s = Snap(1, n)
				if mode == "all" then return s end
				if mode == "none" then s.items = {} return s end
				local keep, k = {}, 0
				for id, at in pairs(s.items) do
					k = k + 1
					if (mode == "limited" and k % 2 == 0) or (mode == "mats" and k % 4 == 0) or (mode == "consumables" and k % 4 == 2) then keep[id] = at end
				end
				s.items = keep
				return s
			end
			local bump = 0
			local e = SSH.Endpoint({
				now = function() return now end, claim = function() return "me@realm" end,
				send = function() sent = sent + 1; return 0 end, locked = function() return false end,
				items = function(mode)
					local s = Filtered(mode)
					local k = 0
					for _, at in pairs(s.items) do k = k + 1; if k <= 5 then at[1] = (at[1] or 0) + bump end end
					return s
				end,
				nonce = function() return "0000000000000000" end, say = function() end, changed = function() end,
				eligible = function() return "x" end, matches = function() return true end, broadcast = function() return {} end,
			})
			for g = 1, G do e:JoinGroup("group" .. g, "key" .. g, MODES[(g - 1) % #MODES + 1], true) end
			local common = 0
			for i = 1, F do
				local gs = { ["group" .. ((i - 1) % G + 1)] = true }
				if G > 1 and i % 3 == 0 then gs["group" .. (i % G + 1)] = true end
				for _ in pairs(gs) do common = common + 1 end
				local claim = "friend" .. i .. "@realm"
				e.friends[claim] = { claim = claim, name = "Friend" .. i, route = { kind = "whisper", target = "Friend" .. i },
					groups = gs, items = {}, entries = {}, places = {}, n = 0, last = 0 }
			end
			-- the handshake: a proof per group in common, each side (the A message: "3A nA,nB,mark:mac...")
			local aLen = 3 + 34 + G * 41 + (G - 1)
			-- the first sync
			sent = 0
			t0 = clock()
			for _, f in pairs(e.friends) do e:Share(f, true) end
			local firstMs, firstMsgs = (clock() - t0) * 1000, sent
			-- a bag change
			now = now + SSH.SEND_GAP + 1
			bump = 3
			sent = 0
			t0 = clock()
			e:Changed()
			local changeMs = (clock() - t0) * 1000
			local snaps = 0
			for _ in pairs(e.snaps) do snaps = snaps + 1 end
			say("%-6d %-7d %-5d | up to %d (%3.1f avg) %3d chars %5.1f ms | %5d msgs %8.1f ms | %d snapshots %7.1f ms %4d msgs",
				G, F, n, G, common / F, aLen, macMs * 2 * common / F, firstMsgs, firstMs, snaps, changeMs, sent)
		end
	end
end
SSH.BURST = burst
return table.concat(out, "\\n")
""", rt.table_from(groups), rt.table_from([n for n in items if n >= 500] or items), rt.table_from([F for F in friends if F >= 10] or friends))
    print(res)

# ---------------------------------------------------------------- 3. search
if sizes:
    res = rt.execute(PRELUDE + """
local sizesList = ...
local out = {}
local function say(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
say("")
say("3. Searching many entries (made-up rows over many lists, every one in a plain search; a slice a frame)")
_G.debugprofilestop = function() return clock() * 1000 end
local queue = {}
C_Timer.After = function(_, fn) queue[#queue + 1] = fn end
local tick = 0
_G.GetTime = function() return tick end
local function frame()
	tick = tick + 0.016
	local q = queue; queue = {}
	for _, fn in ipairs(q) do fn() end
	return #q
end
local function run(label, fn)
	local t0 = clock()
	fn()
	local firstMs = (clock() - t0) * 1000
	local longest, total, frames = firstMs, firstMs, 0
	while (UI.searchJob or #queue > 0) and frames < 4000 do
		local tf = clock()
		frame()
		local ms = (clock() - tf) * 1000
		longest = math.max(longest, ms); total = total + ms; frames = frames + 1
		if not UI.searchJob and #queue == 0 then break end
	end
	say("  %-34s first %6.1f ms   longest frame %6.1f ms   total %7.1f ms  %4d frames  %4d results", label, firstMs, longest, total, frames, #UI.Results())
end
local LISTS = 24
local rows = {}
-- (Simple mode's categories: the lists spread over three, NPCs, Dungeon loot and Items, as big lists are)
local CATS = { "npcs", "loot", "items" }
for l = 1, LISTS do
	local id = "stress" .. l
	rows[l] = {}
	ns:RegisterProvider(id, { label = "Stress " .. l, aliases = { id }, simpleCategory = CATS[(l - 1) % #CATS + 1],
		collect = function(p)
			local meta = ns:CompactMeta(p, { icon = "x" }, { detail = function(t) return "row #" .. t.key end })
			local list = {}
			for i = 1, #rows[l] do
				local name = NameOf(rows[l][i])
				list[i] = setmetatable({ _compact = true, key = rows[l][i], name = name, _lname = ns.Lower(name) }, meta)
			end
			return list
		end })
end
for _, N in ipairs(sizesList) do
	-- N rows over the lists, the first lists biggest (as @npc and @loot are): a quarter, an eighth... the last the rest
	local per, left = {}, N
	for l = 1, LISTS do
		per[l] = l < LISTS and math.floor(left / 4) or left
		left = left - per[l]
	end
	local id = 1
	for l = 1, LISTS do
		rows[l] = {}
		for i = 1, per[l] do rows[l][i] = id; id = id + 1 end
		ns:Changed("stress" .. l)
		ns:GetEntries(ns.providers["stress" .. l]) -- (built, as after a list is read; not timed)
	end
	collectgarbage("collect")
	say("%d rows over %d lists (largest %d, smallest %d)", N, LISTS, per[1], per[LISTS - 1])
	local easy = ns.db.easyMode
	ns.db.easyMode = false
	UI:Hide(); frame(); frame()
	run("Advanced: 'k' (wide)", function() UI:Open("k") end)
	run("  then 'ka'", function() UI:SetQuery("ka") end)
	run("  then 'kar'", function() UI:SetQuery("kar") end)
	run("  then 'ka t' (two words)", function() UI:SetQuery("ka t") end)
	run("  then 'zzqx' (nothing)", function() UI:SetQuery("zzqx") end)
	run("  then '@stress1 ka' (one list)", function() UI:SetQuery("@stress1 ka") end)
	run("  then '@stress1 ka sort:name'", function() UI:SetQuery("@stress1 ka sort:name") end)
	UI:Hide(); frame()
	ns.db.easyMode = true
	run("Simple: 'k' (its categories, counted)", function() UI:Open("k") end)
	run("  then 'ka'", function() UI:SetQuery("ka") end)
	run("  NPCs picked: 'ka'", function() UI:SetCategory("npcs") end)
	run("  then 'ka t'", function() UI:SetQuery("ka t") end)
	run("  Dungeon loot picked: 'ka t'", function() UI:SetCategory("loot") end)
	UI:Hide(); frame()
	ns.db.easyMode = easy
	collectgarbage("collect")
end
return table.concat(out, "\\n")
""", rt.table_from(sizes))
    print(res)
