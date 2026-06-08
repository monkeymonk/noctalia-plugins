.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// desktop.js — parse freedesktop .desktop entries into launchable app records.
// QML enumerates/reads the files; these functions parse the text. Part of the
// v5-portable core.
// ─────────────────────────────────────────────────────────────────────────────

// Standard search dirs (QML resolves $HOME).
var APP_DIRS = ["/usr/share/applications", "/usr/local/share/applications",
                "~/.local/share/applications"];

// Parse a single .desktop file body → entry, or null if it shouldn't be listed.
function parseDesktopEntry(text) {
    if (!text) return null;
    var inEntry = false, e = {};
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line[0] === "[") { inEntry = (line === "[Desktop Entry]"); continue; }
        if (!inEntry || !line || line[0] === "#") continue;
        var eq = line.indexOf("=");
        if (eq === -1) continue;
        var key = line.slice(0, eq).trim();
        var val = line.slice(eq + 1).trim();
        // ignore locale-suffixed keys (Name[fr]=…)
        if (key.indexOf("[") !== -1) continue;
        e[key] = val;
    }
    if ((e.Type && e.Type !== "Application")) return null;
    if (e.NoDisplay === "true" || e.Hidden === "true") return null;
    if (!e.Name || !e.Exec) return null;
    return {
        name: e.Name,
        exec: cleanExec(e.Exec),
        rawExec: e.Exec,
        icon: e.Icon || "",
        terminal: e.Terminal === "true",
        comment: e.Comment || ""
    };
}

// Strip field codes (%U %u %F %f %i %c %k %D %v %m) and unescape.
function cleanExec(exec) {
    if (!exec) return "";
    return exec
        .replace(/%[fFuUickdDnNvm]/g, "")
        .replace(/%%/g, "%")
        .replace(/\s+/g, " ")
        .trim();
}

// Does the command need a shell (metacharacters)? Then prefer spawn-sh.
function needsShell(cmd) { return /[|&;<>$`(){}*?~"']/.test(cmd); }

// Tokenize a simple command into argv (no shell features). Honors basic quotes.
function tokenize(cmd) {
    var out = [], cur = "", q = null;
    for (var i = 0; i < cmd.length; i++) {
        var c = cmd[i];
        if (q) { if (c === q) q = null; else cur += c; continue; }
        if (c === '"' || c === "'") { q = c; continue; }
        if (c === " ") { if (cur) { out.push(cur); cur = ""; } continue; }
        cur += c;
    }
    if (cur) out.push(cur);
    return out;
}

// Build a niri action ({name, args}) from a command string.
function commandToAction(cmd) {
    var c = (cmd || "").trim();
    if (!c) return null;
    if (needsShell(c)) return { name: "spawn-sh", args: [c] };
    return { name: "spawn", args: tokenize(c) };
}

// Build an action from a parsed desktop entry.
function entryToAction(entry) { return commandToAction(entry.exec); }

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        APP_DIRS: APP_DIRS, parseDesktopEntry: parseDesktopEntry, cleanExec: cleanExec,
        needsShell: needsShell, tokenize: tokenize, commandToAction: commandToAction,
        entryToAction: entryToAction
    };
}
