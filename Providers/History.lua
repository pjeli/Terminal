local ns = select(2, ...)
local L = ns.L

-- The lines you ran from the prompt. Up arrow on an empty prompt walks back through them
-- (UI:Up / UI:Down); .history lists them and .history clear forgets them. (0.63.6, the player: "like a real shell")
-- Ctrl+R searches them (UI/Modes.lua's history search), @history lists them, and "history" asks for them in plain
-- words; each says when it last ran (db.historyAt).

local MAX_HISTORY = 50

--- Remember a line run from the prompt (newest first, each once).
function ns:RecordHistory(line)
	if not self.db then return end
	line = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if line == "" then return end
	if ns.SecretLine(line) then return end -- (.ssh password: never kept; Terminal: Share)
	local h = self.db.history
	if type(h) ~= "table" then h = {}; self.db.history = h end
	for i = #h, 1, -1 do
		if h[i] == line then table.remove(h, i) end
	end
	table.insert(h, 1, line)
	local at = self.db.historyAt
	if type(at) ~= "table" then at = {}; self.db.historyAt = at end
	for i = #h, MAX_HISTORY + 1, -1 do at[h[i]] = nil; h[i] = nil end
	at[line] = time()
	ns:Changed("history")
end

--- When a line from the history last ran (time()), or nil (kept before 0.63.6).
function ns:HistoryAt(line)
	local at = self.db and self.db.historyAt
	return type(at) == "table" and at[line] or nil
end

--- The history Up walks, newest first: every line, whatever mode ran it. (Until 0.54.3 Simple mode left out what ran
--- in Advanced; a line of Advanced syntax brought back is searched as it is, Simple mode kept since 0.55.9.)
function ns:HistoryLines()
	local h = self.db and self.db.history
	if type(h) ~= "table" then return {} end
	return h
end

--- Find a terminal command by name or alias (in registration order, so a shared alias always
--- finds the same one).

ns:RegisterCommand("history", {
	desc = L["What you ran from the prompt (Up arrow on an empty prompt walks back through it); .history clear"],
	complete = function() return { { "clear", L["forget the history"] } } end,
	run = function(args)
		local h = ns.db and ns.db.history or {}
		if strtrim(args or ""):lower() == "clear" then
			for i = #h, 1, -1 do h[i] = nil end
			if ns.db then ns.db.historyAt = {} end
			ns:Changed("history")
			return { L["History cleared."] }
		end
		if #h == 0 then return { L["Nothing in the history yet."] } end
		local lines = { L["%s earlier line(s), newest first:"]:format(#h) }
		-- (a "|" as typed, "linen|wool": "||" in chat, else it starts an escape; review, 0.53.6)
		for i, l in ipairs(h) do lines[#lines + 1] = ("  %2d  %s"):format(i, (tostring(l):gsub("|", "||"))) end
		return lines
	end,
})

----------------------------------------------------------------------
-- @history, and "history" in plain words (0.63.6)
----------------------------------------------------------------------

local H = {}
ns.History = H
H.ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"

--- Enter on a line from the history (@history, "history"): it's searched again, as if typed (Shift+Left back).
local function SearchAgain(e)
	local UI = ns.UI
	if not (UI and UI.WalkTo) then return end
	UI:WalkTo(e.line, e)
end

--- Rows for the history, newest first: { name = the line, detail = when it ran }.
function H.Rows()
	local out = {}
	for i, line in ipairs(ns:HistoryLines()) do
		local at = ns:HistoryAt(line)
		out[#out + 1] = {
			key = line, name = line, line = line, histPos = i, icon = H.ICON,
			detail = at and ns.Ago(math.max(0, time() - at)) or nil,
			activate = SearchAgain, staysOpen = true,
		}
	end
	return ns.RankInOrder(out)
end

ns:RegisterProvider("history", {
	label = L["History"],
	color = "ff9fd8c8", -- (a pale teal: no other list has it)
	aliases = { "history", "hist", "ran" },
	explicit = true, -- (only asked for: @history, "history", Ctrl+R)
	refreshOnOpen = 60, -- (each row's "when it ran" kept true: made again on an open a minute on; 0.63.7, review)
	collect = function() return H.Rows() end,
})

-- "history", "my history", "search history", "recent searches", "what did i run": the history, newest first
local ASK = {}
for _, l in ipairs({ "history", "my history", "command history", "search history", "terminal history", "recent searches",
	"my searches", "past searches", "previous searches", "previous commands", "recent commands", "what did i run",
	"what did i search", "what have i searched", "what did i search for", "show history", "show my history" }) do ASK[l] = true end

function H.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	return ASK[t] and {} or nil
end

function H.Answer()
	local p = ns.providers.history
	local rows = p and ns:GetEntries(p) or {}
	local list = {}
	for i, e in ipairs(rows) do list[i] = e end
	table.sort(list, function(a, b) return a.histPos < b.histPos end)
	ns.ScoreInOrder(list)
	if #list == 0 then return {}, L["Nothing in the history yet: what you run from the prompt is kept here"] end
	return list, L["What you ran, newest first"] .. ns.DETAIL_SEP .. L["Enter searches it again"] .. ns.DETAIL_SEP .. L["Ctrl+R searches the history"]
end

function H.ToAdvanced() return "@history" end
