"""Run the smoke tests: python3 tests/run_smoke.py  (needs: pip install lupa)"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _env
repo = _env.enter()
from lupa import lua51 as L
rt = L.LuaRuntime(unpack_returned_tuples=True)
rt.execute(open(os.path.join(repo, "tests", "smoke.lua"), encoding="utf-8").read())
