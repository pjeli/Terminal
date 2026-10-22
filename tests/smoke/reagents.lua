-- Reagents on the empty prompt (0.64.4, the player: "try: nearest reagent vendor, if level is appropriate and if it is
-- needed: priest candles if none, paladin if empty on anything, mages, druids etc.")
local T = ...
local ns, check = T.ns, T.check
local E = ns.Easy

io.write("[reagents: where to buy them, suggested]\n")
do
	local CS = ns.ClassSpells
	local save = { known = CS.Known, count = C_Item.GetItemCount, gcount = _G.GetItemCount, class = _G.UnitClass,
		missing = ns.Integrations.AddonMissing, easy = ns.db.easyMode }
	local known, bags = {}, {}
	CS.Known = function(id) return known[id] == true end
	C_Item.GetItemCount = function(id) return bags[id] or 0 end
	_G.GetItemCount = C_Item.GetItemCount
	local function Need(cls) local t = E.ReagentNeed(cls); return t and table.concat(t, ",") or nil end

	-- a priest: no Prayer of Fortitude yet (too low), nothing; with it and no candles, Holy Candles; with rank 2, Sacred
	check(Need("PRIEST") == nil, "a priest without Prayer of Fortitude: nothing to buy")
	known = { [21562] = true }
	check(Need("PRIEST") == "17028", "Prayer of Fortitude, no Holy Candles: to buy")
	bags = { [17028] = 5 }
	check(Need("PRIEST") == nil, "Holy Candles carried: nothing")
	known = { [21562] = true, [21564] = true }
	check(Need("PRIEST") == "17029", "rank 2 known: its Sacred Candles, not the Holy ones carried")

	-- a paladin: empty on anything (Divine Intervention's symbols, the Greater Blessings')
	known, bags = { [19752] = true, [25898] = true }, { [17033] = 2 }
	check(Need("PALADIN") == "21177", "a paladin with Symbols of Divinity, no Symbols of Kings: those")
	bags = {}
	check(Need("PALADIN") == "17033,21177", "neither: both")

	-- a mage: runes for the Teleports and Portals; a druid: the seed of Rebirth's highest rank; a warrior: never
	known, bags = { [3567] = true, [11417] = true }, { [17031] = 10 }
	check(Need("MAGE") == "17032", "a mage with teleport runes, no portal runes: those")
	known, bags = { [20484] = true, [20739] = true }, { [17034] = 3 }
	check(Need("DRUID") == "17035", "Rebirth rank 2: Stranglethorn Seeds, not the Maple Seeds carried")
	check(Need("WARRIOR") == nil, "a warrior: no reagents")

	-- the suggestion itself: Simple mode's words, Advanced's, offered more often than the others
	known, bags = { [21562] = true }, {}
	_G.UnitClass = function() return "Priest", "PRIEST" end
	ns.Integrations.AddonMissing = function() return false end -- (Questie here)
	local found, adv
	for _, x in ipairs(E.PersonalTagged(false)) do if x[1] == "nearest reagent vendor" then found = x end end
	local hadNpc = ns.providers.npc
	if not hadNpc then ns:RegisterProvider("npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = function() return {} end }) end
	for _, x in ipairs(E.PersonalTagged(true)) do if x[1] == "@npc reagent is:vendor faction:friendly sort:nearest" then adv = x end end
	check(found and found.todo, "try: nearest reagent vendor, as pressing")
	check(adv and adv.todo, "Advanced: @npc reagent is:vendor faction:friendly sort:nearest (as Alt+` writes the Simple line)")
	if not hadNpc then
		ns.providers.npc = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "npc" then table.remove(ns.providerOrder, i) end end
		ns:AliasesChanged()
	end
	-- bought: gone on the next open, not a minute on
	ns.db.easyMode = true
	E.ResetPool()
	local function Offered(line)
		for _, l in ipairs(E.ExamplePool()) do if l == "try: " .. (line or "nearest reagent vendor") then return true end end
		return false
	end
	check(Offered(), "no candles: the empty prompt offers the reagent vendor")
	-- (release review, 0.64.6) bag changes that don't change what's to buy: the pool as it was, not made again (it
	-- reshuffled the examples on every arrow shot); a burst of them checked once
	local list = E.ExamplePool()
	local checks, realCheck = 0, E.CheckBuy
	E.CheckBuy = function() checks = checks + 1 return realCheck() end
	for _ = 1, 5 do E.OnBags() end
	T.FlushAll()
	E.CheckBuy = realCheck
	check(checks == 1 and E.ExamplePool() == list, "five bag changes, nothing new to buy: checked once, the pool kept: " .. checks)
	bags = { [17028] = 20 }
	E.OnBags(); T.FlushAll()
	check(not Offered(), "candles bought: the next open doesn't offer it")
	-- (release review, 0.64.6) a reagent a reagent vendor doesn't sell: a rogue's Flash Powder, at a poison supplier
	known, bags = { [1856] = true }, {}
	_G.UnitClass = function() return "Rogue", "ROGUE" end
	local saveName = C_Item.GetItemNameByID
	C_Item.GetItemNameByID = function(id) return id == 5140 and "Flash Powder" or nil end
	local rv, fp
	for _, x in ipairs(E.PersonalTagged(false)) do
		if x[1] == "nearest reagent vendor" then rv = x end
		if x[1] == "nearest vendor sells:flash_powder" then fp = x end
	end
	check(fp and fp.todo and not rv, "a rogue out of Flash Powder: the vendors selling it, not a reagent vendor")
	C_Item.GetItemNameByID = saveName
	-- (the player, 0.64.6) a reagent of a spell cast now and then (Divine Intervention, a Portal): suggested, but not more
	-- often than the other examples; an everyday one missing too (Symbols of Kings): more often again
	known, bags = { [19752] = true, [25898] = true }, { [21177] = 20 }
	_G.UnitClass = function() return "Paladin", "PALADIN" end
	local function Reagent(adv)
		for _, x in ipairs(E.PersonalTagged(adv)) do
			if x[1] == "nearest reagent vendor" or x[1] == "@npc reagent is:vendor faction:friendly sort:nearest" then return x end
		end
	end
	local r = Reagent(false)
	check(r and not r.todo, "a paladin out of Symbols of Divinity only: suggested, not more often")
	bags = {}
	r = Reagent(false)
	check(r and r.todo, "out of Symbols of Kings too: more often")
	known, bags = { [11417] = true }, {}
	_G.UnitClass = function() return "Mage", "MAGE" end
	r = Reagent(false)
	check(r and not r.todo, "a mage out of portal runes only: not more often")

	CS.Known, C_Item.GetItemCount, _G.GetItemCount, _G.UnitClass = save.known, save.count, save.gcount, save.class
	ns.Integrations.AddonMissing, ns.db.easyMode = save.missing, save.easy
	E.ResetPool()
end
