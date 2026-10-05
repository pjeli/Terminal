local ns = select(2, ...)

-- Every registered slash command (SLASH_<NAME><n> globals), searchable with "/".
-- Typing "/reload" or "/term" fuzzy-matches; anything after the first word is passed
-- as arguments, e.g.  "/dnd back in 5"  runs  /dnd back in 5.

local function RunSlash(text)
	local eb = (ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend()) or DEFAULT_CHAT_FRAME.editBox
	ChatEdit_ActivateChat(eb)
	eb:SetText(text)
	ChatEdit_SendText(eb, 1)
	ChatEdit_DeactivateChat(eb)
end
ns.RunSlash = RunSlash

local function RunEntry(e, args)
	local line = e.name
	if args and args ~= "" then line = line .. " " .. args end
	RunSlash(line)
end

local function ChatEntry(e, args)
	local line = e.name .. " "
	if args and args ~= "" then line = line .. args end
	ChatFrame_OpenChat(line)
end

-- /console name value: the game presses it (a line on the secure macro button), so a CVar is set the
-- way typing it in chat sets it, not from Terminal's own (tainted) code. /console isn't always one of
-- the SLASH_ globals (the chat box handles it itself), so its row is added when missing.
local function ConsoleMacro()
	local args = ns.UI and ns.UI.args or ""
	args = args:gsub("^%s+", ""):gsub("%s+$", "")
	if args == "" then return nil end
	return "/console " .. args
end
local CONSOLE_SPEC = { macro = ConsoleMacro }
local function ConsoleNeverOpen() return false end
local function ConsoleAfter() ns:Trace("slash: the game ran /console " .. tostring(ns.UI and ns.UI.args)) end
local function ConsoleDirect(e, args)
	if not args or args == "" then
		ns:Print("Usage: /console <setting> <value> (find settings with @cvar)")
		return
	end
	ns:Print("Couldn't hand /console to the game (in combat?). Try again out of combat.")
end
local function ConsoleEntry(e)
	e.secure, e.isOpen, e.after, e.activate = CONSOLE_SPEC, ConsoleNeverOpen, ConsoleAfter, ConsoleDirect
	e.detail = (e.detail ~= "" and (e.detail .. "  ") or "") .. "set a CVar (@cvar lists them)"
	return e
end

local cached, cachedCount -- the list, and how many handlers SlashCmdList had when it was made

ns:RegisterProvider("slash", {
	label = "Slash",
	color = "ff33ff99",
	aliases = { "slash", "command", "cmd" },
	explicit = true,
	refreshOnOpen = true, -- other addons register commands whenever they load
	collect = function()
		-- walking all of _G is slow: only when a handler was added since (an addon loaded)
		local count = 0
		for _ in pairs(SlashCmdList or {}) do count = count + 1 end
		if cached and count == cachedCount then return cached end
		local groups = {}
		for key, val in pairs(_G) do
			if type(key) == "string" and type(val) == "string" and val:sub(1, 1) == "/" then
				local base, idx = key:match("^SLASH_(.-)(%d+)$")
				if base then
					local g = groups[base] or {}
					groups[base] = g
					g[tonumber(idx)] = val
				end
			end
		end

		local out = {}
		for base, g in pairs(groups) do
			local idxs = {}
			for i in pairs(g) do idxs[#idxs + 1] = i end
			table.sort(idxs)
			local names = {}
			for _, i in ipairs(idxs) do names[#names + 1] = g[i] end
			local alt = {}
			for i = 2, #names do alt[#alt + 1] = names[i] end
			out[#out + 1] = {
				key = base,
				name = names[1],
				icon = "Interface\\Icons\\INV_Misc_Note_01",
				detail = table.concat(alt, "  "),
				text = base:lower() .. " " .. table.concat(alt, " "),
				tip = "Handler: " .. base .. "\nAliases: " .. (#alt > 0 and table.concat(alt, ", ") or "none"),
				activate = RunEntry,
				-- Shift+Enter: drop it in the chat box instead of running it
				secondary = ChatEntry,
			}
		end
		local console
		for _, e in ipairs(out) do if e.name == "/console" then console = e break end end
		if not console then
			console = { key = "CONSOLE", name = "/console", icon = "Interface\\Icons\\INV_Misc_Note_01", detail = "",
				text = "console cvar setting", secondary = ChatEntry }
			out[#out + 1] = console
		end
		ConsoleEntry(console)
		cached, cachedCount = out, count
		return out
	end,
})
