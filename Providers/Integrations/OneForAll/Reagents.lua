local ns = select(2, ...)
local L = ns.L
local OA = ns.OneForAll

-- Where to get a reagent, OneForAll's way (its REAGENT_SOURCES, read while it's installed, never copied): for the
-- reagents QuestieDB has no source for, it says (from Wowhead's Forever pages, its header says) what they're skinned
-- from (`sk`: NPC ids, or a kind of creature), where they're fished (`f`: "Zone, Zone"), the item levels disenchanted
-- for them (`de`: { lowest, highest }), the item they're found in (`ci`: its name) and what makes them (`c`: { skill
-- line, "1x Copper Ore" }). Its vendors and droppers (v, d) are Questie's already. A "sources" definition of its own
-- (Search/Steps/Chains.lua runs every definition): "where to farm heavy hide" says the beasts to skin (NPC rows: Enter
-- shows one on the map), "where to find raw summer bass" its zones (Enter: the map), a shard the item levels to
-- disenchant, a clam's meat the clam (Enter: where to get the clam).

local RS = {}
OA.Reagents = RS
local Lower, Num, Str = ns.Lower, ns.Num, ns.Str
local FIELDS = { "sk", "f", "de", "ci", "c" } -- (those Terminal says: an entry with none of them is left out)

--- Its sources, checked: the table itself (each entry read as it's asked for) and how many say something Terminal
--- shows: { raw, n }, or nil.
function RS.Data()
	return OA.Part("reagentSources", "REAGENT_SOURCES", L["Where to get reagents by skinning, fishing or disenchanting (OneForAll) is unavailable."],
		function(raw)
			local n = 0
			for id, s in pairs(raw) do
				if type(id) == "number" and type(s) == "table" then
					for _, f in ipairs(FIELDS) do if s[f] ~= nil then n = n + 1 break end end
				end
			end
			if n == 0 then return nil, "OneForAll.REAGENT_SOURCES: no item with sk, f, de, ci or c" end
			return { raw = raw, n = n }
		end, true)
end

-- a "A, B" text or a list of texts: the texts
local function Texts(v)
	local out = {}
	if type(v) == "string" then
		for part in (v .. ","):gmatch("([^,]*),") do
			part = part:gsub("^%s+", ""):gsub("%s+$", "")
			if part ~= "" then out[#out + 1] = part end
		end
	elseif type(v) == "table" then
		for _, s in ipairs(v) do if Str(s) then out[#out + 1] = s end end
	end
	return out
end

--- An item's sources, checked: { sk = { NPC ids or names }, f = { zones }, de = { lo, hi }, ci = { names }, c = { skill,
--- text } } (only those it has), or nil.
function RS.Of(id)
	local d = type(id) == "number" and RS.Data()
	local s = d and d.raw[id]
	if type(s) ~= "table" then return nil end
	local out, any = {}, false
	if s.sk ~= nil then
		local sk = {}
		for _, v in ipairs(type(s.sk) == "table" and s.sk or { s.sk }) do
			if Num(v) or Str(v) then sk[#sk + 1] = v end
		end
		if #sk > 0 then out.sk, any = sk, true end
	end
	local f = Texts(s.f)
	if #f > 0 then out.f, any = f, true end
	if type(s.de) == "table" and Num(s.de[1]) and Num(s.de[2]) then out.de, any = { s.de[1], s.de[2] }, true end
	local ci = Texts(s.ci)
	if #ci > 0 then out.ci, any = ci, true end
	if type(s.c) == "table" and Str(s.c[2]) then out.c, any = { Num(s.c[1]) or 0, s.c[2] }, true end
	return any and out or nil
end

local ICON_FISH, ICON_DE, ICON_CRAFT = "Interface\\Icons\\Trade_Fishing", "Interface\\Icons\\INV_Enchant_Disenchant",
	"Interface\\Icons\\Trade_Mining"
local function Plain(key, name, detail, icon)
	return { key = key, kind = "source", name = name, detail = detail, icon = icon, noActivate = true }
end

-- a profession's name in the game's words (Chains.lua's AtlasLoot numbers: 12 Skinning, 11 Fishing, 10 Enchanting, 7
-- Mining)
local function Prof(n)
	local P = ns.Pipes
	local pr = P and P.AL_PROFS and P.AL_PROFS[n]
	return pr and P.ProfName and P.ProfName(pr) or (pr and pr[3]) or nil
end

-- the zone a fishing source names: its @map row (Enter: the map) with the skill it needs, else just its name
local function FishRow(zone, lib)
	local Z, M = ns.Zones, ns.Maps
	local z = Z and Z.ByName and Z.ByName(zone)
	local fishing = Prof(11)
	if z and Z.Row and M and M.Key then
		local row = Z.Row(z, (Z.FishText and Z.FishText(z)) or fishing)
		row._score, row.pipeHow = nil, L["fished in"]
		return row
	end
	local shown = type(lib.ZoneName) == "function" and Str(OA.Call(lib.ZoneName, zone)) or zone
	local r = Plain("fish:" .. zone, shown, fishing, ICON_FISH)
	r.pipeHow = L["fished in"]
	return r
end

local function AddRows(out, id, s, lib)
	local P, I = ns.Pipes, ns.Integrations
	if s.sk then
		local skinning = Prof(12)
		local ids, names = {}, {}
		local mobs = type(lib.REAGENT_MOBS) == "table" and lib.REAGENT_MOBS or {}
		for _, v in ipairs(s.sk) do
			if type(v) ~= "number" then
				names[#names + 1] = v -- (a kind of creature)
			elseif I and I.NpcRow and I.NpcRow(v) then
				ids[#ids + 1] = v
			else
				-- (one Questie doesn't know, or no Questie: the name OneForAll gives it)
				local m = mobs[v]
				local name = type(m) == "table" and Str(m[1])
				if name then names[#names + 1] = name end
			end
		end
		if #ids > 0 and P.AddNpcs then P.AddNpcs(out, I, ids, skinning, 15, L["skinned from"]) end
		for k, name in ipairs(names) do
			if k > 15 then break end
			local r = Plain("skin:" .. name, name, skinning, "Interface\\Icons\\INV_Misc_Pelt_Wolf_01")
			r.pipeHow = L["skinned from"]
			out[#out + 1] = r
		end
	end
	for _, zone in ipairs(s.f or {}) do out[#out + 1] = FishRow(zone, lib) end
	if s.de then
		local r = Plain("de:" .. id, L["Disenchanting items of item level %d-%d"]:format(s.de[1], s.de[2]), Prof(10), ICON_DE)
		out[#out + 1] = r
	end
	-- (the item it's found in, by name: its row when Questie knows the name, Enter its sources)
	for _, name in ipairs(s.ci or {}) do
		local F = ns.Filters
		local bid = F and F.QuestieItemIds and F.QuestieItemIds(Lower(name))[1]
		local r = bid and P.ItemRow and P.ItemRow(bid, L["Contains it"], L["found in"])
		if not r then
			r = Plain("in:" .. name, name, L["Contains it"], "Interface\\Icons\\INV_Misc_Bag_10")
			r.pipeHow = L["found in"]
		end
		out[#out + 1] = r
	end
	-- (made: said only when neither your recipes nor AtlasLoot's crafts say it already)
	if s.c and not (P.Reagents and P.Reagents({ itemID = id })) then
		out[#out + 1] = Plain("ofacraft:" .. id, s.c[2], ns.Detail(L["Crafted"], s.c[1] == 186 and Prof(7) or nil), ICON_CRAFT)
	end
end

OA.AddSetup(function()
	if not RS.Data() or RS.relation or not ns.RegisterRelation or not ns.Pipes then return end
	RS.relation = true
	local P = ns.Pipes
	ns:RegisterRelation("sources", {
		aliases = {},
		desc = L["where to get it"],
		available = function() return RS.Data() ~= nil end, addon = "OneForAll",
		applies = function(e) return RS.Of(P.ItemOf(e)) ~= nil end,
		run = function(rows)
			local out = {}
			local lib = OA.Lib() or {}
			for _, e in ipairs(rows) do
				local id = P.ItemOf(e)
				AddRows(out, id, RS.Of(id), lib)
			end
			return out
		end,
	})
end)
OA.AddStatus(function()
	local d = RS.Data()
	return d and L["%d reagents' sources (where to get)"]:format(d.n) or nil
end)
