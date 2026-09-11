import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/kdl.js" as Kdl
import qs.Commons
import qs.Widgets

// Miscellaneous editor: prefer-no-csd, screenshot-path, cursor, hotkey-overlay,
// clipboard, overview. The environment block (and anything else) is left to the
// "Edit file" button. Surgical batched save over the owning file's top-level
// nodes / blocks.
ColumnLayout {
    id: root

    required property var panel
    required property var configModel

    property string miscFile: ""
    property string sectionFile: miscFile
    property var orig: ({})

    property bool preferNoCsd: false
    property string screenshotPath: ""
    property string cursorTheme: ""
    property string cursorSize: ""
    property bool cursorHideTyping: false
    property string cursorHideMs: ""
    property bool hkSkipStartup: false
    property bool hkHideNotBound: false
    property bool clipDisablePrimary: false
    property string overviewZoom: ""
    property string overviewBackdrop: ""

    spacing: Style.marginM

    // ---- settings table: one row per option, drives read / snapshot / dirty / save ----
    // root: null = top-level node, otherwise the owning top-level block.
    // kind: flag (bare node) | str | int | float | path (screenshot-path, accepts bare `null`)
    readonly property var settingDefs: [
        { prop: "preferNoCsd", root: null, name: "prefer-no-csd", kind: "flag" },
        { prop: "screenshotPath", root: null, name: "screenshot-path", kind: "path" },
        { prop: "cursorTheme", root: "cursor", name: "xcursor-theme", kind: "str" },
        { prop: "cursorSize", root: "cursor", name: "xcursor-size", kind: "int" },
        { prop: "cursorHideTyping", root: "cursor", name: "hide-when-typing", kind: "flag" },
        { prop: "cursorHideMs", root: "cursor", name: "hide-after-inactive-ms", kind: "int" },
        { prop: "hkSkipStartup", root: "hotkey-overlay", name: "skip-at-startup", kind: "flag" },
        { prop: "hkHideNotBound", root: "hotkey-overlay", name: "hide-not-bound", kind: "flag" },
        { prop: "clipDisablePrimary", root: "clipboard", name: "disable-primary", kind: "flag" },
        { prop: "overviewZoom", root: "overview", name: "zoom", kind: "float" },
        { prop: "overviewBackdrop", root: "overview", name: "backdrop-color", kind: "str" }
    ]

    // ---- read (one parse per recompute) ----
    function topOf(doc, name) {
        for (var i = 0; i < doc.nodes.length; i++) if (doc.nodes[i].name === name) return doc.nodes[i];
        return null;
    }
    function readSetting(doc, d) {
        var n = d.root === null ? topOf(doc, d.name) : Kdl.childNamed(topOf(doc, d.root), d.name);
        if (d.kind === "flag") return !!n;
        if (d.kind === "path") return (n && n.args[0]) ? (n.args[0].value === null ? "null" : String(n.args[0].value)) : "";
        return (n && n.args[0]) ? String(n.args[0].value) : "";
    }

    function recompute() {
        if (!(configModel && configModel.loaded)) return;
        var ow = configModel.allOwners(["prefer-no-csd", "screenshot-path", "cursor", "hotkey-overlay", "clipboard", "overview", "environment"]);
        // no loaded file owns these: write to the main config, the only file guaranteed
        // to be part of the include graph (a fresh side file would never be read by niri).
        miscFile = ow.length ? ow[0].path : configModel.mainPath;
        var doc = Kdl.parse(configModel.textOf(miscFile));
        var defs = settingDefs;
        for (var i = 0; i < defs.length; i++) root[defs[i].prop] = readSetting(doc, defs[i]);
        orig = snapshot();
    }
    function snapshot() {
        var s = {}, defs = settingDefs;
        for (var i = 0; i < defs.length; i++) s[defs[i].prop] = root[defs[i].prop];
        return s;
    }

    Component.onCompleted: recompute()
    Connections { target: root.configModel; function onConfigChanged() { root.recompute(); } }

    readonly property bool dirty: {
        if (!orig) return false;
        var s = snapshot();
        for (var k in s) if (s[k] !== orig[k]) return true;
        return false;
    }

    // ---- write (one parse per top-level node, one batched pass per block) ----
    function writeTop(text, name, line) {
        var ex = topOf(Kdl.parse(text), name);
        if (line === null) return ex ? Kdl.removeNodeLine(text, ex) : text;
        if (ex) return Kdl.replaceNodeLine(text, ex, Kdl.leadingIndent(text, ex.range) + line);
        return Kdl.appendNode(text, line);
    }
    // The finished source line for a setting, or null when it must be removed.
    function settingLine(d, v) {
        if (d.kind === "flag") return v ? d.name : null;
        if (d.kind === "path") return v === "" ? null : (v === "null" ? (d.name + " null") : (d.name + ' "' + v + '"'));
        if (d.kind === "int") return (v === "" || isNaN(parseInt(v))) ? null : (d.name + " " + parseInt(v));
        if (d.kind === "float") return (v === "" || isNaN(parseFloat(v))) ? null : (d.name + " " + parseFloat(v));
        return v ? (d.name + ' "' + v + '"') : null;
    }

    // Changed settings only, in settingDefs order: consecutive children of the
    // same block collapse into one applyChildEdits call (edits in disjoint
    // regions commute, so the resulting text is the per-setting fold's).
    function save() {
        var t = configModel.textOf(miscFile), o = orig, defs = settingDefs;
        var ops = [];   // { root: null, name, line } | { root: "cursor", edits: [...] }
        for (var i = 0; i < defs.length; i++) {
            var d = defs[i], v = root[d.prop];
            if (v === o[d.prop]) continue;
            var line = settingLine(d, v);
            if (d.root === null) { ops.push({ root: null, name: d.name, line: line }); continue; }
            var last = ops.length ? ops[ops.length - 1] : null;
            if (last && last.root === d.root) last.edits.push({ path: [], name: d.name, line: line });
            else ops.push({ root: d.root, edits: [{ path: [], name: d.name, line: line }] });
        }
        for (var j = 0; j < ops.length; j++) {
            var op = ops[j];
            t = op.root === null ? writeTop(t, op.name, op.line) : Kdl.applyChildEdits(t, op.root, op.edits);
        }
        panel.requestSave(miscFile, t, panel.tr("misc.summary", "misc settings"));
    }

    // ---- UI ----
    RowLayout {
        Layout.fillWidth: true
        NText { text: panel.tr("section.misc", "Misc"); font.weight: Style.fontWeightBold; Layout.fillWidth: true }
        NButton {
            text: panel.tr("input.save", "Save changes")
            backgroundColor: Color.mPrimary; textColor: Color.mOnPrimary
            enabled: root.dirty && root.miscFile !== ""
            onClicked: root.save()
        }
    }

    NScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: scroll.availableWidth
            spacing: Style.marginM

            NText { text: panel.tr("misc.general", "General"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NToggle { Layout.fillWidth: true; label: panel.tr("misc.csd", "Prefer no client-side decorations"); checked: root.preferNoCsd; onToggled: v => root.preferNoCsd = v }
            NTextInput { Layout.fillWidth: true; label: panel.tr("misc.screenshot", "Screenshot path (or 'null' to disable)"); text: root.screenshotPath; placeholderText: "~/Pictures/Screenshots/%Y-%m-%d.png"; onTextChanged: root.screenshotPath = text }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("misc.cursor", "Cursor"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("misc.cursor-theme", "Theme"); text: root.cursorTheme; placeholderText: "default"; onTextChanged: root.cursorTheme = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("misc.cursor-size", "Size"); text: root.cursorSize; placeholderText: "24"; onTextChanged: root.cursorSize = text }
            }
            NToggle { Layout.fillWidth: true; label: panel.tr("misc.cursor-hide-typing", "Hide while typing"); checked: root.cursorHideTyping; onToggled: v => root.cursorHideTyping = v }
            NTextInput { Layout.fillWidth: true; label: panel.tr("misc.cursor-hide-ms", "Hide after inactive (ms)"); text: root.cursorHideMs; onTextChanged: root.cursorHideMs = text }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("misc.hotkey", "Hotkey overlay"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            NToggle { Layout.fillWidth: true; label: panel.tr("misc.hk-skip", "Skip at startup"); checked: root.hkSkipStartup; onToggled: v => root.hkSkipStartup = v }
            NToggle { Layout.fillWidth: true; label: panel.tr("misc.hk-hide", "Hide unbound entries"); checked: root.hkHideNotBound; onToggled: v => root.hkHideNotBound = v }

            NDivider { Layout.fillWidth: true }
            NText { text: panel.tr("misc.overview", "Overview & clipboard"); font.weight: Style.fontWeightBold; color: Color.mPrimary }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NTextInput { Layout.fillWidth: true; label: panel.tr("misc.zoom", "Overview zoom (0–0.75)"); text: root.overviewZoom; placeholderText: "0.5"; onTextChanged: root.overviewZoom = text }
                NTextInput { Layout.fillWidth: true; label: panel.tr("misc.ov-backdrop", "Overview backdrop color"); text: root.overviewBackdrop; onTextChanged: root.overviewBackdrop = text }
            }
            NToggle { Layout.fillWidth: true; label: panel.tr("misc.clip-primary", "Disable primary clipboard"); checked: root.clipDisablePrimary; onToggled: v => root.clipDisablePrimary = v }

            NText { text: panel.tr("misc.env-hint", "Environment variables and other blocks: use the Edit file button above."); color: Color.mOnSurfaceVariant; font.pointSize: Style.fontSizeXS; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        }
    }
}
