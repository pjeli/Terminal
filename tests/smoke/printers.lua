-- The printers read the line's reading (docs/FRONT_END.md, Phase 4): Alt+` (Easy.ToAdvanced, Search.lua's
-- ns.LineToAdvanced) and .explain (Easy.Explain). Over the parse corpus: Alt+` of Alt+` is the same line (invariant 6),
-- and .explain says the same of both (invariant 5), whichever mode it's typed in; the words keep their case.
local T = ...
local ns, check = T.ns, T.check
local E = ns.Easy

print("[printers: Alt+` and .explain read the line's reading]")

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local corpus = {}
do
	local f = assert(io.open("Terminal/tests/parse_corpus.txt", "r"))
	for line in f:lines() do
		line = line:gsub("\r$", "")
		if line ~= "" and not line:find("^#") then corpus[#corpus + 1] = line end
	end
	f:close()
end

-- (lines whose first Alt+` is a wrong reading, recorded in FRONT_END.md section 10 to fix after: printed again, they
-- differ)
local KNOWN = {
}

local wasEasy, wasLevel = ns.db.easyMode, _G.UnitLevel
-- (the harness has no Questie: an @npc printed would read as nothing the second time; a list of that name, as the game
-- has with Questie, for this file only)
local hadNpc = ns.providers.npc
if not hadNpc then ns:RegisterProvider("npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = function() return {} end }) end
_G.UnitLevel = function() return 30 end
ns.db.easyMode = true
local ok, err = pcall(function()
	-- the words as typed: "Hogger", not the search's lowercase (FRONT_END.md 10.1)
	local a = Trim(E.ToAdvanced("Hogger but not in my bank"))
	check(a == "Hogger | except @bank", "printers: the words' case kept: " .. a)
	-- (Simple mode's copy in words: the send it stands for; review)
	check(Trim(E.ToAdvanced("linen to csv")) == "linen >>> csv" and Trim(E.ToAdvanced("linen as text")) == "linen >>> text",
		"printers: a copy said in words is >>> csv / text: " .. Trim(E.ToAdvanced("linen to csv")) .. " / " .. Trim(E.ToAdvanced("linen as text")))
	check(Trim(E.ToAdvanced("Linen Cloth")):find("Linen", 1, true) ~= nil, "printers: a name's capitals kept: " .. Trim(E.ToAdvanced("Linen Cloth")))

	local notSame, notSaid, n = {}, {}, 0
	for _, line in ipairs(corpus) do
		local adv = Trim(E.ToAdvanced(line))
		if adv ~= "" and not KNOWN[line] then
			n = n + 1
			local again = Trim(E.ToAdvanced(adv))
			if again ~= adv then notSame[#notSame + 1] = line .. ": " .. adv .. " -> " .. again end
			local said, saidAgain = E.Explain(adv), E.Explain(again)
			if said ~= saidAgain then notSaid[#notSaid + 1] = line .. ": " .. tostring(said) .. " / " .. tostring(saidAgain) end
		end
	end
	check(n > 300, "printers: the corpus read (" .. n .. " lines)")
	check(#notSame == 0, "printers: Alt+` of Alt+` is the same line: " .. #notSame .. " differ, first: " .. tostring(notSame[1]))
	check(#notSaid == 0, "printers: .explain says the same of both: " .. #notSaid .. " differ, first: " .. tostring(notSaid[1]))

	-- .explain of an Advanced line is the same typed in either mode (it reads the line as Advanced mode does)
	local differ = {}
	for i = 1, #corpus, 4 do
		local adv = Trim(E.ToAdvanced(corpus[i]))
		if adv ~= "" then
			ns.db.easyMode = true
			local simple = E.Explain(adv)
			ns.db.easyMode = false
			local advanced = E.Explain(adv)
			ns.db.easyMode = true
			if simple ~= advanced then differ[#differ + 1] = adv .. ": " .. tostring(simple) .. " / " .. tostring(advanced) end
		end
	end
	check(#differ == 0, "printers: .explain the same in both modes: " .. #differ .. " differ, first: " .. tostring(differ[1]))
end)
ns.db.easyMode, _G.UnitLevel = wasEasy, wasLevel
if not hadNpc then
	ns.providers.npc = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "npc" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
end
check(ok, "printers: " .. tostring(err))
