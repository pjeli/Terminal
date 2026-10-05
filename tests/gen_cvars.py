"""Build Providers/CVarList.lua: the names (and help) of the game's console settings.

WoW Forever doesn't let addons list them (C_Console.GetAllCommands fails), so Terminal ships the
names and checks each against the game (only settings this client has are shown, with its values).
Source: Ketho's BlizzardInterfaceResources (Resources/CVars.lua, pulled from the retail client).

    git clone --depth 1 https://github.com/Ketho/BlizzardInterfaceResources /tmp/bir
    python3 tests/gen_cvars.py /tmp/bir/Resources/CVars.lua
"""
import os
import sys

import lupa

src = sys.argv[1]
lua = lupa.LuaRuntime()
code = open(src, encoding="utf-8").read()
res = lua.execute(code)  # the file returns { CVars, PTR }
t = res[1] if res[1] is not None else res
rows = []
for name, v in t["var"].items():
    help_ = (v[6] or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()
    cat = v[2] if v[2] is not None else ""
    rows.append(f"{name}\t{cat}\t{help_}")
rows.sort(key=str.lower)
blob = "\n".join(rows)
assert "]==]" not in blob
out = os.path.join(os.path.dirname(__file__), "..", "Providers", "CVarList.lua")
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write("local ns = select(2, ...)\n\n")
    f.write("-- The game's console settings by name (\"name<tab>category<tab>help\" per line), for @cvar: WoW Forever\n")
    f.write("-- doesn't let addons list them, so each is checked against the game (Misc.lua). Made by tests/gen_cvars.py\n")
    f.write(f"-- from Ketho's BlizzardInterfaceResources (retail client). {len(rows)} settings.\n")
    f.write("ns.CVAR_LIST = [==[\n" + blob + "\n]==]\n")
print(len(rows), "settings,", os.path.getsize(out), "bytes")
