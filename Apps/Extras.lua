local ns = select(2, ...)

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
	{ "snake", "Play Snake (WASD or arrows steer, Esc or ` quits)" },
	{ "tetris", "Play Tetris (arrows or WASD move and turn, Enter drops, C holds, Esc or ` quits)" },
	{ "lootrun", "Play Loot Run, a maze chase (WASD or arrows move, Esc or ` quits)", { "maze" } },
	{ "typing", "A typing speed test (Tab: 15 / 30 / 60 s; Enter afterwards tells your guild; Esc quits)", { "wpm", "typetest" } },
	{ "wowamp", "WoWamp: radio stations playing the game's music (.wowamp stop, next, or a station)", { "radio", "amp" } },
}

local function Call(f, ...)
	if type(f) ~= "function" then return nil end
	local ok, a, b = pcall(f, ...)
	if ok then return a, b end
	return nil
end

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
		ns:Print("Terminal Extras (the games and the radio) is switched off in your AddOn list: switch it on to play.")
	elseif reason == "MISSING" then
		ns:Print("Terminal Extras (the games and the radio) isn't installed: it comes with Terminal, in its own folder"
			.. " (Terminal_Extras). Restart the game after updating.")
	else
		ns:Print("Terminal Extras couldn't be loaded" .. (reason and (" (" .. tostring(reason) .. ")") or "") .. ".")
	end
	return false
end

-- a stand-in: loads the extras, then runs the real command they registered in its place
local stubs = {}
local function StubRun(name, args)
	if not X.Load() then return nil end
	local real = ns.commands[name]
	if not real or real == stubs[name] then
		ns:Print("Terminal Extras loaded, but ." .. name .. " isn't in it: restart the game after updating.")
		return nil
	end
	return real.run(args)
end

for _, c in ipairs(X.COMMANDS) do
	local name = c[1]
	local def = { desc = c[2], aliases = c[3], run = function(args) return StubRun(name, args) end }
	stubs[name] = def
	ns:RegisterCommand(name, def)
end
X.stubs = stubs -- (tests)

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
