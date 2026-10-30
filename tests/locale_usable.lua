-- Terminal on another client language, usable and not only translated (tests/locale_usable.py runs this once per
-- language Terminal is translated into, the whole addon loaded as that client loads it). Not under tests/smoke/: the
-- main run is English's.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local L, E = ns.L, ns.Easy
local lang = ns.LOCALE

io.write("[usable in " .. tostring(lang) .. "]\n")

-- each language's own letters: an item as its client names it, a part typed in small letters, and one in capitals
local SAMPLES = {
	deDE = { name = "Großer Rückenschild", typed = "rückensch", caps = "RÜCKENSCHILD", other = "Leinenstoff" },
	esES = { name = "Paño de lino", typed = "paño", caps = "PAÑO DE LINO", other = "Tela de lana" },
	esMX = { name = "Paño de lino", typed = "paño", caps = "PAÑO DE LINO", other = "Tela de lana" },
	frFR = { name = "Étoffe de lin", typed = "étoffe", caps = "ÉTOFFE DE LIN", other = "Étoffe de laine" },
	ruRU = { name = "Льняная ткань", typed = "льнян", caps = "ЛЬНЯНАЯ ТКАНЬ", other = "Шерстяная ткань" },
	zhCN = { name = "亚麻布", typed = "亚麻", caps = "亚麻布", other = "毛料" },
}
local sample = SAMPLES[lang]
check(sample ~= nil, "a sample for " .. tostring(lang))
sample = sample or SAMPLES.deDE

--- The characters of a UTF-8 text, each whole.
local function Chars(s)
	local out = {}
	for ch in tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
	return out
end
--- A line still carrying a format code ("%s", "%d"): a translation that didn't take its values.
local function Unformatted(line) return type(line) == "string" and line:find("%%[sd]") ~= nil end

-- 1. the translations are there: nearly every text in this language
do
	local keys, done, missing = 0, 0, {}
	for line in io.lines("Terminal/Locales/enUS.lua") do
		local k = line:match('^L%["(.*)"%] = true')
		if k then
			k = k:gsub('\\"', '"'):gsub("\\\\", "\\")
			keys = keys + 1
			if rawget(L, k) ~= nil then done = done + 1 elseif #missing < 5 then missing[#missing + 1] = k end
		end
	end
	local share = keys > 0 and done / keys or 0
	io.write(("  %s: %d of %d texts translated (%.1f%%)\n"):format(lang, done, keys, share * 100))
	check(share >= 0.95, lang .. ": 95% of the texts translated at least: " .. done .. "/" .. keys .. "; not: " .. table.concat(missing, " | "))
	local same = 0
	for k, v in pairs(L) do if type(v) ~= "string" or v == "" then same = same + 1 end end
	check(same == 0, lang .. ": every translation is a text")
end

-- 2. its own letters typed: whole characters in, Backspace takes one whole character, the caret never inside one
do
	UI:Open("")
	local chars = Chars(sample.name)
	for _, ch in ipairs(chars) do T.F.scripts.OnChar(T.F, ch) end
	check(T.query() == sample.name, lang .. ": typed as it is: " .. T.query())
	T.key("BACKSPACE")
	check(T.query() == table.concat(chars, "", 1, #chars - 1), lang .. ": Backspace takes one whole character: " .. T.query())
	T.key("LEFT")
	T.F.scripts.OnChar(T.F, chars[1])
	local q = T.query()
	local whole = true
	for _, ch in ipairs(Chars(q)) do if #ch == 1 and ch:byte() >= 128 then whole = false end end
	check(whole and #Chars(q) == #chars, lang .. ": a character typed after Left lands between characters: " .. q)
	UI:Hide()
end

-- 3. searching its own names: a part in small letters, the whole in capitals; nothing found that only shares bytes
local pick = function(rows, name) for i, e in ipairs(rows) do if e.name == name then return i end end end
do
	local had = ns.providers.locsample
	local rows = { { name = sample.name, key = 1 }, { name = sample.other, key = 2 } }
	if lang == "zhCN" then
		-- (common letters of item names: a search for one must never find a name it isn't in, by its bytes alone)
		for i, n in ipairs({ "铜矿石", "铁锭", "银锭", "魔法药水", "治疗药剂", "符文布", "丝绸", "魔纹布", "厚皮", "草药" }) do
			rows[#rows + 1] = { name = n, key = 10 + i }
		end
	end
	if not had then
		ns:RegisterProvider("locsample", { label = "Sample", aliases = { "locsample" }, collect = function() return rows end })
	end
	ns.providers.locsample._dirty = true
	-- (Simple mode lists what's in a category: the sample is in Items while this runs)
	local items
	for _, c in ipairs(E.CATEGORIES) do if c.id == "items" then items = c end end
	table.insert(items.kinds, "locsample")
	if E.CategoriesChanged then E.CategoriesChanged() end
	local easy = ns.db.easyMode
	for _, mode in ipairs({ false, true }) do
		ns.db.easyMode = mode
		local said = mode and "Simple" or "Advanced"
		for _, typed in ipairs({ sample.typed, sample.caps }) do
			for _, p in pairs(ns.providers) do p._dirty = true end
			local found = UI:Search(typed)
			check(pick(found, sample.name) ~= nil, lang .. " (" .. said .. "): \"" .. typed .. "\" finds " .. sample.name)
		end
	end
	ns.db.easyMode = false
	if lang == "zhCN" then
		local wrong = {}
		local pool = { "铜", "矿", "石", "铁", "锭", "银", "魔", "法", "药", "水", "治", "疗", "剂", "符", "文", "布", "丝", "绸", "纹", "厚", "皮", "草", "亚", "麻", "毛", "料" }
		for _, ch in ipairs(pool) do
			for _, p in pairs(ns.providers) do p._dirty = true end
			for _, e in ipairs(UI:Search("@locsample " .. ch)) do
				if e.kind == "locsample" and not tostring(e.name):find(ch, 1, true) then wrong[#wrong + 1] = ch .. " -> " .. tostring(e.name) end
			end
		end
		check(#wrong == 0, "zhCN: a character searched finds only names with that character: " .. table.concat(wrong, ", "))
		-- (two characters typed: names with both, in order, as letters are for other languages)
		for _, p in pairs(ns.providers) do p._dirty = true end
		local found = UI:Search("@locsample 魔布")
		check(pick(found, "魔纹布") ~= nil and not pick(found, "魔法药水"), "zhCN: two characters typed: a name with both")
		-- (no close spellings by bytes: 铝 aluminium is a byte from 铁 iron, another word, not a slip of the hand)
		for _, p in pairs(ns.providers) do p._dirty = true end
		found = UI:Search("@locsample 铝锭")
		check(not pick(found, "铁锭"), "zhCN: no \"close spelling\" a byte away: 铝锭 doesn't find 铁锭")
	end
	if lang == "ruRU" then
		-- (close spellings allowed by letters, not bytes: a 7-letter word is 14 bytes)
		local S = ns.Score
		check(S.NearLimit(#"льняная", "льняная") == S.NearLimit(7) and S.NearLimit(#"ткань", "ткань") == S.NearLimit(5),
			"ruRU: a close spelling's room counted in letters")
	end
	ns.db.easyMode = easy
	for i = #items.kinds, 1, -1 do if items.kinds[i] == "locsample" then table.remove(items.kinds, i) end end
	ns.providers.locsample = had
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "locsample" and not had then table.remove(ns.providerOrder, i) end end
end

-- 4. Simple mode's questions said its way: each phrasing translated is read as the English line it stands for, and
-- those released (the first six) are all translated (the rest wait for the release's translations: CLAUDE.md)
local RELEASED = { ["mats for %s"] = true, ["what uses %s"] = true, ["where to learn %s"] = true, ["where to get %s"] = true,
	["nearest %s"] = true, ["where %s"] = true }
do
	local untranslated, waiting = {}, 0
	for _, ph in ipairs(E.PHRASES or {}) do
		local said = ph[2]
		if type(said) ~= "string" or said:find("^phrases: ") then
			if RELEASED[ph[1]] then untranslated[#untranslated + 1] = ph[1] else waiting = waiting + 1 end
		else
			for alt in (said .. "|"):gmatch("([^|]*)|") do
				local line = alt:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%%s", "xyzzy")
				if line ~= "" then
					local english = E.English(line)
					local want = ph[1]:find("%s", 1, true) and ph[1]:format("xyzzy") or ph[1]
					check(ns.Lower(english) == ns.Lower(want), lang .. ": \"" .. line .. "\" read as \"" .. want .. "\": " .. tostring(english))
				end
			end
		end
	end
	check(#untranslated == 0, lang .. ": Simple mode's phrasings translated: " .. table.concat(untranslated, ", "))
	if waiting > 0 then io.write(("  %s: %d question phrasings wait for their translation\n"):format(lang, waiting)) end
end

-- 5. the empty prompt's examples: "try:" in this language, Shift+Right still typing the example
do
	local easy = ns.db.easyMode
	ns.db.easyMode = true
	UI:Open("")
	local ghost = UI.ghost and UI.ghost:IsShown() and (UI.ghost:GetText() or "") or ""
	check(ghost ~= "" and not ghost:find("^try:"), lang .. ": the example said in this language: " .. ghost)
	local typed = UI:SuggestionText()
	check(type(typed) == "string" and typed ~= "", lang .. ": Shift+Right has an example to type: " .. tostring(typed))
	UI:Hide()
	ns.db.easyMode = easy
end

-- 6. help, and every command: runs, says what it does, and nothing it says keeps a format code
local SKIP = { reload = true, rl = true } -- (the game reloaded)
do
	local lines = E.HelpLines and E.HelpLines() or {}
	local bad = {}
	for _, l in ipairs(lines) do if Unformatted(l) then bad[#bad + 1] = l end end
	check(#lines > 0 and #bad == 0, lang .. ": Simple mode's help: " .. #lines .. " lines; unformatted: " .. table.concat(bad, " | "))
	local names = {}
	for name in pairs(ns.commands) do names[#names + 1] = name end
	table.sort(names)
	local broken, unformatted, nodesc = {}, {}, {}
	for _, name in ipairs(names) do
		local c = ns.commands[name]
		if type(c.desc) ~= "string" or c.desc == "" or Unformatted(c.desc) then nodesc[#nodesc + 1] = name end
		if c.complete then
			local ok, err = pcall(c.complete, "")
			if not ok then broken[#broken + 1] = name .. " (complete): " .. tostring(err) end
		end
		if not SKIP[name] and c.run then
			local ok, out = pcall(c.run, "")
			if not ok then broken[#broken + 1] = name .. ": " .. tostring(out)
			elseif type(out) == "table" then
				for _, l in ipairs(out) do if Unformatted(l) then unformatted[#unformatted + 1] = name .. ": " .. l end end
			end
		end
		if ns.Panel and ns.Panel.CloseAll then pcall(ns.Panel.CloseAll) end
	end
	check(#broken == 0, lang .. ": every command runs: " .. table.concat(broken, " || "))
	check(#unformatted == 0, lang .. ": nothing a command says keeps a format code: " .. table.concat(unformatted, " || "))
	check(#nodesc == 0, lang .. ": every command says what it does: " .. table.concat(nodesc, ", "))
end

-- 7. fonts: every font the settings offer has this language's letters
do
	local Theme = ns.Theme
	local latinOnly = { ["fonts\\frizqt__.ttf"] = true, ["fonts\\morpheus.ttf"] = true, ["fonts\\skurri.ttf"] = true }
	if lang == "zhCN" or lang == "zhTW" or lang == "koKR" then latinOnly["fonts\\arialn.ttf"] = true end
	local wrong = {}
	for _, id in ipairs(Theme.FONT_ORDER) do
		local path = ns.Lower(tostring(Theme.FONTS[id]))
		-- (the game's own font, STANDARD_TEXT_FONT, is each client's: here it's the harness's English one)
		local own = Theme.FONTS[id] == _G.STANDARD_TEXT_FONT
		if latinOnly[path] and not own and (lang == "ruRU" or lang == "zhCN" or lang == "zhTW" or lang == "koKR") then
			wrong[#wrong + 1] = id .. " = " .. path
		end
	end
	check(#wrong == 0, lang .. ": every font offered has its letters: " .. table.concat(wrong, ", "))
end

-- 8. trainers by what they teach: QuestieDB translates NPC titles on this client ("Bergbaulehrer", "Maître des
-- mineurs", "采矿训练师"), and they're matched as Questie's English ones say it ("Mining Trainer"). Its untranslated title
-- is read for that (LibQuestieDB's GetRaw); what's shown and searched stays the client's
do
	local I, F = ns.Integrations, ns.Filters
	local was = I.NpcField
	local titles = { deDE = "Bergbaulehrer", esES = "Instructor de minería", esMX = "Instructor de minería", frFR = "Maître des mineurs",
		ruRU = "Учитель горного дела", zhCN = "采矿训练师" }
	local shown = titles[lang] or "Bergbaulehrer"
	I.NpcField = function(id, field)
		if id ~= 990077 then return was(id, field) end
		return ({ subName = shown, subNameEn = "Mining Trainer" })[field]
	end
	local row = { kind = "npc", key = 990077, name = "Test", sub = shown }
	if F.ClearCache then F.ClearCache() end
	local ok1, a = pcall(function() return F.Parse("trainer:mining")(row) end)
	local ok2, b = pcall(function() return F.Parse("trainer:blacksmithing")(row) end)
	check(ok1 and a and ok2 and not b, lang .. ": a trainer of mining by Questie's title, translated here (" .. shown .. ")")
	I.NpcField = was
	if F.ClearCache then F.ClearCache() end
end

