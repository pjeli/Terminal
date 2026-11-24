-- (1.8.1, the player: "find bonuses for biomes as well as against creature types; filter-able and group-able") an item's
-- bonus by area type or creature, read from its tooltip: bonus:haunted, bonus:undead, is:bonus, | group by bonus.
local T = ...
local ns, check, FlushAll = T.ns, T.check, T.FlushAll
local F, BN, A, E = ns.Filters, ns.Bonus, ns.Aggregate, ns.Easy

io.write("[bonus: area types and creatures from the tooltip]\n")

local function Read(line)
	local areas, foes = {}, {}
	BN.ReadLine(line, areas, foes)
	local out = {}
	for _, a in ipairs(BN.AREAS) do if areas[a.key] then out[#out + 1] = a.key end end
	local fk = {}
	for k in pairs(foes) do fk[#fk + 1] = k end
	table.sort(fk)
	for _, k in ipairs(fk) do out[#out + 1] = "vs " .. k end
	return table.concat(out, ",")
end

do -- the wordings
	local CASES = {
		{ "Equip: +14 Attack Power. This effect is tripled in Forest and Grassland areas.", "forest" },
		{ "Use: Restores 63 Mana every 1 sec for 10 sec. This effect is doubled in Wasteland and Haunted areas.", "wasteland,haunted" },
		{ "Healing is doubled in Strongholds and Cities.", "stronghold" },
		{ "This effect is doubled in swamps while swimming.", "swamp" },
		{ "Increases damage and healing done by magical spells and effects by up to 15. This effect is doubled in Marsh and Swamp areas.", "swamp" },
		{ "Equip: Increases Spirit by 16 in Cavernous or Underground areas.", "cavern" },
		{ "Damage is doubled in Forest areas and Swamp areas.", "forest,swamp" },
		{ "|cff00ff00Equip: Restores 9 Mana per 5 sec in Haunted areas.|r", "haunted" },
		{ "Can only be used in Stormwind City.", "" },
		{ "In Haunted areas, your spells cost 5% less mana.", "haunted" },
		{ "Forged in the city of Ironforge.", "" },
		{ "\"Found deep in the swamps.\"", "" },
		{ "Equip: +45 Attack Power when fighting Undead.", "vs undead" },
		{ "Equip: Increases damage done to Demons by magical spells and effects by up to 30.", "vs demon" },
		{ "(3) Set: Increases your damage against undead by 2%.", "vs undead" },
		{ "Equip: +18 Attack Power against Beasts.", "vs beast" },
		{ "Use: An extended effect against the Naga.", "vs naga" },
		{ "Equip: Increases your damage against Trolls by 3%.", "vs troll" },
		{ "Equip: +20 Attack Power against Harpies in Desert areas.", "desert,vs harpy" },
		{ "Equip: Increases your armor against ranged attacks.", "" },
		{ "Reduces the damage done to you by 5.", "" },
		{ "Increases your resistance against Fire by 10.", "" },
	}
	for _, c in ipairs(CASES) do
		local got = Read(c[1])
		check(got == c[2], "bonus read of \"" .. c[1] .. "\": " .. got .. " (wanted " .. c[2] .. ")")
	end
end

-- items: their tooltips, class and whether the client has them
local save = { tti = _G.C_TooltipInfo, inst = C_Item.GetItemInfoInstant, cached = C_Item.IsItemDataCachedByID,
	req = C_Item.RequestLoadItemDataByID, loading = F.loading }
local TIPS = {
	[501] = { "Rune of the Dead", "Equip: Restores 9 Mana per 5 sec in Haunted areas." },
	[502] = { "Seal of Dawn", "Equip: +45 Attack Power when fighting Undead." },
	[503] = { "Graveyard Charm", "Use: Doubled in Wasteland and Haunted areas.", "(3) Set: Increases your damage against undead by 2%." },
	[504] = { "Troll Bane", "Equip: Increases your damage against Trolls by 3%." },
	[505] = { "Plain Ring", "Equip: +5 Stamina." },
	[506] = { "Linen Cloth", "This effect is doubled in Haunted areas." }, -- (trade goods: never read)
	[507] = { "Coming Soon", "Equip: in Haunted areas." },
}
local CLASS = { [501] = 4, [502] = 4, [503] = 4, [504] = 2, [505] = 4, [506] = 7, [507] = 4 }
local reads, uncached, asked = 0, {}, 0
_G.C_TooltipInfo = { GetItemByID = function(id)
	reads = reads + 1
	local t = TIPS[id]
	if not t then return nil end
	local lines = {}
	for i, s in ipairs(t) do lines[i] = { leftText = s } end
	return { lines = lines }
end }
C_Item.GetItemInfoInstant = function(id) return id, "Armor", "Misc", "INVTYPE_TRINKET", 0, CLASS[id] or 4, 0 end
C_Item.IsItemDataCachedByID = function(id) return not uncached[id] end
C_Item.RequestLoadItemDataByID = function() asked = asked + 1 end
BN.ForgetForTests()
F.ResetAsks()

local function Row(id) return { kind = "items", name = TIPS[id][1], itemID = id } end
local rows = {}
for _, id in ipairs({ 501, 502, 503, 504, 505, 506 }) do rows[#rows + 1] = Row(id) end
local function Names(word)
	local f = F.Parse(word)
	if not f then return "(no filter)" end
	local out = {}
	for _, e in ipairs(rows) do if F.Pass(e, { f }) then out[#out + 1] = e.itemID end end
	return table.concat(out, ",")
end

do -- the filter
	check(Names("bonus:haunted") == "501,503", "bonus:haunted: " .. Names("bonus:haunted"))
	check(Names("bonus:undead") == "502,503", "bonus:undead (a set bonus too): " .. Names("bonus:undead"))
	check(Names("bonus:troll") == "504", "bonus:troll finds \"against Trolls\": " .. Names("bonus:troll"))
	check(Names("bonus:trolls") == "504", "bonus:trolls (plural typed): " .. Names("bonus:trolls"))
	check(Names("bonus:und") == "502,503", "bonus:und (a start): " .. Names("bonus:und"))
	check(Names("bonus:area") == "501,503", "bonus:area: any area type: " .. Names("bonus:area"))
	check(Names("bonus:creature") == "502,503,504", "bonus:creature: any creature: " .. Names("bonus:creature"))
	check(Names("bonus:waste") == "503", "bonus:waste (an area type's start): " .. Names("bonus:waste"))
	check(Names("is:bonus") == "501,502,503,504", "is:bonus: either: " .. Names("is:bonus"))
	check(Names("-is:bonus") == "505,506", "-is:bonus: " .. Names("-is:bonus"))
	check(Names("bonus:haunted|troll") == "501,503,504", "bonus:haunted|troll: " .. Names("bonus:haunted|troll"))
	local before = reads
	Names("bonus:haunted")
	check(reads == before, "each tooltip read once: " .. (reads - before) .. " more")
	-- (trade goods and the like: their tooltip never read)
	BN.ForgetForTests(); reads = 0
	BN.Of(506)
	check(reads == 0 and BN.Of(506) == false, "a trade good's tooltip isn't read: " .. reads)
	-- (1.8.5, the player: "why can I not look at @loot that has bonuses against trolls / biome?") an item the client
	-- hasn't got yet: queued and asked of the server in the background, read once it's in
	uncached[507] = true; F.loading, F.bonusLoading = false, nil
	check(BN.Of(507) == nil and F.bonusLoading == true and not F.loading and BN.Left() == 1,
		"an item still coming: queued (searched again as they come in, not every 1.1 s): " .. BN.Left())
	FlushAll()
	check(asked == 1 and BN.Left() == 1, "...asked of the server in the background: " .. asked)
	uncached[507] = nil
	T.Fire("ITEM_DATA_LOAD_RESULT", 507, true)
	check(BN.Of(507) and BN.Of(507)[1].key == "haunted" and BN.Left() == 0, "once it's in: read, none left: " .. BN.Left())
	FlushAll()
	BN.ForgetForTests()
end

do -- (1.8.5) thousands of them (AtlasLoot's): a batch at a time, the search shown run again as they come in, the
	-- footer saying how many are left; kept for the next session of this client build
	BN.ForgetForTests(); F.ResetAsks()
	asked = 0
	for id = 7000, 7099 do uncached[id] = true; TIPS[id] = { "Far Charm " .. id, "Equip: +5 Attack Power against Trolls." } end
	local UI = ns.UI
	local redone, shows = 0, nil
	local redoWas, shownWas, editWas = UI.QuietRedo, UI.IsShown, UI.edit
	UI.QuietRedo = function(_, sh) redone = redone + 1; shows = sh end
	UI.IsShown = function() return true end
	UI.edit = { GetText = function() return "@loot bonus:troll" end }
	local f = F.Parse("bonus:troll")
	local passed = 0
	for id = 7000, 7099 do if F.Pass({ itemID = id }, { f }) then passed = passed + 1 end end
	check(passed == 0 and BN.Left() == 100 and asked == 0, "a hundred not loaded: none yet, all queued, none asked in the search: " .. asked)
	check(tostring(BN.Note()):find("100", 1, true), "the footer says how many are left: " .. tostring(BN.Note()))
	T.Flush()
	check(asked == BN.BATCH, "asked a batch at a time: " .. asked)
	FlushAll()
	check(asked == 100, "...then the rest: " .. asked)
	for id = 7000, 7099 do uncached[id] = nil; T.Fire("ITEM_DATA_LOAD_RESULT", id, true) end
	FlushAll()
	passed = 0
	for id = 7000, 7099 do if F.Pass({ itemID = id }, { f }) then passed = passed + 1 end end
	check(passed == 100 and BN.Left() == 0 and BN.Note() == nil, "all in: every one found, the footer's note gone: " .. passed)
	check(redone >= 1 and shows == true, "the search shown was run again as they came in, what it finds put up (no F5): " .. redone)
	-- a line typed since: not run again for it
	redone = 0
	UI.edit = { GetText = function() return "something else" end }
	uncached[7100] = true; TIPS[7100] = TIPS[7000]
	BN.Of(7100); FlushAll(); uncached[7100] = nil; T.Fire("ITEM_DATA_LOAD_RESULT", 7100, true); FlushAll()
	check(redone == 0, "another line typed meanwhile: not run again: " .. redone)
	-- (1.8.8, review) an item the server never answers: let go after a while, not asked again, the note gone
	local clockWas, t = _G.GetTime, 5000
	_G.GetTime = function() return t end
	UI.edit = { GetText = function() return "@loot bonus:troll" end }
	BN.wantedText = "@loot bonus:troll"
	uncached[7200] = true; TIPS[7200] = TIPS[7000]
	asked = 0
	BN.Of(7200); T.Flush()
	check(asked == 1 and BN.Left() == 1, "asked once: " .. asked)
	t = t + BN.GIVE_UP + 1
	FlushAll()
	check(BN.Left() == 0 and BN.Note() == nil, "never answered: let go, the note gone: " .. BN.Left())
	check(BN.Of(7200) == nil and BN.Left() == 0, "...and not queued again this session")
	FlushAll()
	check(asked == 1, "...nor asked again: " .. asked)
	_G.GetTime = clockWas
	uncached[7200] = nil
	-- kept for the next session: read again from what was kept, not from the tooltips
	local dbWas = ns.db.bonusIndex
	BN.SaveKept()
	local x = ns.db.bonusIndex
	check(type(x) == "table" and x.build == BN.Build() and x.items:find("7000=f:troll:Trolls", 1, true), "kept by build: "
		.. tostring(x and x.items and x.items:sub(1, 60)))
	BN.ForgetForTests()
	reads = 0
	check(F.Pass({ itemID = 7042 }, { F.Parse("bonus:troll") }) and reads == 0, "the next session: from what was kept, no tooltip read: " .. reads)
	check(BN.Labels({ itemID = 7042 })[1] == "Against Trolls", "its label kept too: " .. tostring(BN.Labels({ itemID = 7042 })[1]))
	-- another client build: read again
	ns.db.bonusIndex.build = "0.0.0.1"
	BN.ForgetForTests()
	BN.Of(7042)
	check(reads == 1, "a new client build: read again: " .. reads)
	-- (1.8.10, review) written at logout only when something new was read: the saved copy left as it is otherwise
	BN.ForgetForTests()
	local sentinel = { build = BN.Build(), items = "7042=f:troll:Trolls" }
	ns.db.bonusIndex = sentinel
	BN.Of(7042) -- (from the saved copy: nothing new)
	BN.SaveKept()
	check(ns.db.bonusIndex == sentinel, "nothing new read: not written again at logout")
	-- the bar's Group menu: only what's kept is said, no tooltip read for a row not read yet
	reads = 0
	check(BN.KnownLabels({ itemID = 7042 }) == "Against Trolls" and BN.KnownLabels({ itemID = 7001 }) == nil and reads == 0,
		"what's kept only, nothing read: " .. reads)
	check(A.FIELDS.bonus.peek ~= nil, "Group by bonus's menu check reads what's kept (peek)")
	-- (1.8.8, review) .saved clear bonuses: what was read this session goes too, not written back at logout
	ns:FindCommand("saved").run("clear bonuses")
	BN.SaveKept()
	check(ns.db.bonusIndex == nil, ".saved clear bonuses sticks: " .. tostring(ns.db.bonusIndex))
	-- recipes and materials (skipped by their class): not written to the saved file
	BN.ForgetForTests()
	BN.Of(506); BN.Of(7042)
	BN.SaveKept()
	check(ns.db.bonusIndex and not ns.db.bonusIndex.items:find("506=", 1, true) and ns.db.bonusIndex.items:find("7042=", 1, true),
		"a trade good skipped by its class isn't saved: " .. tostring(ns.db.bonusIndex and ns.db.bonusIndex.items))
	ns.db.bonusIndex = dbWas
	for id = 7000, 7100 do TIPS[id] = nil end
	UI.QuietRedo, UI.IsShown, UI.edit = redoWas, shownWas, editWas
	-- (1.8.8, review) a new search starts with no line wanted (a bonus: filter, or an item queued, sets it again)
	BN.wantedText = "@loot bonus:troll"
	UI:Search("@items linen")
	check(BN.wantedText == nil and not F.bonusLoading, "a new search: no line wanted yet: " .. tostring(BN.wantedText))
	BN.ForgetForTests()
end

do -- (1.8.8, review) on screen, while tooltips load: no rows without the bonus as "the closest", and what comes in
	-- put up without F5
	BN.ForgetForTests()
	local UI = ns.UI
	local lists = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	for id = 7300, 7319 do uncached[id] = true; TIPS[id] = { "Troll Charm " .. id, "Equip: +5 Attack Power against Trolls." }; CLASS[id] = 4 end
	for id = 7320, 7339 do TIPS[id] = { "Plain Charm " .. id, "Equip: +5 Stamina." }; CLASS[id] = 4 end
	ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = function()
		local list = {}
		for id = 7300, 7339 do list[#list + 1] = { name = TIPS[id][1], itemID = id, key = "l" .. id } end
		return list
	end })
	ns.db.easyMode = true; UI:EasyChanged()
	UI.lastScan = nil
	UI:Open("charm against trolls"); T.Flush()
	local function Ids()
		local t = {}
		for _, e in ipairs(UI.Results()) do if e.itemID then t[#t + 1] = e.itemID end end
		return t
	end
	check(#Ids() == 0, "nothing read yet: no plain charms listed as the closest: " .. #Ids())
	for id = 7300, 7319 do uncached[id] = nil; T.Fire("ITEM_DATA_LOAD_RESULT", id, true) end
	FlushAll()
	check(#Ids() == 20 and not UI.held, "they came in: put up, not held for F5: " .. #Ids())
	UI:Hide(); FlushAll()
	ns.db.easyMode = lists.easy; UI:EasyChanged()
	ns.providers, ns.providerOrder = lists.providers, lists.order
	ns:AliasesChanged()
	UI.lastScan = nil
	for id = 7300, 7339 do TIPS[id], CLASS[id] = nil, nil end
	BN.ForgetForTests()
end

do -- the group
	local spec = A.Parse({ "group by bonus" }, "@items")
	check(not spec.bad, "group by bonus reads: " .. tostring(spec.bad))
	local out = A.Apply(spec, rows, spec.base)
	local got = {}
	for _, r in ipairs(out) do got[#got + 1] = tostring(r.name) .. "=" .. tostring(r.groupN) end
	local said = table.concat(got, " | ")
	check(said == "Against Undead=2 | Haunted=2 | Against Trolls=1 | Wasteland=1",
		"grouped by bonus, an item with two in both: " .. said)
	local haunted
	for _, r in ipairs(out) do if r.name == "Haunted" then haunted = r end end
	check(haunted and haunted.drillTo and haunted.drillTo:find("bonus:haunted", 1, true), "Enter on Haunted: bonus:haunted: " .. tostring(haunted and haunted.drillTo))
	local undead
	for _, r in ipairs(out) do if r.name == "Against Undead" then undead = r end end
	check(undead and undead.drillTo and undead.drillTo:find("bonus:undead", 1, true), "Enter on Against Undead: bonus:undead: " .. tostring(undead and undead.drillTo))
	-- a keeping step by it: any of the row's bonuses
	spec = A.Parse({ "bonus:haunted" }, "@items")
	out = A.Apply(spec, rows, spec.base)
	local ids = {}
	for _, e in ipairs(out) do ids[#ids + 1] = e.itemID end
	check(table.concat(ids, ",") == "501,503", "| bonus:haunted keeps either: " .. table.concat(ids, ","))
	check(A.FieldOf("biome") == "bonus" and A.FieldOf("bonuses") == "bonus", "group by biome: the same field")
	local inMenu = false
	for _, id in ipairs(ns.Bar.GROUPS) do if id == "bonus" then inMenu = true end end
	check(inMenu, "the bar's Group menu offers bonus")
	BN.ForgetForTests()
end

do -- Simple mode's words, and how the filter is said
	check(E.WORDS["against undead"] == "bonus:undead", "against undead: " .. tostring(E.WORDS["against undead"]))
	check(E.WORDS["vs beasts"] == "bonus:beast", "vs beasts: " .. tostring(E.WORDS["vs beasts"]))
	check(E.WORDS["swamp bonus"] == "bonus:swamp", "swamp bonus: " .. tostring(E.WORDS["swamp bonus"]))
	check(E.WORDS["city areas"] == "bonus:stronghold", "city areas: " .. tostring(E.WORDS["city areas"]))
	-- (1.8.11, review) an area type's word alone isn't one: names have them ("Volcanic Leggings", "The Haunted Isle")
	check(rawget(E.WORDS, "haunted") == nil and rawget(E.WORDS, "volcanic") == nil and E.WORDS["haunted gear"] == "bonus:haunted"
		and E.WORDS["biome"] == "bonus:area", "haunted alone a word, haunted gear the bonus, biome alone too")
	check(rawget(E.WORDS, "swamp") == nil and rawget(E.WORDS, "forest") == nil, "a zone's word alone stays a word (Swamp of Sorrows, Elwynn Forest)")
	local said = E.SayFilter("bonus:haunted") or ""
	check(said:find("Haunted", 1, true), "bonus:haunted said: " .. said)
	said = E.SayFilter("bonus:undead") or ""
	check(said:find("undead", 1, true), "bonus:undead said: " .. said)
	check(F.IsKey("bonus") and F.IsKey("biome"), "bonus: and biome: are filter keys")
	-- (1.8.8, review) said as the filter reads it: an area type's start is that area type
	said = E.SayFilter("bonus:mount") or ""
	check(said:find("Mountainous", 1, true), "bonus:mount said as Mountainous: " .. said)
	local specs = BN.Take({ "rewards", "against", "the", "naga" })
	check(specs[1] == "bonus:naga", "\"against the naga\" in plain words: " .. tostring(specs[1]))
	local helped = false
	for _, h in ipairs(F.HELP) do if h[1] == "bonus:haunted" then helped = true end end
	check(helped, ".filters lists bonus:")
end

_G.C_TooltipInfo, C_Item.GetItemInfoInstant, C_Item.IsItemDataCachedByID = save.tti, save.inst, save.cached
C_Item.RequestLoadItemDataByID, F.loading = save.req, save.loading
BN.ForgetForTests()
F.ResetAsks()
