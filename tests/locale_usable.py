"""Terminal on the other client languages it's translated into: python tests/locale_usable.py [deDE ...]

Each language gets a run of its own: the whole addon loaded as that client loads it (its language file, nothing else),
then tests/locale_usable.lua. run_smoke.py runs this after the main run. Exits 1 when a language fails.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _env
repo = _env.enter() if __name__ == "__main__" else _env.REPO
from lupa import lua51 as L

LANGS = ["deDE", "esES", "esMX", "frFR", "ruRU", "zhCN"]


def run(lang):
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    rt.execute('GetLocale = function() return "%s" end' % lang)
    rt.globals().SMOKE_EXTRAS_ONLY = True
    rt.globals().SMOKE_EXTRA = rt.table_from([os.path.join(repo, "tests", "locale_usable.lua").replace("\\", "/")])
    rt.execute(open(os.path.join(repo, "tests", "smoke.lua"), encoding="utf-8").read())
    fails = rt.globals().SMOKE_FAILS
    return 1 if fails is None else int(fails)


def main(argv=None):
    langs = (sys.argv[1:] if argv is None else argv) or LANGS
    bad = []
    for lang in langs:
        n = run(lang)
        print("[%s: %s]" % (lang, "usable" if n == 0 else "%d failures" % n))
        if n:
            bad.append(lang)
    print("ALL LANGUAGES USABLE" if not bad else "LANGUAGES FAILING: " + ", ".join(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
