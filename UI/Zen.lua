local ns = select(2, ...)

-- .zen: hides the game's menu and bag buttons, the XP bar and the quest tracker (the action bars and the minimap stay)
-- to see how far Terminal alone can drive the game. Windows still open from Terminal: the bars are only
-- made invisible (alpha 0), never hidden or moved, so key bindings, the micro buttons Terminal clicks and everything
-- secure keep working exactly as before. Unit frames, chat, the cast bar and buffs stay. .zen again brings it back;
-- it's remembered across sessions.
--
-- Alpha isn't protected (it changes in combat too) and nothing of Blizzard's Lua is called: only SetAlpha on the
-- frames, and a hooksecurefunc on each one's SetAlpha so a bar the game fades back in goes out again.

local Z = {}
ns.Zen = Z

-- what goes (only the names this client has are touched)
Z.FRAMES = {
	"MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar", "BagsBar", "StatusTrackingBarManager",
	"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "ObjectiveTrackerFrame", "QuestWatchFrame",
	"WatchFrame",
}
-- (kept up, the player's call in 0.43.20: the action bars and the minimap. Never put them here: MainActionBar,
-- MainMenuBar (the action bar itself on classic layouts), MultiBar*, Stance/Pet/Possess bars, MinimapCluster)
Z.KEEP = { "MainActionBar", "MainMenuBar", "MainMenuBarArtFrame", "MultiBarBottomLeft", "MultiBarBottomRight",
	"MultiBarRight", "MultiBarLeft", "StanceBar", "PetActionBar", "MinimapCluster", "Minimap" }

local saved = {} -- frame -> its alpha before
local hooked = {}
local busy = false -- (our own SetAlpha inside the hook)

local function On() return ns.db and ns.db.zen == true end

local function Fade(f)
	if busy or not On() or saved[f] == nil then return end
	local ok, a = pcall(f.GetAlpha, f)
	if ok and a == 0 then return end
	busy = true
	pcall(f.SetAlpha, f, 0)
	busy = false
end

--- The frames this client has, by name.
function Z.Frames()
	local out = {}
	for _, name in ipairs(Z.FRAMES) do
		local f = _G[name]
		if type(f) == "table" and type(f.SetAlpha) == "function" then out[#out + 1] = f end
	end
	return out
end

--- Hide (alpha 0) or bring back every bar; returns how many frames it touched.
function Z.Apply()
	local n = 0
	if On() then
		for _, f in ipairs(Z.Frames()) do
			if saved[f] == nil then
				local ok, a = pcall(f.GetAlpha, f)
				saved[f] = ok and type(a) == "number" and a or 1
			end
			if not hooked[f] and type(hooksecurefunc) == "function" then
				hooked[f] = pcall(hooksecurefunc, f, "SetAlpha", Fade)
			end
			busy = true
			pcall(f.SetAlpha, f, 0)
			busy = false
			n = n + 1
		end
	else
		for f, a in pairs(saved) do
			busy = true
			pcall(f.SetAlpha, f, a) -- (as it was: a bar another addon kept invisible stays so)
			busy = false
			n = n + 1
		end
		saved = {}
	end
	ns:Trace(("zen: %s, %d frames"):format(On() and "on" or "off", n))
	return n
end

function Z.Set(on)
	if not ns.db then return 0 end
	ns.db.zen = on and true or false
	return Z.Apply()
end

ns:RegisterCommand("zen", {
	desc = "Hide the game's menu and bag buttons, XP bar and quest tracker (action bars and minimap stay) to play from Terminal; .zen again brings them back",
	aliases = { "hideui", "minimal" },
	complete = function() return { { "on", "hide the bars" }, { "off", "bring them back" } } end,
	run = function(args)
		local a = strtrim(args or ""):lower()
		local want
		if a == "on" then want = true elseif a == "off" then want = false else want = not On() end
		local n = Z.Set(want)
		if want then
			return { ("Zen: %d bars hidden (your action bars and minimap stay). Windows still open from Terminal, and your key bindings work as always. The bars are only invisible: hovering or clicking where they were still reaches them. .zen again brings them back."):format(n) }
		end
		return { "Zen off: the bars are back." }
	end,
})

-- remembered: hidden again after a loading screen or a reload (the game builds its bars by then), and once more a
-- moment later (Edit Mode places and fades them after it)
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "EDIT_MODE_LAYOUTS_UPDATED")
ev:SetScript("OnEvent", function()
	if not On() then return end
	Z.Apply()
	C_Timer.After(1, function() if On() then Z.Apply() end end)
end)
