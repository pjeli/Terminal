local ns = select(2, ...)

-- Theme: colours, font and layout of the terminal. Stored per account in TerminalDB.theme
-- and applied live. Change it from the terminal ( .theme, .set ) or the options panel.

local T = {}
ns.Theme = T

-- Default: Classic Forever look. Soft earthy brown (the game's scroll backgrounds) inside a
-- bronze frame, gold text, blue prompt.
T.DEFAULTS = {
	preset = "forever",
	promptText = ">",
	prompt = "6db8ff",   -- prompt colour
	accent = "c79c4e",   -- selected row
	match = "ffffff",    -- matched letters
	text = "ffd100",
	dim = "c9c2b0",      -- details, footer
	bg = "47331f",
	border = "b08040",
	bgAlpha = 0.95,
	frame = "classic",   -- classic: the game's tooltip-style frame; flat: a thin line
	font = "friz",
	fontSize = 13,
	width = 640,
	rows = 10,
	scale = 1.0,
	hints = true,
	autoScan = true, -- index professions quietly after login
	v = 3, -- theme defaults version (see T.Get)
}

T.PRESET_ORDER = { "forever", "foreverblue", "midnight", "matrix", "dracula", "solarized", "horde", "alliance" }
T.PRESETS = {
	forever = { label = "Forever", bg = "47331f", border = "b08040", accent = "c79c4e", prompt = "6db8ff", text = "ffd100", dim = "c9c2b0", match = "ffffff", bgAlpha = 0.95, frame = "classic" },
	foreverblue = { label = "Forever Blue", bg = "47331f", border = "b08040", accent = "c79c4e", prompt = "ffd100", text = "a8d8ff", dim = "d6c49a", match = "ffd100", bgAlpha = 0.95, frame = "classic" },
	midnight = { label = "Midnight", bg = "0d0f14", border = "40475a", accent = "ffd200", prompt = "33ff99", text = "ffffff", dim = "8c8c8c", match = "ffd200", bgAlpha = 0.96, frame = "flat" },
	matrix = { label = "Matrix", bg = "000a00", border = "0f6b26", accent = "00ff66", prompt = "00ff66", text = "c8ffc8", dim = "4f8f5f", match = "9dff9d", bgAlpha = 0.95, frame = "flat" },
	dracula = { label = "Dracula", bg = "282a36", border = "44475a", accent = "bd93f9", prompt = "50fa7b", text = "f8f8f2", dim = "8b9bd0", match = "ff79c6", bgAlpha = 0.97, frame = "flat" },
	solarized = { label = "Solarized", bg = "002b36", border = "2a5a66", accent = "b58900", prompt = "859900", text = "c5d1d1", dim = "8aa1a6", match = "e8743b", bgAlpha = 0.97, frame = "flat" },
	horde = { label = "Horde", bg = "1f0505", border = "8c1a0d", accent = "ff3b1f", prompt = "ff8a00", text = "f2e6d9", dim = "b09088", match = "ffb000", bgAlpha = 0.96, frame = "classic" },
	alliance = { label = "Alliance", bg = "050d24", border = "1a4099", accent = "3fa9ff", prompt = "ffd100", text = "e6eeff", dim = "8e9dc4", match = "7fd4ff", bgAlpha = 0.96, frame = "classic" },
}

T.FONTS = {
	friz = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
	arial = "Fonts\\ARIALN.TTF",
	morpheus = "Fonts\\MORPHEUS.TTF",
	skurri = "Fonts\\SKURRI.TTF",
}
T.FONT_ORDER = { "friz", "arial", "morpheus", "skurri" }

-- What each setting accepts. Order is how .set lists them.
T.ORDER = { "promptText", "prompt", "accent", "match", "text", "dim", "bg", "border", "bgAlpha",
	"frame", "font", "fontSize", "width", "rows", "scale", "hints", "autoScan" }
T.FIELDS = {
	promptText = { kind = "text", label = "Prompt", max = 4 },
	prompt = { kind = "color", label = "Prompt colour" },
	accent = { kind = "color", label = "Selection" },
	match = { kind = "color", label = "Match highlight" },
	text = { kind = "color", label = "Text" },
	dim = { kind = "color", label = "Details" },
	bg = { kind = "color", label = "Background" },
	border = { kind = "color", label = "Border" },
	bgAlpha = { kind = "number", label = "Opacity", min = 0.3, max = 1, step = 0.05 },
	frame = { kind = "choice", label = "Frame", choices = { "classic", "flat" } },
	font = { kind = "choice", label = "Font", choices = T.FONT_ORDER },
	fontSize = { kind = "number", label = "Font size", min = 10, max = 22, step = 1 },
	width = { kind = "number", label = "Width", min = 420, max = 1100, step = 10 },
	rows = { kind = "number", label = "Rows", min = 4, max = 20, step = 1 },
	scale = { kind = "number", label = "Scale", min = 0.6, max = 1.6, step = 0.05 },
	hints = { kind = "bool", label = "Key hints in footer" },
	autoScan = { kind = "bool", label = "Index professions at login" },
}
local PRESET_KEYS = { frame = true, bg = true, border = true, accent = true, prompt = true, text = true, dim = true, match = true, bgAlpha = true }

----------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------

function T.Get()
	local db = ns.db
	if not db then return T.DEFAULTS end
	db.theme = db.theme or {}
	local t = db.theme
	-- themes saved before the Forever look became the default: an untouched old default
	-- ("midnight") moves to the new one; anything the player picked or tuned stays
	if t.v == nil and next(t) ~= nil then
		if t.preset == "midnight" then
			for k, v in pairs(T.PRESETS.forever) do
				if k ~= "label" then t[k] = v end
			end
			t.preset = "forever"
		end
		t.frame = t.frame or ((T.PRESETS[t.preset] or {}).frame) or "flat"
		t.v = 2
	end
	-- v3: the Forever themes went from black to the scroll brown
	if t.v == 2 then
		if (t.preset == "forever" or t.preset == "foreverblue") and t.bg == "000000" then
			for k, v in pairs(T.PRESETS[t.preset]) do
				if k ~= "label" then t[k] = v end
			end
		end
		t.v = 3
	end
	-- a theme that no longer exists (Paper, Parchment) falls back to the default look
	if t.preset and t.preset ~= "custom" and not T.PRESETS[t.preset] then
		for k, v in pairs(T.PRESETS.forever) do
			if k ~= "label" then t[k] = v end
		end
		t.preset = "forever"
	end
	for k, v in pairs(T.DEFAULTS) do
		if t[k] == nil then t[k] = v end
	end
	return t
end

function T.RGB(hex)
	local r, g, b = tostring(hex or ""):match("^(%x%x)(%x%x)(%x%x)$")
	if not r then return 1, 1, 1 end
	return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

function T.IsLight()
	local r, g, b = T.RGB(T.Get().bg)
	return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
end

-- Readability on light backgrounds: colours made for the game's dark UI (item qualities,
-- the kind labels, gold hints) are darkened until they stand out against the background.
local function Lin(c) return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
local function Lum(r, g, b) return 0.2126 * Lin(r) + 0.7152 * Lin(g) + 0.0722 * Lin(b) end
local readable = {}
function T.Readable(hex)
	if not T.IsLight() then return hex end
	local bg = T.Get().bg
	local key = bg .. hex
	if readable[key] then return readable[key] end
	local br, bgg, bb = T.RGB(bg)
	local lb = Lum(br, bgg, bb)
	local r, g, b = T.RGB(hex)
	local f = 1
	while f > 0.05 do
		local l = Lum(r * f, g * f, b * f)
		if (lb + 0.05) / (l + 0.05) >= 4.5 then break end
		f = f - 0.05
	end
	local out = ("%02x%02x%02x"):format(math.floor(r * f * 255 + 0.5), math.floor(g * f * 255 + 0.5), math.floor(b * f * 255 + 0.5))
	readable[key] = out
	return out
end

--- Every |cAARRGGBB colour in a string, made readable on the current background.
function T.FixColors(s)
	if type(s) ~= "string" or not T.IsLight() then return s end
	return (s:gsub("|c(%x%x)(%x%x%x%x%x%x)", function(a, h) return "|c" .. a .. T.Readable(h:lower()) end))
end

function T.Format(key, v)
	local f = T.FIELDS[key]
	if not f then return tostring(v) end
	if f.kind == "bool" then return v and "on" or "off" end
	if f.kind == "number" then
		if f.step < 1 then return ("%.2f"):format(v) end
		return tostring(math.floor(v + 0.5))
	end
	return tostring(v)
end

----------------------------------------------------------------------
-- Fonts
----------------------------------------------------------------------

local function MakeFont(name, parent)
	local f = CreateFont(name)
	if parent then pcall(f.CopyFontObject, f, parent) end
	return f
end
T.fonts = {
	input = MakeFont("TerminalFontInput", _G.GameFontHighlightLarge),
	row = MakeFont("TerminalFontRow", _G.GameFontHighlight),
	small = MakeFont("TerminalFontSmall", _G.GameFontHighlightSmall),
}

function T.ApplyFonts()
	local t = T.Get()
	local path = T.FONTS[t.font] or T.FONTS.friz
	local function set(f, size)
		local ok, res = pcall(f.SetFont, f, path, size, "")
		if not ok or res == false then pcall(f.SetFont, f, T.FONTS.friz, size, "") end
	end
	set(T.fonts.input, t.fontSize + 3)
	set(T.fonts.row, t.fontSize)
	set(T.fonts.small, math.max(9, t.fontSize - 2))
end

----------------------------------------------------------------------
-- Changing
----------------------------------------------------------------------

function T.Changed()
	if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end
	if ns.Options and ns.Options.Refresh then ns.Options.Refresh() end
end

local function Hex(v)
	v = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^#", ""):lower()
	v = v:gsub("^|c(%x%x)", "")
	if v:match("^%x%x%x%x%x%x$") then return v end
	if v:match("^%x%x%x$") then
		return v:sub(1, 1):rep(2) .. v:sub(2, 2):rep(2) .. v:sub(3, 3):rep(2)
	end
end

--- Validates and stores one setting. Returns ok, value-or-error.
function T.Set(key, raw)
	local f = T.FIELDS[key]
	if not f then return false, "unknown setting '" .. tostring(key) .. "'" end
	local v
	if f.kind == "color" then
		v = Hex(raw)
		if not v then return false, "expected a hex colour such as ff79c6" end
	elseif f.kind == "number" then
		v = tonumber(raw)
		if not v then return false, "expected a number from " .. f.min .. " to " .. f.max end
		v = math.floor(v / f.step + 0.5) * f.step
		v = math.max(f.min, math.min(f.max, v))
		v = tonumber(("%.2f"):format(v))
	elseif f.kind == "bool" then
		local s = tostring(raw):lower()
		if s == "true" or s == "on" or s == "1" or s == "yes" then v = true
		elseif s == "false" or s == "off" or s == "0" or s == "no" then v = false
		else return false, "expected on or off" end
	elseif f.kind == "choice" then
		local s = tostring(raw):lower()
		for _, c in ipairs(f.choices) do
			if c == s or c:sub(1, #s) == s and #s > 0 then v = c break end
		end
		if not v then return false, "expected one of: " .. table.concat(f.choices, ", ") end
	elseif f.kind == "text" then
		v = tostring(raw or ""):gsub("|", "")
		if v == "" then return false, "prompt can't be empty" end
		local chars = select(2, v:gsub("[^\128-\191]", "")) -- UTF-8 characters, not bytes
		if chars > f.max then
			return false, "prompt can be at most " .. f.max .. " characters"
		end
	end
	local t = T.Get()
	t[key] = v
	if PRESET_KEYS[key] then t.preset = "custom" end
	T.Changed()
	return true, v
end

function T.FindPreset(name)
	name = tostring(name or ""):lower()
	if T.PRESETS[name] then return name end
	for _, id in ipairs(T.PRESET_ORDER) do
		if #name > 0 and id:sub(1, #name) == name then return id end
	end
end

function T.ApplyPreset(name)
	local id = T.FindPreset(name)
	if not id then return false end
	local t = T.Get()
	for k, v in pairs(T.PRESETS[id]) do
		if k ~= "label" then t[k] = v end
	end
	t.preset = id
	T.Changed()
	return true, id
end

function T.Reset()
	if ns.db then ns.db.theme = nil end
	T.Get()
	T.Changed()
end

----------------------------------------------------------------------
-- Terminal commands
----------------------------------------------------------------------

ns:RegisterCommand("theme", {
	desc = "List themes, or apply one: .theme dracula  (.theme reset)",
	aliases = { "themes" },
	run = function(args)
		args = strtrim(args or "")
		if args == "reset" then
			T.Reset()
			return { "Theme reset to defaults." }
		end
		if args ~= "" then
			local ok, id = T.ApplyPreset(args)
			if not ok then return { "No theme called '" .. args .. "'. Try .theme" } end
			return { "Theme: " .. T.PRESETS[id].label }
		end
		local cur = T.Get().preset
		local lines = { "Themes (.theme <name>):" }
		for _, id in ipairs(T.PRESET_ORDER) do
			lines[#lines + 1] = ("  %s%s"):format(T.PRESETS[id].label, id == cur and "  (current)" or "")
		end
		if cur == "custom" then lines[#lines + 1] = "  (current colours are customised)" end
		lines[#lines + 1] = "Fine-tune with .set, or the options panel: .options"
		return lines
	end,
})

ns:RegisterCommand("set", {
	desc = "Show or change a setting: .set accent ff79c6",
	aliases = { "config" },
	run = function(args)
		local key, value = strtrim(args or ""):match("^(%S*)%s*(.-)$")
		local t = T.Get()
		if key == "" then
			local lines = { "Settings (.set <name> <value>):" }
			for _, k in ipairs(T.ORDER) do
				lines[#lines + 1] = ("  %s = %s   (%s)"):format(k, T.Format(k, t[k]), T.FIELDS[k].label)
			end
			return lines
		end
		-- accept settings in any case
		for _, k in ipairs(T.ORDER) do
			if k:lower() == key:lower() then key = k break end
		end
		if value == "" then
			if not T.FIELDS[key] then return { "Unknown setting '" .. key .. "'. Try .set" } end
			return { ("%s = %s"):format(key, T.Format(key, t[key])) }
		end
		local ok, res = T.Set(key, value)
		if not ok then return { "Can't set " .. key .. ": " .. res } end
		return { ("%s = %s"):format(key, T.Format(key, res)) }
	end,
})
