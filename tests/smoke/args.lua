-- A command's arguments as rows while you type them (UI:ArgEntries): one of several words ("share on") is matched
-- against all that's typed and runs whole (0.51.5: "share on" matched by its last word ran "share share on").
local T = ...
local ns, UI, check = T.ns, T.UI, T.check

io.write("[args: a command's arguments as rows]\n")
do
	ns:RegisterCommand("argtest", { desc = "test", run = function() end,
		complete = function() return { { "share on", "a" }, { "share off", "b" }, { "probe", "c" } } end })
	local rows = UI:ArgEntries("argtest share on")
	check(rows and rows[1] and rows[1].argLine == "share on", "several words typed: its row runs them whole: "
		.. tostring(rows and rows[1] and rows[1].argLine))
	rows = UI:ArgEntries("argtest share o")
	local lines = {}
	for _, e in ipairs(rows or {}) do lines[#lines + 1] = e.argLine end
	check(table.concat(lines, ",") == "share on,share off", "...part of them: both, each whole (not probe): " .. table.concat(lines, ","))
	ns:UnregisterCommand("argtest")
	-- (one-word arguments as before: the last word typed, after the words before it)
	ns:RegisterCommand("argtest", { desc = "test", run = function() end,
		complete = function() return { "dracula", "nord" } end })
	rows = UI:ArgEntries("argtest x dr")
	check(rows and rows[1] and rows[1].argLine == "x dracula", "one-word arguments: after the words before: "
		.. tostring(rows and rows[1] and rows[1].argLine))
	ns:UnregisterCommand("argtest")
end
