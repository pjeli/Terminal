-- Terminal: Share in this client (0.58.1): the game's events and calls as Share.lua reads them, @shared in searches,
-- .ssh at the prompt, and what's never kept (the password line; anything a friend sent).
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
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
		and not ns.SecretLine(".shared password"), "the password line is told apart (.share and .ssh)")
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
	check(ep.key ~= nil, ".ssh password, Enter: the key is set: " .. tostring(ep.key ~= nil))
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
	check(_G.TerminalShareDB and _G.TerminalShareDB.key == ns.Crypto.Hex(ep.key), "the key is remembered, not the password")
	local h = ns:HistoryLines()
	check(not (h[1] and h[1]:find("ssh", 1, true)), "not in the history (Up): " .. tostring(h[1]))
	-- hello went to the friend by whisper and the Battle.net friend's character by game data, prefix TermSSH
	local toFriend, toBN = false, false
	for _, m in ipairs(sent) do
		if m.prefix == "TermSSH" and m.chan == "WHISPER" and m.target == "Quilleran" and m.text:find("^1H ") then toFriend = true end
		check(not m.text:find("hunter2", 1, true), "the password is never sent")
	end
	for _, m in ipairs(bnSent) do if m.id == 77 and m.prefix == "TermSSH" and m.text:find("^1H ") then toBN = true end end
	check(toFriend and toBN, "hello to the friend list (whisper) and the Battle.net friend's character (game data)")
end

-- at login: the remembered key in use, a few seconds in, everyone said hello to
do
	local hex = _G.TerminalShareDB.key
	ep:Off()
	ep.key = nil
	local n, nb = #sent, #bnSent
	SSH.OnEvent("PLAYER_LOGIN")
	check(ep.key == nil, "not at once: friends and guild are read first")
	T.FlushAll()
	check(ep.key and ns.Crypto.Hex(ep.key) == hex, "a few seconds in: the remembered key")
	check(#sent > n and #bnSent > nb and sent[#sent].text:find("^1H "), "...and hello to everyone")
	-- .ssh off forgets it
	ns:FindCommand("ssh").run("off")
	check(_G.TerminalShareDB.key == nil and ep.key == nil, ".ssh off: forgotten")
	SSH.OnEvent("PLAYER_LOGIN")
	T.FlushAll()
	check(ep.key == nil, "...and not used at the next login")
	-- (back as it was for the tests after: the key set)
	_G.TerminalShareDB.key = hex
	SSH.OnEvent("PLAYER_LOGIN")
	T.FlushAll()
	ep.peers, ep.queue, ep.hellos, ep.tokens, ep.refillAt = {}, {}, {}, SSH.BURST, 0 -- (its hellos unanswered: the tests after start clean)
end

-- who's heard
do
	local n, nb0 = #sent, #bnSent
	SSH.OnEvent("CHAT_MSG_ADDON", "OtherAddon", "1H 00000000000000aa,quilleran@realm", "WHISPER", "Quilleran")
	check(#sent == n, "another addon's prefix: ignored")
	SSH.OnEvent("CHAT_MSG_ADDON", "TermSSH", "1H 00000000000000aa,eve@realm", "WHISPER", "Eve")
	check(#sent == n, "a stranger's whisper: ignored, no answer")
	SSH.OnEvent("CHAT_MSG_ADDON", "TermSSH", "1H 00000000000000aa,quilleran@realm", "PARTY", "Quilleran")
	check(#sent == n, "a party message: never read")
	_G.issecretvalue = function(v) return v == "SECRET" end
	SSH.OnEvent("CHAT_MSG_ADDON", "TermSSH", "SECRET", "WHISPER", "Quilleran")
	SSH.OnEvent("CHAT_MSG_ADDON", "TermSSH", "1H 00000000000000aa,quilleran@realm", "WHISPER", "SECRET")
	check(#sent == n, "secret fields (chat locked): ignored")
	_G.issecretvalue = saved.issecretvalue
	SSH.OnEvent("BN_CHAT_MSG_ADDON", "TermSSH", "1H 00000000000000aa,mal@realm", "WHISPER", 78)
	check(#bnSent == nb0, "Battle.net data from a game account that isn't a friend's: ignored")
	-- a friend's hello: challenged, by whisper, to the name the server gave
	ep.peers = {}
	SSH.OnEvent("CHAT_MSG_ADDON", "TermSSH", "1H 00000000000000aa,quilleran@realm", "WHISPER", "Quilleran")
	check(#sent == n + 1 and Last().text:find("^1C 00000000000000aa,%x+,") and Last().target == "Quilleran" and Last().chan == "WHISPER",
		"a friend's hello: challenged: " .. tostring(Last().text))
	-- a Battle.net friend's character: by game data
	SSH.OnEvent("BN_CHAT_MSG_ADDON", "TermSSH", "1H 00000000000000ab,zephyrine@realm", "WHISPER", 77)
	check(bnSent[#bnSent].id == 77 and bnSent[#bnSent].text:find("^1C 00000000000000ab,"), "a Battle.net friend's: challenged by game data")
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
	friend.mode, friend.key = "all", key
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
	check(d:find("friend Zephyrine (all): items 2", 1, true), ".ssh debug says so: " .. d)
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
			parts = { [2589] = { { place = 1, n = 5 }, { place = 2, n = 15 } }, [118] = { { place = 1, n = 3 } } } },
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
	check(e and e.detail == "x20" .. ns.DETAIL_SEP .. "Quilleran", "...and their name: " .. tostring(e and e.detail))
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
	ep.key = ep.key or "k"
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
	for _ = 1, 10 do f.scripts.OnUpdate(f, 0.1) end
	check(f.alpha and f.alpha < 0.3, "after some seconds: faded: " .. tostring(f.alpha))
	f.scripts.OnEnter(f)
	check(f.alpha == 1, "pointed at: back")
	f.scripts.OnLeave(f)
	for _ = 1, 10 do f.scripts.OnUpdate(f, 0.1) end
	check(f.alpha == 1, "...and stays a while after")
	later = later + badge.fade + 1
	for _ = 1, 10 do f.scripts.OnUpdate(f, 0.1) end
	check(f.alpha < 0.3, "...then fades again")
	ns.UI.WakeBadge("share")
	check(f.alpha == 1, "something new (a friend connects): back")
	_G.GetTime = gt
	UI:Hide()
	-- .ssh: who's connected (by character, never an account name)
	local status = table.concat(ns:FindCommand("ssh").run(""), " / ")
	check(status:find("Quilleran (items: 2)", 1, true) and status:find("Zephyrine (items: 1)", 1, true) and not status:find("|K", 1, true),
		".ssh says who's connected: " .. status)
	-- .ssh off: gone
	local out = ns:FindCommand("ssh").run("off")
	check(ep.key == nil and next(ep.peers) == nil and #UI:Search("@shared linen") == 0, ".ssh off: " .. tostring(out[1]))
	check(not badge.shown(), "...the badge goes")
	local bye = 0
	for _, m in ipairs(sent) do if m.text == "1B" and m.target == "Quilleran" then bye = bye + 1 end end
	check(bye == 1 and bnSent[#bnSent].text == "1B", "...each friend was said goodbye to")
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
	check(SSH.game.mode == "limited", "limited unless you chose otherwise: " .. tostring(SSH.game.mode))
end

-- .ssh share, a short password
do
	local out = ns:FindCommand("ssh").run("password short")
	check(ep.key == nil and out[1]:find("8", 1, true), "a password under 8 characters: refused: " .. tostring(out[1]))
	out = ns:FindCommand("ssh").run("share consumables")
	check(ep.mode == "consumables" and ns.db.sshShare == "consumables", ".ssh share consumables: " .. tostring(out[1]))
	out = ns:FindCommand("ssh").run("share bags")
	check(ep.mode == "consumables", "...an unknown mode: unchanged")
	for _, m in ipairs({ "all", "mats", "limited" }) do
		ns:FindCommand("ssh").run(m)
		check(ep.mode == m, ".ssh " .. m)
	end
	ns.db.sshShare = nil
end

for _, k in ipairs(names) do _G[k] = saved[k] end -- (those that weren't there go again)
C_Item.GetItemNameByID = savedNameByID
ns.Crypto.HMAC = hmacWas
SSH.KDF_ROUNDS = roundsWas
SSH.Forget()
ep:Off()
ns:Changed("shared")
_G.TerminalShareDB = nil
