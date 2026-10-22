-- 0.65.x review (0.65.10): "nearest mailbox" turned round on the bar: "farthest mailbox", not "mailbox".
-- review B: "nearest mailbox" then the bar's Distance picked to turn it round (farthest)
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local E, B, I = ns.Easy, ns.Bar, ns.Integrations
local saved = { providers = ns.providers, order = ns.providerOrder, map = _G.C_Map }
local function Show(res)
	local t = {}
	for i = 1, math.min(#res, 8) do t[i] = tostring(res[i].name) .. (rawget(res[i], "_dist") and ("@" .. math.floor(res[i]._dist)) or "") end
	return table.concat(t, " | ")
end
local ok, err = pcall(function()
	_G.C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return { x = 0.30, y = 0.80 } end,
		GetWorldPosFromMapPos = function(map, p) return map == 1429 and 1 or 2, { x = p.x * 1000, y = p.y * 1000 } end }
	I._.ResetDistances()
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("mailbox", { label = "Mailbox", aliases = { "mailbox", "mailboxes" }, explicit = true, collect = function()
		return { { name = "Mailbox", key = 1, wcont = 1, wx = 310, wy = 790, zone = "Goldshire" },
			{ name = "Mailbox", key = 2, wcont = 1, wx = 600, wy = 100, zone = "Stormwind" },
			{ name = "Mailbox", key = 3, wcont = 2, wx = 0, wy = 0, zone = "Far" } }
	end })
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function() return { { name = "Hearthstone", key = 6948, itemID = 6948 } } end })
	UI.lastScan = nil
	E.Set(true)
	B.Reset()
	UI:Open("nearest mailbox"); FlushAll()
	io.write("nearest mailbox: " .. Show(UI.Results()) .. "\n")
	local dist
	for _, o in ipairs(B.Options("sort")) do if o.id == "distance" then dist = o end end
	io.write("bar offers Distance: " .. tostring(dist and dist.on) .. " typed=" .. tostring(dist and dist.typed) .. "\n")
	B.Pick("sort", "distance"); FlushAll()
	local rows = Show(UI.Results())
	io.write("after Pick: line='" .. tostring(T.query()) .. "' bar=" .. tostring(B.state.sort) .. " rows=" .. rows .. "\n")
	check(rows:find("Mailbox", 1, true), "turning 'nearest mailbox' round on the bar: the mailboxes are gone: " .. rows)
	UI:Hide(); FlushAll(); B.Reset()
	UI:Open("farthest mailbox"); FlushAll()
	io.write("farthest mailbox: " .. Show(UI.Results()) .. "\n")
	B.Pick("sort", "distance"); FlushAll()
	rows = Show(UI.Results())
	io.write("after Pick: line='" .. tostring(T.query()) .. "' bar=" .. tostring(B.state.sort) .. " rows=" .. rows .. "\n")
	check(rows:find("Mailbox", 1, true), "turning 'farthest mailbox' round on the bar: the mailboxes are gone: " .. rows)
end)
_G.C_Map = saved.map; I._.ResetDistances()
ns.providers, ns.providerOrder = saved.providers, saved.order
ns:AliasesChanged(); UI.lastScan = nil; ns.Bar.Reset()
ns.db.easyMode = false; UI:EasyChanged(); UI:Hide(); FlushAll()
if not ok then check(false, "mailbox_flip: " .. tostring(err)) end
