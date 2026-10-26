-- The parse corpus's readings, part 3 of 8 (docs/FRONT_END.md, Phase 0): tests/parse_golden.lua reads this part of
-- tests/parse_corpus.txt and compares it with tests/parse_golden.txt.
local T = ...
local G = assert(loadfile("Terminal/tests/parse_golden.lua"))(T, 3, 8)
G.Run()
