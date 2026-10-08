"""Search timings on a big compact list: python3 tests/bench.py [rows]  (needs: pip install lupa)

Runs the smoke harness for a loaded addon, then times searches over N NPC-like compact rows (the
shape of @npc): for each query, the time until the first results show, the longest single frame,
and the total. A search spread over frames shows its best results first and finishes later.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _env
repo = _env.enter()
from lupa import lua51 as L
rt = L.LuaRuntime(unpack_returned_tuples=True)
# the smoke run prints its own log: send it nowhere
sys.stdout.flush()
saved = os.dup(1)
devnull = os.open(os.devnull, os.O_WRONLY)
os.dup2(devnull, 1)
try:
    rt.execute(open(os.path.join(repo, "tests", "smoke.lua"), encoding="utf-8").read())
finally:
    sys.stdout.flush()
    os.dup2(saved, 1)
N = int(sys.argv[1]) if len(sys.argv) > 1 else 30000
res = rt.execute("""
local N = ...
debug.sethook() -- the smoke run's instruction limit
local ns, UI = _G.Terminal, _G.Terminal.UI
local clock = os.clock
_G.debugprofilestop = function() return clock() * 1000 end
-- timers run when the bench says (one batch = one frame)
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
local syll = { "ka", "ro", "mi", "ten", "dar", "vel", "ish", "gor", "lan", "the", "bru", "sa", "nok", "fi", "zul", "an" }
local rows, meta = {}, nil
ns:RegisterProvider("benchnpc", { label = "BNPC", aliases = { "benchnpc" }, explicit = true,
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
ns:GetEntries(ns.providers.benchnpc) -- built (as after the index), not timed
UI:Hide(); frame(); frame()
local lines = {}
local function run(label, fn)
	local t0 = clock()
	fn()
	local firstMs = (clock() - t0) * 1000
	local longest, total, frames = firstMs, firstMs, 0
	while (UI.searchJob or #queue > 0) and frames < 2000 do
		local tf = clock()
		frame()
		local ms = (clock() - tf) * 1000
		longest = math.max(longest, ms); total = total + ms; frames = frames + 1
		if not UI.searchJob and #queue == 0 then break end
	end
	lines[#lines + 1] = string.format("%-28s first results %6.1f ms   longest frame %6.1f ms   total %6.1f ms   %3d frames   %d results",
		label, firstMs, longest, total, frames, #UI.Results())
end
run("open with @benchnpc k", function() UI:Open("@benchnpc k") end)
UI:Hide(); frame()
run("again: open with @benchnpc k", function() UI:Open("@benchnpc k") end)
do -- where the time goes
	local list = ns:GetEntries(ns.providers.benchnpc)
	local t = clock(); local n = 0
	for i = 1, #list do if ns.Fuzzy.score("k", list[i].name, rawget(list[i], "_lname")) then n = n + 1 end end
	lines[#lines + 1] = string.format("  Fuzzy.score only: %.1f ms (%d matches)", (clock() - t) * 1000, n)
	t = clock(); local r = UI:SearchText("@benchnpc k")
	lines[#lines + 1] = string.format("  SearchText: %.1f ms", (clock() - t) * 1000)
end
run("  then 'ka'", function() UI:SetQuery("@benchnpc ka") end)
run("  then 'kar'", function() UI:SetQuery("@benchnpc kar") end)
UI:Hide(); frame()
run("open with @benchnpc e (wide)", function() UI:Open("@benchnpc e") end)
run("  then 'e t' (2 words)", function() UI:SetQuery("@benchnpc e t") end)
UI:Hide(); frame()
-- pure fuzzy finding (Tab+`): every list, names only
UI:Open(""); UI:FuzzyOnce()
run("fuzzy find 'k' (every list)", function() UI:SetQuery("k", 1) end)
run("  then 'ka'", function() UI:SetQuery("ka", 2) end)
run("  then 'ka t' (2 words)", function() UI:SetQuery("ka t", 4) end)
UI:Hide(); frame()
return table.concat(lines, "\\n")
""", N)
print(f"{N} rows")
print(res)
