# .console (in main since 0.67.8; built on branch `console-dev`)

A Linux-like console over everything Terminal knows. `.console` (also `.tty`, `.tsh`) opens it; `` ` `` steps out
(apps in it pause), `.console` comes back to everything as it was; `.console reset` starts again.


The console (and `.atop`) live in Terminal Extras, the load-on-demand addon beside Terminal (the player's call): Terminal
has stand-ins for `.console` and `.atop` (Apps/Extras.lua) that load it the first time one is run.

## Files

- `Terminal_Extras/Console/FS.lua` (`ns.ConsoleFS`): the file system. Every list Terminal searches is a directory at the root,
  named by its first @kind word (`/item`, `/npc`, `/spell`, `/questie`...); each row is a file named by the row's name
  (a `/` in a name becomes U+2215, a name twice gets `~2`; a `_` typed stands for a space). A file's contents are its
  tooltip, read through a recorder that stands in for a GameTooltip (any `Set<X>` with a `C_TooltipInfo.Get<X>` reads
  that data; nothing there: a hidden game tooltip read line by line; nothing there either, for an item: its item data),
  then the row's search words. Also `/bin` (commands), `/etc` (motd, hostname, os-release, passwd: your own
  characters), `/proc` (uptime, meminfo, loadavg, version), `/tmp` (what `>` writes, this session only). Nothing in it
  yields.
- `Terminal_Extras/Console/Shell.lua` (`ns.Shell`): tsh. Words, quotes, `\` escapes, globs, `|`, `;`, `&&`, `||`, `>`/`>>` (into
  /tmp only), `#`, `!!`/`!N`/`!word`, aliases. Commands: ls cd pwd tree find locate cat less head tail stat file grep
  wc count sort uniq cut field where nl tac rev shuf tr sed sum seq xargs tee echo clear history help man which
  alias unalias whoami hostname uname date uptime ping free sleep true false sudo touch rm mkdir vim search link pin
  font fortune murlocsay neofetch split exit layout ps kill. Any Terminal command runs too, with or without the dot
  (`top` is `.atop`); its chat output is caught into the pane. grep: smart case, a small regular-expression subset
  turned into Lua patterns (`a|b`, `\d \w \s \b`, sets), `-ivclnrwFhm`.
- `Terminal_Extras/Console/Commands.lua` (0.69.8, split from Shell.lua as they were): the looking-around commands (ls,
  cd, pwd, tree, find, locate, cat, head, tail, stat, file) and the pipe ones (wc, sort, uniq, cut...). They read the
  shell's shared helpers through `ns.Shell` (`SH._` for those it keeps as locals).
- `Terminal_Extras/Console/Console.lua` (`ns.Console`): the window manager. Up to four panes, layouts grid (default), tall, wide,
  mono, plus zoom; panes glide to their places (0.2 s; none with Terminal's animations off). Each pane: a scrollback
  of 2000 lines, a real EditBox (clipboard works) with its text drawn over in colour and a block caret, its own text
  size. A line runs as a coroutine, 8 ms a frame shared by the running panes; Ctrl+C stops it. An app a command opens
  (any Panel app) is docked into that pane: re-anchored, scaled to fit, FULLSCREEN strata, its OnKeyDown wrapped so
  the console's keys still work, its `Close` wrapped to know it closed.

## ls -l, field, where

`ls -l` prints a line of columns per file, one word each, the name last: `mode kind id role title lvl count dist zone
name`, `-` where a row has none (spaces as `_`). `man ls` says what each is. Shown: the columns any file listed has (a
file named alone: all), or `-o dist,title,name` / `-o all`. The cells are parted by tabs, which the pane lines up at
measured stops. Every line also carries all its columns, shown or not, ahead of its text as an empty link
(`|Htsh:...|h|h`) the pane strips before drawing and `FS.Strip` drops, so `field`, `where` and `sort -k` read any
column, also after `grep`; `field path` (never shown) is the whole path, for `xargs`. `ls -N` lists nearest first. A
`>` inside a word is the word's (`where lvl>20`); a redirect needs the space before it.

- mode: `d`/`-`/`c` (directory, row, system file), then `r` a tooltip, `x` Enter does something, `s` Shift+Enter does,
  `l` a chat link, `n` a place in the world, `u` an upgrade for you (loot rows: Terminal's is:upgrade, `FS.IsUpgrade`).
- id: the game's number, `item:2589`, `spell:133`. role: an NPC's roles from Questie's flags (`repair,vendor`). title:
  its Questie title (`Reagent_Vendor`), a loot row's boss, an attunement step's text. zone: a loot row's instance.
  dist: yards from you (`I.RowYards`).

## Folders

A list can be folders by what its rows are (`FS.GROUPS[provider id]`: a function per depth giving the folder's name,
nil to stay where it is): `/loot/<instance or crafting section>/<boss>/<item>`, `/recipe/<profession>/<recipe>`,
`/mailbox/<zone>/<mailbox>`, `/npc/<zone>/<role>/<npc>` (no role: right in its zone; no zone known: at the top). `FS.Tree(d)` makes them once per rebuild of the list's rows (`root`, `folderOf`); names
are told apart within a folder only. Folders come first in `ls`, blue with their `/`; `ls -l` gives a folder's line
with how many rows are under it. `ls -R` lists every folder under it after its path; `find <dir> -type f` gives every
file's path, flat; `ls -lR /loot | where zone~lordaeron` and `ls -lR /mailbox | sort -n -k dist | head -3` (the
nearest mailbox anywhere) read every file's line. tree, locate, grep -r, globs, Tab and search's paths all know them.

`search` prints a row of a list as its path; a row that isn't a file but leads to another search ("search bored",
"what should i do": the suggestions' `searchText`, Enter's search in the panel) ends with `→ search <that search>`,
the next thing to type, and the answer's note loses the panel's "Enter searches for it".

## Rows that are directories

A list may give a row files of its own (`FS.CHILDREN[provider id]`): Attune's attunements are directories of their
steps, named by Attune's numbers (`/attune/The Dalaran Key/step2a`, side quests `side1`...). ls, cd, cat, ls -l (kind
`attune/The_Dalaran_Key`), grep -r and Tab go into them.

## Zones' files

A zone's file in /map adds `levels:` and `fishing:` lines from Zones.lua (`FS.ZoneLines`: the skill it needs, deeper
spots', and yours: enough or not yet): `grep -r fishing /map`, `cat /map/Ashenvale`.

## What NPCs sell

An NPC's file has `role:` and `sells:` lines (six items a line). Questie keeps sellers per item, so the first `cat` or
`grep` on /npc reads every item's vendors once (`FS.BuildSold`, the shell waiting while it does) and keeps NPC -> items
for the session: `grep -rl 'sells:.*arrow' /npc | xargs ls -l | sort -n -k dist | head -3`.

## Other addons as mounts

`FS.MOUNTS` names the addons Terminal reads and the lists each one fills: AtlasLoot (/loot), Questie or QuestieDB (/npc
/questie /mailbox), Attune (/attune), Syndicator or BagBrother (/stored /bank), What's Training or TrainerSpells
(/training), Ace3 (/addonoptions), Auctionator (no list: its values and questions). `FS.Mounts()` says which is in use
and how full each is (rows made; AtlasLoot's: its rows, less those still waiting on their names). `df [-ha]`, `mount`
and `/etc/fstab` (those not installed commented out) show it; `umount` (hidden) says the target is busy. Lists
Terminal fills itself (items, spells, flight paths, entrances) aren't mounts. Terminal: Share is NFS (`remotes`): each friend connected
a mount of its own (`Bob:/bags on /shared/Bob type nfs4 (ro,vers=4,sharing=limited)`, the character's name, never a
Battle.net one), your groups /etc/fstab's exports (`share:<group> /shared nfs4 ro,auto,_netdev`); /shared is a folder a
friend (`FS.GROUPS.shared`, by the row's owner).

## Acting on files

`pin <file>`: the map waypoint and arrow on an NPC (Questie's spawn, `I.NpcPin`), a spot row (mailbox, flight master,
entrance: `I.PinObject`) or a zone (`Maps.PinOnly`), as Enter / Shift+Enter set them; `pin -c` clears it.
`link <file>` puts its link in the chat box. Nothing else a row's Enter does (game-pressed) runs from the console.

## less and aliases

`cmd | less` / `less file` keeps every line (the scrollback keeps 2000): Space/PageDown, b/PageUp, j/k/arrows, g/G,
`/` and `?` search, `n`/`N`, q or Esc. The typed keys are read from the pane's box (which stays empty). Ctrl+R (or
Ctrl+B `[`) opens the pane's scrollback in it, searching back from the end.
`alias name='text'` (kept in `db.console.aliases`) puts the text where the name is typed first in a command, the
words after it kept; an alias isn't read again inside itself; `unalias`. Aliases are read where a line is typed, not by
xargs.

## awk

`Terminal_Extras/Console/Awk.lua` (`SH.Awk`): the real awk's everyday part, compiled to closures (`AWK.Compile`) and run per line
inside a pcall (`AWK.Run`; next, exit, break and continue are errors caught there; loops stop at `AWK.LOOP_MAX`).
Rules, BEGIN/END, $0 $1 $NF, NR NF, variables and arrays (for-in, in, delete), arithmetic, comparisons, ~ !~ /regex/
(SH.Matcher, case as typed), && || !, ?:, concatenation, assignments, ++ --, if/else, while, for, print, printf,
length substr index split tolower toupper int sprintf; -F, -v. tsh's own: an ls -l line's columns are variables
(`dist`, `zone`, `name`, `path`...; a variable you set wins), a value with a number in front compares as that number
(312yd), and `print` alone gives the line as it came (colours and the hidden columns kept). `where` and `field` stay
as the short forms.

## neofetch and art lines

None of the game's fonts is monospace, so ASCII art drifts. `SH.Mono(art, cols, rest)` makes an art line
(`|Htshm:<bytes of art>:<cols>|h|h` then the art and the rest; stripped, piped or printed elsewhere it's the plain
text): the console draws each of the art's characters in a slot of one width (`Width("0")`, centred, colour codes
kept), spaces as empty slots, and the rest after `cols` slots and `C.MONO_GAP`, so every line of one picture lines up.
`neofetch` (fetch, screenfetch) is its first user: your class's picture (`SH.FETCH_LOGOS`, each line its text and a
string of colour letters as long: `c` the class's colour, the rest `SH.FETCH_PAINT`'s gold, steel, leather, white,
red, fel, leaf, blue; `SH.FetchArt` paints runs): a long sword through a shield, a glowing hammer, a curved bow
and arrow, the rogue's dagger, the priest's white staff with its blue gem, a storm cloud's lightning, a wizard's hat
with a curled tip, the warlock's clawed demon hand in fel fire, a tree (the class icons where there's one to follow); Terminal's own for a class with none. The class's
colour (`ns.ClassHex`, else `SH.FETCH_CLASS_HEX`) also colours you@host and the keys. `-c CLASS` shows another class
(`SH.FetchClassNamed`: the file name, the game's own name, 3+ letters of either), `-n` the next one each run, round
`SH.FETCH_ORDER` from yours (`SH.fetchAt`, this session). Beside it the system's facts only (the player's call: the
character as hardware was too much): OS, Host (realm), Kernel (Terminal's version and the build), Uptime
(`FS.SessionSeconds`: the session, else since Terminal loaded; GetSessionTime may say 0), Packages (addons, loaded),
Resolution, Locale; then two rows of colour blocks.

## matrix (an easter egg)

`matrix` (`cmatrix`) rains green letters down the pane, as cmatrix does: a FontString per column of letters, its lines
the rows, each column's drop a white head and a fading trail, drawn 20 times a second; any key stops it (the console's
own keys still work). Commands marked `hidden` aren't in help, /bin or Tab; `man` still knows them.

## sudo rm -rf / (an easter egg)

`sudo rm -rf /` (also `/*` and `~`) "removes" every list (a red line each), then `C.Wipe`: a black frame over the whole
screen (TOOLTIP strata, ignoring UIParent's alpha) for `C.BLACK_HOLD` s, the console stepped out of, the black fading
out over `C.BLACK_FADE` s onto the interface as it was. Nothing real is touched, and the pane that ran it looks as if it
never had: the lines the command printed (`p.since`, its prompt line too) and its history line are taken back, so
`.console` comes back to everything as it was.
Without sudo, `rm -rf /` gives GNU rm's refusal.

## Hooks into the rest

- `Panel.Opening` and `UI:Open` leave the console's docked apps alone (`Panel.Keeps`); `UI:Open` closes the console
  itself, which steps out.
- `Zen.Force(on)`: the console is always zen, whatever `.zen` says.
- `I.NpcPin` (Questie.lua) is exported for `pin`.

## ls --icons

`ls --icons` (`opts.I`) puts each row's game icon (`SH.IconText(e)`: `|T<icon>:0|t`, the line's height) in a cell of its
own before the name, parted by a tab like ls -l's columns, so the console lines the names up after the icons and the
selection's and clicks' character mapping still holds (`FS.Strip` drops the icon). A folder shows its own row's icon
or its first file's, at any depth (`SH.FolderIcon`); a list at the root its tree's, once the list is made (never built
for an icon). `alias ls='ls --icons'` for always. Unverified in game: the icon's size against the line.

## Tab past the command word

`SH.Complete` asks `SH.CompleteArg` first for any word after a pipeline's command (not after `>`/`>>`: those are
paths): a word starting with `-` gets the command's options, read from its usage line (`SH.OptionsOf`: "[-lrRN]" is
four, "-name glob" one); `where`/`filter` the ls -l columns (no space after one: the comparison comes next), then
values for `zone` (Terminal's zones) and `kind` (the lists) after the comparison; `field` and `sort -k` a column;
`ls -o` the last of a comma list; `man` and `which` (`args = "cmd"`) the commands; `unalias` your aliases; `layout`
and `font` their words (`SH.FIXED_ARGS`); `neofetch -c` the classes. An alias is read as the command it starts with.
Anything else: paths, as before.

## Clicking the output

The shell links the paths it prints (`SH.Link(path, text)` = `|Htshp:<path>|h<text>|h`: ls's names, ls -l's name column,
find, locate, grep's file names and -l, search's rows; `SH.SearchLink` for a suggestion's "→ search"). The marker draws
as its text and `FS.Strip` takes it out, so pipes, `sort -k` and chat never see it. A click with no drag (`C.SelectEnd`)
asks `C.LinkAt`: the place under the mouse (the selection's own mapping of x to characters) inside one of the line's
links (`C.LinksIn` counts characters as `Parts` does), only on the link's text, not the room after the line. It runs
in the pane as if typed (`C.LinkLine`): a folder `cd '<path>' && ls`, a file `cat '<path>'`, Shift+click `pin '<path>'`,
a search link `search <words>`. Hovering a link puts what a click does in the status line (`C.Hover`, worked out only
when the mouse moved).

## Tiling as a tree

The default layout, `tile`, keeps the panes in a split tree (i3's and bspwm's way): `{ pane }` or `{ dir = "v" (side by
side) | "h" (stacked), ratio, a, b }`. A split (`C.TreeAdd(p, from)`) halves the pane it's made from along its longer
side and leaves every other pane where it was; closing one (`C.TreeRemove`) gives its room back to the one it was split
with. `C.TreeRects` lays the tree out with `C.GAP` between and lists each split's gap (`C.splits`). The gaps are the
console frame's own, not a pane's: pressing one (`C.GapDown`) grabs that split, it follows the mouse while held
(`C.GapTick`, ratio kept within `C.RATIO_MIN`..`C.RATIO_MAX`), a second press within `C.DOUBLE` s evens it; the gap
under the mouse is lit (`C.GapHover`). Ctrl+Enter swaps places with the first pane. grid, tall, wide and mono lay the
panes out their own way (`C.Rects`, equal shares, no gaps to drag) and keep the tree for `layout tile`. The session
keeps the tree (`C.TreeSave`/`C.TreeLoad`: a pane is its place in the list); one that doesn't fit is made again
(`TreeCheck`: each pane split from the one before it).

## As you type: suggestions, the usage, Ctrl+R

fish's autosuggestion: with the cursor at the end, the rest of the newest history line starting with what's typed shows
faint after it (`SH.Suggest`; `p.suggestion`); Right or End takes it all, Alt+Right one word. The status bar's right
side says the usage and description of the command the cursor is in (`SH.CommandAt`: the words since the last
`| ; && ||`; `SH.UsageHint`, kept in `C.usageNote`), unless a selection or a link has something to say. Ctrl+R is
bash's reverse-i-search over the history (`C.SearchStart`): the box holds what's searched for (what was typed already
is searched at once), the prompt says `(reverse-i-search)`` or `(failed reverse-i-search)``, the line found shows faint
after it (`SH.HistorySearch`: newest first, any case); Ctrl+R again an older line, Enter runs it, Right/Left/Home/End/
Up/Down/Tab put it in the box to edit, Esc / Ctrl+G / Ctrl+C put the line back as it was. The scrollback's own search
is Ctrl+B `[` then `/` or `?`.

## z

zoxide's jumper: every folder `cd` (or `z`) goes to is kept in `db.consoleData.z` (the cache file, TerminalCache.lua) (path -> visits `r`, last visit `t`,
`time()`; the root isn't). Frecency (`SH.ZScore`) = visits x 4 within an hour, x 2 a day, x 0.5 a week, else x 0.25;
past `SH.Z_AGE` visits in all, every count is aged by a tenth and those under 1 forgotten. `z words`: the words in the
path in order, any case, the last one in the folder's own name (`SH.ZMatches`); the best that isn't where you are and
still resolves. `z` alone: /, `z -`: the last folder, a real path: there (as cd), `z -l [words]` the list with scores,
`z -x [path]` forgets one. Tab after z: the folders' names.

## prompt and theme

`prompt` (kept in `db.console.prompt`): classic (user@host:dir$, the default), starship (dir, zone, level, gold, bags,
took, then the end mark), minimal, full, or your own parts in order (`prompt dir zone gold`; `SH.SEGMENTS`: user, dir,
zone (the subzone if any), level, xp, gold, bags (free/all, orange at 4, red when full), time, took (the last line's
time, 2 s or more: `sh.took`, set by `SH.Run`), status (the last exit status when it failed; ^C is 130), char (always
last: `SH.PROMPT_CHAR` », green, red after a failure; starship's ❯ isn't in the game's fonts)). A part with nothing to
say is left out. `prompt` alone shows each preset as it would look and lists the parts.

`theme` (kept in `db.console.theme`): tokyonight (the default), dracula, gruvbox, nord, catppuccin (Mocha), solarized
(dark), class (Tokyo Night with your class's colour for the caret, cyan and the focused pane's border). `SH.SetTheme`
writes the scheme's ten colours into `SH.C` in place (every Paint after reads them) and returns old -> new, with which
`C.ApplyTheme` recolours every pane's lines already printed (`SH.Recolor`: only `|cff` codes of the old scheme) and
sets the console's own colours (background, panes, title bars, edges, caret, the selection, the focused border: the
scheme's `focus`, else Terminal's accent). neofetch's colour blocks follow it (`SH.Blocks`).

## Through a /reload

The panes come back after a /reload or a login (tmux-resurrect's way): `C.SaveSession` keeps each pane's place (cwd and
the previous one, for `cd -`'s sake), its text size and its last `C.SAVE_LINES` lines, the layout, zoom and which pane had
the keyboard in `db.consoleData.session` (the cache file) on PLAYER_LOGOUT (a /reload sends it too); `C.Open` with no panes puts them back
(`C.RestoreSession`), each with a dim "-- restored after a reload --" under its lines. Apps docked and commands running
then come back as plain shells. The last pane closed and `.console reset` forget it (a fresh console with the motd next
time). The extras load on demand: a session where the console wasn't used leaves what was kept as it was.

## Keys

Ctrl+N new pane, Ctrl+W close, Ctrl+Tab / Ctrl+arrows / Ctrl+1-4 move, Ctrl+Z zoom, Ctrl+Space next layout,
Ctrl+Enter to the big pane; or Ctrl+B then a key, tmux's way, for browsers that keep Ctrl+N/W/T/Tab (uiforever.com):
c (or % ") new pane, x close, o/n next, p back, arrows/1-4 move, z zoom, Space layout, Enter big, `[` scrollback,
= - 0 text size (the key after Ctrl+B types nothing: each box's text is put back a frame later). Ctrl+C stop, Ctrl+L
clear, Ctrl+U clear the line, Ctrl+D (empty line) close, Ctrl+R search the history, Up/Down history, Right take the suggestion, Ctrl+= / Ctrl+-
this pane's text size (Ctrl+0 the default; `font N|+|-|reset` for this pane, `font -a N` / `.console font N` every
pane's, kept in `db.console.fontSize`; titles and the status bar keep Terminal's size), Tab complete (twice for many),
PageUp/PageDown, Shift+Up/Down or the wheel scroll, Esc clears the line (on an empty one steps out), `` ` `` steps out.

Lines wider than the pane aren't cut to fit: they're drawn whole on a sheet clipped at the pane's edges (`p.sheet`
the scroll child of a ScrollFrame, `p.clip`: SetClipsChildren on a plain frame let the text run on
over the next pane in game), and slide sideways (`C.Side`, `p.hx` px): Shift+wheel (`C.SIDE_CHARS` characters a notch),
Left/Right on an empty line or in the pager (half a pane, as `less -S`). Never past the widest line shown; the title
says `[col N/M]` while lines run past the edge. A command run, Ctrl+L or the pager closing goes back to the left edge.

Dragging the mouse over a pane's lines selects text (bands behind it, `C.DrawSelection`; the main view or the pager,
not an app's or the matrix). Let go and the text (an ls -l line's columns joined by two spaces, lines by 
) goes into
a hidden multi-line box of the console's (`CopyBox`) that takes the keyboard with it all selected: Ctrl+C copies it
(an addon can't write the clipboard; the box and the player's key can), says "copied" in the status line, and gives
the keyboard back. Any other key lets the selection go and is the pane's (a letter reaches the line through the box's
OnChar). A click with no drag selects nothing.

## Not verified in game yet

EditBox OnKeyDown reaching the console's keys, the drawn caret's position against the box's text, docked apps'
scaling, C_TooltipInfo data shapes on Forever, WoW's fonts drawing `|--` tree lines and ASCII art (no monospace font),
the column stops' measuring, Attune's step numbers on real data, Ctrl+C in the hidden copy box reaching the
clipboard (an alpha 0 box; in a browser client especially), a letter typed after a selection landing once. Art lines' slot width against the font's real glyphs.
The ScrollFrame cutting the lines' text at the pane's edges; The prompt's » in the game's fonts; Right/End/Alt+Right reaching OnKeyDown before the box moves its cursor; the zone, gold and bag calls on Forever.
