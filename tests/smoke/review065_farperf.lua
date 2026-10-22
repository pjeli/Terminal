-- 0.65.x review (0.65.10): sort:-distance makes no table for each row with no distance known.
-- review B: sort:-distance wraps every row with no distance in a table of its own, every search
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local saved = { providers = ns.providers, order = ns.providerOrder }
local function Use(defs)
	ns.providers, ns.providerOrder = {}, {}
	for _, d in ipairs(defs) do ns:RegisterProvider(d[1], d[2]) end
	UI.lastScan, UI.lastExtra, UI.lastFzf = nil, nil, nil
end
local function CompactRows(specs)
	local made
	return function(p)
		if made then return made end
		local meta = ns:CompactMeta(p)
		made = {}
		for i, s in ipairs(specs) do made[i] = setmetatable({ _compact = true, name = s[1], key = s[2] }, meta) end
		return made
	end
end
local I, QD = ns.Integrations, ns.QuestieData
local save = { db = QD.DB, ui = QD.UiMapOfArea, map = _G.C_Map }
local ok, err = pcall(function()
	local spawns, npcs = {}, {}
	local N = 6000
	for i = 1, N do
		npcs[i] = { ("Npc %04d"):format(i), i }
		spawns[i] = { [i % 2 == 0 and 40 or 12] = { { (i * 37) % 100, (i * 53) % 100 } } } -- half on the other continent
	end
	local DB = { QueryNPCSingle = function(id, field) if field == "spawns" then return spawns[id] end end }
	QD.DB = function() return DB end
	QD.UiMapOfArea = function(area) return area == 12 and 1429 or 1436 end
	_G.C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return { x = 0.30, y = 0.80 } end,
		GetWorldPosFromMapPos = function(map, p) return map == 1429 and 1 or 2, { x = p.x * 1000, y = p.y * 1000 } end }
	I._.ResetDistances()
	Use({ { "npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = CompactRows(npcs) } } })
	ns.db.easyMode = false
	local function Count(line)
		UI:Search(line) -- warm
		local made, realSet = 0, _G.setmetatable
		_G.setmetatable = function(t, m) made = made + 1 return realSet(t, m) end
		local res = UI:Search(line)
		_G.setmetatable = realSet
		return made, res
	end
	local nearMade, nearRes = Count("@npc sort:distance")
	local farMade, farRes = Count("@npc sort:-distance")
	io.write(("tables with a metatable per search: sort:distance %d, sort:-distance %d; shown %d / %d; first far row has _dist=%s\n")
		:format(nearMade, farMade, #nearRes, #farRes, tostring(rawget(farRes[1], "_dist"))))
	local views = 0
	for _, e in ipairs(farRes) do if rawget(e, "_dist") then views = views + 1 end end
	io.write("far: rows with a distance among the shown: " .. views .. "\n")
	check(farMade < nearMade + 500, ("sort:-distance makes a table per unknown row each search: %d vs %d"):format(farMade, nearMade))
end)
QD.DB, QD.UiMapOfArea, _G.C_Map = save.db, save.ui, save.map; I._.ResetDistances()
ns.providers, ns.providerOrder = saved.providers, saved.order
ns:AliasesChanged()
UI.lastScan = nil
if not ok then check(false, "far_perf: " .. tostring(err)) end
