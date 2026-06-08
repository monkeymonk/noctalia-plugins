// Write-path + safety-gate verification — runs ENTIRELY in a /tmp sandbox copy.
// NEVER touches ~/.config/niri. Proves: surgical insert, base64 save pipeline,
// niri validate gate, .bak creation, and auto-restore on an invalid edit.
// Run: node niri-config/test/save.sandbox.test.js
const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");
const { loadLib } = require("./_load");

const K = loadLib("lib/kdl.js");
const B = loadLib("lib/binds.js");
const NIRI = loadLib("lib/niri.js");

let pass = 0, fail = 0;
function ok(name, cond, extra) { if (cond) pass++; else { fail++; console.log("  ✗ " + name + (extra ? "  " + extra : "")); } }

const srcDir = path.join(os.homedir(), ".config", "niri");
const sandbox = path.join(os.tmpdir(), "niri-config-sandbox");

function run(argv) {
    const r = cp.spawnSync(argv[0], argv.slice(1), { encoding: "utf8" });
    return { code: r.status, out: (r.stdout || "").trim(), err: (r.stderr || "").trim() };
}

// ── set up sandbox ───────────────────────────────────────────────────────────
cp.spawnSync("rm", ["-rf", sandbox]);
const cpr = cp.spawnSync("cp", ["-r", srcDir, sandbox]);
if (cpr.status !== 0) { console.log("could not copy config to sandbox; skipping"); process.exit(0); }

const mainCfg = path.join(sandbox, "config.kdl");
const kbFile = path.join(sandbox, "cfg", "keybinds.kdl");
const original = fs.readFileSync(kbFile, "utf8");

// sanity: niri validate works on the untouched sandbox copy
const baseVal = run(NIRI.validateCmd(mainCfg));
ok("sandbox base config validates", baseVal.code === 0, baseVal.err);

// ── 1. valid surgical insert via the real save pipeline ──────────────────────
const doc = K.parse(original);
const binds = K.findNode(doc, "binds");
const newBind = { combo: "Mod+Shift+T", attrs: { "hotkey-overlay-title": "niri-config test" },
                  actions: [{ name: "spawn", args: ["ghostty"] }], disabled: false };
const newText = K.insertChildLine(original, binds, B.serializeBind(newBind, { padTo: 36 }));
const b64 = Buffer.from(newText, "utf8").toString("base64");

const save = run(NIRI.saveCmd(kbFile, mainCfg, b64));
ok("save pipeline returns OK", save.out.indexOf("OK") !== -1, "out=" + save.out + " err=" + save.err);
ok(".bak created", fs.existsSync(kbFile + ".bak"));
ok(".bak equals original", fs.readFileSync(kbFile + ".bak", "utf8") === original);

const afterValid = fs.readFileSync(kbFile, "utf8");
ok("new bind present", afterValid.indexOf('"niri-config test"') !== -1);
ok("config still valid after save", run(NIRI.validateCmd(mainCfg)).code === 0);
// only ONE region changed: removing the new line restores original
const reDoc = K.parse(afterValid);
const reBind = K.findNode(reDoc, "binds").children.find(b => b.props && b.props["hotkey-overlay-title"] === "niri-config test");
ok("inserted bind re-parses", !!reBind);
const restored = K.removeNodeLine(afterValid, reBind);
ok("surgical insert touched nothing else", restored === original, "diff len " + restored.length + " vs " + original.length);

// ── 2. invalid edit must auto-restore from .bak ──────────────────────────────
const broken = afterValid + "\nthis is { not valid kdl for niri binds at top level\n";
const b64bad = Buffer.from(broken, "utf8").toString("base64");
const badSave = run(NIRI.saveCmd(kbFile, mainCfg, b64bad));
ok("invalid save reports ERR", badSave.out.indexOf("ERR") !== -1, "out=" + badSave.out);
ok("invalid save surfaces validate error", badSave.err.length > 0);
ok("file auto-restored after invalid edit", fs.readFileSync(kbFile, "utf8") === afterValid);
ok("config valid after auto-restore", run(NIRI.validateCmd(mainCfg)).code === 0);

// ── 3. edit / toggle / delete on a real existing bind (indentation preserved) ─
const cur = fs.readFileSync(kbFile, "utf8");
const d2 = K.parse(cur);
const liveBinds = B.parseBinds(K.findNode(d2, "binds"));
const target = liveBinds.find(b => b.combo === "Mod+Return") || liveBinds[0];
const indent = K.leadingIndent(cur, target.node.range);
ok("real binds use 4-space indent", indent === "    ", JSON.stringify(indent));

// edit: rebuild the same bind via serializer + preserved indent → must still validate
const edited = { combo: target.combo, attrs: target.attrs,
                 actions: [{ name: "spawn", args: ["ghostty", "--title", "edited"] }], disabled: false };
const editLine = indent + B.serializeBind(edited, { padTo: 36 });
const editText = K.replaceNodeLine(cur, target.node, editLine);
const r1 = run(NIRI.saveCmd(kbFile, mainCfg, Buffer.from(editText, "utf8").toString("base64")));
ok("edit saves & validates", r1.out.indexOf("OK") !== -1, r1.out + " " + r1.err);
ok("edit preserved indent", fs.readFileSync(kbFile, "utf8").split("\n").some(l => l.startsWith("    " + target.combo)));

// toggle disable (slashdash) then re-enable, validating each time
let t = fs.readFileSync(kbFile, "utf8");
let tn = B.parseBinds(K.findNode(K.parse(t), "binds")).find(b => b.combo === target.combo);
const disabledText = K.setDisabled(t, tn.node, true);
const r2 = run(NIRI.saveCmd(kbFile, mainCfg, Buffer.from(disabledText, "utf8").toString("base64")));
ok("disable (slashdash) validates", r2.out.indexOf("OK") !== -1, r2.out + " " + r2.err);
ok("bind now slashdashed", /\/-\s*Mod\+Return/.test(fs.readFileSync(kbFile, "utf8")));

t = fs.readFileSync(kbFile, "utf8");
tn = B.parseBinds(K.findNode(K.parse(t), "binds")).find(b => b.combo === target.combo);
ok("disabled bind detected", tn && tn.disabled === true);
const enabledText = K.setDisabled(t, tn.node, false);
const r3 = run(NIRI.saveCmd(kbFile, mainCfg, Buffer.from(enabledText, "utf8").toString("base64")));
ok("re-enable validates", r3.out.indexOf("OK") !== -1, r3.out + " " + r3.err);

// delete the bind
t = fs.readFileSync(kbFile, "utf8");
tn = B.parseBinds(K.findNode(K.parse(t), "binds")).find(b => b.combo === target.combo);
const delText = K.removeNodeLine(t, tn.node);
const r4 = run(NIRI.saveCmd(kbFile, mainCfg, Buffer.from(delText, "utf8").toString("base64")));
ok("delete validates", r4.out.indexOf("OK") !== -1, r4.out + " " + r4.err);
ok("bind removed", !B.parseBinds(K.findNode(K.parse(fs.readFileSync(kbFile, "utf8")), "binds")).some(b => b.combo === target.combo && b.actions.some(a => a.args.indexOf("edited") !== -1)));

// ── cleanup ──────────────────────────────────────────────────────────────────
cp.spawnSync("rm", ["-rf", sandbox]);

console.log("\n" + (fail === 0 ? "✓ ALL PASS (sandbox only — your real config untouched)" : "✗ FAIL") + "  (" + pass + " pass, " + fail + " fail)");
process.exit(fail === 0 ? 0 : 1);
