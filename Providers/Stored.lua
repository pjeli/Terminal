local ns = select(2, ...)

-- Items on your other characters, in banks, mailboxes, guild banks and the warband bank,
-- read from the bag addon that records them: Syndicator (Baganator's) or BagBrother
-- (Bagnon's). "where is my Linen Cloth?" -> one result per item, with how many and on whom.
--
--   Enter        like an Item result: your bags open on the ones you carry (nothing if none);
--                the tooltip lists who has them and where
--   Shift+Enter  the full breakdown in chat
--
-- Items only in the bags you carry are left to the Item results. With both addons loaded the
-- counts come from Syndicator (it has full item links and guild names) and items open in Bagnon.
-- Bag addon frames belong to those addons, not Blizzard: opening them from here is what their
-- own slash commands do. In combat they can't build their secure item buttons, so Enter waits.

local S = { mine = {} }
ns.Stored = S


local WHERE_LABEL = {
	bags = "bags", bank = "bank", mail = "mail", equipped = "equipped", void = "void storage",
	auctions = "auctions", guild = "guild bank", warband = "warband bank",
}

--- Syndicator's API when it's loaded (ready or not).
local function SyndicatorAPI()
	local A = _G.Syndicator and _G.Syndicator.API
	return A and A.GetAllCharacters and A.GetByCharacterFullName and A or nil
end

local function SyndicatorReady(A)
	local ok, ready = pcall(function() return not A.IsReady or A.IsReady() end)
	return ok and ready
end

local function BrotherBags()
	local bb = _G.BrotherBags
	return type(bb) == "table" and next(bb) ~= nil and bb or nil
end

local function Bagnon() return ns.Bags.Bagnon() end -- shared with the Item results (Bags.lua)
S.SyndicatorAPI, S.SyndicatorReady, S.BrotherBags = SyndicatorAPI, SyndicatorReady, BrotherBags

--- Whose records to read: those of the bag addon in use this session, and only those. Bagnon's
--- bags -> BagBrother's records; Baganator's (or Syndicator on its own) -> Syndicator's. Records an
--- addon left behind while it isn't loaded are stale (an old realm, a deleted character) and are
--- never read, and while Syndicator is still loading nothing else stands in for it.
--- "Syndicator", "BagBrother" or nil.
function S.Source()
	local which = ns.Bags.Active()
	if which == "Baganator" then return SyndicatorAPI() and "Syndicator" or nil end
	if which then return BrotherBags() and "BagBrother" or nil end -- Bagnon or Bagnonium
	return SyndicatorAPI() and "Syndicator" or nil
end

----------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------

-- add(itemID, count, link, icon, quality, holder): holder = { key, who, where, mine, ...where it is }

--- Syndicator's tooltip settings (SYNDICATOR_CONFIG), or an empty table.
local function SyndicatorConfig()
	return type(_G.SYNDICATOR_CONFIG) == "table" and _G.SYNDICATOR_CONFIG or {}
end

--- Whether Syndicator's tooltip counts connected realms only: its setting, else its default (not on retail).
local function ConnectedOnly(cfg)
	local connected = cfg.tooltips_connected_realms_only_2
	if connected == nil then connected = not (_G.Syndicator.Constants and _G.Syndicator.Constants.IsRetail) end
	return connected
end

--- Every item id in Syndicator's records (characters, guild banks, the warband bank), each with an
--- item table carrying a link, icon and quality to show it by.
local function SyndicatorItems(A)
	local seen = {}
	local function note(items)
		for _, it in pairs(type(items) == "table" and items or {}) do
			if type(it) == "table" and type(it.itemID) == "number" and not seen[it.itemID] then
				seen[it.itemID] = it
			end
		end
	end
	local function notes(bags)
		for _, bag in pairs(type(bags) == "table" and bags or {}) do
			note(type(bag) == "table" and (bag.slots or bag))
		end
	end
	for _, full in ipairs(A.GetAllCharacters() or {}) do
		local c = A.GetByCharacterFullName(full)
		if type(c) == "table" then
			notes(c.bags); notes(c.bank); notes(c.bankTabs); note(c.mail); note(c.equipped); notes(c.void); note(c.auctions)
		end
	end
	for _, full in ipairs(A.GetAllGuilds and A.GetAllGuilds() or {}) do
		local g = A.GetByGuildFullName(full)
		if type(g) == "table" then notes(g.bank) end
	end
	local w = A.GetWarband and A.GetWarband(1)
	if type(w) == "table" then notes(w.bank) end
	return seen
end

--- Syndicator: the same counts its own tooltip shows. Every item in its records is looked up with
--- its API (GetInventoryInfoByItemID), with the tooltip's own settings (SYNDICATOR_CONFIG):
--- connected realms only (the default on this client), one faction only, guild banks and worn items
--- shown or not. Characters it hides, or on realms its tooltip leaves out, don't count here either.
local function ReadSyndicator(A, add)
	local cfg = SyndicatorConfig()
	local connectedOnly = ConnectedOnly(cfg)
	local factionOnly = cfg.tooltips_faction_only == true
	local showGuilds = cfg.show_guild_banks_in_tooltips ~= false
	local showWorn = cfg.show_equipped_items_in_tooltips ~= false
	local current = A.GetCurrentCharacter and A.GetCurrentCharacter()
	local myRealm = current and current:match("%-(.+)$")

	local seen = SyndicatorItems(A) -- (every item id in the records)

	local holders = {} -- one per owner and place, shared by every item they hold
	local PLACES = { "bags", "bank", "mail", "equipped", "void", "auctions" }
	for id, it in pairs(seen) do
		local ok, info = pcall(A.GetInventoryInfoByItemID, id, connectedOnly, factionOnly)
		if ok and type(info) == "table" then
			for _, c in ipairs(info.characters or {}) do
				local realm = c.realmNormalized or ""
				local full = c.character .. (realm ~= "" and ("-" .. realm) or "")
				local mine = full == current
				for _, where in ipairs(PLACES) do
					local n = tonumber(c[where]) or 0
					if n > 0 and (where ~= "equipped" or showWorn) then
						local key = full .. "|" .. where
						local h = holders[key]
						if not h then
							local d = (A.GetByCharacterFullName(full) or {}).details or {}
							local who = c.character
							if myRealm and realm ~= "" and realm ~= myRealm then who = who .. "-" .. realm end
							h = { key = key, who = who, where = where, mine = mine, owner = full, class = d.className or d.class }
							holders[key] = h
							if mine then S.mine[where] = h end
						end
						add(id, n, it.itemLink, it.iconTexture, it.quality, h)
					end
				end
			end
			if showGuilds then
				for _, g in ipairs(info.guilds or {}) do
					local n = tonumber(g.bank) or 0
					if n > 0 then
						local full = g.guild .. "-" .. (g.realmNormalized or "")
						local key = full .. "|guild"
						holders[key] = holders[key] or { key = key, who = g.guild, where = "guild", owner = full }
						add(id, n, it.itemLink, it.iconTexture, it.quality, holders[key])
					end
				end
			end
			local wb = type(info.warband) == "table" and tonumber(info.warband[1]) or 0
			if wb > 0 then
				holders.warband = holders.warband or { key = "warband", who = "Warband", where = "warband", owner = "warband" }
				add(id, wb, it.itemLink, it.iconTexture, it.quality, holders.warband)
			end
		end
	end
end

--- BagBrother's item strings: "1234", "1234;20", or a longer item payload "1234:0:...;20".
local function ParseBrother(s)
	if type(s) == "number" then return s, 1 end
	if type(s) ~= "string" or not s:find("^%d") then return nil end -- battle pets and the like
	local id = tonumber(s:match("^(%d+)"))
	return id, tonumber(s:match(";(%d+)$")) or 1
end

local function ReadBrother(bb, add)
	local B = Bagnon()
	local numBags = (type(B) == "table" and B.NumBags) or _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or _G.NUM_BAG_SLOTS or 4
	local me = type(B) == "table" and type(B.player) == "table" and B.player or {}
	local function items(t, holder)
		for slot, s in pairs(type(t) == "table" and (t.items or t) or {}) do
			if tonumber(slot) then
				local id, count = ParseBrother(s)
				if id then add(id, count, nil, nil, nil, holder) end
			end
		end
	end
	for realm, owners in pairs(bb) do
		if realm ~= "account" and type(owners) == "table" then
			for id, cache in pairs(owners) do
				if type(id) == "string" and type(cache) == "table" then
					local isGuild = id:find("%*$") ~= nil
					local who = isGuild and id:sub(1, -2) or id
					if me.realm and realm ~= me.realm then who = who .. "-" .. realm end
					local mine = (realm == me.realm and id == me.id) or false
					local function holder(where)
						local h = { key = realm .. "|" .. id .. "|" .. where, who = who, where = where, mine = mine,
							owner = realm .. "|" .. id, class = cache.class }
						if mine then S.mine[where] = h end
						return h
					end
					if isGuild then
						local h = holder("guild")
						for tab, t in pairs(cache) do
							if tonumber(tab) then items(t, h) end
						end
					else
						local bags, bank = holder("bags"), holder("bank")
						for bag, t in pairs(cache) do
							bag = tonumber(bag)
							if bag then
								local inBags = (bag >= 0 and bag <= numBags) or bag == (_G.KEYRING_CONTAINER or -2)
								items(t, inBags and bags or bank)
							end
						end
						items(cache.equip, holder("equipped"))
						items(cache.mail, holder("mail"))
						items(cache.vault, holder("void"))
					end
				end
			end
		end
	end
	if type(bb.account) == "table" then
		local h = { key = "account", who = "Warband", where = "warband", owner = "warband" }
		for bag, t in pairs(bb.account) do
			if tonumber(bag) then items(t, h) end
		end
	end
end

----------------------------------------------------------------------
-- Entries
----------------------------------------------------------------------

--- A holder's per-item counts read the rest from it (one metatable per holder, not per item).
local function HolderMeta(holder)
	local mt = holder._mt
	if not mt then mt = { __index = holder }; holder._mt = mt end
	return mt
end

local function ItemCount(id, bank)
	local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	if not f then return nil end
	local ok, n = pcall(f, id, bank, false, bank)
	return ok and type(n) == "number" and n or nil
end

--- Your own bags and bank as the game counts them now. A record can be stale (it was written
--- when the bank was last open, or by an older version), and you are online: the live count is
--- the truth, as in Bagnon's own tooltip. Equipped items count as carried, so they come off.
local function LiveCounts(e)
	local carrying, withBank = ItemCount(e.id, false), ItemCount(e.id, true)
	if not (carrying and withBank) then return end
	local worn = e.holders[S.mine.equipped and S.mine.equipped.key or ""]
	local live = { bags = math.max(0, carrying - (worn and worn.count or 0)), bank = math.max(0, withBank - carrying) }
	for where, n in pairs(live) do
		local base = S.mine[where] or { key = "me|" .. where, who = S.mineName or "You", where = where, mine = true, owner = "me" }
		local h = e.holders[base.key]
		local had = h and h.count or 0
		if had ~= n then
			if where == "bank" then ns:Trace(("stored: your bank record had %d of item %d, the game counts %d"):format(had, e.id, n)) end
			e.total = e.total - had + n
			if n == 0 then
				e.holders[base.key] = nil
			elseif h then
				h.count = n
			else
				e.holders[base.key] = setmetatable({ count = n }, HolderMeta(base))
			end
		end
	end
end

local QualityHex = ns.QualityHex -- (Util.lua)

local function HolderLabel(h)
	local where = WHERE_LABEL[h.where] or h.where
	if h.mine then return "you (" .. where .. ")" end
	if h.where == "guild" or h.where == "warband" then return h.who end
	if h.where == "bags" then return h.who end
	return h.who .. " (" .. where .. ")"
end

--- What you carry or wear right now (the Item results already cover it).
local function Carried(h) return (h.mine and (h.where == "bags" or h.where == "equipped")) == true end

--- Holders in the order to show and open them: the most first, what you carry last.
local function Sorted(e)
	local list = {}
	for _, h in pairs(e.holders) do list[#list + 1] = h end
	table.sort(list, function(a, b)
		local ac, bc = Carried(a), Carried(b)
		if ac ~= bc then return bc end
		if a.count ~= b.count then return a.count > b.count end
		return HolderLabel(a) < HolderLabel(b)
	end)
	return list
end

-- Item names asked of the server and not here yet (BagBrother keeps only item numbers). Each
-- arrives with its own GET_ITEM_INFO_RECEIVED; the list is rebuilt once they're all in.
local waiting, waitingCount = {}, 0
local waitGen = 0 -- which wait the give-up timer belongs to (bumped whenever a wait ends)
local asked = {} -- item id -> times its name was asked for (some never come: stop after two)

local function Arrived(id)
	if waiting[id] then
		waiting[id] = nil
		waitingCount = waitingCount - 1
		if waitingCount == 0 then
			waitGen = waitGen + 1
			if ns.providers.stored then ns.providers.stored._dirty = true end
		end
	end
end

local function Name(id, link)
	local name = type(link) == "string" and link:match("|h%[(.-)%]|h")
	if name and name ~= "" then return name end
	name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if name and name ~= "" then return name end
	if C_Item and C_Item.RequestLoadItemDataByID and (asked[id] or 0) < 2 and not waiting[id] then
		asked[id] = (asked[id] or 0) + 1
		if waitingCount == 0 then
			-- names that never come don't keep the list waiting (only this wait: an older one's timer
			-- would end a newer wait early)
			local gen = waitGen
			C_Timer.After(10, function()
				if waitGen == gen and waitingCount > 0 then
					for k in pairs(waiting) do waiting[k] = nil end
					waitingCount = 0
					waitGen = waitGen + 1
					if ns.providers.stored then ns.providers.stored._dirty = true end
				end
			end)
		end
		waiting[id] = true
		waitingCount = waitingCount + 1
		pcall(C_Item.RequestLoadItemDataByID, id)
	end
end

--- The holders grouped by who has them (a character, a guild, the warband), most first:
--- { name, total, parts = { "bank 20", "bags 5" }, class, mine, single }.
local function Groups(e)
	local byOwner, list = {}, {}
	for _, h in ipairs(Sorted(e)) do
		local key = h.mine and "me" or h.owner or h.key
		local g = byOwner[key]
		if not g then
			local name = h.who
			if h.where == "guild" then name = h.who .. " (guild)" end
			g = { name = name, total = 0, parts = {}, class = h.class, mine = h.mine, place = h.where }
			byOwner[key] = g
			list[#list + 1] = g
		end
		g.total = g.total + h.count
		g.parts[#g.parts + 1] = (WHERE_LABEL[h.where] or h.where) .. " " .. h.count
	end
	table.sort(list, function(a, b)
		if a.total ~= b.total then return a.total > b.total end
		return a.name < b.name
	end)
	return list
end
S.Groups = Groups
S.Name = Name -- (tests)

local function GroupParts(g)
	-- a guild or the warband holds things in one place: its name says where
	if #g.parts == 1 and (g.place == "guild" or g.place == "warband") then return "" end
	return table.concat(g.parts, ", ")
end

local ClassHex = ns.ClassHex

local function Breakdown(e)
	local link = type(e.link) == "string" and e.link:find("^|c") and e.link or e.name
	local lines = { link .. ":  " .. e.total .. " in all" }
	for _, g in ipairs(Groups(e)) do
		local parts = GroupParts(g)
		lines[#lines + 1] = ("  %s%s: %d%s"):format(g.name, g.mine and " (you)" or "", g.total, parts ~= "" and ("  (" .. parts .. ")") or "")
	end
	return lines
end
S.Breakdown = Breakdown

--- The terminal's tooltip for a stored item: who has how many, and where, like Baganator's.
local function Tooltip(e, t)
	local c = e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
	t:SetText(e.name, c and c.r or 1, c and c.g or 1, c and c.b or 1)
	for _, g in ipairs(Groups(e)) do
		local name = (ClassHex(g.class) or "|cffffffff") .. g.name .. "|r" .. (g.mine and " |cff9d9d9d(you)|r" or "")
		local parts = GroupParts(g)
		t:AddDoubleLine(name, "|cffffffff" .. g.total .. "|r" .. (parts ~= "" and ("  |cff9d9d9d" .. parts .. "|r") or ""), 1, 1, 1, 1, 1, 1)
	end
	t:AddDoubleLine("Total", tostring(e.total), 1, 0.82, 0, 1, 0.82, 0)
	t:AddLine(" ")
	t:AddLine("Enter: show the ones you carry    Shift+Enter: list in chat", 0.6, 0.6, 0.6, true)
end
S.Tooltip = Tooltip

local function PrintBreakdown(e) ns:Output(Breakdown(e)) end

--- What follows the item's link when it's sent to chat (>> party, the menu's chat lines, a chain's "> alts"): how many
--- in all and who holds them, " x48: Plamen Warr 20 (bags 12, bank 8), Plamen Pally 28 (bank), Warband 5". Within
--- `room` characters when given: the smallest holders go first ("+2 more").
function S.ChatSummary(e, room)
	if type(e.total) ~= "number" or type(e.holders) ~= "table" then return nil end
	local head = " x" .. e.total
	local groups = Groups(e)
	local parts = {}
	for _, g in ipairs(groups) do
		local where
		if #g.parts == 1 then
			where = (g.place ~= "guild" and g.place ~= "warband") and (WHERE_LABEL[g.place] or g.place) or nil
		else
			where = table.concat(g.parts, ", ")
		end
		parts[#parts + 1] = g.name .. " " .. g.total .. (where and (" (" .. where .. ")") or "")
	end
	if #parts == 0 then return head end
	local n = #parts
	while n > 0 do
		local more = #parts - n
		local text = head .. ": " .. table.concat(parts, ", ", 1, n) .. (more > 0 and (", +" .. more .. " more") or "")
		if not room or #text <= room then return text end
		n = n - 1
	end
	return head
end
local function ChatSummary(e, room) return S.ChatSummary(e, room) end

--- Enter or a click: like an Item result, your bags open on the ones you carry, highlighted.
--- Carrying none, nothing happens: the tooltip already says who has them and where.
local function Open(e)
	if not ns.Bags.ShowItem(e.itemID, e.link, e.name) then
		ns:Trace("stored: you don't carry " .. tostring(e.name) .. ", nothing to show")
	end
end

--- The row for an item kept somewhere you aren't carrying it: x = { total, holders, link, icon, quality }.
local function StoredRow(id, x, name)
	local words = {}
	for _, h in pairs(x.holders) do words[#words + 1] = h.who .. " " .. (WHERE_LABEL[h.where] or h.where) end
	-- who has it: one owner is named, more are counted (the tooltip groups them)
	local owners, first, nOwners = {}, nil, 0
	for _, h in pairs(x.holders) do
		local k = h.mine and "me" or h.owner or h.key
		if not owners[k] then owners[k] = true; nOwners = nOwners + 1; first = h end
	end
	local quality = x.quality or (C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id))
	return {
		key = id,
		name = name,
		icon = x.icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)),
		color = QualityHex(quality),
		link = x.link or ("item:" .. id),
		-- short, so it fits beside the name; the tooltip has the rest
		detail = x.total .. "  ·  " .. (nOwners == 1
			and ((first.where == "guild" and first.who .. " (guild)" or first.who) .. (first.mine and " (you)" or ""))
			or (nOwners .. " places")),
		quality = quality,
		tooltip = Tooltip,
		text = "stored " .. table.concat(words, " "),
		holders = x.holders, total = x.total, itemID = id,
		activate = Open,
		secondary = PrintBreakdown,
		shareExtra = ChatSummary, -- (sent to chat: who holds how many)
	}
end

ns:RegisterProvider("stored", {
	label = "Stored",
	color = "ffb4a0ff",
	aliases = { "stored", "alts", "alt", "bank", "banks", "storage", "everywhere", "syndicator", "bagnon" },
	busy = function() return S.Busy() end, -- the terminal's spinner
	explicit = true, -- every item on every character: only with @stored (a plain search offers it when only it has a match)
	hintLabel = "your alts and banks",
	hintFull = true, -- (small enough to match fully: by item name and by who has it)
	hintSecond = true, -- offered under a carried item of the same name, too
	events = { "BAG_UPDATE_DELAYED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "MAIL_INBOX_UPDATE",
		"GUILDBANKBAGSLOTS_CHANGED", "PLAYER_EQUIPMENT_CHANGED" },
	guard = 1,
	idleDrop = 600,
	collect = function()
		local out = {}
		local byID = {}
		local function add(id, count, link, icon, quality, holder)
			local e = byID[id]
			if not e then
				e = { id = id, total = 0, holders = {}, link = link, icon = icon, quality = quality }
				byID[id] = e
			end
			e.link = e.link or link
			e.icon = e.icon or icon
			e.quality = e.quality or quality
			local h = e.holders[holder.key]
			if not h then
				h = setmetatable({ count = 0 }, HolderMeta(holder))
				e.holders[holder.key] = h
			end
			h.count = h.count + (count or 1)
			e.total = e.total + (count or 1)
		end
		S.HookSyndicator()
		S.mine = {}
		local src = S.Source()
		local A = src == "Syndicator" and SyndicatorAPI() or nil
		local bb = src == "BagBrother" and BrotherBags() or nil
		if A and not SyndicatorReady(A) then A = nil end -- busy() says so; filled in once it's ready
		S.mineName = ns.CharacterName() or "You" -- (with the surname, as Syndicator names characters)
		if A then ReadSyndicator(A, add) elseif bb then ReadBrother(bb, add) end
		for _, x in pairs(byID) do LiveCounts(x) end
		for id, x in pairs(byID) do
			-- only what's somewhere you aren't carrying it (your bags are the Item results)
			local elsewhere = false
			for _, h in pairs(x.holders) do
				if not Carried(h) then elsewhere = true break end
			end
			local name = elsewhere and Name(id, x.link)
			if name then out[#out + 1] = StoredRow(id, x, name) end
		end
		return out
	end,
})

-- Names the server hadn't sent yet: rebuild once they arrive.
local f = CreateFrame("Frame")
S.nameFrame = f
pcall(f.RegisterEvent, f, "GET_ITEM_INFO_RECEIVED")
f:SetScript("OnEvent", function(_, _, itemID, success)
	if waitingCount == 0 then return end
	if itemID then Arrived(itemID) return end
	-- some clients don't say which: whatever has a name now has arrived
	for id in pairs(waiting) do
		if C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) then Arrived(id) end
	end
end)

-- Syndicator says when its records change (any character, guild or the warband bank).
function S.HookSyndicator()
	local R = _G.Syndicator and _G.Syndicator.CallbackRegistry
	if type(R) ~= "table" or not R.RegisterCallback or S.hooked then return end
	S.hooked = true
	local function dirty()
		if ns.providers.stored then ns.providers.stored._dirty = true end
		if ns.providers.gold then ns.providers.gold._dirty = true end -- (Gold.lua: money is in the same records)
	end
	for _, ev in ipairs({ "Ready", "BagCacheUpdate", "MailCacheUpdate", "GuildCacheUpdate", "WarbandBankCacheUpdate",
		"EquippedCacheUpdate", "VoidCacheUpdate", "AuctionsCacheUpdate", "CharacterDeleted", "GuildDeleted",
		"CurrencyCacheUpdate", "WarbandCurrencyCacheUpdate" }) do
		pcall(R.RegisterCallback, R, ev, dirty, S)
	end
end
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function() S.HookSyndicator() end)

--- While the records aren't all in: Syndicator still scanning, or item names on their way from
--- the server. The terminal shows a spinner with this text.
function S.Busy()
	local A = S.Source() == "Syndicator" and SyndicatorAPI()
	if A and not SyndicatorReady(A) then return "Waiting for Syndicator to finish reading your characters" end
	if waitingCount > 0 then
		return ("Loading %d item name%s from the server for %s's records"):format(waitingCount, waitingCount == 1 and "" or "s", S.Source() or "your bag addon")
	end
end

--- For .integrations: where the counts come from.
function S.Status()
	local src = S.Source()
	if not src then
		if BrotherBags() then return "not used: BagBrother's records are there but Bagnon isn't loaded (they'd be stale)" end
		return "not found (install Syndicator/Baganator or Bagnon)"
	end
	local n = 0
	if src == "Syndicator" then
		if not SyndicatorReady(SyndicatorAPI()) then return "Syndicator, still loading (@stored)" end
		n = #(SyndicatorAPI().GetAllCharacters() or {})
		local connected = ConnectedOnly(SyndicatorConfig())
		return ("Syndicator, %d character(s) tracked, counted as its tooltip counts them%s (@stored)"):format(
			n, connected and " (connected realms only)" or "")
	else
		for realm, owners in pairs(BrotherBags()) do
			if realm ~= "account" and type(owners) == "table" then
				for id in pairs(owners) do if type(id) == "string" and not id:find("%*$") then n = n + 1 end end
			end
		end
	end
	return ("%s, %d character(s) (@stored)"):format(src, n)
end
