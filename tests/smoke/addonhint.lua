-- An addon reached for that isn't installed (0.50.2, the player's ask): @questie, @npc, @loot, @attune, their chains,
-- filters and plain words add a footer line saying which addon to install (Setup.lua's MissingHint, List.lua's
-- SetStatus); the footer grows a line for it and shrinks back.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I = ns.Integrations

io.write("[addon hint: Questie, AtlasLoot, Attune not installed]\n")
do
	local save = { questie = ns.providers.questie, npc = ns.providers.npc, loot = ns.providers.loot, attune = ns.providers.attune,
		mailbox = ns.providers.mailbox, easy = ns.db.easyMode }
	ns.providers.questie, ns.providers.npc, ns.providers.loot, ns.providers.attune, ns.providers.mailbox = nil, nil, nil, nil, nil
	ns:AliasesChanged()
	ns.db.easyMode = false
	I.ForgetHint()
	local function For(s)
		local a = I.MissingFor(s)
		if a and a.name == "AtlasLoot" and ns.LootLog.Question(s) then a = nil end
		return a and a.name or "none"
	end
	local cases = {
		{ "@questie seeking the blade", "Questie" }, { "@npc ratchet", "Questie" }, { "@vendor", "Questie" },
		{ "@loot thunderfury", "AtlasLoot" }, { "@atlasloot", "AtlasLoot" }, { "@attune", "Attune" }, { "@attunements", "Attune" },
		{ "seeking the blade > chain", "Questie" }, { "molten core > steps", "Attune" }, { "attunement to the core > attunement", "Attune" },
		{ "@quest reward:outlaw_sabre", "Questie" }, { "@item sells:linen", "Questie" },
		{ "copper ore", "none" }, { "thorium belt > mats", "none" },
		-- (Advanced mode's plain words are a search: no hint for them; review, 0.50.2)
		{ "molten core loot", "none" }, { "auto loot", "none" }, { "how do i get into molten core", "none" }, { "my attunements", "none" },
		{ "quest chain for the missing diplomat", "none" }, { "innkeeper", "none" },
	}
	for _, c in ipairs(cases) do
		check(For(c[1]) == c[2], c[1] .. ": " .. c[2] .. " (" .. For(c[1]) .. ")")
	end
	ns.db.easyMode = true
	local simple = {
		{ "nearest innkeeper", "Questie" }, { "enchanting trainer", "Questie" }, { "linen cloth", "none" },
		{ "molten core loot", "AtlasLoot" }, { "loot from brd", "AtlasLoot" }, { "dungeon loot", "AtlasLoot" },
		{ "what did i loot", "none" }, { "auto loot", "none" }, { "loot window", "none" },
		{ "quest chain for the missing diplomat", "Questie" }, { "how do i get into molten core", "Attune" },
		{ "how do i get into stormwind", "none" }, { "mc attunement", "Attune" }, { "my attunements", "Attune" },
		{ "attunement to the core", "none" }, { "steps for molten core", "Attune" }, { "dance steps", "none" },
	}
	for _, c in ipairs(simple) do
		check(For(c[1]) == c[2], "Simple mode: " .. c[1] .. ": " .. c[2] .. " (" .. For(c[1]) .. ")")
	end
	ns.db.easyMode = false

	-- the footer: a line of its own, the frame one line taller; gone again for a line that doesn't need it
	I.ForgetHint()
	UI:Hide(); FlushAll()
	-- (a search that finds something: one that finds nothing has .report on that line, 0.67.11)
	UI:Open("hearthstone"); FlushAll()
	local base = UI.footerH
	check(not UI.footExtra:IsShown(), "nothing missing: no extra line")
	UI:Hide(); FlushAll()
	UI:Open("@attune"); FlushAll()
	local said = tostring(UI.footExtra:GetText())
	check(UI.footExtra:IsShown() and said:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") == "Install Attune for this."
		and UI.footerH > base and not tostring(UI.status:GetText()):find("Install", 1, true),
		"@attune without Attune: the extra line says to install it, in few words: " .. said)
	-- (0.50.6, the player's screenshot: the line was above the status, in the font's yellow)
	check(not said:find("|cffffd200", 1, true), "not in a notice's gold: " .. said)
	check(UI.footExtra.lastPoint[5] < UI.status.lastPoint[5] and UI.status.lastPoint[5] < UI.footerH,
		"under the status line: " .. tostring(UI.footExtra.lastPoint[5]) .. " < " .. tostring(UI.status.lastPoint[5]))
	local colour
	UI.footExtra.SetTextColor = function(_, r, g, b) colour = { r, g, b } end
	UI:ApplyTheme()
	local dr, dg, db = ns.Theme.RGB(ns.Theme.Get().dim)
	check(colour and colour[1] == dr and colour[2] == dg and colour[3] == db, "in the footer's own dim colour")
	UI.footExtra.SetTextColor = nil
	UI:Hide(); FlushAll()
	UI:Open("hearthstone"); FlushAll()
	check(not UI.footExtra:IsShown() and UI.footerH == base, "then a search that needs nothing: the line goes, the footer as it was")
	-- (0.67.11) a search that found nothing: that line says where to report it
	UI:Hide(); FlushAll()
	UI:Open("zzqqxxww"); FlushAll()
	check(UI.footExtra:IsShown() and tostring(UI.footExtra:GetText()):find(".report", 1, true),
		"found nothing: the extra line points to .report: " .. tostring(UI.footExtra:GetText()))
	UI:Hide(); FlushAll()

	-- your alts' things (0.50.6, the player): Syndicator or BagBrother, said only with neither
	do
		local St, B = ns.Stored, ns.Bags
		local sv = { api = St.SyndicatorAPI, bb = St.BrotherBags, bagnon = B.Bagnon }
		St.SyndicatorAPI, St.BrotherBags, B.Bagnon = function() return nil end, function() return nil end, function() return nil end
		for _, c in ipairs({ { "@stored linen", "Syndicator" }, { "@alts", "Syndicator" }, { "@bank", "Syndicator" },
			{ "linen on:bob", "Syndicator" }, { "linen in:bank", "Syndicator" }, { "linen in:guild", "Syndicator" },
			{ "linen in:bags", "none" }, { "linen", "none" } }) do
			check(For(c[1]) == c[2], c[1] .. ": " .. c[2] .. " (" .. For(c[1]) .. ")")
		end
		ns.db.easyMode = true
		check(For("bank") == "none", "Simple mode: \"bank\" is the banker, no hint")
		ns.db.easyMode = false
		I.ForgetHint()
		local said = tostring(I.MissingHint("@stored linen")):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		check(said == "Install Syndicator or BagBrother for this.", "both named: " .. said)
		St.SyndicatorAPI = function() return {} end
		check(For("@stored") == "none", "Syndicator there: no hint")
		St.SyndicatorAPI, St.BrotherBags = sv.api, function() return { x = 1 } end
		check(For("@stored") == "none", "BagBrother's records there: no hint")
		St.BrotherBags, B.Bagnon = function() return nil end, function() return true end
		check(For("@stored") == "none", "Bagnon there (its records to come): no hint")
		St.SyndicatorAPI, St.BrotherBags, B.Bagnon = sv.api, sv.bb, sv.bagnon
		I.ForgetHint()
	end

	-- installed: no hint
	ns.providers.questie, ns.providers.npc, ns.providers.loot, ns.providers.mailbox = save.questie or {}, save.npc or {}, save.loot or {}, save.mailbox
	ns.providers.attune = save.attune or {}
	I.ForgetHint()
	check(For("@questie x") == "none" and For("@loot x") == "none" and For("@attune") == "none" and For("molten core loot") == "none",
		"with the addons: no hint")
	ns.providers.questie, ns.providers.npc, ns.providers.loot, ns.providers.attune, ns.providers.mailbox = save.questie, save.npc, save.loot, save.attune, save.mailbox
	ns:AliasesChanged()
	ns.db.easyMode = save.easy
	I.ForgetHint()
end
