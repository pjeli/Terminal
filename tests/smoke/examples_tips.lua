-- The empty prompt's "try:" suggestions, 1.2.10 (the player: "enhance the 'try' recommendations to also suggest
-- different terminal settings (try .zen mode; try .share settings openmap on; etc). Also if they are blacksmithing or
-- mining, suggest nearby forge, nearby anvil, nearby whatever trainers they may need"). Search/Reading/Examples.lua.
local T = ...
local ns, check = T.ns, T.check
local E = ns.Easy

io.write("[examples: your professions' trainers and places, Terminal's settings]\n")

local save = { profs = _G.GetProfessions, info = _G.GetProfessionInfo, guild = _G.IsInGuild, group = _G.IsInGroup,
	missing = ns.Integrations.AddonMissing, zen = ns.db.zen, ask = rawget(ns.db, "ask") }
ns.Integrations.AddonMissing = function() return false end -- (Questie there)
local PROFS = {
	{ "Blacksmithing", 70, 75, 164 }, { "Mining", 120, 150, 186 }, { "Tailoring", 200, 225, 197 },
}
_G.GetProfessions = function() return 1, 2, 3 end
_G.GetProfessionInfo = function(i)
	local p = PROFS[i]
	if p then return p[1], 1, p[2], p[3], 0, 0, p[4] end
end
_G.IsInGuild = function() return true end
_G.IsInGroup = function() return false end

local function Find(list, text)
	for _, x in ipairs(list) do if x[1] == text then return x end end
end
local function Texts(list)
	local t = {}
	for _, x in ipairs(list) do t[#t + 1] = x[1] end
	return table.concat(t, " | ")
end

do
	local mine = E.PersonalTagged(false)
	local all = Texts(mine)
	local bs = Find(mine, "nearest blacksmithing trainer (70/75)")
	check(bs and bs.todo, "blacksmithing at the top of its rank (70 of 75): its trainer, with the skill, offered more often: " .. all)
	check(Find(mine, "nearest mining trainer") and not Find(mine, "nearest mining trainer").todo,
		"mining with room to grow (120 of 150): its trainer, as any other suggestion")
	check(Find(mine, "nearest anvil") and Find(mine, "nearest forge"), "blacksmithing and mining: the nearest anvil and forge")
	local forges = 0
	for _, x in ipairs(mine) do if x[1] == "nearest forge" then forges = forges + 1 end end
	check(forges == 1, "the forge suggested once for both: " .. forges)
	check(not Find(mine, "nearest moonwell"), "tailoring under 250: no moonwell yet (Mooncloth needs 250)")
	PROFS[3][2] = 260
	check(Find(E.PersonalTagged(false), "nearest moonwell"), "tailoring at 260: the nearest moonwell")
	PROFS[3][2] = 200
	PROFS[2] = { "Mining", 300, 300, 186 }
	check(not (Find(E.PersonalTagged(false), "nearest mining trainer (300/300)") or {}).todo,
		"at the top rank (300): nothing more to train, not offered as a need")
	PROFS[2] = { "Mining", 120, 150, 186 }
	-- Advanced: the same, as its syntax (where this setup has the kinds)
	local adv = E.PersonalTagged(true)
	if ns:ResolveProvider("npc") then
		check(Find(adv, "@npc trainer:blacksmithing sort:distance") and Find(adv, "@npc trainer:blacksmithing sort:distance").todo,
			"Advanced: the trainer as @npc trainer:, offered more often when it's time: " .. Texts(adv))
	else
		check(not Texts(adv):find("@npc", 1, true), "Advanced, no @npc here (no Questie): no trainer suggested by it: " .. Texts(adv))
	end
	check(Find(adv, ".zen on (the game fades while Terminal is open)"), "Advanced: the settings too (commands work in both modes)")
	if ns:ResolveProvider("anvil") then check(Find(adv, "@anvil sort:distance"), "Advanced: @anvil sort:distance") end
end

do
	-- Terminal's settings: offered while they'd change something, now and then (their own weight)
	ns.db.zen = nil
	ns.db.ask = nil
	local mine = E.PersonalTagged(false)
	local zen = Find(mine, ".zen on (the game fades while Terminal is open)")
	check(zen and zen.setting and not zen.mine, ".zen off: .zen on suggested (a setting's own weight): " .. Texts(mine))
	check(Find(mine, ".ask guild on (Terminal answers guildmates' !t)"), "in a guild with .ask guild off: .ask guild on")
	check(not Find(mine, ".ask group on (Terminal answers your group's !t)"), "in no group: no .ask group")
	local SSH = ns.Ssh
	if SSH and SSH.SETTINGS and SSH.SETTINGS.openmap then
		local dbWas = _G.TerminalShareDB
		_G.TerminalShareDB = {}
		check(Find(E.PersonalTagged(false), ".share settings openmap on (see guildmates who share with OpenMap)"),
			"in a guild, OpenMap players' places off: .share settings openmap on")
		_G.TerminalShareDB = { settings = { openmap = true } }
		check(not Find(E.PersonalTagged(false), ".share settings openmap on (see guildmates who share with OpenMap)"), "on already: not suggested")
		_G.TerminalShareDB = dbWas
	end
	for _, x in ipairs(mine) do
		if x.setting then check(not x[1]:find("%a+:%S"), "a setting's note has no key:value a search would read: " .. x[1]) end
	end
	-- weighed apart: E.SETTING_WEIGHT
	local rand01 = E.rand01
	E.rand01 = function() return 0.5 end
	local order = E.Ordered({ { "a", nil, nil, setting = true }, { "b", nil, nil } }, "field")
	E.rand01 = rand01
	check(order[1][1] == "b" and E.SETTING_WEIGHT < 1, "a setting comes up less often than the game's own suggestions")
	-- turned on: gone from the rotation at once (the settings offered are part of what the rotation is made for)
	E.Set(true)
	ns.db.easyMode = nil
	E.ResetPool()
	local function InPool(text)
		for _, x in ipairs(E.ExamplePool()) do if x == text then return true end end
		return false
	end
	check(InPool("try: .zen on (the game fades while Terminal is open)"), "in the rotation while .zen is off")
	ns.db.zen = true
	check(not InPool("try: .zen on (the game fades while Terminal is open)"), ".zen on: gone from the rotation at once")
	E.Set(false)
end

_G.GetProfessions, _G.GetProfessionInfo, _G.IsInGuild, _G.IsInGroup = save.profs, save.info, save.guild, save.group
ns.Integrations.AddonMissing = save.missing
ns.db.zen, ns.db.ask = save.zen, save.ask
E.ResetPool()
