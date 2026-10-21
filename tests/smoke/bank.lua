-- (0.62.1, the player: "@bank as just MY bank (current player's bank) separate from @stored (which is everyone on alts as
-- well)"; "'what is in my bank' should have a suitable answer")
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L = ns.L
io.write("[bank: this character's bank, apart from @stored]\n")
local S = ns.Stored
local P = ns.providers
check(P.bank and ns:ResolveProvider("bank") == P.bank and ns:ResolveProvider("mybank") == P.bank, "@bank is its own list")
check(ns:ResolveProvider("stored") == P.stored and ns:ResolveProvider("alts") == P.stored and ns:ResolveProvider("banks") == P.stored,
	"@stored, @alts, @banks: everyone's")
local function H(who, where, n, mine) return { key = who .. "|" .. where, who = who, where = where, count = n, mine = mine } end
local ROWS = {
	{ name = "Linen Cloth", id = 2589, holders = { H("Me", "bank", 12, true), H("Alt", "bags", 40) } },
	{ name = "Wool Cloth", id = 2592, holders = { H("Alt", "bank", 8) } },
	{ name = "Silk Cloth", id = 4306, holders = { H("Me", "bank", 3, true), H("Me", "mail", 5, true) } },
}
local saveStored, saveSource = P.stored, S.Source
ns:RegisterProvider("stored", { label = "Alts & bank", aliases = { "stored", "alts" }, explicit = true, collect = function()
	local out = {}
	for i, r in ipairs(ROWS) do
		local hs, total = {}, 0
		for _, h in ipairs(r.holders) do hs[h.key] = h; total = total + h.count end
		out[i] = { name = r.name, key = r.id, itemID = r.id, holders = hs, total = total, detail = "x" .. total }
	end
	return out
end })
S.Source = function() return "Syndicator" end
ns:AliasesChanged()
P.bank._dirty = true
local bank = ns:GetEntries(P.bank)
local by = {}
for _, e in ipairs(bank) do by[e.name] = e end
check(#bank == 2 and by["Linen Cloth"] and by["Silk Cloth"] and not by["Wool Cloth"], "@bank: only what's in your own bank (not an alt's)")
check(by["Linen Cloth"].total == 12 and by["Silk Cloth"].total == 3, "its count: the bank's (not your alt's 40, your mail's 5)")
check(by["Linen Cloth"].kind == "bank" and by["Linen Cloth"].detail:find("x12", 1, true), "a row of its own kind: " .. by["Linen Cloth"].detail)
-- "what is in my bank"
local Q = ns.MyBankQ
for _, s in ipairs({ "what is in my bank", "What's in my bank?", "my bank", "bank items", "show my bank" }) do
	check(Q.Question(s) ~= nil, "asked: " .. s)
end
check(Q.Question("bank") == nil and Q.Question("nearest bank") == nil and Q.Question("my bank linen") == nil, "\"bank\" is still the banker")
check(ns.QuestionToAdvanced("what is in my bank") == "@bank ", "as Advanced: " .. tostring(ns.QuestionToAdvanced("what is in my bank")))
local easy = ns.db.easyMode
for _, simple in ipairs({ true, false }) do
	ns.db.easyMode = simple; UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	UI:Open("what is in my bank"); FlushAll()
	local names = {}
	for _, e in ipairs(UI.Results()) do names[#names + 1] = e.name end
	check(table.concat(names, " | ") == "Linen Cloth | Silk Cloth" and UI.answerNote and UI.answerNote:find(L["Your bank"], 1, true),
		(simple and "Simple" or "Advanced") .. ": what is in my bank: " .. table.concat(names, " | ") .. " / " .. tostring(UI.answerNote))
	UI:Hide(); FlushAll()
end
-- no bag addon keeping it: said so
S.Source = function() return nil end
local rows = Q.Answer()
check(#rows == 1 and rows[1].name:find("Syndicator", 1, true), "no bag addon: says which keep it")
S.Source = saveSource
ns.db.easyMode = easy; UI:EasyChanged()
P.stored = saveStored
ns:AliasesChanged()
P.bank._dirty = true
UI.lastScan, UI.lastExtra = nil, nil
