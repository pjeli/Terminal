local ns = select(2, ...)

-- Installed addons. Enter does what clicking the addon's minimap button does, or opens its
-- own options panel (Game Menu > Options > AddOns) when it has no button. An addon with both
-- gets a second row, "<addon> options", for its panel. Addons with neither open the AddOn list.
-- Shift+Enter turns the addon on or off (for the next /reload). Minimap buttons that don't belong
-- to a listed addon are listed too.
--
-- Options panels are matched to addons by name. Minimap buttons are found through
-- LibDBIcon / LibDataBroker (what most addons use for them), or a minimap button whose
-- name contains the addon's name.

local Plain, Norm = ns.Plain, ns.Norm -- Norm keeps letters of every language (Locale.lua)

----------------------------------------------------------------------
-- Options panels
----------------------------------------------------------------------

local function IdOf(cat) return cat:GetID() end -- (one function for every category, not a closure each)

local function SettingsCategories()
	local out = {}
	if SettingsPanel and SettingsPanel.GetAllCategories then
		local ok, list = pcall(SettingsPanel.GetAllCategories, SettingsPanel)
		if ok and type(list) == "table" then
			for _, cat in ipairs(list) do
				local name = ns.FrameName(cat)
				local okI, id = pcall(IdOf, cat)
				if name and name ~= "" then
					out[#out + 1] = { name = name, id = okI and id or nil, cat = cat }
				end
			end
		end
	end
	if #out == 0 and type(INTERFACEOPTIONS_ADDONCATEGORIES) == "table" then -- older clients
		for _, panel in ipairs(INTERFACEOPTIONS_ADDONCATEGORIES) do
			if type(panel.name) == "string" then out[#out + 1] = { name = panel.name, panel = panel } end
		end
	end
	return out
end

local function OpenCategory(c)
	if c.id and Settings and Settings.OpenToCategory and pcall(Settings.OpenToCategory, c.id) then return true end
	if c.panel and InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(c.panel)
		return true
	end
	if Settings and Settings.OpenToCategory then return pcall(Settings.OpenToCategory, c.name) end
	return false
end

----------------------------------------------------------------------
-- Minimap buttons
----------------------------------------------------------------------

local function Lib(name)
	local LS = _G.LibStub
	if not LS then return nil end
	local ok, lib = pcall(LS, name, true)
	return ok and lib or nil
end

--- LibDataBroker launchers and other clickable data objects: { name, obj }
local function Brokers()
	local out = {}
	local ldb = Lib("LibDataBroker-1.1")
	if ldb and ldb.DataObjectIterator then
		for name, obj in ldb:DataObjectIterator() do
			if type(obj) == "table" and type(obj.OnClick) == "function" then
				out[#out + 1] = { name = name, obj = obj, icon = obj.icon }
			end
		end
	end
	return out
end

local function MinimapButtons()
	local out = {}
	local seen = {}
	for _, parent in ipairs({ _G.Minimap, _G.MinimapBackdrop, _G.MinimapCluster }) do
		if parent and parent.GetChildren then
			for _, child in ipairs({ parent:GetChildren() }) do
				local name = ns.FrameName(child)
				if name and child.Click and not seen[child] then
					seen[child] = true
					out[#out + 1] = { name = name, button = child }
				end
			end
		end
	end
	return out
end

local function ClickBroker(b)
	local icon = Lib("LibDBIcon-1.0")
	local frame = icon and icon.GetMinimapButton and icon:GetMinimapButton(b.name)
	pcall(b.obj.OnClick, frame or UIParent, "LeftButton")
end

local function Launch(t)
	if t.obj then ClickBroker(t) elseif t.button then pcall(t.button.Click, t.button, "LeftButton") end
end

local function AddonList()
	if _G.AddonList then ShowUIPanel(_G.AddonList) end
end

----------------------------------------------------------------------
-- Provider
----------------------------------------------------------------------

--- normalised name -> index of the first item with it ("" never matches)
local function ByName(list)
	local m = {}
	for i, x in ipairs(list) do
		local k = Norm(x.name)
		if k ~= "" and not m[k] then m[k] = i end
	end
	return m
end

--- The first item (lowest index) named either way, and its index.
local function First(list, by, k1, k2)
	local a, b = by[k1], by[k2]
	local i = (a and b) and math.min(a, b) or a or b
	return i and list[i], i
end

-- Blizzard's windows (an options page, the AddOn list) are opened by the game: a /run line on the secure
-- macro button (as the Keybindings page is), never Settings.OpenToCategory / ShowUIPanel from Terminal's
-- code, which taints them. A minimap button is another addon's own frame: clicked from here.
local ADDONLIST_MACRO = "/run if AddonList then ShowUIPanel(AddonList) end"
local function CategoryMacro(c)
	if c.id and _G.Settings and _G.Settings.OpenToCategory then return ("/run Settings.OpenToCategory(%d)"):format(c.id) end
	if c.panel then return nil end -- (an old client's panel object: no line can name it)
	if _G.Settings and _G.Settings.OpenToCategory then return ("/run Settings.OpenToCategory(%q)"):format(c.name) end
	return nil
end
local function AddonMacro(e)
	if e.launch then return nil end -- (its minimap button: Terminal clicks that itself)
	if e.opt then return CategoryMacro(e.opt) end
	return ADDONLIST_MACRO
end
local function OptionsMacro(e) return CategoryMacro(e.opt) end
local ADDON_SPEC, OPTIONS_SPEC = { macro = AddonMacro, opensWindow = true }, { macro = OptionsMacro, opensWindow = true }
local NeverOpen = ns.Never -- (always pressed: the window may show another page)
local function Opened(e) ns:Trace("addons: the game opened the window for " .. tostring(e.name)) end

-- shared by every row (they carry what they open); the fallbacks without the secure route
local function AddonActivate(e)
	if e.launch then return Launch(e.launch) end
	if e.opt and OpenCategory(e.opt) then return end
	AddonList()
end
local function OpenOptions(e)
	if not OpenCategory(e.opt) then AddonList() end
end

----------------------------------------------------------------------
-- On / off (Shift+Enter)
--
-- For this character, as the AddOn List does with this character picked (its default): the
-- character's name goes with the call, as the list passes it. (nil would mean every character,
-- and the player keeps addons on for some characters only.) Turning an addon on or off is a plain
-- C call, not a window: no game press needed. It takes effect at the next /reload (.reload).
----------------------------------------------------------------------

local function Character() return ns.CharacterName() end -- (with the surname where characters have one: Util.lua)

--- Whether the addon is turned on for the character named `who` (nil: the client doesn't say). The list asks for
--- every addon with the name worked out once (Character()), not once per addon.
local function EnabledFor(name, who)
	local get = C_AddOns.GetAddOnEnableState
	local st = get and ns.Num(ns.Safe(get, name, who))
	if st == nil then return nil end
	return st > 0 -- (0 off, 1 on for some characters, 2 on)
end

--- Whether the addon is turned on for this character (nil: the client doesn't say).
local function Enabled(name) return EnabledFor(name, Character()) end

local function Detail(e)
	local state
	if e.enabled == nil then -- (the client doesn't say: what it does, else whether it's loaded)
		if e.does then return e.does end
		state = e.loaded and "Loaded" or "Not loaded"
	else
		state = e.enabled and "enabled" or "disabled"
		if e.enabled ~= e.loaded then state = state .. " (.reload to apply)" end
	end
	return e.does and (e.does .. "  ·  " .. state) or state
end

local function ToggleAddon(e)
	if e.key == ns.name then
		ns:Print(ns.name .. " can't turn itself off from here: use the AddOn list.")
		return
	end
	local on = Enabled(e.key)
	if on == nil then on = e.loaded end
	local fn = on and C_AddOns.DisableAddOn or C_AddOns.EnableAddOn
	if not (fn and pcall(fn, e.key, Character())) then
		ns:Print("Couldn't turn " .. tostring(e.name) .. (on and " off." or " on."))
		return
	end
	-- the change is only in memory until it's saved: the AddOn list's Okay button saves it (SaveAddOns);
	-- without that, the reload that should apply it threw it away and the addon stayed as it was
	local save = C_AddOns.SaveAddOns or _G.SaveAddOns
	if save then pcall(save) end
	local now = Enabled(e.key)
	ns:Trace(("addons: %s %s for %s; the game now says %s"):format(tostring(e.key), on and "disabled" or "enabled",
		tostring(Character()), tostring(now)))
	if now == on then
		-- the game didn't take it (the character name it was given isn't how it knows this character?)
		ns:Print(("The game didn't turn %s %s (asked for %s). Try the AddOn list."):format(tostring(e.name), on and "off" or "on", tostring(Character())))
		return
	end
	if now == nil then now = not on end
	e.enabled = now
	e.detail = Detail(e) -- (shown at once; the list is read again next time too)
	ns.entriesGen = ns.entriesGen + 1
	if ns.providers.addons then ns.providers.addons._dirty = true end
	ns:Print(("%s %s: .reload to apply"):format(tostring(e.name), now and "enabled" or "disabled"))
	local UI = ns.UI
	if UI and UI.IsShown and UI:IsShown() and UI.Refresh then UI:Refresh() end
end
local function BrokerActivate(e) ClickBroker(e.launch) end

ns:RegisterProvider("addons", {
	label = "AddOn",
	color = "ffb0b0b0",
	aliases = { "addon", "addons", "plugin" },
	noCombat = true, -- opening windows is protected in combat
	refreshOnOpen = true, -- options panels and minimap buttons appear as addons load
	collect = function()
		local out = {}
		local cats = SettingsCategories()
		local brokers = Brokers()
		local buttons = MinimapButtons()
		local usedBroker = {}
		-- names normalised once, not once per addon (this runs on every open)
		local catBy, brokerBy = ByName(cats), ByName(brokers)
		local buttonKeys = {}
		for i, mb in ipairs(buttons) do buttonKeys[i] = Norm(mb.name) end
		local who = Character() -- (this character's name, as the AddOn list knows it: once, not per addon)

		for i = 1, C_AddOns.GetNumAddOns() do
			local name, title, notes = C_AddOns.GetAddOnInfo(i)
			if name then
				local label = Plain(title or name)
				if label == "" then label = name end
				local n1, n2 = Norm(name), Norm(label)
				local opt = First(cats, catBy, n1, n2)
				local launch, bi = First(brokers, brokerBy, n1, n2)
				if launch then usedBroker[bi] = true end
				if not launch and #n1 >= 4 then
					for j, k in ipairs(buttonKeys) do
						if k:find(n1, 1, true) then launch = buttons[j] break end
					end
				end
				local loaded = C_AddOns.IsAddOnLoaded(name) and true or false
				local does = launch and "Minimap button" or (opt and "Options") or nil
				local plainNotes = notes and Plain(notes) or nil
				local e = {
					key = name,
					name = label,
					icon = (launch and launch.icon) or "Interface\\Icons\\INV_Misc_Gear_01",
					text = name .. " " .. (plainNotes or ""),
					tip = plainNotes,
					launch = launch, opt = opt,
					does = does, loaded = loaded, enabled = EnabledFor(name, who),
					secure = ADDON_SPEC, isOpen = NeverOpen, after = Opened,
					activate = AddonActivate,
					secondary = ToggleAddon, -- Shift+Enter: on / off
				}
				e.detail = Detail(e)
				out[#out + 1] = e
				if opt and launch then
					-- Enter is its minimap button: its options panel is a row of its own (it was Shift+Enter)
					out[#out + 1] = {
						key = "options:" .. name,
						name = label .. " options",
						icon = "Interface\\Icons\\INV_Misc_Gear_01",
						detail = "Options",
						text = name .. " options settings",
						opt = opt,
						secure = OPTIONS_SPEC, isOpen = NeverOpen, after = Opened,
						activate = OpenOptions,
					}
				end
			end
		end

		-- minimap buttons that aren't any listed addon's
		for bi, b in ipairs(brokers) do
			if not usedBroker[bi] then
				out[#out + 1] = {
					key = "broker:" .. b.name,
					name = Plain(b.obj.label or b.name),
					icon = b.icon or "Interface\\Icons\\INV_Misc_Gear_01",
					detail = "Minimap button",
					text = b.name .. " minimap button",
					launch = b,
					activate = BrokerActivate,
				}
			end
		end
		return out
	end,
})
