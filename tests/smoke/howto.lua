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
	-- the topic its words name, first
	local rows = Ask("how do i send to party")
	check(rows[1] and rows[1].key == "howto:send" and rows[1].example == "hearthstone >> party" and rows[1].kind == "howto",
		"how do i send to party: sending to chat first: " .. Ids(rows))
	check(#rows <= HT.MAX, "at most " .. HT.MAX .. " rows: " .. #rows)
	check(Ask("what does shift enter do")[1].key == "howto:other", "what does shift enter do: a row's other action: " .. Ids(Ask("what does shift enter do")))
	check(Ask("how do i make my own command")[1].key == "howto:alias", "my own command: .alias: " .. Ids(Ask("how do i make my own command")))
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
	local ranked = Q.Ranked and Q.Ranked("how many linen do i have")
	check(ranked and ranked[1] and ranked[1].a.id == "HaveQ", "how many linen do i have: still the item count's: " .. tostring(ranked and ranked[1] and ranked[1].a.id))
	-- Enter: the example in the prompt, searched; Shift+Left comes back
	UI:Open("how do i send to party"); FlushAll()
	local first = UI.Results()[1]
	check(first and first.key == "howto:send", "searched: the how-to rows: " .. tostring(first and first.name))
	UI:Activate(1, {}); FlushAll()
	check(UI:IsShown() and UI.edit:GetText() == "hearthstone >> party", "Enter: its example written: " .. UI.edit:GetText())
	UI:HideNow(); FlushAll()
	ns.db.easyMode = easy; UI:EasyChanged()
end
