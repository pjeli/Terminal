local ns = select(2, ...)

-- Theme: colours, font and layout of the terminal. Stored per account in TerminalDB.theme
-- and applied live. Change it from the terminal ( .theme, .set ) or the options panel.

local T = {}
ns.Theme = T

--- A colour made darker (f < 1) or lighter (f > 1): the prompt's background is the
--- theme's background, slightly darker.
local PROMPT_DARKEN = 0.7
function T.Darken(hex, f)
	local r, g, b = tostring(hex or ""):match("^(%x%x)(%x%x)(%x%x)$")
	if not r then return hex end
	local function c(x) return math.max(0, math.min(255, math.floor(tonumber(x, 16) * f + 0.5))) end
	return ("%02x%02x%02x"):format(c(r), c(g), c(b))
end

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
	promptBg = "322416", -- the prompt's background (slightly darker than bg)
	border = "b08040",
	bgAlpha = 0.95,
	frame = "classic",   -- classic: the game's tooltip-style frame; flat: a thin line
	font = "friz",
	fontSize = 13,
	width = 640,
	rows = 10,
	scale = 1.0,
	hints = true,
	animations = "smooth", -- how the terminal moves: a style from T.ANIMATIONS, or "off" (everything snaps)
	cursor = "blinking-line", -- the text cursor: blinking or solid, a line or a box
	blinkRate = 0.8, -- blinks per second
	autoScan = true, -- index professions quietly after login
	syntax = true, -- colour what's typed: @kinds, filters, .commands, /slash commands
	v = 3, -- theme defaults version (see T.Get)
}

T.PRESET_ORDER = { "forever", "foreverblue", "midnight", "matrix", "dracula", "solarized", "horde", "alliance",
	"wowhead", "allakhazam", "thottbot", "mmochampion" }
T.PRESETS = {
	forever = { label = "Forever", bg = "47331f", border = "b08040", accent = "c79c4e", prompt = "6db8ff", text = "ffd100", dim = "c9c2b0", match = "ffffff", bgAlpha = 0.95, frame = "classic" },
	foreverblue = { label = "Forever Blue", bg = "47331f", border = "b08040", accent = "c79c4e", prompt = "ffd100", text = "a8d8ff", dim = "d6c49a", match = "ffd100", bgAlpha = 0.95, frame = "classic" },
	midnight = { label = "Midnight", bg = "0d0f14", border = "40475a", accent = "ffd200", prompt = "33ff99", text = "ffffff", dim = "8c8c8c", match = "ffd200", bgAlpha = 0.96, frame = "flat" },
	matrix = { label = "Matrix", bg = "000a00", border = "0f6b26", accent = "00ff66", prompt = "00ff66", text = "c8ffc8", dim = "4f8f5f", match = "9dff9d", bgAlpha = 0.95, frame = "flat" },
	dracula = { label = "Dracula", bg = "282a36", border = "44475a", accent = "bd93f9", prompt = "50fa7b", text = "f8f8f2", dim = "8b9bd0", match = "ff79c6", bgAlpha = 0.97, frame = "flat" },
	solarized = { label = "Solarized", bg = "002b36", border = "2a5a66", accent = "b58900", prompt = "859900", text = "c5d1d1", dim = "8aa1a6", match = "e8743b", bgAlpha = 0.97, frame = "flat" },
	horde = { label = "Horde", bg = "1f0505", border = "8c1a0d", accent = "ff3b1f", prompt = "ff8a00", text = "f2e6d9", dim = "b09088", match = "ffb000", bgAlpha = 0.96, frame = "classic" },
	alliance = { label = "Alliance", bg = "050d24", border = "1a4099", accent = "3fa9ff", prompt = "ffd100", text = "e6eeff", dim = "8e9dc4", match = "7fd4ff", bgAlpha = 0.96, frame = "classic" },
	-- the old database sites, for fun
	-- Wowhead: charcoal pages, orange logo, gold highlights
	wowhead = { label = "Wowhead", bg = "1b1b1b", border = "505050", accent = "ff8c1a", prompt = "ffd100", text = "e8e8e8", dim = "a0a0a0", match = "ffcc33", bgAlpha = 0.97, frame = "flat" },
	-- Allakhazam: tan parchment, dark brown text, oxblood links (light)
	allakhazam = { label = "Allakhazam", bg = "efe4c6", promptBg = "e0d2ab", border = "7a3b1e", accent = "8a1c12", prompt = "8a1c12", text = "2b1a0c", dim = "5e4429", match = "a8230f", bgAlpha = 0.98, frame = "flat" },
	-- Thottbot: a plain white page ("blinding whiteness"), black text, blue links
	thottbot = { label = "Thottbot", bg = "fbfcfe", promptBg = "e4eaf4", border = "3a5f9f", accent = "2a5db0", prompt = "0a3d91", text = "111111", dim = "545b66", match = "c41a00", bgAlpha = 0.98, frame = "flat" },
	-- MMO-Champion: black page, green text
	mmochampion = { label = "MMO-Champion", bg = "050805", border = "3f6a2c", accent = "5fbf2a", prompt = "9cff3c", text = "d6ead0", dim = "86a37f", match = "d4ff6a", bgAlpha = 0.97, frame = "flat" },
}

for _, p in pairs(T.PRESETS) do
	p.promptBg = p.promptBg or T.Darken(p.bg, PROMPT_DARKEN)
end
T.DEFAULTS.promptBg = T.PRESETS.forever.promptBg

T.FONTS = {
	friz = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
	arial = "Fonts\\ARIALN.TTF",
	morpheus = "Fonts\\MORPHEUS.TTF",
	skurri = "Fonts\\SKURRI.TTF",
}
T.FONT_ORDER = { "friz", "arial", "morpheus", "skurri" }

-- What each setting accepts. Order is how .set lists them.
T.ORDER = { "promptText", "prompt", "accent", "match", "text", "dim", "bg", "promptBg", "border", "bgAlpha",
	"frame", "font", "fontSize", "width", "rows", "scale", "hints", "animations", "cursor", "blinkRate", "autoScan", "syntax" }
T.CURSOR_ORDER = { "blinking-line", "solid-line", "blinking-box", "solid-box" }

-- Animation styles: open/close (seconds; `fade`: how long the opening fade takes, if not the whole
-- opening), drift (pixels the terminal travels: up from below when positive, down from above when
-- negative), ease ("back": overshoots and settles), rows fading in (seconds, the delay between rows,
-- how far they slide in from the left; foldOut: they leave the same way, bottom-up), and speed (how
-- fast the selection, caret and height glide; 100: they jump).

--- Eases for the styles: cubic ease-out, and "back" (overshoots a little, then settles).
function T.Ease(x)
	if x ~= x or x <= 0 then return 0 elseif x >= 1 then return 1 end
	local u = 1 - x
	return 1 - u * u * u
end
function T.Move(A, x) -- how far along a movement is (may pass 1 for "back")
	if x ~= x or x <= 0 then return 0 elseif x >= 1 then return 1 end
	if A and A.ease == "back" then
		local c1 = 1.70158
		local u = x - 1
		return 1 + (c1 + 1) * u * u * u + c1 * u * u
	end
	return T.Ease(x)
end
T.ANIMATION_ORDER = { "smooth", "snappy", "floaty", "cascade", "dropdown", "off" }
T.ANIMATION_LABELS = { smooth = "Smooth", snappy = "Snappy", floaty = "Floaty", cascade = "Cascade",
	dropdown = "Drop Down", off = "Off" }
T.ANIMATIONS = {
	smooth = { open = 0.18, close = 0.12, drift = 10, closeDrift = 6, rowFade = 0.14, stagger = 0.018, slide = 0, speed = 1 },
	-- pops in with a little bounce (it overshoots and settles), shows up almost at once, and the
	-- selection and caret jump instead of gliding
	snappy = { open = 0.26, fade = 0.05, close = 0.06, drift = 18, closeDrift = 0, ease = "back", rowFade = 0.04,
		stagger = 0, slide = 0, speed = 100 },
	floaty = { open = 0.34, close = 0.22, drift = 22, closeDrift = 12, rowFade = 0.26, stagger = 0.03, slide = 0, speed = 0.55 },
	-- the rows swing in one after another from well to the left, overshooting a little, and fold
	-- away bottom-up when it closes
	cascade = { open = 0.12, close = 0.3, drift = 0, closeDrift = 0, ease = "back", rowFade = 0.3, stagger = 0.06,
		slide = 44, foldOut = true, speed = 0.8 },
	-- drops down from above, like a game console, and goes back up
	dropdown = { open = 0.22, close = 0.16, drift = -60, closeDrift = -60, rowFade = 0.1, stagger = 0, slide = 0, speed = 1.3 },
}

--- The animation style in use (a table from T.ANIMATIONS), or nil when animations are off.
function T.Animation(t)
	local a = (t or T.Get()).animations
	if a == false or a == "off" then return nil end
	return T.ANIMATIONS[a] or T.ANIMATIONS.smooth
end
T.CURSOR_LABELS = { ["blinking-line"] = "Blinking line", ["solid-line"] = "Solid line", ["blinking-box"] = "Blinking box", ["solid-box"] = "Solid box" }
T.FIELDS = {
	promptText = { kind = "text", label = "Prompt", max = 3 },
	prompt = { kind = "color", label = "Prompt colour" },
	accent = { kind = "color", label = "Selection" },
	match = { kind = "color", label = "Match highlight" },
	text = { kind = "color", label = "Text" },
	dim = { kind = "color", label = "Details" },
	bg = { kind = "color", label = "Background" },
	promptBg = { kind = "color", label = "Prompt background" },
	border = { kind = "color", label = "Border" },
	bgAlpha = { kind = "number", label = "Opacity", min = 0.3, max = 1, step = 0.01 },
	frame = { kind = "choice", label = "Frame", choices = { "classic", "flat" } },
	font = { kind = "choice", label = "Font", choices = T.FONT_ORDER },
	fontSize = { kind = "number", label = "Font size", min = 10, max = 22, step = 1 },
	width = { kind = "number", label = "Width", min = 420, max = 1100, step = 10 },
	rows = { kind = "number", label = "Max rows", min = 4, max = 20, step = 1 },
	scale = { kind = "number", label = "Scale", min = 0.6, max = 1.6, step = 0.05 },
	hints = { kind = "bool", label = "Key hints in footer" },
	syntax = { kind = "bool", label = "Colour what you type" },
	animations = { kind = "choice", label = "Animation", choices = T.ANIMATION_ORDER },
	cursor = { kind = "choice", label = "Cursor", choices = T.CURSOR_ORDER },
	blinkRate = { kind = "number", label = "Blink speed", min = 0.2, max = 3, step = 0.1 },
	autoScan = { kind = "bool", label = "Index professions at login" },
}
local PRESET_KEYS = { frame = true, promptBg = true, bg = true, border = true, accent = true, prompt = true, text = true, dim = true, match = true, bgAlpha = true }

----------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------

local checked -- the theme table already migrated and filled in (Get runs many times a frame)

--- Copies a preset's colours (everything but its label) into t.
local function CopyPreset(t, id)
	for k, v in pairs(T.PRESETS[id]) do
		if k ~= "label" then t[k] = v end
	end
end

function T.Get()
	local db = ns.db
	if not db then return T.DEFAULTS end
	local t = db.theme
	if t and t == checked then return t end
	t = t or {}
	db.theme = t
	-- themes saved before the Forever look became the default: an untouched old default
	-- ("midnight") moves to the new one; anything the player picked or tuned stays
	if t.v == nil and next(t) ~= nil then
		if t.preset == "midnight" then
			CopyPreset(t, "forever")
			t.preset = "forever"
		end
		t.frame = t.frame or ((T.PRESETS[t.preset] or {}).frame) or "flat"
		t.v = 2
	end
	-- v3: the Forever themes went from black to the scroll brown
	if t.v == 2 then
		if (t.preset == "forever" or t.preset == "foreverblue") and t.bg == "000000" then
			CopyPreset(t, t.preset)
		end
		t.v = 3
	end
	-- animations were on/off before there were styles
	if t.animations == true then t.animations = "smooth" elseif t.animations == false then t.animations = "off" end
	if t.animations == "console" then t.animations = "dropdown" end -- its name in 0.29.0
	-- themes saved before the prompt had its own background: a slightly darker bg
	if t.promptBg == nil and t.bg then t.promptBg = T.Darken(t.bg, PROMPT_DARKEN) end
	-- a theme that no longer exists (Paper, Parchment) falls back to the default look
	if t.preset and t.preset ~= "custom" and not T.PRESETS[t.preset] then
		CopyPreset(t, "forever")
		t.preset = "forever"
	end
	for k, v in pairs(T.DEFAULTS) do
		if t[k] == nil then t[k] = v end
	end
	checked = t
	return t
end

function T.RGB(hex)
	local r, g, b = tostring(hex or ""):match("^(%x%x)(%x%x)(%x%x)$")
	if not r then return 1, 1, 1 end
	return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local lightBg, light -- the last background asked about, and the answer
function T.IsLight()
	local bg = T.Get().bg
	if bg ~= lightBg then
		local r, g, b = T.RGB(bg)
		lightBg, light = bg, (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
	end
	return light
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
-- the prompt's colours for what it recognises (UI:Highlighted); @kinds use their own colour,
-- .commands the accent, /slash commands the prompt colour, plain words the text colour
T.SYNTAX = { filter = "6ee7a8", bad = "ff6b6b" }

function T.FixColors(s)
	if type(s) ~= "string" or not T.IsLight() then return s end
	return (s:gsub("|c(%x%x)(%x%x%x%x%x%x)", function(a, h) return "|c" .. a .. T.Readable(h:lower()) end))
end

--- The colour for text drawn on top of `under` (the character under a box cursor): the
--- theme's background if that reads clearly there, else black or white, whichever is clearer.
local function Ratio(a, b)
	local ar, ag, ab = T.RGB(a)
	local br, bg, bb = T.RGB(b)
	local x, y = Lum(ar, ag, ab), Lum(br, bg, bb)
	if x < y then x, y = y, x end
	return (x + 0.05) / (y + 0.05)
end

function T.OnColor(under, prefer)
	if prefer and Ratio(prefer, under) >= 4.5 then return prefer end
	return Ratio("000000", under) >= Ratio("ffffff", under) and "000000" or "ffffff"
end

function T.Format(key, v)
	local f = T.FIELDS[key]
	if not f then return tostring(v) end
	if f.kind == "bool" then return v and "on" or "off" end
	if f.kind == "number" then
		if key == "blinkRate" then return ("%.1f/s"):format(v) end
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

--- Validates and stores one setting. Returns ok, value-or-error. `quiet`: don't redraw yet (a batch, T.Import).
function T.Set(key, raw, quiet)
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
		-- animations used to be on/off
		if key == "animations" and (s == "on" or s == "true" or s == "yes" or s == "1") then s = "smooth" end
		if key == "animations" and (s == "false" or s == "no" or s == "0") then s = "off" end
		if key == "animations" and (s == "console" or s == "drop" or s == "drop down" or s == "drop-down") then s = "dropdown" end
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
	-- a new background takes the prompt background along, unless that was set by hand
	if key == "bg" and t.promptBg == T.Darken(t.bg, PROMPT_DARKEN) then
		t.promptBg = T.Darken(v, PROMPT_DARKEN)
	end
	t[key] = v
	if PRESET_KEYS[key] then t.preset = "custom" end
	if not quiet then T.Changed() end
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
	CopyPreset(t, id)
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
-- Style strings: the look as one line, to paste in chat or a forum post
----------------------------------------------------------------------

-- "TERM1:bg=47331f; accent=c79c4e; ...": the look's settings (colours, opacity, frame, font, cursor, animation,
-- prompt text), not the layout (width, rows, scale: they fit a screen, not a style) nor behaviour (hints,
-- autoScan, syntax). Values as `.set` takes them, so one string works across versions: a key this version
-- doesn't know is skipped. Under 255 characters, so a chat message carries one.
T.STYLE_MARK = "TERM1:"
T.STYLE_KEYS = { "prompt", "accent", "match", "text", "dim", "bg", "promptBg", "border", "bgAlpha", "frame",
	"font", "fontSize", "promptText", "cursor", "blinkRate", "animations" }

local function EncodeValue(v)
	-- the prompt text can hold anything: ';', '=', '%' and spaces are written as %XX
	return (tostring(v):gsub("[;=%%%s]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function DecodeValue(s)
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

--- Which preset the look is, if its colours are exactly one of them (else "custom").
function T.MatchPreset(t)
	for _, id in ipairs(T.PRESET_ORDER) do
		local same = true
		for k in pairs(PRESET_KEYS) do
			if t[k] ~= T.PRESETS[id][k] then same = false break end
		end
		if same then return id end
	end
	return "custom"
end

--- The current look as a style string.
function T.Export()
	local t = T.Get()
	local parts = {}
	for _, k in ipairs(T.STYLE_KEYS) do
		local v = t[k]
		if T.FIELDS[k].kind == "number" then v = T.Format(k, v):gsub("/s$", "") end -- "0.95", "13", "0.8"
		parts[#parts + 1] = k .. "=" .. EncodeValue(v)
	end
	return T.STYLE_MARK .. table.concat(parts, "; ") -- (a space after each ';' lets the text wrap where it's shown)
end

--- Applies a style string. Returns ok, message: how many settings were set (and skipped), or what was wrong.
--- Anything around the string (a chat line's name and time, spaces) is ignored; only known settings
--- change, each checked as `.set` would.
function T.Import(s)
	s = tostring(s or "")
	local at = s:find(T.STYLE_MARK, 1, true)
	if not at then return false, "not a Terminal style: it starts with " .. T.STYLE_MARK end
	local body = s:sub(at + #T.STYLE_MARK):gsub(";%s+", ";"):match("^[^%s|]*") or ""
	local t = T.Get()
	local set, skipped, bad = 0, 0, {}
	local keep = {}
	for k, v in pairs(t) do keep[k] = v end -- all or nothing: a bad value leaves the look as it was
	for pair in body:gmatch("[^;]+") do
		local k, v = pair:match("^([%w_]+)=(.*)$")
		if k and T.FIELDS[k] then
			local ok, res = T.Set(k, DecodeValue(v), true)
			if ok then set = set + 1 else bad[#bad + 1] = k .. ": " .. tostring(res) end
		else
			skipped = skipped + 1
		end
	end
	if #bad > 0 or set == 0 then
		for k in pairs(t) do t[k] = nil end
		for k, v in pairs(keep) do t[k] = v end
		if set == 0 and #bad == 0 then return false, "no settings in that style string" end
		return false, "not applied: " .. table.concat(bad, "; ")
	end
	t.preset = T.MatchPreset(t)
	T.Changed()
	local msg = set .. " settings applied"
	if skipped > 0 then msg = msg .. " (" .. skipped .. " unknown skipped)" end
	if t.preset ~= "custom" then msg = msg .. ": " .. T.PRESETS[t.preset].label end
	return true, msg
end

ns:RegisterCommand("style", {
	desc = "Share the look: .style copies it as a string, .style TERM1:... applies one",
	aliases = { "skin", "look" },
	complete = function(args)
		if (args or "") ~= "" then return {} end
		return { { "export", "the current look as a string, to copy" }, { "import", "paste a style string after it" } }
	end,
	run = function(args)
		args = strtrim(args or "")
		if args == "" or args == "export" then
			ns:ShowText("Terminal style: paste it to a friend", T.Export(), { compact = true })
			return {}
		end
		local ok, msg = T.Import((args:gsub("^import%s*", "")))
		if not ok then return { "Style: " .. msg } end
		return { "Style: " .. msg }
	end,
})

----------------------------------------------------------------------
-- Terminal commands
----------------------------------------------------------------------

ns:RegisterCommand("theme", {
	desc = "List themes, or apply one: .theme dracula  (.theme reset)",
	aliases = { "themes" },
	-- Tab completion (and the rows shown while typing): theme names
	complete = function()
		local cur = T.Get().preset
		local out = {}
		for _, id in ipairs(T.PRESET_ORDER) do
			out[#out + 1] = { id, T.PRESETS[id].label .. (id == cur and "  (current)" or "") }
		end
		out[#out + 1] = { "reset", "back to the defaults" }
		return out
	end,
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
	-- Tab completion: setting names, then the values a setting takes
	complete = function(args)
		local t = T.Get()
		local key = args:match("^(%S+)%s")
		if not key then
			local out = {}
			for _, k in ipairs(T.ORDER) do
				out[#out + 1] = { k, T.FIELDS[k].label .. ":  " .. T.Format(k, t[k]) }
			end
			return out
		end
		for _, k in ipairs(T.ORDER) do
			if k:lower() == key:lower() then
				local f = T.FIELDS[k]
				local values = (f.kind == "bool" and { "on", "off" }) or (f.kind == "choice" and f.choices) or {}
				local cur = T.Format(k, t[k])
				local out = {}
				for _, v in ipairs(values) do
					local label = (k == "cursor" and T.CURSOR_LABELS[v]) or (k == "animations" and T.ANIMATION_LABELS[v]) or ""
					out[#out + 1] = { v, label .. (v == cur and ((label ~= "" and "  " or "") .. "(current)") or "") }
				end
				return out
			end
		end
		return {}
	end,
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
