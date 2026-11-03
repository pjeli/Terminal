local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local OA = ns.OneForAll

-- OneForAll's gear value (1.0.5, the player's ask: "we can forgo our own upgrades if OneForAll suggests upgrades"):
-- while it's installed, is:upgrade ("upgrades") takes its verdict on each item, its stat weights for your talents
-- against what you wear (FLT.GearValue.Change: up, by how much; new, the slot empty; down, same, worn), in place of
-- Terminal's own weights (Search/Filters/Upgrades.lua). Terminal's own still decide when you picked roles in .weights
-- (OneForAll judges for your talents alone), and its checks before stay: your level, what your class can use.
-- The gear OneForAll's planner knows you could get (dungeon loot, quest rewards, sets, reputation, crafted: FLT.GearIndex)
-- is @loot's (1.0.25, the player: "it should be under Loot with sources mapped"; was @gearplan): each item with where it
-- comes from (`lootSource`: dungeon, raid, quest, crafted, reputation, other; source:quest...), a boss's said as
-- AtlasLoot's rows are ("Arugal  Shadowfang Keep"); what AtlasLoot lists already left to its rows. Without AtlasLoot,
-- @loot is these alone. "upgrades" finds the upgrades among them too.

local G = {}
OA.Gear = G
ns.OneForAllGear = G
local Lower, Num = ns.Lower, ns.Num

local KINDS = { up = true, new = true, down = true, same = true, worn = true }

-- its GearValue, when it has the call Terminal reads
local function GV()
	local lib = OA.Lib()
	local v = lib and rawget(lib, "GearValue")
	if type(v) == "table" and type(v.Change) == "function" then return v end
end

--- Is OneForAll's verdict there to take?
function G.Available() return GV() ~= nil end

--- Its verdict on an item against what you wear: "up" (and by how many percent), "new" (the slot empty), "down",
--- "same", "worn"; nil when it can't say (not gear, not for your class, the item not loaded yet).
function G.Change(id)
	local v = G.gv or GV()
	if not v then return nil end
	local kind, pct = OA.Call(v.Change, id)
	if not KINDS[kind] then return nil end
	return kind, Num(pct)
end

--- What `F.GearFit` takes of it: { change = G.Change } while it's there and no roles are picked, else nil.
function G.Judge()
	local F = ns.Filters
	if F and F.MyRoles and F.MyRoles() then G.gv = nil return nil end
	-- (found once a search, each row's verdict asks it: review, 1.0.21)
	G.gv = GV()
	return G.gv and G or nil
end

-- where an item of its planner's comes from, by what its entry carries (UI/GearPlanner.lua's buildIndex): a quest's id, a
-- profession, a boss of a dungeon or a raid, a faction's standing in its words ("Argent Dawn (Honored)")
local STANDINGS = { Friendly = true, Honored = true, Revered = true, Exalted = true }
local function SourceOf(e)
	if Num(e.qid) then return "quest" end
	if OA.Text(e.prof) then return "crafted" end
	if OA.Text(e.boss) then return (type(e.d) == "table" and e.d.raid) and "raid" or "dungeon" end
	local rank = (OA.Text(e.src) or ""):match("%((%a+)%)$")
	if rank and STANDINGS[rank] then return "reputation" end
	return "other"
end

--- The gear its planner knows: { { id, name, src, lvl, side, source, boss, inst, qid } } (checked), or nil.
function G.Index()
	local lib = OA.Lib()
	local fn = lib and rawget(lib, "GearIndex")
	if type(fn) ~= "function" then return nil end
	local list = OA.Call(fn)
	if type(list) ~= "table" then return nil end
	local out = {}
	for _, e in ipairs(list) do
		local id = type(e) == "table" and Num(e.id)
		if id then
			local d = type(e.d) == "table" and e.d or nil
			out[#out + 1] = { id = id, name = OA.Text(e.name), src = OA.Text(e.src), lvl = Num(e.lvl), side = OA.Text(e.side),
				source = SourceOf(e), boss = OA.Text(e.boss), inst = d and OA.Text(d.name), qid = Num(e.qid) }
		end
	end
	return out
end

local function ItemName(id)
	local f = (C_Item and C_Item.GetItemNameByID) or nil
	local n = f and ns.Safe(f, id)
	return type(n) == "string" and n ~= "" and n or nil
end

local function Tooltip(e, t)
	if not pcall(t.SetHyperlink, t, "item:" .. e.itemID) then t:SetText(e.name, 1, 1, 1) end
	t:AddLine(" ")
	if e.src then t:AddLine(e.src, 1, 0.82, 0, true) end
	t:AddLine(L["Gear from OneForAll's planner"], 0.5, 0.5, 0.5)
	-- (a quest's: Enter, its Wowhead page)
	if e.qid then ns.KeyHints(t, L["Enter: show its Wowhead page    Shift+Enter: link it in chat"], 0.6, 0.6, 0.6, true) end
end

local function QuestPage(e)
	if e.qid and I.WOWHEAD_QUEST then ns:ShowText(L["Wowhead: %s"]:format(tostring(e.src)), I.WOWHEAD_QUEST:format(e.qid), { compact = true }) end
end
local function LinkIt(e) ns.LinkInChat(select(2, ns.Safe(C_Item.GetItemInfo, e.itemID)) or e.name) end

--- @loot's rows of its planner's gear: each item once, none AtlasLoot lists already (`listed`: item id -> true), your
--- faction's and both sides'.
function G.Rows(listed)
	local list = G.Index()
	if not list then return {} end
	local side = OA.Side()
	local out, seen = {}, {}
	for i, e in ipairs(list) do
		if not seen[e.id] and not (listed and listed[e.id]) and not (e.side and side and e.side ~= side) then
			seen[e.id] = true
			local name = e.name or ItemName(e.id)
			if name then
				-- (a boss's as AtlasLoot's rows say it, "<boss>  <instance>": the loot readers take its instance from that)
				local where = (e.boss and e.inst) and (e.boss .. "  " .. e.inst) or e.src or ""
				out[#out + 1] = {
					key = "ofa:" .. e.id, name = name, _lname = Lower(name), itemID = e.id, src = e.src, order = i,
					lootSource = e.source, lootLevel = e.lvl, qid = e.qid, tooltip = Tooltip, detail = where,
					activate = e.qid and QuestPage or nil, secondary = LinkIt,
					text = Lower((e.src or "") .. " " .. (e.inst or "") .. " " .. e.source),
				}
			end
		end
	end
	return out
end

OA.AddSetup(function()
	if type(rawget(OA.Lib() or {}, "GearIndex")) ~= "function" then return end
	G.on = true
	-- (with AtlasLoot, its @loot's collect adds these: Loot.lua; without it, @loot is these alone)
	if ns.providers.loot then return end
	ns:RegisterProvider("loot", {
		label = L["Loot"], color = "ffd9a441", aliases = { "loot" },
		lazy = true, collect = function() return G.Rows() end,
	})
end)
OA.AddStatus(function()
	if not G.Available() then return nil end
	return G.Judge() and L["its gear value decides is:upgrade"] or L["its gear value (not used: you picked roles in .weights)"]
end)
