local ns = select(2, ...)

----------------------------------------------------------------------
-- CVars (@cvar): the game's console settings, with their value and default. Many settings the
-- options panel never shows live only here. Enter puts "/console <name> <value>" in the prompt to
-- edit; running that line has the game set it (see Slash.lua). Shift+Enter: the same with its default.
----------------------------------------------------------------------

local CHANGED = "|cffffd200"

local function Plain(v)
	if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
	return tostring(v)
end

-- Enum.ConsoleCategory's names, by number: "Graphics", "Sound"...
local categories
local function Category(n)
	if not categories then
		categories = {}
		for k, v in pairs(Enum.ConsoleCategory or {}) do categories[v] = k end
	end
	return categories[n]
end

local function CVarLine(e, value)
	local line = "/console " .. e.name .. " " .. (value or "")
	ns.UI:SetQuery(line, #line)
end
local function EditCVar(e) CVarLine(e, Plain(C_CVar.GetCVar(e.name)) or e.value) end
local function DefaultCVar(e) CVarLine(e, e.default) end

-- Terminal's list of names (CVarList.lua), read once: name -> { category, help }, and the names in order
local known, knownOrder
local function Known()
	if not known then
		known, knownOrder = {}, {}
		for name, cat, help in (ns.CVAR_LIST or ""):gmatch("([^\t\n]+)\t([^\t\n]*)\t([^\n]*)") do
			known[name] = { tonumber(cat), help }
			knownOrder[#knownOrder + 1] = name
		end
	end
	return known, knownOrder
end

--- A setting's value and default, and whether it's read-only / protected; nil value: not a setting here.
local function Read(name)
	local value, default, readOnly, secure
	local info, get = C_CVar and C_CVar.GetCVarInfo, C_CVar and C_CVar.GetCVar
	if info then
		local ok, v, d, _, _, locked, sec, ro = pcall(info, name)
		if ok then value, default, readOnly, secure = Plain(v), Plain(d), (ro or locked) and true or false, sec and true or false end
	end
	if value == nil and get then
		local ok, v = pcall(get, name)
		value = ok and Plain(v) or nil
	end
	if value ~= nil and default == nil and C_CVar.GetCVarDefault then
		local ok, d = pcall(C_CVar.GetCVarDefault, name)
		default = ok and Plain(d) or nil
	end
	return value, default, readOnly, secure
end

--- The row's value, detail, colour and searchable text, from its current value.
local function Fill(e, value, default)
	e.value, e.default = value, default
	e.changed = value ~= nil and default ~= nil and value ~= default
	e.color = e.changed and CHANGED or nil
	e.detail = "= " .. (value or "?") .. (e.changed and ("  (default " .. default .. ")") or "")
		.. (e.readOnly and "  read-only" or "") .. (e.cat and ("  " .. e.cat) or "")
	e._ltext = ns.Lower(e.help .. " " .. (e.cat or "") .. (e.changed and " changed" or ""))
end

-- the tooltip, made when hovered (not for every one of ~1650 rows up front)
local function Tooltip(e, t)
	t:SetText(e.name, 1, 1, 1)
	if e.help ~= "" then t:AddLine(e.help, 0.8, 0.8, 0.8, true) end
	t:AddDoubleLine("Value", tostring(e.value or "?"), 1, 0.82, 0, 1, 1, 1)
	t:AddDoubleLine("Default", tostring(e.default or "?"), 1, 0.82, 0, 1, 1, 1)
	if e.readOnly then t:AddLine("Read-only: the game won't let it be changed", 1, 0.4, 0.4, true) end
	if e.secure then t:AddLine("Protected: can't be changed in combat", 1, 0.6, 0.3, true) end
	t:AddLine(" ")
	t:AddLine("Enter: edit it    Shift+Enter: back to its default", 0.6, 0.6, 0.6, true)
end

--- The names to look up: { name, category, help } each (the last two only from the game's list), where they came
--- from (for the trace), whether the game's own call worked, and Terminal's list (name -> { category, help }).
local function CVarNames()
	-- the game's own list, when it gives one (WoW Forever doesn't let addons have it)
	local ok, all = false, nil
	for _, fn in ipairs({ C_Console and C_Console.GetAllCommands or false, _G.ConsoleGetAllCommands or false }) do
		if fn then
			ok, all = pcall(fn)
			if ok and type(all) == "table" and #all > 0 then break end
		end
	end
	all = ok and type(all) == "table" and all or {}
	local kn, order = Known()
	local from = #all > 0 and "the game's list" or "Terminal's list"
	local names = {}
	if #all > 0 then
		for _, c in ipairs(all) do
			local name = type(c) == "table" and Plain(c.command)
			if name then names[#names + 1] = { name, c.category, Plain(c.help) } end
		end
	else
		-- otherwise the names Terminal knows, each looked up in the game below
		for _, name in ipairs(order) do names[#names + 1] = { name } end
	end
	return names, from, ok, kn
end

local byName = {} -- setting name -> its row (CVAR_UPDATE updates just that row)
ns.CVars = { Edit = EditCVar, Default = DefaultCVar, Rows = function() return byName end }

ns:RegisterProvider("cvars", {
	label = "CVar",
	color = "ff8ec5ff",
	aliases = { "cvar", "cvars", "console" }, -- ("settings" is the options panel's, GameOptions.lua)
	explicit = true, -- a few thousand: only with @cvar
	lazy = true,
	idleDrop = 600,
	onDrop = function() byName = {} end,
	collect = function(p)
		local out = {}
		byName = {}
		local names, from, ok, kn = CVarNames()
		for _, n in ipairs(names) do
			local name = n[1]
			-- a setting is whatever has a value: the command type isn't trusted (ClassicUIForever doesn't
			-- either), and console commands (reloadui...) have none
			local value, default, readOnly, secure = Read(name)
			if value ~= nil then
				local k = kn[name]
				local help = (n[3] and n[3] ~= "" and n[3]) or (k and k[2]) or ""
				local e = {
					key = name, name = name, help = help, cat = Category(n[2] or (k and k[1])),
					readOnly = readOnly, secure = secure,
					icon = "Interface\\Icons\\INV_Misc_Gear_01",
					tooltip = Tooltip,
					staysOpen = true, -- only fills the prompt in: you edit, then Enter runs it
					activate = EditCVar,
					secondary = DefaultCVar,
				}
				Fill(e, value, default)
				out[#out + 1] = e
				byName[name] = e
			end
		end
		ns:Trace(("cvars: %s: %d names (the game's own call %s), %d settings this client has"):format(from, #names, ok and "ok" or "failed", #out))
		if #out == 0 then
			-- the list can come back empty early on: ask again on the next search, and say what happened
			C_Timer.After(1, function() p._dirty = true end)
			out[1] = { key = "none", name = "No console settings could be read yet", raw = true, noActivate = true, icon = false,
				detail = ("%d names from %s, none with a value"):format(#names, from), text = "" }
		end
		return out
	end,
})

-- A setting changed (yours, the options panel's, an addon's: the camera's change often): just its row is
-- updated, not the whole list made again. A change without a name marks the list to be made again.
local cvarWatch = CreateFrame("Frame")
ns.CVars.watch = cvarWatch
pcall(cvarWatch.RegisterEvent, cvarWatch, "CVAR_UPDATE")
cvarWatch:SetScript("OnEvent", function(_, _, name)
	local p = ns.providers.cvars
	if not (p and p._entries) then return end
	local e = type(name) == "string" and byName[name]
	if not e then
		if type(name) ~= "string" then p._dirty = true end
		return
	end
	local value, default = Read(name)
	if value ~= e.value or default ~= e.default then
		Fill(e, value, default)
		ns.entriesGen = ns.entriesGen + 1 -- (searches narrowed from the last one see the new value)
	end
end)
