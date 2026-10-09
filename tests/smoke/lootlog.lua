-- @drop (@lootlog): what dropped and who got it, from the chat's loot lines and the game's loot history (0.43.10)
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local LL = ns.LootLog

local save = { self = _G.LOOT_ITEM_SELF, selfm = _G.LOOT_ITEM_SELF_MULTIPLE, item = _G.LOOT_ITEM, itemm = _G.LOOT_ITEM_MULTIPLE,
	won = _G.LOOT_ROLL_WON, youwon = _G.LOOT_ROLL_YOU_WON, time = _G.time, zone = _G.GetRealZoneText, hist = _G.C_LootHistory }
_G.LOOT_ITEM_SELF = "You receive loot: %s."
_G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
_G.LOOT_ITEM = "%s receives loot: %s."
_G.LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
_G.LOOT_ROLL_WON = "%s won: %s"
_G.LOOT_ROLL_YOU_WON = "You won: %s"
LL.ResetPatterns()
local now = 1000000
_G.time = function() return now end
_G.GetRealZoneText = function() return "Wailing Caverns" end
ns.db.lootLog = {}

local cloth = "|cff1eff00|Hitem:2589::::::::|h[Linen Cloth]|h|r" -- (green here: whites aren't logged)
local belt = "|cff1eff00|Hitem:6505::::::::|h[Crescent Belt]|h|r"
do
	local link, who, n = LL.Parse("You receive loot: " .. cloth .. "x3.")
	check(link == cloth and n == 3 and who ~= "Bob", "your own loot line, several: " .. tostring(link) .. " " .. tostring(n))
	link, who, n = LL.Parse("Bob receives loot: " .. belt .. ".")
	check(link == belt and who == "Bob" and n == 1, "someone else's loot line")
	link, who = LL.Parse("Bob won: " .. belt)
	check(link == belt and who == "Bob", "a roll won")
	check(LL.Parse("You receive item: " .. cloth .. ".") == nil and LL.Parse("Bob says hi") == nil, "other lines aren't loot")
	-- a language with its arguments swapped ("%2$s ... %1$s")
	local p, args = LL.Pattern("Beute %2$s für %1$s.")
	local a, b = ("Beute X für Bob."):match(p)
	check(a == "X" and b == "Bob" and args[1] == 2 and args[2] == 1, "numbered arguments keep their places")
	-- only what's worth rolling for (0.43.26): grey and white drops aren't kept, whoever got them
	local grey = "|cff9d9d9d|Hitem:3300::::::::|h[Rabbit's Foot]|h|r"
	local white = "|cffffffff|Hitem:2592::::::::|h[Wool Cloth]|h|r"
	local newer = "|cnIQ1:|Hitem:2593::::::::|h[Flask of Port]|h|r"
	LL.OnEvent("CHAT_MSG_LOOT", "You receive loot: " .. grey .. ".")
	LL.OnEvent("CHAT_MSG_LOOT", "Bob receives loot: " .. white .. "x2.")
	LL.OnEvent("CHAT_MSG_LOOT", "Bob won: " .. newer)
	check(#ns.db.lootLog == 0, "greys and whites aren't logged (old and new link colours)")
	check(LL.Quality(belt) == 2 and LL.Quality("|cnIQ4:|Hitem:1|h[X]|h|r") == 4 and LL.Quality(grey) == 0, "quality read from the link")
	ns.db.lootLog = { { t = now, id = 2592, link = white, who = "Bob" } } -- (kept before 0.43.26)
	ns.providers.lootlog._dirty = true
	check(#ns:GetEntries(ns.providers.lootlog) == 0 and #ns.db.lootLog == 0, "whites logged before are dropped")
	-- recorded: newest first; the win and its loot line a moment later are one drop
	LL.OnEvent("CHAT_MSG_LOOT", "Bob won: " .. belt)
	now = now + 2
	LL.OnEvent("CHAT_MSG_LOOT", "Bob receives loot: " .. belt .. ".")
	now = now + 60
	LL.OnEvent("CHAT_MSG_LOOT", "You receive loot: " .. cloth .. "x2.")
	check(#ns.db.lootLog == 2 and ns.db.lootLog[1].id == 2589 and ns.db.lootLog[2].who == "Bob", "two drops kept, newest first")
	-- the game's loot history: the boss
	_G.C_LootHistory = {
		GetSortedInfoForDrop = function() return { itemHyperlink = belt, winner = { playerName = "Bob" } } end,
		GetInfoForEncounter = function() return { encounterName = "Lord Cobrahn" } end,
	}
	LL.OnEvent("LOOT_HISTORY_UPDATE_DROP", 1, 1)
	check(#ns.db.lootLog == 3 and ns.db.lootLog[1].from == "Lord Cobrahn", "the loot history's drop, with its boss")
	-- two loot lines of the same thing are two drops (farming); the history's drop then its loot line are one
	now = now + 3
	LL.OnEvent("CHAT_MSG_LOOT", "Bob receives loot: " .. belt .. ".")
	check(#ns.db.lootLog == 3 and ns.db.lootLog[1].src == "history+loot", "the history's drop and its loot line: one")
	now = now + 100
	LL.OnEvent("CHAT_MSG_LOOT", "You receive loot: " .. cloth .. "x2.")
	now = now + 5
	LL.OnEvent("CHAT_MSG_LOOT", "You receive loot: " .. cloth .. ".")
	check(#ns.db.lootLog == 5, "two stacks looted a moment apart: both kept")
	do -- (0.44.10) each way a drop is told counts once per drop
		local keep = ns.db.lootLog
		ns.db.lootLog = {}
		now = now + 100
		LL.OnEvent("CHAT_MSG_LOOT", "Bob won: " .. belt)
		LL.OnEvent("CHAT_MSG_LOOT", "Bob receives loot: " .. belt .. ".")
		LL.OnEvent("CHAT_MSG_LOOT", "Bob won: " .. belt)
		LL.OnEvent("CHAT_MSG_LOOT", "Bob receives loot: " .. belt .. ".")
		check(#ns.db.lootLog == 2, "two of one green won by Bob, each a win and its loot line: two drops: " .. #ns.db.lootLog)
		now = now + 100
		LL.OnEvent("LOOT_HISTORY_UPDATE_DROP", 7, 3)
		LL.OnEvent("LOOT_HISTORY_UPDATE_DROP", 7, 3)
		check(#ns.db.lootLog == 3, "the loot history updated again for a drop logged already: still one: " .. #ns.db.lootLog)
		ns.db.lootLog = keep
	end
	table.remove(ns.db.lootLog, 1); table.remove(ns.db.lootLog, 1)
	-- the list
	now = now + 60
	local p = ns.providers.lootlog
	p._dirty = true
	local rows = ns:GetEntries(p)
	check(#rows == 3 and rows[2].name == "Linen Cloth x2" and rows[2].detail:find("you", 1, true) and rows[2].detail:find(" min ago", 1, true) and rows[1].detail:find("Lord Cobrahn", 1, true),
		"rows: name, count, who, when: " .. tostring(rows[2] and rows[2].detail))
	local res = UI:Search("@lootlog bob")
	local names = {}
	for _, e in ipairs(res) do names[#names + 1] = e.name end
	check(#res == 2 and res[1].name == "Crescent Belt" and res[1].detail:find("Lord Cobrahn", 1, true), "@lootlog bob: Bob's drops, newest first: " .. table.concat(names, ", "))
	-- @drop is its name (0.43.19; AtlasLoot's @loot had taken "drop"), @dropped too
	check(ns:ResolveProvider("drop") == p and ns:ResolveProvider("dropped") == p and ns:ResolveProvider("lootlog") == p,
		"@drop / @dropped / @lootlog: the loot log")
	check(#UI:Search("@drop bob") == 2, "@drop bob: Bob's drops")
	check(UI:ResultText(res[1]):find("^@drop "), "a row written into the prompt says @drop: " .. tostring(UI:ResultText(res[1])))
	-- asked in plain words (0.43.22): "what dropped", "what drops did we get", "what did i loot", "what did bob get"
	local LLQ = function(t) local q = LL.Question(t) return q and (q.who or "all") or nil end
	check(LLQ("what dropped") == "all" and LLQ("what drops did we get") == "all" and LLQ("what did we loot") == "all"
		and LLQ("recent drops") == "all" and LLQ("loot log") == "all", "loot questions: everyone's drops")
	check(LLQ("what did i loot") == "me" and LLQ("my drops") == "me" and LLQ("what did i get") == "me", "loot questions: yours")
	check(LLQ("what did bob get") == "Bob" and LLQ("what did bob loot") == "Bob", "loot questions: someone in the log")
	check(LLQ("boss loot") == nil and LLQ("boss drops") == nil and LLQ("the loot") == nil and LLQ("item drops") == nil
		and LLQ("show loot") == nil and LLQ("all drops") == nil, "a loot word alone with search words stays a search (0.43.27)")
	check(LLQ("loot") == nil and LLQ("molten core loot") == nil and LLQ("what did zed get") == nil and LLQ("@drop bob") == nil
		and LLQ("what drops thorium bar") == nil and LLQ("what killed me") == nil and LLQ("where should i level") == nil, "other searches stay searches")
	-- a looter from another realm: asked by name, with or without the realm
	table.insert(ns.db.lootLog, { t = now, id = 6505, link = belt, who = "Zed-Stormrage" })
	check(LLQ("what did zed get") == "Zed-Stormrage" and LLQ("what did zed stormrage get") == "Zed-Stormrage"
		and LLQ("what did zed-stormrage get") == "Zed-Stormrage", "a looter from another realm, with or without the realm")
	table.remove(ns.db.lootLog, #ns.db.lootLog)
	ns.db.easyMode = true
	res = UI:SearchText("what drops did we get")
	check(#res == 3 and res[1].kind == "lootlog" and UI.answerNote == "Drops, newest first", "Simple mode: the loot log answers: " .. tostring(UI.answerNote))
	res = UI:SearchText("what did bob get")
	check(#res == 2 and res[1].name == "Crescent Belt" and UI.answerNote == "Bob's drops, newest first", "someone's drops: " .. #res)
	res = UI:SearchText("what did i loot")
	check(#res == 1 and res[1].name == "Linen Cloth x2", "your drops: " .. #res)
	check(ns.Easy.ToAdvanced("what dropped") == "@drop " and ns.Easy.ToAdvanced("what did i loot") == "@drop you "
		and ns.Easy.ToAdvanced("what did bob get") == "@drop bob ", "Alt+`: their Advanced forms: " .. ns.Easy.ToAdvanced("what did i loot"))
	ns.db.easyMode = false
	check(ns.Filters.Parse("q:uncommon") ~= nil, "(filters work on its rows: they carry the item)")
	for i = 1, LL.MAX + 5 do LL.Add("|Hitem:" .. (5000 + i) .. "|h[X]|h", "Bob", 1) now = now + 20 end
	check(#ns.db.lootLog == LL.MAX, "only the newest " .. LL.MAX .. " are kept")
	ns:FindCommand("lootlog").run("clear")
	check(#ns.db.lootLog == 0, ".lootlog clear")
end

_G.LOOT_ITEM_SELF, _G.LOOT_ITEM_SELF_MULTIPLE, _G.LOOT_ITEM, _G.LOOT_ITEM_MULTIPLE = save.self, save.selfm, save.item, save.itemm
_G.LOOT_ROLL_WON, _G.LOOT_ROLL_YOU_WON, _G.time, _G.GetRealZoneText, _G.C_LootHistory = save.won, save.youwon, save.time, save.zone, save.hist
LL.ResetPatterns()

-- @loot before @lootlog in the kinds list and for "@loo", though AtlasLoot's list registers after the loot log (0.43.24)
do
	local hadLoot = ns.providers.loot
	if not hadLoot then ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot", "atlasloot" }, collect = function() return {} end }) end
	local li, ll
	for i, id in ipairs(ns.providerOrder) do if id == "loot" then li = i elseif id == "lootlog" then ll = i end end
	check(hadLoot or (li and ll and li > ll), "(the loot list registered after the loot log, as in the game)")
	ns.db.easyMode = false
	UI:Open("")
	T.typeText("@loo")
	local r = UI.Results()
	check(r[1] and r[1].name == "@loot" and r[2] and r[2].name == "@lootlog", "@loo: @loot first, then @lootlog: "
		.. tostring(r[1] and r[1].name) .. ", " .. tostring(r[2] and r[2].name))
	check(ns:ResolveProvider("loo") == ns.providers.loot and ns:ResolveProvider("lootl") == ns.providers.lootlog,
		"\"@loo\" searches the loot, \"@lootl\" the loot log")
	UI:Hide()
	if not hadLoot then
		ns.providers.loot = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "loot" then table.remove(ns.providerOrder, i) end end
		ns:AliasesChanged()
	end
end
