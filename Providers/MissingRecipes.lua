local ns = select(2, ...)

-- Recipes you don't have yet, and where to learn them (0.45.14, the player's ask). "blacksmithing recipes i'm missing"
-- (both modes; Advanced: @recipe is:unknown) lists every recipe of your professions you don't know, each with the skill
-- it needs and how it's learned; "recipes i can learn now" (is:learnable) keeps those your skill already allows.
--
-- What you don't know is the game's own answer: its profession window lists the recipes you haven't learned too, and
-- Professions.lua keeps them (`unknown`) as it indexes a window; one learned since is told by IsPlayerSpell. So a
-- profession whose window hasn't been opened since this came in can't be listed yet: the note says to open it.
-- How each is learned, and where that's from (each said in the tooltip):
-- - a trainer and its cost: what a trainer's window showed you (its services' names, costs and skill needed are kept
--   when you open one: `db.recipeTrainers`); a craft AtlasLoot knows with no recipe item is a trainer's too (its cost
--   not seen yet)
-- - its recipe item (AtlasLoot's Data.Recipe): sold by Questie's vendors (limited supply as a vendor's window showed
--   it: `db.recipeVendors`), dropped by Questie's NPCs and AtlasLoot's bosses, a quest's reward, found in an object
-- - the skill it needs: AtlasLoot's (the craft's, else its recipe item's), else what a trainer showed
-- Enter on one is "where to learn <it>" (the learn chain: the nearest trainers, the vendors on the map).

local MR = {}
ns.MissingRecipes = MR

local Safe, Lower, Str, Num, Secret = ns.Safe, ns.Lower, ns.Str, ns.Num, ns.Secret

-- the professions with recipes to list (a window of their own: gathering ones have none, Mining's is Smelting)
MR.CRAFTING = { [171] = true, [164] = true, [333] = true, [202] = true, [165] = true, [197] = true, [755] = true,
	[773] = true, [185] = true, [129] = true, [186] = true }

----------------------------------------------------------------------
-- What trainers and vendors showed you
----------------------------------------------------------------------

-- the NPC a unit is (its id in its GUID: "Creature-0-1-2-3-<id>-...")
local function NpcOf(unit)
	local g = UnitGUID and Safe(UnitGUID, unit)
	if type(g) ~= "string" or Secret(g) then return nil end
	return tonumber(g:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)") or g:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end
MR.NpcOf = NpcOf

local function Db(field)
	local db = ns.db
	if not db then return nil end
	db[field] = db[field] or {}
	return db[field]
end

local function Dirty()
	local p = ns.providers.missing
	if p then p._dirty = true end
end

--- Reads the open trainer's window: each service's cost and the skill it needs, by its name (a recipe's name is the
--- spell's). Only a profession trainer's (a class trainer's spells aren't recipes). How many were kept.
function MR.ReadTrainer()
	if type(_G.IsTradeskillTrainer) == "function" and Safe(_G.IsTradeskillTrainer) == false then return 0 end
	local n = Num(Safe(_G.GetNumTrainerServices)) or 0
	local seen = Db("recipeTrainers")
	if not seen or n == 0 then return 0 end
	local npc, who = NpcOf("npc"), Str(Safe(_G.UnitName, "npc"))
	local kept = 0
	for i = 1, n do
		local name, kind = Safe(_G.GetTrainerServiceInfo, i)
		name, kind = Str(name), Str(kind)
		if name and kind ~= "header" then
			local cost = Num(Safe(_G.GetTrainerServiceCost, i))
			local skill, rank = Safe(_G.GetTrainerServiceSkillReq, i)
			seen[Lower(name)] = { cost = cost, skill = Str(skill), rank = Num(rank), npc = npc, who = who, t = time() }
			kept = kept + 1
		end
	end
	ns:Trace(("recipes to learn: %s's trainer window: %d services kept"):format(tostring(who), kept))
	if kept > 0 then Dirty() end
	return kept
end

-- is it a recipe item (the game's item class, else AtlasLoot's recipe list)?
local function IsRecipeItem(id)
	local get = C_Item and C_Item.GetItemInfoInstant or _G.GetItemInfoInstant
	if get then
		local _, _, _, _, _, classID = Safe(get, id)
		local recipeClass = Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
		if classID == recipeClass then return true end
	end
	local AL = _G.AtlasLoot
	local Rc = AL and AL.Data and AL.Data.Recipe
	return Rc and Rc.IsRecipe and Safe(Rc.IsRecipe, id) and true or false
end

--- Reads the open vendor's window: each recipe item on sale, whether its supply is limited, and its price, by the
--- vendor. How many were kept.
function MR.ReadMerchant()
	local npc = NpcOf("npc")
	local n = Num(Safe(_G.GetMerchantNumItems)) or 0
	local seen = Db("recipeVendors")
	if not (npc and seen) or n == 0 then return 0 end
	local kept = 0
	for i = 1, n do
		local id = Num(Safe(_G.GetMerchantItemID, i))
		if id and IsRecipeItem(id) then
			local price, avail
			local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and Safe(C_MerchantFrame.GetItemInfo, i)
			if type(info) == "table" then
				price, avail = Num(info.price), Num(info.numAvailable)
			else
				local _, _, p, _, a = Safe(_G.GetMerchantItemInfo, i)
				price, avail = Num(p), Num(a)
			end
			if avail then
				local by = seen[id] or {}
				seen[id] = by
				-- (-1: as many as you like; 0 and up: limited supply, 0 when sold out for now)
				by[npc] = { limited = avail >= 0, price = price, t = time() }
				kept = kept + 1
			end
		end
	end
	if kept > 0 then
		ns:Trace(("recipes to learn: vendor %d sells %d recipe items"):format(npc, kept))
		Dirty()
	end
	return kept
end

--- What a trainer's window said of a recipe (by its name): { cost, skill, rank, who, t }, or nil.
function MR.TrainerFor(name)
	local seen = ns.db and ns.db.recipeTrainers
	return type(name) == "string" and seen and seen[Lower(name)] or nil
end

--- Whether a vendor's window showed the recipe item in limited supply at that vendor (nil: not seen there).
function MR.Limited(itemID, npcID)
	local seen = ns.db and ns.db.recipeVendors
	local r = seen and seen[itemID] and seen[itemID][npcID]
	if r then return r.limited and true or false end
	return nil
end

local events = CreateFrame("Frame")
MR.events = events -- (tests)
for _, ev in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do pcall(events.RegisterEvent, events, ev) end
events:SetScript("OnEvent", function(_, ev)
	-- (a moment later: the window fills in after it shows)
	local read = (ev == "TRAINER_SHOW" or ev == "TRAINER_UPDATE") and MR.ReadTrainer or MR.ReadMerchant
	C_Timer.After(0.2, function() pcall(read) end)
end)

----------------------------------------------------------------------
-- The list
----------------------------------------------------------------------

local function AtlasData()
	local AL = _G.AtlasLoot
	local D = AL and AL.Data
	return D and D.Recipe, D and D.Profession
end

-- learned since the window was read? (a recipe is its spell)
local function KnownNow(id, known)
	if known[id] then return true end
	local f = _G.IsPlayerSpell or (C_SpellBook and C_SpellBook.IsSpellKnown)
	return f and Safe(f, id) == true or false
end

local function Coins(c) return ns.Gold and ns.Gold.Text and ns.Gold.Text(c) or (tostring(c) .. "c") end

-- how a recipe is learned, as far as the data says: { trainer = record or true, rid, vendors = {ids}, limited,
-- drops = {ids}, bosses = {loot rows}, quests = {ids}, objects = {ids} }
local function Sources(id, name, data, rid)
	local s = { rid = rid }
	s.trainerSeen = MR.TrainerFor(name)
	if rid then
		local I = ns.Integrations
		if I and I.ItemField then
			local function List(field) local l = I.ItemField(rid, field) return type(l) == "table" and l or {} end
			s.vendors, s.drops, s.quests, s.objects = List("vendors"), List("npcDrops"), List("questRewards"), List("objectDrops")
		end
		local P = ns.Pipes
		s.bosses = P and P.LootRowsOf and P.LootRowsOf(rid) or {}
		for _, v in ipairs(s.vendors or {}) do if MR.Limited(rid, v) then s.limited = true break end end
	elseif data or s.trainerSeen then
		s.trainer = true -- (AtlasLoot knows the craft, no recipe item teaches it; or a trainer's window listed it)
	end
	if s.trainerSeen then s.trainer = true end
	return s
end

-- the words for how: "Trainer 1s 50c", "Vendor (limited supply)", "Drop", "Quest reward", "Found"
local function HowText(s)
	local parts = {}
	if s.trainer then parts[#parts + 1] = "Trainer" .. ((s.trainerSeen and s.trainerSeen.cost) and (" " .. Coins(s.trainerSeen.cost)) or "") end
	if s.vendors and #s.vendors > 0 then parts[#parts + 1] = "Vendor" .. (s.limited and " (limited supply)" or "") end
	if (s.drops and #s.drops > 0) or (s.bosses and #s.bosses > 0) then parts[#parts + 1] = "Drop" end
	if s.quests and #s.quests > 0 then parts[#parts + 1] = "Quest reward" end
	if s.objects and #s.objects > 0 then parts[#parts + 1] = "Found" end
	if #parts == 0 then return s.rid and "Its recipe item: where to get it isn't known" or "How it's learned isn't known" end
	return table.concat(parts, "  ·  ")
end

local function WalkLearn(e)
	local P = ns.Pipes
	local t = P and P.Phrase and P.Phrase(e.name, "learn") or e.name
	if ns.UI and ns.UI.SetQuery then ns.UI:SetQuery(t, #t) end
end
local function SpellLink(e)
	local f = C_Spell and C_Spell.GetSpellLink or _G.GetSpellLink
	local l = f and Safe(f, e.recipeID)
	return type(l) == "string" and l ~= "" and not Secret(l) and l or nil
end
local function LinkInChat(e) ns.LinkInChat(SpellLink(e) or e.name) end
local CHATBOX -- (made once ns.ChatBoxSpec is there: below)

local GREY = "|cff8a8a8a"

--- The tooltip: the skill it needs (against yours), then each way it's learned and where that's from.
function MR.Tooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	if e.need then
		local ok = e.rank and e.rank >= e.need
		t:AddLine(("Requires %s %d (you have %d)"):format(e.profName, e.need, e.rank or 0), 1, ok and 1 or 0.3, ok and 1 or 0.3)
	else
		t:AddLine(e.profName .. ": the skill it needs isn't known", 0.62, 0.62, 0.62)
	end
	local s = e.sources or {}
	local I = ns.Integrations
	local function NpcName(id) local r = I and I.NpcRow and I.NpcRow(id) return r and r.name or ("NPC " .. id) end
	if s.trainer then
		local ts = s.trainerSeen
		if ts and ts.cost then
			t:AddLine("Trainer: " .. Coins(ts.cost) .. (ts.who and ("  (seen at " .. ts.who .. ")") or ""), 1, 1, 1, true)
		else
			t:AddLine("Trainer: no recipe item teaches it (AtlasLoot); its cost shows once you open a trainer's window", 1, 1, 1, true)
		end
	end
	if s.rid then
		local nm = C_Item and C_Item.GetItemNameByID and Str(Safe(C_Item.GetItemNameByID, s.rid))
		t:AddLine("Its recipe: " .. (nm or ("item " .. s.rid)) .. "  (AtlasLoot)", 1, 1, 1, true)
		for k, v in ipairs(s.vendors or {}) do
			if k > 4 then t:AddLine(("  +%d more vendors"):format(#s.vendors - 4), 0.62, 0.62, 0.62) break end
			local lim = MR.Limited(s.rid, v)
			t:AddLine("  Sold by " .. NpcName(v) .. (lim and "  ·  limited supply" or (lim == false and "  ·  always in stock" or "")), 1, 1, 1)
		end
		for k, l in ipairs(s.bosses or {}) do
			if k > 3 then break end
			t:AddLine("  Drops from " .. ns.Plain(tostring(l.detail or "")):gsub("%s%s+", " in ", 1), 1, 1, 1)
		end
		if s.drops and #s.drops > 0 then
			t:AddLine(#s.drops <= 2 and ("  Drops from " .. NpcName(s.drops[1]) .. (s.drops[2] and (", " .. NpcName(s.drops[2])) or ""))
				or ("  Drops from %d kinds of creature"):format(#s.drops), 1, 1, 1)
		end
		for k, q in ipairs(s.quests or {}) do
			if k > 2 then break end
			local row = I and I.QuestRow and I.QuestRow(q)
			t:AddLine("  A reward from " .. (row and row.name or ("quest " .. q)), 1, 1, 1)
		end
		if s.objects and #s.objects > 0 then t:AddLine("  Found in an object (a chest, a crate)", 1, 1, 1) end
		if s.vendors and #s.vendors > 0 and s.limited == nil and not MR.AnySeen(s) then
			t:AddLine("Limited supply or not shows once you open a vendor's window", 0.62, 0.62, 0.62, true)
		end
	end
	if not s.trainer and not s.rid then t:AddLine("How it's learned isn't known: AtlasLoot doesn't list it", 0.62, 0.62, 0.62, true) end
	t:AddLine("Enter: where to learn it", 0.62, 0.62, 0.62)
end

--- Has a vendor's window shown this recipe item at any of its vendors?
function MR.AnySeen(s)
	for _, v in ipairs(s.vendors or {}) do if MR.Limited(s.rid, v) ~= nil then return true end end
	return false
end

local function Row(u, pd, pr, Rc, Pr)
	local id = u.id
	local data = Pr and Pr.GetProfessionData and Safe(Pr.GetProfessionData, id)
	data = type(data) == "table" and data or nil
	local rid = Rc and Rc.GetRecipeForSpell and Safe(Rc.GetRecipeForSpell, id)
	rid = type(rid) == "number" and rid or nil
	local s = Sources(id, u.name, data, rid)
	local need = data and Num(data[3])
	if not need and rid then
		local d = Rc.GetRecipeData and Safe(Rc.GetRecipeData, rid)
		need = type(d) == "table" and Num(d[2]) or nil
	end
	if not need and s.trainerSeen then need = s.trainerSeen.rank end
	if need and need <= 0 then need = nil end
	local can = need ~= nil and (pr.rank or 0) >= need
	local how = HowText(s)
	local lhow = Lower(ns.Plain(how))
	return {
		key = id, name = u.name, icon = u.icon, recipeID = id, makesItem = u.item,
		profName = pr.name, profLine = pr.skillLine, rank = pr.rank, need = need, canLearn = can or nil,
		sources = s, recipeItem = rid,
		color = (not can) and GREY or nil,
		detail = pr.name .. (need and (" " .. need) or "") .. "  ·  " .. how,
		text = table.concat({ pr.name, pd.name ~= pr.name and pd.name or "", "recipe missing unknown unlearned to learn", lhow }, " "),
		activate = WalkLearn, staysOpen = true,
		tooltip = MR.Tooltip, getLink = SpellLink,
		secondary = LinkInChat, secondarySecure = CHATBOX, secondaryIsOpen = ns.Never,
	}
end

--- The rows: every recipe the windows of your professions listed that you don't know. Also `MR.notListed`: your
--- crafting professions with no such list yet (their window not opened since).
function MR.Rows()
	local P = ns.Professions
	local store = P and P.Store and P.Store() or {}
	local profs = P and P.PlayerProfessions and P.PlayerProfessions() or {}
	local byLine, byName = {}, {}
	for _, pr in ipairs(profs) do
		if pr.skillLine then byLine[pr.skillLine] = pr end
		byName[Lower(pr.name)] = pr
	end
	local known = {}
	local rp = ns.providers.recipes
	for _, r in ipairs(rp and ns:GetEntries(rp) or {}) do if r.recipeID then known[r.recipeID] = true end end
	local Rc, Pr = AtlasData()
	local out, seen, listed = {}, {}, {}
	for _, pd in pairs(store) do
		local pr = (pd.skillLine and byLine[pd.skillLine]) or (pd.name and byName[Lower(pd.name)]) or (pd.parent and byName[Lower(pd.parent)])
		if pr and type(pd.unknown) == "table" then
			listed[pr.name] = true
			for _, u in ipairs(pd.unknown) do
				if type(u) == "table" and u.id and type(u.name) == "string" and not seen[u.id] and not KnownNow(u.id, known) then
					seen[u.id] = true
					out[#out + 1] = Row(u, pd, pr, Rc, Pr)
				end
			end
		end
	end
	MR.notListed = {}
	for _, pr in ipairs(profs) do
		if not listed[pr.name] and MR.CRAFTING[pr.skillLine or 0] then MR.notListed[#MR.notListed + 1] = pr.name end
	end
	return out
end

ns:RegisterProvider("missing", {
	label = "Recipe to learn",
	color = "ff9ec9b4", -- (a grey of the recipes' mint)
	aliases = { "missing", "tolearn", "missingrecipe", "missingrecipes" },
	explicit = true, -- (only asked for: "recipes i'm missing", @recipe is:unknown)
	lazy = true,
	-- (a skill gained, a recipe learned: what you can learn now changes)
	events = { "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_SKILL_LINE" }, -- (Forever's names)
	guard = 1,
	collect = function()
		CHATBOX = CHATBOX or ns.ChatBoxSpec(function(e) return SpellLink(e) or e.name end)
		return MR.Rows()
	end,
})

----------------------------------------------------------------------
-- In plain words: "blacksmithing recipes i'm missing", "recipes i don't know", "recipes i can learn now"
----------------------------------------------------------------------

local SUBJECT = { recipe = true, recipes = true, pattern = true, patterns = true, plans = true, formula = true,
	formulas = true, schematic = true, schematics = true, design = true, designs = true, manual = true, manuals = true }
-- (not "need": "recipes that need copper bar" is what uses it)
local MISSING = { missing = true, miss = true, unknown = true, unlearned = true, dont = true, havent = true, lack = true,
	learn = true, learnable = true, new = true, yet = true, still = true }
local ASK = {}
for w in ([[i im my me the a an all any every what which show list do dont know have havent got get yet learned learn
	learnt can could now to still are that is there for of in still left more new need missing miss unknown unlearned lack
	learnable available i'd ive is are profession professions]]):gmatch("%S+") do ASK[w] = true end

-- your profession a word names ("blacksmithing", "blacksmith", "smithing"...: its name holds the word, 4 letters or more)
local function ProfWord(w, profs)
	if #w < 4 then return nil end
	for _, pr in ipairs(profs) do
		local ln = Lower(pr.name)
		if ln:find(w, 1, true) or w:find(ln:sub(1, math.min(#ln, 6)), 1, true) then return pr.name end
	end
end

--- The question: { profs = { names }, words = the words narrowing it by name, learnable = only those your skill
--- allows }, or nil when the line isn't it.
function MR.Question(text)
	if type(text) ~= "string" or text:find("[@:>|]") or text:find("^%s*[%./!%-]") then return nil end
	local t = Lower(text):gsub("'", ""):gsub("[%p]", " ")
	local subject, cue, can, now, words = false, false, false, false, {}
	local list = {}
	for w in t:gmatch("%S+") do list[#list + 1] = w end
	for _, w in ipairs(list) do
		if SUBJECT[w] then subject = true end
		if MISSING[w] then cue = true end
		if w == "can" or w == "could" or w == "learnable" or w == "available" then can = true end
		if w == "now" then now = true end
	end
	if not (subject and cue) then return nil end
	local P = ns.Professions
	local profs = P and P.PlayerProfessions and P.PlayerProfessions() or {}
	local q = { profs = {}, words = {} }
	-- "recipes i can learn (now)", "learnable recipes", "recipes available to learn"
	local hasLearn = false
	for _, w in ipairs(list) do if w == "learn" or w == "learnable" or w == "available" then hasLearn = true end end
	q.learnable = (can and hasLearn) or (now and hasLearn) or nil
	for _, w in ipairs(list) do
		if not SUBJECT[w] and not ASK[w] then
			local pn = ProfWord(w, profs)
			if pn then q.profs[#q.profs + 1] = pn else q.words[#q.words + 1] = w end
		end
	end
	return q
end

-- easiest first: the skill needed (none known last), then the name
local function Order(a, b)
	if (a.need ~= nil) ~= (b.need ~= nil) then return a.need ~= nil end
	if a.need and b.need and a.need ~= b.need then return a.need < b.need end
	if a.profName ~= b.profName then return tostring(a.profName) < tostring(b.profName) end
	return tostring(a.name) < tostring(b.name)
end

--- The answer: the rows the question wants, easiest first, and the footer's note.
function MR.Answer(q)
	q = q or {}
	local p = ns.providers.missing
	local rows, noSkill, nextUp = {}, 0, nil
	local wantProf = {}
	for _, n in ipairs(q.profs or {}) do wantProf[n] = true end
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		local ok = (not next(wantProf) or wantProf[e.profName])
		if ok then
			local hay = rawget(e, "_lname") or Lower(e.name)
			for _, w in ipairs(q.words or {}) do if not hay:find(w, 1, true) then ok = false break end end
		end
		if ok and q.learnable then
			if not e.need then
				noSkill, ok = noSkill + 1, false
			elseif not e.canLearn then
				ok = false
				if not nextUp or e.need < nextUp.need then nextUp = e end
			end
		end
		if ok then rows[#rows + 1] = e end
	end
	table.sort(rows, Order)
	for i, e in ipairs(rows) do e._score = 1e6 - i end
	local which = (#(q.profs or {}) == 1) and q.profs[1] or nil
	local note = (q.learnable and "Recipes you can learn now" or "Recipes you don't know yet") .. (which and (": " .. which) or "")
	if #rows == 0 then
		if q.learnable and nextUp then
			note = ("None you can learn yet: the next, %s, needs %s %d"):format(nextUp.name, nextUp.profName, nextUp.need)
		elseif q.learnable then
			note = "None you can learn now"
		else
			note = "None you don't know" .. (which and (" in " .. which) or "") .. ", as your profession windows listed them"
		end
	end
	if q.learnable and noSkill > 0 then note = note .. ("  ·  %d whose skill isn't known left out"):format(noSkill) end
	local open = {}
	for _, n in ipairs(MR.notListed or {}) do if not next(wantProf) or wantProf[n] then open[#open + 1] = n end end
	if #open > 0 then note = note .. "  ·  open your " .. table.concat(open, ", ") .. " window once to list " .. (#open == 1 and "its" or "their") .. " recipes" end
	return rows, note
end
