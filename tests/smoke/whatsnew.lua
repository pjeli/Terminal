-- What's new in the empty prompt after an update (1.7.5, the player's pick from the suggestions: the login's chat line
-- is easily lost): "try: .changelog (what's new in <version>)", until the changelog is opened or typed over.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L, E, CL = ns.L, ns.Easy, ns.Changelog

io.write("[whatsnew: the empty prompt says what's new after an update]\n")
do
	local db = ns.db
	local was = { seen = db.versionSeen, newsFor = db.newsFor, newsSeen = db.newsSeen, history = db.history, version = ns.version,
		print = ns.Print, suggest = ns.Theme.Get().suggest }
	ns.Print = function() end
	ns.Theme.Get().suggest = true
	ns.version = "9.9.9"
	local LINE = "try: .changelog (" .. L["what's new in %s"]:format("9.9.9") .. ")"

	-- a fresh install: nothing new to say (the tour comes first)
	db.versionSeen, db.newsFor, db.newsSeen, db.history = nil, nil, nil, {}
	local tourWas = db.tourOffered
	db.tourOffered = nil
	CL.Announce()
	check(CL.NewsLine() == nil and E.NextExample() ~= LINE, "a fresh install: no what's new")
	db.tourOffered = tourWas

	-- an update: the first suggestion, Shift+Right writes .changelog
	db.versionSeen, db.newsFor, db.newsSeen, db.history = "9.9.8", nil, nil, { "linen" }
	check(CL.Announce() == true and CL.NewsLine() == LINE, "updated: what's new to say: " .. tostring(CL.NewsLine()))
	UI:Open(""); FlushAll()
	check(E.Example() == LINE and E.newsShown and UI:SuggestionText() == ".changelog",
		"the empty prompt says it; Shift+Right writes .changelog: " .. tostring(E.Example()))
	-- Enter on it: the changelog
	UI:Activate(nil, {}); FlushAll()
	check(CL.IsShown() and db.newsSeen == "9.9.9" and CL.NewsLine() == nil, "Enter: the changelog opens, what's new read")
	CL.Close(); FlushAll()
	UI:HideNow(); FlushAll()
	UI:Open(""); FlushAll()
	check(E.Example() ~= LINE, "read: not said again")
	UI:HideNow(); FlushAll()

	-- typed over: passed over for good
	db.newsSeen = nil
	UI:Open(""); FlushAll()
	check(E.Example() == LINE, "(said again for this test)")
	UI:SetQuery("linen", 5); FlushAll()
	check(db.newsSeen == "9.9.9" and CL.NewsLine() == nil, "typed over: not said again")
	UI:HideNow(); FlushAll()
	-- another update: said again
	db.versionSeen = "9.9.9"
	ns.version = "9.9.10"
	CL.Announce()
	check(CL.NewsLine() == "try: .changelog (" .. L["what's new in %s"]:format("9.9.10") .. ")", "the next update: said again")

	db.versionSeen, db.newsFor, db.newsSeen, db.history = was.seen, was.newsFor, was.newsSeen, was.history
	ns.version, ns.Print, E.newsShown = was.version, was.print, nil
	ns.Theme.Get().suggest = was.suggest
	UI:HideNow(); FlushAll()
end
