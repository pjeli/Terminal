-- (review, 0.53.6) every plain-word question reads its line through ns.QuestionText: a "-word" or "!word" (the search's
-- "not") is never a question, nor a line with a "not" word the question doesn't read itself. Before, "party -dead",
-- "party not dead" and "mail not cod" listed the very thing left out, and "-mc", "-kobold", "-frost", "-leather"
-- narrowed to it.
local T = ...
local ns, check = T.ns, T.check

io.write("[questions: ns.QuestionText, not-words]\n")
local Q = ns.QuestionText
check(Q("What's   dropped?") == "whats   dropped ", "lower case, apostrophes dropped, punctuation as spaces: " .. tostring(Q("What's   dropped?")))
check(Q("@npc dead") == nil and Q("q:rare") == nil and Q("a > mats") == nil and Q("x | count") == nil and Q(".help") == nil
	and Q("/who") == nil and Q("-dead") == nil and Q(nil) == nil, "Advanced syntax, a command, a slash: never a question")
check(Q("party -dead") == nil and Q("party !dead") == nil, "a -word or !word: the search's not")
check(Q("half-elf quests") ~= nil, "a hyphen inside a word is no not")
check(Q("party not dead") == nil and Q("mail without cod") == nil and Q("mail no cod") == nil and Q("x except y") == nil,
	"a not-word the question doesn't read: the search's")
check(Q("who is without fortitude", { without = true }) ~= nil, "one it reads itself: kept")

local function Is(f, s) local ok, q = pcall(f, s) return ok and q ~= nil end
local G, M, LK, SP, MR, PQ = ns.Group, ns.Mail, ns.Lockouts, ns.Spells, ns.MissingRecipes, ns.GroupQuests
check(Is(G.Question, "who is dead") and not Is(G.Question, "party not dead") and not Is(G.Question, "party -dead")
	and not Is(G.Question, "who is not in range"), "the group: dead asked, not-dead left to the search")
check(Is(G.Question, "who is without fortitude"), "the group: \"without\" is its own word (missing a buff)")
check(Is(M.Question, "cod mail") and not Is(M.Question, "mail -cod") and not Is(M.Question, "mail not cod")
	and not Is(M.Question, "mail without cod"), "mail: COD asked, not-COD left to the search")
check(Is(LK.Question, "my lockouts") and not Is(LK.Question, "lockouts -mc"), "lockouts: -mc left to the search")
check(Is(SP.Question, "spells not on my bars") and not Is(SP.Question, "spells -frost not on my bars"),
	"spells: \"not on my bars\" is its own; -frost left to the search")
check(Is(MR.Question, "recipes i can learn") and not Is(MR.Question, "recipes i can learn -leather"), "recipes: -leather left to the search")
check(Is(PQ.Question, "party quests") and not Is(PQ.Question, "party quests -kobold") and not Is(PQ.Question, "quests not shared"),
	"party quests: -kobold and not-shared left to the search")
check(Is(ns.LootLog.Question, "what's dropped"), "\"what's dropped\" (whats) still the loot log's")
