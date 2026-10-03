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
function S.Resolve(spec)
	-- a spell that opens a window (Smelting): Enter casts it, on the same key press
	if type(spec) == "table" and spec.spell then return { spell = spec.spell } end
	-- a run of /click lines, pressed by the game itself (so nothing in the window runs
	-- tainted); spec.macro is the text, or a function returning it (nil: not possible now)
	if type(spec) == "table" and spec.macro then
		local text = spec.macro
		if type(text) == "function" then
			local ok, t = pcall(text)
			text = ok and t or nil
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

local function PostClick(self)
	if S.armed == self.targetName and S.onClicked then
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
	p:SetAttribute("useOnKeyDown", false)
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
