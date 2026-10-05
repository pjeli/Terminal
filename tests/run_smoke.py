"""Run the smoke tests: python3 tests/run_smoke.py  (needs: pip install lupa)"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _env
repo = _env.enter()
from lupa import lua51 as L
rt = L.LuaRuntime(unpack_returned_tuples=True)
import glob
extra = sorted(glob.glob(os.path.join(repo, "tests", "smoke", "*.lua")))
rt.globals().SMOKE_EXTRA = rt.table_from([p.replace("\\", "/") for p in extra])
rt.execute(open(os.path.join(repo, "tests", "smoke.lua"), encoding="utf-8").read())
# frame methods the mock answered with a no-op: visibility, not a failure (one sorted line)
unknown = rt.globals().UNKNOWN_FRAME_METHODS
names = sorted(str(k) for k in unknown.keys()) if unknown is not None else []
if names:
    print("[unknown frame methods: " + ", ".join(names) + "]")
