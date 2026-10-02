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
			lines[#lines + 1] = ("  > %s  -  %s"):format(name, c.desc or "")
		end
		lines[#lines + 1] = "Modes: plain text = search everything, / = slash commands, > = commands, @kind = filter"
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
