.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// kdl.js — tolerant KDL (v2) parser + surgical text-edit primitives.
//
// PORTABILITY: pure ECMAScript, zero QML/Noctalia deps. This is part of the
// v5-portable core (see README). QML only consumes the functions here.
//
// The parser records the exact source character range of every node so edits
// can be applied to the ORIGINAL text without reformatting. Untouched bytes are
// never rewritten — comments, alignment and section headers are preserved.
//
// Node shape:
//   {
//     name:        string,                 // node name (e.g. "Mod+Return", "spawn", "output")
//     args:        [{ value, raw, range }] // positional values
//     props:       { key: value, ... }     // last-wins, decoded values
//     propsList:   [{ key, value, raw, range, keyRange }]
//     children:    [Node],
//     slashdash:   bool,                   // node disabled via /-
//     range:       [start, end],           // whole node incl. children + terminator
//     headerRange: [start, end],           // name + args + props (before "{" or terminator)
//     nameRange:   [start, end],
//     childrenRange: [start, end] | null,  // inside the "{ }" (excludes braces)
//   }
//
// Value: { value: <decoded JS value>, raw: <source slice>, range: [s,e] }
// ─────────────────────────────────────────────────────────────────────────────

function isWs(c) { return c === " " || c === "\t" || c === "\r" || c === "﻿" || c === " "; }
function isNewline(c) { return c === "\n"; }
function isTerminator(c) { return c === undefined || c === "\n" || c === ";"; }

// Characters that end a bare identifier/value token.
function isDelim(c) {
    return c === undefined || isWs(c) || c === "\n" || c === ";" ||
           c === "{" || c === "}" || c === "(" || c === ")" || c === "=" ||
           c === "\\" || c === "/"; // "/" only matters when followed by /,* — caller checks
}

function Parser(text) {
    this.t = text;
    this.i = 0;
    this.n = text.length;
}

Parser.prototype.peek = function (o) { return this.t[this.i + (o || 0)]; };
Parser.prototype.eof = function () { return this.i >= this.n; };

// Skip inline whitespace, line continuations (\ + newline) and comments,
// but NOT bare newlines (those terminate a node). Returns true if a node
// terminator (newline/;) boundary was *not* crossed.
Parser.prototype.skipInline = function () {
    while (!this.eof()) {
        var c = this.t[this.i];
        if (c === " " || c === "\t" || c === "\r" || c === "﻿" || c === " ") { this.i++; continue; }
        if (c === "\\") {
            // line continuation: backslash then (optional ws) newline
            var j = this.i + 1;
            while (j < this.n && (this.t[j] === " " || this.t[j] === "\t" || this.t[j] === "\r")) j++;
            if (this.t[j] === "\n") { this.i = j + 1; continue; }
            // stray backslash — stop
            return;
        }
        if (c === "/" && this.t[this.i + 1] === "/") { this.skipLineComment(); return; }
        if (c === "/" && this.t[this.i + 1] === "*") { this.skipBlockComment(); continue; }
        return;
    }
};

// Skip whitespace/newlines/comments freely (between nodes).
Parser.prototype.skipWsAndNewlines = function () {
    while (!this.eof()) {
        var c = this.t[this.i];
        if (isWs(c) || c === "\n") { this.i++; continue; }
        if (c === "\\") { this.i++; continue; }
        if (c === "/" && this.t[this.i + 1] === "/") { this.skipLineComment(); continue; }
        if (c === "/" && this.t[this.i + 1] === "*") { this.skipBlockComment(); continue; }
        return;
    }
};

Parser.prototype.skipLineComment = function () {
    while (!this.eof() && this.t[this.i] !== "\n") this.i++;
};

Parser.prototype.skipBlockComment = function () {
    this.i += 2;
    var depth = 1;
    while (!this.eof() && depth > 0) {
        if (this.t[this.i] === "/" && this.t[this.i + 1] === "*") { depth++; this.i += 2; continue; }
        if (this.t[this.i] === "*" && this.t[this.i + 1] === "/") { depth--; this.i += 2; continue; }
        this.i++;
    }
};

// Read a string value: "..", #".."#, r".." or r#"..."# (niri uses r#"..."#).
// Returns {value, raw, range} or null if not a string at the cursor.
Parser.prototype.readString = function () {
    var start = this.i;
    if (this.t[this.i] === "r") this.i++;           // optional raw prefix (KDL v1 style)
    var hashes = 0;
    while (this.t[this.i] === "#") { hashes++; this.i++; }
    if (this.t[this.i] !== '"') { this.i = start; return null; }
    // multiline?
    var triple = this.t[this.i + 1] === '"' && this.t[this.i + 2] === '"';
    var closer = (triple ? '"""' : '"') + "#".repeat(hashes);
    this.i += triple ? 3 : 1;
    var raw = (this.t[start] === "r") || hashes > 0; // raw string: no escape processing
    var out = "";
    while (!this.eof()) {
        if (!raw && this.t[this.i] === "\\") {
            var e = this.t[this.i + 1];
            var map = { n: "\n", t: "\t", r: "\r", '"': '"', "\\": "\\", b: "\b", f: "\f", s: " " };
            if (e in map) { out += map[e]; this.i += 2; continue; }
            if (e === "u") {
                var m = /^\\u\{([0-9a-fA-F]+)\}/.exec(this.t.slice(this.i));
                if (m) { out += String.fromCodePoint(parseInt(m[1], 16)); this.i += m[0].length; continue; }
            }
            out += e; this.i += 2; continue;
        }
        if (this.t.startsWith(closer, this.i)) { this.i += closer.length; break; }
        out += this.t[this.i]; this.i++;
    }
    return { value: out, raw: this.t.slice(start, this.i), range: [start, this.i] };
};

// Read a bare / number / keyword value. Returns {value, raw, range}.
Parser.prototype.readBare = function () {
    var start = this.i;
    // optional (type) annotation — skip but keep in raw
    if (this.t[this.i] === "(") {
        var d = 1; this.i++;
        while (!this.eof() && d > 0) { if (this.t[this.i] === "(") d++; else if (this.t[this.i] === ")") d--; this.i++; }
    }
    while (!this.eof()) {
        var c = this.t[this.i];
        if (c === "/" && (this.t[this.i + 1] === "/" || this.t[this.i + 1] === "*")) break;
        if (isWs(c) || c === "\n" || c === ";" || c === "{" || c === "}" || c === "=" || c === "\\") break;
        this.i++;
    }
    var raw = this.t.slice(start, this.i);
    var token = raw;
    // strip a leading (type)
    var tp = token.indexOf(")");
    if (token[0] === "(" && tp !== -1) token = token.slice(tp + 1);
    var value = token;
    if (token === "true" || token === "#true") value = true;
    else if (token === "false" || token === "#false") value = false;
    else if (token === "null" || token === "#null") value = null;
    else if (token === "#inf" || token === "#-inf" || token === "#nan") value = token;
    else if (/^[+-]?(\d[\d_]*)(\.\d[\d_]*)?([eE][+-]?\d+)?$/.test(token)) value = Number(token.replace(/_/g, ""));
    else if (/^0x[0-9a-fA-F_]+$/.test(token)) value = parseInt(token.replace(/_/g, ""), 16);
    return { value: value, raw: raw, range: [start, this.i] };
};

// Read one value (string or bare) at the cursor, or null if none.
Parser.prototype.readValue = function () {
    var c = this.t[this.i], c1 = this.t[this.i + 1];
    if (c === '"' || c === "#" || (c === "r" && (c1 === '"' || c1 === "#"))) {
        var s = this.readString();
        if (s) return s;
    }
    if (c === undefined || isWs(c) || c === "\n" || c === ";" || c === "{" || c === "}") return null;
    return this.readBare();
};

// Parse a single node at the cursor. Returns Node or null (e.g. at "}" / EOF).
Parser.prototype.parseNode = function () {
    this.skipWsAndNewlines();
    if (this.eof() || this.t[this.i] === "}") return null;

    var nodeStart = this.i;
    var slashdash = false;
    if (this.t[this.i] === "/" && this.t[this.i + 1] === "-") { slashdash = true; this.i += 2; this.skipInline(); }

    var nameVal = this.readValue();
    if (!nameVal) {
        // unexpected char; advance to avoid infinite loop
        if (!this.eof()) this.i++;
        return null;
    }
    var node = {
        name: String(nameVal.value),
        nameRange: nameVal.range.slice(),
        args: [],
        props: {},
        propsList: [],
        children: [],
        slashdash: slashdash,
        range: [nodeStart, this.i],
        headerRange: [nameVal.range[0], this.i],
        childrenRange: null
    };

    while (!this.eof()) {
        var iterStart = this.i;
        this.skipInline();
        var c = this.t[this.i];
        if (c === undefined || c === "\n" || c === ";") { break; }
        if (c === "}") { break; }
        // stray glue chars that cannot start a value — skip to guarantee progress
        if (c === "=" || c === "\\") { this.i++; continue; }
        if (c === "{") {
            // children block
            var braceOpen = this.i;
            this.i++;
            var childrenInnerStart = this.i;
            var kids = [];
            while (true) {
                this.skipWsAndNewlines();
                if (this.eof() || this.t[this.i] === "}") break;
                var kid = this.parseNode();
                if (kid) kids.push(kid); else break;
            }
            var childrenInnerEnd = this.i;
            if (this.t[this.i] === "}") this.i++;
            node.children = kids;
            node.childrenRange = [childrenInnerStart, childrenInnerEnd];
            node.headerRange[1] = braceOpen;
            break;
        }
        // slashdash on an entry/child
        if (c === "/" && this.t[this.i + 1] === "-") {
            this.i += 2; this.skipInline();
            if (this.t[this.i] === "{") { // disabled children block
                this.i++; var dd = 1;
                while (!this.eof() && dd > 0) { if (this.t[this.i] === "{") dd++; else if (this.t[this.i] === "}") dd--; this.i++; }
            } else {
                this.readValue();
                if (this.t[this.i] === "=") { this.i++; this.readValue(); }
            }
            continue;
        }
        // a value — could be arg or prop key
        var v = this.readValue();
        if (!v) { if (!this.eof()) this.i++; continue; }
        if (this.t[this.i] === "=") {
            // property
            var keyEnd = this.i;
            this.i++; // consume =
            var pv = this.readValue();
            var key = String(v.value);
            node.props[key] = pv ? pv.value : null;
            node.propsList.push({
                key: key, value: pv ? pv.value : null,
                raw: pv ? pv.raw : "", range: [v.range[0], pv ? pv.range[1] : this.i],
                keyRange: [v.range[0], keyEnd]
            });
        } else {
            node.args.push(v);
        }
        if (this.i === iterStart) this.i++; // hard progress guarantee
    }

    // consume terminator ";" (newline is left for skipWsAndNewlines)
    if (this.t[this.i] === ";") this.i++;
    node.range[1] = this.i;
    if (node.headerRange[1] < node.nameRange[1]) node.headerRange[1] = node.nameRange[1];
    return node;
};

// Parse a whole document → { text, nodes:[Node] }
function parse(text) {
    var p = new Parser(text);
    var nodes = [];
    var guard = 0;
    while (!p.eof()) {
        p.skipWsAndNewlines();
        if (p.eof()) break;
        var before = p.i;
        var node = p.parseNode();
        if (node) nodes.push(node);
        if (p.i <= before) { p.i = before + 1; } // safety
        if (++guard > 1000000) break;
    }
    return { text: text, nodes: nodes };
}

// ── tree helpers ────────────────────────────────────────────────────────────

// Depth-first walk in document order. cb(node, parent) is called for every node.
function walk(nodes, cb, parent) {
    for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i];
        cb(n, parent || null);
        if (n.children && n.children.length) walk(n.children, cb, n);
    }
}

// Find the first node matching name (case-insensitive), depth-first, stopping at
// the first hit — the sections call this dozens of times per recompute.
function findNode(doc, name, nodes) {
    var target = name.toLowerCase();
    var roots = nodes || doc.nodes;
    var stack = [];
    for (var i = roots.length - 1; i >= 0; i--) stack.push(roots[i]);
    while (stack.length) {
        var n = stack.pop();
        if (n.name.toLowerCase() === target) return n;
        var kids = n.children;
        if (kids) for (var j = kids.length - 1; j >= 0; j--) stack.push(kids[j]);
    }
    return null;
}

// ── surgical text edits (operate on raw text + ranges) ───────────────────────

// True when only whitespace separates pos from the start of its physical line.
function startsLine(text, pos) {
    while (pos > 0 && text[pos - 1] !== "\n") { if (!isWs(text[pos - 1])) return false; pos--; }
    return true;
}

// Expand a [start,end] range to cover full physical lines (incl. leading indent
// and the trailing newline) — but ONLY when those lines hold nothing but the node
// itself. A node that shares its line with anything else (`xkb { layout "us" }
// numlock`, `a 1; b 2`, an enclosing block opened on the same line) keeps its own
// range (minus the inter-token whitespace the parser swept up after it), so a
// line-oriented edit can never swallow a neighbour or the space before a brace.
function lineSpan(text, range) {
    var s = range[0], e = range[1];
    while (s > 0 && text[s - 1] !== "\n") s--;
    while (e < text.length && text[e] !== "\n") e++;
    var shared = !startsLine(text, range[0]);
    for (var i = range[1]; !shared && i < e; i++) if (!isWs(text[i])) shared = true;
    if (shared) {
        var ne = range[1];
        while (ne > range[0] && isWs(text[ne - 1])) ne--;
        return [range[0], ne];
    }
    if (e < text.length) e++;
    return [s, e];
}

// Indentation of the node's own line — "" when the node does not start the line
// (an inline child owns no indent; the enclosing line's indent is not its own).
function leadingIndent(text, range) {
    if (!startsLine(text, range[0])) return "";
    var s = range[0];
    while (s > 0 && text[s - 1] !== "\n") s--;
    return text.slice(s, range[0]);
}

// Replace the text covered by [start,end] with replacement.
function spliceText(text, range, replacement) {
    return text.slice(0, range[0]) + replacement + text.slice(range[1]);
}

// Replace a node's whole line(s) with newLine (no trailing newline expected).
// For a node sharing its line, only the node itself is replaced and its ";"
// terminator is kept so the following sibling stays a separate node.
function replaceNodeLine(text, node, newLine) {
    var span = lineSpan(text, node.range);
    var last = text[span[1] - 1];
    var trailing = "";
    if (last === "\n") trailing = "\n";
    else if (last === ";" && newLine.charAt(newLine.length - 1) !== ";") trailing = ";";
    return spliceText(text, span, newLine + trailing);
}

// Remove a node entirely (its full line span, or just itself — plus the inline
// whitespace that followed it — when it shares a line with a sibling).
function removeNodeLine(text, node) {
    var span = lineSpan(text, node.range);
    var e = span[1];
    if (text[e - 1] !== "\n") while (text[e] === " " || text[e] === "\t") e++;
    return spliceText(text, [span[0], e], "");
}

// Insert newLine as a child of parent, just before its closing "}".
// A single-line block stays on its line, the new node separated by ";" so it does
// not merge into the previous node's arguments. A multi-line block gets a fresh
// line indented like its siblings, continuation lines included, so a block
// inserted as `name {\n}` closes at its own indent.
function insertChildLine(text, parent, newLine) {
    if (!parent.childrenRange) return text;
    var innerStart = parent.childrenRange[0], innerEnd = parent.childrenRange[1];
    var at = innerEnd;
    while (at > innerStart && (text[at - 1] === " " || text[at - 1] === "\t")) at--;

    if (text.slice(innerStart, innerEnd).indexOf("\n") === -1) {
        var sep = at === innerStart ? " " : (text[at - 1] === ";" ? " " : "; ");
        return spliceText(text, [at, innerEnd], sep + newLine.replace(/\s*\n\s*/g, " ") + " ");
    }

    // derive child indent from an existing line-owning child, else parent indent + 4
    var kids = parent.children || [];
    var last = kids.length ? kids[kids.length - 1] : null;
    var indent = (last && startsLine(text, last.range[0]))
        ? leadingIndent(text, last.range)
        : leadingIndent(text, parent.range) + "    ";
    // sit on a fresh line, before the closing brace's own indentation
    if (at > 0 && text[at - 1] !== "\n") at = innerEnd;
    var prefix = (at > 0 && text[at - 1] !== "\n") ? "\n" : "";
    return spliceText(text, [at, at], prefix + indent + newLine.split("\n").join("\n" + indent) + "\n");
}

// Enable/disable a node in place by adding/removing a leading "/-" slashdash,
// preserving the rest of the line exactly (no reserialization).
function setDisabled(text, node, disabled) {
    var start = node.range[0];
    var hasSlash = text.slice(start, start + 2) === "/-";
    if (disabled && !hasSlash) return text.slice(0, start) + "/-" + text.slice(start);
    if (!disabled && hasSlash) return text.slice(0, start) + text.slice(start + 2);
    return text;
}

// Append a brand-new top-level node to the document text.
function appendNode(text, newText) {
    var sep = text.length === 0 || text.endsWith("\n") ? "" : "\n";
    return text + sep + newText + (newText.endsWith("\n") ? "" : "\n");
}

// ── block editing (path-addressed children of a named root block) ────────────

// First child named exactly `name`, or null.
function childNamed(node, name) {
    var kids = node && node.children ? node.children : null;
    if (!kids) return null;
    for (var i = 0; i < kids.length; i++) if (kids[i].name === name) return kids[i];
    return null;
}

// Parse text, find the `rootName` node, then descend pathArr by child name.
function blockPath(text, rootName, pathArr) {
    var cur = findNode(parse(text), rootName);
    var path = pathArr || [];
    for (var i = 0; cur && i < path.length; i++) cur = childNamed(cur, path[i]);
    return cur || null;
}

// Create every missing block along rootName + pathArr. Returns text unchanged
// when the whole path already exists.
function ensurePath(text, rootName, pathArr) {
    var path = pathArr || [];
    var root = findNode(parse(text), rootName);
    if (!root) {
        text = appendNode(text, rootName + " {\n}");
        root = findNode(parse(text), rootName);
    }
    for (var i = 0; i < path.length; i++) {
        var cur = root;
        for (var j = 0; cur && j < i; j++) cur = childNamed(cur, path[j]);
        if (!cur || childNamed(cur, path[i])) continue;
        text = insertChildLine(text, cur, path[i] + " {\n}");
        root = findNode(parse(text), rootName);
    }
    return text;
}

// Set the child `name` of the block at rootName + pathArr to the finished source
// line `line` (numeric/string coercion is the caller's job). line === null removes
// the child. Missing blocks along the path are created on demand.
function setChildLine(text, rootName, pathArr, name, line) {
    var block = blockPath(text, rootName, pathArr);
    var existing = block ? childNamed(block, name) : null;
    if (line === null) return existing ? removeNodeLine(text, existing) : text;
    if (existing) return replaceNodeLine(text, existing, leadingIndent(text, existing.range) + line);
    text = ensurePath(text, rootName, pathArr);
    block = blockPath(text, rootName, pathArr);
    return block ? insertChildLine(text, block, line) : text;
}

// Add/remove a bare flag node (e.g. `numlock`) in the block at rootName + pathArr.
function setChildFlag(text, rootName, pathArr, name, on) {
    var block = blockPath(text, rootName, pathArr);
    var existing = block ? childNamed(block, name) : null;
    if (!on) return existing ? removeNodeLine(text, existing) : text;
    if (existing) return text;
    text = ensurePath(text, rootName, pathArr);
    block = blockPath(text, rootName, pathArr);
    return block ? insertChildLine(text, block, name) : text;
}

// Apply many child edits to the same root block in one pass. `edits` is
//   [{ path: ["keyboard", "xkb"], name: "layout", line: 'layout "us"' | null }]
// The result is identical to folding
//   setChildLine(text, rootName, e.path, e.name, e.line)
// over `edits`, but the document is parsed ONCE for every edit whose target node
// already exists — only a first-time insert (which may have to create blocks
// along the path) falls back to the sequential primitive. `line === null` removes
// the child; a bare flag is `line === name` (on) / null (off). The caller must
// not pass two edits with the same (path, name).
function applyChildEdits(text, rootName, edits) {
    var list = edits || [];
    if (!list.length) return text;

    var root = findNode(parse(text), rootName);
    if (!root) {
        // Nothing exists yet: the sequential path creates the root block.
        for (var f = 0; f < list.length; f++)
            text = setChildLine(text, rootName, list[f].path, list[f].name, list[f].line);
        return text;
    }

    var splices = [];   // { node, line } — line === null means "remove"
    var deferred = [];  // edits whose target does not exist yet
    for (var k = 0; k < list.length; k++) {
        var e = list[k];
        var cur = root, p = e.path || [];
        for (var j = 0; cur && j < p.length; j++) cur = childNamed(cur, p[j]);
        var existing = cur ? childNamed(cur, e.name) : null;
        if (!existing) { if (e.line !== null) deferred.push(e); continue; }
        splices.push({ node: existing, line: e.line });
    }

    // Descending by range start: every splice leaves the ranges before it intact.
    // Targets are distinct nodes, so the ranges never overlap.
    splices.sort(function (a, b) { return b.node.range[0] - a.node.range[0]; });
    for (var s = 0; s < splices.length; s++) {
        var sp = splices[s];
        text = sp.line === null
            ? removeNodeLine(text, sp.node)
            : replaceNodeLine(text, sp.node, leadingIndent(text, sp.node.range) + sp.line);
    }

    // Inserts re-parse per edit — they only happen the first time a setting is written.
    for (var d = 0; d < deferred.length; d++) {
        var de = deferred[d];
        text = setChildLine(text, rootName, de.path, de.name, de.line);
    }
    return text;
}

// node-only export (no-op under QML where `module` is undefined)
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parse: parse, walk: walk, findNode: findNode,
        lineSpan: lineSpan, leadingIndent: leadingIndent, spliceText: spliceText,
        replaceNodeLine: replaceNodeLine, removeNodeLine: removeNodeLine,
        insertChildLine: insertChildLine, setDisabled: setDisabled, appendNode: appendNode,
        childNamed: childNamed, blockPath: blockPath, ensurePath: ensurePath,
        setChildLine: setChildLine, setChildFlag: setChildFlag,
        applyChildEdits: applyChildEdits
    };
}
