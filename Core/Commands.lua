local ns = select(2, ...)
local L = ns.L

-- Terminal commands: type "." in the terminal. Add your own from any addon:
--   Terminal:RegisterCommand("hello", {
--       desc = "say hello", aliases = { "hi" },
--       run  = function(args, ns) return { "hello " .. args } end,
--   })

ns:RegisterCommand("help", {
	desc = L["How to use Terminal; .help advanced: every command and the Advanced syntax"],
	aliases = { "?", "h" },
	complete = function() return { { "advanced", L["every command and the Advanced syntax"] } } end,
	run = function(args)
		-- (plain sentences; .help advanced, or a line in Advanced mode: the commands and the syntax)
		local want = ns.Lower(tostring(args or "")):gsub("%s+", "")
		local full = want == "advanced" or want == "all" or want == "syntax"
		if not full and ns.Easy and ns.Easy.On() then return ns.Easy.HelpLines() end
		local lines = { L["Terminal commands:"] }
		for _, name in ipairs(ns.commandOrder) do
			local c = ns.commands[name]
			lines[#lines + 1] = ("  .%s  -  %s"):format(name, c.desc or "")
		end
		lines[#lines + 1] = L["Modes: plain text = search everything, / = slash commands, . = commands, @kind = filter, 3*45g = calculator"]
		lines[#lines + 1] = L["Filters (add to a search, .filters for all): lvl:20-30  q:rare+  stat:stamina  slot:wrist  in:bank  is:todo  is:usable"]
		lines[#lines + 1] = L["Send a result to chat with  >>  :  hearthstone >> party   @npc hogger >> guild   copper bar >> w Name"]
		lines[#lines + 1] = L["Every result at once with  >>>  :  mats for thorium belt >>> party   @loot lorgus jett >>> guild"]
		lines[#lines + 1] = L["To copy and paste elsewhere:  >> text  (the selected result),  >>> text  or  >>> csv  (every result): they open in a box, Ctrl+C copies"]
	lines[#lines + 1] = L["Drop quests with  >> drop  (the selected one)  and  >>> drop  (every quest listed), Terminal asking first:  @quest is:drop >>> drop"]
		lines[#lines + 1] = L["Words in quotes are found together, as they are: \"outlaw saber\" (in:\"elwynn forest\" too)"]
		lines[#lines + 1] = L["Sum up what a search found with a | standing alone:  in:bags | sum value  (what it sells for),  @quest | group by zone,  @item | count by quality,  in:bags | sum value by quality;  Enter on a group lists its rows"]
		lines[#lines + 1] = L["Chains: thorium belt > mats, copper bar > uses, thorium bar > sources, thorium belt > learn (.chains); plain words work too: mats for thorium belt, where to learn thorium belt"]
		lines[#lines + 1] = L["Guildies by what they do: @guild blacksmith, @guild priest is:online (Enter whispers, Shift+Enter invites)"]
		lines[#lines + 1] = L["Ask in plain words: where should i level, what dungeon should i do, where should i fish, what killed me, what dropped, spells not on my bars (@spell is:unplaced), quests to drop (@quest is:drop; is:grey, is:leftbehind), recipes i'm missing (@recipe is:unknown; recipes i can learn now: is:learnable), my mail / mail running out (@mail is:expiring; is:cod, is:money, is:unread; is:sent: the last hour's), who is dead / who needs fortitude / who is out of range (@group is:dead, missing:fortitude|consumables, is:far, is:healer; @group >>> party: what's missing, in one line), party quests / quests to share (@group quests; is:shareable, is:together; Enter shares; >>> party: the same quests and what you can share, in one line)"]
		lines[#lines + 1] = L["Your auctions: my auctions / what am i selling (@auction: every character's auctions up now with price and time left, and the auction house's news; is:incoming: only the news)"]
		lines[#lines + 1] = L["Lockouts and levelling: my lockouts / raid lockouts (@lockout is:raid; is:dungeon, on:<character>), blacksmithing plan / level blacksmithing (@recipe blacksmithing sort:plan: the recipes that still give skill, by how many times your materials make each; the footer says the points)"]
		lines[#lines + 1] = L["The calendar: holidays / what's on this week / next darkmoon faire / my invites (@calendar is:holiday, is:invite, when:week; when:today, tomorrow, weekend, nextweek, month, nextmonth)"]
		lines[#lines + 1] = L["Flight paths you haven't learned: @flight is:unlearned sort:nearest (in plain words: nearest unlearned flight master); a flight master's map tells Terminal which you know"]
		lines[#lines + 1] = L["do:use / do:cast / do:summon... make Enter that action (Simple mode's action words): @items do:use hearthstone"]
		lines[#lines + 1] = L["Shift+Right at the end of the prompt writes the selected result into it (@npc Thrall), to build on; right-click a result for everything it can do"]
		lines[#lines + 1] = L["Tab+` (hold Tab, press `) is pure fuzzy finding over every list, by name; Alt+click a link in chat to look it up here"]
		lines[#lines + 1] = L["Upgrades: @loot is:upgrade sort:best (what you can get that beats what you wear, the biggest first; the tooltip says why); @questie is:upgrade sort:best: quests whose reward is one"]
		lines[#lines + 1] = L["F5: a list that changed while you looked at it (your bags, item data coming in) stays put, the footer saying so; F5 shows the new one"]
		lines[#lines + 1] = L["Keys: Enter does the row's action and Shift+Enter its other one (the footer says which), Ctrl+Enter act but keep the terminal open (a window it opens still closes it), Up on an empty prompt = earlier lines (.history), Down = your recent picks, Tab completes (with nothing to complete: the next result), Shift+Left goes back a step; F1 (or .keybinds) shows every key, for each mode"]
		return lines
	end,
})

ns:RegisterCommand("filters", {
	desc = L["List search filters (add them to a search: @loot stat:stamina q:rare+)"],
	aliases = { "filter" },
	run = function()
		local lines = { L["Search filters (key:value, add to any search; Tab completes values):"] }
		for _, h in ipairs(ns.Filters and ns.Filters.HELP or {}) do
			lines[#lines + 1] = ("  %s  -  %s"):format(h[1], h[2])
		end
		lines[#lines + 1] = L["Examples: @loot stat:stamina q:rare+ lvl:20-30   @stored on:plamen in:bank   @npc is:vendor in:ashenvale   @questie is:todo lvl:20-25"]
		return lines
	end,
})

ns:RegisterCommand("kinds", {
	desc = L["List searchable kinds (use with @kind)"],
	aliases = { "providers" },
	run = function()
		local lines = { L["Searchable kinds:"] }
		for _, id in ipairs(ns.providerOrder) do
			local p = ns.providers[id]
			if not p.noKind then -- (a list no @ names is reached by a filter: "@recipe is:unknown")
				local flags = {}
				if p.explicit then flags[#flags + 1] = L["explicit"] end
				if p.lazy then flags[#flags + 1] = L["lazy"] end
				lines[#lines + 1] = ("  %s  (%s)%s"):format(ns:KindName(p), p.label,
					#flags > 0 and ("  [" .. table.concat(flags, ", ") .. "]") or "")
			end
		end
		return lines
	end,
})

ns:RegisterCommand("reload", {
	desc = L["Reload the UI"],
	aliases = { "rl" },
	-- (not a protected call: run from here, no game press needed; 0.50.7, review: command rows can carry one now, see
	-- UI:CommandEntries and the /slash aliases)
	run = function()
		local reload = (C_UI and C_UI.Reload) or ReloadUI
		if reload then reload() end
	end,
})

ns:RegisterCommand("refresh", {
	desc = L["Rebuild all search indexes"],
	run = function()
		ns:MarkAllDirty()
		return { L["Indexes will rebuild on next search."] }
	end,
})

ns:RegisterCommand("bind", {
	desc = L["Bind a key to toggle the terminal, e.g. .bind CTRL-SPACE"],
	run = function(args)
		args = strtrim(args or ""):upper()
		if args == "" then
			return { L["Usage: .bind CTRL-SPACE"], L["Current: %s"]:format(GetBindingKey("TERMINAL_TOGGLE") or L["none"]) }
		end
		if InCombatLockdown() then return { L["Keys can't be bound in combat; try .bind again after."] } end
		if SetBinding(args, "TERMINAL_TOGGLE") then
			SaveBindings(GetCurrentBindingSet())
			return { L["Terminal toggle bound to %s"]:format(args) }
		end
		return { L["Could not bind %s"]:format(args) }
	end,
})

ns:RegisterCommand("forget", {
	desc = L["Clear learned usage ranking"],
	aliases = { "reset" },
	run = function()
		wipe(ns.db.freq)
		if ns.db.recent then wipe(ns.db.recent) end -- (the recent picks shown on an empty prompt are learned usage too)
		ns.db.catPicks = nil -- (and the categories picked for words in Simple mode)
		ns.freqKinds = nil
		return { L["Usage history cleared."] }
	end,
})

ns:RegisterCommand("clear", {
	desc = L["Clear highlights"],
	run = function()
		ns.Highlight:Clear()
		return { L["Highlights cleared."] }
	end,
})

ns:RegisterCommand("about", {
	desc = L["Version info"],
	run = function()
		return { "Terminal " .. ns.version, L["Providers: %d  Commands: %d"]:format(#ns.providerOrder, #ns.commandOrder) }
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
		lines[#lines + 1] = L["Terminal memory: %.0f KB"]:format(kb)
	else
		lines[#lines + 1] = L["Terminal memory: not reported by this client"]
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
			state = L["%d entries"]:format(n)
		else
			state = L["not built"] .. (p.idleDrop and (" " .. L["(freed when idle)"]) or "")
		end
		local flags = {}
		if p.explicit then flags[#flags + 1] = p.noKind and L["only through that filter"] or L["only with @"] end
		if p.lazy then flags[#flags + 1] = L["skipped on empty searches"] end
		if n and p._usedAt then flags[#flags + 1] = L["used %ds ago"]:format(math.floor(now - p._usedAt)) end
		lines[#lines + 1] = ("  %s (%s): %s%s"):format(ns:KindName(p) or id, p.label, state,
			#flags > 0 and ("  [" .. table.concat(flags, ", ") .. "]") or "")
	end
	lines[#lines + 1] = "  " .. L["%d entries in all"]:format(total)
end

-- the game's own measure of Terminal's CPU time, where this client has it
local function CpuLine(lines)
	local P, M = _G.C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
	if P and P.GetAddOnMetric and M and M.RecentAverageTime then
		local ok, mine = pcall(P.GetAddOnMetric, ns.name, M.RecentAverageTime)
		local okAll, all = false, nil
		if P.GetOverallMetric then okAll, all = pcall(P.GetOverallMetric, M.RecentAverageTime) end
		if ok and type(mine) == "number" then
			lines[#lines + 1] = L["Terminal CPU: %.3f ms per frame lately%s"]:format(mine,
				(okAll and type(all) == "number" and all > 0) and (" " .. L["(%.1f%% of all addons)"]:format(mine / all * 100)) or "")
		end
	end
end

-- what runs on its own right now (nothing, with the terminal and its options closed), and the lists built ahead
local function RunningLine(lines)
	local UI0 = ns.UI
	local running = {}
	if UI0 and UI0.motion and UI0.motion:IsShown() then
		running[#running + 1] = UI0.blinkOnly and L["cursor blink (30/s)"] or L["animation (every frame)"]
	end
	if UI0 and UI0.busy and UI0.busy:IsVisible() then running[#running + 1] = L["loading spinner"] end
	if UI0 and UI0.searchJob then running[#running + 1] = L["a search"] end
	if ns.Options and ns.Options.preview and ns.Options.preview:IsVisible() then running[#running + 1] = L["options example (30/s)"] end
	lines[#lines + 1] = L["Running now: %s"]:format(#running > 0 and table.concat(running, ", ") or L["nothing"])
	local W = ns.warm or {}
	if W.started then
		lines[#lines + 1] = W.done and L["Lists built ahead of use: done"]
			or L["Lists built ahead of use: %d to go"]:format(W.queue and #W.queue or #ns.providerOrder)
	end
end

local function SearchLine(lines)
	local UI = ns.UI
	if UI and UI.lastSearchMs then
		local slices = UI.lastSearchSlices or 1
		lines[#lines + 1] = L["Last search: %.1f ms for %d results%s%s"]:format(UI.lastSearchMs, UI.lastSearchCount or 0,
			UI.lastSearchNarrowed and (" " .. L["(narrowed from the previous search)"]) or "",
			slices > 1 and (" " .. L["(spread over %d frames, about %d ms each)"]:format(slices, UI.SLICE_MS or 6)) or "")
	end
end

ns:RegisterCommand("mem", {
	desc = L["Show Terminal's memory use, entries per kind, and the last search time"],
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
