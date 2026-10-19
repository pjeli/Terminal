local ns = select(2, ...)
local L = ns.L

-- The lines you ran from the prompt. Up arrow on an empty prompt walks back through them
-- (UI:Up / UI:Down); .history lists them and .history clear forgets them.

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
	for i = #h, MAX_HISTORY + 1, -1 do h[i] = nil end
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
			return { L["History cleared."] }
		end
		if #h == 0 then return { L["Nothing in the history yet."] } end
		local lines = { L["%s earlier line(s), newest first:"]:format(#h) }
		-- (a "|" as typed, "linen|wool": "||" in chat, else it starts an escape; review, 0.53.6)
		for i, l in ipairs(h) do lines[#lines + 1] = ("  %2d  %s"):format(i, (tostring(l):gsub("|", "||"))) end
		return lines
	end,
})
