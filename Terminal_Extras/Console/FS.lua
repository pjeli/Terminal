-- (Terminal Extras, a load-on-demand addon of its own: Terminal's namespace is its public table, _G.Terminal)
local ns = _G.Terminal
if not ns then return end
local L = ns.L

-- The console's file system (.console, branch console-dev): every list Terminal searches is a directory at the root,
-- named by its first @kind word (/item, /npc, /spell, /questie...), and each of its rows a file named by the row's
-- name. A file's contents are what its tooltip says (the recorder below reads what the tooltip would show, line by
-- line), so grep finds stats, effect texts and quest objectives. Beside them: /bin (the commands), /etc and /proc (a
-- few files about you and the game), /tmp (what the console writes with >, this session only).
-- Nothing here yields: the shell (Shell.lua) waits between calls, never inside one (no yield through a pcall in 5.1).

local FS = {}
ns.ConsoleFS = FS

FS.SPECIAL = { "bin", "etc", "proc", "tmp" }
FS.tmp = {} -- lowercase name -> { name = "as written", lines = { ... } }

----------------------------------------------------------------------
-- Names
----------------------------------------------------------------------

--- Text without the game's escape codes (colours, textures, links: their shown text kept, "||" as "|").
function FS.Strip(s)
	s = tostring(s or "")
	if not s:find("|", 1, true) then return s end
	s = s:gsub("||", "\1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|c[nN][^:]*:", ""):gsub("|r", "")
		:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|n", " ")
	return (s:gsub("\1", "|"))
end

--- A row's name as a file name: one line, no "/" (a path's separator; the division slash looks the same), no codes.
function FS.Clean(name)
	-- (most names have nothing to clean: as they are, no copies made; a folder's first listing cleaned each of 13,000
	-- NPCs' names and folders about four times; 0.68.13, review over QuestieDB's real data)
	if type(name) == "string" and name ~= "" and not name:find("[|\r\n\t/]") and not name:find("^%s") and not name:find("%s$") then
		return name
	end
	local s = FS.Strip(name):gsub("[\r\n\t]", " "):gsub("/", "\226\136\149")
	s = s:match("^%s*(.-)%s*$")
	if s == "" then s = "?" end
	return s
end

local function Lower(s) return ns.Lower(s) end

----------------------------------------------------------------------
-- The root: one directory per list
----------------------------------------------------------------------

local dirs, dirsBy, dirsKey

--- The root's directories in name order, and a map of lowercase name -> directory. A directory is
--- { name, lname, p = the provider } or { name, lname, special = "bin" | "etc" | "proc" | "tmp" }.
function FS.Dirs()
	local key = #ns.providerOrder
	if dirs and dirsKey == key then return dirs, dirsBy end
	dirs, dirsBy, dirsKey = {}, {}, key
	for _, s in ipairs(FS.SPECIAL) do
		local d = { name = s, lname = s, special = s }
		dirs[#dirs + 1], dirsBy[s] = d, d
	end
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		if p and not p.noKind and type(p.collect) == "function" then
			local base = Lower(FS.Clean((p.aliases and p.aliases[1]) or id)):gsub("%s+", "-")
			local name, i = base, 2
			while dirsBy[name] do name, i = base .. i, i + 1 end
			local d = { name = name, lname = name, p = p }
			dirs[#dirs + 1], dirsBy[name] = d, d
		end
	end
	table.sort(dirs, function(a, b) return a.lname < b.lname end)
	return dirs, dirsBy
end

--- The directory a provider's rows live in (by the provider's id), or nil.
function FS.DirOf(kind)
	local list = FS.Dirs()
	for _, d in ipairs(list) do
		if d.p and d.p.id == kind then return d end
	end
	return nil
end

-- rows that are directories too: provider id -> function(row) -> its rows (each may say its file's name as
-- `fileName`), or nil (FS.Children, FS.SubFiles)
FS.CHILDREN = {}

-- an attunement's steps: step1, step2a, step2b... (Attune's numbers, AT.StepRows' order), side quests side1...
FS.CHILDREN.attune = function(e)
	local AT = ns.Attune
	if not AT or e.isStep then return nil end
	local rec = AT.RecOf(e)
	if not rec then return nil end
	local rows = AT.StepRows(rec)
	local sides = 0
	for i, r in ipairs(rows) do
		local s = r.stepRec or {}
		if s.label then r.fileName = "step" .. tostring(s.label)
		elseif s.side then sides = sides + 1 r.fileName = "side" .. sides
		else r.fileName = "step" .. (r.stepIndex or i) end
	end
	return rows
end

--- The root made again next time (lists registered or swapped: the tests).
function FS.Forget() dirs, dirsBy, dirsKey = nil, nil, nil end

--- Whether a list's rows are made already (asking for them would not build anything now).
function FS.Built(d)
	if not d.p then return true end
	return d.p._entries ~= nil and not d.p._dirty
end

--- What a list says it's still loading, as one line, or nil.
function FS.Busy(d)
	local p = d.p
	if not (p and type(p.busy) == "function") then return nil end
	local ok, b = pcall(p.busy, p)
	if not ok or not b then return nil end
	if type(b) == "table" then b = b[1] end
	if b == true or b == "" then return L["loading"] end
	return type(b) == "string" and FS.Strip(b) or nil
end

----------------------------------------------------------------------
-- The special directories
----------------------------------------------------------------------

local function Special(name, lines) return { special = true, name = name, lines = lines } end

local SPECIAL_FILES = {}

SPECIAL_FILES.etc = function()
	local me = ns.CharacterName and ns.CharacterName() or "you"
	local realm = _G.GetRealmName and _G.GetRealmName() or "forever"
	local files = {
		Special("motd", function() return FS.Motd() end),
		Special("hostname", function() return { FS.Host() } end),
		Special("fstab", function() return FS.Fstab() end),
		Special("os-release", function()
			local v, build = "", ""
			if _G.GetBuildInfo then v, build = _G.GetBuildInfo() end
			return { 'NAME="World of Warcraft Forever"', ('VERSION="%s (%s)"'):format(tostring(v), tostring(build)),
				'ID=forever', ('PRETTY_NAME="Terminal %s on %s"'):format(tostring(ns.version), tostring(realm)) }
		end),
		Special("passwd", function()
			-- (your own characters as Terminal saw them log in: Experience.lua's notes; never anyone else's)
			local out, uid = {}, 1000
			local chars = ns.db and ns.db.xpChars or {}
			local keys = {}
			for k in pairs(chars) do keys[#keys + 1] = k end
			table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
			for _, k in ipairs(keys) do
				local c = chars[k]
				if type(c) == "table" and c.name then
					local user = Lower(FS.Clean(c.name)):gsub("%s+", "")
					out[#out + 1] = ("%s:x:%d:%d:%s level %s:/home/%s:/bin/tsh"):format(user, uid, uid,
						tostring(c.class or "?"), tostring(c.level or "?"), user)
					uid = uid + 1
				end
			end
			if #out == 0 then out[1] = ("%s:x:1000:1000::/home/%s:/bin/tsh"):format(Lower(me), Lower(me)) end
			return out
		end),
	}
	return files
end

SPECIAL_FILES.proc = function()
	return {
		Special("uptime", function() return { FS.Uptime() } end),
		Special("meminfo", function()
			local lua = collectgarbage("count")
			local mine
			if _G.UpdateAddOnMemoryUsage and _G.GetAddOnMemoryUsage then
				pcall(_G.UpdateAddOnMemoryUsage)
				local ok, kb = pcall(_G.GetAddOnMemoryUsage, "Terminal")
				mine = ok and kb or nil
			end
			return { ("LuaTotal:    %d kB"):format(math.floor(lua)),
				("Terminal:    %s kB"):format(mine and tostring(math.floor(mine)) or "?") }
		end),
		Special("loadavg", function()
			local fps = _G.GetFramerate and _G.GetFramerate() or 0
			local home, world = 0, 0
			if _G.GetNetStats then
				local _, _, h, w = _G.GetNetStats()
				home, world = h or 0, w or 0
			end
			return { ("%.1f fps  %d ms home  %d ms world"):format(fps, home, world) }
		end),
		Special("version", function()
			local v, build, date = "?", "?", "?"
			if _G.GetBuildInfo then v, build, date = _G.GetBuildInfo() end
			return { ("Terminal version %s (tsh) on WoW Forever %s build %s (%s), %s"):format(tostring(ns.version),
				tostring(v), tostring(build), tostring(date), _VERSION or "Lua") }
		end),
	}
end

SPECIAL_FILES.tmp = function()
	local out = {}
	for _, f in pairs(FS.tmp) do
		local lines = f.lines
		out[#out + 1] = Special(f.name, function() return lines end)
	end
	return out
end

-- /bin: the shell's own commands and Terminal's; Shell.lua sets FS.Commands (name -> what it is) once it loads
SPECIAL_FILES.bin = function()
	local out = {}
	for _, c in ipairs(FS.Commands and FS.Commands() or {}) do
		out[#out + 1] = { special = true, name = c.name, command = c, lines = function()
			return { c.desc or "", c.terminal and L["(a Terminal command)"] or L["(a shell command: man %s)"]:format(c.name) }
		end }
	end
	return out
end

----------------------------------------------------------------------
-- A directory's files
----------------------------------------------------------------------

--- A directory's files: { names = sorted, by = lowercase name -> row, nameOf = row -> name, byKey = key -> name, list }.
--- A list's rows are made if they aren't (FS.Built says whether that would happen).
function FS.Files(d)
	local list
	if d.special then
		local make = SPECIAL_FILES[d.special]
		list = make and make() or {}
	else
		local ok, res = pcall(ns.GetEntries, ns, d.p)
		list = ok and type(res) == "table" and res or {}
		if d.files and d.files.list == list and d.files.n == #list then return d.files end
	end
	local names, by, nameOf, byKey, lows = {}, {}, {}, {}, {}
	for _, e in ipairs(list) do
		if type(e) == "table" and not e.noActivate and not e.lead then
			local n = FS.Clean(e.name)
			local ln = Lower(n)
			if by[ln] then
				local i = 2
				while by[ln .. "~" .. i] do i = i + 1 end
				n = n .. "~" .. i
				ln = Lower(n)
			end
			names[#names + 1], by[ln], nameOf[e], lows[n] = n, e, n, ln
			local k = rawget(e, "key")
			if k == nil and not e.special then k = e.key end
			if k ~= nil then byKey[tostring(k)] = n end
		end
	end
	table.sort(names, function(a, b) return lows[a] < lows[b] end)
	-- (lows: each name's lowercase, kept for FS.Tree)
	local files = { names = names, by = by, nameOf = nameOf, byKey = byKey, list = list, n = #list, lows = lows }
	if not d.special then d.files = files end
	return files
end

----------------------------------------------------------------------
-- Paths
----------------------------------------------------------------------

--- A path's parts from cwd ("/" or "/item"), "." and ".." taken, "~" = "/". Names keep their case.
function FS.Parts(cwd, path)
	path = tostring(path or "")
	if path == "" then path = cwd or "/" end
	if path == "~" then path = "/" elseif path:sub(1, 2) == "~/" then path = path:sub(2) end
	if path:sub(1, 1) ~= "/" then path = (cwd or "/") .. "/" .. path end
	local parts = {}
	for part in path:gmatch("[^/]+") do
		if part == ".." then parts[#parts] = nil
		elseif part ~= "." then parts[#parts + 1] = part end
	end
	return parts
end

function FS.Join(parts)
	if #parts == 0 then return "/" end
	return "/" .. table.concat(parts, "/")
end

----------------------------------------------------------------------
-- Folders: a list's rows grouped by what they are (/loot/<instance>/<boss>/<item>), and rows with files of their own
----------------------------------------------------------------------

-- provider id -> { function(row) -> the folder it goes in at that depth (a name) or nil, ... }, outermost first: a row
-- with no name for a level stays where it is. Lists without any are flat.
FS.GROUPS = {}

local function Under(s) return (FS.Clean(s):gsub("%s+", "_")) end
FS.Under = Under

--- A folder: { name, path, kind (the list's name and the folders', spaces as _: an ls -l line's kind), dirs = { lowercase
--- name -> folder }, dirNames (in order), files = { names, by, nameOf }, total (rows under it), row (a row's own) }.
local function NewFolder(name, parent, d)
	local f = { name = name, dirs = {}, dirNames = {}, files = { names = {}, by = {}, nameOf = {} }, total = 0, parent = parent }
	if parent then
		f.path, f.kind = parent.path .. "/" .. name, parent.kind .. "/" .. Under(name)
	else
		f.path, f.kind = "/" .. d.name, d.name
	end
	return f
end

local function AddFile(folder, e, base)
	local fl = folder.files
	local n, ln, i = base, Lower(base), 2
	while fl.by[ln] or folder.dirs[ln] do n = base .. "~" .. i; ln = Lower(n); i = i + 1 end
	fl.names[#fl.names + 1], fl.by[ln], fl.nameOf[e] = n, e, n
	return n
end

local function SortFolders(f)
	if #f.dirNames > 1 then table.sort(f.dirNames, function(a, b) return Lower(a) < Lower(b) end) end
	for _, sub in pairs(f.dirs) do SortFolders(sub) end
end

--- A list's folders: { root, files (FS.Files'), folderOf = row -> its folder }. Made again when its rows are.
function FS.Tree(d)
	local files = FS.Files(d)
	local t = d.tree
	if t and t.files == files and t.n == files.n then return t end
	local levels = d.p and FS.GROUPS[d.p.id]
	local root = NewFolder(nil, nil, d)
	local folderOf = {}
	if not levels then
		root.files, root.total = files, #files.names -- (flat: the list's own names, nothing copied)
	else
		local lows = files.lows or {}
		for _, n in ipairs(files.names) do
			local e = files.by[lows[n] or Lower(n)]
			local f = root
			f.total = f.total + 1
			for _, level in ipairs(levels) do
				local ok, g = pcall(level, e)
				g = ok and type(g) == "string" and FS.Clean(g) or nil
				if g and g ~= "?" and g ~= "-" then
					local lg = Lower(g)
					local sub = f.dirs[lg]
					if not sub then
						sub = NewFolder(g, f)
						f.dirs[lg] = sub
						f.dirNames[#f.dirNames + 1] = g
					end
					f = sub
					f.total = f.total + 1
				end
			end
			AddFile(f, e, FS.Clean(e.name))
			folderOf[e] = f
		end
		SortFolders(root)
	end
	t = { root = root, files = files, n = files.n, folderOf = folderOf }
	if not d.special then d.tree = t end
	return t
end

--- Every folder under `f` (itself first), depth first, in order.
function FS.EachFolder(f, fn, depth)
	depth = depth or 0
	if fn(f, depth) == false then return false end
	for _, n in ipairs(f.dirNames) do
		if FS.EachFolder(f.dirs[Lower(n)], fn, depth + 1) == false then return false end
	end
	return true
end

--- A row's own rows (a directory under its list's), or nil.
function FS.Children(d, e)
	local f = d and d.p and FS.CHILDREN[d.p.id]
	if not f or type(e) ~= "table" or e.special then return nil end
	local ok, rows = pcall(f, e)
	return ok and type(rows) == "table" and #rows > 0 and rows or nil
end

--- A row's own files, in the order its list gives them (an attunement's steps in order): as FS.Files, or nil.
function FS.SubFiles(d, e)
	local rows = FS.Children(d, e)
	if not rows then return nil end
	local names, by, nameOf = {}, {}, {}
	for _, r in ipairs(rows) do
		local n = FS.Clean(r.fileName or r.name)
		local ln = Lower(n)
		if by[ln] then
			local i = 2
			while by[ln .. "~" .. i] do i = i + 1 end
			n = n .. "~" .. i
			ln = Lower(n)
		end
		names[#names + 1], by[ln], nameOf[r] = n, r, n
	end
	return { names = names, by = by, nameOf = nameOf, list = rows }
end

--- A row with files of its own as a folder (in `parent`, named `name`), or nil.
function FS.RowFolder(d, e, parent, name)
	if not (d and d.p and FS.CHILDREN[d.p.id]) or parent.row then return nil end
	local sub = FS.SubFiles(d, e)
	if not sub then return nil end
	return { name = name, path = parent.path .. "/" .. name, kind = parent.kind .. "/" .. Under(name), dirs = {},
		dirNames = {}, files = sub, total = #sub.names, row = e, parent = parent }
end

--- A name as typed in a folder: any case; a _ standing for a space (cd /attune/the_dalaran_key).
local function Find(map, name)
	local e = map[Lower(name)]
	if not e and name:find("_", 1, true) then e = map[Lower((name:gsub("_", " ")))] end
	return e
end

--- A row's file path (a search's row: the same table, else the row with its key), or nil.
function FS.PathOf(d, e)
	local t = FS.Tree(d)
	if not t.files.nameOf[e] then
		local k = e.key
		local n = k ~= nil and t.files.byKey and t.files.byKey[tostring(k)]
		e = n and t.files.by[Lower(n)]
		if not e then return nil end
	end
	local f = t.folderOf[e] or t.root
	local name = f.files.nameOf[e]
	return name and (f.path .. "/" .. name) or nil
end

--- What a path names, or nil and the error (Linux's words):
---   { kind = "root", path }
---   { kind = "dir", d, folder, path }                      a list, one of its folders, or a row's own (folder.row)
---   { kind = "file", d, e, name, path, folder, children }  a row (children: it has files of its own: cd, ls go in)
--- `cheap`: never make a list's rows for it (the prompt's colours): nil, "unknown" past a list not made.
function FS.Resolve(cwd, path, cheap)
	local parts = FS.Parts(cwd, path)
	if #parts == 0 then return { kind = "root", path = "/" } end
	local _, by = FS.Dirs()
	local d = by[Lower(parts[1])]
	if not d then return nil, L["No such file or directory"] end
	if #parts > 1 and cheap and not FS.Built(d) then return nil, "unknown" end
	local folder = FS.Tree(d).root
	local i = 2
	while i <= #parts do
		local part = parts[i]
		local sub = Find(folder.dirs, part)
		if sub then
			folder = sub
		else
			local e = Find(folder.files.by, part)
			if not e then return nil, L["No such file or directory"] end
			local name = folder.files.nameOf[e]
			local own = FS.RowFolder(d, e, folder, name)
			if i == #parts then
				return { kind = "file", d = d, e = e, name = name, path = folder.path .. "/" .. name, folder = folder,
					children = own ~= nil, own = own }
			end
			if not own then return nil, L["Not a directory"] end
			folder = own
		end
		i = i + 1
	end
	return { kind = "dir", d = d, folder = folder, path = folder.path }
end

--- The path shown in the prompt: "~" for the root.
function FS.Pretty(path)
	if path == "/" then return "~" end
	return "~" .. path
end

----------------------------------------------------------------------
-- Glob patterns (*, ?, [abc])
----------------------------------------------------------------------

--- A shell glob as a Lua pattern over lowercase text, anchored.
function FS.GlobPattern(glob)
	local out, i, n = { "^" }, 1, #glob
	while i <= n do
		local c = glob:sub(i, i)
		if c == "*" then out[#out + 1] = ".*"
		elseif c == "?" then out[#out + 1] = "."
		elseif c == "[" then
			local j = glob:find("]", i + 1, true)
			if j then
				local set = glob:sub(i + 1, j - 1):gsub("^!", "^"):gsub("%%", "%%%%")
				out[#out + 1] = "[" .. Lower(set) .. "]"
				i = j
			else out[#out + 1] = "%[" end
		elseif c:match("%p") then out[#out + 1] = "%" .. c
		else out[#out + 1] = Lower(c) end
		i = i + 1
	end
	out[#out + 1] = "$"
	return table.concat(out)
end

function FS.GlobMatch(pattern, name)
	local ok, hit = pcall(string.find, Lower(name), pattern)
	return ok and hit ~= nil
end

function FS.HasGlob(s) return s:find("[%*%?%[]") ~= nil end

----------------------------------------------------------------------
-- A file's contents: what its tooltip says
----------------------------------------------------------------------

local function Hex(r, g, b)
	local function c(v) return math.max(0, math.min(255, math.floor((tonumber(v) or 1) * 255 + 0.5))) end
	return ("|cff%02x%02x%02x"):format(c(r), c(g), c(b))
end

local function Colored(text, r, g, b)
	if text == nil then return nil end
	text = tostring(text)
	if r == nil or text == "" then return text end
	return Hex(r, g, b) .. text .. "|r"
end

local function ColorOf(c)
	if type(c) ~= "table" then return nil end
	if type(c.GetRGB) == "function" then
		local ok, r, g, b = pcall(c.GetRGB, c)
		if ok then return r, g, b end
	end
	return c.r, c.g, c.b
end

local RETRIEVING = _G.RETRIEVING_ITEM_INFO or "Retrieving item information"

-- The tooltip recorder: a stand-in for a GameTooltip that keeps the lines it's given. Any Set<Thing> the game's
-- C_TooltipInfo has a Get<Thing> for (SetHyperlink, SetItemByID, SetSpellByID...) reads that data; anything else a row's
-- own tooltip function calls on it does nothing.
local M = {}
function M:ClearLines() self.lines = {} end
function M:SetText(text, r, g, b) self.lines = {}; self:AddLine(text, r, g, b) end
function M:AddLine(text, r, g, b)
	if text == nil then return end
	for part in (tostring(text) .. "\n"):gmatch("(.-)\n") do
		if part:find(RETRIEVING, 1, true) then self.loading = true end
		self.lines[#self.lines + 1] = Colored(part, r, g, b)
	end
end
function M:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
	local l = Colored(left or "", lr, lg, lb)
	if right and tostring(right) ~= "" then l = l .. "    " .. Colored(right, rr, rg, rb) end
	self:AddLine(l)
end
function M:NumLines() return #self.lines end
function M:IsShown() return true end
function M:GetOwner() return nil end
function M:AddData(data)
	if type(data) ~= "table" or type(data.lines) ~= "table" then return end
	for _, line in ipairs(data.lines) do
		local left, right = line.leftText, line.rightText
		if left == nil and type(line.args) == "table" then -- (older data: the texts as args)
			for _, a in ipairs(line.args) do
				if a.field == "leftText" then left = a.stringVal elseif a.field == "rightText" then right = a.stringVal end
			end
		end
		if ns.Secret and (ns.Secret(left) or ns.Secret(right)) then left, right = nil, nil end
		if left or right then
			local lr, lg, lb = ColorOf(line.leftColor)
			local rr, rg, rb = ColorOf(line.rightColor)
			if right and right ~= "" then self:AddDoubleLine(left or "", right, lr, lg, lb, rr, rg, rb)
			else self:AddLine(left or "", lr, lg, lb) end
		end
	end
end
local function Noop() end
-- A hidden game tooltip, read line by line: where the game has no C_TooltipInfo (or it gives nothing), what a
-- Set<Thing> on a real tooltip shows (the classic way; uiforever.com's client: cat on an item said only its name).
local scan
function FS.ScanTip()
	if scan == nil then
		local ok, t = pcall(CreateFrame, "GameTooltip", "TerminalConsoleScanTip", nil, "GameTooltipTemplate")
		scan = ok and t or false
	end
	return scan or nil
end
function FS.SetScanTip(t) scan = t end -- (the tests' stand-in)

local function TextOf(fs)
	if not (fs and fs.GetText) then return nil end
	local ok, text = pcall(fs.GetText, fs)
	if not ok or type(text) ~= "string" or text == "" or (ns.Secret and ns.Secret(text)) then return nil end
	if fs.IsShown and not fs:IsShown() then return nil end
	local r, g, b
	if fs.GetTextColor then
		local okC, cr, cg, cb = pcall(fs.GetTextColor, fs)
		if okC then r, g, b = cr, cg, cb end
	end
	return text, r, g, b
end

local function Scanned(rec, method, ...)
	local t = FS.ScanTip()
	if not (t and type(t[method]) == "function") then
		rec.tried[#rec.tried + 1] = ("hidden tooltip: %s"):format(t and ("no " .. method) or "couldn't be made")
		return false
	end
	if t.SetOwner then pcall(t.SetOwner, t, _G.UIParent or _G.WorldFrame, "ANCHOR_NONE") end
	if t.ClearLines then pcall(t.ClearLines, t) end
	if not pcall(t[method], t, ...) then return false end
	local name = t.GetName and t:GetName()
	local n = t.NumLines and tonumber(t:NumLines()) or 0
	for i = 1, n do
		local left, lr, lg, lb = TextOf(name and _G[name .. "TextLeft" .. i])
		local right, rr, rg, rb = TextOf(name and _G[name .. "TextRight" .. i])
		if left or right then
			if right then rec:AddDoubleLine(left or "", right, lr, lg, lb, rr, rg, rb)
			else rec:AddLine(left, lr, lg, lb) end
		end
	end
	if t.Hide then pcall(t.Hide, t) end
	rec.tried[#rec.tried + 1] = ("hidden tooltip %s: %d lines"):format(method, n)
	return true
end

local RecMeta = { __index = function(_, k)
	local m = M[k]
	if m then return m end
	if type(k) == "string" and k:sub(1, 3) == "Set" then
		local api = _G.C_TooltipInfo and _G.C_TooltipInfo["Get" .. k:sub(4)]
		return function(self, ...)
			local before = #self.lines
			if type(api) == "function" then
				local ok, data = pcall(api, ...)
				if ok then self:AddData(data) end
				self.tried[#self.tried + 1] = ("C_TooltipInfo.Get%s: %s"):format(k:sub(4),
					not ok and "error" or type(data) ~= "table" and "nothing" or (#self.lines - before) .. " lines")
			else
				self.tried[#self.tried + 1] = ("C_TooltipInfo.Get%s: not in this client"):format(k:sub(4))
			end
			if #self.lines == before then Scanned(self, k, ...) end
			return #self.lines > before
		end
	end
	return Noop
end }

-- (`loading` set here: RecMeta answers any field it doesn't hold with a no-op function, which read as "still loading"
-- and made every cat of a row with no item wait its 3 s)
function FS.Recorder() return setmetatable({ lines = {}, tried = {}, loading = false }, RecMeta) end

--- What a row's tooltip says, as lines (colours kept), and whether the game is still loading it.
function FS.TipLines(e)
	local rec = FS.Recorder()
	local shown = false
	if type(e.tooltip) == "function" then
		shown = pcall(e.tooltip, e, rec) and #rec.lines > 0
	end
	if not shown then
		local link = e.link
		if not link and type(e.getLink) == "function" then
			local ok, l = pcall(e.getLink, e)
			link = ok and l or nil
		end
		if not link and tonumber(e.itemID) then link = "item:" .. tonumber(e.itemID) end -- (an item row without a link)
		if type(link) == "string" and link ~= "" and not link:find("|Htrade:", 1, true) then
			rec:SetHyperlink(link)
			shown = #rec.lines > 0
		end
	end
	if not shown and e.tip then
		rec:SetText(e.name)
		rec:AddLine(e.tip)
	end
	return rec.lines, rawget(rec, "loading") == true, rec.tried
end

--- The item a row is about (asked for when its tooltip is still loading), or nil.
local function ItemOf(e)
	local id = tonumber(e.itemID)
	if id then return id end
	local link = e.link
	if type(link) == "string" then return tonumber(link:match("item:(%d+)")) end
	return nil
end

--- The shown parts of a row other than its tooltip: its name, kind and detail.
local function Head(node)
	local e, d = node.e, node.d
	local p = d.p
	local out = {}
	local color = p and p.color or "ffffffff"
	out[1] = "|c" .. color .. FS.Clean(e.name) .. "|r"
	local detail = e.detail and FS.Strip(e.detail) or ""
	local label = p and FS.Strip(e.kindLabel or p.label or p.id) or ""
	out[2] = "|cff6b7387" .. label .. (detail ~= "" and ("  \194\183  " .. detail) or "") .. "|r"
	return out
end

--- An item's lines from the game's item data (name, item level, slot and type, stats, level, sell price): where no
--- tooltip says anything (uiforever.com's client). nil and true while the game hasn't loaded the item.
function FS.ItemLines(id)
	local info = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
	if not (info and id) then return nil end
	local ok, name, link, quality, ilvl, minLevel, itype, subType, _, equipLoc, _, sell = pcall(info, id)
	if not ok or type(name) ~= "string" then return nil, true end
	local out = {}
	local hex = ns.QualityHex and ns.QualityHex(quality)
	out[1] = (hex and (hex .. name .. "|r")) or name
	if tonumber(ilvl) and ilvl > 1 then out[#out + 1] = ((_G.ITEM_LEVEL or "Item Level %d"):gsub("%%d", tostring(ilvl))) end
	local slot = type(equipLoc) == "string" and equipLoc ~= "" and _G[equipLoc]
	local what = subType ~= "" and subType or itype
	if slot or what then out[#out + 1] = (slot and type(slot) == "string" and (slot .. "    ") or "") .. tostring(what or "") end
	local get = (_G.C_Item and _G.C_Item.GetItemStats) or _G.GetItemStats
	if get and link then
		local okS, stats = pcall(get, link)
		if okS and type(stats) == "table" then
			local list = {}
			for k, v in pairs(stats) do
				local label = _G[k]
				if type(label) ~= "string" or label:find("%", 1, true) then
					label = tostring(k):gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "):lower()
				end
				list[#list + 1] = ("+%s %s"):format(tostring(v), label)
			end
			table.sort(list)
			for _, l in ipairs(list) do out[#out + 1] = "|cff1eff00" .. l .. "|r" end
		end
	end
	if tonumber(minLevel) and minLevel > 1 then out[#out + 1] = ((_G.ITEM_MIN_LEVEL or "Requires Level %d"):gsub("%%d", tostring(minLevel))) end
	if tonumber(sell) and sell > 0 and ns.Money then out[#out + 1] = L["Sell price: %s"]:format(ns.Money(sell, true)) end
	return out
end

--- A file's contents, as lines. `wait(seconds)` (the shell's; it may yield) is called while the game loads an item's
--- data, a few times at most; without it, what's there now. `verbose` (cat -v): a last line saying where they came from.
function FS.Content(node, wait, verbose)
	if node.kind ~= "file" then return nil end
	local e = node.e
	if e.special then
		local ok, lines = pcall(e.lines)
		return ok and type(lines) == "table" and lines or {}
	end
	local tip, loading, tried = FS.TipLines(e)
	local id = ItemOf(e)
	-- an item no tooltip said more of than its name: what the game's item data says
	local function FromItem()
		if not id or #tip > 1 then return end
		local lines, pending = FS.ItemLines(id)
		tried[#tried + 1] = ("item data (GetItemInfo %d): %s"):format(id, lines and (#lines .. " lines") or pending and "not loaded yet" or "none")
		if lines then tip = lines elseif pending then loading = true end
	end
	FromItem()
	if loading and wait then
		for _ = 1, 12 do
			if id and _G.C_Item and _G.C_Item.RequestLoadItemDataByID then pcall(_G.C_Item.RequestLoadItemDataByID, id) end
			wait(0.25)
			tip, loading, tried = FS.TipLines(e)
			FromItem()
			if not loading then break end
		end
	end
	local out = Head(node)
	-- (a tooltip's first line is the name again: said once)
	local first = 1
	if tip[1] and FS.Strip(tip[1]) == FS.Strip(e.name) then first = 2 end
	if #tip >= first then out[#out + 1] = "|cff3b4252--|r" end
	for i = first, #tip do out[#out + 1] = tip[i] end
	-- the words a search reads on the row that the tooltip may not say (titles, zones, holders): grep finds them too
	local words = rawget(e, "_ltext")
	if type(words) == "string" and words ~= "" then out[#out + 1] = "|cff6b7387words: " .. words .. "|r" end
	if e.kind == "npc" then FS.NpcLines(e, out) end
	if e.kind == "maps" then FS.ZoneLines(e, out) end
	if verbose then -- (cat -v: where the lines came from, for a client that shows none)
		out[#out + 1] = "|cff6b7387-- read with: " .. (#tried > 0 and table.concat(tried, "; ") or "nothing (no link, tooltip or tip)") .. "|r"
	end
	return out
end

--- A file's fields (stat): the row's own values, a line each, name order.
FS.STAT_FIELDS = { "kind", "key", "name", "detail", "level", "minLevel", "zone", "itemID", "spellID", "questID", "npcID",
	"recipeID", "mapID", "count", "total", "quality", "link", "freqKey" }
function FS.Stat(node)
	local out = {}
	if node.kind ~= "file" then
		local d, f = node.d, node.folder
		out[#out + 1] = "  File: " .. node.path
		out[#out + 1] = "  Type: directory"
		if d and d.p then
			out[#out + 1] = "  List: " .. FS.Strip(d.p.label or d.p.id) .. "  (@" .. tostring(d.p.aliases and d.p.aliases[1] or d.p.id) .. ")"
		end
		if f then
			out[#out + 1] = "  Rows: " .. tostring(f.total or #f.files.names)
			if #f.dirNames > 0 then out[#out + 1] = "  Folders: " .. #f.dirNames end
			if f.row then out[#out + 1] = "  Row: " .. FS.Clean(f.row.name) end
		elseif d and d.p then
			out[#out + 1] = "  Rows: " .. (FS.Built(d) and tostring(#(d.p._entries or {})) or "not made yet")
		end
		return out
	end
	local e = node.e
	out[#out + 1] = "  File: " .. node.path
	if e.special then out[#out + 1] = "  Type: special file" return out end
	local seen, keys, vals = {}, {}, {}
	local function put(k, v)
		if seen[k] or v == nil then return end
		local t = type(v)
		if t ~= "string" and t ~= "number" and t ~= "boolean" then return end
		if type(k) == "string" and k:sub(1, 1) == "_" and k ~= "_ltext" then return end
		seen[k] = true
		keys[#keys + 1] = tostring(k)
		local s = FS.Strip(tostring(v)):gsub("[\r\n]", " ")
		if #s > 160 then s = s:sub(1, 157) .. "..." end
		vals[tostring(k)] = s
	end
	for k, v in pairs(e) do put(k, v) end
	for _, k in ipairs(FS.STAT_FIELDS) do
		local ok, v = pcall(function() return e[k] end)
		if ok then put(k, v) end
	end
	table.sort(keys)
	for _, k in ipairs(keys) do out[#out + 1] = ("  %s: %s"):format(k, vals[k]) end
	return out
end

----------------------------------------------------------------------
-- A few files about you and the game
----------------------------------------------------------------------

function FS.User()
	local name = ns.CharacterName and ns.CharacterName() or (_G.UnitName and _G.UnitName("player")) or "you"
	local first = tostring(name):match("^(%S+)") or "you"
	return Lower(FS.Clean(first))
end

function FS.Host()
	local realm = _G.GetRealmName and _G.GetRealmName()
	if ns.Secret and ns.Secret(realm) then realm = nil end
	realm = Lower(FS.Clean(realm or "forever")):gsub("[^%w%-]+", "-")
	if realm == "" or realm == "?" then realm = "forever" end
	return realm
end

FS.LOADED_AT = _G.GetTime and tonumber(_G.GetTime()) or 0

--- Seconds since login: the game's session time, or (none, or a 0 it gives) since Terminal loaded (a /reload's too).
function FS.SessionSeconds()
	local ok, t = pcall(_G.GetSessionTime or function() end)
	t = ok and tonumber(t) or 0
	if t <= 0 then t = (_G.GetTime and tonumber(_G.GetTime()) or 0) - FS.LOADED_AT end
	return math.max(0, t)
end

function FS.Uptime()
	local t = math.floor(FS.SessionSeconds())
	local h, m = math.floor(t / 3600), math.floor(t % 3600 / 60)
	return L["up %d:%02d"]:format(h, m)
end

function FS.Motd()
	return {
		"|cff7aa2f7tsh|r |cff6b7387: Terminal's console. Every list is a directory, every row a file.|r",
		L["  |cff9ece6als|r look around    |cff9ece6acd|r npc    |cff9ece6acat|r a file    |cff9ece6agrep|r -ri stamina /item    |cff9ece6ahelp|r everything"],
		L["  Ctrl+B then c: a new pane (up to 4), x: close it, o: the next   ` steps out, .console comes back"],
	}
end

----------------------------------------------------------------------
-- ls -l: a row as columns, POSIX-style (one word each, the name last), so cut/field/where/sort -k read them
----------------------------------------------------------------------

-- mode kind id role title lvl count dist zone name; "-" where a row has none
FS.COLUMNS = { "mode", "kind", "id", "role", "title", "lvl", "count", "dist", "zone", "name" }
FS.COLUMN_INDEX = {}
for i, c in ipairs(FS.COLUMNS) do FS.COLUMN_INDEX[c] = i end
FS.COLUMN_ALIASES = { level = "lvl", lv = "lvl", n = "count", qty = "count", distance = "dist", yd = "dist",
	yards = "dist", where = "zone", place = "zone", file = "name", type = "kind", perms = "mode", roles = "role", sub = "title", subname = "title" }

--- A column's name as typed ("distance", "lvl", "5") -> its index, or nil.
function FS.ColumnOf(word)
	word = Lower(tostring(word or ""))
	word = FS.COLUMN_ALIASES[word] or word
	if word == "path" then return "path" end -- (not printed: worked out from kind and name, for xargs)
	return FS.COLUMN_INDEX[word] or tonumber(word)
end

-- the lists whose rows can be upgrades for you (the u in their mode)
FS.UPGRADE_LISTS = { loot = true }
local upgradeTest, upgradeAt

--- Whether a row is an upgrade for you: Terminal's own is:upgrade (Filters/Upgrades.lua: your class's stats against
--- what you wear in its slot), for FS.UPGRADE_LISTS' rows only. The test made again after a second (gear changes).
function FS.IsUpgrade(e)
	if not FS.UPGRADE_LISTS[e.kind] then return false end
	local now = GetTime and GetTime() or 0
	if upgradeTest == nil or now - (upgradeAt or 0) > 1 then
		local F = ns.Filters
		local ok, t = pcall(F and F.Parse, "is:upgrade")
		upgradeTest, upgradeAt = ok and type(t) == "function" and t or false, now
	end
	if not upgradeTest then return false end
	local ok, yes = pcall(upgradeTest, e)
	return ok and yes == true
end
function FS.ForgetUpgrade() upgradeTest = nil end -- (tests)

--- A row's mode: its type (d a directory, - a row, c a system file), then what it has: r a tooltip to read, x Enter
--- does something, s so does Shift+Enter, l a link for chat, n a place in the world (a distance), u an upgrade for
--- you (loot).
function FS.Mode(e, isDir)
	if isDir then return "drx----" end
	if e.special then return "cr-----" end
	local r = (e.tooltip or e.link or e.getLink or e.tip) and "r" or "-"
	local x = (e.activate or e.secure) and "x" or "-"
	local s = (e.secondary or e.secondarySecure) and "s" or "-"
	local l = (e.link or e.getLink or e.shareLink) and "l" or "-"
	local n = (rawget(e, "wcont") or e.wcont or e.kind == "npc") and "n" or "-"
	local u = FS.IsUpgrade(e) and "u" or "-"
	return "-" .. r .. x .. s .. l .. n .. u
end

local I = ns.Integrations

local function NpcId(e)
	if e.kind ~= "npc" then return nil end
	local id = e.npcID or rawget(e, "key")
	return type(id) == "number" and id or nil
end

-- An NPC's roles, as Terminal's is: filters read them (Questie's NPC flags): one word, commas between
FS.ROLES = { "innkeeper", "repair", "vendor", "banker", "auctioneer", "flightmaster", "trainer", "stablemaster",
	"battlemaster", "spirithealer", "questgiver" }
-- (each row's worked out once, kept as long as the row is: eleven tests on each of QuestieDB's 13,000 NPCs were about
-- 100 ms, asked again by every listing; 0.68.13, review over its real data)
local rolesOf = setmetatable({}, { __mode = "k" })
function FS.Roles(e)
	if not NpcId(e) then return nil end
	local known = rolesOf[e]
	if known ~= nil then return known or nil end
	local F = ns.Filters
	local IS = F and F._ and F._.IS
	if not IS then return nil end
	local out = {}
	for _, r in ipairs(FS.ROLES) do
		local test = IS[r]
		if test then
			local ok, yes = pcall(test, e)
			if ok and yes then out[#out + 1] = r end
		end
	end
	local roles = #out > 0 and table.concat(out, ",") or nil
	rolesOf[e] = roles or false
	return roles
end
function FS.ForgetRoles() rolesOf = setmetatable({}, { __mode = "k" }) end -- (tests)

-- What each NPC sells, by NPC: Questie keeps it by item (each item's vendors), so the whole list is read once
-- (FS.BuildSold, the shell waiting while it does) and kept for the session. npc id -> item names, sorted.
FS.sold = nil
local function QuestieDB()
	local DB = ns.QuestieData and ns.QuestieData.DB()
	return DB and DB.QueryItemSingle and DB.ItemIds and DB or nil
end
FS.HasQuestie = function() return QuestieDB() ~= nil end

--- Reads every Questie item's vendors once. `step(i, n)` is called every so often (the shell's: it may wait a frame;
--- never inside a pcall here). False without Questie.
function FS.BuildSold(step)
	if FS.sold then return true end
	local DB = QuestieDB()
	if not DB then return false end
	local ok, ids = pcall(DB.ItemIds)
	if not ok or type(ids) ~= "table" then return false end
	local sold = {}
	for i, id in ipairs(ids) do
		local okV, vendors = pcall(DB.QueryItemSingle, id, "vendors")
		if okV and type(vendors) == "table" and next(vendors) then
			local okN, name = pcall(DB.QueryItemSingle, id, "name")
			if okN and type(name) == "string" and name ~= "" then
				for _, npc in pairs(vendors) do
					local list = sold[npc]
					if not list then list = {} sold[npc] = list end
					list[#list + 1] = name
				end
			end
		end
		if step and i % 200 == 0 then step(i, #ids) end
	end
	for _, list in pairs(sold) do table.sort(list) end
	FS.sold = sold
	return true
end
FS.SELLS_PER_LINE = 6

--- An NPC file's own lines: its roles and what it sells (six items a line, each line saying "sells:").
function FS.NpcLines(e, out)
	local roles = FS.Roles(e)
	if roles then out[#out + 1] = "|cff7dcfffrole: " .. roles .. "|r" end
	local id = NpcId(e)
	if not id then return end
	if FS.sold then
		local list = FS.sold[id]
		if list then
			for i = 1, #list, FS.SELLS_PER_LINE do
				local part = {}
				for j = i, math.min(#list, i + FS.SELLS_PER_LINE - 1) do part[#part + 1] = list[j] end
				out[#out + 1] = "|cffe0af68sells: |r" .. table.concat(part, ", ")
			end
		end
	elseif QuestieDB() then
		out[#out + 1] = "|cff6b7387" .. L["sells: (not read yet: cat or grep on /npc reads it)"] .. "|r"
	end
end

--- A zone file's own lines (Zones.lua's): its levels, the fishing skill it needs (deeper spots: more), and yours:
--- grep -r fishing /map.
function FS.ZoneLines(e, out)
	local Z = ns.Zones
	local ok, z = pcall(function() return Z and Z.Of and e.mapID and Z.Of(e.mapID) end)
	if not (ok and z) then return end
	if z.min then
		out[#out + 1] = "|cff7dcfff" .. L["levels: %s"]:format(z.min == z.max and tostring(z.min) or (z.min .. "-" .. z.max)) .. "|r"
	end
	if z.fish then
		local line = L["fishing: %d"]:format(z.fish)
		if z.fishHigh then line = line .. ", " .. L["deeper spots %d"]:format(z.fishHigh) end
		local okS, mine = pcall(Z.FishingSkill or function() end)
		if okS and type(mine) == "number" then
			line = line .. "  " .. (mine >= z.fish and L["(yours: %d, enough)"] or L["(yours: %d, not yet)"]):format(mine)
		end
		out[#out + 1] = "|cff7dcfff" .. line .. "|r"
	end
end

--- An AtlasLoot row's boss and instance: its detail is "<boss>  <instance>" (Loot.lua's GroupText). nil, nil else.
function FS.LootPlace(e)
	if e.kind ~= "loot" then return nil end
	local detail = FS.Strip(e.detail or "")
	local boss, inst = detail:match("^(.-)  +(.+)$")
	if not boss then return nil, detail ~= "" and detail or nil end
	if boss == "?" or boss == "" then boss = nil end
	return boss, inst
end

--- An NPC's title (Questie's: "Reagent Vendor", "Mining Trainer"), or a loot row's boss, as one word: spaces as _.
function FS.Title(e)
	local boss = FS.LootPlace(e)
	if boss then return (FS.Clean(boss):gsub("%s+", "_")) end
	if e.isStep and e.fileName then return (FS.Clean(e.name):gsub("%s+", "_")) end -- (an attunement step: what it is)
	if not NpcId(e) then return nil end
	local sub = e.sub
	if type(sub) ~= "string" or sub == "" or (ns.Secret and ns.Secret(sub)) then return nil end
	return (FS.Clean(sub):gsub("%s+", "_"))
end

local function LevelText(e)
	local lo, hi
	local id = NpcId(e)
	if type(e.level) == "number" then
		lo, hi = e.level, e.level
		if type(e.minLevel) == "number" and e.minLevel <= e.level then lo = e.minLevel end
	elseif id and I and I.NpcField then
		local ok, a = pcall(I.NpcField, id, "minLevel")
		local ok2, b = pcall(I.NpcField, id, "maxLevel")
		lo, hi = ok and tonumber(a) or nil, ok2 and tonumber(b) or nil
	elseif tonumber(e.itemID) then
		local info = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
		if info then
			local ok, _, _, _, _, m = pcall(info, tonumber(e.itemID))
			if ok and type(m) == "number" and m > 1 then lo, hi = m, m end
		end
	end
	if type(lo) ~= "number" then return "-" end
	if not hi or hi == lo then return tostring(lo) end
	return lo .. "-" .. hi
end

-- the game's own number for a row, as its kind and the number (the way links write them): item:2589, spell:133
FS.ID_FIELDS = { { "itemID", "item" }, { "spellID", "spell" }, { "recipeID", "recipe" }, { "questID", "quest" },
	{ "qid", "quest" }, { "npcID", "npc" }, { "currencyID", "currency" }, { "factionID", "faction" }, { "mapID", "map" } }
-- (lists whose rows' key is the game's own number)
FS.ID_KEYS = { achievements = "achievement", npc = "npc", questie = "quest", quests = "quest", maps = "map" }

function FS.IdText(e)
	for _, f in ipairs(FS.ID_FIELDS) do
		local ok, v = pcall(function() return e[f[1]] end)
		v = ok and tonumber(v)
		if v then return f[2] .. ":" .. ("%.0f"):format(v) end
	end
	local what = FS.ID_KEYS[e.kind]
	local key = tonumber(rawget(e, "key"))
	if what and key then return what .. ":" .. ("%.0f"):format(key) end
	return "-"
end

local areaNames = {} -- area id -> name or false (C_Map.GetAreaInfo once each, not once per NPC listed)
local function AreaName(area)
	local n = areaNames[area]
	if n == nil then
		n = false
		if _G.C_Map and _G.C_Map.GetAreaInfo then
			local ok, name = pcall(_G.C_Map.GetAreaInfo, area)
			if ok and type(name) == "string" and not (ns.Secret and ns.Secret(name)) then n = name end
		end
		areaNames[area] = n
	end
	return n or nil
end

local function ZoneText(e)
	local z = e.zone
	if (type(z) ~= "string" or z == "") and e.kind == "loot" then z = select(2, FS.LootPlace(e)) end -- (its instance)
	if type(z) ~= "string" or z == "" then
		z = nil
		local ui = rawget(e, "ui") or e.ui
		if type(ui) == "number" and I and I.ZoneName then z = I.ZoneName(ui) end
		local id = not z and NpcId(e)
		if id and I and I.NpcField then
			local ok, area = pcall(I.NpcField, id, "zoneID")
			if ok and type(area) == "number" then z = AreaName(area) end
		end
	end
	if type(z) ~= "string" or z == "" or (ns.Secret and ns.Secret(z)) then return "-" end
	return (FS.Clean(z):gsub("%s+", "_"))
end

--- How far a row is from `here` (I.Here()), in whole yards, or nil.
function FS.Yards(e, here)
	if not (here and I and I.RowYards) then return nil end
	local ok, d = pcall(I.RowYards, e, here)
	if ok and type(d) == "number" then return math.floor(d + 0.5) end
	return nil
end

--- A row's columns, in FS.COLUMNS' order (strings; "-" for none). `here`: where you stand (distances), or nil.
function FS.Columns(d, e, name, here, folder)
	if not e then
		local p = d and d.p
		local n = p and (FS.Built(d) and tostring(#(p._entries or {})) or "-") or "-"
		return { FS.Mode(nil, true), "dir", "-", "-", "-", "-", n, "-", "-", name or (d and d.name) or "/" }
	end
	local count = e.special and "-" or (tonumber(e.total) or tonumber(e.count))
	local yd = not e.special and FS.Yards(e, here)
	return {
		FS.Mode(e, FS.CHILDREN[d and d.p and d.p.id or ""] and not (folder and folder.row) and FS.Children(d, e) ~= nil),
		folder and folder.kind or (d and d.name) or "-",
		e.special and "-" or FS.IdText(e),
		not e.special and FS.Roles(e) or "-",
		not e.special and FS.Title(e) or "-",
		e.special and "-" or LevelText(e),
		count and tostring(count) or "-",
		yd and (yd .. "yd") or "-",
		e.special and "-" or ZoneText(e),
		name,
	}
end

-- Every ls -l line carries all its columns, whichever it shows (ls -l -o): ahead of its text, an empty link the game
-- draws as nothing, "|Htsh:<mode>\t<kind>\t...\t<name>|h|h". FS.Strip drops it (grep sees what's shown).
FS.HIDDEN = "|Htsh:"

function FS.Hidden(cols)
	local parts = {}
	for i = 1, #FS.COLUMNS do parts[i] = tostring(cols[i] or "-"):gsub("[|\t\n]", "") end
	return FS.HIDDEN .. table.concat(parts, "\t") .. "|h|h"
end

--- An ls -l line read back (as printed, or its plain text with every column shown): { mode, kind, ..., name, [1..10],
--- path } or nil when it isn't one.
local lastLine, lastLong -- (where and field ask the same line for each condition and column: read once)
function FS.ParseLong(line)
	line = tostring(line or "")
	if line == lastLine then return lastLong end
	local out = FS.ReadLong(line)
	lastLine, lastLong = line, out
	return out
end

function FS.ReadLong(line)
	local hidden = line:match("|Htsh:(.-)|h|h")
	local out
	if hidden then
		out = {}
		for part in (hidden .. "\t"):gmatch("(.-)\t") do out[#out + 1] = part end
		if #out ~= #FS.COLUMNS then return nil end
	else
		local plain = FS.Strip(line)
		local mode, rest = plain:match("^%s*([%-dc][r%-][x%-][s%-][l%-][n%-][u%-])%s+(.*)$")
		if not mode then return nil end
		out = { mode }
		for i = 2, 9 do
			local word, after = rest:match("^(%S+)%s+(.*)$")
			if not word then return nil end
			out[i], rest = word, after
		end
		out[10] = rest
	end
	for i, c in ipairs(FS.COLUMNS) do out[c] = out[i] end
	-- the file's whole path, for what reads paths (ls -l /npc | field path | xargs cat)
	out.path = out.kind == "dir" and ("/" .. out.name:gsub("/$", "")) or ("/" .. out.kind .. "/" .. out.name:gsub("/$", ""))
	return out
end

----------------------------------------------------------------------
-- The lists that are folders by what their rows are
----------------------------------------------------------------------

-- AtlasLoot's: /loot/<instance or crafting section>/<boss>/<item>
FS.GROUPS.loot = { function(e) return (select(2, FS.LootPlace(e))) end, function(e) return (FS.LootPlace(e)) end }
-- your recipes: /recipe/<profession>/<recipe>
FS.GROUPS.recipes = { function(e) return e.profName end }
-- QuestieDB's mailboxes: /mailbox/<zone>/<mailbox>
FS.GROUPS.mailbox = { function(e) return e.zone end }
FS.GROUPS.forge = FS.GROUPS.mailbox
FS.GROUPS.anvil = FS.GROUPS.mailbox
FS.GROUPS.cookingfire = FS.GROUPS.mailbox
FS.GROUPS.moonwell = FS.GROUPS.mailbox

-- Questie's NPCs: /npc/<zone>/<role>/<npc> (an NPC with no role, most monsters, right in its zone; one whose zone
-- isn't known stays at the top). The role is its first in FS.ROLES' order (a vendor that repairs: repair).
local function NpcZone(e)
	local id = NpcId(e)
	if not id then return nil end
	local z = rawget(e, "zone")
	if type(z) == "string" and z ~= "" then return z end
	if not (I and I.NpcField) then return nil end
	local ok, area = pcall(I.NpcField, id, "zoneID")
	return ok and type(area) == "number" and AreaName(area) or nil
end
FS.NpcZone = NpcZone
FS.GROUPS.npc = { NpcZone, function(e)
	if not NpcZone(e) then return nil end -- (no zone: no role folder at the top either)
	local roles = FS.Roles(e)
	return roles and roles:match("^[^,]+") or nil
end }

----------------------------------------------------------------------
-- Other addons as mounted filesystems (df, mount, /etc/fstab): the lists each one fills
----------------------------------------------------------------------

local function AddonLoaded(name)
	local f = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	if not f then return false end
	local ok, yes = pcall(f, name)
	return ok and yes == true
end

-- each: the lists it fills (provider ids), its addons' names (the first one said in /etc/fstab when none is
-- loaded), and which of them is in use now (nil: none). Lists Terminal fills itself (items, spells, flight paths,
-- entrances...) aren't mounts.
FS.MOUNTS = {
	{ type = "atlasloot", lists = { "loot" }, names = { "AtlasLootClassic", "AtlasLoot", "AtlasLootContinued" },
		source = function() return I and I.LoadedCore and I.LoadedCore() end },
	{ type = "questiedb", lists = { "npc", "questie", "mailbox", "forge", "anvil", "cookingfire", "moonwell" }, names = { "Questie", "QuestieDB" },
		source = function() return ns.QuestieData and ns.QuestieData.Source() end },
	{ type = "attune", lists = { "attune" }, names = { "Attune" },
		source = function() return I and I.attune and I.attune.on and "Attune" or nil end },
	{ type = "bags", lists = { "stored", "bank" }, names = { "Syndicator", "BagBrother" },
		source = function() return ns.Stored and ns.Stored.Source() end },
	{ type = "trainers", lists = { "training" }, names = { "WhatsTraining", "TrainerSpells" },
		source = function()
			local p = ns.providers.training
			if p then return p.fromTrainerSpells and "TrainerSpells" or "WhatsTraining" end
		end },
	{ type = "aceconfig", lists = { "addonoptions" }, names = { "Ace3" },
		source = function()
			local LS = _G.LibStub
			return LS and LS("AceConfigRegistry-3.0", true) and "Ace3" or nil
		end },
	{ type = "auctionator", lists = {}, names = { "Auctionator" },
		source = function() return AddonLoaded("Auctionator") and "Auctionator" or nil end },
	-- Terminal: Share, as NFS: each friend connected a remote filesystem (their name: the character's, never a
	-- Battle.net name), your groups its exports
	{ type = "nfs4", lists = { "shared" }, names = { "Terminal_Share" },
		source = function() return ns.Ssh and ns.Ssh.game and "Terminal_Share" or nil end,
		remotes = function()
			local ep = ns.Ssh and ns.Ssh.game
			if not (ep and ep:On()) then return {} end
			local d = FS.DirOf("shared")
			local out = {}
			for _, c in ipairs(ep:Connected() or {}) do
				local who = FS.Clean(c.name)
				local mode = c.friend and c.friend.mode
				out[#out + 1] = { source = who .. ":/bags", point = "/" .. (d and d.name or "shared") .. "/" .. who,
					size = c.n, used = c.n, opts = "ro,vers=4" .. (mode and (",sharing=" .. mode) or "") }
			end
			table.sort(out, function(x, y) return x.source < y.source end)
			return out
		end,
		fstab = function(src)
			if not src then
				return { ("# Terminal_Share\t/shared\tnfs4\tro,noauto\t0\t0\t# %s"):format(L["not installed"]) }
			end
			local ep = ns.Ssh.game
			local names = {}
			for g in pairs(ep and ep.groups or {}) do names[#names + 1] = g end
			table.sort(names)
			if #names == 0 then
				return { ("# share:<group>\t/shared\tnfs4\tro,noauto,_netdev\t0\t0\t# %s"):format(L["no group yet: .share password <password>"]) }
			end
			local out = {}
			for _, g in ipairs(names) do
				out[#out + 1] = ("share:%s\t/shared\tnfs4\tro,auto,_netdev,sharing=%s\t0\t0"):format(FS.Clean(g), tostring(ep.groups[g].mode or "limited"))
			end
			return out
		end },
}

--- Every mount as it stands: { m, source (the addon in use, or nil), points (its directories' paths), size, used
--- (rows: all of them, those ready; nil when no list is made yet), opts (mount's: ro, lazy, loading...), note }. A mount
--- with `remotes` (Share) is one a remote (a friend connected), or one with no source and a note when there's none.
function FS.Mounts()
	local out = {}
	for _, m in ipairs(FS.MOUNTS) do
		local ok, src = pcall(m.source)
		src = ok and type(src) == "string" and src or nil
		if m.remotes then
			local okR, list = false, nil
			if src then okR, list = pcall(m.remotes) end
			list = okR and type(list) == "table" and list or {}
			for _, r in ipairs(list) do
				out[#out + 1] = { m = m, source = r.source, points = { r.point }, size = r.size, used = r.used, opts = r.opts, remote = true }
			end
			if #list == 0 then
				out[#out + 1] = { m = m, points = {}, opts = "ro", note = src and L["nobody connected"] or nil }
			end
		else
			local points, size, used, opts = {}, nil, nil, { "ro" }
			local lazy, busy, drop = false, false, false
			for _, id in ipairs(m.lists) do
				local d = FS.DirOf(id)
				local p = ns.providers[id]
				if d then points[#points + 1] = "/" .. d.name end
				if p then
					if p._entries then
						size = (size or 0) + #p._entries
						used = (used or 0) + #p._entries
					end
					lazy = lazy or p.lazy == true
					drop = drop or p.idleDrop ~= nil
					busy = busy or (d and FS.Busy(d)) ~= nil
				end
			end
			-- (AtlasLoot's rows wait for their names from the server: those are its not-yet-used part)
			if m.type == "atlasloot" and I and I.loot and I.loot.on then
				local waiting = I.LootWaiting and I.LootWaiting() or 0
				size = #I.loot.rows
				used = size - waiting
				if waiting > 0 then opts[#opts + 1] = "names-pending" end
			end
			opts[#opts + 1] = lazy and "lazy" or "auto"
			if drop then opts[#opts + 1] = "idle-drop" end
			if busy then opts[#opts + 1] = "loading" end
			out[#out + 1] = { m = m, source = src, points = points, size = size, used = used, opts = table.concat(opts, ",") }
		end
	end
	return out
end

--- /etc/fstab: every addon Terminal reads, in fstab's columns; the ones not here are commented out. A mount with its
--- own lines (Share's groups, as NFS exports) gives them.
function FS.Fstab()
	local out = { "# /etc/fstab: the addons Terminal reads, mounted read-only (df: how full; mount: as they are now)",
		"# <addon>\t<mount point>\t<type>\t<options>\t<dump>\t<pass>" }
	local done = {}
	for _, mt in ipairs(FS.Mounts()) do
		local m = mt.m
		if m.fstab then
			if not done[m] then
				done[m] = true
				local ok, src = pcall(m.source)
				src = ok and type(src) == "string" and src or nil
				local okF, lines = pcall(m.fstab, src)
				for _, l in ipairs(okF and lines or {}) do out[#out + 1] = l end
			end
		else
			local points = #mt.points > 0 and mt.points or {}
			if #points == 0 then
				for _, id in ipairs(m.lists) do points[#points + 1] = "/" .. id end
				if #points == 0 then points[1] = "none" end
			end
			for _, pt in ipairs(points) do
				if mt.source then
					out[#out + 1] = ("%s\t%s\t%s\t%s\t0\t0"):format(mt.source, pt, m.type, mt.opts)
				else
					out[#out + 1] = ("# %s\t%s\t%s\tro,noauto\t0\t0\t# %s"):format(m.names[1], pt, m.type, L["not installed"])
				end
			end
		end
	end
	return out
end

-- Terminal: Share's: /shared/<friend>/<item> (each friend's things in their own folder, as their NFS mount says)
FS.GROUPS.shared = { function(e) return e.owner end }
