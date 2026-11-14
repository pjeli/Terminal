local ns = select(2, ...)

-- Thanking players who buff you (1.5.4, the player's ask; the setting thankBuffs, off unless turned on): a /thank to a
-- player outside your group whose buff lands on you, as OneForAll's "Thank players who buff you" does. With OneForAll
-- there and that option of its own on, Terminal leaves it to OneForAll: one thank, not two.
--
-- How a buff is told: the combat log doesn't reach addons on this client (Providers/CombatLog.lua), so UNIT_AURA on
-- you: its added auras, helpful ones, cast by a unit the game names (the aura's sourceUnit: a target, a nameplate, a
-- mouseover...). A caster the game gives no unit for isn't thanked. Never while the game restricts addons (combat, a
-- boss fight, a keystone, a PvP match, a restricted map): nothing then, nothing saved for later. Each player at most
-- once in TH.COOLDOWN seconds (a paladin's three blessings: one thank).

local TH = {}
ns.Thanks = TH
TH.COOLDOWN = 600

local Safe, Str, Secret = ns.Safe, ns.Str, ns.Secret
local last = {} -- (a player's name -> when they were last thanked, GetTime)

local function Yes(v) return v ~= nil and not Secret(v) and v == true end
local function Now() return (GetTime and GetTime()) or 0 end

--- Is OneForAll's own "Thank players who buff you" on? Its saved setting, read while it's loaded: the profile this
--- character uses (OneForAllCharDB.profile, "Default" else), its older single settings table before profiles.
function TH.OneForAllThanks()
	local OA = ns.OneForAll
	if not (OA and OA.Loaded and OA.Loaded()) then return false end
	local db = rawget(_G, "OneForAllDB")
	if type(db) ~= "table" then return false end
	local char = rawget(_G, "OneForAllCharDB")
	local name = type(char) == "table" and type(char.profile) == "string" and char.profile or "Default"
	local p = type(db.profiles) == "table" and db.profiles[name]
	local qol = (type(p) == "table" and type(p.qol) == "table" and p.qol) or (type(db.qol) == "table" and db.qol) or nil
	return qol ~= nil and qol.thanksBuff == true
end

--- Thanking now? The setting on, OneForAll not doing it.
function TH.On()
	local T = ns.Theme and ns.Theme.Get and ns.Theme.Get()
	return type(T) == "table" and T.thankBuffs == true and not TH.OneForAllThanks()
end

--- Does the game restrict addons right now (or are you in combat)?
function TH.Restricted()
	if InCombatLockdown and Yes(Safe(InCombatLockdown)) then return true end
	local R, E = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
	if R and R.IsAddOnRestrictionActive and type(E) == "table" then
		for _, v in pairs(E) do if Yes(Safe(R.IsAddOnRestrictionActive, v)) then return true end end
	end
	return false
end

--- Thanks the player behind `unit` when they're one to thank: a player, not you, not in your group, not thanked in
--- the last TH.COOLDOWN seconds, nothing restricted. True when the game was asked to /thank them.
function TH.Thank(unit)
	if type(unit) ~= "string" or Secret(unit) or unit == "" then return false end
	if not Yes(Safe(UnitIsPlayer, unit)) or Yes(Safe(UnitIsUnit, unit, "player")) then return false end
	if Yes(Safe(UnitInParty, unit)) then return false end
	local raid = Safe(UnitInRaid, unit)
	if raid ~= nil and not Secret(raid) then return false end -- (its index in your raid)
	local name = Str(Safe(UnitName, unit))
	if not name then return false end
	local now = Now()
	if last[name] and now - last[name] < TH.COOLDOWN then return false end
	if TH.Restricted() then
		ns:Trace("thanks: " .. name .. " buffed you, not thanked: the game restricts addons now")
		return false
	end
	if type(DoEmote) ~= "function" then return false end
	last[name] = now
	local ok, err = pcall(DoEmote, "THANK", unit)
	ns:Trace("thanks: " .. name .. (ok and " thanked" or (" not thanked: " .. tostring(err))))
	return ok
end

--- One UNIT_AURA on you: each helpful aura added, its caster thanked (once each).
function TH.OnAura(info)
	if type(info) ~= "table" or type(info.addedAuras) ~= "table" or not TH.On() then return end
	for _, a in ipairs(info.addedAuras) do
		if type(a) == "table" and Yes(a.isHelpful) then
			local src = a.sourceUnit
			if type(src) == "string" and not Secret(src) then TH.Thank(src) end
		end
	end
end

function TH.Forget() last = {} end -- (tests)

do
	local f = CreateFrame("Frame")
	-- (only your own auras: every unit's would fire for each nameplate)
	if not (f.RegisterUnitEvent and pcall(f.RegisterUnitEvent, f, "UNIT_AURA", "player")) then pcall(f.RegisterEvent, f, "UNIT_AURA") end
	f:SetScript("OnEvent", function(_, _, unit, info)
		if unit == "player" then TH.OnAura(info) end
	end)
	TH.frame = f -- (tests)
end
