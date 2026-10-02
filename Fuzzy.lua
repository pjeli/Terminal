local ns = select(2, ...)

-- fzy-style fuzzy matcher (Needleman-Wunsch style DP with word-boundary bonuses).
local Fuzzy = {}
ns.Fuzzy = Fuzzy

local MIN = -math.huge
local LEAD, TRAIL, INNER = -0.005, -0.005, -0.01
local CONSEC, SLASH, WORD, CAPITAL, DOT = 1.0, 0.9, 0.8, 0.7, 0.6
local MAXLEN = 256
local EXACT = 100

local byte, find = string.byte, string.find
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

--- needle must already be lowercase. lhay is optional (lowercased hay).
--- Returns score, positions (array of byte indices in hay) or nil if no match.
function Fuzzy.match(needle, hay, lhay)
	local n, m = #needle, #hay
	if n == 0 then return 0, {} end
	if n > m or m > MAXLEN then return nil end
	lhay = lhay or hay:lower()

	-- cheap subsequence check first
	local pos = 0
	for i = 1, n do
		pos = find(lhay, needle:sub(i, i), pos + 1, true)
		if not pos then return nil end
	end

	if n == m then
		local p = {}
		for i = 1, n do p[i] = i end
		return EXACT, p
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

--- Split a query into lowercase whitespace-separated tokens.
function Fuzzy.tokens(q)
	local t = {}
	for w in (q or ""):lower():gmatch("%S+") do t[#t + 1] = w end
	return t
end

--- Wrap matched positions (set: [index]=true) in a highlight colour.
--- base is an optional "|cffrrggbb" prefix for unmatched characters.
function Fuzzy.Colorize(name, set, base)
	local out, inRun = {}, false
	local restore = base or ""
	for i = 1, #name do
		local c = name:sub(i, i)
		if c == "|" then c = "||" end
		local hit = set and set[i]
		if hit and not inRun then
			out[#out + 1] = Fuzzy.matchColor or "|cffffd200"
			inRun = true
		elseif not hit and inRun then
			out[#out + 1] = "|r" .. restore
			inRun = false
		end
		out[#out + 1] = c
	end
	if inRun then out[#out + 1] = "|r" end
	if base then return base .. table.concat(out) .. "|r" end
	return table.concat(out)
end
