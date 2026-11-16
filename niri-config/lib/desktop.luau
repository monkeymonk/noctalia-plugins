--!nonstrict
-- desktop.luau — parse freedesktop .desktop entries into launchable app
-- records; command string <-> niri bind action conversion. Faithful port of
-- lib/desktop.js (niri-config v4). Pure text parsing; the caller lists/reads
-- the files (noctalia.listDir / noctalia.readFile — both synchronous and
-- in-process, so no subprocess batching trick is needed here either).

local M = {}

M.APP_DIRS = { "/usr/share/applications", "/usr/local/share/applications", "~/.local/share/applications" }

-- Parse a single .desktop file body → entry, or nil if it shouldn't be listed.
function M.parseDesktopEntry(text)
	if not text or text == "" then
		return nil
	end
	local inEntry = false
	local e = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local l = (line:gsub("^%s+", ""):gsub("%s+$", ""))
		if l:sub(1, 1) == "[" then
			inEntry = (l == "[Desktop Entry]")
		elseif inEntry and l ~= "" and l:sub(1, 1) ~= "#" then
			local eq = l:find("=", 1, true)
			if eq then
				local key = (l:sub(1, eq - 1):gsub("%s+$", ""))
				local val = (l:sub(eq + 1):gsub("^%s+", ""))
				-- ignore locale-suffixed keys (Name[fr]=…)
				if not key:find("[", 1, true) then
					e[key] = val
				end
			end
		end
	end
	if e.Type and e.Type ~= "Application" then
		return nil
	end
	if e.NoDisplay == "true" or e.Hidden == "true" then
		return nil
	end
	if not e.Name or not e.Exec then
		return nil
	end
	return {
		name = e.Name,
		exec = M.cleanExec(e.Exec),
		rawExec = e.Exec,
		icon = e.Icon or "",
		terminal = e.Terminal == "true",
		comment = e.Comment or "",
	}
end

-- Strip field codes (%U %u %F %f %i %c %k %D %v %m) and unescape %%.
function M.cleanExec(exec)
	if not exec or exec == "" then
		return ""
	end
	local out = (exec:gsub("%%[fFuUickdDnNvm]", ""))
	out = (out:gsub("%%%%", "%%"))
	out = (out:gsub("%s+", " "))
	return (out:gsub("^%s+", ""):gsub("%s+$", ""))
end

local SHELL_META = "[|&;<>$`(){}*?~\"']"

-- Does the command need a shell (metacharacters)? Then prefer spawn-sh.
function M.needsShell(cmd)
	return cmd:find(SHELL_META) ~= nil
end

-- Tokenize a simple command into argv (no shell features). Honors basic quotes.
function M.tokenize(cmd)
	local out = {}
	local cur = {}
	local q = nil
	for i = 1, #cmd do
		local c = cmd:sub(i, i)
		if q then
			if c == q then
				q = nil
			else
				table.insert(cur, c)
			end
		elseif c == '"' or c == "'" then
			q = c
		elseif c == " " then
			if #cur > 0 then
				table.insert(out, table.concat(cur))
				cur = {}
			end
		else
			table.insert(cur, c)
		end
	end
	if #cur > 0 then
		table.insert(out, table.concat(cur))
	end
	return out
end

-- Build a niri action ({name, args}) from a command string.
function M.commandToAction(cmd)
	local c = (cmd or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if c == "" then
		return nil
	end
	if M.needsShell(c) then
		return { name = "spawn-sh", args = { c } }
	end
	return { name = "spawn", args = M.tokenize(c) }
end

return M
