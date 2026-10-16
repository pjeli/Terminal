-- Spell ids (0.54.1, a player's ask: "I'd love if 'spellid claw' would let me copy 1082, and 'spellid 1082' would show
-- druid's Claw rank 1"): SpellIds.lua's question; the id in spells', talents' and @training's tooltips.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L, SI = ns.L, ns.SpellIds

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[spellids: a spell's id by its name, a spell by its id]\n")
do
	local save = { api = rawget(_G, "WT_API"), name = C_Spell.GetSpellName, sub = C_Spell.GetSpellSubtext,
		desc = C_Spell.GetSpellDescription, show = ns.ShowText, easy = ns.db.easyMode }
	local NAMES = { [1082] = "Claw", [3029] = "Claw", [5221] = "Shred", [768] = "Cat Form" }
	local SUBS = { [1082] = "Rank 1", [3029] = "Rank 2", [5221] = "Rank 1" }
	C_Spell.GetSpellName = function(id) return NAMES[id] or save.name(id) end
	C_Spell.GetSpellSubtext = function(id) return SUBS[id] end
	C_Spell.GetSpellDescription = function(id) if id == 1082 then return "Claw the enemy, causing 27 additional damage." end return "" end
	-- What's Training's list: every rank of your class's spells, known or not
	_G.WT_API = { version = 1, Status = {}, Event = {}, IsReady = function() return true end, GetSource = function() end,
		RegisterCallback = function() end,
		GetSpells = function() return {
			{ id = 1082, name = "Claw", subText = "Rank 1", level = 10, status = "known" },
			{ id = 3029, name = "Claw", subText = "Rank 2", level = 18, status = "available" },
			{ id = 5221, name = "Shred", subText = "Rank 1", level = 22, status = "notLevel" },
			{ id = "i:1", name = "Claw", subText = "Rank 9", level = 60, status = "notLevel", isItem = true, itemId = 1 },
		} end }

	-- the question, its spellings
	check(SI.Question("spellid claw").words[1] == "claw" and SI.Question("spell id claw").words[1] == "claw"
		and SI.Question("claw spell id").words[1] == "claw" and SI.Question("spell ids for claw").words[1] == "claw"
		and SI.Question("SpellID 1082").id == 1082, "spellid claw, spell id claw, claw spell id, spell ids for claw, SpellID 1082")
	check(SI.Question("spellid") == nil and SI.Question("spells not on my bars") == nil and SI.Question("claw") == nil
		and SI.Question("@spell claw") == nil, "not the question: a word alone, another question, Advanced syntax")

	-- by name: every rank, each with its id, by rank
	local rows, note = SI.Answer(SI.Question("spellid claw"))
	check(Names(rows) == "Claw (Rank 1) | Claw (Rank 2)", "every rank of Claw (not a grimoire): " .. Names(rows))
	check(rows[1].spellID == 1082 and rows[1].detail:find(L["id %d"]:format(1082), 1, true) and note:find(L["Enter copies one"], 1, true),
		"each says its id: " .. tostring(rows[1].detail))
	local copied
	ns.ShowText = function(_, title, text) copied = text end
	rows[1].activate(rows[1])
	check(copied == "1082", "Enter: the id to copy: " .. tostring(copied))
	check(table.concat({ ns.Easy.Verbs(rows[1]) }, "/") ~= "", "its verbs")
	-- by id
	rows = SI.Answer(SI.Question("spellid 1082"))
	check(rows[1] and rows[1].name == "Claw (Rank 1)" and rows[1].spellID == 1082 and rows[1].tip and rows[1].tip:find("Claw the enemy", 1, true),
		"spellid 1082: Claw (Rank 1), what it does: " .. Names(rows))
	rows = SI.Answer(SI.Question("spellid 999999"))
	check(rows[1] and rows[1].noActivate and rows[1].name == L["No spell with id %d"]:format(999999), "an id the game has no spell for: said")
	rows = SI.Answer(SI.Question("spellid frobnicate"))
	check(rows[1] and rows[1].noActivate, "a name nothing has: said: " .. Names(rows))
	-- through the prompt, in Simple mode and Advanced alike
	for _, simple in ipairs({ true, false }) do
		ns.db.easyMode = simple; UI:EasyChanged()
		UI:Open("spellid claw"); FlushAll()
		check(Names(UI.Results()) == "Claw (Rank 1) | Claw (Rank 2)", (simple and "Simple" or "Advanced") .. ": typed: " .. Names(UI.Results()))
		UI:Hide(); FlushAll()
	end
	check(ns.QuestionToAdvanced("spellid claw") == "spellid claw ", "as Advanced: the same words")
	-- the id in the tooltips of spells, talents and What's Training's spells
	check(SI.Of({ kind = "spells", spellID = 1082 }) == 1082 and SI.Of({ kind = "talents", spellID = 7 }) == 7
		and SI.Of({ kind = "training", wtId = 3029 }) == 3029 and SI.Of({ kind = "training", wtId = "i:1", isItem = true }) == nil
		and SI.Of({ kind = "items", spellID = 5 }) == nil, "which rows' tooltips say a spell id")
	-- (0.54.3, the player: @classspell's tooltip lists every rank's id already: no Spell ID line under it)
	check(SI.Of({ kind = "classspells", spellID = 1714 }) == nil, "@classspell: no Spell ID line, its ranks have them")
	local lines = {}
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("spellid claw"); FlushAll()
	UI:UpdateTooltip()
	local tip = _G.TerminalTooltip
	check(tip ~= nil, "(the tooltip made)")
	local add = tip.AddLine
	tip.AddLine = function(self, s, ...) lines[#lines + 1] = tostring(s) return add(self, s, ...) end
	tip.entry, tip.noneFor = nil, nil
	tip:Hide()
	UI:UpdateTooltip()
	tip.AddLine = add
	check(table.concat(lines, "\n"):find(L["Spell ID: %d"]:format(1082), 1, true), "the tooltip says the id: " .. table.concat(lines, " / "))
	UI:Hide(); FlushAll()

	_G.WT_API = save.api
	C_Spell.GetSpellName, C_Spell.GetSpellSubtext, C_Spell.GetSpellDescription = save.name, save.sub, save.desc
	ns.ShowText, ns.db.easyMode = save.show, save.easy
	UI:EasyChanged()
end
