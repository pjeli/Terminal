"""Write tests/parse_golden.txt: what each line of tests/parse_corpus.txt is read into today (docs/FRONT_END.md, Phase 0).

    python tests/gen_parse_golden.py

Runs tests/smoke.lua's set-up and then tests/smoke/parse_golden_*.lua alone (as run_smoke.py runs them: first, before
any other file can leave its state behind; until the 1.7.4 test rework the corpus was read in whatever state the 120
files before them left, so the golden matched only a whole run), with PARSE_GOLDEN_WRITE set: they keep each line's
block instead of comparing it, and they're written out here, in the corpus's order. Run it only when a change to how lines are read is meant (or
the corpus changed), and read the diff (git diff tests/parse_golden.txt) before committing it.
Needs: pip install lupa
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _env
repo = _env.enter()
from lupa import lua51 as L
rt = L.LuaRuntime(unpack_returned_tuples=True)
import glob
extra = sorted(glob.glob(os.path.join(repo, "tests", "smoke", "parse_golden_*.lua")))
g = rt.globals()
g.SMOKE_EXTRAS_ONLY = True
g.SMOKE_FIRST = rt.table_from([p.replace("\\", "/") for p in extra])
g.PARSE_GOLDEN_WRITE = True
sys.stdout.flush()
saved = os.dup(1)
devnull = os.open(os.devnull, os.O_WRONLY)
os.dup2(devnull, 1) # (the smoke run prints its own log: sent nowhere)
try:
    rt.execute(open(os.path.join(repo, "tests", "smoke.lua"), encoding="utf-8").read())
finally:
    sys.stdout.flush()
    os.dup2(saved, 1)
out = g.PARSE_GOLDEN_OUT
if out is None:
    sys.exit("no readings kept: did tests/smoke/parse_golden_*.lua run?")
blocks = sorted((int(k), v) for k, v in out.items())
lines = ["# What each line of tests/parse_corpus.txt is read into (docs/FRONT_END.md, Phase 0), compared by",
         "# tests/smoke/parse_golden_*.lua. Made by python tests/gen_parse_golden.py: never edited by hand.", ""]
for _, b in blocks:
    lines.append("== " + b["line"])
    lines.append(b["block"])
    lines.append("")
path = os.path.join(repo, "tests", "parse_golden.txt")
with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines))
fails = g.SMOKE_FAILS
print(f"{len(blocks)} lines read into {os.path.relpath(path, repo)}" + (f" ({fails} smoke failures in the same run)" if fails else ""))
