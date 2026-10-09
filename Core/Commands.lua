local ns = select(2, ...)

-- Terminal commands: type "." in the terminal. Add your own from any addon:
--   Terminal:RegisterCommand("hello", {
--       desc = "say hello", aliases = { "hi" },
--       run  = function(args, ns) return { "hello " .. args } end,
--   })

ns:RegisterCommand("help", {
	desc = "List terminal commands",
	aliases = { "?", "h" },
	run = function()
		if ns.Easy and ns.Easy.On() then return ns.Easy.HelpLines() end -- (plain sentences in easy mode)
		local lines = { "Terminal commands:" }
		for _, name in ipairs(ns.commandOrder) do
			local c = ns.commands[name]
			lines[#lines + 1] = ("  .%s  -  %s"):format(name, c.desc or "")
		end
		lines[#lines + 1] = "Modes: plain text = search everything, / = slash commands, . = commands, @kind = filter, 3*45g = calculator"
		lines[#lines + 1] = "Filters (add to a search, .filters for all): lvl:20-30  q:rare+  stat:stamina  slot:wrist  in:bank  is:todo  is:usable"
		lines[#lines + 1] = "Send a result to chat with  >>  :  hearthstone >> party   @npc hogger >> guild   copper bar >> w Name"
		lines[#lines + 1] = "Every result at once with  >>>  :  mats for thorium belt >>> party   @loot lorgus jett >>> guild"
		lines[#lines + 1] = "Chains: thorium belt > mats, copper bar > uses, thorium bar > sources (.chains); plain words work too: mats for thorium belt"
		lines[#lines + 1] = "Ask in plain words: where should i level, what dungeon should i do, where should i fish, what killed me, what dropped"
		lines[#lines + 1] = "Flight paths you haven't learned: @flight is:unlearned sort:nearest (in plain words: nearest unlearned flight master); a flight master's map tells Terminal which you know"
		lines[#lines + 1] = "do:use / do:cast / do:summon... make Enter that action (Simple mode's action words): @items do:use hearthstone"
		lines[#lines + 1] = "Shift+Right at the end of the prompt writes the selected result into it (@npc Thrall), to build on; right-click a result for everything it can do"
		lines[#lines + 1] = "Tab+` (hold Tab, press `) is pure fuzzy finding over every list, by name; Ctrl+click a link in chat to look it up here"
		lines[#lines + 1] = "Keys: Enter does the row's action and Shift+Enter its other one (the footer says which), Ctrl+Enter act but keep the terminal open (a window it opens still closes it), Up on an empty prompt = earlier lines (.history), Down = your recent picks, Tab completes commands and their arguments"
		return lines
	end,
})

ns:RegisterCommand("filters", {
	desc = "List search filters (add them to a search: @loot stat:stamina q:rare+)",
	aliases = { "filter" },
	run = function()
		local lines = { "Search filters (key:value, add to any search; Tab completes values):" }
		for _, h in ipairs(ns.Filters and ns.Filters.HELP or {}) do
			lines[#lines + 1] = ("  %s  -  %s"):format(h[1], h[2])
		end
		lines[#lines + 1] = "Examples: @loot stat:stamina q:rare+ lvl:20-30   @stored on:plamen in:bank   @npc is:vendor in:ashenvale   @questie is:todo lvl:20-25"
		return lines
	end,
})

ns:RegisterCommand("kinds", {
	desc = "List searchable kinds (use with @kind)",
	aliases = { "providers" },
	run = function()
		local lines = { "Searchable kinds:" }
		for _, id in ipairs(ns.providerOrder) do
			local p = ns.providers[id]
			local flags = {}
			if p.explicit then flags[#flags + 1] = "explicit" end
			if p.lazy then flags[#flags + 1] = "lazy" end
			lines[#lines + 1] = ("  @%s  (%s)%s"):format(p.aliases[1] or id, p.label,
				#flags > 0 and ("  [" .. table.concat(flags, ", ") .. "]") or "")
		end
		return lines
	end,
})

ns:RegisterCommand("reload", {
	desc = "Reload the UI",
	aliases = { "rl" },
	-- (not a protected call: run from here. Command rows can't carry a game press, see UI:CommandEntries)
	run = function()
		local reload = (C_UI and C_UI.Reload) or ReloadUI
		if reload then reload() end
	end,
})

ns:RegisterCommand("refresh", {
	desc = "Rebuild all search indexes",
	run = function()
		ns:MarkAllDirty()
		return { "Indexes will rebuild on next search." }
	end,
})

ns:RegisterCommand("bind", {
	desc = "Bind a key to toggle the terminal, e.g. .bind CTRL-SPACE",
	run = function(args)
		args = strtrim(args or ""):upper()
		if args == "" then
			return { "Usage: .bind CTRL-SPACE", "Current: " .. (GetBindingKey("TERMINAL_TOGGLE") or "none") }
		end
		if InCombatLockdown() then return { "Keys can't be bound in combat; try .bind again after." } end
		if SetBinding(args, "TERMINAL_TOGGLE") then
			SaveBindings(GetCurrentBindingSet())
			return { "Terminal toggle bound to " .. args }
		end
		return { "Could not bind " .. args }
	end,
})

ns:RegisterCommand("forget", {
	desc = "Clear learned usage ranking",
	aliases = { "reset" },
	run = function()
		wipe(ns.db.freq)
		if ns.db.recent then wipe(ns.db.recent) end -- (the recent picks shown on an empty prompt are learned usage too)
		ns.freqKinds = nil
		return { "Usage history cleared." }
	end,
})

ns:RegisterCommand("clear", {
	desc = "Clear highlights",
	run = function()
		ns.Highlight:Clear()
		return { "Highlights cleared." }
	end,
})

ns:RegisterCommand("about", {
	desc = "Version info",
	run = function()
		return { "Terminal " .. ns.version, "Providers: " .. #ns.providerOrder .. "  Commands: " .. #ns.commandOrder }
	end,
})

-- .mem : Terminal's own memory use, how many entries each kind holds, and how long the last
-- search took. For measuring before and after performance changes. Each part adds its lines.
local function MemoryLine(lines)
	local upd = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or _G.UpdateAddOnMemoryUsage
	local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or _G.GetAddOnMemoryUsage
	if upd then pcall(upd) end
	local kb = get and select(2, pcall(get, ns.name))
	if type(kb) == "number" then
		lines[#lines + 1] = ("Terminal memory: %.0f KB"):format(kb)
	else
		lines[#lines + 1] = "Terminal memory: not reported by this client"
	end
end

-- every list: its entries (or not built), its flags; then the total
local function ProviderLines(lines)
	local now = GetTime()
	local total = 0
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		local n = p._entries and #p._entries
		local state
		if n then
			total = total + n
			state = ("%d entries"):format(n)
		else
			state = "not built" .. (p.idleDrop and " (freed when idle)" or "")
		end
		local flags = {}
		if p.explicit then flags[#flags + 1] = "only with @" end
		if p.lazy then flags[#flags + 1] = "skipped on empty searches" end
		if n and p._usedAt then flags[#flags + 1] = ("used %ds ago"):format(math.floor(now - p._usedAt)) end
		lines[#lines + 1] = ("  @%s (%s): %s%s"):format(p.aliases[1] or id, p.label, state,
			#flags > 0 and ("  [" .. table.concat(flags, ", ") .. "]") or "")
	end
	lines[#lines + 1] = ("  %d entries in all"):format(total)
end

-- the game's own measure of Terminal's CPU time, where this client has it
local function CpuLine(lines)
	local P, M = _G.C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
	if P and P.GetAddOnMetric and M and M.RecentAverageTime then
		local ok, mine = pcall(P.GetAddOnMetric, ns.name, M.RecentAverageTime)
		local okAll, all = false, nil
		if P.GetOverallMetric then okAll, all = pcall(P.GetOverallMetric, M.RecentAverageTime) end
		if ok and type(mine) == "number" then
			lines[#lines + 1] = ("Terminal CPU: %.3f ms per frame lately%s"):format(mine,
				(okAll and type(all) == "number" and all > 0) and (" (%.1f%% of all addons)"):format(mine / all * 100) or "")
		end
	end
end

-- what runs on its own right now (nothing, with the terminal and its options closed), and the lists built ahead
local function RunningLine(lines)
	local UI0 = ns.UI
	local running = {}
	if UI0 and UI0.motion and UI0.motion:IsShown() then
		running[#running + 1] = UI0.blinkOnly and "cursor blink (30/s)" or "animation (every frame)"
	end
	if UI0 and UI0.busy and UI0.busy:IsVisible() then running[#running + 1] = "loading spinner" end
	if UI0 and UI0.searchJob then running[#running + 1] = "a search" end
	if ns.Options and ns.Options.preview and ns.Options.preview:IsVisible() then running[#running + 1] = "options example (30/s)" end
	lines[#lines + 1] = "Running now: " .. (#running > 0 and table.concat(running, ", ") or "nothing")
	local W = ns.warm or {}
	if W.started then
		lines[#lines + 1] = W.done and "Lists built ahead of use: done"
			or ("Lists built ahead of use: %d to go"):format(W.queue and #W.queue or #ns.providerOrder)
	end
end

local function SearchLine(lines)
	local UI = ns.UI
	if UI and UI.lastSearchMs then
		local slices = UI.lastSearchSlices or 1
		lines[#lines + 1] = ("Last search: %.1f ms for %d results%s%s"):format(UI.lastSearchMs, UI.lastSearchCount or 0,
			UI.lastSearchNarrowed and " (narrowed from the previous search)" or "",
			slices > 1 and (" (spread over %d frames, about %d ms each)"):format(slices, UI.SLICE_MS or 6) or "")
	end
end

ns:RegisterCommand("mem", {
	desc = "Show Terminal's memory use, entries per kind, and the last search time",
	aliases = { "memory", "perf" },
	run = function()
		local lines = {}
		MemoryLine(lines)
		ProviderLines(lines)
		CpuLine(lines)
		RunningLine(lines)
		SearchLine(lines)
		return lines
	end,
})
