-- Your layer (Providers/Layer.lua, 1.1.13, the player: "what layer am i on" should work; or just "my layer"; @layer a
-- single entry): read from the creatures you meet, their GUID's zone UID.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local LY = ns.Layer

io.write("[layer: what layer am i on, my layer, @layer]\n")
do
	local was = { guid = _G.UnitGUID, name = _G.UnitName, inst = _G.IsInInstance, zone = _G.GetRealZoneText, easy = ns.db.easyMode }
	local units = {}
	_G.UnitGUID = function(u) return units[u] and units[u].guid end
	_G.UnitName = function(u) return units[u] and units[u].name end
	local inside = false
	_G.IsInInstance = function() return inside, inside and "party" or "none" end
	_G.GetRealZoneText = function() return "Elwynn Forest" end
	LY.Reset()
	local function Saw(event, unit, guid, name)
		units[unit] = { guid = guid, name = name }
		LY.frame.scripts.OnEvent(LY.frame, event, event == "NAME_PLATE_UNIT_ADDED" and unit or nil)
	end
	local function Ask(q)
		UI:Open(q); FlushAll()
		local r = UI.Results()
		return r[1], r
	end
	check(LY.FromGUID("Creature-0-4372-0-2051-299-0000AB12CD") == 2051 and LY.FromGUID("Player-4372-0ABCDEF0") == nil
		and LY.FromGUID("Pet-0-4372-0-2051-416-0100AB12CD") == nil and LY.FromGUID("Vehicle-0-4372-1-3000-1-00") == 3000,
		"a creature's or a vehicle's GUID gives its layer; a player's or a pet's none")
	for _, simple in ipairs({ true, false }) do
		ns.db.easyMode = simple; UI:EasyChanged()
		LY.Reset(); ns.providers.layer._dirty = true
		local mode = simple and "Simple" or "Advanced"
		-- nothing met yet: says how to get one
		local r = Ask(simple and "what layer am i on" or "@layer")
		check(r and r.noActivate and tostring(r.name):find("mouse over", 1, true), mode .. ": nothing met yet: how to: " .. tostring(r and r.name))
		UI:Hide(); FlushAll()
		-- a creature moused over
		Saw("UPDATE_MOUSEOVER_UNIT", "mouseover", "Creature-0-4372-0-2051-299-0000AB12CD", "Marshal Dughan")
		for _, q in ipairs(simple and { "what layer am i on", "my layer", "which layer am i on", "layer" } or { "@layer", "what layer am i on" }) do
			local e, all = Ask(q)
			check(e and e.name == "Layer 2051" and #all == 1 and tostring(e.detail):find("Marshal Dughan", 1, true),
				mode .. ": \"" .. q .. "\": Layer 2051, from Marshal Dughan: " .. tostring(e and e.name) .. " / " .. tostring(e and e.detail))
			UI:Hide(); FlushAll()
		end
		-- another layer met (a group joined): the latest, and which of the two by number
		Saw("NAME_PLATE_UNIT_ADDED", "nameplate1", "Creature-0-4372-0-1987-6-0000AB12CE", "Kobold Vermin")
		local e = Ask(simple and "my layer" or "@layer")
		check(e and e.name == "Layer 1987" and tostring(e.detail):find("1 of 2", 1, true), mode .. ": moved: Layer 1987, 1 of 2 seen: " .. tostring(e and e.detail))
		UI:Hide(); FlushAll()
	end
	-- not a question about layers
	check(LY.Question("which layer is hogger on") == nil and LY.Question("layer hop") == nil and LY.Question("my layer") ~= nil,
		"\"which layer is hogger on\", \"layer hop\": not the question")
	-- a secret GUID, a player: nothing read
	LY.Reset()
	local secretWas = ns.Secret
	ns.Secret = function(v) return v == "secret" end
	Saw("PLAYER_TARGET_CHANGED", "target", "secret", "Someone")
	Saw("PLAYER_TARGET_CHANGED", "target", "Player-4372-0ABCDEF0", "Plamen")
	ns.Secret = secretWas
	check(LY.Current() == nil, "a secret GUID or a player's: nothing kept")
	-- in a dungeon: no layers
	Saw("PLAYER_TARGET_CHANGED", "target", "Creature-0-4372-36-5000-639-0000AB12CD", "Edwin VanCleef")
	inside = true
	ns.providers.layer._dirty = true
	ns.db.easyMode = false; UI:EasyChanged()
	local e = Ask("@layer")
	check(e and e.noActivate and tostring(e.name):find("dungeon", 1, true), "in a dungeon: no layers there: " .. tostring(e and e.name))
	UI:Hide(); FlushAll()
	inside = false
	-- Enter says it in chat; what's sent to chat names the zone
	Saw("PLAYER_TARGET_CHANGED", "target", "Creature-0-4372-0-2051-299-0000AB12CD", "Marshal Dughan")
	e = Ask("@layer")
	check(e and LY.ShareText(e) == "Layer 2051 (Elwynn Forest)", "to chat: Layer 2051 (Elwynn Forest): " .. tostring(e and LY.ShareText(e)))
	local a, b = ns.Easy.Verbs(e)
	check(a == "show in chat" and b == "put in the chat box", "its verbs: show in chat, put in the chat box")
	-- a loading screen: what was read may be another layer's
	LY.frame.scripts.OnEvent(LY.frame, "PLAYER_ENTERING_WORLD")
	check(LY.Current() == nil, "a loading screen: read again")
	UI:Hide(); FlushAll()
	LY.Reset()
	_G.UnitGUID, _G.UnitName, _G.IsInInstance, _G.GetRealZoneText = was.guid, was.name, was.inst, was.zone
	ns.db.easyMode = was.easy; UI:EasyChanged()
end
