local ns = select(2, ...)
local L = ns.L

-- Talents by what they do (0.54.4, a player's ask, again: "healing talents", "shaman crit talents", "druid regen talents"):
--
--   "healing talents", "talents for crit"     every talent whose name, tree or description says it (yours first)
--   "shaman crit talents", "my regen talents"  one class's
--   "druid talents"                           that class's, tree by tree
--
-- A question, not a search: a plain search read "crit" and "healing" as everyday words (an item's stats), and "healing"
-- missed "healed", "heals". Each word here stands for the ways a description says it (WORDS: crit = critical, regen =
-- regeneration, heal = healed / heals / healing), and every word must be there. Descriptions not sent by the game yet are
-- asked for at once (Providers/Talents.lua's TL.Desc); the list is searched again as they come in.
-- In Advanced syntax: @talent class:shaman crit.

local TQ = {}
ns.TalentsQ = TQ
local Lower = ns.Lower

-- the ways a word is said in talent descriptions ("x*": any word starting so; a space: those words together)
local WORDS = {
	heal = { "heal", "heals", "healed", "healing", "healer", "healers", "heal's" },
	crit = { "crit*" },
	regen = { "regen*", "mana per 5" },
	damage = { "damage" },
	threat = { "threat" },
	cooldown = { "cooldown*" },
	haste = { "haste", "speed" },
	slow = { "slow*", "snare*", "daze*", "movement speed" },
	stun = { "stun*" },
	armor = { "armor", "armour" },
	aoe = { "all enemies", "all targets", "nearby enemies", "enemies within", "all party", "party members" },
	pet = { "pet", "pets", "pet's" },
	stealth = { "stealth*" },
	shield = { "shield*" },
	mana = { "mana" },
	cost = { "cost", "costs" },
	range = { "range" },
	tank = { "threat", "armor", "block*", "parry", "dodge", "defense" },
}
-- other words for those
local SAME = { healing = "heal", heals = "heal", healed = "heal", healer = "heal", healers = "heal",
	crits = "crit", critical = "crit", criticals = "crit", regeneration = "regen", regenerate = "regen", mp5 = "regen",
	dmg = "damage", aggro = "threat", cd = "cooldown", cds = "cooldown", cooldowns = "cooldown", speed = "haste",
	snare = "slow", snares = "slow", slows = "slow", stuns = "stun", armour = "armor", tanking = "tank", pets = "pet",
	shields = "shield", ["area"] = "aoe" }
-- words that ask nothing of the talent
local FILL = {}
for w in ([[talent talents the a an for with that which what whats show list all any good best me i my are is do does
	of to in on give gives increase increases increased improve improves improved boost boosts more better can could
	some about]]):gmatch("%S+") do FILL[w] = true end
-- the talent window and the like: not this question ("talents window", "reset talents")
local NOT = {}
for w in ([[window windows frame panel open toggle key keybind bind reset point points respec calculator wowhead
	build builds loadout spec specs where]]):gmatch("%S+") do NOT[w] = true end
TQ.WORDS, TQ.SAME = WORDS, SAME -- (tests)

--- How a word is looked for: the ways it's said (WORDS), else itself as a word's start (and without a plural s).
local function Ways(w)
	w = SAME[w] or w
	if WORDS[w] then return WORDS[w] end
	local ways = { #w >= 3 and (w .. "*") or w }
	if #w > 3 and w:sub(-1) == "s" then ways[2] = w:sub(1, -2) .. "*" end
	return ways
end

--- "shaman crit talents": { class = "SHAMAN", words = { "crit" }, mine = bool }; nil when the line isn't one.
function TQ.Question(text)
	if not ns.providers.talents then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local talent, q = false, { words = {} }
	local ClassOf = ns.ClassSpells and ns.ClassSpells.Q and ns.ClassSpells.Q.ClassOf
	for w in t:gmatch("%S+") do
		if w == "talent" or w == "talents" then talent = true
		elseif NOT[w] then return nil
		elseif w == "my" then q.mine = true
		elseif not q.class and ClassOf and ClassOf(w) then q.class = ClassOf(w)
		elseif not FILL[w] then q.words[#q.words + 1] = w end
	end
	if not talent then return nil end
	if q.mine and not q.class then q.class = ns.ClassSpells and ns.ClassSpells.MyClass and ns.ClassSpells.MyClass() end
	if not q.class and #q.words == 0 then return nil end -- ("talents", "my talents" with no class known: the list itself)
	return q
end

local function Tokens(s, into)
	for w in Lower(tostring(s or "")):gsub("'", ""):gmatch("[%w\128-\255]+") do into[w] = true end
	return into
end

--- How well a talent's text says one of these ways: 0, or more when its name (4) or tree (2) says it, its description (1).
local function Says(ways, name, tab, desc)
	local best = 0
	for i, where in ipairs({ name, tab, desc }) do
		local hit = false
		for _, a in ipairs(ways) do
			if a:find(" ", 1, true) then
				hit = (" " .. where.text .. " "):find(" " .. a .. " ", 1, true) ~= nil
			elseif a:sub(-1) == "*" then
				local pre = a:sub(1, -2)
				for tok in pairs(where.tokens) do if tok:sub(1, #pre) == pre then hit = true break end end
			else
				hit = where.tokens[a] == true or where.tokens[(a:gsub("'", ""))] == true
			end
			if hit then break end
		end
		if hit then best = math.max(best, ({ 4, 2, 1 })[i]) end
	end
	return best
end

local function Where(s)
	local text = Lower(tostring(s or "")):gsub("'", ""):gsub("[^%w\128-\255]+", " ")
	return { text = text, tokens = Tokens(text, {}) }
end

TQ.ASK = 400 -- (descriptions asked for at once by one question: the rest the next time)

--- The talents (yours first when no class is asked for) and the footer's note; nil when none says it (a search then).
function TQ.Answer(q)
	local TL = ns.Talents
	local rows = {}
	local p = ns.providers.talents
	local mine = ns.ClassSpells and ns.ClassSpells.MyClass and ns.ClassSpells.MyClass()
	local ways = {}
	for i, w in ipairs(q.words) do ways[i] = Ways(w) end
	local budget, waiting = { n = TQ.ASK }, 0
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		if type(e) == "table" and e.name and (not q.class or e.classFile == q.class) then
			local score, ok = 0, true
			if #ways > 0 then
				local desc = TL and TL.Desc(e.spellID, budget)
				if desc == nil then waiting = waiting + 1 end
				local name, tab, d = Where(e.name), Where(e.tab), Where(desc)
				for _, wy in ipairs(ways) do
					local s = Says(wy, name, tab, d)
					if s == 0 then ok = false break end
					score = score + s
				end
			end
			if ok then rows[#rows + 1] = { e = e, score = score, mine = e.classFile == mine } end
		end
	end
	table.sort(rows, function(a, b)
		if a.mine ~= b.mine then return a.mine end
		if a.score ~= b.score then return a.score > b.score end
		local ca, cb = tostring(a.e.className or ""), tostring(b.e.className or "")
		if ca ~= cb then return ca < cb end
		local ia, ib = tonumber(a.e.tabIndex) or 99, tonumber(b.e.tabIndex) or 99 -- (tree by tree, in the window's order)
		if ia ~= ib then return ia < ib end
		local ta, tb = tostring(a.e.tab or ""), tostring(b.e.tab or "")
		if ta ~= tb then return ta < tb end
		return tostring(a.e.name) < tostring(b.e.name)
	end)
	local out = {}
	for i, r in ipairs(rows) do out[i] = r.e end
	local still = waiting > 0 and L["still reading what %d talents do"]:format(waiting) or nil
	if #out == 0 then
		if not still then return nil end
		return { ns.NoteRow(L["No talent says that yet"], still) }, L["Talents by what they do"]
	end
	ns.ScoreInOrder(out)
	return out, ns.Detail(L["Talents by what they do"], still) -- (the footer counts them)
end

-- (as said, 0.55.7: the talents are found by what they do, the words' kin and the descriptions scored, which "@talent crit"
-- doesn't do: nil, Search.lua's ns.QuestionToAdvanced)
function TQ.ToAdvanced() return nil end
