--!nonstrict
-- niri.luau — `niri msg` command builders + JSON parsers + the validated-save
-- pipeline. Faithful port of lib/niri.js (niri-config v4), adapted to the
-- Luau runtime:
--   * `checkInstalledCmd()` is gone — use `noctalia.commandExists("niri")`
--     directly, a synchronous in-process call, instead of spawning `sh -c
--     "command -v niri"`.
--   * File contents travel as a plain argv element instead of base64
--     (`Qt.btoa`). `noctalia.runAsync({...}, cb)`'s argv-array form (plugin_api
--     24) executes the program directly and passes each later value as one
--     literal argument with NO shell parsing — exactly the property v4 used
--     base64 to get out of QML's Process.command. The embedded `sh -c`
--     scripts below receive that content as `"$2"` etc and write it with
--     `printf %s "$c" > "$f"`, which is byte-safe for arbitrary KDL text
--     (printf's own "%s" format string never re-scans the substituted
--     argument for escapes/specifiers).
-- Returns argv arrays / parsed data; the caller (lib/state.luau) runs the
-- processes via noctalia.runAsync.

local M = {}

-- ── command builders ────────────────────────────────────────────────────

function M.jsonCmd(kind)
	return { "niri", "msg", "--json", kind }
end

function M.validateCmd(mainConfigPath)
	return { "niri", "validate", "-c", mainConfigPath }
end

-- Live, non-destructive output preview (reverts on next config reload).
-- prop ∈ {mode,scale,transform,position,vrr,on,off}; value is pre-stringified.
function M.outputCmd(name, prop, value)
	if not name or not prop then
		return nil
	end
	if prop == "position" then
		if type(value) ~= "table" or #value ~= 2 then
			return nil
		end
		if value[1] == nil or value[1] == "" then
			return nil
		end
		if value[2] == nil or value[2] == "" then
			return nil
		end
		return { "niri", "msg", "output", name, "position", "set", tostring(value[1]), tostring(value[2]) }
	end
	local c = { "niri", "msg", "output", name, prop }
	if prop == "on" or prop == "off" then
		return c
	end
	if value == nil or value == "" then
		return nil
	end
	if type(value) == "table" then
		if #value == 0 then
			return nil
		end
		for _, v in ipairs(value) do
			table.insert(c, tostring(v))
		end
		return c
	end
	table.insert(c, tostring(value))
	return c
end

-- Apply MANY staged files atomically. Each file's current contents are staged
-- aside first, then the new contents are written and the whole config
-- validated once. On success the staged copies are promoted to "$f.bak" and
-- niri reloads; on failure the tree is put back exactly as it was. Prints
-- OK/ERR on stdout, validate errors on stderr.
local APPLY_SCRIPT = 'set -u; main="$1"; shift; '
	.. 'tmp=$(mktemp -d) || { echo ERR; echo "mktemp failed" >&2; exit 0; }; '
	.. ': > "$tmp/list"; n=0; ok=1; msg=""; '
	.. 'while [ $# -ge 2 ]; do f="$1"; c="$2"; shift 2; n=$((n + 1)); '
	.. '  if [ -e "$f" ]; then cp -f "$f" "$tmp/$n.bak" 2>/dev/null || true; '
	.. "  else : > \"$tmp/$n.new\"; fi; "
	.. '  printf "%s\\n" "$f" >> "$tmp/list"; '
	.. '  printf %s "$c" > "$f" || { ok=0; msg="write failed: $f"; break; }; '
	.. "done; "
	.. 'if [ "$ok" = 1 ] && niri validate -c "$main" 2>"$tmp/err"; then '
	.. '  i=0; while IFS= read -r f; do i=$((i + 1)); '
	.. '    if [ -f "$tmp/$i.bak" ]; then cp -f "$tmp/$i.bak" "$f.bak"; fi; done < "$tmp/list"; '
	.. "  niri msg action load-config-file >/dev/null 2>&1 || true; echo OK; "
	.. "else "
	.. '  i=0; while IFS= read -r f; do i=$((i + 1)); '
	.. '    if [ -f "$tmp/$i.bak" ]; then cp -f "$tmp/$i.bak" "$f"; '
	.. '    elif [ -f "$tmp/$i.new" ]; then rm -f "$f"; fi; done < "$tmp/list"; '
	.. "  echo ERR; "
	.. '  if [ -n "$msg" ]; then echo "$msg" >&2; fi; '
	.. '  if [ -s "$tmp/err" ]; then cat "$tmp/err" >&2; fi; '
	.. "fi; "
	.. 'rm -rf "$tmp"; exit 0'

-- pairs: { { path = ..., text = ... }, ... }
function M.applyCmd(mainConfigPath, pairs)
	local args = { "sh", "-c", APPLY_SCRIPT, "_", mainConfigPath }
	for _, p in ipairs(pairs) do
		table.insert(args, p.path)
		table.insert(args, p.text)
	end
	return args
end

-- Restore the .bak of each path (undo the last successful apply), then
-- reload. Prints "RESTORED <n>" or "ERR <msg>".
local UNDO_SCRIPT = "set -u; n=0; "
	.. 'for f in "$@"; do '
	.. '  if [ -f "$f.bak" ]; then '
	.. '    cp -f "$f.bak" "$f" || { echo "ERR restore failed: $f"; exit 0; }; '
	.. "    n=$((n + 1)); "
	.. "  fi; "
	.. "done; "
	.. 'if [ "$n" -gt 0 ]; then niri msg action load-config-file >/dev/null 2>&1 || true; fi; '
	.. 'echo "RESTORED $n"'

function M.undoCmd(paths)
	local args = { "sh", "-c", UNDO_SCRIPT, "_" }
	for _, p in ipairs(paths) do
		table.insert(args, p)
	end
	return args
end

-- Write an arbitrary file (e.g. a managed script) directly; chmod +x when
-- executable. No niri validate — used for non-config files. Prints OK/ERR.
local WRITE_SCRIPT = 'set -u; f="$1"; c="$2"; ex="$3"; mkdir -p "$(dirname "$f")"; '
	.. 'printf %s "$c" > "$f" || { echo ERR; echo "write failed" >&2; exit 0; }; '
	.. '[ "$ex" = "1" ] && chmod +x "$f"; echo OK'

function M.writeFileCmd(filePath, content, executable)
	return { "sh", "-c", WRITE_SCRIPT, "_", filePath, content, executable and "1" or "0" }
end

function M.deleteFileCmd(filePath)
	return { "sh", "-c", 'rm -f "$1" && echo OK || echo ERR', "_", filePath }
end

-- ── JSON parsers ────────────────────────────────────────────────────────

-- `niri msg --json outputs` (and friends) may decode to a Luau array (JSON
-- array) or a map (JSON object keyed by name) depending on niri's schema for
-- that command; normalize either to a 1-indexed list.
local function toList(raw)
	if raw == nil then
		return {}
	end
	if raw[1] ~= nil then
		return raw
	end
	local out = {}
	for _, v in pairs(raw) do
		table.insert(out, v)
	end
	return out
end

local function fmtRefresh(mHz)
	return string.format("%.3f", mHz / 1000)
end

function M.modeString(m)
	return tostring(m.width) .. "x" .. tostring(m.height) .. "@" .. fmtRefresh(m.refresh_rate)
end

function M.parseOutputs(text)
	local ok, raw = pcall(noctalia.json.decode, text)
	if not ok or raw == nil then
		return {}
	end
	local list = toList(raw)
	local out = {}
	for _, o in ipairs(list) do
		local modes = {}
		for idx, m in ipairs(o.modes or {}) do
			table.insert(modes, {
				index = idx - 1,
				width = m.width,
				height = m.height,
				refresh = m.refresh_rate,
				refreshHz = fmtRefresh(m.refresh_rate),
				preferred = m.is_preferred == true,
				label = M.modeString(m),
			})
		end
		local logical = o.logical or {}
		local currentMode = o.current_mode
		local currentModeLabel = ""
		if currentMode ~= nil and modes[currentMode + 1] ~= nil then
			currentModeLabel = modes[currentMode + 1].label
		end
		table.insert(out, {
			name = o.name,
			make = o.make or "",
			model = o.model or "",
			serial = o.serial,
			modes = modes,
			currentMode = (currentMode ~= nil) and currentMode or -1,
			currentModeLabel = currentModeLabel,
			vrrSupported = o.vrr_supported == true,
			vrrEnabled = o.vrr_enabled == true,
			scale = (logical.scale ~= nil) and logical.scale or 1,
			x = (logical.x ~= nil) and logical.x or 0,
			y = (logical.y ~= nil) and logical.y or 0,
			transform = logical.transform or "Normal",
			logicalWidth = logical.width,
			logicalHeight = logical.height,
		})
	end
	return out
end

function M.parseWorkspaces(text)
	local ok, raw = pcall(noctalia.json.decode, text)
	if not ok or type(raw) ~= "table" then
		return {}
	end
	local out = {}
	for _, w in ipairs(raw) do
		table.insert(out, {
			id = w.id,
			idx = w.idx,
			name = w.name,
			output = w.output,
			active = w.is_active == true,
			focused = w.is_focused == true,
			urgent = w.is_urgent == true,
			activeWindowId = w.active_window_id,
		})
	end
	return out
end

function M.parseWindows(text)
	local ok, raw = pcall(noctalia.json.decode, text)
	if not ok or type(raw) ~= "table" then
		return {}
	end
	local out = {}
	for _, w in ipairs(raw) do
		table.insert(out, {
			id = w.id,
			title = w.title or "",
			appId = w.app_id or "",
			pid = w.pid,
			workspaceId = w.workspace_id,
			focused = w.is_focused == true,
			floating = w.is_floating == true,
		})
	end
	return out
end

return M
