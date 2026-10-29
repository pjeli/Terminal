local ns = select(2, ...)
local L = ns.L
local Safe, Str, Num = ns.Safe, ns.Str, ns.Num

-- !t (0.68.4, the player's design: docs/ASK.md): someone in your guild or group who doesn't run Terminal asks it a
-- question ("!t nearest innkeeper") and one Terminal user's client answers in the same channel, in one line. Off until
-- switched on per channel (.ask guild on): the answer goes out under your name. World facts only (A.ALLOW), from the
-- asker's side: where they stand, their class and level, from your group or the guild roster (ns.Asker, read by
-- I.Here, the class trainer filter and the zone levels while the answer is searched). Whispers only from friends,
-- guildies and your group. A question in letters this client's language doesn't use is left unanswered.
-- Several Terminal users hear one question: each waits a random moment and claims it with a hidden addon message; the
-- first claim answers, the rest stay quiet (two at once: the lower GUID answers). Your own question is answered for
-- you in your chat, nothing sent. A.New(env) is one client over an `env` (the game's, or the tests' pretend guild).
local A = {}
ns.Ask = A

A.PREFIX = "TermAsk"
A.WAIT_MIN, A.WAIT_MAX = 0.3, 1.2 -- (s before claiming: a random moment, so one client is first)
A.TIE_WAIT = 0.8 -- (s after claiming before answering: another claim meanwhile, the lower GUID answers; longer than
-- a hidden message takes to reach the others, or two claims a moment apart both answered: 0.68.5, review)
A.ASKER_GAP = 10 -- (s between two answers to one asker)
A.SAME_GAP = 60 -- (s before the same question from the same asker is answered again)
A.CHANNEL_MAX = 6 -- (answers a minute in one channel at most)
A.SEND_GAP = 1 -- (s between two lines sent: one queue)
A.CLAIM_KEEP = 30 -- (s a claim is remembered)
A.BUSY_TRIES, A.BUSY_WAIT = 3, 2 -- (lists still loading: searched again this often, this much later)
A.STALE = 20 -- (s: a question older than this is dropped, not answered late)
A.LOG_MAX = 8
A.LINE_MAX = 255
A.QUESTION_MAX = 120

-- the lists an answer may come from: the world's, never yours (bags, bank, alts, mail, auctions, your quest log,
-- professions, friends' shared bags). A list added later is private until it's named here.
A.ALLOW = { npc = true, questie = true, loot = true, mailbox = true, forge = true, anvil = true, cookingfire = true,
	moonwell = true, dungeon = true, raid = true, flight = true, maps = true }
-- words asking what you've learned (your flight paths): taken out, the answer is the world's
A.YOURS = { learned = true, unlearned = true, known = true, unknown = true, missing = true }

-- the chat events heard: the setting that lets them be answered, and the chat type the answer goes to (`instance`:
-- never in a battleground, where the instance group is strangers; 0.68.6, the player's call)
A.CHANNELS = {
	CHAT_MSG_GUILD = { set = "guild", chat = "GUILD" },
	CHAT_MSG_PARTY = { set = "group", chat = "PARTY" }, CHAT_MSG_PARTY_LEADER = { set = "group", chat = "PARTY" },
	CHAT_MSG_RAID = { set = "group", chat = "RAID" }, CHAT_MSG_RAID_LEADER = { set = "group", chat = "RAID" },
	CHAT_MSG_INSTANCE_CHAT = { set = "group", chat = "INSTANCE_CHAT", instance = true },
	CHAT_MSG_INSTANCE_CHAT_LEADER = { set = "group", chat = "INSTANCE_CHAT", instance = true },
	CHAT_MSG_WHISPER = { set = "whisper", chat = "WHISPER" },
}
A.SETTINGS = { "guild", "group", "whisper" }
local SAID = { guild = L["guild"], group = L["group"], whisper = L["whisper"] }

----------------------------------------------------------------------
-- Reading a question
----------------------------------------------------------------------

--- The text as words: a link's name ("[Thunderfury]" -> "Thunderfury"), the game's other codes and "|" left out. (0.68.5,
--- review: a linked item was searched as its codes, and "nothing found for ..." echoed the question cut at 60 bytes,
--- half a link: a broken link in a line sent.)
function A.Clean(text)
	text = tostring(text or ""):gsub("|H.-|h%[?(.-)%]?|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return (text:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|", ""))
end

--- The question after the trigger ("!t nearest inn" -> "nearest inn"; "!t" alone -> "help"), or nil when the line
--- isn't one: !t or !terminal, any case, at the start, then a space. Links are read as their names (A.Clean).
function A.Question(text)
	if type(text) ~= "string" or ns.Secret(text) then return nil end
	local word, rest = A.Clean(text):match("^%s*!(%a+)(.*)$")
	if not word then return nil end
	word = word:lower()
	if word ~= "t" and word ~= "terminal" then return nil end
	if rest ~= "" and not rest:find("^%s") then return nil end
	rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
	if rest == "" then return "help" end
	if #rest > A.QUESTION_MAX then return nil end
	return rest
end

-- the letters each client language reads beside a-z (which every one does: names, numbers); a letter of any other
-- script: a question this client's Terminal can't read, left unanswered (the player's call)
A.SCRIPTS = { deDE = "latin", frFR = "latin", esES = "latin", esMX = "latin", itIT = "latin", ptBR = "latin",
	ruRU = "cyrillic", zhCN = "han", zhTW = "han", koKR = "hangul" }
local function ScriptOf(cp)
	if cp < 0x80 then return "ascii" end
	if cp == 0xD7 or cp == 0xF7 or cp < 0xC0 then return "mark" end
	if cp <= 0x24F then return "latin" end
	if cp >= 0x400 and cp <= 0x4FF then return "cyrillic" end
	if (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF) then return "han" end
	if (cp >= 0xAC00 and cp <= 0xD7AF) or (cp >= 0x1100 and cp <= 0x11FF) or (cp >= 0x3130 and cp <= 0x318F) then return "hangul" end
	if (cp >= 0x2000 and cp <= 0x206F) or (cp >= 0x3000 and cp <= 0x303F) or (cp >= 0xFF00 and cp <= 0xFFEF) then return "mark" end
	return "other"
end

--- Is every letter of the text one this client's language (locale) reads?
function A.InLocale(text, locale)
	local own = A.SCRIPTS[locale or "enUS"]
	local i, n = 1, #text
	while i <= n do
		local c = text:byte(i)
		local len = (c >= 0xF0 and 4) or (c >= 0xE0 and 3) or (c >= 0xC0 and 2) or 1
		local cp = c
		local b1, b2 = (text:byte(i + 1) or 0x80) % 0x40, (text:byte(i + 2) or 0x80) % 0x40
		if len == 2 then cp = (c % 0x20) * 0x40 + b1
		elseif len == 3 then cp = (c % 0x10) * 0x1000 + b1 * 0x40 + b2
		elseif len == 4 then cp = 0x10000 end -- (emoji and the like: other)
		local s = ScriptOf(cp)
		if s ~= "ascii" and s ~= "mark" and s ~= own then return false end
		i = i + len
	end
	return true
end

-- (a question's id, as every client works it out: who asked (their GUID, the same on every client; else their name)
-- and what, lowercase)
local function Id(sender, q)
	local s = ns.Lower(tostring(sender or "")) .. "\n" .. ns.Lower(tostring(q or ""))
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
	return ("%x"):format(h)
end
A.Id = Id

----------------------------------------------------------------------
-- Who asked
----------------------------------------------------------------------

local function Ambig(name)
	local s = type(_G.Ambiguate) == "function" and Str(Safe(_G.Ambiguate, name, "none"))
	return s or name
end
local function SameName(a, b)
	if not (a and b) then return false end
	return ns.Norm(a) == ns.Norm(b) or ns.Norm(Ambig(a)) == ns.Norm(Ambig(b))
end
A.SameName = SameName

-- zone name (lowercase) -> uiMap, from Terminal's zone list (made once)
local zoneMaps
local function ZoneMap(zone)
	if not zone then return nil end
	if not zoneMaps then
		zoneMaps = {}
		local Z = ns.Zones
		for _, z in ipairs(Z and Z.LIST or {}) do
			local info = C_Map and C_Map.GetMapInfo and Safe(C_Map.GetMapInfo, z[1])
			local name = type(info) == "table" and Str(info.name)
			if name then zoneMaps[ns.Lower(name)] = z[1] end
		end
	end
	return zoneMaps[ns.Lower(zone)]
end

-- a class name in the client's language -> its token (MAGE): a friend's class is given only so
local function ClassToken(shown)
	if not shown then return nil end
	for _, t in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
		if type(t) == "table" then
			for token, name in pairs(t) do if name == shown then return token end end
		end
	end
	return nil
end

--- Who asked, as your group, the guild roster or your friend list has them: { name, guid, level, class (the token:
--- MAGE), zone, here (where they stand, world yards: in your group, outdoors), near (here is them, not their zone's
--- middle), trusted (one of yours: a whisper is answered) }, or nil when they're none of those.
function A.Asker(sender, guid)
	local I, GR = ns.Integrations, ns.Group
	local who
	if GR and GR.Units then
		for _, u in ipairs(GR.Units()) do
			local g = Str(Safe(UnitGUID, u))
			if (guid and g == guid) or (not guid and SameName(GR.NameOf and GR.NameOf(u), sender)) then
				local _, class = Safe(UnitClass, u)
				local here = I and I.UnitSpot and I.UnitSpot(u)
				who = { name = Ambig(sender), guid = g, unit = u, level = Num(Safe(UnitLevel, u)), class = Str(class),
					here = here, near = here ~= nil, trusted = true }
				break
			end
		end
	end
	if Safe(_G.IsInGuild) and _G.GetGuildRosterInfo then
		-- (the name before the realm first: the whole comparison only for those, not for each of a thousand members;
		-- 0.68.5, review)
		local short = ns.Lower(tostring(sender or ""):match("^[^-]*"))
		for i = 1, Num(Safe(_G.GetNumGuildMembers)) or 0 do
			local n, _, _, level, _, zone, _, _, _, _, class, _, _, _, _, _, g = Safe(_G.GetGuildRosterInfo, i)
			n, g = Str(n), Str(g)
			if (guid and g == guid) or (n and ns.Lower(n:match("^[^-]*")) == short and SameName(n, sender)) then
				who = who or { name = Ambig(sender), guid = g, level = Num(level), class = Str(class), trusted = true }
				who.zone = who.zone or Str(zone)
				break
			end
		end
	end
	if not who then
		local FL = C_FriendList
		for i = 1, (FL and FL.GetNumFriends and Num(Safe(FL.GetNumFriends)) or 0) do
			local f = Safe(FL.GetFriendInfoByIndex, i)
			if type(f) == "table" and ((guid and Str(f.guid) == guid) or SameName(Str(f.name), sender)) then
				who = { name = Ambig(sender), guid = Str(f.guid), level = Num(f.level), class = ClassToken(Str(f.className)),
					zone = Str(f.area), trusted = true }
				break
			end
		end
	end
	-- not grouped, or inside: the middle of their zone stands for where they are ("nearest" in their zone)
	if who and not who.here and who.zone and I and I.MapSpot then
		local ui = ZoneMap(who.zone)
		who.here = ui and I.MapSpot(ui, 0.5, 0.5) or nil
	end
	return who
end

----------------------------------------------------------------------
-- The answer
----------------------------------------------------------------------

-- the search's state a question's own search starts without (read as nil until it sets them; the terminal's,
-- through __index, otherwise: its category, its last scan to narrow from)
A.FRESH = { "aggregate", "place", "category", "categoryAuto", "action", "sendTo", "overviewWinner", "lastExtra", "lastScan",
	"lastFzf", "lastOverview", "lastSearchNarrowed", "typedPicks", "showRecent", "showField", "histSearch", "fzf",
	"pipeTrail", "args", "searchedText", "whyQ", "secondLook", "ungrouped", "dataRetry", "noPosition",
	-- (what a search clears as it starts, Scan.ResetFlags: cleared in the view, read through to the terminal's: its last
	-- search's "close spellings only" made the answer's overview relaxed; 0.68.5, review)
	"closeSpellings", "softRelaxed", "linkedGuess", "linked", "answerNote", "weightsNote", "flightNote", "missingNote",
	"calcAnswered" }
local FRESH = {}
for _, k in ipairs(A.FRESH) do FRESH[k] = true end
local VIEW = { __index = function(_, k) if not FRESH[k] then return ns.UI[k] end end }
local function NoRetry() end

-- the search's rows from the world's lists, real results only
local function Allowed(res)
	local out = {}
	for _, e in ipairs(type(res) == "table" and res or {}) do
		if A.ALLOW[e.kind] then out[#out + 1] = e end
	end
	local SH = ns.Share
	return SH and SH.GroupRows and SH.GroupRows(out) or out
end

-- one search of the text in its own view of the terminal (a category picked, or none)
local function OneSearch(text, category)
	local view = setmetatable({ results = {}, RetryWhenLoaded = NoRetry, category = category }, VIEW)
	local ok, res = pcall(ns.UI.Search, view, text)
	if not ok then ns:Trace("ask: the search failed: " .. tostring(res)) return {} end
	return type(res) == "table" and res or {}
end

-- (does a Simple-mode category hold one of the world's lists?)
local function WorldCategory(id)
	local cat = ns.Easy and ns.Easy.BY_ID and ns.Easy.BY_ID[id]
	for _, k in ipairs(cat and cat.kinds or {}) do if A.ALLOW[k] then return true end end
	return false
end

--- The rows Terminal finds for a question from the asker's side (ns.Asker while it searches, in Simple mode, the
--- terminal's own search left as it was): only the world's (A.ALLOW), real results. Found in several categories (Simple
--- mode lists them to pick from: "hogger"), the world's are opened in the order shown until one has rows. Second: a
--- list it reads is still loading (asked again later).
function A.Rows(question, asker)
	local UI, E = ns.UI, ns.Easy
	if not (UI and UI.Search) then return {}, false end
	local words = {}
	for w in tostring(question):gmatch("%S+") do if not A.YOURS[ns.Lower(w)] then words[#words + 1] = w end end
	local text = table.concat(words, " ")
	local F = ns.Filters
	local tempWas, flightWas, askerWas = E and E.tempSimple, UI.flightNote, ns.Asker
	-- (a search clears them as it starts: the terminal's own search waiting on items to load would be forgotten)
	local loadingWas, fitWas = F and F.loading, F and F.fitMade
	ns.Asker = { here = asker and asker.here or false, class = asker and asker.class, level = asker and asker.level }
	if E then E.tempSimple = true end
	-- (whatever happens in it, you're you again after: an error left in would have measured your "nearest" from Bob)
	local ok, out = pcall(function()
		local res = OneSearch(text)
		local found = Allowed(res)
		if #found == 0 then
			for _, e in ipairs(res) do
				if e.catId and WorldCategory(e.catId) then
					found = Allowed(OneSearch(text, e.catId))
					if #found > 0 then break end
				end
			end
		end
		return found
	end)
	ns.Asker = askerWas
	if E then E.tempSimple = tempWas end
	UI.flightNote = flightWas
	if F then F.loading, F.fitMade = loadingWas, fitWas end
	if not ok then ns:Trace("ask: " .. tostring(out)) out = {} end
	local busy = false
	if #out == 0 then
		for kind in pairs(A.ALLOW) do
			local p = ns.providers[kind]
			if p and type(p.busy) == "function" then
				local okB, b = pcall(p.busy, p)
				if okB and b then busy = true end
			end
		end
	end
	return out, busy
end

-- an NPC's or a spot's text sets your map pin to link it: your own pin is put back after
local function KeepingWaypoint(f, ...)
	local M, ST = C_Map, C_SuperTrack
	local had = M and M.GetUserWaypoint and Safe(M.GetUserWaypoint)
	local tracked = ST and ST.IsSuperTrackingUserWaypoint and Safe(ST.IsSuperTrackingUserWaypoint)
	local ok, a, b = pcall(f, ...)
	if M then
		if had and M.SetUserWaypoint then Safe(M.SetUserWaypoint, had)
		elseif M.ClearUserWaypoint then Safe(M.ClearUserWaypoint) end
	end
	if ST and ST.SetSuperTrackedUserWaypoint and type(tracked) == "boolean" then Safe(ST.SetSuperTrackedUserWaypoint, tracked) end
	if not ok then ns:Trace("ask: " .. tostring(a)) return nil end
	return a, b
end

local function Head(asker) return L["Terminal (%s): %s"]:format(tostring(asker and asker.name or "?"), "") end

--- The line to send for a question (`asker` from A.Asker), or nil; second: nil because a list is still loading.
function A.AnswerLine(question, asker)
	local head = Head(asker)
	if ns.Lower(question) == "help" then
		return head .. L["ask me: !t nearest innkeeper, !t where is hogger, !t what drops thunderfury"]
	end
	local rows, busy = A.Rows(question, asker)
	if #rows == 0 then return nil, busy end
	local SH = ns.Share
	local lines = KeepingWaypoint(SH.GroupLines, rows, question, 1, A.LINE_MAX - #head)
	if type(lines) ~= "table" or not lines[1] then return nil end
	return head .. lines[1]
end

--- The line for a question nothing answered.
function A.NothingLine(question, asker)
	return Head(asker) .. L["nothing found for \"%s\" (!t help)"]:format(ns.Cut and ns.Cut(question, 60) or question)
end

----------------------------------------------------------------------
-- One client: hearing, claiming, answering
----------------------------------------------------------------------

local Inst = {}
Inst.__index = Inst

--- A client over `env`: me() (your GUID), now(), after(s, f), random() (0-1), send(text, chat, target),
--- addon(msg, chat, target), print(line), locked(), combat(), setting(name), asker(sender, guid), answer(q, asker)
--- -> line, busy; locale(); battleground() (in one: its instance chat isn't answered).
function A.New(env)
	return setmetatable({ env = env, claims = {}, rivals = {}, lastAsker = {}, lastSame = {}, sent = {}, queue = {},
		told = {}, log = {} }, Inst)
end

-- what happened to a question, for .ask (the last few) and the trace
local REASON = {
	answered = L["answered"], off = L["not switched on"], stranger = L["not a friend, guildie or group member"],
	language = L["another language"], combat = L["you were in combat"], lockdown = L["chat was locked"],
	soon = L["asked again too soon"], again = L["the same question again"], full = L["too many answers this minute"],
	claimed = L["another Terminal answered"], late = L["too late"], yours = L["your own: answered for you"],
	quiet = L["nothing to say"], battleground = L["battleground chat: never answered"],
}
function Inst:Log(who, q, why)
	local log = self.log
	table.insert(log, 1, { who = who, q = q, why = why })
	for i = #log, A.LOG_MAX + 1, -1 do log[i] = nil end
	ns:Trace(("ask: %s asked %q: %s"):format(tostring(who), tostring(q), why))
end

-- (claims older than CLAIM_KEEP forgotten, and askers and questions past their gaps: a long session's guild chat
-- isn't kept)
function Inst:Prune(now)
	for id, c in pairs(self.claims) do
		if now - c.at > A.CLAIM_KEEP then self.claims[id], self.rivals[id] = nil, nil end
	end
	for k, t in pairs(self.lastAsker) do if now - t >= A.ASKER_GAP then self.lastAsker[k] = nil end end
	for k, t in pairs(self.lastSame) do if now - t >= A.SAME_GAP then self.lastSame[k] = nil end end
end

-- (an answer in a channel, yours or another Terminal's: counted for its answers a minute)
function Inst:Spent(chat, now)
	local t = self.sent[chat] or {}
	self.sent[chat] = t
	t[#t + 1] = now
end

-- (another Terminal has it: what it answers counts here too, or the next question went to whoever hadn't answered yet)
function Inst:Claimed(job)
	self:Spent(job.chat, self.env.now())
	self:Log(job.sender, job.q, "claimed")
end

-- (can this client answer it now? Asked before claiming as well: a claim it then couldn't answer silenced the rest)
function Inst:Able(job)
	local env = self.env
	if not env.setting(job.set) then return "off" end
	if env.locked() then return "lockdown" end
	if env.combat() then return "combat" end
	return nil
end

function Inst:ChannelFull(chat, now)
	local t = self.sent[chat] or {}
	self.sent[chat] = t
	for i = #t, 1, -1 do if now - t[i] > 60 then table.remove(t, i) end end
	return #t >= A.CHANNEL_MAX
end

function Inst:Pump()
	local item = table.remove(self.queue, 1)
	if not item then self.sending = nil return end
	self.sending = true
	if not self.env.locked() then
		local ok, err = pcall(self.env.send, item[1], item[2], item[3])
		if not ok then ns:Trace("ask: couldn't send: " .. tostring(err)) end
	end
	self.env.after(A.SEND_GAP, function() self:Pump() end)
end

function Inst:Queue(line, chat, target)
	self.queue[#self.queue + 1] = { line, chat, target }
	if not self.sending then self:Pump() end
end

--- Answers a question (job: { id, q, asker, chat, target, sender, asked }): the line, or that nothing was found; a
--- list still loading: asked again a little later.
function Inst:Reply(job, tries)
	local env = self.env
	local why = self:Able(job)
	if why then self:Log(job.sender, job.q, why) return end
	if env.now() - job.asked > A.STALE then self:Log(job.sender, job.q, "late") return end
	-- (counted again: several questions heard at once were each under the limit then)
	if not tries and self:ChannelFull(job.chat, env.now()) then self:Log(job.sender, job.q, "full") return end
	local ok, line, busy = pcall(env.answer, job.q, job.asker)
	if not ok then ns:Trace("ask: " .. tostring(line)) line, busy = nil, false end
	if not line and busy and (tries or 0) < A.BUSY_TRIES then
		env.after(A.BUSY_WAIT, function() self:Reply(job, (tries or 0) + 1) end)
		return
	end
	line = line or A.NothingLine(job.q, job.asker)
	self:Spent(job.chat, env.now())
	self:Queue(line, job.chat, job.target)
	self:Log(job.sender, job.q, "answered")
end

--- A chat line heard (event: CHAT_MSG_GUILD...; text, its sender's name and GUID).
function Inst:OnChat(event, text, sender, guid)
	local ch = A.CHANNELS[event]
	if not ch then return end
	local env = self.env
	if ns.Secret(text) or ns.Secret(sender) then return end -- (in chat lockdown: unreadable)
	local q = A.Question(text)
	if not q then return end
	sender, guid = Str(sender), Str(guid)
	if not sender then return end
	if env.locked() then self:Log(sender, q, "lockdown") return end
	local now = env.now()
	self:Prune(now)
	local id = Id(guid or sender, q)
	local me = env.me()
	if guid and guid == me then
		-- your own question: answered for you in your chat, nothing sent; claimed at once, so the others stay quiet
		if ch.chat == "WHISPER" then return end
		self.claims[id] = { guid = me, at = now, mine = true }
		pcall(env.addon, "c:" .. id .. ":" .. me, ch.chat)
		local who = env.asker(sender, guid) or { name = Ambig(sender) }
		local ok, line, busy = pcall(env.answer, q, who)
		if ok and not line and busy then line = L["Still loading what it needs: try again in a moment."] end
		env.print(ok and line or A.NothingLine(q, who))
		self:Log(sender, q, "yours")
		return
	end
	-- (a battleground's chat: strangers, never answered, nor told about; your premade party's is still your group's)
	if ch.instance and env.battleground and env.battleground() then self:Log(sender, q, "battleground") return end
	if not env.setting(ch.set) then
		if not self.told[ch.set] then
			self.told[ch.set] = true
			env.print(L["%s asked Terminal something in %s chat. .ask %s on lets Terminal answer for you."]:format(Ambig(sender),
				SAID[ch.set], ch.set))
		end
		self:Log(sender, q, "off")
		return
	end
	-- (the cheap tests first: the asker is looked for in the guild roster only for a question that may be answered)
	if not A.InLocale(q, env.locale()) then self:Log(sender, q, "language") return end
	if env.combat() then self:Log(sender, q, "combat") return end
	local key = ns.Lower(sender)
	local last = self.lastAsker[key]
	if last and now - last < A.ASKER_GAP then self:Log(sender, q, "soon") return end
	if self.lastSame[id] and now - self.lastSame[id] < A.SAME_GAP then self:Log(sender, q, "again") return end
	if self:ChannelFull(ch.chat, now) then self:Log(sender, q, "full") return end
	local asker = env.asker(sender, guid)
	if ch.chat == "WHISPER" and not (asker and asker.trusted) then self:Log(sender, q, "stranger") return end
	-- (counted when heard, whoever answers it: a second question before the first's answer, or after another
	-- Terminal's, waits its turn as well; 0.68.5, review)
	self.lastAsker[key], self.lastSame[id] = now, now
	local job = { id = id, q = q, asker = asker or { name = Ambig(sender) }, chat = ch.chat, set = ch.set, sender = sender,
		asked = now, target = ch.chat == "WHISPER" and sender or nil }
	if ch.chat == "WHISPER" then self:Reply(job) return end -- (only you were asked: no claiming)
	if self.claims[id] then self:Claimed(job) return end
	env.after(A.WAIT_MIN + env.random() * (A.WAIT_MAX - A.WAIT_MIN), function()
		if self.claims[id] then self:Claimed(job) return end
		local why = self:Able(job)
		if why then self:Log(sender, q, why) return end
		self.claims[id] = { guid = me, at = env.now(), mine = true }
		self.rivals[id] = {}
		pcall(env.addon, "c:" .. id .. ":" .. tostring(me), ch.chat)
		env.after(A.TIE_WAIT, function()
			for _, g in ipairs(self.rivals[id] or {}) do
				if tostring(g) < tostring(me) then self:Claimed(job) return end
			end
			self:Reply(job)
		end)
	end)
end

--- A hidden addon message heard: another Terminal's claim ("c:<id>:<guid>").
function Inst:OnAddon(prefix, msg)
	if prefix ~= A.PREFIX or type(msg) ~= "string" then return end
	local id, guid = msg:match("^c:(%x+):(.+)$")
	if not id or guid == self.env.me() then return end
	local c = self.claims[id]
	if c and c.mine then
		local r = self.rivals[id]
		if r then r[#r + 1] = guid end
	elseif not c then
		self.claims[id] = { guid = guid, at = self.env.now() }
	end
end

----------------------------------------------------------------------
-- The game's client
----------------------------------------------------------------------

--- Is answering in this channel switched on (db.ask.guild...)? Off until the player says so.
function A.On(name)
	local a = ns.db and rawget(ns.db, "ask")
	return type(a) == "table" and a[name] == true
end

local function ChatType(chat)
	local SH = ns.Share
	return SH and SH.ChatType and SH.ChatType(chat) or chat
end

A.GAME = {
	me = function() return Str(Safe(UnitGUID, "player")) end,
	now = function() return GetTime() end,
	after = function(s, f) C_Timer.After(s, f) end,
	random = function() return math.random() end,
	send = function(text, chat, target)
		local send = ns.ChatSender()
		if send then send(text, ChatType(chat), nil, target) end
	end,
	addon = function(msg, chat, target)
		local CI = C_ChatInfo
		if CI and CI.SendAddonMessage then CI.SendAddonMessage(A.PREFIX, msg, ChatType(chat), target) end
	end,
	print = function(line) ns:Output({ line }) end,
	locked = function() return ns.ChatLocked() end,
	combat = function() return Safe(InCombatLockdown) == true end,
	setting = function(name) return A.On(name) end,
	asker = function(sender, guid) return A.Asker(sender, guid) end,
	answer = function(q, asker) return A.AnswerLine(q, asker) end,
	locale = function() return Str(Safe(GetLocale)) or "enUS" end,
	battleground = function()
		local _, kind = Safe(IsInInstance)
		return kind == "pvp" or kind == "arena"
	end,
}
A.live = A.New(A.GAME)

do
	local CI = C_ChatInfo
	if CI and CI.RegisterAddonMessagePrefix then Safe(CI.RegisterAddonMessagePrefix, A.PREFIX) end
	local f = CreateFrame("Frame")
	for ev in pairs(A.CHANNELS) do pcall(f.RegisterEvent, f, ev) end
	pcall(f.RegisterEvent, f, "CHAT_MSG_ADDON")
	f:SetScript("OnEvent", function(_, event, ...)
		local ok, err
		if event == "CHAT_MSG_ADDON" then
			-- (every addon's hidden messages come here, a raid's boss timers too: the others' left at once; 0.68.5, review)
			local prefix, msg = ...
			if Str(prefix) ~= A.PREFIX then return end
			ok, err = pcall(A.live.OnAddon, A.live, A.PREFIX, Str(msg))
		else
			local text, sender = ...
			ok, err = pcall(A.live.OnChat, A.live, event, text, sender, (select(12, ...)))
		end
		if not ok then ns:Trace("ask: " .. tostring(err)) end
	end)
	A.frame = f -- (tests)
end

----------------------------------------------------------------------
-- .ask
----------------------------------------------------------------------

local function OnOff(v) return v and L["on"] or L["off"] end

function A.Status()
	local lines = { L["!t: your guild or group asks Terminal (\"!t nearest innkeeper\") and it answers for you, in the same channel."] }
	lines[#lines + 1] = L["Answering: guild %s, group %s, whispers %s (friends, guildies and your group only)"]:format(
		OnOff(A.On("guild")), OnOff(A.On("group")), OnOff(A.On("whisper")))
	for _, e in ipairs(A.live.log) do
		lines[#lines + 1] = ("  %s: %s  (%s)"):format(Ambig(e.who), tostring(e.q), REASON[e.why] or e.why)
	end
	lines[#lines + 1] = L[".ask guild on|off, .ask group on|off, .ask whisper on|off, .ask off, .ask test <question>"]
	return lines
end

ns:RegisterCommand("ask", {
	desc = L["Let Terminal answer what your guild or group asks it (!t nearest innkeeper): .ask guild on, .ask group on, .ask whisper on, .ask off, .ask test <question>"],
	complete = function()
		local out = {}
		for _, s in ipairs(A.SETTINGS) do
			out[#out + 1] = { s .. " on", L["answer questions in %s chat"]:format(SAID[s]) }
			out[#out + 1] = { s .. " off", L["stop answering in %s chat"]:format(SAID[s]) }
		end
		out[#out + 1] = { "off", L["answer nothing"] }
		out[#out + 1] = { "test", L["what Terminal would answer you, sent nowhere: .ask test nearest innkeeper"] }
		return out
	end,
	run = function(args)
		local text = tostring(args or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local first, rest = text:match("^(%S+)%s*(.*)$")
		first = first and ns.Lower(first)
		if first == "test" then
			rest = A.Clean(rest):gsub("^%s+", ""):gsub("%s+$", "")
			if rest == "" then return { L["Ask something: .ask test nearest innkeeper"] } end
			local me = ns.CharacterName and ns.CharacterName() or "you"
			local who = A.Asker(me, Str(Safe(UnitGUID, "player"))) or { name = me }
			if not A.InLocale(rest, A.GAME.locale()) then return { L["Not in this client's language: Terminal would stay quiet."] } end
			local line, busy = A.AnswerLine(rest, who)
			if not line and busy then return { L["Still loading what it needs: try again in a moment."] } end
			return { L["Would send: %s"]:format(line or A.NothingLine(rest, who)) }
		end
		local a = ns.db and rawget(ns.db, "ask")
		if first == "off" then
			rawset(ns.db, "ask", nil)
			return { L["Terminal answers nothing now."] }
		end
		local set = SAID[first or ""] and first
		local v = ns.Lower(rest)
		if set and (v == "on" or v == "off") then
			if type(a) ~= "table" then a = {}; rawset(ns.db, "ask", a) end
			a[set] = v == "on" or nil
			if not next(a) then rawset(ns.db, "ask", nil) end
			return { L["Answering in %s chat: %s"]:format(SAID[set], OnOff(v == "on")) }
		end
		return A.Status()
	end,
})
