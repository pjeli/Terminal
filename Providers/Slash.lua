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

-- Every slash line is pressed by the game: the line goes on the secure macro button (as a macro would
-- run it), so a command runs the way typing it in chat runs it, never through Terminal's own (tainted)
-- chat-box route, which protected commands (/console on a protected setting) refuse. RunSlash is only
-- the fallback without a secure button.
local function Line(e, args)
	args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if args == "" then return e.name end
	return e.name .. " " .. args
end

local function SlashMacro(e)
	local line = Line(e, ns.UI and ns.UI.args)
	if e.needsArgs and line == e.name then return nil end -- (/console alone: nothing to set; says so below)
	return line
end
local SLASH_SPEC = { macro = SlashMacro }
local function NeverOpen() return false end -- nothing has to be open first: always pressed
local function SlashAfter(e) ns:Trace("slash: the game ran " .. Line(e, ns.UI and ns.UI.args)) end

local function RunEntry(e, args) RunSlash(Line(e, args)) end

-- /console's fallback never types into the chat box: a protected setting would be refused as Terminal's
local function ConsoleDirect(e, args)
	if not args or args:match("^%s*$") then
		ns:Print("Usage: /console <setting> <value> (find settings with @cvar)")
		return
	end
	ns:Print("Couldn't hand /console to the game (in combat?). Try again out of combat.")
end

local function ChatEntry(e, args)
	local line = e.name .. " "
	if args and args ~= "" then line = line .. args end
	ChatFrame_OpenChat(line)
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
				secure = SLASH_SPEC, isOpen = NeverOpen, after = SlashAfter, -- (the game presses the line)
				activate = RunEntry, -- (no secure button: the chat box)
				-- Shift+Enter: drop it in the chat box instead of running it
				secondary = ChatEntry,
			}
		end
		-- /console isn't always one of the SLASH_ globals (the chat box handles it itself): its row is added when
		-- missing. It needs a setting and a value (@cvar lists them)
		local console
		for _, e in ipairs(out) do if e.name == "/console" then console = e break end end
		if not console then
			console = { key = "CONSOLE", name = "/console", icon = "Interface\\Icons\\INV_Misc_Note_01", detail = "",
				text = "console cvar setting", secure = SLASH_SPEC, isOpen = NeverOpen, after = SlashAfter,
				secondary = ChatEntry }
			out[#out + 1] = console
		end
		console.needsArgs, console.activate = true, ConsoleDirect
		console.detail = (console.detail ~= "" and (console.detail .. "  ") or "") .. "set a CVar (@cvar lists them)"
		cached, cachedCount = out, count
		return out
	end,
})
