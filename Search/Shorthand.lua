local ns = select(2, ...)

-- What players call places: "brd" finds Blackrock Depths' loot, "@quest strat" quests in
-- Stratholme, "@map sw" Stormwind City. Lowercase shorthand -> the full names (lowercase, as
-- they are in a row's name or text: "deadmines" matches "The Deadmines" and "Deadmines").
-- A search word that is one of these also matches rows with the full name (ScoreEntry, Search/Score.lua (scoring)).
-- English names: on other clients only rows that have the English name match.
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

ns.Shorthand = S
