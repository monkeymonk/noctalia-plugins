.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// binds.js — model + serialization for niri `binds {}` entries, plus the action
// vocabulary. Operates on kdl.js node objects (passed in); no QML/Noctalia deps.
// Part of the v5-portable core.
// ─────────────────────────────────────────────────────────────────────────────

// Modifier canonical names + display order for normalization/conflict detection.
var MOD_ORDER = ["Mod", "Super", "Ctrl", "Alt", "Shift", "ISO_Level3_Shift", "Mod5"];
var MOD_ALIASES = { control: "Ctrl", ctrl: "Ctrl", super: "Super", win: "Super", windows: "Super",
                    alt: "Alt", shift: "Shift", mod: "Mod", mod5: "Mod5", altgr: "ISO_Level3_Shift",
                    iso_level3_shift: "ISO_Level3_Shift" };

// Recognized bind-line attributes (KDL props on the bind node).
var BIND_ATTRS = ["hotkey-overlay-title", "repeat", "cooldown-ms", "allow-when-locked",
                  "allow-inhibiting", "hotkey-overlay-hidden"];

// ── parsing ──────────────────────────────────────────────────────────────────

// Turn a kdl bind node into a model. Keeps `node` for source ranges.
function parseBind(node) {
    return {
        node: node,
        combo: node.name,
        attrs: node.props || {},
        actions: (node.children || []).map(function (c) {
            return { name: c.name, args: (c.args || []).map(function (a) { return a.value; }) };
        }),
        disabled: !!node.slashdash
    };
}

// All binds inside a parsed `binds {}` node.
function parseBinds(bindsNode) {
    if (!bindsNode || !bindsNode.children) return [];
    return bindsNode.children.map(parseBind);
}

// ── combo normalization & conflicts ──────────────────────────────────────────

function splitCombo(combo) {
    return String(combo).split("+").map(function (s) { return s.trim(); }).filter(Boolean);
}

// Canonical string for conflict comparison: sorted mods + uppercased key.
function normalizeCombo(combo) {
    var parts = splitCombo(combo);
    if (!parts.length) return "";
    var key = parts.pop();
    var mods = parts.map(function (m) {
        var a = MOD_ALIASES[m.toLowerCase()];
        return a || m;
    });
    var seen = {}, ordered = [];
    MOD_ORDER.forEach(function (m) { if (mods.indexOf(m) !== -1 && !seen[m]) { ordered.push(m); seen[m] = 1; } });
    mods.forEach(function (m) { if (!seen[m]) { ordered.push(m); seen[m] = 1; } }); // unknown mods kept
    return ordered.join("+") + "+" + key.toUpperCase();
}

// Returns the first ENABLED bind whose combo conflicts, excluding `exceptNode`
// (the bind being edited). Matches by reference OR source-range identity, so it
// works even if the nodes came from a different parse of the same text.
function findConflict(binds, combo, exceptNode) {
    var norm = normalizeCombo(combo);
    var exRange = (exceptNode && exceptNode.range) ? exceptNode.range[0] : -1;
    for (var i = 0; i < binds.length; i++) {
        var b = binds[i];
        if (b.disabled) continue;
        if (exceptNode && (b.node === exceptNode || (b.node && b.node.range && b.node.range[0] === exRange))) continue;
        if (normalizeCombo(b.combo) === norm) return b;
    }
    return null;
}

// ── serialization ────────────────────────────────────────────────────────────

function quoteString(s) { return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'; }

function formatPropValue(v) {
    if (v === true) return "true";
    if (v === false) return "false";
    if (typeof v === "number") return String(v);
    return quoteString(v);
}

// Args for an action. Numbers stay bare (focus-workspace 1); strings get quoted
// (spawn "ghostty", set-column-width "-10%").
function formatActionArg(a) {
    if (typeof a === "number") return String(a);
    if (a === true) return "true";
    if (a === false) return "false";
    return quoteString(a);
}

function formatAction(act) {
    var s = act.name;
    if (act.args && act.args.length) s += " " + act.args.map(formatActionArg).join(" ");
    return s;
}

// Serialize one bind to a config line (no leading indent, no trailing newline).
// opts.padTo pads the combo to a column for alignment with existing binds.
function serializeBind(b, opts) {
    opts = opts || {};
    var combo = b.combo;
    var head = combo;
    // attributes in canonical order, then any extras
    var attrParts = [];
    BIND_ATTRS.forEach(function (k) {
        if (b.attrs && b.attrs[k] !== undefined) attrParts.push(k + "=" + formatPropValue(b.attrs[k]));
    });
    Object.keys(b.attrs || {}).forEach(function (k) {
        if (BIND_ATTRS.indexOf(k) === -1) attrParts.push(k + "=" + formatPropValue(b.attrs[k]));
    });
    if (opts.padTo && combo.length < opts.padTo) head = combo + " ".repeat(opts.padTo - combo.length);
    else head = combo + " ";
    var attrStr = attrParts.length ? attrParts.join(" ") + " " : "";
    var actStr = (b.actions || []).map(formatAction).join("; ");
    var line = head + attrStr + "{ " + actStr + (actStr ? "; " : "") + "}";
    if (b.disabled) line = "/-" + line;
    return line;
}

// Suggest an alignment column from a set of binds (max combo length + 2, capped).
function alignColumnFor(binds) {
    var max = 0;
    (binds || []).forEach(function (b) { if (b.combo.length > max) max = b.combo.length; });
    return Math.min(Math.max(max + 2, 20), 40);
}

// ── human-readable description (for list UI) ─────────────────────────────────

function describeAction(act) {
    if (!act) return "";
    if (act.name === "spawn" || act.name === "spawn-sh") {
        return (act.args && act.args.length) ? act.args.join(" ") : act.name;
    }
    var label = ACTION_LABELS[act.name];
    var base = label || act.name.replace(/-/g, " ");
    if (act.args && act.args.length) base += " " + act.args.join(" ");
    return base;
}

function describeBind(b) {
    return describeAction(b.actions && b.actions[0]);
}

// ── action vocabulary ────────────────────────────────────────────────────────
// arg types: "none" | "string" | "spawn" | "workspaceRef" | "amount" | "index"
var ACTIONS = [
    // Applications / system
    { name: "spawn", cat: "system", arg: "spawn" },
    { name: "spawn-sh", cat: "system", arg: "spawn" },
    { name: "close-window", cat: "window", arg: "none" },
    { name: "quit", cat: "system", arg: "none" },
    { name: "show-hotkey-overlay", cat: "system", arg: "none" },
    { name: "toggle-overview", cat: "system", arg: "none" },
    { name: "power-off-monitors", cat: "system", arg: "none" },
    { name: "power-on-monitors", cat: "system", arg: "none" },
    { name: "screenshot", cat: "system", arg: "none" },
    { name: "screenshot-screen", cat: "system", arg: "none" },
    { name: "screenshot-window", cat: "system", arg: "none" },
    { name: "toggle-keyboard-shortcuts-inhibit", cat: "system", arg: "none" },
    // Window / floating / fullscreen
    { name: "fullscreen-window", cat: "window", arg: "none" },
    { name: "toggle-windowed-fullscreen", cat: "window", arg: "none" },
    { name: "toggle-window-floating", cat: "window", arg: "none" },
    { name: "switch-focus-between-floating-and-tiling", cat: "window", arg: "none" },
    { name: "center-window", cat: "window", arg: "none" },
    // Focus
    { name: "focus-column-left", cat: "focus", arg: "none" },
    { name: "focus-column-right", cat: "focus", arg: "none" },
    { name: "focus-column-first", cat: "focus", arg: "none" },
    { name: "focus-column-last", cat: "focus", arg: "none" },
    { name: "focus-column-or-monitor-left", cat: "focus", arg: "none" },
    { name: "focus-column-or-monitor-right", cat: "focus", arg: "none" },
    { name: "focus-window-up", cat: "focus", arg: "none" },
    { name: "focus-window-down", cat: "focus", arg: "none" },
    { name: "focus-window-or-workspace-up", cat: "focus", arg: "none" },
    { name: "focus-window-or-workspace-down", cat: "focus", arg: "none" },
    { name: "focus-workspace-up", cat: "focus", arg: "none" },
    { name: "focus-workspace-down", cat: "focus", arg: "none" },
    { name: "focus-workspace-previous", cat: "focus", arg: "none" },
    { name: "focus-workspace", cat: "focus", arg: "workspaceRef" },
    { name: "focus-monitor-left", cat: "focus", arg: "none" },
    { name: "focus-monitor-right", cat: "focus", arg: "none" },
    { name: "focus-monitor-up", cat: "focus", arg: "none" },
    { name: "focus-monitor-down", cat: "focus", arg: "none" },
    // Move
    { name: "move-column-left", cat: "move", arg: "none" },
    { name: "move-column-right", cat: "move", arg: "none" },
    { name: "move-column-to-first", cat: "move", arg: "none" },
    { name: "move-column-to-last", cat: "move", arg: "none" },
    { name: "move-column-left-or-to-monitor-left", cat: "move", arg: "none" },
    { name: "move-column-right-or-to-monitor-right", cat: "move", arg: "none" },
    { name: "move-window-up", cat: "move", arg: "none" },
    { name: "move-window-down", cat: "move", arg: "none" },
    { name: "move-window-up-or-to-workspace-up", cat: "move", arg: "none" },
    { name: "move-window-down-or-to-workspace-down", cat: "move", arg: "none" },
    { name: "move-column-to-workspace", cat: "move", arg: "workspaceRef" },
    { name: "move-window-to-workspace", cat: "move", arg: "workspaceRef" },
    { name: "move-column-to-monitor-left", cat: "move", arg: "none" },
    { name: "move-column-to-monitor-right", cat: "move", arg: "none" },
    { name: "move-column-to-monitor-up", cat: "move", arg: "none" },
    { name: "move-column-to-monitor-down", cat: "move", arg: "none" },
    // Sizing / layout
    { name: "set-column-width", cat: "layout", arg: "amount" },
    { name: "set-window-height", cat: "layout", arg: "amount" },
    { name: "expand-column-to-available-width", cat: "layout", arg: "none" },
    { name: "maximize-column", cat: "layout", arg: "none" },
    { name: "center-column", cat: "layout", arg: "none" },
    { name: "center-visible-columns", cat: "layout", arg: "none" },
    { name: "switch-preset-column-width", cat: "layout", arg: "none" },
    { name: "switch-preset-window-height", cat: "layout", arg: "none" },
    { name: "toggle-column-tabbed-display", cat: "layout", arg: "none" },
    { name: "consume-window-into-column", cat: "layout", arg: "none" },
    { name: "expel-window-from-column", cat: "layout", arg: "none" },
    { name: "consume-or-expel-window-left", cat: "layout", arg: "none" },
    { name: "consume-or-expel-window-right", cat: "layout", arg: "none" }
];

var ACTION_LABELS = {};
ACTIONS.forEach(function (a) { ACTION_LABELS[a.name] = a.name.replace(/-/g, " "); });

function actionSpec(name) {
    for (var i = 0; i < ACTIONS.length; i++) if (ACTIONS[i].name === name) return ACTIONS[i];
    return null;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        MOD_ORDER: MOD_ORDER, BIND_ATTRS: BIND_ATTRS, ACTIONS: ACTIONS,
        parseBind: parseBind, parseBinds: parseBinds, splitCombo: splitCombo,
        normalizeCombo: normalizeCombo, findConflict: findConflict,
        serializeBind: serializeBind, alignColumnFor: alignColumnFor,
        describeBind: describeBind, describeAction: describeAction, actionSpec: actionSpec,
        quoteString: quoteString
    };
}
