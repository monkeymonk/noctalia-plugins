.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// rules.js — parse/serialize niri window-rule / layer-rule blocks, plus a helper
// to seed a match from a live window. Operates on kdl.js nodes. v5-portable core.
// ─────────────────────────────────────────────────────────────────────────────

// niri match values are regexes; raw-string them when they contain metachars so
// we don't have to escape, otherwise a plain quoted string.
function fmtMatchVal(v) {
    v = String(v);
    if (/[\\^$.*+?()[\]{}|]/.test(v)) return 'r#"' + v + '"#';
    return '"' + v.replace(/"/g, '\\"') + '"';
}

function findChildNumber(node, childName) {
    var kids = node.children || [];
    for (var i = 0; i < kids.length; i++)
        if (kids[i].name === childName && kids[i].args[0]) return Number(kids[i].args[0].value);
    return null;
}

// Parse a match/exclude node → plain object of its props (app-id, title, …).
function parseMatch(node) {
    var m = {};
    for (var k in (node.props || {})) m[k] = node.props[k];
    return m;
}

var MODELED_RULE_CHILDREN = {
    "match": 1, "exclude": 1, "open-floating": 1, "open-maximized": 1, "open-fullscreen": 1,
    "open-focused": 1, "open-maximized-to-edges": 1, "open-on-workspace": 1, "open-on-output": 1,
    "default-column-width": 1, "default-window-height": 1, "default-column-display": 1,
    "default-floating-position": 1, "opacity": 1, "scroll-factor": 1, "variable-refresh-rate": 1,
    "draw-border-with-background": 1, "geometry-corner-radius": 1, "clip-to-geometry": 1,
    "tiled-state": 1, "baba-is-float": 1, "block-out-from": 1,
    "min-width": 1, "max-width": 1, "min-height": 1, "max-height": 1
};

function boolArg(c) { return c.args[0] ? (c.args[0].value === true) : true; }

// Parse a window-rule / layer-rule node → editable model (keeps node for ranges).
// Pass `text` (the source) to capture unmodeled child nodes verbatim so an edit
// can re-emit them losslessly.
function parseRule(node, text) {
    var r = { node: node, kind: node.name, matches: [], excludes: [], props: {}, rawExtras: [], disabled: !!node.slashdash };
    (node.children || []).forEach(function (c) {
        switch (c.name) {
            case "match": r.matches.push(parseMatch(c)); break;
            case "exclude": r.excludes.push(parseMatch(c)); break;
            case "open-floating": r.props.openFloating = c.args[0] ? c.args[0].value : true; break;
            case "open-maximized": r.props.openMaximized = c.args[0] ? c.args[0].value : true; break;
            case "open-fullscreen": r.props.openFullscreen = c.args[0] ? c.args[0].value : true; break;
            case "open-focused": r.props.openFocused = c.args[0] ? c.args[0].value : true; break;
            case "open-on-workspace": r.props.openOnWorkspace = c.args[0] ? String(c.args[0].value) : ""; break;
            case "open-on-output": r.props.openOnOutput = c.args[0] ? String(c.args[0].value) : ""; break;
            case "default-column-width": r.props.colWidth = findChildNumber(c, "proportion"); break;
            case "default-window-height": r.props.winHeight = findChildNumber(c, "proportion"); break;
            case "open-maximized-to-edges": r.props.openMaxToEdges = boolArg(c); break;
            case "default-column-display": r.props.defaultColDisplay = c.args[0] ? String(c.args[0].value) : ""; break;
            case "block-out-from": r.props.blockOutFrom = c.args[0] ? String(c.args[0].value) : ""; break;
            case "opacity": r.props.opacity = c.args[0] ? Number(c.args[0].value) : null; break;
            case "scroll-factor": r.props.scrollFactor = c.args[0] ? Number(c.args[0].value) : null; break;
            case "variable-refresh-rate": r.props.vrr = boolArg(c); break;
            case "draw-border-with-background": r.props.drawBorderWithBg = boolArg(c); break;
            case "clip-to-geometry": r.props.clipToGeometry = boolArg(c); break;
            case "tiled-state": r.props.tiledState = boolArg(c); break;
            case "baba-is-float": r.props.babaIsFloat = boolArg(c); break;
            case "geometry-corner-radius": r.props.cornerRadius = (c.args || []).map(function (a) { return a.value; }).join(" "); break;
            case "min-width": r.props.minWidth = c.args[0] ? Number(c.args[0].value) : null; break;
            case "max-width": r.props.maxWidth = c.args[0] ? Number(c.args[0].value) : null; break;
            case "min-height": r.props.minHeight = c.args[0] ? Number(c.args[0].value) : null; break;
            case "max-height": r.props.maxHeight = c.args[0] ? Number(c.args[0].value) : null; break;
            case "default-floating-position":
                r.props.floatPos = { x: c.props.x, y: c.props.y, relativeTo: c.props["relative-to"] || "" }; break;
            default:
                if (text) r.rawExtras.push(text.slice(c.range[0], c.range[1]));
        }
    });
    return r;
}

// Emit ALL props of a match (app-id/title as regex; booleans as-is; anything
// else preserved) so unknown match criteria survive an edit.
function serializeMatch(keyword, m) {
    var parts = [];
    for (var k in m) {
        var v = m[k];
        if (v === true) parts.push(k + "=true");
        else if (v === false) parts.push(k + "=false");
        else if (typeof v === "number") parts.push(k + "=" + v);
        else parts.push(k + "=" + fmtMatchVal(v));
    }
    if (!parts.length) return null;
    return keyword + " " + parts.join(" ");
}

// Serialize a rule model → KDL block (no leading indent on first line).
function serializeRule(r, indent) {
    indent = indent || "    ";
    var L = [(r.disabled ? "/-" : "") + (r.kind || "window-rule") + " {"];
    (r.matches || []).forEach(function (m) { var s = serializeMatch("match", m); if (s) L.push(indent + s); });
    (r.excludes || []).forEach(function (m) { var s = serializeMatch("exclude", m); if (s) L.push(indent + s); });
    var p = r.props || {};
    function emitBool(name, v) { if (v !== undefined) L.push(indent + name + " " + (v ? "true" : "false")); }
    emitBool("open-floating", p.openFloating);
    emitBool("open-maximized", p.openMaximized);
    emitBool("open-fullscreen", p.openFullscreen);
    emitBool("open-focused", p.openFocused);
    emitBool("open-maximized-to-edges", p.openMaxToEdges);
    emitBool("variable-refresh-rate", p.vrr);
    emitBool("draw-border-with-background", p.drawBorderWithBg);
    emitBool("clip-to-geometry", p.clipToGeometry);
    emitBool("tiled-state", p.tiledState);
    emitBool("baba-is-float", p.babaIsFloat);
    if (p.openOnWorkspace) L.push(indent + 'open-on-workspace "' + p.openOnWorkspace + '"');
    if (p.openOnOutput) L.push(indent + 'open-on-output "' + p.openOnOutput + '"');
    if (p.defaultColDisplay) L.push(indent + 'default-column-display "' + p.defaultColDisplay + '"');
    if (p.blockOutFrom) L.push(indent + 'block-out-from "' + p.blockOutFrom + '"');
    if (p.opacity != null) L.push(indent + "opacity " + p.opacity);
    if (p.scrollFactor != null) L.push(indent + "scroll-factor " + p.scrollFactor);
    if (p.cornerRadius) L.push(indent + "geometry-corner-radius " + p.cornerRadius);
    if (p.minWidth != null) L.push(indent + "min-width " + p.minWidth);
    if (p.maxWidth != null) L.push(indent + "max-width " + p.maxWidth);
    if (p.minHeight != null) L.push(indent + "min-height " + p.minHeight);
    if (p.maxHeight != null) L.push(indent + "max-height " + p.maxHeight);
    if (p.colWidth != null) L.push(indent + "default-column-width { proportion " + p.colWidth + "; }");
    if (p.winHeight != null) L.push(indent + "default-window-height { proportion " + p.winHeight + "; }");
    if (p.floatPos && (p.floatPos.x != null || p.floatPos.y != null)) {
        var fp = "default-floating-position x=" + (p.floatPos.x || 0) + " y=" + (p.floatPos.y || 0);
        if (p.floatPos.relativeTo) fp += ' relative-to="' + p.floatPos.relativeTo + '"';
        L.push(indent + fp);
    }
    // re-emit unmodeled child nodes verbatim (indent each line)
    (r.rawExtras || []).forEach(function (raw) {
        L.push(indent + String(raw).split("\n").join("\n" + indent));
    });
    L.push("}");
    return L.join("\n");
}

// Seed a match object from a live window ({appId, title}).
function matchFromWindow(win) {
    var m = {};
    if (win && win.appId) m["app-id"] = win.appId;
    if (win && win.title) m.title = win.title;
    return m;
}

// Human summary of a rule for the list view.
function describeRule(r) {
    var bits = [];
    (r.matches || []).forEach(function (m) {
        var s = [];
        if (m["app-id"]) s.push(m["app-id"]);
        if (m.title) s.push('“' + m.title + '”');
        if (s.length) bits.push(s.join(" · "));
    });
    var head = bits.length ? bits.join(", ") : "any window";
    var props = [];
    var p = r.props || {};
    if (p.openFloating) props.push("floating");
    if (p.openMaximized) props.push("maximized");
    if (p.openFullscreen) props.push("fullscreen");
    if (p.openOnWorkspace) props.push("→ " + p.openOnWorkspace);
    if (p.openOnOutput) props.push("@ " + p.openOnOutput);
    if (p.colWidth != null) props.push("w " + Math.round(p.colWidth * 100) + "%");
    return head + (props.length ? "  —  " + props.join(", ") : "");
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        fmtMatchVal: fmtMatchVal, parseMatch: parseMatch, parseRule: parseRule,
        serializeMatch: serializeMatch, serializeRule: serializeRule,
        matchFromWindow: matchFromWindow, describeRule: describeRule
    };
}
