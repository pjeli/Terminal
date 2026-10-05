local ns = select(2, ...)

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

S.MACRO_MAX = 255 -- the game runs at most this many characters of a macro, all lines together
S.armed = nil -- binding command or button name currently armed
S.mode = nil  -- "binding" or "button"

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

--- spec: { binding = "TOGGLECHARACTER0", buttons = { "CharacterMicroButton" } },
--- or just a button name / list of button names. Returns { binding = } or { button = } or nil.
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

function S.ClickMacro(spec, e)
	if type(spec) == "string" then spec = { buttons = { spec } } end
	if type(spec) ~= "table" then return nil end
	local t = Text(spec.click, e) or Text(spec.macro, e)
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
		c = CreateFrame("Button", "TerminalClick" .. key, UIParent, "SecureActionButtonTemplate")
		c:SetSize(1, 1)
		c:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -500, 500)
		c:EnableMouse(false)
		c:RegisterForClicks("AnyUp", "AnyDown")
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
				if ns.Trace then
					-- what kind of thing the tab is, and which mouse events it listens to (safe on any frame)
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
			if ok and type(txt) == "string" and not (issecretvalue and issecretvalue(txt)) then
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
	if how == "frame" and type(_G.ToggleCharacter) == "function" then
		-- a tab that can't be clicked: the macro runs what the character key itself runs
		-- (TOGGLECHARACTERn is ToggleCharacter(page)), pressed by the game, not Terminal's code
		if ns.Trace then ns:Trace("click: " .. frameName .. " tab is a plain frame; the macro runs ToggleCharacter") end
		return '/run ToggleCharacter("' .. frameName .. '", true)'
	end
	if not _G.CharacterMicroButton then return nil end
	if not tab then
		if ns.Trace then ns:Trace("click: no character tab for " .. frameName) end
		return nil
	end
	if ns.Trace then ns:Trace("click: " .. frameName .. " through " .. how .. " " .. tab) end
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

--- Offscreen secure button that clicks a Blizzard button. Created once, out of combat.
function S.Proxy(targetName)
	local p = proxies[targetName]
	if p then return p end
	local target = _G[targetName]
	if not target or InCombatLockdown() then return nil end
	p = CreateFrame("Button", "TerminalProxy" .. targetName, UIParent, "SecureActionButtonTemplate")
	p:SetSize(1, 1)
	p:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -500, 500)
	p:EnableMouse(false)
	p:RegisterForClicks("AnyUp", "AnyDown")
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
	local p = CreateFrame("Button", "TerminalMacroProxy", UIParent, "SecureActionButtonTemplate")
	p:SetSize(1, 1)
	p:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -500, 500)
	p:EnableMouse(false)
	p:RegisterForClicks("AnyUp", "AnyDown")
	-- acts on key down, the same press the game's own bindings act on
	p:SetAttribute("useOnKeyDown", true)
	p.actsOnDown = true
	p:SetAttribute("type", "macro")
	p.targetName = "MACRO"
	p:HookScript("PostClick", PostClick)
	macroProxy = p
	return p
end

--- Bind Enter to a resolved spec. False if that isn't possible right now.
function S.Arm(r)
	if InCombatLockdown() or type(r) ~= "table" then return false end
	if ns.Trace then ns:Trace("Secure.Arm " .. tostring(r.binding or r.button or r.spell or (r.macro and ("macro: " .. r.macro:gsub("\n", " | "))))) end
	if r.macro then
		local p = MacroProxy()
		if not p then return false end
		p:SetAttribute("macrotext", r.macro)
		ClearOverrideBindings(owner)
		SetOverrideBindingClick(owner, true, "ENTER", p:GetName(), "LeftButton")
		SetOverrideBindingClick(owner, true, "NUMPADENTER", p:GetName(), "LeftButton")
		S.armed, S.mode = "MACRO", "button"
	elseif r.binding then
		ClearOverrideBindings(owner)
		SetOverrideBinding(owner, true, "ENTER", r.binding)
		SetOverrideBinding(owner, true, "NUMPADENTER", r.binding)
		S.armed, S.mode = r.binding, "binding"
	elseif r.spell then
		ClearOverrideBindings(owner)
		SetOverrideBindingSpell(owner, true, "ENTER", r.spell)
		SetOverrideBindingSpell(owner, true, "NUMPADENTER", r.spell)
		S.armed, S.mode = "SPELL " .. r.spell, "binding"
	elseif r.button then
		local p = S.Proxy(r.button)
		if not p then return false end
		ClearOverrideBindings(owner)
		SetOverrideBindingClick(owner, true, "ENTER", p:GetName(), "LeftButton")
		SetOverrideBindingClick(owner, true, "NUMPADENTER", p:GetName(), "LeftButton")
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
