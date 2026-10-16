-- (Terminal Extras, a load-on-demand addon of its own: Terminal's namespace is its public table, _G.Terminal)
local ns = _G.Terminal
if not ns then return end
local L = ns.L

-- What the games (.snake, .tetris, .lootrun) and the typing test share: opening (not in combat), the best score kept,
-- telling your guild once, the game-over keys and footer, their commands as the stand-ins name them. One copy each (review,
-- 0.53.6: three or four copies of each, which had started to drift: Tetris never cleared "a new best" on a game that
-- wasn't one).

local Panel = ns.Panel
local G = {}
ns.Game = G

--- A game may open: not in combat (it couldn't choose which keys to keep). `name`: the game's name, said if not.
function G.CanOpen(name)
	return Panel.CanOpen(L["%s takes over keys, which the game doesn't allow in combat."]:format(name))
end

--- Opens an app's window (Build once, then Style), straight in: the terminal and the other panels go; then a new game.
--- False in combat.
function G.Open(app, name, Build, Style)
	if not G.CanOpen(name) then return false end
	Build()
	Style()
	Panel.Opening(app)
	app.Reset()
	app.frame:Show()
	app.Draw()
	return true
end

--- The game's score against the best kept under db[key]: kept when it's higher, and game.newBest says whether it was.
function G.KeepBest(game, key)
	local db = ns.db
	local best = db and tonumber(db[key]) or 0
	game.newBest = db ~= nil and (game.score or 0) > best
	if game.newBest then db[key] = game.score end
end

--- Enter on the game-over screen: the guild is told the score, once (nothing to tell at 0).
function G.TellGuild(game, brag)
	if not game.over or (game.score or 0) <= 0 then return false end
	return ns.Extras.TellGuildOnce(game, brag)
end

G.BRAG = L["Enter tell your guild"]
G.BRAGGED = L["Your guild heard it"]

--- The game-over screen's keys, as the typing test's: Enter tells your guild (a score worth telling; once), Tab plays
--- again, Esc quits.
function G.OverKeys(score, sent)
	local brag = (score or 0) > 0 and ((sent and G.BRAGGED or G.BRAG) .. "  ·  ") or ""
	return brag .. Panel.AGAIN .. "  ·  " .. Panel.QUIT
end

--- A key on the game-over screen: Tab plays again; Enter (when `fresh` isn't false) tells your guild and closes, so the
--- chat shows it. True when it was one of those.
function G.OverKey(app, game, key, fresh)
	if key == "TAB" then
		app.Reset()
		app.Draw()
		return true
	end
	if (key == "ENTER" or key == "NUMPADENTER") and fresh ~= false then
		if (game.score or 0) > 0 then app.TellGuild(); app.Close() end
		return true
	end
	return false
end

--- The footer saying the keys, cut short at the frame's right edge (or `rightOf`'s left) in a longer language.
function G.Footer(frame, text, rightOf)
	local footer = Panel.Footer(frame, 9, text or "")
	if rightOf then footer:SetPoint("RIGHT", rightOf, "LEFT", -8, 0)
	else footer:SetPoint("RIGHT", frame, "RIGHT", -12, 0) end
	return footer
end

--- Registers the real command in the stand-in's place, with the stand-in's description and other names (Apps/Extras.lua's
--- X.COMMANDS: written once). `complete`: its own, else the stand-in's.
function G.Command(name, run, complete)
	for _, c in ipairs(ns.Extras.COMMANDS) do
		if c[1] == name then
			ns:RegisterCommand(name, { desc = c[2], aliases = c[3], complete = complete or c[4], run = run })
			return
		end
	end
end
