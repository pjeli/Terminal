-- "Did you mean...?" (0.56.2, the player's ask): a plain-words search that finds nothing offers the closest phrases
-- Terminal understands, or the category a word names; .missed keeps the searches that found nothing (Search/DidYouMean.lua).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L, DYM = ns.L, ns.DidYouMean

local function Rows()
	local t = {}
	for _, e in ipairs(UI.Results()) do t[#t + 1] = tostring(e.name) .. "/" .. tostring(e.kind) end
	return table.concat(t, " | ")
end

io.write("[didyoumean: suggestions when nothing is found, .missed]\n")
do
	local save = { easy = ns.db.easyMode, missed = ns.db.missed }
	ns.db.missed = nil
	check(DYM.Distance("inkeeper", "innkeeper", 2) == 1 and DYM.Distance("hearhtstone", "hearthstone", 2) == 1
		and DYM.Distance("abc", "xyz", 1) == 2, "the edit distance (a letter added, two swapped; past the cap: cap + 1)")
	check(DYM.Close("innkeepers", "innkeeper") and DYM.Close("durabilty", "durability") and not DYM.Close("dont", "done")
		and not DYM.Close("mail", "main"), "close words: plurals and a letter or two off; short words exactly")
	ns.db.easyMode = true; UI:EasyChanged()

	-- a misspelt word Terminal knows: the line put right, selected for Enter
	UI:Open("durabilty"); FlushAll()
	local res = UI.Results()
	check(res[1] and res[1].noActivate and res[2] and res[2].kind == "suggestion" and res[2].name == "durability",
		"durabilty: nothing, and durability offered: " .. Rows())
	check(UI.sel == 2, "the suggestion is selected (Enter takes it): " .. tostring(UI.sel))
	-- taken: searched, kept by .missed (what was typed and what was taken); Shift+Left back to what was typed
	res[2].activate(res[2]); FlushAll()
	check(UI.edit:GetText() == "durability", "Enter: its search: " .. UI.edit:GetText())
	local m = ns.db.missed and ns.db.missed[1]
	check(m and m.t == "durabilty" and m.took == "durability" and m.n == 1, ".missed keeps it and what was taken: " .. tostring(m and m.t))
	UI:WalkBack(); FlushAll()
	check(UI.edit:GetText() == "durabilty", "Shift+Left: back to what was typed: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	check(#ns.db.missed == 1 and ns.db.missed[1].n == 2, "closed on it again: counted, not kept twice: " .. #ns.db.missed)

	-- a phrase it's like, by the words they share
	UI:Open("flight paths i dont have"); FlushAll()
	check(Rows():find("unlearned flight paths/suggestion", 1, true) and not Rows():find("done", 1, true),
		"flight paths i dont have: unlearned flight paths (and \"dont\" left as it is): " .. Rows())
	-- a word every phrase has isn't enough
	UI:SetQuery("my atunements"); FlushAll()
	check(not Rows():find("my mail", 1, true), "my atunements: not my mail: " .. Rows())
	-- a category's name searched as a word: that category, with the rest (only one that has it)
	UI:SetQuery("commands reload"); FlushAll()
	local look
	for _, e in ipairs(UI.Results()) do if e.catId then look = e end end
	check(look and look.name == L["Look in %s: %s"]:format(L["Commands"], "reload"), "commands reload: look in Commands: " .. Rows())
	look.activate(look); FlushAll()
	check(UI.edit:GetText() == "reload" and UI.category == "commands", "Enter: reload, in Commands: " .. UI.edit:GetText() .. " " .. tostring(UI.category))
	UI:SetQuery("settings qwzx"); FlushAll()
	for _, e in ipairs(UI.Results()) do check(not e.catId, "settings qwzx: no Look in Settings (nothing there)") end
	-- nothing near: the note alone; closed on it: kept
	UI:SetQuery("qwzx"); FlushAll()
	check(#UI.Results() == 1, "qwzx: the note alone: " .. Rows())
	UI:Hide(); FlushAll()
	check(ns.db.missed[1].t == "qwzx" and ns.db.missed[1].n == 1, "closed on nothing found: kept, the newest first")

	-- Advanced mode: no suggestions (its words are its syntax)
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("durabilty"); FlushAll()
	for _, e in ipairs(UI.Results()) do check(e.kind ~= "suggestion", "Advanced mode: no suggestions") end
	UI:Hide(); FlushAll()

	-- .missed: the list, each with how often; one tried again; clear
	local c = ns.commands.missed
	local list = c.complete("")
	check(list[1][1] == "qwzx" and list[3][1] == "durabilty" and tostring(list[3][2]):find(L["%d times"]:format(2), 1, true)
		and tostring(list[3][2]):find("durability", 1, true) and list[#list][1] == "clear", ".missed lists them: " .. tostring(list[3][2]))
	-- (0.56.4, the player: Enter on ".missed" printed and stayed open) Enter: the list in the chat window, Terminal closed;
	-- a search picked from its list: Terminal stays open on it
	local said = {}
	local outWas = ns.Output
	ns.Output = function(_, l) said[#said + 1] = l end
	UI:Open(".missed"); FlushAll()
	UI:Activate(1); FlushAll()
	check(#said == 1 and not UI:IsShown(), ".missed: said, and closed: " .. #said .. " " .. tostring(UI:IsShown()))
	UI:Open(".missed "); FlushAll()
	local qi
	for i, e in ipairs(UI.Results()) do if e.argLine == "qwzx" then qi = i end end
	if qi then UI:Activate(qi); FlushAll() end
	check(qi and UI:IsShown() and UI.edit:GetText() == "qwzx", "a search from its list: open on it: " .. tostring(qi) .. " " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	ns.Output = outWas
	local lines = c.run("")
	check(lines[2]:find("qwzx", 1, true) and #lines == 4, ".missed alone: the lines: " .. #lines)
	UI:Open(""); FlushAll()
	c.run("durabilty"); FlushAll()
	check(UI.edit:GetText() == "durabilty", ".missed <search>: tried again: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	c.run("clear")
	check(#ns.db.missed == 0 and c.run("")[1] == L["No search has come up empty yet."], ".missed clear: forgotten")

	ns.db.easyMode, ns.db.missed = save.easy, save.missed
	UI:EasyChanged()
end

io.write("[didyoumean: \"nearest\" alone is no likeness (release review)]\n")
do
	local DYM = T.ns.DidYouMean
	T.check(DYM.Score("nearest inkeeper", "nearest dungeon") == 0 and DYM.Score("newest mail", "nearest dungeon") == 0,
		"\"nearest inkeeper\" isn't like \"nearest dungeon\" for sharing nearest alone")
	T.check(DYM.Distance("nearset", "nearest", 2) == 1 and DYM.Distance("kitten", "sitting", 3) == 3 and DYM.Distance("abc", "abc", 1) == 0,
		"the distance, its rows used again, still right")
end
