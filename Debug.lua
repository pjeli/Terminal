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
--   .debug log       the recorded events with what Terminal was doing at the time
--   .debug clear     forget them
--
-- Terminal:Trace("text") adds a trace line (used by the terminal itself).

local D = {}
ns.Debug = D

local TRACE_MAX, EVENT_MAX, WINDOW = 40, 30, 3 -- lines, events, seconds of context

local trace, events = {}, {}
D.trace, D.events = trace, events
D.count = 0 -- blocked/forbidden events seen; code can compare before/after a call

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
	local lines = { ("%s  addon=%s%s  function=%s"):format(
		ev.event == "ADDON_ACTION_FORBIDDEN" and "FORBIDDEN" or "BLOCKED",
		tostring(ev.addon), mine and " (Terminal)" or "", tostring(ev.func)) }
	if ev.combat then lines[#lines + 1] = "  in combat" end
	if #ev.recent == 0 then
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

local function OnAction(event, addon, func)
	D.count = D.count + 1
	local at = Now()
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
	elseif addon == ns.name then
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

local function SetCvar(name, value)
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
		SetCvar("taintLog", "2")
		SetCvar("scriptErrors", "1")
	else
		db.debug = false
		if db.prevTaintLog then SetCvar("taintLog", db.prevTaintLog) end
		if db.prevScriptErrors then SetCvar("scriptErrors", db.prevScriptErrors) end
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

ns:RegisterCommand("debug", {
	desc = "Why 'Interface action failed because of an AddOn' happens (on | off | log | clear)",
	aliases = { "taintdebug", "taint" },
	complete = function() return { "on", "off", "log", "clear" } end,
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
		elseif arg == "log" or arg == "" then
			out = { "Debug is " .. (Live() and "ON" or "off") .. "  (taintLog " .. tostring(Cvar("taintLog")) .. ")  -  .debug on | off | log | clear" }
			for _, l in ipairs(D.Log(arg == "log" and 10 or 3)) do out[#out + 1] = l end
			if arg == "log" and #trace > 0 then
				out[#out + 1] = "Latest Terminal trace:"
				for i = math.max(1, #trace - 12), #trace do
					out[#out + 1] = ("  %.2f  %s"):format(trace[i].t, trace[i].msg)
				end
			end
		else
			out = { "Usage: .debug on | off | log | clear" }
		end
		return out
	end,
})
