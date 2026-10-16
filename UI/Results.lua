local ns = select(2, ...)
local L = ns.L

-- What's listed and selected: a search run a slice of a frame at a time, ">>>" collapsing the list into one row, the
-- pick lists of "@" and "key:", the selection moving and scrolling, Up/Down through the history and back to the last
-- search, Simple mode's categories. Split out of UI.lua.

local UI = ns.UI
local LY = UI.layout
local EasyOn, SLICE_MS, Forget = UI.EasyOn, UI.SLICE_MS, UI.Forget

--- A search spread over frames: up to SLICE_MS of it now. Gives the results to show, and
--- whether they're final; if not, the best matches found so far (sorted once, on a copy) show
--- now and the search goes on quietly in the next frames (see ContinueSearch).
function UI:RunSearch(text)
	self.searchJob = nil
	if not (debugprofilestop and coroutine) then return self:Search(text), true end
	local job = { co = coroutine.create(function() return self:Search(text) end), ms = 0 }
	job.step = function() self:ContinueSearch(job) end
	local res, done = self:StepSearch(job)
	if done then return res, true end
	-- not finished: the best of what matched so far (on a copy: the search goes on filling it),
	-- under the calculator's answer when there is one (Search adds it only at the end)
	local t0 = debugprofilestop()
	local copy = UI.SortAndTrim(res) -- (a new list: the search goes on filling res)
	-- ("| sum value": what's found so far, summed up; the whole list once the search is done)
	local agg = self.aggregate
	if agg and ns.Aggregate then copy = ns.Aggregate.Apply(agg, res, agg.base) end
	local calc = not self.fzf and ns.Calc and ns.Calc.Entry(text)
	if calc then table.insert(copy, 1, calc) end
	job.ms = job.ms + (debugprofilestop() - t0)
	return copy, false
end

function UI:StepSearch(job)
	local t0 = debugprofilestop()
	self.sliceUntil = t0 + SLICE_MS
	local ok, res = coroutine.resume(job.co)
	self.sliceUntil = nil
	job.ms = job.ms + (debugprofilestop() - t0)
	job.slices = (job.slices or 0) + 1
	if not ok then
		self.searchJob = nil
		ns:Print(L["Search error: %s"]:format(tostring(res)))
		return {}, true
	end
	if coroutine.status(job.co) == "dead" then
		self.searchJob = nil
		return res or {}, true
	end
	self.searchJob = job
	return res, false -- the matches so far (still being filled)
end

--- ">>> party": the list collapses into one row saying how many go where ("Send all 12 to party"); the rows themselves
--- are kept in `UI.groupList` for sending (Activate, the footer, Share.Prefetch), and the ones that go, grouped once,
--- in `UI.groupRows` (UI:GroupedRows). Any other search: the list as it is.
function UI:CollapseGroup(list)
	local to, SH = self.sendTo, ns.Share
	if not (to and to.all and SH) then self.groupList, self.groupRows = nil, nil return list end
	self.groupList = list
	if not SH.Searched(to.query) then
		-- (">>> party" alone: what's listed is your recent picks, nothing that says what they are; never sent)
		self.groupRows = {}
		return { { kind = "send", kindLabel = "|cff33ff99" .. L["chat"] .. "|r", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", raw = true,
			sendAll = true, noActivate = true, _pos = UI.NO_POS, _score = 0, name = L["Nothing searched to send"],
			detail = L["search first, then >>> %s"]:format(to.drop and "drop" or "party") } }
	end
	if to.copy then
		-- ">>> text", ">>> csv": every result, to copy (Activate opens them in a box)
		local rows = {}
		-- (a summed-up list's rows all go, totals too: "| group zone >>> csv")
		for _, e in ipairs(list) do if not e.noActivate or e.kind == "aggregate" then rows[#rows + 1] = e end end
		self.groupRows = rows
		local n = #rows
		local row = { kind = "send", kindLabel = "|cff33ff99" .. L["copy"] .. "|r", icon = "Interface\\Icons\\INV_Misc_Note_01", raw = true,
			sendAll = true, _pos = UI.NO_POS, _score = 0, actionVerb = L["copy as %s"]:format(to.label),
			detail = L["Enter opens them in a box to copy (Ctrl+C)"] }
		if n == 0 then
			row.name, row.noActivate, row.detail = L["Nothing to copy"], true, ""
		else
			row.name = (n == 1 and L["Copy the %d as %s"] or L["Copy all %d as %s"]):format(n, to.label)
		end
		return { row }
	end
	if to.drop and ns.QuestDrop then
		-- ">>> drop": the quests in your log among them (complete ones kept), dropped after Terminal's confirmation
		local rows, kept = ns.QuestDrop.GroupRows(list, true)
		self.groupRows = rows
		local n = #rows
		local row = { kind = "dropall", kindLabel = "|cffffd200" .. L["quests"] .. "|r", icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
			raw = true, sendAll = true, _pos = UI.NO_POS, _score = 0, actionVerb = L["drop them all"] }
		if n == 0 then
			row.name, row.noActivate = L["Nothing to drop"], true
			row.detail = kept > 0 and L["the quests listed are complete: turn them in"] or L["no quest in your log among the results"]
		else
			row.name = (n == 1 and L["Drop the %d quest"] or L["Drop all %d quests"]):format(n)
			row.detail = (kept > 0 and (L["%s complete kept"]:format(kept) .. "  ·  ") or "") .. L["you'll see them all and be asked first"]
		end
		return { row }
	end
	local group = SH.GroupRows(list)
	self.groupRows = group
	local n = #group
	-- (what the rows are, as the chat line will say it: no row's text worked out, so no NPC's map pin is set here)
	local what = n > 0 and SH.GroupHeader(group, to.query) or nil
	local row = { kind = "send", kindLabel = "|cff33ff99" .. L["chat"] .. "|r", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", raw = true,
		sendAll = true, _pos = UI.NO_POS, _score = 0, detail = what or "" }
	if n == 0 then
		row.name, row.noActivate, row.detail = L["Nothing to send"], true, ""
	elseif to.cmd and SH.Restricted(to) then
		-- (say, yell: the game presses one line, as many as fit, the rest counted: SH.PressLine)
		row.name = L["Send %d to %s in one line"]:format(n, to.label)
	elseif to.cmd then
		row.name = (n == 1 and L["Send the %d to %s"] or L["Send all %d to %s"]):format(n, to.label)
	else
		row.name = L["%d to send"]:format(n)
		row.detail = to.bad and L["no channel called %s"]:format(to.bad) or L["say where: party, guild, raid, say, whisper <name>"]
	end
	return { row }
end

--- The rows ">>>" sends, for the footer and Share.Prefetch (asked on every status update): the ones CollapseGroup
--- grouped for the list kept, else the shown rows grouped now.
function UI:GroupedRows()
	if self.groupList and self.groupRows then return self.groupRows end
	return ns.Share.GroupRows(self.groupList or UI.results)
end

--- The same row, or the same row made again (kind, key and name).
local function SameRow(e, keep) return e == keep or (e.kind == keep.kind and e.name == keep.name and e.key == keep.key) end

--- Rows put up in place of the shown ones, the selected row kept selected where it was on screen (if it's there).
local function PutUp(list)
	local keep = (UI.sel > 1 or UI.offset > 0) and UI.results[UI.sel] or nil
	local keptRow = UI.sel - UI.offset
	UI.results = list
	UI.sel, UI.offset = 1, 0
	if keep then
		for i, e in ipairs(UI.results) do
			if SameRow(e, keep) then
				UI.sel = i
				UI.offset = math.max(0, math.min(i - keptRow, #UI.results - LY.ROWS))
				break
			end
		end
	end
end

-- A search run again because item data came in (UI:RetryWhenLoaded) runs in the background: the list shown stays as
-- it is, and what it found waits (UI.held) for F5 (UI.UPDATE_KEY), the footer saying so; unless nothing was shown but
-- "keep typing" lines (0.51.8, the player: "just generate a result list and stick with it; let the updating happen in
-- the background or on a key press rather than while I am searching").
UI.UPDATE_KEY = "F5"
local function Real(list)
	for i = 1, #list do if not list[i].noActivate then return true end end
	return false
end
-- What a search sets beside its rows, read with the rows shown (the footer, Enter, >>> sending): a background search
-- whose rows are held mustn't change them under the shown list (review, 0.51.25: ">>> party" sent the new rows while the
-- list said the old ones; Simple mode's category label changed with the list staying)
local LIST_FIELDS = { "sendTo", "groupList", "groupRows", "blockedSyntax", "blockedCopy", "aggregate", "linked", "answerNote", "pipeTrail",
	"flightNote", "missingNote", "overviewWinner", "category", "categoryAuto", "softRelaxed" }
local NONE = {}
local function Fields(self)
	local t = {}
	for _, k in ipairs(LIST_FIELDS) do local v = self[k] if v == nil then t[k] = NONE else t[k] = v end end
	return t
end
local function SetFields(self, t)
	if not t then return end
	for _, k in ipairs(LIST_FIELDS) do local v = t[k] if v == NONE then self[k] = nil else self[k] = v end end
end
--- A background search's rows: "held" for F5 (the shown list and what it was searched with kept), "same" (the same
--- rows: put up in their place, nothing moving, so a stack's count is the new one; review, 0.51.25), or nil: nothing
--- real was shown, so they're shown.
--- What the list on screen was searched with: kept whenever rows are put up (UI.shownFields), so a background search's
--- held rows give back the shown list's, whichever search ran in between (review, 0.51.25: a background search started
--- again, or F5 pressed while one ran, gave back another's).
local function Shown(self) self.shownFields = Fields(self) end
local function Equal(a, b)
	if not a or not b or #a ~= #b then return false end
	for i = 1, #a do if not SameRow(a[i], b[i]) then return false end end
	return true
end
-- F5 only for a list that's sure (0.52.9, the player: after a /reload "upgrades" jumped between result sets, F5 coming
-- and going while item data came in: "if an F5 result appears it should be because we definitely have a new stable
-- set"): a background search's rows unlike what's shown are a candidate; the same search again UI.CONFIRM_S s later
-- (or the next one data coming in starts) finding the same rows confirms them, and only then is F5 offered. Likewise
-- an offered list is taken back only once the shown one is found again twice. At most UI.CONFIRM_TRIES checks a search.
UI.CONFIRM_S, UI.CONFIRM_TRIES = 1.5, 6
local confirm = { gen = 0, tries = 0 }
local function Confirm(self)
	confirm.tries = confirm.tries + 1
	if confirm.tries > UI.CONFIRM_TRIES then return end
	local gen = confirm.gen
	C_Timer.After(UI.CONFIRM_S, function()
		if gen ~= confirm.gen or not self.candidate or not self:IsShown() or self.searchJob then return end
		self:QuietRedo()
	end)
end
local function Hold(self, shown, new)
	if not Real(shown) then self.candidate = nil return nil end
	local confirmed = self.candidate ~= nil and Equal(self.candidate, new)
	self.candidate = nil
	if Equal(shown, new) then
		-- (what's shown found again: an F5 offered goes only when that's sure too)
		if self.held and not confirmed then self.candidate = new; Confirm(self)
		else self.held, self.heldFields = nil, nil end
		Shown(self)
		self:SetStatus()
		return "same"
	end
	if not (self.held and Equal(self.held, new)) then -- (offered already: as it was)
		if confirmed then
			self.held, self.heldFields = new, Fields(self)
		else
			self.candidate = new -- (not offered yet: once it's found again)
			Confirm(self)
		end
	end
	SetFields(self, self.shownFields)
	self:SetStatus()
	return "held"
end

-- A category stepped into from the list of categories, listing another number than its row counted (0.51.11, the
-- player: "Dungeon loot" said 100+ upgrades and listed a steady 52, item data having come in meanwhile): the footer
-- says the list was updated as you stepped in, for UI.COUNT_NOTE_S s.
UI.COUNT_NOTE_S = 6
function UI:NoteCountChange()
	local want = self.expectCount
	if not want or self.searchJob then return end
	self.expectCount = nil
	if want.cat ~= self.category then return end
	local n = 0
	for _, e in ipairs(UI.results) do if not e.noActivate and not e.lead then n = n + 1 end end
	if n == want.n or n >= ns.Score.LIST_MAX then return end
	local note = { text = L["updated as you stepped in: %d counted a moment ago"]:format(want.n) }
	self.countNote = note
	C_Timer.After(UI.COUNT_NOTE_S, function()
		if self.countNote == note then self.countNote = nil; self:SetStatus() end
	end)
end

-- A list changes while its rows are shown (bags while you loot, the loot log, mail; 0.51.12): searched again in the
-- background UI.LIVE_WAIT s after the last change, what it finds held for F5 as data coming in is (Hold); shown at
-- once only when nothing real was. A list that keeps changing as it's read (its own events) is searched again at
-- most UI.LIVE_SAME times in a row while nothing new comes of it.
UI.LIVE_WAIT, UI.LIVE_SAME, UI.LIVE_FRESH = 1, 3, 10
local live = { kinds = {}, timer = false, same = 0 }
UI.live = live -- (tests)

--- The same search run again in the background (Refresh's quiet path): data came in, a list changed.
function UI:QuietRedo()
	if not self:IsShown() or self.mode ~= "search" then return end
	self.lastScan, self.lastOverview = nil, nil
	self.refreshedAt, self.searchedText = nil, nil
	self.quietRedo = true
	self:Refresh()
end

local function SameRows(a, b)
	if not a or not b or #a ~= #b then return false end
	for i = 1, #a do if not SameRow(a[i], b[i]) then return false end end
	return true
end
--- A background search for a changed list done: nothing new (nothing held, or what was held already) counts toward
--- UI.LIVE_SAME.
function UI.LiveCounted(shownNew)
	local before = live.before
	if before == nil then return end
	live.before = nil
	if shownNew then return end -- (nothing real was shown: what it found is up, not "nothing new")
	if not UI.held or SameRows(UI.held, before or nil) then live.same = live.same + 1 else live.same = 0 end
end

local function ShowsKind(kinds)
	if not Real(UI.results) then return UI.edit and UI.edit:GetText() ~= "" end -- (nothing found yet: any list may have it now)
	for _, e in ipairs(UI.results) do
		local k = e.kind
		if k == "category" or (k and kinds[k]) then return true end
	end
	return false
end

function ns.OnDirty(p)
	if not (UI.IsShown and UI:IsShown()) or UI.mode ~= "search" then return end
	live.kinds[p.id] = true
	live.at = GetTime()
	-- (a change a while after the last search again is a new one, not the list changing as it's read: counted afresh;
	-- review, 0.51.25: three unrelated changes stopped them for good)
	-- (UI.LIVE_FRESH s: longer than a server's answer to the read itself, which would start it over and over)
	if live.redoneAt and live.at - live.redoneAt > UI.LIVE_FRESH then live.same = 0 end
	if live.timer then return end
	live.timer = true
	local function Fire()
		local quiet = UI.LIVE_WAIT - (GetTime() - live.at)
		if quiet > 0.05 then C_Timer.After(quiet, Fire) return end -- (changed again meanwhile: once it settles)
		live.timer = false
		local kinds = live.kinds
		live.kinds = {}
		if not UI:IsShown() or UI.searchJob or not ShowsKind(kinds) then return end
		if live.same >= UI.LIVE_SAME then return end
		live.before = UI.held or false
		live.redoneAt = GetTime()
		UI.shownNew = nil
		UI:QuietRedo()
		if not UI.searchJob then UI.LiveCounted(UI.shownNew) end -- (else once it's done: Completed)
	end
	C_Timer.After(UI.LIVE_WAIT, Fire)
end

--- F5: the results a background search held put up (nothing held: nothing changes).
function UI:ShowNewResults()
	local held, fields = self.held, self.heldFields
	self.held, self.heldFields, self.candidate = nil, nil, nil
	if not held then return end -- (nothing new: the list stays as it is)
	SetFields(self, fields)
	PutUp(held)
	Shown(self)
	self:SelectPopTarget(true)
	self:SetStatus()
	self:Render()
end

-- a search done: its full results replace the early ones; the selected result stays selected if it's still there,
-- and the list stays where you scrolled it
-- (the same row made again counts: kind, key and name, as Refresh has it; 0.51.7: a category row, made anew by every
-- search, lost the selection to the top row whenever item data came in)
local function Completed(self, job, final)
	final = self:CollapseGroup(final)
	if job.quiet then -- (run in the background: held for F5)
		local h = Hold(self, UI.results, final)
		UI.LiveCounted(h == nil)
		if h == "held" then self:UpdateBusy() return end
		if h == "same" then
			UI.results = final -- (the same rows in the same places: the selection and scroll stay)
			self:UpdateBusy()
			self:Render()
			return
		end
	end
	PutUp(final)
	Shown(self)
	self.lastSearchMs, self.lastSearchCount, self.lastSearchSlices = job.ms, #UI.results, job.slices
	self:SelectPopTarget(true)
	self:NoteCountChange()
	if ns.Tour then ns.Tour.Arrived() end -- (.tour: the row its step is about selected)
	self:UpdateBusy()
	self:Render()
end

--- The next frame's share of the search. Once done, the full results replace the early ones.
function UI:ContinueSearch(job)
	if self.searchJob ~= job then return end -- typed again, or closed: this search is stale
	-- (armed, it goes on: Enter presses the armed entry whatever the list shows; dropped, the list stayed at its first
	-- slice for good, review 0.48.6)
	if not self:IsShown() or self.closing then self.searchJob = nil return end
	local final, done = self:StepSearch(job)
	if not done then
		C_Timer.After(0, job.step) -- (one closure per search, not one per frame)
		return
	end
	Completed(self, job, final)
end

UI.FINISH_MS, UI.SEND_FINISH_MS = 12, 40
--- A search still going over frames, finished now if it takes no more than `budget` ms (with none: however long it
--- takes), its results put up as when it ends by itself: what reads the results (Alt+`, sending every result) then
--- reads all of them, not the first frame's best. Whether no search is left going (past the budget it goes on as it
--- was, in the next frames).
function UI:FinishSearch(budget)
	local job = self.searchJob
	if not job then return true end
	local t0 = debugprofilestop and debugprofilestop()
	repeat
		local final, done = self:StepSearch(job)
		if done then Completed(self, job, final) return true end
	until budget and t0 and debugprofilestop() - t0 >= budget
	return false
end

--- Advanced mode, the last word being typed is "@..." or "key:...": the kinds or the filter's values that fit it, as
--- rows to pick from (Enter/click writes it with a space after it; Tab / Shift+Tab move the selection round), or nil.
function UI:SyntaxRows(text)
	-- (typed with the caret at the end; not a text set by code: Open("@item") lists the items)
	if EasyOn() or self.fzf or self.opening or (self.cursor or #text) < #text then return nil end
	-- (a line Up brought back from the history runs as it is: "@npc is:repair sort:nearest" isn't a pick list)
	if self._histSet or (self.histIdx and text == self.histText) then return nil end
	local last = text:match("(%S+)$")
	if not last then return nil end
	local before = text:sub(1, #text - #last)
	local picks = {}
	local function Row(word, detail, kindLabel)
		picks[#picks + 1] = { name = word, detail = detail or "", kindLabel = kindLabel or "", icon = false, raw = true,
			completion = before .. word .. " ", staysOpen = true, activate = UI.HintActivate, syntaxRow = true, _pos = UI.NO_POS,
			_score = 0 }
	end
	if last:sub(1, 1) == "@" then
		local want = ns.Lower(last:sub(2))
		for _, id in ipairs(ns.providerOrder) do
			local p = ns.providers[id]
			-- (its name, as .kinds, Shift+Right and Alt+` write it: its first alias, else its id, else an alias the
			-- typed letters start; a list no @ names isn't offered)
			local main = (p.aliases and p.aliases[1]) or id
			local word
			if p.noKind then word = nil
			elseif ns.Lower(main):sub(1, #want) == want then word = main
			elseif id:sub(1, #want) == want then word = id
			else
				for _, a in ipairs(p.aliases or {}) do
					if type(a) == "string" and ns.Lower(a):sub(1, #want) == want then word = a break end
				end
			end
			if word then
				local label = p.label or id
				Row("@" .. word, (p.aliases and #p.aliases > 0) and ("@" .. table.concat(p.aliases, " @")) or "",
					"|c" .. (p.color or "ff7fb2ff") .. label .. "|r")
				-- (a kind whose word the other's starts with goes before it: @loot before @lootlog, whichever
				-- registered first; AtlasLoot's list comes late)
				local r = table.remove(picks)
				local at = #picks + 1
				for j = 1, #picks do
					local w = picks[j].name
					if #w > #r.name and w:sub(1, #r.name) == r.name then at = j break end
				end
				table.insert(picks, at, r)
			end
		end
	else
		local key, val = last:match("^(%a+):(%S*)$")
		-- (only the values that judge a list typed: "@questlog is:" isn't offered online or equippable)
		local values = key and ns.Filters and (ns.Filters.ValuesFor and ns.Filters.ValuesFor(key, before)
			or ns.Filters.VALUES[ns.Lower(key)])
		if not values then return nil end
		val = ns.Lower(val)
		for _, v in ipairs(values) do
			if v:sub(1, #val) == val then Row(key .. ":" .. v, "", L["filter"]) end
		end
	end
	if #picks == 0 then return nil end
	return picks
end

--- The selection moved: the list scrolls to keep it on screen (every row redrawn), else only the selection is.
local function FollowSelection(self)
	local was = UI.offset
	if UI.sel <= UI.offset then UI.offset = UI.sel - 1 end
	if UI.sel > UI.offset + LY.ROWS then UI.offset = UI.sel - LY.ROWS end
	if UI.offset ~= was then self:Render() else self:SelectionChanged() end
end

--- The pick list ("@", "q:"...): Tab / Shift+Tab move its selection down / up, round from the end to the start.
function UI:StepSyntax(dir)
	if not (UI.results[1] and UI.results[1].syntaxRow) then return false end
	local n = #UI.results
	UI.sel = ((UI.sel - 1 + dir) % n) + 1
	FollowSelection(self)
	return true
end

--- ">>" in the prompt: the search is the part before it. Simple mode: nothing is sent (a row says it's Advanced
--- mode's); Advanced: where Enter sends the selected result, or every result with ">>>" (UI.sendTo). Gives the text
--- to search.
local function TakeSendTo(self, text, first)
	-- "copper bar >> party": the search is before the ">>"; Enter sends the selected result there (Share.lua)
	self.sendTo, self.groupList, self.groupRows = nil, nil, nil
	self.blockedSyntax = nil
	if self.fzf then
		-- (nothing to take off)
	elseif first ~= "." and first ~= "/" and ns.Share and EasyOn() then
		-- Simple mode: no ">>" (the words before it are searched and a row says it's Advanced mode's, ">> csv" too); to
		-- copy, plain words at the end: "linen to csv", "linen as text" (every result; 0.52.12, the player's call)
		local query, rest = ns.Share.Split(text)
		if rest then
			local to = ns.Share.Channel(rest)
			query = query:gsub("%s+$", "")
			self.blockedSyntax = to.copy and query ~= "" and "copy" or "send"
			self.blockedCopy = to.copy and query .. " to " .. to.copy or nil
			text = query
		else
			local q, how = ns.Share.PlainCopy(text)
			if q then
				local to = ns.Share.Channel(how)
				to.query, to.all = q, true
				self.sendTo = to
				text = q
			end
		end
	elseif first ~= "." and first ~= "/" and ns.Share then
		local query, rest, all = ns.Share.Split(text)
		if rest then
			self.sendTo = ns.Share.Channel(rest)
			self.sendTo.query = query -- (what was searched: the chat line says what the result is, Share.Context)
			self.sendTo.all = all -- (">>> party": every result at once, Share.SendAll)
			text = query:gsub("%s+$", "")
		end
	end
	return text
end

--- Advanced mode's "| sum value", "| group zone" (0.52.13): the steps after a "|" standing alone, read into UI.aggregate
--- (the search sums its results up: Pipes.lua's ns.Aggregate); gives the text to search. Simple mode: a "|" is
--- Advanced mode's (Easy.IsAdvancedWord).
local function TakeAggregate(self, text, first)
	self.aggregate = nil
	local A = ns.Aggregate
	if self.fzf or first == "." or first == "/" or not A or EasyOn() then return text end
	local query, steps = A.Split(text)
	if not steps then return text end
	self.aggregate = A.Parse(steps, query)
	return query
end

--- The rows for what's typed: commands, slash commands, a pick list ("@", "key:") or a search (its first slice
--- when it goes on in the next frames).
local function ListFor(self, text, first, edit)
	if first == "." then
		self.mode = "cmd"
		UI.results = self:ArgEntries(text:sub(2)) or self:ExactCommandFirst(self:WordSearch(self:CommandEntries(), text:sub(2)), text:sub(2))
	elseif first == "/" then
		self.mode = "slash"
		local p = ns.providers.slash
		UI.results = p and self:WordSearch(ns:GetEntries(p), text) or {}
	else
		local picked = self:SyntaxRows(edit:GetText())
		if picked then
			UI.results = picked -- (typing "@" or "stat:": what fits, to pick from)
			-- (the search before it said things in the footer: not about this list; 0.50.7, review: "no exact match: close
			-- spellings" and "Use ·" stayed on after " q:")
			local Scan = UI._Scan
			if Scan and Scan.ResetFlags then Scan.ResetFlags(self) end
			self.action, self.noPosition = nil, nil
		else
			local done
			UI.results, done = self:RunSearch(text)
			UI.results = self:CollapseGroup(UI.results)
			if not done then
				C_Timer.After(0, self.searchJob.step)
			end
		end
	end
end

function UI:Refresh()
	local frame, edit = UI.frame, UI.edit
	if not frame then return end
	-- typed faster than a frame: one search for the whole burst, on the next frame
	local now = GetTime()
	if self.refreshedAt == now then
		if not self.refreshQueued then
			self.refreshQueued = true
			C_Timer.After(0, function()
				self.refreshQueued = false
				self.refreshedAt = nil
				if self:IsShown() then self:Refresh() end
			end)
		end
		return
	end
	self.refreshedAt = now
	self.refreshCount = (self.refreshCount or 0) + 1
	if edit:GetText() ~= "" then self.showRecent = nil end -- (Down's recent picks last until you type)
	if self.searchJob then ns:Trace("search: started again before the last one finished (" .. (self.searchJob.slices or 0) .. " frames in)") end
	-- (a search of yours still going: one asked for in the background now runs as yours, its first frame's best not held
	-- behind F5 as if it were the list; review, 0.51.25)
	local yours = self.searchJob and not self.searchJob.quiet
	self.searchJob = nil -- a search still going on is for the old text
	self.searchedText = edit:GetText()
	-- the same text searched again (a list finished loading, item data came in): the row selected stays selected, and
	-- what was armed stays armed (review, 0.48.6: the selection jumped back to the first row every 1.1 s while data loaded)
	local same = self.refreshText == self.searchedText
	local keep = same and (UI.sel > 1 or UI.offset > 0) and UI.results[UI.sel] or nil
	local keptRow = UI.sel - UI.offset
	self.refreshText = self.searchedText
	local t0 = debugprofilestop and debugprofilestop()
	if self.armedEntry and not same then self:Disarm() end -- the query changed: whatever was armed is stale
	-- (a press finishing (FinishSoon) is kept through the same text searched again: the data retry, the spinner's
	-- refresh, a queued one; 0.49.2, review: it was dropped, and the terminal stayed over the window it opened)
	if not same then self.pendingAfter = nil end
	self.args = nil
	self.mode = "search"
	local text = edit:GetText():gsub("^%s+", "")
	local first = text:sub(1, 1)
	if self.fzf then first = "" end -- (pure fuzzy finding: every line is a search, nothing in it is syntax)
	text = TakeSendTo(self, text, first)
	text = TakeAggregate(self, text, first)
	-- searched again because item data came in (RetryWhenLoaded): the list shown stays as it is till the search is done,
	-- not its first frame's best put up meanwhile (0.51.7, the player: "upgrades" jumped about and back to the top
	-- every couple of seconds while the items loaded)
	local quiet = same and self.quietRedo and not yours
	self.quietRedo = nil
	if not quiet then
		self.held, self.heldFields, self.candidate, live.same = nil, nil, nil, 0
		confirm.gen, confirm.tries = confirm.gen + 1, 0 -- (checks of the last search's candidate: not this one's)
	end -- (a search of its own: whatever a background one held is stale)
	if not same then self.countNote, self.expectCount = nil, nil end -- (typed on: the note was about another list)
	local shown = UI.results
	ListFor(self, text, first, edit)
	-- (the same text searched again otherwise, a category picked: the list shown stays till the search is done, not its
	-- first frame's best put up meanwhile)
	if same and not quiet and self.searchJob and Real(shown) then UI.results = shown end
	if quiet then
		if self.searchJob then
			self.searchJob.quiet = true -- (Completed holds what it finds)
			UI.results = shown
		else
			local h = Hold(self, shown, UI.results)
			UI.shownNew = h == nil -- (nothing real was shown: put up, not counted as nothing new)
			if h == "held" then UI.results = shown end
			if h then
				self:UpdateBusy()
				self:Render()
				return
			end
		end
	end
	if t0 then self.lastSearchMs = debugprofilestop() - t0 end
	self.lastSearchCount = #UI.results
	self.lastSearchSlices = 1
	self:UpdateBusy()
	UI.sel, UI.offset = 1, 0
	if keep then
		local found
		for i, e in ipairs(UI.results) do
			if SameRow(e, keep) then found = i break end
		end
		if found then
			UI.sel, UI.offset = found, math.max(0, math.min(found - keptRow, #UI.results - LY.ROWS))
		elseif not self.popTarget then
			self.popTarget = keep -- (not in the first slice: once the search ends, SelectPopTarget)
		end
	end
	if not (quiet and self.searchJob) then Shown(self) end -- (a background search going on: the old list is up)
	self:SelectPopTarget(not self.searchJob)
	self:NoteCountChange()
	if ns.Tour then ns.Tour.Arrived() end -- (.tour: the row its step is about selected)
	self:Render()
end

----------------------------------------------------------------------
-- Back (0.45.16, the player: from a recipe's sources there was no easy way back to the recipes you don't know): a row
-- whose Enter writes a new search (a recipe -> "where to learn it", a chain's next step, Shift+Right's "write it") keeps
-- the search it left; Shift+Left (0.45.17: the one key for going back, wherever the cursor is) goes back to it while
-- its text is untouched, the row picked selected again (Keys.lua).
----------------------------------------------------------------------
UI.walks = {}
UI.WALKS_MAX = 10

--- Writes `text` as the new search, keeping the one it leaves (and the row it was left from: `pick`, else the
--- selected one) to go back to.
function UI:WalkTo(text, pick)
	local from = UI.edit:GetText()
	if from ~= text then
		local w = self.walks
		if #w >= UI.WALKS_MAX then table.remove(w, 1) end
		w[#w + 1] = { from = from, to = text, pick = pick or UI.results[UI.sel],
			category = (not self.categoryAuto) and self.category or nil }
	end
	self:SetQuery(text, #text)
end

--- The step Shift+Left would go back from: only while the prompt still says what that step wrote (anything else typed
--- since: the trail is gone).
function UI:WalkTop()
	local w = self.walks
	local top = w[#w]
	if not top then return nil end
	if UI.edit and UI.edit:GetText() == top.to then return top end
	self.walks = {}
	return nil
end

--- Back to the search a step left, the row it was left from selected. False: no step to go back from.
function UI:WalkBack()
	local top = self:WalkTop()
	if not top then return false end
	table.remove(self.walks)
	self.popTarget = top.pick -- (selected again once the results are in: SelectPopTarget)
	self.category, self.categoryAuto = top.category, nil
	ns:Trace(("back: %q -> %q"):format(top.to, top.from))
	self:SetQuery(top.from, #top.from)
	return true
end

--- Shift+Left: back one step: the search a step left (WalkBack), else in Simple mode from a category you picked to all
--- of them. False: nothing to go back to (Shift+Left selects then).
function UI:GoBack()
	if self.fzf then return false end
	if self:WalkBack() then return true end
	if self:HistoryBack() then return true end
	if EasyOn() and self.category and not self.categoryAuto and UI.mode == "search" then
		self:SetCategory(nil)
		return true
	end
	return false
end

--- Is there somewhere Shift+Left goes back to (the footer says so)?
function UI:CanGoBack()
	if self.fzf then return false end
	return self:WalkTop() ~= nil or self:HistoryBack(true)
		or (EasyOn() and self.category ~= nil and not self.categoryAuto and UI.mode == "search")
end

function UI:Move(delta)
	local n = #UI.results
	if n == 0 then return end
	if self.armedEntry then self:Disarm() end
	UI.sel = math.max(1, math.min(n, UI.sel + delta))
	FollowSelection(self)
end

--- Walk back (dir -1) or forward (dir 1) through the lines run before. Only from an empty
--- prompt, or while already walking: typing anything ends it.
function UI:History(dir)
	local h = ns.HistoryLines and ns:HistoryLines() or (ns.db and ns.db.history)
	if type(h) ~= "table" or #h == 0 then return false end
	local idx = self.histIdx
	if dir < 0 then
		idx = math.min(#h, (idx or 0) + 1)
	else
		idx = (idx or 0) - 1
	end
	local text = idx >= 1 and h[idx] or ""
	-- the game may report this change a frame later: the walk goes on while the text is the one it set
	self.histText = text
	self._histSet = true
	self:SetQuery(text, #text)
	self._histSet = false
	self.histIdx = idx >= 1 and idx or nil
	return true
end

--- A line Up brought back is in the prompt as it brought it. (A category picked in it since, in Simple mode, is a later
--- step: Up and Shift+Left are the category's then, as on any search.)
local function Walking(self)
	return self.histIdx ~= nil and not self.fzf
		and not (EasyOn() and self.category and not self.categoryAuto and UI.mode == "search")
end

--- Shift+Left on a line Up brought back: a step toward the newest line, the last step to the empty prompt (`dry`: only
--- whether it would). False: not walking the history.
function UI:HistoryBack(dry)
	if not Walking(self) then return false end
	if dry then return true end
	return self:History(1)
end

--- Up: the list's selection goes up; from the first row of an empty prompt, or of a line it brought back, it goes
--- back through the history instead (0.48.3, the player: Down then goes into that line's results, as on any search).
function UI:Up()
	local edit = UI.edit
	if self.fzf then return self:Move(-1) end -- (pure fuzzy finding: the arrows only go through the list)
	-- what Down brought up (your recent picks; Simple mode: the last search), Up on its first row puts away
	if UI.sel <= 1 and not self.histIdx then
		local text = edit:GetText()
		if self.showRecent and text == "" then
			self.showRecent = nil
			self:Research()
			return
		end
		if self.recalled and text == self.recalled then
			self.recalled = nil
			self:SetQuery("", 0)
			return
		end
	end
	if UI.sel <= 1 and (Walking(self) or edit:GetText() == "") and self:History(-1) then return end
	self:Move(-1)
end

function UI:Down()
	local edit = UI.edit
	if self.fzf then return self:Move(1) end
	-- a line Up brought back: Down goes into its results, as on any search (back toward the empty prompt is Shift+Left's,
	-- UI:HistoryBack); only with nothing listed (nor coming: a search still going) on toward the newest line. (Until
	-- 0.48.3 Down always walked the history: Up, then Down to the results, emptied the prompt.)
	if Walking(self) and #UI.results == 0 and not self.searchJob and self:History(1) then return end
	if edit:GetText() == "" and #UI.results == 0 and self:Recall() then return end
	self:Move(1)
end

--- Down on the bare prompt. Simple mode: the last search back (its words, and the category picked),
--- to look through again; with none, your recent picks. Advanced: your recent picks (as the empty
--- prompt listed them before), Up being the lines you ran.
function UI:Recall()
	local q = EasyOn() and self.lastQuery
	if q then
		self:SetQuery(q, #q)
		self.recalled = q
		local cat = self.lastCategory
		if cat and EasyOn() and ns.Easy.BY_ID[cat] then self:SetCategory(cat) end
		return true
	end
	if self.showRecent then return false end
	self.showRecent = true
	self:Research()
	return #UI.results > 0
end

function UI:Scroll(delta)
	local maxOffset = math.max(0, #UI.results - LY.ROWS)
	UI.offset = math.max(0, math.min(maxOffset, UI.offset - delta * 3))
	local was = UI.sel
	UI.sel = math.max(UI.offset + 1, math.min(UI.offset + LY.ROWS, UI.sel))
	-- (the selection moved: what a click armed is another row's now, as Move does; review, 0.48.6)
	if UI.sel ~= was and self.armedEntry then self:Disarm() end
	self:Render()
end

----------------------------------------------------------------------
-- Easy mode: categories (Easy.lua has them): picked from the rows a search lists
----------------------------------------------------------------------

--- Search again now, even within the frame of the last search.
function UI:Research()
	self.refreshedAt = nil
	self:Refresh()
end

--- The prompt set to `text` (its change searches), or searched again when it already says that.
function UI:SetOrResearch(text)
	local edit = UI.edit
	if edit:GetText() == text then self:Research() else self:SetQuery(text, #text) end
end

--- Pick a category ("items", "emotes"...; nil: none, back to the categories): the results are searched again. An id
--- a category took over ("bags", "game": Easy.lua's `was`) picks that category.
function UI:SetCategory(id)
	if id ~= nil and not (ns.Easy and ns.Easy.BY_ID[id]) then return end
	if id ~= nil then id = ns.Easy.BY_ID[id].id end
	-- what its row in the list of categories counted, to say so if stepping in lists another number (NoteCountChange)
	self.expectCount, self.countNote = nil, nil
	for _, e in ipairs(id and UI.results or {}) do
		if e.catId == id and e.countExact and type(e.count) == "number" then self.expectCount = { cat = id, n = e.count } break end
	end
	self.category, self.categoryAuto = id, nil
	self.lastScan, self.lastOverview = nil, nil -- (other kinds: not a narrowing of the last search)
	if self:IsShown() then self:Research() end
end

--- Tab in easy mode on a category row: picks it (true). Anything else: false (Tab goes to the next row; back to all
--- the categories is Shift+Left's, UI:GoBack, since 0.45.20).
function UI:EasyTab()
	local e = UI.results[UI.sel]
	if not (e and e.catId) then return false end
	self:SetCategory(e.catId)
	return true
end

--- Easy mode switched on or off (Easy.Set): what's shown is searched again.
function UI:EasyChanged()
	local frame = UI.frame
	self.category = nil
	Forget(self, true)
	if not frame then return end
	if self:IsShown() then self:Research() end
end
