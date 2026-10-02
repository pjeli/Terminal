local ns = select(2, ...)
local H = ns.Highlight

-- The game's own options (Game Menu > Options): every page (Graphics, Audio, Interface,
-- Accessibility, Controls, ...) and every setting on them, searchable by name. Enter opens
-- the page and highlights the setting. Addons' own pages are left to the AddOn index.

local function Plain(s)
	return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function Norm(s)
	return (Plain(s):lower():gsub("[^%w]", ""))
end

local function Call(obj, method, ...)
	if type(obj) ~= "table" or type(obj[method]) ~= "function" then return nil end
	local ok, res = pcall(obj[method], obj, ...)
	if ok then return res end
end

local function AddonNames()
	local set = {}
	for i = 1, C_AddOns.GetNumAddOns() do
		local name, title = C_AddOns.GetAddOnInfo(i)
		if name then
			set[Norm(name)] = true
			if title then set[Norm(title)] = true end
		end
	end
	return set
end

local function InitializerName(init)
	local n = Call(init, "GetName")
	if (type(n) ~= "string" or n == "") and type(init) == "table" and type(init.data) == "table" then n = init.data.name end
	if type(n) == "string" and n ~= "" then return n end
end

local function Walk(cat, path, out, skip, depth)
	if depth > 4 then return end
	local name = Call(cat, "GetName")
	if type(name) ~= "string" or name == "" or skip[Norm(name)] then return end
	local id = Call(cat, "GetID")
	local here = path and (path .. " > " .. name) or name
	out[#out + 1] = { page = true, name = name, path = path, id = id }
	local layout = SettingsPanel and Call(SettingsPanel, "GetLayout", cat)
	local inits = layout and Call(layout, "GetInitializers")
	if type(inits) == "table" then
		for _, init in ipairs(inits) do
			local n = InitializerName(init)
			if n then
				local tip = type(init.data) == "table" and init.data.tooltip or nil
				out[#out + 1] = { name = n, path = here, id = id, tip = type(tip) == "string" and tip or nil }
			end
		end
	end
	local subs = Call(cat, "GetSubcategories")
	if type(subs) == "table" then
		for _, sub in ipairs(subs) do Walk(sub, here, out, skip, depth + 1) end
	end
end

local function OpenPage(o)
	if not (Settings and Settings.OpenToCategory) then return false end
	-- newer clients take the setting's name to scroll to; older ones ignore it
	if o.id and pcall(Settings.OpenToCategory, o.id, (not o.page) and o.name or nil) then return true end
	return pcall(Settings.OpenToCategory, o.name)
end

local function ExactText(f, text)
	if f.GetText then
		local ok, t = pcall(f.GetText, f)
		if ok and type(t) == "string" and Plain(t) == text then return true end
	end
	for _, r in ipairs({ f:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "FontString" and Plain(r:GetText()) == text then return true end
	end
	return false
end

-- Point at the setting (or the page in the list). If it isn't on screen after a moment,
-- the options window's own search box is used to bring it up.
local function HighlightSetting(name)
	local tries, searched = 0, false
	H:Find(function()
		local sp = SettingsPanel
		if not (sp and sp:IsVisible()) then return nil end
		tries = tries + 1
		local hit = ns.FindFrame(sp, function(f) return ExactText(f, name) end, 20)
		if hit then return hit end
		if tries >= 10 and not searched and sp.SearchBox and sp.SearchBox.SetText then
			searched = true
			pcall(sp.SearchBox.SetText, sp.SearchBox, name)
		end
		return nil
	end, 6, 40)
end

ns:RegisterProvider("gameoptions", {
	label = "Options",
	color = "ff9fb7ff",
	aliases = { "option", "options", "setting", "settings" },
	noCombat = true, -- opening windows is protected in combat
	lazy = true, -- hundreds of settings: only offered once you type something
	events = { "PLAYER_ENTERING_WORLD", "ADDON_LOADED" },
	guard = 5,
	collect = function()
		local out = {}
		local list = SettingsPanel and Call(SettingsPanel, "GetAllCategories")
		if type(list) ~= "table" then return out end
		local items, skip, seen = {}, AddonNames(), {}
		for _, cat in ipairs(list) do Walk(cat, nil, items, skip, 0) end
		for _, o in ipairs(items) do
			local key = (o.path or "") .. "/" .. o.name
			if not seen[key] then
				seen[key] = true
				local label = Plain(o.name)
				out[#out + 1] = {
					key = key,
					name = label,
					icon = o.page and "Interface\\Icons\\INV_Misc_Gear_02" or "Interface\\Icons\\Trade_Engineering",
					detail = o.page and (o.path and (o.path .. "  page") or "Options page") or o.path,
					text = (o.path or "") .. " options settings " .. (o.tip or ""),
					tip = o.tip,
					activate = function()
						if OpenPage(o) then HighlightSetting(label) end
					end,
				}
			end
		end
		return out
	end,
})
