local ns = select(2, ...)
local L = ns.L
local OA = ns.OneForAll

-- OneForAll's dungeon bosses: each one's level (BOSS_LEVELS, or the level its own GetBossLevel learned in game), its
-- creature type (BOSS_TYPES, GetBossType) and whether it only comes when summoned (BOSS_SUMMONED), by its dungeon's boss
-- list (DUNGEONS: name, npcID). Read while OneForAll is installed, never copied. Said on @loot's tooltips (Loot.lua's
-- I.LootTipMore), in "what level is vancleef" (Suggest.lua's LevelOf) and by "summoned bosses in blackrock spire".

local B = {}
OA.Bosses = B
ns.OneForAllBosses = B
local Num, Lower = ns.Num, ns.Lower
local SEP = ns.DETAIL_SEP
local Words = OA.Words

--- Its bosses, checked: { list = { { name, words, npc, inst, iwords, boss (OneForAll's own record) } }, byNpc, byName,
--- byPlace ("<instance words>\001<boss words>") }, or nil.
function B.Data()
	return OA.Part("bosses", "DUNGEONS", L["Its bosses' levels and types are unavailable."], function(raw)
		local out = { list = {}, byNpc = {}, byName = {}, byPlace = {} }
		for _, d in ipairs(raw) do
			local inst = type(d) == "table" and OA.Text(d.name)
			if inst and type(d.bosses) == "table" then
				local iw = Words(inst)
				for _, b in ipairs(d.bosses) do
					local name = type(b) == "table" and OA.Text(b.name)
					if name then
						local r = { name = name, words = Words(name), npc = Num(b.npcID), inst = inst, iwords = iw, boss = b }
						out.list[#out.list + 1] = r
						if r.npc and not out.byNpc[r.npc] then out.byNpc[r.npc] = r end
						if not out.byName[r.words] then out.byName[r.words] = r end
						out.byPlace[iw .. "\001" .. r.words] = r
						for _, a in ipairs(type(b.aliases) == "table" and b.aliases or {}) do
							if OA.Text(a) and not out.byName[Words(a)] then out.byName[Words(a)] = r end
						end
					end
				end
			end
		end
		if #out.list == 0 then return nil, "OneForAll.DUNGEONS: no boss in the shape expected" end
		return out
	end, true)
end

--- The boss an NPC id, or a boss's and its instance's names, are (OneForAll's English names: on another client only
--- the id finds it), or nil.
function B.Find(boss, inst, npc)
	local d = B.Data()
	if not d then return nil end
	if npc and d.byNpc[npc] then return d.byNpc[npc] end
	if type(boss) ~= "string" then return nil end
	local bw = Words(ns.Plain(boss))
	if type(inst) == "string" then
		local r = d.byPlace[Words(ns.Plain(inst)) .. "\001" .. bw]
		if r then return r end
	end
	return d.byName[bw]
end

--- A boss by what's typed ("vancleef", "edwin vancleef"): its whole name, else the first whose name has those words
--- whole; nil.
function B.Named(what)
	local d = B.Data()
	if not (d and type(what) == "string" and what ~= "") then return nil end
	local w = Words(what)
	if d.byName[w] then return d.byName[w] end
	if #w < 4 then return nil end
	local pad = " " .. w .. " "
	for _, r in ipairs(d.list) do
		if (" " .. r.words .. " "):find(pad, 1, true) then return r end
	end
end

--- What OneForAll says of a boss: its level (text: "51", "61-62"), its creature type, summoned or not.
function B.Info(r)
	local lib = OA.Lib()
	if not (lib and r) then return nil, nil, false end
	local level = OA.Text(OA.Call(lib.GetBossLevel, lib, r.boss))
	if not level then
		local t = type(lib.BOSS_LEVELS) == "table" and lib.BOSS_LEVELS or {}
		level = OA.Text((r.npc and t[r.npc]) or t[r.name])
	end
	if level == "??" or level == "?" then level = nil end
	local ctype = OA.Text(OA.Call(lib.GetBossType, lib, r.boss))
	if not ctype and r.npc and type(lib.BOSS_TYPES) == "table" then ctype = OA.Text(lib.BOSS_TYPES[r.npc]) end
	local summoned = r.npc ~= nil and type(lib.BOSS_SUMMONED) == "table" and lib.BOSS_SUMMONED[r.npc] == true
	return level, ctype, summoned
end

--- A boss's level, type and "Summoned" as one line ("Level 59  ·  Dragonkin  ·  Summoned"; `noLevel`: without the
--- level), or nil when OneForAll says none of them.
function B.Said(r, noLevel)
	local level, ctype, summoned = B.Info(r)
	local parts = {}
	if level and not noLevel then parts[#parts + 1] = L["Level %s"]:format(level) end
	if ctype then parts[#parts + 1] = ctype end
	if summoned then parts[#parts + 1] = L["Summoned"] end
	return #parts > 0 and table.concat(parts, SEP) or nil
end

--- A boss's level as two numbers (lo, hi), or nil.
function B.Levels(r)
	local level = B.Info(r)
	local lo, hi = tostring(level or ""):match("^(%d+)%s*%-%s*(%d+)$")
	if lo then return tonumber(lo), tonumber(hi) end
	lo = tonumber(level or "")
	return lo, lo
end

OA.AddStatus(function()
	local d = B.Data()
	return d and L["boss levels and types (on @loot)"] or nil
end)

----------------------------------------------------------------------
-- "summoned bosses in blackrock spire", "which bosses are summoned", "summonable bosses in stratholme"
----------------------------------------------------------------------

local SUMMON = { summoned = true, summonable = true, summon = true }
local BOSS = { boss = true, bosses = true }
local FILL = { ["in"] = true, of = true, the = true, at = true, ["for"] = true, all = true, list = true, show = true, what = true,
	which = true, are = true, is = true, me = true, can = true, be = true, i = true, that = true, who = true, get = true, need = true,
	to = true, a = true, an = true, only = true, dungeon = true, dungeons = true, instance = true }

--- The question: { inst = the instances' words asked (nil: every one), place }, or nil.
function B.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local summon, boss, rest = false, false, {}
	for w in t:gmatch("%S+") do
		if SUMMON[w] then summon = true elseif BOSS[w] then boss = true elseif not FILL[w] then rest[#rest + 1] = w end
	end
	if not (summon and boss) then return nil end
	local d = B.Data()
	if not d then return nil end
	if #rest == 0 then return {} end
	local want = table.concat(rest, " ")
	-- (an instance's words, or its shorthand's: "ubrs", "blackrock spire" = both spires)
	local S = ns.Shorthand
	local wants = { want }
	for _, f in ipairs(S and type(S[want]) == "table" and S[want] or {}) do if type(f) == "string" then wants[#wants + 1] = Words(f) end end
	local found = {}
	for _, r in ipairs(d.list) do
		for _, w in ipairs(wants) do
			if (" " .. r.iwords .. " "):find(" " .. w .. " ", 1, true) then found[r.iwords] = true end
		end
	end
	if not next(found) then return nil end
	return { inst = found, place = ns.UpperFirst(want) }
end

local function BossWalk(e)
	local P = ns.Pipes
	local line = P and P.Phrase and P.Phrase(e.name, "drops") or (e.name .. " > drops")
	if ns.UI and ns.UI.WalkTo then ns.UI:WalkTo(line, e) end
end
B.Walk = BossWalk -- (Suggest.lua's bosses of an instance walk the same way)

function B.Answer(q)
	q = q or {}
	local d = B.Data()
	local rows = {}
	for _, r in ipairs(d and d.list or {}) do
		if not q.inst or q.inst[r.iwords] then
			local level, ctype, summoned = B.Info(r)
			if summoned then
				local parts = { r.inst }
				if level then parts[#parts + 1] = L["Level %s"]:format(level) end
				if ctype then parts[#parts + 1] = ctype end
				rows[#rows + 1] = { key = "boss:" .. r.name .. ":" .. r.inst, name = r.name, kind = "pipe", kindLabel = L["Bosses"],
					detail = table.concat(parts, SEP), activate = BossWalk, staysOpen = true,
					icon = "Interface\\Icons\\INV_Misc_Bone_ElfSkull_01", _lname = Lower(r.name) }
			end
		end
	end
	table.sort(rows, function(a, b) if a.detail ~= b.detail then return a.detail < b.detail end return a.name < b.name end)
	local title = L["Bosses"] .. SEP .. L["Summoned"] .. (q.place and (SEP .. q.place) or "")
	if #rows == 0 then return { ns.NoteRow(L["OneForAll knows no summoned boss there"]) }, title end
	ns.ScoreInOrder(rows)
	return rows, title
end
