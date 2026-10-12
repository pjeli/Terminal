local ns = select(2, ...)
local H = ns.Highlight

-- The game's own options (Game Menu > Options): every page (Graphics, Audio, Interface,
-- Accessibility, Controls, ...) and every setting on them, searchable by name. Enter opens
-- the page and highlights the setting. Addons' own pages are left to the AddOn index.

local Plain, Norm = ns.Plain, ns.Norm -- Norm keeps letters of every language (Locale.lua)

local function Call(obj, method, ...)
	if type(obj) ~= "table" then return nil end
	return (ns.Safe(obj[method], obj, ...))
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
	set[""] = nil -- a name of only symbols matches nothing
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

-- (the fallback, Terminal's own code: the game's own call, which the settings window's code answers itself)
local function OpenPage(o)
	local U = _G.C_SettingsUtil
	local id = ns.Secure.SettingsID(o.id or o.name)
	if not (U and U.OpenSettingsPanel and id) then return false end
	return (pcall(U.OpenSettingsPanel, id, (not o.page) and o.name or nil))
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

-- Point at the setting (or the page in the list), whenever it shows in the window. Nothing is typed into the window's
-- search box (that was Terminal's code writing the window's state: its list was then rebuilt tainted). `hint`: said
-- once when it isn't showing after a moment (a keybinding in a closed section).
local LOOKS, HINT_AFTER = 150, 10 -- (a tenth of a second apart)

--- Whether a frame in the settings list is in the part of the list that shows (a keybinding row further down an
--- unfolded section is laid out, but below the list's bottom edge: pointed at only once it's scrolled to). Frames
--- outside the list (the category list) count as shown.
local function InView(f, sp)
	local ok, list = pcall(function() return sp:GetSettingsList() end)
	local box = ok and type(list) == "table" and rawget(list, "ScrollBox")
	if not (box and box.GetTop and f.GetTop) then return true end
	local p, inside = f, false
	for _ = 1, 15 do
		local okP, up = pcall(p.GetParent, p)
		p = okP and up or nil
		if not p then break end
		if p == box then inside = true break end
	end
	if not inside then return true end
	local okB, top, bottom = pcall(function() return box:GetTop(), box:GetBottom() end)
	local okF, ft, fb = pcall(function() return f:GetTop(), f:GetBottom() end)
	if not (okB and okF and top and bottom and ft and fb) then return true end
	local mid = (ft + fb) / 2
	return mid <= top and mid >= bottom
end

local function HighlightSetting(name, hint)
	local tries, seen = 0, false
	H:Find(function()
		local sp = SettingsPanel
		if not (sp and sp:IsVisible()) then if seen then return false end return nil end -- (closed again after it showed)
		seen = true
		tries = tries + 1
		local hit = ns.FindFrame(sp, function(f) return ExactText(f, name) and InView(f, sp) end, 20)
		if hit then return hit end
		if tries == HINT_AFTER and hint then ns:Print(hint) end
		return nil
	end, LOOKS)
end

ns.GameOptions = { HighlightSetting = HighlightSetting, InView = InView } -- (keybindings point at their row the same way)

-- The page is opened by the game: C_SettingsUtil.OpenSettingsPanel on the secure macro button (Secure.SettingsMacro),
-- which the window's own code answers, scrolling to the setting by name. Always pressed (the window may be open on
-- another page); afterwards Terminal only points at the setting.
local function OptionMacro(e)
	local o = e.opt
	if not o then return nil end
	return ns.Secure.SettingsMacro(o.id or o.name, (not o.page) and o.name or nil)
end
local OPTION_SPEC = { macro = OptionMacro, opensWindow = true }
local function PointAtOption(e) HighlightSetting(e.name) end

-- the fallback without the secure route (Terminal's own code): open, then point
local function OpenOption(e)
	if OpenPage(e.opt) then HighlightSetting(e.name) end
end

ns:RegisterProvider("gameoptions", {
	label = "Options",
	color = "ff9fb7ff",
	aliases = { "option", "options", "setting", "settings" },
	noCombat = true, -- opening windows is protected in combat
	lazy = true, -- hundreds of settings: only offered once you type something
	events = { "PLAYER_ENTERING_WORLD" }, -- (addons' pages are left out, so their loading changes nothing)
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
					opt = o,
					secure = OPTION_SPEC, after = PointAtOption,
					activate = OpenOption,
				}
			end
		end
		return out
	end,
})
