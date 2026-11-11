local ns = select(2, ...)
local L = ns.L

-- What a token turns into, and what an item comes from: AtlasLoot's token data (AtlasLootClassic/Data/Token.lua: its
-- public AtlasLoot.Data.Token.GetTokenData and GetClassItemsForToken), read in the game, never copied. A token's data is
-- a list of items ({ id, count } or an id; 0 starts a new group; "CLASS_WARRIOR" starts a class's group) and a type
-- that says what the list is: what it's turned in for (Dire Maul's books, Zul'Gurub's and Ahn'Qiraj's pieces, the
-- tier tokens, a Libram's arcanum), what it holds (a sack of gems), a quest's rewards (Head of Onyxia). Only the first
-- group is what it gives, unless the groups are classes' (each class its own) or the list is what it holds (every
-- group); a list of what it's bought with, or the crafts it's a reagent for, gives nothing.
--
--   libram of focus > rewards        "what does libram of focus give": what you get for it (your class's first)
--   black pearl > sources            "where to find black pearl": ... and "Blue Sack of Gems  Contains it"
--
-- "rewards" is a quest's (Rewards.lua) and a faction's (OneForAll's Armory.lua) too: this definition is the tokens'.
-- The tokens looked at are the items of AtlasLoot's loot list (@loot): the reverse ("what gives it") is made once per
-- list.

local TK = {}
ns.Tokens = TK
local Safe, Str, Lower = ns.Safe, ns.Str, ns.Lower
local SEP = ns.DETAIL_SEP

-- the types whose every group is what it gives (possible items, quest rewards, loot, contents); those giving nothing:
-- a reagent for crafts, bought with, achievements
local ALL_GROUPS = { [2] = true, [3] = true, [9] = true, [11] = true }
local NONE = { [5] = true, [7] = true, [10] = true }
local HOLDS = { [2] = true, [11] = true } -- (said "Contains it", not "Gives it")
TK.DUMMY = 900000 -- (AtlasLoot's numbers from here up stand for no item)

local function Token()
	local AL = rawget(_G, "AtlasLoot")
	local D = type(AL) == "table" and AL.Data
	local T = type(D) == "table" and D.Token
	return type(T) == "table" and type(T.GetTokenData) == "function" and T or nil
end
TK.Api = Token

-- what each token gives, kept (its data never changes): id -> list or false
local gives, givesCount = {}, 0

--- What a token gives: { { id, count (a number or AtlasLoot's "1-3"), class ("WARRIOR") } }, or nil (not a token,
--- or nothing it gives).
function TK.Gives(token)
	if type(token) ~= "number" then return nil end
	local got = gives[token]
	if got ~= nil then return got or nil end
	local T = Token()
	if not T then return nil end -- (not kept: AtlasLoot may come later)
	local data = Safe(T.GetTokenData, token)
	if type(data) == "number" then data = Safe(T.GetTokenData, data) end -- (a card names its deck: read before AtlasLoot's init)
	local out
	if type(data) == "table" and not NONE[data.type] then
		local all = ALL_GROUPS[data.type] or false
		local class = type(data.type) == "string" and data.type:match("^%u+$") or nil -- (a Dire Maul book: its class's)
		local byClass = false
		out = {}
		for _, v in ipairs(data) do
			if v == 0 then
				if byClass then class = nil elseif not all then break end
			elseif type(v) == "string" then
				local c = v:match("^CLASS_(%u+)$") -- ("prof1234": a craft, not an item)
				if c then class, byClass = c, true end
			else
				local id, count = v, nil
				if type(v) == "table" then id, count = v[1], v[2] end
				if type(id) == "number" and id > 0 and id < TK.DUMMY and id ~= token and (class or not byClass) then
					out[#out + 1] = { id = id, count = count, class = class }
				end
			end
		end
		if #out == 0 then out = nil end
	end
	-- (every loot item is asked once: most are no token, kept as false)
	if givesCount > 40000 then gives, givesCount = {}, 0 end
	gives[token], givesCount = out or false, givesCount + 1
	return out
end
TK.Forget = function() gives, givesCount = {}, 0; TK.index = nil end -- (tests)

--- Does it give what it holds ("Contains it": a sack, a bag) rather than what it's turned in for?
function TK.Holds(token)
	local T = Token()
	local data = T and Safe(T.GetTokenData, token)
	return type(data) == "table" and HOLDS[data.type] == true
end

-- the loot list's tokens, made once per list: { list, ids (token ids), from (an item -> the tokens giving it), names
-- (lowercase name -> token id), whole (every token's name was in) }
local function Index()
	local p = ns.providers.loot
	local list = p and ns:GetEntries(p) or {}
	local x = TK.index
	if not (x and x.list == list) then
		x = { list = list, ids = {}, from = {}, names = {}, whole = false }
		TK.index = x
		if Token() then
			local seen = {}
			for _, l in ipairs(list) do
				local id = l.itemID
				if type(id) == "number" and not seen[id] then
					seen[id] = true
					local g = TK.Gives(id)
					if g then
						x.ids[#x.ids + 1] = id
						for _, it in ipairs(g) do
							local f = x.from[it.id]
							if not f then f = {}; x.from[it.id] = f end
							f[#f + 1] = { token = id, class = it.class }
						end
					end
				end
			end
		end
	end
	-- (names: the game's, as they come in; looked at again only while some are missing, once a second at most: an item
	-- the client never names would have had every keystroke read them all, 1.3.13, review)
	local now = GetTime and GetTime() or 0
	if not x.whole and (not x.namesAt or now - x.namesAt >= 1) then
		x.namesAt = now
		local all = true
		local get = C_Item and C_Item.GetItemNameByID
		for _, id in ipairs(x.ids) do
			local n = get and Str(Safe(get, id))
			if n then x.names[Lower(n)] = id else all = false end
		end
		x.whole = all
	end
	return x
end
TK.Index = Index

--- Do these (lowercase) words name a token AtlasLoot knows (exactly, or but for a leading article)? (Chains.lua's
--- phrases: "what does libram of focus give")
function TK.Named(what)
	if type(what) ~= "string" or what == "" or not Token() then return false end
	local names = Index().names
	if names[what] then return true end
	for _, a in ipairs(ns.Pipes and ns.Pipes.ARTICLES or {}) do if names[a .. what] then return true end end
	return false
end

-- your class as the token data names it ("WARRIOR"), and a class's name in the game's words
local function MyClass() return Str(UnitClass and select(2, Safe(UnitClass, "player"))) end
local function ClassName(c)
	local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
	return type(names) == "table" and Str(names[c]) or (c:sub(1, 1) .. Lower(c:sub(2)))
end
TK.ClassName = ClassName

local function Count(c)
	if type(c) == "number" and c > 1 then return "x" .. c end
	if type(c) == "string" and c ~= "" and c ~= "1" then return "x" .. c end
end

local P = ns.Pipes
if ns.RegisterRelation and P then
	P.TokenNamed = TK.Named
	-- "libram of focus > rewards", "what does libram of focus give": what it's turned in for (your class's first, then
	-- the other classes', each said)
	ns:RegisterRelation("rewards", {
		aliases = { "turnsinto", "contains", "token" },
		desc = L["what a token or a bag turns into (AtlasLoot)"],
		available = function() return Token() ~= nil end, addon = "AtlasLoot",
		applies = function(e) return TK.Gives(P.ItemOf(e)) ~= nil end,
		run = function(rows)
			local out, seen = {}, {}
			local T, me = Token(), MyClass()
			for _, e in ipairs(rows) do
				local token = P.ItemOf(e)
				local name = Str(e.name) or tostring(token)
				local list = TK.Gives(token) or {}
				-- (AtlasLoot's own pick for your class, when it has one: first)
				local mine = {}
				local yours = me and T and T.GetClassItemsForToken and Safe(T.GetClassItemsForToken, token, me)
				for _, v in ipairs(type(yours) == "table" and yours or {}) do
					local id = type(v) == "table" and v[1] or v
					if type(id) == "number" then mine[id] = true end
				end
				local first, rest = {}, {}
				for _, it in ipairs(list) do
					if mine[it.id] or (it.class and it.class == me) then first[#first + 1] = it else rest[#rest + 1] = it end
				end
				for _, group in ipairs({ first, rest }) do
					for _, it in ipairs(group) do
						if #out >= P.MAX_OUT then break end
						if not seen[it.id] then
							local r = P.ItemRow(it.id, ns.Detail(it.class and ClassName(it.class), Count(it.count), L["From %s"]:format(name)))
							if r then seen[it.id] = true; out[#out + 1] = r end
						end
					end
				end
			end
			return out
		end,
	})
	-- "where to get <item>": the tokens it comes from ("Libram of Focus  Gives it"; Enter: where to get the token)
	ns:RegisterRelation("sources", {
		aliases = {},
		desc = L["where to get it"],
		available = function() return Token() ~= nil end, addon = "AtlasLoot",
		applies = function(e) return P.ItemOf(e) ~= nil and Token() ~= nil end,
		run = function(rows)
			local out = {}
			local x = Index()
			for _, e in ipairs(rows) do
				for k, f in ipairs(x.from[P.ItemOf(e)] or {}) do
					if k > 15 then break end
					local holds = TK.Holds(f.token)
					local r = P.ItemRow(f.token, ns.Detail(holds and L["Contains it"] or L["Gives it"], f.class and ClassName(f.class)),
						holds and L["found in"] or L["from"])
					if r then out[#out + 1] = r end
				end
			end
			return out
		end,
	})
end
