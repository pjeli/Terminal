local ns = select(2, ...)
local L = ns.L

-- .report (0.67.11, the player's call): a problem report to paste where the author reads it, CurseForge's comments
-- first (GitHub issues too). Addons can't open a page, write the clipboard or send anything, so it's text in the copy
-- window, selected: Ctrl+C, then paste. What it holds: what you say happened, the result it's about (the row menu's
-- "Report a problem"), the last searches that found nothing, Terminal's and the game's versions, the addons Terminal
-- found, blocked actions, Terminal's errors BugSack caught, and Terminal's last steps. Your characters', alts' and
-- guild's names become "you", "alt 1", "your guild"; nothing leaves the game unless you paste it.
-- Pointed to where a report helps: a search that found nothing (Simple mode's row, Advanced's footer), an action the
-- game blocked, an error of Terminal's (BugSack), and the row menu. Written in English like .debug log (the author
-- reads it), what the player is told through L[].

local R = {}
ns.Report = R

R.MISSED = 5 -- (searches that found nothing, newest first)
R.STEPS = 15 -- (Terminal's last trace lines)
R.ERRORS = 3 -- (Terminal's newest errors BugSack holds)
R.HINT = L["expected something? .report"]

-- people's rows: their names are someone's, never put in a report
local PEOPLE = { guild = true, friends = true, who = true, group = true, shared = true }

local function Plain(s)
	s = tostring(s or "")
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
	return s
end

--- The names a report must not carry, longest first: { { name, what it becomes } }.
function R.Names()
	local out, seen = {}, {}
	local function Add(name, as)
		if type(name) ~= "string" or name == "" or ns.Secret(name) or seen[name] then return end
		seen[name] = true
		out[#out + 1] = { name, as }
	end
	Add(ns.CharacterName and ns.CharacterName(), "you")
	Add(_G.UnitName and (ns.Safe(_G.UnitName, "player")), "you")
	local n = 0
	for _, m in ipairs({ ns.Mail, ns.Experience, ns.Lockouts }) do
		for _, alt in ipairs(m and m.AltNames and m.AltNames() or {}) do
			if not seen[alt] then n = n + 1; Add(alt, "alt " .. n) end
		end
	end
	Add(_G.GetGuildInfo and (ns.Safe(_G.GetGuildInfo, "player")), "your guild")
	table.sort(out, function(a, b) return #a[1] > #b[1] end)
	return out
end

--- A line with every name in `names` replaced (plain text, whole names only).
function R.Scrub(line, names)
	line = tostring(line or "")
	for _, p in ipairs(names) do
		local name, as = p[1], p[2]
		local from = 1
		while true do
			local s, e = line:find(name, from, true)
			if not s then break end
			local before, after = line:sub(s - 1, s - 1), line:sub(e + 1, e + 1)
			if not before:find("[%w\128-\255]") and not after:find("[%w\128-\255]") then
				line = line:sub(1, s - 1) .. as .. line:sub(e + 1)
				from = s + #as
			else
				from = e + 1
			end
		end
	end
	return line
end

local function Version()
	local gv, gb = "?", "?"
	local ok, v, b = pcall(_G.GetBuildInfo)
	if ok then gv, gb = tostring(v), tostring(b) end
	local loc = _G.GetLocale and (ns.Safe(_G.GetLocale)) or "?"
	local mode = (ns.Easy and ns.Easy.On and ns.Easy.On()) and "Simple" or "Advanced"
	return ("Terminal %s · game %s (%s) · %s · %s mode"):format(tostring(ns.version or "?"), gv, gb, tostring(loc), mode)
end

-- Terminal's newest errors BugSack (BugGrabber) holds: its public GetDB, read defensively; {} without it
local function BugErrors()
	local BG = _G.BugGrabber
	local ok, db = pcall(function() return BG and BG.GetDB and BG:GetDB() end)
	local out = {}
	if not (ok and type(db) == "table") then return out end
	for i = #db, 1, -1 do
		local e = db[i]
		local msg = type(e) == "table" and tostring(e.message or "") or ""
		if msg:find("AddOns[\\/]Terminal") then
			out[#out + 1] = msg:gsub("\n.*", "") .. ((tonumber(e.counter) or 1) > 1 and (" (x%d)"):format(e.counter) or "")
			if #out >= R.ERRORS then break end
		end
	end
	return out
end

--- The report's lines. opts: { what = what happened, row = a result it's about }.
function R.Lines(opts)
	opts = opts or {}
	local names = R.Names()
	local lines = { "Terminal report" }
	local what = tostring(opts.what or ""):gsub("^%s+", ""):gsub("%s+$", "")
	lines[#lines + 1] = "What happened: " .. (what ~= "" and what or "(say what happened here)")
	local e = opts.row
	if type(e) == "table" then
		local kind = tostring(rawget(e, "kind") or e.kind or "?")
		local name = PEOPLE[kind] and "(a player)" or Plain(e.name)
		local detail = PEOPLE[kind] and "" or Plain(e.detail)
		lines[#lines + 1] = ("About this result: %s \"%s\"%s%s"):format(kind, name,
			(e.key ~= nil and not PEOPLE[kind]) and (" (key " .. tostring(e.key) .. ")") or "",
			detail ~= "" and (" · " .. detail) or "")
	end
	local UI = ns.UI
	local typed = opts.search or (UI and UI.lastQuery) or nil
	if type(typed) == "string" and typed ~= "" and not ns.SecretLine(typed) then lines[#lines + 1] = "Last search: " .. typed end
	lines[#lines + 1] = Version()
	-- the addons Terminal found (.integrations, colours taken out)
	local cmd = ns.commands and ns.commands.integrations
	local ok, found = pcall(function() return cmd and cmd.run("") end)
	if ok and type(found) == "table" then
		for i = 2, #found do lines[#lines + 1] = Plain(found[i]) end
	end
	local missed = ns.db and type(ns.db.missed) == "table" and ns.db.missed or {}
	if #missed > 0 then
		local t = {}
		for i = 1, math.min(#missed, R.MISSED) do t[#t + 1] = tostring(missed[i].t) end
		lines[#lines + 1] = "Searches that found nothing (newest first): " .. table.concat(t, "; ")
	end
	local D = ns.Debug
	if D and (D.count or 0) > 0 then
		local last = D.events and D.events[#D.events]
		lines[#lines + 1] = ("Blocked actions this session: %d (newest: %s)"):format(D.count, tostring(last and last.func or "?"))
	end
	local calls = D and D.BlockedCalls and D.BlockedCalls() or {}
	if #calls > 0 then lines[#lines + 1] = "Calls not tried again: " .. table.concat(calls, ", ") end
	local errs = BugErrors()
	if #errs > 0 then
		lines[#lines + 1] = "Errors (BugSack), newest first:"
		for _, m in ipairs(errs) do lines[#lines + 1] = "  " .. m end
	end
	local trace = D and D.trace or {}
	if #trace > 0 then
		lines[#lines + 1] = "Terminal's last steps:"
		for i = math.max(1, #trace - R.STEPS + 1), #trace do lines[#lines + 1] = "  " .. tostring(trace[i].msg) end
	end
	for i, l in ipairs(lines) do lines[i] = R.Scrub(l, names) end
	return lines
end

--- Opens the report in the copy window, selected.
function R.Open(opts)
	local lines = R.Lines(opts)
	if ns.ShowText then
		ns:ShowText(L["Terminal report: Ctrl+C, then paste it on CurseForge"], lines)
		return { L["Your report is in a window, selected: Ctrl+C, then paste it as a comment on Terminal's CurseForge page (a GitHub issue works too). Your characters' names are left out; read it over before posting."] }
	end
	return lines
end

ns:RegisterCommand("report", {
	desc = L["Report a problem: what happened (.report <what>), with what Terminal knows that helps, to copy and paste on CurseForge"],
	aliases = { "bug" },
	run = function(args) return R.Open({ what = args }) end,
})

--- Once a session: where to report a problem (an action the game blocked, an error of Terminal's).
function R.Nudge()
	if R.nudged then return end
	R.nudged = true
	ns:Print(L["To tell the author about it, type /term .report: it puts what happened in a window to copy."])
end

-- Terminal's errors caught by BugSack: pointed to .report once (its public callback, defensively)
function R.WatchBugs()
	local BG = _G.BugGrabber
	if R.watching or not (BG and BG.RegisterCallback) then return end
	R.watching = true
	pcall(BG.RegisterCallback, R, "BugGrabber_BugGrabbed", function(_, e)
		local msg = type(e) == "table" and tostring(e.message or "") or ""
		if msg:find("AddOns[\\/]Terminal") then R.Nudge() end
	end)
end
local bugFrame = CreateFrame("Frame")
bugFrame:RegisterEvent("PLAYER_LOGIN")
bugFrame:SetScript("OnEvent", function() pcall(R.WatchBugs) end)
