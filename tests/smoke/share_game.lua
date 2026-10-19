-- Terminal: Share in this client (0.58.1): the game's events and calls as Share.lua reads them, @shared in searches,
-- .ssh at the prompt, and what's never kept (the password line; anything a friend sent).
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local L = ns.L
local SSH = ns.Ssh

io.write("[share: the share shell in the game]\n")

local roundsWas = SSH.KDF_ROUNDS
SSH.KDF_ROUNDS = 3
local hmacWas = ns.Crypto.HMAC
-- (a quick stand-in for HMAC, as share.lua's: the harness's SHA-256 is plain arithmetic)
ns.Crypto.HMAC = function(key, msg)
	local s = tostring(key) .. "\0" .. tostring(msg)
	local a = 7
	for i = 1, #s do a = (a * 31 + s:byte(i) + i) % 2147483629 end
	return string.rep(string.char(a % 256, math.floor(a / 256) % 256, math.floor(a / 65536) % 256, 7), 8)
end

-- the game, as this file needs it
local saved, names = {}, { "C_ChatInfo", "C_FriendList", "C_BattleNet", "BNGetNumFriends", "IsInGuild", "GetNumGuildMembers",
	"GetGuildRosterInfo", "GetNormalizedRealmName", "UnitName", "issecretvalue", "ChatFrame_SendTell" }
for _, k in ipairs(names) do saved[k] = rawget(_G, k) end
local savedNameByID = C_Item.GetItemNameByID
local sent, bnSent, tells = {}, {}, {}
_G.C_ChatInfo = {
	SendAddonMessage = function(prefix, text, chan, target) sent[#sent + 1] = { prefix = prefix, text = text, chan = chan, target = target }; return 0 end,
	InChatMessagingLockdown = function() return false end,
	RegisterAddonMessagePrefix = function() return true end,
}
_G.C_FriendList = {
	GetNumFriends = function() return 1 end,
	GetFriendInfoByIndex = function(i) return i == 1 and { name = "Quilleran", connected = true } or nil end,
}
_G.BNGetNumFriends = function() return 1 end
_G.C_BattleNet = {
	GetFriendAccountInfo = function(i)
		return i == 1 and { bnetAccountID = 5, battleTag = "Zeph#1234", accountName = "|Kq55|k", isOnline = true } or nil
	end,
	GetFriendNumGameAccounts = function() return 1 end,
	GetFriendGameAccountInfo = function(i, j)
		return { gameAccountID = 77, characterName = "Zephyrine", realmName = "Realm", clientProgram = "WoW", isOnline = true }
	end,
	SendGameData = function(id, prefix, text) bnSent[#bnSent + 1] = { id = id, prefix = prefix, text = text }; return 0 end,
}
_G.IsInGuild = function() return false end
_G.GetNormalizedRealmName = function() return "Realm" end
_G.ChatFrame_SendTell = function(who) tells[#tells + 1] = who end
C_Item.GetItemNameByID = function(id) return ({ [2589] = "Linen Cloth", [6948] = "Hearthstone", [118] = "Minor Healing Potion" })[id] end
SSH.Forget()
local ep = SSH.game
ep:Off()

local function Last() return sent[#sent] end

-- nonces: the game's, 16 hex characters, never the same twice; made cheaply after (the harness's SHA-256 is plain
-- arithmetic, and these tests say hello many times)
check(SSH.Nonce():find("^%x+$") and #SSH.Nonce() == 16 and SSH.Nonce() ~= SSH.Nonce(), "a nonce: 16 hex characters, new each time")
local nonceWas, nn = ep.env.nonce, 0
ep.env.nonce = function() nn = nn + 1; return ("%016x"):format(nn + 4096) end

-- .ssh is Terminal: Share's (Terminal's stand-in, saying how to turn it on, is registered over)
check(ns:FindCommand("share") and ns:FindCommand("share").complete ~= nil, ".share is Terminal: Share's, not the stand-in")
-- (0.58.14, the player: .share the command, .ssh its alias)
check(ns:FindCommand("ssh") == ns:FindCommand("share") and ns.commands.share and not ns.commands.ssh, ".share, and .ssh as its alias")

-- the password line: never kept
do
	check(ns.SecretLine(".ssh password hunter2hunter2") and ns.SecretLine("  ssh pass x") and ns.SecretLine(".SSH Password X")
		and ns.SecretLine(".ssh pw secret") and not ns.SecretLine(".ssh pwn")
		and not ns.SecretLine("linen cloth") and not ns.SecretLine(".ssh share all")
		and ns.SecretLine(".share password x") and ns.SecretLine("share pw x") and not ns.SecretLine(".share all")
		and not ns.SecretLine("mountain pass") and not ns.SecretLine("shared password"),
		"the password line is told apart (.share and .ssh)")
	-- (review, 0.58.16) the command search finds .share by a shortened or misspelt name: those lines are too
	check(ns.SecretLine(".shar password x") and ns.SecretLine(".sh pw x") and ns.SecretLine(".hare pass x")
		and ns.SecretLine(".shared password x") and ns.MaskSecret(".shar pw abc") == ".shar pw ***"
		and not ns.SecretLine(".shar pwn x") and not ns.SecretLine(".set cursor block"), "...a shortened .share too")
	UI:Open("")
	T.typeText(".ssh password hunter2hunter2")
	-- a tab made while it's typed: the line isn't kept in it
	ns.Tabs.New()
	local list = ns.db.tabs and ns.db.tabs.list or {}
	local inTab = false
	for _, tab in ipairs(list) do if tostring(tab.text):find("hunter2", 1, true) then inTab = true end end
	check(#list >= 2 and not inTab, "a tab kept while the password is typed: without it")
	ns.Tabs.Close()
	UI:Hide()
	UI:Open("")
	T.typeText(".share password hunter2hunter2")
	-- shown as *s while it's typed (0.58.6, the player: streams)
	check(ns.MaskSecret(".ssh password hunter2hunter2") == ".ssh password **************" and ns.MaskSecret("linen") == "linen"
		and ns.MaskSecret(".ssh pw abc") == ".ssh pw ***" and ns.MaskSecret(".share password abc") == ".share password ***",
		"the password as *s, a * a letter")
	UI:UpdateSyntax()
	local drawn = UI.syntax and (UI.syntax.text or (UI.syntax.GetText and UI.syntax:GetText())) or ""
	check(type(drawn) == "string" and not drawn:find("hunter2", 1, true) and drawn:find("**************", 1, true),
		"the prompt draws it as *s: " .. tostring(drawn))
	T.key("ENTER")
	if T.F.scripts.OnKeyUp then T.F.scripts.OnKeyUp(T.F, "ENTER") end -- (let go: the games after this read a held Enter)
	T.FlushAll()
	check(ep.groups.default ~= nil, ".ssh password, Enter: the key is set (the default group): " .. tostring(ep:On()))
	-- nothing saved holds it
	local found
	local seen = {}
	local function Walk(t, path)
		if seen[t] then return end
		seen[t] = true
		for k, v in pairs(t) do
			if type(v) == "string" and v:find("hunter2", 1, true) then found = path .. "." .. tostring(k) end
			if type(k) == "string" and k:find("hunter2", 1, true) then found = path .. "[key]" end
			if type(v) == "table" then Walk(v, path .. "." .. tostring(k)) end
		end
	end
	Walk(ns.db, "db")
	Walk(_G.TerminalShareDB or {}, "TerminalShareDB")
	check(found == nil, "the password is nowhere in what's saved: " .. tostring(found))
	-- remembered: the key made from it (0.58.6, the player: "saved and re-used automatically on login")
	local saved = _G.TerminalShareDB and _G.TerminalShareDB.groups and _G.TerminalShareDB.groups.default
	check(saved and saved.key == ns.Crypto.Hex(ep.groups.default.key) and saved.mode == "limited", "the key is remembered, not the password (and what's shared)")
	local h = ns:HistoryLines()
	local inHist
	for _, line in ipairs(h) do if tostring(line):find("hunter2", 1, true) then inHist = line end end
	check(inHist == nil, "not in the history (Up): " .. tostring(inHist))
	-- hello went to the friend by whisper and the Battle.net friend's character by game data, prefix TermSSH
	local toFriend, toBN = false, false
	for _, m in ipairs(sent) do
		if m.prefix == "TermSSH" and m.chan == "WHISPER" and m.target == "Quilleran" and m.text:find("^4H ") then toFriend = true end
		check(not m.text:find("hunter2", 1, true), "the password is never sent")
	end
	for _, m in ipairs(bnSent) do if m.id == 77 and m.prefix == "TermSSH" and m.text:find("^4H ") then toBN = true end end
	check(toFriend and toBN, "hello to the friend list (whisper) and the Battle.net friend's character (game data)")
end

-- (review, 0.58.16) the password's other ways out
do
	local edit = UI.edit
	local pwSet = rawget(edit, "SetPassword")
	local pwOn
	rawset(edit, "SetPassword", function(self, v) pwOn = v end)
	edit.secretShown = nil
	-- a shortened .share runs the password too: never in the history either
	UI:Hide(); UI:Open("")
	T.typeText(".shar password hunter2hunter2")
	T.FlushAll()
	check(UI.results[1] and UI.results[1].name == "share", ".shar finds .share: " .. tostring(UI.results[1] and UI.results[1].name))
	local drawn = UI.syntax and (UI.syntax.text or (UI.syntax.GetText and UI.syntax:GetText())) or ""
	check(not drawn:find("hunter2", 1, true), "...and the prompt draws it as *s: " .. tostring(drawn))
	-- leaving Terminal's own keys with the line as it is (a click into the box): the box's own password mode
	check(UI.keys and pwOn == false, "Terminal's keys: the box's password mode off (the copy over it shows *s)")
	edit.scripts.OnEditFocusGained(edit)
	check(not UI.keys and pwOn == true, "the box's own keys: its password mode on (it was left off, the password in clear)")
	UI:Hide(); UI:Open("")
	-- traces (.debug) say it as *s: fuzzy finding started on it
	local traced = {}
	local trace = ns.Trace
	ns.Trace = function(_, m) traced[#traced + 1] = tostring(m) end
	T.typeText(".share password hunter2hunter2")
	UI:StartFuzzy()
	UI:EndFuzzy()
	ns.Trace = trace
	local leak
	for _, m in ipairs(traced) do if m:find("hunter2", 1, true) then leak = m end end
	check(#traced > 0 and leak == nil, "a trace of the line: the password as *s: " .. tostring(leak))
	-- a click among the *s of one letter (two bytes, two *s): before the letter, never inside it
	UI:Hide(); UI:Open("")
	edit:SetText(".share password pässwörter")
	UI:UpdateSyntax()
	local real = edit:GetText()
	local inside
	for x = 0, 7 * #real, 1 do
		local at = UI.PromptIndexAt(x, 0)
		local b = real:byte(at + 1)
		if at > 0 and b and b >= 128 and b < 192 then inside = at end
	end
	check(inside == nil, "a click on the masked password lands between letters: " .. tostring(inside))
	ns:RecordHistory(".sh pw hunter2hunter2")
	local h = ns:HistoryLines()
	check(not tostring(h[1]):find("hunter2", 1, true), "a shortened password line isn't kept")
	rawset(edit, "SetPassword", pwSet)
	edit.secretShown = nil
	UI:Hide()
end

-- (review, 0.58.16) a guildmate on your friend list: said hello on the guild channel, not by whisper as well (the roster
-- writes "Quilleran-Realm", the friend list "Quilleran")
do
	local was = { rawget(_G, "IsInGuild"), rawget(_G, "GetNumGuildMembers"), rawget(_G, "GetGuildRosterInfo") }
	local keep = { peers = {}, queue = ep.queue, hellos = ep.hellos, tried = ep.tried }
	for k, p in pairs(ep.peers) do local c = {}; for a, b in pairs(p) do c[a] = b end; keep.peers[k] = c end
	ep.queue, ep.hellos, ep.tried = {}, {}, {}
	_G.IsInGuild = function() return true end
	_G.GetNumGuildMembers = function() return 1 end
	_G.GetGuildRosterInfo = function(i) if i == 1 then return "Quilleran-Realm" end end
	SSH.OnEvent("GUILD_ROSTER_UPDATE")
	local n0 = #sent
	ep.tokens = 0
	ep:Hello()
	local guild, whisper = 0, 0
	local function Count(m) if m.text:find("^4H ") then
		if m.chan == "GUILD" or (m.route and m.route.kind == "guild") then guild = guild + 1
		elseif m.target == "Quilleran" or (m.route and m.route.target == "Quilleran") then whisper = whisper + 1 end
	end end
	for i = n0 + 1, #sent do Count(sent[i]) end
	for _, m in ipairs(ep.queue) do Count(m) end
	check(guild == 1 and whisper == 0, "a guildmate on your friend list: one hello, the guild channel's: " .. guild .. "/" .. whisper)
	_G.IsInGuild, _G.GetNumGuildMembers, _G.GetGuildRosterInfo = was[1], was[2], was[3]
	SSH.OnEvent("GUILD_ROSTER_UPDATE")
	ep.peers, ep.queue, ep.hellos, ep.tried = keep.peers, keep.queue, keep.hellos, keep.tried
	ep.tokens = SSH.BURST
end

-- at login: the remembered key in use, a few seconds in, everyone said hello to
do
	local hex = _G.TerminalShareDB.groups.default.key
	ep:Off()
	local n, nb = #sent, #bnSent
	SSH.OnEvent("PLAYER_LOGIN")
	check(not ep:On(), "not at once: friends and guild are read first")
	T.FlushAll()
	check(ep.groups.default and ns.Crypto.Hex(ep.groups.default.key) == hex, "a few seconds in: the remembered key")
	check(#sent > n and #bnSent > nb and sent[#sent].text:find("^4H "), "...and hello to everyone")
	-- .ssh off forgets it
	ns:FindCommand("ssh").run("off")
	check(next(_G.TerminalShareDB.groups) == nil and not ep:On(), ".ssh off: forgotten")
	SSH.OnEvent("PLAYER_LOGIN")
	T.FlushAll()
	check(not ep:On(), "...and not used at the next login")
	-- (0.58.6-0.58.16 remembered one key, TerminalShareDB.key; 0.59.0 makes keys with ten times the rounds: one made
	-- before is forgotten and its password asked for again, once; what was shared with it is kept as the setting)
	_G.TerminalShareDB = { key = hex, groups = { raid = { key = hex, mode = "all" } } }
	ns.db.sshShare = "mats"
	local says = {}
	local sayWas = ep.env.say
	ep.env.say = function(t) says[#says + 1] = t end
	SSH.OnEvent("PLAYER_LOGIN")
	T.FlushAll()
	ep.env.say = sayWas
	check(not ep:On() and next(SSH.Saved().groups) == nil and _G.TerminalShareDB.key == nil and ns.db.sshShare == nil
		and SSH.Saved().mode == "mats", "keys made the way before: forgotten, not used: " .. table.concat(says, " / "))
	check(#says == 1 and says[1]:find("default", 1, true) and says[1]:find("raid", 1, true), "...said once, naming the groups to type again")
	-- (a key made this way: used)
	_G.TerminalShareDB.groups = { default = { key = hex, mode = "mats", kdf = SSH.KDF_ID } }
	SSH.OnEvent("PLAYER_LOGIN")
	T.FlushAll()
	check(ep.groups.default and ns.Crypto.Hex(ep.groups.default.key) == hex and ep.groups.default.mode == "mats",
		"a key made this way: used at login, its mode kept")
	ep:SetMode("limited")
	SSH.Saved().mode, SSH.Saved().groups.default.mode, ep.defaultMode = nil, "limited", "limited"
	ep.peers, ep.queue, ep.hellos, ep.tokens, ep.refillAt = {}, {}, {}, SSH.BURST, 0 -- (its hellos unanswered: the tests after start clean)
end

-- who's heard
do
	local n, nb0 = #sent, #bnSent
	SSH.OnEvent("CHAT_MSG_ADDON", "OtherAddon", "4H 00000000000000aa,quilleran@realm,0000," .. SSH.Mark(ep.groups.default.key, "0000", "quilleran@realm"), "WHISPER", "Quilleran")
	check(#sent == n, "another addon's prefix: ignored")
	SSH.OnEvent("CHAT_MSG_ADDON", "TermSSH", "4H 00000000000000aa,eve@realm,0000," .. SSH.Mark(ep.groups.default.key, "0000", "eve@realm"), "WHISPER", "Eve")
	check(#sent == n, "a stranger's whisper: ignored, no answer")
	SSH.OnEvent("CHAT_MSG_ADDON", "TermSSH", "4H 00000000000000aa,quilleran@realm,0000," .. SSH.Mark(ep.groups.default.key, "0000", "quilleran@realm"), "PARTY", "Quilleran")
	check(#sent == n, "a party message: never read")
	_G.issecretvalue = function(v) return v == "SECRET" end
	SSH.OnEvent("CHAT_MSG_ADDON", "TermSSH", "SECRET", "WHISPER", "Quilleran")
	SSH.OnEvent("CHAT_MSG_ADDON", "TermSSH", "4H 00000000000000aa,quilleran@realm,0000," .. SSH.Mark(ep.groups.default.key, "0000", "quilleran@realm"), "WHISPER", "SECRET")
	check(#sent == n, "secret fields (chat locked): ignored")
	_G.issecretvalue = saved.issecretvalue
	SSH.OnEvent("BN_CHAT_MSG_ADDON", "TermSSH", "4H 00000000000000aa,mal@realm,0000," .. SSH.Mark(ep.groups.default.key, "0000", "mal@realm"), "WHISPER", 78)
	check(#bnSent == nb0, "Battle.net data from a game account that isn't a friend's: ignored")
	-- a friend's hello: challenged, by whisper, to the name the server gave
	ep.peers = {}
	SSH.OnEvent("CHAT_MSG_ADDON", "TermSSH", "4H 00000000000000aa,quilleran@realm,0000," .. SSH.Mark(ep.groups.default.key, "0000", "quilleran@realm"), "WHISPER", "Quilleran")
	check(#sent == n + 1 and Last().text:find("^4C 00000000000000aa,%x+,") and Last().target == "Quilleran" and Last().chan == "WHISPER",
		"a friend's hello: challenged: " .. tostring(Last().text))
	-- a Battle.net friend's character: by game data
	SSH.OnEvent("BN_CHAT_MSG_ADDON", "TermSSH", "4H 00000000000000ab,zephyrine@realm,0000," .. SSH.Mark(ep.groups.default.key, "0000", "zephyrine@realm"), "WHISPER", 77)
	check(bnSent[#bnSent].id == 77 and bnSent[#bnSent].text:find("^4C 00000000000000ab,"), "a Battle.net friend's: challenged by game data")
end

-- a Battle.net friend, end to end through the game's calls and events (0.58.2, in game: connected over Battle.net,
-- "items: 0" on every side): a "|" in what's sent comes back escaped, as chat's escape character
do
	local clock = 5000
	local gt = _G.GetTime
	_G.GetTime = function() return clock end
	local key
	SSH.Derive("hunter2hunter2", function(k) key = k end)
	local toFriend = {}
	local friend = SSH.Endpoint({
		now = function() return clock end,
		claim = function() return "zephyrine@realm" end,
		send = function(route, text)
			-- (into the game as Battle.net game data from account 77, a "|" escaped on the way)
			SSH.OnEvent("BN_CHAT_MSG_ADDON", "TermSSH", (text:gsub("|", "||")), "WHISPER", 77)
			return 0
		end,
		eligible = function() return "Plamen" end,
		matches = function() return true end,
		items = function() return SSH.Simple("Zephyrine", { [2589] = 15, [118] = 2 }) end,
		locked = function() return false end, changed = function() end, say = function() end,
		nonce = (function() local n = 0; return function() n = n + 1; return ("%016x"):format(n) end end)(),
		broadcast = function() return {} end,
	})
	friend.defaultMode = "all"
	friend:JoinGroup("default", key, nil, true)
	local sendGame = C_BattleNet.SendGameData
	C_BattleNet.SendGameData = function(id, prefix, text)
		bnSent[#bnSent + 1] = { id = id, prefix = prefix, text = text }
		if id == 77 then toFriend[#toFriend + 1] = (text:gsub("|", "||")) end
		return 0
	end
	ep.peers, ep.friends = {}, {}
	friend:Hello({ kind = "bn", id = 1 })
	for _ = 1, 30 do
		while #toFriend > 0 do friend:Receive({ kind = "bn", id = 1 }, table.remove(toFriend, 1)) end
		clock = clock + 1
		ep:Tick()
		friend:Tick()
	end
	local c = ep:Connected()[1]
	check(c and c.name == "Zephyrine" and c.n == 2, "a Battle.net friend's items arrive: " .. tostring(c and c.n))
	local d = table.concat(SSH.Debug(ep), " / ")
	check(d:find("friend Zephyrine (all; groups default): items 2", 1, true), ".ssh debug says so: " .. d)
	C_BattleNet.SendGameData = sendGame
	_G.GetTime = gt
	ep.peers, ep.friends = {}, {}
end

-- friends' items in searches: @shared, Simple mode's Bank & alts, > alts
do
	ep.peers = {}
	ep.friends = {
		["quilleran@realm"] = { key = "w:quilleran", state = "up", name = "Quilleran", claim = "quilleran@realm", last = GetTime(),
			route = { kind = "whisper", target = "Quilleran" }, items = { [2589] = 20, [118] = 3 }, n = 2, gold = 12345678,
			places = { { who = "Quilleran", where = "b" }, { who = "Quillalt", where = "k" } },
			entries = { [2589] = "0.5,1.f", [118] = "0.3" } },
		["zephyrine@realm"] = { key = "b:77", state = "up", name = "Zephyrine", claim = "zephyrine@realm", last = GetTime(),
			route = { kind = "bn", id = 77, name = "Zephyrine", bnetID = 5 }, items = { [2589] = 15 }, n = 1 },
	}
	ns:Changed("shared")
	local easy = ns.db.easyMode
	ns.db.easyMode = false
	local rows = UI:Search("@shared linen")
	local e, z
	for _, r in ipairs(rows) do
		if r.owner == "Quilleran" then e = r elseif r.owner == "Zephyrine" then z = r end
	end
	check(#rows == 2 and e and z and e.kind == "shared" and e.total == 20 and z.total == 15,
		"@shared linen: a row each friend who has it, with their count: " .. #rows)
	-- (0.59.0, the player: "distinctly separated as in Bank vs in Bags")
	check(e and e.detail == "x20" .. ns.DETAIL_SEP .. "Quilleran" .. ns.DETAIL_SEP .. L["bags"] .. " 5, " .. L["bank"] .. " 15",
		"...their name, and bags and bank apart: " .. tostring(e and e.detail))
	check(e and e.shareExtra(e) == " x20: Quillalt 15 (bank), Quilleran 5 (bags)",
		"sent to chat: their characters, as @stored says it: " .. tostring(e and e.shareExtra(e)))
	-- grouped and sorted by owner (0.58.6, the player: "Cad Man vs Cherry Tusks")
	UI:Open("@shared | group by owner")
	T.FlushAll()
	local gn = {}
	for _, r in ipairs(UI.Results()) do if r.kind == "aggregate" then gn[#gn + 1] = ns.Plain(tostring(r.name)) end end
	UI:Hide()
	table.sort(gn)
	check(table.concat(gn, ",") == "Quilleran,Zephyrine", "| group by owner: a group a friend: " .. table.concat(gn, ","))
	local sorted = UI:Search("@shared sort:owner")
	local last, inOrder = "", true
	for _, r in ipairs(sorted) do
		if r.owner then
			if r.owner < last then inOrder = false end
			last = r.owner
		end
	end
	check(inOrder and last == "Zephyrine", "sort:owner: A-Z by friend")
	check(ns.Bar.ById(ns.Bar.SORTS, "owner") and (function()
		for _, id in ipairs(ns.Bar.GROUPS) do if id == "owner" then return true end end
	end)(), "the bar's Sort and Group offer Owner")
	check(#UI:Search("@shared on:zeph") == 1 and #UI:Search("@ssh potion") == 1, "on:<friend> and @ssh work")
	-- (0.58.12, the player: "Rename @friendsbags to @shared")
	check(ns:ResolveProvider("shared") == ns.providers.shared and ns.providers.shared.label == "Shared"
		and ns:ResolveProvider("friendsbags") == nil, "the list is @shared, labelled Shared; @friendsbags is gone")
	-- the game's own item tooltip, then the friends'
	local got = {}
	local tip = setmetatable({}, { __index = function(_, k)
		return function(_, a) got[#got + 1] = k .. "(" .. tostring(a) .. ")" end
	end })
	e.tooltip(e, tip)
	local doubles = 0
	for _, g in ipairs(got) do if g:find("^AddDoubleLine") then doubles = doubles + 1 end end
	check(got[1] == "SetHyperlink(item:2589)" and table.concat(got, " "):find("Quillalt|r", 1, true) and doubles == 3
		and table.concat(got, " "):find("Zephyrine 15", 1, true),
		"the tooltip: the item's own, a line per character and the total as @stored's, who else has it: " .. table.concat(got, " "))
	-- where a friend keeps it, and their gold (.ssh all)
	check(SSH.Breakdown(e)[2] == "  Quillalt: 15  (bank 15)", "Shift+Enter: as @stored's: " .. tostring(SSH.Breakdown(e)[2]))
	local g = UI:Search("@shared gold")
	check(#g == 1 and g[1].name == "Quilleran's gold" and g[1].money == 12345678, "a friend's gold: " .. tostring(g[1] and g[1].name))
	-- no Battle.net account name anywhere in a row
	local leak = false
	for _, r in ipairs(UI:Search("@shared")) do
		for _, v in pairs(r) do if type(v) == "string" and v:find("|K", 1, true) then leak = true end end
	end
	check(not leak, "no Battle.net account name in a row")
	-- Enter: whisper the friend with the most
	local top = SSH.Top(e)
	check(top and top.whisperTo == "Quilleran", "Enter whispers the friend with the most: " .. tostring(top and top.whisperTo))
	-- a plain search: there with your own
	local found = false
	for _, r in ipairs(UI:Search("linen cloth")) do if r.kind == "shared" then found = true end end
	check(found, "a plain search lists friends' items too")
	-- > alts
	found = false
	for _, r in ipairs(UI:Search("linen cloth > alts")) do if r.kind == "shared" then found = true end end
	check(found, "linen cloth > alts: friends' bags with your alts")
	-- Simple mode: in Bank & alts
	ns.db.easyMode = true
	found = false
	local cat = false
	for _, r in ipairs(UI:Search("linen cloth")) do if r.kind == "category" and r.catId == "stored" then cat = true end end
	UI:SetCategory("stored")
	for _, r in ipairs(UI:Search("linen cloth")) do if r.kind == "shared" then found = true end end
	UI:SetCategory(nil)
	check(cat and found, "Simple mode: in Bank & alts")
	ns.db.easyMode = easy
	-- memory only: nothing of it in what's saved
	local saw
	local seen = {}
	local function Walk(t, path)
		if seen[t] then return end
		seen[t] = true
		for k, v in pairs(t) do
			if type(v) == "string" and (v:find("Zephyrine", 1, true) or v:find("Quilleran", 1, true)) then saw = path .. "." .. tostring(k) end
			if type(v) == "table" then Walk(v, path .. "." .. tostring(k)) end
		end
	end
	Walk(ns.db, "db")
	check(saw == nil, "nothing a friend sent is in what's saved: " .. tostring(saw))
	-- the badge at the end of the prompt (0.58.6, the player: "a little wifi icon"): shown while sharing, its tooltip
	-- says who's connected and what they share
	local badge
	for _, d in ipairs(UI.badges) do if d.id == "share" then badge = d end end
	if not ep:On() then ep:JoinGroup("default", "k", nil, true) end
	UI:Open("")
	check(badge and badge.shown() and badge.frame and badge.frame.shown ~= false and (UI.badgeRoom or 0) > 0,
		"the badge shows at the end of the prompt while sharing, the box made room for it")
	local lines = {}
	local tip = setmetatable({}, { __index = function(_, k)
		return function(_, a, b) lines[#lines + 1] = tostring(a) .. (k == "AddDoubleLine" and (" | " .. tostring(b)) or "") end
	end })
	SSH.BadgeTip(tip)
	local said = table.concat(lines, " / ")
	check(said:find("Quilleran | 2 items", 1, true) and said:find("Zephyrine | 1 item", 1, true) and said:find("Sharing | you: ", 1, true) and lines[#lines] == ".share off to disconnect" and lines[#lines - 1] == " ",
		"its tooltip: who's connected and how much: " .. said)
	-- (0.59.0, the player: "put the channel name in the wifi tooltip, default if it is default")
	check(said:find(L["Group"] .. " | default: ", 1, true) ~= nil, "...and the group, by name, with what you share in it: " .. said)
	-- (0.58.15, the player) its colour: friends connected, the accent; nobody and nothing under way, red
	SSH.BadgeColour(badge.frame)
	check(badge.frame.state == "up", "a friend connected: the accent")
	local friendsWas, peersWas = ep.friends, ep.peers
	ep.friends, ep.peers = {}, {}
	SSH.BadgeColour(badge.frame)
	check(badge.frame.state == "none", "nobody connected, nothing under way: red")
	ep.peers = { ["w:x"] = { key = "w:x", state = "hello", route = { kind = "whisper", target = "X" } } }
	SSH.BadgeColour(badge.frame)
	check(badge.frame.state == "connecting", "a hello under way: connecting (its arcs light in turn)")
	ep.peers = { ["w:x"] = { key = "w:x", state = "noanswer", name = "X", route = { kind = "whisper", target = "X" } } }
	SSH.BadgeColour(badge.frame)
	check(badge.frame.state == "none", "only a no answer: red")
	ep.friends, ep.peers = friendsWas, peersWas
	-- (0.58.13, the player) gone once something's typed, back when the prompt's empty again
	T.typeText("lin")
	check(badge.frame.shown == false and (UI.badgeRoom or 0) == 0, "typing: the badge goes, the box has its room back")
	T.key("BACKSPACE"); T.key("BACKSPACE"); T.key("BACKSPACE")
	check(badge.frame.shown ~= false and (UI.badgeRoom or 0) > 0, "the prompt empty again: the badge is back")
	-- the pop-out: Terminal's own tooltip, in the row tooltip's place; hover shows it, a click keeps it up
	local f = badge.frame
	-- (0.58.10, the player: "make sure the tooltips don't overlap") a row's tooltip up, then the badge pointed at
	UI:Open("@shared linen")
	T.FlushAll()
	UI:UpdateTooltip()
	local rowTip = _G.TerminalTooltip
	check(rowTip and rowTip.shown, "a row's tooltip is up")
	f.scripts.OnEnter(f)
	check(not rowTip.shown and _G.TerminalBadgeTip.shown, "the badge pointed at: its pop-out, the row's tooltip put away")
	UI:UpdateTooltip()
	check(not rowTip.shown, "...and it stays away while the pop-out's up")
	f.scripts.OnLeave(f)
	check(rowTip.shown and not _G.TerminalBadgeTip.shown, "pointer gone: the row's tooltip back")
	f.scripts.OnEnter(f)
	local pop = _G.TerminalBadgeTip
	check(pop and pop.shown and f.tipUp, "hovering the badge: its pop-out shows (Terminal's own tooltip)")
	f.scripts.OnLeave(f)
	check(not pop.shown, "...and goes when the pointer leaves")
	f.scripts.OnMouseUp(f)
	f.scripts.OnLeave(f)
	check(pop.shown and f.pinned, "a click keeps it up")
	f.scripts.OnMouseUp(f)
	check(not pop.shown, "...a second click puts it away")
	-- (0.58.9, the player) a few seconds on, it fades to a faint mark; pointed at, it's back
	local gt = _G.GetTime
	local later = gt() + badge.fade + 1
	_G.GetTime = function() return later end
	local function frames(n) for _ = 1, n do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.1) end end end
	frames(10)
	check(f.alpha and f.alpha < 0.3, "after some seconds: faded: " .. tostring(f.alpha))
	-- (review, 0.58.16: its per-frame script ran for good, faded and with nothing up)
	check(f.scripts.OnUpdate == nil, "faded with no pop-out: its per-frame script stops")
	f.scripts.OnEnter(f)
	check(f.alpha == 1 and f.scripts.OnUpdate ~= nil, "pointed at: back (and its per-frame script again)")
	f.scripts.OnLeave(f)
	frames(10)
	check(f.alpha == 1, "...and stays a while after")
	later = later + badge.fade + 1
	frames(10)
	check(f.alpha < 0.3 and f.scripts.OnUpdate == nil, "...then fades again, and stops")
	ns.UI.WakeBadge("share")
	check(f.alpha == 1 and f.scripts.OnUpdate ~= nil, "something new (a friend connects): back")
	later = later + badge.fade + 1
	frames(10)
	f.scripts.OnMouseUp(f) -- (pinned: the pop-out drawn again every second, faded or not)
	frames(10)
	check(f.scripts.OnUpdate ~= nil and f.tipUp, "a pop-out kept up: its per-frame script runs")
	f.scripts.OnMouseUp(f)
	frames(10)
	check(f.scripts.OnUpdate == nil, "...put away: stops again")
	_G.GetTime = gt
	UI:Hide()
	-- .ssh: who's connected (by character, never an account name)
	local status = table.concat(ns:FindCommand("ssh").run(""), " / ")
	check(status:find("Quilleran (items: 2)", 1, true) and status:find("Zephyrine (items: 1)", 1, true) and not status:find("|K", 1, true),
		".ssh says who's connected: " .. status)
	-- .ssh off: gone
	local out = ns:FindCommand("ssh").run("off")
	check(not ep:On() and next(ep.peers) == nil and #UI:Search("@shared linen") == 0, ".ssh off: " .. tostring(out[1]))
	check(not badge.shown(), "...the badge goes")
	local bye = 0
	for _, m in ipairs(sent) do if m.text == "4B" and m.target == "Quilleran" then bye = bye + 1 end end
	check(bye == 1 and bnSent[#bnSent].text == "4B", "...each friend was said goodbye to")
end

-- what's shared from this client: limited (the default) = this character's mats and consumables; all = everything,
-- alts and banks, gold
do
	local inst = C_Item.GetItemInfoInstant
	C_Item.GetItemInfoInstant = function(id)
		local class = ({ [2589] = 7, [6948] = 15, [118] = 0 })[id]
		return id, "x", "y", "", 1, class
	end
	local lim = SSH.Snapshot("limited")
	check(lim.items[2589] and not lim.items[6948] and lim.gold == nil, "limited: Linen Cloth (a mat), not the Hearthstone, no gold")
	check(next(SSH.Snapshot("consumables").items) == nil and SSH.Snapshot("mats").items[2589], "consumables: none here; mats: the cloth")
	local all = SSH.Snapshot("all")
	check(all.items[2589] and all.items[6948] and all.gold ~= nil, "all: everything, and gold")
	C_Item.GetItemInfoInstant = inst
	check(SSH.game.defaultMode == "limited", "limited unless you chose otherwise: " .. tostring(SSH.game.defaultMode))
	-- (0.59.0, the player) limited, mats and consumables: this character's bank too, as @stored has it, apart from its bags
	local real = ns.GetEntries
	ns.GetEntries = function(self, p)
		if p == ns.providers.stored then
			return { { itemID = 2589, holders = { { mine = true, where = "bank", count = 15 }, { mine = true, where = "bags", count = 5 },
				{ who = "Alt", where = "bank", count = 7 } } }, { itemID = 6948, holders = { { mine = true, where = "bank", count = 1 } } } }
		end
		return real(self, p)
	end
	C_Item.GetItemInfoInstant = function(id)
		local class = ({ [2589] = 7, [6948] = 15, [118] = 0 })[id]
		return id, "x", "y", "", 1, class
	end
	local withBank = SSH.Snapshot("limited")
	ns.GetEntries = real
	C_Item.GetItemInfoInstant = inst
	local bank, bags
	for i, pl in ipairs(withBank.places) do if pl.where == "k" then bank = i elseif pl.where == "b" then bags = i end end
	local cloth = withBank.items[2589] or {}
	check(bank and bags and cloth[bank] == 15 and cloth[bags] and cloth[bags] ~= 15 and not withBank.items[6948] and #withBank.places == 2,
		"limited: this character's bank too, as its own place (an alt's bank and the Hearthstone not): " .. tostring(cloth[bank]))
end

-- .ssh share, a short password
do
	local out = ns:FindCommand("ssh").run("password short")
	check(not ep:On() and out[1]:find("8", 1, true), "a password under 8 characters: refused: " .. tostring(out[1]))
	out = ns:FindCommand("ssh").run("share consumables")
	check(ep.defaultMode == "consumables" and SSH.Saved().mode == "consumables", ".ssh share consumables: " .. tostring(out[1]))
	out = ns:FindCommand("ssh").run("share bags")
	check(ep.defaultMode == "consumables", "...an unknown mode: unchanged")
	for _, m in ipairs({ "all", "mats", "limited" }) do
		ns:FindCommand("ssh").run(m)
		check(ep.defaultMode == m, ".ssh " .. m)
	end
	SSH.Saved().mode = nil
end

-- groups at the prompt (0.59.0, the player: ".share join group1 password1"; a level of sharing each)
do
	local share = ns:FindCommand("share")
	ep:Off()
	SSH.ForgetGroups()
	ep.tokens, ep.refillAt = SSH.BURST, 0
	share.run("join raid hunter2hunter2")
	T.FlushAll()
	local db = SSH.Saved()
	check(ep.groups.raid and db.groups.raid and db.groups.raid.key == ns.Crypto.Hex(ep.groups.raid.key) and db.groups.raid.mode == "limited",
		".share join raid: joined, its key remembered, sharing limited")
	local leak
	for k, v in pairs(db.groups) do if tostring(v.key):find("hunter2", 1, true) or k:find("hunter2", 1, true) then leak = k end end
	check(leak == nil, "...never the password")
	check(ns.MaskSecret(".share join raid hunter2") == ".share join raid *******" and ns.SecretLine(".shar join raid my words")
		and ns.SecretLine(".share join hunter2hunter2") and ns.MaskSecret(".share join raid") == ".share join raid",
		"the password after .share join <group> as *s, the group's name shown (a password typed without one: never kept either)")
	ns:RecordHistory(".share join raid hunter2hunter2")
	check(not tostring(ns:HistoryLines()[1]):find("hunter2", 1, true), "...and never in the history")
	local out = share.run("join all hunter2hunter2")
	check(not ep.groups.all and out[1]:find(".share join", 1, true), "a group named as a word .share takes: refused: " .. out[1])
	out = share.run("join bad! hunter2hunter2")
	check(not ep.groups["bad!"] and out[1]:find(".share join", 1, true), "a group's name that isn't one word of letters: refused")
	-- what you share in one group: .share raid all, or .share mats raid
	out = share.run("raid all")
	check(ep.groups.raid.mode == "all" and db.groups.raid.mode == "all", ".share raid all: " .. out[1])
	out = share.run("mats raid")
	check(ep.groups.raid.mode == "mats" and db.groups.raid.mode == "mats", ".share mats raid: " .. out[1])
	share.run("password hunter3hunter3")
	T.FlushAll()
	check(ep.groups.default and ep.groups.raid and ep.groups.default.mode == "limited", ".share password: the default group, beside raid")
	local status = table.concat(SSH.Status(ep), " / ")
	check(status:find("raid: ", 1, true) and status:find("default: ", 1, true), ".share lists each group and what it shares: " .. status)
	-- five at most
	for _, g in ipairs({ "g3", "g4", "g5" }) do share.run("join " .. g .. " hunter2hunter2") end
	T.FlushAll()
	out = share.run("join g6 hunter2hunter2")
	T.FlushAll()
	check(not ep.groups.g6 and out[1]:find("5", 1, true), "a sixth group: refused: " .. out[1])
	out = share.run("leave g3")
	check(not ep.groups.g3 and not db.groups.g3 and ep.groups.raid, ".share leave g3: left and forgotten, the others kept")
	out = share.run("leave nope")
	check(out[1]:find("nope", 1, true) ~= nil, ".share leave a group you're not in: said so")
	-- at login: every remembered group, one hello for them all
	ep:Off()
	ep.tokens, ep.refillAt = SSH.BURST, 0
	local n0 = #sent
	SSH.OnEvent("PLAYER_LOGIN")
	T.FlushAll()
	local hellos, tagsSaid = 0, nil
	for i = n0 + 1, #sent do
		if sent[i].text:find("^4H ") and sent[i].target == "Quilleran" then hellos = hellos + 1; tagsSaid = sent[i].text:match(",([%x%.]*)$") end
	end
	for _, m in ipairs(ep.queue) do
		if m.text:find("^4H ") and m.route.target == "Quilleran" then hellos = hellos + 1; tagsSaid = m.text:match(",([%x%.]*)$") end
	end
	local nGroups = 0
	for _ in pairs(ep.groups) do nGroups = nGroups + 1 end
	check(nGroups == 4 and ep.groups.raid.mode == "mats" and hellos == 1 and tagsSaid and #tagsSaid == 4 * 8 + 3,
		"at login: the four groups back, as they were, one hello naming them all: " .. nGroups .. ", " .. hellos .. ", " .. tostring(tagsSaid))
	-- rows: "raid linen" finds raid friends' linen; the tooltip says the groups
	ep.friends = {
		["quilleran@realm"] = { key = "w:quilleran", name = "Quilleran", claim = "quilleran@realm", last = GetTime(),
			route = { kind = "whisper", target = "Quilleran" }, items = { [2589] = 20 }, n = 1, groups = { raid = true },
			places = { { who = "Quilleran", where = "b" } }, entries = { [2589] = "0.k" } },
	}
	ns:Changed("shared")
	local easy = ns.db.easyMode
	ns.db.easyMode = false
	local rows = UI:Search("@shared raid linen")
	ns.db.easyMode = easy
	check(#rows == 1 and rows[1].owner == "Quilleran", "@shared raid linen: the raid friend's linen: " .. #rows)
	local lines = {}
	local tip = setmetatable({ AddLine = function(_, t) lines[#lines + 1] = tostring(t) end, AddDoubleLine = function(_, a, b) lines[#lines + 1] = tostring(a) .. " " .. tostring(b) end,
		SetText = function(_, t) lines[#lines + 1] = tostring(t) end, SetHyperlink = function() end }, { __index = function() return function() end end })
	if rows[1] then rows[1].tooltip(rows[1], tip) end
	check(table.concat(lines, " / "):find(L["Shared in: %s"]:format("raid"), 1, true), "...its tooltip says the group: " .. table.concat(lines, " / "))
	ep.friends = {}
	ns:Changed("shared")
	share.run("off")
	check(not ep:On() and next(SSH.Saved().groups) == nil, ".share off: every group left and forgotten")
end

-- (review, 0.59.0) groups at the prompt: what the review found
do
	-- (a quick stand-in for SHA-256 here: every join makes a key, and the harness's SHA-256 is plain arithmetic)
	local shaWas = ns.Crypto.SHA256
	ns.Crypto.SHA256 = function(m)
		local a, b = 7, 13
		for i = 1, #m do local c = m:byte(i); a = (a * 31 + c) % 2147483629; b = (b * 37 + c * 3 + i) % 2147483587 end
		local out = {}
		for i = 1, 8 do out[i] = string.char(a % 256, b % 256, math.floor(a / 256) % 256, math.floor(b / 256) % 256); a, b = math.floor(a / 7) + b + i, math.floor(b / 5) + a end
		return table.concat(out)
	end
	local share = ns:FindCommand("share")
	local slice = SSH.KDF_SLICE
	SSH.KDF_SLICE = 1 -- (a password made over frames, as in the game: a frame or more to wait)
	ep:Off()
	SSH.ForgetGroups()
	-- leaving a group whose password is still being made: it's never joined
	share.run("join raid hunter2hunter2")
	local out = share.run("leave raid")
	T.FlushAll()
	check(not ep.groups.raid and not SSH.Saved().groups.raid, ".share leave while its password was being made: never joined: " .. out[1])
	-- Enter on a password being typed runs what's typed, never a completion of its last word
	UI:Hide(); UI:Open("")
	T.typeText(".share join raid correct horse at")
	T.FlushAll()
	T.key("ENTER")
	if T.F.scripts.OnKeyUp then T.F.scripts.OnKeyUp(T.F, "ENTER") end
	T.FlushAll()
	local want
	SSH.Derive("correct horse at", function(k) want = k end, nil, "raid")
	check(ep.groups.raid and ep.groups.raid.key == want, "Enter on .share join raid <words>: the words typed, not a completion's (\"mats\")")
	UI:Hide()
	-- five at most, those still being made counted
	for _, g in ipairs({ "g2", "g3", "g4", "g5" }) do share.run("join " .. g .. " hunter2hunter2") end
	out = share.run("join g6 hunter2hunter2")
	T.FlushAll()
	local n = 0
	for _ in pairs(ep.groups) do n = n + 1 end
	check(n == 5 and not ep.groups.g6, "a sixth while the others' passwords were being made: refused: " .. n)
	-- your only group's password changed while another group's is being made: both end up joined
	ep:Off()
	SSH.ForgetGroups()
	share.run("join raid hunter2hunter2")
	T.FlushAll()
	share.run("join raid hunter3hunter3")
	share.run("join guild hunter4hunter4")
	T.FlushAll()
	check(ep.groups.raid and ep.groups.guild, "another password for your only group, another group joined meanwhile: both joined")
	-- @stored's records changing (this character's bank): what you share sent again
	ep.snaps = { limited = { text = "old" } }
	ns:Changed("stored")
	check(next(ep.snaps) == nil, "@stored changed: what you share made again and sent")
	-- .share raid alone: what raid shares; .share leave alone: which group
	out = share.run("raid")
	check(out[1]:find("raid", 1, true) and not out[1]:find(".share limited (the default)", 1, true), ".share raid: what raid shares: " .. out[1])
	out = share.run("leave")
	check(out[1]:find(".share leave <group>", 1, true) ~= nil, ".share leave alone: which group: " .. out[1])
	-- a group's name in any language's letters
	check(SSH.GroupName("рейд") == "рейд" and SSH.GroupName("公会") == "公会" and not SSH.GroupName(string.rep("я", 17))
		and SSH.GroupName(string.rep("я", 16)), "a group's name in any language's letters, 16 at most")
	-- what's remembered, broken by hand: dropped, no error
	ep:Off()
	_G.TerminalShareDB = { groups = { raid = 5, [1] = { key = string.rep("a", 64) }, ok = { key = string.rep("b", 64), mode = "mats", kdf = SSH.KDF_ID } } }
	local fine = pcall(share.run, "all")
	SSH.OnEvent("PLAYER_LOGIN")
	T.FlushAll()
	check(fine and ep.groups.ok and not ep.groups.raid and SSH.Saved().groups.raid == nil, "broken entries in what's remembered: dropped, the rest used")
	share.run("off")
	ns.Crypto.SHA256 = shaWas
	SSH.KDF_SLICE = slice
end

for _, k in ipairs(names) do _G[k] = saved[k] end -- (those that weren't there go again)
C_Item.GetItemNameByID = savedNameByID
ns.Crypto.HMAC = hmacWas
SSH.KDF_ROUNDS = roundsWas
SSH.Forget()
ep:Off()
ns:Changed("shared")
_G.TerminalShareDB = nil
ep.env.nonce = nonceWas
