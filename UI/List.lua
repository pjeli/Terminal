local ns = select(2, ...)
local L = ns.L

-- The list: the result rows, the selection band, the footer (what was found, the key hints), the arrow on a selected
-- NPC's row, and the frame's height following the results. Split out of UI.lua.

local UI = ns.UI
local Fuzzy, Theme = ns.Fuzzy, ns.Theme
local LY = UI.layout
local EasyOn, Wake, Style, rows = UI.EasyOn, UI.Wake, UI.Style, UI.rows
local MAX_ROWS, FOOTER_H, ONCE_LABEL = UI.MAX_ROWS, UI.FOOTER_H, UI.ONCE_LABEL
-- a field's say in the rows' detail when the search is sorted by it (or asks for it): field -> function(e, field)
-- returning the detail, or nil for the row's own (Auctionator.lua: ahvalue, ahprice; Rewards.lua: slots)
ns.FIELD_DETAIL = ns.FIELD_DETAIL or {}

-- key hints, most useful first: on a narrow terminal the last ones are left out, never wrapped. Advanced: what Enter
-- and Shift+Enter do for the selected row (Easy.VERBS), then the command line's own keys
local SYNTAX_KEYS = { { "@", L["kind"] }, { "/", L["slash"] }, { ".", L["command"] }, { "=", L["calc"] } }

-- F1: every key, per mode (Apps/KeysWindow.lua). Last in every list but Advanced's (before its syntax keys): the first to
-- go when the footer is narrow, it's there for finding the rest
local KEYS_HINT = { "F1", L["keys"] }
local FZF_LABEL = L["Fuzzy find"] -- (Tab+`: pure fuzzy finding over every list, this run)
local HIST_HINTS = { { "Enter", L["put it in the prompt"] }, { "Ctrl+R", L["older"] }, { "Esc", L["back"] }, KEYS_HINT }
local FZF_HINTS = { { "Enter", L["to Simple"] }, { "Shift+Enter", L["with its list"] }, { "Up/Down", L["move"] }, { "Tab+`", L["close"] }, KEYS_HINT }
-- (Advanced's @kind / key: pick lists; "back" is Shift+Left's word, so Shift+Tab is "previous")
local SYNTAX_HINTS = { { "Enter", L["write it"] }, { "Tab", L["next"] }, { "Shift+Tab", L["previous"] }, KEYS_HINT }
-- easy mode (Easy.lua): its footer says what Enter and Shift+Enter do for the selected row
local BACK_HINT = { "Shift+Left", L["back"] } -- (back to the search a step left, UI:GoBack)
local BACK_CATEGORIES = { "Shift+Left", L["all categories"] } -- (Simple mode, a category picked)
local EASY_TAB_PICK = { "Tab", L["pick"] }

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
	local MODE_LABEL = { cmd = L["commands"], slash = L["slash commands"] }
	local STATUS_SEP = "  ·  "
	local function Append(text, x) return text .. (text ~= "" and STATUS_SEP or "") .. x end
	local function Prepend(x, text) return x .. (text ~= "" and STATUS_SEP or "") .. text end

	--- ">> track only" on a row: how many others it untracks (0.63.7, review: the footer said only "Enter tracks it").
	local function OnlyFooter(e)
		local QK = ns.QuestTrack
		local o = QK and type(e) == "table" and (rawget(e, "pipeOf") or e) or nil
		if not (o and o.kind == "quests" and type(o.questID) == "number") then return nil end
		local n = #QK.Plan({ o }, "only").untrack
		return n > 0 and (n == 1 and L["Enter tracks only it: 1 other untracked"] or L["Enter tracks only it: %d others untracked"]:format(n))
			or L["Enter tracks it"]
	end

	function UI:SetStatus()
		local status, hints, busy = UI.status, UI.hints, UI.busy
		if not status then return end
		if ns.Bar then ns.Bar.Update() end -- (Simple mode's bar: shown or not, what it says; Bar.lua)
		if self.clipHint and not self.keys then
			status:SetText(Theme.FixColors(HINT .. (self.clipHint == "V" and L["Press Ctrl+V again to paste"] or L["Press Ctrl+C again to copy"]) .. "|r"))
			if hints then hints:Hide() end
			return
		end
		if self.armedEntry then
			-- (what the press does, as the footer said it: "Press Enter: use", "...: cast"; 0.49.2, review: "Press Enter to %s" read
			-- "Press Enter to options" where the verb is a noun)
			local a = self.armedEntry
			local enter, shift
			if ns.Easy then enter, shift = ns.Easy.Verbs(a) end -- (not `x and f()`: that keeps only f's first result)
			local verb = (rawget(a, "isShift") and shift) or enter or L["open"]
			status:SetText(Theme.FixColors(HINT .. L["Press Enter: %s"]:format(verb) .. "|r  " .. a.name))
			if hints then hints:Hide() end -- the armed line gets the whole footer
			return
		end
		if hints then hints:SetShown(Theme.Get().hints and true or false) end
		local count = #UI.results
		local quiet = count > 0 and UI.results[1].noActivate
		local mode = MODE_LABEL[self.mode or ""] -- plain searching needs no label
		local text = quiet and L["keep typing, or Esc to close"] or (count == 1 and L["%s result"] or L["%s results"]):format(count)
		-- (grouped: how many groups, and how many results they hold; 0.56.2, the player's screenshot said "14 results"
		-- for 14 dungeons holding 34 swords)
		local groups, inside = 0, 0
		for _, e in ipairs(UI.results) do
			local n = rawget(e, "groupN")
			if n then groups, inside = groups + 1, inside + n end
		end
		if groups > 0 then
			text = (groups == 1 and L["%d group"] or L["%d groups"]):format(groups) .. STATUS_SEP
				.. (inside == 1 and L["%s result"] or L["%s results"]):format(inside)
		end
		if count > 0 and UI.results[1].catId then text = (count == 1 and L["found in %s category: pick one"] or L["found in %s categories: pick one"]):format(count) end
		-- (Simple mode's clear winner above the categories: Search.lua's EasyOverview)
		if count > 1 and self.overviewWinner and UI.results[1] == self.overviewWinner then
			text = L["the best match first, or pick one of %s categories"]:format(count - 1)
		end
		if count > 0 and UI.results[1].syntaxRow then text = L["%s to pick from: Tab / Shift+Tab, Enter writes it"]:format(count) end
		local cat = self.category and EasyOn() and ns.Easy.BY_ID[self.category]
		if self.action and self.mode == "search" then cat = { label = self.action.label } end -- (Advanced: do:use)
		if self.answerNote and self.mode == "search" then cat = { label = self.answerNote } end
		if self.pipeTrail and self.mode == "search" then
			-- (Simple mode says it in words: "Mats for core leather belt", never a ">" chain)
			cat = { label = EasyOn() and ns.Pipes and ns.Pipes.SimpleLabel(self.pipeTrail) or self.pipeTrail }
		end
		if cat then text = HINT .. cat.label .. "|r  ·  " .. text end
		local to = self.sendTo
		local selRow = UI.results[UI.sel]
		if to and self.mode == "search" and selRow and selRow.catId then
			-- (a category row selected: Enter picks it, the count says so; what's sent is in it. 0.63.7, review: it said
			-- "Enter sends it to party", and sent the word "Items")
		elseif to and to.drop and self.mode == "search" then
			local n = to.all and self.groupRows and #self.groupRows
			local say = (to.all and ((n or 0) == 0 and L["nothing to drop"] or (n == 1 and L["Enter drops it: Terminal asks first"] or L["Enter drops all %s: Terminal asks first"]:format(n))))
				or L["Enter drops it: Terminal asks first"]
			text = Prepend(HINT .. say .. "|r", text)
		elseif to and to.quests and self.mode == "search" then
			-- (">>>": the one row's own word when it does nothing: "no quest in your log among the results"; 0.63.7, review)
			local row = UI.results[1]
			local say = to.all and ((row and row.noActivate and row.detail) or L["Enter changes the tracker for the quests listed"])
				or (to.quests == "untrack" and L["Enter untracks it"]) or (to.quests == "only" and OnlyFooter(selRow))
				or L["Enter tracks it"]
			text = Prepend(HINT .. say .. "|r", text)
		elseif to and to.copy and self.mode == "search" then
			local n = to.all and self.groupRows and #self.groupRows
			local say = to.all and ((n or 0) == 0 and L["nothing to copy"] or L["Enter copies all %s as %s"]:format(n, to.label))
				or L["Enter copies it as %s"]:format(to.label)
			text = Prepend(HINT .. say .. "|r", text)
		elseif to and self.mode == "search" then
			local group = to.all and to.cmd and self:GroupedRows() -- (grouped once per list, not on every status update)
			local n = group and #group
			if n and n > 0 then ns.Share.Prefetch(group, true) end -- (their links loaded by the time Enter sends them)
			local one = n and n > 0 and ns.Share.Restricted(to) -- (say, yell: one line the game presses)
			local say = (one and L["Enter sends one line to %s, all %s counted"]:format(to.label, n))
				or (n and (n == 0 and L["nothing to send"] or (n == 1 and L["Enter sends the 1 to %s"]:format(to.label) or L["Enter sends all %s to %s"]:format(n, to.label))))
				or (to.cmd and L["Enter sends it to %s"]:format(to.label)) or (to.bad and L["no channel called %s"]:format(to.bad) or L["send to: party, guild, raid, say, whisper <name>..."])
			text = Prepend(HINT .. say .. "|r", text)
		end
		if mode then text = Append(text, mode) end
		local near = self.closeSpellings and self.mode == "search" and count > 0
		if self.softRelaxed and self.mode == "search" and count > 0 then
			text = Append(text, HINT .. L["nothing matches every word: the closest"] .. "|r")
			near = true
		end
		if near then text = Append(text, HINT .. L["no exact match: close spellings"] .. "|r") end
		if self.noPosition and self.mode == "search" then
			text = Append(text, HINT .. L["sort:distance: your position isn't known here"] .. "|r")
			near = true
		end
		-- (flight paths listed on a continent no flight master's map has been read on: Search.lua's Scan.FlightNote)
		if self.flightNote and self.mode == "search" and count > 0 then text = Append(text, HINT .. self.flightNote .. "|r") end
		-- (recipes you don't know listed, a profession's window that would list more not read yet: MissingRecipes.lua)
		if self.missingNote and self.mode == "search" and count > 0 then text = Append(text, HINT .. self.missingNote .. "|r") end
		-- (upgrades weighed: how to judge them otherwise, with them listed or none; Search.lua's UI:Search, 0.65.9)
		if self.weightsNote and self.mode == "search" then text = Append(text, HINT .. self.weightsNote .. "|r") end
		if busy and busy:IsShown() then text = Append(text, L["loading..."]) end
		-- (a search run again in the background found more: UI.held, shown on F5)
		if self.held and self.mode == "search" then text = Append(text, HINT .. L["new results: F5 shows them"] .. "|r") end
		-- (a category listing another number than its row counted: UI:NoteCountChange)
		if self.countNote and self.mode == "search" then text = Append(text, HINT .. self.countNote.text .. "|r") end
		-- (an addon the line reaches for that isn't installed: which one to add, on a line of its own; Setup.lua)
		local I = ns.Integrations
		local missing = self.mode == "search" and not self.bare and I and I.MissingHint and UI.edit and I.MissingHint(UI.edit:GetText()) or nil
		self:SetFooterExtra(missing) -- (the footer's dim colour, not the gold of a notice: 0.50.6)
		local once = ns.Easy and ns.Easy.temp
		if self.histSearch then
			once = true
			text = Prepend(HINT .. L["History search (Ctrl+R)"] .. "|r", text)
		elseif self.fzf then
			once = true
			text = Prepend(HINT .. FZF_LABEL .. "|r", text)
		elseif once then text = Prepend(HINT .. ONCE_LABEL .. "|r", text) end
		status:SetText(Theme.FixColors(text)) -- (always: the notes' gold too, on light themes; it returns at once on dark ones)
		self:FitHints()
		if (self.tabsH or 0) > 0 and ns.Tabs then ns.Tabs.Draw() end -- (the tab shown: its text and count)
	end
end

--- What Enter does to the selected row while ">> party", ">> drop", ">> track"... is typed: the one verb (false: none, no
--- channel yet), or nil when the row's own verbs stand (">>>", a category to pick, a heading). Both modes (0.63.7, review:
--- Simple mode's hints said "use" while its footer said where it went). (review, 0.48.6: the hints said "Enter open"
--- while the status line said where it would be sent)
local function SendVerb(self, sel)
	local to = self.sendTo
	if not (to and not to.all and self.mode == "search" and sel) then return nil end
	if sel.noActivate or sel.raw or sel.completion or UI.PicksFirst(sel) then return nil end
	if to.drop then return L["drop"] end
	if to.quests then
		return (to.quests == "untrack" and L["untrack"]) or (to.quests == "only" and L["track only it"]) or L["track"]
	end
	if to.copy then return L["copy as %s"]:format(to.label) end
	if to.cmd then return L["send it to %s"]:format(tostring(to.label)) end
	return false
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
	-- (a step's search, or a line Up brought back: Shift+Left goes back, UI:GoBack)
	local back = self:CanStepBack()
	if self.histSearch then
		list, key = HIST_HINTS, key .. "|hist"
	elseif self.fzf then
		list, key = FZF_HINTS, key .. "|fzf"
	elseif not EasyOn() and sel and sel.syntaxRow then
		list, key = SYNTAX_HINTS, key .. "|syntax"
	elseif not EasyOn() then
		-- Advanced: what Enter and Shift+Enter do for the selected row too (Easy.VERBS), then the command line's keys
		-- (Tab completes what the faint text after the cursor shows: that text says it)
		local enter, shift
		if ns.Easy then enter, shift = ns.Easy.Verbs(sel) end
		local sent = SendVerb(self, sel)
		if sent ~= nil then enter, shift = sent or nil, nil end
		local write = enter and self:ResultText(sel) ~= nil
		list = {}
		if enter then list[#list + 1] = { "Enter", enter } end
		if back then list[#list + 1] = BACK_HINT end
		if shift then list[#list + 1] = { "Shift+Enter", shift } end
		if write then list[#list + 1] = { "Shift+Right", L["write it"] } end
		list[#list + 1] = KEYS_HINT
		for _, k in ipairs(SYNTAX_KEYS) do list[#list + 1] = k end
		key = key .. "|adv|" .. tostring(enter) .. "|" .. tostring(shift) .. "|" .. tostring(write)
	else
		-- what Enter and Shift+Enter do for the selected row, in words (Easy.VERBS)
		local enter, shift = ns.Easy.Verbs(UI.results[UI.sel])
		local sent = SendVerb(self, sel)
		if sent ~= nil then enter, shift = sent or nil, nil end
		list = {}
		if enter then list[#list + 1] = { "Enter", enter } end
		-- (before Shift+Enter: on a narrow footer, how to get back counts more; Shift+Left is the back key, Tab too for
		-- a category)
		if back then list[#list + 1] = BACK_HINT
		elseif self.category and not self.categoryAuto then list[#list + 1] = BACK_CATEGORIES
		elseif UI.results[UI.sel] and UI.results[UI.sel].catId then list[#list + 1] = EASY_TAB_PICK end
		if shift then list[#list + 1] = { "Shift+Enter", shift } end
		local r = UI.results[UI.sel]
		if r and not (r.catId or r.noActivate) then list[#list + 1] = { "Shift+Right", L["more"] } end -- (the row menu)
		list[#list + 1] = KEYS_HINT
		key = key .. "|" .. tostring(enter) .. "|" .. tostring(shift) .. "|" .. tostring(self.category) .. "|" .. tostring(UI.results[UI.sel] and UI.results[UI.sel].catId)
	end
	local room = (t.width or 640) - 28 - (status:GetStringWidth() or 0) - 24
	-- every render asks: measure again only when the room or the colours (or easy mode's verbs) changed
	if back then key = key .. "|back" end
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
	self.hintCount = #parts -- (tests)
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
	-- a row saying how far: the distance shown keeps up as you walk (only one that says it: a zone answer's
	-- distance is for its order, its detail says levels)
	local e = nav.e
	if r.distShown and nav.d then
		local shown = math.floor(nav.d + 0.5)
		if shown ~= nav.shownD then
			nav.shownD = shown
			local yd = ("%d yd"):format(shown) -- (the detail keeps "N yd", read back by FillRow; the column is translated)
			e.detail = yd .. ((r.distRest or "") ~= "" and ("  " .. r.distRest) or "")
			r.dist:SetText(L["%d yd"]:format(shown))
		end
	end
	-- where: the slot before the distance's column (the same place on every such row); else just left of the
	-- detail's text as shown (cut to the room it has: a long one is cut off, never wider)
	-- (measured when the row or its text changes, not every frame the arrow turns: review, 0.53.6)
	local w = 0
	if not r.distShown then
		local text, room = r.detail:GetText(), r.detail:GetWidth()
		if nav.wRow == r and nav.wText == text and nav.wRoom == room then
			w = nav.wDetail
		else
			w = r.detail:GetStringWidth()
			w = type(w) == "number" and w or 0
			if type(room) == "number" and room > 0 and w > room then w = room end
			nav.wRow, nav.wText, nav.wRoom, nav.wDetail = r, text, room, w
		end
	end
	local key = r.distShown and -1 or w
	if key ~= nav.w or nav.placedRow ~= r then
		nav.w, nav.placedRow = key, r
		navArrow:ClearAllPoints()
		if r.distShown then
			navArrow:SetPoint("RIGHT", r.dist, "LEFT", -1, 0)
		else
			navArrow:SetPoint("RIGHT", r.detail, "RIGHT", -(w + 4), 0)
		end
	end
	if not navArrow:IsShown() then navArrow:Show() end
end

--- The arrow follows the selection: shown on an NPC row with a known place on your continent.
function UI:UpdateNav()
	local frame = UI.frame
	local e = UI.results[UI.sel]
	local i = UI.sel - UI.offset
	local id = NavID(e)
	if not (id and frame and frame:IsShown() and not self.closing and i >= 1 and i <= LY.ROWS and ns.Integrations
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

-- An item row drawn before the game had that item (its quality: the colour, read as it's drawn) came out white, and
-- stayed so until it was drawn again (scrolled off and back; the player's screenshot of loot lists). Such an item is
-- asked for, and the rows on screen are drawn again once it comes: on its GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT,
-- and, as the server answers late while thousands of AtlasLoot items are asked for (0.51.7: an item given up on after
-- 10 s, and never asked for again that session, stayed white), looked at every UI.COLOR_POLL s while the terminal is
-- open; asked for again every UI.COLOR_REASK s, given up on after UI.COLOR_POLLS looks (drawn again: waited for anew).
UI.COLOR_POLL, UI.COLOR_POLLS, UI.COLOR_REASK = 1, 60, 5
local colorWait = { ids = {}, n = 0, asked = {}, queued = false, polling = false }
UI.colorWait = colorWait -- (tests)
local function ColorWaitDone()
	for k in pairs(colorWait.ids) do colorWait.ids[k] = nil end
	-- (when each was last asked for: let go with the wait, not kept for every item ever drawn; review, 0.51.25)
	for k in pairs(colorWait.asked) do colorWait.asked[k] = nil end
	colorWait.n = 0
	local f = colorWait.frame
	if f then
		pcall(f.UnregisterEvent, f, "GET_ITEM_INFO_RECEIVED")
		pcall(f.UnregisterEvent, f, "ITEM_DATA_LOAD_RESULT")
	end
end
local function RedrawSoon()
	if colorWait.queued then return end
	colorWait.queued = true
	C_Timer.After(0.1, function()
		colorWait.queued = false
		if UI:IsShown() then UI:Render() end
	end)
end
--- Whether the game has an item yet (no way to tell: as if it had).
local function ItemCached(id)
	local f = C_Item and C_Item.IsItemDataCachedByID
	if not f then return true end
	local ok, yes = pcall(f, id)
	return not ok or yes ~= false
end
local function Came(id)
	colorWait.ids[id] = nil
	colorWait.n = colorWait.n - 1
end
local function Poll()
	colorWait.polling = false
	if colorWait.n <= 0 then return ColorWaitDone() end
	local open, any = UI:IsShown(), false
	for id, looks in pairs(colorWait.ids) do
		if ItemCached(id) then Came(id); any = true
		elseif not open or looks >= UI.COLOR_POLLS then Came(id)
		else colorWait.ids[id] = looks + 1 end
	end
	if any then RedrawSoon() end
	if colorWait.n <= 0 then return ColorWaitDone() end
	colorWait.polling = true
	C_Timer.After(UI.COLOR_POLL, Poll)
end
local function AwaitItem(id)
	if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
	local now = GetTime()
	local last = colorWait.asked[id]
	if not last or now - last >= UI.COLOR_REASK then
		colorWait.asked[id] = now
		pcall(C_Item.RequestLoadItemDataByID, id)
	end
	if colorWait.ids[id] then return end
	colorWait.ids[id] = 0
	colorWait.n = colorWait.n + 1
	local f = colorWait.frame
	if not f then
		f = CreateFrame("Frame")
		colorWait.frame = f
		f:SetScript("OnEvent", function(_, _, itemID)
			itemID = tonumber(itemID)
			if not (itemID and colorWait.ids[itemID]) then return end
			Came(itemID)
			if colorWait.n <= 0 then ColorWaitDone() end
			RedrawSoon()
		end)
	end
	if colorWait.n == 1 then
		pcall(f.RegisterEvent, f, "GET_ITEM_INFO_RECEIVED")
		pcall(f.RegisterEvent, f, "ITEM_DATA_LOAD_RESULT")
	end
	if not colorWait.polling then
		colorWait.polling = true
		C_Timer.After(UI.COLOR_POLL, Poll)
	end
end

--- A row's text: its name with the matched letters, the icon, the detail (or what it's needed for), the kind.
--- A text's whole width, however much room it has.
local function Unbounded(fs)
	local f = fs.GetUnboundedStringWidth
	if f then
		local ok, w = pcall(f, fs)
		if ok and type(w) == "number" and w > 0 then return w end
	end
	local ok, w = pcall(fs.GetStringWidth, fs)
	return ok and type(w) == "number" and w or 0
end

--- The detail's room on this row (and the name's, which ends where it begins).
local function SetDetailW(r, w)
	if r.detailW == w then return end
	r.detailW = w
	r.detail:SetWidth(w)
	r.label:ClearAllPoints()
	r.label:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
	r.label:SetPoint("RIGHT", r.kind, "LEFT", -(16 + w), 0)
end

--- (0.62.1, the player at 800 wide: "a lot of space in the detail column"... details cut off beside short names) a
--- detail longer than its column takes the room the name doesn't use: the name keeps its own width, up to NAME_SHARE
--- of the row (cut there when both are long), the detail the rest.
UI.NAME_SHARE = 0.4
local function FitDetail(r)
	-- (measured when the row's texts or the layout change, not on every render; release review, 0.63.0)
	local name, detail = r.label:GetText(), r.detail:GetText()
	if r.fitName == name and r.fitDetail == detail and r.fitSpan == LY.SPAN and r.fitBase == LY.DETAIL_W and type(r.detailW) == "number" then return end
	r.fitName, r.fitDetail, r.fitSpan, r.fitBase = name, detail, LY.SPAN, LY.DETAIL_W
	local span, base = LY.SPAN, LY.DETAIL_W
	local w = base
	if span and span > base then
		local need = Unbounded(r.detail)
		if need > base then
			local name = math.min(Unbounded(r.label), math.floor(span * UI.NAME_SHARE))
			w = math.max(base, math.min(math.ceil(need) + 2, span - name - 8))
		end
	end
	SetDetailW(r, w)
end
UI.FitDetail = FitDetail -- (tests)

local function FillRow(self, r, e, light)
	r:Show()
	if e.raw then
		r.label:SetText(Theme.FixColors(e.name))
	else
		local base = e.color
		if base == nil then -- (an item the game hasn't sent yet: no colour to draw till it comes)
			local id = tonumber(e.itemID)
			if id and not ItemCached(id) then AwaitItem(id) end
		end
		if light and base == "|cffffffff" then base = nil end -- white item names vanish on light themes
		if e._pos == nil then e._pos = UI.Positions(e, self.posTokens) end -- only for rows on screen
		local text = Fuzzy.Colorize(e.name, e._pos, base)
		-- (a name only the game can show: a Battle.net friend's account name, an escape it draws as their name; never the
		-- row's name, which goes to chat and copies: Social.lua)
		local shown = rawget(e, "shownName")
		if shown then text = (base or "") .. shown .. (base and "|r" or "") end
		-- (a category row: which of its lists had matches, after its name: Search.lua's KindsNote)
		local note = rawget(e, "labelNote")
		if note then text = text .. "     " .. note end
		r.label:SetText(Theme.FixColors(text))
	end
	if e.icon == false then
		r.icon:Hide()
	else
		r.icon:Show()
		r.icon:SetTexture(e.icon or QUESTION_MARK)
		-- (a picture filling only part of its texture: a holiday's, Calendar.lua) cropped; the next row uncropped again
		local c = e.iconCoords
		if type(c) == "table" then
			r.icon:SetTexCoord(c[1], c[2], c[3], c[4])
			r.iconCropped = true
		elseif r.iconCropped then
			r.icon:SetTexCoord(0, 1, 0, 1)
			r.iconCropped = nil
		end
	end
	local from = self.linked and self.linked[e]
	local yd, rest
	if not from and rawget(e, "_dist") and type(e.detail) == "string" then yd, rest = e.detail:match("^(%d+ yd)%s*(.*)$") end
	if yd then
		-- how far, in its column after the arrow's slot; what it is after that: every such row lines up (0.45.18, the
		-- player's screenshot: the arrow sat wherever the text began, a different place on every row)
		r.distShown, r.distRest = true, rest
		r.dist:SetText(L["%d yd"]:format(tonumber(yd:match("%d+")) or 0)) -- (the detail says "N yd" in English: read here)
		r.dist:Show()
		-- (the distance's column lines up on every such row: the detail's room as it was; set once while it stays one)
		if r.detailW ~= "dist" then
			SetDetailW(r, LY.DETAIL_W)
			r.detail:SetWidth(math.max(1, LY.DETAIL_W - LY.NAV_SLOT - LY.DIST_W - 6))
			r.detailW = "dist"
		end
		r.detail:SetJustifyH("LEFT")
		r.detail:SetText(rest)
	else
		if r.distShown then
			r.distShown, r.distRest = nil, nil
			r.dist:Hide()
			r.detail:SetJustifyH("RIGHT")
		end
		if from and not e.raw then
			r.label:SetText(ARROW .. r.label:GetText())
			r.detail:SetText((self.linkedGuess and self.linkedGuess[e] and L["maybe needs %s"] or L["needs %s"]):format(from.name))
		else
			-- (sorted by AH value: what it brings, where it is, Auctionator.lua; quests for bags: which and its slots,
			-- Rewards.lua)
			local how = self.showField and not e.raw and ns.FIELD_DETAIL[self.showField]
			local d = how and how(e, self.showField)
			r.detail:SetText(d or e.detail or "")
		end
		FitDetail(r)
	end
	r.kind:SetText(Theme.FixColors(e.kindLabel or ""))
end

function UI:Render()
	local frame = UI.frame
	-- nothing to draw while it's closed (a setting changed in the options panel, say): drawing
	-- then put the rows up, and the next open showed them without their animation
	if not frame or not frame:IsShown() then return end
	local light = Theme.IsLight()
	-- rows come in with the style on every open (snapNext, on open, is for the height only);
	-- only a new layout (theme changes) puts them up at once
	local animated = self:Animated() and not (self.snapNext and not self.opening)
	local now, entering = GetTime(), 0
	for i = 1, MAX_ROWS do
		local r = rows[i]
		local idx = UI.offset + i
		local e = (i <= LY.ROWS) and UI.results[idx] or nil
		if e then
			entering = EnterRow(r, animated, now, entering)
			FillRow(self, r, e, light)
		elseif r:IsShown() and not r.leaving then
			-- no result for this row any more: it fades as the list shrinks over it
			if animated and i <= LY.ROWS then
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
-- (tabsH: the tabs' strip over the prompt, Tabs.lua; barH: Simple mode's bar under it, Bar.lua)
local function HeaderH() return LY.HEADER_H + (UI.promptExtra or 0) + (UI.tabsH or 0) + (UI.barH or 0) end

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
		row.baseY = -hh - (i - 1) * LY.ROW_H
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
	local n = math.max(0, math.min(LY.ROWS, #UI.results - UI.offset))
	-- nothing typed yet: just the prompt, no divider, no footer. Once something is typed the footer stays, in both
	-- modes, even when nothing was found (0.43.4: Simple mode hid it then, and the player lost what the keys do)
	local bare = #UI.results == 0 and self.mode == "search" and not self.sendTo
		and not (text or (edit and edit:GetText()) or ""):find("%S")
	if bare ~= (self.bare or false) then
		self.bare = bare
		divider:SetShown(not bare)
		footLine:SetShown(not bare)
		status:SetShown(not bare)
		if bare and self.footExtraOn then self:SetFooterExtra(nil) end
		self.hintsRoom = nil
		self:FitHints()
	end
	local h
	-- (the prompt's own background stops HeaderH - 4 down, inset by the border: the bare frame ends below it,
	-- or the background covered the bottom border)
	if bare then h = HeaderH() - 4 + (Theme.Get().frame == "classic" and 4 or 1)
	else h = HeaderH() + n * LY.ROW_H + (self.footerH or FOOTER_H) end
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
	if not e or e.noActivate or i < 1 or i > LY.ROWS then
		selBar:Hide(); selEdge:Hide()
		return
	end
	self.selTo = -HeaderH() - (i - 1) * LY.ROW_H
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
	-- (every frame of a glide: only the bar moves; its height when the theme's rows change, the edge anchored to it once.
	-- Review, 0.53.6)
	if selBar.h ~= LY.ROW_H then selBar.h = LY.ROW_H; selBar:SetHeight(LY.ROW_H) end
	if not selEdge.anchored then
		selEdge.anchored = true
		selEdge:ClearAllPoints()
		selEdge:SetPoint("TOPLEFT", selBar, "TOPLEFT", 0, 0)
		selEdge:SetPoint("BOTTOMLEFT", selBar, "BOTTOMLEFT", 0, 0)
	end
end
