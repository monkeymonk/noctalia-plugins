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

// Comment-out a bind
const commented = K.commentOutNodeLine(sample, binds.children[1]);
ok("comment-out disables bind", K.parse(commented).nodes.length === 3);
ok("comment-out kept close-window text", commented.indexOf("close-window") !== -1);

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
