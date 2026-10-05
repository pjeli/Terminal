-- Core, UI, Fuzzy, Highlight, Secure and Debug review fixes (0.36.x): allocation and repaint
-- savings that must not change what shows, and a few behaviours they touched.
local T = ...
local ns, UI, S, F, check, log = T.ns, T.UI, T.S, T.F, T.check, T.log
local Fuzzy, H = ns.Fuzzy, ns.Highlight

do -- rows listed without a search share one empty position table (no table per row)
	local NO = UI.NO_POS
	check(type(NO) == "table" and next(NO) == nil, "UI.NO_POS is an empty table")
	local out = UI:WordSearch(UI:CommandEntries(), "")
	local shared = #out > 1
	for _, e in ipairs(out) do if e._pos ~= NO then shared = false end end
	check(shared, "a mode's whole list (no word yet): every row's _pos is the shared table")
	UI:Open("@item")
	shared = #UI.Results() > 0
	for _, e in ipairs(UI.Results()) do if not e.raw and e._pos ~= NO then shared = false end end
	check(shared, "@kind alone: every row's _pos is the shared table")
	UI:Hide()
	ns:Bump("items:6948") -- (a recent pick: the empty terminal lists it)
	UI:Open("")
	shared = false
	for _, e in ipairs(UI.Results()) do if e.freqKey == "items:6948" then shared = e._pos == NO end end
	check(shared, "the empty terminal's recent picks: _pos is the shared table")
	check(next(NO) == nil, "nothing wrote into the shared table")
	UI:Hide()
end

do -- moving the selection repaints only the selection, not every row; the tooltip isn't rebuilt
	UI:Open("e")
	check(#UI.Results() > 2, "enough results to move through")
	local renders = 0
	local realRender = UI.Render
	UI.Render = function(...) renders = renders + 1; return realRender(...) end
	UI:Move(1)
	check(renders == 0 and UI.Selected() == 2, "Down: no full render, selection on row 2 (" .. renders .. " renders)")
	check(UI.selBar.shown ~= false, "the selection band is placed")
	if ns.Theme.Animation() then check(UI.motion.shown == true, "the band glides (the motion loop runs)") end
	local r2 = UI.rows[3]
	r2.scripts.OnEnter(r2)
	check(renders == 0 and UI.Selected() == 3, "hovering a row: selection follows without a full render")
	UI:Move(100)
	check(renders == 1, "a move that scrolls the list still redraws the rows")
	UI.Render = realRender
	UI:Hide()
	-- tooltip: the same row still selected and its tooltip up: SetHyperlink isn't called again
	UI:Open("hearthstone")
	local tt = _G.TerminalTooltip
	local sets = 0
	local base = tt.SetHyperlink
	tt.SetHyperlink = function(_, l) sets = sets + 1 end
	UI:UpdateTooltip(); UI:UpdateTooltip()
	check(tt.shown == true and sets == 0, "an unchanged tooltip isn't rebuilt (" .. sets .. " SetHyperlink calls)")
	UI:Open("linen")
	check(sets == 1, "another row: the tooltip is built again")
	tt.SetHyperlink = base
	UI:Hide()
	check(tt.shown == false, "and it hides with the terminal")
end

do -- the click catcher: an unchanged hover keeps its macros (no recompute per render), quiet tracing
	local calls = 0
	local realCM = S.ClickMacro
	S.ClickMacro = function(...) calls = calls + 1; return realCM(...) end
	UI:Open("wolves across")
	local row = UI.rows[1]
	row.GetLeft, row.GetBottom, row.GetEffectiveScale = function() return 100 end, function() return 300 end, function() return 1 end
	UIParent.GetEffectiveScale = function() return 1 end
	UI:PlaceCatcher(1)
	local c = UI.catcher
	check(c and c.shown == true and c.entry == UI.Results()[1], "catcher laid over the quest row")
	local after = calls
	check(after > 0, "the row's click macro was worked out")
	UI:PlaceCatcher(1)
	UI:Render()
	check(calls == after and c.shown == true and c.entry == UI.Results()[1], "the same row again (hover, render): macros kept, only re-anchored (" .. (calls - after) .. " recomputes)")
	c.lastPoint = nil
	UI:PlaceCatcher(1)
	check(c.lastPoint ~= nil, "it still follows its row")
	S.ClickMacro = realCM
	row.GetLeft, row.GetBottom, row.GetEffectiveScale = nil, nil, nil
	UIParent.GetEffectiveScale = nil
	UI:Hide(); T.FlushAll()
	-- character tabs: traced when armed or clicked, not while the pointer rests on a row
	local savedCF, savedMicro = _G.CharacterFrame, _G.CharacterMicroButton
	_G.CharacterMicroButton = _G.CharacterMicroButton or T.Obj("Button")
	_G.CharacterFrame = T.Obj("Frame"); CharacterFrame.shown = false
	CharacterFrame.ModeTabs = { Tabs = { { frameName = "ReputationFrame" } } }
	local trace = ns.Debug.trace
	local n = #trace
	local m = S.ClickMacro({ click = S.REP_CLICK }, nil, true)
	check(m == '/run ToggleCharacter("ReputationFrame", true)', "quiet: the macro is still worked out: " .. tostring(m))
	check(#trace == n and S.quiet == nil, "quiet: no trace lines for a resting pointer (" .. (#trace - n) .. ")")
	S.ClickMacro({ click = S.REP_CLICK }, nil)
	check(#trace > n, "a press traces the tab's steps as before")
	_G.CharacterFrame, _G.CharacterMicroButton = savedCF, savedMicro
end

do -- narrowing: one more word still scores only the last matches; stale scans are dropped
	UI.lastScan = nil
	UI:Search("wolves"); UI:Search("wolves")
	check(UI.lastSearchNarrowed, "the same words again: narrowed from the last scan")
	local fresh = T.names(UI:Search("wolves across"))
	UI.lastScan = nil
	local full = T.names(UI:Search("wolves across"))
	local same = true
	for k in pairs(fresh) do if not full[k] then same = false end end
	for k in pairs(full) do if not fresh[k] then same = false end end
	check(same and fresh["Wolves Across the Border"], "an added word: the same results either way")
	UI:Search("wolves")
	UI:Search("wolves across")
	check(UI.lastSearchNarrowed, "an added word narrows (every match had the first word)")
	UI:Search("wolves acrozz")
	check(not UI.lastSearchNarrowed, "a different second word: a full scan")
	UI:Search("wolves")
	ns.entriesGen = ns.entriesGen + 1 -- (a list was rebuilt or freed)
	UI:Search("wolvesa")
	check(not UI.lastSearchNarrowed and UI.lastScan and UI.lastScan.gen == ns.entriesGen, "a stale scan isn't reused, and is replaced")
	UI:Open("wolves")
	check(UI.lastScan ~= nil, "a search keeps its scan")
	UI:Hide()
	check(UI.lastScan == nil, "closing drops it (its rows may be freed lists')")
	check(UI:Completion() == nil or true, "the completion memo survives a hide without error")
end

do -- Tab completion of a shared start never cuts inside a letter (Cyrillic shares lead bytes)
	local a, b = "рыбалка", "рыбак"
	ns:RegisterCommand(a, { desc = "x", run = function() return {} end })
	ns:RegisterCommand(b, { desc = "x", run = function() return {} end })
	UI:Open(".ры")
	local got = UI:Completion()
	check(got == ".рыба", "the shared start is whole letters: " .. tostring(got))
	UI:Hide()
	for _, name in ipairs({ a, b }) do
		ns.commands[name] = nil
		for i = #ns.commandOrder, 1, -1 do if ns.commandOrder[i] == name then table.remove(ns.commandOrder, i) end end
	end
end

do -- @kind lookup: one lowercase map, not every alias lowercased per call; kept up to date
	local items = ns.providers.items
	check(ns:ResolveProvider("ITEM") == items and ns:ResolveProvider("items") == items, "aliases and ids resolve")
	local lowers = 0
	local realLower = ns.Lower
	ns.Lower = function(...) lowers = lowers + 1; return realLower(...) end
	ns:ResolveProvider("item")
	check(lowers == 1, "a lookup lowercases only the token (" .. lowers .. " calls)")
	ns.Lower = realLower
	table.insert(items.aliases, "zzalias")
	ns:AliasesChanged()
	check(ns:ResolveProvider("ZZALIAS") == items, "an alias added later is found after AliasesChanged")
	table.remove(items.aliases)
	ns:AliasesChanged()
	check(ns:ResolveProvider("zzalias") == nil, "and gone once removed")
	check(ns:ResolveProvider("ite") == items, "a prefix of an id still resolves")
end

do -- compact rows of a kind never picked aren't read for their kind while scoring
	local kindReads = 0
	local p = { label = "CK", aliases = { "ck" }, explicit = true }
	local mt = ns:CompactMeta(p)
	local inner = mt.__index
	mt.__index = function(t, k) if k == "kind" then kindReads = kindReads + 1 end return inner(t, k) end
	p.collect = function()
		local out = {}
		for i = 1, 50 do out[i] = setmetatable({ name = "Compact Foo " .. i, key = i, _compact = true }, mt) end
		return out
	end
	ns:RegisterProvider("ck", p)
	ns:GetEntries(p)
	kindReads = 0
	local res = UI:Search("@ck foo")
	check(#res >= 50, "the compact rows match")
	check(kindReads == 0, "scoring them read no row's kind (" .. kindReads .. " reads)")
	ns.providers.ck = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "ck" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
end

do -- the letters lit up are the ones that ranked the row: a needle found as-is is that run
	local s, pos = Fuzzy.match("ab", "xab a-b")
	check(pos and pos[1] == 2 and pos[2] == 3, "the substring's letters, not a scattered match's: " .. tostring(pos and pos[1]) .. "," .. tostring(pos and pos[2]))
	check(s and math.abs(s - Fuzzy.score("ab", "xab a-b")) < 1e-9, "and its score is the ranking score")
	local s2, pos2 = Fuzzy.match("wolf", "wolf")
	check(s2 == 100 and pos2 and #pos2 == 4, "an exact match still scores 100")
	check(Fuzzy.match("wolf", "woof") == nil, "no match stays nil")
	local s3, pos3 = Fuzzy.match("wf", "wolf")
	check(s3 and pos3 and pos3[1] == 1 and pos3[2] == 4 and math.abs(s3 - Fuzzy.score("wf", "wolf")) < 1e-9, "a scattered match still finds its letters, with the ranking score")
end

do -- highlights: one update function for all, and a target already glowing gets no second glow
	local t1, t2 = T.Obj("Frame"), T.Obj("Frame")
	t1.shown, t2.shown = true, true
	H:Clear()
	local g1 = H:Show(t1)
	local again = H:Show(t1)
	check(g1 and again == g1, "the same target: the one glow starts over, no second one")
	local g2 = H:Show(t2)
	check(g2 ~= g1 and g1.scripts.OnUpdate == g2.scripts.OnUpdate, "glows share their OnUpdate")
	H:Clear()
	check(g1.shown == false and g2.shown == false, "cleared")
end

do -- a proxy button clicks the current button of that name, not the one from when it was made
	_G.ZzProxyTarget = T.Obj("Button")
	local p = S.Proxy("ZzProxyTarget")
	check(p and p.attrs.clickbutton == _G.ZzProxyTarget, "proxy clicks the button")
	local old = _G.ZzProxyTarget
	_G.ZzProxyTarget = T.Obj("Button")
	check(S.Proxy("ZzProxyTarget") == p and p.attrs.clickbutton == _G.ZzProxyTarget and p.attrs.clickbutton ~= old, "the button made anew: the proxy points at it")
	check(S.Arm({ button = "ZzProxyTarget" }) and S.armed == "ZzProxyTarget", "and arms")
	S.Disarm()
	_G.ZzProxyTarget = nil
end

do -- Terminal's own blocked call repeating: one record with a count, one chat line
	local D = ns.Debug
	for i = #D.events, 1, -1 do D.events[i] = nil end
	local f = D.frame
	local mark = #log
	for _ = 1, 50 do f.scripts.OnEvent(f, "ADDON_ACTION_BLOCKED", ns.name, "ZzBlocked()") end
	check(#D.events == 1 and D.events[1].times == 50 and D.events[1].stack ~= nil, "50 blocks of one call: one record (x50) with its stack")
	local printed = 0
	for i = mark + 1, #log do if log[i]:find("blocked ZzBlocked()", 1, true) then printed = printed + 1 end end
	check(printed == 1, "the chat line is printed once (" .. printed .. ")")
	check(table.concat(D.Describe(D.events[1]), " "):find("(x50)", 1, true) ~= nil, "the log says how many")
	f.scripts.OnEvent(f, "ADDON_ACTION_BLOCKED", ns.name, "ZzOther()")
	check(#D.events == 2, "another call: its own record")
	for i = #D.events, 1, -1 do D.events[i] = nil end
end

do -- prewarm: a provider registered after the queue was made is queued too (AtlasLoot, late)
	local W = ns.warm
	local savedQ, savedSeen, savedDone, savedTries = W.queue, W.seen, W.done, W.tries
	W.queue, W.tries, W.seen, W.done = {}, {}, #ns.providerOrder, true
	ns:RegisterProvider("warmlate", { label = "WL", aliases = { "warmlate" }, explicit = true,
		collect = function() return { { name = "Late thing" } } end })
	UI:Hide(); T.FlushAll()
	ns.background = 0
	ns:PrewarmStep()
	check(ns.providers.warmlate._entries and ns.providers.warmlate._entries[1].name == "Late thing", "the late list is built by the prewarm")
	ns.providers.warmlate = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "warmlate" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
	W.queue, W.seen, W.done, W.tries = savedQ, savedSeen, savedDone, savedTries
end

do -- keys shared by the drawn prompt and the real box: Ctrl+U clears through SetQuery, deletes over a selection
	UI:Open("hearthstone")
	UI.anchor, UI.cursor = 0, 6
	T.key("BACKSPACE")
	check(T.query() == "stone" and UI.cursor == 0 and UI.anchor == nil, "Backspace over a selection removes it: " .. T.query())
	UI:SetQuery("hearthstone", 11)
	UI.anchor, UI.cursor = 6, 11
	T.key("DELETE")
	check(T.query() == "hearth" and UI.cursor == 6, "Delete over a selection removes it: " .. T.query())
	T.withCtrl(function() T.key("N") end)
	check(UI.Selected() == 2 or #UI.Results() < 2, "Ctrl+N moves down")
	T.withCtrl(function() T.key("P") end)
	check(UI.Selected() == 1, "Ctrl+P moves up")
	-- the real text box: the same keys
	UI:EnterEdit()
	T.withCtrl(function() UI.edit.scripts.OnKeyDown(UI.edit, "J") end)
	check(UI.Selected() == 2 or #UI.Results() < 2, "box: Ctrl+J moves down")
	UI.edit.scripts.OnKeyDown(UI.edit, "PAGEUP")
	check(UI.Selected() == 1, "box: PageUp moves to the top")
	T.withCtrl(function() UI.edit.scripts.OnKeyDown(UI.edit, "U") end)
	check(T.query() == "" and UI.cursor == 0, "box: Ctrl+U clears the query through SetQuery")
	UI:Hide(); T.FlushAll()
end
