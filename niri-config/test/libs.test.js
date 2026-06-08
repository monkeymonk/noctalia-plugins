// Logic tests for binds/keys/niri/desktop/outputs/xkb against real system data.
// Run: node niri-config/test/libs.test.js
const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");
const { loadLib } = require("./_load");

const K = loadLib("lib/kdl.js");
const B = loadLib("lib/binds.js");
const KEYS = loadLib("lib/keys.js");
const NIRI = loadLib("lib/niri.js");
const D = loadLib("lib/desktop.js");
const O = loadLib("lib/outputs.js");
const X = loadLib("lib/xkb.js");

let pass = 0, fail = 0;
function ok(name, cond, extra) { if (cond) pass++; else { fail++; console.log("  ✗ " + name + (extra ? "  " + extra : "")); } }
function sh(cmd) { try { return cp.execSync(cmd, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }); } catch (e) { return ""; } }

// ── binds ────────────────────────────────────────────────────────────────────
ok("normalizeCombo orders mods", B.normalizeCombo("Shift+Mod+q") === B.normalizeCombo("Mod+Shift+Q"));
ok("normalizeCombo ctrl alias", B.normalizeCombo("Control+A") === B.normalizeCombo("Ctrl+a"));
const sampleBind = { combo: "Mod+Shift+T", attrs: { "hotkey-overlay-title": "Open Terminal", repeat: false },
                     actions: [{ name: "spawn", args: ["ghostty"] }], disabled: false };
const line = B.serializeBind(sampleBind, { padTo: 36 });
ok("serializeBind shape", /^Mod\+Shift\+T\s+hotkey-overlay-title="Open Terminal" repeat=false \{ spawn "ghostty"; \}$/.test(line), line);
const reparsed = K.parse("binds {\n    " + line + "\n}");
const rb = B.parseBinds(K.findNode(reparsed, "binds"))[0];
ok("serializeBind round-trips combo", rb.combo === "Mod+Shift+T", rb.combo);
ok("serializeBind round-trips attr", rb.attrs["hotkey-overlay-title"] === "Open Terminal");
ok("serializeBind round-trips action", rb.actions[0].name === "spawn" && rb.actions[0].args[0] === "ghostty");
ok("serializeBind repeat=false", rb.attrs.repeat === false);

// real keybinds
const kbPath = path.join(os.homedir(), ".config", "niri", "cfg", "keybinds.kdl");
if (fs.existsSync(kbPath)) {
    const doc = K.parse(fs.readFileSync(kbPath, "utf8"));
    const binds = B.parseBinds(K.findNode(doc, "binds"));
    ok("real binds parsed", binds.length > 50, "n=" + binds.length);
    ok("conflict detected on existing combo", !!B.findConflict(binds, binds[5].combo));
    ok("no conflict for self", !B.findConflict(binds, binds[5].combo, binds[5].node));
    ok("describeBind nonempty", B.describeBind(binds.find(b => b.actions.length)) !== "");
    // every real bind re-serializes to something that re-parses to same combo
    let bad = 0;
    binds.forEach(b => {
        const ln = B.serializeBind(b, { padTo: 36 });
        const rp = B.parseBinds(K.findNode(K.parse("binds {\n" + ln + "\n}"), "binds"))[0];
        if (!rp || B.normalizeCombo(rp.combo) !== B.normalizeCombo(b.combo)) bad++;
    });
    ok("all real binds re-serialize cleanly", bad === 0, "bad=" + bad);
}

// ── keys ─────────────────────────────────────────────────────────────────────
ok("letter+meta+shift", KEYS.comboFromEvent(0x54, KEYS.QT_META | KEYS.QT_SHIFT, "T") === "Mod+Shift+T");
ok("named key Return", KEYS.comboFromEvent(0x01000004, KEYS.QT_META, "") === "Mod+Return");
ok("digit", KEYS.comboFromEvent(0x31, KEYS.QT_META, "1") === "Mod+1");
ok("bare modifier → null", KEYS.comboFromEvent(0x01000021, KEYS.QT_CTRL, "") === null);
ok("symbol via text", KEYS.keyToken(0x2f, "/") === "Slash");
ok("shifted digit → base", KEYS.comboFromEvent(0x21, KEYS.QT_META | KEYS.QT_SHIFT, "!") === "Mod+Shift+1");
ok("SPECIAL_KEYS present", KEYS.SPECIAL_KEYS.length > 10);

// ── niri (live) ──────────────────────────────────────────────────────────────
const outJson = sh("niri msg --json outputs");
if (outJson) {
    const outs = NIRI.parseOutputs(outJson);
    ok("parseOutputs nonempty", outs.length > 0, "n=" + outs.length);
    ok("output has name", outs[0].name && outs[0].name.length > 0);
    ok("output has modes", outs[0].modes.length > 0, "modes=" + outs[0].modes.length);
    ok("mode label format", /^\d+x\d+@\d+\.\d{3}$/.test(outs[0].modes[0].label), outs[0].modes[0].label);
    console.log("  · outputs: " + outs.map(o => o.name + " " + o.currentModeLabel + " @" + o.scale).join(", "));
} else { console.log("  · (niri msg outputs unavailable — skipped live output tests)"); }

const wsJson = sh("niri msg --json workspaces");
if (wsJson) { const ws = NIRI.parseWorkspaces(wsJson); ok("parseWorkspaces nonempty", ws.length > 0, "n=" + ws.length); }
const winJson = sh("niri msg --json windows");
if (winJson) { const wins = NIRI.parseWindows(winJson); ok("parseWindows ok", Array.isArray(wins)); console.log("  · windows open: " + wins.length); }

// saveCmd shape
const sc = NIRI.saveCmd("/tmp/x.kdl", "/tmp/config.kdl", "YmFzZTY0");
ok("saveCmd is sh -c", sc[0] === "sh" && sc[1] === "-c" && sc.length === 7 && sc[4] === "/tmp/x.kdl");

// ── desktop ──────────────────────────────────────────────────────────────────
ok("cleanExec strips field codes", D.cleanExec("firefox %u") === "firefox");
ok("commandToAction simple → spawn", JSON.stringify(D.commandToAction("ghostty")) === JSON.stringify({ name: "spawn", args: ["ghostty"] }));
const shAct = D.commandToAction("sh -c 'echo hi | cat'");
ok("commandToAction shell → spawn-sh", shAct.name === "spawn-sh");
ok("tokenize honors quotes", JSON.stringify(D.tokenize('ghostty -e "yazi launch"')).indexOf("yazi launch") !== -1);
// parse a real .desktop if any exist
const appDir = "/usr/share/applications";
if (fs.existsSync(appDir)) {
    const files = fs.readdirSync(appDir).filter(f => f.endsWith(".desktop")).slice(0, 200);
    let parsed = 0;
    files.forEach(f => { const e = D.parseDesktopEntry(fs.readFileSync(path.join(appDir, f), "utf8")); if (e) parsed++; });
    ok("parsed many .desktop entries", parsed > 5, "parsed=" + parsed + "/" + files.length);
    console.log("  · .desktop apps parsed: " + parsed + "/" + files.length);
}

// ── outputs ──────────────────────────────────────────────────────────────────
const onode = K.findNode(K.parse('output "eDP-1" {\n  mode "2256x1504@59.999"\n  scale 1.5\n  position x=0 y=0\n  variable-refresh-rate\n}'), "output");
const om = O.parseOutput(onode);
ok("parseOutput name", om.name === "eDP-1");
ok("parseOutput mode", om.mode === "2256x1504@59.999");
ok("parseOutput scale", om.scale === 1.5);
ok("parseOutput position", om.x === 0 && om.y === 0);
ok("parseOutput vrr", om.vrr === true);
const ser = O.serializeOutput(om);
ok("serializeOutput round-trips", O.parseOutput(K.findNode(K.parse(ser), "output")).mode === "2256x1504@59.999", ser);
ok("parseMode", O.parseMode("1920x1080@60.000").width === 1920);

// ── xkb ──────────────────────────────────────────────────────────────────────
const evdev = "/usr/share/X11/xkb/rules/evdev.lst";
if (fs.existsSync(evdev)) {
    const parsed = X.parseEvdevList(fs.readFileSync(evdev, "utf8"));
    ok("xkb layouts parsed", parsed.layouts.length > 20, "n=" + parsed.layouts.length);
    ok("xkb has us layout", parsed.layouts.some(l => l.code === "us"));
    ok("xkb variants parsed", parsed.variants.length > 10, "n=" + parsed.variants.length);
    console.log("  · xkb: " + parsed.layouts.length + " layouts, " + parsed.variants.length + " variants, " + parsed.options.length + " options");
} else {
    const fb = X.parseEvdevList("");
    ok("xkb fallback layouts", fb.layouts.length > 0);
}

console.log("\n" + (fail === 0 ? "✓ ALL PASS" : "✗ FAIL") + "  (" + pass + " pass, " + fail + " fail)");
process.exit(fail === 0 ? 0 : 1);
