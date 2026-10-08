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
function SH.Split(text)
	if type(text) ~= "string" or not text:find(">>", 1, true) then return text, nil end
	local at
	for pos, w in text:gmatch("()(%S+)") do
		if w:sub(1, 2) == ">>" then at = pos end -- (the last one)
	end
	if not at then return text, nil end
	return text:sub(1, at - 1), (text:sub(at + 2):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Where to send: { cmd = "/p", label = "party" }; { pending = true } while the channel is still to be
--- typed; { bad = word } for a word that isn't one.
function SH.Channel(rest)
	local w, more = (rest or ""):match("^(%S*)%s*(.-)%s*$")
	local lw = ns.Lower(w or "")
	if lw == "" then return { pending = true } end
	local ch = CHANNELS[lw]
	if ch then return { cmd = COMMAND[ch], label = ch } end
	if WHISPER[lw] then
		local who = (more or ""):match("^(%S+)")
		if not who then return { pending = true, label = "whisper" } end
		return { cmd = "/w " .. who, label = "whisper " .. who }
	end
	local n = tonumber(lw)
	if n and n >= 1 and n <= 20 then return { cmd = "/" .. n, label = "channel " .. n } end
	return { bad = w }
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a = pcall(fn, ...)
	if ok then return a end
end

local function IsLink(l) return type(l) == "string" and l:find("|H", 1, true) ~= nil end

local function ItemLink(id)
	local get = C_Item and C_Item.GetItemInfo
	if not (get and id) then return nil end
	local ok, _, link = pcall(get, id)
	return ok and IsLink(link) and link or nil
end

--- Where a loot row's item drops, from its detail ("Garr  Molten Core"): "dropped by Garr in Molten Core", "from
--- trash in Stratholme", "from Molten Core" (no boss named); nil for other rows.
function SH.LootSource(e)
	if not e or e.kind ~= "loot" or type(e.detail) ~= "string" then return nil end
	local d = ns.Plain(e.detail)
	local boss, inst = d:match("^(.-)%s%s+(.-)%s*$")
	if not boss then boss, inst = d:match("^%s*(.-)%s*$"), "" end
	if boss == "?" or boss == inst then boss = "" end
	if boss == "" and inst == "" then return nil end
	local where = inst ~= "" and (" in " .. inst) or ""
	if boss == "" then return "from " .. inst end
	if ns.Lower(boss):find("trash", 1, true) then return "from trash" .. where end
	return "dropped by " .. boss .. where
end

--- What a row sends: its link (a loot row's says where it drops, unless `bare`), a map pin for an NPC, else its name.
function SH.Text(e, bare)
	local text = SH.BaseText(e)
	local from = not bare and type(text) == "string" and text ~= "" and SH.LootSource(e)
	return from and (text .. " " .. from) or text
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
	local out = { { cmd = "/s", label = "Say in chat" } }
	local function Is(fn, ...) return type(fn) == "function" and Call(fn, ...) and true or false end
	local instance = _G.LE_PARTY_CATEGORY_INSTANCE
	local inInstance = instance and Is(_G.IsInGroup, instance)
	if Is(_G.IsInRaid) then
		out[#out + 1] = { cmd = "/raid", label = "Send to raid" }
	elseif Is(_G.IsInGroup) and not (inInstance and not Is(_G.IsInGroup, _G.LE_PARTY_CATEGORY_HOME)) then
		out[#out + 1] = { cmd = "/p", label = "Send to party" }
	end
	if inInstance then out[#out + 1] = { cmd = "/i", label = "Send to instance" } end
	if Is(_G.IsInGuild) then out[#out + 1] = { cmd = "/g", label = "Send to guild" } end
	if Is(_G.UnitIsPlayer, "target") and not Is(_G.UnitIsUnit, "target", "player") then
		local name = ns.Str(Call(_G.UnitName, "target"))
		out[#out + 1] = { cmd = "/w %t", label = "Whisper " .. (name or "your target") }
	end
	return out
end

--- What goes into the chat box for a row: "<context>: <text>" (Context), else the text.
function SH.Line(e, query)
	local text = SH.Text(e)
	if type(text) ~= "string" or text == "" then return nil end
	local ctx = SH.Context(query, e)
	return ctx and (ctx .. ": " .. text) or text
end

--- The chat line for a row, or nil. Kept within what a macro runs (255 characters): what the search said it is
--- comes first ("Nearby reagent vendor: Name [pin]"), dropped when the line would be too long.
function SH.Macro(e, to)
	if not (to and to.cmd and e) then return nil end
	local text = SH.Text(e)
	if type(text) ~= "string" or text == "" then return nil end
	local max = ns.Secure and ns.Secure.MACRO_MAX or 255
	local ctx = SH.Context(to.query, e)
	local line = to.cmd .. " " .. (ctx and (ctx .. ": ") or "") .. text
	if #line > max then line = to.cmd .. " " .. (e.generic and (tostring(e.name) .. " ") or "") .. text end
	if #line > max then line = to.cmd .. " " .. tostring(SH.Text(e, true)) end -- (a loot row: without where it drops)
	if #line > max then line = to.cmd .. " " .. tostring(e.name) end
	return line
end
