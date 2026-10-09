local ns = select(2, ...)

-- Experience (@experience, @exp, @xp; Simple mode: "xp", under Character): your character's experience and rested
-- experience, read live, and your alts' as they were when you last played them. No bag addon records experience, so
-- Terminal keeps its own note per character (db.xpChars, by GUID): an alt shows up once you've logged in on it with
-- Terminal. An alt's rested experience is worked out from that note: it keeps filling while you're away, as the game
-- fills it (5% of a level per 8 hours resting in an inn or city, a quarter of that elsewhere, up to a level and a
-- half), marked "~" as the estimate it is.
--
--   Enter        every character's experience in chat (only you see it)
--   Shift+Enter  the row in the chat box ("Plamen Warr: level 23, 41% (rested 57%)"), to send

local X = {}
ns.Experience = X

local Safe, Num, Str = ns.Safe, ns.Num, ns.Str

X.RESTED_PER_HOUR = 0.05 / 8 -- (of a level, resting; a quarter of it elsewhere)
X.AWAY_SHARE = 0.25
X.RESTED_CAP = 1.5 -- (levels)

local function Now() return (_G.time and _G.time()) or 0 end

local function Chars()
	if not ns.db then return nil end
	if type(ns.db.xpChars) ~= "table" then ns.db.xpChars = {} end
	return ns.db.xpChars
end

local function MaxLevel()
	local f = _G.GetMaxLevelForPlayerExpansion or _G.GetMaxPlayerLevel
	return f and Num(Safe(f)) or (_G.MAX_PLAYER_LEVEL or 60)
end

local function MyKey() return Str(Safe(UnitGUID, "player")) end

--- Your character as it is now: { name, realm, class, level, xp, max, rested, resting, maxed, t }; nil when the game
--- won't say (secret values, no player yet).
function X.ReadMe()
	local level = Num(Safe(UnitLevel, "player"))
	if not level or level < 1 then return nil end
	local max = MaxLevel()
	local disabled = _G.IsXPUserDisabled and Safe(_G.IsXPUserDisabled) == true
	-- (the game's own word first: GetMaxLevelForPlayerExpansion may give the retail cap on WoW Forever)
	local atMax = _G.IsLevelAtEffectiveMaxLevel and Safe(_G.IsLevelAtEffectiveMaxLevel, level)
	local maxed = atMax == true or (max and level >= max) or false
	local xp, xpMax = Num(Safe(UnitXP, "player")), Num(Safe(UnitXPMax, "player"))
	if not xpMax or xpMax <= 0 then xp, xpMax = nil, nil end -- (0 at logout and early in a login: not an answer)
	local rested = Num(Safe(GetXPExhaustion)) or 0
	local realm = Str(Safe(GetRealmName))
	return {
		name = ns.CharacterName() or Str(Safe(UnitName, "player")) or "You", realm = realm,
		class = Str(select(2, Safe(UnitClass, "player"))), level = level,
		xp = (not maxed) and xp or nil, max = (not maxed) and xpMax or nil, rested = (not maxed) and rested or 0,
		resting = Safe(IsResting) == true, maxed = maxed, disabled = disabled or nil, t = Now(),
	}
end

--- Keeps a reading in the note: a whole one replaces it; one without experience (the game answers 0 at logout and
--- for a moment at login) only moves the time and the resting place on, keeping the last real numbers.
function X.Keep(chars, key, me)
	local old = chars[key]
	if me.maxed or me.max or type(old) ~= "table" or old.level ~= me.level then
		chars[key] = me
		return me
	end
	old.t, old.resting, old.name, old.realm, old.class = me.t, me.resting, me.name, me.realm, me.class
	return old
end

--- Writes down where your character is (on every experience change, and at logout: the time and the resting
--- place the estimate goes from).
function X.Record()
	local key, chars = MyKey(), Chars()
	if not (key and chars) then return nil end
	local me = X.ReadMe()
	if not me then return nil end
	me = X.Keep(chars, key, me)
	local p = ns.providers.experience
	if p then p._dirty = true end
	return me
end

--- An alt's rested experience now: its note's, plus what filled while away (capped); estimated = true when it grew.
function X.RestedNow(c, now)
	if c.maxed or not c.max or c.max <= 0 then return 0, false end
	local base = tonumber(c.rested) or 0
	local hours = math.max(0, ((now or Now()) - (c.t or 0)) / 3600)
	local rate = X.RESTED_PER_HOUR * (c.resting and 1 or X.AWAY_SHARE)
	local cap = c.max * X.RESTED_CAP
	local r = math.min(cap, base + c.max * rate * hours)
	if r < base then r = base end
	return math.floor(r), r > base + 0.5
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local function Thousands(n) return ns.Gold and ns.Gold.Thousands(n) or ("%.0f"):format(n) end
local function Pct(a, b) return (b and b > 0) and math.floor(a / b * 100 + 0.5) or 0 end

local function Ago(t)
	local d = math.max(0, Now() - (t or 0))
	if d < 3600 then return "just now" end
	if d < 86400 then return math.floor(d / 3600) .. " h ago" end
	return math.floor(d / 86400) .. " d ago"
end

local list -- (the last collect's rows: Enter lists them all)

--- "level 23, 41% (rested 57%)", "level 60 (max)": what's sent and printed.
local function Summary(e, plain)
	if e.maxed then return ("level %d (max)"):format(e.level) end
	local s = ("level %d"):format(e.level)
	if e.xpMax then s = s .. (", %d%%"):format(Pct(e.xp or 0, e.xpMax)) end
	if (e.rested or 0) > 0 and e.xpMax then -- (no experience read yet: no "rested 0%")
		s = s .. (" (%srested %d%%)"):format(e.estimated and "~" or "", Pct(e.rested, e.xpMax))
	end
	if e.disabled and not plain then s = s .. " (experience turned off)" end
	return s
end

local function ShareText(e) return e.who .. ": " .. Summary(e, true) end

local function Lines()
	local out = {}
	for _, e in ipairs(list or {}) do
		out[#out + 1] = "  " .. (e.color or "") .. e.who .. (e.color and "|r" or "") .. (e.mine and " (you)" or "")
			.. ":  " .. Summary(e) .. ((not e.mine) and ("  |cff9d9d9d(" .. Ago(e.seen) .. ")|r") or "")
	end
	return out
end

local function PrintAll() ns:Output(Lines()) end
local function ToChatBox(e) ns.LinkInChat(ShareText(e)) end
local CHATBOX = ns.ChatBoxSpec(ShareText)

local function Tooltip(e, t)
	t:SetText(e.who, 1, 0.82, 0)
	t:AddLine(("Level %d"):format(e.level), 1, 1, 1)
	if e.maxed then
		t:AddLine("Max level", 0.6, 0.6, 0.6)
	elseif e.xpMax then
		t:AddDoubleLine("Experience", ("%s / %s (%d%%)"):format(Thousands(e.xp or 0), Thousands(e.xpMax), Pct(e.xp or 0, e.xpMax)), 1, 1, 1, 1, 1, 1)
		t:AddDoubleLine("To level", Thousands(math.max(0, e.xpMax - (e.xp or 0))), 1, 1, 1, 1, 1, 1)
		t:AddDoubleLine("Rested" .. (e.estimated and " (estimated)" or ""),
			("%s (%d%%)"):format(Thousands(e.rested or 0), Pct(e.rested or 0, e.xpMax)), 1, 1, 1, 0.4, 0.6, 1)
	end
	if e.resting then t:AddLine(e.mine and "Resting now" or "Logged out resting (inn or city)", 0.4, 0.6, 1) end
	if not e.mine then t:AddLine("Last played " .. Ago(e.seen), 0.6, 0.6, 0.6) end
	t:AddLine("Enter: every character in chat    Shift+Enter: put it in the chat box", 0.6, 0.6, 0.6, true)
end

local ICON_ME, ICON_ALT = "Interface\\Icons\\Spell_Holy_SurgeOfLight", "Interface\\Icons\\INV_Misc_Book_09"

local function Row(key, c, mine, myRealm, now)
	local rested, estimated = c.rested or 0, false
	if not mine then rested, estimated = X.RestedNow(c, now) end
	local who = c.name or "?"
	if c.realm and myRealm and c.realm ~= myRealm then who = who .. "-" .. c.realm end
	local e = {
		key = key, name = who, who = who, mine = mine or nil, level = c.level, xp = c.xp,
		xpMax = (tonumber(c.max) or 0) > 0 and c.max or nil, -- (0: a note from before 0.43.23, read at logout)
		rested = rested, estimated = estimated or nil, maxed = c.maxed or nil, resting = c.resting or nil,
		disabled = c.disabled, seen = c.t,
		color = ns.ClassHex(c.class), icon = mine and ICON_ME or ICON_ALT,
		text = "experience exp xp level " .. (rested > 0 and "rested " or "") .. (mine and "you me mine" or "alt alts character"),
		tooltip = Tooltip, activate = PrintAll,
		secondary = ToChatBox, secondarySecure = CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen, shareLink = ShareText,
	}
	local d = { Summary(e) }
	if mine then d[#d + 1] = "|cff9d9d9d(you)|r" else d[#d + 1] = "|cff9d9d9d" .. Ago(c.t) .. "|r" end
	e.detail = table.concat(d, "  ")
	return e
end

function X.Collect()
	local chars = Chars() or {}
	local myKey = MyKey()
	local me = X.ReadMe()
	local myRealm = me and me.realm
	local now = Now()
	local rows = {}
	if me then
		if myKey then me = X.Keep(chars, myKey, me) end -- (kept fresh while you play)
		rows[1] = Row(myKey or "me", me, true, myRealm, now)
	end
	local alts = {}
	for key, c in pairs(chars) do
		if key ~= myKey and type(c) == "table" and type(c.level) == "number" then alts[#alts + 1] = Row(key, c, false, myRealm, now) end
	end
	-- the highest level first, then the closest to the next one, then by name
	table.sort(alts, function(a, b)
		if a.level ~= b.level then return a.level > b.level end
		local pa, pb = Pct(a.xp or 0, a.xpMax), Pct(b.xp or 0, b.xpMax)
		if pa ~= pb then return pa > pb end
		return a.who < b.who
	end)
	for _, e in ipairs(alts) do rows[#rows + 1] = e end
	local n = #rows
	for i, e in ipairs(rows) do e._rank = (n - i + 1) / (n + 1) * 0.5 end -- (this order among equal matches)
	list = rows
	return rows
end

ns:RegisterProvider("experience", {
	label = "Experience",
	color = "ff8a6cff", -- (the XP bar's purple)
	aliases = { "experience", "exp", "xp", "rested" },
	refreshOnOpen = true, -- (alts' rested keeps filling)
	events = { "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" },
	guard = 1,
	collect = function() return X.Collect() end,
})

ns:RegisterCommand("xp", {
	desc = "Your characters' experience and rested experience; .xp forget <name> drops an alt",
	aliases = { "experience", "rested" },
	complete = function()
		local out = {}
		for _, c in pairs(Chars() or {}) do
			if type(c) == "table" and c.name then out[#out + 1] = { "forget " .. c.name, "drop it from the list" } end
		end
		return out
	end,
	run = function(args)
		local a = strtrim(args or "")
		local who = a:match("^[Ff]orget%s+(.+)$")
		if who then
			local lw, chars, myKey, n = ns.Lower(who), Chars() or {}, MyKey(), 0
			for key, c in pairs(chars) do
				if key ~= myKey and type(c) == "table" and c.name and (ns.Lower(c.name) == lw
					or ns.Lower(c.name .. "-" .. tostring(c.realm)) == lw) then
					chars[key] = nil
					n = n + 1
				end
			end
			local p = ns.providers.experience
			if p then p._dirty = true end
			return { n > 0 and ("Forgot %s."):format(who) or ("No alt called %s (you can't forget the character you're on)."):format(who) }
		end
		X.Collect()
		local lines = Lines()
		if #lines <= 1 then
			lines[#lines + 1] = "  (Alts show up here once you've logged in on them with Terminal.)"
		end
		table.insert(lines, 1, "Experience:")
		return lines
	end,
})

-- the note on each change, and at logout (the time and whether you're resting: the estimate starts there)
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP",
	"PLAYER_UPDATE_RESTING", "PLAYER_LOGOUT" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LEVEL_UP" then
		C_Timer.After(0.5, function() pcall(X.Record) end) -- (UnitLevel catches up a moment later)
	elseif event == "PLAYER_ENTERING_WORLD" then
		pcall(X.Record)
		C_Timer.After(3, function() pcall(X.Record) end) -- (the experience may not be in yet)
	else
		pcall(X.Record)
	end
end)
