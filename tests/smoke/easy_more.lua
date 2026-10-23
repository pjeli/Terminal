-- Simple mode, continued (easy.lua split in two: each file has its own instruction budget).
local T = ...
local ns, UI, check, key, FlushAll, log, logHas, S = T.ns, T.UI, T.check, T.key, T.FlushAll, T.log, T.logHas, T.S
local E = ns.Easy

local saved = { providers = ns.providers, order = ns.providerOrder }
local function Use(defs)
	ns.providers, ns.providerOrder = {}, {}
	for _, d in ipairs(defs) do ns:RegisterProvider(d[1], d[2]) end
	UI.lastScan = nil
end
local function Restore()
	ns.providers, ns.providerOrder = saved.providers, saved.order
	ns:AliasesChanged()
	UI.lastScan = nil
end
local function Rows(list)
	return function()
		local out = {}
		for i, r in ipairs(list) do
			local e = {}
			for k, v in pairs(r) do e[k] = v end
			e.key = e.key or i
			out[i] = e
		end
		return out
	end
end
local function BigList(label, alias, names)
	return { label = label, hintLabel = label, aliases = { alias }, explicit = true, collect = Rows((function()
			local t = {}
			for i, n in ipairs(names) do t[i] = { name = n } end
			return t
		end)()),
		hintFind = function(_, tokens)
			local first, count, ids = nil, 0, {}
			for i, n in ipairs(names) do
				local ln, all = n:lower(), true
				for _, tk in ipairs(tokens) do if not ln:find(tk, 1, true) then all = false end end
				if all then
					count = count + 1; first = first or n
					if #ids < 3 then ids[#ids + 1] = i end
				end
			end
			return first, count, ids
		end,
		hintRow = function(_, id) return { name = names[id], key = id, kind = alias } end }
end
local function Has(res, name)
	for i, e in ipairs(res) do if e.name == name then return i end end
end
local function Kinds(res)
	local t = {}
	for _, e in ipairs(res) do t[e.kind or "?"] = true end
	return t
end
local function Show(res)
	local t = {}
	for i = 1, math.min(#res, 8) do t[i] = tostring(res[i].completion or res[i].name) end
	return table.concat(t, " | ")
end
local function Run(title, fn)
	io.write("[easy: " .. title .. "]\n")
	local ok, err = pcall(fn)
	Restore()
	UI.category = nil
	ns.db.easyMode = false
	UI:EasyChanged()
	UI:Hide(); FlushAll()
	if not ok then check(false, title .. ": " .. tostring(err)) end
end

local function Lists()
	Use({
		{ "items", { label = "Item", aliases = { "item" }, collect = Rows({
			{ name = "Rare Sword", quality = 1, itemID = 1 },
			{ name = "Blade of Ages", quality = 3, itemID = 2 },
			{ name = "Shiny Sword", quality = 3, itemID = 3 },
			{ name = "Rusty Sword", quality = 0, itemID = 4 },
		}) } },
		{ "spells", { label = "Spell", aliases = { "spell" }, collect = Rows({ { name = "Sword Specialization" }, { name = "Fireball" } }) } },
		{ "quests", { label = "Quest", aliases = { "questlog" }, collect = Rows({ { name = "The Sword of Kings", questID = 9 } }) } },
		{ "keybinds", { label = "Keybinding", aliases = { "keybind" }, collect = Rows({ { name = "Sheathe Sword" } }) } },
		{ "loot", { label = "Loot", aliases = { "loot" }, collect = Rows({ { name = "Sword of Omen", itemID = 50 }, { name = "Thunderfury" } }) } },
		{ "npc", BigList("Questie's NPCs", "npc", { "Sword Master Thorn", "Swordsmith Ivan", "Old Sword Guy", "Sword Dummy" }) },
		{ "questie", BigList("Questie's quests", "questie", { "The Sword of Kings", "Sword Practice" }) },
		{ "slash", { label = "Slash", aliases = { "slash" }, explicit = true, collect = Rows({
			{ name = "/dance", emote = "DANCE", text = "emote dance" }, { name = "/swordplay", text = "swordplay" },
			{ name = "/reload", text = "reload" } }) } },
		{ "cvars", { label = "CVar", aliases = { "cvar" }, explicit = true, collect = Rows({ { name = "cameraDistanceMaxZoomFactor" } }) } },
	})
end
-- typed, then the category picked from the rows (as a player does it)
local function In(cat, query)
	UI:Open(query)
	UI:SetCategory(cat)
	return UI.Results()
end


local function Fire(e) return function() log[#log + 1] = "RAN " .. e end end
local function ActionLists()
	Use({
		{ "items", { label = "Item", aliases = { "item" }, collect = Rows({
			{ name = "Hearthstone", itemID = 6948, secure = { binding = "OPENALLBAGS" }, activate = Fire("bags"),
				secondary = Fire("use"), secondarySecure = { macro = "/use item:6948" }, link = "|cffffffff|Hitem:6948|h[Hearthstone]|h|r" },
			{ name = "Shiny Sword", quality = 3, itemID = 3 } }) } },
		{ "spells", { label = "Spell", aliases = { "spell" }, collect = Rows({
			{ name = "Frost Nova", activate = Fire("book"), secondary = Fire("cast"), secondarySecure = { macro = "/cast Frost Nova" } },
			{ name = "Summon Voidwalker", activate = Fire("book"), secondary = Fire("cast"),
				secondarySecure = { macro = "/cast Summon Voidwalker" } } }) } },
		{ "mounts", { label = "Mount", aliases = { "mount" }, collect = Rows({ { name = "Swift Raptor", activate = Fire("summon") } }) } },
		{ "npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = Rows({
			{ name = "Innkeeper Farley", key = 295, npcID = 295, activate = Fire("map"), secondary = Fire("target"), secondarySecure = { macro = "/targetexact Innkeeper Farley" } },
			{ name = "Innkeeper Allison", key = 6740, npcID = 6740, activate = Fire("map") },
			{ name = "Innkeeper Far Away", key = 9999, npcID = 9999, activate = Fire("map") },
			{ name = "Hogger", key = 448, npcID = 448, activate = Fire("map") },
			{ name = "Bernie Heisten", key = 3546, npcID = 3546, activate = Fire("map") },
			{ name = "Grimtak", key = 3881, npcID = 3881, activate = Fire("map") } }) } },
	})
end

Run("reopening: no flash of the last results; Down brings them back", function()
	for _, mode in ipairs({ true, false }) do
		local name = mode and "Simple" or "Advanced"
		E.Set(mode); ns.db.easyMode = mode
		Lists()
		UI:Open("sword")
		local fr = _G.TerminalFrame
		local tall = fr.h
		check(#UI.Results() > 0 and not UI.bare, name .. ": a search lists rows")
		UI:Hide(); FlushAll()
		-- the game may report SetText's change a frame later: Open must not wait for it
		local edit = UI.edit
		local realSet = edit.SetText
		edit.SetText = function(self, s) self.text = s or ""; C_Timer.After(0, function() local f = self.scripts.OnTextChanged; if f then f(self) end end) end
		local realShow = fr.Show
		local atShow
		fr.Show = function(self, ...) atShow = self.h; return realShow(self, ...) end
		UI:Open()
		fr.Show = nil
		check(atShow and atShow < tall, name .. ": the frame is already the bare prompt when it shows: " .. tostring(atShow) .. " (was " .. tostring(tall) .. ")")
		check(#UI.Results() == 0 and UI.bare, name .. ": nothing listed at once, not a frame later")
		FlushAll()
		edit.SetText = nil
		check(rawget(edit, "SetText") == nil and edit.SetText ~= nil, "(mock restored)")
		check(UI.edit:GetText() == "" and UI.bare, name .. ": reopened as just the prompt")
		if mode then
			key("DOWN")
			check(UI.edit:GetText() == "sword" and #UI.Results() > 0, name .. ": Down brings the last search back: " .. UI.edit:GetText())
		end
		UI:Hide(); FlushAll()
	end
	-- a category picked in Simple mode comes back with it
	E.Set(true); ns.db.easyMode = true
	Lists()
	In("spells", "sword")
	UI:Hide(); FlushAll()
	UI:Open()
	key("DOWN")
	check(UI.edit:GetText() == "sword" and UI.category == "spells", "Simple: the category comes back too: " .. tostring(UI.category))
	key("UP")
	check(UI.edit:GetText() == "" and UI.bare, "Up on its first row: put away, just the prompt")
	UI:Hide(); FlushAll()
	-- a .command isn't a search to bring back
	UI.lastQuery = nil
	UI:Open(".help"); UI:Hide(); FlushAll()
	check(UI.lastQuery == nil, "a .command isn't kept as the last search")
	-- (0.50.7, review) closed by the game (a window a press opened), not by Terminal: the search is kept all the same
	UI:Open("frostbolt"); FlushAll()
	UI.frame:Hide(); UI.frame.scripts.OnHide(UI.frame); FlushAll()
	UI:Hide(); FlushAll()
	check(UI.lastQuery == "frostbolt", "closed by the game: kept for Down: " .. tostring(UI.lastQuery))

	-- Advanced: Down shows your recent picks (even with a last search), Up the last line run
	ns.db.easyMode = false; UI:EasyChanged()
	ns:Bump("items:1")
	UI:Open("sword"); UI:Hide(); FlushAll()
	UI:Open()
	check(UI:Suggestion() == nil and UI.bare, "Advanced: the bare prompt")
	key("DOWN")
	check(UI.edit:GetText() == "" and #UI.Results() > 0 and UI.Results()[1].name == "Rare Sword", "Advanced: Down shows your recent picks: " .. Show(UI.Results()))
	key("UP")
	check(UI.edit:GetText() == "" and #UI.Results() == 0 and UI.bare, "Up on the first of them: back to just the prompt")
	UI:Hide(); FlushAll()
	local saveH = ns.db.history
	ns.db.history = { ".about" }
	UI:Open(); key("UP")
	check(UI.edit:GetText() == ".about", "Advanced: Up brings the last line run: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	ns.db.history = {}
	UI:Open(); key("UP")
	check(UI.edit:GetText() == "", "no lines run: Up does nothing")
	ns.db.history = saveH
	ns.db.recent = {}
end)

Run("release review fixes", function()
	E.Set(true)
	ActionLists()
	-- everyday words match a name's word start, not inside a word: "ah" isn't Sarah, "inn" isn't Finn
	local function NameRow(n) return { name = n, _lname = n:lower(), kind = "x" } end
	check(not E.Word("ah")(NameRow("Sarah Shahram")) and not E.Word("inn")(NameRow("Finn")), "ah / inn don't match inside names")
	check(not E.Word("ring")(NameRow("Red Herring")) and E.Word("ring")(NameRow("Ring of Valor")), "ring: a word start (not Herring)")
	check(E.Word("sword")(NameRow("Swordsmith Ivan")), "sword still finds Swordsmith (a word start)")
	-- an action word with nothing to do it to says so (it collapsed to the bare prompt)
	UI:Open("use xyzzyq")
	local r = UI.Results()
	check(r[1] and r[1].noActivate and not UI.bare, "use xyzzy: a line says nothing has that: " .. Show(r))
	UI:Hide(); FlushAll()
	-- an action view never falls back to the row's own Enter (no secondary function: false, not nil)
	local view = E.ActionView({ kind = "items", name = "X", activate = function() return "primary" end, secondarySecure = { macro = "/use x" } },
		{ map = { items = "s" }, label = "use" })
	check(view.activate == false, "action view: activate false when the row has only a secure secondary")
	-- the right-click menu goes when combat starts (its secure lines can't be hidden once it's on)
	UI:Open("hearthstone")
	UI:ShowRowMenu(1)
	local m = _G.TerminalRowMenu
	check(m:IsShown(), "(menu shown)")
	m.scripts.OnEvent(m, "PLAYER_REGEN_DISABLED")
	check(not m:IsShown(), "combat starts: the menu goes")
	UI:Hide(); FlushAll()
	-- the sort:distance note doesn't outlive its search
	UI.noPosition = true
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Search("hearthstone")
	check(not UI.noPosition, "the no-position note is reset by the next search")
end)

Run("Alt+`: Advanced mode for this run only", function()
	E.Set(true)
	ActionLists()
	local F = T.F
	local function alt(fn) _G.IsAltKeyDown = function() return true end; fn(); _G.IsAltKeyDown = function() return false end end
	-- what a Simple search says, in Advanced syntax
	-- (0.55.18: a kind of item said as a word is that kind or the word in a name, sword|type:sword, as searched)
	check(E.ToAdvanced("rare sword") == "q:rare sword|type:sword ",
		"rare sword -> filters: " .. E.ToAdvanced("rare sword"))
	check(E.ToAdvanced("attack power food") == "stat:ap food|type:food ", "attack power food -> stat:ap type:food: " .. E.ToAdvanced("attack power food"))
	check(E.ToAdvanced("cast frost nova") == "@spell do:cast frost nova ", "cast frost nova -> @spell do:cast (0.44.11: the action stays): " .. E.ToAdvanced("cast frost nova"))
	check(E.ToAdvanced("nearest innkeeper") == "@npc is:innkeeper faction:friendly sort:distance ",
		"nearest innkeeper -> @npc ... sort:distance: " .. E.ToAdvanced("nearest innkeeper"))
	check(E.ToAdvanced("hearthstone", "bags") == "@item hearthstone ", "a picked category -> its @kind: " .. E.ToAdvanced("hearthstone", "bags"))
	check(E.ToAdvanced("shield that drops from kresh") == "kresh shield|type:shield ", "sentence words dropped: " .. E.ToAdvanced("shield that drops from kresh"))
	check(E.ToAdvanced("") == "", "nothing typed: nothing")
	-- Alt+` in an open Simple prompt: written in Advanced syntax, searched as Advanced
	UI:Open("cast frost nova")
	alt(function() key("`", "`") end) -- (the key's character comes after it, as in the game)
	check(UI:IsShown() and T.query() == "@spell do:cast frost nova " and not E.On() and E.temp, "Alt+`: the prompt is Advanced now: " .. T.query())
	check(UI.ONCE_LABEL == ns.L["Advanced"], "the footer says Advanced (0.55.17: not \"Advanced, this time\"): " .. tostring(UI.ONCE_LABEL))
	local r = UI.Results()
	check(r[1] and r[1].name == "Frost Nova" and r[1].actionVerb == "cast", "searched as Advanced: the spell, Enter still casts it: " .. Show(r))
	key("A", "a")
	check(T.query() == "@spell do:cast frost nova a", "typing goes on after it (only the switch's ` was dropped): " .. T.query())
	key("BACKSPACE")
	check(ns.db.easyMode == true, "the saved mode stays Simple")
	-- closing gives Simple back, and Down brings back what the Simple prompt said
	UI:Hide(); FlushAll()
	check(E.On() and not E.temp, "closed: Simple again")
	UI:Open(""); key("DOWN")
	check(T.query() == "cast frost nova", "Down: the Simple search, not the Advanced one: " .. T.query())
	UI:Hide(); FlushAll()
	-- closed: the binding does nothing (0.57.0, the author's call: Alt+` only switches Simple and Advanced; it opened
	-- Terminal as ` did from 0.54.3)
	UI:AdvancedOnce()
	check(not UI:IsShown() and E.On() and not E.temp, "the binding (closed): nothing")
	UI:Open("")
	UI:SetQuery("@spell nova")
	check(UI.Results()[1] and UI.Results()[1].name == "Frost Nova" and E.On(), "Advanced syntax typed: found, Simple kept (0.55.9)")
	UI:Hide(); FlushAll()
	-- (0.55.9, the player: "we lose the ability to go back") Alt+` again: back to the Simple words, the bar's picks too
	UI:Open("cast frost nova")
	ns.Bar.Pick("sort", "name")
	alt(function() key("`", "`") end)
	check(not E.On() and T.query():find("^@spell do:cast frost nova") and not ns.Bar.Active(), "(Alt+`: Advanced)")
	alt(function() key("`", "`") end)
	check(UI:IsShown() and E.On() and not E.temp and T.query() == "cast frost nova" and ns.Bar.state.sort == "name",
		"Alt+` again: the Simple words back, and the bar's sort: " .. T.query())
	-- Shift+Left does it too (the footer says so)
	alt(function() key("`", "`") end)
	check(not E.On() and UI:CanGoBack(), "(Advanced again; Shift+Left can go back)")
	check(UI:GoBack() and E.On() and T.query() == "cast frost nova", "Shift+Left: the Simple words back: " .. T.query())
	-- edited since: the line as it is now, in Simple mode
	alt(function() key("`", "`") end)
	key("SPACE", " "); key("X", "x")
	check(not UI:CanUndoAdvanced(), "edited: Shift+Left doesn't undo Alt+` any more")
	local edited = T.query()
	alt(function() key("`", "`") end)
	check(E.On() and T.query() == edited, "edited, then Alt+`: Simple, the line kept: " .. T.query())
	ns.Bar.Reset()
	-- plain words with nothing Advanced to write: Alt+` leaves the line and the mode as they are
	UI:SetQuery("", 0)
	alt(function() key("`", "`") end)
	check(E.On() and not E.temp and T.query() == "", "an empty line: Alt+` changes nothing: " .. T.query())
	UI:Hide(); FlushAll()
	-- in Advanced for good, Alt+` has nothing to switch: it neither opens nor closes Terminal (0.57.0)
	ns.db.easyMode = false
	UI:AdvancedOnce()
	check(not UI:IsShown() and not E.temp, "Advanced for good, closed: Alt+` doesn't open it")
	UI:Open("")
	UI:AdvancedOnce()
	check(UI:IsShown() and not E.temp, "Advanced for good, open: Alt+` doesn't close it")
	UI:Hide(); FlushAll()
end)

Run("Advanced syntax typed after Simple words: kept as typed, in Simple mode (0.55.9; 0.54.3-0.55.8 rewrote the line)", function()
	E.Set(true)
	ActionLists()
	local function Names() local t = {} for _, e in ipairs(UI.Results()) do if ns.Bar.Real(e) then t[#t + 1] = tostring(e.name) end end return table.concat(t, " | ") end
	UI:Open("")
	UI:SetQuery("cast frost nova", 15); FlushAll()
	local plain = Names()
	UI:SetQuery("cast frost nova >> party", 24); FlushAll()
	check(T.query() == "cast frost nova >> party" and E.On() and UI.sendTo and UI.sendTo.cmd, "cast frost nova >> party: as typed, Simple: " .. T.query())
	check(Names() == plain and UI.Results()[1].actionVerb == "cast", "the same results, Enter still casts: " .. Names())
	UI:Hide(); FlushAll()
	check(E.On() and UI.lastQuery == "cast frost nova >> party", "closed: Down brings the line back as it was: " .. tostring(UI.lastQuery))
	-- a filter typed after the words
	UI:Open("")
	UI:SetQuery("cast frost nova q:rare"); FlushAll()
	check(T.query() == "cast frost nova q:rare" and E.On(), "a key:value after them: as typed: " .. T.query())
	UI:Hide(); FlushAll()
	-- the line starting with it: as it is
	UI:Open("")
	UI:SetQuery("@spell nova"); FlushAll()
	check(T.query() == "@spell nova" and E.On() and UI.Results()[1] and UI.Results()[1].name == "Frost Nova", "@spell nova: as typed")
	UI:Hide(); FlushAll()
	-- a .command, and Simple's own a|b: left alone
	UI:Open("")
	UI:SetQuery("sword|axe"); FlushAll()
	check(T.query() == "sword|axe" and E.On(), "sword|axe: Simple's own")
	UI:Hide(); FlushAll()
end)

Run("Alt+` names the lists the results come from (use hearthstone: @item, not @camp @item @toy)", function()
	E.Set(true)
	local function alt(fn) _G.IsAltKeyDown = function() return true end; fn(); _G.IsAltKeyDown = function() return false end end
	local function Lists(items)
		Use({
			{ "camp", { label = "Camp", aliases = { "camp" }, collect = Rows({ { name = "Campfire", secondary = Fire("craft") } }) } },
			{ "items", { label = "Item", aliases = { "item" }, collect = Rows(items or {
				{ name = "Hearthstone", itemID = 6948, secondary = Fire("use"), secondarySecure = { macro = "/use item:6948" } },
				{ name = "Train Ticket", itemID = 7, secondary = Fire("use") } }) } },
			{ "toys", { label = "Toy", aliases = { "toy" }, explicit = true, collect = Rows({ { name = "Toy Train Set", activate = Fire("toy") } }) } },
			{ "mounts", { label = "Mount", aliases = { "mount" }, collect = Rows({ { name = "Swift Raptor", activate = Fire("summon") } }) } },
			{ "pets", { label = "Pet", aliases = { "pet" }, collect = Rows({ { name = "Mechanical Squirrel", activate = Fire("pet") } }) } },
		})
	end
	Lists()
	local function Converted(text)
		UI:Open(text)
		alt(function() key("`", "`") end)
		local q = T.query()
		UI:Hide(); FlushAll()
		return q
	end
	-- not told what shows: every list the action looks in (as before)
	check(E.ToAdvanced("use hearthstone") == "@camp @item @toy do:use hearthstone ", "(not told what shows: every list) " .. E.ToAdvanced("use hearthstone"))
	check(E.ToAdvanced("use hearthstone", nil, { items = true }) == "@item do:use hearthstone ", "told: only the list the result is in")
	check(E.ToAdvanced("use zzz", nil, {}) == "do:use zzz ", "nothing shows: no @kind, do:use stands for the action's lists")
	-- in the terminal: what the Simple search shows
	local q = Converted("use hearthstone")
	check(q == "@item do:use hearthstone ", "use hearthstone -> only @item (not a camp object, nor a toy): " .. q)
	q = Converted("use train")
	check(q == "@item @toy do:use train ", "two lists show something: both named: " .. q)
	q = Converted("use zzzz")
	check(q == "do:use zzzz ", "nothing found: do:use alone: " .. q)
	q = Converted("summon raptor")
	check(q == "@mount do:summon raptor ", "summon raptor -> @mount (no pet called that): " .. q)
	-- a category opened for you: its lists that show something (Collections has mounts, pets, toys...)
	q = Converted("swift")
	check(q == "@mount swift ", "swift in Collections -> @mount only: " .. q)
	check(E.ToAdvanced("swift", "collections", {}) == "@mount @pet @toy swift ", "a category with nothing showing: all its lists (no one word for them)")
	-- the Advanced search finds what the Simple one did, Enter still uses it
	UI:Open("use hearthstone")
	alt(function() key("`", "`") end)
	local r = UI.Results()
	check(r[1] and r[1].name == "Hearthstone" and r[1].actionVerb == "use", "searched as Advanced: the Hearthstone, Enter uses it: " .. Show(r))
	UI:Hide(); FlushAll()
	-- a search still going over frames when Alt+` comes: finished first, so the lists named are what it found (its
	-- first frame had seen only part of the bags, nothing that matched, and no toys yet)
	local big = {}
	for i = 1, 3000 do big[i] = { name = ("Pebble %04d"):format(i), itemID = 10000 + i } end
	big[#big + 1] = { name = "Train Ticket", itemID = 7, secondary = Fire("use") }
	Lists(big)
	local realClock = _G.debugprofilestop
	local ms = 0
	_G.debugprofilestop = function() ms = ms + 1; return ms end -- every look at the clock: 1 ms
	local budget = UI.FINISH_MS
	UI.FINISH_MS = 1e9 -- (quick enough to finish)
	UI:Open("use train")
	local going = UI.searchJob ~= nil
	alt(function() key("`", "`") end)
	q = T.query()
	FlushAll()
	check(going and q == "@item @toy do:use train ", "a search still going: finished first, then named (" .. tostring(going) .. "): " .. q)
	UI:Hide(); FlushAll()
	-- the same with a category Simple mode opens for you: it's set only once the overview is done (read after it)
	UI:Open("swift")
	going = UI.searchJob ~= nil
	alt(function() key("`", "`") end)
	q = T.query()
	FlushAll()
	check(going and q == "@mount swift ", "a category opened for you while the search still went on: named: " .. q)
	UI:Hide(); FlushAll()
	-- too long to finish at once (the budget spent): not a frame-long hitch, every list the action looks in instead
	UI.FINISH_MS = 0
	UI:Open("use train")
	alt(function() key("`", "`") end)
	q = T.query()
	FlushAll()
	_G.debugprofilestop = realClock
	UI.FINISH_MS = budget
	check(q == "@camp @item @toy do:use train ", "a search too long to finish now: every list the action looks in: " .. q)
end)

Run("pure fuzzy finding (Tab+`): every list, names only, no syntax; Enter to Simple, Shift+Enter with its @kind", function()
	E.Set(true)
	ActionLists()
	local function win(fn) local was = _G.IsKeyDown; _G.IsKeyDown = function(k) return k == "TAB" end; fn(); _G.IsKeyDown = was end
	local function shifted(fn) local was = _G.IsShiftKeyDown; _G.IsShiftKeyDown = function() return true end; fn(); _G.IsShiftKeyDown = was end
	-- one more list: a row whose words are only in its text, and a copy list (@gear-like) that must not double rows
	ns:RegisterProvider("quests", { label = "Quest", aliases = { "quest" }, collect = Rows({
		{ name = "The Lost Ring", text = "Bring Hogger's claw to the marshal" } }) })
	ns:RegisterProvider("gearcopy", { label = "Gear", aliases = { "gearcopy" }, follows = "items", explicit = true,
		collect = Rows({ { name = "Shiny Sword", quality = 3, itemID = 3 } }) })
	-- Tab+` in an open Simple prompt
	UI:Open("cast frost nova")
	local traceWas, traced = ns.Trace, false
	ns.Trace = function(self, m) if tostring(m):find("key `: alt=false tab=true", 1, true) then traced = true end return traceWas(self, m) end
	win(function() key("`", "`") end)
	ns.Trace = traceWas
	check(UI.fzf and T.query() == "cast frost nova ", "Tab+`: fuzzy finding, the prompt keeps its words: " .. T.query())
	check(UI.glow and UI.glow:IsShown(), "a glow round the prompt bar")
	check((UI.status:GetText() or ""):find("Fuzzy find", 1, true), "the footer says so: " .. tostring(UI.status:GetText()))
	check((UI.hints:GetText() or ""):find("Enter", 1, true), "its own key hints: " .. tostring(UI.hints:GetText()))
	check(traced, "the ` press is traced with its modifiers")
	UI:SetQuery("frost nova", 10)
	local r = UI.Results()
	check(r[1] and r[1].name == "Frost Nova" and not r[1].actionVerb, "Frost Nova found: " .. Show(r))
	-- explicit lists too (NPCs need no @npc), letters in order
	UI:SetQuery("hggr", 4)
	r = UI.Results()
	check(r[1] and r[1].name == "Hogger" and #r == 1, "hggr: Hogger, from a list only searched with @kind elsewhere: " .. Show(r))
	-- names only: a quest's text doesn't match
	UI:SetQuery("marshal", 7)
	check(#UI.Results() == 0, "words in a row's text don't count: " .. Show(UI.Results()))
	-- nothing is syntax: @kinds, filters and sums are plain letters
	UI:SetQuery("@npc hogger", 11)
	check(#UI.Results() == 0, "@npc is just letters: " .. Show(UI.Results()))
	UI:SetQuery("q:rare", 6)
	check(#UI.Results() == 0, "q:rare is just letters (nothing has them): " .. Show(UI.Results()))
	UI:SetQuery("2+2", 3)
	check(#UI.Results() == 0, "no calculator: " .. Show(UI.Results()))
	check(#UI:SyntaxSegments("@npc q:rare >> party") == 1, "the prompt isn't coloured as syntax")
	UI:SetQuery("froost", 6)
	check(#UI.Results() == 0, "no close spellings: " .. Show(UI.Results()))
	-- a row once, even from a copy list
	UI:SetQuery("shiny", 5)
	r = UI.Results()
	check(#r == 1 and r[1].kind == "items", "a copy list (follows another) isn't listed twice: " .. Show(r))
	-- the arrows go through the list, never the history
	ns.db.history = { "@spell frost nova" }
	UI:SetQuery("", 0)
	check(UI.ghost:IsShown() and UI.ghost:GetText() == "fzf", "the empty prompt says fzf: " .. tostring(UI.ghost:GetText()))
	key("UP")
	check(T.query() == "", "Up on the empty prompt: no history line: " .. T.query())
	key("DOWN")
	check(#UI.Results() == 0, "Down on the empty prompt: no recent picks")
	UI:SetQuery("innkeeper", 9)
	check(UI.Selected() == 1 and #UI.Results() == 3, "three innkeepers: " .. Show(UI.Results()))
	key("DOWN"); key("DOWN")
	check(UI.Selected() == 3, "Down moves through them: " .. tostring(UI.Selected()))
	key("UP")
	check(UI.Selected() == 2, "Up moves back: " .. tostring(UI.Selected()))
	key("TAB")
	check(UI.Selected() == 3, "Tab moves too (no categories here): " .. tostring(UI.Selected()))
	-- narrowing letter by letter gives what a fresh search does
	for _, word in ipairs({ "i", "in", "inn", "innk", "innk f", "innk fa" }) do
		UI:SetQuery(word, #word)
		local got = Show(UI.Results())
		local was = UI.lastFzf
		UI.lastFzf = nil
		local fresh = Show(UI:Search(word))
		check(got == fresh, ("'%s': narrowed = fresh (%s / %s)"):format(word, got, fresh))
		UI.lastFzf = was
	end
	ns.db.history = {}
	-- Shift+Right writes the plain name (no @kind)
	UI:SetQuery("hggr", 4)
	shifted(function() key("RIGHT") end)
	check(T.query() == "Hogger ", "Shift+Right: the name only: " .. T.query())
	-- no click catcher over the rows (a click hands over, it never opens)
	UI:PlaceCatcher(1)
	check(not (_G.TerminalClickCatcher and _G.TerminalClickCatcher:IsShown()), "no click catcher in fuzzy finding")
	-- Enter: to Simple mode, in its category, selected; nothing is run or armed
	UI:SetQuery("innkeeper farley", 16)
	key("ENTER")
	check(not UI.fzf and E.On() and T.query() == "Innkeeper Farley " and UI.category == "npcs" and not UI.armedEntry,
		"Enter: to Simple mode, in NPCs: " .. T.query() .. " [" .. tostring(UI.category) .. "]")
	r = UI.Results()
	check(r[UI.Selected()] and r[UI.Selected()].name == "Innkeeper Farley", "the result is selected there: " .. Show(r))
	check(not UI.glow:IsShown(), "the glow goes")
	UI:Hide(); FlushAll()
	-- Shift+Enter: to Advanced mode, "@kind name", for this run only
	UI:Open("")
	win(function() key("`", "`") end)
	check(UI.fzf and T.query() == "", "Tab+` on the empty prompt: fuzzy finding")
	UI:SetQuery("frost", 5)
	shifted(function() key("ENTER") end)
	check(not UI.fzf and E.On() and not E.temp and T.query() == "@spell Frost Nova ", "Shift+Enter: \"@kind name\", Simple kept (0.55.9): " .. T.query())
	r = UI.Results()
	check(r[UI.Selected()] and r[UI.Selected()].name == "Frost Nova", "selected: " .. Show(r))
	check(ns.db.easyMode == true, "the saved mode stays Simple")
	UI:Hide(); FlushAll()
	check(E.On() and not E.temp, "closed: Simple again")
	-- a click is Enter (Shift+click Shift+Enter)
	UI:Open(""); UI:FuzzyOnce()
	UI:SetQuery("raptor", 6)
	UI:Activate(1, {})
	check(not UI.fzf and E.On() and T.query() == "Swift Raptor ", "a click: to Simple: " .. T.query())
	UI:Hide(); FlushAll()
	-- Tab+` in it: the terminal closes (as Alt+` again does), and the next open is the usual mode
	UI:Open("hogger")
	win(function() key("`", "`") end)
	check(UI.fzf, "(fuzzy finding)")
	win(function() key("`", "`") end)
	check(not UI:IsShown() and not UI.fzf and E.On(), "Tab+` again: closes")
	FlushAll()
	UI:FuzzyOnce()
	-- Alt+` in it: out of it; nothing typed, nothing to write in Advanced syntax: Simple (0.54.3: the line picks the mode)
	_G.IsAltKeyDown = function() return true end; key("`", "`"); _G.IsAltKeyDown = function() return false end
	check(not UI.fzf and E.On() and not E.temp, "Alt+` in it: out of it, Simple for an empty line")
	UI:Hide(); FlushAll()
	-- Tab seen by its own key-down (a client where IsKeyDown doesn't answer)
	local was = _G.IsKeyDown
	_G.IsKeyDown = nil
	UI:Open("")
	key("TAB"); key("`", "`")
	check(UI.fzf, "Tab's own key-down counts")
	T.F.scripts.OnKeyUp(T.F, "TAB")
	key("`")
	check(not UI:IsShown(), "let go: ` closes as ever")
	FlushAll()
	-- closed: the toggle key with Tab held opens in fuzzy finding
	win(function() UI:Toggle() end)
	check(UI:IsShown() and UI.fzf, "the toggle binding with Tab held: fuzzy finding")
	UI:Hide(); FlushAll()
	-- IsKeyDown not answering (or secret): ` opens the terminal, then Tab's repeats and its release come
	_G.IsKeyDown = function() return false end
	UI:Toggle()
	check(UI:IsShown() and not UI.fzf and E.On(), "(the toggle key opened it in Simple mode)")
	key("TAB")
	check(not UI.fzf and UI.openedByToggle, "Tab still held right after opening: swallowed (no Tab of its own)")
	T.F.scripts.OnKeyUp(T.F, "TAB")
	check(UI.fzf, "Tab let go right after: it was Tab+`, fuzzy finding now")
	UI:Hide(); FlushAll()
	UI:Toggle()
	key("A", "a")
	T.F.scripts.OnKeyUp(T.F, "TAB")
	check(not UI.fzf, "something typed first: Tab let go later is just that")
	UI:Hide(); FlushAll()
	_G.IsKeyDown = was
	check(not UI.fzf and not UI.glow:IsShown() and E.On() and not E.temp, "closed: over, Simple again")
	-- the frame hidden by something else ends it too
	UI:Open(""); UI:FuzzyOnce()
	local tf = _G.TerminalFrame
	tf:Hide(); tf.scripts.OnHide(tf)
	check(not UI.fzf, "the frame hidden directly: over")
	FlushAll()
	-- .fuzzy [words]: once, from a command
	UI:Open(".fuzzy hggr"); key("ENTER"); FlushAll()
	check(UI:IsShown() and UI.fzf and T.query() == "hggr" and UI.Results()[1] and UI.Results()[1].name == "Hogger",
		".fuzzy hggr: opens fuzzy finding with the words: " .. T.query())
	UI:Hide(); FlushAll()
	-- Advanced for good: Enter takes it to Simple for this run only
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("@npc hogger is:elite >> party")
	UI:FuzzyOnce()
	check(UI.fzf and T.query() == "hogger ", "syntax dropped going in: " .. T.query())
	key("ENTER")
	check(E.On() and E.tempSimple and T.query() == "Hogger ", "Advanced player, Enter: Simple this run: " .. T.query())
	-- Alt+` then (0.44.16): Advanced for this run (it stayed Simple, refusing what it had just written)
	_G.IsAltKeyDown = function() return true end; key("`", "`"); _G.IsAltKeyDown = function() return false end
	local top = UI.Results()[1]
	check(not E.On() and not E.tempSimple and T.query():lower():find("hogger", 1, true) and top ~= E.ADVANCED_ROW,
		"handed over to Simple, then Alt+`: Advanced this run: " .. T.query() .. " / " .. tostring(top and top.name))
	UI:Hide(); FlushAll()
	check(not E.On() and not E.tempSimple and not E.temp, "closed: Advanced again")
	check(UI.FuzzyPlain(".help") == "" and UI.FuzzyPlain("sword|axe -boe rare sort:distance") == "rare ", "plain words kept: " .. UI.FuzzyPlain("sword|axe -boe rare sort:distance"))
end)

Run("Up walks every line run, whatever mode ran it (0.54.3: one mode)", function()
	E.Set(true)
	ActionLists()
	ns.db.history = {}
	local function alt(fn) _G.IsAltKeyDown = function() return true end; fn(); _G.IsAltKeyDown = function() return false end end
	UI:Open("shiny sword"); key("ENTER"); UI:Hide(); FlushAll()
	-- an Alt+` run
	UI:Open("cast frost nova"); alt(function() key("`", "`") end)
	check(T.query() == "@spell do:cast frost nova ", "(Advanced this run)")
	UI:Activate(1); UI:Hide(); FlushAll()
	check(ns.db.history[1] == "@spell do:cast frost nova", "the Advanced line is in the history: " .. tostring(ns.db.history[1]))
	-- Up: it, then the Simple one; brought back, it runs in Advanced again by itself
	UI:Open(""); key("UP")
	check(T.query() == "@spell do:cast frost nova" and E.On(), "Up: the Advanced line, searched as it is (Simple kept): " .. T.query())
	key("UP")
	check(T.query() == "shiny sword", "Up again: the Simple one: " .. T.query())
	UI:Hide(); FlushAll()
	-- closed Alt+`: the same prompt and the same Up as `
	local function Seen(open)
		open(); local first = T.query(); key("UP"); local up = T.query()
		UI:Hide(); FlushAll()
		return first .. " / " .. up
	end
	local tick = Seen(function() UI:Toggle() end)
	local altTick = Seen(function() UI:AdvancedOnce() end)
	check(altTick == tick and tick:find("shiny sword", 1, true), "opened with Alt+`: as with `: " .. altTick .. " = " .. tick)
	ns.db.history = {}
end)

Run("typing on narrows from the last keystroke's matches, with the same results", function()
	E.Set(true)
	Lists()
	local function Sig(res)
		local t = {}
		for i, e in ipairs(res) do t[i] = tostring(e.name) .. "|" .. tostring(e.detail) .. "|" .. tostring(e.catId) end
		return table.concat(t, " ; ")
	end
	local reused = 0
	for _, phrase in ipairs({ "sword", "sword sp", "rare sword", "thunder", "s" }) do
		UI:Open("")
		for k = 1, #phrase do
			local part = phrase:sub(1, k)
			UI:SetQuery(part, #part)
			local got = Sig(UI.Results())
			if UI.lastSearchNarrowed then reused = reused + 1 end
			-- the same search from scratch (then the narrowing state put back for the next letter)
			local scanWas, ovWas, catWas, autoWas = UI.lastScan, UI.lastExtra, UI.category, UI.categoryAuto
			UI.lastScan, UI.lastExtra = nil, nil
			if autoWas then UI.category, UI.categoryAuto = nil, nil end
			local fresh = Sig(UI:Search(part))
			check(got == fresh, ("'%s': narrowed = fresh (%s / %s)"):format(part, got, fresh))
			UI.lastScan, UI.lastExtra, UI.category, UI.categoryAuto = scanWas, ovWas, catWas, autoWas
		end
		UI:Hide(); FlushAll()
	end
	check(reused > 0, "the overview did reuse the last keystroke's matches: " .. reused)
	-- a list rebuilt between keystrokes: its new rows are found (not the old matches)
	UI:Open(""); UI:SetQuery("sw", 2)
	local p = ns.providers.keybinds
	p.collect = Rows({ { name = "Sheathe Sword" }, { name = "Swap Weapons" } })
	p._dirty = true
	UI:SetQuery("swa", 3)
	check(Sig(UI.Results()):find("Swap Weapons", 1, true) or Sig(UI.Results()):find("Keybind", 1, true), "a list rebuilt meanwhile is scanned in full: " .. Sig(UI.Results()))
	UI:Hide(); FlushAll()
end)

Run("Alt+` ends with the terminal however it closes; Up's history line runs as it is", function()
	E.Set(true)
	ActionLists()
	-- the frame hidden by something else (a window the press opened closes it): Simple again all the same
	UI:Open("cast frost nova")
	UI:AdvancedOnce()
	check(E.temp and not E.On(), "(Advanced this run)")
	local tf = _G.TerminalFrame
	tf:Hide(); tf.scripts.OnHide(tf) -- (as UISpecialFrames / a window opening does, not through UI:Hide)
	check(E.temp == nil and E.On(), "the frame hidden directly: Simple again")
	check(UI.lastQuery == "cast frost nova", "and Down brings back the Simple search: " .. tostring(UI.lastQuery))
	FlushAll()
	-- Advanced syntax typed: a Simple search like any (0.55.9): Down brings it back
	UI.lastQuery = "old simple search"
	UI:Open("")
	UI:SetQuery("@spell nova", 11)
	UI:Hide(); FlushAll()
	check(UI.lastQuery == "@spell nova", "Advanced syntax typed: Down brings it back: " .. tostring(UI.lastQuery))
	-- Advanced: a history line ending in a filter runs, it isn't a pick list
	ns.db.easyMode = false; UI:EasyChanged()
	ns.db.history = { "@spell is:passive" }
	UI:Open(""); T.key("UP")
	check(T.query() == "@spell is:passive" and not (UI.Results()[1] and UI.Results()[1].syntaxRow), "Up's line is searched, not a pick list")
	UI:Hide(); FlushAll()
	ns.db.history = {}
end)

Run("stamina food right after login: found once the game has loaded the food's text", function()
	E.Set(true)
	local F = ns.Filters
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
	local save = { info = C_Item.GetItemInfo, inst = C_Item.GetItemInfoInstant, spell = C_Item.GetItemSpell,
		desc = C_Spell.GetSpellDescription, stats = C_Item.GetItemStats, cached = C_Spell.IsSpellDataCached, now = _G.GetTime }
	local loaded = false
	local clock = 1000
	_G.GetTime = function() return clock end
	C_Item.GetItemInfo = function(id) if id == 201 then return "Spiced Wolf Ribs", "|Hitem:201|h", 1, 15, 10, "Consumable", "Food & Drink" end end
	C_Item.GetItemInfoInstant = function(id) return id, "Consumable", "Food & Drink", "", 1, 0, 0 end
	C_Item.GetItemSpell = function(id) return "spell", 6201 end
	-- the spell's text isn't in yet at first (the game is still loading it)
	C_Spell.GetSpellDescription = function() return loaded and "Restores 552 health. Well fed: gain 6 Stamina and Spirit for 15 min." or "" end
	C_Spell.IsSpellDataCached = function() return loaded end
	C_Item.GetItemStats = function() return {} end
	Use({ { "items", { label = "Item", aliases = { "item" }, collect = Rows({ { name = "Spiced Wolf Ribs", itemID = 201 } }) } } })
	-- the prewarm asks for your bags' consumables' text ahead of any search
	local asked, reqWas = 0, C_Spell.RequestLoadSpellData
	C_Spell.RequestLoadSpellData = function() asked = asked + 1 end
	check(F.WarmEffects(ns:GetEntries(ns.providers.items)) == 1 and asked == 1 and not F.loading, "the bags' food has its text asked for ahead of the search")
	C_Spell.RequestLoadSpellData = reqWas
	clock = clock + 2 -- (past the wait the warm-up set)
	UI:Open("stamina food")
	local first = UI.Results()
	check(not Has(first, "Spiced Wolf Ribs"), "(the food's text still loading: not yet)")
	-- the text comes in: the same search runs again by itself, from scratch
	loaded = true
	clock = clock + 2
	FlushAll()
	local res = UI.Results()
	check(Has(res, "Spiced Wolf Ribs") or (res[1] and res[1].catId == "bags"), "once loaded, the food shows without typing again: " .. Show(res))
	UI:Hide(); FlushAll()
	-- Advanced, with a ">> party" after the search: the retry still fires (the prompt isn't the searched text)
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
	loaded = false
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("stat:stamina type:food >> party")
	clock = clock + 0.01; T.Flush() -- (the refresh the opening queued for the next frame runs now, while still loading)
	check(not Has(UI.Results(), "Spiced Wolf Ribs"), "(Advanced: still loading)")
	loaded = true
	clock = clock + 2
	FlushAll()
	check(Has(UI.Results(), "Spiced Wolf Ribs"), "Advanced with >>: found once loaded: " .. Show(UI.Results()))
	UI:Hide(); FlushAll()
	E.Set(true)
	C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.GetItemSpell = save.info, save.inst, save.spell
	C_Spell.GetSpellDescription, C_Item.GetItemStats, C_Spell.IsSpellDataCached, _G.GetTime = save.desc, save.stats, save.cached, save.now
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
end)

Run("helmet among the loot: every helmet; helm upgrades: the ones that suit you (level, class, item level)", function()
	E.Set(true)
	local F = ns.Filters
	F.ClearCache()
	local save = { info = C_Item.GetItemInfo, level = _G.UnitLevel, inv = _G.GetInventoryItemLink, can = C_PlayerInfo.CanUseItem,
		det = C_Item.GetDetailedItemLevelInfo }
	local ITEMS = {
		[1] = { "Good Helm", "|Hitem:1|h", 2, 24, 18, "Armor", "Leather", 1, "INVTYPE_HEAD" },
		[2] = { "Future Helm", "|Hitem:2|h", 3, 40, 35, "Armor", "Leather", 1, "INVTYPE_HEAD" },
		[3] = { "Old Cap", "|Hitem:3|h", 1, 8, 3, "Armor", "Cloth", 1, "INVTYPE_HEAD" },
		[4] = { "Plate Helm", "|Hitem:4|h", 2, 25, 20, "Armor", "Plate", 1, "INVTYPE_HEAD" },
		[5] = { "Great Helm", "|Hitem:5|h", 4, 30, 22, "Armor", "Leather", 1, "INVTYPE_HEAD" },
		[9] = { "Worn Hood", "|Hitem:9|h", 2, 20, 15, "Armor", "Leather", 1, "INVTYPE_HEAD" },
	}
	C_Item.GetItemInfo = function(id) local t = ITEMS[tonumber(id) or 0] if t then return unpack(t) end end
	C_Item.GetDetailedItemLevelInfo = function(link) local id = tonumber(tostring(link):match("item:(%d+)")); return ITEMS[id] and ITEMS[id][4] end
	_G.UnitLevel = function() return 21 end
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9|h[Worn Hood]|h" end end
	C_PlayerInfo.CanUseItem = function(id) return id ~= 4 end -- (plate: not for you)
	local function L(name, id) return { name = name, itemID = id, detail = "Boss  Dungeon", _ltext = "dungeon boss loot drop atlasloot" } end
	Use({ { "loot", { label = "Loot", aliases = { "loot" }, collect = Rows({
		L("Good Helm", 1), L("Future Helm", 2), L("Old Cap", 3), L("Plate Helm", 4), L("Great Helm", 5) }) } } })
	ITEMS[6] = { "Kraul Helm", "|Hitem:6|h", 2, 26, 20, "Armor", "Leather", 1, "INVTYPE_HEAD" }
	ITEMS[7] = { "Rough Flask of Kings", "|Hitem:7|h", 2, 26, 20, "Armor", "Leather", 1, "INVTYPE_HEAD" }
	Use({ { "loot", { label = "Loot", aliases = { "loot" }, collect = Rows({
		L("Good Helm", 1), L("Future Helm", 2), L("Old Cap", 3), L("Plate Helm", 4), L("Great Helm", 5),
		{ name = "Kraul Helm", itemID = 6, detail = "Agathelos  Razorfen Kraul", _ltext = "agathelos razorfen kraul" },
		{ name = "Rough Flask of Kings", itemID = 7, detail = "Boss  Dungeon", _ltext = "dungeon boss loot" } }) } } })
	-- a plain slot word: every helmet
	local res = In("loot", "helmet")
	check(#res == 7, "helmet: every helmet: " .. Show(res))
	-- "upgrades": only what you can equip now, near what you wear or better
	UI:Hide(); FlushAll()
	res = In("loot", "helm upgrades")
	check(Has(res, "Good Helm") and Has(res, "Kraul Helm"), "helm upgrades: near what you wear and better: " .. Show(res))
	check(not Has(res, "Future Helm") and not Has(res, "Great Helm"), "never one above your level (Great Helm needs 22, you're 21)")
	check(not Has(res, "Old Cap"), "not ones well below what you wear")
	check(not Has(res, "Plate Helm"), "not a kind you can't wear")
	-- a level 3 with nothing worn: only what a level 3 can wear
	_G.UnitLevel = function() return 3 end
	_G.GetInventoryItemLink = function() return nil end
	UI:Hide(); FlushAll()
	res = In("loot", "helm upgrades")
	check(#res == 1 and res[1].name == "Old Cap", "a level 3: the cap only: " .. Show(res))
	-- nothing suits (a level 60 in far better gear): no helmet you'd never want
	_G.UnitLevel = function() return 60 end
	ITEMS[9][4] = 100
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9|h[Worn Hood]|h" end end
	UI:Hide(); FlushAll()
	UI:Open("helm upgrades")
	res = UI.Results()
	check(not Has(res, "Good Helm") and not Has(res, "Great Helm") and not Has(res, "Future Helm"), "none suits: none listed: " .. Show(res))
	UI:Hide(); FlushAll()
	-- an instance's shorthand: its helmets only (no name whose letters fit r f k)
	_G.UnitLevel = function() return 21 end
	res = In("loot", "rfk helm")
	check(#res == 1 and res[1].name == "Kraul Helm", "rfk helm: Razorfen Kraul's helmet only: " .. Show(res))
	check(ns.Easy.ToAdvanced("helm upgrades"):find("is:upgrade", 1, true), "Alt+`: upgrades -> is:upgrade: " .. ns.Easy.ToAdvanced("helm upgrades"))
	-- the filter never asks the server for AtlasLoot's items, and others only a few per search
	local savedCached, savedReq, savedInst = C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID, C_Item.GetItemInfoInstant
	local asks = 0
	C_Item.IsItemDataCachedByID = function() return false end
	C_Item.RequestLoadItemDataByID = function() asks = asks + 1 end
	local fit = F.GearFit()
	for i = 1, 100 do fit({ kind = "loot", itemID = 1000 + i }) end
	check(asks == 0, "loot rows the client hasn't got: never asked from the filter: " .. asks)
	for i = 1, 100 do fit({ kind = "items", itemID = 2000 + i }) end
	check(asks == F.GEAR_ASK, "other rows: at most F.GEAR_ASK asks per search: " .. asks)
	-- not equipment by the client's own data: turned away before anything is asked
	C_Item.IsItemDataCachedByID = savedCached
	C_Item.GetItemInfoInstant = function() return 1, "Consumable", "Food", "" end
	local infoWas, infos = C_Item.GetItemInfo, 0
	C_Item.GetItemInfo = function(...) infos = infos + 1 return infoWas(...) end
	check(F.GearFit()({ kind = "loot", itemID = 3001 }) == false and infos == 0, "non-equipment: no item info read")
	C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.RequestLoadItemDataByID = infoWas, savedInst, savedReq
	-- a two-hander worn: one-handers and shields are weighed against it (the off hand isn't empty)
	F.ClearCache()
	ITEMS[20] = { "Big Sword", "|Hitem:20|h", 2, 40, 20, "Weapon", "Two-Handed Swords", 1, "INVTYPE_2HWEAPON" }
	ITEMS[21] = { "Small Shield", "|Hitem:21|h", 2, 22, 20, "Armor", "Shields", 1, "INVTYPE_SHIELD" }
	local savedId = _G.GetInventoryItemID
	_G.GetInventoryItemID = function(_, slot) if slot == 16 then return 20 end end
	C_Item.GetItemInfoInstant = function(id) local t = ITEMS[id] return id, t and t[6], t and t[7], t and t[9] end
	_G.GetInventoryItemLink = function(_, slot) if slot == 16 then return "|Hitem:20|h[Big Sword]|h" end end
	check(F.GearFit()({ kind = "loot", itemID = 21 }) == false, "a shield 18 item levels below your two-hander isn't an upgrade")
	_G.GetInventoryItemID, C_Item.GetItemInfoInstant = savedId, savedInst
	-- outside the loot (your bags), a slot word is only the slot
	C_Item.GetItemInfo, _G.UnitLevel, _G.GetInventoryItemLink, C_PlayerInfo.CanUseItem = save.info, save.level, save.inv, save.can
	C_Item.GetDetailedItemLevelInfo = save.det
	F.ClearCache()
end)

Run("upgrades inside an or (helm upgrades or boots upgrades): made new each search, never kept from an earlier one", function()
	E.Set(true)
	local F = ns.Filters
	F.ClearCache()
	local save = { info = C_Item.GetItemInfo, level = _G.UnitLevel, inv = _G.GetInventoryItemLink, can = C_PlayerInfo.CanUseItem,
		det = C_Item.GetDetailedItemLevelInfo }
	local ITEMS = {
		[1] = { "Good Helm", "|Hitem:1|h", 2, 24, 18, "Armor", "Leather", 1, "INVTYPE_HEAD" },
		[2] = { "Good Boots", "|Hitem:2|h", 2, 24, 18, "Armor", "Leather", 1, "INVTYPE_FEET" },
		[9] = { "Worn Hood", "|Hitem:9|h", 2, 100, 15, "Armor", "Leather", 1, "INVTYPE_HEAD" },
		[10] = { "Worn Shoes", "|Hitem:10|h", 2, 100, 15, "Armor", "Leather", 1, "INVTYPE_FEET" },
	}
	C_Item.GetItemInfo = function(id) local t = ITEMS[tonumber(id) or 0] if t then return unpack(t) end end
	C_Item.GetDetailedItemLevelInfo = function(link) local id = tonumber(tostring(link):match("item:(%d+)")); return ITEMS[id] and ITEMS[id][4] end
	C_PlayerInfo.CanUseItem = function() return true end
	-- a level 60 in far better gear: nothing is an upgrade
	_G.UnitLevel = function() return 60 end
	_G.GetInventoryItemLink = function(_, slot)
		if slot == 1 then return "|Hitem:9|h[Worn Hood]|h" elseif slot == 8 then return "|Hitem:10|h[Worn Shoes]|h" end
	end
	Use({ { "items", { label = "Item", aliases = { "item" }, collect = Rows({
		{ name = "Good Helm", itemID = 1 }, { name = "Good Boots", itemID = 2 } }) } } })
	local res = In("items", "helm upgrades or boots upgrades")
	check(not Has(res, "Good Helm") and not Has(res, "Good Boots"), "level 60 in better gear: no upgrades: " .. Show(res))
	UI:Hide(); FlushAll()
	-- the same search after the character changed (level 21, nothing worn): the new level and gear count
	_G.UnitLevel = function() return 21 end
	_G.GetInventoryItemLink = function() return nil end
	UI.lastScan, UI.lastExtra = nil, nil
	res = In("items", "helm upgrades or boots upgrades")
	check(Has(res, "Good Helm") and Has(res, "Good Boots"), "level 21, nothing worn: both are upgrades now: " .. Show(res))
	-- a hard word reached as a plain piece is the strict filter itself (no name fallback)
	check(E.Word("upgrades") ~= E.Word("upgrades"), "upgrades: a new filter each time it's asked for")
	check(E.Word("upgrades")({ name = "Upgrades Manual", itemID = 999 }) == false, "upgrades: a name with the word isn't an upgrade")
	C_Item.GetItemInfo, _G.UnitLevel, _G.GetInventoryItemLink, C_PlayerInfo.CanUseItem = save.info, save.level, save.inv, save.can
	C_Item.GetDetailedItemLevelInfo = save.det
	F.ClearCache()
end)

Run("E.JoinPairs: two everyday words that mean one thing become one word", function()
	local w = { "Attack", "Power", "food", "spell", "power", "x" }
	E.JoinPairs(w)
	check(table.concat(w, ",") == "attack power,food,spell power,x", "pairs joined, the rest kept: " .. table.concat(w, ","))
	w = { "rare", "sword" }
	E.JoinPairs(w)
	check(table.concat(w, ",") == "rare,sword", "no pair: unchanged")
	check(E.ToAdvanced("attack power food"):find("stat:ap", 1, true), "ToAdvanced: attack power -> stat:ap: " .. E.ToAdvanced("attack power food"))
	check(E.ToAdvanced("mining trainer nearby"):find("sort:distance", 1, true), "ToAdvanced: nearest said last: " .. E.ToAdvanced("mining trainer nearby"))
	check(E.ToAdvanced("sword or axe not boe"):find("type:sword|type:axe", 1, true) and E.ToAdvanced("sword or axe not boe"):find("-is:boe", 1, true),
		"ToAdvanced: or/not pieces as filters: " .. E.ToAdvanced("sword or axe not boe"))
	-- (0.63.7, review) a kind of item turned down: written whole, as Simple mode turns it down
	check(E.ToAdvanced("linen not cloth"):find("-cloth|type:cloth", 1, true), "ToAdvanced: not cloth: " .. E.ToAdvanced("linen not cloth"))
end)

-- (0.49.2, review C2) "X without Y" is Simple mode's "not", never the group's question: "cloak without stamina" said
-- "Needs Fortitude, cloak"; a missing word with no group word nor "who" asks only when every other word names a buff
Run("\"X without Y\" stays a search, not the group's question", function()
	local Q = ns.Group.Question
	check(Q("cloak without stamina") == nil and Q("food without spirit") == nil and Q("shield without stamina") == nil
		and Q("elixir without intellect") == nil and Q("cloak needs stamina") == nil and Q("boots missing spirit") == nil,
		"an item word with without/needs/missing: a search")
	check(Q("missing stamina") and Q("needs int") and Q("who is without fortitude") and Q("party without food")
		and Q("needs blessing of kings") and Q("missing shadow protection") and Q("need flask") and Q("missing buffs"),
		"still the group's: missing stamina, needs int, who is without fortitude, party without food, a buff by its name")
	Use({ { "items", { label = "Item", aliases = { "item" }, collect = Rows({ { name = "Wolf Cloak" }, { name = "Linen Shirt" } }) } } })
	ns.db.easyMode = true
	UI:EasyChanged()
	UI.category, UI.lastExtra = nil, nil
	local res = UI:Search("cloak without stamina")
	check(UI.answerNote == nil and res[1] and res[1].name == "Wolf Cloak", "Simple: cloak without stamina lists the cloak: "
		.. tostring(UI.answerNote) .. " / " .. tostring(res[1] and res[1].name))
end)

-- (0.49.2, review G14) the examples made for you name your professions, not their trade spells (Smelting: "nearest
-- smelting trainer", "smelting skillup", "@npc trainer:smelting" found nothing)
Run("examples name your professions, not their trade spells", function()
	local rand, missing = E.rand, ns.Integrations.AddonMissing
	E.rand = function(a) return a end -- (the first of each list)
	ns.Integrations.AddonMissing = function() return false end
	Use({ { "professions", { label = "Profession", aliases = { "profession" }, collect = Rows({
		{ name = "Smelting", spellID = 2656, parentName = "Mining" }, { name = "Mining", skillLine = 186 } }) } } })
	ns:GetEntries(ns.providers.professions) -- (built, as the lists are after login: suggestions never build them, 0.53.1)
	local ok, err = pcall(function()
		local mine = table.concat(E.PersonalExamples(false), " | ") .. " | " .. table.concat(E.PersonalExamples(true), " | ")
		check(not mine:find("smelting", 1, true) and mine:find("try: mining skillup", 1, true) and mine:find("try: nearest mining trainer", 1, true),
			"Mining, not Smelting: " .. mine)
	end)
	E.rand, ns.Integrations.AddonMissing = rand, missing
	if not ok then error(err, 0) end
end)

-- (0.49.8, the player's ask) "nearest enchanting trainer" found nothing ("nearest enchant trainer" did): a profession
-- said with trainer is what they teach (trainer:enchanting finds the Journeyman Enchanter), not a word in the title
Run("a profession's trainer by what they teach", function()
	for q, want in pairs({ ["nearest enchanting trainer"] = "trainer:enchanting", ["nearest enchant trainer"] = "trainer:enchanting",
		["blacksmithing trainer"] = "trainer:blacksmithing", ["herbalism trainers"] = "trainer:herbalism",
		["nearest first aid trainer"] = "trainer:firstaid", ["mining trainer in org"] = "trainer:mining" }) do
		local a = E.ToAdvanced(q)
		check(a:find(want, 1, true) and not a:find(" enchanting ", 1, true) and not a:find(" enchant ", 1, true)
			and not a:find(" aid ", 1, true) and not a:find(" blacksmithing ", 1, true), "Alt+`: " .. q .. " -> " .. a)
	end
	local a = E.ToAdvanced("nearest enchanting supplies")
	check(not a:find("trainer:", 1, true) and a:find("enchanting", 1, true), "no trainer said: the word stays a word: " .. a)
	a = E.ToAdvanced("nearest first trainer")
	check(not a:find("trainer:first", 1, true), "\"first\" alone isn't first aid: " .. a)
	-- the search itself: the Journeyman Enchanter, nearest first; not the blacksmith
	E.Set(true)
	Use({ { "npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = Rows({
		{ name = "Elra Spellweave", key = 7001, npcID = 7001, activate = Fire("map") },
		{ name = "Tovan Brightquill", key = 7003, npcID = 7003, activate = Fire("map") },
		{ name = "Gorm Anvilhand", key = 7002, npcID = 7002, activate = Fire("map") },
		{ name = "Ardan Vey", key = 7004, npcID = 7004, activate = Fire("map") },
		{ name = "Lysa Fernwhistle", key = 7005, npcID = 7005, activate = Fire("map") },
		{ name = "Bram Huntsworth", key = 7006, npcID = 7006, activate = Fire("map") },
		{ name = "Morvek Ashgrin", key = 7007, npcID = 7007, activate = Fire("map") },
		{ name = "Selis Darrow", key = 7008, npcID = 7008, activate = Fire("map") } }) } } })
	local I = ns.Integrations
	local was = { field = I.NpcField, defs = I.NpcFlagDefs, here = I.Here, dist = I.NpcDistance, group = _G.UnitFactionGroup }
	local FIELDS = { [7001] = { subName = "Journeyman Enchanter", npcFlags = 16, friendlyToFaction = "A" },
		[7003] = { subName = "Enchanting Trainer", npcFlags = 16, friendlyToFaction = "A" },
		[7002] = { subName = "Journeyman Blacksmith", npcFlags = 16, friendlyToFaction = "A" },
		[7004] = { subName = "Master Mage", npcFlags = 16, friendlyToFaction = "A" }, -- (no "trainer" in the title)
		[7005] = { subName = "Pet Trainer", npcFlags = 16, friendlyToFaction = "A" },
		[7006] = { subName = "Hunter Trainer", npcFlags = 16, friendlyToFaction = "A" },
		[7007] = { subName = "Demon Trainer", npcFlags = 4, friendlyToFaction = "A" }, -- (sells grimoires: a vendor's flag, not a trainer's)
		[7008] = { subName = "Warlock Trainer", npcFlags = 16, friendlyToFaction = "A" } }
	local DIST = { [7001] = 30, [7003] = 90, [7002] = 10, [7004] = 55, [7005] = 70, [7006] = 5, [7007] = 80, [7008] = 3 }
	I.NpcField = function(id, f) return FIELDS[id] and FIELDS[id][f] end
	I.NpcFlagDefs = function() return { TRAINER = 16 } end
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	I.NpcDistance = function(id) return DIST[id] end
	_G.UnitFactionGroup = function() return "Alliance" end
	ns.Filters.ClearCache()
	for _, q in ipairs({ "nearest enchanting trainer", "nearest enchant trainer", "enchanting trainer nearby" }) do
		UI:Hide(); FlushAll()
		UI:Open(q)
		local res = UI.Results()
		check(res[1] and res[1].name == "Elra Spellweave" and res[2] and res[2].name == "Tovan Brightquill" and not Has(res, "Gorm Anvilhand"),
			q .. ": the enchanting trainers, nearest first: " .. Show(res))
	end
	UI:Hide(); FlushAll()
	UI:Open("nearest blacksmithing trainer")
	local res = UI.Results()
	check(res[1] and res[1].name == "Gorm Anvilhand" and #res == 1, "nearest blacksmithing trainer: the Journeyman Blacksmith: " .. Show(res))
	-- (0.49.9, the player's ask) said alone, without nearest: the nearest all the same (it listed nothing)
	for q, want in pairs({ ["blacksmithing trainer"] = "Gorm Anvilhand", ["enchanting trainer"] = "Elra Spellweave",
		["enchant trainers"] = "Elra Spellweave", ["mage trainer"] = "Ardan Vey", ["hunter pet trainer"] = "Lysa Fernwhistle",
		["pet trainer"] = "Lysa Fernwhistle", ["demon trainer"] = "Morvek Ashgrin", ["warlock pet trainer"] = "Morvek Ashgrin",
		["warlock trainer"] = "Selis Darrow" }) do
		UI:Hide(); FlushAll()
		UI:Open(q)
		res = UI.Results()
		check(res[1] and res[1].name == want and res[1].detail == DIST[res[1].key] .. " yd" and UI.action == E.ACTIONS.nearest,
			q .. " alone: the nearest, how far: " .. Show(res))
	end
	check(E.ToAdvanced("blacksmithing trainer") == "@npc trainer:blacksmithing faction:friendly sort:distance ",
		"Alt+` writes it as the nearest: " .. E.ToAdvanced("blacksmithing trainer"))
	check(E.ToAdvanced("hunter pet trainer") == "@npc trainer:pet faction:friendly sort:distance ",
		"hunter pet trainer: the pet trainers, nearest: " .. E.ToAdvanced("hunter pet trainer"))
	check(E.ToAdvanced("warlock pet trainer") == "@npc trainer:demon faction:friendly sort:distance ",
		"warlock pet trainer: the Demon Trainers, nearest: " .. E.ToAdvanced("warlock pet trainer"))
	-- "pet trainer" alone follows your class: a warlock's are the Demon Trainers ("hunter pet trainer" stays the hunters')
	local classWas = _G.UnitClass
	_G.UnitClass = function() return "Warlock", "WARLOCK" end
	UI:Hide(); FlushAll()
	UI:Open("pet trainer")
	res = UI.Results()
	check(res[1] and res[1].name == "Morvek Ashgrin" and not Has(res, "Lysa Fernwhistle"), "a warlock's pet trainer: the Demon Trainer: " .. Show(res))
	check(E.ToAdvanced("hunter pet trainer"):find("trainer:pet", 1, true), "a warlock's hunter pet trainer: still the hunters'")
	_G.UnitClass = function() return "Hunter", "HUNTER" end
	check(E.ToAdvanced("pet trainer"):find("trainer:pet", 1, true), "a hunter's pet trainer: the pet trainers")
	_G.UnitClass = classWas
	-- (review, 0.49.17) a sentence's little words go as for any everyday word; several professions: any of them; a
	-- two-word class isn't its first word's; first aid only by name; Alt+` names the NPCs a place or not
	UI:Hide(); FlushAll()
	UI:Open("the enchanting trainer")
	res = UI.Results()
	check(res[1] and res[1].name == "Elra Spellweave", "the enchanting trainer: the little word isn't searched: " .. Show(res))
	UI:Hide(); FlushAll()
	UI:Open("enchanting blacksmithing trainer")
	res = UI.Results()
	check(res[1] and res[1].name == "Gorm Anvilhand" and Has(res, "Elra Spellweave"), "two professions: either's trainers: " .. Show(res))
	check(E.ToAdvanced("mining herbalism trainer"):find("trainer:mining|trainer:herbalism", 1, true), "Alt+`: one filter, either: "
		.. E.ToAdvanced("mining herbalism trainer"))
	check(not E.ToAdvanced("demon hunter trainer"):find("trainer:", 1, true), "demon hunter trainer: words: " .. E.ToAdvanced("demon hunter trainer"))
	check(not E.ToAdvanced("firs trainer"):find("firstaid", 1, true), "firs trainer isn't first aid: " .. E.ToAdvanced("firs trainer"))
	-- "trainer" alone, or a name with it, isn't a nearest search
	UI:Hide(); FlushAll()
	UI:Open("trainer")
	check(UI.action == nil, "\"trainer\" alone: no nearest search")
	I.NpcField, I.NpcFlagDefs, I.Here, I.NpcDistance, _G.UnitFactionGroup = was.field, was.defs, was.here, was.dist, was.group
	ns.Filters.ClearCache()
end)

io.write("[easy: NPC lists nearest first by default: what was typed first (release review)]\n")
do
	local Scan, I = UI._Scan, ns.Integrations
	local was = I.RowYards
	I.RowYards = function(e) return e.d end
	local rows = {}
	for i = 1, 120 do rows[i] = { name = "Thogg Berrer " .. i, _lname = "thogg berrer " .. i, key = i, d = i * 10, _score = 4 } end
	rows[#rows + 1] = { name = "Hogger", _lname = "hogger", key = 500, d = 5000, _score = 100 }
	rows[#rows + 1] = { name = "Hogger's Cousin", _lname = "hogger's cousin", key = 501, d = 8000, _score = 6 }
	rows[#rows + 1] = { name = "Hogger Lost", _lname = "hogger lost", key = 502, _score = 6 } -- (no place known)
	local res = UI.SortAndTrim(Scan.NearDefault(rows, { cont = 1, x = 0, y = 0 }, { "hogger" }, 100))
	check(#res == 100 and res[1].name == "Hogger" and res[1].detail and res[1].detail:find("5000", 1, true)
		and res[2].name == "Hogger's Cousin" and res[3].name == "Hogger Lost" and res[4].name == "Thogg Berrer 1",
		"Hogger first (named it), then names with the word (nearest first, no place last), then the rest nearest first: "
		.. tostring(res[1] and res[1].name) .. ", " .. tostring(res[2] and res[2].name) .. ", " .. tostring(res[3] and res[3].name)
		.. ", " .. tostring(res[4] and res[4].name))
	-- a title's word: every one alike, the nearest first
	local titled = {}
	for i = 1, 5 do titled[i] = { name = "Vendor " .. i, _lname = "vendor " .. i, key = i, d = (6 - i) * 100, _score = 1 } end
	res = UI.SortAndTrim(Scan.NearDefault(titled, { cont = 1, x = 0, y = 0 }, { "reagent" }, 100))
	check(res[1].name == "Vendor 5" and res[5].name == "Vendor 1", "a title's word: the nearest first")
	-- summed up: every match counted, not the nearest 100
	local q = { kinds = { npc = true }, tokens = { "thogg" } }
	local hereWas = I.Here
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	local out = Scan.Nearest({ aggregate = { last = { kind = "count" } } }, q, rows)
	check(#out == #rows and not q.nearDefault, "summed up (| count): every match, as it is: " .. #out)
	out = Scan.Nearest({}, { kinds = { npc = true }, tokens = { "thogg" } }, rows)
	check(#out == 100, "listed: the best 100 by the default nearest: " .. #out)
	I.Here, I.RowYards = hereWas, was
end
