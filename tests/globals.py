"""Accidental globals: writes to names never declared local, and reads of a file-level local
from code above its declaration (it reads a nil global there). Run by check.py when
luaparser is installed (pip install luaparser)."""
import sys
from luaparser import ast, astnodes as A
# Scope-aware: report writes to names never declared local in an enclosing scope.
def scan(path):
    src = open(path, encoding="utf-8").read()
    try: tree = ast.parse(src)
    except Exception as ex: return [("PARSE " + str(ex)[:80], "?")]
    out = []
    top = set()
    for st in tree.body.body:
        if isinstance(st, A.LocalAssign): top |= {t.id for t in st.targets}
        if isinstance(st, A.LocalFunction): top.add(st.name.id)
    def walk(node, scope):
        if isinstance(node, A.Name):
            if node.id in top and node.id not in scope: out.append(("READ-before-local " + node.id, '?'))
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
    return [(n, l) for n, l in out if n not in ALLOWED]

# the globals Terminal means to set: key binding names, the saved variable, the slash command
ALLOWED = {"BINDING_HEADER_TERMINAL", "BINDING_NAME_TERMINAL_TOGGLE", "TerminalDB", "SLASH_TERMINAL1"}

def problems(path):
    found = scan(path) or []
    return [f"{path}: " + (n.replace("READ-before-local ", "reads local declared below: ") if n.startswith("READ")
            else f"global write {n} (line {l})") for n, l in found]

if __name__ == "__main__":
    bad = [p for f in sys.argv[1:] for p in problems(f)]
    print("\n".join(bad) or "no accidental globals")
