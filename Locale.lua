local ns = select(2, ...)

-- Text helpers for every client language, and the game's own words for Terminal's kinds.
--
-- The game's string.lower folds ASCII only, and Lua patterns like %w or [^%w] only know ASCII:
-- on a Korean client "[^%w]" deletes every letter. So names are compared with these helpers
-- instead, and English words from the client are never matched: the game's own globals are.

--- Lowercase for matching: ASCII plus the two-byte letters other clients use (accented Latin,
--- Greek, Cyrillic), so "Équipement" is found by "équipement" and "Рыба" by "рыба".
--- Korean and Chinese have no case and pass through unchanged.
local function FoldTwoByte(a, b)
	local cp = (a:byte() - 0xC0) * 64 + (b:byte() - 0x80)
	local to = cp
	if cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7 then to = cp + 32 -- Latin-1
	elseif cp >= 0x391 and cp <= 0x3A9 and cp ~= 0x3A2 then to = cp + 32 -- Greek
	elseif cp >= 0x410 and cp <= 0x42F then to = cp + 32 -- Cyrillic
	elseif cp >= 0x400 and cp <= 0x40F then to = cp + 80
	elseif (cp >= 0x100 and cp <= 0x12F) or (cp >= 0x132 and cp <= 0x137) or (cp >= 0x14A and cp <= 0x177) then
		if cp % 2 == 0 then to = cp + 1 end -- Latin Extended-A: even is upper case...
	elseif (cp >= 0x139 and cp <= 0x148) or (cp >= 0x179 and cp <= 0x17E) then
		if cp % 2 == 1 then to = cp + 1 end -- ...but odd here
	end
	if to == cp then return a .. b end
	return string.char(0xC0 + math.floor(to / 64), 0x80 + to % 64)
end

function ns.Lower(s)
	s = tostring(s or ""):lower()
	if not s:find("[\195-\213]") then return s end -- the lead bytes of those letters
	return (s:gsub("([\195-\213])([\128-\191])", FoldTwoByte))
end

--- Without textures and colour codes.
function ns.Plain(s)
	return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

--- A key for comparing names: plain, lowercase, without spaces and ASCII punctuation.
--- Letters of every language are kept ("Deadly Boss Mods" == "deadlybossmods").
function ns.Norm(s)
	return (ns.Lower(ns.Plain(s)):gsub("[%s%p]", ""))
end

--- The game's own text for a global string (REPUTATION...), cleaned up; `fallback` when the
--- client has none, or it is a format string ("%s").
function ns.GameText(global, fallback)
	local v = global and _G[global]
	if type(v) == "string" and not v:find("%", 1, true) then
		v = ns.Plain(v):gsub("^%s+", ""):gsub("%s+$", "")
		if v ~= "" then return v end
	end
	return fallback
end

-- The game's words for each kind, accepted after @ next to the English ones: a Korean client
-- can type @평판 (reputation) or @매크로 (macros).
local KINDS = {
	items = { "ITEMS" },
	equipmentset = { "EQUIPMENT_MANAGER" },
	reputation = { "REPUTATION" },
	skills = { "SKILLS" },
	professions = { "TRADE_SKILLS", "PROFESSIONS_BUTTON" },
	spells = { "SPELLS", "SPELLBOOK" },
	quests = { "QUESTS_LABEL", "QUESTLOG_BUTTON" },
	macros = { "MACROS" },
	currency = { "CURRENCY" },
	mounts = { "MOUNTS" },
	talents = { "TALENTS" },
	achievements = { "ACHIEVEMENT_BUTTON" },
	addons = { "ADDONS" },
	gameoptions = { "OPTIONS", "SETTINGS" },
	maps = { "WORLD_MAP" },
	loot = { "LOOT" },
	stored = { "BANK" },
}

--- Adds the game's words to a provider's aliases (called by RegisterProvider, so providers
--- registered late, like AtlasLoot's, get them too). Each word becomes one @token.
function ns.LocalizeKind(p)
	local have = {}
	for _, a in ipairs(p.aliases) do have[ns.Lower(a)] = true end
	for _, g in ipairs(KINDS[p.id] or {}) do
		local word = ns.GameText(g)
		local token = word and word:gsub("[%s%p]", "")
		if token and token ~= "" and not have[ns.Lower(token)] then
			p.aliases[#p.aliases + 1] = token
			have[ns.Lower(token)] = true
		end
	end
end
