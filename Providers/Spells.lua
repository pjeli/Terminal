local ns = select(2, ...)
local L = ns.L
local H = ns.Highlight

-- Spells (@spell): every spell in your spellbook.
--   Enter        opens the spellbook on the spell and points at it. The game's own book: opened by its
--                micro button and turned to the spell's tab and page by the game's own clicks in the same
--                press (Secure.lua's "Turning a window", NAV below), so nothing runs tainted; with that
--                turned off (.nav), opened with your Spellbook key and the spell pointed at once it shows.
--                ClassicUIForever's classic book: turned to the spell's tab and page, as you would,
--                through the parts its public API (ClassicUIForeverAPI) hands out, and the highest
--                rank shown is pointed at.
--   Shift+Enter  casts it: a /cast line on the secure macro button, pressed by the game. Passive
--                spells can't be cast. In combat Enter can't be handed to the game, so neither works.

local SP = {}
ns.Spells = SP

local BANK = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local ITEM_SPELL = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1

local Secret, Call = ns.Secret, ns.Safe -- (Util.lua)

--- One spellbook slot's spell: id, passive, rank text; nil for anything else (flyouts, future
--- spells, empty slots). This client can give no item info for a slot it lists, so then the
--- slot's type and id are asked instead (as ClassicUIForever's book does).
local function SlotSpell(slot)
	local it = Call(C_SpellBook.GetSpellBookItemInfo, slot, BANK)
	if type(it) == "table" then
		if Secret(it.itemType) or it.itemType ~= ITEM_SPELL or it.isOffSpec == true then return nil end
		local id = it.spellID or it.actionID
		if type(id) ~= "number" or Secret(id) or id <= 0 then return nil end
		local passive = it.isPassive
		return id, (not Secret(passive)) and passive == true, (not Secret(it.subName)) and it.subName or nil
	end
	if not C_SpellBook.GetSpellBookItemType then return nil end
	local ok, kind, id = pcall(C_SpellBook.GetSpellBookItemType, slot, BANK)
	if not ok or Secret(kind) or Secret(id) or kind ~= ITEM_SPELL or type(id) ~= "number" or id <= 0 then return nil end
	local passive = C_Spell.IsSpellPassive and Call(C_Spell.IsSpellPassive, id)
	local sub = C_Spell.GetSpellSubtext and Call(C_Spell.GetSpellSubtext, id)
	return id, (not Secret(passive)) and passive == true, (type(sub) == "string" and not Secret(sub)) and sub or nil
end

--- ClassicUIForever's API when its spellbook stands in for the client's, else nil.
local function CUF()
	local A = _G.ClassicUIForeverAPI
	if type(A) == "table" and type(A.GetFrame) == "function" and Call(A.IsOn, "spellBook") then return A end
end

--- The spellbook showing now (ClassicUIForever's, the client's, a classic one), or nil.
function SP.Book()
	local A = CUF()
	if A then
		local f = Call(A.GetFrame, "spellBook")
		return f and f:IsVisible() and f or nil
	end
	local p = _G.PlayerSpellsFrame
	local book = p and p.SpellBookFrame
	if book and book:IsVisible() then return book end
	local s = _G.SpellBookFrame
	if s and s:IsVisible() then return s end
end

local function BookOpen() return SP.Book() ~= nil end

-- The game's own spellbook (no ClassicUIForever) is turned to the spell by the game's own clicks (0.46.18, Secure.lua's
-- "Turning a window"): the press opens it with its micro button when it's closed, then each step clicks the search
-- box's clear button, the spell's tab or a page arrow, picked by reading the book (its categories, its pages' element
-- lists); the book's own code does the turning, untainted. Then Terminal points at the spell. Until 0.46.2 the game
-- pressed /run ... SpellBookFrame:GoToSpell(id), but a /run line runs tainted (0.46.1), and the book's items set up by
-- it held tainted slots (a click on a spell there, C_SpellBook.CastSpellBookItem, could be blocked); 0.46.2-0.46.17
-- only opened it and pointed. Turned off (.nav) or not possible: opened with your spellbook key and pointed at.

--- The game's own book (PlayerSpellsFrame.SpellBookFrame), shown or not; nil without it.
local function GameBook()
	local p = _G.PlayerSpellsFrame
	return p and p.SpellBookFrame or nil
end

--- The spell's slot in the book (its own rank: the entry keeps the highest known).
local function SlotOf(e)
	if not C_SpellBook.FindSpellBookSlotForSpell then return nil end
	local ok, s, b = pcall(C_SpellBook.FindSpellBookSlotForSpell, e.spellID, false, true, false, false)
	if ok and type(s) == "number" then return s, b end
end

--- One step toward the spell in the game's own book: the button to click, and why; nil when it shows (or can't be
--- reached by a click). Reads only: the book's categories, its tab buttons, its pages' element lists, its page arrows.
function SP.NavStep(e)
	local book = GameBook()
	if not (book and book:IsVisible()) then return nil, "the book isn't showing" end
	local search = book.SearchBox
	if search and search.GetText then
		local ok, t = pcall(search.GetText, search)
		if ok and type(t) == "string" and t ~= "" then
			return search.clearButton, "clear the book's search"
		end
	end
	local slot, bank = SlotOf(e)
	if not slot then return nil, "no spellbook slot for " .. tostring(e.name) end
	local cat
	for _, c in ipairs(rawget(book, "categoryMixins") or {}) do
		local ok, has = pcall(c.ContainsSlot, c, slot, bank)
		if ok and has then cat = c break end
	end
	if not cat then return nil, "no tab holds slot " .. slot end
	local tabs = rawget(book, "CategoryTabSystem") or rawget(book, "TabSystem")
	local okID, tabID = pcall(cat.GetTabID, cat)
	local okCur, cur = pcall(book.GetTab, book)
	if okID and okCur and tabID ~= cur then
		if not (tabs and tabs.GetTabButton) then return nil, "no tab system to switch with" end
		local okB, btn = pcall(tabs.GetTabButton, tabs, tabID)
		return okB and btn or nil, "the spell's tab"
	end
	local paged = rawget(book, "PagedSpellsFrame")
	local list = paged and rawget(paged, "viewDataList")
	local pc = paged and rawget(paged, "PagingControls")
	if type(list) ~= "table" or not pc then return nil, "the book's pages aren't laid out" end
	local perPage = tonumber(rawget(paged, "viewsPerPage")) or 1
	local at
	for vi, view in ipairs(list) do
		for _, el in ipairs(view) do
			if type(el) == "table" and not el.isSpacer and el.slotIndex == slot and (bank == nil or el.spellBank == nil or el.spellBank == bank) then
				at = vi break
			end
		end
		if at then break end
	end
	if not at then return nil, "the spell isn't on any page of its tab" end
	local page, now = math.ceil(at / perPage), tonumber(rawget(pc, "currentPage")) or 1
	if page > now then return rawget(pc, "NextPageButton"), ("page %d, from %d"):format(page, now) end
	if page < now then return rawget(pc, "PrevPageButton"), ("page %d, from %d"):format(page, now) end
	return nil, "on its page"
end

-- what the clicks write, read after the press (Secure.lua): the page the book shows
local NAV = {
	route = "spellbook", step = SP.NavStep,
	watch = { function()
		local book = GameBook()
		local paged = book and rawget(book, "PagedSpellsFrame")
		return paged and rawget(paged, "PagingControls"), "currentPage"
	end },
	watchName = function() return L["the spellbook's page"] end,
}

--- Whether the press turns the game's own book (else ClassicUIForever's route, or the key and pointing).
local function Turns()
	if CUF() or not ns.Secure.NavOn("spellbook") then return false end
	-- your spellbook key taken by another addon's book (ClassicUIForever's): its route
	if ns.Secure.EffectiveAction("TOGGLESPELLBOOK") ~= "TOGGLESPELLBOOK" then return false end
	return true
end

local function NavMacro(e)
	-- (a spell's row only: the Spellbook panel row shares this spec, and turning nothing would still clear the book's
	-- search, 0.47.0 review)
	if type(e) ~= "table" or not e.spellID or not Turns() then return nil end
	local book = GameBook()
	local open
	if not (book and book:IsVisible()) then
		open = ns.Secure.ClickLine("SpellbookMicroButton")
		if not open then return nil end
	end
	return (ns.Secure.NavMacro(NAV, e, open))
end

-- open = nothing to press (the spellbook key would toggle an open book shut): only turned (ClassicUIForever's) or
-- pointed at; the game's own book being turned is always pressed (its macro opens it only when it's closed)
local function IsOpen(e) return BookOpen() and not Turns() end
SP.IsOpen = IsOpen -- (tests)

--- The game's own book (turned by the press): the spell's item there, found by its spellbook slot
--- (only read: its items keep slotIndex/spellBank). The entry's id is its highest rank's.
function SP.ClientButton(book, e)
	local paged = book.PagedSpellsFrame or book
	local slot, bank = SlotOf(e)
	local item = ns.FindFrame(paged, function(f)
		if slot then return f.slotIndex == slot and (bank == nil or f.spellBank == bank) end
		return type(f.spellBookItemInfo) == "table" and f.spellBookItemInfo.spellID == e.spellID
	end, 8)
	if item then return item.Button or item end
end

SP.SECURE = { macro = NavMacro, binding = "TOGGLESPELLBOOK", buttons = { "SpellbookMicroButton" } }

--- The page's button for the spell: its own (highest known) rank, else the highest rank of it shown.
local function OnPage(A, book, e)
	local best, bestSlot
	for _, btn in ipairs(book.Buttons or {}) do
		local id = Call(A.SpellOnButton, btn)
		if id then
			if id == e.spellID then return btn, true end
			if Call(C_Spell.GetSpellName, id) == e.name and (not bestSlot or (btn.slot or 0) > bestSlot) then
				best, bestSlot = btn, btn.slot or 0
			end
		end
	end
	return best, false
end

local MAX_PAGES = 40

--- ClassicUIForever's book turned to the spell, as a player would: its tab (the spell's skill line),
--- then page by page from the first until it shows. Its tabs and page arrows are its own plain
--- buttons, which its API hands to other addons; the search box is left empty. Returns the button.
function SP.TurnTo(A, book, e)
	local btn, exact = OnPage(A, book, e)
	if exact then return btn end
	local search = book.Search
	if search and search.GetText and (search:GetText() or "") ~= "" then search:SetText("") end
	local tab
	for _, t in ipairs(book.SkillTabs or {}) do
		if t:IsShown() and t.line == e.line then tab = t break end
	end
	if tab then tab:Click() else ns:Trace("spells: no tab for skill line " .. tostring(e.line)) end
	local prev, nxt = book.PrevPage, book.NextPage
	for _ = 1, MAX_PAGES do
		if not (prev and prev:IsEnabled()) then break end
		prev:Click()
	end
	local page, fallbackPage = 1, nil
	for _ = 1, MAX_PAGES do
		local b, ex = OnPage(A, book, e)
		if ex then
			ns:Trace(("spells: %s on page %d"):format(e.name, page))
			return b
		end
		if b then fallbackPage = page end -- a lower rank of it: the last page with one is kept
		if not (nxt and nxt:IsEnabled()) then break end
		nxt:Click()
		page = page + 1
	end
	if not fallbackPage then
		ns:Trace("spells: " .. tostring(e.name) .. " isn't on any page of its tab")
		return nil
	end
	for _ = 1, page - fallbackPage do if prev then prev:Click() end end
	ns:Trace(("spells: %s (a lower rank shown) on page %d"):format(e.name, fallbackPage))
	return (OnPage(A, book, e))
end

SP.WATCH = 200 -- looks (a tenth of a second apart) for the spell in the game's own book: 20 seconds to turn to it
SP.HINT_AFTER = 8 -- looks before saying it isn't on the page showing

--- After the book opened: turn it to the spell (ClassicUIForever's) or point at it when it shows (the game's own).
local function PointAtSpell(e)
	local A = CUF()
	ns:Trace("spells: pointing at " .. tostring(e.name) .. (A and " (ClassicUIForever's book)" or " (client book)"))
	local turned, last, looks, seen = false, nil, 0, false
	H:When(function()
		local book = SP.Book()
		if not book then if seen then return false end return nil end -- (closed again after it showed: nothing more to look for)
		seen = true
		if A then
			-- turned once; after that only looked at (the highlight's retries don't turn it again)
			if turned then return (OnPage(A, book, e)) end
			turned = true
			return SP.TurnTo(A, book, e)
		end
		-- the game's book, opened by this press, fills its page in over its first frames: point only once the
		-- same frame shows the spell on two looks in a row (a tenth of a second apart). Not on this page: said once,
		-- and looked for until SP.WATCH runs out (pointed at as soon as you turn to it)
		local item = SP.ClientButton(book, e)
		if item and item == last then return item end
		last = item
		looks = looks + 1
		if looks == SP.HINT_AFTER and not item then
			ns:Print(L["%s isn't on this page of your spellbook: turn to it and Terminal points at it."]:format(tostring(e.name)))
		end
		return nil
	end, function(target) H:Show(target) end, A and 25 or SP.WATCH, function()
		-- for a .debug log: which step found nothing
		local book = SP.Book()
		local slot = SlotOf(e)
		ns:Trace(("spells: gave up pointing at %s (book shown: %s, its slot: %s, frame found: %s)"):format(
			tostring(e.name), book and "yes" or "no", tostring(slot), tostring(book and SP.ClientButton(book, e) ~= nil)))
	end)
end

-- Without the secure route (no binding, no button): try the book's own openers.
local function SpellLink(e) return Call(C_Spell.GetSpellLink, e.spellID) end

local function OpenSpellBook(e)
	local A = CUF()
	if A then
		Call(A.Open, "spellBook")
	else
		ns:Print(L["Couldn't open your spellbook from the terminal. Press your Spellbook key."])
		return
	end
	PointAtSpell(e)
end

-- Shift+Enter: cast it. The game presses the /cast line (Terminal's own code can't cast).
local function CastMacro(e) return not e.passive and ("/cast " .. e.name) or nil end
local CAST_SPEC = { macro = CastMacro }
local NeverOpen = ns.Never -- nothing to open first: always pressed
local function CastAfter(e) ns:Trace("spells: the game cast " .. tostring(e.name)) end
-- only when the game couldn't be handed the press: in combat, or a passive spell
local function CastFallback(e)
	if e.passive then
		ns:Print(L["%s is passive: there's nothing to cast."]:format(tostring(e.name)))
	elseif InCombatLockdown() then
		ns:Print(L["In combat: Terminal can't cast %s (the game doesn't allow it then)."]:format(tostring(e.name)))
	else
		ns:Trace("spells: no secure button to cast " .. tostring(e.name))
		ns:Print(L["Couldn't cast %s from the terminal."]:format(tostring(e.name)))
	end
end

----------------------------------------------------------------------
-- On your bars or not (is:unplaced; "spells not on my bars")
--
-- A spell is placed when a bar you have holds it (any rank, or a macro casting it), the stance bar has it, or a key is
-- bound to it ("SPELL <name>") or to a macro casting it. Which action slots are bars you have follows Blizzard's own
-- bar code (Forever's ActionButtonUtil.AddPlayerActionBarsContainingSlots): 12 slots a page; pages 1-2 the main bar,
-- 3-6 and 13-15 the side and bottom bars (only when shown: switched on in the settings), 7-10 the stance and form bars
-- (when you have stances or forms: you see each in its own). Not counted: the main bar's first page for a warrior with
-- stances (always in one, so its stance bar shows instead: seen in game, Overpower in slot 8 while in Berserker Stance),
-- and any slot outside those pages (vehicle, override, and slot 181, where Blood Fury sat unseen; the spellbook's own
-- tooltip said "You haven't added this to your action bars"). C_ActionBar.IsOnBarOrSpecialBar counts those hidden
-- slots, so it isn't used. As the spellbook does (Forever's SpellSearchUtil), passive spells and auto attacks (Attack,
-- Shoot, Auto Shot) are never "unplaced"; unlike it, a macro or a key counts, and so does another stance's bar.
----------------------------------------------------------------------

SP.SIDE_BARS = { [3] = "MultiBarRight", [4] = "MultiBarLeft", [5] = "MultiBarBottomRight", [6] = "MultiBarBottomLeft",
	[13] = "MultiBar5", [14] = "MultiBar6", [15] = "MultiBar7" }
SP.KEEP_PLACED = 2 -- (s the names are kept: a bar switched on or off in the settings shows by the next search)
local placedNames, placedAt -- { [lowercase name] = true } (nil: worked out again when asked)

--- Whether an action slot is on a bar you have (see above).
function SP.SlotCounts(slot)
	local page = math.floor((slot - 1) / 12) + 1
	if page == 1 then
		-- (a warrior is always in a stance once he has one: the first page never shows)
		local _, class = Call(_G.UnitClass, "player")
		return not (class == "WARRIOR" and (Call(_G.GetNumShapeshiftForms) or 0) > 0)
	end
	if page == 2 then return true end
	if page >= 7 and page <= 10 then return (Call(_G.GetNumShapeshiftForms) or 0) > 0 end -- (no stances or forms: never shown)
	local bar = SP.SIDE_BARS[page]
	if not bar then return false end
	local f = _G[bar]
	if not (f and f.IsShown) then return true end -- (no such frame here: not judged, counted)
	return Call(f.IsShown, f) and true or false
end

-- the slash words that cast or use something, the game's own (other languages) and English
local castWords
local function CastWords()
	if castWords then return castWords end
	castWords = { cast = true, use = true, castsequence = true, castrandom = true, userandom = true }
	for _, k in ipairs({ "CAST", "USE", "CASTSEQUENCE", "CASTRANDOM", "USERANDOM" }) do
		for i = 1, 8 do
			local w = _G["SLASH_" .. k .. i]
			if type(w) == "string" then castWords[ns.Lower((w:gsub("^/", "")))] = true end
		end
	end
	return castWords
end

--- The spell names a macro's text casts or uses (conditions, "!", "(Rank 3)", castsequence's reset= dropped).
function SP.MacroSpellNames(body, into)
	into = into or {}
	if type(body) ~= "string" or ns.Secret(body) then return into end
	local words = CastWords()
	for line in body:gmatch("[^\n]+") do
		local cmd, args = line:match("^%s*/(%S+)%s+(.+)$")
		if cmd and words[ns.Lower(cmd)] then
			args = args:gsub("%b[]", ""):gsub("reset=%S+", "")
			for part in args:gmatch("[^;,]+") do
				local n = part:gsub("^%s*!?", ""):gsub("%s*%(.-%)%s*$", ""):gsub("%s+$", "")
				if n ~= "" then into[ns.Lower(n)] = true end
			end
		end
	end
	return into
end

local function SpellNameOf(id)
	local n = type(id) == "number" and C_Spell and C_Spell.GetSpellName and Call(C_Spell.GetSpellName, id)
	return (type(n) == "string" and n ~= "" and not Secret(n)) and n or nil
end

-- a macro's spells by its index: what it casts now (GetMacroSpell) and every name its text casts
local function AddMacro(index, into)
	SP.MacroSpellNames(Call(_G.GetMacroBody, index), into)
	local n = SpellNameOf(Call(_G.GetMacroSpell, index))
	if n then into[ns.Lower(n)] = true end
end

--- Every spell name on your bars or keys (lowercase -> true), kept a moment and until something changes.
function SP.PlacedNames()
	local now = GetTime()
	if placedNames and now - (placedAt or 0) < SP.KEEP_PLACED then return placedNames end
	local into = {}
	local used, counted = 0, 0
	for slot = 1, 180 do
		local has = Call(_G.HasAction, slot)
		if has then used = used + 1 end
		if has and SP.SlotCounts(slot) then
			counted = counted + 1
			local kind, id = Call(_G.GetActionInfo, slot)
			if Secret(kind) or Secret(id) then kind = nil end -- (never compared: a secret value errors)
			if kind == "spell" then
				local n = SpellNameOf(id)
				if n then into[ns.Lower(n)] = true end
			elseif kind == "macro" and type(id) == "number" then
				AddMacro(id, into)
			end
		end
	end
	-- the stance bar
	for i = 1, Call(_G.GetNumShapeshiftForms) or 0 do
		local n = SpellNameOf(select(4, Call(_G.GetShapeshiftFormInfo, i)))
		if n then into[ns.Lower(n)] = true end
	end
	-- macros on a key of their own (character macros are numbered from 121)
	local global, perChar = Call(_G.GetNumMacros)
	local function Macro(i)
		local name = Call(_G.GetMacroInfo, i)
		if type(name) == "string" and name ~= "" and not Secret(name) and Call(_G.GetBindingKey, "MACRO " .. name) then AddMacro(i, into) end
	end
	for i = 1, tonumber(global) or 0 do Macro(i) end
	for i = 121, 120 + (tonumber(perChar) or 0) do Macro(i) end
	if used ~= SP.lastUsed or counted ~= SP.lastCounted then -- (traced when the bars change)
		ns:Trace(("spells: %d action slots in use, %d on bars you have (the first page %s)"):format(used, counted,
			SP.SlotCounts(1) and "counted" or "not counted: a warrior is always in a stance"))
	end
	SP.lastUsed, SP.lastCounted = used, counted
	placedNames, placedAt = into, now
	return into
end

-- the auto attack or a ranged one (Attack, Shoot, Auto Shot): the spellbook never calls those missing from your bars
local function AutoAttack(id)
	if type(id) ~= "number" or not C_Spell then return false end
	for i = 1, 2 do
		local f = C_Spell[i == 1 and "IsAutoAttackSpell" or "IsRangedAutoAttackSpell"]
		local yes = f and Call(f, id)
		if not Secret(yes) and yes == true then return true end -- (never compared while secret)
	end
	return false
end

--- A spell you can cast that isn't on any bar you have or a key; false for anything else (passives, auto attacks,
--- other rows).
function SP.Unplaced(e)
	if e.kind ~= "spells" or e.passive or type(e.name) ~= "string" or AutoAttack(e.spellID) then return false end
	if SP.PlacedNames()[ns.Lower(e.name)] then return false end
	if Call(_G.GetBindingKey, "SPELL " .. e.name) then return false end
	return true
end

local placeEvents = CreateFrame("Frame")
SP.placeEvents = placeEvents -- (tests)
for _, ev in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "UPDATE_MACROS", "UPDATE_SHAPESHIFT_FORMS", "SPELLS_CHANGED",
	"PLAYER_ENTERING_WORLD" }) do
	pcall(placeEvents.RegisterEvent, placeEvents, ev)
end
placeEvents:SetScript("OnEvent", function() placedNames = nil end)

-- "spells not on my bars" (both modes; Advanced: @spell is:unplaced): a line of these words, a spell word and one
-- that says "not on a bar" among them; any other words narrow the answer by name ("frost spells not on my bars")
local QUESTION_WORDS = {}
for w in ([[spell spells ability abilities not on my any the action actionbar actionbars bar bars missing from off
	unplaced placed what which show me list all i have are arent isnt is that of keys key keybinds keybind binds hotkeys
	or and yet learned known a]]):gmatch("%a+") do QUESTION_WORDS[w] = true end
local SUBJECT = { spell = true, spells = true, ability = true, abilities = true }

--- The question's words to narrow by ({ ... }, maybe empty), or nil when the line isn't the question.
function SP.Question(text)
	if type(text) ~= "string" or text:find("[@:>|]") or text:find("^%s*[%./]") then return nil end
	local t = " " .. ns.Lower(text):gsub("'", ""):gsub("[%p]", " "):gsub("%s+", " ") .. " "
	local says = t:find(" not on [%a ]-bars? ") or t:find(" arent on [%a ]-bars? ") or t:find(" isnt on [%a ]-bars? ")
		or t:find(" missing from [%a ]-bars? ") or t:find(" off [%a ]-bars? ") or t:find(" unplaced ") or t:find(" not placed ")
	if not says then return nil end
	local subject, rest = false, {}
	for w in t:gmatch("%S+") do
		if SUBJECT[w] then subject = true
		elseif not QUESTION_WORDS[w] then rest[#rest + 1] = w end
	end
	if not subject then return nil end
	return rest
end

--- The answer: the unplaced spells (in the spellbook's order), narrowed by the question's other words; the note.
function SP.Answer(words)
	local p = ns.providers.spells
	local rows = {}
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		if SP.Unplaced(e) then
			local hay = (rawget(e, "_lname") or ns.Lower(e.name)) .. " " .. (rawget(e, "_ltext") or "")
			local ok = true
			for _, w in ipairs(words or {}) do if not hay:find(w, 1, true) then ok = false break end end
			if ok then rows[#rows + 1] = e end
		end
	end
	for i, e in ipairs(rows) do e._score = 1e6 - i end
	local note = L["Spells not on your bars or keys"]
	if #rows == 0 then
		note = (words and #words > 0) and L["None of those spells is off your bars"] or L["Every spell you can cast is on a bar or a key"]
	end
	return rows, note
end

ns:RegisterProvider("spells", {
	label = L["Spell"],
	color = "ff9d7bff",
	aliases = { "spell", "spells", "ability", "abilities", "spellbook" },
	events = { "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_TALENT_UPDATE", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" },
	guard = 2,
	collect = function()
		local out, byName = {}, {}
		for line = 1, (Call(C_SpellBook.GetNumSpellBookSkillLines) or 0) do
			local li = Call(C_SpellBook.GetSpellBookSkillLineInfo, line)
			if type(li) == "table" and not li.shouldHide and type(li.itemIndexOffset) == "number" then
				local tab = (not Secret(li.name)) and li.name or ""
				for slot = li.itemIndexOffset + 1, li.itemIndexOffset + (li.numSpellBookItems or 0) do
					local id, passive, rank = SlotSpell(slot)
					local info = id and Call(C_Spell.GetSpellInfo, id)
					local name = type(info) == "table" and info.name
					if type(name) == "string" and name ~= "" and not Secret(name) then
						-- one row per spell: ranks of it share the name, the highest (listed last) is kept
						local e = byName[name]
						if not e then
							e = { name = name, activate = OpenSpellBook, secure = SP.SECURE, isOpen = IsOpen, after = PointAtSpell,
								getLink = SpellLink } -- (its link made when selected, not per spell on every rebuild)
							byName[name] = e
							out[#out + 1] = e
						end
						local rankText = type(rank) == "string" and rank ~= "" and rank or nil
						-- known by its name: learning a new rank mustn't make it another row (its history kept)
						e.key, e.spellID, e.icon, e.passive, e.line = name, id, info.iconID, passive, line
						e.tab = tab
						e.detail = (passive and (L["Passive"] .. "  ") or "") .. (rankText and (rankText .. "  ") or "") .. tab
						e.text = tab .. (passive and " passive" or "")
						if passive then
							e.secondary, e.secondarySecure, e.secondaryIsOpen, e.secondaryAfter = CastFallback, nil, nil, nil
						else
							e.secondary, e.secondarySecure, e.secondaryIsOpen, e.secondaryAfter = CastFallback, CAST_SPEC, NeverOpen, CastAfter
						end
					end
				end
			end
		end
		return out
	end,
})
