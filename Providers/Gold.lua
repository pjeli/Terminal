local ns = select(2, ...)

-- Your gold (@gold, also @money; Simple mode: "gold", under Character). Your own is read live (GetMoney). With a bag addon
-- that records your characters, every alt's gold is listed too, plus guild banks and the warband bank, and a row on top
-- with all of it together, counted as that addon's own gold summary counts it:
--   Syndicator (Baganator): the characters and guilds its gold tooltip shows: connected realms, "show gold" not turned
--     off for them, your faction only where Baganator keeps to it (classic clients; not WoW Forever)
--   BagBrother (Bagnon): its characters on your realm and the realms connected to it
-- Records are read only from the bag addon in use this session (Stored.Source), as @stored does.
--
--   Enter        every row's gold in chat (only you see it)
--   Shift+Enter  the row in the chat box ("All gold: 1,234g 5s 6c"), to send

local G = {}
ns.Gold = G

local Safe, Num, Str = ns.Safe, ns.Num, ns.Str

local COPPER_PER_GOLD, COPPER_PER_SILVER = 10000, 100
local ICON = {
	gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

--- 1234567 -> "1,234,567" (no %d: past 2^31 it overflows on this client).
function G.Thousands(n)
	local s = ("%.0f"):format(math.floor(n))
	local sep = _G.LARGE_NUMBER_SEPERATOR
	if type(sep) ~= "string" or sep == "" then sep = "," end
	local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep:reverse()):reverse()
	return (out:gsub("^%" .. sep, ""))
end

--- Copper as gold, silver and copper: with coin icons (`plain` false), or "1,234g 5s 6c" for chat.
function G.Text(copper, plain)
	copper = math.max(0, math.floor(tonumber(copper) or 0))
	local g = math.floor(copper / COPPER_PER_GOLD)
	local s = math.floor((copper % COPPER_PER_GOLD) / COPPER_PER_SILVER)
	local c = copper % COPPER_PER_SILVER
	local parts = {}
	if g > 0 then parts[#parts + 1] = G.Thousands(g) .. (plain and "g" or ICON.gold) end
	if s > 0 or (g > 0 and c > 0) then parts[#parts + 1] = s .. (plain and "s" or ICON.silver) end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. (plain and "c" or ICON.copper) end
	return table.concat(parts, " ")
end

----------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------

-- add(holder): { key, who, money, class, kind = "me"/"alt"/"guild"/"warband" }

--- The warband bank's gold, live (only while the game lets the account bank be read).
local function LiveWarband()
	if not (C_Bank and C_Bank.FetchDepositedMoney and Enum and Enum.BankType and Enum.BankType.Account) then return nil end
	return Num(Safe(C_Bank.FetchDepositedMoney, Enum.BankType.Account))
end

local function ReadSyndicator(A, add, me)
	local S = _G.Syndicator
	local realms = {}
	local list = S.Utilities and S.Utilities.GetConnectedRealms and Safe(S.Utilities.GetConnectedRealms)
	for _, r in ipairs(type(list) == "table" and list or {}) do realms[r] = true end
	local current = A.GetCurrentCharacter and Safe(A.GetCurrentCharacter)
	local cur = current and A.GetByCharacterFullName(current)
	local curDetails = type(cur) == "table" and cur.details or {}
	local myRealm = curDetails.realmNormalized or (current and current:match("%-(.+)$"))
	if not next(realms) and myRealm then realms[myRealm] = true end -- (no list: your realm only)
	local faction = S.Constants and S.Constants.IsClassic and curDetails.faction or nil
	local function Shown(d)
		if type(d.show) == "table" then return d.show.gold ~= false end
		return d.hidden ~= true
	end
	local function Name(d, full)
		local n = d.character or full:match("^(.-)%-") or full
		if d.realmNormalized and d.realmNormalized ~= myRealm then n = n .. "-" .. d.realmNormalized end
		return n
	end
	for _, full in ipairs(A.GetAllCharacters() or {}) do
		local c = A.GetByCharacterFullName(full)
		local d = type(c) == "table" and type(c.details) == "table" and c.details or nil
		if d and full ~= current and realms[d.realmNormalized or ""] and Shown(d) and (not faction or d.faction == faction) then
			add({ key = "c:" .. full, who = Name(d, full), money = tonumber(c.money) or 0, class = d.className, kind = "alt" })
		end
	end
	for _, full in ipairs(A.GetAllGuilds and A.GetAllGuilds() or {}) do
		local g = A.GetByGuildFullName(full)
		local d = type(g) == "table" and type(g.details) == "table" and g.details or nil
		-- (guilds' gold is shown only when turned on for them, as Baganator's summary does)
		if d and realms[d.realmNormalized or ""] and type(d.show) == "table" and d.show.gold and (not faction or d.faction == faction) then
			add({ key = "g:" .. full, who = Name({ character = d.guild, realmNormalized = d.realmNormalized }, full),
				money = tonumber(g.money) or 0, kind = "guild" })
		end
	end
	local w = A.GetWarband and Safe(A.GetWarband, 1)
	if type(w) == "table" and (w.details == nil or w.details.gold) then
		add({ key = "warband", who = "Warband bank", money = LiveWarband() or tonumber(w.money) or 0, kind = "warband" })
	end
end

local function ReadBrother(bb, add)
	local B = ns.Bags.Bagnon()
	local me = type(B) == "table" and type(B.player) == "table" and B.player or {}
	local realms = {}
	if me.realm then realms[me.realm] = true end
	local auto = GetAutoCompleteRealms and { Safe(GetAutoCompleteRealms) } or {}
	for _, r in ipairs(type(auto[1]) == "table" and auto[1] or auto) do if type(r) == "string" then realms[r] = true end end
	for realm, owners in pairs(bb) do
		if realm ~= "account" and type(owners) == "table" and (not next(realms) or realms[realm]) then
			for id, cache in pairs(owners) do
				local isGuild = type(id) == "string" and id:find("%*$")
				local mine = realm == me.realm and id == me.id
				if type(id) == "string" and type(cache) == "table" and not isGuild and not mine then
					local who = id
					if me.realm and realm ~= me.realm then who = who .. "-" .. realm end
					add({ key = "c:" .. realm .. "|" .. id, who = who, money = tonumber(cache.money) or 0, class = cache.class, kind = "alt" })
				end
			end
		end
	end
	local w = LiveWarband()
	if w and w > 0 then add({ key = "warband", who = "Warband bank", money = w, kind = "warband" }) end
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local ICONS = {
	me = "Interface\\Icons\\INV_Misc_Coin_01", alt = "Interface\\Icons\\INV_Misc_Coin_03",
	guild = "Interface\\Icons\\INV_Shirt_GuildTabard_01", warband = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
	total = "Interface\\Icons\\INV_Misc_Coin_02",
}

local list -- the rows of the last collect (the total row's tooltip and Enter list them)

local function Label(e) return e.goldKind == "total" and "All gold" or e.who end

--- What's sent: "All gold: 1,234g 5s 6c", "Plamen Warr: 12g".
local function ShareText(e) return Label(e) .. ": " .. G.Text(e.money, true) end

local function Lines()
	local out = {}
	for _, e in ipairs(list or {}) do
		local k = e.goldKind
		out[#out + 1] = (k == "total" and "All gold" or ("  " .. (e.color or "") .. e.who .. (e.color and "|r" or "")))
			.. (k == "me" and " (you)" or "") .. ":  " .. G.Text(e.money)
	end
	return out
end

local function PrintAll() ns:Output(Lines()) end
local function ToChatBox(e) ns.LinkInChat(ShareText(e)) end
local CHATBOX = ns.ChatBoxSpec(ShareText)

local function Tooltip(e, t)
	t:SetText(Label(e), 1, 0.82, 0)
	if e.goldKind == "total" then
		for _, r in ipairs(list or {}) do
			local k = r.goldKind
			if k ~= "total" then
				local cc = r.color or (k == "guild" and "|cff40ff40") or (k == "warband" and "|cff8ab8ff") or "|cffffffff"
				t:AddDoubleLine(cc .. r.who .. "|r" .. (k == "me" and " |cff9d9d9d(you)|r" or ""), G.Text(r.money), 1, 1, 1, 1, 1, 1)
			end
		end
		t:AddLine(" ")
	else
		t:AddLine(G.Text(e.money), 1, 1, 1)
	end
	t:AddLine("Enter: every row in chat    Shift+Enter: put it in the chat box", 0.6, 0.6, 0.6, true)
end

local WORDS = { me = "you me mine my", alt = "alt alts character", guild = "guild bank", warband = "warband bank account", total = "all total everyone alts" }

local function Row(h)
	local e = {
		key = h.key, name = h.who, who = h.who, money = h.money, goldKind = h.kind,
		color = ns.ClassHex(h.class),
		icon = ICONS[h.kind],
		detail = G.Text(h.money) .. (h.kind == "me" and "  |cff9d9d9d(you)|r" or ""),
		text = "gold money " .. WORDS[h.kind],
		tooltip = Tooltip,
		activate = PrintAll,
		secondary = ToChatBox, -- (combat: Terminal's own)
		secondarySecure = CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen, -- the game opens the chat box with it
		shareLink = ShareText,
	}
	return e
end

function G.Collect()
	local holders = {}
	local function add(h) holders[#holders + 1] = h end
	local me = Num(Safe(GetMoney)) or 0
	add({ key = "me", who = ns.CharacterName() or (Str(Safe(UnitName, "player"))) or "You", money = me,
		class = Str(select(2, Safe(UnitClass, "player"))), kind = "me" })
	local St = ns.Stored
	local src = St and St.Source()
	G.source = nil
	if src == "Syndicator" then
		local A = St.SyndicatorAPI()
		if A and St.SyndicatorReady(A) then G.source = src; ReadSyndicator(A, add, me) end
	elseif src == "BagBrother" then
		local bb = St.BrotherBags()
		if bb then G.source = src; ReadBrother(bb, add) end
	else
		local w = LiveWarband()
		if w and w > 0 then add({ key = "warband", who = "Warband bank", money = w, kind = "warband" }) end
	end
	-- the richest first, you always first among the characters; the total on top when there's more than you
	table.sort(holders, function(a, b)
		if (a.kind == "me") ~= (b.kind == "me") then return a.kind == "me" end
		if a.money ~= b.money then return a.money > b.money end
		return a.who < b.who
	end)
	local rows, total, n = {}, 0, #holders
	for i, h in ipairs(holders) do
		local e = Row(h)
		e._rank = (n - i + 1) / (n + 1) * 0.5 -- (keeps this order among equally good matches)
		rows[#rows + 1] = e
		total = total + h.money
	end
	if n > 1 then
		local chars = 0
		for _, h in ipairs(holders) do if h.kind == "me" or h.kind == "alt" then chars = chars + 1 end end
		local t = Row({ key = "total", who = "All gold", money = total, kind = "total" })
		t.detail = G.Text(total) .. "  |cff9d9d9d" .. chars .. (chars == 1 and " character" or " characters") .. "|r"
		t._rank = 1
		table.insert(rows, 1, t)
	end
	list = rows
	return rows
end

ns:RegisterProvider("gold", {
	label = "Gold",
	color = "fff0c020", -- (coin gold, apart from the quests' yellow)
	aliases = { "gold", "money", "coins", "wealth" },
	busy = function()
		local St = ns.Stored
		if St and St.Source() == "Syndicator" then
			local A = St.SyndicatorAPI()
			if A and not St.SyndicatorReady(A) then return "Waiting for Syndicator to finish reading your characters" end
		end
	end,
	events = { "PLAYER_MONEY", "ACCOUNT_MONEY", "GUILDBANK_UPDATE_MONEY", "PLAYER_ENTERING_WORLD" },
	guard = 1,
	collect = function() return G.Collect() end,
})
