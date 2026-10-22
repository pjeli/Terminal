local ns = select(2, ...)
local L = ns.L

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
-- own slash commands do (in combat too: they open their windows as their own keys would).

local S = { mine = {} }
ns.Stored = S


local WHERE_LABEL = {
	bags = L["bags"], bank = L["bank"], mail = L["mail"], equipped = L["equipped"], void = L["void storage"],
	auctions = L["auctions"], guild = L["guild bank"], warband = L["warband bank"],
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
	-- (each copy's enchant, by where it is: ench["Name-Realm|bank"][itemID] = { [true] = a copy has one, [false] = one
	-- hasn't }; is:enchanted, 0.64.2. A row's link is one copy's.)
	local ench = {}
	local function note(items, place)
		for _, it in pairs(type(items) == "table" and items or {}) do
			if type(it) == "table" and type(it.itemID) == "number" then
				if not seen[it.itemID] then seen[it.itemID] = it end
				local e = place and ns.LinkEnchant(it.itemLink)
				if e then
					local p = ench[place] or {}
					ench[place] = p
					local s = p[it.itemID] or {}
					p[it.itemID] = s
					s[e ~= 0] = true
				end
			end
		end
	end
	local function notes(bags, place)
		for _, bag in pairs(type(bags) == "table" and bags or {}) do
			note(type(bag) == "table" and (bag.slots or bag), place)
		end
	end
	for _, full in ipairs(A.GetAllCharacters() or {}) do
		local c = A.GetByCharacterFullName(full)
		if type(c) == "table" then
			notes(c.bags, full .. "|bags"); notes(c.bank, full .. "|bank"); notes(c.bankTabs, full .. "|bank")
			note(c.mail, full .. "|mail"); note(c.equipped, full .. "|equipped"); notes(c.void, full .. "|void")
			note(c.auctions, full .. "|auctions")
		end
	end
	for _, full in ipairs(A.GetAllGuilds and A.GetAllGuilds() or {}) do
		local g = A.GetByGuildFullName(full)
		if type(g) == "table" then notes(g.bank, full .. "|guild") end
	end
	local w = A.GetWarband and A.GetWarband(1)
	if type(w) == "table" then notes(w.bank, "warband") end
	return seen, ench
end

--- Auctions in Syndicator's records that Terminal saw come back by mail (Mail.lua's MA.EndedAuctions), as
--- { [character] = { [itemID] = count } }, or nil: left out of "auctions". 0.48.9, the player: a failed auction's 200
--- arrows, mailed back and taken, still showed as on the auction house: the game told addons nothing when it came back, so
--- Syndicator keeps the auction until its next visit to the auction house.
local function EndedAuctions(A)
	local M = ns.Mail
	local ended = M and M.EndedAuctions and M.EndedAuctions()
	if not (ended and next(ended)) then return nil end
	local out
	for _, full in ipairs(A.GetAllCharacters() or {}) do
		local c = A.GetByCharacterFullName(full)
		for _, it in pairs(type(c) == "table" and type(c.auctions) == "table" and c.auctions or {}) do
			if type(it) == "table" and it.auctionID and ended[it.auctionID] and type(it.itemID) == "number" then
				out = out or {}
				local mine = out[full] or {}
				out[full] = mine
				mine[it.itemID] = (mine[it.itemID] or 0) + (tonumber(it.itemCount) or 1)
			end
		end
	end
	return out
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

	local seen, ench = SyndicatorItems(A) -- (every item id in the records; each copy's enchant, by place)
	local over = EndedAuctions(A) -- (auctions that came back, still in its records)

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
					if where == "auctions" and over and over[full] then n = n - (over[full][id] or 0) end
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
						add(id, n, it.itemLink, it.iconTexture, it.quality, h, ench[key] and ench[key][id])
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
						add(id, n, it.itemLink, it.iconTexture, it.quality, holders[key], ench[key] and ench[key][id])
					end
				end
			end
			local wb = type(info.warband) == "table" and tonumber(info.warband[1]) or 0
			if wb > 0 then
				holders.warband = holders.warband or { key = "warband", who = L["Warband"], where = "warband", owner = "warband" }
				add(id, wb, it.itemLink, it.iconTexture, it.quality, holders.warband, ench.warband and ench.warband[id])
			end
		end
	end
end

--- BagBrother's item strings: "1234", "1234;20", or a longer item payload "1234:0:...;20".
local function ParseBrother(s)
	if type(s) == "number" then return s, 1 end
	if type(s) ~= "string" or not s:find("^%d") then return nil end -- battle pets and the like
	local id = tonumber(s:match("^(%d+)"))
	local payload = s:match("^[^;]+")
	-- ("1234:1897:...": its enchant; "1234" alone is a plain copy: none)
	local e = payload:find(":", 1, true) and ns.LinkEnchant(payload) or 0
	return id, tonumber(s:match(";(%d+)$")) or 1, e
end

local function ReadBrother(bb, add)
	local B = Bagnon()
	local numBags = (type(B) == "table" and B.NumBags) or _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or _G.NUM_BAG_SLOTS or 4
	local me = type(B) == "table" and type(B.player) == "table" and B.player or {}
	local function items(t, holder)
		for slot, s in pairs(type(t) == "table" and (t.items or t) or {}) do
			if tonumber(slot) then
				local id, count, e = ParseBrother(s)
				if id then add(id, count, nil, nil, nil, holder, e and { [e ~= 0] = true } or nil) end
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
		local h = { key = "account", who = L["Warband"], where = "warband", owner = "warband" }
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
		local base = S.mine[where] or { key = "me|" .. where, who = S.mineName or L["You"], where = where, mine = true, owner = "me" }
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
	if h.mine then return L["you (%s)"]:format(where) end
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

-- Item names asked of the server and not here yet (BagBrother keeps only item numbers): the list is made again once
-- they're all in, or after 10 s (Util.lua's ns.NameWait; GET_ITEM_INFO_RECEIVED listened to only while awaited).
local nameWait = ns.NameWait("stored")
S.nameFrame = nameWait.frame
local function Name(id, link) return nameWait.Name(id, link) end

--- The holders grouped by who has them (a character, a guild, the warband), most first:
--- { name, total, parts = { "bank 20", "bags 5" }, class, mine, single }.
local function Groups(e)
	local byOwner, list = {}, {}
	for _, h in ipairs(Sorted(e)) do
		local key = h.mine and "me" or h.owner or h.key
		local g = byOwner[key]
		if not g then
			local name = h.who
			if h.where == "guild" then name = L["%s (guild)"]:format(h.who) end
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
	local lines = { L["%s:  %d in all"]:format(link, e.total) }
	for _, g in ipairs(Groups(e)) do
		local parts = GroupParts(g)
		lines[#lines + 1] = ("  %s%s: %d%s"):format(g.name, g.mine and (" " .. L["(you)"]) or "", g.total, parts ~= "" and ("  (" .. parts .. ")") or "")
	end
	return lines
end
S.Breakdown = Breakdown

--- Who has how many and where, a line each, and the total (the tooltip's lines; Terminal: Share's friends' items too).
function S.GroupLines(e, t)
	for _, g in ipairs(Groups(e)) do
		local name = (ClassHex(g.class) or "|cffffffff") .. g.name .. "|r" .. (g.mine and (" |cff9d9d9d" .. L["(you)"] .. "|r") or "")
		local parts = GroupParts(g)
		t:AddDoubleLine(name, "|cffffffff" .. g.total .. "|r" .. (parts ~= "" and ("  |cff9d9d9d" .. parts .. "|r") or ""), 1, 1, 1, 1, 1, 1)
	end
	t:AddDoubleLine(L["Total"], tostring(e.total), 1, 0.82, 0, 1, 0.82, 0)
end

--- The terminal's tooltip for a stored item: who has how many, and where, like Baganator's.
local function Tooltip(e, t)
	local c = e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
	t:SetText(e.name, c and c.r or 1, c and c.g or 1, c and c.b or 1)
	S.GroupLines(e, t)
	t:AddLine(" ")
	ns.KeyHints(t, L["Enter: show the ones you carry"] .. "    " .. L["Shift+Enter: show in chat"], 0.6, 0.6, 0.6)
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
		local text = head .. ": " .. table.concat(parts, ", ", 1, n) .. (more > 0 and (", " .. L["+%d more"]:format(more)) or "")
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
	local quality = x.quality or ns.ItemQuality(id)
	return {
		key = id,
		name = name,
		icon = x.icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)),
		color = QualityHex(quality),
		link = x.link or ("item:" .. id),
		-- short, so it fits beside the name; the tooltip has the rest
		detail = "x" .. x.total .. ns.DETAIL_SEP .. (nOwners == 1
			and ((first.where == "guild" and L["%s (guild)"]:format(first.who) or first.who) .. (first.mine and (" " .. L["(you)"]) or ""))
			or L["%d places"]:format(nOwners)),
		quality = quality,
		tooltip = Tooltip,
		text = "stored " .. table.concat(words, " "),
		holders = x.holders, total = x.total, itemID = id, enchanted = x.enchanted, unenchanted = x.unenchanted,
		activate = Open,
		secondary = PrintBreakdown,
		shareExtra = ChatSummary, -- (sent to chat: who holds how many)
	}
end

ns:RegisterProvider("stored", {
	label = L["Alts & bank"],
	color = "ffb4a0ff",
	-- ("bank" alone is @bank: this character's own, below; 0.62.1, the player)
	aliases = { "stored", "alts", "alt", "banks", "storage", "everywhere", "syndicator", "bagnon" },
	busy = function() return S.Busy() end, -- the terminal's spinner
	explicit = true, -- every item on every character: only with @stored (a plain search offers it when only it has a match)
	hintLabel = L["your alts and banks"],
	hintFull = true, -- (small enough to match fully: by item name and by who has it)
	hintSecond = true, -- offered under a carried item of the same name, too
	events = { "BAG_UPDATE_DELAYED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "MAIL_INBOX_UPDATE",
		"GUILDBANKBAGSLOTS_CHANGED", "PLAYER_EQUIPMENT_CHANGED" },
	guard = 1,
	idleDrop = 600,
	-- (read again a moment after a bag, bank or mail change, with the terminal closed: every plain search reads it for
	-- its hint, and it costs one item info per recorded item; review, 0.48.6)
	warmDirty = 2,
	-- (Syndicator's records in use, its callbacks heard: they say when its records change, after it has read them; the
	-- game's own bag, mail and bank events made the whole list again as well, a second time; review, 0.57.7)
	ignoreEvent = function() return S.hooked == true and S.Source() == "Syndicator" end,
	collect = function()
		local out = {}
		local byID = {}
		local function add(id, count, link, icon, quality, holder, enchants)
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
			-- (is:enchanted: some copy here has one, some hasn't; the row's and each holder's, for @bank's own)
			if enchants then
				if enchants[true] then e.enchanted, h.enchanted = true, true end
				if enchants[false] then e.unenchanted, h.unenchanted = true, true end
			end
		end
		S.HookSyndicator()
		S.mine = {}
		local src = S.Source()
		local A = src == "Syndicator" and SyndicatorAPI() or nil
		local bb = src == "BagBrother" and BrotherBags() or nil
		if A and not SyndicatorReady(A) then A = nil end -- busy() says so; filled in once it's ready
		S.mineName = ns.CharacterName() or L["You"] -- (with the surname, as Syndicator names characters)
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


----------------------------------------------------------------------
-- @bank (0.62.1, the player: "@bank as just MY bank (current player's bank) ... from @stored (which is everyone on alts
-- as well)"): what this character has in its bank, @stored's rows cut to that one place (its count the bank's, as the
-- game counts it while you're online: LiveCounts)
----------------------------------------------------------------------

--- This character's bank holder of a @stored row, or nil.
function S.MyBank(e)
	for _, h in pairs(type(e) == "table" and e.holders or {}) do
		if h.mine and h.where == "bank" and (h.count or 0) > 0 then return h end
	end
end

ns:RegisterProvider("bank", {
	label = L["Bank"],
	color = "ffc9b27a",
	aliases = { "bank", "mybank" },
	explicit = true, -- (the same items as @stored: only asked for)
	follows = "stored", -- (made again whenever @stored is)
	idleDrop = 600, -- (let go with @stored's, unused: its rows hold @stored's holders)
	busy = function() return S.Busy() end,
	collect = function()
		local out = {}
		for _, e in ipairs(ns:GetEntries(ns.providers.stored)) do
			local h = S.MyBank(e)
			if h then
				local c = {}
				for k, v in pairs(e) do c[k] = v end -- (a copy: the @stored row keeps every holder)
				c.holders = { [h.key] = h }
				c.total = h.count
				c.enchanted, c.unenchanted = rawget(h, "enchanted"), rawget(h, "unenchanted") -- (the bank's copies' own)
				-- (searched by its name and its place, not by every holder @stored's row has: "@bank mail")
				c.text, c._ltext = nil, ns.Lower(L["bank"] .. " bank " .. tostring(h.who or ""))
				c.detail = "x" .. h.count .. ns.DETAIL_SEP .. L["bank"]
				out[#out + 1] = c
			end
		end
		return out
	end,
})

-- "what is in my bank", "my bank", "bank items": @bank's rows (Search.lua's Scan.ANSWERS: Asks("MyBankQ"))
local BQ = {}
ns.MyBankQ = BQ
local BANK_ASKS = {}
for _, s in ipairs({ "what is in my bank", "whats in my bank", "what do i have in my bank", "what do i have in the bank",
	"what is in the bank", "whats in the bank", "my bank", "my bank items", "bank items", "items in my bank", "items in bank",
	"show my bank", "list my bank", "show bank", "my bank contents", "bank contents", "whats in bank", "what is in bank",
	"what have i got in my bank", "what did i put in my bank", "what is stored in my bank", "whats stored in my bank" }) do
	BANK_ASKS[s] = true
end

function BQ.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub(" please$", "")
	if BANK_ASKS[t] then return {} end
	return nil
end

function BQ.Answer()
	local p = ns.providers.bank
	local note = L["Your bank"]
	if not (p and S.Source()) then
		return { ns.NoteRow(L["Needs Syndicator (Baganator) or BagBrother (Bagnon): they keep what's in your bank"]) }, note
	end
	local rows = {}
	for _, e in ipairs(ns:GetEntries(p)) do rows[#rows + 1] = e end
	if #rows == 0 then
		local busy = S.Busy() -- (Syndicator still reading your characters)
		return { ns.NoteRow(busy or L["Nothing kept in your bank yet: open it once with your bag addon running"]) }, note
	end
	table.sort(rows, function(a, b) return tostring(a.name) < tostring(b.name) end)
	ns.ScoreInOrder(rows)
	return rows, note .. ns.DETAIL_SEP .. ((#rows == 1 and L["%d item"] or L["%d items"]):format(#rows))
end

function BQ.ToAdvanced() return "@bank " end

-- Syndicator says when its records change (any character, guild or the warband bank).
function S.HookSyndicator()
	local R = _G.Syndicator and _G.Syndicator.CallbackRegistry
	if type(R) ~= "table" or not R.RegisterCallback or S.hooked then return end
	S.hooked = true
	-- (0.50.7, review: these set the list dirty directly, so it was read again inside the next keystroke, and the
	-- currency ones, which change no item, did it too; now through ns:Changed, read in the background, money for Gold)
	local function dirty()
		ns:Changed("stored")
		ns:Changed("gold") -- (Gold.lua: money is in the same records)
	end
	local function money() ns:Changed("gold") end
	for _, ev in ipairs({ "Ready", "BagCacheUpdate", "MailCacheUpdate", "GuildCacheUpdate", "WarbandBankCacheUpdate",
		"EquippedCacheUpdate", "VoidCacheUpdate", "AuctionsCacheUpdate", "CharacterDeleted", "GuildDeleted" }) do
		pcall(R.RegisterCallback, R, ev, dirty, S)
	end
	for _, ev in ipairs({ "CurrencyCacheUpdate", "WarbandCurrencyCacheUpdate" }) do pcall(R.RegisterCallback, R, ev, money, S) end
end
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function() S.HookSyndicator() end)

--- While the records aren't all in: Syndicator still scanning, or item names on their way from
--- the server. The terminal shows a spinner with this text.
function S.Busy()
	local A = S.Source() == "Syndicator" and SyndicatorAPI()
	if A and not SyndicatorReady(A) then return L["Waiting for Syndicator to finish reading your characters"] end
	local n = nameWait.count
	if n > 0 then
		return (n == 1 and L["Loading %d item name from the server for %s's records"] or L["Loading %d item names from the server for %s's records"])
			:format(n, S.Source() or L["your bag addon"])
	end
end

--- For .integrations: where the counts come from.
function S.Status()
	local src = S.Source()
	if not src then
		if BrotherBags() then return L["not used: BagBrother's records are there but Bagnon isn't loaded (they'd be stale)"] end
		return L["not found (install Syndicator/Baganator or Bagnon)"]
	end
	local n = 0
	if src == "Syndicator" then
		if not SyndicatorReady(SyndicatorAPI()) then return L["Syndicator, still loading (@stored)"] end
		n = #(SyndicatorAPI().GetAllCharacters() or {})
		local connected = ConnectedOnly(SyndicatorConfig())
		return L["Syndicator, %d character(s) tracked, counted as its tooltip counts them%s (@stored)"]:format(
			n, connected and (" " .. L["(connected realms only)"]) or "")
	else
		for realm, owners in pairs(BrotherBags()) do
			if realm ~= "account" and type(owners) == "table" then
				for id in pairs(owners) do if type(id) == "string" and not id:find("%*$") then n = n + 1 end end
			end
		end
	end
	return L["%s, %d character(s) (@stored)"]:format(src, n)
end
