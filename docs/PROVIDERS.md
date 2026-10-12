# Adding your own list to Terminal

Terminal searches lists: your bags, quests, spells, NPCs, mail and so on. Each list is a **provider**: a table that
says how to make its rows, and what Enter and Shift+Enter do on them. Your addon can add one, and its rows show up in
Terminal next to everything else: found by fuzzy search, reached with `@yourword`, in Simple mode's categories, with a
tooltip, sent to chat with `>>`, picked often and remembered.

A complete, working example is in [`docs/example/TerminalNotes`](example/TerminalNotes): a small addon that keeps your
own notes. `.note buy 20 linen` adds one, `@note linen` finds it, Enter shows it in your chat window and Shift+Enter says
it in your party. Copy the folder into `Interface\AddOns`, `/reload`, and try it. This page walks through it.

## The shape of it

```lua
-- TerminalNotes.toc
## Interface: 16001, 120100
## Title: Terminal Notes (example)
## Dependencies: Terminal
## SavedVariables: TerminalNotesDB
TerminalNotes.lua
```

`## Dependencies: Terminal` makes the game load Terminal first, so its public table, `_G.Terminal`, is there when your
file runs. (Use `## OptionalDeps: Terminal` and check for `_G.Terminal` if your addon should also work without it.)

```lua
local T = _G.Terminal
if not (T and T.RegisterProvider) then return end

T:RegisterProvider("notes", {
	label = "Note",                 -- the kind shown on each row
	color = "ffffe08a",             -- the kind's colour, aarrggbb
	aliases = { "note", "notes" },  -- @note and @notes find this list
	collect = function()
		local out = {}
		for i, n in ipairs(TerminalNotesDB.notes) do
			out[#out + 1] = {
				key = n.t or i,       -- stable across rebuilds
				name = n.text,        -- what's searched and shown
				icon = "Interface\\Icons\\INV_Misc_Note_02",
				activate = Show,      -- Enter
			}
		end
		return out
	end,
})
```

That's a working list. Everything else below is optional.

## The list (provider) fields

| Field | What it does |
|---|---|
| `label` | The kind's name on each row ("Note"). |
| `color` | The kind label's colour, `"aarrggbb"`. Pick one apart from Terminal's own kinds. |
| `aliases` | The words after `@` that reach this list. The first one is how Terminal names it (`.mem`, Alt+\`). Keep them unique: the first list registered keeps a word two of them share. |
| `collect(p)` | Returns the rows (a list of tables, below). Called when the list is first searched, and again after it's marked changed. |
| `events` | Game events that mark the list changed (`{ "BAG_UPDATE" }`). It's made again the next time it's searched, not on every event. |
| `guard` | Seconds: events in a burst mark it changed once. |
| `explicit` | `true`: only searched with its `@word`, or in its Simple mode category; plain searches leave it out. Use it for long lists, or ones that would crowd other results. |
| `lazy` | `true`: searched only once something is typed (not on an empty prompt). |
| `refreshOnOpen` | `true`: made again each time Terminal opens; a number: only when older than that many seconds. For lists that change with no event telling (time left, distances). |
| `noCombat` | `true`: Enter does nothing in combat (opening windows isn't allowed then). |
| `simpleCategory` | Where its rows go in Simple mode: an existing category's id (`"game"`, `"character"`, `"collections"`...) or `{ id, label, icon }` for a new one. Without it, Simple mode doesn't show the list's rows (Advanced mode does). |
| `verbs` | What Enter and Shift+Enter do, in a word or two: `{ "show in chat", "say in party" }`, or `function(row) return enter, shift end`. The footer and the right-click menu say them. |

## The row fields

| Field | What it does |
|---|---|
| `name` | **Required.** Searched (fuzzily: "lnn" finds "linen") and shown. |
| `key` | A stable id. Terminal's history and "picked often" follow it across rebuilds. Defaults to the name. |
| `icon` | A texture path or file id. |
| `detail` | The grey text on the right. |
| `text` | More words to search by that aren't shown (a description, a zone, tags). |
| `color` | A colour code for the name, `"|cffrrggbb"`. |
| `tip` | A plain tooltip under the name. |
| `tooltip(row, tooltip)` | Draw the tooltip yourself (`tooltip:AddLine(...)`). |
| `link` / `getLink(row)` | An item, spell or quest link: shown as the tooltip, and what `>> party` sends. `getLink` is called only when the row is selected. |
| `activate(row)` | Enter. Terminal's code runs it (`T:Output({ "..." })` prints lines in your chat window). |
| `secondary(row)` | Shift+Enter, the same way. |
| `secure`, `isOpen(row)`, `after(row)` | Enter as a press the **game** makes (below). |
| `secondarySecure`, `secondaryIsOpen(row)`, `secondaryAfter(row)` | Shift+Enter as a press the game makes. |
| `staysOpen` | `true`: Terminal stays open after Enter (the row writes a new search, say). |
| `noActivate` | `true`: a line that only says something (nothing happens on Enter). |

Rows of a big list should share their functions: write `activate = Show`, not a new `function` per row. Terminal
copies the name and text into lowercase once, when the list is made.

## Doing things the game protects

WoW Forever runs on the retail Midnight API: anything protected (casting, using items, sending chat, targeting,
opening many of Blizzard's windows) must come from the game, on a key press, and any Blizzard code that addon code
calls runs **tainted**. Tainted code that writes into a Blizzard window leaves it broken, often minutes later in a
fight ("action blocked"). So Terminal never does those things from its own code. It hands your press to the game:
Enter is bound, for that one key press, to a secure button that runs what you give it.

Give a row a `secure` spec (or `secondarySecure` for Shift+Enter):

```lua
secondarySecure = { macro = function(row) return "/p " .. row.name end }, -- a macro the game runs
secondaryIsOpen = T.Never,                                               -- nothing to open first: always pressed
secondary = NotInCombat,                                                 -- what runs when the game can't be handed it
```

- `{ macro = "text" }` or `{ macro = function(row) return "text" end }`: macro lines (`/cast`, `/use`, `/p`, `/click
  SomeButton`). At most 255 characters, all lines together (the game cuts the rest).
- `{ binding = "TOGGLESPELLBOOK" }`: presses one of the game's own key bindings (it opens the window exactly as your key
  does). Add `buttons = { "SpellbookMicroButton" }` as the fallback for a client without that binding.
- `isOpen(row)`: true when there's nothing to press (the window already shows: the key would close it). Then only
  `after` runs.
- `after(row)`: runs a moment after the press, to point at something in the window that opened. Only **read** the
  window there (find a frame, `T.Highlight:Show(frame)`); never call its functions or change it.
- Don't put `/run` lines that call Blizzard's Lua functions in a macro: a `/run` line runs tainted too. A `/run` that
  only calls a `C_...` function is fine.
- In combat Enter can't be handed to the game: `activate` / `secondary` run instead, so make them say so.

## Commands

```lua
T:RegisterCommand("note", {
	desc = "Add a note",
	aliases = { "n" },
	complete = function(args) return { { "forget", "forget the notes with these words" } } end, -- (optional)
	run = function(args) return { "Noted: " .. args } end, -- lines returned are printed in chat
})
```

`.note buy linen` runs it. `complete` lists the arguments while you type them.

## Keeping the list up to date

- `events` mark it changed when a game event says so.
- `T:Changed("notes")` marks it changed when something else does (your own command, a timer). It's made again the next
  time it's searched.

## Helpers you can use

| | |
|---|---|
| `T:Print(...)` | A line in chat, labelled Terminal. |
| `T:Output(lines)` | Lines in your chat window, as system text. |
| `T.Never` | A function that returns false: an `isOpen` for presses with nothing to open. |
| `T.Ago(seconds)` | "just now", "5 min ago", "3 h ago", "2 d ago". |
| `T.Str(v)`, `T.Num(v)`, `T.Secret(v)` | Secret-value guards: Midnight hides some values (health, names in a boss fight) as secrets, which can't even be compared. `T.Str(v)` is a usable string or nil. |
| `T.Lower(s)` | Lowercase that folds accented letters, Cyrillic and Greek too (`string.lower` is ASCII only). |
| `T.Highlight:Show(frame)` | Terminal's pulsing outline around a frame. |
| `T.version` | Terminal's version string. |

## Notes

- Terminal is on its 0.x versions. `_G.Terminal` is its whole namespace; what this page lists is what's meant for other
  addons and kept working. Anything else may change between versions.
- Searching costs a little per row per keystroke: keep `collect` quick, and make long lists `explicit` or `lazy`.
- Try it: `/reload`, open Terminal (\`), type `@yourword`. `/term .debug on` prints what Terminal does, `.debug log`
  shows it.
