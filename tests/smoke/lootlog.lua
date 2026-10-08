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

local cloth = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r"
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
	check(#ns.db.lootLog == 3 and ns.db.lootLog[1].src == "both", "the history's drop and its loot line: one")
	now = now + 100
	LL.OnEvent("CHAT_MSG_LOOT", "You receive loot: " .. cloth .. "x2.")
	now = now + 5
	LL.OnEvent("CHAT_MSG_LOOT", "You receive loot: " .. cloth .. ".")
	check(#ns.db.lootLog == 5, "two stacks looted a moment apart: both kept")
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
	check(ns.Filters.Parse("q:uncommon") ~= nil, "(filters work on its rows: they carry the item)")
	for i = 1, LL.MAX + 5 do LL.Add("|Hitem:" .. (5000 + i) .. "|h[X]|h", "Bob", 1) now = now + 20 end
	check(#ns.db.lootLog == LL.MAX, "only the newest " .. LL.MAX .. " are kept")
	ns:FindCommand("lootlog").run("clear")
	check(#ns.db.lootLog == 0, ".lootlog clear")
end

_G.LOOT_ITEM_SELF, _G.LOOT_ITEM_SELF_MULTIPLE, _G.LOOT_ITEM, _G.LOOT_ITEM_MULTIPLE = save.self, save.selfm, save.item, save.itemm
_G.LOOT_ROLL_WON, _G.LOOT_ROLL_YOU_WON, _G.time, _G.GetRealZoneText, _G.C_LootHistory = save.won, save.youwon, save.time, save.zone, save.hist
LL.ResetPatterns()
