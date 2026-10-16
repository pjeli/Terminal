-- Talents by what they do (0.54.4, a player, again: "healing talents", "shaman crit talents", "druid regen talents" weren't
-- quite doing it): a question (Search/Talents.lua), not a search that read "crit" and "healing" as an item's stats; each
-- word as descriptions say it ("healed", "critical", "regeneration"), every word there.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L = ns.L

io.write("[talentsq: talents by what they do]\n")
do
	local P, TL = ns.providers.talents, ns.Talents
	local save = { collect = P.collect, desc = C_Spell.GetSpellDescription, cached = C_Spell.IsSpellDataCached,
		ask = C_Spell.RequestLoadSpellData, store = ns.db.talentDesc, easy = ns.db.easyMode, class = _G.UnitClass }
	local DESC, rows, id, asked = {}, {}, 90000, {}
	local function R(name, cls, cfile, tab, ti, desc)
		id = id + 1; DESC[id] = desc
		rows[#rows + 1] = { name = name, text = tab .. " " .. cls .. " talent talents", classFile = cfile, className = cls,
			tab = tab, tabIndex = ti, detail = cls, spellID = id }
	end
	R("Purification", "Shaman", "SHAMAN", "Restoration", 3, "Increases the effectiveness of your healing spells by 10%.")
	R("Call of Thunder", "Shaman", "SHAMAN", "Elemental", 1, "Increases the critical strike chance of your Lightning Bolt spell by 1%.")
	R("Tidal Mastery", "Shaman", "SHAMAN", "Restoration", 3, "Increases the critical effect chance of your healing and lightning spells by 1%.")
	R("Intensity", "Druid", "DRUID", "Restoration", 3, "Allows 10% of your Mana regeneration to continue while casting.")
	R("Sharpened Claws", "Druid", "DRUID", "Feral Combat", 2, "Increases your critical strike chance while in Bear or Cat Form by 2%.")
	R("Spiritual Healing", "Priest", "PRIEST", "Holy", 2, "Increases the amount healed by your healing spells by 2%.")
	R("Improved Renew", "Priest", "PRIEST", "Holy", 2, "Increases the amount healed by your Renew spell by 5%.")
	R("Toughness", "Warrior", "WARRIOR", "Protection", 3, "Increases your armor value from items by 10%. Increases your maximum health.")
	R("Cruelty", "Warrior", "WARRIOR", "Fury", 2, "Increases your chance to get a critical strike with melee weapons by 1%.")
	P.collect = function() return rows end
	C_Spell.GetSpellDescription = function(i) return DESC[i] or "" end
	C_Spell.IsSpellDataCached = function(i) return DESC[i] ~= nil end
	C_Spell.RequestLoadSpellData = function(i) asked[i] = true end
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	ns.db.talentDesc = nil
	TL.ForgetDescAsks()
	P._dirty = true
	local function Names(res)
		local t = {}
		for _, e in ipairs(res) do t[#t + 1] = tostring(e.name) end
		return table.concat(t, " | ")
	end
	ns.db.easyMode = true; UI:EasyChanged()
	-- "healing" is "healed" too; every word must be there; yours first
	check(Names(UI:SearchText("healing talents")) == "Spiritual Healing | Improved Renew | Purification | Tidal Mastery",
		"healing talents: healing, healed: " .. Names(UI:SearchText("healing talents")))
	check(Names(UI:SearchText("shaman crit talents")) == "Call of Thunder | Tidal Mastery",
		"shaman crit talents: the shaman's that say critical (not Purification): " .. Names(UI:SearchText("shaman crit talents")))
	check(Names(UI:SearchText("druid regen talents")) == "Intensity", "druid regen talents: regeneration: " .. Names(UI:SearchText("druid regen talents")))
	check(Names(UI:SearchText("crit talents")):find("^Cruelty | "), "crit talents (crit is an item's stat in a search): yours first: "
		.. Names(UI:SearchText("crit talents")))
	check(Names(UI:SearchText("talents for healing")) == Names(UI:SearchText("healing talents")), "talents for healing: the same")
	check(Names(UI:SearchText("druid talents")) == "Sharpened Claws | Intensity", "druid talents: tree by tree: " .. Names(UI:SearchText("druid talents")))
	check(Names(UI:SearchText("my crit talents")) == "Cruelty", "my crit talents: yours: " .. Names(UI:SearchText("my crit talents")))
	check(Names(UI:SearchText("tank talents")) == "Toughness", "tank talents: armor: " .. Names(UI:SearchText("tank talents")))
	check(UI.answerNote and UI.answerNote:find(L["Talents by what they do"], 1, true), "the footer says what it is: " .. tostring(UI.answerNote))
	-- not this question: the window, the list itself
	local Q = ns.TalentsQ
	check(Q.Question("talents window") == nil and Q.Question("reset talents") == nil and Q.Question("talents") == nil
		and Q.Question("@talent crit") == nil and Q.Question("crit food") == nil, "not its questions")
	check(ns.QuestionToAdvanced("shaman crit talents") == "@talent class:shaman crit ", "as Advanced: " .. tostring(ns.QuestionToAdvanced("shaman crit talents")))
	-- a description not sent yet: asked for at once, said in the footer, found once it's in
	local later = DESC[90002]
	DESC[90002] = nil
	ns.db.talentDesc = nil
	TL.ForgetDescAsks()
	P._dirty = true
	check(Names(UI:SearchText("shaman crit talents")) == "Tidal Mastery" and asked[90002], "not in yet: asked for: " .. Names(UI:SearchText("shaman crit talents")))
	check(UI.answerNote and UI.answerNote:find(L["still reading what %d talents do"]:format(1), 1, true), "the footer says some are still coming: " .. tostring(UI.answerNote))
	DESC[90002] = later
	TL.descFrame:GetScript("OnEvent")(TL.descFrame, "SPELL_DATA_LOAD_RESULT", 90002, true)
	check(Names(UI:SearchText("shaman crit talents")) == "Call of Thunder | Tidal Mastery", "come in: found: " .. Names(UI:SearchText("shaman crit talents")))
	UI:Hide(); FlushAll()

	P.collect, C_Spell.GetSpellDescription, C_Spell.IsSpellDataCached, C_Spell.RequestLoadSpellData = save.collect, save.desc, save.cached, save.ask
	ns.db.talentDesc, ns.db.easyMode, _G.UnitClass = save.store, save.easy, save.class
	TL.ForgetDescAsks()
	P._dirty = true
	UI:EasyChanged()
end
