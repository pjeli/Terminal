local ns = select(2, ...)
local H = ns.Highlight

-- The recipe and profession rows (@recipe, @profession), made from the index Professions.lua keeps.

local P = ns.Professions
local function TS() return _G.C_TradeSkillUI end
local Secret, Lower = ns.Secret, ns.Lower
local PlayerBank, WindowHas, RecipeIDs = P.PlayerBank, P.WindowHas, P.RecipeIDs
local Store, WatchNames = P.Store, P.WatchNames

----------------------------------------------------------------------
-- Provider: recipes
----------------------------------------------------------------------

local itemNames = {} -- reagent names already known (asked for every recipe on every rebuild)
local asked = {} -- item id -> times its name was asked of the server (stop after two: some never come)
local function ItemName(id)
	local n = itemNames[id]
	if n then return n end
	-- (guarded: a failing or secret answer is no name, and "" is never kept as one)
	n = ns.Str(ns.Safe(C_Item.GetItemNameByID, id)) or ns.Str(ns.Safe(C_Item.GetItemInfo, id))
	if n then
		itemNames[id] = n
		P.waitingNames[id] = nil
	elseif (asked[id] or 0) < 2 then
		asked[id] = (asked[id] or 0) + 1
		P.unresolved = (P.unresolved or 0) + 1
		P.waitingNames[id] = true
		if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
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
	local bank = PlayerBank()
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
		local tracking = P.TrackingSpells()
		for _, pr in ipairs((P.PlayerProfessions())) do
			local parts = {}
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
