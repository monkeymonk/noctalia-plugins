.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// input.js — the `input {}` settings table plus read/diff/serialize/apply for
// the input editor. Pure ECMAScript, zero QML/Noctalia deps (kdl is injected):
// part of the v5-portable core. InputSection.qml owns only the properties and
// the widgets.
//
// One row per niri input option:
//   kind: flag (bare node) | bool (`name true|false`) | str | int | float
// ─────────────────────────────────────────────────────────────────────────────

var SETTINGS = [
    { prop: "layout", path: ["keyboard", "xkb"], name: "layout", kind: "str" },
    { prop: "variant", path: ["keyboard", "xkb"], name: "variant", kind: "str" },
    { prop: "options", path: ["keyboard", "xkb"], name: "options", kind: "str" },
    { prop: "model", path: ["keyboard", "xkb"], name: "model", kind: "str" },
    { prop: "trackLayout", path: ["keyboard"], name: "track-layout", kind: "str" },
    { prop: "numlock", path: ["keyboard"], name: "numlock", kind: "flag" },
    { prop: "repeatDelay", path: ["keyboard"], name: "repeat-delay", kind: "int" },
    { prop: "repeatRate", path: ["keyboard"], name: "repeat-rate", kind: "int" },

    { prop: "tpOff", path: ["touchpad"], name: "off", kind: "flag" },
    { prop: "tpTap", path: ["touchpad"], name: "tap", kind: "flag" },
    { prop: "tpDwt", path: ["touchpad"], name: "dwt", kind: "flag" },
    { prop: "tpDwtp", path: ["touchpad"], name: "dwtp", kind: "flag" },
    { prop: "tpNatural", path: ["touchpad"], name: "natural-scroll", kind: "flag" },
    { prop: "tpDrag", path: ["touchpad"], name: "drag", kind: "bool" },
    { prop: "tpDragLock", path: ["touchpad"], name: "drag-lock", kind: "flag" },
    { prop: "tpMiddleEmu", path: ["touchpad"], name: "middle-emulation", kind: "flag" },
    { prop: "tpLeftHanded", path: ["touchpad"], name: "left-handed", kind: "flag" },
    { prop: "tpDisabledExt", path: ["touchpad"], name: "disabled-on-external-mouse", kind: "flag" },
    { prop: "tpAccel", path: ["touchpad"], name: "accel-speed", kind: "float" },
    { prop: "tpAccelProfile", path: ["touchpad"], name: "accel-profile", kind: "str" },
    { prop: "tpScrollMethod", path: ["touchpad"], name: "scroll-method", kind: "str" },
    { prop: "tpClickMethod", path: ["touchpad"], name: "click-method", kind: "str" },
    { prop: "tpTapButtonMap", path: ["touchpad"], name: "tap-button-map", kind: "str" },

    { prop: "msOff", path: ["mouse"], name: "off", kind: "flag" },
    { prop: "msNatural", path: ["mouse"], name: "natural-scroll", kind: "flag" },
    { prop: "msMiddleEmu", path: ["mouse"], name: "middle-emulation", kind: "flag" },
    { prop: "msLeftHanded", path: ["mouse"], name: "left-handed", kind: "flag" },
    { prop: "msAccel", path: ["mouse"], name: "accel-speed", kind: "float" },
    { prop: "msAccelProfile", path: ["mouse"], name: "accel-profile", kind: "str" },
    { prop: "msScrollMethod", path: ["mouse"], name: "scroll-method", kind: "str" },

    { prop: "focusFollowsMouse", path: [], name: "focus-follows-mouse", kind: "flag" },
    { prop: "warpMouse", path: [], name: "warp-mouse-to-focus", kind: "flag" },
    { prop: "wsBackAndForth", path: [], name: "workspace-auto-back-and-forth", kind: "flag" },
    { prop: "disablePowerKey", path: [], name: "disable-power-key-handling", kind: "flag" },
    { prop: "modKey", path: [], name: "mod-key", kind: "str" }
];

// ── read ─────────────────────────────────────────────────────────────────────

// Descend a parsed node by child name.
function blockAt(node, pathArr, kdl) {
    var cur = node;
    for (var i = 0; cur && i < pathArr.length; i++) cur = kdl.childNamed(cur, pathArr[i]);
    return cur;
}

function readSetting(inputNode, d, kdl) {
    var b = blockAt(inputNode, d.path, kdl);
    var n = b ? kdl.childNamed(b, d.name) : null;
    if (d.kind === "flag") return !!n;
    // bool-valued node (e.g. `drag true`): value if present, true if bare, false if absent
    if (d.kind === "bool") return n ? (n.args[0] ? (n.args[0].value === true) : true) : false;
    return (n && n.args[0]) ? String(n.args[0].value) : "";
}

// Parse an `input` node (one walk per setting) → flat model keyed by `prop`.
function parse(inputNode, kdl) {
    var m = {};
    for (var i = 0; i < SETTINGS.length; i++) m[SETTINGS[i].prop] = readSetting(inputNode, SETTINGS[i], kdl);
    return m;
}

// ── write ────────────────────────────────────────────────────────────────────

// Rows whose value differs from the loaded snapshot: the setting def + its value.
function diff(model, orig) {
    var out = [];
    if (!model || !orig) return out;
    for (var i = 0; i < SETTINGS.length; i++) {
        var d = SETTINGS[i];
        if (model[d.prop] === orig[d.prop]) continue;
        out.push({ prop: d.prop, path: d.path, name: d.name, kind: d.kind, value: model[d.prop] });
    }
    return out;
}

// The finished KDL source line for one changed row, or null to remove the child.
function lineFor(d, v) {
    if (d.kind === "flag") return v ? d.name : null;
    if (d.kind === "bool") return d.name + " " + (v ? "true" : "false");
    if (d.kind === "int") return (v === "" || isNaN(parseInt(v))) ? null : (d.name + " " + parseInt(v));
    if (d.kind === "float") return (v === "" || isNaN(parseFloat(v))) ? null : (d.name + " " + parseFloat(v));
    return v ? (d.name + ' "' + v + '"') : null;
}

// Changed rows → the edit list Kdl.applyChildEdits consumes.
function edits(changed) {
    var out = [];
    for (var i = 0; i < (changed || []).length; i++) {
        var c = changed[i];
        out.push({ path: c.path, name: c.name, line: lineFor(c, c.value) });
    }
    return out;
}

// Apply every changed row to the config text in a single batched edit.
function apply(text, changed, kdl) {
    return kdl.applyChildEdits(text, "input", edits(changed));
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        SETTINGS: SETTINGS, parse: parse, diff: diff, edits: edits, apply: apply
    };
}
