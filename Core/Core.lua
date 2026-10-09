local ADDON, ns = ...
_G.Terminal = ns -- public API for other addons

ns.name = ADDON
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

BINDING_HEADER_TERMINAL = "Terminal"
BINDING_NAME_TERMINAL_TOGGLE = "Toggle terminal"
BINDING_NAME_TERMINAL_ADVANCED_ONCE = "Advanced mode, this time (Simple mode's search as a command line)"
BINDING_NAME_TERMINAL_FUZZY = "Fuzzy find, this time (every list, by name only)"

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

--- What of this kind was ever picked: { [key] = times } (its freqKeys "kind:key", the key also as a number when it is
--- one, so a compact row's own key looks it up without building a string), or false. Lets scoring skip compact rows
--- of kinds nobody picked, and read the rest without making "kind:key" per row.
function ns:FreqKind(kind)
	local kinds = self.freqKinds
	if not kinds then
		kinds = {}
		for k, n in pairs(self.db and self.db.freq or {}) do
			local id, key = nil, nil
			if type(k) == "string" then id, key = k:match("^([^:]+):(.*)$") end
			if id then
				local t = kinds[id]
				if not t then t = {}; kinds[id] = t end
				t[key] = n
				local num = tonumber(key)
				if num and tostring(num) == key then t[num] = n end
			end
		end
		self.freqKinds = kinds
	end
	return kinds[kind] or false
end

--- Put a link in the chat box: into the text being typed when the box is open, else the box opens with it.
function ns.LinkInChat(link)
	if type(link) ~= "string" or link == "" then return false end
	if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return true end
	if ChatFrame_OpenChat then ChatFrame_OpenChat(link) return true end
	return false
end

--- A line the game runs that opens the chat box with `text` a moment after the press ("|" written as \124), or nil
--- when too long (or nothing). Use it rather than ns.LinkInChat wherever a press can carry it: the chat box's code is
--- Blizzard Lua, and Terminal's code running it would taint what it writes (see CLAUDE.md, delayed taint).
function ns.ChatBoxMacro(text)
	if type(text) ~= "string" or text == "" then return nil end
	local lit = text:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("|", "\\124")
	-- (into what's being typed when the box is open, as ns.LinkInChat does; else the box opened with it)
	local run = "/run C_Timer.After(.1,function() local t=\"" .. lit .. "\" if not ChatEdit_InsertLink(t) then ChatFrame_OpenChat(t) end end)"
	local max = ns.Secure and ns.Secure.MACRO_MAX or 255
	return #run <= max and run or nil
end

--- Always false: the `isOpen` of a result that is always pressed (nothing has to be open first), shared.
function ns.Never() return false end
ns.ChatBoxNeverOpen = ns.Never -- (the chat box spec's: always pressed)

--- A secure spec (Shift+Enter's) that has the game open the chat box with textOf(e): `secondarySecure = ns.ChatBoxSpec(f)`.
function ns.ChatBoxSpec(textOf)
	return { macro = function(e)
		local ok, t = pcall(textOf, e)
		return ok and ns.ChatBoxMacro(t) or nil
	end }
end

function ns:Bump(freqKey)
	if not freqKey or not self.db then return end
	self.db.freq[freqKey] = (self.db.freq[freqKey] or 0) + 1
	self.freqKinds = nil
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
--     refreshOnOpen = true,            -- re-collect each time the terminal opens (a number: when older than that, s)
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
	self:AliasesChanged()
	for _, ev in ipairs(def.events or {}) do
		self:WatchEvent(ev, def)
	end
end

--- Call after adding to a provider's aliases once it's registered: the @kind lookup is rebuilt.
function ns:AliasesChanged() self.aliasMap = nil end

--- Every lowercase word that names a provider after @ (its id, label and aliases), the first
--- registered keeping a word two of them share. Built once, not lowercased on every lookup.
local function AliasMap(self)
	local map = {}
	for _, id in ipairs(self.providerOrder) do
		local p = self.providers[id]
		local function put(word) word = ns.Lower(word); if not map[word] then map[word] = p end end
		put(id)
		put(p.label)
		for _, a in ipairs(p.aliases) do put(a) end
	end
	self.aliasMap = map
	return map
end

function ns:ResolveProvider(token)
	token = ns.Lower(token)
	if token == "" then return nil end
	local p = (self.aliasMap or AliasMap(self))[token]
	if p then return p end
	-- (a kind named by the start of its id: the first in order, unless another's id is the start of that one's:
	-- "@loo" is @loot, not @lootlog, though the loot log registered first)
	local best
	for _, id in ipairs(self.providerOrder) do
		if id:sub(1, #token) == token and (not best or (#id < #best and best:sub(1, #id) == id)) then best = id end
	end
	return best and self.providers[best] or nil
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
	-- a list made from another one (@gear, @consumable, @mats from your items) is made again whenever
	-- that one was: its own events alone left it stale (gear in your bags missing, built before they loaded)
	if p.follows then
		local src = self.providers[p.follows]
		local list = src and self:GetEntries(src)
		if list ~= p._followed then p._dirty, p._followed = true, list end
	end
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
					local text = rawget(e, "text") -- (compact rows have none: no __index call)
					if text then
						e._ltext = ns.Lower(text)
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
		ns:StartPrewarm(10) -- the lists, built ahead of their first search (see Prewarming)
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
		-- Alt+` (once): Advanced mode for one run. While the terminal is open it reads that key itself; the
		-- binding opens it straight in Advanced. Only on a free key, never taking another action's.
		if not ns.db.bindingAdvancedOnce then
			ns.db.bindingAdvancedOnce = true
			local action = GetBindingAction("ALT-`")
			if not GetBindingKey("TERMINAL_ADVANCED_ONCE") and (not action or action == "")
				and SetBinding("ALT-`", "TERMINAL_ADVANCED_ONCE") then
				SaveBindings(GetCurrentBindingSet())
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
				-- one timer per provider, however many events come in meanwhile
				p._pendingAt = now
				if not p._pendingTimer then
					p._pendingTimer = true
					C_Timer.After(wait, function()
						p._pendingTimer = nil
						if not p._collectedAt or p._collectedAt <= p._pendingAt then p._dirty = true end
					end)
				end
			end
		end
	end
end)

-- Prewarming: after login, every list is built ahead of its first search, one per second while
-- nothing else is going on (out of combat, the terminal closed). A list still loading (Questie's
-- NPCs, AtlasLoot) waits its turn and is built once it's in. Lists freed when unused (idleDrop)
-- are built again only when next wanted.
local warm = {}
ns.warm = warm

local function Busy(p)
	if not p.busy then return nil end
	local ok, msg = pcall(p.busy, p)
	return ok and type(msg) == "string" and msg ~= "" and msg or nil
end

--- Builds the next list. True while there's more to do.
function ns:PrewarmStep()
	if not self.db then return true end
	if InCombatLockdown() or (self.UI and self.UI.IsShown and self.UI:IsShown()) then return true end -- later
	if (self.background or 0) > 0 then return true end -- (Questie's lists still indexing: not on top of that)
	local q = warm.queue
	if not q then
		q, warm.tries, warm.seen = {}, {}, 0
		warm.queue = q
	end
	-- providers registered since the queue was made (AtlasLoot's, late) are queued too. Left out:
	-- lists that rebuild on every open anyway, and the huge ones freed when unused (Questie, NPCs,
	-- maps...: built at every login and thrown away 10 minutes later otherwise)
	local order = self.providerOrder
	for i = warm.seen + 1, #order do
		local p = self.providers[order[i]]
		if not p.refreshOnOpen and not p.idleDrop then q[#q + 1] = order[i] end
	end
	warm.seen = #order
	while #q > 0 do
		local id = table.remove(q, 1)
		local p = self.providers[id]
		if p and (p._dirty or not p._entries) then
			if Busy(p) then
				-- still loading: back of the queue (for a few minutes at most)
				warm.tries[id] = (warm.tries[id] or 0) + 1
				if warm.tries[id] < 300 then q[#q + 1] = id end
				return true
			end
			local t0 = debugprofilestop and debugprofilestop()
			self:GetEntries(p)
			-- your bags' consumables: their effect text asked for now, so "stamina food" has it at the first search
			if id == "items" and self.Filters and self.Filters.WarmEffects then pcall(self.Filters.WarmEffects, p._entries) end
			if Busy(p) then q[#q + 1] = id end -- reading it started its loading (Questie's index): again once in
			if self.Trace then
				self:Trace(("prewarm: @%s ready, %d entries%s"):format(id, p._entries and #p._entries or 0,
					t0 and (", %.1f ms"):format(debugprofilestop() - t0) or ""))
			end
			if #q == 0 then warm.done = true end
			return #q > 0
		end
	end
	warm.done = true
	return false
end

function ns:StartPrewarm(delay)
	if warm.started then return end
	warm.started = true
	local function tick()
		if ns:PrewarmStep() then C_Timer.After(1, tick) end
	end
	C_Timer.After(delay or 10, tick)
end

-- Big lists nobody searched for a while are freed, and rebuilt when next wanted.
function ns:DropIdle(now)
	now = now or GetTime()
	for _, p in pairs(self.providers) do
		-- (held: a list a provider keeps itself, built in the background without a search: Questie's NPCs)
		local held = p._entries or (p.held and p.held(p))
		if p.idleDrop and held and p._usedAt and now - p._usedAt > p.idleDrop then
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
