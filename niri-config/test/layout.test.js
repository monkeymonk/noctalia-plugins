// Logic tests for lib/layout.js — the layout section's model (parse/diff/edits/apply).
// Run: node niri-config/test/layout.test.js
const { loadLib } = require("./_load");

const K = loadLib("lib/kdl.js");
const L = loadLib("lib/layout.js");

let pass = 0, fail = 0;
function ok(name, cond, extra) {
    if (cond) { pass++; } else { fail++; console.log("  ✗ " + name + (extra ? "  " + extra : "")); }
}

// ── fixture ─────────────────────────────────────────────────────────────────
// Covers every kind: flag, bool, float, str, enum (with and without
// omitDefault), preset (mixed proportion/fixed) — plus absent settings.
const fixture = `// niri config
layout {
    gaps 12
    center-focused-column "on-overflow"
    always-center-single-column
    default-column-display "tabbed"
    background-color "#000000"
    preset-column-widths {
        proportion 0.33
        fixed 1280
    }
    default-column-width { proportion 0.5; }
    focus-ring {
        off
        width 3
        active-color "#7fc8ff"
    }
    shadow {
        softness 30
        draw-behind-window true
    }
    // keep me — an unrelated comment
    struts {
        left 8
    }
}
`;

function layoutNode(text) { return K.findNode(K.parse(text), "layout"); }

// ── parse ───────────────────────────────────────────────────────────────────
const m0 = L.parse(layoutNode(fixture), K);
ok("parse float", m0.gaps === "12", m0.gaps);
ok("parse enum", m0.centerFocused === "on-overflow", m0.centerFocused);
ok("parse enum omitDefault", m0.defaultColDisplay === "tabbed", m0.defaultColDisplay);
ok("parse flag present", m0.alwaysCenterSingle === true);
ok("parse flag absent", m0.emptyWsAbove === false);
ok("parse bool", m0.shadowBehind === true);
ok("parse str", m0.background === "#000000", m0.background);
ok("parse nested flag", m0.frDisabled === true);
ok("parse nested float", m0.frWidth === "3", m0.frWidth);
ok("parse nested str", m0.frActive === "#7fc8ff", m0.frActive);
ok("parse preset mixed", m0.presetCols === "0.33, 1280px", m0.presetCols);
ok("parse preset inline", m0.defaultColWidth === "0.5", m0.defaultColWidth);
ok("parse absent preset", m0.presetHeights === "");
ok("parse absent str", m0.tabPosition === "");
ok("parse absent enum falls back to def", m0.centerFocused !== "" && L.parse(layoutNode("layout {\n}"), K).centerFocused === "never");
ok("parse absent bool", L.parse(layoutNode("layout {\n}"), K).shadowBehind === false);
ok("parse covers every setting", Object.keys(m0).length === L.SETTINGS.length, Object.keys(m0).length + "/" + L.SETTINGS.length);

// ── diff ────────────────────────────────────────────────────────────────────
const changedModel = Object.assign({}, m0, { gaps: "16", frDisabled: false, background: "#111111" });
const d = L.diff(changedModel, m0);
ok("diff length", d.length === 3, "n=" + d.length);
const dProps = d.map((r) => r.prop).sort().join(",");
ok("diff props", dProps === "background,frDisabled,gaps", dProps);
ok("diff carries descriptor", d.every((r) => r.def && r.def.prop === r.prop));
ok("diff carries value", d.find((r) => r.prop === "gaps").value === "16");
ok("diff of identical model is empty", L.diff(m0, m0).length === 0);
ok("diff without orig is empty", L.diff(m0, null).length === 0);

// ── edits ───────────────────────────────────────────────────────────────────
const S = {};
L.SETTINGS.forEach((row) => { S[row.prop] = row; });
function ed(prop, value) { return L.edits([{ prop: prop, def: S[prop], value: value }]); }
function line(prop, value) {
    const e = ed(prop, value);
    return e.childEdits.length ? e.childEdits[0].line : "(no child edit)";
}

ok("edits flag on", line("alwaysCenterSingle", true) === "always-center-single-column", String(line("alwaysCenterSingle", true)));
ok("edits flag off → null", line("alwaysCenterSingle", false) === null);
ok("edits bool true", line("shadowBehind", true) === "draw-behind-window true", String(line("shadowBehind", true)));
ok("edits bool false", line("shadowBehind", false) === "draw-behind-window false", String(line("shadowBehind", false)));
ok("edits float", line("gaps", "16") === "gaps 16", String(line("gaps", "16")));
ok("edits float trims", line("gaps", " 8 ") === "gaps 8", String(line("gaps", " 8 ")));
ok("edits float empty → null", line("gaps", "") === null);
ok("edits float NaN → null", line("gaps", "abc") === null);
ok("edits str", line("background", "#111") === 'background-color "#111"', String(line("background", "#111")));
ok("edits str empty → null", line("background", "") === null);
ok("edits enum keeps default without omitDefault", line("centerFocused", "never") === 'center-focused-column "never"', String(line("centerFocused", "never")));
ok("edits enum non-default", line("defaultColDisplay", "tabbed") === 'default-column-display "tabbed"', String(line("defaultColDisplay", "tabbed")));
ok("edits enum omitDefault → null", line("defaultColDisplay", "normal") === null, String(line("defaultColDisplay", "normal")));
ok("edits carries path", ed("frWidth", "3").childEdits[0].path[0] === "focus-ring");
ok("edits carries name", ed("frWidth", "3").childEdits[0].name === "width");
const presetEd = ed("presetCols", "0.5, 1280px");
ok("edits preset is not a child edit", presetEd.childEdits.length === 0);
ok("edits preset name", presetEd.presets.length === 1 && presetEd.presets[0].name === "preset-column-widths");
ok("edits preset value", presetEd.presets[0].value === "0.5, 1280px");
const batch = L.edits(L.diff(Object.assign({}, m0, { gaps: "16", presetCols: "0.5", tabGap: "4" }), m0));
ok("edits batches children", batch.childEdits.length === 2, "n=" + batch.childEdits.length);
ok("edits batches presets", batch.presets.length === 1, "n=" + batch.presets.length);

// ── apply (round-trip through parse) ────────────────────────────────────────
// three settings (a float change, a first-time insert into a missing block, a
// removal) + one preset insert.
const target = Object.assign({}, m0, {
    gaps: "16",
    tabPosition: "top",
    background: "",
    presetHeights: "0.5, 720px"
});
const out = L.apply(fixture, L.diff(target, m0), K);
const m1 = L.parse(layoutNode(out), K);
ok("apply float change", m1.gaps === "16", m1.gaps);
ok("apply insert into missing block", m1.tabPosition === "top", m1.tabPosition);
ok("apply removal", m1.background === "", m1.background);
ok("apply preset insert", m1.presetHeights === "0.5, 720px", m1.presetHeights);
ok("apply keeps comment", out.indexOf("// keep me — an unrelated comment") !== -1);
ok("apply keeps header comment", out.indexOf("// niri config") === 0);
ok("apply leaves other settings alone",
   m1.presetCols === "0.33, 1280px" && m1.alwaysCenterSingle === true && m1.frActive === "#7fc8ff" &&
   m1.shadowBehind === true && m1.strutL === "8",
   JSON.stringify({ p: m1.presetCols, a: m1.alwaysCenterSingle, f: m1.frActive, s: m1.strutL }));
ok("apply drops the removed line", out.indexOf("background-color") === -1);
ok("apply no-op with no changes", L.apply(fixture, [], K) === fixture);

// preset removal: clearing the string deletes the whole block
const cleared = L.apply(fixture, L.diff(Object.assign({}, m0, { presetCols: "" }), m0), K);
ok("apply preset clear removes block", L.parse(layoutNode(cleared), K).presetCols === "" &&
   cleared.indexOf("preset-column-widths") === -1);
// flag toggle off removes the bare node
const noRing = L.apply(fixture, L.diff(Object.assign({}, m0, { frDisabled: false }), m0), K);
ok("apply flag off removes node", L.parse(layoutNode(noRing), K).frDisabled === false &&
   L.parse(layoutNode(noRing), K).frWidth === "3");

console.log("\n" + (fail === 0 ? "✓ ALL PASS" : "✗ FAIL") + "  (" + pass + " pass, " + fail + " fail)");
process.exit(fail === 0 ? 0 : 1);
