.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// config.js — resolve niri's `include` graph and map config sections to the
// file that owns them. Pure: QML does the file IO and passes text in.
// Part of the v5-portable core.
// ─────────────────────────────────────────────────────────────────────────────

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

// Across loaded files ({path, doc}), find the first file owning a top-level node
// of `nodeName`. Returns {path, doc, nodes} (every top-level match in that file)
// or null. Same record shape as allOwners — a caller wanting the single block
// reads `.nodes[0]`.
function ownerOf(files, nodeName) {
    for (var i = 0; i < files.length; i++) {
        var matches = files[i].doc.nodes.filter(function (n) { return n.name === nodeName; });
        if (matches.length) return { path: files[i].path, doc: files[i].doc, nodes: matches };
    }
    return null;
}

// All files containing ANY node whose name is in `nodeNames` (e.g. output / window-rule).
function allOwners(files, nodeNames) {
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
        dirname: dirname, resolveInclude: resolveInclude, includePaths: includePaths,
        ownerOf: ownerOf, allOwners: allOwners
    };
}
