-- Guild members and friends (Social.lua): @guild / @friend, searched by class, rank, zone, notes, professions;
-- is:online, in:, lvl:; Enter whispers and Shift+Enter invites from lines the game runs.
local T = ...
local ns, UI, S, check, key, FlushAll = T.ns, T.UI, T.S, T.check, T.key, T.FlushAll

local function names(res) local t = {} for _, e in ipairs(res) do t[#t + 1] = tostring(e.name) end return table.concat(t, ",") end

io.write("[guild and friends]\n")
do
	local save = { ig = _G.IsInGuild, n = _G.GetNumGuildMembers, info = _G.GetGuildRosterInfo, gi = _G.C_GuildInfo,
		nts = _G.GetNumGuildTradeSkill, ts = _G.GetGuildTradeSkillInfo, fl = _G.C_FriendList, bnn = _G.BNGetNumFriends,
		bn = _G.C_BattleNet, amb = _G.Ambiguate, club = _G.C_Club, easy = ns.db.easyMode }
	local asked = 0
	_G.C_GuildInfo = { GuildRoster = function() asked = asked + 1 end }
	_G.IsInGuild = function() return true end
	local ROSTER = {
		{ "Mendy-Realm", "Officer", 1, 60, "Priest", "Undercity", "healer, alchemy", "", true, 0, "PRIEST" },
		{ "Hammer-Realm", "Member", 3, 42, "Warrior", "Orgrimmar", "", "", true, 0, "WARRIOR" },
		{ "Sleepy-Realm", "Member", 3, 30, "Priest", "Undercity", "", "", false, 0, "PRIEST" },
		{ "Boss-Realm", "Guild Master", 0, 60, "Mage", "Stormwind City", "", "", true, 0, "MAGE" },
	}
	_G.GetNumGuildMembers = function() return #ROSTER, 3 end
	_G.GetGuildRosterInfo = function(i) local r = ROSTER[i] if r then return unpack(r) end end
	_G.GetNumGuildTradeSkill = function() return 3 end
	_G.GetGuildTradeSkillInfo = function(i)
		if i == 1 then return 164, false, nil, "Blacksmithing" end
		if i == 2 then return nil, nil, nil, nil, 1, 1, 1, "Hammer", "Hammer-Realm" end
		if i == 3 then return 171, false, nil, "Alchemy" end
	end
	_G.Ambiguate = function(n) return (n:gsub("%-Realm$", "")) end
	-- the newer roster's professions: the guild's club member info (when it has them, the older profession list isn't read)
	_G.C_Club = { GetGuildClubId = function() return 7 end, GetClubMembers = function() return { 1, 2, 3 } end,
		GetMemberInfo = function(_, id)
			if id == 1 then return { name = "Boss", profession1Name = "Tailoring", profession2Name = "Enchanting" } end
			if id == 3 then return { name = "Hammer-Realm", profession1ID = 164, profession1Name = "Blacksmithing" } end
			return { name = "Sleepy-Realm" }
		end }
	_G.C_FriendList = { GetNumFriends = function() return 2 end, GetFriendInfoByIndex = function(i)
		if i == 1 then return { name = "Buddy", level = 50, className = "Hunter", area = "Feralas", connected = true, notes = "" } end
		return { name = "Gone", level = 20, className = "Rogue", connected = false }
	end }
	_G.BNGetNumFriends = function() return 2 end
	ns.Social.ForgetCrafts()
	_G.C_BattleNet = { GetFriendAccountInfo = function(i)
		if i == 1 then return { battleTag = "Pal#1234", note = "", accountName = "|Kq1|k",
			gameAccountInfo = { isOnline = true, clientProgram = "App", richPresence = "In the app" } } end
		-- playing, their BattleTag not readable (a secret value comes through Str as nil): listed by their character
		return { bnetAccountID = 55, gameAccountInfo = { isOnline = true, clientProgram = "WoW", characterName = "Girl Bird",
			className = "Druid", areaName = "The Barrens", characterLevel = 18, gameAccountID = 99 } }
	end, GetAccountInfoByID = function(id) if id == 55 then return { accountName = "|Kq2|k" } end end }
	ns.providers.guild._dirty, ns.providers.friends._dirty = true, true
	ns.db.easyMode = false; UI:EasyChanged()

	check(names(UI:Search("@guild priest online")) == "Mendy", "@guild priest online: the online priest: " .. names(UI:Search("@guild priest online")))
	check(names(UI:Search("@guild blacksmith")) == "Hammer", "@guild blacksmith: from the club roster: " .. names(UI:Search("@guild blacksmith")))
	check(names(UI:Search("@guild tailoring")) == "Boss" and names(UI:Search("@guild enchanting")) == "Boss", "@guild tailoring: from the club roster's professions: " .. names(UI:Search("@guild tailoring")))
	check(ns.Social.profStats.list == 0 and ns.Social.profStats.club == 2 and ns.Social.profStats.members == 3,
		"the trace's counts: the club roster had them, the older list not read: " .. ns.Social.profStats.list .. " " .. ns.Social.profStats.club
		.. " " .. ns.Social.profStats.members)
	local alch = names(UI:Search("@guild alchemy"))
	check(alch:find("Mendy", 1, true), "@guild alchemy: from a public note too: " .. alch)
	local uc = names(UI:Search("@guild in:undercity"))
	check(uc:find("Mendy", 1, true) and uc:find("Sleepy", 1, true) and not uc:find("Hammer", 1, true), "@guild in:undercity: " .. uc)
	check(names(UI:Search("@guild officer")) == "Mendy", "@guild officer: by rank: " .. names(UI:Search("@guild officer")))
	check(names(UI:Search("@guild guild master")) == "Boss", "@guild guild master: " .. names(UI:Search("@guild guild master")))
	check(names(UI:Search("@guild lvl:40-50")) == "Hammer", "@guild lvl:40-50: " .. names(UI:Search("@guild lvl:40-50")))
	local off = names(UI:Search("@guild is:offline"))
	check(off == "Sleepy", "@guild is:offline: " .. off)
	check(asked >= 1, "the roster is asked for")
	-- not in plain searches (a guild's names would crowd every search)
	check(not names(UI:Search("mendy")):find("Mendy", 1, true), "only with @guild")
	-- Enter whispers, Shift+Enter invites: from Terminal's code (a whisper the game opened on Enter's own press
	-- closed again at once in the game; the chat box and invites aren't protected)
	local e = UI:Search("@guild mendy")[1]
	local told, bntold, invited, bninv
	local saved2 = { st = _G.ChatFrame_SendTell, sbn = _G.ChatFrame_SendBNetTell, pi = _G.C_PartyInfo, bni = _G.BNInviteFriend }
	_G.ChatFrame_SendTell = function(n) told = n end
	_G.ChatFrame_SendBNetTell = function(n) bntold = n end
	_G.C_PartyInfo = { InviteUnit = function(n) invited = n end }
	_G.BNInviteFriend = function(id) bninv = id end
	-- Enter: the game opens the whisper box a moment after the press (a timer in the /run line it runs): Terminal's own
	-- call tainted the chat box and later macros (panels, /who) stopped working
	local w = e and S.Resolve(e.secure, e)
	local body = w and w.macro and w.macro:match("^/run (.*)$")
	check(body and w.macro:find("C_Timer.After(.1,function()", 1, true) and #w.macro <= S.MACRO_MAX and loadstring(body), "Enter: a whisper the game opens a moment later: " .. tostring(w and w.macro))
	local timerWas = C_Timer.After
	local later
	C_Timer.After = function(_, fn) later = fn end
	if body then loadstring(body)() end
	C_Timer.After = timerWas
	check(told == nil and later, "not on the press itself")
	if later then later() end
	check(told == "Mendy-Realm", "then the whisper box to the full name: " .. tostring(told))
	told = nil
	e.activate(e) -- (in combat: Terminal's own)
	check(told == "Mendy-Realm", "the combat fallback whispers too")
	e.secondary(e)
	check(invited == "Mendy-Realm", "Shift+Enter invites the full name: " .. tostring(invited))
	-- friends: the friend list and Battle.net
	local fr = names(UI:Search("@friend online"))
	check(fr:find("Buddy", 1, true) and fr:find("Pal", 1, true) and not fr:find("Gone", 1, true), "@friend online: " .. fr)
	check(names(UI:Search("@friend hunter")) == "Buddy", "@friend hunter: " .. names(UI:Search("@friend hunter")))
	local pal = UI:Search("@friend pal")[1]
	pal.activate(pal)
	check(bntold == "|Kq1|k", "a Battle.net friend outside the game: whispered by BattleTag (account name): " .. tostring(bntold))
	local msgs = {}
	local po = ns.Print
	ns.Print = function(_, m) msgs[#msgs + 1] = m end
	invited = nil
	pal.secondary(pal)
	ns.Print = po
	check(invited == nil and msgs[1] and msgs[1]:find("isn't playing", 1, true), "no invite for someone not in the game")
	local girl = UI:Search("@friend girl")[1]
	check(girl and girl.name == "Girl Bird" and names(UI:Search("@friend druid")) == "Girl Bird", "a Battle.net friend playing, BattleTag unreadable: listed by their character: " .. tostring(girl and girl.name))
	bntold = nil
	girl.activate(girl)
	check(bntold == "|Kq2|k", "whispered by their account id: " .. tostring(bntold))
	girl.secondary(girl)
	check(bninv == 99, "invited through their game account: " .. tostring(bninv))
	_G.ChatFrame_SendTell, _G.ChatFrame_SendBNetTell, _G.C_PartyInfo, _G.BNInviteFriend = saved2.st, saved2.sbn, saved2.pi, saved2.bni
	check(girl and girl.zone == "The Barrens" and names(UI:Search("@friend in:barrens")) == "Girl Bird", "in: works on them")
	-- Simple mode: a category of their own, and online as an everyday word
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("priest online")
	local found = false
	for _, r in ipairs(UI.Results()) do if r.catId == "people" or r.name == "Mendy" then found = true end end
	check(found, "Simple mode: priest online finds them under Guild & friends")
	UI:Hide(); FlushAll()
	-- Shift+Right > Whisper (the menu from the keyboard): the game opens the whisper
	UI:Open("mendy")
	UI:Move(1) -- (past the /who ask row)
	local sel = UI.Results()[2]
	local F = _G.TerminalFrame
	_G.IsShiftKeyDown = function() return true end
	F.scripts.OnKeyDown(F, "RIGHT")
	_G.IsShiftKeyDown = function() return false end
	local m = _G.TerminalRowMenu
	local first = m and m.lines[1] and m.lines[1].fs:GetText()
	check(sel and sel.name == "Mendy" and m:IsShown() and first == "Whisper", "the menu on Mendy, Whisper first: " .. tostring(sel and sel.name) .. " / " .. tostring(first))
	S.Disarm()
	key("ENTER")
	local px = _G.TerminalMacroProxy
	check(F.propagate == true and S.armed == "MACRO" and px and tostring(px.attrs.macrotext):find("SendTell", 1, true)
		and tostring(px.attrs.macrotext):find("C_Timer", 1, true) and not m:IsShown(), "Enter on Whisper: the game opens the whisper a moment after the press: " .. tostring(px and px.attrs.macrotext))
	UI:Hide(); FlushAll()

	_G.IsInGuild, _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.C_GuildInfo = save.ig, save.n, save.info, save.gi
	_G.GetNumGuildTradeSkill, _G.GetGuildTradeSkillInfo, _G.C_FriendList = save.nts, save.ts, save.fl
	_G.BNGetNumFriends, _G.C_BattleNet, _G.Ambiguate, _G.C_Club = save.bnn, save.bn, save.amb, save.club
	ns.db.easyMode = save.easy; UI:EasyChanged()
	ns.providers.guild._dirty, ns.providers.friends._dirty = true, true
end

io.write("[guild professions: the club roster, and the older profession list when it says nothing]\n")
do
	local SO = ns.Social
	local save = { ig = _G.IsInGuild, n = _G.GetNumGuildMembers, info = _G.GetGuildRosterInfo, gi = _G.C_GuildInfo,
		nts = _G.GetNumGuildTradeSkill, ts = _G.GetGuildTradeSkillInfo, ex = _G.ExpandGuildTradeSkillHeader,
		co = _G.CollapseGuildTradeSkillHeader, gso = _G.GetGuildRosterShowOffline, sso = _G.SetGuildRosterShowOffline,
		qgr = _G.QueryGuildRecipes, amb = _G.Ambiguate, club = _G.C_Club, gt = _G.GetTime, gp = _G.GetProfessions,
		gpi = _G.GetProfessionInfo, easy = ns.db.easyMode }
	local clock = 1000
	_G.GetTime = function() return clock end
	_G.C_GuildInfo = { GuildRoster = function() end }
	_G.IsInGuild = function() return true end
	_G.Ambiguate = function(n) return (n:gsub("%-Realm$", "")) end
	_G.C_Club = nil
	_G.GetProfessions = function() return nil end
	local ROSTER = {
		{ "Hammer-Realm", "Member", 3, 60, "Warrior", "Orgrimmar", "", "", true, 0, "WARRIOR" },
		{ "Anvil-Realm", "Member", 3, 58, "Paladin", "Ironforge", "", "", false, 0, "PALADIN" },
	}
	_G.GetNumGuildMembers = function() return #ROSTER, 1 end
	_G.GetGuildRosterInfo = function(i) local r = ROSTER[i] if r then return unpack(r) end end
	-- the older list as WoW Forever sends it (seen in game): every header folded; members under a header only while it's
	-- open, and online ones only. The newer order: name, name with realm, class, online, zone, skill, class file, mobile, away
	local folded = { [164] = true, [186] = true }
	local LIST = {
		{ id = 164, name = "Blacksmithing", members = {
			{ "Hammer", "Hammer-Realm", "Warrior", true, "Orgrimmar", 265, "WARRIOR" },
			{ "Anvil", "Anvil-Realm", "Paladin", false, "Ironforge", 260, "PALADIN" } } },
		{ id = 186, name = "Mining", members = { { "Hammer", "Hammer-Realm", "Warrior", true, "Orgrimmar", 150, "WARRIOR" } } },
		{ id = 2933, name = "Test Profession [DNT]", members = { { "Hammer", "Hammer-Realm", "Warrior", true, "Orgrimmar", 1, "WARRIOR" } } },
	}
	local oldOrder = false -- (4.x's order: no name with realm, the skill 12th)
	local function ListRows()
		local out = {}
		for _, h in ipairs(LIST) do
			local online = 0
			for _, m in ipairs(h.members) do if m[4] then online = online + 1 end end
			out[#out + 1] = { h.id, folded[h.id] or false, 1, h.name, online, online, #h.members }
			if not folded[h.id] then
				for _, m in ipairs(h.members) do
					if m[4] then
						if oldOrder then out[#out + 1] = { h.id, nil, nil, nil, nil, nil, nil, m[1], m[3], m[4], m[5], m[6], m[7], false }
						else out[#out + 1] = { h.id, nil, nil, nil, nil, nil, nil, m[1], m[2], m[3], m[4], m[5], m[6], m[7], false, false } end
					end
				end
			end
		end
		return out
	end
	local expanded, asks, offlineAsked = {}, 0, false
	_G.GetNumGuildTradeSkill = function() return #ListRows() end
	_G.GetGuildTradeSkillInfo = function(i) local r = ListRows()[i] if r then return unpack(r, 1, 16) end end
	_G.ExpandGuildTradeSkillHeader = function(id) folded[id] = false; expanded[#expanded + 1] = id end
	_G.CollapseGuildTradeSkillHeader = function(id) folded[id] = true end
	_G.GetGuildRosterShowOffline = function() return false end
	_G.SetGuildRosterShowOffline = function() offlineAsked = true end -- (didn't apply to this list in game: no longer touched)
	_G.QueryGuildRecipes = function() asks = asks + 1 end
	SO.ForgetCrafts()
	ns.providers.guild._dirty = true
	ns.db.easyMode = false; UI:EasyChanged()

	-- no club roster professions: the older list, its folded headers opened for the read and folded back
	local c = SO.Crafts()
	check(c and c.profs[164] and #c.profs[164].members == 1 and c.members.hammer.skills[164] == 265 and c.members.hammer.skills[186] == 150,
		"the older list: its folded headers opened, the online members read with their skill: " .. tostring(c and c.profs[164] and #c.profs[164].members))
	check(folded[164] and folded[186] and #expanded == 2 and not offlineAsked, "folded again as they were; offline members not asked for")
	check(not c.profs[2933] and c.members.hammer.skills[2933] == nil, "\"Test Profession [DNT]\" isn't a profession")
	check(c.stats.headers == 3 and c.stats.opened == 2 and c.stats.listed == 3, "the counts for the trace: "
		.. c.stats.headers .. " " .. c.stats.opened .. " " .. c.stats.listed)
	check(asks == 1, "the server asked for the guild's professions once, as the guild window does: " .. asks)
	check(SO.Crafts() == c and #expanded == 2, "kept for a while: not read again at once")
	-- headers already open (another addon, say): read as they are, nothing opened or folded
	folded[164], folded[186] = false, false
	SO.ForgetCrafts()
	local open = SO.Crafts()
	check(#expanded == 2 and not folded[164] and open.members.hammer and open.members.hammer.skills[164] == 265, "headers already open: read as they are")
	folded[164], folded[186] = true, true
	SO.ForgetCrafts()
	c = SO.Crafts()
	-- should the game ever refuse opening the list (a blocked action): remembered, put back, read as it stands from then on
	do
		local D, realExpand, tries = ns.Debug, _G.ExpandGuildTradeSkillHeader, 0
		_G.ExpandGuildTradeSkillHeader = function() tries = tries + 1; D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", "Terminal", "UNKNOWN()") end
		ns.db.blockedCalls = nil
		SO.ForgetCrafts()
		local cb = SO.Crafts()
		check(tries == 2 and ns.db.blockedCalls and ns.db.blockedCalls.guildlist and folded[164] and folded[186] and cb.profs[164] == nil,
			"blocked: remembered, the list put back as it was: " .. tries)
		SO.ForgetCrafts()
		SO.Crafts()
		check(tries == 2, "not tried again: the list read as it stands")
		_G.ExpandGuildTradeSkillHeader = realExpand
		ns.db.blockedCalls = nil
		for i = #D.events, 1, -1 do D.events[i] = nil end
		SO.ForgetCrafts()
		c = SO.Crafts()
	end
	local res = UI:Search("@guild blacksmith")
	local hammer
	for _, r in ipairs(res) do if r.name == "Hammer" then hammer = r end end
	check(hammer and hammer.detail:find("Blacksmithing 265, Mining 150", 1, true), "a member's professions with their skill: " .. tostring(hammer and hammer.detail))
	-- the list's own events, fired by opening and folding it for the read, aren't changes; a later one is
	local F = SO.craftEvents
	ns.providers.guild._dirty = false
	F.scripts.OnEvent(F, "GUILD_TRADESKILL_UPDATE")
	check(SO.Crafts() == c and not ns.providers.guild._dirty, "an update right after the read (its own) changes nothing")
	clock = clock + 2
	F.scripts.OnEvent(F, "GUILD_TRADESKILL_UPDATE")
	check(ns.providers.guild._dirty and SO.Crafts() ~= c, "a later update: read again, the guild list rebuilt")
	-- 4.x's order of a member's values: the skill 12th, no realm name
	oldOrder = true
	SO.ForgetCrafts()
	c = SO.Crafts()
	check(c.members.hammer and c.members.hammer.skills[164] == 265 and c.members.hammer.online == true and c.members.hammer.zone == "Orgrimmar",
		"the older order of a member's values read too: " .. tostring(c.members.hammer and c.members.hammer.skills[164]))
	oldOrder = false

	-- the club roster (WoW Forever's: everyone, offline ones too): the older list isn't touched
	local CLUB = {
		{ name = "Hammer-Realm", presence = 1, zone = "Orgrimmar", guid = "Player-1-H", profession1ID = 164, profession1Name = "Blacksmithing",
			profession1Rank = 1, profession2ID = 186, profession2Name = "Mining", profession2Rank = 1 },
		{ name = "Anvil-Realm", presence = 3, guid = "Player-1-A", profession1ID = 164, profession1Name = "Blacksmithing", profession1Rank = 1 },
		{ name = "Plamen-Realm", presence = 1, guid = "Player-1-ME", isSelf = true, profession1ID = 186, profession1Name = "Mining", profession1Rank = 1 },
		{ name = "Nobody-Realm", presence = 3, guid = "Player-1-N" },
		{ name = "Skinny-Realm", presence = 1, profession1ID = 393, profession1Name = "Skinning", profession1Rank = 1,
			profession2Name = "Herbalism", profession2Rank = 1 },
	}
	_G.C_Club = { GetGuildClubId = function() return 7 end, GetClubMembers = function() local ids = {} for i in ipairs(CLUB) do ids[i] = i end return ids end,
		GetMemberInfo = function(_, i) return CLUB[i] end }
	-- your own Mining is 186 by the game, the guild says 1 (seen in game: every member's rank came as 1)
	_G.GetProfessions = function() return 1 end
	_G.GetProfessionInfo = function() return "Mining", 1, 186, 300, 2, 0, 186 end
	expanded = {}
	SO.ForgetCrafts()
	c = SO.Crafts()
	ROSTER[3] = { "Skinny-Realm", "Member", 3, 30, "Druid", "Ashenvale", "", "", true, 0, "DRUID" }
	check(#expanded == 0 and c.stats.club == 4 and c.stats.members == 5 and #c.profs[164].members == 2 and c.members.anvil.online == false
, "the club roster: everyone with a profession (offline ones too), the older list not opened")
	check(c.ranks == false and c.check and c.check.said == 1 and c.check.real == 186, "the guild's 1 for your Mining 186: its numbers aren't skill levels")
	ns.providers.guild._dirty = true
	res = UI:Search("@guild blacksmith")
	local list = names(res)
	hammer = nil
	for _, r in ipairs(res) do if r.name == "Hammer" then hammer = r end end
	check(names(UI:Search("@guild skinner")) == "Skinny" and names(UI:Search("@guild herbalists")) == "Skinny",
		"@guild skinner / herbalists: what the people are called: " .. names(UI:Search("@guild skinner")) .. " / " .. names(UI:Search("@guild herbalists")))
	check(list:find("Hammer", 1, true) and list:find("Anvil", 1, true) and hammer and hammer.detail:find("Blacksmithing, Mining", 1, true)
		and not hammer.detail:find("Blacksmithing 1", 1, true), "@guild blacksmith: both, the offline one too, and no made-up skill: "
		.. list .. " / " .. tostring(hammer and hammer.detail))
	-- Simple mode, in plain words: "guild blacksmith"
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("guild blacksmith"); FlushAll()
	local shown = {}
	for _, r in ipairs(UI.Results()) do shown[#shown + 1] = tostring(r.name) end
	shown = table.concat(shown, ",")
	check(shown:find("Hammer", 1, true) and shown:find("Anvil", 1, true), "Simple mode: guild blacksmith finds them: " .. shown)
	UI:Hide(); FlushAll()
	-- what the people are called, not only the profession's name: "skinner" isn't the start of "Skinning"
	for _, q in ipairs({ "guild miner", "guild miners", "guild blacksmiths" }) do
		UI:Open(q); FlushAll()
		shown = {}
		for _, r in ipairs(UI.Results()) do shown[#shown + 1] = tostring(r.name) end
		shown = table.concat(shown, ",")
		check(shown:find("Hammer", 1, true) and (q == "guild miner" or q == "guild miners" or shown:find("Anvil", 1, true))
			and not (q ~= "guild blacksmiths" and shown:find("Anvil", 1, true)), "Simple mode: " .. q .. ": " .. shown)
		UI:Hide(); FlushAll()
	end
	ns.db.easyMode = false; UI:EasyChanged()
	-- numbers that match yours (a few skill-ups behind at most) are skill levels; a 1 never is
	CLUB[3].profession1Rank = 180
	CLUB[1].profession1Rank = 265
	SO.ForgetCrafts()
	c = SO.Crafts()
	ns.providers.guild._dirty = true
	res = UI:Search("@guild blacksmith")
	hammer = nil
	for _, r in ipairs(res) do if r.name == "Hammer" then hammer = r end end
	check(c.ranks == true and hammer and hammer.detail:find("Blacksmithing 265, Mining", 1, true) and not hammer.detail:find("Mining 1", 1, true),
		"matching numbers are used (but never a 1): " .. tostring(hammer and hammer.detail))
	CLUB[3].profession1Rank, CLUB[1].profession1Rank = 1, 1
	_G.C_Club = nil

	-- nothing anywhere yet: the server asked, the loading ring until it answers (5 s), then asked again
	local LIST0 = LIST
	LIST = {}
	SO.ForgetCrafts()
	asks = 0
	SO.Crafts()
	check(asks == 1 and SO.CraftsWaiting() and ns.providers.guild.busy(ns.providers.guild), "nothing yet: asked, waiting: the loading ring")
	clock = clock + 2
	F.scripts.OnEvent(F, "GUILD_TRADESKILL_UPDATE") -- (an answer still holding nothing)
	SO.Crafts()
	check(asks == 1, "not asked again while waiting: " .. asks)
	clock = clock + 10
	check(not SO.CraftsWaiting() and not ns.providers.guild.busy(ns.providers.guild), "the wait is over")
	F.scripts.OnEvent(F, "GUILD_TRADESKILL_UPDATE")
	SO.Crafts()
	check(asks == 2, "still nothing: asked again: " .. asks)
	LIST = LIST0
	F.scripts.OnEvent(F, "GUILD_TRADESKILL_UPDATE")
	c = SO.Crafts()
	check(not SO.CraftsWaiting() and c.profs[164] and asks == 2, "the answer in: read, nothing asked")

	_G.IsInGuild, _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.C_GuildInfo = save.ig, save.n, save.info, save.gi
	_G.GetNumGuildTradeSkill, _G.GetGuildTradeSkillInfo, _G.ExpandGuildTradeSkillHeader = save.nts, save.ts, save.ex
	_G.CollapseGuildTradeSkillHeader, _G.GetGuildRosterShowOffline, _G.SetGuildRosterShowOffline = save.co, save.gso, save.sso
	_G.QueryGuildRecipes, _G.Ambiguate, _G.C_Club, _G.GetTime = save.qgr, save.amb, save.club, save.gt
	_G.GetProfessions, _G.GetProfessionInfo = save.gp, save.gpi
	ns.db.easyMode = save.easy; UI:EasyChanged()
	SO.ForgetCrafts()
	ns.providers.guild._dirty = true
end

io.write("[who]\n")
do
	local save = { fl = _G.C_FriendList, easy = ns.db.easyMode }
	local RESULTS = {}
	local toUi
	_G.C_FriendList = {
		GetNumWhoResults = function() return #RESULTS end,
		GetWhoInfo = function(i) return RESULTS[i] end,
		SetWhoToUi = function(v) toUi = v end,
		SendWho = function() end,
		GetNumFriends = function() return 0 end,
	}
	ns.providers.who._dirty = true
	ns.db.easyMode = false; UI:EasyChanged()
	-- the words become the /who text
	check(ns.Social.WhoFilter("@who priest lvl:50-60 in:undercity is:online") == 'priest 50-60 z-"undercity"', "the /who text: " .. ns.Social.WhoFilter("@who priest lvl:50-60 in:undercity is:online"))
	check(ns.Social.WhoFilter("who orc warrior") == "orc warrior", "Simple mode's action word left out")
	-- before any answer: the row that asks, pressed by the game, the terminal staying open
	UI:Open("@who priest undercity")
	local r = UI.Results()
	local ask = r[1]
	check(ask and ask.whoFilter == "priest undercity" and ask.staysOpen, "on top: ask the server: " .. tostring(ask and ask.name))
	check(ask and type(ask.isOpen) == "function" and ask.isOpen(ask) == false, "the ask row is never 'already open' (always pressed)")
	local m = ask and S.Resolve(ask.secure, ask)
	check(m and m.macro:find('SendWho("priest undercity",1)', 1, true) and loadstring(m.macro:match("^/run (.*)$")), "the game runs SendWho: " .. tostring(m and m.macro))
	-- pressed: the terminal stays, the ring says it's asking
	S.armed = "MACRO"; UI.armedEntry = ask
	UI:FinishSecure()
	FlushAll()
	check(UI:IsShown(), "the terminal stays open after the press")
	check(ns.providers.who.busy(ns.providers.who) ~= nil, "waiting for the answer")
	-- the answer: rows to search, whisper and invite; who-to-UI put back
	RESULTS[1] = { fullName = "Sana-Realm", fullGuildName = "Night Watch", level = 58, raceStr = "Undead", classStr = "Priest", area = "Undercity", filename = "PRIEST" }
	RESULTS[2] = { fullName = "Grim-Realm", level = 40, raceStr = "Orc", classStr = "Warrior", area = "Orgrimmar", filename = "WARRIOR" }
	toUi = true
	ns.Social.who.asked = nil -- (the mock's answer isn't what was asked: searched by its own words here)
	ns.providers.who._dirty = true
	local rows = ns:GetEntries(ns.providers.who)
	check(#rows == 2 and toUi == false and not ns.providers.who.busy(ns.providers.who), "answer in: two rows, chat gets /who again, done waiting")
	local res = UI:Search("@who priest")
	check(res[1] and res[1].whoFilter and res[2] and res[2].name:find("^Sana") and not res[3], "the answer searched: " .. tostring(res[2] and res[2].name))
	check(res[2] and res[2].detail:find("Night Watch", 1, true) and res[2].activate == ns.Social.Whisper, "guild shown, whisper ready")
	res = UI:Search("@who lvl:30-45")
	check(res[2] and res[2].name:find("^Grim") and not res[3], "lvl: on the answer")
	-- what the server understood (a level range) lists them too: they answered that /who
	ns.Social.who.asked = "priest 50-60"
	ns.providers.who._dirty = true
	res = UI:Search("@who priest 50-60")
	check(#res == 3, "the search that asked lists its whole answer, \"50-60\" too: " .. #res)
	UI:Hide(); FlushAll()
	-- Simple mode: "who priest"
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("who priest")
	res = UI.Results()
	check(res[1] and res[1].whoFilter == "priest", "Simple mode: who priest asks the server: " .. tostring(res[1] and res[1].name))
	UI:Hide(); FlushAll()
	_G.C_FriendList = save.fl
	ns.db.easyMode = save.easy; UI:EasyChanged()
	ns.providers.who._dirty = true
end

io.write("[chat box macro]\n")
do
	local text = 'say "hi" \\o/ |Hitem:1|h[x]|h'
	local m = ns.ChatBoxMacro(text)
	check(m and not m:find("|", 1, true), "no raw | in the macro (\\124 instead): " .. tostring(m))
	local got
	local oc, il, ta = _G.ChatFrame_OpenChat, _G.ChatEdit_InsertLink, C_Timer.After
	_G.ChatFrame_OpenChat = function(t) got = t end
	_G.ChatEdit_InsertLink = function() return false end
	C_Timer.After = function(_, f) f() end
	local fn = m and loadstring(m:match("^/run (.*)$"))
	if fn then fn() end
	check(got == text, "the chat box gets the text exactly: " .. tostring(got))
	local inserted
	_G.ChatEdit_InsertLink = function(t) inserted = t return true end
	got = nil
	if fn then fn() end
	check(inserted == text and got == nil, "a box already open: into what's being typed")
	_G.ChatFrame_OpenChat, _G.ChatEdit_InsertLink, C_Timer.After = oc, il, ta
	check(ns.ChatBoxMacro(string.rep("x", 300)) == nil and ns.ChatBoxMacro("") == nil, "too long or nothing: no macro")
end
