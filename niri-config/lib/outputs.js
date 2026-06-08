.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// outputs.js — model + KDL serialization for `output "NAME" { … }` blocks.
// Operates on kdl.js nodes; no QML/Noctalia deps. Part of the v5-portable core.
// ─────────────────────────────────────────────────────────────────────────────

var TRANSFORMS = ["Normal", "90", "180", "270", "Flipped", "Flipped-90", "Flipped-180", "Flipped-270"];
var COMMON_SCALES = [1, 1.25, 1.5, 1.75, 2, 2.5, 3];

// Parse an `output` kdl node → editable model.
function parseOutput(node) {
    var m = { name: node.args[0] ? String(node.args[0].value) : "", node: node,
              off: false, mode: "", scale: null, x: null, y: null, transform: null,
              vrr: false, vrrOnDemand: false, focusAtStartup: false, backdropColor: "", maxBpc: null };
    (node.children || []).forEach(function (c) {
        switch (c.name) {
            case "off": m.off = true; break;
            case "mode": if (c.args[0]) m.mode = String(c.args[0].value); break;
            case "scale": if (c.args[0]) m.scale = Number(c.args[0].value); break;
            case "transform": if (c.args[0]) m.transform = String(c.args[0].value); break;
            case "position": m.x = c.props.x != null ? Number(c.props.x) : null;
                             m.y = c.props.y != null ? Number(c.props.y) : null; break;
            case "variable-refresh-rate": m.vrr = true; m.vrrOnDemand = (c.props && c.props["on-demand"] === true); break;
            case "focus-at-startup": m.focusAtStartup = true; break;
            case "backdrop-color": if (c.args[0]) m.backdropColor = String(c.args[0].value); break;
            case "max-bpc": if (c.args[0]) m.maxBpc = Number(c.args[0].value); break;
        }
    });
    return m;
}

// Serialize a model → KDL block text (no leading indent on first line). A
// disabled monitor uses `off` inside the block (niri's way), not slashdash.
function serializeOutput(m, indent) {
    indent = indent || "    ";
    var L = ['output "' + m.name + '" {'];
    if (m.off) L.push(indent + "off");
    if (m.mode) L.push(indent + 'mode "' + m.mode + '"');
    if (m.scale != null) L.push(indent + "scale " + m.scale);
    if (m.x != null && m.y != null) L.push(indent + "position x=" + m.x + " y=" + m.y);
    if (m.transform && m.transform !== "Normal") L.push(indent + 'transform "' + m.transform + '"');
    if (m.vrr) L.push(indent + "variable-refresh-rate" + (m.vrrOnDemand ? " on-demand=true" : ""));
    if (m.backdropColor) L.push(indent + 'backdrop-color "' + m.backdropColor + '"');
    if (m.focusAtStartup) L.push(indent + "focus-at-startup");
    L.push("}");
    return L.join("\n");
}

// Parse a niri mode string "WxH@R" → {width,height,refresh}.
function parseMode(s) {
    var m = /^(\d+)x(\d+)(?:@([\d.]+))?$/.exec(String(s).trim());
    if (!m) return null;
    return { width: +m[1], height: +m[2], refresh: m[3] ? +m[3] : null };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        TRANSFORMS: TRANSFORMS, COMMON_SCALES: COMMON_SCALES,
        parseOutput: parseOutput, serializeOutput: serializeOutput, parseMode: parseMode
    };
}
