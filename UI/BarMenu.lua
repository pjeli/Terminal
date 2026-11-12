local ns = select(2, ...)
local L = ns.L

-- The bar as it's drawn: the strip under the prompt (Filter, Sort, Group, Send), its menu, and the keys that work
-- them. What's picked and how picks are written into the line is Bar.lua's, loaded just before this (1.4.2: one file
-- until then).

local UI, Theme = ns.UI, ns.Theme
local B = ns.Bar
local state, ById, SortParts, Real = B._.state, B._.ById, B._.SortParts, B._.Real

----------------------------------------------------------------------
-- The strip and its menu
----------------------------------------------------------------------

local strip
local HORN = "Interface\\Icons\\INV_Misc_Horn_01"
-- the speaker (a megaphone's look): the chat frame's voice button's atlas, the voice chat's own; else the old voice
-- chat textures (a speaker, its sound waves over it); else the horn
local SPEAKER_ATLASES = { "chatframe-button-icon-speaker-on", "voicechat-icon-speaker" }
local SPEAKER, WAVES = "Interface\\Common\\VoiceChat-Speaker", "Interface\\Common\\VoiceChat-On"

--- The send button's picture on these textures: which one was used ("atlas:<name>", "file", "horn").
function B.SpeakerIcon(icon, waves)
	waves:Hide()
	local CT = _G.C_Texture
	if CT and CT.GetAtlasInfo and icon.SetAtlas then
		for _, name in ipairs(SPEAKER_ATLASES) do
			local ok, info = pcall(CT.GetAtlasInfo, name)
			if ok and info and pcall(icon.SetAtlas, icon, name) then return "atlas:" .. name end
		end
	end
	-- (SetTexture says whether the file was there; a client that says nothing: taken as there)
	local ok, there = pcall(icon.SetTexture, icon, SPEAKER)
	if ok and there ~= false then
		if waves:SetTexture(WAVES) ~= false then waves:Show() end
		return "file"
	end
	icon:SetTexture(HORN)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	return "horn"
end

local function Label(which, typed)
	typed = typed or B.Typed()
	if which == "filter" then
		-- (what's picked here and what's typed: one list, the typed words' once each)
		local labels, seen = {}, {}
		for _, p in ipairs(typed.filters) do
			if not seen[p.spec] then seen[p.spec] = true; labels[#labels + 1] = B.SpecLabel(p.spec, p.word) end
		end
		for _, id in ipairs(state.filters) do
			if not seen[id] then seen[id] = true; local o = ById(B.FILTERS, id); labels[#labels + 1] = o and o.label or id end
		end
		if #labels == 1 then return L["Filter: %s"]:format(labels[1]) end
		if #labels > 1 then return L["Filter: %d"]:format(#labels) end
		return L["Filter"]
	elseif which == "sort" then
		local list = ns.Filters and ns.Filters.SortList and ns.Filters.SortList(state.sort or (typed.sort and typed.sort.id)) or {}
		local o = list[1] and ById(B.SORTS, (SortParts(list[1])))
		-- (and its "then by", "Sort: Quality, Level")
		local nxt = state.thenBy or (not state.sort and list[2]) or nil
		-- (none after distance: rows don't tie on yards, so a field after it isn't said; review)
		local t = nxt and SortParts(list[1]) ~= "distance" and ById(B.SORTS, (SortParts(nxt)))
		if o and t then return L["Sort: %s, %s"]:format(o.label, t.label) end
		return o and L["Sort: %s"]:format(o.label) or L["Sort"]
	else
		local g = B.GroupOn() -- (a group typed is the one summed up: TakeAggregate; steps typed: none of the bar's)
		local f = g and ns.Aggregate and ns.Aggregate.FIELDS[g]
		return f and L["Group: %s"]:format(ns.UpperFirst(f.label)) or B.GroupWord()
	end
end

B.Label = function(which) return Label(which, B.Typed()) end -- (a button's words, as shown)

--- The Group button's word when nothing's grouped: "Group". Translated as "Group by", since "Group" is also the party's
--- word and some languages say the two differently (zhCN: 队伍, the party; 分组, grouping).
function B.GroupWord()
	local t = L["Group by"]
	if t == "Group by" then t = L["Group"] end -- (English, or not translated yet)
	return t
end

local function Build()
	if strip or not UI.frame then return strip end
	strip = CreateFrame("Frame", nil, UI.frame)
	strip.buttons = {}
	for _, which in ipairs({ "filter", "sort", "group" }) do
		local b = CreateFrame("Button", nil, strip)
		b.which = which
		b.text = b:CreateFontString(nil, "OVERLAY")
		b.text:SetFontObject(Theme.fonts.small)
		b.text:SetPoint("CENTER", 0, 0)
		b.text:SetWordWrap(false)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		-- (its key's letter underlined, Alt+F, Alt+S, Alt+G: B.Underline)
		b.under = b:CreateTexture(nil, "OVERLAY")
		b.under:SetHeight(1)
		b.under:Hide()
		if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
		b:SetScript("OnClick", function(_, button)
			if UI.closing then return end
			if button == "RightButton" then B.Clear(which) B.HideMenu() return end
			if b.off then return end
			if B.menu and B.menu:IsShown() and B.menu.which == which then B.HideMenu() return end
			B.ShowMenu(which, b)
		end)
		b:SetScript("OnEnter", function() b.hover = true; B.Shade(b) end) -- (only its shade: nothing moves under the pointer)
		b:SetScript("OnLeave", function() b.hover = nil; B.Shade(b) end)
		strip.buttons[#strip.buttons + 1] = b
	end
	strip.measure = strip:CreateFontString(nil, "OVERLAY") -- (B.Underline's ruler: never shown)
	strip.measure:SetFontObject(Theme.fonts.small)
	strip.measure:Hide()
	local horn = CreateFrame("Button", nil, strip)
	horn.bg = horn:CreateTexture(nil, "BACKGROUND")
	horn.bg:SetAllPoints()
	horn.edges = {}
	for i = 1, 4 do horn.edges[i] = horn:CreateTexture(nil, "BORDER") end
	local e1, e2, e3, e4 = horn.edges[1], horn.edges[2], horn.edges[3], horn.edges[4]
	e1:SetPoint("TOPLEFT"); e1:SetPoint("TOPRIGHT"); e1:SetHeight(1)
	e2:SetPoint("BOTTOMLEFT"); e2:SetPoint("BOTTOMRIGHT"); e2:SetHeight(1)
	e3:SetPoint("TOPLEFT"); e3:SetPoint("BOTTOMLEFT"); e3:SetWidth(1)
	e4:SetPoint("TOPRIGHT"); e4:SetPoint("BOTTOMRIGHT"); e4:SetWidth(1)
	horn.icon = horn:CreateTexture(nil, "ARTWORK")
	horn.icon:SetPoint("TOPLEFT", 2, -2)
	horn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	horn.waves = horn:CreateTexture(nil, "OVERLAY")
	horn.waves:SetAllPoints(horn.icon)
	B.SpeakerIcon(horn.icon, horn.waves)
	if horn.RegisterForClicks then horn:RegisterForClicks("LeftButtonUp") end
	horn:SetScript("OnClick", function() if not UI.closing then B.Horn() end end)
	horn:SetScript("OnEnter", function()
		-- (its own tooltip, as the spinner's: the game's faded with the interface under .zen; Zen.lua keeps this one)
		if not B.tip then
			local ok, tip = pcall(CreateFrame, "GameTooltip", "TerminalBarTip", UIParent, "GameTooltipTemplate")
			B.tip = ok and tip or nil
			if B.tip and ns.Zen then ns.Zen.Made(B.tip) end
		end
		local tip = B.tip
		if not tip then return end
		-- that one put away while the pointer is here, and this one growing left, over the terminal
		if UI.HideTooltip then UI:HideTooltip() end
		B.tipUp = true
		tip:SetOwner(horn, "ANCHOR_TOPLEFT")
		tip:SetText(L["Send or copy all"], 1, 1, 1)
		tip:AddLine(L["Every result at once, to say, party, raid, guild..., or copied as text or CSV (one result: right-click it)"], 0.8, 0.8, 0.8, true)
		tip:Show()
	end)
	horn:SetScript("OnLeave", function()
		if B.tip then B.tip:Hide() end
		B.tipUp = nil
		if UI.UpdateTooltip and UI:IsShown() then UI:UpdateTooltip() end -- (the selected row's back)
	end)
	strip.horn = horn
	B.strip = strip
	return strip
end

--- How tall the bar is now (0: not shown), for the header (List.lua's HeaderH).
function B.Height() return B.On() and B.H or 0 end

--- Shown or hidden, its labels: from the footer's update (List.lua), on every keystroke and selection.
function B.Update()
	B.TidyThen()
	if not UI.frame then return end
	local h = B.Height()
	if h ~= (UI.barH or 0) then
		UI.barH = h
		if UI.LayoutHeader then UI:LayoutHeader() end
		if UI.FitHeight then UI:FitHeight() end
		UI.selY = nil
		if UI.PlaceSelection then UI:PlaceSelection() end
	end
	local s = Build()
	if not s then return end
	s:SetShown(h > 0)
	if h == 0 then
		B.HideMenu()
		-- (gone under the pointer: no OnLeave may come; its tooltip goes, and the row's may show again)
		if B.tipUp then B.tipUp = nil; if B.tip then B.tip:Hide() end end
		return
	end
	local t = Theme.Get()
	local classic = t.frame == "classic"
	local inset = classic and 9 or 6
	local top = (UI.tabsH or 0) + ns.UI.layout.HEADER_H + (UI.promptExtra or 0) - 4
	-- (only whether categories show: B.Overview stops at the first; ShownKinds walked every row and built the kinds on
	-- every keystroke and selection move)
	local overview = B.Overview(UI.results)
	-- (placed again only when where it goes or a label's width changed: a frame moved under the pointer loses it, so
	-- placing the buttons on every footer update took every hover and click away)
	local widths = {}
	local typed = B.Typed() -- (once per update, not per button: it runs on every keystroke)
	for i, b in ipairs(s.buttons) do
		local label = Label(b.which, typed)
		if b.label ~= label then b.label = label; b.text:SetText(label); B.Underline(b) end
		widths[i] = math.ceil((b.text:GetStringWidth() or 40) + 18)
	end
	local laid = table.concat({ inset, top, h, table.concat(widths, ",") }, ":")
	if s.laid ~= laid then
		s.laid = laid
		s:ClearAllPoints()
		s:SetPoint("TOPLEFT", UI.frame, "TOPLEFT", inset, -top)
		s:SetPoint("TOPRIGHT", UI.frame, "TOPRIGHT", -inset, -top)
		s:SetHeight(h - 2)
		local x = 0
		for i, b in ipairs(s.buttons) do
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", s, "TOPLEFT", x, 0)
			b:SetSize(widths[i], h - 2)
			b:Show()
			x = x + widths[i] + 4
		end
		for _, b in ipairs(s.buttons) do B.Underline(b) end
		local horn = s.horn
		horn:ClearAllPoints()
		horn:SetPoint("RIGHT", s, "RIGHT", -2, 0)
		horn:SetSize(h - 4, h - 4)
	end
	for _, b in ipairs(s.buttons) do
		local active = (b.which == "filter" and (#state.filters > 0 or #typed.filters > 0)) or (b.which == "sort" and (state.sort or typed.sort))
			or (b.which == "group" and B.GroupOn())
		b.off = overview and b.which ~= "filter" and not active
		b.active = active and true or false
		local col = b.off and t.dim or (active and t.accent or t.text)
		b.text:SetTextColor(Theme.RGB(col))
		b.under:SetColorTexture(Theme.RGB(col))
		B.Shade(b)
	end
	s.horn.off = not B.FirstReal()
	s.horn:SetAlpha(s.horn.off and 0.35 or 1)
	s.horn.bg:SetColorTexture(0, 0, 0, 0.6)
	local br, bg, bb = Theme.RGB(t.border)
	for _, edge in ipairs(s.horn.edges) do edge:SetColorTexture(br, bg, bb, 1) end
end

-- each button's key: Alt+F, Alt+S, Alt+G (Keys.lua)
B.KEY_LETTER = { filter = "f", sort = "s", group = "g" }

--- Its key's letter underlined in its label, as a menu's keys are shown: the first F of "Filter", S of "Sort", G of
--- "Group". A language whose word hasn't that letter: none.
function B.Underline(b)
	local u, label = b.under, ns.Plain and ns.Plain(tostring(b.label or "")) or tostring(b.label or "")
	local letter = B.KEY_LETTER[b.which]
	local at = letter and label:lower():find(letter, 1, true)
	-- (only in the button's own word, before its ":" and what's picked: "Ordenado: Más cercano" has no s of its own;
	-- release review, the s of "Más" was underlined)
	local stop = math.min(label:find(":", 1, true) or #label + 1, label:find("\239\188\154", 1, true) or #label + 1)
	if at and at >= stop then at = nil end
	local m = strip and strip.measure
	if not (at and m) then u:Hide() return end
	m:SetText(label:sub(1, at - 1))
	local before = at > 1 and (m:GetStringWidth() or 0) or 0
	m:SetText(label:sub(at, at))
	local wide = m:GetStringWidth() or 0
	if wide <= 0 then u:Hide() return end
	u:ClearAllPoints()
	u:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", math.floor(before + 0.5), 0)
	u:SetWidth(math.max(1, math.floor(wide + 0.5)))
	u:Show()
	b.underAt, b.underWide = before, wide -- (tests)
end

--- A button's background: the accent, stronger when it has something picked, a little more under the pointer.
function B.Shade(b)
	local ar, ag, ab = Theme.RGB(Theme.Get().accent)
	b.bg:SetColorTexture(ar, ag, ab, (b.active and 0.18 or 0) + (b.hover and not b.off and 0.14 or 0))
end

local MENU_W, LINE = 180, 20
local function MenuFrame()
	if B.menu then return B.menu end
	local m = CreateFrame("Frame", "TerminalBarMenu", UIParent, "BackdropTemplate")
	if ns.Zen then ns.Zen.Made(m) end -- (made while .zen has the interface faded: kept up, Zen.lua; else it faded with it)
	m:SetFrameStrata("TOOLTIP")
	m:SetClampedToScreen(true)
	m:EnableMouse(true)
	m.lines = {}
	pcall(m.RegisterEvent, m, "GLOBAL_MOUSE_DOWN")
	m:SetScript("OnEvent", function()
		if m:IsShown() and not (m.IsMouseOver and m:IsMouseOver()) and not (m.owner and m.owner.IsMouseOver and m.owner:IsMouseOver()) then
			m:Hide()
		end
	end)
	m:Hide()
	B.menu = m
	return m
end

local function MenuLine(m, i)
	local b = m.lines[i]
	if b then return b end
	b = CreateFrame("Button", nil, m)
	b:SetSize(MENU_W - 8, LINE)
	b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * LINE)
	b.fs = b:CreateFontString(nil, "OVERLAY")
	b.fs:SetFontObject(Theme.fonts.small)
	b.fs:SetPoint("LEFT", 20, 0)
	b.fs:SetPoint("RIGHT", -6, 0)
	b.fs:SetJustifyH("LEFT")
	b.check = b:CreateTexture(nil, "OVERLAY")
	b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	b.check:SetSize(14, 14)
	b.check:SetPoint("LEFT", 3, 0)
	-- (a sort's way: the game's sort arrow, as its auction house columns show it, up or down)
	b.arrow = b:CreateTexture(nil, "OVERLAY")
	b.arrow:SetTexture(B.ARROW)
	b.arrow:SetSize(9, 8)
	b.arrow:SetPoint("CENTER", b.check, "CENTER", 0, 0)
	b.arrow:Hide()
	b.hl = b:CreateTexture(nil, "BACKGROUND")
	b.hl:SetAllPoints()
	b.hl:Hide()
	b:SetScript("OnEnter", function() b.hl:Show() end)
	b:SetScript("OnLeave", function() if not (m.keys and m.keySel == i) then b.hl:Hide() end end)
	b:SetScript("OnClick", function()
		local which, id = m.which, b.id
		if id == nil then return end -- (a line saying something: nothing to pick)
		if id == false then B.Clear(which) m:Hide() return end
		-- (Shift: Sort's "then by")
		B.Pick(which, id, which == "sort" and IsShiftKeyDown and IsShiftKeyDown() or nil)
		-- (filters add up: it stays open, the keys' line where it was)
		-- (the keys' line: the one picked again, found by what it is; a typed one unticked has gone: the line where it was)
		if which == "filter" then B.ShowMenu(which, m.owner, m.keys, m.keys and m.keySel, id) else m:Hide() end
	end)
	m.lines[i] = b
	return b
end

local function HasOn(opts) for _, o in ipairs(opts) do if o.on then return true end end return false end

--- A button's menu, under it: its options, the ones picked ticked (typed ones say so), "None" on top to clear.
function B.ShowMenu(which, owner, keys, sel, selId)
	local m = MenuFrame()
	local t = Theme.Get()
	local opts = B.Options(which)
	local items = { { id = false, label = which == "filter" and L["No filter"] or which == "sort" and L["Best match"] or L["No groups"],
		on = #opts == 0 or not HasOn(opts) } }
	for _, o in ipairs(opts) do items[#items + 1] = o end
	if #opts == 0 then items[#items + 1] = { label = L["Nothing to pick for these results"], dead = true } end
	-- (a field sorted by: Shift picks another to go by on a tie)
	if which == "sort" then
		for _, o in ipairs(opts) do
			local so = o.on and not o.thenBy and ById(B.SORTS, o.id)
			if so and so.field then items[#items + 1] = { label = L["Shift: then by another"], dead = true } break end
		end
	end
	m.which, m.owner = which, owner
	for i, it in ipairs(items) do
		local b = MenuLine(m, i)
		-- ("No filter" is false: kept, not turned into nil by an and/or; a line saying something has none)
		if it.dead then b.id = nil else b.id = it.id end
		b.fs:SetText(it.thenBy and L["then by %s"]:format(it.label) or it.typed and L["%s (typed)"]:format(it.label) or it.label)
		b.fs:SetTextColor(Theme.RGB(it.dead and t.dim or (it.on and t.accent or t.text)))
		local way = it.on and it.asc ~= nil
		b.check:SetShown((it.on and not way) and true or false)
		b.arrow:SetShown(way and true or false)
		if way then
			if it.asc then b.arrow:SetTexCoord(0, 0.5625, 1, 0) else b.arrow:SetTexCoord(0, 0.5625, 0, 1) end -- (up / down)
			b.arrow:SetVertexColor(Theme.RGB(t.accent))
		end
		b.hl:SetColorTexture(Theme.RGB(t.accent))
		b.hl:SetAlpha(0.25)
		b.hl:Hide()
		b:EnableMouse(not it.dead)
		b:Show()
	end
	for i = #items + 1, #m.lines do m.lines[i]:Hide() end
	-- (opened from the keys, Alt+F/S/G: a line picked to move from, the one ticked first; B.MenuKey)
	m.n, m.keys, m.keySel = #items, keys and true or nil, nil
	if keys then
		local first, byId
		for i, it in ipairs(items) do
			if it.on and i > 1 then first = first or i end
			if selId ~= nil and it.id == selId and not it.dead then byId = byId or i end
		end
		B.MenuSelect(byId or (sel and math.min(sel, #items)) or first or 1)
	end
	m:SetSize(MENU_W, #items * LINE + 8)
	ns.Panel.Flat(m)
	local r, g, bb = Theme.RGB(t.bg)
	m:SetBackdropColor(r, g, bb, 0.97)
	m:SetBackdropBorderColor(Theme.RGB(t.border))
	m:SetScale(t.scale or 1)
	m:ClearAllPoints()
	-- (by screen position, as the row menu is: never anchored into the terminal's frame)
	local left, bottom, os, ms = owner:GetLeft(), owner:GetBottom(), owner:GetEffectiveScale(), m:GetEffectiveScale()
	if type(left) == "number" and type(bottom) == "number" and type(os) == "number" and type(ms) == "number" and ms > 0 then
		m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * os / ms, bottom * os / ms - 2)
	else
		m:SetPoint("CENTER", UIParent, "CENTER")
	end
	m:Show()
end

function B.HideMenu() if B.menu then B.menu:Hide() end end

----------------------------------------------------------------------
-- The keys: the menu opens with a line picked; Up/Down (Tab) move, Enter or Space picks (Filter's stay open),
-- Left/Right go to the next menu, Esc closes it. Any other key closes it and does what it does.
----------------------------------------------------------------------

B.ALT_KEYS = { F = "filter", S = "sort", G = "group" }

--- Alt+F's character, when the client types one for it (Windows types the f, a Mac's Option+F ƒ): not typed. Only that
--- key's letter, or a character a Mac makes of it, and only before the next key goes down (Keys.lua): nothing coming,
--- the next letter isn't eaten.
function B.SwallowAltChar(key)
	UI.swallowChar = { at = GetTime(), letter = type(key) == "string" and ns.Lower(key) or nil }
end
local ORDER = { "filter", "sort", "group" }

--- Line `i` of the open menu picked from the keys (round the ends; a line saying something skipped).
function B.MenuSelect(i, dir)
	local m = B.menu
	if not (m and m.n and m.n > 0) then return end
	for _ = 1, m.n do
		i = (i - 1) % m.n + 1
		if m.lines[i].id ~= nil then break end
		i = i + (dir or 1)
	end
	if m.keySel and m.lines[m.keySel] then m.lines[m.keySel].hl:Hide() end
	m.keySel = i
	m.lines[i].hl:Show()
end

--- Alt+F / Alt+S / Alt+G: that menu, from the keys. False when the bar isn't showing (the key does what it did).
function B.KeyOpen(which)
	if not B.On() then return false end
	B.Update()
	local s = B.strip
	if not s then return false end
	if UI.HideRowMenu then UI:HideRowMenu() end -- (one menu from the keys at a time)
	for _, b in ipairs(s.buttons) do
		-- (one that can't be used now, Sort and Group over the categories, as a click: the key taken, nothing opened)
		if b.which == which then
			if b.off then B.HideMenu() return true end
			B.ShowMenu(which, b, true)
			return true
		end
	end
	return false
end

--- A key while a bar menu opened from the keys is up: true when it was the menu's.
function B.MenuKey(f, key)
	local m = B.menu
	if not (m and m.keys and m:IsShown()) then return false end
	local function Took() f:SetPropagateKeyboardInput(false) return true end
	if IsAltKeyDown and IsAltKeyDown() and B.ALT_KEYS[key] then
		B.SwallowAltChar(key)
		if B.ALT_KEYS[key] == m.which then B.HideMenu() else B.KeyOpen(B.ALT_KEYS[key]) end
		return Took()
	end
	-- (the terminal's key, ` or ^ or Ctrl+Space: closes the menu, before Space picks a line, and its character isn't typed
	-- after it, as the row menu's; 0.65.x review)
	if ns.IsTickKey(key) then
		B.HideMenu()
		UI.swallowTick = GetTime()
		return Took()
	end
	if key == "UP" or (key == "TAB" and IsShiftKeyDown()) then
		B.MenuSelect((m.keySel or 1) - 1, -1)
	elseif key == "DOWN" or key == "TAB" then
		B.MenuSelect((m.keySel or 0) + 1, 1)
	elseif key == "LEFT" or key == "RIGHT" then
		-- (the next menu that can be used: Filter alone over the categories)
		local at, step = 1, key == "LEFT" and -1 or 1
		for i, w in ipairs(ORDER) do if w == m.which then at = i end end
		local off = {}
		for _, b in ipairs(B.strip and B.strip.buttons or {}) do off[b.which] = b.off end
		for _ = 1, #ORDER do
			at = (at - 1 + step) % #ORDER + 1
			if not off[ORDER[at]] then break end
		end
		if ORDER[at] ~= m.which then B.KeyOpen(ORDER[at]) end
	elseif key == "ENTER" or key == "NUMPADENTER" or key == "SPACE" then
		if key == "SPACE" then UI.swallowChar = { at = GetTime(), ch = " " } end
		local b = m.keySel and m.lines[m.keySel]
		if b then b:GetScript("OnClick")(b) end
	elseif key == "ESCAPE" then
		B.HideMenu()
	else
		B.HideMenu()
		return false
	end
	return Took()
end

--- The first result to send (the selected one when it is one), its place in the list; nil when none is.
function B.FirstReal()
	local res = UI.results or {}
	if Real(res[UI.sel]) then return UI.sel end
	for i, e in ipairs(res) do if Real(e) then return i end end
	-- (grouped or summed up: its rows, to copy out all of them)
	for i, e in ipairs(res) do if type(e) == "table" and e.kind == "aggregate" and not e.noActivate then return i end end
end

--- The send button: every result at once, to a channel or copied.
function B.Horn()
	B.HideMenu()
	local i = B.FirstReal()
	if not i then ns:Print(L["Nothing to send yet: search for something first."]) return end
	UI:ShowRowMenu(i, false, true)
end
