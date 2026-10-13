local ns = select(2, ...)
local L = ns.L
local P = ns.Professions

-- WoW Forever camping: Cooking makes campfires, every other profession makes camp
-- objects that give buffs to anyone sitting at the fire. Names, tiers and buffs come
-- from community guides and may shift during the beta, so whether you actually KNOW an
-- object is always read from your own indexed recipes, never from this table.

local GREEN = "|cff40ff40"

-- profession, { tier 1, tier 2, tier 3 }, tier-1 buff, class buff it overlaps with
local OBJECTS = {
	{ "Alchemy", { "Mana Well", "Fermenter", "Alchemy Laboratory" }, L["Mana regeneration"], "Blessing of Wisdom" },
	{ "Blacksmithing", { "Sharpening Wheel", "Anvil", "Master Forge" }, L["Strength"], "Strength of Earth Totem" },
	{ "Enchanting", { "Enchanted Lute", "Arcane Salvager", "Arcane Forge" }, L["Armor, stats and resistances"], "Mark of the Wild" },
	{ "Engineering", { "Reagent Bot", "Repair Bot", "Anarchist's Workbench" }, L["Reagent vendor and repairs"], nil },
	{ "Herbalism", { "Incense Candle", "Greenhouse", "Seed Hybridizer" }, L["Intellect"], "Arcane Intellect" },
	{ "Leatherworking", { "Camp Tent", "Tanning Rack", "Sewing Machine" }, L["Rested experience (up to 5%% of a level)"]:format(), nil },
	{ "Mining", { "Lodestone", "Rock Garden", "Molten Foundry" }, L["Melee attack power"], "Blessing of Might" },
	{ "Skinning", { "Camp Chair", "Field Guide", "Trapper's Workbench" }, L["2%% critical strike chance"]:format(), "Moonkin Form" },
	{ "Tailoring", { "Faction Banner", "Spinning Wheel", "Loom" }, L["Spirit"], "Divine Spirit" },
	{ "First Aid", { "First Aid Kit", "Toxin Study", "Plague Doctor's Laboratory" }, L["Stamina"], "Power Word: Fortitude" },
	{ "Fishing", { "Fish Bowl", "Fishing Rack", "Fishing Hut" }, L["8%% increased stats"]:format(), "Blessing of Kings" },
}
local TIER_SKILL = { 20, 140, 300 }

-- name, cooking skill, note, extra search words
local COOKING = {
	{ "Basic Campfire", 1, L["Holds 3 camp features"], "simple wood flint tinder" },
	{ "Journeyman Campfire", 90, L["Holds 5 camp features"], "" },
	{ "Expert Campfire", 200, L["Holds 10 camp features"], "" },
	{ "Iron Oven", 300, L["Unlocks advanced camp recipes"], "" },
	{ "Cookie's Feast", nil, L["Cooking camp object"], "food feast" },
}

local ALL, BYNAME = {}, {}

local function Add(def)
	def.lname = ns.Lower(def.name) -- (the recipe index's keys are made the same way)
	ALL[#ALL + 1] = def
	BYNAME[def.lname] = def
end

for _, o in ipairs(OBJECTS) do
	for tier, name in ipairs(o[2]) do
		local tip = { L["%s camp object, tier %s"]:format(o[1], tier) }
		if tier == 1 then
			tip[#tip + 1] = L["Buff: %s"]:format(o[3])
			if o[4] then tip[#tip + 1] = L["Doesn't stack with: %s"]:format(o[4]) end
		else
			tip[#tip + 1] = L["Higher tiers need a Blueprint recipe (dungeon boss drops)."]
		end
		tip[#tip + 1] = L["Sit or craft near the campfire for a minute for an hour-long buff."]
		Add({
			name = name, prof = o[1], tier = tier, skill = TIER_SKILL[tier],
			text = table.concat({ o[1], "camp camping campfire", tier == 1 and o[3] or "", tier == 1 and (o[4] or "") or "" }, " "),
			tip = table.concat(tip, "\n"),
		})
	end
end
for _, c in ipairs(COOKING) do
	Add({
		name = c[1], prof = "Cooking", skill = c[2],
		text = "cooking camp camping campfire fire " .. c[4],
		tip = L["Cooking camp object"] .. "\n" .. c[3] .. "\n" .. L["Campfires fade after roughly 10-15 minutes."],
	})
end

ns.Camp = {
	IsCampName = function(lname) return BYNAME[lname] ~= nil end,
}

----------------------------------------------------------------------
-- Provider
----------------------------------------------------------------------

-- only camp objects you can actually make are listed; Enter opens their recipe, Shift+Enter uses one from your
-- bags or makes it
local function OpenCamp(e) P.OpenRecipe(e.hit.r.id, e.hit.profID, e.name) end

--- The camp object's item (what its recipe makes), or nil: kept at indexing, else asked of the game.
local function CampItem(e)
	local F = ns.Filters
	return F and F.ItemOf and F.ItemOf({ recipeID = e.recipeID, makesItem = e.hit and e.hit.r.item }) or nil
end

local function InBags(e)
	local id = CampItem(e)
	local count = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	if not count then return false end
	local ok, n = pcall(count, id or e.name)
	return ok and type(n) == "number" and n > 0
end

-- Shift+Enter: use it when you have one in your bags (as a right-click there), else make it: the window's
-- own craft (C_TradeSkillUI.CraftRecipe, which needs the window), the window opened first on the same press
-- when it isn't (casting a recipe by name with no window doesn't work here). A window opening on that press
-- may not be ready to craft yet: the next Shift+Enter, with it open, crafts.
local function CampMacro(e)
	if InBags(e) then
		e._campUse = true
		local id = CampItem(e)
		return id and ("/use item:" .. id) or ("/use " .. e.name)
	end
	e._campUse = false
	if not e.recipeID then return nil end
	-- (Shift+Enter hands a view whose secure/isOpen are its own: the recipe's are kept apart)
	local open = e.recipeIsOpen and e.recipeIsOpen(e)
	-- the window's own way of crafting (seen to work; it needs the window). Without the window, the same press
	-- opens it first (the profession's window spell, as Enter does). A recipe can't be cast by name here (tried)
	local craft = ("/run C_TradeSkillUI.CraftRecipe(%d,1)"):format(e.recipeID)
	local spell = type(e.recipeSecure) == "table" and e.recipeSecure.spell
	if open or not spell then return craft end
	return "/cast " .. spell .. "\n" .. craft
end
local CAMP_SPEC = { macro = CampMacro }
local CampNeverOpen = ns.Never
local function CampAfter(e)
	if e._campUse then
		ns:Trace("camp: the game used " .. tostring(e.name))
	else
		ns:Trace("camp: the game was asked to make " .. tostring(e.name) .. " (its window opened first if it wasn't)")
		if e.recipeAfter then e.recipeAfter(e) end -- (its recipe selected and pointed at in the window)
	end
end
-- only when the game couldn't be handed the press (in combat, no secure button)
local function CampFallback(e)
	if InCombatLockdown() then
		ns:Print(L["In combat: Terminal can't use or make %s now."]:format(tostring(e.name)))
	else
		ns:Print(L["Couldn't use or make %s from the terminal."]:format(tostring(e.name)))
	end
end

ns:RegisterProvider("camp", {
	label = L["Camp"],
	color = "ffff9040",
	aliases = { "camp", "camping", "campfire", "campsite" },
	collect = function()
		local idx = P.NameIndex()
		local out = {}
		for _, def in ipairs(ALL) do
			local hit = idx[def.lname]
			if hit and hit.r.learned then
				local label = def.prof
				if def.tier then label = L["%s T%s"]:format(label, def.tier) end
				if def.skill then label = label .. " (" .. def.skill .. ")" end
				local e = {
					key = def.name,
					name = def.name,
					icon = hit.r.icon or "Interface\\Icons\\INV_Misc_Spyglass_03",
					color = GREEN,
					detail = label .. "  ·  " .. L["Known"],
					text = def.text,
					tip = def.tip,
					hit = hit,
					activate = OpenCamp,
				}
				-- opened like its recipe: the profession it's in (e.g. Bait and Tackle) is cast on
				-- Enter by the game, then the recipe is selected and pointed at
				if hit.pdata and P.MakeRecipeEntry then
					local re = P.MakeRecipeEntry(hit.profID, hit.pdata, hit.r)
					e.recipeID, e.profID = re.recipeID, re.profID
					-- (0.49.2, review: the window's names too: RecipeIsOpen matches a trade spell's window (Bait and
					-- Tackle, keyed "spell:...") or one whose info says id 0 only by them, and RecipeAfter reads profSpell.
					-- Without them an open window counted as closed: Enter's /cast shut it, Shift+Enter's toggled it)
					e.profName, e.profWindow, e.profSpell = re.profName, re.profWindow, re.profSpell
					e.secure, e.isOpen, e.after = re.secure, re.isOpen, re.after
					e.recipeSecure, e.recipeIsOpen, e.recipeAfter = re.secure, re.isOpen, re.after
					e.getLink = re.getLink
					e.secondary, e.secondarySecure, e.secondaryIsOpen, e.secondaryAfter = CampFallback, CAMP_SPEC, CampNeverOpen, CampAfter
				end
				out[#out + 1] = e
			end
		end
		return out
	end,
})
