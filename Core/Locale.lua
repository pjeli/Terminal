local ns = select(2, ...)
local L = ns.L

-- the key bindings' names (Options > Keybindings), in the player's language (the translations are in by now)
BINDING_HEADER_TERMINAL = "Terminal"
BINDING_NAME_TERMINAL_TOGGLE = L["Toggle Terminal"] -- (Terminal is its name: capitalised, 0.46.12)
BINDING_NAME_TERMINAL_ADVANCED_ONCE = L["Open Terminal, or write its search in Advanced syntax"] -- (closed: as Toggle does, 0.54.3)
BINDING_NAME_TERMINAL_FUZZY = L["Fuzzy find, this time (every list, by name only)"]
BINDING_NAME_TERMINAL_SLASH = L["Open Terminal on a slash command (/)"]

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

-- (the other way: a two-byte lowercase letter's capital, for the first letter of a word)
local function UpperTwoByte(a, b)
	local cp = (a:byte() - 0xC0) * 64 + (b:byte() - 0x80)
	local to = cp
	if cp >= 0xE0 and cp <= 0xFE and cp ~= 0xF7 then to = cp - 32 -- Latin-1
	elseif cp >= 0x3B1 and cp <= 0x3C9 and cp ~= 0x3C2 then to = cp - 32 -- Greek
	elseif cp >= 0x430 and cp <= 0x44F then to = cp - 32 -- Cyrillic
	elseif cp >= 0x450 and cp <= 0x45F then to = cp - 80
	elseif (cp >= 0x100 and cp <= 0x12F) or (cp >= 0x132 and cp <= 0x137) or (cp >= 0x14A and cp <= 0x177) then
		if cp % 2 == 1 then to = cp - 1 end
	elseif (cp >= 0x139 and cp <= 0x148) or (cp >= 0x179 and cp <= 0x17E) then
		if cp % 2 == 0 then to = cp - 1 end
	end
	if to == cp then return a .. b end
	return string.char(0xC0 + math.floor(to / 64), 0x80 + to % 64)
end

--- The text with its first letter a capital, in every client language ns.Lower folds ("équipement" -> "Équipement").
--- (string.upper and "%l" know ASCII only: review, 0.53.6.)
function ns.UpperFirst(s)
	s = tostring(s or "")
	if s:find("^%l") then return (s:gsub("^%l", string.upper)) end
	local a, b = s:match("^([\195-\213])([\128-\191])")
	if a then return UpperTwoByte(a, b) .. s:sub(3) end
	return s
end

--- Every word with a capital first letter ("östliche pestländer" -> "Östliche Pestländer"; not "öStliche PestläNder",
--- as an ASCII-only %a made of it: review, 0.53.6).
function ns.Titled(s)
	return (tostring(s or ""):gsub("%S+", ns.UpperFirst))
end

--- A format string of the game's ("%s receives loot: %sx%d.") as an anchored pattern, and for each capture the format
--- argument it is ("%2$s" in some languages swaps them). One copy: the loot log's, the group's quest replies' and the
--- mail's subjects and chat lines had one each, two of them without "%2$s" (review, 0.53.6).
local PATTERN_MAGIC = { ["("] = true, [")"] = true, ["."] = true, ["+"] = true, ["-"] = true, ["*"] = true, ["?"] = true,
	["["] = true, ["]"] = true, ["^"] = true, ["$"] = true, ["%"] = true }
function ns.FormatPattern(fmt)
	if type(fmt) ~= "string" or fmt == "" then return nil end
	local out, args, i, nextArg = { "^" }, {}, 1, 1
	while i <= #fmt do
		local c = fmt:sub(i, i)
		if c == "%" then
			local num, kind, len = fmt:match("^%%(%d)%$([sd])()", i)
			if not num then kind, len = fmt:match("^%%([sd])()", i) end
			if kind then
				out[#out + 1] = kind == "s" and "(.-)" or "(%d+)"
				args[#args + 1] = tonumber(num) or nextArg
				nextArg = nextArg + 1
				i = len
			else
				out[#out + 1] = "%%"
				i = i + ((fmt:sub(i + 1, i + 1) == "%") and 2 or 1)
			end
		else
			out[#out + 1] = PATTERN_MAGIC[c] and ("%" .. c) or c
			i = i + 1
		end
	end
	out[#out + 1] = "$"
	return table.concat(out), args
end

--- Without textures and colour codes.
function ns.Plain(s)
	return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- the words Simple mode reads as "not" (Joins.lua's E.NOT_WORDS: "rare ring not boe")
local NOT_WORDS = { ["not"] = true, no = true, without = true, except = true }

--- A line as a plain-word question reads it ("party quests", "what killed me"): lower case, apostrophes dropped
--- ("what's" -> "whats"), the rest of the punctuation as spaces. nil when it can't be one: Advanced syntax (@kinds,
--- key:value, chains, sums, a .command or /slash), a word the search reads as "not" ("-cod", "!dead"), or a "not" word
--- the question doesn't read itself (`allow`: the ones it does, { without = true }). Every question reads its line
--- through this (review, 0.53.6: 19 copies, two of them; "party -dead", "party not dead" and "mail not cod" listed the
--- very thing left out).
-- (the last line read, per `allow`: every question asks of the same line on a keystroke, ~29 times; 0.63.7, review:
-- a sixth of a plain search's time)
local qtLast, NO_ALLOW = setmetatable({}, { __mode = "k" }), {}
function ns.QuestionText(text, allow)
	if type(text) ~= "string" then return nil end
	local last = qtLast[allow or NO_ALLOW]
	if last and last.text == text then return last.t or nil end
	local t
	if not (text:find("[@:>|]") or text:find("^%s*[%./!%-]") or (" " .. text):find("%s[!%-][%a\128-\255]")) then
		t = ns.Lower(text):gsub("'", ""):gsub("%p", " ")
		for w in t:gmatch("%S+") do
			if NOT_WORDS[w] and not (allow and allow[w]) then t = nil break end
		end
	end
	if last then last.text, last.t = text, t or false
	else qtLast[allow or NO_ALLOW] = { text = text, t = t or false } end
	return t
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
	-- (the game's BANK is @bank, this character's own, not @stored, everyone's: 0.62.3, the player's screenshot, @bank
	-- listed @stored's rows, its "Bank" word put first)
	bank = { "BANK" },
	calendar = { "CALENDAR" },
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
