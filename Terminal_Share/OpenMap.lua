-- (Terminal: Share, an addon of its own: Terminal's namespace is its public table, _G.Terminal. Not loaded, nothing of
-- this runs.)
-- OpenMap players' places (1.2.7, the player: "Can we have Terminal detect and show OpenMap coordinates of friends that
-- might be using OpenMap", then "Guild and friends"; .share settings openmap, off by default). OpenMap (an addon of its
-- own, MIT, github.com/openmap-world/openmap) lets a player share where they are with their guild and their friends who
-- use it, as addon messages under the prefix "OpenMapLoc": "L1 map x y class level" (tab-separated: a uiMapID, x and y
-- on it 0..1, the class's file name, the level), "L0" (stopped sharing), "H1" (a hello), "H2" (its answer). Its public
-- API (OpenMapAPI) has no call for these, so they're read as they arrive; nothing of OpenMap's code is used.
--
-- What's done with them: a guild member's place comes to the whole guild, so it's only heard. A friend's comes only to
-- friends their OpenMap has heard from: Terminal says hello (H1) to each friend as they come online, and answers a
-- friend's hello (H2), as OpenMap itself does. Your own place is never sent this way (that's Share's location setting,
-- to your Share groups). With OpenMap itself loaded, it says the hellos (Terminal stays quiet) and draws its own dots
-- (Terminal lists them only). A whisper is read only from a friend online, a guild message only on the guild's channel.
-- What's heard lives in memory only, and goes after GONE seconds without word.
local ns = _G.Terminal
if not ns or not ns.Ssh then return end
local L = ns.L

local SSH = ns.Ssh
local Lower, Str, Num, Safe = ns.Lower, ns.Str, ns.Num, ns.Safe
local Canon = SSH.Canon
local floor = math.floor

local OM = {}
SSH.OpenMap = OM

OM.PREFIX = "OpenMapLoc"
OM.GONE = 150      -- s without word before a place goes (as OpenMap's own dots)
OM.GAP = 0.5       -- s between messages sent (hellos and answers)
OM.MAX = 200       -- places kept at most (a big guild)
OM.SCAN_WAIT = 1   -- s after a friend list event before it's read (they come in bursts)
OM.FIRST_WAIT = 5  -- s after login before the first hellos

local live = {}     -- key -> { name, map, x, y, class, level, guild, at, shown }
local friends = {}  -- canonical name -> { key, name, whisper = target } or { key, name, bn = gameAccountID }: online now
local helloed = {}  -- key -> true: said hello since they came online
OM.live, OM.friends, OM.helloed = live, friends, helloed
OM.gen = 0          -- bumped by every change of a place (the map's dots follow it)
OM.on = false

local function Now() return GetTime() end

local function MyRealm()
	local r = Str(Safe(_G.GetNormalizedRealmName)) or Str(Safe(_G.GetRealmName)) or ""
	return Canon((r:gsub("[%s%-']", "")))
end

-- a name as the game writes it, canonical, your own realm left out ("Bob-YourRealm", "Bob": "bob"; "Bob-Other":
-- "bob-other"): a guild message's "Name-Realm" and a friend list's "Name" are one key
local function Key(name, realm)
	local c = Canon(name)
	if c == "" then return nil end
	if realm and realm ~= "" then c = c .. "-" .. Canon((realm:gsub("[%s%-']", ""))) end
	local mine = MyRealm()
	if mine ~= "" and #c > #mine + 1 and c:sub(-(#mine + 1)) == "-" .. mine then c = c:sub(1, -(#mine + 2)) end
	return c
end

-- the name shown: your own realm's left out (Ambiguate)
local function Shown(name)
	if type(_G.Ambiguate) == "function" then
		local s = Str(Safe(_G.Ambiguate, name, "none"))
		if s then return s end
	end
	return name
end

local function IsMe(c) -- (c: a Key)
	for _, n in ipairs({ ns.CharacterName and ns.CharacterName() or false, Str(Safe(_G.UnitName, "player")) or false }) do
		if n then
			if c == Key(n) then return true end
		end
	end
	return false
end

-- a friend online by the name a message came with: theirs, or nil
local function FriendOf(sender)
	local k = Key(sender)
	return k and friends[k] or nil
end

local function OpenMapLoaded() return _G.OpenMapAPI ~= nil end
OM.OpenMapLoaded = OpenMapLoaded

----------------------------------------------------------------------
-- Sending: one message each GAP, one waiting for each friend (a newer one replaces it)
----------------------------------------------------------------------

local outbox, order, sending = {}, {}, false
OM.outbox, OM.order = outbox, order

local function SendOne(m)
	if m.bn then
		local f = (C_BattleNet and C_BattleNet.SendGameData) or _G.BNSendGameData
		if f then pcall(f, m.bn, OM.PREFIX, m.text) end
	elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, OM.PREFIX, m.text, "WHISPER", m.whisper)
	end
end

OM.LOCKED_WAIT = 5 -- s before trying again while chat is locked down (in a fight, in some instances)
local function Pump()
	if order[1] and ns.ChatLocked and ns.ChatLocked() and C_Timer and C_Timer.After then
		C_Timer.After(OM.LOCKED_WAIT, Pump) -- (kept for then: a hello lost now isn't said again until they log in again)
		return
	end
	local key = table.remove(order, 1)
	if not key then sending = false return end
	local m = outbox[key]
	outbox[key] = nil
	if m and OM.on then SendOne(m) end
	if C_Timer and C_Timer.After then C_Timer.After(OM.GAP, Pump) else Pump() end
end

local function ToFriend(f, text)
	if not f or OpenMapLoaded() then return end -- (OpenMap loaded: it says its own)
	if not outbox[f.key] then order[#order + 1] = f.key end
	outbox[f.key] = { text = text, whisper = f.whisper, bn = f.bn }
	if not sending then sending = true; Pump() end
end
OM.ToFriend = ToFriend

----------------------------------------------------------------------
-- Friends online (and a hello to each just come online)
----------------------------------------------------------------------

local function Add(seen, name, realm, how)
	local key = Key(name, realm)
	if not key or IsMe(key) then return end
	local f = friends[key] or { key = key, name = Shown(name) }
	f.whisper, f.bn = how.whisper, how.bn
	seen[key] = f
end

--- Your friends online now, read again (C_FriendList, Battle.net friends playing this game); a hello to each new one.
function OM.Scan()
	local seen = {}
	local FL = C_FriendList
	for i = 1, (FL and FL.GetNumFriends and Num(Safe(FL.GetNumFriends)) or 0) do
		local f = Safe(FL.GetFriendInfoByIndex, i)
		local n = type(f) == "table" and f.connected == true and Str(f.name)
		-- (whispered as the game whispers them: a surname's space as the game writes it, Share.lua's WhisperTarget)
		local S = ns.Share
		if n then Add(seen, n, nil, { whisper = S and S.WhisperTarget and S.WhisperTarget(n) or n }) end
	end
	local B = C_BattleNet
	local wow = _G.BNET_CLIENT_WOW or "WoW"
	for i = 1, (Num(Safe(_G.BNGetNumFriends)) or 0) do
		local a = B and B.GetFriendAccountInfo and Safe(B.GetFriendAccountInfo, i)
		local g = type(a) == "table" and a.gameAccountInfo
		if type(g) == "table" and g.isOnline == true and g.clientProgram == wow
			and (not g.wowProjectID or not _G.WOW_PROJECT_ID or g.wowProjectID == _G.WOW_PROJECT_ID) then
			local char, id = Str(g.characterName), Num(g.gameAccountID)
			if char and id then Add(seen, char, Str(g.realmName), { bn = id }) end
		end
	end
	for k in pairs(friends) do friends[k] = nil end
	for k, f in pairs(seen) do friends[k] = f end
	-- (gone offline: a hello again when they're back, as OpenMap does)
	for k in pairs(helloed) do if not seen[k] then helloed[k] = nil end end
	for k, f in pairs(seen) do
		if not helloed[k] then helloed[k] = true; ToFriend(f, "H1") end
	end
end

local scanWaiting = false
local function ScanSoon(wait)
	if scanWaiting or not OM.on then return end
	if not (C_Timer and C_Timer.After) then OM.Scan() return end
	scanWaiting = true
	C_Timer.After(wait or OM.SCAN_WAIT, function()
		scanWaiting = false
		if OM.on then OM.Scan() end
	end)
end

----------------------------------------------------------------------
-- Places heard
----------------------------------------------------------------------

local function Changed() ns:Changed("shared") end

local expiry
local function Expire()
	local now, gone = Now(), false
	for k, p in pairs(live) do
		if now - p.at > OM.GONE then live[k] = nil; gone = true end
	end
	if gone then OM.gen = OM.gen + 1; Changed() end
	if not next(live) and expiry then expiry:Cancel(); expiry = nil end
end
OM.Expire = Expire

local function Watch()
	if expiry or not (C_Timer and C_Timer.NewTicker) then return end
	expiry = C_Timer.NewTicker(15, Expire)
end

local function Drop(key)
	if live[key] then live[key] = nil; OM.gen = OM.gen + 1; Changed() end
end

--- A message heard: from `sender` ("Name" or "Name-Realm"), the friend it came from (or nil), on the guild's channel or not.
function OM.Heard(sender, text, friend, guild)
	if not OM.on or type(text) ~= "string" or #text > 120 then return end
	local key = friend and friend.key or Key(sender)
	if not key or IsMe(key) then return end -- (your own, sent to your guild by OpenMap)
	if not (guild or friend) then return end -- (a whisper only from a friend online)
	local part = {}
	for v in (text .. "\t"):gmatch("([^\t]*)\t") do part[#part + 1] = v end
	local kind, m, x, y, class, level = part[1], part[2], part[3], part[4], part[5], part[6]
	if kind == "H1" then
		if friend then ToFriend(friend, "H2") end -- (they learn you hear them)
		return
	elseif kind == "L0" then
		Drop(key)
		return
	elseif kind ~= "L1" then
		return
	end
	m, x, y, level = tonumber(m), tonumber(x), tonumber(y), tonumber(level)
	if not (m and x and y) or m ~= floor(m) or m <= 0 or m > 1e6 or x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then return end
	if C_Map and C_Map.GetMapInfo and not Safe(C_Map.GetMapInfo, m) then return end -- (a map this client doesn't have)
	class = type(class) == "string" and #class <= 20 and class:match("^%u+$") or nil
	level = level and level == floor(level) and level >= 0 and level <= 1000 and level or nil
	local p = live[key]
	if not p then
		local n = 0
		for _ in pairs(live) do n = n + 1 if n >= OM.MAX then return end end
		p = { key = key, name = friend and friend.name or Shown(sender) }
		live[key] = p
	end
	p.map, p.x, p.y, p.class, p.level, p.at = m, x, y, class, level, Now()
	p.guild = p.guild or guild or false
	p.friend = friend and true or p.friend
	OM.gen = OM.gen + 1
	Watch()
	-- (the rows made again only when what one shows changes: the zone, x and y to the whole number, the class)
	local shown = m .. ":" .. floor(x * 100 + 0.5) .. ":" .. floor(y * 100 + 0.5) .. ":" .. (class or "")
	if shown ~= p.shown then p.shown = shown; Changed() end
end

--- Everyone sharing their place with OpenMap, heard lately: { name, map, x, y, at, class, level, guild, openmap, key }.
function OM.Places()
	local out = {}
	if not OM.on then return out end
	Expire()
	for k, p in pairs(live) do
		out[#out + 1] = { name = p.name, map = p.map, x = p.x, y = p.y, at = p.at, class = p.class, level = p.level,
			guild = p.guild, openmap = true, key = "omap:" .. k, omKey = k }
	end
	return out
end

--- .share settings openmap on|off: listening (and the hellos) start or stop; off, everything heard is forgotten.
function OM.SetOn(on)
	on = on == true
	if on == OM.on then return end
	OM.on = on
	if on then
		local CI = C_ChatInfo
		if not OM.registered and CI and CI.RegisterAddonMessagePrefix then
			pcall(CI.RegisterAddonMessagePrefix, OM.PREFIX)
			OM.registered = true
		end
		ScanSoon(OM.started and OM.SCAN_WAIT or OM.FIRST_WAIT)
	else
		for _, t in ipairs({ live, friends, helloed, outbox }) do for k in pairs(t) do t[k] = nil end end
		for i = #order, 1, -1 do order[i] = nil end
		if expiry then expiry:Cancel(); expiry = nil end
		OM.gen = OM.gen + 1
		Changed()
	end
end

----------------------------------------------------------------------
-- The setting, and the game's events
----------------------------------------------------------------------

if SSH.SETTINGS and SSH.SETTINGS_ORDER then
	SSH.SETTINGS.openmap = {
		default = false,
		name = L["Places on OpenMap"], -- (a name few words match by scattered letters: "npc", "omen", "swa" did, the parse golden)
		desc = L["Guild members and friends who share where they are with OpenMap show as class-coloured dots on your world map, and in your searches (where are my friends). Friends' OpenMap sends it only to those it hears from, so Terminal says hello to it as they come online. Yours is never sent this way. With OpenMap installed, it draws its own dots."],
		words = "guild location map gps", -- (few: more matched "npc", "omen" by scattered letters, the parse golden)
		apply = function(on) OM.SetOn(on) end,
	}
	SSH.SETTINGS_ORDER[#SSH.SETTINGS_ORDER + 1] = "openmap"
end

--- The game's events, as OpenMap's places are heard (also the tests' way in).
function OM.OnEvent(event, ...)
	if event == "PLAYER_LOGIN" then
		OM.SetOn(SSH.Setting and SSH.Setting("openmap") == true)
		OM.started = true
		return
	end
	if not OM.on then return end
	if event == "CHAT_MSG_ADDON" then
		local prefix, text, channel, sender = ...
		if Str(prefix) ~= OM.PREFIX then return end
		text, channel, sender = Str(text), Str(channel), Str(sender) -- (secret while chat is locked: ignored)
		if not (text and channel and sender) then return end
		if channel == "GUILD" then OM.Heard(sender, text, FriendOf(sender), true)
		elseif channel == "WHISPER" then OM.Heard(sender, text, FriendOf(sender), false) end
	elseif event == "BN_CHAT_MSG_ADDON" then
		local prefix, text, _, id = ...
		if Str(prefix) ~= OM.PREFIX then return end
		text, id = Str(text), Num(id)
		if not (text and id) then return end
		local f
		for _, o in pairs(friends) do if o.bn == id then f = o break end end
		if not f then -- (a Battle.net friend the last read didn't see yet)
			local g = C_BattleNet and C_BattleNet.GetGameAccountInfoByID and Safe(C_BattleNet.GetGameAccountInfoByID, id)
			local char = type(g) == "table" and Str(g.characterName)
			local key = char and Key(char, Str(g.realmName))
			if not key then return end
			f = { key = key, name = Shown(char), bn = id }
			friends[key] = f
		end
		OM.Heard(f.name, text, f, false)
	else
		ScanSoon() -- (the friend lists changed: who's online read again)
	end
end

do
	local f = CreateFrame("Frame")
	for _, ev in ipairs({ "CHAT_MSG_ADDON", "BN_CHAT_MSG_ADDON", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED",
		"BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "PLAYER_LOGIN" }) do
		pcall(f.RegisterEvent, f, ev)
	end
	f:SetScript("OnEvent", function(_, event, ...) OM.OnEvent(event, ...) end)
	OM.frame = f
end
