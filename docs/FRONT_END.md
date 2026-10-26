# Terminal: one front end for reading a line (design, to ship in 0.68.0)

This document is written to be handed to Claude Code as the brief for the work. Read it all first, then CLAUDE.md.

## Decisions (the player, October 25, 2026, before starting)

These answer section 9 and override the plan in section 5 where they differ:

1. **Branch:** the work is done on the branch `front-end`, checked out in the AddOns folder itself (the game loads the
   branch until it's merged).
2. **Versions:** commits on the branch don't follow the 0.x.y convention (no TOC bump, no version in the subject, no
   changelog line per commit). The branch is squashed and merged into `main` as one proper 0.x.y commit when ready.
   Everything else in section 5 still holds: the full suite and `tests/check.py` pass at every commit, a fix gets a
   test that fails without it, and nothing is pushed until the player says "push".
3. **New files:** fine. `Search/Lex.lua` and `Search/Phrase.lua` each need a full game restart the first time.
4. **Wrong readings found on the way:** recorded (below, section 10) and fixed afterwards, each as its own change.
   Phase 3 stays a pure move with the golden file unchanged.

It builds on the search rewrite of 0.55.4–0.56.0, which is already in the code:
- every filter goes through one function, `Scan.AddFilter`, with its strength (hard, strict or soft) and its Advanced form;
- `ns.QueryToAdvanced` reads a line with the search's own steps and prints the query (Alt+`);
- questions' rows go through `Scan.AnswerView`, which applies the bar's picks and Advanced words typed after a question;
- the bar shows typed filters as picks and removes their words from the line when unticked;
- Advanced syntax typed in Simple mode is searched as typed, without switching modes;
- `tests/smoke/roundtrip.lua` checks that a Simple line, its Alt+` line and the bar's picks all list the same results.

- **Status:** proposed on October 25, 2026, against `main` at 0.67.5 (f7b9917). Built on the branch `front-end`: Phases 0–5, the section 10 fixes and a review's fixes; Phase 6 left for later (the player's call). Each phase's as-built notes follow its design section (4.3–4.5) and its timings are in section 7. To be squashed into `main` as one 0.x.y version. After Phase 5, Search/ was reorganized as pure moves: the file names below are the old ones (Easy.lua is now `Search/Reading/Simple.lua` for the mode, `Words.lua` for single words, `PlainNumbers.lua`, `StepWords.lua` and `Joins.lua` for the plain, steps and join stages' phrase readers, and `Explain.lua`; `Lex.lua` and `Phrase.lua` are in `Search/Reading/`; Pipes.lua is `Search/Steps/Chains.lua` and `Aggregate.lua`; the questions are in `Search/Questions/`; Search.lua's query reading, "nearest" and its fallbacks are `Search/Query.lua`, `Nearest.lua` and `Fallbacks.lua`).
- **Scope:** how the prompt's text is read: Simple mode's plain words, questions, steps, sends, and the Advanced syntax typed into Simple mode. The search engine, the scoring and the question answers themselves are out of scope.

## 1. Why

A Simple line is read by about six separate passes. Each one splits and lowercases the raw text again, each one claims words without knowing what the others claimed, and three other features re-implement parts of those passes instead of reading their result. About a third to a half of the findings in the 0.66.14 and 0.66.18–0.66.22 reviews came from this structure, not from logic errors:

- **Phrases claim words with no context.** The article "the" broke "the 3 nearest mailboxes" (0.66.15). "The five sorrows" was read as a count, "30 yard range" as a top 30, "the best of both worlds" as "first 1". "Tonight We Dine", "Last Day of Summer" and "Next Level Thinking" were read as a date or a level, which found nothing (0.66.21 patched this by searching again).
- **Copies drift.** Alt+` (`E.ToAdvanced`) repeats `TakeAggregate`'s top N and comparison handling by hand. Their step order differed (fixed in 0.66.14). `ns.QuestionToAdvancedOf` repeats `Scan.Answer`'s retries. `E.Explain` has a third parser for Advanced syntax, which mis-said dates (0.66.14). 26 smoke checks (`T.SameAsAdvanced`, `roundtrip.lua`) exist only to catch this drift.
- **Positions and case get lost.** `E.SetOp` returned the rest of the line from a lowercased copy ("Hogger" became "hogger", 0.66.21). The bar removes a typed filter by searching the line for its words (`B.DropWords`, `B.SwapWord`), through `said`, a map keyed by the filter's text. The same filter typed twice collides, and the line has to be re-searched with escaped patterns.
- **Precedence is in comments.** `Scan.ANSWERS` (about 40 question matchers, `Search/Search.lua` ~758) is ordered by notes such as "before the chains: …". Adding a question means reading the whole list.
- **Ambiguity is patched afterwards.** "Is 'tonight' a date or part of a name?" is settled by running the search again without the date reading (`UI:Search`, `Scan.AnyNameHas`, `self.noPlain`).

This is **not** a performance project. Simple-mode keystrokes cost about 2–6 ms worst case today. The new front end must not be slower (section 7).

## 2. Goals and non-goals

**Goals**
1. Read a line once: one tokenizer whose tokens keep their original text and byte position.
2. One registry of phrase recognizers (dates, levels from yours, number phrases, orders, top N, comparisons, sends, steps, actions, places, joins). Each recognizer claims a span of tokens, at a priority that is data, not code order.
3. One reading of the line (an intermediate representation) that the search, the bar, Alt+`, `.explain` and the question matchers all read. Alt+` and `.explain` become printers of that reading. They are never parsers of their own.
4. Ambiguity made explicit: a claim can carry an alternative reading, and the search tries the alternatives in order.
5. Every player-visible behaviour stays exactly as it is, except the bugs listed in a phase's acceptance criteria.

**Non-goals**
- No grammar, LR or LL parser, or AST of English. Plain words have no grammar, and the players' edge cases are the specification.
- No change to Advanced syntax, Simple-mode vocabulary, question answers, scoring, the overview or the bar's UI.
- No new player-facing features and no new L[] texts. If a phase needs one, stop and ask the player.
- No new input languages: Simple mode keeps understanding what it understands today. The design only leaves room for more (4.7).
- No big-bang rewrite. Every phase ships as ordinary development commits with the full suite passing (on the branch: see Decisions). The whole is released as 0.68.0 when the player calls the release.

## 3. How a line is read today (map for the implementer)

In the order a keystroke runs it (`UI:Refresh`, `UI/Results.lua` ~620):

| # | Where | What it does | Re-tokenizes? |
|---|---|---|---|
| 1 | `TakeSendTo` (`UI/Results.lua` ~509), `ns.Share.Split`, `ns.Share.PlainCopy` | Takes off `>> party`, `>>> raid` and "linen to csv". Sets `self.sendTo`. | yes |
| 2 | `TakeAggregate` (`UI/Results.lua` ~537) | `ns.PerField.Line` ("quests per zone"); `ns.Aggregate.Split` on a lone `\|`; else `E.TopN` + `E.SetOp`. Builds `self.aggregate` (`A.Parse(steps, rest)`, with `topWords`/`fromBar`) and adds the bar's Group. | yes (TopN, SetOp each) |
| 3 | `UI:SearchText` → `E.English` (`Search/Easy.lua` ~379) | A phrase in the client's language becomes its English line. | string level |
| 4 | `Scan.Answer` (`Search/Search.lua` ~1225) → `Scan.Ask` → `Scan.ANSWERS[i].ask(text)` | About 40 matchers, each over raw text, most through `ns.QuestionText` (`Core/Locale.lua` ~123: lowercase, punctuation to spaces, refuses syntax, cached per text). Retries: `E.PlainDates`, then `Scan.SplitTail` (filters or sorts after a question), then `E.PlainNumbers`. | yes, per matcher |
| 5 | `Scan.Parse` (`Search/Search.lua` ~1532) | `Scan.Words` (quotes) → `E.PlainNumbers` (`DateAt`, `RelativeAt`, `OrderAt`, `OpAt`/`FieldAt`/`NumAt`/`SpanAt`/`ValueAt`; returns new words + `said`) → `E.JoinPairs` → `E.JoinLogic` → per word: `F.SortOf`, `F.ActionOf`, `@kind`, `F.Parse` (+ `PlainWord`), `E.HARD_WORDS`/`E.Strict`, `E.Word` (soft), else a search token. Builds `q` via `Scan.AddFilter` (`q.filters/hard/softs/specOf/fsig`), `q.picks`, `q.typedSort`, `q.kinds`. | yes |
| 6 | After Parse | `Scan.ActionAndPlace` → `Scan.TakeAction` (articles, action words, "nearest" last), places; `Scan.TrainerWords`; `Scan.OnlyRoles`; `Scan.Prepare`; `Scan.SimpleScope`. | on q.tokens |
| 7 | `UI:Search` | The 0.66.21/0.66.23 retry: no results, a date or level phrase that a name has → search again with `self.noPlain`. | whole search |

Re-implementations of the above:
- `E.ToAdvanced` (`Search/Easy.lua` ~1322): `A.Split`, `E.TopN`, `E.SetOp`, the bar's Group, then `ns.QueryToAdvanced` (`Search/Search.lua` ~985). The latter already prints from a parsed `q`: keep that idea and extend it.
- `ns.QuestionToAdvancedOf` (~926) repeats `Scan.Answer`'s chain/date/tail retries.
- `E.Explain` (`Search/Easy.lua` ~1590) parses an Advanced line on its own: `A.Split`, `>>`, chains, `ns.Words`, its own filter and sort reading (`FilterSay`, `SortSay`, `LevelSay`, `TimeSay`, `SinceSay`).
- The bar: `B.Typed`, `B.DropWords`, `B.SwapWord` (`UI/Bar.lua` ~163–290) find typed words in the line by text, from `UI.typedPicks` (`q.picks`, `q.typedSort`) and `UI.typedGroup`.

## 4. Target design

### 4.1 Tokens (`ns.Lex`)

```lua
-- one token
{ text = "Hogger",   -- as typed (original bytes)
  low  = "hogger",   -- ns.Lower(text)
  s = 1, e = 6,      -- byte span in the line as typed (inclusive)
  class = "word",    -- word | syntax | quoted | op (below)
  open = nil,        -- true for an unfinished last token (an unclosed quote, "lvl:", "@np")
  i = 1 }            -- index in the token list
```

- `ns.Lex.Read(line)` returns `{ line = line, toks = { ... } }`. It keeps the last few lines read (a small LRU keyed by the line string), because one keystroke asks several times.
- The lexer splits on whitespace, keeps quoted phrases whole (the exact rules of `Scan.Words`, including `"a b"c`), and keeps `|`, `>`, `>>` and `>>>` as tokens of their own when they stand alone. It does **not** split inside a word (`q:rare|epic`, `-is:boe`, `1g50s`, `50%` stay one token), as today.
- Lowercasing goes through `ns.Lower` (UTF-8 aware), never `string.lower`.
- **The token's class** is set by the lexer, once, so that Simple mode and Advanced mode can share one token list:
  - `op`: a lone `|`, `>`, `>>` or `>>>`.
  - `quoted`: a "quoted phrase". Never claimed by a recognizer, never removed by the bar.
  - `syntax`: Advanced syntax. That is a token starting with `@`, a `key:value` (any part of an `a|b` or `a&b`), a leading `-` or `!` before a key or an @kind, `sort:`, `do:`. The test is `E.IsAdvancedWord`'s, moved here.
  - `word`: everything else, including `-boe`, `sword|axe`, `1g50s` and `50%`. These are Simple mode's own forms, read by its recognizers as today.
- **Half-typed lines are normal input:** an unclosed quote, a trailing `|` or `>>`, `lvl:`, `@np`. The lexer never fails. It marks the last token `open = true`, so the pick lists and completion can read it from the tokens instead of from the raw text.
- **Translation stays before the lexer.** `E.English` turns a phrase in the client's language into its English line on the whole string (`E.PHRASES`). It is not a recognizer (see 4.7).

### 4.2 Claims and the recognizer registry (`ns.Phrase`)

```lua
-- one claim: a span of tokens read as one thing
{ from = 3, to = 6,              -- token indexes (inclusive)
  kind = "filter",               -- filter | sort | step | send | action | place | top | setop | join | question | words
  spec = "lvl:20-30",            -- Advanced form where there is one ("| first 3", "except @bank", ">> party")
  said = "between level 20 and 30", -- the original text of the span: line:sub(toks[from].s, toks[to].e)
  by = "numbers",                -- the recognizer's id (for .debug traces and tests)
  alt = nil }                    -- optional: the other reading (4.5)

ns.Phrase.Register({
  id = "dates",                  -- unique
  stage = "plain",               -- send | steps | plain | join | action | place (run in this order, see 4.3)
  priority = 40,                 -- higher wins when two claims overlap within a stage
  first = { "yesterday", "today", "tonight", "since", "this", "last", "past", "in", "older", "more", "over", "from", "on" },
                                 -- first-token index: at() is only asked where toks[i].low is in this set (nil = everywhere)
  classes = { word = true },     -- the token classes it may claim (default: word only; sends and steps also take op and syntax)
  modes = { simple = true },     -- the modes it runs in (default: simple; sends, steps and chains: both)
  lang = nil,                    -- nil: language-neutral or English (always runs); "deDE" etc.: only on that client (4.7)
  at = function(r, i, ctx) ... return claim or nil end,  -- r = the reading, i = token index
})
```

- A claim may only cover tokens of the recognizer's `classes`. The scanner enforces this, not each recognizer. A plain-word phrase can then never take a piece of `lvl:20-30`, an `@kind` or a quoted name, which is a check every pass has to remember on its own today.
- Recognizers are pure: they read `r.toks` and `ctx` (`ctx.simple`, `ctx.level`, `ctx.now`, `ctx.bar`) and return a claim. They never touch `UI`, never search and never allocate when they don't match.
- The `first` index replaces today's ad-hoc indexes (`OpAt`'s, `OrderAt`'s `orderFirst`): only recognizers whose first word matches are asked.
- Today's `E.WORDS`, `E.ORDER_WORDS`, `E.NUM_BEFORE`, `E.NUM_AFTERWARDS`, `E.LIST_PHRASES`, `E.NOT_COUNTED`, `E.NOT_A_NOUN`, `E.RANK_WORDS` and so on stay as they are. Recognizers read them. Moving or renaming vocabulary is not part of this work.

### 4.3 Reading a line

`ns.Phrase.ReadLine(line, ctx)` → the reading:

```lua
{ line = line, toks = {...},
  claims = { ... },     -- sorted by `from`, never overlapping
  rest = { ... },       -- tokens no claim took, in order (the search words)
  send = claim|nil, steps = { claim ... }, top = claim|nil, setop = claim|nil, action = claim|nil, place = claim|nil }
```

The stages run in a fixed order, each over the tokens the earlier stages left:

1. **send** (`>>`, `>>>`, "to csv", "as text"; `ns.Share.Split`, `PlainCopy`)
2. **steps** (a lone `|` and what follows; `PerField.Line`; then top N and comparisons said in words)
3. **plain** (dates, levels from yours, number phrases, orders: today's `PlainNumbers` parts)
4. **join** (`JoinPairs`, `JoinLogic`)
5. **action** and **place** (`TakeAction`, places)

Within a stage, the scanner walks i = 1..n and asks the recognizers indexed by `toks[i].low` in priority order. The first claim wins, and the scanner continues after its `to`. This is exactly today's left-to-right, first-match behaviour, made explicit. Overlaps across stages can't happen, because a later stage only sees unclaimed tokens.

As built (Phase 3):

- **A recognizer is a point or a pass.** A point (`at`) is asked at a token, as above. A pass (`pass`) reads the stage's whole line at once and runs before the points, in priority order. The join stage is three passes over the plain stage's *units* (`r.units`: the line's words with each plain claim's filter words in place of its words): "pairs", then every "not", then every "or" ("rare sword or axe not boe" needs the "not" read before the "or" looks how far its side goes). A join records a `keep` claim (`Phrase.Join`) over the units' tokens.
- **Keep claims** are notes on tokens, not takings: the recognizers after them are still asked, and they take no tokens from `rest`. Joins, `per`, and the action and place are keep claims.
- **The action and the place are noted, not read, by the reading.** They need the filters (a place is looked for in what the filters left; an action word only counts with more after it), so `Scan.ActionAndPlace` reads them after `Scan.Parse` as before and records them on the reading with `Phrase.Note` (`r.action`, `r.place`, once per reading). Their stages exist in `Phrase.STAGES` but have no recognizers.
- **The search's reading** is `ReadLine(text, { simple, parse = true, noPlain })`: the plain stage (Simple mode, unless `UI:Search` retries with the words as typed), the units, then the join stage. `Scan.Parse` reads `r.units` and records where each filter, sort and word came from: `q.src[filter]`, `q.srcSort`, `q.tokenSrc[i]` (each `{ from, to, by, said }`), `q.srcAction`.
- `rest` is made when asked (`Phrase.Rest(r)`): nothing in the addon reads it yet.
- `E.PlainNumbers`, `E.PlainDates`, `E.JoinPairs` and `E.JoinLogic` stay as wrappers over `Phrase.ReadWords(words, ctx)` (a list of words read as a line, `ctx.stages` and `ctx.only` naming what's asked), for `Scan.Answer`, `UI:Search`'s retries and the tests.

### 4.4 The query (the IR) and its printers

`Scan.Parse` keeps building `q` as today (`Scan.AddFilter`, `q.kinds`, sort fields and so on), but from the reading instead of from words:
- Every filter, sort, step and send records the claim it came from: `q.src[f] = claim` (or `q.srcSort`, `q.srcSteps`). This replaces `said`, `q.picks[i].word`, `q.typedSort.word` and `UI.typedGroup.word`.
- `UI.aggregate` and `self.sendTo` are built from `reading.steps` and `reading.send` in one place (one function used by `TakeAggregate`, `TakeSendTo` and Alt+`).
- **The bar** removes a pick by its span: `line:sub(1, s-1) .. line:sub(e+1)`, after checking the prompt's text is still `reading.line`. It swaps a word the same way. `B.DropWords` and `B.SwapWord` keep their signatures as wrappers for callers that pass words. "Not boe" (a join claim) removes both words, because its span covers both.
- **The Advanced printer**: `ns.QueryToAdvanced` prints `q`, then `reading.setop`, `reading.top`, the bar's Group, the steps and the send, in the one order the search applies them. `E.ToAdvanced` becomes a thin call to it. It no longer calls `TopN` or `SetOp` itself.
- **The words printer**: `E.Explain(line)` reads the line in Advanced mode with the same front end and `Scan.Parse` (`ctx.simple = false`, with a scratch `self` as `QueryToAdvanced` uses), then says the `q` it gets. `FilterSay`, `SortSay`, `LevelSay`, `TimeSay` and `SinceSay` stay as the vocabulary; only the reading is shared.

As built (Phase 4):

- **The bar removes by span.** Each pick carries `src = { s, e, line }`: the bytes of its claim in the line `Scan.Parse` read (a filter's unit, a joined "not boe", a number phrase's words; the sort's; "nearest"'s action word; a typed group's last step from its `|`, the steps claim's `bars`). `B.DropTyped(items)` cuts those spans out when the prompt still starts with that line, else falls back to `B.DropWords` (a line the search rewrote first: a top N, a translation). `B.SwapTyped` swaps "nearest"/"farthest" the same way. Unticking a filter takes out every place that filter was typed ("rare sword rare" leaves "sword", as before, 0.55.18), and only those: "boe linen not boe" unticked Boe leaves "linen not boe" (`DropWords` left "linen not"). The `said` map keyed by a filter's text is gone: a pick's words are its own unit's.
- **One line printer.** `ns.LineToAdvanced` (Search.lua) prints `q` (`ns.QueryToAdvanced`), then the reading's comparison and top N, the bar's Group, the steps and the send. `E.ToAdvanced` is a call to it. The words are printed as they were typed (`q.typedOf`): "Hogger | except @bank".
- **`.explain` reads the shared reading**, not `Scan.Parse`: the send, the steps, a chain's `>`, its words and quoted phrases all come from `Phrase.ReadLine(line, { simple = false })`, and each word is said with the vocabulary as before. Reading it through `Scan.Parse` would change what it says (`sword|type:sword` is a filter to the search but "matching sword|type:sword" to `.explain`, as the golden file has it), which is out of scope.
- **One retry order for questions.** `Scan.ReadQuestion(text, ask)` holds the order (a chain with sorts after it, dates after a question, the line, filters typed after it, numbers in words after it); `Scan.Answer` and `ns.QuestionToAdvancedOf` each pass their own `ask`.

### 4.5 Ambiguity as alternatives

A claim may carry `alt = "words"`: "this may also be plain words of a name". Today that applies to dates, levels from yours, a bare number word, and "the <rank word> <noun>" as first-1. The search:
1. runs the primary reading;
2. if it found nothing (`Scan.AnyReal`) and some claim has an `alt`, and `Scan.AnyNameHas(said)` says a name has that claim's words (cached per words and `ns.entriesGen`), it runs the reading with those claims dropped;
3. keeps the second result only if a name has the words (`Scan.NamesHave`); else it restores the first.

That is today's `noPlain` logic, made general and keyed by claims. `UI:Search`'s special case and `self.plainPhrases` go away.

As built (Phase 5):

- **Which claims carry `alt`:** the plain stage's claims whose filters are a date (`since:`, `older:`) or a level from yours (`lvl:...me`): exactly the ones 0.66.21's retry looked at. The brief's other two (a bare number word, "the <rank word> <noun>" as first 1) are left without one: today nothing reads them again, so giving them an `alt` would change what's listed. That's a question for the player, not this move.
- **The second look:** `UI:Search` takes the alt claims' words from the reading the search left (`Scan.AltPhrases(self.whyQ.reading)`), and when nothing real was found and a name has them (`Scan.AnyNameHas`, cached per words and `ns.entriesGen`), searches again with `UI:SearchText(text, { noAlt = true })`: the reader refuses those claims and leaves their words as words (`Phrase.ReadLine`'s `ctx.noAlt`). Kept only when a name has them (`Scan.NamesHave`), else the first search again.
- **Only those claims go:** "tonight we dine worth more than 1g" is read again as the words "tonight we dine" with `value:>1g` kept. `self.noPlain` dropped the whole plain stage. `self.noPlain`, `self.plainPhrases` and `ctx.noPlain` are gone (a stale `plainPhrases` could also outlive a search a question answered).

### 4.6 Questions

Questions keep their matchers and their answers. What changes:
- `ns.QuestionText(text)` becomes a view over the reading: the same normalized string, built once from the tokens (one cache, shared by all 40 matchers).
- Words two questions both claim, still settled only by the order of `Scan.ANSWERS` (as of 0.56.0): "grey", "missing", "repair", "auction"/"ah", "raid"/"dungeon", "done"/"todo", "learn", "unplaced". The clash test below should start from these.
- Each `Scan.ANSWERS` entry gains `priority` (a number) and `id`. The table is sorted by priority once at load. A smoke test prints, for a corpus of question lines, which entries match each line, so a new clash shows up as a test failure, not as a comment.
- Later, one module per commit, a question may take the token list (`ask(text, reading)`) instead of re-reading the text. The adapter keeps `ask(text)` working, so nothing has to move at once.
- `ns.QuestionToAdvancedOf` and `Scan.Answer` share one function for their chain, date, tail and number retries.

### 4.7 Room for other languages (designed for, not built)

Simple mode's input is English today, apart from the six translated phrase templates in `E.PHRASES`, which `E.English` turns into English lines before reading. Understanding other languages is a possible later feature, **not part of this work**. The design only has to leave room for it:
- **The language comes from the client** (`GetLocale()`), never from guessing at the typed text. English recognizers always run as well, because many players on other clients type English.
- **One tokenizer for every language that writes spaces** (deDE, frFR, esES, esMX, ruRU, koKR, ptBR, itIT). What differs per language is vocabulary and a few rules: Russian word endings, German compound words, French word order. That belongs in recognizers with a `lang` field and per-language word tables, not in a second tokenizer.
- **Chinese (zhCN, zhTW) is the exception.** It writes no spaces between words, so a whitespace tokenizer makes a whole line one token. Name search still works because it matches substrings, but no phrase could ever be recognized. `ns.Lex.Read` takes the splitting rule from a small table keyed by locale, `ns.Lex.SPLIT[locale]`, with whitespace as the only one built now. A later Chinese splitter (known phrases matched against the text, or splitting by a dictionary) slots in there without changing anything downstream.
- Nothing in this work adds non-English vocabulary or L[] texts.

## 5. Plan (one phase at a time; each phase is one or more commits)

Every commit (on the branch: see Decisions for versions and changelog lines):
- the full smoke suite and `tests/check.py` pass;
- a fix gets a test that fails without it;
- no push until the player says "push".

A new .lua file needs a full game restart, not a /reload: say so when a phase adds one. Put new files in the TOC before `Search\Easy.lua` (they're read by Easy, Search and Results at run time).

### Phase 0: lock the behaviour (no code change in the addon)
- Add `tests/parse_corpus.txt`: about 300 lines.
  - **Take:** every Simple line from the existing smoke tests (`easy.lua`, `easy_more.lua`, `plainnumbers.lua`, `datewords.lua`, `topn.lua`, `compare.lua`, `roundtrip.lua`, `questions.lua`, `explain.lua`, `bar.lua`).
  - **Plus:** names that look like phrases ("Tonight We Dine", "The Five Sorrows", "No Rest for the Wicked", "Last Rites", "30 yard range").
  - **Plus:** mixed lines ("linen q:rare >> party", "the 3 nearest mailboxes | count", "hogger but not in my bank").
- Add `tests/gen_parse_golden.py` and `tests/smoke/parse_golden.lua`. For each corpus line, record what the line is read into today:
  - the question id or none;
  - `q.tokens`;
  - each filter's spec and strength (hard, strict or soft);
  - the sort, `q.kinds`, the action and the place;
  - the steps, `topWords`, the send;
  - Alt+`'s line;
  - `E.Explain` of Alt+`'s line;
  - the bar's picks with their words.

  Store the output in `tests/parse_golden.txt`. The test fails on any difference and prints the diff.
- Add `tests/easybench.py`: the per-keystroke timing of Simple lines (type each corpus line one character at a time; report the total and the worst key, Simple and Advanced). Record the 0.67.5 numbers in this document's section 7.
- **Done when:** the golden test passes at 0.67.5, and the bench numbers are recorded.

### Phase 1: the lexer
- `Search/Lex.lua` with `ns.Lex.Read`. Re-implement `Scan.Words` on top of it, with identical outputs: `words` and `phrases`. Keep `Scan.Words`'s signature.
- Unit tests in `tests/smoke/lex.lua`:
  - spans, quotes (including `"a b"c`, an unclosed quote, a quote mid-word), `|`/`>`/`>>`/`>>>` standing alone vs inside words, UTF-8 (`Schwarzfelsspitze`, `Чёрная`), and leading or double spaces;
  - each token's class: `q:rare|epic`, `-is:boe`, `@npc`, `sort:quality,-level` and `in:"Scarlet Monastery"` are syntax; `-boe`, `sword|axe`, `1g50s`, `50%` and `rare&sword` are word; a lone `|` or `>>` is op; `E.IsAdvancedWord` agrees with the syntax class for every word of the parse corpus;
  - half-typed lines (`lvl:`, `@np`, `"tonight we`, `linen |`, `linen >>`): no error, the last token `open`;
  - `ns.Lex.SPLIT` falls back to whitespace for every locale.
- **Done when:** golden unchanged, suite passes, bench within +5%.

### Phase 2: the registry, with the steps and sends moved
- `Search/Phrase.lua` with `ns.Phrase.Register` and `ns.Phrase.ReadLine` (stages send and steps only at first).
- Move into recognizers: `ns.Share.Split` / `PlainCopy` (send), the lone-`|` split, `PerField.Line`, `E.TopN`, `E.SetOp`.
- Make `TakeSendTo`, `TakeAggregate` and `E.ToAdvanced` read `reading.send`, `reading.steps`, `reading.top` and `reading.setop`. Delete their own scanning. Keep `E.TopN(text)` and `E.SetOp(text)` as thin wrappers (tests call them).
- **Done when:** golden unchanged; `E.ToAdvanced` contains no top N or comparison logic of its own; bench within +5%.

### Phase 3: the plain-word stages moved
- Move `DateAt`, `RelativeAt`, `OrderAt` and the number phrases (`OpAt`/`FieldAt`/`NumAt`/`SpanAt`/`ValueAt`) into recognizers in stage plain. Move `JoinPairs` and `JoinLogic` into stage join, `TakeAction` into stage action, and the places into stage place.
- `E.PlainNumbers(words)` stays as a wrapper returning today's `(out, said)` from a reading, because tests and `Scan.Answer` call it.
- `Scan.Parse` builds `q` from the reading and records `q.src`.
- **Done when:** golden unchanged (wrong readings recorded in section 10, not fixed here: see Decisions). Bench within +5%.

### Phase 4: the bar and the printers read the query
- The bar's picks come from `q.src` spans. Removing and swapping work by span. `B.DropWords` and `B.SwapWord` become wrappers.
- `ns.QueryToAdvanced` prints the steps and send from the reading. `E.Explain` uses the shared front end (4.4). `ns.QuestionToAdvancedOf` and `Scan.Answer` share their retries (4.6).
- New tests:
  - the same filter typed twice, unticking one: only that one goes; (as built: only that filter's words go, every place
    it was typed, never another filter's that read the same; "rare sword rare" unticked leaves "sword", as since 0.55.18;
    see 4.4)
  - case kept ("Hogger but not in my bank" → "Hogger");
  - Explain(Alt+`(line)) equals Explain of the Advanced line typed by hand, over the whole corpus;
  - Alt+` of a line equals Alt+` of Alt+` (idempotent), over the corpus.
- **Done when:** golden unchanged except approved fixes; `E.Explain` has no reading of its own; the 26 `SameAsAdvanced` checks still pass.

### Phase 5: alternatives
- Claims with `alt` (4.5). The search's retry is keyed by claims, and `self.noPlain`, `self.plainPhrases` and the special case in `UI:Search` are deleted.
- Tests: the 0.66.21 names, and the cost guard from 0.66.23 (no extra search when no name has the words).
- **Done when:** golden unchanged; bench within +5% (the 0.66.23 numbers in particular).

### Phase 6 (optional, later): questions on tokens
- Priorities as data, the clash test (4.6). Then one question module per commit takes `ask(text, reading)`.
- Ask the player before starting this phase. It touches about 40 files and is the least valuable per hour.

## 6. Invariants (checked by tests where possible)

1. **Spans are honest:** for every claim `c`, `reading.line:sub(reading.toks[c.from].s, reading.toks[c.to].e) == c.said`.
2. **No overlaps:** claims never overlap, and claims plus rest cover every token exactly once.
3. **Pure recognizers:** the same line, ctx and vocabulary always give the same reading.
4. **Simple and Advanced agree:** a Simple line and its Alt+` line list the same results (the existing `roundtrip.lua` and `SameAsAdvanced` checks).
5. **Explain is stable:** Explain(line) == Explain(Alt+`(line)) for the corpus lines that have an Advanced form.
6. **Printing is idempotent:** Alt+`(Alt+`(line)) == Alt+`(line).
7. **Quotes are opaque:** nothing inside a quoted phrase is ever claimed or removed by the bar.
8. **Classes are respected:** a claim covers only tokens of its recognizer's `classes`. In particular, a plain-word recognizer never claims a syntax, quoted or op token.
9. **No new player-facing text,** and all existing L[] keys are kept (`gen_locale.py --check` passes).

## 7. Performance budget

- Measure with `tests/easybench.py` (Phase 0) and `tests/bench.py`. Results are noisy: run each three times and compare the medians.
- **Budget:** per-keystroke total and worst key within +5% of 0.67.5 at every phase. The reading should make it faster, because it replaces about six tokenizations with one.
- **Allocation:** a token table per word and a claim per match are fine (lines are short). No closures created per keystroke, no allocation in a recognizer that doesn't match, and the `first`-token index keeps most recognizers from being asked at all.
- **Instruction budgets:** each smoke file has 20M instructions (the main run 40M). `easy.lua` is about 13M, `datewords.lua` and `explain.lua` are small. The golden test runs about 300 lines, so split it into two files if it nears its budget.
- **0.67.5 baseline** (October 25, 2026, on the player's PC: Windows, Python 3.12, lupa 2.8):
  - `python tests/easybench.py 3`, the 397 corpus lines typed a key at a time (6283 keys a mode), medians of 3 runs:

    | | total | median key | 99% of keys under | worst key |
    |---|---|---|---|---|
    | Simple | 4809 ms | 0.57 ms | 2.40 ms | 19.2 ms ("the cheapest upgrades on the ah", every run) |
    | Advanced | 2994 ms | 0.48 ms | 1.11 ms | 2.84 ms |

    The worst single key swings with the harness's garbage collection (Simple 16–25 ms, Advanced 1.6–8.4 ms over six
    runs): judge the +5% on the total and the 99th percentile, the worst key only by its median over runs.
  - `python tests/bench.py` (30,000 rows), 3 runs: `@benchnpc k` first results 8 ms, longest frame 8 ms, total 24–26 ms;
    fuzzy finding `k` over every list total 24–25 ms (the harness clock steps in whole milliseconds).
- **Compare A/B in one session, not against the numbers above.** The same 0.67.5 code ran 9% slower in the afternoon
  than in the morning (the PC's own load), more than the budget. So each phase is timed against the code before it,
  back to back and alternating (the phase, then the files before it restored, twice).
  - Phase 1 (the lexer): Simple 5324/5350 ms against 5272/5256 ms before (+1.3%), Advanced 3169/3135 against
    3109/3123 (+0.8%).
  - Phase 2 (sends and steps): three alternating runs, medians: Simple 5355 ms against 5932 before (-9.7%, a noisy
    session: read it as not slower), Advanced 3252 against 3265 (-0.4%).
  - Phase 3 (plain words and joins): three alternating runs, medians: Simple 5874 ms against 5683 before (+3.4%),
    Advanced 3531 against 3495 (+1.0%). The first build was +8.6% in Simple mode; what brought it in: each plain
    recognizer asked only at the words its phrases can start with (`first`, `firstMatch`), the asked recognizers picked
    out once per stage (the join stage, all passes, walks no tokens), units carrying their word lowered, the pairs pass
    looking at a word only when some pair starts with it (`E.PairFirst`), and `rest` made only when asked. `Scan.Parse`
    alone is still about 18% slower than before (it now records where everything came from); the keystroke is what's
    budgeted.
  - Phase 4 (the bar and the printers): three alternating runs, medians: Simple 4531 ms against 4552 before (-0.5%),
    Advanced 2742 against 2731 (+0.4%). (A quieter session: both builds ran about 20% faster than in Phase 3's.)
  - Phase 5 (alternatives): three alternating runs, medians: Simple 5152 ms against 5284 before (-2.5%), Advanced 3071
    against 3242 (a noisy session: read both as not slower). The 0.66.23 guard holds: no name with the words, one search
    a keystroke (`tests/smoke/datewords.lua`).
- **The harness gives the character a level of 30** for the golden test and the bench (`UnitLevel`): without one,
  "lvl:me+3" reads as a word, not a filter, which never happens in the game.

## 8. Risks

- **Behaviour encoded only in order.** Several fixes rely on which pass ran first (e.g. JoinLogic's "not" only before an everyday word or a filter; DateAt refusing "last"/"past" after the/of/a/an; TopN's number words only beside a rank word). Keep those conditions inside the recognizers as they are, with their comments, and let the golden test prove it.
- **The bar's picks are the most fragile part:** typed words that become picks, unticking that removes words, and `said` keyed by spec. Move them last (Phase 4), with the bar's existing tests (`bar.lua`, `multisort.lua`, `review065_farbar.lua`) plus the new span tests.
- **The client:** a new file needs a game restart. Lua 5.1 only: no `goto`, no integer division, `#` only on proper sequences.
- **Scope creep:** vocabulary changes, new phrases or "while we're here" fixes don't belong in these commits. Note them for the player instead.

## 9. Questions for the player before starting

Answered: see Decisions at the top.

1. Is it right to build this on the 0.67.x line (0.67.6 onwards) and release it as 0.68.0 when Phase 5 is done, with Phase 6 left for later?
2. Phases 1 and 2 add files (`Search/Lex.lua`, `Search/Phrase.lua`), so the first test of each needs a full game restart. Is that acceptable?
3. Phase 3 may turn up readings the golden file shows as wrong today. Fix them in that phase (each approved by you), or record them and fix them afterwards?

## 10. Wrong readings found on the way (to fix after, each as its own change)

Found while making the Phase 0 golden file (October 25, 2026), each as `tests/parse_golden.txt` shows it at 0.67.5:

1. **Alt+` lowers the search words.** "Hogger but not in my bank" prints `hogger | except @bank`. The query keeps only
   lowercased tokens. **Fixed in Phase 4** (the words printed as typed; `tests/smoke/printers.lua`): the golden file's
   Alt+` and `.explain` lines of the 19 corpus lines with capitals changed, nothing else.
2. **Alt+` lines often end in a space** (348 of the 397): "sword" prints `"sword|type:sword "`. Harmless when typed, but
   invariant 6 (Alt+` of Alt+` is the same) should compare without it, or the printer should trim. **Kept on
   purpose:** `ns.QueryToAdvanced` ends the line with a space to type on (Alt+` leaves the caret there);
   `tests/smoke/printers.lua` compares trimmed.
3. **Names read as phrases when nothing has the name** (the harness has no such rows): "Next Level Thinking" is
   `thinking lvl:me+1`, "Last Day of Summer" `summer since:1d`, "Tonight We Dine" `we dine since:today`. In the game the
   0.66.21 retry reads them as names when a name has the words; Phase 5 keeps that and keys it by claims (done: only the
   date's or level's own words are read as words the second time). Nothing to fix: the harness has no rows with these
   names, so the golden file shows the first reading. Recorded so the
   golden file's readings of them aren't mistaken for the right ones.
4. **"-@npc" is a word, not syntax** (found in Phase 1). Section 4.1 says a leading `-` or `!` before an @kind is
   syntax, but `E.IsAdvancedWord` has always said no, and the lexer keeps its answer (`Lex.IsAdvanced`), so the move
   changes nothing. Whether `-@npc` should mean "not NPCs" is a question for the player, not this work. **The player's
   call: it stays a word.**
5. **Two edge cases now read as the design says** (Phase 2, no corpus line changed): a `>>` inside a "quoted phrase" is
   no longer a send (`SH.Split` used to split there; invariant 7, quotes are opaque), and Alt+` takes the line's last
   `>>` as the send, as the search always did (it used to take the first, so `lvl:>>20 linen >> party` printed wrongly).
   `tests/smoke/phrase.lua` checks the first. Not wrong: recorded as changed.
6. **A plain phrase no longer reads across a "quoted phrase"** (Phase 3, no corpus line changed). The old
   `PlainNumbers` read the line's words with the quoted phrases already taken out, so `under "bob" level 25` read
   `under level 25` as `lvl:<25`. A claim may only take word tokens and the quoted phrase sits inside that span, so it now
   reads "under" as a search word and `level 25` as `lvl:25`. Quotes are opaque (invariant 7), so this is the design's
   reading; `tests/smoke/phrase.lua` checks it. Not wrong: recorded as changed.
7. **"not in my bank" isn't read as "not"** (Phase 4, from the idempotence test). The "not" join is asked before "in"
   and "my" go, so "not" isn't next to "bank" and stays a search word: the golden file has the word "not" and the soft
   filter is:bank. Alt+` writes `not is:bank` (or `not bank` once nothing passed is:bank, as in the golden run), and
   Alt+` of that reads `-is:bank`. Probably meant: what isn't in your bank. **Fixed (the player's call):** said alone,
   a comparison is taken from your items: "not in my bank" is `@item | except @bank`, "not on my alts" `@item | except
   @stored` (the setop claim's `base`, `E.ALONE_BASE`; not "not in my log": no list of items is the log). And the lists
   said without "my" ("in bank", "in the bank", "on alts", "in the mail"...) are comparison phrases too: "linen not in
   bank" read `linen -in is:bank`, now `linen | except @bank`. `tests/smoke/compare.lua`.
8. **"items by zone q:rare" prints `@items`** (Phase 4). `PerField.Line` writes the alias as typed; Alt+` of it writes
   the kind's own word, `@item`. Harmless (both name the same list). **Fixed:** the per line writes the kind's own word
   (`ns:KindName`), as Alt+` does for every other list; `tests/smoke/printers.lua` checks the corpus line.
9. **Alt+` of a question with a date after it now follows the search** (Phase 4, the shared retry order,
   `Scan.ReadQuestion`). When the dates' rest is taken by a question that reads dates itself (the calendar's,
   `ownDates`), the search answers the whole line without the date filters. The old printer instead asked the whole line
   again, of the other questions only, and appended the date filters the search never applied. Alt+` now writes what's
   searched. No corpus line has this, and there's no test of it (the harness has no calendar to ask); recorded as
   changed, not wrong.

## 11. For the release notes: what players see change since 0.67.0

The branch's commits carry no version or changelog line (Decisions, 2). When it's squashed into `main` as one 0.x.y,
Apps/Changelog.lua's in-testing entry and CHANGELOG.md get these, in players' words (beside what 0.67.1–0.67.5 already
say there):

- Alt+` keeps your capitals ("Hogger but not in my bank" -> `Hogger | except @bank`), writes "linen to csv" as
  `linen >>> csv`, writes "items by zone" with `@item`, and writes a name found by its words ("Tonight We Dine") as it
  was searched.
- "not in my bank" (or "not on my alts") on its own lists your items that aren't there; "in bank", "in the bank",
  "on alts", "in the mail" and the like compare a search as "in my bank" does ("linen not in bank").
- Unticking a typed filter on the bar takes out exactly the words that said it: another filter's same word stays
  ("boe linen not boe"), and nothing inside a "quoted phrase" is touched.
- A `>>` inside a "quoted phrase" is part of it, not a send; with two `>>`, the last one is the send (Alt+` agrees).
- A number or date said in words no longer reads across a "quoted phrase" (`under "bob" level 25`).
- A name that has a date's words: the second look reads only the date's words as words, so "tonight we dine worth
  more than 1g" keeps worth more than 1g.
- New files: the first time, the game needs a full restart, not a /reload.

