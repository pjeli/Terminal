local T = ...
-- docs/example/TerminalNotes: the example of another addon adding its own list to Terminal (docs/PROVIDERS.md). Loaded
-- here as the game would load it (after Terminal), and used through Terminal's public table only.
local ns, UI, check = T.ns, T.UI, T.check

io.write("[example: another addon's list]\n")
do
	local path = "docs/example/TerminalNotes/TerminalNotes.lua"
	local chunk = loadfile(path) or loadfile("Terminal/" .. path)
	check(chunk ~= nil, "the example loads")
	if chunk then
		check(_G.Terminal == ns, "Terminal's public table is its namespace")
		local easyWas = ns.db.easyMode
		_G.TerminalNotesDB = nil
		_G.date = _G.date or os.date -- (the game has date(); the mock doesn't)
		chunk("TerminalNotes", {})
		local p = ns.providers.notes
		check(p and ns:ResolveProvider("note") == p, "its list is registered: @note")
		-- the saved variable arrives, then ADDON_LOADED
		_G.TerminalNotesDB = { notes = {} }
		local out = ns:FindCommand("note").run("buy 20 linen for the bandages")
		check(out[1] == "Noted: buy 20 linen for the bandages" and #TerminalNotesDB.notes == 1, ".note adds one: " .. tostring(out[1]))
		ns:FindCommand("note").run("ask Ann about the dungeon")
		ns.db.easyMode = false
		local res = UI:Search("@note linen")
		check(#res == 1 and res[1].name == "buy 20 linen for the bandages" and res[1].kind == "notes", "@note linen finds it")
		local e = res[1]
		local outWas, shown = ns.Output, nil
		ns.Output = function(_, lines) shown = lines end
		e.activate(e)
		ns.Output = outWas
		check(type(shown) == "table" and shown[1] == "Note: buy 20 linen for the bandages", "Enter: shown in your chat window")
		local r = ns.Secure.Resolve(e.secondarySecure, e)
		check(r and r.macro == "/p buy 20 linen for the bandages", "Shift+Enter: the game says it in party: " .. tostring(r and r.macro))
		local enter, shift = ns.Easy.Verbs(e)
		check(enter == "show in chat" and shift == "say in party", "its verbs, for the footer and the menu: " .. tostring(enter) .. "/" .. tostring(shift))
		-- Simple mode: its own category
		ns.db.easyMode = true
		check(ns.Easy.BY_ID.notes and ns.Easy.BY_ID.notes.kinds[1] == "notes" and ns.Easy.CategoryOf(e) == "notes",
			"Simple mode: a Notes category")
		local found = false
		for _, row in ipairs(UI:Search("linen")) do
			if row.catId == "notes" or row.kind == "notes" then found = true end
		end
		check(found, "Simple mode: \"linen\" finds it in Notes")
		-- forgetting: the list is made again (Terminal:Changed)
		out = ns:FindCommand("note").run("forget linen")
		ns.db.easyMode = false
		check(out[1] == "Forgot 1 note." and #UI:Search("@note linen") == 0 and #UI:Search("@note ann") == 1, ".note forget: gone from the list")
		-- tidy up: the example's list, command and category leave the other tests alone
		ns.providers.notes = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "notes" then table.remove(ns.providerOrder, i) end end
		ns:AliasesChanged()
		ns.commands.note = nil
		for i = #ns.commandOrder, 1, -1 do if ns.commandOrder[i] == "note" then table.remove(ns.commandOrder, i) end end
		for i = #ns.Easy.CATEGORIES, 1, -1 do if ns.Easy.CATEGORIES[i].id == "notes" then table.remove(ns.Easy.CATEGORIES, i) end end
		ns.Easy.BY_ID.notes, ns.Easy.VERBS.notes = nil, nil
		_G.TerminalNotesDB = nil
		ns.db.easyMode = easyWas
	end
end
