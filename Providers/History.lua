local ns = select(2, ...)

-- The lines you ran from the prompt. Up arrow on an empty prompt walks back through them
-- (UI:Up / UI:Down); .history lists them and .history clear forgets them.

local MAX_HISTORY = 50

--- Remember a line run from the prompt (newest first, each once).
function ns:RecordHistory(line)
	if not self.db then return end
	line = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if line == "" then return end
	local h = self.db.history
	if type(h) ~= "table" then h = {}; self.db.history = h end
	for i = #h, 1, -1 do
		if h[i] == line then table.remove(h, i) end
	end
	table.insert(h, 1, line)
	for i = #h, MAX_HISTORY + 1, -1 do h[i] = nil end
end

--- Find a terminal command by name or alias (in registration order, so a shared alias always
--- finds the same one).
function ns:FindCommand(name)
	name = ns.Lower(name)
	if self.commands[name] then return self.commands[name] end
	for _, n in ipairs(self.commandOrder) do
		for _, a in ipairs(self.commands[n].aliases or {}) do
			if ns.Lower(a) == name then return self.commands[n] end
		end
	end
end

ns:RegisterCommand("history", {
	desc = "What you ran from the prompt (Up arrow on an empty prompt walks back through it); .history clear",
	complete = function() return { { "clear", "forget the history" } } end,
	run = function(args)
		local h = ns.db and ns.db.history or {}
		if strtrim(args or ""):lower() == "clear" then
			for i = #h, 1, -1 do h[i] = nil end
			return { "History cleared." }
		end
		if #h == 0 then return { "Nothing in the history yet." } end
		local lines = { #h .. " earlier line(s), newest first:" }
		for i, l in ipairs(h) do lines[#lines + 1] = ("  %2d  %s"):format(i, l) end
		return lines
	end,
})
