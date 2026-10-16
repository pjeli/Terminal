local ns = select(2, ...)
local L = ns.L

-- Spell ids (0.54.1, a player's ask: "what I most need to go to Wowhead for is looking up spell ids"):
--
--   "spellid claw", "spell id claw", "claw spell id"   every spell called that and each of its ranks, with its id:
--                                                     Enter copies the id, Shift+Enter links it in chat
--   "spellid 1082"                                    the spell with that id: its name, rank and what it does
--
-- The names are looked for in your spellbook (every rank you know), What's Training's list (every rank of your class's
-- spells, known or not), and the talents (yours and every other class's); a spell the game knows by that name too. The
-- spell ids show in the tooltips of spells, talents and @training's rows as well (Tooltip.lua).

local SI = {}
ns.SpellIds = SI

local Safe, Str, Lower = ns.Safe, ns.Str, ns.Lower
local SEP = ns.DETAIL_SEP
local ICON = "Interface\\Icons\\INV_Misc_Note_01"

local function SpellName(id) return Str(Safe(C_Spell and C_Spell.GetSpellName, id)) end
local function SpellIcon(id) return Safe(C_Spell and C_Spell.GetSpellTexture, id) end
local function Subtext(id)
	local s = Str(Safe(C_Spell and C_Spell.GetSpellSubtext, id))
	return s and not ns.Secret(s) and s or nil
end
local function Link(e) return Safe(C_Spell and C_Spell.GetSpellLink, e.spellID) end

local function CopyId(e)
	ns:ShowText(L["Spell ID of %s"]:format(tostring(e.name)), tostring(e.spellID), { compact = true })
end
local function LinkIt(e) ns.LinkInChat(Link(e) or ("[" .. tostring(e.name) .. "] " .. tostring(e.spellID))) end
local CHATBOX = ns.ChatBoxSpec(function(e) return Link(e) or tostring(e.spellID) end)

--- A row for a spell id: "Claw (Rank 1)", "1082  ·  Druid  ·  your spellbook".
function SI.Row(id, name, rank, where, extra)
	local shown = rank and (name .. " (" .. rank .. ")") or name
	return {
		key = "spellid:" .. id, kind = "spellid", kindLabel = L["Spell ID"], name = shown, spellID = id,
		icon = SpellIcon(id) or ICON, detail = ns.Detail(L["id %d"]:format(id), extra, where),
		getLink = Link, activate = CopyId, staysOpen = false,
		secondary = LinkIt, secondarySecure = CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen,
		shareLink = function(e) return (Link(e) or e.name) .. " " .. L["id %d"]:format(e.spellID) end,
	}
end

-- every spell Terminal knows a name and id of: { id, name, rank, where, class }
local function Candidates()
	local out = {}
	local function Add(id, name, rank, where, class)
		if type(id) == "number" and type(name) == "string" and name ~= "" then out[#out + 1] = { id, name, rank, where, class } end
	end
	local myClass = select(1, Safe(UnitClass, "player"))
	-- your spellbook: every rank you know
	local sp = ns.providers.spells
	for _, e in ipairs(sp and ns:GetEntries(sp) or {}) do
		for _, r in ipairs(e.ranks or { { e.spellID } }) do Add(r[1], e.name, r[2], L["your spellbook"], myClass) end
	end
	-- What's Training: every rank of your class's spells, known or not
	local api = ns.WhatsTraining and ns.WhatsTraining.Api()
	if api then
		local ok, spells = pcall(api.GetSpells)
		for _, s in ipairs(ok and type(spells) == "table" and spells or {}) do
			if type(s.id) == "number" and not s.isItem then
				Add(s.id, s.name, Str(s.subText), L["What's Training"], myClass)
			end
		end
	end
	-- every class's spells, every rank (ClassSpellData.lua)
	local CS = ns.ClassSpells
	if CS then
		for _, cls in ipairs(CS.CLASSES) do
			local cname
			for _, s in ipairs(CS.Spells(cls, false)) do
				cname = cname or (CS.ClassName and CS.ClassName(cls)) or cls
				for _, r in ipairs(s.ranks) do Add(r[1], s.name, Str(Safe(C_Spell and C_Spell.GetSpellSubtext, r[1])), L["level %d"]:format(r[2]), cname) end
			end
		end
	end
	-- the talents: yours and every other class's
	local tp = ns.providers.talents
	for _, e in ipairs(tp and ns:GetEntries(tp) or {}) do
		if type(e.spellID) == "number" then Add(e.spellID, e.name, nil, L["talent"], e.className) end
	end
	return out
end
SI.Candidates = Candidates -- (tests)

--- The rows for these (lowercase) words: every spell whose name has each of them, each id once, by name then rank.
function SI.ByName(words)
	local seen, rows = {}, {}
	local function Has(name)
		local l = " " .. Lower(name):gsub("'", "") .. " "
		for _, w in ipairs(words) do if not l:find(w, 1, true) then return false end end
		return true
	end
	for _, c in ipairs(Candidates()) do
		local id, name, rank, where, class = c[1], c[2], c[3], c[4], c[5]
		if not seen[id] and Has(name) then
			seen[id] = true
			rows[#rows + 1] = SI.Row(id, name, rank or Subtext(id), where, class)
			rows[#rows]._sort = Lower(name) .. "\0" .. string.format("%04d", tonumber((rank or ""):match("%d+")) or 0)
		end
	end
	-- (a spell the game knows by its name, if none of those had it: one in your spellbook it lists, say)
	if #rows == 0 then
		local info = Safe(C_Spell and C_Spell.GetSpellInfo, table.concat(words, " "))
		local id = type(info) == "table" and info.spellID
		if type(id) == "number" and not ns.Secret(id) then
			rows[1] = SI.Row(id, Str(info.name) or table.concat(words, " "), Subtext(id), nil, nil)
			rows[1]._sort = ""
		end
	end
	table.sort(rows, function(a, b) if a._sort ~= b._sort then return a._sort < b._sort end return a.spellID < b.spellID end)
	return rows
end

--- The row for a spell id, or nil when the game knows none by it.
function SI.ById(id)
	local name = SpellName(id)
	if not name then return nil end
	local class
	for _, c in ipairs(Candidates()) do if c[1] == id then class = c[5] break end end
	local e = SI.Row(id, name, Subtext(id), nil, class)
	local d = Safe(C_Spell and C_Spell.GetSpellDescription, id)
	e.tip = Str(d) and not ns.Secret(d) and d or nil
	return e
end

----------------------------------------------------------------------
-- The question
----------------------------------------------------------------------

local PATTERNS = { "^spell ?ids? of (.+)$", "^spell ?ids? for (.+)$", "^spell ?ids? (.+)$", "^(.+) spell ?ids?$" }

--- "spellid claw", "spell id 1082", "claw spell id": { id = n } or { words = {...} }; nil when the line isn't one.
function SI.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	local what
	for _, p in ipairs(PATTERNS) do
		what = t:match(p)
		if what then break end
	end
	if not what or what == "" then return nil end
	local id = tonumber(what)
	if id then return { id = math.floor(id) } end
	local words = {}
	for w in what:gmatch("%S+") do if w ~= "the" and w ~= "of" and w ~= "for" then words[#words + 1] = w end end
	if #words == 0 then return nil end
	return { words = words, said = what }
end

function SI.Answer(q)
	local NoteRow = ns.NoteRow
	if q.id then
		local e = SI.ById(q.id)
		if not e then return { NoteRow(L["No spell with id %d"]:format(q.id)) }, L["Spell ID"] end
		return ns.ScoreInOrder({ e }), L["Spell ID"] .. SEP .. L["Enter copies it"]
	end
	local rows = SI.ByName(q.words)
	if #rows == 0 then
		return { NoteRow(L["No spell called \"%s\" that Terminal knows"]:format(q.said),
			L["Your spellbook, every class's spells and the talents are looked in"]) }, L["Spell ID"]
	end
	return ns.ScoreInOrder(rows), L["Spell IDs"] .. SEP .. L["Enter copies one"]
end

function SI.ToAdvanced(q)
	return "spellid " .. (q.id and tostring(q.id) or table.concat(q.words, " ")) .. " "
end

--- The spell id a row stands for, for its tooltip's line: a spell's, a talent's, a spell What's Training lists.
function SI.Of(e)
	if type(e) ~= "table" then return nil end
	local k = e.kind
	-- (not @classspell's: its tooltip lists every rank's id already; 0.54.3, the player: "redundant")
	if (k == "spells" or k == "talents" or k == "spellid") and type(e.spellID) == "number" then return e.spellID end
	if k == "training" and not e.isItem and type(e.wtId) == "number" then return e.wtId end
end
