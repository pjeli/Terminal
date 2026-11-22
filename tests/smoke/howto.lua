-- "How do I..." answers (1.7.6, the player's pick from the suggestions): Terminal's own help as rows, Enter writes the
-- example into the prompt. Search/Questions/HowTo.lua.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local HT, Q = ns.HowTo, ns.Questions

io.write("[howto: how do i ... as rows]\n")
do
	local easy = ns.db.easyMode
	ns.db.easyMode = true; UI:EasyChanged()
	local function Ids(rows)
		local t = {}
		for i, e in ipairs(rows or {}) do t[i] = tostring(e.key):gsub("^howto:", "") end
		return table.concat(t, ",")
	end
	local function Ask(text)
		local rows = Q.Answer(text)
		return rows or {}
	end
	-- the topic its words name, first; in Simple mode said without Advanced syntax (release review)
	local rows = Ask("how do i send to party")
	check(rows[1] and rows[1].key == "howto:send" and rows[1].kind == "howto" and not rows[1].example
		and not rows[1].how:find(">>", 1, true), "how do i send to party: sending to chat first, Simple's way: " .. Ids(rows) .. " / " .. tostring(rows[1] and rows[1].how))
	local f = Ask("how do i filter by quality")[1]
	check(f and f.key == "howto:filters" and not f.how:find("q:rare", 1, true) and f.example == "rare swords under level 30",
		"filters in Simple mode: said, not q:rare+: " .. tostring(f and f.how))
	ns.db.easyMode = false; UI:EasyChanged()
	rows = Ask("how do i send to party")
	check(rows[1] and rows[1].example == "hearthstone >> party" and Ask("how do i filter by quality")[1].how:find("q:rare+", 1, true),
		"Advanced: >> party, q:rare+")
	ns.db.easyMode = true; UI:EasyChanged()
	check(#rows <= HT.MAX, "at most " .. HT.MAX .. " rows: " .. #rows)
	check(Ask("what does shift enter do")[1].key == "howto:other", "what does shift enter do: a row's other action: " .. Ids(Ask("what does shift enter do")))
	check(Ask("how do i make my own command")[1].key == "howto:alias", "my own command: .alias: " .. Ids(Ask("how do i make my own command")))
	-- (release review) examples that change nothing on a second Enter: the commands' own help
	check(Ask("how do i make my own command")[1].example == ".alias" and Ask("how do i change the key that opens it")[1].example == ".bind",
		".alias and .bind alone: " .. tostring(Ask("how do i change the key that opens it")[1].example))
	check(Ask("how can i change the theme")[1].key == "howto:look", "the theme: how it looks")
	check(Ask("how to find upgrades")[1].key == "howto:upgrades", "how to find upgrades")
	-- a topic with keys to press, no example: shown, nothing to write
	local hist = Ask("how do i repeat what i ran before")
	check(hist[1] and hist[1].key == "howto:history" and hist[1].noActivate and not hist[1].example, "history: keys to press, no example: " .. Ids(hist))
	-- other questions keep their lines; a how-to about nothing it knows is searched as words
	check(HT.Question("how do i bake bread") == nil, "no topic fits: not a how-to answer")
	check(HT.Question("nearest innkeeper") == nil and HT.Question("send to party") == nil, "no how-to cue: not one")
	check(HT.Question("what does innkeeper farley sell") == nil and HT.Question("what does old chain one unlock") == nil
		and HT.Question("where do i turn in the defias brotherhood") == nil, "what does ___ sell / unlock, where do i: other questions'")
	-- (release review) every word must fit a topic: other questions' lines, spells' and items' names stay theirs
	for _, line in ipairs({ "how do i get the scarlet key", "how do i get the key to scholomance", "how do i get a bigger bag",
		"how to get rare items", "how do i get a group for deadmines", "how do i share quests",
		"what does power word fortitude do", "what does fade do", "what does the ring of the keeper do" }) do
		check(HT.Question(line) == nil, "not a how-to: " .. line)
	end
	local share = Q.Ranked and Q.Ranked("how do i share quests")
	check(share and share[1] and share[1].a.id ~= "HowTo", "how do i share quests: not HowTo's: " .. tostring(share and share[1] and share[1].a.id))
	check(Ask("what does .zen do")[1].key == "howto:zen" and Ask("how do i turn off zen")[1].key == "howto:zen",
		"what does .zen do, how do i turn off zen: zen first: " .. Ids(Ask("how do i turn off zen")))
	check(Ask("what does ctrl r do")[1] ~= nil, "what does ctrl r do: the keys")
	local ranked = Q.Ranked and Q.Ranked("how many linen do i have")
	check(ranked and ranked[1] and ranked[1].a.id == "HaveQ", "how many linen do i have: still the item count's: " .. tostring(ranked and ranked[1] and ranked[1].a.id))
	-- Enter: the example in the prompt, searched; Shift+Left comes back
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("how do i send to party"); FlushAll()
	local first = UI.Results()[1]
	check(first and first.key == "howto:send", "searched: the how-to rows: " .. tostring(first and first.name))
	UI:Activate(1, {}); FlushAll()
	check(UI:IsShown() and UI.edit:GetText() == "hearthstone >> party", "Enter: its example written: " .. UI.edit:GetText())
	UI:HideNow(); FlushAll()
	ns.db.easyMode = easy; UI:EasyChanged()
end
