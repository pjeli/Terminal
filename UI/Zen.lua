local ns = select(2, ...)
local L = ns.L

-- .zen (a setting, remembered): while Terminal is open, the rest of the game's interface fades away and the screen dims
-- behind it; closing Terminal brings everything back smoothly, and combat brings it back at once (and Terminal opened in
-- combat leaves the interface alone). Terminal's apps (.atop, .changelog, F1's keys...) count as Terminal: the
-- interface comes back once the last of them closes.
--
-- How: UIParent's alpha (every frame of the interface is under it) is faded, and Terminal's own frames are set to
-- ignore their parent's alpha (SetIgnoreParentAlpha), so they stay as they are; a black frame over the world and under
-- Terminal (HIGH strata, the terminal is DIALOG) dims the screen. Alpha only: nothing is hidden or moved, so key
-- bindings, secure buttons and clicks all work as before (a faded bar still takes a click where it is). Alpha isn't
-- protected, and nothing of Blizzard's Lua is called. A client without SetIgnoreParentAlpha only gets the dimming.
--
-- The dimming takes the weather's colour (0.50.6, the player's ask: subtle): bluer in rain, paler in snow, warmer in a
-- sandstorm, as strong as the weather is (C_Weather.GetCurrentWeather: its type and intensity, 12.1.5); clear skies,
-- other weather, under a roof (IsIndoors) or a client without C_Weather: plain black, as before. Weather that turns
-- while the screen is dimmed (WEATHER_CHANGED; walking in or out of a building, looked at every second) fades to the
-- new colour over Z.TINT_FADE.

local Z = {}
ns.Zen = Z

Z.DIM = 0.55 -- (how dark the screen gets: the black frame's alpha)
Z.IN, Z.OUT = 0.2, 0.2 -- (s: fading away as Terminal opens; coming back as it closes; the player's, 0.46.13)
Z.WATCH = 0.25 -- (s: while one of Terminal's apps shows in its place, checked this often)
-- frames that don't follow UIParent's alpha, faded on their own (0.46.8, the player: the minimap's icons stayed up),
-- and the frame-rate counter (0.48.8, the player: it showed through: its parent is WorldFrame, not UIParent, as the
-- game's Blizzard_FramerateFrame makes it; one turned on while faded stays faded, its alpha already 0)
Z.ALSO = { "Minimap", "MinimapCluster", "FramerateFrame" }
-- frames whose drawing ignores alpha altogether: the minimap's blips (party members, tracked herbs and ores, quest
-- spots: the engine draws them on the minimap at full strength). Hidden as the fade starts (0.46.13, the player:
-- sooner; 0.46.11 hid them once it was done), shown again the moment it turns back or combat comes (0.46.11, the
-- player's screenshot: the blips stayed up). Blizzard's own minimap key
-- does the same (ToggleMinimap: Minimap:Hide()); one you hid yourself is left alone.
Z.HIDE = { "Minimap" }
-- Terminal's frames that sit on UIParent (its apps' frames come from the Panel registry)
Z.OWN = { "TerminalFrame", "TerminalTooltip", "TerminalRowMenu", "TerminalLinkFrame", "TerminalCopyFrame",
	"TerminalStyleImport", "TerminalBusyTip" } -- (not the click catcher: a secure button, invisible anyway; the busy
	-- spinner's tooltip: 0.49.2, review)

local level, target = 0, 0 -- (0: the interface as it was; 1: faded away, the screen dimmed)
local uiAlpha -- UIParent's alpha before the fade (put back exactly)
local also -- Z.ALSO's frames -> their alpha before the fade
local dim, driver
local kept = {} -- Terminal's frames already set to ignore UIParent's alpha
local hidden = {} -- Z.HIDE's frames this fade hid (shown again as it ends)
local watching = false

local function On() return ns.db and ns.db.zen == true end

local Safe, Num = ns.Safe, ns.Num

-- the weather's colours at its strongest (the dimming's colour; times the weather's intensity, so a drizzle barely
-- shows), by Enum.WeatherType's names: Clear 0, Rain 1, Snow 2, Sandstorm 3, Miscellaneous 4 (ash, blood rain...: none)
Z.TINTS = {
	Rain = { 0.05, 0.10, 0.24 }, -- bluer
	Snow = { 0.30, 0.32, 0.36 }, -- paler (a grey in place of the black: the screen washed out)
	Sandstorm = { 0.30, 0.19, 0.06 }, -- warmer
}
Z.TINT_FADE = 2.5 -- (s: from one weather's colour to the next)
Z.POLL = 1 -- (s: while dimmed, the weather looked at again this often: indoors has no event)
local TYPE_IDS = { Clear = 0, Rain = 1, Snow = 2, Sandstorm = 3, Miscellaneous = 4 }

--- The weather here: its Enum.WeatherType name and intensity (0-1); nil with no C_Weather, an unreadable answer, or
--- indoors (under a roof the weather isn't seen).
function Z.Weather()
	local CW = _G.C_Weather
	if not (CW and type(CW.GetCurrentWeather) == "function") then return nil end
	local info = Safe(CW.GetCurrentWeather)
	if type(info) ~= "table" then return nil end
	local kind, i = Num(info.type), Num(info.intensity)
	if not (kind and i) or i ~= i then return nil end -- (a secret value, or NaN: not known)
	if _G.IsIndoors and Safe(_G.IsIndoors) then return nil end
	local ids = (_G.Enum and type(_G.Enum.WeatherType) == "table") and _G.Enum.WeatherType or TYPE_IDS
	local name
	for n, id in pairs(ids) do if id == kind then name = n end end
	return name, math.max(0, math.min(1, i))
end

--- The dimming's colour for the weather now: r, g, b (black for none).
function Z.TintFor()
	local name, i = Z.Weather()
	local c = name and Z.TINTS[name]
	if not c or i <= 0 then return 0, 0, 0 end
	return c[1] * i, c[2] * i, c[3] * i
end

local tint = { 0, 0, 0 } -- the colour the dimming has now
local tintFrom, tintTo, tintT -- a fade between two colours: from, to, how far along (0-1); nil: none
local tinter, sincePoll = nil, 0

--- Whether this client can fade the interface and keep Terminal up (else only the screen dims).
function Z.Can()
	return _G.UIParent ~= nil and type(_G.UIParent.SetIgnoreParentAlpha) == "function"
end

local function Dim()
	if dim then return dim end
	dim = CreateFrame("Frame", "TerminalZenDim", UIParent)
	dim:SetFrameStrata("HIGH") -- (over the interface, under the terminal)
	dim:SetFrameLevel(1) -- (under the drag grid, also HIGH)
	dim:SetAllPoints(UIParent)
	dim:EnableMouse(false) -- (clicks go through to the world)
	if dim.SetIgnoreParentAlpha then pcall(dim.SetIgnoreParentAlpha, dim, true) end
	local t = dim:CreateTexture(nil, "BACKGROUND")
	t:SetAllPoints(dim)
	t:SetColorTexture(tint[1], tint[2], tint[3], 1)
	dim.tex = t
	dim:SetAlpha(0)
	dim:Hide()
	Z.dim = dim
	return dim
end

local function SetTint(r, g, b)
	tint = { r, g, b }
	if dim then dim.tex:SetColorTexture(r, g, b, 1) end
end
local function Same(a, r, g, b) return math.abs(a[1] - r) + math.abs(a[2] - g) + math.abs(a[3] - b) < 0.004 end

--- The dimming's colour to the weather's now: faded to it, or at once (Terminal just opened: the dimming fades in
--- already; animations off). Nothing when it's already there or on its way.
function Z.Retint(instant)
	local r, g, b = Z.TintFor()
	if Same(tintTo or tint, r, g, b) then return end
	if instant or not (ns.Theme and ns.Theme.Animation()) then
		tintFrom, tintTo, tintT = nil, nil, nil
		SetTint(r, g, b)
		return
	end
	if tintTo then ns:Trace("zen: the weather turned again mid-fade") end
	tintFrom, tintTo, tintT = { tint[1], tint[2], tint[3] }, { r, g, b }, 0
end

-- while dimmed: the colour's fade, and the weather looked at again every Z.POLL (indoors has no event)
local function TintTick(_, elapsed)
	elapsed = tonumber(elapsed) or 0
	if tintTo then
		tintT = math.min(1, tintT + elapsed / Z.TINT_FADE)
		local e = tintT * tintT * (3 - 2 * tintT)
		SetTint(tintFrom[1] + (tintTo[1] - tintFrom[1]) * e, tintFrom[2] + (tintTo[2] - tintFrom[2]) * e,
			tintFrom[3] + (tintTo[3] - tintFrom[3]) * e)
		if tintT >= 1 then tintFrom, tintTo, tintT = nil, nil, nil end
	end
	sincePoll = sincePoll + elapsed
	if sincePoll >= Z.POLL then
		sincePoll = 0
		Z.Retint(false)
	end
end

local function Tinting(on)
	tinter = tinter or CreateFrame("Frame")
	Z.tinter = tinter
	sincePoll = 0
	tinter:SetScript("OnUpdate", on and TintTick or nil)
	if not on then tintFrom, tintTo, tintT = nil, nil, nil end
end

local function Keep(f)
	if type(f) ~= "table" or kept[f] or type(f.SetIgnoreParentAlpha) ~= "function" then return end
	if pcall(f.SetIgnoreParentAlpha, f, true) then kept[f] = true end
end
Z.Keep = Keep -- (the drag grid, made on the first drag: UI.lua)
function Z.Kept(f) return kept[f] == true end
--- One of Terminal's frames made just now (the tooltip, the row menu, the copy bar... are made the first time they're
--- needed): while the interface is faded it keeps its own alpha at once; later opens keep it by name (Z.OWN). 0.46.17,
--- the player's screenshot: right after a /reload no tooltip ever showed until Terminal was opened again: the tooltip
--- was made after .zen had faded UIParent, and so faded with it, invisible.
function Z.Made(f)
	if Z.active and Z.Can() then Keep(f) end
end

local function HideRest()
	if InCombatLockdown and InCombatLockdown() then return end
	for _, name in ipairs(Z.HIDE) do
		local f = _G[name]
		if type(f) == "table" and not hidden[f] and f.IsShown and f:IsShown() and pcall(f.Hide, f) then hidden[f] = true end
	end
end
local function ShowRest()
	for f in pairs(hidden) do pcall(f.Show, f) end
	hidden = {}
end

--- Terminal's frames keep their own alpha while the interface fades: the named ones and every app's (Panel.Build keeps
--- them). Never a walk over UIParent's children: GetChildren there gives hundreds of values, and through pcall that
--- overflows the C stack (0.46.5: "Assertion failure! L->top < L->ci->top", the game closed; pcall pushes its true
--- after the callee's results, past the room it has).
function Z.KeepOwn()
	for _, name in ipairs(Z.OWN) do Keep(_G[name]) end
	for _, f in ipairs(ns.Panel and ns.Panel.Frames and ns.Panel.Frames() or {}) do Keep(f) end
end

--- The look at a point of the fade (v: 0 = as it was, 1 = faded away), eased.
local function Apply(v)
	local e = v * v * (3 - 2 * v)
	if Z.Can() then
		pcall(UIParent.SetAlpha, UIParent, (uiAlpha or 1) * (1 - e))
		for f, a in pairs(also or {}) do pcall(f.SetAlpha, f, a * (1 - e)) end
	end
	local d = Dim()
	d:SetAlpha(Z.DIM * e)
	if v > 0 then d:Show() else d:Hide() end
end

local function Done()
	Z.active = false
	Tinting(false)
	ShowRest()
	uiAlpha, also = nil, nil
	ns:Trace("zen: the interface is back")
end

local function Tick(_, elapsed)
	local dur = target > level and Z.IN or Z.OUT
	local step = (tonumber(elapsed) or 0) / dur
	if target > level then level = math.min(target, level + step) else level = math.max(target, level - step) end
	Apply(level)
	if level == target then
		driver:SetScript("OnUpdate", nil) -- (runs only while fading)
		if level == 0 then Done() end -- (the minimap was hidden as the fade began: MoveTo)
	end
end

local function MoveTo(t, instant)
	driver = driver or CreateFrame("Frame")
	Z.driver = driver
	target = t
	if t == 0 then ShowRest() else HideRest() end -- (at once both ways: their drawing can't fade)
	if instant or not (ns.Theme and ns.Theme.Animation()) then
		level = t
		Apply(level)
		driver:SetScript("OnUpdate", nil)
		if t == 0 then Done() end
		return
	end
	driver:SetScript("OnUpdate", Tick)
end

--- Terminal opened: the interface fades away, the screen dims. Not in combat, and only with .zen on.
function Z.Opened()
	if not On() or (InCombatLockdown and InCombatLockdown()) then return false end
	if uiAlpha == nil and Z.Can() then
		local ok, a = pcall(UIParent.GetAlpha, UIParent)
		uiAlpha = ok and type(a) == "number" and a or 1
		also = {}
		for _, name in ipairs(Z.ALSO) do
			local f = _G[name]
			if type(f) == "table" and type(f.GetAlpha) == "function" and type(f.SetAlpha) == "function" then
				local okA, fa = pcall(f.GetAlpha, f)
				also[f] = okA and type(fa) == "number" and fa or 1
			end
		end
	end
	if Z.Can() then Z.KeepOwn() end
	if not Z.active then
		ns:Trace("zen: Terminal opened, the interface fades and the screen dims")
		Z.Retint(true) -- (the weather's colour from the start: the dimming fades in already)
		local name, i = Z.Weather()
		ns:Trace(("zen: the weather: %s %s"):format(tostring(name), tostring(i)))
	end
	Z.active = true
	Tinting(true)
	MoveTo(1)
	return true
end

--- Everything back: smoothly, or at once (combat, .zen off, a loading screen).
function Z.Leave(instant)
	if not Z.active and level == 0 then return false end
	MoveTo(0, instant)
	return true
end

local function AppShown() return ns.Panel and ns.Panel.AnyShown() or false end

local function Check()
	watching = false
	if not Z.active then return end
	if ns.UI and ns.UI:IsShown() then return end
	if AppShown() then -- (back when the last app closes)
		watching = true
		C_Timer.After(Z.WATCH, Check)
		return
	end
	Z.Leave(false)
end

--- Terminal closed (its frame hid): everything comes back, unless an app took its place; looked at a frame later, once
--- that app shows.
function Z.Closed()
	if not Z.active or watching then return end
	watching = true
	C_Timer.After(0, Check)
end

function Z.Set(on)
	if not ns.db then return end
	ns.db.zen = on and true or false
	if not on then Z.Leave(true) end
end

ns:RegisterCommand("zen", {
	desc = L["While Terminal is open, fade the rest of the interface and dim the screen; .zen again turns it off"],
	aliases = { "hideui", "minimal" },
	complete = function() return { { "on", L["fade the interface while Terminal is open"] }, { "off", L["leave it alone"] } } end,
	run = function(args)
		local a = strtrim(args or ""):lower()
		local want
		if a == "on" then want = true elseif a == "off" then want = false else want = not On() end
		Z.Set(want)
		if want then
			return { Z.Can()
				and L["Zen on: while Terminal is open, the rest of the interface fades away and the screen dims. Closing Terminal brings it back, and so does combat, at once. .zen again turns it off."]
				or L["Zen on: while Terminal is open the screen dims (this client can't fade the interface and keep Terminal up). .zen again turns it off."] }
		end
		return { L["Zen off: the interface stays up while Terminal is open."] }
	end,
})

function Z.OnEvent(event, ...)
	if event == "WEATHER_CHANGED" then
		if Z.active then Z.Retint(false) end
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" then
		if Z.Leave(true) then ns:Trace("zen: " .. (event == "PLAYER_REGEN_DISABLED" and "combat" or "a loading screen") .. ": the interface is back at once") end
	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
		local kind, state = ...
		local E, S = Enum and Enum.AddOnRestrictionType, Enum and Enum.AddOnRestrictionState
		if E and kind == E.Combat and not (S and state == S.Inactive) then Z.Leave(true) end
	end
end

local ev = CreateFrame("Frame")
Z.frame = ev
for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_LEAVING_WORLD", "ADDON_RESTRICTION_STATE_CHANGED", "WEATHER_CHANGED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, ...) Z.OnEvent(event, ...) end)
