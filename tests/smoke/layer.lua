-- Your layer (Providers/Layer.lua, 1.1.13, the player: "what layer am i on"; 1.8.3: WoW Forever's November 20, 2026
-- hotfix hid it, every creature's GUID now carries a different number): @layer and its question say it can't be told,
-- and nothing is read from the creatures you meet.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local LY = ns.Layer

io.write("[layer: what layer am i on, my layer, @layer]\n")
do
	local was = { guid = _G.UnitGUID, easy = ns.db.easyMode }
	local asked = 0
	_G.UnitGUID = function(u) asked = asked + 1 return "Creature-0-4372-0-2051-299-0000AB12CD" end
	local function Ask(q)
		UI:Open(q); FlushAll()
		local r = UI.Results()
		return r[1], r
	end
	for _, simple in ipairs({ true, false }) do
		ns.db.easyMode = simple; UI:EasyChanged()
		ns.providers.layer._dirty = true
		local mode = simple and "Simple" or "Advanced"
		for _, q in ipairs(simple and { "what layer am i on", "my layer", "which layer am i on", "layer" } or { "@layer", "what layer am i on" }) do
			local e, all = Ask(q)
			check(e and e.noActivate and #all == 1 and tostring(e.name):find("November 20, 2026", 1, true),
				mode .. ": \"" .. q .. "\": the layer can't be told any more: " .. tostring(e and e.name))
			UI:Hide(); FlushAll()
		end
	end
	T.Fire("UPDATE_MOUSEOVER_UNIT")
	T.Fire("PLAYER_TARGET_CHANGED")
	check(asked == 0, "no creature's GUID read for a layer: " .. asked)
	-- not a question about layers
	check(LY.Question("which layer is hogger on") == nil and LY.Question("layer hop") == nil and LY.Question("my layer") ~= nil,
		"\"which layer is hogger on\", \"layer hop\": not the question")
	_G.UnitGUID = was.guid
	ns.db.easyMode = was.easy; UI:EasyChanged()
end
