local ns = select(2, ...)

-- ">> channel": whatever result is selected goes to a chat channel instead of being opened.
--
--   copper bar >> party        the item's link to your party
--   @npc hogger >> guild       a map pin where Hogger stands
--   >> whisper Plamen          the selected recent pick, whispered
--
-- A ">>" standing on its own (or starting a word: ">>party") ends the search; the word after it is the
-- channel. With two, the last one counts. Enter (or a click)
-- has the game press the chat line (/p, /g...) from the secure macro button, as it runs your macros:
-- Terminal's own code never sends chat. What goes out: the row's link (items, spells, achievements,
-- recipes, quests), a map pin for NPCs, else its name. The game runs at most 255 characters of a macro.
--
-- ">>> channel" (0.44.2) sends every result at once instead: "mats for thorium belt >>> party",
-- "@loot lorgus jett >>> guild". One line says what they are ("Mats for Thorium Belt (3): 12x [Thorium Bar], ..."),
-- as many lines as it takes (SH.GROUP_LINES at most). A macro the game presses runs only 255 characters in all, so
-- these lines are sent by Terminal itself, inside the key press or click that asked (SH.SendAll). The right-click
-- menu has the same as "All N to party" (Simple mode too).

local SH = {}
ns.Share = SH

local CHANNELS = {
	party = "party", p = "party", group = "party",
	guild = "guild", g = "guild",
	raid = "raid", r = "raid",
	officer = "officer", o = "officer",
	say = "say", s = "say",
	yell = "yell", y = "yell",
	instance = "instance", i = "instance", bg = "instance",
}
local COMMAND = { party = "/p", guild = "/g", raid = "/raid", officer = "/o", say = "/s", yell = "/y", instance = "/i" }
local WHISPER = { w = true, whisper = true, tell = true, t = true }
-- (the game's chat types, for the lines Terminal sends itself: ">>>")
local CHAT_TYPE = { party = "PARTY", guild = "GUILD", raid = "RAID", officer = "OFFICER", say = "SAY", yell = "YELL",
	instance = "INSTANCE_CHAT" }
SH.CHAT_TYPE = CHAT_TYPE
SH.NAMES = { "party", "guild", "raid", "say", "yell", "officer", "instance", "whisper" }

--- Does some channel name start with this word? (While it's being typed: not wrong yet.) A number
--- only when it can still become a channel number (1-20, as Channel takes them).
function SH.IsStart(word)
	local w = ns.Lower(word or "")
	for _, n in ipairs(SH.NAMES) do if n:sub(1, #w) == w then return true end end
	return w:match("^[1-9]%d?$") ~= nil and tonumber(w) <= 20
end

--- The search text and what follows a ">>" standing alone or starting a word (nil when there's none):
--- "copper >> party" -> "copper ", "party"; "copper >>party" the same. The last ">>" is the one (a ">>" in
--- the search part before it stays a word of the search). "lvl:>>20" has none: it's inside a word.
--- A third result is true for ">>>" (every result, not only the selected one).
function SH.Split(text)
	if type(text) ~= "string" or not text:find(">>", 1, true) then return text, nil end
	local at, all
	for pos, w in text:gmatch("()(%S+)") do
		if w:sub(1, 2) == ">>" then at, all = pos, w:sub(3, 3) == ">" end -- (the last one)
	end
	if not at then return text, nil end
	return text:sub(1, at - 1), (text:sub(at + (all and 3 or 2)):gsub("^%s+", ""):gsub("%s+$", "")), all or nil
end

--- Where to send: { cmd = "/p", label = "party" }; { pending = true } while the channel is still to be
--- typed; { bad = word } for a word that isn't one.
function SH.Channel(rest)
	local w, more = (rest or ""):match("^(%S*)%s*(.-)%s*$")
	local lw = ns.Lower(w or "")
	if lw == "" then return { pending = true } end
	local ch = CHANNELS[lw]
	if ch then return { cmd = COMMAND[ch], label = ch, chat = CHAT_TYPE[ch] } end
	if WHISPER[lw] then
		local who = (more or ""):match("^(%S+)")
		if not who then return { pending = true, label = "whisper" } end
		return { cmd = "/w " .. who, label = "whisper " .. who, chat = "WHISPER", target = who }
	end
	local n = tonumber(lw)
	if n and n >= 1 and n <= 20 then return { cmd = "/" .. n, label = "channel " .. n, chat = "CHANNEL", target = n } end
	return { bad = w }
end

local Call = ns.Safe -- (every use keeps only the first result)

local function IsLink(l) return type(l) == "string" and l:find("|H", 1, true) ~= nil end

local function ItemLink(id)
	local get = C_Item and C_Item.GetItemInfo
	if not (get and id) then return nil end
	local ok, _, link = pcall(get, id)
	return ok and IsLink(link) and link or nil
end

--- Where a loot row's item drops, from its detail ("Garr  Molten Core"): "dropped by Garr in Molten Core", "from
--- trash in Stratholme", "from Molten Core" (no boss named); nil for other rows.
--- A loot row's boss and instance, from its detail ("Garr  Molten Core"): "Garr", "Molten Core"; "" for one not
--- named ("?"); nil for other rows.
function SH.LootWhere(e)
	if not e or e.kind ~= "loot" or type(e.detail) ~= "string" then return nil end
	local d = ns.Plain(e.detail)
	local boss, inst = d:match("^(.-)%s%s+(.-)%s*$")
	if not boss then boss, inst = d:match("^%s*(.-)%s*$"), "" end
	if boss == "?" or boss == inst then boss = "" end
	return boss, inst
end

function SH.LootSource(e)
	local boss, inst = SH.LootWhere(e)
	if not boss or (boss == "" and inst == "") then return nil end
	local where = inst ~= "" and (" in " .. inst) or ""
	if boss == "" then return "from " .. inst end
	if ns.Lower(boss):find("trash", 1, true) then return "from trash" .. where end
	return "dropped by " .. boss .. where
end

-- the base text with where a loot row's item drops after it, and what the row adds of its own (`shareExtra`: a
-- stored item's holders) within `room` characters when given
local function WithSource(e, text, room)
	if type(text) ~= "string" or text == "" then return text end
	local from = SH.LootSource(e)
	if from then text = text .. " " .. from end
	local f = e.shareExtra
	if type(f) == "function" then
		local ok, x = pcall(f, e, room and (room - #text) or nil)
		if ok and type(x) == "string" and x ~= "" then text = text .. x end
	end
	return text
end

--- What a row sends: its link (a loot row's says where it drops, unless `bare`), a map pin for an NPC, else its name.
function SH.Text(e, bare)
	local text = SH.BaseText(e)
	if bare then return text end
	return WithSource(e, text)
end

function SH.BaseText(e)
	-- an NPC: a map pin where it stands (the waypoint Shift+Enter drops; a C API, fine from here)
	if e.npcID and ns.Integrations and ns.Integrations.NpcPinLink then
		local pin = ns.Integrations.NpcPinLink(e)
		if pin then return e.name .. " " .. pin end
	end
	-- a spot of its own (an instance entrance, a mailbox): its name and a map pin there
	if e.ui and e.px and ns.Integrations and ns.Integrations.SpotPinLink then
		local pin = ns.Integrations.SpotPinLink(e)
		-- (a row named only for what it is, "Mailbox": the context says it, "Nearby mailbox: [pin]")
		if pin then return e.generic and pin or ((e.pinName or e.name) .. " " .. pin) end
	end
	-- (shareLink: a link only for sending, never shown in a tooltip: a profession's opens its window)
	local shared = Call(e.shareLink, e)
	-- (a shareLink may be text another addon reads as a link: Questie's "[Name (id)]")
	if type(shared) == "string" and shared ~= "" then return shared end
	local link = Call(e.getLink, e) or e.link
	if not IsLink(link) then
		local id = e.itemID or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
		link = id and ItemLink(id) or nil
	end
	if not IsLink(link) then
		local q = e.questID or e.qid
		local get = _G.GetQuestLink or (C_QuestLog and C_QuestLog.GetQuestLink)
		if q and get then
			local l = Call(get, q)
			if IsLink(l) then link = l end
		end
		-- the game links only quests in your log here: Questie's link otherwise
		if not IsLink(link) and q and ns.Integrations and ns.Integrations.QuestieQuestLink then
			local l = ns.Integrations.QuestieQuestLink(q)
			if type(l) == "string" and l ~= "" then return l end
		end
	end
	if IsLink(link) then return link end -- (a link carries its own name)
	return e.name
end

-- What an NPC search's filters say the NPC is ("@npc reagent is:vendor sort:nearest" -> "Nearby reagent vendor").
SH.ROLES = {
	vendor = "vendor", repair = "repair vendor", inn = "innkeeper", innkeeper = "innkeeper", bank = "banker",
	banker = "banker", flight = "flight master", flightmaster = "flight master", auctioneer = "auctioneer",
	stable = "stable master", stablemaster = "stable master", trainer = "trainer",
	questgiver = "quest giver", classtrainer = "class trainer", proftrainer = "profession trainer",
	battlemaster = "battlemaster", pvpvendor = "PvP vendor", pvp = "PvP NPC",
}
local MY_CLASS = { class = true, my = true, me = true, myclass = true }

local function Titled(s) return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)) end

--- Is the word a shorthand whose full name is in the name ("rfk" for Razorfen Kraul)? Then it says nothing more.
function SH.ShortIn(word, lname)
	local xs = ns.Shorthand and ns.Shorthand[word]
	if not xs then return false end
	for _, x in ipairs(xs) do if lname:find(x, 1, true) then return true end end
	return false
end

--- Words saying what an NPC sent to chat is, from what was searched: "Nearby reagent vendor", "Mining trainer in
--- Orgrimmar". The search's own words (those not in the NPC's name), its role and trainer filters, "Nearby" for
--- sort:nearest / near:, "in <place>" for in:. nil when the search says nothing more than the name.
function SH.Context(query, e)
	if type(query) ~= "string" or not (e and (e.npcID or (e.ui and e.px))) then return nil end
	local lname = ns.Lower(tostring(e.name or ""))
	local F = ns.Filters
	local nearby, words, roles, place = false, {}, {}, nil
	for w in query:gmatch("%S+") do
		local lw = ns.Lower(w)
		local key, val = lw:match("^(%a+):(.*)$")
		if lw:sub(1, 1) == "@" then
			-- (the kind: an NPC already)
		elseif F and F.SortOf and F.SortOf(lw) then
			nearby = true
		elseif key and F and F.IsKey and F.IsKey(key) then
			val = val:gsub("_", " ")
			if key == "near" or key == "within" or key == "dist" then
				nearby = true
			elseif key == "is" and SH.ROLES[val] then
				roles[#roles + 1] = SH.ROLES[val]
			elseif key == "trainer" then
				if MY_CLASS[val] then
					local cls = UnitClass and UnitClass("player")
					val = type(cls) == "string" and ns.Lower(cls) or "class"
				elseif val == "mine" then
					val = "mining"
				end
				roles[#roles + 1] = val .. " trainer"
			elseif key == "in" or key == "zone" or key == "from" or key == "where" then
				place = Titled(val)
			end
		elseif not lname:find(lw, 1, true) and not SH.ShortIn(lw, lname) then
			words[#words + 1] = lw
		end
	end
	local parts = {}
	if nearby then parts[#parts + 1] = "nearby" end
	if e.generic then parts[#parts + 1] = lname end -- (what it is: the line then carries only its pin)
	if nearby and e.what then parts[#parts + 1] = e.what end -- ("Nearby dungeon: Razorfen Kraul entrance [pin]")
	for _, w in ipairs(words) do parts[#parts + 1] = w end
	for _, r in ipairs(roles) do parts[#parts + 1] = r end
	if #parts == 0 and not place then return nil end
	local text = table.concat(parts, " ")
	if place then text = (text ~= "" and (text .. " in ") or "in ") .. place end
	return (text:gsub("^%l", string.upper))
end

--- The channels a row can go to from its right-click menu, those you're in: { cmd, label } (say always; party or
--- raid, instance, guild when you're in one; your target when it's another player: "/w %t", the game fills the name).
function SH.MenuChannels()
	local out = { { cmd = "/s", label = "Say in chat", chat = "SAY", short = "say" } }
	local function Is(fn, ...) return type(fn) == "function" and Call(fn, ...) and true or false end
	local instance = _G.LE_PARTY_CATEGORY_INSTANCE
	local inInstance = instance and Is(_G.IsInGroup, instance)
	if Is(_G.IsInRaid) then
		out[#out + 1] = { cmd = "/raid", label = "Send to raid", chat = "RAID", short = "raid" }
	elseif Is(_G.IsInGroup) and not (inInstance and not Is(_G.IsInGroup, _G.LE_PARTY_CATEGORY_HOME)) then
		out[#out + 1] = { cmd = "/p", label = "Send to party", chat = "PARTY", short = "party" }
	end
	if inInstance then out[#out + 1] = { cmd = "/i", label = "Send to instance", chat = "INSTANCE_CHAT", short = "instance" } end
	if Is(_G.IsInGuild) then out[#out + 1] = { cmd = "/g", label = "Send to guild", chat = "GUILD", short = "guild" } end
	if Is(_G.UnitIsPlayer, "target") and not Is(_G.UnitIsUnit, "target", "player") then
		local name = ns.Str(Call(_G.UnitName, "target"))
		out[#out + 1] = { cmd = "/w %t", label = "Whisper " .. (name or "your target") }
	end
	return out
end

--- What a chain's row is, said before it in chat ("mats for thorium belt": "Mats for Thorium Belt"), and its text
--- as the chain sees it: a reagent's count ("8x [Thorium Bar]"), a source's way ("sold by Name [pin]"). nil, text
--- for rows not from a chain.
SH.CHAIN = {
	mats = "Mats for %s", uses = "%s is used in", sources = "Where to get %s", -- (alts: the holders say it)
}
function SH.ChainText(e, text)
	local rel = e.pipeRel
	if not rel or type(text) ~= "string" or text == "" then return nil, text end
	if rel == "mats" and tonumber(e.need) then
		text = ("%dx %s"):format(e.need, text)
	elseif rel == "sources" and type(e.pipeHow) == "string" then
		text = e.pipeHow .. " " .. text
	end
	local from, fmt = e.pipeFrom, SH.CHAIN[rel]
	return (fmt and from) and fmt:format(from) or nil, text
end

--- What goes into the chat box for a row: "<context>: <text>" (a chain's, else Context), else the text.
function SH.Line(e, query)
	-- ("used in" rows from AtlasLoot are its crafting pages: no "dropped by Blacksmithing in Crafting")
	local ctx, text = SH.ChainText(e, SH.Text(e, e.pipeRel == "uses"))
	if type(text) ~= "string" or text == "" then return nil end
	ctx = ctx or SH.Context(query, e)
	return ctx and (ctx .. ": " .. text) or text
end

--- The chat line for a row, or nil. Kept within what a macro runs (255 characters): what the search said it is
--- comes first ("Nearby reagent vendor: Name [pin]"), dropped when the line would be too long.
function SH.Macro(e, to)
	if not (to and to.cmd and e) then return nil end
	local base = SH.BaseText(e) -- (worked out once: an NPC's sets your map pin to link it)
	local max = ns.Secure and ns.Secure.MACRO_MAX or 255
	local ctx, text = SH.ChainText(e, e.pipeRel == "uses" and base or WithSource(e, base, max - #to.cmd - 1))
	if type(text) ~= "string" or text == "" then return nil end
	ctx = ctx or SH.Context(to.query, e)
	local line = to.cmd .. " " .. (ctx and (ctx .. ": ") or "") .. text
	if #line > max then line = to.cmd .. " " .. (e.generic and (tostring(e.name) .. " ") or "") .. text end
	if #line > max then line = to.cmd .. " " .. tostring(base) end -- (a loot row: without where it drops)
	if #line > max then line = to.cmd .. " " .. tostring(e.name) end
	return line
end

----------------------------------------------------------------------
-- Every result at once (">>> party", the menu's "All N to party")
----------------------------------------------------------------------

SH.GROUP_LINES = 6 -- (chat lines at most; what doesn't fit is counted: "+5 more")
SH.LINE_MAX = 255

--- The rows worth sending: real results (no hint, help, category or completion rows), each once.
function SH.GroupRows(list)
	local out, seen = {}, {}
	for _, e in ipairs(list or {}) do
		if type(e) == "table" and not (e.noActivate or e.raw or e.completion or e.catId or e.syntaxRow) then
			local o = rawget(e, "pipeOf") or e
			local id = tostring(o.kind) .. ":" .. tostring(o.key or o.itemID or o.name)
			if not seen[id] then seen[id] = true; out[#out + 1] = e end
		end
	end
	return out
end

-- What a search's filters say the rows are ("@loot rfk type:weapon q:rare" -> "Rare weapons"): the noun from type: or
-- slot:, words before it from q: and is:boe, "upgrades" for is:upgrade, "with <stat>" and the levels after. nil when
-- the filters say nothing.
local MASS = { armor = true, cloth = true, leather = true, mail = true, plate = true, food = true, gear = true,
	ammo = true, jewelry = true, ["trade goods"] = true, junk = true, miscellaneous = true, ammunition = true }
local PLURAL = { staff = "staves", stave = "staves", knife = "knives", ["fist weapon"] = "fist weapons" }
local SLOT_NOUN = {
	head = { "helm", "helms" }, neck = { "necklace", "necklaces" }, shoulder = { "shoulder", "shoulders" },
	back = { "cloak", "cloaks" }, chest = { "chest piece", "chest pieces" }, wrist = { "bracer", "bracers" },
	hands = { "glove", "gloves" }, waist = { "belt", "belts" }, legs = { "legging", "leggings" },
	feet = { "boot", "boots" }, finger = { "ring", "rings" }, trinket = { "trinket", "trinkets" },
	["two-hand"] = { "two-hander", "two-handers" }, ["one-hand"] = { "one-hander", "one-handers" },
	["off hand"] = { "off-hand", "off-hands" }, ["main hand"] = { "main-hand weapon", "main-hand weapons" },
	shield = { "shield", "shields" }, ranged = { "ranged weapon", "ranged weapons" }, tabard = { "tabard", "tabards" },
	shirt = { "shirt", "shirts" },
}
local ARMOUR = { cloth = true, leather = true, mail = true, plate = true }
SH.QUALITY_WORDS = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary" }

local function Plural(w)
	if MASS[w] then return w end
	if PLURAL[w] then return PLURAL[w] end
	if w:match("[sxz]$") or w:match("[cs]h$") then return w .. "es" end
	if w:match("[^aeiou]y$") then return w:sub(1, -2) .. "ies" end
	return w .. "s"
end

local function Value(v) return (v:gsub("_", " ")) end

function SH.Describe(query)
	if type(query) ~= "string" then return nil end
	local types, slot, quality, stats, boe, upgrade, lvl, ilvl = {}, nil, nil, {}, false, false, nil, nil
	for w in query:gmatch("%S+") do
		local lw = ns.Lower(w)
		if lw:sub(1, 1) ~= "-" and lw:sub(1, 1) ~= "!" then
			for part in lw:gmatch("[^|&]+") do
				local key, val = part:match("^(%a+):(.+)$")
				if key == "type" then types[#types + 1] = Value(val)
				elseif key == "slot" then slot = Value(val)
				elseif key == "q" then
					local n, plus = val:match("^(%d)(%+?)$")
					local word, plus2 = val:match("^(%a+)(%+?)$")
					local q = n and SH.QUALITY_WORDS[tonumber(n)] or word
					if q then quality = q .. (((plus or plus2) == "+") and " or better" or "") end
				elseif key == "stat" or key == "stats" then
					local name = val:match("^([%a_]+)")
					if name then stats[#stats + 1] = Value(name) end
				elseif key == "is" and val == "boe" then boe = true
				elseif key == "is" and (val == "upgrade" or val == "upgrades") then upgrade = true
				elseif key == "lvl" or key == "level" then lvl = val
				elseif key == "ilvl" then ilvl = val
				end
			end
		end
	end
	local noun
	local sn = slot and SLOT_NOUN[slot]
	if #types == 1 and ARMOUR[types[1]] and slot then
		-- "plate boots"
		noun = types[1] .. " " .. (sn and (upgrade and sn[1] or sn[2]) or (slot .. (upgrade and "" or " gear")))
	elseif #types > 0 then
		local parts = {}
		for i, t in ipairs(types) do parts[i] = upgrade and t or Plural(t) end
		noun = table.concat(parts, upgrade and "/" or " and ")
	elseif slot then
		noun = sn and (upgrade and sn[1] or sn[2]) or (slot .. (upgrade and "" or " gear"))
	end
	if upgrade then noun = noun and (noun .. " upgrades") or "upgrades" end
	local before = {}
	if quality then before[#before + 1] = quality end
	if boe then before[#before + 1] = "BoE" end
	if not noun and #before == 0 and #stats == 0 and not lvl and not ilvl then return nil end
	noun = noun or "items"
	local text = table.concat(before, " ") .. (#before > 0 and " " or "") .. noun
	if #stats > 0 then text = text .. " with " .. table.concat(stats, " and ") end
	if lvl then text = text .. " (level " .. lvl .. ")" end
	if ilvl then text = text .. " (item level " .. ilvl .. ")" end
	return (text:gsub("^%l", string.upper))
end

--- What the rows are, said once before them: a chain's ("Mats for Thorium Belt"), the boss and place every loot row
--- shares ("Dropped by Lorgus Jett in Blackfathom Deeps"), the instance they all share ("Loot from Razorfen Kraul":
--- each then says only its boss), what the filters say they are ("Weapons from Razorfen Kraul"), else what the search
--- says of its NPCs ("Nearby innkeeper").
--- Second result: "source" when it's the whole loot source (each row's own then isn't repeated), "instance" when
--- only the instance.
function SH.GroupHeader(rows, query)
	local first = rows[1]
	if not first then return nil end
	local ctx = SH.ChainText(first, "x")
	if ctx then
		for _, e in ipairs(rows) do if e.pipeRel ~= first.pipeRel or e.pipeFrom ~= first.pipeFrom then ctx = nil break end end
		if ctx then return ctx end
	end
	local what = SH.Describe(query)
	local src = SH.LootSource(first)
	if src then
		for _, e in ipairs(rows) do if SH.LootSource(e) ~= src then src = nil break end end
		if src then return what and (what .. " " .. src) or (src:gsub("^%l", string.upper)), "source" end
		local _, inst = SH.LootWhere(first)
		for _, e in ipairs(rows) do
			local _, i = SH.LootWhere(e)
			if i ~= inst then inst = nil break end
		end
		if inst and inst ~= "" then return (what or "Loot") .. " from " .. inst, "instance" end
	end
	return SH.Context(query, first) or what
end

--- The chat lines for every row: "<header> (N): a, b, c" packed into lines of at most LINE_MAX characters, GROUP_LINES
--- at most; the rest counted on the last ("+5 more"). Each row as the chain or list says it: "12x [Thorium Bar]".
function SH.GroupLines(rows, query)
	rows = SH.GroupRows(rows)
	if #rows == 0 then return {} end
	local header, lootHeader = SH.GroupHeader(rows, query)
	local texts = {}
	for _, e in ipairs(rows) do
		local base = SH.BaseText(e)
		local t = (lootHeader or e.pipeRel == "uses") and base or WithSource(e, base, SH.LINE_MAX - 8)
		if lootHeader == "instance" and type(base) == "string" then
			-- (the instance is in the header: each says only who drops it)
			local boss = SH.LootWhere(e)
			if boss and boss ~= "" then
				t = base .. " (" .. (ns.Lower(boss):find("trash", 1, true) and "trash" or boss) .. ")"
			end
		end
		local _, chained = SH.ChainText(e, t)
		t = chained or t
		if type(t) == "string" and t ~= "" then
			if #t > SH.LINE_MAX then t = tostring(base) end
			if #t <= SH.LINE_MAX then texts[#texts + 1] = t end
		end
	end
	local lines, line = {}, header and (header .. " (" .. #texts .. "):") or nil
	local sent = 0
	for _, t in ipairs(texts) do
		local joined = line and (line .. (line:sub(-1) == ":" and " " or ", ") .. t) or t
		-- (the last line keeps room for "+N more")
		local max = SH.LINE_MAX - (#lines == SH.GROUP_LINES - 1 and 12 or 0)
		if #joined <= max then
			line = joined
		else
			if line then lines[#lines + 1] = line end
			if #lines >= SH.GROUP_LINES then line = nil break end
			line = t
		end
		sent = sent + 1
	end
	if line and #lines < SH.GROUP_LINES then lines[#lines + 1] = line end
	local left = #texts - sent
	if left > 0 and #lines > 0 then
		local more = " +" .. left .. " more"
		if #lines[#lines] + #more <= SH.LINE_MAX then lines[#lines] = lines[#lines] .. more end
	end
	return lines, #texts
end

--- The items among the rows the client hasn't loaded yet: sent now, they'd go as plain names (no link). Item ids.
function SH.Unloaded(rows)
	local cached = C_Item and C_Item.IsItemDataCachedByID
	local out = {}
	if not cached then return out end
	for _, e in ipairs(rows) do
		local o = rawget(e, "pipeOf") or e
		local id = tonumber(o.itemID or e.itemID)
		if id and Call(cached, id) == false then out[#out + 1] = id end
	end
	return out
end

-- (asked once each: the server answers in its own time; a fresh ask a minute later)
local asked = {}
SH.PREFETCH_MAX = 200

--- Has the client load every item among the rows (">>>" typed, the menu's "All" lines shown), so their links are
--- there by the time they're sent.
function SH.Prefetch(rows)
	local req = C_Item and C_Item.RequestLoadItemDataByID
	if not req then return 0 end
	local now, n = GetTime and GetTime() or 0, 0
	for _, id in ipairs(SH.Unloaded(SH.GroupRows(rows))) do
		if n >= SH.PREFETCH_MAX then break end
		if not asked[id] or now - asked[id] > 60 then
			asked[id] = now
			Call(req, id)
			n = n + 1
		end
	end
	return n
end

-- say, yell and numbered channels want a key press or click to send (outside instances): never sent later
local NEEDS_PRESS = { SAY = true, YELL = true, CHANNEL = true }
SH.LINK_WAIT, SH.LINK_STEP = 3, 0.25 -- (seconds waited for items to load before sending without their links)

local function SendLines(rows, to, query, send)
	local lines = SH.GroupLines(rows, query)
	if #lines == 0 then return nil, "Nothing to send." end
	local n = 0
	for _, l in ipairs(lines) do
		local ok = pcall(send, l, to.chat, nil, to.target)
		if not ok then break end
		n = n + 1
	end
	ns:Trace(("share: sent %d of %d lines to %s"):format(n, #lines, tostring(to.label or to.chat)))
	if n == 0 then return nil, "Couldn't send to " .. tostring(to.label or to.chat) .. "." end
	return n
end

--- Sends every row's line to the channel `to` ({ chat, target, label }): from Terminal's own code, inside the key
--- press or click that asked (say and yell want one). Items the client hasn't loaded would go without their links
--- (a whole instance's loot): they're asked for, and party, raid, guild, instance and whispers wait for them (up to
--- LINK_WAIT s) before sending. Returns how many lines went (true when they'll go in a moment), or nil and why not.
function SH.SendAll(rows, to, query)
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
	if not (to and to.chat and send) then return nil, "Say where to send them: >>> party, guild, raid, say, instance, whisper <name>" end
	local lock = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
	if lock and Call(lock) == true then return nil, "The game doesn't let addons send chat right now (in combat in an instance)." end
	rows = SH.GroupRows(rows) -- (kept: the list on screen changes while waiting)
	if #rows == 0 then return nil, "Nothing to send." end
	local missing = SH.Unloaded(rows)
	if #missing == 0 or NEEDS_PRESS[to.chat] or not (C_Timer and C_Timer.After) then
		if #missing > 0 then ns:Trace("share: " .. #missing .. " items not loaded yet go without links (" .. to.chat .. " can't wait)") end
		return SendLines(rows, to, query, send)
	end
	local req = C_Item and C_Item.RequestLoadItemDataByID
	for _, id in ipairs(missing) do if req then Call(req, id) end end
	ns:Trace("share: waiting for " .. #missing .. " items to load before sending")
	local waited = 0
	local function Try()
		waited = waited + SH.LINK_STEP
		local left = #SH.Unloaded(rows)
		if left > 0 and waited < SH.LINK_WAIT then C_Timer.After(SH.LINK_STEP, Try) return end
		if left > 0 then ns:Trace("share: " .. left .. " items still not loaded: sent without links") end
		local n, why = SendLines(rows, to, query, send)
		if not n then ns:Print(why) end
	end
	C_Timer.After(SH.LINK_STEP, Try)
	return true
end
