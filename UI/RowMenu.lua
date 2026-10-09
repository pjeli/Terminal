local ns = select(2, ...)

-- The row menu (TerminalRowMenu): right-click a row, or Shift+Right at the end of a Simple prompt, for everything it
-- can do. Its lines are secure buttons the game presses, so the menu is placed against UIParent by screen position,
-- never anchored to the terminal (that made the terminal's frame protected). Split out of UI.lua.

local UI = ns.UI
local Theme = ns.Theme
local EasyOn, SecureView, ClickFor, FinishClicked, rows = UI.EasyOn, UI.SecureView, UI.ClickFor, UI.FinishClicked, UI.rows
local NeverOpen = ns.Never -- (a chat line: always pressed)

----------------------------------------------------------------------
-- The row menu (right-click): everything a row can do, in words
----------------------------------------------------------------------

local ChatBoxMacro = ns.ChatBoxMacro -- (Core.lua)

local menu -- TerminalRowMenu: a small list by the pointer, its lines secure buttons (the game presses windows open)
local MENU_W, MENU_LINE = 190, 22

local function Cap(s) return (tostring(s):gsub("^%l", string.upper)) end

local function MenuLine(i)
	local b = menu.lines[i]
	if b then return b end
	b = CreateFrame("Button", "TerminalRowMenuLine" .. i, menu, "SecureActionButtonTemplate")
	b:SetSize(MENU_W - 8, MENU_LINE)
	b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * MENU_LINE)
	b:RegisterForClicks("LeftButtonUp")
	b:SetAttribute("useOnKeyDown", false)
	b.fs = b:CreateFontString(nil, "OVERLAY")
	b.fs:SetFontObject(Theme.fonts.small)
	b.fs:SetPoint("LEFT", 8, 0)
	b.fs:SetPoint("RIGHT", -8, 0)
	b.fs:SetJustifyH("LEFT")
	b.hl = b:CreateTexture(nil, "BACKGROUND")
	b.hl:SetAllPoints()
	b.hl:Hide()
	b:SetScript("OnEnter", function() b.hl:Show() end)
	b:SetScript("OnLeave", function() b.hl:Hide() end)
	-- a chat line: what's sent is worked out on the click (out of combat: the menu never shows in combat)
	b:SetScript("PreClick", function()
		local it, SH = b.item, ns.Share
		if it and it.chatTo and SH and menu and menu.entry and not InCombatLockdown() then
			it.chat = SH.Macro(menu.entry, it.chatTo) or ""
			b:SetAttribute("macrotext1", it.chat)
		elseif it and it.boxLine and not InCombatLockdown() then
			it.chat = ChatBoxMacro(it.boxLine()) or ""
			b:SetAttribute("macrotext1", it.chat)
		end
	end)
	b:HookScript("PostClick", function() UI:MenuPicked(b) end)
	menu.lines[i] = b
	return b
end

function UI:HideRowMenu()
	if menu and menu:IsShown() and not InCombatLockdown() then
		menu.keys = nil
		menu:Hide()
		self:UpdateTooltip() -- (the selected row's tooltip back)
	end
end

-- (a block: ShowRowMenu's parts are its own)
do
	--- TerminalRowMenu, made the first time it's asked for.
	local function MenuFrame()
		if menu then return end
		menu = CreateFrame("Frame", "TerminalRowMenu", UIParent, "BackdropTemplate")
		menu:SetFrameStrata("TOOLTIP")
		menu:SetClampedToScreen(true)
		menu:EnableMouse(true)
		menu.lines = {}
		-- a click anywhere else closes it
		pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
		-- combat: its lines are secure buttons, so it can't be hidden once the lockdown is on: it goes as combat
		-- starts (the event comes just before), and once it's over should that ever have been too late
		pcall(menu.RegisterEvent, menu, "PLAYER_REGEN_DISABLED")
		pcall(menu.RegisterEvent, menu, "PLAYER_REGEN_ENABLED")
		menu:SetScript("OnHide", function() menu.keys = nil end)
		menu:SetScript("OnEvent", function(_, event)
			if not menu:IsShown() then return end
			if event == "PLAYER_REGEN_DISABLED" then
				menu.keys = nil
				menu:Hide()
				return
			end
			if event == "PLAYER_REGEN_ENABLED" or not (menu.IsMouseOver and menu:IsMouseOver()) then UI:HideRowMenu() end
		end)
	end

	--- The menu's lines for row `e`, in order: { label, and secondary (Enter's / Shift+Enter's verb), boxLine (the chat
	--- box), chatTo (a channel) or run (Terminal's own) }.
	local function MenuItems(self, e)
		local edit = UI.edit
		local items = {}
		local enter, shift
		if ns.Easy then enter, shift = ns.Easy.Verbs(e) end
		items[#items + 1] = { label = Cap(enter or "open"), secondary = false }
		if e.secondary or e.secondarySecure then items[#items + 1] = { label = Cap(shift or "more"), secondary = true } end
		-- to chat (both modes; Simple mode has no ">>"): the chat box with it, then a line per channel you're in, each
		-- a chat line the game presses (Terminal's code never sends chat)
		local SH = ns.Share
		-- (@who's "Ask the server" asks something: it isn't a result to send)
		if SH and SH.Line and not (e.syntaxRow or e.catId or e.raw or e.completion or e.lead) then
			local query = SH.Split(edit:GetText() or "")
			if EasyOn() and ns.Easy and ns.Easy.ToAdvanced then query = ns.Easy.ToAdvanced(query, self.category) end
			-- (what's sent is worked out only when a line is picked: an NPC's or a spot's text sets the map pin it links,
			-- and opening the menu, then Cancel, mustn't move your waypoint)
			local linked = e.npcID or (e.ui and e.px) or e.getLink or e.link or e.shareLink or e.itemID or e.questID or e.qid
			-- (the game opens the box with it: see ChatBoxMacro; not when Shift+Enter, just above, already does that)
			if shift ~= "link in chat" and shift ~= "put in the chat box" then
				items[#items + 1] = { label = linked and "Link in chat" or "Put in the chat box", boxLine = function() return SH.Line(e, query) end }
			end
			local channels = SH.MenuChannels()
			for _, ch in ipairs(channels) do
				items[#items + 1] = { label = ch.label, chatTo = { cmd = ch.cmd, query = query } }
			end
			-- every result at once ("All 8 to party"): Terminal sends them on the click or Enter (Share.SendAll)
			local group = SH.GroupRows(UI.results)
			local n = #group
			if n >= 2 then
				SH.Prefetch(group, true)
				for _, ch in ipairs(channels) do
					if ch.chat then
						local list, to = UI.results, { chat = ch.chat, label = ch.short }
						items[#items + 1] = { label = "All " .. n .. " to " .. ch.short, run = function()
							local sent, why = SH.SendAll(list, to, query)
							if not sent then ns:Print(why) return end
							UI:Hide()
						end }
					end
				end
			end
		end
		if not EasyOn() and self:ResultText(e) then
			items[#items + 1] = { label = "Write into the prompt", run = function() UI:FillFromResult() end }
		end
		-- (`run` lines are Terminal's own and keep it open: writing into the prompt, Cancel)
		items[#items + 1] = { label = "Cancel", run = function() end }
		return items
	end

	--- Where the menu goes: by the pointer, or (from the keyboard) beside row `idx` with its first line picked.
	local function PlaceMenu(self, idx, fromKeys)
		local frame = UI.frame
		local x, y
		if GetCursorPosition then x, y = GetCursorPosition() end
		local s = menu:GetEffectiveScale()
		local row = fromKeys and rows[idx - UI.offset]
		if fromKeys then
			-- from the keyboard (Shift+Right): beside the row, its first line picked (Up/Down, Enter, Esc/Left). Placed
			-- by screen position against UIParent, never anchored to the row: the menu holds secure buttons, and a secure
			-- frame anchored to Terminal's frame made it protected, so SetPropagateKeyboardInput stopped working and no
			-- Enter press reached the game again until a /reload (0.42.11-0.42.23: "everything breaks after the menu")
			local at = (row and row:IsShown()) and row or frame
			local right, top, as = at:GetRight(), at:GetTop(), at:GetEffectiveScale()
			if type(right) == "number" and type(top) == "number" and type(as) == "number" and type(s) == "number" and s > 0 then
				menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right * as / s + 4, top * as / s)
			else
				menu:SetPoint("CENTER", UIParent, "CENTER")
			end
			self:MenuSelect(1)
		elseif type(x) == "number" and type(s) == "number" and s > 0 then
			menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
		else
			menu:SetPoint("CENTER", UIParent, "CENTER")
		end
	end

	--- Right-click on row `idx`: its actions (Enter's, Shift+Enter's, Link in chat; Advanced: write it into the prompt).
	--- Window-opening ones are macros the game runs when the line is clicked, as the click catcher's are.
	function UI:ShowRowMenu(idx, fromKeys)
		local frame = UI.frame
		local e = UI.results[idx]
		if not e or e.noActivate or not frame then return end
		if InCombatLockdown() then ns:Print("Not in combat: right-click again afterwards.") return end
		MenuFrame()
		local t = Theme.Get()
		local items = MenuItems(self, e)
		menu.entry, menu.idx = e, idx
		for i, it in ipairs(items) do
			local b = MenuLine(i)
			b.item = it
			b.fs:SetText(it.label)
			b.fs:SetTextColor(Theme.RGB(it.label == "Cancel" and t.dim or t.text))
			b.hl:SetColorTexture(Theme.RGB(t.accent))
			b.hl:SetAlpha(0.25)
			-- a window to open: the game runs the macro on the click (as the catcher does); else Terminal's own action
			local macro, view
			if it.secondary ~= nil then macro, view = ClickFor(e, it.secondary, true) end
			if it.chatTo or it.boxLine then macro = "" end -- (the chat line: set in PreClick, see MenuLine)
			it.view = view
			b:SetAttribute("type1", macro and "macro" or "")
			b:SetAttribute("macrotext1", macro)
			it.macro = macro
			b:Show()
		end
		for i = #items + 1, #menu.lines do menu.lines[i]:Hide() end
		menu:SetSize(MENU_W, #items * MENU_LINE + 8)
		menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		local r, g, b = Theme.RGB(t.bg)
		menu:SetBackdropColor(r, g, b, 0.97)
		menu:SetBackdropBorderColor(Theme.RGB(t.border))
		menu:SetScale(t.scale or 1)
		menu:ClearAllPoints()
		if fromKeys then self:Disarm() end -- (Enter belongs to the menu's line now)
		menu.keys, menu.n = fromKeys and true or nil, #items
		for i = 1, #items do menu.lines[i].hl:Hide() end
		PlaceMenu(self, idx, fromKeys)
		menu:Show()
		self:UpdateTooltip() -- (hidden while the menu is up: it would sit under it)
	end
end

--- The keyboard's line in a menu opened from the keyboard.
function UI:MenuSelect(i)
	if not (menu and menu.n and menu.n > 0) then return end
	i = (i - 1) % menu.n + 1
	if menu.keySel and menu.lines[menu.keySel] then menu.lines[menu.keySel].hl:Hide() end
	menu.keySel = i
	menu.lines[i].hl:Show()
end
function UI:MenuShown() return menu ~= nil and menu:IsShown() end

--- Where the menu's row is now: lists rebuild under an open menu (friends' Battle.net updates come every few
--- seconds), so the same row may be a new table at another place. Its index, or nil when it's gone.
local function MenuRowIndex(e, idx)
	if UI.results[idx] == e then return idx end
	for i, r in ipairs(UI.results) do
		if r == e or (r.kind == e.kind and r.key ~= nil and r.key == e.key) then return i end
	end
end

--- A chat line picked from the keyboard: the view whose press has the game send it (Share.Macro) or open the chat box
--- with it a moment after the press (ChatBoxMacro). nil and the line when there's nothing the game can run.
local function MenuChatView(it, e)
	local SH = ns.Share
	local run, m
	if it.boxLine then
		m = it.boxLine()
		run = m and ChatBoxMacro(m)
	else
		m = SH and SH.Macro(e, it.chatTo)
		run = m ~= "" and m or nil
	end
	if run then return setmetatable({ secure = { macro = run }, isOpen = NeverOpen, after = false }, { __index = e }) end
	return nil, m
end

--- A key while the row menu opened from the keyboard is up: Up/Down/Tab pick a line, Enter runs it (as the line's
--- click would: windows and chat lines are pressed by the game, through Enter's own binding), Esc/Left close it.
--- True when the key was the menu's.
function UI:MenuKey(f, key)
	local edit = UI.edit
	if not (menu and menu.keys and menu:IsShown()) then return false end
	if key == "UP" or (key == "TAB" and IsShiftKeyDown()) then
		f:SetPropagateKeyboardInput(false); self:MenuSelect((menu.keySel or 1) - 1) return true
	elseif key == "DOWN" or key == "TAB" then
		f:SetPropagateKeyboardInput(false); self:MenuSelect((menu.keySel or 0) + 1) return true
	elseif key == "ESCAPE" or key == "LEFT" or key == "`" then
		f:SetPropagateKeyboardInput(false); self:HideRowMenu() return true
	elseif key ~= "ENTER" and key ~= "NUMPADENTER" then
		return false -- (anything else closes it and does what it does)
	end
	-- Enter runs the line the way Terminal's own Enter runs a row (which works in the game): the line's action is
	-- armed on Enter during this press and the press goes on to the game, SetPropagateKeyboardInput called ONCE
	-- (true). Binding Enter to a menu line or a proxy ahead of the press never fired in the game (0.42.14-16).
	local b = menu.lines[menu.keySel or 1]
	local it, e, idx = b and b.item, menu.entry, menu.idx
	ns:Trace("menu: Enter on line " .. tostring(menu.keySel) .. " (" .. tostring(b and b.fs:GetText()) .. ")")
	if not (it and e) then self:HideRowMenu() f:SetPropagateKeyboardInput(false) return true end
	if it.run then
		f:SetPropagateKeyboardInput(false)
		self:HideRowMenu()
		it.run()
		return true
	end
	-- (the row the menu was opened on: its own entry, wherever the list has put it since)
	local found = MenuRowIndex(e, idx)
	UI.sel = found or UI.sel
	local se
	if it.chatTo or it.boxLine then
		-- a chat line: sent by the game on this press, as the click sends it (Share.Macro); "Put in the chat box": the
		-- game opens the box with it a moment after the press (ChatBoxMacro)
		local m
		se, m = MenuChatView(it, e)
		if not se then
			f:SetPropagateKeyboardInput(false)
			self:HideRowMenu()
			if m and m ~= "" then ns:Print("Too long to put in the chat box from the keyboard: right-click it and pick the line.") end
			return true
		end
	else
		se = SecureView(e, it.secondary)
	end
	if se and self:ArmForPress(se) then
		f:SetPropagateKeyboardInput(true) -- this same press reaches the game's binding
		ns:Trace("menu: armed Enter for the press (" .. tostring(ns.Secure.armed) .. ")")
		if not (it.chatTo or it.boxLine) then ns:RecordHistory(edit:GetText()) end
		self:FinishSoon(se)
		self:HideRowMenu()
		return true
	end
	f:SetPropagateKeyboardInput(false)
	self:HideRowMenu()
	if not (it.chatTo or it.boxLine) and found then self:Activate(found, { secondary = it.secondary }) end
	return true
end

--- A menu line was clicked (after the game ran its macro, if it had one).
function UI:MenuPicked(b)
	local it, e, idx = b.item, menu and menu.entry, menu and menu.idx
	if not (it and e) then return end
	self:HideRowMenu()
	if it.run then
		it.run()
		return
	end
	if it.boxLine and (it.chat or "") == "" then -- (too long for a line the game runs: Terminal's own, as before)
		local line = it.boxLine()
		if line then ns.LinkInChat(line) end
		self:Hide()
		return
	end
	if it.chatTo or it.boxLine then -- the game sent it to chat / opens the chat box with it
		ns:Trace("menu: sent to chat: " .. tostring(it.chat):sub(1, 3))
		self:Hide()
		return
	end
	local now = MenuRowIndex(e, idx)
	if not now and not it.macro then return end
	UI.sel = now or UI.sel
	if it.macro then -- the game opened it: finish as after Enter
		FinishClicked(e, it.view or e)
		return
	end
	self:Activate(now, { secondary = it.secondary })
end
