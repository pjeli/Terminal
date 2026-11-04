-- The questions' registry (docs/QUESTIONS.md): every entry has an id, which question gets a line when several could
-- (Q.Ranked: `last`, `over`, the words understood, then the list's order), and every entry's examples are its own.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local Scan = UI._Scan
local Q = ns.Questions
local easy = ns.db.easyMode
ns.db.easyMode = true; UI:EasyChanged()
local unitLevel = _G.UnitLevel
_G.UnitLevel = function() return 30 end

local ok, err = pcall(function()
	-- [questions: ids] every entry has its own id; `over` names entries that exist
	do
		local seen, bad = {}, {}
		for i, a in ipairs(Scan.ANSWERS) do
			if type(a.id) ~= "string" or seen[a.id] then bad[#bad + 1] = tostring(a.id or ("#" .. i)) end
			seen[a.id or i] = true
		end
		for _, a in ipairs(Scan.ANSWERS) do
			for _, o in ipairs(a.over or {}) do if not seen[o] then bad[#bad + 1] = a.id .. " over " .. o end end
		end
		check(#Scan.ANSWERS > 50 and #bad == 0, "[questions: ids] every entry named once, every `over` an entry: " .. table.concat(bad, ", "))
		check(Q.ById("HaveQ") and Q.ById("HaveQ").id == "HaveQ" and Q.ById("nope") == nil, "[questions: ids] Q.ById")
	end

	-- [questions: ranking] the rule itself, over stand-ins: `last` loses, `over` wins outright, then the words
	-- understood, then the list's order
	do
		local function Fake(id, test, more)
			local a = { id = id, ask = function(t) return test(t) and {} or nil end, answer = function() return { { name = id } } end,
				toAdvanced = function() return nil end }
			for k, v in pairs(more or {}) do a[k] = v end
			return a
		end
		-- "zzqa one two": A wants all three words, B only "zzqa" (the rest a free slot)
		local A = Fake("zzA", function(t) return t == "zzqa one two" end)
		local B = Fake("zzB", function(t) return t:find("^zzqa ") ~= nil end)
		table.insert(Scan.ANSWERS, 1, B)
		table.insert(Scan.ANSWERS, 2, A)
		local r = Q.Ranked("zzqa one two")
		check(#r == 2 and r[1].a == A and r[1].n == 3 and r[2].n == 1,
			"[questions: ranking] the entry understanding more words wins, wherever it is in the list: " .. tostring(r[1] and r[1].a.id))
		B.over = { "zzA" }
		r = Q.Ranked("zzqa one two")
		check(r[1].a == B, "[questions: ranking] `over` wins outright")
		B.over, B.last = nil, true
		table.remove(Scan.ANSWERS, 2); table.insert(Scan.ANSWERS, 1, A) -- (A first, B second)
		local C = Fake("zzC", function(t) return t == "zzqa one two" end)
		table.insert(Scan.ANSWERS, 3, C)
		r = Q.Ranked("zzqa one two")
		check(r[1].a == A and r[2].a == C and r[3].a == B,
			"[questions: ranking] a tie: the earlier in the list; `last` after every other: " .. tostring(r[1].a.id) .. " " .. tostring(r[2].a.id) .. " " .. tostring(r[3].a.id))
		-- the answer asks them in that order: the first with rows answers, nil passes the line on
		A.answer = function() return nil end
		ns.db.easyMode = false; UI:EasyChanged()
		local res = UI:Search("zzqa one two")
		check(res[1] and res[1].name == "zzC", "[questions: ranking] an answer that says nil passes the line to the next: " .. tostring(res[1] and res[1].name))
		ns.db.easyMode = true; UI:EasyChanged()
		for k = #Scan.ANSWERS, 1, -1 do local x = Scan.ANSWERS[k] if x == A or x == B or x == C then table.remove(Scan.ANSWERS, k) end end
	end

	-- [questions: examples] each entry's examples are its own: when it takes one, it gets it; when it doesn't here (the
	-- harness lacks its data), no other entry takes it either. Two entries that understand an example as well must be
	-- settled by `over` (the list's order isn't a reason)
	do
		local wrong, ties, mine, unread = {}, {}, 0, 0
		for _, a in ipairs(Scan.ANSWERS) do
			for _, line in ipairs(a.examples or {}) do
				local r = Q.Ranked(line)
				local top = r[1]
				local owned = false
				for _, c in ipairs(r) do if c.a == a then owned = true end end
				if not owned then
					unread = unread + 1
					if top then wrong[#wrong + 1] = line .. " -> " .. tostring(top.a.id) .. " (" .. a.id .. "'s, not read here)" end
				elseif top.a ~= a then
					wrong[#wrong + 1] = line .. " -> " .. tostring(top.a.id) .. " (" .. a.id .. "'s)"
				else
					mine = mine + 1
					local second = r[2]
					if second and second.n == top.n and not second.a.last then
						local declared = false
						for _, o in ipairs(a.over or {}) do if o == second.a.id then declared = true end end
						if not declared then ties[#ties + 1] = line .. ": " .. a.id .. " = " .. second.a.id end
					end
				end
			end
		end
		io.write(("[questions: examples] %d answered by their entry, %d whose entry has no data here\n"):format(mine, unread))
		check(mine > 50 and #wrong == 0, "[questions: examples] every example is its entry's: " .. table.concat(wrong, "; "))
		check(#ties == 0, "[questions: examples] no example settled by the list's order: " .. table.concat(ties, "; "))
	end

	-- [questions: words understood] a free slot counts for less than a word a question knows: "how many mounts do i
	-- have" is the collections' (it knows "mounts"), "do i have mail" the mail's, "how many linen do i have" the count's
	do
		local function Top(line) local c = Q.Ranked(line)[1] return c and c.a.id end
		check(Top("how many mounts do i have") == "CollectionsQ" and Top("do i have mail") == "Mail"
			and Top("how many linen do i have") == "HaveQ",
			"[questions: words understood] " .. tostring(Top("how many mounts do i have")) .. " " .. tostring(Top("do i have mail")))
		local hv = Q.ById("HaveQ")
		local mounts = Q.Understood(hv, "how many mounts do i have")
		check(mounts == 5, "[questions: words understood] the count understands all but its slot: " .. tostring(mounts))
	end

	-- [questions: one search] the ranking is kept while a search runs, asked again outside one
	do
		local n = 0
		local A = { id = "zzCount", ask = function(t) if t == "zzqcount" then n = n + 1 return {} end end,
			answer = function() return { { name = "x" } } end, toAdvanced = function() return nil end }
		table.insert(Scan.ANSWERS, 1, A)
		Q.Ranked("zzqcount"); Q.Ranked("zzqcount")
		check(n == 2, "[questions: one search] outside a search: asked each time")
		n = 0
		Q.Begin(); Q.Ranked("zzqcount"); Q.Ranked("zzqcount"); Q.Finish()
		check(n == 1, "[questions: one search] inside one: asked once")
		table.remove(Scan.ANSWERS, 1)
	end
end)
_G.UnitLevel = unitLevel
ns.db.easyMode = easy; UI:EasyChanged()
if not ok then check(false, "questions: " .. tostring(err)) end
