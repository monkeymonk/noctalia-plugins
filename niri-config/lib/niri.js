.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// niri.js — `niri msg` command builders + JSON parsers + the validated-save
// pipeline. Pure: returns argv arrays / parsed data; QML runs the processes.
// Part of the v5-portable core.
// ─────────────────────────────────────────────────────────────────────────────

// ── command builders ─────────────────────────────────────────────────────────

function checkInstalledCmd() { return ["sh", "-c", "command -v niri"]; }
function jsonCmd(kind) { return ["niri", "msg", "--json", kind]; }   // outputs|workspaces|windows|keyboard-layouts
function actionCmd(name, args) { return ["niri", "msg", "action", name].concat(args || []); }
function reloadCmd() { return ["niri", "msg", "action", "load-config-file"]; }
function validateCmd(mainConfigPath) { return ["niri", "validate", "-c", mainConfigPath]; }

// Live, non-destructive output preview (reverts on next config reload).
// prop ∈ {mode,scale,transform,position,vrr,on,off}; value is pre-stringified.
function outputCmd(name, prop, value) {
    var c = ["niri", "msg", "output", name, prop];
    // position uses `position set X Y` grammar
    if (prop === "position") {
        if (Array.isArray(value) && value.length === 2 && value[0] !== "" && value[1] !== "")
            return c.concat(["set", String(value[0]), String(value[1])]);
        return c;
    }
    if (value !== undefined && value !== null && value !== "") {
        if (Array.isArray(value)) c = c.concat(value.map(String));
        else c.push(String(value));
    }
    return c;
}

// Validated save pipeline. `b64` is base64 of the new file content (use Qt.btoa
// in QML). On success: writes file, validates the whole config, hot-reloads,
// prints "OK". On failure: restores from .bak, prints "ERR" + validate stderr.
var SAVE_SCRIPT =
    'set -u; f="$1"; main="$2"; b64="$3"; ' +
    'cp -f "$f" "$f.bak" 2>/dev/null || true; ' +
    'printf %s "$b64" | base64 -d > "$f" || { echo ERR; echo "write failed" >&2; exit 0; }; ' +
    'if niri validate -c "$main" 2>/tmp/niri-config-validate.err; then ' +
    '  niri msg action load-config-file >/dev/null 2>&1 || true; echo OK; ' +
    'else ' +
    '  cp -f "$f.bak" "$f"; echo ERR; cat /tmp/niri-config-validate.err >&2; ' +
    'fi';

function saveCmd(filePath, mainConfigPath, b64Content) {
    return ["sh", "-c", SAVE_SCRIPT, "_", filePath, mainConfigPath, b64Content];
}

// Apply MANY staged files atomically: .bak + write each, validate the whole
// config once, reload on success, restore every .bak on failure. Prints OK/ERR.
// pairs: [{ path, b64 }]; b64 is Qt.btoa(newText).
var APPLY_SCRIPT =
    'set -u; main="$1"; shift; written=""; ok=1; ' +
    'while [ $# -ge 2 ]; do f="$1"; b="$2"; shift 2; ' +
    '  cp -f "$f" "$f.bak" 2>/dev/null || true; ' +
    '  if printf %s "$b" | base64 -d > "$f"; then written="$written $f"; else echo ERR; echo "write failed: $f" >&2; ok=0; break; fi; ' +
    'done; ' +
    'if [ "$ok" = 1 ] && niri validate -c "$main" 2>/tmp/nc-apply.err; then ' +
    '  niri msg action load-config-file >/dev/null 2>&1 || true; echo OK; ' +
    'else for f in $written; do cp -f "$f.bak" "$f"; done; echo ERR; cat /tmp/nc-apply.err >&2 2>/dev/null; fi';

function applyCmd(mainConfigPath, pairs) {
    var args = ["sh", "-c", APPLY_SCRIPT, "_", mainConfigPath];
    pairs.forEach(function (p) { args.push(p.path); args.push(p.b64); });
    return args;
}

// Restore the .bak of each path (undo the last apply), then reload.
var UNDO_SCRIPT = 'set -u; for f in "$@"; do [ -f "$f.bak" ] && cp -f "$f.bak" "$f"; done; ' +
    'niri msg action load-config-file >/dev/null 2>&1 || true; echo OK';
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

function parseKeyboardLayouts(text) {
    var raw = safeParse(text);
    if (!raw) return { names: [], currentIdx: 0 };
    return { names: raw.names || [], currentIdx: raw.current_idx || 0 };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        checkInstalledCmd: checkInstalledCmd, jsonCmd: jsonCmd, actionCmd: actionCmd,
        reloadCmd: reloadCmd, validateCmd: validateCmd, outputCmd: outputCmd, saveCmd: saveCmd,
        writeFileCmd: writeFileCmd, deleteFileCmd: deleteFileCmd, applyCmd: applyCmd, undoCmd: undoCmd,
        modeString: modeString, parseOutputs: parseOutputs, parseWorkspaces: parseWorkspaces,
        parseWindows: parseWindows, parseKeyboardLayouts: parseKeyboardLayouts
    };
}
