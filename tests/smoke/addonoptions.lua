-- Other addons' options (AddonOptions.lua, 0.50.3, the player's ask): every setting registered with Ace3's
-- AceConfigRegistry, searchable; Enter opens AceConfigDialog's window on its group and points at it; Shift+Enter turns
-- an on/off setting on or off, as its checkbox would.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local AO, P = ns.AddonOptions, ns.providers.addonoptions

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[addon options: Ace3's registered settings]\n")
do
	local save = { ls = _G.LibStub, easy = ns.db.easyMode, show = ns.Highlight.Show, print = ns.Print }
	check(P and ns:ResolveProvider("addonoption") == P and ns:ResolveProvider("addonsettings") == P, "@addonoption, @addonsettings")
	-- an addon's options as Ace3 holds them: groups, inline groups, headers, hidden ones, handlers' method names
	local db = { icons = false, lock = false, announce = true }
	local Handler = { Get = function(self, info) return db[info[#info]] end, Set = function(self, info, v) db[info[#info]] = v end }
	local questie = { type = "group", name = "|cffffd200Questie|r", args = {
		map = { type = "group", name = "Map", order = 1, args = {
			icons = { type = "toggle", name = "Show map icons", desc = "Quest icons on the world map", order = 1,
				get = function() return db.icons end, set = function(_, v) db.icons = v end },
			scale = { type = "range", name = "Icon scale", order = 2, min = 0.5, max = 2 },
			hdr = { type = "header", name = "Icons" },
			secret = { type = "toggle", name = "Debug icons", hidden = true },
		} },
		tracker = { type = "group", name = "Tracker", order = 2, args = {
			lock = { type = "toggle", name = "Lock tracker", disabled = function() return true end,
				get = function() return db.lock end, set = function(_, v) db.lock = v end },
			fonts = { type = "group", inline = true, name = "Fonts", args = { size = { type = "range", name = "Font size" } } },
		} },
		general = { type = "group", name = "General", order = 3, handler = Handler, get = "Get", set = "Set", args = {
			announce = { type = "toggle", name = "Announce quests", desc = function(info) return "Say " .. info[0] end },
			wipe = { type = "execute", name = "Reset everything", confirm = true, func = function() db.wiped = true end },
			-- (asks first, checks the value: the window's to do; review, 0.50.3)
			ask = { type = "toggle", name = "Ask first", confirm = function(_, v) return v == true end },
			check = { type = "toggle", name = "Checked value", validate = function() return true end },
		} },
		-- (inline for the config window but not the dialog: its own page there)
		paged = { type = "group", name = "Paged", order = 4, inline = true, dialogInline = false, args = {
			deep = { type = "toggle", name = "Deep setting" } } },
		-- (a plugin's option wins over the group's own of that key)
		alpha = { type = "toggle", name = "Alpha", order = 5 },
	}, plugins = { extra = { alpha = { type = "toggle", name = "PluginAlpha", order = 5 } } } }
	local attune = { type = "group", name = function() return "Attune" end, args = {
		announce = { type = "toggle", name = "Announce attunements", get = function() return false end, set = function() end },
	} }
	local notified, opened, selected = {}, {}, {}
	local reg = { tables = {} }
	-- (review, 0.53.6) the registry's callbacks: the list is read again when an addon says its options changed
	local callbacks = {}
	function reg.RegisterCallback(target, event, fn) callbacks[event] = fn end
	-- (as AceConfigRegistry: a function to call with the uiType, or, given one, the table itself; review, 0.50.3)
	function reg.GetOptionsTable(_, app, uiType)
		local f = reg.tables[app]
		if f and uiType then return f(uiType) end
		return f
	end
	function reg.NotifyChange(_, app) notified[#notified + 1] = app end
	for app, t in pairs({ Questie = questie, Attune = attune }) do
		reg.tables[app] = function() return t end
	end
	-- Ace3's window: Open makes its frame; its widgets carry their option's path (as InjectInfo tags them)
	local function Widget(path)
		local w = { frame = T.Obj("Frame"), children = {} }
		w.frame:Show()
		local user = { path = path }
		function w.GetUserDataTable() return user end
		return w
	end
	local dialog = { OpenFrames = {} }
	function dialog.Open(_, app)
		opened[#opened + 1] = app
		local f = Widget({})
		f.children = { Widget({ "map", "icons" }), Widget({ "map", "scale" }), Widget({ "general", "announce" }) }
		dialog.OpenFrames[app] = f
	end
	function dialog.SelectGroup(_, app, ...) selected[#selected + 1] = app .. ":" .. table.concat({ ... }, ">") end
	_G.LibStub = setmetatable({}, { __call = function(_, name)
		if name == "AceConfigRegistry-3.0" then return reg end
		if name == "AceConfigDialog-3.0" then return dialog end
	end })
	local said = {}
	ns.Print = function(_, s) said[#said + 1] = tostring(s) end
	local shown
	ns.Highlight.Show = function(self, target, ...) shown = target return save.show(self, target, ...) end
	ns.db.easyMode = false
	P._dirty = true

	local res = UI:Search("@addonoption")
	local all = res
	-- every visible setting and page, in the window's order; headers, hidden ones and inline groups' own rows left out
	check(Names(res) == "Announce attunements | Map | Show map icons | Icon scale | Tracker | Font size | Lock tracker | General | Announce quests | Ask first | Checked value | Reset everything | Paged | Deep setting | PluginAlpha",
		"the settings, in the window's order: " .. Names(res))
	check(P.refreshOnOpen == nil and callbacks.ConfigTableChange ~= nil, "listening to ConfigTableChange, not read again every 5 minutes")
	P._dirty = false
	callbacks.ConfigTableChange("SomeAddon")
	check(P._dirty == true, "an addon's options changed: the list to be read again")
	local function Row(name, rows)
		for _, e in ipairs(rows or all) do if e.name == name then return e end end
	end
	local icons = Row("Show map icons")
	check(icons.detail:find("Questie › Map", 1, true) and icons.detail:find("on/off", 1, true) and icons.detail:find("off", 1, true),
		"its detail: where, what kind, and its value: " .. icons.detail)
	check(Row("Font size").opt.selectPath[1] == "tracker" and #Row("Font size").opt.selectPath == 1, "an inline group's setting: its page is the parent's")
	check(Row("Announce quests").opt.desc == "Say Questie", "a description worked out by the addon's own function, with Ace3's info")
	-- found by what it's called, its addon and its page
	res = UI:Search("questie map icons")
	check(res[1] and res[1].name == "Show map icons", "questie map icons: " .. Names(res))
	-- Enter: Ace3's window on its page, pointing at it
	shown = nil
	icons.activate(icons); FlushAll()
	check(opened[#opened] == "Questie" and selected[#selected] == "Questie:map" and shown and shown == dialog.OpenFrames.Questie.children[1].frame,
		"Enter: Questie's options on Map, the setting pointed at: " .. tostring(selected[#selected]))
	local V = function(e) return table.concat({ ns.Easy.Verbs(e) }, "/") end
	check(V(icons) == "open its options/turn on or off" and V(Row("Icon scale")) == "open its options", "verbs: " .. V(icons))
	-- Shift+Enter: on and off, as its checkbox would; the window told
	icons.secondary(icons)
	check(db.icons == true and notified[#notified] == "Questie" and said[#said]:find("Show map icons", 1, true) and said[#said]:find("on", 1, true),
		"Shift+Enter turns it on: " .. tostring(said[#said]))
	icons.secondary(icons)
	check(db.icons == false, "and off again")
	-- through the handler's method names
	local ann = Row("Announce quests")
	ann.secondary(ann)
	check(db.announce == false, "a handler's Get/Set by name")
	-- not one that's greyed out
	local lock = Row("Lock tracker")
	lock.secondary(lock)
	check(db.lock == false and said[#said]:find("open its options", 1, true), "greyed out: not changed, said so: " .. said[#said])
	check(Row("Reset everything").secondary == nil, "a button: no Shift+Enter")
	-- (review, 0.50.3) asks first or checks the value: left to the window, nothing of the addon's called
	local ask = Row("Ask first")
	ask.secondary(ask)
	check(db.ask == nil and said[#said]:find("open its options", 1, true), "one that asks first: not flipped")
	local chk = Row("Checked value")
	chk.secondary(chk)
	check(db.check == nil and said[#said]:find("open its options", 1, true), "one that checks the value: not flipped")
	-- in combat: not now
	local combat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	icons.secondary(icons)
	check(db.icons == false and said[#said]:find("after the fight", 1, true), "in combat: not changed: " .. said[#said])
	_G.InCombatLockdown = combat
	check(Row("Deep setting").opt.selectPath[1] == "paged", "inline for the config window only: its own page in the dialog")
	-- .integrations names them
	local lines = table.concat(ns:FindCommand("integrations").run("") or {}, " / ")
	check(lines:find("Attune, Questie", 1, true), ".integrations: " .. lines)

	-- Simple mode: under Settings
	ns.db.easyMode = true
	check(ns.Easy.CategoryOf(icons) == "settings", "Simple mode: Settings")
	ns.db.easyMode = false

	_G.LibStub, ns.db.easyMode, ns.Highlight.Show, ns.Print = save.ls, save.easy, save.show, save.print
	P._dirty = true
end
