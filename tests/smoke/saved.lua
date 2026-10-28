-- (0.67.7, a player's report: Terminal.lua in SavedVariables was large) the settings in TerminalDB, everything recorded
-- in TerminalCacheDB, an old save moved over, the big tables packed at logout, and .saved to see and choose it.
local T = ...
local ns, check = T.ns, T.check
local SV = ns.Saved

local function Same(a, b, path)
	path = path or "value"
	if type(a) ~= type(b) then return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b) end
	if type(a) ~= "table" then
		if a == b then return true end
		return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b)
	end
	for k, v in pairs(a) do
		local ok, why = Same(v, b[k], path .. "." .. tostring(k))
		if not ok then return false, why end
	end
	for k in pairs(b) do if a[k] == nil then return false, path .. "." .. tostring(k) .. ": missing" end end
	return true
end

local function Run(args) return ns.commands.saved.run(args) end

local was = { db = ns.db, tdb = _G.TerminalDB, cache = _G.TerminalCacheDB }
local ok, err = pcall(function()
	io.write("[saved: packing a list keeps every value]\n")
	do
		local list = {
			{ t = 1700000000, id = 19019, link = "|cffff8000|Hitem:19019|h[Thunderfury]|h|r", who = "Plamen", n = 2,
				zone = "Molten Core", src = "loot+roll" },
			{ t = 1700000001, id = 19019, link = "|cffff8000|Hitem:19019|h[Thunderfury]|h|r", who = "Plamen", n = nil,
				zone = "Molten Core", src = "loot" },
			{ t = 1.5, id = -3, link = "#not a number", who = "'quoted", zone = "", src = "=", flag = true, off = false },
			{ t = 0.1 + 0.2, id = 2 ^ 40, link = "!1", who = "plain", big = 12345678901234 },
		}
		local s = SV.Pack(list)
		check(type(s) == "string", "a list of flat records packs")
		local back = SV.Unpack(s)
		local same, why = Same(list, back)
		check(same, "and reads back the same: " .. tostring(why))
		check(not s:find("Thunderfury", s:find("Thunderfury", 1, true) + 1, true),
			"a value the same as the record above's is written once")
		local arrays = { { "AtlasLootClassic_DungeonsAndRaids", "Deadmines", 1, "The Deadmines", "Rhahk'Zor", "872.1.0 5187.1.0", "dungeon", 18 },
			{ "AtlasLootClassic_DungeonsAndRaids", "Deadmines", 2, "The Deadmines", "Sneed", "", "dungeon", 18 } }
		same, why = Same(arrays, SV.Unpack(SV.Pack(arrays)))
		check(same, "arrays too (the loot index's groups): " .. tostring(why))
		check(SV.Pack({ { name = "a\tb" } }) == nil, "a text with a tab can't be packed: kept as it was")
		check(SV.Pack({ { inner = {} } }) == nil, "nor a record holding a table")
		check(#SV.Unpack("") == 0 and #SV.Unpack(nil) == 0, "nothing reads back as an empty list")
	end

	io.write("[saved: an old single-file save is moved into the cache file]\n")
	do
		_G.TerminalDB = {
			theme = { preset = "amber" }, history = { "@loot thunderfury" }, freq = { ["item:6948"] = 3 },
			lootLog = { { t = 5, id = 6948, link = "x", who = "me" } },
			itemStore = { build = "1", v = 4, quality = { new = { [6948] = 1 }, old = {}, n = 1 } },
			lootCache = { key = "k", groups = {} }, mailSent = { a = 1 },
		}
		_G.TerminalCacheDB = nil
		ns.db = SV.Load()
		local raw = _G.TerminalDB
		check(rawget(raw, "lootLog") == nil and rawget(raw, "itemStore") == nil and rawget(raw, "lootCache") == nil
			and rawget(raw, "mailSent") == nil, "the old copies are gone from Terminal.lua")
		check(rawget(raw, "theme") and rawget(raw, "history") and rawget(raw, "freq"), "the settings stay in Terminal.lua")
		local cache = _G.TerminalCacheDB
		check(type(cache) == "table" and cache.lootLog and cache.lootLog[1].id == 6948 and cache.mailSent.a == 1,
			"what was recorded is in TerminalCache.lua")
		check(ns.db.lootLog == cache.lootLog, "ns.db still reads it (passed through)")
		ns.db.combatLog = { { what = "died" } }
		check(rawget(raw, "combatLog") == nil and cache.combatLog[1].what == "died", "and writes it into the cache file")
		ns.db.zen = true
		check(rawget(raw, "zen") == true and cache.zen == nil, "a setting written goes into Terminal.lua")
		ns.db.lootLog = nil
		check(cache.lootLog == nil, "a cache key set to nil is cleared in the cache file")
	end

	io.write("[saved: a newer cache file wins over a leftover old copy]\n")
	do
		_G.TerminalDB = { lootLog = { { id = 1 } } }
		_G.TerminalCacheDB = { lootLog = { { id = 2 } } }
		ns.db = SV.Load()
		check(ns.db.lootLog[1].id == 2 and rawget(_G.TerminalDB, "lootLog") == nil, "the cache file's kept, the old copy dropped")
	end

	io.write("[saved: written packed at logout, read back the same]\n")
	do
		local quality = {}
		for i = 1, 300 do quality[1000 + i * 7] = i % 6 end
		local facts = { [1007] = "INVTYPE_HEAD;16;22;2;str=7", [1014] = "INVTYPE_FEET;8;12;1;" }
		local loot = {}
		for i = 1, 20 do loot[i] = { t = 100 - i, id = 6948 + i, link = "|Hitem:" .. (6948 + i) .. "|h", who = "me", zone = "Elwynn Forest" } end
		local okB, _, b = pcall(_G.GetBuildInfo)
		local build = okB and tostring(b) or "?"
		local data = {
			itemStore = { build = build, v = ns.ItemStore.VERSION, quality = { new = quality, old = { [5] = 2 }, n = 300 }, facts = { new = facts, old = {}, n = 2 } },
			lootCache = { key = "v3 x", groups = { { "Mod", "Deadmines", 1, "The Deadmines", "Sneed", "872.1.0", "dungeon", 18 } } },
			talentCache = { key = "2:1", classes = { MAGE = { { 1, "Arcane Focus", 11222, "Arcane", 1, 5, 135894 } } }, names = { MAGE = "Mage" } },
			talentDesc = { key = "2:1", d = { [11222] = "reduces the chance...", [11223] = "" } },
			lootLog = loot,
			combatLog = { { t = 1, what = "crit", amount = 1234, by = "Hogger" } },
			recipes = { ["Player-1"] = { a = 1 } },
		}
		local copy = {}
		for k, v in pairs(data) do copy[k] = v end
		_G.TerminalDB = { savedKeep = { items = "large" } }
		_G.TerminalCacheDB = copy
		ns.db = SV.Load()
		local before = #SV.Pack(loot)
		SV.Save()
		local c = _G.TerminalCacheDB
		check(c.itemStore.packed and type(c.itemStore.quality.new) == "string" and type(c.lootLog.packed) == "string"
			and type(c.lootCache.groups) == "string" and type(c.talentCache.classes.MAGE) == "string"
			and type(c.talentDesc.d) == "string", "item details, the loot index, talents and logs are written packed")
		check(#c.itemStore.quality.new < 300 * 5, "qualities take a few characters an item: " .. #c.itemStore.quality.new)
		check(c.recipes == data.recipes, "a record with no packing is written as it is")
		check(SV.Size("lootLog") < before + 40, "the size .saved shows is the packed one")
		-- the next session
		ns.db = SV.Load()
		for k, v in pairs(data) do
			local same, why = Same(v, _G.TerminalCacheDB[k], k)
			check(same, "read back the same at the next load: " .. tostring(why))
		end
		ns.ItemStore.NewSession()
		check(ns.ItemStore.Get("quality", 1007) == 1 % 6 and ns.ItemStore.Get("facts", 1014) == facts[1014],
			"the item store reads them again")
	end

	io.write("[saved: something packed can't be changed by a late write]\n")
	do
		_G.TerminalDB = {}
		_G.TerminalCacheDB = { itemStore = { build = "1", v = 4, quality = { new = { [1] = 3 }, old = {}, n = 1 } } }
		ns.db = SV.Load()
		ns.ItemStore.NewSession()
		SV.Save()
		local packed = _G.TerminalCacheDB.itemStore
		ns.ItemStore.Put("quality", 2, 4) -- (an item answered after the save: nothing to keep it in)
		check(_G.TerminalCacheDB.itemStore == packed and type(packed.quality.new) == "string",
			"the packed item store is left as written")
	end

	io.write("[saved: a broken packed table is dropped, not an error]\n")
	do
		_G.TerminalDB = {}
		_G.TerminalCacheDB = { talentCache = { packed = 1, classes = 5 }, lootLog = { packed = 7 } }
		ns.db = SV.Load()
		check(type(ns.db.lootLog) == "table" and #ns.db.lootLog == 0, "an unreadable log comes back empty")
	end

	io.write("[saved: .saved keep and clear]\n")
	do
		local loot, combat = {}, {}
		for i = 1, 400 do loot[i] = { id = i, t = i } end
		for i = 1, 250 do combat[i] = { what = "crit", t = i } end
		_G.TerminalDB = {}
		_G.TerminalCacheDB = { lootLog = loot, combatLog = combat, lootCache = { key = "k", groups = {} },
			itemStore = { build = "1", v = 4, quality = { new = {}, old = {}, n = 0 } }, mailSent = { x = 1 } }
		ns.db = SV.Load()
		check(SV.Level("loot") == "normal" and SV.Limit("loot") == 250, "the loot log keeps 250 drops by default")
		SV.Save()
		ns.db = SV.Load()
		check(#ns.db.lootLog == 250 and ns.db.lootLog[1].id == 1 and #ns.db.combatLog == 150,
			"at logout the logs are cut to what's kept, newest kept")
		local out = table.concat(Run("keep loot small"), "\n")
		check(#ns.db.lootLog == 100 and out:find("100", 1, true), "keep loot small: cut to 100 now: " .. out)
		check(rawget(_G.TerminalDB, "savedKeep").loot == "small", "the pick is a setting, in Terminal.lua")
		Run("keep loot normal")
		check(rawget(_G.TerminalDB, "savedKeep") == nil, "the default picked again: nothing kept for it")
		out = table.concat(Run("keep loot huge"), "\n")
		check(out:find("small", 1, true) and out:find("large", 1, true), "a level it hasn't: the ones it has: " .. out)
		Run("keep atlasloot off")
		check(ns.db.lootCache == nil, "a cache turned off is cleared")
		Run("keep all minimal")
		check(SV.Level("items") == "off" and SV.Level("loot") == "small" and ns.ItemStore.CAP.quality > 0,
			"keep all minimal: item details off (still remembered this session), the logs small")
		Run("keep all normal")
		check(SV.Level("items") == "normal" and SV.Level("atlasloot") == "on" and ns.ItemStore.CAP.quality == 4000,
			"keep all normal: the defaults")
		out = table.concat(Run(""), "\n")
		check(out:find("Terminal.lua", 1, true) and out:find("TerminalCache.lua", 1, true) and out:find("loot", 1, true),
			".saved lists both files and each part: " .. out)
		Run("clear mail")
		check(ns.db.mailSent == nil and ns.db.lootLog, "clear mail: only the mail")
		Run("clear all")
		check(ns.db.lootLog == nil and ns.db.combatLog == nil, "clear all: the whole cache file")
		local rows = ns.commands.saved.complete("keep ")
		local has = {}
		for _, r in ipairs(rows) do has[r[1]] = true end
		check(has["keep loot small"] and has["keep all minimal"] and has["keep atlasloot off"], "Tab offers the levels")
	end
end)
_G.TerminalDB, _G.TerminalCacheDB = was.tdb, was.cache
ns.db = SV.Load()
ns.ItemStore.NewSession()
check(ns.db == was.db, "the run's own saved variables back")
check(ok, "saved: " .. tostring(err))

io.write("[saved: the console's records in the cache file, its settings in Terminal.lua]\n")
do
	local SH = ns.Shell
	local raw = _G.TerminalDB
	local had, hadData = rawget(raw, "console"), ns.db.consoleData
	rawset(raw, "console", { history = { "ls" }, session = { layout = "wide" }, z = { ["/bags"] = { r = 1, t = 0 } }, theme = "dracula" })
	ns.db.consoleData = nil
	local d = SH.Data()
	local c = rawget(raw, "console")
	check(d.history[1] == "ls" and d.session.layout == "wide" and d.z["/bags"] and c.history == nil and c.session == nil
		and c.z == nil, "records kept in db.console before are moved to the cache file")
	check(c.theme == "dracula" and rawget(raw, "consoleData") == nil and _G.TerminalCacheDB.consoleData == d,
		"the theme stays a setting; the records are in TerminalCache.lua")
	rawset(raw, "console", had)
	ns.db.consoleData = hadData
end
