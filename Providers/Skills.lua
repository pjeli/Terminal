local ns = select(2, ...)

-- Skills (the character window's Skills tab): weapon skills, languages, armor
-- proficiencies, professions... searchable by name or group, or only skills with @skill.
-- Results show the rank ("150/300", plus any bonus). Enter opens the Skills tab through the
-- game's own key (TOGGLECHARACTER1) and points at the skill; Shift+Enter prints the
-- skill's rank and description in chat.
--
-- Read through Forever's C_SkillInfo (or the classic GetSkillLineInfo). Groups that are
-- collapsed are expanded for the read and collapsed again afterwards.

local K = {}
ns.Skills = K

local function Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
	if ok then return a, b, c, d, e, f, g, h end
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

local function API() return _G.C_SkillInfo end

local function Count()
	local S = API()
	if S and S.GetNumSkillLines then return Safe(S.GetNumSkillLines) or 0 end
	return Safe(_G.GetNumSkillLines) or 0
end

--- One line of the skills list as a table, whichever API this client has.
local function Line(i)
	local S = API()
	if S and S.GetSkillLineInfo then
		local d = Safe(S.GetSkillLineInfo, i)
		if type(d) ~= "table" then return nil end
		return {
			name = Str(d.name or d.skillName), header = d.isHeader,
			expanded = d.isExpanded, collapsed = d.isCollapsed,
			rank = Num(d.rank or d.skillRank), max = Num(d.maxRank or d.skillMaxRank or d.max),
			bonus = Num(d.modifier or d.skillModifier), id = d.skillID or d.skillLineID,
			desc = Str(d.description),
		}
	end
	if not _G.GetSkillLineInfo then return nil end
	local name, header, expanded, rank, _, modifier, maxRank, _, _, _, _, _, desc = Safe(_G.GetSkillLineInfo, i)
	return {
		name = Str(name), header = header, expanded = expanded, rank = Num(rank), max = Num(maxRank),
		bonus = Num(modifier), desc = Str(desc),
	}
end

local function IsCollapsed(l)
	if l.collapsed ~= nil then return l.collapsed and true or false end
	if l.expanded ~= nil then return not l.expanded end
	return false
end

local function Expand(i)
	local S = API()
	if S and S.ExpandSkillHeader then return Safe(S.ExpandSkillHeader, i) end
	return Safe(_G.ExpandSkillHeader, i)
end

local function Collapse(i)
	local S = API()
	if S and S.CollapseSkillHeader then return Safe(S.CollapseSkillHeader, i) end
	return Safe(_G.CollapseSkillHeader, i)
end

--- Every skill line, with collapsed groups opened for the read and closed again after.
local function ReadAll()
	local opened = {}
	local i, guard = 1, 0
	while i <= Count() and guard < 300 do
		local l = Line(i)
		if l and l.header and l.name and IsCollapsed(l) then
			Expand(i)
			opened[#opened + 1] = l.name
		end
		i, guard = i + 1, guard + 1
	end
	local lines, group = {}, nil
	for j = 1, Count() do
		local l = Line(j)
		if l and l.name then
			if l.header then group = l.name else l.group = group end
			lines[#lines + 1] = l
		end
	end
	for k = #opened, 1, -1 do
		for j = Count(), 1, -1 do
			local l = Line(j)
			if l and l.header and l.name == opened[k] and not IsCollapsed(l) then
				Collapse(j)
				break
			end
		end
	end
	return lines
end

local function Rank(l)
	if not l.rank then return nil end
	local s = l.max and l.max > 0 and (l.rank .. "/" .. l.max) or tostring(l.rank)
	if l.bonus and l.bonus ~= 0 then s = s .. (l.bonus > 0 and " (+" or " (") .. l.bonus .. ")" end
	return s
end

local function SkillsOpen()
	local f = _G.SkillsFrame or _G.SkillFrame
	return f and f.IsVisible and f:IsVisible() and true or false
end

--- Runs once the Skills tab is showing: scroll to the skill and point at its row.
local function ShowSkill(e)
	local H = ns.Highlight
	local scrolled = false
	H:When(function()
		local f = _G.SkillsFrame or _G.SkillFrame
		if not (f and f:IsVisible()) then return nil end
		local function find()
			return ns.FindFrame(f, function(b)
				if not b.Click then return false end
				if b.GetText then
					local ok, t = pcall(b.GetText, b)
					if ok and type(t) == "string" and t:find(e.name, 1, true) == 1 then return true end
				end
				for _, r in ipairs({ b:GetRegions() }) do
					if r.GetObjectType and r:GetObjectType() == "FontString" and r:GetText() == e.name then return true end
				end
				return false
			end, 10)
		end
		local row = find()
		local box = f.ScrollBox or (f.ListScrollFrame and f.ListScrollFrame.ScrollBox)
		if not row and not scrolled and box and box.ScrollToElementDataByPredicate then
			scrolled = true
			pcall(box.ScrollToElementDataByPredicate, box, function(node)
				local d = type(node) == "table" and (node.GetData and node:GetData() or node)
				return type(d) == "table" and (d.name == e.name or d.skillName == e.name)
			end)
			row = find()
		end
		return row
	end, function(row)
		H:Show(row)
	end, 20, function()
		ns:Trace("skills: no row for " .. tostring(e.name) .. " on the Skills tab")
	end)
end

local function Describe(e)
	local lines = { e.name .. (e.rankText and (": " .. e.rankText) or "") .. (e.group and ("  (" .. e.group .. ")") or "") }
	if e.desc then lines[#lines + 1] = "  " .. e.desc end
	ns:Output(lines)
end

local SKILL_SECURE = { binding = "TOGGLECHARACTER1", click = ns.Secure.SKILLS_CLICK } -- click: a mouse click opens the tab

ns:RegisterProvider("skills", {
	label = "Skill",
	color = "ffd0c090",
	aliases = { "skill", "skills", "weaponskill", "language", "languages", "proficiency" },
	noCombat = true, -- opening the character window is blocked in combat
	events = { "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" },
	guard = 2,
	selfEvents = true, -- reading expands and collapses groups, which fires SKILL_LINES_CHANGED
	collect = function()
		local out = {}
		for _, l in ipairs(ReadAll()) do
			if not l.header then
				local rank = Rank(l)
				local parts = {}
				if rank then parts[#parts + 1] = rank end
				if l.group then parts[#parts + 1] = l.group end
				out[#out + 1] = {
					key = l.id or l.name,
					name = l.name,
					icon = "Interface\\Icons\\INV_Sword_04",
					detail = table.concat(parts, "  "),
					text = "skill " .. (l.group or "") .. " " .. (l.desc or ""),
					tip = l.desc,
					rankText = rank, group = l.group, desc = l.desc,
					secure = SKILL_SECURE,
					isOpen = SkillsOpen,
					after = ShowSkill,
					activate = Describe, -- no Skills key to ride on: the details go to chat
					secondary = Describe,
				}
			end
		end
		return out
	end,
})

K.ReadAll = ReadAll
