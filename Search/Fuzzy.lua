local ns = select(2, ...)

-- fzy-style fuzzy matcher (Needleman-Wunsch style DP with word-boundary bonuses).
local Fuzzy = {}
ns.Fuzzy = Fuzzy

local MIN = -math.huge
local LEAD, TRAIL, INNER = -0.005, -0.005, -0.01
local CONSEC, SLASH, WORD, CAPITAL, DOT = 1.0, 0.9, 0.8, 0.7, 0.6
local MAXLEN = 256
local EXACT = 100

local byte, find, ssub = string.byte, string.find, string.sub
local max = math.max

local function bonusFor(last, cur)
	if last == 47 then return SLASH end -- /
	if last == 45 or last == 95 or last == 32 or last == 58 or last == 40 or last == 91 then
		return WORD -- - _ space : ( [
	end
	if last == 46 then return DOT end
	if last >= 97 and last <= 122 and cur >= 65 and cur <= 90 then return CAPITAL end
	return 0
end

--- The needle as it is in the name (most queries): the best such place's score, and where it is.
local function substringScore(needle, hay, lhay, n, m)
	local best, at
	local p = find(lhay, needle, 1, true)
	while p do
		local last = p > 1 and byte(hay, p - 1) or 47
		local s = (p - 1) * LEAD + bonusFor(last, byte(hay, p)) + (n - 1) * CONSEC + (m - (p + n - 1)) * TRAIL
		if not best or s > best then best, at = s, p end
		p = find(lhay, needle, p + 1, true)
	end
	return best, at
end

--- needle must already be lowercase. lhay is optional (lowercased hay).
--- Returns score, positions (array of byte indices in hay) or nil if no match. The same score
--- Fuzzy.score gives, so the letters lit up are the ones that ranked the row: a needle found as it
--- is in the name is that run of letters, even where a scattered match would score higher.
function Fuzzy.match(needle, hay, lhay)
	local n, m = #needle, #hay
	if n == 0 then return 0, {} end
	if n > m or m > MAXLEN then return nil end
	lhay = lhay or ns.Lower(hay)

	if n == m then
		if lhay ~= needle then return nil end
		local p = {}
		for i = 1, n do p[i] = i end
		return EXACT, p
	end
	local sub, at = substringScore(needle, hay, lhay, n, m)
	if sub then
		local p = {}
		for i = 1, n do p[i] = at + i - 1 end
		return sub, p
	end

	-- cheap subsequence check first
	local pos = 0
	for i = 1, n do
		pos = find(lhay, ssub(needle, i, i), pos + 1, true)
		if not pos then return nil end
	end

	local bonus = {}
	local last = 47
	for j = 1, m do
		local c = byte(hay, j)
		bonus[j] = bonusFor(last, c)
		last = c
	end

	local D, M = {}, {}
	for i = 1, n do
		local Di, Mi = {}, {}
		D[i], M[i] = Di, Mi
		local prev = MIN
		local gap = (i == n) and TRAIL or INNER
		local nc = byte(needle, i)
		local Dp, Mp = D[i - 1], M[i - 1]
		for j = 1, m do
			if byte(lhay, j) == nc then
				local score = MIN
				if i == 1 then
					score = (j - 1) * LEAD + bonus[j]
				elseif j > 1 then
					score = max(Mp[j - 1] + bonus[j], Dp[j - 1] + CONSEC)
				end
				Di[j] = score
				prev = max(score, prev + gap)
			else
				Di[j] = MIN
				prev = prev + gap
			end
			Mi[j] = prev
		end
	end

	-- backtrack to recover matched positions (for highlighting)
	local positions = {}
	local matchRequired = false
	local j = m
	for i = n, 1, -1 do
		while j >= 1 do
			if D[i][j] ~= MIN and (matchRequired or D[i][j] == M[i][j]) then
				matchRequired = (i > 1 and j > 1 and M[i][j] == D[i - 1][j - 1] + CONSEC)
				positions[i] = j
				j = j - 1
				break
			end
			j = j - 1
		end
	end

	return M[n][m], positions
end

-- Scoring without positions, for ranking every candidate on each keystroke. Same scale as
-- Fuzzy.match, but: a match that appears as-is in the name (most queries) is scored
-- directly, and scattered matches use two reused rows instead of an n x m grid, so a search
-- allocates nothing per entry. Positions (for highlighting) come from Fuzzy.match, only for
-- the rows on screen. The second result is true when the needle is in the name as it is (the
-- initials and shorthand looks in Search/Score.lua (scoring) only run when it isn't).
local rowM, rowD, rowM2, rowD2 = {}, {}, {}, {}
local rowB, rowL, rowLo = {}, {}, {} -- (per row: each letter's bonus, its lowercase byte; per needle letter: its first possible place)

-- A needle's letters, each as a one-letter string (1..n, for the scattered-letters look) and as a byte (n+1..2n, for
-- the rows), made once per needle: a search scores thousands of rows with the same few needles, and string.sub per
-- letter per row was a good part of a scattered look.
local needleParts, needleCount = {}, 0
local function Parts(needle, n)
	local c = needleParts[needle]
	if c then return c end
	if needleCount >= 256 then needleParts, needleCount = {}, 0 end -- (typed words: a few per search)
	c = {}
	for i = 1, n do c[i], c[n + i] = ssub(needle, i, i), byte(needle, i) end
	needleParts[needle], needleCount = c, needleCount + 1
	return c
end

function Fuzzy.score(needle, hay, lhay)
	local n, m = #needle, #hay
	if n == 0 then return 0 end
	if n > m or m > MAXLEN then return nil end
	lhay = lhay or ns.Lower(hay)
	if n == m then
		if lhay == needle then return EXACT, true end
		return nil
	end
	local sub = substringScore(needle, hay, lhay, n, m)
	if sub then return sub, true end
	-- cheap subsequence check first; each letter's earliest place bounds where its row starts
	local Lo, L = rowLo, Parts(needle, n)
	local pos = find(lhay, L[1], 1, true)
	if not pos then return nil end
	local first = pos
	Lo[1] = pos
	for i = 2, n do
		pos = find(lhay, L[i], pos + 1, true)
		if not pos then return nil end
		Lo[i] = pos
	end
	-- the bonus of each letter and its lowercase byte, once (not once per needle letter)
	local B, Lb = rowB, rowL
	local last = first > 1 and byte(hay, first - 1) or 47
	for j = first, m do
		local c = byte(hay, j)
		B[j] = bonusFor(last, c)
		Lb[j] = byte(lhay, j)
		last = c
	end
	local Mp, Dp, Mc, Dc = rowM, rowD, rowM2, rowD2
	for i = 1, n do
		local nc = L[n + i]
		local prev = MIN
		local gap = (i == n) and TRAIL or INNER
		local lo = Lo[i]
		-- (row i+1 starts past Lo[i]: it reads this row from Lo[i]; nothing left of it can hold letter i)
		local hi = (i == n) and m or (m - n + i)
		Mc[lo - 1], Dc[lo - 1] = MIN, MIN
		for j = lo, hi do
			if Lb[j] == nc then
				local s
				if i == 1 then
					s = (j - 1) * LEAD + B[j]
				else
					local a, b = Mp[j - 1] + B[j], Dp[j - 1] + CONSEC
					s = a > b and a or b
				end
				Dc[j] = s
				prev = (s > prev + gap) and s or (prev + gap)
			else
				Dc[j] = MIN
				prev = prev + gap
			end
			Mc[j] = prev
		end
		Mp, Mc = Mc, Mp
		Dp, Dc = Dc, Dp
	end
	local r = Mp[m]
	if r == MIN then return nil end
	return r
end

----------------------------------------------------------------------
-- Initials: "scb" for Shadow Council Bracers, "zg" for Zul'Gurub
----------------------------------------------------------------------

-- A full initials match ranks like the same letters at the start of a word, a little lower: above
-- scattered matches, under a name that has the letters as they are ("be": Bear before Bracers of
-- the Eagle). A needle that is only the start of the initials (3+ letters) a little lower again.
local INI_FULL, INI_PREFIX = WORD - 0.15, WORD - 0.4
Fuzzy.INI_FULL, Fuzzy.INI_PREFIX = INI_FULL, INI_PREFIX

local function wordChar(b)
	return b ~= nil and ((b >= 97 and b <= 122) or (b >= 65 and b <= 90) or (b >= 48 and b <= 57) or b >= 128)
end

local function lowerByte(b)
	if b and b >= 65 and b <= 90 then return b + 32 end
	return b
end

-- of, the, a, an, and: left out of the second set of initials ("Bracers of the Eagle": "be")
local function minorWord(hay, j, c)
	if c ~= 111 and c ~= 116 and c ~= 97 then return false end -- o t a
	local len = 0
	while true do
		local b = byte(hay, j + len)
		if not (b and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122))) then
			if wordChar(b) or b == 39 then return false end -- (a digit, a letter of another script, an apostrophe)
			break
		end
		len = len + 1
		if len > 3 then return false end
	end
	local c2, c3 = lowerByte(byte(hay, j + 1)), lowerByte(byte(hay, j + 2))
	if len == 1 then return c == 97 end
	if len == 2 then return (c == 111 and c2 == 102) or (c == 97 and c2 == 110) end
	return (c == 116 and c2 == 104 and c3 == 101) or (c == 97 and c2 == 110 and c3 == 100)
end

--- The needle (lowercase letters) as the initials of the name's words: its score, or nil. Words
--- split at spaces, hyphens and other marks, and at an apostrophe before a capital (Zul'Gurub:
--- "zg"; Hero's stays one word); words starting with a digit are skipped. Two sets: every word,
--- and without of/the/a/an/and. Allocation-free; `out` (a table), when given, gets the initials'
--- byte positions (for the highlight).
function Fuzzy.initials(needle, hay, out)
	local n, m = #needle, #hay
	if n < 2 or m > MAXLEN then return nil end
	-- per set: 0 still matching, 1 used up with words left (a prefix), -1 no match
	local s1, s2, k1, k2 = 0, 0, 1, 1
	local p1, p2 = out and {}, out and {}
	for j = 1, m do
		local b = byte(hay, j)
		if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b >= 192 then
			local start
			if j == 1 then
				start = true
			else
				local p = byte(hay, j - 1)
				if p == 39 then
					start = (b >= 65 and b <= 90) or not wordChar(j > 2 and byte(hay, j - 2) or nil)
				else -- (wordChar, written out: once per letter)
					start = not ((p >= 97 and p <= 122) or (p >= 65 and p <= 90) or (p >= 48 and p <= 57) or p >= 128)
				end
			end
			if start then
				local c = lowerByte(b)
				if s1 == 0 then
					if k1 > n then s1 = 1
					elseif c == byte(needle, k1) then
						if p1 then p1[k1] = j end
						k1 = k1 + 1
					else s1 = -1 end
				end
				if s2 == 0 and not minorWord(hay, j, c) then
					if k2 > n then s2 = 1
					elseif c == byte(needle, k2) then
						if p2 then p2[k2] = j end
						k2 = k2 + 1
					else s2 = -1 end
				end
				if s1 ~= 0 and s2 ~= 0 then break end
			end
		end
	end
	local pos, score
	if s1 == 0 and k1 > n then pos, score = p1, INI_FULL
	elseif s2 == 0 and k2 > n then pos, score = p2, INI_FULL
	elseif n >= 3 and s1 == 1 then pos, score = p1, INI_PREFIX
	elseif n >= 3 and s2 == 1 then pos, score = p2, INI_PREFIX
	else return nil end
	score = score + (n - 1) * CONSEC
	if out then for i = 1, n do out[i] = pos[i] end end
	return score
end

----------------------------------------------------------------------
-- Close spellings
----------------------------------------------------------------------

local dRow0, dRow1, dRow2 = {}, {}, {}

--- The edit distance (optimal string alignment: a letter changed, added, dropped, or two side
--- by side swapped) between `a` and bytes from..to of `s`, both lowercase; nil when it's over
--- `limit`. Reuses three rows: allocation-free.
function Fuzzy.distance(a, s, from, to, limit)
	local n, m = #a, to - from + 1
	if n - m > limit or m - n > limit then return nil end
	local prev2, prev, cur = dRow0, dRow1, dRow2
	for j = 0, m do prev[j] = j end
	for i = 1, n do
		local ai, ap = byte(a, i), i > 1 and byte(a, i - 1)
		cur[0] = i
		local rowMin = i
		for j = 1, m do
			local sj = byte(s, from + j - 1)
			local v = prev[j] + 1
			local w = cur[j - 1] + 1
			if w < v then v = w end
			w = prev[j - 1] + (ai == sj and 0 or 1)
			if w < v then v = w end
			if ap and j > 1 and ai == byte(s, from + j - 2) and ap == sj then
				w = prev2[j - 2] + 1
				if w < v then v = w end
			end
			cur[j] = v
			if v < rowMin then rowMin = v end
		end
		if rowMin > limit then return nil end
		prev2, prev, cur = prev, cur, prev2
	end
	local d = prev[m]
	if d <= limit then return d end
	return nil
end

--- Wrap matched positions (set: [index]=true) in a highlight colour.
--- base is an optional "|cffrrggbb" prefix for unmatched characters.
function Fuzzy.Colorize(name, set, base)
	local out, inRun = {}, false
	local restore = base or ""
	local i, n = 1, #name
	while i <= n do
		-- one whole character: a colour code must never land inside a multi-byte letter
		local b = name:byte(i)
		local len = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
		if i + len - 1 > n then len = n - i + 1 end
		local c = name:sub(i, i + len - 1)
		local hit = false
		if set then
			for k = i, i + len - 1 do
				if set[k] then hit = true break end
			end
		end
		if c == "|" then c = "||" end
		if hit and not inRun then
			out[#out + 1] = Fuzzy.matchColor or "|cffffd200"
			inRun = true
		elseif not hit and inRun then
			out[#out + 1] = "|r" .. restore
			inRun = false
		end
		out[#out + 1] = c
		i = i + len
	end
	if inRun then out[#out + 1] = "|r" end
	if base then return base .. table.concat(out) .. "|r" end
	return table.concat(out)
end
