"""Keystroke timings of the parse corpus: python tests/easybench.py [runs]  (needs: pip install lupa)

Runs the smoke harness for a loaded addon (its main run, as tests/bench.py does), then types every line of
tests/parse_corpus.txt one character at a time from an empty prompt, in Simple mode and in Advanced mode, and times
each keystroke: the prompt's text set, then every frame of its search until it's done (a frame per timer batch, as in
the game). Says, per mode, the keys typed, their total, the median key and the worst key (with its line).

docs/FRONT_END.md, section 7: the per-keystroke total and the worst key must stay within +5% of 0.67.5 at every phase.
Times are noisy: run it three times (or give a number of runs) and compare the medians of the totals.
"""
import os, sys, time, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _env
repo = _env.enter()
from lupa import lua51 as L

def corpus():
    out = []
    for line in open(os.path.join(repo, "tests", "parse_corpus.txt"), encoding="utf-8"):
        line = line.rstrip("\r\n")
        if line and not line.startswith("#"):
            out.append(line)
    return out

def one_run(lines):
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    sys.stdout.flush()
    saved = os.dup(1)
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 1) # (the smoke run prints its own log: sent nowhere)
    try:
        rt.execute(open(os.path.join(repo, "tests", "smoke.lua"), encoding="utf-8").read())
    finally:
        sys.stdout.flush()
        os.dup2(saved, 1)
    rt.globals().hrclock = time.perf_counter
    return rt.execute("""
local lines = ...
debug.sethook() -- the smoke run's instruction limit
local ns, UI = _G.Terminal, _G.Terminal.UI
local clock = hrclock
_G.UnitLevel = function() return 30 end -- (as the parse golden reads the corpus: "lvl:me+3" a filter, as in the game)
_G.debugprofilestop = function() return clock() * 1000 end
-- timers run when the bench says (one batch = one frame), the game's time moving a frame each
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
local function settle()
	local n = 0
	while (UI.searchJob or #queue > 0) and n < 2000 do frame(); n = n + 1 end
end
local out = {}
for _, mode in ipairs({ "simple", "advanced" }) do
	ns.db.easyMode = mode == "simple"; UI:EasyChanged()
	local keys = {}
	for li = 1, #lines do
		local line = lines[li]
		if ns.Bar and ns.Bar.Reset then ns.Bar.Reset() end
		UI.lastScan, UI.lastExtra = nil, nil
		UI:Open(""); settle()
		for k = 1, #line do
			-- (a UTF-8 letter typed whole: never cut inside one)
			local b = line:byte(k)
			local nextb = line:byte(k + 1)
			if not (nextb and nextb >= 128 and nextb < 192) then
				frame() -- (each key on a frame of its own, as typing is)
				local t0 = clock()
				UI:SetQuery(line:sub(1, k), k)
				settle()
				keys[#keys + 1] = { ms = (clock() - t0) * 1000, line = line, k = k }
			end
		end
		UI:Hide(); settle()
	end
	out[mode] = keys
end
ns.db.easyMode = false; UI:EasyChanged()
return out
""", rt.table_from(lines))

def summary(keys):
    ms = sorted(k["ms"] for k in keys)
    worst = max(keys, key=lambda k: k["ms"])
    # (the 99th percentile key: the worst key alone is often the harness's garbage collector landing on it)
    p99 = ms[min(len(ms) - 1, int(len(ms) * 0.99))]
    return sum(ms), statistics.median(ms), p99, worst

def main():
    runs = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    lines = corpus()
    seen = {"simple": {"total": [], "p99": [], "worst": []}, "advanced": {"total": [], "p99": [], "worst": []}}
    for r in range(runs):
        res = one_run(lines)
        for mode in ("simple", "advanced"):
            keys = [res[mode][i] for i in range(1, len(res[mode]) + 1)]
            total, med, p99, worst = summary(keys)
            for k, v in (("total", total), ("p99", p99), ("worst", worst["ms"])):
                seen[mode][k].append(v)
            print(f"run {r + 1}  {mode:8}  {len(keys):5} keys  total {total:8.1f} ms  median key {med:6.3f} ms  "
                  f"99% of keys under {p99:6.2f} ms  worst key {worst['ms']:6.2f} ms "
                  f"({worst['line'][:worst['k']]!r} of {worst['line']!r})")
    if runs > 1:
        for mode in ("simple", "advanced"):
            m = {k: statistics.median(v) for k, v in seen[mode].items()}
            print(f"medians over {runs} runs, {mode}: total {m['total']:.1f} ms, 99th percentile key {m['p99']:.2f} ms, "
                  f"worst key {m['worst']:.2f} ms")

if __name__ == "__main__":
    main()
