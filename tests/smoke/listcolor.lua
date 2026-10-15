-- An item row drawn before the game had the item (its quality's colour read as it's drawn) came out white and stayed
-- so till it was drawn again (scrolled off and back; the player's screenshot, loot lists): the item is asked for and
-- the rows drawn again once it comes.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll

io.write("[list: item rows coloured once their item comes]\n")
do
	local cached, quality = false, nil
	local saveCached, saveReq = C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID
	local asked = {}
	C_Item.IsItemDataCachedByID = function(id) if id == 990001 then return cached end return true end
	C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
	local row = setmetatable({ name = "Late Sword", itemID = 990001, kind = "loot", detail = "" }, { __index = function(_, k)
		if k == "color" then return quality and ns.QualityHex(quality) or nil end
	end })
	UI:Open("")
	FlushAll()
	UI.results, UI.offset = { row }, 0
	UI:Render()
	check(asked[1] == 990001 and UI.colorWait.ids[990001], "drawn before its item came: the item asked for")
	UI:Render()
	check(UI.colorWait.n == 1, "...waited for once (drawn again: not twice)")
	-- (it comes: the rows drawn again, in its colour)
	cached, quality = true, 4
	local renders, real = 0, UI.Render
	UI.Render = function(self, ...) renders = renders + 1 return real(self, ...) end
	UI.colorWait.frame:GetScript("OnEvent")(UI.colorWait.frame, "ITEM_DATA_LOAD_RESULT", 990001, true)
	FlushAll()
	UI.Render = real
	check(renders >= 1 and UI.colorWait.n == 0, "its item come: the rows drawn again")
	check(tostring(UI.rows[1].label:GetText()):find("|cffa335ee", 1, true), "...in its quality's colour: "
		.. tostring(UI.rows[1].label:GetText()))
	UI:Hide()
	FlushAll()
	C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID = saveCached, saveReq
end

-- (0.51.7, the player: still white till scrolled past) the server answered after the wait gave up, and an item was asked
-- for once a session: it's looked at while the terminal is open, and asked for again when drawn again later
io.write("[list: an item that comes late, or with no event heard, is still coloured]\n")
do
	local cached, asks = false, 0
	local saveCached, saveReq = C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID
	C_Item.IsItemDataCachedByID = function(id) if id == 990002 then return cached end return true end
	C_Item.RequestLoadItemDataByID = function(id) if id == 990002 then asks = asks + 1 end end
	local row = setmetatable({ name = "Slow Helm", itemID = 990002, kind = "loot", detail = "" }, { __index = function(_, k)
		if k == "color" then return cached and ns.QualityHex(4) or nil end
	end })
	UI:Open("")
	FlushAll()
	UI.results, UI.offset = { row }, 0
	UI:Render()
	check(asks >= 1, "drawn white: asked for")
	-- it comes a while later, its event not heard (it came for another asker, or after a reload of the cache)
	local clock = T.clock()
	for _ = 1, 15 do T.Flush() if T.clock() - clock >= 12 then break end end
	cached = true
	FlushAll()
	check(tostring(UI.rows[1].label:GetText()):find("|cffa335ee", 1, true), "come 12 s on, no event heard: drawn in its colour: "
		.. tostring(UI.rows[1].label:GetText()))
	check(UI.colorWait.n == 0, "...and no longer waited for")
	-- given up on, then drawn again: asked for again
	cached = false
	UI:Render()
	local before = asks
	for _ = 1, 200 do T.Flush() if UI.colorWait.n == 0 then break end end
	UI:Render()
	check(UI.colorWait.ids[990002] ~= nil and asks > before, "given up on, then drawn again: waited for and asked for again ("
		.. before .. " -> " .. asks .. ")")
	UI:Hide()
	FlushAll()
	C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID = saveCached, saveReq
end

