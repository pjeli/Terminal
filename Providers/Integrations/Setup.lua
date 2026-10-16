local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local loot, npc, qdb = I.loot, I.npc, I.qdb
local LoadedCore = I.LoadedCore
local QD = ns.QuestieData
local QuestieReady = QD.Ready -- (the data can be read: QuestieDB loaded, and Questie ready if installed)

----------------------------------------------------------------------
-- At login each integration whose addon is there starts; .integrations says what was found
----------------------------------------------------------------------

--- Each on its own: one failing (another version of its addon, a table missing) leaves the others to start (review,
--- 0.53.6), and .debug log says which.
function I.Setup()
	for _, name in ipairs({ "AtlasLoot", "Questie", "Attune", "WhatsTraining" }) do
		local ok, err = pcall(I._["Setup" .. name])
		if not ok then ns:Trace("integrations: " .. name .. " failed to start: " .. tostring(err)) end
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() I.Setup() end)

ns:RegisterCommand("integrations", {
	desc = L["Show which other addons Terminal found (AtlasLoot, Questie, Attune, What's Training)"],
	run = function()
		local lines = { L["Integrations:"] }
		lines[#lines + 1] = "  AtlasLoot: " .. (loot.on
			and L["found (%s). %d loot modules, %d indexed, %d items%s%s"]:format(tostring(LoadedCore() or "AtlasLoot"), loot.modules, loot.loaded, #loot.rows, loot.done and "" or (" " .. L["(still loading)"]),
				(function()
					local n = I.LootWaiting()
					return n > 0 and (", " .. L["%d waiting for their names from the server"]:format(n)) or ""
				end)())
			or L["not found"])
		local src = QD.Source()
		local found = src == "QuestieDB" and L["QuestieDB found (without Questie)"] or L["found"]
		lines[#lines + 1] = "  Questie: " .. (npc.on
			and (npc.list and L["%s. %d NPCs (@npc), %s quests (@questie)"]:format(found, #npc.list, qdb.list and #qdb.list or L["indexing"])
				-- (the NPC list freed while unused: nothing is indexing; review, 0.48.6)
				or (not npc.busy and npc.count and L["%s. %d NPCs (@npc: read again when next searched), %s quests (@questie)"]:format(found,
					npc.count, qdb.list and #qdb.list or L["indexing"]))
				or (QuestieReady() and L["%s, indexing NPCs..."]:format(found) or L["found, waiting for Questie to finish loading"]))
			or L["not found"])
		lines[#lines + 1] = "  Attune: " .. ns.Attune.Status()
		lines[#lines + 1] = "  What's Training: " .. ns.WhatsTraining.Status()
		-- (every addon whose options Ace3 holds: @addonoption)
		local apps = ns.AddonOptions and ns.AddonOptions.Apps() or {}
		lines[#lines + 1] = "  " .. L["Addon options (Ace3):"] .. " " .. (#apps > 0 and table.concat(apps, ", ") or L["none"])
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
	{ name = "Questie", missing = function() return not (ns.providers.questie or ns.providers.npc) end,
		kinds = { questie = true, questdb = true, allquests = true, npc = true, npcs = true, mob = true, mobs = true, vendor = true,
			mailbox = true, mailboxes = true },
		keys = { reward = true, rewards = true, sells = true, sold = true } },
	{ name = "AtlasLoot", missing = function() return not ns.providers.loot end,
		kinds = { loot = true, atlasloot = true, al = true } },
	{ name = "Attune", missing = function() return not ns.providers.attune end,
		kinds = { attune = true, attunes = true, attunement = true, attunements = true },
		words = { attunements = true, attuned = true } },
	-- (0.53.7: @training and its questions; an old What's Training, without the API Terminal reads: "Update")
	{ name = "WhatsTraining", label = "What's Training", missing = function() return not ns.providers.training end,
		outdated = function() return ns.WhatsTraining and ns.WhatsTraining.Loaded() and not ns.WhatsTraining.Api() end,
		kinds = { training = true, train = true, trainable = true, whatstraining = true },
		words = { training = true, trainable = true } },
	-- (0.50.6, the player: your alts' bags and banks, @stored, come from Syndicator or BagBrother (Bagnon's): said only
	-- with neither detected, naming both. Simple mode's "bank" is the banker: no word of its own)
	{ name = "Syndicator", also = "BagBrother", missing = function()
			local S = ns.Stored
			return not (S and ((S.SyndicatorAPI and S.SyndicatorAPI()) or (S.BrotherBags and S.BrotherBags())
				or (ns.Bags and ns.Bags.Bagnon and ns.Bags.Bagnon())))
		end,
		kinds = { stored = true, alts = true, alt = true, bank = true, banks = true, storage = true, everywhere = true,
			syndicator = true, bagnon = true },
		keys = { on = true, who = true },
		values = { ["in:bank"] = true, ["in:guild"] = true } },
}
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
	local name = a and (a.also and L["%s or %s"]:format(Named(label), Named(a.also)) or Named(label))
	hintText = a and ((a.outdated and a.outdated()) and L["Update %s for this."] or L["Install %s for this."]):format(name) or nil
	return hintText
end
function I.ForgetHint() hintFor, hintText = nil, nil end -- (tests: an addon came or went)
