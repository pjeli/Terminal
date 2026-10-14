local ns = select(2, ...)
local L = ns.L

-- Your own commands (0.50.4, the player's ask): .alias <name> <what it runs> makes .<name> a command of yours, kept for
-- every character (TerminalDB.commandAliases: a new name, nothing of the old .alias kept). What it runs:
--
--   a search or a question   .alias rep durability            .rep: the terminal shows "durability"
--                            .alias mcs molten core > steps   (any search, Simple or Advanced, a chain, a question)
--   a slash command          .alias rl /reload                pressed by the game, as a slash row is (a macro's line)
--   a dot command            .alias th .theme dracula         that command, run
--
-- Words typed after it are added at the end (.rep legs -> "durability legs"), or go where $* stands
-- (.alias wh /w $* hi -> .wh bob: /w bob hi). .alias lists yours; .alias <name> says what it runs; .unalias <name>
-- forgets it. A name that's already a command (or one of its other names) can't be taken.

local A = {}
ns.Aliases = A

A.MAX_DEPTH = 5 -- (an alias running another, and that one another...: stopped here, a loop never runs forever)
local NAME = "^[%w_%-]+$"

local function Store()
	if not ns.db then return nil end
	if type(ns.db.commandAliases) ~= "table" then ns.db.commandAliases = {} end
	return ns.db.commandAliases
end

--- What an alias runs with these words: $* replaced by them, else they're added at the end.
function A.Expand(text, args)
	args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text:find("$*", 1, true) then return ((text:gsub("%$%*", (args:gsub("%%", "%%%%")))):gsub("%s+$", "")) end
	if args == "" then return text end
	return text .. " " .. args
end

local function Kind(text)
	local c = text:sub(1, 1)
	if c == "/" then return "slash" end
	if c == "." then return "dot" end
	return "search"
end
A.Kind = Kind

local depth = 0
-- a dot command's line: that command, run with its words (an alias running an alias, up to MAX_DEPTH)
local function RunDot(line)
	local word, rest = line:match("^%.(%S+)%s*(.-)$")
	local c = word and ns:FindCommand(word)
	if not c then return { L["No command .%s"]:format(tostring(word)) } end
	if depth >= A.MAX_DEPTH then return { L["Aliases run each other too deep: stopped at .%s"]:format(word) } end
	depth = depth + 1
	local ok, res = pcall(c.run, rest or "", ns)
	depth = depth - 1
	if not ok then return { L["Error: %s"]:format(tostring(res)) } end
	return res
end

-- a search's line: the terminal on it (open, it walks there: Shift+Left comes back)
local function ShowSearch(line)
	local UI = ns.UI
	if not UI then return end
	local E = ns.Easy
	-- (Advanced syntax in Simple mode, "@durability is:damaged": Advanced for this one run, as Alt+` makes it)
	local advanced = line:find("[@>|]") or line:find("%a:%S")
	local open = UI:IsShown()
	if not open then UI:Open("") end
	if advanced and E and E.On() then E.temp = { from = line } end
	if open then UI:WalkTo(line) else UI:SetQuery(line, #line) end
end

local function Define(name, text)
	local kind = Kind(text)
	local def = {
		isAlias = true, aliasText = text,
		desc = L["your alias: %s"]:format(text),
	}
	if kind == "search" then
		def.staysOpen = true
		def.run = function(args) ShowSearch(A.Expand(text, args)) end
	elseif kind == "dot" then
		def.run = function(args) return RunDot(A.Expand(text, args)) end
	else
		-- (pressed by the game from the secure macro button, as a slash row's line; without it, or in combat, typed into
		-- the chat box by Terminal, as the slash rows' own fallback)
		def.secure = { macro = function() return A.Expand(text, ns.UI and ns.UI.args) end }
		def.isOpen = ns.Never
		def.after = function() ns:Trace("alias: the game ran " .. A.Expand(text, ns.UI and ns.UI.args)) end
		def.run = function(args) if ns.RunSlash then ns.RunSlash(A.Expand(text, args)) end end
	end
	ns:RegisterCommand(name, def)
end

--- Whether a name is taken by one of Terminal's commands (its name or another name of it), not by an alias.
local function Taken(name)
	local c = ns:FindCommand(name)
	return c ~= nil and not c.isAlias
end

--- Every alias of yours registered as a command (at login; again after a change).
function A.Load()
	for name, c in pairs(ns.commands) do
		if c.isAlias then ns:UnregisterCommand(name) end
	end
	for name, text in pairs(Store() or {}) do
		if type(name) == "string" and type(text) == "string" and name:match(NAME) and not Taken(name) then Define(name, text) end
	end
end

--- Set (text: what it runs) or forget (text nil) an alias: nil and why when it can't be.
function A.Set(name, text)
	name = ns.Lower(name or ""):gsub("^%.", "")
	if not name:match(NAME) then return nil, L["An alias's name is letters, digits, - and _ (.alias rep durability)."] end
	if Taken(name) then return nil, L[".%s is already one of Terminal's commands: pick another name."]:format(name) end
	local store = Store()
	if not store then return nil, L["Not ready yet: try again in a moment."] end
	if text then
		text = text:gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" then return nil, L["What should .%s run? (.alias %s durability)"]:format(name, name) end
		if text:lower():match("^%.%s*" .. name:gsub("%-", "%%-") .. "%f[%s%z]") or text:lower() == "." .. name then
			return nil, L[".%s can't run itself."]:format(name)
		end
		store[name] = text
	else
		if not store[name] then return nil, L["No alias .%s"]:format(name) end
		store[name] = nil
	end
	A.Load()
	return name
end

--- Your aliases, for .alias: { { name, text } } by name.
function A.List()
	local out = {}
	for name, text in pairs(Store() or {}) do out[#out + 1] = { name, text } end
	table.sort(out, function(a, b) return a[1] < b[1] end)
	return out
end

ns:RegisterCommand("alias", {
	desc = L["Your own commands: .alias <name> <a search, /slash or .command> makes .<name> run it; .alias lists them; .unalias <name> forgets one"],
	aliases = { "aliases" },
	complete = function(args)
		local out = {}
		if args:find("%s") then return out end
		for _, a in ipairs(A.List()) do out[#out + 1] = { a[1], a[2] } end
		return out
	end,
	run = function(args)
		local name, text = (args or ""):match("^%s*(%S+)%s*(.-)%s*$")
		if not name then
			local list = A.List()
			if #list == 0 then return { L["No aliases yet: .alias rep durability makes .rep show your durability."] } end
			local lines = { L["Your aliases:"] }
			for _, a in ipairs(list) do lines[#lines + 1] = ("  .%s  ->  %s"):format(a[1], a[2]) end
			return lines
		end
		if text == "" then
			local t = (Store() or {})[ns.Lower(name):gsub("^%.", "")]
			if t then return { (".%s  ->  %s"):format(ns.Lower(name):gsub("^%.", ""), t) } end
			return { L["No alias .%s"]:format(name) }
		end
		local ok, why = A.Set(name, text)
		if not ok then return { why } end
		return { L["Alias .%s runs: %s"]:format(ok, text) }
	end,
})

ns:RegisterCommand("unalias", {
	desc = L["Forget one of your aliases: .unalias <name>"],
	complete = function()
		local out = {}
		for _, a in ipairs(A.List()) do out[#out + 1] = { a[1], a[2] } end
		return out
	end,
	run = function(args)
		local name = (args or ""):match("^%s*(%S+)")
		if not name then return { L["Which alias? .unalias <name> (.alias lists them)"] } end
		local ok, why = A.Set(name, nil)
		if not ok then return { why } end
		return { L["Forgot .%s."]:format(ok) }
	end,
})

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() A.Load() end)
