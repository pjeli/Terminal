-- .zen's dimming takes the weather's colour (0.50.6, the player's ask): bluer in rain, paler in snow, warmer in a
-- sandstorm, as strong as the weather (C_Weather.GetCurrentWeather); weather turning while dimmed fades to the new one.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local Z = ns.Zen

local function Col() local c = Z.dim and Z.dim.tex.color return c and c[1] or -1, c and c[2] or -1, c and c[3] or -1 end
local function Near(r, g, b, er, eg, eb) return math.abs(r - er) + math.abs(g - eg) + math.abs(b - eb) < 1e-3 end
local function Tick(dt) local f = Z.tinter and Z.tinter.scripts.OnUpdate if f then f(Z.tinter, dt) end end
local function Show() return ("%.3f %.3f %.3f"):format(Col()) end

io.write("[zen: the weather's colour]\n")
do
	local save = { zen = ns.db.zen, cw = _G.C_Weather, indoors = _G.IsIndoors, combat = _G.InCombatLockdown, anim = ns.Theme.Animation,
		enum = _G.Enum and _G.Enum.WeatherType }
	local weather = { type = 1, intensity = 0.5 }
	_G.C_Weather = { GetCurrentWeather = function() return weather end }
	local inside = false
	_G.IsIndoors = function() return inside end
	_G.InCombatLockdown = function() return false end
	ns.Theme.Animation = function() return ns.Theme.ANIMATIONS.smooth end
	ns.db.zen = true
	local R, S, D = Z.TINTS.Rain, Z.TINTS.Snow, Z.TINTS.Sandstorm

	-- opened in the rain: the dimming blue from the start, as strong as the rain
	UI:Open()
	local r, g, b = Col()
	check(Z.active and Near(r, g, b, R[1] * 0.5, R[2] * 0.5, R[3] * 0.5) and b > r, "rain, half: bluer, half as strong: " .. Show())
	check(Z.dim.tex.color[4] == 1 and math.abs(Z.DIM - 0.55) < 1e-9, "still the same dimming (only its colour), subtle")
	-- the weather turns while it's open: faded to it, not at once
	weather = { type = 2, intensity = 1 }
	Z.OnEvent("WEATHER_CHANGED")
	check(Near(r, g, b, Col()), "snow comes: not at once")
	Tick(Z.TINT_FADE / 2)
	local r2, g2, b2 = Col()
	check(r2 > r and r2 < S[1] and g2 < S[2], "halfway to snow: " .. Show())
	Tick(Z.TINT_FADE)
	check(Near(S[1], S[2], S[3], Col()), "snow: paler: " .. Show())
	check(S[1] > R[1] and S[2] > R[2], "(paler than rain)")
	-- a sandstorm: warmer; a drizzle barely shows
	weather = { type = 3, intensity = 0.8 }
	Z.OnEvent("WEATHER_CHANGED"); Tick(Z.TINT_FADE + 0.1)
	r, g, b = Col()
	check(Near(r, g, b, D[1] * 0.8, D[2] * 0.8, D[3] * 0.8) and r > g and g > b, "sandstorm: warmer: " .. Show())
	weather = { type = 1, intensity = 0.1 }
	Z.OnEvent("WEATHER_CHANGED"); Tick(Z.TINT_FADE + 0.1)
	r, g, b = Col()
	check(r + g + b < 0.05, "a drizzle: barely there: " .. Show())
	-- indoors: no weather; looked at again without an event
	weather = { type = 1, intensity = 1 }
	inside = true
	Tick(Z.POLL + 0.01); Tick(Z.TINT_FADE + 0.1)
	check(Near(0, 0, 0, Col()), "indoors: plain black (found without an event): " .. Show())
	inside = false
	Tick(Z.POLL + 0.01); Tick(Z.TINT_FADE + 0.1)
	check(Near(R[1], R[2], R[3], Col()), "outside again: the rain's blue: " .. Show())
	-- the game's own enum, other weather, odd answers: black
	_G.Enum = _G.Enum or {}
	_G.Enum.WeatherType = { Clear = 0, Rain = 1, Snow = 2, Sandstorm = 3, Miscellaneous = 4 }
	for _, w in ipairs({ { type = 4, intensity = 1 }, { type = 0, intensity = 1 }, { type = 1, intensity = 0 / 0 }, {}, 7 }) do
		weather = w
		Tick(Z.POLL + 0.01); Tick(Z.TINT_FADE + 0.1)
		check(Near(0, 0, 0, Col()), "other weather, clear skies, nothing readable: black: " .. tostring(type(w) == "table" and w.type or w) .. " " .. Show())
	end
	weather = { type = 2, intensity = 3 }
	Tick(Z.POLL + 0.01); Tick(Z.TINT_FADE + 0.1)
	check(Near(S[1], S[2], S[3], Col()), "an intensity past 1: as strong as it gets: " .. Show())
	-- closed: nothing runs; opened again: the weather's colour now, at once
	Z.Leave(true)
	check(not Z.active and Z.tinter.scripts.OnUpdate == nil, "closed: nothing runs")
	UI:HideNow(); T.FlushAll()
	weather = { type = 3, intensity = 1 }
	UI:Open()
	check(Near(D[1], D[2], D[3], Col()), "opened again: the weather now, at once: " .. Show())
	Z.Leave(true); UI:HideNow(); T.FlushAll()
	-- no C_Weather (an older client): black, as before
	_G.C_Weather = nil
	UI:Open()
	check(Near(0, 0, 0, Col()), "no C_Weather: plain black: " .. Show())
	-- animations off: the new colour at once
	Z.Leave(true); UI:HideNow(); T.FlushAll()
	_G.C_Weather = { GetCurrentWeather = function() return weather end }
	weather = { type = 1, intensity = 1 }
	ns.Theme.Animation = function() return nil end
	UI:Open()
	weather = { type = 2, intensity = 1 }
	Z.OnEvent("WEATHER_CHANGED")
	check(Near(S[1], S[2], S[3], Col()), "animations off: at once: " .. Show())
	Z.Leave(true); UI:HideNow(); T.FlushAll()

	ns.db.zen, _G.C_Weather, _G.IsIndoors, _G.InCombatLockdown, ns.Theme.Animation = save.zen, save.cw, save.indoors, save.combat, save.anim
	_G.Enum.WeatherType = save.enum
end

-- (0.51.1, the player's ask) how dark .zen makes the screen: a setting (Options: Zen dimming; .set zenDim), live
io.write("[zen: how dark, a setting]\n")
do
	local Th, O = ns.Theme, ns.Options
	local save = { zen = ns.db.zen, combat = _G.InCombatLockdown, anim = Th.Animation, dim = Th.Get().zenDim }
	_G.InCombatLockdown = function() return false end
	Th.Animation = function() return nil end -- (at once)
	ns.db.zen = true
	check(Th.FIELDS.zenDim and Th.Get().zenDim == 0.55, "a setting, 0.55 (as it was) unless changed")
	check(O.widgets.zenDim ~= nil, "a slider in the Options panel")
	UI:Open()
	check(math.abs(Z.dim:GetAlpha() - 0.55) < 1e-6, "dimmed as before")
	local ok = Th.Set("zenDim", 0.3)
	check(ok and math.abs(Z.dim:GetAlpha() - 0.3) < 1e-6, "changed while dimmed: at once: " .. tostring(Z.dim:GetAlpha()))
	check(Th.Format("zenDim", 0.3) == "30%" and O.widgets.zenDim.valueText:GetText() == "30%", "shown as a percentage")
	check(select(2, Th.Set("zenDim", 5)) == 0.9 and Th.Set("zenDim", 0), "kept from 0 to 0.9")
	check(Z.dim:GetAlpha() == 0, "0: no dimming at all")
	Z.Leave(true); UI:HideNow(); T.FlushAll()
	Th.Set("zenDim", save.dim)
	ns.db.zen, _G.InCombatLockdown, Th.Animation = save.zen, save.combat, save.anim
end
