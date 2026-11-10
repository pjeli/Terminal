-- The 1.3.0 release review's fixes (four reviewers over 1.2.1-1.2.10): one check each that fails without its fix.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local SSH, E = ns.Ssh, ns.Easy

io.write("[review 1.3.0: Share, OpenMap, the footer, .zen, the suggestions]\n")

-- the world map's dots: back on a reopened map (they stayed hidden until a friend next moved)
do
	local D = SSH and SSH.Dots
	if D and D.Start() then
		D.lastSig = "same"
		D.driver.scripts.OnHide(D.driver)
		check(D.lastSig == nil, "the map closed: its dots are placed again on the next show")
	end
end

-- a friend who leaves, sharing no items but their place: their place's row goes too
do
	local ep = SSH.game
	local changedWas, changed = ep.env.changed, 0
	ep.env.changed = function() changed = changed + 1 end
	local f = { claim = "nobag@realm", name = "Nobag", items = {}, where = { map = 1429, x = 0.5, y = 0.5, at = ep:Now() } }
	ep.friends[f.claim] = f
	ep:Drop(f, "test")
	ep.env.changed = changedWas
	check(changed >= 1 and not ep.friends[f.claim], "a friend with only a place, dropped: the rows made again (their place's row goes)")
end

-- the per-group location rows follow a renamed group
do
	local dbWas = _G.TerminalShareDB
	_G.TerminalShareDB = { groups = { raid = { key = "k", mode = "limited" } } }
	local ep = { groups = { raid = { name = "raid" } } }
	function ep:Rename(old, new) self.groups[new], self.groups[old] = self.groups[old], nil return true end
	local changedWas, shared = ns.Changed, 0
	ns.Changed = function(self, id, ...) if id == "shared" then shared = shared + 1 end return changedWas(self, id, ...) end
	local badgeWas = SSH.Badge
	SSH.Badge = function() end
	SSH.RenameCmd(ep, "raid team")
	SSH.Badge, ns.Changed = badgeWas, changedWas
	_G.TerminalShareDB = dbWas
	check(shared == 1 and ep.groups.team, ".share rename: the rows made again (\"Share your location in team\")")
end

-- the footer: a new font face lays it out again (its width changes)
do
	UI:Open("linen"); FlushAll()
	UI:SetStatus()
	local t = ns.Theme.Get()
	local key, fontWas = UI.statusFitKey, t.font
	t.font = "SomeOtherFace"
	UI:FitStatus()
	check(UI.statusFitKey ~= key, "the font face changed: the footer laid out again")
	t.font = fontWas
	UI:FitStatus()
	UI:Hide(); FlushAll()
end

-- the open key's character: only the first one after it is dropped (a key that types nothing left it waiting)
do
	UI:Open(); FlushAll()
	UI:SetQuery("")
	UI.swallowTick = GetTime()
	UI:OnChar("a")
	UI:OnChar("~")
	check(UI.edit:GetText() == "a~", "a ~ typed after another character: typed (only the first after the key could be the key's): " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
end

-- a suggestion typed as shown, its note too: the note isn't read
do
	ns.db.zen = nil
	E.ResetPool()
	local pool = E.ExamplePool()
	local shown
	for _, x in ipairs(pool) do if x:find("^try: %.zen on %(") then shown = x end end
	check(shown ~= nil, "(.zen on is suggested here)")
	if shown then
		local line = shown:gsub("^try: ", "")
		check(E.WithoutNote(line) == ".zen on", "typed with its note: read without it: " .. tostring(E.WithoutNote(line)))
	end
	check(E.WithoutNote("wool (grey)") == "wool (grey)", "brackets in a line that isn't a suggestion: kept")
	UI:Open(); FlushAll()
	UI:SetQuery(".theme (a look of your own)"); FlushAll()
	UI:Refresh()
	check(UI.args == "", ".theme typed with its note: no argument read from the note: " .. tostring(UI.args))
	UI:Hide(); FlushAll()
end

-- when it's time to train: secondaries' later ranks aren't a trainer's; a rank wants a level; the top: nothing
do
	check(not E.ProfCapped({ line = 356, rank = 150, max = 150 }, 40), "Fishing at 150: Expert is a book, not a trainer")
	check(E.ProfCapped({ line = 356, rank = 75, max = 75 }, 20), "Fishing at 75 of 75: its trainer")
	check(not E.ProfCapped({ line = 164, rank = 75, max = 75 }, 5), "Blacksmithing 75 of 75 at level 5: Journeyman wants 10")
	check(E.ProfCapped({ line = 164, rank = 75, max = 75 }, 12), "... at level 12: its trainer")
	check(E.ProfDone({ line = 164, rank = 300, max = 300 }), "300 of 300: nothing more to train")
end

-- profession names of any length (Cyrillic letters are two bytes): Russian Blacksmithing keeps its anvil
do
	local was = { profs = _G.GetProfessions, info = _G.GetProfessionInfo, missing = ns.Integrations.AddonMissing }
	ns.Integrations.AddonMissing = function() return false end
	_G.GetProfessions = function() return 1 end
	_G.GetProfessionInfo = function(i) if i == 1 then return "Кузнечное дело", 1, 100, 150, 0, 0, 164 end end
	local anvil = false
	for _, x in ipairs(E.PersonalTagged(false)) do if x[1] == "nearest anvil" then anvil = true end end
	check(anvil, "Кузнечное дело (27 bytes): its anvil suggested")
	-- Advanced: the trainer by its English word (Questie's titles), whatever the client's language
	local en = false
	for _, x in ipairs(E.PersonalTagged(true)) do if x[1] == "@npc trainer:blacksmithing sort:distance" then en = true end end
	check(en or not ns:ResolveProvider("npc"), "Advanced: @npc trainer:blacksmithing, not the Russian name")
	_G.GetProfessions, _G.GetProfessionInfo, ns.Integrations.AddonMissing = was.profs, was.info, was.missing
end

-- a profession whose name is a place's word (French Blacksmithing, "Forge"): "nearest forge" is the forge
do
	local TS = _G.C_TradeSkillUI
	local was = TS and rawget(TS, "GetTradeSkillDisplayName")
	_G.C_TradeSkillUI = TS or {}
	_G.C_TradeSkillUI.GetTradeSkillDisplayName = function(line) if line == 164 then return "Forge" end end
	local localeWas = ns.LOCALE
	ns.LOCALE = "frFR" -- (the game's own words are read only on a client that isn't English)
	E.ForgetGameWords()
	check(E.GameWord("forge") == nil, "\"forge\" isn't read as the blacksmithing trainer: " .. tostring(E.GameWord("forge")))
	_G.C_TradeSkillUI.GetTradeSkillDisplayName = function(line) if line == 164 then return "Forge" elseif line == 186 then return "Minage" end end
	E.ForgetGameWords()
	check(E.GameWord("minage") == "trainer:mining", "the other professions' words still read: " .. tostring(E.GameWord("minage")))
	ns.LOCALE = localeWas
	_G.C_TradeSkillUI.GetTradeSkillDisplayName = was
	if not TS then _G.C_TradeSkillUI = nil end
	E.ForgetGameWords()
end

-- the location tip: only with a group that follows the global setting
do
	local gameWas = SSH.game
	local dbWas = _G.TerminalShareDB
	_G.TerminalShareDB = {}
	local function Tip()
		for _, t in ipairs(E.SettingTips()) do if t[1] == ".share settings location on" then return true end end
		return false
	end
	SSH.game = { groups = { raid = { where = false } }, On = function() return true end, WhereAny = function() return false end }
	check(not Tip(), "every group with its own off: .share settings location on wouldn't change anything, not suggested")
	SSH.game.groups.raid.where = nil
	check(Tip(), "a group that follows the global setting: suggested")
	SSH.game = gameWas
	_G.TerminalShareDB = dbWas
end

-- .zen: parts a fight kept from being put back go back when it ends
do
	local Zen = ns.Zen
	local part = CreateFrame("Frame")
	part.ign = true
	part.IsIgnoringParentAlpha = function(self) return self.ign end
	part.SetIgnoreParentAlpha = function(self, v) self.ign = v end
	local f = CreateFrame("Frame")
	f.selectionHighlight = part
	_G.CompactPartyFrameMember4 = f
	Zen.Follow()
	check(part.ign == false, "(following its parent's alpha)")
	local combatWas = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	check(Zen.Unfollow() == false and part.ign == false, "in a fight: kept for later")
	_G.InCombatLockdown = function() return false end
	Zen.OnEvent("PLAYER_REGEN_ENABLED")
	check(part.ign == true, "the fight over: back as Blizzard made it")
	_G.InCombatLockdown = combatWas
	_G.CompactPartyFrameMember4 = nil
end

ns.db.zen = nil
E.ResetPool()
