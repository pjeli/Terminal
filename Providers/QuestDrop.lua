local ns = select(2, ...)

-- Quests to drop: "quests to drop" (both modes; Advanced: @quest is:drop, or is:grey / is:leftbehind) lists the quests
-- in your log the game shows grey for your level, and those in zones you've left behind (Quests.lua marks each row:
-- `grey`, `behind`, `complete`, `drop`; complete ones never count: turn them in). Shift+Enter on one has the game ask
-- before dropping it, as the quest log's own Abandon does.
--
-- Several at once: the answer's top row "Drop all N", the right-click menu's "Drop all N quests", or Advanced
-- ">>> drop" after any quest search (">> drop" drops the selected one: the game asks). The game's own dialog asks
-- about one quest at a time, so a group gets Terminal's own confirmation naming every quest (Enter drops them, Esc
-- keeps them); then each is dropped as the game's dialog would (C_QuestLog.SetAbandonQuest / AbandonQuest: C calls,
-- not protected on this client), a moment apart, and a chat line says which went.

local QD = {}
ns.QuestDrop = QD

local Lower = ns.Lower
local Call = ns.Safe

----------------------------------------------------------------------
-- The question
----------------------------------------------------------------------

-- a line of these words, "quest(s)" and a word that asks for ones to drop among them; any other words narrow the
-- answer by the quest's name, zone and text ("westfall quests to drop")
local ASK = {}
for w in ([[to i can could should would which what my the show list all me in log questlog quest log that are is am
	have ive gone for level levels lvl my of a an up any some do now still please help get rid off clean these those
	from zone zones left low here there ones one theyre them it its more]]):gmatch("%a+") do ASK[w] = true end
local SUBJECT = { quest = true, quests = true }
-- what the word asks for: any to drop, grey ones, or those in zones left behind
local CUE = { drop = "all", abandon = "all", dump = "all", remove = "all", delete = "all", cleanup = "all", clean = "all",
	old = "all", droppable = "all", grey = "grey", gray = "grey", trivial = "grey", behind = "behind",
	outleveled = "behind", outlevelled = "behind", outgrown = "behind" }

--- The question: { words = the words that narrow it, grey = only grey ones, behind = only zones left behind }, or
--- nil when the line isn't it.
function QD.Question(text)
	if type(text) ~= "string" or text:find("[@:>|]") or text:find("^%s*[%./]") then return nil end
	local t = Lower(text):gsub("'", ""):gsub("[%p]", " ")
	local subject, cues, rest = false, {}, {}
	for w in t:gmatch("%S+") do
		if SUBJECT[w] then subject = true
		elseif CUE[w] then cues[CUE[w]] = true
		elseif not ASK[w] then rest[#rest + 1] = w end
	end
	if not subject or not next(cues) then return nil end
	local only = not cues.all
	return { words = rest, grey = only and cues.grey and not cues.behind or nil, behind = only and cues.behind and not cues.grey or nil }
end

----------------------------------------------------------------------
-- The answer
----------------------------------------------------------------------

local function Matches(e, words)
	if not words or #words == 0 then return true end
	local hay = (rawget(e, "_lname") or Lower(e.name or "")) .. " " .. (rawget(e, "_ltext") or Lower(e.zone or ""))
	for _, w in ipairs(words) do if not hay:find(w, 1, true) then return false end end
	return true
end

-- grey first, then the lowest level, then by name
local function Order(a, b)
	if (a.grey and true or false) ~= (b.grey and true or false) then return a.grey and true or false end
	local la, lb = a.level or 0, b.level or 0
	if la ~= lb then return la < lb end
	return tostring(a.name) < tostring(b.name)
end

--- The rows a group drop takes from a list: quests in your log, each once; `explicit` (">>> drop": the player named
--- them) takes any that isn't complete, else only those to drop. The second result: how many complete ones were left.
function QD.GroupRows(list, explicit)
	local out, seen, kept = {}, {}, 0
	for _, e in ipairs(list or {}) do
		local o = type(e) == "table" and (rawget(e, "pipeOf") or e) or nil
		if o and o.kind == "quests" and type(o.questID) == "number" and not seen[o.questID] then
			seen[o.questID] = true
			if o.complete then kept = kept + 1
			elseif o.drop or explicit then out[#out + 1] = o end
		end
	end
	return out, kept
end

local function DropAllRow(rows)
	local list = {}
	for i, e in ipairs(rows) do list[i] = e end
	return {
		name = ("Drop all %d"):format(#list), kind = "dropall", kindLabel = "|cffffd200quests|r", raw = true, lead = true,
		icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", detail = "you'll see them all and be asked first",
		actionVerb = "drop them all", activate = function() QD.Confirm(list) end, _pos = ns.UI and ns.UI.NO_POS or {},
	}
end

QD.NOTE = "Quests to drop: grey, or in a zone you've left behind"
QD.NOTE_GREY = "Grey quests"
QD.NOTE_BEHIND = "Quests in zones you've left behind"

--- The answer: the quests to drop (or only the grey ones, or only those in zones left behind), narrowed by the
--- question's other words, grey first and then by level; "Drop all N" on top when there are two or more. The note.
function QD.Answer(q)
	q = q or {}
	local p = ns.providers.quests
	local rows, kept = {}, 0
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		local which = (q.grey and e.grey) or (q.behind and e.behind) or (not q.grey and not q.behind and (e.grey or e.behind))
		if which and Matches(e, q.words) then
			if e.complete then kept = kept + 1 else rows[#rows + 1] = e end
		end
	end
	table.sort(rows, Order)
	for i, e in ipairs(rows) do e._score = 1e6 - i end
	local note = (q.grey and QD.NOTE_GREY) or (q.behind and QD.NOTE_BEHIND) or QD.NOTE
	if #rows == 0 then
		note = (kept > 0 and "Nothing to drop: the only ones are complete, turn them in")
			or ((q.words and #q.words > 0) and "None of those quests is one to drop")
			or (q.grey and "No grey quests in your log") or (q.behind and "No quests in zones you've left behind")
			or "Nothing to drop: no grey quests, none in zones you've left behind"
	else
		if kept > 0 then note = note .. ("  ·  %d complete left out: turn %s in"):format(kept, kept == 1 and "it" or "them") end
		if #rows >= 2 then
			local top = DropAllRow(rows)
			top._score = 2e6
			table.insert(rows, 1, top)
		end
	end
	return rows, note
end

----------------------------------------------------------------------
-- Dropping several: Terminal's confirmation, then the game drops each
----------------------------------------------------------------------

QD.STEP = 0.15 -- (s between two quests dropped)
QD.SHOW_MAX = 12 -- (names the confirmation lists; the rest are counted)
QD.ENTER_WAIT = 0.4 -- (s an Enter is ignored after the confirmation shows: a held key's repeats don't answer it)

--- Drops one quest the way the game's dialog does once you say yes (its selection put back after). False when it's no
--- longer in your log, or the game refused.
function QD.DropOne(id)
	local Q = C_QuestLog
	if not (Q and Q.SetAbandonQuest and Q.AbandonQuest and Q.SetSelectedQuest) then return false end
	if Q.GetLogIndexForQuestID and not Call(Q.GetLogIndexForQuestID, id) then return false end
	local before = Q.GetSelectedQuest and Call(Q.GetSelectedQuest)
	local ok = ns.Guarded("abandonquest", function()
		Q.SetSelectedQuest(id)
		Q.SetAbandonQuest()
		Q.AbandonQuest()
	end)
	if type(before) == "number" and before ~= id then pcall(Q.SetSelectedQuest, before) end
	return ok and true or false
end

--- Drops every quest in `list` ({ { questID, name } }), one each QD.STEP; says in chat which went.
function QD.DropAll(list)
	local gone, failed = {}, {}
	local i = 0
	local function Step()
		i = i + 1
		local q = list[i]
		if not q then
			local lines = {}
			if #gone > 0 then lines[#lines + 1] = ("Dropped %d quest%s: %s"):format(#gone, #gone == 1 and "" or "s", table.concat(gone, ", ")) end
			if #failed > 0 then lines[#lines + 1] = ("Not dropped (no longer in your log, or the game refused): %s"):format(table.concat(failed, ", ")) end
			ns:Trace(("quests: dropped %d of %d"):format(#gone, #list))
			ns:Output(lines)
			return
		end
		if QD.DropOne(q.questID) then gone[#gone + 1] = q.name else failed[#failed + 1] = q.name end
		C_Timer.After(QD.STEP, Step)
	end
	Step()
end

local dialog, pending
local app = {}
function app.IsShown() return dialog and dialog:IsShown() or false end
function app.Close(why)
	if dialog and dialog:IsShown() then
		dialog:Hide()
		pending = nil
		if why == "combat" then ns:Print("Dropping quests: closed, combat started. Nothing was dropped.") end
	end
end
QD.app = app -- (tests)

local function Decide(yes)
	local list = pending
	pending = nil
	if dialog then dialog:Hide() end
	if yes and list and #list > 0 then QD.DropAll(list) end
end
QD.Decide = Decide -- (tests: as Enter / Esc would)

local function Button(parent, label, x, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(170, 24)
	b:SetPoint("BOTTOM", parent, "BOTTOM", x, 14)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

QD.CONFIRM_W = 460

--- The confirmation for dropping several quests (`rows`: quest log rows): it names them all (QD.SHOW_MAX, then a
--- count), Enter or "Drop them" drops them, Esc or "Keep them" keeps them. Not in combat.
function QD.Confirm(rows)
	local P = ns.Panel
	local list = {}
	for _, e in ipairs(rows or {}) do
		if type(e.questID) == "number" then list[#list + 1] = { questID = e.questID, name = tostring(e.name) } end
	end
	if #list == 0 then ns:Print("Nothing to drop.") return end
	if not (P and P.CanOpen("In combat: drop them once the fight is over.")) then return end
	if not dialog then
		dialog = P.Build("TerminalDropQuests", app)
		dialog.title = P.Text(dialog, 15, "CENTER")
		dialog.title:SetPoint("TOP", 0, -14)
		dialog.body = dialog:CreateFontString(nil, "OVERLAY")
		dialog.body:SetFontObject(ns.Theme.fonts.small)
		dialog.body:SetJustifyH("LEFT")
		dialog.body:SetWordWrap(true)
		dialog.body:SetPoint("TOP", 0, -40)
		dialog.body:SetWidth(QD.CONFIRM_W - 40)
		dialog.yes = Button(dialog, "Drop them", -92, function() Decide(true) end)
		dialog.no = Button(dialog, "Keep them", 92, function() Decide(false) end)
		dialog:SetScript("OnKeyDown", function(_, key)
			if key == "ENTER" then
				if GetTime() - (dialog.shownAt or 0) >= QD.ENTER_WAIT then Decide(true) end
			elseif key == "ESCAPE" or key == "`" then Decide(false) end
		end)
	end
	pending = list
	P.Opening(app)
	local t = P.Layout(dialog)
	dialog.title:SetText(("|cff%sDrop %d quest%s?|r"):format(t.text, #list, #list == 1 and "" or "s"))
	local names = {}
	for i = 1, math.min(#list, QD.SHOW_MAX) do names[i] = list[i].name end
	local more = #list - #names
	dialog.body:SetText(("|cff%s%s%s.\n\nThey go from your quest log at once: the game won't ask again for each.|r"):format(t.dim,
		table.concat(names, ", "), more > 0 and (", +" .. more .. " more") or ""))
	local h = dialog.body:GetStringHeight()
	h = type(h) == "number" and h > 0 and h or 42
	dialog:SetSize(QD.CONFIRM_W, math.floor(40 + h + 14 + 24 + 14 + 4))
	dialog.shownAt = GetTime()
	dialog:Show()
	ns:Trace(("quests: asked to drop %d"):format(#list))
end

--- The confirmation's list while it shows (tests), else nil.
function QD.Pending() return pending end
