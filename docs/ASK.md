# !t: guildies ask, Terminal answers (0.68.4; code: Core/Ask.lua, tests: tests/smoke/ask.lua)

Someone in your guild or group who doesn't run Terminal types a question with `!t` in front:

    [Guild] [Bob]: !t nearest innkeeper
    [Guild] [You]: Terminal (Bob): Nearby innkeeper (3): Innkeeper Boorand Plainswind [map pin], ...

One Terminal user's client answers, in the same channel, with one line. Bob needs nothing installed.

Not tried in game yet: see "Trying it in game" at the end.

## The trigger

- `!t <question>` or `!terminal <question>`, at the very start of the message, followed by a space and at least one
  word. Case doesn't matter (`!T`, `!T WHERE...`). 120 characters at most. A linked item or quest is read as its name
  (`!t what drops [Thunderfury]`); the game's other codes are left out (`A.Clean`), so no line sent echoes half a link.
- `!t` alone, or `!t help`, answers with three examples.
- One trigger. `!` is how bot commands start in Discord, on Twitch and in WoW (`!keys` in retail party chat), and it
  stays clear of real questions starting with `?` ("? anyone up for SFK").
- Answers start with `Terminal (Bob):`, so people can tell what answered, and whom.

## Where it listens

| Channel | Answered | Notes |
|---|---|---|
| Guild | when switched on | the main place |
| Party, raid, instance | when switched on | answered in the same channel (party in an instance group: instance chat) |
| Whisper to you | when switched on | only from friends, guildies and your group; only you were asked: no claiming |
| Officer | no | |
| Say, yell, trade, general, other channels | never | sending there needs a key press, and answering strangers is spam |

**Off by default, per channel** (the player's call). The answer goes out under your character's name. Settings:
`db.ask = { guild, group, whisper }` (in Terminal.lua; nil = all off). The first time Terminal sees a `!t` question
in a channel that's off, it tells you once, in your chat only: "Bob asked Terminal something in guild chat. .ask guild
on lets Terminal answer for you." Not again that session.

## A question in another language

Left unanswered, without a word (the player's call). Every client reads a-z (names, numbers, Terminal's English
words); beyond that a German, French, Spanish, Italian or Portuguese client reads Latin letters with accents, a Russian
one Cyrillic, a Chinese one Han, a Korean one Hangul (`A.SCRIPTS`). A letter of any other script, or an emoji: silence.
Marks (`?`, full-width punctuation) don't count.

## One answer, not five

Several Terminal users in a guild all hear Bob's question. Exactly one answers:

1. Each client that would answer waits a random 0.3 to 1.2 s, then sends a hidden addon message, `c:<id>:<its GUID>`,
   on the same channel (prefix `TermAsk`). The id is a short hash of the asker's GUID (their name when there's none)
   and the question: the same on every client. A client in combat, in chat lockdown or switched off doesn't claim.
2. A claim heard before your own timer ends: you drop it.
3. After claiming, a client waits 0.8 s more (longer than a hidden message takes to arrive). Another claim for the
   same id in that time: the lower GUID answers.
4. Whispers have no claiming: only the person whispered answers.

**Your own question.** If Bob runs Terminal himself, his client sees his own `!t` line, claims it at once (no wait,
so the others drop it) and prints the answer in his chat only, nothing sent. This works whatever the settings: it's how
you try it yourself.

## What it answers

World facts only, through Terminal's normal Simple-mode reading of the question, from lists on an allow-list
(`A.ALLOW`): `npc`, `questie`, `loot`, `mailbox`, `forge`, `anvil`, `cookingfire`, `moonwell`, `dungeon`, `raid`,
`flight`, `maps`. The words learned / unlearned / known / unknown / missing are taken out of the question (your flight
paths are yours).

**Never** anything of yours: bags, bank, alts, gold, mail, auctions, professions and recipes, your quest log, your
position, friends' shared bags, guild notes. The allow-list is the rule: a list added later is private until it's
named there.

A word found in several Simple-mode categories ("!t hogger") lists them to pick from; the answer opens the ones holding
a world list, in the order shown, until one has rows.

Its search runs in a view of its own (`A.Rows`: a table reading through to `UI`, the terminal's search state read as
nil), so the terminal's own search, category and narrowing are left as they were, and it always reads in Simple mode.

## From Bob's side

While the answer is searched, `ns.Asker = { here, class, level }` stands in for you:

- `I.Here()` gives Bob's place: his map position if he's in your group and outdoors (`I.UnitSpot(unit)`), else the
  middle of his zone from the guild roster or your friend list (`I.MapSpot(ui, 0.5, 0.5)`, the zone found by name in
  Terminal's zone list), else nothing ("nearest" then finds nothing near him).
- The class trainer filter (`trainer:class`, "my trainer") and "pet trainer" use Bob's class.
- The zone levels ("where should i level") use Bob's level.
- Faction: your guild and group are your faction.

Where Bob is found: your group first (`UnitGUID` against the chat line's GUID), then the guild roster (by its 17th
answer, the GUID, else the name), then your friend list.

## The answer line

- One message, 255 characters at most: `Terminal (Bob): ` and Share's packed line (`SH.GroupLines`, as `>>> party`
  sends): what they are ("Nearby innkeeper (3):"), then each row with its link or map pin, "+N more" when they don't fit.
- Map pins are made by setting your waypoint and reading its link (as `>> party` does); your own waypoint and its
  tracking are put back after.
- Nothing found: "Terminal (Bob): nothing found for "..." (!t help)". A list still loading (Questie's NPCs right
  after login): searched again 2 s later, three times, then the nothing-found line.

## Guards

- Never in chat lockdown (`C_ChatInfo.InChatMessagingLockdown()`; the question's text is secret then anyway), never
  while you're in combat (checked when heard and again when answering). A question more than 20 s old isn't answered.
- Every Terminal counts each question when it hears it and each answer, whichever Terminal gave it, so these hold
  across all of them: one answer to an asker every 10 s; the same question from them once a minute; 6 answers a minute per channel
  (counted again when answering: questions heard together were each under it then).
- One line sent at a time, a second apart.
- `.debug log` traces every question heard and what became of it ("ask: Bob asked "nearest inn": answered").

## Commands

- `.ask`: what's on, and the last eight questions and what became of them.
- `.ask guild on|off`, `.ask group on|off`, `.ask whisper on|off`, `.ask off`.
- `.ask test <question>`: the line that would be sent, as asked by you (your class, level and place). Sends nothing.

## Code

`Core/Ask.lua`: `A.Question`, `A.InLocale`, `A.Asker`, `A.Rows`, `A.AnswerLine`, and `A.New(env)`, one client over an
`env` (me, now, after, random, send, addon, print, locked, combat, setting, asker, answer, locale). `A.live` is the
game's (`A.GAME`). The tests run several clients over a pretend guild channel with a clock of their own.
Hooks elsewhere: `I.Here` / `I.UnitSpot` / `I.MapSpot` (Providers/Integrations/Distances.lua), `MyClass` in
Search/Filters/Npcs.lua, the pet trainer words in Search/Reading/Words.lua, `PlayerLevel` in Providers/Zones.lua.

## Trying it in game

1. `.ask test nearest innkeeper`: the line it would send, nothing sent.
2. Your own `!t nearest innkeeper` in guild chat: the answer in your chat only, nothing sent.
3. With a guildie (or a second account): `.ask guild on`, they type `!t nearest innkeeper`. This is the real check: the
   game letting an addon send a chat line by itself, from a timer (Questie's party announcements on Forever do the
   same). `.debug log` shows each step.
4. In a group outdoors: `.ask group on`, a party member asks "!t nearest mailbox": nearest to them, not you (their map
   position may be refused on Forever: then their zone's middle).

Unverified: all of the above in game; whether the chat event's 12th value is the sender's GUID on Forever (else the
name is used); `C_Map.GetUserWaypoint` / `SetUserWaypoint` putting your pin back.
