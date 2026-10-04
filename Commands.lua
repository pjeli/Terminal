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
		local lines = { "Terminal commands:" }
		for _, name in ipairs(ns.commandOrder) do
			local c = ns.commands[name]
			lines[#lines + 1] = ("  .%s  -  %s"):format(name, c.desc or "")
		end
		lines[#lines + 1] = "Modes: plain text = search everything, / = slash commands, . = commands, @kind = filter, 3*45g = calculator"
		lines[#lines + 1] = "Keys: Enter open, Shift+Enter the result's other action (use an item, pin only, link, list items...), Ctrl+Enter act but keep the terminal open, Up on an empty prompt = earlier lines (.history), Tab completes commands and their arguments"
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
	run = function() ReloadUI() end,
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
-- search took. For measuring before and after performance changes.
ns:RegisterCommand("mem", {
	desc = "Show Terminal's memory use, entries per kind, and the last search time",
	aliases = { "memory", "perf" },
	run = function()
		local lines = {}
		local upd = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or _G.UpdateAddOnMemoryUsage
		local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or _G.GetAddOnMemoryUsage
		if upd then pcall(upd) end
		local kb = get and select(2, pcall(get, "Terminal"))
		if type(kb) == "number" then
			lines[#lines + 1] = ("Terminal memory: %.0f KB"):format(kb)
		else
			lines[#lines + 1] = "Terminal memory: not reported by this client"
		end
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
		local W = ns.warm or {}
		if W.started then
			lines[#lines + 1] = W.done and "Lists built ahead of use: done"
				or ("Lists built ahead of use: %d to go"):format(W.queue and #W.queue or #ns.providerOrder)
		end
		local UI = ns.UI
		if UI and UI.lastSearchMs then
			local slices = UI.lastSearchSlices or 1
			lines[#lines + 1] = ("Last search: %.1f ms for %d results%s%s"):format(UI.lastSearchMs, UI.lastSearchCount or 0,
				UI.lastSearchNarrowed and " (narrowed from the previous search)" or "",
				slices > 1 and (" (spread over %d frames, about %d ms each)"):format(slices, UI.SLICE_MS or 6) or "")
		end
		return lines
	end,
})
