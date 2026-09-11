.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// niri.js — `niri msg` command builders + JSON parsers + the validated-save
// pipeline. Pure: returns argv arrays / parsed data; QML runs the processes.
// Part of the v5-portable core.
// ─────────────────────────────────────────────────────────────────────────────

// ── command builders ─────────────────────────────────────────────────────────

function checkInstalledCmd() { return ["sh", "-c", "command -v niri"]; }
function jsonCmd(kind) { return ["niri", "msg", "--json", kind]; }   // outputs|workspaces|windows|keyboard-layouts
function validateCmd(mainConfigPath) { return ["niri", "validate", "-c", mainConfigPath]; }

// Live, non-destructive output preview (reverts on next config reload).
// prop ∈ {mode,scale,transform,position,vrr,on,off}; value is pre-stringified.
function outputCmd(name, prop, value) {
    if (!name || !prop) return null;
    // position uses `position set X Y` grammar — both coordinates are required
    if (prop === "position") {
        if (!Array.isArray(value) || value.length !== 2) return null;
        if (value[0] === null || value[0] === undefined || value[0] === "") return null;
        if (value[1] === null || value[1] === undefined || value[1] === "") return null;
        return ["niri", "msg", "output", name, "position", "set", String(value[0]), String(value[1])];
    }
    var c = ["niri", "msg", "output", name, prop];
    // bare switches take no argument
    if (prop === "on" || prop === "off") return c;
    if (value === undefined || value === null || value === "") return null;
    if (Array.isArray(value)) {
        if (value.length === 0) return null;
        return c.concat(value.map(String));
    }
    return c.concat([String(value)]);
}

// Apply MANY staged files atomically. Each file's current contents are staged
// aside first, then the new contents are written and the whole config validated
// once. On success the staged copies are promoted to "$f.bak" and niri reloads;
// on failure the tree is put back exactly as it was — a file that existed is
// restored from its staged copy, a file this run CREATED is deleted again — and
// the pre-existing ".bak" files are left untouched, so a failed apply never
// destroys the backup of the last successful one.
// Prints OK/ERR on stdout, validate errors on stderr.
// pairs: [{ path, b64 }]; b64 is Qt.btoa(newText).
var APPLY_SCRIPT =
    'set -u; main="$1"; shift; ' +
    'tmp=$(mktemp -d) || { echo ERR; echo "mktemp failed" >&2; exit 0; }; ' +
    ': > "$tmp/list"; n=0; ok=1; msg=""; ' +
    'while [ $# -ge 2 ]; do f="$1"; b="$2"; shift 2; n=$((n + 1)); ' +
    '  if [ -e "$f" ]; then cp -f "$f" "$tmp/$n.bak" 2>/dev/null || true; ' +
    '  else : > "$tmp/$n.new"; fi; ' +
    '  printf "%s\\n" "$f" >> "$tmp/list"; ' +
    '  printf %s "$b" | base64 -d > "$f" || { ok=0; msg="write failed: $f"; break; }; ' +
    'done; ' +
    'if [ "$ok" = 1 ] && niri validate -c "$main" 2>"$tmp/err"; then ' +
    '  i=0; while IFS= read -r f; do i=$((i + 1)); ' +
    '    if [ -f "$tmp/$i.bak" ]; then cp -f "$tmp/$i.bak" "$f.bak"; fi; done < "$tmp/list"; ' +
    '  niri msg action load-config-file >/dev/null 2>&1 || true; echo OK; ' +
    'else ' +
    '  i=0; while IFS= read -r f; do i=$((i + 1)); ' +
    '    if [ -f "$tmp/$i.bak" ]; then cp -f "$tmp/$i.bak" "$f"; ' +
    '    elif [ -f "$tmp/$i.new" ]; then rm -f "$f"; fi; done < "$tmp/list"; ' +
    '  echo ERR; ' +
    '  if [ -n "$msg" ]; then echo "$msg" >&2; fi; ' +
    '  if [ -s "$tmp/err" ]; then cat "$tmp/err" >&2; fi; ' +
    'fi; ' +
    'rm -rf "$tmp"; exit 0';

function applyCmd(mainConfigPath, pairs) {
    var args = ["sh", "-c", APPLY_SCRIPT, "_", mainConfigPath];
    pairs.forEach(function (p) { args.push(p.path); args.push(p.b64); });
    return args;
}

// Restore the .bak of each path (undo the last successful apply), then reload.
// Prints "RESTORED <n>" with the number of files actually restored, or
// "ERR <msg>" if a restore failed.
var UNDO_SCRIPT =
    'set -u; n=0; ' +
    'for f in "$@"; do ' +
    '  if [ -f "$f.bak" ]; then ' +
    '    cp -f "$f.bak" "$f" || { echo "ERR restore failed: $f"; exit 0; }; ' +
    '    n=$((n + 1)); ' +
    '  fi; ' +
    'done; ' +
    'if [ "$n" -gt 0 ]; then niri msg action load-config-file >/dev/null 2>&1 || true; fi; ' +
    'echo "RESTORED $n"';

function undoCmd(paths) { return ["sh", "-c", UNDO_SCRIPT, "_"].concat(paths); }

// Write an arbitrary file (e.g. a managed script) from base64; chmod +x when
// executable. No niri validate — used for non-config files. Prints OK/ERR.
var WRITE_SCRIPT =
    'set -u; f="$1"; b64="$2"; ex="$3"; mkdir -p "$(dirname "$f")"; ' +
    'printf %s "$b64" | base64 -d > "$f" || { echo ERR; echo "write failed" >&2; exit 0; }; ' +
    '[ "$ex" = "1" ] && chmod +x "$f"; echo OK';

function writeFileCmd(filePath, b64Content, executable) {
    return ["sh", "-c", WRITE_SCRIPT, "_", filePath, b64Content, executable ? "1" : "0"];
}

function deleteFileCmd(filePath) {
    return ["sh", "-c", 'rm -f "$1" && echo OK || echo ERR', "_", filePath];
}

// ── JSON parsers ─────────────────────────────────────────────────────────────

function safeParse(text) { try { return JSON.parse(text); } catch (e) { return null; } }

function fmtRefresh(mHz) { return (mHz / 1000).toFixed(3); }
function modeString(m) { return m.width + "x" + m.height + "@" + fmtRefresh(m.refresh_rate); }

// Normalize `niri msg --json outputs` (object-keyed or array) → array.
function parseOutputs(text) {
    var raw = safeParse(text);
    if (!raw) return [];
    var list = Array.isArray(raw) ? raw : Object.keys(raw).map(function (k) { return raw[k]; });
    return list.map(function (o) {
        var modes = (o.modes || []).map(function (m, idx) {
            return {
                index: idx, width: m.width, height: m.height,
                refresh: m.refresh_rate, refreshHz: fmtRefresh(m.refresh_rate),
                preferred: !!m.is_preferred, label: modeString(m)
            };
        });
        var logical = o.logical || {};
        return {
            name: o.name, make: o.make || "", model: o.model || "", serial: o.serial || null,
            modes: modes, currentMode: (o.current_mode != null ? o.current_mode : -1),
            currentModeLabel: (o.current_mode != null && modes[o.current_mode]) ? modes[o.current_mode].label : "",
            vrrSupported: !!o.vrr_supported, vrrEnabled: !!o.vrr_enabled,
            scale: logical.scale != null ? logical.scale : 1,
            x: logical.x != null ? logical.x : 0, y: logical.y != null ? logical.y : 0,
            transform: logical.transform || "Normal",
            logicalWidth: logical.width, logicalHeight: logical.height
        };
    });
}

function parseWorkspaces(text) {
    var raw = safeParse(text);
    if (!Array.isArray(raw)) return [];
    return raw.map(function (w) {
        return { id: w.id, idx: w.idx, name: w.name || null, output: w.output || null,
                 active: !!w.is_active, focused: !!w.is_focused, urgent: !!w.is_urgent,
                 activeWindowId: w.active_window_id != null ? w.active_window_id : null };
    });
}

function parseWindows(text) {
    var raw = safeParse(text);
    if (!Array.isArray(raw)) return [];
    return raw.map(function (w) {
        return { id: w.id, title: w.title || "", appId: w.app_id || "", pid: w.pid,
                 workspaceId: w.workspace_id, focused: !!w.is_focused, floating: !!w.is_floating };
    });
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        checkInstalledCmd: checkInstalledCmd, jsonCmd: jsonCmd, validateCmd: validateCmd,
        outputCmd: outputCmd, applyCmd: applyCmd, undoCmd: undoCmd,
        writeFileCmd: writeFileCmd, deleteFileCmd: deleteFileCmd,
        modeString: modeString, parseOutputs: parseOutputs,
        parseWorkspaces: parseWorkspaces, parseWindows: parseWindows
    };
}
