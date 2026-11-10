-- Alt+` and .explain over the parse corpus, part 2 of 2 (1.3.0: split, the whole corpus had reached one test file's
-- 20M-instruction budget): tests/printers.lua reads this part of tests/parse_corpus.txt.
local T = ...
assert(loadfile("Terminal/tests/printers.lua"))(T, 2, 2)
