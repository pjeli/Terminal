-- .console (0.67.8, built on branch console-dev): Terminal_Extras/Console/FS.lua (lists as directories, rows as files), Shell.lua (the shell: words,
-- pipes, the commands) and Console.lua (panes, tiling, apps in panes, stepping out, zen always on).
local T = ...
local ns, check = T.ns, T.check
local FS, SH, C, Panel = ns.ConsoleFS, ns.Shell, ns.Console, ns.Panel

print("[console: the file system and the shell]")

local saved = { providers = ns.providers, order = ns.providerOrder }
ns.providers, ns.providerOrder = {}, {}
local ROWS = {
	{ name = "Linen Cloth", key = 1, detail = "x20  Backpack", text = "cloth trade goods", count = 20, level = 5, itemID = 2589,
		tooltip = function(e, t) t:SetText(e.name); t:AddLine("Stamina +5", 0, 1, 0); t:AddLine("Use: Heals 10") end },
	{ name = "Linen Cloth", key = 2, tip = "the second one" },
	{ name = "Heavy/Rope", key = 3, tip = "a rope", wcont = 1, wx = 300, wy = 0, zone = "Elwynn Forest" },
	{ name = "Copper Bar", key = 4, tip = "Smelted from copper", wcont = 1, wx = 30, wy = 40, zone = "Elwynn Forest", ui = 1429, px = 40, py = 50 },
}
ns:RegisterProvider("consoletest", { label = "Console test", aliases = { "ctest" }, color = "ff66ccff",
	collect = function() local out = {} for i, r in ipairs(ROWS) do out[i] = r end return out end })
ns:AliasesChanged()
FS.Forget()
ns:RegisterCommand("ctestcmd", { desc = "a test command", run = function(args)
	ns:Print("printed " .. args)
	ns:Output({ "out line" })
	return { "ret line" }
end })

local out = {}
local sh = SH.Session({ print = function(l) out[#out + 1] = FS.Strip(l) end })
local function Run(line)
	out = {}
	local status = SH.Run(sh, line)
	return out, status
end
local function Has(lines, text)
	for _, l in ipairs(lines) do if l:find(text, 1, true) then return true end end
	return false
end

local ok, err = pcall(function()
	local o = Run("ls")
	check(Has(o, "ctest/") and Has(o, "bin/") and Has(o, "tmp/"), "ls at the root: the lists and the system's directories: " .. table.concat(o, ","))
	Run("cd ctest")
	o = Run("pwd")
	check(o[1] == "/ctest", "cd into a list: " .. tostring(o[1]))
	o = Run("ls")
	check(#o == 4 and o[1] == "Copper Bar" and o[4] == "Linen Cloth~2" and Has(o, "Heavy\226\136\149Rope"),
		"its rows as files, sorted, a name twice told apart, no / in a name: " .. table.concat(o, ","))
	-- ls -l: POSIX-like columns, one word each, the name last; field, where and sort read them
	local I = ns.Integrations
	local realHere = I.Here
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	o = Run("ls -l")
	check(o[1] == "-r---n-\t-\t-\t-\t50yd\tElwynn_Forest\tCopper Bar", "ls -l: the columns some file has, parted by tabs: " .. tostring(o[1]))
	check(Has(o, "-r-----\titem:2589\t5\t20\t-\t-\tLinen Cloth"), "ls -l: a level and a count, - where none: " .. table.concat(o, " / "))
	local all = Run("ls -l -o all")
	check(all[1] == "-r---n-\tctest\t-\t-\t-\t-\t-\t50yd\tElwynn_Forest\tCopper Bar", "ls -l -o all: every column: " .. tostring(all[1]))
	check(Run("ls -l /ctest/Copper\\ Bar")[1] == all[1] and Run("ls -l 'Copper Bar'")[1] == all[1],
		"ls -l on one file: every column")
	check(Run("ls -l -o dist,zone")[1] == "50yd\tElwynn_Forest\tCopper Bar", "ls -l -o: the columns asked for, the name last")
	o = Run("ls -l -o name | where dist<100 | field kind dist name")
	check(#o == 1 and o[1] == "ctest  50yd  Copper Bar", "columns not shown are still read: where, field: " .. table.concat(o, " / "))
	check(#Run("ls -l -o lvl | grep -i copper | where zone~elwynn") == 1, "and still after grep")
	o, err = Run("ls -l -o bogus")
	check(err == 2 and Has(o, "no column 'bogus'"), "ls -l -o with a column there isn't")
	local long = FS.ParseLong(all[1])
	check(FS.ParseLong(all[1]) == long and FS.ParseLong("x") == nil and FS.ParseLong(all[1]) ~= long,
		"(speed) a line read back once for every column asked of it in a row")
	check(long and long.dist == "50yd" and long.name == "Copper Bar" and long[9] == "Elwynn_Forest" and long.id == "-", "an ls -l line read back")
	o = Run("ls -lN | field dist name")
	check(o[1] == "50yd  Copper Bar" and o[2] == "300yd  Heavy\226\136\149Rope" and o[3] == "-  Linen Cloth",
		"ls -N nearest first, field picks columns: " .. table.concat(o, " / "))
	o = Run("ls -l | where dist<100")
	check(#o == 1 and o[1]:find("Copper Bar", 1, true), "where dist<100: " .. table.concat(o, " / "))
	check(#Run("ls -l | where dist>=50 zone~elwynn") == 2 and #Run("ls -l | where lvl>=5 count=20") == 1
		and #Run("ls -l | where dist!=50") == 3, "where: several conditions, all must pass; none = != passes")
	o = Run("ls -l | sort -n -r -k dist | field name")
	check(o[1] == "Heavy\226\136\149Rope" and o[2] == "Copper Bar" and #o == 4, "sort -k dist: no number last, either way: " .. table.concat(o, " / "))
	check(Run("echo a b c | field 2 -1")[1] == "b  c", "field on any line: its words")
	o, err = Run("ls | field dist")
	check(err == 1 and Has(o, "needs ls -l"), "a column by name needs ls -l's lines")
	o = Run("ls -l | where id~item: | field id")
	check(#o == 1 and o[1] == "item:2589", "the id column: the game's number, where and field read it: " .. table.concat(o, " / "))
	local cells = ns.Console.Cells("a\tb\tc")
	check(cells and #cells == 3 and cells[3] == "c" and ns.Console.Cells("plain") == nil, "a tabbed line's cells, for lining up")
	local cols = FS.Columns({ name = "loot" }, { kind = "loot", name = "Shadowfang", detail = "Varimathras  Ruins of Lordaeron" }, "Shadowfang")
	check(cols[5] == "Varimathras" and cols[9] == "Ruins_of_Lordaeron", "a loot row: its boss as the title, its instance as the zone: " .. table.concat(cols, " "))
	check(Has(Run("ls -l /"), "drx----\t"), "ls -l /: the lists as directories, in the same columns")
	-- NPCs: their roles as a column, what they sell in their files (read once, all of Questie's items)
	local realQD = ns.QuestieData.DB
	ns.QuestieData.DB = function()
		return { ItemIds = function() return { 2512, 2516, 4470 } end, QueryItemSingle = function(id, field)
			if field == "name" then return ({ [2512] = "Rough Arrow", [2516] = "Light Shot", [4470] = "Simple Wood" })[id] end
			if field == "vendors" then return ({ [2512] = { 100 }, [2516] = { 100, 101 } })[id] end
		end }
	end
	FS.sold = nil
	ns:RegisterProvider("npc", { label = "NPC", aliases = { "npc" }, collect = function() return {
		{ kind = "npc", name = "Ammo Vendor", key = 100, wcont = 1, wx = 0, wy = 80, roles = { VENDOR = true, REPAIR = true } },
		{ kind = "npc", name = "Gun Vendor", key = 101, sub = "Reagent Vendor", wcont = 1, wx = 0, wy = 20, roles = { VENDOR = true } },
		{ kind = "npc", name = "Innkeeper Farley", key = 102, wcont = 1, wx = 0, wy = 10, roles = { INNKEEPER = true } },
		{ kind = "npc", name = "Thrall", key = 200, zone = "Orgrimmar", wcont = 1, wx = 0, wy = 500, roles = { TRAINER = true } },
		{ kind = "npc", name = "Orgrimmar Grunt", key = 201, zone = "Orgrimmar", wcont = 1, wx = 0, wy = 600 },
	} end })
	ns:AliasesChanged()
	FS.Forget()
	o = Run("ls -lN /npc | where role~repair | field role name")
	check(#o == 1 and o[1] == "repair,vendor  Ammo Vendor", "the role column: where role~repair finds the repairer: " .. table.concat(o, " / "))
	check(Run("ls -lN /npc | where role~innkeeper | head -1 | field name")[1] == "Innkeeper Farley", "nearest innkeeper by browsing")
	o = Run("ls /npc")
	check(o[1] == "Orgrimmar/" and not Has(o, "Thrall"), "/npc: a folder per zone first: " .. table.concat(o, " / "))
	o = Run("ls /npc/orgrimmar")
	check(#o == 2 and o[1] == "trainer/" and o[2] == "Orgrimmar Grunt", "a zone: its NPCs by role, those with none right in it: " .. table.concat(o, " / "))
	o = Run("ls -lR /npc | where role~trainer | field path")
	check(#o == 1 and o[1] == "/npc/Orgrimmar/trainer/Thrall", "ls -lR reaches them; paths resolve: " .. table.concat(o, " / "))
	o = Run("ls -lN /npc | where title~reagent | field title name")
	check(#o == 1 and o[1] == "Reagent_Vendor  Gun Vendor", "the title column, spaces as _: where title~reagent: " .. table.concat(o, " / "))
	o = Run("grep -rl 'sells:.*arrow' /npc")
	check(Has(o, "reading what every NPC sells") and Has(o, "/npc/Ammo Vendor") and not Has(o, "/npc/Gun Vendor"),
		"grep sells: reads what NPCs sell once, then finds the arrow seller: " .. table.concat(o, " / "))
	o = Run("grep -rl 'sells:.*shot' /npc | xargs ls -l | sort -n -k dist | field dist name")
	check(#o == 2 and o[1] == "20yd  Gun Vendor" and o[2] == "80yd  Ammo Vendor", "nearest seller of shot, by browsing: " .. table.concat(o, " / "))
	o = Run("ls -lN /npc | where role~vendor | field path | xargs grep -l 'sells:.*arrow'")
	check(#o == 1 and o[1] == "/npc/Ammo Vendor", "field path feeds xargs: whole paths, wherever you are: " .. table.concat(o, " / "))
	check(Run("ls -l / | where name~ctest | field path")[1] == "/ctest", "a directory's path")
	o = Run("cat /npc/Ammo\\ Vendor")
	check(Has(o, "role: repair,vendor") and Has(o, "sells: Light Shot, Rough Arrow") and not Has(o, "reading what"),
		"cat on an NPC: its roles and what it sells; read once only: " .. table.concat(o, " / "))
	local realNpcPin = I.NpcPin
	I.NpcPin = function(e) ns:Print("pinned " .. e.name) end
	o = Run("ls -lN /npc | where title~reagent | head -1 | field path | xargs pin")
	check(o[1] == "pinned Gun Vendor", "pin the nearest reagent vendor, by browsing: " .. table.concat(o, " / "))
	I.NpcPin = realNpcPin
	ns.providers.npc, ns.QuestieData.DB, FS.sold = nil, realQD, nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "npc" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
	FS.Forget()
	I.Here = realHere
	o = Run("cat 'Linen Cloth'")
	check(Has(o, "Stamina +5") and Has(o, "Use: Heals 10") and Has(o, "words: cloth trade goods"), "cat: the tooltip, line by line, and the row's words")
	check(#Run("cat linen cloth") == #o, "cat linen cloth: the words read as one name")
	-- an item row with no tooltip function and no C_TooltipInfo: a hidden game tooltip read line by line
	local realTI = _G.C_TooltipInfo
	_G.C_TooltipInfo = nil
	local shownLink
	local lines = {}
	local tip = { GetName = function() return "TestConsoleScan" end, NumLines = function() return #lines end,
		SetHyperlink = function(_, link) shownLink = link; lines = { "Copper Bar", "+3 Stamina", "Requires Level 10" } end }
	for i = 1, 3 do
		_G["TestConsoleScanTextLeft" .. i] = { GetText = function() return lines[i] end, GetTextColor = function() return 0, 1, 0 end }
	end
	FS.SetScanTip(tip)
	ROWS[4].tip, ROWS[4].itemID = nil, 2840
	ns.providers.consoletest._dirty = true
	o = Run("cat /ctest/Copper\\ Bar")
	check(shownLink == "item:2840" and Has(o, "+3 Stamina") and Has(o, "Requires Level 10"),
		"cat an item with no C_TooltipInfo: the hidden tooltip's lines: " .. table.concat(o, " / "))
	-- neither tooltip says anything: the game's item data
	local realInfo, realStats, realQ = _G.GetItemInfo, _G.GetItemStats, _G.C_Item
	tip.SetHyperlink = function() lines = {} end
	_G.C_Item = nil
	_G.GetItemInfo = function(id)
		if id ~= 2840 then return nil end
		return "Copper Bar", "|cffffffff|Hitem:2840|h[Copper Bar]|h|r", 1, 15, 12, "Armor", "Mail", 1, "INVTYPE_WRIST", 0, 250
	end
	_G.GetItemStats = function() return { ITEM_MOD_STAMINA_SHORT = 3 } end
	local realStam, realWrist = _G.ITEM_MOD_STAMINA_SHORT, _G.INVTYPE_WRIST
	_G.ITEM_MOD_STAMINA_SHORT, _G.INVTYPE_WRIST = "Stamina", "Wrist"
	ns.providers.consoletest._dirty = true
	o = Run("cat -v /ctest/Copper\\ Bar")
	check(Has(o, "+3 Stamina") and Has(o, "Item Level 15") and Has(o, "Wrist    Mail") and Has(o, "Requires Level 12")
		and Has(o, "item data (GetItemInfo 2840): "), "no tooltip at all: the item's data, and cat -v says so: " .. table.concat(o, " / "))
	_G.GetItemInfo, _G.GetItemStats, _G.C_Item = realInfo, realStats, realQ
	_G.ITEM_MOD_STAMINA_SHORT, _G.INVTYPE_WRIST = realStam, realWrist
	ROWS[4].tip, ROWS[4].itemID = "Smelted from copper", nil
	ns.providers.consoletest._dirty = true
	FS.SetScanTip(nil)
	_G.C_TooltipInfo = realTI
	o = Run("grep -r stamina /ctest")
	check(o[1] == "/ctest/Linen Cloth:Stamina +5", "grep -r: the file and the line: " .. tostring(o[1]))
	o = Run("grep -rl copper /")
	check(Has(o, "/ctest/Copper Bar") and not Has(o, "/ctest/Linen"), "grep -rl over everything: the files only: " .. table.concat(o, ","))
	check(Run("ls | grep -c linen")[1] == "2", "smart case: no capital, either case")
	check(Run("ls | grep -c LINEN")[1] == "0" and Run("ls | grep -ci LINEN")[1] == "2", "a capital matches as typed; -i ignores case")
	check(Run("ls | sort -r | head -n 1")[1] == "Linen Cloth~2", "sort -r | head -n 1")
	check(Run("ls | wc -l")[1] == "4" and Run("ls | count")[1] == "4", "wc -l and count")
	check(Run("seq 5 | tail -2")[1] == "4" and Run("seq 5 | head -3")[3] == "3", "seq, head -N, tail -N")
	check(Run("seq 4 | sum")[1]:find("sum 10", 1, true) ~= nil, "sum: " .. tostring(Run("seq 4 | sum")[1]))
	check(Run("seq 20 | grep -c '^1\\d$'")[1] == "10", "a regular expression: ^1\\d$")
	check(Run("seq 12 | grep -c '^3$|^12$'")[1] == "2", "a|b: either")
	check(Run("echo hello world | sed 's/o/0/g'")[1] == "hell0 w0rld", "sed s///g")
	check(Run("echo a:b:c | cut -d : -f 2")[1] == "b", "cut -d -f")
	check(Run("echo abc | rev")[1] == "cba" and Run("echo abc | tr a-z A-Z")[1] == "ABC", "rev and tr")
	Run("echo a > /tmp/x; echo a >> /tmp/x; echo b >> /tmp/x")
	o = Run("uniq -c /tmp/x")
	check(#o == 2 and o[1]:find("2 a") and o[2]:find("1 b"), "> and >> into /tmp, uniq -c reads it: " .. table.concat(o, ","))
	o, err = Run("echo x > here")
	check(Has(o, "Read-only file system") and err == 1, "the rest is read-only")
	check(Run("false && echo no || echo yes")[1] == "yes", "&& and ||")
	o, err = Run("nosuchthing")
	check(Has(o, "command not found") and err == 127, "an unknown command: 127")
	o = Run("ls /ctest/linen*")
	check(#o == 2, "a glob: both linen files: " .. table.concat(o, ","))
	o = Run("ctestcmd hi")
	check(o[1] == "|cff33ff99Terminal|r: printed hi" or (Has(o, "printed hi") and Has(o, "out line") and Has(o, "ret line")),
		"a Terminal command: what it prints and returns, in the pane: " .. table.concat(o, ","))
	check(Has(Run(".ctestcmd x"), "printed x"), "with the dot too")
	Run("echo one")
	check(Run("!!")[2] == "one", "!! runs the last line again")
	o = Run("find / -name '*rope*'")
	check(o[1] == "/ctest/Heavy\226\136\149Rope", "find -name: " .. tostring(o[1]))
	check(Has(Run("stat /ctest/Copper\\ Bar"), "key: 4"), "stat: the row's own values")
	check(Has(Run("ls /ctest | grep Copper | xargs cat"), "Smelted from copper"), "xargs: a command per line")
	o = Run("search linen")
	check(o ~= nil, "search runs Terminal's own search")
	-- a row with no item isn't "still loading": cat doesn't wait (every keybind's cat waited 3 s)
	local _, loading = FS.TipLines({ name = "Toggle Sound", detail = "CTRL-S" })
	local mt = getmetatable(sh).__index
	local realSleep, slept = mt.Sleep, 0
	mt.Sleep = function(self, s) slept = slept + (tonumber(s) or 0) return realSleep(self, s) end
	Run("cat /ctest/Heavy\226\136\149Rope")
	mt.Sleep = realSleep
	check(loading == false and slept == 0, "cat a row with no item: no waiting: " .. tostring(loading) .. ", " .. slept .. " s")
	-- neofetch: your class's logo in its colour, a character a slot (art lines), the system's facts lined up after it
	local realClass = _G.UnitClass
	_G.UnitClass = function() return "Mage", "MAGE" end
	local raw = {}
	SH.Run(SH.Session({ print = function(l) raw[#raw + 1] = l end }), "neofetch")
	local mono = 0
	for _, l in ipairs(raw) do if l:find("^|Htshm:%d+:26|h|h") then mono = mono + 1 end end
	check(mono == #raw and #raw >= #SH.FETCH_LOGOS.MAGE, "neofetch: every line an art line of 26 slots: " .. mono .. "/" .. #raw)
	local _, hex = SH.FetchClass()
	local all = table.concat(raw, " ")
	check(all:find("|cff" .. SH.FETCH_PAINT.g .. "*|r", 1, true) and raw[2]:find("|cff" .. hex .. "/|r", 1, true),
		"neofetch: a mage's hat in the mage's colour, its stars gold: " .. raw[2])
	-- every picture: each line's colours as long as its text, and no wider than the slots
	for file, logo in pairs(SH.FETCH_LOGOS) do
		for i, l in ipairs(logo) do
			check(#l[1] == #l[2] and #l[1] <= SH.FETCH_COLS, ("%s line %d: text and colours alike, within the slots"):format(file, i))
		end
	end
	-- -c: another class's picture; -n: the next one each time, round all of them
	raw = {}
	SH.Run(SH.Session({ print = function(l) raw[#raw + 1] = l end }), "neofetch -c war")
	check(FS.Strip(raw[1]):find("/\\", 1, true) and table.concat(raw, " "):find("|cff" .. SH.FETCH_PAINT.g .. "===[##]===|r", 1, true), "neofetch -c war: the warrior's sword, its guard gold")
	check(Has(Run("neofetch -c monk"), "no picture for monk"), "neofetch -c: a class with none says which there are")
	SH.fetchAt = nil
	local seen = {}
	for _ = 1, #SH.FETCH_ORDER + 1 do
		Run("neofetch -n")
		seen[#seen + 1] = SH.FETCH_ORDER[SH.fetchAt]
	end
	check(seen[1] == "WARLOCK" and seen[2] == "DRUID" and seen[3] == "WARRIOR" and seen[10] == "WARLOCK",
		"neofetch -n: from the class after yours, round all nine: " .. table.concat(seen, " "))
	o = Run("neofetch")
	check(Has(o, "OS: World of Warcraft Forever") and Has(o, "Uptime: ") and Has(o, "Kernel: Terminal")
		and not Has(o, "CPU:") and not Has(o, "Shell:"), "neofetch: the system's facts only: " .. FS.Strip(o[3] or ""))
	_G.UnitClass = function() return "Monk", "MONK" end
	check(SH.FetchClass() == "OTHER", "a class with no art: Terminal's own")
	_G.UnitClass = realClass
	check(#Run("neofetch | grep Kernel") == 1, "neofetch piped: plain lines")
	check(SH.FetchUptime(2 * 3600 + 13 * 60) == "2 hours, 13 mins" and SH.FetchUptime(30) == "0 mins"
		and SH.FetchUptime(86400 + 60) == "1 day, 1 min", "uptime as neofetch says it")
	-- a row leading to another search ("what should i do"'s): that search, to type next; not the panel's Enter
	local realST, realNote = ns.UI.SearchText, ns.UI.answerNote
	ns.UI.SearchText = function(self)
		self.answerNote = "Things to do  ·  Enter searches for it"
		return { { kind = "suggestion", name = "Train new spells", detail = "37 spells to learn", searchText = "nearest class trainer" } }
	end
	o = Run("search bored")
	ns.UI.SearchText, ns.UI.answerNote = realST, realNote
	check(Has(o, "Train new spells") and Has(o, "→ search nearest class trainer"), "search: a suggestion says the search it leads to: " .. table.concat(o, " / "))
	check(Has(o, "Things to do") and not Has(o, "Enter searches"), "search: the note without the panel's Enter")
	o, err = Run("| ls")
	check(Has(o, "syntax error") and err == 2, "a pipe with nothing before it: a syntax error")
	-- pin: a waypoint on a file with a place
	local realPlace, placed = ns.Maps.Place, nil
	ns.Maps.Place = function(e) placed = e return "set" end
	o = Run("ls /ctest | grep Copper | xargs pin")
	check(placed and placed.mapID == 1429 and placed.pos.x == 0.4 and Has(o, "Waypoint set on Copper Bar"),
		"pin: the waypoint on the row's place, said in the pane: " .. table.concat(o, " / "))
	placed = nil
	o, err = Run("pin 'Linen Cloth'")
	check(placed == nil and err == 1 and Has(o, "no place on the map"), "pin on a row with no place: said")
	ns.Maps.Place = realPlace
	-- lists as folders: /loot/<instance>/<boss>/<item>
	ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = function() return {
		{ kind = "loot", name = "Necromantic Band", key = "a", detail = "Darkreaver  Scholomance", tip = "a ring of bone" },
		{ kind = "loot", name = "Shadow Band", key = "b", detail = "Darkreaver  Scholomance", tip = "dark" },
		{ kind = "loot", name = "Shadow Band", key = "c", detail = "Varimathras  Ruins of Lordaeron", tip = "darker" },
		{ kind = "loot", name = "Thorium Belt", key = "d", detail = "Blacksmithing", tip = "plate" },
	} end })
	ns:AliasesChanged()
	FS.Forget()
	o = Run("ls /loot")
	check(#o == 3 and o[1] == "Blacksmithing/" and o[2] == "Ruins of Lordaeron/" and o[3] == "Scholomance/",
		"/loot: its instances and crafting sections as folders: " .. table.concat(o, " / "))
	check(Run("ls /loot/scholomance")[1] == "Darkreaver/" and Run("ls /loot/blacksmithing")[1] == "Thorium Belt",
		"an instance: its bosses; a section with no boss: its items")
	o = Run("ls /loot/ruins_of_lordaeron/varimathras")
	check(#o == 1 and o[1] == "Shadow Band", "a boss: its items, a name twice in two folders kept as it is: " .. table.concat(o, " / "))
	o = Run("ls -l /loot")
	check(Has(o, "drx----\t2\tScholomance/"), "ls -l: a folder says how many rows are under it: " .. table.concat(o, " / "))
	o = Run("ls -lR /loot | where zone~lordaeron | field path")
	check(#o == 1 and o[1] == "/loot/Ruins_of_Lordaeron/Varimathras/Shadow Band", "ls -lR reaches every file; paths resolve: " .. table.concat(o, " / "))
	check(Has(Run("cat " .. o[1]), "darker"), "such a path, catted")
	o = Run("ls -R /loot/Scholomance")
	check(o[1] == "/loot/Scholomance:" and o[2] == "Darkreaver/" and Has(o, "/loot/Scholomance/Darkreaver:") and Has(o, "Necromantic Band"),
		"ls -R: each folder after its path: " .. table.concat(o, " / "))
	check(Run("find /loot -type f | count")[1] == "4", "find: every file under it, flat")
	o = Run("find /loot -type d")
	check(#o == 6 and o[1] == "/loot", "find -type d: the folders: " .. table.concat(o, " / "))
	o = Run("grep -rl band /loot/Scholomance")
	check(#o == 2 and Has(o, "/loot/Scholomance/Darkreaver/Shadow Band"), "grep -r in one folder: " .. table.concat(o, " / "))
	o = Run("locate shadow band")
	check(#o == 2 and Has(o, "/loot/Ruins of Lordaeron/Varimathras/Shadow Band"), "locate: nested paths")
	check(#Run("ls /loot/Scholomance/Darkreaver/N*") == 1, "a glob in a folder")
	check(SH.Complete(sh, "cd /loot/sch") == "cd /loot/Scholomance/", "Tab: folders end in /")
	o = Run("tree /loot")
	check(Has(o, "Scholomance/ (2)") and Has(o, "Thorium Belt") and Has(o, "5 directories, 4 files"), "tree: folders with their counts: " .. table.concat(o, " / "))
	check(FS.PathOf(FS.DirOf("loot"), { key = "c", kind = "loot" }) == "/loot/Ruins of Lordaeron/Varimathras/Shadow Band",
		"a search's row, found by its key: its folder's path")
	-- recipes by profession, mailboxes by zone
	ns:RegisterProvider("recipes", { label = "Recipe", aliases = { "recipe" }, collect = function() return {
		{ kind = "recipes", name = "Copper Bracers", key = 1, profName = "Blacksmithing" },
		{ kind = "recipes", name = "Linen Bandage", key = 2, profName = "First Aid" },
	} end })
	ns:RegisterProvider("mailbox", { label = "Mailbox", aliases = { "mailbox" }, collect = function() return {
		{ kind = "mailbox", name = "Mailbox", key = "1-1", zone = "Orgrimmar" },
		{ kind = "mailbox", name = "Mailbox", key = "1-2", zone = "Orgrimmar" },
		{ kind = "mailbox", name = "Mailbox", key = "2-1", zone = "The Barrens" },
	} end })
	ns:AliasesChanged()
	FS.Forget()
	o = Run("ls /recipe")
	check(#o == 2 and o[1] == "Blacksmithing/" and o[2] == "First Aid/", "/recipe: a folder per profession: " .. table.concat(o, " / "))
	check(Run("ls /recipe/first_aid")[1] == "Linen Bandage", "a profession's recipes")
	o = Run("ls /mailbox")
	check(#o == 2 and o[1] == "Orgrimmar/" and o[2] == "The Barrens/", "/mailbox: a folder per zone: " .. table.concat(o, " / "))
	o = Run("ls /mailbox/orgrimmar")
	check(#o == 2 and o[1] == "Mailbox" and o[2] == "Mailbox~2", "a zone's mailboxes: " .. table.concat(o, " / "))
	ns.providers.recipes, ns.providers.mailbox = nil, nil
	for i = #ns.providerOrder, 1, -1 do
		local id = ns.providerOrder[i]
		if id == "recipes" or id == "mailbox" then table.remove(ns.providerOrder, i) end
	end
	-- (review) field leaves ls -R's headers out; xargs takes an ls -l line as its file; Tab says which are folders; stat
	o, err = Run("ls -lR /loot | field name")
	check(err == 0 and Has(o, "Necromantic Band") and not Has(o, "/loot"), "field over ls -lR: the headers left out: " .. table.concat(o, " / "))
	check(Has(Run("ls -l /loot/Scholomance/Darkreaver | where name~necro | xargs cat"), "a ring of bone"), "xargs: an ls -l line is its file")
	local _, _, choices = SH.Complete(sh, "cd /loot/")
	check(choices and Has(choices, "Scholomance/") and Has(choices, "Blacksmithing/"), "Tab's choices: folders with their /")
	o = Run("stat /loot/Scholomance")
	check(Has(o, "Rows: 2") and Has(o, "Folders: 1"), "stat on a folder: its own rows and folders: " .. table.concat(o, " / "))
	-- u: an upgrade for you (Terminal's is:upgrade), loot only
	local realParse = ns.Filters.Parse
	ns.Filters.Parse = function(word, ...)
		if word == "is:upgrade" then return function(e) return e.name == "Necromantic Band" end end
		return realParse(word, ...)
	end
	FS.ForgetUpgrade()
	o = Run("ls -lR /loot | where mode~u | field mode name")
	check(#o == 1 and o[1] == "-r----u  Necromantic Band", "ls -l: u on a loot row that's an upgrade: " .. table.concat(o, " / "))
	ns.Filters.Parse = realParse
	FS.ForgetUpgrade()
	ns.providers.loot = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "loot" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
	FS.Forget()
	-- rows that are directories too (an attunement's steps)
	local KEY = { name = "The Dalaran Key", key = 7, kids = {
		{ name = "Talk to the Archmage", fileName = "step1", isStep = true, tip = "Go see the archmage in Dalaran" },
		{ name = "Collect shards", fileName = "step2a", isStep = true, tip = "Get 5 arcane shards" },
	} }
	ns:RegisterProvider("chtest", { label = "Nested", aliases = { "chtest" }, collect = function() return { KEY, { name = "Plain One", key = 8 } } end })
	FS.CHILDREN.chtest = function(e) return e.kids end
	ns:AliasesChanged()
	FS.Forget()
	o = Run("ls /chtest")
	check(o[1] == "Plain One" and o[2] == "The Dalaran Key/", "a row with files of its own is listed as a directory: " .. table.concat(o, " / "))
	o = Run("ls /chtest/the_dalaran_key")
	check(#o == 2 and o[1] == "step1" and o[2] == "step2a", "its files in their order; _ stands for a space: " .. table.concat(o, " / "))
	check(Has(Run("cat /chtest/The\\ Dalaran\\ Key/step2a"), "Get 5 arcane shards"), "cat on a step")
	Run("cd /chtest/the_dalaran_key")
	check(Run("pwd")[1] == "/chtest/The Dalaran Key" and Has(Run("cat step1"), "archmage"), "cd into it; its files by their names")
	Run("cd /")
	o = Run("ls -l /chtest/the_dalaran_key | field title path")
	check(o[1] == "Talk_to_the_Archmage  /chtest/The_Dalaran_Key/step1", "ls -l: a step's title, and a path that resolves: " .. table.concat(o, " / "))
	check(Has(Run("ls -l /chtest/the_dalaran_key | field path | xargs cat"), "Get 5 arcane shards"), "those paths feed xargs")
	o = Run("grep -rl shards /chtest")
	check(#o == 1 and o[1] == "/chtest/The Dalaran Key/step2a", "grep -r reads a row's own files too: " .. table.concat(o, " / "))
	check(SH.Complete(sh, "cd /chtest/the") == "cd /chtest/The\\ Dalaran\\ Key/", "Tab: such a row ends in / like a directory")
	check(SH.Complete(sh, "cat /chtest/The\\ Dalaran\\ Key/step2") == "cat /chtest/The\\ Dalaran\\ Key/step2a ", "Tab inside it")
	-- Attune's: its step numbers as names
	local realAT = ns.Attune
	ns.Attune = { RecOf = function(e) return e.rec end, StepRows = function()
		return { { name = "A", stepRec = { label = "1" } }, { name = "B", stepRec = { label = "2a" } },
			{ name = "C", stepRec = { side = true } }, { name = "D", stepRec = {}, stepIndex = 4 } }
	end }
	local steps = FS.CHILDREN.attune({ rec = {} })
	check(steps and steps[1].fileName == "step1" and steps[2].fileName == "step2a" and steps[3].fileName == "side1"
		and steps[4].fileName == "step4", "an attunement's steps: step1, step2a, side1...")
	check(FS.CHILDREN.attune({ rec = {}, isStep = true }) == nil, "a step has no files of its own")
	ns.Attune = realAT
	FS.CHILDREN.chtest = nil
	ns.providers.chtest = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "chtest" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
	FS.Forget()
	-- aliases
	Run("alias near='ls -l /ctest | where'")
	o = Run("near count=20 | field name")
	check(#o == 1 and o[1] == "Linen Cloth", "an alias, the words after it kept: " .. table.concat(o, " / "))
	check(Run("alias")[1] == "alias near='ls -l /ctest | where'" and ns.db.console.aliases.near == "ls -l /ctest | where",
		"alias lists them; kept in the saved settings")
	Run("alias cnt='ls /ctest | count'")
	check(Run("cnt")[1] == "4" and Run("echo x; cnt")[2] == "4", "an alias after ; too")
	Run("alias ls='ls /ctest'")
	check(#Run("ls") == 4, "an alias named as the command it runs: read once, not again")
	Run("unalias ls")
	check(Has(Run("type near"), "near is aliased to 'ls -l /ctest | where'"), "type says what an alias is")
	check(SH.Highlight(sh, "near x"):find("|cff" .. SH.C.green .. "near|r", 1, true) ~= nil, "an alias is coloured as a command")
	check(SH.Complete(sh, "nea") == "near ", "Tab knows aliases")
	-- ls --icons: each row's game icon in a cell of its own before its name; a folder its first file's
	ROWS[4].icon = 133217
	ns.providers.consoletest._dirty = true
	local rawLs = {}
	local rawSh = SH.Session({ print = function(l) rawLs[#rawLs + 1] = l end })
	SH.Run(rawSh, "ls --icons /ctest")
	local copperLine
	for _, l in ipairs(rawLs) do if FS.Strip(l) == "\tCopper Bar" then copperLine = l end end
	check(copperLine and copperLine:find("^|T133217:0|t\t"), "ls --icons: the icon, a tab, the name: " .. tostring(copperLine))
	check(not Run("ls /ctest")[1]:find("\t", 1, true), "ls without it: as before")
	rawLs = {}
	SH.Run(rawSh, "ls --icons /")
	local rootLine
	for _, l in ipairs(rawLs) do if FS.Strip(l) == "\tctest/" then rootLine = l end end
	check(rootLine and rootLine:find("|T133217:0|t", 1, true), "ls --icons /: a list's icon is its first file's: " .. tostring(rootLine))
	rawLs = {}
	SH.Run(rawSh, "ls -l --icons /ctest/Copper\\ Bar")
	check(rawLs[1] and rawLs[1]:find("|T133217:0|t\t", 1, true) and FS.ParseLong(rawLs[1]).name == "Copper Bar", "ls -l --icons: the long line keeps its columns")
	ROWS[4].icon = nil
	ns.providers.consoletest._dirty = true
	-- Tab past the command word: what that command takes there
	check(SH.Complete(sh, "unalias ne") == "unalias near ", "Tab: unalias, your aliases")
	local _, _, opts = SH.Complete(sh, "ls -")
	check(opts and table.concat(opts, " ") == "--icons -N -R -l -o -r", "Tab: a command's options, from its usage line: " .. table.concat(opts or {}, " "))
	local _, _, fopts = SH.Complete(sh, "find /ctest -")
	check(fopts and table.concat(fopts, " "):find("-maxdepth", 1, true) and table.concat(fopts, " "):find("-name", 1, true), "Tab: find's long options whole")
	check(SH.Complete(sh, "ls -l /ctest | where di") == "ls -l /ctest | where dist", "Tab: where, the columns")
	check(SH.Complete(sh, "ls -l /ctest | filter zo") == "ls -l /ctest | filter zone", "Tab: by its other name too")
	check(SH.Complete(sh, "ls -l /ctest | sort -k ti") == "ls -l /ctest | sort -k title ", "Tab: sort -k, a column")
	check(SH.Complete(sh, "ls -l /ctest | field zo") == "ls -l /ctest | field zone ", "Tab: field, a column")
	check(SH.Complete(sh, "ls -l -o dist,ti") == "ls -l -o dist,title ", "Tab: ls -o, the last of the columns")
	check(SH.Complete(sh, "ls -l /ctest | where kind~ct") == "ls -l /ctest | where kind~ctest ", "Tab: where's kind values: the lists")
	check(SH.Complete(sh, "man gre") == "man grep ", "Tab: man, the commands")
	check(SH.Complete(sh, "layout wi") == "layout wide ", "Tab: layout's names")
	check(SH.Complete(sh, "neofetch -c ma") == "neofetch -c mage ", "Tab: neofetch -c, the classes")
	check(SH.Complete(sh, "cat /ctest/Copp") == "cat /ctest/Copper\\ Bar ", "Tab: paths as before")
	local afterRedirect = SH.Complete(sh, "echo -n hi > /tm")
	check(afterRedirect == "echo -n hi > /tmp/", "Tab after >: paths, not the command's words: " .. tostring(afterRedirect))
	o, err = Run("echo a | xargs near")
	check(err == 127 and Has(o, "an alias"), "xargs runs commands, not aliases: said")
	Run("unalias near cnt")
	o, err = Run("near")
	check(err == 127 and next(ns.db.console.aliases) == nil, "unalias forgets them")
	-- a zone's file: its levels and fishing
	local realZones = ns.Zones
	ns.Zones = { Of = function(ui) return ui == 1440 and { min = 18, max = 30, fish = 55, fishHigh = 130 } or nil end,
		FishingSkill = function() return 75 end }
	ns:RegisterProvider("maps", { label = "Map", aliases = { "map" }, collect = function() return {
		{ kind = "maps", name = "Ashenvale", key = 1440, mapID = 1440 }, { kind = "maps", name = "Kalimdor", key = 1414, mapID = 1414 },
	} end })
	ns:AliasesChanged()
	FS.Forget()
	o = Run("cat /map/Ashenvale")
	check(Has(o, "levels: 18-30") and Has(o, "fishing: 55, deeper spots 130  (yours: 75, enough)"), "a zone's file: levels, fishing, yours: " .. table.concat(o, " / "))
	o = Run("grep -rl fishing /map")
	check(#o == 1 and o[1] == "/map/Ashenvale", "grep -r fishing /map: the zones with fish")
	ns.Zones = realZones
	ns.providers.maps = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "maps" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
	FS.Forget()
	-- (review) ! is history only at a word's start, never inside single quotes
	Run("echo one")
	check(SH.Expand(sh, "ls | where dist!=50") == "ls | where dist!=50" and SH.Expand(sh, "grep '!echo' x") == "grep '!echo' x"
		and SH.Expand(sh, "echo a!echo") == "echo a!echo", "a ! inside a word or in single quotes stays")
	local ex, changed = SH.Expand(sh, "echo !!")
	check(ex == "echo echo one" and changed, "!! still: " .. tostring(ex))
	check(not Has(Run("help"), "matrix") and SH.Complete(sh, "matri") == "matri" and Has(Run("man matrix"), "matrix"),
		"matrix is an easter egg: not in help or Tab, but man knows it")
	-- awk: the real language's everyday part
	local function Lines(cmd) return table.concat(Run(cmd), "|") end
	check(Lines("seq 5 | awk '$1 > 3'") == "4|5", "awk: a pattern alone prints the line")
	check(Lines("seq 5 | awk '{ s += $1 } END { print s }'") == "15", "awk: a sum in END")
	check(Lines("echo a b c | awk '{ print $2, $NF, NF }'") == "b c 3", "awk: $2 $NF NF")
	check(Lines("echo a:b:c | awk -F: '{ print $2 }'") == "b", "awk -F")
	check(Lines("seq 3 | awk -v n=2 '$1 == n'") == "2", "awk -v: " .. Lines("seq 3 | awk -v n=2 '$1 == n'"))
	check(Lines("seq 3 | awk 'END { print NR }'") == "3", "awk: NR in END")
	check(Lines("seq 4 | awk '{ if ($1 % 2) print \"odd\"; else print \"even\" }'") == "odd|even|odd|even", "awk: if/else")
	check(Lines("seq 20 | awk '/^1/ && $1 > 15'") == "16|17|18|19", "awk: /regex/ && a comparison")
	check(Lines("seq 6 | awk '{ c[$1 % 2]++ } END { for (k in c) print k, c[k] }'") == "0 3|1 3", "awk: arrays, for (k in a)")
	check(Lines("seq 3 | awk '{ printf \"%03d-\", $1 } END { printf \"\\n\" }'") == "001-002-003-", "awk: printf, its lines joined until a newline")
	check(Lines("echo hello world | awk '{ print toupper(substr($0, 1, 3)), length($1), index($0, \"wor\") }'") == "HEL 5 7",
		"awk: substr toupper length index")
	check(Lines("echo a-b-c | awk '{ n = split($0, p, \"-\"); print n, p[3] }'") == "3 c", "awk: split")
	check(Lines("seq 10 | awk 'BEGIN { x = 0 } { while (x < 3) x++; if ($1 == 5) exit } END { print x, NR }'") == "3 5",
		"awk: while, exit then END")
	check(Lines("seq 5 | awk '$1 == 2 { next } { print }'") == "1|3|4|5", "awk: next")
	check(Lines("echo 3 4 | awk '{ print $1 * $2 + 2 ^ 3, ($1 > 2 ? \"big\" : \"small\") }'") == "20 big", "awk: arithmetic, ?:")
	check(Lines("echo a b | awk '{ $2 = \"x\"; print; print $0 }'") == "a x|a x", "awk: a field set: the line made again")
	check(Lines("ls -l /ctest | awk 'count >= 20 { print name, count }'") == "Linen Cloth 20", "awk: ls -l's columns by name")
	check(Lines("ls -l /ctest | awk 'count >= 20' | field name") == "Linen Cloth", "awk: print alone keeps the line, its columns too")
	check(Lines("echo 312yd | awk '$1 > 300 { print \"far\" }'") == "far", "awk: 312yd compares as 312")
	o, err = Run("awk '{ print '")
	check(err == 2 and Has(o, "never closed"), "awk: a broken program: said, status 2: " .. table.concat(o, " / "))
	o, err = Run("seq 2 | awk '{ while (1) x++ }'")
	check(err == 2 and Has(o, "never ended"), "awk: a loop that never ends: stopped")
	-- other addons as mounts: df, mount, /etc/fstab
	local mountsWere = #FS.MOUNTS
	table.insert(FS.MOUNTS, { type = "ctest", lists = { "consoletest" }, names = { "CtestAddon" }, source = function() return "CtestAddon" end })
	table.insert(FS.MOUNTS, { type = "nothere", lists = { "nothere" }, names = { "NotHere" }, source = function() return nil end })
	Run("ls /ctest")
	o = Run("df")
	check(o[1] == "Filesystem\tSize\tUsed\tAvail\tUse%\tMounted on" and Has(o, "CtestAddon\t4\t4\t0\t100%\t/ctest") and not Has(o, "NotHere"),
		"df: an addon's lists as a filesystem, only those installed: " .. table.concat(o, " / "))
	check(Has(Run("df -a"), "NotHere (not installed)"), "df -a: those not installed too")
	check(Has(Run("mount"), "CtestAddon on /ctest type ctest (ro,auto)"), "mount: which, where, how")
	-- (review, 0.67.12) link on a file that isn't there says so, not "missing operand"
	o = Run("link /ctest/Nothing\ Here")
	check(Has(o, "No such file") and not Has(o, "missing operand"), "link: no such file, said: " .. table.concat(o, ","))
	o = Run("cat /etc/fstab")
	check(Has(o, "CtestAddon\t/ctest\tctest\tro,auto\t0\t0") and Has(o, "# NotHere\t/nothere\tnothere\tro,noauto\t0\t0\t# not installed"),
		"/etc/fstab: those there, and those not commented out: " .. table.concat(o, " / "))
	o = Run("cat /etc/fstab | grep -v '^#'")
	local commented = false
	for _, l in ipairs(o) do if l:sub(1, 1) == "#" then commented = true end end
	check(Has(o, "CtestAddon") and not Has(o, "NotHere") and not commented, "fstab without its comments: what's mounted")
	o, err = Run("umount /ctest")
	check(err == 32 and Has(o, "target is busy (CtestAddon is using it)"), "umount: busy, as the addon is using it")
	for i = #FS.MOUNTS, mountsWere + 1, -1 do table.remove(FS.MOUNTS, i) end
	-- Terminal: Share as NFS: a friend connected a remote mount, the groups fstab's exports, /shared a folder a friend
	local realSsh = ns.Ssh
	local friends = { { name = "Bob", n = 12, friend = { mode = "limited" } } }
	ns.Ssh = { game = { On = function() return true end, Connected = function() return friends end,
		groups = { raid = { mode = "limited" } } } }
	ns:RegisterProvider("shared", { label = "Shared", aliases = { "shared" }, collect = function() return {
		{ name = "Linen Cloth", key = "b1", owner = "Bob" }, { name = "Bob's gold", key = "g1", owner = "Bob" },
	} end })
	ns:AliasesChanged()
	FS.Forget()
	check(Has(Run("mount"), "Bob:/bags on /shared/Bob type nfs4 (ro,vers=4,sharing=limited)"), "Share: a friend connected, an NFS mount")
	check(Has(Run("df"), "Bob:/bags\t12\t12\t0\t100%\t/shared/Bob"), "df: their items")
	check(Has(Run("cat /etc/fstab"), "share:raid\t/shared\tnfs4\tro,auto,_netdev,sharing=limited\t0\t0"), "fstab: your groups as exports")
	o = Run("ls /shared")
	check(#o == 1 and o[1] == "Bob/" and Run("ls /shared/bob")[2] == "Linen Cloth", "/shared: a folder a friend: " .. table.concat(o, " / "))
	friends = {}
	check(Has(Run("df -a"), "Terminal_Share (nobody connected)") and not Has(Run("mount"), "nfs4"), "nobody connected: no mount, said by df -a")
	ns.Ssh = realSsh
	ns.providers.shared = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "shared" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
	FS.Forget()
	-- prompt colours
	local hl = SH.Highlight(sh, "ls -l | nosuch 'q'")
	check(hl:find("|cff" .. SH.C.green .. "ls|r", 1, true) and hl:find("|cff" .. SH.C.cyan .. "-l|r", 1, true)
		and hl:find("|cff" .. SH.C.red .. "nosuch|r", 1, true) and hl:find("|cff" .. SH.C.magenta .. "||", 1, true)
		and hl:find("|cff" .. SH.C.yellow .. "'q'|r", 1, true), "colours as you type: " .. hl)
	-- Tab
	local line, pos, choices = SH.Complete(sh, "cat /ctest/cop")
	check(line == "cat /ctest/Copper\\ Bar " and pos == #line and choices == nil, "Tab: one name, escaped: " .. line)
	line = SH.Complete(sh, "cat /ctest/lin")
	check(line == "cat /ctest/Linen\\ Cloth", "Tab: as far as the names agree: " .. line)
	line, pos, choices = SH.Complete(sh, "cat /ctest/Linen\\ Cloth")
	check(choices and #choices == 2, "Tab: the choices when they part")
	check(SH.Complete(sh, "gre") == "grep ", "Tab on a command")
	check(SH.Complete(sh, "cd /ct") == "cd /ctest/", "Tab on a directory: its /")
	-- options and patterns
	local opts, rest = SH.Opts({ "-n5", "x" }, "n:")
	check(opts.n == "5" and rest[1] == "x", "-n5")
	local s, e = SH.Matcher("a.c")("xabcx")
	check(s == 2 and e == 4, "a.c matches abc")
	check(SH.Matcher("[a-c]+", {})("zzbcaz") == 3, "a set with a range")
	-- Ctrl+C
	sh.cancelled = true
	local okRun, why = pcall(SH.Run, sh, "seq 1000")
	sh.cancelled = false
	check(not okRun and why == SH.CANCEL, "Ctrl+C stops a command")
end)
check(ok, "console shell: " .. tostring(err))

print("[console: panes, apps in them, stepping out]")
-- (Zen's own fade isn't run here: it keeps each frame it kept for the session, and support.lua's .zen test counts them)
local realOpened, zenOpened = ns.Zen.Opened, 0
ns.Zen.Opened = function() zenOpened = zenOpened + 1 return true end
ok, err = pcall(function()
	ns.db.zen = false
	check(C.Open() and C.IsShown() and ns.Zen.forced == true and zenOpened == 1, "opens, zen forced on whatever .zen says")
	local panes = C.Panes()
	check(#panes == 1 and #panes[1].lines >= 2, "one pane, the welcome in it")
	local first = panes[1]
	C.Layout()
	local tickNow = C.frame:GetScript("OnUpdate")
	for _ = 1, 20 do tickNow(C.frame, 0.05) end
	local was = first.shownRect
	local second = C.Split(first)
	check(second.shownRect and second.shownRect.w == was.w and second.glide ~= nil, "a new pane starts where its parent was, and glides")
	for _ = 1, 20 do tickNow(C.frame, 0.05) end
	check(second.glide == nil and math.abs(second.shownRect.x - second.rect.x) < 0.5 and math.abs(first.shownRect.w - first.rect.w) < 0.5,
		"the glide ends where the tiling puts them")
	for _ = 1, 2 do C.Split(C.Focused()) end
	check(#panes == 4 and C.Split(C.Focused()) == nil, "four panes at most")
	local r = C.Rects(4, "grid", 100, 100, 0)
	check(r[1].w == 50 and r[4].x == 50 and r[4].y == 50, "grid: two rows of two")
	r = C.Rects(3, "grid", 100, 100, 0)
	check(r[1].h == 100 and r[2].h == 50, "three: one big, two stacked")
	r = C.Rects(3, "mono", 100, 100, 0, 2)
	check(r[1] == false and r[2].w == 100, "mono: the focused one only")
	local p = panes[1]
	C.Focus(p)
	local tick = C.frame:GetScript("OnUpdate")
	local function Drain() for _ = 1, 200 do if not p.job then break end tick(C.frame, 0.02) end end
	C.Run(p, "echo hi there")
	Drain()
	check(FS.Strip(p.lines[#p.lines]) == "hi there", "a line run in a pane: " .. tostring(p.lines[#p.lines]))
	-- an app opened from a pane goes into it
	local app = {}
	local f = Panel.Build("TerminalCtestApp", app)
	app.IsShown = function() return f:IsShown() end
	app.Close = function() f:Hide() end
	local gotKey
	f:SetScript("OnKeyDown", function(_, key) gotKey = key end)
	ns:RegisterCommand("ctestapp", { desc = "an app", run = function() Panel.Opening(app); f:Show() end })
	C.Run(p, "ctestapp")
	Drain()
	check(C.IsShown() and C.DockedIn(app) == p and p.app and p.app.app == app and f:IsShown(), "the app opens in the pane, the console stays")
	f.GetPoint = function() return "CENTER", p.body end
	f:GetScript("OnKeyDown")(f, "`")
	check(not C.IsShown() and not f:IsShown() and not ns.Zen.forced, "` in the app: the console and its apps step out")
	check(not Panel.Keeps(app), "out of the console, Panel closes its apps as any")
	C.Open()
	check(C.IsShown() and f:IsShown() and C.DockedIn(app) == p, "back: the app where it was")
	local function Ctrl(key)
		_G.IsControlKeyDown = function() return true end
		C.WindowKey(C.Focused(), key)
		_G.IsControlKeyDown = function() return false end
	end
	-- Ctrl+B, then a key (a browser keeps Ctrl+N, Ctrl+W and Ctrl+Tab)
	local function Prefixed(key) Ctrl("B") C.WindowKey(C.Focused(), "LCTRL") C.WindowKey(C.Focused(), key) end
	local before = #panes
	C.Focus(panes[#panes])
	Ctrl("W")
	check(#panes == before - 1, "Ctrl+W closes a pane")
	Prefixed("C")
	check(#panes == before and not C.prefix, "Ctrl+B c: a new pane (a modifier between doesn't end the prefix)")
	C.Focused().edit:SetText("c") -- (the game types the key into the new pane, which has the keyboard now)
	T.FlushAll()
	check(C.Focused() == panes[#panes] and C.Focused().edit:GetText() == "", "Ctrl+B c: the c isn't left in the new pane")
	Prefixed("1")
	check(C.Focused() == panes[1], "Ctrl+B 1: to the first pane")
	Prefixed("O")
	check(C.Focused() == panes[2], "Ctrl+B o: the next")
	panes[2].edit:SetText("ab")
	Ctrl("B")
	check(C.prefix == true, "Ctrl+B waits for its key")
	C.WindowKey(panes[2], "Q")
	panes[2].edit:SetText("abq") -- (the game types the key into the box after it was read)
	T.FlushAll()
	check(not C.prefix and panes[2].edit:GetText() == "ab", "the key after Ctrl+B types nothing, an unknown one does nothing")
	panes[2].edit:SetText("")
	C.Focus(panes[2])
	Ctrl("Z")
	tick(C.frame, 0.2)
	check(C.DockedIn(app) == p and not f:IsShown(), "zoomed onto another pane: the app hides, still in its pane")
	Ctrl("Z")
	tick(C.frame, 0.2)
	check(C.DockedIn(app) == p and f:IsShown(), "zoomed out: the app shows again")
	T.UI:Open(""); T.FlushAll()
	check(not C.IsShown() and C.DockedIn(app) == p and not f:IsShown() and not p.app.closed, "Terminal opened over it: the console steps out, its app kept")
	f:GetScript("OnKeyDown")(f, "`")
	check(gotKey == "`", "the console away: the app's keys are its own")
	T.UI:Hide(); T.FlushAll()
	C.Open()
	check(C.IsShown() and f:IsShown(), "and back again")
	app.Close()
	tick(C.frame, 0.2)
	check(C.DockedIn(app) == nil and p.app == nil and app.Close ~= nil, "the app closed: its pane is a shell again")
	-- (review) a list still loading: the console waits, then reads it again
	local busyLeft = 3
	ns:RegisterProvider("busytest", { label = "Busy", aliases = { "busytest" },
		busy = function() if busyLeft > 0 then busyLeft = busyLeft - 1 return "loading" end end,
		collect = function() return busyLeft > 0 and {} or { { name = "Late Row", key = 1, tip = "here at last" } } end })
	ns:AliasesChanged()
	FS.Forget()
	local realGT, clock = _G.GetTime, 0
	_G.GetTime = function() clock = clock + 1 return clock end -- (a second a look: each quarter-second wait over at once)
	C.Run(p, "cat /busytest/Late\\ Row")
	Drain()
	_G.GetTime = realGT
	local said = {}
	for i = #p.lines - 4, #p.lines do said[#said + 1] = FS.Strip(p.lines[i] or "") end
	check(table.concat(said, "\n"):find("here at last", 1, true) ~= nil and table.concat(said, "\n"):find("loading", 1, true) ~= nil,
		"a list loading: said, waited for, then read: " .. table.concat(said, " / "))
	ns.providers.busytest = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "busytest" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
	FS.Forget()
	-- less: every line kept, a page at a time, searched
	C.Run(p, "seq 3000 | less")
	Drain()
	local pg = p.pager
	check(pg and #pg.lines == 3000 and pg.top == 1, "less keeps every line (more than the scrollback's 2000)")
	local function Type(text) p.edit:SetText(text) end
	Type("G")
	check(pg.top > 2900 and p.edit:GetText() == "", "G: the end; what's typed is the pager's key, not text")
	Type("g")
	Type("/")
	check(pg.mode == "search", "/ opens the search line")
	Type("250")
	C.Enter(p)
	check(pg.top == 250 and pg.mode == "keys", "Enter searches: the page moves to the first match")
	Type("n")
	check(pg.top == 1250, "n: the next match")
	Type("N")
	check(pg.top == 250, "N: the one before")
	Type("?")
	Type("zzz")
	check(p.overlay.text == "zzz", "the pager's search line isn't coloured as a command: " .. tostring(p.overlay.text))
	C.Enter(p)
	check(pg.top == 250 and pg.note ~= nil, "nothing found: it stays, and says so")
	C.KeyDown(p, "PAGEDOWN")
	check(pg.top > 250, "PageDown: a page on")
	Type("q")
	check(p.pager == nil, "q quits")
	C.Run(p, "echo needle")
	Drain()
	_G.IsControlKeyDown = function() return true end
	C.KeyDown(p, "B")
	_G.IsControlKeyDown = function() return false end
	C.KeyDown(p, "[")
	Type("?")
	check(p.pager and p.pager.mode == "search" and p.pager.dir == -1 and p.pager.title == "scrollback",
		"Ctrl+B [ then ?: the scrollback in the pager, searching back")
	Type("needle")
	C.Enter(p)
	check(FS.Strip(p.pager.lines[p.pager.top]) == "needle", "found in the scrollback: " .. tostring(p.pager.lines[p.pager.top]))
	p.edit:GetScript("OnEscapePressed")(p.edit)
	check(p.pager == nil and C.IsShown(), "Esc closes the pager, not the console")
	-- an art line drawn: its characters in slots of one width, the rest after the slots
	local realH = p.body.GetHeight
	p.body.GetHeight = function() return 400 end
	p.lines = { SH.Mono("|cffff0000ab|r d", 6, "after") }
	p.offset = 0
	C.Draw(p)
	local r1 = p.rows[1]
	local cw = C.Width("0", p)
	check(r1.mono and r1.mono[1]:GetText() == "|cffff0000a|r" and r1.mono[3]:GetText() == "d" and r1.rest and r1.rest:GetText() == "after",
		"an art line: a character a slot, its colour kept, the rest after")
	local x3, xr
	r1.mono[3].SetPoint = function(_, _, _, _, x) x3 = x end
	r1.rest.SetPoint = function(_, _, _, _, x) xr = xr or x end
	C.Draw(p)
	r1.mono[3].SetPoint, r1.rest.SetPoint = nil, nil
	check(x3 == 3 * cw and xr == 6 * cw + C.MONO_GAP, "the slots one width each, the rest after all the slots: " .. tostring(x3) .. " " .. tostring(xr))
	p.lines = { "plain" }
	C.Draw(p)
	check(not r1.mono[1]:IsShown() and not r1.rest:IsShown(), "a plain line after it: the slots hidden")
	p.body.GetHeight = realH
	-- selecting with the mouse: a drag from "beta" to "gam" goes into the copy box, selected, for Ctrl+C
	C.Run(p, "echo alpha beta")
	Drain()
	C.Run(p, "echo gamma")
	Drain()
	local realBodyH = p.body.GetHeight
	p.body.GetHeight = function() return 400 end -- (the harness's frames have no size)
	C.Draw(p)
	local at, at2
	for i, l in ipairs(p.lines) do
		if FS.Strip(l) == "alpha beta" then at = i end
		if FS.Strip(l) == "gamma" then at2 = i end
	end
	local lh = C.FontSize(p) + 5
	local row = at - p.view.first + 1
	local want = "beta\n" .. FS.Strip(p.lines[at + 1]) .. "\ngam"
	local realCursor, realDown = _G.GetCursorPosition, _G.IsMouseButtonDown
	local mx, my = 4 + 42, 2 + (row - 1) * lh + 1 -- ("alpha " is 6 letters of 7 px in the harness)
	_G.GetCursorPosition = function() return mx, -my end
	_G.IsMouseButtonDown = function() return true end
	C.SelectStart(p)
	mx, my = 4 + 21, 2 + (at2 - p.view.first) * lh + 1
	tick(C.frame, 0.02)
	check(C.SelectedText(p) == want, "dragging: the text from one end to the other: " .. tostring(C.SelectedText(p)))
	check(p.bands and p.bands[1] and p.bands[1]:IsShown() and p.bands[2] and p.bands[2]:IsShown(), "dragging: the selection drawn on both lines")
	_G.IsMouseButtonDown = function() return false end
	tick(C.frame, 0.02)
	local box = C.CopyBox()
	check(box and box.pane == p and box:GetText() == want, "let go: the text in the copy box: " .. tostring(box and box:GetText()))
	check((C.SelectionNote() or ""):find("3 lines", 1, true), "the status line says Ctrl+C copies it: " .. tostring(C.SelectionNote()))
	_G.IsControlKeyDown = function() return true end
	C.CopyKey(p, "LCTRL")
	check(p.sel ~= nil, "Ctrl alone keeps the selection")
	C.CopyKey(p, "C")
	_G.IsControlKeyDown = function() return false end
	T.FlushAll()
	check(p.sel == nil and box.pane == nil and C.SelectionNote() == "copied", "Ctrl+C: copied, the selection let go")
	-- a click with no drag selects nothing; a key after a selection is the pane's
	mx, my = 30, 3
	C.SelectStart(p)
	C.SelectEnd(p)
	check(p.sel == nil and box.pane == nil, "a click: nothing selected")
	mx, my = 4, 2 + (row - 1) * lh + 1
	C.SelectStart(p)
	mx = 4 + 35
	C.SelectEnd(p)
	check(box:GetText() == "alpha", "within a line: " .. tostring(box:GetText()))
	C.CopyKey(p, "PAGEUP")
	T.FlushAll()
	check(p.sel == nil and p.offset > 0, "another key: the selection let go, the key the pane's")
	C.Scroll(p, -#p.lines)
	-- clicking what a command printed: a file is cat, a folder cd and ls, Shift pins; only on the text
	local l1 = C.LinksIn("|cff00ff00x|r |Htshp:/a/b|h|cffffffffName|r|h tail")
	check(#l1 == 1 and l1[1].from == 3 and l1[1].to == 6 and l1[1].target == "/a/b" and l1[1].kind == "p", "a line's links: where they are, what they open")
	local realShift = _G.IsShiftKeyDown
	local function Click(text, shift, dx)
		C.Draw(p)
		local row
		for i = 1, p.view.count do
			if FS.Strip(p.view.lines[p.view.first + i - 1] or "") == text then row = i end
		end
		if not row then return false end
		mx, my = 4 + (dx or 10), 2 + (row - 1) * lh + 1
		_G.IsShiftKeyDown = function() return shift == true end
		C.SelectStart(p)
		C.SelectEnd(p)
		Drain()
		_G.IsShiftKeyDown = realShift
		return true
	end
	C.Run(p, "cd /") Drain()
	C.Run(p, "ls /ctest") Drain()
	check(Click("Copper Bar") and Has({ FS.Strip(table.concat(p.lines, "\n")) }, "Smelted from copper")
		and Has(p.sh.history, "cat '/ctest/Copper Bar'"), "a click on a file: cat, run as if typed: " .. tostring(p.sh.history[#p.sh.history]))
	C.Run(p, "ls /") Drain()
	check(Click("ctest/") and p.sh.cwd == "/ctest" and p.sh.history[#p.sh.history] == "cd '/ctest' && ls", "a click on a folder: cd there and ls")
	local realPlace, placedRow = ns.Maps.Place, nil
	ns.Maps.Place = function(e) placedRow = e return "set" end
	C.Run(p, "ls /ctest") Drain()
	check(Click("Copper Bar", true) and placedRow and placedRow.name == "Copper Bar", "Shift+click: pinned")
	ns.Maps.Place = realPlace
	local before = #p.sh.history
	C.Run(p, "ls /ctest") Drain()
	check(Click("Copper Bar", false, 300) and #p.sh.history == before + 1, "a click past the end of the name: nothing")
	p.lines, p.offset = { "Train  " .. SH.SearchLink("nearest class trainer", "|cff7dcfff→ search nearest class trainer|r") }, 0
	C.Draw(p)
	mx, my = 4 + 7 * 10, 3
	local link = C.LinkAt(p, mx, my)
	check(link and C.LinkLine(link) == "search nearest class trainer" and C.LinkHint(link):find("nearest class trainer", 1, true),
		"a suggestion's search link: the search it runs, said on hover")
	check(Run("echo 'it'\\''s'")[1] == "it's", "a quote inside a quoted path, as the click writes it")
	p.lines, p.offset = {}, 0
	_G.GetCursorPosition, _G.IsMouseButtonDown = realCursor, realDown
	p.body.GetHeight = realBodyH
	-- matrix (an easter egg): the rain, any key stops it
	C.Run(p, "matrix")
	Drain()
	check(p.matrix ~= nil, "matrix: the rain starts in the pane")
	for _ = 1, 5 do tick(C.frame, 0.1) end
	local rain = p.mcols and p.mcols[1] and p.mcols[1].text or ""
	check(p.matrix.drops and #p.matrix.drops > 0 and select(2, rain:gsub("\n", "")) == p.matrix.rows - 1,
		"a column of letters per column, a line per row: " .. tostring(#rain))
	p.edit:SetText("x")
	check(p.matrix == nil and p.edit:GetText() == "", "a key stops it, typing nothing")
	C.Run(p, "cmatrix")
	Drain()
	C.KeyDown(p, "LSHIFT")
	check(p.matrix ~= nil, "a modifier alone doesn't stop it")
	C.KeyDown(p, "DOWN")
	check(p.matrix == nil, "any other key does")
	-- text sizes: each pane its own, a default for all
	local fontSet
	local other = panes[2]
	local base = C.DefaultFontSize()
	p.prompt.SetFontObject = function(_, f) fontSet = f end
	C.Run(p, "font 16")
	Drain()
	check(C.FontSize(p) == 16 and fontSet == ns.Theme.FontAt(16) and C.FontSize(other) == base
		and (ns.db.console.fontSize or false) == false, "font 16: this pane only, redrawn in it")
	C.Run(p, "font +")
	Drain()
	check(C.FontSize(p) == 17, "font +: a step up")
	_G.IsControlKeyDown = function() return true end
	C.WindowKey(p, "-")
	check(C.FontSize(p) == 16 and C.FontSize(other) == base, "Ctrl+-: a step down, this pane")
	C.WindowKey(p, "0")
	_G.IsControlKeyDown = function() return false end
	check(p.fontSize == nil and C.FontSize(p) == base, "Ctrl+0: the default again")
	C.Run(p, "font 99")
	Drain()
	check(C.FontSize(p) == C.FONT_MAX, "too big: the biggest")
	C.Run(p, "font huge")
	Drain()
	check(p.lines[#p.lines]:find("reset", 1, true) ~= nil and C.FontSize(p) == C.FONT_MAX, "not a size: said, unchanged")
	C.Run(other, "font -a 20")
	Drain()
	check(ns.db.console.fontSize == 20 and C.FontSize(p) == 20 and C.FontSize(other) == 20 and p.fontSize == nil,
		"font -a 20: the default, every pane takes it (its own size let go)")
	C.Run(p, "font 12")
	Drain()
	ns:FindCommand("console").run("font 14")
	check(C.DefaultFontSize() == 14 and C.FontSize(p) == 14 and C.FontSize(other) == 14, ".console font 14 from Terminal: every pane")
	C.SetFontSize(nil)
	C.Run(p, "split")
	Drain()
	check(#panes == 4, "split with four: refused")
	for i = #panes, 1, -1 do C.ClosePane(panes[i]) end
	check(not C.IsShown() and #C.Panes() == 0, "the last pane closed: the console goes")
	ns:UnregisterCommand("ctestapp")
end)
check(ok, "console panes: " .. tostring(err))

print("[console: tiling as a tree]")
ok, err = pcall(function()
	C.Reset()
	local F = C.frame
	local realW, realH, realL, realT, realS = F.GetWidth, F.GetHeight, F.GetLeft, F.GetTop, F.GetEffectiveScale
	F.GetWidth, F.GetHeight = function() return 1016 end, function() return 636 end -- (an area of 1000 x 600)
	F.GetLeft, F.GetTop, F.GetEffectiveScale = function() return 0 end, function() return 636 end, function() return 1 end
	C.Open()
	local function R(p) local r = p.rect return r and ("%d,%d %dx%d"):format(r.x, r.y, r.w, r.h) or "none" end
	local p1 = C.Panes()[1]
	check(R(p1) == "0,0 1000x600", "one pane: all of it: " .. R(p1))
	local p2 = C.Split(p1, true) C.Layout(true)
	check(R(p1) == "0,0 497x600" and R(p2) == "503,0 497x600", "a wide pane split: side by side, halves: " .. R(p1) .. " / " .. R(p2))
	local p3 = C.Split(p2, true) C.Layout(true)
	check(R(p1) == "0,0 497x600" and R(p2) == "503,0 497x297" and R(p3) == "503,303 497x297",
		"a tall pane split: one above the other, the others where they were: " .. R(p2) .. " / " .. R(p3))
	-- (the player's case: three panes, the third split: it halves, nothing else moves)
	local p4 = C.Split(p3, true) C.Layout(true)
	check(R(p1) == "0,0 497x600" and R(p2) == "503,0 497x297" and R(p3) == "503,303 246x297" and R(p4) == "755,303 245x297",
		"the third split: it alone halves, side by side: " .. R(p3) .. " / " .. R(p4))
	C.ClosePane(p4) C.Layout(true)
	check(R(p3) == "503,303 497x297", "closed: the room back to the one it was split from: " .. R(p3))
	-- dragging the first split's gap, then a double click evens it
	local first
	for _, sp in ipairs(C.splits) do if sp.node.dir == "v" then first = sp end end
	check(first and first.x == 497 and first.w == 6 and C.SplitAt(499, 100) == first and not C.SplitAt(300, 100), "the gaps can be found under the mouse")
	local realCursor, realDown, realGT, clock = _G.GetCursorPosition, _G.IsMouseButtonDown, _G.GetTime, 100
	_G.GetTime = function() return clock end
	local mx, my = 499, 100
	_G.GetCursorPosition = function() return mx + C.PAD, 636 - C.PAD - my end
	_G.IsMouseButtonDown = function() return true end
	C.GapDown()
	mx = 700
	C.GapTick()
	check(math.abs(p1.rect.w - 697) <= 1 and p2.rect.x >= 702, "dragged: the split follows the mouse: " .. R(p1) .. " / " .. R(p2))
	_G.IsMouseButtonDown = function() return false end
	C.GapTick() C.GapUp()
	clock = 105
	for _, sp in ipairs(C.splits) do if sp.node.dir == "v" then mx = sp.x + 2 end end
	C.GapDown() C.GapUp()
	clock = 105.2
	C.GapDown() C.GapUp()
	check(R(p1) == "0,0 497x600", "a double click on the gap: even again: " .. R(p1))
	-- (review, 0.67.9) the gap under the mouse is lit, and placed again only when it's another: this runs every frame
	local realOver = C.frame.IsMouseOver
	C.frame.IsMouseOver = function() return true end
	for _, sp in ipairs(C.splits) do if sp.node.dir == "v" then mx = sp.x + 2 end end
	C.GapHover()
	local div
	for i = 1, 60 do
		local n, v = debug.getupvalue(C.GapHover, i)
		if not n then break end
		if n == "divider" then div = v end
	end
	local placed = 0
	local realSet = div and div.SetPoint
	if div then div.SetPoint = function(self, ...) placed = placed + 1 return realSet(self, ...) end end
	C.GapHover() C.GapHover() C.GapHover()
	check(div and div:IsShown() and placed == 0, "the lit gap isn't placed again while the mouse stays on it: " .. placed)
	mx = 300
	C.GapHover()
	check(div and not div:IsShown(), "off the gap: not lit")
	if div then div.SetPoint = realSet end
	C.frame.IsMouseOver = realOver
	_G.GetCursorPosition, _G.IsMouseButtonDown, _G.GetTime = realCursor, realDown, realGT
	-- the other layouts lay them out their own way; tile again: the tree as it was
	C.Run(p1, "layout grid")
	for _ = 1, 50 do if not p1.job then break end C.frame:GetScript("OnUpdate")(C.frame, 0.02) end
	check(R(p1) == "0,0 497x600" and R(p2) == "503,0 497x297" and not C.SplitAt(499, 100), "grid with three: its own way, no gaps to drag")
	C.Run(p1, "layout tile")
	for _ = 1, 50 do if not p1.job then break end C.frame:GetScript("OnUpdate")(C.frame, 0.02) end
	check(R(p3) == "503,303 497x297", "tile again: as it was")
	-- through a /reload: the tree kept, its splits too
	for _, sp in ipairs(C.splits) do if sp.node.dir == "h" then sp.node.ratio = 0.3 end end
	C.SaveSession()
	local kept = ns.db.consoleData.session
	C.Reset()
	ns.db.consoleData.session = kept
	C.Open() C.Layout(true)
	local q = C.Panes()
	check(#q == 3 and R(q[1]) == "0,0 497x600" and q[2].rect.h < q[3].rect.h, "after a reload: the same tiles, the split where it was: " .. R(q[2]) .. " / " .. R(q[3]))
	C.Reset()
	C.Close("exit")
	F.GetWidth, F.GetHeight, F.GetLeft, F.GetTop, F.GetEffectiveScale = realW, realH, realL, realT, realS
end)
check(ok, "console tiling: " .. tostring(err))

print("[console: through a /reload]")
ok, err = pcall(function()
	C.Reset()
	C.Open()
	local tick = C.frame:GetScript("OnUpdate")
	local function Drain(p) for _ = 1, 200 do if not p.job then break end tick(C.frame, 0.02) end end
	local a = C.Focused()
	C.Run(a, "cd /ctest") Drain(a)
	C.Run(a, "layout wide") Drain(a)
	C.Run(a, "echo kept line") Drain(a)
	local b = C.Split(a)
	C.Run(b, "echo second pane") Drain(b)
	C.SetFontSize(17, b)
	C.Focus(b)
	-- the interface goes (a /reload sends PLAYER_LOGOUT): kept; then everything is gone as after the reload
	C.saver:GetScript("OnEvent")(C.saver, "PLAYER_LOGOUT")
	local kept = ns.db.consoleData.session
	check(kept and #kept.panes == 2 and kept.layout == "wide" and kept.focus == 2, "PLAYER_LOGOUT keeps the panes, the layout, the focus")
	C.Reset()
	check(ns.db.consoleData.session == nil, ".console reset forgets them")
	ns.db.consoleData.session = kept
	C.Open()
	local panes = C.Panes()
	local last = panes[1] and panes[1].lines[#panes[1].lines] or ""
	check(#panes == 2 and panes[1].sh.cwd == "/ctest" and FS.Strip(panes[1].lines[#panes[1].lines - 1] or "") == "kept line"
		and FS.Strip(last):find("restored", 1, true), "after the reload: the pane's place and lines, saying so: " .. FS.Strip(last))
	check(FS.Strip(panes[2].lines[#panes[2].lines - 1] or "") == "second pane" and C.FontSize(panes[2]) == 17 and C.Focused() == panes[2],
		"the second pane: its lines, its text size, the keyboard")
	C.SaveSession()
	check(ns.db.consoleData.session.layout == "wide", "the layout as it was: " .. tostring(ns.db.consoleData.session.layout))
	-- the last pane closed: nothing to bring back
	for i = #panes, 1, -1 do C.ClosePane(panes[i]) end
	check(ns.db.consoleData.session == nil, "the last pane closed: nothing kept")
	C.Open()
	check(#C.Panes() == 1 and not FS.Strip(table.concat(C.Panes()[1].lines, " ")):find("restored", 1, true), "a fresh console then")
	C.Reset()
	C.Close("exit")
end)
check(ok, "console reload: " .. tostring(err))

print("[console: suggestions, Ctrl+R, z, prompt, theme]")
ok, err = pcall(function()
	local o
	local Paint, Theme = SH.Paint, ns.Theme
	-- fish's suggestion, the usage line, the history search
	local hs = SH.Session({ history = { "ls -l /ctest", "cat linen", "ls -lN" } })
	check(SH.Suggest(hs, "ls") == " -lN" and SH.Suggest(hs, "ls -l ") == "/ctest" and SH.Suggest(hs, "x") == nil
		and SH.Suggest(hs, "") == nil and SH.Suggest(hs, "ls -lN") == nil, "suggest: the rest of the newest line starting with what's typed")
	check((FS.Strip(SH.UsageHint("cat x | grep -i", 15) or "")):find("grep", 1, true) == 1, "the usage of the command the cursor is in: "
		.. FS.Strip(SH.UsageHint("cat x | grep -i", 15) or ""))
	check(SH.UsageHint("nosuchcmd", 9) == nil and SH.UsageHint("", 0) == nil, "nothing for an unknown command")
	check(SH.HistorySearch(hs, "LS") == 3 and SH.HistorySearch(hs, "ls", 3) == 1 and SH.HistorySearch(hs, "ls", 1) == nil
		and SH.HistorySearch(hs, "") == nil, "history search: the newest first, any case, before an index")

	C.Open()
	local p = C.Focused()
	local tick = C.frame:GetScript("OnUpdate")
	local function Drain() for _ = 1, 50 do if not p.job then break end tick(C.frame, 0.05) end end
	local h = p.sh.history
	local keptHistory = {}
	for i, l in ipairs(h) do keptHistory[i] = l end
	for i = #h, 1, -1 do h[i] = nil end
	h[1], h[2], h[3] = "ls -l /ctest", "cat linen", "echo found it"
	p.edit:SetText("ec")
	check(p.suggestion == "ho found it" and FS.Strip(p.overlay.text) == "echo found it",
		"typed: the rest of a line from the history, faint after it: " .. FS.Strip(tostring(p.overlay.text)))
	check(C.usageNote == nil, "no usage line for a word that isn't a command yet")
	C.KeyDown(p, "RIGHT")
	check(p.edit:GetText() == "echo found it" and p.suggestion == nil, "Right takes it: " .. p.edit:GetText())
	check((FS.Strip(C.usageNote or "")):find("echo", 1, true) == 1, "the status bar: echo's usage: " .. FS.Strip(C.usageNote or ""))
	local realAlt = _G.IsAltKeyDown
	p.edit:SetText("ls")
	_G.IsAltKeyDown = function() return true end
	C.KeyDown(p, "RIGHT")
	_G.IsAltKeyDown = realAlt
	check(p.edit:GetText() == "ls -l", "Alt+Right: one word of it: " .. p.edit:GetText())

	-- Ctrl+R
	local function CtrlR()
		_G.IsControlKeyDown = function() return true end
		C.KeyDown(p, "R")
		_G.IsControlKeyDown = function() return false end
	end
	p.edit:SetText("")
	CtrlR()
	check(p.isearch and FS.Strip(C.PromptText(p)):find("(reverse-i-search)", 1, true) == 1, "Ctrl+R: the history searched")
	p.edit:SetText("l")
	check(p.isearch.line == "cat linen" and FS.Strip(p.overlay.text) == "l': cat linen",
		"the newest line holding it, after it: " .. FS.Strip(tostring(p.overlay.text)))
	CtrlR()
	check(p.isearch.line == "ls -l /ctest" and not p.isearch.failed, "Ctrl+R again: an older one")
	CtrlR()
	check(p.isearch.line == "ls -l /ctest" and p.isearch.failed and FS.Strip(C.PromptText(p)):find("failed", 1, true),
		"none older: the line stays, the prompt says it failed")
	p.edit:SetText("echo")
	check(p.isearch.line == "echo found it" and not p.isearch.failed, "typing searches again from the newest")
	C.Enter(p)
	Drain()
	check(p.isearch == nil and FS.Strip(p.lines[#p.lines]) == "found it", "Enter runs the line found: " .. FS.Strip(p.lines[#p.lines] or ""))
	p.edit:SetText("draft")
	CtrlR()
	p.edit:SetText("cat")
	p.edit:GetScript("OnEscapePressed")(p.edit)
	check(p.isearch == nil and p.edit:GetText() == "draft", "Esc lets go: the line as it was")
	CtrlR()
	p.edit:SetText("cat")
	C.KeyDown(p, "RIGHT")
	check(p.isearch == nil and p.edit:GetText() == "cat linen", "Right takes the line found, to edit")
	p.edit:SetText("")
	for i = #h, 1, -1 do h[i] = nil end
	for i, l in ipairs(keptHistory) do h[i] = l end

	-- z: frecency, zoxide's matching
	local now = 1000000
	check(SH.ZScore({ r = 2, t = now - 100 }, now) == 8 and SH.ZScore({ r = 2, t = now - 2 * 86400 }, now) == 1
		and SH.ZScore({ r = 2, t = 0 }, now) == 0.5, "frecency: visits weighed by how long ago")
	check(SH.ZMatches("/npc/Orgrimmar trainers", { "org", "TRAIN" }) and not SH.ZMatches("/npc/Orgrimmar", { "npc" })
		and not SH.ZMatches("/npc/Orgrimmar", { "org", "npc" }) and SH.ZMatches("/x", {}),
		"z's words: in order, any case, the last in the folder's own name")
	local realAge = SH.Z_AGE
	SH.Z_AGE = 3
	ns.db.consoleData.z = { ["/old"] = { r = 1, t = 0 } }
	for _ = 1, 3 do SH.ZAdd("/new", now) end
	check(ns.db.consoleData.z["/old"] == nil and math.abs(ns.db.consoleData.z["/new"].r - 2.7) < 1e-9, "past the cap every rank ages; under 1 is forgotten")
	SH.Z_AGE = realAge
	ns.db.consoleData.z = nil
	Run("cd /ctest")
	Run("cd /tmp")
	Run("cd /ctest")
	Run("cd /")
	Run("z CT")
	check(Run("pwd")[1] == "/ctest", "z: the folder cd went to that the words match")
	Run("z")
	check(Run("pwd")[1] == "/", "z alone: /")
	o = Run("z -l")
	check(#o == 2 and o[1]:find("/ctest", 1, true) and o[2]:find("/tmp", 1, true), "z -l: best first: " .. table.concat(o, " / "))
	o, err = Run("z nothing")
	check(err == 1 and Has(o, "no match found"), "z: nothing kept matches")
	Run("z -x /tmp")
	check(#SH.ZList({}) == 1, "z -x forgets one")
	Run("z /tmp")
	check(Run("pwd")[1] == "/tmp" and #SH.ZList({}) == 2, "z with a real path goes there, as cd, and keeps it")
	Run("cd /ctest")
	Run("z t")
	check(Run("pwd")[1] == "/tmp", "the folder you're in is never where z takes you (as zoxide)")
	check(SH.Complete(sh, "z ct", 4) == "z ctest ", "Tab after z: the folders kept")
	ns.db.consoleData.z = nil
	Run("cd /")

	-- the prompt
	local pretty = FS.Pretty(sh.cwd)
	check(FS.Strip(SH.PromptLine(sh)) == FS.User() .. "@" .. FS.Host() .. ":" .. pretty .. "$ ", "the classic prompt by default")
	Run("prompt starship")
	check(ns.db.console.prompt == "starship", "prompt starship: kept")
	local real = { zone = _G.GetRealZoneText, sub = _G.GetSubZoneText, lvl = _G.UnitLevel, money = _G.GetMoney, cc = _G.C_Container }
	_G.GetRealZoneText, _G.GetSubZoneText = function() return "Durotar" end, function() return "Razor Hill" end
	_G.UnitLevel, _G.GetMoney = function() return 23 end, function() return 123456 end
	_G.C_Container = { GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end, GetContainerNumFreeSlots = function() return 3, 0 end }
	sh.status, sh.took = 0, 3
	local line = FS.Strip(SH.PromptLine(sh))
	check(line == pretty .. " in Razor Hill lvl 23 12g 34s 56c bags 3/16 took 3s \194\187 ", "starship: where, level, gold, bags, took: " .. line)
	sh.took = 1
	check(not FS.Strip(SH.PromptLine(sh)):find("took", 1, true), "a quick command doesn't say how long")
	Run("prompt dir bogus")
	check(ns.db.console.prompt == "starship", "a part there isn't: refused")
	Run("prompt dir gold status")
	sh.status = 1
	line = SH.PromptLine(sh)
	check(FS.Strip(line) == pretty .. " 12g 34s 56c [1] \194\187 " and line:find(SH.C.red .. "\194\187", 1, true),
		"your own parts, the failed status, the end in red: " .. FS.Strip(line))
	_G.GetRealZoneText, _G.GetSubZoneText, _G.UnitLevel, _G.GetMoney, _G.C_Container = real.zone, real.sub, real.lvl, real.money, real.cc
	Run("true")
	check(type(sh.took) == "number" and sh.status == 0, "each line's time and status kept for the prompt")
	check(SH.Complete(sh, "prompt star", 11) == "prompt starship ", "Tab: the presets")
	Run("prompt classic")
	check(ns.db.console.prompt == nil and FS.Strip(SH.PromptLine(sh)):sub(-2) == "$ ", "prompt classic: back as it was")
	-- (0.68.0, the player's screenshot) the presets list draws classic as classic, whatever prompt you have
	Run("prompt starship")
	local o = Run("prompt")
	local classicLine
	for _, l in ipairs(o) do if l:find("^%s*classic") then classicLine = l end end
	check(classicLine and classicLine:find(FS.User() .. "@" .. FS.Host() .. ":", 1, true) and classicLine:find("$ ", 1, true),
		"prompt: the classic preset shown as user@host:dir$, not as starship: " .. tostring(classicLine))
	Run("prompt classic")

	-- themes
	local red = Paint("red", "x")
	C.Run(p, "echo " .. "done")
	p.lines[#p.lines + 1] = red
	C.Run(p, "theme dracula")
	Drain()
	check(SH.C.red == "ff5555" and ns.db.console.theme == "dracula", "theme dracula: the colours, kept")
	local found = false
	for _, l in ipairs(p.lines) do if l == "|cffff5555x|r" then found = true end end
	check(found, "the pane's lines already printed in the new colours")
	local r, g, b = Theme.RGB("282a36")
	check(p.frame.bgColor and math.abs(p.frame.bgColor[1] - r) < 1e-6 and math.abs(p.frame.bgColor[3] - b) < 1e-6, "the pane's background too")
	check(SH.Blocks()[1][2] == "ff5555", "neofetch's blocks in the scheme's colours")
	o = Run("theme")
	check(Has(o, "* dracula") and Has(o, "nord") and #o == #SH.THEME_ORDER, "theme lists them, the one in use marked")
	o, err = Run("theme nope")
	check(err == 1 and SH.C.red == "ff5555", "a scheme there isn't")
	local realClass = _G.UnitClass
	_G.UnitClass = function() return "Mage", "MAGE" end
	local cls = SH.ThemeOf("class")
	_G.UnitClass = realClass
	check(cls.cyan == cls.caret and cls.caret == cls.focus and cls.cyan ~= SH.THEMES.tokyonight.cyan and cls.bg == SH.THEMES.tokyonight.bg,
		"class: Tokyo Night in your class's colour: " .. tostring(cls.cyan))
	check(SH.Complete(sh, "theme dr", 8) == "theme dracula ", "Tab: the schemes")
	local map = SH.SetTheme("gruvbox")
	check(map["ff5555"] == "fb4934" and SH.Recolor("|cffff5555x|r and |cff123456y|r", map) == "|cfffb4934x|r and |cff123456y|r",
		"recolouring: the old scheme's colours only")
	C.Run(p, "theme tokyonight")
	Drain()
	check(SH.C.red == "f7768e" and ns.db.console.theme == nil, "back to Tokyo Night")
	C.Reset()
	C.Close("exit")
end)
check(ok, "console as you type: " .. tostring(err))

print("[console: a password typed is never shown or kept]")
ok, err = pcall(function()
	ns.db.consoleData = ns.db.consoleData or {}
	ns.db.consoleData.history = { "ls", "ssh password oldsecret", "share join raid oldsecret" }
	C.Reset()
	C.Open()
	local p = C.Focused()
	local tick = C.frame:GetScript("OnUpdate")
	local function Drain() for _ = 1, 50 do if not p.job then break end tick(C.frame, 0.05) end end
	local h = p.sh.history
	check(#h == 1 and h[1] == "ls", "a password kept before is dropped from the saved history: " .. table.concat(h, " / "))
	p.edit:SetText("ssh password hunter2")
	check(FS.Strip(p.overlay.text) == "ssh password *******" and p.edit.textColor[4] == 0,
		"typed: the password drawn as *s, the box's own text hidden: " .. FS.Strip(tostring(p.overlay.text)))
	p.edit:SetText("ssh password " .. ("x"):rep(400))
	check(not FS.Strip(p.overlay.text):find("x", 1, true) and p.edit.textColor[4] == 0, "a password too long for the line still hidden")
	p.edit:SetText("ssh password hunter2")
	C.Enter(p)
	Drain()
	local seen, masked = false, false
	for _, l in ipairs(p.lines) do
		if l:find("hunter2", 1, true) then seen = true end
		if FS.Strip(l):find("ssh password *******", 1, true) then masked = true end
	end
	check(not seen and masked and not (p.jobText or ""):find("hunter2", 1, true), "the line run is shown masked")
	check(#h == 1 and h[1] == "ls", "the password line isn't kept in the history")
	p.edit:SetText("share join raid pw2")
	check(FS.Strip(p.overlay.text) == "share join raid ***", "share join: the group shown, its password not")
	p.edit:SetText("")
	C.Reset()
	C.Close("exit")
end)
check(ok, "console passwords: " .. tostring(err))

print("[console: lines wider than the pane slide sideways]")
ok, err = pcall(function()
	C.Reset()
	C.Open()
	local p = C.Focused()
	local tick = C.frame:GetScript("OnUpdate")
	local function Drain() for _ = 1, 50 do if not p.job then break end tick(C.frame, 0.05) end end
	p.body.h = 300 -- (the mock's frames have no height of their own)
	local long = ("x"):rep(100) .. "END"
	C.Run(p, "echo " .. long)
	Drain()
	C.Draw(p)
	local function LongRow()
		for _, r in ipairs(p.rows) do if (r.text or ""):find("^x+END$") then return r end end -- (echo's line, not the command's)
	end
	local r = LongRow()
	-- (0.68.13, the player's screenshots: the game's clipping let lines run on over the next pane; each row is cut itself)
	local room = (p.body:GetWidth() or 0) - 8
	check(r and r.lastPoint and r.lastPoint[1] == "TOPLEFT" and r.lastPoint[2] == p.sheet and r.lastPoint[4] == 0
		and r.w == room, "a long line starts at the left edge and ends at the pane's right one: " .. tostring(r and r.w))
	p.clip:GetScript("OnSizeChanged")(p.clip, 380, 290)
	check(p.clip.__kind == "ScrollFrame" and p.sheet.w == 380 and p.sheet.h == 290,
		"the lines on a ScrollFrame's child (what cuts text at the pane's edges in the game), sized to its room")
	check(p.view.most > 0 and FS.Strip(p.titleRight.text or ""):find("[col 1/", 1, true),
		"the title says the lines run past the pane: " .. FS.Strip(p.titleRight.text or ""))
	local realShift = _G.IsShiftKeyDown
	_G.IsShiftKeyDown = function() return true end
	p.frame:GetScript("OnMouseWheel")(p.frame, -1)
	_G.IsShiftKeyDown = realShift
	C.Draw(p)
	local step = C.SIDE_CHARS * C.Width("0", p)
	r = LongRow()
	check(p.view.hx == step and r.lastPoint[4] == 0 and r.text == ("x"):rep(100 - C.SIDE_CHARS) .. "END" and r.w == room,
		"Shift+wheel down: the lines slide left, what's past the left edge cut off, not drawn there: "
		.. tostring(r and r.lastPoint[4]) .. " " .. tostring(r and #r.text))
	-- (a part of a character past the edge: cut, the rest starting a little right of it; colours kept)
	local cut, off = C.CutLeft(p, "|cffff0000abc|rdef", 10) -- (7 px a letter here: a and b go, c starts 4 px in)
	check(cut == "|cffff0000c|rdef" and off == 4, "cutting a coloured line: " .. cut .. " " .. off)
	p.edit:SetText("")
	C.KeyDown(p, "RIGHT")
	C.Draw(p)
	check(p.view.hx == step + C.HalfWidth(p), "Right on an empty line: half a pane further")
	for _ = 1, 5 do C.KeyDown(p, "RIGHT"); C.Draw(p) end
	check(p.view.hx == p.view.most, "never past the widest line's end")
	C.KeyDown(p, "LEFT")
	C.Draw(p)
	check(p.view.hx == p.view.most - C.HalfWidth(p), "Left: back again")
	p.edit:SetText("ls")
	local before = p.view.hx
	C.KeyDown(p, "RIGHT")
	C.Draw(p)
	check(p.view.hx == before, "with something typed, Left/Right are the line's own")
	-- (0.68.13, the player's screenshot) a narrow pane: the input line's prompt shortened and cut, not run on past its edge
	local wasW = p.body.w
	p.body.w = 150
	C.UpdateInput(p)
	check(p.prompt.text == SH.PromptLine(p.sh, "char") and p.prompt.w == 142,
		"a narrow pane: only the prompt's end, cut to the pane: " .. FS.Strip(p.prompt.text or "") .. " " .. tostring(p.prompt.w))
	p.body.w = 3000
	C.UpdateInput(p)
	check(p.prompt.text == C.PromptText(p), "a wide one: the prompt as set: " .. FS.Strip(p.prompt.text or ""))
	p.body.w = wasW
	C.UpdateInput(p)
	p.edit:SetText("")
	C.Run(p, "true")
	Drain()
	C.Draw(p)
	check(p.view.hx == 0, "a command run: back to the left edge")
	C.Pager(p, { "short", long }, { title = "x" })
	C.Draw(p)
	C.KeyDown(p, "RIGHT")
	C.Draw(p)
	check(p.pager and p.view.hx == C.HalfWidth(p), "the pager: Right slides, as less -S")
	C.ClosePager(p)
	C.Draw(p)
	check(p.view.hx == 0, "the pager closed: from the left edge again")
	C.Reset()
	C.Close("exit")
end)
check(ok, "console sideways: " .. tostring(err))

print("[console: sudo rm -rf /]")
ok, err = pcall(function()
	o = Run("rm -rf /")
	check(Has(o, "dangerous to operate recursively"), "rm -rf /: GNU rm's refusal")
	check(Has(Run("sudo ls"), "not in the sudoers file"), "sudo anything else: no")
	o = Run("sudo rm -rf /")
	check(Has(o, "removed directory '/ctest'"), "sudo rm -rf / without a console: only the words")
	C.Open()
	local p = C.Focused()
	C.Run(p, "echo before")
	local linesBefore, histBefore = #p.lines, #p.sh.history
	local tick = C.frame:GetScript("OnUpdate")
	local realGT, clock = _G.GetTime, 0
	_G.GetTime = function() clock = clock + 1 return clock end
	C.Run(p, "sudo rm -rf /")
	for _ = 1, 200 do if not C.IsShown() then break end tick(C.frame, 0.05) end
	_G.GetTime = realGT
	check(not C.IsShown() and C.black and C.black:IsShown(), "sudo rm -rf /: the console stepped out of, the screen black")
	local trace = false
	for _, l in ipairs(p.lines) do if l:find("sudo", 1, true) or l:find("removed directory", 1, true) then trace = true end end
	check(#C.Panes() == 1 and #p.lines == linesBefore and not trace and #p.sh.history == histBefore,
		"the pane that ran it as if it never had: its lines and its history line taken back: " .. #C.Panes() .. " " .. #p.lines .. "/" .. linesBefore
		.. " " .. tostring(trace) .. " " .. #p.sh.history .. "/" .. histBefore .. " " .. tostring(p.lines[#p.lines]))
	T.FlushAll()
	local fade = C.black:GetScript("OnUpdate")
	if fade then fade(C.black, 1) end
	check(not C.black:IsShown(), "then the interface comes back")
	C.Open()
	check(C.IsShown() and C.Focused() == p and FS.Strip(p.lines[#p.lines]) == "before", ".console: everything as it was")
	C.ClosePane(p)
end)
check(ok, "console wipe: " .. tostring(err))

ns:UnregisterCommand("ctestcmd")
ns.providers, ns.providerOrder = saved.providers, saved.order
ns:AliasesChanged()
FS.Forget()
for k in pairs(FS.tmp) do FS.tmp[k] = nil end
if C.IsShown() then C.Close("exit") end
ns.Zen.Force(false)
ns.Zen.Opened = realOpened
T.FlushAll()

io.write("[console: a big list's folders made with less work]\n")
do
	-- (0.68.13, review over QuestieDB's 13,000 NPCs) a name with nothing to clean is itself; one with codes is cleaned
	check(FS.Clean("Innkeeper Farley") == "Innkeeper Farley" and FS.Clean(" a/b ") == "a\226\136\149b"
		and FS.Clean("|cffff0000Red|r") == "Red" and FS.Clean("") == "?", "FS.Clean: as before, quicker for plain names")
	-- an NPC's roles worked out once while the row lives
	local IS = ns.Filters._.IS
	local real, calls = IS.innkeeper, 0
	IS.innkeeper = function(e) calls = calls + 1 return real(e) end
	FS.ForgetRoles()
	local row = { kind = "npc", npcID = 99001, name = "Someone" }
	FS.Roles(row); FS.Roles(row); FS.Roles(row)
	IS.innkeeper = real
	check(calls == 1, "an NPC's roles asked once, not every listing: " .. calls)
end
