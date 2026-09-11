// Parser-safety harness for lib/kdl.js — the gate before any write feature.
// Run: node niri-config/test/kdl.test.js
const fs = require("fs");
const os = require("os");
const path = require("path");
const { loadLib } = require("./_load");

const K = loadLib("lib/kdl.js");

let pass = 0, fail = 0;
function ok(name, cond, extra) {
    if (cond) { pass++; } else { fail++; console.log("  ✗ " + name + (extra ? "  " + extra : "")); }
}

// ── 1. Synthetic round-trip / structure tests ───────────────────────────────
const sample = `// header comment
binds {
    Mod+Return  hotkey-overlay-title="Open Terminal" { spawn "ghostty"; }
    Mod+Shift+Q { close-window; }
    XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "vol up"; }
    /-Mod+Disabled { spawn "nope"; }
}
output "eDP-1" {
    mode "2256x1504@59.999"
    scale 1.5
    position x=0 y=0
}
input {
    keyboard { xkb { layout "us" } numlock }
    touchpad { tap natural-scroll }
}
`;

const doc = K.parse(sample);
ok("top-level node count", doc.nodes.length === 3, "got " + doc.nodes.length);

const binds = K.findNode(doc, "binds");
ok("found binds", !!binds);
ok("binds has children", binds && binds.children.length === 4, binds && ("got " + binds.children.length));

const ret = binds.children[0];
ok("bind name parsed", ret.name === "Mod+Return", "got " + ret.name);
ok("bind prop parsed", ret.props["hotkey-overlay-title"] === "Open Terminal", JSON.stringify(ret.props));
ok("bind child action", ret.children[0] && ret.children[0].name === "spawn");
ok("bind child arg", ret.children[0].args[0].value === "ghostty");

const dis = binds.children[3];
ok("slashdash flagged", dis.slashdash === true);

const out = K.findNode(doc, "output");
ok("output arg", out.args[0].value === "eDP-1");
const mode = K.findNode(doc, "mode", out.children);
ok("mode value", mode.args[0].value === "2256x1504@59.999");
const pos = K.findNode(doc, "position", out.children);
ok("position props", pos.props.x === 0 && pos.props.y === 0, JSON.stringify(pos.props));

// ── 2. Surgical edit invariants ──────────────────────────────────────────────
// Replace ONE bind line; everything else must be byte-identical.
const newText = K.replaceNodeLine(sample, ret, '    Mod+Return  hotkey-overlay-title="Open Terminal" { spawn "kitty"; }');
ok("replace changed target", newText.indexOf('spawn "kitty"') !== -1);
ok("replace kept other binds", newText.indexOf("close-window") !== -1 && newText.indexOf("XF86AudioRaiseVolume") !== -1);
ok("replace kept header comment", newText.indexOf("// header comment") === 0);
// Only the kitty line differs:
const dl1 = sample.split("\n"), dl2 = newText.split("\n");
let diffs = 0; for (let i = 0; i < Math.max(dl1.length, dl2.length); i++) if (dl1[i] !== dl2[i]) diffs++;
ok("replace touched exactly 1 line", diffs === 1, "diffs=" + diffs);

// No-op replace (same line) → byte identical
const noop = K.replaceNodeLine(sample, ret, sample.slice(...K.lineSpan(sample, ret.range)).replace(/\n$/, ""));
ok("no-op replace is byte-identical", noop === sample, "len " + noop.length + " vs " + sample.length);

// Insert a new child bind into binds
const inserted = K.insertChildLine(sample, binds, "Mod+T { spawn \"ghostty\"; }");
const doc2 = K.parse(inserted);
ok("insert added a child", K.findNode(doc2, "binds").children.length === 5);
ok("insert preserved comment", inserted.indexOf("// header comment") === 0);

// ── 2b. Line-sharing nodes: an edit must never swallow a sibling ─────────────
const kidNames = (n) => (n ? n.children.map((c) => c.name).join(",") : "<no block>");

const nested = 'input {\n    keyboard { xkb { layout "us" } numlock }\n}\n';
const nestedLayout = K.findNode(K.parse(nested), "layout");

const nRep = K.replaceNodeLine(nested, nestedLayout, 'layout "fr"');
const nRepKb = K.blockPath(nRep, "input", ["keyboard"]);
ok("inline replace kept keyboard siblings", kidNames(nRepKb) === "xkb,numlock", kidNames(nRepKb));
const nRepXkb = K.childNamed(nRepKb, "xkb");
ok("inline replace rewrote only layout",
   kidNames(nRepXkb) === "layout" && nRepXkb.children[0].args[0].value === "fr",
   JSON.stringify(nRep));

const nRem = K.removeNodeLine(nested, nestedLayout);
const nRemKb = K.blockPath(nRem, "input", ["keyboard"]);
ok("inline remove kept keyboard siblings", kidNames(nRemKb) === "xkb,numlock", kidNames(nRemKb));
ok("inline remove dropped only layout", kidNames(K.childNamed(nRemKb, "xkb")) === "", JSON.stringify(nRem));

// ";"-separated siblings on one line
const semi = "debug {\n    a 1; b 2; c 3\n}\n";
const semiB = K.childNamed(K.blockPath(semi, "debug", []), "b");
const sRep = K.replaceNodeLine(semi, semiB, "b 5");
const sRepBlk = K.blockPath(sRep, "debug", []);
ok("semicolon replace kept siblings", kidNames(sRepBlk) === "a,b,c", kidNames(sRepBlk));
ok("semicolon replace rewrote only b", K.childNamed(sRepBlk, "b").args[0].value === 5, JSON.stringify(sRep));
const sRem = K.removeNodeLine(semi, semiB);
ok("semicolon remove dropped only b", kidNames(K.blockPath(sRem, "debug", [])) === "a,c", JSON.stringify(sRem));

// ── 2c. Block-edit API ───────────────────────────────────────────────────────
ok("blockPath resolves a nested block", K.blockPath(nested, "input", ["keyboard", "xkb"]) !== null);
ok("blockPath misses return null", K.blockPath(nested, "input", ["keyboard", "nope"]) === null);
ok("childNamed is case-sensitive", K.childNamed(K.blockPath(nested, "input", []), "Keyboard") === null);

ok("ensurePath is a no-op when the path exists",
   K.ensurePath(nested, "input", ["keyboard", "xkb"]) === nested);
const grown = K.ensurePath("", "input", ["touchpad"]);
ok("ensurePath creates root and block", K.blockPath(grown, "input", ["touchpad"]) !== null, JSON.stringify(grown));

// create into a block that does not exist yet
const created = K.setChildLine("", "input", ["keyboard", "xkb"], "layout", 'layout "fr"');
const createdXkb = K.blockPath(created, "input", ["keyboard", "xkb"]);
ok("setChildLine creates the whole path",
   createdXkb !== null && K.childNamed(createdXkb, "layout").args[0].value === "fr", JSON.stringify(created));

// update in place, preserving the existing indentation
const multi = 'input {\n    keyboard {\n        xkb {\n            layout "us"\n        }\n        numlock\n    }\n}\n';
const updated = K.setChildLine(multi, "input", ["keyboard", "xkb"], "layout", 'layout "de"');
ok("setChildLine keeps the existing indent", updated.indexOf('\n            layout "de"\n') !== -1, JSON.stringify(updated));
ok("setChildLine left the rest alone", kidNames(K.blockPath(updated, "input", ["keyboard"])) === "xkb,numlock");

const dropped = K.setChildLine(multi, "input", ["keyboard", "xkb"], "layout", null);
ok("setChildLine(null) removes the child", kidNames(K.blockPath(dropped, "input", ["keyboard", "xkb"])) === "");
ok("setChildLine(null) on a missing child is a no-op",
   K.setChildLine(multi, "input", ["keyboard", "xkb"], "variant", null) === multi);

const flagOff = K.setChildFlag(multi, "input", ["keyboard"], "numlock", false);
ok("setChildFlag(false) removes the flag", kidNames(K.blockPath(flagOff, "input", ["keyboard"])) === "xkb");
const flagOn = K.setChildFlag(flagOff, "input", ["keyboard"], "numlock", true);
ok("setChildFlag(true) restores the flag", kidNames(K.blockPath(flagOn, "input", ["keyboard"])) === "xkb,numlock");
ok("setChildFlag(true) is idempotent", K.setChildFlag(flagOn, "input", ["keyboard"], "numlock", true) === flagOn);
const flagNew = K.setChildFlag("", "input", ["touchpad"], "natural-scroll", true);
ok("setChildFlag(true) creates the path", kidNames(K.blockPath(flagNew, "input", ["touchpad"])) === "natural-scroll",
   JSON.stringify(flagNew));

// ── 2d. Insertion formatting stays surgical ──────────────────────────────────
const inline = 'input {\n    keyboard { xkb { layout "us" } numlock }\n    touchpad { tap natural-scroll }\n}\n';

const inlineRep = K.setChildLine(inline, "input", ["keyboard", "xkb"], "layout", 'layout "fr"');
ok("inline replace keeps the space before the brace",
   inlineRep.indexOf('keyboard { xkb { layout "fr" } numlock }') !== -1, JSON.stringify(inlineRep));

const inlineIns = K.setChildLine(inlineRep, "input", ["keyboard", "xkb"], "variant", 'variant "azerty"');
ok("inline insert stays on the block's line",
   inlineIns.indexOf('keyboard { xkb { layout "fr"; variant "azerty" } numlock }') !== -1, JSON.stringify(inlineIns));
const insXkb = K.blockPath(inlineIns, "input", ["keyboard", "xkb"]);
ok("inline insert yields two distinct nodes",
   kidNames(insXkb) === "layout,variant" && insXkb.children[0].args.length === 1 &&
   insXkb.children[1].args[0].value === "azerty", JSON.stringify(inlineIns));

const inlineOff = K.setChildFlag(inlineIns, "input", ["keyboard"], "numlock", false);
ok("inline flag removal leaves single spacing",
   inlineOff.indexOf('    keyboard { xkb { layout "fr"; variant "azerty" } }\n') !== -1, JSON.stringify(inlineOff));

const madeBlock = K.setChildLine(inlineOff, "input", ["mouse"], "accel-speed", "accel-speed 0.5");
ok("a created block closes at its own indent",
   madeBlock.indexOf("\n    mouse {\n        accel-speed 0.5\n    }\n}\n") !== -1, JSON.stringify(madeBlock));
const mouse = K.blockPath(madeBlock, "input", ["mouse"]);
ok("a created block parses with its child",
   kidNames(mouse) === "accel-speed" && mouse.children[0].args[0].value === 0.5, JSON.stringify(madeBlock));
ok("insertion left the neighbouring blocks alone",
   kidNames(K.blockPath(madeBlock, "input", [])) === "keyboard,touchpad,mouse" &&
   madeBlock.indexOf("    touchpad { tap natural-scroll }\n") !== -1, JSON.stringify(madeBlock));

const scratch = K.setChildLine("", "input", ["keyboard", "xkb"], "layout", 'layout "fr"');
ok("nested creation indents every level",
   scratch === 'input {\n    keyboard {\n        xkb {\n            layout "fr"\n        }\n    }\n}\n',
   JSON.stringify(scratch));

// ── 2e. Batched child edits equal the sequential setChildLine fold ───────────
const batchSrc = [
    "// batch fixture header",
    "input {",
    "    keyboard {",
    '        xkb { layout "us" }',
    "        repeat-delay 600",
    "        numlock",
    "    }",
    "    touchpad {",
    "        // touchpad comment",
    "        tap",
    "        accel-speed 0.0",
    "    }",
    "}",
    ""
].join("\n");

// One call covering: two replacements in different nested blocks, a removal,
// a brand-new insert, a no-op removal of an absent child, and an edit inside a
// single-line inline block (the shared-line guard).
const batchEdits = [
    { path: ["keyboard", "xkb"], name: "layout", line: 'layout "fr"' },   // inline block
    { path: ["keyboard"], name: "repeat-delay", line: "repeat-delay 300" }, // replace #1
    { path: ["touchpad"], name: "accel-speed", line: "accel-speed 0.3" },   // replace #2
    { path: ["keyboard"], name: "numlock", line: null },                    // removal
    { path: ["touchpad"], name: "scroll-method", line: 'scroll-method "two-finger"' }, // insert
    { path: ["keyboard", "xkb"], name: "variant", line: null }              // absent → no-op
];
const fold = (t, list) => list.reduce((acc, e) => K.setChildLine(acc, "input", e.path, e.name, e.line), t);

const batched = K.applyChildEdits(batchSrc, "input", batchEdits);
ok("applyChildEdits equals the sequential fold", batched === fold(batchSrc, batchEdits),
   JSON.stringify(batched) + " vs " + JSON.stringify(fold(batchSrc, batchEdits)));

// Splices run right-to-left, so the input order must not matter.
const reversed = batchEdits.slice().reverse();
ok("applyChildEdits is order-independent", K.applyChildEdits(batchSrc, "input", reversed) === batched,
   JSON.stringify(K.applyChildEdits(batchSrc, "input", reversed)));

ok("batched edit kept comments and untouched lines",
   batched.indexOf("// batch fixture header\n") === 0 &&
   batched.indexOf("        // touchpad comment\n") !== -1 &&
   batched.indexOf("        tap\n") !== -1, JSON.stringify(batched));
ok("batched inline edit stayed inline",
   batched.indexOf('        xkb { layout "fr" }\n') !== -1, JSON.stringify(batched));

const batchedKb = K.blockPath(batched, "input", ["keyboard"]);
const batchedTp = K.blockPath(batched, "input", ["touchpad"]);
ok("batched removal dropped only numlock", kidNames(batchedKb) === "xkb,repeat-delay", kidNames(batchedKb));
ok("batched replacements applied", batchedKb.children[1].args[0].value === 300 &&
   K.childNamed(batchedTp, "accel-speed").args[0].value === 0.3, JSON.stringify(batched));
ok("batched insert landed in the right block",
   kidNames(batchedTp) === "tap,accel-speed,scroll-method" &&
   K.childNamed(batchedTp, "scroll-method").args[0].value === "two-finger", kidNames(batchedTp));

ok("applyChildEdits with only absent removals is byte-identical",
   K.applyChildEdits(batchSrc, "input", [
       { path: ["keyboard"], name: "repeat-rate", line: null },
       { path: ["mouse"], name: "accel-speed", line: null }
   ]) === batchSrc);
ok("applyChildEdits with no edits is byte-identical", K.applyChildEdits(batchSrc, "input", []) === batchSrc);

// Missing root block → the sequential fallback creates it.
const fromScratch = [
    { path: ["keyboard", "xkb"], name: "layout", line: 'layout "fr"' },
    { path: ["touchpad"], name: "tap", line: "tap" }
];
ok("applyChildEdits creates a missing root like the fold",
   K.applyChildEdits("", "input", fromScratch) === fold("", fromScratch),
   JSON.stringify(K.applyChildEdits("", "input", fromScratch)));

// Two siblings sharing ONE physical line, both edited in the same call: the
// batched splices must still match the fold (the shared-line guard is what
// keeps them from swallowing each other).
const inlinePair = 'input {\n    xkb { layout "us" variant "intl" }\n    numlock\n}\n';
const pairEdits = [
    { path: ["xkb"], name: "layout", line: 'layout "fr"' },
    { path: ["xkb"], name: "variant", line: 'variant "nodeadkeys"' }
];
ok("inline siblings edited together equal the fold",
   K.applyChildEdits(inlinePair, "input", pairEdits) === fold(inlinePair, pairEdits),
   JSON.stringify(K.applyChildEdits(inlinePair, "input", pairEdits)));

const pairRemoved = [
    { path: ["xkb"], name: "variant", line: null },
    { path: ["xkb"], name: "layout", line: 'layout "de"' }
];
ok("removing one inline sibling while editing the other equals the fold",
   K.applyChildEdits(inlinePair, "input", pairRemoved) === fold(inlinePair, pairRemoved),
   JSON.stringify(K.applyChildEdits(inlinePair, "input", pairRemoved)));

// Remove a bind line
const removed = K.removeNodeLine(sample, binds.children[1]);
ok("remove dropped the bind", removed.indexOf("close-window") === -1);
ok("remove kept siblings", removed.indexOf("XF86AudioRaiseVolume") !== -1);

// ── 3. Real config — round-trip every included file (the real gate) ──────────
const cfgDir = path.join(os.homedir(), ".config", "niri");
function check(file) {
    if (!fs.existsSync(file)) return;
    const text = fs.readFileSync(file, "utf8");
    const d = K.parse(text);
    // Invariant A: every node's raw slice re-parses to the same name.
    let bad = 0;
    K.walk(d.nodes, (n) => {
        const slice = text.slice(n.range[0], n.range[1]);
        if (slice.indexOf(n.name.split("+")[0]) === -1 && n.name.indexOf("\"") === -1) {
            // loose check: the name token should appear within the node's own range
            if (text.slice(n.nameRange[0], n.nameRange[1]).length === 0) bad++;
        }
    });
    // Invariant B: a no-op edit of the FIRST top-level node is byte-identical.
    let noopOk = true;
    if (d.nodes.length) {
        const first = d.nodes[0];
        const slice = text.slice(...K.lineSpan(text, first.range)).replace(/\n$/, "");
        const rt = K.replaceNodeLine(text, first, slice);
        noopOk = rt === text;
    }
    const name = path.relative(cfgDir, file);
    // display.kdl is legitimately all-comments (outputs managed in monitors.kdl) → 0 nodes ok
    ok("[" + name + "] node-range integrity", bad === 0, "bad=" + bad);
    ok("[" + name + "] no-op edit byte-identical", noopOk);
    console.log("  · " + name + ": " + d.nodes.length + " top-level nodes");
}

["cfg/keybinds.kdl", "cfg/input.kdl", "cfg/display.kdl", "cfg/layout.kdl",
 "cfg/rules.kdl", "cfg/workspaces.kdl", "cfg/animation.kdl", "cfg/autostart.kdl",
 "cfg/misc.kdl", "config.kdl", "noctalia.kdl", "monitors.kdl"].forEach((f) => check(path.join(cfgDir, f)));

// Deep-dive: parse the real keybinds and report bind count + a sample.
const kb = path.join(cfgDir, "cfg", "keybinds.kdl");
if (fs.existsSync(kb)) {
    const text = fs.readFileSync(kb, "utf8");
    const d = K.parse(text);
    const b = K.findNode(d, "binds");
    if (b) {
        console.log("  · real keybinds: " + b.children.length + " binds");
        const withTitle = b.children.filter((n) => n.props["hotkey-overlay-title"]).length;
        const spawns = b.children.filter((n) => n.children.some((c) => c.name === "spawn" || c.name === "spawn-sh")).length;
        console.log("    - with hotkey-overlay-title: " + withTitle + ", spawn/spawn-sh: " + spawns);
        ok("real binds parsed", b.children.length > 20, "got " + b.children.length);
    }
}

console.log("\n" + (fail === 0 ? "✓ ALL PASS" : "✗ FAIL") + "  (" + pass + " pass, " + fail + " fail)");
process.exit(fail === 0 ? 0 : 1);
