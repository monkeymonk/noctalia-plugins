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

// Depth-first walk. cb(node, parent) -> if returns false, skip children.
function walk(nodes, cb, parent) {
    for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i];
        var r = cb(n, parent || null);
        if (r !== false && n.children && n.children.length) walk(n.children, cb, n);
    }
}

// Find the first top-level (or nested) node matching name (case-insensitive).
function findNode(doc, name, nodes) {
    var target = name.toLowerCase();
    var hit = null;
    walk(nodes || doc.nodes, function (n) {
        if (!hit && n.name.toLowerCase() === target) { hit = n; return false; }
    });
    return hit;
}

function findNodes(nodes, predicate) {
    var out = [];
    walk(nodes, function (n) { if (predicate(n)) out.push(n); });
    return out;
}

// ── surgical text edits (operate on raw text + ranges) ───────────────────────

// Expand a [start,end] range to cover full physical lines (incl. leading indent
// and the trailing newline). Used to cleanly remove/replace line-oriented nodes.
function lineSpan(text, range) {
    var s = range[0], e = range[1];
    while (s > 0 && text[s - 1] !== "\n") s--;
    while (e < text.length && text[e] !== "\n") e++;
    if (e < text.length && text[e] === "\n") e++;
    return [s, e];
}

function leadingIndent(text, range) {
    var s = range[0];
    while (s > 0 && text[s - 1] !== "\n") s--;
    var ind = "";
    for (var i = s; i < text.length && (text[i] === " " || text[i] === "\t"); i++) ind += text[i];
    return ind;
}

// Replace the text covered by [start,end] with replacement.
function spliceText(text, range, replacement) {
    return text.slice(0, range[0]) + replacement + text.slice(range[1]);
}

// Replace a node's whole line(s) with newLine (no trailing newline expected).
function replaceNodeLine(text, node, newLine) {
    var span = lineSpan(text, node.range);
    var trailing = text[span[1] - 1] === "\n" ? "\n" : "";
    return spliceText(text, span, newLine + trailing);
}

// Remove a node entirely (its full line span).
function removeNodeLine(text, node) {
    return spliceText(text, lineSpan(text, node.range), "");
}

// Comment out a node by line: prefix each physical line with "// ".
function commentOutNodeLine(text, node) {
    var span = lineSpan(text, node.range);
    var block = text.slice(span[0], span[1]);
    var commented = block.replace(/^(\s*)(?=\S)/gm, "$1// ");
    return spliceText(text, span, commented);
}

// Insert newLine just before the closing "}" of parent (as a child), using the
// indentation of existing children when available. parent.childrenRange must be set.
function insertChildLine(text, parent, newLine) {
    if (!parent.childrenRange) return text;
    var insertAt = parent.childrenRange[1];
    // derive child indent from an existing child, else parent indent + 4 spaces
    var indent;
    if (parent.children && parent.children.length) {
        indent = leadingIndent(text, parent.children[parent.children.length - 1].range);
    } else {
        indent = leadingIndent(text, parent.range) + "    ";
    }
    // ensure we sit on a fresh line
    var prefix = (insertAt > 0 && text[insertAt - 1] !== "\n") ? "\n" : "";
    return spliceText(text, [insertAt, insertAt], prefix + indent + newLine + "\n");
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

// node-only export (no-op under QML where `module` is undefined)
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parse: parse, walk: walk, findNode: findNode, findNodes: findNodes,
        lineSpan: lineSpan, leadingIndent: leadingIndent, spliceText: spliceText,
        replaceNodeLine: replaceNodeLine, removeNodeLine: removeNodeLine,
        commentOutNodeLine: commentOutNodeLine, insertChildLine: insertChildLine,
        setDisabled: setDisabled, appendNode: appendNode
    };
}
