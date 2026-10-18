-- In combat only Ctrl+` opens Terminal (0.57.0, the author's ask): a ` hit by accident in a fight opened it, and it took
-- the next keys from your spells. A plain ` says so in chat; Tab+` and /term open it as ever; / never opens it in combat.
-- Alt+` only switches Simple and Advanced in an open terminal: it never opens or closes it.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll

io.write("[combatopen: Ctrl+` in combat; Alt+` never opens]\n")
do
	local save = { combat = _G.InCombatLockdown, time = _G.GetTime, print = ns.Print, ctrl = _G.IsControlKeyDown, alt = _G.IsAltKeyDown,
		chat = rawget(_G, "ChatFrame_OpenChat") }
	local fight, now, said, ctrl, alt = true, 1000, {}, false, false
	_G.InCombatLockdown = function() return fight end
	_G.GetTime = function() return now end
	_G.IsControlKeyDown = function() return ctrl end
	_G.IsAltKeyDown = function() return alt end
	ns.Print = function(_, m) said[#said + 1] = m end
	UI:Hide(); FlushAll()
	UI.combatSaid = nil
	local SAY = ns.L["In combat, Ctrl+` opens Terminal."]
	UI:Toggle()
	check(not UI:IsShown() and #said == 1 and said[1] == SAY, "in combat, `: not opened, said in chat: " .. tostring(said[1]))
	now = now + 0.3
	UI:Toggle()
	check(not UI:IsShown() and #said == 1, "pressed again quickly: still not opened, not said twice")
	now = now + 5
	UI:Toggle()
	check(not UI:IsShown() and #said == 2, "a while later: said again")
	ctrl = true
	UI:Toggle()
	check(UI:IsShown(), "Ctrl+`: opened")
	ctrl = false
	UI:Toggle()
	check(not UI:IsShown(), "open, ` closes it")
	FlushAll()
	-- Tab+`: fuzzy finding, in combat too (not a key hit by accident)
	local n = #said
	UI:FuzzyOnce()
	check(UI:IsShown() and UI.fzf and #said == n, "Tab+` in combat: fuzzy finding, nothing said")
	UI:Hide(); FlushAll()
	-- / in combat: never Terminal (the chat box, as the game's own /)
	local chat
	_G.ChatFrame_OpenChat = function(t) chat = t end
	UI:SlashOpen(); FlushAll()
	check(not UI:IsShown() and chat == "/", "/ in combat: the chat box, never Terminal")
	-- /term typed: as ever
	_G.SlashCmdList.TERMINAL("")
	check(UI:IsShown() and #said == n, "/term typed in combat: opens, nothing said")
	UI:Hide(); FlushAll()
	-- out of combat: ` opens it
	fight = false
	UI:Toggle()
	check(UI:IsShown(), "out of combat: ` opens it")
	UI:Hide(); FlushAll()
	-- Alt+`: never opens it, in combat or out (its binding, or ` with Alt held)
	alt = true
	UI:AdvancedOnce()
	check(not UI:IsShown(), "Alt+`, closed: nothing")
	UI:Toggle()
	check(not UI:IsShown(), "` with Alt held (no Alt+` binding): nothing")
	alt = false
	_G.InCombatLockdown, _G.GetTime, ns.Print, _G.IsControlKeyDown, _G.IsAltKeyDown = save.combat, save.time, save.print, save.ctrl, save.alt
	_G.ChatFrame_OpenChat = save.chat
	UI.combatSaid = nil
end
