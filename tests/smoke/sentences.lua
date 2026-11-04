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
	-- (1.0.56) what your bags are worth: summed
	UI:Open(""); UI:SetQuery("what are my bags worth"); T.FlushAll()
	local wr = UI.Results()
	check(wr[1] and wr[1].kind == "aggregate" and Adv("what are my bags worth") == "in:bags | sum value" and ns.BagWorth.Question("bags") == nil,
		"what are my bags worth: in:bags | sum value: " .. tostring(wr[1] and wr[1].kind))
	UI:Hide(); T.FlushAll()
	-- (1.0.57) bigger bags than your smallest
	local BB = ns.BiggerBags
	local numWas = C_Container and C_Container.GetContainerNumSlots
	if C_Container then C_Container.GetContainerNumSlots = function(b) return ({ 16, 6, 10, 10 })[b] end end
	local bq = BB.Question("bigger bags")
	local bwas = ns.providers.items
	local brows = bq and BB.Answer(bq)
	local badv = Adv("bigger bags")
	if C_Container then C_Container.GetContainerNumSlots = numWas end
	check(bq and bq.least == 6 and badv:find("slots:>6", 1, true) and BB.Question("bags") == nil and BB.Question("bags with more slots")
		and type(brows) == "table" and brows[1], "bigger bags: than your smallest (6): " .. tostring(bq and bq.least))
	-- (1.0.58) item, quest and NPC ids, as spell ids
	local OI = ns.ObjectIds
	local iq = OI.Question("itemid linen cloth")
	local irows = iq and OI.Answer(iq)
	check(iq and iq.kind == "item" and irows and irows[1] and irows[1].name == "Linen Cloth" and irows[1].objID
		and OI.Question("item id 2589").id == 2589 and OI.Question("questid 176").kind == "quest" and OI.Question("npcid hogger").kind == "npc"
		and OI.Question("linen cloth item id").kind == "item" and OI.Question("item linen") == nil,
		"itemid linen cloth: its id: " .. tostring(irows and irows[1] and irows[1].objID))
	check(Adv("itemid linen cloth") == "itemid linen cloth", "...Alt+`: the question: " .. Adv("itemid linen cloth"))
end)
ns.db.easyMode = easy; UI:EasyChanged()
check(ok, "sentences: " .. tostring(err))
