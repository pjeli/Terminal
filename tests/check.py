"""Syntax-check every Lua file: python3 tests/check.py  (needs: pip install lupa)"""
import glob, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _env
_env.enter()
from lupa import lua51 as L
rt = L.LuaRuntime(unpack_returned_tuples=True)
def lua_files(): # (with "/" on Windows too: the checks below split and match on it)
    return [f.replace("\\", "/") for f in sorted(glob.glob("Terminal/**/*.lua", recursive=True))]
ok = True
for f in lua_files():
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
    # (every file parsed once, side by side, and only those changed since the last run: globals.py's cache)
    G.analyze_all([f for f in lua_files() if "/tests/" not in f])
    for f in lua_files():
        if "/tests/" in f:
            continue
        for p in G.problems(f):
            print("FAIL", p)
            ok = False
        for w in G.warnings(f): # (a likely typo: said, not failed)
            print("WARN", w)
if ok and G:
    files = [f for f in lua_files() if "/tests/" not in f]
    for p in G.split_reads(files):
        print("FAIL", p)
        ok = False
# translations: Locales/enUS.lua up to date, the seeded translations' keys and %-values (tests/gen_locale.py)
import subprocess
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "gen_locale.py"), "--check"],
    capture_output=True, text=True)
for line in r.stdout.splitlines():
    if line.startswith("FAIL"):
        print(line)
if r.returncode != 0:
    ok = False
# the CurseForge package (0.52.15, the player's ask): only what the game runs. The files the packager would take (what
# git tracks, less .pkgmeta's ignore list and anything starting with a dot) must be code, the TOCs, Bindings.xml or the
# licence: a new folder of notes or tools has to be added to .pkgmeta's ignore list.
repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
meta = open(os.path.join(repo, ".pkgmeta"), encoding="utf-8").read()
block = meta.split("ignore:", 1)[1].split("\n\n", 1)[0] if "ignore:" in meta else ""
ignored = [l.strip()[2:].strip() for l in block.splitlines() if l.strip().startswith("- ")]
tracked = subprocess.run(["git", "ls-files"], cwd=repo, capture_output=True, text=True).stdout.split()
for f in tracked:
    if any(part.startswith(".") for part in f.split("/")) or any(f == i or f.startswith(i + "/") for i in ignored):
        continue
    if not (f.endswith((".lua", ".toc")) or f in ("Bindings.xml", "LICENSE")):
        print("FAIL the CurseForge package would carry", f, "(add it to .pkgmeta's ignore list)")
        ok = False
    elif f.endswith(".lua") and f.startswith(("tests/", "docs/")):
        print("FAIL the CurseForge package would carry", f)
        ok = False
# (0.67.4) Terminal carries no other addon's data: Leatrix's tables were replaced by cited sources (docs/DATA_SOURCES.md),
# and nothing tracked names them any more (a comment saying where data came from would be a sign some was copied back)
for f in tracked:
    path = os.path.join(repo, f)
    if f.endswith((".lua", ".toc", ".md", ".py", ".xml")) and os.path.exists(path) and f != "tests/check.py":
        if "leatrix" in open(path, encoding="utf-8", errors="replace").read().lower():
            print("FAIL", f, "names Leatrix: Terminal carries no other addon's data (docs/DATA_SOURCES.md)")
            ok = False
# (review, 0.53.6) a list is marked changed through ns:Changed (it also searches an open terminal's list again, dots a
# tab that showed it, and reads a warmDirty list again in the background), never by setting _dirty from a provider.
# Core marks its own; the terminal its refreshOnOpen and loaded lists; Questie's NPC index, freed once built, its own.
import re
DIRTY_OK = ("Core/Core.lua", "UI/UI.lua", "UI/Prompt.lua", "Providers/Integrations/Questie.lua")
for f in lua_files():
    rel = f.split("Terminal/", 1)[1]
    if "/tests/" in f or rel.startswith("tests/") or rel in DIRTY_OK:
        continue
    for i, line in enumerate(open(f, encoding="utf-8"), 1):
        if re.search(r"_dirty\s*=\s*true", line) and not line.lstrip().startswith("--"):
            print("FAIL %s:%d sets _dirty: use ns:Changed(id)" % (rel, i))
            ok = False
if not ok:
    print("problems found")
elif G:
    print("all files OK")
else:
    print("all files OK (globals not checked: pip install luaparser)")
sys.exit(0 if ok else 1)
