local ns = select(2, ...)

-- Completion (Tab, Right at the end of the prompt) and the faint text after what's typed: the completion, or on an
-- empty prompt an example of what to type. Split out of UI.lua.

local UI = ns.UI
local Theme = ns.Theme
local EasyOn, NextPos, ONCE_LABEL = UI.EasyOn, UI.NextPos, UI.ONCE_LABEL

local DOWN_RECENT = "Down: your recent picks"

UI.HINT_GAP = 6 -- (px between the cursor and an empty prompt's hint)
local FZF_GHOST = "fzf" -- (the player's call: just that; the footer has the keys)

----------------------------------------------------------------------
-- Completion (Tab), shell style
--
-- ".th<Tab>" completes a command, ".theme dr<Tab>" its argument, "/rel<Tab>" a slash
-- command, "@equ<Tab>" a kind, and a plain search completes to the selected result's name.
-- Several candidates: Tab fills in what they share; nothing left to add, Tab moves down the
-- list. The suggestion shows faintly after the text; Right arrow at the end takes it too.
----------------------------------------------------------------------

local function StartsWith(s, prefix)
	return ns.Lower(s:sub(1, #prefix)) == ns.Lower(prefix)
end

--- What the candidates share at their start, whole characters at a time: a byte-wise compare cut
--- Cyrillic and Korean names inside a letter (their letters share lead bytes).
local function CommonPrefix(list)
	local p = list[1]
	for i = 2, #list do
		local s, j = list[i], 0
		while j < #p and j < #s do
			local np, nsp = NextPos(p, j), NextPos(s, j)
			if ns.Lower(p:sub(j + 1, np)) ~= ns.Lower(s:sub(j + 1, nsp)) then break end
			j = np
		end
		p = p:sub(1, j)
	end
	return p
end

--- Complete `word` from `cands`: the text that should replace it, and whether that's final.
local function CompleteWord(word, cands)
	local hits, seen = {}, {}
	for _, c in ipairs(cands) do
		if type(c) == "table" then c = c[1] end -- { value, detail }
		if type(c) == "string" and StartsWith(c, word) and not seen[ns.Lower(c)] then
			seen[ns.Lower(c)] = true
			hits[#hits + 1] = c
		end
	end
	if #hits == 0 then return nil end
	if #hits == 1 then return hits[1], true end
	table.sort(hits, function(a, b) return #a < #b end)
	local cp = CommonPrefix(hits)
	if #cp <= #word then cp = word end -- nothing shared beyond what's typed
	return cp, false
end

--- The text with its last `word` replaced by `new` (and a space after it when that's final).
local function Replace(text, word, new, final)
	return text:sub(1, #text - #word) .. new .. (final and " " or "")
end

--- ".th" -> ".theme", ".theme dr" -> ".theme dracula": a command, then its argument. Whether the text is a
--- command, and its completion.
local function CompleteCommand(text)
	if text:sub(1, 1) ~= "." then return false end
	local word, rest = text:sub(2):match("^(%S*)(.*)$")
	if rest == "" then
		local new, final = CompleteWord(word, ns.commandOrder)
		if new then return true, Replace(text, word, new, final) end
		return true, nil
	end
	local c = ns:FindCommand(word)
	if not (c and c.complete) then return true, nil end
	local args = rest:gsub("^%s+", "")
	local argWord = args:match("(%S*)$") or ""
	local ok, cands = pcall(c.complete, args)
	if not ok or type(cands) ~= "table" then return true, nil end
	local new, final = CompleteWord(argWord, cands)
	if not new then return true, nil end
	return true, Replace(text, argWord, new, final)
end

--- "/rel" -> "/reload": a slash command. Whether the text is one, and its completion.
local function CompleteSlash(text)
	if text:sub(1, 1) ~= "/" then return false end
	if text:find("%s") then return true, nil end
	local cands = {}
	local p = ns.providers.slash
	if p then for _, e in ipairs(ns:GetEntries(p)) do cands[#cands + 1] = e.name end end
	local new, final = CompleteWord(text, cands)
	if new then return true, Replace(text, text, new, final) end
	return true, nil
end

--- ">> par" -> ">> party": the channel after ">>". Whether the last word is one, and its completion.
local function CompleteChannel(text, last)
	local before = text:sub(1, #text - #last)
	if not (ns.Share and before:match("%s?>>>?%s+$") and last ~= "") then return false end
	local new, final = CompleteWord(ns.Lower(last), ns.Share.NAMES)
	if not new then return true, nil end
	return true, Replace(text, last, new, final)
end

--- "@equ" -> "@equipment": a kind. Whether the last word is one, and its completion.
local function CompleteKind(text, last)
	if last:sub(1, 1) ~= "@" then return false end
	local cands = {}
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		cands[#cands + 1] = "@" .. id
		for _, a in ipairs(p.aliases or {}) do cands[#cands + 1] = "@" .. a end
	end
	local new, final = CompleteWord(last, cands)
	if not new then return true, nil end
	return true, Replace(text, last, new, final)
end

--- A filter's value: is:to -> is:todo, q:ep -> q:epic, stat:sta -> stat:stamina. Whether the last word is a filter
--- with values to complete, and its completion.
local function CompleteFilterValue(text, last)
	local fkey, fval = last:match("^(%a+):(%S*)$")
	local values = fkey and ns.Filters and ns.Filters.VALUES[ns.Lower(fkey)]
	if not values then return false end
	local new, final = CompleteWord(ns.Lower(fval), values)
	if not new then return true, nil end
	return true, Replace(text, fval, new, final)
end

--- The selected row: the "Search <list> for this" row adds its @kind; a plain search completes to the row's name
--- when the typed words start it.
local function CompleteName(text)
	-- the "Search <list> for this" row: Tab adds its @kind
	local e = UI.results[UI.sel]
	if e and e.completion then return e.completion end
	-- plain search: the selected result's name, when the typed words start it
	if not e or e.raw or e.noActivate or type(e.name) ~= "string" or e.kind == "calc" then return nil end
	local kinds = text:match("^(@%S+%s+)") or ""
	while true do -- every leading @kind
		local more = text:sub(#kinds + 1):match("^(@%S+%s+)")
		if not more then break end
		kinds = kinds .. more
	end
	local query = text:sub(#kinds + 1)
	if query == "" or #e.name <= #query or not StartsWith(e.name, query) then return nil end
	return kinds .. e.name
end

local function ComputeCompletion(self, text)
	if text == "" or self.fzf or (self.cursor or #text) < #text then return nil end
	-- the pick list: the faint completion is the row picked in it (Right takes it)
	local picked = UI.results[1] and UI.results[1].syntaxRow and UI.results[UI.sel]
	if picked then return picked.completion end
	-- (a shape that recognises the text answers, nil included: the next one isn't tried)
	local matched, value = CompleteCommand(text)
	if matched then return value end
	matched, value = CompleteSlash(text)
	if matched then return value end
	if EasyOn() then return nil end -- (Simple mode: no @kinds, filters or channels to complete)
	local last = text:match("(%S*)$") or ""
	matched, value = CompleteChannel(text, last)
	if matched then return value end
	matched, value = CompleteKind(text, last)
	if matched then return value end
	matched, value = CompleteFilterValue(text, last)
	if matched then return value end
	return CompleteName(text)
end

--- A result as prompt text that finds it again: "@npc Thrall", ".theme", "/dance"; nil for rows that are
--- only help or hints.
function UI:ResultText(e)
	if not e or e.raw or e.noActivate or e.completion or type(e.name) ~= "string" or e.kind == "calc" then return nil end
	if e.kind == "cmd" then return "." .. (e.cmd and e.cmd.name or e.name) end
	if e.kind == "slash" then return e.name end
	local p = e.kind and ns.providers[e.kind]
	if not p then return e.name end
	return "@" .. ((p.aliases and p.aliases[1]) or p.id) .. " " .. e.name
end

--- The suggestion shown in the empty prompt, as text to type ("try: hogger >> party" -> "hogger >> party"),
--- or nil (suggestions off, something typed or listed, a tip rather than an example).
function UI:SuggestionText()
	local edit = UI.edit
	if edit:GetText() ~= "" or #UI.results > 0 or self.histIdx or self.fzf or Theme.Get().suggest == false then return nil end
	local ex = ns.Easy and ns.Easy.Example()
	local body = type(ex) == "string" and ex:match("^try:%s*(.-)%s*$")
	if not body then return nil end
	body = body:gsub("%s*%b()$", "") -- (".filters (every key:value)": the note isn't typed)
	return body ~= "" and body or nil
end

--- Shift+Right at the end of the prompt: the selected result written into it ("@npc Thrall"), to build on
--- (a ">> channel" already typed is kept). False when there's nothing to write.
function UI:FillFromResult()
	local edit = UI.edit
	-- the empty prompt: Shift+Right takes the suggestion shown in it
	local suggested = self:SuggestionText()
	if suggested then
		suggested = suggested .. " " -- (a space for the next word)
		self:SetQuery(suggested, #suggested)
		return true
	end
	local new = self:ResultText(UI.results[UI.sel])
	-- pure fuzzy finding: just the name (no @kind: nothing is syntax here)
	if self.fzf then
		local e = UI.results[UI.sel]
		new = e and not e.noActivate and type(e.name) == "string" and ns.Plain(e.name) or nil
		if not new or new == "" then return false end
		new = new .. " "
		self:SetQuery(new, #new)
		return true
	end
	if not new then return false end
	local _, rest, all = nil, nil, nil
	if ns.Share then _, rest, all = ns.Share.Split(edit:GetText()) end
	if rest then new = new .. (all and " >>> " or " >> ") .. rest else new = new .. " " end
	self:SetQuery(new, #new)
	return true
end

--- The query with the completion applied, or nil when there's nothing to complete.
--- Asked several times per keystroke (caret, ghost text, render): worked out once per state.
local memo = {}
function UI:Completion()
	local edit = UI.edit
	if not edit or self:SelRange() then return nil end
	local text = edit:GetText()
	if memo.gen ~= ns.entriesGen then memo.results, memo.value = nil, nil end -- (rows of freed lists go)
	if memo.text == text and memo.cursor == self.cursor and memo.results == UI.results and memo.sel == UI.sel then
		return memo.value
	end
	local value = ComputeCompletion(self, text)
	memo.text, memo.cursor, memo.results, memo.sel, memo.gen, memo.value = text, self.cursor, UI.results, UI.sel, ns.entriesGen, value
	return value
end

--- What the suggestion adds to the typed text (for the faint preview), or nil.
function UI:Suggestion()
	local edit = UI.edit
	local text = edit and edit:GetText() or ""
	local new = self:Completion()
	if not new or #new <= #text or not StartsWith(new, text) then return nil end
	local add = new:sub(#text + 1):gsub("%s+$", "")
	return add ~= "" and add or nil
end

--- Apply the completion. False when there was nothing to complete.
function UI:AcceptCompletion()
	local edit = UI.edit
	local text = edit and edit:GetText() or ""
	local new = self:Completion()
	if not new or new == text then return false end
	self:SetQuery(new, #new)
	return true
end

function UI:UpdateGhost()
	local edit, ghost = UI.edit, UI.ghost
	if not ghost then return end
	local add = self:IsShown() and self:Suggestion() or nil
	if self.clipHint and not self.keys and self:IsShown() then
		add = (edit:GetText() ~= "" and "   " or "") .. (self.clipHint == "V" and "Ctrl+V again to paste" or "Ctrl+C again to copy")
	end
	-- nothing typed: a faint line in the prompt says what to do (there's nothing under it); fuzzy finding has its own
	if not add and self:IsShown() and edit:GetText() == "" and self.fzf then
		add = FZF_GHOST
	elseif not add and self:IsShown() and edit:GetText() == "" and not self.histIdx and #UI.results == 0 then
		-- a rotating example of what to type (Advanced: its own syntax, and what Up/Down bring)
		-- (the option off: the prompt stays empty)
		if Theme.Get().suggest ~= false then add = ns.Easy and ns.Easy.Example() or DOWN_RECENT end
		-- Alt+`: this run is Advanced (Simple again once it closes)
		if ns.Easy and ns.Easy.temp then add = ONCE_LABEL .. (add and ("  ·  " .. add) or "") end
	end
	if not add then ghost:Hide() return end
	local text = edit:GetText()
	local w, y = self:PromptXY(#text) -- (the end of the last line)
	-- an empty prompt's hint (an example, "fzf", Advanced's Up/Down line) starts a little after the cursor, so the
	-- cursor doesn't sit on its first letter; a completion of typed text carries straight on from it
	if text == "" then w = w + UI.HINT_GAP end
	local room = (edit:GetWidth() or 400) - w - 4
	if room < 20 then ghost:Hide() return end
	ghost:SetText((add:gsub("|", "||")))
	ghost:ClearAllPoints()
	ghost:SetPoint("LEFT", edit, "LEFT", w, y)
	ghost:SetWidth(room)
	ghost:Show()
end

--- The completion kept for the last search's rows forgotten (UI.lua's Forget).
function UI:ForgetCompletion()
	memo.results, memo.value = nil, nil
end
