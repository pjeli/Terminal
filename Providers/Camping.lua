local ns = select(2, ...)
local H = ns.Highlight
local P = ns.Professions

-- WoW Forever camping: Cooking makes campfires, every other profession makes camp
-- objects that give buffs to anyone sitting at the fire. Names, tiers and buffs come
-- from community guides and may shift during the beta, so whether you actually KNOW an
-- object is always read from your own indexed recipes, never from this table.

local GREEN = "|cff40ff40"

-- profession, { tier 1, tier 2, tier 3 }, tier-1 buff, class buff it overlaps with
local OBJECTS = {
	{ "Alchemy", { "Mana Well", "Fermenter", "Alchemy Laboratory" }, "Mana regeneration", "Blessing of Wisdom" },
	{ "Blacksmithing", { "Sharpening Wheel", "Anvil", "Master Forge" }, "Strength", "Strength of Earth Totem" },
	{ "Enchanting", { "Enchanted Lute", "Arcane Salvager", "Arcane Forge" }, "Armor, stats and resistances", "Mark of the Wild" },
	{ "Engineering", { "Reagent Bot", "Repair Bot", "Anarchist's Workbench" }, "Reagent vendor and repairs", nil },
	{ "Herbalism", { "Incense Candle", "Greenhouse", "Seed Hybridizer" }, "Intellect", "Arcane Intellect" },
	{ "Leatherworking", { "Camp Tent", "Tanning Rack", "Sewing Machine" }, "Rested experience (up to 5% of a level)", nil },
	{ "Mining", { "Lodestone", "Rock Garden", "Molten Foundry" }, "Melee attack power", "Blessing of Might" },
	{ "Skinning", { "Camp Chair", "Field Guide", "Trapper's Workbench" }, "2% critical strike chance", "Moonkin Form" },
	{ "Tailoring", { "Faction Banner", "Spinning Wheel", "Loom" }, "Spirit", "Divine Spirit" },
	{ "First Aid", { "First Aid Kit", "Toxin Study", "Plague Doctor's Laboratory" }, "Stamina", "Power Word: Fortitude" },
	{ "Fishing", { "Fish Bowl", "Fishing Rack", "Fishing Hut" }, "8% increased stats", "Blessing of Kings" },
}
local TIER_SKILL = { 20, 140, 300 }

-- name, cooking skill, note, extra search words
local COOKING = {
	{ "Basic Campfire", 1, "Holds 3 camp features", "simple wood flint tinder" },
	{ "Journeyman Campfire", 90, "Holds 5 camp features", "" },
	{ "Expert Campfire", 200, "Holds 10 camp features", "" },
	{ "Iron Oven", 300, "Unlocks advanced camp recipes", "" },
	{ "Cookie's Feast", nil, "Cooking camp object", "food feast" },
}

local ALL, BYNAME = {}, {}

local function Add(def)
	def.lname = def.name:lower()
	ALL[#ALL + 1] = def
	BYNAME[def.lname] = def
end

for _, o in ipairs(OBJECTS) do
	for tier, name in ipairs(o[2]) do
		local tip = { o[1] .. " camp object, tier " .. tier }
		if tier == 1 then
			tip[#tip + 1] = "Buff: " .. o[3]
			if o[4] then tip[#tip + 1] = "Doesn't stack with: " .. o[4] end
		else
			tip[#tip + 1] = "Higher tiers need a Blueprint recipe (dungeon boss drops)."
		end
		tip[#tip + 1] = "Sit or craft near the campfire for a minute for an hour-long buff."
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
		tip = "Cooking camp object\n" .. c[3] .. "\nCampfires fade after roughly 10-15 minutes.",
	})
end

ns.Camp = {
	IsCampName = function(lname) return BYNAME[lname] ~= nil end,
}

----------------------------------------------------------------------
-- Status of each object, from the player's own indexed recipes
----------------------------------------------------------------------

local function Status(def, idx, have, haveAny)
	local hit = idx[def.lname]
	if hit then
		if hit.r.learned then return "Known", hit end
		return "Not learned", hit
	end
	if haveAny and not have[def.prof:lower()] then return "No " .. def.prof, nil end
	return "Not scanned", nil
end

ns:RegisterProvider("camp", {
	label = "Camp",
	color = "ffff9040",
	aliases = { "camp", "camping", "campfire", "campsite" },
	collect = function()
		local idx = P.NameIndex()
		local have = P.ProfessionNameSet()
		local haveAny = next(have) ~= nil
		local out = {}
		for _, def in ipairs(ALL) do
			local status, hit = Status(def, idx, have, haveAny)
			if status == "Known" then -- only camp objects you can actually make
			local label = def.prof
			if def.tier then label = label .. " T" .. def.tier end
			if def.skill then label = label .. " (" .. def.skill .. ")" end
			local e = {
				key = def.name,
				name = def.name,
				icon = (hit and hit.r.icon) or "Interface\\Icons\\INV_Misc_Spyglass_03",
				color = status == "Known" and GREEN or nil,
				detail = label .. " - " .. status,
				text = def.text,
				tip = def.tip,
				def = def,
				hit = hit,
				activate = function(e)
					if e.hit then
						P.OpenRecipe(e.hit.r.id, e.hit.profID, e.name)
					else
						local pr = have[e.def.prof:lower()]
						if pr then
							P.OpenProfession(pr.skillLine, e.name)
							ns:Print(e.name .. " isn't in your recipe index yet. Open the " .. e.def.prof .. " window, or run .scan.")
						else
							ns:Print(e.name .. " is a " .. e.def.prof .. " camp object, and you don't have that profession.")
						end
					end
				end,
			}
			-- opened like its recipe: the profession it's in (e.g. Bait and Tackle) is cast on
			-- Enter by the game, then the recipe is selected and pointed at
			if hit and hit.pdata and P.MakeRecipeEntry then
				local re = P.MakeRecipeEntry(hit.profID, hit.pdata, hit.r)
				e.recipeID, e.profID = re.recipeID, re.profID
				e.secure, e.isOpen, e.after = re.secure, re.isOpen, re.after
				e.secondary = re.secondary
				e.getLink = re.getLink
			end
			out[#out + 1] = e
			end
		end
		return out
	end,
})

----------------------------------------------------------------------
-- .camp : one line per profession
----------------------------------------------------------------------

ns:RegisterCommand("camp", {
	desc = "Which camp objects you can make",
	aliases = { "camping", "campfire" },
	run = function()
		local idx = P.NameIndex()
		local have = P.ProfessionNameSet()
		local haveAny = next(have) ~= nil
		local byProf, order = {}, {}
		for _, def in ipairs(ALL) do
			if not byProf[def.prof] then
				byProf[def.prof] = {}
				order[#order + 1] = def.prof
			end
			table.insert(byProf[def.prof], def)
		end
		local lines = { "Camp objects you know:" }
		for _, prof in ipairs(order) do
			local known, scanned, owned = {}, false, (not haveAny) or have[prof:lower()] ~= nil
			for _, def in ipairs(byProf[prof]) do
				local status = Status(def, idx, have, haveAny)
				if status == "Known" then known[#known + 1] = def.name end
				if status ~= "Not scanned" and not status:find("^No ") then scanned = true end
			end
			local text
			if not owned then
				text = "profession not learned"
			elseif #known > 0 then
				text = table.concat(known, ", ")
			elseif scanned then
				text = "none yet"
			else
				text = "not scanned (open it or .scan)"
			end
			lines[#lines + 1] = ("  %s: %s"):format(prof, text)
		end
		return lines
	end,
})
