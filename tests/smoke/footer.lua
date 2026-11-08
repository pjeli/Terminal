-- The footer (1.2.6, the player's screenshot of "Recipes you can learn now · 186 whose skill isn't known left out ·
-- 372 more need more skill ("all recipes to learn" lists th" cut off: "The footer can get really long and cut off
-- sometimes; I think its okay to extend the footer downwards in such cases"). UI:FitStatus in List.lua.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll

io.write("[footer: too long for its line, it wraps and the footer grows downwards]\n")
do
	UI:Open("linen"); FlushAll()
	UI:SetStatus()
	local h1, f1 = UI.frame:GetHeight(), UI.footerH
	check((UI.statusLines or 1) == 1 and not UI.statusWrapped, "(a short footer: one line)")
	-- a long note, as "recipes i can learn now"'s
	UI.missingNote = string.rep("372 more need more skill (\"all recipes to learn\" lists them) ", 3)
	UI:SetStatus(); FlushAll()
	check(UI.statusWrapped and (UI.statusLines or 1) >= 2, "too long for one line: wrapped onto " .. tostring(UI.statusLines))
	check(UI.footerH > f1 and UI.heightTo > h1 - 0.5 and UI.heightTo >= h1 + (UI.footerH - f1) - 0.5,
		"the footer taller, the terminal with it: " .. tostring(f1) .. " -> " .. tostring(UI.footerH))
	check(not (UI.hints and UI.hints.shown), "the key hints give it their room")
	UI.missingNote = string.rep("x", 4000)
	UI:SetStatus(); FlushAll()
	check(UI.statusLines == UI.STATUS_MAX_LINES, "however long: " .. UI.STATUS_MAX_LINES .. " lines at most")
	-- short again: one line, the footer as it was
	UI.missingNote = nil
	UI:SetStatus(); FlushAll()
	check(UI.statusLines == 1 and not UI.statusWrapped and UI.footerH == f1, "short again: one line, the footer as it was")
	UI:Hide(); FlushAll()
end
