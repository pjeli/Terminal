local ns = select(2, ...)

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

local function Describe(ev)
	local mine = ev.addon == ns.name
	local lines = { ("%s  addon=%s%s  function=%s%s"):format(
		ev.event == "ADDON_ACTION_FORBIDDEN" and "FORBIDDEN" or "BLOCKED",
		tostring(ev.addon), mine and " (Terminal)" or "", tostring(ev.func),
		(ev.times or 1) > 1 and ("  (x%d)"):format(ev.times) or "") }
	if ev.combat then lines[#lines + 1] = "  in combat" end
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

local function OnAction(event, addon, func)
	local at = Now()
	if addon ~= ns.name then
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
			times = 1, combat = InCombatLockdown and InCombatLockdown() or false }
		if Live() then -- (once per new line, not per repeat)
			local ok, stack = pcall(debugstack, 3, 12, 0)
			ev.stack, ev.traced = ok and stack or nil, true
		end
		events[#events + 1] = ev
		if #events > EVENT_MAX then table.remove(events, 1) end
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
	local ok, stack = pcall(debugstack, 3, 12, 0)
	local ev = {
		event = event, addon = addon, func = func, t = at,
		recent = Recent(at), stack = ok and stack or nil,
		combat = InCombatLockdown and InCombatLockdown() or false,
	}
	events[#events + 1] = ev
	if #events > EVENT_MAX then table.remove(events, 1) end
	if Live() then
		for _, l in ipairs(Describe(ev)) do print("|cffff5555Terminal|r " .. l) end
	else
		ns:Print(("blocked %s (%s). Type /term .debug log for what led to it."):format(tostring(func), event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked"))
	end
end

local f = CreateFrame("Frame")
D.frame = f
for _, e in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, event, addon, func) OnAction(event, addon, func) end)

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

ns:RegisterCommand("debug", {
	desc = "Why 'Interface action failed because of an AddOn' happens (on | off | log | clear)",
	aliases = { "taintdebug", "taint" },
	complete = function()
		return {
			{ "log", "what led to blocked actions, in a copyable window" },
			{ "on", "print every blocked action and step live" },
			{ "off", "stop printing them" },
			{ "clear", "forget what was recorded" },
		}
	end,
	run = function(args)
		local arg = (args or ""):lower():match("^%s*(%S*)") or ""
		local out
		if arg == "on" then
			D.Set(true)
			out = {
				"Debug ON. Every blocked action and every step Terminal takes is printed live.",
				"Also set taintLog 2: the game writes Logs\\taint.log (in your WoW folder) naming the addon and the",
				"exact line that tainted things. /reload once if it stays empty. Lua error popups are on too.",
				"Now repeat what failed, then send me the printed lines or Logs\\taint.log.",
			}
		elseif arg == "off" then
			D.Set(false)
			out = { "Debug OFF. taintLog and scriptErrors restored. Blocked actions are still recorded: .debug log" }
		elseif arg == "clear" then
			for i = #events, 1, -1 do events[i] = nil end
			for i = #trace, 1, -1 do trace[i] = nil end
			out = { "Cleared." }
		elseif arg == "log" then
			-- a real text box: select all is done, Ctrl+C copies it out of the game
			if ns.ShowText then
				ns:ShowText("Terminal debug log", D.Report())
				out = { "Debug log opened in a window: Ctrl+C copies all of it, Esc closes." }
			else
				out = D.Report()
			end
		elseif arg == "" then
			out = { "Debug is " .. (Live() and "ON" or "off") .. "  (taintLog " .. tostring(Cvar("taintLog")) .. ")  -  .debug on | off | log | clear",
				("Blocked actions this session: %d by Terminal, %d by other addons"):format(D.count, D.others) }
			for _, l in ipairs(D.Log(3)) do out[#out + 1] = l end
		else
			out = { "Usage: .debug on | off | log | clear" }
		end
		return out
	end,
})
