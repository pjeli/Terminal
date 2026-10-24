# Where Terminal's world data comes from

Terminal reads most of what it shows from the game while you play: your bags, spells, quests, the Group Finder,
flight masters' maps. A few things the game doesn't tell an addon, and Terminal carries them: where flight masters
stand, where dungeon entrances are, zones' level ranges, the fishing skill a zone needs, and .wowamp's tracks.
This page says where each of those comes from, so every value can be checked and made again.

The tables that come from data are written by a script, `tests/gen_data.py`, never typed in by hand. Each sits in
its Lua file between two marker lines (`-- generated: tests/gen_data.py <name>` ... `-- end of generated: <name>`):

```
python tests/gen_data.py all        # make every table again from its sources
python tests/gen_data.py --check    # change nothing; FAIL for a table that differs from its sources
```

The script keeps what it downloads in a cache (`TERMINAL_GAMEDATA`, default `~/.cache/terminal-gamedata`), so a
second run works offline.

What Terminal decides for itself stays in the Lua files, and the script reads it from there: which instances
WoW Forever has and in which zone, the zones' level ranges, which tracks each radio station plays.

## The game's own data

Blizzard's client tables (DB2), exported per build by [wago.tools](https://wago.tools/db2). Terminal uses the
build WoW Forever runs, **1.60.1.70532** (product `wowf`), and one classic table from WoW Classic Era
**1.15.8.66129**. URLs take the form `https://wago.tools/db2/<Table>/csv?build=<build>`.

Blizzard's interface code for the same build, [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source)
(branch `forever`, 1.60.1 (70532)), shows which of these the game itself uses: its world map draws zone levels
with `C_Map.GetMapLevels` and its Group Finder lists activities with `C_LFGList.GetActivityInfoTable`.

## Flight points

`FL.POINTS` in `Providers/Integrations/Flights.lua`, from `gen_data.py flights`.

| What | Source |
|---|---|
| The flight masters, their names ("Ratchet, The Barrens") | `TaxiNodes` (1.60.1.70532): `Name_lang` |
| Who flies from each: Alliance, Horde or both | `TaxiNodes.Flags`: 1 Alliance, 2 Horde |
| Where each stands | `TaxiNodes.Pos_0/Pos_1` on `ContinentID`, placed on the zone's map through `UiMapAssignment` (each zone map's region in world coordinates) and `UiMap` (`Type` 3: zones) |

A node is a flight master when it has an Alliance or a Horde flag and isn't a transport, a quest's path or one of
the data's left-overs (names starting "Transport", "Quest Path", "Generic", "zzOLD"). Six more nodes in the data
aren't flight masters a character learns in WoW Forever's world and are left out by their id: Nighthaven in
Moonglade (62, 63), whose flight master flies druids only, and the Eastern Plaguelands' four towers (84-87:
Plaguewood, Northpass, Eastwall and Crown Guard Tower). A point shows on its place's own map (a capital's), else its zone's
map, else the smallest map it's on. Each line in the table names its `TaxiNodes` id.

What a character has learned is read in the game, from flight masters' maps (see Flights.lua).

## Dungeon and raid entrances

`I.INSTANCES`, `I.ACTIVITY_LEVELS` and `I.RUNBACK` in `Providers/Integrations/Entrances.lua`.

| What | Source |
|---|---|
| Which instances WoW Forever has, their names, the zone each door is in | Terminal's own list (`I.INSTANCES`), by the game's map id (`Map.ID`) |
| Where each door is | Read in the game from [Questie](https://github.com/Questie/Questie)'s dungeon list (`ZoneDB:GetDungeonLocation`) or, without Questie, [QuestieDB](https://github.com/Questie/QuestieDB)'s (`LibQuestieDB.Support`), through their public interfaces. Nothing of theirs is copied into Terminal |
| ... without either | The spot the game sends your ghost to beside the entrance: `Map.Corpse_0/Corpse_1` on `CorpseMapID` (1.60.1.70532), used only when it lies in the instance's own zone (`gen_data.py instances`: `I.RUNBACK`) |
| Levels | Read in the game from its Group Finder: `C_LFGList.GetActivityInfoTable(activity)`: `minLevel` to `maxLevelSuggestion`, over the instance's activities |
| ... as the build carries them | `GroupFinderActivity.MinLevel`, `MaxLevelSuggestion` (1.60.1.70532), `gen_data.py instances`: `I.ACTIVITY_LEVELS` |

An instance with no door known yet (no Questie or QuestieDB, and no ghost spot in its zone) keeps its name and
levels, so questions and lockouts still know it, but gets no row until a door is known.

## Zone levels

`Z.LEVELS` in `Providers/Zones.lua`: Terminal's own list, kept by hand from these sources.

| Zones | Source |
|---|---|
| The classic zones | warcraft.wiki.gg, [Zones by level (Classic)](https://warcraft.wiki.gg/wiki/Zones_by_level_(Classic)), revision 6885680 (2026-09-24) |
| Riverglades: 35-45 | warcraft.wiki.gg, [Riverglades](https://warcraft.wiki.gg/wiki/Riverglades), revision 6933832 (2026-10-23) |
| Zephras Isle: 1-12 | warcraft.wiki.gg, [Zephras Isle](https://warcraft.wiki.gg/wiki/Zephras_Isle), revision 6901937 (2026-10-06) |
| Mount Hyjal: 60 | warcraft.wiki.gg, [Mount Hyjal (Forever)](https://warcraft.wiki.gg/wiki/Mount_Hyjal_(Forever)), revision 6912075 (2026-10-13) |
| Shen'dralas | No published range yet: not listed until there is one |

A second view of the same zones comes from the game: its Group Finder's "Quests & Zones" activities
(`GroupFinderActivity`, 1.60.1.70532) suggest a band for each zone, a little wider than the ranges above (about two
levels below, up to five above). Terminal shows the ranges above.

## Fishing skill

`Z.FISHING` in `Providers/Zones.lua`, from `gen_data.py fishing`.

| What | Source |
|---|---|
| The skill a zone needs | Mangos Zero's `skill_fishing_base_level` ([mangosArchives/Mangos-Zero-database-old](https://github.com/mangosArchives/Mangos-Zero-database-old/blob/develop/zp_world/skill_fishing_base_level.sql)), one number per classic area id; the skill is that number, or 1 where it is lower |
| A higher one in places | The same table's numbers for a zone's own parts (isles, lakes, coves: `AreaTable.ParentAreaID`), where higher |
| The classic area ids, by zone name | `AreaTable` (WoW Classic Era 1.15.8.66129) |

The game client doesn't carry these (the server decides them), so a server project's table is the source.
WoW Forever's own zones have none there yet, so they show no fishing skill.

## .wowamp's tracks

`Terminal_Extras/WowampStations.lua`, from `gen_data.py music`. Which tracks each station plays is Terminal's own.

| What | Source |
|---|---|
| Each track is a sound of the game | `SoundKitEntry.FileDataID` (1.60.1.70532); a file not there is dropped |
| Its length in seconds | Measured from the file itself (`https://wago.tools/api/casc/<file id>?download`), with ffprobe or mutagen |
| Its title | Made from the file's name, as the [wowdev community listfile](https://github.com/wowdev/wow-listfile) (`verified-listfile-withcapitals.csv`) gives it: "stormwind01-moment.mp3" becomes "Stormwind 01 (moment)" |

The files are only downloaded to be measured: none is shipped.

## Not used

- Wowhead: its robots.txt doesn't allow automated reading, and it has no public interface.
- Other addons' tables: Terminal doesn't copy another addon's data. Where another addon has what Terminal needs
  (Questie's dungeon doors), Terminal reads it in the game through that addon's public interface, and says so in chat
  when it can't.
