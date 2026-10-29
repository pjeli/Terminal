-- (review, 0.67.12) the shell given odd and broken lines: never a Lua error, raised or printed (half-typed pipes,
-- redirects, options without values, patterns that aren't ones, huge lines)
local T = ...
local ns, check = T.ns, T.check
local FS, SH = ns.ConsoleFS, ns.Shell
local out = {}
local sh = SH.Session({ print = function(l) out[#out + 1] = FS.Strip(tostring(l)) end })
local LINES = { "", " ", "|", "| |", "ls |", "| ls", "ls >", "ls >>", "> x", "echo 'unterminated", 'echo "un', "cat", "cd ..",
	"cd ../../..", "!!", "!0", "!-1", "!999", "!xyz", "ls ;;", ";", "&&", "|| ls", "ls && && ls", "grep", "grep -", "grep -z x",
	"head -n", "head -n x", "head -n -5", "tail -n -5", "tail -n x", "sort -k", "sort -k x", "cut -d", "cut -f", "cut -f x", "awk",
	"awk '{print'", "awk 'BEGIN{x=1/0; print x}'", "awk '{print $999}'", "awk 'BEGIN{while(1){}}'", "sed", "sed s/a", "sed 's/(/x/'", "seq 1 100000", "seq 5 1",
	"seq x", "seq 1 0 5", "shuf -n", "shuf -n x", "tr", "tr a", "xargs", "xargs nope", "find / -name", "find / -name '['", "tree /", "ls -lR /npc",
	"kill", "kill 999", "kill x", "layout bogus", "split", "split x", "font 999", "font -", "font x", "theme nope", "prompt",
	"prompt nope", "alias x=", "alias =", "alias", "unalias", "unalias nope", "z", "z nope", "history -c", "history x", "pin", "pin /nope", "link",
	"link /nope", "man", "man nope", "which", "which nope", "sudo", "touch /", "rm /", "mkdir", "cd /tmp", "echo hi > a",
	"cat a", "cat /tmp/a /tmp/a", "rev", "nl", "wc -x", "uniq -c", "count", "field", "field x", "where", "where dist<", "where lvl>>3",
	"ls -l /npc | where zone==", "sum", "ping", "sleep -1", "sleep x", "date +%", "echo \\", "echo \\\\", "ls '/npc/", 'cd ""',
	string.rep("a", 5000), "ls " .. string.rep("/x", 300), "echo |cff00ff00red", "echo |Hitem:1|h[x]|h", "grep '[' /etc/motd",
	"grep '(' /etc/motd", "grep '%' /etc/motd", "grep '.*' /etc/motd", "sed 's/%/x/' /etc/motd", "echo a | sed 's/a/%1/'",
	"tr '%' x", "cut -c 5-2", "cut -c -", "ls -l -o", "ls -l -o nope", "ls -lN", "ls -lNx", "stat", "stat /nope", "file /",
	"tee", "tee /npc/x", "echo x >> /npc/y", "rm -k /tmp/a", "rm -", -- (0.68.13: an unknown option to rm) "less", "less /nope", "vim /etc/motd", "fortune", "murlocsay", "murlocsay " .. string.rep("w ", 200),
	"neofetch", "uptime", "free", "uname -a", "whoami", "hostname", "ps", "exit 5x", "true; false || echo ok", "echo $?", "echo $HOME",
	"echo *", "echo /*/", "echo /npc/*", "ls /npc/*/*", "locate", "locate [", "search", "search @nope", "nl -x", "tac /nope", "shuf /nope",
	"sum value", "count by", "count by nope", "uniq -x", "sort -x", "sort -t", "head -c 5", "seq 1 2 3 4", "echo a > /tmp/" .. string.rep("b", 300),
}
local bad = {}
for _, line in ipairs(LINES) do
	out = {}
	local ok, err = pcall(SH.Run, sh, line)
	local text = table.concat(out, "\n")
	if not ok then bad[#bad + 1] = ("[%s] ERROR %s"):format(line:sub(1, 40), tostring(err))
	elseif text:find("attempt to ", 1, true) or text:find("stack traceback", 1, true) or text:find("bad argument", 1, true)
		or text:find("malformed pattern", 1, true) or text:find("invalid capture", 1, true) or text:find("%.lua:%d+:") then
		bad[#bad + 1] = ("[%s] SAID %s"):format(line:sub(1, 40), text:sub(1, 200))
	end
end
check(#bad == 0, "odd lines never raise or print a Lua error: " .. table.concat(bad, " // "))
