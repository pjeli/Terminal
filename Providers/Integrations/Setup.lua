local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local loot, npc, qdb = I.loot, I.npc, I.qdb
local LoadedCore = I.LoadedCore
local QD = ns.QuestieData
local QuestieReady = QD.Ready -- (the data can be read: QuestieDB loaded, and Questie ready if installed)
local function AddOnVersion(name) return I._.AddOnVersion(name) end -- (Shared.lua's)

----------------------------------------------------------------------
-- At login each integration whose addon is there starts; .integrations says what was found
----------------------------------------------------------------------

--- Each on its own: one failing (another version of its addon, a table missing) leaves the others to start (review,
--- 0.53.6), and .debug log says which.
-- what each one starting with an error leaves out, said in chat (I.Failed; 0.57.1)
I.LOST = {
	AtlasLoot = { "AtlasLoot", L["@loot (its loot tables) is unavailable."] },
	Questie = { "Questie", L["@npc and @questie are unavailable."] },
	Attune = { "Attune", L["@attune is unavailable."] },
	WhatsTraining = { "What's Training", L["@training is unavailable."] },
	TrainerSpells = { "TrainerSpells", L["Its trainers, weapon masters, class spells and profession training are unavailable."] },
}
function I.Setup()
	for _, name in ipairs({ "AtlasLoot", "Questie", "Attune", "WhatsTraining", "TrainerSpells" }) do
		local setup = I._["Setup" .. name]
		local ok, err = true, nil
		if setup then ok, err = pcall(setup) end
		if not ok then
			ns:Trace("integrations: " .. name .. " failed to start: " .. tostring(err))
			local lost = I.LOST[name]
			if lost then I.Failed(lost[1], lost[2], err) end
		end
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() I.Setup() end)

--- What @npc is without Questie: nothing, or TrainerSpells' trainers.
function I.NoQuestieStatus()
	local p = ns.providers.npc
	local TS = ns.TrainerSpells
	local rows = p and p.trainersOnly and TS and TS.TrainerRows and TS.TrainerRows()
	return rows and L["not found; TrainerSpells' %d trainers are @npc"]:format(#rows) or L["not found"]
end

--- Training's line: What's Training or TrainerSpells, whichever @training comes from, with its counts ("What's
--- Training (1.4). 42 spells to learn, 5 now (@training)"); TrainerSpells' recipes a trainer teaches too when it's there
--- ("442 profession spells"). An old What's Training: said to update; neither: not found, naming both.
function I.TrainingStatus()
	local p = ns.providers.training
	local WT, TS = ns.WhatsTraining, ns.TrainerSpells
	local tsOn = TS and TS.Loaded()
	local profs = 0
	local d = tsOn and TS.ProfData()
	for _, list in pairs(d and d.list or {}) do profs = profs + #list end
	local function Profs(said) return profs > 0 and (said .. ", " .. L["%d profession spells (@recipe is:unknown)"]:format(profs)) or said end
	if p then
		local left, now = 0, 0
		for _, e in ipairs(ns:GetEntries(p)) do
			if e.state ~= "ignored" then left = left + 1 end
			if e.state == "now" then now = now + 1 end
		end
		local ts = p.fromTrainerSpells
		local said = L["%s (%s). %d spells to learn, %d now (@training)"]:format(ts and "TrainerSpells" or "What's Training",
			AddOnVersion(ts and TS.ADDON or WT.ADDON), left, now)
		-- (TrainerSpells too, What's Training's @training: its profession spells named after it)
		if not ts and tsOn and profs > 0 then return said .. "; " .. L["TrainerSpells: %d profession spells (@recipe is:unknown)"]:format(profs) end
		return Profs(said)
	end
	if WT and WT.Loaded() then return WT.Status() end -- (too old: update it)
	if tsOn then return Profs(L["%s (%s)."]:format("TrainerSpells", AddOnVersion(TS.ADDON))) end -- (its class spells unusable: said after)
	return L["not found (What's Training or TrainerSpells)"]
end

ns:RegisterCommand("integrations", {
	desc = L["Show which other addons Terminal found (AtlasLoot, Questie, Attune, What's Training, TrainerSpells)"],
	run = function()
		local lines = { L["Integrations:"] }
		lines[#lines + 1] = "  AtlasLoot: " .. (loot.on
			and L["found (%s). %d loot modules, %d indexed, %d items%s%s"]:format(tostring(LoadedCore() or "AtlasLoot"), loot.modules, loot.loaded, #loot.rows, loot.done and "" or (" " .. L["(still loading)"]),
				(function()
					local n = I.LootWaiting()
					return n > 0 and (", " .. L["%d waiting for their names from the server"]:format(n)) or ""
				end)())
			or L["not found"]) .. I.FailedText("AtlasLoot")
		local src = QD.Source()
		local found = src == "QuestieDB" and L["QuestieDB found (without Questie)"] or L["found"]
		lines[#lines + 1] = "  Questie: " .. (npc.on
			and (npc.list and L["%s. %d NPCs (@npc), %s quests (@questie)"]:format(found, #npc.list, qdb.list and #qdb.list or L["indexing"])
				-- (the NPC list freed while unused: nothing is indexing; review, 0.48.6)
				or (not npc.busy and npc.count and L["%s. %d NPCs (@npc: read again when next searched), %s quests (@questie)"]:format(found,
					npc.count, qdb.list and #qdb.list or L["indexing"]))
				or (QuestieReady() and L["%s, indexing NPCs..."]:format(found) or L["found, waiting for Questie to finish loading"]))
			or I.NoQuestieStatus()) .. I.FailedText("Questie")
		lines[#lines + 1] = "  Attune: " .. ns.Attune.Status() .. I.FailedText("Attune")
		-- (0.57.4, the author's ask: one line, as alts and banks are said: What's Training or TrainerSpells, either one
		-- (never both expected), the one used named with its counts)
		lines[#lines + 1] = "  " .. L["Training:"] .. " " .. I.TrainingStatus() .. I.FailedText("What's Training") .. I.FailedText("TrainerSpells")
		-- (every addon whose options Ace3 holds: @addonoption)
		local apps = ns.AddonOptions and ns.AddonOptions.Apps() or {}
		lines[#lines + 1] = "  " .. L["Addon options (Ace3):"] .. " " .. (#apps > 0 and table.concat(apps, ", ") or L["none"])
		if ns.Auctionator then lines[#lines + 1] = "  Auctionator: " .. ns.Auctionator.Status() end
		if ns.Stored then lines[#lines + 1] = "  " .. L["Alts and banks:"] .. " " .. ns.Stored.Status() end
		return lines
	end,
})
----------------------------------------------------------------------
-- Reaching for an addon that isn't there (0.50.2, the player's ask): @questie, @npc, @loot, @attune, @stored, their chains
-- (> chain, > steps), filters (reward:, sells:) and plain words (an NPC's role in Simple mode, "loot", "attunements",
-- "how do i get into") say in an extra footer line which addon to install for it. Nothing changes in the search itself.
----------------------------------------------------------------------

I.ADDONS = {
	-- (TrainerSpells' trainers as @npc without Questie: Questie still missing for every other NPC; 0.57.1)
	{ name = "Questie", missing = function()
			local p = ns.providers.npc
			return not (ns.providers.questie or (p and not p.trainersOnly))
		end,
		kinds = { questie = true, questdb = true, allquests = true, npc = true, npcs = true, mob = true, mobs = true, vendor = true,
			mailbox = true, mailboxes = true, forge = true, forges = true, anvil = true, anvils = true,
			cookingfire = true, cookingfires = true, moonwell = true, moonwells = true },
		keys = { reward = true, rewards = true, sells = true, sold = true } },
	{ name = "AtlasLoot", missing = function() return not ns.providers.loot end,
		kinds = { loot = true, atlasloot = true, al = true } },
	{ name = "Attune", missing = function() return not ns.providers.attune end,
		kinds = { attune = true, attunes = true, attunement = true, attunements = true },
		words = { attunements = true, attuned = true } },
	-- (0.53.7: @training and its questions; an old What's Training, without the API Terminal reads: "Update")
	-- (0.57.4: or TrainerSpells, which makes @training too: either one, never both expected; the hint names both)
	{ name = "WhatsTraining", label = "What's Training", also = "TrainerSpells", missing = function() return not ns.providers.training end,
		outdated = function() return ns.WhatsTraining and ns.WhatsTraining.Loaded() and not ns.WhatsTraining.Api() end,
		kinds = { training = true, train = true, trainable = true, whatstraining = true },
		words = { training = true, trainable = true } },
	-- (0.56.1: every class's spells and weapon masters are What's Training's catalog, WT_API.GetCatalog: "druid spells",
	-- "upcoming spells"; an older What's Training, without it: "Update")
	{ name = "WhatsTrainingCatalog", label = "What's Training", also = "TrainerSpells", kinds = {},
		-- (TrainerSpells' class spells do too, 0.57.1: then nothing's missing)
		missing = function()
			local CS = ns.ClassSpells
			return not (CS and ((CS.Api and CS.Api()) or (CS.FromTrainerSpells and CS.FromTrainerSpells())))
		end,
		outdated = function() return ns.WhatsTraining and ns.WhatsTraining.Loaded() and true or false end },
	-- (0.50.6, the player: your alts' bags and banks, @stored, come from Syndicator or BagBrother (Bagnon's): said only
	-- with neither detected, naming both. Simple mode's "bank" is the banker: no word of its own)
	{ name = "Syndicator", also = "BagBrother", missing = function()
			local S = ns.Stored
			return not (S and ((S.SyndicatorAPI and S.SyndicatorAPI()) or (S.BrotherBags and S.BrotherBags())
				or (ns.Bags and ns.Bags.Bagnon and ns.Bags.Bagnon())))
		end,
		kinds = { stored = true, alts = true, alt = true, bank = true, banks = true, mybank = true, storage = true, everywhere = true,
			syndicator = true, bagnon = true },
		keys = { on = true, who = true },
		values = { ["in:bank"] = true, ["in:guild"] = true } },
}
-- (0.62.0: auction house prices, AuctionValues.lua: its filters and fields say to install it)
I.ADDONS[#I.ADDONS + 1] = { name = "Auctionator", missing = function() return not (ns.Auctionator and ns.Auctionator.On()) end,
	kinds = {}, words = { auctionable = true, undercut = true }, values = { ["is:auctionable"] = true, ["is:undercut"] = true,
	["sort:ahvalue"] = true, ["sort:ah"] = true, ["sort:ahprice"] = true, ["sort:market"] = true } }
local BY_NAME = {}
for _, a in ipairs(I.ADDONS) do BY_NAME[a.name] = a end

-- Simple mode's word for an NPC's role ("innkeeper", "trainer"): Questie's NPCs
local function NpcWord(w)
	local E, F = ns.Easy, ns.Filters
	local spec = E and E.WORDS and E.WORDS[w]
	if type(spec) ~= "string" then return false end
	if spec:find("^trainer:") then return true end
	local v = spec:match("^is:(%a+)$")
	local where = v and F and F.APPLIES and F.APPLIES.is[v]
	for _, k in ipairs(where or {}) do if k == "npc" then return true end end
	return false
end

-- Do these words name a dungeon or raid (Terminal's own list of entrances: each word in one's name, or its shorthand,
-- "mc"), or say dungeon, raid or boss?
local GENERIC = { dungeon = true, dungeons = true, raid = true, raids = true, boss = true, bosses = true, instance = true }
local function NamesInstance(what)
	local words = {}
	for w in what:gsub("'", ""):gsub("[%p]", " "):gmatch("%S+") do
		if w ~= "the" then words[#words + 1] = w end
	end
	if #words == 0 then return false end
	if #words == 1 and GENERIC[words[1]] then return true end
	for _, d in ipairs(I.ENTRANCES or {}) do
		local n = " " .. ns.Lower(d[1]):gsub("'", ""):gsub("[%p]", " ") .. " "
		local all = true
		for _, w in ipairs(words) do
			local found = n:find(" " .. w, 1, true) ~= nil
			for _, full in ipairs(not found and ns.Shorthand and ns.Shorthand[w] or {}) do
				if n:find(" " .. full:gsub("'", ""), 1, true) then found = true break end
			end
			if not found then all = false break end
		end
		if all then return true end
	end
	return false
end
I._.NamesInstance = NamesInstance

local function Missing(name)
	local a = BY_NAME[name]
	return a and a.missing() and a or nil
end

--- Is this addon (by its name in I.ADDONS: "Questie", "AtlasLoot") not installed, or not ready? (.tour, Tour.lua)
function I.AddonMissing(name) return Missing(name) ~= nil end

I.TRAINING_ASKS = { "^what can i train", "^what can i learn$", "^what can i learn now", "^what do i learn",
	"^what spells can i learn", "^what spells do i learn", "^when do i learn ", "^when can i learn ", "^spells to learn",
	"^spells to train", "^what should i train", "^what to train" }

local hintText, hintFor
--- The addon a line reaches for that isn't installed: { name, what }, or nil. Its syntax in any mode (an @kind, a
--- key:value filter, a > link); Simple mode's words too (an NPC's role, "molten core loot", "how do i get into mc",
--- "attunements", a chain's words: "quest chain for x").
function I.MissingFor(text)
	if type(text) ~= "string" or not text:find("%S") then return nil end
	local lt = ns.Lower(text)
	local simple = ns.Easy and ns.Easy.On and ns.Easy.On()
	local P = ns.Pipes
	local afterLink = false
	for w in lt:gmatch("%S+") do
		if w == ">" then
			afterLink = true
		elseif afterLink then
			-- (a link word: the relation an addon brings, while it isn't there)
			afterLink = false
			for name, defs in pairs(P and P.relations or {}) do
				local def = defs[1]
				local named = w == name
				for _, al in ipairs(def and def.aliases or {}) do if w == al then named = true end end
				if named and def.addon and not P.Available(name) and Missing(def.addon) then return Missing(def.addon) end
			end
		else
			local kind = w:match("^@(%S+)")
			local key = w:match("^[-!]?(%a+):")
			local kv = key and (key .. ":" .. (w:match(":(.*)$") or ""))
			for _, a in ipairs(I.ADDONS) do
				if a.missing() and ((kind and a.kinds[kind]) or (key and a.keys and a.keys[key]) or (kv and a.values and a.values[kv])
					or (simple and not kind and not key and a.words and a.words[w])) then
					return a
				end
			end
			if simple and not kind and not key and NpcWord(w) and Missing("Questie") then return Missing("Questie") end
		end
	end
	if not simple or lt:find("[@>|]") or lt:find(":%S") then return nil end
	local line = lt:gsub("'", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	-- a chain's words, its link an addon's ("quest chain for x", "steps for mc")
	for _, ph in ipairs(P and P.PHRASES or {}) do
		local defs = P.relations[ph[2]]
		local def = defs and defs[1]
		local what = def and def.addon and not P.Available(ph[2]) and Missing(def.addon) and line:match(ph[1])
		-- (Attune's: an instance's steps, not "dance steps")
		if what and (def.addon ~= "Attune" or NamesInstance(what)) then return Missing(def.addon) end
	end
	-- spirit healers: Questie's NPCs ("nearest spirit healer", "graveyard")
	if (line:find("spirit healer", 1, true) or line:find("graveyard", 1, true)) and Missing("Questie") then return Missing("Questie") end
	-- an instance's loot ("molten core loot", "loot from brd", "dungeon loot"), its attunement ("mc attunement",
	-- "attunement for onyxia"), how to get in ("how do i get into mc")
	local at = Missing("AtlasLoot")
	if at then
		local what = line:match("^(.+) loot$") or line:match("^loot from (.+)$") or line:match("^loot in (.+)$")
		if what and NamesInstance(what) then return at end
	end
	-- what you can train ("what can i train", "what do i learn next level", "when do i learn fireball")
	local wt = Missing("WhatsTraining")
	if wt then
		for _, pat in ipairs(I.TRAINING_ASKS) do if line:find(pat) then return wt end end
	end
	-- every class's spells ("druid spells", "upcoming spells", "spells at level 30"; not "my spells": the spellbook's)
	local cat = Missing("WhatsTrainingCatalog")
	local CQ = cat and ns.ClassSpells and ns.ClassSpells.Q
	if CQ and CQ.Parse then
		local q = CQ.Parse(text)
		if q and not q.known then return cat end
	end
	local an = Missing("Attune")
	if an then
		local what = line:match("^(.+) attunement$") or line:match("^attunement for (.+)$")
			or line:match("^how do i get into (.+)$") or line:match("^how to get into (.+)$") or line:match("^how do i get attuned to (.+)$")
			or line:match("^how to get attuned to (.+)$")
		if what and NamesInstance(what) then return an end
	end
	return nil
end

--- The footer's extra line for a line typed: which addon to install for what it reaches for, or nil.
function I.MissingHint(text)
	local key = ((ns.Easy and ns.Easy.On and ns.Easy.On()) and "1" or "0") .. tostring(text)
	if key == hintFor then return hintText end
	hintFor = key
	-- (the loot log's own questions say "loot" too: "what did i loot" is answered without AtlasLoot)
	local LL = ns.LootLog
	local a = I.MissingFor(text)
	if a and a.name == "AtlasLoot" and LL and LL.Question and type(text) == "string" and LL.Question(text) then a = nil end
	-- (short, under the status, the addon's name in the text's colour: 0.50.6, the player's screenshot)
	local th = ns.Theme and ns.Theme.Get and ns.Theme.Get()
	local function Named(n) return th and th.text and ("|cff" .. th.text .. n .. "|r") or n end
	local label = a and (a.label or a.name)
	local old = a and a.outdated and a.outdated()
	-- (either of two does it: both named to install; one installed but too old: that one named to update)
	local name = a and ((a.also and not old) and L["%s or %s"]:format(Named(label), Named(a.also)) or Named(label))
	hintText = a and (old and L["Update %s for this."] or L["Install %s for this."]):format(name) or nil
	return hintText
end
function I.ForgetHint() hintFor, hintText = nil, nil end -- (tests: an addon came or went)
