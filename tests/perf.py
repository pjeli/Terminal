"""The speed check: what a fixed set of searches costs, in Lua instructions (1.7.4).

  python tests/perf.py            compare with tests/perf_baseline.json; exits 1 when one costs over 10% more
  python tests/perf.py --update   write tests/perf_baseline.json from this build (after a change meant to cost more,
                                  or one that made something cheaper: commit it with the change)

Instructions, not time: the same build costs the same on any machine, CI's included, so a slowdown shows up as a number
that grew. Each case runs in tests/smoke.lua's set-up (its files and checks left out) over a made-up list of
PERF_ROWS compact rows, the shape of @npc, and a search spread over frames is counted until it's done. Needs lupa.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _env
repo = _env.enter()
from lupa import lua51 as L

BASELINE = os.path.join(repo, "tests", "perf_baseline.json")
SLACK = 0.10       # more than this over the baseline fails
FLOOR = 20000      # (and by more than this many instructions: a tiny case's small change isn't a slowdown)
PERF_ROWS = 5000

CASES_LUA = r"""
local N = ...
debug.sethook() -- (the set-up's runaway guard: the counts below are what's measured)
local ns, UI = _G.Terminal, _G.Terminal.UI
-- timers run when a frame says, one batch a frame; the clock moves a frame a time
local queue = {}
C_Timer.After = function(_, fn) queue[#queue + 1] = fn end
local tick = 2000
_G.GetTime = function() return tick end
local function frame()
	tick = tick + 0.016
	local q = queue; queue = {}
	for _, fn in ipairs(q) do fn() end
	return #q
end
-- a made-up list the shape of @npc: N compact rows, two made-up words each (the same every run)
local syll = { "ka", "ro", "mi", "ten", "dar", "vel", "ish", "gor", "lan", "the", "bru", "sa", "nok", "fi", "zul", "an" }
local rows, meta = {}, nil
ns:RegisterProvider("perfnpc", { label = "PNPC", aliases = { "perfnpc" }, explicit = true,
	collect = function(p)
		meta = meta or ns:CompactMeta(p, { icon = "x" }, { detail = function(t) return "NPC #" .. t.key end })
		if #rows == 0 then
			local s = 7
			for i = 1, N do
				local parts = {}
				for w = 1, 2 do
					local name = ""
					for _ = 1, 2 + (i + w) % 2 do s = (s * 1103515245 + 12345) % 2147483648; name = name .. syll[math.floor(s / 65536) % #syll + 1] end
					parts[w] = name:sub(1, 1):upper() .. name:sub(2)
				end
				local name = table.concat(parts, " ")
				rows[i] = setmetatable({ _compact = true, key = i, name = name, _lname = ns.Lower(name) }, meta)
			end
		end
		return rows
	end })
ns:GetEntries(ns.providers.perfnpc) -- (made before, as after a login's indexing: not counted)
UI:Hide(); frame(); frame()

-- instructions, counted a thousand at a time by the hook
local count = 0
local function Counted(fn)
	count = 0
	debug.sethook(function() count = count + 1 end, "", 1000)
	fn()
	local frames = 0
	while (UI.searchJob or #queue > 0) and frames < 2000 do
		frame()
		frames = frames + 1
	end
	debug.sethook()
	return count * 1000
end

local out = {}
local function Case(name, fn, easy)
	ns.db.easyMode = easy and true or false
	UI:EasyChanged()
	out[name] = Counted(fn)
	UI:HideNow(); frame(); frame()
end
-- (searching: a big list, letters and words; Simple mode's reading; questions; filters; chains; Alt+`)
Case("open @perfnpc, 1 letter", function() UI:Open("@perfnpc k") end)
Case("type 3 more letters", function() UI:Open("@perfnpc k"); UI:SetQuery("@perfnpc kaml", 13) end)
Case("plain words, every list", function() UI:Open("ro dar") end)
Case("a close spelling", function() UI:Open("@perfnpc kamllvel") end)
Case("Simple: everyday words", function() UI:Open("nearest vendor") end, true)
Case("Simple: a question", function() UI:Open("what should i do") end, true)
Case("Simple: dates and numbers", function() UI:Open("loot since yesterday worth more than 1g") end, true)
Case("filters: item quality", function() UI:Open("@item q:rare+ sort:name") end)
Case("filters: upgrades", function() UI:Open("@item is:upgrade") end)
Case("a chain: sources", function() UI:Open("linen cloth > sources") end)
Case("group by", function() UI:Open("@perfnpc ka | group by kind") end)
Case("Alt+` of a Simple line", function() ns.Easy.ToAdvanced("rare swords under level 30 sorted by level") end, true)
Case(".explain", function() ns:FindCommand("explain").run("@item q:rare+ lvl:20-30 sort:-level | first 5") end)
-- (1.8.10; set up after the other cases, whose item filters it would change) a list of items the shape of @loot, every tenth with a creature bonus and every seventh an area one; their
-- tooltips read once before (as after a first search): what a bonus search costs per keystroke
local items, imeta = {}, nil
local TIP_PLAIN, TIP_FOE, TIP_AREA = { lines = { { leftText = "x" }, { leftText = "Equip: +5 Stamina." } } },
	{ lines = { { leftText = "x" }, { leftText = "Equip: +20 Attack Power when fighting Trolls." } } },
	{ lines = { { leftText = "x" }, { leftText = "Use: Restores 40 mana. This effect is doubled in Haunted areas." } } }
_G.C_TooltipInfo = { GetItemByID = function(id) return (id % 10 == 0 and TIP_FOE) or (id % 7 == 0 and TIP_AREA) or TIP_PLAIN end }
C_Item.GetItemInfoInstant = function(id) return id, "Armor", "Misc", "INVTYPE_TRINKET", 0, 4, 0 end
C_Item.IsItemDataCachedByID = function() return true end
ns:RegisterProvider("perfitem", { label = "PItem", aliases = { "perfitem" }, explicit = true,
	collect = function(p)
		imeta = imeta or ns:CompactMeta(p, { icon = "x" }, { detail = function(t) return "Item #" .. t.itemID end })
		if #items == 0 then
			for i = 1, N do
				local name = "Charm " .. i
				items[i] = setmetatable({ _compact = true, key = i, itemID = 300000 + i, name = name, _lname = ns.Lower(name) }, imeta)
			end
		end
		return items
	end })
ns:GetEntries(ns.providers.perfitem)
for i = 1, N do ns.Bonus.Of(300000 + i) end
Case("bonus: filter", function() UI:Open("@perfitem bonus:troll") end)
Case("group by bonus", function() UI:Open("@perfitem | group by bonus") end)
return out
"""


def measure():
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    g.SMOKE_EXTRAS_ONLY = True
    g.SMOKE_EXTRA = rt.table_from([])
    sys.stdout.flush()
    saved, devnull = os.dup(1), os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 1) # (the set-up's own log: sent nowhere)
    try:
        rt.execute(open(os.path.join(repo, "tests", "smoke.lua"), encoding="utf-8").read())
        out = rt.execute(CASES_LUA, PERF_ROWS)
        rt.execute("io.stdout:flush()")
    finally:
        sys.stdout.flush()
        os.dup2(saved, 1)
    return {str(k): int(v) for k, v in out.items()}


def main(argv):
    now = measure()
    if "--update" in argv:
        with open(BASELINE, "w", encoding="utf-8", newline="\n") as f:
            json.dump(dict(sorted(now.items())), f, indent=2)
            f.write("\n")
        print("perf baseline written: %d cases (tests/perf_baseline.json)" % len(now))
        return 0
    if not os.path.exists(BASELINE):
        print("no tests/perf_baseline.json: python tests/perf.py --update")
        return 1
    base = json.load(open(BASELINE, encoding="utf-8"))
    bad = []
    for name in sorted(set(now) | set(base)):
        b, n = base.get(name), now.get(name)
        if b is None or n is None:
            bad.append(name)
            print("  %-30s %s" % (name, "new: not in the baseline" if b is None else "gone: in the baseline only"))
            continue
        change = (n - b) / b if b else 0.0
        slower = n > b * (1 + SLACK) and n - b > FLOOR
        if slower:
            bad.append(name)
        print("  %-30s %12s instructions  %+6.1f%%%s" % (name, format(n, ","), change * 100, "  SLOWER" if slower else ""))
    if bad:
        print("SPEED CHECK FAILED: %s. Meant? python tests/perf.py --update, and commit the baseline with it." % ", ".join(bad))
        return 1
    print("SPEED CHECK PASSED (each within %d%% of tests/perf_baseline.json)" % int(SLACK * 100))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
