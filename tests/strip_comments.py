"""The release's Lua without its comments (0.68.7, the player's call: the ZIP is the game's, the GitHub repository keeps
the comments for whoever wants to read them).

    python tests/strip_comments.py --check [root]      strip every file in memory and prove it: nothing written
    python tests/strip_comments.py --in-place [root]   strip and write them (the release workflow, before packaging)

Every line stays where it was, blank where a comment was, so an error's "Core/Ask.lua:412", BugSack's stack and .debug's
traces point at the same line as the repository at that version's tag. The packager's keywords (--@localization(...)@,
--@do-not-package@ and the like) stay. Text in quotes and [[long strings]] is left alone, whatever it holds.

The proof: each file compiled before and after (Lua 5.1, the game's; string.dump keeps every instruction's line) must be
byte for byte the same; a file that isn't is left as it was and the run fails (needs: pip install lupa).
Not stripped: tests/ and docs/ (never packaged), and files that aren't .lua.
"""
import os, sys

SKIP_DIRS = {"tests", "docs", ".git", ".github"}


def _long_bracket(src, i):
    """At src[i] == "[": the level of a long bracket opening there ([[ is 0, [==[ is 2), else None."""
    j = i + 1
    while j < len(src) and src[j] == "=":
        j += 1
    if j < len(src) and src[j] == "[":
        return j - i - 1
    return None


def strip(src):
    """The Lua source without its comments, every line break kept. src and the result are str (read as latin-1, so
    any bytes go through unchanged)."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == "-" and src.startswith("--", i):
            j = i + 2
            level = _long_bracket(src, j) if j < n and src[j] == "[" else None
            if level is not None:
                close = "]" + "=" * level + "]"
                end = src.find(close, j)
                end = n if end < 0 else end + len(close)
                body = src[j + level + 2:end]
            else:
                end = src.find("\n", i)
                end = n if end < 0 else end
                if end > i and src[end - 1] == "\r":
                    end -= 1
                body = src[j:end]
            text = src[i:end]
            if body.startswith("@"):
                out.append(text) # (the packager's keywords: it reads them)
            else:
                # (what stood before it on its line, spaces and tabs, goes too; a long comment between two words on one
                # line leaves a space, so they don't run together)
                while out and out[-1] in (" ", "\t"):
                    out.pop()
                breaks = text.count("\n")
                if breaks:
                    out.append("\r\n" * breaks if "\r\n" in text else "\n" * breaks)
                elif level is not None:
                    out.append(" ")
            i = end
            continue
        if c == '"' or c == "'":
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == "\\":
                    j += 1 # (an escaped quote, backslash or line break)
                elif src[j] == "\n":
                    break # (an unfinished string: Lua says so; the proof catches it)
                j += 1
            out.append(src[i:j + 1])
            i = j + 1
            continue
        if c == "[":
            level = _long_bracket(src, i)
            if level is not None:
                close = "]" + "=" * level + "]"
                end = src.find(close, i + level + 2)
                end = n if end < 0 else end + len(close)
                out.append(src[i:end])
                i = end
                continue
        out.append(c)
        i += 1
    return "".join(out)


def lua_files(root):
    for dirpath, dirnames, files in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        if rel.split(os.sep)[0] in SKIP_DIRS:
            dirnames[:] = []
            continue
        dirnames.sort()
        for f in sorted(files):
            if f.endswith(".lua"):
                yield os.path.join(dirpath, f)


def compiler():
    from lupa import lua51
    rt = lua51.LuaRuntime(encoding=None)
    return rt.eval("""function(s)
		local f, err = loadstring(s, "=chunk")
		if not f then return nil, err end
		return string.dump(f)
	end""")


CASES = [ # (source, stripped)
    ('local s = "a -- b" -- c\nx = 1', 'local s = "a -- b"\nx = 1'),
    ("local s = 'it\\'s -- x' -- y", "local s = 'it\\'s -- x'"),
    ('x = "esc \\\\" -- c', 'x = "esc \\\\"'),
    ('x = "a\\\nb -- in the string"', 'x = "a\\\nb -- in the string"'),
    ("x = [[ -- not ]] -- yes", "x = [[ -- not ]]"),
    ("x = [==[ ]] -- ]==] y = 1", "x = [==[ ]] -- ]==] y = 1"),
    ("--[[ a\nb ]] z = 1", "\n z = 1"),
    ("--[==[ a ]] b\n]==]\nz = 1", "\n\nz = 1"),
    ("a = 1 --[[x]] + 2", "a = 1  + 2"),
    ("x = 1 - -2 --2", "x = 1 - -2"),
    ("\t-- a whole line\r\nb = 2 -- c\r\n", "\r\nb = 2\r\n"),
    ("--@do-not-package@\nL = 1\n--@end-do-not-package@", "--@do-not-package@\nL = 1\n--@end-do-not-package@"),
    ('--@localization(locale="deDE", format="lua_additive_table")@', '--@localization(locale="deDE", format="lua_additive_table")@'),
    ("--[==[@non-retail@\nx = 1\n--@end-non-retail@]==]", "--[==[@non-retail@\nx = 1\n--@end-non-retail@]==]"),
    ("t = { a = 1, -- one\n\tb = 2 } -- two", "t = { a = 1,\n\tb = 2 }"),
]


def self_test():
    """The cases above, and the proof catching a line moved: problems as text, none when all's well."""
    problems = []
    for src, want in CASES:
        got = strip(src)
        if got != want:
            problems.append("strip(%r) = %r, not %r" % (src, got, want))
    dump = compiler()
    if dump(b"a = 1\nb = 2") == dump(b"a = 1 b = 2"):
        problems.append("the proof doesn't see a line moved")
    return problems


def run(root, write):
    for p in self_test():
        print("FAIL", p)
        return False
    dump = compiler()
    before = after = 0
    bad = []
    for path in lua_files(root):
        raw = open(path, "rb").read()
        src = raw.decode("latin-1")
        new = strip(src)
        a, b = dump(raw), dump(new.encode("latin-1"))
        if a is None or a != b:
            bad.append(os.path.relpath(path, root))
            continue
        if src.count("\n") != new.count("\n"):
            bad.append(os.path.relpath(path, root) + " (lines)")
            continue
        before += len(raw)
        after += len(new)
        if write and new != src:
            open(path, "wb").write(new.encode("latin-1"))
    for b in bad:
        print("NOT THE SAME:", b)
    print("%s: %.0f KB -> %.0f KB (%.0f%% smaller)%s" % ("stripped" if write else "would strip", before / 1024,
        after / 1024, 100 * (1 - after / max(before, 1)), "" if not bad else ", %d file(s) left as they were" % len(bad)))
    return not bad


if __name__ == "__main__":
    args = sys.argv[1:]
    write = "--in-place" in args
    if not write and "--check" not in args:
        print(__doc__)
        sys.exit(2)
    roots = [a for a in args if not a.startswith("--")]
    root = roots[0] if roots else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sys.exit(0 if run(root, write) else 1)
