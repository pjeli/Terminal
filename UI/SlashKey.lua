local ns = select(2, ...)
local UI = ns.UI

-- The / key opens Terminal on a slash command (0.56.9, the player's ask: "have Terminal open on a / character as well;
-- as if the player is trying to type a slash command"). The game's own / (open the chat box with "/") is taken over only
-- while you're out of combat, and only when / still does that: another binding of yours on / is left alone. In combat
-- / opens the chat box as ever (Terminal closes in combat). Off unless turned on (0.56.14): .set slashKey on, or Options:
-- Open on /.
--
-- An override binding of Terminal's own (never saved to your key bindings): set out of combat, taken off as combat
-- starts (PLAYER_REGEN_DISABLED comes before the game locks bindings), set again after.

local SK = {}
ns.SlashKey = SK
SK.KEY = "/"
SK.GAME = "OPENCHATSLASH" -- (the game's own action on /)
SK.ACTION = "TERMINAL_SLASH" -- (Bindings.xml)

local owner = CreateFrame("Frame")
local applied = false

--- Should / open Terminal now: the setting on, and / still the game's chat box key.
function SK.Wanted()
	local T = ns.Theme
	local t = T and T.Get and T.Get()
	if not (t and t.slashKey == true) then return false end
	if InCombatLockdown() then return false end
	local ok, action = pcall(GetBindingAction, SK.KEY)
	return ok and action == SK.GAME
end

--- The override set or taken off, as SK.Wanted says (nothing done when it's already so).
function SK.Apply()
	if InCombatLockdown() then return end
	local want = SK.Wanted()
	if want == applied then return end
	applied = want
	if want then
		SetOverrideBinding(owner, false, SK.KEY, SK.ACTION)
	else
		SetOverrideBinding(owner, false, SK.KEY, nil)
	end
end
function SK.Applied() return applied end -- (tests)

owner:RegisterEvent("PLAYER_LOGIN")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:RegisterEvent("PLAYER_REGEN_DISABLED")
owner:RegisterEvent("UPDATE_BINDINGS")
function SK.OnEvent(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		-- (before the game locks bindings: / is the chat box's again for the fight)
		if applied then applied = false; SetOverrideBinding(owner, false, SK.KEY, nil) end
		return
	end
	SK.Apply()
end
owner:SetScript("OnEvent", SK.OnEvent)

--- The / key: Terminal opens on a fresh prompt saying "/", the slash commands listed, the caret after it; the key's own
--- "/", typed after the press, isn't typed again.
function UI:SlashOpen()
	if self:IsShown() then return end
	if InCombatLockdown() then
		-- (the override is off in combat; should the key still reach here: the game's chat box, as / does)
		local open = rawget(_G, "ChatFrame_OpenChat")
		if type(open) == "function" then pcall(open, "/") end
		return
	end
	self:Open("/")
	local edit = UI.edit
	if not edit then return end
	if edit:GetText() ~= "/" then self:SetQuery("/", 1) end
	self.cursor = 1
	if self.UpdateCaret then self:UpdateCaret() end
	-- the drawn prompt drops the "/" the key types next (OnChar); the game's own text box types it itself: taken out
	self.swallowChar = { ch = "/", at = GetTime() }
	if not self.keys then
		C_Timer.After(0, function() if edit:GetText() == "//" then UI:SetQuery("/", 1) end end)
	end
end
