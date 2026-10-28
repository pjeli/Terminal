local ns = select(2, ...)
local L = ns.L

-- @combatlog (@combat): what hit you hard and what killed you, kept across sessions (the last 300). From the combat
-- log, only what touches you: critical hits on you and by you, the killing blow on you, and your deaths. Plain
-- questions answer from it: "what killed me", "who crit me", "my biggest crit", "my deaths".
--
-- The combat log doesn't reach addons on Midnight clients (WoW Forever included): it isn't asked for there (CB.Listen);
-- deaths are still kept (PLAYER_DEAD), with what killed you from the game's Death Recap (C_DeathRecap), and
-- `.combatlog` says why there are no crits.

local CB = {}
ns.CombatLog = CB

CB.MAX = 300
CB.MAX_DEATHS = 100

local Safe, Secret = ns.Safe, ns.Secret
local Now = ns.Now
local function Log()
	if not ns.db then return nil end
	if type(ns.db.combatLog) ~= "table" then ns.db.combatLog = {} end
	return ns.db.combatLog
end

local me -- your GUID (read on login)
local lastHit -- the last hit on you: { who, spell, amount, crit }, for a death with no killing blow seen
CB.state = { events = 0, secret = 0, blocked = false } -- (for .combatlog)

local function Dirty() ns:Changed("combatlog") end

--- Adds an entry: { t, what = "crit"/"critby"/"killed"/"died", who, spell, amount, overkill, zone, guid, char }.
--- (0.49.2, review: the log is the account's, kept across characters: each entry says whose it is, so "what killed me"
--- on one character doesn't answer with another's death)
function CB.Add(e)
	local log = Log()
	if not log then return end
	e.t = e.t or Now()
	e.guid = e.guid or me
	e.char = e.char or (ns.CharacterName and ns.CharacterName()) or nil
	local zone = _G.GetRealZoneText and Safe(_G.GetRealZoneText)
	e.zone = e.zone or (type(zone) == "string" and zone ~= "" and zone or nil)
	table.insert(log, 1, e)
	CB.Trim(log, CB.MAX, CB.MAX_DEATHS)
	Dirty()
	return e
end

--- A log (newest first) cut to `max` entries: the oldest crit goes first; deaths stay (up to `maxDeaths`) so "what
--- killed me" still answers after a long fight. The cap's rule, and what .saved keeps (Core/Saved.lua).
function CB.Trim(log, max, maxDeaths)
	if type(log) ~= "table" or #log <= max then return end
	local deaths = 0
	for _, x in ipairs(log) do if x.what == "died" or x.what == "killed" then deaths = deaths + 1 end end
	for i = #log, 1, -1 do
		if #log <= max then break end
		local death = log[i].what == "died" or log[i].what == "killed"
		if not death or deaths > maxDeaths then
			if death then deaths = deaths - 1 end
			table.remove(log, i)
		end
	end
end

-- where the damage fields sit, by the event's prefix: amount, overkill, critical (positions in the event's values)
local DAMAGE = {
	SWING_DAMAGE = { 12, 13, 18 },
	RANGE_DAMAGE = { 15, 16, 21, spell = 13 }, SPELL_DAMAGE = { 15, 16, 21, spell = 13 },
	SPELL_PERIODIC_DAMAGE = { 15, 16, 21, spell = 13 }, SPELL_BUILDING_DAMAGE = { 15, 16, 21, spell = 13 },
	ENVIRONMENTAL_DAMAGE = { 13, 14, 19, env = 12 },
}

--- One combat log event, given its values as the game lists them (CombatLogGetCurrentEventInfo()).
function CB.OnCombatEvent(...)
	local st = CB.state
	st.events = st.events + 1
	local _, sub, _, src, srcName, _, _, dst, dstName = ...
	if Secret and (Secret(sub) or Secret(src) or Secret(dst)) then st.secret = st.secret + 1 return end
	if not me or (src ~= me and dst ~= me) then return end
	if sub == "UNIT_DIED" then
		if dst == me then
			if CB.killedAt and Now() - CB.killedAt <= 5 then CB.killedAt = nil return end -- (the killing blow said it)
			local hit = lastHit
			if not (hit and Now() - hit.t <= 5) then hit = nil end
			CB.Add({ what = "died", who = hit and hit.who, spell = hit and hit.spell, amount = hit and hit.amount })
			lastHit = nil
		end
		return
	end
	local d = DAMAGE[sub]
	if not d then return end
	local amount, overkill, crit = select(d[1], ...), select(d[2], ...), select(d[3], ...)
	if Secret and (Secret(amount) or Secret(crit)) then st.secret = st.secret + 1 return end
	if type(amount) ~= "number" then return end
	local spell = d.spell and select(d.spell, ...) or (d.env and select(d.env, ...)) or nil
	if Secret and spell and Secret(spell) then spell = nil end
	if d.env and type(spell) == "string" then spell = spell:sub(1, 1):upper() .. spell:sub(2):lower() end
	local who = type(srcName) == "string" and not (Secret and Secret(srcName)) and srcName or nil
	local target = type(dstName) == "string" and not (Secret and Secret(dstName)) and dstName or nil
	if dst == me then
		who = who or (d.env and L["the world"]) or "?"
		lastHit = { who = who, spell = spell, amount = amount, crit = crit and true or false, t = Now() }
		if type(overkill) == "number" and overkill > 0 then
			CB.Add({ what = "killed", who = who, spell = spell, amount = amount, overkill = overkill, crit = crit and true or nil })
			lastHit = nil
			CB.killedAt = Now() -- (the death that follows isn't a second entry)
		elseif crit then
			CB.Add({ what = "crit", who = who, spell = spell, amount = amount })
		end
	elseif src == me and crit and dst ~= me then
		CB.Add({ what = "critby", who = target or "?", spell = spell or (sub == "SWING_DAMAGE" and L["melee"] or nil), amount = amount })
	end
end

local function CombatEvent()
	local get = _G.CombatLogGetCurrentEventInfo
	if not get then return end
	CB.OnCombatEvent(get())
end

-- Midnight (Interface 12.0 on, and WoW Forever, which reports 16001 but has Midnight's secret values) keeps the combat
-- log from addons: registering for it is a forbidden action (WoW Forever
-- 1.60.1 showed "Terminal has been blocked from an action only available to the Blizzard UI" at login, 0.43.15; the
-- pcall said fine, the block comes as ADDON_ACTION_FORBIDDEN). Never asked there; elsewhere asked once through
-- ns.Guarded (Debug.lua), which remembers a block (db.blockedCalls) so it is never asked again.
CB.MIDNIGHT = 120000
function CB.Listen(frame)
	-- (WoW Forever reports Interface 16001, not 12.x: the Midnight API is told by its secret values, issecretvalue)
	local build = _G.GetBuildInfo and select(4, ns.Safe(_G.GetBuildInfo))
	if _G.issecretvalue or (type(build) == "number" and build >= CB.MIDNIGHT) then
		return false, "not asked: this client keeps the combat log from addons"
	end
	local ok = ns.Guarded("combatlog", frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")
	return ok and true or false, "the game refused it to addons"
end

-- The game's Death Recap (C_DeathRecap: WoW Forever has it, 0.43.17): what hit you last before you died, even where the
-- combat log is kept from addons. Each death has a recap id (the chat's "[Death Recap]" link: |Hdeath:<id>|h); the
-- newest is found by asking HasRecapEvents up from the last one seen, or read from that chat link when it comes.
local recapSeen, recapLink = 0, nil
CB.RECAP_LOOK = 40 -- (ids asked past the last one seen)
local Num = ns.Num -- (Util.lua: a number that isn't secret, else nil)
-- (secret first: a secret string can't even be compared with "")
local function Text(v) return type(v) == "string" and not (Secret and Secret(v)) and v ~= "" and v or nil end

--- The newest death recap id, or nil.
function CB.NewestRecap()
	local R = _G.C_DeathRecap
	if not (R and R.HasRecapEvents) then return nil end
	local newest = nil
	if recapLink and recapLink > recapSeen and Safe(R.HasRecapEvents, recapLink) then newest = recapLink end
	for id = recapSeen + 1, recapSeen + CB.RECAP_LOOK do
		if Safe(R.HasRecapEvents, id) then newest = id end
	end
	if newest then recapSeen = newest end
	return newest
end

--- What a death recap says killed you: { who, spell, amount, overkill }, or nil (no recap, or nothing readable).
function CB.FromRecap(id)
	local R = _G.C_DeathRecap
	local events = id and R and R.GetRecapEvents and Safe(R.GetRecapEvents, id)
	if type(events) ~= "table" or #events == 0 then return nil end
	local best, bestT
	for _, e in ipairs(events) do
		if type(e) == "table" then
			local over = Num(e.overkill)
			if over and over > 0 then best = e break end
			local t = Num(e.timestamp)
			if t and (not bestT or t > bestT) then best, bestT = e, t end
		end
	end
	best = best or events[1]
	if type(best) ~= "table" then return nil end
	local spell = Text(best.spellName)
	local env = Text(best.environmentalType)
	if not spell and env then spell = env:sub(1, 1):upper() .. env:sub(2):lower() end
	local over = Num(best.overkill)
	return { who = Text(best.sourceName) or (env and L["the world"]) or nil, spell = spell, amount = Num(best.amount),
		overkill = over and over > 0 and over or nil }
end
CB.ResetRecaps = function() recapSeen, recapLink = 0, nil end -- (tests)

--- After a death: the killing blow from the combat log (when there is one), else the death recap, else the last hit
--- seen; a death recap that isn't ready yet fills the entry in a moment later.
function CB.OnDeath()
	local log = Log()
	local last = log and log[1]
	if last and (last.what == "died" or last.what == "killed") and Now() - (last.t or 0) <= 5 then return end
	-- the death is written down first: reading the recap can fail (secret values) and must never lose it
	local hit = lastHit and Now() - lastHit.t <= 5 and lastHit or nil
	local e = CB.Add({ what = "died", who = hit and hit.who, spell = hit and hit.spell, amount = hit and hit.amount })
	lastHit = nil
	if not e then return end
	local function Fill()
		local ok, id, rec = pcall(function() local i = CB.NewestRecap() return i, CB.FromRecap(i) end)
		if not ok then ns:Trace("combat log: reading the death recap failed: " .. tostring(id)) return false end
		ns:Trace(("combat log: a death; death recap %s%s"):format(tostring(id or "none found"),
			rec and (": " .. tostring(rec.who) .. " / " .. tostring(rec.spell)) or ""))
		if rec and rec.who then
			e.what, e.who, e.spell, e.amount, e.overkill = "killed", rec.who, rec.spell, rec.amount, rec.overkill
			Dirty()
			return true
		end
		return false
	end
	if not Fill() then C_Timer.After(1.5, function() if e.what == "died" then Fill() end end) end
end

--- At login: the recaps the client already holds (from before a /reload) are taken as seen, so the next death's
--- isn't mistaken for an old one.
CB.RECAP_SEED = 200
function CB.SeedRecaps()
	local R = _G.C_DeathRecap
	if not (R and R.HasRecapEvents) then return end
	for id = 1, CB.RECAP_SEED do
		if Safe(R.HasRecapEvents, id) then recapSeen = math.max(recapSeen, id) end
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_DEAD")
-- (the "[Death Recap]" link in chat carries the death's recap id)
pcall(ev.RegisterEvent, ev, "CHAT_MSG_SYSTEM")
pcall(ev.RegisterEvent, ev, "CHAT_MSG_COMBAT_MISC_INFO")
ev:SetScript("OnEvent", function(self, event, msg)
	if event == "CHAT_MSG_SYSTEM" or event == "CHAT_MSG_COMBAT_MISC_INFO" then
		local id = type(msg) == "string" and not (Secret and Secret(msg)) and tonumber(msg:match("|Hdeath:(%d+)"))
		if id then recapLink = id end
		return
	end
	if event == "PLAYER_LOGIN" then
		me = _G.UnitGUID and Safe(_G.UnitGUID, "player")
		if Secret and Secret(me) then me = nil end
		local ok, why = CB.Listen(self)
		CB.state.blocked = not ok
		ns:Trace("combat log: " .. (ok and "listening" or why))
		pcall(CB.SeedRecaps)
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		pcall(CombatEvent)
	elseif event == "PLAYER_DEAD" then
		-- (the combat log's own death line wasn't seen, or came without a killing blow: the recap, a moment later)
		C_Timer.After(0.3, function() pcall(CB.OnDeath) end)
	end
end)
CB.SetMe = function(guid) me = guid end -- (tests)

----------------------------------------------------------------------
-- The list
----------------------------------------------------------------------

local function Ago(t) return ns.Ago(ns.Now() - (t or 0)) end -- (Util's, not through LootLog's)
local function Amount(n) return n and (BreakUpLargeNumbers and Safe(BreakUpLargeNumbers, n) or tostring(n)) or nil end

--- The line an entry says ("Hogger crit you for 245 (Mortal Strike)").
function CB.Line(e)
	local with = e.spell and (" (" .. e.spell .. ")") or ""
	local amt = Amount(e.amount)
	if e.what == "crit" then return L["%s crit you for %s%s"]:format(e.who or "?", amt or "?", with) end
	if e.what == "critby" then return L["You crit %s for %s%s"]:format(e.who or "?", amt or "?", with) end
	if e.what == "killed" then
		if amt then return L["%s killed you with %s%s"]:format(e.who or "?", amt, with) end
		return L["%s killed you%s"]:format(e.who or "?", with)
	end
	if e.who then
		if amt then return L["You died: %s hit you for %s%s"]:format(e.who, amt, with) end
		return L["You died: %s%s"]:format(e.who, with)
	end
	return L["You died"]
end

local WORDS = { crit = "crit critical hit you taken", critby = "crit critical you dealt mine", killed = "killed you death died killing blow",
	died = "died death killed you" }
-- Enter: shown in your chat window (only you see it), as other lists show their rows (ns:Output)
local function Say(e) ns:Output({ e.line .. "  (" .. e.detail .. ")" }) end
local function LineOf(e) return e.line end
local CHATBOX = ns.ChatBoxSpec(LineOf) -- (shared by every row)
local function ToChat(e) ns.LinkInChat(e.line) end

ns:RegisterProvider("combatlog", {
	label = L["Combat log"],
	color = "ffff6b5c",
	aliases = { "combatlog", "combat", "deaths", "crits" },
	explicit = true,
	refreshOnOpen = 60, -- (the "5 min ago" moves on: rebuilt on open when a minute old; new entries mark it dirty)
	leadRow = ns.EmptyLead(L["Nothing recorded yet"], function() return #(Log() or {}) == 0 end), -- (0.49.2, review)
	collect = function()
		local out, log = {}, Log() or {}
		local n = #log
		for i, d in ipairs(log) do
			if type(d) == "table" and d.what then
				local line = CB.Line(d)
				local parts = { Ago(d.t) }
				if d.overkill then parts[#parts + 1] = L["%s overkill"]:format(Amount(d.overkill)) end
				if d.zone then parts[#parts + 1] = d.zone end
				-- another character's (entries kept before 0.49.2 say no one: taken as yours, as they were)
				local other = d.guid and me and d.guid ~= me or nil
				if other then parts[#parts + 1] = L["on %s"]:format(d.char or "?") end
				out[#out + 1] = {
					-- (by what it is, not its place: each new entry moved every older one's key, and picks never matched again;
					-- review, 0.53.6)
					key = table.concat({ d.t or 0, d.what, tostring(d.who), tostring(d.spell), tostring(d.amount) }, ":"), name = line, line = line, what = d.what, amount = d.amount, other = other,
					at = d.t, -- (when: since:today; 0.66.8)
					icon = (d.what == "died" or d.what == "killed") and "Interface\\Icons\\Ability_Rogue_FeignDeath"
						or "Interface\\Icons\\Ability_CriticalStrike",
					detail = table.concat(parts, ns.DETAIL_SEP),
					text = table.concat({ WORDS[d.what] or "", d.who or "", d.spell or "", d.zone or "", other and d.char or "" }, " "),
					_rank = (n - i + 1) / (n + 1) * 0.99,
					activate = Say,
					secondarySecure = CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen, secondary = ToChat,
				}
			end
		end
		return out
	end,
})

----------------------------------------------------------------------
-- Questions: "what killed me", "who crit me", "my biggest crit", "my deaths"
----------------------------------------------------------------------

local ASKS = {}
for w in ([[what whats who whos killed kill me my i did die died deaths death how crit crits crited critted hit hits hardest
	biggest best top last recent the was by on]]):gmatch("%S+") do ASKS[w] = true end

--- "killed" / "crit" / "critby" for a question in plain words, else nil.
function CB.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local has, n = {}, 0
	for w in t:gmatch("%S+") do
		if not ASKS[w] then return nil end
		has[w], n = true, n + 1
	end
	if n < 2 then return nil end
	if (has.killed or has.kill or has.die or has.died or has.death or has.deaths) and (has.me or has.my or has.i) then return "killed" end
	local crit = has.crit or has.crits or has.crited or has.critted or has.hardest
	if crit and (has.my or has.i) and not has.me then return "critby" end
	if (crit or has.hit or has.hits) and (has.me or has.who or has.what) then return "crit" end
end

--- The rows a question wants, and the footer's note.
function CB.Answer(kind)
	local p = ns.providers.combatlog
	local rows = {}
	-- (the filters Alt+` writes: is:mine, and is:death / is:taken / is:dealt; Filters/Others.lua)
	local F = ns.Filters
	local mine, which = F.Parse("is:mine"), F.Parse((kind == "killed" and "is:death") or (kind == "crit" and "is:taken") or "is:dealt")
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		-- (yours only: "what killed me" on this character; @combatlog lists every character's, each named)
		if mine(e) and which(e) then rows[#rows + 1] = e end
	end
	if kind ~= "killed" then -- (crits: the biggest first)
		table.sort(rows, function(a, b) return (a.amount or 0) > (b.amount or 0) end)
	end
	ns.ScoreInOrder(rows)
	local note = (kind == "killed" and L["Your deaths, newest first"]) or (kind == "crit" and L["The hardest crits on you"])
		or L["Your biggest crits"]
	if #rows == 0 then
		note = (CB.state.blocked and kind ~= "killed") and L["The game doesn't give addons the combat log here (crits need it)"]
			or L["Nothing recorded yet"]
	end
	return rows, note
end

--- Forget the combat log kept: `.forget combatlog` (0.65.12: .combatlog is gone; "what killed me" and @combatlog read it).
function CB.Clear()
	if ns.db then ns.db.combatLog = {} end
	Dirty()
end
