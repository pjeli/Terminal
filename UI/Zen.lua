local ns = select(2, ...)

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

local Z = {}
ns.Zen = Z

Z.DIM = 0.55 -- (how dark the screen gets: the black frame's alpha)
Z.IN, Z.OUT = 0.25, 0.4 -- (s: fading away as Terminal opens; coming back as it closes; 0.46.8, the player: a bit faster)
Z.WATCH = 0.25 -- (s: while one of Terminal's apps shows in its place, checked this often)
-- frames that don't follow UIParent's alpha, faded on their own (0.46.8, the player: the minimap's icons stayed up)
Z.ALSO = { "Minimap", "MinimapCluster" }
-- Terminal's frames that sit on UIParent (its apps' frames come from the Panel registry)
Z.OWN = { "TerminalFrame", "TerminalTooltip", "TerminalRowMenu", "TerminalLinkFrame", "TerminalCopyFrame",
	"TerminalStyleImport" } -- (not the click catcher: a secure button, invisible anyway)

local level, target = 0, 0 -- (0: the interface as it was; 1: faded away, the screen dimmed)
local uiAlpha -- UIParent's alpha before the fade (put back exactly)
local also -- Z.ALSO's frames -> their alpha before the fade
local dim, driver
local kept = {} -- Terminal's frames already set to ignore UIParent's alpha
local watching = false

local function On() return ns.db and ns.db.zen == true end

--- Whether this client can fade the interface and keep Terminal up (else only the screen dims).
function Z.Can()
	return _G.UIParent ~= nil and type(_G.UIParent.SetIgnoreParentAlpha) == "function"
end

local function Dim()
	if dim then return dim end
	dim = CreateFrame("Frame", "TerminalZenDim", UIParent)
	dim:SetFrameStrata("HIGH") -- (over the interface, under the terminal)
	dim:SetAllPoints(UIParent)
	dim:EnableMouse(false) -- (clicks go through to the world)
	if dim.SetIgnoreParentAlpha then pcall(dim.SetIgnoreParentAlpha, dim, true) end
	local t = dim:CreateTexture(nil, "BACKGROUND")
	t:SetAllPoints(dim)
	t:SetColorTexture(0, 0, 0, 1)
	dim.tex = t
	dim:SetAlpha(0)
	dim:Hide()
	Z.dim = dim
	return dim
end

local function Keep(f)
	if type(f) ~= "table" or kept[f] or type(f.SetIgnoreParentAlpha) ~= "function" then return end
	if pcall(f.SetIgnoreParentAlpha, f, true) then kept[f] = true end
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
		if level == 0 then Done() end
	end
end

local function MoveTo(t, instant)
	driver = driver or CreateFrame("Frame")
	Z.driver = driver
	target = t
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
	if not Z.active then ns:Trace("zen: Terminal opened, the interface fades and the screen dims") end
	Z.active = true
	MoveTo(1)
	return true
end

--- Everything back: smoothly, or at once (combat, .zen off, a loading screen).
function Z.Leave(instant)
	if not Z.active and level == 0 then return false end
	MoveTo(0, instant)
	return true
end

--- Whether one of Terminal's apps shows (in the terminal's place: they count as Terminal).
local function AppShown()
	for _, app in ipairs(ns.Panel and ns.Panel.Registered() or {}) do
		if type(app.IsShown) == "function" and app.IsShown() then return true end
	end
	return false
end

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
	desc = "While Terminal is open, fade the rest of the interface and dim the screen; .zen again turns it off",
	aliases = { "hideui", "minimal" },
	complete = function() return { { "on", "fade the interface while Terminal is open" }, { "off", "leave it alone" } } end,
	run = function(args)
		local a = strtrim(args or ""):lower()
		local want
		if a == "on" then want = true elseif a == "off" then want = false else want = not On() end
		Z.Set(want)
		if want then
			return { Z.Can()
				and "Zen on: while Terminal is open, the rest of the interface fades away and the screen dims. Closing Terminal brings it back, and so does combat, at once. .zen again turns it off."
				or "Zen on: while Terminal is open the screen dims (this client can't fade the interface and keep Terminal up). .zen again turns it off." }
		end
		return { "Zen off: the interface stays up while Terminal is open." }
	end,
})

function Z.OnEvent(event, ...)
	if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" then
		if Z.Leave(true) then ns:Trace("zen: " .. (event == "PLAYER_REGEN_DISABLED" and "combat" or "a loading screen") .. ": the interface is back at once") end
	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
		local kind, state = ...
		local E, S = Enum and Enum.AddOnRestrictionType, Enum and Enum.AddOnRestrictionState
		if E and kind == E.Combat and not (S and state == S.Inactive) then Z.Leave(true) end
	end
end

local ev = CreateFrame("Frame")
Z.frame = ev
for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_LEAVING_WORLD", "ADDON_RESTRICTION_STATE_CHANGED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, ...) Z.OnEvent(event, ...) end)
