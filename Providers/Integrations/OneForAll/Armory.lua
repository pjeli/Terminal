local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local OA = ns.OneForAll

-- Reputation rewards and @itemset, OneForAll's armory: what each faction's quartermaster sells at each standing (and
-- yours: can you buy it yet), the item sets (each class's, the dungeon and raid sets, how many pieces you have, the
-- bonuses) and their pieces (where each comes from, yours or not). "argent dawn rewards", "what can i buy at honored",
-- "my class sets", "pieces of battlegear of might" ask for them (Simple mode). 1.0.10 (the player: too many kinds): a
-- set's pieces are no kind of their own (was @setpiece) but @itemset's rows that only "<set> > pieces", Enter on a set
-- and "pieces of <set>" list, as Attune's steps are; a set's text has its pieces' names and sources, so "@itemset
-- onyxia" finds the sets with a piece from Onyxia. 1.0.11 (the same call): the rewards are no kind of their own either
-- (was @repreward) but @reputation's rows (`repReward`), in its list with the factions since 1.0.27 (the player:
-- "@reputation shows only Orgrimmar"): @reputation is:reward, is:canbuy, standing:, sort:standing, Group by faction or
-- standing; the questions ("argent dawn rewards", "what can i buy at honored") and "<faction> > rewards" list them too.
--
-- OneForAll's ranks run 0-7 (4 Friendly .. 7 Exalted); the game's standings 1-8 (5 Friendly .. 8 Exalted): a reward's
-- standing is its rank + 1, as the reputation list reads it (`reaction`: the standing it needs).

local A = {}
OA.Armory = A
ns.Armory = A
local Safe, Lower, Num = ns.Safe, ns.Lower, ns.Num
local SEP = ns.DETAIL_SEP
local ICONS = "Interface\\Icons\\"
local STANDING_ENGLISH = ns.STANDING_ENGLISH -- (Util.lua)

-- an icon as OneForAll gives it: a file id, or an icon's name
local function Icon(v, fallback)
	-- (0: no icon, OneForAll's unnamed pieces)
	if type(v) == "number" then return v > 0 and v or fallback end
	local s = OA.Text(v)
	if s and s:match("^%d+$") then return tonumber(s) > 0 and tonumber(s) or fallback end
	return s and (ICONS .. s) or fallback
end

--- A standing's name (1-8): the game's, else English (ns.StandingName, Util.lua).
function A.StandingName(st) return ns.StandingName(st) or "?" end

--- Your standing with a faction (1-8), or nil (not met, or the game won't say).
function A.Standing(fid)
	local C = rawget(_G, "C_Reputation")
	if type(C) == "table" and C.GetFactionDataByID then
		local d = Safe(C.GetFactionDataByID, fid)
		if type(d) == "table" and d.name then return Num(d.reaction) end
	end
	local f = rawget(_G, "GetFactionInfoByID")
	if f then
		local name, _, st = Safe(f, fid)
		if name then return Num(st) end
	end
	return nil
end

local MySide = OA.Side

--- Its factions, checked: { { id, name, side, vendors = { { npcID, name, ui, x, y, zone } }, items = { { id, name, slot,
--- quality, icon, need (1-8), what ("gear", "recipe", "other"), vendors = { npcID... } } } } }, or nil. Those not in
--- WoW Forever yet (st 0) are left out.
function A.Factions()
	return OA.Part("reputation", "ARMORY_REPUTATION", L["Its reputation rewards are unavailable."], function(raw)
		local out = {}
		for _, f in ipairs(raw) do
			local id, name = type(f) == "table" and Num(f.id), type(f) == "table" and OA.Text(f.n)
			if id and name and f.st ~= 0 then
				local vendors, byId = {}, {}
				for _, v in ipairs(type(f.v) == "table" and f.v or {}) do
					if type(v) == "table" and Num(v[1]) then
						local t = { npcID = v[1], name = OA.Text(v[2]), ui = Num(v[3]), x = Num(v[4]), y = Num(v[5]), zone = OA.Text(v[6]) }
						if not (t.ui and t.x and t.y) then t.ui, t.x, t.y = nil, nil, nil end
						vendors[#vendors + 1] = t
						byId[t.npcID] = t
					end
				end
				local items = {}
				for _, it in ipairs(type(f.i) == "table" and f.i or {}) do
					local iid, rank = type(it) == "table" and Num(it[1]), type(it) == "table" and Num(it[6])
					if iid and rank and rank >= 0 and rank <= 7 then
						local sold = {}
						for _, nid in ipairs(type(it[8]) == "table" and it[8] or {}) do if byId[nid] then sold[#sold + 1] = byId[nid] end end
						items[#items + 1] = { id = iid, name = OA.Text(it[2]), slot = OA.Text(it[3]), quality = Num(it[4]), icon = it[5],
							need = rank + 1, what = OA.Text(it[7]) or "other", vendors = sold }
					end
				end
				if #items > 0 then
					-- (its name's words, for the question: once, not per keystroke; "the" left out)
					local words = {}
					for w in OA.Words(name):gmatch("%S+") do if w ~= "the" then words[#words + 1] = w end end
					out[#out + 1] = { id = id, name = name, side = OA.Text(f.side), vendors = vendors, items = items, words = words }
				end
			end
		end
		if #out == 0 then return nil, "OneForAll.ARMORY_REPUTATION: no faction in the shape expected" end
		return out
	end)
end

--- OneForAll's item sets, checked: { { id, name, group, sub, status (1 obtainable, 2 source not known yet, 0 not in WoW
--- Forever yet), side, classes = { FILE = true } or nil (any class), armor, level, bonuses = { { pieces, text } },
--- pieces = { { id, name, slot, quality, icon, sources = { text... } } } } }, or nil.
function A.OFASets()
	return OA.Part("itemsets", "ARMORY_SETS", L["@itemset (its item sets) is unavailable."], function(raw)
		local out = {}
		for i, s in ipairs(raw) do
			local name = type(s) == "table" and OA.Text(s.n)
			if name and type(s.i) == "table" then
				local pieces = {}
				for _, it in ipairs(s.i) do
					local iid = type(it) == "table" and Num(it[1])
					if iid then
						local src = {}
						for _, x in ipairs(type(it[6]) == "table" and it[6] or {}) do if OA.Text(x) then src[#src + 1] = x end end
						pieces[#pieces + 1] = { id = iid, name = OA.Text(it[2]), slot = OA.Text(it[3]), quality = Num(it[4]), icon = it[5], sources = src }
					end
				end
				local classes
				for _, c in ipairs(type(s.cls) == "table" and s.cls or {}) do
					if OA.Text(c) then classes = classes or {}; classes[c] = true end
				end
				local bonuses = {}
				for _, b in ipairs(type(s.b) == "table" and s.b or {}) do
					if type(b) == "table" and Num(b[1]) and OA.Text(b[2]) then bonuses[#bonuses + 1] = { pieces = b[1], text = b[2] } end
				end
				if #pieces > 0 then
					out[#out + 1] = { id = Num(s.id) or i, order = i, name = name, norm = " " .. OA.Words(name) .. " ", -- (SetIn's)
						group = OA.Text(s.g), sub = OA.Text(s.sub), status = Num(s.st) or 1,
						side = OA.Text(s.side), classes = classes, armor = OA.Text(s.arm), level = Num(s.lv), bonuses = bonuses, pieces = pieces }
				end
			end
		end
		if #out == 0 then return nil, "OneForAll.ARMORY_SETS: no set in the shape expected" end
		return out
	end)
end

----------------------------------------------------------------------
-- Item sets from AtlasLoot (1.4.9: @itemset without OneForAll). Its public set data (AtlasLoot.Data.ItemSet), read
-- while it's installed, never copied: the set an item belongs to (GetSetIDforItemID), a set's items (GetSetItems), its
-- name as the game says it (GetSetName), its bonuses (GetSetBonusString), and which classes may wear a piece
-- (AtlasLoot.Data.Requirements.ClassCanUseItem). AtlasLoot gives no list of its sets, so they're the sets of the items
-- in its loot list (every loot row once: read ahead by the idle warm-up, what's left at once when asked). Where a
-- piece comes from is its loot rows' boss and place. In the shape OneForAll's are in, so the rows, the pieces, the
-- questions and class: are the same code.
----------------------------------------------------------------------

local function AtlasApi()
	local AL = rawget(_G, "AtlasLoot")
	local D = type(AL) == "table" and AL.Data
	local IS = type(D) == "table" and D.ItemSet
	if type(IS) ~= "table" or type(IS.GetSetIDforItemID) ~= "function" or type(IS.GetSetItems) ~= "function"
		or type(IS.GetSetName) ~= "function" then return nil end
	return IS, type(D.Requirements) == "table" and D.Requirements or nil
end
A.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

--- A set's bonuses as AtlasLoot words them ("(2) Set: ..." a line), read back: { { pieces, text } }; {} while the
--- game hasn't sent their texts (asked again when next shown).
function A.AtlasBonuses(setID)
	local IS = AtlasApi()
	local text = IS and type(IS.GetSetBonusString) == "function" and Safe(IS.GetSetBonusString, setID)
	local out = {}
	if type(text) ~= "string" then return out end
	for line in text:gmatch("[^\n]+") do
		local n = tonumber(line:match("%((%d+)%)"))
		local said = line:match("|c%x%x%x%x%x%x%x%x(.-)|r") or line:match("%)%s*[^:]*:%s*(.+)$")
		if n and said and said ~= "" then out[#out + 1] = { pieces = n, text = said } end
	end
	return out
end

-- one set as OneForAll's are shaped, or nil (no items, or the game doesn't know a set by that number here)
local function AtlasSet(IS, Req, setID, order)
	local items = Safe(IS.GetSetItems, setID)
	local name = ns.Str(Safe(IS.GetSetName, setID))
	if type(items) ~= "table" or #items == 0 or not name or name == rawget(_G, "UNKNOWN") then return nil end
	local P = ns.Pipes
	local inst = (C_Item and C_Item.GetItemInfoInstant) or rawget(_G, "GetItemInfoInstant")
	local pieces, places, armor = {}, {}, nil
	for _, iid in ipairs(items) do
		if type(iid) == "number" then
			local rows = P and P.LootRowsOf and P.LootRowsOf(iid) or {}
			local src, seen = {}, {}
			for _, r in ipairs(rows) do
				local d = ns.Str(r.detail)
				if d and not seen[d] and #src < 3 then
					seen[d] = true
					src[#src + 1] = (d:gsub("%s%s+", ", ")) -- ("Ragnaros  Molten Core": the boss, the place)
					local place = d:match("%s%s+(.+)$") or d
					places[place] = (places[place] or 0) + 1
				end
			end
			local _, _, sub, loc, icon, class, subClass = Safe(inst, iid)
			-- (cloth, leather, mail, plate: the armour's kind as the game names it)
			if not armor and class == 4 and type(subClass) == "number" and subClass >= 1 and subClass <= 4 then armor = ns.Str(sub) end
			pieces[#pieces + 1] = { id = iid, name = (rows[1] and ns.Str(rows[1].name)) or ns.ItemName(iid),
				slot = type(loc) == "string" and ns.Str(rawget(_G, loc)) or nil, chest = loc == "INVTYPE_CHEST" or loc == "INVTYPE_ROBE",
				quality = ns.ItemQuality(iid), icon = icon, sources = src }
		end
	end
	if #pieces == 0 then return nil end
	-- where most of it comes from ("Molten Core"): said with the set
	local sub, most = nil, 0
	for place, n in pairs(places) do if n > most or (n == most and place < sub) then sub, most = place, n end end
	-- the classes that may wear it: all of its first piece's, unless that's every class
	local classes
	local first = pieces[1].id
	if Req and type(Req.ClassCanUseItem) == "function" and Safe(Req.HasRequirements, first) == true then
		local n, set = 0, {}
		for _, c in ipairs(A.CLASSES) do
			if Safe(Req.ClassCanUseItem, c, first) == true then set[c] = true; n = n + 1 end
		end
		if n > 0 and n < #A.CLASSES then classes = set end
	end
	return { id = setID, order = order, name = name, norm = " " .. OA.Words(name) .. " ", sub = sub, status = 1, classes = classes,
		armor = armor, bonuses = A.AtlasBonuses(setID), pieces = pieces }
end

local atlas -- { list (the loot list it's of), at (the next loot row to look at), seen, have, ids (sets, as met), sets }
local DONE = math.huge
local function AtlasFresh(list) return { list = list, at = AtlasApi() and 1 or DONE, seen = {}, have = {}, ids = {} } end
local function AtlasOne(x, i, IS)
	local l = x.list[i]
	local id = l and l.itemID
	if type(id) == "number" and not x.seen[id] then
		x.seen[id] = true
		local set = Num(Safe(IS.GetSetIDforItemID, id))
		if set and not x.have[set] then x.have[set] = true; x.ids[#x.ids + 1] = set end
	end
end
--- AtlasLoot's item sets, in the order its loot list meets them; nil when it has none (not installed, no set data, its
--- loot not read yet).
function A.AtlasSets()
	local IS, Req = AtlasApi()
	if not IS then return nil end
	local p = ns.providers.loot
	local list = p and ns:GetEntries(p) or {}
	local x = atlas
	if not (x and x.list == list) then
		x = AtlasFresh(list)
		atlas = x
	end
	if x.at ~= DONE then
		for i = x.at, #list do AtlasOne(x, i, IS) end
		x.at, x.seen = DONE, nil
	end
	if not x.sets then
		local out = {}
		for _, id in ipairs(x.ids) do
			local s = AtlasSet(IS, Req, id, #out + 1)
			if s then out[#out + 1] = s end
		end
		x.sets = out
	end
	return #x.sets > 0 and x.sets or nil
end
--- The read-ahead: the loot list's rows a slice a frame (Core's warm-up runs it once the loot list is built), only
--- when the sets would be AtlasLoot's.
function A.WarmAtlasSets(list)
	local IS = AtlasApi()
	if type(list) ~= "table" or not IS or not I.RunSliced or (OA.Loaded() and A.OFASets()) then return end
	if atlas and atlas.list == list then return end
	local x = AtlasFresh(list)
	atlas = x
	I.RunSliced("item sets: among the loot", #list, function(i)
		if atlas == x and x.at ~= DONE and i >= x.at then AtlasOne(x, i, IS); x.at = i + 1 end
	end, function()
		if atlas == x and x.at ~= DONE then x.at, x.seen = DONE, nil end
	end)
end
ns:AfterWarm("loot", A.WarmAtlasSets)
function A.ForgetAtlasSets() atlas = nil end -- (tests)

--- The item sets and whose list they are: OneForAll's when it has them, else AtlasLoot's (nil: neither).
function A.Sets()
	local ofa = OA.Loaded() and A.OFASets() or nil
	if ofa then return ofa, "OneForAll" end
	local al = A.AtlasSets()
	if al then return al, "AtlasLoot" end
	return nil
end

local function ItemCount(id)
	local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	return f and Num(Safe(f, id, true)) or 0
end
local function Equipped(id)
	local f = (C_Item and C_Item.IsEquippedItem) or _G.IsEquippedItem
	return f and Safe(f, id) == true or false
end
--- Where you have an item: "equipped", "bags" (or the bank), or nil.
function A.Owned(id)
	if Equipped(id) then return "equipped" end
	if ItemCount(id) > 0 then return "bags" end
	return nil
end

local function ClassName(file)
	local t = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
	return type(t) == "table" and t[file] or (file:sub(1, 1) .. Lower(file:sub(2)))
end
local function ClassNames(set)
	if not set then return L["any class"] end
	local t = {}
	for f in pairs(set) do t[#t + 1] = ClassName(f) end
	table.sort(t)
	return table.concat(t, ", ")
end

local function ItemTip(e, t)
	if not pcall(t.SetHyperlink, t, "item:" .. e.itemID) then t:SetText(e.name, 1, 1, 1) end
end

local function RewardTooltip(e, t)
	ItemTip(e, t)
	t:AddLine(" ")
	t:AddLine(L["%s: %s"]:format(e.faction, A.StandingName(e.reaction)), 1, 0.82, 0)
	if e.mine then
		local can = e.mine >= e.reaction
		t:AddLine(L["You're %s"]:format(A.StandingName(e.mine)) .. (can and (SEP .. L["you can buy it"]) or ""), can and 0.4 or 1, 1, can and 0.4 or 0.4)
	else
		t:AddLine(L["You haven't met them yet"], 0.8, 0.8, 0.8)
	end
	for _, v in ipairs(e.vendors) do
		t:AddLine((v.name or "?") .. (v.zone and (SEP .. v.zone) or "") .. (v.x and ("  " .. ("%.1f, %.1f"):format(v.x, v.y)) or ""), 0.8, 0.8, 0.8, true)
	end
	t:AddLine(L["Reputation rewards from OneForAll"], 0.5, 0.5, 0.5)
end

local function NoSpot(e) ns:Print(L["OneForAll has no spot for %s yet."]:format(e.vendorName or e.name)) end

-- (rows a question or a chain lists beside their kind's list (set pieces; the rewards are @reputation's own rows too
-- since 1.0.27): what ns:GetEntries gives the list's rows, the kind's label and the key picks are counted by)
local function Stamp(rows, kind)
	local p = ns.providers[kind]
	local label = p and ns:KindLabel(p) or nil
	for _, e in ipairs(rows) do
		e.kindLabel = label
		e.freqKey = ns:FreqKey(kind, e.key or e.name)
		if e.noCombat == nil and p then e.noCombat = p.noCombat end
	end
	return rows
end

--- The reward rows: each faction's rewards (your faction's and both sides'), by faction then standing.
function A.RewardRows()
	local out = {}
	local side = MySide()
	for fi, f in ipairs(A.Factions() or {}) do
		if not (f.side and side and f.side ~= side) then
			local mine = A.Standing(f.id)
			for ii, it in ipairs(f.items) do
				local name = it.name or L["item %s"]:format(it.id)
				local can = mine ~= nil and mine >= it.need
				local v = it.vendors[1] or f.vendors[1]
				local spot
				for _, x in ipairs(#it.vendors > 0 and it.vendors or f.vendors) do if x.ui then spot = x break end end
				local row = {
					key = f.id .. ":" .. it.id, kind = "reputation", repReward = true, namesOnly = true, name = name, _lname = Lower(name), itemID = it.id, icon = Icon(it.icon),
					quality = it.quality, slot = it.slot, faction = f.name, factionID = f.id, reaction = it.need, mine = mine, canBuy = can,
					what = it.what, vendors = #it.vendors > 0 and it.vendors or f.vendors, vendorName = v and v.name, order = fi * 1000 + it.need * 100 + ii,
					tooltip = RewardTooltip, generic = false, pinName = spot and spot.name,
					detail = f.name .. SEP .. A.StandingName(it.need) .. (it.slot and (SEP .. it.slot) or "")
						.. (can and (SEP .. L["you can buy it"]) or ""),
					text = Lower(table.concat({ L["reputation reward"], "reputation reward rep", f.name, A.StandingName(it.need),
						STANDING_ENGLISH[it.need], it.slot or "", it.what, v and v.name or "", can and "canbuy" or "" }, " ")),
				}
				if spot then
					row.ui, row.px, row.py = spot.ui, spot.x, spot.y
					if I.SpotXY then row.wcont, row.wx, row.wy = I.SpotXY(spot.ui, { spot.x, spot.y }) end
					out[#out + 1] = I.SpotRow(row)
				else
					row.activate, row.secondary = NoSpot, NoSpot
					out[#out + 1] = row
				end
			end
		end
	end
	return out
end

-- (made once, again when your standing changes: the questions ask them per keystroke)
local rewards, watch
--- The reward rows, kept.
function A.Rewards()
	if not watch then -- (only once they're asked for: no frame for everyone)
		watch = CreateFrame("Frame")
		A.watch = watch -- (tests)
		watch:RegisterEvent("UPDATE_FACTION")
		-- (not on the one @reputation's own header read fires: the standings didn't change)
		watch:SetScript("OnEvent", function()
			local p = ns.providers.reputation
			if p and p._firedOwn and GetTime() - (p._collectedAt or 0) < 1 then return end
			rewards = nil
		end)
	end
	if not rewards then rewards = Stamp(A.RewardRows(), "reputation") end
	return rewards
end
function A.ForgetRewards() rewards = nil end -- (tests)
--- A faction's rewards (its id), in order.
function A.RewardsOf(fid)
	local out = {}
	for _, e in ipairs(A.Rewards()) do if e.factionID == fid then out[#out + 1] = e end end
	return out
end

local STATUS = { [0] = L["not in WoW Forever yet"], [2] = L["where it comes from isn't known yet"] }

local Walk = OA.Walk
--- A set's pieces as a search: its chain ("Battlegear of Might > pieces"); in Simple mode, its question.
A.PiecesSearch = function(name, simple)
	if simple then return "pieces of " .. Lower(name) end
	return name .. " > pieces "
end
-- Enter on a set: its pieces
local function SetPieces(e)
	local E = ns.Easy
	Walk(A.PiecesSearch(e.name, E and E.On and E.On()))
end

local function SetTooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	local about = ns.Detail(e.sub, e.armor, e.level and L["level %d"]:format(e.level))
	if about ~= "" then t:AddLine(about, 1, 1, 1, true) end
	t:AddLine(ClassNames(e.classFiles), 0.8, 0.8, 0.8, true)
	if STATUS[e.status] then t:AddLine(STATUS[e.status], 1, 0.5, 0.3, true) end
	t:AddLine(" ")
	t:AddLine(L["%d of %d pieces"]:format(e.owned, e.total), e.owned > 0 and 0.4 or 0.8, 1, e.owned > 0 and 0.4 or 0.8)
	for _, p in ipairs(e.pieces) do
		local have = A.Owned(p.id)
		t:AddLine((have and "|cff66ff66+|r " or "|cff808080-|r ") .. (p.name or L["item %s"]:format(p.id)) .. (p.slot and (" (" .. p.slot .. ")") or ""),
			1, 1, 1)
	end
	-- (AtlasLoot's bonuses are worded by the game: not sent yet when the list was made, asked for again now)
	local bonuses = e.bonuses
	if #bonuses == 0 and e.source == "AtlasLoot" then bonuses = A.AtlasBonuses(e.setID) end
	if #bonuses > 0 then
		t:AddLine(" ")
		for _, b in ipairs(bonuses) do
			local on = e.owned >= b.pieces
			t:AddLine(L["(%d) Set: %s"]:format(b.pieces, b.text), on and 0.4 or 0.6, on and 1 or 0.6, on and 0.4 or 0.6, true)
		end
	end
	t:AddLine(L["Enter: its pieces"], 0.62, 0.62, 0.62)
	t:AddLine(e.source == "AtlasLoot" and L["Item sets from AtlasLoot"] or L["Item sets from OneForAll"], 0.5, 0.5, 0.5)
end

-- its pieces' names and where they come from, for the set's text ("@itemset onyxia", "@itemset gauntlets of might")
function A.PiecesText(s)
	local t = {}
	for _, p in ipairs(s.pieces) do
		t[#t + 1] = p.name or ""
		for _, x in ipairs(p.sources) do t[#t + 1] = x end
	end
	return table.concat(t, " ")
end

--- @itemset's rows: one a set (your faction's and both sides'), in its list's order (OneForAll's, else AtlasLoot's).
function A.SetRows()
	local out = {}
	local side = MySide()
	local sets, source = A.Sets()
	for _, s in ipairs(sets or {}) do
		if not (s.side and side and s.side ~= side) then
			local owned = 0
			for _, p in ipairs(s.pieces) do if A.Owned(p.id) then owned = owned + 1 end end
			local chest
			for _, p in ipairs(s.pieces) do if p.slot == "Chest" or p.chest then chest = p break end end
			chest = chest or s.pieces[1]
			local only
			if s.classes then for f in pairs(s.classes) do only = (only == nil) and f or false end end
			out[#out + 1] = {
				key = s.id, kind = "itemset", name = s.name, _lname = Lower(s.name), setID = s.id, icon = Icon(chest.icon, "Interface\\Icons\\INV_Chest_Chain"),
				group = s.group, sub = s.sub, status = s.status, armor = s.armor, level = s.level, bonuses = s.bonuses, pieces = s.pieces,
				classFiles = s.classes, anyClass = s.classes == nil, classFile = only or nil, owned = owned, total = #s.pieces,
				isDone = owned == #s.pieces, order = s.order, tooltip = SetTooltip, activate = SetPieces, secondary = SetPieces, generic = false,
				source = source,
				detail = ns.Detail(s.sub, L["%d of %d pieces"]:format(owned, #s.pieces), s.armor, ClassNames(s.classes), STATUS[s.status]),
				text = Lower(table.concat({ L["item set"], "item set itemset", s.sub or "", s.group or "", s.armor or "", ClassNames(s.classes),
					owned > 0 and "started" or "", A.PiecesText(s) }, " ")),
			}
		end
	end
	return out
end

local function PieceTooltip(e, t)
	ItemTip(e, t)
	t:AddLine(" ")
	t:AddLine(L["Part of %s"]:format(e.set), 1, 0.82, 0)
	for _, s in ipairs(e.sources) do t:AddLine(s, 0.8, 0.8, 0.8, true) end
	if #e.sources == 0 then
		t:AddLine(e.source == "AtlasLoot" and L["AtlasLoot lists it in no boss's loot"] or L["OneForAll doesn't say where it comes from"], 0.62, 0.62, 0.62, true)
	end
	if e.have then t:AddLine(e.have == "equipped" and L["You're wearing it"] or L["You have it"], 0.4, 1, 0.4) end
	t:AddLine(e.source == "AtlasLoot" and L["Item sets from AtlasLoot"] or L["Item sets from OneForAll"], 0.5, 0.5, 0.5)
end

--- A set's pieces (its id), each saying its set, slot and where it comes from, yours or not: @itemset's rows that only
--- its chain lists (`setPiece`).
function A.PieceRows(setID)
	local out = {}
	local sets, source = A.Sets()
	for _, s in ipairs(sets or {}) do
		if s.id == setID then
			for i, p in ipairs(s.pieces) do
				local have = A.Owned(p.id)
				local name = p.name or L["item %s"]:format(p.id)
				out[#out + 1] = {
					key = s.id .. ":" .. p.id, kind = "itemset", setPiece = true, name = name, _lname = Lower(name), itemID = p.id, icon = Icon(p.icon),
					quality = p.quality, slot = p.slot, set = s.name, sources = p.sources, have = have, isDone = have ~= nil,
					classFiles = s.classes, anyClass = s.classes == nil, order = s.order * 100 + i, tooltip = PieceTooltip, generic = false,
					source = source,
					detail = s.name .. (p.slot and (SEP .. p.slot) or "") .. (p.sources[1] and (SEP .. p.sources[1]) or "")
						.. (have and (SEP .. (have == "equipped" and L["worn"] or L["yours"])) or ""),
					text = Lower(table.concat({ L["set piece"], "set piece", s.name, s.sub or "", p.slot or "", table.concat(p.sources, " "),
						ClassNames(s.classes) }, " ")),
				}
			end
		end
	end
	return Stamp(out, "itemset")
end

OA.AddSetup(function()
	-- "<faction> > rewards": what its quartermaster sells, by standing
	if A.Factions() and ns.RegisterRelation and not A.rewardsRelation then
		A.rewardsRelation = true
		ns:RegisterRelation("rewards", {
			aliases = { "reprewards", "quartermaster" },
			desc = L["what a faction's quartermaster sells, and the standing each needs (OneForAll)"],
			available = function() return A.Factions() ~= nil end, addon = "OneForAll",
			seedKinds = { "reputation" },
			seedNone = L["No faction called \"%s\" among your reputations (one you haven't met: ask for its rewards, \"%s rewards\")"],
			-- (e.repReward, not rawget: a chain's rows are views on them)
			applies = function(e) return e.kind == "reputation" and not e.repReward and e.factionID ~= nil end,
			run = function(rows)
				local out = {}
				for _, e in ipairs(rows) do
					for i, r in ipairs(A.RewardsOf(e.factionID)) do
						out[#out + 1] = setmetatable({ _score = 1e6 - i }, { __index = r })
					end
				end
				return out
			end,
		})
		if ns.Pipes then ns.Pipes.LABELS.rewards = "rewards" end
	end
	A.SetupSets()
end)

--- @itemset and "<set> > pieces": OneForAll's sets when it has them (its own setup runs this too); else AtlasLoot's
--- (Setup.lua's "ItemSets", after AtlasLoot's and OneForAll's), made again whenever its loot list is.
function A.SetupSets()
	if ns.providers.itemset then return end
	local ofa = OA.Loaded() and A.OFASets()
	if not (ofa or AtlasApi()) then return end
	local ev = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "BANKFRAME_CLOSED" }
	ns:RegisterProvider("itemset", {
		label = L["Item set"], color = "ffe0c060", -- (@set: your equipment sets)
		aliases = { "itemset", "itemsets", "tierset", "tiersets", "setpiece", "setpieces" },
		namesOnly = true, -- (a search that doesn't name it: by the sets' names only, Search.lua's Scan.NameMode)
		lazy = true, events = ev, guard = 1, collect = A.SetRows,
		-- (AtlasLoot's: its sets are those of its loot list, read a moment after login; while that's built, its line)
		follows = (not ofa) and "loot" or nil,
		busy = (not ofa) and function()
			local lp = ns.providers.loot
			return lp and type(lp.busy) == "function" and lp.busy(lp) or nil
		end or nil,
	})
	-- "<set> > pieces": its pieces, first to last
	if ns.RegisterRelation and not A.piecesRelation then
		A.piecesRelation = true
		ns:RegisterRelation("pieces", {
			aliases = { "piece", "setpieces" },
			desc = L["an item set's pieces, where each comes from (OneForAll)"],
			available = function() return ns.providers.itemset ~= nil end, addon = "OneForAll",
			seedKinds = { "itemset" },
			applies = function(e) return e.kind == "itemset" and not e.setPiece and e.setID ~= nil end,
			run = function(rows)
				local out = {}
				for _, e in ipairs(rows) do
					for i, r in ipairs(A.PieceRows(e.setID)) do
						r._score = 1e6 - i
						out[#out + 1] = r
					end
				end
				return out
			end,
		})
		if ns.Pipes then ns.Pipes.LABELS.pieces = "pieces" end
	end
end
if I._ then I._.SetupItemSets = A.SetupSets end
--- .integrations' line when the sets are AtlasLoot's (OneForAll's are counted on its own line); nil otherwise.
function A.SetsStatus()
	local sets, source = A.Sets()
	if source ~= "AtlasLoot" then return nil end
	return L["%d from AtlasLoot (@itemset)"]:format(#sets)
end
OA.AddStatus(function()
	local f, s = A.Factions(), A.OFASets()
	if not (f or s) then return nil end
	return L["%d factions' rewards (> rewards), %d item sets (@itemset)"]:format(f and #f or 0, s and #s or 0)
end)

----------------------------------------------------------------------
-- "argent dawn rewards", "what can i buy at honored", "rep rewards", "my class sets", "pieces of battlegear of might"
----------------------------------------------------------------------

-- (not "vendor", "sell": "vendor in ratchet", "booty bay vendor" are NPC searches, those towns factions too) ("buy"
-- only with a standing, a rep word or "can": "where to buy in booty bay" is the town's vendors; not "quartermaster":
-- "argent dawn quartermaster" is the NPC.)
local REWARD = { reward = true, rewards = true, unlocks = true }
local REP = { rep = true, reputation = true, faction = true, factions = true }
local WHAT = { recipes = "recipe", recipe = "recipe", patterns = "recipe", plans = "recipe", formulas = "recipe", gear = "gear",
	armor = "gear", weapons = "gear" }
local NOW = { can = true, now = true, afford = true, unlocked = true }
local SET = { set = true, sets = true, itemset = true, itemsets = true, tier = true }
local PIECE = { piece = true, pieces = true }
local ASK = { i = true, im = true, ["do"] = true, the = true, a = true, an = true, to = true, where = true, are = true, is = true, what = true,
	which = true, show = true, list = true, me = true, of = true, ["for"] = true, ["in"] = true, at = true, from = true, with = true,
	get = true, my = true, all = true, yet = true, still = true, have = true, ive = true, class = true, need = true, needed = true }

local Norm = OA.Words

-- a faction named in the words ("argent dawn", "timbermaw", "booty bay"): the faction and the words it took
-- AtlasLoot's factions among @reputation's rewards (its faction loot: a name, no id): { name, words }, made once a list
local alFactions, alOf = {}, nil
local function AtlasFactions()
	local p = ns.providers.reputation
	local list = p and p._entries
	if alOf ~= list then
		alOf, alFactions = list, {}
		local seen = {}
		for _, e in ipairs(list or {}) do
			if e.repReward and not e.factionID and type(e.faction) == "string" and not seen[e.faction] then
				seen[e.faction] = true
				local w = {}
				for x in Lower(e.faction):gsub("[%p]", ""):gmatch("%S+") do w[#w + 1] = x end
				alFactions[#alFactions + 1] = { name = e.faction, words = w }
			end
		end
	end
	return alFactions
end
local function FactionIn(words)
	local best, bestN, bestAt
	local function Try(f)
		local fw = f.words
		-- (its whole name, or its first word alone when that's its own: "timbermaw", "cenarion", "thorium")
		for i = 1, #words do
			local n = 0
			while fw[n + 1] and words[i + n] == fw[n + 1] do n = n + 1 end
			if n > 0 and (n == #fw or (n == 1 and #fw[1] > 5)) and (not best or n > bestN) then best, bestN, bestAt = f, n, i end
		end
	end
	for _, f in ipairs(A.Factions() or {}) do Try(f) end
	-- (AtlasLoot's faction loot's factions too, "brood of nozdormu rewards": its rewards are @reputation's since
	-- 1.0.28)
	if not best then for _, f in ipairs(AtlasFactions()) do Try(f) end end
	return best, bestAt, bestN
end

-- (the standing: filter's words, English and the game's, female forms too; made once: Search/Filters/Others.lua)
local function StandingIn(w)
	local F = ns.Filters
	local words = F and F._ and F._.StandingWords and F._.StandingWords()
	return words and words[w] or nil
end

-- a set named in the words ("battlegear of might"): the set's row name
local function SetIn(text)
	local t = " " .. Norm(text) .. " "
	local best
	for _, s in ipairs(A.Sets() or {}) do
		if t:find(s.norm, 1, true) and (not best or #s.name > #best) then best = s.name end
	end
	return best
end

--- The question: { what = "rewards" (faction, standing, now, kind, words) | "sets" (mine, words) | "pieces" (set) }, or nil.
function A.Question(text)
	if not (A.Factions() or ns.providers.itemset) then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local words = {}
	for w in t:gmatch("%S+") do words[#words + 1] = w end
	-- the pieces of a set: "pieces of battlegear of might", "battlegear of might pieces"
	local hasPiece = false
	for _, w in ipairs(words) do if PIECE[w] then hasPiece = true end end
	if hasPiece and ns.providers.itemset then
		local s = SetIn(t)
		if s then return { what = "pieces", set = s } end
	end
	-- reputation rewards
	if A.Factions() then
		local f, at, n = FactionIn(words)
		local q = { what = "rewards", faction = f, words = {} }
		local reward, rep, buy = false, false, false
		for i, w in ipairs(words) do
			if not (f and i >= at and i < at + n) then
				local st = StandingIn(w)
				if st then q.standing = st
				elseif REWARD[w] then reward = true
				elseif w == "buy" then buy = true
				elseif REP[w] then rep = true
				elseif WHAT[w] then q.kind = WHAT[w]; reward = true
				elseif NOW[w] then q.now = true
				elseif not ASK[w] then q.words[#q.words + 1] = w end
			end
		end
		-- (a faction or a standing, and a word for what it sells: "argent dawn rewards", "what can i buy at honored",
		-- "timbermaw recipes"; "rep rewards" too) ("what can i buy at honored": what honored lets you buy, up to it,
		-- whatever you are now)
		if buy and (q.standing or rep or q.now) then reward = true end
		if q.standing and q.now then q.now, q.upTo = nil, true end
		if reward and (f or q.standing or rep) and #q.words == 0 then return q end
	end
	-- item sets: "my class sets", "warrior sets", "tier 1 sets", "item sets"
	if ns.providers.itemset then
		local set, mine, sure = false, false, false
		local q = { what = "sets", words = {} }
		for i, w in ipairs(words) do
			-- ("item", "tier", "class": item sets; "my sets", "sets" alone are your equipment sets')
			if w == "item" or w == "tier" or w == "class" or w == "itemset" or w == "itemsets" then sure = true end
			if SET[w] then set = true
				if w == "tier" and tonumber(words[i + 1] or "") then q.words[#q.words + 1] = "tier " .. words[i + 1] end
			elseif w == "my" or w == "mine" then mine = true
			elseif tonumber(w) and words[i - 1] == "tier" then -- (said with "tier")
			elseif not ASK[w] and w ~= "item" then q.words[#q.words + 1] = w end
		end
		if set and (sure or #q.words > 0) then
			q.mine = mine
			-- other words: a class, an armor, a place ("warrior sets", "plate sets", "molten core sets")
			if #q.words > 0 then
				local p = ns.providers.itemset
				local any = false
				for _, e in ipairs(ns:GetEntries(p)) do
					if OA.Has(e, q.words) then any = true break end
				end
				if not any then return nil end
			end
			return q
		end
	end
	return nil
end

local Has = OA.Has

local MyClass = ns.ClassToken

function A.Answer(q)
	q = q or {}
	if q.what == "pieces" then
		local rows = {}
		for _, s in ipairs(A.Sets() or {}) do
			if s.name == q.set then rows = A.PieceRows(s.id) break end
		end
		ns.ScoreInOrder(rows)
		local have = 0
		for _, e in ipairs(rows) do if e.have then have = have + 1 end end
		return rows, L["Pieces of %s"]:format(q.set) .. SEP .. L["%d of %d pieces"]:format(have, #rows)
	end
	if q.what == "sets" then
		local cls = MyClass()
		local rows = {}
		for _, e in ipairs(ns:GetEntries(ns.providers.itemset)) do
			local fits = not q.mine or e.anyClass or (e.classFiles and cls and e.classFiles[cls])
			if fits and Has(e, q.words) then rows[#rows + 1] = e end
		end
		-- (the sets you've started first, then OneForAll's order)
		table.sort(rows, function(a, b)
			if (a.owned > 0) ~= (b.owned > 0) then return a.owned > 0 end
			return a.order < b.order
		end)
		ns.ScoreInOrder(rows)
		if #rows == 0 then return { ns.NoteRow(L["No item set has that"]) }, L["Item sets"] end
		return rows, q.mine and L["Item sets for your class"] or L["Item sets"]
	end
	-- (@reputation's rewards, OneForAll's and AtlasLoot's, as the line Alt+` writes finds them)
	local rows = {}
	local p = ns.providers.reputation
	local all = {}
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do if e.repReward then all[#all + 1] = e end end
	if #all == 0 then all = A.Rewards() end
	local lf = q.faction and Lower(q.faction.name)
	for _, e in ipairs(all) do
		local ok = (not q.faction or (q.faction.id and e.factionID == q.faction.id) or (not e.factionID and Lower(tostring(e.faction)) == lf))
			and (not q.standing or (q.upTo and e.reaction <= q.standing) or e.reaction == q.standing)
			and (not q.kind or e.what == q.kind) and (not q.now or e.canBuy) and Has(e, q.words)
		if ok then rows[#rows + 1] = e end
	end
	ns.ScoreInOrder(rows)
	local title = q.faction and L["%s rewards"]:format(q.faction.name) or L["Reputation rewards"]
	if q.standing then title = title .. SEP .. (q.upTo and L["up to %s"]:format(A.StandingName(q.standing)) or A.StandingName(q.standing)) end
	if q.faction and q.faction.id then
		local mine = A.Standing(q.faction.id)
		title = title .. SEP .. (mine and L["you're %s"]:format(A.StandingName(mine)) or L["not met yet"])
	end
	if q.now then title = title .. SEP .. L["the ones you can buy"] end
	if #rows == 0 then
		return { ns.NoteRow(q.now and L["Nothing you can buy yet"] or L["No reputation reward has that"]) }, title
	end
	return rows, title
end

function A.ToAdvanced(q)
	q = q or {}
	if q.what == "pieces" then return A.PiecesSearch(q.set) end
	local w = q.words and #q.words > 0 and (table.concat(q.words, " ") .. " ") or ""
	if q.what == "sets" then return "@itemset " .. (q.mine and "class:mine " or "") .. w end
	-- (as @reputation's filters, the faction's words, its standing (up to it, or that one), a kind's word, can buy)
	local parts = { "@reputation is:reward" }
	if q.faction then parts[#parts + 1] = Norm(q.faction.name) end
	if q.standing then parts[#parts + 1] = "standing:" .. (q.upTo and "<=" or "") .. Lower(STANDING_ENGLISH[q.standing] or tostring(q.standing)) end
	if q.kind then parts[#parts + 1] = q.kind end
	if q.now then parts[#parts + 1] = "is:canbuy" end
	return table.concat(parts, " ") .. " " .. w
end
