# Terminal: the questions layer (design, built in 1.0.76 onward)

- **Status:** written November 3, 2026, against `main` at 1.0.75 (1996c8c). The player asked for the rewrite ("fix up /
  re-write the questions layer ... make sure this is tested against and committed to design"). It is built on `main`, one
  versioned commit per phase (CLAUDE.md's rules: TOCs bumped, a test per fix, `.changelog` kept), and each phase records
  what it actually did in section 8.
- **Scope:** Simple mode's plain-word questions (`Scan.ANSWERS`, Search/Questions/Questions.lua): how a line is
  recognized as one of them, which one gets it when several could, and how its answer is made. The chains (`>`, Chains.lua)
  stay as they are: they are already one pipeline for the answer and for Alt+`. The search engine changes only where
  section 5 says so.

## 1. Why

The 1.0.75 survey and a read of every question (three inventories, November 3, 2026) found three problems in the
structure, not in single questions:

1. **The list's order decides.** `Scan.ANSWERS` held 58 recognizers, and the first that took a line answered it. About
   20 entries had comments saying "before X, because ..." (1.0.65 moved `HaveQ` after Mail because "do i have mail" was
   read as an item count). Adding a question meant reading the whole list, and a new one could take lines from an old
   one silently.
2. **An answer was a second copy of the search.** Most questions had their own `Answer` (walk a list, filter, sort, cut:
   54 `ScoreInOrder` calls in 31 files) and also a `ToAdvanced` writing "the same thing" as an Advanced line for Alt+`.
   The two were written by hand and differed. Found: RepQuests, QuestNeeds and QuestsHere listed quests your race or
   class can't take (or ones done) in Advanced only; TurnIn, Spells, QuestDrop, MissingRecipes, ClassSpells, Library
   Books, Armory and the reward-item quests came in another order; Group's "tanks and healers" was written `is:tank
   is:healer` (both at once: nobody); Durability's `is:damaged` dropped the "Repair all" row; CanCraft's Mining missed the
   Smelting recipes; HaveQ listed an item twice (@item and @stored); collections, the bank and vendor upgrades were cut at
   100 rows in Advanced only; `reward:bag` never said it was loading, so an early search stayed empty.
3. **Each recognizer reads the line its own way.** 57 `ns.QuestionText` calls with their own trimming and patterns.

## 2. The model

A question is an entry in one registry (`ns.Questions`, `Scan.ANSWERS` is its list):

```lua
Q.Add({
	id = "QuestNeeds",                -- unique; tests, the golden file and `over` name it
	ask = function(text) ... end,     -- the recognizer: what the line asks (and a second value), or nil
	-- one of:
	line = function(q, extra) ... end,    -- a SEARCH question: the Advanced line that answers it (section 4)
	answer = function(q, extra) ... end,  -- an OWN answer: rows, note, isTrail (section 4.2)
	toAdvanced = function(q, extra) ... end, -- with answer: Alt+`'s line (nil: the words as typed)
	note = function(q, rows) ... end,     -- a SEARCH question's footer (its title), optional
	empty = function(q) ... end,          -- a SEARCH question's row when nothing is found, optional
	over = { "HaveQ" },                   -- the entries it beats when both understand the line equally (section 3)
	examples = { "tailoring quests", "daily quests" }, -- lines it must answer (section 6)
	custom = "why no search gives these rows", -- an OWN answer says why it is one
	ownDates = true, perField = true,    -- as before
})
```

`Asks("Name")` stays the shorthand for a module: its `Question`; `Line` (nil for a question it answers itself),
`Footer`, `None` and `Lead` (rows on top, "Drop all N") for a search question; `Answer` and `ToAdvanced` for an own
answer, or where `Line` gives none ("my mail"). (Not `Note`/`Empty`: Plan.lua's `PL.Note` and CombatLog.lua's `CB.Line`
were taken; CombatLog passes its `QuestionLine` explicitly.) Tests ask a question as the search does with
`ns.Questions.Answer(text)` -> rows, note.

## 3. Which question gets a line

Every entry is asked. When one takes the line, it gets it. When several do, the one that **understands more of the
line's words** gets it:

- A word is *understood* by an entry when the entry no longer takes the line with that word replaced by a word nothing
  knows (`Q.PROBE`, "zzqx"). A cue word ("quests", "mounts", "who"), a word naming a thing the entry looks up (a
  profession, a quest, an NPC, an instance) or a filler word the entry accepts only among its own are all understood. A
  free slot ("how many ___ do i have", "quests for ___") is not: anything fits there.
- An entry marked `last` (PerField: any "<list> by <field>" line) loses to every other that takes the line.
- An entry whose `over` names the other wins outright: a decision made on purpose, by a review or the player, written
  where it is made and tested, instead of a place in the list (1.0.76 turned each "before X, because ..." note into one).
- Else more understood words wins; else the earlier entry in the list (as before). The probe runs only when two or
  more entries take the line, and the ranking of a line is kept while one search runs (`Q.Ranked`, `Q.Begin`/`Q.Finish`
  in UI:Search; outside a search it is asked again, what it reads may have changed).
- The answer asks the entries in that ranking and the first whose answer gives rows answers (an own answer may still say
  nil and pass the line on, as before).

So "how many mounts do i have" is the collections' (it understands "mounts"; the item count only has a slot there), and
"do i have mail" the mail's, without either knowing of the other. A tie that list order would settle silently is a test
failure for a line in `examples` (section 6): ties between examples must be declared with `over`.

## 4. How a question is answered

### 4.1 A search question (`line`)

Its answer **is** the search of its Advanced line: the registry writes the line (with the filters and sorts typed after
the question, `Scan.WithTail`, as now) and the search runs it, in either mode. Alt+` writes the same line. The answer
and Alt+` can't differ, because there is one of them.

- A line with steps (`| group by zone`, `| sum value`) is read at the steps stage, as "quests per zone" was: the
  `question` recognizer (was `per`, Suggest.lua) claims the line and TakeAggregate searches its query with its steps.
  A line without steps is searched straight from `Scan.Answer` (`UI:SearchText(line)`).
- `note(q, rows)` puts the question's title in the footer; `empty(q)` gives the row shown when nothing is found (why
  there is none). These are the only things a question adds to the search's rows, and only when asked as a question.
- What the search reads (Why is this here?, the bar's picks, the parse golden's fields) is the line's reading.

### 4.2 An own answer (`answer`)

Kept only where no search can list the same rows, each with its reason in `custom`:

| Question | Why it is its own |
|---|---|
| Suggest | rows made from the game's state (durability, training, turn-ins...), no list holds them |
| SpellIds, ObjectIds | rows made on the spot from four sources; no list of ids |
| TalentsQ | descriptions read with families of like words, "yours first, then how well" |
| Zones | ranked by fit, quest counts and distance, from Z.LIST |
| LevelOf | one row from three kinds, the level is the answer |
| HearthBind, XpRate | a game value, session state |
| Corpse | your corpse, then the three nearest spirit healers |
| QuestPeople, NearQuests | a quest's giver / turn-in NPC: no relation in the search for it yet |
| QuestTrack | its rows are the plan (to track / to untrack), with the "Track N" row that does it |
| InstanceBosses | boss rows whose Enter walks to the drops chain |
| AhUpgradesQ | gain per gold over one row per item |
| Mail (plain, money, auctions) | your mail and the auction house's news in one list |
| ClassSpells (upcoming, at a level, a name) | the rank learned at a level, your class first |
| ProfTraining (not "now") | can-learn first, then the skill needed, with the next rank's text |
| LibraryBooks (rewards), AuctionatorQ (alts, everywhere) | rows of no list; counting only chosen holders |
| Chains, Attune How, Armory pieces | already a chain: the same pipeline either way |
| HunterPets | OneForAll's beasts aren't @npc rows; one row per ability |

An own answer is still filtered and sorted by what's typed after it and by the bar (`Scan.AnswerView`).

## 5. What the search gains

Each a filter, sort or field anyone can type in Advanced mode, added where a question needed it:

- **`sort:list`**: the rows in their lists' own order (their `_rank`, else the order the list gives them), never your
  picks first. Spells and the quest log rows get a `_rank` (the spellbook's order, the log's).
- **No 100-row cut for a sorted list with no words**: `@bank sort:name` lists the whole bank (up to `Score.LIST_MAX`).
- **Quest filters**: `is:foryou` (your race, class and side may take it: `QR.ForYou`), `is:cantake` (and you meet its
  needs: `QR.MeetsRequires`), `is:itemstart` (an item starts it), `is:started` (some progress made); `needrep:` (a
  quest that needs a standing with a faction).
- **Recipe filters**: `prof:` (the recipe's profession, `profName`: Smelting is Mining's), `source:` on recipes to learn
  (trainer, vendor, drop, quest, favor).
- **Sorts**: `sort:need` (the skill a recipe needs), `sort:rep` (the reputation a quest gives), `sort:grey` (grey quests
  first, then level), `sort:cantake` (quests you can take first).
- **Fields shown**: a sort's or filter's field in the detail where the answer showed it (`FIELD_DETAIL`: the needs, the
  reputation, the counts), as `sort:slots` already does.
- **`| unique`**: one row per item (an item in your bags and on an alt once, its count added up: `count` is bags + bank +
  alts for it).
- Fixes: `reward:bag` says it is loading (`F.loading`) while the reward index builds; `is:damaged` keeps the
  "Repair all" row; Group writes several roles as one `is:a|b`.

## 6. Invariants and their tests

1. **One line per search question.** For every `line` entry's examples, the rows of the question typed in Simple mode
   equal the rows of its Alt+` line typed in Advanced mode, in order (`tests/smoke/question_registry.lua`, "[questions: answer
   = Alt+`]").
2. **Every example goes to its owner.** Each entry's `examples` are answered by that entry and no other; a line two
   entries understand equally must be settled by `over` (the test names both). "[questions: examples]".
3. **No line changes owner by accident.** The parse golden records the question's id (not its index) for each corpus line;
   a phase that moves a line to another question shows it in `git diff tests/parse_golden.txt`.
4. **Every entry has an id, and an own answer says why** (`custom`), checked over the registry.
5. **Not slower.** `python tests/easybench.py 3` before and after each phase (FRONT_END.md §7): a keystroke on a question
   line may ask every entry (a plain search already did), and the probe runs only on conflicts.

## 7. Phases (each one commit, one version)

1. **1.0.76 — the registry and the ranking.** Ids for every entry, `Q.Ranked` (understood words, `over`, then order),
   examples for every entry, the tests of 6.2 and 6.4, the golden file by id. No answer changes; any line whose owner the
   ranking changes is checked against the old order and either kept (with `over`) or noted as a fix.
2. **1.0.77 — search questions.** `line`, `note`, `empty`; the `question` recognizer for lines with steps (PerField,
   BagWorth and AhValueQ move onto it; `PF.Line`'s special cases and `ns.PerFieldTaken` go); `sort:list`; no cut for
   a sorted list with no words; the test of 6.1.
3. **1.0.78 — the lists in their own order.** History, TurnIn, Buyback, LootLog, MyBank, Lockouts, Auctions, Calendar,
   GroupQuests, CombatLog, Attunements (the list), Durability, Group, Mail (filtered), What's Training, Collections,
   Spells (not on bars), QuestDrop, ClassSpells (known, a class), CanCraft, Plan.
4. **1.0.79 — quests and recipes.** QuestsHere, QuestNeeds, RepQuests, ItemQuests, AlmostDone, the reward questions
   (bags, an item, upgrades, vendor upgrades), MissingRecipes, with the filters and sorts of section 5.
5. **1.0.80 — counts and the rest.** HaveQ, BiggerBags (`| unique`), OneForAll's world and armory, Library Books (the
   lists), AuctionatorQ (bags, bank).

What can't be moved without losing something the player sees stays an own answer (4.2) and is listed there.

## 8. As built

### 1.0.76 (phase 1)

- `ns.Questions` (Questions.lua): `Q.Asks(name, more)`, `Q.Ranked(text)`, `Q.Understood(a, text)`, `Q.ById(id)`,
  `Q.Begin/Finish/Forget`. Every entry of `Scan.ANSWERS` has an id and, where the harness can read them, examples (83).
  `Scan.Ask` and `ns.QuestionToAdvancedOf` read `Q.Ranked`; `ns.PerFieldTaken` is "the best entry isn't PerField".
- The old order checked against the ranking over 1,163 lines (every quoted line of the smoke tests, the parse corpus,
  the examples): 288 taken by a question, 7 by several, 1 whose owner the counts alone would change ("lockouts by raid",
  PerField 3 words to Lockouts' 1; the 0.63.0 review kept it Lockouts', so PerField is `last`). The six others were
  settled by the list's order: each is now an `over` (QuestTrack over GroupQuests, BuybackQ over Auctions, GroupQuests
  over Group, MissingRecipes over Group, QuestsHere over Zones; LootLog over Chains also wins by the count). The
  "before X" notes of entries the harness can't read (OneForAll, Auctionator, Attune, What's Training) became `over`
  as written: Armory and AuctionatorQ over Auctions, AhValueQ, AttuneHow, SpellIds, Talents over Chains, HunterPets over
  CollectionsQ and Chains, ProfTraining over WhatsTraining, WhatsTraining over ClassSpells, MissingRecipes over both,
  GroupQuests and QuestDrop over Attunements, BagQuests over RewardQuests, CollectionsQ and Mail over HaveQ.
- The parse golden names the question by id: its diff was the 47 index-to-id swaps only.
- easybench (3 runs each, same session): Simple total 7327.5 -> 7390.5 ms (+0.9%), worst key 19.7 -> 19.0 ms;
  Advanced 4919.3 -> 4921.3 ms.
- Tests: tests/smoke/question_registry.lua ([questions: ids], [questions: ranking] over stand-ins, [questions: examples],
  [questions: words understood], [questions: one search]).

### 1.0.77 (phase 2)

- An entry with `line(q, extra)` is a search question: `Scan.Ask` gives `{ searchLine }`, `Scan.Answer` adds the tail
  (`Scan.WithTail`: before the first `|` step or `>>` send) and `Scan.SearchLine` searches it (`UI:SearchText`, never in
  a pcall: it may yield; `Q.lineDepth` guards a line that is a question again), then `empty(q)` when nothing is real and
  `note(q, rows)` as `UI.answerNote`. SearchText keeps the line's reading as `whyQ` (Why is this here?).
- Step lines: `Q.StepLine(text)` (was `PF.Line`) reads the best entry's line, its Advanced tail before the "|", and splits
  it as A.Split does (by hand: A.Split reads the line, and this runs inside its reading). The "per" recognizer moved to
  Questions.lua and calls it. Entries with steps say `steps = true` (PerField, BagWorth, AhValueQ): only when one of them
  takes a line is it ranked, because every line read goes through the recognizer and the full ranking there ran
  phrase.lua and printers.lua out of their budget. `PF.Line`, `PF.Answer`, `PF.ToAdvanced`, `BW.Answer`/`ToAdvanced`, the
  AH value's `Answer`/`ToAdvanced` and `ns.PerFieldTaken` are gone.
- `sort:list` (also sort:order, sort:listed): Bar.lua's `KeyOf` gives `-_rank`, every row the same without one (Keyed's
  tie is the row's place: the list's order); not on the bar's Sort (no Aggregate field). APPLIES.sort.list names the
  lists with an order of their own. `.filters` has its line; `.explain` says "in their list's order".
- `Scan.Finalize`: a sorted search with no words keeps up to `Score.LIST_MAX` (1000) rows, not 100.
- Alt+` with the bar's picks writes them before a step line's "|" (Printers.lua, through `Scan.WithTail`).
- easybench, the two trees one after the other on the six slowest lines: 1381.0 / 1354.1 ms against 1362.3 / 1333.2 ms
  (Simple), worst key 21.3 / 20.9 against 20.8 / 19.8 ms. (Run side by side they had looked 4 ms apart: two runs at once
  share the processor.)
- Tests: [questions: answer = Alt+`] (a stand-in line question over 150 rows: Simple equals Advanced row for row, all
  150 in the list's order, its tail, note and empty row), [questions: sort:list], [questions: step lines].

### 1.0.78 (phase 3)

- Search questions now: History, TurnIn, BuybackQ, LootLog, MyBankQ, Lockouts, Auctions, Calendar, GroupQuests,
  CombatLog, Durability, Group, CanCraft, Plan, QuestDrop, UnplacedSpells; and in part (the rest their own answer):
  Attunements (no words; words name attunements, else their steps), Mail (filtered; "my mail", gold, auction mail mix
  in the news), WhatsTraining (not "how much": a list with its total), CollectionsQ (no words; words name rows by
  their starts), ClassSpells ("my spells", another class's).
- `Scan.WithTail` puts the words in Alt+`'s order (filters, then the sort; a sort typed takes the line's place), so Alt+`
  of Alt+` is the same line (printers.lua's idempotence over the corpus found "@drop sort:list since:today").
- `Scan.SearchLine`: the inner search's typed picks are dropped (the bar's typed filters are the prompt's; taking one
  off would cut the prompt where the line had it); a `Footer` that says nil leaves the search's own (sort:plan's);
  `Lead` rows go on top.
- New in the search: `prof:` (KEYS.prof / profession: a recipe's own profName, Smelting's recipes are Mining's, `_` for a
  space), `sort:grey` (Aggregate's `grey` field: grey first, the tie by level, then name; on the bar's Sort for quests).
- Fixes found by making the answer the search: Group's roles are one `is:tank|healer` (was both at once: nobody), and
  "and"/"or" are the group question's own words (was a name looked for: "tanks and healers" never answered);
  `is:damaged` keeps the "Repair all" row while anything is to repair (and `n` read with `select`: `D and D.Total()`
  keeps one value); `is:unbuffed` and `missing:food`/`missing:consumables` leave out the dead and the offline, as the
  question did; CanCraft and Plan name the profession with prof: ("mining" missed the Smelting recipes); ClassSpells'
  other class is `sort:level,name` (was by name in Advanced); Spells and QuestDrop keep their list's order.
- Tests: [questions: every search question] (36 examples: the question in Simple mode and its Alt+` in Advanced list the
  same rows), [questions: sort:grey, prof:]; group.lua (tanks and healers, missing:food); durability.lua (is:damaged's
  row); about 40 Alt+` expectations now end in the line's sort; tests that called an answer directly ask
  `ns.Questions.Answer(text)`.
- easybench (one after the other): Simple 7285.6 -> 7329.0 ms (+0.6%), worst key 22.4 -> 18.8 ms; Advanced 4857.9 ->
  4988.2 ms (+2.7%).

### 1.0.79 (phase 4)

- Search questions now: QuestsHere (`@questie lvl:a-b in:<zone> is:todo is:cantake sort:level,name`: its Alt+` had
  listed done quests and other races'), QuestNeeds for a profession, dailies and repeatables (`is:foryou`,
  `sort:cantake`, which says in the detail what each needs; the standing needed stays its own: no filter says it),
  ItemQuests (`@questie is:itemstart sort:list`, the detail naming the item), AlmostDone (`is:started` with `is:todo` /
  `-is:complete`, `sort:progress,name`: its Alt+` had stayed as typed), BagQuests (its reward: filter already kept to
  you; the footer counts the done ones again), MissingRecipes (`prof:`, `sort:need`; MR.Answer is now only what its
  footer and empty row read).
- Own answers, with their reasons (`custom`): RepQuests (ranked by the reputation the faction asked for gives; its Alt+`
  gained `is:foryou`), RewardQuests (in the order of the items rewarded, with the chain), QuestUpgrades and
  VendorUpgrades (what is an upgrade by how much, the giver's distance or dungeon).
- New in the search: `is:foryou`, `is:cantake`, `is:itemstart` (Rewards.lua), `is:started` (Others.lua), `sort:cantake`
  (Rewards.lua's field, the tie by level), `sort:need` (Aggregate's `need`, the tie by `prof`, a new text field that also
  groups: "| group by prof"). A sort or a word whose field has a detail of its own is said in the detail: Query.lua's
  showField reads `ns.FIELD_DETAIL[sort]` and `ns.SHOW_FIELD_FOR[word]` (was three sorts by name).
- Fix: `reward:bag` (quiver, ammo pouch) says it is loading while Questie's rewards are read (`QR.Building()`), so the
  search is made again: an early Advanced search stayed empty.
- Lines that name the quest log write `@questlog` (Alt+` of `@quest` prints `@questlog`: one line either way).
- Tests: [questions: quest filters] (is:foryou, is:cantake, sort:cantake, is:started, reward:bag's loading);
  [questions: every search question] now 45 examples; questbags.lua and questiedb.lua read the detail as shown and ask
  the registry.
- easybench: Simple 7278.7 -> 7195.5 ms, Advanced 4902.2 -> 4884.7 ms (the same).
