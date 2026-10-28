local ns = select(2, ...)

-- What Terminal has learned of items, kept between sessions (0.51.13, the player's ask: after a /reload "upgrades" and
-- the loot list's colours filled in bit by bit as the game sent its items again). Kinds: "quality" (item id -> its
-- quality) and "facts" (item id -> what is:upgrade reads of it, Upgrades.lua's record). Each kind keeps two
-- generations of at most S.CAP[kind] items (the older dropped when the newer is full), and all of it is let go when the
-- game's build changes (a patch may change items).
local S = {}
ns.ItemStore = S
S.VERSION = 4 -- (2: "usable" kept per character, not per class; 0.51.25. 3: spells' hit and crit, feral attack power: 0.56.14.
-- 4: block value, spell schools, a ranged weapon's DPS: 0.65.11)
S.CAP = { quality = 4000, facts = 2000 } -- (the .saved keep level's: S.UseLimit, set at load)

local cur -- (the store as found this session: { db = ns.db, t = the saved table })
local function Root()
	local db = ns.db
	if type(db) ~= "table" then return nil end
	if cur and cur.db == db and db.itemStore == cur.t then return cur.t end
	local ok, _, build = pcall(_G.GetBuildInfo)
	build = ok and tostring(build) or "?"
	local t = db.itemStore
	if type(t) == "table" and t.packed then return nil end -- (written for the save at logout: Saved.lua)
	if type(t) ~= "table" or t.build ~= build or t.v ~= S.VERSION then
		t = { build = build, v = S.VERSION }
		db.itemStore = t
	end
	cur = { db = db, t = t }
	return t
end

local function Kind(kind)
	local root = Root()
	if not root then return nil end
	local t = root[kind]
	if type(t) ~= "table" or type(t.new) ~= "table" or type(t.old) ~= "table" then
		t = { new = {}, old = {}, n = 0 }
		root[kind] = t
	end
	return t
end

--- What's kept of an item (nil: nothing). One found in the older generation is kept on in the newer.
function S.Get(kind, id)
	local t = Kind(kind)
	if not t or id == nil then return nil end
	local v = t.new[id]
	if v ~= nil then return v end
	v = t.old[id]
	if v ~= nil then S.Put(kind, id, v) end
	return v
end

--- Keep what was learned of an item.
function S.Put(kind, id, v)
	local t = Kind(kind)
	if not t or id == nil or v == nil then return end
	if t.new[id] == v then return end
	if t.new[id] == nil then
		t.n = (tonumber(t.n) or 0) + 1
		if t.n > (S.CAP[kind] or 1000) then t.old, t.new, t.n = t.new, {}, 1 end
	end
	t.new[id] = v
end

--- The player's .saved keep for item details (Saved.lua): each generation that many qualities, half as many facts
--- (0: nothing kept between sessions, a session still remembers the defaults' worth).
S.CAP_DEFAULT = { quality = 4000, facts = 2000 }
function S.UseLimit(n)
	n = tonumber(n) or 0
	if n <= 0 then n = S.CAP_DEFAULT.quality end
	S.CAP = { quality = n, facts = math.floor(n / 2) }
end

--- How many items each kind keeps now (tests).
function S.Count(kind)
	local t = Kind(kind)
	if not t then return 0 end
	local n = 0
	for _ in pairs(t.new) do n = n + 1 end
	for k in pairs(t.old) do if t.new[k] == nil then n = n + 1 end end
	return n
end

--- (tests: a new session, the game's build looked at again)
function S.NewSession() cur = nil end

--- Forget a kind (tests).
function S.Clear(kind)
	local root = Root()
	if root then root[kind] = nil end
end
