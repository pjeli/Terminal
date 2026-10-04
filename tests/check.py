"""Syntax-check every Lua file: python3 tests/check.py  (needs: pip install lupa)"""
import glob, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _env
_env.enter()
from lupa import lua51 as L
rt = L.LuaRuntime(unpack_returned_tuples=True)
ok = True
for f in sorted(glob.glob("Terminal/**/*.lua", recursive=True)):
    if "/tests/" in f:
        continue
    src = open(f, encoding="utf-8").read()
    r = rt.eval("function(s, n) local f, e = (loadstring or load)(s, n); return {f=f, e=e} end")(src, "@" + f)
    if not r["f"]:
        print("FAIL", f, r["e"])
        ok = False
try:
    import globals as G # accidental globals (needs: pip install luaparser)
except ImportError:
    G = None
if ok and G:
    for f in sorted(glob.glob("Terminal/**/*.lua", recursive=True)):
        if "/tests/" in f:
            continue
        for p in G.problems(f):
            print("FAIL", p)
            ok = False
print("all files OK" if ok else "problems found")
sys.exit(0 if ok else 1)
