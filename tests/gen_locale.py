"""Terminal's translations: every L["..."] key in the code, and the checks on the translations.

    python3 tests/gen_locale.py          writes Locales/enUS.lua (every key = true: what CurseForge's localization tool
                                         imports, enUS, "Lua Additive Table")
    python3 tests/gen_locale.py --check  fails when Locales/enUS.lua isn't up to date, when a seeded translation names a
                                         key the code no longer has, or when a translation's %s / %d don't match its key's
    python3 tests/gen_locale.py --import out/   one file per seeded language (its translations, for CurseForge's import)
                                         and enUS.lua (L["text"] = "text"): what .github/workflows/locales.yml imports

check.py runs --check.
"""
import os, re, sys, glob

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY = re.compile(r'\bL\["((?:[^"\\]|\\.)*)"\]')
SEED_LINE = re.compile(r'^L\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*$')
FMT = re.compile(r'%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?([sdifgxXcq])')
SKIP_DIRS = ("tests", "docs", "Locales", ".claude", ".git", ".github")


def code_files():
    out = []
    for f in sorted(glob.glob(os.path.join(REPO, "**", "*.lua"), recursive=True)):
        rel = os.path.relpath(f, REPO)
        if rel.split(os.sep)[0] in SKIP_DIRS:
            continue
        out.append(f)
    return out


def keys():
    found = {}
    for f in code_files():
        for k in KEY.findall(open(f, encoding="utf-8").read()):
            found.setdefault(k, os.path.relpath(f, REPO))
    return found


def enus_text(ks):
    lines = ["-- The English texts Terminal translates. A push to main that changes this file imports them into CurseForge's",
             "-- localization tool (.github/workflows/locales.yml; by hand: tests/gen_locale.py --import, language enUS, format",
             "-- \"Table Additions\"). Made by tests/gen_locale.py from every L[\"...\"] in the code: don't edit it.",
             "-- Not loaded by the game (not in the TOC); English is the keys themselves.",
             "local L = {}"]
    for k in sorted(ks):
        lines.append('L["%s"] = true' % k)
    return "\n".join(lines) + "\n"


def seeds(lang):
    """The translations written into Locales/<lang>.lua (between --@do-not-package@ and --@end-do-not-package@)."""
    path = os.path.join(REPO, "Locales", lang + ".lua")
    if not os.path.exists(path):
        return {}
    out, inside = {}, False
    for line in open(path, encoding="utf-8").read().splitlines():
        s = line.strip()
        if s == "--@do-not-package@":
            inside = True
        elif s == "--@end-do-not-package@":
            inside = False
        elif inside:
            m = SEED_LINE.match(s)
            if m:
                out[m.group(1)] = m.group(2)
    return out


def formats(s):
    """The values a text formats, in the order they're filled: %s %d in order, or by their number (%2$s %1$d: the
    game's string.format takes those; a translation may reorder that way, never by plain order)."""
    s = s.replace("%%", "")
    found = FMT.findall(s)
    if any(n for n, _ in found):
        if not all(n for n, _ in found):
            return ["mixed numbered and plain"]
        return [c for _, c in sorted(found, key=lambda x: int(x[0]))]
    return [c for _, c in found]


def fmt_ok(k, v):
    """A translation's %-values match its English. A "phrases: ..." key is the language's phrasings for a typed
    question, | between them: each holds one %s (where the thing asked about goes), Easy.lua's E.PHRASES."""
    if k.startswith("phrases: "):
        parts = [p for p in v.split("|") if p.strip()]
        return len(parts) > 0 and all(formats(p) == ["s"] for p in parts)
    return formats(k) == formats(v)


CODES = re.compile(r'\|c[0-9a-fA-F]{8}|\|c|\|r|\|T|\|t|\|H|\|h|\|n|\\n')


def codes(s):
    """Colour codes, textures, links and line breaks: a translation keeps as many of each as its English."""
    return sorted(c[:2] if c.startswith("|c") else c for c in CODES.findall(s.replace("||", "")))


def main():
    args = sys.argv[1:]
    ks = keys()
    text = enus_text(ks)
    path = os.path.join(REPO, "Locales", "enUS.lua")
    if "--import" in args:
        out = args[args.index("--import") + 1]
        os.makedirs(out, exist_ok=True)
        for f in sorted(glob.glob(os.path.join(REPO, "Locales", "*.lua"))):
            lang = os.path.basename(f)[:-4]
            if lang == "enUS":
                continue
            sd = seeds(lang)
            if sd:
                # (only the lines: CurseForge's Import box takes the translations, no header or `local L`)
                with open(os.path.join(out, lang + ".lua"), "w", encoding="utf-8") as w:
                    w.write("".join('L["%s"] = "%s"\n' % (k, v) for k, v in sorted(sd.items()) if k in ks))
        with open(os.path.join(out, "enUS.lua"), "w", encoding="utf-8") as w:
            w.write("".join('L["%s"] = "%s"\n' % (k, k) for k in sorted(ks)))
        print("written to", out)
        return 0
    if "--check" not in args:
        with open(path, "w", encoding="utf-8") as w:
            w.write(text)
        print("Locales/enUS.lua: %d texts" % len(ks))
        return 0
    ok = True
    # CurseForge's tool turns a key's non-ASCII letters into "u00b7"-like text (·, •: FlareUI's issue 4, Oct 2026), so
    # the key no longer matches the code and its translation never shows: keys stay ASCII (put a "  ·  " outside them)
    for k, f in sorted(ks.items()):
        if any(ord(c) > 127 for c in k):
            print("FAIL %s: a text with a non-ASCII character (CurseForge mangles those in keys): %s" % (f, k))
            ok = False
    if not os.path.exists(path) or open(path, encoding="utf-8").read() != text:
        print("FAIL Locales/enUS.lua isn't up to date: run python3 tests/gen_locale.py")
        ok = False
    for f in sorted(glob.glob(os.path.join(REPO, "Locales", "*.lua"))):
        lang = os.path.basename(f)[:-4]
        if lang == "enUS":
            continue
        sd = seeds(lang)
        stale = [k for k in sd if k not in ks]
        bad = [k for k, v in sd.items() if k in ks and not fmt_ok(k, v)]
        badCodes = [k for k, v in sd.items() if k in ks and codes(k) != codes(v)]
        for k in stale:
            print("FAIL Locales/%s.lua: translates a text the code no longer has: %s" % (lang, k))
        for k in bad:
            print("FAIL Locales/%s.lua: %%-values differ from the English: %s" % (lang, k))
        for k in badCodes:
            print("FAIL Locales/%s.lua: colour codes, links or line breaks differ from the English: %s" % (lang, k))
        if stale or bad or badCodes:
            ok = False
        if sd:
            print("  %s: %d of %d texts translated" % (lang, len([k for k in sd if k in ks]), len(ks)))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
