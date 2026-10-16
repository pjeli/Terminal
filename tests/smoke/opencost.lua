-- (0.53.1, the player: a CPU spike as the terminal opens) opening with nothing typed builds no list: the empty prompt's
-- suggestions, made again a minute on, read the lists as they were last built (they had your bags, quest log and
-- professions read again on every such open). Closing builds none either.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll

io.write("[opening builds no list]\n")
local realTime = _G.GetTime
local now = 50000
_G.GetTime = function() return now end
local collected = {}
local wrapped = {}
for id, p in pairs(ns.providers) do
	local c = p.collect
	if type(c) == "function" then
		wrapped[p] = c
		p.collect = function(...) collected[#collected + 1] = id return c(...) end
	end
end
local easy = ns.db.easyMode
for _, simple in ipairs({ true, false }) do
	ns.db.easyMode = simple
	UI:EasyChanged()
	for _, p in pairs(ns.providers) do p._dirty = true end -- (bags, quests... changed since)
	now = now + 120 -- (the suggestions made again)
	collected = {}
	UI:Open("")
	FlushAll()
	check(#collected == 0, (simple and "Simple" or "Advanced") .. " mode, opened with nothing typed: no list built: "
		.. table.concat(collected, ","))
	collected = {}
	UI:Hide(); FlushAll()
	check(#collected == 0, "closed: no list built: " .. table.concat(collected, ","))
end
for p, c in pairs(wrapped) do p.collect = c end
ns.db.easyMode = easy
UI:EasyChanged()
_G.GetTime = realTime
