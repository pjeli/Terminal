local ns = select(2, ...)

-- What players call places: "brd" finds Blackrock Depths' loot, "@quest strat" quests in
-- Stratholme, "@map sw" Stormwind City. Lowercase shorthand -> the full names (lowercase, as
-- they are in a row's name or text: "deadmines" matches "The Deadmines" and "Deadmines").
-- A search word that is one of these also matches rows with the full name (ScoreEntry, Search/Score.lua (scoring)).
-- English names; on another client also each place as the game names it there (PLACES, below: 0.69.6).
-- DM is Dire Maul, as classic players say it; the Deadmines are VC (Van Cleef) or dmines.
local S = {
	-- dungeons
	rfc = { "ragefire chasm" },
	wc = { "wailing caverns" },
	vc = { "deadmines" },
	dmines = { "deadmines" },
	sfk = { "shadowfang keep" },
	stocks = { "stockade" },
	bfd = { "blackfathom deeps" },
	gnomer = { "gnomeregan" },
	rfk = { "razorfen kraul" },
	sm = { "scarlet monastery" },
	rfd = { "razorfen downs" },
	uld = { "uldaman" },
	zf = { "zul'farrak" },
	mara = { "maraudon" },
	st = { "sunken temple", "atal'hakkar" },
	brd = { "blackrock depths" },
	brs = { "blackrock spire" },
	lbrs = { "lower blackrock spire" },
	ubrs = { "upper blackrock spire" },
	dm = { "dire maul" },
	scholo = { "scholomance" },
	strat = { "stratholme" },
	-- raids
	zg = { "zul'gurub" },
	mc = { "molten core" },
	bwl = { "blackwing lair" },
	ony = { "onyxia's lair" },
	aq = { "ahn'qiraj" },
	aq20 = { "ruins of ahn'qiraj" },
	aq40 = { "temple of ahn'qiraj" },
	naxx = { "naxxramas" },
	-- battlegrounds
	wsg = { "warsong gulch" },
	ab = { "arathi basin" },
	av = { "alterac valley" },
	-- cities and zones
	sw = { "stormwind" },
	["if"] = { "ironforge" },
	org = { "orgrimmar" },
	tb = { "thunder bluff" },
	uc = { "undercity" },
	darn = { "darnassus" },
	stv = { "stranglethorn" },
	epl = { "eastern plaguelands" },
	wpl = { "western plaguelands" },
	ungoro = { "un'goro" },
	sos = { "swamp of sorrows" },
	bs = { "burning steppes" },
	sg = { "searing gorge" },
	bb = { "booty bay" },
	xr = { "crossroads" },
}

-- each place's ids in the game's tables: an instance (map), a zone map (ui), an area. Written by tests/gen_data.py
-- from the client build's Map, UiMap and AreaTable (docs/DATA_SOURCES.md), never by hand
-- generated: tests/gen_data.py shorthand (do not edit by hand)
local PLACES = {
	rfc = { map = { 389 } }, -- Ragefire Chasm
	wc = { map = { 43 } }, -- Wailing Caverns
	vc = { map = { 36 } }, -- Deadmines
	dmines = { map = { 36 } }, -- Deadmines
	sfk = { map = { 33 } }, -- Shadowfang Keep
	stocks = { area = { 717 } }, -- The Stockade
	bfd = { map = { 48 } }, -- Blackfathom Deeps
	gnomer = { map = { 90 } }, -- Gnomeregan
	rfk = { map = { 47 } }, -- Razorfen Kraul
	sm = { map = { 189 } }, -- Scarlet Monastery
	rfd = { map = { 129 } }, -- Razorfen Downs
	uld = { map = { 70 } }, -- Uldaman
	zf = { map = { 209 } }, -- Zul'Farrak
	mara = { map = { 349 } }, -- Maraudon
	st = { map = { 109 } }, -- Sunken Temple
	brd = { map = { 230 } }, -- Blackrock Depths
	brs = { map = { 229 } }, -- Blackrock Spire
	lbrs = { map = { 229 } }, -- Blackrock Spire
	ubrs = { map = { 229 } }, -- Blackrock Spire
	dm = { map = { 429 } }, -- Dire Maul
	scholo = { map = { 289 } }, -- Scholomance
	strat = { map = { 329 } }, -- Stratholme
	zg = { map = { 309 } }, -- Zul'Gurub
	mc = { map = { 409 } }, -- Molten Core
	bwl = { map = { 469 } }, -- Blackwing Lair
	ony = { map = { 249 } }, -- Onyxia's Lair
	aq = { area = { 3428 } }, -- Ahn'Qiraj
	aq20 = { map = { 509 } }, -- Ruins of Ahn'Qiraj
	aq40 = { area = { 16076 } }, -- Temple of Ahn'Qiraj
	naxx = { map = { 533, 2921 } }, -- Naxxramas
	wsg = { map = { 489 } }, -- Warsong Gulch
	ab = { map = { 529 } }, -- Arathi Basin
	av = { map = { 30 } }, -- Alterac Valley
	sw = { ui = { 1453 } }, -- Stormwind City
	["if"] = { ui = { 1455 } }, -- Ironforge
	org = { ui = { 1454 } }, -- Orgrimmar
	tb = { ui = { 1456 } }, -- Thunder Bluff
	uc = { ui = { 1458 } }, -- Undercity
	darn = { ui = { 1457 } }, -- Darnassus
	stv = { ui = { 1434 } }, -- Stranglethorn Vale
	epl = { ui = { 1423 } }, -- Eastern Plaguelands
	wpl = { ui = { 1422 } }, -- Western Plaguelands
	ungoro = { ui = { 1449 } }, -- Un'Goro Crater
	sos = { ui = { 1435 } }, -- Swamp of Sorrows
	bs = { ui = { 1428 } }, -- Burning Steppes
	sg = { ui = { 1427 } }, -- Searing Gorge
	bb = { area = { 35 } }, -- Booty Bay
	xr = { area = { 380 } }, -- The Crossroads
}
-- end of generated: shorthand

--- On a client in another language, each shorthand also stands for the place as the game names it there ("brd":
--- "schwarzfelstiefen"), lowercase, after its English ones. Run at load, and by the tests.
function ns.ShorthandLocalize()
	local lang = ns.LOCALE
	if lang == nil or lang == "enUS" or lang == "enGB" then return end
	local zone = _G.GetRealZoneText
	local mapInfo = C_Map and C_Map.GetMapInfo
	local areaInfo = C_Map and C_Map.GetAreaInfo
	for short, ids in pairs(PLACES) do
		local list = S[short]
		if list then
			local function Put(name)
				if type(name) ~= "string" or name == "" then return end
				local l = ns.Lower(name)
				for _, have in ipairs(list) do if have == l then return end end
				list[#list + 1] = l
			end
			for _, id in ipairs(ids.map or {}) do if zone then local ok, n = pcall(zone, id) if ok then Put(n) end end end
			for _, id in ipairs(ids.ui or {}) do
				if mapInfo then local ok, i = pcall(mapInfo, id) if ok and type(i) == "table" then Put(i.name) end end
			end
			for _, id in ipairs(ids.area or {}) do if areaInfo then local ok, n = pcall(areaInfo, id) if ok then Put(n) end end end
		end
	end
end
ns.ShorthandLocalize()

ns.Shorthand = S
