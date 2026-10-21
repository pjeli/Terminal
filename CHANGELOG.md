# Changelog

## 0.62.0 (in testing)

**Auctionator**
- With Auctionator installed, Terminal reads its auction house prices (through its API for other addons; scan the auction house with Auctionator to have them).
- Items have an **AH value**: **sort:ahvalue** (the bar's Sort: AH value), **| sum ahvalue**, **| avg ahprice**, on your bags, your alts', loot and the items recipes make.
- **what should i auction** (or **what can i sell on the ah**): your bag items worth more on the auction house than at a vendor, not bound, the most valuable first, each with what it would bring and what a vendor pays; the note says about what they come to (**@item is:auctionable sort:ahvalue**).
- **ah value of my mats** / **what are my mats worth** (**@mats | sum ahvalue**), and the same for your bags, consumables and gear.
- **what should i do** says **Post on the auction house** when your bags would bring a gold or more, and the empty prompt may say **try: what should i auction (about 30g)** or **try: ah value of my mats (about 12g)**.
- **@auction**: each auction up now says the auction house's price now, and **undercut** (orange) when it's below yours; **am i undercut** / **@auction is:undercut** lists those.
- **.integrations** says whether Auctionator was found.


**What should I do?**
- Ask **what should i do** (or **what now**, **suggestions**, **im bored**) for what's worth doing now, the most pressing first: gear to repair when a piece is low, junk to sell (grey items, or bags nearly full), class spells or a weapon skill to train, a profession at its cap with its next rank to learn (or one to level, with its plan), your class quest once you're its level (Attune; Enter lists its steps, and Enter on a step opens Attune on it), quests ready to turn in, quests at your level where you are or a better zone to move on to (Questie), and the dungeon that fits your level (its upgrades, with AtlasLoot). Each row says why; Enter searches for it ("nearest repair", "nearest vendor", "nearest mage trainer", "quests to turn in"...), and its tooltip shows the same search in Advanced syntax.
- **try: what should i do** is one of Simple mode's empty prompt examples, coming up sooner when there's something worth doing (from what Terminal has already read: opening the terminal builds nothing, and the prompt stays empty).

**Plain questions, and their Advanced syntax**
- **quests to turn in** / **turn in quests** / **which quests are ready**: your quest log's quests ready to turn in (**@questlog is:complete**).
- **quests here** / **quests in this zone**: Questie's quests at your level in the zone you're in, not done yet (**@questie lvl:20-25 in:<zone>**).
- **what can i craft** / **what can i cook** / **craftable**: your recipes you have every reagent for (**@recipe is:craftable**).
- **nearest class trainer** / **my trainer**: your class's trainers (**trainer:class**), no longer NPCs with "class" in their names; **nearest weapon trainer** / **weapon master**: the weapon masters (**is:weaponmaster**). A weapon or profession named with them is theirs: **nearest fist weapons trainer** is **trainer:fist** (Sayoc in Orgrimmar), **my tailoring trainer** **trainer:tailoring**; in Advanced mode **@npc trainer:fists**, **trainer:staff**, **trainer:daggers** list the weapon masters What's Training or TrainerSpells says teach it.
- **quests per zone** / **my quests by zone** / **quests by level** (and **<list> per <field>**): the list grouped by it (**@questie | group by zone**); the bar shows it as its Group.
- Enter on a group steps into it: the words you typed to find the group go ("@questie Death" grouped by zone, Enter on Deathknell: **@questie in:"Deathknell"**, every quest there), not left beside it.
- **low durability** is **@durability**; **dungeons at my level** and **best dungeon for upgrades** are the dungeon for your level, as "what dungeon should i do".

**Terminal: Share**
- Terminal: Share shares only with characters on your own realm: a Battle.net friend playing on another realm (another ruleset, PvE beside PvP) isn't connected to, and their items aren't shown. A Battle.net friend on your realm still is, whatever their faction.

## 0.60.0

**Terminal: Share, a new addon that comes with Terminal**
- Friends who run it and type the same password see what's in each other's bags in their searches: "linen cloth" lists what you carry, what your alts hold, and what your friends have, with how many each has. It's **@shared** (also **@ssh**), in Simple mode's Bank & alts, and **linen cloth > alts** lists it with your alts.
- **.share password <password>** (8 characters or more, no spaces, with three of: capitals, small letters, numbers, symbols) connects you with your friend list, your guild and your Battle.net friends' characters who use the same one. The password shows as \*s while you type it and is never sent or saved; a key made from it is remembered, so you connect again by yourself when you log in. **.share off** forgets it.
- Don't want it? Turn Terminal: Share off in the AddOn list and none of it runs.

**Groups**
- **.share join <group> <password>** joins a group of its own, with its own password: a raid team, a crafting circle, your alts' friends. Five groups at most; **.share password** is the group "default".
- Each group shares what you choose: **.share raid all**, **.share default limited** (or **.share all raid**). A friend sees what you share in the groups you have in common, together: a raid friend everything, a friend only in default your mats and consumables.
- **.share leave <group>** leaves one (its password forgotten; friends you had only it with are said goodbye to). **.share** lists your groups and what each shares; the wifi sign's pop-out says each friend's groups.
- **@shared raid linen** finds your raid friends' linen; a friend's tooltip says which groups you share with them.

**What you share**
- **.share limited** (the default): this character's crafting mats and consumables, in its bags and its bank (as @stored has the bank: Syndicator or BagBrother).
- **.share all**: everything in your bags, on your other characters and in your banks, mail, void storage and warband bank (as @stored reads them), and your gold.
- **.share mats**, **.share consumables**: just those, bags and bank. **.share none**: see your friends' items, share nothing.

**Friends' items**
- A row for each friend, saying where they keep it, bags and bank apart ("Linen Cloth x20 · Cad Man · bags 12, bank 8"), grouped or sorted by **Owner** from the bar, **sort:owner** or **| group by owner**. Item filters work on them (**@shared q:rare**).
- The tooltip is the item's own, with that friend's characters below it as @stored shows yours. Enter whispers the friend; Shift+Enter and **>> party** work as with @stored.
- A friend sharing **all** has a gold row ("Bob's gold").

**The wifi sign**
- While you share, a small wifi sign sits at the end of the prompt: lit with a friend connected, its arcs moving while it connects, red with nobody connected. It fades after a few seconds and steps aside while you type.
- Point at it (or click it, to keep it up) for who's connected, how many items each shares and what, and who hasn't answered.

**Private and light**
- Only friends, guild members and Battle.net friends' characters are heard; anyone else is ignored. A Battle.net friend is named by their character, never their account name.
- A Battle.net friend's character is checked before it's taken for one: by its GUID against your friend list's and guild roster's characters, the name Battle.net gives it, and its realm. A friend with the same first name can't pass for another.
- What friends send is kept in memory only, until you log out.
- After the first sync only what changed is sent, usually one message; a small update never waits behind another friend's big one, and friends who missed your hello are said hello to again later.
- Passwords show as \*s while you type them however you write the command, in the prompt and in the tab strip, are never completed or kept in your history; Enter runs exactly what you typed.
- Group names are never sent: a group is known in messages only by a mark made from its password, another every session. A password needs 8 characters or more, no spaces, with three kinds of them (capitals, small letters, numbers, symbols): hard to guess. It's turned into a key a sliver of each frame, so play stays smooth (**.share** says how far), and logging in uses the remembered key.

**Fixes and speed-ups from a review**
- Logging in with saved passwords keeps sharing going all session (friends were dropped after half an hour).
- A friend who dropped you gets your items again when you reconnect; friends who already have yours keep hearing from you while a big first sync goes to others.
- With many friends online who don't run Terminal, the ones who do still connect at login.
- Selling a stack of greys or looting a run of mobs sends one update, not one per bag change, and your bank is read in its own time, never in the middle of combat or a bag change.
- A big guild's roster changes no longer cost a hitch when a friend's message comes in.

**Searching very large lists**
- Every frame of a search stays short however many rows there are: Simple mode's categories no longer sort every match in one frame, and a search's first results no longer stall picking the best of thousands (found by a new stress test: up to 200,000 rows over 24 lists).

## 0.58.0

**TrainerSpells**
- Terminal reads TrainerSpells when it's installed, at the moment you search (nothing of it is copied). Either What's Training or TrainerSpells is enough for training.
- Without What's Training, **@training** lists your class's spells, weapon skills and pet abilities still to learn: a hunter's from the pet trainers, a warlock's demons' grimoires from the Demon Trainers. "what can i train", "what do i learn next level" and "where to learn ..." work with it, and every class's spells come from it.
- Without Questie, its trainers and weapon masters are **@npc**: "nearest mage trainer", "polearm trainer".

**Profession training**
- The recipes a trainer teaches that you don't know are listed with your other recipes to learn, with the skill each needs and its cost, even before you've opened the profession's window: "what can i train in tailoring", "how much is tailoring training".
- **@profession** shows each profession's next rank, the skill it needs and its cost.

**Trainers**
- "polearm trainer" and the like list only the weapon masters who teach that weapon to your faction (What's Training's or TrainerSpells' list), not every weapon master.

**Other addons**
- When an addon's data isn't in the shape Terminal expects (a new version of it), chat says once what's unavailable, and **.integrations** lists it.
- **.integrations** has one Training line: What's Training or TrainerSpells, whichever is installed, with how many spells you have to learn.

**Fixes and speed-ups from a review**
- Down after closing brings back what you typed, not its Advanced syntax or a fuzzy find's letters.
- Filters whose answer changes by itself (is:ready, near:) stay right as you type.
- Sold auctions keep their posted price when the chat line comes before the notification; .mail forget also forgets that character's sales.
- A merchant who doesn't repair no longer shows the last repair vendor's total as your bill.
- Names starting with a quote or a number are found by their initials ("mp" finds "Mr. Pinchy").
- Questions about quest rewards no longer pause on every letter of a long word.

## 0.57.0

**Upgrades you can trust**
- **upgrades** weighs only what your class or role uses: gear whose stats are all ones you don't want (Intellect and Spell Power for a warrior) is never an upgrade, however high its item level, nor for an empty slot.
- Spells' hit and crit and feral attack power count only for those who use them.
- A plain weapon with nothing but damage is still judged by item level for a healer, but never over one with stats a healer wants.
- When an upgrade is judged by item level, its tooltip says so.

**NPCs, nearest first**
- Every list of NPCs is sorted nearest first unless you pick another sort: trainers, merchants, reagent vendors. An NPC named what you typed stays on top.
- An NPC's role said alone lists the nearest: **inn**, **bank**, **repair**, **weapon master**, **merchant**; **skinner**, **miner** or **herbalist** gives the nearest trainer of it.
- **nearest** mistyped (**nearset**, **neareset**) still means nearest.

**Finding things**
- Simple mode's categories come in a better order. NPCs whose title has your word (**reagent**: the reagent vendors) go near the top, a category with more matches above one with fewer, and the category you picked for those words before goes higher each time. **.forget** clears those picks.
- When plain words find nothing, Terminal offers what you may have meant: a spelling put right, a phrase it understands, or the category a word names. **.missed** lists the searches that found nothing, to try again.
- Every class's spells (**travel form**, **druid spells**, **upcoming spells**) and the weapon masters (**dagger trainer**) come straight from What's Training's catalog, as up to date as it is.

**Your auctions**
- **@auction** lists your sales of the last 30 days (**auctions sold**): the price, the buyer and what you got, from the auction house's news, the Auctions tab or the sale's mail.
- Auctions posted one after another each keep their own price, and one kept without a price takes the Auctions tab's.

**Attune's new look**
- Enter opens Attune on the right attunement (its Archived group too) and points at it in the list or the icon view, or at a step, scrolling the chart to it.
- Steps are lettered as its chart draws them, a split's branches each their own letter; side quests are named by its "Inside the dungeon" box.
- Its short names (**ubrs**, **dal key**) find attunements.

**Also**
- The bar's button says **Group**, and the F, S and G of Filter, Sort and Group are underlined: Alt+F, Alt+S and Alt+G open them.
- Grouped results say how many groups and results they hold: "14 groups · 34 results".
- In combat only **Ctrl+\`** opens Terminal: a \` hit by accident in a fight says so in chat instead of taking your next keys. Tab+\` and `/term` open it as before; / never opens it in combat.
- **Alt+\`** only switches what you typed between plain words and Advanced syntax; it no longer opens or closes Terminal.
- The **/** key can open Terminal on a slash command, the "/" already typed: turn it on with `.set slashKey on`, or in Options (out of combat; in combat / opens the chat box as before).
- A result's menu says **Whisper to target** with your target's full name, and the whisper reaches them.
- Battle.net friends show the name the Friends window shows.
- **.credits**: a thank-you to the people who kept Terminal going.
- Fixes from a review: the send button's menu with a player targeted, a sale told twice kept once, refused auction posts, a commodity's sale, and more.

## 0.56.0

**The bar**
- In plain words, a bar under the prompt narrows, sorts and groups what's found. **Filter** offers what fits the results shown: quality, usable, upgrades, bind on equip, known, ready, complete, not on your action bars, quests to drop, needs repair, unread mail, sold auctions, holidays and more; several add up. **Sort** goes nearest first, or by name, level, item level, quality, value or count. **Group** gives a row per zone, quality, type, slot, dungeon, raid, boss or level, with how many in each; Enter on one lists its rows, and Shift+Left brings the groups back.
- **Alt+F**, **Alt+S** and **Alt+G** open the menus from the keyboard: Up and Down move, Enter or Space picks, Left and Right go to the next menu, Esc closes.
- The **speaker button** on the right sends every result at once (All 8 to party, raid, guild, say…) or copies them all as text or CSV. One result is sent or copied from its right-click menu.
- What your words already ask shows on the bar: **rare sword** shows Filter: Rare, **nearest innkeeper** Sort: Nearest first. Untick it and the word leaves the line.

**Your words stay your words**
- Advanced syntax typed in plain words (`@npc`, `q:rare+`, `sort:name`, `>> party`, `| group by zone`) works right there: nothing is rewritten, so Shift+Left and the categories keep working. The `@` and `key:` pick lists and completion work there too.
- **Alt+\`** writes what you typed as Advanced syntax, finding exactly the same results. **Alt+\`** again, or **Shift+Left**, brings back your words, their category and the bar's picks.

**Questions take the bar too**
- **my auctions**, **my spells**, **what killed me**, **where should i level**…: the bar's Filter and Sort apply to their answers, and Advanced filters and sorts can follow them: `my auctions q:rare+ sort:value`.
- Alt+\` writes what a question asks so it finds the same: `@auction is:sold`, `@calendar is:guild`, `@drop is:mine`, `@drop looter:bob`, `@combatlog is:mine is:taken sort:damage`. A question no search can answer the same way (where to level, your corpse, quest upgrades, talents by what they do) is kept as you said it: questions work in Advanced syntax too.

**Attunement steps, outlined**
- **steps for blackfathom deeps** numbers each step as Attune lays it out: 1, then 2a, 2b, 2c side by side, then 3a, 3b, 3c. Each letter is one line of quests, done one after the other. Side quests say no quest leads up to them. Sort **Line by line** (`sort:line`) lists each line in turn instead.

**Also**
- Advanced mode sorts: `sort:name`, `sort:level`, `sort:ilvl`, `sort:quality`, `sort:value`, `sort:count`, `sort:damage`.
- Items (your bags) and Bank & alts are two categories again.
- The categories are now one search that narrows as you type, with the same scoring, close spellings and everyday words as any other: quicker on big lists, and the same results whichever way you ask.
- Many fixes from a review of the new search: the bar's picks never carry over to another search, quoted phrases and places of several words survive Alt+\`, unknown recipes are found in plain words, and more.

## 0.55.0

**One mode**
- Terminal starts in plain words, and Advanced syntax (`@npc`, `q:rare`, `>> party`) works as soon as you type it, for that line. Typed after plain words, it writes them in Advanced syntax too: **nearest innkeeper**, then ` >>`, becomes `@npc is:innkeeper faction:friendly sort:nearest >>`. `.simple` and `.advanced` are gone; `.help advanced` lists the syntax.
- Alt+\` writes what you typed as Advanced syntax; with Terminal closed it opens it as \` does. Up goes through every line you ran.

**Spells of every class**
- `@spell` lists your spellbook and every class's spells you don't know yet, with the level each rank is learned at: **travel form**, **healing wave**, **druid spells**, **shaman spells at level 20**, **upcoming spells**, **when do i learn travel form**. `class:druid` narrows to a class, `is:known` (or **my spells**) keeps to your spellbook. Enter opens a spell's Wowhead page.
- **spellid claw** lists every rank's spell ID, ready to copy; **spellid 1082** shows the spell. Spell, talent and training tooltips show the ID.
- Weapon masters by weapon (**dagger trainer**, **where do i learn daggers**) without What's Training too.

**Talents by what they do**
- **healing talents**, **shaman crit talents**, **druid regen talents**, **tank talents**: the talents whose name, tree or description says it ("crit" finds "critical", "healing" finds "healed"), any class's, yours first. **druid talents** lists a class's tree by tree.
- Druid talents are found from every class: they were never read before.

**Upgrades for your roles**
- `.weights` shows how upgrades are judged for your class and picks the roles to judge them for: `.weights feral healer` counts an upgrade for either, and the tooltip says which.

**Also**
- Tooltips say what Enter and Shift+Enter do on a line each, the same way everywhere, with the keys named Enter and Shift+Enter in every language.

## 0.54.0

**With What's Training**
- `@training`, or ask in plain words: **what can i train**, **what do i learn next level**, **spells at level 30**, **weapon skills to learn**, **how much is training**, **when do i learn polymorph**. Every spell, rank, weapon skill and pet ability your class has still to learn, with when you can learn it, what it costs and where it's taught.
- Enter opens What's Training's window on the spell and points at it. Shift+Enter lists who teaches it, the nearest first; Enter on one of them shows them on the map.
- **where to learn fireball**: your class trainers, nearest first (pet trainers for a pet ability), the weapon masters for a weapon skill, the quest for a quest's spell, or where to get the book.
- Advanced mode: `@training is:learnable`, `is:nextlevel`, `is:later`, `is:weapon`, `is:pet`, `lvl:30`, and `@training is:learnable | sum cost` for what it all costs.
- `.tour` has a step for it, and the footer says to install it (or update it) when you reach for it without.

**Weapon masters**
- **dagger trainer**, **where do i learn daggers**, **who trains staves**: the weapon masters who teach it, the nearest first and then those on the other continent, even for a weapon skill you already know. Advanced mode: `@npc trainer:daggers`. Without What's Training, every weapon master.

**Tabs**
- Ctrl+T opens a tab, Ctrl+1-4 or Ctrl+Tab switch between them, Ctrl+Shift+W closes one. Each keeps its own search and mode, the one shown keeps itself up to date, and a dot marks one whose lists changed.

**Summing up and filters**
- Summed searches group **by dungeon**, **by raid** or **by instance** as they say (no battlegrounds, professions or world bosses), and leave out what has none of it.
- Filters take quoted values: `q:"Rare"`, `in:"Elwynn Forest"`. Enter on a summed-up group writes the filter you'd type.

**Also**
- `@dungeon` and `@raid` list Blackrock Mountain's instances once, at the nearer door.
- `.zen`'s faded interface takes no clicks or hovers; a click on it closes the terminal.
- Faster: narrowing a search is up to twice as fast, and opening and closing the terminal costs less.
- Fixes from a review: tabs keep their own search through chat links and the tour; `stat:mp5` and `stat:healing` no longer match health regen, and ranged attack power is its own stat; characters who share a first name are told apart; chat lines read right in other languages; and many smaller fixes.

## 0.53.0

**Suggestions for where you are**
- The empty prompt's "try:" suggestions fit where you are: in a city, trainers, the mailbox, the auction house and your mail come first; out in the world, quests, dungeons and upgrades; in a dungeon, your group and its loot. The others still come up, later.
- Suggestions for an addon you don't have (Questie's NPCs, AtlasLoot's loot, Attune) aren't made, and there are more of them.

**Upgrades, compared as the game does**
- An upgrade's tooltip shows the game's own comparison with what you wear there ("+5 Strength", "-4 Agility"), right in Terminal's tooltip; for a quest, its reward. An item the game hasn't loaded yet is compared once it has.
- "upgrades" lists clear upgrades only: little given up for what's gained, and never a piece you already wear.
- F5's new results are offered only once they're sure, so F5 no longer comes and goes while item data comes in after a /reload.

**Copy results out**
- `>> text` and `>> csv` copy the selected result instead of sending it to chat; `>>> text` and `>>> csv` copy every result (CSV: name, detail, kind, id). A box opens with it; Ctrl+C copies it and the box closes.
- In Simple mode, say it in words: "linen to csv", "linen as text".

**Search in quotes**
- Words in quotes are found together, as they are: `"outlaw saber"` finds the Outlaw Saber, not every name with both words in it. Filters too: `in:"elwynn forest"`, `-"outlaw saber"`.

**Summing up (Advanced mode)**
- A `|` standing alone sums up what a search found, every match and not only the first 100: `in:bags | sum value` (what it all sells for at a vendor), `@quest | group by zone`, `@item | count by quality`, `in:bags | sum value by quality`, `| avg ilvl by slot`.
- Enter on a group lists its rows (`@quest | zone:"Elwynn Forest"`); Shift+Left goes back.

**Also**
- Closed with the toggle key or a click elsewhere and opened again within 5 seconds, the terminal has your text back, in the mode it was in. Esc closes it and clears the text.
- `.atop`: Left/Right switch the CPU % between each addon's share of all addons and its share of a frame.
- A smaller download: only what the game runs.
- Fixes: rings, trinkets and two weapons are judged against each piece you wear; a list that changes several times while you look at it keeps up; Enter on a summed-up total says it in chat; and smaller fixes from a review before release.

## 0.52.0

**Upgrades, the best first**
- "upgrades" (Advanced mode: `@loot is:upgrade sort:best`) lists gear you can actually get that beats what you wear: about your level, from dungeons you can enter, never raid, profession, PvP or event loot, nor what's bound to one of your alts.
- The biggest upgrades come first, and each one's tooltip says why: what it's weighed against, then a line per stat, gains in green and losses in red. Dual wielding, rings and trinkets: against each piece it beats, by name.
- The list is the same each time you ask, and what Terminal learns of items is kept between sessions, so after a /reload upgrades and item colours are right from the first search.

**Quest upgrades (with Questie)**
- "quest upgrades" (or "quests with upgrades") lists the quests near your level you can still take whose reward is an upgrade for you, the biggest first, with what each rewards and how far its giver is, the arrow pointing the way (Advanced mode: `@questie is:upgrade sort:best`).

**Lists that stay put**
- When a list changes while you look at it (your bags as you loot, the loot log, mail, item data coming in), it no longer shifts under the cursor: the new list waits for F5, and the footer says so.
- A row whose count changed (one more cloth in a stack) updates in place; a list that showed nothing takes the new rows at once.

**.tour**
- `.tour` shows Terminal in a few short steps: a card says what each step shows, the search is typed for you and the result it's about is highlighted. Enter goes on, Shift+Left goes back, Esc ends it.
- It finds something from your bags and one of the game's settings, says what to do with a kind of thing you have ("use stamina food", "equip shield"), and shows what Questie, AtlasLoot and Attune add, or what installing them would.
- On a fresh install, the empty prompt suggests it first.

**Also**
- An NPC inside a dungeon says which one on its row, and its distance, arrow and map pin point at the dungeon's entrance.
- `.zen`'s dimming is adjustable: Options > Zen dimming (or `.set zenDim 0.4`).
- `@xp` also lists the alts your bag addon knows of that Terminal hasn't seen yet, saying to log in on each once.
- Fixes: items in a list no longer show white until you scroll past them; a Simple mode category lists everything its row counted; a command's choices of more than one word are picked whole; the Options panel fits its frame; Terminal Extras has its own icon in the AddOn list; and many smaller fixes from a review before release.

## 0.51.0

**Your corpse and the nearest spirit healers**
- After a death, "where is my body" (or "my corpse", "corpse run", "where did i die"; Advanced mode: `@corpse`) shows where your body lies, how far and which way, with an arrow that turns with you, and the nearest spirit healers under it.
- Enter opens the map on it with a pin; Shift+Enter only sets the pin. Inside an instance the game doesn't say where your corpse is, and the row says so.
- With Questie, spirit healers are NPCs like innkeepers: "nearest spirit healer", "nearest graveyard" (Advanced mode: `@npc is:spirithealer`).

**Your gear's wear and the repair bill**
- "durability", "repair cost", "what needs repair" or "broken gear" (Advanced mode: `@durability`, `.durability`) lists every piece that wears down, lowest first, and the damaged ones in your bags, each with its durability and what repairing it costs, the whole bill on top.
- The cost is the game's own, less the reputation discount the last repair vendor gave you; at a vendor, its own total.
- Enter shows the piece on your character or in your bags; Shift+Enter finds the nearest repair vendor. Advanced mode: `is:damaged`, `is:broken`, `dura:<50`.

**Other addons' settings**
- Type what a setting is called ("questie map icons", "attune announce") to find it in any addon that uses Ace3's options (Advanced mode: `@addonoption`; Simple mode: under Settings).
- Enter opens that addon's options on it and points at it; Shift+Enter turns an on/off setting on or off. `.integrations` lists the addons found.

**With Attune**
- "my attunements", "raid attunements", "my keys", "class quests", "attunements to do" or "am i attuned to mc" (Advanced mode: `@attune`) lists your attunements, dungeon quest lines, keys and class quests, each with how far along you are, your next step and your alts' progress.
- "how do i get into molten core" or "steps for the deadmines" (Advanced mode: `<attunement> > steps`) lists the steps first to last; `<quest> > attunement` names the attunements a quest is part of.
- Enter opens Attune on it and points at it; Shift+Enter puts it in the chat box.

**Your own commands**
- `.alias rep durability` makes `.rep` run that search. An alias can be any search or question, a `/slash` command (pressed by the game) or another `.command`.
- Words typed after it are added at the end (`.rep legs`), or go where `$*` stands (`.alias wh /w $* hi`). `.alias` lists yours, `.unalias <name>` forgets one; they're kept for every character.

**Also**
- Reaching for Questie, AtlasLoot, Attune or your alts' bags without the addon for it adds a short line under the footer: "Install Attune for this." (Syndicator or BagBrother for your alts' bags).
- Alt+click a link in chat to look it up in Terminal; Ctrl+click is the game's dressing room alone again.
- `in:warband` is no longer offered: WoW Forever has no warband bank.
- A review of the whole addon:
  - "who needs blessing of kings" lists everyone missing Kings, not only those with no Blessing.
  - `in:bags` finds what's in your own bags; "summon voidwalker" finds the spell.
  - "old blanchy quest" and the like are searches again, not quests to drop.
  - "spells not on my bars" reads the macros on your bars right; `is:upgrade` no longer calls every one-hander an upgrade for a class that can't dual-wield.
  - `reward:` finds names with an apostrophe, and waits for its list after login.
  - A sum like `3*45g` shows just its answer.
  - The row menu's Send on a ">>> party" row sends, and your last search comes back with Down after a window closed Terminal.
  - A returned auction is matched to the one that ran out, and mount favourites update.
  - The map, the AddOn list and the options are never opened from Terminal's own code.
  - "nearest" searches, place names and your alts' items do less work while you type or play.

## 0.50.0

**The calendar**
- "holidays", "what's on this week", "today", "next darkmoon faire", "my invites" or "guild events" (Advanced mode: `@calendar`) lists what's on from today to the end of next month: holidays such as the Darkmoon Faire, your, your guild's and your communities' events with your answer, invitations you haven't answered yet, and raid resets.
- Each says when it starts and ends, to the minute, as the calendar's own tooltip does: the Stranglethorn Fishing Extravaganza's 2 to 4 PM, when the Darkmoon Faire closes.
- Enter opens the calendar on the event; Shift+Enter puts it in the chat box (your and your guild's events as the game's link).
- Advanced mode: `is:holiday`, `is:invite`, `is:today`, `when:week` (also today, tomorrow, weekend, nextweek, month, nextmonth).

**Quests by their reward, and the quests before one**
- "outlaw sabre quest", "quest for outlaw sabre" or "which quest rewards the outlaw sabre" lists the quest whose reward it is, the one your faction can take. A close spelling counts ("outlaw saber"). Advanced mode: `@questie reward:outlaw_sabre`.
- "quest chain for the missing diplomat" (Advanced mode: `<quest> > chain`) lists the quests that lead up to it, first to last, each with its step; where the chain branches, the one your race and class can take. "quest chain for outlaw sabre" is the chain of the quest rewarding it.

**Trainers by what they teach**
- "enchanting trainer", "blacksmithing trainer", "mage trainer" or "hunter pet trainer" lists the nearest ones, no "nearest" needed. They're found by what they teach, so the Journeyman Enchanter, the Herbalists and the Master Mages are in ("enchanting" used to find nothing while "enchant" did).
- "demon trainer" or "warlock pet trainer" finds the warlocks' Demon Trainers; "pet trainer" alone is your class's.
- A place said keeps to it ("mining trainer in org", "trainer in mage quarter"), and two professions at once list either's trainers.

**Recipes to learn**
- "recipes to learn" keeps to the ones your skill allows now (it listed hundreds beyond it), and the footer says how many more need more skill. "recipes in my skill range" does the same; "all recipes to learn" or "recipes i'm missing" lists every one.

**Also**
- Opening a profession window no longer says "Indexed Blacksmithing: 120 known recipes" in chat; it's still indexed, and debug mode (`.debug`) says it.
- Enter does what the footer says after a Shift+Enter or a click set it up.
- A window opened while lists are still loading closes Terminal and is pointed at.
- AltGr letters type (Polish, Czech and Hungarian keyboard layouts), and a key you bound to Terminal closes it too.
- F1, `.changelog` and `.atop` catch the mouse, and close when Terminal opens.
- Searches:
  - "not" and "-" work with any language's letters.
  - "cloak without stamina", "reset my keybinds", "where is the ah" and "how do i get to orgrimmar" are searches again, not other questions.
  - "what does my group need" asks the group, and "leveling plan" plans all your professions.
  - `sqrt(2)`, `max(3, 5)` and the like add up.
  - Items "of the Monkey" and "of the Bear" each keep their own stats.
- Worn bows, wands and relics, and keys on the keyring, are found.
- "what killed me" answers with this character's deaths only.
- A new sale's news stays until its own mail comes.
- `@mail`, `@drop` and `@combatlog` say why when they're empty.
- Camp objects and talents open right when their window is already up.
- Questie's NPCs open and get pinned at the spawn the row measures, and your waypoint stays where a place can't take one.
- Quick Keybind Mode starts from the Keybindings page's own button.
- Translations reach the release even before CurseForge's translators have done them (0.49.0 shipped some new texts in English only).

## 0.49.0

**Raid lockouts**
- "my lockouts", "raid lockouts" or "am i saved" (Advanced mode: `@lockout`) lists what each of your characters is saved to: raids, dungeons and world bosses, how many bosses are down and when each resets. Your alts show up once you've logged in on them with Terminal.
- Enter puts a lockout in your chat window, with its bosses; Shift+Enter puts your own in the chat box as the game's lockout link (an alt's in words).
- Advanced mode: `is:raid`, `is:dungeon`; `.lockouts forget <name>` drops an alt from the list.

**Your auctions**
- "my auctions" or "what am i selling" (Advanced mode: `@auction`) lists what each of your characters has on the auction house, as Terminal saw it posted or on your Auctions tab, with its price and time left.
- Then the auction house's news: sold, won, outbid and expired, each item with its own icon, quality and count. The news moved here from `@mail`; "incoming mail" still shows it.
- An auction that comes back to you by mail (it failed, expired or was cancelled) no longer counts in your stored items as still on the auction house.

**Profession levelling plans**
- "blacksmithing plan" or "level blacksmithing" (Advanced mode: `@recipe blacksmithing sort:plan`) lists your recipes that still give skill, by how many times your materials make each: your bags and bank, and your alts'. Materials a vendor sells don't count.
- The footer says about how many skill points your materials would give.
- Recipes the profession window shows grey are left out, even where AtlasLoot's levels say otherwise.

**Simple mode's categories, named for what you'd do**
- Items (your bags, bank and alts together), Windows, Settings (options, keybindings, console settings, addons and Terminal's own), Commands (slash commands and macros), Emotes, Dungeon loot and Recent (your drops and deaths). Mail is under Character.
- Each category says which lists it found something in, and a result named exactly what you typed comes first, ready to open.

**Also**
- Mail carrying an item is drawn in that item's colour, with its icon.
- The Legacy window: "Legacy Challenges" opens it on its Challenges page; "Legacy Rewards" (new) and "Legacy Tree" open it and point at their tab, also when it's already open on another page. The game gives addons no way to switch to those two tabs themselves.
- Up on an empty prompt brings back a line you ran; Down then goes into its results like any search, Up from the top result goes further back, and Shift+Left steps back toward the empty prompt.
- `.zen` hides the frame-rate counter too, and brings it back as Terminal closes.
- Terminal is listed on CurseForge for WoW Forever only (0.48.0 also showed up for retail).
- Quicker searches once you've picked things before; your alts' items are counted again in the background rather than as you type.
- `.debug reset` lets Terminal try again what the game once blocked.
- Fixes:
  - Currencies under a folded header are listed.
  - A profession window's search or filters no longer shrink the recipes Terminal keeps for it.
  - Load-on-demand addons say so in `@addon` instead of asking for a reload.
  - "nearest mailbox" works right after login.
  - Clicks and the right-click menu do what Enter does; `>> party` sends from the click, not on hover.
  - A fight that closes the keys window (F1) brings your search back afterwards.
  - F1's pure fuzzy finding tab says what right-click offers there: take the result to Simple or Advanced mode, or link it or send it to chat.
  - Row details and the games' and windows' key hints read the same way everywhere.

## 0.48.0

**Terminal speaks your language**
- Terminal follows your game's language: English, German, French, Spanish, Russian or Chinese (simplified). Every chat line, row, tooltip and window is translated.
- In those languages Simple mode also understands the game's own words: qualities, slots, weapon and armour kinds, group and NPC roles, standings, classes and professions ("selten", "Rücken", "Heiler", "Krieger"), and English words like "sword" or "back" now work in any language too.
- The main questions work in your words: "nearest ...", "mats for ...", "what uses ...", "where to get ...", "where to learn ...", "where is ..." ("nächster Gastwirt", "Mats für ..."). English always works.
- The translations are new and come from the community through CurseForge: open the Localization tab on Terminal's CurseForge page to correct or add one.

**Party quests**
- "party quests" (Advanced mode: `@group quests`) lists each quest in your log with who in your party is on it too: "Ann too", "the whole party", "share with Bob".
- Enter shares a quest with the party; "quests to share" lists the ones someone lacks; "quests in common" the ones you're on together.
- `>>> party` (or right-click and pick "All to party") says it in one line: "On the same quests: Wolves Across the Border (Ann), The Fargodeep Mine. I can share: Wolves Across the Border, Princess Must Die!"
- Where the game doesn't say who's on what, Terminal learns it from sharing ("is already on that quest", "has accepted your quest").

**Mail on its way**
- Mail you send to anyone, not just your alts, shows in `@mail` for the hour it takes to arrive ("sent mail"), even when the game takes a minute or two to send it.
- The auction house's news shows before you reach a mailbox ("incoming mail"): sold (with its price, and when the gold is due), won, outbid and expired.

**Also**
- Typing a filter offers only the values that make sense for the lists you named: `@questlog is:` offers complete, grey, leftbehind and drop, not online or equippable.
- Terminal's games and radio are an addon of their own, **Terminal Extras** (in its own folder, it comes with Terminal), loaded the first time you use one, so Terminal alone takes less memory. Keep it switched on in your AddOn list to play.

## 0.47.0

**Your group**
- `@group` (Simple mode: "who is dead", "who needs fortitude", "who is out of range", "group healers", "missing buffs") lists your party or raid: each member's role, whether they're dead, offline or out of range, and the group's buffs they're missing (only those someone in the group can cast).
- Enter targets a member; Shift+Enter casts your buff they lack on them.
- `@group >>> party` (or right-click a member and pick "All to party") says what's missing in one short line: "Missing buffs: Fortitude (Cid), Blessing (all but Ann)". "missing consumables" finds who has no food or flask/elixir.
- In boss fights, keystones and PvP matches the game hides range and buffs from addons; Terminal says so instead of guessing.

**Your mail**
- `@mail` (Simple mode: "my mail", "mail running out", "cod mail", "mail from bob") lists what's in every character's mailbox as Terminal last saw it: who sent it, its gold and COD, what's attached, and when it runs out (deleted, or sent back). Open a mailbox once on each character; no bag addon needed.
- Mail you send to one of your own characters is in its list at once.
- At login a chat line tells you when gold or items in your mail run out within 3 days (`.mail warn off` stops it).

**Enter goes all the way again, safely**
- A spell turns your spellbook to its tab and page; a quest opens its details in the quest log; a keybinding scrolls Options > Keybindings to its section and unfolds it. Then Terminal points at it.
- The game makes those clicks itself, in the same Enter press, so nothing Terminal opens is left tainted. Terminal checks afterwards; if a window ever comes out tainted anyway, it only opens and points there from then on. `.nav` shows which windows it turns, `.nav reset` tries again.
- The map, the options pages, the Legacy and Group Finder tabs and the collections journal are opened by the game's own calls and clicks too, never by Blizzard code run from Terminal, so they no longer fail later in a fight ("action blocked").
- Dropping one quest (Shift+Enter, or `>> drop`) asks in Terminal's own window, as dropping several does.

**Combat and .zen**
- Combat closes Terminal at once; when the fight is over it opens again where you left off: your search, the row you picked, the mode you were in. Press \` during the fight to have it back sooner.
- `.zen`: while Terminal is open the rest of the interface (the minimap too) fades away and the screen dims behind it; closing Terminal brings it all back smoothly, and combat brings it back at once. Terminal's tooltip, menus and windows stay visible in it, and dragging Terminal still shows its grid.

**For addon authors**
- Other addons can add their own lists to Terminal: rows found by fuzzy search, `@yourword`, Simple mode categories, tooltips, Enter and Shift+Enter actions the game presses safely, and commands. See [docs/PROVIDERS.md](docs/PROVIDERS.md) and the working example in [docs/example/TerminalNotes](docs/example/TerminalNotes).

**Also**
- Spell and talent tooltips (other classes' too) fill in their text as soon as the game has it, also right after a /reload; the rows on screen are loaded ahead.
- Collections: Shift+Enter opens the journal and points at the toy, pet or mount, or at its tab when another one shows.
- The key binding reads "Toggle Terminal".
- `.debug log` names the press of Terminal's behind a blocked action the game blames on a /run line.
- Fixes:
  - Searches like "food buff", "consumables", "mail boots from wailing caverns" or "new mail gloves" are no longer taken for group or mail questions.
  - Shift+Enter on a Questie quest you have opens its details in your log again.
  - The Spellbook row no longer clears the spellbook's search.
  - `@group` no longer fails in a boss fight, when the game hides members' roles and names.
  - Enter on one spell or quest and then another no longer points at the first one later, and a window you close stops being looked at.

## 0.46.0

**Every key in one place**
- Press **F1** in Terminal (or type `.keybinds`) for a small window listing every key, with a tab each for Simple mode, Advanced mode and fuzzy finding. Keys a mode does its own way are highlighted. Esc, F1 or Shift+Left take you back to your search exactly as you left it.
- The keys work alike in every mode:
  - Tab completes what's faint after the cursor (or picks the selected category) and otherwise goes to the next result; Shift+Tab goes to the previous one.
  - Ctrl+Home / Ctrl+End jump to the first / last result.
  - Ctrl+W and Ctrl+Delete delete a word; Ctrl+U deletes everything before the cursor.
  - Right-click in fuzzy finding offers what its Enter and Shift+Enter do.
- **Shift+Left goes back**: after Enter takes you from a list to a recipe's sources (or a chain's next step, a name you picked, Shift+Right's "write it"), Shift+Left returns to the list with your pick still selected, wherever the cursor is. In Simple mode it also takes you from a category back to all of them (Tab now goes down the list there, as everywhere).
- Drag Terminal and it snaps to a grid, with lines showing the screen's middles (the one it sits on lights up); hold Shift to place it freely.
- The game's own keys that don't get in the way still work while Terminal is open: Ctrl+R (frame rate), Ctrl+S (sound), Ctrl+M (music), volume, screenshots, Alt+Enter (windowed).

**Recipes you don't have yet, and where to learn them**
- "blacksmithing recipes i'm missing" lists every recipe of your professions you don't know, each with the skill it needs and how it's learned: a trainer and its cost, a vendor (and whether it's limited supply), a drop or a quest. "recipes i can learn now" keeps those your skill allows. Advanced mode: `@recipe is:unknown`, `@recipe is:learnable`.
- "where to learn thorium belt" (also "who teaches ...") shows the plans that teach it and who sells or drops them, nearest first and only those who'd sell to you, or, when no plans exist, the nearest trainers who can teach it. Advanced mode: `thorium belt > learn`.
- How far each seller, dropper or trainer is shows in a column of its own, with the direction arrow beside it.
- Open each profession's window once, and a trainer's or vendor's window, for Terminal to see what they say; with nothing to list, a line says which window to open.

**More plain-word questions**
- "nearest unlearned flight master" points you to the closest flight path you haven't learned yet; "unlearned flight paths" lists them all. Terminal learns which ones you know from the first flight master's map you open on each continent, per character (until then they say "not checked yet"). Advanced mode: `@flight is:unlearned sort:nearest`.
- "spells not on my bars" lists the spells you can cast that aren't on any action bar you can see or on a key (a macro casting one counts). Advanced mode: `@spell is:unplaced`.
- "quests to drop" lists the quests gone grey for your level and those in zones you've left behind. Shift+Enter drops one (the game asks first); "Drop all", or right-click, drops them together after showing you the list. Advanced mode: `@quest is:drop` (or `is:grey`, `is:leftbehind`), and `>>> drop` drops every quest listed.
- "guild blacksmith", "guild skinner", "guild herbalists": guild members by profession, offline ones too. Advanced mode: `@guild skinner`.

**Tooltips and chat**
- Quests in your log and Questie's show a tooltip with their level, zone, objectives and rewards: the experience at your level, the money and the items (Questie's experience figure, marked as such, where the game gives none).
- Drops sent to chat say who got them, from which boss, where and when: "[Rotmender's Garb] looted by Zd Zd in Razorfen Downs (26 min ago)"; all of them at once say what they share once: "Drops in Razorfen Downs (5): ...".
- Sending everything at once (`>>>` or right-click "All N to ...") needs a search first, so your recent picks never go out by themselves; to say and yell it's one line with them all counted, as the game won't let addons send more there.

**Also**
- Gear works the same wherever you find it: Shift+Enter on a piece of equipment found with `@item`, a plain search or Simple mode's Bags equips it, as `@gear` does; worn gear with a use of its own (a trinket) is used, other worn gear says it's already equipped.
- Fixes:
  - A `>` typed in Simple mode is no longer run as a chain; it says that's Advanced mode's.
  - A function key pressed before typing anything no longer switches Terminal to the plain text box.
  - `.mem` names every list the way you'd search for it (recipes to learn: `@recipe is:unknown`).

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
- Lighter: earned achievements no longer re-read the whole list, and `sells:` looks its sellers up once per search.

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
