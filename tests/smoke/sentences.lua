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
	-- (1.0.49) your alts': "items on my alts" is @stored (not your bags), "which alt has linen" the alts' linen
	check(Adv("items on my alts") == "@stored" and Adv("which alt has linen") == "@stored linen" and Adv("linen on my alts") == "@stored linen",
		"items on my alts, which alt has linen: @stored: " .. Adv("items on my alts") .. " / " .. Adv("which alt has linen"))
	-- (1.0.51) how many you have, and where
	local HV = ns.HaveQ
	local hq = HV.Question("how many linen do i have")
	local hrows = hq and HV.Answer(hq)
	check(hq and hq.what == "linen" and HV.Question("do i have linen cloth").what == "linen cloth" and HV.Question("count my linen").what == "linen"
		and HV.Question("how many") == nil and hrows and hrows[1] and hrows[1].name == "Linen Cloth" and (hrows[1].detail or ""):find("have", 1, true),
		"how many linen do i have: Linen Cloth, how many: " .. tostring(hrows and hrows[1] and hrows[1].detail))
	check(HV.ToAdvanced(hq):find("linen", 1, true), "...and its Advanced line: " .. HV.ToAdvanced(hq))
	-- (1.0.53) where to farm or find a thing: its sources
	local P = ns.Pipes
	check(P.Canonical("where to farm linen cloth") == "linen cloth > sources" and P.Canonical("where do i find red bandanas") == "red bandanas > sources"
		and P.Canonical("where can i find linen") == "linen > sources", "where to farm / find a thing: its sources: " .. tostring(P.Canonical("where to farm linen cloth")))
	-- (1.0.54) flight paths you don't know: as "unknown flight paths"
	local unknown = Adv("unknown flight paths")
	for _, line in ipairs({ "flight paths i don't know", "flight paths i dont have", "flight paths i haven't got" }) do
		local a = Adv(line)
		check(a:find("is:unlearned", 1, true) and a:find("is:flightpath", 1, true) and not a:find("%f[%a]i%f[%A]"), line .. ": as " .. unknown .. " (got " .. a .. ")")
	end
	-- (1.0.55) levels as an answer: a zone's range, a dungeon's (an NPC's: questiedb.lua)
	local LV = ns.LevelOf
	local zq = LV.Question("duskwood level")
	local zrows = zq and LV.Answer(zq)
	check(zq and zq.said and zrows and zrows[1] and (tostring(zrows[1].name) .. " " .. tostring(zrows[1].detail)):find("Lv", 1, true)
		and LV.Question("my level") == nil and LV.Question("what level is nothing like this") == nil,
		"duskwood level: its range: " .. tostring(zq and zq.said))
	local dq = LV.Question("what level is the stockade")
	check(not ns.providers.dungeon or (dq and dq.said), "what level is the stockade: the dungeon's: " .. tostring(dq and dq.said))
end)
ns.db.easyMode = easy; UI:EasyChanged()
check(ok, "sentences: " .. tostring(err))
