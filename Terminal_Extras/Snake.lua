-- (Terminal Extras, a load-on-demand addon of its own: Terminal's namespace is its public table, _G.Terminal)
local ns = _G.Terminal
if not ns then return end
local L = ns.L

-- .snake: Snake, in a small window where the terminal sits. WASD or the arrow keys steer; after a game
-- over, as the typing test, the footer says the keys: Enter tells your guild the score and closes (the interface back:
-- .zen ends; the player's ask), Tab plays again; Esc or ` quits. No pausing (it's for fun; Space stays the game's). Only the game's keys are taken: any
-- other key still reaches the game (your action bars, chat...). The best score is kept.
--
-- Choosing which keys pass on (SetPropagateKeyboardInput) isn't allowed in combat, so the game
-- doesn't start in combat and closes when combat starts.

local S = {}
ns.Snake = S

local Theme = ns.Theme
local Panel = ns.Panel
local COLS, ROWS, CELL = 20, 15, 16
local START_SPEED, MAX_SPEED, SPEED_UP = 7, 16, 0.35 -- moves a second; faster with every apple
local DIRS = {
	W = { 0, -1 }, UP = { 0, -1 }, S = { 0, 1 }, DOWN = { 0, 1 },
	A = { -1, 0 }, LEFT = { -1, 0 }, D = { 1, 0 }, RIGHT = { 1, 0 },
}

local frame, board, scoreText, bestText, overlay, overlaySub, footer
local food
local game = {}

S.rand = function(n) return math.random(n) end -- (tests replace it)

local function Key(x, y) return y * 100 + x end

-- runs only while a game is on: game over takes it off (nothing moves then), Reset puts it back
local function OnUpdate(_, elapsed) S.Tick(elapsed) end

----------------------------------------------------------------------
-- The game
----------------------------------------------------------------------

local function PlaceFood()
	local free = {}
	local taken = {}
	for _, c in ipairs(game.body) do taken[Key(c[1], c[2])] = true end
	for y = 0, ROWS - 1 do
		for x = 0, COLS - 1 do
			if not taken[Key(x, y)] then free[#free + 1] = { x, y } end
		end
	end
	game.food = #free > 0 and free[S.rand(#free)] or nil
end

function S.Reset()
	local y = math.floor(ROWS / 2)
	game.body = { { 6, y }, { 5, y }, { 4, y } } -- head first, moving right
	game.dir, game.queue = { 1, 0 }, {}
	game.score, game.speed, game.acc = 0, START_SPEED, 0
	game.over, game.won, game.sent = false, false, false
	PlaceFood()
	if frame then frame:SetScript("OnUpdate", OnUpdate) end
end

--- Turn (taken on the next move; two quick presses are both kept, so a fast U-turn works,
--- but never straight back into yourself).
function S.Turn(dx, dy)
	local last = game.queue[#game.queue] or game.dir
	if (dx == -last[1] and dy == -last[2]) or (dx == last[1] and dy == last[2]) then return end
	if #game.queue < 2 then game.queue[#game.queue + 1] = { dx, dy } end
end

--- One move: the head goes ahead; an apple makes the snake longer, a wall or the tail ends it.
function S.Step()
	if game.over then return end
	if #game.queue > 0 then game.dir = table.remove(game.queue, 1) end
	local head = game.body[1]
	local nx, ny = head[1] + game.dir[1], head[2] + game.dir[2]
	local eating = game.food and nx == game.food[1] and ny == game.food[2]
	if nx < 0 or ny < 0 or nx >= COLS or ny >= ROWS then return S.GameOver("wall") end
	for i = 1, #game.body - (eating and 0 or 1) do -- (the tail's last cell moves out of the way)
		local c = game.body[i]
		if c[1] == nx and c[2] == ny then return S.GameOver("tail") end
	end
	table.insert(game.body, 1, { nx, ny })
	if eating then
		game.score = game.score + 1
		game.speed = math.min(MAX_SPEED, game.speed + SPEED_UP)
		PlaceFood()
		if not game.food then game.won = true; return S.GameOver("won") end
	else
		table.remove(game.body)
	end
end

function S.GameOver(why)
	game.over, game.why = true, why
	if frame then frame:SetScript("OnUpdate", nil) end -- (nothing moves on the game-over screen)
	ns.Game.KeepBest(game, "snakeBest")
end

S.game = game

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

-- each body cell's texture, placed once when the cell is new: a move adds a head and drops a tail, so only those two are
-- placed and shown (every segment was placed again on every move, up to 16 a second; review, 0.53.6)
local placed, spare = {}, {} -- cell -> its texture; textures of cells gone, for the next new ones
S.placed = placed -- (tests)

local function NewSeg()
	local t = table.remove(spare)
	if t then return t end
	t = board:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(1, 1, 1, 1)
	t:SetSize(CELL - 2, CELL - 2)
	return t
end

local function Place(t, x, y)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", board, "TOPLEFT", x * CELL + 1, -y * CELL - 1)
end

function S.Draw()
	if not frame then return end
	local t = Theme.Get()
	local ar, ag, ab = Theme.RGB(t.accent)
	local tr, tg, tb = Theme.RGB(t.text)
	local live = {}
	for i, c in ipairs(game.body) do
		local seg = placed[c]
		if not seg then
			seg = NewSeg()
			Place(seg, c[1], c[2])
			seg:Show()
			placed[c] = seg
		end
		live[c] = true
		if i == 1 then
			seg:SetVertexColor(ar, ag, ab, 1)
		else
			local fade = 1 - 0.5 * (i - 1) / math.max(1, #game.body) -- (the tail fades a little)
			seg:SetVertexColor(tr, tg, tb, fade)
		end
	end
	for c, seg in pairs(placed) do
		if not live[c] then
			seg:Hide()
			placed[c] = nil
			spare[#spare + 1] = seg
		end
	end
	if game.food then
		Place(food, game.food[1], game.food[2])
		food:Show()
	else
		food:Hide()
	end
	scoreText:SetText(("|cff%s%s|r   %s"):format(t.accent, L["snake"], L["score %d"]:format(game.score)))
	bestText:SetText(L["best %d"]:format(math.max(ns.db and ns.db.snakeBest or 0, game.score)))
	if game.over then
		overlay:SetText(game.won and L["you filled the board!"] or (game.newBest and L["new best!"] or L["game over"]))
		overlaySub:SetText(L["score %d"]:format(game.score))
		overlay:Show(); overlaySub:Show()
	else
		overlay:Hide(); overlaySub:Hide()
	end
	-- the keys in the footer: the game's while playing, the game-over ones after (as the typing test's)
	footer:SetText(game.over and ns.Game.OverKeys(game.score, game.sent) or S.PLAY_KEYS)
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local Text = Panel.Text

local function Build()
	if frame then return end
	frame = Panel.Build("TerminalSnake", S)
	frame:SetSize(COLS * CELL + 24, ROWS * CELL + 64)
	frame:SetScript("OnKeyDown", function(self, key) S.KeyDown(self, key) end)

	scoreText, bestText = Panel.Header(frame)

	board = Panel.Board(frame)
	board:SetSize(COLS * CELL, ROWS * CELL)
	board:SetPoint("TOP", 0, -32)
	food = board:CreateTexture(nil, "ARTWORK")
	food:SetColorTexture(1, 0.37, 0.37, 1)
	food:SetSize(CELL - 4, CELL - 4)

	overlay = Text(board, 16, "CENTER")
	overlay:SetPoint("CENTER", 0, 10)
	overlaySub = Text(board, 11, "CENTER")
	overlaySub:SetPoint("CENTER", 0, -12)
	S.PLAY_KEYS = L["WASD or arrows steer"] .. "  ·  " .. Panel.QUIT
	footer = ns.Game.Footer(frame)
	S.frame, S.footer = frame, footer
end

local function Style()
	local t = Panel.Layout(frame) -- (its size is the board's, set once)
	Panel.StyleBoard(board, t)
	local tr, tg, tb = Theme.RGB(t.text)
	local dr, dg, db = Theme.RGB(t.dim)
	scoreText:SetTextColor(tr, tg, tb)
	bestText:SetTextColor(dr, dg, db)
	overlay:SetTextColor(tr, tg, tb)
	overlaySub:SetTextColor(dr, dg, db)
	footer:SetTextColor(dr, dg, db)
end

--- What the guild is told: "[Terminal] Snake: 23 points (a new best)." (a new best only when it is one: filling the
--- board again ties the best; review, 0.49.17)
function S.Brag()
	return L["[Terminal] Snake: %d points%s."]
		:format(game.score, game.newBest and (" " .. L["(a new best)"]) or "")
end

--- Enter on the game-over screen: the guild is told the score, once (nothing to tell at 0); KeyDown then closes.
function S.TellGuild() return ns.Game.TellGuild(game, S.Brag()) end

--- The game's keys are kept; any other key goes on to the game.
function S.KeyDown(self, key)
	local mine = true
	if key == "ESCAPE" or key == "`" then
		S.Close()
	elseif game.over and ns.Game.OverKey(S, game, key) then
		-- (game over: Enter tells your guild and closes, so the chat shows it; Tab plays again)
	elseif DIRS[key] then
		if not game.over then S.Turn(DIRS[key][1], DIRS[key][2]) end
	else
		mine = false
	end
	Panel.Propagate(self, mine)
end

function S.Tick(elapsed)
	if game.over then return end
	-- a long frame (alt-tab, a loading hitch) mustn't make many moves at once, into a wall unseen
	game.acc = (game.acc or 0) + math.min(elapsed or 0, 0.2)
	local every = 1 / game.speed
	local moved = false
	while game.acc >= every and not game.over do
		game.acc = game.acc - every
		S.Step()
		moved = true
	end
	if moved then S.Draw() end
end

function S.IsShown() return Panel.Shown(frame) end

function S.Open() return ns.Game.Open(S, L["Snake"], Build, Style) end

function S.Close(why)
	Panel.Close(frame, why, L["Snake"])
end

ns.Game.Command("snake", function() S.Open() end)
