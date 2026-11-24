-- .pick (Apps/Pick.lua, 1.8.6, the player: "I like the .pick idea!"): someone of your group at random, said in the
-- group's chat; .pick quiet only to you; .pick tacos, pizza, sushi one of those; the roll of names on screen. (1.8.12, the
-- player: the pick was said at once, before the roll had played out: said when it lands.)
local T = ...
local ns, check, FlushAll = T.ns, T.check, T.FlushAll
local PK = ns.Pick

io.write("[pick: .pick, .pick quiet, .pick a, b, c]\n")
do
	local was = { inGroup = _G.IsInGroup, inRaid = _G.IsInRaid, num = _G.GetNumGroupMembers, name = _G.UnitName,
		send = ns.ChatSender, locked = ns.ChatLocked, output = ns.Output, random = PK.random, guid = _G.UnitGUID }
	local grouped, raid = true, false
	_G.IsInGroup = function() return grouped end
	_G.IsInRaid = function() return raid end
	_G.GetNumGroupMembers = function() return grouped and 3 or 0 end
	local NAMES = { player = "Plamen", party1 = "Bob", party2 = "Eve" }
	_G.UnitName = function(u) return NAMES[u] end
	local sent, printed = {}, {}
	ns.ChatSender = function() return function(text, chat) sent[#sent + 1] = chat .. ": " .. text end end
	ns.ChatLocked = function() return false end
	ns.Output = function(_, lines) for _, l in ipairs(lines) do printed[#printed + 1] = l end end
	local seq, at = { 2 }, 0
	PK.random = function(n) at = at + 1 local v = seq[(at - 1) % #seq + 1] return math.min(v, n) end
	local run = ns:FindCommand("pick").run

	-- in a party: one of you three, said in party chat once the roll lands on it, not before
	check(run("") == nil and #sent == 0, ".pick: nothing said while the names roll")
	local f = PK.Frame()
	check(f and f.shown, "the roll shows")
	T.Flush()
	check(#sent == 0, "...still rolling: still nothing said")
	FlushAll()
	check(f.name:GetText():find("Bob", 1, true) and f.sub:GetText():find("3", 1, true), "it lands on the pick: " .. tostring(f.name:GetText()))
	check(sent[1] == "PARTY: Terminal picks Bob (of 3)" and #printed == 0, "...and says it in party as it lands: " .. tostring(sent[1]))
	check(not f.shown, "...and the roll goes after a moment")
	-- quiet: only you, as it lands
	sent, printed = {}, {}
	check(run("quiet") == nil and #printed == 0, ".pick quiet: nothing yet")
	FlushAll()
	check(#sent == 0 and printed[1] == "Terminal picks Bob (of 3)", ".pick quiet: only to you, as it lands: " .. tostring(printed[1]))
	-- a list: commas, or words
	sent = {}
	check(table.concat(PK.Listed("tacos, pizza night, sushi"), "|") == "tacos|pizza night|sushi"
		and table.concat(PK.Listed("bob alice"), "|") == "bob|alice" and PK.Listed("  ") == nil, "a list: by commas, else words")
	run("tacos, pizza night, sushi"); FlushAll()
	check(sent[1] == "PARTY: Terminal picks pizza night (of 3)", ".pick of a list, said in party: " .. tostring(sent[1]))
	-- a raid: raid chat
	raid, sent = true, {}
	_G.GetNumGroupMembers = function() return 2 end
	NAMES.raid1, NAMES.raid2 = "Plamen", "Zed"
	run(""); FlushAll()
	check(sent[1] and sent[1]:find("^RAID: Terminal picks"), "in a raid: raid chat: " .. tostring(sent[1]))
	raid = false
	_G.GetNumGroupMembers = function() return grouped and 3 or 0 end
	-- chat locked by the time it lands (an encounter pulled): said to you instead
	sent, printed = {}, {}
	run("")
	ns.ChatLocked = function() return true end
	FlushAll()
	check(#sent == 0 and printed[1] and printed[1]:find("Terminal picks Bob", 1, true), "chat locked as it lands: said to you: " .. tostring(printed[1]))
	ns.ChatLocked = function() return false end
	-- a second .pick while the first still rolls: only the second is said
	sent = {}
	run(""); T.Flush()
	seq = { 3 }; at = 0
	run(""); FlushAll()
	check(#sent == 1 and sent[1] == "PARTY: Terminal picks Eve (of 3)", "a second .pick mid-roll: only its pick said: " .. table.concat(sent, " / "))
	seq = { 2 }; at = 0
	-- no group: a list still works (only to you); nothing to pick from says how
	grouped, sent, printed = false, {}, {}
	local out = run("")
	check(out and out[1]:find("Not in a group", 1, true), "no group, no list: says how: " .. tostring(out and out[1]))
	run("tacos, pizza"); FlushAll()
	check(#sent == 0 and printed[1] == "Terminal picks pizza (of 2)", "no group, a list: only to you: " .. tostring(printed[1]))
	-- (1.8.11, review) "quiet" offered only as the first word: a list's last word matched it and was written over
	local complete = ns:FindCommand("pick").complete
	check(#complete("") == 1 and #complete("qu") == 1 and #complete("yes, no, qu") == 0 and #complete("me you qu") == 0,
		"quiet offered only as the first word")
	out = run("tacos")
	check(out and out[1]:find("Only one", 1, true), "one thing listed: nothing to pick: " .. tostring(out and out[1]))
	check(ns:FindCommand("random") and ns:FindCommand("choose"), ".random and .choose say the same")

	_G.IsInGroup, _G.IsInRaid, _G.GetNumGroupMembers, _G.UnitName = was.inGroup, was.inRaid, was.num, was.name
	ns.ChatSender, ns.ChatLocked, ns.Output, PK.random, _G.UnitGUID = was.send, was.locked, was.output, was.random, was.guid
end
