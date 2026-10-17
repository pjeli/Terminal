local ns = select(2, ...)
local L = ns.L

-- The bar (0.55.1, experimental; the player: "if we are outside of advanced mode, let's try to add some tabs for
-- filtering, sorting, grouping, and a little announcement horn for putting out to say, party, raid, text"): a strip
-- under the prompt in Simple mode, so what Advanced syntax does is a click away.
--
--   Filter   what the shown lists can be narrowed by: quality, usable, upgrades, known spells, complete quests...
--            (several at once; each an Advanced filter the search takes as it takes a typed one)
--   Sort     nearest first, or by name, level, item level, quality, value, count (what the rows have)
--   Group    a row per zone, quality, type, slot, dungeon... with how many in each (Advanced's "| group by")
--   (horn)   the selected result, or all of them, to say, party, raid, guild..., or copied as text or CSV
--
-- What the words typed already ask shows too ("rare sword": Filter: Rare; "nearest ...": Sort: Nearest first), and
-- unticking it takes the word out of the line: the bar is one more way to write the search's query (0.55.7). A question's
-- answer ("my auctions") is filtered, sorted and grouped like any search's rows.
-- A click on one opens its menu; a right-click clears it. What's picked lasts while the prompt has words and goes
-- when it's cleared or the terminal closes. Typing Advanced syntax takes the bar away (that line is Advanced); Alt+`,
-- or Advanced syntax typed after the words, writes what's picked into the line ("q:rare+ sort:nearest | group by
-- zone": the search's query printed, Search.lua's ns.QueryToAdvanced). While the categories show (nothing picked yet), only Filter works: they count what passes it.

local UI, Theme = ns.UI, ns.Theme
local B = {}
ns.Bar = B

B.H = 22
local state = { filters = {}, sort = nil, group = nil }
B.state = state -- (tests)

-- what Filter offers: the filter (an Advanced one), what it says; shown when a list it judges is shown (F.APPLIES)
B.FILTERS = {
	{ id = "q:uncommon+", label = L["Uncommon or better"] },
	{ id = "q:rare+", label = L["Rare or better"] },
	{ id = "q:epic+", label = L["Epic or better"] },
	{ id = "is:upgrade", label = L["Upgrades"] },
	{ id = "is:usable", label = L["Usable"] },
	{ id = "is:boe", label = L["Bind on equip"] },
	{ id = "is:quest", label = L["Quest items"] },
	{ id = "is:known", label = L["Known"] },
	{ id = "is:unknown", label = L["Not known yet"] },
	{ id = "is:ready", label = L["Ready (off cooldown)"] },
	{ id = "is:complete", label = L["Complete"] },
	{ id = "is:todo", label = L["Not done yet"] },
	{ id = "is:craftable", label = L["Craftable"] },
	{ id = "is:skillup", label = L["Gives skill"] },
	{ id = "faction:friendly", label = L["Friendly"] },
	{ id = "is:vendor", label = L["Vendors"] },
	{ id = "is:trainer", label = L["Trainers"] },
	{ id = "is:online", label = L["Online"] },
}
-- what Sort offers: nearest (sort:nearest's lists), else a field the rows have (Aggregate's, and the name)
B.SORTS = {
	{ id = "nearest", label = L["Nearest first"], near = true },
	{ id = "name", label = L["Name"], field = "name", asc = true },
	{ id = "level", label = L["Level"], field = "level", asc = true },
	{ id = "ilvl", label = L["Item level"], field = "ilvl" },
	{ id = "quality", label = L["Quality"], field = "quality" },
	{ id = "value", label = L["Value"], field = "value" },
	{ id = "count", label = L["Count"], field = "count" },
	{ id = "damage", label = L["Biggest hit"], field = "damage" },
}
-- what Group offers: Aggregate's fields that name something
B.GROUPS = { "kind", "zone", "quality", "type", "slot", "dungeon", "raid", "boss", "level" }

local function E() return ns.Easy end
local function ById(list, id) for _, o in ipairs(list) do if o.id == id then return o end end end
B.ById = ById

--- Is the bar in use: Simple mode (not a line run in Advanced, not fuzzy finding), searching, words typed?
function B.On()
	local Ez = E()
	if not (UI.frame and Ez and Ez.On and Ez.On()) or Ez.temp or UI.fzf then return false end
	if UI.mode ~= "search" then return false end
	local text = UI.edit and UI.edit:GetText() or ""
	if not text:find("%S") then return false end
	local first = text:match("^%s*(.)")
	return first ~= "." and first ~= "/"
end

--- What's picked, for the search: only in Simple mode (the bar's own), else nothing.
function B.Active()
	local Ez = E()
	if not (Ez and Ez.On and Ez.On()) or Ez.temp or UI.fzf then return nil end
	if #state.filters == 0 and not state.sort and not state.group then return nil end
	return state
end

function B.Reset()
	local had = #state.filters > 0 or state.sort or state.group
	state.filters, state.sort, state.group = {}, nil, nil
	if B.menu then B.menu:Hide() end
	return had
end

--- The filters and the sort typed as words in Simple mode ("rare", "usable", "nearest"), as the search read them
--- (Search.lua's UI.typedPicks): shown as picked, and taken back out of the line from here (0.55.7, the search's rewrite:
--- the bar edits the query, the words typed included). Filters only of the kinds Filter offers (quality, is:, friendly).
local SHOWN_SPEC = { "^%-?is:", "^%-?q:", "^faction:" }
function B.Typed()
	local t = UI.typedPicks
	local out = { filters = {}, sort = t and t.sort or nil }
	for _, p in ipairs(t and t.filters or {}) do
		local spec = p.spec
		local shown
		for _, pat in ipairs(SHOWN_SPEC) do if type(spec) == "string" and spec:find(pat) then shown = true break end end
		if shown then out.filters[#out.filters + 1] = p end
	end
	return out
end

--- Words taken out of the prompt (case aside, whole words; a phrase's spaces any spaces), the search run again.
function B.DropWords(words)
	local edit = UI.edit
	if not edit then return end
	local text = edit:GetText() or ""
	for _, w in ipairs(words) do
		local pat = ns.Lower(w):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%s+", "%%s+")
		local lower, from = ns.Lower(text), 1
		while true do
			local a, b = lower:find(pat, from)
			if not a then break end
			local before, after = lower:sub(a - 1, a - 1), lower:sub(b + 1, b + 1)
			if (a == 1 or before:find("%s")) and (after == "" or after:find("%s")) then
				text = text:sub(1, a - 1) .. text:sub(b + 1)
				break
			end
			from = a + 1
		end
	end
	local had = (edit:GetText() or ""):find("%s$") -- (a space typed after the last word stays: the next word is on its way)
	text = text:gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if had and text ~= "" then text = text .. " " end
	if UI.SetQuery then UI:SetQuery(text, #text) else edit:SetText(text) end
end

--- The search's sort for a field (Search.lua's Scan.Finalize): the rows that have it in its order (the biggest first,
--- or A-Z / the lowest first), then the rest as they were. Changes their scores.
local function NumOf(field, e)
	local A = ns.Aggregate
	local f = A and A.FIELDS[field]
	if not (f and f.num) then return nil end
	local ok, n = pcall(f.num, e)
	return ok and type(n) == "number" and n or nil
end
local function Real(e) return type(e) == "table" and not (e.raw or e.noActivate or e.completion or e.lead or e.catId or e.syntaxRow) end
B.Real = Real

local function KeyOf(s, e)
	if s.field == "name" then return ns.Lower(ns.Plain(tostring(e.name or ""))) end
	return NumOf(s.field, e)
end
local function Keyed(s, rows)
	local keyed, rest = {}, {}
	for i, e in ipairs(rows) do
		if Real(e) then
			local k = KeyOf(s, e)
			if k ~= nil then keyed[#keyed + 1] = { e = e, k = k, i = i } else rest[#rest + 1] = e end
		end
	end
	table.sort(keyed, function(a, b)
		if a.k ~= b.k then
			if s.asc then return a.k < b.k end
			return a.k > b.k
		end
		return a.i < b.i
	end)
	return keyed, rest
end

function B.SortRows(rows, id)
	local s = ById(B.SORTS, id)
	if not (s and s.field) or #rows > 5000 then return rows end
	local keyed = Keyed(s, rows)
	for i, r in ipairs(keyed) do r.e._score = 1e10 - i end -- (above any search score; a pinned row stays on top)
	return rows
end

--- A question's rows in a field's order (Search.lua's Scan.AnswerView: an answer isn't scored): each run of results
--- between its lines (a heading, a note) sorted on its own, the rows with the field first. A new list.
function B.Order(rows, id)
	local s = ById(B.SORTS, id)
	if not (s and s.field) or #rows > 5000 then return rows end
	local out, run = {}, {}
	local function Flush()
		if #run == 0 then return end
		local keyed, rest = Keyed(s, run)
		for _, r in ipairs(keyed) do out[#out + 1] = r.e end
		for _, e in ipairs(rest) do out[#out + 1] = e end
		run = {}
	end
	for _, e in ipairs(rows) do
		if Real(e) then run[#run + 1] = e else Flush(); out[#out + 1] = e end
	end
	Flush()
	return out
end

--- The lists the shown rows come from (a category's lists for its row), and whether the categories show.
local function ShownKinds()
	local kinds, overview = {}, false
	for _, e in ipairs(UI.results or {}) do
		if type(e) == "table" then
			if e.catId then
				overview = true
				for k in pairs(ns.Easy.Kinds(e.catId) or {}) do kinds[k] = true end
			elseif Real(e) and e.kind then
				kinds[e.kind] = true
			end
		end
	end
	return kinds, overview
end
B.ShownKinds = ShownKinds

--- Do these rows show Simple mode's categories (nothing picked yet)?
function B.Overview(rows)
	for _, e in ipairs(rows or {}) do if type(e) == "table" and e.catId then return true end end
	return false
end

--- Does this filter judge a list that's shown (F.APPLIES; a key it doesn't list: never offered)?
local function Fits(id, kinds)
	local F = ns.Filters
	local key, val = id:match("^(%a+):(.+)$")
	local ap = F and F.APPLIES and F.APPLIES[key]
	if not ap then return false end
	local where = ap[val] or ap["*"]
	for _, k in ipairs(where or {}) do if kinds[k] then return true end end
	return false
end
B.Fits = Fits

--- The options a menu offers now: { id, label, on }.
function B.Options(which)
	local kinds, overview = ShownKinds()
	local out = {}
	local typed = B.Typed()
	if which == "filter" then
		local on, listed = {}, {}
		for _, id in ipairs(state.filters) do on[id] = true end
		-- (typed ones first: "usable" typed is Usable ticked; one Filter doesn't offer, its word: "Rare")
		for _, p in ipairs(typed.filters) do
			if not listed[p.spec] then
				listed[p.spec] = true
				local o = ById(B.FILTERS, p.spec)
				out[#out + 1] = { id = p.spec, label = o and o.label or ns.UpperFirst(p.word), on = true, typed = p.word }
			end
		end
		for _, o in ipairs(B.FILTERS) do
			if not listed[o.id] and (on[o.id] or Fits(o.id, kinds)) then out[#out + 1] = { id = o.id, label = o.label, on = on[o.id] } end
		end
		return out
	end
	if overview then return out end
	-- (the rows' own fields: the first few dozen are asked)
	local sample = {}
	for _, e in ipairs(UI.results or {}) do
		if Real(e) then sample[#sample + 1] = e; if #sample >= 40 then break end end
	end
	local A = ns.Aggregate
	local function Has(field)
		if field == "name" then return #sample >= 2 end
		local f = A and A.FIELDS[field]
		if not f then return false end
		for _, e in ipairs(sample) do
			local ok, v
			if f.text then ok, v = pcall(f.text, e, f) else ok, v = pcall(f.num, e) end
			if ok and v ~= nil then return true end
		end
		return false
	end
	if which == "sort" then
		for _, o in ipairs(B.SORTS) do
			local typedHere = typed.sort and typed.sort.id == o.id
			local fits = o.near and Fits("sort:nearest", kinds) or (o.field and Has(o.field))
			if fits or state.sort == o.id or typedHere then
				out[#out + 1] = { id = o.id, label = o.label, on = state.sort == o.id or typedHere, typed = typedHere and typed.sort.word or nil }
			end
		end
	elseif which == "group" then
		for _, id in ipairs(B.GROUPS) do
			if Has(id) or state.group == id then
				local f = A.FIELDS[id]
				out[#out + 1] = { id = id, label = ns.UpperFirst(f and f.label or id), on = state.group == id }
			end
		end
	end
	return out
end

--- Pick or drop an option: Filter's add up, Sort's and Group's are one each. The terminal searches again.
function B.Pick(which, id)
	local typed = B.Typed()
	if which == "filter" then
		-- (one typed as a word, not picked here: its word taken out of the line)
		local mine = false
		for _, f in ipairs(state.filters) do if f == id then mine = true end end
		if not mine then
			for _, p in ipairs(typed.filters) do
				if p.spec == id then B.DropWords({ p.word }) B.Update() return end
			end
		end
		local had
		for i, f in ipairs(state.filters) do if f == id then table.remove(state.filters, i); had = true break end end
		if not had then state.filters[#state.filters + 1] = id end
	elseif which == "sort" then
		if typed.sort and typed.sort.id == id and state.sort ~= id then B.DropWords({ typed.sort.word }) B.Update() return end
		state.sort = (state.sort ~= id) and id or nil
	elseif which == "group" then
		state.group = (state.group ~= id) and id or nil
	end
	B.Changed()
end

--- Nothing picked for Filter, Sort or Group: the words typed for it taken out of the line too.
function B.Clear(which)
	local typed, words = B.Typed(), {}
	if which == "filter" then
		state.filters = {}
		for _, p in ipairs(typed.filters) do words[#words + 1] = p.word end
	elseif which == "sort" then
		state.sort = nil
		if typed.sort then words[1] = typed.sort.word end
	else
		state.group = nil
	end
	if #words > 0 then B.DropWords(words) end
	B.Changed()
end

--- Something picked or dropped: the search again (its filters, sort and summing), the bar redrawn.
function B.Changed()
	UI.lastScan, UI.lastExtra = nil, nil -- (another filter: not a narrowing of the last keystroke's matches)
	if UI.frame and UI:IsShown() then UI:Research() end
	B.Update()
end

----------------------------------------------------------------------
-- The strip and its menu
----------------------------------------------------------------------

local strip
local HORN = "Interface\\Icons\\INV_Misc_Horn_01"

local function Label(which)
	local typed = B.Typed()
	if which == "filter" then
		-- (what's picked here and what's typed: one list, the typed words' once each)
		local labels, seen = {}, {}
		for _, p in ipairs(typed.filters) do
			if not seen[p.spec] then seen[p.spec] = true; local o = ById(B.FILTERS, p.spec); labels[#labels + 1] = o and o.label or ns.UpperFirst(p.word) end
		end
		for _, id in ipairs(state.filters) do
			if not seen[id] then seen[id] = true; local o = ById(B.FILTERS, id); labels[#labels + 1] = o and o.label or id end
		end
		if #labels == 1 then return L["Filter: %s"]:format(labels[1]) end
		if #labels > 1 then return L["Filter: %d"]:format(#labels) end
		return L["Filter"]
	elseif which == "sort" then
		local o = (state.sort and ById(B.SORTS, state.sort)) or (typed.sort and ById(B.SORTS, typed.sort.id))
		return o and L["Sort: %s"]:format(o.label) or L["Sort"]
	else
		local f = state.group and ns.Aggregate and ns.Aggregate.FIELDS[state.group]
		return f and L["Group: %s"]:format(ns.UpperFirst(f.label)) or L["Group"]
	end
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
	local horn = CreateFrame("Button", nil, strip)
	horn.icon = horn:CreateTexture(nil, "ARTWORK")
	horn.icon:SetAllPoints()
	horn.icon:SetTexture(HORN)
	horn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
		tip:SetOwner(horn, "ANCHOR_TOP")
		tip:SetText(L["Send or copy"], 1, 1, 1)
		tip:AddLine(L["The selected result, or all of them, to say, party, raid, guild..., or copied as text or CSV"], 0.8, 0.8, 0.8, true)
		tip:Show()
	end)
	horn:SetScript("OnLeave", function() if B.tip then B.tip:Hide() end end)
	strip.horn = horn
	B.strip = strip
	return strip
end

--- How tall the bar is now (0: not shown), for the header (List.lua's HeaderH).
function B.Height() return B.On() and B.H or 0 end

--- Shown or hidden, its labels: from the footer's update (List.lua), on every keystroke and selection.
function B.Update()
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
	if h == 0 then B.HideMenu() return end
	local t = Theme.Get()
	local classic = t.frame == "classic"
	local inset = classic and 9 or 6
	local top = (UI.tabsH or 0) + ns.UI.layout.HEADER_H + (UI.promptExtra or 0) - 4
	local _, overview = ShownKinds()
	-- (placed again only when where it goes or a label's width changed: a frame moved under the pointer loses it, so
	-- placing the buttons on every footer update took every hover and click away; 0.55.1, the player: "mousing over and
	-- clicking do nothing")
	local widths = {}
	for i, b in ipairs(s.buttons) do
		local label = Label(b.which)
		if b.label ~= label then b.label = label; b.text:SetText(label) end
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
		local horn = s.horn
		horn:ClearAllPoints()
		horn:SetPoint("RIGHT", s, "RIGHT", -2, 0)
		horn:SetSize(h - 6, h - 6)
	end
	for _, b in ipairs(s.buttons) do
		local typed = B.Typed()
		local active = (b.which == "filter" and (#state.filters > 0 or #typed.filters > 0)) or (b.which == "sort" and (state.sort or typed.sort))
			or (b.which == "group" and state.group)
		b.off = overview and b.which ~= "filter" and not active
		b.active = active and true or false
		local col = b.off and t.dim or (active and t.accent or t.text)
		b.text:SetTextColor(Theme.RGB(col))
		B.Shade(b)
	end
	local e = UI.results and UI.results[UI.sel]
	s.horn.off = not Real(e)
	s.horn:SetAlpha(s.horn.off and 0.35 or 1)
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
	b.hl = b:CreateTexture(nil, "BACKGROUND")
	b.hl:SetAllPoints()
	b.hl:Hide()
	b:SetScript("OnEnter", function() b.hl:Show() end)
	b:SetScript("OnLeave", function() b.hl:Hide() end)
	b:SetScript("OnClick", function()
		local which, id = m.which, b.id
		if id == false then B.Clear(which) m:Hide() return end
		B.Pick(which, id)
		if which == "filter" then B.ShowMenu(which, m.owner) else m:Hide() end -- (filters add up: it stays open)
	end)
	m.lines[i] = b
	return b
end

local function HasOn(opts) for _, o in ipairs(opts) do if o.on then return true end end return false end

--- A button's menu, under it: its options, the ones picked ticked (typed ones say so), "None" on top to clear.
function B.ShowMenu(which, owner)
	local m = MenuFrame()
	local t = Theme.Get()
	local opts = B.Options(which)
	local items = { { id = false, label = which == "filter" and L["No filter"] or which == "sort" and L["Best match"] or L["No groups"],
		on = #opts == 0 or not HasOn(opts) } }
	for _, o in ipairs(opts) do items[#items + 1] = o end
	if #opts == 0 then items[#items + 1] = { label = L["Nothing to pick for these results"], dead = true } end
	m.which, m.owner = which, owner
	for i, it in ipairs(items) do
		local b = MenuLine(m, i)
		b.id = (not it.dead) and it.id or nil
		b.fs:SetText(it.typed and L["%s (typed)"]:format(it.label) or it.label)
		b.fs:SetTextColor(Theme.RGB(it.dead and t.dim or (it.on and t.accent or t.text)))
		b.check:SetShown(it.on and true or false)
		b.hl:SetColorTexture(Theme.RGB(t.accent))
		b.hl:SetAlpha(0.25)
		b:EnableMouse(not it.dead)
		b:Show()
	end
	for i = #items + 1, #m.lines do m.lines[i]:Hide() end
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

--- The horn: the selected result's sending lines, all of them to a channel, or copied (the row menu's, those only).
function B.Horn()
	B.HideMenu()
	local e = UI.results and UI.results[UI.sel]
	if not Real(e) then ns:Print(L["Pick a result first: the horn sends or copies it."]) return end
	UI:ShowRowMenu(UI.sel, false, true)
end
