local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations

-- Spoken's lore (Spoken_Bosses, Spoken_Places, Spoken_Readables), read while those addons are installed, never copied
-- into Terminal: their texts come partly from warcraft.wiki.gg (CC BY-SA) and the books' from the game. Spoken's API.lua
-- says only what it defines on `Spoken` is a contract; the tables read here are its modules' data globals, not that, so
-- each is checked as it's read (a type check on every level, its functions called in a pcall) and anything not in the
-- shape expected is left out quietly (.debug log says so):
--
--   SpokenBosses.maps[instance map] = { { id, ids, key, [1] = English name, deDE = ..., ... } }   (Data/Bosses.lua)
--   SpokenBossStories[instance map][key] = "story" or { [1] = English, deDE = ... }               (Data/Stories.lua)
--   SpokenDungeons.dungeons[map] = { zone, [1] = name, deDE = ... }, .worldBosses[map] = { zone, bossZones }
--                                                                    (Spoken's Data/Dungeons.lua: instance names)
--   SpokenPlaces:GetLore(uiMapID) -> { name, short, full, source }; SpokenPlaces.Zones / .Subzones[uiMapID][key]
--                                                                    (the client's language only: Spoken_Places loads one)
--   SpokenReadablesData.books[id] = { title, pages = { page ids } }, .pages[id].text, .owners.item / .object[id] = book
--   SpokenReadablesPlaces.books[id] = { kind, type, zones (uiMapIDs), dungeons (instance maps), event, wide }
--
-- What it makes: @lore (boss stories, zones' and subzones' lore: Enter reads the whole text in Terminal's text window),
-- and every readable as a row of @book beside OneForAll's Library Books (OneForAll/Books.lua; @book is these alone
-- without OneForAll), read or not by the books you read in the game (db.lore, Apps/Extras.lua). The rows hold names,
-- places and ids only: the texts are looked up when a tooltip or the window wants them, the books' pages searched only
-- when a question asks ("books that mention stalvan"). Without Spoken: nothing here, @book as it was.

local SL = {}
ns.Spoken = SL
local Lower, Str, Safe = ns.Lower, ns.Str, ns.Safe
local SEP = ns.DETAIL_SEP
local LORE_COLOR, BOOK_COLOR = "ff9fd8c0", "ffd8b070"
SL.ICON_BOSS, SL.ICON_PLACE, SL.ICON_BOOK = "Interface\\Icons\\INV_Misc_Head_Dragon_01", "Interface\\Icons\\INV_Misc_Map_01",
	"Interface\\Icons\\INV_Misc_Book_11"
SL.SHORT = 300 -- (characters of a boss's story in its tooltip: its first sentences)

local function Tab(v) return type(v) == "table" and v or nil end
local function Text(v) return Str(v) end

--- A name or text in the client's language, else English: a string, or { [1] = English, deDE = ... }.
local function Localized(v)
	if type(v) == "string" then return Text(v) end
	if type(v) ~= "table" then return nil end
	return Text(rawget(v, ns.LOCALE)) or Text(rawget(v, 1))
end
SL.Localized = Localized

----------------------------------------------------------------------
-- Their data, checked
----------------------------------------------------------------------

function SL.BossMaps() local b = Tab(rawget(_G, "SpokenBosses")) return b and Tab(b.maps) end
function SL.Stories() return Tab(rawget(_G, "SpokenBossStories")) end
--- A boss's story, or nil.
function SL.Story(map, key)
	local s = SL.Stories()
	local m = s and Tab(s[map])
	return m and Localized(m[key]) or nil
end

local function Dungeons() local d = Tab(rawget(_G, "SpokenDungeons")) return d end

--- SpokenPlaces (Spoken_Places' namespace), when it has its lore tables.
function SL.Places()
	local p = Tab(rawget(_G, "SpokenPlaces"))
	if p and (Tab(rawget(p, "Zones")) or Tab(rawget(p, "Subzones"))) then return p end
	return nil
end
--- A zone's lore entry ({ name, short, full, source }): its own GetLore, else its table.
function SL.ZoneLore(map)
	local P = SL.Places()
	if not P then return nil end
	local e = type(P.GetLore) == "function" and Safe(P.GetLore, P, map) or nil
	if type(e) ~= "table" then
		local z = Tab(rawget(P, "Zones"))
		e = z and z[map]
	end
	return Tab(e)
end
function SL.SubzoneLore(map, key)
	local P = SL.Places()
	local s = P and Tab(rawget(P, "Subzones"))
	local z = s and Tab(s[map])
	return z and Tab(z[key]) or nil
end
-- an entry with words (Spoken lists places nobody has written of yet: `pending`, empty texts)
local function Written(e) return e and not e.pending and (Text(e.full) or Text(e.short)) ~= nil end

--- SpokenReadablesData, when its books and pages are tables.
function SL.Readables()
	local d = Tab(rawget(_G, "SpokenReadablesData"))
	return d and Tab(d.books) and Tab(d.pages) and d or nil
end
local function ReadablePlaces() local p = Tab(rawget(_G, "SpokenReadablesPlaces")) return p and Tab(p.books) end

--- An instance's name: Spoken's (the client's Map table, in this language), Terminal's list, else the game's.
local function InstanceName(map)
	local D = Dungeons()
	local n = Localized(D and Tab(D.dungeons) and D.dungeons[map])
	if n then return n end
	for _, inst in ipairs(I.INSTANCES or {}) do if inst[1] == map then return inst[2] end end
	return _G.GetRealZoneText and Str(Safe(_G.GetRealZoneText, map)) or nil
end
SL.InstanceName = InstanceName
local ZoneName = function(ui) return type(ui) == "number" and I.ZoneName and I.ZoneName(ui) or nil end

----------------------------------------------------------------------
-- @lore: a boss's story, a zone's or subzone's lore; Enter reads it whole
----------------------------------------------------------------------

--- A row's whole text and where it's from (a wiki page's address, else Spoken), or nil.
function SL.LoreText(e)
	if e.what == "boss" then return SL.Story(e.map, e.bkey), nil end
	local entry = e.what == "zone" and SL.ZoneLore(e.map) or SL.SubzoneLore(e.map, e.akey)
	if not Written(entry) then return nil end
	return Text(entry.full) or Text(entry.short), Text(entry.source)
end

--- Its first words, for the tooltip: a place's short text, a story's first sentences.
function SL.Short(e)
	if e.what ~= "boss" then
		local entry = e.what == "zone" and SL.ZoneLore(e.map) or SL.SubzoneLore(e.map, e.akey)
		local s = entry and (Text(entry.short) or Text(entry.full))
		if s then return s end
	end
	local text = SL.LoreText(e)
	if not text then return nil end
	text = text:match("^(.-)\n") or text
	if #text <= SL.SHORT then return text end
	local cut = ns.Cut(text, SL.SHORT)
	return cut:match("^(.*[%.!%?])%s") or cut
end

local function LoreTip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	t:AddLine(e.detail, 0.62, 0.62, 0.62)
	local s = SL.Short(e)
	if s then t:AddLine(s, 1, 1, 1, true) end
	t:AddLine(L["From %s"]:format("Spoken"), 0.5, 0.5, 0.5)
end

local function ShowLore(e)
	local text, source = SL.LoreText(e)
	if not text then return ns:Print(L["No page for %s."]:format(tostring(e.name))) end
	ns:ShowText(e.name .. (e.where and (SEP .. e.where) or ""), text .. "\n\n" .. L["From %s"]:format(source or "Spoken"))
end
SL.ShowLore = ShowLore

local LORE_PROTO = { tooltip = LoreTip, activate = ShowLore, actionVerb = L["read"], generic = false }
local LORE_LAZY = {
	icon = function(t) return t.what == "boss" and SL.ICON_BOSS or SL.ICON_PLACE end,
	detail = function(t)
		local what = t.what == "boss" and L["Boss"] or t.what == "zone" and L["Zone"] or nil
		if what and t.where then return what .. SEP .. t.where end
		return what or t.where or ""
	end,
}

--- The rows: every boss with a story, every zone and subzone with lore written, by name.
function SL.LoreRows(p)
	local meta = ns:CompactMeta(p, LORE_PROTO, LORE_LAZY)
	local out = {}
	local function Add(t) out[#out + 1] = setmetatable(t, meta) end
	local maps, stories = SL.BossMaps(), SL.Stories()
	local D = Dungeons()
	local world = D and Tab(D.worldBosses) or {}
	local bad = 0
	if maps and stories then
		local bossWord = Lower(L["Boss"])
		for map, bosses in pairs(maps) do
			local told = type(map) == "number" and Tab(bosses) and Tab(stories[map])
			if told then
				-- (a world boss's map is no instance: the zone it stands in)
				local wb = Tab(world[map])
				local where = not wb and InstanceName(map) or nil
				for _, b in ipairs(bosses) do
					local key = Tab(b) and Text(b.key)
					local name = key and Localized(b)
					if name and told[key] ~= nil then
						local at = where or (wb and ZoneName(Tab(wb.bossZones) and wb.bossZones[key] or wb.zone)) or nil
						Add({ name = name, key = "b:" .. map .. ":" .. key, what = "boss", map = map, bkey = key, where = at,
							_compact = true, _ltext = "boss story lore " .. bossWord .. " " .. Lower(at or "") })
					elseif not name then
						bad = bad + 1
					end
				end
			end
		end
	end
	local P = SL.Places()
	if P then
		local zoneWord = Lower(L["Zone"])
		local zones, subs = Tab(rawget(P, "Zones")) or {}, Tab(rawget(P, "Subzones")) or {}
		for map, entry in pairs(zones) do
			if type(map) == "number" and Written(Tab(entry)) then
				local name = ZoneName(map) or Text(entry.name)
				if name then
					Add({ name = name, key = "z:" .. map, what = "zone", map = map, _compact = true,
						_ltext = "zone place lore " .. zoneWord })
				end
			end
		end
		for map, areas in pairs(subs) do
			if type(map) == "number" and Tab(areas) then
				local zone = ZoneName(map) or Text(Tab(zones[map]) and zones[map].name)
				for key, entry in pairs(areas) do
					local name = type(key) == "string" and Written(Tab(entry)) and Text(entry.name)
					if name then
						Add({ name = name, key = "s:" .. map .. ":" .. key, what = "subzone", map = map, akey = key, where = zone,
							_compact = true, _ltext = "place lore " .. Lower(zone or "") })
					end
				end
			end
		end
	end
	if bad > 0 then ns:Trace(("spoken: %d bosses not in the shape expected, left out"):format(bad)) end
	table.sort(out, function(a, b) return a.name < b.name or (a.name == b.name and a.key < b.key) end)
	return out
end

function SL.HasLore() return (SL.BossMaps() and SL.Stories()) ~= nil or SL.Places() ~= nil end

----------------------------------------------------------------------
-- Readables: rows of @book. Read = in db.lore (the books you read in the game, by title)
----------------------------------------------------------------------

--- Have you read it in the game (its title among the books kept, Apps/Extras.lua)?
function SL.IsRead(e)
	local lore = ns.db and ns.db.lore -- (read or not is asked as a row is drawn: a book read since shows at once)
	return type(lore) == "table" and type(e.name) == "string" and lore[Lower(e.name)] ~= nil or false
end

--- A book's pages, as one text (nil without any).
function SL.PagesText(e)
	local d = SL.Readables()
	local book = d and Tab(d.books[e.bookID])
	local out = {}
	for _, pid in ipairs(book and Tab(book.pages) or {}) do
		local pg = Tab(d.pages[pid])
		local s = pg and Text(pg.text)
		if s then out[#out + 1] = s end
	end
	return #out > 0 and table.concat(out, "\n\n- - -\n\n") or nil
end

local function ShowBook(e)
	local text = SL.PagesText(e)
	if not text then return ns:Print(L["No page for %s."]:format(tostring(e.name))) end
	ns:ShowText(e.name .. (e.zone and (SEP .. e.zone) or ""), text .. "\n\n" .. L["From %s"]:format("Spoken"))
end
SL.ShowBook = ShowBook

local function ItemName(id)
	return C_Item and C_Item.GetItemNameByID and Str(Safe(C_Item.GetItemNameByID, id)) or L["item %s"]:format(id)
end
local function BookTip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	local read = SL.IsRead(e)
	t:AddLine(read and L["read"] or L["unread"], read and 0.4 or 1, 1, read and 0.4 or 1)
	if e.zone then t:AddLine(e.zone, 1, 1, 1, true) end
	if e.ownerItem then t:AddLine(L["Item"] .. ": " .. ItemName(e.ownerItem), 0.8, 0.8, 0.8) end
	local first = SL.PagesText(e)
	if first then t:AddLine(ns.Cut(first:match("^(.-)\n") or first, SL.SHORT), 0.8, 0.8, 0.8, true) end
	t:AddLine(L["From %s"]:format("Spoken"), 0.5, 0.5, 0.5)
end

local BOOK_PROTO = { icon = SL.ICON_BOOK, tooltip = BookTip, activate = ShowBook, actionVerb = L["read"], generic = false,
	readable = true }
local BOOK_LAZY = {
	isRead = function(t) return SL.IsRead(t) end,
	detail = function(t) return (SL.IsRead(t) and L["read"] or L["unread"]) .. (t.zone and (SEP .. t.zone) or "") end,
}

local bookRows -- (made once: a few hundred small rows; read or not is asked as they're drawn)
--- The readables as @book rows (the same rows every time), or an empty list without Spoken_Readables.
function SL.BookRows()
	if bookRows then return bookRows end
	local d = SL.Readables()
	if not d then return {} end
	local places = ReadablePlaces() or {}
	local owners = Tab(d.owners) or {}
	local items = {}
	for id, book in pairs(Tab(owners.item) or {}) do
		if type(id) == "number" and type(book) == "number" and not items[book] then items[book] = id end
	end
	local label = { id = "book", label = ns.TitleCase(L["Book"]), color = BOOK_COLOR }
	if ns.providers.book then label.color = ns.providers.book.color or BOOK_COLOR end
	local meta = ns:CompactMeta(label, BOOK_PROTO, BOOK_LAZY)
	local out, bad = {}, 0
	local holiday = L["Holiday"]
	for id, book in pairs(d.books) do
		local title = type(id) == "number" and Tab(book) and Text(book.title)
		if title and Tab(book.pages) then
			local at = Tab(places[id]) or {}
			local where = {}
			for _, ui in ipairs(Tab(at.zones) or {}) do where[#where + 1] = ZoneName(ui) end
			for _, map in ipairs(Tab(at.dungeons) or {}) do where[#where + 1] = InstanceName(map) end
			if Text(at.event) then where[#where + 1] = holiday end
			local zone = #where > 0 and table.concat(where, ", ") or nil
			out[#out + 1] = setmetatable({ name = title, key = "r" .. id, bookID = id, zone = zone, ownerItem = items[id],
				readable = true, _compact = true,
				_ltext = Lower(table.concat({ "book readable", Text(at.type) or "", Text(at.kind) or "", zone or "" }, " ")) }, meta)
		else
			bad = bad + 1
		end
	end
	if bad > 0 then ns:Trace(("spoken: %d readables not in the shape expected, left out"):format(bad)) end
	table.sort(out, function(a, b) return a.name < b.name or (a.name == b.name and a.bookID < b.bookID) end)
	for i, e in ipairs(out) do e.order = i end
	bookRows = out
	return out
end
function SL.HasBooks() return SL.Readables() ~= nil end
function SL.Forget() bookRows = nil end -- (tests; a new data shape)

--- The readables whose pages have every word (lowercase), each a view whose detail is the words around the first:
--- the pages are read only now, page by page, nothing kept but the last answer.
local lastMention
function SL.Mentions(words)
	local key = table.concat(words or {}, " ")
	if lastMention and lastMention.key == key and lastMention.rows == bookRows then return lastMention.out end
	local d = SL.Readables()
	local rows = SL.BookRows()
	local out = {}
	if d and #words > 0 then
		for _, e in ipairs(rows) do
			local book = Tab(d.books[e.bookID])
			local found, snippet = {}, nil
			for _, pid in ipairs(book and Tab(book.pages) or {}) do
				local pg = Tab(d.pages[pid])
				local s = pg and Text(pg.text)
				if s then
					local ls = Lower(s)
					for i, w in ipairs(words) do
						local at = not found[i] and ls:find(w, 1, true)
						if at then
							found[i] = true
							if not snippet and i == 1 then
								snippet = s:sub(math.max(1, at - 50), at + 90):gsub("^[\128-\191]+", ""):gsub("%s+", " ")
								snippet = (at > 51 and "..." or "") .. ns.Cut(snippet, 130)
							end
						end
					end
				end
			end
			local all = true
			for i = 1, #words do if not found[i] then all = false break end end
			if all then
				out[#out + 1] = setmetatable({ detail = snippet or e.detail, readable = true, _score = 1e6 - #out },
					{ __index = e })
			end
		end
	end
	lastMention = { key = key, rows = bookRows, out = out }
	return out
end

----------------------------------------------------------------------
-- At login: @lore, the readables in @book
----------------------------------------------------------------------

local function Setup()
	if SL.HasLore() and not ns.providers.lore then
		ns:RegisterProvider("lore", {
			label = L["Lore"], color = LORE_COLOR, aliases = { "lore", "story", "stories" },
			explicit = true, -- (a thousand names and places: only with @lore, Simple mode's Lore, or asked in words)
			lazy = true, idleDrop = 600, -- (freed after 10 minutes unused; made again when next wanted)
			collect = SL.LoreRows,
		})
	end
	if ns.Easy and ns.Easy.VERBS and not ns.Easy.VERBS.lore then ns.Easy.VERBS.lore = { L["read"] } end
	if SL.HasBooks() then
		local p = ns.providers.book
		if not p then
			-- (no OneForAll: @book is the readables alone)
			ns:RegisterProvider("book", {
				label = L["Book"], color = BOOK_COLOR, aliases = { "book", "books", "readable", "readables" },
				namesOnly = true, lazy = true, readablesOnly = true, -- (OneForAll/Books.lua: no Library Book question then)
				collect = SL.BookRows,
			})
		else
			-- (OneForAll's @book: its collect adds these, Books.lua; the readables' own words for it)
			local have = {}
			for _, a in ipairs(p.aliases) do have[a] = true end
			for _, a in ipairs({ "readable", "readables" }) do if not have[a] then p.aliases[#p.aliases + 1] = a end end
			ns:AliasesChanged()
			ns:Changed("book")
		end
	end
end
I._.SetupSpoken = Setup

--- .integrations' line, or nil without any of Spoken's lore.
function SL.Status()
	if not (SL.HasLore() or SL.HasBooks()) then return nil end
	local stories, places = 0, 0
	local lore = ns.providers.lore
	for _, e in ipairs(lore and ns:GetEntries(lore) or {}) do
		if e.what == "boss" then stories = stories + 1 else places = places + 1 end
	end
	return L["%d boss stories and %d places (@lore), %d books (@book)"]:format(stories, places, #SL.BookRows())
end

----------------------------------------------------------------------
-- "who is edwin vancleef", "lore of duskwood", "tell me about goldshire": @lore's rows by name (a search question:
-- its line is "@lore <name>")
----------------------------------------------------------------------

local LQ = {}
ns.LoreQ = LQ
-- what makes it this question, and the words around a name that aren't it
local CUE = { lore = true, story = true, stories = true, history = true, legend = true, tale = true, background = true }
local FILL = {}
for w in ([[who whos is was were are tell me us about of on the a an what whats behind for]]):gmatch("%S+") do FILL[w] = true end

local function NamesHave(p, words)
	for _, e in ipairs(ns:GetEntries(p)) do
		local n = rawget(e, "_lname") or Lower(e.name)
		local all = true
		for i = 1, #words do if not n:find(words[i], 1, true) then all = false break end end
		if all then return true end
	end
	return false
end

--- The question: { words (the name asked about) }, or nil when the line isn't one, or names nothing @lore has.
function LQ.Question(text)
	local p = ns.providers.lore
	if not p then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local w = {}
	for x in t:gmatch("%S+") do w[#w + 1] = x end
	-- "who is X", "whos X", "tell me about X", "lore of X", "X lore", "the story of X"
	local cue = (w[1] == "who" and (w[2] == "is" or w[2] == "was" or w[2] == "were" or w[2] == "are")) or w[1] == "whos"
		or (w[1] == "tell" and (w[2] == "me" or w[2] == "us") and (w[3] == "about" or w[3] == "of"))
	local rest = {}
	for _, x in ipairs(w) do
		if CUE[x] then cue = true elseif not FILL[x] then rest[#rest + 1] = x end
	end
	if not cue or #rest == 0 then return nil end
	if not NamesHave(p, rest) then return nil end
	return { words = rest }
end
function LQ.Line(q) return "@lore " .. table.concat(q.words, " ") .. " " end
function LQ.Footer() return L["Lore"] end

----------------------------------------------------------------------
-- "books that mention stalvan" (the pages searched, an answer of its own), "books in duskwood" (@book in:<place>)
----------------------------------------------------------------------

local LB = {}
ns.LoreBooks = LB
local BOOK = { book = true, books = true, readable = true, readables = true, letter = true, letters = true, note = true,
	notes = true }
local MENTION = { mention = true, mentions = true, mentioning = true, mentioned = true, contain = true, contains = true,
	containing = true, say = true, says = true, saying = true, about = true, with = true }
local BFILL = {}
for w in ([[the a an that which what whats any all is are do does where can i find show me list of my word words
	text name named]]):gmatch("%S+") do BFILL[w] = true end

local function ZoneHas(words)
	for _, e in ipairs(SL.BookRows()) do
		local t = rawget(e, "_ltext") or ""
		local all = true
		for i = 1, #words do if not t:find(words[i], 1, true) then all = false break end end
		if all then return true end
	end
	return false
end

--- The question: { mention = words } or { zone = words }, or nil.
function LB.Question(text)
	if not (ns.providers.book and SL.HasBooks()) then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local book, mention, place, rest = false, false, false, {}
	for x in t:gmatch("%S+") do
		if x == "library" then return nil -- (OneForAll's Library Books: their own question)
		elseif BOOK[x] then book = true
		elseif MENTION[x] then mention = true
		elseif (x == "in" or x == "from" or x == "at") and not mention then place = true
		elseif not BFILL[x] then rest[#rest + 1] = x end
	end
	if not book or #rest == 0 then return nil end
	if mention then return { mention = rest } end
	if place and ZoneHas(rest) then return { zone = rest } end
	return nil
end
function LB.Line(q)
	if not q.zone then return nil end -- (the pages: its own answer)
	return "@book in:\"" .. table.concat(q.zone, " ") .. "\" sort:list "
end
function LB.Answer(q)
	local said = table.concat(q.mention or {}, " ")
	local rows = SL.Mentions(q.mention or {})
	if #rows == 0 then return { ns.NoteRow(L["No book mentions %s"]:format(said)) }, L["Books that mention %s"]:format(said) end
	return rows, L["Books that mention %s"]:format(said)
end
