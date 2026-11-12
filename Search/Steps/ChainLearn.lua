local ns = select(2, ...)
local L = ns.L

-- The `learn` relation of the chains: where a recipe is learned ("where to learn thorium belt", <recipe> > learn).
-- The rows and the other relations are Chains.lua's, loaded just before this (1.4.2: one file until then).

local P = ns.Pipes
local Safe, Pressed = ns.Safe, ns.Bags.Pressed
local Entries, ItemOf, ItemName, Icon, AtlasCraft = P._.Entries, P._.ItemOf, P._.ItemName, P._.Icon, P._.AtlasCraft
local LootIndex, OwnRecipes, StoredByID, SOURCE_LABEL = P._.LootIndex, P._.OwnRecipes, P._.StoredByID, P._.SOURCE_LABEL
local ShowItem, View, NearSaid, AddQuestie = P._.ShowItem, P._.View, P._.NearSaid, P._.AddQuestie

----------------------------------------------------------------------
-- learn: where a recipe is learned. The game doesn't say: this client's profession window lists recipes you don't know,
-- but C_TradeSkillUI.GetRecipeSourceText gives nothing for them (the player's probe). So: AtlasLoot's recipe items (its
-- Data.Recipe: [Plans: Thorium Belt] teaches the spell; GetRecipeForSpell is the reverse) and where to get that item
-- (Questie, AtlasLoot's bosses, your alts); a craft AtlasLoot knows with no recipe item is taught by a trainer, said
-- with that evidence, and the nearest trainers of its profession Questie knows (a trainer whose rank tops out below the
-- skill the recipe needs left out).
----------------------------------------------------------------------

-- AtlasLoot's profession numbers: the word trainer: takes, the skill line
P.AL_PROFS = {
	[1] = { "firstaid", 129, "First Aid" }, [2] = { "blacksmithing", 164, "Blacksmithing" },
	[3] = { "leatherworking", 165, "Leatherworking" }, [4] = { "alchemy", 171, "Alchemy" }, [5] = { "herbalism", 182, "Herbalism" },
	[6] = { "cooking", 185, "Cooking" }, [7] = { "mining", 186, "Mining" }, [8] = { "tailoring", 197, "Tailoring" },
	[9] = { "engineering", 202, "Engineering" }, [10] = { "enchanting", 333, "Enchanting" }, [11] = { "fishing", 356, "Fishing" },
	[12] = { "skinning", 393, "Skinning" }, [14] = { "jewelcrafting", 755, "Jewelcrafting" }, [15] = { "inscription", 773, "Inscription" },
}
-- the highest skill a trainer of each rank teaches (classic's ranks; a title with none of these: kept)
P.RANK_CAP = { { "grand master", 450 }, { "master", 375 }, { "artisan", 300 }, { "expert", 225 }, { "journeyman", 150 },
	{ "apprentice", 75 } }
P.TRAINERS = 5 -- (the nearest ones listed)

local function AtlasRecipes()
	local AL = _G.AtlasLoot
	local D = AL and AL.Data
	return D and D.Recipe, D and D.Profession
end

--- The craft a row stands for: its spell, the item it makes, the recipe item (when the row is one); nil when neither
--- your recipes nor AtlasLoot say.
function P.LearnOf(e)
	local id = ItemOf(e)
	-- (a recipe you know, or one you don't yet: MissingRecipes.lua)
	if (e.kind == "recipes" or e.kind == "missing") and type(e.recipeID) == "number" then return e.recipeID, id, e.recipeItem end
	if not id then return nil end
	local Rc = AtlasRecipes()
	if Rc and Rc.IsRecipe and Safe(Rc.IsRecipe, id) then
		local d = Safe(Rc.GetRecipeData, id)
		if type(d) == "table" and type(d[3]) == "number" and d[3] ~= 0 then return d[3], nil, id end
	end
	local own = OwnRecipes()[id]
	if own and type(own.recipeID) == "number" then return own.recipeID, id end
	local _, spell = AtlasCraft(id)
	if spell then return spell, id end
	return nil
end

-- a profession's name in the game's words (the English one when the client doesn't say)
local function ProfName(prof)
	local f = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
	local n = f and Safe(f, prof[2])
	if type(n) == "string" and n ~= "" and not (ns.Secret and ns.Secret(n)) then return n end
	return prof[3]
end
P.ProfName = ProfName -- (an AL_PROFS entry's name: OneForAll's skinning, fishing and disenchanting sources)

--- AtlasLoot's profession entry (P.AL_PROFS) for a skill line, or for a profession's name (the game's or English).
function P.ProfOfLine(line)
	if type(line) ~= "number" then return nil end
	for _, pr in pairs(P.AL_PROFS) do if pr[2] == line then return pr end end
end
function P.ProfOfName(name)
	if type(name) ~= "string" then return nil end
	local ln = ns.Lower(name)
	for _, pr in pairs(P.AL_PROFS) do
		if ns.Lower(pr[3]) == ln or ns.Lower(ProfName(pr)) == ln then return pr end
	end
end

local function RankCap(title)
	for _, r in ipairs(P.RANK_CAP) do if title:find(r[1], 1, true) then return r[2] end end
end

-- the NPC list's trainers of a profession friendly to you, made once per list
local trainersOf = { list = nil, by = {} }
local function Trainers(word)
	local p, F = ns.providers.npc, ns.Filters
	if not (p and F and F.Parse) then return {} end
	local list = ns:GetEntries(p)
	local busy = p.busy and p.busy()
	if busy then P.loading = true; F.loading = true end -- (Questie's NPCs still being read: asked again once they're in)
	if trainersOf.list ~= list then trainersOf.list, trainersOf.by = list, {} end
	-- (trainer:class and trainer:pet are whose class asks, !t's asker's too: kept per class)
	local key = word
	if word == "class" or word == "pet" then key = word .. ":" .. tostring(F._ and F._.MyClass and F._.MyClass() or "") end
	local got = trainersOf.by[key]
	if got then return got end
	got = {}
	local isTrainer, friendly = F.Parse("trainer:" .. word), F.Parse("faction:friendly")
	if isTrainer then
		for _, e in ipairs(list) do
			if Safe(isTrainer, e) and (not friendly or Safe(friendly, e)) then got[#got + 1] = e end
		end
	end
	if not busy and #list > 0 then trainersOf.by[key] = got end
	return got
end
P.Trainers = Trainers -- (What's Training's spells: trainer:class, trainer:pet; WhereToLearn.lua)
P.ForgetTrainers = function() trainersOf.list, trainersOf.by = nil, {} end -- (tests)

-- the nearest trainers who teach up to `need`, as rows saying so
local function AddTrainers(out, prof, need)
	local I = ns.Integrations
	local here = I and I.Here and I.Here() or nil
	local list = {}
	local FP = ns.Filters and ns.Filters._ -- (P is this file's ns.Pipes)
	for _, e in ipairs(Trainers(prof[1])) do
		local id = e.npcID or rawget(e, "key")
		-- (the title as Questie's base data says it, English, even where QuestieDB translates titles: the ranks are English;
		-- a row that isn't an NPC row by its kind, its own title or its NPC's)
		local title = (FP and FP.EnglishTitle and FP.EnglishTitle(e)) or rawget(e, "sub") or (I and I.NpcField and I.NpcField(id, "subName")) or ""
		local cap = type(title) == "string" and RankCap(ns.Lower(title)) or nil
		if not (cap and need and cap < need) then
			local d = here and I.NpcDistance and I.NpcDistance(id, here) or nil
			list[#list + 1] = { e = e, d = d, title = title }
		end
	end
	table.sort(list, function(a, b)
		if (a.d ~= nil) ~= (b.d ~= nil) then return a.d ~= nil end
		if a.d and b.d and a.d ~= b.d then return a.d < b.d end
		return tostring(a.e.name) < tostring(b.e.name)
	end)
	for i = 1, math.min(#list, P.TRAINERS) do
		local t = list[i]
		local rest = L["Teaches it"] .. (t.title ~= "" and (ns.DETAIL_SEP .. t.title) or "")
		out[#out + 1] = NearSaid(View(t.e, rest, nil, L["taught by"]), t.d, rest)
	end
end

-- the recipe item: where to get it (Questie, AtlasLoot's bosses, your alts)
local function AddRecipeItem(out, rid, prof, need, stored)
	local skill = prof and need and (ns.DETAIL_SEP .. ProfName(prof) .. " " .. need) or ""
	out[#out + 1] = Pressed({ key = "recipe:" .. rid, kind = "source", kindLabel = SOURCE_LABEL, name = ItemName(rid) or L["item %d"]:format(rid),
		itemID = rid, link = "item:" .. rid, icon = Icon(rid), detail = L["Teaches it"] .. skill, pipeHow = L["taught by"] }, ShowItem)
	local I = ns.Integrations
	local from = #out + 1
	if I and I.ItemField then AddQuestie(out, I, rid, P.RECIPE_WORDS) end
	-- (a vendor's window showed it in limited supply there, or always in stock: MissingRecipes.lua keeps what it saw)
	local MR = ns.MissingRecipes
	for k = from, #out do
		local v = out[k]
		local nid = v.pipeHow == P.RECIPE_WORDS.sold and (v.npcID or rawget(v, "key") or v.key)
		local lim = nid and MR and MR.Limited(rid, nid)
		if lim ~= nil then
			local say = ns.DETAIL_SEP .. (lim and L["limited supply"] or L["always in stock"])
			rawset(v, "detail", v.detail .. say)
			if rawget(v, "nearRest") then rawset(v, "nearRest", v.nearRest .. say) end -- (kept when the distance updates)
		end
	end
	local by = LootIndex()
	for k, l in ipairs(by[rid] or {}) do
		if k > 15 then break end
		out[#out + 1] = l
	end
	if stored[rid] then out[#out + 1] = View(stored[rid], L["Your alts hold the recipe"] .. ns.DETAIL_SEP .. tostring(stored[rid].detail or "")) end
end

ns:RegisterRelation("learn", {
	aliases = { "learned", "taught", "teach", "teaches", "trainer", "trainers", "recipesource" },
	desc = L["where to learn the recipe: its recipe item, or a trainer"],
	applies = function(e) return P.LearnOf(e) ~= nil end,
	run = function(rows)
		local _, Pr = AtlasRecipes()
		local Rc = AtlasRecipes()
		local stored = StoredByID()
		local out = {}
		for _, e in ipairs(rows) do
			local spell, made, rid = P.LearnOf(e)
			local data = Pr and Pr.GetProfessionData and Safe(Pr.GetProfessionData, spell)
			data = type(data) == "table" and data or nil
			local prof = data and P.AL_PROFS[data[2]] or nil
			local need = data and tonumber(data[3]) or nil
			made = made or (data and data[1]) or nil
			-- you know it already: said first
			local own = (e.kind == "recipes" and e) or (made and OwnRecipes()[made]) or nil
			if own then out[#out + 1] = View(own, L["You know it"] .. (own.detail and (ns.DETAIL_SEP .. own.detail) or "")) end
			rid = rid or (Rc and Rc.GetRecipeForSpell and Safe(Rc.GetRecipeForSpell, spell)) or nil
			if type(rid) == "number" then
				AddRecipeItem(out, rid, prof, need, stored)
			else
				-- AtlasLoot knows the craft but no recipe item for it, or a trainer's window listed it: a trainer
				-- teaches it (what it costs, when a trainer's window showed it: MissingRecipes.lua)
				local MR = ns.MissingRecipes
				local sname = (e.kind == "recipes" or e.kind == "missing") and e.name
					or (C_Spell and C_Spell.GetSpellName and Safe(C_Spell.GetSpellName, spell)) or e.name
				local seen = MR and MR.TrainerFor(sname)
				if data or seen then
					prof = prof or P.ProfOfLine(e.profLine) or (seen and P.ProfOfName(seen.skill)) or nil
					need = need or (seen and seen.rank) or nil
					local pname = prof and ProfName(prof) or nil
					local why = (seen and seen.cost) and (L["costs %s"]:format(ns.Money(seen.cost))
						.. (seen.who and (" " .. L["(seen at %s)"]:format(seen.who)) or "")) or L["No recipe item teaches it (AtlasLoot)"]
					out[#out + 1] = { key = "trainer:" .. spell, kind = "source", kindLabel = SOURCE_LABEL, noActivate = true,
						name = pname and L["Taught by a %s trainer"]:format(pname) or L["Taught by a trainer"],
						icon = "Interface\\Icons\\INV_Misc_Book_11",
						detail = why .. (pname and need and (ns.DETAIL_SEP .. L["learn at %s %s"]:format(pname, need)) or "") }
					if prof then AddTrainers(out, prof, need) end
				end
			end
		end
		return out
	end,
})

-- alts: who holds an item on your alts, in banks, the mail...
ns:RegisterRelation("alts", {
	aliases = { "stored", "who", "bank", "holders" },
	desc = L["who holds it on your alts and banks"],
	applies = function(e) return ItemOf(e) ~= nil and e.kind ~= "stored" and e.kind ~= "shared" end,
	run = function(rows)
		local by = StoredByID()
		-- (and your friends' bags, .ssh: Ssh.lua's @shared)
		local shared = {} -- (an item a friend: each friend's row)
		for _, e in ipairs(Entries("shared")) do
			if e.itemID then
				shared[e.itemID] = shared[e.itemID] or {}
				table.insert(shared[e.itemID], e)
			end
		end
		local out = {}
		for _, e in ipairs(rows) do
			local id = ItemOf(e)
			if by[id] then out[#out + 1] = by[id] end
			for _, s in ipairs(shared[id] or {}) do out[#out + 1] = s end
		end
		return out
	end,
})
