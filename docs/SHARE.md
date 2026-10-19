# Terminal: Share — the share shell (`.share`; `.ssh` is its alias)

Terminal: Share is an addon of its own (folder `Terminal_Share`, packaged beside Terminal like Terminal Extras).
Leave it off in the AddOn list and none of this runs: no addon-message prefix is registered and no message is
read. On, friends who run it and agree on a password see each other's bags in their searches: "linen cloth"
lists what you carry, what your alts hold, and what your friends carry ("Linen Cloth x35: Bob 20, Ann 15").

Nothing a friend sends is ever saved: it lives in memory for the session and is gone on logout or /reload.

Friends share in groups (0.59.0): each group has a name, a password of its own, and what you share in it.
`.share password <words>` is the group `default`; `.share join <group> <words>` joins any other (five at most). Friends
who joined the same group with the same password see each other, and each sees from you what you share in the groups
you have in common, together (`.share raid all` and `.share default limited`: a raid friend sees everything, a friend
in both too, a friend only in default your mats and consumables). Who can talk to you is the same whatever the groups.

## Who can talk to you

A message is read only when its sender is one of:

- a character on your friend list,
- a member of your guild,
- the character a Battle.net friend is playing (World of Warcraft, this game's version).

Anything from anyone else is ignored without a reply. The sender is the server's word, never the message's:
a whisper's sender, the guild channel (only members are on it), a Battle.net message's game account. Party,
raid, instance and channel messages are never read. Your own guild message, heard back, is ignored.

## The password

(The command was `.ssh` until 0.58.14: a nod to secure shell, but `.share` says what it does to a WoW player; `.ssh`
still works.)

Each side types the same password: `.share password <password>` or `.share join <group> <password>` (8 characters or
more, no spaces, with three kinds of them: a capital, a small letter, a number, a symbol, a letter of another script:
`SSH.PasswordProblem`, 0.59.3; 0.59.2 asked for 10, or a phrase of 20 with spaces), shown as `*`s while it's typed (a group's name shown) (`ns.MaskSecret`: the prompt draws it so; in the game's typing mode the box is the game's password box). The
password as typed is never kept: Terminal turns it into a key (SHA-256 iterated `SSH.KDF_ROUNDS` = 1,000 times,
2,000 until 0.59.0; 20,000 and 4,000 were tried and were too much for the game's CPU, so the password's own strength
does the work: each guess costs 1,000 hashes, and there are far more passwords to guess; salted with `Terminal.ssh.1`, and `|<group>` for a group
other than default: the same password in two groups is two keys, and a guess needs the group's name too, which is never
sent; done 2 ms a frame, the clock looked at after every hash, a few seconds in all, `.share` and the badge saying how far), and each group's key is remembered in Terminal: Share's own saved variables
(`TerminalShareDB.groups[name] = { key = hex, mode, kdf }`; a key made another way, fewer rounds or the one key of
0.58.6–0.58.16, is forgotten at login and its password asked for again, once). At login they're used again by themselves a few seconds in (friends and guild read first:
`SSH.LOGIN_WAIT`) and everyone is said hello to, once for all of them. Anyone with your WTF folder could connect as
you with them, the same as knowing the passwords. A line starting `.share pass`, `.share pw` or `.share join` is never
written to the history, a tab,
`.missed` or anywhere else saved (`ns.SecretLine`, in Terminal itself so it holds whether Share is loaded or not). Any
`.` line whose second word is `password`, `pass` or `pw` counts: the command search finds `.share` by a shortened or
misspelt name too (`.shar pw ...`). The debug traces write it as `*`s, a click among the `*`s never lands inside a
letter, and leaving Terminal's own keys with it typed (a click into the box) turns the box's password mode on.
Nothing is offered to complete a password's words (Enter runs what's typed). Another password typed for a group says
goodbye to the friends you had only that group with. `.share leave <group>` forgets one group (and says goodbye to
those you had only it with; the others are told, `3L`, and sent what you share with them now); `.share off` forgets
every group, says goodbye to every friend and drops what they sent.

What you share is saved per group (and `.share <mode>` for all of them and groups joined later:
`TerminalShareDB.mode`; Terminal's `db.sshShare` until 0.58.16), so a /reload never shares more than you chose.

## Connecting (mutual challenge-response)

Messages use the addon prefix `TermSSH`; each starts with the protocol version and a letter. The version is `4`
since 0.59.0 (groups, their marks made from their keys; `2`, 0.58.16: delta updates, 150-piece snapshots, sessions); a
hello in another version gets a line in chat, once ("<name> runs another version of Terminal: Share"), and no answer.

```
A -> B   4H nA,idA,sA,marks          hello (sA: A's session, 4 hex characters made at login; marks: A's groups)
B -> A   4C nA,nB,idB,sB,common      challenge: B's nonce, the marks of the groups they have in common
A -> B   4A nA,nB,mark:macI.mark:...  A proves it holds each group's key: macI = HMAC(Kg, "I|nA|nB|idA|idB")
B -> A   4K nA,nB,mark:macR....       B checks each, then proves those that passed: macR = HMAC(Kg, "R|nA|nB|idA|idB")
```

- A group's mark (0.59.0, the player: "hide the group name") is 8 hex characters of HMAC(Kg, "M|session|claim"): made
  from the group's key, so only who has the key can make it or tell which group it is; another every session, so a
  guildmate can't tell your groups apart or follow one from one login to the next. A group's name is never sent. B
  finds its groups in A's hello by making its own marks for A's session and name (`E:MarksOf`, kept per session).
  Five groups' proofs fit one message (246 characters with long names).
- Another password for a group makes another mark: the group isn't in common, so the hello gets no answer ("no
  answer"; the other side lists "<name> wants to connect: no group in common"). No proof is ever sent to someone without
  the key. A proof that fails all the same is said ("<name>'s password for raid doesn't match yours"). No group proven
  on the way you send to a friend by: they're dropped.

- Nonces are 16 hex characters (SHA-256 of the time, a counter, `math.random`). Proofs are 32 hex characters
  (128 bits of the HMAC).
- `idA`/`idB` ("claims") are the characters as `name@realm`, lowercase, the name's words joined by `-`
  ("Plamen Warr" -> `plamen-warr@classicbetapvp`). A claim is accepted only when it names the character the
  server says sent it (`SSH.ClaimIs`: the sender is `name-realm`, or `name` and the realm is yours, spaces and `-`
  alike). Because
  both proofs name both characters, a third character can't pass one friend's proof on to another (a relay:
  Ann's proof to Mal names Ann and Mal; Bob wants one naming Mal and Bob).
- On Forever, Battle.net gives the character's full name with its surname ("Girl Bird", realm "ClassicBetaPvP") and
  its GUID (`playerGuid`, "Player-4619-..."), as does the guild roster (seen in game, 0.59.3): a claim over Battle.net is
  then that name exactly ("girl-bird@classicbetapvp"), nothing added. In case Battle.net gives a first name only
  ("Bob"), a claim over it may add the surname ("bob-warr@realm"), and that surname is checked (0.59.1): when your friend list or guild roster knows a character of that name and Battle.net
  gives the friend's character's GUID, the two GUIDs must be the same; a name they know without a GUID to compare
  isn't taken over Battle.net (that friend connects the way they're known by); a surname no one else is known by is
  kept, this session, by the Battle.net account first proven with it (`SSH.bnOwner`, set by the env's `proven`).
- `I` and `R` make the two proofs different: one can't be sent back as the other.
- A connection is made only when the proof checks. A wrong password gets no answer (its marks aren't the
  group's): `.share` says "no answer" after 30 s, and the other side lists you as wanting to connect.
- The password is never sent. Someone who sees a proof, or a mark, could guess passwords offline against it, so
  the key is 1,000 rounds of SHA-256 (each guess as many) and a password must be strong (above), salted with the group's name (never sent: a guess needs
  it too, but "default" is known), and a password should be long and one not used anywhere else. Since marks are
  made from keys, only someone who already has a group's key gets a proof for it from you: a guildmate without it
  gets no answer at all.
- Both saying hello at once (the guild channel at login): the smaller claim's hello goes on and the other
  side answers it. The smaller side says its hello again, with the same nonce, to a friend whose hello it
  hears while waiting: that friend may have heard the first one before it had a password.
- The same hello again while you challenge it (it left a busy queue late): your challenge again, the same nonce, so
  their proof of the first still fits.
- Limits: a friend can start a handshake at most every 5 s; at most 20 handshakes others started are under way at
  once (your own hellos aren't counted). A handshake's 30 s start when its message leaves the queue, not when it's
  queued.
- A friend connected already hears your guild channel hello to others and lets it be when it's the same session of
  yours and the same groups in common; a new session (you /reloaded), or a group joined, is a new handshake. While a
  way is proven again, what comes on it still lands, and when it's the same way and session nothing is sent whole
  again unless what you share with them changed.
- Hello again: a friend (or the guild channel) who didn't answer is said hello to again 10 minutes on, then 20, 40, 80
  (a hello lost while chat was locked, a friend list read late at login); a friend not tried yet, within a minute.

## Ways and friends

A friend can reach you several ways at once: the guild channel and whispers (one way: the server may write the
name "Bob" or "Bob-Realm", your own realm is dropped), and Battle.net game data ("b:<game account>"). Each way
has its own handshake (`peers`); a friend (`friends`, by claim) is connected once any way is proven, data from any
proven way lands on them, and what you share goes the newest proven way, by the groups proven on that way (not every
way's together: a way proven in one group gets that group's share only). `.share debug` lists both, with what was
sent (the game's answers) and heard.

## Sharing

Once connected, each side sends what it shares, and sends it again when it changes (at most every 15 s to a
friend, or every 2 s per message for a big snapshot; what didn't change isn't sent again):

```
4D ver,i,n,payload       a snapshot in n pieces of at most 200 characters (at most 150), put back together as they
                         were. The snapshot: places!items!gold!mode (never a "|", chat's escape character: it doesn't
                         survive Battle.net game data)
                           places  "Bob/b,Bobalt/k,/w"   who and where: b bags, k bank, m mail, v void storage,
                                                         w warband bank
                           items   "id:place.count,place.count;id:..."  (base 36; place counted from 0)
                           gold    copper in base 36, or empty
                           mode    what they share (limited, all, ...)
4U ver,base,i,n,payload  what changed since snapshot `base`: "id:entry;id:x;...!gold" (x: gone). Sent when the
                         friend has `base` whole, the places and mode are the same, and it's under half the size
4R                       I don't have your `base`: the next goes whole
4L mark                  I left that group (my mark for it): what you share with me is what's left in common
4P                       still here (every 10 minutes)
4B                       goodbye: drop what I sent
```

`ver` is the session's mark and a count (`a3f01`, `a3f02`...): a /reload's numbers are never taken for the last
session's. Pieces are put together by their kind, number, base and count all at once.

What you share, per group (`.share <group> <mode>` or `.share <mode> <group>`; `.share <mode>` in every group and those
joined later; `.share share <mode>` too). A friend gets the modes of the groups you have in common together
(`SSH.Union`: mats and consumables are limited; anything and all is all):

| Mode | |
|---|---|
| `limited` (the default) | this character's crafting mats and consumables, in its bags and its bank (as @stored has the bank: Syndicator or BagBrother; sent again when @stored's records change) |
| `all` | everything in this character's bags, everything on your other characters and in your banks, mail, void storage and warband bank as @stored reads them (Syndicator or BagBrother; worn gear, auctions and guild banks aren't shared), and your gold (all characters', as @gold totals it) |
| `mats` | this character's crafting mats (trade goods, reagents, crafting reagents: as @mats), bags and bank |
| `consumables` | this character's consumables (the game's Consumable class: as @consumable), bags and bank |
| `none` | connect and see, share nothing |

- The bank is a place of its own in a snapshot (`k`), the bags another (`b`): a friend's row says them apart.
- One snapshot is made per mode in use among your groups (at most four), once a bag change, for every friend it goes
  to; the delta from the last one is worked out once for every friend who had it (`E:DeltaOf`).
- A friend's items are dropped after 30 minutes without a word, on goodbye, and within a minute of their no
  longer being a friend or guild member. What was still queued for them goes with them.
- Data or a ping from a friend you aren't connected to (you /reloaded and typed the password again) makes
  you say hello to them again (at most every 30 s).
- Sends go through a queue: six at once, then one a second (the game allows ten, then one a second); a
  handshake goes before items still waiting; the game's "throttled" answer keeps a message in the queue; of
  friends' items, the friend with the fewest pieces left goes first (a one-message update never waits behind another
  friend's hundred pieces). A snapshot still going out isn't replaced: the next change waits for its last piece, then
  goes as what changed since. Nothing is sent while the game locks chat messaging
  (`C_ChatInfo.InChatMessagingLockdown`), and a message whose fields are secret values is ignored.
- `.share off`'s goodbyes go through the queue too: one the game says wait to goes a second later.

## In searches

`@shared` (also `@ssh`; its rows labelled Shared): one row per item per friend ("Linen Cloth x20 · Cad Man · bags 12,
bank 8", "x15 · Cherry Tusks · bags 15": where they keep it, bags and bank apart), each with its owner: the bar's Group and Sort offer Owner, as do `sort:owner` and `| group by owner`. The
tooltip is the game's item tooltip, then that friend's characters as @stored shows yours ("Plamen Pally  53  bags 18,
bank 35"), and who else has it; Shift+Enter and the chat line (`>> party`) are @stored's too. A friend sharing `all`
has a gold row ("Bob's gold"; "gold" finds it). A plain search lists them too. It's in Simple mode's Bank & alts
category, and `linen cloth > alts` lists it with your alts. Item filters work on it (`@shared q:rare`, `@shared
on:bob`). A group's name finds its friends' items (`@shared raid linen`), and the tooltip says the groups ("Shared in:
raid, default") when there's more than the default one. Enter whispers that friend. A Battle.net friend is named by their character, never their account name.

## The badge

While the share shell is on (a password set), a wifi sign (a dot and three arcs) sits at the end of the prompt, in
the spinner's spot (left of it while it spins): the theme's accent with a friend connected, its arcs lit in turn
while connecting, red with nobody connected and nothing under way. It's at full strength as the terminal opens and
when a friend connects or goes, and fades to a faint mark after 6 s; pointed at, it's back. It's not there while
anything is typed in the prompt (badges never are). Pointing at it (or clicking it, which keeps it up) pops out
Terminal's own tooltip in the row tooltip's place beside the terminal (the row's put away meanwhile), a line each:
"Sharing" and you (how many items), your groups by name and what you share in each ("Group  default: limited"; "Groups
raid: all · default: limited"), each friend (their groups too when you're in several)
("Cad Mán  39 items · all · raid · Battle.net", how long
since they were heard once it's a minute or more), who's still connecting (a "no answer" for 30 s, then not said),
and, after a gap, ".share off to disconnect". It's Terminal's `UI.AddBadge` (Prompt.lua: draw, shown, refresh,
tooltip, fade), which any addon can use for its own.

## Commands

| Command | |
|---|---|
| `.share` | who you're connected to, who's waiting, what you share |
| `.share password <words>` | the default group's password; say hello to your friends and guild |
| `.share join <group> <words>` | join a group of its own, with its own password (five groups at most) |
| `.share leave <group>` | leave a group, its password forgotten |
| `.share <group> <mode>`, `.share <mode> <group>` | what you share in one group (`.share <group>` alone: what it shares) |
| `.share connect [name]` | say hello again: to one friend, or to everyone |
| `.share limited \| all \| mats \| consumables \| none` | what you share in every group (`.share share <mode>` too) |
| `.share off` | leave every group, say goodbye, drop everything |

## Code

- `Terminal_Share/Crypto.lua`: SHA-256, HMAC-SHA256 (the game's `bit` library, or plain arithmetic).
- `Terminal_Share/Share.lua`: `SSH.Endpoint(env)` is the protocol, reaching the game only through `env`;
  `SSH.game` is this client's. The rows (`@shared`), `.share`, and the game's events (`SSH.OnEvent`).
- Terminal itself: `ns.SecretLine` (Core/Util.lua), the `shared` kind in Simple mode's Bank & alts, the item
  filters and the `alts` relation.
- Tests: `tests/smoke/crypto.lua` (standard vectors, both bit paths), `tests/smoke/share.lua` (endpoints
  talking: connect, wrong password, strangers, a relay, both at once, the queue, dropping, deltas, retries),
  `tests/smoke/share_groups.lua` (groups: what each sees, a password not matching, joining and leaving, five at once,
  the review's cases), `tests/smoke/share_game.lua` (the game's events and calls, the prompt, searches, nothing saved).
  The pretend network they share is `tests/share_net.lua`.
- `@shared` rows are compact (Terminal's lazy rows: an item's quality, icon, link and tooltip lines made when shown),
  made per friend and kept until that friend's items change: one friend's update makes only theirs again.

## How far it goes (`python3 tests/stress.py [friends,...] [items,...] [--groups 1,3,5] [--search 20000,...]`)

The stress test loads Terminal and Terminal: Share in the smoke harness and measures three things. Its times are this
harness's (Lua 5.1 through lupa: they compare with `tests/bench.py`'s, not the game's exactly); 0.59.0.

**1. Sharing with friends** (`.share all`, every item in one or two places): one snapshot, a full round to every friend
at the game's pace, a 5-item change, reading the snapshots, making the `@shared` rows (and their memory), one friend's
update, a plain and an `@shared` search.

| friends × items | snapshot | first sync | an update | rows made / one friend's | memory | search (total) |
|---|---|---|---|---|---|---|
| 10 × 100 | 7 msgs | 1 min | 1 msg | 4 / 1.5 ms | 0.9 MB | 2 ms |
| 10 × 500 | 30 msgs | 5 min | 1 msg | 12 / 4 ms | 4 MB | 5 ms |
| 25 × 500 | 30 msgs | 12 min | 1 msg | 32 / 8 ms | 10 MB | 13 ms |
| 10 × 2000 | 119 msgs | 20 min | 1 msg | 59 / 15 ms | 17 MB | 20 ms |
| 25 × 2000 | 119 msgs | 50 min | 1 msg | 174 / 40–140 ms | 41 MB | 90 ms |
| 50 × 2000 | 119 msgs | 99 min | 1 msg | 300 / 63 ms | 83 MB | 105–111 ms |

**2. One group against several** (the side that shares; each group sharing another mode, friends spread over them,
every third in two). What a friend receives is one snapshot whatever the groups, so their side is part 1's.

| groups | friends × items | handshake proofs (A message) | a bag change: snapshots, CPU, messages |
|---|---|---|---|
| 1 | 50 × 500 | 1 (78 chars) | 1, 8 ms, 50 |
| 3 | 50 × 500 | up to 3 (162 chars) | 2, 8 ms, 50 |
| 5 | 50 × 500 | up to 5 (246 chars) | 4, 8 ms, 43 |
| 1 | 50 × 2000 | 1 | 1, 27 ms, 50 |
| 5 | 50 × 2000 | up to 5 | 4, 31 ms, 43 |

Groups cost the side that shares one snapshot per mode in use (four at most) a bag change, and a proof per group in
a handshake; messages stay one per friend an update (fewer: a friend in a group sharing none gets nothing).

**3. Searching many entries** (made-up rows over 24 lists in three Simple-mode categories, every list in a plain
search; each search as the terminal runs it, a slice a frame):

| rows | wide search ("k"): first frame / longest / total | nothing found | one list (@kind) | Simple mode's categories: longest / total |
|---|---|---|---|---|
| 20,000 | 8 / 8 / 41 ms | 41 ms | 11 ms | 8 / 41 ms |
| 100,000 | 13 / 13 / 197 ms | 237 ms | 51 ms | 9 / 202 ms |
| 200,000 | 11–31 / 15–31 / 351 ms | 488 ms | 100 ms | 8 / 406 ms |

- A search's frames stay at ~8 ms (16 with the harness's garbage collection now and then) however many rows: what grows
  is how many frames the results take to settle, ~0.4 s at 200,000 rows.
- The stress test found two frames that grew with the rows, fixed in 0.59.0: Simple mode sorted every match into its
  category in one frame (half a second at 200,000 rows; now a slice a frame, and a row's category from a map made
  once), and a search's first frame picked the best of every match so far to show (20 ms more at 200,000; now 3 ms at
  most, the rest a few frames on).
- Sharing: the limit that shows first is the game's send rate (one message a second): the first full sync to everyone
  grows with friends × items; after it, a bag change is one message per friend. Making the `@shared` rows is one
  frame: past ~25 friends × 500 items (12,500 rows) a friend's update is a hitch of 10 ms or more; ~0.8 KB a row.
