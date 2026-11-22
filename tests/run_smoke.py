"""Run the smoke tests (needs: pip install lupa).

  python tests/run_smoke.py                 everything: tests/smoke.lua's own checks, every tests/smoke/*.lua, then
                                            Terminal on each translated language (about 8 seconds)
  python tests/run_smoke.py pawn focus      tests/smoke.lua's set-up, then only those files (tests/smoke/<name>.lua)
  python tests/run_smoke.py --alone [names] each file on its own after the set-up, every file or those named: a file
                                            that only passes after another (it borrows what that one left) fails here
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _env
repo = _env.enter()
from lupa import lua51 as L
import glob

SMOKE = open(os.path.join(repo, "tests", "smoke.lua"), encoding="utf-8").read()


def files_named(names):
    """tests/smoke/<name>.lua for each name (".lua" optional); all of them, alphabetically, when none is named."""
    if not names:
        return sorted(glob.glob(os.path.join(repo, "tests", "smoke", "*.lua")))
    out = []
    for n in names:
        p = os.path.join(repo, "tests", "smoke", n if n.endswith(".lua") else n + ".lua")
        if not os.path.exists(p):
            sys.exit("no such test file: " + p)
        out.append(p)
    return out


def run(files, files_only):
    """One run in a fresh Lua: the set-up, smoke.lua's own checks unless files_only, then the files. Its failures."""
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    if files_only:
        rt.globals().SMOKE_EXTRAS_ONLY = True
    # (the parse golden's parts first, right after the set-up and before smoke.lua's own checks: they compare readings
    # with tests/parse_golden.txt, recorded from that state by gen_parse_golden.py)
    first = [p for p in files if os.path.basename(p).startswith("parse_golden_")]
    rt.globals().SMOKE_FIRST = rt.table_from([p.replace("\\", "/") for p in first])
    rt.globals().SMOKE_EXTRA = rt.table_from([p.replace("\\", "/") for p in files if p not in first])
    sys.stdout.flush()
    rt.execute(SMOKE)
    rt.execute("io.stdout:flush()") # (Lua's lines before Python's: they share the console)
    fails = rt.globals().SMOKE_FAILS
    return rt, 1 if fails is None else int(fails)


def main(argv):
    if argv and argv[0] == "--alone":
        bad = []
        for f in files_named(argv[1:]):
            _, n = run([f], True)
            if n:
                bad.append(os.path.basename(f))
        print("EVERY FILE PASSES ALONE" if not bad else "FAILING ALONE (%d): %s" % (len(bad), ", ".join(bad)))
        return 1 if bad else 0
    if argv:
        _, n = run(files_named(argv), True)
        print("PASSED" if n == 0 else "%d FAILURES" % n)
        return 1 if n else 0
    rt, n = run(files_named([]), False)
    # frame methods the mock answered with a no-op: visibility, not a failure (one sorted line)
    unknown = rt.globals().UNKNOWN_FRAME_METHODS
    names = sorted(str(k) for k in unknown.keys()) if unknown is not None else []
    if names:
        print("[unknown frame methods: " + ", ".join(names) + "]")
    # then Terminal on each other client language it's translated into (tests/locale_usable.py: a run each)
    import locale_usable
    langs_failing = locale_usable.main([])
    # a failed check (or a test file that errored or hit the runaway guard) fails the run, so CI and scripts see it
    return 1 if n or langs_failing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
