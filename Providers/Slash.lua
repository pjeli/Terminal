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

ns:RegisterProvider("slash", {
	label = "Slash",
	color = "ff33ff99",
	aliases = { "slash", "command", "cmd" },
	explicit = true,
	refreshOnOpen = true, -- other addons register commands whenever they load
	collect = function()
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
		return out
	end,
})
