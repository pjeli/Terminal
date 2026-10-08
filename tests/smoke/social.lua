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
	-- the newer roster's professions: the guild's club member info
	_G.C_Club = { GetGuildClubId = function() return 7 end, GetClubMembers = function() return { 1, 2 } end,
		GetMemberInfo = function(_, id)
			if id == 1 then return { name = "Boss", profession1Name = "Tailoring", profession2Name = "Enchanting" } end
			return { name = "Sleepy-Realm" }
		end }
	_G.C_FriendList = { GetNumFriends = function() return 2 end, GetFriendInfoByIndex = function(i)
		if i == 1 then return { name = "Buddy", level = 50, className = "Hunter", area = "Feralas", connected = true, notes = "" } end
		return { name = "Gone", level = 20, className = "Rogue", connected = false }
	end }
	_G.BNGetNumFriends = function() return 2 end
	_G.C_BattleNet = { GetFriendAccountInfo = function(i)
		if i == 1 then return { battleTag = "Pal#1234", note = "",
			gameAccountInfo = { isOnline = true, clientProgram = "App", richPresence = "In the app" } } end
		-- playing, their BattleTag not readable (a secret value comes through Str as nil): listed by their character
		return { bnetAccountID = 55, gameAccountInfo = { isOnline = true, clientProgram = "WoW", characterName = "Girl Bird",
			className = "Druid", areaName = "The Barrens", characterLevel = 18, gameAccountID = 99 } }
	end }
	ns.providers.guild._dirty, ns.providers.friends._dirty = true, true
	ns.db.easyMode = false; UI:EasyChanged()

	check(names(UI:Search("@guild priest online")) == "Mendy", "@guild priest online: the online priest: " .. names(UI:Search("@guild priest online")))
	check(names(UI:Search("@guild blacksmith")) == "Hammer", "@guild blacksmith: from the guild's profession list: " .. names(UI:Search("@guild blacksmith")))
	check(names(UI:Search("@guild tailoring")) == "Boss" and names(UI:Search("@guild enchanting")) == "Boss", "@guild tailoring: from the club roster's professions: " .. names(UI:Search("@guild tailoring")))
	check(ns.Social.profStats.list == 1 and ns.Social.profStats.club == 1 and ns.Social.profStats.members == 2, "the trace's counts: what each source gave")
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
	-- Enter whispers, Shift+Enter invites: lines the game runs
	local e = UI:Search("@guild mendy")[1]
	local w = e and S.Resolve(e.secure, e)
	check(w and w.macro and w.macro:find('f("Mendy-Realm")', 1, true) and #w.macro <= S.MACRO_MAX, "Enter: a whisper the game opens: " .. tostring(w and w.macro))
	local body = w and w.macro:match("^/run (.*)$")
	check(body and loadstring(body), "valid Lua")
	local told
	_G.ChatFrame_SendTell = function(n) told = n end
	if body then loadstring(body)() end
	check(told == "Mendy-Realm", "the whisper goes to the full name")
	_G.ChatFrame_SendTell = nil
	local inv = e and S.Resolve(e.secondarySecure, e)
	check(inv and inv.macro and inv.macro:find("InviteUnit", 1, true) and inv.macro:find('"Mendy-Realm"', 1, true), "Shift+Enter: an invite the game sends: " .. tostring(inv and inv.macro))
	-- friends: the friend list and Battle.net
	local fr = names(UI:Search("@friend online"))
	check(fr:find("Buddy", 1, true) and fr:find("Pal", 1, true) and not fr:find("Gone", 1, true), "@friend online: " .. fr)
	check(names(UI:Search("@friend hunter")) == "Buddy", "@friend hunter: " .. names(UI:Search("@friend hunter")))
	local pal = UI:Search("@friend pal")[1]
	local pw = pal and S.Resolve(pal.secure, pal)
	check(pw and pw.macro:find('battleTag=="Pal#1234"', 1, true) and #pw.macro <= S.MACRO_MAX, "a Battle.net friend outside the game: whispered by BattleTag: " .. tostring(pw and pw.macro))
	check(pw and loadstring(pw.macro:match("^/run (.*)$")), "valid Lua (Battle.net)")
	check(pal and pal.secondarySecure == nil, "no invite for someone not in the game")
	local girl = UI:Search("@friend girl")[1]
	check(girl and girl.name == "Girl Bird" and names(UI:Search("@friend druid")) == "Girl Bird", "a Battle.net friend playing, BattleTag unreadable: listed by their character: " .. tostring(girl and girl.name))
	local gw = girl and S.Resolve(girl.secure, girl)
	check(gw and gw.macro:find("GetAccountInfoByID(55)", 1, true) and loadstring(gw.macro:match("^/run (.*)$")), "whispered by their account id: " .. tostring(gw and gw.macro))
	local gi = girl and girl.secondarySecure and S.Resolve(girl.secondarySecure, girl)
	check(gi and gi.macro:find("BNInviteFriend(99)", 1, true) and loadstring(gi.macro:match("^/run (.*)$")), "invited through their game account: " .. tostring(gi and gi.macro))
	check(girl and girl.zone == "The Barrens" and names(UI:Search("@friend in:barrens")) == "Girl Bird", "in: works on them")
	-- Simple mode: a category of their own, and online as an everyday word
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("priest online")
	local found = false
	for _, r in ipairs(UI.Results()) do if r.catId == "people" or r.name == "Mendy" then found = true end end
	check(found, "Simple mode: priest online finds them under Guild & friends")
	UI:Hide(); FlushAll()

	_G.IsInGuild, _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.C_GuildInfo = save.ig, save.n, save.info, save.gi
	_G.GetNumGuildTradeSkill, _G.GetGuildTradeSkillInfo, _G.C_FriendList = save.nts, save.ts, save.fl
	_G.BNGetNumFriends, _G.C_BattleNet, _G.Ambiguate, _G.C_Club = save.bnn, save.bn, save.amb, save.club
	ns.db.easyMode = save.easy; UI:EasyChanged()
	ns.providers.guild._dirty, ns.providers.friends._dirty = true, true
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
	check(res[2] and res[2].detail:find("Night Watch", 1, true) and res[2].secure, "guild shown, whisper ready")
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
