local ns = select(2, ...)
local H = ns.Highlight

-- Spells (@spell): every spell in your spellbook.
--   Enter        opens the spellbook on the spell and points at it. The game opens the book (your
--                own Spellbook key, bound to Enter for that press), so nothing runs tainted.
--                ClassicUIForever's classic book: turned to the spell's tab and page, as you would,
--                through the parts its public API (ClassicUIForeverAPI) hands out, and the highest
--                rank shown is pointed at. The game's own book: the press itself turns it there
--                (Blizzard's SpellBookFrame:GoToSpell, run as the game), then Terminal points at it.
--   Shift+Enter  casts it: a /cast line on the secure macro button, pressed by the game. Passive
--                spells can't be cast. In combat Enter can't be handed to the game, so neither works.

local SP = {}
ns.Spells = SP

local BANK = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local ITEM_SPELL = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a = pcall(fn, ...)
	if ok then return a end
end

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
SP.SlotSpell = SlotSpell

--- ClassicUIForever's API when its spellbook stands in for the client's, else nil.
local function CUF()
	local A = _G.ClassicUIForeverAPI
	if type(A) == "table" and type(A.GetFrame) == "function" and Call(A.IsOn, "spellBook") then return A end
end
SP.CUF = CUF

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
-- open = nothing to press. ClassicUIForever's book is turned by Terminal afterwards; the game's own is
-- turned by the press itself, so that one is always pressed (open or not)
local function IsOpen() return CUF() ~= nil and BookOpen() end

--- The game's own spellbook (no ClassicUIForever): the press that opens it also turns it to the spell,
--- with Blizzard's own SpellBookFrame:GoToSpell (the spell's category, then its page), after clearing a
--- search left in its search box (search results hide the categories). All of it runs as the game, from
--- the secure macro button, so nothing in Blizzard's book is written by Terminal's code.
local function ClientBookMacro(e)
	if CUF() or not (_G.PlayerSpellsUtil and e.spellID) then return nil end
	-- (the game cuts a macro off at 255 characters in all, not per line: keep it short)
	return "/run PlayerSpellsUtil.OpenToSpellBookTab()\n"
		.. ("/run local b=PlayerSpellsFrame.SpellBookFrame b:ClearActiveSearchState(true) b:GoToSpell(%d,true)"):format(e.spellID)
end
SP.ClientBookMacro = ClientBookMacro

--- The game's own book (turned by the press): the spell's item there, found by its spellbook slot
--- (only read: its items keep slotIndex/spellBank). The entry's id is its highest rank's.
function SP.ClientButton(book, e)
	local paged = book.PagedSpellsFrame or book
	local slot, bank
	if C_SpellBook.FindSpellBookSlotForSpell then
		local ok, s, b = pcall(C_SpellBook.FindSpellBookSlotForSpell, e.spellID, false, true, false, false)
		if ok then slot, bank = s, b end
	end
	local item = ns.FindFrame(paged, function(f)
		if slot then return f.slotIndex == slot and (bank == nil or f.spellBank == bank) end
		return type(f.spellBookItemInfo) == "table" and f.spellBookItemInfo.spellID == e.spellID
	end, 8)
	if item then return item.Button or item end
end

SP.SECURE = { macro = ClientBookMacro, binding = "TOGGLESPELLBOOK", buttons = { "SpellbookMicroButton" } }

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
	for _ = 1, page - fallbackPage do prev:Click() end
	ns:Trace(("spells: %s (a lower rank shown) on page %d"):format(e.name, fallbackPage))
	return (OnPage(A, book, e))
end

--- After the book opened: turn it to the spell and point at it.
local function PointAtSpell(e)
	local A = CUF()
	ns:Trace("spells: pointing at " .. tostring(e.name) .. (A and " (ClassicUIForever's book)" or " (client book)"))
	local turned, last = false, nil
	H:When(function()
		local book = SP.Book()
		if not book then return nil end
		if A then
			-- turned once; after that only looked at (the highlight's retries don't turn it again)
			if turned then return (OnPage(A, book, e)) end
			turned = true
			return SP.TurnTo(A, book, e)
		end
		-- the game's book, opened by this press, fills its page in over its first frames: point only once the
		-- same frame shows the spell on two looks in a row (a tenth of a second apart)
		local item = SP.ClientButton(book, e)
		if item and item == last then return item end
		last = item
		return nil
	end, function(target) H:Show(target) end, 25, function()
		-- for a .debug log: which step found nothing
		local book = SP.Book()
		local slot = C_SpellBook.FindSpellBookSlotForSpell and Call(C_SpellBook.FindSpellBookSlotForSpell, e.spellID, false, true, false, false)
		ns:Trace(("spells: gave up pointing at %s (book shown: %s, its slot: %s, frame found: %s)"):format(
			tostring(e.name), book and "yes" or "no", tostring(slot), tostring(book and SP.ClientButton(book, e) ~= nil)))
	end)
end
SP.PointAtSpell = PointAtSpell

-- Without the secure route (no binding, no button): try the book's own openers.
local function OpenSpellBook(e)
	local A = CUF()
	if A then
		Call(A.Open, "spellBook")
	else
		ns:Print("Couldn't open your spellbook from the terminal. Press your Spellbook key.")
		return
	end
	PointAtSpell(e)
end

-- Shift+Enter: cast it. The game presses the /cast line (Terminal's own code can't cast).
local function CastMacro(e) return not e.passive and ("/cast " .. e.name) or nil end
local CAST_SPEC = { macro = CastMacro }
local function NeverOpen() return false end -- nothing to open first: always pressed
local function CastAfter(e) ns:Trace("spells: the game cast " .. tostring(e.name)) end
-- only when the game couldn't be handed the press: in combat, or a passive spell
local function CastFallback(e)
	if e.passive then
		ns:Print(tostring(e.name) .. " is passive: there's nothing to cast.")
	elseif InCombatLockdown() then
		ns:Print("In combat: Terminal can't cast " .. tostring(e.name) .. " (the game doesn't allow it then).")
	else
		ns:Trace("spells: no secure button to cast " .. tostring(e.name))
		ns:Print("Couldn't cast " .. tostring(e.name) .. " from the terminal.")
	end
end

ns:RegisterProvider("spells", {
	label = "Spell",
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
							e = { name = name, activate = OpenSpellBook, secure = SP.SECURE, isOpen = IsOpen, after = PointAtSpell }
							byName[name] = e
							out[#out + 1] = e
						end
						local rankText = type(rank) == "string" and rank ~= "" and rank or nil
						e.key, e.spellID, e.icon, e.passive, e.line = id, id, info.iconID, passive, line
						e.link = Call(C_Spell.GetSpellLink, id)
						e.tab = tab
						e.detail = (passive and "Passive  " or "") .. (rankText and (rankText .. "  ") or "") .. tab
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
