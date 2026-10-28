-- (Terminal Extras, a load-on-demand addon of its own: Terminal's namespace is its public table, _G.Terminal)
local ns = _G.Terminal
if not ns then return end
local L = ns.L

-- The console's shell, tsh (.console, branch console-dev): a line is read as a Unix shell reads one (words, 'quotes',
-- "quotes", \ escapes, globs, | pipes, ; && ||, > and >> into /tmp, # comments, !! and !N), each command is one of the
-- shell's own (ls, cd, cat, grep, find, sort, uniq...) or any of Terminal's (.snake, .wowamp, .atop..., with or without
-- the dot), and every stage hands the next its lines. The console (Console.lua) runs a line in a coroutine and gives
-- the shell a frame's time at a time: `sh:Check()` yields when that's spent, `sh:Sleep(s)` waits; a test runs a line
-- straight through (`sh.yieldable` unset).

local FS = ns.ConsoleFS
local SH = {}
ns.Shell = SH

SH.CANCEL = "\1cancelled"
SH.HISTORY_MAX = 300

-- the console's colours (a dark terminal of its own, whatever Terminal's theme)
SH.C = {
	text = "d5dbe6", dim = "6b7387", green = "9ece6a", blue = "7aa2f7", cyan = "7dcfff", yellow = "e0af68",
	magenta = "bb9af7", red = "f7768e", orange = "ff9e64", white = "ffffff",
}
local C = SH.C
local function Paint(color, s) return "|cff" .. C[color] .. tostring(s) .. "|r" end
SH.Paint = Paint
local Strip = FS.Strip
local Lower = ns.Lower

--- Text shown as it is: a "|" doubled (the game reads one as an escape).
function SH.Literal(s) return (tostring(s or ""):gsub("|", "||")) end

--- A line carrying a password (ssh password ..., share join ...: Terminal's ns.SecretLine): never kept, never shown.
function SH.Secret(line) return ns.SecretLine ~= nil and ns.SecretLine(line) end
--- The line as it's shown: a password as *s, one a byte (the caret and the colours stay where they were).
function SH.Masked(line) return ns.MaskSecret and ns.MaskSecret(line) or line end

----------------------------------------------------------------------
-- Reading a line
----------------------------------------------------------------------

--- The line's tokens: { t = "word" | "op" | "comment", v = the word as meant, s, e = where it is in the line, quoted,
--- glob (an unquoted * ? [), open (a quote never closed) }.
function SH.Lex(line)
	local toks, i, n = {}, 1, #line
	while i <= n do
		local c = line:sub(i, i)
		local two = line:sub(i, i + 1)
		if c:match("%s") then
			i = i + 1
		elseif two == "||" or two == "&&" or two == ">>" then
			toks[#toks + 1] = { t = "op", v = two, s = i, e = i + 1 }
			i = i + 2
		elseif c == "|" or c == ";" or c == ">" then
			toks[#toks + 1] = { t = "op", v = c, s = i, e = i }
			i = i + 1
		elseif c == "#" then
			toks[#toks + 1] = { t = "comment", v = line:sub(i), s = i, e = n }
			break
		else
			local s, buf, quoted, glob, open = i, {}, false, false, false
			while i <= n do
				c = line:sub(i, i)
				if c == "\\" and i < n then
					buf[#buf + 1] = line:sub(i + 1, i + 1)
					quoted = true
					i = i + 2
				elseif c == "'" or c == '"' then
					quoted = true
					local j = line:find(c, i + 1, true)
					if not j then
						buf[#buf + 1] = line:sub(i + 1)
						open = c
						i = n + 1
					else
						buf[#buf + 1] = line:sub(i + 1, j - 1)
						i = j + 1
					end
				-- (a > inside a word is the word's: where dist>200; > /tmp/x needs the space before it)
				elseif c:match("%s") or c == "|" or c == ";" or line:sub(i, i + 1) == "&&" then
					break
				else
					if c == "*" or c == "?" or c == "[" then glob = true end
					buf[#buf + 1] = c
					i = i + 1
				end
			end
			toks[#toks + 1] = { t = "word", v = table.concat(buf), s = s, e = i - 1, quoted = quoted, glob = glob, open = open }
		end
	end
	return toks
end

--- The line as commands: a list of { pipeline = { { words = {tokens}, out = token, append } ... }, op = what follows
--- (";", "&&", "||" or nil) }; or nil and what's wrong.
function SH.Parse(line)
	local toks = SH.Lex(line)
	local list, pipeline, cmd = {}, {}, { words = {} }
	local i = 1
	local function EndCmd()
		if #cmd.words == 0 then return false end
		pipeline[#pipeline + 1] = cmd
		cmd = { words = {} }
		return true
	end
	while i <= #toks do
		local t = toks[i]
		if t.t == "word" then
			cmd.words[#cmd.words + 1] = t
		elseif t.t == "op" then
			if t.v == ">" or t.v == ">>" then
				local target = toks[i + 1]
				if not (target and target.t == "word") then return nil, L["syntax error near unexpected token `newline'"] end
				cmd.out, cmd.append = target, t.v == ">>"
				i = i + 1
			elseif t.v == "|" then
				if not EndCmd() then return nil, L["syntax error near unexpected token `|'"] end
			else
				if not EndCmd() then
					if #pipeline == 0 then return nil, L["syntax error near unexpected token `%s'"]:format(t.v) end
				end
				list[#list + 1] = { pipeline = pipeline, op = t.v }
				pipeline = {}
			end
		end
		i = i + 1
	end
	if #cmd.words > 0 then pipeline[#pipeline + 1] = cmd
	elseif #pipeline > 0 then return nil, L["syntax error near unexpected token `|'"] end
	if #pipeline > 0 then list[#list + 1] = { pipeline = pipeline } end
	return list
end

----------------------------------------------------------------------
-- A session: where you are, what you typed, where the output goes
----------------------------------------------------------------------

local Session = {}
Session.__index = Session

--- A new session. `opts`: print(line), clear(), ui (the console's: Split, ClosePane, Layout, Panes, Kill...),
--- history (a list shared between sessions).
function SH.Session(opts)
	opts = opts or {}
	local sh = setmetatable({
		cwd = "/", prevCwd = "/",
		history = opts.history or {},
		print = opts.print or function() end,
		clear = opts.clear or function() end,
		ui = opts.ui,
		yieldable = false,
	}, Session)
	return sh
end

function Session:Print(line)
	line = tostring(line or "")
	if line:find("\n", 1, true) then
		for part in (line .. "\n"):gmatch("(.-)\n") do self.print(part) end
	else
		self.print(line)
	end
end
function Session:Error(line) self:Print(Paint("red", line)) end

--- Gives the console its frame back when this one's time is spent (only inside the console's coroutine); stops
--- here when Ctrl+C was pressed.
function Session:Check()
	if self.cancelled then error(SH.CANCEL, 0) end
	if self.yieldable and debugprofilestop and debugprofilestop() > (self.deadline or 0) then
		coroutine.yield()
		if self.cancelled then error(SH.CANCEL, 0) end
	end
end

--- Waits `seconds` (frames go by; in a test, nothing waits).
function Session:Sleep(seconds)
	if not self.yieldable then return end
	local untilT = GetTime() + (tonumber(seconds) or 0)
	repeat
		coroutine.yield()
		if self.cancelled then error(SH.CANCEL, 0) end
	until GetTime() >= untilT
end

function Session:Wait() return function(s) self:Sleep(s) end end

function Session:Remember(line)
	local h = self.history
	if line:match("^%s") or line == "" then return end -- (a line starting with a space isn't kept, as bash's ignorespace)
	if SH.Secret(line) then return end
	if h[#h] ~= line then h[#h + 1] = line end
	while #h > SH.HISTORY_MAX do table.remove(h, 1) end
end

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------

SH.CMDS = {}
SH.TERMINAL_NAMES = { top = "atop", htop = "atop" } -- (Linux's word for one of Terminal's commands)
SH.ALIASES = {}
SH.ORDER = {}

--- A shell command: def = { run = function(io) -> status, desc, usage, man = { lines }, aliases, args = "path" | "cmd" }.
function SH.Command(name, def)
	def.name = name
	SH.CMDS[name] = def
	SH.ORDER[#SH.ORDER + 1] = name
	for _, a in ipairs(def.aliases or {}) do SH.ALIASES[a] = name end
end

--- What the console records (its history, the panes kept over a /reload, the folders z knows), kept in the cache file
--- (ns.db.consoleData: Core/Saved.lua's "console" part); db.console keeps only its settings. Records kept in
--- db.console before 0.67.8 are moved over.
function SH.Data()
	local db = ns.db
	if not db then return nil end
	local d = type(db.consoleData) == "table" and db.consoleData or {}
	db.consoleData = d
	local old = type(rawget(db, "console")) == "table" and rawget(db, "console") or nil
	if old then
		for _, k in ipairs({ "history", "session", "z" }) do
			if old[k] ~= nil then
				if d[k] == nil then d[k] = old[k] end
				old[k] = nil
			end
		end
	end
	return d
end

--- Your aliases (alias name='text'), kept between sessions: lowercase name -> text.
function SH.Aliases()
	local db = ns.db
	if not db then return {} end
	db.console = type(db.console) == "table" and db.console or {}
	db.console.aliases = type(db.console.aliases) == "table" and db.console.aliases or {}
	return db.console.aliases
end

--- The line with each command's first word that is an alias (not quoted) replaced by its text, as bash does: the
--- words after it stay, so "alias near='ls -lN /npc | where'" then "near title~reagent". An alias's own first word is
--- not read again as itself (alias ls='ls -l').
function SH.ExpandAliases(line)
	local aliases = SH.Aliases()
	if next(aliases) == nil then return line end
	local used = {}
	for _ = 1, 5 do
		local toks = SH.Lex(line)
		local hits = {}
		for i, t in ipairs(toks) do
			local prev = toks[i - 1]
			local first = not prev or (prev.t == "op" and prev.v ~= ">" and prev.v ~= ">>")
			local name = t.t == "word" and first and not t.quoted and Lower(t.v)
			if name and aliases[name] and not used[name] then hits[#hits + 1] = t end
		end
		if #hits == 0 then break end
		for i = #hits, 1, -1 do
			local t = hits[i]
			line = line:sub(1, t.s - 1) .. aliases[Lower(t.v)] .. line:sub(t.e + 1)
		end
		for _, t in ipairs(hits) do used[Lower(t.v)] = true end
	end
	return line
end

--- What a command word runs: an alias, the shell's command (def), or Terminal's (`terminal = c`), or nil. A leading "."
--- asks for Terminal's first; "/bin/x" is x. `noAlias`: not an alias (they're read into the line before it runs).
function SH.Find(word, noAlias)
	word = tostring(word or ""):gsub("^/bin/", "")
	local lw = Lower(word)
	local alias = not noAlias and SH.Aliases()[lw]
	if alias then return { name = lw, alias = alias, desc = L["alias for: "] .. alias } end
	local dotted = lw:sub(1, 1) == "."
	if dotted then lw = lw:sub(2) end
	if not dotted then
		local own = SH.CMDS[lw] or SH.CMDS[SH.ALIASES[lw] or ""]
		if own then return own end
	end
	local c = lw ~= "" and ns.FindCommand and ns:FindCommand(SH.TERMINAL_NAMES[lw] or lw)
	if c then return { name = c.name, terminal = c, desc = c.desc } end
	if dotted then return SH.CMDS[lw] or SH.CMDS[SH.ALIASES[lw] or ""] end
	return nil
end

--- Every command, shell's and Terminal's, for /bin, help and Tab: { name, desc, terminal }.
function SH.AllCommands()
	local out, seen = {}, {}
	for _, n in ipairs(SH.ORDER) do
		if not SH.CMDS[n].hidden then out[#out + 1] = { name = n, desc = SH.CMDS[n].desc } end
		seen[n] = true
	end
	for _, n in ipairs(ns.commandOrder or {}) do
		local c = ns.commands[n]
		if c and not seen[n] then out[#out + 1] = { name = n, desc = c.desc, terminal = c } end
		seen[n] = true
	end
	for n, text in pairs(SH.Aliases()) do
		if not seen[n] then out[#out + 1] = { name = n, desc = L["alias for: "] .. text, alias = text } end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end
FS.Commands = SH.AllCommands

----------------------------------------------------------------------
-- Options
----------------------------------------------------------------------

--- Reads a command's options. `spec`: letters that are switches, a letter followed by ":" takes a value ("n:").
--- `long`: { ["--count"] = "c" }. "-5" gives opts.number = 5 when `numbers` is set. Returns opts, the other words, or
--- nil and the error.
function SH.Opts(args, spec, long, numbers)
	local takes, flag = {}, {}
	for letter, colon in spec:gmatch("(%a)(:?)") do
		if colon == ":" then takes[letter] = true else flag[letter] = true end
	end
	local opts, rest, i = {}, {}, 1
	while i <= #args do
		local a = args[i]
		if a == "--" then
			for j = i + 1, #args do rest[#rest + 1] = args[j] end
			break
		elseif long and long[a] then
			local letter = long[a]
			if takes[letter] then opts[letter] = args[i + 1]; i = i + 1 else opts[letter] = true end
		elseif numbers and a:match("^%-%d+$") then
			opts.number = tonumber(a:sub(2))
		elseif a:match("^%-%a") then
			local j = 2
			while j <= #a do
				local letter = a:sub(j, j)
				if takes[letter] then
					local v = a:sub(j + 1)
					if v == "" then v = args[i + 1]; i = i + 1 end
					if v == nil then return nil, L["option requires an argument -- '%s'"]:format(letter) end
					opts[letter] = v
					break
				elseif flag[letter] then
					opts[letter] = true
				else
					return nil, L["invalid option -- '%s'"]:format(letter)
				end
				j = j + 1
			end
		else
			rest[#rest + 1] = a
		end
		i = i + 1
	end
	return opts, rest
end

----------------------------------------------------------------------
-- Patterns (grep, sed): the regular expressions people type, as Lua patterns
----------------------------------------------------------------------

--- A pattern's letters lower case (not a %-class's letter: %S stays %S).
local function LowerPattern(p)
	local out, i = {}, 1
	while i <= #p do
		local c = p:sub(i, i)
		if c == "%" then out[#out + 1] = p:sub(i, i + 1); i = i + 2
		else out[#out + 1] = Lower(c); i = i + 1 end
	end
	return table.concat(out)
end

local CLASSES = { d = "%d", D = "%D", w = "[%w_]", W = "[^%w_]", s = "%s", S = "%S" }

--- One alternative of a regular expression as a Lua pattern.
local function RegexToLua(re)
	local out, i, n, inSet = {}, 1, #re, false
	while i <= n do
		local c = re:sub(i, i)
		if c == "\\" and i < n then
			local x = re:sub(i + 1, i + 1)
			if CLASSES[x] then
				local cls = CLASSES[x]
				if inSet then cls = cls:gsub("^%[(.*)%]$", "%1") end
				out[#out + 1] = cls
			elseif x == "b" then out[#out + 1] = inSet and "" or "%f[%w_]"
			elseif x:match("%p") then out[#out + 1] = "%" .. x
			else out[#out + 1] = x end
			i = i + 2
		else
			if inSet then
				if c == "]" then inSet = false; out[#out + 1] = c
				elseif c == "%" then out[#out + 1] = "%%"
				else out[#out + 1] = c end
			elseif c == "[" then inSet = true; out[#out + 1] = c
				if re:sub(i + 1, i + 1) == "^" then out[#out + 1] = "^"; i = i + 1 end
			elseif c == "%" or c == "-" then out[#out + 1] = "%" .. c
			elseif c == "{" or c == "}" then out[#out + 1] = "%" .. c
			else out[#out + 1] = c end
			i = i + 1
		end
	end
	return table.concat(out)
end

--- Splits a regular expression at its top-level "|" (and "\|", as grep's basic syntax writes it).
local function Alternatives(re)
	local parts, buf, depth, i = {}, {}, 0, 1
	while i <= #re do
		local c = re:sub(i, i)
		if c == "\\" and re:sub(i + 1, i + 1) == "|" and depth == 0 then
			parts[#parts + 1] = table.concat(buf); buf = {}; i = i + 2
		elseif c == "\\" then buf[#buf + 1] = re:sub(i, i + 1); i = i + 2
		else
			if c == "[" then depth = depth + 1 elseif c == "]" and depth > 0 then depth = depth - 1 end
			if c == "|" and depth == 0 then parts[#parts + 1] = table.concat(buf); buf = {}
			else buf[#buf + 1] = c end
			i = i + 1
		end
	end
	parts[#parts + 1] = table.concat(buf)
	return parts
end

--- A matcher for `pattern`: function(text) -> start, end (in the text) or nil. `how`: fixed (no regular expression),
--- ignore (case), case (match case even without a capital: else a pattern with no capital ignores case, "smart case"),
--- word (whole words).
function SH.Matcher(pattern, how)
	how = how or {}
	local ignore = how.ignore or (not how.case and not pattern:find("%u"))
	local pats = {}
	if how.fixed then
		local p = pattern:gsub("%p", "%%%0")
		pats[1] = p
	else
		for _, alt in ipairs(Alternatives(pattern)) do
			local p = RegexToLua(alt)
			if not pcall(string.find, "", p) then p = alt:gsub("%p", "%%%0") end -- (not one: its letters as typed)
			pats[#pats + 1] = p
		end
	end
	for i, p in ipairs(pats) do
		if ignore then p = LowerPattern(p) end
		if how.word then p = "%f[%w_]" .. p .. "%f[^%w_]" end
		pats[i] = p
	end
	return function(text)
		local hay = ignore and Lower(text) or text
		local bs, be
		for _, p in ipairs(pats) do
			local ok, s, e = pcall(string.find, hay, p)
			if ok and s and e >= s - 1 and (not bs or s < bs) then bs, be = s, e end
		end
		return bs, be
	end
end

--- A line with what matched painted red: on its plain text, the codes kept up to the match (after it, plain colours).
local function Mark(line, s, e)
	local plain = Strip(line)
	local hidden = line:match("|Htsh:.-|h|h") -- (an ls -l line's columns, kept: where and field read them after grep)
	if hidden then return hidden .. Mark(plain, s, e) end
	if plain == line then
		return SH.Literal(line:sub(1, s - 1)) .. Paint("red", SH.Literal(line:sub(s, e))) .. SH.Literal(line:sub(e + 1))
	end
	return SH.Literal(plain:sub(1, s - 1)) .. Paint("red", SH.Literal(plain:sub(s, e))) .. SH.Literal(plain:sub(e + 1))
end
SH.Mark = Mark

----------------------------------------------------------------------
-- Running a line
----------------------------------------------------------------------

--- !! and !N and !word: a line from the history. Returns the line, and whether it changed. Only a ! starting a word,
--- and never inside single quotes: "where dist!=50" and "grep '!x'" stay as they are.
function SH.Expand(sh, line)
	local h = sh.history
	if not line:find("!", 1, true) then return line, false end
	local out, i, n, changed, quote = {}, 1, #line, false, false
	while i <= n do
		local c = line:sub(i, i)
		if quote then
			if c == "'" then quote = false end
			out[#out + 1] = c
			i = i + 1
		elseif c == "'" then
			quote = true
			out[#out + 1] = c
			i = i + 1
		elseif c == "\\" then
			out[#out + 1] = line:sub(i, i + 1)
			i = i + 2
		elseif c == "!" and (i == 1 or line:sub(i - 1, i - 1):match("[%s;|&]")) then
			local bang, word = line:match("^!(!?)(%-?%w*)", i)
			local got
			if bang == "!" then
				got = h[#h]
				if word ~= "" then got = got and (got .. word) end
			elseif word:match("^%-?%d+$") then
				local k = tonumber(word)
				got = k < 0 and h[#h + 1 + k] or h[k]
			elseif word ~= "" then
				for j = #h, 1, -1 do if h[j]:sub(1, #word) == word then got = h[j] break end end
			end
			if got then
				out[#out + 1] = got
				changed = true
				i = i + 1 + #bang + #word
			else
				out[#out + 1] = c
				i = i + 1
			end
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
	return table.concat(out), changed
end

--- The words of a command as strings, globs turned into the paths they match ("cat /item/linen*"; none: as typed).
function SH.Words(sh, tokens)
	local out = {}
	for _, t in ipairs(tokens) do
		if t.glob and not t.quoted then
			local hits = SH.Glob(sh, t.v)
			if #hits > 0 then for _, h in ipairs(hits) do out[#out + 1] = h end
			else out[#out + 1] = t.v end
		else
			out[#out + 1] = t.v
		end
	end
	return out
end

--- The paths a glob matches: its last part's (* ? [ ]) in the folder before it; a glob in a list's name (/*/x) looks
--- in every list's top folder.
function SH.Glob(sh, word)
	local parts = FS.Parts(sh.cwd, word)
	local absolute = word:sub(1, 1) == "/" or word:sub(1, 1) == "~"
	local prefix = absolute and "" or nil
	local out = {}
	local function Match(folder, pat)
		for _, n in ipairs(folder.dirNames) do if FS.GlobMatch(pat, n) then out[#out + 1] = folder.path .. "/" .. n end end
		for _, n in ipairs(folder.files.names) do if FS.GlobMatch(pat, n) then out[#out + 1] = folder.path .. "/" .. n end end
	end
	if #parts == 1 then
		local pat = FS.GlobPattern(parts[1])
		for _, d in ipairs((FS.Dirs())) do
			if FS.GlobMatch(pat, d.name) then out[#out + 1] = "/" .. d.name end
		end
	elseif #parts == 2 and FS.HasGlob(parts[1]) then
		local dirPat, pat = FS.GlobPattern(parts[1]), FS.GlobPattern(parts[2])
		for _, d in ipairs((FS.Dirs())) do
			if FS.GlobMatch(dirPat, d.name) then
				local top = FS.Resolve("/", "/" .. d.name)
				if top then Match(top.folder, pat) end
			end
		end
	elseif #parts >= 2 then
		local before = {}
		for i = 1, #parts - 1 do before[i] = parts[i] end
		local node = FS.Resolve("/", FS.Join(before))
		local folder = node and (node.kind == "dir" and node.folder or node.own)
		if folder then Match(folder, FS.GlobPattern(parts[#parts])) end
	end
	-- written relative, given back relative to where you are (as bash does)
	if not prefix and sh.cwd ~= "/" then
		local here = sh.cwd .. "/"
		for i, p in ipairs(out) do
			if p:sub(1, #here) == here then out[i] = p:sub(#here + 1) end
		end
	elseif not prefix then
		for i, p in ipairs(out) do out[i] = p:sub(2) end
	end
	return out
end

--- Runs fn(...) with what Terminal prints to chat (ns:Output, ns:Print) caught instead: the lines, ok, fn's result.
function SH.Capture(fn, ...)
	local captured = {}
	local outF, printF = ns.Output, ns.Print
	ns.Output = function(_, lines)
		if type(lines) ~= "table" then return end
		for _, l in ipairs(lines) do captured[#captured + 1] = tostring(l) end
	end
	ns.Print = function(_, ...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		captured[#captured + 1] = table.concat(parts, " ")
	end
	local ok, ret = pcall(fn, ...)
	ns.Output, ns.Print = outF, printF
	return captured, ok, ret
end

local function RunTerminal(io, c)
	local args = table.concat(io.args, " ")
	if c.secure then
		io.err(L["it's pressed by the game: run it from Terminal (`), not the console"])
		return 1
	end
	local captured, ok, ret = SH.Capture(c.run, args, ns)
	if ok and type(ret) == "table" then
		for _, l in ipairs(ret) do captured[#captured + 1] = tostring(l) end
	end
	for _, l in ipairs(captured) do io.out(l) end
	if io.sh.ui and io.sh.ui.Launched then io.sh.ui.Launched(io.sh) end
	if not ok then io.err(tostring(ret)) return 1 end
	return 0
end

--- Runs one command (its words as strings). `io`: stdin (lines or nil), out(line), sh. The command's status.
function SH.RunWords(sh, words, stdin, out)
	local name = words[1]
	local args = {}
	for i = 2, #words do args[#args + 1] = words[i] end
	local io = { sh = sh, args = args, stdin = stdin, out = out, name = name }
	io.err = function(msg) sh:Error(tostring(name) .. ": " .. tostring(msg)) end
	-- (aliases were put in the line before it was read; one reached here (xargs near) is the command it shadows, if any)
	local def = SH.Find(name, true)
	if not def then
		if SH.Aliases()[Lower(tostring(name or ""))] then
			sh:Error(L["tsh: %s: an alias, read only where a line is typed (xargs runs commands)"]:format(SH.Literal(name)))
			return 127
		end
		sh:Error(L["tsh: %s: command not found"]:format(SH.Literal(name)))
		return 127
	end
	if def.terminal then return RunTerminal(io, def.terminal) end
	local status = def.run(io)
	return tonumber(status) or 0
end

--- Where a > goes: /tmp only (the rest of this world is read-only).
local function WriteTarget(sh, word)
	local parts = FS.Parts(sh.cwd, word)
	if #parts == 2 and Lower(parts[1]) == "tmp" then return parts[2] end
	if #parts == 1 and sh.cwd == "/tmp" then return parts[1] end
	return nil
end

function SH.Write(name, lines, append)
	local key = Lower(name)
	local f = FS.tmp[key]
	if not f or not append then f = { name = name, lines = {} } FS.tmp[key] = f end
	for _, l in ipairs(lines) do f.lines[#f.lines + 1] = l end
end

local function RunPipeline(sh, pipeline)
	local input, status = nil, 0
	for k, cmd in ipairs(pipeline) do
		sh:Check()
		local last = k == #pipeline
		local words = SH.Words(sh, cmd.words)
		local lines = {}
		local out
		if last and not cmd.out then out = function(l) sh:Print(l) end
		else out = function(l) lines[#lines + 1] = l end end
		status = SH.RunWords(sh, words, input, out)
		input = lines
		if last and cmd.out then
			local target = WriteTarget(sh, cmd.out.v)
			if not target then
				sh:Error(L["tsh: %s: Read-only file system (write to /tmp)"]:format(SH.Literal(cmd.out.v)))
				return 1
			end
			SH.Write(target, lines, cmd.append)
		end
	end
	return status
end

--- Runs a line (the console calls this inside its coroutine). Its last status.
function SH.Run(sh, line)
	line = tostring(line or "")
	local expanded, changed = SH.Expand(sh, line)
	if changed then sh:Print(Paint("dim", SH.Literal(SH.Masked(expanded)))) end
	sh:Remember(expanded)
	local list, err = SH.Parse(SH.ExpandAliases(expanded))
	if not list then sh:Error("tsh: " .. err) return 2 end
	local status, prevOp = 0, nil
	local started = GetTime and GetTime()
	for _, item in ipairs(list) do
		local skip = (prevOp == "&&" and status ~= 0) or (prevOp == "||" and status == 0)
		if not skip then status = RunPipeline(sh, item.pipeline) end
		prevOp = item.op
	end
	sh.status = status
	sh.took = started and GetTime() - started or nil
	return status
end

----------------------------------------------------------------------
-- What the commands share
----------------------------------------------------------------------

--- What NPCs sell, read once (Questie's items, every one): the first cat or grep on /npc waits for it.
local function EnsureSold(io, d)
	if FS.sold or not (d and d.p and d.p.id == "npc") or not FS.HasQuestie() then return end
	io.sh:Print(Paint("dim", L["reading what every NPC sells (once a session)..."]))
	FS.BuildSold(function() io.sh:Check() end)
end
SH.EnsureSold = EnsureSold

--- A list's rows (made if they aren't), waiting while the list says it's loading (Questie's NPCs at login), then made
--- again (what it had while loading was only part).
local function FilesOf(io, d)
	local said = false
	for _ = 1, 40 do
		local busy = FS.Busy(d)
		if not busy then break end
		if not io.sh.yieldable then break end
		if not said then io.sh:Print(Paint("dim", L["%s: loading (%s)..."]:format(d.name, SH.Literal(busy)))) said = true end
		io.sh:Sleep(0.25)
	end
	if said and d.p then ns:Changed(d.p.id) end
	return FS.Files(d)
end
SH.FilesOf = FilesOf

--- Resolves a path, waiting first while its list says it's loading (Questie's NPCs at login): a file not there yet
--- may be once it has.
local function Resolve(io, path)
	local node, err = FS.Resolve(io.sh.cwd, path)
	local first = FS.Parts(io.sh.cwd, path)[1]
	local _, by = FS.Dirs()
	local d = first and by[Lower(first)]
	if d and FS.Busy(d) then
		FilesOf(io, d)
		node, err = FS.Resolve(io.sh.cwd, path)
	end
	return node, err
end

--- The folder a node lists: a list's or one of its folders, or a row's own files; nil for a plain file.
local function FolderOf(node)
	if node.kind == "dir" then return node.folder end
	return node.own
end

--- The paths among `args`, with "cat linen cloth" read as one file when its words alone aren't files.
local function PathArgs(io, args)
	if #args > 1 then
		local any = false
		for _, a in ipairs(args) do if FS.Resolve(io.sh.cwd, a) then any = true break end end
		if not any then
			local joined = table.concat(args, " ")
			if FS.Resolve(io.sh.cwd, joined) then return { joined } end
		end
	end
	return args
end

--- A row's name painted in its list's colour (a directory blue, with its "/").
local function Painted(d, name)
	if d and d.p and d.p.color then return "|c" .. d.p.color .. SH.Literal(name) .. "|r" end
	return SH.Literal(name)
end
SH.Painted = Painted
local function DirName(name) return Paint("blue", SH.Literal(name) .. "/") end

--- `text` shown as it is, clickable in the console: a click on it opens `path` (cd into a folder, cat a file), Shift+click
--- pins it. Invisible everywhere else: FS.Strip takes it out, so pipes and chat see only the text.
function SH.Link(path, text)
	if type(path) ~= "string" or path == "" then return text end
	return "|Htshp:" .. path:gsub("|", "") .. "|h" .. text .. "|h"
end
local Link = SH.Link

--- `text` shown as it is, clickable in the console: a click runs `search <words>`.
function SH.SearchLink(words, text)
	return "|Htshs:" .. tostring(words):gsub("|", "") .. "|h" .. text .. "|h"
end

--- A row's game icon as text (the game draws it the height of the line), or "" for none.
function SH.IconText(e)
	local icon = type(e) == "table" and e.icon
	if type(icon) ~= "string" and type(icon) ~= "number" then return "" end
	if icon == "" or icon == 0 then return "" end
	return "|T" .. tostring(icon) .. ":0|t"
end

--- A folder's icon: its own row's (a row that is a directory), else the first file's under it, at any depth.
function SH.FolderIcon(folder)
	if type(folder) ~= "table" then return "" end
	if folder.row then return SH.IconText(folder.row) end
	local found = ""
	FS.EachFolder(folder, function(f)
		local first = f.files and f.files.names[1]
		if first then
			found = SH.IconText(f.files.by[Lower(first)])
			if found ~= "" then return false end
		end
	end)
	return found
end

--- ls --icons: the icon in a cell of its own before the name (the console lines the names up after it; the tab is
--- what parts them, as ls -l's columns).
local function WithIcon(icon, shown) return icon .. "\t" .. shown end

--- A path under a folder ("/" .. name at the root).
local function Under(folderPath, name)
	if folderPath == "/" or folderPath == "" then return "/" .. name end
	return folderPath .. "/" .. name
end

--- The lines a command reads: the files named (their contents), else what was piped in. nil and the error when neither.
local function InputLines(io, files)
	if files and #files > 0 then
		local out = {}
		for _, path in ipairs(PathArgs(io, files)) do
			local node, err = Resolve(io, path)
			if not node then io.err(SH.Literal(path) .. ": " .. err)
			elseif node.kind ~= "file" then io.err(SH.Literal(path) .. ": " .. L["Is a directory"])
			else
				EnsureSold(io, node.d)
				for _, l in ipairs(FS.Content(node, io.sh:Wait()) or {}) do out[#out + 1] = l end
			end
		end
		return out
	end
	return io.stdin
end

SH.InputLines = InputLines

local function Count(n) return Paint("orange", n) end

----------------------------------------------------------------------
-- Looking around: ls, cd, pwd, tree, find, locate, cat, head, tail, stat, file
----------------------------------------------------------------------

-- ls -l's columns painted: mode dim, kind cyan, the id magenta, numbers orange, the distance green, the zone yellow, the name last
local COLUMN_PAINT = { "dim", "cyan", "magenta", "blue", "white", "orange", "orange", "green", "yellow" }
-- (cells are parted by tabs: the console lines them up at stops it measures, the plain text still splits at spaces)

--- The columns an ls -l shows: -o's ("dist,title,name", "all"), else those any of `rows` has (mode and the name
--- always; kind only when the files come from several lists). A list of column numbers, or nil and the bad word.
function SH.ShowColumns(spec, rows, oneList)
	local show = {}
	if spec and spec ~= "" then
		if spec == "all" then
			for i = 1, #FS.COLUMNS do show[i] = i end
			return show
		end
		local hasName = false
		for word in spec:gmatch("[^,%s]+") do
			local i = FS.ColumnOf(word)
			if type(i) ~= "number" or not FS.COLUMNS[i] then return nil, word end
			show[#show + 1] = i
			if i == #FS.COLUMNS then hasName = true end
		end
		if not hasName then show[#show + 1] = #FS.COLUMNS end
		return show
	end
	for i = 1, #FS.COLUMNS - 1 do
		local keep = i == 1
		if i == 2 then keep = not oneList
		elseif not keep then
			for _, cols in ipairs(rows) do
				if cols[i] ~= "-" then keep = true break end
			end
		end
		if keep then show[#show + 1] = i end
	end
	show[#show + 1] = #FS.COLUMNS
	return show
end

local function LongLine(cols, painted, show)
	local out = {}
	for k, i in ipairs(show) do
		local v = cols[i]
		if i == #FS.COLUMNS then out[k] = painted
		else out[k] = v == "-" and Paint("dim", "-") or Paint(COLUMN_PAINT[i], SH.Literal(v)) end
	end
	return FS.Hidden(cols) .. table.concat(out, "\t")
end
SH.LongLine = LongLine

local function LsRoot(io, opts)
	local list = FS.Dirs()
	local from, to, step = 1, #list, 1
	if opts.r then from, to, step = #list, 1, -1 end
	local rows = {}
	if opts.l then for i, d in ipairs(list) do rows[i] = FS.Columns(d, nil, d.name) end end
	local show = opts.l and SH.ShowColumns(opts.o, rows, true)
	for i = from, to, step do
		local d = list[i]
		if opts.l then
			local shown = Link("/" .. d.name, DirName(d.name))
			if opts.I then shown = WithIcon(SH.FolderIcon(FS.Built(d) and FS.Tree(d).root or nil), shown) end
			io.out(LongLine(rows[i], shown, show))
		else
			local shown = Link("/" .. d.name, DirName(d.name))
			io.out(opts.I and WithIcon(SH.FolderIcon(FS.Built(d) and FS.Tree(d).root or nil), shown) or shown)
		end
		io.sh:Check()
	end
end

local function Here()
	local I = ns.Integrations
	if not (I and I.Here) then return nil end
	local ok, here = pcall(I.Here)
	return ok and here or nil
end

--- A folder's own line in ls -l: how many rows are under it.
local function FolderCols(f, name)
	return { FS.Mode(nil, true), f.parent and f.parent.kind or f.kind, "-", "-", "-", "-", tostring(f.total or 0), "-", "-", name }
end

--- ls of a folder: its folders first (blue, with their /), then its files. -R: then each folder under it, its path
--- said first, as ls -R does.
local function LsFolder(io, d, folder, opts)
	local nested = not folder.row and d.p and FS.CHILDREN[d.p.id] -- (rows that are directories: shown with their /)
	local files = folder.files
	local function Shown(n)
		if nested and FS.Children(d, files.by[Lower(n)]) then return Painted(d, n) .. Paint("blue", "/") end
		return Painted(d, n)
	end
	local names = files.names
	local here = (opts.l or opts.N) and Here() or nil
	if opts.N then -- nearest first (no place: last, in name order)
		local yd = {}
		for i, n in ipairs(names) do
			yd[n] = FS.Yards(files.by[Lower(n)], here) or math.huge
			if i % 64 == 0 then io.sh:Check() end
		end
		local copy, order = {}, {}
		for i, n in ipairs(names) do copy[i], order[n] = n, i end
		table.sort(copy, function(a, b)
			if yd[a] ~= yd[b] then return yd[a] < yd[b] end
			return order[a] < order[b]
		end)
		names = copy
	end
	-- what's listed: { name, folder } then { name, row }
	local items = {}
	for _, n in ipairs(folder.dirNames) do items[#items + 1] = { n, folder.dirs[Lower(n)] } end
	for _, n in ipairs(names) do items[#items + 1] = { n, nil, files.by[Lower(n)] } end
	local rows, show = {}, nil
	if opts.l then -- (every row's columns first: which to show depends on them all)
		for i, it in ipairs(items) do
			rows[i] = it[2] and FolderCols(it[2], it[1]) or FS.Columns(d, it[3], it[1], here, folder)
			if i % 64 == 0 then io.sh:Check() end
		end
		show = SH.ShowColumns(opts.o, rows, true)
	end
	local from, to, step = 1, #items, 1
	if opts.r then from, to, step = #items, 1, -1 end
	for i = from, to, step do
		local it = items[i]
		local shown = Link(Under(folder.path, it[1]), it[2] and DirName(it[1]) or Shown(it[1]))
		if opts.I then shown = WithIcon(it[2] and SH.FolderIcon(it[2]) or SH.IconText(it[3]), shown) end
		io.out(opts.l and LongLine(rows[i], shown, show) or shown)
		if i % 64 == 0 then io.sh:Check() end
	end
	if opts.R then
		for _, n in ipairs(folder.dirNames) do
			local sub = folder.dirs[Lower(n)]
			io.out("")
			io.out(Paint("blue", SH.Literal(sub.path)) .. ":")
			LsFolder(io, d, sub, opts)
		end
	end
end

SH.Command("ls", {
	desc = L["list a directory: every list is one, every row a file"],
	usage = "ls [-lrRN] [-o columns] [--icons] [path...]",
	man = { L["Lists are folders: /loot/<instance>/<boss>, /npc/<zone>/<role>, /recipe/<profession>, /mailbox/<zone>; folders first."],
		L["-R  every folder under it too, each after its path (ls -lR /loot | where zone~lordaeron; or find /loot -type f)"],
		L["-l  long: a line of columns per file, one word each (- for none), lined up, the name last."],
		L["--icons  each file's game icon before its name (a folder: its first file's); alias ls='ls --icons' for always"],
		L["    Shown: the columns any file listed has (a file named alone: all of them). Every line still carries"],
		L["    all of them, so where, field and sort -k read any column, shown or not."],
		L["-o  the columns to show, commas between (the name is added last): ls -l -o dist,title,name; -o all"],
		L["-N  nearest first      -r  reverse order"],
		"",
		L["FIELDS"],
		L["    mode   d a directory, - a row, c a system file; then r it has a tooltip, x Enter does something,"],
		L["           s so does Shift+Enter, l a link for chat, n a place in the world, u an upgrade for you (loot)"],
		L["    kind   the list (the directory) it's in: npc, item, loot..."],
		L["    id     the game's number for it: item:2589, spell:133, npc:448, quest:..., map:..."],
		L["    role   an NPC's roles (Questie's): innkeeper, repair, vendor, banker, flightmaster, trainer..."],
		L["    title  an NPC's title (Reagent_Vendor, Mining_Trainer), or a loot row's boss; spaces as _"],
		L["    lvl    its level, or level range (20-25): an item's required level, an NPC's, a quest's, a zone's"],
		L["    count  how many: your stacks, a currency, rows in a directory"],
		L["    dist   how far from you: 312yd (NPCs, mailboxes, flight masters, entrances)"],
		L["    zone   where it is (a loot row: its instance); spaces as _"],
		L["    name   the file's name"],
		L["    path   not shown: the whole path, for xargs (field path)"],
		"",
		L["ls -lN /npc | head      ls -l /npc | where dist<300 lvl>=20      ls -l -o dist,zone,name /mailbox"] },
	aliases = { "ll", "dir" },
	args = "path",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "lar1NRo:I", { ["--icons"] = "I" })
		if not opts then io.err(rest) return 2 end
		if io.name == "ll" then opts.l = true end
		if opts.o then
			opts.l = true
			local ok, bad = SH.ShowColumns(opts.o, {}, true)
			if not ok then io.err(L["no column '%s' (ls -l's: mode kind id role title lvl count dist zone name)"]:format(SH.Literal(bad))) return 2 end
		end
		if #rest == 0 then rest = { io.sh.cwd } end
		rest = PathArgs(io, rest)
		local status = 0
		for i, path in ipairs(rest) do
			local node, err = Resolve(io, path)
			if not node then
				io.err(L["cannot access '%s': %s"]:format(SH.Literal(path), err))
				status = 2
			else
				local folder = FolderOf(node)
				if (#rest > 1 or opts.R) and (folder or node.kind == "root") then
					if i > 1 then io.out("") end
					io.out(Paint("blue", SH.Literal(node.path)) .. ":")
				end
				if node.kind == "root" then
					LsRoot(io, opts)
					if opts.R then
						for _, d in ipairs((FS.Dirs())) do
							io.out("")
							io.out(Paint("blue", "/" .. SH.Literal(d.name)) .. ":")
							local top = Resolve(io, "/" .. d.name)
							if top then LsFolder(io, d, top.folder, opts) end
						end
					end
				elseif folder then LsFolder(io, node.d, folder, opts)
				elseif opts.l then -- (a file named: its own ls -l line, as in its directory's listing)
					local cols = FS.Columns(node.d, node.e, node.name, Here(), node.folder)
					local shown = Link(node.path, Painted(node.d, node.name))
					if opts.I then shown = WithIcon(SH.IconText(node.e), shown) end
					io.out(LongLine(cols, shown, SH.ShowColumns(opts.o or "all", { cols })))
				else
					local shown = Link(node.path, Painted(node.d, node.name))
					io.out(opts.I and WithIcon(SH.IconText(node.e), shown) or shown)
				end
			end
		end
		return status
	end,
})

SH.Command("cd", {
	desc = L["change directory (cd -: the last one; cd: ~)"],
	usage = "cd [path]",
	args = "path",
	run = function(io)
		local path = io.args[1] or "/"
		if path == "-" then path = io.sh.prevCwd end
		if #io.args > 1 then path = table.concat(io.args, " ") end
		local node, err = Resolve(io, path)
		if not node then io.err(SH.Literal(path) .. ": " .. err) return 1 end
		if node.kind == "file" and not node.children then io.err(SH.Literal(path) .. ": " .. L["Not a directory"]) return 1 end
		io.sh.prevCwd, io.sh.cwd = io.sh.cwd, node.path
		SH.ZAdd(node.path)
		return 0
	end,
})

SH.Command("pwd", {
	desc = L["where you are"],
	run = function(io) io.out(io.sh.cwd) return 0 end,
})

SH.Command("tree", {
	desc = L["the directories and their files as a tree"],
	usage = "tree [-L depth] [path]",
	man = { L["-L n  how deep (from the root: 1 = the lists only, the default there; elsewhere: all of it)"] },
	args = "path",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "L:")
		if not opts then io.err(rest) return 2 end
		local node, err = Resolve(io, rest[1] or io.sh.cwd)
		if not node then io.err(err) return 1 end
		local depth = tonumber(opts.L)
		local nd, nf = 0, 0
		-- a folder's folders and files, drawn under `lead`, `level` deep (from where tree started)
		local function Draw(d, folder, lead, level)
			local items = {}
			for _, n in ipairs(folder.dirNames) do items[#items + 1] = { n, folder.dirs[Lower(n)] } end
			if not depth or level <= depth then
				for _, n in ipairs(folder.files.names) do items[#items + 1] = { n } end
			end
			for i, it in ipairs(items) do
				local last = i == #items
				if it[2] then
					io.out(Paint("dim", lead .. (last and "`-- " or "|-- ")) .. DirName(it[1]) .. " " .. Paint("dim", "(" .. (it[2].total or 0) .. ")"))
					nd = nd + 1
					if not depth or level < depth then Draw(d, it[2], lead .. (last and "    " or "|   "), level + 1) end
				else
					io.out(Paint("dim", lead .. (last and "`-- " or "|-- ")) .. Painted(d, it[1]))
					nf = nf + 1
				end
				if i % 64 == 0 then io.sh:Check() end
			end
		end
		if node.kind == "root" then
			depth = depth or 1
			io.out(Paint("blue", "~"))
			local list = FS.Dirs()
			for i, d in ipairs(list) do
				local lastOne = i == #list
				local n = d.p and FS.Built(d) and (" " .. Paint("dim", "(" .. #(d.p._entries or {}) .. ")")) or ""
				io.out(Paint("dim", lastOne and "`-- " or "|-- ") .. DirName(d.name) .. n)
				nd = nd + 1
				if depth >= 2 then
					local top = Resolve(io, "/" .. d.name)
					if top then Draw(d, top.folder, lastOne and "    " or "|   ", 2) end
				end
				io.sh:Check()
			end
		elseif FolderOf(node) then
			io.out(DirName(node.path))
			Draw(node.d, FolderOf(node), "", 1)
		else
			io.out(Painted(node.d, node.name))
			nf = 1
		end
		io.out("")
		io.out(L["%d directories, %d files"]:format(nd, nf))
		return 0
	end,
})

--- Walks the paths given (the root: every list), calling each(path, d, name, isDir, depth) for every folder and file
--- under them; stops early when each says so.
local function Walk(io, paths, maxDepth, each)
	local stop = false
	local function Folder(d, folder, depth)
		if stop then return end
		if each(folder.path, d, folder.name or d.name, true, depth) then stop = true return end
		if maxDepth and depth >= maxDepth then return end
		for i, n in ipairs(folder.files.names) do
			if each(folder.path .. "/" .. n, d, n, false, depth + 1) then stop = true return end
			if i % 64 == 0 then io.sh:Check() end
		end
		for _, n in ipairs(folder.dirNames) do
			Folder(d, folder.dirs[Lower(n)], depth + 1)
			if stop then return end
		end
		io.sh:Check()
	end
	for _, path in ipairs(paths) do
		local node, err = Resolve(io, path)
		if not node then io.err(SH.Literal(path) .. ": " .. err)
		elseif node.kind == "root" then
			if each("/", nil, nil, true, 0) then return end
			for _, d in ipairs((FS.Dirs())) do
				local top = Resolve(io, "/" .. d.name)
				if top then Folder(d, top.folder, 1) end
				if stop then return end
			end
		elseif FolderOf(node) then
			Folder(node.d, FolderOf(node), 0)
		elseif each(node.path, node.d, node.name, false, 0) then return end
		if stop then return end
	end
end

SH.Command("find", {
	desc = L["find files by name (-name '*glob*', -type f|d)"],
	usage = "find [path...] [-name glob] [-iname glob] [-type f|d] [-maxdepth n]",
	man = { L["-name glob   names matching the glob (* ? [abc]), either case (-iname the same)"],
		L["-type f|d    files or directories only"], L["-maxdepth n  how deep (1 = what's right under where it starts)"],
		L["find / -name '*potion*'     find /item -name 'linen*'     find /loot/Scholomance -type f | xargs ls -l"] },
	args = "path",
	run = function(io)
		local paths, glob, ftype, maxDepth = {}, nil, nil, nil
		local i = 1
		local a = io.args
		while i <= #a do
			local w = a[i]
			if w == "-name" or w == "-iname" then glob = a[i + 1]; i = i + 1
			elseif w == "-type" then ftype = a[i + 1]; i = i + 1
			elseif w == "-maxdepth" then maxDepth = tonumber(a[i + 1]); i = i + 1
			elseif w:sub(1, 1) == "-" then io.err(L["unknown predicate '%s'"]:format(SH.Literal(w))) return 1
			else paths[#paths + 1] = w end
			i = i + 1
		end
		if #paths == 0 then paths = { io.sh.cwd } end
		local pat = glob and FS.GlobPattern(glob)
		local n = 0
		Walk(io, paths, maxDepth, function(path, d, name, isDir)
			if ftype == "f" and isDir then return end
			if ftype == "d" and not isDir then return end
			local base = name or (d and d.name) or "/"
			if not pat or FS.GlobMatch(pat, base) then
				n = n + 1
				io.out(Link(path, isDir and Paint("blue", SH.Literal(path)) or (Paint("dim", SH.Literal(path:match("^(.*/)") or "")) .. Painted(d, base))))
			end
		end)
		return n > 0 and 0 or 1
	end,
})

SH.Command("locate", {
	desc = L["every file whose name has all these words, in every list"],
	usage = "locate word...",
	run = function(io)
		if #io.args == 0 then io.err(L["no words given"]) return 1 end
		local words = {}
		for _, w in ipairs(io.args) do words[#words + 1] = Lower(w) end
		local n = 0
		for _, d in ipairs((FS.Dirs())) do
			local top = not d.special and Resolve(io, "/" .. d.name)
			if top then
				FS.EachFolder(top.folder, function(folder)
					for i, name in ipairs(folder.files.names) do
						local ln = Lower(name)
						local all = true
						for _, w in ipairs(words) do if not ln:find(w, 1, true) then all = false break end end
						if all then n = n + 1; io.out(Link(Under(folder.path, name), Paint("dim", SH.Literal(folder.path) .. "/") .. Painted(d, name))) end
						if i % 128 == 0 then io.sh:Check() end
					end
				end)
			end
			io.sh:Check()
		end
		return n > 0 and 0 or 1
	end,
})

SH.Command("cat", {
	desc = L["what a file says: its tooltip, line by line"],
	usage = "cat [-nv] file...",
	man = { L["-n  number the lines"], L["-v  also say where the lines came from (the tooltip API, a hidden tooltip, the item's data)"],
		L["With no file: what was piped in."] },
	aliases = { "bat" },
	args = "path",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "nv")
		if not opts then io.err(rest) return 2 end
		local status = 0
		local function Put(lines)
			for i, l in ipairs(lines) do
				io.out(opts.n and (Paint("dim", ("%5d  "):format(i)) .. l) or l)
				if i % 64 == 0 then io.sh:Check() end
			end
		end
		if #rest == 0 then
			if not io.stdin then io.err(L["no file given"]) return 1 end
			Put(io.stdin)
			return 0
		end
		for _, path in ipairs(PathArgs(io, rest)) do
			local node, err = Resolve(io, path)
			if not node then io.err(SH.Literal(path) .. ": " .. err) status = 1
			elseif node.kind ~= "file" then io.err(SH.Literal(path) .. ": " .. L["Is a directory"]) status = 1
			else
				EnsureSold(io, node.d)
				Put(FS.Content(node, io.sh:Wait(), opts.v) or {})
			end
		end
		return status
	end,
})

local function HeadTail(tail)
	return function(io)
		local opts, rest = SH.Opts(io.args, "n:", nil, true)
		if not opts then io.err(rest) return 2 end
		local n = tonumber(opts.n) or opts.number or 10
		local lines = InputLines(io, rest)
		if not lines then io.err(L["no input"]) return 1 end
		local from, to = 1, math.min(n, #lines)
		if tail then from, to = math.max(1, #lines - n + 1), #lines end
		for i = from, to do io.out(lines[i]) end
		return 0
	end
end
SH.Command("head", { desc = L["the first lines (-n N, default 10)"], usage = "head [-n N] [file...]", args = "path", run = HeadTail(false) })
SH.Command("tail", { desc = L["the last lines (-n N, default 10)"], usage = "tail [-n N] [file...]", args = "path", run = HeadTail(true) })

SH.Command("less", {
	desc = L["read lines a page at a time, all of them (the scrollback keeps 2000): q quits, / searches"],
	usage = "less [file...]",
	man = { L["Keys: Space or PageDown a page on, b or PageUp back, j k or the arrows a line, g the top, G the end,"],
		L["/ searches on, ? back, n the next match, N the one before, q or Esc quits. The wheel scrolls too."],
		L["ls -l /npc | less      grep -r stamina /item | less      Ctrl+R: this pane's scrollback, searching back"] },
	aliases = { "more", "pager" },
	args = "path",
	run = function(io)
		local lines = InputLines(io, io.args)
		if not lines then io.err(L["no input: give a file, or pipe something in (ls -l /npc | less)"]) return 1 end
		local ui = io.sh.ui
		if ui and ui.Pager then
			ui.Pager(io.sh, lines, #io.args > 0 and table.concat(io.args, " ") or "less")
			return 0
		end
		for _, l in ipairs(lines) do io.out(l) end
		return 0
	end,
})

SH.Command("stat", {
	desc = L["a file's fields: its row's own values"],
	usage = "stat file...",
	args = "path",
	run = function(io)
		if #io.args == 0 then io.err(L["missing operand"]) return 1 end
		for _, path in ipairs(PathArgs(io, io.args)) do
			local node, err = Resolve(io, path)
			if not node then io.err(SH.Literal(path) .. ": " .. err)
			else
				for _, l in ipairs(FS.Stat(node)) do
					local k, v = l:match("^(%s*[^:]+:)(.*)$")
					io.out(k and (Paint("cyan", SH.Literal(k)) .. SH.Literal(v)) or SH.Literal(l))
				end
			end
		end
		return 0
	end,
})

SH.Command("file", {
	desc = L["what kind of thing a file is"],
	usage = "file path...",
	args = "path",
	run = function(io)
		for _, path in ipairs(PathArgs(io, io.args)) do
			local node, err = Resolve(io, path)
			if not node then io.err(SH.Literal(path) .. ": " .. err)
			elseif node.kind ~= "file" then io.out(SH.Literal(path) .. ": " .. L["directory"])
			elseif node.e.special then io.out(SH.Literal(path) .. ": " .. L["text"])
			else
				local p = node.d.p
				local detail = node.e.detail and FS.Strip(node.e.detail) or ""
				io.out(SH.Literal(path) .. ": " .. Paint("cyan", SH.Literal(FS.Strip(p.label or p.id)))
					.. (detail ~= "" and (", " .. SH.Literal(detail)) or ""))
			end
		end
		return 0
	end,
})

----------------------------------------------------------------------
-- grep
----------------------------------------------------------------------

SH.Command("grep", {
	desc = L["lines matching a pattern: in what was piped in, or in files (-r: whole directories)"],
	usage = "grep [-ivclnrwFh] [-m N] pattern [path...]",
	man = {
		L["Without -i a pattern with no capital letter matches either case (smart case); with a capital, as typed."],
		L["Patterns: . * + ? ^ $ [abc] [^abc] \\d \\w \\s, a|b for either (quote it: 'a|b'); -F for plain text."],
		L["-i ignore case   -v lines that don't match   -c count   -l the files only   -n line numbers"],
		L["-r a directory's files (or every list from ~)   -w whole words   -h no file names   -m N stop after N"],
		L["ls /item | grep potion      grep -ri 'stamina' /item      grep -rl 'Hogger' /quest"],
	},
	aliases = { "egrep", "rg" },
	args = "path",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "ivclnrRwFEPhHsm:o", { ["--count"] = "c", ["--ignore-case"] = "i",
			["--invert-match"] = "v", ["--recursive"] = "r", ["--files-with-matches"] = "l" })
		if not opts then io.err(rest) return 2 end
		local pattern = table.remove(rest, 1)
		if not pattern then io.err(L["usage: grep [options] pattern [path...]"]) return 2 end
		local recursive = opts.r or opts.R
		local match = SH.Matcher(pattern, { ignore = opts.i, fixed = opts.F, word = opts.w })
		local max = tonumber(opts.m)
		local found = 0
		-- (label: the file, said before each line only when several are read; -l always says it)
		local function Lines(lines, label, path)
			local hits = 0
			for i, line in ipairs(lines) do
				local plain = Strip(line)
				local s, e = match(plain)
				if (s ~= nil) ~= (opts.v == true) then
					hits = hits + 1
					if opts.l then break end
					if not opts.c then
						local text = (s and not opts.v) and Mark(line, s, e) or line
						local lead = ""
						if label and not opts.h then lead = Link(path or label, Paint("magenta", SH.Literal(label))) .. Paint("dim", ":") end
						if opts.n then lead = lead .. Paint("green", i) .. Paint("dim", ":") end
						io.out(lead .. text)
					end
					if max and hits >= max then break end
				end
				if i % 128 == 0 then io.sh:Check() end
			end
			if opts.c then io.out((label and not opts.h) and (Paint("magenta", SH.Literal(label)) .. Paint("dim", ":") .. hits) or tostring(hits)) end
			if opts.l and hits > 0 then io.out(Link(path or label, Paint("magenta", SH.Literal(path or label or "(standard input)")))) end
			found = found + hits
		end
		if #rest == 0 then
			if not io.stdin then io.err(L["no input: give a file, or pipe something in (ls | grep x)"]) return 2 end
			Lines(io.stdin, nil)
			return found > 0 and 0 or 1
		end
		local several = #rest > 1 or recursive
		for _, path in ipairs(rest) do
			local node, err = Resolve(io, path)
			if not node then io.err(SH.Literal(path) .. ": " .. err)
			elseif node.kind == "file" then
				EnsureSold(io, node.d)
				Lines(FS.Content(node, io.sh:Wait()) or {}, several and node.path or nil, node.path)
			elseif not recursive then
				io.err(SH.Literal(path) .. ": " .. L["Is a directory (grep -r reads its files)"])
			else
				-- (every folder under it; a whole list read: no waiting on each item the game hasn't loaded)
				local function Folder(d, folder)
					EnsureSold(io, d)
					local files = folder.files
					local nested = not folder.row and d.p and FS.CHILDREN[d.p.id]
					for _, n in ipairs(files.names) do
						local f = { kind = "file", d = d, e = files.by[Lower(n)], name = n, path = folder.path .. "/" .. n }
						Lines(FS.Content(f, nil) or {}, f.path)
						-- (a row with files of its own, an attunement's steps: those too)
						local own = nested and FS.RowFolder(d, f.e, folder, n)
						if own then Folder(d, own) end
						io.sh:Check()
					end
					for _, dn in ipairs(folder.dirNames) do Folder(d, folder.dirs[Lower(dn)]) end
				end
				if node.kind == "root" then
					for _, d in ipairs((FS.Dirs())) do
						local top = Resolve(io, "/" .. d.name)
						if top then Folder(d, top.folder) end
					end
				else
					Folder(node.d, FolderOf(node))
				end
			end
		end
		return found > 0 and 0 or 1
	end,
})

----------------------------------------------------------------------
-- Pipes: what was piped in, made into something else
----------------------------------------------------------------------

local function NeedInput(io, files)
	local lines = InputLines(io, files)
	if not lines then io.err(L["no input: pipe something in (ls | %s)"]:format(io.name)) end
	return lines
end

SH.Command("wc", {
	desc = L["count lines, words and characters (-l lines only)"],
	usage = "wc [-lwc] [file...]",
	args = "path",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "lwcm")
		if not opts then io.err(rest) return 2 end
		local lines = NeedInput(io, rest)
		if not lines then return 1 end
		local w, c = 0, 0
		for _, l in ipairs(lines) do
			local p = Strip(l)
			c = c + #p + 1
			for _ in p:gmatch("%S+") do w = w + 1 end
		end
		if opts.l and not (opts.w or opts.c or opts.m) then io.out(Count(#lines))
		elseif opts.w and not (opts.l or opts.c) then io.out(Count(w))
		elseif (opts.c or opts.m) and not (opts.l or opts.w) then io.out(Count(c))
		else io.out(("%s %s %s"):format(Count(#lines), Count(w), Count(c))) end
		return 0
	end,
})

SH.Command("count", {
	desc = L["how many lines (ls /mount | count)"],
	usage = "count [file...]",
	args = "path",
	run = function(io)
		local lines = NeedInput(io, io.args)
		if not lines then return 1 end
		io.out(Count(#lines))
		return 0
	end,
})

local function Field(plain, k, delim)
	if not k then return plain end
	local i = 0
	if delim then
		for part in (plain .. delim):gmatch("(.-)" .. delim:gsub("%p", "%%%0")) do
			i = i + 1
			if i == k then return part end
		end
		return ""
	end
	for part in plain:gmatch("%S+") do
		i = i + 1
		if i == k then return part end
	end
	return ""
end

local NO_COLUMN = L["no column '%s' (ls -l's: mode kind id role title lvl count dist zone name)"]

local function Number(s)
	s = tostring(s or ""):gsub("(%d),(%d)", "%1%2")
	return tonumber(s:match("%-?%d+%.?%d*"))
end
SH.Number = Number

SH.Command("sort", {
	desc = L["sort lines (-r reverse, -n by number, -u once each, -k N by the Nth word or an ls -l column: -k dist)"],
	usage = "sort [-rnuf] [-k N|column] [-t delim] [file...]",
	args = "path",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "rnufk:t:hV")
		if not opts then io.err(rest) return 2 end
		local lines = NeedInput(io, rest)
		if not lines then return 1 end
		local k, delim = opts.k, opts.t
		local named = k and not tonumber(k) and FS.ColumnOf(k)
		if k and not tonumber(k) and not named then
			io.err(NO_COLUMN:format(SH.Literal(k)))
			return 2
		end
		local keys, nums = {}, {}
		local copy = {}
		local numeric = opts.n or opts.h
		for i, l in ipairs(lines) do
			copy[i] = i
			local plain = Strip(l)
			local f
			if named then
				local long = FS.ParseLong(l)
				f = long and long[named] or ""
			else
				f = Field(plain, tonumber(k), delim)
			end
			keys[i] = Lower(f)
			if numeric then nums[i] = Number(f) end
		end
		local rev = opts.r
		-- (lines with no number go last, either way round; equal lines keep their order)
		table.sort(copy, function(a, b)
			if numeric then
				local x, y = nums[a], nums[b]
				if x and not y then return true end
				if y and not x then return false end
				if x ~= y then if rev then return x > y end return x < y end
			end
			if keys[a] ~= keys[b] then if rev then return keys[a] > keys[b] end return keys[a] < keys[b] end
			return a < b
		end)
		local last
		for _, i in ipairs(copy) do
			if not (opts.u and last and keys[last] == keys[i]) then io.out(lines[i]) end
			last = i
		end
		return 0
	end,
})

SH.Command("uniq", {
	desc = L["drop a line repeated right after itself (-c: with how many; sort first for every repeat)"],
	usage = "uniq [-cdi] [file...]",
	args = "path",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "cdiu")
		if not opts then io.err(rest) return 2 end
		local lines = NeedInput(io, rest)
		if not lines then return 1 end
		local function Key(l) local p = Strip(l) return opts.i and Lower(p) or p end
		local i = 1
		while i <= #lines do
			local j = i
			local key = Key(lines[i])
			while j < #lines and Key(lines[j + 1]) == key do j = j + 1 end
			local n = j - i + 1
			if (not opts.d or n > 1) and (not opts.u or n == 1) then
				io.out(opts.c and (Paint("orange", ("%7d "):format(n)) .. lines[i]) or lines[i])
			end
			i = j + 1
		end
		return 0
	end,
})

local function Ranges(spec)
	local list = {}
	for part in tostring(spec or ""):gmatch("[^,]+") do
		local a, b = part:match("^(%d*)%-(%d*)$")
		if a then list[#list + 1] = { tonumber(a) or 1, tonumber(b) or math.huge }
		elseif tonumber(part) then list[#list + 1] = { tonumber(part), tonumber(part) } end
	end
	return list
end
local function InRanges(list, i)
	for _, r in ipairs(list) do if i >= r[1] and i <= r[2] then return true end end
	return false
end

SH.Command("cut", {
	desc = L["parts of each line: -f fields (split at -d, else at spaces), -c characters"],
	usage = "cut [-d delim] -f list | -c list [file...]",
	args = "path",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "d:f:c:")
		if not opts then io.err(rest) return 2 end
		if not (opts.f or opts.c) then io.err(L["you must say a list of fields (-f) or characters (-c)"]) return 1 end
		local lines = NeedInput(io, rest)
		if not lines then return 1 end
		local ranges = Ranges(opts.f or opts.c)
		for _, l in ipairs(lines) do
			local p = Strip(l)
			local out = {}
			if opts.c then
				for i = 1, #p do if InRanges(ranges, i) then out[#out + 1] = p:sub(i, i) end end
				io.out(SH.Literal(table.concat(out)))
			else
				local parts = {}
				if opts.d then
					for part in (p .. opts.d):gmatch("(.-)" .. opts.d:gsub("%p", "%%%0")) do parts[#parts + 1] = part end
				else
					for part in p:gmatch("%S+") do parts[#parts + 1] = part end
				end
				for i, part in ipairs(parts) do if InRanges(ranges, i) then out[#out + 1] = part end end
				io.out(SH.Literal(table.concat(out, opts.d or " ")))
			end
		end
		return 0
	end,
})

--- A line's value for a column: an ls -l column by name (or number, the name being all that's left), else its Nth
--- word. nil when it has none ("-" counts as none); the second result false when a named column needs ls -l's lines.
local function ColumnValue(line, col, delim)
	local long = FS.ParseLong(line)
	local plain = Strip(line)
	local idx = FS.ColumnOf(col)
	local v
	if long and idx then
		v = long[idx]
	elseif tonumber(col) then
		local n = tonumber(col)
		local words = {}
		if delim then
			for part in (plain .. delim):gmatch("(.-)" .. delim:gsub("%p", "%%%0")) do words[#words + 1] = part end
		else
			for w in plain:gmatch("%S+") do words[#words + 1] = w end
		end
		if n < 0 then n = #words + n + 1 end
		v = words[n]
	else
		return nil, false
	end
	if v == nil or v == "-" or v == "" then return nil, true end
	return v, true
end
SH.ColumnValue = ColumnValue

SH.Command("field", {
	desc = L["pick columns: ls -l's by name (mode kind id role title lvl count dist zone name), or any line's Nth word"],
	usage = "field [-d delim] column...",
	man = { L["ls -l /npc | field dist name      ls -l /item | field count name      echo a b c | field 2 -1"],
		L["path: the whole path, not shown by ls -l, for xargs: ls -lN /npc | where role~vendor | field path | xargs cat"],
		L["A negative number counts from the end. A column a line hasn't: -."] },
	aliases = { "col" },
	run = function(io)
		local opts, rest = SH.Opts(io.args, "d:")
		if not opts then io.err(rest) return 2 end
		if #rest == 0 then io.err(L["say which columns (field dist name)"]) return 2 end
		local lines = io.stdin
		if not lines then io.err(L["no input: pipe something in (ls -l | field dist name)"]) return 1 end
		for _, col in ipairs(rest) do
			if not FS.ColumnOf(col) then io.err(NO_COLUMN:format(SH.Literal(col))) return 2 end
		end
		local anyLong -- (a line without columns, ls -R's "path:" and blank lines, is left out when others have them)
		for i, l in ipairs(lines) do
			local out, skip = {}, false
			for _, col in ipairs(rest) do
				local v, known = ColumnValue(l, col, opts.d)
				if known == false then
					if anyLong == nil then
						anyLong = false
						for _, x in ipairs(lines) do if FS.ParseLong(x) then anyLong = true break end end
					end
					if not anyLong then io.err(L["'%s' needs ls -l's lines"]:format(SH.Literal(col))) return 1 end
					skip = true
					break
				end
				out[#out + 1] = SH.Literal(v or "-")
			end
			if not skip then io.out(table.concat(out, opts.d or "  ")) end
			if i % 128 == 0 then io.sh:Check() end
		end
		return 0
	end,
})

local WHERE_OPS = { "<=", ">=", "!=", "!~", "==", "=", "<", ">", "~" }

--- One where condition ("dist<300", "zone~elwynn", "lvl>=20", "kind=npc") as function(plain) -> passes; nil when it
--- can't be read.
function SH.Condition(cond)
	for _, op in ipairs(WHERE_OPS) do
		local s = cond:find(op, 1, true)
		if s and s > 1 then
			local col, want = cond:sub(1, s - 1), cond:sub(s + #op)
			if not FS.ColumnOf(col) then return nil end
			local lwant, nwant = Lower(want), Number(want)
			local numberWanted = nwant ~= nil and not lwant:find("%a")
			return function(line)
				local v = ColumnValue(line, col)
				if not v then return op == "!=" or op == "!~" end
				local lv, nv = Lower(v), Number(v)
				if op == "~" then return lv:find(lwant, 1, true) ~= nil end
				if op == "!~" then return not lv:find(lwant, 1, true) end
				if op == "=" or op == "==" then
					if numberWanted and nv then return nv == nwant end
					return lv == lwant
				end
				if op == "!=" then
					if numberWanted and nv then return nv ~= nwant end
					return lv ~= lwant
				end
				if not (nv and nwant) then return false end
				if op == "<" then return nv < nwant end
				if op == "<=" then return nv <= nwant end
				if op == ">" then return nv > nwant end
				return nv >= nwant
			end
		end
	end
	return nil
end

SH.Command("where", {
	desc = L["keep the lines whose columns pass: where dist<300 lvl>=20 zone~elwynn (ls -l's columns, or 1 2 3...)"],
	usage = "where condition...",
	man = { L["Conditions: a column, then = != < <= > >= (numbers: 312yd counts as 312) or ~ !~ (holds, doesn't hold),"],
		L["then a value. Every condition must pass. Columns: mode kind id role title lvl count dist zone name, or a word's number."],
		L["ls -l /npc | where dist<200 mode~x      ls -l /item | where count>=20      ls -l /npc | where zone~barrens lvl<=15"] },
	aliases = { "filter" },
	run = function(io)
		if #io.args == 0 then io.err(L["say what to keep (where dist<300)"]) return 2 end
		local lines = io.stdin
		if not lines then io.err(L["no input: pipe something in (ls -l | where dist<300)"]) return 1 end
		local tests = {}
		for _, a in ipairs(io.args) do
			local t = SH.Condition(a)
			if not t then
				io.err(L["can't read '%s' (a column, then = != < <= > >= ~ !~, then a value)"]:format(SH.Literal(a)))
				return 2
			end
			tests[#tests + 1] = t
		end
		local n = 0
		for i, l in ipairs(lines) do
			local all = true
			for _, t in ipairs(tests) do
				if not t(l) then all = false break end
			end
			if all then io.out(l) n = n + 1 end
			if i % 128 == 0 then io.sh:Check() end
		end
		return n > 0 and 0 or 1
	end,
})

SH.Command("nl", {
	desc = L["number the lines"],
	usage = "nl [file...]",
	args = "path",
	run = function(io)
		local lines = NeedInput(io, io.args)
		if not lines then return 1 end
		for i, l in ipairs(lines) do io.out(Paint("dim", ("%6d  "):format(i)) .. l) end
		return 0
	end,
})

SH.Command("tac", {
	desc = L["the lines last to first"],
	usage = "tac [file...]",
	args = "path",
	run = function(io)
		local lines = NeedInput(io, io.args)
		if not lines then return 1 end
		for i = #lines, 1, -1 do io.out(lines[i]) end
		return 0
	end,
})

SH.Command("rev", {
	desc = L["each line's characters backwards"],
	usage = "rev [file...]",
	args = "path",
	run = function(io)
		local lines = NeedInput(io, io.args)
		if not lines then return 1 end
		for _, l in ipairs(lines) do
			local chars = {}
			for ch in Strip(l):gmatch("[%z\1-\127\194-\244][\128-\191]*") do table.insert(chars, 1, ch) end
			io.out(SH.Literal(table.concat(chars)))
		end
		return 0
	end,
})

SH.Command("shuf", {
	desc = L["the lines in a random order (-n N: N of them)"],
	usage = "shuf [-n N] [file...]",
	args = "path",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "n:")
		if not opts then io.err(rest) return 2 end
		local lines = NeedInput(io, rest)
		if not lines then return 1 end
		local copy = {}
		for i, l in ipairs(lines) do copy[i] = l end
		for i = #copy, 2, -1 do
			local j = math.random(i)
			copy[i], copy[j] = copy[j], copy[i]
		end
		local n = math.min(#copy, tonumber(opts.n) or #copy)
		for i = 1, n do io.out(copy[i]) end
		return 0
	end,
})

--- tr's sets: a-z ranges, [:lower:] [:upper:] [:digit:] [:space:].
local function TrSet(s)
	s = s:gsub("%[:lower:%]", "a-z"):gsub("%[:upper:%]", "A-Z"):gsub("%[:digit:%]", "0-9"):gsub("%[:space:%]", " \t")
	local out, i = {}, 1
	while i <= #s do
		local a, b = s:sub(i, i), s:sub(i + 2, i + 2)
		if s:sub(i + 1, i + 1) == "-" and b ~= "" then
			for c = a:byte(), b:byte() do out[#out + 1] = string.char(c) end
			i = i + 3
		else
			out[#out + 1] = a
			i = i + 1
		end
	end
	return out
end

SH.Command("tr", {
	desc = L["change characters (tr a-z A-Z) or delete them (-d)"],
	usage = "tr [-d] set1 [set2]",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "d")
		if not opts then io.err(rest) return 2 end
		if not io.stdin then io.err(L["no input: pipe something in"]) return 1 end
		local from = TrSet(rest[1] or "")
		local to = TrSet(rest[2] or "")
		local map = {}
		for i, c in ipairs(from) do map[c] = opts.d and "" or (to[i] or to[#to] or c) end
		for _, l in ipairs(io.stdin) do
			io.out(SH.Literal((Strip(l):gsub(".", function(c) return map[c] end))))
		end
		return 0
	end,
})

SH.Command("sed", {
	desc = L["s/pattern/replacement/[gi] on each line"],
	usage = "sed 's/pattern/replacement/g' [file...]",
	args = "path",
	run = function(io)
		local script = table.remove(io.args, 1)
		local lines = NeedInput(io, io.args)
		if not lines then return 1 end
		local sep = script and script:match("^s(.)")
		if not sep then io.err(L["only s/pattern/replacement/ is known here"]) return 1 end
		local esep = sep:gsub("%p", "%%%0")
		local pat, rep, flags = script:match("^s" .. esep .. "(.-)" .. esep .. "(.-)" .. esep .. "(%a*)$")
		if not pat then io.err(L["unterminated `s' command"]) return 1 end
		local match = SH.Matcher(pat, { ignore = flags:find("i") ~= nil, case = not flags:find("i") })
		local global = flags:find("g") ~= nil
		rep = rep:gsub("&", "\2")
		for _, l in ipairs(lines) do
			local p = Strip(l)
			local out, pos = {}, 1
			while pos <= #p do
				local s, e = match(p:sub(pos))
				if not s then break end
				s, e = s + pos - 1, e + pos - 1
				out[#out + 1] = p:sub(pos, s - 1)
				out[#out + 1] = (rep:gsub("\2", function() return p:sub(s, e) end))
				pos = math.max(e + 1, s + 1)
				if e < s then out[#out + 1] = p:sub(s, s) end
				if not global then break end
			end
			out[#out + 1] = p:sub(pos)
			io.out(SH.Literal(table.concat(out)))
		end
		return 0
	end,
})

SH.Command("sum", {
	desc = L["add up the numbers (each line's first number, or its -f Nth word's): total, count, average, min, max"],
	usage = "sum [-f N] [file...]",
	aliases = { "stats" },
	args = "path",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "f:")
		if not opts then io.err(rest) return 2 end
		local lines = NeedInput(io, rest)
		if not lines then return 1 end
		local total, n, lo, hi = 0, 0, nil, nil
		for _, l in ipairs(lines) do
			local v = Number(Field(Strip(l), tonumber(opts.f)))
			if v then
				total, n = total + v, n + 1
				lo = lo and math.min(lo, v) or v
				hi = hi and math.max(hi, v) or v
			end
		end
		if n == 0 then io.out(Paint("dim", L["no numbers"])) return 1 end
		local function F(v) if v == math.floor(v) then return ("%.0f"):format(v) end return ("%.2f"):format(v) end
		io.out(("%s %s   %s %s   %s %s   %s %s   %s %s"):format(Paint("dim", "sum"), Count(F(total)), Paint("dim", "count"),
			Count(n), Paint("dim", "avg"), Count(F(total / n)), Paint("dim", "min"), Count(F(lo)), Paint("dim", "max"), Count(F(hi))))
		return 0
	end,
})

SH.Command("seq", {
	desc = L["numbers in a row: seq 5, seq 2 10, seq 0 5 100"],
	usage = "seq [first [step]] last",
	run = function(io)
		local a = {}
		for i, v in ipairs(io.args) do a[i] = tonumber(v) end
		local first, step, last = 1, 1, a[1]
		if #a == 2 then first, last = a[1], a[2] elseif #a >= 3 then first, step, last = a[1], a[2], a[3] end
		if not (first and step and last) or step == 0 then io.err(L["usage: seq [first [step]] last"]) return 1 end
		local n = 0
		for v = first, last, step do
			io.out(tostring(v))
			n = n + 1
			if n >= 100000 then break end
			if n % 256 == 0 then io.sh:Check() end
		end
		return 0
	end,
})

SH.Command("xargs", {
	desc = L["run a command once per line piped in, the line as its last word (an ls -l line: its path): ls | grep x | xargs cat"],
	usage = "xargs command [words...]",
	run = function(io)
		if not io.stdin then io.err(L["no input: pipe something in"]) return 1 end
		local words = {}
		for i, w in ipairs(io.args) do words[i] = w end
		if #words == 0 then words[1] = "echo" end
		local status = 0
		for _, l in ipairs(io.stdin) do
			-- (an ls -l line stands for its file: ls -l /npc | where dist<200 | xargs pin)
			local long = FS.ParseLong(l)
			local line = long and long.path or Strip(l):match("^%s*(.-)%s*$")
			if line ~= "" then
				local w = {}
				for i, x in ipairs(words) do w[i] = x end
				w[#w + 1] = line
				local s = SH.RunWords(io.sh, w, nil, io.out)
				if s ~= 0 then status = s end
				io.sh:Check()
			end
		end
		return status
	end,
})

SH.Command("tee", {
	desc = L["pass lines on and keep a copy in /tmp (tee /tmp/name)"],
	usage = "tee [-a] /tmp/name",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "a")
		if not opts then io.err(rest) return 2 end
		local lines = io.stdin or {}
		for _, l in ipairs(lines) do io.out(l) end
		if rest[1] then
			local target = WriteTarget(io.sh, rest[1])
			if not target then io.err(SH.Literal(rest[1]) .. ": " .. L["Read-only file system (write to /tmp)"]) return 1 end
			SH.Write(target, lines, opts.a)
		end
		return 0
	end,
})

----------------------------------------------------------------------
-- The shell itself
----------------------------------------------------------------------

SH.Command("echo", {
	desc = L["say the words back"],
	usage = "echo [words...]",
	run = function(io)
		local a = io.args
		if a[1] == "-n" or a[1] == "-e" then table.remove(a, 1) end
		io.out(SH.Literal(table.concat(a, " ")))
		return 0
	end,
})

SH.Command("clear", {
	desc = L["clear the pane (Ctrl+L)"],
	aliases = { "cls" },
	run = function(io) io.sh.clear() return 0 end,
})

SH.Command("history", {
	desc = L["the lines you ran (!N runs line N again, !! the last, -c forgets them)"],
	usage = "history [-c] [N]",
	run = function(io)
		local h = io.sh.history
		if io.args[1] == "-c" then for i = #h, 1, -1 do h[i] = nil end return 0 end
		local n = tonumber(io.args[1]) or #h
		for i = math.max(1, #h - n + 1), #h do io.out(Paint("dim", ("%5d  "):format(i)) .. SH.Highlight(io.sh, h[i], true)) end
		return 0
	end,
})

local function Synopsis(def)
	return def.usage or def.name
end

SH.Command("help", {
	desc = L["every command, with a line on each"],
	run = function(io)
		io.out(Paint("blue", "tsh") .. Paint("dim", L[": the shell's commands (man <name> says more):"]))
		for _, n in ipairs(SH.ORDER) do
			local def = SH.CMDS[n]
			if not def.hidden then io.out("  " .. Paint("green", n) .. "  " .. Paint("dim", SH.Literal(def.desc or ""))) end
		end
		io.out(Paint("blue", "Terminal") .. Paint("dim", L[": its commands run here too (with or without the dot):"]))
		local names = {}
		for _, n in ipairs(ns.commandOrder or {}) do
			if not SH.CMDS[n] then names[#names + 1] = Paint("cyan", n) end
		end
		local line = {}
		for i, n in ipairs(names) do
			line[#line + 1] = n
			if #line == 10 or i == #names then io.out("  " .. table.concat(line, "  ")) line = {} end
		end
		io.out(Paint("dim", L["Pipes: cmd | grep x | sort | uniq -c | sort -rn | head   /   ; && ||   /   > /tmp/name   /   !! !N"]))
		io.out(Paint("dim", L["Keys: Ctrl+N new pane  Ctrl+W close  Ctrl+Tab/Ctrl+arrows/Ctrl+1-4 move  Ctrl+Z zoom  Ctrl+Space layout  Ctrl+Enter to the big pane"]))
		io.out(Paint("dim", L["      or Ctrl+B, then: c new pane  x close  o/n next  p back  arrows/1-4 move  z zoom  Space layout  Enter big  = - 0 size"]))
		io.out(Paint("dim", L["      (in a browser, Ctrl+N, Ctrl+W, Ctrl+T and Ctrl+Tab are the browser's: use Ctrl+B)"]))
		io.out(Paint("dim", L["      Ctrl+C stop  Ctrl+L clear  Up/Down history  Tab complete  PageUp/PageDown or the wheel scroll  ` step out"]))
		io.out(Paint("dim", L["      Lines too wide for the pane: Shift+wheel, or Left/Right with nothing typed (and in less), slides them"]))
		io.out(Paint("dim", L["      Right (or End) takes the faint suggestion from your history, Alt+Right one word of it"]))
		io.out(Paint("dim", L["      Ctrl+R searches your history (again: an older one; Enter runs it, Right or Tab edits it, Esc lets go)"]))
		io.out(Paint("dim", L["      Ctrl+B [: this pane's scrollback in the pager (/ or ? searches it); cmd | less: all of a long answer"]))
		io.out(Paint("dim", L["      z words: the folder you go to most with them   prompt: how the prompt looks   theme: the colours"]))
		io.out(Paint("dim", L["      Ctrl+= / Ctrl+- this pane's text size (Ctrl+0: the default), or the font command (font -a: every pane)"]))
		return 0
	end,
})

SH.Command("man", {
	desc = L["more on a command"],
	usage = "man command",
	args = "cmd",
	run = function(io)
		local name = io.args[1]
		if not name then io.err(L["What manual page do you want?"]) return 1 end
		local def = SH.Find(name)
		if not def then io.err(L["No manual entry for %s"]:format(SH.Literal(name))) return 16 end
		io.out(Paint("white", "NAME"))
		io.out("    " .. Paint("green", def.name) .. " - " .. SH.Literal(def.desc or ""))
		io.out(Paint("white", "SYNOPSIS"))
		io.out("    " .. SH.Literal(def.terminal and ("." .. def.name .. " [args]") or Synopsis(def)))
		if def.man then
			io.out(Paint("white", "DESCRIPTION"))
			for _, l in ipairs(def.man) do io.out("    " .. SH.Literal(l)) end
		end
		local aliases = def.aliases or (def.terminal and def.terminal.aliases)
		if aliases and #aliases > 0 then
			io.out(Paint("white", "ALSO"))
			io.out("    " .. SH.Literal(table.concat(aliases, ", ")))
		end
		return 0
	end,
})

SH.Command("which", {
	desc = L["where a command lives"],
	usage = "which command...",
	aliases = { "type", "whereis" },
	args = "cmd",
	run = function(io)
		local status = 0
		for _, name in ipairs(io.args) do
			local def = SH.Find(name)
			if not def then io.err(L["no %s"]:format(SH.Literal(name))) status = 1
			elseif def.alias then
				io.out(SH.Literal(name) .. L[" is aliased to "] .. Paint("yellow", "'" .. SH.Literal(def.alias) .. "'"))
			elseif io.name == "type" then
				io.out(SH.Literal(name) .. (def.terminal and L[" is a Terminal command"] or L[" is a shell builtin"]))
			else io.out("/bin/" .. def.name) end
		end
		return status
	end,
})

SH.Command("alias", {
	desc = L["name a command line: alias near='ls -lN /npc | where' (then: near title~reagent); kept between sessions"],
	usage = "alias [name='text' ...] [name]",
	man = { L["With nothing: every alias. name: that one. name='text': sets it (quote the text)."],
		L["An alias is its text put where its name is typed first in a command; the words after it stay:"],
		L["alias near='ls -lN /npc | where'      near title~reagent | head -3      unalias near"] },
	run = function(io)
		local aliases = SH.Aliases()
		if #io.args == 0 then
			local names = {}
			for n in pairs(aliases) do names[#names + 1] = n end
			table.sort(names)
			for _, n in ipairs(names) do io.out(Paint("green", "alias ") .. n .. "=" .. Paint("yellow", "'" .. SH.Literal(aliases[n]) .. "'")) end
			return 0
		end
		local status = 0
		for _, a in ipairs(io.args) do
			local name, text = a:match("^([^=%s]+)=(.*)$")
			if name then
				name = Lower(name)
				if text:match("^%s*$") then io.err(L["an alias needs some text"]) status = 1
				else aliases[name] = text end -- (it may stand in for a command, as in bash: alias ls='ls -l')
			else
				local t = aliases[Lower(a)]
				if t then io.out(Paint("green", "alias ") .. Lower(a) .. "=" .. Paint("yellow", "'" .. SH.Literal(t) .. "'"))
				else io.err(L["%s: not found"]:format(SH.Literal(a))) status = 1 end
			end
		end
		return status
	end,
})

SH.Command("unalias", {
	desc = L["forget an alias (unalias -a: all of them)"],
	usage = "unalias [-a] name...",
	run = function(io)
		local aliases = SH.Aliases()
		if io.args[1] == "-a" then
			for k in pairs(aliases) do aliases[k] = nil end
			return 0
		end
		if #io.args == 0 then io.err(L["usage: unalias [-a] name..."]) return 2 end
		local status = 0
		for _, a in ipairs(io.args) do
			if aliases[Lower(a)] then aliases[Lower(a)] = nil
			else io.err(L["%s: not found"]:format(SH.Literal(a))) status = 1 end
		end
		return status
	end,
})

SH.Command("whoami", { desc = L["your name here"], run = function(io) io.out(FS.User()) return 0 end })
SH.Command("hostname", { desc = L["this machine's name (your realm)"], run = function(io) io.out(FS.Host()) return 0 end })

SH.Command("uname", {
	desc = L["what this system is (-a: all of it)"],
	usage = "uname [-a]",
	run = function(io)
		local v, build = "?", "?"
		if _G.GetBuildInfo then v, build = _G.GetBuildInfo() end
		if io.args[1] == "-a" then
			io.out(("Forever %s %s-terminal-%s #%s %s"):format(FS.Host(), tostring(v), tostring(ns.version), tostring(build), _VERSION or "Lua"))
		else io.out("Forever") end
		return 0
	end,
})

SH.Command("date", {
	desc = L["the date and time (and the realm's)"],
	run = function(io)
		if date then io.out(date("%a %b %d %H:%M:%S %Y")) end
		if _G.GetGameTime then
			local h, m = _G.GetGameTime()
			if h then io.out(Paint("dim", L["realm time %02d:%02d"]:format(h, m))) end
		end
		return 0
	end,
})

SH.Command("uptime", {
	desc = L["how long you've played this session"],
	run = function(io)
		local fps = _G.GetFramerate and _G.GetFramerate() or 0
		io.out(("%s %s,  %s"):format(date and date("%H:%M:%S") or "", FS.Uptime(), L["%.0f fps"]:format(fps)))
		return 0
	end,
})

SH.Command("ping", {
	desc = L["how far the realm is: your latency"],
	run = function(io)
		local home, world = 0, 0
		if _G.GetNetStats then
			local _, _, h, w = _G.GetNetStats()
			home, world = h or 0, w or 0
		end
		local host = FS.Host()
		io.out(L["PING %s: 64 bytes from %s: time=%d ms (world %d ms)"]:format(host, host, home, world))
		return 0
	end,
})

SH.Command("free", {
	desc = L["memory: the game's Lua and Terminal's"],
	run = function(io)
		local node = FS.Resolve("/", "/proc/meminfo")
		for _, l in ipairs(node and FS.Content(node) or {}) do io.out(l) end
		return 0
	end,
})

--- A count as df -h writes it: 31k, 1.2k, 950.
local function Human(n)
	if not n then return "-" end
	if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
	if n >= 10000 then return ("%dk"):format(math.floor(n / 1000 + 0.5)) end
	if n >= 1000 then return ("%.1fk"):format(n / 1000) end
	return tostring(n)
end

SH.Command("df", {
	desc = L["the other addons Terminal reads, as mounted filesystems: how many rows each has, how many are ready"],
	usage = "df [-ha]",
	man = { L["Size: the rows an addon's lists hold; Used: those ready (AtlasLoot's still waiting on their names aren't);"],
		L["- when no list of it is made yet. -h: 31k, not 31000. -a: the ones not installed too."] },
	run = function(io)
		local opts, rest = SH.Opts(io.args, "ha")
		if not opts then io.err(rest) return 2 end
		local function N(n) return opts.h and Human(n) or (n and tostring(n) or "-") end
		io.out(Paint("dim", "Filesystem\tSize\tUsed\tAvail\tUse%\tMounted on"))
		for _, mt in ipairs(FS.Mounts()) do
			if mt.source or opts.a then
				local pct = (mt.size and mt.size > 0) and (math.floor(mt.used / mt.size * 100 + 0.5) .. "%") or "-"
				local avail = mt.size and (mt.size - mt.used) or nil
				local where = #mt.points > 0 and table.concat(mt.points, " ") or "none"
				local name = mt.source or (mt.m.names[1] .. " (" .. (mt.note or L["not installed"]) .. ")")
				io.out(("%s\t%s\t%s\t%s\t%s\t%s"):format(mt.source and Paint("green", SH.Literal(name)) or Paint("dim", SH.Literal(name)),
					Count(N(mt.size)), Count(N(mt.used)), Count(N(avail)), Paint("yellow", pct), Paint("blue", SH.Literal(where))))
			end
		end
		return 0
	end,
})

SH.Command("mount", {
	desc = L["the other addons Terminal reads, as mounts: which, where, how"],
	usage = "mount",
	run = function(io)
		local any = false
		for _, mt in ipairs(FS.Mounts()) do
			if mt.source then
				local points = #mt.points > 0 and mt.points or { "none" }
				for _, pt in ipairs(points) do
					io.out(("%s on %s type %s (%s)"):format(Paint("green", SH.Literal(mt.source)), Paint("blue", SH.Literal(pt)),
						Paint("cyan", mt.m.type), mt.opts))
					any = true
				end
			end
		end
		if not any then io.out(Paint("dim", L["nothing mounted: no addon Terminal reads is loaded"])) end
		return 0
	end,
})

SH.Command("umount", {
	desc = L["(the addons stay)"],
	usage = "umount mountpoint",
	hidden = true,
	run = function(io)
		local target = io.args[1]
		if not target then io.err(L["usage: umount mountpoint"]) return 1 end
		local node = FS.Resolve(io.sh.cwd, target)
		local path = node and node.path or target
		for _, mt in ipairs(FS.Mounts()) do
			for _, pt in ipairs(mt.points) do
				if mt.source and pt == path then
					io.err(L["%s: target is busy (%s is using it)"]:format(SH.Literal(path), SH.Literal(mt.source)))
					return 32
				end
			end
		end
		io.err(L["%s: not mounted"]:format(SH.Literal(path)))
		return 32
	end,
})

SH.Command("sleep", {
	desc = L["wait N seconds (Ctrl+C stops it)"],
	usage = "sleep seconds",
	run = function(io)
		local s = tonumber(io.args[1])
		if not s then io.err(L["missing operand"]) return 1 end
		io.sh:Sleep(math.min(s, 3600))
		return 0
	end,
})

SH.Command("true", { desc = L["do nothing, successfully"], run = function() return 0 end })
SH.Command("false", { desc = L["do nothing, unsuccessfully"], run = function() return 1 end })

--- rm's words: whether they ask for everything (-r, and / or ~ or every list: /* already turned into them).
local function EverythingAsked(args)
	local recursive, paths, root = false, 0, false
	for _, a in ipairs(args) do
		if a:match("^%-%a*[rR]") or a == "--recursive" then recursive = true
		elseif a:sub(1, 1) ~= "-" then
			paths = paths + 1
			if a == "/" or a == "~" or a == "/*" or a == "~/" then root = true end
		end
	end
	if recursive and not root and paths > 0 and paths >= #(FS.Dirs()) then root = true end -- (/* expanded)
	return recursive and root
end
SH.EverythingAsked = EverythingAsked

SH.Command("sudo", {
	desc = L["no"],
	run = function(io)
		-- (an easter egg: sudo rm -rf / "removes" everything; nothing is, the console goes)
		if Lower(io.args[1] or "") == "rm" then
			local rest = {}
			for i = 2, #io.args do rest[#rest + 1] = io.args[i] end
			if EverythingAsked(rest) then
				for i, d in ipairs(FS.Dirs()) do
					io.out(Paint("red", L["removed directory '/%s'"]:format(d.name)))
					if i % 6 == 0 then io.sh:Sleep(0.05) end
				end
				io.sh:Sleep(0.3)
				local ui = io.sh.ui
				if ui and ui.Wipe then ui.Wipe(io.sh) end
				return 0
			end
		end
		io.err(L["%s is not in the sudoers file. This incident will be reported."]:format(FS.User()))
		return 1
	end,
})

local function ReadOnly(io)
	io.err(L["Read-only file system (only /tmp can be written: cmd > /tmp/name)"])
	return 1
end
SH.Command("touch", {
	desc = L["make an empty file in /tmp"],
	usage = "touch /tmp/name",
	run = function(io)
		for _, a in ipairs(io.args) do
			local target = WriteTarget(io.sh, a)
			if not target then return ReadOnly(io) end
			if not FS.tmp[Lower(target)] then SH.Write(target, {}) end
		end
		return 0
	end,
})
-- (rm -rf / is GNU rm's refusal; with sudo, an easter egg: sudo's, above)
SH.Command("rm", {
	desc = L["remove files from /tmp"],
	usage = "rm /tmp/name...",
	args = "path",
	run = function(io)
		if EverythingAsked(io.args) then
			io.err(L["it is dangerous to operate recursively on '/'"])
			io.err(L["use --no-preserve-root to override this failsafe"])
			return 1
		end
		local _, rest = SH.Opts(io.args, "rf")
		for _, a in ipairs(rest or {}) do
			local target = WriteTarget(io.sh, a)
			if not target then return ReadOnly(io) end
			if not FS.tmp[Lower(target)] then io.err(L["cannot remove '%s': No such file or directory"]:format(SH.Literal(a)))
			else FS.tmp[Lower(target)] = nil end
		end
		return 0
	end,
})
SH.Command("mkdir", { desc = L["(the world is read-only)"], run = ReadOnly })
SH.Command("vim", {
	desc = L["(the world is read-only)"],
	aliases = { "vi", "nano", "emacs" },
	run = function(io)
		io.err(L["E45: 'readonly' option is set. (Good news: no :q to remember.)"])
		return 1
	end,
})

----------------------------------------------------------------------
-- Searching as Terminal does
----------------------------------------------------------------------

--- A search's rows as paths: "/kind/name   detail".
SH.Command("search", {
	desc = L["Terminal's own search, in words or Advanced (search nearest innkeeper; ask what killed me)"],
	usage = "search words...",
	aliases = { "ask", "?" },
	run = function(io)
		local text = table.concat(io.args, " ")
		if text == "" then io.err(L["say what to look for"]) return 1 end
		local UI = ns.UI
		if not (UI and UI.SearchText) then io.err(L["the search isn't ready"]) return 1 end
		local saved = UI.sliceUntil
		UI.sliceUntil = nil -- (searched straight through: never a yield from inside it)
		local ok, res = pcall(UI.SearchText, UI, text)
		UI.sliceUntil = saved
		if not ok then io.err(tostring(res)) return 1 end
		local n = 0
		for _, e in ipairs(res or {}) do
			if type(e) == "table" and not e.noActivate and e.kind then
				local d = FS.DirOf(e.kind)
				local path = d and FS.PathOf(d, e)
				local detail = e.detail and FS.Strip(e.detail) or ""
				if d and path then
					local dir, name = path:match("^(.*/)(.-)$")
					io.out(Link(path, Paint("dim", SH.Literal(dir)) .. Painted(d, name)) .. (detail ~= "" and ("  " .. Paint("dim", SH.Literal(detail))) or ""))
				else
					-- (a row that leads to another search, "what should i do"'s: that search, to type next)
					local nextSearch = type(e.searchText) == "string" and e.searchText ~= "" and e.searchText or nil
					io.out(SH.Literal(FS.Clean(e.name)) .. (detail ~= "" and ("  " .. Paint("dim", SH.Literal(detail))) or "")
						.. (nextSearch and ("  " .. SH.SearchLink(nextSearch, Paint("cyan", "→ search " .. SH.Literal(nextSearch)))) or ""))
				end
				n = n + 1
			elseif type(e) == "table" and e.noActivate and e.name then
				io.out(Paint("dim", SH.Literal(FS.Strip(e.name))))
			end
		end
		if UI.answerNote then
			-- (the panel's "Enter searches for it": here, the → search each row says)
			local note = FS.Strip(UI.answerNote)
			local enter = L["Enter searches for it"]
			local at = note:find(enter, 1, true)
			if at then note = note:sub(1, at - 1):gsub("[%s·]+$", "") end
			if note ~= "" then io.out(Paint("dim", SH.Literal(note))) end
		end
		return n > 0 and 0 or 1
	end,
})

--- How a row is pinned on the map, or nil: an NPC (Questie's spawn), a spot row (a mailbox, a flight master, an
--- entrance: its own map and place), a map row (a zone: the waypoint moves there).
function SH.PinOf(e)
	local I, M = ns.Integrations, ns.Maps
	if type(e) ~= "table" or e.special then return nil end
	if e.kind == "npc" and I and I.NpcPin then return I.NpcPin end
	if e.ui and e.px and e.py and I and I.PinObject then return I.PinObject end
	if e.mapID and M and M.PinOnly and (e.kind == "maps" or e.pos) then return M.PinOnly end
	return nil
end

SH.Command("pin", {
	desc = L["a map waypoint on a file: an NPC, a mailbox, a flight master, an entrance, a zone (pin -c clears it)"],
	usage = "pin [-c] file",
	man = { L["The waypoint and the arrow to it, as Enter or Shift+Enter in Terminal sets them. One waypoint at a time:"],
		L["given several files (xargs), the first that has a place. -c clears the waypoint."],
		L["ls -lN /npc | where title~reagent | head -1 | field path | xargs pin"] },
	aliases = { "waypoint", "way" },
	args = "path",
	run = function(io)
		local opts, rest = SH.Opts(io.args, "c")
		if not opts then io.err(rest) return 2 end
		if opts.c then
			if _G.C_Map and _G.C_Map.ClearUserWaypoint then pcall(_G.C_Map.ClearUserWaypoint) end
			io.out(Paint("dim", L["waypoint cleared"]))
			return 0
		end
		if #rest == 0 then io.err(L["say what to pin (pin /mailbox/<name>, or xargs pin)"]) return 1 end
		for _, path in ipairs(PathArgs(io, rest)) do
			local node, err = Resolve(io, path)
			if not node then io.err(SH.Literal(path) .. ": " .. err)
			elseif node.kind == "file" then
				local how = SH.PinOf(node.e)
				if how then
					local lines = SH.Capture(how, node.e)
					for _, l in ipairs(lines) do io.out(l) end
					return 0
				end
				io.err(SH.Literal(path) .. ": " .. L["no place on the map"])
			else
				io.err(SH.Literal(path) .. ": " .. L["Is a directory"])
			end
		end
		return 1
	end,
})

SH.Command("link", {
	desc = L["put a file's link in the chat box"],
	usage = "link file",
	args = "path",
	run = function(io)
		local path = PathArgs(io, io.args)[1]
		local node, err = path and Resolve(io, path)
		if not node then io.err(err or L["missing operand"]) return 1 end
		if node.kind ~= "file" or node.e.special then io.err(L["no link"]) return 1 end
		local e = node.e
		local text = ns.Share and ns.Share.Text and select(2, pcall(ns.Share.Text, e)) or nil
		if type(text) ~= "string" or text == "" then
			text = e.link or (type(e.getLink) == "function" and select(2, pcall(e.getLink, e))) or FS.Clean(e.name)
		end
		if ns.LinkInChat then ns.LinkInChat(text) end
		io.out(Paint("dim", L["in the chat box: "]) .. tostring(text))
		return 0
	end,
})

----------------------------------------------------------------------
-- Fun
----------------------------------------------------------------------

SH.FORTUNES = {
	L["The fish you didn't catch was a Mr. Pinchy."],
	L["Always check the vendor before you hearth."],
	L["A green today is a grey tomorrow. Vendor wisely."],
	L["Your bags are full. They were always going to be full."],
	L["The flight path you need is the one you haven't found."],
	L["Somewhere, a rogue is standing behind you. Not now. But soon."],
	L["A shaman who forgets to drop totems is just a person in mail."],
	L["Linen Cloth: humble beginnings for great bandages."],
	L["Repair bills are the taxes of the brave."],
	L["You will meet a tall stranger. It is a tauren. It is always a tauren."],
	L["grep finds what the bags hide."],
	L["There is no cow level. There is, however, Mulgore."],
	L["The best mount is the one you're on when the boss enrages."],
	L["A quest log at 25/25 is a cry for help."],
}

SH.Command("fortune", {
	desc = L["a word of wisdom"],
	run = function(io)
		io.out(Paint("yellow", SH.Literal(SH.FORTUNES[math.random(#SH.FORTUNES)])))
		return 0
	end,
})

SH.Command("murlocsay", {
	desc = L["a murloc says it (murlocsay text, or pipe something in)"],
	usage = "murlocsay [words...]",
	aliases = { "cowsay" },
	run = function(io)
		local text = table.concat(io.args, " ")
		if text == "" and io.stdin then
			local parts = {}
			for _, l in ipairs(io.stdin) do parts[#parts + 1] = Strip(l) end
			text = table.concat(parts, " ")
		end
		if text == "" then text = L["Mrglglglgl!"] end
		if #text > 60 then text = text:sub(1, 57) .. "..." end
		local bar = string.rep("-", #text + 2)
		io.out(" " .. string.rep("_", #text + 2))
		io.out("< " .. SH.Literal(text) .. " >")
		io.out(" " .. bar)
		io.out(Paint("green", "      \\   .--."))
		io.out(Paint("green", "       \\ ( o o )~"))
		io.out(Paint("green", "         /  V  \\"))
		io.out(Paint("green", "        (( mrgl ))"))
		io.out(Paint("green", "         ^^   ^^"))
		return 0
	end,
})

--- An art line: `art` drawn a fixed width a character in the console (`cols` slots, whatever its length: the lines of
--- one picture line up), then `rest`. Piped or printed elsewhere: the plain text.
function SH.Mono(art, cols, rest)
	art = art or ""
	return "|Htshm:" .. #art .. ":" .. (cols or 0) .. "|h|h" .. art .. (rest or "")
end

-- neofetch's logo: your class's picture, each line { text, colours }: a letter a character, painted from
-- SH.FETCH_PAINT ("c" the class's colour, " " nothing). Both as long as each other (a test checks).
SH.FETCH_LOGOS = {
	WARRIOR = {
		{ [=[            /\]=], "            ss" },
		{ [=[           /||\]=], "           ssss" },
		{ [=[           ||||]=], "           ssss" },
		{ [=[           ||||]=], "           ssss" },
		{ [=[           ||||]=], "           ssss" },
		{ [=[      .----||||----.]=], "      cccccssssccccc" },
		{ [=[     /     ||||     \]=], "     c     ssss     c" },
		{ [=[    |      ||||      |]=], "    c      ssss      c" },
		{ [=[    |      ||||      |]=], "    c      ssss      c" },
		{ [=[    |   ===[##]===   |]=], "    c   gggggggggg   c" },
		{ [=[     \      ||      /]=], "     c      bb      c" },
		{ [=[      '.    ()    .']=], "      cc    gg    cc" },
		{ [=[        '-.____.-']=], "        cccccccccc" },
	},
	PALADIN = {
		{ [=[    .    \   |   /    .]=], "    w    g   g   g    w" },
		{ [=[      *   \  |  /   *]=], "      w   g  g  g   w" },
		{ [=[   \    .-''''''''-.    /]=], "   g    cccccccccccc    g" },
		{ [=[  -- = |############| = --]=], "  gg g cssssssssssssc g gg" },
		{ [=[  -- = |############| = --]=], "  gg g cssssssssssssc g gg" },
		{ [=[   /    '-.______.-'    \]=], "   g    cccccccccccc    g" },
		{ [=[      *      ||      *]=], "      w      bb      w" },
		{ [=[    .        ||        .]=], "    w        bb        w" },
		{ [=[             ||]=], "             bb" },
		{ [=[             ||]=], "             bb" },
		{ [=[             ||]=], "             bb" },
		{ [=[            (__)]=], "            gggg" },
	},
	HUNTER = {
		{ [=[      |`.]=], "      wcc" },
		{ [=[      |  `.]=], "      w  cc" },
		{ [=[      |    \]=], "      w    c" },
		{ [=[      |     \]=], "      w     c" },
		{ [=[      |      )]=], "      w      c" },
		{ [=[ >>---+------|------>]=], " llbbbbbbbbbbcbbbbbbs" },
		{ [=[      |      )]=], "      w      c" },
		{ [=[      |     /]=], "      w     c" },
		{ [=[      |    /]=], "      w    c" },
		{ [=[      |  .']=], "      w  cc" },
		{ [=[      |.']=], "      wcc" },
	},
	ROGUE = {
		{ [=[                      _.]=], "                      sw" },
		{ [=[                   / / /]=], "                   s w s" },
		{ [=[                  / / /]=], "                  s w s" },
		{ [=[                 / / /]=], "                 s w s" },
		{ [=[                / / /]=], "                s w s" },
		{ [=[               / / /]=], "               s w s" },
		{ [=[              / / /]=], "              s w s" },
		{ [=[         o   / / /]=], "         g   s w s" },
		{ [=[          \\/ / /]=], "          ggs w s" },
		{ [=[            \=\]=], "            ggg" },
		{ [=[           /#/ \\]=], "           bbb gg" },
		{ [=[          /#/    o]=], "          bbb    g" },
		{ [=[         /#/]=], "         bbb" },
		{ [=[       (@)]=], "       gcg" },
	},
	PRIEST = {
		{ [=[        .   *   .]=], "        w   w   w" },
		{ [=[     *  .-'''''-.  *]=], "     w  wcccccccw  w" },
		{ [=[       / .-'''-. \]=], "       c ccccccc c" },
		{ [=[      | |  /^\  | |]=], "      c c  nnn  c c" },
		{ [=[      | | < * > | |]=], "      c c n w n c c" },
		{ [=[      | |  \v/  | |]=], "      c c  nnn  c c" },
		{ [=[       \ '-----' /]=], "       c ccccccc c" },
		{ [=[  ~~~~~~'-.| |.-'~~~~~~]=], "  nnnnnncccc ccccnnnnnn" },
		{ [=[   ~~~~~   | |   ~~~~~]=], "   nnnnn   c c   nnnnn" },
		{ [=[           |o|]=], "           cnc" },
		{ [=[           | |]=], "           c c" },
		{ [=[           | |]=], "           c c" },
		{ [=[           |o|]=], "           cnc" },
		{ [=[           | |]=], "           c c" },
		{ [=[           |_|]=], "           ccc" },
	},
	SHAMAN = {
		{ [=[         .--.    .-.]=], "         cccc    ccc" },
		{ [=[      .-(    )--(   )-.]=], "      ccc    cccc   ccc" },
		{ [=[     (    .__    __.   )]=], "     c    ccc    ccc   c" },
		{ [=[      '--(___)--(___)-']=], "      ccccccccccccccccc" },
		{ [=[             /  /]=], "             g  g" },
		{ [=[            /  /__]=], "            g  gww" },
		{ [=[           /__   /]=], "           gww   g" },
		{ [=[             /  /]=], "             g  g" },
		{ [=[            / ,']=], "            g gg" },
		{ [=[           /,']=], "           ggg" },
		{ [=[          '']=], "          gg" },
		{ [=[     .  '  .  '  .  ']=], "     n  n  n  n  n  n" },
	},
	MAGE = {
		{ [=[              __]=], "              cc" },
		{ [=[             /  `.]=], "             c  cc" },
		{ [=[            /  .-'   *]=], "            c  ccc   g" },
		{ [=[      *    /  /]=], "      g    c  c" },
		{ [=[          / *  \       .]=], "          c g  c       w" },
		{ [=[    .    /  .   \]=], "    w    c  w   c" },
		{ [=[        /     *  \    *]=], "        c     g  c    g" },
		{ [=[   *   /  ()      \]=], "   g   c  ww      c" },
		{ [=[      /____________\]=], "      cccccccccccccc" },
		{ [=[     |=<>==[##]==<>=|]=], "     cnggnnggggnnggnc" },
		{ [=[  .--'______________'--.]=], "  nnnnnnnnnnnnnnnnnnnnnn" },
		{ [=[ (______________________)]=], " nnnnnnnnnnnnnnnnnnnnnnnn" },
		{ [=[     *     .      *]=], "     g     w      g" },
	},
	WARLOCK = {
		{ [=[    (   )  (    )   (]=], "    f   f  f    f   f" },
		{ [=[   ) ( ( )  ) (  ) ) )]=], "   f f f f  f f  f f f" },
		{ [=[     ,   ,   ,   ,]=], "     w   w   w   w" },
		{ [=[    /|  /|  /|  /|]=], "    ww  ww  ww  ww" },
		{ [=[   | | | | | | | |]=], "   c c c c c c c c" },
		{ [=[   | | | | | | | |   ,]=], "   c c c c c c c c   w" },
		{ [=[   | |_| |_| |_| |  /|]=], "   c ccc ccc ccc c  ww" },
		{ [=[   |               |/ /]=], "   c               cc c" },
		{ [=[   |   .-'''''-.     /]=], "   c   ccccccccc     c" },
		{ [=[   |  (  (@@)  )    /]=], "   c  c  cffc  c    c" },
		{ [=[    \  '-.___.-'   /]=], "    c  ccccccccc   c" },
		{ [=[     \            /]=], "     c            c" },
		{ [=[      |          |]=], "      c          c" },
		{ [=[      |__________|]=], "      cccccccccccc" },
	},
	DRUID = {
		{ [=[        .-~~~~~-.]=], "        lllllllll" },
		{ [=[     .-~  @   *  ~-.]=], "     lll  c   g  lll" },
		{ [=[   .~   *    @     *~.]=], "   ll   g    c     gll" },
		{ [=[  (   @   .~~~.   @   )]=], "  l   c   lllll   c   l" },
		{ [=[   '~.  *(     ) *  .~']=], "   lll  gl     l g  lll" },
		{ [=[      '-.~ | | ~.-']=], "      llll b b llll" },
		{ [=[           | |]=], "           b b" },
		{ [=[           | |]=], "           b b" },
		{ [=[          /| |\]=], "          bb bb" },
		{ [=[      ___/ / \ \___]=], "      bbbb b b bbbb" },
	},
}
SH.FETCH_LOGOS.OTHER = {
	{ [[   _______]], "   ccccccc" },
	{ [[  |__   __|]], "  ccc   ccc" },
	{ [[     | |  >_]], "     c c  gg" },
	{ [[     | |]], "     c c" },
	{ [[     |_|]], "     ccc" },
}
SH.FETCH_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
SH.FETCH_COLS = 26
SH.FETCH_PAINT = { g = "e0af68", s = "c0caf5", b = "a0703c", w = "ffffff", r = "f7768e", f = "9ece6a", l = "6fbf4a",
	n = "7aa2f7", d = "565f89" }
-- (the classic class colours, for a client without RAID_CLASS_COLORS)
SH.FETCH_CLASS_HEX = {
	WARRIOR = "c79c6e", PALADIN = "f58cba", HUNTER = "abd473", ROGUE = "fff569", PRIEST = "ffffff",
	SHAMAN = "0070de", MAGE = "69ccf0", WARLOCK = "9482c9", DRUID = "ff7d0a", OTHER = "7dcfff",
}
-- (the two rows of colour blocks every fetch ends with: the palette, then its bright half)
SH.FETCH_BLOCKS = {
	{ "414868", "f7768e", "9ece6a", "e0af68", "7aa2f7", "bb9af7", "7dcfff", "a9b1d6" },
	{ "565f89", "ff899d", "b9f27c", "ffc777", "8db0ff", "c7a9ff", "a4daff", "c0caf5" },
}

local function Hex(hex, s) return "|cff" .. hex .. s .. "|r" end
local function Try(f, ...)
	if type(f) ~= "function" then return nil end
	local ok, a, b = pcall(f, ...)
	if ok then return a, b end
end

--- A logo line painted: each run of one colour letter in its colour (the class's for "c").
function SH.FetchArt(text, mask, accent)
	local out, i = {}, 1
	while i <= #text do
		local m = mask:sub(i, i)
		local j = i
		while j < #text and mask:sub(j + 1, j + 1) == m do j = j + 1 end
		local run = SH.Literal(text:sub(i, j))
		local hex = (m ~= " " and m ~= "") and (m == "c" and accent or SH.FETCH_PAINT[m] or accent) or nil
		out[#out + 1] = hex and Hex(hex, run) or run
		i = j + 1
	end
	return table.concat(out)
end

--- The class a word names (WARRIOR, "mage", "pal", the game's own name for it), or nil.
function SH.FetchClassNamed(word)
	local w = Lower(tostring(word or ""))
	if w == "" then return nil end
	local names = _G.LOCALIZED_CLASS_NAMES_MALE or {}
	for _, file in ipairs(SH.FETCH_ORDER) do
		local own = type(names[file]) == "string" and Lower(names[file]) or nil
		if w == file:lower() or w == own or (#w >= 3 and (file:lower():sub(1, #w) == w or (own and own:sub(1, #w) == w))) then
			return file
		end
	end
	return nil
end

--- The class shown (`want`, else yours when there's art for it, else "OTHER") and its colour (6 hex digits).
function SH.FetchClass(want)
	local file = want
	if not file then
		local _, mine = Try(_G.UnitClass, "player")
		file = mine
	end
	if not (type(file) == "string" and SH.FETCH_LOGOS[file]) then file = "OTHER" end
	local hex = ns.ClassHex and file ~= "OTHER" and ns.ClassHex(file)
	hex = type(hex) == "string" and hex:match("(%x%x%x%x%x%x)$") or SH.FETCH_CLASS_HEX[file]
	return file, hex
end

--- "2 hours, 13 mins", as neofetch says it.
function SH.FetchUptime(t)
	t = math.floor(tonumber(t) or 0)
	local d, h, m = math.floor(t / 86400), math.floor(t % 86400 / 3600), math.floor(t % 3600 / 60)
	local parts = {}
	if d > 0 then parts[#parts + 1] = (d == 1 and L["%d day"] or L["%d days"]):format(d) end
	if h > 0 then parts[#parts + 1] = (h == 1 and L["%d hour"] or L["%d hours"]):format(h) end
	if m > 0 or #parts == 0 then parts[#parts + 1] = (m == 1 and L["%d min"] or L["%d mins"]):format(m) end
	return table.concat(parts, ", ")
end

--- neofetch's lines, { key, value }: the system's, nothing about the character.
function SH.FetchInfo()
	local out = {}
	local function Add(k, v) if v ~= nil and v ~= "" then out[#out + 1] = { k, tostring(v) } end end
	local v, build = Try(_G.GetBuildInfo)
	Add("OS", "World of Warcraft Forever " .. tostring(v or "?"))
	local realm = Try(_G.GetRealmName)
	if realm and not (ns.Secret and ns.Secret(realm)) then Add("Host", SH.Literal(realm)) end
	Add("Kernel", "Terminal " .. tostring(ns.version or "?") .. " (" .. tostring(build or "?") .. ")")
	Add("Uptime", SH.FetchUptime(FS.SessionSeconds()))
	local A = _G.C_AddOns
	local n = A and Try(A.GetNumAddOns)
	if type(n) == "number" then
		local loaded = 0
		for i = 1, n do if Try(A.IsAddOnLoaded, i) then loaded = loaded + 1 end end
		Add("Packages", L["%d (addons), %d (loaded)"]:format(n, loaded))
	end
	local pw, ph = Try(_G.GetPhysicalScreenSize)
	if not (tonumber(pw) and tonumber(pw) > 0) then pw, ph = Try(_G.GetScreenWidth), Try(_G.GetScreenHeight) end
	if tonumber(pw) and tonumber(ph) then Add("Resolution", math.floor(pw + 0.5) .. "x" .. math.floor(ph + 0.5)) end
	Add("Locale", Try(_G.GetLocale))
	return out
end

SH.Command("neofetch", {
	desc = L["you and this system, at a glance"],
	usage = "neofetch [-n] [-c class]",
	man = { L["-c CLASS  that class's picture and colours (warrior, mage, pal...)"],
		L["-n  the next class's picture each time it's run, round all nine"] },
	aliases = { "fetch", "screenfetch" },
	run = function(io)
		local opts, rest = SH.Opts(io.args, "nc:")
		if not opts then io.err(rest) return 2 end
		local want
		if opts.c then
			want = SH.FetchClassNamed(opts.c)
			if not want then
				local names = {}
				for i, f in ipairs(SH.FETCH_ORDER) do names[i] = f:lower() end
				io.err(L["no picture for %s: %s"]:format(SH.Literal(opts.c), table.concat(names, " ")))
				return 1
			end
		elseif opts.n then
			local at = SH.fetchAt
			if not at then
				local mine = SH.FetchClass()
				at = 0
				for i, f in ipairs(SH.FETCH_ORDER) do if f == mine then at = i end end
			end
			at = at % #SH.FETCH_ORDER + 1
			SH.fetchAt = at
			want = SH.FETCH_ORDER[at]
		end
		local file, accent = SH.FetchClass(want)
		local user, host = FS.User(), FS.Host()
		local right = {
			Hex(accent, SH.Literal(user)) .. "@" .. Hex(accent, SH.Literal(host)),
			Paint("dim", string.rep("-", #user + #host + 1)),
		}
		for _, kv in ipairs(SH.FetchInfo()) do right[#right + 1] = Hex(accent, kv[1]) .. ": " .. kv[2] end
		right[#right + 1] = ""
		for _, row in ipairs(SH.Blocks()) do
			local b = {}
			for _, hex in ipairs(row) do b[#b + 1] = Hex(hex, "###") end
			right[#right + 1] = table.concat(b, "")
		end
		local logo = SH.FETCH_LOGOS[file]
		for i = 1, math.max(#logo, #right) do
			local l = logo[i]
			io.out(SH.Mono(l and SH.FetchArt(l[1], l[2], accent) or "", SH.FETCH_COLS, right[i] or ""))
		end
		return 0
	end,
})

----------------------------------------------------------------------
-- Panes, layouts, jobs (the console's; nothing without one)
----------------------------------------------------------------------

local function UI(io, what)
	local ui = io.sh.ui
	if not (ui and ui[what]) then io.err(L["only in the console"]) return nil end
	return ui
end

SH.Command("split", {
	desc = L["a new pane beside this one (Ctrl+N; up to 4)"],
	aliases = { "tmux", "new" },
	run = function(io) local ui = UI(io, "Split") if ui then return ui.Split(io.sh) and 0 or 1 end return 1 end,
})

SH.Command("exit", {
	desc = L["close this pane (Ctrl+W; the last one closes the console)"],
	aliases = { "logout", "quit" },
	run = function(io) local ui = UI(io, "ClosePane") if ui then ui.ClosePane(io.sh) end return 0 end,
})

SH.Command("layout", {
	desc = L["how the panes are tiled: tile (each split halves its pane; drag the gaps), grid, tall, wide, mono (Ctrl+Space: the next one)"],
	usage = "layout [tile|grid|tall|wide|mono]",
	run = function(io)
		local ui = UI(io, "Layout")
		if not ui then return 1 end
		local ok, now = ui.Layout(io.args[1])
		if not ok then io.err(L["layouts: grid, tall, wide, mono"]) return 1 end
		io.out(Paint("dim", L["layout: "]) .. Paint("cyan", now))
		return 0
	end,
})

SH.Command("font", {
	desc = L["this pane's text size: font 16, font + / font -, font reset (Ctrl+= / Ctrl+- / Ctrl+0); font -a 16: every pane's"],
	usage = "font [-a] [size|+|-|reset]",
	man = { L["Without -a: this pane only, for this session (reset: back to the default)."],
		L["-a: the default every pane takes, kept between sessions (the same as .console font N; reset: Terminal's size)."] },
	aliases = { "fontsize" },
	run = function(io)
		local ui = UI(io, "Font")
		if not ui then return 1 end
		local size, all = ui.Font(io.args, io.sh)
		if not size then io.err(all) return 1 end
		io.out(Paint("dim", L["font size: "]) .. Paint("orange", size) .. Paint("dim", all and L[" (every pane)"] or L[" (this pane)"]))
		return 0
	end,
})

-- (an easter egg, as the games are: not in help, /bin or Tab)
SH.Command("matrix", {
	desc = L["wake up, Neo (any key stops it)"],
	aliases = { "cmatrix" },
	hidden = true,
	run = function(io)
		local ui = UI(io, "Matrix")
		if not ui then return 1 end
		ui.Matrix(io.sh)
		return 0
	end,
})

SH.Command("ps", {
	desc = L["the panes and what runs in each"],
	aliases = { "jobs" },
	run = function(io)
		local ui = UI(io, "Panes")
		if not ui then return 1 end
		io.out(Paint("dim", "  PID TTY      CMD"))
		for _, p in ipairs(ui.Panes()) do
			io.out(("%5d %-8s %s"):format(p.id, "pts/" .. p.index, SH.Literal(p.what)))
		end
		return 0
	end,
})

SH.Command("kill", {
	desc = L["stop what runs in a pane (its PID from ps): a command, or an app"],
	usage = "kill pid",
	run = function(io)
		local ui = UI(io, "Kill")
		if not ui then return 1 end
		local pid = tonumber((io.args[1] or ""):match("%d+"))
		if not pid then io.err(L["usage: kill pid"]) return 1 end
		if not ui.Kill(pid, io.sh) then io.err(L["(%d) - No such process"]:format(pid)) return 1 end
		return 0
	end,
})


----------------------------------------------------------------------
-- As you type: fish's suggestion from the history, the command's usage in the status bar, Ctrl+R's search
----------------------------------------------------------------------

--- fish's autosuggestion: the rest of the newest history line that starts with what's typed, or nil.
function SH.Suggest(sh, text)
	text = tostring(text or "")
	if text:match("^%s*$") then return nil end
	local h = sh.history
	for i = #h, 1, -1 do
		local line = h[i]
		if #line > #text and line:sub(1, #text) == text then return line:sub(#text + 1) end
	end
	return nil
end

--- The command word the cursor is in (the words since the last | ; && ||), and what it runs (SH.Find), or nil.
function SH.CommandAt(line, cursor)
	line = tostring(line or "")
	local word, first = nil, true
	for _, t in ipairs(SH.Lex(line:sub(1, cursor or #line))) do
		if t.t == "op" then
			first = t.v ~= ">" and t.v ~= ">>"
			if first then word = nil end
		elseif t.t == "word" and first then
			word, first = t.v, false
		end
	end
	if not word then return nil end
	return word, SH.Find(word)
end

SH.HINT_MAX = 70 -- (characters of a command's description in the status bar)

--- The status bar's line on what's typed: the command's usage and what it does (painted), or nil.
function SH.UsageHint(line, cursor)
	local word, def = SH.CommandAt(line, cursor)
	if not def then return nil end
	local usage, desc
	if def.alias then usage, desc = Lower(word), L["alias for: "] .. def.alias
	elseif def.terminal then usage, desc = "." .. def.name, def.desc
	else usage, desc = def.usage or def.name, def.desc end
	desc = tostring(desc or "")
	if ns.Cut then desc = ns.Cut(desc, SH.HINT_MAX) end
	return Paint("cyan", SH.Literal(usage)) .. (desc ~= "" and ("  " .. Paint("dim", SH.Literal(desc))) or "")
end

--- Ctrl+R: the newest history line before index `before` (none: the whole history) holding `query` in any case, and
--- its index; nil when none does (or nothing is asked).
function SH.HistorySearch(sh, query, before)
	local lq = Lower(tostring(query or ""))
	if lq == "" then return nil end
	local h = sh.history
	for i = math.min((before or #h + 1) - 1, #h), 1, -1 do
		if Lower(h[i]):find(lq, 1, true) then return i, h[i] end
	end
	return nil
end

----------------------------------------------------------------------
-- z: the folders you go to, by frecency (zoxide's rules)
----------------------------------------------------------------------

SH.Z_AGE = 1000 -- (the ranks' sum past which every rank is aged by a tenth, as zoxide's _ZO_MAXAGE, scaled down)

local function Now() return time and time() or 0 end

--- The folders kept: path -> { r = rank, t = last visit (time()) }, kept between sessions.
function SH.ZData()
	local d = SH.Data()
	if not d then return {} end
	d.z = type(d.z) == "table" and d.z or {}
	return d.z
end

--- A folder gone to: one more visit (the root isn't kept).
function SH.ZAdd(path, now)
	if type(path) ~= "string" or path == "/" or path == "" then return end
	local z = SH.ZData()
	local e = type(z[path]) == "table" and z[path] or { r = 0 }
	e.r, e.t = (tonumber(e.r) or 0) + 1, now or Now()
	z[path] = e
	local sum = 0
	for _, x in pairs(z) do sum = sum + (tonumber(x.r) or 0) end
	if sum > SH.Z_AGE then
		for p, x in pairs(z) do
			x.r = (tonumber(x.r) or 0) * 0.9
			if x.r < 1 then z[p] = nil end
		end
	end
end

--- zoxide's frecency: the visits weighed by how long ago the last was (an hour x4, a day x2, a week x0.5, else x0.25).
function SH.ZScore(e, now)
	local age = (now or Now()) - (tonumber(e.t) or 0)
	local w = age < 3600 and 4 or age < 86400 and 2 or age < 604800 and 0.5 or 0.25
	return (tonumber(e.r) or 0) * w
end

--- The words in the path in their order (any case), the last one in the folder's own name.
function SH.ZMatches(path, words)
	local lp, at = Lower(path), 1
	for _, w in ipairs(words) do
		local _, e = lp:find(Lower(w), at, true)
		if not e then return false end
		at = e + 1
	end
	local last = words[#words]
	return not last or (lp:match("[^/]*$") or ""):find(Lower(last), 1, true) ~= nil
end

--- The folders kept that the words match, best first: { { path, score } }.
function SH.ZList(words, now)
	now = now or Now()
	local out = {}
	for path, e in pairs(SH.ZData()) do
		if type(e) == "table" and SH.ZMatches(path, words or {}) then out[#out + 1] = { path, SH.ZScore(e, now) } end
	end
	table.sort(out, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
	return out
end

local function IsFolder(node) return node and (node.kind ~= "file" or node.children) end

SH.Command("z", {
	desc = L["jump to the folder you go to most whose path has the words (zoxide)"],
	usage = "z [-l] [-x] [words...]",
	man = {
		L["Every folder cd (or z) takes you to is kept, ranked by how often and how lately (frecency)."],
		L["The words must come in the path in order, the last one in the folder's own name: z org trainer"],
		L["z alone: /   z -: the last folder   z with a real path: cd there"],
		L["-l  the folders kept that the words match, best first, with their scores"],
		L["-x  forget this folder (or the one named)"],
	},
	run = function(io)
		local opts, rest = SH.Opts(io.args, "lx")
		if not opts then io.err(rest) return 2 end
		if opts.x then
			local path = io.sh.cwd
			if #rest > 0 then
				local node = Resolve(io, table.concat(rest, " "))
				path = node and node.path or table.concat(rest, " ")
			end
			local z = SH.ZData()
			if not z[path] then io.err(SH.Literal(path) .. ": " .. L["not kept"]) return 1 end
			z[path] = nil
			return 0
		end
		if opts.l then
			for _, it in ipairs(SH.ZList(rest)) do
				io.out(Paint("dim", ("%.1f"):format(it[2])) .. "\t" .. Link(it[1], Paint("blue", SH.Literal(it[1]))))
			end
			return 0
		end
		local function Go(path)
			io.sh.prevCwd, io.sh.cwd = io.sh.cwd, path
			SH.ZAdd(path)
			return 0
		end
		if #rest == 0 then return Go("/") end
		if #rest == 1 and rest[1] == "-" then return Go(io.sh.prevCwd) end
		if #rest == 1 then -- (a real path is gone to as cd would)
			local node = FS.Resolve(io.sh.cwd, rest[1])
			if IsFolder(node) then return Go(node.path) end
		end
		for _, it in ipairs(SH.ZList(rest)) do
			if it[1] ~= io.sh.cwd then -- (as zoxide: the folder you're in isn't where you want to go)
				local node = FS.Resolve("/", it[1])
				if IsFolder(node) then return Go(node.path) end
			end
		end
		io.err("z: " .. L["no match found"])
		return 1
	end,
})

----------------------------------------------------------------------
-- The prompt: user@host:dir$ as always, or starship's way: parts in a row (where you are, your level, gold, bags...)
----------------------------------------------------------------------

SH.PROMPTS = {
	classic = false, -- (user@host:dir$)
	starship = "dir zone level gold bags took char",
	minimal = "dir char",
	full = "user dir zone level xp gold bags time took status char",
}
SH.PROMPT_ORDER = { "classic", "starship", "minimal", "full" }
SH.TOOK_MIN = 2 -- (s: a command that took longer says so in the prompt after it)
SH.PROMPT_CHAR = "\194\187" -- (») starship's ❯, which the game's fonts lack

local function Duration(s)
	s = math.floor(s + 0.5)
	if s < 60 then return s .. "s" end
	return math.floor(s / 60) .. "m" .. (s % 60) .. "s"
end

local function BagSpace()
	local CC = C_Container
	local num = CC and CC.GetContainerNumSlots or GetContainerNumSlots
	local free = CC and CC.GetContainerNumFreeSlots or GetContainerNumFreeSlots
	if type(num) ~= "function" or type(free) ~= "function" then return nil end
	local f, t = 0, 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local n = tonumber((Try(num, bag))) or 0
		local fr, kind = Try(free, bag)
		if n > 0 and (kind == nil or kind == 0) then t, f = t + n, f + (tonumber(fr) or 0) end
	end
	if t == 0 then return nil end
	return f, t
end

-- each part: its text (painted), or nil to leave it out
SH.SEGMENTS = {
	user = function() return Paint("green", SH.Literal(FS.User() .. "@" .. FS.Host())) end,
	dir = function(sh) return Paint("blue", SH.Literal(FS.Pretty(sh.cwd))) end,
	zone = function()
		local zone, sub = Try(GetRealZoneText), Try(GetSubZoneText)
		local place = (type(sub) == "string" and sub ~= "" and sub) or (type(zone) == "string" and zone ~= "" and zone)
		return place and (Paint("dim", L["in "]) .. Paint("yellow", SH.Literal(place))) or nil
	end,
	level = function()
		local lvl = tonumber((Try(UnitLevel, "player")))
		return lvl and (Paint("dim", "lvl ") .. Paint("magenta", lvl)) or nil
	end,
	xp = function()
		local x, max = tonumber((Try(UnitXP, "player"))), tonumber((Try(UnitXPMax, "player")))
		if not x or not max or max <= 0 then return nil end
		return Paint("dim", "xp ") .. Paint("magenta", math.floor(x / max * 100) .. "%")
	end,
	gold = function()
		local m = tonumber((Try(GetMoney)))
		return m and ns.Money and Paint("yellow", SH.Literal(ns.Money(m, true))) or nil
	end,
	bags = function()
		local f, t = BagSpace()
		if not f then return nil end
		return Paint("dim", L["bags "]) .. Paint(f == 0 and "red" or f <= 4 and "orange" or "green", f .. "/" .. t)
	end,
	time = function() return date and Paint("dim", date("%H:%M")) or nil end,
	took = function(sh)
		local t = tonumber(sh.took)
		return t and t >= SH.TOOK_MIN and (Paint("dim", L["took "]) .. Paint("yellow", Duration(t))) or nil
	end,
	status = function(sh)
		local s = tonumber(sh.status)
		return s and s ~= 0 and Paint("red", "[" .. s .. "]") or nil
	end,
	char = function(sh) return Paint((tonumber(sh.status) or 0) ~= 0 and "red" or "green", SH.PROMPT_CHAR) end,
}
SH.SEGMENT_ORDER = {
	{ "user", L["user@host"] }, { "dir", L["where you are"] }, { "zone", L["the game's zone (or the part of it)"] },
	{ "level", L["your level"] }, { "xp", L["your experience in this level"] }, { "gold", L["your gold"] },
	{ "bags", L["free bag slots / all of them"] }, { "time", L["the time"] },
	{ "took", L["how long the last command took (2 s or more)"] }, { "status", L["the last command's exit status, when it failed"] },
	{ "char", L["the prompt's end, red after a failure (always last)"] },
}

--- The prompt as set (prompt): a preset's name, or your own parts; nil: classic.
function SH.PromptSpec()
	local db = ns.db
	local set = db and type(db.console) == "table" and db.console.prompt
	if type(set) ~= "string" or set == "" then return nil end
	if SH.PROMPTS[set] ~= nil then return SH.PROMPTS[set] or nil end
	return set
end

--- The prompt line for a session (painted, a space at its end).
function SH.PromptLine(sh, spec)
	spec = spec or SH.PromptSpec()
	if not spec then
		return Paint("green", FS.User() .. "@" .. FS.Host()) .. Paint("dim", ":") .. Paint("blue", SH.Literal(FS.Pretty(sh.cwd)))
			.. Paint("dim", "$") .. " "
	end
	local parts = {}
	for name in spec:gmatch("%S+") do
		local f = name ~= "char" and SH.SEGMENTS[name]
		local s = f and Try(f, sh)
		if type(s) == "string" and s ~= "" then parts[#parts + 1] = s end
	end
	parts[#parts + 1] = SH.SEGMENTS.char(sh)
	return table.concat(parts, " ") .. " "
end

SH.Command("prompt", {
	desc = L["how the prompt looks: classic (user@host:dir$), starship, minimal, full, or your own parts (kept)"],
	usage = "prompt [classic|starship|minimal|full|part...]",
	man = { L["prompt dir zone gold   your own: the parts in that order (the prompt's end is always last)"] },
	run = function(io)
		local db = ns.db
		local cdb = db and (type(db.console) == "table" and db.console or {})
		if db then db.console = cdb end
		if #io.args == 0 then
			local now = cdb and cdb.prompt or "classic"
			io.out(Paint("dim", L["now: "]) .. Paint("cyan", SH.Literal(now)) .. "   " .. SH.PromptLine(io.sh))
			io.out(Paint("dim", L["presets:"]))
			for _, n in ipairs(SH.PROMPT_ORDER) do
				io.out("  " .. Paint("green", n) .. "\t" .. SH.PromptLine(io.sh, SH.PROMPTS[n] or nil))
			end
			io.out(Paint("dim", L["parts (prompt dir zone gold):"]))
			for _, s in ipairs(SH.SEGMENT_ORDER) do io.out("  " .. Paint("green", s[1]) .. "\t" .. Paint("dim", SH.Literal(s[2]))) end
			return 0
		end
		local words = {}
		for _, a in ipairs(io.args) do words[#words + 1] = Lower(a) end
		local set
		if #words == 1 and SH.PROMPTS[words[1]] ~= nil then set = words[1]
		else
			for _, w in ipairs(words) do
				if not SH.SEGMENTS[w] then io.err(L["prompt: no part '%s' (prompt lists them)"]:format(SH.Literal(w))) return 1 end
			end
			set = table.concat(words, " ")
		end
		if cdb then cdb.prompt = set ~= "classic" and set or nil end
		return 0
	end,
})

----------------------------------------------------------------------
-- Themes: the console's colour schemes (the shell's colours and the console's own: background, panes, caret)
----------------------------------------------------------------------

SH.THEME_KEYS = { "text", "dim", "green", "blue", "cyan", "yellow", "magenta", "red", "orange", "white" }
SH.THEMES = {
	tokyonight = { label = "Tokyo Night",
		text = "d5dbe6", dim = "6b7387", green = "9ece6a", blue = "7aa2f7", cyan = "7dcfff", yellow = "e0af68",
		magenta = "bb9af7", red = "f7768e", orange = "ff9e64", white = "ffffff",
		bg = "0b0d12", pane = "10131a", edge = "232836", title = "161a23", caret = "7dcfff", sel = "33467c" },
	dracula = { label = "Dracula",
		text = "f8f8f2", dim = "6272a4", green = "50fa7b", blue = "bd93f9", cyan = "8be9fd", yellow = "f1fa8c",
		magenta = "ff79c6", red = "ff5555", orange = "ffb86c", white = "ffffff",
		bg = "191a21", pane = "282a36", edge = "44475a", title = "21222c", caret = "ff79c6", sel = "44475a", focus = "bd93f9" },
	gruvbox = { label = "Gruvbox",
		text = "ebdbb2", dim = "928374", green = "b8bb26", blue = "83a598", cyan = "8ec07c", yellow = "fabd2f",
		magenta = "d3869b", red = "fb4934", orange = "fe8019", white = "fbf1c7",
		bg = "1d2021", pane = "282828", edge = "3c3836", title = "32302f", caret = "fabd2f", sel = "504945", focus = "fe8019" },
	nord = { label = "Nord",
		text = "d8dee9", dim = "616e88", green = "a3be8c", blue = "81a1c1", cyan = "88c0d0", yellow = "ebcb8b",
		magenta = "b48ead", red = "bf616a", orange = "d08770", white = "eceff4",
		bg = "242933", pane = "2e3440", edge = "3b4252", title = "3b4252", caret = "88c0d0", sel = "434c5e", focus = "88c0d0" },
	catppuccin = { label = "Catppuccin Mocha",
		text = "cdd6f4", dim = "6c7086", green = "a6e3a1", blue = "89b4fa", cyan = "89dceb", yellow = "f9e2af",
		magenta = "cba6f7", red = "f38ba8", orange = "fab387", white = "ffffff",
		bg = "11111b", pane = "1e1e2e", edge = "313244", title = "181825", caret = "f5e0dc", sel = "45475a", focus = "cba6f7" },
	solarized = { label = "Solarized Dark",
		text = "93a1a1", dim = "586e75", green = "859900", blue = "268bd2", cyan = "2aa198", yellow = "b58900",
		magenta = "d33682", red = "dc322f", orange = "cb4b16", white = "fdf6e3",
		bg = "00212b", pane = "002b36", edge = "073642", title = "073642", caret = "93a1a1", sel = "0a4b5c", focus = "268bd2" },
	class = { label = L["Tokyo Night in your class's colour"], base = "tokyonight", class = true },
}
SH.THEME_ORDER = { "tokyonight", "dracula", "gruvbox", "nord", "catppuccin", "solarized", "class" }
SH.theme = "tokyonight" -- (the scheme in SH.C now)

--- A scheme's every colour (class: Tokyo Night with your class's colour for the caret, the focused pane and cyan).
function SH.ThemeOf(name)
	local th = SH.THEMES[name]
	if not th or not th.class then return th end
	local out = {}
	for k, v in pairs(SH.THEMES[th.base]) do out[k] = v end
	out.label = th.label
	local _, file = Try(UnitClass, "player")
	local hex = ns.ClassHex and ns.ClassHex(file)
	hex = type(hex) == "string" and hex:match("(%x%x%x%x%x%x)$") or SH.FETCH_CLASS_HEX[file or ""]
	if hex then out.cyan, out.caret, out.focus = hex, hex, hex end
	return out
end

--- The scheme kept (theme NAME), else Tokyo Night.
function SH.ThemeName()
	local db = ns.db
	local n = db and type(db.console) == "table" and db.console.theme
	return SH.THEMES[n] and n or "tokyonight"
end

--- Puts a scheme's colours into SH.C (in place: every Paint after reads them). Returns the old colour -> new colour map
--- for lines already painted (SH.Recolor), or nil when there's no such scheme.
function SH.SetTheme(name)
	local th = SH.ThemeOf(name)
	if not th then return nil end
	local map = {}
	for _, k in ipairs(SH.THEME_KEYS) do
		local old, new = Lower(C[k]), Lower(th[k])
		if old ~= new and map[old] == nil then map[old] = new end
		C[k] = th[k]
	end
	SH.theme, SH.palette = name, th
	return map
end

--- A painted line in the new scheme's colours.
function SH.Recolor(line, map)
	if type(line) ~= "string" or not map or next(map) == nil then return line end
	return (line:gsub("|c[fF][fF](%x%x%x%x%x%x)", function(hex)
		local new = map[Lower(hex)]
		return new and ("|cff" .. new) or nil
	end))
end

local function Lighter(hex, by)
	local out = {}
	for i = 1, 5, 2 do
		local v = tonumber(hex:sub(i, i + 1), 16) or 0
		out[#out + 1] = ("%02x"):format(math.floor(v + (255 - v) * by + 0.5))
	end
	return table.concat(out)
end

--- neofetch's two rows of colour blocks in the scheme's colours.
function SH.Blocks()
	local th = SH.palette
	if not th or SH.theme == "tokyonight" then return SH.FETCH_BLOCKS end
	local row = { th.dim, th.red, th.green, th.yellow, th.blue, th.magenta, th.cyan, th.text }
	local bright = {}
	for i, hex in ipairs(row) do bright[i] = Lighter(hex, 0.25) end
	return { row, bright }
end

SH.Command("theme", {
	desc = L["the console's colours: tokyonight, dracula, gruvbox, nord, catppuccin, solarized or your class's (kept)"],
	usage = "theme [name]",
	run = function(io)
		local name = io.args[1] and Lower(io.args[1])
		if not name then
			for _, n in ipairs(SH.THEME_ORDER) do
				local th = SH.ThemeOf(n)
				local sw = {}
				for _, k in ipairs({ "red", "green", "yellow", "blue", "magenta", "cyan" }) do sw[#sw + 1] = Hex(th[k], "###") end
				io.out((n == SH.theme and Paint("green", "* ") or "  ") .. Hex(th.text, n) .. "\t" .. table.concat(sw) .. "\t"
					.. Paint("dim", SH.Literal(th.label)))
			end
			return 0
		end
		local map = SH.SetTheme(name)
		if not map then io.err(L["theme: no scheme '%s' (theme lists them)"]:format(SH.Literal(name))) return 1 end
		local db = ns.db
		if db then
			db.console = type(db.console) == "table" and db.console or {}
			db.console.theme = name ~= "tokyonight" and name or nil
		end
		if io.sh.ui and io.sh.ui.Theme then io.sh.ui.Theme(map) end
		return 0
	end,
})

----------------------------------------------------------------------
-- Colours as you type
----------------------------------------------------------------------

--- The line painted: a known command green (unknown red), options cyan, quoted words yellow, operators magenta, paths
--- that exist blue (a directory) or their list's colour (a file), comments dim. `plain`: only the cheap colours.
function SH.Highlight(sh, line, plain)
	line = tostring(line or "")
	local toks = SH.Lex(line)
	local out, pos = {}, 1
	local first = true
	local afterRedirect = false
	for _, t in ipairs(toks) do
		if t.s > pos then out[#out + 1] = SH.Literal(line:sub(pos, t.s - 1)) end
		local raw = line:sub(t.s, t.e)
		local color
		if t.t == "comment" then color = "dim"
		elseif t.t == "op" then
			color = "magenta"
			first = t.v ~= ">" and t.v ~= ">>"
			afterRedirect = not first
		elseif afterRedirect then
			color = "orange"
			afterRedirect = false
		elseif first then
			color = SH.Find(t.v) and "green" or "red"
			first = false
		elseif t.open then color = "yellow"
		elseif t.v:sub(1, 1) == "-" and not t.quoted then color = "cyan"
		elseif t.quoted and not t.v:find("/", 1, true) then color = "yellow"
		elseif not plain then
			local node = FS.Resolve(sh.cwd, t.v, true)
			if node then
				if node.kind == "file" and node.d.p and node.d.p.color then
					out[#out + 1] = "|c" .. node.d.p.color .. SH.Literal(raw) .. "|r"
					color = false
				else color = "blue" end
			elseif t.quoted then color = "yellow" end
		end
		if color then out[#out + 1] = Paint(color, SH.Literal(raw))
		elseif color == nil then out[#out + 1] = SH.Literal(raw) end
		pos = t.e + 1
	end
	if pos <= #line then out[#out + 1] = SH.Literal(line:sub(pos)) end
	return table.concat(out)
end

----------------------------------------------------------------------
-- Tab
----------------------------------------------------------------------

--- A name as typed on a line: spaces and the shell's own characters escaped.
function SH.Escape(name)
	return (tostring(name):gsub("([%s'\"\\|;&><#%*%?%[%]%(%)%$!])", "\\%1"))
end

local function CommonPrefix(list)
	if #list == 0 then return "" end
	local p = list[1]
	for i = 2, #list do
		local s = list[i]
		local n = 0
		while n < #p and n < #s and Lower(p:sub(n + 1, n + 1)) == Lower(s:sub(n + 1, n + 1)) do n = n + 1 end
		p = p:sub(1, n)
	end
	return p
end

----------------------------------------------------------------------
-- Tab past the command word: what that command takes there, before paths. Its options (read from its usage line:
-- "[-lrRN]" is four, "-name glob" one), the columns ls -l gives for where, field, sort -k and ls -o (and where's zone
-- and kind values), commands for man and which, your aliases for unalias, the layouts, the text sizes, the classes
-- for neofetch -c. Anything else: paths, as before.
----------------------------------------------------------------------

--- A command's options, from its usage line: { "-l", "-r", "-o", "-name", ... }.
function SH.OptionsOf(def)
	local out, seen = {}, {}
	local usage = type(def) == "table" and def.usage or ""
	local function Add(o) if not seen[o] then seen[o] = true; out[#out + 1] = o end end
	for flag, after in usage:gmatch("%s%[?(%-%-?[%a][%w%-]*)(.?)") do
		if after == "]" and not flag:find("^%-%-") and #flag > 2 and not usage:find("%s" .. flag:gsub("%-", "%%-") .. "%s") then
			for c in flag:sub(2):gmatch(".") do Add("-" .. c) end
		else
			Add(flag)
		end
	end
	table.sort(out)
	return out
end

--- What an ls -l column's values can be, where Terminal knows them (zone, kind), or nil.
local function ColumnValues(col)
	local out = {}
	if col == "zone" then
		for _, z in ipairs(ns.Zones and ns.Zones.LIST or {}) do
			if type(z[6]) == "string" then out[#out + 1] = z[6] end
		end
	elseif col == "kind" then
		for _, d in ipairs((FS.Dirs())) do if not d.special then out[#out + 1] = d.name end end
	else
		return nil
	end
	table.sort(out)
	return out
end

-- (a value with a space or a quote typed as one word)
local function EscapeValue(v) return (tostring(v):gsub("([%s'\"\\])", "\\%1")) end

SH.FIXED_ARGS = {
	layout = { "tile", "grid", "tall", "wide", "mono" },
	font = { "+", "-", "reset", "-a" },
}

--- What Tab offers for `word` (the arg-th word after the command, `prev` the word before it): full words, or nil for
--- paths; and true when a word filled in takes no space after it.
function SH.CompleteArg(sh, cmdName, def, prev, word, arg)
	local function Starting(list, keep)
		local lw, out = Lower(word), {}
		for _, c in ipairs(list) do
			if Lower(c):sub(1, #lw) == lw then out[#out + 1] = keep and keep(c) or c end
		end
		return out
	end
	local name = def and def.name or cmdName
	if word:sub(1, 1) == "-" and def and def.usage then return Starting(SH.OptionsOf(def)) end
	if prev == "-c" and name == "neofetch" then
		local classes = {}
		for i, f in ipairs(SH.FETCH_ORDER or {}) do classes[i] = f:lower() end
		return Starting(classes)
	end
	if (prev == "-k" and name == "sort") or name == "field" then return Starting(FS.COLUMNS) end
	if prev == "-o" and name == "ls" then
		local done, last = word:match("^(.*,)([^,]*)$")
		done, last = done or "", last or word
		local out = {}
		for _, c in ipairs(FS.COLUMNS) do
			if Lower(c):sub(1, #last) == Lower(last) then out[#out + 1] = done .. c end
		end
		return out
	end
	if name == "where" then
		local col, op, value = word:match("^(%a+)([=!<>~]+)(.*)$")
		if not col then return Starting(FS.COLUMNS), true end -- (no space: the comparison comes next)
		local idx = FS.ColumnOf(col)
		local values = idx and ColumnValues(FS.COLUMNS[idx])
		if not values then return {} end
		local lv, out = Lower(value), {}
		for _, v in ipairs(values) do
			if Lower(v):find(lv, 1, true) == 1 then out[#out + 1] = col .. op .. EscapeValue(v) end
		end
		return out
	end
	if def and def.args == "cmd" and arg == 1 then
		local names = {}
		for _, c in ipairs(SH.AllCommands()) do names[#names + 1] = c.name end
		return Starting(names)
	end
	if name == "unalias" then
		local names = {}
		for n in pairs(SH.Aliases()) do names[#names + 1] = n end
		table.sort(names)
		return Starting(names)
	end
	if name == "theme" and arg == 1 then return Starting(SH.THEME_ORDER) end
	if name == "prompt" then
		local all = {}
		if arg == 1 then for _, n in ipairs(SH.PROMPT_ORDER) do all[#all + 1] = n end end
		for _, seg in ipairs(SH.SEGMENT_ORDER) do all[#all + 1] = seg[1] end
		return Starting(all)
	end
	if name == "z" and word:sub(1, 1) ~= "/" and word:sub(1, 1) ~= "." then
		local seen, names = {}, {}
		for _, it in ipairs(SH.ZList({})) do
			local n = it[1]:match("[^/]*$")
			if n and n ~= "" and not seen[Lower(n)] then seen[Lower(n)] = true; names[#names + 1] = EscapeValue(n) end
		end
		return Starting(names)
	end
	if SH.FIXED_ARGS[name] and arg == 1 then return Starting(SH.FIXED_ARGS[name]) end
	return nil
end

--- Tab at the cursor: the new line and cursor, and the choices when there are several (nil when it filled one in).
--- Names starting with what's typed first, else names holding it.
function SH.Complete(sh, line, cursor)
	cursor = cursor or #line
	local before = line:sub(1, cursor)
	local toks = SH.Lex(before)
	local last = toks[#toks]
	local word, from = "", cursor + 1
	local commandWord = true
	if last and last.t == "word" and last.e == #before and not before:sub(-1):match("%s") then
		word, from = last.v, last.s
		commandWord = #toks == 1 or (toks[#toks - 1].t == "op" and toks[#toks - 1].v ~= ">" and toks[#toks - 1].v ~= ">>")
	else
		commandWord = not last or (last.t == "op" and last.v ~= ">" and last.v ~= ">>")
	end
	local candidates, isDir = {}, {}
	local dirPart, base = "", word
	-- (past the command word: what that command takes there, when it says)
	if not commandWord then
		local cmd, prev, arg = nil, nil, 0
		local upto = (word ~= "" and #toks - 1) or #toks
		for i = upto, 1, -1 do
			local t = toks[i]
			if t.t == "op" then
				if t.v == ">" or t.v == ">>" then cmd = false end
				break
			end
			if t.t == "word" then
				if not prev then prev = t.v end
				cmd = t.v
				arg = arg + 1
			end
		end
		if cmd then
			if prev == cmd and arg == 1 then prev = nil end
			local def = SH.Find(cmd)
			if def and def.alias then def = SH.Find((def.alias:match("^%s*(%S+)")), true) end
			local own, open = SH.CompleteArg(sh, Lower(cmd), def, prev, word, arg)
			if own then
				local function Put(text, closing)
					local new = line:sub(1, from - 1) .. text .. closing .. line:sub(cursor + 1)
					return new, from - 1 + #text + #closing
				end
				if #own == 1 then return Put(own[1], (open or own[1]:sub(-1) == ",") and "" or " ") end
				if #own == 0 then return line, cursor, {} end
				local common = CommonPrefix(own)
				if #common > #word then return Put(common, "") end
				return line, cursor, own
			end
		end
	end
	if commandWord and not word:find("/", 1, true) then
		local dotted = word:sub(1, 1) == "."
		local lw = Lower(dotted and word:sub(2) or word)
		for _, c in ipairs(SH.AllCommands()) do
			if (not dotted or c.terminal) and Lower(c.name):sub(1, #lw) == lw then candidates[#candidates + 1] = (dotted and "." or "") .. c.name end
		end
	else
		local slash = word:match("^.*()/")
		if slash then dirPart, base = word:sub(1, slash), word:sub(slash + 1) end
		local node = FS.Resolve(sh.cwd, dirPart == "" and "." or dirPart)
		local lb = Lower(base)
		local names = {}
		if node and node.kind == "root" then
			for _, d in ipairs((FS.Dirs())) do names[#names + 1] = d.name; isDir[d.name] = true end
		elseif node and FolderOf(node) then
			local folder = FolderOf(node)
			for _, n in ipairs(folder.dirNames) do names[#names + 1] = n; isDir[n] = true end
			local files = folder.files
			local nested = not folder.row and node.d.p and FS.CHILDREN[node.d.p.id]
			for _, n in ipairs(files.names) do
				names[#names + 1] = n
				if nested and FS.Children(node.d, files.by[Lower(n)]) then isDir[n] = true end
			end
		end
		for _, n in ipairs(names) do
			if Lower(n):sub(1, #lb) == lb then candidates[#candidates + 1] = n end
		end
		if #candidates == 0 and lb ~= "" then
			for _, n in ipairs(names) do
				if Lower(n):find(lb, 1, true) then candidates[#candidates + 1] = n end
			end
		end
	end
	local function Put(text, closing)
		local new = line:sub(1, from - 1) .. text .. closing .. line:sub(cursor + 1)
		return new, from - 1 + #text + #closing
	end
	if #candidates == 1 then
		local c = candidates[1]
		if commandWord and not word:find("/", 1, true) then return Put(c, " ") end
		return Put(SH.Escape(dirPart) .. SH.Escape(c), isDir[c] and "/" or " ")
	end
	if #candidates == 0 then return line, cursor, {} end
	local common = CommonPrefix(candidates)
	if #common > #base and Lower(common):sub(1, #base) == Lower(base) then
		if commandWord and not word:find("/", 1, true) then return Put(common, "") end
		return Put(SH.Escape(dirPart) .. SH.Escape(common), "")
	end
	local shown = {}
	for i, c in ipairs(candidates) do shown[i] = isDir[c] and (c .. "/") or c end
	return line, cursor, shown
end
