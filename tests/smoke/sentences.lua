-- (1.0.46-1.0.49, the player's ask: the reach audit's part 2) lines that were read as the wrong thing: a state turned
-- round in a sentence ("quests i haven't done"), who gives a quest, a list near you, your alts' items.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local E = ns.Easy
io.write("[sentences: lines read as what they say]\n")
local easy = ns.db.easyMode
ns.db.easyMode = true; UI:EasyChanged()
local function Adv(line) return ((E.ToAdvanced(line) or ""):gsub("%s+$", "")) end
local ok, err = pcall(function()
	-- (1.0.46) "haven't", "not yet" before a state word turn it round; "i have" goes
	for line, want in pairs({ ["quests i haven't done"] = "@questlog -is:done", ["quests i havent done"] = "@questlog -is:done",
		["quests i have done"] = "@questlog is:done", ["undone quests"] = "@questlog -is:done", ["quests not yet done"] = "@questlog -is:done",
		["quests i havent done in westfall"] = "@questlog westfall -is:done", ["achievements i havent earned"] = "@achievement -is:done" }) do
		check(Adv(line) == want, line .. ": " .. want .. " (got " .. Adv(line) .. ")")
	end
	-- (1.0.48) near you: a list that isn't NPCs, by distance; quests and turn-ins by their NPC's; NPCs as before
	local NQ = ns.NearQuests
	check(NQ.Question("quests near me") and NQ.Question("nearest quests") and NQ.Question("turn ins near me").turn
		and not NQ.Question("quests") and not NQ.Question("nearest innkeeper") and not NQ.Question("quests near hogger"),
		"quests near me, turn ins near me: the questions; not quests alone, nor an NPC")
	local rows = NQ.Answer(NQ.Question("quests near me"))
	check(type(rows) == "table" and rows[1] ~= nil, "quests near me: an answer (a note without Questie)")
	check(Adv("camps nearby") == "@camp sort:distance" and Adv("nearest camp") == "@camp sort:distance"
		and Adv("dungeons near me") == "@dungeon sort:distance" and Adv("nearest innkeeper"):find("@npc is:innkeeper", 1, true),
		"camps nearby: @camp nearest first; dungeons, innkeepers as before: " .. Adv("camps nearby"))
end)
ns.db.easyMode = easy; UI:EasyChanged()
check(ok, "sentences: " .. tostring(err))
