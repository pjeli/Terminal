local ns = select(2, ...)

-- ">> channel": whatever result is selected goes to a chat channel instead of being opened.
--
--   copper bar >> party        the item's link to your party
--   @npc hogger >> guild       a map pin where Hogger stands
--   >> whisper Plamen          the selected recent pick, whispered
--
-- A ">>" standing on its own ends the search; the word after it is the channel. Enter (or a click)
-- has the game press the chat line (/p, /g...) from the secure macro button, as it runs your macros:
-- Terminal's own code never sends chat. What goes out: the row's link (items, spells, achievements,
-- recipes, quests), a map pin for NPCs, else its name. The game runs at most 255 characters of a macro.

local SH = {}
ns.Share = SH

local CHANNELS = {
	party = "party", p = "party", group = "party",
	guild = "guild", g = "guild",
	raid = "raid",
	officer = "officer", o = "officer",
	say = "say", s = "say",
	yell = "yell", y = "yell",
	instance = "instance", i = "instance", bg = "instance",
}
local COMMAND = { party = "/p", guild = "/g", raid = "/raid", officer = "/o", say = "/s", yell = "/y", instance = "/i" }
local WHISPER = { w = true, whisper = true, tell = true, t = true }
SH.NAMES = { "party", "guild", "raid", "say", "yell", "officer", "instance", "whisper" }

--- Does some channel name start with this word? (While it's being typed: not wrong yet.)
function SH.IsStart(word)
	local w = ns.Lower(word or "")
	for _, n in ipairs(SH.NAMES) do if n:sub(1, #w) == w then return true end end
	return w:match("^%d+$") ~= nil
end

--- The search text and what follows a standalone ">>" (nil when there's none): "copper >> party" -> "copper ", "party".
function SH.Split(text)
	if type(text) ~= "string" or not text:find(">>", 1, true) then return text, nil end
	local at
	for pos, w in text:gmatch("()(%S+)") do
		if w == ">>" then at = pos end -- (the last one)
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

--- What a row sends: its link, a map pin for an NPC, else its name.
function SH.Text(e)
	-- an NPC: a map pin where it stands (the waypoint Shift+Enter drops; a C API, fine from here)
	if e.npcID and ns.Integrations and ns.Integrations.NpcPinLink then
		local pin = ns.Integrations.NpcPinLink(e)
		if pin then return e.name .. " " .. pin end
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

--- The chat line for a row, or nil. Kept within what a macro runs (255 characters).
function SH.Macro(e, to)
	if not (to and to.cmd and e) then return nil end
	local text = SH.Text(e)
	if type(text) ~= "string" or text == "" then return nil end
	local line = to.cmd .. " " .. text
	if #line > (ns.Secure and ns.Secure.MACRO_MAX or 255) then line = to.cmd .. " " .. tostring(e.name) end
	return line
end
