local ns = select(2, ...)

-- What's listed and selected: a search run a slice of a frame at a time, ">>>" collapsing the list into one row, the
-- pick lists of "@" and "key:", the selection moving and scrolling, Up/Down through the history and back to the last
-- search, Simple mode's categories. Split out of UI.lua.

local UI = ns.UI
local L = UI.layout
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
		ns:Print("Search error: " .. tostring(res))
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
	if to.drop and ns.QuestDrop then
		-- ">>> drop": the quests in your log among them (complete ones kept), dropped after Terminal's confirmation
		local rows, kept = ns.QuestDrop.GroupRows(list, true)
		self.groupRows = rows
		local n = #rows
		local row = { kind = "dropall", kindLabel = "|cffffd200quests|r", icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
			raw = true, sendAll = true, _pos = UI.NO_POS, _score = 0, actionVerb = "drop them all" }
		if n == 0 then
			row.name, row.noActivate = "Nothing to drop", true
			row.detail = kept > 0 and "the quests listed are complete: turn them in" or "no quest in your log among the results"
		else
			row.name = ("Drop %s %d quest%s"):format(n == 1 and "the" or "all", n, n == 1 and "" or "s")
			row.detail = (kept > 0 and (kept .. " complete kept  ·  ") or "") .. "you'll see them all and be asked first"
		end
		return { row }
	end
	local group = SH.GroupRows(list)
	self.groupRows = group
	local n = #group
	-- (what the rows are, as the chat line will say it: no row's text worked out, so no NPC's map pin is set here)
	local what = n > 0 and SH.GroupHeader(group, to.query) or nil
	local row = { kind = "send", kindLabel = "|cff33ff99chat|r", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", raw = true,
		sendAll = true, _pos = UI.NO_POS, _score = 0, detail = what or "" }
	if n == 0 then
		row.name, row.noActivate, row.detail = "Nothing to send", true, ""
	elseif to.cmd then
		row.name = ("Send %s %d to %s"):format(n == 1 and "the" or "all", n, to.label)
	else
		row.name = ("%d to send"):format(n)
		row.detail = to.bad and ("no channel called " .. to.bad) or "say where: party, guild, raid, say, whisper <name>"
	end
	return { row }
end

--- The rows ">>>" sends, for the footer and Share.Prefetch (asked on every status update): the ones CollapseGroup
--- grouped for the list kept, else the shown rows grouped now.
function UI:GroupedRows()
	if self.groupList and self.groupRows then return self.groupRows end
	return ns.Share.GroupRows(self.groupList or UI.results)
end

-- a search done: its full results replace the early ones; the selected result stays selected if it's still there,
-- and the list stays where you scrolled it
local function Completed(self, job, final)
	local keep = (UI.sel > 1 or UI.offset > 0) and UI.results[UI.sel] or nil
	local keptRow = UI.sel - UI.offset
	UI.results = self:CollapseGroup(final)
	UI.sel, UI.offset = 1, 0
	if keep then
		for i, e in ipairs(UI.results) do
			if e == keep then
				UI.sel = i
				UI.offset = math.max(0, math.min(i - keptRow, #UI.results - L.ROWS))
				break
			end
		end
	end
	self.lastSearchMs, self.lastSearchCount, self.lastSearchSlices = job.ms, #UI.results, job.slices
	self:SelectPopTarget(true)
	self:UpdateBusy()
	self:Render()
end

--- The next frame's share of the search. Once done, the full results replace the early ones.
function UI:ContinueSearch(job)
	if self.searchJob ~= job then return end -- typed again, or closed: this search is stale
	if not self:IsShown() or self.closing or self.armedEntry then self.searchJob = nil return end
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
--- rows to pick from (Enter/click writes it with a space after it; Shift+Tab cycles them in the prompt), or nil.
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
			-- typed letters start)
			local main = (p.aliases and p.aliases[1]) or id
			local word
			if ns.Lower(main):sub(1, #want) == want then word = main
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
		local values = key and ns.Filters and ns.Filters.VALUES[ns.Lower(key)]
		if not values then return nil end
		val = ns.Lower(val)
		for _, v in ipairs(values) do
			if v:sub(1, #val) == val then Row(key .. ":" .. v, "", "filter") end
		end
	end
	if #picks == 0 then return nil end
	return picks
end

--- The selection moved: the list scrolls to keep it on screen (every row redrawn), else only the selection is.
local function FollowSelection(self)
	local was = UI.offset
	if UI.sel <= UI.offset then UI.offset = UI.sel - 1 end
	if UI.sel > UI.offset + L.ROWS then UI.offset = UI.sel - L.ROWS end
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
		-- Simple mode: no sending to chat; the words before ">>" are searched and a row says it's Advanced mode's
		local query, rest = ns.Share.Split(text)
		if rest then
			self.blockedSyntax = "send"
			text = query:gsub("%s+$", "")
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
	self.searchJob = nil -- a search still going on is for the old text
	self.searchedText = edit:GetText()
	local t0 = debugprofilestop and debugprofilestop()
	if self.armedEntry then self:Disarm() end -- the query changed: whatever was armed is stale
	self.pendingAfter = nil
	self.args = nil
	self.mode = "search"
	local text = edit:GetText():gsub("^%s+", "")
	local first = text:sub(1, 1)
	if self.fzf then first = "" end -- (pure fuzzy finding: every line is a search, nothing in it is syntax)
	text = TakeSendTo(self, text, first)
	ListFor(self, text, first, edit)
	if t0 then self.lastSearchMs = debugprofilestop() - t0 end
	self.lastSearchCount = #UI.results
	self.lastSearchSlices = 1
	self:UpdateBusy()
	UI.sel, UI.offset = 1, 0
	self:SelectPopTarget(not self.searchJob)
	self:Render()
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

--- Up: the list's selection goes up; past the first row of an empty prompt it goes back through
--- the history instead.
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
	if (self.histIdx or (edit:GetText() == "" and UI.sel <= 1)) and self:History(-1) then return end
	self:Move(-1)
end

function UI:Down()
	local edit = UI.edit
	if self.fzf then return self:Move(1) end
	if self.histIdx ~= nil and self:History(1) then return end
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
	local maxOffset = math.max(0, #UI.results - L.ROWS)
	UI.offset = math.max(0, math.min(maxOffset, UI.offset - delta * 3))
	UI.sel = math.max(UI.offset + 1, math.min(UI.offset + L.ROWS, UI.sel))
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

--- Pick a category ("bags", "emotes"...; nil: none, back to the categories): the results are searched again.
function UI:SetCategory(id)
	if id ~= nil and not (ns.Easy and ns.Easy.BY_ID[id]) then return end
	self.category, self.categoryAuto = id, nil
	self.lastScan, self.lastOverview = nil, nil -- (other kinds: not a narrowing of the last search)
	if self:IsShown() then self:Research() end
end

--- Tab in easy mode: in a category, back to all of them; on a category row, pick it.
function UI:EasyTab()
	if self.category and not self.categoryAuto then return self:SetCategory(nil) end
	local e = UI.results[UI.sel]
	if e and e.catId then self:SetCategory(e.catId) end
end

--- Easy mode switched on or off (Easy.Set): what's shown is searched again.
function UI:EasyChanged()
	local frame = UI.frame
	self.category = nil
	Forget(self, true)
	if not frame then return end
	if self:IsShown() then self:Research() end
end
