-- The line's reading is kept for the frame (Phrase.ReadLine's cache; docs/FRONT_END.md 4.3). In the game GetTime is
-- one value a frame, so a second read of a line in the same frame (UI:Search's redo, Alt+`'s own Parse, the overview) is
-- given the same reading, which the first one added its notes to (Phrase.Note: the action, the place). The harness's
-- clock moves on every call, so the rest of the suite almost never hits the cache: here it stands still. Over the parse
-- corpus, a line read twice in one frame, Alt+` between, reads the same both times.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local Scan, E, P = UI._Scan, ns.Easy, ns.Phrase

print("[readcache: a line read twice in one frame reads the same]")

local corpus = {}
do
	local f = assert(io.open("Terminal/tests/parse_corpus.txt", "r"))
	for line in f:lines() do
		line = line:gsub("\r$", "")
		if line ~= "" and not line:find("^#") then corpus[#corpus + 1] = line end
	end
	f:close()
end

--- What a reading gave the query: its words, filters, the bar's picks and where each is in the line, the action's words.
local function Shape(q)
	local specs, picks = {}, {}
	for _, f in ipairs(q.filters or {}) do specs[#specs + 1] = tostring(q.specOf and q.specOf[f]) end
	for _, p in ipairs(q.picks or {}) do
		picks[#picks + 1] = p.spec .. "=" .. tostring(p.word) .. "@" .. tostring(p.src and p.src.s) .. "-" .. tostring(p.src and p.src.e)
	end
	return table.concat(q.tokens, ",") .. " | " .. table.concat(specs, " ") .. " | " .. table.concat(picks, " ")
		.. " | " .. tostring(q.actWord) .. "@" .. tostring(q.srcAction and q.srcAction.said)
end

local getTime, wasEasy, wasLevel = _G.GetTime, ns.db.easyMode, _G.UnitLevel
local frame = 5000
_G.GetTime = function() return frame end
_G.UnitLevel = function() return 30 end
ns.db.easyMode = true
local ok, err = pcall(function()
	local differ, n = {}, 0
	for i = 1, #corpus, 2 do
		local line = corpus[i]
		frame = frame + 1
		P.Forget()
		local a, b = {}, {}
		local q1 = Scan.Parse(a, line); Scan.ActionAndPlace(a, q1)
		local adv1 = E.ToAdvanced(line)
		local q2 = Scan.Parse(b, line); Scan.ActionAndPlace(b, q2)
		local adv2 = E.ToAdvanced(line)
		n = n + 1
		if q1.reading ~= q2.reading then differ[#differ + 1] = line .. ": read again, not kept for the frame" end
		if Shape(q1) ~= Shape(q2) then differ[#differ + 1] = line .. ": " .. Shape(q1) .. " / " .. Shape(q2) end
		if adv1 ~= adv2 then differ[#differ + 1] = line .. ": Alt+` " .. tostring(adv1) .. " / " .. tostring(adv2) end
	end
	check(n > 150, "readcache: the corpus read (" .. n .. " lines)")
	check(#differ == 0, "readcache: the same reading in one frame: " .. #differ .. " differ, first: " .. tostring(differ[1]))
end)
_G.GetTime, ns.db.easyMode, _G.UnitLevel = getTime, wasEasy, wasLevel
P.Forget()
check(ok, "readcache: " .. tostring(err))
