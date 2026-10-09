local ns = select(2, ...)

-- Your guild and your friends (@guild, @friend): "@guild priest online", "@guild blacksmith", "@guild in:undercity",
-- "@guild officer", "@friend online". Each person's row is searchable by name, class, rank, zone, notes and (where the
-- game says) professions; lvl: and in: work on them, is:online / is:offline too. Enter opens a whisper
-- to them, pressed by the game (WHISPER: a /run line that opens the chat box a moment after the press,
-- SO.WhisperMacro; from Terminal's code only in combat, SO.Whisper). Shift+Enter invites them (Terminal's code: the
-- invite isn't protected).

local SO = {}
ns.Social = SO

local Safe, Str, Num = ns.Safe, ns.Str, ns.Num

local OFFLINE_HEX = "|cff808080"

local ClassHex = ns.ClassHex

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

local Never = ns.Never

--- A Battle.net friend's account name (an escape the chat box reads; never put in macro text), by id, else BattleTag.
local function AccountName(e)
	local B = C_BattleNet
	if not B then return nil end
	if e.bnetID and B.GetAccountInfoByID then
		local a = Safe(B.GetAccountInfoByID, e.bnetID)
		if type(a) == "table" and a.accountName then return a.accountName end
	end
	if e.bnetTag and B.GetFriendAccountInfo and BNGetNumFriends then
		for i = 1, (Num(Safe(BNGetNumFriends)) or 0) do
			local a = Safe(B.GetFriendAccountInfo, i)
			if type(a) == "table" and a.battleTag == e.bnetTag and a.accountName then return a.accountName end
		end
	end
end

--- The whisper box from Terminal's code: only where nothing can be pressed (combat).
function SO.Whisper(e)
	local bn = (e.bnetID or e.bnetTag) and AccountName(e)
	local sendBN = ChatFrame_SendBNetTell or (ChatFrameUtil and ChatFrameUtil.SendBNetTell)
	if bn and sendBN then
		ns:Trace("social: Battle.net whisper to " .. tostring(e.name))
		sendBN(bn)
		return
	end
	local who = e.whisperTo or (not e.bnetID and not e.bnetTag and e.name)
	if not who then ns:Print("Can't whisper " .. tostring(e.name) .. " from here right now.") return end
	local tell = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
	ns:Trace("social: whisper to " .. tostring(who))
	if tell then tell(who) else ns.LinkInChat("/w " .. who .. " ") end
end

--- Shift+Enter: invite them to your group (C calls, no window touched).
function SO.Invite(e)
	if e.bnetGame and BNInviteFriend then
		ns:Trace("social: Battle.net invite to " .. tostring(e.name))
		BNInviteFriend(e.bnetGame)
		return
	end
	if not e.whisperTo then ns:Print(tostring(e.name) .. " isn't playing World of Warcraft right now.") return end
	local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
	if not invite then ns:Print("Can't invite " .. tostring(e.name) .. " from here right now.") return end
	ns:Trace("social: invite " .. tostring(e.whisperTo))
	invite(e.whisperTo)
end

--- Enter: the whisper box, opened by the game (a /run line on the secure button), a moment after the press so the
--- Enter that pressed it is over. (Terminal's own call would run the chat box's Blizzard Lua tainted.)
function SO.WhisperMacro(e)
	local open
	if e.bnetID then
		open = "local a=C_BattleNet.GetAccountInfoByID(" .. e.bnetID .. ") local f=ChatFrame_SendBNetTell or ChatFrameUtil.SendBNetTell"
			.. " if a and f then f(a.accountName) end"
	elseif e.bnetTag then
		open = "for i=1,BNGetNumFriends() do local a=C_BattleNet.GetFriendAccountInfo(i) if a and a.battleTag=="
			.. Quoted(e.bnetTag) .. " then (ChatFrame_SendBNetTell or ChatFrameUtil.SendBNetTell)(a.accountName) end end"
	elseif e.whisperTo or e.name then
		open = "(ChatFrame_SendTell or ChatFrameUtil.SendTell)(" .. Quoted(e.whisperTo or e.name) .. ")"
	else
		return nil
	end
	return "/run C_Timer.After(.1,function() " .. open .. " end)"
end
local WHISPER = { macro = SO.WhisperMacro }

local function Row(t)
	t.secure, t.isOpen = WHISPER, Never
	t.activate, t.secondary = SO.Whisper, SO.Invite -- (Enter in combat, when nothing can be pressed: Terminal's own)
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

----------------------------------------------------------------------
-- Guild professions: who has which ("@guild blacksmith")
--
-- What the game says: the guild's club roster (C_Club member info: profession1ID/Name/Rank, profession2..., what the
-- newer roster window reads; on WoW Forever 31 of 32 members had them, offline ones too, seen in game 0.45.3) and, only
-- when that says nothing, the guild's profession list (GetGuildTradeSkillInfo: a header row per profession, members
-- under an open one; on Forever every header comes folded and it lists online members only: opened for the read and
-- folded back). Skill numbers are shown only when they're real: the guild's number for your own profession is checked
-- against the game's (on Forever every member's rank came as 1, your Mining 186 included), and a 1 never counts.
-- Kept CRAFTS_FRESH seconds. The server is asked for the guild's professions (QueryGuildRecipes, as the guild window
-- asks when it opens) on the first read, when nothing has them, and ASK_AGAIN after the last ask.
-- (0.45.3-0.45.4 also listed "who can craft <recipe>" from this: dropped, the player's call. The server never says who
-- learned a recipe (QueryGuildMembersForRecipe goes unanswered on Forever), and guildies listed under "who can craft"
-- read as if they knew it.)
----------------------------------------------------------------------

SO.CRAFTS_FRESH = 30
SO.ASK_AGAIN = 600 -- (s between asks for the guild's professions)
SO.ASK_WAIT = 5 -- (s the loading ring waits for them)
SO.RANK_SLACK = 10 -- (the guild's number for your profession may lag the game's by a few skill-ups)
SO.TRADE_ICON = "Interface\\Icons\\INV_Shirt_GuildTabard_01"

-- { at, stale, members = { [key] = { name, full, class, online, zone, skills = { [prof] = rank } } },
--   profs = { [prof] = { id, name, members = { member... } } }, selfSaid = { [skill line] = the guild's number for your
--   own profession }, ranks (false: its numbers aren't skill levels), check, stats }; prof = the skill line (else the
--   lowercase name)
local crafts
local readUntil = 0 -- (the list's own events until then: fired by opening and folding it for the read)
local askedAt -- (when the server was last asked for the guild's professions)

--- The key a member is matched by in every list: the name as chat shows it, lowercase.
local function CraftKey(name) return ns.Lower(Short(name)) end
SO.CraftKey = CraftKey

local function InGuild() return (_G.IsInGuild and Safe(IsInGuild)) and true or false end

-- one member as the guild's lists know them (made once, filled in by each list)
local function Member(c, who, seen)
	local key = CraftKey(who)
	local m = c.members[key]
	if not m then m = { name = Short(who), full = who, skills = {} }; c.members[key] = m end
	if seen then
		if m.online == nil then m.online = seen.online end
		m.class, m.zone = m.class or seen.class, m.zone or seen.zone
	end
	return m
end

-- a member's number in one profession (the highest a list says)
local function AddSkill(c, m, id, prof, rank)
	if not (id or prof) or (prof and prof:find("[DNT]", 1, true)) then return end -- ("Test Profession [DNT]")
	local pk = id or ns.Lower(prof)
	local p = c.profs[pk]
	if not p then p = { id = id, members = {} }; c.profs[pk] = p end
	p.name = p.name or prof
	if m.skills[pk] == nil then p.members[#p.members + 1] = m end
	m.skills[pk] = math.max(m.skills[pk] or 0, rank or 0)
end

-- one row of the guild's profession list: a header ({ header = name, id, folded, players }) or a member under the one
-- above ({ name, full, online, zone, skill, class }). A member's values come in two orders: a newer client gives the
-- name with its realm 9th (skill 13th), 4.x didn't (skill 12th); where the skill, a number, sits tells them apart
local function ListRow(i)
	local r = { Safe(_G.GetGuildTradeSkillInfo, i) }
	local header = Str(r[4])
	if header then return { header = header, id = Num(r[1]), folded = r[2] and true or false, players = Num(r[7]) or 0 } end
	local name = Str(r[8])
	if not name then return nil end
	if type(r[13]) == "number" then
		return { name = name, full = Str(r[9]), online = r[11] and true or false, zone = Str(r[12]), skill = Num(r[13]), class = Str(r[14]) }
	elseif type(r[12]) == "number" then
		return { name = name, online = r[10] and true or false, zone = Str(r[11]), skill = Num(r[12]), class = Str(r[13]) }
	end
	return { name = name, full = Str(r[9]) }
end

local function ReadList(c)
	local count = _G.GetNumGuildTradeSkill
	if type(count) ~= "function" or type(_G.GetGuildTradeSkillInfo) ~= "function" then return end
	local st, folded = c.stats, {}
	for i = 1, Num(Safe(count)) or 0 do
		local row = ListRow(i)
		if row and row.header then
			st.headers, st.players = st.headers + 1, st.players + row.players
			if row.folded and row.id then folded[#folded + 1] = row.id end
		end
	end
	if st.headers == 0 then return end
	local function Read()
		st.listed = 0
		local id, prof
		for i = 1, Num(Safe(count)) or 0 do
			local row = ListRow(i)
			if row and row.header then
				id, prof = row.id, row.header
			elseif row and (id or prof) then
				st.listed = st.listed + 1
				AddSkill(c, Member(c, row.full or row.name, row), id, prof, row.skill)
			end
		end
	end
	local expand, collapse = _G.ExpandGuildTradeSkillHeader, _G.CollapseGuildTradeSkillHeader
	if type(expand) ~= "function" or type(collapse) ~= "function" then folded = {} end
	readUntil = GetTime() + 1
	-- (as a call the game might block: tried once, and a block is remembered; then the list is read as it stands)
	local opened = {}
	local read = #folded > 0 and ns.Guarded("guildlist", function()
		for _, id in ipairs(folded) do expand(id); opened[#opened + 1] = id end
		Read()
	end)
	-- (folded back as it was, whatever happened: last opened first)
	for k = #opened, 1, -1 do Safe(collapse, opened[k]) end
	if not read then Read() end
	st.opened = #opened
end

-- Enum.ClubMemberPresence: Online 1, Away 4, Busy 5 are in the game (OnlineMobile 2 is the app)
local PRESENT = { [1] = true, [4] = true, [5] = true }
local function ClassFile(classID)
	if not classID then return nil end
	local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and Safe(C_CreatureInfo.GetClassInfo, classID)
	if type(info) == "table" then return Str(info.classFile) end
	local _, file = Safe(_G.GetClassInfo, classID)
	return Str(file)
end

local function ReadClub(c)
	local C = C_Club
	local club = C and C.GetGuildClubId and Safe(C.GetGuildClubId)
	local ids = club and C.GetClubMembers and Safe(C.GetClubMembers, club)
	if type(ids) ~= "table" then return end
	local st = c.stats
	for _, mid in ipairs(ids) do
		local info = Safe(C.GetMemberInfo, club, mid)
		local who = type(info) == "table" and Str(info.name)
		if who then
			st.members = st.members + 1
			local m = Member(c, who, { online = PRESENT[Num(info.presence)] or false, zone = Str(info.zone),
				class = ClassFile(Num(info.classID)) })
			local any = false
			for k = 1, 2 do
				local id, prof = Num(info["profession" .. k .. "ID"]), Str(info["profession" .. k .. "Name"])
				if id or prof then
					local rank = Num(info["profession" .. k .. "Rank"])
					AddSkill(c, m, id, prof, rank)
					if info.isSelf and id and rank then c.selfSaid[id] = rank end
					any = true
				end
			end
			if any then st.club = st.club + 1 end
		end
	end
end

-- The guild's numbers checked against the one member whose skill the game tells: you. A number off from yours by more
-- than RANK_SLACK: they aren't skill levels (c.ranks = false: none shown or used); matching: c.ranks = true.
local function CheckRanks(c)
	local P = ns.Professions
	local mine = P and P.PlayerProfessions and (P.PlayerProfessions()) or {}
	for _, pr in ipairs(mine) do
		local said = pr.skillLine and c.selfSaid[pr.skillLine]
		if said and (pr.rank or 0) > 0 then
			c.check = { name = pr.name, said = said, real = pr.rank }
			if math.abs(said - pr.rank) > SO.RANK_SLACK then c.ranks = false return end
			c.ranks = true
		end
	end
end

--- A member's number in a profession when it's a skill level (else 0): never a 1, never when yours didn't match.
local function RealRank(c, rank)
	return (c.ranks ~= false and rank and rank > 1) and rank or 0
end

--- What the game says of your guild's crafting (see above), read again once it's CRAFTS_FRESH old or a list changed.
--- Not in a guild: nil.
function SO.Crafts()
	if not InGuild() then return nil end
	local now = GetTime()
	if crafts and not crafts.stale and now - crafts.at < SO.CRAFTS_FRESH then return crafts end
	local c = { at = now, members = {}, profs = {}, selfSaid = {},
		stats = { headers = 0, players = 0, opened = 0, listed = 0, members = 0, club = 0 } }
	ReadClub(c)
	local st = c.stats
	if st.club == 0 then ReadList(c) end -- (the club roster says nothing: the older list, online members only)
	CheckRanks(c)
	local ask = _G.QueryGuildRecipes
	if type(ask) == "function" and (not askedAt or (st.club == 0 and st.headers == 0 and now - askedAt >= SO.ASK_WAIT)
		or now - askedAt > SO.ASK_AGAIN) then
		askedAt = now
		ns.Guarded("guildrecipes", ask)
	end
	crafts = c
	local profs = 0
	for _ in pairs(c.profs) do profs = profs + 1 end
	local ch = c.check
	ns:Trace(("guild professions: the club roster: %d of %d members with professions; %s; %s; %d professions known"):format(st.club,
		st.members, st.club > 0 and "the guild's profession list: not read (the club roster has them)"
		or ("the guild's profession list: %d professions, %d players, %d folded ones opened, %d members read"):format(st.headers,
		st.players, st.opened, st.listed),
		ch and ("your %s: the guild says %s, the game %s: %s"):format(tostring(ch.name), tostring(ch.said), tostring(ch.real),
		c.ranks and "its skill numbers used" or "its numbers aren't skill levels, not used")
		or "no profession of yours to check its numbers by", profs))
	return c
end

--- Still waiting for the server's word on the guild's professions (asked, and nothing has them yet).
function SO.CraftsWaiting()
	return (askedAt and GetTime() - askedAt < SO.ASK_WAIT and not (crafts and (crafts.stats.club > 0 or crafts.stats.headers > 0)))
		and true or false
end

--- Forget what was read (tests; a new guild).
function SO.ForgetCrafts() crafts, askedAt, readUntil = nil, nil, 0 end

-- "Blacksmithing 265, Mining 300" (a number that isn't a skill level: the name alone), by name
local function SkillsText(c, m)
	local list = {}
	for pk, rank in pairs(m.skills) do
		local p = c.profs[pk]
		local name = p and p.name
		local real = RealRank(c, rank)
		if name then list[#list + 1] = real > 0 and (name .. " " .. real) or name end
	end
	table.sort(list)
	return list
end

-- What a member who has a profession is called, for searching ("guild skinner", "guild herbalists": the profession's
-- own name only starts "blacksmith"): by skill line, else by the profession's English name. English only.
SO.PEOPLE = { [164] = "blacksmith blacksmiths", [165] = "leatherworker leatherworkers", [171] = "alchemist alchemists",
	[182] = "herbalist herbalists", [186] = "miner miners", [197] = "tailor tailors", [202] = "engineer engineers",
	[333] = "enchanter enchanters", [393] = "skinner skinners", [755] = "jewelcrafter jewelcrafters", [773] = "scribe scribes",
	[185] = "cook cooks", [356] = "fisherman fishermen", [129] = "medic medics" }
local PEOPLE_BY_NAME = { blacksmithing = 164, leatherworking = 165, alchemy = 171, herbalism = 182, mining = 186,
	tailoring = 197, engineering = 202, enchanting = 333, skinning = 393, jewelcrafting = 755, inscription = 773,
	cooking = 185, fishing = 356, ["first aid"] = 129 }
local function PeopleWords(c, m)
	local out = {}
	for pk in pairs(m.skills) do
		local p = c.profs[pk]
		local w = SO.PEOPLE[pk] or (p and p.name and SO.PEOPLE[PEOPLE_BY_NAME[ns.Lower(p.name)] or 0])
		if w then out[#out + 1] = w end
	end
	return out
end

-- the lists' changes (the server's answer to an ask, a member's skill-up), apart from a read's own; another guild
local craftEvents = CreateFrame("Frame")
SO.craftEvents = craftEvents -- (tests)
for _, ev in ipairs({ "GUILD_TRADESKILL_UPDATE", "PLAYER_GUILD_UPDATE" }) do pcall(craftEvents.RegisterEvent, craftEvents, ev) end
craftEvents:SetScript("OnEvent", function(_, event)
	if event == "GUILD_TRADESKILL_UPDATE" and GetTime() < readUntil then return end
	if crafts then crafts.stale = true end
	local p = ns.providers.guild
	if p then p._dirty = true end
end)

-- the trace's counts of the last guild list built: members with a profession from each place, the club's members
local profStats = { list = 0, club = 0, members = 0 }
SO.profStats = profStats

function SO.GuildRows()
	local out = {}
	if not InGuild() then return out end
	AskRoster()
	local n = Num(Safe(GetNumGuildMembers)) or 0
	local c = SO.Crafts()
	local st = c and c.stats
	profStats.list, profStats.club, profStats.members = st and st.listed or 0, st and st.club or 0, st and st.members or 0
	for i = 1, n do
		local name, rank, rankIndex, level, classShown, zone, note, officerNote, online, _, class = Safe(GetGuildRosterInfo, i)
		name = Str(name)
		if name then
			rank, classShown, zone, note, officerNote = Str(rank), Str(classShown), Str(zone), Str(note), Str(officerNote)
			level, online = Num(level), online and true or false
			local shown = Short(name)
			local m = c and c.members[CraftKey(name)]
			local skills = m and SkillsText(c, m)
			-- (any of these can be missing: nil holes, so walked by count, not ipairs)
			local words = { "guild member", classShown, rank, zone, note, officerNote, online and "online" or "offline" }
			local text = {}
			for k = 1, 7 do local w = words[k]; if w and w ~= "" then text[#text + 1] = w end end
			if skills then for _, x in ipairs(skills) do text[#text + 1] = x end end
			if m then for _, x in ipairs(PeopleWords(c, m)) do text[#text + 1] = x end end
			out[#out + 1] = Row({
				key = name, name = shown, whisperTo = name, level = level, zone = zone, online = online,
				class = Str(class), rank = rank, rankIndex = Num(rankIndex), note = note,
				detail = Detail(level, classShown, rank, zone, online) .. ((skills and #skills > 0) and ("  " .. table.concat(skills, ", ")) or ""),
				color = online and ClassHex(Str(class)) or OFFLINE_HEX,
				icon = SO.TRADE_ICON,
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
	-- (GUILD_TRADESKILL_UPDATE: craftEvents, which knows the read's own from real changes)
	events = { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" },
	guard = 2,
	collect = function() return SO.GuildRows() end,
	busy = function() return SO.CraftsWaiting() and "Asking the server for your guild's professions" or nil end,
})

----------------------------------------------------------------------
-- Friends (the game's friend list and Battle.net friends)
----------------------------------------------------------------------

--- The game's friend list as rows (into out; seen[name] marks each). The number of friends on it.
local function FriendListRows(out, seen)
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
	return n
end

--- Battle.net friends as rows (into out), leaving out a character already listed from the friend list (seen).
--- How many were listed, how many are playing, and how many Battle.net friends there are.
-- Their BattleTag, account name or character may come as secret values here (Str gives nil): a friend is listed with
-- whatever is readable (playing: their character, "Girl Bird"), and whispered by their account id, which the /run line
-- turns into the account name when pressed (that name is an escape, never in text)
local function BNetRows(out, seen)
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
	return listed, playing, bn
end

function SO.FriendRows()
	local out, seen = {}, {}
	local n = FriendListRows(out, seen)
	local listed, playing, bn = BNetRows(out, seen)
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

----------------------------------------------------------------------
-- /who (@who; Simple mode: "who priest undercity")
--
-- Asking the server is protected (it wants a key press): the top row "Ask the server: /who <words>" is pressed by the
-- game (`/run C_FriendList.SendWho(...)`), the terminal stays open, and the answer (WHO_LIST_UPDATE) fills the list
-- below it, searched like the guild's (class, race, guild, zone, level; in:, lvl:). Results go to this list, not to
-- chat (SetWhoToUi while asking, put back once the answer is in).
----------------------------------------------------------------------

local who = { waiting = nil, asked = nil }
SO.who = who
SO.WHO_WAIT = 5 -- seconds the loading ring waits for an answer

--- The /who text for a search: its plain words, lvl:20-30 -> "20-30", in:undercity -> z-"Undercity"; other filters and
--- the @kind / action word dropped.
function SO.WhoFilter(text)
	local parts = {}
	local first = true
	for w in tostring(text or ""):gmatch("%S+") do
		local lw = ns.Lower(w)
		local key, val = lw:match("^(%a+):(.+)$")
		if lw:sub(1, 1) == "@" or (first and lw == "who") then
			-- (the kind, or Simple mode's action word)
		elseif key == "lvl" or key == "level" then
			local lo, hi = val:match("^(%d+)%-(%d+)$")
			parts[#parts + 1] = lo and (lo .. "-" .. hi) or val:match("^%d+$") or nil
		elseif key == "in" or key == "zone" then
			parts[#parts + 1] = 'z-"' .. val:gsub("_", " ") .. '"'
		elseif not key and not w:find('"', 1, true) then
			parts[#parts + 1] = w
		end
		first = false
	end
	return table.concat(parts, " ")
end

function SO.WhoMacro(e)
	return "/run local F=C_FriendList if F.SetWhoToUi then F.SetWhoToUi(true) end F.SendWho(" .. Quoted(e.whoFilter or "") .. ",1)"
end
local WHO_ASK = { macro = SO.WhoMacro }
local function WhoAsked(e)
	who.waiting, who.asked = GetTime(), e.whoFilter
	ns:Trace("who: asked the server: /who " .. tostring(e.whoFilter))
	if ns.UI and ns.UI.UpdateBusy then ns.UI:UpdateBusy() end
end
local function WhoInCombat() ns:Print("Ask /who again once combat is over (it needs a key press the game allows).") end

--- The row on top of an @who search: ask the server with the typed words.
function SO.WhoAskRow(text)
	local filter = SO.WhoFilter(text)
	return {
		name = "Ask the server: /who " .. (filter ~= "" and filter or "(everyone in your zone)"),
		detail = "Enter", kind = "who", kindLabel = "", icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
		whoFilter = filter, lead = true, secure = WHO_ASK, isOpen = Never, after = WhoAsked, activate = WhoInCombat,
		staysOpen = true, _pos = ns.UI and ns.UI.NO_POS or nil,
	}
end

function SO.WhoRows()
	local out = {}
	local FL = C_FriendList
	local n = FL and FL.GetNumWhoResults and Num(Safe(FL.GetNumWhoResults)) or 0
	for i = 1, n do
		local w = Safe(FL.GetWhoInfo, i)
		local name = type(w) == "table" and Str(w.fullName)
		if name then
			local guild, level, race, class, zone = Str(w.fullGuildName), Num(w.level), Str(w.raceStr), Str(w.classStr), Str(w.area)
			-- (each one answered the /who asked: its words count as theirs, so the search that asked lists them all, also
			-- by words only the server understood, "1-10" or z-"undercity"; words typed after that narrow them down)
			local text = { "who", who.asked or "" }
			local vals = { guild, race, class, zone, level and tostring(level) } -- (nil holes: walked by count)
			for k = 1, 5 do
				local v = vals[k]
				if v and v ~= "" then text[#text + 1] = v end
			end
			out[#out + 1] = Row({
				key = name, name = Short(name), whisperTo = name, level = level, zone = zone, online = true, guild = guild,
				class = Str(w.filename),
				detail = Detail(level, (race and class) and (race .. " " .. class) or class, guild and ("<" .. guild .. ">") or nil, zone, true),
				color = ClassHex(Str(w.filename)), icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
				text = table.concat(text, " "),
			})
		end
	end
	return out
end

ns:RegisterProvider("who", {
	label = "Who",
	color = "fff0e890",
	aliases = { "who" },
	explicit = true,
	events = { "WHO_LIST_UPDATE" },
	collect = function()
		if who.waiting then
			who.waiting = nil
			-- (who-to-UI back off: the game's own /who prints to chat again)
			if C_FriendList and C_FriendList.SetWhoToUi then Safe(C_FriendList.SetWhoToUi, false) end
		end
		local rows = SO.WhoRows()
		ns:Trace(("who: %d results (/who %s)"):format(#rows, tostring(who.asked or "")))
		return rows
	end,
	busy = function()
		if who.waiting and GetTime() - who.waiting < SO.WHO_WAIT then return "Asking the server who's online" end
		who.waiting = nil
	end,
	-- the top row of an @who search
	leadRow = function(_, text) return SO.WhoAskRow(text) end,
})
