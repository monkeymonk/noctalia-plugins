--!nonstrict
-- scripts.luau — templates + listing for user-managed niri helper scripts
-- that live in <config-dir>/scripts/ and are referenced from binds as
-- spawn "name". Faithful port of lib/scripts.js (niri-config v4). The
-- listing half is used by phase 1 (Shortcuts tab's app/script picker); the
-- template-building half is unused until the deferred Scripts tab (phase 2)
-- but kept here since it has zero UI dependency and nothing about it would
-- change when that tab is built.

local M = {}

function M.scriptsDir(configDir)
	return configDir .. "/scripts"
end

-- argv for a shell listing scripts with their executable flag
-- ("<x|->\t<name>\n…"), run via noctalia.runAsync.
function M.listCmd(dir)
	return {
		"sh",
		"-c",
		'd="$1"; [ -d "$d" ] || exit 0; for f in "$d"/*; do [ -f "$f" ] || continue; '
			.. 'printf "%s\\t%s\\n" "$([ -x "$f" ] && echo x || echo -)" "$(basename "$f")"; done',
		"_",
		dir,
	}
end

function M.parseList(text, dir)
	local out = {}
	if not text then
		return out
	end
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		if line ~= "" then
			local tab = line:find("\t", 1, true)
			if tab then
				local exec = line:sub(1, tab - 1) == "x"
				local name = line:sub(tab + 1)
				if name ~= "" then
					table.insert(out, { name = name, executable = exec, path = dir .. "/" .. name })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

-- ── templates (for the deferred Scripts tab) ────────────────────────────

function M.blankTemplate()
	return "#!/usr/bin/env bash\nset -euo pipefail\n\n"
end

function M.shQuote(s)
	return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

-- Focus an existing window by app-id, otherwise spawn the command (the
-- practical "app toggle" under niri). Uses python3 for robust JSON parsing.
function M.focusOrSpawnTemplate(appId, command)
	appId = (appId and appId ~= "") and appId or "APP_ID"
	command = (command and command ~= "") and command or "COMMAND"
	return "#!/usr/bin/env bash\n"
		.. "# Focus the window matching app-id, or launch it if not running.\n"
		.. "set -euo pipefail\n\n"
		.. "app_id="
		.. M.shQuote(appId)
		.. "\n"
		.. "id=$(niri msg --json windows | python3 -c \"import sys,json; ws=json.load(sys.stdin); print(next((w['id'] for w in ws if w.get('app_id')==sys.argv[1]), ''))\" \"$app_id\")\n\n"
		.. 'if [ -n "$id" ]; then\n'
		.. '  niri msg action focus-window --id "$id"\n'
		.. "else\n"
		.. "  "
		.. command
		.. " &\n"
		.. "fi\n"
end

function M.templates()
	return {
		{ key = "blank", name = "Blank script" },
		{ key = "focus-or-spawn", name = "Focus-or-spawn (app toggle)" },
	}
end

function M.buildTemplate(key, params)
	params = params or {}
	if key == "focus-or-spawn" then
		return M.focusOrSpawnTemplate(params.appId, params.command)
	end
	return M.blankTemplate()
end

return M
