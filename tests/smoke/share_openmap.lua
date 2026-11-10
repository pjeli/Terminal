-- Terminal: Share: OpenMap players' places (1.2.7, the player: "Can we have Terminal detect and show OpenMap coordinates
-- of friends that might be using OpenMap", then "Guild and friends"). Terminal_Share/OpenMap.lua: .share settings
-- openmap, the messages heard (prefix OpenMapLoc), the hellos to friends, and where they show (@shared, the map's dots).
local T = ...
local ns, check, FlushAll = T.ns, T.check, T.FlushAll
local SSH = ns.Ssh
local OM = SSH.OpenMap

io.write("[share: OpenMap players' places, guild and friends]\n")
check(OM ~= nil, "OpenMap.lua loaded (Terminal_Share's TOC)")

local names = { "C_ChatInfo", "C_FriendList", "C_BattleNet", "BNGetNumFriends", "GetNormalizedRealmName", "UnitName",
	"OpenMapAPI", "GetTime", "C_Map", "Ambiguate" }
local saved = {}
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end
local savedDB, savedFriends = _G.TerminalShareDB, SSH.game.friends
_G.TerminalShareDB = {}

local sent, bnSent, registered = {}, {}, {}
_G.C_ChatInfo = {
	SendAddonMessage = function(prefix, text, chan, target) sent[#sent + 1] = { prefix = prefix, text = text, chan = chan, target = target }; return 0 end,
	RegisterAddonMessagePrefix = function(p) registered[p] = true; return true end,
}
local online = { { name = "Bob", connected = true }, { name = "Dan", connected = false } }
_G.C_FriendList = {
	GetNumFriends = function() return #online end,
	GetFriendInfoByIndex = function(i) return online[i] end,
}
_G.BNGetNumFriends = function() return 1 end
_G.C_BattleNet = {
	GetFriendAccountInfo = function(i)
		return i == 1 and { bnetAccountID = 5, gameAccountInfo = { gameAccountID = 77, characterName = "Eve", realmName = "Realm",
			clientProgram = "WoW", isOnline = true } } or nil
	end,
	SendGameData = function(id, prefix, text) bnSent[#bnSent + 1] = { id = id, prefix = prefix, text = text }; return 0 end,
}
_G.GetNormalizedRealmName = function() return "Realm" end
_G.UnitName = function() return "Tester" end
_G.OpenMapAPI = nil
_G.Ambiguate = function(n) return (n:gsub("%-Realm$", "")) end
local now = 1000
_G.GetTime = function() return now end
_G.C_Map = setmetatable({ GetMapInfo = function(id) if id == 1429 or id == 1411 then return { mapID = id, name = "Zone" .. id } end end },
	{ __index = saved.C_Map })
local changes = 0
local changedWas = ns.Changed
ns.Changed = function(self, id, ...) if id == "shared" then changes = changes + 1 end return changedWas(self, id, ...) end

local function Msg(text, chan, sender) OM.OnEvent("CHAT_MSG_ADDON", "OpenMapLoc", text, chan, sender) end
local function Place(name)
	for _, w in ipairs(OM.Places()) do if w.name == name then return w end end
end

do
	-- off by default: nothing heard, nothing sent
	check(SSH.Setting("openmap") == false and not OM.on, "off by default")
	Msg("L1\t1429\t0.4\t0.6\tMAGE\t30", "GUILD", "Gina-Realm")
	check(#OM.Places() == 0, "off: a guild member's place isn't kept")
	check(SSH.SETTINGS_ORDER[#SSH.SETTINGS_ORDER] == "openmap", "a Share setting of its own: .share settings openmap")

	-- on: the prefix registered, a hello to each friend online (Bob; Eve over Battle.net), none to Dan (offline)
	local out = SSH.SettingsCmd("openmap on")
	check(OM.on and _G.TerminalShareDB.settings.openmap == true and registered.OpenMapLoc,
		".share settings openmap on: on, remembered, its prefix registered: " .. tostring(out and out[1]))
	FlushAll()
	check(#sent == 1 and sent[1].prefix == "OpenMapLoc" and sent[1].text == "H1" and sent[1].chan == "WHISPER" and sent[1].target == "Bob",
		"a hello to Bob, a friend online (whispered): " .. tostring(sent[1] and sent[1].target))
	check(#bnSent == 1 and bnSent[1].id == 77 and bnSent[1].text == "H1", "a hello to Eve over Battle.net (her game account)")
	OM.Scan(); FlushAll()
	check(#sent == 1 and #bnSent == 1, "read again: no second hello to someone still online")

	-- a guild member's place, as OpenMap sends it to the guild
	changes = 0
	Msg("L1\t1429\t0.4000\t0.6000\tMAGE\t30", "GUILD", "Gina-Realm")
	local g = Place("Gina")
	check(g and g.map == 1429 and g.x == 0.4 and g.y == 0.6 and g.class == "MAGE" and g.guild and g.openmap,
		"a guild member's place: zone, x, y, class")
	check(changes == 0, "the rows not made again at once (1.2.9 review: a guild moving made them on every message)")
	FlushAll()
	check(changes == 1, "a new place: the rows made again, a moment later")
	local gen = OM.gen
	Msg("L1\t1429\t0.4000\t0.6000\tMAGE\t30", "GUILD", "Gina-Realm")
	check(OM.gen == gen, "the same place again: the map's dots not placed again (1.2.9 review)")
	Msg("L1\t1429\t0.4001\t0.6001\tMAGE\t30", "GUILD", "Gina-Realm"); FlushAll()
	check(changes == 1 and Place("Gina").x == 0.4 and OM.gen == gen, "a move too small to see (under OM.DOT_MOVE): the dots and rows left as they are (1.3.0 review)")
	Msg("L1\t1429\t0.5\t0.6\tMAGE\t30", "GUILD", "Gina-Realm")
	Msg("L1\t1429\t0.6\t0.6\tMAGE\t30", "GUILD", "Gina-Realm"); FlushAll()
	check(changes == 2 and Place("Gina").x == 0.6, "two moves that show, in a moment: the rows made again once")

	-- a whisper only from a friend online
	Msg("L1\t1429\t0.1\t0.1\tWARRIOR\t20", "WHISPER", "Zed-Realm")
	check(not Place("Zed"), "a whisper from someone not your friend: ignored")
	Msg("L1\t1411\t0.2\t0.3\tHUNTER\t25", "WHISPER", "Bob-Realm")
	local b = Place("Bob")
	check(b and b.map == 1411 and not b.guild, "Bob, a friend, whispers his place: kept (\"Bob-Realm\" is Bob on your realm)")
	OM.OnEvent("BN_CHAT_MSG_ADDON", "OpenMapLoc", "L1\t1429\t0.7\t0.7\tPRIEST\t40", "WHISPER", 77)
	check(Place("Eve") and Place("Eve").class == "PRIEST", "Eve over Battle.net: kept")
	Msg("L1\t1429\t0.7\t0.7\tPRIEST\t40", "PARTY", "Bob-Realm")
	Msg("L1\t1429\t0.7\t0.7\tPRIEST\t40", "GUILD", "Tester-Realm")
	check(not Place("Tester"), "your own place (OpenMap's, sent to your guild): not you on your map")

	-- what isn't a place
	for _, bad in ipairs({ "L1\t1429\t1.5\t0.5\tMAGE\t1", "L1\t0\t0.5\t0.5\tMAGE\t1", "L1\t9999\t0.5\t0.5\tMAGE\t1",
		"L1\t1429\t0\t0\tMAGE\t1", "L1\tx\t0.5\t0.5", "L9\t1429\t0.5\t0.5", "", string.rep("x", 200) }) do
		Msg(bad, "GUILD", "Hal-Realm")
	end
	check(not Place("Hal"), "off the map, a map the game doesn't have, 0,0, words, an unknown kind, too long: none kept")
	-- (nan: "nan" reads as a number on the game's C runtime, and no comparison turns it down; 1.2.9 review)
	local tonumberWas = _G.tonumber
	_G.tonumber = function(v, ...) if v == "nan" then return 0 / 0 end return tonumberWas(v, ...) end
	Msg("L1\t1429\tnan\t0.5\tMAGE\t1", "GUILD", "Hal-Realm")
	Msg("L1\t1429\t0.5\tnan\tMAGE\t1", "GUILD", "Hal-Realm")
	_G.tonumber = tonumberWas
	check(not Place("Hal"), "x or y that is nan: not kept")
	Msg("L1\t1429\t0.5\t0.5\t<script>\t-3", "GUILD", "Hal-Realm")
	check(Place("Hal") and Place("Hal").class == nil, "a class that isn't one: left out, the place kept")

	-- their hello: answered (they learn you hear them); a stranger's: not
	Msg("H1", "WHISPER", "Bob-Realm"); FlushAll()
	check(sent[#sent].text == "H2" and sent[#sent].target == "Bob", "Bob's hello: answered H2")
	local n = #sent
	Msg("H1", "WHISPER", "Zed-Realm"); FlushAll()
	check(#sent == n, "a stranger's hello: not answered")

	-- stopped sharing; gone quiet
	Msg("L0", "GUILD", "Hal-Realm")
	check(not Place("Hal"), "L0: stopped sharing, the place gone")
	now = now + OM.GONE + 1
	Msg("L1\t1429\t0.5\t0.5\tMAGE\t30", "GUILD", "Gina-Realm")
	check(#OM.Places() == 3, "gone quiet: still listed until it's looked at (never while the rows are made; 1.2.9 review)")
	OM.Expire()
	local left = {}
	for _, w in ipairs(OM.Places()) do left[#left + 1] = w.name end
	check(#left == 1 and left[1] == "Gina", "no word for " .. OM.GONE .. " s: gone (Gina, heard again, stays): " .. table.concat(left, ","))
	Msg("L1\t1411\t0.2\t0.3\tHUNTER\t25", "WHISPER", "Bob-Realm")

	-- with everyone's places: a Share friend by the same name is shown once (Share's), the rest after
	SSH.game.friends = { ["bob@realm"] = { claim = "bob@realm", name = "Bob", items = {}, where = { map = 1429, x = 0.1, y = 0.1, at = now } } }
	local all = SSH.AllPlaces(SSH.game)
	check(#all == 2 and all[1].name == "Bob" and not all[1].openmap and all[2].name == "Gina",
		"a Share friend sharing too: shown once, by Share; OpenMap's others after")
	SSH.game.friends = {}
	-- their rows: in @shared where, "openmap" and "guild" find them
	local rows = SSH.Rows(SSH.game)
	local row
	for _, r in ipairs(rows) do if r.omKey and r.name == "Gina" then row = r end end
	check(row and row.key == "omap:gina" and row.text:find("openmap guild", 1, true) and row.ui == 1429,
		"a row each: \"openmap\" and \"guild\" in its text, a spot row on the zone")
	local tip = { lines = {} }
	function tip:SetText(s) self.lines[#self.lines + 1] = s end
	function tip:AddLine(s) self.lines[#self.lines + 1] = s end
	function tip:AddDoubleLine(s) self.lines[#self.lines + 1] = s end
	local ok = pcall(row.tooltip, row, tip)
	check(ok and table.concat(tip.lines, "|"):find("OpenMap", 1, true), "its tooltip: shared with OpenMap, a guild member's")
	check(ns.SharePlaces.Question("where is gina") ~= nil, "\"where is gina\": asked of her place")

	-- chat locked down (a fight): the hello waits, then goes
	local lockedWas = ns.ChatLocked
	ns.ChatLocked = function() return true end
	n = #sent
	online[#online + 1] = { name = "Fay", connected = true }
	OM.Scan()
	for _ = 1, 20 do T.Flush() end
	check(#sent == n, "chat locked down: Fay's hello waits")
	ns.ChatLocked = lockedWas
	FlushAll()
	check(#sent == n + 1 and sent[#sent].target == "Fay" and sent[#sent].text == "H1", "then it goes")

	-- (1.2.9 review) a hello waiting for a friend gone offline meanwhile: not whispered to nobody
	ns.ChatLocked = function() return true end
	online[#online + 1] = { name = "Gus", connected = true }
	OM.Scan()
	table.remove(online) -- (Gus logs off before it goes)
	OM.Scan()
	ns.ChatLocked = lockedWas
	n = #sent
	FlushAll()
	local toGus = false
	for i = n + 1, #sent do if sent[i].target == "Gus" then toGus = true end end
	check(not toGus, "a friend gone offline before their hello went: not whispered")
	-- (1.2.9 review) the game says "not now" (throttled): tried again, not lost
	local sendWas, tries = _G.C_ChatInfo.SendAddonMessage, 0
	_G.C_ChatInfo.SendAddonMessage = function(prefix, text, chan, target)
		if target == "Hank" then
			tries = tries + 1
			if tries == 1 then return 3 end
		end
		return sendWas(prefix, text, chan, target)
	end
	online[#online + 1] = { name = "Hank", connected = true }
	n = #sent
	OM.Scan(); FlushAll()
	_G.C_ChatInfo.SendAddonMessage = sendWas
	check(tries == 2 and sent[#sent].target == "Hank" and sent[#sent].text == "H1", "throttled: Hank's hello tried again and sent: " .. tries)
	-- (1.2.9 review) the cap is the guild's: a friend's place is always kept
	local maxWas = OM.MAX
	OM.MAX = 0
	Msg("L1\t1429\t0.3\t0.3\tMAGE\t9", "GUILD", "Ida-Realm")
	Msg("L1\t1429\t0.3\t0.3\tMAGE\t9", "WHISPER", "Hank-Realm")
	OM.MAX = maxWas
	check(not Place("Ida") and Place("Hank"), "the guild's places at their cap: a new guild member's left out, a friend's kept")
	-- (1.2.9 review) one player twice, by Battle.net's first name alone and the guild's whole name: shown once
	OM.Heard("Ivy Moss-Realm", "L1\t1429\t0.2\t0.2\tDRUID", nil, true)
	OM.Heard("Ivy", "L1\t1429\t0.2\t0.2\tDRUID", { key = "ivy", name = "Ivy", bn = 99 }, false)
	local ivies = 0
	for _, w in ipairs(SSH.AllPlaces(SSH.game)) do if w.name:find("^Ivy") then ivies = ivies + 1 end end
	check(ivies == 1, "Ivy by her first name and her whole name: one place shown: " .. ivies)
	OM.OnEvent("CHAT_MSG_ADDON", "OpenMapLoc", "L0", "GUILD", "Ivy Moss-Realm")
	OM.Heard("Ivy", "L0", { key = "ivy", name = "Ivy", bn = 99 }, false)
	OM.OnEvent("CHAT_MSG_ADDON", "OpenMapLoc", "L0", "WHISPER", "Hank-Realm")

	-- the map's dots: OpenMap's too, unless OpenMap is loaded (it draws its own)
	check(#SSH.AllPlaces(SSH.game, true) == 2, "the dots: OpenMap players' too")
	_G.OpenMapAPI = {}
	check(#SSH.AllPlaces(SSH.game, true) == 0 and #SSH.AllPlaces(SSH.game) == 2, "OpenMap loaded: no dots of Terminal's for them, the rows still")
	n = #sent
	online[2].connected = true -- (Dan comes online)
	OM.Scan(); FlushAll()
	check(#sent == n, "OpenMap loaded: it says its own hellos, Terminal none")
	_G.OpenMapAPI = nil

	-- off: forgotten
	SSH.SettingsCmd("openmap off")
	check(not OM.on and #OM.Places() == 0 and next(OM.friends) == nil, "off: everything heard forgotten")
	Msg("L1\t1429\t0.5\t0.5\tMAGE\t30", "GUILD", "Gina-Realm")
	check(#OM.Places() == 0, "off: nothing heard")
	check(ns.SharePlaces.None()[1].name:find("openmap on", 1, true),
		"nobody's place: the note says how to see OpenMap players' too")
end

for _, k in ipairs(names) do _G[k] = saved[k] end
ns.Changed = changedWas
_G.TerminalShareDB = savedDB
SSH.game.friends = savedFriends
ns:Changed("shared")
