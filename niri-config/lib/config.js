.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// config.js — resolve niri's `include` graph and map config sections to the
// file that owns them. Pure: QML does the file IO and passes text in.
// Part of the v5-portable core.
// ─────────────────────────────────────────────────────────────────────────────

// Marker used by the multi-file read pipeline (see ConfigModel.qml).
var FILE_MARKER = "<<<<NIRICFG-FILE:";

function dirname(p) { var i = p.lastIndexOf("/"); return i <= 0 ? "/" : p.slice(0, i); }

// Resolve an include spec (relative/./~/absolute) against baseDir + home.
function resolveInclude(spec, baseDir, home) {
    var s = String(spec).trim();
    if (s[0] === "~") return home + s.slice(1);
    if (s[0] === "/") return s;
    if (s.slice(0, 2) === "./") s = s.slice(2);
    return baseDir + "/" + s;
}

// Given a parsed main config (kdl doc) → list of resolved include paths.
function includePaths(doc, baseDir, home) {
    var out = [];
    (doc.nodes || []).forEach(function (n) {
        if (n.name === "include" && n.args[0]) out.push(resolveInclude(n.args[0].value, baseDir, home));
    });
    return out;
}

// Pack a multi-file cat blob (printed by ConfigModel's reader) into {path:text}.
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

// Build a shell command that cats files with markers (for QML Process).
function readBlobCmd(paths) {
    var script = 'for f in "$@"; do printf "%s%s>>>>\\n" "' + FILE_MARKER + '" "$f"; cat "$f" 2>/dev/null; printf "\\n"; done';
    return ["sh", "-c", script, "_"].concat(paths);
}

// Across loaded files ({path, doc}), find the first file owning a top-level node
// of `nodeName`. Returns {path, node, doc} or null.
function findOwner(files, nodeName) {
    for (var i = 0; i < files.length; i++) {
        var nodes = files[i].doc.nodes;
        for (var j = 0; j < nodes.length; j++) {
            if (nodes[j].name === nodeName) return { path: files[i].path, node: nodes[j], doc: files[i].doc };
        }
    }
    return null;
}

// All files containing ANY node whose name is in `nodeNames` (e.g. output / window-rule).
function findAllOwners(files, nodeNames) {
    var set = {}; nodeNames.forEach(function (n) { set[n] = 1; });
    var out = [];
    files.forEach(function (f) {
        var matches = f.doc.nodes.filter(function (n) { return set[n.name]; });
        if (matches.length) out.push({ path: f.path, doc: f.doc, nodes: matches });
    });
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        FILE_MARKER: FILE_MARKER, dirname: dirname, resolveInclude: resolveInclude,
        includePaths: includePaths, splitFileBlob: splitFileBlob, readBlobCmd: readBlobCmd,
        findOwner: findOwner, findAllOwners: findAllOwners
    };
}
