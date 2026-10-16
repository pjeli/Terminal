-- (0.52.13, the player's ask) Advanced mode's "|" standing alone sums up what a search found: "in:bags | sum value" (what
-- it would all sell for at a vendor), "| group by zone", "| count by quality", "| sum value by zone"; a group's Enter keeps
-- its rows ("| zone:\"Elwynn Forest\"").
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L = ns.L
local A = ns.Aggregate

io.write("[aggregate: | count, | sum value, | group by zone]\n")

-- reading the steps
do
	local q, steps = A.Split("in:bags | sum value")
	check(q == "in:bags" and steps and steps[1] == "sum value", "split at a | standing alone")
	q, steps = A.Split("sword|axe q:rare|epic")
	check(q == "sword|axe q:rare|epic" and steps == nil, "a|b is still either")
	q, steps = A.Split('"a | b" | count')
	check(q == '"a | b"' and steps and steps[1] == "count", "not inside quotes")
	local s = A.ParseStep("sum by value")
	check(s.op == "sum" and s.field == "value" and s.by == nil, "sum by value = sum value")
	s = A.ParseStep("sum value by zone")
	check(s.op == "sum" and s.field == "value" and s.by == "zone", "sum value by zone")
	s = A.ParseStep("group by zone")
	check(s.op == "group" and s.by == "zone", "group by zone")
	s = A.ParseStep("count by q")
	check(s.op == "group" and s.by == "quality", "count by q: a group by quality")
	s = A.ParseStep("count")
	check(s.op == "count", "count alone")
	s = A.ParseStep("avg ilvl by slot")
	check(s.op == "avg" and s.field == "ilvl" and s.by == "slot", "avg ilvl by slot")
	check(A.ParseStep("sum zone").bad and A.ParseStep("sum").bad and A.ParseStep("group").bad and A.ParseStep("frobnicate").bad,
		"what isn't a step says so")
	s = A.ParseStep('zone:"Elwynn Forest"')
	check(s.where == "zone" and s.value == "elwynn forest" and s.exact, "a keeping step: field:\"value\"")
	local spec = A.Parse({ "q:rare", "sum value" }, "@item")
	check(not spec.bad and #spec.wheres == 1 and spec.last.op == "sum" and spec.base == "@item | q:rare", "steps chain")
	check(A.Parse({ "sum value", "count" }, "x").bad, "a sum is the last step")
end

do
	local save = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode, gii = C_Item.GetItemInfo }
	local INFO = { -- name, link, quality, ilvl, minLevel, type, subType, stack, equipLoc, texture, sellPrice
		[990001] = { "Linen Cloth", "l", 1, 5, 0, "Tradeskill", "Cloth", 20, "", 1, 13 },
		[990002] = { "Wool Cloth", "l", 1, 15, 0, "Tradeskill", "Cloth", 20, "", 1, 33 },
		[990003] = { "Rare Ring", "l", 3, 30, 25, "Armor", "Miscellaneous", 1, "INVTYPE_FINGER", 1, 1500 },
	}
	C_Item.GetItemInfo = function(id)
		local t = INFO[id]
		if t then return unpack(t) end
		return save.gii(id)
	end
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
		local rows = {
			{ name = "Linen Cloth", key = 990001, itemID = 990001, count = 20, zone = "Elwynn Forest" },
			{ name = "Wool Cloth", key = 990002, itemID = 990002, count = 5, zone = "Westfall" },
			{ name = "Rare Ring", key = 990003, itemID = 990003, count = 1, zone = "Elwynn Forest" },
			{ name = "Mystery Thing", key = 990004, itemID = 990004, count = 2 },
		}
		for i = 1, 150 do rows[#rows + 1] = { name = "Bolt " .. i, key = "bolt" .. i } end
		return rows
	end })
	ns:AliasesChanged()
	ns.db.easyMode = false
	UI:EasyChanged()
	UI.lastScan, UI.lastOverview = nil, nil
	local function Rows(text)
		UI:Open(text)
		FlushAll()
		return UI.Results()
	end

	local r = Rows("cloth | sum value")
	check(#r == 1 and r[1].name == ns.Gold.Text(20 * 13 + 5 * 33) and r[1].kind == "aggregate",
		"sum value: what it'd sell for, the count each times its price: " .. tostring(r[1] and r[1].name))
	r = Rows("@item | count")
	check(#r == 1 and r[1].name == L["%d results"]:format(154), "count: every match, past the 100 a list shows: " .. tostring(r[1] and r[1].name))
	r = Rows("@item -bolt | group by zone")
	-- (0.53.4, the player: "group by raid" had a "no raid" group of 3164) what has no zone is left out, not a group
	check(#r == 2 and r[1].name == "Elwynn Forest" and r[1].detail == L["%d results"]:format(2) and r[2].name == "Westfall",
		"group by zone: the biggest first; what has none left out: " .. #r .. " " .. tostring(r[1] and r[1].name) .. "/"
		.. tostring(r[#r] and r[#r].name))
	r = Rows("@item -bolt | sum value by zone")
	check(r[1].name == L["All: %s"]:format(ns.Gold.Text(260 + 165 + 1500)) and r[2].name == "Elwynn Forest"
		and r[2].detail:find(ns.Gold.Text(1760), 1, true), "sum value by zone: all of it on top, then each zone's: "
		.. tostring(r[1].name) .. " / " .. tostring(r[2].detail))
	check(r[1].detail:find(L["%d results"]:format(3), 1, true) and #r == 3, "the row with no zone isn't in it: " .. r[1].detail)
	r = Rows("@item -bolt | sum value by kind")
	check(r[1].detail:find(L["%d with no %s"]:format(1, L["value"]), 1, true), "the row with no price is said: " .. r[1].detail)

	-- (release review) an average of a group with nothing to average: "-", not its count
	r = Rows("@item mystery | avg ilvl by kind")
	check(r[1] and r[1].detail:sub(1, 1) == "-", "avg with nothing to average: - : " .. tostring(r[1] and r[1].detail))
	-- (review, 0.53.6) a number's step is kept by its range; a group's Enter after a step ends with a space; close
	-- spellings aren't counted; money isn't a group
	r = Rows("@item -bolt | lvl:20-30")
	check(#r == 1 and r[1].name == "Rare Ring", "| lvl:20-30: the level-25 ring: " .. #r)
	r = Rows("@item -bolt | lvl:2")
	check(#r == 0, "| lvl:2: not the level-25 ring (\"2\" in \"25\"): " .. #r)
	check(A.ParseStep("lvl:abc").bad and A.ParseStep("group by value").bad and A.ParseStep("sum count by price").bad,
		"| lvl:abc says what goes there; copper amounts aren't groups")
	r = Rows("@item -bolt | q:rare | group by level")
	UI:Activate(1); FlushAll()
	check(UI.edit:GetText():sub(-1) == " " and not (UI.Results()[1] and UI.Results()[1].syntaxRow),
		"a group's Enter after a step: a space after it, the rows listed (not q:'s values): \"" .. UI.edit:GetText() .. "\"")
	r = Rows("@item linnen | count")
	check(r[1] and r[1].name == L["%d results"]:format(0), "a count of a misspelling: 0, not the close spellings: " .. tostring(r[1] and r[1].name))

	-- Enter on a total: said in the chat window, the search kept in the history
	local printed
	local realPrint = ns.Print
	ns.Print = function(_, msg) printed = msg end
	Rows("cloth | sum value")
	UI:Activate()
	FlushAll()
	ns.Print = realPrint
	check(printed and printed:find(ns.Gold.Text(425, true), 1, true) and not UI:IsShown(), "Enter on a total: said in chat: " .. tostring(printed))
	local hist = ns.db.history or {}
	local inHist = false
	for _, l in ipairs(hist) do if l == "cloth | sum value" then inHist = true end end
	check(inHist, "and the search is in the history")
	-- a group named with quote marks: Enter still finds its rows
	ns.providers.items._dirty = true

	-- a group's Enter: its rows (Shift+Left goes back)
	r = Rows("@item -bolt | group zone")
	UI:Activate(1)
	FlushAll()
	check(UI.edit:GetText() == '@item -bolt in:"Elwynn Forest" ' and UI:IsShown(), "Enter on a group: its rows, by the filter for it (0.53.1): "
		.. UI.edit:GetText())
	local got = {}
	for _, e in ipairs(UI.Results()) do got[#got + 1] = e.name end
	table.sort(got)
	check(table.concat(got, ",") == "Linen Cloth,Rare Ring", "the group's rows: " .. table.concat(got, ","))

	-- (0.53.1) a quality group's Enter: the filter you'd type, no "|"
	r = Rows("@item -bolt | count by quality")
	UI:Activate(1)
	FlushAll()
	check(UI.edit:GetText() == "@item -bolt q:rare " and UI.Results()[1] and UI.Results()[1].name == "Rare Ring",
		"Enter on the Rare group: @item -bolt q:rare: " .. UI.edit:GetText() .. " / " .. tostring(UI.Results()[1] and UI.Results()[1].name) .. " #" .. #UI.Results())

	-- chained: keep, then sum
	r = Rows("@item | q:rare | sum value")
	check(#r == 1 and r[1].name == ns.Gold.Text(1500), "q:rare then sum value: " .. tostring(r[1] and r[1].name))
	local realColors = _G.ITEM_QUALITY_COLORS
	_G.ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" }, [3] = { hex = "|cff0070dd" } } -- (the game's: hex has the |c)
	r = Rows("@item -bolt | count by quality")
	_G.ITEM_QUALITY_COLORS = realColors
	local plainName = ns.Plain(r[1].name)
	check(r[1].name:sub(1, 10) == "|cff0070dd" and not r[1].name:find("|c|c", 1, true) and (plainName == "rare" or plainName == "Rare"),
		"by quality: the best first, in its colour (no stray |c): " .. tostring(r[1].name))

	-- still being typed, or a word it doesn't know: a line on top, the rows below
	r = Rows("cloth |")
	check(r[1].kind == "aggregate" and r[1].noActivate and #r >= 3, "a | with nothing after it: a line says what goes there, the rows stay")
	r = Rows("cloth | sum frob")
	check(r[1].name == L["no number called %s"]:format("frob"), "an unknown field says so: " .. tostring(r[1].name))

	-- Simple mode: Advanced mode's
	ns.db.easyMode = true
	UI:EasyChanged()
	UI.lastScan, UI.lastOverview = nil, nil
	r = Rows("cloth | sum value")
	check(UI.aggregate == nil and r[1] and r[1].name == L["@, >, >>, | and key:value are for Advanced mode"],
		"Simple mode: a | is Advanced mode's: " .. tostring(r[1] and r[1].name))
	ns.db.easyMode = false
	UI:EasyChanged()

	-- ">>> csv" copies the summed-up rows
	r = Rows("@item -bolt | group zone >>> csv")
	check(UI.sendTo and UI.sendTo.copy == "csv" and UI.groupRows and #UI.groupRows == 2, "| group zone >>> csv: the groups to copy")

	local shownText
	local realShow = ns.ShowText
	ns.ShowText = function(_, _, text) shownText = text end
	UI:Activate()
	FlushAll()
	check(shownText and shownText:find("Elwynn Forest", 1, true) and not shownText:find("no zone", 1, true), ">>> csv: the groups copied: "
		.. tostring(shownText))
	shownText = nil
	Rows("cloth | sum value >> text")
	UI:Activate()
	FlushAll()
	check(shownText == ns.Gold.Text(425, true) .. " - " .. L["%s of %s"]:format(L["value"], L["%d results"]:format(2)),
		">> text on the total: its money as plain text: " .. tostring(shownText))
	ns.ShowText = realShow

	-- (release review) every match counted, past 5000; a group whose name has quote marks found again by its Enter
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
		local rows = { { name = "Cookie's Ladle", key = "q", zone = '"Captain" Cove' } }
		for i = 1, 6000 do rows[#rows + 1] = { name = "Nail " .. i, key = "n" .. i } end
		return rows
	end })
	ns:AliasesChanged()
	UI.lastScan, UI.lastOverview = nil, nil
	r = Rows("nail | count")
	check(r[1] and r[1].name == L["%d results"]:format(6000), "6000 matches: 6000 counted: " .. tostring(r[1] and r[1].name))
	r = Rows("ladle | group zone")
	UI:Activate(1)
	FlushAll()
	check(UI.Results()[1] and UI.Results()[1].name == "Cookie's Ladle", "a group named with quote marks: Enter lists its rows: "
		.. UI.edit:GetText())

	-- a keeping step alone: over every match, not the best 100 (review, 0.53.6: 9 of a group's 30)
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
		local out = {}
		for i = 1, 200 do out[#out + 1] = { name = "Bolt " .. i, key = "b" .. i, zone = "Westfall" } end
		for i = 1, 30 do out[#out + 1] = { name = "Zbolt " .. i, key = "z" .. i, zone = '"Cap" Cove' } end
		return out
	end })
	ns:AliasesChanged()
	UI.lastScan, UI.lastOverview = nil, nil
	r = Rows("bolt | group by zone")
	local cap
	for _, e in ipairs(r) do if e.name == '"Cap" Cove' then cap = e end end
	check(cap and cap.detail == L["%d results"]:format(30), "the group: 30 rows: " .. tostring(cap and cap.detail))
	r = Rows('bolt | zone:"Cap Cove"')
	check(#r == 30, "its Enter's step keeps all 30, not the few of them in the best 100: " .. #r)

	C_Item.GetItemInfo = save.gii
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	UI.lastScan, UI.lastOverview = nil, nil
	ns.db.easyMode = save.easy
	UI:EasyChanged()
	UI:Hide(); FlushAll()
end

-- (release review) the prompt's colours: after a "|", a step's field:value in the filters' colour, not a bad filter's;
-- pure fuzzy finding keeps no quote marks
do
	local UI2 = T.UI
	local Theme = T.ns.Theme
	local segs = UI2:SyntaxSegments('@item | quality:"Rare"')
	local last = segs[#segs]
	T.check(last and last[3] == Theme.SYNTAX.filter, "| quality:\"Rare\": a step, in the filters' colour")
	segs = UI2:SyntaxSegments("@item | frob:x")
	T.check(segs[#segs][3] == Theme.SYNTAX.bad, "| frob:x: no such field, said so")
	T.check(UI2.FuzzyPlain('"outlaw saber" in:"elwynn forest" | count') == "outlaw saber ",
		"pure fuzzy finding keeps the words, no quote marks: " .. UI2.FuzzyPlain('"outlaw saber" in:"elwynn forest" | count'))
end

-- (0.53.1, the player: "@loot q:rare | count by dungeon" listed Arathi Basin, Ruins of Ahn'Qiraj... and Leatherworking)
-- a dungeon's or a raid's loot has a dungeon and a boss; a battleground's, a profession's or a faction's has neither
do
	io.write("[aggregate: by dungeon is dungeons and raids only]\n")
	local I = ns.Integrations
	I.NotePlace("T_Agg", "Deadmines", "dungeon", 10)
	I.NotePlace("T_Agg", "AQ20", "raid", 60)
	I.NotePlace("T_Agg", "AB", "other", nil)
	I.NotePlace("T_Agg", "LW", "other", nil)
	local function Row(content, detail) return { kind = "loot", addon = "T_Agg", content = content, detail = detail, name = "x" } end
	local D, B, Z = A.FIELDS.dungeon.text, A.FIELDS.boss.text, A.FIELDS.zone.text
	local dm, aq = Row("Deadmines", "Edwin VanCleef  The Deadmines"), Row("AQ20", "Ossirian  Ruins of Ahn'Qiraj")
	local ab, lw = Row("AB", "Defiler Rewards  Arathi Basin"), Row("LW", "Leather Armor  Leatherworking")
	local old = Row("Unknown", "Some Boss  Old Place") -- (an index from before 0.51.9: no kind)
	check(D(dm) == "The Deadmines" and B(dm) == "Edwin VanCleef", "a dungeon's loot: its dungeon and boss")
	check(A.FIELDS.raid.text(aq) == "Ruins of Ahn'Qiraj" and B(aq) == "Ossirian", "a raid's: the raid and boss")
	check(D(ab) == nil and B(ab) == nil and Z(ab) == nil, "a battleground's: no dungeon, no boss: " .. tostring(D(ab)))
	check(D(lw) == nil and B(lw) == nil and Z(lw) == nil, "a profession's: no dungeon, no boss: " .. tostring(D(lw)))
	-- (0.53.3, the player: "by raid" listed dungeons, "by dungeon" raids) dungeon and raid apart; instance is either
	local R, In = A.FIELDS.raid.text, A.FIELDS.instance.text
	check(D(aq) == nil and R(aq) == "Ruins of Ahn'Qiraj" and In(aq) == "Ruins of Ahn'Qiraj", "a raid's: by raid and by instance, not by dungeon")
	check(R(dm) == nil and In(dm) == "The Deadmines", "a dungeon's: by dungeon and by instance, not by raid")
	check(R(ab) == nil and In(ab) == nil and In(lw) == nil, "a battleground's, a profession's: by none of them")
	check(D(old) == nil and R(old) == nil and In(old) == "Old Place" and B(old) == "Some Boss",
		"a table of unknown kind: an instance, neither a dungeon nor a raid")
	-- (0.53.4, the player: "World Bosses" grouped as a raid) AtlasLoot files them under its raids: bosses, no instance
	I.NotePlace("T_Agg", "WorldBosses", "raid", 60)
	local az = Row("WorldBosses", "Azuregos  World Bosses")
	check(R(az) == nil and In(az) == nil and Z(az) == nil and B(az) == "Azuregos",
		"a world boss's loot: by boss, not by raid, instance or zone: " .. tostring(R(az)))
	check(A.FIELDS.raid.text(aq) == "Ruins of Ahn'Qiraj", "(the raids still are)")
	check(A.FieldOf("raid") == "raid" and A.FieldOf("raids") == "raid" and A.FieldOf("dungeons") == "dungeon"
		and A.FieldOf("instances") == "instance" and A.FieldOf("instance") == "instance", "by raids, by dungeons, by instances")
end
