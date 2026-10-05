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
-- the rows on screen.
local rowM, rowD, rowM2, rowD2 = {}, {}, {}, {}

function Fuzzy.score(needle, hay, lhay)
	local n, m = #needle, #hay
	if n == 0 then return 0 end
	if n > m or m > MAXLEN then return nil end
	lhay = lhay or ns.Lower(hay)
	if n == m then return lhay == needle and EXACT or nil end
	local sub = substringScore(needle, hay, lhay, n, m)
	if sub then return sub end
	-- cheap subsequence check first; nothing before the first letter's first match counts
	local first = find(lhay, ssub(needle, 1, 1), 1, true)
	if not first then return nil end
	local pos = first
	for i = 2, n do
		pos = find(lhay, ssub(needle, i, i), pos + 1, true)
		if not pos then return nil end
	end
	local Mp, Dp, Mc, Dc = rowM, rowD, rowM2, rowD2
	Mp[first - 1], Dp[first - 1] = MIN, MIN
	Mc[first - 1], Dc[first - 1] = MIN, MIN
	for i = 1, n do
		local nc = byte(needle, i)
		local prev = MIN
		local gap = (i == n) and TRAIL or INNER
		local last = first > 1 and byte(hay, first - 1) or 47
		for j = first, m do
			local c = byte(hay, j)
			local bonus = bonusFor(last, c)
			last = c
			if byte(lhay, j) == nc then
				local s
				if i == 1 then
					s = (j - 1) * LEAD + bonus
				elseif j > first then
					local a, b = Mp[j - 1] + bonus, Dp[j - 1] + CONSEC
					s = a > b and a or b
				else
					s = MIN
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
