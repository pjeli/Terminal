-- (1.5.4, the player's ask) Thanking players who buff you (Core/Thanks.lua, the setting thankBuffs): a /thank to a
-- player outside your group whose buff lands on you (UNIT_AURA's added auras: the combat log doesn't reach addons
-- here), each at most once in TH.COOLDOWN seconds, never while the game restricts addons; OneForAll's own option on:
-- left to it.
local T = ...
local ns, check = T.ns, T.check
local L = ns.L
local TH, Theme = ns.Thanks, ns.Theme
io.write("[thanks: a /thank to who buffs you]\n")

local G = { "UnitIsPlayer", "UnitIsUnit", "UnitInParty", "UnitInRaid", "UnitName", "DoEmote", "InCombatLockdown", "GetTime",
	"C_RestrictedActions", "Enum", "issecretvalue", "OneForAllDB", "OneForAllCharDB", "OneForAll", "C_AddOns", "C_ChatInfo" }
local save = {}
for _, k in ipairs(G) do save[k] = rawget(_G, k) end
local setWas = Theme.Get().thankBuffs

local ok, err = pcall(function()
	-- the units around: a stranger on a nameplate, a party member, a raid member, an NPC, you
	local UNITS = {
		nameplate3 = { name = "Bob", player = true }, nameplate4 = { name = "Alice", player = true },
		party1 = { name = "Pal", player = true, party = true }, raid5 = { name = "Raider", player = true, raid = 5 },
		target = { name = "Innkeeper", player = false }, player = { name = "Me", player = true, me = true },
	}
	_G.UnitIsPlayer = function(u) return UNITS[u] and UNITS[u].player or false end
	_G.UnitIsUnit = function(a, b) return a == b or (b == "player" and UNITS[a] and UNITS[a].me) or false end
	_G.UnitInParty = function(u) return UNITS[u] and UNITS[u].party or false end
	_G.UnitInRaid = function(u) return UNITS[u] and UNITS[u].raid or nil end
	_G.UnitName = function(u) return UNITS[u] and UNITS[u].name end
	local emotes = {}
	_G.DoEmote = function(token, unit) emotes[#emotes + 1] = token .. " " .. tostring(unit) end
	local combat, restricted, now = false, {}, 1000
	_G.InCombatLockdown = function() return combat end
	_G.GetTime = function() return now end
	_G.Enum = setmetatable({ AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4 } },
		{ __index = save.Enum })
	_G.C_RestrictedActions = { IsAddOnRestrictionActive = function(r) return restricted[r] == true end }
	_G.issecretvalue = function(v) return v == "SECRET" end
	local loaded = {}
	_G.C_AddOns = setmetatable({ IsAddOnLoaded = function(n) if loaded[n] ~= nil then return loaded[n] end return save.C_AddOns.IsAddOnLoaded(n) end },
		{ __index = save.C_AddOns })
	_G.OneForAll, _G.C_ChatInfo = nil, nil
	-- (a buff just cast, lasting half an hour; `ago`: cast that long ago, `dur`: its length)
	local function Aura(src, helpful, ago, dur)
		dur = dur or 1800
		return { spellId = 1243, isHelpful = helpful ~= false, sourceUnit = src, duration = dur, expirationTime = now - (ago or 0) + dur }
	end
	local function Buff(src, helpful, ago, dur) TH.OnAura({ addedAuras = { Aura(src, helpful, ago, dur) } }) end
	local function Event(unit, info) local h = TH.frame:GetScript("OnEvent") h(TH.frame, "UNIT_AURA", unit, info) end
	TH.Forget()

	-- off unless turned on
	Theme.Set("thankBuffs", "off", true)
	Buff("nameplate3")
	check(#emotes == 0 and not TH.On(), "off (the default): nobody thanked")
	check(Theme.Set("thankBuffs", "on", true) and TH.On(), "turned on")

	-- a stranger's buff: thanked, by the unit the game gave
	Event("player", { addedAuras = { Aura("nameplate3") } })
	check(emotes[1] == "THANK nameplate3", "a player outside your group: /thank: " .. table.concat(emotes, ", "))
	-- the same player again within ten minutes: once
	now = now + 120
	Buff("nameplate3")
	check(#emotes == 1, "their next buff a while after: not thanked again")
	now = now + TH.COOLDOWN
	Buff("nameplate3")
	check(#emotes == 2, "ten minutes on: thanked again")
	-- not these
	emotes = {}
	Buff("party1"); Buff("raid5"); Buff("target"); Buff("player"); Buff(nil); Buff("SECRET"); Buff("nameplate4", false)
	Event("target", { addedAuras = { Aura("nameplate4") } })
	TH.OnAura({ isFullUpdate = true })
	check(#emotes == 0, "not your group, an NPC, yourself, no caster named, a secret one, a debuff, another unit's aura, a full update: "
		.. table.concat(emotes, ", "))
	-- not while the game restricts addons; not saved for later
	combat = true
	Buff("nameplate4")
	combat = false
	restricted[1] = true
	Buff("nameplate4")
	check(#emotes == 0, "in combat, in a boss fight: nobody thanked")
	restricted[1] = nil
	Buff("nameplate4")
	check(emotes[1] == "THANK nameplate4", "out of it, their next buff: thanked (not kept back from before)")

	-- (1.5.8, review) only a buff just cast that lasts a while
	emotes = {}
	TH.Forget()
	Buff("nameplate3", true, 1200)
	check(#emotes == 0, "one cast 20 minutes ago, reported again after a loading screen or a /reload: not thanked")
	Buff("nameplate3", true, 0, 15)
	check(#emotes == 0, "a heal over time (15 s): not thanked")
	TH.OnAura({ addedAuras = { { isHelpful = true, sourceUnit = "nameplate3" } } })
	check(#emotes == 0, "no length or start said: not thanked")
	Buff("nameplate3", true, 2)
	check(emotes[1] == "THANK nameplate3", "one cast 2 s ago, half an hour long: thanked")
	-- an aura list the game keeps secret: no error, nothing done
	emotes = {}
	TH.Forget()
	local h = TH.frame:GetScript("OnEvent")
	local okSecret = pcall(h, TH.frame, "UNIT_AURA", "player", { addedAuras = "SECRET" })
	check(okSecret and #emotes == 0, "a secret aura list: no error, nobody thanked")
	-- the game's PerformEmote first: a refused emote is said so (not "thanked")
	local performed, refuse = {}, false
	_G.C_ChatInfo = { PerformEmote = function(token, unit) performed[#performed + 1] = token .. " " .. unit return refuse end }
	Buff("nameplate4")
	check(performed[1] == "THANK nameplate4" and #emotes == 0, "PerformEmote used where there is one")
	refuse = true
	check(TH.Thank("nameplate3") == false, "refused by the game: not counted as thanked")
	_G.C_ChatInfo = nil

	-- OneForAll's own option on: left to it; off there: Terminal's
	emotes = {}
	-- (1.5.8, review) as it is now: its own reading (QoL.Get), not a profile's copy saved at the last logout
	local live = { thanksBuff = true }
	_G.OneForAll, loaded.OneForAll = { QoL = { Get = function(k) return live[k] end } }, true
	_G.OneForAllCharDB = { profile = "Raid" }
	_G.OneForAllDB = { qol = live, profiles = { Raid = { qol = { thanksBuff = false } } } }
	TH.Forget()
	Buff("nameplate3")
	check(TH.OneForAllThanks() and not TH.On() and #emotes == 0, "OneForAll thanking: Terminal doesn't too")
	live.thanksBuff = false -- (turned off in its options this session)
	check(not TH.OneForAllThanks() and TH.On(), "turned off there this session: Terminal's (the profile's old copy doesn't count)")
	_G.OneForAll = {} -- (no QoL to ask: its live settings)
	_G.OneForAllDB = { qol = { thanksBuff = true }, profiles = { Raid = { qol = { thanksBuff = false } } } }
	check(TH.OneForAllThanks(), "its live settings read when its reading isn't there")
	loaded.OneForAll = false
	check(not TH.OneForAllThanks() and TH.On(), "OneForAll not loaded: its saved option doesn't count")

	-- the setting: a settings row, found by its words
	local O = ns.Options
	check(O and O.SET_DESC.thankBuffs and O.SET_WORDS.thankBuffs:find("thank", 1, true), "a description and search words for it")
end)
for _, k in ipairs(G) do _G[k] = save[k] end
Theme.Set("thankBuffs", setWas and "on" or "off", true)
TH.Forget()
check(ok, "thanks: " .. tostring(err))
