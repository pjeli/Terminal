-- The password where else the typed line shows (0.60.0 review): the tab strip's label and the command completion's
-- ghost and accept, as the prompt does (*s, never its letters)
local T = ...
local ns, UI, check = T.ns, T.UI, T.check

io.write("[share: the password in the tab strip and completions]\n")

-- the tab strip: the shown tab's label is the line as typed, masked
do
	UI:Open("")
	T.typeText("linen")
	ns.Tabs.New()
	T.typeText(".share password Hunter2hunter2")
	T.FlushAll()
	UI:Render()
	local leak, labels = nil, 0
	for _, b in ipairs(ns.Tabs.strip and ns.Tabs.strip.buttons or {}) do
		local l = b.label or ""
		labels = labels + 1
		if l:find("unter2", 1, true) then leak = l end
	end
	check(labels >= 2 and leak == nil, "the tab strip: the password typed in the shown tab as *s: " .. tostring(leak))
	ns.Tabs.Close()
	UI:Hide()
end

-- the completion: none on a password's letters (its ghost would show them after the *s; accepting it would put another
-- word in place of the password, unseen)
do
	UI:Open("")
	T.typeText(".share password c")
	T.FlushAll()
	check(UI:Completion() == nil, ".share password c: no completion of the password: " .. tostring(UI:Completion()))
	UI:Hide(); UI:Open("")
	T.typeText(".share join raid Al")
	T.FlushAll()
	check(UI:Completion() == nil, ".share join raid Al: none either: " .. tostring(UI:Completion()))
	UI:Hide(); UI:Open("")
	T.typeText(".share pass")
	T.FlushAll()
	local c = UI:Completion()
	check(c and c:find("password", 1, true), "...a subcommand still completes (.share pass): " .. tostring(c))
	UI:Hide()
end
