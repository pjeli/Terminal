-- Terminal Notes: an example of adding your own list to Terminal (docs/PROVIDERS.md walks through it).
--
--   .note buy 20 linen for the bandages   adds a note
--   .note forget linen                     forgets the notes with "linen" in them
--   @note linen  (Simple mode: "linen")    finds it; Enter shows it in your chat window,
--                                          Shift+Enter says it in your party (the game sends it)

local ADDON = ...
local T = _G.Terminal -- Terminal's public table (## Dependencies: Terminal makes sure it's loaded first)
if not (T and T.RegisterProvider) then return end

TerminalNotesDB = TerminalNotesDB or { notes = {} } -- (the saved variable is there once ADDON_LOADED fires; see below)

local function Notes() return TerminalNotesDB.notes end

-- Shift+Enter: the game sends the line in party chat. Terminal hands the macro to the game on your key press (its
-- "secure" route), because addon code may not send chat or do anything protected by itself. 255 characters at most.
local function PartyMacro(e) return ("/p %s"):format(e.name):sub(1, 255) end
local PARTY = { macro = PartyMacro } -- (one table for every row: rows share their functions and specs)

-- Enter: Terminal's own code runs it (here: the note, in your chat window).
local function Show(e) T:Output({ "Note: " .. e.name }) end

-- In combat the game can't be handed the press: Shift+Enter runs this instead.
local function NotInCombat(e) T:Print("In combat: say it in party once the fight is over.") end

T:RegisterProvider("notes", {
	label = "Note", -- (the kind shown on each row, and @note's word)
	color = "ffffe08a", -- (aarrggbb: the kind label's colour; keep it apart from Terminal's own kinds)
	aliases = { "note", "notes" }, -- @note, @notes (the first alias is how Terminal names the list)
	simpleCategory = { id = "notes", label = "Notes", icon = "Interface\\Icons\\INV_Misc_Note_02" }, -- Simple mode
	verbs = { "show in chat", "say in party" }, -- what the footer and the right-click menu say Enter / Shift+Enter do
	explicit = true, -- (only searched with @note or Simple mode's Notes category, not in every plain search)
	collect = function()
		local out = {}
		for i, n in ipairs(Notes()) do
			out[#out + 1] = {
				key = n.t or i, -- (stable across rebuilds: Terminal's history and "picked often" follow it)
				name = n.text, -- (searched, fuzzily, and shown)
				icon = "Interface\\Icons\\INV_Misc_Note_02",
				detail = T.Ago and T.Ago(time() - (n.t or time())) or nil, -- (the grey text on the right)
				tip = "Added " .. date("%d %b %H:%M", n.t or time()), -- (its tooltip)
				activate = Show,
				secondarySecure = PARTY, secondaryIsOpen = T.Never, -- (nothing to open first: always pressed)
				secondary = NotInCombat,
			}
		end
		return out
	end,
})

T:RegisterCommand("note", {
	desc = "Add a note (.note forget <words> forgets the ones with those words)",
	complete = function()
		local out = { { "forget", "forget the notes with these words" } }
		return out
	end,
	run = function(args)
		local text = strtrim(args or "")
		local forget = text:match("^forget%s+(.+)$")
		if forget then
			local kept, gone = {}, 0
			for _, n in ipairs(Notes()) do
				if n.text:lower():find(forget:lower(), 1, true) then gone = gone + 1 else kept[#kept + 1] = n end
			end
			TerminalNotesDB.notes = kept
			T:Changed("notes") -- (no game event tells Terminal the list changed: say so, it's made again when searched)
			return { ("Forgot %d note%s."):format(gone, gone == 1 and "" or "s") }
		end
		if text == "" then return { "Type .note and what to remember." } end
		table.insert(Notes(), 1, { text = text, t = time() })
		T:Changed("notes")
		return { "Noted: " .. text }
	end,
})

-- The saved variable is loaded just before ADDON_LOADED for this addon: keep the notes it holds.
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
	if name ~= ADDON then return end
	TerminalNotesDB = TerminalNotesDB or {}
	TerminalNotesDB.notes = TerminalNotesDB.notes or {}
	T:Changed("notes")
	f:UnregisterEvent("ADDON_LOADED")
end)
