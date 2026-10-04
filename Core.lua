local ADDON, ns = ...
_G.Terminal = ns -- public API for other addons

ns.name = ADDON
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

BINDING_HEADER_TERMINAL = "Terminal"
BINDING_NAME_TERMINAL_TOGGLE = "Toggle terminal"

local DEFAULTS = {
	freq = {}, -- usage counts, used to boost frequently picked results
	recent = {}, -- freqKeys of the last things picked, newest first (the terminal's history)
	debug = false, -- .debug on: print blocked actions and Terminal's own steps
	history = {}, -- lines run from the prompt, newest first (Up arrow on an empty prompt)
}

ns.providers = {}
ns.providerOrder = {}
ns.commands = {}
ns.commandOrder = {}

----------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------

--- Lines in the main chat window as system text (what terminal commands answer with).
function ns:Output(lines)
	if type(lines) ~= "table" then return end
	local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
	local r, g, b = 1, 1, 0
	if info then r, g, b = info.r or r, info.g or g, info.b or b end
	local chat = DEFAULT_CHAT_FRAME
	for _, line in ipairs(lines) do
		line = tostring(line)
		if chat and chat.AddMessage then chat:AddMessage(line, r, g, b) else print(line) end
	end
end

function ns:Print(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	print("|cff33ff99Terminal|r: " .. table.concat(parts, " "))
end

function ns.LoadBlizz(addon)
	if C_AddOns.IsAddOnLoaded(addon) then return true end
	pcall(C_AddOns.LoadAddOn, addon)
	return C_AddOns.IsAddOnLoaded(addon)
end

function ns:Bump(freqKey)
	if not freqKey or not self.db then return end
	self.db.freq[freqKey] = (self.db.freq[freqKey] or 0) + 1
	-- history: most recent first, each thing once
	local recent = self.db.recent
	if type(recent) ~= "table" then recent = {}; self.db.recent = recent end
	for i = #recent, 1, -1 do
		if recent[i] == freqKey then table.remove(recent, i) end
	end
	table.insert(recent, 1, freqKey)
	for i = #recent, 41, -1 do recent[i] = nil end
end

----------------------------------------------------------------------
-- Providers
--
-- ns:RegisterProvider("id", {
--     label    = "Items",              -- shown on the right of each row
--     color    = "ff7fb2ff",           -- label colour (AARRGGBB)
--     aliases  = { "item", "bag" },    -- accepted after @ in the terminal
--     events   = { "BAG_UPDATE_DELAYED" }, -- events that invalidate the cache
--     explicit = true,                 -- only searched with @kind (or a mode)
--     lazy     = true,                 -- skipped on empty queries (heavy index)
--     guard    = 1.0,                  -- events within N s of a collect wait until then
--     selfEvents = true,               -- ...or are ignored: collecting fires them itself
--     idleDrop = 600,                  -- free the entries after N s without a search
--     onDrop   = function() end,       -- ...and free whatever else the provider keeps
--     refreshOnOpen = true,            -- re-collect each time the terminal opens
--     noCombat = true,                 -- Enter does nothing in combat (protected actions)
--     busy     = function() return "Indexing..." end, -- still loading: the terminal shows a
--                                      -- spinner with this text on mouse-over (nil: ready)
--     collect  = function() return { entry, ... } end,
-- })
--
-- Entry fields:
--   name (required), key, icon, detail, text (extra searchable text),
--   color (|cffrrggbb prefix for the name), link (hyperlink for tooltip),
--   tip (plain tooltip string), activate = function(entry, args) end,
--   secondary = function(entry, args) end  (Shift+Enter)
----------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local watchers = {}

function ns:WatchEvent(event, provider)
	if not watchers[event] then
		watchers[event] = {}
		if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
			watchers[event] = nil
			return
		end
	end
	table.insert(watchers[event], provider)
end

function ns:RegisterProvider(id, def)
	def.id = id
	def.label = def.label or id
	def.aliases = def.aliases or {}
	def._dirty = true
	if not self.providers[id] then
		table.insert(self.providerOrder, id)
	end
	self.providers[id] = def
	if ns.LocalizeKind then ns.LocalizeKind(def) end -- the game's words for @kind (Locale.lua)
	for _, ev in ipairs(def.events or {}) do
		self:WatchEvent(ev, def)
	end
end

function ns:ResolveProvider(token)
	token = ns.Lower(token)
	if token == "" then return nil end
	for _, id in ipairs(self.providerOrder) do
		local p = self.providers[id]
		if token == id or token == ns.Lower(p.label) then return p end
		for _, a in ipairs(p.aliases) do
			if token == ns.Lower(a) then return p end
		end
	end
	for _, id in ipairs(self.providerOrder) do
		local p = self.providers[id]
		if id:sub(1, #token) == token then return p end
	end
end

function ns:MarkAllDirty()
	for _, p in pairs(self.providers) do p._dirty = true end
end

ns.entriesGen = 0 -- bumped whenever any provider's entries are rebuilt

--- Shared fields for compact entries (big lists): an entry holds only what differs (name,
--- id...), and kind, label, freqKey and anything in `proto` come from its metatable.
--- `lazy` fields are computed on first read (detail strings and the like).
function ns:CompactMeta(p, proto, lazy)
	local label
	return { __index = function(t, k)
		if k == "kind" then return p.id end
		if k == "kindLabel" then
			label = label or ("|c" .. (p.color or "ff7fb2ff") .. p.label .. "|r")
			return label
		end
		if k == "noCombat" then return p.noCombat end
		if k == "freqKey" then return p.id .. ":" .. tostring(rawget(t, "key") or t.name) end
		local f = lazy and lazy[k]
		if f then return f(t) end
		return proto and proto[k]
	end }
end

function ns:GetEntries(p)
	p._usedAt = GetTime()
	if p._dirty or not p._entries then
		local ok, res = pcall(p.collect, p)
		p._collectedAt = GetTime()
		p._dirty = false
		ns.entriesGen = ns.entriesGen + 1
		if ok and type(res) == "table" then
			local clean = {}
			local label = "|c" .. (p.color or "ff7fb2ff") .. p.label .. "|r"
			for _, e in ipairs(res) do
				if type(e.name) == "string" and e.name ~= "" then
					if not rawget(e, "_compact") then
						e.kind = p.id
						if e.noCombat == nil then e.noCombat = p.noCombat end
						e.kindLabel = label
						e.freqKey = p.id .. ":" .. tostring(e.key or e.name)
					end
					if not rawget(e, "_lname") then e._lname = ns.Lower(e.name) end
					-- searchable text is only ever matched in lowercase: keep just that copy
					if e.text then
						e._ltext = ns.Lower(e.text)
						e.text = nil
					end
					clean[#clean + 1] = e
				end
			end
			p._entries = clean
		else
			p._entries = p._entries or {}
			if not p._warned then
				p._warned = true
				self:Print(p.label .. " provider failed: " .. tostring(res))
			end
		end
	end
	return p._entries
end

----------------------------------------------------------------------
-- Terminal commands (the "." mode)
--
-- ns:RegisterCommand("name", {
--     desc = "what it does", aliases = { "n" },
--     run  = function(args, ns) return { "output line", ... } end, -- return lines to
-- })                                                                -- keep the terminal open
----------------------------------------------------------------------

function ns:RegisterCommand(name, def)
	name = name:lower()
	def.name = name
	def.aliases = def.aliases or {}
	if not self.commands[name] then
		table.insert(self.commandOrder, name)
	end
	self.commands[name] = def
end

----------------------------------------------------------------------
-- Events / saved variables
----------------------------------------------------------------------

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		TerminalDB = TerminalDB or {}
		for k, v in pairs(DEFAULTS) do
			if TerminalDB[k] == nil then
				TerminalDB[k] = type(v) == "table" and CopyTable(v) or v
			end
		end
		ns.db = TerminalDB
		return
	elseif event == "PLAYER_LOGIN" then
		-- First run: bind ` (tilde key) to toggle the terminal, or CTRL-` if ` is taken.
		-- Change it any time with:  /term .bind <KEY>
		-- (also once after the rename from WoWTerm: its old key binding is taken over)
		if not ns.db.bindingTerminal then
			ns.db.bindingTerminal = true
			if not GetBindingKey("TERMINAL_TOGGLE") then
				local chosen
				local old = "WOW" .. "TERM_TOGGLE"
				for _, key in ipairs({ "`", "CTRL-`" }) do
					local action = GetBindingAction(key)
					if (not action or action == "" or action == old) and SetBinding(key, "TERMINAL_TOGGLE") then
						chosen = key
						break
					end
				end
				if chosen then
					SaveBindings(GetCurrentBindingSet())
					ns:Print("loaded. Press " .. chosen .. " (or type /term) to open. Rebind with: /term .bind <KEY>")
				else
					ns:Print("loaded. Type /term to open. Both ` and CTRL-` are in use; bind a key with: /term .bind CTRL-SPACE")
				end
			end
		end
		return
	end

	local list = watchers[event]
	if list then
		local now = GetTime()
		for _, p in ipairs(list) do
			local wait = p.guard and p._collectedAt and (p.guard - (now - p._collectedAt)) or 0
			if wait <= 0 then
				p._dirty = true
			elseif not p.selfEvents then
				-- just after a collect: the change still counts, a moment later (a bag update
				-- right after a search used to be dropped, leaving stale counts)
				local at = now
				C_Timer.After(wait, function()
					if not p._collectedAt or p._collectedAt <= at then p._dirty = true end
				end)
			end
		end
	end
end)

-- Big lists nobody searched for a while are freed, and rebuilt when next wanted.
function ns:DropIdle(now)
	now = now or GetTime()
	for _, p in pairs(self.providers) do
		if p.idleDrop and p._entries and p._usedAt and now - p._usedAt > p.idleDrop then
			p._entries, p._dirty = nil, true
			if p.onDrop then pcall(p.onDrop) end
			ns.entriesGen = ns.entriesGen + 1
		end
	end
end
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(60, function() ns:DropIdle() end) end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

SLASH_TERMINAL1 = "/term"
SlashCmdList.TERMINAL = function(msg)
	msg = strtrim(msg or "")
	if msg == "" then
		ns.UI:Toggle()
	else
		ns.UI:Open(msg)
	end
end
