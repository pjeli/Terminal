local ns = select(2, ...)
local L = ns.L
local H = ns.Highlight

-- Other addons' options (@addonoption, @addonoptions; Simple mode: under Settings; 0.50.3, the player's ask): every
-- setting an addon registers through Ace3 (AceConfigRegistry: Questie, Attune, AtlasLoot, Details and most others),
-- searchable by its name, its description and the groups it's in: "questie map icons", "attune announce".
--
--   Enter        that addon's options in Ace3's own window (AceConfigDialog: an addon's frame, never the game's Settings
--                panel, which Terminal's code would taint), open on the setting's group, pointing at the setting
--   Shift+Enter  an on/off setting: turned on or off right there, as its checkbox would (not one that asks first, checks
--                what you set, or is greyed out)
--
-- Read when first searched and again when an addon says its options changed (AceConfigRegistry's ConfigTableChange) or one
-- loads; only what the window would show (hidden ones left out). Each addon's own code answers for its names and values,
-- called as Ace3 calls it.

local AO = {}
ns.AddonOptions = AO

local Str, Lower = ns.Str, ns.Lower

AO.MAX_PER_APP, AO.MAX = 3000, 10000
AO.DEPTH = 10
local DIALOG = "AceConfigDialog-3.0"

local function Lib(name)
	local LS = _G.LibStub
	if type(LS) ~= "table" and type(LS) ~= "function" then return nil end
	local ok, lib = pcall(LS, name, true)
	return ok and type(lib) == "table" and lib or nil
end
local function Registry() return Lib("AceConfigRegistry-3.0") end
local function Dialog() return Lib("AceConfigDialog-3.0") end
AO.Registry, AO.Dialog = Registry, Dialog

-- text without the game's colour, texture and link codes
local function Plain(s)
	if type(s) ~= "string" then return nil end
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h(.-)|h", "%1")
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	return s ~= "" and s or nil
end
AO.Plain = Plain

-- the members Ace3 reads from the nearest group up the path when the option has none of its own
local INHERITED = { set = true, get = true, func = true, confirm = true, validate = true, disabled = true, hidden = true }
local LITERAL = { name = true, desc = true }

-- a group's child by key: a plugin's first, then its own (as Ace3's GetSubOption looks)
local function Sub(group, key)
	if type(group) ~= "table" then return nil end
	for _, p in pairs(type(group.plugins) == "table" and group.plugins or {}) do
		if type(p) == "table" and type(p[key]) == "table" then return p[key] end
	end
	local args = group.args
	local v = type(args) == "table" and args[key]
	if type(v) == "table" then return v end
end

-- Ace3's pickfirstset: the first of these that's set
local function First(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v ~= nil then return v end
	end
end

-- An option's member, worked out as AceConfigDialog does: a value as it is; a function called with Ace3's info table; a
-- method name on the handler (names and descriptions are text as written). pcall'd: it's the addon's own code.
local function Member(name, option, options, path, appName, ...)
	local member
	if INHERITED[name] then
		local group = options
		if group[name] ~= nil then member = group[name] end
		for i = 1, #path do
			group = Sub(group, path[i])
			if not group then break end
			if group[name] ~= nil then member = group[name] end
		end
	else
		member = option[name]
	end
	if not (type(member) == "function" or (not LITERAL[name] and type(member) == "string")) then return true, member end
	local info, group, handler = {}, options, options.handler
	for i = 1, #path do
		group = Sub(group, path[i]) or {}
		info[i] = path[i]
		handler = group.handler or handler
	end
	info.options, info.appName, info[0], info.arg, info.handler = options, appName, appName, option.arg, handler
	info.option, info.type, info.uiType, info.uiName = option, option.type, "dialog", DIALOG
	if type(member) == "function" then return pcall(member, info, ...) end
	if type(handler) == "table" and type(handler[member]) == "function" then return pcall(handler[member], handler, info, ...) end
	return false
end
AO.Member = Member

local function Value(name, option, options, path, appName)
	local ok, v = Member(name, option, options, path, appName)
	return ok and v or nil
end

local function Hidden(option, options, path, appName)
	local h = option.dialogHidden
	if h == nil then h = option.guiHidden end
	if h ~= nil then return h and true or false end
	local ok, v = Member("hidden", option, options, path, appName)
	return not ok or (v and true or false) -- (an error working it out: left out, as the window would fail on it too)
end

-- options in the order the window shows them: order (100 by default; a negative order after the rest), then name
local function Sorted(group, options, path, appName)
	local keys, seen = {}, {}
	-- (each key once: a plugin's wins over the group's own, as Ace3 lists them)
	local function AddFrom(t)
		for k, v in pairs(type(t) == "table" and t or {}) do
			if type(v) == "table" and type(k) == "string" and not seen[k] then
				seen[k] = true
				keys[#keys + 1] = { k, v }
			end
		end
	end
	for _, p in pairs(type(group.plugins) == "table" and group.plugins or {}) do AddFrom(p) end
	AddFrom(group.args)
	for _, kv in ipairs(keys) do
		path[#path + 1] = kv[1]
		local o = tonumber(Value("order", kv[2], options, path, appName)) or 100
		if o ~= o then o = 100 end -- (not a number: a sort given NaN fails as a whole)
		kv[3] = o < 0 and (1e6 + o) or o
		local nm = Value("name", kv[2], options, path, appName)
		kv[5] = nm
		kv[4] = type(nm) == "string" and nm:upper() or ""
		path[#path] = nil
	end
	-- (as Ace3 sorts them: order, then the name in capitals)
	table.sort(keys, function(a, b) if a[3] ~= b[3] then return a[3] < b[3] end if a[4] ~= b[4] then return a[4] < b[4] end return a[1] < b[1] end)
	return keys
end

--- An addon's options table, as Ace3's window asks for it: GetOptionsTable(app) hands a function, called with the
--- window's uiType (given a uiType itself, it hands the table: both are taken). Nil when it can't be had.
function AO.Root(reg, appName)
	local okT, app = pcall(reg.GetOptionsTable, reg, appName)
	if not okT then return nil end
	if type(app) == "function" then
		local okO, options = pcall(app, "dialog", DIALOG)
		return okO and type(options) == "table" and options or nil
	end
	return type(app) == "table" and app or nil
end

local SKIP = { header = true, description = true }

--- Every visible setting of every addon registered with Ace3: { app, title, path, selectPath, name, desc, type, groups }.
function AO.Read()
	local reg = Registry()
	local out = {}
	if not (reg and type(reg.tables) == "table") then return out end
	local apps = {}
	for appName in pairs(reg.tables) do if type(appName) == "string" then apps[#apps + 1] = appName end end
	table.sort(apps)
	for _, appName in ipairs(apps) do
		local options = AO.Root(reg, appName)
		if options then
			local title = Plain(Value("name", options, options, {}, appName)) or appName
			local count = 0
			-- (a group shown inline sits in its parent's page: what to select stops at the first one; their children too)
			local function Walk(group, path, names, selectPath, inline, depth)
				if depth > AO.DEPTH then return end
				for _, kv in ipairs(Sorted(group, options, path, appName)) do
					if count >= AO.MAX_PER_APP or #out >= AO.MAX then return end
					local k, v = kv[1], kv[2]
					path[#path + 1] = k
					local ty = v.type
					if not Hidden(v, options, path, appName) then
						local name = Plain(kv[5])
						if ty == "group" then
							local isInline = inline or First(v.dialogInline, v.guiInline, v.inline, false) and true or false
							local sp = selectPath
							if not isInline then
								sp = { unpack(selectPath) }
								sp[#sp + 1] = k
							end
							if name and not isInline then
								count = count + 1
								out[#out + 1] = { app = appName, title = title, path = { unpack(path) }, selectPath = sp, name = name,
									desc = Plain(Value("desc", v, options, path, appName)), type = "group", groups = { unpack(names) },
									option = v, options = options }
							end
							names[#names + 1] = name or k
							Walk(v, path, names, sp, isInline, depth + 1)
							names[#names] = nil
						elseif name and ty and not SKIP[ty] then
							count = count + 1
							out[#out + 1] = { app = appName, title = title, path = { unpack(path) }, selectPath = selectPath, name = name,
								desc = Plain(Value("desc", v, options, path, appName)), type = ty, groups = { unpack(names) },
								toggle = ty == "toggle" and not v.tristate or nil, option = v, options = options }
						end
					end
					path[#path] = nil
				end
			end
			Walk(options, {}, {}, {}, false, 1)
		end
	end
	return out
end

-- the option's table and its root, as read (not asked of the addon again on every draw: a function-made table would be
-- built anew each time)
local function Resolve(o) return o.option, o.options end

--- An on/off setting's value now (true/false), or nil when it can't be read.
function AO.Get(o)
	if not o.toggle then return nil end
	local opt, options = Resolve(o)
	if not opt then return nil end
	local ok, v = Member("get", opt, options, o.path, o.app)
	if not ok then return nil end
	return v and true or false
end

-- an inherited member as written (nothing called): the option's own, else the nearest group's up the path
local function Raw(name, option, options, path)
	local member, group = options[name], options
	local handler = options.handler
	for i = 1, #path do
		group = Sub(group, path[i])
		if not group then break end
		if group[name] ~= nil then member = group[name] end
		handler = group.handler or handler
	end
	if option[name] ~= nil then member = option[name] end
	return member, handler
end

--- Can Shift+Enter turn it on or off? Not when greyed out, when it asks first or checks the value (whatever its
--- answer would be: those are the window's to ask), or when nothing would set it.
local function CanFlip(o)
	if not o.toggle then return false end
	local opt, options = Resolve(o)
	if not opt then return false end
	local dis = First(opt.dialogDisabled, opt.guiDisabled)
	if dis == nil then
		local ok, v = Member("disabled", opt, options, o.path, o.app)
		dis = not ok or v
	end
	if dis then return false end
	local confirm = Raw("confirm", opt, options, o.path)
	if confirm ~= nil and confirm ~= false then return false end
	if Raw("validate", opt, options, o.path) ~= nil then return false end
	local set, handler = Raw("set", opt, options, o.path)
	if not (type(set) == "function" or (type(set) == "string" and type(handler) == "table" and type(handler[set]) == "function")) then
		return false
	end
	return true, opt, options
end

----------------------------------------------------------------------
-- Ace3's window, opened on the setting
----------------------------------------------------------------------

local function Join(t) return table.concat(t, "\001") end

-- the widget showing this option in the open window: its path, as Ace3 tags each one
local function FindWidget(widget, want, depth)
	if type(widget) ~= "table" or depth > 30 then return nil end
	local user = widget.GetUserDataTable and widget:GetUserDataTable()
	if type(user) == "table" and type(user.path) == "table" and Join(user.path) == want and widget.frame
		and widget.frame.IsVisible and widget.frame:IsVisible() then
		return widget.frame
	end
	for _, c in ipairs(type(widget.children) == "table" and widget.children or {}) do
		local f = FindWidget(c, want, depth + 1)
		if f then return f end
	end
end

function AO.Open(e)
	local o = e.opt
	local ACD = Dialog()
	if not (o and ACD and ACD.Open) then
		ns:Print(L["%s's options can't be opened from here."]:format(tostring(e and e.title)))
		return
	end
	local ok, err = pcall(ACD.Open, ACD, o.app)
	if not ok then
		ns:Trace("addon options: open " .. tostring(o.app) .. " failed: " .. tostring(err))
		ns:Print(L["%s's options can't be opened from here."]:format(tostring(o.title)))
		return
	end
	if #o.selectPath > 0 and ACD.SelectGroup then
		local okS, errS = pcall(ACD.SelectGroup, ACD, o.app, unpack(o.selectPath))
		if not okS then ns:Trace("addon options: select failed: " .. tostring(errS)) end
	end
	-- (a page: opened on it, nothing to point at; a setting: its widget, once the window is built again for the page
	-- picked: Ace3 does that on its next frame)
	if o.type == "group" then return end
	local want = Join(o.path)
	H:When(function()
		local f = ACD.OpenFrames and ACD.OpenFrames[o.app]
		if not f then return false end
		local upd = ACD.frame and ACD.frame.GetScript and ACD.frame:GetScript("OnUpdate")
		if upd then return nil end
		return FindWidget(f, want, 0)
	end, function(b) H:Show(b) end, 30, function()
		ns:Trace("addon options: nothing to point at for " .. tostring(o.app) .. " " .. want)
	end)
end

--- Shift+Enter on an on/off setting: turned the other way, as its checkbox would.
function AO.Flip(e)
	local o = e.opt
	-- (the addon's own code runs from Terminal's key: in combat a setting touching protected frames would be blocked)
	if InCombatLockdown() then
		ns:Print(L["In combat: change %s after the fight."]:format(tostring(e.name)))
		return
	end
	local can, opt, options = CanFlip(o)
	if not can then
		ns:Print(L["%s: open its options to change it (Enter)."]:format(tostring(e.name)))
		return
	end
	local now = AO.Get(o)
	if now == nil then return end
	local ok, err = Member("set", opt, options, o.path, o.app, not now)
	if not ok then
		ns:Trace("addon options: set failed: " .. tostring(err))
		ns:Print(L["%s: open its options to change it (Enter)."]:format(tostring(e.name)))
		return
	end
	local reg = Registry()
	if reg and reg.NotifyChange then pcall(reg.NotifyChange, reg, o.app) end
	local after = AO.Get(o)
	ns:Print(L["%s (%s): %s"]:format(tostring(e.name), tostring(o.title), after and L["on"] or L["off"]))
	-- (its row reads the value when drawn: drawn again, nothing read anew)
	if ns.UI and ns.UI.IsShown and ns.UI:IsShown() and ns.UI.Render then pcall(ns.UI.Render, ns.UI) end
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local TYPE_WORD = { toggle = L["on/off"], range = L["slider"], select = L["choice"], multiselect = L["choices"], input = L["text"],
	color = L["colour"], execute = L["button"], keybinding = L["key"], group = L["page"] }

local function Tooltip(e, t)
	local o = e.opt
	t:SetText(e.name, 1, 0.82, 0)
	local where = { o.title }
	for _, g in ipairs(o.groups) do where[#where + 1] = g end
	t:AddLine(table.concat(where, " › "), 0.8, 0.8, 0.8, true)
	if o.desc then t:AddLine(o.desc, 1, 1, 1, true) end
	if o.toggle then
		local v = AO.Get(o)
		if v ~= nil then t:AddDoubleLine(L["Now"], v and L["on"] or L["off"], 1, 1, 1, v and 0.25 or 1, v and 1 or 0.4, v and 0.25 or 0.4) end
	end
	t:AddLine(o.toggle and L["Enter: open its options    Shift+Enter: turn it on or off"] or L["Enter: open its options"], 0.6, 0.6, 0.6, true)
end

local ROW = { activate = AO.Open, tooltip = Tooltip, icon = "Interface\\Icons\\INV_Misc_Gear_02" }
local LAZY = {
	detail = function(t)
		local o = t.opt
		local where = { o.title }
		for _, g in ipairs(o.groups) do where[#where + 1] = g end
		local parts = { table.concat(where, " › "), TYPE_WORD[o.type] }
		if o.toggle then
			local v = AO.Get(o)
			if v ~= nil then parts[#parts + 1] = v and ("|cff40ff40" .. L["on"] .. "|r") or ("|cffff6060" .. L["off"] .. "|r") end
		end
		return ns.Detail(unpack(parts))
	end,
	title = function(t) return t.opt.title end,
	secondary = function(t) return t.opt.toggle and AO.Flip or nil end,
}
local meta

-- (an addon telling its options changed (AceConfigRegistry's ConfigTableChange, sent on NotifyChange): the list is
-- read again the next time it's searched. Listened to from the first read on)
local function Watch()
	local reg = Registry()
	if AO.watching or not (reg and reg.RegisterCallback) then return end
	AO.watching = pcall(reg.RegisterCallback, AO, "ConfigTableChange", function() ns:Changed("addonoptions") end) or nil
end

function AO.Collect()
	local p = ns.providers.addonoptions
	meta = meta or ns:CompactMeta(p, ROW, LAZY)
	Watch()
	local rows = {}
	for i, o in ipairs(AO.Read()) do
		local words = { Lower(o.title), Lower(o.app), o.desc and Lower(o.desc) or "", TYPE_WORD[o.type] or "", "option options setting settings" }
		for _, g in ipairs(o.groups) do words[#words + 1] = Lower(g) end
		rows[#rows + 1] = setmetatable({ _compact = true, key = o.app .. "\001" .. Join(o.path), name = o.name, opt = o,
			text = table.concat(words, " ") }, meta)
	end
	ns.RankInOrder(rows) -- (the window's order among equal matches)
	ns:Trace(("addon options: %d settings"):format(#rows))
	return rows
end

--- The addons whose options are searchable, for .integrations: { names }.
function AO.Apps()
	local reg = Registry()
	local out = {}
	for appName in pairs(reg and type(reg.tables) == "table" and reg.tables or {}) do out[#out + 1] = tostring(appName) end
	table.sort(out)
	return out
end

ns:RegisterProvider("addonoptions", {
	label = L["Addon option"],
	color = "ff70a8a0",
	aliases = { "addonoption", "addonoptions", "addonsetting", "addonsettings", "aceoptions" },
	lazy = true, -- (read on the first search that needs it)
	-- (read again when an addon says its options changed (Watch), or one loads; not every 5 minutes inside a keystroke:
	-- every option of every addon, its own functions called for each, review 0.53.6)
	events = { "ADDON_LOADED" },
	collect = function() return AO.Collect() end,
})
