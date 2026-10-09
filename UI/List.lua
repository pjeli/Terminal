local ns = select(2, ...)

-- The list: the result rows, the selection band, the footer (what was found, the key hints), the arrow on a selected
-- NPC's row, and the frame's height following the results. Split out of UI.lua.

local UI = ns.UI
local Fuzzy, Theme = ns.Fuzzy, ns.Theme
local L = UI.layout
local EasyOn, Wake, Style, rows = UI.EasyOn, UI.Wake, UI.Style, UI.rows
local MAX_ROWS, FOOTER_H, ONCE_LABEL = UI.MAX_ROWS, UI.FOOTER_H, UI.ONCE_LABEL

-- key hints, most useful first: on a narrow terminal the last ones are left out, never wrapped. Advanced: what Enter
-- and Shift+Enter do for the selected row (Easy.VERBS), then the command line's own keys
local SYNTAX_KEYS = { { "@", "kind" }, { "/", "slash" }, { ".", "command" }, { "=", "calc" } }

local FZF_LABEL = "Fuzzy find" -- (Tab+`: pure fuzzy finding over every list, this run)
local FZF_HINTS = { { "Enter", "to Simple" }, { "Shift+Enter", "to Advanced" }, { "Up/Down", "move" }, { "Tab+`", "close" } }
local SYNTAX_HINTS = { { "Enter", "write it" }, { "Tab", "next" }, { "Shift+Tab", "back" } } -- (Advanced's @kind / key: pick lists)
-- easy mode (Easy.lua): its footer says what Enter and Shift+Enter do for the selected row
local EASY_TAB_BACK = { "Tab", "all categories" }
local EASY_TAB_PICK = { "Tab", "pick" }

local QUESTION_MARK = 134400
local HINT = "|cffffd200"

--- A row in its place, or `dx` pixels to the right of it (sliding in).
local function PlaceRow(r, dx)
	local y = r.baseY or 0
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", 6 + (dx or 0), y)
	r:SetPoint("TOPRIGHT", -6 + (dx or 0), y)
end
UI.PlaceRow = PlaceRow

----------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------

-- (a block: the footer's helpers are SetStatus's own)
do
	local MODE_LABEL = { cmd = "commands", slash = "slash commands" }
	local STATUS_SEP = "  ·  "
	local function Append(text, x) return text .. (text ~= "" and STATUS_SEP or "") .. x end
	local function Prepend(x, text) return x .. (text ~= "" and STATUS_SEP or "") .. text end

	function UI:SetStatus()
		local status, hints, busy = UI.status, UI.hints, UI.busy
		if not status then return end
		if self.clipHint and not self.keys then
			status:SetText(Theme.FixColors(HINT .. (self.clipHint == "V" and "Press Ctrl+V again to paste" or "Press Ctrl+C again to copy") .. "|r"))
			if hints then hints:Hide() end
			return
		end
		if self.armedEntry then
			-- (what the press does, as the footer said it: "Press Enter to use", "... to cast")
			local a = self.armedEntry
			local enter, shift
			if ns.Easy then enter, shift = ns.Easy.Verbs(a) end -- (not `x and f()`: that keeps only f's first result)
			local verb = (rawget(a, "isShift") and shift) or enter or "open"
			status:SetText(Theme.FixColors(HINT .. "Press Enter to " .. verb .. "|r  " .. a.name))
			if hints then hints:Hide() end -- the armed line gets the whole footer
			return
		end
		if hints then hints:SetShown(Theme.Get().hints and true or false) end
		local count = #UI.results
		local quiet = count > 0 and UI.results[1].noActivate
		local mode = MODE_LABEL[self.mode or ""] -- plain searching needs no label
		local text = quiet and "keep typing, or Esc to close" or (count .. " result" .. (count == 1 and "" or "s"))
		if count > 0 and UI.results[1].catId then text = "found in " .. count .. " categor" .. (count == 1 and "y" or "ies") .. ": pick one" end
		if count > 0 and UI.results[1].syntaxRow then text = count .. " to pick from: Tab / Shift+Tab, Enter writes it" end
		local cat = self.category and EasyOn() and ns.Easy.BY_ID[self.category]
		if self.action and self.mode == "search" then cat = { label = self.action.label } end -- (Advanced: do:use)
		if self.answerNote and self.mode == "search" then cat = { label = self.answerNote } end
		if self.pipeTrail and self.mode == "search" then
			-- (Simple mode says it in words: "Mats for core leather belt", never a ">" chain)
			cat = { label = EasyOn() and ns.Pipes and ns.Pipes.SimpleLabel(self.pipeTrail) or self.pipeTrail }
		end
		if cat then text = HINT .. cat.label .. "|r  ·  " .. text end
		local to = self.sendTo
		if to and self.mode == "search" then
			local group = to.all and to.cmd and self:GroupedRows() -- (grouped once per list, not on every status update)
			local n = group and #group
			if n and n > 0 then ns.Share.Prefetch(group, true) end -- (their links loaded by the time Enter sends them)
			local say = (n and (n == 0 and "nothing to send" or ("Enter sends " .. (n == 1 and "the 1" or ("all " .. n)) .. " to " .. to.label)))
				or (to.cmd and ("Enter sends it to " .. to.label)) or (to.bad and ("no channel called " .. to.bad) or "send to: party, guild, raid, say, whisper <name>...")
			text = Prepend(HINT .. say .. "|r", text)
		end
		if mode then text = Append(text, mode) end
		local near = self.closeSpellings and self.mode == "search" and count > 0
		if self.softRelaxed and self.mode == "search" and count > 0 then
			text = Append(text, HINT .. "nothing matches every word: the closest|r")
			near = true
		end
		if near then text = Append(text, HINT .. "no exact match: close spellings|r") end
		if self.noPosition and self.mode == "search" then
			text = Append(text, HINT .. "sort:nearest: your position isn't known here|r")
			near = true
		end
		if busy and busy:IsShown() then text = Append(text, "loading...") end
		local once = ns.Easy and ns.Easy.temp
		if self.fzf then
			once = true
			text = Prepend(HINT .. FZF_LABEL .. "|r", text)
		elseif once then text = Prepend(HINT .. ONCE_LABEL .. "|r", text) end
		status:SetText((self.sendTo or near or cat or once) and Theme.FixColors(text) or text)
		self:FitHints()
	end
end

--- The key hints: each key in the text colour, its meaning dimmed, as many as fit on one
--- line beside the result count (the less useful ones go first when it's narrow).
function UI:FitHints()
	local frame, status, hints = UI.frame, UI.status, UI.hints
	if not (hints and frame) then return end
	local t = Theme.Get()
	if not t.hints or self.bare then hints:Hide() return end
	local list
	local key = "|cff" .. t.text
	local sel = UI.results[UI.sel]
	if self.fzf then
		list, key = FZF_HINTS, key .. "|fzf"
	elseif not EasyOn() and sel and sel.syntaxRow then
		list, key = SYNTAX_HINTS, key .. "|syntax"
	elseif not EasyOn() then
		-- Advanced: what Enter and Shift+Enter do for the selected row too (Easy.VERBS), then the command line's keys
		-- (Tab completes what the faint text after the cursor shows: that text says it)
		local enter, shift
		if ns.Easy then enter, shift = ns.Easy.Verbs(sel) end
		local write = enter and self:ResultText(sel) ~= nil
		list = {}
		if enter then list[#list + 1] = { "Enter", enter } end
		if shift then list[#list + 1] = { "Shift+Enter", shift } end
		if write then list[#list + 1] = { "Shift+Right", "write it" } end
		for _, k in ipairs(SYNTAX_KEYS) do list[#list + 1] = k end
		key = key .. "|adv|" .. tostring(enter) .. "|" .. tostring(shift) .. "|" .. tostring(write)
	else
		-- what Enter and Shift+Enter do for the selected row, in words (Easy.VERBS)
		local enter, shift = ns.Easy.Verbs(UI.results[UI.sel])
		list = {}
		if enter then list[#list + 1] = { "Enter", enter } end
		-- (Tab before Shift+Enter: on a narrow footer, how to get back counts more)
		if self.category and not self.categoryAuto then list[#list + 1] = EASY_TAB_BACK
		elseif UI.results[UI.sel] and UI.results[UI.sel].catId then list[#list + 1] = EASY_TAB_PICK end
		if shift then list[#list + 1] = { "Shift+Enter", shift } end
		local r = UI.results[UI.sel]
		if r and not (r.catId or r.noActivate) then list[#list + 1] = { "Shift+Right", "more" } end -- (the row menu)
		key = key .. "|" .. tostring(enter) .. "|" .. tostring(shift) .. "|" .. tostring(self.category) .. "|" .. tostring(UI.results[UI.sel] and UI.results[UI.sel].catId)
	end
	local room = (t.width or 640) - 28 - (status:GetStringWidth() or 0) - 24
	-- every render asks: measure again only when the room or the colours (or easy mode's verbs) changed
	if self.hintsRoom == room and self.hintsKey == key then return end
	self.hintsRoom, self.hintsKey = room, key
	key = "|cff" .. t.text
	local parts, text = {}, ""
	for _, h in ipairs(list) do
		parts[#parts + 1] = key .. h[1] .. "|r " .. h[2]
		local try = table.concat(parts, "     ")
		hints:SetText(try)
		if (hints:GetStringWidth() or 0) > room then
			parts[#parts] = nil
			break
		end
		text = try
	end
	hints:SetText(text)
	self.hintCount = #parts
	hints:SetShown(text ~= "")
end

local ARROW = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:12:12|t "

----------------------------------------------------------------------
-- Which way: a small arrow on the selected NPC row (Questie's NPCs: nearest, vendors, trainers...)
-- turning with you. Only the selected row has one, and it runs only while one is shown.
----------------------------------------------------------------------

UI.NAV_TEXTURE = "Interface\\Minimap\\MinimapArrow"
UI.NAV_SIZE = 20
UI.NAV_REFRESH = 0.25 -- seconds between looking up where you are (the turning is every frame)
local nav = {} -- id, row, e, here, spot, d, at, shownD
local navArrow, navTicker

--- What the arrow points at for a row: an NPC's id, or the row itself when it has a place of its own (@mailbox).
local function NavID(e)
	if not e or e.raw then return nil end
	if e.wcont then return e end
	if e.kind ~= "npc" then return nil end
	local id = rawget(e, "key") or e.npcID or e.key -- (a "nearest" view reads its row's)
	return type(id) == "number" and id or nil
end

local function NavHide()
	if navArrow then navArrow:Hide() end
	if navTicker then navTicker:Hide() end
	nav.id, nav.e, nav.row = nil, nil, nil
end
UI.HideNav = NavHide -- (UI.lua's Hide)

local function NavTick()
	local I = ns.Integrations
	local r = nav.row and rows[nav.row]
	if not (I and r and nav.id) then return NavHide() end
	local now = GetTime()
	if not nav.at or now - nav.at >= UI.NAV_REFRESH then
		nav.at = now
		nav.here = I.Here()
		if type(nav.id) == "table" then nav.d, nav.spot = I.RowDistance(nav.id, nav.here)
		else nav.d, nav.spot = I.NpcDistance(nav.id, nav.here) end
	end
	if not nav.spot then
		-- nowhere to point (not on your continent, an instance): rest until the selection changes
		navArrow:Hide()
		navTicker:Hide()
		return
	end
	local face = I.Facing()
	if not face then navArrow:Hide() return end
	local ang = I.Bearing(nav.here, nav.spot, face)
	if not nav.ang or math.abs(ang - nav.ang) > 0.01 then nav.ang = ang; navArrow:SetRotation(ang) end
	-- "nearest": the distance shown keeps up as you walk
	local e = nav.e
	if rawget(e, "_dist") and nav.d then
		local shown = math.floor(nav.d + 0.5)
		if shown ~= nav.shownD then
			nav.shownD = shown
			local rest = rawget(e, "nearRest") -- (what the row is: a title, a zone)
			e.detail = ("%d yd"):format(shown) .. (rest and ("  " .. rest) or "")
			r.detail:SetText(e.detail)
		end
	end
	local w = r.detail:GetStringWidth()
	w = type(w) == "number" and w or 0
	if w ~= nav.w or nav.placedRow ~= r then
		nav.w, nav.placedRow = w, r
		navArrow:ClearAllPoints()
		navArrow:SetPoint("RIGHT", r.detail, "RIGHT", -(w + 4), 0)
	end
	if not navArrow:IsShown() then navArrow:Show() end
end

--- The arrow follows the selection: shown on an NPC row with a known place on your continent.
function UI:UpdateNav()
	local frame = UI.frame
	local e = UI.results[UI.sel]
	local i = UI.sel - UI.offset
	local id = NavID(e)
	if not (id and frame and frame:IsShown() and not self.closing and i >= 1 and i <= L.ROWS and ns.Integrations
		and ns.Integrations.Bearing) then
		return NavHide()
	end
	if not navArrow then
		navArrow = frame:CreateTexture(nil, "OVERLAY")
		navArrow:SetTexture(UI.NAV_TEXTURE)
		navArrow:SetSize(UI.NAV_SIZE, UI.NAV_SIZE)
		navTicker = CreateFrame("Frame", nil, frame)
		navTicker:SetScript("OnUpdate", function()
			if not UI:IsShown() then return NavHide() end
			NavTick()
		end)
		UI.navArrow = navArrow
	end
	navArrow:SetVertexColor(1, 1, 1) -- (the texture's own gold, as the minimap's player arrow)
	if nav.id ~= id or nav.row ~= i or nav.e ~= e then
		nav.id, nav.row, nav.e, nav.at, nav.shownD, nav.ang, nav.w = id, i, e, nil, nil, nil, nil
	end
	NavTick()
	if nav.spot then navTicker:Show() end
end

--- What shows the selection: the arrow, the band, the footer, the tooltip, the ghost text; and the catcher follows
--- its row when the list moved under the pointer (typing, scrolling).
local function ShowSelection(self)
	local catcher = UI.catcher
	self:UpdateNav()
	self:PlaceSelection()
	self:SetStatus()
	self:UpdateTooltip()
	self:UpdateGhost()
	if catcher and catcher.entry and catcher:IsShown() then self:PlaceCatcher(catcher.row) end
end

--- A row that wasn't there comes in with the style (after the `entering` rows already coming in this time); a row
--- that stays keeps its place. Gives how many rows are coming in now.
local function EnterRow(r, animated, now, entering)
	-- a row that wasn't there fades in (one after another); a row that stays just
	-- takes its new text, so typing doesn't repaint the whole list
	if not r:IsShown() or r.leaving then
		r.leaving, r.slideOut = nil, nil -- (reopened while folding away: it comes back)
		if animated then
			local A = Style()
			r.fadeAt = now + entering * A.stagger
			r.slide = A.slide > 0 and A.slide or nil
			if r.slide then PlaceRow(r, -r.slide) end
			entering = entering + 1
			if not r:IsShown() then r:SetAlpha(0) end
			Wake()
		else
			r.fadeAt = nil
			r:SetAlpha(1)
		end
	end
	return entering
end

--- A row's text: its name with the matched letters, the icon, the detail (or what it's needed for), the kind.
local function FillRow(self, r, e, light)
	r:Show()
	if e.raw then
		r.label:SetText(Theme.FixColors(e.name))
	else
		local base = e.color
		if light and base == "|cffffffff" then base = nil end -- white item names vanish on light themes
		if e._pos == nil then e._pos = UI.Positions(e, self.posTokens) end -- only for rows on screen
		r.label:SetText(Theme.FixColors(Fuzzy.Colorize(e.name, e._pos, base)))
	end
	if e.icon == false then
		r.icon:Hide()
	else
		r.icon:Show()
		r.icon:SetTexture(e.icon or QUESTION_MARK)
	end
	local from = self.linked and self.linked[e]
	if from and not e.raw then
		r.label:SetText(ARROW .. r.label:GetText())
		r.detail:SetText((self.linkedGuess and self.linkedGuess[e] and "maybe needs " or "needs ") .. from.name)
	else
		r.detail:SetText(e.detail or "")
	end
	r.kind:SetText(Theme.FixColors(e.kindLabel or ""))
end

function UI:Render()
	local frame = UI.frame
	-- nothing to draw while it's closed (a setting changed in the options panel, say): drawing
	-- then put the rows up, and the next open showed them without their animation
	if not frame or not frame:IsShown() then return end
	local t = Theme.Get()
	local light = Theme.IsLight()
	-- rows come in with the style on every open (snapNext, on open, is for the height only);
	-- only a new layout (theme changes) puts them up at once
	local animated = self:Animated() and not (self.snapNext and not self.opening)
	local now, entering = GetTime(), 0
	for i = 1, MAX_ROWS do
		local r = rows[i]
		local idx = UI.offset + i
		local e = (i <= L.ROWS) and UI.results[idx] or nil
		if e then
			entering = EnterRow(r, animated, now, entering)
			FillRow(self, r, e, light)
		elseif r:IsShown() and not r.leaving then
			-- no result for this row any more: it fades as the list shrinks over it
			if animated and i <= L.ROWS then
				r.leaving, r.leaveAt, r.fadeAt = true, now, nil
				Wake()
			else
				r:Hide()
			end
		elseif not r.leaving then
			r:Hide()
		end
	end
	self:FitHeight()
	ShowSelection(self)
end

--- The selection moved to another row that's already on screen: only what shows the selection is
--- redrawn (the band, the footer, the ghost text, the tooltip, the click catcher), not every row.
function UI:SelectionChanged()
	local frame = UI.frame
	if not frame or not frame:IsShown() then return end
	ShowSelection(self)
end

--- The header's height: the prompt's first line, and every line a long prompt wraps onto.
local function HeaderH() return L.HEADER_H + (UI.promptExtra or 0) end

--- The prompt took more (or fewer) lines: the header grows down, and what's under it moves.
function UI:SetPromptExtra(extra)
	local frame = UI.frame
	if not frame or extra == (self.promptExtra or 0) then return end
	self.promptExtra = extra
	self:LayoutHeader()
	self:FitHeight()
	self.selY = nil -- (the selection band snaps to its row's new place)
	self:PlaceSelection()
end

--- What depends on the header's height: the divider, the prompt's background, the rows, the
--- area that catches clicks on the prompt.
function UI:LayoutHeader()
	local frame, edit, divider, promptBg, hit = UI.frame, UI.edit, UI.divider, UI.promptBg, UI.hit
	if not frame then return end
	local classic = Theme.Get().frame == "classic"
	local hh, extra = HeaderH(), self.promptExtra or 0
	local inset, pin = classic and 5 or 1, classic and 4 or 1
	divider:ClearAllPoints()
	divider:SetPoint("TOPLEFT", inset, -(hh - 4))
	divider:SetPoint("TOPRIGHT", -inset, -(hh - 4))
	promptBg:ClearAllPoints()
	promptBg:SetPoint("TOPLEFT", pin, -pin)
	promptBg:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -pin, -(HeaderH() - 4))
	for i = 1, MAX_ROWS do
		local row = rows[i]
		row.baseY = -hh - (i - 1) * L.ROW_H
		if not row.slide then PlaceRow(row, 0) end
	end
	hit:ClearAllPoints()
	hit:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, 0)
	hit:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", 0, -extra)
end

--- The terminal is as tall as its results: header, one row per result shown, footer. It
--- grows and shrinks smoothly as you type (snaps on open and when animations are off).
function UI:FitHeight(text) -- (text: the prompt's text about to be set, on open)
	local frame, edit, divider, footLine, status = UI.frame, UI.edit, UI.divider, UI.footLine, UI.status
	if not frame then return end
	local n = math.max(0, math.min(L.ROWS, #UI.results - UI.offset))
	-- nothing typed yet: just the prompt, no divider, no footer. Once something is typed the footer stays, in both
	-- modes, even when nothing was found (0.43.4: Simple mode hid it then, and the player lost what the keys do)
	local bare = #UI.results == 0 and self.mode == "search" and not self.sendTo
		and not (text or (edit and edit:GetText()) or ""):find("%S")
	if bare ~= (self.bare or false) then
		self.bare = bare
		divider:SetShown(not bare)
		footLine:SetShown(not bare)
		status:SetShown(not bare)
		self.hintsRoom = nil
		self:FitHints()
	end
	local h
	-- (the prompt's own background stops HeaderH - 4 down, inset by the border: the bare frame ends below it,
	-- or the background covered the bottom border)
	if bare then h = HeaderH() - 4 + (Theme.Get().frame == "classic" and 4 or 1)
	else h = HeaderH() + n * L.ROW_H + (self.footerH or FOOTER_H) end
	self.heightTo = h
	local cur = frame:GetHeight()
	if self.snapNext or not self:Animated() or type(cur) ~= "number" or cur <= 0 then
		frame:SetHeight(h)
	elseif math.abs(cur - h) > 0.5 then
		Wake()
	end
end

--- The selection band: on the selected row, gliding there unless animations are off.
function UI:PlaceSelection()
	local selBar, selEdge = UI.selBar, UI.selEdge
	if not selBar then return end
	local i = UI.sel - UI.offset
	local e = UI.results[UI.sel]
	if not e or e.noActivate or i < 1 or i > L.ROWS then
		selBar:Hide(); selEdge:Hide()
		return
	end
	self.selTo = -HeaderH() - (i - 1) * L.ROW_H
	if not (self:Animated() and self.selY and selBar:IsShown()) then
		self.selY = self.selTo
		self:SetSelectionY(self.selY)
	else
		Wake()
	end
	selBar:Show(); selEdge:Show()
end

function UI:SetSelectionY(y)
	local frame, selBar, selEdge = UI.frame, UI.selBar, UI.selEdge
	self.selPlaced = y
	selBar:ClearAllPoints()
	selBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, y)
	selBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, y)
	selBar:SetHeight(L.ROW_H)
	selEdge:ClearAllPoints()
	selEdge:SetPoint("TOPLEFT", selBar, "TOPLEFT", 0, 0)
	selEdge:SetPoint("BOTTOMLEFT", selBar, "BOTTOMLEFT", 0, 0)
end
