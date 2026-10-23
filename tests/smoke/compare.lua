-- Comparing two searches (0.66.10, the player): "| except @bank" leaves out what the other search finds, "| also @stored"
-- adds it; in plain words "... but not in my bank", "... plus my alts". Search/Pipes.lua (A.Compare, A.OtherRows,
-- A.Identity), Easy.lua (SetOp), UI/Results.lua (TakeAggregate).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local A, E, B = ns.Aggregate, ns.Easy, ns.Bar

io.write("[compare: | except and | also]\n")
do
	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	local BAGS = { { "Linen Cloth", 2589 }, { "Wool Cloth", 2592 }, { "Silk Cloth", 4306 } }
	local BANK = { { "Wool Cloth", 2592 }, { "Mageweave Cloth", 4338 } }
	local function Rows(list, where)
		return function()
			local out = {}
			for i, r in ipairs(list) do out[i] = { name = r[1], itemID = r[2], key = where .. i, text = "cloth " .. where } end
			return out
		end
	end
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = Rows(BAGS, "bags") })
	ns:RegisterProvider("bank", { label = "Bank", aliases = { "bank" }, collect = Rows(BANK, "bank") })
	ns:AliasesChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	local function Names()
		local t = {}
		for _, e in ipairs(UI.Results()) do if B.Real(e) then t[#t + 1] = tostring(e.name):match("^(%S+)") end end
		table.sort(t)
		return table.concat(t, " ")
	end
	check(A.Identity({ itemID = 5 }) == "i:5" and A.Identity({ name = "|cffffffffHogger|r" }) == "t:hogger", "what a row is")
	local spec = A.Parse({ "except @bank" }, "@item cloth")
	check(spec.wheres[1] and spec.wheres[1].except and spec.wheres[1].other == "@bank" and A.Summing(spec), "| except @bank read")
	check(A.Parse({ "except" }, "@item").bad, "| except with nothing: said")
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open(""); FlushAll()
	-- (a space after it: an @kind just typed offers the list to pick, as it does anywhere)
	UI:SetQuery("@item cloth | except @bank "); FlushAll()
	check(Names() == "Linen Silk", "in your bags, not in your bank: " .. Names())
	UI:SetQuery("@item cloth | also @bank "); FlushAll()
	check(Names() == "Linen Mageweave Silk Wool", "your bags and bank, each once: " .. Names())
	UI:SetQuery("@item cloth | except @bank wool"); FlushAll()
	check(Names() == "Linen Silk", "the other search's words: only wool left out: " .. Names())
	UI:SetQuery("@item cloth | except @bank | count"); FlushAll()
	check(tostring(UI.Results()[1] and UI.Results()[1].name):find("2", 1, true), "then counted: 2")
	check(E.Explain("@item cloth | except @bank") == "Items matching cloth, leaving out your bank", "explained: " .. tostring(E.Explain("@item cloth | except @bank")))
	-- plain words
	local rest, step = E.SetOp("cloth but not in my bank")
	check(rest == "cloth" and step == "except @bank", "but not in my bank: " .. tostring(rest) .. " / " .. tostring(step))
	check(select(2, E.SetOp("cloth plus my alts")) == "also @stored" and select(2, E.SetOp("not in my bank")) == nil
		and select(2, E.SetOp("cloth not boe")) == nil, "plus my alts; alone or another not: no comparison")
	ns.db.easyMode = true; UI:EasyChanged()
	UI:SetQuery("cloth but not in my bank"); FlushAll()
	check(Names() == "Linen Silk", "Simple mode: cloth but not in my bank: " .. Names())
	local adv = E.ToAdvanced("cloth but not in my bank")
	check(adv:find("| except @bank", 1, true), "Alt+` writes | except @bank: " .. adv)
	UI:Hide(); FlushAll()
	ns.providers, ns.providerOrder, ns.db.easyMode = saved.providers, saved.order, saved.easy
	ns:AliasesChanged(); UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
end
