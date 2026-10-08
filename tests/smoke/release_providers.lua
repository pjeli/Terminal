-- Release review fixes: journal filters put back only when read, the item-name give-up timer, the
-- achievement lists read once per change.
local T = ...
local ns, check, names, Flush, FlushAll = T.ns, T.check, T.names, T.Flush, T.FlushAll

local function reload() assert(loadfile("Terminal/Providers/Collections.lua"))("Terminal", ns) end
local function drop(id)
	ns.providers[id] = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
end

io.write("[toys: a filter list that can't be read is left alone]\n")
do
	local save = { tb = _G.C_ToyBox, pj = _G.C_PetJournal, has = _G.PlayerHasToy, ne = _G.GetNumExpansions }
	local state = { src = { true, true, true }, setCalls = 0 }
	_G.C_ToyBox = {
		GetNumToys = function() return 1 end,
		GetToyFromIndex = function() return 1001 end,
		GetToyInfo = function(id) return id, "Toy Train Set", 7, false end,
		-- the second source can't be read: the list must not be put back from a guess (that turned it off)
		IsSourceTypeFilterChecked = function(i) if i == 2 then error("no answer") end return state.src[i] end,
		SetSourceTypeFilter = function(i, v) state.setCalls = state.setCalls + 1; state.src[i] = v end,
		SetAllSourceTypeFilters = function(v) for i = 1, 3 do state.src[i] = v end end,
	}
	_G.C_PetJournal = { GetNumPetSources = function() return 3 end }
	_G.GetNumExpansions = nil
	_G.PlayerHasToy = function() return true end
	reload()
	local t = names(ns:GetEntries(ns.providers.toys))
	check(t["Toy Train Set"], "the toy is still read")
	check(state.setCalls == 0 and state.src[1] and state.src[2] and state.src[3], "no source filter turned off after a failed read")
	_G.C_ToyBox, _G.C_PetJournal, _G.PlayerHasToy, _G.GetNumExpansions = save.tb, save.pj, save.has, save.ne
	drop("toys")
end

io.write("[item names: an old give-up timer leaves a new wait alone]\n")
do
	local W, NameOf = ns.ItemNames.wait, ns.ItemNames.NameOf
	local saveReq, saveBy = C_Item.RequestLoadItemDataByID, C_Item.GetItemNameByID
	C_Item.RequestLoadItemDataByID = function() end
	C_Item.GetItemNameByID = function() return nil end
	FlushAll()
	local f = ns.ItemNames.frame
	-- first wait: starts its 10 s timer, then ends early
	check(NameOf(990001, "|h[]|h") == nil and W.count == 1, "first item awaited")
	f.scripts.OnEvent(f, "GET_ITEM_INFO_RECEIVED", 990001, true)
	check(W.count == 0, "it arrived")
	-- 5 s on (the virtual clock jumps to the next timer), then a second wait starts
	C_Timer.After(5, function() end)
	Flush()
	check(NameOf(990002, "|h[]|h") == nil and W.count == 1, "second item awaited")
	Flush() -- (runs only the first wait's timer, due 5 s before the second's)
	check(W.count == 1 and W.ids[990002], "the first wait's timer leaves the second wait running")
	FlushAll()
	check(W.count == 0, "its own timer still gives up")
	C_Item.RequestLoadItemDataByID, C_Item.GetItemNameByID = saveReq, saveBy
	ns.providers.items._dirty = true
end

io.write("[stored names: an old give-up timer leaves a new wait alone]\n")
do
	local St = ns.Stored
	local saveReq, saveBy = C_Item.RequestLoadItemDataByID, C_Item.GetItemNameByID
	C_Item.RequestLoadItemDataByID = function() end
	C_Item.GetItemNameByID = function() return nil end
	FlushAll()
	local f = St.nameFrame
	local function waitingFor() local s = St.Busy() return s and tonumber(s:match("Loading (%d+)")) or 0 end
	check(St.Name(991001) == nil and waitingFor() == 1, "stored: first name awaited")
	f.scripts.OnEvent(f, "GET_ITEM_INFO_RECEIVED", 991001, true)
	check(waitingFor() == 0, "stored: it arrived")
	C_Timer.After(5, function() end)
	Flush()
	check(St.Name(991002) == nil and waitingFor() == 1, "stored: second name awaited")
	Flush() -- (the first wait's timer, due 5 s before the second's)
	check(waitingFor() == 1, "stored: the first wait's timer leaves the second wait running")
	FlushAll()
	check(waitingFor() == 0, "stored: its own timer still gives up")
	C_Item.RequestLoadItemDataByID, C_Item.GetItemNameByID = saveReq, saveBy
	if ns.providers.stored then ns.providers.stored._dirty = true end
end

io.write("[achievements: the whole list read once per change]\n")
do
	local save = { info = _G.GetAchievementInfo, num = _G.GetCategoryNumAchievements, list = _G.GetCategoryList }
	local reads = 0
	_G.GetCategoryList = function() reads = reads + 1; return { 1 } end
	_G.GetCategoryNumAchievements = function() return 2 end
	_G.GetAchievementInfo = function(_, i)
		if i == 2 then return 8, "Level 20", 10, false, 1, 1, 1, "Reach level 20.", 0, 1 end
		return 7, "Level 10", 10, true, 1, 1, 1, "Reach level 10.", 0, 1
	end
	local all, earned = ns.providers.achievementlist, ns.providers.achievements
	all._dirty, earned._dirty = true, true
	-- an achievement earned: both lists are stale (the same event); @achievement read first, then a plain search
	ns:GetEntries(all)
	reads = 0
	ns:GetEntries(earned)
	check(reads == 0, "the earned list reuses the whole list just made: read " .. reads .. " more time(s)")
	-- the earned list stale again (a change) with the whole one it was made from: that one is read again
	earned._dirty = true
	ns:GetEntries(earned)
	check(reads == 1, "made again from a fresh read when the whole list is the one it already used: " .. reads)
	check(names(ns:GetEntries(earned))["Level 10"] and not names(ns:GetEntries(earned))["Level 20"], "still earned ones only")
	_G.GetAchievementInfo, _G.GetCategoryNumAchievements, _G.GetCategoryList = save.info, save.num, save.list
	all._dirty, earned._dirty = true, true
end
