-- An Advanced line read back in plain words (0.66.9, the player: "the explain; reverse Alt+`"): .explain. Search/Easy.lua
-- (E.Explain).
local T = ...
local ns, check = T.ns, T.check
local E = ns.Easy

io.write("[explain: an Advanced line in plain words]\n")
do
	local CASES = {
		{ "@npc is:vendor sells:arrow faction:friendly sort:distance", "Friendly vendors, that sell arrow, nearest first" },
		{ "@item q:rare+ lvl:20-30 sort:quality,-level", "Rare or better items, level 20-30, best quality first, then highest level first" },
		{ "@questie lvl:me+3 -is:done", "Quests, 3 levels above yours, not done" },
		{ "@mail older:20d", "Mail, older than 20 days" },
		{ "@drop since:yesterday older:today", "Loot you saw drop, since yesterday, from before today" },
		{ "@mailbox sort:distance | first 3", "Mailboxes, nearest first, the first 3" },
		{ "in:bags | sum value", "Everything, in bags, the value summed up" },
		{ "linen value:>1g", "Everything matching linen, worth over 1g" },
		{ "@item is:upgrade sort:best >> party", "Upgrades for you, biggest upgrades first, sent to party" },
		{ "@questie lvl:me-2..me+3", "Quests, from 2 levels below yours to 3 levels above yours" },
		{ "type:sword|type:axe", "Sword or axe" },
		-- (review) a time ago said as one: not "since 3 days", "since 1 hours"
		{ "@drop since:3d", "Loot you saw drop, in the last 3 days" },
		{ "@drop since:1h", "Loot you saw drop, in the last hour" },
		{ "@mail older:1d", "Mail, older than 1 day" },
	}
	for _, c in ipairs(CASES) do
		local got = E.Explain(c[1])
		check(got == c[2], ("%q:\n    want %q\n    got  %q"):format(c[1], c[2], tostring(got)))
	end
	check(E.Explain("") == nil and E.Explain("   ") == nil, "nothing typed: nothing to say")
	-- the command: a line, or the last one run
	local cmd = ns:FindCommand("explain")
	local out = cmd.run("@npc is:innkeeper sort:distance", ns)
	check(out[2] and out[2]:find("Innkeepers, nearest first", 1, true), ".explain <line>: " .. tostring(out[2]))
	ns:RecordHistory("@mail is:unread")
	out = cmd.run("", ns)
	check(out[1] == "@mail is:unread" and out[2]:find("Unread mail", 1, true), ".explain: the last line run: " .. tostring(out[2]))
	-- (review) the last line in plain words: explained as Advanced writes it, not word for word
	ns:RecordHistory("the 3 nearest mailboxes")
	out = cmd.run("", ns)
	check(out[1] ~= "the 3 nearest mailboxes" and not tostring(out[2]):find("matching the 3 nearest", 1, true),
		".explain: a Simple line as Advanced writes it: " .. tostring(out[1]) .. " / " .. tostring(out[2]))
	check(ns.Bar.SpecLabel("since:3d", "since:3d") == ns.L["In the last %s"]:format("3 " .. ns.L["days"]), "the bar says it so too: " .. tostring(ns.Bar.SpecLabel("since:3d", "since:3d")))
end

io.write("[explain: the pointer on an Advanced line]\n")
do
	local UI = T.UI
	UI:Open(""); T.FlushAll()
	UI:SetQuery("@npc is:innkeeper sort:distance"); T.FlushAll()
	local shown = {}
	local realTip = _G.GameTooltip
	_G.GameTooltip = T.Obj("GameTooltip")
	_G.GameTooltip.AddLine = function(_, l) shown[#shown + 1] = l end
	UI.hit.scripts.OnEnter(UI.hit)
	check(shown[1] == "Innkeepers, nearest first" and _G.GameTooltip.text == ns.L["In plain words"], "hovered: said in plain words: " .. tostring(shown[1]))
	UI.hit.scripts.OnLeave(UI.hit)
	shown = {}
	UI:SetQuery("hogger"); T.FlushAll()
	UI.hit.scripts.OnEnter(UI.hit)
	check(#shown == 0, "plain words: nothing to say")
	-- (review) the line changed with the pointer still on it: said again
	UI:SetQuery("@mail is:unread"); T.FlushAll()
	UI.hit.scripts.OnEnter(UI.hit)
	shown = {}
	UI:SetQuery("@npc is:innkeeper sort:distance"); T.FlushAll()
	check(shown[1] == "Innkeepers, nearest first", "typed on with the pointer on it: said again: " .. tostring(shown[1]))
	UI.hit.scripts.OnLeave(UI.hit)
	_G.GameTooltip = realTip
	UI:Hide(); T.FlushAll()
end
