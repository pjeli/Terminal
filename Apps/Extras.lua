local ns = select(2, ...)
local L = ns.L

-- Terminal Extras: the games and the radio (.snake, .tetris, .lootrun, .typing, .wowamp) live in an addon of their own
-- that comes with Terminal (the Terminal_Extras folder: ## LoadOnDemand, ## Dependencies: Terminal), loaded the first
-- time one is asked for, so Terminal alone doesn't carry them (0.47.8, the player's ask). Their commands are here as
-- stand-ins with the same names, words and descriptions: running one loads the extras (C_AddOns.LoadAddOn), whose own
-- files register the real commands in their place (RegisterCommand replaces a name), and runs that.
--
-- WoWamp switches the zone music off while it plays and back on when it stops; after a /reload or a login the radio isn't
-- playing (and the extras aren't loaded), so the music is put back here (it was the radio's own PLAYER_LOGIN before).

local X = {}
ns.Extras = X

X.ADDON = "Terminal_Extras"
X.COMMANDS = {
	{ "snake", L["Play Snake (WASD or arrows steer; afterwards Enter tells your guild, Tab plays again; Esc or ` quits)"] },
	{ "tetris", L["Play Tetris (arrows or WASD move and turn, Enter drops, C holds; afterwards Enter tells your guild, Tab plays again; Esc or ` quits)"] },
	{ "lootrun", L["Play Loot Run, a maze chase (WASD or arrows move; afterwards Enter tells your guild, Tab plays again; Esc or ` quits)"], { "maze" } },
	{ "typing", L["A typing speed test (Tab: 15 / 30 / 60 s; Enter afterwards tells your guild; Esc or ` quits)"], { "wpm", "typetest" } },
	{ "wowamp", L["WoWamp: radio stations playing the game's music (.wowamp stop, next, or a station)"], { "radio", "amp" },
		-- (what it takes before the extras are loaded: its stations come with them; review, 0.48.6)
		function() return { { "stop", L["stop the radio"] }, { "next", L["skip this track"] } } end },
}

----------------------------------------------------------------------
-- Telling your guild a score (the typing test since 0.48.x; the games since 0.49.3, the player's ask: "cheeky
-- advertising"): sent from Terminal's code inside your key press (guild chat isn't held back for addons, as Share's party
-- and guild lines aren't), once per game, with a [Terminal] banner.
----------------------------------------------------------------------

-- (the keys are the typing test's on every game-over screen: Enter tells your guild, Tab plays again; the player's ask)

--- Says `text` in guild chat. True when it went out; false, with a line saying why, when it can't.
function X.TellGuild(text)
	if type(text) ~= "string" or text == "" then return false end
	if _G.IsInGuild and not _G.IsInGuild() then ns:Print(L["You're not in a guild: nobody to tell."]) return false end
	if ns.ChatLocked() then ns:Print(L["Chat is held back right now: tell your guild later."]) return false end
	local send = ns.ChatSender()
	if not send then return false end
	local ok = pcall(send, text, "GUILD")
	ns:Trace("extras: told the guild: " .. tostring(ok))
	return ok
end

--- Once per game: `state.sent` remembers it (a game's Reset clears it). True when it went out now.
function X.TellGuildOnce(state, text)
	if state.sent then ns:Print(L["Your guild has heard this one."]) return false end
	state.sent = X.TellGuild(text) and true or false
	return state.sent
end

local Call = ns.Safe

--- Whether the extras are loaded now.
function X.Loaded()
	local AO = C_AddOns
	return (Call(AO and AO.IsAddOnLoaded or _G.IsAddOnLoaded, X.ADDON)) == true
end

--- Loads the extras (once). True when they're in; false, and a line saying why, when the game won't load them.
function X.Load()
	if X.Loaded() then return true end
	local AO = C_AddOns
	local loaded, reason = Call(AO and AO.LoadAddOn or _G.LoadAddOn, X.ADDON)
	ns:Trace("extras: loading " .. X.ADDON .. ": " .. tostring(loaded) .. (reason and (" (" .. tostring(reason) .. ")") or ""))
	if loaded then return true end
	if reason == "DISABLED" then
		ns:Print(L["Terminal Extras (the games and the radio) is switched off in your AddOn list: switch it on to play."])
	elseif reason == "MISSING" then
		ns:Print(L["Terminal Extras (the games and the radio) isn't installed: it comes with Terminal, in its own folder (Terminal_Extras). Restart the game after updating."])
	else
		ns:Print(reason and L["Terminal Extras couldn't be loaded (%s)."]:format(tostring(reason)) or L["Terminal Extras couldn't be loaded."])
	end
	return false
end

-- a stand-in: loads the extras, then runs the real command they registered in its place
local stubs = {}
local function StubRun(name, args)
	if not X.Load() then return nil end
	local real = ns.commands[name]
	if not real or real == stubs[name] then
		ns:Print(L["Terminal Extras loaded, but .%s isn't in it: restart the game after updating."]:format(name))
		return nil
	end
	return real.run(args)
end

for _, c in ipairs(X.COMMANDS) do
	local name = c[1]
	local def = { desc = c[2], aliases = c[3], complete = c[4], run = function(args) return StubRun(name, args) end }
	stubs[name] = def
	ns:RegisterCommand(name, def)
end
X.stubs = stubs -- (tests)

----------------------------------------------------------------------
-- Lore books for the typing test (Typing.lua draws its words from them, and says at the end which book it was)
----------------------------------------------------------------------

-- Every book, plaque and note you read in the game (the item text window: a book on a shelf, a tablet, a letter you
-- find), kept by its title in db.lore, page by page as you turn them (pages never read aren't known: Terminal doesn't turn
-- them for you). Kept here, always loaded, as the extras aren't loaded until a game is played. A letter a player wrote
-- (the window names a creator: your mail) isn't kept. The game sends the text: Terminal ships none of it.
X.LORE_BOOKS = 300 -- (books kept at most: the least recently read go first)
X.LORE_PAGES = 40 -- (pages kept per book)
X.LORE_CHARS = 4000 -- (characters kept per page)
X.LORE_MIN = 20 -- (a page shorter than this, cleaned, isn't kept: a sign, a blank page)

local Safe, Str, Num = ns.Safe, ns.Str, ns.Num

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'", nbsp = " " }

--- A page's words as read: no markup (the window's HTML, colour codes, textures, links' brackets kept as their text),
--- the game's $-codes (a line break, your name) and runs of spaces taken out.
function X.CleanLore(text)
	if type(text) ~= "string" or text == "" then return nil end
	local s = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " "):gsub("|T.-|t", " ")
		:gsub("|H.-|h(.-)|h", "%1"):gsub("||", "|")
	s = s:gsub("<[^>]*>", " "):gsub("&(%a+);", function(e) return ENTITIES[e:lower()] or " " end)
	s = s:gsub("%$%a", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	if #s < X.LORE_MIN then return nil end
	return s
end

local function Books()
	if not ns.db then return nil end
	if type(ns.db.lore) ~= "table" then ns.db.lore = {} end
	return ns.db.lore
end

--- The page the item text window shows now, kept under its book's title (nil when it isn't kept, and why).
function X.KeepPage()
	local books = Books()
	if not books then return nil, "no saved variables" end
	local creator = Str(Safe(_G.ItemTextGetCreator))
	if creator then return nil, "a letter a player wrote" end
	local title = X.loreTitle or Str(Safe(_G.ItemTextGetItem))
	if not title then return nil, "no title" end
	local text = X.CleanLore(Str(Safe(_G.ItemTextGetText)))
	if not text then return nil, "no words" end
	local page = math.max(1, Num(Safe(_G.ItemTextGetPage)) or 1)
	-- (past the pages kept: not kept; pages 41-50 each wrote over page 40. Review, 0.53.6)
	if page > X.LORE_PAGES then return nil, "past the pages kept" end
	local key = ns.Lower(title)
	local b = books[key]
	if type(b) ~= "table" or type(b.pages) ~= "table" then b = { title = title, pages = {} }; books[key] = b end
	b.pages[page] = text:sub(1, X.LORE_CHARS)
	b.t = (_G.time and _G.time()) or 0
	-- the least recently read go when there are too many
	local n, oldest, oldKey = 0, nil, nil
	for k, v in pairs(books) do
		n = n + 1
		local t = type(v) == "table" and tonumber(v.t) or 0
		if not oldest or t < oldest then oldest, oldKey = t, k end
	end
	if n > X.LORE_BOOKS and oldKey and oldKey ~= key then books[oldKey] = nil end
	ns:Trace(("lore: kept page %d of %s (%d characters)"):format(page, title, #text))
	return b
end

local loreFrame = CreateFrame("Frame")
for _, e in ipairs({ "ITEM_TEXT_BEGIN", "ITEM_TEXT_READY", "ITEM_TEXT_CLOSED" }) do pcall(loreFrame.RegisterEvent, loreFrame, e) end
loreFrame:SetScript("OnEvent", function(_, event)
	if event == "ITEM_TEXT_BEGIN" then
		X.loreTitle = Str(Safe(_G.ItemTextGetItem))
	elseif event == "ITEM_TEXT_READY" then
		pcall(X.KeepPage)
	else
		X.loreTitle = nil
	end
end)
X.loreFrame = loreFrame -- (tests)

-- the zone music back after a /reload or a login if the radio had switched it off (WoWamp's db.wowamp.musicWasOn)
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
	local w = ns.db and ns.db.wowamp
	if type(w) == "table" and w.musicWasOn and not (ns.Wowamp and ns.Wowamp.Playing and ns.Wowamp.Playing()) then
		local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
		if set then pcall(set, "Sound_EnableMusic", "1") end
		w.musicWasOn = nil
	end
end)
X.loginFrame = login -- (tests)
