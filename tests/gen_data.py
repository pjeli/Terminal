"""Terminal's game data, made again from its sources: python tests/gen_data.py [flights|instances|fishing|music|cvars|all] [--check]

Each table the addon carries about the world is written here from where it comes from (docs/DATA_SOURCES.md says which
and why), never typed in by hand:

  flights    Providers/Integrations/Flights.lua  FL.POINTS        Blizzard's TaxiNodes, UiMapAssignment, UiMap (DB2)
  instances  Providers/Integrations/Entrances.lua I.ACTIVITY_LEVELS, I.RUNBACK
                                                                   Blizzard's GroupFinderActivity, Map (DB2)
  fishing    Providers/Zones.lua                 Z.FISHING        Mangos Zero's skill_fishing_base_level, named through
                                                                   Blizzard's classic AreaTable (DB2)
  music      Terminal_Extras/WowampStations.lua  the tracks       Blizzard's SoundKitEntry (DB2), the files' own lengths,
                                                                   their names from the wowdev community listfile
  cvars      Providers/CVarList.lua              ns.CVAR_LIST     Blizzard's interface code for the build (wow-ui-source,
                                                                   branch forever): the settings it names

Blizzard's tables come from wago.tools' DB2 exports of the client build below (WoW Forever: product "wowf"). What the
addon decides itself stays in the Lua files and is read from there: which instances WoW Forever has (I.INSTANCES), the
zones' level ranges (Z.LEVELS, cited in DATA_SOURCES.md), which tracks each .wowamp station plays.

Downloads are kept in a cache (TERMINAL_GAMEDATA, default ~/.cache/terminal-gamedata), so a second run is offline.
--check writes nothing: it says FAIL for a table that differs from what its sources make (and exits 1).
Needs: Python 3; for music, ffprobe on the PATH or `pip install mutagen`.
"""
import csv, io, json, os, re, subprocess, sys, urllib.request

BUILD = "1.60.1.70532"     # WoW Forever, the client the addon is for
ERA_BUILD = "1.15.8.66129" # WoW Classic Era: the classic area ids Mangos Zero's table is keyed by
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.environ.get("TERMINAL_GAMEDATA") or os.path.join(os.path.expanduser("~"), ".cache", "terminal-gamedata")
UA = {"User-Agent": "TerminalAddonDataGen/1.0 (github.com/pjeli/Terminal)"}
FISHING_SQL = "https://raw.githubusercontent.com/mangosArchives/Mangos-Zero-database-old/develop/zp_world/skill_fishing_base_level.sql"
LISTFILE = "https://github.com/wowdev/wow-listfile/releases/latest/download/verified-listfile-withcapitals.csv"

# ----------------------------------------------------------------------------------------------------------------------
# Fetching and the cache
# ----------------------------------------------------------------------------------------------------------------------

def cached(name, url):
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        print("  fetching", url)
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r:
            data = r.read()
        with open(path + ".part", "wb") as f:
            f.write(data)
        os.replace(path + ".part", path)
    return path

def db2(table, build=BUILD):
    path = cached(os.path.join(build, table + ".csv"), f"https://wago.tools/db2/{table}/csv?build={build}")
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if text.startswith("{"):
        raise SystemExit(f"wago.tools has no {table} for build {build}: {text[:200]}")
    return list(csv.DictReader(io.StringIO(text)))

def read(rel):
    with open(os.path.join(REPO, rel), encoding="utf-8") as f:
        return f.read()

FAILS = []
def write(rel, old, new, check):
    if old == new:
        print(f"  {rel}: up to date")
    elif check:
        FAILS.append(rel)
        print(f"FAIL {rel}: differs from what its sources make (python tests/gen_data.py)")
    else:
        with open(os.path.join(REPO, rel), "w", encoding="utf-8", newline="\n") as f:
            f.write(new)
        print(f"  {rel}: written")

def block(text, name, body):
    """The text with the generated block `name` (between its two marker lines) replaced by body."""
    start = f"-- generated: tests/gen_data.py {name} (do not edit by hand)\n"
    end = f"-- end of generated: {name}\n"
    i, j = text.find(start), text.find(end)
    if i < 0 or j < i:
        raise SystemExit(f"no generated block '{name}' (its marker lines are missing)")
    return text[:i + len(start)] + body + text[j:]

def num(v):
    s = ("%.1f" % v)
    return s

# ----------------------------------------------------------------------------------------------------------------------
# Map positions: a world position -> the zone maps it is on, as map percentages
# ----------------------------------------------------------------------------------------------------------------------

class Maps:
    def __init__(self):
        self.ui = {r["ID"]: r for r in db2("UiMap")}
        self.assign = [a for a in db2("UiMapAssignment") if self.ui.get(a["UiMapID"], {}).get("Type") == "3"] # zones

    def on(self, continent, x, y):
        """[(area of the map's region, uiMap, x %, y %)] for every zone map the point is on, the smallest first."""
        out = []
        for a in self.assign:
            if a["MapID"] != str(continent):
                continue
            x0, y0, x1, y1 = (float(a[k]) for k in ("Region_0", "Region_1", "Region_3", "Region_4"))
            if x0 <= x <= x1 and y0 <= y <= y1:
                u0, v0, u1, v1 = (float(a[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1"))
                # (the world's x runs north and its y west: the map's x is across, from the west, its y down, from the north)
                px = (u0 + (u1 - u0) * (y1 - y) / (y1 - y0)) * 100
                py = (v0 + (v1 - v0) * (x1 - x) / (x1 - x0)) * 100
                out.append(((x1 - x0) * (y1 - y0), int(a["UiMapID"]), px, py))
        return sorted(out)

    def name(self, ui):
        return self.ui[str(ui)]["Name_lang"]

# ----------------------------------------------------------------------------------------------------------------------
# flights: FL.POINTS
# ----------------------------------------------------------------------------------------------------------------------

# Nodes the game data holds that aren't flight masters a character learns in WoW Forever's world: the Eastern
# Plaguelands towers' paths, and Nighthaven's flight master, who flies druids only.
NOT_FLIGHT_MASTERS = {62, 63, 84, 85, 86, 87}
CONTINENTS = {0: "Eastern Kingdoms", 1: "Kalimdor"}

def flights(check):
    maps = Maps()
    points = []
    for t in db2("TaxiNodes"):
        flags, name, tid = int(t["Flags"]), t["Name_lang"], int(t["ID"])
        # a flight master: the node is flown from by the Alliance (flag 1), the Horde (2) or both; not a transport's or
        # a quest's path, nor the data's left-overs ("zzOLD...", "Generic, World target")
        if not flags & 3 or tid in NOT_FLIGHT_MASTERS or re.match(r"(zzOLD|Quest Path|Transport|Generic)", name):
            continue
        on = maps.on(int(t["ContinentID"]), float(t["Pos_0"]), float(t["Pos_1"]))
        if not on:
            continue
        place, _, zone = name.partition(", ")
        # the map it's shown on: the place's own (a city's), else its zone's ("Refuge Pointe, Arathi"), else the smallest
        def named(word):
            w = word.lower()
            return next((m for m in on if w in maps.name(m[1]).lower() or maps.name(m[1]).lower() in w), None)
        _, ui, x, y = named(place) or (zone and named(zone)) or on[0]
        side = "N" if flags & 3 == 3 else ("A" if flags & 1 else "H")
        points.append((int(t["ContinentID"]), ui, place, zone or None, round(x, 1), round(y, 1), side, tid))
    points.sort(key=lambda p: (p[0], p[2], p[6]))
    lines, cont = [], None
    for c, ui, place, zone, x, y, side, tid in points:
        if c != cont:
            lines.append(f"\t-- {CONTINENTS.get(c, c)}\n")
            cont = c
        z = '"%s"' % zone if zone else "false"
        lines.append(f'\t{{ "{place}", {z}, {ui}, {num(x)}, {num(y)}, "{side}" }}, -- TaxiNodes {tid}\n')
    rel = "Providers/Integrations/Flights.lua"
    old = read(rel)
    write(rel, old, block(old, "flights", "FL.POINTS = {\n" + "".join(lines) + "}\n"), check)
    print(f"  {len(points)} flight points")

# ----------------------------------------------------------------------------------------------------------------------
# instances: I.ACTIVITY_LEVELS, I.RUNBACK (for the instances I.INSTANCES lists)
# ----------------------------------------------------------------------------------------------------------------------

def instances(check):
    rel = "Providers/Integrations/Entrances.lua"
    old = read(rel)
    listed = old.split("I.INSTANCES = {", 1)[1].split("\n}\n", 1)[0]
    rows = re.findall(r"\{ (\d+), \"[^\"]+\", (?:true|false), \{ ([\d, ]+) \}, \d+, \{ ([\d, ]+) \}", listed)
    if not rows:
        raise SystemExit("I.INSTANCES: no rows found")
    zones_of = {}
    for m, _, zs in rows:
        zones_of.setdefault(int(m), set()).update(int(z) for z in zs.split(","))
    want_acts = {int(a) for _, acts, _ in rows for a in acts.split(",")}
    acts = {int(a["ID"]): a for a in db2("GroupFinderActivity")}
    lines = ["I.ACTIVITY_LEVELS = {\n"]
    for aid in sorted(want_acts):
        a = acts.get(aid)
        if not a:
            raise SystemExit(f"GroupFinderActivity {aid} isn't in build {BUILD}")
        lines.append(f'\t[{aid}] = {{ {a["MinLevel"]}, {a["MaxLevelSuggestion"]} }}, -- {a["FullName_lang"]}\n')
    lines.append("}\n")
    maps = Maps()
    lines.append("I.RUNBACK = {\n")
    for m in db2("Map"):
        mid = int(m["ID"])
        if mid not in zones_of or int(m["CorpseMapID"]) < 0:
            continue
        # (only where the spot is on the map of the instance's own zone: zone maps overlap where they meet)
        at = [o for o in maps.on(int(m["CorpseMapID"]), float(m["Corpse_0"]), float(m["Corpse_1"])) if o[1] in zones_of[mid]]
        if at:
            _, ui, x, y = at[0]
            lines.append(f'\t[{mid}] = {{ {ui}, {num(x)}, {num(y)} }}, -- {m["MapName_lang"]}\n')
    lines.append("}\n")
    write(rel, old, block(old, "instances", "".join(lines)), check)

# ----------------------------------------------------------------------------------------------------------------------
# fishing: Z.FISHING (for the zones Z.LEVELS lists)
# ----------------------------------------------------------------------------------------------------------------------

def fishing(check):
    rel = "Providers/Zones.lua"
    old = read(rel)
    listed = old.split("Z.LEVELS = {", 1)[1].split("\n}\n", 1)[0]
    zones = re.findall(r"\{ (\d+), (?:nil|\d+), (?:nil|\d+), \"([^\"]+)\" \}", listed)
    with open(cached("mangos-zero/skill_fishing_base_level.sql", FISHING_SQL), encoding="utf-8") as f:
        base = {int(a): int(s) for a, s in re.findall(r"\((\d+),\s*(-?\d+)\)", f.read())}
    era = db2("AreaTable", ERA_BUILD)
    # each classic zone (a top-level area of the two continents) by its name, and its parts (towns, isles, lakes)
    top, parts = {}, {}
    for r in era:
        if r["ParentAreaID"] == "0" and r["ContinentID"] in ("0", "1"):
            top.setdefault(r["AreaName_lang"].lower(), int(r["ID"]))
    for r in era:
        parts.setdefault(int(r["ParentAreaID"]), []).append(int(r["ID"]))
    lines = ["Z.FISHING = {\n"]
    for ui, name in zones:
        aid = top.get(name.lower())
        if aid is None or aid not in base:
            continue
        need = max(1, base[aid]) # (the table's skill can be below 1: anyone fishes there)
        deeper = [base[p] for p in parts.get(aid, []) if p in base and base[p] > base[aid]]
        high = max(deeper) if deeper else None
        lines.append(f'\t[{ui}] = {{ {need}, {high if high else "nil"} }}, -- {name} (area {aid})\n')
    lines.append("}\n")
    write(rel, old, block(old, "fishing", "".join(lines)), check)

# ----------------------------------------------------------------------------------------------------------------------
# music: the .wowamp stations' tracks
# ----------------------------------------------------------------------------------------------------------------------

# the files' run-together words, as the places and things are written ("AhnQiraj" -> "Ahn'Qiraj")
SPELLING = [("Ahn Qiraj", "Ahn'Qiraj"), ("Zul Gurub", "Zul'Gurub"), ("Kel Thuzad", "Kel'Thuzad"), ("Voo Doo", "Voodoo"),
    ("Barren Dry", "Barrens"), ("Gnomeragon", "Gnomeregan"), ("Thunderbluff", "Thunder Bluff"), ("Soggyplace", "Soggy Place"),
    ("Pvp", "PvP"), ("Wow", "WoW"), ("Wo W", "WoW")]

def title(path):
    """A track's title from its file's name: "stormwind01-moment.mp3" -> "Stormwind 01 (moment)",
    "NaxxramasKelThuzad1.mp3" -> "Naxxramas Kel'Thuzad 01"."""
    base = re.sub(r"\.(mp3|ogg)$", "", path.replace("\\", "/").split("/")[-1], flags=re.I)
    moment = re.search(r"-moment$", base, re.I)
    base = re.sub(r"-(moment|zone)(?=\d*$)", " ", base, flags=re.I) # ("-zone2": the second of its zone's)
    base = base.replace("_", " ").replace("-", " ")
    base = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", base) # CamelCase
    base = re.sub(r"(?<=[A-Za-z])(?=\d)", " ", base)
    words = [("%02d" % int(w)) if w.isdigit() else w[:1].upper() + w[1:] for w in base.split()]
    text = " ".join(words)
    for a, b in SPELLING:
        text = re.sub(r"\b%s\b" % a, b, text)
    return text + (" (moment)" if moment else "")

def length(path):
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path],
            capture_output=True, text=True, timeout=60)
        if out.returncode == 0 and out.stdout.strip():
            return float(out.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass
    from mutagen import File # (pip install mutagen)
    return File(path).info.length

def music(check):
    rel = "Terminal_Extras/WowampStations.lua"
    old = read(rel)
    track = re.compile(r'^(\t\t)\{ (\d+), (\d+), "((?:[^"\\]|\\.)*)" \},\n', re.M)
    ids = {int(m.group(2)) for m in track.finditer(old)}
    in_game = {int(r["FileDataID"]) for r in db2("SoundKitEntry")}
    paths = {}
    with open(cached("wowdev/verified-listfile-withcapitals.csv", LISTFILE), encoding="utf-8") as f:
        for line in f:
            i, _, p = line.rstrip("\n").partition(";")
            if i.isdigit() and int(i) in ids:
                paths[int(i)] = p
    def one(m):
        fid = int(m.group(2))
        if fid not in in_game or fid not in paths:
            print(f"  dropped file {fid}: not a sound of build {BUILD}" if fid not in in_game else f"  dropped file {fid}: no name in the listfile")
            return ""
        f = cached(f"files/{fid}.mp3", f"https://wago.tools/api/casc/{fid}?download")
        return f'{m.group(1)}{{ {fid}, {round(length(f))}, "{title(paths[fid])}" }},\n'
    write(rel, old, track.sub(one, old), check)
    print(f"  {len(ids)} tracks read")

# ----------------------------------------------------------------------------------------------------------------------
# cvars: the console settings' names (Providers/CVarList.lua), from Blizzard's own interface code for this build
# ----------------------------------------------------------------------------------------------------------------------

UI_SOURCE = "https://github.com/Gethe/wow-ui-source.git"

def ui_source():
    """Blizzard's interface code for this build (Gethe/wow-ui-source, branch forever: only its .lua files), checked out
    into the cache once; its commit must be this build's ("1.60.1 (70532)")."""
    path = os.path.join(CACHE, "wow-ui-source-forever")
    if not os.path.isdir(os.path.join(path, ".git")):
        print("  fetching", UI_SOURCE, "(forever, .lua files only)")
        subprocess.run(["git", "clone", "-q", "--depth", "1", "--filter=blob:none", "--sparse", "--branch", "forever",
            UI_SOURCE, path], check=True)
        subprocess.run(["git", "-C", path, "sparse-checkout", "set", "--no-cone", "/Interface/AddOns/**/*.lua"], check=True)
    version = subprocess.run(["git", "-C", path, "log", "-1", "--format=%s"], capture_output=True, text=True).stdout.strip()
    major, build = BUILD.rsplit(".", 1)
    if not version.startswith(f"{major} ({build})"):
        raise SystemExit(f"wow-ui-source's forever branch is {version!r}, not build {BUILD}: delete {path} to fetch it again")
    return path, version

NAME = r'"([A-Za-z][A-Za-z0-9_]*)"'
# a setting named in a call: the game's CVar calls, Blizzard's settings helpers and its CVar callback registry (a first
# argument before the name, Settings' category, is allowed)
CVAR_CALL = re.compile(r'(?:\b(?:GetCVar|GetCVarBool|SetCVar|GetCVarDefault|GetCVarNumberOrDefault|GetCVarBitfield|'
    r'SetCVarBitfield|RegisterCVar)|C_CVar\.\w+|Settings\.\w*CVar\w*|CVarCallbackRegistry:\w+)'
    r'\(\s*(?:[A-Za-z_][\w.]*\s*,\s*)?' + NAME)
# ... or in a table of settings ({ cvar = "name", ... })
CVAR_KEY = re.compile(r'\b(?:cvar|cVar|CVar|cvarName)\s*=\s*' + NAME)
# the options panel's own words for one: Settings.SetupCVarCheckbox(category, "name", LABEL, OPTION_TOOLTIP_...)
CVAR_SETUP = re.compile(r'Settings\.(?:SetupCVar\w+|RegisterCVarSetting)\(\s*\w+\s*,\s*' + NAME + r'\s*,([^\n]*)')
GLOBAL = re.compile(r'\b([A-Z][A-Z0-9_]{2,})\b')

def cvars(check):
    path, version = ui_source()
    names, words = set(), {}
    for root, _, files in os.walk(os.path.join(path, "Interface", "AddOns")):
        if "Blizzard_APIDocumentationGenerated" in root: # (the API's own documentation names tables, not settings)
            continue
        for fn in files:
            if not fn.endswith(".lua"):
                continue
            with open(os.path.join(root, fn), encoding="utf-8", errors="replace") as f:
                text = f.read()
            names.update(CVAR_CALL.findall(text))
            names.update(CVAR_KEY.findall(text))
            for name, rest in CVAR_SETUP.findall(text):
                # its label and its tooltip: the game's own strings by their global names (read in the game, in its
                # language), skipping the setting's kind ("Settings.VarType.Boolean") and constants
                said = [g for g in GLOBAL.findall(rest.split(")")[0]) if g not in ("SETTINGS",)]
                label = next((g for g in said if not g.startswith("OPTION_TOOLTIP_")), None)
                tip = next((g for g in said if g.startswith("OPTION_TOOLTIP_")), None)
                got = [g for g in (label, tip) if g]
                if got and len(got) > len(words.get(name, [])):
                    words[name] = got
    names = {n for n in names if not n.isupper()} # ("ENABLE_TEXT_TO_SPEECH": a constant's name, not a setting's)
    lines = [f"{n}\t\t{' '.join(words.get(n, []))}\n" for n in sorted(names, key=str.lower)]
    rel = "Providers/CVarList.lua"
    old = read(rel)
    body = f"-- {len(lines)} settings, from Blizzard's interface code {version}\nns.CVAR_LIST = [==[\n" + "".join(lines) + "]==]\n"
    write(rel, old, block(old, "cvars", body), check)
    print(f"  {len(lines)} settings, {len(words)} with the options panel's words")

# ----------------------------------------------------------------------------------------------------------------------

STEPS = {"flights": flights, "instances": instances, "fishing": fishing, "music": music, "cvars": cvars}

def main(args):
    check = "--check" in args
    names = [a for a in args if not a.startswith("--")] or ["all"]
    for n in (list(STEPS) if names == ["all"] else names):
        if n not in STEPS:
            raise SystemExit(__doc__)
        print(n)
        STEPS[n](check)
    if FAILS:
        sys.exit(1)

if __name__ == "__main__":
    main(sys.argv[1:])
