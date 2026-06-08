.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// xkb.js — parse /usr/share/X11/xkb/rules/evdev.lst into layouts/variants/
// options for the keyboard editor. QML reads the file; this parses it. Part of
// the v5-portable core. Falls back to a curated subset when the file is absent.
// ─────────────────────────────────────────────────────────────────────────────

var FALLBACK_LAYOUTS = [
    { code: "us", desc: "English (US)" }, { code: "gb", desc: "English (UK)" },
    { code: "fr", desc: "French" }, { code: "de", desc: "German" },
    { code: "es", desc: "Spanish" }, { code: "it", desc: "Italian" },
    { code: "ca", desc: "French (Canada)" }, { code: "ch", desc: "Swiss" },
    { code: "ru", desc: "Russian" }, { code: "jp", desc: "Japanese" }
];

// evdev.lst is sectioned: "! layout", "! variant", "! option", "! model".
// Lines: "<code><whitespace><description>"; variant lines have a 3rd column (layout).
function parseEvdevList(text) {
    var res = { models: [], layouts: [], variants: [], options: [] };
    if (!text) return withFallback(res);
    var section = null;
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var t = line.trim();
        if (!t) continue;
        if (t[0] === "!") {
            var s = t.slice(1).trim().toLowerCase();
            section = (s === "layout" || s === "variant" || s === "option" || s === "model") ? s : null;
            continue;
        }
        if (!section) continue;
        var m = /^(\S+)\s+(.*)$/.exec(t);
        if (!m) continue;
        var code = m[1], rest = m[2].trim();
        if (section === "variant") {
            // "<variant> <layout>: <description>"  OR  "<variant>  <description>"
            var vm = /^(\S+):\s*(.*)$/.exec(rest);
            if (vm) res.variants.push({ code: code, layout: vm[1], desc: vm[2] });
            else res.variants.push({ code: code, layout: null, desc: rest });
        } else if (section === "layout") {
            res.layouts.push({ code: code, desc: rest });
        } else if (section === "option") {
            res.options.push({ code: code, desc: rest });
        } else if (section === "model") {
            res.models.push({ code: code, desc: rest });
        }
    }
    return withFallback(res);
}

function withFallback(res) {
    if (!res.layouts.length) res.layouts = FALLBACK_LAYOUTS.slice();
    return res;
}

function variantsForLayout(parsed, layoutCode) {
    return (parsed.variants || []).filter(function (v) { return v.layout === layoutCode; });
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        FALLBACK_LAYOUTS: FALLBACK_LAYOUTS, parseEvdevList: parseEvdevList,
        variantsForLayout: variantsForLayout
    };
}
