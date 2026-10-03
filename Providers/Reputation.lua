local ns = select(2, ...)

-- Reputations: every faction you know, searchable by name or with @reputation (@rep,
-- @faction), showing your standing (Honored, Revered...) and progress. Enter opens the
-- Reputation tab of the character window (through the game's own key, TOGGLECHARACTER2)
-- and points at the faction; Shift+Enter makes it your watched reputation (the bar).
--
-- Factions under a collapsed header aren't in the game's list, so headers are expanded
-- while reading and collapsed again afterwards (game state only; no window is touched).

local R = {}
ns.Reputation = R

local function Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local function Str(v)
	if type(v) ~= "string" or v == "" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function Num(v)
	if type(v) ~= "number" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

--- The faction list API, retail (C_Reputation) or classic (GetFactionInfo).
local function Count()
	local C = _G.C_Reputation
	if C and C.GetNumFactions then return Safe(C.GetNumFactions) or 0 end
	return Safe(_G.GetNumFactions) or 0
end

--- One row of the faction list as a table, whichever API this client has.
local function Row(i)
	local C = _G.C_Reputation
	if C and C.GetFactionDataByIndex then
		local d = Safe(C.GetFactionDataByIndex, i)
		if type(d) ~= "table" then return nil end
		return {
			name = Str(d.name), id = d.factionID, header = d.isHeader, collapsed = d.isCollapsed,
			hasRep = d.isHeaderWithRep, reaction = Num(d.reaction), watched = d.isWatched,
			min = Num(d.currentReactionThreshold), max = Num(d.nextReactionThreshold), value = Num(d.currentStanding),
			desc = Str(d.description),
		}
	end
	if not _G.GetFactionInfo then return nil end
	local name, desc, reaction, min, max, value, _, _, header, collapsed, hasRep, watched, _, id =
		Safe(_G.GetFactionInfo, i)
	return {
		name = Str(name), id = id, header = header, collapsed = collapsed, hasRep = hasRep,
		reaction = Num(reaction), watched = watched, min = Num(min), max = Num(max), value = Num(value),
		desc = Str(desc),
	}
end

local function Expand(i)
	local C = _G.C_Reputation
	if C and C.ExpandFactionHeader then return Safe(C.ExpandFactionHeader, i) end
	return Safe(_G.ExpandFactionHeader, i)
end

local function Collapse(i)
	local C = _G.C_Reputation
	if C and C.CollapseFactionHeader then return Safe(C.CollapseFactionHeader, i) end
	return Safe(_G.CollapseFactionHeader, i)
end

--- Every faction row, with collapsed headers opened for the read and closed again after.
local function ReadAll()
	local opened = {}
	local i, guard = 1, 0
	while i <= Count() and guard < 500 do
		local r = Row(i)
		if r and r.header and r.collapsed and r.name then
			Expand(i)
			opened[#opened + 1] = r.name
		end
		i, guard = i + 1, guard + 1
	end
	local rows, path = {}, {}
	for j = 1, Count() do
		local r = Row(j)
		if r and r.name then
			if r.header then path[#path + 1] = r.name end
			r.group = path[#path - (r.header and 1 or 0)]
			rows[#rows + 1] = r
		end
	end
	-- close what was opened, last first (indexes shift as headers close)
	for k = #opened, 1, -1 do
		for j = Count(), 1, -1 do
			local r = Row(j)
			if r and r.header and r.name == opened[k] and not r.collapsed then
				Collapse(j)
				break
			end
		end
	end
	return rows
end

local function Standing(reaction)
	if not reaction then return nil end
	local sex = UnitSex and UnitSex("player") or nil
	local label = GetText and Safe(GetText, "FACTION_STANDING_LABEL" .. reaction, sex)
	return Str(label) or Str(_G["FACTION_STANDING_LABEL" .. reaction])
end

local function Hex(reaction)
	local c = _G.FACTION_BAR_COLORS and _G.FACTION_BAR_COLORS[reaction]
	if type(c) ~= "table" or not c.r then return nil end
	return ("|cff%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

--- Friendship-style factions (the "Good Friend" kind) have their own rank names.
local function Friendship(id)
	local G = _G.C_GossipInfo
	local f = id and G and G.GetFriendshipReputation and Safe(G.GetFriendshipReputation, id)
	if type(f) == "table" and f.friendshipFactionID and f.friendshipFactionID > 0 then
		return Str(f.reaction), Num(f.standing), Num(f.reactionThreshold), Num(f.nextThreshold)
	end
end

local function RepOpen()
	local f = _G.ReputationFrame
	return f and f.IsVisible and f:IsVisible() and true or false
end

--- Runs once the Reputation tab is showing: scroll the list to the faction and point at it.
local function ShowFaction(e)
	local H = ns.Highlight
	local scrolled = false
	H:When(function()
		local f = _G.ReputationFrame
		if not (f and f:IsVisible()) then return nil end
		local function find()
			return ns.FindFrame(f, function(b)
				if b.factionID ~= nil then return b.factionID == e.factionID end
				local d = b.GetElementData and select(2, pcall(b.GetElementData, b))
				if type(d) == "table" and d.factionID ~= nil then return d.factionID == e.factionID end
				if not b.Click then return false end
				for _, r in ipairs({ b:GetRegions() }) do
					if r.GetObjectType and r:GetObjectType() == "FontString" and r:GetText() == e.name then return true end
				end
				return false
			end, 10)
		end
		local row = find()
		local box = f.ScrollBox
		if not row and not scrolled and box and box.ScrollToElementDataByPredicate then
			scrolled = true
			pcall(box.ScrollToElementDataByPredicate, box, function(node)
				local d = type(node) == "table" and (node.GetData and node:GetData() or node)
				return type(d) == "table" and (d.factionID == e.factionID or d.name == e.name)
			end)
			row = find()
		end
		return row
	end, function(row)
		H:Show(row)
	end, 20, function()
		ns:Trace("reputation: no row for " .. tostring(e.name) .. " (it may be under a collapsed header)")
	end)
end

local function Watch(e)
	local C = _G.C_Reputation
	local ok
	if C and C.SetWatchedFactionByID and e.factionID then
		ok = ns.Professions.Guarded("SetWatchedFactionByID", C.SetWatchedFactionByID, e.factionID)
	elseif _G.SetWatchedFactionIndex then
		-- classic: by list position, which may have moved since the list was read
		for i = 1, Count() do
			local r = Row(i)
			if r and r.name == e.name then
				ok = ns.Professions.Guarded("SetWatchedFactionIndex", _G.SetWatchedFactionIndex, i)
				break
			end
		end
	end
	ns:Print(ok and ("Watching " .. e.name .. ".") or ("Couldn't watch " .. e.name .. "."))
end

-- no character key to ride on: say so rather than open it from our code
local function NoKey(e)
	ns:Print("Bind a key to the Reputation tab to open it from here (" .. e.name .. ": " .. (e.standing or "?") .. ").")
end
local REP_SECURE = { binding = "TOGGLECHARACTER2" }

ns:RegisterProvider("reputation", {
	label = "Reputation",
	color = "ff9fc6ff",
	aliases = { "reputation", "reputations", "rep", "reps", "faction", "factions", "standing", "repuatation" },
	noCombat = true, -- opening the character window is blocked in combat
	events = { "UPDATE_FACTION" },
	guard = 2,
	selfEvents = true, -- reading expands and collapses headers, which fires UPDATE_FACTION
	collect = function()
		local out = {}
		for _, r in ipairs(ReadAll()) do
			if not r.header or r.hasRep then
				local standing = Standing(r.reaction)
				local cur, lo, hi = r.value, r.min, r.max
				local fr, fcur, flo, fhi = Friendship(r.id)
				if fr then standing, cur, lo, hi = fr, fcur or cur, flo or lo, fhi or hi end
				local progress
				if cur and lo and hi and hi > lo then
					progress = math.floor(cur - lo + 0.5) .. "/" .. math.floor(hi - lo + 0.5)
				end
				local parts = {}
				if standing then parts[#parts + 1] = standing end
				if progress then parts[#parts + 1] = progress end
				if r.watched then parts[#parts + 1] = "watched" end
				out[#out + 1] = {
					key = r.id or r.name,
					name = r.name,
					icon = "Interface\\Icons\\INV_Misc_Note_02",
					color = Hex(r.reaction),
					detail = table.concat(parts, "  "),
					text = "reputation faction standing " .. (standing or "") .. " " .. (r.group or "") .. " " .. (r.desc or ""),
					tip = r.group and (r.group .. (r.desc and ("\n" .. r.desc) or "")) or r.desc,
					factionID = r.id,
					standing = standing,
					secure = REP_SECURE,
					isOpen = RepOpen,
					after = ShowFaction,
					activate = NoKey,
					-- Shift+Enter: make it the watched reputation (the bar)
					secondary = Watch,
				}
			end
		end
		return out
	end,
})

R.ReadAll = ReadAll
