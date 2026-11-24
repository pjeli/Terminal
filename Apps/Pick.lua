local ns = select(2, ...)
local L = ns.L

-- .pick (1.8.6, the player: "I like the .pick idea!"): someone from your group picked at random, "who's buying the
-- repairs", with a short roll of names on screen; or one of the things you list (.pick tacos, pizza, sushi). In a group
-- the pick is said in the group's chat (party, raid, or instance chat when the group is the instance's), sent inside the
-- Enter that ran it as Share's >>> sends; .pick quiet keeps it to you.

local PK = {}
ns.Pick = PK

local Str, Safe = ns.Str, ns.Safe

PK.random = function(n) return math.random(n) end -- (tests: a fixed one)
PK.FLIPS, PK.FIRST, PK.GROW, PK.HOLD = 14, 0.04, 1.18, 3 -- (names rolled, the first one's time, each next one's longer, the pick shown)

--- Your group's names (you included), or nil when you're in none.
function PK.GroupNames()
	local GR = ns.Group
	if not (GR and GR.Units and GR.NameOf) then return nil end
	if not (Safe(_G.IsInGroup) == true) then return nil end
	local out = {}
	for _, u in ipairs(GR.Units()) do
		local n = u == "player" and ns.CharacterName() or GR.NameOf(u)
		if n then out[#out + 1] = n end
	end
	return #out > 1 and out or nil
end

--- What .pick's words list: "tacos, pizza, sushi" (commas: each part), else "bob alice eve" (each word). Nil: none.
function PK.Listed(args)
	args = tostring(args or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if args == "" then return nil end
	local out = {}
	if args:find(",", 1, true) then
		for part in (args .. ","):gmatch("([^,]*),") do
			part = part:gsub("^%s+", ""):gsub("%s+$", "")
			if part ~= "" then out[#out + 1] = part end
		end
	else
		for w in args:gmatch("%S+") do out[#out + 1] = w end
	end
	return #out > 0 and out or nil
end

--- The group's chat now (party, raid, or instance chat), or nil when you're in no group.
function PK.Chat()
	if Safe(_G.IsInRaid) == true then return ns.Share and ns.Share.ChatType and ns.Share.ChatType("RAID") or "RAID" end
	if Safe(_G.IsInGroup) == true then return ns.Share and ns.Share.ChatType and ns.Share.ChatType("PARTY") or "PARTY" end
	return nil
end

----------------------------------------------------------------------
-- The roll on screen: names flicked through, slower and slower, landing on the pick (Terminal's own frame, timers,
-- nothing every frame)
----------------------------------------------------------------------

local frame
local function Frame()
	if frame then return frame end
	frame = CreateFrame("Frame", "TerminalPickFrame", UIParent)
	if ns.Zen then ns.Zen.Made(frame) end -- (made while .zen has the interface faded: kept up)
	frame:SetFrameStrata("HIGH")
	frame:SetSize(600, 80)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
	frame:EnableMouse(false)
	frame.name = frame:CreateFontString(nil, "OVERLAY")
	frame.name:SetFontObject(_G.GameFontNormalHuge or (ns.Theme and ns.Theme.fonts and ns.Theme.fonts.input))
	frame.name:SetPoint("CENTER", 0, 10)
	frame.sub = frame:CreateFontString(nil, "OVERLAY")
	frame.sub:SetFontObject(_G.GameFontHighlight or (ns.Theme and ns.Theme.fonts and ns.Theme.fonts.small))
	frame.sub:SetPoint("TOP", frame.name, "BOTTOM", 0, -6)
	frame:Hide()
	return frame
end
PK.Frame = function() return frame end -- (tests)

local rollGen = 0
--- Roll `names` on screen, landing on `pick`.
function PK.Roll(names, pick, of)
	local f = Frame()
	rollGen = rollGen + 1
	local gen = rollGen
	f:SetAlpha(1)
	f.sub:SetText(L["picking..."])
	f:Show()
	local flips, wait, last = PK.FLIPS, PK.FIRST, nil
	local function Step(i)
		if gen ~= rollGen then return end -- (another .pick took over)
		if i > flips then
			f.name:SetText("|cffffd200" .. pick .. "|r")
			f.sub:SetText(L["picked, out of %d"]:format(of))
			if _G.PlaySound and _G.SOUNDKIT and _G.SOUNDKIT.READY_CHECK then pcall(_G.PlaySound, _G.SOUNDKIT.READY_CHECK) end
			C_Timer.After(PK.HOLD, function() if gen == rollGen then f:Hide() end end)
			return
		end
		-- (any name but the one shown last: a flick you can see)
		local n = names[PK.random(#names)]
		if #names > 1 then
			local tries = 0
			while n == last and tries < 5 do n = names[PK.random(#names)]; tries = tries + 1 end
		end
		last = n
		f.name:SetText(n)
		C_Timer.After(wait, function() Step(i + 1) end)
		wait = wait * PK.GROW
	end
	Step(1)
end

--- .pick: who or what was picked and where it was said; lines for the chat (only to you), nil when said in the group.
function PK.Run(args)
	local words = tostring(args or "")
	local quiet = false
	local first = ns.Lower(words:match("^%s*(%S*)") or "")
	if first == "quiet" or first == "me" then quiet, words = true, words:gsub("^%s*%S+%s*", "") end
	local names = PK.Listed(words) or PK.GroupNames()
	if not names then
		return { L["Not in a group: .pick picks someone of your group; .pick tacos, pizza, sushi picks one of those."] }
	end
	if #names == 1 then return { L["Only one to pick from: %s."]:format(names[1]) } end
	local pick = names[PK.random(#names)]
	local said = L["Terminal picks %s (of %d)"]:format(pick, #names)
	local chat = not quiet and PK.Chat()
	PK.Roll(names, pick, #names)
	if chat then
		local send = ns.ChatSender and ns.ChatSender()
		if ns.ChatLocked and ns.ChatLocked() then
			ns:Print(said .. "  " .. L["(the game doesn't let addons send chat right now)"])
		elseif send then
			local ok = pcall(send, said, chat)
			if not ok then ns:Print(said) end
		end
		return nil
	end
	ns:Print(said)
	return nil
end

ns:RegisterCommand("pick", {
	desc = L["Pick someone of your group at random, said in its chat (.pick quiet: only you see it); .pick tacos, pizza, sushi picks one of those"],
	aliases = { "random", "choose" },
	complete = function() return { { "quiet", L["only you see the pick"] } } end,
	run = function(args) return PK.Run(args) end,
})
