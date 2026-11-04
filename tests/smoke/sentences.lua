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
		["quests i havent done in westfall"] = "@questlog westfall -is:done", ["achievements i havent earned"] = "@achievement -is:done",
		-- (review, 1.0.66: a state already turned round, turned round again)
		["quests not undone"] = "@questlog is:done", ["quests not incomplete"] = "@questlog is:done" }) do
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
	check(Adv("what alt has linen") == "@stored linen", "what alt has linen: as which alt (review, 1.0.66): " .. Adv("what alt has linen"))
	-- (review, 1.0.66) "nearest" and a list's name: only a list whose rows have a place, never beside an NPC's role
	check(Adv("nearest recipe vendor"):find("@npc", 1, true) and Adv("nearest recipe vendor"):find("is:vendor", 1, true)
		and not Adv("nearest achievement"):find("@achievement", 1, true) and not Adv("nearest macro"):find("@macro", 1, true),
		"nearest recipe vendor: vendors; nearest achievement: no distance: " .. Adv("nearest recipe vendor") .. " / " .. Adv("nearest achievement"))
	-- (review, 1.0.66) a list matched by names only: close spellings of the name too
	local Scan = ns.UI._Scan
	local zan = { name = "Zanzil's Concentration" }
	check(not Scan.NameLeftOut(1, zan, { "zanzils", "concentration" }) and not Scan.NameLeftOut(1, zan, { "zanzil", "concentation" })
		and Scan.NameLeftOut(1, zan, { "linen" }) and not Scan.NameLeftOut(0, zan, { "linen" }), "names only: close spellings of the name count, other words don't")
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
	-- (review, 1.0.70) Alt+` lists what the answer counts: your bags' too, with a bag addon's records
	do
		local had = ns.providers.stored
		ns.providers.stored = ns.providers.stored or { id = "stored" }
		local line = HV.ToAdvanced(hq)
		ns.providers.stored = had
		check(line:find("^@item @stored ") ~= nil, "how many linen do i have, Alt+`: your bags and your records: " .. line)
		local SF = E.SayFilter
		check(SF("is:rareelite") == ns.Lower(ns.L["Rare Elite"]) and SF("is:daily") == ns.Lower(ns.L["Daily"]) and SF("skill:any"):find(ns.L["a profession"], 1, true),
			".explain: an NPC's rank, a daily quest, skill:any in words: " .. tostring(SF("is:rareelite")) .. " / " .. tostring(SF("skill:any")))
		local helped = false
		for _, h in ipairs(ns.Filters.HELP) do if h[1] == "is:elite" then helped = true end end
		check(helped, ".filters: a line for an NPC's rank")
	end
	-- (review, 1.0.65) not another question's: "how many mounts do i have" (the collections'), "do i have mail" (the
	-- mail's), "how much gold do i have" (no item)
	do
		local Scan = ns.UI._Scan
		local hv, hit = HV.Question, nil
		HV.Question = function(t) local r = hv(t) if r then hit = true end return r end
		for _, line in ipairs({ "how many mounts do i have", "how many pets do i have", "do i have mail", "do i have any mail",
			"how much gold do i have" }) do
			hit = nil
			for _, a in ipairs(Scan.ANSWERS) do if a.ask and a.ask(line) then break end end
			check(not hit, line .. ": not the item count's")
		end
		HV.Question = hv
		check(HV.Question("how much gold do i have") == nil and HV.Question("do i have any linen").what == "linen", "gold isn't an item; any linen is")
	end
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
	-- (review, 1.0.67) a zone called "The ...": with "the" or without
	check(LV.Question("the barrens level") and LV.Question("barrens level") and LV.Question("what level is the barrens"),
		"the barrens level: with or without the")
	-- (review, 1.0.67) a list's name said alone: each list read once for it, not on every ask
	do
		local reads, rows = 0, { { name = "Zzlist", _lname = "zzlist" } }
		local fake = setmetatable({ id = "zzfake", label = "Zz", aliases = {} }, { __index = function(_, k)
			if k == "_entries" then reads = reads + 1 return rows end end })
		ns.providers.zzfake = fake
		ns.providerOrder[#ns.providerOrder + 1] = "zzfake"
		Adv("macros"); local first = reads
		Adv("macros"); Adv("macros")
		ns.providers.zzfake = nil
		table.remove(ns.providerOrder)
		check(first >= 1 and reads == first, "macros said alone: the lists read once for it (" .. first .. ", then " .. reads .. ")")
	end
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
	check(bq and bq.least == 6 and badv == "bigger bags" and BB.Question("bags") == nil and BB.Question("bags with more slots")
		and type(brows) == "table" and brows[1], "bigger bags: than your smallest (6): " .. tostring(bq and bq.least))
	-- (review, 1.0.68) the most slots first, and the cut keeps those
	do
		local mk = function(n) return { kind = "items", name = n .. " Slot Bag", itemID = 90000 + n, slots = n } end
		local rowsWas, maxWas, slotsWas = ns.providers.items, BB.MAX, ns.QuestRewards.SlotsOfRow
		ns.providers.items = { id = "items", label = "Items", aliases = {}, _dirty = true,
			collect = function() return { mk(8), mk(14), mk(10), mk(18), mk(12) } end }
		ns.QuestRewards.SlotsOfRow = function(e) return e.slots end
		BB.MAX = 3
		local got = BB.Answer({ least = 6 })
		BB.MAX, ns.providers.items, ns.QuestRewards.SlotsOfRow = maxWas, rowsWas, slotsWas
		local said = {}
		for i, e in ipairs(got) do said[i] = tostring(e.slots) end
		check(table.concat(said, ",") == "18,14,12", "bigger bags: the most slots first, those kept: " .. table.concat(said, ","))
	end
	-- (review, 1.0.68) an instance's bosses: its whole name (or its start, 4 letters or more), each instance's own, no
	-- faction's standing as a boss
	do
		local P = ns.Pipes
		local function Row(boss, inst, src, n) return { kind = "loot", name = "Item " .. n, itemID = 80000 + n, detail = boss .. "  " .. inst, lootSource = src } end
		local lootWas = ns.providers.loot
		ns.providers.loot = { id = "loot", label = "Loot", aliases = {}, _dirty = true, collect = function() return {
			Row("Baron Rivendare", "Stratholme", "dungeon", 1), Row("Trash Mobs", "Stratholme", "dungeon", 2),
			Row("Bazil Thredd", "The Stockade", "dungeon", 3), Row("Trash Mobs", "The Stockade", "dungeon", 4),
			Row("Honored", "Argent Dawn", "reputation", 5) } end }
		local IB = ns.InstanceBosses
		local st, ad, short = IB.Question("stockade bosses"), IB.Question("argent dawn bosses"), IB.Question("boss a")
		local srows = st and IB.Answer(st)
		ns.providers.loot = lootWas
		local names = {}
		for i, e in ipairs(srows or {}) do names[i] = e.name .. "@" .. tostring(e.detail):match("^(.-)%s") end
		check(st and #st.bosses == 2 and not ad and not short and not P.BossLoot()["honored"],
			"stockade bosses: its own two (its trash once), not Stratholme's; argent dawn: no bosses: " .. table.concat(names, ", "))
	end
	-- (1.0.58) item, quest and NPC ids, as spell ids
	local OI = ns.ObjectIds
	local iq = OI.Question("itemid linen cloth")
	local irows = iq and OI.Answer(iq)
	check(iq and iq.kind == "item" and irows and irows[1] and irows[1].name == "Linen Cloth" and irows[1].objID
		and OI.Question("item id 2589").id == 2589 and OI.Question("questid 176").kind == "quest" and OI.Question("npcid hogger").kind == "npc"
		and OI.Question("linen cloth item id").kind == "item" and OI.Question("item linen") == nil,
		"itemid linen cloth: its id: " .. tostring(irows and irows[1] and irows[1].objID))
	check(Adv("itemid linen cloth") == "itemid linen cloth", "...Alt+`: the question: " .. Adv("itemid linen cloth"))
	-- (1.0.59) almost done: the closest to done first; sort:progress
	local A = ns.Aggregate
	check(A.Progress({ kind = "achievements", progress = "3/4" }) == 0.75 and A.Progress({ kind = "quests", objectives = { { "Gnoll Paw: 3/8" }, { "Flank: 1/2" } } }) == 0.4
		and ns.Filters.SortOf("sort:progress") == "progress", "progress: an achievement's criteria, a quest's objectives; sort:progress")
	local AD = ns.AlmostDone
	check(AD.Question("achievements almost done").kind == "achievements" and AD.Question("quests almost done").kind == "quests"
		and AD.Question("achievements") == nil and Adv("achievements almost done") == "achievements almost done"
		and type(AD.Answer(AD.Question("achievements almost done"))) == "table", "achievements almost done: the question, its Advanced line")
	-- (1.0.60) where your hearthstone takes you
	local HB = ns.HearthBind
	local bindWas, cdWas = _G.GetBindLocation, C_Container and C_Container.GetItemCooldown
	_G.GetBindLocation = function() return "Goldshire" end
	if C_Container then C_Container.GetItemCooldown = function() return 0, 0, 1 end end
	local hrows = HB.Question("where is my hearth") and HB.Answer()
	_G.GetBindLocation = bindWas
	if C_Container then C_Container.GetItemCooldown = cdWas end
	local hs = hrows and hrows[1]
	check(hs and (tostring(hs.detail) .. tostring(hs.name)):find("Goldshire", 1, true) and (tostring(hs.detail) .. tostring(hs.name)):find(ns.L["ready"], 1, true)
		and HB.Question("hearthstone") == nil, "where is my hearth: Goldshire, ready: " .. tostring(hs and hs.detail))
	-- (1.0.61) experience an hour this session, and the time to the next level
	local X, XR = ns.Experience, ns.XpRate
	local readWas, sessWas = X.ReadMe, X.session
	X.ReadMe = function() return { level = 20, xp = 1000, max = 7000 } end
	X.session = nil
	X.SessionTick()
	X.SessionTick({ level = 20, xp = 4000, max = 7000 })
	X.SessionTick({ level = 21, xp = 500, max = 7500 }) -- (a level's rollover: the rest of 20, then 500)
	X.session.since = ns.Now() - 3600
	X.ReadMe = function() return { level = 21, xp = 500, max = 7500 } end
	local rate = X.Rate()
	local xrows = XR.Question("how long to level") and XR.Answer()
	X.ReadMe, X.session = readWas, sessWas
	check(rate and math.floor(rate + 0.5) == 6500 and xrows and xrows[2] and tostring(xrows[2].name):find("22", 1, true) and XR.Question("level") == nil,
		"how long to level: 6500 an hour this session, level 22 in about an hour: " .. tostring(rate) .. " / " .. tostring(xrows and xrows[2] and xrows[2].name))
	-- (review, 1.0.68) a rollover read before the level catches up: counted once; at the level cap: said so
	X.session = nil
	X.SessionTick({ level = 20, xp = 6000, max = 7000 })
	X.SessionTick({ level = 20, xp = 300, max = 7000 })
	X.SessionTick({ level = 21, xp = 300, max = 7500 })
	local rolled = X.session.gained
	X.ReadMe = function() return { level = 60, maxed = true } end
	local mrows = XR.Answer()
	X.ReadMe, X.session = readWas, sessWas
	check(rolled == 1300 and mrows[1] and mrows[1].name == ns.L["Max level"], "a level-up read late: 1300, not 7000 (" .. tostring(rolled)
		.. "); at the cap: " .. tostring(mrows[1] and mrows[1].name))
	-- (review, 1.0.68) "who gives" a name two quests share: both, those in your log first
	do
		local QP = ns.QuestPeople
		local qWas = ns.providers.questie
		ns.providers.questie = { id = "questie", _entries = { { name = "Twin Hunt", qid = 7001 }, { name = "Twin Hunt", qid = 7002 } } }
		local q2 = QP.Question("who gives twin hunt")
		ns.providers.questie = qWas
		local logWas = C_QuestLog.GetLogIndexForQuestID
		C_QuestLog.GetLogIndexForQuestID = function(id) return id == 7002 and 1 or nil end
		local which = q2 and QP.Which(q2.ids)
		C_QuestLog.GetLogIndexForQuestID = logWas
		check(q2 and #q2.ids == 2 and which and #which == 1 and which[1] == 7002, "who gives twin hunt: both quests, the one in your log: " .. tostring(q2 and #q2.ids) .. " / " .. tostring(which and #which) .. " / " .. tostring(which and which[1]))
	end
end)
ns.db.easyMode = easy; UI:EasyChanged()
check(ok, "sentences: " .. tostring(err))
