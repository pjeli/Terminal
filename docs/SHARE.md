# Terminal: Share — the share shell (`.share`; `.ssh` is its alias)

Terminal: Share is an addon of its own (folder `Terminal_Share`, packaged beside Terminal like Terminal Extras).
Leave it off in the AddOn list and none of this runs: no addon-message prefix is registered and no message is
read. On, friends who run it and agree on a password see each other's bags in their searches: "linen cloth"
lists what you carry, what your alts hold, and what your friends carry ("Linen Cloth x35: Bob 20, Ann 15").

Nothing a friend sends is ever saved: it lives in memory for the session and is gone on logout or /reload.

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

Each side types the same password: `.share password <words>` (8 characters or more), shown as `*`s while it's
typed (`ns.MaskSecret`: the prompt draws it so; in the game's typing mode the box is the game's password box). The
password as typed is never kept: Terminal turns it into a key (SHA-256 iterated `SSH.KDF_ROUNDS` = 2000 times,
salted with `Terminal.share.1`, done a slice a frame), and that key is remembered in Terminal: Share's own saved
variables (`TerminalShareDB.key`, hex). At login it's used again by itself a few seconds in (friends and guild read
first: `SSH.LOGIN_WAIT`) and everyone is said hello to. Anyone with your WTF folder could connect as you with it,
the same as knowing the password. A line starting `.share pass` or `.share pw` is never written to the history, a tab,
`.missed` or anywhere else saved (`ns.SecretLine`, in Terminal itself so it holds whether Share is loaded or not).
Another password typed says goodbye to the friends connected with the old one. `.share off` forgets the key (and the
remembered one), says goodbye to every friend and drops what they sent.

The share mode (`.share share ...`) is a setting and is saved (`db.shareShare`), so a /reload never shares more
than you chose.

## Connecting (mutual challenge-response)

Messages use the addon prefix `TermSSH`; each starts with the protocol version `1` and a letter.

```
A -> B   1H nA,idA             hello
B -> A   1C nA,nB,idB          challenge (B has a password: its own nonce)
A -> B   1A nA,nB,macI         A proves it holds the key: macI = HMAC(K, "I|nA|nB|idA|idB")
B -> A   1K nA,nB,macR         B checks macI, then proves it too: macR = HMAC(K, "R|nA|nB|idA|idB")
```

- Nonces are 16 hex characters (SHA-256 of the time, a counter, `math.random`). Proofs are 32 hex characters
  (128 bits of the HMAC).
- `idA`/`idB` ("claims") are the characters as `name@realm`, lowercase, the name's words joined by `-`
  ("Plamen Warr" -> `plamen-warr@classicbetapvp`). A claim is accepted only when it names the character the
  server says sent it (`SSH.ClaimIs`: the sender is `name` or `name-realm`, spaces and `-` alike). Because
  both proofs name both characters, a third character can't pass one friend's proof on to another (a relay:
  Ann's proof to Mal names Ann and Mal; Bob wants one naming Mal and Bob).
- `I` and `R` make the two proofs different: one can't be sent back as the other.
- A connection is made only when the proof checks. A wrong password gets no answer; the side that checked
  says "<name>'s password doesn't match yours", the other side's `.share` says "no answer" after 30 s.
- The password is never sent. Someone who sees a proof could guess passwords offline against it, so the key
  is iterated and the password should be one not used anywhere else.
- Both saying hello at once (the guild channel at login): the smaller claim's hello goes on and the other
  side answers it. The smaller side says its hello again, with the same nonce, to a friend whose hello it
  hears while waiting: that friend may have heard the first one before it had a password.
- Limits: a friend can start a handshake at most every 5 s; at most 20 handshakes are under way at once.

## Ways and friends

A friend can reach you several ways at once: the guild channel and whispers (one way: the server may write the
name "Bob" or "Bob-Realm", your own realm is dropped), and Battle.net game data ("b:<game account>"). Each way
has its own handshake (`peers`); a friend (`friends`, by claim) is connected once any way is proven, data from any
proven way lands on them, and what you share goes the newest proven way. `.share debug` lists both, with what was
sent (the game's answers) and heard.

## Sharing

Once connected, each side sends what it shares, and sends it again when it changes (at most every 15 s to a
friend, or every 2 s per message for a big snapshot; what didn't change isn't sent again):

```
1D ver,i,n,payload    a snapshot in n pieces of at most 200 characters (at most 100 pieces), put back together as
                      they were. The snapshot: places!items!gold (never a "|", chat's escape
                      character: it doesn't survive Battle.net game data)
                        places  "Bob/b,Bobalt/k,/w"   who and where: b bags, k bank, m mail, v void storage,
                                                      w warband bank
                        items   "id:place.count,place.count;id:..."  (base 36; place counted from 0)
                        gold    copper in base 36, or empty
1P                    still here (every 10 minutes)
1B                    goodbye: drop what I sent
```

What you share (`.share <mode>`, or `.share share <mode>`; saved as a setting, `db.shareShare`):

| Mode | |
|---|---|
| `limited` (the default) | this character's crafting mats and consumables (its bags) |
| `all` | everything in this character's bags, everything on your other characters and in your banks, mail, void storage and warband bank as @stored reads them (Syndicator or BagBrother; worn gear, auctions and guild banks aren't shared), and your gold (all characters', as @gold totals it) |
| `mats` | this character's crafting mats (trade goods, reagents, crafting reagents: as @mats) |
| `consumables` | this character's consumables (the game's Consumable class: as @consumable) |
| `none` | connect and see, share nothing |

- A friend's items are dropped after 30 minutes without a word, on goodbye, and within a minute of their no
  longer being a friend or guild member.
- Data or a ping from a friend you aren't connected to (you /reloaded and typed the password again) makes
  you say hello to them again (at most every 30 s).
- Sends go through a queue: six at once, then one a second (the game allows ten, then one a second); a
  handshake goes before items still waiting; the game's "throttled" answer puts a message back in the queue;
  a newer snapshot to a friend replaces one still waiting. Nothing is sent while the game locks chat messaging
  (`C_ChatInfo.InChatMessagingLockdown`), and a message whose fields are secret values is ignored.

## In searches

`@shared` (also `@ssh`; its rows labelled Shared): one row per item per friend ("Linen Cloth x20 · Cad Man", "x15 · Cherry
Tusks"), each with its owner: the bar's Group and Sort offer Owner, as do `sort:owner` and `| group by owner`. The
tooltip is the game's item tooltip, then that friend's characters as @stored shows yours ("Plamen Pally  53  bags 18,
bank 35"), and who else has it; Shift+Enter and the chat line (`>> party`) are @stored's too. A friend sharing `all`
has a gold row ("Bob's gold"; "gold" finds it). A plain search lists them too. It's in Simple mode's Bank & alts
category, and `linen cloth > alts` lists it with your alts. Item filters work on it (`@shared q:rare`, `@shared
on:bob`). Enter whispers that friend. A Battle.net friend is named by their character, never their account name.

## The badge

While the share shell is on (a password set), a wifi sign (a dot and three arcs) sits at the end of the prompt, in
the spinner's spot (left of it while it spins): the theme's accent with a friend connected, its arcs lit in turn
while connecting, red with nobody connected and nothing under way. It's at full strength as the terminal opens and
when a friend connects or goes, and fades to a faint mark after 6 s; pointed at, it's back. It's not there while
anything is typed in the prompt (badges never are). Pointing at it (or clicking it, which keeps it up) pops out
Terminal's own tooltip in the row tooltip's place beside the terminal (the row's put away meanwhile), a line each:
"Sharing" and you (how many items, what you share), each friend ("Cad Mán  39 items · all · Battle.net", how long
since they were heard once it's a minute or more), who's still connecting (a "no answer" for 30 s, then not said),
and, after a gap, ".share off to disconnect". It's Terminal's `UI.AddBadge` (Prompt.lua: draw, shown, refresh,
tooltip, fade), which any addon can use for its own.

## Commands

| Command | |
|---|---|
| `.share` | who you're connected to, who's waiting, what you share |
| `.share password <words>` | set the shared password (this session) and say hello to your friends and guild |
| `.share connect [name]` | say hello again: to one friend, or to everyone |
| `.share limited \| all \| mats \| consumables \| none` | what you share (`.share share <mode>` too) |
| `.share off` | forget the password, say goodbye, drop everything |

## Code

- `Terminal_Share/Crypto.lua`: SHA-256, HMAC-SHA256 (the game's `bit` library, or plain arithmetic).
- `Terminal_Share/Share.lua`: `SSH.Endpoint(env)` is the protocol, reaching the game only through `env`;
  `SSH.game` is this client's. The rows (`@shared`), `.share`, and the game's events (`SSH.OnEvent`).
- Terminal itself: `ns.SecretLine` (Core/Util.lua), the `shared` kind in Simple mode's Bank & alts, the item
  filters and the `alts` relation.
- Tests: `tests/smoke/crypto.lua` (standard vectors, both bit paths), `tests/smoke/share.lua` (endpoints
  talking: connect, wrong password, strangers, a relay, both at once, the queue, dropping),
  `tests/smoke/share_game.lua` (the game's events and calls, searches, nothing saved).
