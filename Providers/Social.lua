local ns = select(2, ...)

-- Your guild and your friends (@guild, @friend): "@guild priest online", "@guild blacksmith", "@guild in:undercity",
-- "@guild officer", "@friend online". Each person's row is searchable by name, class, rank, zone, notes and (where the
-- game says) professions; lvl: and in: work on them, is:online / is:offline too. Enter opens a whisper to them, Shift+Enter
-- invites them, both from a line the game runs (the chat box and the party are the game's, never written from here).

local SO = {}
ns.Social = SO

local Safe, Str, Num = ns.Safe, ns.Str, ns.Num

local OFFLINE_HEX = "|cff808080"

local function ClassHex(class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not c then return nil end
	if c.colorStr then return "|c" .. c.colorStr end
	return ("|cff%02x%02x%02x"):format(math.floor((c.r or 1) * 255), math.floor((c.g or 1) * 255), math.floor((c.b or 1) * 255))
end

--- A name as chat shows it: the realm dropped when it's yours (the game's Ambiguate, a pure helper).
local function Short(full)
	if type(Ambiguate) == "function" then
		local s = Str(Safe(Ambiguate, full, "none"))
		if s then return s end
	end
	return full
end

-- a name as a Lua string inside a /run line (quotes and backslashes escaped; "|" doubled, or chat reads a code)
local function Quoted(s) return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("|", "||") .. '"' end

--- Enter: a whisper to them, opened by the game (a /run line on the secure macro button).
function SO.WhisperMacro(e)
	-- a Battle.net friend: a Battle.net whisper (it reaches them on any realm, under any name), by account id, else by
	-- BattleTag; their account name is an escape, read when pressed, never put in the text
	if e.bnetID then
		return "/run local a=C_BattleNet.GetAccountInfoByID(" .. e.bnetID .. ") local f=ChatFrame_SendBNetTell or ChatFrameUtil.SendBNetTell"
			.. " if a and f then f(a.accountName) end"
	end
	if e.bnetTag then
		return "/run for i=1,BNGetNumFriends() do local a=C_BattleNet.GetFriendAccountInfo(i) if a and a.battleTag=="
			.. Quoted(e.bnetTag) .. " then (ChatFrame_SendBNetTell or ChatFrameUtil.SendBNetTell)(a.accountName) end end"
	end
	return "/run local f=ChatFrame_SendTell or ChatFrameUtil and ChatFrameUtil.SendTell if f then f(" .. Quoted(e.whisperTo or e.name) .. ") end"
end
--- Shift+Enter: invite them to your group (the party is the game's: a /run line it runs).
function SO.InviteMacro(e)
	if e.bnetGame then
		-- (their game account, as the friend list's own invite does; by name when the client has no such call)
		return "/run if BNInviteFriend then BNInviteFriend(" .. e.bnetGame .. ") else C_PartyInfo.InviteUnit(" .. Quoted(e.whisperTo or e.name) .. ") end"
	end
	return "/run local f=C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit if f then f(" .. Quoted(e.whisperTo or e.name) .. ") end"
end
local WHISPER = { macro = SO.WhisperMacro }
local INVITE = { macro = SO.InviteMacro }
local function Never() return false end
local function NoPress(e) ns:Print("Can't whisper " .. tostring(e.name) .. " from here right now.") end
local function NoInvite(e)
	if not e.whisperTo then ns:Print(tostring(e.name) .. " isn't playing World of Warcraft right now.") return end
	ns:Print("Can't invite " .. tostring(e.name) .. " from here right now.")
end

local function Row(t)
	t.secure, t.isOpen, t.activate = WHISPER, Never, NoPress
	t.secondary, t.secondarySecure, t.secondaryIsOpen = NoInvite, (t.whisperTo or t.bnetGame) and INVITE or nil, Never
	return t
end

--- "Lv 60 Priest  Officer  Undercity" / "offline  Lv 60 Priest  Officer".
local function Detail(level, class, extra, zone, online)
	local parts = {}
	if not online then parts[#parts + 1] = "offline" end
	local who = {}
	if level and level > 0 then who[#who + 1] = "Lv " .. level end
	if class then who[#who + 1] = class end
	if #who > 0 then parts[#parts + 1] = table.concat(who, " ") end
	if extra then parts[#parts + 1] = extra end
	if online and zone then parts[#parts + 1] = zone end
	return table.concat(parts, "  ")
end

----------------------------------------------------------------------
-- Guild
----------------------------------------------------------------------

local lastAsk = 0
local function AskRoster()
	-- (the server answers with GUILD_ROSTER_UPDATE; it throttles asks itself, ours at most every 10 s)
	if GetTime() - lastAsk < 10 then return end
	lastAsk = GetTime()
	local ask = C_GuildInfo and C_GuildInfo.GuildRoster or _G.GuildRoster
	if ask then Safe(ask) end
end

--- Who has which profession, as far as the game tells: name -> { "Blacksmithing", ... }. Two places: the guild's
--- profession list (GetGuildTradeSkillInfo: header rows name the profession, member rows follow) and the guild's
--- club roster (C_Club member info: profession1Name, profession2Name), which the newer roster uses. A server may send
--- neither (classic servers never had them): then only notes say. The counts go to the trace.
local profStats = { list = 0, club = 0, members = 0 }
SO.profStats = profStats
local function AddProf(out, who, prof)
	if not (who and prof) then return end
	local t = out[who]
	if not t then t = {}; out[who] = t end
	for _, p in ipairs(t) do if p == prof then return end end
	t[#t + 1] = prof
end
local function GuildProfessions()
	local out = {}
	profStats.list, profStats.club, profStats.members = 0, 0, 0
	local n = Num(Safe(_G.GetNumGuildTradeSkill))
	local current
	for i = 1, n or 0 do
		local _, _, _, header, _, _, _, player, playerFull = Safe(_G.GetGuildTradeSkillInfo, i)
		header, player, playerFull = Str(header), Str(player), Str(playerFull)
		if header then
			current = header
		elseif current and (playerFull or player) then
			AddProf(out, playerFull or player, current)
			profStats.list = profStats.list + 1
		end
	end
	local C = C_Club
	local club = C and C.GetGuildClubId and Safe(C.GetGuildClubId)
	local ids = club and C.GetClubMembers and Safe(C.GetClubMembers, club)
	if type(ids) == "table" then
		for _, id in ipairs(ids) do
			local m = Safe(C.GetMemberInfo, club, id)
			if type(m) == "table" then
				profStats.members = profStats.members + 1
				local who = Str(m.name)
				local p1, p2 = Str(m.profession1Name), Str(m.profession2Name)
				if who and (p1 or p2) then
					AddProf(out, who, p1); AddProf(out, who, p2)
					profStats.club = profStats.club + 1
				end
			end
		end
	end
	return out
end

function SO.GuildRows()
	local out = {}
	if not (_G.IsInGuild and Safe(IsInGuild)) then return out end
	AskRoster()
	local n = Num(Safe(GetNumGuildMembers)) or 0
	local profs = GuildProfessions()
	for i = 1, n do
		local name, rank, rankIndex, level, classShown, zone, note, officerNote, online, _, class = Safe(GetGuildRosterInfo, i)
		name = Str(name)
		if name then
			rank, classShown, zone, note, officerNote = Str(rank), Str(classShown), Str(zone), Str(note), Str(officerNote)
			level, online = Num(level), online and true or false
			local shown = Short(name)
			local p = profs[name] or profs[shown]
			-- (any of these can be missing: nil holes, so walked by count, not ipairs)
			local words = { "guild member", classShown, rank, zone, note, officerNote, online and "online" or "offline" }
			local text = {}
			for k = 1, 7 do local w = words[k]; if w and w ~= "" then text[#text + 1] = w end end
			if p then for _, x in ipairs(p) do text[#text + 1] = x end end
			out[#out + 1] = Row({
				key = name, name = shown, whisperTo = name, level = level, zone = zone, online = online,
				class = Str(class), rank = rank, rankIndex = Num(rankIndex), note = note,
				detail = Detail(level, classShown, rank, zone, online) .. (p and ("  " .. table.concat(p, ", ")) or ""),
				color = online and ClassHex(Str(class)) or OFFLINE_HEX,
				icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
				text = table.concat(text, " "),
			})
		end
	end
	-- online first, then by name (searches sort by score; this is the order with nothing typed)
	table.sort(out, function(a, b)
		if a.online ~= b.online then return a.online end
		return a.name < b.name
	end)
	ns:Trace(("guild: %d members read; professions: %d from the guild's profession list, %d of %d from the club roster")
		:format(#out, profStats.list, profStats.club, profStats.members))
	return out
end

ns:RegisterProvider("guild", {
	label = "Guild",
	color = "ff34d080",
	aliases = { "guild", "guildies", "guildmates", "gmember" },
	explicit = true, -- (only with @guild, or Simple mode's People: a guild's names would crowd every search)
	lazy = true,
	events = { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "GUILD_TRADESKILL_UPDATE" },
	guard = 2,
	collect = function() return SO.GuildRows() end,
})

----------------------------------------------------------------------
-- Friends (the game's friend list and Battle.net friends)
----------------------------------------------------------------------

function SO.FriendRows()
	local out, seen = {}, {}
	local FL = C_FriendList
	local n = FL and FL.GetNumFriends and Num(Safe(FL.GetNumFriends)) or 0
	for i = 1, n do
		local f = Safe(FL.GetFriendInfoByIndex, i)
		local name = type(f) == "table" and Str(f.name)
		if name then
			local online = f.connected and true or false
			local level, class, zone, note = Num(f.level), Str(f.className), Str(f.area), Str(f.notes)
			seen[name] = true
			out[#out + 1] = Row({
				key = name, name = Short(name), whisperTo = name, level = level, zone = zone, online = online, note = note,
				detail = Detail(level, class, nil, zone, online), color = online and nil or OFFLINE_HEX,
				icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
				text = table.concat({ "friend", class or "", zone or "", note or "", online and "online" or "offline" }, " "),
			})
		end
	end
	-- Battle.net friends. Their BattleTag, account name or character may come as secret values here (Str gives nil):
	-- a friend is listed with whatever is readable (playing: their character, "Girl Bird"), and whispered by their
	-- account id, which the /run line turns into the account name when pressed (that name is an escape, never in text)
	local BN = C_BattleNet
	local bn = Num(Safe(_G.BNGetNumFriends)) or 0
	local listed, playing = 0, 0
	for i = 1, bn do
		local a = BN and BN.GetFriendAccountInfo and Safe(BN.GetFriendAccountInfo, i)
		if type(a) == "table" then
			local tag, acct = Str(a.battleTag), Num(a.bnetAccountID)
			local g = type(a.gameAccountInfo) == "table" and a.gameAccountInfo or {}
			local online = (g.isOnline or a.isOnline) and true or false
			local charName = g.isOnline and Str(g.characterName) or nil
			local realm = charName and Str(g.realmName)
			local char = charName and (realm and (charName .. "-" .. realm:gsub("%s", "")) or charName)
			if (tag or charName or acct) and not (char and (seen[char] or seen[charName])) then
				local level, class, zone, note = Num(g.characterLevel), Str(g.className), Str(g.areaName), Str(a.note)
				local who = tag and (tag:gsub("#%d+$", "")) or nil
				local name = charName and (who and (charName .. " (" .. who .. ")") or charName) or who or ("Battle.net friend " .. i)
				listed = listed + 1
				if charName then playing = playing + 1 end
				out[#out + 1] = Row({
					key = "bn:" .. (tag or acct or i), name = name, bnetTag = tag, bnetID = acct, bnetGame = charName and Num(g.gameAccountID) or nil,
					whisperTo = char or nil, level = charName and level or nil, zone = charName and zone or nil, online = online, note = note,
					detail = Detail(charName and level, charName and class, not charName and (online and Str(g.richPresence) or "Battle.net") or nil, zone, online),
					color = online and nil or OFFLINE_HEX,
					icon = "Interface\\FriendsFrame\\Battlenet-Portrait",
					text = table.concat({ "friend battle.net bnet", tag or "", charName or "", class or "", zone or "", note or "", online and "online" or "offline" }, " "),
				})
			end
		end
	end
	ns:Trace(("friends: %d on the friend list, %d of %d Battle.net friends listed (%d playing)"):format(n, listed, bn, playing))
	table.sort(out, function(x, y)
		if x.online ~= y.online then return x.online end
		return x.name < y.name
	end)
	return out
end

ns:RegisterProvider("friends", {
	label = "Friend",
	color = "ff4890f8",
	aliases = { "friend", "friends", "bnet" },
	explicit = true,
	lazy = true,
	events = { "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE" },
	guard = 2,
	collect = function() return SO.FriendRows() end,
})
