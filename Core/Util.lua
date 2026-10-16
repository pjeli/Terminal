local ns = select(2, ...)
local L = ns.L

-- Small helpers every provider needs: guarded calls, values that may be "secret" on this
-- client, and the two routines the character window's lists share (reading a list with its
-- collapsed headers opened, pointing at a row in a scrolling list).

--- fn(...) in a pcall: all its results, or nothing when it isn't a function or errors.
local function Results(ok, ...)
	if ok then return ... end
end
function ns.Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	return Results(pcall(fn, ...))
end

--- Whether the value is one of this client's secret values (quest text, health...): never compared.
function ns.Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

--- A usable string: not empty, not secret; else nil. (Secret first: comparing a secret value, even with "", is an
--- error on this client.)
function ns.Str(v)
	if type(v) ~= "string" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	if v == "" then return nil end
	return v
end

--- The given strings that are there (nil and "" left out), joined with `sep`: built by count, as a table with nils in
--- it would stop table.concat (or make it error) at the first hole.
function ns.Join(sep, ...)
	local out = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) == "string" and v ~= "" then out[#out + 1] = v end
	end
	return table.concat(out, sep)
end

--- A row's detail from its parts (nil and "" left out), joined as every list's are: "Lv 20  ·  Elwynn Forest  ·  grey"
--- (review, 0.48.6: a dozen lists joined theirs with two spaces). Not the distance in front ("80 yd  ..."), which the
--- list reads, nor Items' "x5  Backpack".
ns.DETAIL_SEP = "  ·  "
function ns.Detail(...) return ns.Join(ns.DETAIL_SEP, ...) end

--- A row's detail with how far it is said first: "80 yd  Sells it". Always the English "N yd": the list reads it back
--- into its distance column (List.lua FillRow, translated there) and keeps it up to date as you walk; the rest is
--- `nearRest` (review, 0.53.6: "quest upgrades" wrote the translated "%.0f m", and lost the column on German clients).
function ns.NearDetail(d, rest)
	return ("%.0f yd"):format(d) .. ((rest and rest ~= "") and ("  " .. rest) or "")
end

--- An answer's rows scored in the order given (the first on top): no search scored them. Returns them.
function ns.ScoreInOrder(rows)
	for i, e in ipairs(rows) do e._score = 1e6 - i end
	return rows
end

--- A list's rows ranked by their own order, kept among equally good matches (the rank is under 1, a score's tie-break):
--- `scale` (0.5 by default) how much it may count. Returns them. (Review, 0.53.6: these two loops had 15 and 13 copies.)
function ns.RankInOrder(rows, scale)
	local n, k = #rows, scale or 0.5
	for i, e in ipairs(rows) do e._rank = (n - i + 1) / (n + 1) * k end
	return rows
end

--- A line in a list saying why it lists nothing ("No mail kept yet: ..."): not a result, nothing to run or send.
function ns.NoteRow(text, detail)
	return { name = text, raw = true, icon = false, noActivate = true, kindLabel = "", detail = detail or "",
		_pos = ns.UI and ns.UI.NO_POS or nil }
end

--- A list's leadRow saying `text` when the list has nothing at all (asked for by name: @mail, its Simple category);
--- `empty(p)` tells, after the list is made.
function ns.EmptyLead(text, empty)
	return function(p, _, res)
		if res and #res > 0 then return nil end
		ns:GetEntries(p)
		if not empty(p) then return nil end
		if type(text) == "function" then return ns.NoteRow(text()) end -- (a function: the text and its detail)
		return ns.NoteRow(text)
	end
end

--- A usable number: not secret; else nil.
function ns.Num(v)
	if type(v) ~= "number" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

--- A frame's (or any object's) name when it has a string one; else nil. Never errors.
local function NameOf(f) return f:GetName() end -- (one function for every call: walks over UIParent's children made a closure per frame)
function ns.FrameName(f)
	local ok, n = pcall(NameOf, f)
	return ok and type(n) == "string" and n or nil
end

--- The texts a row shows: its own GetText (when it has one and it's a string), then every FontString
--- region's text, in that order. Each caller compares them in its own way. A secret text is left out (comparing it
--- errors: the row counted as no match whatever its other texts said; review, 0.53.6), as is an empty one.
function ns.FrameTexts(f)
	local texts = {}
	if f.GetText then
		local ok, t = pcall(f.GetText, f)
		if ok and ns.Str(t) then texts[#texts + 1] = t end
	end
	for _, r in ipairs({ f:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "FontString" then
			local t = ns.Str(r:GetText())
			if t then texts[#texts + 1] = t end
		end
	end
	return texts
end

--- Does a row show exactly `name` (its own text or one of its FontStrings; `prefix`: or a text starting with it,
--- "Swords 150/300")? Secret texts never compared (FrameTexts). One test for the lists that point at their row in a
--- game window (review, 0.53.6: Skills, Reputation and Equipment sets had a copy each, comparing raw texts).
function ns.HasText(f, name, prefix)
	if type(name) ~= "string" or name == "" then return false end
	for _, t in ipairs(ns.FrameTexts(f)) do
		if t == name or (prefix and t:sub(1, #name) == name) then return true end
	end
	return false
end

-- An item's quality, kept once the game has said it (0.51.9, the player: rows went white again after F5): the game
-- lets go of items it loaded a while ago, and asked again for one it no longer has it says nothing. Kept between
-- sessions too (ItemStore.lua, 0.51.13): after a /reload the loot list has its colours from the first search.
local qualityOf = {}
local function Keep(id, q)
	if qualityOf[id] == q then return end
	qualityOf[id] = q
	if ns.ItemStore then ns.ItemStore.Put("quality", id, q) end
end
function ns.ItemQuality(id)
	if type(id) ~= "number" then return nil end
	local get = C_Item and C_Item.GetItemQualityByID
	local q = get and ns.Safe(get, id)
	if type(q) == "number" and not ns.Secret(q) then Keep(id, q) return q end
	q = qualityOf[id]
	if q == nil then -- (looked up once a session; false: none kept)
		q = ns.ItemStore and ns.ItemStore.Get("quality", id)
		q = type(q) == "number" and q or false
		qualityOf[id] = q
	end
	return q or nil
end
--- What the game said of an item's quality elsewhere (GetItemInfo), kept as ns.ItemQuality keeps it.
function ns.NoteQuality(id, q)
	if type(id) == "number" and type(q) == "number" and not ns.Secret(q) then Keep(id, q) end
end
--- (tests: a new session, what was kept between sessions still there)
function ns.ForgetSessionQualities() qualityOf = {} end

--- The colour code of an item quality ("|cffa335ee"), or nil.
function ns.QualityHex(q)
	local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	return c and c.hex
end

--- The colour code of a class ("|cffc79c6e" for "WARRIOR"), or nil. Takes the class file name.
function ns.ClassHex(class)
	local c = type(class) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not c then return nil end
	if c.colorStr then return "|c" .. c.colorStr end
	return ("|cff%02x%02x%02x"):format(math.floor((c.r or 1) * 255), math.floor((c.g or 1) * 255), math.floor((c.b or 1) * 255))
end

--- Every row of a list whose headers can be collapsed (reputations, skills): collapsed headers are
--- expanded for the read and collapsed again afterwards, last first (indexes shift as headers close).
--- Game state only; no window is touched. api: count(), row(i) -> { name, header, ... } or nil,
--- collapsed(row), expand(i), collapse(i); guard: at most this many rows looked at while expanding.
function ns.ReadExpanded(api, guard)
	local opened = {}
	local i, n = 1, 0
	while i <= api.count() and n < guard do
		local r = api.row(i)
		if r and r.header and r.name and api.collapsed(r) then
			api.expand(i)
			opened[#opened + 1] = r.name
			ns.firedOwn = true -- (the list's own events come from this: Core drops them, and only then; review, 0.48.6)
		end
		i, n = i + 1, n + 1
	end
	local rows = {}
	for j = 1, api.count() do
		local r = api.row(j)
		if r and r.name then rows[#rows + 1] = r end
	end
	for k = #opened, 1, -1 do
		for j = api.count(), 1, -1 do
			local r = api.row(j)
			if r and r.header and r.name == opened[k] and not api.collapsed(r) then
				api.collapse(j)
				break
			end
		end
	end
	return rows
end

--- Scrolls a ScrollBox to the element whose data `pred` accepts (a row not scrolled into view
--- doesn't exist yet). True when the box could be asked.
function ns.ScrollBoxTo(box, pred)
	if not (box and box.ScrollToElementDataByPredicate) then return false end
	return (pcall(box.ScrollToElementDataByPredicate, box, function(node)
		local d = type(node) == "table" and (node.GetData and node:GetData() or node)
		return type(d) == "table" and pred(d) or false
	end))
end

--- Once `o.frame()` gives a showing frame: `o.find(frame)` its row; not there, `o.scroll(frame)` once
--- (the row may be further down the list) and look again; then `o.show(row)` (default: the
--- highlight). o.tries looks a tenth of a second apart; o.fail() when none found.
function ns.PointAtRow(o)
	local H = ns.Highlight
	local scrolled = false
	H:When(function()
		local f = o.frame()
		if not f then return nil end
		local row = o.find(f)
		if not row and not scrolled and o.scroll then
			scrolled = true
			o.scroll(f)
			row = o.find(f)
		end
		return row
	end, o.show or function(row) H:Show(row) end, o.tries or 20, o.fail)
end

-- the game's own words for each equipment slot (INVTYPE_x: "Main Hand", "Finger"...; English when the client lacks one)
local SLOT_INVTYPE = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_BODY", "INVTYPE_CHEST", "INVTYPE_WAIST",
	"INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_FINGER", "INVTYPE_FINGER", "INVTYPE_TRINKET",
	"INVTYPE_TRINKET", "INVTYPE_CLOAK", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_RANGED", "INVTYPE_TABARD" }
local SLOT_ENGLISH = { L["Head"], L["Neck"], L["Shoulder"], L["Shirt"], L["Chest"], L["Waist"], L["Legs"], L["Feet"], L["Wrist"],
	L["Hands"], L["Finger"], L["Finger"], L["Trinket"], L["Trinket"], L["Back"], L["Main Hand"], L["Off Hand"], L["Ranged"], L["Tabard"] }
--- An equipment slot's name (1-19), as the game says it.
function ns.SlotText(slot)
	local g = SLOT_INVTYPE[slot] and _G[SLOT_INVTYPE[slot]]
	return (type(g) == "string" and g ~= "") and g or SLOT_ENGLISH[slot]
end

--- What you wear, slot by slot over `names` (the game's slot names, "HeadSlot"...): for each slot with an item,
--- slotName, slotId, link, slotText (where it's worn as the game says it: "Finger", "Off Hand"), itemID. A slot name this
--- client doesn't know is left out. (One walk: @items' and @durability's each had one; review, 0.53.6.)
function ns.WornSlots(names)
	local i = 0
	return function()
		while true do
			i = i + 1
			local slotName = names[i]
			if not slotName then return nil end
			local ok, slotId = pcall(GetInventorySlotInfo, slotName)
			if ok and type(slotId) == "number" then
				local link = ns.Str(ns.Safe(GetInventoryItemLink, "player", slotId))
				if link then
					local itemID, _, _, equipLoc
					if C_Item and C_Item.GetItemInfoInstant then itemID, _, _, equipLoc = ns.Safe(C_Item.GetItemInfoInstant, link) end
					local slotText = (ns.Str(equipLoc) and ns.Str(_G[equipLoc])) or ns.SlotText(slotId) or (slotName:gsub("Slot", ""))
					return slotName, slotId, link, slotText, tonumber(link:match("item:(%d+)")) or ns.Num(itemID)
				end
			end
		end
	end
end

--- How long is left, said one way everywhere (the mail's days, a cooldown's seconds): "3 days", "1 day", "5 h",
--- "20 min", "35 s". (The collections' cooldowns said "4m", the mail "20 min": review, 0.53.6.)
function ns.Left(seconds)
	local s = math.max(0, tonumber(seconds) or 0)
	if s >= 2 * 86400 then return L["%d days"]:format(math.floor(s / 86400)) end
	if s >= 86400 then return L["1 day"] end
	if s >= 3600 then return L["%d h"]:format(math.floor(s / 3600)) end
	if s >= 60 then return L["%d min"]:format(math.floor(s / 60)) end
	return L["%d s"]:format(math.ceil(s))
end

--- How long ago, said one way everywhere: "just now" (under a minute), "12 min ago", "3 h ago", "2 d ago".
function ns.Ago(seconds)
	local d = math.max(0, tonumber(seconds) or 0)
	if d < 60 then return L["just now"] end
	if d < 3600 then return L["%d min ago"]:format(math.floor(d / 60)) end
	if d < 86400 then return L["%d h ago"]:format(math.floor(d / 3600)) end
	return L["%d d ago"]:format(math.floor(d / 86400))
end

--- The words for the mode the player is in: Simple mode's (no @kind, key:value or >>), else Advanced's.
function ns.Said(simple, advanced)
	if ns.Easy and ns.Easy.On and ns.Easy.On() then return simple end
	return advanced
end

--- This character's name as the game keys per-character settings (the AddOn list's on/off): on clients
--- where characters have a surname (RegionalUniqueNamesEnabled: "Plamen Warr"), UnitName gives the two
--- apart and only "Plamen" alone named another character (an old one called just Plamen), so the AddOn
--- list Terminal read and changed was that character's. Joined with the game's own separator, as Syndicator does.
function ns.CharacterName()
	local name, surname = UnitName("player")
	name, surname = ns.Str(name), ns.Str(surname)
	if not name then return nil end
	local sep = ns.SurnameSeparator()
	return (surname and sep) and (name .. sep .. surname) or name
end

--- What joins a name and its surname, where characters have one (RegionalUniqueNamesEnabled: the game's own
--- separator, " " when it doesn't say), else nil: UnitName's second answer is then the realm. (One copy: the AddOn
--- list's key, a group member's name and a whisper's target each had their own.)
function ns.SurnameSeparator()
	if not (_G.RegionalUniqueNamesEnabled and ns.Safe(_G.RegionalUniqueNamesEnabled)) then return nil end
	local C = _G.Constants and _G.Constants.CharacterNameSeparatorConsts
	return C and C.CHARACTERNAME_SURNAME_SEPARATOR or " "
end

--- The text cut to at most n bytes, never in the middle of a letter (UTF-8: a letter's bytes go whole or not at all).
function ns.Cut(s, n)
	s = tostring(s or "")
	if #s <= n then return s end
	local cut = s:sub(1, math.max(0, n))
	local lead = cut:match("()[\192-\255][\128-\191]*$")
	if lead then
		local b = cut:byte(lead)
		local need = (b >= 240 and 4) or (b >= 224 and 3) or 2
		if #cut - lead + 1 < need then cut = cut:sub(1, lead - 1) end
	end
	return cut
end

--- The game's way to send a chat line (C_ChatInfo's, else the old global), and whether chat is held back from addons
--- now (in combat in an instance). One copy: Share's lines and the games' scores to the guild had one each (review, 0.53.6).
function ns.ChatSender() return (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage end
function ns.ChatLocked()
	local lock = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
	return lock ~= nil and ns.Safe(lock) == true
end

--- ns.db[name] as a table (made when it isn't one), or nil before the saved variables are there. (Mail's and
--- MissingRecipes' copies: review, 0.53.6.)
function ns.DbTable(name)
	local db = ns.db
	if not db then return nil end
	if type(db[name]) ~= "table" then db[name] = {} end
	return db[name]
end

--- A frame that's there to use: shown, and not one the game forbids addons to touch.
function ns.Usable(f)
	return type(f) == "table" and not (f.IsForbidden and f:IsForbidden()) and f.IsVisible and f:IsVisible() or false
end

--- The windows on screen (UIParent's children) whose name holds `word` (plain), not Terminal's own and not one `skip`
--- says no to: { { frame, name } } in the game's order. (The quest log's and the talents' finders had one each: review,
--- 0.53.6.)
function ns.VisibleWindows(word, skip)
	local out = {}
	for _, f in ipairs({ UIParent:GetChildren() }) do
		local name = ns.FrameName(f)
		if name and name:find(word, 1, true) and not name:find("^Terminal") and not (skip and skip(name)) and ns.Usable(f) then
			out[#out + 1] = { f, name }
		end
	end
	return out
end

--- The game's call `method` of the table `ctable` (C_Reputation...), else the old global one (`global`, or `method`),
--- guarded: its results, or nothing. Looked up at each call (the skills' and reputations' wrappers: review, 0.53.6).
function ns.ApiCall(ctable, method, global, ...)
	local C = _G[ctable]
	local fn = type(C) == "table" and C[method] or nil
	return ns.Safe(fn or _G[global or method], ...)
end

-- Small helpers several lists had a copy of each (0.52.15: one each, here)

--- The clock's time in seconds (time()), or 0.
function ns.Now() return (_G.time and _G.time()) or 0 end

--- This character's GUID: the key its saved records are kept under.
function ns.PlayerGUID() return ns.Str(ns.Safe(_G.UnitGUID, "player")) end

local COPPER_PER_GOLD, COPPER_PER_SILVER = 10000, 100
local MONEY_ICON = {
	gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

--- 1234567 -> "1,234,567" (no %d: past 2^31 it overflows on this client).
function ns.Thousands(n)
	local s = ("%.0f"):format(math.floor(n))
	local sep = _G.LARGE_NUMBER_SEPERATOR
	if type(sep) ~= "string" or sep == "" then sep = "," end
	local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep:reverse()):reverse()
	return (out:gsub("^%" .. sep, ""))
end

--- Copper as gold, silver and copper: with coin icons (`plain` false), or "1,234g 5s 6c" for chat (and copied).
function ns.Money(copper, plain)
	copper = math.max(0, math.floor(tonumber(copper) or 0))
	local g = math.floor(copper / COPPER_PER_GOLD)
	local s = math.floor((copper % COPPER_PER_GOLD) / COPPER_PER_SILVER)
	local c = copper % COPPER_PER_SILVER
	local parts = {}
	if g > 0 then parts[#parts + 1] = plain and L["%sg"]:format(ns.Thousands(g)) or (ns.Thousands(g) .. MONEY_ICON.gold) end
	if s > 0 or (g > 0 and c > 0) then parts[#parts + 1] = plain and L["%ss"]:format(s) or (s .. MONEY_ICON.silver) end
	if c > 0 or #parts == 0 then parts[#parts + 1] = plain and L["%sc"]:format(c) or (c .. MONEY_ICON.copper) end
	return table.concat(parts, " ")
end


--- An item's link as the game makes it ("|cff...|Hitem:..|h[Name]|h|r"), or nil while the client doesn't have it (and
--- for a secret one). One copy: the tooltip's and the chat lines' (review, 0.53.6).
function ns.ItemLink(id)
	local get = C_Item and C_Item.GetItemInfo
	if not (get and id) then return nil end
	local ok, _, link = pcall(get, id)
	return ok and type(link) == "string" and not ns.Secret(link) and link:find("|H", 1, true) and link or nil
end

--- An item's name as its link says it ("|h[Linen Cloth]|h"), or nil (none, empty, secret).
function ns.LinkName(link)
	if not ns.Str(link) then return nil end
	return ns.Str(link:match("|h%[(.-)%]|h"))
end

-- Item names the game hasn't loaded yet (right after login an item's info can come without its name: a link reads "[]").
-- One wait per list (ns.NameWait(id)): `w.Name(id, link, given)` gives the name now, or asks for it (twice at most:
-- some never come) and gives nil; once every name asked for is in, or after ns.NAME_GIVE_UP s, the list is marked
-- changed (ns:Changed). The game's events are listened to only while names are awaited. (Review, 0.53.6: Items, Stored
-- and Durability each had a copy, and they had drifted: Durability never gave up, Stored missed ITEM_DATA_LOAD_RESULT.)
ns.NAME_GIVE_UP = 10
local NAME_EVENTS = { "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }
function ns.NameWait(listId)
	local w = { ids = {}, count = 0, asked = {}, gen = 0 } -- (gen: which wait the give-up timer belongs to)
	local frame = CreateFrame("Frame")
	w.frame = frame
	local function Listen(on)
		for _, ev in ipairs(NAME_EVENTS) do
			if on then pcall(frame.RegisterEvent, frame, ev) else pcall(frame.UnregisterEvent, frame, ev) end
		end
	end
	local function Done()
		for k in pairs(w.ids) do w.ids[k] = nil end
		w.count = 0
		w.gen = w.gen + 1 -- (a wait that ended early and a new one begun: the old one's timer does nothing)
		Listen(false)
		ns:Changed(listId)
	end
	--- Ask for an item's name: the list is made again once it's in.
	function w.Ask(id)
		local C = _G.C_Item
		if not id or w.ids[id] or (w.asked[id] or 0) >= 2 or not (C and C.RequestLoadItemDataByID) then return end
		w.asked[id] = (w.asked[id] or 0) + 1
		if w.count == 0 then
			Listen(true)
			local gen = w.gen
			C_Timer.After(ns.NAME_GIVE_UP, function() if w.gen == gen and w.count > 0 then Done() end end)
		end
		w.ids[id] = true
		w.count = w.count + 1
		pcall(C.RequestLoadItemDataByID, id)
		ns:Trace(("%s: waiting for the name of item %s"):format(listId, tostring(id)))
	end
	--- The name: `given`, else the link's, else the game's by id; else nil, and it's asked for.
	function w.Name(id, link, given)
		local name = ns.Str(given) or ns.LinkName(link)
		if name then return name end
		local C = _G.C_Item
		name = id and C and C.GetItemNameByID and ns.Str(ns.Safe(C.GetItemNameByID, id))
		if name then return name end
		w.Ask(id)
		return nil
	end
	frame:SetScript("OnEvent", function(_, _, id)
		if w.count == 0 then return end
		if id ~= nil then
			if not w.ids[id] then return end -- (someone else's item)
			w.ids[id] = nil
			w.count = w.count - 1
		else
			-- (a client that doesn't say which: whatever has a name now has arrived)
			local C = _G.C_Item
			for k in pairs(w.ids) do
				if C and C.GetItemNameByID and ns.Str(ns.Safe(C.GetItemNameByID, k)) then
					w.ids[k] = nil
					w.count = w.count - 1
				end
			end
		end
		if w.count <= 0 then Done() end
	end)
	return w
end
