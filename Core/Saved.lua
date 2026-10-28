local ns = select(2, ...)
local L = ns.L

-- Saved data in two files (0.67.7, a player's report: Terminal.lua in SavedVariables was large). TerminalDB
-- (Terminal.lua) keeps the settings, tabs, picks and search history; everything Terminal records or learns as you play
-- (logs, item and loot indexes, alts' mail, recipes...) is in TerminalCacheDB (TerminalCache.lua), which can be deleted
-- whole without losing a setting. ns.db is TerminalDB with the cache keys passed through to TerminalCacheDB (a
-- metatable: the code reading ns.db.lootLog didn't change), and a save from before the split is moved over at load.
-- What's kept between sessions is the player's to choose (.saved keep), and the big tables are written packed: rows
-- as lines of tab-separated fields, read back at load (Pack/Unpack below).
local SV = {}
ns.Saved = SV

-- The cache file's keys, by the .saved name they're shown and cleared under. `levels`: how much of it is kept between
-- sessions (0 = nothing), `default` the level used when the player hasn't picked one. Without levels: a record kept
-- whole until cleared. `lists`: the providers built from it, read again when it's cut or cleared.
SV.GROUPS = {
	{ name = "items", keys = { "itemStore" }, label = L["item details (qualities, stats)"], rebuilt = true,
		levels = { off = 0, small = 2000, normal = 4000, large = 12000 }, default = "normal", unit = L["items"] },
	{ name = "atlasloot", keys = { "lootCache" }, label = L["AtlasLoot's index"], rebuilt = true,
		levels = { off = 0, on = 1 }, default = "on" },
	{ name = "talents", keys = { "talentCache", "talentDesc" }, label = L["every class's talents"], rebuilt = true, lists = { "talents" },
		levels = { off = 0, on = 1 }, default = "on" },
	{ name = "objects", keys = { "objectIndex" }, label = L["Questie's mailboxes and objects"], rebuilt = true, lists = { "mailbox", "forge", "anvil", "cookingfire", "moonwell" },
		levels = { off = 0, on = 1 }, default = "on" },
	{ name = "loot", keys = { "lootLog" }, label = L["loot log"], lists = { "lootlog" },
		levels = { off = 0, small = 100, normal = 250, large = 500 }, default = "normal", unit = L["drops"] },
	{ name = "combat", keys = { "combatLog" }, label = L["combat log"], lists = { "combatlog" },
		levels = { off = 0, small = 50, normal = 150, large = 300 }, default = "normal", unit = L["entries"] },
	{ name = "missed", keys = { "missed" }, label = L["searches that found nothing"] },
	{ name = "characters", keys = { "xpChars", "xpForgotten", "lockouts", "flights" },
		label = L["your characters' experience, lockouts and flight paths"], lists = { "experience", "lockouts", "flight" } },
	{ name = "recipes", keys = { "recipes", "recipeVendors", "recipeTrainers" }, label = L["recipes and where to learn them"],
		lists = { "recipes", "missing", "professions" } },
	{ name = "mail", keys = { "mailboxes", "mailAuctions", "mailSent", "auctionsPosted", "auctionsEnded", "auctionsSold" },
		label = L["mail and auctions"], lists = { "mail", "auctions" } },
	{ name = "vendors", keys = { "vendorItems", "repairVendor", "buyback" }, label = L["vendors and buyback"],
		lists = { "buyback", "durability" } },
	{ name = "books", keys = { "lore" }, label = L["books read"] },
	{ name = "console", keys = { "consoleData" }, label = L["the console's history, panes and folders"] },
	{ name = "other", keys = { "typingBest", "snakeBest", "tetrisBest", "lootrunBest" }, label = L["other records"] },
}
SV.KEY = {} -- (cache key -> its group)
SV.BY_NAME = {}
for _, g in ipairs(SV.GROUPS) do
	SV.BY_NAME[g.name] = g
	for _, k in ipairs(g.keys) do SV.KEY[k] = g end
end
-- (.saved keep all <preset>: each group's level)
SV.PRESETS = {
	minimal = { items = "off", atlasloot = "off", talents = "off", objects = "off", loot = "small", combat = "small" },
	normal = {},
	everything = { items = "large", loot = "large", combat = "large" },
}

----------------------------------------------------------------------
-- Packing: a list of flat records (or arrays) as one string. The first line names the fields, each next line is a
-- record, fields split by tabs. A field is "" (nil), "=" (the record above's), "#<number>", "!1"/"!0" (true/false),
-- "'<text>" (text starting with one of those marks) or the text itself. nil when a record can't be written this way
-- (a table inside it, a tab or a line break in a text): kept as it was then.
----------------------------------------------------------------------

local MARK = { ["#"] = true, ["!"] = true, ["="] = true, ["'"] = true }

local function Field(v)
	local t = type(v)
	if v == nil then return "" end
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return nil end
		-- (%.0f: %d overflows past 2^31 in this client's Lua)
		if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return ("#%.0f"):format(v) end
		return ("#%.17g"):format(v)
	end
	if t == "boolean" then return v and "!1" or "!0" end
	if t ~= "string" or v:find("[\t\n\r]") then return nil end
	if v == "" or MARK[v:sub(1, 1)] then return "'" .. v end
	return v
end

local function Value(f)
	if f == "" then return nil end
	local c = f:sub(1, 1)
	if c == "#" then return tonumber(f:sub(2)) end
	if c == "!" then return f == "!1" end
	if c == "'" then return f:sub(2) end
	return f
end

local function Split(line)
	local out, i = {}, 1
	for f in (line .. "\t"):gmatch("(.-)\t") do out[i] = f; i = i + 1 end
	return out, i - 1
end

--- A list of flat tables as one string, or nil.
function SV.Pack(list)
	if type(list) ~= "table" then return nil end
	local keys, seen = {}, {}
	for _, r in ipairs(list) do
		if type(r) ~= "table" then return nil end
		for k in pairs(r) do
			if not seen[k] then
				if type(k) ~= "string" and type(k) ~= "number" then return nil end
				seen[k] = true
				keys[#keys + 1] = k
			end
		end
	end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then return type(a) == "number" end
		return a < b
	end)
	local head = {}
	for i, k in ipairs(keys) do
		head[i] = Field(k)
		if not head[i] then return nil end
	end
	local lines, prev = { table.concat(head, "\t") }, {}
	for n, r in ipairs(list) do
		local row = {}
		for i, k in ipairs(keys) do
			local v = r[k]
			local f = Field(v)
			if not f then return nil end
			row[i] = (v ~= nil and n > 1 and prev[i] == f) and "=" or f
			prev[i] = f
		end
		lines[#lines + 1] = table.concat(row, "\t")
	end
	return table.concat(lines, "\n")
end

--- SV.Pack's string as the list again ({} for anything else).
function SV.Unpack(s)
	local out = {}
	if type(s) ~= "string" or s == "" then return out end
	local keys, prev
	for line in (s .. "\n"):gmatch("(.-)\n") do
		if not keys then
			keys = {}
			local fields, n = Split(line)
			for i = 1, n do keys[i] = Value(fields[i]) end
			prev = {}
		else
			local fields = Split(line)
			local r = {}
			for i, k in ipairs(keys) do
				local f = fields[i] or ""
				if f == "=" then f = prev[i] or "" end
				prev[i] = f
				if k ~= nil then r[k] = Value(f) end
			end
			out[#out + 1] = r
		end
	end
	return out
end

-- (a map as a packed list of {key, value}, in key order)
local function PackMap(map)
	if type(map) ~= "table" then return nil end
	local list = {}
	for k, v in pairs(map) do list[#list + 1] = { k, v } end
	table.sort(list, function(a, b)
		if type(a[1]) ~= type(b[1]) then return type(a[1]) == "number" end
		return a[1] < b[1]
	end)
	return SV.Pack(list)
end
local function UnpackMap(s)
	local out = {}
	for _, r in ipairs(SV.Unpack(s)) do if r[1] ~= nil then out[r[1]] = r[2] end end
	return out
end

-- Item qualities (item id -> 0..7, thousands of them): per quality, the ids in order as base-36 steps from the one
-- before ("q:step,step,...;"), three or four characters an item.
local function B36(n)
	local digits, s = "0123456789abcdefghijklmnopqrstuvwxyz", ""
	repeat
		local d = n % 36
		s = digits:sub(d + 1, d + 1) .. s
		n = (n - d) / 36
	until n == 0
	return s
end
local function PackQualities(map)
	local by = {}
	for id, q in pairs(map) do
		if type(id) ~= "number" or id < 0 or id ~= math.floor(id) or type(q) ~= "number" or q < 0 or q ~= math.floor(q) then
			return nil
		end
		by[q] = by[q] or {}
		by[q][#by[q] + 1] = id
	end
	local parts = {}
	for q, ids in pairs(by) do
		table.sort(ids)
		local steps, last = {}, 0
		for i, id in ipairs(ids) do steps[i] = B36(id - last); last = id end
		parts[#parts + 1] = q .. ":" .. table.concat(steps, ",")
	end
	table.sort(parts)
	return table.concat(parts, ";")
end
local function UnpackQualities(s)
	local out = {}
	if type(s) ~= "string" then return out end
	for q, steps in s:gmatch("(%d+):([^;]*)") do
		local last = 0
		q = tonumber(q)
		for step in steps:gmatch("[^,]+") do
			last = last + (tonumber(step, 36) or 0)
			out[last] = q
		end
	end
	return out
end

-- Each packed key's way in and out. Pack returns a new table (the live one isn't changed), nil when it can't.
local function Copy(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end
local function ListCodec()
	return {
		pack = function(v)
			local s = SV.Pack(v)
			return s and { packed = s } or nil
		end,
		unpack = function(v) return SV.Unpack(v.packed) end,
	}
end
SV.CODECS = {
	lootLog = ListCodec(),
	combatLog = ListCodec(),
	itemStore = {
		pack = function(v)
			local out = Copy(v)
			for kind, how in pairs({ quality = PackQualities, facts = PackMap }) do
				local t = v[kind]
				if type(t) == "table" and type(t.new) == "table" and type(t.old) == "table" then
					local new, old = how(t.new), how(t.old)
					if not (new and old) then return nil end
					out[kind] = { n = t.n, new = new, old = old }
				end
			end
			out.packed = 1
			return out
		end,
		unpack = function(v)
			local out = Copy(v)
			out.packed = nil
			for kind, how in pairs({ quality = UnpackQualities, facts = UnpackMap }) do
				local t = v[kind]
				if type(t) == "table" then out[kind] = { n = t.n, new = how(t.new), old = how(t.old) } end
			end
			return out
		end,
	},
	lootCache = {
		pack = function(v)
			if type(v.groups) ~= "table" then return nil end
			local s = SV.Pack(v.groups)
			if not s then return nil end
			local out = Copy(v)
			out.groups, out.packed = s, 1
			return out
		end,
		unpack = function(v)
			local out = Copy(v)
			out.groups, out.packed = SV.Unpack(v.groups), nil
			return out
		end,
	},
	talentCache = {
		pack = function(v)
			if type(v.classes) ~= "table" then return nil end
			local classes = {}
			for file, rows in pairs(v.classes) do
				classes[file] = SV.Pack(rows)
				if not classes[file] then return nil end
			end
			local out = Copy(v)
			out.classes, out.packed = classes, 1
			return out
		end,
		unpack = function(v)
			local out, classes = Copy(v), {}
			for file, s in pairs(v.classes or {}) do classes[file] = SV.Unpack(s) end
			out.classes, out.packed = classes, nil
			return out
		end,
	},
	talentDesc = {
		pack = function(v)
			if type(v.d) ~= "table" then return nil end
			local s = PackMap(v.d)
			if not s then return nil end
			local out = Copy(v)
			out.d, out.packed = s, 1
			return out
		end,
		unpack = function(v)
			local out = Copy(v)
			out.d, out.packed = UnpackMap(v.d), nil
			return out
		end,
	},
}

----------------------------------------------------------------------
-- How much is kept
----------------------------------------------------------------------

--- A group's level name (the player's pick, else its default).
function SV.Level(g)
	g = type(g) == "string" and SV.BY_NAME[g] or g
	if not (g and g.levels) then return nil end
	local picks = ns.db and rawget(ns.db, "savedKeep")
	local pick = type(picks) == "table" and picks[g.name]
	return g.levels[pick] and pick or g.default
end

--- How many of a group's records are kept between sessions (0: none; nil: all, it has no levels).
function SV.Limit(name)
	local g = SV.BY_NAME[name]
	if not (g and g.levels) then return nil end
	return g.levels[SV.Level(g)]
end

-- (a list newest first: the first n kept)
local function Head(list, n)
	if type(list) ~= "table" then return end
	for i = #list, n + 1, -1 do list[i] = nil end
end
-- (an item store kind: its newer generation first, then the older, up to n items)
local function TrimKind(t, n)
	if type(t) ~= "table" or type(t.new) ~= "table" or type(t.old) ~= "table" then return end
	local new, count = {}, 0
	for _, gen in ipairs({ t.new, t.old }) do
		for id, v in pairs(gen) do
			if count >= n then break end
			if new[id] == nil then new[id], count = v, count + 1 end
		end
	end
	t.new, t.old, t.n = new, {}, count
end

--- Each group cut down to what its level keeps (at logout, and when a level is picked).
function SV.Trim()
	local cache = SV.cache
	if not cache then return end
	for _, g in ipairs(SV.GROUPS) do
		local n = SV.Limit(g.name)
		if n == 0 then
			for _, k in ipairs(g.keys) do cache[k] = nil end
		elseif n and g.name == "items" then
			local s = cache.itemStore
			if type(s) == "table" and not s.packed then
				TrimKind(s.quality, n)
				TrimKind(s.facts, math.floor(n / 2))
			end
		elseif n and g.name == "loot" then
			if type(cache.lootLog) == "table" and not cache.lootLog.packed then Head(cache.lootLog, n) end
		elseif n and g.name == "combat" then
			local log = cache.combatLog
			if type(log) == "table" and not log.packed then
				-- (the log's own rule: deaths kept over crits, so "what killed me" still answers)
				local CB = ns.CombatLog
				if CB and CB.Trim then CB.Trim(log, n, math.min(CB.MAX_DEATHS or n, math.floor(n / 2))) else Head(log, n) end
			end
		end
	end
	if ns.ItemStore then ns.ItemStore.UseLimit(SV.Limit("items")) end
end

----------------------------------------------------------------------
-- Load and save
----------------------------------------------------------------------

--- The saved variables at load: the cache file made, a save from before the split moved into it, packed tables read
--- back, and ns.db passing the cache keys through. Returns TerminalDB.
function SV.Load()
	local db = type(_G.TerminalDB) == "table" and _G.TerminalDB or {}
	local cache = type(_G.TerminalCacheDB) == "table" and _G.TerminalCacheDB or {}
	_G.TerminalDB, _G.TerminalCacheDB = db, cache
	setmetatable(db, nil)
	-- (the old format: everything in Terminal.lua. Moved, unless the cache file has newer; then the old copy goes)
	for k in pairs(SV.KEY) do
		local v = rawget(db, k)
		if v ~= nil then
			if cache[k] == nil then cache[k] = v end
			rawset(db, k, nil)
		end
	end
	for k, codec in pairs(SV.CODECS) do
		local v = cache[k]
		if type(v) == "table" and v.packed then
			local ok, out = pcall(codec.unpack, v)
			cache[k] = ok and out or nil -- (unreadable: dropped, rebuilt or recorded again)
		end
	end
	cache.format = 1
	SV.cache = cache
	setmetatable(db, {
		__index = cache,
		__newindex = function(t, k, v)
			if SV.KEY[k] then cache[k] = v else rawset(t, k, v) end
		end,
	})
	if ns.ItemStore then ns.ItemStore.UseLimit(SV.Limit("items")) end
	return db
end

--- At logout (and /reload): trimmed to the levels kept, the big tables packed.
function SV.Save()
	local cache = SV.cache
	if not cache then return end
	pcall(SV.Trim)
	for k, codec in pairs(SV.CODECS) do
		local v = cache[k]
		if type(v) == "table" and not v.packed then
			local ok, out = pcall(codec.pack, v)
			if ok and out then cache[k] = out end
		end
	end
end

local saveFrame = CreateFrame("Frame")
saveFrame:RegisterEvent("PLAYER_LOGOUT")
saveFrame:SetScript("OnEvent", function() SV.Save() end)

----------------------------------------------------------------------
-- .saved
----------------------------------------------------------------------

-- (about how many bytes a value takes in a saved variables file)
local function Bytes(v, depth)
	local t = type(v)
	if t == "string" then return #v + 3 end
	if t == "number" then return #tostring(v) end
	if t == "boolean" then return 5 end
	if t ~= "table" or (depth or 0) > 20 then return 3 end
	local n = 4
	for k, x in pairs(v) do n = n + Bytes(k, (depth or 0) + 1) + Bytes(x, (depth or 0) + 1) + 6 end
	return n
end

--- About how many bytes a cache key will take on disk (as written: packed).
function SV.Size(k)
	local v = SV.cache and SV.cache[k]
	if v == nil then return 0 end
	local codec = SV.CODECS[k]
	if codec and type(v) == "table" and not v.packed then
		local ok, out = pcall(codec.pack, v)
		if ok and out then v = out end
	end
	return Bytes(v)
end

--- About how many bytes the settings file takes.
function SV.SettingsSize()
	local db = _G.TerminalDB
	if type(db) ~= "table" then return 0 end
	local n = 0
	for k, v in next, db do n = n + Bytes(k) + Bytes(v) + 6 end
	return n
end

local function KB(n) return ("%.1f KB"):format(n / 1024) end

local function LevelText(g)
	local level = SV.Level(g)
	if not level then return L["kept until cleared"] end
	local n = g.levels[level]
	if g.unit and n > 0 then return L["keep: %s (%d %s)"]:format(level, n, g.unit) end
	return L["keep: %s"]:format(level)
end

-- (a group's level names, smallest first)
local function LevelNames(g)
	local out = {}
	for name in pairs(g.levels) do out[#out + 1] = name end
	table.sort(out, function(a, b) return g.levels[a] < g.levels[b] end)
	return out
end

--- Something cleared or cut: the lists made from it read again (only those: every list built again was seconds of
--- background work for a log cut).
local function Changed(groups)
	for _, g in ipairs(groups) do
		for _, id in ipairs(g.lists or {}) do ns:Changed(id) end
	end
end

function SV.Report()
	local lines = { L["Terminal's saved data (sizes are estimates, as written at logout):"] }
	lines[#lines + 1] = ("  Terminal.lua  %s  %s"):format(KB(SV.SettingsSize()), L["settings, tabs, picks and search history"])
	local total, rows = 0, {}
	for _, g in ipairs(SV.GROUPS) do
		local n = 0
		for _, k in ipairs(g.keys) do n = n + SV.Size(k) end
		total = total + n
		rows[#rows + 1] = ("    %-10s %9s  %s · %s%s"):format(g.name, KB(n), g.label, LevelText(g),
			g.rebuilt and (" · " .. L["rebuilt when needed"]) or "")
	end
	lines[#lines + 1] = ("  TerminalCache.lua  %s  %s"):format(KB(total), L["what Terminal recorded and learned (safe to delete)"])
	for _, r in ipairs(rows) do lines[#lines + 1] = r end
	lines[#lines + 1] = L[".saved keep <name> <level>, .saved keep all minimal|normal|everything, .saved clear <name>"]
	return lines
end

ns:RegisterCommand("saved", {
	desc = L["What Terminal keeps in its saved variables, how big it is, and how much of it to keep (.saved keep, .saved clear)"],
	-- (every choice whole, matched against all that's typed: a bare "keep" or "clear" only printed "Keep what?")
	complete = function()
		local out = {
			{ "keep all minimal", L["keep as little as possible"] },
			{ "keep all normal", L["the usual amounts"] },
			{ "keep all everything", L["keep the most"] },
		}
		for _, g in ipairs(SV.GROUPS) do
			if g.levels then
				for _, level in ipairs(LevelNames(g)) do out[#out + 1] = { ("keep %s %s"):format(g.name, level), g.label } end
			end
		end
		for _, g in ipairs(SV.GROUPS) do out[#out + 1] = { "clear " .. g.name, g.label } end
		out[#out + 1] = { "clear all", L["everything in TerminalCache.lua"] }
		return out
	end,
	run = function(args)
		local words = {}
		for w in tostring(args or ""):gmatch("%S+") do words[#words + 1] = ns.Lower(w) end
		local verb, name, level = words[1], words[2], words[3]
		if verb == "keep" then
			if name == "all" then
				local preset = SV.PRESETS[level or ""]
				if not preset then return { L["Pick minimal, normal or everything: .saved keep all normal"] } end
				local picks = {}
				for g, l in pairs(preset) do picks[g] = l end
				rawset(ns.db, "savedKeep", next(picks) and picks or nil)
				SV.Trim()
				Changed(SV.GROUPS)
				return { L["Keeping %s from now on."]:format(level) }
			end
			local g = SV.BY_NAME[name or ""]
			if not (g and g.levels) then
				local names = {}
				for _, x in ipairs(SV.GROUPS) do if x.levels then names[#names + 1] = x.name end end
				return { L["Keep what? %s"]:format(table.concat(names, ", ")) }
			end
			if not g.levels[level or ""] then
				return { L["%s: pick %s"]:format(g.name, table.concat(LevelNames(g), ", ")) }
			end
			local picks = rawget(ns.db, "savedKeep")
			if type(picks) ~= "table" then picks = {}; rawset(ns.db, "savedKeep", picks) end
			picks[g.name] = level ~= g.default and level or nil
			if not next(picks) then rawset(ns.db, "savedKeep", nil) end
			SV.Trim()
			Changed({ g })
			return { ("%s: %s"):format(g.label, LevelText(g)) }
		elseif verb == "clear" then
			local list = {}
			if name == "all" then list = SV.GROUPS else list[1] = SV.BY_NAME[name or ""] end
			if not list[1] then return { L["Clear what? .saved lists the names"] } end
			for _, g in ipairs(list) do
				for _, k in ipairs(g.keys) do SV.cache[k] = nil end
			end
			Changed(list)
			return { name == "all" and L["Cleared everything in TerminalCache.lua."] or L["Cleared %s."]:format(list[1].label) }
		end
		return SV.Report()
	end,
})
