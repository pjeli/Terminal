"""Accidental globals: writes to names never declared local, and reads of a file-level local
from code above its declaration (it reads a nil global there). Run by check.py when
luaparser is installed (pip install luaparser). Also warns (not a failure) about reads of a
never-declared name one letter away from a file-level local or a known C_* table: a typo
reads nil instead of the thing meant (C_Iten.GetItemInfo, infoCahce).
And a local inside a function named as a file-level local declared above it: the rest of that function reads the new
one, not the file's (0.69.10, the review's find: Chains.lua's `local P = ns.Filters._` hid the file's P, ns.Pipes, and
"where to learn" broke). Name it apart."""
import sys, re
from luaparser import ast, astnodes as A

# the game's C_* tables the code may read; a C_ name one letter off one of these is likely a typo
KNOWN_C = {"C_AddOns", "C_AddOnProfiler", "C_ChatInfo", "C_ClassTalents", "C_Console", "C_Container",
    "C_CurrencyInfo", "C_CVar", "C_EquipmentSet", "C_Item", "C_Map", "C_Minimap", "C_MountJournal",
    "C_PlayerInfo", "C_QuestLog", "C_Reputation", "C_Spell", "C_SpellBook", "C_SuperTrack", "C_Timer",
    "C_TooltipInfo", "C_TradeSkillUI", "C_Traits", "C_UnitAuras", "C_Macro", "C_AchievementInfo",
    "C_Texture", "C_TaskQuest", "C_QuestInfoSystem", "C_GossipInfo", "C_PetJournal", "C_ToyBox"}

def distance1(a, b):
    """Are a and b one slip apart (a letter changed, dropped, added, or two neighbours swapped)?"""
    if a == b: return False
    if len(a) == len(b):
        diff = [i for i, (x, y) in enumerate(zip(a, b)) if x != y]
        return len(diff) == 1 or (len(diff) == 2 and diff[1] == diff[0] + 1 and a[diff[0]] == b[diff[1]] and a[diff[1]] == b[diff[0]])
    if abs(len(a) - len(b)) != 1: return False
    if len(a) > len(b): a, b = b, a
    i = 0
    while i < len(a) and a[i] == b[i]: i += 1
    return a[i:] == b[i + 1:]

def line_in(src, name):
    """The line a name is first read on (luaparser's Name nodes carry no position)."""
    m = re.search(r"(?<![A-Za-z0-9_.:])" + re.escape(name) + r"(?![A-Za-z0-9_])", src)
    return src.count("\n", 0, m.start()) + 1 if m else "?"

# Scope-aware: report writes to names never declared local in an enclosing scope.
def scan(path, warnings=None, free=None, parsed=None):
    src, tree = parsed if parsed else (open(path, encoding="utf-8").read(), None)
    if tree is None:
        try: tree = ast.parse(src)
        except Exception as ex: return [("PARSE " + str(ex)[:80], "?")]
    out = []
    top = set()
    reads = {} # the never-declared names read (for the near-miss warnings)
    seen_top = set() # the file-level locals declared so far (a function below them sees them)
    depth = [0] # how many functions deep the walk is
    blocks = [] # the blocks the walk is in (the file's own block first: its locals are the file's; a top-level
    # do ... end's go when it ends)
    def shadow(name):
        if depth[0] > 0 and name in seen_top: out.append(("SHADOW " + name, '?'))
    for st in tree.body.body:
        if isinstance(st, A.LocalAssign): top |= {t.id for t in st.targets}
        if isinstance(st, A.LocalFunction): top.add(st.name.id)
    def walk(node, scope):
        if isinstance(node, A.Name):
            if node.id in top and node.id not in scope: out.append(("READ-before-local " + node.id, '?'))
            elif node.id not in scope: reads.setdefault(node.id, True)
            return
        if isinstance(node, list):
            for n in node: walk(n, scope)
            return
        if not isinstance(node, A.Node): return
        if isinstance(node, A.Block):
            inner = set(scope)
            blocks.append(node)
            for st in node.body:
                handle(st, inner)
            blocks.pop()
            return
        handle(node, scope)
    def fn_body(node, scope, extra=()):
        s = set(scope) | {a.id for a in node.args if isinstance(a, A.Name)} | set(extra)
        depth[0] += 1
        walk(node.body, s)
        depth[0] -= 1
    def handle(st, scope):
        if isinstance(st, A.LocalAssign):
            walk(st.values, scope)
            for t in st.targets:
                shadow(t.id)
                scope.add(t.id)
                if blocks and blocks[-1] is tree.body: seen_top.add(t.id)
        elif isinstance(st, A.LocalFunction):
            shadow(st.name.id)
            scope.add(st.name.id)
            if blocks and blocks[-1] is tree.body: seen_top.add(st.name.id)
            fn_body(st, scope)
        elif isinstance(st, A.Function):
            if isinstance(st.name, A.Name) and st.name.id not in scope:
                out.append((st.name.id, getattr(st,'line',None) or getattr(st.name,'line','?')))
            fn_body(st, scope)
        elif isinstance(st, A.Method):
            fn_body(st, scope, ("self",))
        elif isinstance(st, A.Assign):
            walk(st.values, scope)
            for t in st.targets:
                if isinstance(t, A.Name):
                    if t.id not in scope: out.append((t.id, getattr(t,'line','?')))
                else: walk(t, scope)
        elif isinstance(st, A.Fornum):
            walk([st.start, st.stop, st.step], scope); walk(st.body, scope | {st.target.id})
        elif isinstance(st, A.Forin):
            walk(st.iter, scope); walk(st.body, scope | {t.id for t in st.targets})
        elif isinstance(st, A.Index):
            walk(st.value, scope)
            if st.notation == A.IndexNotation.SQUARE: walk(st.idx, scope)
        elif isinstance(st, A.Invoke):
            walk(st.source, scope); walk(st.args, scope)
        elif isinstance(st, A.Field):
            if getattr(st, 'between_brackets', False): walk(st.key, scope)
            walk(st.value, scope)
        elif isinstance(st, A.AnonymousFunction):
            fn_body(st, scope)
        else:
            for k, v in vars(st).items():
                if k.startswith('_') or k in ('comments','line','start_char','stop_char','first_token','last_token'): continue
                if isinstance(v, (A.Node, list)): walk(v, scope)
    walk(tree.body, set())
    if free is not None: free.update(reads)
    if warnings is not None:
        for name in reads:
            near = None
            if name.startswith("C_"):
                near = next((k for k in sorted(KNOWN_C) if distance1(name, k)), None)
            elif len(name) >= 3: # (one-letter locals are near everything)
                near = next((k for k in sorted(top) if len(k) >= 3 and distance1(name, k)), None)
            if near: warnings.append((name, near, line_in(src, name)))
    return [(n, l) for n, l in out if n not in ALLOWED]

# the globals Terminal means to set: key binding names, the saved variable, the slash command
ALLOWED = {"BINDING_HEADER_TERMINAL", "BINDING_NAME_TERMINAL_TOGGLE", "BINDING_NAME_TERMINAL_ADVANCED_ONCE", "BINDING_NAME_TERMINAL_FUZZY", "BINDING_NAME_TERMINAL_SLASH", "TerminalDB", "TerminalCacheDB", "SLASH_TERMINAL1",
           "TerminalNotesDB"}  # (docs/example/TerminalNotes: the example addon's saved variable)

# Parsing is the slow part (luaparser: seconds for a big file), so each file is parsed once and what the checks need
# from it is kept: in memory for this run, and on disk by the file's content (tests/__pycache__/globals.json), so a run
# parses only the files changed since the last one. The cache is keyed by this script's own text too: a change to the
# checks reads every file again.
import hashlib, json, os
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "__pycache__", "globals.json")
_SELF = hashlib.sha1(open(os.path.abspath(__file__), "rb").read()).hexdigest()
_memo, _disk = {}, None

def _locals_of(tree):
    out = set()
    for st in tree.body.body:
        if isinstance(st, A.LocalFunction): out.add(st.name.id)
        elif isinstance(st, A.LocalAssign):
            for i, t in enumerate(st.targets):
                v = st.values[i] if i < len(st.values) else None
                copied = (isinstance(v, A.Name) and v.id == t.id) or (isinstance(v, A.Index) and isinstance(v.idx, A.Name)
                    and v.idx.id == t.id and isinstance(v.value, A.Name) and v.value.id == "_G")
                if not copied: out.add(t.id)
    return out

def _analyze_src(path, src):
    """One parse: the file's accidental globals, near-miss warnings, never-declared reads, and own locals."""
    try: tree = ast.parse(src)
    except Exception as ex:
        return {"found": [["PARSE " + str(ex)[:80], "?"]], "warns": [], "free": [], "locals": []}
    warns, free = [], set()
    found = scan(path, warns, free, (src, tree))
    return {"found": [list(x) for x in found], "warns": [list(w) for w in warns], "free": sorted(free),
            "locals": sorted(_locals_of(tree))}

def _load_disk():
    global _disk
    if _disk is None:
        try:
            d = json.load(open(CACHE, encoding="utf-8"))
            _disk = d["files"] if d.get("self") == _SELF else {}
        except Exception:
            _disk = {}
    return _disk

def _save_disk():
    if _disk is None: return
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        tmp = CACHE + ".tmp"
        json.dump({"self": _SELF, "files": _disk}, open(tmp, "w", encoding="utf-8"))
        os.replace(tmp, CACHE)
    except Exception:
        pass

def _key(src): return hashlib.sha1(src.encode("utf-8")).hexdigest()

def _work(args):
    path, src = args
    return _analyze_src(path, src)

def analyze_all(paths):
    """Every file's analysis, the ones not cached parsed side by side (one process per core)."""
    disk = _load_disk()
    todo = []
    for p in paths:
        if p in _memo: continue
        src = open(p, encoding="utf-8").read()
        k = _key(src)
        if k in disk: _memo[p] = disk[k]
        else: todo.append((p, src, k))
    if todo:
        results = None
        if len(todo) > 1 and (os.cpu_count() or 1) > 1:
            try:
                import multiprocessing as mp
                with mp.get_context("fork").Pool(min(len(todo), os.cpu_count())) as pool:
                    # (biggest first: the long parses don't end up last on one worker)
                    order = sorted(range(len(todo)), key=lambda i: -len(todo[i][1]))
                    got = pool.map(_work, [(todo[i][0], todo[i][1]) for i in order], chunksize=1)
                    results = [None] * len(todo)
                    for i, r in zip(order, got): results[i] = r
            except Exception:
                results = None
        if results is None: results = [_analyze_src(p, src) for p, src, _ in todo]
        for (p, _, k), r in zip(todo, results):
            _memo[p] = r
            disk[k] = r
        # (only the files still there kept: the cache doesn't grow with every edit)
        live = {_key(open(p, encoding="utf-8").read()) for p in _memo}
        for k in [k for k in disk if k not in live]: del disk[k]
        _save_disk()
    return {p: _memo[p] for p in paths}

def analyze(path): return analyze_all([path])[path]

def _shadow_lines(path, name):
    """The lines of the locals inside functions named `name` (indented, after the file-level one): luaparser gives none."""
    lines = open(path, encoding="utf-8").read().split("\n")
    top = next((i for i, l in enumerate(lines) if re.match(r"local\s+(function\s+)?([\w\s,]*?\b)?" + re.escape(name) + r"\b", l)), 0)
    at = [str(i + 1) for i in range(top + 1, len(lines))
        if re.match(r"\s+local\s+(function\s+)?([\w\s,]*?\b)?" + re.escape(name) + r"\b", lines[i])]
    return ", ".join(at) or "?"

def problems(path):
    found = [(n, l) for n, l in analyze(path)["found"]]
    out, said = [], set()
    for n, l in found:
        if n.startswith("READ"): out.append(f"{path}: " + n.replace("READ-before-local ", "reads local declared below: "))
        elif n.startswith("SHADOW "):
            name = n[7:]
            if name in said: continue
            said.add(name)
            out.append(f"{path}: lines {_shadow_lines(path, name)}: a local inside a function hides the file's own {name}: name it apart")
        else: out.append(f"{path}: global write {n} (line {l})")
    return out

def warnings(path):
    """Reads of a never-declared name one letter away from a file local or a known C_* table."""
    return [f"{path}: reads global {n} (line {l}), one letter from {near}: a typo?" for n, near, l in analyze(path)["warns"]]

def file_locals(path):
    """The names a file declares at its top level, without the ones copied from a global (local X = X / _G.X)."""
    return set(analyze(path)["locals"])

def split_reads(paths):
    """Reads of a never-declared name that another file declares as its own local: after moving code between files,
    a name left behind reads a nil global (Lua doesn't say). Returns problem lines."""
    res = analyze_all(paths)
    owners = {}
    for p in paths:
        for n in res[p]["locals"]: owners.setdefault(n, []).append(p)
    out = []
    for p in paths:
        for n in res[p]["free"]:
            if n in owners and p not in owners[n] and n not in SPLIT_OK:
                out.append(f"{p}: reads {n}, a local of {', '.join(owners[n])} (missing here: a nil global)")
    return out

# names a file declares locally that are also real globals the others may read
SPLIT_OK = {"ns", "_", "AddonList"} # (AddonList: the game's window, Addons.lua keeps its own copy)

if __name__ == "__main__":
    analyze_all(sys.argv[1:])
    bad = [p for f in sys.argv[1:] for p in problems(f)]
    print("\n".join(bad) or "no accidental globals")
    for f in sys.argv[1:]:
        for w in warnings(f): print("WARN", w)
