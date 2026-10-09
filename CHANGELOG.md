# Changelog

## 0.45.0

**Send every result at once**
- Right-click a result (or Shift+Right in Simple mode) and pick "All 8 to party" (guild, raid, say...): one header line, then the items packed into chat lines with their links, like "Mats for Thorium Belt (2): 12x [Thorium Bar], 2x [Heart of Fire]", or a whole dungeon's loot, "Weapons from Razorfen Kraul (12): ...", each item with its boss.
- Advanced mode: `mats for thorium belt >>> party`; the list becomes one row saying how many go where.

**Every class's talents**
- "ice barrier" finds the mage talent even on your warrior; your own class's come first. Enter shows it on Wowhead, Shift+Enter links it in chat.
- Advanced mode: `class:mage`.

**Alike things work alike**
- The footer and the right-click menu say what Enter and Shift+Enter really do on every row (equip, summon, run, track, set waypoint...), in Advanced mode too, and the menu lists each action once.
- Enter on a mailbox opens the map on it; Ctrl+Enter keeps Terminal open after using an item or toy; a quest in your log isn't listed twice; nearest lists keep each NPC's title; drops and AtlasLoot items show their quality's colour (Shift+Enter links an AtlasLoot item); a chain's "gathered from" vein shows on the map.
- Action words reach more: "equip <set>", "link <recipe, talent or item>", "where is <dungeon>". Alt+` keeps them (Advanced mode: `do:use`, `do:cast`...) and names only the lists your results come from ("use hearthstone" becomes `@item do:use hearthstone`).
- Simple mode's tips and messages no longer show `@` or `>>`, and both `.help` texts cover everything; levels, counts, slot names and times are written one way; kind colours and names are clearer.

**Also**
- The `.lootlog` command is gone: ask "what dropped" (Advanced mode: `@drop`) to see the loot log.
- Quicker typing: chains ("mats for ...") and Simple mode's categories answer faster key by key, and `type:`, `slot:` and `is:equippable` no longer wait on item data; other classes' talents take a third of the memory; tidier code throughout.
- Fixes:
  - Chains never guess: "mats for core leather belt" no longer gives another recipe's mats; with no such name it offers the closest, and when several names fit it asks which.
  - Chains count bars you just bought, take `@kinds` (`@recipe thorium belt > mats`) and names like "Pattern: Linen Belt".
  - "upgrades" no longer calls any +1 stat better than gear with no stats.
  - Sending every result names everything asked for ("Swords and axes"), reaches whispers to first and last names, and never sends twice.
  - A tooltip stuck on "Retrieving item information" fills in once the item arrives.
  - The loot log keeps two of the same drop apart.
  - The first Alt+` after a /reload opens in Advanced mode; `.zen` off leaves bars other addons hide alone.
  - A click on the second line of a long prompt puts the cursor there; Shift+Enter on an equipment set lists its items as links; the mount journal points at the mount in its list.

## 0.44.0

**Ask in plain words**
- "where should i level", "what dungeon should i do", "where should i fish" (also "fishing spots" and "zones for level 35"): the zones, dungeons or fishing spots for your level or skill, from Leatrix Maps' zone levels.
- "what killed me", "what dropped", "what did i loot", "what did bob get".
- Alt+` shows any of them in Advanced form (`@map lvl:23`, `@map fish:mine`, `@drop you`...).

**Chains**
- "mats for thorium belt" lists its reagents with how many you have (bank and alts too); "where to get thorium bar" who sells it, drops it, where to gather it or how it's crafted; "what uses copper bar" what it goes into.
- Enter on a row goes one step further, Shift+Enter opens it, and the footer shows the path: "copper bar > used in > chain belt > mats".
- Sent to chat, a chain row says what it is: "Mats for Thorium Belt: 12x [Thorium Bar]".
- Advanced mode: `thorium belt > mats > alts`; `.chains` lists them.

**New lists**
- `@xp` (Simple mode: "xp"): your level, experience and rested experience, and your alts' as of when you last played them, their rested topped up for the time away.
- `@drop` (Simple mode: Loot log): what dropped (green and better) and who got it, with the boss and zone, kept across sessions.
- `@combatlog`: your deaths and what killed you, from the game's Death Recap.

**Searching and sending**
- Stored items sent to chat say who holds how many: "[Linen Cloth] x53: Alt 28 (bank), Bob 20 (bags 12, bank 8)".
- Zones show their level range; `lvl:` works on zones and dungeons, and `fish:` finds the zones your fishing skill is enough for.
- "upgrades" weighs the stats your class wants against what you wear, not just item level.
- PvP NPCs: "nearby battlemaster", "nearest pvp vendor" (Advanced mode: `is:battlemaster`, `is:pvpvendor`, `is:pvp`).
- Ctrl+click an item, spell or quest link in chat to look it up in Terminal.

**Also**
- `.zen` hides the menu and bag buttons, the XP bar and the quest tracker (your action bars and minimap stay), to play from Terminal.
- Fuzzy mode's glow: breathing, steady, bright, a thin line or off, in any colour (options panel).
- Simple mode keeps its footer once you start typing; `@loot` comes before `@drop` when picking a kind.
- Quicker searches and tidier code; the loot list no longer rebuilds while item names come in.
- Fixes:
  - `@loot` now has AtlasLoot's classic dungeons and WoW Forever's own, like the Ruins of Lordaeron (it had only Burning Crusade's).
  - Shift+Enter on an NPC only targets it (it also dropped a map pin).
  - A level said in a question is used, not yours.
  - A death could go unrecorded.
  - "boss loot" and "dungeon locations" are searches again.

## 0.43.0

**Your guild, friends and gold**
- `@guild` and `@friend` (Simple mode: Guild & friends): search members by class, rank, zone, notes or profession, like "@guild priest online" or "@guild in:undercity". Battle.net friends show the character they're playing. Enter whispers them; Shift+Enter invites them.
- `@who` (Simple mode: "who priest undercity"): Enter on the top row asks the server, and the answer comes into the list to search, whisper and invite.
- `@gold` (Simple mode: "gold"): your gold, and with Baganator or Bagnon every alt's, the guild banks and the warband bank, with the total on top.

**Pure fuzzy finding**
- Hold Tab and press **`** (or type `.fuzzy`): every list at once, matched by name only, like fzf. No `@`, no filters, no extras. Go through the results with Up/Down.
- Enter takes the result to Simple mode, Shift+Enter to Advanced mode, to open, use or send from there. A soft glow round the prompt says it's on; Tab+` again closes Terminal.

**Searching**
- "or" and "not": "sword or axe", "rare sword or epic axe", "rare ring not boe" (also "without" and "except").
  - In Advanced mode: `|` between values, filters or words (`q:rare|epic`, `sword|axe`), `&` for both inside one (`q:rare&type:sword|q:epic&type:axe`), and `-` or `!` for not (`-is:soulbound`, `!q:poor`).
- "skillup" lists recipes that still give skill (orange and yellow). Advanced mode: `is:skillup`, also with `@profession`; `is:orange`, `is:yellow`, `is:green`, `is:grey` too. Recipes show in their difficulty colour.
- The "try:" suggestions in the empty prompt are made for your character: your class trainer, your professions' skill-ups, a dungeon at your level, where you are, what's in your bags.

**Places and windows**
- Dungeon and raid entrances are WoW Forever's own, with level ranges: The Drowned City, the Hall of Thanes and the rest are there, and other expansions' are gone.
- "group browser" and "who listing" open the Dungeons window straight to that tab.

**Sending to chat**
- Simple mode: Shift+Right opens the selected result's menu (open, use, link or send to chat), to pick from with Up/Down and Enter.
- Loot sent to chat says where it drops: "[Thunderfury] dropped by Garr in Molten Core".

**Also**
- Fixes:
  - Typing Advanced syntax in Simple mode could raise an error during a long search.
  - "upgrades" inside an or-search kept using your gear and level from the first search.
  - An invisible click area could stay on screen after a window closed Terminal.
  - One failing reagent name could empty a profession's whole recipe list.
- Lighter and quicker: NPC role searches (vendor, repair, trainer), item type and stat filters do less work per row; tidier code throughout.

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
