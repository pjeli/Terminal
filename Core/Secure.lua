local ns = select(2, ...)
local L = ns.L

-- Secure opening of Blizzard windows.
--
-- In Forever, windows such as the Character frame read "secret" values (your own health,
-- for one) when they show. If Terminal calls ToggleCharacter() from its own Lua, that whole
-- call runs tainted and Blizzard's code errors on the comparison.
--
-- So the terminal never opens those windows itself. When you press Enter on one, Enter is
-- briefly bound to the game's own keybinding command for that window (TOGGLECHARACTER0,
-- TOGGLETALENTS, ...) and the keypress is passed on to the game: the game then runs its
-- own, untainted binding code, exactly as if you had pressed your Character or Talents key.
--
-- If a client lacks the command, a hidden SecureActionButtonTemplate button that clicks
-- the window's micro button is used instead. (Classic-style micro buttons act on mouse
-- down/up rather than a plain click, which is why the binding route comes first.)

local S = {}
ns.Secure = S

local proxies = {}
local owner = CreateFrame("Frame")
local token = 0

--- A hidden secure button off the screen's corner, for the game to press (by a binding or a macro's /click):
--- 1x1, never under the mouse, taking both halves of a click. Placed against UIParent, never Terminal's frames.
local function Offscreen(name)
	local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	b:SetSize(1, 1)
	b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -500, 500)
	b:EnableMouse(false)
	b:RegisterForClicks("AnyUp", "AnyDown")
	return b
end

S.MACRO_MAX = 255 -- the game runs at most this many characters of a macro, all lines together
S.armed = nil -- binding command or button name currently armed
S.mode = nil  -- "binding" or "button"

----------------------------------------------------------------------
-- What Terminal had the game press, and what it left written (0.46.2)
--
-- A /run line runs tainted even when the game presses it: the game blames what it does on "*** ForceTaint_Strong ***",
-- not on Terminal (0.46.1). So every macro the game ran for Terminal is noted here (S.NotePress, from the macro proxy,
-- the click catcher and the row menu): Debug.lua counts a ForceTaint_Strong block as Terminal's when one of its /run
-- presses came just before, and names the last one otherwise. A moment after each press, S.TaintCheck reads (never
-- writes) who last wrote the Blizzard window fields those presses touch (issecurevariable), and traces the tainted.
----------------------------------------------------------------------

S.PRESSES_MAX = 8
S.presses = {} -- { t, text, via, run }, newest last
S.TAINT_DELAY = 0.5 -- seconds after a press before its window fields are read

--- The window fields presses write, read after each one: { path, key }. Missing ones are skipped.
S.WATCH = {
	{ "WorldMapFrame", "mapID" },
	{ "QuestMapFrame.DetailsFrame", "questID" },
	{ "PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame.PagingControls", "currentPage" },
	{ "CharacterFrame", "selectedTab" },
	{ "SettingsPanel", "currentLayout" },
	{ "CollectionsJournal", "selectedTab" },
	{ "AchievementFrame", "selectedTab" },
	{ "CommunitiesFrame", "displayMode" },
}

local function Walk(path)
	local f = _G
	for part in path:gmatch("[^%.]+") do
		if type(f) ~= "table" then return nil end
		f = rawget(f, part) or f[part]
	end
	return type(f) == "table" and f or nil
end

--- Who last wrote t[key] (read only): "the game's own code", else the name the game blames ("*** ForceTaint_Strong ***"
--- for a /run line, an addon's name). Nil when it can't tell (no issecurevariable, no such field).
S.GAME = "the game's own code" -- (what S.Writer says of a field only the game's code wrote)
function S.Writer(t, key)
	local check = _G.issecurevariable
	if type(t) ~= "table" or type(check) ~= "function" then return nil end
	local ok, secure, by = pcall(check, t, key)
	if not ok then return nil end
	return secure and S.GAME or tostring(by or "an unknown caller")
end

local reported = {} -- path.key -> the writer last traced (each change traced once)

--- Reads every watched field; traces each one some other code than the game's wrote (once per change).
--- Returns { ["path.key"] = writer } of the tainted ones (tests).
function S.TaintCheck(after)
	local out = {}
	for _, w in ipairs(S.WATCH) do
		local t = Walk(w[1])
		if t and rawget(t, w[2]) ~= nil then
			local id = w[1] .. "." .. w[2]
			local by = S.Writer(t, w[2])
			if by and by ~= S.GAME then
				out[id] = by
				if reported[id] ~= by and ns.Trace then
					ns:Trace(("taint: %s was written by %s%s: what reads it later may be blocked"):format(id, by,
						after and (" (after " .. after .. ")") or ""))
				end
			end
			reported[id] = by
		end
	end
	return out
end

--- The game ran `text` for Terminal (`via`: "Enter", "click", "menu"). Noted, and the window fields are read a moment later.
function S.NotePress(text, via)
	if type(text) ~= "string" or text == "" then return end
	local run = text:find("/run", 1, true) ~= nil
	local p = { t = GetTime(), text = text, via = via, run = run }
	S.presses[#S.presses + 1] = p
	if #S.presses > S.PRESSES_MAX then table.remove(S.presses, 1) end
	local label = text:gsub("\n", " | "):sub(1, 80)
	if C_Timer and C_Timer.After then C_Timer.After(S.TAINT_DELAY, function() S.TaintCheck(label) end) end
end

--- The settings window's category id for a number or a category's name (read only), else nil.
function S.SettingsID(idOrName)
	if type(idOrName) == "number" then return idOrName end
	local St = _G.Settings
	if type(idOrName) ~= "string" or not (St and type(St.GetCategory) == "function") then return nil end
	local ok, cat = pcall(St.GetCategory, idOrName)
	if not (ok and type(cat) == "table") then return nil end
	local okID, id = pcall(function() return cat.GetID and cat:GetID() or cat.ID end)
	return okID and type(id) == "number" and id or nil
end

--- The line that opens the settings window on a category (and scrolls to the setting `name`), or nil.
--- C_SettingsUtil.OpenSettingsPanel is the game's own call (Blizzard's Settings.OpenToCategory only calls it): the game
--- answers with SETTINGS_PANEL_OPEN and the settings window's own code opens itself, as C_Map.OpenWorldMap does for
--- the map (0.46.1). No Blizzard Lua runs from the line. No id: the window as it was last (no category).
function S.SettingsMacro(idOrName, name)
	local U = _G.C_SettingsUtil
	if not (U and type(U.OpenSettingsPanel) == "function") then return nil end
	if idOrName == nil then return "/run C_SettingsUtil.OpenSettingsPanel()" end
	local id = S.SettingsID(idOrName)
	if not id then return nil end
	if type(name) == "string" and name ~= "" then return ("/run C_SettingsUtil.OpenSettingsPanel(%d,%q)"):format(id, name) end
	return ("/run C_SettingsUtil.OpenSettingsPanel(%d)"):format(id)
end

--- The last /run press, and how many seconds before `at` it came (nil: none this session).
function S.LastRunPress(at)
	for i = #S.presses, 1, -1 do
		local p = S.presses[i]
		if p.run then return p, (at or GetTime()) - p.t end
	end
end

--- First of a button name (or list of names) that exists in this client, else nil.
function S.First(names)
	if type(names) ~= "table" then names = { names } end
	for _, n in ipairs(names) do
		if _G[n] then return n end
	end
end

--- Whether this client knows a keybinding command.
function S.HasBinding(cmd)
	if not cmd then return false end
	if _G["BINDING_NAME_" .. cmd] then return true end
	return GetBindingKey and GetBindingKey(cmd) ~= nil or false
end

--- What the player's own key for a command does right now. Addons can take a key over
--- (ClassicUIForever re-binds your Talents and Quest Log keys to open its own windows), and
--- Enter should open the same window your key would. Falls back to the command itself.
function S.EffectiveAction(cmd)
	if GetBindingKey and GetBindingAction then
		local keys = { GetBindingKey(cmd) }
		for i = 1, 2 do
			local k = keys[i]
			if type(k) == "string" and k ~= "" then
				local ok, action = pcall(GetBindingAction, k, true)
				if ok and type(action) == "string" and action ~= "" then return action end
			end
		end
	end
	return cmd
end

--- spec: { binding = "TOGGLECHARACTER0", buttons = { "CharacterMicroButton" } }, { spell = "Smelting" },
--- { macro = text or function(e) }, or just a button name / list of button names. Returns { spell = },
--- { macro = }, { binding = } or { button = }, or nil.
function S.Resolve(spec, e)
	-- a spell that opens a window (Smelting): Enter casts it, on the same key press
	if type(spec) == "table" and spec.spell then return { spell = spec.spell } end
	-- a run of /click lines, pressed by the game itself (so nothing in the window runs
	-- tainted); spec.macro is the text, or a function returning it (nil: not possible now)
	if type(spec) == "table" and spec.macro then
		local text = spec.macro
		if type(text) == "function" then
			local ok, t = pcall(text, e) -- given the entry: its macro can name the quest, the map...
			text = ok and t or nil
		end
		-- the game cuts a macro off at 255 characters in all (a cut /run line is a Lua error): never hand one over
		if type(text) == "string" and #text > S.MACRO_MAX then
			if ns.Trace then ns:Trace(("secure: macro too long (%d of %d characters), not used: %s"):format(#text, S.MACRO_MAX, text:sub(1, 60))) end
			text = nil
		end
		if type(text) == "string" and text ~= "" then return { macro = text } end
		if not (spec.binding or spec.buttons) then return nil end
	end
	if type(spec) == "table" and (spec.binding or spec.buttons) then
		if S.HasBinding(spec.binding) then return { binding = S.EffectiveAction(spec.binding) } end
		local b = S.First(spec.buttons or {})
		return b and { button = b } or nil
	end
	local b = spec and S.First(spec)
	return b and { button = b } or nil
end

--- What a mouse click on a result runs, as macro text: the mouse can't press a keybinding
--- command the way Enter does, so a click on a result goes to a secure button running /click
--- lines instead (pressed by the game, so nothing runs tainted). In order: the spec's own
--- `click` text, its `macro`, a cast of its `spell`, a click on its first existing button.
--- Nil when there is no such way (that result then arms Enter, as before).
local function Text(v, e)
	if type(v) == "function" then
		local ok, t = pcall(v, e)
		v = ok and t or nil
	end
	return type(v) == "string" and v ~= "" and v or nil
end

--- `quiet`: worked out for a pointer resting on a row (every redraw), not for a press: the
--- character tab lookups don't trace their steps (S.quiet, read by CharTab).
function S.ClickMacro(spec, e, quiet)
	if type(spec) == "string" then spec = { buttons = { spec } } end
	if type(spec) ~= "table" then return nil end
	S.quiet = quiet and true or nil
	local t = Text(spec.click, e) or Text(spec.macro, e)
	S.quiet = nil
	if t and #t > S.MACRO_MAX then
		if ns.Trace then ns:Trace(("secure: click macro too long (%d characters), not used"):format(#t)) end
		t = nil -- (the spec's spell or button instead, as Resolve does)
	end
	if t then return t end
	if type(spec.spell) == "string" and spec.spell ~= "" then return "/cast " .. spec.spell end
	local b = S.First(spec.buttons or (spec[1] and spec) or {})
	return b and ("/click " .. b) or nil
end

--- A secure button that clicks `target` (a frame, named or not), so a macro can /click it:
--- this client's character tabs have no names. One per key, created out of combat; the
--- target is set again each time (attributes can't change in combat, nor are they needed then).
local clickers = {}
function S.Clicker(key, target)
	if InCombatLockdown() or type(target) ~= "table" then return clickers[key] end
	local c = clickers[key]
	if not c then
		c = Offscreen("TerminalClick" .. key)
		c:SetAttribute("useOnKeyDown", false) -- /click sends a release
		c:SetAttribute("type", "click")
		-- for a .debug log: did the game press it, and with which half of the click
		c:HookScript("PostClick", function(_, button, down)
			if ns.Trace then ns:Trace("click: " .. key .. " clicker pressed (" .. tostring(button) .. ", down=" .. tostring(down) .. ")") end
		end)
		clickers[key] = c
	end
	c:SetAttribute("clickbutton", target)
	return c
end

-- a trace line, unless the macro is only being worked out for a resting pointer (S.quiet)
local function Say(msg)
	if ns.Trace and not S.quiet then ns:Trace(msg) end
end

-- (.debug log) what kind of thing a character tab is, and which mouse events it listens to (safe on any frame)
local function TraceTab(frameName, t)
	local function has(h)
		local okH, hs = pcall(t.HasScript, t, h)
		if not okH or not hs then return "n/a" end
		local okG, f = pcall(t.GetScript, t, h)
		return okG and f and "set" or "empty"
	end
	local okT, ty = pcall(t.GetObjectType, t)
	ns:Trace(("click: %s tab is a %s, %s, OnClick %s, OnMouseDown %s, OnMouseUp %s"):format(frameName,
		tostring(okT and ty), type(t.Click) == "function" and "has Click" or "no Click",
		has("OnClick"), has("OnMouseDown"), has("OnMouseUp")))
end

--- The character window's tab for one of its pages (ReputationFrame, SkillsFrame...).
--- This client: CharacterFrame.ModeTabs.Tabs, each with the frameName of its page (unnamed;
--- ClassicUIForever draws its own tabs over them). Classic clients: CharacterFrameTabN,
--- found by its label. Returns the name to /click, or nil.
local function CharTab(frameName, labels)
	local cf = _G.CharacterFrame
	local mt = cf and cf.ModeTabs
	local tabs = type(mt) == "table" and mt.Tabs
	if type(tabs) == "table" then
		for _, t in ipairs(tabs) do
			if type(t) == "table" and t.frameName == frameName then
				if ns.Trace and not S.quiet then TraceTab(frameName, t) end
				-- this client's tabs are plain frames acting on the mouse itself: nothing to /click
				if type(t.Click) ~= "function" then return nil, "frame" end
				local ok, n = pcall(t.GetName, t)
				if ok and type(n) == "string" and n ~= "" and _G[n] == t then return n, "mode tab" end
				local c = S.Clicker(frameName, t)
				return c and (c:GetName() .. " LeftButton false"), "mode tab (unnamed)"
			end
		end
	end
	for i = 1, 8 do
		local name = "CharacterFrameTab" .. i
		local t = _G[name]
		if type(t) == "table" and t.GetText then
			local ok, txt = pcall(t.GetText, t)
			if ok and type(txt) == "string" and not ns.Secret(txt) then
				for _, l in ipairs(labels) do
					if txt == l then return name, "labelled tab" end
				end
			end
		end
	end
end

--- /click lines that open the character window on one of its pages: the micro button if
--- the window is closed, then that page's tab.
function S.CharTabMacro(frameName, labels)
	local tab, how = CharTab(frameName, labels)
	if how == "frame" then
		-- a tab that can't be clicked (this client's): no line. The click arms Enter instead, and Enter presses the
		-- character key's own binding. (Until 0.46.2 a /run line ran ToggleCharacter: a /run line runs tainted, 0.46.1,
		-- and the character window it switched then held what it wrote: it reads secret values on its next show.)
		Say("click: " .. frameName .. " tab is a plain frame: no click route, the click arms Enter")
		return nil
	end
	if not _G.CharacterMicroButton then return nil end
	if not tab then
		Say("click: no character tab for " .. frameName)
		return nil
	end
	Say("click: " .. frameName .. " through " .. how .. " " .. tab)
	local cf = _G.CharacterFrame
	local lines = {}
	if not (cf and cf.IsVisible and cf:IsVisible()) then lines[1] = "/click CharacterMicroButton" end
	lines[#lines + 1] = "/click " .. tab
	return table.concat(lines, "\n")
end

S.PAPERDOLL_CLICK = function() return S.CharTabMacro("PaperDollFrame", { _G.CHARACTER or "Character", "Character" }) end
S.REP_CLICK = function() return S.CharTabMacro("ReputationFrame", { _G.REPUTATION or "Reputation", "Reputation" }) end
S.SKILLS_CLICK = function()
	return S.CharTabMacro(_G.SkillsFrame and "SkillsFrame" or "SkillFrame", { _G.SKILLS or "Skills", "Skills" })
end

-- A key bound to a button "clicks" it twice: on key down and on key up. The button acts on
-- only one of them (useOnKeyDown); finishing on the other would unbind Enter too early, and
-- the press that does the work would then find nothing bound.
-- The press can come back after Enter was let go: the window it opened can close the terminal (a
-- special frame) while the press is still running, and closing disarms. A press of what was armed a
-- moment ago still finishes (its after-step points at the result).
S.LATE = 1 -- seconds
local function PostClick(self, _, down)
	if self.actsOnDown ~= nil and down ~= nil and (down and true or false) ~= self.actsOnDown then return end
	if not S.onClicked then return end
	if S.armed == self.targetName then
		S.onClicked(self.targetName)
		S.lastArmed = nil -- (finished: not a press still to come back)
	elseif S.lastArmed == self.targetName and S.lastArmedAt and GetTime() - S.lastArmedAt < S.LATE then
		if ns.Trace then ns:Trace("secure: the press came back after Enter was let go (the window it opened closed the terminal); finishing it") end
		S.lastArmed = nil
		S.onClicked(self.targetName)
	end
end

--- Offscreen secure button that clicks a Blizzard button. Created once, out of combat; the
--- button it clicks is set again on every arm (as Clicker does), so one the game or an addon
--- made anew since isn't a dead reference.
function S.Proxy(targetName)
	local p = proxies[targetName]
	local target = _G[targetName]
	if p then
		if target and not InCombatLockdown() and p:GetAttribute("clickbutton") ~= target then
			p:SetAttribute("clickbutton", target)
		end
		return p
	end
	if not target or InCombatLockdown() then return nil end
	p = Offscreen("TerminalProxy" .. targetName)
	p:SetAttribute("useOnKeyDown", false)
	p.actsOnDown = false
	p:SetAttribute("type", "click")
	p:SetAttribute("clickbutton", target)
	p.targetName = targetName
	p:HookScript("PostClick", PostClick)
	proxies[targetName] = p
	return p
end

local macroProxy
--- The one offscreen secure button that runs a macro (its text set when armed).
local function MacroProxy()
	if macroProxy or InCombatLockdown() then return macroProxy end
	local p = Offscreen("TerminalMacroProxy")
	-- acts on key down, the same press the game's own bindings act on
	p:SetAttribute("useOnKeyDown", true)
	p.actsOnDown = true
	p:SetAttribute("type", "macro")
	p.targetName = "MACRO"
	p:HookScript("PostClick", PostClick)
	macroProxy = p
	return p
end

-- (.debug log: did the game press the macro button at all, and on which half of the key press?)
local function TracePress(p, _, down)
	if S.armed ~= p.targetName then return end
	if ns.Trace then ns:Trace(("secure: the game pressed %s on key %s"):format(p:GetName(), down and "down" or "up")) end
	-- (the half of the key press the macro runs on: noted for Debug.lua and the taint check)
	if p.actsOnDown == nil or down == nil or (down and true or false) == p.actsOnDown then
		S.NotePress(p:GetAttribute("macrotext"), "Enter")
	end
end

-- Enter (and the keypad's) bound to one thing only: set(owner, true, key, ...) is SetOverrideBinding/Click/Spell
local function BindEnter(set, ...)
	ClearOverrideBindings(owner)
	set(owner, true, "ENTER", ...)
	set(owner, true, "NUMPADENTER", ...)
end

--- Bind Enter to a resolved spec. False if that isn't possible right now.
function S.Arm(r)
	if InCombatLockdown() or type(r) ~= "table" then return false end
	if ns.Trace then ns:Trace("Secure.Arm " .. tostring(r.binding or r.button or r.spell or (r.macro and ("macro: " .. r.macro:gsub("\n", " | "))))) end
	if r.macro then
		local p = MacroProxy()
		if not p then return false end
		if not p.traced then p.traced = true; p:HookScript("PreClick", TracePress) end
		p:SetAttribute("macrotext", r.macro)
		BindEnter(SetOverrideBindingClick, p:GetName(), "LeftButton")
		S.armed, S.mode = p.targetName, "button"
	elseif r.binding then
		BindEnter(SetOverrideBinding, r.binding)
		S.armed, S.mode = r.binding, "binding"
	elseif r.spell then
		BindEnter(SetOverrideBindingSpell, r.spell)
		S.armed, S.mode = "SPELL " .. r.spell, "binding"
	elseif r.button then
		local p = S.Proxy(r.button)
		if not p then return false end
		BindEnter(SetOverrideBindingClick, p:GetName(), "LeftButton")
		S.armed, S.mode = r.button, "button"
	else
		return false
	end
	-- never leave Enter hijacked: give up after a while
	token = token + 1
	local mine = token
	C_Timer.After(10, function()
		if S.armed and token == mine and ns.UI then ns.UI:Disarm() end
	end)
	return true
end

function S.Disarm()
	if S.armed then S.lastArmed, S.lastArmedAt = S.armed, GetTime() end
	S.armed, S.mode = nil, nil
	token = token + 1
	if InCombatLockdown() then
		S.dirty = true -- bindings can't change in combat; cleared when it ends
	else
		ClearOverrideBindings(owner)
	end
end

----------------------------------------------------------------------
-- Turning a window to the right page by the game's own clicks (0.46.18, the player's ask)
--
-- The press that opens a window goes on to its tab, page, section or row in the same Enter press: the macro gets lines
-- "/click TerminalNavN", and each one is one step. Just before it runs, the step's PreClick (Terminal's code, which only
-- READS the window) picks the Blizzard button the next step needs: the spellbook's tab or page arrow, the quest's row,
-- a keybinding section's header. It sets that button as its own "clickbutton", and the secure button clicks it for the
-- game (SECURE_ACTIONS.click), so the window's own code runs untainted, as if you had clicked it. Terminal never writes
-- into the window. A step that only a write could do (scrolling a list, typing into a search box) isn't taken: the
-- window is opened and the row pointed at, as before.
--
-- Checked afterwards (the "taint detection"): each route names the window fields its clicks write (`watch`). A moment
-- after the press they are read with issecurevariable. One that comes out written by anyone but the game, when it
-- wasn't before, means the clicks didn't stay clean: the route is turned off (db.navTainted), said once in chat, and
-- from then on that window is only opened and pointed at. A blocked action blamed on Terminal right after such a press
-- turns the route off the same way. .nav (.navigate) lists them; .nav reset tries again.
----------------------------------------------------------------------

S.NAV_SLOTS = 8 -- plans kept at once, one secure button each (a hover's macro and Enter's each get their own)
S.NAV_STEPS = 12 -- the most steps one press takes (the macro's 255 characters may allow fewer)
S.NAV_BLAME = 3 -- seconds: a blocked action this soon after a turning press turns that route off
S.NAV_LABELS = { spellbook = L["your spellbook"], questlog = L["the quest log"], keybinds = L["Options > Keybindings"] }

S.navPlans = {} -- slot -> plan: { route, e, step, watch, watchName, before, n, at, quiet, verified }
local navButtons, navSlot = {}, 0

--- Whether a frame is an enabled Button (read only).
local function IsButton(f)
	if type(f) ~= "table" or type(f.Click) ~= "function" then return false end
	local okT, isButton = pcall(f.IsObjectType, f, "Button")
	if not (okT and isButton) then return false end
	if f.IsEnabled then
		local okE, en = pcall(f.IsEnabled, f)
		if okE and en == false then return false end
	end
	return true
end

--- Whether a frame can be clicked for the game: a visible, enabled Button the game lets a click reach.
local function Clickable(f)
	if not IsButton(f) then return false end
	local okV, vis = pcall(f.IsVisible, f)
	if not (okV and vis) then return false end
	if f.HasAccessConstraints then
		local okA, c = pcall(f.HasAccessConstraints, f)
		if okA and c == true then return false end
	end
	return true
end
S.Clickable = Clickable

local function Named(f)
	local n = ns.FrameName and ns.FrameName(f)
	if type(n) == "string" then return n end
	local ok, d = pcall(function() return f.GetDebugName and f:GetDebugName() end)
	return ok and type(d) == "string" and d or "a button"
end

--- The route's window fields, read now: { [i] = writer }.
local function ReadWatch(plan)
	local out = {}
	for i, w in ipairs(plan.watch or {}) do
		local ok, t, k = pcall(w, plan.e)
		if ok and type(t) == "table" and k ~= nil and rawget(t, k) ~= nil then out[i] = S.Writer(t, k) or false end
	end
	return out
end

--- Whether Terminal may turn this window for you (not turned off for leaving something tainted).
function S.NavOn(route)
	local off = ns.db and ns.db.navTainted
	return not (off and off[route])
end

--- The route turned off: what came out tainted (`what`), and by whom. Said once in chat.
function S.NavTaint(route, what, by)
	if not ns.db then return end
	ns.db.navTainted = ns.db.navTainted or {}
	if ns.db.navTainted[route] then return end
	ns.db.navTainted[route] = { t = time and time() or 0, what = what, by = by }
	if ns.Trace then ns:Trace(("nav: %s turned off: %s, by %s"):format(route, tostring(what), tostring(by))) end
	ns:Print(L["Turning %s left %s written by %s (taint), so from now on Terminal only opens it and points. Type /term .nav for more; .nav reset tries again."]
		:format(S.NAV_LABELS[route] or route, tostring(what), tostring(by)))
end

local function Verify(plan)
	if plan.verified then return end
	plan.verified = true
	local now = ReadWatch(plan)
	for i, by in pairs(now) do
		if by and by ~= S.GAME and by ~= plan.before[i] then
			local okD, label = pcall(plan.watchName or function() return nil end, i)
			S.NavTaint(plan.route, okD and label or L["field %d"]:format(i), by)
			return
		end
	end
	if ns.Trace then ns:Trace(("nav: %s checked after the press: nothing it clicked was left tainted"):format(plan.route)) end
end

--- Just before one step's click: the plan's step function picks the button (or none) and the secure button is set to it.
local function NavPreClick(self)
	local plan = S.navPlans[self.slot]
	local target, why
	if plan and not InCombatLockdown() then
		plan.n = (plan.n or 0) + 1
		if plan.n <= S.NAV_STEPS then
			local ok, t, w = pcall(plan.step, plan.e, plan)
			if ok then target, why = t, w else why = "error: " .. tostring(t) end
		end
		if target and not Clickable(target) then why, target = (why or "") .. " (" .. Named(target) .. " can't be clicked now)", nil end
		if not plan.at then
			plan.at = GetTime()
			if C_Timer and C_Timer.After then C_Timer.After(S.TAINT_DELAY, function() Verify(plan) end) end
		end
		if ns.Trace and (target or not plan.quiet) then
			ns:Trace(("nav: %s step %d: %s"):format(plan.route, plan.n, target and ("click " .. Named(target) .. (why and (" (" .. why .. ")") or ""))
				or ("nothing to click" .. (why and (" (" .. why .. ")") or ""))))
		end
		if not target then plan.quiet = true end -- (the rest of its lines: said once)
	end
	if not InCombatLockdown() then self:SetAttribute("clickbutton", target) end
end

local function NavButton(slot)
	local b = navButtons[slot]
	if b or InCombatLockdown() then return b end
	b = Offscreen("TerminalNav" .. slot)
	b:SetAttribute("useOnKeyDown", false) -- (/click sends a release)
	b:SetAttribute("type", "click")
	b.slot = slot
	b:SetScript("PreClick", NavPreClick)
	navButtons[slot] = b
	return b
end

--- A macro line that clicks a named Blizzard button (a micro button opening a window), or nil when it can't be clicked.
function S.ClickLine(name) return IsButton(_G[name]) and ("/click " .. name) or nil end

--- The macro for a turning press: `open` (the lines opening the window, or nil when it shows) and as many step lines as
--- fit. `def` = { route, step = fn(e, plan) -> button[, why], watch = { fn(e) -> table, key }, watchName = fn(i) }.
--- Nil when the route is off, or nothing would fit.
function S.NavMacro(def, e, open)
	if not (def and S.NavOn(def.route)) or InCombatLockdown() then return nil end
	if open == "" then open = nil end
	local slot = navSlot % S.NAV_SLOTS + 1
	local line = "/click TerminalNav" .. slot
	local lines = {}
	local used = 0
	if open then lines[1] = open; used = #open end
	for _ = 1, S.NAV_STEPS do
		if used + (used > 0 and 1 or 0) + #line > S.MACRO_MAX then break end
		lines[#lines + 1] = line
		used = used + (used > 0 and 1 or 0) + #line
	end
	if #lines == (open and 1 or 0) then return nil end -- (no room for a single step: the window's own route instead)
	-- (the slot is taken only now: a macro that couldn't be made leaves the plans as they were)
	local b = NavButton(slot)
	if not b then return nil end
	navSlot = slot
	local plan = { route = def.route, e = e, step = def.step, watch = def.watch, watchName = def.watchName }
	plan.before = ReadWatch(plan)
	S.navPlans[slot] = plan
	return table.concat(lines, "\n"), plan
end

--- A blocked action blamed on Terminal (Debug.lua): right after a turning press, that route is turned off too.
function S.OnBlocked(func, at)
	local newest
	for _, plan in pairs(S.navPlans) do
		if plan.at and (not newest or plan.at > newest.at) then newest = plan end
	end
	if newest and (at or GetTime()) - newest.at <= S.NAV_BLAME then
		S.NavTaint(newest.route, L["a blocked action (%s)"]:format(tostring(func)), L["the game, right after it"])
	end
end

ns:RegisterCommand("navigate", {
	desc = L["Which windows Terminal turns to the right page for you, and any it stopped turning because something came out tainted"],
	aliases = { "nav" },
	complete = function() return { { "reset", L["try turning every window again"] } } end,
	run = function(args)
		local a = strtrim(args or ""):lower()
		local off = ns.db and ns.db.navTainted or {}
		if a == "reset" then
			if ns.db then ns.db.navTainted = nil end
			return { L["Terminal turns every window to the right page again."] }
		end
		local out = { L["Windows Terminal turns to the right page with the game's own clicks:"] }
		local names, anyOff = {}, false
		for route in pairs(S.NAV_LABELS) do names[#names + 1] = route end
		table.sort(names)
		for _, route in ipairs(names) do
			local o = off[route]
			if o then anyOff = true end
			out[#out + 1] = ("  %s: %s"):format(S.NAV_LABELS[route], o and L["off (%s written by %s%s)"]:format(tostring(o.what), tostring(o.by),
				(o.t and time and ns.Ago) and (", " .. ns.Ago(time() - o.t)) or "") or L["on"])
		end
		if anyOff then out[#out + 1] = L[".nav reset turns them on again."] end
		return out
	end,
})

function S.OnCombat()
	if ns.UI and ns.UI.OnCombat then ns.UI:OnCombat() elseif S.armed then S.Disarm() end
end

function S.OnRegen()
	if S.dirty and not S.armed then
		ClearOverrideBindings(owner)
		S.dirty = false
	end
	if ns.UI and ns.UI.OnRegen then ns.UI:OnRegen() end
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_DISABLED")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then S.OnCombat() else S.OnRegen() end
end)
