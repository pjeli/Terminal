local ns = select(2, ...)

-- Installed addons. Enter does what clicking the addon's minimap button does, or opens its
-- own options panel (Game Menu > Options > AddOns) when it has no button. Shift+Enter opens
-- the options panel when an addon has both. Addons with neither open the AddOn list. Minimap buttons that don't belong to a listed addon are listed too.
--
-- Options panels are matched to addons by name. Minimap buttons are found through
-- LibDBIcon / LibDataBroker (what most addons use for them), or a minimap button whose
-- name contains the addon's name.

local Plain, Norm = ns.Plain, ns.Norm -- Norm keeps letters of every language (Locale.lua)

----------------------------------------------------------------------
-- Options panels
----------------------------------------------------------------------

local function SettingsCategories()
	local out = {}
	if SettingsPanel and SettingsPanel.GetAllCategories then
		local ok, list = pcall(SettingsPanel.GetAllCategories, SettingsPanel)
		if ok and type(list) == "table" then
			for _, cat in ipairs(list) do
				local okN, name = pcall(function() return cat:GetName() end)
				local okI, id = pcall(function() return cat:GetID() end)
				if okN and type(name) == "string" and name ~= "" then
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
				local ok, name = pcall(function() return child:GetName() end)
				if ok and type(name) == "string" and child.Click and not seen[child] then
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

		for i = 1, C_AddOns.GetNumAddOns() do
			local name, title, notes = C_AddOns.GetAddOnInfo(i)
			if name then
				local label = Plain(title or name)
				if label == "" then label = name end
				local keys = { [Norm(name)] = true, [Norm(label)] = true }
				keys[""] = nil -- a name of only symbols matches nothing
				local opt
				for _, c in ipairs(cats) do
					if keys[Norm(c.name)] then opt = c break end
				end
				local launch
				for bi, b in ipairs(brokers) do
					if keys[Norm(b.name)] then launch = b; usedBroker[bi] = true break end
				end
				if not launch then
					local n1 = Norm(name)
					for _, mb in ipairs(buttons) do
						if #n1 >= 4 and Norm(mb.name):find(n1, 1, true) then launch = mb break end
					end
				end
				local loaded = C_AddOns.IsAddOnLoaded(name)
				local does
				if opt and launch then does = "Minimap button  |  Shift: options"
				elseif opt then does = "Options"
				elseif launch then does = "Minimap button"
				else does = loaded and "Loaded" or "Not loaded" end
				out[#out + 1] = {
					key = name,
					name = label,
					icon = (launch and launch.icon) or "Interface\\Icons\\INV_Misc_Gear_01",
					detail = does,
					text = name .. " " .. Plain(notes or ""),
					tip = notes and Plain(notes) or nil,
					activate = function()
						if launch then return Launch(launch) end
						if opt and OpenCategory(opt) then return end
						AddonList()
					end,
					secondary = function()
						if opt and launch and OpenCategory(opt) then return end
						AddonList()
					end,
				}
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
					activate = function() ClickBroker(b) end,
				}
			end
		end
		return out
	end,
})
