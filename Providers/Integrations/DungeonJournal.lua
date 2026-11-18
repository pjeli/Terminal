local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations

-- DungeonJournal (ForeverDungeonJournal on disk, by Exehn: a boss, loot and quest journal of WoW Forever's dungeons),
-- read while it's installed (1.5.3, the player's ask):
--   * "Show in Dungeon Journal" in a row's right-click menu: an item it lists (a boss's loot, a quest's reward) opens on
--     its page with the item pointed at, a quest on its quest page, a dungeon (@dungeon) on its own page;
--   * @favorite (also @favourite: US spelling first, 1.6.0, the player's ask): the items you starred in it (right-click
--     in its loot lists), this character's, each with where it comes from; Enter opens it there. "my favorites" asks for
--     them; is:favorite finds them among other items too.
-- It has no API documented for other addons: its whole namespace is a global table (ForeverDungeonJournal_NS), read and
-- called here as OneForAll's is, every field checked, every call in a pcall. What isn't in the shape expected is said
-- once in chat and on its .integrations line (I.Failed, as every integration's) and the rest goes on without it.
-- Nothing of its data is copied.

local DJ = {}
ns.DungeonJournal = DJ
local Safe, Num, Str, Lower = ns.Safe, ns.Num, ns.Str, ns.Lower
local SEP = ns.DETAIL_SEP
DJ.ADDON, DJ.NAME = "ForeverDungeonJournal", "DungeonJournal"

local function Loaded()
	local f = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
	return f and Safe(f, DJ.ADDON) and true or false
end
DJ.Loaded = Loaded

--- Its namespace when it's loaded and has what Terminal reads (its dungeons and their order), else nil.
function DJ.Lib()
	if not Loaded() then return nil end
	local N = rawget(_G, "ForeverDungeonJournal_NS")
	if type(N) ~= "table" or type(N.DB) ~= "table" or type(N.ORDER) ~= "table" then return nil end
	return N
end
function DJ.On() return DJ.Lib() ~= nil end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
	ns:Trace("dungeonjournal: a call failed: " .. tostring(a))
	return nil
end

-- (what of it isn't there any more: said once, in chat and on its .integrations line; `what`: its function)
local function Lost(what) I.Failed(DJ.NAME, L["Show in Dungeon Journal is unavailable."], what .. " missing") end

----------------------------------------------------------------------
-- Which of its pages a row is
----------------------------------------------------------------------

--- Its dungeon for one of the game's instances: by the instance's map ID (its own table of them), else by the name
--- Terminal gives it ("The Hall of Thanes", "Dire Maul (North)"); an instance whose wings it lists apart (Scarlet
--- Monastery, Stratholme) opens on the first of them. nil: not one of its dungeons (a raid).
function DJ.Dungeon(instanceID, name)
	local N = DJ.Lib()
	if not N then return nil end
	local DB, tries = N.DB, {}
	local byID = Num(instanceID) and type(N.INSTANCE_ID_TO_DUNGEON) == "table" and N.INSTANCE_ID_TO_DUNGEON[instanceID]
	if type(byID) == "string" then tries[#tries + 1] = byID end
	if type(name) == "string" then tries[#tries + 1] = name end
	for _, t in ipairs(tries) do
		local bare = t:gsub("^The ", "")
		for _, c in ipairs({ t, bare, "The " .. bare, (t:gsub("%s*%((.-)%)$", ": %1")) }) do
			if type(DB[c]) == "table" then return c end
		end
		for _, d in ipairs(N.ORDER) do
			if type(d) == "string" and d:sub(1, #bare + 1) == bare .. ":" and type(DB[d]) == "table" then return d end
		end
	end
	return nil
end

-- its quests by id: the dungeon whose page lists each (read once per its namespace)
local quests = { of = nil, map = nil }
local function QuestDungeon(id)
	local N = DJ.Lib()
	if not N or not id then return nil end
	if quests.of ~= N then
		local map = {}
		for _, d in ipairs(N.ORDER) do
			local page = type(d) == "string" and N.DB[d]
			for _, q in ipairs(type(page) == "table" and type(page.quests) == "table" and page.quests or {}) do
				local qid = type(q) == "table" and Num(q.id)
				if qid and not map[qid] then map[qid] = d end
			end
		end
		quests.of, quests.map = N, map
	end
	return quests.map[id]
end

local function ItemSource(id)
	local N = DJ.Lib()
	if not (N and id) then return nil end
	if type(N.GetItemSource) ~= "function" then Lost("GetItemSource") return nil end
	local s = Call(N.GetItemSource, id)
	return type(s) == "table" and type(s.dungeonName) == "string" and s or nil
end
DJ.ItemSource = ItemSource

--- Where a row opens it: { item = id } (its boss's or quest's page), { dungeon, quest }, { dungeon }; nil when it
--- lists none of it (or isn't there). Its own favourites' rows open it on Enter already.
function DJ.Target(e)
	if type(e) ~= "table" or e.kind == "favorite" or not DJ.On() then return nil end
	if e.kind == "dungeon" or e.kind == "raid" then
		local d = DJ.Dungeon(rawget(e, "instanceID") or e.instanceID, e.name)
		return d and { dungeon = d } or nil
	end
	local item = Num(e.itemID)
	if item and ItemSource(item) then return { item = item } end
	local q = Num(e.questID) or Num(e.qid)
	local d = q and QuestDungeon(q)
	if d then return { dungeon = d, quest = q } end
	return nil
end

----------------------------------------------------------------------
-- Opening it
----------------------------------------------------------------------

--- Opens the journal on that page. It picks its own page as it's shown, so the page is asked for again a moment after
--- (as its own world map buttons do). false: it couldn't (said in chat).
function DJ.Open(t)
	local N = DJ.Lib()
	if not (N and type(t) == "table") then return false end
	local frame = rawget(_G, "ForeverDungeonJournalFrame")
	local wasShown = type(frame) == "table" and type(frame.IsShown) == "function" and Safe(frame.IsShown, frame)
	local fn, args
	if t.item then
		if not ItemSource(t.item) then return false end -- (an item it doesn't list: nothing to open on)
		fn, args = N.OpenItemSource, { t.item }
	elseif t.quest then
		fn, args = N.OpenQuestPage, { t.dungeon, t.quest }
	else
		fn, args = N.OpenBossPage, { t.dungeon } -- (no boss: the dungeon's page)
	end
	if type(fn) ~= "function" then
		Lost(t.item and "OpenItemSource" or t.quest and "OpenQuestPage" or "OpenBossPage")
		return false
	end
	if not t.item and not wasShown then
		-- (an item's opener shows the journal itself)
		if type(N.ToggleJournal) == "function" then Call(N.ToggleJournal)
		elseif type(frame) == "table" and type(frame.Show) == "function" then Safe(frame.Show, frame)
		else Lost("ToggleJournal") return false end
	end
	Call(fn, unpack(args))
	if not wasShown and C_Timer and C_Timer.After then C_Timer.After(0.05, function() Call(fn, unpack(args)) end) end
	ns:Trace(("dungeonjournal: opened on %s"):format(tostring(t.item and ("item " .. t.item) or t.quest and (t.dungeon .. " quest " .. t.quest) or t.dungeon)))
	return true
end

----------------------------------------------------------------------
-- @favorite: the items you starred in it (this character's)
----------------------------------------------------------------------

local function Favourites()
	if not DJ.On() then return nil end
	local db = rawget(_G, "ForeverDungeonJournalCharacterDB")
	local favs = type(db) == "table" and db.favouriteItems
	return type(favs) == "table" and favs or nil
end

--- Is this item one of your favourites there? (its own answer; false without it)
function DJ.IsFavourite(id)
	local N = DJ.Lib()
	id = Num(id)
	if not (N and id) then return false end
	if type(N.IsFavouriteItem) == "function" then return Call(N.IsFavouriteItem, id) == true end
	local favs = Favourites()
	return favs ~= nil and favs[tostring(id)] ~= nil
end

local function DungeonText(d)
	local N = DJ.Lib()
	local t = N and type(N.LocalizeDungeonName) == "function" and Str(Call(N.LocalizeDungeonName, d))
	return t or d
end
local function FavText(e) return ns.Share and ns.Share.Text and ns.Share.Text(e) or e.name end
local FAV_CHATBOX, FavToChat = ns.ChatBoxPair(FavText)
local function OpenFav(e)
	if not DJ.Open({ item = e.itemID }) then
		-- (an item it no longer lists: its dungeon's page, as the favourite says)
		local d = e.djDungeon and DJ.Lib() and DJ.Lib().DB[e.djDungeon] and e.djDungeon
		if not (d and DJ.Open({ dungeon = d })) then ns:Print(L["DungeonJournal has no page for %s."]:format(e.name)) end
	end
end

--- The rows: one a favourite, by the order of its dungeons, then by name.
function DJ.FavouriteRows()
	local out = {}
	local favs = Favourites()
	if not favs then return out end
	local N = DJ.Lib()
	local rank = {}
	for i, d in ipairs(N.ORDER) do if type(d) == "string" then rank[d] = i end end
	for _, f in pairs(favs) do
		local id = type(f) == "table" and Num(tonumber(f.id))
		if id then
			local d = Str(f.dungeon)
			local from = Str(f.boss) or Str(f.questName)
			local name = ns.ItemName(id) or Str(f.name) or L["item %s"]:format(("%.0f"):format(id))
			local q = Num(f.quality)
			local icon = C_Item and C_Item.GetItemIconByID and Safe(C_Item.GetItemIconByID, id)
			out[#out + 1] = {
				key = id, name = name, itemID = id, link = "item:" .. ("%.0f"):format(id), icon = icon or 134400,
				color = q and ns.QualityHex and ns.QualityHex(q) or nil,
				detail = ns.Join(SEP, from, d and DungeonText(d)), djDungeon = d, slot = Str(f.slot),
				text = Lower(table.concat({ L["favorite"], "favorite favourite", Str(f.slot) or "", from or "", d or "" }, " ")),
				order = rank[d or ""] or 999,
				activate = OpenFav, secondary = FavToChat, secondarySecure = FAV_CHATBOX,
			}
		end
	end
	table.sort(out, function(a, b)
		if a.order ~= b.order then return a.order < b.order end -- (its dungeons' order, then by name)
		return a.name < b.name
	end)
	for i, e in ipairs(out) do e.order = i end
	return out
end

local function Register()
	if ns.providers.favorite then return end
	ns:RegisterProvider("favorite", {
		label = L["Favorite"], color = "ffff73ab", aliases = { "favorite", "favorites", "favourite", "favourites", "fav", "favs" },
		lazy = true, refreshOnOpen = true, -- (starred in its window: no event says so)
		simpleCategory = "loot",
		verbs = { L["show in Dungeon Journal"], L["link in chat"] },
		collect = DJ.FavouriteRows,
	})
end

--- At login (its saved favourites are read by then): @favorite while it's there.
function DJ.Setup()
	if DJ.On() then Register() end
end

--- is:favorite's answer for a row that isn't a mount, pet or toy (Providers/Collections.lua asks): one of @favorite's,
--- or an item starred there.
function DJ.FavouriteRow(e)
	if e.kind == "favorite" then return true end
	local id = Num(e.itemID)
	return id ~= nil and DJ.IsFavourite(id)
end

--- .integrations' line.
function DJ.Status()
	if not Loaded() then return L["not found"] end
	local ver = I._ and I._.AddOnVersion and I._.AddOnVersion(DJ.ADDON) or "?"
	if not DJ.On() then return L["found (%s), but not its API for other addons: update %s"]:format(ver, DJ.NAME) end
	local n = 0
	for _ in pairs(Favourites() or {}) do n = n + 1 end
	return L["found (%s). %d favorites (@favorite); right-click a row: Show in Dungeon Journal"]:format(ver, n)
end

----------------------------------------------------------------------
-- "my favorites", "dungeon journal favorites", "favorite items" (and the UK spellings)
----------------------------------------------------------------------

local Q = {}
ns.DungeonJournalFavourites = Q
local FAV = { favourite = true, favourites = true, favorite = true, favorites = true, favs = true, faves = true, starred = true }
local ASK = {}
for w in ("my me show list the all what are is which whats what's dungeon journal journals dj items item loot gear in of i have"):gmatch("%S+") do ASK[w] = true end

--- { } when the line asks for the items starred in it, else nil (and nil without it: "favorite mounts" is the
--- collections' question).
function Q.Question(text)
	if not ns.providers.favorite then return nil end
	local t = ns.QuestionText and ns.QuestionText(text)
	if not t then return nil end
	local fav = false
	for w in t:gmatch("%S+") do
		if FAV[w] then fav = true elseif not ASK[w] then return nil end
	end
	return fav and {} or nil
end
function Q.Line() return "@favorite " end
function Q.Footer() return L["Your Dungeon Journal favorites"] end
function Q.None() return { ns.NoteRow(L["No favorites yet: right-click an item in the Dungeon Journal to star it"]) } end

do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function() Safe(DJ.Setup) end)
end
