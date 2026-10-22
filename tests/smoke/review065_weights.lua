-- 0.65.x review (0.65.10): .weights set and Pawn scale strings' edge cases.
-- review B: .weights set / Pawn parsing edge cases
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local F = ns.Filters
local saveRoles, saveCustom = ns.db.upgradeRoles, ns.db.upgradeCustom
local ok, err = pcall(function()
	local weights = ns:FindCommand("weights")
	local function Run(a) return table.concat(weights.run(a, ns), "\n") end
	local function P(s) local w, bad = F.ParseWeights(s) local t = {} for k, v in pairs(w or {}) do t[#t + 1] = k .. "=" .. v end table.sort(t) return table.concat(t, " ") .. " | bad: " .. table.concat(bad, " ") end
	io.write("set 'str = 2 agi = 1': " .. P("str = 2 agi = 1") .. "\n")
	io.write("set 'str=1,5': " .. P("str=1,5") .. "\n")
	io.write("set 'str=2 str=3': " .. P("str=2 str=3") .. "\n")
	-- all zero
	ns.db.upgradeCustom, ns.db.upgradeRoles = nil, nil
	local out = Run("set str=0 agi=0")
	io.write("set str=0 agi=0 -> " .. out:gsub("\n.*", "") .. " | roles=" .. tostring(F.MyRoles() and F.MyRoles()[1]) .. "\n")
	local s = F.MyWeightSets()[1][1]
	io.write("scaled: str=" .. tostring(s.str) .. "\n")
	check(F.MyRoles() == nil, "all-zero weights accepted and picked as the role (nothing can ever be an upgrade): " .. out:gsub("\n.*", ""))
	-- negative only
	out = Run("set str=-1")
	s = F.MyWeightSets()[1][1]
	io.write("set str=-1 -> " .. out:gsub("\n.*", "") .. " scaled str=" .. tostring(s.str) .. "\n")
	-- Pawn: a retail-style string with Class/Spec numbers
	local w, name, ignored = F.ParsePawn('( Pawn: v1: "Warrior: Arms": Class=1, Spec=1, Strength=1.48, CritRating=0.9, HitRating=1.1 )')
	io.write("pawn ignored: " .. table.concat(ignored or {}, ", ") .. " name=" .. tostring(name) .. "\n")
	check(not (ignored and ignored[1] == "Class"), "Pawn: Class and Spec (not stats) said as stats 'not weighed here': " .. table.concat(ignored or {}, ", "))
	-- Pawn: unnamed
	out = Run('pawn ( Pawn: v1: "": Strength=1 )')
	io.write("unnamed pawn -> " .. out:gsub("\n.*", "") .. "\n")
	-- Pawn: lower case
	out = Run('( pawn: v1: "x": Strength=1 )')
	io.write("lowercase pawn -> " .. out:gsub("\n.*", "") .. "\n")
	-- Pawn: cut short (the prompt takes 256 letters)
	local long = '( Pawn: v1: "Long": Strength=1'
	for i = 1, 40 do long = long .. ", Stat" .. i .. "=0.1" end
	long = long .. " )"
	out = Run("pawn " .. long:sub(1, 250))
	io.write("cut pawn (" .. #long .. " letters) -> " .. out:gsub("\n.*", "") .. "\n")
	-- Pawn: many stats said: WeightsText cut to 6
	local okP, say = F.ApplyPawn('( Pawn: v1: "Many": Strength=1, Agility=0.9, Stamina=0.8, Intellect=0.7, Spirit=0.6, Ap=0.5, CritRating=0.4, HitRating=0.3 )')
	io.write("ApplyPawn many -> " .. tostring(say) .. "\n")
	out = Run("")
	io.write(".weights after -> " .. out .. "\n")
end)
ns.db.upgradeRoles, ns.db.upgradeCustom = saveRoles, saveCustom
if not ok then check(false, "weights_edges: " .. tostring(err)) end
