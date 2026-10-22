-- 0.65.x review (0.65.10): a typed nearest/farthest word decides over the bar's Distance, and its arrow says so.
-- review B: farthest / bar sort direction interplay (NPC lists as easy.lua's "nearest")
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local E = ns.Easy
local saved = { providers = ns.providers, order = ns.providerOrder }
local function Use(defs)
	ns.providers, ns.providerOrder = {}, {}
	for _, d in ipairs(defs) do ns:RegisterProvider(d[1], d[2]) end
	UI.lastScan = nil
end
local function Rows(list)
	return function()
		local out = {}
		for i, r in ipairs(list) do
			local e = {}
			for k, v in pairs(r) do e[k] = v end
			e.key = e.key or i
			out[i] = e
		end
		return out
	end
end
local function Show(res)
	local t = {}
	for i = 1, math.min(#res, 8) do t[i] = tostring(res[i].completion or res[i].name) end
	return table.concat(t, " | ")
end
local function Fire() return function() end end

local ok, err = pcall(function()
	E.Set(true)
	Use({
		{ "npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = Rows({
			{ name = "Innkeeper Farley", key = 295, npcID = 295, activate = Fire() },
			{ name = "Innkeeper Allison", key = 6740, npcID = 6740, activate = Fire() },
			{ name = "Innkeeper Far Away", key = 9999, npcID = 9999, activate = Fire() },
			{ name = "Hogger", key = 448, npcID = 448, activate = Fire() } }) } },
	})
	local I = ns.Integrations
	local saveHere, saveDist = I.Here, I.NpcDistance
	local DIST = { [295] = 120, [6740] = 40 }
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	I.NpcDistance = function(id) return DIST[id] end
	local saveField, saveDefs, saveGroup = I.NpcField, I.NpcFlagDefs, _G.UnitFactionGroup
	local FIELDS = { [295] = { npcFlags = 128, friendlyToFaction = "A" }, [6740] = { npcFlags = 128, friendlyToFaction = "AH" },
		[9999] = { npcFlags = 128, friendlyToFaction = "A" }, [448] = { npcFlags = 0 } }
	I.NpcField = function(id, f) return FIELDS[id] and FIELDS[id][f] end
	I.NpcFlagDefs = function() return { VENDOR = 4, REPAIR = 4096, INNKEEPER = 128 } end
	_G.UnitFactionGroup = function() return "Alliance" end
	ns.Filters.ClearCache()
	local B = ns.Bar

	-- A: bar's Distance picked (nearest first), then "farthest" typed in front
	UI:Hide(); FlushAll(); B.Reset()
	UI:Open("innkeeper"); FlushAll()
	B.Pick("sort", "distance"); FlushAll()
	io.write("A0 bar=" .. tostring(B.state.sort) .. " rows=" .. Show(UI.Results()) .. "\n")
	UI:SetQuery("farthest innkeeper"); FlushAll()
	local rows = Show(UI.Results())
	local dist
	for _, o in ipairs(B.Options("sort")) do if o.id == "distance" then dist = o end end
	io.write("A1 bar=" .. tostring(B.state.sort) .. " asc=" .. tostring(dist and dist.asc) .. " rows=" .. rows .. " adv=" .. E.ToAdvanced("farthest innkeeper") .. "\n")
	check(not (rows:find("^Innkeeper Far Away") and dist and dist.asc == true),
		"A: bar says Distance ascending (arrow up: nearest first) while the rows are farthest first: " .. rows)

	-- B: bar's -distance (farthest), then "nearest" typed in front
	UI:Hide(); FlushAll(); B.Reset()
	UI:Open("innkeeper"); FlushAll()
	B.Pick("sort", "distance"); B.Pick("sort", "distance"); FlushAll()
	UI:SetQuery("nearest innkeeper"); FlushAll()
	rows = Show(UI.Results())
	for _, o in ipairs(B.Options("sort")) do if o.id == "distance" then dist = o end end
	io.write("B1 bar=" .. tostring(B.state.sort) .. " asc=" .. tostring(dist and dist.asc) .. " rows=" .. rows .. " adv=" .. E.ToAdvanced("nearest innkeeper") .. "\n")
	check(not rows:find("^Innkeeper Far Away"), "B: 'nearest innkeeper' typed lists the farthest first (bar's -distance wins): " .. rows)

	-- C: SameAsAdvanced for the farthest
	UI:Hide(); FlushAll(); B.Reset()
	local same, why = T.SameAsAdvanced("farthest innkeeper")
	check(same, "C: farthest innkeeper as Advanced: " .. tostring(why))
	same, why = T.SameAsAdvanced("nearest innkeeper")
	io.write("C2 nearest same=" .. tostring(same) .. " " .. tostring(why) .. "\n")

	-- D: Share context for farthest
	if ns.Share and ns.Share.Context then
		io.write("D " .. tostring(ns.Share.Context("@npc is:innkeeper sort:-distance", { name = "Innkeeper Farley", kind = "npc" })) .. " / "
			.. tostring(ns.Share.Context("@npc is:innkeeper sort:distance", { name = "Innkeeper Farley", kind = "npc" })) .. "\n")
	end

	I.Here, I.NpcDistance, I.NpcField, I.NpcFlagDefs, _G.UnitFactionGroup = saveHere, saveDist, saveField, saveDefs, saveGroup
end)
ns.providers, ns.providerOrder = saved.providers, saved.order
ns:AliasesChanged()
UI.lastScan = nil
ns.Bar.Reset()
ns.db.easyMode = false; UI:EasyChanged()
UI:Hide(); FlushAll()
if not ok then check(false, "far_bar: " .. tostring(err)) end
