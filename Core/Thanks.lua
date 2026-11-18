local ns = select(2, ...)

-- Thanking players who buff you (1.5.4, the player's ask; the setting thankBuffs, off unless turned on): a /thank to a
-- player outside your group whose buff lands on you, as OneForAll's "Thank players who buff you" does. With OneForAll
-- there and that option of its own on, Terminal leaves it to OneForAll: one thank, not two.
--
-- How a buff is told: the combat log doesn't reach addons on this client (Providers/CombatLog.lua), so UNIT_AURA on
-- you: its added auras, helpful ones, cast by a unit the game names (the aura's sourceUnit: a target, a nameplate, a
-- mouseover...). A caster the game gives no unit for isn't thanked. Never while the game restricts addons (combat, a
-- boss fight, a keystone, a PvP match, a restricted map): nothing then, nothing saved for later. Each player at most
-- once in TH.COOLDOWN seconds (a paladin's three blessings: one thank). Only a buff just cast (the game reports every
-- aura again after a loading screen or a /reload) that lasts a while (not a heal over time or a proc): 1.5.8, review.

local TH = {}
ns.Thanks = TH
TH.COOLDOWN = 600
TH.FRESH = 3 -- (seconds: a buff cast longer ago than this is one the game reports again, not one just cast)
TH.MIN_DURATION = 60 -- (seconds: shorter ones aren't thanked)

local Safe, Str, Secret = ns.Safe, ns.Str, ns.Secret
local last = {} -- (a player's name -> when they were last thanked, GetTime)

local function Yes(v) return v ~= nil and not Secret(v) and v == true end
local function Now() return (GetTime and GetTime()) or 0 end

--- Is OneForAll's own "Thank players who buff you" on? As it is now, while it's loaded: its own reading (QoL.Get), else
--- its live settings (OneForAllDB.qol: a profile is copied into them at login and back at logout, so the profile's own
--- copy is the last session's; 1.5.8, review).
function TH.OneForAllThanks()
	local OA = ns.OneForAll
	if not (OA and OA.Loaded and OA.Loaded()) then return false end
	local lib = OA.Lib and OA.Lib()
	local Q = type(lib) == "table" and type(lib.QoL) == "table" and lib.QoL
	if Q and type(Q.Get) == "function" then
		local ok, v = pcall(Q.Get, "thanksBuff")
		if ok and not Secret(v) then return v == true end
	end
	local db = rawget(_G, "OneForAllDB")
	return type(db) == "table" and type(db.qol) == "table" and db.qol.thanksBuff == true
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
	-- (the game's emote call, which says when it was refused; DoEmote where there's none)
	local CI = C_ChatInfo
	local perform = CI and type(CI.PerformEmote) == "function" and CI.PerformEmote
	if not (perform or type(DoEmote) == "function") then return false end
	last[name] = now
	local ok, res
	if perform then ok, res = pcall(perform, "THANK", unit) else ok, res = pcall(DoEmote, "THANK", unit) end
	local refused = perform and ok and not Secret(res) and res == true -- (PerformEmote: true when it was restricted)
	ns:Trace("thanks: " .. name .. ((ok and not refused) and " thanked" or (" not thanked: " .. (refused and "the game refused the emote" or tostring(res)))))
	return ok and not refused
end

-- a buff just cast that lasts a while (not one the game reports again after a loading screen, not a heal over time)
local function JustCast(a)
	local dur, ends = a.duration, a.expirationTime
	if type(dur) ~= "number" or type(ends) ~= "number" or Secret(dur) or Secret(ends) then return false end
	if dur <= TH.MIN_DURATION then return false end
	return math.abs((ends - dur) - Now()) <= TH.FRESH
end

--- One UNIT_AURA on you: each helpful aura just cast, its caster thanked (once each). Nothing in combat.
function TH.OnAura(info)
	if type(info) ~= "table" or Secret(info) then return end
	local added = info.addedAuras
	if type(added) ~= "table" or Secret(added) or not TH.On() then return end
	if InCombatLockdown and Yes(Safe(InCombatLockdown)) then return end
	for _, a in ipairs(added) do
		if type(a) == "table" and Yes(a.isHelpful) and JustCast(a) then
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
		if unit == "player" then Safe(TH.OnAura, info) end -- (an aura of a shape not seen yet: no error on every change)
	end)
	TH.frame = f -- (tests)
end
