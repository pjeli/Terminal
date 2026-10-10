local ns = select(2, ...)

-- The terminal's modes for one run: Alt+` (Advanced, this time), pure fuzzy finding (Tab+`, the glow round the
-- prompt bar while it's on) and its hand-off of a result to Simple or Advanced mode. Split out of UI.lua.

local UI = ns.UI
local Theme = ns.Theme
local L = UI.layout
local Forget, TAB_LATE = UI.Forget, UI.TAB_LATE

-- Tab+` (Tab held, then `) is pure fuzzy finding (0.42.31; the Windows key never reached the game reliably). Tab held:
-- IsKeyDown("TAB") where the client answers it, else its own key-down seen while the terminal reads keys (UI.tabHeld,
-- the time it went down, trusted for TAB_HOLD s; cleared on its key-up)
local TAB_HOLD = 3

--- Alt+` made this run Advanced: Simple again, and Down brings back what the Simple prompt said (nothing, when
--- Alt+` opened it closed: the Advanced text typed then isn't a Simple search). From Hide and from the frame's
--- OnHide (a window the press opens can close the terminal itself: Hide then returns early).
function UI:EndAdvancedOnce()
	if ns.Easy then ns.Easy.tempSimple = nil end -- (Simple for this run, from fuzzy finding: over too)
	local once = ns.Easy and ns.Easy.temp
	if not once then return end
	ns.Easy.temp = nil
	local from = once.from and once.from:find("%S") and once.from or nil
	self.lastQuery, self.lastCategory = from, from and once.category or nil
	self.category, self.categoryAuto = nil, nil
end

--- The key's ` comes after Alt+` as a typed character: Terminal's drawn prompt drops it (OnChar), and the game's own
--- text box (clipboard, combat) types it itself, so it's taken back out next frame (`want`: the text it should say).
local function DropTick(want)
	local edit = UI.edit
	UI.swallowTick = GetTime()
	if UI.keys then return end
	C_Timer.After(0, function()
		if edit:GetText() == want .. "`" then UI:SetQuery(want, #want) end
	end)
end

--- Pure fuzzy finding for this run (UI.fzf, FuzzySearch): Tab+`, its binding, or .fuzzy (UI:FuzzyOnce). The prompt
--- keeps its plain words; a soft glow round the prompt bar says the mode is on. Tab+` again closes the terminal (which ends it).
function UI:StartFuzzy()
	local frame, edit = UI.frame, UI.edit
	if self.fzf or not frame then return end
	local text = edit:GetText()
	local plain = UI.FuzzyPlain(text)
	self.fzf = true
	DropTick(plain)
	ns:Trace(("fuzzy find: on (%q -> %q)"):format(text, plain))
	self.category, self.categoryAuto, self.action, self.place, self.sendTo, self.blockedSyntax = nil, nil, nil, nil, nil, nil
	self.showRecent, self.recalled, self.histIdx = nil, nil, nil
	Forget(self, true)
	self.lastFzf = nil
	self:ShowGlow(true)
	self:SetOrResearch(plain)
	self:SetStatus()
	self:UpdateGhost()
end

--- Pure fuzzy finding ends: closed (Hide, OnHide), or Tab+`/Alt+` in it (`stay`: back to the mode it came from, the
--- text as it is).
function UI:EndFuzzy(stay)
	local edit = UI.edit
	if not self.fzf then return end
	self.fzf = nil
	self.lastFzf = nil
	self:ShowGlow(false)
	if not (stay and self:IsShown()) then return end
	ns:Trace("fuzzy find: off")
	DropTick(edit:GetText())
	Forget(self, true)
	self:Research()
	self:SetStatus()
	self:UpdateGhost()
end

--- Is Tab held? The client's IsKeyDown("TAB") (a secret answer counts as no), else its key-down seen a moment ago.
function UI:TabDown()
	local f = _G.IsKeyDown
	if f then
		local ok, down = pcall(f, "TAB")
		if ok and down == true and not ns.Secret(down) then return true end
	end
	return self.tabHeld ~= nil and GetTime() - self.tabHeld < TAB_HOLD
end

--- Tab let go while the terminal reads keys. Opened by the toggle key a moment ago with nothing typed since: the
--- opening press was Tab+` (Tab was held when ` opened it, and IsKeyDown didn't say so), so fuzzy finding now.
function UI:TabReleased()
	self.tabHeld = nil
	local at = self.openedByToggle
	self.openedByToggle = nil
	if at and GetTime() - at < TAB_LATE and self:IsShown() and not self.fzf then
		ns:Trace("fuzzy find: Tab let go just after the toggle key opened the terminal: it was Tab+`")
		self:FuzzyOnce()
	end
end

--- (.debug log: what the game reports with a ` press: whether Tab+` reaches it on this client)
function UI:TraceTick()
	local f = _G.IsKeyDown
	local ok, tab = false, nil
	if f then ok, tab = pcall(f, "TAB") end
	ns:Trace(("key `: alt=%s tab=%s (IsKeyDown(TAB) %s, Tab key seen %s)"):format(tostring(IsAltKeyDown and IsAltKeyDown() or false),
		tostring(self:TabDown()), f and (ok and (ns.Secret(tab) and "secret" or tostring(tab)) or "error") or "missing",
		self.tabHeld and "yes" or "no"))
end

--- Tab+` / the fuzzy binding / .fuzzy [words]: pure fuzzy finding, opening the terminal for it when closed; in it
--- already, the terminal closes (as Alt+` pressed again does).
function UI:FuzzyOnce(text)
	if self.fzf and self:IsShown() then return self:Hide() end -- (Tab+` again closes, as Alt+` again does)
	if not self:IsShown() then self:Open() end
	self:StartFuzzy()
	if type(text) == "string" and text:find("%S") then
		text = text:gsub("^%s+", "")
		self:SetQuery(text, #text)
	end
end

--- Enter / Shift+Enter (or a click) in pure fuzzy finding: the picked result goes over to Simple mode (its name, in
--- its category) or Advanced mode ("@kind name"), for this run, and is selected there to open, use or send.
function UI:FuzzyPop(e, advanced)
	if not e or e.noActivate or type(e.name) ~= "string" then return end
	local E = ns.Easy
	local name = ns.Plain(e.name)
	local simpleUser = not (ns.db and ns.db.easyMode == false)
	self:EndFuzzy()
	Forget(self, true)
	self.blockedSyntax, self.sendTo = nil, nil
	local text
	if advanced then
		if E then
			E.tempSimple = nil
			if simpleUser and not E.temp then E.temp = { from = name } end
		end
		text = self:ResultText(e) or name
		self.category, self.categoryAuto = nil, nil
	else
		if E then
			E.temp = nil
			E.tempSimple = (not simpleUser) or nil
		end
		text = name
		local cat = E and E.CategoryOf and E.CategoryOf(e)
		self.category, self.categoryAuto = cat, nil -- (straight into its category: no list of categories first)
	end
	ns:Trace(("fuzzy find: %s -> %s %q"):format(tostring(e.name), advanced and "Advanced" or "Simple", text))
	self.popTarget = e
	self:SetOrResearch(text .. " ")
	self:SetStatus()
	self:UpdateGhost()
end

--- After a hand-off (FuzzyPop): the picked result selected among the new results once they're in (`final`: the search
--- is done, so it's given up on when it isn't there).
function UI:SelectPopTarget(final)
	local t = self.popTarget
	if not t then return end
	for i, e in ipairs(UI.results) do
		-- (the same table, or the same row made again: kind, key and name; rows with no key, a chain's names to pick
		-- from, by kind and name: Backspace back to them, UI:WalkBack)
		if e == t or (e.kind == t.kind and e.name == t.name and ((e.key ~= nil and e.key == t.key) or (e.key == nil and t.key == nil))) then
			UI.sel = i
			UI.offset = math.max(0, math.min(i - 1, #UI.results - L.ROWS))
			self.popTarget = nil
			return
		end
	end
	if final then self.popTarget = nil end
end

--- The glow round the prompt bar while fuzzy finding: rings of the accent colour inside its edges, fading inward,
--- breathing slowly (an AnimationGroup: the game runs it, no Lua each frame; still with animations off).
-- each ring's alpha per glow style (Theme's fzfGlow): rings go inwards from the prompt's edge, 2 px each
local GLOW_STYLES = {
	breathe = { 0.34, 0.18, 0.09, 0.04, pulse = true },
	steady = { 0.34, 0.18, 0.09, 0.04 },
	bright = { 0.6, 0.38, 0.22, 0.12, pulse = true },
	line = { 0.7, 0, 0, 0 },
}
local GLOW_RINGS = GLOW_STYLES.breathe
local glow
local function GlowStyle()
	local t = Theme.Get()
	return GLOW_STYLES[t.fzfGlow] or (t.fzfGlow ~= "off" and GLOW_RINGS) or nil
end
UI.GlowStyle = GlowStyle -- (tests)
function UI:ShowGlow(on)
	local frame, promptBg = UI.frame, UI.promptBg
	if not frame then return end
	if on and not GlowStyle() then on = false end -- (glow set to off)
	if on and not glow then
		glow = CreateFrame("Frame", nil, frame)
		glow:SetPoint("TOPLEFT", promptBg, "TOPLEFT", 0, 0)
		glow:SetPoint("BOTTOMRIGHT", promptBg, "BOTTOMRIGHT", 0, 0)
		glow.tex = {}
		for k, a in ipairs(GLOW_RINGS) do
			local i = (k - 1) * 2
			local function T(p1, x1, y1, p2, x2, y2, w, h)
				local tx = glow:CreateTexture(nil, "BACKGROUND")
				tx:SetPoint(p1, glow, p1, x1, y1)
				tx:SetPoint(p2, glow, p2, x2, y2)
				if w then tx:SetWidth(w) else tx:SetHeight(h) end
				tx.alpha = a
				glow.tex[#glow.tex + 1] = tx
			end
			T("TOPLEFT", i, -i, "TOPRIGHT", -i, -i, nil, 2)
			T("BOTTOMLEFT", i, i, "BOTTOMRIGHT", -i, i, nil, 2)
			T("TOPLEFT", i, -i - 2, "BOTTOMLEFT", i, i + 2, 2)
			T("TOPRIGHT", -i, -i - 2, "BOTTOMRIGHT", -i, i + 2, 2)
		end
		if glow.CreateAnimationGroup then
			pcall(function()
				local ag = glow:CreateAnimationGroup()
				ag:SetLooping("BOUNCE")
				local an = ag:CreateAnimation("Alpha")
				an:SetFromAlpha(1)
				an:SetToAlpha(0.45)
				an:SetDuration(1.4)
				if an.SetSmoothing then an:SetSmoothing("IN_OUT") end
				glow.pulse = ag
			end)
		end
		self:ColorGlow()
	end
	if not glow then return end
	glow:SetShown(on and true or false)
	UI.glow = glow -- (tests)
	local style = GlowStyle()
	if glow.pulse then
		if on and style and style.pulse and self:Animated() then pcall(glow.pulse.Play, glow.pulse) else pcall(glow.pulse.Stop, glow.pulse) end
	end
	if on then self:ColorGlow() end
end

--- The glow's colour (Theme's fzfColor, else the selection colour) and its rings' strength (the style).
function UI:ColorGlow()
	if not glow then return end
	local t = Theme.Get()
	local r, g, b = Theme.RGB(t.fzfColor or t.accent)
	local style = GlowStyle() or GLOW_RINGS
	for i, tx in ipairs(glow.tex) do
		local a = style[math.floor((i - 1) / 4) + 1] or 0
		tx:SetColorTexture(r, g, b, a)
		tx.alpha = a
	end
end

--- Alt+`: Advanced mode for this run only. Open in Simple mode, what the prompt says is written in Advanced
--- syntax (Easy.ToAdvanced: the lists the results come from as @kinds, of those the action word or the category
--- looks in) and the search goes on from there; closed, it opens straight in Advanced. Simple comes back when the
--- terminal closes (Hide). Already Advanced (for good or for this run): the same as `.
function UI:AdvancedOnce()
	local edit = UI.edit
	local E = ns.Easy
	-- in pure fuzzy finding: out of it first (to Advanced, the plain words kept)
	if self.fzf then
		self:EndFuzzy(true)
		if not (E and E.On()) then return end
	end
	if not (E and E.On()) then return self:Toggle() end
	if not self:IsShown() then
		E.temp = { from = "" }
		return self:Open()
	end
	local text = edit:GetText()
	-- the lists what shows comes from name the @kinds ("use hearthstone": @item, the list the Hearthstone shown is in,
	-- not every list "use" looks in): a search still going is finished first if that's quick (a category opened for
	-- you is set only then: read after it); else every list the action or category looks in, as before 0.44.12
	local done = self:FinishSearch(UI.FINISH_MS)
	local cat = not self.categoryAuto and self.category or nil -- (a category opened on its own counts too: it's what shows)
	local conv = E.ToAdvanced(text, self.category, done and E.ShownKinds(UI.results) or nil)
	DropTick(conv) -- (the key's ` still comes as a typed character)
	E.temp, E.tempSimple = { from = text, category = cat }, nil -- (Simple for a run from fuzzy finding: Advanced now)
	ns:Trace(("advanced once: %q%s -> %q"):format(text, cat and (" [" .. cat .. "]") or "", conv))
	self.category, self.categoryAuto, self.action = nil, nil, nil
	Forget(self, true)
	self.blockedSyntax = nil
	self:SetOrResearch(conv)
	self:SetStatus()
	self:UpdateGhost()
end
