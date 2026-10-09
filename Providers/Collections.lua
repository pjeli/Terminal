local ns = select(2, ...)
local H = ns.Highlight

-- Toys, companion pets and titles: what you own, like the mounts (Mounts.lua).
--
-- Everything that uses one or opens a window is pressed by the game: Enter is a line on the secure
-- macro button (/use a toy, summon a pet, set a title), Shift+Enter opens the Collections journal on
-- the toy's or pet's tab with its name in the journal's search box (one /run line, as the Keybindings
-- page is searched in Keybinds.lua), and Terminal only points at it afterwards. Rows are compact
-- (a few hundred toys, a thousand pets): every function here is shared, reading what it needs from
-- the row. A client without the toy box, pet journal or titles has no such @kind.

local Safe, Num, Str = ns.Safe, ns.Num, ns.Str

-- the journal's tabs (COLLECTIONS_JOURNAL_TAB_INDEX_*): 1 mounts, 2 pets, 3 toys
local PETS_TAB, TOYS_TAB = 2, 3

--- A /run line opening the journal on a tab, with `name` typed into that tab's search box (so the
--- row shows whatever page it's on). `box` is the Lua that finds the box; the name is quoted (%q).
--- (SetCollectionsJournalShown loads the journal first; ToggleCollectionsJournal for a client without it)
local JOURNAL = "/run local S=SetCollectionsJournalShown if S then S(true,%d) else ToggleCollectionsJournal(%d) end local B=%s if B then B:SetText(%q) end"
local function JournalMacro(tab, box, name)
	return JOURNAL:format(tab, tab, box, name or "")
end

local NeverOpen = ns.Never -- (always pressed: the search is set even when it's open)

--- Points at the row's name inside a part of the journal once it shows (reading only).
local function PointIn(rootFn, name)
	H:Find(function()
		local root = rootFn()
		return root and root:IsVisible() and ns.FindByText(root, name) or nil
	end)
end

--- Without the game's press (no macro route), or in combat: nothing is opened from here.
local function NoJournal(e)
	ns:Print(InCombatLockdown() and ("In combat: can't open the journal for " .. tostring(e.name) .. " now.")
		or ("Couldn't open the journal for " .. tostring(e.name) .. "."))
end

-- (Mounts.lua, loaded before this file, uses these at run time for the mount journal)
ns.Collections = { JournalMacro = JournalMacro, PointIn = PointIn, NoJournal = NoJournal }

--- "4m", "35s": time left on a cooldown.
local function Left(sec)
	if sec >= 3600 then return ("%dh"):format(math.floor(sec / 3600)) end
	if sec >= 60 then return ("%dm"):format(math.floor(sec / 60)) end
	return ("%ds"):format(math.ceil(sec))
end

--- Runs read() with a journal's filters opened up (collected shown, every type/source/expansion,
--- no search), then puts each back as it was. The journals' C calls list only what passes their
--- filters, so a toy hidden in the journal would be missing here otherwise. Filters are C state
--- (no window is touched); each step is guarded, so a call this client lacks is skipped.
--- spec.flags: { get, set, want, arg }; spec.lists: { count, get, set, all }; spec.search: { text, set }.
local function Widened(spec, read)
	local undo = {}
	for _, f in ipairs(spec.flags or {}) do
		if f.get and f.set then
			local was
			if f.arg ~= nil then was = Safe(f.get, f.arg) else was = Safe(f.get) end
			if type(was) == "boolean" and was ~= f.want then
				if f.arg ~= nil then Safe(f.set, f.arg, f.want) else Safe(f.set, f.want) end
				undo[#undo + 1] = function() if f.arg ~= nil then Safe(f.set, f.arg, was) else Safe(f.set, was) end end
			end
		end
	end
	for _, l in ipairs(spec.lists or {}) do
		local n = l.count and Num(Safe(l.count)) or 0
		if n > 0 and l.get and l.set and l.all then
			local was, off, known = {}, false, true
			for i = 1, n do
				-- (a read that fails leaves the list as it is: putting back a guess would turn a filter off)
				local ok, on = pcall(l.get, i)
				if not ok then known = false break end
				was[i] = on and true or false
				if not was[i] then off = true end
			end
			if off and known then
				Safe(l.all, true)
				undo[#undo + 1] = function() for i = 1, n do if not was[i] then Safe(l.set, i, false) end end end
			end
		end
	end
	local s = spec.search
	local text = s and s.text and s.text()
	if text and text ~= "" and s.set then
		Safe(s.set, "")
		undo[#undo + 1] = function() Safe(s.set, text) end
	end
	local ok, out = pcall(read)
	for i = #undo, 1, -1 do undo[i]() end
	if #undo > 0 then ns:Trace(("collections: %d journal filters opened for the read and put back"):format(#undo)) end
	return ok and out or {}
end

--- A search box's text (the journal's own frame, only read), or nil.
local function BoxText(box)
	if type(box) ~= "table" or not box.GetText then return nil end
	local t = Safe(box.GetText, box)
	return Str(t)
end

----------------------------------------------------------------------
-- Toys (@toy)
----------------------------------------------------------------------

-- Enter uses it: `/use item:<id>` (the game uses toys by item in macros, as by name)
local function ToyMacro(e) return "/use item:" .. e.key end
local function ToyJournalMacro(e)
	return JournalMacro(TOYS_TAB, "ToyBox and ToyBox.searchBox", e.name)
end
local function ToyRoot() local T = _G.ToyBox; return T and (T.iconsFrame or T) end
local function PointAtToy(e) PointIn(ToyRoot, e.name) end
local function NoToy(e) ns:Print("Couldn't use " .. tostring(e.name) .. " from here.") end
local function ToyLink(e)
	local link = C_ToyBox.GetToyLink and Safe(C_ToyBox.GetToyLink, e.key)
	return Str(link) or ("item:" .. e.key)
end

local function ToyDetail(t)
	local parts = {}
	if rawget(t, "fav") then parts[1] = "Favorite" end
	local cd = C_Container and C_Container.GetItemCooldown
	local start, duration = Safe(cd, rawget(t, "key"))
	start, duration = Num(start), Num(duration)
	if start and duration and start > 0 and duration > 1.5 then -- (not the global cooldown)
		local left = start + duration - GetTime()
		if left > 0 then parts[#parts + 1] = "ready in " .. Left(left) end
	end
	return table.concat(parts, "  ")
end

local function ReadToys()
	local T = C_ToyBox
	local out = {}
	local n = Num(Safe(T.GetNumToys)) or 0
	for i = 1, n do
		local id = Num(Safe(T.GetToyFromIndex, i))
		if id and id > 0 and (not PlayerHasToy or Safe(PlayerHasToy, id)) then
			local _, name, icon, fav = Safe(T.GetToyInfo, id)
			name = Str(name)
			if name then out[#out + 1] = { id, name, icon, fav and true or false } end
		end
	end
	return out
end

local TOY_FILTERS
local function ToyFilters()
	if TOY_FILTERS then return TOY_FILTERS end
	local T, PJ = C_ToyBox, C_PetJournal or {}
	TOY_FILTERS = {
		flags = {
			{ get = T.GetCollectedShown, set = T.SetCollectedShown, want = true },
			{ get = T.GetUncollectedShown, set = T.SetUncollectedShown, want = false }, -- (fewer to read)
			{ get = T.GetUnusableShown, set = T.SetUnusableShown, want = true },
		},
		lists = {
			-- (the toy box filters by the pet journal's source list, as its own filter menu does)
			{ count = PJ.GetNumPetSources, get = T.IsSourceTypeFilterChecked, set = T.SetSourceTypeFilter, all = T.SetAllSourceTypeFilters },
			{ count = _G.GetNumExpansions, get = T.IsExpansionTypeFilterChecked, set = T.SetExpansionTypeFilter, all = T.SetAllExpansionTypeFilters },
		},
		search = { text = function() local B = _G.ToyBox; return BoxText(B and B.searchBox) end, set = T.SetFilterString },
	}
	return TOY_FILTERS
end

local toyMeta
if C_ToyBox and C_ToyBox.GetNumToys and C_ToyBox.GetToyFromIndex and C_ToyBox.GetToyInfo then
	ns:RegisterProvider("toys", {
		label = "Toy",
		color = "ff00c8f8",
		aliases = { "toy", "toys" },
		events = { "TOYS_UPDATED", "NEW_TOY_ADDED" },
		guard = 2, selfEvents = true, -- (opening the filters for the read fires TOYS_UPDATED itself)
		collect = function()
			local out = {}
			for _, t in ipairs(Widened(ToyFilters(), ReadToys)) do
				out[#out + 1] = setmetatable({ _compact = true, key = t[1], name = t[2], icon = t[3], fav = t[4] or nil }, toyMeta)
			end
			ns:Trace(("collections: %d toys"):format(#out))
			return out
		end,
	})
	toyMeta = ns:CompactMeta(ns.providers.toys, {
		secure = { macro = ToyMacro },
		activate = NoToy,
		getLink = ToyLink,
		secondary = NoJournal,
		secondarySecure = { macro = ToyJournalMacro },
		secondaryIsOpen = NeverOpen,
		secondaryAfter = PointAtToy,
	}, { detail = ToyDetail })
end

----------------------------------------------------------------------
-- Companion pets (@pet)
----------------------------------------------------------------------

-- Enter summons it (or puts it away, when it's the one out). There's no slash command for one pet
-- (only /randompet), so the line runs the journal's own C call; pressed by the game, it counts as
-- your key press, which summoning needs. A pet's GUID is short: the line stays far under 255.
local function PetMacro(e) return ('/run C_PetJournal.SummonPetByGUID("%s")'):format(e.key) end
local function PetJournalMacro(e)
	-- (the species name: what the journal's search matches)
	return JournalMacro(PETS_TAB, "PetJournalSearchBox or PetJournal and PetJournal.searchBox", e.species or e.name)
end
local function PetRoot() local P = _G.PetJournal; return P and (P.ScrollBox or P.listScroll or P) end
local function PointAtPet(e) PointIn(PetRoot, e.species or e.name) end
local function NoPet(e)
	if not ns.Guarded("SummonPetByGUID", C_PetJournal.SummonPetByGUID, e.key) then
		ns:Print("Couldn't summon " .. tostring(e.name) .. " from here.")
	end
end
local function PetLink(e) return Str(C_PetJournal.GetBattlePetLink and Safe(C_PetJournal.GetBattlePetLink, e.key)) end

local function PetDetail(t)
	local parts = {}
	local level = rawget(t, "level")
	if level and level > 0 then parts[1] = "Lv " .. level end
	local species = rawget(t, "species")
	if species and species ~= rawget(t, "name") then parts[#parts + 1] = species end
	if rawget(t, "fav") then parts[#parts + 1] = "Favorite" end
	local out = C_PetJournal.GetSummonedPetGUID and Safe(C_PetJournal.GetSummonedPetGUID)
	if out and out == rawget(t, "key") then parts[#parts + 1] = "out now (Enter puts it away)" end
	return table.concat(parts, "  ")
end

local function PetRow(out, guid, species, custom, level, fav, icon)
	guid, species = Str(guid), Str(species)
	if not (guid and species) then return end
	out[#out + 1] = { guid, Str(custom) or species, species, Num(level), fav and true or false, icon }
end

local function ReadPetsByIndex()
	local PJ = C_PetJournal
	local out = {}
	local n = Num(Safe(PJ.GetNumPets)) or 0
	for i = 1, n do
		local guid, _, owned, custom, level, fav, revoked, species, icon = Safe(PJ.GetPetInfoByIndex, i)
		if guid and owned ~= false and not revoked then PetRow(out, guid, species, custom, level, fav, icon) end
	end
	return out
end

local PET_FILTERS
local function PetFilters()
	if PET_FILTERS then return PET_FILTERS end
	local PJ = C_PetJournal
	PET_FILTERS = {
		flags = {
			{ get = PJ.IsFilterChecked, set = PJ.SetFilterChecked, arg = _G.LE_PET_JOURNAL_FILTER_COLLECTED or 1, want = true },
			{ get = PJ.IsFilterChecked, set = PJ.SetFilterChecked, arg = _G.LE_PET_JOURNAL_FILTER_NOT_COLLECTED or 2, want = false },
		},
		lists = {
			{ count = PJ.GetNumPetTypes, get = PJ.IsPetTypeChecked, set = PJ.SetPetTypeFilter, all = PJ.SetAllPetTypesChecked },
			{ count = PJ.GetNumPetSources, get = PJ.IsPetSourceChecked, set = PJ.SetPetSourceChecked, all = PJ.SetAllPetSourcesChecked },
		},
		search = { text = function() return BoxText(_G.PetJournalSearchBox) end, set = PJ.SetSearchFilter },
	}
	return PET_FILTERS
end

--- Your pets: by their GUIDs when the client lists them (no journal filters in the way), else
--- through the journal's list with its filters opened up for the read.
local function ReadPets()
	local PJ = C_PetJournal
	local ids = PJ.GetOwnedPetIDs and Safe(PJ.GetOwnedPetIDs)
	if type(ids) == "table" and #ids > 0 and PJ.GetPetInfoByPetID then
		local out = {}
		for _, guid in ipairs(ids) do
			local _, custom, level, _, _, _, fav, species, icon = Safe(PJ.GetPetInfoByPetID, guid)
			PetRow(out, guid, species, custom, level, fav, icon)
		end
		return out
	end
	return Widened(PetFilters(), ReadPetsByIndex)
end

local petMeta
if C_PetJournal and C_PetJournal.SummonPetByGUID and (C_PetJournal.GetOwnedPetIDs or (C_PetJournal.GetNumPets and C_PetJournal.GetPetInfoByIndex)) then
	ns:RegisterProvider("pets", {
		label = "Pet",
		color = "ff60ff40",
		aliases = { "pet", "pets", "battlepet", "companion" },
		events = { "PET_JOURNAL_LIST_UPDATE" },
		guard = 2, selfEvents = true, -- (opening the filters for the read fires it itself)
		lazy = true, -- (a thousand pets: not read for an empty prompt)
		collect = function()
			local out = {}
			for _, p in ipairs(ReadPets()) do
				out[#out + 1] = setmetatable({ _compact = true, key = p[1], name = p[2], species = p[3], level = p[4], fav = p[5] or nil, icon = p[6] }, petMeta)
			end
			ns:Trace(("collections: %d pets"):format(#out))
			return out
		end,
	})
	petMeta = ns:CompactMeta(ns.providers.pets, {
		secure = { macro = PetMacro },
		activate = NoPet,
		getLink = PetLink,
		secondary = NoJournal,
		secondarySecure = { macro = PetJournalMacro },
		secondaryIsOpen = NeverOpen,
		secondaryAfter = PointAtPet,
	}, { detail = PetDetail })
end

----------------------------------------------------------------------
-- Titles (@title)
----------------------------------------------------------------------

-- Enter wears it: SetCurrentTitle(id), on the secure macro button. "No title" is id -1, as in the
-- character window's title list.
local NO_TITLE = -1
local function TitleMacro(e) return "/run SetCurrentTitle(" .. e.key .. ")" end
local function NoTitle(e)
	if not ns.Guarded("SetCurrentTitle", SetCurrentTitle, e.key) then
		ns:Print("Couldn't set the title " .. tostring(e.name) .. " from here.")
	end
end
local function TitleSet(e) ns:Trace("titles: the game set " .. tostring(e.name)) end

local function TitleDetail(t)
	local cur = Num(Safe(GetCurrentTitle)) or 0
	local key = rawget(t, "key")
	if key == cur or (key == NO_TITLE and cur <= 0) then return "Current" end
	return ""
end

local titleMeta
if GetNumTitles and GetTitleName and IsTitleKnown and SetCurrentTitle then
	ns:RegisterProvider("titles", {
		label = "Title",
		color = "fff0f0ff",
		aliases = { "title", "titles" },
		events = { "KNOWN_TITLES_UPDATE", "NEW_TITLE_EARNED" },
		guard = 1,
		collect = function()
			local out = { setmetatable({ _compact = true, key = NO_TITLE, name = ns.GameText("PLAYER_TITLE_NONE", "No title") }, titleMeta) }
			for i = 1, Num(Safe(GetNumTitles)) or 0 do
				if Safe(IsTitleKnown, i) then
					local name = Str(Safe(GetTitleName, i))
					name = name and name:match("^%s*(.-)%s*$") -- ("Private " and " the Explorer" come with a space)
					if name and name ~= "" then out[#out + 1] = setmetatable({ _compact = true, key = i, name = name }, titleMeta) end
				end
			end
			return out
		end,
	})
	titleMeta = ns:CompactMeta(ns.providers.titles, {
		icon = "Interface\\Icons\\INV_Scroll_11",
		secure = { macro = TitleMacro },
		after = TitleSet,
		activate = NoTitle,
	}, { detail = TitleDetail })
end
