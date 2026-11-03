-- Fixes from the full review of November 2026 (1.0.20) that no other test file's area holds: the /who line within 255
-- characters, a spell's data come again not making another class's rows again, another class's rows kept only whole.
local T = ...
local ns, check, FlushAll = T.ns, T.check, T.FlushAll

io.write("[full review: /who's line, spells' data events, another class's rows]\n")
do
	-- the /who line: its last words left out to fit, never refused for its length
	local SO = ns.Social
	local row = SO.WhoAskRow("@who " .. ("someone "):rep(40) .. "lvl:1-60")
	check(#SO.WhoMacro(row) <= ns.Secure.MACRO_MAX, "a long @who: its line within 255 characters: " .. #SO.WhoMacro(row))
	check(SO.WhoAskRow("@who priest").whoFilter == "priest", "a short one as it is")
	-- (review, 1.0.32) one long word of two-byte letters: cut between letters
	local ru = SO.WhoAskRow("@who a" .. ("ж"):rep(120)).whoFilter
	check(#ru <= 150 and #ru % 2 == 1 and ru == "a" .. ("ж"):rep((#ru - 1) / 2), "a long Russian @who: cut between letters: " .. #ru)
end
do
	-- a spell's data in, then in again: another class's rows made again once, not each time
	local SP, CS = ns.Spells, ns.ClassSpells
	local was = { desc = C_Spell.GetSpellDescription, req = C_Spell.RequestLoadSpellData, cached = C_Spell.IsSpellDataCached, forget = CS.ForgetRows }
	local forgot = 0
	CS.ForgetRows = function() forgot = forgot + 1 return was.forget() end
	C_Spell.GetSpellDescription = function() return "" end
	C_Spell.IsSpellDataCached = function() return false end
	C_Spell.RequestLoadSpellData = function() end
	SP.ForgetFacts()
	check(SP.Desc(424242, { n = 5 }) == nil, "a spell's description not in: asked for")
	local on = SP.descFrame:GetScript("OnEvent")
	on(SP.descFrame, "SPELL_DATA_LOAD_RESULT", 424242, true)
	FlushAll()
	on(SP.descFrame, "SPELL_DATA_LOAD_RESULT", 424242, true)
	FlushAll()
	on(SP.descFrame, "SPELL_DATA_LOAD_RESULT", 515151, true) -- (one never asked for)
	FlushAll()
	check(forgot == 1, "its data in: made again once; in again, or another's: not: " .. forgot)
	C_Spell.GetSpellDescription, C_Spell.RequestLoadSpellData, C_Spell.IsSpellDataCached, CS.ForgetRows = was.desc, was.req, was.cached, was.forget
	SP.ForgetFacts()
end
do
	-- another class's rows with a description not in yet: not kept for the session (made again once it is)
	local SP, CS = ns.Spells, ns.ClassSpells
	local was, spellsWas = SP.Desc, CS.Spells
	CS.Spells = function() return { { name = "Moonfire", ranks = { { 8921 } } } } end -- (a class's list, as What's Training gives it)
	SP.Desc = function() return nil end
	CS.ForgetRows()
	local cls = "DRUID"
	local first = CS.Rows(cls, false)
	check(#first == 1, "another class's row made: " .. #first)
	do
		check(CS.Rows(cls, false) ~= first, "a description not in: another class's rows not kept, made again next time")
		-- (review, 1.0.32) ...a few times, then kept: a description that never comes doesn't make them on every search
		local third = CS.Rows(cls, false)
		check(CS.Rows(cls, false) == third, "never in: kept after " .. tostring(CS.WHOLE_TRIES) .. " tries")
		CS.ForgetRows()
		SP.Desc = function() return "" end
		local whole = CS.Rows(cls, false)
		check(CS.Rows(cls, false) == whole, "every one in: kept")
	end
	SP.Desc, CS.Spells = was, spellsWas
	CS.ForgetRows()
end
