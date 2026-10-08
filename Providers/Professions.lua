local ns = select(2, ...)
local H = ns.Highlight

-- Profession recipe index.
--
-- The profession UI only exposes recipes while a profession window is open, so we
-- snapshot them whenever one opens (and at login, or on demand from the "Index my recipes" result) and keep the result
-- in saved variables, per character. Searching then works any time, window open or not.
--
-- Forever quirks this copes with:
--  * GetProfessions() returns prof1, prof2, first aid, fishing, cooking (with gaps).
--  * The open window's own profession info can come back without a name or with id 0,
--    so the profession is worked out from its recipes' skill line and matched against
--    the player's list instead.
--  * Some returns can be "secret" values, which addon code must not compare.

local P = {}
ns.Professions = P

local function TS() return _G.C_TradeSkillUI end

local Secret, Lower = ns.Secret, ns.Lower -- (Util.lua, Locale.lua: names are compared in every client language)

----------------------------------------------------------------------
-- Storage
----------------------------------------------------------------------

--- The character's own key: its GUID. Name-Realm wasn't unique: characters with the same name
--- on this client's connected realms all report the same realm name, so they shared one index
--- (a Paladin without Fishing was offered his namesake's Fish Bowl).
local function CharKey()
	local g = UnitGUID and UnitGUID("player")
	if type(g) == "string" and g ~= "" and not Secret(g) then return g end
	return (ns.CharacterName() or "?") .. "-" .. (GetRealmName() or "?")
end

local cleaned
local function Store()
	local db = ns.db
	if not db then return nil end
	db.recipes = db.recipes or {}
	local k = CharKey()
	if not cleaned and k:find("^Player%-") then
		-- indexes saved under Name-Realm mix characters of the same name: dropped (each character
		-- indexes its own professions again as their windows open, or from "Index my recipes")
		cleaned = true
		for key in pairs(db.recipes) do
			if type(key) == "string" and not key:find("^Player%-") then db.recipes[key] = nil end
		end
	end
	db.recipes[k] = db.recipes[k] or {}
	return db.recipes[k]
end
P.CharKey = CharKey
P.Store = Store

-- recipes and camp objects come from the index; the professions list doesn't (its own events
-- and skill changes refresh it)
function P.MarkDirty()
	for _, id in ipairs({ "recipes", "camp" }) do
		local p = ns.providers[id]
		if p then p._dirty = true end
	end
end

----------------------------------------------------------------------
-- The player's professions (primary and secondary)
----------------------------------------------------------------------

--- Returns the list, and whether it was read completely (no secret values in the way).
function P.PlayerProfessions()
	local out, complete = {}, true
	if not (GetProfessions and GetProfessionInfo) then return out, false end
	local slots = { GetProfessions() }
	for i = 1, 8 do
		local idx = slots[i]
		if idx ~= nil then
			if Secret(idx) then
				complete = false
			else
				local name, icon, rank, maxRank, numSpells, spellOffset, skillLine = GetProfessionInfo(idx)
				if Secret(name) or Secret(skillLine) or Secret(rank) or Secret(maxRank) then
					complete = false
				elseif type(name) == "string" and name ~= "" then
					out[#out + 1] = {
						name = name, icon = icon,
						rank = tonumber(rank) or 0, maxRank = tonumber(maxRank) or 0,
						skillLine = skillLine,
						numSpells = tonumber(numSpells), spellOffset = tonumber(spellOffset),
					}
				end
			end
		end
	end
	return out, complete
end

--- Profession spells that open a crafting window of their own: Smelting for miners, and
--- Forever's like (skinners' tanning and so on). Same test the game's spellbook uses:
--- C_TradeSkillUI.CanTradeSkillShowCraftingUI(spellID). Opened by casting the spell.
P.tradeSpellNames = {}
function P.TradeSpells()
	local out, seen = {}, {}
	local api = TS()
	if not (api and api.CanTradeSkillShowCraftingUI and C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then return out end
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	local profs = P.PlayerProfessions()
	local profNames = {}
	for _, pr in ipairs(profs) do profNames[Lower(pr.name)] = true end
	local function consider(slot, parent)
		local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
		if not ok or type(info) ~= "table" then return end
		local id = info.spellID or info.actionID
		if not id or Secret(id) or seen[id] then return end
		seen[id] = true
		local okC, can = pcall(api.CanTradeSkillShowCraftingUI, id)
		if not (okC and not Secret(can) and can == true) then return end
		local name = info.name
		if (type(name) ~= "string" or name == "") and C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(id) end
		-- the profession's own spell (Cooking, First Aid) is already listed as the profession
		if type(name) == "string" and name ~= "" and not profNames[Lower(name)] then
			out[#out + 1] = { spellID = id, name = name, icon = info.iconID, parent = parent }
			P.tradeSpellNames[Lower(name)] = true
		end
	end
	for _, pr in ipairs(profs) do
		if pr.spellOffset then
			for slot = pr.spellOffset + 1, pr.spellOffset + math.max(pr.numSpells or 0, 1) do consider(slot, pr.name) end
		end
	end
	if C_SpellBook.GetNumSpellBookSkillLines then -- anywhere else in the book
		for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
			local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
			if type(li) == "table" and li.itemIndexOffset then
				for slot = li.itemIndexOffset + 1, li.itemIndexOffset + (li.numSpellBookItems or 0) do consider(slot, nil) end
			end
		end
	end
	return out
end

--- lowercase recipe name -> { r = recipe, pdata = profession data, profID = key }
function P.NameIndex()
	local idx = {}
	for profID, pdata in pairs(Store() or {}) do
		for _, r in ipairs(pdata.list or {}) do
			-- older saved data may still hold unlearned recipes: never offer those
			if r.learned ~= false then
				local key = Lower(r.name)
				-- the same recipe can be indexed under two windows (Fish Bowl: under Fishing
				-- and under Bait and Tackle); prefer the one a spell can open
				local cur = idx[key]
				if not cur or (not cur.pdata.spell and pdata.spell) then
					idx[key] = { r = r, pdata = pdata, profID = profID }
				end
			end
		end
	end
	return idx
end

--- Index entry for a player profession, by skill line or name.
function P.FindIndexed(pr)
	local lname = Lower(pr.name)
	for key, pdata in pairs(Store() or {}) do
		if (pr.skillLine and (pdata.skillLine == pr.skillLine or key == pr.skillLine))
			or (pdata.name and Lower(pdata.name) == lname) then
			return pdata, key
		end
	end
end

--- Opening a profession window from addon code is a protected action on Forever (the game
--- answers with ADDON_ACTION_BLOCKED and "Interface action failed because of an AddOn").
--- Direct calls are therefore a last resort: tried at most until the game blocks one, then
--- never again (remembered in the saved variables). Returns true if the call went through.
function P.DirectOpen(skillLine)
	local api = TS()
	local db = ns.db
	if not (api and api.OpenTradeSkill and skillLine) then return false end
	if db and db.noDirectOpen then return false end
	local D = ns.Debug
	local before = D and D.count or 0
	ns:Trace("DIRECT OpenTradeSkill(" .. tostring(skillLine) .. ")")
	local ok = pcall(api.OpenTradeSkill, skillLine)
	if D and D.count > before then
		if db then db.noDirectOpen = true end
		return false
	end
	if ok and db and db.noDirectOpen == nil then db.noDirectOpen = false end -- seen to work
	return ok
end

--- Any other protected call (OpenRecipe...): made until the game blocks it once, then never
--- again. Remembered per call name in the saved variables.
function P.Guarded(key, fn, ...)
	local db = ns.db
	if type(fn) ~= "function" then return false end
	if db then
		db.blockedCalls = db.blockedCalls or {}
		if db.blockedCalls[key] then return false end
	end
	local D = ns.Debug
	local before = D and D.count or 0
	ns:Trace("DIRECT " .. key)
	local ok = pcall(fn, ...)
	if D and D.count > before then
		-- a block in combat says nothing about out-of-combat: don't remember it
		if db and not (InCombatLockdown and InCombatLockdown()) then db.blockedCalls[key] = true end
		return false
	end
	return ok
end

--- The spell that opens this profession's crafting window, when casting it does (Cooking,
--- First Aid, Blacksmithing...). Casting is done by the game on Enter (see Secure.lua).
--- Not for professions like Fishing, whose spell does something else.
function P.OpenSpell(name)
	local api = TS()
	if not (name and api and api.CanTradeSkillShowCraftingUI and C_Spell and C_Spell.GetSpellInfo) then return nil end
	local ok, info = pcall(C_Spell.GetSpellInfo, name)
	local id = ok and type(info) == "table" and info.spellID
	if not id or Secret(id) then return nil end
	local ok2, can = pcall(api.CanTradeSkillShowCraftingUI, id)
	if ok2 and can == true then return name end
end

--- The spell that opens a profession's window when it isn't named like the profession (Herbalism's own
--- spell on this client): among the profession's spellbook entries (GetProfessionInfo's spell offset), the
--- one the game says shows a crafting window, the rule the game's own profession book goes by. Its name, or nil.
function P.OpenerSpell(skillLine, name)
	local api = TS()
	if not (api and api.CanTradeSkillShowCraftingUI and C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then return nil end
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	local lname = type(name) == "string" and Lower(name) or nil
	for _, pr in ipairs((P.PlayerProfessions())) do
		if pr.spellOffset and ((skillLine and pr.skillLine == skillLine) or (lname and Lower(pr.name) == lname)) then
			local named -- (its entry named like it: what the game's profession book casts when the test says no)
			for _, sp in ipairs(P.ProfessionSpells(pr)) do
				if sp.canShow then
					ns:Trace(("professions: %s's window opens with %s"):format(pr.name, sp.name))
					return sp.name
				end
				if not named and not sp.passive and Lower(sp.name) == Lower(pr.name) then named = sp.name end
			end
			-- gathering professions given a window on this client (Herbalism): the game may still say its
			-- spell shows no crafting window
			if named then
				ns:Trace(("professions: %s: no entry says it opens a window; using its own %s"):format(pr.name, named))
				return named
			end
			-- else its one active entry that isn't a minimap tracking spell (Herbalism: Find Herbs tracks,
			-- Gardening opens the window)
			local tracking, left = P.TrackingSpells(), {}
			for _, sp in ipairs(P.ProfessionSpells(pr)) do
				if not sp.passive and not tracking[sp.id] then left[#left + 1] = sp end
			end
			if #left == 1 then
				ns:Trace(("professions: %s: its one entry that isn't tracking, %s, opens it"):format(pr.name, left[1].name))
				return left[1].name
			end
		end
	end
end

--- The spells in the minimap's tracking menu (Find Herbs, Find Minerals...), as a set of spell ids.
function P.TrackingSpells()
	local set = {}
	local M = C_Minimap
	if not (M and M.GetNumTrackingTypes and M.GetTrackingInfo) then return set end
	local okN, n = pcall(M.GetNumTrackingTypes)
	for i = 1, (okN and tonumber(n) or 0) do
		local ok, a, _, _, _, _, f = pcall(M.GetTrackingInfo, i)
		local id = ok and (type(a) == "table" and a.spellID or f)
		if type(id) == "number" and not Secret(id) then set[id] = true end
	end
	return set
end

--- A profession's spellbook entries: { name, id, canShow (opens a crafting window, says the game), passive }.
function P.ProfessionSpells(pr)
	local out = {}
	local api = TS()
	if not (pr and pr.spellOffset and C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then return out end
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	for slot = pr.spellOffset + 1, pr.spellOffset + math.max(pr.numSpells or 0, 1) do
		local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
		local id = ok and type(info) == "table" and (info.spellID or info.actionID)
		if id and not Secret(id) then
			local n = info.name
			if (type(n) ~= "string" or n == "") and C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id) end
			if type(n) == "string" and n ~= "" and not Secret(n) then
				local can = false
				if api and api.CanTradeSkillShowCraftingUI then
					local okC, c = pcall(api.CanTradeSkillShowCraftingUI, id)
					can = okC and not Secret(c) and c == true
				end
				local passive = info.isPassive
				out[#out + 1] = { name = n, id = id, slot = slot, canShow = can, passive = (not Secret(passive)) and passive == true }
			end
		end
	end
	return out
end

--- The spell that opens a profession's window: the one you opened it with last time (learned, `opener`),
--- else named like it, else found among its own entries (OpenerSpell); nil when none.
function P.WindowSpell(skillLine, name, pdata)
	if not pdata then
		for _, pd in pairs(Store() or {}) do
			if (skillLine and pd.skillLine == skillLine) or (name and pd.name and Lower(pd.name) == Lower(name)) then pdata = pd break end
		end
	end
	return (pdata and pdata.opener) or P.OpenSpell(name) or P.OpenerSpell(skillLine, name)
end

--- Is this spell one of the profession's own spellbook entries?
function P.IsOwnSpell(skillLine, name, spellName)
	local lname = type(name) == "string" and Lower(name) or nil
	for _, pr in ipairs((P.PlayerProfessions())) do
		if (skillLine and pr.skillLine == skillLine) or (lname and Lower(pr.name) == lname) then
			for _, sp in ipairs(P.ProfessionSpells(pr)) do
				if sp.name == spellName then return true end
			end
		end
	end
	return false
end

-- What you just cast (the game's profession book casts a profession's entry to open its window): when a
-- profession window opens right after, that spell is its opener, kept with its index (`opener`).
P.lastCast = nil
pcall(hooksecurefunc, C_SpellBook, "CastSpellBookItem", function(slot, bank)
	local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
	local n = ok and type(info) == "table" and info.name
	if type(n) == "string" and n ~= "" and not Secret(n) then P.lastCast = { name = n, at = GetTime() } end
end)
-- (cast from an action bar or a key: the same, by the cast itself)
local castWatch = CreateFrame("Frame")
P.castWatch = castWatch
pcall(castWatch.RegisterUnitEvent, castWatch, "UNIT_SPELLCAST_SUCCEEDED", "player")
castWatch:SetScript("OnEvent", function(_, _, unit, _, spellID)
	if unit ~= "player" or type(spellID) ~= "number" or Secret(spellID) then return end
	local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if type(n) == "string" and n ~= "" and not Secret(n) then P.lastCast = { name = n, at = GetTime() } end
end)

--- Drop indexes of professions this character no longer has. Only entries we could tie to
--- the profession list are considered, and only when that list was read completely.
function P.Prune()
	if InCombatLockdown and InCombatLockdown() then return end
	local list, complete = P.PlayerProfessions()
	local store = Store()
	if not store or not complete or #list == 0 then return end
	local lines, names = {}, {}
	for _, pr in ipairs(list) do
		if pr.skillLine then lines[pr.skillLine] = true end
		names[Lower(pr.name)] = true
	end
	for key, pdata in pairs(store) do
		if pdata.fromList and not lines[pdata.skillLine or key] and not names[Lower(pdata.name or "")] then
			store[key] = nil
		end
	end
end

----------------------------------------------------------------------
-- Snapshot
----------------------------------------------------------------------

--- The recipe's reagents ({ { itemID, count }, ... }) and the item it makes (nil for enchants).
local function ReagentsOf(recipeID)
	local api = TS()
	if not api.GetRecipeSchematic then return nil end
	local ok, s = pcall(api.GetRecipeSchematic, recipeID, false)
	if not ok or type(s) ~= "table" then return nil end
	local made = type(s.outputItemID) == "number" and s.outputItemID > 0 and s.outputItemID or nil
	if type(s.reagentSlotSchematics) ~= "table" then return nil, made end
	local out = {}
	for _, slot in ipairs(s.reagentSlotSchematics) do
		local qty = slot.quantityRequired or 1
		for n, rg in ipairs(slot.reagents or {}) do
			if n > 3 then break end -- quality tiers of one reagent: first few are enough
			if rg.itemID then out[#out + 1] = { rg.itemID, qty } end
		end
	end
	return out, made
end

--- Every recipe id the open window offers. On Forever, GetFilteredRecipeIDs (what
--- ClassicUIForever reads) answers where GetAllRecipeIDs can come back empty, so read both.
local function RecipeIDs(api)
	local ids, seen = {}, {}
	for _, fn in ipairs({ "GetAllRecipeIDs", "GetFilteredRecipeIDs" }) do
		if api[fn] then
			local ok, list = pcall(api[fn])
			if ok and type(list) == "table" then
				for _, id in ipairs(list) do
					if not seen[id] and not Secret(id) then
						seen[id] = true
						ids[#ids + 1] = id
					end
				end
			end
		end
	end
	return ids
end
P.RecipeIDs = RecipeIDs

--- Which of the player's professions the open window belongs to.
--- Returns key, name, fromList.
local function ResolveProfession(api, ids)
	local info = api.GetChildProfessionInfo and api.GetChildProfessionInfo()
	if type(info) ~= "table" or not info.professionName or info.professionName == "" or (info.professionID or 0) == 0 then
		info = api.GetBaseProfessionInfo and api.GetBaseProfessionInfo()
	end
	local id, name
	if type(info) == "table" and not Secret(info.professionID) then
		id = (info.parentProfessionID and info.parentProfessionID ~= 0) and info.parentProfessionID or info.professionID
		name = (info.parentProfessionName and info.parentProfessionName ~= "") and info.parentProfessionName or info.professionName
		if id == 0 then id = nil end
		if name == "" then name = nil end
	end

	-- the recipes themselves know their skill line
	local lineID, parentID
	if api.GetTradeSkillLineForRecipe and ids[1] then
		local ok, a, _, c = pcall(api.GetTradeSkillLineForRecipe, ids[1])
		if ok and not Secret(a) then lineID, parentID = a, c end
	end

	local lname = name and Lower(name)
	for _, pr in ipairs((P.PlayerProfessions())) do
		local sl = pr.skillLine
		if (sl and (sl == lineID or sl == parentID or sl == id)) or (lname and Lower(pr.name) == lname) then
			return sl or id, pr.name, true
		end
	end
	-- a scan knows which profession it just opened
	if P.scanning then return P.scanning.skillLine or P.scanning.name, P.scanning.name, true end
	if id and name then return id, name, false end
end

local busy = false

--- Reads every recipe of the profession window that is currently open.
function P.Snapshot(done)
	local function finish()
		busy = false
		P.MarkDirty()
		if done then done() end
	end
	local function skip()
		if done then done() end
	end
	if busy then
		if done then C_Timer.After(1, function() P.Snapshot(done) end) end
		return
	end
	local api = TS()
	if not (api and api.GetRecipeInfo and (api.GetAllRecipeIDs or api.GetFilteredRecipeIDs)) then return skip() end
	-- never index someone else's recipes (linked / guild / NPC crafting windows)
	if (api.IsTradeSkillLinked and api.IsTradeSkillLinked())
		or (api.IsTradeSkillGuild and api.IsTradeSkillGuild())
		or (api.IsNPCCrafting and api.IsNPCCrafting()) then
		return skip()
	end
	local store = Store()
	local ids = RecipeIDs(api)
	if not store or #ids == 0 then return skip() end
	local key, profName, fromList = ResolveProfession(api, ids)
	if not key or not profName then return skip() end

	busy = true
	local list, cats, i = {}, {}, 0
	local step
	local function stepInner()
		local stop = math.min(i + 40, #ids)
		while i < stop do
			i = i + 1
			local id = ids[i]
			local info = api.GetRecipeInfo(id)
			if type(info) == "table" and type(info.name) == "string" and not Secret(info.name) and info.learned ~= false then
				local catName
				if info.categoryID then
					catName = cats[info.categoryID]
					if catName == nil then
						local ci = api.GetCategoryInfo and api.GetCategoryInfo(info.categoryID)
						catName = (type(ci) == "table" and ci.name) or false
						cats[info.categoryID] = catName
					end
				end
				local reagents, made = ReagentsOf(id)
				list[#list + 1] = {
					id = id,
					name = info.name,
					icon = info.icon,
					learned = true, -- only recipes the character knows are kept
					cat = catName or nil,
					reagents = reagents,
					item = made, -- what it makes (stat:/slot: filters on crafts)
					diff = ns.Num(info.relativeDifficulty), -- orange/yellow/green/grey now (is:skillup; Filters.DIFF)
				}
			end
		end
		if i < #ids then
			C_Timer.After(0, step) -- spread the work over a few frames
		else
			-- a window opened by a profession spell (Smelting): keep it apart from its profession
			local spell = P.lastSpell and (GetTime() - P.lastSpell.at) < 6 and P.lastSpell.name or nil
			if not spell and P.tradeSpellNames[Lower(profName)] then spell = profName end
			local parent
			if spell and Lower(spell) ~= Lower(profName) then
				parent = profName
				key, profName, fromList = "spell:" .. spell, spell, false
			elseif spell then
				key, fromList = "spell:" .. spell, false
			end
			P.lastSpell = nil
			-- opened by you from the game (its profession book casting an entry): that spell opens it next time
			local opener = store[key] and store[key].opener
			local cast = not spell and P.lastCast and GetTime() - P.lastCast.at < 5 and P.lastCast.name or nil
			-- only one of the profession's own entries (a spell cast just before, say in a fight, isn't its opener)
			if cast and P.IsOwnSpell(fromList and key or nil, profName, cast) then
				opener = cast
				ns:Trace(("professions: %s's window was opened with %s: kept as its opener"):format(profName, opener))
			end
			P.lastCast = nil
			-- one entry per profession: drop older copies stored under another key
			local lname = Lower(profName)
			local prevCount
			for _, pd in pairs(store) do
				if pd.name and Lower(pd.name) == lname then prevCount = #(pd.list or {}) end
			end
			if not P.scanning and prevCount ~= #list then
				ns:Print(("indexed %s: %d known recipe%s."):format(profName, #list, #list == 1 and "" or "s"))
			end
			for k, pd in pairs(store) do
				if k ~= key and pd.name and Lower(pd.name) == lname then store[k] = nil end
			end
			store[key] = {
				name = profName,
				skillLine = fromList and key or nil,
				fromList = fromList or nil,
				spell = spell,
				opener = opener,
				parent = parent,
				updated = time(),
				list = list,
			}
			finish()
		end
	end
	-- an error part-way must not leave a scan waiting forever
	step = function()
		if not pcall(stepInner) then
			busy = false
			if done then done() end
		end
	end
	step()
end

----------------------------------------------------------------------
-- Opening things
----------------------------------------------------------------------

local Plain = ns.Plain -- (Locale.lua)

--- A clickable row in the profession window whose label is `name` (ClassicUIForever's
--- list may add a count after it, e.g. "Charred Wolf Meat [4]").
local function RecipeRow(root, name)
	return ns.FindFrame(root, function(f)
		if not f.Click then return false end
		local texts = {}
		if f.GetText then
			local ok, t = pcall(f.GetText, f)
			if ok and type(t) == "string" then texts[#texts + 1] = t end
		end
		for _, r in ipairs({ f:GetRegions() }) do
			if r.GetObjectType and r:GetObjectType() == "FontString" then texts[#texts + 1] = r:GetText() end
		end
		for _, t in ipairs(texts) do
			t = Plain(t)
			if t == name or t:sub(1, #name + 1) == name .. " " then return true end
		end
		return false
	end, 16)
end
P.RecipeRow = RecipeRow

-- A login scan keeps the window invisible; make sure nothing else ever inherits that.
local function Unhide()
	local pf = _G.ProfessionsFrame
	if pf and pf.SetAlpha and not P.scanBusy then pf:SetAlpha(1) end
end

local function WindowHas(recipeID)
	local pf = _G.ProfessionsFrame
	if not (pf and pf:IsVisible()) then return false end
	for _, id in ipairs(RecipeIDs(TS())) do
		if id == recipeID then return true end
	end
	return false
end

function P.OpenProfession(skillLine, name)
	ns.LoadBlizz("Blizzard_Professions")
	Unhide()
	if not P.DirectOpen(skillLine) and ToggleProfessionsBook then
		ns:Trace("DIRECT ToggleProfessionsBook")
		ToggleProfessionsBook()
	end
end

--- Opens the recipe's profession (unless that one is already showing), selects the recipe
--- in the list and points at it.
function P.OpenRecipe(recipeID, profID, name)
	ns.LoadBlizz("Blizzard_Professions")
	Unhide()
	local api = TS()
	if not api then return end
	if not WindowHas(recipeID) and profID then P.DirectOpen(profID) end
	P.SelectRecipe(recipeID, name)
end

--- Scrolls the profession window's recipe list to the recipe, so its row exists to click.
--- (C_TradeSkillUI.OpenRecipe would do this, but it's protected in this client: calling it
--- from an addon is always blocked, so it's never called.)
local function ScrollToRecipe(pf, recipeID)
	local page = pf.CraftingPage
	local list = page and page.RecipeList
	local box = list and list.ScrollBox
	if not (box and box.ScrollToElementDataByPredicate) then return false end
	local ok = pcall(box.ScrollToElementDataByPredicate, box, function(node)
		local d = node and node.GetData and node:GetData()
		local info = type(d) == "table" and (d.recipeInfo or d)
		return type(info) == "table" and info.recipeID == recipeID
	end)
	return ok
end
P.ScrollToRecipe = ScrollToRecipe

--- In the open profession window: scroll the list to the recipe and point at it. Only pointed at,
--- never clicked: a click from Terminal's code would leave the window's selected recipe tainted.
function P.SelectRecipe(recipeID, name)
	if not TS() then return end
	ns.PointAtRow({
		frame = function() local pf = _G.ProfessionsFrame; return pf and pf:IsVisible() and pf or nil end,
		find = function(pf) return name and RecipeRow(pf, name) or nil end,
		scroll = function(pf) return ScrollToRecipe(pf, recipeID) end, -- (the row may be further down the list)
		show = function(row) H:Show(row, 6) end,
		tries = 30,
	})
end

----------------------------------------------------------------------
-- Scan: open each profession once so every recipe gets indexed
----------------------------------------------------------------------

--- What to do when the game won't let an addon open profession windows.
function P.ScanHelp()
	local todo = {}
	for _, pr in ipairs((P.PlayerProfessions())) do
		if not P.FindIndexed(pr) and P.OpenSpell(pr.name) then todo[#todo + 1] = pr.name end
	end
	ns:Print("The game doesn't let addons open profession windows, so Terminal can't scan them itself.")
	ns:Print("Every profession is indexed the moment you open it. Search it here (@profession) and press Enter: that opens it the normal way.")
	if #todo > 0 then ns:Print("Not indexed yet: " .. table.concat(todo, ", ") .. ".") end
end

--- quiet: the login scan. The profession window is kept invisible while it's read, and
--- nothing is printed.
function P.Scan(quiet)
	if InCombatLockdown and InCombatLockdown() then
		if not quiet then ns:Print("can't scan professions in combat.") end
		return
	end
	if P.scanBusy then return end
	local list = P.PlayerProfessions()
	if #list == 0 then
		if not quiet then ns:Print("no professions found to scan.") end
		return
	end
	ns.LoadBlizz("Blizzard_Professions")
	local api = TS()
	if not (api and api.OpenTradeSkill) or (ns.db and ns.db.noDirectOpen) then
		if not quiet then P.ScanHelp() end
		return
	end
	local pf = _G.ProfessionsFrame
	local hidden = quiet and pf and pf.SetAlpha and not pf:IsShown()
	P.scanBusy = true
	local i, empty, over = 0, {}, false

	local function finishScan()
		if over then return end
		over = true
		P.scanning = nil
		if api.CloseTradeSkill then pcall(api.CloseTradeSkill) end
		if hidden then pf:SetAlpha(1) end
		P.scanBusy = false
		P.MarkDirty()
		if not quiet then
			local n = 0
			for _, pd in pairs(Store() or {}) do n = n + #(pd.list or {}) end
			ns:Print(("scan finished, %d recipes indexed."):format(n))
			if #empty > 0 then ns:Print("nothing to craft yet in: " .. table.concat(empty, ", ") .. ".") end
		end
	end

	-- A profession with nothing to craft (Mining or Fishing early on) still counts as read.
	local function settle(pr)
		if P.FindIndexed(pr) then return end
		local store = Store()
		if store then
			store[pr.skillLine or pr.name] = { name = pr.name, skillLine = pr.skillLine, fromList = true, updated = time(), list = {} }
		end
		empty[#empty + 1] = pr.name
	end

	if hidden then pf:SetAlpha(0) end
	-- whatever happens, the window is never left invisible
	C_Timer.After(#list * 3 + 10, finishScan)

	local nextProf
	nextProf = function()
		if over then return end
		P.scanning = nil
		i = i + 1
		local pr = list[i]
		if not pr then return finishScan() end
		if not (pr.skillLine and P.DirectOpen(pr.skillLine)) then
			if ns.db and ns.db.noDirectOpen then -- the game refused: nothing was opened, so nothing is "empty"
				if not quiet then P.ScanHelp() end
				return finishScan()
			end
			settle(pr)
			return nextProf()
		end
		C_Timer.After(1.2, function()
			if over then return end
			P.scanning = pr
			local ok = pcall(P.Snapshot, function()
				pcall(settle, pr)
				nextProf()
			end)
			if not ok then
				pcall(settle, pr)
				nextProf()
			end
		end)
	end
	if not quiet then ns:Print(("scanning %d professions..."):format(#list)) end
	nextProf()
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

-- Index every profession quietly a few seconds after logging in (setting: autoScan).
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_ENTERING_WORLD")
login:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		C_Timer.After(6, function()
			if not (ns.Theme and ns.Theme.Get().autoScan) then return end
			if not (ns.db and ns.db.noDirectOpen == false) then return end -- never poke the game's protected opener blind
			if InCombatLockdown() then
				self:RegisterEvent("PLAYER_REGEN_ENABLED") -- wait for the fight to end
			else
				P.Scan(true)
			end
		end)
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		C_Timer.After(2, function() P.Scan(true) end)
	end
end)

local ev = CreateFrame("Frame")
for _, e in ipairs({
	"TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
	"NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED",
}) do
	pcall(ev.RegisterEvent, ev, e)
end
-- Reagent names arrive late (GET_ITEM_INFO_RECEIVED, which fires for everything in the game): listened for
-- only while some are missing, and the list is made again once for the names that came, not on every
-- event. An id asked for twice and still unnamed is given up on (some never come).
P.waitingNames = {} -- item id -> true while its name is awaited
local pendingItems
local function WatchNames(on)
	if on == P.watchingNames then return end
	P.watchingNames = on
	if on then pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED") else pcall(ev.UnregisterEvent, ev, "GET_ITEM_INFO_RECEIVED") end
end
P.WatchNames = WatchNames
local pendingSnap, pendingPrune
ev:SetScript("OnEvent", function(_, event, id)
	if event == "GET_ITEM_INFO_RECEIVED" then
		if id ~= nil and not P.waitingNames[id] then return end -- (someone else's item)
		if id ~= nil then P.waitingNames[id] = nil end
		if not pendingItems then
			pendingItems = true
			C_Timer.After(2, function()
				pendingItems = false
				P.MarkDirty()
			end)
		end
	elseif event == "SKILL_LINES_CHANGED" then
		P.MarkDirty()
		if ns.providers.professions then ns.providers.professions._dirty = true end -- ranks
		if not pendingPrune then
			pendingPrune = true
			C_Timer.After(3, function()
				pendingPrune = false
				P.Prune()
				P.MarkDirty()
			end)
		end
	elseif not pendingSnap and not P.scanBusy then
		pendingSnap = true
		C_Timer.After(1.5, function()
			pendingSnap = false
			P.Snapshot()
		end)
	end
end)

----------------------------------------------------------------------
-- Provider: recipes
----------------------------------------------------------------------

local itemNames = {} -- reagent names already known (asked for every recipe on every rebuild)
local asked = {} -- item id -> times its name was asked of the server (stop after two: some never come)
local function ItemName(id)
	local n = itemNames[id]
	if n then return n end
	n = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if not n then n = C_Item.GetItemInfo(id) end
	if n then
		itemNames[id] = n
		P.waitingNames[id] = nil
	elseif (asked[id] or 0) < 2 then
		asked[id] = (asked[id] or 0) + 1
		P.unresolved = (P.unresolved or 0) + 1
		P.waitingNames[id] = true
		if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
	end
	return n
end

-- shared by every recipe entry (not one set of functions per recipe)
local function RecipeLink(e)
	local api = TS()
	local ok, l = pcall(api.GetRecipeLink, e.recipeID)
	return ok and l or nil
end
local function RecipeActivate(e) P.OpenRecipe(e.recipeID, e.profID, e.name) end
local function RecipeIsOpen(e) return WindowHas(e.recipeID) end
local function RecipeAfter(e)
	if e.profSpell then P.lastSpell = { name = e.profSpell, at = GetTime() } end
	P.SelectRecipe(e.recipeID, e.name)
end
local function RecipeLinkInChat(e) ns.LinkInChat(RecipeLink(e)) end
local RECIPE_CHATBOX = ns.ChatBoxSpec(RecipeLink)
local spellSpecs = {} -- one { spell = } table per profession spell, shared
local function SpellSpec(name)
	local s = spellSpecs[name]
	if not s then s = { spell = name }; spellSpecs[name] = s end
	return s
end

-- the profession window's own colours for a recipe's difficulty (TradeSkillTypeColor in the classic window)
local DIFF_HEX
local function DiffColor(d)
	if type(d) ~= "number" then return nil end
	if not DIFF_HEX then
		local D = ns.Filters.DIFF
		DIFF_HEX = { [D.orange] = "|cffff8040", [D.yellow] = "|cffffff00", [D.green] = "|cff40c040", [D.grey] = "|cff808080" }
	end
	return DIFF_HEX[d]
end

--- castSpell: the spell that opens this profession's window (false: none), once per profession;
--- worked out here when not given.
local function MakeEntry(profID, pdata, r, castSpell)
	if castSpell == nil then castSpell = pdata.spell or P.WindowSpell(pdata.skillLine, pdata.name, pdata) or false end
	castSpell = castSpell or nil
	local parts = { pdata.name, r.cat or "" }
	local lines = {}
	for _, rg in ipairs(r.reagents or {}) do
		local nm = ItemName(rg[1])
		if nm then
			parts[#parts + 1] = nm
			lines[#lines + 1] = rg[2] .. "x " .. nm
		end
	end
	return {
		key = r.id,
		name = r.name,
		icon = r.icon,
		color = r.learned == false and "|cff8a8a8a" or DiffColor(r.diff),
		difficulty = r.diff, -- (is:skillup, is:orange...: as of the window's last read)
		detail = (r.learned == false and "Unlearned  " or "") .. pdata.name,
		text = table.concat(parts, " "),
		tip = #lines > 0 and ("Reagents: " .. table.concat(lines, ", ")) or nil,
		getLink = RecipeLink,
		recipeID = r.id,
		reagents = r.reagents, -- (is:craftable; the index's own table, not a copy)
		makesItem = r.item, -- (filters: the crafted item's stats, slot, item level; nil: asked of the game)
		profID = pdata.skillLine or profID,
		profSpell = pdata.spell,
		activate = RecipeActivate,
		secure = castSpell and SpellSpec(castSpell) or nil,
		isOpen = castSpell and RecipeIsOpen or nil,
		after = castSpell and RecipeAfter or nil,
		-- Shift+Enter: link the recipe in chat
		secondary = RecipeLinkInChat,
		secondarySecure = RECIPE_CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen, -- (the game opens the chat box with it)
	}
end

P.MakeRecipeEntry = MakeEntry

ns:RegisterProvider("recipes", {
	busy = function() return P.scanBusy and "Indexing your professions' recipes" or nil end,
	label = "Recipe",
	color = "ff5fd0c0",
	aliases = { "recipe", "craft", "crafts", "crafting", "reagent" },
	collect = function()
		P.unresolved = 0
		local out, count = {}, 0
		-- every profession indexed for this character, primary or secondary
		for profID, pdata in pairs(Store() or {}) do
			-- only recipes the character knows; also purges unlearned ones older versions saved
			local kept = {}
			for _, r in ipairs(pdata.list or {}) do
				if r.learned ~= false then kept[#kept + 1] = r end
			end
			if #kept ~= #(pdata.list or {}) then pdata.list = kept end
			local castSpell = pdata.spell or P.WindowSpell(pdata.skillLine, pdata.name, pdata) or false
			for _, r in ipairs(kept) do
				count = count + 1
				local isCamp = ns.Camp and ns.Camp.IsCampName(Lower(r.name))
				if not isCamp then out[#out + 1] = MakeEntry(profID, pdata, r, castSpell) end
			end
		end
		WatchNames((P.unresolved or 0) > 0) -- (names still to come: listen for them; none: don't)
		if count == 0 then
			out[1] = {
				key = "scan",
				name = "Index my recipes (scan professions)",
				icon = "Interface\\Icons\\INV_Misc_Note_01",
				detail = "open a profession once to index it",
				text = "recipes crafts crafting professions scan index reagents",
				activate = function() P.Scan() end,
			}
		end
		return out
	end,
})

----------------------------------------------------------------------
-- Provider: professions themselves
----------------------------------------------------------------------

--- A profession's link, listing every recipe you know (what the game's profession book gives on a
--- shift-click: C_SpellBook.GetSpellBookItemTradeSkillLink on its entry, no window needed); for a
--- trade spell's row (Smelting), its own entry's. Else the open window's, when it's that profession's.
local function ProfessionLink(e)
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	local get = C_SpellBook and C_SpellBook.GetSpellBookItemTradeSkillLink
	local pname = e.parentName or e.name
	for _, pr in ipairs((P.PlayerProfessions())) do
		if get and pr.spellOffset and ((e.skillLine and pr.skillLine == e.skillLine) or (pname and pr.name == pname)) then
			for slot = pr.spellOffset + 1, pr.spellOffset + math.max(pr.numSpells or 0, 1) do
				local mine = true
				if e.spellID then -- (a trade spell's row: only its own entry)
					local okI, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
					mine = okI and type(info) == "table" and (info.spellID or info.actionID) == e.spellID
				end
				if mine then
					local ok, link = pcall(get, slot, bank)
					if ok and type(link) == "string" and link ~= "" and not Secret(link) then return link end
				end
			end
		end
	end
	local api = TS()
	if api and api.GetTradeSkillListLink then
		local ok, link = pcall(api.GetTradeSkillListLink)
		if ok and type(link) == "string" and link ~= "" and not Secret(link) and link:find(e.name, 1, true) then return link end
	end
end
P.ProfessionLink = ProfessionLink

-- Shift+Enter: the profession's link (all your recipes) in chat
local PROF_CHATBOX = ns.ChatBoxSpec(function(e) return ProfessionLink(e) end)
local function LinkProfession(e)
	if not ns.LinkInChat(ProfessionLink(e)) then ns:Print("Couldn't link " .. tostring(e.name) .. " in chat.") end
end

local function TradeSpellAfter(e) P.lastSpell = { name = e.name, at = GetTime() } end
local function TradeSpellInCombat(e) ns:Print(e.name .. " can't be opened from the terminal in combat.") end
local function ProfessionActivate(e) P.OpenProfession(e.skillLine, e.name) end

ns:RegisterProvider("professions", {
	label = "Profession",
	color = "ff5fd0c0",
	aliases = { "profession", "prof", "profs" }, -- ("skill" is the Skills tab's, Skills.lua)
	events = { "SPELLS_CHANGED" },
	guard = 2,
	collect = function()
		local out = {}
		for _, ts in ipairs(P.TradeSpells()) do
			out[#out + 1] = {
				key = "spell:" .. ts.spellID,
				name = ts.name,
				icon = ts.icon,
				detail = ts.parent or "Profession",
				text = (ts.parent or "") .. " profession crafting",
				link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(ts.spellID) or nil,
				-- cast through Enter itself (casting is protected), then index what opens
				secure = SpellSpec(ts.name),
				after = TradeSpellAfter,
				activate = TradeSpellInCombat,
				spellID = ts.spellID, parentName = ts.parent,
				shareLink = ProfessionLink, -- (>> guild: the profession's link; not getLink: the tooltip would open the profession)
				secondary = LinkProfession, -- Shift+Enter: that link in chat
				secondarySecure = PROF_CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen,
			}
		end
		for _, pr in ipairs((P.PlayerProfessions())) do
			local opener = P.WindowSpell(pr.skillLine, pr.name)
			out[#out + 1] = {
				key = pr.name,
				name = pr.name,
				icon = pr.icon,
				detail = pr.rank .. " / " .. pr.maxRank,
				skillLine = pr.skillLine,
				shareLink = ProfessionLink, -- (>> guild: the profession's link; not getLink: the tooltip would open the profession)
				secondary = LinkProfession, -- Shift+Enter: that link in chat
				secondarySecure = PROF_CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen, -- (Enter opens its window)
				secure = opener and SpellSpec(opener) or nil,
				activate = ProfessionActivate,
			}
		end
		return out
	end,
})

----------------------------------------------------------------------
-- Terminal commands
----------------------------------------------------------------------

ns:RegisterCommand("profs", {
	desc = "Show which professions are indexed",
	aliases = { "professions" },
	run = function()
		local lines = { "Professions:" }
		for _, pr in ipairs((P.PlayerProfessions())) do
			local pd = P.FindIndexed(pr)
			lines[#lines + 1] = ("  %s %d/%d - %s"):format(pr.name, pr.rank, pr.maxRank,
				pd and (#pd.list .. " recipes indexed") or "not indexed (open it once, or search @recipe and pick Index my recipes)")
		end
		if #lines == 1 then lines[2] = "  none found" end
		return lines
	end,
})

-- .profdebug : what the open profession window reports, for bug reports.
-- Printed to chat as well, so it can be copied.
ns:RegisterCommand("profdebug", {
	desc = "Show what the open profession window reports (for bug reports)",
	run = function()
		local function S(v)
			if Secret(v) then return "<secret>" end
			return tostring(v)
		end
		local api = TS()
		local lines = { "Profession debug (open a profession window first):" }
		if not api then
			lines[2] = "  C_TradeSkillUI is missing in this client"
			return lines
		end
		local function count(fn)
			if not api[fn] then return "missing" end
			local ok, l = pcall(api[fn])
			if not ok then return "error" end
			return type(l) == "table" and tostring(#l) or S(l)
		end
		local function info(fn)
			if not api[fn] then return "missing" end
			local ok, i = pcall(api[fn])
			if not ok or type(i) ~= "table" then return S(i) end
			return ("%s / %s (parent %s / %s)"):format(S(i.professionID), S(i.professionName),
				S(i.parentProfessionID), S(i.parentProfessionName))
		end
		lines[#lines + 1] = "  GetAllRecipeIDs: " .. count("GetAllRecipeIDs") .. "   GetFilteredRecipeIDs: " .. count("GetFilteredRecipeIDs")
		lines[#lines + 1] = "  Base: " .. info("GetBaseProfessionInfo")
		lines[#lines + 1] = "  Child: " .. info("GetChildProfessionInfo")
		local ids = RecipeIDs(api)
		if ids[1] then
			local i1 = api.GetRecipeInfo(ids[1]) or {}
			local line, parent = "?", "?"
			if api.GetTradeSkillLineForRecipe then
				local ok, a, _, c = pcall(api.GetTradeSkillLineForRecipe, ids[1])
				if ok then line, parent = S(a), S(c) end
			end
			lines[#lines + 1] = ("  First recipe: %s  learned=%s  line=%s parent=%s"):format(S(i1.name), S(i1.learned), line, parent)
		end
		-- each profession's spellbook entries, and which spell Terminal opens its window with
		for _, pr in ipairs((P.PlayerProfessions())) do
			local parts = {}
			local tracking = P.TrackingSpells()
			for _, sp in ipairs(P.ProfessionSpells(pr)) do
				parts[#parts + 1] = ("%s #%s%s%s%s"):format(sp.name, S(sp.id), sp.canShow and " [opens window]" or "",
					sp.passive and " (passive)" or "", tracking[sp.id] and " (tracking)" or "")
			end
			lines[#lines + 1] = ("  %s (%s): %s  -> opens with: %s"):format(pr.name, S(pr.skillLine),
				#parts > 0 and table.concat(parts, ", ") or "no entries", S(P.WindowSpell(pr.skillLine, pr.name)))
		end
		local profs = {}
		for _, pr in ipairs((P.PlayerProfessions())) do profs[#profs + 1] = pr.name .. "(" .. S(pr.skillLine) .. ")" end
		lines[#lines + 1] = "  Your professions: " .. (#profs > 0 and table.concat(profs, ", ") or "none")
		local idx = {}
		for _, pd in pairs(Store() or {}) do idx[#idx + 1] = (pd.name or "?") .. "=" .. #(pd.list or {}) end
		lines[#lines + 1] = "  Indexed: " .. (#idx > 0 and table.concat(idx, ", ") or "nothing yet")
		return lines
	end,
})
