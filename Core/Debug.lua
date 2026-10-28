local ns = select(2, ...)
local L = ns.L

-- Debugging "Interface action failed because of an AddOn".
--
-- That message is the game telling you some addon's code tried to do something only
-- Blizzard's own (secure) code may do - open a protected window, click a protected button,
-- change bindings in combat. The game fires ADDON_ACTION_FORBIDDEN / ADDON_ACTION_BLOCKED
-- with the addon's name and the function it tried to call. Terminal always listens, keeps
-- the last few, and remembers what it was doing just before (its "trace"), so a report can
-- say which entry and which step led to it.
--
--   .debug           status and the last events
--   .debug on / off  print every event and trace line live; also turns on the game's own
--                     taint log (Logs\taint.log) and Lua error popups
--   .debug log       the recorded events with what Terminal was doing at the time, in a
--                     window with the text selected: Ctrl+C, then paste it anywhere
--   .debug clear     forget them
--
-- Terminal:Trace("text") adds a trace line (used by the terminal itself).

local D = {}
ns.Debug = D

local TRACE_MAX, EVENT_MAX, WINDOW = 200, 30, 3 -- lines, events, seconds of context
local REPEAT_S = 1 -- Terminal's own block of the same call again within this: one record, counted

local trace, events = {}, {}
D.trace, D.events = trace, events
D.count = 0 -- blocked/forbidden events blamed on Terminal; code can compare before/after a call
D.others = 0 -- the same, blamed on other addons

local function Now() return GetTime and GetTime() or 0 end

local function Live() return ns.db and ns.db.debug end

--- Record what the terminal is doing. Cheap; printed immediately only in debug mode.
function ns:Trace(msg)
	trace[#trace + 1] = { t = Now(), msg = tostring(msg), combat = InCombatLockdown and InCombatLockdown() or false }
	if #trace > TRACE_MAX then table.remove(trace, 1) end
	if Live() then print("|cff808080Terminal trace: " .. tostring(msg) .. "|r") end
end

local function Recent(at)
	local out = {}
	for _, l in ipairs(trace) do
		if at - l.t <= WINDOW and l.t <= at then
			out[#out + 1] = ("%+.2fs %s%s"):format(l.t - at, l.msg, l.combat and "  [combat]" or "")
		end
	end
	return out
end

-- a press's macro for a line: one line, cut short
local function PressText(p) return tostring(p and p.text or ""):gsub("\n", " | "):sub(1, 120) end

local function Describe(ev)
	local mine = ev.addon == ns.name or ev.runPress ~= nil
	local lines = { ("%s  addon=%s%s  function=%s%s"):format(
		ev.event == "ADDON_ACTION_FORBIDDEN" and "FORBIDDEN" or "BLOCKED",
		tostring(ev.addon), ev.runPress and " (Terminal's /run press)" or mine and " (Terminal)" or "", tostring(ev.func),
		(ev.times or 1) > 1 and ("  (x%d)"):format(ev.times) or "") }
	if ev.combat then lines[#lines + 1] = "  in combat" end
	-- (a /run line runs tainted, and the game blames it as ForceTaint_Strong, not as Terminal: see Secure.NotePress)
	if ev.runPress then
		lines[#lines + 1] = ("  a /run line Terminal had the game press %.1f s before (%s): %s"):format(ev.runAgo or 0,
			tostring(ev.runPress.via), PressText(ev.runPress))
	elseif ev.lastRun then
		-- (ns.Ago says "5 min ago" / "just now" itself: "was 5 min ago ago" until 0.47.0)
		lines[#lines + 1] = ("  Terminal's last /run press was %s (%s): %s; a block later on can still come from what it wrote"):format(
			ns.Ago and ns.Ago(ev.lastRunAgo or 0) or (math.floor(ev.lastRunAgo or 0) .. " s ago"), tostring(ev.lastRun.via), PressText(ev.lastRun))
	end
	if ev.cheap and not ev.traced then
		lines[#lines + 1] = "  (another addon's; what Terminal was doing isn't recorded for these while .debug is off)"
	elseif #ev.recent == 0 then
		lines[#lines + 1] = "  Terminal did nothing in the 3 s before: likely another addon" .. (mine and " (or a delayed action of ours)" or "")
	else
		lines[#lines + 1] = "  Terminal was doing:"
		for _, l in ipairs(ev.recent) do lines[#lines + 1] = "    " .. l end
	end
	if ev.stack and ev.stack ~= "" then
		lines[#lines + 1] = "  Stack:"
		for l in ev.stack:gmatch("[^\n]+") do lines[#lines + 1] = "    " .. l end
	end
	return lines
end

D.Describe = Describe

-- a new record, the oldest dropped past EVENT_MAX
local function Push(ev)
	events[#events + 1] = ev
	if #events > EVENT_MAX then table.remove(events, 1) end
end

D.RUN_BLAME = 3 -- seconds: a ForceTaint_Strong block this soon after one of Terminal's /run presses is Terminal's

local function OnAction(event, addon, func)
	local at = Now()
	-- the game blames what a /run line does on "*** ForceTaint_Strong ***": Terminal's, when one of its presses came just before
	local runPress, runAgo
	if type(addon) == "string" and addon:find("ForceTaint", 1, true) and ns.Secure and ns.Secure.LastRunPress then
		runPress, runAgo = ns.Secure.LastRunPress(at)
	end
	local blamed = runPress and runAgo <= D.RUN_BLAME
	if addon ~= ns.name and not blamed then
		-- another addon's: these can come by the hundred a second (taint spreading), and each one
		-- used to take a stack and the trace with it, counted as Terminal's CPU. Now only a count,
		-- and repeats fold into one line (printed once with .debug on, not hundreds of times).
		D.others = D.others + 1
		local last = events[#events]
		if last and last.cheap and last.addon == addon and last.func == func and last.event == event then
			last.times, last.t = last.times + 1, at
			return
		end
		local ev = { event = event, addon = addon, func = func, t = at, recent = Live() and Recent(at) or {}, cheap = true,
			times = 1, combat = InCombatLockdown and InCombatLockdown() or false, lastRun = runPress, lastRunAgo = runAgo }
		if Live() then -- (once per new line, not per repeat)
			local ok, stack = pcall(debugstack, 3, 12, 0)
			ev.stack, ev.traced = ok and stack or nil, true
		end
		Push(ev)
		if Live() then
			for _, l in ipairs(Describe(ev)) do print("|cffff5555Terminal|r " .. l) end
		end
		return
	end
	D.count = D.count + 1 -- (Terminal's own from here on)
	-- the same call blocked again within a second (a loop of them when taint spreads): counted on the
	-- first's record, which keeps its stack and trace; the chat line is printed once, not every time
	local last = events[#events]
	if last and not last.cheap and last.func == func and last.event == event and at - last.t <= REPEAT_S then
		last.times, last.t = (last.times or 1) + 1, at
		return
	end
	-- (right after a press that turned a window for you: that window is only pointed at from now on, Secure.lua; once
	-- per new block, not for each repeat of a storm)
	if ns.Secure and ns.Secure.OnBlocked then pcall(ns.Secure.OnBlocked, func, at) end
	local ok, stack = pcall(debugstack, 3, 12, 0)
	local ev = {
		event = event, addon = addon, func = func, t = at,
		recent = Recent(at), stack = ok and stack or nil,
		combat = InCombatLockdown and InCombatLockdown() or false,
		runPress = blamed and runPress or nil, runAgo = blamed and runAgo or nil,
	}
	Push(ev)
	if Live() then
		for _, l in ipairs(Describe(ev)) do print("|cffff5555Terminal|r " .. l) end
	else
		ns:Print(L["Blocked %s (%s). Type /term .debug log for what led to it."]:format(tostring(func), event == "ADDON_ACTION_FORBIDDEN" and L["forbidden"] or L["blocked"]))
		if ns.Report then ns.Report.Nudge() end -- (where to tell the author: once a session; 0.67.11)
	end
end

local f = CreateFrame("Frame")
D.frame = f
for _, e in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, event, addon, func) OnAction(event, addon, func) end)

----------------------------------------------------------------------
-- Guarded calls (was Professions.Guarded, still reachable there)
----------------------------------------------------------------------

--- A call that may be protected (OpenRecipe, SetCurrentTitle...): made until the game blocks it once, then never
--- again. Remembered per call name in the saved variables (db.blockedCalls). Blocks fire synchronously, so the
--- count of Terminal's blocked actions (D.count) before and after the call tells.
function ns.Guarded(key, fn, ...)
	local db = ns.db
	if type(fn) ~= "function" then return false end
	if db then
		db.blockedCalls = db.blockedCalls or {}
		if db.blockedCalls[key] then return false end
	end
	local D = ns.Debug
	local before = D and D.count or 0
	ns:Trace("DIRECT " .. key)
	local ok = pcall(fn, ...)
	if D and D.count > before then
		-- a block in combat says nothing about out-of-combat: don't remember it
		if db and not (InCombatLockdown and InCombatLockdown()) then db.blockedCalls[key] = true end
		return false
	end
	return ok
end

----------------------------------------------------------------------
-- Game-side logging
----------------------------------------------------------------------

local function Cvar(name)
	local ok, v = pcall(GetCVar, name)
	return ok and v or nil
end

local function SetCVarSafe(name, value)
	if ConsoleExec then return pcall(ConsoleExec, name .. " " .. value) end
	return pcall(SetCVar, name, value)
end

function D.Set(on)
	local db = ns.db
	if not db then return end
	if on then
		if not db.debug then
			db.prevTaintLog, db.prevScriptErrors = Cvar("taintLog"), Cvar("scriptErrors")
		end
		db.debug = true
		SetCVarSafe("taintLog", "2")
		SetCVarSafe("scriptErrors", "1")
	else
		db.debug = false
		if db.prevTaintLog then SetCVarSafe("taintLog", db.prevTaintLog) end
		if db.prevScriptErrors then SetCVarSafe("scriptErrors", db.prevScriptErrors) end
		db.prevTaintLog, db.prevScriptErrors = nil, nil
	end
end

-- (D.Log and D.Report stay in English on every client, as the trace does: they're copied into bug reports for the
-- author to read, not read in the game; what the player is told goes through L[]. 0.63.7, review)
function D.Log(n)
	local lines = {}
	if #events == 0 then
		lines[1] = "No blocked-action events recorded since login."
	else
		lines[1] = ("%d blocked-action event(s), newest last:"):format(#events)
		for i = math.max(1, #events - (n or 5) + 1), #events do
			for _, l in ipairs(Describe(events[i])) do lines[#lines + 1] = l end
			lines[#lines + 1] = ""
		end
	end
	return lines
end

--- The whole log as one text for the copy window: where it ran, every recorded event,
--- then the latest trace lines.
--- The calls the game blocked once and Terminal no longer tries (ns.Guarded), sorted: { "abandonquest", ... }.
function D.BlockedCalls()
	local out = {}
	for k, v in pairs(ns.db and ns.db.blockedCalls or {}) do if v then out[#out + 1] = tostring(k) end end
	table.sort(out)
	return out
end

function D.Report()
	local lines = {}
	local ver = ns.version or "?"
	local gv, gb = "?", "?"
	if GetBuildInfo then
		local ok, v, b = pcall(GetBuildInfo)
		if ok then gv, gb = tostring(v), tostring(b) end
	end
	lines[1] = ("Terminal %s, game %s (build %s), debug %s, taintLog %s"):format(
		tostring(ver), gv, gb, Live() and "ON" or "off", tostring(Cvar("taintLog")))
	lines[2] = ""
	local calls = D.BlockedCalls()
	if #calls > 0 then lines[#lines + 1] = "Calls not tried again (blocked once): " .. table.concat(calls, ", "); lines[#lines + 1] = "" end
	for _, l in ipairs(D.Log(EVENT_MAX)) do lines[#lines + 1] = l end
	if #trace > 0 then
		lines[#lines + 1] = "Terminal trace (latest last):"
		for i = math.max(1, #trace - 120), #trace do
			lines[#lines + 1] = ("  %.2f  %s%s"):format(trace[i].t, trace[i].msg, trace[i].combat and "  [combat]" or "")
		end
	else
		lines[#lines + 1] = "No Terminal trace recorded."
	end
	return lines
end

-- what other files add: .debug talents (Talents.lua), .debug professions (Recipes.lua)
D.PARTS = {}

ns:RegisterCommand("debug", {
	desc = L["Why 'Interface action failed because of an AddOn' happens (on | off | log | clear | reset)"],
	aliases = { "taintdebug", "taint" },
	complete = function()
		return {
			{ "log", L["what led to blocked actions, in a copyable window"] },
			{ "on", L["print every blocked action and step live"] },
			{ "off", L["stop printing them"] },
			{ "clear", L["forget what was recorded"] },
			{ "reset", L["try again the calls the game blocked once"] },
			{ "talents", L["what Terminal sees in the open talent window (for bug reports)"] },
			{ "professions", L["what the open profession window reports (for bug reports)"] },
		}
	end,
	run = function(args)
		local arg = (args or ""):lower():match("^%s*(%S*)") or ""
		local out
		if arg == "on" then
			D.Set(true)
			out = {
				L["Debug ON. Every blocked action and every step Terminal takes is printed live."],
				L["Also set taintLog 2: the game writes Logs\\taint.log (in your WoW folder) naming the addon and the"],
				L["exact line that tainted things. /reload once if it stays empty. Lua error popups are on too."],
				L["Now repeat what failed, then send me the printed lines or Logs\\taint.log."],
			}
		elseif arg == "off" then
			D.Set(false)
			out = { L["Debug OFF. taintLog and scriptErrors restored. Blocked actions are still recorded: .debug log"] }
		elseif arg == "clear" then
			for i = #events, 1, -1 do events[i] = nil end
			for i = #trace, 1, -1 do trace[i] = nil end
			out = { L["Cleared."] }
		elseif arg == "reset" then
			-- (a call blocked once, outside combat, is never tried again on any character: a passing restriction kept it
			-- off for good; review, 0.48.6)
			local calls = D.BlockedCalls()
			if ns.db then ns.db.blockedCalls = {} end
			out = { #calls > 0 and L["Terminal will try these again: %s"]:format(table.concat(calls, ", ")) or L["No call was blocked."] }
		elseif arg == "log" then
			-- a real text box: select all is done, Ctrl+C copies it out of the game
			if ns.ShowText then
				ns:ShowText(L["Terminal debug log"], D.Report())
				out = { L["Debug log opened in a window: Ctrl+C copies all of it, Esc closes."] }
			else
				out = D.Report()
			end
		elseif D.PARTS[arg] then
			-- (0.65.12: .talentdebug and .profdebug, as parts of .debug)
			out = D.PARTS[arg]()
		elseif arg == "" then
			out = { L["Debug is %s  (taintLog %s)  -  .debug on | off | log | clear | reset"]:format(Live() and L["ON"] or L["off"], tostring(Cvar("taintLog"))),
				L["Blocked actions this session: %d by Terminal, %d by other addons"]:format(D.count, D.others) }
			local calls = D.BlockedCalls()
			if #calls > 0 then out[#out + 1] = L["Not tried again since the game blocked them: %s (.debug reset tries them again)"]:format(table.concat(calls, ", ")) end
			for _, l in ipairs(D.Log(3)) do out[#out + 1] = l end
		else
			out = { L["Usage: .debug on | off | log | clear | reset | talents | professions"] }
		end
		return out
	end,
})
