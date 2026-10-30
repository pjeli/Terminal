-- (Terminal Extras, a load-on-demand addon of its own: Terminal's namespace is its public table, _G.Terminal)
local ns = _G.Terminal
if not ns then return end
local L = ns.L

-- The console's commands that look around (ls, cd, pwd, tree, find, locate, cat, head, tail, stat, file) and those that
-- make what was piped in into something else (sort, uniq, wc, cut...): split from Shell.lua as they were (0.69.8).
-- Shell.lua is the shell: reading a line, running it, the commands' registry and what they share.

local FS = ns.ConsoleFS
local SH = ns.Shell
local C = SH.C
local function Paint(color, s) return "|cff" .. C[color] .. tostring(s) .. "|r" end
local Strip = FS.Strip
local Lower = ns.Lower
local EnsureSold, InputLines, Mark, Painted = SH.EnsureSold, SH.InputLines, SH.Mark, SH.Painted
local X = SH._
local Count, DirName, FolderOf, Link, PathArgs, Resolve = X.Count, X.DirName, X.FolderOf, X.Link, X.PathArgs, X.Resolve
local Under, WithIcon, WriteTarget = X.Under, X.WithIcon, X.WriteTarget

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
