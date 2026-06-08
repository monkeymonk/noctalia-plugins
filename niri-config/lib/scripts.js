.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// scripts.js — templates + listing for user-managed niri helper scripts that
// live in ~/.config/niri/scripts/ and are referenced from binds as spawn "name".
// Pure: QML does the file IO. v5-portable core.
// ─────────────────────────────────────────────────────────────────────────────

function scriptsDir(home) { return home + "/.config/niri/scripts"; }

// Parse the listing produced by listCmd ("<x|->\t<name>\n…") into records.
function parseList(text, dir) {
    var out = [];
    if (!text) return out;
    text.split("\n").forEach(function (line) {
        if (!line) return;
        var tab = line.indexOf("\t");
        if (tab === -1) return;
        var exec = line.slice(0, tab) === "x";
        var name = line.slice(tab + 1);
        if (!name) return;
        out.push({ name: name, executable: exec, path: dir + "/" + name });
    });
    out.sort(function (a, b) { return a.name < b.name ? -1 : 1; });
    return out;
}

// Shell command (argv) to list scripts with their executable flag.
function listCmd(dir) {
    return ["sh", "-c",
        'd="$1"; [ -d "$d" ] || exit 0; for f in "$d"/*; do [ -f "$f" ] || continue; ' +
        'printf "%s\\t%s\\n" "$([ -x "$f" ] && echo x || echo -)" "$(basename "$f")"; done',
        "_", dir];
}

// ── templates ────────────────────────────────────────────────────────────────

function blankTemplate() {
    return "#!/usr/bin/env bash\nset -euo pipefail\n\n";
}

// Focus an existing window by app-id, otherwise spawn the command (the practical
// "app toggle" under niri). Uses python3 for robust JSON parsing.
function focusOrSpawnTemplate(appId, command) {
    appId = appId || "APP_ID";
    command = command || "COMMAND";
    return "#!/usr/bin/env bash\n" +
        "# Focus the window matching app-id, or launch it if not running.\n" +
        "set -euo pipefail\n\n" +
        "app_id=" + shQuote(appId) + "\n" +
        "id=$(niri msg --json windows | python3 -c \"import sys,json; ws=json.load(sys.stdin); print(next((w['id'] for w in ws if w.get('app_id')==sys.argv[1]), ''))\" \"$app_id\")\n\n" +
        "if [ -n \"$id\" ]; then\n" +
        "  niri msg action focus-window --id \"$id\"\n" +
        "else\n" +
        "  " + command + " &\n" +
        "fi\n";
}

function shQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

function templates() {
    return [
        { key: "blank", name: "Blank script" },
        { key: "focus-or-spawn", name: "Focus-or-spawn (app toggle)" }
    ];
}

// Build body for a template key (+ optional params).
function buildTemplate(key, params) {
    params = params || {};
    if (key === "focus-or-spawn") return focusOrSpawnTemplate(params.appId, params.command);
    return blankTemplate();
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        scriptsDir: scriptsDir, parseList: parseList, listCmd: listCmd,
        blankTemplate: blankTemplate, focusOrSpawnTemplate: focusOrSpawnTemplate,
        templates: templates, buildTemplate: buildTemplate, shQuote: shQuote
    };
}
