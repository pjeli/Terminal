"""Terminal: Share under load: python3 tests/stress.py [friends,...] [items,...]  (needs: pip install lupa)

Runs the smoke harness for a loaded Terminal and Terminal: Share, then, for each number of friends and of items each
shares (".share all": every item in two places on average), measures:

  snapshot   what one friend sends: its text, the messages it takes, the time to make it (SSH.Encode)
  queue      a full round to every friend at the game's pace (6 at once, then 1 a second): how long until the last
             friend has it
  receive    reading every friend's snapshot back (SSH.Decode)
  update     a bag change after that (5 items): the delta update's messages, and the round to every friend
  rows       the @shared list made from nothing (each friend's items: a row each), how many, the Lua memory the
             friends' items and rows take; then one friend's update (only their rows made again)
  search     a plain search and an @shared search over them (UI:Search: every list, as the terminal searches)

Times are this harness's (Lua 5.1 through lupa, a mocked game): the game's own Lua is of the same kind, so the
numbers compare with tests/bench.py's, not with the game's frame budget exactly. A search here past ~16 ms (a frame
at 60 fps) or a round past ~5 minutes is where it starts to show.
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

friends = [int(x) for x in (sys.argv[1] if len(sys.argv) > 1 else "1,5,10,25,50").split(",")]
items = [int(x) for x in (sys.argv[2] if len(sys.argv) > 2 else "100,500,2000").split(",")]

res = rt.execute("""
local friendsList, itemsList = ...
debug.sethook() -- the smoke run's instruction limit
local ns, UI = _G.Terminal, _G.Terminal.UI
local SSH = ns.Ssh
local clock = os.clock
local ep = SSH.game

-- item names the game "has": syllables, so searches match some and not others
local syll = { "ka", "ro", "mi", "ten", "dar", "vel", "ish", "gor", "lan", "the", "bru", "sa", "nok", "fi", "zul", "an" }
local names = {}
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

local out = {}
local function say(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
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
				route = { kind = "whisper", target = "Friend" .. f } }
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
