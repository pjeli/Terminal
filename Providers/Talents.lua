local ns = select(2, ...)
local H = ns.Highlight

-- Talents: every talent in your tree, taken or not, searchable by name or tree, opened in
-- the talent window with its node highlighted. Forever's talents are a C_Traits tree split
-- into the classic three tabs (the same way ClassicUIForever reads it).
-- Other classes' talents (0.44.7) are listed too, below your own (`_rank`): read once through the game's "view a
-- loadout" config (C_ClassTalents.InitializeViewLoadout: what the talent window shows a shared build with, C calls),
-- kept in the saved variables per game build. Enter shows the talent's Wowhead page; class:mage narrows to a class.

local TL = {}
ns.Talents = TL

-- talent windows we know by name, first visible wins (any other visible "...Talent..."
-- window is tried after these)
local ROOTS = { "ClassicUIForeverTalents", "PlayerSpellsFrame", "ClassTalentFrame", "PlayerTalentFrame", "TalentFrame" }
-- Forever shows TalentMicroButton; PlayerSpellsMicroButton is the retail one
TL.BUTTONS = { "TalentMicroButton", "PlayerSpellsMicroButton" }
-- opened through the game's own Talents keybinding command; the buttons are the fallback
TL.SECURE = { binding = "TOGGLETALENTS", buttons = TL.BUTTONS }

local TAKEN = "|cff40ff40Taken|r"
local NOT_TAKEN = "|cff8a8a8aNot taken|r"

local function ConfigID()
	local SI = C_SpecializationInfo
	local spec = SI and SI.GetActiveSpecGroup and SI.GetActiveSpecGroup()
	local id = spec and SI.GetCombatConfigIDForSpecGroup and SI.GetCombatConfigIDForSpecGroup(spec)
	if not id and C_ClassTalents and C_ClassTalents.GetActiveConfigID then id = C_ClassTalents.GetActiveConfigID() end
	return id
end

local function Usable(f)
	return f and not (f.IsForbidden and f:IsForbidden()) and f.IsVisible and f:IsVisible()
end

function TL.Window()
	for _, name in ipairs(ROOTS) do
		local f = _G[name]
		if Usable(f) then return f, name end
	end
	-- some other talent window (this client's own, or another addon's)
	for _, f in ipairs({ UIParent:GetChildren() }) do
		local name = ns.FrameName(f)
		if name and name:find("Talent") and not name:find("^Terminal") and Usable(f) then
			return f, name
		end
	end
end

function TL.IsOpen() return TL.Window() ~= nil end

local function IsNode(f, nodeID)
	if f.nodeID == nodeID then return true end
	if type(f.talent) == "table" and f.talent.nodeID == nodeID then return true end -- ClassicUIForever
	if f.GetNodeID then -- Blizzard talent buttons
		local ok, id = pcall(f.GetNodeID, f)
		if ok and id == nodeID then return true end
	end
	return false
end

local function AnyNode(f)
	if type(f.nodeID) == "number" then return true end
	if type(f.talent) == "table" and f.talent.nodeID then return true end
	if f.GetNodeID then
		local ok, id = pcall(f.GetNodeID, f)
		return ok and type(id) == "number"
	end
	return false
end

local Plain = ns.Plain -- (Locale.lua)

-- a tab label for the tree: "Fury", or "Fury (5)" with points spent
local function TabText(f, tabName)
	local texts = ns.FrameTexts(f)
	for _, t in ipairs(texts) do
		t = Plain(t)
		if t == tabName then return true end
		local nxt = t:sub(#tabName + 1, #tabName + 1)
		if t:sub(1, #tabName) == tabName and (nxt == " " or nxt == "(") then return true end
	end
	return false
end

local function FindTab(root, rootName, tabName, tabIndex)
	if tabName and tabName ~= "" then
		local tab = ns.FindFrame(root, function(f) return f.Click and TabText(f, tabName) end, 10)
		if tab then return tab end
	end
	-- unlabelled tabs: the window's numbered tab buttons, in tree order
	if tabIndex and rootName then
		local t = _G[rootName .. "Tab" .. tabIndex]
		if Usable(t) and t.Click then return t end
	end
end

-- Blizzard's own talent windows: nothing in them is clicked from Terminal's code (a click runs tainted and
-- the window's state stays so). ClassicUIForever's and classic clients' windows are turned as a player would.
local BLIZZARD_ROOTS = { PlayerSpellsFrame = true, ClassTalentFrame = true }

--- Highlight the talent's node. Windows that show one tree at a time only have buttons for
--- the tree on screen, so if the node isn't there, the talent's tree tab is clicked first.
function TL.Highlight(nodeID, tabName, tabIndex)
	local switched = false
	H:Find(function()
		local root, rootName = TL.Window()
		if not root then return nil end
		local node = ns.FindFrame(root, function(f) return IsNode(f, nodeID) end, 14)
		if node then return node end
		if not switched and not BLIZZARD_ROOTS[rootName] then
			local tab = FindTab(root, rootName, tabName, tabIndex)
			if tab then
				switched = true
				pcall(tab.Click, tab)
			end
		elseif not switched then
			switched = true
			ns:Trace("talents: " .. tostring(rootName) .. " shows another tree; its tabs aren't clicked from here (taint)")
		end
		return nil
	end, 60) -- a freshly opened window can take a moment to build its buttons
end

-- Direct opener: only used when neither the keybinding nor a micro button is available.
local function OpenFallback(e)
	ns:Trace("DIRECT talent window open (addon code, may be blocked)")
	ns.LoadBlizz("Blizzard_PlayerSpells")
	if PlayerSpellsUtil and PlayerSpellsUtil.OpenToClassTalentsTab then
		pcall(PlayerSpellsUtil.OpenToClassTalentsTab)
	elseif PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then
		pcall(PlayerSpellsUtil.ToggleClassTalentFrame)
	elseif ToggleTalentFrame then
		pcall(ToggleTalentFrame)
	end
	TL.Highlight(e.nodeID, e.tab, e.tabIndex)
end

-- a tree's tabs: { groupID -> tab name }, { groupID -> its place }
local function ReadTabs(treeID)
	local tabs, order = {}, {}
	local ok, groups = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
	if ok and type(groups) == "table" then
		table.sort(groups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
		for i, g in ipairs(groups) do
			tabs[g.groupID] = g.displayName
			order[g.groupID] = i
		end
	end
	return tabs, order
end

--- Reads the active talent tree. Returns configID, treeID, { groupID -> tab name }.
local function ReadTree()
	if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes) then return end
	local configID = ConfigID()
	local config = configID and C_Traits.GetConfigInfo(configID)
	local treeID = config and config.treeIDs and config.treeIDs[1]
	if not treeID then return end
	local tabs, order = ReadTabs(treeID)
	return configID, treeID, tabs, order
end

--- Every visible talent of a tree as the config sees it: { nodeID, name, spellID, icon, tab, tabIndex, rank, maxRanks }.
local function ReadNodes(configID, treeID, tabs, order)
	local out = {}
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
		local node = C_Traits.GetNodeInfo(configID, nodeID)
		if node and node.isVisible ~= false then
			local entryID = node.activeEntry and node.activeEntry.entryID or (node.entryIDs and node.entryIDs[1])
			local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
			local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
			local spellID = def and (def.overriddenSpellID or def.spellID)
			local name = def and def.overrideName
			if (not name or name == "") and spellID and C_Spell and C_Spell.GetSpellName then
				name = C_Spell.GetSpellName(spellID)
			end
			if type(name) == "string" and name ~= "" and not ns.Secret(name) then
				local tab, tabIndex
				for _, gid in ipairs(node.groupIDs or {}) do
					if tabs[gid] then tab, tabIndex = tabs[gid], order[gid] break end
				end
				out[#out + 1] = { nodeID = nodeID, name = name, spellID = spellID, tab = tab, tabIndex = tabIndex,
					rank = node.ranksPurchased or 0, maxRanks = node.maxRanks or 1,
					icon = (def and def.overrideIcon)
						or (spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)) }
			end
		end
	end
	return out
end

----------------------------------------------------------------------
-- Other classes' talents
----------------------------------------------------------------------

TL.OTHER_RANK = -1.5 -- (below your own class's among equal matches: class:mage keeps only those anyway)
-- the classes WoW Forever has (the classic nine: WhatsTraining's Camelot data lists these); the retail API may name more
-- (Death Knight, Monk, Demon Hunter, Evoker), left out unless you play one
TL.PLAYABLE = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true,
	WARLOCK = true, DRUID = true }
TL.RETRY = 10 -- (s: read skipped in combat or with a talent window open, asked again this long after)
TL.CACHE_FORMAT = 1
TL.otherRows = {} -- classFile -> the rows last made for it, and what they were made from (the talents list's collect)

local function MyClassFile()
	local ok, _, file = pcall(UnitClass, "player")
	return ok and file or nil
end

local function SpecsOf(classID)
	local SI = C_SpecializationInfo
	local count = (SI and SI.GetNumSpecializationsForClassID) or _G.GetNumSpecializationsForClassID
	local info = (SI and SI.GetSpecializationInfoForClassID) or _G.GetSpecializationInfoForClassID
	local out = {}
	if not (count and info) then return out end
	local ok, n = pcall(count, classID)
	for i = 1, (ok and tonumber(n)) or 0 do
		local okI, id = pcall(info, classID, i)
		if okI and type(id) == "number" then out[#out + 1] = id end
	end
	return out
end

--- One class's talents, read through the game's view config (every spec's tree once). nil when the game can't.
function TL.ReadClass(classID, level)
	local CT = C_ClassTalents
	local view = Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID
	if not (CT and CT.InitializeViewLoadout and CT.GetTraitTreeForSpec and view and C_Traits and C_Traits.GetTreeNodes) then return nil end
	local guarded = ns.Guarded
	local out, seenTree, seenNode = {}, {}, {}
	for _, specID in ipairs(SpecsOf(classID)) do
		local ok, treeID = pcall(CT.GetTraitTreeForSpec, specID)
		if ok and treeID and not seenTree[treeID] then
			seenTree[treeID] = true
			local inited = guarded and guarded("viewloadout", CT.InitializeViewLoadout, specID, level)
				or (not guarded and pcall(CT.InitializeViewLoadout, specID, level))
			if not inited then return nil end
			local tabs, order = ReadTabs(treeID)
			local okR, nodes = pcall(ReadNodes, view, treeID, tabs, order)
			for _, n in ipairs(okR and nodes or {}) do
				if not seenNode[n.nodeID] then
					seenNode[n.nodeID] = true
					out[#out + 1] = { n.nodeID, n.name, n.spellID, n.tab or "", n.tabIndex or 0, n.maxRanks, n.icon }
				end
			end
		end
	end
	return out
end

local function CacheKey()
	local ok, _, build = pcall(GetBuildInfo)
	return TL.CACHE_FORMAT .. ":" .. tostring(ok and build or "?")
end

-- in combat, or with a talent window open: the talents list is made again once that's over (checked every TL.RETRY s)
local function ReadLater()
	if TL.retrying or not (C_Timer and C_Timer.After) then return end
	TL.retrying = true
	local function Try()
		if (InCombatLockdown and InCombatLockdown()) or TL.IsOpen() then C_Timer.After(TL.RETRY, Try) return end
		TL.retrying = false
		local p = ns.providers.talents
		if p then p._dirty = true end
	end
	C_Timer.After(TL.RETRY, Try)
end

--- Every other class's talents, from the saved copy when it's this build's, else read now (not in combat, not while a
--- talent window shows: the view config is the window's too; read a moment after then). { classFile = { {nodeID, name,
--- spellID, tab, tabIndex, maxRanks, icon}, ... } }, and { classFile = class name }.
function TL.OtherClasses()
	local db = ns.db or {}
	local key, mine = CacheKey(), MyClassFile()
	local cache = db.talentCache
	if not (cache and cache.key == key and cache.classes) then
		if TL.triedOthers == key then return {}, {} end -- (read once a session when nothing came of it)
		if not GetClassInfo then return {}, {} end
		if (InCombatLockdown and InCombatLockdown()) or TL.IsOpen() then ReadLater() return {}, {} end
		local level = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
		local classes, names, read = {}, {}, 0
		local okN, n = pcall(GetNumClasses or function() return 13 end)
		for id = 1, (okN and tonumber(n)) or 13 do
			local okC, name, file = pcall(GetClassInfo, id)
			if okC and file and name and (TL.PLAYABLE[file] or file == mine) then
				local rows = TL.ReadClass(id, level)
				if rows == nil then
					ns:Trace("talents: other classes can't be read here (no view loadout)")
					TL.triedOthers = key
					return {}, {}
				end
				if #rows > 0 then classes[file], names[file], read = rows, name, read + 1 end
			end
		end
		ns:Trace("talents: read " .. read .. " classes' talents")
		if read == 0 then TL.triedOthers = key return {}, {} end -- (nothing read: not kept, tried again next session)
		cache = { key = key, classes = classes, names = names }
		db.talentCache = cache
	end
	local out, names = {}, {}
	for file, rows in pairs(cache.classes) do
		if file ~= mine and TL.PLAYABLE[file] then out[file], names[file] = rows, (cache.names or {})[file] or file end
	end
	return out, names
end

-- Wowhead has a WoW Forever section: a talent of another class is shown there (its tree isn't yours to open)
TL.WOWHEAD_SPELL = "https://www.wowhead.com/forever/spell=%d"
local function ShowOnWowhead(e)
	if not e.spellID then ns:Print("No page for " .. tostring(e.name) .. ".") return end
	ns:ShowText("Wowhead: " .. tostring(e.name), TL.WOWHEAD_SPELL:format(e.spellID), { compact = true })
end

local function HighlightNode(e) TL.Highlight(e.nodeID, e.tab, e.tabIndex) end

local function TalentLink(e) return e.spellID and C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(e.spellID) or nil end
local function LinkTalent(e) ns.LinkInChat(TalentLink(e)) end
local TALENT_CHATBOX = ns.ChatBoxSpec(TalentLink)

ns:RegisterProvider("talents", {
	label = "Talent",
	color = "ffa3e05f",
	aliases = { "talent", "talents", "tree" },
	events = { "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "PLAYER_TALENT_UPDATE",
		"ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "CHARACTER_POINTS_CHANGED" },
	guard = 1,
	collect = function()
		local out = {}
		local mine = MyClassFile()
		local okName, myName = pcall(UnitClass, "player")
		myName = okName and type(myName) == "string" and myName or nil
		local configID, treeID, tabs, order = ReadTree()
		if treeID then
			for _, n in ipairs(ReadNodes(configID, treeID, tabs, order)) do
				local tab, rank = n.tab, n.rank
				local taken = rank > 0
				out[#out + 1] = {
					key = n.nodeID,
					name = n.name,
					color = (not taken) and "|cffa0a0a0" or nil,
					icon = n.icon,
					detail = ((tab and tab ~= "") and (tab .. "  ") or "") .. (taken and TAKEN or NOT_TAKEN)
						.. " " .. rank .. "/" .. n.maxRanks,
					text = (tab or "") .. " " .. (myName or "") .. " talent",
					getLink = TalentLink, -- (made when selected, not per talent on every rebuild)
					nodeID = n.nodeID,
					tab = tab,
					tabIndex = n.tabIndex,
					taken = taken,
					spellID = n.spellID,
					classFile = mine, className = myName,
					-- opened through the game's Talents keybinding, then the node is highlighted
					secure = TL.SECURE,
					isOpen = TL.IsOpen,
					after = HighlightNode,
					activate = OpenFallback,
					-- Shift+Enter: link the talent in chat
					secondary = LinkTalent,
					secondarySecure = TALENT_CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen,
				}
			end
		end
		-- other classes' talents, below yours: Enter shows the Wowhead page, Shift+Enter links it in chat. Your own tree's
		-- events rebuild this list often: each class's rows (~800 in all) are made once and used again while they'd come
		-- out the same (TL.otherRows: the same saved talents, the class shown the same way); only the icon is asked again.
		local others, names = TL.OtherClasses()
		local made = {}
		for file, rows in pairs(others) do
			local cname = names[file] or file
			local hex = ns.ClassHex and ns.ClassHex(file) -- ("|cff3fc7eb": the colour code whole)
			local shown = hex and (hex .. cname .. "|r") or cname
			local m = TL.otherRows[file]
			if m and m.from == rows and m.shown == shown and m.cname == cname and m.rank == TL.OTHER_RANK
				and m.never == ns.ChatBoxNeverOpen then
				for i, e in ipairs(m.rows) do
					local r = rows[i]
					e.icon = r[7] or (r[3] and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(r[3]))
					out[#out + 1] = e
				end
			else
				m = { from = rows, shown = shown, cname = cname, rank = TL.OTHER_RANK, never = ns.ChatBoxNeverOpen, rows = {} }
				for _, r in ipairs(rows) do
					local tab = r[4] ~= "" and r[4] or nil
					local e = {
						key = file .. ":" .. r[1],
						name = r[2],
						icon = r[7] or (r[3] and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(r[3])),
						detail = shown .. "  " .. (tab and (tab .. "  ") or "") .. r[6] .. (r[6] == 1 and " rank" or " ranks"),
						text = (tab or "") .. " " .. cname .. " talent",
						getLink = TalentLink,
						nodeID = r[1], tab = tab, tabIndex = r[5], spellID = r[3],
						classFile = file, className = cname, other = true,
						_rank = TL.OTHER_RANK,
						activate = ShowOnWowhead,
						secondary = LinkTalent,
						secondarySecure = TALENT_CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen,
					}
					m.rows[#m.rows + 1] = e
					out[#out + 1] = e
				end
			end
			made[file] = m
		end
		TL.otherRows = made
		return out
	end,
})

-- .talentdebug : what Terminal sees of the open talent window, for bug reports.
ns:RegisterCommand("talentdebug", {
	desc = "Show what Terminal sees in the open talent window (for bug reports)",
	run = function()
		local lines = { "Talent debug (open the talent window first):" }
		local configID, treeID, tabs = ReadTree()
		local names = {}
		for _, n in pairs(tabs or {}) do names[#names + 1] = n end
		lines[#lines + 1] = ("  Tree: config %s, tree %s, tabs: %s"):format(tostring(configID), tostring(treeID),
			#names > 0 and table.concat(names, ", ") or "none")
		local root, rootName = TL.Window()
		lines[#lines + 1] = "  Window: " .. (rootName or "none open")
		if root then
			local nodes, tabButtons, labels = 0, {}, {}
			local function walk(f, depth)
				if depth > 14 or not Usable(f) then return end
				if AnyNode(f) then nodes = nodes + 1 end
				for _, n in ipairs(names) do
					if f.Click and TabText(f, n) then tabButtons[#tabButtons + 1] = n end
				end
				if f.Click and f.GetText and #labels < 10 then
					local ok, t = pcall(f.GetText, f)
					if ok and type(t) == "string" and t ~= "" then labels[#labels + 1] = Plain(t) end
				end
				for _, child in ipairs({ f:GetChildren() }) do walk(child, depth + 1) end
			end
			walk(root, 0)
			lines[#lines + 1] = ("  Talent buttons visible: %d   Tree tabs found: %s"):format(nodes,
				#tabButtons > 0 and table.concat(tabButtons, ", ") or "none")
			local numbered = {}
			for i = 1, 4 do
				if _G[rootName .. "Tab" .. i] then numbered[#numbered + 1] = rootName .. "Tab" .. i end
			end
			lines[#lines + 1] = "  Numbered tabs: " .. (#numbered > 0 and table.concat(numbered, ", ") or "none")
			lines[#lines + 1] = "  Button labels: " .. (#labels > 0 and table.concat(labels, " | ") or "none")
		end
		return lines
	end,
})
