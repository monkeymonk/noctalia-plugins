// Logic tests for lib/input.js (the `input {}` settings table: parse / diff /
// edits / apply). Run: node niri-config/test/input.test.js
const { loadLib } = require("./_load");

const K = loadLib("lib/kdl.js");
const I = loadLib("lib/input.js");

let pass = 0, fail = 0;
function ok(name, cond, extra) { if (cond) pass++; else { fail++; console.log("  ✗ " + name + (extra ? "  " + extra : "")); } }

function inputNode(text) { return K.findNode(K.parse(text), "input"); }
function modelOf(text) { return I.parse(inputNode(text), K); }
function defOf(prop) { return I.SETTINGS.filter(d => d.prop === prop)[0]; }

const BASE = [
    "// niri config",
    "input {",
    "    keyboard {",
    "        // keep this comment",
    "        xkb {",
    '            layout "us,de"',
    '            options "grp:alt_shift_toggle,ctrl:nocaps"',
    "        }",
    "        numlock",
    "        repeat-delay 400",
    "    }",
    "    touchpad {",
    "        tap",
    "        drag",
    "        accel-speed 0.3",
    "    }",
    "    focus-follows-mouse",
    "}",
    "",
    'output "eDP-1" {',
    "    scale 1.5",
    "}",
    ""
].join("\n");

// ── SETTINGS table ───────────────────────────────────────────────────────────
ok("SETTINGS rows have prop/path/name/kind", I.SETTINGS.every(
    d => typeof d.prop === "string" && Array.isArray(d.path) && typeof d.name === "string" &&
         ["flag", "bool", "str", "int", "float"].indexOf(d.kind) !== -1));
{
    const seen = {};
    let dupes = 0;
    I.SETTINGS.forEach(d => { const k = d.path.join("/") + "|" + d.name; if (seen[k]) dupes++; seen[k] = 1; });
    ok("SETTINGS has no duplicate (path,name)", dupes === 0, "dupes=" + dupes);
}

// ── parse ────────────────────────────────────────────────────────────────────
const m = modelOf(BASE);
ok("parse flag present → true", m.numlock === true);
ok("parse flag absent → false", m.tpDwt === false && m.msOff === false);
ok("parse top-level flag", m.focusFollowsMouse === true);
ok("parse bare bool node → true", m.tpDrag === true);
ok("parse int → string", m.repeatDelay === "400", JSON.stringify(m.repeatDelay));
ok("parse int absent → empty", m.repeatRate === "");
ok("parse float → string", m.tpAccel === "0.3", JSON.stringify(m.tpAccel));
ok("parse str keeps comma list", m.layout === "us,de", m.layout);
ok("parse nested str", m.options === "grp:alt_shift_toggle,ctrl:nocaps");
ok("parse str absent → empty", m.variant === "" && m.model === "" && m.modKey === "");
ok("parse ignores other blocks", m.msAccel === "" && m.trackLayout === "");
ok("parse explicit bool false", modelOf("input { touchpad { drag false } }").tpDrag === false);
ok("parse explicit bool true", modelOf("input { touchpad { drag true } }").tpDrag === true);
ok("parse missing block → all defaults", modelOf("input {\n}").numlock === false);

// ── diff ─────────────────────────────────────────────────────────────────────
{
    const next = Object.assign({}, m, { layout: "us", numlock: false, repeatRate: "25" });
    const changed = I.diff(next, m);
    ok("diff returns only changed rows", changed.length === 3, "n=" + changed.length);
    const byProp = {};
    changed.forEach(c => byProp[c.prop] = c);
    ok("diff carries path/name/kind/value", byProp.layout &&
        byProp.layout.name === "layout" && byProp.layout.kind === "str" &&
        byProp.layout.path.join("/") === "keyboard/xkb" && byProp.layout.value === "us");
    ok("diff sees flag flip", byProp.numlock && byProp.numlock.value === false);
    ok("diff sees new int", byProp.repeatRate && byProp.repeatRate.value === "25");
    ok("diff of identical models is empty", I.diff(m, m).length === 0);
    ok("diff without orig is empty", I.diff(m, null).length === 0);
}

// ── edits (serialization per kind) ───────────────────────────────────────────
function lineOf(prop, value) {
    const e = I.edits([Object.assign({}, defOf(prop), { value: value })]);
    return e[0].line;
}
ok("edits flag on → bare name", lineOf("numlock", true) === "numlock");
ok("edits flag off → null", lineOf("numlock", false) === null);
ok("edits bool true", lineOf("tpDrag", true) === "drag true");
ok("edits bool false", lineOf("tpDrag", false) === "drag false");
ok("edits int", lineOf("repeatDelay", "600") === "repeat-delay 600");
ok("edits int uses parseInt prefix", lineOf("repeatDelay", "600px") === "repeat-delay 600");
ok("edits int empty → null", lineOf("repeatDelay", "") === null);
ok("edits int NaN → null", lineOf("repeatDelay", "abc") === null);
ok("edits float", lineOf("tpAccel", "-0.5") === "accel-speed -0.5");
ok("edits float empty → null", lineOf("tpAccel", "") === null);
ok("edits float NaN → null", lineOf("tpAccel", "fast") === null);
ok("edits str quotes", lineOf("layout", "us,de") === 'layout "us,de"');
ok("edits str empty → null", lineOf("layout", "") === null);
{
    const e = I.edits([Object.assign({}, defOf("layout"), { value: "fr" })]);
    ok("edits keeps path + name", e[0].path.join("/") === "keyboard/xkb" && e[0].name === "layout");
    ok("edits of nothing is empty", I.edits([]).length === 0 && I.edits(null).length === 0);
}

// ── apply (batched, surgical) ────────────────────────────────────────────────
ok("apply with no changes is identity", I.apply(BASE, [], K) === BASE);
ok("apply with an unchanged model is identity", I.apply(BASE, I.diff(m, m), K) === BASE);

{
    const next = Object.assign({}, m, {
        layout: "us,de,fr",     // str changed in place
        options: "",            // str removed
        numlock: false,         // flag removed
        repeatRate: "25",       // int added
        tpDrag: false,          // bool flipped
        tpAccel: "",            // float removed
        modKey: "Super",        // str added at top level
        msNatural: true         // flag added in a missing block
    });
    const out = I.apply(BASE, I.diff(next, m), K);
    const back = modelOf(out);

    ok("apply → layout updated", back.layout === "us,de,fr", back.layout);
    ok("apply → options removed", back.options === "", JSON.stringify(back.options));
    ok("apply → flag removed", back.numlock === false);
    ok("apply → int added", back.repeatRate === "25", JSON.stringify(back.repeatRate));
    ok("apply → bool flipped", back.tpDrag === false);
    ok("apply → float removed", back.tpAccel === "");
    ok("apply → top-level str added", back.modKey === "Super", back.modKey);
    ok("apply → flag added in created block", back.msNatural === true);
    ok("apply → untouched settings survive", back.tpTap === true && back.repeatDelay === "400" &&
        back.focusFollowsMouse === true);
    ok("apply preserves comments", out.indexOf("// keep this comment") !== -1 &&
        out.indexOf("// niri config") !== -1);
    ok("apply leaves other blocks alone", out.indexOf('output "eDP-1" {\n    scale 1.5\n}') !== -1);
    ok("apply round-trips to the intended model",
        I.diff(back, next).length === 0, JSON.stringify(I.diff(back, next)));
}

// a keyboard the user never touched must come out byte-identical
{
    const next = Object.assign({}, m, { tpTap: false });
    const out = I.apply(BASE, I.diff(next, m), K);
    ok("untouched keyboard block is byte-identical",
        out.indexOf('layout "us,de"') !== -1 &&
        out.indexOf('options "grp:alt_shift_toggle,ctrl:nocaps"') !== -1);
    ok("only the touched line changed",
        out.split("\n").length === BASE.split("\n").length - 1 && out.indexOf("        tap\n") === -1);
}

console.log((fail ? "✗ " : "✓ ") + "input.js: " + pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
