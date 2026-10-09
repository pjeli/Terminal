-- The providers/core clean-up (0.44.8 refactor, package C): what moved keeps its contract (ns.Bags in Bags.lua,
-- ns.Guarded in Debug.lua), and the speed-ups give the same results.
local T = ...
local ns, UI, check, Obj = T.ns, T.UI, T.check, T.Obj

io.write("[providers parts: guarded calls]\n")
do
	local D = ns.Debug
	check(type(ns.Guarded) == "function" and ns.Professions.Guarded == ns.Guarded, "ns.Guarded (Debug.lua) is Professions.Guarded too")
	local save = { blocked = ns.db.blockedCalls, count = D.count, events = #D.events, print = ns.Print }
	ns.db.blockedCalls = {}
	ns.Print = function() end
	local calls = 0
	check(ns.Guarded("PartsFine", function() calls = calls + 1 end) == true and calls == 1, "a call that goes through: true")
	local blocked = ns.Guarded("PartsBlocked", function()
		calls = calls + 1
		D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", "Terminal", "PartsBlocked()")
	end)
	check(blocked == false and calls == 2 and ns.db.blockedCalls.PartsBlocked == true, "blocked by the game: false, and remembered")
	check(ns.Professions.Guarded("PartsBlocked", function() calls = calls + 1 end) == false and calls == 2,
		"never tried again, asked through either name")
	check(ns.Guarded("PartsNoFunction", nil) == false, "nothing to call: false")
	for i = #D.events, save.events + 1, -1 do D.events[i] = nil end
	ns.db.blockedCalls, D.count, ns.Print = save.blocked, save.count, save.print
end

io.write("[providers parts: shared helpers]\n")
do
	check(ns.Never() == false and ns.ChatBoxNeverOpen == ns.Never, "ns.Never (Core.lua) is also the chat box spec's isOpen")
	local p = ns.providers.lootlog
	local saveLog = ns.db.lootLog
	ns.db.lootLog = { { link = "|cff1eff00|Hitem:2589::::::::|h[Partsy Cloth]|h|r", id = 2589, who = "Bob", t = 1, src = "loot" } }
	p._dirty = true
	local row = ns:GetEntries(p)[1]
	check(row and row.secondaryIsOpen == ns.Never, "the loot log's rows share ns.Never")
	ns.db.lootLog = saveLog
	p._dirty = true
	-- the profession window's recipe list scrolled through ns.ScrollBoxTo: its nodes' data, or the data's recipeInfo
	local asked = {}
	local function window(nodes)
		return { CraftingPage = { RecipeList = { ScrollBox = { ScrollToElementDataByPredicate = function(_, pred)
			for _, n in ipairs(nodes) do if pred(n) then asked[#asked + 1] = n end end
		end } } } }
	end
	local a = { GetData = function() return { recipeInfo = { recipeID = 11 } } end }
	local b = { GetData = function() return { recipeID = 12 } end }
	local c = { GetData = function() return { recipeInfo = { recipeID = 13 } } end }
	local Scroll = ns.Professions.ScrollToRecipe
	check(Scroll(window({ a, b, c }), 12) == true and asked[1] == b and #asked == 1, "the recipe list: scrolled to the node whose data is the recipe")
	asked = {}
	check(Scroll(window({ a, b, c }), 13) == true and asked[1] == c and #asked == 1, "or whose data's recipeInfo is")
	check(Scroll({}, 11) == false and Scroll({ CraftingPage = { RecipeList = {} } }, 11) == false, "no list: false")
	local bad = { CraftingPage = { RecipeList = { ScrollBox = { ScrollToElementDataByPredicate = function() error("x") end } } } }
	check(Scroll(bad, 11) == false, "a list that errors: false")
end

io.write("[providers parts: frame names]\n")
do
	local named, unnamed, failing, numbered = Obj("Frame"), Obj("Frame"), Obj("Frame"), Obj("Frame")
	named.GetName = function() return "PartsFrame" end
	unnamed.GetName = function() return nil end
	failing.GetName = function() error("forbidden") end
	numbered.GetName = function() return 7 end
	local FN = ns.FrameName
	check(FN(named) == "PartsFrame" and FN(unnamed) == nil and FN(failing) == nil and FN(numbered) == nil,
		"ns.FrameName: a string name, else nil")
	check(FN(nil) == nil and FN({}) == nil and FN(3) == nil and FN("x") == nil and FN(true) == nil, "ns.FrameName: never an error")
	-- (a walk over UIParent's children asks every child: no closure made per call, so nothing is left to collect)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 20000 do FN(named) end
	local grew = collectgarbage("count") - before
	collectgarbage("restart")
	check(grew < 64, ("ns.FrameName makes nothing per call: %.0f KB over 20000 calls"):format(grew))
end

io.write("[providers parts: addons]\n")
do
	local base, saveName = _G.C_AddOns, ns.CharacterName
	local me = saveName()
	local asked, states = 0, {}
	ns.CharacterName = function() asked = asked + 1; return saveName() end
	_G.C_AddOns = setmetatable({
		GetNumAddOns = function() return 3 end,
		GetAddOnInfo = function(i) local n = ({ "PartsA", "PartsB", "PartsC" })[i]; return n, "Parts " .. n, "notes" end,
		IsAddOnLoaded = function(n) return n ~= "PartsB" end,
		GetAddOnEnableState = function(n, char) states[#states + 1] = tostring(char); return n == "PartsC" and 0 or 2 end,
	}, { __index = base })
	local p = ns.providers.addons
	p._dirty = true
	local a = {}
	for _, e in ipairs(ns:GetEntries(p)) do a[e.key] = e end
	check(asked == 1, "the addon list works out this character's name once, not once per addon: " .. asked)
	check(#states == 3 and states[1] == tostring(me) and states[2] == states[1] and states[3] == states[1],
		"every addon's state asked for this character: " .. table.concat(states, ", "))
	check(a.PartsA and a.PartsA.enabled == true and a.PartsA.detail == "enabled"
		and a.PartsB and a.PartsB.enabled == true and a.PartsB.detail == "enabled (.reload to apply)"
		and a.PartsC and a.PartsC.enabled == false and a.PartsC.detail == "disabled (.reload to apply)",
		"each addon's state as before: " .. tostring(a.PartsB and a.PartsB.detail) .. " / " .. tostring(a.PartsC and a.PartsC.detail))
	_G.C_AddOns, ns.CharacterName = base, saveName
	p._dirty = true
end

io.write("[providers parts: other classes' talent rows kept]\n")
do
	local TL, P = ns.Talents, ns.providers.talents
	local save = { cache = ns.db.talentCache, uc = _G.UnitClass, rcc = _G.RAID_CLASS_COLORS, tex = C_Spell.GetSpellTexture,
		tried = TL.triedOthers, easy = ns.db.easyMode }
	ns.db.easyMode = false
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	_G.RAID_CLASS_COLORS = { MAGE = { colorStr = "ff3fc7eb" } }
	local okB, _, build = pcall(GetBuildInfo) -- (the saved copy's key, as Talents.lua makes it)
	local function saved()
		return { key = TL.CACHE_FORMAT .. ":" .. tostring(okB and build or "?"), names = { MAGE = "Mage" },
			classes = { MAGE = { { 2001, "Ice Barrier", 52001, "Frost", 2, 1, 135988 }, { 2002, "Partsy Frostbolt", 52002, "Frost", 2, 5 } } } }
	end
	ns.db.talentCache, TL.triedOthers = saved(), nil
	local texture
	C_Spell.GetSpellTexture = function(id) if id == 52002 then return texture end return 1 end
	local function others()
		P._dirty = true
		local by = {}
		for _, e in ipairs(ns:GetEntries(P)) do if e.other then by[e.name] = e end end
		return by
	end
	local a = others()
	local ib, fb = a["Ice Barrier"], a["Partsy Frostbolt"]
	check(ib and fb and ib.detail == "|cff3fc7ebMage|r  Frost  1 rank" and fb.detail == "|cff3fc7ebMage|r  Frost  5 ranks"
		and ib.icon == 135988 and fb.icon == nil and ib.key == "MAGE:2001", "another class's talent rows: " .. tostring(ib and ib.detail))
	texture = 4242
	local b = others()
	check(b["Ice Barrier"] == ib and b["Partsy Frostbolt"] == fb, "a rebuild uses the same rows again, not new tables")
	check(fb.icon == 4242 and ib.icon == 135988 and ib.detail == "|cff3fc7ebMage|r  Frost  1 rank"
		and rawget(ib, "_ltext") == "frost mage talent" and ib.className == "Mage" and ib._rank == TL.OTHER_RANK,
		"...the same fields, and an icon the saved copy lacks asked again as a new row would: " .. tostring(fb.icon))
	local res = UI:Search("@talent class:mage")
	check(#res == 2 and res[1].classFile == "MAGE" and res[2].classFile == "MAGE", "class:mage still lists them: " .. #res)
	res = UI:Search("@talent partsy frostbolt")
	check(res[1] and res[1].name == "Partsy Frostbolt", "and finds one by name")
	-- something a row shows changed: made again
	_G.RAID_CLASS_COLORS = { MAGE = { colorStr = "ff0000ff" } }
	local c = others()
	local ib2 = c["Ice Barrier"]
	check(ib2 and ib2 ~= ib and ib2.detail == "|cff0000ffMage|r  Frost  1 rank", "the class's colour changed: its rows made again")
	ns.db.talentCache = saved() -- (another saved copy: read again)
	local d = others()
	check(d["Ice Barrier"] and d["Ice Barrier"] ~= ib2 and d["Ice Barrier"].detail == ib2.detail, "a new saved copy: made again")
	ns.db.talentCache, _G.UnitClass, _G.RAID_CLASS_COLORS, C_Spell.GetSpellTexture = save.cache, save.uc, save.rcc, save.tex
	TL.triedOthers, ns.db.easyMode = save.tried, save.easy
	P._dirty = true
end

io.write("[providers parts: bags]\n")
do
	local B = ns.Bags
	local all = true
	for _, k in ipairs({ "Bagnon", "Baganator", "Active", "Open", "FindButton", "Locations", "ShowItem", "Show" }) do
		all = all and type(B[k]) == "function"
	end
	check(all, "ns.Bags (Bags.lua) has every function it had, and Show")
	local p = ns.providers.items
	p._dirty = true
	local row
	for _, e in ipairs(ns:GetEntries(p)) do if e.locs then row = e break end end
	check(row and row.activate == B.Show, "a bag item's Enter is ns.Bags.Show")
end
