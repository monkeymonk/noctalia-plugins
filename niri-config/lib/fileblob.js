.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// fileblob.js — read many files in one process: build a marker-delimited cat
// command, and split the resulting blob back into {path: text}. Generic; no
// niri knowledge. Part of the v5-portable core.
// ─────────────────────────────────────────────────────────────────────────────

// Marker used by the multi-file read pipeline.
var FILE_MARKER = "<<<<NIRICFG-FILE:";

// Build a shell command that cats files with markers (for QML Process).
function readBlobCmd(paths) {
    var script = 'for f in "$@"; do printf "%s%s>>>>\\n" "' + FILE_MARKER + '" "$f"; cat "$f" 2>/dev/null; printf "\\n"; done';
    return ["sh", "-c", script, "_"].concat(paths);
}

// Pack a multi-file cat blob (printed by readBlobCmd) into {path:text}.
function splitFileBlob(blob) {
    var map = {};
    if (!blob) return map;
    var parts = blob.split(FILE_MARKER);
    for (var i = 1; i < parts.length; i++) {
        var seg = parts[i];
        var gt = seg.indexOf(">>>>");
        if (gt === -1) continue;
        var path = seg.slice(0, gt);
        var body = seg.slice(gt + 4);
        if (body[0] === "\n") body = body.slice(1);
        map[path] = body;
    }
    return map;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        FILE_MARKER: FILE_MARKER, readBlobCmd: readBlobCmd, splitFileBlob: splitFileBlob
    };
}
