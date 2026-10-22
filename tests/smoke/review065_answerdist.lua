-- 0.65.x review (0.65.10): an answer sorted by distance is in that order.
-- review B: a question's rows with sort:distance / sort:-distance (Scan.AnswerView -> Scan.NearestViews)
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local Scan = UI._Scan
local I = ns.Integrations
local saveHere, saveDist = I.Here, I.NpcDistance
local ok, err = pcall(function()
	local DIST = { [1] = 300, [2] = 50, [3] = 120 }
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	I.NpcDistance = function(id) return DIST[id] end
	local A = { ask = function(text) if text == "zzq answer" then return {} end end,
		answer = function() return {
			{ name = "Far Npc", kind = "npc", npcID = 1, key = 1 },
			{ name = "Near Npc", kind = "npc", npcID = 2, key = 2 },
			{ name = "Unknown Npc", kind = "npc", npcID = 4, key = 4 },
			{ name = "Mid Npc", kind = "npc", npcID = 3, key = 3 } } end }
	table.insert(Scan.ANSWERS, 1, A)
	ns.db.easyMode = false
	local function Names(line)
		local t = {}
		for _, e in ipairs(UI:Search(line)) do t[#t + 1] = tostring(e.name) .. (rawget(e, "_dist") and ("=" .. e._dist) or "") end
		return table.concat(t, ", ")
	end
	local plain, near, far = Names("zzq answer"), Names("zzq answer sort:distance"), Names("zzq answer sort:-distance")
	io.write("plain: " .. plain .. "\nnear: " .. near .. "\nfar: " .. far .. "\n")
	check(near:find("^Near Npc=50, Mid Npc=120, Far Npc=300"), "an answer sort:distance: the nearest first: " .. near)
	check(far:find("^Unknown Npc, Far Npc=300, Mid Npc=120, Near Npc=50"), "an answer sort:-distance: unknown, then the farthest: " .. far)
	table.remove(Scan.ANSWERS, 1)
end)
I.Here, I.NpcDistance = saveHere, saveDist
if not ok then check(false, "answer_dist: " .. tostring(err)) end
