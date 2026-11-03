local ns = select(2, ...)
local L = ns.L
local OA = ns.OneForAll

-- OneForAll's gear value (1.0.5, the player's ask: "we can forgo our own upgrades if OneForAll suggests upgrades"):
-- while it's installed, is:upgrade ("upgrades") takes its verdict on each item, its stat weights for your talents
-- against what you wear (FLT.GearValue.Change: up, by how much; new, the slot empty; down, same, worn), in place of
-- Terminal's own weights (Search/Filters/Upgrades.lua). Terminal's own still decide when you picked roles in .weights
-- (OneForAll judges for your talents alone), and its checks before stay: your level, what your class can use.
-- @gearplan: the gear OneForAll's planner knows you could get (dungeon loot, quest rewards, sets, reputation, crafted:
-- FLT.GearIndex), where each comes from; "upgrades" finds the upgrades among them too.

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

--- The gear its planner knows: { { id, name, src, lvl, side } } (checked), or nil.
function G.Index()
	local lib = OA.Lib()
	local fn = lib and rawget(lib, "GearIndex")
	if type(fn) ~= "function" then return nil end
	local list = OA.Call(fn)
	if type(list) ~= "table" then return nil end
	local out = {}
	for _, e in ipairs(list) do
		local id = type(e) == "table" and Num(e.id)
		if id then out[#out + 1] = { id = id, name = OA.Text(e.name), src = OA.Text(e.src), lvl = Num(e.lvl), side = OA.Text(e.side) } end
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
end

--- @gearplan's rows: each item once (one AtlasLoot lists already is left to @loot), your faction's and both sides'.
function G.Rows()
	local list = G.Index()
	if not list then return {} end
	local side = UnitFactionGroup and UnitFactionGroup("player")
	side = (side == "Alliance" and "A") or (side == "Horde" and "H") or nil
	local inLoot = {}
	local lp = ns.providers.loot
	if lp then for _, r in ipairs(ns:GetEntries(lp)) do if r.itemID then inLoot[r.itemID] = true end end end
	local out, seen = {}, {}
	for i, e in ipairs(list) do
		if not seen[e.id] and not inLoot[e.id] and not (e.side and side and e.side ~= side) then
			seen[e.id] = true
			local name = e.name or ItemName(e.id)
			if name then
				out[#out + 1] = {
					key = e.id, kind = "gearplan", name = name, _lname = Lower(name), itemID = e.id, src = e.src, order = i,
					tooltip = Tooltip, detail = e.src or "", text = Lower((e.src or "") .. " " .. L["gear to get"] .. " gear to get"),
				}
			end
		end
	end
	return out
end

OA.AddSetup(function()
	if type(rawget(OA.Lib() or {}, "GearIndex")) ~= "function" then return end
	ns:RegisterProvider("gearplan", {
		label = L["Gear to get"], color = "ffc0e080", aliases = { "gearplan", "gearplanner", "suggested", "suggestedgear" },
		lazy = true, collect = G.Rows, follows = "loot", -- (AtlasLoot's left out: made again with it; review, 1.0.22)
	})
end)
OA.AddStatus(function()
	if not G.Available() then return nil end
	return G.Judge() and L["its gear value decides is:upgrade"] or L["its gear value (not used: you picked roles in .weights)"]
end)
