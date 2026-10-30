-- (Terminal: Share, an addon of its own: Terminal's namespace is its public table, _G.Terminal. Not loaded, nothing of
-- this runs: no prefix registered, no message read.)
-- The share shell in this client: what friends share as rows (@shared), what you share, the groups remembered, .share
-- at the prompt, the badge, and the game's calls and events (SSH.game). The protocol itself is Protocol.lua
-- (SSH.Endpoint, reaching the game only through its env); docs/SHARE.md has the design.
local ns = _G.Terminal
if not ns or not ns.Ssh then return end
local L = ns.L

local SSH = ns.Ssh

local C = ns.Crypto
local Lower, Str, Num, Safe = ns.Lower, ns.Str, ns.Num, ns.Safe
local floor, concat, sort = math.floor, table.concat, table.sort
local Canon = SSH.Canon
local SENT, Names = SSH._.SENT, SSH.Names

----------------------------------------------------------------------
-- Rows: @shared
----------------------------------------------------------------------

local nameWait = ns.NameWait("shared")
SSH.nameFrame = nameWait.frame


local WHERE_SAID = { b = L["bags"], k = L["bank"], m = L["mail"], v = L["void storage"], w = L["warband bank"] }
local WHERE_ORDER = { "b", "k", "m", "v", "w" }

-- A friend's item looks as @stored's does (0.58.5, the player: "keep consistency"; .ssh all's one long line of every
-- character stretched the tooltip across the screen): each character a line, its total and where ("Plamen Pally  53
-- bags 18, bank 35"), the total, as @stored's tooltip, chat line and Shift+Enter say them (Stored.lua's own functions);
-- the game's item tooltip above.
local WHERE_WORD = { b = "bags", k = "bank", m = "mail", v = "void", w = "warband" }

--- The row's holders as @stored's are: { [key] = { key, who, where, owner, count } }, a character's places apart;
--- a friend who shares only their bags is one holder, by their name.
local function StoredHolders(friends)
	local out = {}
	for _, h in ipairs(friends) do
		local f = h.friend or {}
		local claim = tostring(f.claim or h.key or h.who)
		if #(h.parts or {}) == 0 then
			out[claim] = { key = claim, who = h.who, where = "bags", owner = claim, count = h.count }
		else
			for _, pt in ipairs(h.parts) do
				local warband = pt.where == "w" or pt.who == ""
				local who = warband and L["%s (warband)"]:format(h.who) or pt.who
				local owner = claim .. "|" .. (warband and "" or pt.who)
				local key = owner .. "|" .. pt.where
				local had = out[key]
				out[key] = { key = key, who = who, where = WHERE_WORD[pt.where] or "bags", owner = owner,
					count = (had and had.count or 0) + pt.n }
			end
		end
	end
	return out
end
SSH.StoredHolders = StoredHolders

local function Holders(e)
	local list = {}
	for _, h in ipairs(e.friends or {}) do list[#list + 1] = h end
	sort(list, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.who < b.who
	end)
	return list
end
SSH.Holders = Holders

--- The item's own tooltip (the game's, as any item row's), then who has how many and where, as @stored's.
local function Tooltip(e, t)
	local shown = e.itemID and pcall(t.SetHyperlink, t, ns.ItemLink(e.itemID) or ("item:" .. e.itemID))
	if not shown then
		local c = e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
		t:SetText(e.name, c and c.r or 1, c and c.g or 1, c and c.b or 1)
	end
	t:AddLine(" ")
	t:AddLine(L["In your friends' bags now (.share)"], 1, 0.82, 0)
	ns.Stored.GroupLines(e, t)
	if e.others then t:AddLine(L["Other friends: %s"]:format(e.others), 0.6, 0.6, 0.6, true) end
	local f = e.friend
	if f and f.groups and next(f.groups) and not (f.groups[SSH.DEFAULT_GROUP] and not next(f.groups, next(f.groups))) then
		t:AddLine(L["Shared in: %s"]:format(Names(f.groups)), 0.6, 0.6, 0.6, true)
	end
	t:AddLine(" ")
	local top = Holders(e)[1]
	ns.KeyHints(t, L["Enter: whisper %s"]:format(top and top.who or "?") .. "    " .. L["Shift+Enter: show in chat"], 0.6, 0.6, 0.6)
end

--- The friend with the most, as a row Social.lua's whisper takes.
local function Top(e)
	local h = Holders(e)[1]
	if not h then return nil end
	local r = h.friend and h.friend.route or {}
	if r.kind == "bn" then return { name = h.who, bnetID = r.bnetID, whisperTo = r.name } end
	return { name = h.who, whisperTo = r.target }
end
SSH.Top = Top

local function Whisper(e)
	local t = Top(e)
	if t and ns.Social then ns.Social.Whisper(t) end
end

--- Shift+Enter, and what follows the link sent to chat: @stored's ("Linen Cloth: 230 in all", " x230: Plamen Pally 53
--- (bags 18, bank 35), ...").
local function Breakdown(e) return ns.Stored.Breakdown(e) end
SSH.Breakdown = Breakdown
local function ChatSummary(e, room) return ns.Stored.ChatSummary(e, room) end

local WHISPER = { macro = function(e)
	local t = Top(e)
	return t and ns.Social and ns.Social.WhisperMacro(t) or nil
end }

-- One row an item a friend (0.58.6, the player: "group and sort by Owner (Cad Man vs Cherry Tusks)"): an item two
-- friends carry is two rows, "Linen Cloth x20 · Cad Man" and "x15 · Cherry Tusks", each with its owner (Aggregate.lua's
-- owner field: the bar's Group and Sort, sort:owner, | group by owner). The tooltip says who else has it.
--
-- (0.58.16, the stress test: tests/stress.py) Rows are compact (ns:CompactMeta): only what a search reads first is on
-- the row (its name, owner, count); the rest (link, quality, holders, detail...) is worked out when asked and kept.
-- Each friend's rows are kept on the friend and made again only when what they sent changed (or an item's name came
-- in): a friend's update no longer remakes every other friend's rows. 10 friends x 500 items: 96 ms and ~10 MB a
-- remake, before.

local ROW_PROTO = {
	tooltip = Tooltip, secure = WHISPER, isOpen = ns.Never, activate = Whisper,
	secondary = function(e) ns:Output(Breakdown(e)) end,
	shareExtra = ChatSummary,
}
local function Keep(t, k, v) if v ~= nil then rawset(t, k, v) end return v end
local ROW_LAZY = {
	quality = function(t) return Keep(t, "quality", ns.ItemQuality(t.itemID)) end,
	color = function(t) return ns.QualityHex(t.quality) end,
	icon = function(t) return Keep(t, "icon", C_Item and C_Item.GetItemIconByID and Safe(C_Item.GetItemIconByID, t.itemID)) end,
	link = function(t)
		local l = ns.ItemLink(t.itemID)
		if l then rawset(t, "link", l) return l end
		return "item:" .. t.itemID
	end,
	-- (where they keep it, bags and bank apart: "x20 · Cad Man · bags 12, bank 8"; 0.59.0, the player: "distinctly
	-- separated as in Bank vs in Bags")
	detail = function(t)
		local f = t.friend
		local by = {}
		for _, pt in ipairs(SSH.Parts(f.entries and f.entries[t.itemID])) do
			local pl = f.places and f.places[pt.place]
			local w = pl and pl.where or "b"
			by[w] = (by[w] or 0) + pt.n
		end
		local where = {}
		for _, w in ipairs(WHERE_ORDER) do
			if by[w] then where[#where + 1] = WHERE_SAID[w] .. " " .. by[w] end
		end
		local d = "x" .. t.total .. ns.DETAIL_SEP .. t.owner
		if #where > 0 then d = d .. ns.DETAIL_SEP .. concat(where, ", ") end
		return Keep(t, "detail", d)
	end,
	-- (the friend as a holder: who, how many, where they keep it)
	friends = function(t)
		local f = t.friend
		local parts = {}
		for _, pt in ipairs(SSH.Parts(f.entries and f.entries[t.itemID])) do
			local pl = f.places and f.places[pt.place]
			if pl then parts[#parts + 1] = { who = pl.who, where = pl.where, n = pt.n } end
		end
		return Keep(t, "friends", { { key = f.claim, who = f.name or "?", count = t.total, friend = f, parts = parts } })
	end,
	holders = function(t) return Keep(t, "holders", StoredHolders(t.friends)) end,
	-- (who else has it: read when its tooltip is drawn)
	others = function(t)
		local out = {}
		for _, o in pairs(SSH.game and SSH.game.friends or {}) do
			local n = o ~= t.friend and o.items[t.itemID]
			if n then out[#out + 1] = (o.name or "?") .. " " .. n end
		end
		sort(out)
		return #out > 0 and concat(out, ", ") or nil
	end,
}
local rowMeta, lowerName = nil, {}

--- A friend's rows: made when they sent something new, or names were still to come.
local function FriendRows(f, p)
	if f.rows and not f.rowsMissing then return f.rows end
	rowMeta = rowMeta or ns:CompactMeta(p, ROW_PROTO, ROW_LAZY)
	local rows, missing = {}, false
	local who = f.name or "?"
	-- (the groups you have in common: "raid linen" finds raid friends' linen)
	local text = "shared friend " .. Lower(who) .. " " .. Names(f.groups):gsub(",", "")
	local claim = tostring(f.claim)
	for id, n in pairs(f.items) do
		local name = nameWait.Name(id)
		if name then
			local ln = lowerName[id]
			if not ln then ln = Lower(name); lowerName[id] = ln end
			rows[#rows + 1] = setmetatable({ _compact = true, key = id .. ":" .. claim, itemID = id, name = name, _lname = ln,
				_ltext = text, owner = who, total = n, friend = f }, rowMeta)
		else
			missing = true
		end
	end
	f.rows, f.rowsMissing = rows, missing or nil
	return rows
end

function SSH.Rows(ep, p)
	p = p or ns.providers.shared
	local out = {}
	for _, f in pairs(ep.friends) do
		for _, row in ipairs(FriendRows(f, p)) do out[#out + 1] = row end
	end
	-- friends' gold (.share all): a row each, "gold" finds them
	for _, g in ipairs(ep:Gold()) do
		local said = L["%s's gold"]:format(g.who)
		local holder = { who = g.who, count = 1, friend = g.friend } -- (Enter whispers them)
		out[#out + 1] = {
			key = "gold:" .. tostring(g.friend.claim), name = said, icon = "Interface\\Icons\\INV_Misc_Coin_01", owner = g.who,
			detail = ns.Money(g.gold), text = "shared friend gold money " .. g.who, money = g.gold,
			friends = { holder }, total = 1,
			tooltip = function(_, t)
				t:SetText(said, 1, 0.82, 0)
				t:AddLine(ns.Money(g.gold), 1, 1, 1)
				t:AddLine(L["All their characters' gold, as they share it (.share all)"], 0.6, 0.6, 0.6, true)
				ns.KeyHints(t, L["Enter: whisper %s"]:format(g.who), 0.6, 0.6, 0.6)
			end,
			secure = WHISPER, isOpen = ns.Never,
			activate = Whisper,
			secondary = function() ns:Output({ said .. ": " .. ns.Money(g.gold) }) end,
			shareLink = function() return said .. ": " .. ns.Money(g.gold, true) end,
		}
	end
	return out
end

function SSH.Busy()
	local n = nameWait.count
	if n > 0 then return L["Loading %d item names from the server for your friends' bags"]:format(n) end
end

-- (this character's bank, as @stored has it, is in what limited, mats and consumables share: when @stored's records
-- change, Syndicator's word after the game's bag events, what you share is sent again. Review, 0.59.0)
if ns.changedHooks then
	ns.changedHooks[#ns.changedHooks + 1] = function(id)
		if id == "stored" and SSH.game and SSH.game:On() then SSH.game:Changed() end
	end
end

ns:RegisterProvider("shared", {
	label = L["Shared"], -- (0.58.12, the player: "Rename @friendsbags to @shared")
	color = "ff7fd4ff",
	aliases = { "shared", "ssh" },
	busy = function() return SSH.Busy() end,
	hintLabel = L["your friends' bags"],
	collect = function(p) return SSH.game and SSH.Rows(SSH.game, p) or {} end,
})

----------------------------------------------------------------------
-- .ssh
----------------------------------------------------------------------

-- What you share (the player's call, 0.58.2): limited by default
local MODES = { all = true, limited = true, mats = true, consumables = true, none = true }
local MODE_ORDER = { "limited", "all", "mats", "consumables", "none" }
local MODE_SAID = {
	all = L["your gold, and everything on all your characters and in your banks"],
	limited = L["this character's crafting mats and consumables, in its bags and bank"],
	mats = L["this character's crafting mats, in its bags and bank"],
	consumables = L["this character's consumables, in its bags and bank"],
	none = L["nothing"],
}
SSH.MODES = MODES

-- (a group can't be named as a word .share takes)
local RESERVED = { password = true, pass = true, pw = true, join = true, leave = true, off = true, connect = true, rename = true,
	debug = true, status = true, share = true, invite = true, accept = true, decline = true, code = true, newcode = true,
	kick = true, new = true, create = true }
for m in pairs(MODES) do RESERVED[m] = true end
SSH.RESERVED = RESERVED

local function Saved()
	if type(_G.TerminalShareDB) ~= "table" then _G.TerminalShareDB = {} end
	local db = _G.TerminalShareDB
	if type(db.groups) ~= "table" then db.groups = {} end
	-- (anything else in it, a hand edit or another version's: dropped, not an error at login)
	for k, v in pairs(db.groups) do
		if type(k) ~= "string" or type(v) ~= "table" then db.groups[k] = nil end
	end
	-- (0.58.6-0.58.16 remembered one key: the default group's now)
	if type(db.key) == "string" then
		db.groups[SSH.DEFAULT_GROUP] = db.groups[SSH.DEFAULT_GROUP] or { key = db.key }
		db.key = nil
	end
	return db
end
SSH.Saved = Saved

--- What you share, set: in one group, or (no group) in every group and those joined later. Friends whose share
--- changed are sent it now; it's remembered.
function SSH.SetMode(ep, m, group)
	if not MODES[m] then
		return { L["Share: what to share: .share limited (the default), .share all, .share mats, .share consumables or .share none"] }
	end
	if group and not ep.groups[group] then return { L["Share: you're not in %s"]:format(group) } end
	ep:SetMode(m, group)
	local db = Saved()
	if group then
		if db.groups[group] then db.groups[group].mode = m end
		return { L["Share: sharing %s in %s"]:format(MODE_SAID[m], group) }
	end
	db.mode = m
	for _, g in pairs(db.groups) do g.mode = m end
	return { L["Share: sharing %s"]:format(MODE_SAID[m]) }
end

--- Who isn't connected yet, said a line each: connecting, no answer, code doesn't match, wants to connect.
function SSH.Others(ep)
	local other = {}
	for _, p in pairs(ep.peers) do
		if p.claim and ep.friends[p.claim] then
			-- (a friend connected another way: said once, above)
		elseif p.state == "mismatch" then other[#other + 1] = L["%s: code doesn't match"]:format(p.name or "?")
		elseif p.state == "noanswer" then other[#other + 1] = L["%s: no answer"]:format(p.name or p.route.target or p.route.name or "?")
		elseif p.state ~= "up" then other[#other + 1] = L["%s: connecting"]:format(p.name or p.route.target or p.route.name or "?") end
	end
	for _, w in pairs(ep.waiting) do
		other[#other + 1] = L["%s wants to connect: no group in common (.share invite %s, or ask them for an invite)"]:format(w.name, w.name)
	end
	sort(other)
	return other
end

function SSH.Status(ep)
	ep = ep or SSH.game
	local lines = {}
	if not ep then return { L["Share: not available"] } end
	if not ep:On() then
		lines[1] = L["Share: not sharing yet. .share invite <name> starts a group and invites a friend who's online, or .share join <group> <code> with a code a friend gave you"]
	else
		lines[1] = L["Share: your groups (remembered: .share leave <group> or .share off forgets them)"]
		local names = {}
		for n in pairs(ep.groups) do names[#names + 1] = n end
		sort(names)
		for _, n in ipairs(names) do
			lines[#lines + 1] = "  " .. L["%s: sharing %s"]:format(n, MODE_SAID[ep.groups[n].mode] or ep.groups[n].mode)
		end
	end
	local up = ep:Connected()
	if #up > 0 then
		local parts = {}
		for i, c in ipairs(up) do
			local f = c.friend or {}
			local m, gs = f.mode, Names(f.groups)
			if gs == "" then
				parts[i] = m and L["%s (items: %d, sharing: %s)"]:format(c.name, c.n, m) or L["%s (items: %d)"]:format(c.name, c.n)
			else
				parts[i] = m and L["%s (items: %d, sharing: %s, in %s)"]:format(c.name, c.n, m, gs)
					or L["%s (items: %d, in %s)"]:format(c.name, c.n, gs)
			end
		end
		lines[#lines + 1] = "  " .. L["Connected:"] .. " " .. concat(parts, ", ")
	elseif ep:On() then
		lines[#lines + 1] = "  " .. L["Connected: nobody yet"]
	end
	for _, s in ipairs(SSH.Others(ep)) do lines[#lines + 1] = "  " .. s end
	for _, s in ipairs(SSH.InviteLines(ep)) do lines[#lines + 1] = "  " .. s end
	return lines
end

--- Invites waiting, either way, a line each.
function SSH.InviteLines(ep)
	local out = {}
	for _, i in ipairs(ep:Invites()) do
		local mins = math.max(1, math.ceil(i.left / 60))
		if i.mine then out[#out + 1] = L["You invited %s to %s: waiting for their yes (%d min left)"]:format(i.name, i.group, mins)
		elseif i.accepted then out[#out + 1] = L["%s's invite to %s: you said yes, the code is on its way"]:format(i.name, i.group)
		else out[#out + 1] = L["%s invites you to %s: .share accept %s (%d min left)"]:format(i.name, i.group, i.name, mins) end
	end
	return out
end

--- `.ssh debug`: what was sent and heard, each way and each friend (to find why items don't arrive).
function SSH.Debug(ep)
	ep = ep or SSH.game
	local lines = {}
	local function counts(t)
		local out = {}
		for k, n in pairs(t or {}) do out[#out + 1] = k .. "=" .. n end
		sort(out)
		return #out > 0 and concat(out, " ") or "-"
	end
	local now = ep:Now()
	local gs = {}
	local mine = ep:MarksOf(ep:Claim(), ep:Session())
	for m, n in pairs(mine) do gs[#gs + 1] = n .. "=" .. ep.groups[n].mode .. "/" .. m end
	sort(gs)
	lines[1] = ("ssh debug: groups %s, queue %d, sent (game's answers) %s, heard %s"):format(#gs > 0 and concat(gs, " ") or "none",
		#ep.queue, counts(ep.results), counts(ep.heard))
	-- (0.60.2: which Battle.net characters are on your realm, and which were left out for another)
	local P = SSH.People and SSH.People()
	if P then
		local on = {}
		for _, b in pairs(P.bn or {}) do on[#on + 1] = b.name .. " (" .. tostring(b.realm or "?") .. ")" end
		sort(on)
		lines[#lines + 1] = ("  your realm: %s; Battle.net characters on it: %s; left out (another realm): %s"):format(
			tostring(P.realm), #on > 0 and concat(on, ", ") or "none", #(P.skipped or {}) > 0 and concat(P.skipped, ", ") or "none")
	end
	local keys = {}
	for k in pairs(ep.peers) do keys[#keys + 1] = k end
	sort(keys)
	for _, k in ipairs(keys) do
		local p = ep.peers[k]
		lines[#lines + 1] = ("  way %s: %s %s%s%s"):format(k, tostring(p.state), tostring(p.claim or "?"),
			p.groups and (" [" .. Names(p.groups) .. "]") or "", p.got and p.got > 0 and (" (pieces %d)"):format(p.got) or "")
	end
	for _, c in ipairs(ep:Connected()) do
		local f = c.friend
		local text = f.sentText or ""
		lines[#lines + 1] = ("  friend %s (%s; groups %s): items %d%s, heard %ds ago, last data %s; sent to them by %s: %d characters (%s)"):format(
			c.name, tostring(f.mode or "?"), Names(f.groups), c.n, f.gold and (", gold " .. f.gold) or "", floor(now - (f.last or now)),
			f.gotAt and (floor(now - f.gotAt) .. "s ago") or "never", tostring(f.key), #text, tostring(f.sentMode))
	end
	local mine = ep:Snapshot(nil, true)
	lines[#lines + 1] = ("  you share (all your groups together): %d characters: %s"):format(#mine, mine:sub(1, 120))
	return lines
end

-- The groups remembered (0.58.6, the player: "saved and re-used automatically on login"): each group's code, its key
-- and what you share in it, in Terminal: Share's own saved variables (TerminalShareDB.groups[name] = { key = hex, mode,
-- kdf = "code1", code }). At login they're used a few seconds in (friends and guild read first) and everyone is said
-- hello to once. .share leave <group> forgets one; .share off, all.
-- (Anyone with your WTF folder could connect as you with them: the same as having the codes, for this.)
SSH.LOGIN_WAIT = 5

--- A group's key remembered (nil: forgotten), with what you share in it.
function SSH.Remember(group, key, mode, code)
	local db = Saved()
	-- (a group's code, when it has one, kept with its key: .share code shows it again, an invite sends it)
	if key then db.groups[group] = { key = C.Hex(key), mode = mode, kdf = SSH.CODE_ID, code = code }
	else db.groups[group] = nil end
end
--- Every group forgotten (.share off).
function SSH.ForgetGroups() Saved().groups = {} end

local function Unhex(h) return (h:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end)) end

--- The groups remembered: { name = { key (raw), mode } } of those that read.
local function Remembered()
	local out, n, stale = {}, 0, {}
	local names = {}
	for name in pairs(Saved().groups) do names[#names + 1] = name end
	sort(names)
	for _, name in ipairs(names) do
		local g = Saved().groups[name]
		local hex = type(g) == "table" and g.key
		if SSH.GroupName(name) == name and type(hex) == "string" and #hex == 64 and hex:find("^%x+$") and n < SSH.MAX_GROUPS then
			-- (a key made from a typed password, 0.69 and before, or one older still: not used. Codes only)
			local code = g.kdf == SSH.CODE_ID and SSH.ReadCode(g.code) or nil
			if not code then stale[#stale + 1] = name
			else out[name], n = { key = Unhex(hex), mode = MODES[g.mode] and g.mode or nil, code = code }, n + 1 end
		end
	end
	return out, n, stale
end

--- The remembered groups, back in use (at login): true when there was one.
function SSH.Restore(ep)
	ep = ep or SSH.game
	local _, n, stale = Remembered()
	if #stale > 0 then
		-- (a typed password's group: forgotten, said once, with the way to make it again)
		for _, name in ipairs(stale) do Saved().groups[name] = nil end
		ep.env.say(L["Share: typed passwords are gone (anyone in your guild could guess one at home), and with them %s. Make a group again with a code nobody can guess: .share invite <name> [group]"]:format(concat(stale, ", ")))
	end
	if n == 0 then return false end
	-- (the ticker kept going while the groups wait to be joined, and started again once they are. 0.60.0 review: it
	-- stopped a second in, nobody in a group yet, and nothing started it again: no pings, retries or snapshots owed
	-- for the whole session, and friends dropped you after 30 minutes)
	ep.restoring = true
	SSH.StartTicker()
	local ask = C_GuildInfo and C_GuildInfo.GuildRoster or _G.GuildRoster
	if ask then Safe(ask) end
	C_Timer.After(SSH.LOGIN_WAIT, function()
		ep.restoring = nil
		local joined, n = 0, 0
		for _ in pairs(ep.groups) do n = n + 1 end
		for name, g in pairs(Remembered()) do
			-- (a group joined meanwhile, or forgotten: as it is now; five at most with those joined meanwhile)
			if not ep.groups[name] and n < SSH.MAX_GROUPS then
				n = n + 1
				ep:JoinGroup(name, g.key, g.mode or ep.defaultMode, true).code = g.code
				joined = joined + 1
			end
		end
		if joined == 0 then return end
		SSH.StartTicker()
		ep:Hello()
		SSH.Badge()
		ep.env.say(L["Share: back in your groups; saying hello to your friends and guild"])
	end)
	return true
end


----------------------------------------------------------------------
-- Invites and codes at the prompt (0.69.5)
----------------------------------------------------------------------

--- The group a command means when it names none: the only one you're in; else nil and your groups' names.
local function OnlyGroup(ep)
	local names = {}
	for n in pairs(ep.groups) do names[#names + 1] = n end
	sort(names)
	if #names == 1 then return names[1], names end
	return nil, names
end

--- A group made with a code Terminal made (.share new, or an invite to a group you don't have yet): the group, or nil
--- and why.
function SSH.NewGroup(ep, name)
	local n = 0
	for _ in pairs(ep.groups) do n = n + 1 end
	if n >= SSH.MAX_GROUPS then return nil, L["Share: %d groups at most; .share leave one first"]:format(SSH.MAX_GROUPS) end
	local code = SSH.MakeCode()
	local key = SSH.KeyOfCode(code)
	local db = Saved()
	local mode = MODES[db.mode] and db.mode or ep.defaultMode
	ep:JoinGroup(name, key, mode, true).code = code
	SSH.Remember(name, key, mode, code)
	SSH.StartTicker()
	SSH.Badge()
	return ep.groups[name]
end

--- `.share join <group> <code>`: a code a friend gave you (typed, or pasted from the copy box).
function SSH.JoinWithCode(ep, group, code)
	local n = 0
	for _ in pairs(ep.groups) do n = n + 1 end
	if not ep.groups[group] and n >= SSH.MAX_GROUPS then return { L["Share: %d groups at most; .share leave one first"]:format(SSH.MAX_GROUPS) } end
	local key = SSH.KeyOfCode(code)
	local saved = Saved().groups[group]
	local mode = type(saved) == "table" and MODES[saved.mode] and saved.mode or ep.defaultMode
	ep:JoinGroup(group, key, mode).code = code
	SSH.Remember(group, key, mode, code)
	SSH.StartTicker()
	SSH.Badge()
	return { L["Share: joined %s with its code; saying hello to your friends and guild"]:format(group) }
end

--- `.share invite <name> [group]`. `list`: who you can invite (SSH.Invitable's; the tests give their own).
function SSH.InviteCmd(ep, rest, list)
	if rest == "" then
		return { L["Share: who? .share invite <name>: a friend, guild member or Battle.net friend who's online (Tab lists them)"] }
	end
	list = list or SSH.Invitable()
	local person, could = SSH.FindPerson(rest, list)
	local group
	if not person then
		local who, last = rest:match("^(.-)%s+(%S+)$")
		if who then
			local p2, c2 = SSH.FindPerson(who, list)
			if p2 then
				person, group = p2, SSH.GroupName(last)
				if not group or RESERVED[group] then
					return { L["Share: a group's name is one word of letters and digits, %d at most, and not one .share takes"]:format(SSH.GROUP_LEN) }
				end
			elseif #c2 > #could then could = c2 end
		end
	end
	if not person then
		if #could > 1 then
			local names = {}
			for i, p in ipairs(could) do names[i] = p.name end
			return { L["Share: which one? %s"]:format(concat(names, ", ")) }
		end
		return { L["Share: %s isn't online, or isn't a friend, guild member or Battle.net friend's character"]:format(rest) }
	end
	local lines = {}
	if not group then
		local only, names = OnlyGroup(ep)
		if only then group = only
		elseif #names == 0 then group = SSH.DEFAULT_GROUP
		else
			return { L["Share: invite %s to which group? .share invite %s <group> (yours: %s)"]:format(person.name, person.name, concat(names, ", ")) }
		end
	end
	for _, c in ipairs(ep:Connected()) do
		if Canon(c.name) == Canon(person.name) and c.friend.groups and c.friend.groups[group] then
			return { L["Share: %s is in %s with you already"]:format(person.name, group) }
		end
	end
	if not ep.groups[group] then
		local g, why = SSH.NewGroup(ep, group)
		if not g then return { why } end
		lines[#lines + 1] = L["Share: made the group %s, with a code Terminal made that nobody can guess"]:format(group)
	end
	ep:Invite(person.route, person.name, group)
	lines[#lines + 1] = L["Share: invited %s to %s. Once they type .share accept, you're connected (the invite waits 10 minutes)"]:format(person.name, group)
	local mode = ep.groups[group].mode
	lines[#lines + 1] = L["Share: you share %s in %s; .share %s all (or limited, mats, consumables, none) changes it"]:format(MODE_SAID[mode] or mode, group, group)
	SSH.StartTicker()
	SSH.Badge()
	return lines
end

--- `.share accept [name]` / `.share decline [name]` (`no`).
function SSH.AnswerCmd(ep, rest, no)
	local o, k = ep:Offer(rest)
	if not o then
		local names = {}
		for _, i in ipairs(ep:Invites()) do if not i.mine then names[#names + 1] = i.name end end
		if #names == 0 then return { L["Share: no invite is waiting for you"] } end
		return { (no and L["Share: whose invite? .share decline <name> (%s)"] or L["Share: whose invite? .share accept <name> (%s)"]):format(concat(names, ", ")) }
	end
	if no then
		ep:Decline(o, k)
		SSH.Badge()
		return { L["Share: told %s no thanks"]:format(o.name) }
	end
	if o.accepted then return { L["Share: you said yes to %s already; the code is on its way"]:format(o.name) } end
	ep:Accept(o)
	SSH.StartTicker()
	local db = Saved()
	local mode = MODES[db.mode] and db.mode or ep.defaultMode
	return { L["Share: yes to %s's invite to %s; joining in a moment"]:format(o.name, o.group),
		L["Share: you'll share %s there; .share %s all (or limited, mats, consumables, none) changes it"]:format(MODE_SAID[mode] or mode, o.group) }
end

--- The group a command names (`rest`), or the only one you're in: the group's name, or nil and a line saying why.
local function GroupArg(ep, rest, usage)
	local group = rest ~= "" and SSH.GroupName(rest) or nil
	if rest == "" then
		local only, names = OnlyGroup(ep)
		if only then return only end
		if #names == 0 then return nil, L["Share: you're not in a group yet; .share invite <name> starts one"] end
		return nil, usage:format(concat(names, ", "))
	end
	if not (group and ep.groups[group]) then return nil, L["Share: you're not in %s"]:format(rest) end
	return group
end

--- `.share code [group]`: the group's code in the copy box.
function SSH.CodeCmd(ep, rest)
	local group, why = GroupArg(ep, rest, L["Share: which group's code? .share code <group> (yours: %s)"])
	if not group then return { why } end
	local g = ep.groups[group]
	if ns.ShowText then ns:ShowText(L["Share: %s's code"]:format(group), g.code, { compact = true }) end
	return { L["Share: %s's code is in the box to copy (Ctrl+C). Anyone with it can join %s and see what's shared there: give it only to friends, by whisper or outside the game. They type .share join %s <code>"]:format(group, group, group) }
end

--- `.share new <group>`: a group of your own, with a code Terminal makes.
function SSH.NewCmd(ep, rest)
	local group = SSH.GroupName(rest)
	if not group or RESERVED[group] then
		return { L["Share: a group's name is one word of letters and digits, %d at most, and not one .share takes"]:format(SSH.GROUP_LEN) }
	end
	if ep.groups[group] then return { L["Share: you're in %s already; .share invite <name> %s invites a friend to it"]:format(group, group) } end
	local g, why = SSH.NewGroup(ep, group)
	if not g then return { why } end
	return { L["Share: made %s, with a code nobody can guess. Invite friends: .share invite <name> %s"]:format(group, group) }
end

--- `.share rename <group> <new name>`: what you call a group (yours alone: a friend's name for it stays theirs).
function SSH.RenameCmd(ep, rest)
	local old, new = rest:match("^(%S+)%s+(%S+)$")
	if not old then return { L["Share: .share rename <group> <new name>"] } end
	local from, to = SSH.GroupName(old), SSH.GroupName(new)
	if not (from and ep.groups[from]) then return { L["Share: you're not in %s"]:format(old) } end
	if not to or RESERVED[to] then
		return { L["Share: a group's name is one word of letters and digits, %d at most, and not one .share takes"]:format(SSH.GROUP_LEN) }
	end
	if to == from then return { L["Share: %s is called that already"]:format(from) } end
	if ep.groups[to] then return { L["Share: you have a group called %s already"]:format(to) } end
	ep:Rename(from, to)
	local db = Saved()
	db.groups[to], db.groups[from] = db.groups[from], nil
	SSH.Badge()
	return { L["Share: %s is now %s (only for you: friends in it keep their own name for it)"]:format(from, to) }
end

--- An invite came in or went: the badge woken, the prompt's suggestion made again.
function SSH.Offered()
	SSH.StartTicker() -- (an invite to you with no group yet: it runs out on time, and the badge with it)
	SSH.Badge(true)
	local Easy = ns.Easy
	if Easy and Easy.ResetPool then Easy.ResetPool() end
end

-- (an invite waiting for your yes: the empty prompt suggests it first, Shift+Right types it)
if ns.Easy then
	ns.Easy.FIRST = ns.Easy.FIRST or {}
	table.insert(ns.Easy.FIRST, function()
		local ep = SSH.game
		if not ep then return nil end
		for _, i in ipairs(ep:Invites()) do
			if not i.mine and not i.accepted then return "try: .share accept " .. i.name end
		end
	end)
end

-- (.share, 0.58.14, the player: ".ssh ... a fun throwback to secure shell but its probably confusing for WoW players":
-- .ssh is its alias)
ns:RegisterCommand("share", {
	aliases = { "ssh" },
	desc = L["The share shell: your bags in the searches of friends who run Terminal: Share. .share invite <name> starts a group and invites a friend (.share accept to say yes to one); .share join <group> <code> with a code a friend gave you; what you share: .share limited, all, mats, consumables or none (.share <group> all: in one group); .share leave <group>; .share off"],
	complete = function(rest)
		local ep = SSH.game
		local word = Lower(tostring(rest or ""):match("^%s*(%S+)%s") or "")
		-- (a word that takes a name or a group, typed with its space: who or which, as rows)
		if word == "invite" then
			local out = {}
			for _, p in ipairs(SSH.Invitable()) do out[#out + 1] = { "invite " .. p.name, L["online: %s"]:format(p.how) } end
			if #out == 0 then out[1] = { "invite", L["nobody to invite online now: friends, guild members and Battle.net friends who are"] } end
			return out
		elseif word == "accept" or word == "decline" then
			local out = {}
			for _, i in ipairs(ep and ep:Invites() or {}) do
				if not i.mine then out[#out + 1] = { word .. " " .. i.name, L["%s invites you to %s"]:format(i.name, i.group) } end
			end
			return out
		elseif word == "code" or word == "leave" or word == "rename" then
			local out = {}
			local names = {}
			for n in pairs(ep and ep.groups or {}) do names[#names + 1] = n end
			sort(names)
			for _, n in ipairs(names) do out[#out + 1] = { word .. " " .. n, L["sharing %s"]:format(MODE_SAID[ep.groups[n].mode] or ep.groups[n].mode) } end
			return out
		end
		local out = {}
		-- (an invite waiting for you: its yes first)
		for _, i in ipairs(ep and ep:Invites() or {}) do
			if not i.mine and not i.accepted then out[#out + 1] = { "accept " .. i.name, L["%s invites you to %s"]:format(i.name, i.group) } end
		end
		out[#out + 1] = { "invite", L["invite a friend to share: .share invite <name> [group] (Terminal makes the group a code nobody can guess)"] }
		out[#out + 1] = { "join", L["join a group with a code a friend gave you: .share join <group> <code>"] }
		if ep and ep:On() then
			out[#out + 1] = { "code", L["a group's code, to copy and give a friend: .share code [group]"] }
		end
		out[#out + 1] = { "new", L["make a group with a code: .share new <group>"] }
		if ep and ep:On() then out[#out + 1] = { "rename", L["call a group something else (only for you): .share rename <group> <new name>"] } end
		out[#out + 1] = { "connect", L["say hello to one friend again: .share connect <name>"] }
		for _, m in ipairs(MODE_ORDER) do out[#out + 1] = { m, L["share %s"]:format(MODE_SAID[m]) } end
		local names = {}
		for n in pairs(ep and ep.groups or {}) do names[#names + 1] = n end
		sort(names)
		for _, n in ipairs(names) do
			out[#out + 1] = { n, L["what you share in %s: .share %s all, limited, mats, consumables or none"]:format(n, n) }
		end
		if #names > 0 then out[#out + 1] = { "leave", L["leave a group: .share leave <group> (its code forgotten)"] } end
		out[#out + 1] = { "off", L["leave every group, say goodbye, drop what friends sent"] }
		return out
	end,
	run = function(args)
		local ep = SSH.game
		if not ep then return { L["Share: not available"] } end
		local word, rest = tostring(args or ""):match("^%s*(%S*)%s*(.-)%s*$")
		word = Lower(word)
		if word == "" or word == "status" then return SSH.Status(ep) end
		if word == "debug" then return SSH.Debug(ep) end
		if word == "invite" then return SSH.InviteCmd(ep, rest) end
		if word == "accept" or word == "decline" then return SSH.AnswerCmd(ep, rest, word == "decline") end
		if word == "code" then return SSH.CodeCmd(ep, rest) end
		if word == "kick" or word == "newcode" then
			-- (none: a group has no owner, so anyone in it could use one on anyone. Said how to start over instead)
			return { L["Share: a group has no owner, so there's no kick. To leave someone out, start over with the friends you trust: .share new <group>, .share invite each of them to it, then .share leave the old group (they leave it too)"] }
		end
		if word == "new" or word == "create" then return SSH.NewCmd(ep, rest) end
		if word == "rename" then return SSH.RenameCmd(ep, rest) end
		if word == "password" or word == "pass" or word == "pw" then
			-- (0.69 and before: a typed password. Gone; said how instead, the line still never kept: ns.SecretLine)
			return { L["Share: typed passwords are gone (anyone in your guild could guess one at home). .share invite <name> shares with a friend, with a code Terminal makes; .share join <group> <code> joins with a code a friend gave you"] }
		end
		if word == "join" then
			-- (.share join <group> <code>, or .share join <code>: the group then "default", or "default-2" when you have
			-- another default)
			if rest == "" then return { L["Share: .share join <code> with a code a friend gave you (or .share join <group> <code> to name the group)"] } end
			local typed, words = rest:match("^(%S*)%s*(.-)$")
			local code, why = SSH.ReadCode(rest)
			local group
			if code and not SSH.ReadCode(words) then
				group = ep:FreeLabel(SSH.DEFAULT_GROUP, SSH.KeyOfCode(code))
			else
				group = SSH.GroupName(typed)
				if not group or RESERVED[group] then
					return { L["Share: a group's name is one word of letters and digits, %d at most, and not one .share takes"]:format(SSH.GROUP_LEN) }
				end
				code, why = SSH.ReadCode(words)
			end
			if why == "typo" then return { L["Share: that code has a typo (a character wrong, or two swapped); check it with whoever gave it to you"] } end
			if not code then
				return { L["Share: that isn't a code. A code starts TS1- (a friend's: .share code shows it to them), or ask them to .share invite you"] }
			end
			if not group then return { L["Share: %d groups at most; .share leave one first"]:format(SSH.MAX_GROUPS) } end
			SSH.StartTicker()
			-- (the guild's members, read before their answers come: C_GuildInfo.GuildRoster)
			local ask = C_GuildInfo and C_GuildInfo.GuildRoster or _G.GuildRoster
			if ask then Safe(ask) end
			return SSH.JoinWithCode(ep, group, code)
		end
		if word == "leave" then
			local group = SSH.GroupName(rest)
			if not (group and ep.groups[group]) then
				if rest == "" then return { L["Share: which group? .share leave <group>"] } end
				-- (remembered, not joined: still waiting at login, or one past five. 0.60.0 review: it couldn't be left)
				local saved = Saved().groups
				local name = saved[group or ""] and group or (saved[Lower(rest)] and Lower(rest))
				if name then
					SSH.Remember(name, nil)
					SSH.Badge()
					return { L["Share: left %s; its code is forgotten"]:format(name) }
				end
				return { L["Share: you're not in %s"]:format(rest) }
			end
			ep:LeaveGroup(group)
			SSH.Remember(group, nil)
			if #ep.queue == 0 and not ep:On() then SSH.StopTicker() end
			SSH.Badge()
			return { L["Share: left %s; its code is forgotten"]:format(group) }
		end
		if word == "off" then
			ep:Off()
			SSH.ForgetGroups()
			if #ep.queue == 0 then SSH.StopTicker() end -- (else once the goodbyes are gone)
			SSH.Badge()
			return { L["Share: off. Your groups and their codes are forgotten, and your friends' items are gone"] }
		end
		-- (.ssh all, .ssh mats...; .ssh share all too)
		-- (.share limited raid: the mode, then the group, as well as .share raid limited)
		if MODES[word] and rest ~= "" then return SSH.SetMode(ep, word, SSH.GroupName(rest) or rest) end
		if MODES[word] then return SSH.SetMode(ep, word) end
		if word == "share" then return SSH.SetMode(ep, Lower(rest)) end
		-- (.share raid all: what you share in one group)
		if ep.groups[word] then
			if rest == "" then return { L["%s: sharing %s"]:format(word, MODE_SAID[ep.groups[word].mode] or ep.groups[word].mode) } end
			return SSH.SetMode(ep, Lower(rest), word)
		end
		if word == "connect" then
			if not ep:On() then return { L["Share: you're not in a group yet; .share invite <name> starts one"] } end
			if rest == "" then ep:Hello() return { L["Share: saying hello to your friends and guild"] } end
			local route = SSH.RouteFor(rest)
			if not route then return { L["Share: %s isn't on your friend list, in your guild or a Battle.net friend's character"]:format(rest) } end
			ep:Hello(route)
			return { L["Share: saying hello to %s"]:format(rest) }
		end
		return SSH.Status(ep)
	end,
})

----------------------------------------------------------------------
-- The badge at the end of the prompt (0.58.6, the player: "a little wifi icon at the very end of the Terminal prompt
-- box ... who you are connected to and how much they are sharing"): shown while the share shell is on (in a group); the theme's accent with a friend connected, grey with none. Terminal's UI.AddBadge (Prompt.lua).
----------------------------------------------------------------------

-- A wifi sign (0.58.7, the player: "make the wifi icon look a little better"): a dot and three arcs over it, each arc a
-- line of small dots close enough to read as one stroke. The theme's accent with a friend connected, the arcs lit one
-- by one while connecting, grey with nobody.
local ARCS = { 4.5, 8.5, 12.5 }
local function DrawWifi(f)
	f.arcs = {}
	local cx, cy = 0, 5 -- (from the frame's bottom middle: the sign centred in its square, level with the text)
	f.center = f:CreateTexture(nil, "OVERLAY")
	f.center:SetSize(4, 4)
	f.center:SetPoint("CENTER", f, "BOTTOM", cx, cy)
	for k, r in ipairs(ARCS) do
		local arc = {}
		local n = math.ceil(r * math.pi / 2 / 1.1) + 1 -- (a dot every ~1.1 px along the arc)
		for i = 1, n do
			local a = math.pi / 4 + (i - 1) / (n - 1) * math.pi / 2
			local d = f:CreateTexture(nil, "OVERLAY")
			d:SetSize(2.2, 2.2)
			d:SetPoint("CENTER", f, "BOTTOM", cx + math.cos(a) * r, cy + math.sin(a) * r)
			arc[#arc + 1] = d
		end
		f.arcs[k] = arc
	end
end

local function Paint(list, r, g, b, a)
	for _, d in ipairs(list) do d:SetColorTexture(r, g, b, a) end
end

--- A handshake under way: the sign's arcs light in turn.
function SSH.Connecting(ep)
	for _, p in pairs(ep.peers) do
		if (p.state == "hello" or p.state == "challenged" or p.state == "proved") and not (p.claim and ep.friends[p.claim]) then return true end
	end
	return false
end

-- (0.58.15, the player: keep the connecting animation, "but it should just red or something if we haven't connected
-- to anyone") connected: the accent; connecting: its arcs light in turn; nobody, nothing under way: red.
local RED = { 0.9, 0.25, 0.2 }
local function BadgeColour(f)
	local ep = SSH.game
	if not (ep and f.arcs) then return end
	local ar, ag, ab = 0.4, 0.8, 1
	if ns.Theme and ns.Theme.RGB and ns.Theme.Get then ar, ag, ab = ns.Theme.RGB(ns.Theme.Get().accent) end
	local up = #ep:Connected()
	if up == 0 and not SSH.Connecting(ep) then
		f.state = "none"
		f.center:SetColorTexture(RED[1], RED[2], RED[3], 1)
		for _, arc in ipairs(f.arcs) do Paint(arc, RED[1], RED[2], RED[3], 1) end
		return
	end
	local lit = 3
	if up == 0 then lit = 1 + math.floor(GetTime() * 2) % 3 end -- (connecting)
	f.state = up > 0 and "up" or "connecting"
	f.center:SetColorTexture(ar, ag, ab, 1)
	for k, arc in ipairs(f.arcs) do
		if k <= lit then Paint(arc, ar, ag, ab, 1) else Paint(arc, 0.5, 0.5, 0.5, 0.55) end
	end
end
SSH.BadgeColour = BadgeColour

local function Ago(s)
	s = math.max(0, math.floor(s or 0))
	if s < 60 then return L["%ds ago"]:format(s) end
	return L["%dm ago"]:format(math.floor(s / 60))
end

--- The pop-out (0.58.9, the player: "simplify the tooltip a bit"): a line for you, a line a friend ("Cad Mán  39 items
--- · all · Battle.net"), when they were last heard only once it's been a while, then who's still connecting.
function SSH.BadgeTip(t)
	local ep = SSH.game
	local now = ep:Now()
	if not ep:On() then
		t:AddLine(L["Share"], 1, 1, 1)
		for _, line in ipairs(SSH.InviteLines(ep)) do t:AddLine(line, 1, 0.82, 0) end
		return
	end
	local up = ep:Connected()
	local function Items(n) return n == 1 and L["1 item"] or L["%d items"]:format(n) end
	local widest = ep:WidestMode()
	local _, mine = ep:Snapshot(widest)
	local n = mine and #mine.ids or 0
	-- (the groups always, each with what you share in it: "default: limited"; 0.59.0, the player: "put the channel name in
	-- the wifi tooltip, default if it is default". Each friend's groups too once there are several)
	local names = {}
	for g in pairs(ep.groups) do names[#names + 1] = g end
	sort(names)
	local several = #names > 1
	t:AddDoubleLine(L["Sharing"], L["you: %s"]:format(Items(n)), 1, 1, 1, 0.6, 0.6, 0.6)
	if #names > 0 then
		local gs = {}
		for i, g in ipairs(names) do gs[i] = g .. ": " .. ep.groups[g].mode end
		t:AddDoubleLine(several and L["Groups"] or L["Group"], concat(gs, ns.DETAIL_SEP), 0.6, 0.6, 0.6, 0.85, 0.85, 0.85)
	end
	for _, c in ipairs(up) do
		local f = c.friend
		local how = { Items(c.n) }
		if f.mode then how[#how + 1] = f.mode end
		if several then how[#how + 1] = Names(f.groups) end
		if f.gold then how[#how + 1] = ns.Money(f.gold) end
		how[#how + 1] = f.route and f.route.kind == "bn" and "Battle.net" or L["whisper"]
		local quiet = now - (f.last or now)
		if quiet >= 60 then how[#how + 1] = Ago(quiet) end
		t:AddDoubleLine(c.name, concat(how, ns.DETAIL_SEP), 1, 0.82, 0, 0.85, 0.85, 0.85)
	end
	if #up == 0 then t:AddLine(L["Connected: nobody yet"], 0.6, 0.6, 0.6) end
	for _, line in ipairs(SSH.Others(ep)) do t:AddLine(line, 0.55, 0.55, 0.55) end
	for _, line in ipairs(SSH.InviteLines(ep)) do t:AddLine(line, 1, 0.82, 0) end
	t:AddLine(" ")
	t:AddLine(L[".share off to disconnect"], 0.45, 0.45, 0.45)
end

--- The badge placed again (a friend connected or gone, their items in, a group joined or left); `wake`: seen
--- at full strength again (connected, disconnected).
function SSH.Badge(wake)
	local U = ns.UI
	if U and U.PlaceBadges and U.frame then U:PlaceBadges() end
	if wake and U and U.WakeBadge then U.WakeBadge("share") end
end

if ns.UI and ns.UI.AddBadge then
	ns.UI.AddBadge({
		id = "share",
		fade = 6, -- (seconds at full strength, then a faint mark until pointed at; 0.58.9, the player)
		draw = DrawWifi,
		shown = function() local ep = SSH.game return ep ~= nil and (ep:On() or ep:InvitesWaiting()) end,
		refresh = BadgeColour,
		tooltip = function(t) SSH.BadgeTip(t) end,
	})
end

----------------------------------------------------------------------
-- This client: the game's calls
----------------------------------------------------------------------

local function MyRealm()
	local r = Str(Safe(_G.GetNormalizedRealmName)) or Str(Safe(_G.GetRealmName)) or ""
	return Canon((r:gsub("[%s%-']", "")))
end

local function MyForms()
	local me = ns.CharacterName and ns.CharacterName()
	if not me then return {} end
	local c = Canon(me)
	return { [c] = true, [c .. "-" .. MyRealm()] = true }
end

local function Ambig(name)
	if type(_G.Ambiguate) == "function" then
		local s = Str(Safe(_G.Ambiguate, name, "none"))
		if s then return s end
	end
	return name
end

-- friends, guild members and Battle.net friends' characters, read at most every 10 s; after their events (peopleStale)
-- at most every 2 s (0.60.0 review: a big guild's roster events read it all again for the next message, 20 ms each)
local people, peopleAt, peopleStale = nil, -100, nil
local function People()
	local now = GetTime()
	if people and now - peopleAt < (peopleStale and 2 or 10) then return people end
	peopleStale = nil
	local realm = MyRealm()
	local names, bn, guild, guids, bnNames = {}, {}, {}, {}, {}
	local function add(set, name, shown)
		local c = Canon(name)
		if c == "" then return end
		set[c] = shown
		set[c .. "-" .. realm] = shown
	end
	local FL = C_FriendList
	for i = 1, (FL and FL.GetNumFriends and Num(Safe(FL.GetNumFriends)) or 0) do
		local f = Safe(FL.GetFriendInfoByIndex, i)
		local n = type(f) == "table" and Str(f.name)
		if n then
			add(names, n, Ambig(n))
			local guid = Str(f.guid)
			if guid then add(guids, n, guid) end
		end
	end
	for i = 1, (_G.IsInGuild and Safe(_G.IsInGuild) and Num(Safe(_G.GetNumGuildMembers)) or 0) do
		local n, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, g17 = Safe(_G.GetGuildRosterInfo, i)
		n = Str(n)
		if n then
			add(names, n, Ambig(n)); add(guild, n, true)
			-- (the roster's 17th answer: the character's GUID)
			local guid = Str(g17)
			if guid then add(guids, n, guid) end
		end
	end
	local B = C_BattleNet
	local wow = _G.BNET_CLIENT_WOW or "WoW"
	local mine = Str(Safe(_G.UnitGUID, "player"))
	local myServer = mine and mine:match("^Player%-(%d+)%-")
	local skipped = {} -- (.share debug: Battle.net characters left out for another realm)
	for i = 1, (Num(Safe(_G.BNGetNumFriends)) or 0) do
		local a = B and B.GetFriendAccountInfo and Safe(B.GetFriendAccountInfo, i)
		if type(a) == "table" then
			local accounts = {}
			local nGames = B.GetFriendNumGameAccounts and Num(Safe(B.GetFriendNumGameAccounts, i)) or 0
			for j = 1, nGames do accounts[#accounts + 1] = Safe(B.GetFriendGameAccountInfo, i, j) end
			if nGames == 0 then accounts[1] = a.gameAccountInfo end
			for _, g in ipairs(accounts) do
				local id, char = type(g) == "table" and Num(g.gameAccountID), type(g) == "table" and Str(g.characterName)
				-- (0.60.1, the player: "across rulesets (realms) this should not be possible": a Battle.net friend's character
				-- on another realm, Forever's PvE beside your PvP, isn't one to share with, whatever its faction. Its realm by
				-- name; else by the server in its GUID ("Player-4619-..."), as yours; neither given, not taken. 0.60.2:
				-- not by Battle.net's realm id first, the player: "no longer able to connect to my friend on the same
				-- realm" (an id that isn't GetRealmID()'s numbering)
				local realmName = type(g) == "table" and Str(g.realmName)
				local same
				if realmName then same = Canon((realmName:gsub("[%s%-']", ""))) == realm
				else
					local theirs = type(g) == "table" and Str(g.playerGuid)
					theirs = theirs and theirs:match("^Player%-(%d+)%-")
					same = theirs ~= nil and myServer ~= nil and theirs == myServer
				end
				if type(g) == "table" and Str(g.characterName) and g.clientProgram == wow and not same then
					skipped[#skipped + 1] = (Str(g.characterName) or "?") .. " (" .. tostring(realmName or "no realm") .. ")"
				end
				if id and char and same and g.clientProgram == wow and (not g.wowProjectID or not _G.WOW_PROJECT_ID or g.wowProjectID == _G.WOW_PROJECT_ID) then
					bn[id] = { name = char, realm = realmName, bnetID = Num(a.bnetAccountID), guid = Str(g.playerGuid) }
					local full = realmName and (char .. "-" .. realmName:gsub("[%s']", "")) or char
					if not names[Canon(char)] then add(bnNames, char, true) end
					add(names, char, char)
					add(names, full, char)
				end
			end
		end
	end
	people, peopleAt = { names = names, bn = bn, guild = guild, guids = guids, bnNames = bnNames, guildN = Num(Safe(_G.GetNumGuildMembers)) or 0,
		skipped = skipped, realm = realm }, now
	return people
end
SSH.People = People
function SSH.Forget() people = nil end

local function Eligible(route, peer)
	local P = People()
	if route.kind == "bn" then
		local b = P.bn[route.id]
		if not b then return nil end
		route.name, route.bnetID = b.name, b.bnetID
		return b.name
	end
	local sender = Str(route.target)
	if not sender then return nil end
	local c = Canon(sender)
	local mine = MyForms()
	if mine[c] then return nil end -- (your own guild message, heard back)
	if route.kind == "guild" then return Ambig(sender) end -- (the guild channel: only members are on it)
	local realm = MyRealm()
	local shown = P.names[c] or P.names[c .. "-" .. realm]
	if shown then return shown end
	-- (heard first on the guild channel, before the roster was read: still one of them while the roster says nothing)
	if peer and peer.viaGuild and P.guildN == 0 then return peer.name or Ambig(sender) end
	return nil
end

-- A name claimed over Battle.net, with a surname Battle.net didn't give, kept by the Battle.net account first proven
-- with it (0.59.1, the player: "resolve this B.net loose name issue"): { [claim] = bnetAccountID }, this session.
local bnOwner = {}
SSH.bnOwner = bnOwner

local function Matches(claim, route)
	if route.kind == "bn" then
		local P = People()
		local b = P.bn[route.id]
		if not b then return false end
		local name, realm = claim:match("^(.-)@(.*)$")
		local c = Canon(b.name)
		-- (Battle.net may give the first name alone: the claim's surname after it)
		local exact = name == c
		if not (exact or name:sub(1, #c + 1) == c .. "-") then return false end
		-- (0.59.3: Battle.net gave the surname itself, "Girl Bird", as the player's game shows: that name and no other)
		if not exact and c:find("-", 1, true) then return false end
		if b.realm and SSH.Claim("x", b.realm) ~= "x@" .. realm then return false end
		-- (no realm from Battle.net: only a character of your own realm. 0.60.0 review: any realm's taken)
		if not b.realm and realm ~= "" and realm ~= MyRealm() then return false end
		-- (0.59.1) The character claimed, as your friend list or guild roster knows it: by its GUID, it's this Battle.net
		-- friend's character or not. One the game knows only by its name (a friend list or roster without GUIDs, or a
		-- Battle.net friend whose GUID isn't given): a surname claimed over Battle.net isn't taken for it; they connect
		-- the way they're known by instead.
		local key = (realm == MyRealm() or realm == "") and name or (name .. "-" .. realm)
		local withRealm = name .. "-" .. (realm ~= "" and realm or MyRealm()) -- (the roster writes "Name-Realm")
		local knownGuid = P.guids[key] or P.guids[withRealm]
		if knownGuid and b.guid then return knownGuid == b.guid end
		if not exact then
			if (P.names[key] and not P.bnNames[key]) or (P.names[withRealm] and not P.bnNames[withRealm]) then return false end
			-- (a surname no one else is known by: the Battle.net account that first proved it keeps it)
			local owner = bnOwner[claim]
			if owner and b.bnetID and owner ~= b.bnetID then return false end
		end
		return true
	end
	return SSH.ClaimIs(claim, route.target, MyRealm())
end

local function Send(route, text)
	local CI = C_ChatInfo
	local ok, res
	if route.kind ~= "bn" and not (CI and CI.SendAddonMessage) then return -1 end
	if route.kind == "bn" then
		local f = (C_BattleNet and C_BattleNet.SendGameData) or _G.BNSendGameData
		if not f then return -1 end
		ok, res = pcall(f, route.id, SSH.PREFIX, text)
	elseif route.kind == "guild" then
		ok, res = pcall(CI.SendAddonMessage, SSH.PREFIX, text, "GUILD")
	else
		ok, res = pcall(CI.SendAddonMessage, SSH.PREFIX, text, "WHISPER", route.target)
	end
	if not ok then return -1 end
	if res == nil or res == true then return SENT end
	if res == false then return -1 end
	return Num(res) or -1
end

local function ClassOf(id)
	local f = C_Item and C_Item.GetItemInfoInstant
	if not f then return nil end
	return Num((select(6, Safe(f, id))))
end

--- Consumables: food, potions, elixirs, flasks, bandages, scrolls (the game's Consumable item class), as @consumable.
local function Consumable(id)
	return ClassOf(id) == ((_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Consumable) or 0)
end
SSH.Consumable = Consumable

--- Crafting mats: trade goods, reagents, and anything the game calls a crafting reagent, as @mats.
local function Mat(id)
	local IC = _G.Enum and _G.Enum.ItemClass
	local c = ClassOf(id)
	if c == ((IC and IC.Tradegoods) or 7) or c == ((IC and IC.Reagent) or 5) then return true end
	local f = C_Item and C_Item.GetItemInfo
	if not f then return false end
	local ok, r = pcall(function() return select(17, f(id)) end)
	return ok and r == true
end
SSH.Mat = Mat

-- each mode's items from this character's bags (all: every one)
local WANT = {
	limited = function(id) return Consumable(id) or Mat(id) end,
	mats = Mat,
	consumables = Consumable,
}

--- What your bags hold now: { [itemID] = count }.
local function BagItems()
	local out = {}
	local CC = C_Container
	if not (CC and CC.GetContainerNumSlots) then return out end
	local last = (_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or _G.NUM_BAG_SLOTS or 4) + 1
	for bag = 0, last do
		for slot = 1, (Num(Safe(CC.GetContainerNumSlots, bag)) or 0) do
			local info = Safe(CC.GetContainerItemInfo, bag, slot)
			local id = type(info) == "table" and Num(info.itemID)
			if id then out[id] = (out[id] or 0) + (Num(info.stackCount) or 1) end
		end
	end
	return out
end
SSH.BagItems = BagItems

-- where @stored keeps things, as a snapshot says it (worn gear, auctions and guild banks aren't shared)
local WHERE_CODE = { bags = "b", bank = "k", mail = "m", void = "v", warband = "w" }

--- Your gold: every character's (and the warband bank's), as @gold totals it; else this character's.
local function AllGold()
	local p = ns.providers.gold
	local mine
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		if e.goldKind == "total" then return Num(e.money) end
		if e.goldKind == "me" then mine = Num(e.money) end
	end
	return mine or Num(Safe(_G.GetMoney))
end

--- What you share in a mode, as a snapshot (SSH.Encode's shape). limited, mats, consumables: this character's bags;
--- all: everything there, your other characters and banks as @stored reads them (Syndicator or BagBrother), and gold.
-- @stored as it last read it: a change to it is read in its own time (warmDirty: out of combat, after the last change),
-- not here inside a bag event or Syndicator's callback (0.60.0 review: 30 reads of it selling 30 greys, up to 450 ms
-- each with many alts). Read here only the first time. SSH.StoredMoved: once it has read it again, shared again.
local function StoredList()
	local p = ns.providers.stored
	if not p then return {} end
	local list = (p._dirty and p._entries) or ns:GetEntries(p)
	SSH.storedSeen = list
	return list
end

--- @stored read again since what you share was made: made again (each second, from the ticker).
function SSH.StoredMoved(ep)
	local st = ns.providers.stored
	if st and SSH.storedSeen and st._entries and st._entries ~= SSH.storedSeen and ep:On() then
		SSH.storedSeen = st._entries
		ep:Changed()
		return true
	end
	return false
end

function SSH.Snapshot(mode)
	local me = ns.CharacterName and ns.CharacterName() or "?"
	local places, index, items = {}, {}, {}
	local function place(who, where)
		local k = who .. "/" .. where
		if not index[k] then
			places[#places + 1] = { who = who, where = where }
			index[k] = #places
		end
		return index[k]
	end
	local function add(id, pi, n)
		local t = items[id]
		if not t then t = {}; items[id] = t end
		t[pi] = (t[pi] or 0) + n
	end
	local want = WANT[mode]
	local bags = place(me, "b")
	for id, n in pairs(BagItems()) do
		if mode == "all" or (want and want(id)) then add(id, bags, n) end
	end
	local gold
	if mode == "all" then
		for _, e in ipairs(StoredList()) do
			local id = e.itemID
			for _, h in pairs(type(e.holders) == "table" and e.holders or {}) do
				local w = WHERE_CODE[h.where]
				-- (what you carry is read live above)
				if id and w and (h.count or 0) > 0 and not (h.mine and h.where == "bags") then
					add(id, place(w == "w" and "" or (h.mine and me or tostring(h.who)), w), h.count)
				end
			end
		end
		gold = AllGold()
	elseif want then
		-- (0.59.0, the player: "also share the character bank inventory of the same types of items": this character's
		-- bank as @stored has it, Syndicator or BagBrother)
		for _, e in ipairs(StoredList()) do
			local id = e.itemID
			for _, h in pairs(id and type(e.holders) == "table" and e.holders or {}) do
				if h.mine and h.where == "bank" and (h.count or 0) > 0 and want(id) then add(id, place(me, "k"), h.count) end
			end
		end
	end
	return { places = places, items = items, gold = gold }
end

local nonceN = 0
local function Nonce()
	nonceN = nonceN + 1
	local t = (type(_G.debugprofilestop) == "function" and _G.debugprofilestop()) or GetTime()
	return C.Hex(C.SHA256(tostring(t) .. "|" .. nonceN .. "|" .. math.random() .. "|" .. tostring((type(time) == "function" and time()) or 0)
		.. "|" .. tostring(SSH.claimNow or ""))):sub(1, 16)
end
SSH.Nonce = Nonce

--- Where a hello goes: the guild channel, each friend on your list who's online and not in your guild, each Battle.net
--- friend playing World of Warcraft who's on neither.
local function Broadcast()
	local out, done = {}, {}
	local P = People()
	if _G.IsInGuild and Safe(_G.IsInGuild) then
		out[#out + 1] = { kind = "guild" }
		for c in pairs(P.guild) do done[c] = true end
	end
	local FL = C_FriendList
	for i = 1, (FL and FL.GetNumFriends and Num(Safe(FL.GetNumFriends)) or 0) do
		local f = Safe(FL.GetFriendInfoByIndex, i)
		local n = type(f) == "table" and f.connected and Str(f.name)
		-- (a friend on your realm is "bob" here, "bob-realm" on the roster: review, 0.58.16, said hello twice)
		if n and not done[Canon(n)] and not done[Canon(n) .. "-" .. MyRealm()] then
			done[Canon(n)] = true
			out[#out + 1] = { kind = "whisper", target = n }
		end
	end
	for id, b in pairs(P.bn) do
		local c = Canon(b.name)
		if not done[c] and not done[c .. "-" .. MyRealm()] then
			out[#out + 1] = { kind = "bn", id = id, name = b.name, bnetID = b.bnetID }
		end
	end
	return out
end

--- `.ssh connect Bob`: the way to reach a friend by name, or nil when they're none of the three.
function SSH.RouteFor(name)
	local P = People()
	local c = Canon(ns.Share and ns.Share.WhisperTarget and ns.Share.WhisperTarget(name) or name)
	for id, b in pairs(P.bn) do
		if Canon(b.name) == c then return { kind = "bn", id = id, name = b.name, bnetID = b.bnetID } end
	end
	if P.names[c] or P.names[c .. "-" .. MyRealm()] then
		local target = ns.Share and ns.Share.WhisperTarget and ns.Share.WhisperTarget(name) or name
		return { kind = "whisper", target = target }
	end
	return nil
end

-- Randomness for codes (0.69.5): a code is only as good as what it's made from, so it isn't made from
-- math.random alone. A pool, mixed with SHA-256, of what nobody can predict: the time each frame starts, to a fraction
-- of a microsecond, for the first ENTROPY_FRAMES frames after login and a while after each code; the cursor, the
-- clock, memory in use and math.random each time it's mixed; the moment the code is asked for.
SSH.ENTROPY_FRAMES = 600 -- (about 10 s)
local entropy = { pool = "Terminal.ssh.entropy", samples = {}, n = 0, made = 0 }
local function Mix(extra)
	local parts = { entropy.pool, concat(entropy.samples, ","), tostring(math.random()), tostring(GetTime and GetTime() or 0),
		tostring(type(time) == "function" and time() or 0), tostring(collectgarbage and collectgarbage("count") or 0), tostring(extra or "") }
	if GetCursorPosition then
		local x, y = GetCursorPosition()
		parts[#parts + 1] = tostring(x) .. ":" .. tostring(y)
	end
	entropy.pool = C.SHA256(concat(parts, "|"))
	entropy.n = entropy.n + #entropy.samples
	entropy.samples = {}
end
local function Sample()
	local t = type(_G.debugprofilestop) == "function" and _G.debugprofilestop() or 0
	entropy.samples[#entropy.samples + 1] = ("%.4f"):format(t)
	if #entropy.samples >= 32 then Mix() end
end
local sampler
local function Sampling(frames)
	if not CreateFrame then return end
	if not sampler then
		sampler = CreateFrame("Frame")
		sampler.left = 0
		sampler:SetScript("OnUpdate", function(self)
			Sample()
			self.left = self.left - 1
			if self.left <= 0 then self:Hide() end
		end)
	end
	sampler.left = math.max(sampler.left, frames)
	sampler:Show()
end
Sampling(SSH.ENTROPY_FRAMES)
SSH.entropy = entropy -- (tests: how many samples went in)

--- A new code: 120 bits from the pool, mixed with this moment first and again after (the next code shares nothing
--- with this one that could be worked back).
function SSH.MakeCode()
	Sample()
	entropy.made = entropy.made + 1
	Mix("code " .. entropy.made)
	local bytes = C.HMAC(entropy.pool, "code|" .. entropy.made)
	Mix("after " .. entropy.made)
	Sampling(120)
	return SSH.CodeFromBytes(bytes)
end

--- Who you can invite, online now: friends, guild members, Battle.net friends' characters on your realm (not you):
--- { { name, route, how } }, by name.
function SSH.Invitable()
	local out, seen = {}, {}
	local mine = MyForms()
	local function add(name, route, how)
		local c = Canon(name)
		if c == "" or seen[c] or mine[c] then return end
		seen[c] = true
		out[#out + 1] = { name = name, route = route, how = how }
	end
	local FL = C_FriendList
	for i = 1, (FL and FL.GetNumFriends and Num(Safe(FL.GetNumFriends)) or 0) do
		local f = Safe(FL.GetFriendInfoByIndex, i)
		local n = type(f) == "table" and f.connected and Str(f.name)
		if n then add(Ambig(n), { kind = "whisper", target = n }, L["friend"]) end
	end
	for i = 1, (_G.IsInGuild and Safe(_G.IsInGuild) and Num(Safe(_G.GetNumGuildMembers)) or 0) do
		local n, _, _, _, _, _, _, _, online = Safe(_G.GetGuildRosterInfo, i)
		n = Str(n)
		if n and online then add(Ambig(n), { kind = "whisper", target = n }, L["guild"]) end
	end
	for id, b in pairs(People().bn) do add(b.name, { kind = "bn", id = id, name = b.name, bnetID = b.bnetID }, "Battle.net") end
	sort(out, function(a, b) return Lower(a.name) < Lower(b.name) end)
	return out
end

--- Someone in a list ({ name }) by what was typed: their whole name ("Plamen Warr", any capitals, with or without the
--- realm), or the start of it when only one starts so. The person, or nil and those it could be.
function SSH.FindPerson(text, list)
	local c = Canon(text)
	if c == "" then return nil, {} end
	local starts = {}
	for _, p in ipairs(list) do
		local pc = Canon(p.name)
		if pc == c then return p end
		if pc:sub(1, #c) == c then starts[#starts + 1] = p end
	end
	if #starts == 1 then return starts[1] end
	return nil, starts
end

SSH.game = SSH.Endpoint({
	now = function() return GetTime() end,
	claim = function()
		local c = SSH.Claim(ns.CharacterName and ns.CharacterName(), MyRealm())
		SSH.claimNow = c
		return c or "?@"
	end,
	send = Send,
	eligible = Eligible,
	matches = Matches,
	items = SSH.Snapshot,
	locked = function() return ns.ChatLocked and ns.ChatLocked() or false end,
	changed = function() ns:Changed("shared"); SSH.Badge() end,
	say = function(text) ns:Print(text); SSH.Badge(true) end, -- (said: connected, disconnected... the badge with it)
	nonce = Nonce,
	broadcast = Broadcast,
	offered = function() SSH.Offered() end,
	joined = function(name, key, mode, code)
		SSH.Remember(name, key, mode, code)
		SSH.StartTicker()
		SSH.Badge(true)
	end,
	proven = function(claim, route)
		if route.kind == "bn" and route.bnetID and not bnOwner[claim] then bnOwner[claim] = route.bnetID end
	end,
})

local ticker
function SSH.StartTicker()
	if ticker or not (C_Timer and C_Timer.NewTicker) then return end
	ticker = C_Timer.NewTicker(1, function()
		local ep = SSH.game
		ep:Tick()
		SSH.StoredMoved(ep)
		-- (off, and the goodbyes all gone: stopped)
		if not ep:On() and not ep.restoring and #ep.queue == 0 and not ep:InvitesWaiting() then SSH.StopTicker() return end
		local U = ns.UI
		local def = U and U.badges and (function() for _, d in ipairs(U.badges) do if d.id == "share" then return d end end end)()
		if def and def.frame and def.frame:IsShown() then BadgeColour(def.frame) end -- (connecting: the arcs light in turn)
	end)
end
function SSH.StopTicker()
	if ticker then ticker:Cancel(); ticker = nil end
end

--- The game's events, as the endpoint hears them (also the tests' way in).
function SSH.OnEvent(event, ...)
	local ep = SSH.game
	if event == "CHAT_MSG_ADDON" then
		local prefix, text, channel, sender = ...
		if Str(prefix) ~= SSH.PREFIX then return end
		text, channel, sender = Str(text), Str(channel), Str(sender) -- (secret while chat is locked: ignored)
		if not (text and channel and sender) then return end
		local route
		if channel == "WHISPER" then route = { kind = "whisper", target = sender }
		elseif channel == "GUILD" then route = { kind = "guild", target = sender }
		else return end -- (party, raid, channels: never read)
		ep:Receive(route, text)
		local p = ep:Peer(route)
		if p and channel == "GUILD" then p.viaGuild = true end
	elseif event == "BN_CHAT_MSG_ADDON" then
		local prefix, text, _, senderID = ...
		if Str(prefix) ~= SSH.PREFIX then return end
		text, senderID = Str(text), Num(senderID)
		if not (text and senderID) then return end
		ep:Receive({ kind = "bn", id = senderID }, text)
	elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYERBANKSLOTS_CHANGED" or event == "MAIL_INBOX_UPDATE"
		or event == "PLAYER_MONEY" then
		if ep:On() then ep:Changed() end -- (sent only when what you share changed: Share compares the text)
	elseif event == "FRIENDLIST_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "BN_FRIEND_INFO_CHANGED"
		or event == "BN_FRIEND_LIST_SIZE_CHANGED" then
		peopleStale = true
	elseif event == "PLAYER_LOGOUT" then
		ep:Bye()
	elseif event == "PLAYER_LOGIN" then
		-- (what you share: Terminal's setting until 0.58.16, Terminal: Share's own since groups)
		local db = Saved()
		if not MODES[db.mode] and ns.db and MODES[ns.db.sshShare] then db.mode = ns.db.sshShare end
		local def = db.groups[SSH.DEFAULT_GROUP]
		if type(def) == "table" and not MODES[def.mode] then def.mode = db.mode end
		if ns.db then ns.db.sshShare = nil end
		ep.defaultMode = MODES[db.mode] and db.mode or "limited"
		SSH.Restore(ep) -- (the groups remembered: connected again by itself)
	end
end

do
	local CI = C_ChatInfo
	if CI and CI.RegisterAddonMessagePrefix then pcall(CI.RegisterAddonMessagePrefix, SSH.PREFIX) end
	local f = CreateFrame("Frame")
	for _, ev in ipairs({ "CHAT_MSG_ADDON", "BN_CHAT_MSG_ADDON", "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "MAIL_INBOX_UPDATE",
		"PLAYER_MONEY", "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE",
		"BN_FRIEND_INFO_CHANGED", "BN_FRIEND_LIST_SIZE_CHANGED", "PLAYER_LOGOUT", "PLAYER_LOGIN" }) do
		pcall(f.RegisterEvent, f, ev)
	end
	f:SetScript("OnEvent", function(_, event, ...) SSH.OnEvent(event, ...) end)
	SSH.frame = f
end
