"""Accidental globals: writes to names never declared local, and reads of a file-level local
from code above its declaration (it reads a nil global there). Run by check.py when
luaparser is installed (pip install luaparser). Also warns (not a failure) about reads of a
never-declared name one letter away from a file-level local or a known C_* table: a typo
reads nil instead of the thing meant (C_Iten.GetItemInfo, infoCahce)."""
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
def scan(path, warnings=None, free=None):
    src = open(path, encoding="utf-8").read()
    try: tree = ast.parse(src)
    except Exception as ex: return [("PARSE " + str(ex)[:80], "?")]
    out = []
    top = set()
    reads = {} # the never-declared names read (for the near-miss warnings)
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
            for st in node.body:
                handle(st, inner)
            return
        handle(node, scope)
    def fn_body(node, scope, extra=()):
        s = set(scope) | {a.id for a in node.args if isinstance(a, A.Name)} | set(extra)
        walk(node.body, s)
    def handle(st, scope):
        if isinstance(st, A.LocalAssign):
            walk(st.values, scope)
            for t in st.targets: scope.add(t.id)
        elif isinstance(st, A.LocalFunction):
            scope.add(st.name.id); fn_body(st, scope)
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
ALLOWED = {"BINDING_HEADER_TERMINAL", "BINDING_NAME_TERMINAL_TOGGLE", "BINDING_NAME_TERMINAL_ADVANCED_ONCE", "BINDING_NAME_TERMINAL_FUZZY", "TerminalDB", "SLASH_TERMINAL1"}

def problems(path):
    found = scan(path) or []
    return [f"{path}: " + (n.replace("READ-before-local ", "reads local declared below: ") if n.startswith("READ")
            else f"global write {n} (line {l})") for n, l in found]

def warnings(path):
    """Reads of a never-declared name one letter away from a file local or a known C_* table."""
    warns = []
    scan(path, warns)
    return [f"{path}: reads global {n} (line {l}), one letter from {near}: a typo?" for n, near, l in warns]

def file_locals(path):
    """The names a file declares at its top level, without the ones copied from a global (local X = X / _G.X)."""
    src = open(path, encoding="utf-8").read()
    try: tree = ast.parse(src)
    except Exception: return set()
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

def split_reads(paths):
    """Reads of a never-declared name that another file declares as its own local: after moving code between files,
    a name left behind reads a nil global (Lua doesn't say). Returns problem lines."""
    owners = {}
    for p in paths:
        for n in file_locals(p): owners.setdefault(n, []).append(p)
    out = []
    for p in paths:
        free = set()
        scan(p, None, free)
        for n in sorted(free):
            if n in owners and p not in owners[n] and n not in SPLIT_OK:
                out.append(f"{p}: reads {n}, a local of {', '.join(owners[n])} (missing here: a nil global)")
    return out

# names a file declares locally that are also real globals the others may read
SPLIT_OK = {"ns", "_", "AddonList"} # (AddonList: the game's window, Addons.lua keeps its own copy)

if __name__ == "__main__":
    bad = [p for f in sys.argv[1:] for p in problems(f)]
    print("\n".join(bad) or "no accidental globals")
    for f in sys.argv[1:]:
        for w in warnings(f): print("WARN", w)
