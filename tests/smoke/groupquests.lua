-- Quests with your party (GroupQuests.lua, 0.47.1): "party quests" / "@group quests": each quest in your log with who
-- in your party is on it; Enter shares it; "quests to share"; >>> party says it in one line.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check

io.write("[party quests]\n")
do
	local PQ, P, QP = ns.GroupQuests, ns.providers.groupquests, ns.providers.quests
	check(PQ and P and QP, "the party quests list is registered")
	if not (PQ and P and QP) then return end
	local names = { "GetNumSubgroupMembers", "GetNumGroupMembers", "IsInRaid", "IsInGroup", "UnitExists", "UnitName",
		"UnitIsConnected", "QuestLogPushQuest", "IsUnitOnQuest", "issecretvalue", "RegionalUniqueNamesEnabled", "UnitGUID",
		"hooksecurefunc", "time" }
	local trustWas, learnedWas, lastWas, hookedWas = PQ.trusted, PQ.learned, PQ.lastShare, PQ.pushHooked
	PQ.trusted, PQ.learned, PQ.lastShare = false, {}, nil
	local clock = 7000000
	_G.time = function() return clock end
	local save = {}
	for _, n in ipairs(names) do save[n] = _G[n] end
	local QL = C_QuestLog
	local qsave = { QL.GetNumQuestLogEntries, QL.GetInfo, QL.IsUnitOnQuest, QL.IsPushableQuest, QL.GetLogIndexForQuestID,
		QL.GetSelectedQuest, QL.SetSelectedQuest }
	local easyWas = ns.db.easyMode

	-- your log: four quests; your party: Ann and Bob online, Cid offline
	local log = {
		{ title = "Elwynn Forest", isHeader = true },
		{ title = "Wolves Across the Border", questID = 33, level = 5 },
		{ title = "The Fargodeep Mine", questID = 34, level = 7 },
		{ title = "Princess Must Die!", questID = 35, level = 9 },
		{ title = "The Defias Brotherhood", questID = 36, level = 18 },
	}
	local index = { [33] = 2, [34] = 3, [35] = 4, [36] = 5 }
	local party = { party1 = { name = "Ann" }, party2 = { name = "Bob" }, party3 = { name = "Cid", offline = true } }
	local onQuest = { party1 = { [33] = true, [34] = true }, party2 = { [34] = true }, party3 = { [33] = true } }
	local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
	local secretFor, asked, nParty = nil, {}, 3
	local selected, pushed = 33, {}
	_G.issecretvalue = function(v) return v == SECRET end
	_G.GetNumSubgroupMembers = function() return nParty end
	_G.IsInRaid = function() return false end
	_G.IsInGroup = function() return nParty > 0 end
	_G.RegionalUniqueNamesEnabled = function() return false end
	_G.UnitExists = function(u) return party[u] ~= nil and tonumber(u:match("%d+") or 0) <= nParty end
	_G.UnitName = function(u) return party[u] and party[u].name end
	_G.UnitGUID = function(u) return party[u] and ("G-" .. party[u].name) or "G-ME" end
	_G.UnitIsConnected = function(u) return not (party[u] and party[u].offline) end
	QL.GetNumQuestLogEntries = function() return #log end
	QL.GetInfo = function(i) return log[i] end
	QL.IsUnitOnQuest = function(u, id)
		asked[u] = (asked[u] or 0) + 1
		if secretFor == u then return SECRET end
		return onQuest[u] and onQuest[u][id] == true or false
	end
	QL.IsPushableQuest = function(id) return id ~= 36 end
	QL.GetLogIndexForQuestID = function(id) return index[id] end
	QL.GetSelectedQuest = function() return selected end
	QL.SetSelectedQuest = function(id) selected = id end
	_G.QuestLogPushQuest = function(i) pushed[#pushed + 1] = { i = i, selected = selected } end

	local function Rows()
		QP._dirty, P._dirty = true, true
		local by = {}
		for _, e in ipairs(ns:GetEntries(P)) do by[e.questID] = e end
		return by
	end
	local by = Rows()
	local wolves, mine, princess, defias = by[33], by[34], by[35], by[36]
	check(wolves and mine and princess and defias, "every quest in your log")
	check(table.concat(wolves.on, ",") == "Ann" and table.concat(wolves.lacks, ",") == "Bob" and wolves.canShare
		and wolves.detail:find("Ann too", 1, true) and wolves.detail:find("share with Bob", 1, true),
		"Wolves: Ann is on it too, Bob lacks it (share with Bob): " .. wolves.detail)
	check(asked.party3 == nil, "an offline member isn't asked (Cid can't be shared with either)")
	check(not wolves.canShare == false and #wolves.lacks == 1, "offline Cid isn't counted as lacking it")
	check(mine.everyone and not mine.canShare and mine.detail:find("the whole party", 1, true), "Fargodeep: the whole party is on it: " .. mine.detail)
	check(#princess.on == 0 and princess.canShare and princess.detail:find("only you", 1, true) and princess.detail:find("can share", 1, true),
		"Princess: only you, and you can share it: " .. princess.detail)
	check(defias.pushable == false and not defias.canShare and defias.detail:find("can't be shared", 1, true),
		"Defias: the game won't let it be shared: " .. defias.detail)

	-- Enter shares (the quest log's own Share: by the log's index, the quest selected around it, put back)
	wolves.activate(wolves)
	check(#pushed == 1 and pushed[1].i == 2 and pushed[1].selected == 33 and selected == 33, "Enter: Wolves shared (log index 2)")
	selected = 34
	princess.activate(princess)
	check(#pushed == 2 and pushed[2].i == 4 and pushed[2].selected == 35 and selected == 34, "the quest log's selection put back")
	-- a quest the game won't share: Enter is the quest log row's own (the game opens the log at it)
	check(defias.secure == defias.quest.secure and defias.secure ~= nil and defias.activate == defias.quest.activate
		and defias.secondarySecure == nil, "Defias: Enter opens your quest log at it, no Shift+Enter")
	check(wolves.secure == nil and wolves.secondarySecure == wolves.quest.secure and wolves.secondaryAfter == wolves.quest.after,
		"Wolves: Shift+Enter is the quest log at it")
	check(table.concat({ ns.Easy.Verbs(wolves) }, "/") == "share with party/show in quest log"
		and table.concat({ ns.Easy.Verbs(defias) }, "/") == "show in quest log", "verbs: share with party / show in quest log")
	-- not in a party any more: said, nothing pushed
	nParty = 0
	local printed
	local printWas = ns.Print
	ns.Print = function(_, s) printed = s end
	wolves.activate(wolves)
	ns.Print = printWas
	check(#pushed == 2 and printed and printed:find("not in a party", 1, true), "not in a party: nothing shared: " .. tostring(printed))
	nParty = 3

	-- the question
	local Q = PQ.Question
	local function M(text) local q = Q(text) return q and q.mode or "-" end
	check(M("party quests") == "all" and M("group quests") == "all" and M("who is on my quests") == "all"
		and M("quests to share") == "share" and M("shareable quests") == "share" and M("party members missing quests") == "share"
		and M("same quests as my group") == "together" and M("quests in common") == "together",
		"party quests / quests to share / same quests")
	check(Q("who gives the quest hogger") == nil and Q("quests to drop") == nil and Q("missing quest items") == nil
		and Q("quest") == nil and Q("party") == nil and Q("@group quests") == nil, "other lines stay what they were")
	local q = Q("party quests princess")
	check(q and q.words[1] == "princess", "words after it narrow the list")

	ns.db.easyMode = true
	local function Search(text) local t = {} for i, e in ipairs(UI:Search(text)) do t[i] = e.questID or e.name end return table.concat(t, ",") end
	check(Search("party quests") == "33,34,35,36" and UI.answerNote and UI.answerNote:find("Party quests", 1, true),
		"Simple: \"party quests\": every quest, the log's order: " .. Search("party quests"))
	check(Search("quests to share") == "33,35", "quests to share: Wolves and Princess: " .. Search("quests to share"))
	check(Search("party quests princess") == "35", "party quests princess: " .. Search("party quests princess"))
	check(Search("party members missing quests") == "33,35", "asked before the group's own questions (missing = quests here)")
	check(ns.Easy.QuestionToAdvanced("quests to share") == "@group quests is:shareable "
		and ns.Easy.QuestionToAdvanced("party quests") == "@group quests ", "Alt+` writes it as @group quests")

	-- Advanced: @group quests
	ns.db.easyMode = false
	check(Search("@group quests") == "33,34,35,36", "@group quests: " .. Search("@group quests"))
	check(Search("@group quests is:shareable") == "33,35" and Search("@group quests is:together") == "33,34",
		"is:shareable / is:together")
	local still = UI:Search("@group")
	local groupRows = true
	for _, e in ipairs(still) do if e.kind == "groupquests" then groupRows = false end end
	check(groupRows, "@group alone is still your group's members")
	check(ns:KindName(P) == "@group quests" and ns:ResolveProvider("groupquests") ~= P, "named \"@group quests\", no @word of its own")
	-- the file not loaded (a /reload after the update doesn't load new files): a line says to restart
	ns.providers.groupquests = nil
	local gone = UI:Search("@group quests")
	ns.providers.groupquests = P
	check(gone[1] and tostring(gone[1].name):find("Restart the game for party quests", 1, true), "its file not loaded: restart, said")

	-- >>> party: one line, the same quests (who, when not the whole party) and what you can share
	local lines = PQ.ShareGroupOf(UI:Search("@group quests"), "@group quests")
	check(lines[1] == "On the same quests: Wolves Across the Border (Ann), The Fargodeep Mine. I can share: Wolves Across the Border, Princess Must Die!",
		"the line: " .. tostring(lines[1]))
	lines = PQ.ShareGroupOf(UI:Search("@group quests is:shareable"), "@group quests is:shareable")
	check(lines[1] == "I can share: Wolves Across the Border, Princess Must Die!", "only what you can share: " .. tostring(lines[1]))
	lines = ns.Share.GroupLines(UI:Search("@group quests is:together"), "@group quests is:together")
	check(lines[1] == "On the same quests: Wolves Across the Border (Ann), The Fargodeep Mine.", "through Share's GroupLines: " .. tostring(lines[1]))
	lines = PQ.ShareGroupOf({ defias }, "@group quests")
	check(lines[1] == "No quests in common, none to share.", "nothing: said: " .. tostring(lines[1]))
	check(ns.Share.Text(wolves):find("(also on it: Ann; I can share it)", 1, true), "one row: " .. tostring(ns.Share.Text(wolves)))

	-- a member the game can't tell about (a secret answer): not counted as lacking it
	secretFor = "party2"
	by = Rows()
	check(#by[33].lacks == 0 and by[33].unknown[1] == "Bob" and by[33].canShare and by[33].party[2].status == nil,
		"Bob unknown (secret): not lacking Wolves, offered it")
	secretFor = nil

	-- 0.47.2 (the player: Steelsnap shared, "is already on that quest", yet not shown; the game's quest log showed no
	-- "[1]" either): the game never saying "yes" here, its "no" isn't trusted; sharing teaches who has a quest
	PQ.trusted = false
	local onWas = onQuest
	onQuest = {}
	by = Rows()
	wolves, princess = by[33], by[35]
	check(not PQ.trusted and #wolves.lacks == 0 and #wolves.unknown == 2 and wolves.canShare
		and wolves.detail:find("who has it isn't known", 1, true) and wolves.detail:find("can share", 1, true),
		"no \"yes\" from the game: who has Wolves isn't known (offered to both): " .. wolves.detail)
	local _, unknownNote = PQ.Answer({ mode = "all" })
	check(unknownNote:find(PQ.UNKNOWN_NOTE, 1, true), "the note says so: " .. tostring(unknownNote))
	-- share Wolves: the game replies
	pushed = {}
	wolves.activate(wolves)
	check(PQ.lastShare and PQ.lastShare.id == 33, "the share is remembered for its replies")
	check(PQ.Learn("Bob is already on that quest") and not PQ.Learn("Zed is already on that quest"),
		"\"Bob is already on that quest\": kept; a name not in your party: not")
	clock = clock + 40
	check(not PQ.Learn("Ann is already on that quest") and PQ.Learn("Ann has accepted your quest"),
		"an immediate reply 40 s later: not this share's; an answer they clicked: still is")
	by = Rows()
	check(by[33].everyone and not by[33].canShare and table.concat(by[33].on, ",") == "Ann,Bob" and by[35].canShare,
		"Wolves: the whole party is on it now (learned); Princess still offered")
	-- through the game's own lines (UI_INFO_MESSAGE: a type, then the text), for a quest shared from the quest log
	local hooked
	_G.hooksecurefunc = function(name, fn) local orig = _G[name]; _G[name] = function(...) orig(...); fn(...) end; hooked = name end
	PQ.pushHooked = nil
	check(PQ.HookPush() and hooked == "QuestLogPushQuest", "the quest log's own Share is hooked")
	_G.QuestLogPushQuest(4) -- (Princess, from the quest log)
	check(PQ.lastShare.id == 35, "a share from the quest log is remembered too")
	local onEvent = PQ.frame:GetScript("OnEvent")
	onEvent(PQ.frame, "UI_INFO_MESSAGE", 0, "Ann has completed that quest")
	onEvent(PQ.frame, "CHAT_MSG_SYSTEM", "Bob is not eligible for that quest")
	by = Rows()
	princess = by[35]
	check(princess.done[1] == "Ann" and princess.cant[1] == "Bob" and not princess.canShare
		and princess.detail:find("Ann did it", 1, true) and princess.detail:find("Bob can't take it", 1, true),
		"Princess: Ann has done it, Bob can't take it: nothing to share: " .. princess.detail)
	-- the game says "yes" once: its "no" counts from then on (Bob lacks Fargodeep)
	onQuest = { party1 = { [34] = true } }
	by = Rows()
	check(PQ.trusted and table.concat(by[34].lacks, ",") == "Bob" and by[34].canShare, "the game said yes once: its no counts")
	onQuest = onWas
	PQ.ResetRepliesForTests()

	-- not in a party (the game sends GROUP_ROSTER_UPDATE)
	nParty = 0
	P._dirty = true
	ns.db.easyMode = true
	local solo = UI:Search("party quests")
	check(#solo == 1 and solo[1].name == PQ.NONE, "not in a party: said: " .. tostring(solo[1] and solo[1].name))
	ns.db.easyMode = false
	solo = UI:Search("@group quests")
	check(solo[1] and solo[1].name == PQ.NONE, "@group quests not in a party: the line on top")

	for _, n in ipairs(names) do _G[n] = save[n] end
	PQ.trusted, PQ.learned, PQ.lastShare, PQ.pushHooked = trustWas, learnedWas, lastWas, hookedWas
	QL.GetNumQuestLogEntries, QL.GetInfo, QL.IsUnitOnQuest, QL.IsPushableQuest, QL.GetLogIndexForQuestID,
		QL.GetSelectedQuest, QL.SetSelectedQuest = unpack(qsave, 1, 7)
	ns.db.easyMode = easyWas
	QP._dirty, P._dirty = true, true
end

-- (review, 0.53.6) a quest with no level and no zone: its detail doesn't start with a lone separator
do
	local row = T.ns.GroupQuests._Row({ questID = 99001, name = "Nowhere Quest" }, {}, {}, {})
	T.check(row and not row.detail:find("^%s*·") and row.detail:find("only you", 1, true), "no level, no zone: \"" .. tostring(row and row.detail) .. "\"")
end
