.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// layout.js — model + KDL serialization for the niri `layout { … }` block.
//
// PORTABILITY: pure ECMAScript, zero QML/Noctalia deps. Part of the v5-portable
// core (see README). The kdl module is passed in by the caller (`kdl` param) so
// this file needs no import machinery: QML hands it its `Kdl` import, Node hands
// it the `require`d lib/kdl.js.
//
// SETTINGS is the single source of truth: one row per option, driving read,
// dirty-diff and save. kind:
//   flag   — bare node (`always-center-single-column`)
//   bool   — `name true|false`
//   str    — `name "value"`
//   enum   — like str, plus `def` (fallback when absent) and optional
//            `omitDefault` (write nothing when the value equals `def`)
//   float  — `name <number>`
//   preset — `name { proportion|fixed … }`, edited as a "0.5, 1280px" string
// ─────────────────────────────────────────────────────────────────────────────

var SETTINGS = [
    { prop: "gaps", path: [], name: "gaps", kind: "float" },
    { prop: "centerFocused", path: [], name: "center-focused-column", kind: "enum", def: "never" },
    { prop: "alwaysCenterSingle", path: [], name: "always-center-single-column", kind: "flag" },
    { prop: "emptyWsAbove", path: [], name: "empty-workspace-above-first", kind: "flag" },
    { prop: "defaultColDisplay", path: [], name: "default-column-display", kind: "enum", def: "normal", omitDefault: true },
    { prop: "background", path: [], name: "background-color", kind: "str" },
    { prop: "presetCols", path: [], name: "preset-column-widths", kind: "preset" },
    { prop: "presetHeights", path: [], name: "preset-window-heights", kind: "preset" },
    { prop: "defaultColWidth", path: [], name: "default-column-width", kind: "preset" },

    { prop: "frDisabled", path: ["focus-ring"], name: "off", kind: "flag" },
    { prop: "frWidth", path: ["focus-ring"], name: "width", kind: "float" },
    { prop: "frActive", path: ["focus-ring"], name: "active-color", kind: "str" },
    { prop: "frInactive", path: ["focus-ring"], name: "inactive-color", kind: "str" },
    { prop: "frUrgent", path: ["focus-ring"], name: "urgent-color", kind: "str" },

    { prop: "borderEnabled", path: ["border"], name: "on", kind: "flag" },
    { prop: "borderWidth", path: ["border"], name: "width", kind: "float" },
    { prop: "borderActive", path: ["border"], name: "active-color", kind: "str" },
    { prop: "borderInactive", path: ["border"], name: "inactive-color", kind: "str" },

    { prop: "shadowEnabled", path: ["shadow"], name: "on", kind: "flag" },
    { prop: "shadowSoftness", path: ["shadow"], name: "softness", kind: "float" },
    { prop: "shadowSpread", path: ["shadow"], name: "spread", kind: "float" },
    { prop: "shadowColor", path: ["shadow"], name: "color", kind: "str" },
    { prop: "shadowBehind", path: ["shadow"], name: "draw-behind-window", kind: "bool" },

    { prop: "tabDisabled", path: ["tab-indicator"], name: "off", kind: "flag" },
    { prop: "tabWidth", path: ["tab-indicator"], name: "width", kind: "float" },
    { prop: "tabGap", path: ["tab-indicator"], name: "gap", kind: "float" },
    { prop: "tabPosition", path: ["tab-indicator"], name: "position", kind: "str" },
    { prop: "tabHideSingle", path: ["tab-indicator"], name: "hide-when-single-tab", kind: "flag" },
    { prop: "tabActive", path: ["tab-indicator"], name: "active-color", kind: "str" },
    { prop: "tabInactive", path: ["tab-indicator"], name: "inactive-color", kind: "str" },

    { prop: "insertDisabled", path: ["insert-hint"], name: "off", kind: "flag" },
    { prop: "insertColor", path: ["insert-hint"], name: "color", kind: "str" },

    { prop: "strutL", path: ["struts"], name: "left", kind: "float" },
    { prop: "strutR", path: ["struts"], name: "right", kind: "float" },
    { prop: "strutT", path: ["struts"], name: "top", kind: "float" },
    { prop: "strutB", path: ["struts"], name: "bottom", kind: "float" }
];

// ── read ─────────────────────────────────────────────────────────────────────

// A preset block → the editable "0.33, 1280px" string.
function presetToStr(node) {
    if (!node) return "";
    return (node.children || []).map(function (c) {
        if (c.name === "proportion" && c.args[0]) return String(c.args[0].value);
        if (c.name === "fixed" && c.args[0]) return c.args[0].value + "px";
        return "";
    }).filter(Boolean).join(", ");
}

// Descend a parsed node by child name.
function blockAt(node, pathArr, kdl) {
    var cur = node;
    for (var i = 0; cur && i < pathArr.length; i++) cur = kdl.childNamed(cur, pathArr[i]);
    return cur;
}

function readSetting(layoutNode, d, kdl) {
    var b = blockAt(layoutNode, d.path, kdl);
    var n = b ? kdl.childNamed(b, d.name) : null;
    if (d.kind === "flag" || d.kind === "bool") return !!n;
    if (d.kind === "preset") return presetToStr(n);
    var s = (n && n.args[0]) ? String(n.args[0].value) : "";
    return s || (d.def || "");
}

// Parse a `layout` node (one parsed tree, walked once per setting) → flat model
// keyed by SETTINGS[].prop.
function parse(layoutNode, kdl) {
    var m = {};
    for (var i = 0; i < SETTINGS.length; i++) m[SETTINGS[i].prop] = readSetting(layoutNode, SETTINGS[i], kdl);
    return m;
}

// ── diff ─────────────────────────────────────────────────────────────────────

// Settings whose value differs from the last-read snapshot.
function diff(model, orig) {
    var out = [];
    if (!model || !orig) return out;
    for (var i = 0; i < SETTINGS.length; i++) {
        var d = SETTINGS[i];
        if (model[d.prop] !== orig[d.prop]) out.push({ prop: d.prop, def: d, value: model[d.prop] });
    }
    return out;
}

// ── write ────────────────────────────────────────────────────────────────────

// Serialize changed settings into one batch of child edits (for
// kdl.applyChildEdits) plus the preset blocks, which need their own text rewrite.
function edits(changed) {
    var childEdits = [], presets = [];
    for (var i = 0; i < changed.length; i++) {
        var d = changed[i].def, v = changed[i].value, line = null;
        if (d.kind === "preset") { presets.push({ name: d.name, value: v }); continue; }
        if (d.kind === "flag") {
            line = v ? d.name : null;
        } else if (d.kind === "bool") {
            line = d.name + " " + (v ? "true" : "false");
        } else if (d.kind === "float") {
            line = (v === "" || isNaN(parseFloat(v))) ? null : (d.name + " " + parseFloat(v));
        } else {
            var s = (d.omitDefault && v === d.def) ? "" : v;
            line = s ? (d.name + ' "' + s + '"') : null;
        }
        childEdits.push({ path: d.path, name: d.name, line: line });
    }
    return { childEdits: childEdits, presets: presets };
}

// Replace/insert/remove a whole preset-style block from a "0.5, 1280px" string.
function setPreset(text, name, valuesStr, kdl) {
    var toks = String(valuesStr).split(",").map(function (s) { return s.trim(); }).filter(Boolean);
    var L = kdl.blockPath(text, "layout", []);
    var ex = L ? kdl.childNamed(L, name) : null;
    if (!toks.length) return ex ? kdl.removeNodeLine(text, ex) : text;
    var inner = "    ";
    var lines = [name + " {"];
    toks.forEach(function (tk) {
        if (/px$/i.test(tk)) lines.push(inner + "fixed " + parseInt(tk));
        else lines.push(inner + "proportion " + parseFloat(tk));
    });
    lines.push("}");
    var blockText = lines.join("\n");
    if (ex) return kdl.replaceNodeLine(text, ex, kdl.leadingIndent(text, ex.range) + blockText);
    text = kdl.ensurePath(text, "layout", []);
    var root = kdl.blockPath(text, "layout", []);
    return root ? kdl.insertChildLine(text, root, blockText) : text;
}

// Apply the changed settings to the config text: one batched child-edit pass,
// then the preset rewrites folded on top.
function apply(text, changed, kdl) {
    var e = edits(changed);
    if (e.childEdits.length) text = kdl.applyChildEdits(text, "layout", e.childEdits);
    for (var i = 0; i < e.presets.length; i++) text = setPreset(text, e.presets[i].name, e.presets[i].value, kdl);
    return text;
}

// node-only export (no-op under QML where `module` is undefined)
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        SETTINGS: SETTINGS,
        presetToStr: presetToStr, readSetting: readSetting,
        parse: parse, diff: diff, edits: edits, setPreset: setPreset, apply: apply
    };
}
