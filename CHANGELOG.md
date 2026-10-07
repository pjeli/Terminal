# Changelog

## 0.42.0

**Send anything to chat, in Simple mode too**
- Right-click any result to send it to chat: say, party or raid, guild, instance, a whisper to your target, or the chat box to send it yourself.
- NPCs, mailboxes and dungeon entrances go with a map pin and what you searched for: "Nearby innkeeper: …", "Nearby mailbox: [pin]".
- Advanced mode's `>>` says what you sent: `@npc reagent is:vendor sort:nearest >> guild` sends "Nearby reagent vendor: <name> [pin]".

**Finding gear**
- "helm upgrades" (or just "upgrades") lists only gear you can equip now: your level, your class, near your current item level or better. In Advanced mode it's `is:upgrade`.
- "helmet" on its own lists every helmet.
- Instance shorthand comes first: "rfk" lists Razorfen Kraul's loot, "rfk helm" its helmets, "sfk" Shadowfang Keep's. Items whose letters just happen to fit no longer show up.
- "weapon damage" finds sharpening stones and weightstones. In Advanced mode it's `stat:weapondamage`, with amounts: `stat:weapondamage>=5`.

**Places**
- Dungeon and raid entrances: `@dungeon` and `@raid`, or Places and "nearest dungeon" in Simple mode. Enter opens the map on the entrance and pins it.
- Mailboxes: "nearest mailbox", or "nearest mailbox in ratchet", and `@mailbox` in Advanced mode. It shows the closest ones, how far and where, with the direction arrow; Enter pins one.
- "nearby" works like "nearest", and either can come last: "innkeeper nearby".

**Advanced mode**
- Alt+` turns a Simple search into Advanced mode's command line for that one search: "nearest innkeeper" becomes `@npc is:innkeeper sort:nearest`. Pressed with Terminal closed, it opens in Advanced mode.
- Typing `@` lists every kind to pick from, and a filter like `stat:` or `q:` lists its values. Tab and Shift+Tab move through the list; Enter writes the pick.
- `in:goldshire` and `in:ratchet` know the towns.
- `trainer:` finds every trainer of a kind, whatever their title (Miner, Herbalist, riding instructors). `trainer:class` is your own class; `trainer:mine` is the mining trainers.

**Windows**
- `@panel` opens straight to a window's tab: Guild Roster, Guild Info, Character Stats, Equipment Manager and Titles.
- `@panel` also opens WoW Forever's Legacy window and its Challenges and Tree tabs, even with its button moved off the bar.

**Also**
- AtlasLoot Forever: WoW Forever's own items (Snake Eye Kaleidoscope…) show up under Loot once the server has named them.
- "stamina food" right after login finds your food straight away.
- `.atop`: Enter on an addon profiles it. You get its own CPU and memory graphs, how fast its memory grows, and the game's profiler numbers beside all addons'.
- Lighter and quicker:
  - Typing in Simple mode searches only what the previous letter found.
  - Questie's NPC list is freed after 10 unused minutes (about 5 MB).
  - Quest rows take less memory.
  - Results you've picked before no longer slow down broad searches.

## 0.41.0

- Simple mode is the default: type in plain words and pick where it was found (Bags, Quests, NPCs, Emotes…). Everything is searched, no `@` needed. `.advanced` switches to the full command line; `.simple` comes back.
- Plain words do the work: "stamina food", "attack power food", "rare sword", "use hearthstone", "nearest innkeeper", "vendor goldshire", "mining trainer in org".
- Terminal opens as just the prompt, with a suggestion to try; Shift+Right takes it. Down brings back your last search (Simple) or your recent picks (Advanced); Up brings back your last command.
- NPCs show their title (Mining Trainer, Banker) and, when selected, an arrow pointing the way to them.
- Advanced mode: `sort:nearest` puts NPCs closest first; `near:500` keeps those within 500 yards.
- Right-click any row for everything it can do.
- Search understands:
  - initials (scb, zg);
  - shorthand (brd, sw, org);
  - close spellings (hearhtstone);
  - emotes as slash commands (/dance).
- QuestieDB alone is enough for Questie's quests and NPCs.

## 0.39.5

- Fixes from a review pass:
  - A pasted style string changes only the look.
  - The copy bar never cuts off a style string's last line.
  - Reading the toy and pet journals never changes their filters.
- Lighter: WoWamp redraws less often, earned achievements no longer re-read the whole list, and `sells:` looks its sellers up once per search.

## 0.39.4

- New kinds:
  - `@toy`: Enter uses it.
  - `@pet`: Enter summons it.
  - `@title`: Enter wears it.
- `@achievement` lists the achievements you haven't earned too, greyed, with their progress.
- New filters:
  - items: `is:quest`, `is:soulbound`, `is:boe`;
  - spells: `is:passive`, `is:ready`;
  - currencies: `is:capped`;
  - reputations: `standing:honored+`;
  - achievements: `is:done` / `is:todo`;
  - NPCs: `@npc sells:<item>`.
- `@addon`: Shift+Enter turns an addon on or off for this character. `@npc`: Shift+Enter targets the NPC.
